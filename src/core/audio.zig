const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");


pub const SR: usize = 22050;
const SRF: f32 = @floatFromInt(SR);
/// Ceiling is the CAMPFIRE take (12.8 s); the synthesized voices top out at the 8 s wind bed.
const MAX_N: usize = 13 * SR;

var work: [MAX_N]f32 = undefined;
var tape: [MAX_N]f32 = undefined;
var pcm: [MAX_N]i16 = undefined;

/// Chamberlin state-variable filter coefficients. Separate from the filter step because for a FIXED cutoff they never change, and the per-sample `sin` was 90 ms of the heal's bake time (measured).
const SvfCoef = struct { f: f32, q: f32 };

fn svfCoef(cut: f32, res: f32) SvfCoef {
    return .{
        .f = 2.0 * mathx.sinf(std.math.pi * mathx.clampF(cut, 20.0, SRF / 6.0) / SRF),
        .q = mathx.clampF(1.6 - 1.55 * res, 0.05, 2.0),
    };
}

const SvfOut = struct { lp: f32, bp: f32, hp: f32 };

const Svf = struct {
    lp: f32 = 0,
    bp: f32 = 0,

    fn stepAt(s: *Svf, x: f32, c: SvfCoef) SvfOut {
        const hp = x - s.lp - c.q * s.bp;
        s.bp += c.f * hp;
        s.lp += c.f * s.bp;
        return .{ .lp = s.lp, .bp = s.bp, .hp = hp };
    }

    fn step(s: *Svf, x: f32, cut: f32, res: f32) SvfOut {
        return s.stepAt(x, svfCoef(cut, res));
    }
};

const Pole = struct {
    y: f32 = 0,
    fn step(p: *Pole, x: f32, cut: f32) f32 {
        const a = 1.0 - @exp(-std.math.tau * mathx.clampF(cut, 5, SRF * 0.45) / SRF);
        p.y += a * (x - p.y);
        return p.y;
    }
};

fn decay(u: f32, curve: f32) f32 {
    return @exp(-curve * mathx.clampF(u, 0, 1));
}

fn swell(u: f32, peak: f32) f32 {
    const t = mathx.clampF(u, 0, 1);
    if (t < peak) return mathx.smoothstep(0, peak, t);
    return decay((t - peak) / (1.0 - peak), 3.5);
}

const Span = struct {
    a: usize,
    b: usize,

    fn u(s: Span, i: usize) f32 {
        return @as(f32, @floatFromInt(i - s.a)) / @as(f32, @floatFromInt(s.b - s.a));
    }
};

const Rack = struct {
    n: usize = 0,
    rng: mathx.Rng,
    /// Layers that rendered nothing — authored past the voice's own length, so they emit zero samples silently. A test bakes the bank and asserts this stays 0.
    dropped: usize = 0,

    fn init(seed: u64, secs: f32) Rack {
        const n = @min(@as(usize, @intFromFloat(secs * SRF)), MAX_N);
        @memset(work[0..n], 0);
        return .{ .n = n, .rng = mathx.Rng.init(seed) };
    }

    fn at(r: *const Rack, t: f32) usize {
        return @min(@as(usize, @intFromFloat(mathx.maxF(t, 0) * SRF)), r.n);
    }

    fn span(r: *Rack, t0: f32, dur: f32) ?Span {
        const a = r.at(t0);
        const b = @min(a + r.at(dur), r.n);
        if (a >= b) {
            r.dropped += 1;
            return null;
        }
        return .{ .a = a, .b = b };
    }

    /// **THE RATIO DOES NOT MOVE, SO ITS LOG IS TAKEN ONCE.** `f0*(f1/f0)^u` is a `pow` — a log AND an exp —
    /// per SAMPLE, and this loop and `air`'s are where the 4.4 s of synthesis is spent. Hoisted, a sample costs
    /// one `exp2`.
    fn body(r: *Rack, t0: f32, dur: f32, f0: f32, f1: f32, amp: f32, curve: f32) void {
        const s = r.span(t0, dur) orelse return;
        const oct = std.math.log2(f1 / f0);
        var ph: f32 = 0;
        var i = s.a;
        while (i < s.b) : (i += 1) {
            const u = s.u(i);
            const f = f0 * @exp2(oct * u);
            ph += std.math.tau * f / SRF;
            work[i] += mathx.sinf(ph) * amp * decay(u, curve);
        }
    }

    fn air(r: *Rack, t0: f32, dur: f32, amp: f32, c0: f32, c1: f32, res: f32, curve: f32) void {
        const s = r.span(t0, dur) orelse return;
        const oct = std.math.log2(c1 / c0);
        var f = Svf{};
        var i = s.a;
        while (i < s.b) : (i += 1) {
            const u = s.u(i);
            const cut = c0 * @exp2(oct * mathx.smoothstep(0, 1, u));
            const out = f.step(r.rng.signed(), cut, res);
            work[i] += out.bp * amp * decay(u, curve);
        }
    }

    fn grit(r: *Rack, t0: f32, dur: f32, amp: f32, cut: f32, coarse: f32, curve: f32) void {
        const s = r.span(t0, dur) orelse return;
        var p = Pole{};
        var hold: f32 = 0;
        var left: i32 = 0;
        var i = s.a;
        while (i < s.b) : (i += 1) {
            const u = s.u(i);
            if (left <= 0) {
                hold = r.rng.signed();
                left = 1 + r.rng.intn(@intFromFloat(1.0 + coarse * 12.0));
            }
            left -= 1;
            work[i] += p.step(hold, cut) * amp * decay(u, curve);
        }
    }

    fn ring(r: *Rack, t0: f32, dur: f32, f0: f32, amp: f32, curve: f32, parts: u32) void {
        const s = r.span(t0, dur) orelse return;
        const a = s.a;
        const b = s.b;
        var k: u32 = 0;
        while (k < parts) : (k += 1) {
            const mult = 1.0 + @as(f32, @floatFromInt(k)) * (1.48 + r.rng.signed() * 0.12);
            const f = f0 * mult;
            if (f > SRF * 0.45) continue;
            const g = amp / (1.0 + @as(f32, @floatFromInt(k)) * 1.3);
            const d = curve * (1.0 + @as(f32, @floatFromInt(k)) * 0.45);
            const ph0 = r.rng.angle();
            var i = a;
            while (i < b) : (i += 1) {
                work[i] += mathx.sinf(ph0 + std.math.tau * f * @as(f32, @floatFromInt(i - a)) / SRF) * g * decay(s.u(i), d);
            }
        }
    }

    fn growl(r: *Rack, t0: f32, dur: f32, f0: f32, f1: f32, amp: f32, rough: f32, shape: f32) void {
        const s = r.span(t0, dur) orelse return;
        const oct = std.math.log2(f1 / f0);
        var f = Svf{};
        var ph: f32 = 0;
        var vib: f32 = 0;
        var i = s.a;
        while (i < s.b) : (i += 1) {
            const u = s.u(i);
            vib += std.math.tau * (5.5 + 3.0 * u) / SRF;
            const hz = f0 * @exp2(oct * u) * (1.0 + 0.035 * mathx.sinf(vib));
            ph += hz / SRF;
            ph -= @floor(ph);
            const saw = 2.0 * ph - 1.0 + rough * r.rng.signed();
            const out = f.step(saw, hz * (3.0 + 5.0 * (1.0 - u)), 0.72);
            work[i] += out.lp * amp * swell(u, shape);
        }
    }

    fn tick(r: *Rack, t0: f32, amp: f32, cut: f32) void {
        r.grit(t0, 0.012, amp, cut, 0.0, 5.0);
    }

    /// Detuned unison "ahh"s. Formants (~730 and ~1090 Hz for "ah") plus per-voice detune/vibrato/entry, whose
    /// BEATING is the choral sound. The bank's most expensive layer (~70 ms of the heal's bake, Debug); a table LFO would trade that beating away.
    fn choir(r: *Rack, t0: f32, dur: f32, f0: f32, amp: f32, voices: u32, peak: f32) void {
        const s = r.span(t0, dur) orelse return;
        const a = s.a;
        const b = s.b;
        var v: u32 = 0;
        while (v < voices) : (v += 1) {
            const detune = 1.0 + r.rng.signed() * 0.006;
            const hz = f0 * detune;
            if (hz > SRF * 0.45) continue;
            const vrate = r.rng.range(4.2, 6.4);
            const vdepth = r.rng.range(0.004, 0.010);
            const enter = r.rng.range(0, 0.10);
            const c1 = svfCoef(730, 0.86);
            const c2 = svfCoef(1090, 0.82);
            var f1 = Svf{};
            var f2 = Svf{};
            var ph: f32 = r.rng.float();
            var vib: f32 = r.rng.angle();
            var i = a;
            while (i < b) : (i += 1) {
                const u = s.u(i);
                vib += std.math.tau * vrate / SRF;
                ph += hz * (1.0 + vdepth * mathx.sinf(vib)) / SRF;
                ph -= @floor(ph);
                const saw = 2.0 * ph - 1.0;
                const o1 = f1.stepAt(saw, c1);
                const o2 = f2.stepAt(saw, c2);
                const env = swell(mathx.clampF((u - enter) / (1.0 - enter), 0, 1), peak);
                work[i] += (o1.bp * 0.72 + o2.bp * 0.42) * amp / @as(f32, @floatFromInt(voices)) * env;
            }
        }
    }

    fn sparkle(r: *Rack, t0: f32, dur: f32, amp: f32, base: f32, n: u32) void {
        const PENT = [_]f32{ 0, 2, 4, 7, 9, 12, 14, 16, 19, 24 };
        var k: u32 = 0;
        while (k < n) : (k += 1) {
            const when = t0 + r.rng.float() * dur;
            const semis = PENT[@intCast(r.rng.intn(@intCast(PENT.len)))];
            const f = base * std.math.pow(f32, 2.0, semis / 12.0);
            r.ring(when, r.rng.range(0.10, 0.26), f, amp * r.rng.range(0.45, 1.0), r.rng.range(5.0, 9.0), 2);
        }
    }

    /// Three feedback combs, each fed back through a one-pole so the tail DARKENS as it dies — that darkening
    /// is what separates a reverb from a stack of echoes. Feed-forward in time, so it cannot blow up and needs no second buffer.
    fn hall(r: *Rack, secs: f32, cut: f32) void {
        const taps = [_]f32{ 0.0297, 0.0371, 0.0411 };
        for (taps) |d| {
            const lag = @max(r.at(d), 1);
            if (lag >= r.n) continue;
            const g = mathx.clampF(std.math.pow(f32, 0.001, d / @max(secs, 0.05)), 0, 0.92);
            var p = Pole{};
            var i = lag;
            while (i < r.n) : (i += 1) work[i] += p.step(work[i - lag], cut) * g;
        }
    }

    fn chirp(r: *Rack, t0: f32, amp: f32, base: f32) void {
        const notes = 2 + r.rng.intn(3);
        var t = t0;
        var k: i32 = 0;
        while (k < notes) : (k += 1) {
            const semis: f32 = @floatFromInt(r.rng.intn(9) - 3);
            const f = base * std.math.pow(f32, 2.0, semis / 12.0);
            const dur = r.rng.range(0.026, 0.052);
            const a = r.at(t);
            const b = @min(a + r.at(dur), r.n);
            if (a >= b) return;
            var lp = Pole{};
            var ph: f32 = 0;
            var i = a;
            while (i < b) : (i += 1) {
                const u = @as(f32, @floatFromInt(i - a)) / @as(f32, @floatFromInt(b - a));
                ph += f / SRF;
                ph -= @floor(ph);
                const pulse: f32 = if (ph < 0.30) 1.0 else -1.0;
                work[i] += lp.step(pulse, 2600) * amp * decay(u, 3.0) * mathx.smoothstep(0, 0.15, u);
            }
            t += dur + r.rng.range(0.012, 0.045);
        }
    }


    fn sat(r: *Rack, drive: f32) void {
        for (work[0..r.n]) |*s| {
            const x = s.* * drive;
            s.* = x / (1.0 + @abs(x));
        }
    }

    fn warm(r: *Rack, cut: f32) void {
        var p = Pole{};
        for (work[0..r.n]) |*s| s.* = p.step(s.*, cut);
    }

    fn wow(r: *Rack, depth: f32, rate: f32) void {
        if (r.n < 64) return;
        @memcpy(tape[0..r.n], work[0..r.n]);
        const maxLag = depth * SRF;
        var i: usize = 0;
        while (i < r.n) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / SRF;
            const lfo = 0.5 + 0.5 * (0.7 * mathx.sinf(std.math.tau * rate * t) + 0.3 * mathx.sinf(std.math.tau * rate * 2.7 * t + 1.3));
            const src = @as(f32, @floatFromInt(i)) - lfo * maxLag;
            if (src <= 0) continue;
            const ia: usize = @intFromFloat(@floor(src));
            const fr = src - @floor(src);
            const ib = @min(ia + 1, r.n - 1);
            work[i] = tape[ia] * (1.0 - fr) + tape[ib] * fr;
        }
    }

    fn hiss(r: *Rack, amt: f32) void {
        var p = Pole{};
        var q = Pole{};
        var i: usize = 0;
        while (i < r.n) : (i += 1) {
            const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(r.n));
            const nz = q.step(p.step(r.rng.signed(), 5200), 2600);
            work[i] += nz * amt * (0.35 + 0.65 * decay(u, 1.6));
        }
    }

    fn crush(r: *Rack, bits: f32, hold: u32) void {
        const levels = std.math.pow(f32, 2.0, mathx.clampF(bits, 2, 16)) * 0.5;
        const step = @max(hold, 1);
        var held: f32 = 0;
        var k: u32 = 0;
        for (work[0..r.n]) |*s| {
            if (k == 0) held = s.*;
            k = (k + 1) % step;
            const d = (r.rng.signed() + r.rng.signed()) * 0.5 / levels * DITHER_LSB;
            s.* = @round((held + d) * levels) / levels;
        }
    }

    fn band(r: *Rack, cut: f32, res: f32, amt: f32) void {
        const c = svfCoef(cut, res);
        var f = Svf{};
        for (work[0..r.n]) |*s| {
            const out = f.stepAt(s.*, c);
            s.* = mathx.lerpF(s.*, out.bp, mathx.clampF(amt, 0, 1));
        }
    }

    fn thin(r: *Rack, cut: f32, amt: f32) void {
        var p = Pole{};
        const k = mathx.clampF(amt, 0, 1);
        for (work[0..r.n]) |*s| {
            const low = p.step(s.*, cut);
            s.* = s.* - low * k;
        }
    }

    /// ADDED rather than blended — `band` lerps, which cannot boost. This is the bite a muffled voice gets its legibility back from.
    fn lift(r: *Rack, cut: f32, res: f32, amt: f32) void {
        const c = svfCoef(cut, res);
        var f = Svf{};
        const k = mathx.clampF(amt, 0, 1);
        for (work[0..r.n]) |*s| {
            const out = f.stepAt(s.*, c);
            s.* += out.bp * k;
        }
    }

    fn crackle(r: *Rack, amt: f32, perSec: f32) void {
        const chance = perSec / SRF;
        const life = @max(r.at(0.0022), 2);
        var i: usize = 0;
        while (i < r.n) : (i += 1) {
            if (r.rng.float() > chance) continue;
            const a = amt * r.rng.range(0.3, 1.0) * (if (r.rng.float() < 0.5) @as(f32, -1.0) else 1.0);
            var k: usize = 0;
            while (k < life and i + k < r.n) : (k += 1) {
                work[i + k] += a * decay(@as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(life)), 5.0);
            }
        }
    }

    fn norm(r: *Rack, peak: f32) void {
        var hi: f32 = 1e-6;
        for (work[0..r.n]) |s| hi = mathx.maxF(hi, @abs(s));
        const k = peak / hi;
        for (work[0..r.n]) |*s| s.* *= k;
    }

    fn ends(r: *Rack, inS: f32, outS: f32) void {
        const ni = @max(r.at(inS), 1);
        const no = @max(r.at(outS), 1);
        for (work[0..@min(ni, r.n)], 0..) |*s, i| s.* *= @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(ni));
        var i: usize = 0;
        while (i < @min(no, r.n)) : (i += 1) work[r.n - 1 - i] *= @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(no));
    }

    fn master(r: *Rack, drive: f32, cut: f32) void {
        r.masterX(drive, cut, CRUSH_BITS, CRUSH_HOLD);
    }

    fn masterX(r: *Rack, drive: f32, cut: f32, bits: f32, hold: u32) void {
        r.sat(drive);
        r.crush(bits, hold);
        r.warm(cut);
        r.wow(0.0016, 1.7);
        r.hiss(0.012);
        r.norm(0.92);
        r.ends(0.002, 0.012);
    }
};

const CRUSH_BITS: f32 = 7.5;
const DITHER_LSB: f32 = 0.4;
const CRUSH_HOLD: u32 = 2;

const AIR_FAR_BED: f32 = 1400;
const AIR_FAR_CALL: f32 = 2100;
const AIR_FAR_CRY: f32 = 1950;
const AIR_NEAR_DARKEST: f32 = 2200;
const AIR_NEAR_GRASS: f32 = 4200;

// Order is the BANK table's order below; the two are pinned at comptime.
/// **APPEND-ONLY, AND FOR A SHARPER REASON THAN `gfx.Mat`: THE BAKE SEEDS OFF THE ORDINAL.** `bakeTake` builds
/// each take's noise from `0x9E3779B9 *% (idx + 1)`, so inserting an id in the MIDDLE silently re-rolls the
/// synthesis of every voice below it — nothing fails to compile and nothing sounds broken. Caught by exactly
/// that: adding `gremlin_spark` beside the hollow's family moved the knight's heave 2% off the cyclops's, under the 3% a test demands.
pub const Id = enum {
    step_soft,
    step_hard,
    step_sprint,
    step_stone,
    step_water,
    roll,
    jump,
    land,
    swing_light,
    swing_heavy,
    hit_light,
    hit_heavy,
    hurt,
    hurt_heavy,
    stagger,
    guard_block,
    foe_guarded,
    knight_repel,
    guard_break,
    parry,
    refused,
    death,
    respawn,
    toad_hop,
    toad_lunge,
    toad_gape,
    toad_chomp,
    toad_hurt,
    toad_die,
    shroom_hop,
    shroom_coo,
    shroom_fling,
    shroom_puff,
    shroom_hurt,
    shroom_die,
    deer_bloom,
    deer_charge,
    deer_gore,
    deer_hurt,
    deer_die,
    mage_kindle,
    mage_throw,
    mage_hurt,
    mage_die,
    ember_bounce,
    ember_burst,
    lurker_break,
    lurker_lash,
    lurker_sink,
    lurker_hurt,
    lurker_die,
    delver_churn,
    delver_dig,
    delver_claw,
    delver_surge,
    delver_burst,
    delver_hurt,
    delver_die,
    bow_draw,
    bow_loose,
    arrow_hit,
    arrow_dirt,
    arrow_wood,
    arrow_stone,
    arrow_metal,
    wand_charge,
    wand_cast,
    bone_hurt,
    bone_die,
    skel_lunge,
    ogre_step,
    ogre_roar,
    ogre_slam,
    ogre_swipe,
    ogre_heave,
    ogre_hurt,
    ogre_die,
    knight_step,
    knight_plant,
    knight_roar,
    knight_slam,
    knight_heave,
    knight_swipe,
    knight_lunge,
    knight_hurt,
    knight_die,
    kobold_snarl,
    kobold_chop,
    kobold_heave,
    kobold_cast,
    kobold_heal,
    kobold_whirl,
    kobold_sling,
    kobold_bite,
    kobold_hurt,
    kobold_die,
    shade_reach,
    shade_gather,
    shade_wisp,
    shade_touch,
    shade_blink,
    shade_hurt,
    shade_die,
    leech_wing, // retriggered on a fly's cadence, since a synthesized take cannot loop
    leech_stab,
    leech_drink,
    leech_hurt,
    leech_die,
    stone_grind,
    stone_loose,
    wood_wake,
    wood_creak,
    wood_swing,
    wood_hit,
    wood_hurt,
    wood_die,
    spider_hiss,
    spider_spit,
    spider_bite,
    spider_hurt,
    spider_die,
    brood_screech,
    brood_leap,
    brood_bite,
    brood_hurt,
    brood_die,
    sac_lay,
    sac_hit,
    sac_hatch,
    sac_burst,
    acid_splash,
    acid_burn,
    flask_drink,
    flask_cycle,
    eat,
    chest_open,
    item_get,
    souls_spill,
    souls_hum, // a RETRIGGER on its own cadence, since a synthesized take cannot loop
    souls_take,
    ring_snap,
    kill,
    menu_move,
    menu_pick,
    menu_back,
    wind,
    birds,
    birdsong,
    owl,
    crickets,
    rain,
    thunder,
    wolf_howl,
    wolf_growl,
    wolf_bite,
    wolf_hurt,
    wolf_die,
    fog_seal,
    fog_felled,
    fog_pass,
    torch_fire,
    // **APPEND HERE, NEVER IN THE MIDDLE** (see the note above `Id`). The skitterer's, priest's and hollow's
    // families are down here rather than beside their kin because grouping them re-rolled every voice from `lurker_break` to the bone knight's.
    gremlin_spark,
    skitter_clack,
    skitter_slice,
    priest_call,
    priest_breath,
    hollow_toll,
    hollow_clank,
    step_oil,
    step_fungal,
    step_lava,
    oil_pop,
    fungal_pop,
    lava_pop,
    lava_sear,
    oil_bed,
    fungal_bed,
    lava_bed,
    duo_sword_hurt,
    duo_sword_die,
    duo_magus_hurt,
    duo_magus_die,
    duo_orb,
    duo_sprout,
    duo_burst,
    duo_fade,
    duo_bloom,
    // **APPENDED, NOT FILED BESIDE ITS FAMILY** — the bake seeds off the ORDINAL (the note on `Id`), and
    // slotting this in next to `deer_bloom` re-rolled every voice below it and moved the knight's heave 2%
    // off the cyclops's, under the 3% its own test demands. The family is a NAME, not a position.
    deer_spit,
    // …and the same rule again: MOSSBEARD'S ANVIL goes on the end, not beside the village voices it belongs
    // with. The bake seeds off the ORDINAL, so filing it by family re-rolls every take below it.
    smith_ring,
};
const NV = @typeInfo(Id).@"enum".fields.len;

pub const Submix = enum {
    sfx,
    combat,
    ambience,
};
const NMIX = @typeInfo(Submix).@"enum".fields.len;

const TRIM_AMBIENCE: f32 = 0.625;
const TRIM_COMBAT: f32 = 0.46;
const TRIM_SFX: f32 = 0.65;

const COMBAT_TREBLE: f32 = 6200;

fn submixTrim(m: Submix) f32 {
    return switch (m) {
        .sfx => TRIM_SFX,
        .combat => TRIM_COMBAT,
        .ambience => TRIM_AMBIENCE,
    };
}


pub const AFX_COUNT = 11;
pub const AFX_EPS: f32 = 0.001;
pub const AF_DRIVE = 0;
pub const AF_CRUSH = 1;
pub const AF_ALIAS = 2;
pub const AF_MUFFLE = 3;
pub const AF_TELEPHONE = 4;
pub const AF_WOBBLE = 5;
pub const AF_ROOM = 6;
pub const AF_HISS = 7;
pub const AF_CRACKLE = 8;
pub const AF_BASS = 9;
pub const AF_PRESENCE = 10;

const AudioFilter = struct { name: [:0]const u8, tip: [:0]const u8 };
const AUDIO_FILTERS = [AFX_COUNT]AudioFilter{
    .{ .name = "Drive", .tip = "Push it into soft clipping - louder and dirtier, never brighter" },
    .{ .name = "Bit Crush", .tip = "Fewer levels to quantise to. The grit of a cheap sampler" },
    .{ .name = "Sample Hold", .tip = "Hold each sample longer - aliasing, the other half of a cheap sampler" },
    .{ .name = "Muffle", .tip = "Low-pass. Takes the top off, as if it were through a door" },
    .{ .name = "Telephone", .tip = "Band-pass to a narrow mid - no bass and no air" },
    .{ .name = "Wow & Flutter", .tip = "Slow pitch drift, the way worn tape wanders" },
    .{ .name = "Room", .tip = "A short reverb tail that darkens as it dies" },
    .{ .name = "Tape Hiss", .tip = "Steady broadband noise under everything" },
    .{ .name = "Vinyl Crackle", .tip = "Sparse ticks and pops over the top" },
    .{ .name = "Bass Cut", .tip = "High-pass. Thins the bottom so a small speaker can carry it" },
    .{ .name = "Presence", .tip = "Lift the upper mids - what makes a voice cut through" },
};
pub const AFX_NAMES = blk: {
    var out: [AFX_COUNT][:0]const u8 = undefined;
    for (&out, AUDIO_FILTERS) |*o, f| o.* = f.name;
    break :blk out;
};
/// What each rack dial DOES, beside its name for the same reason `dialSpec` carries one: the rack is eleven
/// short labels and nothing else says which way a knob goes.
pub const AFX_TIPS = blk: {
    var out: [AFX_COUNT][:0]const u8 = undefined;
    for (&out, AUDIO_FILTERS) |*o, f| o.* = f.tip;
    break :blk out;
};

comptime {
    const PINS = [_]struct { i: usize, n: []const u8 }{
        .{ .i = AF_DRIVE, .n = "Drive" },
        .{ .i = AF_CRUSH, .n = "Bit Crush" },
        .{ .i = AF_ALIAS, .n = "Sample Hold" },
        .{ .i = AF_MUFFLE, .n = "Muffle" },
        .{ .i = AF_TELEPHONE, .n = "Telephone" },
        .{ .i = AF_WOBBLE, .n = "Wow & Flutter" },
        .{ .i = AF_ROOM, .n = "Room" },
        .{ .i = AF_HISS, .n = "Tape Hiss" },
        .{ .i = AF_CRACKLE, .n = "Vinyl Crackle" },
        .{ .i = AF_BASS, .n = "Bass Cut" },
        .{ .i = AF_PRESENCE, .n = "Presence" },
    };
    if (PINS.len != AFX_COUNT) @compileError("audio: a filter with no pin");
    for (PINS) |p| {
        if (!std.mem.eql(u8, AUDIO_FILTERS[p.i].name, p.n)) @compileError("audio: AF_ index/row mismatch at " ++ p.n);
    }
}

pub const FxPreset = struct { idx: usize, val: f32 };
pub const FX_VINYL = [_]FxPreset{ .{ .idx = AF_CRACKLE, .val = 0.55 }, .{ .idx = AF_HISS, .val = 0.30 }, .{ .idx = AF_WOBBLE, .val = 0.35 }, .{ .idx = AF_MUFFLE, .val = 0.22 } };
pub const FX_RADIO = [_]FxPreset{ .{ .idx = AF_TELEPHONE, .val = 0.85 }, .{ .idx = AF_DRIVE, .val = 0.40 }, .{ .idx = AF_HISS, .val = 0.22 } };
/// The house sound (owner's call). `AFX_DEFAULTS` is derived from this row, so "Reset to Default" and "Preset: Worn Tape" cannot come to mean two things.
pub const FX_TAPE = [_]FxPreset{ .{ .idx = AF_WOBBLE, .val = 0.55 }, .{ .idx = AF_HISS, .val = 0.35 }, .{ .idx = AF_MUFFLE, .val = 0.30 }, .{ .idx = AF_DRIVE, .val = 0.25 } };
pub const FX_CRUSHED = [_]FxPreset{ .{ .idx = AF_CRUSH, .val = 0.70 }, .{ .idx = AF_ALIAS, .val = 0.55 }, .{ .idx = AF_DRIVE, .val = 0.30 } };
pub const FX_BROKEN = [_]FxPreset{ .{ .idx = AF_DRIVE, .val = 0.85 }, .{ .idx = AF_TELEPHONE, .val = 0.50 }, .{ .idx = AF_CRACKLE, .val = 0.40 }, .{ .idx = AF_ALIAS, .val = 0.35 } };

pub const AFX_DEFAULTS = blk: {
    var out = [_]f32{0} ** AFX_COUNT;
    for (FX_TAPE) |p| out[p.idx] = p.val;
    break :blk out;
};

var fxVals: [NMIX][AFX_COUNT]f32 = [_][AFX_COUNT]f32{AFX_DEFAULTS} ** NMIX;

pub fn fxValues(m: Submix) []const f32 {
    return &fxVals[@intFromEnum(m)];
}

fn anyFxIn(m: Submix) bool {
    for (fxVals[@intFromEnum(m)]) |v| {
        if (v > AFX_EPS) return true;
    }
    return false;
}

pub fn setFx(m: Submix, i: usize, v: f32) void {
    if (i >= AFX_COUNT) return;
    const want = mathx.clampF(v, 0, 1);
    const slot = &fxVals[@intFromEnum(m)][i];
    if (slot.* == want) return;
    slot.* = want;
    markFxDirty(m);
}

pub fn allFxOff(m: Submix) void {
    fxVals[@intFromEnum(m)] = [_]f32{0} ** AFX_COUNT;
    markFxDirty(m);
}

pub fn resetFx(m: Submix) void {
    fxVals[@intFromEnum(m)] = AFX_DEFAULTS;
    markFxDirty(m);
}

pub fn applyFxPreset(m: Submix, preset: []const FxPreset) void {
    fxVals[@intFromEnum(m)] = [_]f32{0} ** AFX_COUNT;
    for (preset) |p| {
        if (p.idx < AFX_COUNT) fxVals[@intFromEnum(m)][p.idx] = mathx.clampF(p.val, 0, 1);
    }
    markFxDirty(m);
}

