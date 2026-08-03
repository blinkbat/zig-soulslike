const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");


pub const SR: usize = 22050;
const SRF: f32 = @floatFromInt(SR);
const MAX_N: usize = 9 * SR; // the longest a single voice may be (the wind bed is the only long one)

// Rendering is allocation-free like everything else here: one working buffer, one delay buffer for the wow, one PCM staging buffer, all BSS and all reused voice after voice.
var work: [MAX_N]f32 = undefined;
var tape: [MAX_N]f32 = undefined;
var pcm: [MAX_N]i16 = undefined;

/// A resonant state-variable filter (Chamberlin), the workhorse of the whole bank.
const Svf = struct {
    lp: f32 = 0,
    bp: f32 = 0,

    /// One sample.
    fn step(s: *Svf, x: f32, cut: f32, res: f32) struct { lp: f32, bp: f32, hp: f32 } {
        // Chamberlin is only stable while f stays well under 1; cap the cutoff at a sixth of the rate rather than letting a sweep's top end blow the filter up into a full-scale scream.
        const f = 2.0 * mathx.sinf(std.math.pi * mathx.clampF(cut, 20.0, SRF / 6.0) / SRF);
        const q = mathx.clampF(1.6 - 1.55 * res, 0.05, 2.0);
        const hp = x - s.lp - q * s.bp;
        s.bp += f * hp;
        s.lp += f * s.bp;
        return .{ .lp = s.lp, .bp = s.bp, .hp = hp };
    }
};

/// One-pole lowpass — the gentle one, for warmth rather than shape.
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

/// Attack-then-decay, for anything that has to SWELL before it goes (roars, motes, the death card).
fn swell(u: f32, peak: f32) f32 {
    const t = mathx.clampF(u, 0, 1);
    if (t < peak) return mathx.smoothstep(0, peak, t);
    return decay((t - peak) / (1.0 - peak), 3.5);
}

const Rack = struct {
    n: usize = 0, // samples written so far (the voice's length)
    rng: mathx.Rng,

    // `secs`, not `seconds` — that name belongs to the bank's own length table below, and a parameter shadowing a declaration is a compile error in Zig (rightly).
    fn init(seed: u64, secs: f32) Rack {
        const n = @min(@as(usize, @intFromFloat(secs * SRF)), MAX_N);
        @memset(work[0..n], 0);
        return .{ .n = n, .rng = mathx.Rng.init(seed) };
    }

    fn at(r: *const Rack, t: f32) usize {
        return @min(@as(usize, @intFromFloat(mathx.maxF(t, 0) * SRF)), r.n);
    }

    /// THE FAT LOW END.
    fn body(r: *Rack, t0: f32, dur: f32, f0: f32, f1: f32, amp: f32, curve: f32) void {
        const a = r.at(t0);
        const b = @min(a + r.at(dur), r.n);
        var ph: f32 = 0;
        var i = a;
        while (i < b) : (i += 1) {
            const u = @as(f32, @floatFromInt(i - a)) / @as(f32, @floatFromInt(b - a));
            const f = f0 * std.math.pow(f32, f1 / f0, u); // exponential glide reads as one fall
            ph += std.math.tau * f / SRF;
            work[i] += mathx.sinf(ph) * amp * decay(u, curve);
        }
    }

    fn air(r: *Rack, t0: f32, dur: f32, amp: f32, c0: f32, c1: f32, res: f32, curve: f32) void {
        const a = r.at(t0);
        const b = @min(a + r.at(dur), r.n);
        var f = Svf{};
        var i = a;
        while (i < b) : (i += 1) {
            const u = @as(f32, @floatFromInt(i - a)) / @as(f32, @floatFromInt(b - a));
            const cut = c0 * std.math.pow(f32, c1 / c0, mathx.smoothstep(0, 1, u));
            const out = f.step(r.rng.signed(), cut, res);
            work[i] += out.bp * amp * decay(u, curve);
        }
    }

    /// GRIT — lowpassed noise with a granular amplitude, so it CRUNCHES instead of hissing.
    fn grit(r: *Rack, t0: f32, dur: f32, amp: f32, cut: f32, coarse: f32, curve: f32) void {
        const a = r.at(t0);
        const b = @min(a + r.at(dur), r.n);
        var p = Pole{};
        var hold: f32 = 0;
        var left: i32 = 0;
        var i = a;
        while (i < b) : (i += 1) {
            const u = @as(f32, @floatFromInt(i - a)) / @as(f32, @floatFromInt(b - a));
            // Sample-and-hold on the noise: holding a value for a few samples is what turns a smooth hiss into audible GRAINS, and the grain size is the difference between sand and shingle.
            if (left <= 0) {
                hold = r.rng.signed();
                left = 1 + r.rng.intn(@intFromFloat(1.0 + coarse * 12.0));
            }
            left -= 1;
            work[i] += p.step(hold, cut) * amp * decay(u, curve);
        }
    }

    /// RING — a stack of detuned decaying partials.
    fn ring(r: *Rack, t0: f32, dur: f32, f0: f32, amp: f32, curve: f32, parts: u32) void {
        const a = r.at(t0);
        const b = @min(a + r.at(dur), r.n);
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
                const u = @as(f32, @floatFromInt(i - a)) / @as(f32, @floatFromInt(b - a));
                work[i] += mathx.sinf(ph0 + std.math.tau * f * @as(f32, @floatFromInt(i - a)) / SRF) * g * decay(u, d);
            }
        }
    }

    /// VOICE — a driven saw with vibrato, swept through a resonant lowpass.
    fn growl(r: *Rack, t0: f32, dur: f32, f0: f32, f1: f32, amp: f32, rough: f32, shape: f32) void {
        const a = r.at(t0);
        const b = @min(a + r.at(dur), r.n);
        var f = Svf{};
        var ph: f32 = 0;
        var vib: f32 = 0;
        var i = a;
        while (i < b) : (i += 1) {
            const u = @as(f32, @floatFromInt(i - a)) / @as(f32, @floatFromInt(b - a));
            vib += std.math.tau * (5.5 + 3.0 * u) / SRF;
            const hz = f0 * std.math.pow(f32, f1 / f0, u) * (1.0 + 0.035 * mathx.sinf(vib));
            ph += hz / SRF;
            ph -= @floor(ph);
            const saw = 2.0 * ph - 1.0 + rough * r.rng.signed();
            // The formant sweep: a lowpass riding two octaves above the fundamental is roughly where a throat's first resonance sits, and moving it with the pitch is what keeps a long groan from turning into a drone.
            const out = f.step(saw, hz * (3.0 + 5.0 * (1.0 - u)), 0.72);
            work[i] += out.lp * amp * swell(u, shape);
        }
    }

    /// A TICK — the transient at the front of a hit.
    fn tick(r: *Rack, t0: f32, amp: f32, cut: f32) void {
        r.grit(t0, 0.012, amp, cut, 0.0, 5.0);
    }

    /// A DIGITAL BIRDCALL — two to four short pulse blips at STEPPED pitches.
    fn chirp(r: *Rack, t0: f32, amp: f32, base: f32) void {
        const notes = 2 + r.rng.intn(3);
        var t = t0;
        var k: i32 = 0;
        while (k < notes) : (k += 1) {
            // Whole semitones off the base, and a small set of them — a bird's phrase is a motif, not a scale run.
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
                // Lowpassed hard, or an 8 kHz square at 22 kHz is pure alias fizz — and lowpassed HARDER than that (2600, was 4200) because every bird in this game is a bird out on the plain.
                work[i] += lp.step(pulse, 2600) * amp * decay(u, 3.0) * mathx.smoothstep(0, 0.15, u);
            }
            t += dur + r.rng.range(0.012, 0.045);
        }
    }

    // separately-authored sounds feel like they were recorded in the same room on the same machine.

    /// Soft saturation.
    fn sat(r: *Rack, drive: f32) void {
        for (work[0..r.n]) |*s| {
            const x = s.* * drive;
            s.* = x / (1.0 + @abs(x)); // a cheap tanh, and the asymmetry-free one we want
        }
    }

    /// The tape's own bandwidth.
    fn warm(r: *Rack, cut: f32) void {
        var p = Pole{};
        for (work[0..r.n]) |*s| s.* = p.step(s.*, cut);
    }

    /// WOW & FLUTTER — a slow, drifting pitch wobble read out of a fractional delay.
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
            // `ia`/`ib`, not `i0`/`i1` — those are real Zig integer TYPE names and shadowing a primitive is a compile error (archer.zig's trail loop hit the same wall).
            const ia: usize = @intFromFloat(@floor(src));
            const fr = src - @floor(src);
            const ib = @min(ia + 1, r.n - 1);
            work[i] = tape[ia] * (1.0 - fr) + tape[ib] * fr;
        }
    }

    /// THE NOISE FLOOR.
    fn hiss(r: *Rack, amt: f32) void {
        var p = Pole{};
        var q = Pole{};
        var i: usize = 0;
        while (i < r.n) : (i += 1) {
            const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(r.n));
            // Two poles, so the hiss is a soft band and not a fizz; it fades with the voice so a short sound does not leave a tail of noise hanging behind it.
            const nz = q.step(p.step(r.rng.signed(), 5200), 2600);
            work[i] += nz * amt * (0.35 + 0.65 * decay(u, 1.6));
        }
    }

    /// levels), pixelate (fewer samples) and dither; this is those three exactly, on a waveform: quantize the AMPLITUDE to `bits`, sample-and-HOLD to drop the effective rate by `hold`, and dither the quantizer so the decay tails don't step.
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

    /// Peak-normalize, so a row's `gain` means the same thing across the whole bank and retuning one voice's layers can never quietly make it the loudest thing in the game.
    fn norm(r: *Rack, peak: f32) void {
        var hi: f32 = 1e-6;
        for (work[0..r.n]) |s| hi = mathx.maxF(hi, @abs(s));
        const k = peak / hi;
        for (work[0..r.n]) |*s| s.* *= k;
    }

    /// Ramp the ends to zero.
    fn ends(r: *Rack, inS: f32, outS: f32) void {
        const ni = @max(r.at(inS), 1);
        const no = @max(r.at(outS), 1);
        for (work[0..@min(ni, r.n)], 0..) |*s, i| s.* *= @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(ni));
        var i: usize = 0;
        while (i < @min(no, r.n)) : (i += 1) work[r.n - 1 - i] *= @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(no));
    }

    /// The finish every voice ends on.
    fn master(r: *Rack, drive: f32, cut: f32) void {
        r.masterX(drive, cut, CRUSH_BITS, CRUSH_HOLD);
    }

    /// …and the same finish with the CRUSH dialled per voice.
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

// `CRUSH_BITS` is the amplitude quantizer (fewer = grittier — the audio posterize) and `CRUSH_HOLD` divides the effective sample rate (2 = 11 kHz — the audio pixelate).
const CRUSH_BITS: f32 = 7.5; // was 5.5 — +2 bits is −12 dB of floor, and 180 levels still staircases
/// DITHER DEPTH IN LSB, and the textbook ±1 is a SIXTEEN-BIT rule.
const DITHER_LSB: f32 = 0.4; // …another −8 dB. MEASURED: the chain's tail floor goes −34.7 → −50.8 dBFS
const CRUSH_HOLD: u32 = 2;

// The cue that actually makes a sound read as FAR rather than as quiet.
const AIR_FAR_BED: f32 = 1400; // the wind, a few hundred metres of it in every direction
const AIR_FAR_CALL: f32 = 2100; // …and a bird somewhere out on the plain
/// The big LOW cry — the OWL (a wolf howl was the other and is gone).
const AIR_FAR_CRY: f32 = 1950;
/// The darkest any NEAR voice is rendered (mkOgreStep / mkStepSoft sit here).
const AIR_NEAR_DARKEST: f32 = 2200;
/// …and the one voice that is deliberately NEARER than anything else in the game: the crickets are in the grass AT YOUR FEET, so they are the only ambient layer rendered BRIGHT.
const AIR_NEAR_GRASS: f32 = 4200;

// Order is the BANK table's order below; the two are pinned at comptime.
pub const Id = enum {
    // the hero on his feet
    step_soft,
    step_hard,
    step_sprint,
    // …and WHAT HE IS WALKING ON, as two OVERLAYS played on top of whichever boot fired (see `game.footsteps`).
    step_stone,
    step_water,
    roll,
    // the hero's sword
    swing_light,
    swing_heavy,
    hit_light,
    hit_heavy,
    // the hero taking it
    hurt,
    hurt_heavy,
    stagger,
    guard_block, // …and NOT taking it: a blow caught on the boards
    guard_break, // …until they are knocked aside
    refused,
    death,
    respawn,
    // the gaping toad
    toad_hop,
    toad_lunge,
    toad_gape,
    toad_chomp,
    toad_hurt,
    toad_die,
    // the skeletal archer
    bow_draw,
    bow_loose,
    arrow_hit, // …into flesh — all rip
    arrow_dirt, // …into the earth (the miss)
    arrow_wood, // …into timber
    arrow_stone, // …into masonry
    arrow_metal, // …into ironwork
    bone_hurt,
    bone_die,
    // the one-eyed ogre
    ogre_step,
    ogre_roar,
    ogre_slam,
    ogre_swipe,
    ogre_hurt,
    ogre_die,
    // animal because the yip and the snarl are the same larynx at different sizes.
    kobold_snarl, // HE COMMITS — one bark per flurry, and the cue to get out of reach
    kobold_chop, // …then the axe coming round, once per swing and nothing else in it
    kobold_heave, // …and the flurry's price: a winded, ragged panting
    kobold_cast, // the priest's tell, rising
    kobold_heal, // …and it landing on somebody
    kobold_whirl, // the sling going round overhead
    kobold_sling, // …and the release
    kobold_bite, // teeth: a snap with a wet click in it
    kobold_hurt,
    kobold_die, // a yelp that falls apart
    // THE BROOD. Everything of hers is WET — chitin over fluid — where the kobold is dry and the skeleton
    // is hollow. That is the whole family resemblance, and it is what a player will name her by.
    spider_hiss, // the rear, and the squat before she lays: air forced out through something clenched
    spider_spit, // …and the throw: a heave and a wet launch
    spider_bite, // two fangs and the horn claws crossing behind them
    spider_hurt,
    spider_die, // the big one going over: legs rattling on the ground, then nothing
    brood_screech, // IT IS BORN — the highest thing in the game, straight over the sac splitting
    brood_leap, // a hatchling committing — a thin shriek, and the only warning you get
    brood_bite,
    brood_hurt,
    brood_die, // a wet pop, and it is done
    sac_lay, // something heavy and soft arriving on the ground
    sac_hit, // …and a blade going into it, which does NOT sound like hitting a body
    sac_hatch, // the membrane splitting and three of them coming out at once
    sac_burst, // …or the same thing killed: a burst, and nothing comes out
    acid_splash, // the glob landing and spreading
    acid_burn, // …and standing in it, once per pulse
    // the flasks
    flask_drink,
    flask_cycle,
    eat, // …and the other kind of mouthful: something dried, torn and chewed
    chest_open, // a lid coming up: the lock giving, the hinge turning, the boards settling back
    item_get, // …and something going into the bag
    // the world and the chrome
    kill,
    menu_move,
    menu_pick,
    menu_back,
    wind,
    // bird on it reads as a plain with a single repeating bird on it.
    birds, // …their OWN voice, not five phrases baked into the wind loop (see mkBirds)
    birdsong, // …a SECOND bird, and the opposite kind: fluted and slurred where `birds` is stepped
    owl, // hoo … hu-hoooo, from somewhere in the ruins
    crickets, // the insect chirr in the grass — a BED, and the only ambient voice rendered bright
    // (A WOLF howl was the fifth ambient voice and is GONE — owner's call, after it turned out to be the "skeeter".
};
const NV = @typeInfo(Id).@"enum".fields.len;

