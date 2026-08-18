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

/// Chamberlin state-variable filter coefficients. Separate from the filter step because for a FIXED cutoff
/// they never change, and the per-sample `sin` was 90 ms of the heal's bake time (measured).
const SvfCoef = struct { f: f32, q: f32 };

fn svfCoef(cut: f32, res: f32) SvfCoef {
    return .{
        .f = 2.0 * mathx.sinf(std.math.pi * mathx.clampF(cut, 20.0, SRF / 6.0) / SRF),
        .q = mathx.clampF(1.6 - 1.55 * res, 0.05, 2.0),
    };
}

/// Named, not anonymous: two identically-shaped anonymous structs are distinct types to Zig, so `step`
/// forwarding to `stepAt` would not compile.
const SvfOut = struct { lp: f32, bp: f32, hp: f32 };

const Svf = struct {
    lp: f32 = 0,
    bp: f32 = 0,

    /// For a FIXED cutoff; `step` is the sweeping one.
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

/// Exponential decay 1→0 over `dur`, `curve` steepening it (1 = gentle, 6 = a spike).
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
    n: usize = 0, // samples written so far (the voice's length)
    rng: mathx.Rng,
    /// Layers that rendered nothing — authored past the voice's own length, so they emit zero samples
    /// silently. A test bakes the bank and asserts this stays 0.
    dropped: usize = 0,

    // `secs`, not `seconds`: that name is the bank's length table below, and shadowing is a Zig compile error.
    fn init(seed: u64, secs: f32) Rack {
        const n = @min(@as(usize, @intFromFloat(secs * SRF)), MAX_N);
        @memset(work[0..n], 0);
        return .{ .n = n, .rng = mathx.Rng.init(seed) };
    }

    fn at(r: *const Rack, t: f32) usize {
        return @min(@as(usize, @intFromFloat(mathx.maxF(t, 0) * SRF)), r.n);
    }

    /// `null` when the take has no room for the layer at all.
    fn span(r: *Rack, t0: f32, dur: f32) ?Span {
        const a = r.at(t0);
        const b = @min(a + r.at(dur), r.n);
        if (a >= b) {
            r.dropped += 1;
            return null;
        }
        return .{ .a = a, .b = b };
    }

    fn body(r: *Rack, t0: f32, dur: f32, f0: f32, f1: f32, amp: f32, curve: f32) void {
        const s = r.span(t0, dur) orelse return;
        var ph: f32 = 0;
        var i = s.a;
        while (i < s.b) : (i += 1) {
            const u = s.u(i);
            const f = f0 * std.math.pow(f32, f1 / f0, u);
            ph += std.math.tau * f / SRF;
            work[i] += mathx.sinf(ph) * amp * decay(u, curve);
        }
    }

    fn air(r: *Rack, t0: f32, dur: f32, amp: f32, c0: f32, c1: f32, res: f32, curve: f32) void {
        const s = r.span(t0, dur) orelse return;
        var f = Svf{};
        var i = s.a;
        while (i < s.b) : (i += 1) {
            const u = s.u(i);
            const cut = c0 * std.math.pow(f32, c1 / c0, mathx.smoothstep(0, 1, u));
            const out = f.step(r.rng.signed(), cut, res);
            work[i] += out.bp * amp * decay(u, curve);
        }
    }

    /// Lowpassed noise with a granular amplitude, so it CRUNCHES instead of hissing.
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
            if (f > SRF * 0.45) continue; // never alias a partial back down into the body
            const g = amp / (1.0 + @as(f32, @floatFromInt(k)) * 1.3);
            const d = curve * (1.0 + @as(f32, @floatFromInt(k)) * 0.45); // highs die first, as they do
            const ph0 = r.rng.angle();
            var i = a;
            while (i < b) : (i += 1) {
                work[i] += mathx.sinf(ph0 + std.math.tau * f * @as(f32, @floatFromInt(i - a)) / SRF) * g * decay(s.u(i), d);
            }
        }
    }

    fn growl(r: *Rack, t0: f32, dur: f32, f0: f32, f1: f32, amp: f32, rough: f32, shape: f32) void {
        const s = r.span(t0, dur) orelse return;
        var f = Svf{};
        var ph: f32 = 0;
        var vib: f32 = 0;
        var i = s.a;
        while (i < s.b) : (i += 1) {
            const u = s.u(i);
            vib += std.math.tau * (5.5 + 3.0 * u) / SRF;
            const hz = f0 * std.math.pow(f32, f1 / f0, u) * (1.0 + 0.035 * mathx.sinf(vib));
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

    /// Detuned unison "ahh"s. What makes it voices rather than an organ: formants (~730 and ~1090 Hz for
    /// "ah") plus per-voice detune/vibrato/entry, whose beating IS the choral sound. The bank's most
    /// expensive layer (~70 ms of the heal's bake, Debug); a table LFO would trade that beating away.
    fn choir(r: *Rack, t0: f32, dur: f32, f0: f32, amp: f32, voices: u32, peak: f32) void {
        const s = r.span(t0, dur) orelse return;
        const a = s.a;
        const b = s.b;
        var v: u32 = 0;
        while (v < voices) : (v += 1) {
            const detune = 1.0 + r.rng.signed() * 0.006; // ±10 cents: a choir, not a chorus pedal
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

    /// Short high bells on a PENTATONIC ladder, so a shimmer never lands on a note that fights the chord
    /// under it — random pitches here read as a broken wind chime.
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

    /// Three feedback combs, each fed back through a one-pole so the tail darkens as it dies — that
    /// darkening is what separates a reverb from a stack of echoes. Feed-forward in time (sample i reads
    /// only earlier samples), so it cannot blow up and needs no second buffer.
    fn hall(r: *Rack, secs: f32, cut: f32) void {
        const taps = [_]f32{ 0.0297, 0.0371, 0.0411 }; // prime-ish, so their echoes never line up
        for (taps) |d| {
            const lag = @max(r.at(d), 1);
            if (lag >= r.n) continue;
            // THE GAIN *IS* THE DECAY TIME: g^(secs/d) = -60 dB. Trimming it by a separate "wet" factor
            // shortens the tail rather than quieting it; level is `norm`'s job at the end of the chain.
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
                // A narrow pulse, not a square: the duty is what gives it that thin reedy whistle.
                const pulse: f32 = if (ph < 0.30) 1.0 else -1.0;
                work[i] += lp.step(pulse, 2600) * amp * decay(u, 3.0) * mathx.smoothstep(0, 0.15, u);
            }
            t += dur + r.rng.range(0.012, 0.045);
        }
    }


    fn sat(r: *Rack, drive: f32) void {
        for (work[0..r.n]) |*s| {
            const x = s.* * drive;
            s.* = x / (1.0 + @abs(x)); // a cheap tanh, and the asymmetry-free one we want
        }
    }

    fn warm(r: *Rack, cut: f32) void {
        var p = Pole{};
        for (work[0..r.n]) |*s| s.* = p.step(s.*, cut);
    }

    fn wow(r: *Rack, depth: f32, rate: f32) void {
        if (r.n < 64) return;
        @memcpy(tape[0..r.n], work[0..r.n]);
        const maxLag = depth * SRF; // samples
        var i: usize = 0;
        while (i < r.n) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / SRF;
            // Two incommensurate rates: one is a wobble, two is a drift with a wobble on it.
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
            // TPDF dither — two uniform draws summed.
            const d = (r.rng.signed() + r.rng.signed()) * 0.5 / levels * DITHER_LSB;
            s.* = @round((held + d) * levels) / levels;
        }
    }

    /// The telephone / transistor-radio read. NOT a lowpass — it loses the BOTTOM as well as the top, and
    /// the bottom going is the half the ear hears as "through a speaker". Mixed, so the dial sweeps into it.
    fn band(r: *Rack, cut: f32, res: f32, amt: f32) void {
        const c = svfCoef(cut, res);
        var f = Svf{};
        for (work[0..r.n]) |*s| {
            const out = f.stepAt(s.*, c);
            s.* = mathx.lerpF(s.*, out.bp, mathx.clampF(amt, 0, 1));
        }
    }

    /// A high pass built as "the signal less its own low end", so one `Pole` does it and the dial is how
    /// much body is taken away.
    fn thin(r: *Rack, cut: f32, amt: f32) void {
        var p = Pole{};
        const k = mathx.clampF(amt, 0, 1);
        for (work[0..r.n]) |*s| {
            const low = p.step(s.*, cut);
            s.* = s.* - low * k;
        }
    }

    /// A band ADDED rather than blended in — `band` lerps, which cannot boost. This is the bite a muffled
    /// voice gets its legibility back from.
    fn lift(r: *Rack, cut: f32, res: f32, amt: f32) void {
        const c = svfCoef(cut, res);
        var f = Svf{};
        const k = mathx.clampF(amt, 0, 1);
        for (work[0..r.n]) |*s| {
            const out = f.stepAt(s.*, c);
            s.* += out.bp * k;
        }
    }

    /// Vinyl crackle. The SPARSENESS is the point — dense, it is just `hiss` with a worse spectrum; what
    /// reads as age is the silence between the clicks.
    fn crackle(r: *Rack, amt: f32, perSec: f32) void {
        const chance = perSec / SRF; // …that a given sample is where a pop starts
        const life = @max(r.at(0.0022), 2); // a pop is a couple of milliseconds and nothing more
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
/// DITHER DEPTH IN LSB, and the textbook ±1 is a SIXTEEN-BIT rule.
const DITHER_LSB: f32 = 0.4;
const CRUSH_HOLD: u32 = 2;

// Air-absorption cutoffs in Hz — the cue that makes a sound read as FAR rather than as quiet.
const AIR_FAR_BED: f32 = 1400;
const AIR_FAR_CALL: f32 = 2100;
const AIR_FAR_CRY: f32 = 1950;
/// The darkest any NEAR voice is rendered.
const AIR_NEAR_DARKEST: f32 = 2200;
const AIR_NEAR_GRASS: f32 = 4200;

// Order is the BANK table's order below; the two are pinned at comptime.
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
    /// YOUR blow stopped on somebody else's boards. `guard_block` is the hero's own shield eating a blow —
    /// the opposite event — and one voice for both makes a swing that achieved nothing sound like one that
    /// saved you.
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
    ravager_bloom,
    ravager_leap,
    ravager_snap,
    ravager_hurt,
    ravager_die,
    mage_kindle,
    mage_throw,
    mage_hurt,
    mage_die,
    ember_bounce,
    ember_burst,
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
    // THE SHADE has no throat: every one of these is AIR and RING and nothing that could be a larynx.
    shade_reach,
    shade_gather,
    shade_wisp,
    shade_touch,
    shade_blink,
    shade_hurt,
    shade_die,
    leech_wing, // retriggered on a fly's cadence, since a synthesized take cannot loop
    leech_stab,
    leech_drink, // …likewise retriggered, while it holds on
    leech_hurt,
    leech_die,
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
    // THE SOULS are gold and AIR, no wood and no iron — audibly a different substance from the chest and
    // the flask beside them.
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
    crickets, // a BED, and the only ambient voice rendered bright
    // THE SUMMONED WOLF has a throat, unlike the shade. What says it is a spirit is the TAIL on every voice
    // — author the larynx honestly and let the reverb be the only unearthly thing.
    wolf_howl,
    wolf_growl,
    wolf_bite,
    wolf_hurt,
    wolf_die,
};
const NV = @typeInfo(Id).@"enum".fields.len;

pub const Submix = enum {
    sfx,
    combat,
    ambience,
};
const NMIX = @typeInfo(Submix).@"enum".fields.len;

const TRIM_AMBIENCE: f32 = 0.625;
/// THE FIGHT SITS UNDER EVERYTHING ELSE (owner's call). The one dial reaching the WHOLE family — the
/// `battle()` band and the literal-gain rows both — where `BATTLE_FLOOR` only moves the band.
const TRIM_COMBAT: f32 = 0.46;
const TRIM_SFX: f32 = 0.65;

/// One author-side pole over every combat voice at bake (`bakeRow`), UNDER the player's own rack so a dial
/// still sits on top of it. The body of every one of these is well below it, so the cut costs no weight.
const COMBAT_TREBLE: f32 = 6200;

/// Author-side level per family, paid before the player's dial sees it. No family ships at unity (owner's
/// call: quieter at the SOURCE, so an untouched slider still hears the intended mix).
fn submixTrim(m: Submix) f32 {
    return switch (m) {
        .sfx => TRIM_SFX,
        .combat => TRIM_COMBAT,
        .ambience => TRIM_AMBIENCE,
    };
}

// The player's filter rack, one per `Submix`. BAKE-TIME, not playback-time, and it has to be: raylib gives
// volume/pitch/pan per playing sound and nothing else. Moving a dial re-renders that family (`tickFx`).

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
/// Added last so the character filters above keep their indices — a `settings.cfg` written before them
/// reads back with these two at 0, which is off.
pub const AF_BASS = 9;
pub const AF_PRESENCE = 10;

/// One row per filter in AF_* order (`gfx.RETRO_FILTERS`' shape), so the menu labels are DERIVED.
const AudioFilter = struct { name: [:0]const u8 };
const AUDIO_FILTERS = [AFX_COUNT]AudioFilter{
    .{ .name = "Drive" },
    .{ .name = "Bit Crush" },
    .{ .name = "Sample Hold" },
    .{ .name = "Muffle" },
    .{ .name = "Telephone" },
    .{ .name = "Wow & Flutter" },
    .{ .name = "Room" },
    .{ .name = "Tape Hiss" },
    .{ .name = "Vinyl Crackle" },
    .{ .name = "Bass Cut" },
    .{ .name = "Presence" },
};
pub const AFX_NAMES = blk: {
    var out: [AFX_COUNT][:0]const u8 = undefined;
    for (&out, AUDIO_FILTERS) |*o, f| o.* = f.name;
    break :blk out;
};

comptime {
    // AF_* must line up with AUDIO_FILTERS' rows, or a dial moves the wrong filter.
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
/// The house sound (owner's call): what the game LAUNCHES as, on all three families. `AFX_DEFAULTS` is
/// derived from this row, so "Reset to Default" and "Preset: Worn Tape" cannot come to mean two things.
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

/// In signal-path order: distort, quantise, band-limit, warp, place in a room, then the medium's own noise.
fn applyFx(r: *Rack, m: Submix) void {
    if (!anyFxIn(m)) return;
    const v = fxVals[@intFromEnum(m)];
    if (v[AF_DRIVE] > AFX_EPS) r.sat(1.0 + 7.0 * v[AF_DRIVE]);
    if (v[AF_CRUSH] > AFX_EPS) r.crush(mathx.lerpF(CRUSH_BITS, 2.0, v[AF_CRUSH]), 1);
    // 16 bits = no audible quantise, so this dial is the HOLD alone: the sample rate coming down.
    if (v[AF_ALIAS] > AFX_EPS) r.crush(16, 1 + @as(u32, @intFromFloat(v[AF_ALIAS] * 15.0)));
    if (v[AF_MUFFLE] > AFX_EPS) r.warm(mathx.lerpF(SRF * 0.45, 320.0, v[AF_MUFFLE]));
    if (v[AF_TELEPHONE] > AFX_EPS) r.band(1450.0, 0.35, v[AF_TELEPHONE]);
    if (v[AF_WOBBLE] > AFX_EPS) r.wow(0.0016 + 0.010 * v[AF_WOBBLE], 1.7 + 3.0 * v[AF_WOBBLE]);
    if (v[AF_ROOM] > AFX_EPS) r.hall(0.12 + 1.5 * v[AF_ROOM], 2600.0);
    if (v[AF_HISS] > AFX_EPS) r.hiss(0.012 + 0.09 * v[AF_HISS]);
    if (v[AF_CRACKLE] > AFX_EPS) r.crackle(0.05 + 0.30 * v[AF_CRACKLE], 6.0 + 340.0 * v[AF_CRACKLE]);
    // THE EQ LAST: it is the tone of the RESULT, and a presence lift ahead of the drive is more to distort.
    if (v[AF_BASS] > AFX_EPS) r.thin(120.0 + 220.0 * v[AF_BASS], v[AF_BASS]);
    if (v[AF_PRESENCE] > AFX_EPS) r.lift(3200.0, 0.5, 0.9 * v[AF_PRESENCE]);
    r.norm(0.92);
    r.ends(0.002, 0.012);
}

/// Seconds a dial must sit still before its family is re-rendered — a held slider glides at frame rate and
/// a re-bake is tens of ms.
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

/// Ticked once a frame from the live loop (REAL time — this is a UI settle, not a game clock).
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
}

const Row = struct {
    /// Here to be CHECKED, not read: `BANK` is indexed by `@intFromEnum`, so an `Id` inserted without its row
    /// leaves the lengths agreeing while every voice below plays its neighbour's recipe.
    id: Id,
    make: *const fn (*Rack) void,
    gain: f32 = 0.7,
    mix: Submix = .sfx,
    jit: f32 = 0.06,
    vjit: f32 = 0.12,
    vars: u8 = 1,
    poly: u8 = 2,
    /// Metres. The range `world()` fades it out over, past which it costs nothing at all.
    reach: f32 = FALLOFF,
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

fn mkRoll(r: *Rack) void {
    // Cloth and grit over dirt, and NOTHING THAT SWEEPS.
    r.grit(0.0, 0.20, 0.34, 1100, 0.55, 3.0);
    r.body(0.05, 0.16, 78, 40, 0.42, 4.5);
    r.grit(0.24, 0.13, 0.20, 1700, 0.45, 4.0);
    r.air(0.0, 0.16, 0.10, 900, 480, 0.10, 3.2);
    r.master(1.15, 2600);
}

fn mkJump(r: *Rack) void {
    // NO TRANSIENT: a `tick` on the front of this is the LANDING's, and the pair reads as one event twice.
    r.air(0.0, 0.14, 0.30, 520, 1100, 0.26, 4.2);
    r.grit(0.0, 0.08, 0.24, 1800 + r.rng.signed() * 300, 0.45, 5.2);
    r.body(0.0, 0.09, 96, 44, 0.28, 5.5);
    r.master(1.2, 3200);
}

fn mkLand(r: *Rack) void {
    // The sprint step is the reference and this sits over it — same BOOT, not a thud out of the combat bank.
    r.tick(0.0, 0.26, 2600);
    r.body(0.0, 0.21, 96 + r.rng.signed() * 10, 36, 1.0, 3.3);
    r.grit(0.004, 0.19, 0.48, 1900 + r.rng.signed() * 400, 0.55, 3.8);
    r.air(0.05, 0.15, 0.14, 700, 420, 0.14, 3.0);
    r.master(2.0, 3200);
}

fn mkSwingLight(r: *Rack) void {
    // MOVED AIR, not a cartoon vwip (owner's call).
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

fn mkGuardBlock(r: *Rack) void {
    r.tick(0.0, 0.42, 3400);
    r.body(0.0, 0.13, 190, 78, 0.95, 5.0);
    r.grit(0.0, 0.07, 0.30, 2400, 0.4, 6.0);
    r.ring(0.003, 0.09, 940, 0.16, 8.0, 2);
    r.master(1.6, 4200);
}

/// **THE TOWER SHIELD TURNING A BLOW** (owner: it needs a better shield repel sound). The same event as
/// `guard_block` on a WALL rather than a man's boards: almost no tick, a deep body that takes its time, and
/// the ring dropped two octaves, so what comes back is the mass and not the edge. Longer and darker than
/// anything else in the block family — what the player has to hear is that this one did not care.
fn mkKnightRepel(r: *Rack) void {
    r.tick(0.0, 0.16, 1900);
    r.body(0.0, 0.30, 104, 44, 1.15, 2.8); // the plank itself, struck
    r.body(0.0, 0.13, 58, 30, 0.85, 2.0); // …and the mass behind it
    r.grit(0.0, 0.12, 0.34, 1500, 0.55, 3.6);
    r.ring(0.005, 0.22, 320, 0.13, 4.2, 3); // iron banding, low and short — not a bell
    r.air(0.04, 0.20, 0.18, 900, 240, 0.22, 3.0);
    r.master(2.2, 2600);
}

/// **YOUR BLOW STOPPED DEAD ON SOMEBODY'S BOARDS** (owner: a distinct sound any time your attack is blocked
/// by a shield). It has to be unmistakable against the two things it is not — a hit that landed, and the
/// hero's own guard eating a blow — so it is built backwards from a hit: the transient DULL rather than
/// bright, no meat under it, and dead almost at once.
fn mkFoeGuarded(r: *Rack) void {
    r.tick(0.0, 0.30, 2100); // low and woody: wood and hide, not an edge finding bone
    r.body(0.0, 0.11, 148, 66, 0.75, 4.4);
    r.grit(0.0, 0.08, 0.38, 1800, 0.5, 5.2);
    r.ring(0.004, 0.07, 620, 0.10, 7.0, 2); // a short iron slap off the rim, cut off fast
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
    // THE METAL COMES FROM NOISE, and both alternatives sound like a toy: `body` GLIDES its pitch, so one
    // in the mid register is a cartoon boing, and a `ring` past two or three partials is a spring reverb.
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


// THE SPORELING — cute shapes with one wrong thing in each (owner: "slightly unnerving"), and the wrongness
// is always PITCH doing what a happy sound would not: bending flat, sliding up too far, leaking out.
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


// THE DELVER — EARTH, and earth has no ring in it (the Rooted's rule for wood, one substance along). Every
// voice here is grit over a body low enough to be felt rather than heard, and the pitch of the whole family
// climbs exactly once: the surge. That climb IS the tell.

/// Cut a hair LONGER than `delver.CHURN_EVERY` so consecutive takes overlap — the leechfly's whine rule, and
/// gapped it chatters into a machine rather than a thing ploughing.
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

/// THE ONE THING IN THIS FAMILY THAT RISES. Both bodies sweep UP through the whole of it, so the tell says
/// something is coming rather than that something is happening.
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


/// The shared rip: broadband noise sweeping DOWN fast.
fn arrowRip(r: *Rack, amp: f32) void {
    r.air(0.0, 0.13, amp, 5200, 900, 0.35, 3.4); // the tear
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


/// MINERAL, not a throat. Must be OVER by the throw (see `seconds`), or a chained cast leaves the last
/// gather still climbing under the next crack.
fn mkWandCharge(r: *Rack) void {
    r.air(0.0, 0.34, 0.34, 700, 3800, 0.66, 1.1);
    r.growl(0.02, 0.32, 150, 430, 0.30, 0.26, 0.42);
    r.ring(0.05, 0.30, 880, 0.15, 3.0, 3);
    r.grit(0.0, 0.28, 0.12, 3000, 0.30, 1.2);
    r.master(1.5, 4400);
}

/// A CRACK, not a boom: the bolt is 24 damage of the most-resisted element, and a cannon would promise a
/// hit the numbers cannot pay for.
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


// Every recipe below is AIR, RING and GRIT and never a `growl` — a growl is a throat, and this creature
// must not have one. What makes it a voice at all is that the air is PITCHED and something mineral rings.

fn mkShadeReach(r: *Rack) void {
    r.air(0.0, 0.34, 0.40, 2600, 620, 0.72, 1.5);
    r.ring(0.04, 0.26, 214, 0.11, 3.4, 3);
    r.grit(0.0, 0.20, 0.07, 900, 0.55, 2.2);
    r.master(1.5, 3000);
}

/// Must resolve ON the throw (`shade.MOVES[WISP].windDur`) — the wand's own charge law.
fn mkShadeGather(r: *Rack) void {
    r.air(0.0, 0.66, 0.36, 480, 3100, 0.80, 1.0);
    r.ring(0.10, 0.56, 296, 0.13, 2.2, 4);
    r.ring(0.28, 0.42, 444, 0.09, 2.6, 3);
    r.grit(0.06, 0.58, 0.06, 2400, 0.30, 1.1);
    r.master(1.4, 4200);
}

// WOOD IS GRIT AND A LOW BODY, never a ring — a ring is metal or glass. Everything here is fibre tearing.

fn mkWoodWake(r: *Rack) void {
    r.grit(0.0, 0.62, 0.52, 900, 0.72, 0.6);
    r.growl(0.02, 0.70, 44, 84, 0.40, 0.42, 0.5);
    r.air(0.0, 0.66, 0.20, 700, 2200, 0.30, 0.5);
    r.crackle(0.34, 40.0);
    r.body(0.44, 0.26, 92, 38, 0.34, 3.4);
    r.master(2.0, 2600);
}

/// No transient at the front of it, or it reads as a footstep.
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

/// RISES, where everything else in this bank decays — a thing taking something OUT of you has to go the
/// other way or it reads as a splash.
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

/// ONE sound, played at both ends of the jump — so it carries the rip out and the collapse after it,
/// whichever end of the blink you are standing at.
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

/// CHORAL AND HEAVENLY (owner's call) — one high ring read as a UI ping mid-fight.
fn mkKoboldHeal(r: *Rack) void {
    const ROOT: f32 = 330.0; // E4 — high enough to cut a fight, low enough not to shriek
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

// A REAL LARYNX (the kobold's kit) plus one thing on every voice: a long `ring` tail under the note that
// keeps sounding after the animal has stopped. That tail is the only unearthly thing in any of them.

/// A real howl is ONE LONG GLIDE, not a siren — the pitch travels the whole way and never sits still.
fn mkWolfHowl(r: *Rack) void {
    // NO SECOND VOICE AT A FIFTH: held against a sustained tone that is a CHORD, and the ear hears an organ
    // rather than an animal. The ring tails stay tuned ON the note — detuned they are out of tune, not
    // ethereal (owner: it sounded crazy weird).
    r.body(0.0, 0.80, 150, 134, 0.34, 1.2);
    r.growl(0.0, 0.30, 200, 400, 0.54, 0.09, 0.03);
    r.growl(0.24, 0.60, 408, 384, 0.66, 0.06, 0.02);
    r.growl(0.78, 0.52, 380, 214, 0.48, 0.11, 0.05);
    r.air(0.0, 1.10, 0.08, 700, 400, 0.08, 1.0);
    r.ring(0.34, 0.85, 192, 0.06, 1.1, 3);
    r.master(1.15, 2000);
}

/// Short, because a growl that runs long turns into a note.
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
    // A BLADE INTO A MEMBRANE: no crack and no bone, or it sounds like hitting a body.
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


/// The sweep runs DOWN, and that is the only part that has to be right: this is a loss, and a rising
/// figure reads as a reward.
fn mkSoulsSpill(r: *Rack) void {
    r.ring(0.0, 0.70, 523, 0.40, 2.6, 4);
    r.ring(0.03, 0.62, 349, 0.30, 2.4, 3);
    r.air(0.0, 0.85, 0.34, 3400, 420, 0.55, 1.5);
    r.body(0.05, 0.55, 190, 62, 0.34, 2.2);
    r.master(1.7, 5200);
}

/// Cut short enough that the retrigger in `souls.zig` overlaps its own takes rather than chattering.
fn mkSoulsHum(r: *Rack) void {
    r.ring(0.0, 1.30, 262, 0.26, 1.1, 3);
    r.ring(0.10, 1.05, 392, 0.13, 1.3, 2);
    r.air(0.0, 1.20, 0.09, 700, 1300, 0.30, 1.0);
    r.master(1.2, 4200);
}

/// The spill's own figure run the other way — the sweep CLIMBS, and it is over before the counter stops.
fn mkSoulsTake(r: *Rack) void {
    r.air(0.0, 0.30, 0.30, 500, 4800, 0.52, 2.6);
    r.ring(0.05, 0.44, 523, 0.42, 3.4, 4);
    r.ring(0.09, 0.38, 784, 0.30, 4.0, 3);
    r.ring(0.13, 0.30, 1046, 0.18, 5.0, 2);
    r.master(2.0, 6400);
}

fn mkRingSnap(r: *Rack) void {
    r.tick(0.0, 0.62, 7200);
    r.ring(0.0, 0.20, 1568, 0.34, 7.0, 2);
    r.ring(0.01, 0.11, 2093, 0.20, 9.0, 1);
    r.grit(0.0, 0.05, 0.22, 5200, 0.5, 6.0);
    r.master(2.2, 7000);
}

/// NOT another roar: the roar at the top of the wind already said a swing was coming, and two of the same
/// shape a second apart read as one long noise.
fn mkOgreHeave(r: *Rack) void {
    r.growl(0.0, 0.26, 168, 76, 0.62, 0.42, 3.4);
    r.air(0.0, 0.30, 0.34, 900, 320, 0.42, 2.8);
    r.body(0.0, 0.14, 92, 44, 0.40, 3.0);
    r.grit(0.02, 0.16, 0.24, 1400, 0.7, 2.6);
    r.master(2.2, 3200);
}

fn mkKill(r: *Rack) void {
    // A KILL IS A THUD (owner's call, twice over): no bell, no jingle.
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
    // PER-TAKE GUST PHASES.
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


const CRICKETS = 7; // individuals near enough to be heard APART; past that it is a chirr, not a field
const CRICKET_SING: f32 = 0.22; // fraction of its own cycle one cricket is actually singing

fn mkCrickets(r: *Rack) void {
    var hz: [CRICKETS]f32 = undefined; // stridulation pitch — species and body size
    var rate: [CRICKETS]f32 = undefined; // chirps per second
    var at: [CRICKETS]f32 = undefined;
    var amp: [CRICKETS]f32 = undefined; // how near it is
    var pulses: [CRICKETS]f32 = undefined; // pulses per chirp
    var ph: [CRICKETS]f32 = [_]f32{0} ** CRICKETS; // accumulated, not f*t: at 8 s an f32 product of a
    // 4 kHz phase has lost its low bits and the pitch wobbles audibly
    for (0..CRICKETS) |k| {
        hz[k] = r.rng.range(3500, 5200);
        rate[k] = r.rng.range(1.7, 3.1);
        at[k] = r.rng.float();
        amp[k] = r.rng.range(0.18, 1.0);
        pulses[k] = @floor(r.rng.range(3, 6));
    }
    var band = Svf{};
    var far = Pole{};
    const q = r.rng.angle(); // the distant field's own swell clock, rolled per take
    var i: usize = 0;
    while (i < r.n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / SRF;
        var s: f32 = 0;
        for (0..CRICKETS) |k| {
            ph[k] += hz[k] / SRF;
            ph[k] -= @floor(ph[k]);
            const u = t * rate[k] + at[k];
            const c = u - @floor(u); // 0..1 through this cricket's chirp cycle
            if (c > CRICKET_SING) continue;
            const w = c / CRICKET_SING; // 0..1 across the chirp itself
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
// THE FLORID RAVAGER — and **NOTHING HERE IS A DOG.** The silhouette is a hound and the read has to be that
// the head on it is not one: every voice is WET AND VEGETAL over a chest that is only just an animal. The
// wolf's growl was the obvious borrow and it is exactly the wrong one — it would make the thing a dog again.

/// **THE BLOOM OPENING**, and it is the creature's whole tell in sound: a long wet unfurl, low and rising,
/// with the creak of something fibrous being forced apart under it. No voice in it at all — a flower has no
/// throat, and the moment it sounds like it is snarling the head goes back to being a face.
fn mkRavagerBloom(r: *Rack) void {
    // **AND IT IS THE SPOOKY ONE** (owner). What makes it spooky is that a VOICE comes out of a thing that
    // has no throat: a low detuned choir swelling up under the wet unfurl, pitched so it reads as almost —
    // not quite — a person. Every other creature in the game growls or shrieks, which is an animal noise and
    // therefore a safe one. This one sings, badly, out of a flower, and it is the only thing here that does.
    r.air(0.0, 0.72, 0.28, 240, 1900, 0.55, 1.9); // the unfurl: a slow open filter, wet at the bottom
    r.grit(0.05, 0.50, 0.13, 1500, 0.55, 2.4); // …fibres letting go, one at a time
    r.choir(0.06, 0.66, 132, 0.30, 5, 0.72); // …AND THE VOICE. Low, detuned, swelling — it arrives late
    r.choir(0.20, 0.48, 197, 0.13, 3, 0.62); // …with a bare fifth over it, which is what stops it being warm
    r.ring(0.10, 0.44, 214, 0.13, 4.0, 3); // a hollow that gets bigger as it opens
    r.body(0.0, 0.10, 78, 44, 0.30, 3.2); // the stalk taking the strain
    r.wow(0.006, 0.9); // …and it will not sit still in pitch, which is most of the unease
    r.warm(2600);
    r.master(1.5, 3000);
}

/// THE LEAP — the gather and the launch as ONE sound, because they are one movement: a scrape of claws
/// loading, then the whole mass leaving. Dry and short; the wet is the head's, not the body's.
fn mkRavagerLeap(r: *Rack) void {
    r.grit(0.0, 0.13, 0.34, 2600, 0.70, 2.6); // claws tearing turf
    r.body(0.05, 0.20, 150, 62, 0.62, 4.2); // …and the weight going
    r.air(0.06, 0.26, 0.24, 700, 2400, 0.34, 2.2);
    r.master(1.8, 3400);
}

/// **THE BITE, AND IT IS A WET CLOSE, NOT A CLACK.** Petals shutting on meat: a soft heavy slap with a suck
/// behind it. Teeth would be a jaw and there is no jaw on this thing.
fn mkRavagerSnap(r: *Rack) void {
    r.body(0.0, 0.07, 300, 96, 0.85, 6.5); // the ring meeting itself
    r.air(0.0, 0.20, 0.42, 3000, 420, 0.62, 3.0); // …the suck as it closes, bright falling to nothing
    r.grit(0.01, 0.10, 0.24, 1900, 0.45, 3.4);
    r.ring(0.02, 0.16, 168, 0.20, 7.0, 2);
    r.master(2.0, 3200);
}

/// HURT — a shriek out of the STALK rather than the chest, which is what makes it unpleasant: a torn-reed
/// squeal with the wet under it. Rough, and it bends the wrong way (up at the end, not down).
fn mkRavagerHurt(r: *Rack) void {
    r.growl(0.0, 0.26, 380, 720, 0.52, 0.46, 0.09); // …RISING: an animal's cry falls, this one does not
    r.air(0.02, 0.30, 0.26, 1400, 3400, 0.48, 1.6);
    r.grit(0.0, 0.18, 0.22, 2800, 0.50, 2.2);
    r.master(2.1, 3600);
}

/// AND THE DEATH: the shriek collapsing into a long wet exhale as the bloom comes apart. Longest of the five
/// by some way — the body has to be audibly finished, or a pack of them is a wall of yelps with no ending.
fn mkRavagerDie(r: *Rack) void {
    r.growl(0.0, 0.30, 620, 190, 0.54, 0.52, 0.10); // the cry going out
    r.air(0.10, 0.86, 0.34, 2200, 200, 0.50, 1.2); // …and the long collapse
    r.grit(0.14, 0.52, 0.18, 1200, 0.60, 1.8);
    r.body(0.24, 0.26, 96, 38, 0.34, 2.6); // the mass hitting the ground
    r.warm(2400);
    r.master(1.7, 2800);
}

// THE MUSHROOM MAGE, and **NOTHING HERE IS A WIZARD.** No chime, no bell, no rising sparkle — every one of
// those says "spell" in the register a menu says it in, and this creature is a damp thing in a wood that has
// learned to make fire. The family is WET AND SMOULDERING: a hiss with something soft under it.

/// **THE GATHER**, and it is the tell in sound: a slow inhale of air being pulled INTO a point, with the
/// hiss of something wet meeting something hot climbing under it. It RISES the whole way, so the ear knows
/// how far through the gather it is without looking — which is the entire job, because what the player is
/// reading off this creature is a clock.
fn mkMageKindle(r: *Rack) void {
    r.air(0.0, 0.62, 0.30, 300, 2600, 0.50, 2.2); // the draw: a filter opening, slow and wide
    r.grit(0.04, 0.54, 0.16, 2400, 0.40, 2.6); // …damp wood taking light
    r.body(0.10, 0.48, 62, 128, 0.26, 0.7); // …and a low swell that CLIMBS, which is the clock
    r.ring(0.24, 0.34, 268, 0.10, 3.2, 3); // one thin overtone, so it is not pure noise
    r.wow(0.005, 1.4);
    r.warm(2800);
    r.master(1.4, 3200);
}

/// THE THROW — a wet WHUMP and the ball leaving. Short, and it is the only bright thing in the set: the
/// gather is a long dark climb and this is what the climb was for.
fn mkMageThrow(r: *Rack) void {
    r.body(0.0, 0.11, 210, 74, 0.68, 5.0); // the shove
    r.air(0.0, 0.24, 0.36, 2800, 500, 0.44, 2.8); // …and the fire going away from you, bright falling to dull
    r.grit(0.0, 0.09, 0.26, 3200, 0.52, 3.6);
    r.master(1.8, 3400);
}

/// HURT — a wet tear, not a shriek. It has no throat: what it makes is the noise a mushroom makes when you
/// stand on one, one size up and with a voice trapped somewhere behind it.
fn mkMageHurt(r: *Rack) void {
    r.grit(0.0, 0.20, 0.34, 1700, 0.62, 3.0);
    r.body(0.0, 0.16, 240, 92, 0.42, 4.0);
    r.air(0.02, 0.26, 0.22, 900, 2100, 0.46, 2.0);
    r.master(2.0, 3400);
}

/// AND THE DEATH: the tear again, longer, collapsing into a dry PUFF as the cap goes — the spore cloud is
/// what the eye sees and this is it.
fn mkMageDie(r: *Rack) void {
    r.grit(0.0, 0.30, 0.36, 1500, 0.66, 2.4);
    r.body(0.0, 0.22, 190, 58, 0.44, 3.2);
    r.air(0.16, 0.68, 0.30, 1800, 240, 0.38, 1.4); // the long collapse
    r.grit(0.22, 0.46, 0.20, 900, 0.50, 1.6); // …and the puff
    r.warm(2500);
    r.master(1.6, 2800);
}

/// **THE BALL COMING OFF THE GROUND**, and it is the sound the whole move is learned from: it fires once per
/// bounce, so what the player hears is the RHYTHM of the thing coming — and a rhythm is the one cue you can
/// follow without looking at it. Soft-bodied, because a fireball is not a stone: a dull thud with a hiss of
/// steam off the wet earth.
fn mkEmberBounce(r: *Rack) void {
    r.body(0.0, 0.09, 130, 52, 0.56, 5.5);
    r.air(0.0, 0.17, 0.24, 2200, 620, 0.40, 3.0); // the steam off it
    r.grit(0.0, 0.06, 0.18, 1800, 0.44, 4.0);
    r.master(1.6, 2800);
}

/// …and the last one, where it stops being a threat and is just a fire on the ground for a moment.
fn mkEmberBurst(r: *Rack) void {
    r.body(0.0, 0.14, 170, 44, 0.62, 4.2);
    r.air(0.0, 0.40, 0.34, 3000, 300, 0.46, 2.2);
    r.grit(0.01, 0.22, 0.24, 2000, 0.50, 2.6);
    r.warm(2600);
    r.master(1.9, 3000);
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
    // …and the REFUSAL, which is every foe's boards and not the hero's. Sits under a landed hit on purpose:
    // it is the absence of one.
    .{ .id = .foe_guarded, .make = mkFoeGuarded, .gain = battle(0.70), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 5, .poly = 4, .reach = 52 },
    // …and the WALL's own. Louder and it carries further, because a boss turning a blow is a fight-wide
    // event; barely jittered, since a wall struck twice is one object and not two.
    .{ .id = .knight_repel, .make = mkKnightRepel, .gain = battle(0.90), .mix = .combat, .jit = 0.07, .vjit = 0.12, .vars = 4, .poly = 3, .reach = 95 },
    // The BREAK is once a fight at most, and it is the cue to get out.
    .{ .id = .guard_break, .make = mkGuardBreak, .gain = battle(0.92), .mix = .combat, .jit = 0.05, .vjit = 0.06, .vars = 2, .poly = 1 },
    // Barely jittered: a ring that wanders take to take reads as two pieces of metal, not one struck twice.
    .{ .id = .parry, .make = mkParry, .gain = battle(0.82), .mix = .combat, .jit = 0.07, .vjit = 0.09, .vars = 3, .poly = 2 },
    .{ .id = .refused, .make = mkRefused, .gain = 0.34, .jit = 0.06, .vjit = 0.08, .vars = 2 },
    .{ .id = .death, .make = mkDeath, .gain = battle(0.95), .mix = .combat, .jit = 0.0, .vjit = 0.0, .poly = 1 },
    .{ .id = .respawn, .make = mkRespawn, .gain = battle(0.55), .mix = .combat, .jit = 0.0, .vjit = 0.0, .poly = 1 },
    // A HOP IS TRAVEL, NOT A THREAT — down with the footsteps, since it fires every second and a half.
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
    .{ .id = .ravager_bloom, .make = mkRavagerBloom, .gain = battle(0.70), .mix = .combat, .jit = 0.08, .vjit = 0.14, .vars = 4, .poly = 4, .reach = 34 },
    .{ .id = .ravager_leap, .make = mkRavagerLeap, .gain = battle(0.52), .mix = .combat, .jit = 0.14, .vjit = 0.22, .vars = 4, .poly = 4, .reach = 26 },
    .{ .id = .ravager_snap, .make = mkRavagerSnap, .gain = battle(0.82), .mix = .combat, .jit = 0.08, .vjit = 0.14, .vars = 4, .poly = 4, .reach = 30 },
    .{ .id = .ravager_hurt, .make = mkRavagerHurt, .gain = battle(0.50), .mix = .combat, .jit = 0.16, .vjit = 0.26, .vars = 4, .poly = 4, .reach = 26 },
    .{ .id = .ravager_die, .make = mkRavagerDie, .gain = battle(0.58), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 32 },
    // THE MUSHROOM MAGE. The GATHER carries furthest of the four by a clear margin — it is a tell, and a
    // tell you cannot hear from where the fight is happening is not one.
    .{ .id = .mage_kindle, .make = mkMageKindle, .gain = battle(0.62), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 4, .poly = 4, .reach = 38 },
    .{ .id = .mage_throw, .make = mkMageThrow, .gain = battle(0.58), .mix = .combat, .jit = 0.12, .vjit = 0.20, .vars = 4, .poly = 4, .reach = 32 },
    .{ .id = .mage_hurt, .make = mkMageHurt, .gain = battle(0.50), .mix = .combat, .jit = 0.16, .vjit = 0.26, .vars = 4, .poly = 4, .reach = 26 },
    .{ .id = .mage_die, .make = mkMageDie, .gain = battle(0.56), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 30 },
    // …AND THE BALL'S OWN TWO, which belong to the SHOT and not to the caster: they go off wherever it has
    // got to, long after its hands are empty. Heavily jittered and deeply polyphonic — three mages in a ring
    // is a dozen bounces overlapping, and one voice repeated exactly is a machine gun.
    .{ .id = .ember_bounce, .make = mkEmberBounce, .gain = battle(0.48), .mix = .combat, .jit = 0.18, .vjit = 0.30, .vars = 4, .poly = 6, .reach = 30 },
    .{ .id = .ember_burst, .make = mkEmberBurst, .gain = battle(0.60), .mix = .combat, .jit = 0.12, .vjit = 0.22, .vars = 4, .poly = 5, .reach = 32 },
    // THE DELVER. Its whole family is EARTH — grit and a low body, never a ring — and the CHURN is texture:
    // under the floor, and thinned in count by `delver.CHURN_EVERY`, because it repeats through a hold.
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
    // Barely jittered: the climb IS the tell, and a wandering pitch reads as two different things.
    .{ .id = .wand_charge, .make = mkWandCharge, .gain = 0.28, .mix = .combat, .jit = 0.04, .vjit = 0.06, .vars = 3, .poly = 2, .reach = 80 },
    .{ .id = .wand_cast, .make = mkWandCast, .gain = battle(0.60), .mix = .combat, .jit = 0.08, .vjit = 0.12, .vars = 4, .poly = 3, .reach = 72 },
    .{ .id = .bone_hurt, .make = mkBoneHurt, .gain = battle(0.62), .mix = .combat, .jit = 0.12, .vjit = 0.20, .vars = 4, .poly = 3, .reach = 44 },
    .{ .id = .bone_die, .make = mkBoneDie, .gain = battle(0.68), .mix = .combat, .jit = 0.09, .vjit = 0.12, .vars = 3, .reach = 54 },
    // THE ONE WARNING THE LEAP GIVES YOU, so it carries as far as the leap can reach and then some.
    .{ .id = .skel_lunge, .make = mkSkelLunge, .gain = battle(0.86), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 4, .poly = 3, .reach = 62 },
    // An octave down, and low frequencies are what survive a couple of hundred metres of air — hence `reach`.
    .{ .id = .ogre_step, .make = mkOgreStep, .gain = battle(0.44), .mix = .combat, .jit = 0.08, .vjit = 0.20, .vars = 4, .poly = 3, .reach = 115 },
    .{ .id = .ogre_roar, .make = mkOgreRoar, .gain = battle(0.80), .mix = .combat, .jit = 0.06, .vjit = 0.10, .vars = 3, .reach = 135 },
    .{ .id = .ogre_slam, .make = mkOgreSlam, .gain = battle(1.00), .mix = .combat, .jit = 0.06, .vjit = 0.08, .vars = 3, .reach = 135 },
    .{ .id = .ogre_swipe, .make = mkOgreSwipe, .gain = battle(0.72), .mix = .combat, .jit = 0.07, .vjit = 0.12, .vars = 3, .reach = 85 },
    .{ .id = .ogre_heave, .make = mkOgreHeave, .gain = battle(0.70), .mix = .combat, .jit = 0.07, .vjit = 0.11, .vars = 3, .reach = 85 },
    .{ .id = .ogre_hurt, .make = mkOgreHurt, .gain = battle(0.66), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 80 },
    .{ .id = .ogre_die, .make = mkOgreDie, .gain = battle(0.92), .mix = .combat, .jit = 0.0, .vjit = 0.0, .poly = 1, .reach = 135 },
    .{ .id = .kobold_snarl, .make = mkKoboldSnarl, .gain = battle(0.62), .mix = .combat, .jit = 0.22, .vjit = 0.24, .vars = 6, .poly = 3, .reach = 58 },
    .{ .id = .kobold_chop, .make = mkKoboldChop, .gain = battle(0.38), .mix = .combat, .jit = 0.22, .vjit = 0.28, .vars = 6, .poly = 4, .reach = 40 },
    .{ .id = .kobold_heave, .make = mkKoboldHeave, .gain = battle(0.78), .mix = .combat, .jit = 0.18, .vjit = 0.24, .vars = 5, .poly = 2, .reach = 62 },
    .{ .id = .kobold_cast, .make = mkKoboldCast, .gain = 0.30, .mix = .combat, .jit = 0.05, .vjit = 0.08, .vars = 3, .poly = 2, .reach = 78 },
    // The quietest positive cue in the game, and lowered twice on the owner's call.
    .{ .id = .kobold_heal, .make = mkKoboldHeal, .gain = 0.11, .mix = .combat, .jit = 0.06, .vjit = 0.10, .vars = 3, .poly = 3, .reach = 54 },
    .{ .id = .kobold_whirl, .make = mkKoboldWhirl, .gain = battle(0.34), .mix = .combat, .jit = 0.20, .vjit = 0.24, .vars = 5, .poly = 3, .reach = 44 },
    .{ .id = .kobold_sling, .make = mkKoboldSling, .gain = battle(0.68), .mix = .combat, .jit = 0.13, .vjit = 0.18, .vars = 4, .poly = 4, .reach = 52 },
    .{ .id = .kobold_bite, .make = mkKoboldBite, .gain = battle(0.56), .mix = .combat, .jit = 0.20, .vjit = 0.26, .vars = 6, .poly = 3, .reach = 40 },
    .{ .id = .kobold_hurt, .make = mkKoboldHurt, .gain = battle(0.60), .mix = .combat, .jit = 0.24, .vjit = 0.30, .vars = 6, .poly = 4, .reach = 48 },
    .{ .id = .kobold_die, .make = mkKoboldDie, .gain = battle(0.68), .mix = .combat, .jit = 0.18, .vjit = 0.22, .vars = 5, .poly = 3, .reach = 58 },
    // Quiet but far-carrying: you hear the shade before you find it, and never quite where you looked.
    .{ .id = .shade_reach, .make = mkShadeReach, .gain = battle(0.44), .mix = .combat, .jit = 0.16, .vjit = 0.22, .vars = 4, .poly = 3, .reach = 40 },
    .{ .id = .shade_gather, .make = mkShadeGather, .gain = battle(0.66), .mix = .combat, .jit = 0.06, .vjit = 0.10, .vars = 3, .poly = 3, .reach = 70 },
    .{ .id = .shade_wisp, .make = mkShadeWisp, .gain = battle(0.58), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 4, .poly = 3, .reach = 74 },
    .{ .id = .shade_touch, .make = mkShadeTouch, .gain = battle(0.70), .mix = .combat, .jit = 0.09, .vjit = 0.13, .vars = 4, .poly = 3, .reach = 34 },
    .{ .id = .shade_blink, .make = mkShadeBlink, .gain = battle(0.64), .mix = .combat, .jit = 0.11, .vjit = 0.15, .vars = 4, .poly = 4, .reach = 68 },
    .{ .id = .shade_hurt, .make = mkShadeHurt, .gain = battle(0.54), .mix = .combat, .jit = 0.15, .vjit = 0.22, .vars = 5, .poly = 3, .reach = 44 },
    .{ .id = .shade_die, .make = mkShadeDie, .gain = battle(0.66), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 2, .reach = 60 },
    // AMBIENT-QUIET AND VERY CLOSE: it fires hundreds of times in a fight, and anything at combat level
    // repeating that often becomes a noise floor. High `poly` — a swarm has to overlap without cutting itself.
    .{ .id = .leech_wing, .make = mkLeechWing, .gain = battle(0.035), .mix = .combat, .jit = 0.16, .vjit = 0.34, .vars = 6, .poly = 6, .reach = 12 },
    .{ .id = .leech_stab, .make = mkLeechStab, .gain = battle(0.80), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 4, .poly = 3, .reach = 30 },
    // Texture, not an event: retriggered for as long as the hold lasts (`leechfly.DRINK_EVERY`).
    .{ .id = .leech_drink, .make = mkLeechDrink, .gain = battle(0.40), .mix = .combat, .jit = 0.12, .vjit = 0.16, .vars = 4, .poly = 3, .reach = 26 },
    .{ .id = .leech_hurt, .make = mkLeechHurt, .gain = battle(0.56), .mix = .combat, .jit = 0.16, .vjit = 0.24, .vars = 5, .poly = 4, .reach = 40 },
    .{ .id = .leech_die, .make = mkLeechDie, .gain = battle(0.60), .mix = .combat, .jit = 0.11, .vjit = 0.15, .vars = 4, .poly = 3, .reach = 48 },
    // A big slow mass: the wake and the death are the two longest tails in the bank after the ogre.
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
    // THE HATCH IS A CUE, and one you may be across the plaza from when it fires.
    .{ .id = .sac_hatch, .make = mkSacHatch, .gain = battle(0.66), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 72 },
    .{ .id = .sac_burst, .make = mkSacBurst, .gain = battle(0.74), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 68 },
    .{ .id = .acid_splash, .make = mkAcidSplash, .gain = battle(0.58), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 4, .poly = 4, .reach = 50 },
    .{ .id = .acid_burn, .make = mkAcidBurn, .gain = 0.26, .mix = .combat, .jit = 0.20, .vjit = 0.26, .vars = 5, .poly = 3, .reach = 24 },
    .{ .id = .flask_drink, .make = mkFlaskDrink, .gain = 0.52, .jit = 0.06, .vjit = 0.10, .vars = 2, .poly = 2 },
    .{ .id = .flask_cycle, .make = mkFlaskCycle, .gain = 0.30, .jit = 0.07, .vjit = 0.08, .vars = 2, .poly = 3 },
    // Quieter than the flask: eating is not an emergency, and the sound of it should not be one.
    .{ .id = .eat, .make = mkEat, .gain = 0.40, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 2 },
    .{ .id = .chest_open, .make = mkChestOpen, .gain = 0.72, .jit = 0.04, .vjit = 0.06, .vars = 2, .poly = 2, .reach = 70 },
    .{ .id = .item_get, .make = mkItemGet, .gain = 0.44, .jit = 0.05, .vjit = 0.08, .vars = 3, .poly = 4 },
    // NOT in the combat band: it plays under the YOU DIED card, where nothing else is sounding.
    .{ .id = .souls_spill, .make = mkSoulsSpill, .gain = 0.68, .jit = 0.03, .vjit = 0.05, .vars = 2, .poly = 2 },
    // …and the hum is TEXTURE: found by walking toward it, not heard across the map.
    .{ .id = .souls_hum, .make = mkSoulsHum, .gain = 0.26, .jit = 0.05, .vjit = 0.07, .vars = 3, .poly = 2, .reach = 26 },
    .{ .id = .souls_take, .make = mkSoulsTake, .gain = 0.62, .jit = 0.04, .vjit = 0.07, .vars = 3, .poly = 2, .reach = 40 },
    .{ .id = .ring_snap, .make = mkRingSnap, .gain = 0.66, .jit = 0.05, .vjit = 0.08, .vars = 2, .poly = 2 },
    .{ .id = .kill, .make = mkKill, .gain = battle(0.55), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 4 },
    .{ .id = .menu_move, .make = mkMenuMove, .gain = 0.30, .jit = 0.06, .vjit = 0.08, .vars = 2, .poly = 3 },
    .{ .id = .menu_pick, .make = mkMenuPick, .gain = 0.38, .jit = 0.03, .vjit = 0.05 },
    .{ .id = .menu_back, .make = mkMenuBack, .gain = 0.32, .jit = 0.03, .vjit = 0.05 },
    // MUCH quieter (owner's call).
    .{ .id = .wind, .make = mkWind, .gain = 0.030, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
    // DAYTIME figures (owner: birdcall louder by day) — `CALLS` takes them back down under a dark sky, so
    // what is set here is the noon level and not the night's.
    .{ .id = .birds, .make = mkBirds, .gain = 0.31, .mix = .ambience, .jit = 0.14, .vjit = 0.30, .vars = 4, .poly = 2, .reach = 210 },
    .{ .id = .birdsong, .make = mkBirdsong, .gain = 0.26, .mix = .ambience, .jit = 0.13, .vjit = 0.30, .vars = 4, .poly = 2, .reach = 200 },
    // THE OWL IS RARE AND IT IS ALLOWED TO BE HEARD.
    .{ .id = .owl, .make = mkOwl, .gain = 0.24, .mix = .ambience, .jit = 0.08, .vjit = 0.14, .vars = 3, .poly = 2, .reach = 170 },
    // Its NIGHT figure (owner: crickets louder at night); `BEDS` thins it through the middle of the day.
    .{ .id = .crickets, .make = mkCrickets, .gain = 0.015, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
    // Quieter up close than a kobold: a thing on YOUR side must never fight the creature it is biting for
    // the frame. The HOWL is the exception — thirty focus spent, and the player has to know it landed.
    .{ .id = .wolf_howl, .make = mkWolfHowl, .gain = battle(0.44), .mix = .combat, .jit = 0.05, .vjit = 0.09, .vars = 3, .poly = 1, .reach = 110 },
    .{ .id = .wolf_growl, .make = mkWolfGrowl, .gain = battle(0.30), .mix = .combat, .jit = 0.18, .vjit = 0.24, .vars = 5, .poly = 2, .reach = 46 },
    .{ .id = .wolf_bite, .make = mkWolfBite, .gain = battle(0.52), .mix = .combat, .jit = 0.16, .vjit = 0.22, .vars = 5, .poly = 3, .reach = 52 },
    .{ .id = .wolf_hurt, .make = mkWolfHurt, .gain = battle(0.54), .mix = .combat, .jit = 0.20, .vjit = 0.26, .vars = 5, .poly = 3, .reach = 56 },
    .{ .id = .wolf_die, .make = mkWolfDie, .gain = battle(0.70), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 1, .reach = 90 },
};

fn seconds(id: Id) f32 {
    return switch (id) {
        .wind => 8.0,
        .crickets => 7.3,
        .death => 3.2,
        .owl => 1.6,
        .ogre_die => 2.2,
        .respawn => 1.4,
        .bone_die, .toad_die, .ogre_roar => 1.1,
        // THE HOWL AND THE SPIRIT'S DEATH both outlive their own animal — the ring tail is the point of them,
        // and cut to a combat length it is the tail that goes.
        .wolf_howl => 1.7,
        .wolf_die => 2.0,
        .kobold_cast => 1.35,
        .kobold_heal => 1.95, // the chord has to finish opening, and its room has to finish emptying
        .kobold_die => 1.15,
        .kobold_heave => 0.85, // three ragged breaths, quickening
        .kobold_whirl => 0.75,
        .ogre_slam, .bow_draw, .flask_drink => 1.05,
        .chest_open => 0.9, // the lock, the whole hinge turn, and the lid arriving over
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
        .shade_blink => 0.55, // out and in are one sound heard twice; each end wants the whole tail
        .shade_die => 1.25, // it unravels rather than falling: no impact to cut it short
        .sac_lay => 0.62, // the push, then it arriving on the ground
        .sac_hatch, .brood_screech => 0.55, // the membrane going, and the cry straight over it
        .sac_burst => 0.45,
        .acid_splash => 0.42,
        // Recipes authoring past the 0.5 s default — without a row here `Rack.at` clamps and the tail
        // layers render zero samples.
        .wood_wake => 0.8,
        .wood_die => 1.2, // the tear, THEN the ground taking it at 0.80
        .eat => 0.65,
        .shroom_die => 0.75,
        // Cut past its own retrigger (`delver.CHURN_EVERY`) so consecutive takes OVERLAP.
        .delver_churn => 0.9,
        .delver_surge => 1.25, // the whole of the rise, or the tell stops before the blow does
        .delver_die => 0.85,
        .leech_die => 0.65, // the run-down, then the body arriving at 0.44
        .souls_spill => 0.9,
        // The retrigger fires every HUM_EVERY (1.15 s); the take must outlast it or the hum chatters.
        .souls_hum => 1.30,
        else => 0.5,
    };
}


const MAX_VARS = 6;
/// Voices of one take that may sound AT ONCE. Six, for the leechfly swarm; every other row wants 2..4.
const MAX_POLY = 6;

const MASTER_VOL: f32 = 0.85;

const Slot = struct {
    snd: [MAX_VARS][MAX_POLY]rl.Sound = undefined,
    owned: [MAX_VARS]rl.Sound = undefined, // alias 0 owns the data; the rest borrow it
    next: u8 = 0,
    /// The only thing allowed to bound a walk of `snd`. `Row.vars` is what a row WILL have once `pump`
    /// finishes; walking that instead hands raylib an undefined `rl.Sound` to play, stop or unload.
    varsReady: u8 = 0,
};

// ZERO-INITIALISED, not `undefined`: `varsReady` is read before anything is baked.
var slots = [_]Slot{.{}} ** NV;
var ready = false;
// The PLAYBACK rng — per-trigger pitch wobble only.
var rng = mathx.Rng.init(0x50FA5);
var muted = false;

// The listener, set once a frame by game.zig.
var lisPos: rl.Vector3 = mathx.zero3;
var lisRight: rl.Vector3 = mathx.v3(1, 0, 0);

const FALLOFF: f32 = 46.0;

const PAN_WIDTH: f32 = 0.42;
/// …and inside this radius the pan CLOSES TO CENTRE.
const PAN_NEAR: f32 = 1.4;
/// How much a source DIRECTLY BEHIND the listener is ducked, as a fraction.
const REAR_DUCK: f32 = 0.10;
/// Distance PITCH droop, at full reach.
const PITCH_DROOP: f32 = 0.05;
/// The bed's two channels, as pan values.
const BED_PAN: f32 = 0.93;

fn panFor(side: f32, width: f32) f32 {
    return mathx.clampF(0.5 - width * side, 0.04, 0.96);
}

/// The ONE copy of the recipe→sound path, shared by `init`, `pump` and `rebakeMix`, so a voice cannot come
/// back from a filter change built differently. Takes append in order, so `varsReady` is also the next index.
fn bakeTake(id: Id, idx: usize) void {
    const row = BANK[idx];
    const v = slots[idx].varsReady;
    if (v >= row.vars) return;
    var r = Rack.init(0x9E3779B9 *% (idx + 1) +% v, seconds(id));
    row.make(&r);
    // The fight's own tone, BEFORE the player's rack: his dials sit on top of the mix, never under it.
    if (row.mix == .combat) r.warm(COMBAT_TREBLE);
    applyFx(&r, row.mix);
    slots[idx].snd[v][0] = bake(&r);
    slots[idx].owned[v] = slots[idx].snd[v][0];
    var p: u8 = 1;
    while (p < row.poly) : (p += 1) slots[idx].snd[v][p] = rl.loadSoundAlias(slots[idx].owned[v]);
    slots[idx].varsReady = v + 1; // LAST: nothing may see a half-built take
    slots[idx].next = 0;
}

/// …and every take of one row, for the paths that want a row whole.
fn bakeRow(id: Id, idx: usize) void {
    while (slots[idx].varsReady < BANK[idx].vars) bakeTake(id, idx);
}

/// Walks the rest of the bank in behind the menu, a few ms a frame; returns whether work remains. Whole,
/// it was 4.4 s of synthesis on the main thread in front of an already-blank window.
///
/// A TAKE IS INDIVISIBLE: the budget bounds how much we START, never how much we finish, so one 8 s bed
/// take is a ~300 ms hole in whatever frame picks it up — hence `longOk`, which defers the long rows to a
/// pause. `LONG_TAKE` is in seconds of AUDIO, the one cheap proxy for the cost.
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
            deferred = true; // there IS work, just none this pass may afford
            continue;
        }
        bakeTake(BANK[idx].id, idx);
        if (t.read() >= budgetNs) return true;
        left = NV + 1; // it had work and time: give the walk a fresh lap
    }
    // A full lap that started nothing. Only one of the two reasons is finished: a DEFERRED row is work
    // waiting on the next pause, where nothing deferred means the bank is whole.
    pumpDone = !deferred;
    return deferred;
}

/// Where `pump` resumes. A cursor rather than a rescan from 0, so a nearly-full bank costs one walk.
var pumpAt: usize = 0;
/// …and whether there is anything left to resume AT — without it a finished bank still costs a timer read
/// and a walk of all `NV` rows every frame. Cleared by `freeRow`, the only thing that un-bakes a take.
var pumpDone = false;

/// From take 0, not 1: index 0 is the OWNER and the one the looping beds play on. Bounded by `varsReady`,
/// not `Row.vars` — a take that has not been baked yet is an undefined `rl.Sound`.
fn stopRow(idx: usize) void {
    const row = BANK[idx];
    var v: u8 = 0;
    while (v < slots[idx].varsReady) : (v += 1) {
        var p: u8 = 0;
        while (p < row.poly) : (p += 1) rl.stopSound(slots[idx].snd[v][p]);
    }
}

/// Aliases before the owner whose samples they borrow.
fn freeRow(idx: usize) void {
    const row = BANK[idx];
    var v: u8 = 0;
    while (v < slots[idx].varsReady) : (v += 1) {
        var p: u8 = 1;
        while (p < row.poly) : (p += 1) rl.unloadSoundAlias(slots[idx].snd[v][p]);
        rl.unloadSound(slots[idx].owned[v]);
    }
    slots[idx].varsReady = 0; // freed IS not-ready, and `pump` rebuilds it from take 0
    pumpDone = false; // …so it has to start asking again
}

/// Silence always before free (see `deinit`).
fn dropRow(idx: usize) void {
    stopRow(idx);
    freeRow(idx);
}

/// The looping beds heal themselves: `ambience` re-fires whatever is not playing, so a bed stopped here
/// comes back next frame as the new take.
fn rebakeMix(m: Submix) void {
    if (!ready) return;
    inline for (@typeInfo(Id).@"enum".fields, 0..) |f, idx| {
        if (BANK[idx].mix == m) {
            dropRow(idx);
            // TAKE 0 ONLY, and `pump` walks the variants back in — the same two-stage build `init` uses.
            bakeTake(@enumFromInt(f.value), idx);
        }
    }
    // The campfire is an ambience voice too, and the only one that is a STREAM rather than a baked Sound.
    if (m == .ambience) redressFire();
}

/// Unload BEFORE re-dressing: `dressedFire` overwrites `fireWav` in place and the live stream reads it.
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

/// ENOUGH OF THE BANK TO PLAY, and no more: variant 0 of every row, ~112 takes of the 407 the bank wants.
pub fn init() void {
    loadSettings(); // before the device: the dials are data, and they are what the first bed is mixed at
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
const FIRE_DRIVE: f32 = 1.55; // tape saturation, which is also what stops the shelf clipping
const FIRE_BITS: f32 = 6.5; // crushed HARDER than the synth bank's 7.5: it is the one voice with real
const FIRE_HOLD: u32 = 2; // material in it, so it is the one where the grain actually reads
const FIRE_CUT: f32 = 3400.0; // the tape's top end — a fire is bottom and crackle, no air
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
    // Only the shape this asset actually is — 16-bit PCM.
    if (w.sampleSize != 16) return CAMPFIRE_WAV;
    const frames: usize = @intCast(w.frameCount);
    const chans: usize = @intCast(w.channels);
    const n = frames * chans;
    const bytes = 44 + n * 2;
    // …and short enough to go through `work`. A longer take swapped in later degrades to the RAW asset
    // rather than running off the end of the buffer.
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
        x += FIRE_BASS * low.step(x, FIRE_BASS_HZ); // the shelf: the body a fire has and the take did not
        const d = x * FIRE_DRIVE;
        x = d / (1.0 + @abs(d));
        if (k == 0) held = x;
        k = (k + 1) % @max(FIRE_HOLD, 1);
        const dith = (r.signed() + r.signed()) * 0.5 / levels * DITHER_LSB;
        x = @round((held + dith) * levels) / levels;
        x = lp.step(x, FIRE_CUT);
        x += hq.step(hp.step(r.signed(), 5200), 2600) * FIRE_HISS;
        // INTO `work`, not straight out to bytes: the player's rack runs over it below.
        work[i] = mathx.clampF(x * FIRE_OUT, -1, 1);
    }

    // …and the ambience rack over the top. A COPY: the embedded asset is never touched.
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
    put16(&fireWav, 20, 1); // PCM
    put16(&fireWav, 22, @intCast(chans));
    put32(&fireWav, 24, rate);
    put32(&fireWav, 28, rate * align16);
    put16(&fireWav, 32, align16);
    put16(&fireWav, 34, 16);
    @memcpy(fireWav[36..40], "data");
    put32(&fireWav, 40, @intCast(n * 2));
    return fireWav[0..bytes];
}

/// A STREAM, not a `Sound`, because it is twelve seconds long and has to loop
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

/// The bed's level, 0..1, set per frame — it pays the AMBIENCE dial like every other background voice.
pub fn restFireLevel(v: f32) void {
    const m = restFire orelse return;
    rl.setMusicVolume(m, mathx.clampF(v, 0, 1) * userVol[@intFromEnum(Submix.ambience)]);
}

pub fn tickStreams() void {
    const m = restFire orelse return;
    if (rl.isMusicStreamPlaying(m)) rl.updateMusicStream(m);
}

/// The CLAMP is what makes this a function rather than a multiply: a sample past ±1.024 is not a clipped
/// take but an out-of-range `@intFromFloat`. Both float-out sites share it so they cannot disagree.
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

/// SILENCE EVERYTHING FIRST, THEN FREE IT. Freeing a buffer the mixer is still reading presents as the
/// WINDOW CLOSING WHILE THE PROCESS STAYS UP, and it is not a rare race — several voices are mid-playback
/// on any quit.
pub fn deinit() void {
    if (!ready) return;
    if (restFire) |m| rl.stopMusicStream(m);
    // TWO WHOLE-BANK PASSES, not one per row: everything goes quiet before anything is freed.
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
    const r = BANK[@intFromEnum(id)];
    return .{ .gain = r.gain, .mix = r.mix, .jit = r.jit, .vjit = r.vjit, .vars = r.vars, .poly = r.poly, .reach = r.reach };
}

// One number per `Submix`, multiplied in alongside the author-side trim.
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

/// A ROW PLUS A LEVEL BECOMES A RAYLIB VOLUME HERE AND NOWHERE ELSE.
fn levelFor(row: Row, vol: f32, vj: f32) f32 {
    return mathx.clampF(row.gain * submixTrim(row.mix) * userVol[@intFromEnum(row.mix)] * vol * vj, 0, 1);
}

/// HOW MUCH DAYLIGHT THERE IS, 0 under a dark sky and 1 at noon — stamped by `game.applyHour`, exactly as the
/// scene's own hour is. Nothing in this file knows what an hour is; it is handed the one number it can use.
var daylight: f32 = 1.0;

pub fn setDaylight(k: f32) void {
    daylight = mathx.clampF(k, 0, 1);
}

/// WHAT THE HOUR IS WORTH TO AN AMBIENT VOICE. LERPED on `daylight` rather than switched at sunset, so a
/// bird's last call and a cricket's first are both simply quiet rather than cut off.
const Hour = struct { atNoon: f32 = 1.0, atNight: f32 = 1.0 };

fn hourGain(h: Hour) f32 {
    return mathx.lerpF(h.atNight, h.atNoon, daylight);
}

pub fn setVolume(m: Submix, v: f32) void {
    userVol[@intFromEnum(m)] = mathx.clampF(v, 0, 1);
    // …AND THE BEDS, WHICH ARE ALREADY PLAYING.
    if (ready and m == .ambience) {
        for (BEDS) |b| {
            const s = &slots[@intFromEnum(b.id)];
            const lvl = bedLevel(BANK[@intFromEnum(b.id)], b.hour);
            if (s.varsReady > 0) rl.setSoundVolume(s.snd[0][0], lvl);
            if (s.varsReady > 1) rl.setSoundVolume(s.snd[1][0], lvl);
        }
    }
}

fn bedLevel(row: Row, h: Hour) f32 {
    return levelFor(row, hourGain(h), 1.0);
}

pub const SETTINGS_PATH = "settings.cfg";

/// `fx.<family> a b c …`, one value per AF_* in table order. A file written before the rack existed carries
/// no `fx.` line and loads every family at `AFX_DEFAULTS`.
const FX_KEY = "fx.";

/// SIZED OFF THE TABLES, not a round number that looked big enough (the ring-buffer rule): `saveSettings`
/// writes one volume line and one `fx.` line per submix, every value at `{d:.3}`.
const SETTINGS_CAP = NMIX * (32 + AFX_COUNT * 8) + 64;

pub fn loadSettings() void {
    var buf: [SETTINGS_CAP]u8 = undefined;
    const f = std.fs.cwd().openFile(SETTINGS_PATH, .{}) catch return;
    defer f.close();
    const n = f.readAll(&buf) catch return;
    // IT FILLED THE BUFFER, so the tail was cut MID-LINE. A half-read `fx.` line parses as a short one and
    // loads its remaining dials at ZERO, so the whole file is refused rather than applied wrong.
    if (n == buf.len) return;
    var lines = std.mem.tokenizeAny(u8, buf[0..n], "\r\n");
    while (lines.next()) |line| {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        const key = it.next() orelse continue;
        if (std.mem.startsWith(u8, key, FX_KEY)) {
            const fam = key[FX_KEY.len..];
            inline for (@typeInfo(Submix).@"enum".fields) |fld| {
                if (std.mem.eql(u8, fam, fld.name)) {
                    // A short line leaves the tail at ZERO, not at its default: the file is the whole truth.
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
        const val = it.next() orelse continue;
        const v = std.fmt.parseFloat(f32, val) catch continue;
        inline for (@typeInfo(Submix).@"enum".fields) |fld| {
            if (std.mem.eql(u8, key, fld.name)) setVolume(@enumFromInt(fld.value), v);
        }
    }
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
    worldAt(id, at, 1.0);
}

/// …and the same thing with a level on top, for a caller that has a reason to duck it (`ambience`'s hour).
pub fn worldAt(id: Id, at: rl.Vector3, gain: f32) void {
    if (!ready) return;
    const row = BANK[@intFromEnum(id)];
    const d2 = mathx.dist2XZ(at, lisPos);
    if (d2 > row.reach * row.reach) return;
    const d = @sqrt(d2);
    const k = 1.0 - d / row.reach;
    const near = d / row.reach; // 0 underfoot → 1 at the edge of earshot
    const to = mathx.dirXZ(lisPos, at);
    const side = to.x * lisRight.x + to.z * lisRight.z;
    const fwd = mathx.perpXZ(lisRight);
    const front = to.x * fwd.x + to.z * fwd.z; // +1 dead ahead → −1 dead behind
    const rear = 1.0 - REAR_DUCK * 0.5 * (1.0 - front);
    // …and the pan closes to centre in the near field, so a foe standing on you doesn't strobe.
    const width = PAN_WIDTH * mathx.smoothstep(0, PAN_NEAR, d);
    emit(id, k * k * rear * gain, panFor(side, width), 1.0 - PITCH_DROOP * near);
}

fn emit(id: Id, vol: f32, pan: f32, pitchScale: f32) void {
    if (!ready or muted or vol <= 0.01) return;
    const idx = @intFromEnum(id);
    const row = BANK[idx];
    const s = &slots[idx];
    // Round-robin over the takes THAT EXIST. Before `pump` has caught up a row has one, and `Row.vars` here
    // would pick a take that has not been synthesized yet.
    if (s.varsReady == 0) return;
    const pick = s.next;
    s.next = (s.next + 1) % (s.varsReady * row.poly);
    trigger(s.snd[pick % s.varsReady][pick / s.varsReady % row.poly], row, vol, pan, pitchScale);
}

fn trigger(snd: rl.Sound, row: Row, vol: f32, pan: f32, pitchScale: f32) void {
    const vj = 1.0 - @abs(rng.signed()) * row.vjit;
    rl.setSoundVolume(snd, levelFor(row, vol, vj));
    rl.setSoundPitch(snd, (1.0 + rng.signed() * row.jit) * pitchScale);
    rl.setSoundPan(snd, pan);
    rl.playSound(snd);
}

fn bed(id: Id, vol: f32) void {
    if (!ready or muted) return;
    const idx = @intFromEnum(id);
    const row = BANK[idx];
    const s = &slots[idx];
    if (s.varsReady == 0) return;
    // THE WIDTH IS THE SECOND TAKE, and at launch only take 0 exists. Hard-panned alone that is a bed in
    // one ear; CENTRED it is simply narrow, and the width arrives with the next loop.
    if (s.varsReady == 1) {
        trigger(s.snd[0][0], row, vol, 0.5, 1.0);
        return;
    }
    trigger(s.snd[0][0], row, vol, BED_PAN, 1.0);
    trigger(s.snd[1][0], row, vol, 1.0 - BED_PAN, 1.0);
}

const Bed = struct { id: Id, hour: Hour = .{} };

const BEDS = [_]Bed{
    // The wind blows the same all day; the CHIRR is the night's own, and it thins to a background at noon
    // rather than stopping — there are crickets in a hot field too.
    .{ .id = .wind },
    .{ .id = .crickets, .hour = .{ .atNoon = 0.34, .atNight = 1.0 } },
};

/// A TABLE, because there are three of these now and they differ in nothing but those numbers.
const Call = struct {
    id: Id,
    gapLo: f32,
    gapHi: f32,
    distLo: f32,
    distHi: f32,
    first: f32,
    hour: Hour = .{},
};

// WHERE A CALL COMES FROM IS WHAT SETS HOW LOUD IT IS: `world` fades over `reach` as `k²`, so the distance
// band IS the volume band. The hour is the other half — the bird rows are left far under at night but never
// silenced, since a bird that stops dead at sunset is a switch. The OWL already reads as a night voice.
const CALLS = [_]Call{
    .{ .id = .birds, .gapLo = 6, .gapHi = 17, .distLo = 12, .distHi = 150, .first = 4, .hour = .{ .atNoon = 1.0, .atNight = 0.22 } },
    .{ .id = .birdsong, .gapLo = 7, .gapHi = 20, .distLo = 14, .distHi = 155, .first = 9, .hour = .{ .atNoon = 1.0, .atNight = 0.22 } },
    .{ .id = .owl, .gapLo = 26, .gapHi = 70, .distLo = 40, .distHi = 150, .first = 22 },
};

/// Seconds left on each row's clock, seeded from its own `first`.
var callWait: [CALLS.len]f32 = init: {
    var w: [CALLS.len]f32 = undefined;
    for (CALLS, 0..) |c, i| w[i] = c.first;
    break :init w;
};

/// The beds and the calls over them, ticked once a frame from the live loop.
pub fn ambience(dt: f32) void {
    if (!ready or muted) return;
    for (BEDS) |b| {
        const s = &slots[@intFromEnum(b.id)];
        if (s.varsReady == 0) continue; // not baked yet: `pump` is still walking the bank in
        // The hour is read at the RETRIGGER — seconds against a twenty-minute day, so nothing has to slide
        // a volume under a playing sound.
        if (!rl.isSoundPlaying(s.snd[0][0])) bed(b.id, hourGain(b.hour));
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
    // …and EVERY ROW SITS ON ITS OWN VOICE. The length alone never caught a shifted table (see `Row.id`).
    for (BANK, 0..) |row, i| {
        if (@intFromEnum(row.id) != i) @compileError(std.fmt.comptimePrint(
            "audio: BANK[{d}] is .{s}, which belongs at {d} — the table has shifted against Id",
            .{ i, @tagName(row.id), @intFromEnum(row.id) },
        ));
    }
    // …and a row's `vars`/`poly` INDEX a fixed [MAX_VARS][MAX_POLY] array.
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
            try std.testing.expect(std.math.isFinite(s)); // a filter that blew up says NaN here
            peak = mathx.maxF(peak, @abs(s));
            energy += @abs(s);
        }
        try std.testing.expect(peak > 0.2); // it made a sound…
        try std.testing.expect(peak <= 1.0);
        try std.testing.expect(energy / @as(f32, @floatFromInt(r.n)) > 0.002); // not a lone click
    }
}

test "NO VOICE OUTRUNS ITS OWN TAKE — every authored layer gets samples to render into" {
    // `Rack.at` clamps a layer's start AND its duration to the take, so a recipe authoring past its
    // `seconds()` row loses those layers silently. `Rack.dropped` counts them so it fails HERE instead.
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

/// Total rectified energy of what is in `work`, which is enough to say "this render moved".
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
    // Not "close to": `applyFx` must not have entered the chain at all, or All Off is not really off —
    // and `norm` alone would move this.
    try std.testing.expectEqual(clean, workEnergy(r.n));
}

test "THE HOUSE SOUND IS WORN TAPE, on all three families, and it is the preset's own numbers" {
    // Derived, not copied: the launch state and the "Worn Tape" row are one set of numbers.
    var want = [_]f32{0} ** AFX_COUNT;
    for (FX_TAPE) |p| want[p.idx] = p.val;
    try std.testing.expectEqualSlices(f32, &want, &AFX_DEFAULTS);
    try std.testing.expect(AFX_DEFAULTS[AF_WOBBLE] > AFX_EPS); // …and it really is ON at launch
    // ALL THREE, so nothing launches clean while its neighbours are tape (owner's call).
    inline for (@typeInfo(Submix).@"enum".fields) |fld| {
        try std.testing.expectEqualSlices(f32, &AFX_DEFAULTS, fxValues(@enumFromInt(fld.value)));
    }
}

// THE CAMPFIRE CANNOT BE UNIT-TESTED: `dressedFire` has to `rl.loadWaveFromMemory` first, and doing that
// in a test process with no raylib device hangs it. Its arithmetic is `applyFx`, pinned above.

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
    // THE PROBE IS PER-SAMPLE, not total energy: the chain ends on `norm`, so a pure pitch warp
    // (`wow`) comes back at the same peak AND very nearly the same rectified sum — it moves every
    // sample without moving the total, and an energy test called it decoration.
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
            try std.testing.expect(std.math.isFinite(s)); // a filter that blew up says NaN here
            peak = mathx.maxF(peak, @abs(s));
            diff += @abs(s - c);
        }
        try std.testing.expect(peak > 0.2); // …still a sound, not a filter that ate the voice
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
            try std.testing.expect(row.idx < AFX_COUNT); // an out-of-range idx would silently do nothing
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
    // Setting a dial to the value it already holds is not a change and must not owe a bake.
    fxSettle = 0;
    setFx(.ambience, AF_HISS, 0.5);
    try std.testing.expect(!fxPending());
    // …and the settle has to outlast a frame, or a held slider re-renders at frame rate.
    setFx(.ambience, AF_HISS, 0.6);
    try std.testing.expect(FX_SETTLE > 4.0 / 60.0);
    // `tickFx` is a no-op without an audio device (`ready`), so the flag survives to be checked here.
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
    try std.testing.expect(near * near > far * far * 50.0); // a real curve, not a plateau
}

test "PAN IS THE LEFT CHANNEL'S GAIN — a source on your right must pan DOWN, not up" {
    const right = panFor(1.0, PAN_WIDTH); // source to SCREEN-RIGHT…
    const left = panFor(-1.0, PAN_WIDTH);
    try std.testing.expect(right < 0.5);
    try std.testing.expect(left > 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), panFor(0.0, PAN_WIDTH), 1e-6); // dead ahead is centre
    // …and never so far that a channel disappears (which reads as a broken speaker, not as width).
    for ([_]f32{ -4, -1, 0, 1, 4 }) |s| {
        const p = panFor(s, PAN_WIDTH);
        try std.testing.expect(p >= 0.04 and p <= 0.96);
    }
    // The BED is the deliberate exception: it wants to be as wide as it can get away with.
    try std.testing.expect(BED_PAN > 0.5 + PAN_WIDTH);
    try std.testing.expect(BED_PAN < 1.0);
}

test "the near field closes the pan, so a foe standing on you does not strobe" {
    // A bearing at arm's length is arithmetically fine and perceptually meaningless: a toad chewing your
    // leg crosses side to side in a frame, and panning that honestly flicks it between the speakers.
    const onTop = PAN_WIDTH * mathx.smoothstep(0, PAN_NEAR, 0.05);
    const clear = PAN_WIDTH * mathx.smoothstep(0, PAN_NEAR, 4.0);
    try std.testing.expect(onTop < 0.02); // effectively centred
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
    // The BIRDS carry furthest of anything in the world, and the ordering ends there.
    try std.testing.expect(reach(.bow_loose) > reach(.bow_draw));
    try std.testing.expect(reach(.toad_chomp) > 12.0 and reach(.toad_chomp) < 40.0);
    // …and every voice has to be able to be heard at all.
    for (BANK) |row| try std.testing.expect(row.reach > 1.0);
}

test "every sparse call is rolled INSIDE its own reach, and none of them is rolled at your ear" {
    for (CALLS) |c| {
        const row = BANK[@intFromEnum(c.id)];
        try std.testing.expect(c.distHi < row.reach);
        try std.testing.expect(c.distLo > 10.0 and c.distLo < c.distHi);
        try std.testing.expect(c.gapLo > 0 and c.gapHi > c.gapLo * 1.5);
        try std.testing.expect(c.first > 1.0); // never behind the pause card at launch
    }
    try std.testing.expect(CALLS[2].gapLo > CALLS[0].gapLo * 2.0); // owl vs birds
    try std.testing.expect(CALLS.len == 3);
}

test "THE BACKGROUND IS BACKGROUND — the ambience trim, and only the ambience" {
    for (BEDS) |b| try std.testing.expectEqual(Submix.ambience, BANK[@intFromEnum(b.id)].mix);
    for (CALLS) |c| try std.testing.expectEqual(Submix.ambience, BANK[@intFromEnum(c.id)].mix);
    // WHAT IS PINNED IS THE SIGNAL, NOT THE MIX POSITION.
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
    try std.testing.expectEqual(BEDS.len + CALLS.len, trimmed);
    for ([_]Id{ .toad_chomp, .toad_die, .ogre_slam, .ogre_roar, .bone_die, .hit_heavy, .hurt }) |id| {
        try std.testing.expect(BANK[@intFromEnum(id)].mix != .ambience);
        try std.testing.expectEqual(TRIM_COMBAT, submixTrim(BANK[@intFromEnum(id)].mix));
    }

    var loudBed: f32 = 0;
    for (BEDS) |b| loudBed = mathx.maxF(loudBed, BANK[@intFromEnum(b.id)].gain);
    for (CALLS) |c| try std.testing.expect(BANK[@intFromEnum(c.id)].gain > loudBed);
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
    // A RENDERED voice, not its constants: "ringing" and "pinging" are the same layers at different settings.
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
    // …and a loose lid on shrillness, loose on purpose: zero crossings are dominated by the noisy ATTACK,
    // so this catches a ring parked at 8 kHz and nothing subtler.
    try std.testing.expect(parryBright < blockBright * 1.35);
}

test "THE OPTIONS DIALS — three families, and the fight is one of them" {
    // The player's slider is `Submix`, so a voice's family is now a thing he can hear the effect of.
    for ([_]Id{ .swing_light, .hit_heavy, .hurt, .guard_block, .toad_chomp, .bow_loose, .arrow_dirt, .bone_die, .ogre_slam, .kobold_snarl, .kobold_heal, .kill, .death }) |id| {
        try std.testing.expectEqual(Submix.combat, BANK[@intFromEnum(id)].mix);
    }
    for ([_]Id{ .step_soft, .roll, .refused, .flask_drink, .eat, .chest_open, .item_get, .menu_move }) |id| {
        try std.testing.expectEqual(Submix.sfx, BANK[@intFromEnum(id)].mix);
    }

    // A DIAL SCALES ITS OWN FAMILY AND NOTHING ELSE.
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

test "THE FIGHT IS ONE BAND — no battle voice towers over the rest of them" {
    // WALKED OFF THE BANK, not off a hand-kept list of fifty ids: `.combat` at or under `BATTLE_FLOOR` is
    // the deliberately quiet half, everything else is the band. A new combat voice is inside the guard the
    // moment it has a row.
    var lo: f32 = 1e9;
    var hi: f32 = 0;
    var n: usize = 0;
    for (BANK) |row| {
        if (row.mix != .combat or row.gain <= BATTLE_FLOOR + 1e-6) continue;
        lo = mathx.minF(lo, row.gain);
        hi = mathx.maxF(hi, row.gain);
        n += 1;
    }
    try std.testing.expect(n > 40); // …and it really did walk the whole family, not two rows of it
    // Under 6 dB end to end.
    try std.testing.expect(hi / lo < 2.0);
    // …and the floor did NOT move up to meet it.
    try std.testing.expect(lo >= BATTLE_FLOOR - 1e-4 and lo < BATTLE_FLOOR * 1.15);
    try std.testing.expect(hi < 0.62);

    const g = struct {
        fn of(id: Id) f32 {
            return BANK[@intFromEnum(id)].gain;
        }
    }.of;
    try std.testing.expect(g(.ogre_slam) > g(.kobold_chop)); // the giant still lands hardest…
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
    // A CREATURE'S COMMITTED ARRIVAL OUTRANKS ITS OWN MOVEMENT NOISE — in PAIRS, never across creatures.
    try std.testing.expect(g(.toad_lunge) > g(.toad_hop));
    try std.testing.expect(g(.shroom_fling) > g(.shroom_hop));
    try std.testing.expect(g(.delver_burst) > g(.delver_churn));
    try std.testing.expect(g(.delver_surge) > g(.delver_dig));
    try std.testing.expect(g(.ogre_slam) > g(.ogre_step));
    try std.testing.expect(g(.leech_stab) > g(.leech_wing));
    try std.testing.expect(g(.wood_swing) > g(.wood_creak));
    try std.testing.expect(g(.kobold_heave) > g(.kobold_whirl));
    // …AND THE ONGOING HOLD IS TEXTURE, where the blow that opened it is the event.
    try std.testing.expect(g(.leech_stab) > g(.leech_drink));
    // THE TELLS SIT AT THE TOP OF THE BAND — every one of them past the midpoint of it.
    var hi: f32 = 0;
    for (BANK) |row| {
        if (row.mix == .combat) hi = mathx.maxF(hi, row.gain);
    }
    const mid = (BATTLE_FLOOR + hi) * 0.5;
    for ([_]Id{ .ogre_slam, .ogre_roar, .skel_lunge, .toad_lunge, .shroom_fling, .delver_surge, .delver_burst, .wood_wake, .wood_swing, .kobold_heave, .guard_break }) |id| {
        try std.testing.expect(g(id) > mid);
    }
    // …and the texture sits at or under the floor, which is what takes it out of the band entirely.
    for ([_]Id{ .toad_hop, .shroom_hop, .delver_churn, .wood_creak, .leech_wing, .kobold_whirl }) |id| {
        try std.testing.expect(g(id) <= BATTLE_FLOOR + 1e-6);
    }
}

test "every BED has two takes to pan, and they do not loop in lockstep" {
    // BEDS MUST NOT SHARE A LENGTH: equal-length beds re-trigger on the same frame for the whole session,
    // and two textures repeating in lockstep is a loop you can hear even when neither is audible alone.
    var i: usize = 0;
    while (i < BEDS.len) : (i += 1) {
        // Played through `bed`, which needs two takes to have two channels to pan hard apart.
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
    try std.testing.expect(behind > 0.85); // still unmistakably audible
}

test "the BED's two takes are decorrelated — that IS its width, and it is checkable" {
    const idx: usize = @intFromEnum(Id.wind);
    const first = try std.testing.allocator.alloc(f32, MAX_N); // `work` is one shared buffer
    defer std.testing.allocator.free(first);

    var r0 = Rack.init(0x9E3779B9 *% (idx + 1) +% 0, seconds(.wind));
    BANK[idx].make(&r0);
    @memcpy(first[0..r0.n], work[0..r0.n]);
    var r1 = Rack.init(0x9E3779B9 *% (idx + 1) +% 1, seconds(.wind));
    BANK[idx].make(&r1);
    try std.testing.expectEqual(r0.n, r1.n); // the pair must retrigger together

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
    try std.testing.expect(n > @as(usize, @intFromFloat(SRF * 1.5))); // long enough to be a chord, not a ping
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
    try std.testing.expect(tail < middle); // …but dying, not sustaining: a room, not a drone
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
            return 0.5 * pan * (3.0 - pan * pan); // raudio.c MixAudioFrames
        }
    }.g;
    // Hard pan really is the louder end of that law — the reason the drop was needed at all.
    try std.testing.expect(law(1.0) > law(0.5) * 1.3);
    const before = 0.055 * law(0.5); // one centred take, in either ear
    const after = BANK[@intFromEnum(Id.wind)].gain *
        @sqrt(law(BED_PAN) * law(BED_PAN) + law(1.0 - BED_PAN) * law(1.0 - BED_PAN));
    try std.testing.expect(after < before); // quieter, as asked…
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
            return n / (@as(f32, @floatFromInt(r.n)) / SRF); // crossings per second
        }
    }.of;
    const wind = crossings(.wind, @intFromEnum(Id.wind));
    try std.testing.expect(wind < 0.75 * crossings(.toad_chomp, @intFromEnum(Id.toad_chomp)));
    try std.testing.expect(wind < 0.60 * crossings(.swing_light, @intFromEnum(Id.swing_light)));

    // THE BIRDS ARE NOT MEASURED THIS WAY: a chirp is PITCHED, so its zero-crossing rate is set by its
    // fundamental and barely moves when the reedy harmonics come off the top.
    try std.testing.expect(AIR_FAR_CALL < AIR_NEAR_DARKEST);
    try std.testing.expect(AIR_FAR_BED < AIR_FAR_CALL); // the bed is the furthest thing in the world
    try std.testing.expect(AIR_FAR_CRY < AIR_FAR_CALL);
    try std.testing.expect(AIR_FAR_CRY < AIR_NEAR_DARKEST);
    // …and neither so dark it stops being the thing it is: a bird still has to be a whistle (its band tops
    // out at 2500 Hz) and wind still has to have air in it, not just rumble.
    try std.testing.expect(AIR_FAR_CALL > 1200 and AIR_FAR_BED > 800);
    try std.testing.expect(AIR_NEAR_GRASS > AIR_NEAR_DARKEST);
    // …and every one of the FAR voices stays on the far side of it.
    for ([_]f32{ AIR_FAR_BED, AIR_FAR_CALL, AIR_FAR_CRY }) |cut| {
        try std.testing.expect(cut < AIR_NEAR_DARKEST);
    }
}

test "NO SUSTAINED CALL SITS IN THE MOSQUITO BAND" {
    const MOSQUITO_LO: f32 = 350.0;
    const HELD: f32 = 0.55; // a "held" cry — anything shorter is a hoot or a chirp, and safe
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
    r.body(0.0, 0.10, 220, 60, 0.9, 4.0); // a plain impact — peaks near full scale, then nothing
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