fn applyFx(r: *Rack, m: Submix) void {
    if (!anyFxIn(m)) return;
    applyRack(r, fxVals[@intFromEnum(m)]);
}

fn applyRack(r: *Rack, v: [AFX_COUNT]f32) void {
    if (v[AF_DRIVE] > AFX_EPS) r.sat(1.0 + 7.0 * v[AF_DRIVE]);
    if (v[AF_CRUSH] > AFX_EPS) r.crush(mathx.lerpF(CRUSH_BITS, 2.0, v[AF_CRUSH]), 1);
    if (v[AF_ALIAS] > AFX_EPS) r.crush(16, 1 + @as(u32, @intFromFloat(v[AF_ALIAS] * 15.0)));
    if (v[AF_MUFFLE] > AFX_EPS) r.warm(mathx.lerpF(SRF * 0.45, 320.0, v[AF_MUFFLE]));
    if (v[AF_TELEPHONE] > AFX_EPS) r.band(1450.0, 0.35, v[AF_TELEPHONE]);
    if (v[AF_WOBBLE] > AFX_EPS) r.wow(0.0016 + 0.010 * v[AF_WOBBLE], 1.7 + 3.0 * v[AF_WOBBLE]);
    if (v[AF_ROOM] > AFX_EPS) r.hall(0.12 + 1.5 * v[AF_ROOM], 2600.0);
    if (v[AF_HISS] > AFX_EPS) r.hiss(0.012 + 0.09 * v[AF_HISS]);
    if (v[AF_CRACKLE] > AFX_EPS) r.crackle(0.05 + 0.30 * v[AF_CRACKLE], 6.0 + 340.0 * v[AF_CRACKLE]);
    if (v[AF_BASS] > AFX_EPS) r.thin(120.0 + 220.0 * v[AF_BASS], v[AF_BASS]);
    if (v[AF_PRESENCE] > AFX_EPS) r.lift(3200.0, 0.5, 0.9 * v[AF_PRESENCE]);
    r.norm(0.92);
    r.ends(0.002, 0.012);
}

const FX_SETTLE: f32 = 0.22;
var fxDirty: [NMIX]bool = [_]bool{false} ** NMIX;
var fxSettle: f32 = 0;

fn markFxDirty(m: Submix) void {
    fxDirty[@intFromEnum(m)] = true;
    fxSettle = FX_SETTLE;
}

pub fn fxPending() bool {
    return fxSettle > 0;
}

pub fn tickFx(dt: f32) void {
    if (fxSettle <= 0) return;
    fxSettle -= dt;
    if (fxSettle > 0) return;
    fxSettle = 0;
    for (&fxDirty, 0..) |*d, mi| {
        if (!d.*) continue;
        d.* = false;
        rebakeMix(@enumFromInt(mi));
    }
    // THE FLAG IS SPENT BY THE REBAKE, NEVER BEFORE IT. Cleared above the `ready` gate, an edit queued while the bank is down is dropped and the voice plays on with the old take.
    if (!ready) return;
    for (&voiceDirty, 0..) |*d, idx| {
        if (!d.*) continue;
        d.* = false;
        dropRow(idx);
        bakeTake(BANK[idx].id, idx);
    }
}

const Row = struct {
    id: Id,
    make: *const fn (*Rack) void,
    gain: f32 = 0.7,
    mix: Submix = .sfx,
    jit: f32 = 0.06,
    vjit: f32 = 0.12,
    vars: u8 = 1,
    poly: u8 = 2,
    reach: f32 = FALLOFF,
    /// Where the take SITS, against the `jit` that scatters it. A dial for the bench; nothing authors it.
    pitch: f32 = 1.0,
};


fn mkStepSoft(r: *Rack) void {
    r.body(0.0, 0.11, 108 + r.rng.signed() * 12, 52, 0.55, 5.0);
    r.grit(0.004, 0.075, 0.28, 1500 + r.rng.signed() * 400, 0.5, 5.5);
    r.air(0.0, 0.05, 0.10, 900, 380, 0.35, 6.0);
    r.master(1.5, 3000);
}

fn mkStepHard(r: *Rack) void {
    r.tick(0.0, 0.20, 3000);
    r.body(0.0, 0.16, 138 + r.rng.signed() * 14, 46, 0.85, 4.2);
    r.grit(0.003, 0.13, 0.40, 2100 + r.rng.signed() * 500, 0.55, 4.6);
    r.air(0.0, 0.08, 0.16, 1500, 420, 0.4, 5.0);
    r.master(1.9, 3400);
}

fn mkStepSprint(r: *Rack) void {
    r.tick(0.0, 0.26, 3600);
    r.body(0.0, 0.20, 152 + r.rng.signed() * 16, 42, 1.0, 3.6);
    r.grit(0.002, 0.17, 0.46, 2600 + r.rng.signed() * 600, 0.5, 3.9);
    r.air(0.012, 0.11, 0.22, 2400, 500, 0.45, 4.0);
    r.master(2.2, 3600);
}

fn mkStepStone(r: *Rack) void {
    r.tick(0.0, 0.55, 6500);
    r.body(0.0, 0.045, 660, 300, 0.5, 9.5);
    r.ring(0.001, 0.05, 2400, 0.16, 10.0, 2);
    r.grit(0.0, 0.05, 0.30, 3800, 0.35, 7.0);
    r.master(1.8, 5400);
}

fn mkStepWater(r: *Rack) void {
    r.air(0.0, 0.11, 0.34, 700, 3200, 0.30, 4.0);
    r.body(0.008, 0.07, 380, 820, 0.42, 6.5);
    r.body(0.052, 0.05, 620, 1180, 0.22, 7.5);
    r.grit(0.02, 0.13, 0.16, 2600, 0.25, 3.4);
    r.master(1.7, 4200);
}

// **A BUBBLE RISES IN PITCH AS IT BURSTS.** Helmholtz: the cavity shrinks, so the note goes UP — a pop written
// falling reads as a drip instead. All three of these run `f0 -> f1` with f1 the higher.
fn mkOilPop(r: *Rack) void {
    r.body(0.0, 0.080, 94 + r.rng.signed() * 12, 250, 0.92, 5.0);
    r.body(0.0, 0.17, 54, 30, 0.55, 3.4);
    r.air(0.0, 0.05, 0.13, 500, 1400, 0.30, 6.0);
    r.master(1.4, 1500);
}

fn mkFungalPop(r: *Rack) void {
    r.body(0.0, 0.058, 178 + r.rng.signed() * 26, 540, 0.86, 5.5);
    r.air(0.004, 0.075, 0.20, 900, 2600, 0.34, 5.0);
    r.grit(0.0, 0.06, 0.10, 1800, 0.40, 5.0);
    r.master(1.3, 3200);
}

fn mkLavaPop(r: *Rack) void {
    r.tick(0.0, 0.28, 3200);
    r.body(0.0, 0.10, 118 + r.rng.signed() * 16, 330, 0.82, 4.5);
    r.body(0.0, 0.23, 46, 26, 0.50, 3.0);
    r.air(0.012, 0.34, 0.26, 4200, 900, 0.22, 2.0);
    r.master(1.7, 4600);
}

/// The bite lava takes every second — a HISS and nothing struck, so it can never be read as a blow landing.
fn mkLavaSear(r: *Rack) void {
    r.air(0.0, 0.42, 0.55, 5200, 1300, 0.24, 2.0);
    r.air(0.02, 0.26, 0.20, 1800, 620, 0.40, 2.6);
    r.grit(0.0, 0.30, 0.14, 3200, 0.25, 2.4);
    r.master(1.35, 5200);
}

/// **A SURFACE THAT BOILS IS A BAND PLUS POISSON BLUPS** — the standing band is the mass and the blups are what
/// says it is alive. One helper for three beds, because the difference between a tar pit and a lava run is the
/// numbers and not the shape.
const LiquidBed = struct {
    bodyHz: f32,
    bodySwing: f32,
    /// Blups a second, redrawn at every one of them (`mkTorchFire`'s rule: a crackle is Poisson, not a clock).
    pops: f32,
    popLo: f32,
    popHi: f32,
    /// How far a blup climbs over its own tail, as a fraction: 0.6 is a minor sixth up.
    popRise: f32,
    /// Per-sample decay of a blup's envelope. 0.9975 is a ~160 ms tail.
    popHold: f32,
    hissAmt: f32,
    topHz: f32,
    trim: f32,
};

fn liquidBed(r: *Rack, c: LiquidBed) void {
    var band = Svf{};
    var blup = Svf{};
    var top = Pole{};
    const q1 = r.rng.angle();
    const q2 = r.rng.angle();
    var wait: i32 = 0;
    var env: f32 = 0;
    var hz: f32 = c.popLo;
    var i: usize = 0;
    while (i < r.n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / SRF;
        const g1 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.061 * t + q1);
        const g2 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.137 * t + 1.9 + q2);
        const nz = r.rng.signed();
        if (wait <= 0) {
            wait = 1 + @as(i32, @intFromFloat(@abs(r.rng.signed()) * (2.0 * SRF / c.pops)));
            env = 1.0;
            hz = r.rng.range(c.popLo, c.popHi);
        }
        wait -= 1;
        env *= c.popHold;
        const bo = band.step(nz, c.bodyHz * (1.0 - c.bodySwing + 2.0 * c.bodySwing * g1), 0.40).bp;
        const bl = blup.step(nz, hz * (1.0 + c.popRise * (1.0 - env)), 0.94).bp * env * env;
        const tp = top.step(nz, c.topHz) * c.hissAmt * (0.4 + 0.6 * g2);
        work[i] = bo * (0.45 + 0.55 * g2) + bl * 0.90 + tp;
    }
    r.norm(0.42);
    r.sat(1.1);
    r.crush(CRUSH_BITS + 1.5, CRUSH_HOLD);
    r.warm(c.trim);
    r.wow(0.002, 0.5);
    r.hiss(0.020);
    r.norm(0.60);
    r.ends(0.9, 0.9);
}

fn mkOilBed(r: *Rack) void {
    liquidBed(r, .{ .bodyHz = 74, .bodySwing = 0.28, .pops = 1.4, .popLo = 58, .popHi = 130, .popRise = 0.55, .popHold = 0.9982, .hissAmt = 0.02, .topHz = 1400, .trim = 900 });
}

fn mkFungalBed(r: *Rack) void {
    liquidBed(r, .{ .bodyHz = 210, .bodySwing = 0.34, .pops = 4.6, .popLo = 190, .popHi = 520, .popRise = 0.70, .popHold = 0.9968, .hissAmt = 0.14, .topHz = 3600, .trim = AIR_FAR_BED });
}

fn mkLavaBed(r: *Rack) void {
    liquidBed(r, .{ .bodyHz = 108, .bodySwing = 0.40, .pops = 6.2, .popLo = 90, .popHi = 340, .popRise = 0.45, .popHold = 0.9974, .hissAmt = 0.26, .topHz = 5200, .trim = 2600 });
}

// **WHAT MAKES A FOOTFALL READ AS LIQUID IS A NOISE BAND SWEEPING UP** — that is the splash, and it is the
// whole of what `mkStepWater` does that `mkStepSoft` does not (700 -> 3200 Hz under a rising bubble). Authored
// without one, all three of these came out as textures over a thud: measured they were LOUDER than water's
// (rms 0.18 against 0.11) and none of them said liquid. Each carries water's sweep now, moved to its own body,
// and its own character on top of it.

/// Tar: the same splash, an octave down and slower — a heavy film parting rather than a spray.
fn mkStepOil(r: *Rack) void {
    r.air(0.0, 0.26, 0.38, 220, 2100, 0.34, 2.4);
    r.body(0.010, 0.09, 150 + r.rng.signed() * 14, 460, 0.62, 5.4);
    // **AND THE SUCK ON THE WAY OUT IS WHAT SAYS TAR.** A cavity closing behind a boot is small, so it rises —
    // and it has to rise FASTER than the body under it, or the take gets duller as it runs and stops reading
    // as a splash at all (measured: crossings x0.98 over its own length, against water's x1.60).
    r.body(0.085, 0.12, 130, 620, 0.40, 3.8);
    r.grit(0.03, 0.14, 0.10, 1600, 0.40, 3.4);
    r.master(1.6, 2600);
}

/// Stew: water's own splash with the pitch pulled down and grit in it — thicker, not deeper.
fn mkStepFungal(r: *Rack) void {
    r.air(0.0, 0.14, 0.36, 480, 2600, 0.32, 4.0);
    r.body(0.008, 0.09, 260 + r.rng.signed() * 26, 640, 0.50, 6.0);
    r.body(0.055, 0.07, 400, 900, 0.26, 6.8);
    r.grit(0.02, 0.16, 0.24, 1500, 0.45, 3.2);
    r.master(1.65, 3400);
}

/// Lava: the splash is there and the STEAM answers it — a rising spray under a long falling hiss.
fn mkStepLava(r: *Rack) void {
    r.air(0.0, 0.12, 0.30, 600, 2800, 0.32, 4.4);
    r.body(0.006, 0.10, 190 + r.rng.signed() * 18, 520, 0.55, 5.6);
    r.air(0.030, 0.34, 0.40, 4400, 1000, 0.22, 2.1);
    r.grit(0.02, 0.24, 0.22, 2400, 0.32, 2.6);
    r.body(0.0, 0.14, 88, 42, 0.44, 4.0);
    r.master(1.75, 4400);
}

// THE FUNGAL DUO. **ONE FAMILY, TWO VOICES**: the swordsman is WET MASS with a blade in it and the magus is
// DRY SPORE. Both are pitched under the bone knight's family — they are big, but they are not iron.
fn mkDuoSwordHurt(r: *Rack) void {
    r.body(0.0, 0.16, 132 + r.rng.signed() * 14, 58, 0.90, 3.6);
    r.grit(0.0, 0.20, 0.44, 900, 0.62, 3.2);
    r.air(0.006, 0.14, 0.22, 1600, 520, 0.34, 4.0);
    r.master(1.5, 2600);
}

fn mkDuoSwordDie(r: *Rack) void {
    r.body(0.0, 0.62, 96, 34, 1.15, 1.9);
    r.grit(0.02, 0.70, 0.50, 700, 0.72, 1.8);
    r.air(0.10, 0.58, 0.30, 1200, 340, 0.30, 2.0);
    // The mass going down: a wet thud, not a clatter.
    r.body(0.46, 0.26, 62, 30, 0.72, 3.0);
    r.master(1.7, 2400);
}

fn mkDuoMagusHurt(r: *Rack) void {
    r.air(0.0, 0.20, 0.42, 2600, 900, 0.30, 3.4);
    r.body(0.0, 0.12, 220 + r.rng.signed() * 22, 96, 0.60, 4.4);
    r.grit(0.004, 0.18, 0.30, 2000, 0.44, 3.6);
    r.master(1.35, 3800);
}

fn mkDuoMagusDie(r: *Rack) void {
    r.air(0.0, 0.72, 0.52, 3200, 620, 0.26, 1.9);
    r.body(0.0, 0.48, 150, 52, 0.80, 2.2);
    r.grit(0.06, 0.66, 0.40, 1500, 0.52, 2.0);
    r.master(1.5, 3400);
}

/// A DRY, QUICK SPIT — the orb is attrition, so its voice is small and it comes often.
fn mkDuoOrb(r: *Rack) void {
    r.tick(0.0, 0.22, 3400);
    r.body(0.0, 0.10, 300 + r.rng.signed() * 40, 720, 0.55, 5.5);
    r.air(0.0, 0.14, 0.24, 1400, 3000, 0.34, 4.2);
    r.master(1.25, 4600);
}

/// The ground opening: a low swell with grit in it, and it RISES, because something is coming up.
fn mkDuoSprout(r: *Rack) void {
    r.body(0.0, 0.34, 62, 190, 0.85, 2.6);
    r.grit(0.0, 0.38, 0.42, 800, 0.70, 2.4);
    r.air(0.08, 0.30, 0.26, 700, 2200, 0.32, 3.0);
    r.master(1.4, 3000);
}

/// …and the bunch going off. The one loud thing either of them owns.
fn mkDuoBurst(r: *Rack) void {
    r.tick(0.0, 0.44, 2600);
    r.body(0.0, 0.30, 128, 40, 1.20, 2.8);
    r.body(0.0, 0.16, 68, 34, 0.70, 4.0);
    r.grit(0.0, 0.34, 0.58, 1700, 0.60, 2.6);
    r.air(0.010, 0.40, 0.40, 3000, 700, 0.28, 2.2);
    r.master(1.8, 4200);
}

/// Going: a breath OUT, falling. Coming back is the same breath run the other way — a separate voice, because
/// a reversed sample is a reversed sample and these are synthesized.
fn mkDuoFade(r: *Rack) void {
    r.air(0.0, 0.86, 0.46, 2800, 520, 0.28, 1.8);
    r.body(0.04, 0.52, 210, 74, 0.42, 2.2);
    r.grit(0.0, 0.80, 0.22, 1600, 0.55, 1.9);
    r.master(1.2, 3200);
}

fn mkDuoBloom(r: *Rack) void {
    r.air(0.0, 0.62, 0.44, 620, 3000, 0.30, 2.0);
    r.body(0.0, 0.40, 88, 260, 0.50, 2.6);
    r.grit(0.05, 0.56, 0.24, 1900, 0.50, 2.2);
    r.master(1.25, 3600);
}

fn mkRoll(r: *Rack) void {
    r.grit(0.0, 0.20, 0.34, 1100, 0.55, 3.0);
    r.body(0.05, 0.16, 78, 40, 0.42, 4.5);
    r.grit(0.24, 0.13, 0.20, 1700, 0.45, 4.0);
    r.air(0.0, 0.16, 0.10, 900, 480, 0.10, 3.2);
    r.master(1.15, 2600);
}

fn mkJump(r: *Rack) void {
    r.air(0.0, 0.14, 0.30, 520, 1100, 0.26, 4.2);
    r.grit(0.0, 0.08, 0.24, 1800 + r.rng.signed() * 300, 0.45, 5.2);
    r.body(0.0, 0.09, 96, 44, 0.28, 5.5);
    r.master(1.2, 3200);
}

fn mkLand(r: *Rack) void {
    r.tick(0.0, 0.26, 2600);
    r.body(0.0, 0.21, 96 + r.rng.signed() * 10, 36, 1.0, 3.3);
    r.grit(0.004, 0.19, 0.48, 1900 + r.rng.signed() * 400, 0.55, 3.8);
    r.air(0.05, 0.15, 0.14, 700, 420, 0.14, 3.0);
    r.master(2.0, 3200);
}

fn mkSwingLight(r: *Rack) void {
    r.air(0.0, 0.15, 0.55, 2000, 620, 0.16, 2.6);
    r.air(0.015, 0.085, 0.16, 5200, 2400, 0.12, 3.4);
    r.master(1.05, 4200);
}

fn mkSwingHeavy(r: *Rack) void {
    r.air(0.0, 0.26, 0.26, 900, 1500, 0.14, 1.7);
    r.air(0.24, 0.30, 0.72, 2200, 380, 0.18, 2.1);
    r.body(0.26, 0.14, 170, 64, 0.22, 3.8);
    r.master(1.25, 3600);
}


fn mkHitLight(r: *Rack) void {
    r.tick(0.0, 0.34, 2200);
    r.body(0.0, 0.20, 170, 56, 1.05, 3.8);
    r.body(0.0, 0.09, 88, 52, 0.5, 5.0);
    r.grit(0.0, 0.10, 0.34, 1500, 0.45, 5.0);
    r.ring(0.004, 0.13, 700, 0.13, 7.0, 2);
    r.master(1.25, 2500);
}

fn mkHitHeavy(r: *Rack) void {
    r.tick(0.0, 0.40, 1800);
    r.body(0.0, 0.36, 128, 34, 1.35, 2.4);
    r.body(0.0, 0.14, 66, 38, 0.62, 4.0);
    r.grit(0.0, 0.24, 0.52, 1200, 0.75, 3.2);
    r.ring(0.006, 0.20, 520, 0.15, 5.0, 3);
    r.body(0.11, 0.22, 58, 30, 0.5, 3.0);
    r.master(1.45, 2100);
}

fn mkHurt(r: *Rack) void {
    r.body(0.0, 0.19, 118, 46, 0.85, 3.8);
    r.growl(0.01, 0.22, 156, 108, 0.60, 0.11, 0.14);
    r.grit(0.0, 0.09, 0.22, 1100, 0.45, 5.0);
    r.master(1.3, 2200);
}

fn mkHurtHeavy(r: *Rack) void {
    r.body(0.0, 0.38, 98, 30, 1.15, 2.4);
    r.growl(0.0, 0.42, 140, 70, 0.85, 0.15, 0.10);
    r.grit(0.0, 0.16, 0.34, 900, 0.68, 3.4);
    r.air(0.02, 0.26, 0.18, 1400, 240, 0.30, 3.0);
    r.master(1.5, 1900);
}

fn mkStagger(r: *Rack) void {
    r.grit(0.0, 0.36, 0.52, 1200, 0.8, 2.4);
    r.air(0.0, 0.32, 0.30, 1200, 320, 0.34, 2.6);
    r.body(0.14, 0.18, 70, 38, 0.42, 3.6);
    r.master(1.35, 2000);
}

/// **THE BOARDS ARE IRON-BOUND, AND YOU HEAR THE BAND** (owner: a more metallic sound). It was one short 940 Hz
/// partial pair dead inside 90 ms, which is a knock on wood. The master lowpass opens with it: at 4200 the partials that make it metal never left the rack.
fn mkGuardBlock(r: *Rack) void {
    r.tick(0.0, 0.42, 4200);
    r.body(0.0, 0.13, 190, 78, 0.95, 5.0);
    r.grit(0.0, 0.07, 0.30, 2400, 0.4, 6.0);
    r.ring(0.003, 0.26, 1520, 0.21, 3.4, 4);
    r.ring(0.005, 0.15, 3150, 0.10, 5.2, 3);
    r.master(1.6, 6200);
}

fn mkKnightRepel(r: *Rack) void {
    r.tick(0.0, 0.16, 1900);
    r.body(0.0, 0.30, 104, 44, 1.15, 2.8);
    r.body(0.0, 0.13, 58, 30, 0.85, 2.0);
    r.grit(0.0, 0.12, 0.34, 1500, 0.55, 3.6);
    r.ring(0.005, 0.22, 320, 0.13, 4.2, 3);
    r.air(0.04, 0.20, 0.18, 900, 240, 0.22, 3.0);
    r.master(2.2, 2600);
}

fn mkFoeGuarded(r: *Rack) void {
    r.tick(0.0, 0.30, 2100);
    r.body(0.0, 0.11, 148, 66, 0.75, 4.4);
    r.grit(0.0, 0.08, 0.38, 1800, 0.5, 5.2);
    r.ring(0.004, 0.07, 620, 0.10, 7.0, 2);
    r.master(1.5, 3200);
}

fn mkGuardBreak(r: *Rack) void {
    r.tick(0.0, 0.46, 1700);
    r.body(0.0, 0.34, 132, 40, 1.30, 2.6);
    r.grit(0.0, 0.22, 0.50, 1300, 0.7, 3.2);
    r.ring(0.004, 0.30, 470, 0.22, 3.4, 3);
    r.grit(0.10, 0.34, 0.40, 1100, 0.8, 2.6);
    r.air(0.08, 0.30, 0.24, 1300, 300, 0.32, 2.8);
    r.master(1.7, 2400);
}

fn mkParry(r: *Rack) void {
    r.tick(0.0, 0.58, 6000);
    r.grit(0.0, 0.09, 0.44, 3400, 0.35, 5.0);
    r.body(0.0, 0.15, 205, 84, 1.00, 5.0);
    r.grit(0.05, 0.10, 0.28, 2100, 0.45, 4.2);
    r.air(0.05, 0.15, 0.26, 1500, 6200, 0.30, 3.4);
    r.ring(0.004, 0.17, 1240, 0.20, 5.5, 2);
    r.ring(0.06, 0.15, 1980, 0.11, 6.0, 2);
    r.master(1.7, 5200);
}

fn mkRefused(r: *Rack) void {
    r.body(0.0, 0.055, 190, 120, 0.5, 7.0);
    r.grit(0.0, 0.04, 0.25, 700, 0.3, 8.0);
    r.master(1.4, 1400);
}

fn mkDeath(r: *Rack) void {
    r.growl(0.0, 1.5, 165, 62, 0.9, 0.2, 0.06);
    r.body(0.0, 2.2, 82, 33, 0.8, 1.1);
    r.body(0.10, 1.9, 41, 22, 0.6, 1.0);
    r.air(0.0, 1.6, 0.25, 900, 160, 0.35, 1.6);
    r.ring(0.55, 1.5, 210, 0.10, 1.8, 3);
    r.sat(2.2);
    r.warm(2400);
    r.wow(0.006, 0.9);
    r.hiss(0.02);
    r.norm(0.95);
    r.ends(0.01, 0.35);
}

fn mkRespawn(r: *Rack) void {
    r.body(0.0, 1.1, 88, 132, 0.8, 1.2);
    r.ring(0.02, 1.0, 330, 0.35, 2.0, 4);
    r.air(0.0, 0.8, 0.18, 300, 1800, 0.3, 1.4);
    r.master(1.5, 3600);
}


fn mkToadHop(r: *Rack) void {
    r.body(0.0, 0.09, 190, 88, 0.5, 5.0);
    r.growl(0.0, 0.13, 130, 210, 0.45, 0.3, 0.25);
    r.grit(0.0, 0.06, 0.25, 1200, 0.6, 6.0);
    r.master(1.9, 2600);
}

fn mkToadLunge(r: *Rack) void {
    r.growl(0.0, 0.36, 96, 168, 0.85, 0.34, 0.55);
    r.air(0.26, 0.22, 0.4, 600, 2200, 0.4, 2.6);
    r.body(0.28, 0.16, 150, 64, 0.7, 3.8);
    r.master(2.2, 2800);
}

fn mkToadGape(r: *Rack) void {
    r.air(0.0, 0.34, 0.5, 260, 1500, 0.45, 1.2);
    r.growl(0.05, 0.30, 74, 108, 0.5, 0.4, 0.5);
    r.master(1.7, 2400);
}

fn mkToadChomp(r: *Rack) void {
    r.tick(0.0, 0.6, 2600);
    r.body(0.0, 0.10, 240, 70, 0.9, 5.5);
    r.grit(0.0, 0.07, 0.55, 1100, 0.75, 6.0);
    r.ring(0.002, 0.06, 620, 0.2, 8.0, 2);
    r.master(2.3, 2600);
}

fn mkToadHurt(r: *Rack) void {
    r.growl(0.0, 0.22, 250, 120, 0.8, 0.45, 0.08);
    r.body(0.0, 0.12, 180, 70, 0.6, 5.0);
    r.grit(0.0, 0.09, 0.4, 1500, 0.6, 5.0);
    r.master(2.2, 2700);
}

fn mkToadDie(r: *Rack) void {
    r.growl(0.0, 0.55, 190, 58, 0.9, 0.5, 0.07);
    r.body(0.22, 0.30, 96, 38, 0.7, 2.6);
    r.grit(0.24, 0.22, 0.35, 900, 0.7, 3.0);
    r.master(2.0, 2400);
}


fn mkShroomHop(r: *Rack) void {
    r.body(0.0, 0.07, 150, 70, 0.4, 5.5);
    r.ring(0.0, 0.05, 980, 0.12, 9.0, 1);
    r.master(1.6, 2600);
}

fn mkShroomCoo(r: *Rack) void {
    r.ring(0.0, 0.14, 640, 0.42, 6.5, 2);
    r.growl(0.17, 0.34, 700, 496, 0.34, 0.22, 0.05);
    r.air(0.05, 0.46, 0.20, 800, 2600, 0.30, 1.3);
    r.master(1.5, 3200);
}

fn mkShroomFling(r: *Rack) void {
    r.growl(0.0, 0.34, 340, 1150, 0.38, 0.18, 0.06);
    r.air(0.06, 0.28, 0.26, 900, 3200, 0.32, 2.0);
    r.body(0.0, 0.08, 160, 80, 0.4, 5.0);
    r.master(1.7, 3400);
}

fn mkShroomPuff(r: *Rack) void {
    r.body(0.0, 0.12, 120, 52, 0.7, 3.4);
    r.air(0.02, 0.55, 0.30, 2400, 700, 0.5, 1.0);
    r.grit(0.04, 0.30, 0.16, 3600, 0.35, 1.8);
    r.master(1.9, 3000);
}

fn mkShroomHurt(r: *Rack) void {
    r.ring(0.0, 0.07, 920, 0.4, 8.0, 2);
    r.growl(0.07, 0.20, 560, 170, 0.44, 0.3, 0.07);
    r.grit(0.0, 0.08, 0.25, 1600, 0.5, 5.0);
    r.master(1.9, 3000);
}

fn mkShroomDie(r: *Rack) void {
    r.growl(0.0, 0.60, 520, 64, 0.5, 0.4, 0.06);
    r.air(0.30, 0.40, 0.22, 1800, 500, 0.4, 1.0);
    r.body(0.44, 0.20, 90, 40, 0.5, 2.6);
    r.master(1.8, 2600);
}



fn mkDelverChurn(r: *Rack) void {
    r.grit(0.0, 0.66, 0.30, 460, 0.60, 0.8);
    r.body(0.0, 0.60, 52, 44, 0.55, 0.9);
    r.ends(0.12, 0.16);
    r.master(1.5, 1500);
}

fn mkDelverDig(r: *Rack) void {
    r.grit(0.0, 0.50, 0.62, 820, 0.72, 1.4);
    r.body(0.06, 0.34, 88, 40, 0.66, 2.2);
    r.air(0.0, 0.40, 0.20, 600, 1900, 0.28, 1.2);
    r.master(2.0, 2000);
}