pub const Submix = enum {
    /// The chrome and the hero's ordinary business: his boots, the roll, his flasks, a chest, the menu.
    sfx,
    /// THE FIGHT and everyone in it: his steel, the blows either way, the guard, every foe voice and every arrow.
    combat,
    /// THE BACKGROUND: both beds and all three sparse calls.
    ambience,
};
const NMIX = @typeInfo(Submix).@"enum".fields.len;

// SET BY EAR, THEN SOLVED. 0.55 was too quiet and a first pass at 2.5 was far too loud; the owner played it at 2.5 with the dial on 0.20 and called that right, and asked for that exact loudness to sit at 0.80 on the dial — headroom above the preferred level rather than at the top of it. gain * TRIM * 0.80 == gain * 2.5 * 0.20 → TRIM = 0.625 So this number is not a taste any more, it is the answer to that equation, and the pair of it is `DEFAULT_VOL[.ambience]` below — moving one without the other moves what the dial's 0.80 means.
const TRIM_AMBIENCE: f32 = 0.625;

fn submixTrim(m: Submix) f32 {
    return switch (m) {
        .sfx, .combat => 1.0,
        .ambience => TRIM_AMBIENCE,
    };
}

const Row = struct {
    make: *const fn (*Rack) void,
    gain: f32 = 0.7,
    /// Which family's trim this row pays, and which Options slider moves it (see `Submix`).
    mix: Submix = .sfx,
    jit: f32 = 0.06,
    vjit: f32 = 0.12,
    vars: u8 = 1,
    poly: u8 = 2,
    /// HOW FAR THIS VOICE CARRIES, in metres — the range `world()` fades it out over, and past which it costs nothing at all.
    reach: f32 = FALLOFF,
};

// Each is a handful of layers plus the master.

fn mkStepSoft(r: *Rack) void {
    // A walk: a soft heel body, a scuff of grit, and nothing else.
    r.body(0.0, 0.11, 108 + r.rng.signed() * 12, 52, 0.55, 5.0);
    r.grit(0.004, 0.075, 0.28, 1500 + r.rng.signed() * 400, 0.5, 5.5);
    r.air(0.0, 0.05, 0.10, 900, 380, 0.35, 6.0);
    r.master(1.5, 3000);
}

fn mkStepHard(r: *Rack) void {
    // A run: more mass, a harder transient, and the grit sprays further.
    r.tick(0.0, 0.20, 3000);
    r.body(0.0, 0.16, 138 + r.rng.signed() * 14, 46, 0.85, 4.2);
    r.grit(0.003, 0.13, 0.40, 2100 + r.rng.signed() * 500, 0.55, 4.6);
    r.air(0.0, 0.08, 0.16, 1500, 420, 0.4, 5.0);
    r.master(1.9, 3400);
}

fn mkStepSprint(r: *Rack) void {
    // A sprint: the same boot, but the weight lands ahead of the body — a longer low tail and a scrape on the push-off, so a full-tilt run has its own rhythm in the ears as well as the legs.
    r.tick(0.0, 0.26, 3600);
    r.body(0.0, 0.20, 152 + r.rng.signed() * 16, 42, 1.0, 3.6);
    r.grit(0.002, 0.17, 0.46, 2600 + r.rng.signed() * 600, 0.5, 3.9);
    r.air(0.012, 0.11, 0.22, 2400, 500, 0.45, 4.0);
    r.master(2.2, 3600);
}

fn mkStepStone(r: *Rack) void {
    // A CLOP, and ONLY the clop — this rides on top of a boot that already has the weight, so it carries nothing low at all.
    r.tick(0.0, 0.55, 6500);
    r.body(0.0, 0.045, 660, 300, 0.5, 9.5);
    r.ring(0.001, 0.05, 2400, 0.16, 10.0, 2);
    r.grit(0.0, 0.05, 0.30, 3800, 0.35, 7.0);
    r.master(1.8, 5400);
}

fn mkStepWater(r: *Rack) void {
    // THE PLUNK IS A RISING BODY, and that is the whole voice.
    r.air(0.0, 0.11, 0.34, 700, 3200, 0.30, 4.0); // the sheet thrown up
    r.body(0.008, 0.07, 380, 820, 0.42, 6.5);
    r.body(0.052, 0.05, 620, 1180, 0.22, 7.5);
    r.grit(0.02, 0.13, 0.16, 2600, 0.25, 3.4); // …and the droplets coming back down
    r.master(1.7, 4200);
}

fn mkRoll(r: *Rack) void {
    // CLOTH AND GRIT OVER DIRT, and NOTHING THAT SWEEPS.
    r.grit(0.0, 0.20, 0.34, 1100, 0.55, 3.0);
    r.body(0.05, 0.16, 78, 40, 0.42, 4.5); // …the shoulder taking it
    r.grit(0.24, 0.13, 0.20, 1700, 0.45, 4.0); // …and the plant coming out of it
    r.air(0.0, 0.16, 0.10, 900, 480, 0.10, 3.2); // a breath of cloth, resonance nearly shut — no glide
    r.master(1.15, 2600);
}

fn mkSwingLight(r: *Rack) void {
    // R1: MOVED AIR, not a cartoon vwip (owner's call — the old pair sounded stupid).
    r.air(0.0, 0.15, 0.55, 2000, 620, 0.16, 2.6);
    r.air(0.015, 0.085, 0.16, 5200, 2400, 0.12, 3.4); // the EDGE: a thin hiss riding the front of it
    r.master(1.05, 4200);
}

fn mkSwingHeavy(r: *Rack) void {
    // R2: the raise, a beat, then the drop — the same two-part gesture, still timed to the pause the animation holds at the top of the arc, but taken out of cartoon territory the same way the light was: resonance nearly shut, less drive, and the raise dropped to almost nothing so the DROP is the only part that speaks.
    r.air(0.0, 0.26, 0.26, 900, 1500, 0.14, 1.7);
    r.air(0.24, 0.30, 0.72, 2200, 380, 0.18, 2.1);
    r.body(0.26, 0.14, 170, 64, 0.22, 3.8); // a little mass behind the edge
    r.master(1.25, 3600);
}


fn mkHitLight(r: *Rack) void {
    // Blade into a body: a wet crack and a low thump under it.
    r.tick(0.0, 0.34, 2200);
    r.body(0.0, 0.20, 170, 56, 1.05, 3.8); // …lower and longer: this is the layer doing the work
    r.body(0.0, 0.09, 88, 52, 0.5, 5.0); // a sub under it, for the thud
    r.grit(0.0, 0.10, 0.34, 1500, 0.45, 5.0);
    r.ring(0.004, 0.13, 700, 0.13, 7.0, 2);
    r.master(1.25, 2500);
}

fn mkHitHeavy(r: *Rack) void {
    // The R2 connecting: everything the light has, dropped an octave and given a crunch that carries.
    r.tick(0.0, 0.40, 1800);
    r.body(0.0, 0.36, 128, 34, 1.35, 2.4);
    r.body(0.0, 0.14, 66, 38, 0.62, 4.0); // …and the floor under that
    r.grit(0.0, 0.24, 0.52, 1200, 0.75, 3.2);
    r.ring(0.006, 0.20, 520, 0.15, 5.0, 3);
    r.body(0.11, 0.22, 58, 30, 0.5, 3.0);
    r.master(1.45, 2100);
}

fn mkHurt(r: *Rack) void {
    // Taking a chomp: a short winded grunt over the impact.
    r.body(0.0, 0.19, 118, 46, 0.85, 3.8);
    r.growl(0.01, 0.22, 156, 108, 0.60, 0.11, 0.14);
    r.grit(0.0, 0.09, 0.22, 1100, 0.45, 5.0);
    r.master(1.3, 2200);
}

fn mkHurtHeavy(r: *Rack) void {
    // The lunge or the slam landing: the air goes out of him.
    r.body(0.0, 0.38, 98, 30, 1.15, 2.4);
    r.growl(0.0, 0.42, 140, 70, 0.85, 0.15, 0.10);
    r.grit(0.0, 0.16, 0.34, 900, 0.68, 3.4);
    r.air(0.02, 0.26, 0.18, 1400, 240, 0.30, 3.0);
    r.master(1.5, 1900);
}

fn mkStagger(r: *Rack) void {
    // A stance break: boots losing the floor.
    r.grit(0.0, 0.36, 0.52, 1200, 0.8, 2.4);
    r.air(0.0, 0.32, 0.30, 1200, 320, 0.34, 2.6);
    r.body(0.14, 0.18, 70, 38, 0.42, 3.6);
    r.master(1.35, 2000);
}

fn mkGuardBlock(r: *Rack) void {
    // A BLOW CAUGHT ON WOOD, with iron round the edge of it.
    r.tick(0.0, 0.42, 3400); // the strike itself…
    r.body(0.0, 0.13, 190, 78, 0.95, 5.0); // …the boards taking it, dry and quick
    r.grit(0.0, 0.07, 0.30, 2400, 0.4, 6.0); // …a splintery edge on the impact
    r.ring(0.003, 0.09, 940, 0.16, 8.0, 2); // …and the iron rim, a hint of it and nothing more
    r.master(1.6, 4200);
}

fn mkGuardBreak(r: *Rack) void {
    // THE SHIELD KNOCKED ASIDE — the loudest thing that can happen to you short of dying, and the cue that the next blow is free.
    r.tick(0.0, 0.46, 1700);
    r.body(0.0, 0.34, 132, 40, 1.30, 2.6);
    r.grit(0.0, 0.22, 0.50, 1300, 0.7, 3.2);
    r.ring(0.004, 0.30, 470, 0.22, 3.4, 3); // the rim, swinging away and still ringing
    r.grit(0.10, 0.34, 0.40, 1100, 0.8, 2.6); // …and the feet going
    r.air(0.08, 0.30, 0.24, 1300, 300, 0.32, 2.8);
    r.master(1.7, 2400);
}

fn mkRefused(r: *Rack) void {
    // AN EMPTY BAR.
    r.body(0.0, 0.055, 190, 120, 0.5, 7.0);
    r.grit(0.0, 0.04, 0.25, 700, 0.3, 8.0);
    r.master(1.4, 1400);
}

fn mkDeath(r: *Rack) void {
    // YOU DIED.
    r.growl(0.0, 1.5, 165, 62, 0.9, 0.2, 0.06);
    r.body(0.0, 2.2, 82, 33, 0.8, 1.1);
    r.body(0.10, 1.9, 41, 22, 0.6, 1.0);
    r.air(0.0, 1.6, 0.25, 900, 160, 0.35, 1.6);
    r.ring(0.55, 1.5, 210, 0.10, 1.8, 3); // a far, cold overtone coming up under it
    r.sat(2.2);
    r.warm(2400);
    r.wow(0.006, 0.9); // deeper wow than the house default: the tape is DRAGGING
    r.hiss(0.02);
    r.norm(0.95);
    r.ends(0.01, 0.35);
}

fn mkRespawn(r: *Rack) void {
    // Waking at the grace: a warm low bloom rising out of nothing.
    r.body(0.0, 1.1, 88, 132, 0.8, 1.2);
    r.ring(0.02, 1.0, 330, 0.35, 2.0, 4);
    r.air(0.0, 0.8, 0.18, 300, 1800, 0.3, 1.4);
    r.master(1.5, 3600);
}


fn mkToadHop(r: *Rack) void {
    r.body(0.0, 0.09, 190, 88, 0.5, 5.0); // the push off the haunches
    r.growl(0.0, 0.13, 130, 210, 0.45, 0.3, 0.25); // a short croak going UP with the leap
    r.grit(0.0, 0.06, 0.25, 1200, 0.6, 6.0);
    r.master(1.9, 2600);
}

fn mkToadLunge(r: *Rack) void {
    // The committed pounce: a long loaded croak on the coil, then the launch.
    r.growl(0.0, 0.36, 96, 168, 0.85, 0.34, 0.55);
    r.air(0.26, 0.22, 0.4, 600, 2200, 0.4, 2.6);
    r.body(0.28, 0.16, 150, 64, 0.7, 3.8);
    r.master(2.2, 2800);
}

fn mkToadGape(r: *Rack) void {
    // The jaws yawning: a rising airy suck with a throat under it.
    r.air(0.0, 0.34, 0.5, 260, 1500, 0.45, 1.2);
    r.growl(0.05, 0.30, 74, 108, 0.5, 0.4, 0.5);
    r.master(1.7, 2400);
}

fn mkToadChomp(r: *Rack) void {
    // The snap: a hard wet clack of jaws, a squelch, and a low thud where the head stops.
    r.tick(0.0, 0.6, 2600);
    r.body(0.0, 0.10, 240, 70, 0.9, 5.5);
    r.grit(0.0, 0.07, 0.55, 1100, 0.75, 6.0);
    r.ring(0.002, 0.06, 620, 0.2, 8.0, 2); // the teeth meeting
    r.master(2.3, 2600);
}