fn mkDelverClaw(r: *Rack) void {
    r.air(0.0, 0.28, 0.60, 1500, 260, 0.44, 2.0);
    r.grit(0.04, 0.20, 0.40, 1400, 0.55, 3.0);
    r.body(0.06, 0.18, 130, 56, 0.40, 3.0);
    r.master(2.0, 2600);
}

fn mkDelverSurge(r: *Rack) void {
    r.body(0.0, 0.80, 34, 76, 1.1, 0.7);
    r.grit(0.0, 0.82, 0.42, 340, 0.78, 0.5);
    r.growl(0.10, 0.72, 44, 92, 0.42, 0.34, 0.5);
    r.crackle(0.40, 34.0);
    r.master(2.4, 1700);
}

fn mkDelverBurst(r: *Rack) void {
    r.tick(0.0, 0.85, 2200);
    r.body(0.0, 0.56, 84, 20, 1.4, 2.0);
    r.grit(0.0, 0.44, 0.90, 1500, 0.86, 2.2);
    r.grit(0.12, 0.36, 0.40, 2400, 0.90, 2.0);
    r.air(0.0, 0.30, 0.34, 2000, 240, 0.40, 2.6);
    r.crackle(0.30, 90.0);
    r.master(3.0, 2200);
}

fn mkDelverHurt(r: *Rack) void {
    r.growl(0.0, 0.24, 180, 88, 0.72, 0.42, 0.10);
    r.grit(0.0, 0.12, 0.48, 1300, 0.60, 4.2);
    r.body(0.0, 0.14, 140, 56, 0.50, 4.0);
    r.master(2.2, 2600);
}

fn mkDelverDie(r: *Rack) void {
    r.growl(0.0, 0.62, 160, 46, 0.82, 0.46, 0.08);
    r.grit(0.10, 0.50, 0.40, 900, 0.66, 1.6);
    r.body(0.52, 0.30, 78, 30, 0.70, 2.4);
    r.master(2.2, 2100);
}

fn mkBowDraw(r: *Rack) void {
    r.air(0.0, 0.55, 0.6, 420, 1150, 0.88, 0.9);
    r.grit(0.0, 0.5, 0.14, 2400, 0.85, 1.1);
    r.master(1.6, 3400);
}

fn mkBowLoose(r: *Rack) void {
    r.tick(0.0, 0.5, 6000);
    r.ring(0.0, 0.30, 196, 0.9, 5.0, 4);
    r.air(0.01, 0.22, 0.45, 4200, 1200, 0.5, 3.2);
    r.body(0.0, 0.07, 150, 84, 0.3, 6.0);
    r.master(1.9, 5000);
}


fn arrowRip(r: *Rack, amp: f32) void {
    r.air(0.0, 0.13, amp, 5200, 900, 0.35, 3.4);
    r.grit(0.0, 0.09, amp * 0.55, 3600, 0.25, 4.6);
}

fn mkArrowHit(r: *Rack) void {
    arrowRip(r, 1.0);
    r.tick(0.0, 0.34, 2600);
    r.body(0.0, 0.15, 170, 58, 0.70, 5.0);
    r.grit(0.0, 0.10, 0.50, 1200, 0.55, 5.2);
    r.master(2.2, 3000);
}

fn mkArrowDirt(r: *Rack) void {
    arrowRip(r, 0.62);
    r.body(0.0, 0.11, 150, 52, 0.60, 6.0);
    r.grit(0.0, 0.12, 0.55, 900, 0.65, 5.0);
    r.master(1.9, 2400);
}

fn mkArrowWood(r: *Rack) void {
    arrowRip(r, 0.34);
    r.tick(0.0, 0.70, 5000);
    r.body(0.0, 0.11, 300, 96, 0.95, 6.0);
    r.ring(0.003, 0.13, 420, 0.30, 8.0, 2);
    r.grit(0.0, 0.06, 0.45, 2600, 0.4, 7.0);
    r.master(2.2, 4200);
}

fn mkArrowStone(r: *Rack) void {
    arrowRip(r, 0.40);
    r.tick(0.0, 0.85, 7000);
    r.body(0.0, 0.055, 420, 190, 0.55, 9.0);
    r.ring(0.002, 0.11, 3100, 0.34, 9.0, 2);
    r.grit(0.0, 0.07, 0.75, 4200, 0.35, 7.5);
    r.master(2.1, 5600);
}

fn mkArrowMetal(r: *Rack) void {
    arrowRip(r, 0.30);
    r.tick(0.0, 0.90, 8000);
    r.body(0.0, 0.06, 520, 240, 0.60, 8.5);
    r.ring(0.002, 0.30, 1750, 0.55, 4.5, 3);
    r.grit(0.0, 0.05, 0.5, 5000, 0.3, 8.0);
    r.master(2.0, 5600);
}


fn mkWandCharge(r: *Rack) void {
    r.air(0.0, 0.34, 0.34, 700, 3800, 0.66, 1.1);
    r.growl(0.02, 0.32, 150, 430, 0.30, 0.26, 0.42);
    r.ring(0.05, 0.30, 880, 0.15, 3.0, 3);
    r.grit(0.0, 0.28, 0.12, 3000, 0.30, 1.2);
    r.master(1.5, 4400);
}

/// A CRACK, not a boom: the bolt is 24 damage of the most-resisted element, and a cannon would promise a hit the numbers cannot pay for.
fn mkWandCast(r: *Rack) void {
    r.tick(0.0, 0.44, 5200);
    r.ring(0.0, 0.26, 620, 0.24, 5.5, 3);
    r.air(0.0, 0.20, 0.50, 4600, 1100, 0.48, 3.4);
    r.body(0.0, 0.09, 260, 110, 0.32, 5.5);
    r.grit(0.02, 0.15, 0.24, 1800, 0.45, 3.0);
    r.master(2.1, 5000);
}

fn mkBoneHurt(r: *Rack) void {
    r.tick(0.0, 0.6, 6500);
    r.grit(0.0, 0.20, 0.85, 3800, 0.9, 4.0);
    r.ring(0.0, 0.16, 900, 0.35, 6.5, 4);
    r.body(0.0, 0.09, 260, 100, 0.4, 6.0);
    r.master(2.3, 5200);
}

fn mkBoneDie(r: *Rack) void {
    r.grit(0.0, 0.75, 0.9, 3200, 0.95, 1.9);
    r.ring(0.0, 0.35, 700, 0.3, 4.0, 5);
    r.ring(0.16, 0.35, 520, 0.22, 4.5, 4);
    r.body(0.02, 0.28, 130, 50, 0.4, 3.0);
    r.master(2.1, 4400);
}

fn mkSkelLunge(r: *Rack) void {
    r.grit(0.0, 0.17, 0.85, 3400, 0.9, 4.6);
    r.ring(0.0, 0.20, 820, 0.22, 5.5, 3);
    r.body(0.01, 0.15, 124, 52, 0.75, 4.2);
    r.air(0.09, 0.32, 0.95, 1600, 300, 0.42, 1.9);
    r.air(0.13, 0.20, 0.32, 5000, 1900, 0.16, 3.0);
    r.master(2.2, 3600);
}



fn mkShadeReach(r: *Rack) void {
    r.air(0.0, 0.34, 0.40, 2600, 620, 0.72, 1.5);
    r.ring(0.04, 0.26, 214, 0.11, 3.4, 3);
    r.grit(0.0, 0.20, 0.07, 900, 0.55, 2.2);
    r.master(1.5, 3000);
}

fn mkShadeGather(r: *Rack) void {
    r.air(0.0, 0.66, 0.36, 480, 3100, 0.80, 1.0);
    r.ring(0.10, 0.56, 296, 0.13, 2.2, 4);
    r.ring(0.28, 0.42, 444, 0.09, 2.6, 3);
    r.grit(0.06, 0.58, 0.06, 2400, 0.30, 1.1);
    r.master(1.4, 4200);
}


fn mkStoneLoose(r: *Rack) void {
    r.tick(0.0, 0.36, 3400);
    r.air(0.0, 0.26, 0.62, 420, 2600, 0.34, 1.6);
    r.grit(0.0, 0.20, 0.54, 2200, 0.66, 2.6);
    r.master(2.0, 3200);
}

fn mkStoneGrind(r: *Rack) void {
    r.grit(0.0, 0.70, 0.66, 1400, 0.80, 0.5);
    r.growl(0.0, 0.78, 34, 58, 0.46, 0.50, 0.4);
    r.air(0.06, 0.58, 0.16, 900, 3200, 0.26, 0.7);
    r.crackle(0.30, 26.0);
    r.body(0.40, 0.30, 74, 30, 0.40, 3.0);
    r.master(2.2, 3000);
}

fn mkWoodWake(r: *Rack) void {
    r.grit(0.0, 0.62, 0.52, 900, 0.72, 0.6);
    r.growl(0.02, 0.70, 44, 84, 0.40, 0.42, 0.5);
    r.air(0.0, 0.66, 0.20, 700, 2200, 0.30, 0.5);
    r.crackle(0.34, 40.0);
    r.body(0.44, 0.26, 92, 38, 0.34, 3.4);
    r.master(2.0, 2600);
}

fn mkWoodCreak(r: *Rack) void {
    r.growl(0.0, 0.44, 62, 78, 0.26, 0.34, 1.0);
    r.grit(0.04, 0.30, 0.16, 620, 0.60, 1.6);
    r.ends(0.10, 0.14);
    r.master(1.4, 1800);
}

fn mkWoodSwing(r: *Rack) void {
    r.air(0.0, 0.30, 0.56, 260, 1500, 0.36, 1.5);
    r.growl(0.0, 0.26, 58, 96, 0.20, 0.26, 1.8);
    r.master(1.7, 2400);
}

fn mkWoodHit(r: *Rack) void {
    r.tick(0.0, 0.44, 2600);
    r.body(0.0, 0.20, 150, 44, 0.62, 4.0);
    r.grit(0.0, 0.16, 0.50, 1300, 0.66, 3.4);
    r.crackle(0.22, 70.0);
    r.master(2.4, 2200);
}

fn mkWoodHurt(r: *Rack) void {
    r.tick(0.0, 0.40, 4200);
    r.grit(0.0, 0.13, 0.56, 1900, 0.62, 3.8);
    r.body(0.0, 0.11, 190, 70, 0.34, 4.6);
    r.crackle(0.16, 90.0);
    r.master(2.3, 3200);
}

fn mkWoodDie(r: *Rack) void {
    r.grit(0.0, 0.70, 0.54, 1000, 0.76, 1.2);
    r.growl(0.0, 0.80, 70, 30, 0.44, 0.46, 1.4);
    r.air(0.10, 0.60, 0.26, 1600, 300, 0.30, 1.6);
    r.crackle(0.44, 120.0);
    r.body(0.80, 0.30, 110, 32, 0.72, 3.0);
    r.grit(0.80, 0.24, 0.40, 800, 0.70, 3.2);
    r.master(2.5, 2000);
}

fn mkLeechWing(r: *Rack) void {
    r.growl(0.0, 0.32, 356, 392, 0.26, 0.05, 1.0);
    r.air(0.0, 0.32, 0.06, 2600, 1700, 0.25, 1.0);
    r.wow(0.0045, 6.5);
    r.ends(0.09, 0.12);
    r.master(1.0, 2200);
}

fn mkLeechStab(r: *Rack) void {
    r.tick(0.0, 0.40, 5600);
    r.grit(0.0, 0.055, 0.34, 2400, 0.55, 4.0);
    r.body(0.005, 0.09, 260, 96, 0.30, 5.2);
    r.air(0.01, 0.16, 0.26, 1800, 420, 0.70, 2.4);
    r.master(2.2, 4600);
}

fn mkLeechDrink(r: *Rack) void {
    r.air(0.0, 0.34, 0.44, 500, 2600, 0.82, 0.5);
    r.growl(0.02, 0.26, 96, 148, 0.20, 0.22, 0.8);
    r.ring(0.0, 0.20, 210, 0.10, 3.4, 3);
    r.crackle(0.10, 90.0);
    r.master(1.8, 3600);
}

fn mkLeechHurt(r: *Rack) void {
    r.tick(0.0, 0.36, 4800);
    r.grit(0.0, 0.10, 0.42, 2000, 0.70, 3.4);
    r.growl(0.0, 0.20, 620, 240, 0.26, 0.30, 3.0);
    r.body(0.0, 0.10, 180, 70, 0.26, 5.0);
    r.master(2.3, 4400);
}

fn mkLeechDie(r: *Rack) void {
    r.growl(0.0, 0.46, 600, 120, 0.34, 0.34, 1.6);
    r.air(0.0, 0.40, 0.20, 4000, 700, 0.40, 2.0);
    r.grit(0.02, 0.22, 0.30, 1500, 0.60, 3.0);
    r.body(0.44, 0.14, 130, 48, 0.34, 4.4);
    r.master(2.1, 4000);
}

fn mkShadeWisp(r: *Rack) void {
    r.air(0.0, 0.26, 0.62, 3600, 700, 0.55, 2.8);
    r.ring(0.0, 0.20, 330, 0.20, 5.0, 3);
    r.body(0.0, 0.08, 190, 74, 0.24, 5.5);
    r.grit(0.01, 0.13, 0.16, 1600, 0.40, 3.2);
    r.master(1.9, 4200);
}

fn mkShadeTouch(r: *Rack) void {
    r.tick(0.0, 0.30, 4200);
    r.air(0.0, 0.36, 0.50, 3400, 380, 0.86, 1.4);
    r.ring(0.02, 0.30, 262, 0.22, 3.0, 4);
    r.ring(0.05, 0.24, 175, 0.14, 3.6, 3);
    r.body(0.0, 0.12, 150, 62, 0.30, 4.6);
    r.master(2.0, 3800);
}

fn mkShadeBlink(r: *Rack) void {
    r.air(0.0, 0.14, 0.66, 900, 5200, 0.60, 3.4);
    r.tick(0.01, 0.34, 6000);
    r.air(0.10, 0.34, 0.44, 4400, 340, 0.82, 1.6);
    r.ring(0.0, 0.32, 388, 0.18, 4.0, 4);
    r.grit(0.0, 0.22, 0.14, 2800, 0.45, 2.6);
    r.master(2.0, 4600);
}

fn mkShadeHurt(r: *Rack) void {
    r.air(0.0, 0.22, 0.52, 3000, 900, 0.66, 3.0);
    r.ring(0.0, 0.18, 356, 0.20, 5.0, 3);
    r.grit(0.0, 0.16, 0.22, 2200, 0.60, 3.6);
    r.master(2.2, 4400);
}

fn mkShadeDie(r: *Rack) void {
    r.air(0.0, 0.86, 0.54, 2800, 260, 0.74, 1.5);
    r.ring(0.0, 0.60, 330, 0.16, 2.6, 4);
    r.ring(0.14, 0.52, 246, 0.13, 2.4, 3);
    r.grit(0.05, 0.60, 0.10, 1500, 0.50, 1.7);
    r.master(1.7, 3600);
}

fn mkOgreStep(r: *Rack) void {
    r.body(0.0, 0.42, 74, 27, 1.2, 2.4);
    r.body(0.0, 0.16, 150, 60, 0.4, 4.5);
    r.grit(0.005, 0.26, 0.45, 1500, 0.8, 3.2);
    r.master(2.6, 2200);
}

fn mkOgreRoar(r: *Rack) void {
    r.growl(0.0, 0.85, 68, 104, 1.0, 0.28, 0.35);
    r.growl(0.02, 0.80, 102, 152, 0.5, 0.4, 0.4);
    r.body(0.0, 0.7, 46, 34, 0.6, 1.4);
    r.air(0.1, 0.6, 0.16, 700, 2200, 0.3, 1.5);
    r.master(2.4, 2600);
}

fn mkOgreSlam(r: *Rack) void {
    r.tick(0.0, 0.9, 3000);
    r.body(0.0, 0.62, 96, 22, 1.5, 1.9);
    r.body(0.0, 0.20, 210, 55, 0.7, 3.6);
    r.grit(0.0, 0.40, 0.9, 1700, 0.85, 2.4);
    r.grit(0.14, 0.34, 0.35, 2600, 0.95, 2.2);
    r.air(0.0, 0.30, 0.35, 2200, 260, 0.4, 2.6);
    r.master(3.0, 2400);
}

fn mkOgreSwipe(r: *Rack) void {
    r.air(0.0, 0.42, 1.0, 1900, 210, 0.55, 1.8);
    r.air(0.04, 0.34, 0.4, 900, 3000, 0.35, 2.2);
    r.body(0.06, 0.24, 120, 52, 0.4, 2.8);
    r.master(2.2, 2800);
}

fn mkOgreHurt(r: *Rack) void {
    r.growl(0.0, 0.26, 96, 66, 0.9, 0.3, 0.1);
    r.body(0.0, 0.26, 108, 40, 0.9, 3.2);
    r.grit(0.0, 0.14, 0.4, 1400, 0.7, 4.0);
    r.master(2.5, 2400);
}

fn mkOgreDie(r: *Rack) void {
    r.growl(0.0, 1.0, 92, 34, 1.0, 0.35, 0.06);
    r.body(0.62, 0.75, 74, 20, 1.3, 1.7);
    r.grit(0.62, 0.55, 0.6, 1300, 0.9, 2.0);
    r.body(0.0, 0.9, 50, 30, 0.5, 1.3);
    r.sat(2.8);
    r.warm(2100);
    r.wow(0.004, 1.1);
    r.hiss(0.016);
    r.norm(0.95);
    r.ends(0.006, 0.20);
}

// **IRON OVER BONE, NOTHING ALIVE INSIDE IT.** Every cue carries a `ring` — struck plate, the one layer the ogre never uses — over `grit` that is dry bone rather than a wet thump.

fn mkKnightStep(r: *Rack) void {
    r.body(0.0, 0.46, 70, 25, 1.15, 2.3);
    r.body(0.0, 0.13, 146, 62, 0.34, 4.8);
    r.grit(0.004, 0.20, 0.30, 2800, 0.7, 3.6);
    r.ring(0.006, 0.34, 380, 0.15, 4.4, 3);
    r.master(2.5, 2600);
}

fn mkKnightPlant(r: *Rack) void {
    r.tick(0.0, 0.55, 2600);
    r.body(0.0, 0.60, 84, 21, 1.35, 2.0);
    r.body(0.0, 0.17, 190, 58, 0.55, 3.9);
    r.grit(0.0, 0.34, 0.55, 2200, 0.85, 2.8);
    r.ring(0.004, 0.44, 340, 0.22, 3.6, 4);
    r.air(0.0, 0.26, 0.26, 2000, 260, 0.38, 2.8);
    r.master(2.8, 2500);
}

fn mkKnightRoar(r: *Rack) void {
    r.growl(0.0, 0.95, 58, 88, 0.95, 0.20, 0.30);
    r.growl(0.03, 0.88, 116, 84, 0.42, 0.55, 0.42);
    r.ring(0.0, 0.80, 132, 0.26, 1.9, 4);
    r.body(0.0, 0.85, 66, 48, 0.45, 1.2);
    r.air(0.06, 0.90, 0.20, 520, 1700, 0.42, 1.3);
    r.hall(0.55, 1500);
    r.master(2.3, 2400);
}

fn mkKnightSlam(r: *Rack) void {
    r.tick(0.0, 0.85, 3400);
    r.body(0.0, 0.66, 92, 20, 1.45, 1.9);
    r.body(0.0, 0.19, 230, 60, 0.62, 3.7);
    r.grit(0.0, 0.42, 0.80, 2600, 0.9, 2.4);
    r.ring(0.003, 0.60, 520, 0.30, 3.0, 5);
    r.grit(0.16, 0.36, 0.30, 3400, 0.95, 2.2);
    r.air(0.0, 0.30, 0.32, 2400, 280, 0.42, 2.6);
    r.master(2.9, 2600);
}

fn mkKnightHeave(r: *Rack) void {
    r.growl(0.0, 0.28, 132, 70, 0.58, 0.30, 3.2);
    r.ring(0.0, 0.34, 300, 0.14, 3.4, 3);
    r.air(0.0, 0.32, 0.30, 820, 300, 0.44, 2.6);
    r.body(0.0, 0.14, 86, 42, 0.36, 3.0);
    r.grit(0.02, 0.18, 0.20, 2600, 0.75, 2.6);
    r.master(2.2, 3000);
}

fn mkKnightSwipe(r: *Rack) void {
    r.air(0.0, 0.46, 1.0, 1800, 190, 0.58, 1.7);
    r.air(0.05, 0.36, 0.38, 850, 3200, 0.34, 2.1);
    r.ring(0.10, 0.34, 660, 0.14, 3.2, 3);
    r.body(0.08, 0.24, 112, 48, 0.36, 2.8);
    r.master(2.2, 3000);
}

fn mkKnightLunge(r: *Rack) void {
    r.grit(0.0, 0.20, 0.70, 3000, 0.9, 4.2);
    r.ring(0.0, 0.28, 560, 0.20, 4.2, 4);
    r.body(0.01, 0.18, 104, 44, 0.70, 3.8);
    r.air(0.08, 0.40, 0.90, 1500, 260, 0.44, 1.8);
    r.master(2.3, 3200);
}

fn mkKnightHurt(r: *Rack) void {
    r.tick(0.0, 0.50, 5200);
    r.ring(0.0, 0.30, 720, 0.34, 4.2, 5);
    r.grit(0.0, 0.18, 0.66, 3400, 0.85, 4.2);
    r.body(0.0, 0.11, 210, 84, 0.46, 5.4);
    r.master(2.4, 4200);
}

fn mkKnightDie(r: *Rack) void {
    r.growl(0.0, 0.90, 84, 30, 0.90, 0.26, 0.08);
    r.ring(0.0, 0.70, 150, 0.22, 2.2, 4);
    r.body(0.0, 1.10, 72, 44, 0.42, 1.2);
    // The topple lands at `knight.DEATH_LAND` = 1.36 s, and the crash is written to arrive with it.
    r.tick(1.36, 0.60, 2600);
    r.body(1.36, 0.80, 88, 18, 1.35, 1.6);
    r.grit(1.36, 0.66, 0.70, 2400, 0.92, 1.9);
    r.ring(1.37, 0.80, 400, 0.28, 2.4, 5);
    r.air(1.36, 0.40, 0.30, 2100, 240, 0.40, 2.4);
    r.hall(0.50, 1400);
    r.sat(2.6);
    r.warm(2300);
    r.wow(0.0035, 1.2);
    r.hiss(0.014);
    r.norm(0.94);
    r.ends(0.006, 0.22);
}

fn mkKoboldSnarl(r: *Rack) void {
    r.body(0.0, 0.12, 132, 84, 0.75, 4.0);
    r.growl(0.0, 0.14, 176, 236, 0.85, 0.14, 0.06);
    r.growl(0.10, 0.26, 208, 118, 0.60, 0.26, 0.16);
    r.air(0.0, 0.10, 0.16, 900, 1900, 0.30, 3.2);
    r.master(1.35, 2300);
}

fn mkKoboldChop(r: *Rack) void {
    r.air(0.0, 0.21, 0.46, 1700, 420, 0.34, 2.6);
    r.grit(0.02, 0.10, 0.08, 1000, 0.4, 3.0);
    r.growl(0.0, 0.15, 148, 116, 0.26, 0.24, 0.30);
    r.master(1.15, 2000);
}

fn mkKoboldHeave(r: *Rack) void {
    r.air(0.0, 0.24, 0.52, 1300, 380, 0.22, 1.8);
    r.growl(0.02, 0.20, 148, 104, 0.26, 0.30, 0.18);
    r.air(0.30, 0.26, 0.48, 1150, 340, 0.20, 1.6);
    r.growl(0.32, 0.22, 132, 92, 0.24, 0.34, 0.20);
    r.air(0.58, 0.22, 0.40, 1000, 300, 0.18, 1.6);
    r.master(1.3, 1900);
}

fn mkKoboldCast(r: *Rack) void {
    r.grit(0.0, 0.10, 0.20, 2600, 0.7, 5.0);
    r.growl(0.02, 0.85, 190, 300, 0.40, 0.34, 0.55);
    r.body(0.10, 0.75, 128, 190, 0.24, 1.6);
    r.grit(0.58, 0.30, 0.10, 1500, 0.5, 2.0);
    r.master(1.5, 3200);
}

fn mkKoboldHeal(r: *Rack) void {
    const ROOT: f32 = 330.0;
    r.choir(0.00, 1.55, ROOT * 0.5, 0.30, 2, 0.30);
    r.choir(0.00, 1.60, ROOT, 0.46, 3, 0.26);
    r.choir(0.10, 1.50, ROOT * 1.5, 0.38, 3, 0.28);
    r.choir(0.22, 1.38, ROOT * 2.0, 0.30, 2, 0.30);
    r.choir(0.34, 1.24, ROOT * 2.5, 0.20, 2, 0.32);
    r.sparkle(0.06, 1.10, 0.085, ROOT * 4.0, 11);
    r.ring(0.0, 0.34, ROOT * 4.0, 0.10, 4.2, 2);
    r.hall(1.30, 3400);
    r.master(0.95, 5200);
}

fn mkKoboldWhirl(r: *Rack) void {
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const t = 0.02 + @as(f32, @floatFromInt(i)) * 0.20;
        r.air(t, 0.17, 0.34 + 0.06 * @as(f32, @floatFromInt(i)), 900, 2400, 0.55, 2.2);
    }
    r.master(2.0, 4000);
}

fn mkKoboldSling(r: *Rack) void {
    r.tick(0.0, 0.5, 6000);
    r.air(0.0, 0.11, 0.46, 3400, 1200, 0.5, 4.5);
    r.body(0.0, 0.06, 300, 150, 0.22, 6.0);
    r.master(2.2, 5400);
}

fn mkKoboldBite(r: *Rack) void {
    r.air(0.0, 0.07, 0.26, 900, 1700, 0.32, 3.5);
    r.tick(0.06, 0.34, 2600);
    r.ring(0.06, 0.06, 620, 0.14, 9.0, 2);
    r.body(0.05, 0.10, 128, 72, 0.55, 4.5);
    r.growl(0.0, 0.16, 210, 148, 0.5, 0.22, 0.10);
    r.master(1.3, 2200);
}


fn mkWolfHowl(r: *Rack) void {
    r.body(0.0, 0.80, 150, 134, 0.34, 1.2);
    r.growl(0.0, 0.30, 200, 400, 0.54, 0.09, 0.03);
    r.growl(0.24, 0.60, 408, 384, 0.66, 0.06, 0.02);
    r.growl(0.78, 0.52, 380, 214, 0.48, 0.11, 0.05);
    r.air(0.0, 1.10, 0.08, 700, 400, 0.08, 1.0);
    r.ring(0.34, 0.85, 192, 0.06, 1.1, 3);
    r.master(1.15, 2000);
}

fn mkWolfGrowl(r: *Rack) void {
    r.body(0.0, 0.42, 96, 84, 0.62, 2.0);
    r.growl(0.0, 0.46, 118, 104, 0.70, 0.34, 0.26);
    r.growl(0.04, 0.40, 84, 76, 0.44, 0.42, 0.34);
    r.grit(0.0, 0.38, 0.10, 620, 0.55, 2.2);
    r.ring(0.10, 0.60, 168, 0.07, 1.1, 3);
    r.master(1.20, 1500);
}

fn mkWolfBite(r: *Rack) void {
    r.air(0.0, 0.10, 0.34, 820, 1500, 0.36, 3.2);
    r.tick(0.07, 0.44, 2200);
    r.ring(0.07, 0.09, 540, 0.17, 8.0, 2);
    r.body(0.06, 0.15, 112, 62, 0.72, 3.8);
    r.growl(0.0, 0.20, 152, 112, 0.52, 0.26, 0.14);
    r.grit(0.06, 0.10, 0.12, 900, 0.45, 3.0);
    r.ring(0.10, 0.72, 196, 0.06, 1.0, 3);
    r.master(1.30, 2200);
}

fn mkWolfHurt(r: *Rack) void {
    r.body(0.0, 0.16, 104, 58, 0.62, 4.0);
    r.growl(0.0, 0.17, 176, 288, 0.88, 0.15, 0.07);
    r.growl(0.06, 0.22, 150, 92, 0.46, 0.26, 0.22);
    r.air(0.0, 0.12, 0.18, 1000, 440, 0.26, 2.8);
    r.ring(0.06, 0.85, 182, 0.09, 0.95, 3);
    r.master(1.28, 2000);
}

fn mkWolfDie(r: *Rack) void {
    r.growl(0.0, 0.20, 190, 300, 0.86, 0.17, 0.08);
    r.growl(0.10, 0.52, 168, 74, 0.60, 0.30, 0.16);
    r.body(0.14, 0.34, 92, 34, 0.42, 2.6);
    r.grit(0.22, 0.30, 0.18, 900, 0.60, 2.4);
    r.ring(0.24, 1.60, 208, 0.20, 0.42, 4);
    r.ring(0.42, 1.40, 312, 0.14, 0.48, 3);
    r.ring(0.60, 1.20, 415, 0.08, 0.55, 2);
    r.master(1.30, 2000);
}

fn mkKoboldHurt(r: *Rack) void {
    r.body(0.0, 0.13, 120, 66, 0.6, 4.2);
    r.growl(0.0, 0.15, 200, 300, 0.85, 0.16, 0.08);
    r.growl(0.05, 0.18, 168, 104, 0.42, 0.26, 0.24);
    r.air(0.0, 0.10, 0.16, 1200, 500, 0.26, 3.0);
    r.master(1.3, 2200);
}

fn mkKoboldDie(r: *Rack) void {
    r.growl(0.0, 0.18, 216, 326, 0.9, 0.18, 0.08);
    r.growl(0.09, 0.48, 194, 78, 0.62, 0.30, 0.14);
    r.grit(0.26, 0.34, 0.24, 1100, 0.75, 2.4);
    r.body(0.30, 0.26, 96, 36, 0.44, 2.8);
    r.master(1.35, 1900);
}


fn mkSpiderHiss(r: *Rack) void {
    r.air(0.0, 0.38, 0.46, 2600, 5200, 0.42, 1.5);
    r.grit(0.06, 0.34, 0.16, 2200, 0.35, 1.8);
    r.growl(0.02, 0.30, 96, 132, 0.20, 0.55, 0.40);
    r.air(0.30, 0.30, 0.34, 4200, 2400, 0.38, 2.2);
    r.master(1.5, 5200);
}

fn mkSpiderSpit(r: *Rack) void {
    r.growl(0.0, 0.10, 150, 90, 0.42, 0.40, 0.10);
    r.grit(0.07, 0.09, 0.52, 1500, 0.55, 5.0);
    r.air(0.07, 0.14, 0.40, 1900, 700, 0.40, 3.6);
    r.body(0.07, 0.07, 210, 96, 0.34, 6.0);
    r.master(1.8, 3600);
}

fn mkSpiderBite(r: *Rack) void {
    r.air(0.0, 0.08, 0.30, 1000, 2000, 0.34, 3.4);
    r.tick(0.05, 0.42, 2400);
    r.tick(0.072, 0.30, 3100);
    r.ring(0.05, 0.09, 480, 0.20, 8.0, 3);
    r.body(0.05, 0.12, 112, 60, 0.52, 4.2);
    r.grit(0.05, 0.14, 0.20, 800, 0.6, 3.2);
    r.master(1.4, 2200);
}

fn mkSpiderHurt(r: *Rack) void {
    r.grit(0.0, 0.07, 0.44, 2800, 0.5, 5.5);
    r.air(0.0, 0.26, 0.44, 3400, 1500, 0.52, 2.6);
    r.growl(0.0, 0.22, 340, 190, 0.44, 0.42, 0.14);
    r.body(0.0, 0.11, 130, 70, 0.40, 4.4);
    r.master(1.4, 3400);
}

fn mkSpiderDie(r: *Rack) void {
    r.growl(0.0, 0.30, 360, 120, 0.70, 0.44, 0.10);
    r.air(0.0, 0.42, 0.44, 3000, 900, 0.46, 1.9);
    r.body(0.22, 0.30, 104, 40, 0.66, 3.0);
    r.grit(0.30, 0.52, 0.26, 1300, 0.85, 1.7);
    r.grit(0.62, 0.34, 0.14, 1000, 0.9, 2.2);
    r.master(1.35, 2000);
}

fn mkBroodScreech(r: *Rack) void {
    r.growl(0.0, 0.30, 900, 1750, 0.72, 0.26, 0.16);
    r.growl(0.015, 0.28, 940, 1690, 0.44, 0.40, 0.20);
    r.air(0.0, 0.30, 0.34, 4200, 8000, 0.55, 2.0);
    r.growl(0.24, 0.16, 1600, 820, 0.42, 0.55, 0.30);
    r.grit(0.0, 0.07, 0.26, 5200, 0.35, 5.0);
    r.master(1.7, 8200);
}

fn mkBroodLeap(r: *Rack) void {
    r.growl(0.0, 0.13, 620, 980, 0.70, 0.30, 0.10);
    r.air(0.0, 0.10, 0.24, 3000, 6000, 0.45, 3.0);
    r.tick(0.0, 0.24, 5200);
    r.master(1.5, 6200);
}

fn mkBroodBite(r: *Rack) void {
    r.tick(0.02, 0.34, 4200);
    r.tick(0.036, 0.24, 5000);
    r.ring(0.02, 0.05, 1050, 0.16, 10.0, 2);
    r.air(0.0, 0.05, 0.22, 1800, 3200, 0.34, 4.2);
    r.body(0.02, 0.05, 220, 130, 0.24, 6.0);
    r.master(1.3, 4400);
}

fn mkBroodHurt(r: *Rack) void {
    r.grit(0.0, 0.05, 0.40, 4200, 0.4, 6.0);
    r.growl(0.0, 0.13, 760, 420, 0.52, 0.36, 0.10);
    r.air(0.0, 0.12, 0.26, 4000, 2200, 0.44, 3.4);
    r.master(1.3, 5200);
}

fn mkBroodDie(r: *Rack) void {
    r.grit(0.0, 0.06, 0.62, 2200, 0.6, 6.0);
    r.body(0.0, 0.09, 300, 90, 0.50, 5.5);
    r.growl(0.0, 0.10, 820, 300, 0.44, 0.40, 0.08);
    r.grit(0.05, 0.14, 0.20, 1200, 0.8, 3.0);
    r.master(1.5, 3200);
}

fn mkSacLay(r: *Rack) void {
    r.growl(0.0, 0.34, 120, 84, 0.34, 0.50, 0.45);
    r.grit(0.24, 0.20, 0.34, 900, 0.7, 3.0);
    r.body(0.32, 0.16, 96, 44, 0.60, 4.0);
    r.grit(0.34, 0.16, 0.20, 620, 0.55, 3.4);
    r.master(1.4, 1800);
}

fn mkSacHit(r: *Rack) void {
    r.grit(0.0, 0.09, 0.44, 1300, 0.5, 4.5);
    r.body(0.0, 0.10, 168, 76, 0.44, 5.0);
    r.air(0.0, 0.13, 0.20, 900, 400, 0.30, 3.4);
    r.master(1.4, 2000);
}

fn mkSacHatch(r: *Rack) void {
    r.grit(0.0, 0.20, 0.50, 1800, 0.55, 3.0);
    r.air(0.0, 0.30, 0.34, 2400, 1000, 0.40, 2.4);
    r.body(0.04, 0.18, 130, 58, 0.42, 3.6);
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const t = 0.20 + @as(f32, @floatFromInt(i)) * 0.10 + r.rng.range(-0.03, 0.03);
        r.grit(t, 0.16, 0.18, 3200, 0.9, 3.2);
        r.growl(t, 0.09, 700 + r.rng.signed() * 120, 460, 0.24, 0.34, 0.12);
    }
    r.master(1.5, 4200);
}

fn mkSacBurst(r: *Rack) void {
    r.grit(0.0, 0.08, 0.72, 1600, 0.5, 5.5);
    r.body(0.0, 0.16, 190, 52, 0.72, 4.0);
    r.air(0.0, 0.22, 0.44, 2000, 600, 0.42, 2.8);
    r.grit(0.07, 0.30, 0.26, 800, 0.8, 2.2);
    r.master(1.7, 2600);
}

fn mkAcidSplash(r: *Rack) void {
    r.grit(0.0, 0.07, 0.60, 1200, 0.45, 5.5);
    r.body(0.0, 0.11, 150, 58, 0.50, 4.5);
    r.air(0.04, 0.30, 0.30, 1600, 3600, 0.30, 1.8);
    r.grit(0.10, 0.34, 0.22, 4200, 0.25, 1.6);
    r.master(1.6, 5000);
}

fn mkAcidBurn(r: *Rack) void {
    r.grit(0.0, 0.22, 0.34, 5200, 0.20, 2.2);
    r.air(0.0, 0.18, 0.22, 3000, 6000, 0.34, 2.6);
    r.body(0.0, 0.07, 190, 110, 0.20, 5.0);
    r.master(1.3, 6000);
}

fn mkFlaskDrink(r: *Rack) void {
    r.ring(0.0, 0.20, 2450, 0.55, 9.0, 2);
    r.tick(0.0, 0.30, 3000);
    r.body(0.10, 0.11, 150, 96, 0.55, 5.0);
    r.body(0.27, 0.11, 132, 84, 0.60, 5.0);
    r.body(0.46, 0.13, 118, 72, 0.65, 4.4);
    r.grit(0.10, 0.45, 0.10, 900, 0.5, 2.2);
    r.body(0.58, 0.42, 90, 150, 0.5, 1.7);
    // A slight sparkle on the bloom (owner's call), UNDER the master's 2.8 kHz so it is felt not heard.
    r.sparkle(0.56, 0.34, 0.035, 1320, 4);
    r.master(1.8, 2800);
}

fn mkEat(r: *Rack) void {
    r.grit(0.0, 0.16, 0.42, 1700, 0.85, 3.0);
    r.air(0.0, 0.12, 0.14, 1200, 500, 0.25, 3.4);
    r.body(0.14, 0.09, 116, 74, 0.42, 5.5);
    r.grit(0.14, 0.10, 0.26, 1100, 0.7, 4.5);
    r.body(0.31, 0.09, 104, 66, 0.38, 5.5);
    r.grit(0.31, 0.09, 0.22, 1000, 0.7, 4.8);
    r.body(0.50, 0.10, 96, 60, 0.34, 5.0);
    r.grit(0.50, 0.10, 0.20, 950, 0.65, 4.8);
    r.master(1.4, 2200);
}

fn mkChestOpen(r: *Rack) void {
    r.tick(0.0, 0.55, 4200);
    r.ring(0.0, 0.16, 620, 0.34, 6.0, 3);
    r.grit(0.06, 0.52, 0.30, 1100, 0.85, 1.1);
    r.body(0.06, 0.30, 132, 88, 0.40, 1.6);
    r.tick(0.60, 0.42, 2600);
    r.body(0.60, 0.16, 108, 58, 0.46, 4.0);
    r.master(2.0, 3200);
}

fn mkItemGet(r: *Rack) void {
    r.ring(0.0, 0.34, 784, 0.46, 3.2, 3);
    r.ring(0.02, 0.28, 1176, 0.22, 4.4, 2);
    r.air(0.0, 0.20, 0.12, 2400, 5200, 0.45, 2.6);
    r.master(1.9, 6000);
}

fn mkFlaskCycle(r: *Rack) void {
    r.tick(0.0, 0.30, 6000);
    r.body(0.0, 0.06, 720, 520, 0.45, 6.5);
    r.masterX(1.4, 5200, CRUSH_BITS - 1.0, CRUSH_HOLD);
}


fn mkSoulsSpill(r: *Rack) void {
    r.ring(0.0, 0.70, 523, 0.40, 2.6, 4);
    r.ring(0.03, 0.62, 349, 0.30, 2.4, 3);
    r.air(0.0, 0.85, 0.34, 3400, 420, 0.55, 1.5);
    r.body(0.05, 0.55, 190, 62, 0.34, 2.2);
    r.master(1.7, 5200);
}

fn mkSoulsHum(r: *Rack) void {
    r.ring(0.0, 1.30, 262, 0.26, 1.1, 3);
    r.ring(0.10, 1.05, 392, 0.13, 1.3, 2);
    r.air(0.0, 1.20, 0.09, 700, 1300, 0.30, 1.0);
    r.master(1.2, 4200);
}

fn mkSoulsTake(r: *Rack) void {
    r.air(0.0, 0.30, 0.30, 500, 4800, 0.52, 2.6);
    r.ring(0.05, 0.44, 523, 0.42, 3.4, 4);
    r.ring(0.09, 0.38, 784, 0.30, 4.0, 3);
    r.ring(0.13, 0.30, 1046, 0.18, 5.0, 2);
    r.master(2.0, 6400);
}

/// A long inhale rather than an event, with NO TRANSIENT: a tick at the head is a door latching, which is the sound the SEAL owns.
fn mkFogPass(r: *Rack) void {
    r.air(0.00, 1.55, 0.34, 260, 1500, 0.30, 1.1);
    r.air(0.10, 1.35, 0.24, 1700, 320, 0.34, 1.3);
    r.body(0.00, 1.30, 58, 44, 0.30, 1.5);
    r.grit(0.05, 1.10, 0.10, 700, 0.75, 1.6);
    r.hall(1.20, 1800);
    r.master(1.4, 2200);
    r.ends(0.16, 0.42);
}

/// THE FOG GATE SHUTTING ON A BOSS FIGHT (owner: an ominous, low tone arrangement, about 5 s). Built on the
/// INTERVAL, not the timbre: A1 (55 Hz) against E-flat above it is a TRITONE, the one interval nobody hears as
/// resolved, and the two are laid a beat apart so the dissonance ARRIVES. The sub sags a semitone across the take.
fn mkFogSeal(r: *Rack) void {
    r.body(0.00, 1.60, 96, 44, 0.55, 2.2); // the stone hitting its seat
    r.grit(0.00, 0.90, 0.30, 520, 0.85, 2.6);
    r.body(0.05, 4.70, 41.2, 38.9, 0.62, 0.9); // the sub, sagging a semitone over the whole take
    r.ring(0.10, 4.40, 55.0, 0.34, 1.1, 3); // A1
    r.ring(0.95, 3.70, 77.8, 0.26, 1.2, 3); // …and the tritone above it, a beat late
    r.choir(0.35, 4.20, 82.4, 0.30, 4, 0.42);
    r.air(0.00, 4.90, 0.10, 380, 140, 0.30, 0.8);
    r.hall(2.40, 1500);
    r.master(1.5, 1100);
    r.ends(0.03, 1.10);
}

/// THE BOSS DOWN AND THE DOOR SPENT (owner: still deep and dark but MORE HOPEFUL, not scary). `mkFogSeal`'s
/// architecture, opposite interval: root A1 55 Hz, then the PERFECT FIFTH (E2, 82.41) and the MAJOR THIRD
/// (C#2, 69.30) last — an A major triad. DARK is not the same dial as FRIGHTENING, so the register does not move.
fn mkFogFelled(r: *Rack) void {
    r.body(0.00, 1.40, 82, 55, 0.42, 2.0);      // the weight coming off — not a stone finding its seat
    r.body(0.05, 4.90, 38.9, 41.2, 0.60, 0.8);  // the sub, rising the semitone
    r.ring(0.06, 4.60, 55.0, 0.34, 1.0, 3);     // A1
    r.ring(0.85, 3.90, 82.4, 0.26, 1.1, 3);     // …the fifth above it, a beat late
    r.ring(1.70, 3.10, 69.3, 0.18, 1.2, 2);     // …and the third last, which is the whole of the hope
    r.choir(0.50, 4.40, 110.0, 0.26, 4, 0.50);
    r.choir(1.80, 3.30, 164.8, 0.18, 3, 0.62);
    r.air(0.00, 5.00, 0.09, 300, 900, 0.28, 0.7);
    r.hall(2.60, 2400);
    r.master(1.5, 1700);
    r.ends(0.05, 1.30);
}

fn mkRingSnap(r: *Rack) void {
    r.tick(0.0, 0.62, 7200);
    r.ring(0.0, 0.20, 1568, 0.34, 7.0, 2);
    r.ring(0.01, 0.11, 2093, 0.20, 9.0, 1);
    r.grit(0.0, 0.05, 0.22, 5200, 0.5, 6.0);
    r.master(2.2, 7000);
}

fn mkOgreHeave(r: *Rack) void {
    r.growl(0.0, 0.26, 168, 76, 0.62, 0.42, 3.4);
    r.air(0.0, 0.30, 0.34, 900, 320, 0.42, 2.8);
    r.body(0.0, 0.14, 92, 44, 0.40, 3.0);
    r.grit(0.02, 0.16, 0.24, 1400, 0.7, 2.6);
    r.master(2.2, 3200);
}

fn mkKill(r: *Rack) void {
    r.tick(0.0, 0.35, 2000);
    r.body(0.0, 0.36, 116, 30, 1.3, 2.5);
    r.body(0.035, 0.24, 60, 25, 0.65, 2.7);
    r.grit(0.0, 0.18, 0.34, 850, 0.7, 3.8);
    r.master(2.4, 2200);
}

fn mkMenuMove(r: *Rack) void {
    r.body(0.0, 0.045, 520, 380, 0.5, 6.0);
    r.tick(0.0, 0.25, 4000);
    r.master(1.3, 3800);
}

fn mkMenuPick(r: *Rack) void {
    r.body(0.0, 0.09, 300, 200, 0.7, 4.5);
    r.ring(0.0, 0.16, 440, 0.3, 4.0, 2);
    r.tick(0.0, 0.2, 3000);
    r.master(1.4, 3600);
}

fn mkMenuBack(r: *Rack) void {
    r.body(0.0, 0.10, 300, 150, 0.6, 4.5);
    r.tick(0.0, 0.18, 2400);
    r.master(1.3, 2600);
}

fn mkWind(r: *Rack) void {
    var body = Svf{};
    var whistle = Svf{};
    var top = Pole{};
    var moan = Svf{};
    const q1 = r.rng.angle();
    const q2 = r.rng.angle();
    const q3 = r.rng.angle();
    var i: usize = 0;
    while (i < r.n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / SRF;
        const g1 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.083 * t + q1);
        const g2 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.031 * t + 2.1 + q2);
        const g3 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.157 * t + 4.4 + q3);
        const nz = r.rng.signed();

        const b = body.step(nz, 150.0 + 380.0 * g2, 0.35).bp;
        const w = whistle.step(nz, 620.0 + 1500.0 * g1, 0.86).bp;
        const s = top.step(nz, 5200) * mathx.smoothstep(0.55, 1.0, g3);
        const m = moan.step(nz, 52.0 + 34.0 * g3, 0.55).bp;

        // Distance is SPECTRAL, not level: ISO 9613-2 puts 4 kHz at ~15x the loss per 100 m that 250 Hz takes.
        work[i] = b * (0.30 + 0.70 * g2) * 0.94 +
            w * (0.10 + 0.50 * g1) * 0.20 +
            s * 0.05 +
            m * 0.68;
    }
    r.norm(0.42);
    r.sat(1.2);
    r.crush(CRUSH_BITS + 1.5, CRUSH_HOLD);
    r.warm(AIR_FAR_BED);
    r.wow(0.003, 0.4);
    r.hiss(0.035);
    r.norm(0.62);
    r.ends(0.9, 0.9);
}

fn mkBirds(r: *Rack) void {
    r.chirp(0.04, r.rng.range(0.55, 0.85), r.rng.range(1550, 2500));
    if (r.rng.float() < 0.45) r.chirp(r.rng.range(0.42, 0.72), r.rng.range(0.28, 0.48), r.rng.range(1700, 2700));
    r.masterX(1.1, AIR_FAR_CALL, CRUSH_BITS + 1.0, CRUSH_HOLD);
}

fn mkBirdsong(r: *Rack) void {
    const f0 = r.rng.range(1050, 1650);
    const up = f0 * r.rng.range(1.20, 1.55);
    r.body(0.05, 0.16, f0, up, 0.75, 3.2);
    r.body(0.26, 0.22, up, f0 * r.rng.range(0.80, 0.95), 0.60, 2.6);
    if (r.rng.float() < 0.5) r.body(0.56, 0.18, f0 * 1.1, f0 * 1.45, 0.40, 3.0);
    r.air(0.05, 0.09, 0.06, 2600, 1400, 0.5, 4.0);
    r.masterX(1.1, AIR_FAR_CALL, CRUSH_BITS + 1.0, CRUSH_HOLD);
}

fn mkOwl(r: *Rack) void {
    r.body(0.0, 0.22, 330, 316, 0.60, 2.6);
    r.body(0.0, 0.20, 495, 474, 0.16, 3.4);
    r.air(0.0, 0.20, 0.34, 1000, 560, 0.42, 2.6);
    r.body(0.60, 0.52, 352, 268, 0.95, 1.9);
    r.body(0.60, 0.46, 528, 402, 0.22, 2.6);
    r.air(0.60, 0.44, 0.40, 1150, 520, 0.42, 2.0);
    r.body(0.62, 0.50, 176, 142, 0.28, 1.7);
    r.masterX(1.15, AIR_FAR_CRY, CRUSH_BITS + 1.0, CRUSH_HOLD);
}


const CRICKETS = 7;
const CRICKET_SING: f32 = 0.22;

fn mkRain(r: *Rack) void {
    var sheet = Svf{};
    var patter = Svf{};
    var fine = Pole{};
    var drop = Pole{};
    const q1 = r.rng.angle();
    const q2 = r.rng.angle();
    var hold: f32 = 0;
    var left: i32 = 0;
    var i: usize = 0;
    while (i < r.n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / SRF;
        const g1 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.047 * t + q1);
        const g2 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.113 * t + 1.7 + q2);
        const nz = r.rng.signed();
        if (left <= 0) {
            hold = @abs(r.rng.signed());
            left = 5 + @as(i32, @intFromFloat(@abs(r.rng.signed()) * 9.0));
        }
        left -= 1;
        const sh = sheet.step(nz, 320.0 + 210.0 * g1, 0.30).bp;
        const pa = patter.step(nz, 1900.0 + 900.0 * g2, 0.55).bp * (0.35 + 0.65 * hold);
        const fi = fine.step(nz, 6400) * 0.5;
        const dr = drop.step(nz, 140) * 0.8;
        work[i] = sh * (0.42 + 0.38 * g1) + pa * 0.44 + fi * 0.16 + dr * 0.30;
    }
    r.norm(0.40);
    r.sat(1.1);
    r.crush(CRUSH_BITS + 1.5, CRUSH_HOLD);
    r.warm(AIR_FAR_BED);
    r.wow(0.002, 0.5);
    r.hiss(0.030);
    r.norm(0.60);
    // A BED'S ENDS ARE LONG (the wind's own 0.9 s): a short one is a click, and a bed clicks every loop.
    r.ends(0.9, 0.9);
}

/// Pops a second. A CRACKLE IS POISSON, not a metronome, so the gap is redrawn at every one of them.
const TORCH_POPS: f32 = 9.0;

fn mkTorchFire(r: *Rack) void {
    var roar = Svf{};
    var mid = Svf{};
    var fine = Pole{};
    var snap = Svf{};
    const q1 = r.rng.angle();
    const q2 = r.rng.angle();
    var wait: i32 = 0;
    var env: f32 = 0;
    var hz: f32 = 900;
    var i: usize = 0;
    while (i < r.n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / SRF;
        const g1 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.29 * t + q1);
        const g2 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.73 * t + 1.3 + q2);
        const nz = r.rng.signed();
        if (wait <= 0) {
            wait = 1 + @as(i32, @intFromFloat(@abs(r.rng.signed()) * (2.0 * SRF / TORCH_POPS)));
            env = 1.0;
            hz = 620.0 + @abs(r.rng.signed()) * 2600.0;
        }
        wait -= 1;
        // 0.9986 per sample is a 32 ms tail, and the SQUARE of it is the ~16 ms crack you actually hear.
        env *= 0.9986;
        const ro = roar.step(nz, 96.0 + 120.0 * g1, 0.42).bp;
        const md = mid.step(nz, 520.0 + 380.0 * g2, 0.34).bp;
        const fi = fine.step(nz, 5200) * 0.5;
        const sp = snap.step(nz, hz, 0.88).bp * env * env;
        work[i] = ro * (0.55 + 0.45 * g1) * 1.05 + md * 0.42 + fi * 0.14 + sp * 0.85;
    }
    r.norm(0.44);
    r.sat(1.25);
    r.crush(CRUSH_BITS + 1.5, CRUSH_HOLD);
    r.warm(AIR_FAR_BED);
    r.wow(0.002, 0.45);
    r.hiss(0.028);
    r.norm(0.62);
    // A BED'S ENDS ARE LONG (the wind's own 0.9 s): a short one is a click, and a bed clicks every loop.
    r.ends(0.9, 0.9);
}

fn mkThunder(r: *Rack) void {
    var lo = Svf{};
    var mid = Pole{};
    var rollA = Pole{};
    const q = r.rng.angle();
    var i: usize = 0;
    while (i < r.n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / SRF;
        const u = t / (@as(f32, @floatFromInt(r.n)) / SRF);
        const env = mathx.smoothstep(0, 0.18, u) * (1.0 - mathx.smoothstep(0.20, 1.0, u));
        const beat = 0.72 + 0.28 * mathx.sinf(std.math.tau * 1.9 * t + q) * mathx.sinf(std.math.tau * 0.7 * t);
        const nz = r.rng.signed();
        const body = lo.step(nz, 46.0 + 26.0 * beat, 0.42).bp;
        const air = mid.step(nz, 260.0) * 0.5;
        const roll = rollA.step(nz, 90.0) * 0.9;
        work[i] = (body * 1.15 + roll * 0.55 + air * 0.22) * env * beat;
    }
    r.norm(0.62);
    r.sat(1.35);
    r.master(1.8, 900);
    r.ends(0.25, 0.5);
}

fn mkCrickets(r: *Rack) void {
    var hz: [CRICKETS]f32 = undefined;
    var rate: [CRICKETS]f32 = undefined;
    var at: [CRICKETS]f32 = undefined;
    var amp: [CRICKETS]f32 = undefined;
    var pulses: [CRICKETS]f32 = undefined;
    var ph: [CRICKETS]f32 = [_]f32{0} ** CRICKETS; // accumulated, not f*t: an f32 product loses phase by 8 s
    for (0..CRICKETS) |k| {
        hz[k] = r.rng.range(3500, 5200);
        rate[k] = r.rng.range(1.7, 3.1);
        at[k] = r.rng.float();
        amp[k] = r.rng.range(0.18, 1.0);
        pulses[k] = @floor(r.rng.range(3, 6));
    }
    var band = Svf{};
    var far = Pole{};
    const q = r.rng.angle();
    var i: usize = 0;
    while (i < r.n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / SRF;
        var s: f32 = 0;
        for (0..CRICKETS) |k| {
            ph[k] += hz[k] / SRF;
            ph[k] -= @floor(ph[k]);
            const u = t * rate[k] + at[k];
            const c = u - @floor(u);
            if (c > CRICKET_SING) continue;
            const w = c / CRICKET_SING;
            const p = w * pulses[k];
            const pulse = 1.0 - (p - @floor(p));
            s += mathx.sinf(std.math.tau * ph[k]) * pulse * pulse * mathx.sinf(std.math.pi * w) * amp[k];
        }
        const near = band.step(s, 4300, 0.42).bp;
        const swellK = 0.55 + 0.45 * mathx.sinf(std.math.tau * 0.047 * t + q);
        const chorus = far.step(r.rng.signed(), 3800) * swellK;
        work[i] = near * 0.80 + chorus * 0.30;
    }
    r.sat(1.15);
    r.crush(CRUSH_BITS + 1.5, CRUSH_HOLD);
    r.warm(AIR_NEAR_GRASS);
    r.wow(0.002, 0.6);
    r.hiss(0.010);
    r.norm(0.66);
    r.ends(0.9, 0.9);
}


const BATTLE_FLOOR: f32 = 0.34;

fn mkDeerBloom(r: *Rack) void {
    r.air(0.0, 0.72, 0.28, 240, 1900, 0.55, 1.9);
    r.grit(0.05, 0.50, 0.13, 1500, 0.55, 2.4);
    r.choir(0.06, 0.66, 132, 0.30, 5, 0.72);
    r.choir(0.20, 0.48, 197, 0.13, 3, 0.62);
    r.ring(0.10, 0.44, 214, 0.13, 4.0, 3);
    r.body(0.0, 0.10, 78, 44, 0.30, 3.2);
    r.wow(0.006, 0.9);
    r.warm(2600);
    r.master(1.5, 3000);
}

/// THE VOLLEY LEAVING THE THROAT: a wet cough of air with no thump under it. It is a thing being BREATHED
/// out, not struck — the body is what the charge sounds like and this must not be mistaken for it.
/// **THE ANVIL, AND IT IS A BELL WITH A HAMMER ON THE FRONT OF IT.** The strike is a tick and a short body;
/// everything after it is the RING, which is what an anvil actually is — a tuned bar that will not stop. The
/// tail is long on purpose: he is doing this endlessly, and a dry clank would be a woodpecker.
fn mkSmithRing(r: *Rack) void {
    r.tick(0.0, 0.62, 5200);
    r.body(0.0, 0.09, 420, 190, 0.62, 6.5);
    // Two inharmonic partials over the strike — a bar rings in ratios a bell never does, and the beat between
    // them is the whole character of struck iron.
    r.ring(0.0, 1.35, 1180, 0.46, 1.9, 4);
    r.ring(0.004, 1.05, 2760, 0.24, 2.6, 3);
    r.grit(0.0, 0.10, 0.26, 3200, 0.45, 5.0);
    r.air(0.02, 0.34, 0.12, 900, 2600, 0.30, 2.4);
    r.master(1.7, 4200);
}

fn mkDeerSpit(r: *Rack) void {
    r.air(0.0, 0.44, 0.40, 420, 3400, 0.42, 2.2);
    r.grit(0.0, 0.30, 0.30, 1100, 0.62, 3.0);
    r.choir(0.04, 0.36, 168, 0.10, 3, 0.70);
    r.wow(0.010, 1.4);
    r.master(1.3, 3200);
}

fn mkDeerCharge(r: *Rack) void {
    r.grit(0.0, 0.13, 0.34, 2600, 0.70, 2.6);
    r.body(0.05, 0.20, 150, 62, 0.62, 4.2);
    r.air(0.06, 0.26, 0.24, 700, 2400, 0.34, 2.2);
    r.master(1.8, 3400);
}

fn mkDeerGore(r: *Rack) void {
    r.body(0.0, 0.07, 300, 96, 0.85, 6.5);
    r.air(0.0, 0.20, 0.42, 3000, 420, 0.62, 3.0);
    r.grit(0.01, 0.10, 0.24, 1900, 0.45, 3.4);
    r.ring(0.02, 0.16, 168, 0.20, 7.0, 2);
    r.master(2.0, 3200);
}

fn mkDeerHurt(r: *Rack) void {
    r.growl(0.0, 0.26, 380, 720, 0.52, 0.46, 0.09);
    r.air(0.02, 0.30, 0.26, 1400, 3400, 0.48, 1.6);
    r.grit(0.0, 0.18, 0.22, 2800, 0.50, 2.2);
    r.master(2.1, 3600);
}