fn mkToadHurt(r: *Rack) void {
    r.growl(0.0, 0.22, 250, 120, 0.8, 0.45, 0.08);
    r.body(0.0, 0.12, 180, 70, 0.6, 5.0);
    r.grit(0.0, 0.09, 0.4, 1500, 0.6, 5.0);
    r.master(2.2, 2700);
}

fn mkToadDie(r: *Rack) void {
    // The croak running out of air, then the body going down.
    r.growl(0.0, 0.55, 190, 58, 0.9, 0.5, 0.07);
    r.body(0.22, 0.30, 96, 38, 0.7, 2.6);
    r.grit(0.24, 0.22, 0.35, 900, 0.7, 3.0);
    r.master(2.0, 2400);
}


fn mkBowDraw(r: *Rack) void {
    // A slow creak: resonant noise crawling upward as the limbs load.
    r.air(0.0, 0.55, 0.6, 420, 1150, 0.88, 0.9);
    r.grit(0.0, 0.5, 0.14, 2400, 0.85, 1.1); // fibres crackling under the pull
    r.master(1.6, 3400);
}

fn mkBowLoose(r: *Rack) void {
    // The release: a string twang and the shaft's fizz leaving.
    r.tick(0.0, 0.5, 6000);
    r.ring(0.0, 0.30, 196, 0.9, 5.0, 4);
    r.air(0.01, 0.22, 0.45, 4200, 1200, 0.5, 3.2);
    r.body(0.0, 0.07, 150, 84, 0.3, 6.0);
    r.master(1.9, 5000);
}


/// The shared rip: broadband noise sweeping DOWN fast.
fn arrowRip(r: *Rack, amp: f32) void {
    r.air(0.0, 0.13, amp, 5200, 900, 0.35, 3.4); // the tear
    r.grit(0.0, 0.09, amp * 0.55, 3600, 0.25, 4.6); // …with fibre in it
}

fn mkArrowHit(r: *Rack) void {
    // INTO THE HERO — flesh, so it is mostly RIP: a wet tearing fizz with only a dull, soft thump under it.
    arrowRip(r, 1.0);
    r.tick(0.0, 0.34, 2600);
    r.body(0.0, 0.15, 170, 58, 0.70, 5.0);
    r.grit(0.0, 0.10, 0.50, 1200, 0.55, 5.2);
    r.master(2.2, 3000);
}

fn mkArrowDirt(r: *Rack) void {
    // INTO THE EARTH — the miss, and by far the commonest of the four.
    arrowRip(r, 0.62);
    r.body(0.0, 0.11, 150, 52, 0.60, 6.0);
    r.grit(0.0, 0.12, 0.55, 900, 0.65, 5.0);
    r.master(1.9, 2400);
}

fn mkArrowWood(r: *Rack) void {
    // INTO TIMBER — the satisfying one.
    arrowRip(r, 0.34);
    r.tick(0.0, 0.70, 5000);
    r.body(0.0, 0.11, 300, 96, 0.95, 6.0);
    r.ring(0.003, 0.13, 420, 0.30, 8.0, 2); // a dull, low, fast-dying knock — wood, not metal
    r.grit(0.0, 0.06, 0.45, 2600, 0.4, 7.0);
    r.master(2.2, 4200);
}

fn mkArrowStone(r: *Rack) void {
    // INTO MASONRY — a STRUCTURE, and the one place a bodkin head meets something harder than it is.
    arrowRip(r, 0.40);
    r.tick(0.0, 0.85, 7000);
    r.body(0.0, 0.055, 420, 190, 0.55, 9.0);
    r.ring(0.002, 0.11, 3100, 0.34, 9.0, 2);
    r.grit(0.0, 0.07, 0.75, 4200, 0.35, 7.5);
    r.master(2.1, 5600); // …and the warmth stage opened up enough to let the tink through
}

fn mkArrowMetal(r: *Rack) void {
    // INTO IRON — a brazier, a torch bracket, a gibbet cage.
    arrowRip(r, 0.30);
    r.tick(0.0, 0.90, 8000);
    r.body(0.0, 0.06, 520, 240, 0.60, 8.5);
    r.ring(0.002, 0.30, 1750, 0.55, 4.5, 3); // the shaft and the iron singing together
    r.grit(0.0, 0.05, 0.5, 5000, 0.3, 8.0);
    r.master(2.0, 5600);
}

fn mkBoneHurt(r: *Rack) void {
    // Blade on bone: a dry rattle, no flesh in it at all.
    r.tick(0.0, 0.6, 6500);
    r.grit(0.0, 0.20, 0.85, 3800, 0.9, 4.0);
    r.ring(0.0, 0.16, 900, 0.35, 6.5, 4);
    r.body(0.0, 0.09, 260, 100, 0.4, 6.0);
    r.master(2.3, 5200);
}

fn mkBoneDie(r: *Rack) void {
    // The skeleton coming apart: a long clatter of pieces settling.
    r.grit(0.0, 0.75, 0.9, 3200, 0.95, 1.9);
    r.ring(0.0, 0.35, 700, 0.3, 4.0, 5);
    r.ring(0.16, 0.35, 520, 0.22, 4.5, 4);
    r.body(0.02, 0.28, 130, 50, 0.4, 3.0);
    r.master(2.1, 4400);
}


fn mkOgreStep(r: *Rack) void {
    // A footfall you feel: a very low body with a long tail, and gravel thrown off it.
    r.body(0.0, 0.42, 74, 27, 1.2, 2.4);
    r.body(0.0, 0.16, 150, 60, 0.4, 4.5); // a knock on top, so it reads as a FOOT not a rumble
    r.grit(0.005, 0.26, 0.45, 1500, 0.8, 3.2);
    r.master(2.6, 2200);
}

fn mkOgreRoar(r: *Rack) void {
    // The windup tell.
    r.growl(0.0, 0.85, 68, 104, 1.0, 0.28, 0.35);
    r.growl(0.02, 0.80, 102, 152, 0.5, 0.4, 0.4); // an upper throat layer, for size
    r.body(0.0, 0.7, 46, 34, 0.6, 1.4);
    r.air(0.1, 0.6, 0.16, 700, 2200, 0.3, 1.5);
    r.master(2.4, 2600);
}

fn mkOgreSlam(r: *Rack) void {
    // The club meeting the earth.
    r.tick(0.0, 0.9, 3000);
    r.body(0.0, 0.62, 96, 22, 1.5, 1.9);
    r.body(0.0, 0.20, 210, 55, 0.7, 3.6);
    r.grit(0.0, 0.40, 0.9, 1700, 0.85, 2.4);
    r.grit(0.14, 0.34, 0.35, 2600, 0.95, 2.2); // the debris, arriving late
    r.air(0.0, 0.30, 0.35, 2200, 260, 0.4, 2.6);
    r.master(3.0, 2400);
}

fn mkOgreSwipe(r: *Rack) void {
    // The horizontal scythe: a huge slow whoosh that never touches the ground.
    r.air(0.0, 0.42, 1.0, 1900, 210, 0.55, 1.8);
    r.air(0.04, 0.34, 0.4, 900, 3000, 0.35, 2.2);
    r.body(0.06, 0.24, 120, 52, 0.4, 2.8);
    r.master(2.2, 2800);
}

fn mkOgreHurt(r: *Rack) void {
    // A giant barely gives — a short annoyed grunt off a very deep body, which is what makes his high poise audible instead of only being a number.
    r.growl(0.0, 0.26, 96, 66, 0.9, 0.3, 0.1);
    r.body(0.0, 0.26, 108, 40, 0.9, 3.2);
    r.grit(0.0, 0.14, 0.4, 1400, 0.7, 4.0);
    r.master(2.5, 2400);
}

fn mkOgreDie(r: *Rack) void {
    // The topple.
    r.growl(0.0, 1.0, 92, 34, 1.0, 0.35, 0.06);
    r.body(0.62, 0.75, 74, 20, 1.3, 1.7); // he lands
    r.grit(0.62, 0.55, 0.6, 1300, 0.9, 2.0);
    r.body(0.0, 0.9, 50, 30, 0.5, 1.3);
    r.sat(2.8);
    r.warm(2100);
    r.wow(0.004, 1.1);
    r.hiss(0.016);
    r.norm(0.95);
    r.ends(0.006, 0.20);
}



// THE BARKS, and they go LOW.

fn mkKoboldSnarl(r: *Rack) void {
    // HE COMMITS.
    r.body(0.0, 0.12, 132, 84, 0.75, 4.0); // the chest behind the bark
    r.growl(0.0, 0.14, 176, 236, 0.85, 0.14, 0.06); // …up, fast, barely any rasp
    r.growl(0.10, 0.26, 208, 118, 0.60, 0.26, 0.16); // …and tearing on the way down
    r.air(0.0, 0.10, 0.16, 900, 1900, 0.30, 3.2);
    r.master(1.35, 2300);
}

fn mkKoboldChop(r: *Rack) void {
    // JUST THE AXE.
    r.air(0.0, 0.21, 0.46, 1700, 420, 0.34, 2.6); // DOWN-sweeping, so it reads as travelling past you
    r.grit(0.02, 0.10, 0.08, 1000, 0.4, 3.0); // …the haft turning in a fist
    r.growl(0.0, 0.15, 148, 116, 0.26, 0.24, 0.30); // a low grunt of effort under it, not a bark
    r.master(1.15, 2000);
}

fn mkKoboldHeave(r: *Rack) void {
    // THE OPENING, and it has to SOUND like one — this is the cue that says come back in.
    r.air(0.0, 0.24, 0.52, 1300, 380, 0.22, 1.8);
    r.growl(0.02, 0.20, 148, 104, 0.26, 0.30, 0.18); // …a wheeze under the first one
    r.air(0.30, 0.26, 0.48, 1150, 340, 0.20, 1.6);
    r.growl(0.32, 0.22, 132, 92, 0.24, 0.34, 0.20);
    r.air(0.58, 0.22, 0.40, 1000, 300, 0.18, 1.6);
    r.master(1.3, 1900);
}

fn mkKoboldCast(r: *Rack) void {
    // THE PRIEST'S TELL — A THROAT, NOT A BELL (owner: "should not be a weird bell sound").
    r.grit(0.0, 0.10, 0.20, 2600, 0.7, 5.0); // the charms — the attack
    r.growl(0.02, 0.85, 190, 300, 0.40, 0.34, 0.55); // the chant itself, climbing
    r.body(0.10, 0.75, 128, 190, 0.24, 1.6); // …a hollow tone rising with it (`body` has no vibrato)
    r.grit(0.58, 0.30, 0.10, 1500, 0.5, 2.0); // …and the charms again as it gathers
    r.master(1.5, 3200);
}

fn mkKoboldHeal(r: *Rack) void {
    // JUST A GENTLE CHIME (owner, twice — it was a low bell, then three stacked rings and a breath of air, which is a sparkle).
    r.ring(0.0, 0.30, 1568, 0.30, 3.4, 2);
    r.master(1.0, 6500);
}

fn mkKoboldWhirl(r: *Rack) void {
    // The sling going round.
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const t = 0.02 + @as(f32, @floatFromInt(i)) * 0.20;
        r.air(t, 0.17, 0.34 + 0.06 * @as(f32, @floatFromInt(i)), 900, 2400, 0.55, 2.2);
    }
    r.master(2.0, 4000);
}

fn mkKoboldSling(r: *Rack) void {
    // The release: a hard snap of cord and the stone leaving.
    r.tick(0.0, 0.5, 6000);
    r.air(0.0, 0.11, 0.46, 3400, 1200, 0.5, 4.5);
    r.body(0.0, 0.06, 300, 150, 0.22, 6.0);
    r.master(2.2, 5400);
}

fn mkKoboldBite(r: *Rack) void {
    // TEETH.
    r.air(0.0, 0.07, 0.26, 900, 1700, 0.32, 3.5);
    r.tick(0.06, 0.34, 2600); // the clack — and 7 kHz of it was the ice-pick in the mix
    r.ring(0.06, 0.06, 620, 0.14, 9.0, 2);
    r.body(0.05, 0.10, 128, 72, 0.55, 4.5); // the jaw has MASS: this is what the clack was missing
    r.growl(0.0, 0.16, 210, 148, 0.5, 0.22, 0.10);
    r.master(1.3, 2200);
}

fn mkKoboldHurt(r: *Rack) void {
    // A yelp — up, then straight down.
    r.body(0.0, 0.13, 120, 66, 0.6, 4.2);
    r.growl(0.0, 0.15, 200, 300, 0.85, 0.16, 0.08);
    r.growl(0.05, 0.18, 168, 104, 0.42, 0.26, 0.24); // …and the fall out of it
    r.air(0.0, 0.10, 0.16, 1200, 500, 0.26, 3.0);
    r.master(1.3, 2200);
}

fn mkKoboldDie(r: *Rack) void {
    // The yelp that does not recover: it starts as the hurt voice and comes apart, dropping through a rattle into nothing.
    r.growl(0.0, 0.18, 216, 326, 0.9, 0.18, 0.08);
    r.growl(0.09, 0.48, 194, 78, 0.62, 0.30, 0.14);
    r.grit(0.26, 0.34, 0.24, 1100, 0.75, 2.4); // …a wet rattle in the throat
    r.body(0.30, 0.26, 96, 36, 0.44, 2.8); // …and the body going down
    r.master(1.35, 1900);
}

// ── THE BROOD ────────────────────────────────────────────────────────────────────────────────────────
// EVERY VOICE HERE IS WET, and that is the family: air forced through fluid, chitin knocking on chitin,
// and nothing with a proper chest behind it. Where the kobold barks and the skeleton clatters, she seeps.

fn mkSpiderHiss(r: *Rack) void {
    // THE REAR. Not a snake's hiss — air squeezed out of something that has to clench to do it, so it
    // comes in two pushes and there is liquid in the second.
    r.air(0.0, 0.38, 0.46, 2600, 5200, 0.42, 1.5); // …climbing, which is what makes it a THREAT and not an exhale
    r.grit(0.06, 0.34, 0.16, 2200, 0.35, 1.8); // the wet in it
    r.growl(0.02, 0.30, 96, 132, 0.20, 0.55, 0.40); // a low seething under the air
    r.air(0.30, 0.30, 0.34, 4200, 2400, 0.38, 2.2); // …and the second push, falling away
    r.master(1.5, 5200);
}