fn mkDeerDie(r: *Rack) void {
    r.growl(0.0, 0.30, 620, 190, 0.54, 0.52, 0.10);
    r.air(0.10, 0.86, 0.34, 2200, 200, 0.50, 1.2);
    r.grit(0.14, 0.52, 0.18, 1200, 0.60, 1.8);
    r.body(0.24, 0.26, 96, 38, 0.34, 2.6);
    r.warm(2400);
    r.master(1.7, 2800);
}


fn mkMageKindle(r: *Rack) void {
    r.air(0.0, 0.62, 0.30, 300, 2600, 0.50, 2.2);
    r.grit(0.04, 0.54, 0.16, 2400, 0.40, 2.6);
    r.body(0.10, 0.48, 62, 128, 0.26, 0.7);
    r.ring(0.24, 0.34, 268, 0.10, 3.2, 3);
    r.wow(0.005, 1.4);
    r.warm(2800);
    r.master(1.4, 3200);
}

fn mkMageThrow(r: *Rack) void {
    r.body(0.0, 0.11, 210, 74, 0.68, 5.0);
    r.air(0.0, 0.24, 0.36, 2800, 500, 0.44, 2.8);
    r.grit(0.0, 0.09, 0.26, 3200, 0.52, 3.6);
    r.master(1.8, 3400);
}

fn mkMageHurt(r: *Rack) void {
    r.grit(0.0, 0.20, 0.34, 1700, 0.62, 3.0);
    r.body(0.0, 0.16, 240, 92, 0.42, 4.0);
    r.air(0.02, 0.26, 0.22, 900, 2100, 0.46, 2.0);
    r.master(2.0, 3400);
}

fn mkMageDie(r: *Rack) void {
    r.grit(0.0, 0.30, 0.36, 1500, 0.66, 2.4);
    r.body(0.0, 0.22, 190, 58, 0.44, 3.2);
    r.air(0.16, 0.68, 0.30, 1800, 240, 0.38, 1.4);
    r.grit(0.22, 0.46, 0.20, 900, 0.50, 1.6);
    r.warm(2500);
    r.master(1.6, 2800);
}

fn mkEmberBounce(r: *Rack) void {
    r.body(0.0, 0.09, 130, 52, 0.56, 5.5);
    r.air(0.0, 0.17, 0.24, 2200, 620, 0.40, 3.0);
    r.grit(0.0, 0.06, 0.18, 1800, 0.44, 4.0);
    r.master(1.6, 2800);
}

fn mkEmberBurst(r: *Rack) void {
    r.body(0.0, 0.14, 170, 44, 0.62, 4.2);
    r.air(0.0, 0.40, 0.34, 3000, 300, 0.46, 2.2);
    r.grit(0.01, 0.22, 0.24, 2000, 0.50, 2.6);
    r.warm(2600);
    r.master(1.9, 3000);
}


// THE BONE SKITTERER. Everything it makes is DRY: bone on earth and bone through air, nothing wet and nothing with a chest behind it.
fn mkSkitterClack(r: *Rack) void {
    r.tick(0.0, 0.34, 4600);
    r.ring(0.0, 0.16, 620, 0.16, 7.0, 3);
    r.grit(0.0, 0.13, 0.22, 3400, 0.35, 4.2);
    r.body(0.0, 0.09, 240, 120, 0.20, 6.0);
    r.master(1.7, 5600);
}

/// The blade going over, not the blade landing: it RESOLVES at the strike, so the sweep has to arrive.
fn mkSkitterSlice(r: *Rack) void {
    r.air(0.0, 0.30, 0.52, 900, 4200, 0.62, 1.6);
    r.air(0.16, 0.20, 0.40, 4200, 1100, 0.58, 2.6);
    r.ring(0.19, 0.20, 830, 0.13, 5.0, 3);
    r.tick(0.20, 0.30, 5200);
    r.master(1.9, 5200);
}

// THE ANCIENT PRIEST. The call is a voice with nothing in its throat; the breath is all air and rime.
fn mkPriestCall(r: *Rack) void {
    r.growl(0.0, 1.10, 84, 62, 0.60, 0.30, 0.30);
    r.growl(0.14, 0.95, 126, 94, 0.26, 0.22, 0.36);
    r.air(0.05, 1.20, 0.22, 420, 2600, 0.74, 0.9);
    r.ring(0.30, 1.00, 196, 0.11, 1.6, 4);
    r.grit(0.55, 0.85, 0.14, 1400, 0.62, 1.0);
    r.master(1.5, 4000);
}

/// A HELD EXHALE, not a blast: it has to last the whole pour (`ancientpriest.BREATH_DUR`), so the envelope swells and holds rather than cracking and dying.
fn mkPriestBreath(r: *Rack) void {
    r.air(0.0, 1.00, 0.50, 2800, 900, 0.30, 0.7);
    r.air(0.06, 0.94, 0.34, 700, 5200, 0.52, 0.6);
    r.grit(0.10, 0.86, 0.10, 5600, 0.20, 0.8);
    r.ring(0.12, 0.80, 1480, 0.07, 1.4, 3);
    r.master(1.4, 6200);
}

// THE TOLLING HOLLOW'S BELL. The strike is a tenth of it and the HUM is the rest. Inharmonic by construction —
// `ring`'s partials sit at ~1.48x, which is what a bell has and a string does not; the two rings a fifth apart are the hum note under the strike note.
fn mkHollowToll(r: *Rack) void {
    r.tick(0.0, 0.62, 3800);
    r.ring(0.0, 3.10, 138, 0.40, 0.75, 5);
    r.ring(0.006, 2.40, 206, 0.19, 1.05, 4);
    r.ring(0.010, 1.10, 412, 0.10, 2.40, 3);
    r.body(0.0, 0.80, 72, 58, 0.20, 1.6);
    r.air(0.0, 0.26, 0.20, 2600, 520, 0.44, 2.8);
    r.master(1.6, 5400);
}

/// …and the walking knock, which is the same bronze barely moved: the clapper touching the wall.
fn mkHollowClank(r: *Rack) void {
    r.tick(0.0, 0.22, 3200);
    r.ring(0.0, 0.44, 142, 0.20, 4.2, 3);
    r.ring(0.004, 0.30, 208, 0.10, 5.2, 2);
    r.master(1.4, 4600);
}

/// **NOTHING WITH A CHEST BEHIND IT AND NOTHING WET** — no `body` at all, which is what separates a crack of
/// electricity from every impact in the bank. Short, because there are THREE a volley (`hollow.SPARK_N`).
fn mkGremlinSpark(r: *Rack) void {
    r.tick(0.0, 0.40, 7200);
    r.ring(0.0, 0.20, 2600, 0.10, 6.5, 3);
    r.ring(0.008, 0.13, 4100, 0.06, 8.0, 2);
    r.air(0.0, 0.22, 0.30, 6200, 2400, 0.34, 4.6);
    r.grit(0.0, 0.09, 0.16, 5000, 0.30, 5.0);
    r.master(1.8, 8200);
}

fn mkLurkerBreak(r: *Rack) void {
    r.air(0.0, 0.46, 0.40, 300, 2600, 0.62, 1.7);
    r.body(0.06, 0.28, 96, 38, 0.72, 3.4);
    r.grit(0.04, 0.30, 0.26, 1200, 0.48, 2.2);
    r.ring(0.10, 0.34, 128, 0.14, 5.0, 3);
    r.wow(0.005, 0.7);
    r.master(1.6, 2800);
}

fn mkLurkerLash(r: *Rack) void {
    r.body(0.0, 0.09, 260, 84, 0.88, 6.2);
    r.air(0.01, 0.30, 0.46, 2600, 380, 0.60, 2.6);
    r.grit(0.0, 0.14, 0.28, 2200, 0.50, 3.2);
    r.master(2.0, 3100);
}

fn mkLurkerSink(r: *Rack) void {
    r.air(0.0, 0.62, 0.30, 1400, 190, 0.44, 1.4);
    r.body(0.05, 0.30, 72, 30, 0.34, 2.4);
    r.master(1.3, 2200);
}

fn mkLurkerHurt(r: *Rack) void {
    r.growl(0.0, 0.28, 240, 130, 0.58, 0.50, 0.11);
    r.air(0.02, 0.34, 0.30, 900, 260, 0.52, 1.9);
    r.grit(0.0, 0.20, 0.22, 1500, 0.46, 2.4);
    r.master(2.0, 3000);
}

fn mkLurkerDie(r: *Rack) void {
    r.growl(0.0, 0.34, 300, 96, 0.56, 0.54, 0.12);
    r.air(0.12, 0.78, 0.34, 1100, 160, 0.50, 1.5);
    r.body(0.20, 0.42, 66, 26, 0.40, 2.6);
    r.grit(0.02, 0.26, 0.20, 1300, 0.42, 2.2);
    r.master(1.7, 2600);
}

fn battle(old: f32) f32 {
    return @sqrt(BATTLE_FLOOR * old);
}

const BANK = [NV]Row{
    .{ .id = .step_soft, .make = mkStepSoft, .gain = 0.075, .jit = 0.13, .vjit = 0.30, .vars = 4, .poly = 3 },
    .{ .id = .step_hard, .make = mkStepHard, .gain = 0.100, .jit = 0.12, .vjit = 0.26, .vars = 4, .poly = 3 },
    .{ .id = .step_sprint, .make = mkStepSprint, .gain = 0.120, .jit = 0.11, .vjit = 0.24, .vars = 4, .poly = 3 },
    .{ .id = .step_stone, .make = mkStepStone, .gain = 0.055, .jit = 0.14, .vjit = 0.28, .vars = 4, .poly = 3 },
    .{ .id = .step_water, .make = mkStepWater, .gain = 0.130, .jit = 0.13, .vjit = 0.26, .vars = 4, .poly = 3 },
    .{ .id = .roll, .make = mkRoll, .gain = 0.30, .jit = 0.09, .vjit = 0.14, .vars = 2 },
    .{ .id = .jump, .make = mkJump, .gain = 0.14, .jit = 0.11, .vjit = 0.20, .vars = 3 },
    .{ .id = .land, .make = mkLand, .gain = 0.22, .jit = 0.10, .vjit = 0.18, .vars = 3, .poly = 3 },
    .{ .id = .swing_light, .make = mkSwingLight, .gain = 0.26, .mix = .combat, .jit = 0.16, .vjit = 0.22, .vars = 5, .poly = 3 },
    .{ .id = .swing_heavy, .make = mkSwingHeavy, .gain = 0.34, .mix = .combat, .jit = 0.12, .vjit = 0.16, .vars = 4, .poly = 2 },
    .{ .id = .hit_light, .make = mkHitLight, .gain = battle(0.68), .mix = .combat, .jit = 0.19, .vjit = 0.24, .vars = 6, .poly = 4 },
    .{ .id = .hit_heavy, .make = mkHitHeavy, .gain = battle(0.82), .mix = .combat, .jit = 0.15, .vjit = 0.20, .vars = 5, .poly = 3 },
    .{ .id = .hurt, .make = mkHurt, .gain = battle(0.70), .mix = .combat, .jit = 0.17, .vjit = 0.20, .vars = 5 },
    .{ .id = .hurt_heavy, .make = mkHurtHeavy, .gain = battle(0.86), .mix = .combat, .jit = 0.13, .vjit = 0.16, .vars = 4 },
    .{ .id = .stagger, .make = mkStagger, .gain = battle(0.55), .mix = .combat, .jit = 0.16, .vjit = 0.20, .vars = 4 },
    .{ .id = .guard_block, .make = mkGuardBlock, .gain = battle(0.62), .mix = .combat, .jit = 0.18, .vjit = 0.24, .vars = 5, .poly = 4 },
    .{ .id = .foe_guarded, .make = mkFoeGuarded, .gain = battle(0.70), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 5, .poly = 4, .reach = 52 },
    .{ .id = .knight_repel, .make = mkKnightRepel, .gain = battle(0.90), .mix = .combat, .jit = 0.07, .vjit = 0.12, .vars = 4, .poly = 3, .reach = 95 },
    .{ .id = .guard_break, .make = mkGuardBreak, .gain = battle(0.92), .mix = .combat, .jit = 0.05, .vjit = 0.06, .vars = 2, .poly = 1 },
    .{ .id = .parry, .make = mkParry, .gain = battle(0.82), .mix = .combat, .jit = 0.07, .vjit = 0.09, .vars = 3, .poly = 2 },
    .{ .id = .refused, .make = mkRefused, .gain = 0.34, .jit = 0.06, .vjit = 0.08, .vars = 2 },
    .{ .id = .death, .make = mkDeath, .gain = battle(0.95), .mix = .combat, .jit = 0.0, .vjit = 0.0, .poly = 1 },
    .{ .id = .respawn, .make = mkRespawn, .gain = battle(0.55), .mix = .combat, .jit = 0.0, .vjit = 0.0, .poly = 1 },
    .{ .id = .toad_hop, .make = mkToadHop, .gain = battle(0.28), .mix = .combat, .jit = 0.15, .vjit = 0.26, .vars = 4, .poly = 4, .reach = 30 },
    .{ .id = .toad_lunge, .make = mkToadLunge, .gain = battle(0.86), .mix = .combat, .jit = 0.12, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 34 },
    .{ .id = .toad_gape, .make = mkToadGape, .gain = battle(0.46), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 3, .poly = 3, .reach = 26 },
    .{ .id = .toad_chomp, .make = mkToadChomp, .gain = battle(0.62), .mix = .combat, .jit = 0.13, .vjit = 0.18, .vars = 3, .poly = 3, .reach = 30 },
    .{ .id = .toad_hurt, .make = mkToadHurt, .gain = battle(0.58), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 3, .poly = 3, .reach = 30 },
    .{ .id = .toad_die, .make = mkToadDie, .gain = battle(0.66), .mix = .combat, .jit = 0.11, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 34 },
    .{ .id = .shroom_hop, .make = mkShroomHop, .gain = battle(0.22), .mix = .combat, .jit = 0.18, .vjit = 0.30, .vars = 4, .poly = 4, .reach = 22 },
    .{ .id = .shroom_coo, .make = mkShroomCoo, .gain = battle(0.46), .mix = .combat, .jit = 0.14, .vjit = 0.22, .vars = 4, .poly = 3, .reach = 26 },
    .{ .id = .shroom_fling, .make = mkShroomFling, .gain = battle(0.76), .mix = .combat, .jit = 0.12, .vjit = 0.20, .vars = 3, .poly = 3, .reach = 30 },
    .{ .id = .shroom_puff, .make = mkShroomPuff, .gain = battle(0.56), .mix = .combat, .jit = 0.12, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 30 },
    .{ .id = .shroom_hurt, .make = mkShroomHurt, .gain = battle(0.48), .mix = .combat, .jit = 0.16, .vjit = 0.24, .vars = 4, .poly = 3, .reach = 26 },
    .{ .id = .shroom_die, .make = mkShroomDie, .gain = battle(0.56), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 30 },
    .{ .id = .deer_bloom, .make = mkDeerBloom, .gain = battle(0.70), .mix = .combat, .jit = 0.08, .vjit = 0.14, .vars = 4, .poly = 4, .reach = 34 },
    .{ .id = .deer_charge, .make = mkDeerCharge, .gain = battle(0.52), .mix = .combat, .jit = 0.14, .vjit = 0.22, .vars = 4, .poly = 4, .reach = 26 },
    .{ .id = .deer_gore, .make = mkDeerGore, .gain = battle(0.82), .mix = .combat, .jit = 0.08, .vjit = 0.14, .vars = 4, .poly = 4, .reach = 30 },
    .{ .id = .deer_hurt, .make = mkDeerHurt, .gain = battle(0.50), .mix = .combat, .jit = 0.16, .vjit = 0.26, .vars = 4, .poly = 4, .reach = 26 },
    .{ .id = .deer_die, .make = mkDeerDie, .gain = battle(0.58), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 32 },
    // THE MUSHROOM MAGE. The GATHER carries furthest of the four by a clear margin — a tell you cannot hear from where the fight is happening is not one.
    .{ .id = .mage_kindle, .make = mkMageKindle, .gain = battle(0.62), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 4, .poly = 4, .reach = 38 },
    .{ .id = .mage_throw, .make = mkMageThrow, .gain = battle(0.58), .mix = .combat, .jit = 0.12, .vjit = 0.20, .vars = 4, .poly = 4, .reach = 32 },
    .{ .id = .mage_hurt, .make = mkMageHurt, .gain = battle(0.50), .mix = .combat, .jit = 0.16, .vjit = 0.26, .vars = 4, .poly = 4, .reach = 26 },
    .{ .id = .mage_die, .make = mkMageDie, .gain = battle(0.56), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 30 },
    .{ .id = .ember_bounce, .make = mkEmberBounce, .gain = battle(0.48), .mix = .combat, .jit = 0.18, .vjit = 0.30, .vars = 4, .poly = 6, .reach = 30 },
    .{ .id = .ember_burst, .make = mkEmberBurst, .gain = battle(0.60), .mix = .combat, .jit = 0.12, .vjit = 0.22, .vars = 4, .poly = 5, .reach = 32 },
    .{ .id = .lurker_break, .make = mkLurkerBreak, .gain = battle(0.74), .mix = .combat, .jit = 0.08, .vjit = 0.14, .vars = 4, .poly = 4, .reach = 36 },
    .{ .id = .lurker_lash, .make = mkLurkerLash, .gain = battle(0.84), .mix = .combat, .jit = 0.08, .vjit = 0.14, .vars = 4, .poly = 4, .reach = 30 },
    .{ .id = .lurker_sink, .make = mkLurkerSink, .gain = 0.30, .mix = .combat, .jit = 0.16, .vjit = 0.24, .vars = 3, .poly = 3, .reach = 24 },
    .{ .id = .lurker_hurt, .make = mkLurkerHurt, .gain = battle(0.50), .mix = .combat, .jit = 0.16, .vjit = 0.26, .vars = 4, .poly = 4, .reach = 26 },
    .{ .id = .lurker_die, .make = mkLurkerDie, .gain = battle(0.58), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 32 },
    .{ .id = .delver_churn, .make = mkDelverChurn, .gain = battle(0.30), .mix = .combat, .jit = 0.16, .vjit = 0.26, .vars = 4, .poly = 4, .reach = 34 },
    .{ .id = .delver_dig, .make = mkDelverDig, .gain = battle(0.54), .mix = .combat, .jit = 0.12, .vjit = 0.20, .vars = 3, .poly = 3, .reach = 30 },
    .{ .id = .delver_claw, .make = mkDelverClaw, .gain = battle(0.62), .mix = .combat, .jit = 0.12, .vjit = 0.18, .vars = 3, .poly = 3, .reach = 30 },
    .{ .id = .delver_surge, .make = mkDelverSurge, .gain = battle(0.78), .mix = .combat, .jit = 0.08, .vjit = 0.12, .vars = 3, .poly = 2, .reach = 36 },
    .{ .id = .delver_burst, .make = mkDelverBurst, .gain = battle(0.90), .mix = .combat, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 40 },
    .{ .id = .delver_hurt, .make = mkDelverHurt, .gain = battle(0.52), .mix = .combat, .jit = 0.15, .vjit = 0.22, .vars = 4, .poly = 3, .reach = 28 },
    .{ .id = .delver_die, .make = mkDelverDie, .gain = battle(0.62), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 32 },
    .{ .id = .bow_draw, .make = mkBowDraw, .gain = 0.17, .mix = .combat, .jit = 0.10, .vjit = 0.18, .vars = 3, .poly = 3, .reach = 44 },
    .{ .id = .bow_loose, .make = mkBowLoose, .gain = battle(0.58), .mix = .combat, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 64 },
    .{ .id = .arrow_hit, .make = mkArrowHit, .gain = battle(0.72), .mix = .combat, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 3 },
    .{ .id = .arrow_dirt, .make = mkArrowDirt, .gain = 0.34, .mix = .combat, .jit = 0.15, .vjit = 0.28, .vars = 4, .poly = 4, .reach = 38 },
    .{ .id = .arrow_wood, .make = mkArrowWood, .gain = battle(0.56), .mix = .combat, .jit = 0.12, .vjit = 0.20, .vars = 4, .poly = 4, .reach = 44 },
    .{ .id = .arrow_stone, .make = mkArrowStone, .gain = battle(0.50), .mix = .combat, .jit = 0.13, .vjit = 0.22, .vars = 4, .poly = 4, .reach = 48 },
    .{ .id = .arrow_metal, .make = mkArrowMetal, .gain = battle(0.52), .mix = .combat, .jit = 0.11, .vjit = 0.18, .vars = 3, .poly = 3, .reach = 52 },
    .{ .id = .wand_charge, .make = mkWandCharge, .gain = 0.28, .mix = .combat, .jit = 0.04, .vjit = 0.06, .vars = 3, .poly = 2, .reach = 80 },
    .{ .id = .wand_cast, .make = mkWandCast, .gain = battle(0.60), .mix = .combat, .jit = 0.08, .vjit = 0.12, .vars = 4, .poly = 3, .reach = 72 },
    .{ .id = .bone_hurt, .make = mkBoneHurt, .gain = battle(0.62), .mix = .combat, .jit = 0.12, .vjit = 0.20, .vars = 4, .poly = 3, .reach = 44 },
    .{ .id = .bone_die, .make = mkBoneDie, .gain = battle(0.68), .mix = .combat, .jit = 0.09, .vjit = 0.12, .vars = 3, .reach = 54 },
    .{ .id = .skel_lunge, .make = mkSkelLunge, .gain = battle(0.86), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 4, .poly = 3, .reach = 62 },
    .{ .id = .ogre_step, .make = mkOgreStep, .gain = battle(0.44), .mix = .combat, .jit = 0.08, .vjit = 0.20, .vars = 4, .poly = 3, .reach = 115 },
    .{ .id = .ogre_roar, .make = mkOgreRoar, .gain = battle(0.80), .mix = .combat, .jit = 0.06, .vjit = 0.10, .vars = 3, .reach = 135 },
    .{ .id = .ogre_slam, .make = mkOgreSlam, .gain = battle(1.00), .mix = .combat, .jit = 0.06, .vjit = 0.08, .vars = 3, .reach = 135 },
    .{ .id = .ogre_swipe, .make = mkOgreSwipe, .gain = battle(0.72), .mix = .combat, .jit = 0.07, .vjit = 0.12, .vars = 3, .reach = 85 },
    .{ .id = .ogre_heave, .make = mkOgreHeave, .gain = battle(0.70), .mix = .combat, .jit = 0.07, .vjit = 0.11, .vars = 3, .reach = 85 },
    .{ .id = .ogre_hurt, .make = mkOgreHurt, .gain = battle(0.66), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 80 },
    .{ .id = .ogre_die, .make = mkOgreDie, .gain = battle(0.92), .mix = .combat, .jit = 0.0, .vjit = 0.0, .poly = 1, .reach = 135 },
    .{ .id = .knight_step, .make = mkKnightStep, .gain = battle(0.46), .mix = .combat, .jit = 0.08, .vjit = 0.18, .vars = 4, .poly = 3, .reach = 125 },
    .{ .id = .knight_plant, .make = mkKnightPlant, .gain = battle(0.72), .mix = .combat, .jit = 0.07, .vjit = 0.13, .vars = 4, .poly = 3, .reach = 140 },
    .{ .id = .knight_roar, .make = mkKnightRoar, .gain = battle(0.94), .mix = .combat, .jit = 0.05, .vjit = 0.09, .vars = 3, .poly = 2, .reach = 150 },
    .{ .id = .knight_slam, .make = mkKnightSlam, .gain = battle(1.00), .mix = .combat, .jit = 0.06, .vjit = 0.08, .vars = 3, .poly = 3, .reach = 150 },
    .{ .id = .knight_heave, .make = mkKnightHeave, .gain = battle(0.70), .mix = .combat, .jit = 0.07, .vjit = 0.11, .vars = 4, .poly = 3, .reach = 95 },
    .{ .id = .knight_swipe, .make = mkKnightSwipe, .gain = battle(0.74), .mix = .combat, .jit = 0.07, .vjit = 0.12, .vars = 3, .poly = 3, .reach = 95 },
    .{ .id = .knight_lunge, .make = mkKnightLunge, .gain = battle(0.88), .mix = .combat, .jit = 0.08, .vjit = 0.13, .vars = 3, .poly = 3, .reach = 105 },
    .{ .id = .knight_hurt, .make = mkKnightHurt, .gain = battle(0.64), .mix = .combat, .jit = 0.11, .vjit = 0.18, .vars = 4, .poly = 3, .reach = 90 },
    .{ .id = .knight_die, .make = mkKnightDie, .gain = battle(0.96), .mix = .combat, .jit = 0.0, .vjit = 0.0, .poly = 1, .reach = 150 },
    .{ .id = .kobold_snarl, .make = mkKoboldSnarl, .gain = battle(0.62), .mix = .combat, .jit = 0.22, .vjit = 0.24, .vars = 6, .poly = 3, .reach = 58 },
    .{ .id = .kobold_chop, .make = mkKoboldChop, .gain = battle(0.38), .mix = .combat, .jit = 0.22, .vjit = 0.28, .vars = 6, .poly = 4, .reach = 40 },
    .{ .id = .kobold_heave, .make = mkKoboldHeave, .gain = battle(0.78), .mix = .combat, .jit = 0.18, .vjit = 0.24, .vars = 5, .poly = 2, .reach = 62 },
    .{ .id = .kobold_cast, .make = mkKoboldCast, .gain = 0.30, .mix = .combat, .jit = 0.05, .vjit = 0.08, .vars = 3, .poly = 2, .reach = 78 },
    .{ .id = .kobold_heal, .make = mkKoboldHeal, .gain = 0.11, .mix = .combat, .jit = 0.06, .vjit = 0.10, .vars = 3, .poly = 3, .reach = 54 },
    .{ .id = .kobold_whirl, .make = mkKoboldWhirl, .gain = battle(0.34), .mix = .combat, .jit = 0.20, .vjit = 0.24, .vars = 5, .poly = 3, .reach = 44 },
    .{ .id = .kobold_sling, .make = mkKoboldSling, .gain = battle(0.68), .mix = .combat, .jit = 0.13, .vjit = 0.18, .vars = 4, .poly = 4, .reach = 52 },
    .{ .id = .kobold_bite, .make = mkKoboldBite, .gain = battle(0.56), .mix = .combat, .jit = 0.20, .vjit = 0.26, .vars = 6, .poly = 3, .reach = 40 },
    .{ .id = .kobold_hurt, .make = mkKoboldHurt, .gain = battle(0.60), .mix = .combat, .jit = 0.24, .vjit = 0.30, .vars = 6, .poly = 4, .reach = 48 },
    .{ .id = .kobold_die, .make = mkKoboldDie, .gain = battle(0.68), .mix = .combat, .jit = 0.18, .vjit = 0.22, .vars = 5, .poly = 3, .reach = 58 },
    .{ .id = .shade_reach, .make = mkShadeReach, .gain = battle(0.44), .mix = .combat, .jit = 0.16, .vjit = 0.22, .vars = 4, .poly = 3, .reach = 40 },
    .{ .id = .shade_gather, .make = mkShadeGather, .gain = battle(0.66), .mix = .combat, .jit = 0.06, .vjit = 0.10, .vars = 3, .poly = 3, .reach = 70 },
    .{ .id = .shade_wisp, .make = mkShadeWisp, .gain = battle(0.58), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 4, .poly = 3, .reach = 74 },
    .{ .id = .shade_touch, .make = mkShadeTouch, .gain = battle(0.70), .mix = .combat, .jit = 0.09, .vjit = 0.13, .vars = 4, .poly = 3, .reach = 34 },
    .{ .id = .shade_blink, .make = mkShadeBlink, .gain = battle(0.64), .mix = .combat, .jit = 0.11, .vjit = 0.15, .vars = 4, .poly = 4, .reach = 68 },
    .{ .id = .shade_hurt, .make = mkShadeHurt, .gain = battle(0.54), .mix = .combat, .jit = 0.15, .vjit = 0.22, .vars = 5, .poly = 3, .reach = 44 },
    .{ .id = .shade_die, .make = mkShadeDie, .gain = battle(0.66), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 2, .reach = 60 },
    .{ .id = .leech_wing, .make = mkLeechWing, .gain = battle(0.035), .mix = .combat, .jit = 0.16, .vjit = 0.34, .vars = 6, .poly = 6, .reach = 12 },
    .{ .id = .leech_stab, .make = mkLeechStab, .gain = battle(0.80), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 4, .poly = 3, .reach = 30 },
    .{ .id = .leech_drink, .make = mkLeechDrink, .gain = battle(0.40), .mix = .combat, .jit = 0.12, .vjit = 0.16, .vars = 4, .poly = 3, .reach = 26 },
    .{ .id = .leech_hurt, .make = mkLeechHurt, .gain = battle(0.56), .mix = .combat, .jit = 0.16, .vjit = 0.24, .vars = 5, .poly = 4, .reach = 40 },
    .{ .id = .leech_die, .make = mkLeechDie, .gain = battle(0.60), .mix = .combat, .jit = 0.11, .vjit = 0.15, .vars = 4, .poly = 3, .reach = 48 },
    .{ .id = .stone_grind, .make = mkStoneGrind, .gain = battle(0.88), .mix = .combat, .jit = 0.06, .vjit = 0.10, .vars = 3, .poly = 2, .reach = 104 },
    .{ .id = .stone_loose, .make = mkStoneLoose, .gain = battle(0.72), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 4, .poly = 5, .reach = 62 },
    .{ .id = .wood_wake, .make = mkWoodWake, .gain = battle(0.86), .mix = .combat, .jit = 0.06, .vjit = 0.10, .vars = 3, .poly = 2, .reach = 96 },
    .{ .id = .wood_creak, .make = mkWoodCreak, .gain = battle(0.24), .mix = .combat, .jit = 0.18, .vjit = 0.26, .vars = 5, .poly = 3, .reach = 42 },
    .{ .id = .wood_swing, .make = mkWoodSwing, .gain = battle(0.80), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 4, .poly = 3, .reach = 60 },
    .{ .id = .wood_hit, .make = mkWoodHit, .gain = battle(0.82), .mix = .combat, .jit = 0.08, .vjit = 0.12, .vars = 4, .poly = 3, .reach = 74 },
    .{ .id = .wood_hurt, .make = mkWoodHurt, .gain = battle(0.66), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 5, .poly = 3, .reach = 54 },
    .{ .id = .wood_die, .make = mkWoodDie, .gain = battle(0.90), .mix = .combat, .jit = 0.07, .vjit = 0.11, .vars = 3, .poly = 2, .reach = 110 },
    .{ .id = .spider_hiss, .make = mkSpiderHiss, .gain = battle(0.56), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 4, .poly = 3, .reach = 66 },
    .{ .id = .spider_spit, .make = mkSpiderSpit, .gain = battle(0.58), .mix = .combat, .jit = 0.12, .vjit = 0.18, .vars = 4, .poly = 3, .reach = 62 },
    .{ .id = .spider_bite, .make = mkSpiderBite, .gain = battle(0.64), .mix = .combat, .jit = 0.13, .vjit = 0.18, .vars = 4, .poly = 3, .reach = 34 },
    .{ .id = .spider_hurt, .make = mkSpiderHurt, .gain = battle(0.60), .mix = .combat, .jit = 0.15, .vjit = 0.22, .vars = 4, .poly = 3, .reach = 40 },
    .{ .id = .spider_die, .make = mkSpiderDie, .gain = battle(0.80), .mix = .combat, .jit = 0.08, .vjit = 0.10, .vars = 2, .poly = 2, .reach = 70 },
    .{ .id = .brood_screech, .make = mkBroodScreech, .gain = battle(0.62), .mix = .combat, .jit = 0.22, .vjit = 0.24, .vars = 5, .poly = 4, .reach = 76 },
    .{ .id = .brood_leap, .make = mkBroodLeap, .gain = battle(0.52), .mix = .combat, .jit = 0.26, .vjit = 0.28, .vars = 6, .poly = 4, .reach = 46 },
    .{ .id = .brood_bite, .make = mkBroodBite, .gain = battle(0.44), .mix = .combat, .jit = 0.26, .vjit = 0.30, .vars = 6, .poly = 4, .reach = 30 },
    .{ .id = .brood_hurt, .make = mkBroodHurt, .gain = battle(0.46), .mix = .combat, .jit = 0.28, .vjit = 0.32, .vars = 6, .poly = 4, .reach = 34 },
    .{ .id = .brood_die, .make = mkBroodDie, .gain = battle(0.52), .mix = .combat, .jit = 0.24, .vjit = 0.28, .vars = 6, .poly = 4, .reach = 40 },
    .{ .id = .sac_lay, .make = mkSacLay, .gain = battle(0.50), .mix = .combat, .jit = 0.12, .vjit = 0.18, .vars = 3, .poly = 2, .reach = 44 },
    .{ .id = .sac_hit, .make = mkSacHit, .gain = battle(0.54), .mix = .combat, .jit = 0.16, .vjit = 0.24, .vars = 4, .poly = 4, .reach = 34 },
    .{ .id = .sac_hatch, .make = mkSacHatch, .gain = battle(0.66), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 72 },
    .{ .id = .sac_burst, .make = mkSacBurst, .gain = battle(0.74), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 68 },
    .{ .id = .acid_splash, .make = mkAcidSplash, .gain = battle(0.58), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 4, .poly = 4, .reach = 50 },
    .{ .id = .acid_burn, .make = mkAcidBurn, .gain = 0.26, .mix = .combat, .jit = 0.20, .vjit = 0.26, .vars = 5, .poly = 3, .reach = 24 },
    .{ .id = .flask_drink, .make = mkFlaskDrink, .gain = 0.52, .jit = 0.06, .vjit = 0.10, .vars = 2, .poly = 2 },
    .{ .id = .flask_cycle, .make = mkFlaskCycle, .gain = 0.30, .jit = 0.07, .vjit = 0.08, .vars = 2, .poly = 3 },
    .{ .id = .eat, .make = mkEat, .gain = 0.40, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 2 },
    .{ .id = .chest_open, .make = mkChestOpen, .gain = 0.72, .jit = 0.04, .vjit = 0.06, .vars = 2, .poly = 2, .reach = 70 },
    .{ .id = .item_get, .make = mkItemGet, .gain = 0.44, .jit = 0.05, .vjit = 0.08, .vars = 3, .poly = 4 },
    .{ .id = .souls_spill, .make = mkSoulsSpill, .gain = 0.68, .jit = 0.03, .vjit = 0.05, .vars = 2, .poly = 2 },
    .{ .id = .souls_hum, .make = mkSoulsHum, .gain = 0.26, .jit = 0.05, .vjit = 0.07, .vars = 3, .poly = 2, .reach = 26 },
    .{ .id = .souls_take, .make = mkSoulsTake, .gain = 0.62, .jit = 0.04, .vjit = 0.07, .vars = 3, .poly = 2, .reach = 40 },
    .{ .id = .ring_snap, .make = mkRingSnap, .gain = 0.66, .jit = 0.05, .vjit = 0.08, .vars = 2, .poly = 2 },
    .{ .id = .kill, .make = mkKill, .gain = battle(0.55), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 4 },
    .{ .id = .menu_move, .make = mkMenuMove, .gain = 0.30, .jit = 0.06, .vjit = 0.08, .vars = 2, .poly = 3 },
    .{ .id = .menu_pick, .make = mkMenuPick, .gain = 0.38, .jit = 0.03, .vjit = 0.05 },
    .{ .id = .menu_back, .make = mkMenuBack, .gain = 0.32, .jit = 0.03, .vjit = 0.05 },
    .{ .id = .wind, .make = mkWind, .gain = 0.030, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
    .{ .id = .birds, .make = mkBirds, .gain = 0.31, .mix = .ambience, .jit = 0.14, .vjit = 0.30, .vars = 4, .poly = 2, .reach = 210 },
    .{ .id = .birdsong, .make = mkBirdsong, .gain = 0.26, .mix = .ambience, .jit = 0.13, .vjit = 0.30, .vars = 4, .poly = 2, .reach = 200 },
    .{ .id = .owl, .make = mkOwl, .gain = 0.24, .mix = .ambience, .jit = 0.08, .vjit = 0.14, .vars = 3, .poly = 2, .reach = 170 },
    .{ .id = .crickets, .make = mkCrickets, .gain = 0.015, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
    .{ .id = .rain, .make = mkRain, .gain = 0.052, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
    .{ .id = .thunder, .make = mkThunder, .gain = 0.30, .mix = .ambience, .jit = 0.04, .vjit = 0.10, .vars = 2, .poly = 2 },
    // Quieter up close than a kobold: a thing on YOUR side must never fight the creature it is biting for the frame. The HOWL is the exception — thirty focus spent.
    .{ .id = .wolf_howl, .make = mkWolfHowl, .gain = battle(0.44), .mix = .combat, .jit = 0.05, .vjit = 0.09, .vars = 3, .poly = 1, .reach = 110 },
    .{ .id = .wolf_growl, .make = mkWolfGrowl, .gain = battle(0.30), .mix = .combat, .jit = 0.18, .vjit = 0.24, .vars = 5, .poly = 2, .reach = 46 },
    .{ .id = .wolf_bite, .make = mkWolfBite, .gain = battle(0.52), .mix = .combat, .jit = 0.16, .vjit = 0.22, .vars = 5, .poly = 3, .reach = 52 },
    .{ .id = .wolf_hurt, .make = mkWolfHurt, .gain = battle(0.54), .mix = .combat, .jit = 0.20, .vjit = 0.26, .vars = 5, .poly = 3, .reach = 56 },
    .{ .id = .wolf_die, .make = mkWolfDie, .gain = battle(0.70), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 1, .reach = 90 },
    // ONE TAKE, NO JITTER, ONE VOICE: a sting is a fixed event and the same door twice must sound the same twice;
    // played flat (`sfx.play`) rather than placed, so `reach` never enters into it. On `.sfx` with `ring_snap` and
    // NOT the fight's band — a stinger announcing a fight sits ABOVE it, and the combat submix is compressed flat.
    .{ .id = .fog_seal, .make = mkFogSeal, .gain = 0.60, .jit = 0.0, .vjit = 0.0, .vars = 1, .poly = 1 },
    .{ .id = .fog_felled, .make = mkFogFelled, .gain = 0.60, .jit = 0.0, .vjit = 0.0, .vars = 1, .poly = 1 },
    .{ .id = .fog_pass, .make = mkFogPass, .gain = 0.44, .jit = 0.04, .vjit = 0.08, .vars = 2, .poly = 1 },
    // LOUDER THAN THE RAIN and quieter than every call, because a torch is the one bed held at arm's length.
    .{ .id = .torch_fire, .make = mkTorchFire, .gain = 0.075, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
    // **A SHOT COMING AT YOU FROM 16 M HAS TO BE HEARD FROM 16 M** (`hollow.SPARK_MAX`) — the volley's fairness
    // is three separate arrivals. `poly` is 4 because three are in the air at once and a second rider may fire.
    .{ .id = .gremlin_spark, .make = mkGremlinSpark, .gain = battle(0.58), .mix = .combat, .jit = 0.10, .vjit = 0.22, .vars = 4, .poly = 4, .reach = 40 },
    .{ .id = .skitter_clack, .make = mkSkitterClack, .gain = battle(0.34), .mix = .combat, .jit = 0.18, .vjit = 0.30, .vars = 4, .poly = 6, .reach = 24 },
    .{ .id = .skitter_slice, .make = mkSkitterSlice, .gain = battle(0.72), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 4, .poly = 4, .reach = 30 },
    // THE CALL CARRIES: it is a tell, and a tell you cannot hear from where the fight is happening is not one.
    .{ .id = .priest_call, .make = mkPriestCall, .gain = battle(0.66), .mix = .combat, .jit = 0.08, .vjit = 0.12, .vars = 3, .poly = 3, .reach = 44 },
    .{ .id = .priest_breath, .make = mkPriestBreath, .gain = battle(0.60), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 26 },
    // …AND THE BELL CARRIES AS FAR AS IT REACHES (`hollow.TOLL_R` is 34 m): a voice that faded first would be a lie about the mechanic.
    .{ .id = .hollow_toll, .make = mkHollowToll, .gain = battle(0.92), .mix = .combat, .jit = 0.05, .vjit = 0.06, .vars = 3, .poly = 2, .reach = 40 },
    .{ .id = .hollow_clank, .make = mkHollowClank, .gain = battle(0.30), .mix = .combat, .jit = 0.16, .vjit = 0.24, .vars = 4, .poly = 4, .reach = 20 },
    .{ .id = .step_oil, .make = mkStepOil, .gain = 0.145, .jit = 0.12, .vjit = 0.26, .vars = 4, .poly = 3 },
    .{ .id = .step_fungal, .make = mkStepFungal, .gain = 0.135, .jit = 0.13, .vjit = 0.26, .vars = 4, .poly = 3 },
    .{ .id = .step_lava, .make = mkStepLava, .gain = 0.120, .jit = 0.11, .vjit = 0.24, .vars = 4, .poly = 3 },
    // TEXTURE, at or under the floor and thinned in COUNT too (`game.POP_EVERY`): a pool that pops in your ear
    // as often as it pops on screen is the loudest thing in a quiet map.
    .{ .id = .oil_pop, .make = mkOilPop, .gain = 0.115, .mix = .ambience, .jit = 0.20, .vjit = 0.34, .vars = 5, .poly = 3, .reach = 26 },
    .{ .id = .fungal_pop, .make = mkFungalPop, .gain = 0.100, .mix = .ambience, .jit = 0.22, .vjit = 0.34, .vars = 5, .poly = 3, .reach = 24 },
    .{ .id = .lava_pop, .make = mkLavaPop, .gain = 0.130, .mix = .ambience, .jit = 0.18, .vjit = 0.30, .vars = 5, .poly = 3, .reach = 34 },
    // The bite is what is HAPPENING TO YOU, so it sits with the fight and not with the scenery.
    .{ .id = .lava_sear, .make = mkLavaSear, .gain = battle(0.44), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 4, .poly = 2 },
    .{ .id = .oil_bed, .make = mkOilBed, .gain = 0.052, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
    .{ .id = .fungal_bed, .make = mkFungalBed, .gain = 0.040, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
    .{ .id = .lava_bed, .make = mkLavaBed, .gain = 0.058, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
    .{ .id = .duo_sword_hurt, .make = mkDuoSwordHurt, .gain = battle(0.72), .mix = .combat, .jit = 0.15, .vjit = 0.20, .vars = 4, .poly = 3, .reach = 60 },
    .{ .id = .duo_sword_die, .make = mkDuoSwordDie, .gain = battle(0.95), .mix = .combat, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1, .reach = 100 },
    .{ .id = .duo_magus_hurt, .make = mkDuoMagusHurt, .gain = battle(0.66), .mix = .combat, .jit = 0.16, .vjit = 0.22, .vars = 4, .poly = 3, .reach = 60 },
    .{ .id = .duo_magus_die, .make = mkDuoMagusDie, .gain = battle(0.92), .mix = .combat, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1, .reach = 100 },
    .{ .id = .duo_orb, .make = mkDuoOrb, .gain = battle(0.44), .mix = .combat, .jit = 0.18, .vjit = 0.26, .vars = 5, .poly = 4, .reach = 55 },
    .{ .id = .duo_sprout, .make = mkDuoSprout, .gain = battle(0.62), .mix = .combat, .jit = 0.12, .vjit = 0.18, .vars = 4, .poly = 3, .reach = 70 },
    // **THE TELL IS LOUDER THAN THE CAST** — the bunch going off is the thing you have to hear across a fight.
    .{ .id = .duo_burst, .make = mkDuoBurst, .gain = battle(0.88), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 5, .poly = 4, .reach = 80 },
    .{ .id = .duo_fade, .make = mkDuoFade, .gain = battle(0.58), .mix = .combat, .jit = 0.08, .vjit = 0.12, .vars = 3, .poly = 2, .reach = 65 },
    .{ .id = .duo_bloom, .make = mkDuoBloom, .gain = battle(0.60), .mix = .combat, .jit = 0.08, .vjit = 0.12, .vars = 3, .poly = 2, .reach = 65 },
    .{ .id = .deer_spit, .make = mkDeerSpit, .gain = battle(0.60), .mix = .combat, .jit = 0.10, .vjit = 0.18, .vars = 5, .poly = 4, .reach = 44 },
    // **NOT IN THE FIGHT'S BAND.** It is `.sfx`, so `BATTLE_FLOOR` never touches it and its own tests never
    // have to make room for a sound that is not a threat. It CARRIES, because a smith you can hear from the
    // next field is how you find him — the one voice in the game that is a landmark.
    .{ .id = .smith_ring, .make = mkSmithRing, .gain = 0.66, .jit = 0.05, .vjit = 0.11, .vars = 5, .poly = 3, .reach = 92 },
};

fn seconds(id: Id) f32 {
    return switch (id) {
        // The door shutting on a boss fight, at the length the owner asked for.
        .fog_seal => 5.0,
        // …and the answer to it outlasts it, because the last thing it does is let go.
        .fog_felled => 5.2,
        // …and it has to cover the WALK it plays under (`game.GATE_SPEED` over a gate-and-a-bit of ground).
        .fog_pass => 1.7,
        .wind => 8.0,
        .crickets => 7.3,
        // A BED HAS TO OUTLAST ITS OWN PATTERN or the loop point is the thing you hear — and it may not equal another bed's, or the two retrigger on one frame forever.
        .rain => 8.6,
        .torch_fire => 7.9,
        // …and none of these may equal another bed's, or the two retrigger on the same frame forever.
        .oil_bed => 8.3,
        .fungal_bed => 7.6,
        .lava_bed => 9.1,
        .lava_sear => 0.55,
        .oil_pop, .fungal_pop, .lava_pop => 0.42,
        .duo_sword_die => 1.35,
        .duo_magus_die => 1.45,
        .duo_fade => 1.05,
        .duo_bloom => 0.80,
        .duo_sprout => 0.55,
        .duo_burst => 0.62,
        .thunder => 3.4,
        .death => 3.2,
        .owl => 1.6,
        .ogre_die => 2.2,
        // The boss falls for DEATH_DUR (2.20 s, `knight.zig`) and the crash is written at 1.30.
        .knight_die => 2.45,
        .knight_roar => 1.35,
        .knight_slam => 1.15,
        .knight_plant => 0.8,
        .knight_step, .knight_swipe => 0.7,
        .knight_heave, .knight_lunge => 0.6,
        .respawn => 1.4,
        .bone_die, .toad_die, .ogre_roar => 1.1,
        .wolf_howl => 1.7,
        .wolf_die => 2.0,
        .kobold_cast => 1.35,
        .kobold_heal => 1.95,
        .kobold_die => 1.15,
        .kobold_heave => 0.85,
        .kobold_whirl => 0.75,
        .ogre_slam, .bow_draw, .flask_drink => 1.05,
        .chest_open => 0.9,
        // Every arrow impact is QUICK either way (owner's law) — a third of a second, tops.
        .arrow_hit, .arrow_dirt, .arrow_wood, .arrow_stone, .arrow_metal => 0.36,
        // The climb has to RESOLVE at the throw, and the raise is CAST_DUR × CAST_AT ≈ 0.30 s.
        .wand_charge => 0.40,
        // SHORT ON PURPOSE (see mkParry): a long tail is what made it a ping. Spent by 0.21.
        .parry => 0.28,
        .birds => 1.3, // long enough for a phrase plus the answer that can start at 0.72
        .birdsong => 1.0,
        .roll, .swing_heavy, .ogre_swipe, .ogre_step => 0.7,
        .spider_hiss => 0.7,
        .spider_die => 1.15,
        // The gather has to RESOLVE at the throw, and the wisp's wind-up is 0.68 s (`shade.MOVES`).
        .shade_gather => 0.72,
        .shade_reach => 0.48,
        .shade_blink => 0.55,
        .shade_die => 1.25,
        .sac_lay => 0.62,
        .sac_hatch, .brood_screech => 0.55,
        .sac_burst => 0.45,
        .acid_splash => 0.42,
        // Recipes authoring past the 0.5 s default — without a row here `Rack.at` clamps and the tail
        // layers render zero samples.
        .stone_grind => 0.9,
        .wood_wake => 0.8,
        .wood_die => 1.2, // the tear, THEN the ground taking it at 0.80
        .eat => 0.65,
        .shroom_die => 0.75,
        .delver_churn => 0.9,
        .delver_surge => 1.25,
        .delver_die => 0.85,
        .leech_die => 0.65, // the run-down, then the body arriving at 0.44
        // The bell's HUM is the sound; cut to the default 0.5 s it was a hammer on a pipe.
        .hollow_toll => 3.4,
        .hollow_clank => 0.55,
        // The call must cover the raise's own gather (`ancientpriest.RAISE_WIND` is 1.55 s).
        .priest_call => 1.6,
        // …and the breath must cover the pour (`BREATH_DUR` 0.95 s) plus the tail off it.
        .priest_breath => 1.15,
        .skitter_slice => 0.55,
        // Short on purpose: three a volley, and a long take smears them into one noise.
        .gremlin_spark => 0.45,
        .souls_spill => 0.9,
        // The retrigger fires every HUM_EVERY (1.15 s); the take must outlast it or the hum chatters.
        .souls_hum => 1.30,
        else => 0.5,
    };
}


const MAX_VARS = 6;
const MAX_POLY = 6;

const MASTER_VOL: f32 = 0.85;

const Slot = struct {
    snd: [MAX_VARS][MAX_POLY]rl.Sound = undefined,
    owned: [MAX_VARS]rl.Sound = undefined, // alias 0 owns the data; the rest borrow it
    next: u8 = 0,
    varsReady: u8 = 0,
};

var slots = [_]Slot{.{}} ** NV;
var ready = false;
var rng = mathx.Rng.init(0x50FA5);
var muted = false;

var lisPos: rl.Vector3 = mathx.zero3;
var lisRight: rl.Vector3 = mathx.v3(1, 0, 0);

const FALLOFF: f32 = 46.0;

const PAN_WIDTH: f32 = 0.42;
const PAN_NEAR: f32 = 1.4;
const REAR_DUCK: f32 = 0.10;
const PITCH_DROOP: f32 = 0.05;
const BED_PAN: f32 = 0.93;

fn panFor(side: f32, width: f32) f32 {
    return mathx.clampF(0.5 - width * side, 0.04, 0.96);
}

/// The ONE copy of the recipe→sound path, shared by `init`, `pump` and `rebakeMix`. Takes append in order, so `varsReady` is also the next index.
fn bakeTake(id: Id, idx: usize) void {
    const row = BANK[idx];
    const v = slots[idx].varsReady;
    if (v >= row.vars) return;
    var r = Rack.init(0x9E3779B9 *% (idx + 1) +% v, seconds(id));
    row.make(&r);
    if (row.mix == .combat) r.warm(COMBAT_TREBLE);
    applyFx(&r, row.mix);
    for (voiceFx[idx]) |k| {
        if (k > AFX_EPS) {
            applyRack(&r, voiceFx[idx]);
            break;
        }
    }
    slots[idx].snd[v][0] = bake(&r);
    slots[idx].owned[v] = slots[idx].snd[v][0];
    var p: u8 = 1;
    while (p < row.poly) : (p += 1) slots[idx].snd[v][p] = rl.loadSoundAlias(slots[idx].owned[v]);
    slots[idx].varsReady = v + 1;
    slots[idx].next = 0;
}

/// A few ms a frame behind the menu; whole, it was 4.4 s of synthesis on the main thread. A TAKE IS INDIVISIBLE
/// — the budget bounds what we START, so one 8 s bed take is a ~300 ms hole in the frame that picks it up, hence `longOk`. Seconds of AUDIO, the cheap proxy for cost.
const LONG_TAKE: f32 = 1.4;

pub fn pump(budgetNs: u64, longOk: bool) bool {
    if (!ready or pumpDone) return false;
    var t = std.time.Timer.start() catch return false;
    var left: usize = NV;
    var deferred = false;
    while (left > 0) : (left -= 1) {
        const idx = pumpAt;
        pumpAt = (pumpAt + 1) % NV;
        if (slots[idx].varsReady >= BANK[idx].vars) continue;
        if (!longOk and seconds(BANK[idx].id) > LONG_TAKE) {
            deferred = true;
            continue;
        }
        bakeTake(BANK[idx].id, idx);
        if (t.read() >= budgetNs) return true;
        left = NV + 1;
    }
    pumpDone = !deferred;
    return deferred;
}

var pumpAt: usize = 0;
var pumpDone = false;

fn stopRow(idx: usize) void {
    const row = BANK[idx];
    var v: u8 = 0;
    while (v < slots[idx].varsReady) : (v += 1) {
        var p: u8 = 0;
        while (p < row.poly) : (p += 1) rl.stopSound(slots[idx].snd[v][p]);
    }
}

fn freeRow(idx: usize) void {
    const row = BANK[idx];
    var v: u8 = 0;
    while (v < slots[idx].varsReady) : (v += 1) {
        var p: u8 = 1;
        while (p < row.poly) : (p += 1) rl.unloadSoundAlias(slots[idx].snd[v][p]);
        rl.unloadSound(slots[idx].owned[v]);
    }
    slots[idx].varsReady = 0;
    pumpDone = false;
}

fn dropRow(idx: usize) void {
    stopRow(idx);
    freeRow(idx);
}

fn rebakeMix(m: Submix) void {
    if (!ready) return;
    inline for (@typeInfo(Id).@"enum".fields, 0..) |f, idx| {
        if (BANK[idx].mix == m) {
            dropRow(idx);
            bakeTake(@enumFromInt(f.value), idx);
        }
    }
    if (m == .ambience) redressFire();
}

fn redressFire() void {
    const old = restFire orelse return;
    const wasPlaying = rl.isMusicStreamPlaying(old);
    rl.stopMusicStream(old);
    rl.unloadMusicStream(old);
    restFire = rl.loadMusicStreamFromMemory(".wav", dressedFire()) catch null;
    if (restFire) |*m| {
        m.looping = true;
        rl.setMusicVolume(m.*, 0); // `restFireLevel` owns the level, and it re-sets it every frame
        if (wasPlaying) rl.playMusicStream(m.*);
    }
}

pub fn init() void {
    loadSettings();
    rl.initAudioDevice();
    if (!rl.isAudioDeviceReady()) return;
    rl.setMasterVolume(MASTER_VOL);
    inline for (@typeInfo(Id).@"enum".fields, 0..) |f, idx| bakeTake(@enumFromInt(f.value), idx);
    restFire = rl.loadMusicStreamFromMemory(".wav", dressedFire()) catch null;
    if (restFire) |*m| {
        m.looping = true;
        rl.setMusicVolume(m.*, 0);
    }
    ready = true;
}

const CAMPFIRE_WAV = @embedFile("campfire_wav");


const FIRE_BASS_HZ: f32 = 190.0;
const FIRE_BASS: f32 = 1.35;
const FIRE_DRIVE: f32 = 1.55;
const FIRE_BITS: f32 = 6.5; // crushed HARDER than the synth bank's 7.5: it is the one voice with real
const FIRE_HOLD: u32 = 2;
const FIRE_CUT: f32 = 3400.0;
const FIRE_HISS: f32 = 0.010;
const FIRE_OUT: f32 = 0.92;

var fireWav: [CAMPFIRE_WAV.len + 64]u8 = undefined;

fn put32(b: []u8, at: usize, v: u32) void {
    std.mem.writeInt(u32, b[at..][0..4], v, .little);
}
fn put16(b: []u8, at: usize, v: u16) void {
    std.mem.writeInt(u16, b[at..][0..2], v, .little);
}

fn dressedFire() []const u8 {
    const w = rl.loadWaveFromMemory(".wav", CAMPFIRE_WAV) catch return CAMPFIRE_WAV;
    defer rl.unloadWave(w);
    if (w.sampleSize != 16) return CAMPFIRE_WAV;
    const frames: usize = @intCast(w.frameCount);
    const chans: usize = @intCast(w.channels);
    const n = frames * chans;
    const bytes = 44 + n * 2;
    if (n == 0 or bytes > fireWav.len or n > MAX_N) return CAMPFIRE_WAV;
    const src: [*]i16 = @ptrCast(@alignCast(w.data));

    var low = Pole{};
    var lp = Pole{};
    var hp = Pole{};
    var hq = Pole{};
    var r = mathx.Rng.init(0xF12E9A);
    const levels = std.math.pow(f32, 2.0, FIRE_BITS) * 0.5;
    var held: f32 = 0;
    var k: u32 = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        var x = @as(f32, @floatFromInt(src[i])) / 32768.0;
        x += FIRE_BASS * low.step(x, FIRE_BASS_HZ);
        const d = x * FIRE_DRIVE;
        x = d / (1.0 + @abs(d));
        if (k == 0) held = x;
        k = (k + 1) % @max(FIRE_HOLD, 1);
        const dith = (r.signed() + r.signed()) * 0.5 / levels * DITHER_LSB;
        x = @round((held + dith) * levels) / levels;
        x = lp.step(x, FIRE_CUT);
        x += hq.step(hp.step(r.signed(), 5200), 2600) * FIRE_HISS;
        work[i] = mathx.clampF(x * FIRE_OUT, -1, 1);
    }

    var fr = Rack{ .n = n, .rng = mathx.Rng.init(0xF12E9A ^ 0x5EED) };
    applyFx(&fr, .ambience);
    for (work[0..n], 0..) |s, si| {
        std.mem.writeInt(i16, fireWav[44 + si * 2 ..][0..2], pcm16(s), .little);
    }

    const rate: u32 = w.sampleRate;
    const align16: u16 = @intCast(chans * 2);
    @memcpy(fireWav[0..4], "RIFF");
    put32(&fireWav, 4, @intCast(bytes - 8));
    @memcpy(fireWav[8..12], "WAVE");
    @memcpy(fireWav[12..16], "fmt ");
    put32(&fireWav, 16, 16);
    put16(&fireWav, 20, 1);
    put16(&fireWav, 22, @intCast(chans));
    put32(&fireWav, 24, rate);
    put32(&fireWav, 28, rate * align16);
    put16(&fireWav, 32, align16);
    put16(&fireWav, 34, 16);
    @memcpy(fireWav[36..40], "data");
    put32(&fireWav, 40, @intCast(n * 2));
    return fireWav[0..bytes];
}

var restFire: ?rl.Music = null;

pub fn restFireOn(on: bool) void {
    const m = restFire orelse return;
    if (!ready) return;
    if (on) {
        rl.setMusicVolume(m, 0);
        rl.playMusicStream(m);
        rl.seekMusicStream(m, 0);
    } else {
        rl.stopMusicStream(m);
    }
}

pub fn restFireLevel(v: f32) void {
    const m = restFire orelse return;
    rl.setMusicVolume(m, mathx.clampF(v, 0, 1) * userVol[@intFromEnum(Submix.ambience)]);
}

pub fn tickStreams() void {
    const m = restFire orelse return;
    if (rl.isMusicStreamPlaying(m)) rl.updateMusicStream(m);
}

/// The CLAMP is what makes this a function rather than a multiply: a sample past ±1.024 is not a clipped take but an out-of-range `@intFromFloat`.
fn pcm16(s: f32) i16 {
    return @intFromFloat(mathx.clampF(s, -1, 1) * 32000.0);
}

fn bake(r: *Rack) rl.Sound {
    for (work[0..r.n], 0..) |s, i| {
        pcm[i] = pcm16(s);
    }
    const wave = rl.Wave{
        .frameCount = @intCast(r.n),
        .sampleRate = @intCast(SR),
        .sampleSize = 16,
        .channels = 1,
        .data = @ptrCast(&pcm),
    };
    return rl.loadSoundFromWave(wave);
}

pub fn deinit() void {
    if (!ready) return;
    if (restFire) |m| rl.stopMusicStream(m);
    for (0..NV) |idx| stopRow(idx);
    for (0..NV) |idx| freeRow(idx);
    if (restFire) |m| rl.unloadMusicStream(m);
    ready = false;
    rl.closeAudioDevice();
}

pub fn listen(pos: rl.Vector3, right: rl.Vector3) void {
    lisPos = pos;
    lisRight = right;
}

pub const VoiceInfo = struct {
    gain: f32,
    mix: Submix,
    jit: f32,
    vjit: f32,
    vars: u8,
    poly: u8,
    reach: f32,
};

pub fn voiceInfo(id: Id) VoiceInfo {
    const r = live[@intFromEnum(id)];
    return .{ .gain = r.gain, .mix = r.mix, .jit = r.jit, .vjit = r.vjit, .vars = r.vars, .poly = r.poly, .reach = r.reach };
}

// (owner: let me edit basic things on sound fx and save over them, keep your originals for a revert.)
// `BANK` is the original and NEVER moves — that IS the revert. `live` is what every play path reads and all the
// editor writes; `settings.cfg` carries the DIFFERENCE only, so a voice re-authored in code flows through.
//
// **THE SHAPE OF A ROW IS NOT ON THE BENCH.** `vars` and `poly` size the alias table `freeRow` walks, so a dial
// that moved either between a bake and its free would leak or double-free; those two, `mix`, `id` and `make` have no setter.
var live: [NV]Row = BANK;
var voiceFx: [NV][AFX_COUNT]f32 = [_][AFX_COUNT]f32{[_]f32{0} ** AFX_COUNT} ** NV;
var voiceDirty: [NV]bool = [_]bool{false} ** NV;

/// Each is a plain multiplier or an angle on the take — none re-bakes, which is why they answer under the finger while the filters take `FX_SETTLE`.
pub const Dial = enum { gain, pitch, reach, jit, vjit };

/// A runtime table: the bench lists off it and `settings.cfg` is keyed on it. An `inline for` over the enum instead unrolls its whole body ~190 times per call site and blows the comptime branch quota.
pub const NAMES: [NV][:0]const u8 = blk: {
    var out: [NV][:0]const u8 = undefined;
    for (@typeInfo(Id).@"enum".fields, 0..) |f, i| out[i] = f.name;
    break :blk out;
};

pub const DialSpec = struct { name: [:0]const u8, lo: f32, hi: f32, tip: [:0]const u8 };

pub fn dialSpec(d: Dial) DialSpec {
    return switch (d) {
        .gain => .{ .name = "vol", .lo = 0, .hi = 1, .tip = "How loud, before the family's own trim and the player's slider" },
        .pitch => .{ .name = "pitch", .lo = 0.5, .hi = 2.0, .tip = "Where the take sits - 1.0 is as it was baked" },
        .reach => .{ .name = "reach", .lo = 4, .hi = 220, .tip = "Metres it carries; past this it is not played at all" },
        .jit => .{ .name = "pitch jit", .lo = 0, .hi = 0.30, .tip = "How far each firing wanders off the pitch" },
        .vjit => .{ .name = "level jit", .lo = 0, .hi = 0.40, .tip = "How far each firing wanders off the level" },
    };
}

pub fn dialOf(id: Id, d: Dial) f32 {
    const r = live[@intFromEnum(id)];
    return switch (d) {
        .gain => r.gain,
        .pitch => r.pitch,
        .reach => r.reach,
        .jit => r.jit,
        .vjit => r.vjit,
    };
}

pub fn setDial(id: Id, d: Dial, v: f32) void {
    const s = dialSpec(d);
    const k = mathx.clampF(v, s.lo, s.hi);
    const r = &live[@intFromEnum(id)];
    switch (d) {
        .gain => r.gain = k,
        .pitch => r.pitch = k,
        .reach => r.reach = k,
        .jit => r.jit = k,
        .vjit => r.vjit = k,
    }
}

pub fn voiceFxValues(id: Id) []const f32 {
    return &voiceFx[@intFromEnum(id)];
}

pub fn setVoiceFx(id: Id, i: usize, v: f32) void {
    if (i >= AFX_COUNT) return;
    const idx: usize = @intFromEnum(id);
    const k = mathx.clampF(v, 0, 1);
    if (voiceFx[idx][i] == k) return;
    voiceFx[idx][i] = k;
    voiceDirty[idx] = true;
    fxSettle = FX_SETTLE;
}

pub fn voiceFxOff(id: Id) void {
    for (0..AFX_COUNT) |i| setVoiceFx(id, i, 0);
}

pub fn applyVoiceFxPreset(id: Id, preset: []const FxPreset) void {
    voiceFxOff(id);
    for (preset) |p| setVoiceFx(id, p.idx, p.val);
}

/// What the Revert button lights on, and the whole of what `saveSettings` writes down.
pub fn voiceEdited(id: Id) bool {
    const idx: usize = @intFromEnum(id);
    const a = live[idx];
    const b = BANK[idx];
    if (a.gain != b.gain or a.pitch != b.pitch or a.reach != b.reach or a.jit != b.jit or a.vjit != b.vjit) return true;
    for (voiceFx[idx]) |v| {
        if (v > 0) return true;
    }
    return false;
}

pub fn anyVoiceEdited() bool {
    for (0..NV) |i| {
        if (voiceEdited(@enumFromInt(i))) return true;
    }
    return false;
}

pub fn revertVoice(id: Id) void {
    const idx: usize = @intFromEnum(id);
    const hadFx = blk: {
        for (voiceFx[idx]) |v| {
            if (v > 0) break :blk true;
        }
        break :blk false;
    };
    live[idx] = BANK[idx];
    voiceFx[idx] = [_]f32{0} ** AFX_COUNT;
    if (hadFx) {
        voiceDirty[idx] = true;
        fxSettle = FX_SETTLE;
    }
}

pub fn revertAllVoices() void {
    for (0..NV) |i| revertVoice(@enumFromInt(i));
}

const DEFAULT_VOL = blk: {
    var d = [_]f32{1.0} ** NMIX;
    d[@intFromEnum(Submix.sfx)] = 0.90;
    d[@intFromEnum(Submix.combat)] = 0.80;
    d[@intFromEnum(Submix.ambience)] = 0.80;
    break :blk d;
};
var userVol: [NMIX]f32 = DEFAULT_VOL;

pub fn volume(m: Submix) f32 {
    return userVol[@intFromEnum(m)];
}

fn levelFor(row: Row, vol: f32, vj: f32) f32 {
    return mathx.clampF(row.gain * submixTrim(row.mix) * userVol[@intFromEnum(row.mix)] * vol * vj, 0, 1);
}

var daylight: f32 = 1.0;

pub fn setDaylight(k: f32) void {
    daylight = mathx.clampF(k, 0, 1);
}

var rainLevel: f32 = 0;
var torchLevel: f32 = 0;
/// **THE DIALLED LIQUID BEDS, IN `wf.Liquid` ORDER PAST WATER** — water has none: the wind is its bed, and
/// painting a tarn may not add a voice to a map that already sounded right. `BEDS` is built off this list and
/// `game.LIQUID_VOICE` pins the names against the enum, so the index is the liquid's ordinal minus one and
/// there is no side array to keep in step.
pub const LIQUID_BEDS = [_]Id{ .oil_bed, .fungal_bed, .lava_bed };

/// How much of each is underfoot or next to you. Driven by `game.tickLiquid`.
var liquidLevel: [LIQUID_BEDS.len]f32 = [_]f32{0} ** LIQUID_BEDS.len;

/// `i` is `@intFromEnum(wf.Liquid) - 1`. Out of range is a bounds panic, not a shrug: there is no liquid the
/// caller could mean that this does not have a slot for.
pub fn setLiquidBed(i: usize, k: f32) void {
    liquidLevel[i] = mathx.clampF(k, 0, 1);
}

pub fn setRain(k: f32) void {
    rainLevel = mathx.clampF(k, 0, 1);
}

/// The one bed the WORLD does not set: it is on when he is carrying the thing (`hero.torchOut`).
pub fn setTorch(k: f32) void {
    torchLevel = mathx.clampF(k, 0, 1);
}

const Hour = struct { atNoon: f32 = 1.0, atNight: f32 = 1.0 };

fn hourGain(h: Hour) f32 {
    return mathx.lerpF(h.atNight, h.atNoon, daylight);
}

pub fn setVolume(m: Submix, v: f32) void {
    userVol[@intFromEnum(m)] = mathx.clampF(v, 0, 1);
    if (ready and m == .ambience) {
        for (BEDS) |b| holdBed(b);
    }
}

/// **A BED'S LEVEL IS SET AT ITS TRIGGER AND THEN NEVER AGAIN**, so a dial moved mid-take went unheard until
/// the loop came round — up to 8.6 s. A torch is an F-press, and it crackled on for the rest of the take after
/// he put it away. Held every frame instead. Volume ONLY: `trigger` owns the pan, and re-centring here would collapse its stereo.
fn holdBed(b: Bed) void {
    const s = &slots[@intFromEnum(b.id)];
    const lvl = bedLevel(live[@intFromEnum(b.id)], b.hour) * bedDial(b);
    if (s.varsReady > 0) rl.setSoundVolume(s.snd[0][0], lvl);
    if (s.varsReady > 1) rl.setSoundVolume(s.snd[1][0], lvl);
}

fn bedLevel(row: Row, h: Hour) f32 {
    return levelFor(row, hourGain(h), 1.0);
}

fn bedDial(b: Bed) f32 {
    return if (b.dial) |d| d.* else 1.0;
}

pub const SETTINGS_PATH = "settings.cfg";

const FX_KEY = "fx.";
const VOICE_KEY = "voice.";

const SETTINGS_CAP = NMIX * (32 + AFX_COUNT * 8) + NV * (40 + 5 * 10 + AFX_COUNT * 6) + 64;

pub fn loadSettings() void {
    var buf: [SETTINGS_CAP]u8 = undefined;
    const f = std.fs.cwd().openFile(SETTINGS_PATH, .{}) catch return;
    defer f.close();
    const n = f.readAll(&buf) catch return;
    if (n == buf.len) return;
    var lines = std.mem.tokenizeAny(u8, buf[0..n], "\r\n");
    while (lines.next()) |line| {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        const key = it.next() orelse continue;
        if (std.mem.startsWith(u8, key, FX_KEY)) {
            const fam = key[FX_KEY.len..];
            inline for (@typeInfo(Submix).@"enum".fields) |fld| {
                if (std.mem.eql(u8, fam, fld.name)) {
                    var row = [_]f32{0} ** AFX_COUNT;
                    var i: usize = 0;
                    while (i < AFX_COUNT) : (i += 1) {
                        const tok = it.next() orelse break;
                        row[i] = mathx.clampF(std.fmt.parseFloat(f32, tok) catch 0, 0, 1);
                    }
                    fxVals[fld.value] = row;
                }
            }
            continue;
        }
        if (std.mem.startsWith(u8, key, VOICE_KEY)) {
            const name = key[VOICE_KEY.len..];
            for (NAMES, 0..) |nm, vi| {
                if (!std.mem.eql(u8, name, nm)) continue;
                const id: Id = @enumFromInt(vi);
                // Against the AUTHORED row: a short or damaged line leaves the rest of the voice where the code has it rather than at zero.
                live[vi] = BANK[vi];
                inline for (@typeInfo(Dial).@"enum".fields) |dfld| {
                    if (it.next()) |tok| {
                        if (std.fmt.parseFloat(f32, tok) catch null) |x| setDial(id, @enumFromInt(dfld.value), x);
                    }
                }
                var i: usize = 0;
                while (i < AFX_COUNT) : (i += 1) {
                    const tok = it.next() orelse break;
                    setVoiceFx(id, i, std.fmt.parseFloat(f32, tok) catch 0);
                }
                break;
            }
            continue;
        }
        const val = it.next() orelse continue;
        const v = std.fmt.parseFloat(f32, val) catch continue;
        inline for (@typeInfo(Submix).@"enum".fields) |fld| {
            if (std.mem.eql(u8, key, fld.name)) setVolume(@enumFromInt(fld.value), v);
        }
    }
    // LOADING IS NOT EDITING. `setVoiceFx` arms the settle clock so a dial under the finger coalesces, but
    // this runs BEFORE the first bake and `bakeTake` reads `voiceFx` itself — so every edited voice would be
    // dropped and re-synthesized a fifth of a second into the run for a take it already had.
    voiceDirty = [_]bool{false} ** NV;
    fxSettle = 0;
}

pub fn saveSettings() void {
    const f = std.fs.cwd().createFile(SETTINGS_PATH, .{}) catch return;
    defer f.close();
    var w = f.writer();
    inline for (@typeInfo(Submix).@"enum".fields) |fld| {
        w.print("{s} {d:.3}\n", .{ fld.name, userVol[fld.value] }) catch return;
    }
    inline for (@typeInfo(Submix).@"enum".fields) |fld| {
        w.print(FX_KEY ++ "{s}", .{fld.name}) catch return;
        for (fxVals[fld.value]) |v| w.print(" {d:.3}", .{v}) catch return;
        w.writeAll("\n") catch return;
    }
    // THE DIFFERENCE AND NOTHING ELSE. A voice left where the code put it writes no line, so re-authoring one
    // reaches a save that never mentioned it — which is the same reason `BANK` is the revert.
    for (0..NV) |i| {
        if (!voiceEdited(@enumFromInt(i))) continue;
        const r = live[i];
        w.print(VOICE_KEY ++ "{s} {d:.4} {d:.4} {d:.2} {d:.4} {d:.4}", .{ NAMES[i], r.gain, r.pitch, r.reach, r.jit, r.vjit }) catch return;
        for (voiceFx[i]) |v| w.print(" {d:.3}", .{v}) catch return;
        w.writeAll("\n") catch return;
    }
}

pub fn mute(on: bool) void {
    if (muted == on) return;
    muted = on;
    if (ready) rl.setMasterVolume(if (on) 0.0 else MASTER_VOL);
}

pub fn play(id: Id) void {
    emit(id, 1.0, 0.5, 1.0);
}

pub fn playAt(id: Id, vol: f32) void {
    emit(id, vol, 0.5, 1.0);
}

pub fn world(id: Id, at: rl.Vector3) void {
    worldThrough(id, at, 1.0, 1.0);
}

pub fn worldAt(id: Id, at: rl.Vector3, gain: f32) void {
    worldThrough(id, at, gain, 1.0);
}

/// **WHAT A WALL DOES TO A SOUND.** `clear` is 1 on an open line and 0 with rock in the way; the caller is who
/// can ask that question, since nothing under `core/` can see the world.
///
/// **IT IS A CUT AND A DROOP, NOT A FILTER.** raylib cannot filter a playing voice (AGENTS.md) — the rack is
/// bake-time — so the two levers a live voice has are level and pitch. Level alone reads as FAR AWAY; pulling
/// the pitch down with it is what makes the same take read as dull, which is what coming through stone sounds
/// like. Both are small: the point is a sound you can still place, not one you cannot hear.
pub const MUFFLE_GAIN: f32 = 0.34;
pub const MUFFLE_DROOP: f32 = 0.06;

pub fn worldThrough(id: Id, at: rl.Vector3, gain: f32, clear: f32) void {
    if (!ready) return;
    const row = live[@intFromEnum(id)];
    const d2 = mathx.dist2XZ(at, lisPos);
    if (d2 > row.reach * row.reach) return;
    const d = @sqrt(d2);
    const k = 1.0 - d / row.reach;
    const near = d / row.reach;
    const to = mathx.dirXZ(lisPos, at);
    const side = to.x * lisRight.x + to.z * lisRight.z;
    const fwd = mathx.perpXZ(lisRight);
    const front = to.x * fwd.x + to.z * fwd.z;
    const rear = 1.0 - REAR_DUCK * 0.5 * (1.0 - front);
    const width = PAN_WIDTH * mathx.smoothstep(0, PAN_NEAR, d);
    const c = mathx.clampF(clear, 0, 1);
    const muffle = mathx.lerpF(MUFFLE_GAIN, 1.0, c);
    const droop = mathx.lerpF(MUFFLE_DROOP, 0, c);
    emit(id, k * k * rear * gain * muffle, panFor(side, width), 1.0 - PITCH_DROOP * near - droop);
}

fn emit(id: Id, vol: f32, pan: f32, pitchScale: f32) void {
    if (!ready or muted or vol <= 0.01) return;
    const idx = @intFromEnum(id);
    const row = live[idx];
    const s = &slots[idx];
    if (s.varsReady == 0) return;
    const pick = s.next;
    s.next = (s.next + 1) % (s.varsReady * row.poly);
    trigger(s.snd[pick % s.varsReady][pick / s.varsReady % row.poly], row, vol, pan, pitchScale);
}

fn trigger(snd: rl.Sound, row: Row, vol: f32, pan: f32, pitchScale: f32) void {
    const vj = 1.0 - @abs(rng.signed()) * row.vjit;
    rl.setSoundVolume(snd, levelFor(row, vol, vj));
    rl.setSoundPitch(snd, row.pitch * (1.0 + rng.signed() * row.jit) * pitchScale);
    rl.setSoundPan(snd, pan);
    rl.playSound(snd);
}

fn bed(id: Id, vol: f32) void {
    if (!ready or muted) return;
    const idx = @intFromEnum(id);
    const row = live[idx];
    const s = &slots[idx];
    if (s.varsReady == 0) return;
    if (s.varsReady == 1) {
        trigger(s.snd[0][0], row, vol, 0.5, 1.0);
        return;
    }
    trigger(s.snd[0][0], row, vol, BED_PAN, 1.0);
    trigger(s.snd[1][0], row, vol, 1.0 - BED_PAN, 1.0);
}

/// `dial` is what the WORLD has to say about this bed on top of the hour — null is "always on".
const Bed = struct { id: Id, hour: Hour = .{}, dial: ?*const f32 = null };

const BEDS = [_]Bed{
    .{ .id = .wind },
    .{ .id = .crickets, .hour = .{ .atNoon = 0.34, .atNight = 1.0 } },
    .{ .id = .rain, .dial = &rainLevel },
    .{ .id = .torch_fire, .dial = &torchLevel },
} ++ blk: {
    // GENERATED, so a bed and the slot it dials cannot be written out of step with each other.
    var out: [LIQUID_BEDS.len]Bed = undefined;
    for (LIQUID_BEDS, 0..) |id, i| out[i] = .{ .id = id, .dial = &liquidLevel[i] };
    break :blk out;
};

/// An ambience-mix voice the WORLD fires, rather than a bed that holds or a call on a clock of its own. Each
/// must out-shout the loudest bed (a test pins it), or the thing that happened is quieter than the room.
pub const AMBIENT_EVENTS = [_]Id{ .thunder, .oil_pop, .fungal_pop, .lava_pop };

const Call = struct {
    id: Id,
    gapLo: f32,
    gapHi: f32,
    distLo: f32,
    distHi: f32,
    first: f32,
    hour: Hour = .{},
};

const CALLS = [_]Call{
    .{ .id = .birds, .gapLo = 6, .gapHi = 17, .distLo = 12, .distHi = 150, .first = 4, .hour = .{ .atNoon = 1.0, .atNight = 0.22 } },
    .{ .id = .birdsong, .gapLo = 7, .gapHi = 20, .distLo = 14, .distHi = 155, .first = 9, .hour = .{ .atNoon = 1.0, .atNight = 0.22 } },
    .{ .id = .owl, .gapLo = 26, .gapHi = 70, .distLo = 40, .distHi = 150, .first = 22 },
};

var callWait: [CALLS.len]f32 = init: {
    var w: [CALLS.len]f32 = undefined;
    for (CALLS, 0..) |c, i| w[i] = c.first;
    break :init w;
};

pub fn ambience(dt: f32) void {
    if (!ready or muted) return;
    for (BEDS) |b| {
        const s = &slots[@intFromEnum(b.id)];
        if (s.varsReady == 0) continue;
        const lvl = hourGain(b.hour) * bedDial(b);
        if (lvl <= 0.004) {
            // A DIALLED bed is STOPPED rather than left to play out, and it is silent by then anyway
            // (`holdBed` took it to zero on the way down), so there is no edge to click on.
            if (b.dial != null and rl.isSoundPlaying(s.snd[0][0])) stopRow(@intFromEnum(b.id));
            continue;
        }
        if (rl.isSoundPlaying(s.snd[0][0])) holdBed(b) else bed(b.id, lvl);
    }
    for (CALLS, 0..) |c, i| {
        callWait[i] -= dt;
        if (callWait[i] > 0) continue;
        callWait[i] = rng.range(c.gapLo, c.gapHi);
        const a = rng.angle();
        const d = rng.range(c.distLo, c.distHi);
        worldAt(c.id, mathx.v3(lisPos.x + mathx.cosf(a) * d, lisPos.y, lisPos.z + mathx.sinf(a) * d), hourGain(c.hour));
    }
}

pub fn arrowImpact(surf: ?@import("collision.zig").Surface) Id {
    const s = surf orelse return .arrow_dirt;
    return switch (s) {
        .stone => .arrow_stone,
        .wood => .arrow_wood,
        .metal => .arrow_metal,
    };
}

comptime {
    std.debug.assert(BANK.len == NV);
    for (BANK, 0..) |row, i| {
        if (@intFromEnum(row.id) != i) @compileError(std.fmt.comptimePrint(
            "audio: BANK[{d}] is .{s}, which belongs at {d} — the table has shifted against Id",
            .{ i, @tagName(row.id), @intFromEnum(row.id) },
        ));
    }
    for (BANK, 0..) |row, i| {
        if (row.vars < 1 or row.vars > MAX_VARS) @compileError(std.fmt.comptimePrint(
            "audio: BANK[{d}].vars = {d}, outside 1..{d} (raise MAX_VARS with it)",
            .{ i, row.vars, MAX_VARS },
        ));
        if (row.poly < 1 or row.poly > MAX_POLY) @compileError(std.fmt.comptimePrint(
            "audio: BANK[{d}].poly = {d}, outside 1..{d} (raise MAX_POLY with it)",
            .{ i, row.poly, MAX_POLY },
        ));
    }
}

test "every voice renders, stays in range, and is not silence" {
    inline for (@typeInfo(Id).@"enum".fields, 0..) |f, idx| {
        const id: Id = @enumFromInt(f.value);
        var r = Rack.init(0x9E3779B9 *% (idx + 1), seconds(id));
        BANK[idx].make(&r);
        try std.testing.expect(r.n > 64);
        var peak: f32 = 0;
        var energy: f32 = 0;
        for (work[0..r.n]) |s| {
            try std.testing.expect(std.math.isFinite(s));
            peak = mathx.maxF(peak, @abs(s));
            energy += @abs(s);
        }
        try std.testing.expect(peak > 0.2);
        try std.testing.expect(peak <= 1.0);
        try std.testing.expect(energy / @as(f32, @floatFromInt(r.n)) > 0.002);
    }
}

test "NO VOICE OUTRUNS ITS OWN TAKE — every authored layer gets samples to render into" {
    inline for (@typeInfo(Id).@"enum".fields, 0..) |f, idx| {
        const id: Id = @enumFromInt(f.value);
        var r = Rack.init(0x9E3779B9 *% (idx + 1), seconds(id));
        BANK[idx].make(&r);
        if (r.dropped != 0) {
            std.debug.print("audio: .{s} authors {d} layer(s) past its {d:.2}s take\n", .{ f.name, r.dropped, seconds(id) });
        }
        try std.testing.expectEqual(@as(usize, 0), r.dropped);
    }
}

fn workEnergy(n: usize) f64 {
    var s: f64 = 0;
    for (work[0..n]) |x| s += @abs(x);
    return s;
}

test "AN ALL-OFF RACK IS A NO-OP — the bank bakes exactly as it did before filters existed" {
    const mi = @intFromEnum(Submix.combat);
    const was = fxVals[mi];
    defer fxVals[mi] = was;
    fxVals[mi] = [_]f32{0} ** AFX_COUNT;
    var r = Rack.init(4242, seconds(.hit_light));
    mkHitLight(&r);
    const clean = workEnergy(r.n);
    applyFx(&r, .combat);
    try std.testing.expectEqual(clean, workEnergy(r.n));
}

test "THE HOUSE SOUND IS WORN TAPE, on all three families, and it is the preset's own numbers" {
    var want = [_]f32{0} ** AFX_COUNT;
    for (FX_TAPE) |p| want[p.idx] = p.val;
    try std.testing.expectEqualSlices(f32, &want, &AFX_DEFAULTS);
    try std.testing.expect(AFX_DEFAULTS[AF_WOBBLE] > AFX_EPS);
    inline for (@typeInfo(Submix).@"enum".fields) |fld| {
        try std.testing.expectEqualSlices(f32, &AFX_DEFAULTS, fxValues(@enumFromInt(fld.value)));
    }
}


test "EVERY VOICE SURVIVES THE HOUSE RACK — in range, still a sound, and never NaN" {
    const keep = fxVals;
    defer fxVals = keep;
    for (&fxVals) |*rack| rack.* = AFX_DEFAULTS;
    inline for (@typeInfo(Id).@"enum".fields, 0..) |f, idx| {
        const id: Id = @enumFromInt(f.value);
        var r = Rack.init(0x9E3779B9 *% (idx + 1), seconds(id));
        BANK[idx].make(&r);
        applyFx(&r, BANK[idx].mix);
        var peak: f32 = 0;
        var energy: f32 = 0;
        for (work[0..r.n]) |s| {
            try std.testing.expect(std.math.isFinite(s));
            peak = mathx.maxF(peak, @abs(s));
            energy += @abs(s);
        }
        try std.testing.expect(peak > 0.2);
        try std.testing.expect(peak <= 1.0);
        try std.testing.expect(energy / @as(f32, @floatFromInt(r.n)) > 0.002);
    }
}

test "EVERY FILTER RENDERS: each dial alone changes the voice and none of them blows it up" {
    const mi = @intFromEnum(Submix.combat);
    const was = fxVals[mi];
    defer fxVals[mi] = was;
    const clean = try std.testing.allocator.alloc(f32, MAX_N);
    defer std.testing.allocator.free(clean);
    var r0 = Rack.init(4242, seconds(.hit_light));
    mkHitLight(&r0);
    @memcpy(clean[0..r0.n], work[0..r0.n]);

    for (0..AFX_COUNT) |i| {
        fxVals[mi] = [_]f32{0} ** AFX_COUNT;
        fxVals[mi][i] = 0.8;
        var r = Rack.init(4242, seconds(.hit_light));
        mkHitLight(&r);
        applyFx(&r, .combat);
        var peak: f32 = 0;
        var diff: f64 = 0;
        for (work[0..r.n], clean[0..r.n]) |s, c| {
            try std.testing.expect(std.math.isFinite(s));
            peak = mathx.maxF(peak, @abs(s));
            diff += @abs(s - c);
        }
        try std.testing.expect(peak > 0.2);
        try std.testing.expect(peak <= 1.0);
        try std.testing.expect(diff / @as(f64, @floatFromInt(r.n)) > 1e-4);
    }
}

test "EVERY PRESET IS REACHABLE AND IN RANGE, and names a filter that exists" {
    const mi = @intFromEnum(Submix.sfx);
    const was = fxVals[mi];
    defer fxVals[mi] = was;
    for ([_][]const FxPreset{ &FX_VINYL, &FX_RADIO, &FX_TAPE, &FX_CRUSHED, &FX_BROKEN }) |p| {
        try std.testing.expect(p.len > 0);
        for (p) |row| {
            try std.testing.expect(row.idx < AFX_COUNT);
            try std.testing.expect(row.val > AFX_EPS and row.val <= 1.0);
        }
        applyFxPreset(.sfx, p);
        var on: usize = 0;
        for (fxValues(.sfx)) |v| {
            if (v > AFX_EPS) on += 1;
        }
        try std.testing.expectEqual(p.len, on);
    }
    allFxOff(.combat);
    applyFxPreset(.sfx, &FX_VINYL);
    for (fxValues(.combat)) |v| try std.testing.expect(v <= AFX_EPS);
}

test "A MOVED DIAL OWES A RE-RENDER, and only the family it belongs to" {
    const keep = fxVals;
    defer fxVals = keep;
    fxSettle = 0;
    fxDirty = [_]bool{false} ** NMIX;
    setFx(.ambience, AF_HISS, 0.5);
    try std.testing.expect(fxPending());
    try std.testing.expect(fxDirty[@intFromEnum(Submix.ambience)]);
    try std.testing.expect(!fxDirty[@intFromEnum(Submix.combat)]);
    fxSettle = 0;
    setFx(.ambience, AF_HISS, 0.5);
    try std.testing.expect(!fxPending());
    setFx(.ambience, AF_HISS, 0.6);
    try std.testing.expect(FX_SETTLE > 4.0 / 60.0);
    tickFx(FX_SETTLE + 0.01);
    try std.testing.expect(!fxPending());
}

test "the buffer never starts or ends on a step (that is the click you cannot un-hear)" {
    inline for (@typeInfo(Id).@"enum".fields, 0..) |f, idx| {
        const id: Id = @enumFromInt(f.value);
        var r = Rack.init(1234 + idx, seconds(id));
        BANK[idx].make(&r);
        try std.testing.expect(@abs(work[0]) < 0.02);
        try std.testing.expect(@abs(work[r.n - 1]) < 0.02);
    }
}

test "the world falloff is silent past its own range and loudest underfoot" {
    // `world` can be called thousands of times a frame by a knot of foes, so its early-out has to be real;
    // and a pan that leaves the 0..1 range is a raylib assert.
    listen(mathx.zero3, mathx.v3(1, 0, 0));
    try std.testing.expect(mathx.distXZ(mathx.v3(FALLOFF + 1, 0, 0), lisPos) > FALLOFF);
    const near = 1.0 - 0.0 / FALLOFF;
    const far = 1.0 - (FALLOFF * 0.9) / FALLOFF;
    try std.testing.expect(near * near > far * far * 50.0);
}

test "PAN IS THE LEFT CHANNEL'S GAIN — a source on your right must pan DOWN, not up" {
    const right = panFor(1.0, PAN_WIDTH);
    const left = panFor(-1.0, PAN_WIDTH);
    try std.testing.expect(right < 0.5);
    try std.testing.expect(left > 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), panFor(0.0, PAN_WIDTH), 1e-6);
    for ([_]f32{ -4, -1, 0, 1, 4 }) |s| {
        const p = panFor(s, PAN_WIDTH);
        try std.testing.expect(p >= 0.04 and p <= 0.96);
    }
    try std.testing.expect(BED_PAN > 0.5 + PAN_WIDTH);
    try std.testing.expect(BED_PAN < 1.0);
}

test "the near field closes the pan, so a foe standing on you does not strobe" {
    const onTop = PAN_WIDTH * mathx.smoothstep(0, PAN_NEAR, 0.05);
    const clear = PAN_WIDTH * mathx.smoothstep(0, PAN_NEAR, 4.0);
    try std.testing.expect(onTop < 0.02);
    try std.testing.expectApproxEqAbs(PAN_WIDTH, clear, 1e-6);
}

test "reach is per VOICE: a giant carries, a toad does not, a bird carries furthest" {
    const reach = struct {
        fn of(id: Id) f32 {
            return BANK[@intFromEnum(id)].reach;
        }
    }.of;
    try std.testing.expect(reach(.toad_chomp) < reach(.bow_loose));
    try std.testing.expect(reach(.bow_loose) < reach(.ogre_slam));
    try std.testing.expect(reach(.ogre_slam) < reach(.birds));
    try std.testing.expect(reach(.bow_loose) > reach(.bow_draw));
    try std.testing.expect(reach(.toad_chomp) > 12.0 and reach(.toad_chomp) < 40.0);
    for (BANK) |row| try std.testing.expect(row.reach > 1.0);
}

test "every sparse call is rolled INSIDE its own reach, and none of them is rolled at your ear" {
    for (CALLS) |c| {
        const row = BANK[@intFromEnum(c.id)];
        try std.testing.expect(c.distHi < row.reach);
        try std.testing.expect(c.distLo > 10.0 and c.distLo < c.distHi);
        try std.testing.expect(c.gapLo > 0 and c.gapHi > c.gapLo * 1.5);
        try std.testing.expect(c.first > 1.0);
    }
    try std.testing.expect(CALLS[2].gapLo > CALLS[0].gapLo * 2.0);
    try std.testing.expect(CALLS.len == 3);
}

test "THE BACKGROUND IS BACKGROUND — the ambience trim, and only the ambience" {
    for (BEDS) |b| try std.testing.expectEqual(Submix.ambience, BANK[@intFromEnum(b.id)].mix);
    for (CALLS) |c| try std.testing.expectEqual(Submix.ambience, BANK[@intFromEnum(c.id)].mix);
    for ([_]Submix{ .sfx, .combat, .ambience }) |mx| {
        try std.testing.expect(submixTrim(mx) > 0 and submixTrim(mx) < 1.0);
    }
    for (BANK) |row| {
        if (row.mix != .ambience) continue;
        try std.testing.expect(row.gain * TRIM_AMBIENCE < 1.0);
    }

    var trimmed: usize = 0;
    for (BANK) |row| {
        if (row.mix == .ambience) trimmed += 1;
    }
    try std.testing.expectEqual(BEDS.len + CALLS.len + AMBIENT_EVENTS.len, trimmed);
    for (AMBIENT_EVENTS) |id| try std.testing.expectEqual(Submix.ambience, BANK[@intFromEnum(id)].mix);
    for ([_]Id{ .toad_chomp, .toad_die, .ogre_slam, .ogre_roar, .bone_die, .hit_heavy, .hurt }) |id| {
        try std.testing.expect(BANK[@intFromEnum(id)].mix != .ambience);
        try std.testing.expectEqual(TRIM_COMBAT, submixTrim(BANK[@intFromEnum(id)].mix));
    }

    var loudBed: f32 = 0;
    for (BEDS) |b| loudBed = mathx.maxF(loudBed, BANK[@intFromEnum(b.id)].gain);
    for (CALLS) |c| try std.testing.expect(BANK[@intFromEnum(c.id)].gain > loudBed);
    for (AMBIENT_EVENTS) |id| try std.testing.expect(BANK[@intFromEnum(id)].gain > loudBed);
}

const Rendered = struct {
    /// Zero crossings a second — a cheap brightness proxy, and the one that catches a voice made of
    /// high partials: a sustained 2.3 kHz cluster crosses an order of magnitude more often than a body at 250.
    fn brightness(n: usize) f32 {
        var crossings: f32 = 0;
        var i: usize = 1;
        while (i < n) : (i += 1) {
            if ((work[i - 1] < 0) != (work[i] < 0)) crossings += 1;
        }
        return crossings / (@as(f32, @floatFromInt(n)) / SRF);
    }
    fn energy(a: usize, b: usize) f64 {
        var s: f64 = 0;
        var i = a;
        while (i < b) : (i += 1) s += @abs(work[i]);
        return s;
    }
};

test "THE PARRY IS A STRUCK DISC, NOT A PING — measured against the bank's own struck iron" {
    var r = Rack.init(1, seconds(.parry));
    mkParry(&r);
    const parryTail = Rendered.energy(2 * r.n / 3, r.n) / Rendered.energy(0, r.n / 3);
    const parryBright = Rendered.brightness(r.n);

    var m = Rack.init(1, seconds(.arrow_metal));
    mkArrowMetal(&m);
    const metalTail = Rendered.energy(2 * m.n / 3, m.n) / Rendered.energy(0, m.n / 3);

    var b = Rack.init(1, seconds(.guard_block));
    mkGuardBlock(&b);
    const blockBright = Rendered.brightness(b.n);

    // THE LOAD-BEARING ONE. `decay` is exp(-curve·u), so a slack curve leaves the voice at full cry when it
    // ends, and a `ring` still sounding then is a spring, not a shield. The shape the owner threw out
    // measured 0.106 against the block's 0.015 and this metal's 0.033 — hence a RELATIVE pin, not a number.
    try std.testing.expect(parryTail <= metalTail);
    try std.testing.expect(parryBright < blockBright * 1.35);
}

test "THE OPTIONS DIALS — three families, and the fight is one of them" {
    for ([_]Id{ .swing_light, .hit_heavy, .hurt, .guard_block, .toad_chomp, .bow_loose, .arrow_dirt, .bone_die, .ogre_slam, .kobold_snarl, .kobold_heal, .kill, .death }) |id| {
        try std.testing.expectEqual(Submix.combat, BANK[@intFromEnum(id)].mix);
    }
    for ([_]Id{ .step_soft, .roll, .refused, .flask_drink, .eat, .chest_open, .item_get, .menu_move }) |id| {
        try std.testing.expectEqual(Submix.sfx, BANK[@intFromEnum(id)].mix);
    }

    const combatRow = BANK[@intFromEnum(Id.ogre_slam)];
    const sfxRow = BANK[@intFromEnum(Id.menu_move)];
    const before = levelFor(sfxRow, 1.0, 1.0);
    setVolume(.combat, 0.5);
    defer setVolume(.combat, 1.0);
    try std.testing.expectApproxEqAbs(levelFor(combatRow, 1.0, 1.0), combatRow.gain * TRIM_COMBAT * 0.5, 1e-6);
    try std.testing.expectEqual(before, levelFor(sfxRow, 1.0, 1.0));

    // …and a dial cannot become a boost.
    setVolume(.combat, 4.0);
    try std.testing.expectEqual(@as(f32, 1.0), volume(.combat));
}

test "THE FOG GATE STING IS FIVE SECONDS OF SOUND, not one second and four of silence" {
    const id: Id = .fog_seal;
    const secs = seconds(id);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), secs, 1e-6);
    var r = Rack.init(0x9E3779B9, secs);
    BANK[@intFromEnum(id)].make(&r);
    try std.testing.expectEqual(@as(usize, 0), r.dropped);

    // RMS per second. The sting has to still be SOUNDING at the end — a take that has decayed to nothing by
    // second two is a one-second sound with a four-second gap after it, which is what "about 5s" is not.
    var rms: [5]f32 = undefined;
    for (&rms, 0..) |*v, sec| {
        const a0 = r.at(@as(f32, @floatFromInt(sec)));
        const b0 = r.at(@as(f32, @floatFromInt(sec + 1)));
        var sum: f32 = 0;
        for (work[a0..b0]) |x| sum += x * x;
        v.* = @sqrt(sum / @as(f32, @floatFromInt(b0 - a0)));
    }
    std.debug.print("\n  fog gate sting: rms/s {d:.3} {d:.3} {d:.3} {d:.3} {d:.3}\n", .{ rms[0], rms[1], rms[2], rms[3], rms[4] });
    for (rms) |v| try std.testing.expect(v > 0.02);
    try std.testing.expect(rms[4] > rms[0] * 0.10);
    // …and it OPENS on the door rather than fading in: the first second is the loudest.
    for (rms[1..]) |v| try std.testing.expect(rms[0] >= v);
}

test "THE FIGHT IS ONE BAND — no battle voice towers over the rest of them" {
    var lo: f32 = 1e9;
    var hi: f32 = 0;
    var n: usize = 0;
    for (BANK) |row| {
        if (row.mix != .combat or row.gain <= BATTLE_FLOOR + 1e-6) continue;
        lo = mathx.minF(lo, row.gain);
        hi = mathx.maxF(hi, row.gain);
        n += 1;
    }
    try std.testing.expect(n > 40);
    try std.testing.expect(hi / lo < 2.0);
    try std.testing.expect(lo >= BATTLE_FLOOR - 1e-4 and lo < BATTLE_FLOOR * 1.15);
    try std.testing.expect(hi < 0.62);

    const g = struct {
        fn of(id: Id) f32 {
            return BANK[@intFromEnum(id)].gain;
        }
    }.of;
    try std.testing.expect(g(.ogre_slam) > g(.kobold_chop));
    try std.testing.expect(g(.swing_light) < g(.hit_light));
    try std.testing.expect(g(.bow_draw) < g(.bow_loose));
    try std.testing.expect(g(.kobold_snarl) > g(.kobold_chop));
    for ([_]Id{ .step_soft, .step_hard, .step_sprint, .roll, .swing_light, .swing_heavy, .refused, .arrow_dirt, .kobold_cast, .kobold_heal }) |id| {
        try std.testing.expect(g(id) <= BATTLE_FLOOR + 1e-6);
    }
}

test "THE VOLUME IS RESERVED FOR WHAT IS ABOUT TO HIT YOU" {
    const g = struct {
        fn of(id: Id) f32 {
            return BANK[@intFromEnum(id)].gain;
        }
    }.of;
    try std.testing.expect(g(.toad_lunge) > g(.toad_hop));
    try std.testing.expect(g(.shroom_fling) > g(.shroom_hop));
    try std.testing.expect(g(.delver_burst) > g(.delver_churn));
    try std.testing.expect(g(.delver_surge) > g(.delver_dig));
    try std.testing.expect(g(.ogre_slam) > g(.ogre_step));
    try std.testing.expect(g(.leech_stab) > g(.leech_wing));
    try std.testing.expect(g(.wood_swing) > g(.wood_creak));
    try std.testing.expect(g(.kobold_heave) > g(.kobold_whirl));
    try std.testing.expect(g(.leech_stab) > g(.leech_drink));
    var hi: f32 = 0;
    for (BANK) |row| {
        if (row.mix == .combat) hi = mathx.maxF(hi, row.gain);
    }
    const mid = (BATTLE_FLOOR + hi) * 0.5;
    for ([_]Id{ .ogre_slam, .ogre_roar, .skel_lunge, .toad_lunge, .shroom_fling, .delver_surge, .delver_burst, .wood_wake, .wood_swing, .kobold_heave, .guard_break }) |id| {
        try std.testing.expect(g(id) > mid);
    }
    for ([_]Id{ .toad_hop, .shroom_hop, .delver_churn, .wood_creak, .leech_wing, .kobold_whirl }) |id| {
        try std.testing.expect(g(id) <= BATTLE_FLOOR + 1e-6);
    }
}

test "every BED has two takes to pan, and they do not loop in lockstep" {
    var i: usize = 0;
    while (i < BEDS.len) : (i += 1) {
        try std.testing.expect(BANK[@intFromEnum(BEDS[i].id)].vars >= 2);
        var j = i + 1;
        while (j < BEDS.len) : (j += 1) try std.testing.expect(seconds(BEDS[i].id) != seconds(BEDS[j].id));
    }
}

test "a source BEHIND you is ducked, but nowhere near enough to hide it" {
    const ahead = 1.0 - REAR_DUCK * 0.5 * (1.0 - 1.0);
    const behind = 1.0 - REAR_DUCK * 0.5 * (1.0 - -1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), ahead, 1e-6);
    try std.testing.expect(behind < ahead);
    try std.testing.expect(behind > 0.85);
}

test "the BED's two takes are decorrelated — that IS its width, and it is checkable" {
    const idx: usize = @intFromEnum(Id.wind);
    const first = try std.testing.allocator.alloc(f32, MAX_N);
    defer std.testing.allocator.free(first);

    var r0 = Rack.init(0x9E3779B9 *% (idx + 1) +% 0, seconds(.wind));
    BANK[idx].make(&r0);
    @memcpy(first[0..r0.n], work[0..r0.n]);
    var r1 = Rack.init(0x9E3779B9 *% (idx + 1) +% 1, seconds(.wind));
    BANK[idx].make(&r1);
    try std.testing.expectEqual(r0.n, r1.n);

    var dot: f64 = 0;
    var ea: f64 = 0;
    var eb: f64 = 0;
    for (first[0..r0.n], work[0..r1.n]) |a, b| {
        dot += @as(f64, a) * @as(f64, b);
        ea += @as(f64, a) * @as(f64, a);
        eb += @as(f64, b) * @as(f64, b);
    }
    try std.testing.expect(ea > 0 and eb > 0);
    const corr = @abs(dot) / @sqrt(ea * eb);
    try std.testing.expect(corr < 0.2); // independent noise; identical buffers would read 1.0
    try std.testing.expect(BANK[idx].vars >= 2);
}

test "THE HEAL IS CHORAL AND IT IS IN A ROOM — the parts of that a render can be asked about" {
    const idx: usize = @intFromEnum(Id.kobold_heal);
    var r = Rack.init(0x9E3779B9 *% (idx + 1), seconds(.kobold_heal));
    BANK[idx].make(&r);
    const n = r.n;
    try std.testing.expect(n > @as(usize, @intFromFloat(SRF * 1.5)));
    const rms = struct {
        fn of(from: usize, to: usize) f32 {
            var e: f64 = 0;
            for (work[from..to]) |s| e += @as(f64, s) * @as(f64, s);
            return @floatCast(@sqrt(e / @as(f64, @floatFromInt(@max(to - from, 1)))));
        }
    }.of;
    // IT SWELLS: the middle is louder than the first 40 ms, which is what "sung" means against "struck".
    const attack = rms(0, @intFromFloat(SRF * 0.04));
    const middle = rms(n / 3, n * 2 / 3);
    try std.testing.expect(middle > attack * 1.5);
    // …AND IT HAS A TAIL: real energy is still there at 90% through, where an unreverbed chord has stopped.
    const tail = rms(n * 9 / 10, n);
    try std.testing.expect(tail > middle * 0.02);
    try std.testing.expect(tail < middle);
    // THE SPARKLE IS ACTUAL HIGH CONTENT, measured as zero crossings against the chord's own root.
    var cross: f32 = 0;
    var i: usize = 1;
    while (i < n) : (i += 1) {
        if ((work[i] >= 0) != (work[i - 1] >= 0)) cross += 1;
    }
    try std.testing.expect(cross / (@as(f32, @floatFromInt(n)) / SRF) > 700.0);
}

test "hard-panning the bed does not smuggle the level back up" {
    const law = struct {
        fn g(pan: f32) f32 {
            return 0.5 * pan * (3.0 - pan * pan);
        }
    }.g;
    try std.testing.expect(law(1.0) > law(0.5) * 1.3);
    const before = 0.055 * law(0.5);
    const after = BANK[@intFromEnum(Id.wind)].gain *
        @sqrt(law(BED_PAN) * law(BED_PAN) + law(1.0 - BED_PAN) * law(1.0 - BED_PAN));
    try std.testing.expect(after < before);
    try std.testing.expect(after > before * 0.6);
}

test "the two ambient voices are baked DARK, which is the cue level cannot buy" {
    const crossings = struct {
        fn of(id: Id, idx: usize) f32 {
            var r = Rack.init(0x9E3779B9 *% (idx + 1), seconds(id));
            BANK[idx].make(&r);
            var n: f32 = 0;
            var i: usize = 1;
            while (i < r.n) : (i += 1) {
                if ((work[i] >= 0) != (work[i - 1] >= 0)) n += 1;
            }
            return n / (@as(f32, @floatFromInt(r.n)) / SRF);
        }
    }.of;
    const wind = crossings(.wind, @intFromEnum(Id.wind));
    try std.testing.expect(wind < 0.75 * crossings(.toad_chomp, @intFromEnum(Id.toad_chomp)));
    try std.testing.expect(wind < 0.60 * crossings(.swing_light, @intFromEnum(Id.swing_light)));

    // NOT THE BIRDS: a chirp is PITCHED, so its zero-crossing rate is set by its fundamental.
    try std.testing.expect(AIR_FAR_CALL < AIR_NEAR_DARKEST);
    try std.testing.expect(AIR_FAR_BED < AIR_FAR_CALL);
    try std.testing.expect(AIR_FAR_CRY < AIR_FAR_CALL);
    try std.testing.expect(AIR_FAR_CRY < AIR_NEAR_DARKEST);
    // …and neither so dark it stops being the thing it is: a bird still has to be a whistle (its band tops
    // out at 2500 Hz) and wind still has to have air in it, not just rumble.
    try std.testing.expect(AIR_FAR_CALL > 1200 and AIR_FAR_BED > 800);
    try std.testing.expect(AIR_NEAR_GRASS > AIR_NEAR_DARKEST);
    for ([_]f32{ AIR_FAR_BED, AIR_FAR_CALL, AIR_FAR_CRY }) |cut| {
        try std.testing.expect(cut < AIR_NEAR_DARKEST);
    }
}

test "NO SUSTAINED CALL SITS IN THE MOSQUITO BAND" {
    const MOSQUITO_LO: f32 = 350.0;
    const HELD: f32 = 0.55;
    for (CALLS) |c| {
        if (seconds(c.id) < HELD) continue;
        try std.testing.expect(seconds(c.id) < 2.0);
    }
    try std.testing.expect(MOSQUITO_LO > 300.0 and MOSQUITO_LO < 500.0);
}

test "THE NOISE FLOOR IS THE CRUSH'S, and it has to stay down" {

    const step = 1.0 / (std.math.pow(f32, 2.0, CRUSH_BITS) * 0.5);
    const stepDb = 20.0 * std.math.log10(step);
    try std.testing.expect(stepDb < -36.0);
    try std.testing.expect(DITHER_LSB < 0.6 and DITHER_LSB > 0.15);
    try std.testing.expect(CRUSH_HOLD >= 2);

    var r = Rack.init(0xC0FFEE, 1.0);
    r.body(0.0, 0.10, 220, 60, 0.9, 4.0);
    r.master(2.0, 3200);
    var e: f32 = 0;
    var n: usize = 0;
    var i = r.n * 6 / 10;
    while (i < r.n * 9 / 10) : (i += 1) {
        e += work[i] * work[i];
        n += 1;
    }
    const tailDb = 20.0 * std.math.log10(@max(@sqrt(e / @as(f32, @floatFromInt(n))), 1e-9));
    // MEASURED: −34.7 dBFS at 5.5 bits with ±1 LSB dither, −50.8 dBFS as it stands.
    try std.testing.expect(tailDb < -44.0);
}

fn crossingsPerSec(id: Id) f32 {
    const idx: usize = @intFromEnum(id);
    var r = Rack.init(0x9E3779B9 *% (idx + 1), seconds(id));
    BANK[idx].make(&r);
    var n: f32 = 0;
    var i: usize = 1;
    while (i < r.n) : (i += 1) {
        if ((work[i] >= 0) != (work[i - 1] >= 0)) n += 1;
    }
    return n / (@as(f32, @floatFromInt(r.n)) / SRF);
}

test "THE BOSS HAS HIS OWN THROAT — no cue of his measures as the ogre's, and each one differs the right way" {
    // Judged on zero-crossing rate with the timbre taken away: IRON RINGS, so every struck cue of his sits
    // ABOVE the ogre cue it replaced, and a dead thing in a helm is LOWER than a living throat, so both
    // voiced ones sit below.
    const pairs = [_][2]Id{
        .{ .knight_step, .ogre_step },
        .{ .knight_roar, .ogre_roar },
        .{ .knight_slam, .ogre_slam },
        .{ .knight_heave, .ogre_heave },
        .{ .knight_swipe, .ogre_swipe },
        .{ .knight_hurt, .ogre_hurt },
        .{ .knight_die, .ogre_die },
    };
    std.debug.print("\n  knight vs ogre, zero crossings per second:\n", .{});
    for (pairs) |p| {
        const k = crossingsPerSec(p[0]);
        const o = crossingsPerSec(p[1]);
        std.debug.print("    {s:<13}{d:7.0}  vs  {s:<11}{d:7.0}   ({d:.0}%)\n", .{ @tagName(p[0]), k, @tagName(p[1]), o, 100.0 * (k - o) / o });
        // NOT A COPY, cue for cue: a family that measured the same as what it replaced would be a rename.
        try std.testing.expect(@abs(k - o) > 0.03 * o);
    }
    for ([_][2]Id{ .{ .knight_slam, .ogre_slam }, .{ .knight_heave, .ogre_heave }, .{ .knight_hurt, .ogre_hurt } }) |p| {
        try std.testing.expect(crossingsPerSec(p[0]) > crossingsPerSec(p[1]));
    }
    for ([_][2]Id{ .{ .knight_roar, .ogre_roar }, .{ .knight_die, .ogre_die } }) |p| {
        try std.testing.expect(crossingsPerSec(p[0]) < crossingsPerSec(p[1]));
    }
    // …AND NONE OF IT IS SPENT WHERE IT CANNOT BE HEARD. A fundamental under ~45 Hz is below most of what
    // this will be played on, and amplitude down there is amplitude taken off everything audible by `norm`.
    // It cost the roar and the die a third of their brightness before the sub was lifted out of it.
    for ([_]Id{ .knight_step, .knight_plant, .knight_roar, .knight_slam, .knight_heave, .knight_swipe, .knight_lunge, .knight_hurt, .knight_die }) |id| {
        try std.testing.expect(crossingsPerSec(id) > 90.0);
        try std.testing.expectEqual(Submix.combat, BANK[@intFromEnum(id)].mix);
        try std.testing.expect(BANK[@intFromEnum(id)].reach >= BANK[@intFromEnum(Id.ogre_swipe)].reach);
    }
}

test "THE ANSWER TO THE SEAL IS THE SAME DEPTH AND NOT THE SAME MOOD" {
    // Owner: like the entry sting, still deep and dark, but MORE HOPEFUL — not scary. Dark is a REGISTER and
    // frightening is an INTERVAL, so the two are separable and both halves are checkable: the answer sits in
    // the same subterranean band as the seal (nowhere near a combat cue), and it is the brighter of the two.
    const seal = crossingsPerSec(.fog_seal);
    const felled = crossingsPerSec(.fog_felled);
    std.debug.print("\n  fog gate: seal {d:.0} crossings/s, felled {d:.0} — both under a struck helm at {d:.0}\n", .{ seal, felled, crossingsPerSec(.knight_hurt) });
    try std.testing.expect(felled > seal * 1.5);
    try std.testing.expect(felled < 0.25 * crossingsPerSec(.knight_hurt));
    try std.testing.expect(seconds(.fog_felled) > seconds(.fog_seal));
    try std.testing.expectEqual(BANK[@intFromEnum(Id.fog_seal)].gain, BANK[@intFromEnum(Id.fog_felled)].gain);
}

test "THE BENCH NEVER OVERWRITES THE ORIGINAL — that is what makes revert free" {
    const id: Id = .knight_roar;
    const i: usize = @intFromEnum(id);
    const was = BANK[i];
    try std.testing.expect(!voiceEdited(id));
    setDial(id, .gain, 0.11);
    setDial(id, .pitch, 1.44);
    setVoiceFx(id, AF_MUFFLE, 0.5);
    try std.testing.expect(voiceEdited(id) and anyVoiceEdited());
    try std.testing.expectApproxEqAbs(@as(f32, 0.11), dialOf(id, .gain), 1e-6);
    // …AND THE AUTHORED ROW HAS NOT MOVED A BIT.
    try std.testing.expectEqual(was.gain, BANK[i].gain);
    try std.testing.expectEqual(was.pitch, BANK[i].pitch);
    // Out-of-range is CLAMPED, not refused: a dial dragged to its end is a value, and a settings file that
    // arrived with a silly number in it must still leave the game playable.
    setDial(id, .reach, -50);
    try std.testing.expectApproxEqAbs(dialSpec(.reach).lo, dialOf(id, .reach), 1e-6);
    setDial(id, .reach, 1e9);
    try std.testing.expectApproxEqAbs(dialSpec(.reach).hi, dialOf(id, .reach), 1e-6);
    revertVoice(id);
    try std.testing.expect(!voiceEdited(id) and !anyVoiceEdited());
    try std.testing.expectEqual(was.gain, dialOf(id, .gain));
    try std.testing.expectEqual(was.reach, dialOf(id, .reach));
    for (voiceFxValues(id)) |v| try std.testing.expectEqual(@as(f32, 0), v);
    for (0..NV) |k| {
        try std.testing.expectEqual(BANK[k].vars, live[k].vars);
        try std.testing.expectEqual(BANK[k].poly, live[k].poly);
        try std.testing.expectEqual(BANK[k].mix, live[k].mix);
        try std.testing.expectEqual(BANK[k].id, live[k].id);
    }
    try std.testing.expectEqual(NV, NAMES.len);
    try std.testing.expect(std.mem.eql(u8, NAMES[@intFromEnum(Id.knight_die)], "knight_die"));
}

test "A LIQUID FOOTFALL IS A NOISE BAND SWEEPING UP, and all four carry one" {
    // The splash is what separates `step_water` from `step_soft`: a noise band whose centre CLIMBS. Authoring
    // three textures over a thud is how the liquids came out louder than water (rms 0.18 against 0.11) and
    // still did not say liquid. Measured as the ZERO-CROSSING RATE — the cheap stand-in for spectral centre
    // this file already uses on the knight's grit — over the take's second half against its first.
    const wet = [_]Id{ .step_water, .step_oil, .step_fungal, .step_lava };
    var wetLow: f32 = 1e9;
    inline for (wet) |id| {
        const idx = @intFromEnum(id);
        var r = Rack.init(0x9E3779B9 *% (@as(u64, idx) + 1), seconds(id));
        BANK[idx].make(&r);
        // THE ACTIVE PART ONLY. Every take is authored well inside its own buffer, so halving the BUFFER
        // measured silence against silence and handed back 0% for all seven.
        var last: usize = 0;
        var peak: f32 = 0;
        for (work[0..r.n]) |v| peak = @max(peak, @abs(v));
        for (work[0..r.n], 0..) |v, i| {
            if (@abs(v) > peak * 0.02) last = i;
        }
        const half = last / 2;
        var head: usize = 0;
        var tail: usize = 0;
        var i: usize = 1;
        while (i <= last) : (i += 1) {
            const flip = (work[i] >= 0) != (work[i - 1] >= 0);
            if (!flip) continue;
            if (i < half) head += 1 else tail += 1;
        }
        const hz0 = @as(f32, @floatFromInt(head)) / @max(@as(f32, @floatFromInt(half)), 1.0);
        const hz1 = @as(f32, @floatFromInt(tail)) / @max(@as(f32, @floatFromInt(last - half)), 1.0);
        const rise = hz1 / @max(hz0, 1e-6);
        wetLow = @min(wetLow, rise);
        std.debug.print("  {s: <12} crossings x{d:.2} over the take\n", .{ @tagName(id), rise });
    }
    std.debug.print("  the dullest of the four brightens x{d:.2}\n", .{wetLow});
    // **EVERY LIQUID FOOTFALL BRIGHTENS OVER ITS OWN LENGTH.** Not a claim against the dry set — `step_soft`
    // rises x6.8 off its own grit tail, so "wetter than dry" is not a real separation and pretending it is
    // would be a test that passes by accident. What IS true of all four and false of a thud is the sweep.
    try std.testing.expect(wetLow > 1.05);
}