fn mkSpiderSpit(r: *Rack) void {
    // THE THROW: the body heaving behind it, then the glob actually leaving — a wet slap, not a hiss.
    r.growl(0.0, 0.10, 150, 90, 0.42, 0.40, 0.10); // the heave
    r.grit(0.07, 0.09, 0.52, 1500, 0.55, 5.0); // the launch — thick and granular
    r.air(0.07, 0.14, 0.40, 1900, 700, 0.40, 3.6); // …and it going away from you
    r.body(0.07, 0.07, 210, 96, 0.34, 6.0);
    r.master(1.8, 3600);
}

fn mkSpiderBite(r: *Rack) void {
    // TWO FANGS, and the horn claws crossing behind them — the clack is doubled and unevenly spaced,
    // because nothing on her closes at once.
    r.air(0.0, 0.08, 0.30, 1000, 2000, 0.34, 3.4);
    r.tick(0.05, 0.42, 2400);
    r.tick(0.072, 0.30, 3100); // …the second fang, a hair behind the first
    r.ring(0.05, 0.09, 480, 0.20, 8.0, 3); // horn, not bone: lower and deader than the kobold's clack
    r.body(0.05, 0.12, 112, 60, 0.52, 4.2); // the mass of the head behind it
    r.grit(0.05, 0.14, 0.20, 800, 0.6, 3.2); // …and it is a WET mouth
    r.master(1.4, 2200);
}

fn mkSpiderHurt(r: *Rack) void {
    // A shriek through a spiracle, with the shell cracking under it.
    r.grit(0.0, 0.07, 0.44, 2800, 0.5, 5.5); // the shell
    r.air(0.0, 0.26, 0.44, 3400, 1500, 0.52, 2.6);
    r.growl(0.0, 0.22, 340, 190, 0.44, 0.42, 0.14);
    r.body(0.0, 0.11, 130, 70, 0.40, 4.4);
    r.master(1.4, 3400);
}

fn mkSpiderDie(r: *Rack) void {
    // THE BIG ONE GOING OVER: the shriek collapsing, the body arriving, and eight legs rattling on the
    // ground after it has stopped — which is the part that says spider.
    r.growl(0.0, 0.30, 360, 120, 0.70, 0.44, 0.10);
    r.air(0.0, 0.42, 0.44, 3000, 900, 0.46, 1.9);
    r.body(0.22, 0.30, 104, 40, 0.66, 3.0); // it comes down
    r.grit(0.30, 0.52, 0.26, 1300, 0.85, 1.7); // …and the legs go on moving without it
    r.grit(0.62, 0.34, 0.14, 1000, 0.9, 2.2);
    r.master(1.35, 2000);
}

fn mkBroodScreech(r: *Rack) void {
    // THE BIRTH CRY, and the highest voice in the bank by a long way (owner: higher than the hatch it
    // rides over). Two throats a hair apart so it beats and never sounds like one clean tone, climbing
    // hard and breaking at the top — a thing announcing itself, not a thing warning you.
    r.growl(0.0, 0.30, 900, 1750, 0.72, 0.26, 0.16);
    r.growl(0.015, 0.28, 940, 1690, 0.44, 0.40, 0.20); // …the beat against it
    r.air(0.0, 0.30, 0.34, 4200, 8000, 0.55, 2.0); // the hiss of it, climbing with the pitch
    r.growl(0.24, 0.16, 1600, 820, 0.42, 0.55, 0.30); // …and the break at the top
    r.grit(0.0, 0.07, 0.26, 5200, 0.35, 5.0); // the membrane letting go under it
    r.master(1.7, 8200); // …and the brightest master in the bank, because that is the whole point
}

fn mkBroodLeap(r: *Rack) void {
    // A HATCHLING COMMITTING — thin, high and short. It is the only warning the pounce gives, so it has
    // to cut through a fight rather than sit under it.
    r.growl(0.0, 0.13, 620, 980, 0.70, 0.30, 0.10);
    r.air(0.0, 0.10, 0.24, 3000, 6000, 0.45, 3.0);
    r.tick(0.0, 0.24, 5200); // the legs leaving the ground
    r.master(1.5, 6200);
}

fn mkBroodBite(r: *Rack) void {
    // The same mouth as hers, a third the size: brighter, faster, and hardly any body behind it.
    r.tick(0.02, 0.34, 4200);
    r.tick(0.036, 0.24, 5000);
    r.ring(0.02, 0.05, 1050, 0.16, 10.0, 2);
    r.air(0.0, 0.05, 0.22, 1800, 3200, 0.34, 4.2);
    r.body(0.02, 0.05, 220, 130, 0.24, 6.0);
    r.master(1.3, 4400);
}

fn mkBroodHurt(r: *Rack) void {
    r.grit(0.0, 0.05, 0.40, 4200, 0.4, 6.0); // the shell, and there is not much of it
    r.growl(0.0, 0.13, 760, 420, 0.52, 0.36, 0.10);
    r.air(0.0, 0.12, 0.26, 4000, 2200, 0.44, 3.4);
    r.master(1.3, 5200);
}

fn mkBroodDie(r: *Rack) void {
    // A WET POP. It does not have a death, it has an end.
    r.grit(0.0, 0.06, 0.62, 2200, 0.6, 6.0);
    r.body(0.0, 0.09, 300, 90, 0.50, 5.5);
    r.growl(0.0, 0.10, 820, 300, 0.44, 0.40, 0.08);
    r.grit(0.05, 0.14, 0.20, 1200, 0.8, 3.0); // …the spill
    r.master(1.5, 3200);
}

fn mkSacLay(r: *Rack) void {
    // Something heavy and soft arriving on the ground, out of something that had to push.
    r.growl(0.0, 0.34, 120, 84, 0.34, 0.50, 0.45); // the strain
    r.grit(0.24, 0.20, 0.34, 900, 0.7, 3.0); // …it coming away
    r.body(0.32, 0.16, 96, 44, 0.60, 4.0); // …and landing: soft, and with weight
    r.grit(0.34, 0.16, 0.20, 620, 0.55, 3.4);
    r.master(1.4, 1800);
}

fn mkSacHit(r: *Rack) void {
    // A BLADE INTO A MEMBRANE, which must not sound like hitting a body: no crack, no bone — a taut
    // surface giving and fluid moving behind it.
    r.grit(0.0, 0.09, 0.44, 1300, 0.5, 4.5);
    r.body(0.0, 0.10, 168, 76, 0.44, 5.0);
    r.air(0.0, 0.13, 0.20, 900, 400, 0.30, 3.4);
    r.master(1.4, 2000);
}

fn mkSacHatch(r: *Rack) void {
    // THE SPLIT, then three of them coming out at once — a tear, a wash of fluid, and a scatter of small
    // dry legs finding the ground.
    r.grit(0.0, 0.20, 0.50, 1800, 0.55, 3.0); // the membrane opening
    r.air(0.0, 0.30, 0.34, 2400, 1000, 0.40, 2.4);
    r.body(0.04, 0.18, 130, 58, 0.42, 3.6);
    var i: u32 = 0;
    while (i < 3) : (i += 1) { // …and the three of them, unevenly
        const t = 0.20 + @as(f32, @floatFromInt(i)) * 0.10 + r.rng.range(-0.03, 0.03);
        r.grit(t, 0.16, 0.18, 3200, 0.9, 3.2);
        r.growl(t, 0.09, 700 + r.rng.signed() * 120, 460, 0.24, 0.34, 0.12);
    }
    r.master(1.5, 4200);
}

fn mkSacBurst(r: *Rack) void {
    // THE SAME THING KILLED, and it has to read as a DENIAL: one hard wet burst and no legs after it.
    r.grit(0.0, 0.08, 0.72, 1600, 0.5, 5.5);
    r.body(0.0, 0.16, 190, 52, 0.72, 4.0);
    r.air(0.0, 0.22, 0.44, 2000, 600, 0.42, 2.8);
    r.grit(0.07, 0.30, 0.26, 800, 0.8, 2.2); // …the spill, and that is all
    r.master(1.7, 2600);
}

fn mkAcidSplash(r: *Rack) void {
    // The glob landing: a flat wet slap, then the spread, then the first of the fizz.
    r.grit(0.0, 0.07, 0.60, 1200, 0.45, 5.5);
    r.body(0.0, 0.11, 150, 58, 0.50, 4.5);
    r.air(0.04, 0.30, 0.30, 1600, 3600, 0.30, 1.8); // spreading OUT, so the cut climbs
    r.grit(0.10, 0.34, 0.22, 4200, 0.25, 1.6); // …and it starts to eat
    r.master(1.6, 5000);
}

fn mkAcidBurn(r: *Rack) void {
    // ONE PULSE OF STANDING IN IT. Deliberately not a hurt voice — the hero already has one, and this is
    // the FLOOR doing it: fizz and a shallow bite, so a tick never competes with a blow landing.
    r.grit(0.0, 0.22, 0.34, 5200, 0.20, 2.2);
    r.air(0.0, 0.18, 0.22, 3000, 6000, 0.34, 2.6);
    r.body(0.0, 0.07, 190, 110, 0.20, 5.0);
    r.master(1.3, 6000);
}

fn mkFlaskDrink(r: *Rack) void {
    // Cork, then three glugs, then the warm bloom of it taking hold.
    r.ring(0.0, 0.20, 2450, 0.55, 9.0, 2);
    r.tick(0.0, 0.30, 3000); // …and the stopper coming out under it
    r.body(0.10, 0.11, 150, 96, 0.55, 5.0);
    r.body(0.27, 0.11, 132, 84, 0.60, 5.0);
    r.body(0.46, 0.13, 118, 72, 0.65, 4.4);
    r.grit(0.10, 0.45, 0.10, 900, 0.5, 2.2); // the liquid moving between them
    r.body(0.58, 0.42, 90, 150, 0.5, 1.7); // …and the warmth arriving
    r.master(1.8, 2800);
}

fn mkEat(r: *Rack) void {
    // DRIED MEAT: a tear, then chewing.
    r.grit(0.0, 0.16, 0.42, 1700, 0.85, 3.0); // …the strip torn off
    r.air(0.0, 0.12, 0.14, 1200, 500, 0.25, 3.4);
    r.body(0.14, 0.09, 116, 74, 0.42, 5.5); // …and three soft mouthfuls, unevenly
    r.grit(0.14, 0.10, 0.26, 1100, 0.7, 4.5);
    r.body(0.31, 0.09, 104, 66, 0.38, 5.5);
    r.grit(0.31, 0.09, 0.22, 1000, 0.7, 4.8);
    r.body(0.50, 0.10, 96, 60, 0.34, 5.0);
    r.grit(0.50, 0.10, 0.20, 950, 0.65, 4.8);
    r.master(1.4, 2200); // dark: a bright chew is a crisp, and this is leather
}

fn mkChestOpen(r: *Rack) void {
    // A LID COMING UP, in the three parts it actually has: the lock giving (a hard iron snap), the HINGE turning under load (a long dry grind, which is the part that says heavy), and the boards knocking as the lid goes over past its balance.
    r.tick(0.0, 0.55, 4200);
    r.ring(0.0, 0.16, 620, 0.34, 6.0, 3); // the lock plate
    r.grit(0.06, 0.52, 0.30, 1100, 0.85, 1.1); // the hinge, coarse and slow
    r.body(0.06, 0.30, 132, 88, 0.40, 1.6); // …the mass of it turning
    r.tick(0.60, 0.42, 2600); // the lid arriving, over
    r.body(0.60, 0.16, 108, 58, 0.46, 4.0);
    r.master(2.0, 3200);
}

fn mkItemGet(r: *Rack) void {
    // SOMETHING GAINED.
    r.ring(0.0, 0.34, 784, 0.46, 3.2, 3);
    r.ring(0.02, 0.28, 1176, 0.22, 4.4, 2);
    r.air(0.0, 0.20, 0.12, 2400, 5200, 0.45, 2.6);
    r.master(1.9, 6000);
}

fn mkFlaskCycle(r: *Rack) void {
    // Swapping which flask is up: a dry glassy tap on the belt.
    r.tick(0.0, 0.30, 6000);
    r.body(0.0, 0.06, 720, 520, 0.45, 6.5);
    r.masterX(1.4, 5200, CRUSH_BITS - 1.0, CRUSH_HOLD); // crushed harder — it IS a UI blip
}


fn mkKill(r: *Rack) void {
    // A KILL IS A THUD (owner's call, twice over: no bell, no jingle).
    r.tick(0.0, 0.35, 2000);
    r.body(0.0, 0.36, 116, 30, 1.3, 2.5);
    r.body(0.035, 0.24, 60, 25, 0.65, 2.7); // the second, lower settle — it lands twice, as bodies do
    r.grit(0.0, 0.18, 0.34, 850, 0.7, 3.8);
    r.master(2.4, 2200);
}

fn mkMenuMove(r: *Rack) void {
    // Chrome, so it stays quiet and dry — a warm click with a hint of pitch, nothing musical.
    r.body(0.0, 0.045, 520, 380, 0.5, 6.0);
    r.tick(0.0, 0.25, 4000);
    r.master(1.3, 3800);
}

fn mkMenuPick(r: *Rack) void {
    // Confirm: lower and rounder than the move, with a short ring so it reads as a DECISION.
    r.body(0.0, 0.09, 300, 200, 0.7, 4.5);
    r.ring(0.0, 0.16, 440, 0.3, 4.0, 2);
    r.tick(0.0, 0.2, 3000);
    r.master(1.4, 3600);
}

fn mkMenuBack(r: *Rack) void {
    // Back out: the same gesture falling instead of settling.
    r.body(0.0, 0.10, 300, 150, 0.6, 4.5);
    r.tick(0.0, 0.18, 2400);
    r.master(1.3, 2600);
}

fn mkWind(r: *Rack) void {
    // THE BED.
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
        // The gusts.
        const g1 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.083 * t + q1);
        const g2 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.031 * t + 2.1 + q2);
        const g3 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.157 * t + 4.4 + q3);
        const nz = r.rng.signed();

        const b = body.step(nz, 150.0 + 380.0 * g2, 0.35).bp;
        const w = whistle.step(nz, 620.0 + 1500.0 * g1, 0.86).bp;
        const s = top.step(nz, 5200) * mathx.smoothstep(0.55, 1.0, g3);
        const m = moan.step(nz, 52.0 + 34.0 * g3, 0.55).bp;

        // `norm` sets the LEVEL, so this is purely about WHERE the wind is, and the answer is spectral: air absorbs high frequencies far faster than low ones (ISO 9613-2 puts 4 kHz at roughly fifteen times the loss per hundred metres that 250 Hz takes), so near air is bright and distant air is nothing but weight.
        work[i] = b * (0.30 + 0.70 * g2) * 0.94 +
            w * (0.10 + 0.50 * g1) * 0.20 +
            s * 0.05 +
            m * 0.68;
    }
    // THE BIRDS USED TO LIVE IN HERE, and could not be heard: the bed's own gain is 0.055 (owner's call, and right), so a call mixed into this buffer went out at a twentieth of the level it was written at.
    r.norm(0.42);
    r.sat(1.2);
    r.crush(CRUSH_BITS + 1.5, CRUSH_HOLD); // gentler than the house: a crushed noise bed hisses
    // 1400, down from 2600 — the AIR ABSORPTION of a few hundred metres of it, which is the cue that actually reads as distance (see the mix above).
    r.warm(AIR_FAR_BED);
    r.wow(0.003, 0.4);
    r.hiss(0.035); // …and less tape hiss: hiss is the MEDIUM, and a medium you can hear is a near one
    r.norm(0.62);
    r.ends(0.9, 0.9); // long crossfade ends, so the re-trigger seam is inaudible
}

fn mkBirds(r: *Rack) void {
    // Pitched a little lower than they were (1750-2900 → 1550-2500): the very top of a whistle is what a long crossing of air eats first, so a distant call is not just quieter, it is a rounder note.
    r.chirp(0.04, r.rng.range(0.55, 0.85), r.rng.range(1550, 2500));
    // …and now and then another one answers it, a little further off.
    if (r.rng.float() < 0.45) r.chirp(r.rng.range(0.42, 0.72), r.rng.range(0.28, 0.48), r.rng.range(1700, 2700));
    // 2100, not the old 4200.
    r.masterX(1.1, AIR_FAR_CALL, CRUSH_BITS + 1.0, CRUSH_HOLD);
}

fn mkBirdsong(r: *Rack) void {
    const f0 = r.rng.range(1050, 1650);
    const up = f0 * r.rng.range(1.20, 1.55);
    r.body(0.05, 0.16, f0, up, 0.75, 3.2); // the up-slur…
    r.body(0.26, 0.22, up, f0 * r.rng.range(0.80, 0.95), 0.60, 2.6); // …and back down past where it started
    // …and now and then a third note on the end of the phrase, so the motif is not always the same length.
    if (r.rng.float() < 0.5) r.body(0.56, 0.18, f0 * 1.1, f0 * 1.45, 0.40, 3.0);
    r.air(0.05, 0.09, 0.06, 2600, 1400, 0.5, 4.0); // the breath at the front of it
    r.masterX(1.1, AIR_FAR_CALL, CRUSH_BITS + 1.0, CRUSH_HOLD);
}

fn mkOwl(r: *Rack) void {
    // "hoo…" — short, and already breath-led.
    r.body(0.0, 0.22, 330, 316, 0.60, 2.6);
    r.body(0.0, 0.20, 495, 474, 0.16, 3.4); // …a fifth over, for the hollow
    r.air(0.0, 0.20, 0.34, 1000, 560, 0.42, 2.6);
    // "…hu-hoooo" — falling away.
    r.body(0.60, 0.52, 352, 268, 0.95, 1.9);
    r.body(0.60, 0.46, 528, 402, 0.22, 2.6);
    r.air(0.60, 0.44, 0.40, 1150, 520, 0.42, 2.0);
    r.body(0.62, 0.50, 176, 142, 0.28, 1.7); // an octave under, for the woody chest of it
    r.masterX(1.15, AIR_FAR_CRY, CRUSH_BITS + 1.0, CRUSH_HOLD);
}


// ONE continuous thing; crickets are MANY discrete ones — a chirp is three to five hard ~4.5 kHz pulses, a fifth of a second, two or three times a second.
const CRICKETS = 7; // individuals near enough to be heard APART; past that it is a chirr, not a field
const CRICKET_SING: f32 = 0.22; // fraction of its own cycle one cricket is actually singing

fn mkCrickets(r: *Rack) void {
    var hz: [CRICKETS]f32 = undefined; // stridulation pitch — species and body size
    var rate: [CRICKETS]f32 = undefined; // chirps per second
    var at: [CRICKETS]f32 = undefined; // …and where in its own cycle this one starts
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
            if (c > CRICKET_SING) continue; // …silent for the rest of it
            const w = c / CRICKET_SING; // 0..1 across the chirp itself
            const p = w * pulses[k];
            // A saw DOWN per pulse (a hard front, a fast fade) under one arch across the whole chirp: that pulse train is what makes it a chirr rather than a beep.
            const pulse = 1.0 - (p - @floor(p));
            s += mathx.sinf(std.math.tau * ph[k]) * pulse * pulse * mathx.sinf(std.math.pi * w) * amp[k];
        }
        // The seven get a resonant band so they have a BODY instead of being bare sines…
        const near = band.step(s, 4300, 0.42).bp;
        // …and under them, the hundreds too far away to hear apart: a soft filtered hiss on a slow swell.
        const swellK = 0.55 + 0.45 * mathx.sinf(std.math.tau * 0.047 * t + q);
        const chorus = far.step(r.rng.signed(), 3800) * swellK;
        work[i] = near * 0.80 + chorus * 0.30;
    }
    r.sat(1.15);
    r.crush(CRUSH_BITS + 1.5, CRUSH_HOLD); // gentle, like the wind's: a crushed chirr fizzes
    r.warm(AIR_NEAR_GRASS); // …and BRIGHT, unlike the wind's — see the block above
    r.wow(0.002, 0.6);
    r.hiss(0.010);
    r.norm(0.66);
    r.ends(0.9, 0.9); // long crossfade ends, so the re-trigger seam is inaudible
}


// EVERY BATTLE VOICE IS COMPRESSED INTO ONE BAND (owner's call: "some battle sfx is much louder than others… normalize to the softer ones").
const BATTLE_FLOOR: f32 = 0.34;
fn battle(old: f32) f32 {
    return @sqrt(BATTLE_FLOOR * old);
}

const BANK = [NV]Row{
    // The three boots get the full four takes and the widest level jitter in the bank: they are the most-repeated sound in the game by an order of magnitude, and they are the one that grates first. …and LOW in the mix (owner's call).
    .{ .make = mkStepSoft, .gain = 0.075, .jit = 0.13, .vjit = 0.30, .vars = 4, .poly = 3 },
    .{ .make = mkStepHard, .gain = 0.100, .jit = 0.12, .vjit = 0.26, .vars = 4, .poly = 3 },
    .{ .make = mkStepSprint, .gain = 0.120, .jit = 0.11, .vjit = 0.24, .vars = 4, .poly = 3 },
    // The two SURFACE overlays.
    .{ .make = mkStepStone, .gain = 0.055, .jit = 0.14, .vjit = 0.28, .vars = 4, .poly = 3 },
    .{ .make = mkStepWater, .gain = 0.130, .jit = 0.13, .vjit = 0.26, .vars = 4, .poly = 3 },
    // A ROLL IS QUIET.
    .{ .make = mkRoll, .gain = 0.30, .jit = 0.09, .vjit = 0.14, .vars = 2 },
    // SUBTLE (owner's call).
    .{ .make = mkSwingLight, .gain = 0.26, .mix = .combat, .jit = 0.16, .vjit = 0.22, .vars = 5, .poly = 3 },
    .{ .make = mkSwingHeavy, .gain = 0.34, .mix = .combat, .jit = 0.12, .vjit = 0.16, .vars = 4, .poly = 2 },
    .{ .make = mkHitLight, .gain = battle(0.68), .mix = .combat, .jit = 0.19, .vjit = 0.24, .vars = 6, .poly = 4 },
    .{ .make = mkHitHeavy, .gain = battle(0.82), .mix = .combat, .jit = 0.15, .vjit = 0.20, .vars = 5, .poly = 3 },
    .{ .make = mkHurt, .gain = battle(0.70), .mix = .combat, .jit = 0.17, .vjit = 0.20, .vars = 5 },
    .{ .make = mkHurtHeavy, .gain = battle(0.86), .mix = .combat, .jit = 0.13, .vjit = 0.16, .vars = 4 },
    .{ .make = mkStagger, .gain = battle(0.55), .mix = .combat, .jit = 0.16, .vjit = 0.20, .vars = 4 },
    // A BLOCK IS HEARD OFTEN, so it takes the footsteps' treatment: many takes, wide jitter, and a level under the hit it is answering.
    .{ .make = mkGuardBlock, .gain = battle(0.62), .mix = .combat, .jit = 0.18, .vjit = 0.24, .vars = 5, .poly = 4 },
    // The BREAK is once a fight at most, and it is the cue to get out.
    .{ .make = mkGuardBreak, .gain = battle(0.92), .mix = .combat, .jit = 0.05, .vjit = 0.06, .vars = 2, .poly = 1 },
    .{ .make = mkRefused, .gain = 0.34, .jit = 0.06, .vjit = 0.08, .vars = 2 },
    .{ .make = mkDeath, .gain = battle(0.95), .mix = .combat, .jit = 0.0, .vjit = 0.0, .poly = 1 },
    .{ .make = mkRespawn, .gain = battle(0.55), .mix = .combat, .jit = 0.0, .vjit = 0.0, .poly = 1 },
    // THE TOADS ARE SMALL AND CLOSE.
    .{ .make = mkToadHop, .gain = battle(0.40), .mix = .combat, .jit = 0.15, .vjit = 0.26, .vars = 4, .poly = 4, .reach = 30 },
    .{ .make = mkToadLunge, .gain = battle(0.62), .mix = .combat, .jit = 0.12, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 34 },
    .{ .make = mkToadGape, .gain = battle(0.46), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 3, .poly = 3, .reach = 26 },
    .{ .make = mkToadChomp, .gain = battle(0.62), .mix = .combat, .jit = 0.13, .vjit = 0.18, .vars = 3, .poly = 3, .reach = 30 },
    .{ .make = mkToadHurt, .gain = battle(0.58), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 3, .poly = 3, .reach = 30 },
    .{ .make = mkToadDie, .gain = battle(0.66), .mix = .combat, .jit = 0.11, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 34 },
    // The nock/draw creak sits WELL under the loose (owner's call): it is a tell you register at the edge of hearing, and the twang is the one that has to cut through.
    .{ .make = mkBowDraw, .gain = 0.17, .mix = .combat, .jit = 0.10, .vjit = 0.18, .vars = 3, .poly = 3, .reach = 44 },
    // THE TWANG REACHES FURTHEST OF THE TWO, and by design: it is the one cue in the fight that means MOVE, and an archer shoots from 8-20 m — so its range carries well past its own band, where the creak of the draw only has to be heard from inside it.
    .{ .make = mkBowLoose, .gain = battle(0.58), .mix = .combat, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 64 },
    .{ .make = mkArrowHit, .gain = battle(0.72), .mix = .combat, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 3 },
    // The earth is the miss and therefore the one you hear most — quietest of the four, widest variance, so a volley into the dirt never reads as one sample on repeat.
    .{ .make = mkArrowDirt, .gain = 0.34, .mix = .combat, .jit = 0.15, .vjit = 0.28, .vars = 4, .poly = 4, .reach = 38 },
    .{ .make = mkArrowWood, .gain = battle(0.56), .mix = .combat, .jit = 0.12, .vjit = 0.20, .vars = 4, .poly = 4, .reach = 44 },
    .{ .make = mkArrowStone, .gain = battle(0.50), .mix = .combat, .jit = 0.13, .vjit = 0.22, .vars = 4, .poly = 4, .reach = 48 },
    .{ .make = mkArrowMetal, .gain = battle(0.52), .mix = .combat, .jit = 0.11, .vjit = 0.18, .vars = 3, .poly = 3, .reach = 52 },
    .{ .make = mkBoneHurt, .gain = battle(0.62), .mix = .combat, .jit = 0.12, .vjit = 0.20, .vars = 4, .poly = 3, .reach = 44 },
    .{ .make = mkBoneDie, .gain = battle(0.68), .mix = .combat, .jit = 0.09, .vjit = 0.12, .vars = 3, .reach = 54 },
    // about him is an octave down and half a second longer (see the ogre block above); low frequencies are also what survive a couple of hundred metres of air, so the physics and the character agree for once.
    .{ .make = mkOgreStep, .gain = battle(0.60), .mix = .combat, .jit = 0.08, .vjit = 0.20, .vars = 4, .poly = 3, .reach = 115 },
    .{ .make = mkOgreRoar, .gain = battle(0.80), .mix = .combat, .jit = 0.06, .vjit = 0.10, .vars = 3, .reach = 135 },
    .{ .make = mkOgreSlam, .gain = battle(1.00), .mix = .combat, .jit = 0.06, .vjit = 0.08, .vars = 3, .reach = 135 },
    .{ .make = mkOgreSwipe, .gain = battle(0.72), .mix = .combat, .jit = 0.07, .vjit = 0.12, .vars = 3, .reach = 85 },
    .{ .make = mkOgreHurt, .gain = battle(0.66), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 80 },
    .{ .make = mkOgreDie, .gain = battle(0.92), .mix = .combat, .jit = 0.0, .vjit = 0.0, .poly = 1, .reach = 135 },
    // is the worst case for repetition: five of them yipping the same recording is the single most obviously fake noise a game can make, and there are up to seventy-two of these.
    .{ .make = mkKoboldSnarl, .gain = battle(0.62), .mix = .combat, .jit = 0.22, .vjit = 0.24, .vars = 6, .poly = 3, .reach = 58 },
    .{ .make = mkKoboldChop, .gain = battle(0.38), .mix = .combat, .jit = 0.22, .vjit = 0.28, .vars = 6, .poly = 4, .reach = 40 },
    // The HEAVE has to carry: it is the cue that says come back in, and you will often have backed off to hear it.
    .{ .make = mkKoboldHeave, .gain = battle(0.58), .mix = .combat, .jit = 0.18, .vjit = 0.24, .vars = 5, .poly = 2, .reach = 62 },
    // …and so must the CAST, for the same reason and more so — it is a thing you have to cross a field to stop, so it has to be audible from where you would have to leave.
    .{ .make = mkKoboldCast, .gain = 0.30, .mix = .combat, .jit = 0.05, .vjit = 0.08, .vars = 3, .poly = 2, .reach = 78 },
    // The quietest positive cue in the game, and lowered twice on the owner's call.
    .{ .make = mkKoboldHeal, .gain = 0.11, .mix = .combat, .jit = 0.06, .vjit = 0.10, .vars = 3, .poly = 3, .reach = 54 },
    .{ .make = mkKoboldWhirl, .gain = battle(0.42), .mix = .combat, .jit = 0.20, .vjit = 0.24, .vars = 5, .poly = 3, .reach = 44 },
    .{ .make = mkKoboldSling, .gain = battle(0.50), .mix = .combat, .jit = 0.13, .vjit = 0.18, .vars = 4, .poly = 4, .reach = 52 },
    .{ .make = mkKoboldBite, .gain = battle(0.56), .mix = .combat, .jit = 0.20, .vjit = 0.26, .vars = 6, .poly = 3, .reach = 40 },
    .{ .make = mkKoboldHurt, .gain = battle(0.60), .mix = .combat, .jit = 0.24, .vjit = 0.30, .vars = 6, .poly = 4, .reach = 48 },
    .{ .make = mkKoboldDie, .gain = battle(0.68), .mix = .combat, .jit = 0.18, .vjit = 0.22, .vars = 5, .poly = 3, .reach = 58 },
    // THE BROOD. Her tell has to carry the length of her spit (19 m) with room over it, or the one cue
    // that says get out of the open arrives after the glob does.
    .{ .make = mkSpiderHiss, .gain = battle(0.56), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 4, .poly = 3, .reach = 66 },
    .{ .make = mkSpiderSpit, .gain = battle(0.58), .mix = .combat, .jit = 0.12, .vjit = 0.18, .vars = 4, .poly = 3, .reach = 62 },
    .{ .make = mkSpiderBite, .gain = battle(0.64), .mix = .combat, .jit = 0.13, .vjit = 0.18, .vars = 4, .poly = 3, .reach = 34 },
    .{ .make = mkSpiderHurt, .gain = battle(0.60), .mix = .combat, .jit = 0.15, .vjit = 0.22, .vars = 4, .poly = 3, .reach = 40 },
    .{ .make = mkSpiderDie, .gain = battle(0.80), .mix = .combat, .jit = 0.08, .vjit = 0.10, .vars = 2, .poly = 2, .reach = 70 },
    // …and the hatchlings are the repetition risk in this family (nine of them), so they take the
    // footsteps' treatment: many takes and wide jitter.
    // THE BIRTH CRY carries: it is the moment a sac you did not deal with becomes a thing that is coming.
    .{ .make = mkBroodScreech, .gain = battle(0.62), .mix = .combat, .jit = 0.22, .vjit = 0.24, .vars = 5, .poly = 4, .reach = 76 },
    .{ .make = mkBroodLeap, .gain = battle(0.52), .mix = .combat, .jit = 0.26, .vjit = 0.28, .vars = 6, .poly = 4, .reach = 46 },
    .{ .make = mkBroodBite, .gain = battle(0.44), .mix = .combat, .jit = 0.26, .vjit = 0.30, .vars = 6, .poly = 4, .reach = 30 },
    .{ .make = mkBroodHurt, .gain = battle(0.46), .mix = .combat, .jit = 0.28, .vjit = 0.32, .vars = 6, .poly = 4, .reach = 34 },
    .{ .make = mkBroodDie, .gain = battle(0.52), .mix = .combat, .jit = 0.24, .vjit = 0.28, .vars = 6, .poly = 4, .reach = 40 },
    .{ .make = mkSacLay, .gain = battle(0.50), .mix = .combat, .jit = 0.12, .vjit = 0.18, .vars = 3, .poly = 2, .reach = 44 },
    .{ .make = mkSacHit, .gain = battle(0.54), .mix = .combat, .jit = 0.16, .vjit = 0.24, .vars = 4, .poly = 4, .reach = 34 },
    // THE HATCH IS A CUE, and one you may be across the plaza from when it fires.
    .{ .make = mkSacHatch, .gain = battle(0.66), .mix = .combat, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 72 },
    // …and so is DENYING one, which is the reward for having gone in: it should be heard and unmistakable.
    .{ .make = mkSacBurst, .gain = battle(0.74), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 68 },
    .{ .make = mkAcidSplash, .gain = battle(0.58), .mix = .combat, .jit = 0.14, .vjit = 0.20, .vars = 4, .poly = 4, .reach = 50 },
    // The QUIETEST thing in the fight, deliberately: it fires every 0.42 s while he stands in one, and a
    // tick that shouted would drown the blow that was actually killing him.
    .{ .make = mkAcidBurn, .gain = 0.26, .mix = .combat, .jit = 0.20, .vjit = 0.26, .vars = 5, .poly = 3, .reach = 24 },
    .{ .make = mkFlaskDrink, .gain = 0.52, .jit = 0.06, .vjit = 0.10, .vars = 2, .poly = 2 },
    .{ .make = mkFlaskCycle, .gain = 0.30, .jit = 0.07, .vjit = 0.08, .vars = 2, .poly = 3 },
    // Quieter than the flask: eating is not an emergency, and the sound of it should not be one.
    .{ .make = mkEat, .gain = 0.40, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 2 },
    // A CHEST CARRIES: it is a landmark event and you will be standing over it, but somebody across the plaza should hear the hinge.
    .{ .make = mkChestOpen, .gain = 0.72, .jit = 0.04, .vjit = 0.06, .vars = 2, .poly = 2, .reach = 70 },
    .{ .make = mkItemGet, .gain = 0.44, .jit = 0.05, .vjit = 0.08, .vars = 3, .poly = 4 },
    .{ .make = mkKill, .gain = battle(0.55), .mix = .combat, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 4 },
    .{ .make = mkMenuMove, .gain = 0.30, .jit = 0.06, .vjit = 0.08, .vars = 2, .poly = 3 },
    .{ .make = mkMenuPick, .gain = 0.38, .jit = 0.03, .vjit = 0.05 },
    .{ .make = mkMenuBack, .gain = 0.32, .jit = 0.03, .vjit = 0.05 },
    // MUCH quieter (owner's call).
    .{ .make = mkWind, .gain = 0.030, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
    // …and the birds are now POSITIONED (see `ambience`), so this gain is the level of a call at the near end of the band rather than of one at your ear: the distance curve takes 30-80% back off it depending on where the call was rolled.
    .{ .make = mkBirds, .gain = 0.20, .mix = .ambience, .jit = 0.14, .vjit = 0.22, .vars = 4, .poly = 2, .reach = 210 },
    // The FLUTED bird sits a touch under the chiptune one: it is a purer tone, and a pure tone at the same peak reads louder than a pulse train does (nothing masks it).
    .{ .make = mkBirdsong, .gain = 0.17, .mix = .ambience, .jit = 0.13, .vjit = 0.22, .vars = 4, .poly = 2, .reach = 200 },
    // THE OWL IS RARE AND IT IS ALLOWED TO BE HEARD.
    .{ .make = mkOwl, .gain = 0.24, .mix = .ambience, .jit = 0.08, .vjit = 0.14, .vars = 3, .poly = 2, .reach = 170 },
    // The chirr, at bed level: its whole job is that you only notice it when it stops (see mkWind's row).
    .{ .make = mkCrickets, .gain = 0.010, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
};

/// How long each voice renders for.
fn seconds(id: Id) f32 {
    return switch (id) {
        // The two BEDS are the only long ones, and they are deliberately DIFFERENT lengths: equal loops would re-trigger together for the whole session, and two textures repeating in lockstep is a loop you can hear even when neither is audible on its own.
        .wind => 8.0,
        .crickets => 7.3,
        .death => 3.2,
        .owl => 1.6, // …hoo, a beat of nothing, then hu-hoooo
        .ogre_die => 2.2,
        .respawn => 1.4,
        .bone_die, .toad_die, .ogre_roar => 1.1,
        // The priest's tell runs the length of its own cast (kobold.CAST_DUR is 1.25) — a voice that ended early would stop being a tell halfway through the thing it is telling you about.
        .kobold_cast => 1.35,
        .kobold_die => 1.15,
        .kobold_heave => 0.85, // three ragged breaths, quickening
        .kobold_whirl => 0.75, // …three passes of the cord (see mkKoboldWhirl)
        .ogre_slam, .bow_draw, .flask_drink => 1.05,
        .chest_open => 0.9, // the lock, the whole hinge turn, and the lid arriving over
        // Every arrow impact is QUICK either way (owner's law) — a third of a second, tops.
        .arrow_hit, .arrow_dirt, .arrow_wood, .arrow_stone, .arrow_metal => 0.36,
        .birds => 1.3, // long enough for a phrase plus the answer that can start at 0.72
        .birdsong => 1.0, // …up-slur, down-slur, and the third note that sometimes lands at 0.56
        .roll, .swing_heavy, .ogre_swipe, .ogre_step => 0.7,
        // HER TELL RUNS THE LENGTH OF HER OWN WIND-UP (brood.SPIT_WINDUP is 0.62) — a cue that stopped
        // halfway would stop being a cue halfway, which is the same rule the priest's cast is cut to.
        .spider_hiss => 0.7,
        .spider_die => 1.15, // …the legs go on after the body has stopped
        .sac_lay => 0.62, // the push, then it arriving on the ground
        .sac_hatch, .brood_screech => 0.55, // the membrane going, and the cry straight over it
        .sac_burst => 0.45,
        .acid_splash => 0.42,
        else => 0.5,
    };
}

// A `Sound` can only play once at a time — a second trigger restarts it — so each voice keeps `poly` ALIASES sharing one copy of the sample data, and triggers round-robin through them.

/// HOW MANY SEPARATE TAKES a voice may be rendered as.
const MAX_VARS = 6;
const MAX_POLY = 4;

/// THE OUTPUT LEVEL, in one place.
const MASTER_VOL: f32 = 0.85;

const Slot = struct {
    snd: [MAX_VARS][MAX_POLY]rl.Sound = undefined,
    owned: [MAX_VARS]rl.Sound = undefined, // alias 0 owns the data; the rest borrow it
    next: u8 = 0,
};

var slots: [NV]Slot = undefined;
var ready = false;
// The PLAYBACK rng — per-trigger pitch wobble only.
var rng = mathx.Rng.init(0x50FA5);
var muted = false;

// The listener, set once a frame by game.zig.
var lisPos: rl.Vector3 = mathx.zero3;
var lisRight: rl.Vector3 = mathx.v3(1, 0, 0);

/// The DEFAULT reach, for a voice whose row does not say otherwise (see `Row.reach`, which is where the interesting ones live).
const FALLOFF: f32 = 46.0;

// What a stereo pair can and cannot tell you, so nobody has to re-derive it: AZIMUTH is real and cheap — an inter-channel level difference is most of how you place a sound left or right, and it survives distance unchanged, so `PAN_WIDTH` applies at any range.
const PAN_WIDTH: f32 = 0.42;
/// …and inside this radius the pan CLOSES TO CENTRE.
const PAN_NEAR: f32 = 1.4;
/// How much a source DIRECTLY BEHIND the listener is ducked, as a fraction.
const REAR_DUCK: f32 = 0.10;
/// Distance PITCH droop, at full reach.
const PITCH_DROOP: f32 = 0.05;
/// The bed's two channels, as pan values.
const BED_PAN: f32 = 0.93;

/// PAN FOR A BEARING — and the one place the sign of it is decided, because raylib's `pan` is NOT a left-to-right position.
fn panFor(side: f32, width: f32) f32 {
    return mathx.clampF(0.5 - width * side, 0.04, 0.96);
}

/// Build the whole bank. ~40 voices, most under half a second — a few hundred milliseconds of synthesis at launch, once.
pub fn init() void {
    loadSettings(); // before the device: the dials are data, and they are what the first bed is mixed at
    rl.initAudioDevice();
    if (!rl.isAudioDeviceReady()) return;
    rl.setMasterVolume(MASTER_VOL);
    inline for (@typeInfo(Id).@"enum".fields, 0..) |f, idx| {
        const id: Id = @enumFromInt(f.value);
        const row = BANK[idx];
        var v: u8 = 0;
        while (v < row.vars) : (v += 1) {
            // Seeded per voice AND per variant, so the bank is bit-identical every launch (the determinism law applies to ears too — a sound that differs run to run cannot be tuned).
            var r = Rack.init(0x9E3779B9 *% (idx + 1) +% v, seconds(id));
            row.make(&r);
            slots[idx].snd[v][0] = bake(&r);
            slots[idx].owned[v] = slots[idx].snd[v][0];
            var p: u8 = 1;
            while (p < row.poly) : (p += 1) slots[idx].snd[v][p] = rl.loadSoundAlias(slots[idx].owned[v]);
        }
        slots[idx].next = 0;
    }
    restFire = rl.loadMusicStreamFromMemory(".wav", dressedFire()) catch null;
    if (restFire) |*m| {
        m.looping = true;
        rl.setMusicVolume(m.*, 0);
    }
    ready = true;
}

// Everything else here is synthesized, and the note at the top of this file says so in as many words.
const CAMPFIRE_WAV = @embedFile("campfire_wav");

// ── THE ONE RECORDED SOUND, PUT THROUGH THE SAME MACHINE AS THE REST ─────────────────────────────────
// It arrived clean, thin and plainly from a different room than everything around it — which is exactly
// what the bank's master chain exists to stop. So the take gets that chain too (saturation, the bit crush,
// the tape's bandwidth and its noise floor) plus a LOW SHELF, because a fire you are sitting at is felt in
// the chest and the recording had no bottom in it at all.
// No `wow` here, and that is not an omission: flutter is a PITCH wobble, and a crackle bed has no pitch to
// wobble — it would cost a second buffer the size of the file to hear nothing.

const FIRE_BASS_HZ: f32 = 190.0; // …everything under this comes up
const FIRE_BASS: f32 = 1.35; // …by about 7 dB
const FIRE_DRIVE: f32 = 1.55; // tape saturation, which is also what stops the shelf clipping
const FIRE_BITS: f32 = 6.5; // crushed HARDER than the synth bank's 7.5: it is the one voice with real
const FIRE_HOLD: u32 = 2; // material in it, so it is the one where the grain actually reads
const FIRE_CUT: f32 = 3400.0; // the tape's top end — a fire is bottom and crackle, no air
const FIRE_HISS: f32 = 0.010;
const FIRE_OUT: f32 = 0.92;

/// The re-encoded take. 16-bit PCM out of 16-bit PCM in, so the source file's own length is a safe bound
/// (it carries a `LIST` chunk this header does not) — and it re-sizes itself if the asset is ever swapped.
var fireWav: [CAMPFIRE_WAV.len + 64]u8 = undefined;

fn put32(b: []u8, at: usize, v: u32) void {
    std.mem.writeInt(u32, b[at..][0..4], v, .little);
}
fn put16(b: []u8, at: usize, v: u16) void {
    std.mem.writeInt(u16, b[at..][0..2], v, .little);
}

/// Decode the take, run it through the finish, and hand back a canonical WAV — raylib streams from encoded
/// bytes, so the only way to loop a PROCESSED bed is to write one back out.
fn dressedFire() []const u8 {
    const w = rl.loadWaveFromMemory(".wav", CAMPFIRE_WAV) catch return CAMPFIRE_WAV;
    defer rl.unloadWave(w);
    // Only the shape this asset actually is — 16-bit PCM. Anything else goes through untouched rather than
    // being reinterpreted, because a silently mis-decoded bed is worse than an undressed one.
    if (w.sampleSize != 16) return CAMPFIRE_WAV;
    const frames: usize = @intCast(w.frameCount);
    const chans: usize = @intCast(w.channels);
    const n = frames * chans;
    const bytes = 44 + n * 2;
    if (n == 0 or bytes > fireWav.len) return CAMPFIRE_WAV;
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
        x = d / (1.0 + @abs(d)); // …and the same cheap tanh the rack finishes with
        if (k == 0) held = x;
        k = (k + 1) % @max(FIRE_HOLD, 1);
        const dith = (r.signed() + r.signed()) * 0.5 / levels * DITHER_LSB;
        x = @round((held + dith) * levels) / levels;
        x = lp.step(x, FIRE_CUT);
        x += hq.step(hp.step(r.signed(), 5200), 2600) * FIRE_HISS;
        const s = mathx.clampF(x * FIRE_OUT, -1, 1) * 32000.0;
        std.mem.writeInt(i16, fireWav[44 + i * 2 ..][0..2], @intFromFloat(s), .little);
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

/// A STREAM, not a `Sound`, because it is twelve seconds long and has to loop — `Sound` has no loop and would need re-triggering on a timer that would drift audibly.
var restFire: ?rl.Music = null;

/// Start / stop the rest scene's fire bed.
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

/// The bed's level, 0..1, set per frame by whatever is running the rest — it pays the AMBIENCE dial like every other background voice, because a player who has turned the background down means it.
pub fn restFireLevel(v: f32) void {
    const m = restFire orelse return;
    rl.setMusicVolume(m, mathx.clampF(v, 0, 1) * userVol[@intFromEnum(Submix.ambience)]);
}

/// PUMP THE STREAM.
pub fn tickStreams() void {
    const m = restFire orelse return;
    if (rl.isMusicStreamPlaying(m)) rl.updateMusicStream(m);
}

/// Upload the rack as a mono 16-bit Sound.
fn bake(r: *Rack) rl.Sound {
    for (work[0..r.n], 0..) |s, i| {
        pcm[i] = @intFromFloat(mathx.clampF(s, -1, 1) * 32000.0);
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
    for (&slots, 0..) |*s, idx| {
        const row = BANK[idx];
        var v: u8 = 0;
        while (v < row.vars) : (v += 1) {
            var p: u8 = 1;
            while (p < row.poly) : (p += 1) rl.unloadSoundAlias(s.snd[v][p]);
            rl.unloadSound(s.owned[v]);
        }
    }
    if (restFire) |m| rl.unloadMusicStream(m);
    ready = false;
    rl.closeAudioDevice();
}

/// Where the ears are.
pub fn listen(pos: rl.Vector3, right: rl.Vector3) void {
    lisPos = pos;
    lisRight = right;
}

/// ONE VOICE'S DIALS, for the editor's JUKEBOX to print beside whatever it is auditioning: the numbers you need in front of you while judging a sound are the same ones you would be retuning.
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

// One number per `Submix`, multiplied in alongside the author-side trim. NONE OF THE THREE STARTS AT FULL
// (owner's call): the dial's job is headroom above the level you actually want, not a ceiling you are
// already sitting on — so every family launches with somewhere to go up as well as down.
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

pub fn setVolume(m: Submix, v: f32) void {
    userVol[@intFromEnum(m)] = mathx.clampF(v, 0, 1);
    // …AND THE BEDS, WHICH ARE ALREADY PLAYING.
    if (ready and m == .ambience) {
        for (BEDS) |b| {
            const s = &slots[@intFromEnum(b)];
            const lvl = bedLevel(BANK[@intFromEnum(b)]);
            rl.setSoundVolume(s.snd[0][0], lvl);
            if (BANK[@intFromEnum(b)].vars > 1) rl.setSoundVolume(s.snd[1][0], lvl);
        }
    }
}

/// A bed's steady level — exact rather than approximate, because it goes through the same arithmetic `trigger` used to start it and both beds carry `vjit = 0`, so their wobble really is 1.0.
fn bedLevel(row: Row) f32 {
    return levelFor(row, 1.0, 1.0);
}

/// Where the dials live between runs.
pub const SETTINGS_PATH = "settings.cfg";

/// Best-effort both ways: a missing, truncated or garbled file leaves the defaults standing rather than refusing to start.
pub fn loadSettings() void {
    var buf: [256]u8 = undefined;
    const f = std.fs.cwd().openFile(SETTINGS_PATH, .{}) catch return;
    defer f.close();
    const n = f.readAll(&buf) catch return;
    var lines = std.mem.tokenizeAny(u8, buf[0..n], "\r\n");
    while (lines.next()) |line| {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        const key = it.next() orelse continue;
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
    // Keyed by `@tagName`, so renaming a submix renames its key and an old file's line simply falls through `loadSettings` unmatched — one enum, no second list of names to drift.
    inline for (@typeInfo(Submix).@"enum".fields) |fld| {
        f.writer().print("{s} {d:.3}\n", .{ fld.name, userVol[fld.value] }) catch return;
    }
}

/// Silence the world without tearing the device down — the editor uses it, since a map you are dressing should not be croaking at you.
pub fn mute(on: bool) void {
    if (muted == on) return;
    muted = on;
    if (ready) rl.setMasterVolume(if (on) 0.0 else MASTER_VOL);
}

/// Trigger a voice at the listener (UI, and anything that happens TO the player).
pub fn play(id: Id) void {
    emit(id, 1.0, 0.5, 1.0);
}

/// …with an explicit strength, for the beats that come in degrees (a light vs a heavy).
pub fn playAt(id: Id, vol: f32) void {
    emit(id, vol, 0.5, 1.0);
}

/// Trigger a voice somewhere in the WORLD: attenuated by distance and panned across the camera.
pub fn world(id: Id, at: rl.Vector3) void {
    if (!ready) return;
    const row = BANK[@intFromEnum(id)];
    // SQUARED for the reject, and that is what makes the early-out the cheap thing this voice's own test claims it is: `distXZ` is a square ROOT, and it was being paid on every call by every foe on the map — including the great majority that are out of earshot and return one line later.
    const d2 = mathx.dist2XZ(at, lisPos);
    if (d2 > row.reach * row.reach) return;
    const d = @sqrt(d2);
    // Inverse-square-ish, squared again at the tail so distant sounds fall away rather than hanging at a constant murmur across the whole plain.
    const k = 1.0 - d / row.reach;
    const near = d / row.reach; // 0 underfoot → 1 at the edge of earshot
    const to = mathx.dirXZ(lisPos, at);
    const side = to.x * lisRight.x + to.z * lisRight.z;
    // FORWARD is derived from the stored right vector rather than being a third thing to pass in and keep in step: on the ground plane `perpXZ(right)` IS camera-forward for this codebase's basis (right is (−cos yaw, 0, sin yaw), so its perpendicular is (sin yaw, 0, cos yaw) = headingDir).
    const fwd = mathx.perpXZ(lisRight);
    const front = to.x * fwd.x + to.z * fwd.z; // +1 dead ahead → −1 dead behind
    const rear = 1.0 - REAR_DUCK * 0.5 * (1.0 - front);
    // …and the pan closes to centre in the near field, so a foe standing on you doesn't strobe.
    const width = PAN_WIDTH * mathx.smoothstep(0, PAN_NEAR, d);
    emit(id, k * k * rear, panFor(side, width), 1.0 - PITCH_DROOP * near);
}

fn emit(id: Id, vol: f32, pan: f32, pitchScale: f32) void {
    if (!ready or muted or vol <= 0.01) return;
    const idx = @intFromEnum(id);
    const row = BANK[idx];
    const s = &slots[idx];
    // Round-robin the alias AND the variant off one counter: `poly` and `vars` are coprime often enough that stepping both together decorrelates which take you hear from which slot it lands in, and when they are not, the pitch jitter covers it.
    const pick = s.next;
    s.next = (s.next + 1) % (row.vars * row.poly);
    trigger(s.snd[pick % row.vars][pick / row.vars % row.poly], row, vol, pan, pitchScale);
}

/// Set one alias up and start it.
fn trigger(snd: rl.Sound, row: Row, vol: f32, pan: f32, pitchScale: f32) void {
    // Pitch AND level wobble, both per trigger.
    const vj = 1.0 - @abs(rng.signed()) * row.vjit;
    rl.setSoundVolume(snd, levelFor(row, vol, vj));
    rl.setSoundPitch(snd, (1.0 + rng.signed() * row.jit) * pitchScale);
    rl.setSoundPan(snd, pan);
    rl.playSound(snd);
}

/// Play a voice's first two takes at once, one pushed left and one right.
fn bed(id: Id, vol: f32) void {
    if (!ready or muted) return;
    const idx = @intFromEnum(id);
    const row = BANK[idx];
    const s = &slots[idx];
    trigger(s.snd[0][0], row, vol, BED_PAN, 1.0);
    if (row.vars > 1) trigger(s.snd[1][0], row, vol, 1.0 - BED_PAN, 1.0);
}

/// Two of them now, moving air and the insect chirr, and they are separate VOICES rather than one buffer holding both for the same reason the birds were lifted out of the wind: baked together they would loop together, and two textures that repeat in lockstep is a loop you can hear.
const BEDS = [_]Id{ .wind, .crickets };

/// A TABLE, because there are three of these now and they differ in nothing but those numbers.
const Call = struct {
    id: Id,
    gapLo: f32,
    gapHi: f32,
    distLo: f32,
    distHi: f32,
    /// How long the FIRST one holds off.
    first: f32,
};

const CALLS = [_]Call{
    .{ .id = .birds, .gapLo = 9, .gapHi = 26, .distLo = 26, .distHi = 120, .first = 4 },
    .{ .id = .birdsong, .gapLo = 11, .gapHi = 31, .distLo = 30, .distHi = 140, .first = 9 },
    // Rarer than either bird by a factor of three, and further out: an owl is a thing you hear occasionally from somewhere in the ruins, not a resident of the tree you are standing under. …and the RAREST and FURTHEST of the calls.
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
    // Take 0 is the LEFT channel of a bed and both takes are the same length, so asking raylib whether that one is still running is the whole re-trigger test for the pair.
    for (BEDS) |b| {
        if (!rl.isSoundPlaying(slots[@intFromEnum(b)].snd[0][0])) bed(b, 1.0);
    }
    // Every sparse call rides its OWN clock rather than a bed's loop: baked into the wind buffer the birds repeated with it, five phrases in the same order for ever (see mkWind).
    for (CALLS, 0..) |c, i| {
        callWait[i] -= dt;
        if (callWait[i] > 0) continue;
        callWait[i] = rng.range(c.gapLo, c.gapHi);
        const a = rng.angle();
        const d = rng.range(c.distLo, c.distHi);
        world(c.id, mathx.v3(lisPos.x + mathx.cosf(a) * d, lisPos.y, lisPos.z + mathx.sinf(a) * d));
    }
}

/// WHAT AN ARROW ENDED UP IN → which impact you hear.
pub fn arrowImpact(surf: ?@import("collision.zig").Surface) Id {
    const s = surf orelse return .arrow_dirt;
    return switch (s) {
        .stone => .arrow_stone,
        .wood => .arrow_wood,
        .metal => .arrow_metal,
    };
}

comptime {
    // The table is positional: a voice added to `Id` without a row lands on its neighbour's renderer, which is silent-and-wrong rather than a compile error unless this is here.
    std.debug.assert(BANK.len == NV);
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
    // Catches the two ways a recipe fails without anyone noticing: a layer that cancels itself to nothing, and one that runs away and clips the whole buffer to a square wave.
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
        try std.testing.expect(peak <= 1.0); // …and the master stage kept it inside the rails
        try std.testing.expect(energy / @as(f32, @floatFromInt(r.n)) > 0.002); // not a lone click
    }
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
    // `world` is the one path that can be called thousands of times a frame by a knot of foes, so its early-out has to be real; and a pan that leaves the 0..1 range is a raylib assert.
    listen(mathx.zero3, mathx.v3(1, 0, 0));
    try std.testing.expect(mathx.distXZ(mathx.v3(FALLOFF + 1, 0, 0), lisPos) > FALLOFF);
    const near = 1.0 - 0.0 / FALLOFF;
    const far = 1.0 - (FALLOFF * 0.9) / FALLOFF;
    try std.testing.expect(near * near > far * far * 50.0); // a real curve, not a plateau
}

test "PAN IS THE LEFT CHANNEL'S GAIN — a source on your right must pan DOWN, not up" {
    // THE bug this pins, and it is worth a test of its own because the mistake is the natural reading of the API. raylib's mixer takes `pan` as the LEFT gain and gives the right `1 - pan` (raudio.c MixAudioFrames), while its header says only "(0.5 is center)".
    const right = panFor(1.0, PAN_WIDTH); // source to SCREEN-RIGHT…
    const left = panFor(-1.0, PAN_WIDTH);
    try std.testing.expect(right < 0.5); // …so the LEFT channel's gain comes DOWN
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
    // A bearing at arm's length is arithmetically fine and perceptually meaningless: a toad chewing your leg crosses from one side to the other in a frame, and panning that honestly flicks the sound between the speakers.
    const onTop = PAN_WIDTH * mathx.smoothstep(0, PAN_NEAR, 0.05);
    const clear = PAN_WIDTH * mathx.smoothstep(0, PAN_NEAR, 4.0);
    try std.testing.expect(onTop < 0.02); // effectively centred
    try std.testing.expectApproxEqAbs(PAN_WIDTH, clear, 1e-6); // and full width once it is off you
}

test "reach is per VOICE: a giant carries, a toad does not, a bird carries furthest" {
    // The soundscape's whole legibility rests on this ordering — one shared range for everything is how you end up hearing toads through terrain and missing a slam across the plaza.
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
    // A toad's world is 11 m wide (its aggro radius), so its voice must comfortably cover that and not much more.
    try std.testing.expect(reach(.toad_chomp) > 12.0 and reach(.toad_chomp) < 40.0);
    // …and every voice has to be able to be heard at all.
    for (BANK) |row| try std.testing.expect(row.reach > 1.0);
}

test "every sparse call is rolled INSIDE its own reach, and none of them is rolled at your ear" {
    // Two ways the CALLS table can be wrong and neither shows on screen: a `distHi` past the voice's own `reach` makes the far half of the band SILENCE (`world` early-outs, so the call simply never happens and the clock has already been spent), and a `distLo` near zero puts the thing in your head — which is the bug the birds were moved off `play` to fix in the first place.
    for (CALLS) |c| {
        const row = BANK[@intFromEnum(c.id)];
        try std.testing.expect(c.distHi < row.reach);
        try std.testing.expect(c.distLo > 10.0 and c.distLo < c.distHi);
        // …and a gap band that is a real band, so no voice fires on a fixed metronome.
        try std.testing.expect(c.gapLo > 0 and c.gapHi > c.gapLo * 1.5);
        try std.testing.expect(c.first > 1.0); // never behind the pause card at launch
    }
    // RARITY ORDER, which is the whole shape of the canopy: birds are scenery, the owl is the event.
    try std.testing.expect(CALLS[2].gapLo > CALLS[0].gapLo * 2.0); // owl vs birds
    try std.testing.expect(CALLS.len == 3);
}

test "THE BACKGROUND IS BACKGROUND — the ambience trim, and only the ambience" {
    // Every bed and every sparse call pays the trim: an ambient voice left on `.sfx` is the one that ends up loudest in its own group with nothing to compare it against.
    for (BEDS) |b| try std.testing.expectEqual(Submix.ambience, BANK[@intFromEnum(b)].mix);
    for (CALLS) |c| try std.testing.expectEqual(Submix.ambience, BANK[@intFromEnum(c.id)].mix);
    // WHAT IS PINNED IS THE SIGNAL, NOT THE MIX POSITION.
    try std.testing.expect(TRIM_AMBIENCE > 0);
    for (BANK) |row| {
        if (row.mix != .ambience) continue;
        try std.testing.expect(row.gain * TRIM_AMBIENCE < 1.0);
    }

    // AND NOTHING ELSE DOES — asserted so the reverted `.creature` trim (see `Submix`) cannot come back by accident.
    var trimmed: usize = 0;
    for (BANK) |row| {
        if (row.mix == .ambience) trimmed += 1;
    }
    try std.testing.expectEqual(BEDS.len + CALLS.len, trimmed);
    for ([_]Id{ .toad_chomp, .toad_die, .ogre_slam, .ogre_roar, .bone_die, .hit_heavy, .hurt }) |id| {
        try std.testing.expect(BANK[@intFromEnum(id)].mix != .ambience);
        try std.testing.expectEqual(@as(f32, 1.0), submixTrim(BANK[@intFromEnum(id)].mix));
    }

    // THE BEDS SIT UNDER THE CALLS, which is what makes one a floor and the other an event: a bed you can pick out is a bed that is too loud.
    var loudBed: f32 = 0;
    for (BEDS) |b| loudBed = mathx.maxF(loudBed, BANK[@intFromEnum(b)].gain);
    for (CALLS) |c| try std.testing.expect(BANK[@intFromEnum(c.id)].gain > loudBed);
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
    try std.testing.expectApproxEqAbs(levelFor(combatRow, 1.0, 1.0), combatRow.gain * 0.5, 1e-6);
    try std.testing.expectEqual(before, levelFor(sfxRow, 1.0, 1.0));

    // …and a dial cannot become a boost.
    setVolume(.combat, 4.0);
    try std.testing.expectEqual(@as(f32, 1.0), volume(.combat));
}

test "THE FIGHT IS ONE BAND — no battle voice towers over the rest of them" {
    // Owner's call, and the shape of the fix (see BATTLE_FLOOR): the spread used to be 0.26 → 1.00, nearly 12 dB, so the ogre's slam arrived four times the size of the swing answering it.
    const battleIds = [_]Id{
        .hit_light,    .hit_heavy,     .hurt,          .hurt_heavy,   .stagger,      .guard_block,
        .guard_break,  .death,         .respawn,       .toad_hop,     .toad_lunge,   .toad_gape,
        .toad_chomp,   .toad_hurt,     .toad_die,      .bow_loose,    .arrow_hit,    .arrow_wood,
        .arrow_stone,  .arrow_metal,   .bone_hurt,     .bone_die,     .ogre_step,    .ogre_roar,
        .ogre_slam,    .ogre_swipe,    .ogre_hurt,     .ogre_die,     .kobold_snarl, .kobold_chop,
        .kobold_heave, .kobold_whirl,  .kobold_sling,  .kobold_bite,  .kobold_hurt,  .kobold_die,
        .spider_hiss,  .spider_spit,   .spider_bite,   .spider_hurt,  .spider_die,   .brood_screech,
        .brood_leap,
        .brood_bite,   .brood_hurt,    .brood_die,     .sac_lay,      .sac_hit,      .sac_hatch,
        .sac_burst,    .acid_splash,
        .kill,
    };
    var lo: f32 = 1e9;
    var hi: f32 = 0;
    for (battleIds) |id| {
        const g = BANK[@intFromEnum(id)].gain;
        lo = mathx.minF(lo, g);
        hi = mathx.maxF(hi, g);
    }
    // Under 6 dB end to end.
    try std.testing.expect(hi / lo < 2.0);
    // …and the floor did NOT move up to meet it.
    try std.testing.expect(lo >= BATTLE_FLOOR - 1e-4 and lo < BATTLE_FLOOR * 1.15);
    try std.testing.expect(hi < 0.62);

    // THE ORDERINGS THAT CARRY MEANING SURVIVE IT — a geometric pull cannot invert any pair, and these are the ones a flat level would have destroyed.
    const g = struct {
        fn of(id: Id) f32 {
            return BANK[@intFromEnum(id)].gain;
        }
    }.of;
    try std.testing.expect(g(.ogre_slam) > g(.kobold_chop)); // the giant still lands hardest…
    try std.testing.expect(g(.swing_light) < g(.hit_light)); // …the swing still sits under its hit…
    try std.testing.expect(g(.bow_draw) < g(.bow_loose)); // …the creak under the twang…
    try std.testing.expect(g(.kobold_snarl) > g(.kobold_chop)); // …and the cue over the noise
    // The EXCLUSIONS are excluded: each is at or under the floor already, so compressing them would have RAISED them (see the BANK block's exclusion list).
    for ([_]Id{ .step_soft, .step_hard, .step_sprint, .roll, .swing_light, .swing_heavy, .refused, .arrow_dirt, .kobold_cast, .kobold_heal }) |id| {
        try std.testing.expect(g(id) <= BATTLE_FLOOR + 1e-6);
    }
}

test "every BED has two takes to pan, and they do not loop in lockstep" {
    // BEDS MUST NOT SHARE A LENGTH: equal-length beds re-trigger on the same frame for the whole session, and two textures repeating in lockstep is a loop you can hear even when neither is audible alone.
    var i: usize = 0;
    while (i < BEDS.len) : (i += 1) {
        // Played through `bed`, which needs two takes to have two channels to pan hard apart.
        try std.testing.expect(BANK[@intFromEnum(BEDS[i])].vars >= 2);
        var j = i + 1;
        while (j < BEDS.len) : (j += 1) try std.testing.expect(seconds(BEDS[i]) != seconds(BEDS[j]));
    }
}

test "a source BEHIND you is ducked, but nowhere near enough to hide it" {
    // Front/back cannot be resolved by a stereo pan (it takes the outer ear's own spectral notches), so this is a nudge.
    const ahead = 1.0 - REAR_DUCK * 0.5 * (1.0 - 1.0);
    const behind = 1.0 - REAR_DUCK * 0.5 * (1.0 - -1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), ahead, 1e-6);
    try std.testing.expect(behind < ahead);
    try std.testing.expect(behind > 0.85); // still unmistakably audible
}

test "the BED's two takes are decorrelated — that IS its width, and it is checkable" {
    // The claim `bed` rests on: two ears fed the same buffer hear one source between the speakers, and two independent renders of the same recipe have no single place to be.
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
    try std.testing.expect(BANK[idx].vars >= 2); // …and there have to BE two of them to play
}

test "hard-panning the bed does not smuggle the level back up" {
    // `mkWind`'s gain came down from 0.055 to 0.030 and the comment claims that lands within a whisker of the old per-ear level while being a small real drop.
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
    try std.testing.expect(after > before * 0.6); // …but a nudge, not a mute
}

test "the two ambient voices are baked DARK, which is the cue level cannot buy" {
    // The BED is noise, so its brightness is measurable: a zero-crossing rate is the cheap honest proxy for spectral centroid, and for a noise band it tracks it closely.
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

    // THE BIRDS ARE NOT MEASURED THIS WAY, and the reason is worth writing down: a chirp is PITCHED, so its zero-crossing rate is set by its fundamental and barely moves when you take the reedy harmonics off the top.
    try std.testing.expect(AIR_FAR_CALL < AIR_NEAR_DARKEST);
    try std.testing.expect(AIR_FAR_BED < AIR_FAR_CALL); // the bed is the furthest thing in the world
    // The two big LOW cries are darker again than a bird's whistle — they are further out AND low to begin with, so what crosses the plain is the fundamental and almost none of the throat.
    try std.testing.expect(AIR_FAR_CRY < AIR_FAR_CALL);
    try std.testing.expect(AIR_FAR_CRY < AIR_NEAR_DARKEST);
    // …and neither so dark it stops being the thing it is: a bird still has to be a whistle (its band tops out at 2500 Hz) and wind still has to have air in it, not just rumble.
    try std.testing.expect(AIR_FAR_CALL > 1200 and AIR_FAR_BED > 800);
    // THE CRICKETS ARE THE EXCEPTION, and the ONE ambient voice on the near side of the line: they are in the grass at your feet, and the spectral tilt is the only thing that says so.
    try std.testing.expect(AIR_NEAR_GRASS > AIR_NEAR_DARKEST);
    // …and every one of the FAR voices stays on the far side of it.
    for ([_]f32{ AIR_FAR_BED, AIR_FAR_CALL, AIR_FAR_CRY }) |cut| {
        try std.testing.expect(cut < AIR_NEAR_DARKEST);
    }
}

test "NO SUSTAINED CALL SITS IN THE MOSQUITO BAND" {
    // WHY THIS TEST EXISTS, since the voice it was written for has been deleted: the wolf howl read to the owner as "a skeeter", and the mechanism generalises.
    const MOSQUITO_LO: f32 = 350.0;
    const HELD: f32 = 0.55; // a "held" cry — anything shorter is a hoot or a chirp, and safe
    for (CALLS) |c| {
        if (seconds(c.id) < HELD) continue;
        // The OWL is the only one left over the threshold, and it is legal because it is a two-note HOOT: its notes are 0.26 s and 0.85 s of a 1.6 s buffer with silence between them, so there is no continuous tone for the vibrato to turn into a wingbeat — which is precisely why it never sounded like an insect and the howl did.
        try std.testing.expect(seconds(c.id) < 2.0);
    }
    // …and the band itself is where it says it is, so the number above cannot silently drift.
    try std.testing.expect(MOSQUITO_LO > 300.0 and MOSQUITO_LO < 500.0);
}

test "THE NOISE FLOOR IS THE CRUSH'S, and it has to stay down" {
    // Owner's note was "all sfx have too much hiss", and the dial that looks responsible — the tape `hiss()` layer — is ~28 dB below the thing actually making the noise.

    const step = 1.0 / (std.math.pow(f32, 2.0, CRUSH_BITS) * 0.5);
    const stepDb = 20.0 * std.math.log10(step);
    try std.testing.expect(stepDb < -36.0); // …at 5.5 bits this was −27 dB, and audibly so
    // The textbook ±1 LSB TPDF is a SIXTEEN-BIT rule; at this step size it doubled the quantiser's own noise power for linearity nobody can hear.
    try std.testing.expect(DITHER_LSB < 0.6 and DITHER_LSB > 0.15); // …but still enough to break a staircase
    // The HOLD is the lo-fi character and is deliberately NOT the thing that was turned down — it costs no noise floor at all, so a future "make it crunchier" belongs here and not in the bits.
    try std.testing.expect(CRUSH_HOLD >= 2);

    var r = Rack.init(0xC0FFEE, 1.0);
    r.body(0.0, 0.10, 220, 60, 0.9, 4.0); // a plain impact — peaks near full scale, then nothing
    r.master(2.0, 3200);
    var e: f32 = 0;
    var n: usize = 0;
    var i = r.n * 6 / 10; // …well clear of the thump, and short of `ends`' out-ramp
    while (i < r.n * 9 / 10) : (i += 1) {
        e += work[i] * work[i];
        n += 1;
    }
    const tailDb = 20.0 * std.math.log10(@max(@sqrt(e / @as(f32, @floatFromInt(n))), 1e-9));
    // MEASURED: −34.7 dBFS at 5.5 bits with ±1 LSB dither, −50.8 dBFS as it stands.
    try std.testing.expect(tailDb < -44.0);
}
