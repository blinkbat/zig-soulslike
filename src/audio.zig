const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

// ── AUDIO ── every sound in the game, SYNTHESIZED AT LAUNCH. No .wav files anywhere: the same argument
// as the meshes, and WABI-SABI applies to ears too — a footstep sample played twice is the most obviously
// fake sound a game makes, so the variation is authored in with a seeded Rng.
//
// THE HOUSE SOUND is warm analogue tape: low and fat, everything through a saturation → lowpass → wow →
// hiss chain, almost every gesture noise or a naive oscillator dragged through a SWEEPING RESONANT
// FILTER. That sweep is the character — it is what makes a whoosh travel and a hit land in a body.
//
// 22 kHz IS THE COLOUR, not a compromise: the 11 kHz ceiling rolls the fizz off noise, band-limits the
// oscillators so they stop buzzing, and puts the sound in the same era as the retro picture.
//
// One `BANK` row per voice carries its renderer AND its playback feel, so a voice is ONE ROW — the rule
// `props.INFO` follows, for the same reason.

pub const SR: usize = 22050;
const SRF: f32 = @floatFromInt(SR);
const MAX_N: usize = 9 * SR; // the longest a single voice may be (the wind bed is the only long one)

// ── the scratch rack ────────────────────────────────────────────────────────────────────
// Rendering is allocation-free like everything else here: one working buffer, one delay buffer for
// the wow, one PCM staging buffer, all BSS and all reused voice after voice. They are only USED
// during `init` — nothing here is touched again once the bank is on the audio device.
//
// MEASURED, and deliberately left: at MAX_N these are ~794 KB + ~794 KB + ~397 KB ≈ 2 MB of BSS
// held for the life of the process to serve a few hundred milliseconds of work at launch. That is
// the trade the whole file makes (no allocator, no failure path, no teardown), and 2 MB next to
// Env's ~450 KB of flat arrays and the prop meshes is not worth an allocator to reclaim. Function
// locals are NOT the alternative — a 794 KB stack frame overflows the main thread's stack.
var work: [MAX_N]f32 = undefined;
var tape: [MAX_N]f32 = undefined;
var pcm: [MAX_N]i16 = undefined;

/// A resonant state-variable filter (Chamberlin), the workhorse of the whole bank. Its cutoff is
/// swept per SAMPLE by every caller, because a filter at a fixed cutoff is an EQ and a filter that
/// MOVES is an instrument — that motion is what the brief's "filters that extend" means and it is
/// what separates a whoosh from a hiss.
const Svf = struct {
    lp: f32 = 0,
    bp: f32 = 0,

    /// One sample. `cut` in Hz, `res` 0..1 (1 = on the edge of self-oscillating). Returns all three
    /// outputs; callers pick the band they want.
    fn step(s: *Svf, x: f32, cut: f32, res: f32) struct { lp: f32, bp: f32, hp: f32 } {
        // Chamberlin is only stable while f stays well under 1; cap the cutoff at a sixth of the
        // rate rather than letting a sweep's top end blow the filter up into a full-scale scream.
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

/// Exponential decay 1→0 over `dur`, `curve` steepening it (1 = gentle, 6 = a spike). The shape
/// every percussive layer here wears, because a linear fade reads as a synth and this reads as a
/// thing being struck.
fn decay(u: f32, curve: f32) f32 {
    return @exp(-curve * mathx.clampF(u, 0, 1));
}

/// Attack-then-decay, for anything that has to SWELL before it goes (roars, motes, the death card).
fn swell(u: f32, peak: f32) f32 {
    const t = mathx.clampF(u, 0, 1);
    if (t < peak) return mathx.smoothstep(0, peak, t);
    return decay((t - peak) / (1.0 - peak), 3.5);
}

// ── THE RACK ── every voice is built by layering these gestures into `work`. Six primitives cover
// the whole game, which is the point: a bank made of six well-understood shapes stays TUNEABLE,
// where forty bespoke oscillator graphs would be forty things nobody dares touch.
const Rack = struct {
    n: usize = 0, // samples written so far (the voice's length)
    rng: mathx.Rng,

    // `secs`, not `seconds` — that name belongs to the bank's own length table below, and a
    // parameter shadowing a declaration is a compile error in Zig (rightly).
    fn init(seed: u64, secs: f32) Rack {
        const n = @min(@as(usize, @intFromFloat(secs * SRF)), MAX_N);
        @memset(work[0..n], 0);
        return .{ .n = n, .rng = mathx.Rng.init(seed) };
    }

    fn at(r: *const Rack, t: f32) usize {
        return @min(@as(usize, @intFromFloat(mathx.maxF(t, 0) * SRF)), r.n);
    }

    /// THE FAT LOW END. A sine whose pitch falls from f0 to f1 — a struck body. Every impact in
    /// the game has one of these under it, and it is the single biggest reason the bank reads as
    /// "low and fat" rather than as clicks: the ear hears the PITCH DROP as mass.
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

    /// AIR. Noise dragged through the SVF's bandpass while the cutoff sweeps c0→c1. This is every
    /// whoosh, scuff, breath and gust in the game; the sweep direction is the whole message —
    /// DOWN reads as something heavy passing you, UP as something being drawn or gathering.
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

    /// GRIT — lowpassed noise with a granular amplitude, so it CRUNCHES instead of hissing. Dirt
    /// under a boot, gravel off a slam, bone clatter, the crumble in a heavy hit.
    fn grit(r: *Rack, t0: f32, dur: f32, amp: f32, cut: f32, coarse: f32, curve: f32) void {
        const a = r.at(t0);
        const b = @min(a + r.at(dur), r.n);
        var p = Pole{};
        var hold: f32 = 0;
        var left: i32 = 0;
        var i = a;
        while (i < b) : (i += 1) {
            const u = @as(f32, @floatFromInt(i - a)) / @as(f32, @floatFromInt(b - a));
            // Sample-and-hold on the noise: holding a value for a few samples is what turns a
            // smooth hiss into audible GRAINS, and the grain size is the difference between sand
            // and shingle.
            if (left <= 0) {
                hold = r.rng.signed();
                left = 1 + r.rng.intn(@intFromFloat(1.0 + coarse * 12.0));
            }
            left -= 1;
            work[i] += p.step(hold, cut) * amp * decay(u, curve);
        }
    }

    /// RING — a stack of detuned decaying partials. Steel, a bowstring, a chime, the grace mote.
    /// Deliberately INHARMONIC by a few percent: perfectly harmonic partials read as a synth pad,
    /// and a struck metal object never is.
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

    /// VOICE — a driven saw with vibrato, swept through a resonant lowpass. Roars, groans, croaks,
    /// the death rattle. `rough` adds noise into the drive, which is what makes a throat sound like
    /// a throat instead of a sawtooth.
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
            // The formant sweep: a lowpass riding two octaves above the fundamental is roughly
            // where a throat's first resonance sits, and moving it with the pitch is what keeps a
            // long groan from turning into a drone.
            const out = f.step(saw, hz * (3.0 + 5.0 * (1.0 - u)), 0.72);
            work[i] += out.lp * amp * swell(u, shape);
        }
    }

    /// A TICK — the transient at the front of a hit. Barely anything on its own; it is what makes
    /// the body underneath it read as CONTACT rather than as a note.
    fn tick(r: *Rack, t0: f32, amp: f32, cut: f32) void {
        r.grit(t0, 0.012, amp, cut, 0.0, 5.0);
    }

    /// A DIGITAL BIRDCALL — two to four short pulse blips at STEPPED pitches. The stepping is the
    /// whole trick: a real bird GLIDES between notes and a chiptune one jumps, so quantizing the
    /// interval to semitones and holding each note flat is what makes it read as a machine's idea
    /// of a bird rather than as a bad sample. The master's bitcrush finishes the job.
    fn chirp(r: *Rack, t0: f32, amp: f32, base: f32) void {
        const notes = 2 + r.rng.intn(3);
        var t = t0;
        var k: i32 = 0;
        while (k < notes) : (k += 1) {
            // Whole semitones off the base, and a small set of them — a bird's phrase is a motif,
            // not a scale run.
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
                // Lowpassed hard, or an 8 kHz square at 22 kHz is pure alias fizz — and lowpassed
                // HARDER than that (2600, was 4200) because every bird in this game is a bird out on
                // the plain. A pulse wave's reedy top is the first thing a couple of hundred metres of
                // air takes off it, so keeping it is what made the calls sound like they were coming
                // from just off camera.
                work[i] += lp.step(pulse, 2600) * amp * decay(u, 3.0) * mathx.smoothstep(0, 0.15, u);
            }
            t += dur + r.rng.range(0.012, 0.045);
        }
    }

    // ── the master tape stage ── every voice goes out through this, which is what makes forty
    // separately-authored sounds feel like they were recorded in the same room on the same machine.

    /// Soft saturation. Fattens the low end, rounds every transient, and quietly guarantees nothing
    /// in the bank can clip the output however hard a layer was driven.
    fn sat(r: *Rack, drive: f32) void {
        for (work[0..r.n]) |*s| {
            const x = s.* * drive;
            s.* = x / (1.0 + @abs(x)); // a cheap tanh, and the asymmetry-free one we want
        }
    }

    /// The tape's own bandwidth. Rolls the top off everything so nothing in the game is BRIGHT.
    fn warm(r: *Rack, cut: f32) void {
        var p = Pole{};
        for (work[0..r.n]) |*s| s.* = p.step(s.*, cut);
    }

    /// WOW & FLUTTER — a slow, drifting pitch wobble read out of a fractional delay. The single
    /// most identifiably ANALOGUE thing in the chain: digital audio is perfectly in tune, and tape
    /// never is. Kept small; the point is that it is felt rather than heard.
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
            // `ia`/`ib`, not `i0`/`i1` — those are real Zig integer TYPE names and shadowing a
            // primitive is a compile error (archer.zig's trail loop hit the same wall).
            const ia: usize = @intFromFloat(@floor(src));
            const fr = src - @floor(src);
            const ib = @min(ia + 1, r.n - 1);
            work[i] = tape[ia] * (1.0 - fr) + tape[ib] * fr;
        }
    }

    /// THE NOISE FLOOR. A filtered hiss bed under the whole voice, ducking with the signal so it
    /// sits behind the sound rather than in front of it. This is the brief's "tape hiss": on its
    /// own it is nothing, and without it every sound starts from digital silence and reads sterile.
    fn hiss(r: *Rack, amt: f32) void {
        var p = Pole{};
        var q = Pole{};
        var i: usize = 0;
        while (i < r.n) : (i += 1) {
            const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(r.n));
            // Two poles, so the hiss is a soft band and not a fizz; it fades with the voice so a
            // short sound does not leave a tail of noise hanging behind it.
            const nz = q.step(p.step(r.rng.signed(), 5200), 2600);
            work[i] += nz * amt * (0.35 + 0.65 * decay(u, 1.6));
        }
    }

    /// ── BITCRUSH ── THE RETRO PASS, FOR EARS. The picture goes through posterize (fewer colour
    /// levels), pixelate (fewer samples) and dither; this is those three exactly, on a waveform:
    /// quantize the AMPLITUDE to `bits`, sample-and-HOLD to drop the effective rate by `hold`, and
    /// dither the quantizer so the decay tails don't step. Same idea, same era, and it is why the
    /// sound now belongs to the same machine the render does.
    ///
    /// IT GOES AFTER THE SATURATION AND BEFORE THE WARMTH, and that order is what makes it PHAT
    /// rather than harsh: the drive fattens the signal first so there is something with body to
    /// quantize, and the lowpass afterwards takes the top off the aliasing the hold throws up —
    /// keeping the crunch and losing the fizz. Crushed last it is just noise on top.
    fn crush(r: *Rack, bits: f32, hold: u32) void {
        const levels = std.math.pow(f32, 2.0, mathx.clampF(bits, 2, 16)) * 0.5;
        const step = @max(hold, 1);
        var held: f32 = 0;
        var k: u32 = 0;
        for (work[0..r.n]) |*s| {
            if (k == 0) held = s.*;
            k = (k + 1) % step;
            // TPDF dither — two uniform draws summed. Without it a quiet tail quantizes to one
            // constant level and the decay STAIRCASES, which is the ugly half of lo-fi rather than
            // the good half. Scaled by DITHER_LSB, and see there: the textbook ±1 LSB is a 16-bit
            // rule and this is not a 16-bit quantizer.
            const d = (r.rng.signed() + r.rng.signed()) * 0.5 / levels * DITHER_LSB;
            s.* = @round((held + d) * levels) / levels;
        }
    }

    /// Peak-normalize, so a row's `gain` means the same thing across the whole bank and retuning
    /// one voice's layers can never quietly make it the loudest thing in the game.
    fn norm(r: *Rack, peak: f32) void {
        var hi: f32 = 1e-6;
        for (work[0..r.n]) |s| hi = mathx.maxF(hi, @abs(s));
        const k = peak / hi;
        for (work[0..r.n]) |*s| s.* *= k;
    }

    /// Ramp the ends to zero. A buffer that starts or stops on a non-zero sample CLICKS, and a
    /// click is the one artefact the ear picks out of any mix instantly.
    fn ends(r: *Rack, inS: f32, outS: f32) void {
        const ni = @max(r.at(inS), 1);
        const no = @max(r.at(outS), 1);
        for (work[0..@min(ni, r.n)], 0..) |*s, i| s.* *= @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(ni));
        var i: usize = 0;
        while (i < @min(no, r.n)) : (i += 1) work[r.n - 1 - i] *= @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(no));
    }

    /// The finish every voice ends on. One call, so no sound can accidentally skip the house
    /// character — drive and cutoff are the only things most voices vary about it.
    fn master(r: *Rack, drive: f32, cut: f32) void {
        r.masterX(drive, cut, CRUSH_BITS, CRUSH_HOLD);
    }

    /// …and the same finish with the CRUSH dialled per voice. Big low sounds want less of it (a
    /// 5-bit quantizer on a long sub tail is audible as steps rather than as crunch); small sharp
    /// ones can take much more, and the chrome positively wants it.
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

// ── THE CRUSH, in one place so it can be dialled by ear ─────────────────────────────────
// `BITS` is the amplitude quantizer (fewer = grittier — the audio posterize) and `HOLD` divides
// the effective sample rate (2 = 11 kHz — the audio pixelate). These are the house values every
// voice gets through `master`; the handful that want more or less say so with `masterX`.
//
// ── THE BANK'S HISS COMES FROM HERE, AND `hiss()` IS NOT IT ───────────────────────────────
// "All sfx have too much hiss" is THIS stage, ~28 dB above the tape hiss layer, and turning that layer
// down does nothing. The arithmetic: at 5.5 bits one quantiser step is 0.044 FS (−27 dBFS), so the
// quantisation error is −38 and ±1-LSB TPDF dither on top is −35, together ≈ −33 dBFS broadband on every
// sample of every voice. `hiss()` for comparison sits near −61. `norm` runs after both, so the ratio is
// identical for all 47 voices — which is why the complaint was "ALL sfx" and not "these three".
//
// Fixed in the two constants below. The SAMPLE-RATE crunch (`HOLD`) is deliberately untouched: it is most
// of what the lo-fi character actually is and adds no noise floor at all.
const CRUSH_BITS: f32 = 7.5; // was 5.5 — +2 bits is −12 dB of floor, and 180 levels still staircases
/// DITHER DEPTH IN LSB, and the textbook ±1 is a SIXTEEN-BIT rule. At 16 bits one LSB is inaudible so
/// full-scale TPDF is free; at 5.5 it was the single loudest thing in the master chain, doubling the
/// quantiser's own noise power to buy linearity nobody can hear at that step size. Dither is here to
/// stop a decaying tail collapsing onto one constant level — it does that at a third of an LSB.
const DITHER_LSB: f32 = 0.4; // …another −8 dB. MEASURED: the chain's tail floor goes −34.7 → −50.8 dBFS
const CRUSH_HOLD: u32 = 2;

// ── AIR ABSORPTION, BAKED ───────────────────────────────────────────────────────────────
// The cue that actually makes a sound read as FAR rather than as quiet. Air swallows high frequencies
// far faster than low ones — ISO 9613-2 puts 4 kHz at roughly fifteen times the loss per hundred
// metres that 250 Hz takes, and 8 kHz at fifty — so distance is a spectral tilt long before it is a
// level. raylib gives no filter on a playing voice (volume, pitch and pan, and that is the lot), so
// for the two voices that are ALWAYS distant it goes into the RENDER, which a synthesized bank makes
// free: it is one number in the master stage.
//
// Here rather than as literals inside `mkWind`/`mkBirds` because "these two are the far ones" is a
// decision about the whole soundscape, not a tuning detail of either, and because it is the one thing
// about them a test can actually hold (a pitched chirp's brightness cannot be measured by ear-free
// means nearly as cleanly as its cutoff can be read).
const AIR_FAR_BED: f32 = 1400; // the wind, a few hundred metres of it in every direction
const AIR_FAR_CALL: f32 = 2100; // …and a bird somewhere out on the plain
/// The big LOW cry — the OWL (a wolf howl was the other and is gone). Darker than a bird's whistle, and
/// that is not a guess: it is further out (rolled to 150 m) and low to begin with, so what arrives is
/// the fundamental and almost none of the throat above it.
const AIR_FAR_CRY: f32 = 1950;
/// The darkest any NEAR voice is rendered (mkOgreStep / mkStepSoft sit here). The far ones above must
/// stay clear of it, or "far" is being claimed for something no duller than a boot on gravel at your feet.
const AIR_NEAR_DARKEST: f32 = 2200;
/// …and the one voice that is deliberately NEARER than anything else in the game: the crickets are in
/// the grass AT YOUR FEET, so they are the only ambient layer rendered BRIGHT. Turning that round is
/// what would put the whole insect field out on the horizon with the wind.
///
/// THE CRICKETS ARE NOT THE MOSQUITO, and this is written down because I got it wrong: told "get rid
/// of the mosquito sound", I reasoned from first principles to this constant — 4.2 kHz, continuous,
/// nothing above it to mask it — deleted the whole cricket bed, and was wrong. The owner identified it:
/// the WOLF HOWL. See `mkWolf`. A plausible mechanism is not a diagnosis, and the crickets are what
/// makes a golden-hour field sound like one.
const AIR_NEAR_GRASS: f32 = 4200;

// ── THE VOICES ──────────────────────────────────────────────────────────────────────────
// Order is the BANK table's order below; the two are pinned at comptime.
pub const Id = enum {
    // the hero on his feet
    step_soft,
    step_hard,
    step_sprint,
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
    // ── THE KOBOLDS ── a DOG-THING, and every voice has a throat in it: the family reads as one
    // animal because the yip and the snarl are the same larynx at different sizes. Small, dry and
    // QUICK — the opposite of the ogre's block above, which is the point of putting them beside it.
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
    // ── THE CANOPY ── five ambient voices instead of one, because a plain with a single repeating
    // bird on it reads as a plain with a single repeating bird on it. Two of them are BEDS (wind,
    // crickets) and three are sparse CALLS on their own long clocks (see `CALLS`), so nothing here
    // ever arrives on the same beat as anything else.
    birds, // …their OWN voice, not five phrases baked into the wind loop (see mkBirds)
    birdsong, // …a SECOND bird, and the opposite kind: fluted and slurred where `birds` is stepped
    owl, // hoo … hu-hoooo, from somewhere in the ruins
    crickets, // the insect chirr in the grass — a BED, and the only ambient voice rendered bright
    // (A WOLF howl was the fifth ambient voice and is GONE — owner's call, after it turned out to be
    // the "skeeter". Retuning its fundamental down out of the wingbeat band was tried first and the
    // answer was to remove it entirely, so it is not a tuning problem to come back to.)
};
const NV = @typeInfo(Id).@"enum".fields.len;

// ── VARIANCE: KEEP THE IDENTITY, LOSE THE GRATE (owner's law — the wabi-sabi rule, for ears). Three
// dials, in order of how much they buy:
//
//   `vars` — N different TAKES baked from different seeds, rotated round-robin so you cannot hear the
//            same one twice in a row. By far the strongest: the ear catches a repeated WAVEFORM long
//            before it catches a repeated pitch.
//   `jit`  — per-trigger PITCH wobble, for the fine grain between takes.
//   `vjit` — per-trigger LEVEL wobble. Matters most for footsteps: real steps vary in weight far more
//            than in pitch, and identically-loud ones read as a machine however well pitched.
//
// ── THE SUBMIX TRIM ── one multiplier for THE BACKGROUND, applied where a row's gain becomes a volume.
// A row's own `gain` is its BALANCE INSIDE its family; a family's level is one number here, because
// "put the ambience further back" cannot be six edited literals with one silently missed.
//
// NO TRIM FOR THE COMBAT VOICES. A `.creature` family over the toads and the ogre was tried and REVERTED
// (owner: "I meant ambient sounds not combat sounds") — a fight is what the player is listening TO, and
// quietening the animal eating him is the opposite of the note.
pub const Submix = enum {
    /// Everything that is not background: the hero, his steel, his flasks, the arrows, the foes he is
    /// fighting, the chrome. The reference level — trim 1.0 by definition.
    game,
    /// THE BACKGROUND: both beds and all three sparse calls. Its whole job is to be noticed only
    /// when it stops, which is a level, not a mix position.
    ambience,
};

const TRIM_AMBIENCE: f32 = 0.55; // the canopy pushed a real 5 dB into the back of the room

fn submixTrim(m: Submix) f32 {
    return switch (m) {
        .game => 1.0,
        .ambience => TRIM_AMBIENCE,
    };
}

const Row = struct {
    make: *const fn (*Rack) void,
    gain: f32 = 0.7,
    /// Which family's trim this row pays (see `Submix`). Defaults to the reference level, so a voice
    /// that is neither a creature nor background needs no ceremony.
    mix: Submix = .game,
    jit: f32 = 0.06,
    vjit: f32 = 0.12,
    vars: u8 = 1,
    poly: u8 = 2,
    /// HOW FAR THIS VOICE CARRIES, in metres — the range `world()` fades it out over, and past which
    /// it costs nothing at all. Per VOICE because it is a property of the sound, not of the engine: a
    /// croak dies in the reeds and a giant's club hitting the earth is heard across the plaza, and one
    /// shared 46 m for everything got both wrong in opposite directions. It was audibly wrong, too —
    /// a knot of toads forty metres off murmured away at you through terrain you could not see them
    /// in, while the slam this file's own comment says "should carry across the plaza" went silent
    /// four metres short of it.
    ///
    /// Only voices that go through `world()` use it; the hero's own sounds play at the listener.
    reach: f32 = FALLOFF,
};

// ── the renderers ───────────────────────────────────────────────────────────────────────
// Each is a handful of layers plus the master. Read them as recipes: what the layer IS, then when
// it happens, then how bright and how fast it goes.

fn mkStepSoft(r: *Rack) void {
    // A walk: a soft heel body, a scuff of grit, and nothing else. Kept DARK — a bright footstep
    // is the fastest way to make a heavy character read as light.
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
    // A sprint: the same boot, but the weight lands ahead of the body — a longer low tail and a
    // scrape on the push-off, so a full-tilt run has its own rhythm in the ears as well as the legs.
    r.tick(0.0, 0.26, 3600);
    r.body(0.0, 0.20, 152 + r.rng.signed() * 16, 42, 1.0, 3.6);
    r.grit(0.002, 0.17, 0.46, 2600 + r.rng.signed() * 600, 0.5, 3.9);
    r.air(0.012, 0.11, 0.22, 2400, 500, 0.45, 4.0);
    r.master(2.2, 3600);
}

fn mkRoll(r: *Rack) void {
    // CLOTH AND GRIT OVER DIRT, and NOTHING THAT SWEEPS. This led with a 2600→260 air glide over 0.42 s,
    // which is a whoosh — it read as something being SWUNG rather than a body going over its own
    // shoulder, and it was the loudest layer in the voice. So the tumble is GRIT, which is what is
    // actually in contact with the ground, with a dull low thump under it where the shoulder takes the
    // weight and a smaller scuff on the rise. Kept DARK (a low master cut): a bright roll is a swish.
    r.grit(0.0, 0.20, 0.34, 1100, 0.55, 3.0);
    r.body(0.05, 0.16, 78, 40, 0.42, 4.5); // …the shoulder taking it
    r.grit(0.24, 0.13, 0.20, 1700, 0.45, 4.0); // …and the plant coming out of it
    r.air(0.0, 0.16, 0.10, 900, 480, 0.10, 3.2); // a breath of cloth, resonance nearly shut — no glide
    r.master(1.15, 2600);
}

fn mkSwingLight(r: *Rack) void {
    // R1: MOVED AIR, not a cartoon vwip (owner's call — the old pair sounded stupid). It swept UP
    // 700→3400 with the resonance halfway open and a second sweep coming back DOWN over the top of
    // it: two pitched glides fighting, which is a slide whistle, not a blade. One broad pass now,
    // its cutoff DRIFTING DOWN as the tip goes by (the only doppler a whoosh gets), resonance
    // nearly shut so it stays airy, and barely any drive — saturation is what turned the noise
    // into a rasp. Loudness lives in BANK.gain, since `master` normalizes every voice.
    r.air(0.0, 0.15, 0.55, 2000, 620, 0.16, 2.6);
    r.air(0.015, 0.085, 0.16, 5200, 2400, 0.12, 3.4); // the EDGE: a thin hiss riding the front of it
    r.master(1.05, 4200);
}

fn mkSwingHeavy(r: *Rack) void {
    // R2: the raise, a beat, then the drop — the same two-part gesture, still timed to the pause the
    // animation holds at the top of the arc, but taken out of cartoon territory the same way the
    // light was: resonance nearly shut, less drive, and the raise dropped to almost nothing so the
    // DROP is the only part that speaks.
    r.air(0.0, 0.26, 0.26, 900, 1500, 0.14, 1.7);
    r.air(0.24, 0.30, 0.72, 2200, 380, 0.18, 2.1);
    r.body(0.26, 0.14, 170, 64, 0.22, 3.8); // a little mass behind the edge
    r.master(1.25, 3600);
}

// ── ABRASION ── what actually causes harsh here, because it is four things and none of them is volume:
//   1. `master(drive, …)` — `sat` is a saturator, so drive GENERATES harmonics, right into the 2-5 kHz
//      band the ear is most sensitive to. Biggest cause by far.
//   2. `master(…, cut)` — the tape bandwidth that would otherwise stop them getting out.
//   3. `tick(…, cut)` — a transient at 5 kHz is an ice-pick; it says CONTACT just as well far lower.
//   4. `ring` — partials space at ~1.48x, so 1400 Hz with 3 of them reaches past 4 kHz. On flesh that
//      metallic sting should barely be there.
// The `body` layer is the only one carrying mass, so it gains what the others give up. DARKER, not
// quieter — combat takes no submix trim (see `Submix`).

fn mkHitLight(r: *Rack) void {
    // Blade into a body: a wet crack and a low thump under it. The ring is what says STEEL did it, but
    // it is a hit on FLESH — it is a hint of edge, not a bell, so it sits an octave down with one fewer
    // partial and a third of the level.
    r.tick(0.0, 0.34, 2200);
    r.body(0.0, 0.20, 170, 56, 1.05, 3.8); // …lower and longer: this is the layer doing the work
    r.body(0.0, 0.09, 88, 52, 0.5, 5.0); // a sub under it, for the thud
    r.grit(0.0, 0.10, 0.34, 1500, 0.45, 5.0);
    r.ring(0.004, 0.13, 700, 0.13, 7.0, 2);
    r.master(1.25, 2500);
}

fn mkHitHeavy(r: *Rack) void {
    // The R2 connecting: everything the light has, dropped an octave and given a crunch that
    // carries. The second body an eighth of a second later is the follow-through settling.
    r.tick(0.0, 0.40, 1800);
    r.body(0.0, 0.36, 128, 34, 1.35, 2.4);
    r.body(0.0, 0.14, 66, 38, 0.62, 4.0); // …and the floor under that
    r.grit(0.0, 0.24, 0.52, 1200, 0.75, 3.2);
    r.ring(0.006, 0.20, 520, 0.15, 5.0, 3);
    r.body(0.11, 0.22, 58, 30, 0.5, 3.0);
    r.master(1.45, 2100);
}

fn mkHurt(r: *Rack) void {
    // Taking a chomp: a short winded grunt over the impact. Deliberately GUTTURAL and short — a
    // long cry would be the loudest thing in every fight and it would wear out in a minute. `rough` is
    // the rasp dial and it comes DOWN with everything else: a throat, not a bandsaw.
    r.body(0.0, 0.19, 118, 46, 0.85, 3.8);
    r.growl(0.01, 0.22, 156, 108, 0.60, 0.11, 0.14);
    r.grit(0.0, 0.09, 0.22, 1100, 0.45, 5.0);
    r.master(1.3, 2200);
}

fn mkHurtHeavy(r: *Rack) void {
    // The lunge or the slam landing: the air goes out of him. Lower, longer, and the growl falls
    // further, which is the whole difference between "ow" and "that hurt".
    r.body(0.0, 0.38, 98, 30, 1.15, 2.4);
    r.growl(0.0, 0.42, 140, 70, 0.85, 0.15, 0.10);
    r.grit(0.0, 0.16, 0.34, 900, 0.68, 3.4);
    r.air(0.02, 0.26, 0.18, 1400, 240, 0.30, 3.0);
    r.master(1.5, 1900);
}

fn mkStagger(r: *Rack) void {
    // A stance break: boots losing the floor. All scuff, no impact — the impact already played on
    // the blow that caused it, and doubling it makes a stagger read as a second hit.
    r.grit(0.0, 0.36, 0.52, 1200, 0.8, 2.4);
    r.air(0.0, 0.32, 0.30, 1200, 320, 0.34, 2.6);
    r.body(0.14, 0.18, 70, 38, 0.42, 3.6);
    r.master(1.35, 2000);
}

fn mkGuardBlock(r: *Rack) void {
    // A BLOW CAUGHT ON WOOD, with iron round the edge of it. The whole voice is the difference
    // between this and `mkHurt`: no throat in it at all, because nothing went into HIM — a grunt
    // here would tell the player he had been hit, which is the one thing that did not happen.
    // Bright and short where a wound is low and long: boards CRACK, flesh thumps.
    r.tick(0.0, 0.42, 3400); // the strike itself…
    r.body(0.0, 0.13, 190, 78, 0.95, 5.0); // …the boards taking it, dry and quick
    r.grit(0.0, 0.07, 0.30, 2400, 0.4, 6.0); // …a splintery edge on the impact
    r.ring(0.003, 0.09, 940, 0.16, 8.0, 2); // …and the iron rim, a hint of it and nothing more
    r.master(1.6, 4200);
}

fn mkGuardBreak(r: *Rack) void {
    // THE SHIELD KNOCKED ASIDE — the loudest thing that can happen to you short of dying, and the
    // cue that the next blow is free. Everything the block has, an octave down and three times as
    // long, then the boards ringing off and his boots losing the floor under it (the stagger's own
    // scuff, which is what says his FOOTING went and not just his guard).
    r.tick(0.0, 0.46, 1700);
    r.body(0.0, 0.34, 132, 40, 1.30, 2.6);
    r.grit(0.0, 0.22, 0.50, 1300, 0.7, 3.2);
    r.ring(0.004, 0.30, 470, 0.22, 3.4, 3); // the rim, swinging away and still ringing
    r.grit(0.10, 0.34, 0.40, 1100, 0.8, 2.6); // …and the feet going
    r.air(0.08, 0.30, 0.24, 1300, 300, 0.32, 2.8);
    r.master(1.7, 2400);
}

fn mkRefused(r: *Rack) void {
    // AN EMPTY BAR. Muffled, dull, and over instantly: the sound of an input that did nothing.
    // It exists for exactly the reason `hero.stamRefused` does — under a ZERO INPUT LAG law the
    // player must never have to wonder whether the game heard him, and silence cannot say that.
    r.body(0.0, 0.055, 190, 120, 0.5, 7.0);
    r.grit(0.0, 0.04, 0.25, 700, 0.3, 8.0);
    r.master(1.4, 1400);
}

fn mkDeath(r: *Rack) void {
    // YOU DIED. The one long sound in the game: a groan falling away under a swelling low drone,
    // with the tape dragging on it. It has to survive the card's three and a half seconds without
    // becoming a drone, hence the fall — a note that stops moving stops meaning anything.
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
    // Waking at the grace: a warm low bloom rising out of nothing. The counterpart of the death
    // fall, and the only unambiguously KIND sound in the bank.
    r.body(0.0, 1.1, 88, 132, 0.8, 1.2);
    r.ring(0.02, 1.0, 330, 0.35, 2.0, 4);
    r.air(0.0, 0.8, 0.18, 300, 1800, 0.3, 1.4);
    r.master(1.5, 3600);
}

// ── the gaping toad ── wet, low, and rubbery. Everything it does has liquid in it.

fn mkToadHop(r: *Rack) void {
    r.body(0.0, 0.09, 190, 88, 0.5, 5.0); // the push off the haunches
    r.growl(0.0, 0.13, 130, 210, 0.45, 0.3, 0.25); // a short croak going UP with the leap
    r.grit(0.0, 0.06, 0.25, 1200, 0.6, 6.0);
    r.master(1.9, 2600);
}

fn mkToadLunge(r: *Rack) void {
    // The committed pounce: a long loaded croak on the coil, then the launch. The coil is the tell
    // and it is deliberately the loudest part — you are meant to hear it before you see it.
    r.growl(0.0, 0.36, 96, 168, 0.85, 0.34, 0.55);
    r.air(0.26, 0.22, 0.4, 600, 2200, 0.4, 2.6);
    r.body(0.28, 0.16, 150, 64, 0.7, 3.8);
    r.master(2.2, 2800);
}

fn mkToadGape(r: *Rack) void {
    // The jaws yawning: a rising airy suck with a throat under it. Up-sweeps read as GATHERING,
    // which is exactly what the throat sac is doing.
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

// ── the skeletal archer ── dry, hollow, wooden. Nothing about it is wet, which is what makes it
// read as the opposite of the toad.

fn mkBowDraw(r: *Rack) void {
    // A slow creak: resonant noise crawling upward as the limbs load. The RESONANCE is doing all
    // the work — the same noise unfiltered is just wind.
    r.air(0.0, 0.55, 0.6, 420, 1150, 0.88, 0.9);
    r.grit(0.0, 0.5, 0.14, 2400, 0.85, 1.1); // fibres crackling under the pull
    r.master(1.6, 3400);
}

fn mkBowLoose(r: *Rack) void {
    // The release: a string twang and the shaft's fizz leaving. The twang is a genuine pitched
    // ring, because that is the one sound in the fight that has to cut through everything else —
    // it is the cue to move.
    r.tick(0.0, 0.5, 6000);
    r.ring(0.0, 0.30, 196, 0.9, 5.0, 4);
    r.air(0.01, 0.22, 0.45, 4200, 1200, 0.5, 3.2);
    r.body(0.0, 0.07, 150, 84, 0.3, 6.0);
    r.master(1.9, 5000);
}

// ── ARROW IMPACTS ── FOUR of them, one per thing a shaft can end up in. Every one is the same two
// ingredients in a different ratio, which is what keeps them a family: a RIP (the fletching tearing
// past whatever it went into — a fast downward noise sweep, the "fuzz") and a THUNK (the head
// arriving — a pitched body that falls). Hard things take the thunk, soft things take the rip, and
// all four stay under a fifth of a second, because an arrow landing is an instant, not an event.
//
// The shaft that decides which you hear is `Arrow.struck`, carried up from the collider it hit.

/// The shared rip: broadband noise sweeping DOWN fast. Its own function because all four voices
/// want the identical gesture at different weights, and a rip that drifted between them would make
/// four impacts sound like four unrelated sounds instead of one arrow meeting four materials.
fn arrowRip(r: *Rack, amp: f32) void {
    r.air(0.0, 0.13, amp, 5200, 900, 0.35, 3.4); // the tear
    r.grit(0.0, 0.09, amp * 0.55, 3600, 0.25, 4.6); // …with fibre in it
}

fn mkArrowHit(r: *Rack) void {
    // INTO THE HERO — flesh, so it is mostly RIP: a wet tearing fizz with only a dull, soft thump
    // under it. No ring at all; nothing about a body resonates.
    arrowRip(r, 1.0);
    r.tick(0.0, 0.34, 2600);
    r.body(0.0, 0.15, 170, 58, 0.70, 5.0);
    r.grit(0.0, 0.10, 0.50, 1200, 0.55, 5.2);
    r.master(2.2, 3000);
}

fn mkArrowDirt(r: *Rack) void {
    // INTO THE EARTH — the miss, and by far the commonest of the four. Soft: a scuffing rip and a
    // low soft thud, no ring, gone almost immediately. It has to be the most forgettable of them.
    arrowRip(r, 0.62);
    r.body(0.0, 0.11, 150, 52, 0.60, 6.0);
    r.grit(0.0, 0.12, 0.55, 900, 0.65, 5.0);
    r.master(1.9, 2400);
}

fn mkArrowWood(r: *Rack) void {
    // INTO TIMBER — the satisfying one. A HARD thunk with a short woody knock in it, and only a
    // little rip. A tree trunk is the thing an arrow is happiest hitting and it should sound it.
    arrowRip(r, 0.34);
    r.tick(0.0, 0.70, 5000);
    r.body(0.0, 0.11, 300, 96, 0.95, 6.0);
    r.ring(0.003, 0.13, 420, 0.30, 8.0, 2); // a dull, low, fast-dying knock — wood, not metal
    r.grit(0.0, 0.06, 0.45, 2600, 0.4, 7.0);
    r.master(2.2, 4200);
}

fn mkArrowStone(r: *Rack) void {
    // INTO MASONRY — a STRUCTURE, and the one place a bodkin head meets something harder than it is.
    // The stone itself gives nothing back, so what rings is the HEAD and the shaft behind it: a
    // bright TINK, high and gone almost at once, over the dead crack (owner's call). That tink is
    // what makes "that was a wall" audible without looking, and it is exactly what the ORGANIC
    // three — flesh, earth, timber — must never have.
    arrowRip(r, 0.40);
    r.tick(0.0, 0.85, 7000);
    r.body(0.0, 0.055, 420, 190, 0.55, 9.0);
    r.ring(0.002, 0.11, 3100, 0.34, 9.0, 2);
    r.grit(0.0, 0.07, 0.75, 4200, 0.35, 7.5);
    r.master(2.1, 5600); // …and the warmth stage opened up enough to let the tink through
}

fn mkArrowMetal(r: *Rack) void {
    // INTO IRON — a brazier, a torch bracket, a gibbet cage. The hardest thunk of the four AND the
    // only one allowed to ring, because ironwork is the one thing out here that actually does.
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

// ── the one-eyed ogre ── everything is an octave down and half a second longer. Scale, in sound.

fn mkOgreStep(r: *Rack) void {
    // A footfall you feel: a very low body with a long tail, and gravel thrown off it. This is the
    // voice that most wants the sub — it is the giant's presence when he is only walking.
    r.body(0.0, 0.42, 74, 27, 1.2, 2.4);
    r.body(0.0, 0.16, 150, 60, 0.4, 4.5); // a knock on top, so it reads as a FOOT not a rumble
    r.grit(0.005, 0.26, 0.45, 1500, 0.8, 3.2);
    r.master(2.6, 2200);
}

fn mkOgreRoar(r: *Rack) void {
    // The windup tell. A long rising roar — the one sound in the game allowed to be an event, and
    // it lasts as long as the club takes to get overhead.
    r.growl(0.0, 0.85, 68, 104, 1.0, 0.28, 0.35);
    r.growl(0.02, 0.80, 102, 152, 0.5, 0.4, 0.4); // an upper throat layer, for size
    r.body(0.0, 0.7, 46, 34, 0.6, 1.4);
    r.air(0.1, 0.6, 0.16, 700, 2200, 0.3, 1.5);
    r.master(2.4, 2600);
}

fn mkOgreSlam(r: *Rack) void {
    // The club meeting the earth. Everything at once: a crack, a crater, and debris raining out of
    // it for a third of a second afterwards.
    r.tick(0.0, 0.9, 3000);
    r.body(0.0, 0.62, 96, 22, 1.5, 1.9);
    r.body(0.0, 0.20, 210, 55, 0.7, 3.6);
    r.grit(0.0, 0.40, 0.9, 1700, 0.85, 2.4);
    r.grit(0.14, 0.34, 0.35, 2600, 0.95, 2.2); // the debris, arriving late
    r.air(0.0, 0.30, 0.35, 2200, 260, 0.4, 2.6);
    r.master(3.0, 2400);
}

fn mkOgreSwipe(r: *Rack) void {
    // The horizontal scythe: a huge slow whoosh that never touches the ground. No impact layer —
    // that absence is what tells you it is the OTHER attack.
    r.air(0.0, 0.42, 1.0, 1900, 210, 0.55, 1.8);
    r.air(0.04, 0.34, 0.4, 900, 3000, 0.35, 2.2);
    r.body(0.06, 0.24, 120, 52, 0.4, 2.8);
    r.master(2.2, 2800);
}

fn mkOgreHurt(r: *Rack) void {
    // A giant barely gives — a short annoyed grunt off a very deep body, which is what makes his
    // high poise audible instead of only being a number.
    r.growl(0.0, 0.26, 96, 66, 0.9, 0.3, 0.1);
    r.body(0.0, 0.26, 108, 40, 0.9, 3.2);
    r.grit(0.0, 0.14, 0.4, 1400, 0.7, 4.0);
    r.master(2.5, 2400);
}

fn mkOgreDie(r: *Rack) void {
    // The topple. A long failing roar, then a great deal of weight arriving on the ground.
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

// ── the flasks ──────────────────────────────────────────────────────────────────────────

// ── the kobolds ── SMALL, DRY AND FAST, and all of it comes out of a dog's throat. `growl` is the
// workhorse here the way `body` is for the ogre: a kobold's character is that it is always making a
// noise, and the noise is always an animal one.

// THE BARKS, and they go LOW. A real jackal's larynx sits near 400-600 Hz; up to seventy-two of them
// yipping there through a saturator is the most fatiguing noise this bank can make. A creature can be
// small in the SILHOUETTE and low in the THROAT — the model says how big it is.

fn mkKoboldSnarl(r: *Rack) void {
    // HE COMMITS. One bark, and it is a chest sound: a short low woof with the throat tearing at the end
    // of it. This is the cue to back off, so it is the most PRESENT thing the creature does — present
    // being different from bright, which is the whole note.
    r.body(0.0, 0.12, 132, 84, 0.75, 4.0); // the chest behind the bark
    r.growl(0.0, 0.14, 176, 236, 0.85, 0.14, 0.06); // …up, fast, barely any rasp
    r.growl(0.10, 0.26, 208, 118, 0.60, 0.26, 0.16); // …and tearing on the way down
    r.air(0.0, 0.10, 0.16, 900, 1900, 0.30, 3.2);
    r.master(1.35, 2300);
}

fn mkKoboldChop(r: *Rack) void {
    // JUST THE AXE. The snarl moved out (mkKoboldSnarl, once per flurry) and so did the impact — this
    // used to carry a `tick` + `body`, i.e. the sound of the blow LANDING, on every swing whether it hit
    // anything or not. A swing that always sounds like a hit is a swing you cannot read.
    r.air(0.0, 0.21, 0.46, 1700, 420, 0.34, 2.6); // DOWN-sweeping, so it reads as travelling past you
    r.grit(0.02, 0.10, 0.08, 1000, 0.4, 3.0); // …the haft turning in a fist
    r.growl(0.0, 0.15, 148, 116, 0.26, 0.24, 0.30); // a low grunt of effort under it, not a bark
    r.master(1.15, 2000);
}

fn mkKoboldHeave(r: *Rack) void {
    // THE OPENING, and it has to SOUND like one — this is the cue that says come back in. Ragged
    // panting on a body that has nothing left: air-led, with a thin wheeze rather than a growl, because
    // a creature this size that is out of breath squeaks. THREE breaths, quickening: panting is a rhythm
    // and two of them is just two noises.
    r.air(0.0, 0.24, 0.52, 1300, 380, 0.22, 1.8);
    r.growl(0.02, 0.20, 148, 104, 0.26, 0.30, 0.18); // …a wheeze under the first one
    r.air(0.30, 0.26, 0.48, 1150, 340, 0.20, 1.6);
    r.growl(0.32, 0.22, 132, 92, 0.24, 0.34, 0.20);
    r.air(0.58, 0.22, 0.40, 1000, 300, 0.18, 1.6);
    r.master(1.3, 1900);
}

fn mkKoboldCast(r: *Rack) void {
    // THE PRIEST'S TELL — A THROAT, NOT A BELL (owner: "should not be a weird bell sound"). It was three
    // overlapping `ring`s: twelve partials spaced at 1.48x and sustained for a second, and that spacing
    // is what a struck METAL object does — so a dog-thing chanting came out as a dissonant chime cluster
    // ringing over itself. `ring` is for steel, a bowstring, a chime; a CHANT is a voice.
    //
    // So it is his own larynx, like every other kobold voice: a rough growl CLIMBING (low, where a throat
    // actually lives), a hollow tone rising under it with no vibrato of its own, and the bone charms on
    // the staff rattling as he lifts it — which is what gives the tell an ONSET instead of a fade-in.
    // Kept dark on purpose: brightness is most of what read as metal.
    r.grit(0.0, 0.10, 0.20, 2600, 0.7, 5.0); // the charms — the attack
    r.growl(0.02, 0.85, 190, 300, 0.40, 0.34, 0.55); // the chant itself, climbing
    r.body(0.10, 0.75, 128, 190, 0.24, 1.6); // …a hollow tone rising with it (`body` has no vibrato)
    r.grit(0.58, 0.30, 0.10, 1500, 0.5, 2.0); // …and the charms again as it gathers
    r.master(1.5, 3200);
}

fn mkKoboldHeal(r: *Rack) void {
    // JUST A GENTLE CHIME (owner, twice — it was a low bell, then three stacked rings and a breath of
    // air, which is a sparkle). ONE struck note with a soft tail and nothing else: every extra layer
    // here turns a chime into an event, and hearing this means you were too slow, so the game must not
    // celebrate it at you. Drive 1.0 = no saturation, and the cut stays low enough to keep the top off.
    r.ring(0.0, 0.30, 1568, 0.30, 3.4, 2);
    r.master(1.0, 6500);
}

fn mkKoboldWhirl(r: *Rack) void {
    // The sling going round. Three passes of a cord through air, so the LOOP is audible — that
    // repetition is the tell, and a single whoosh would read as the throw itself.
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const t = 0.02 + @as(f32, @floatFromInt(i)) * 0.20;
        r.air(t, 0.17, 0.34 + 0.06 * @as(f32, @floatFromInt(i)), 900, 2400, 0.55, 2.2);
    }
    r.master(2.0, 4000);
}

fn mkKoboldSling(r: *Rack) void {
    // The release: a hard snap of cord and the stone leaving. Short — all the information is in the
    // whirl before it, and this is only the full stop.
    r.tick(0.0, 0.5, 6000);
    r.air(0.0, 0.11, 0.46, 3400, 1200, 0.5, 4.5);
    r.body(0.0, 0.06, 300, 150, 0.22, 6.0);
    r.master(2.2, 5400);
}

fn mkKoboldBite(r: *Rack) void {
    // TEETH. A snap has three parts and the middle one is what sells it: the jaw opening (air), the
    // clack of the teeth meeting (tick + a tight ring), and the wet click of the throat behind it.
    r.air(0.0, 0.07, 0.26, 900, 1700, 0.32, 3.5);
    r.tick(0.06, 0.34, 2600); // the clack — and 7 kHz of it was the ice-pick in the mix
    r.ring(0.06, 0.06, 620, 0.14, 9.0, 2);
    r.body(0.05, 0.10, 128, 72, 0.55, 4.5); // the jaw has MASS: this is what the clack was missing
    r.growl(0.0, 0.16, 210, 148, 0.5, 0.22, 0.10);
    r.master(1.3, 2200);
}

fn mkKoboldHurt(r: *Rack) void {
    // A yelp — up, then straight down. `growl` with f1 ABOVE f0 rises, and a rise is what a small
    // thing does when it is hurt (the ogre's falls; that difference is most of the size gap). The RISE is
    // the character, so it stays; what goes is the register it rose INTO.
    r.body(0.0, 0.13, 120, 66, 0.6, 4.2);
    r.growl(0.0, 0.15, 200, 300, 0.85, 0.16, 0.08);
    r.growl(0.05, 0.18, 168, 104, 0.42, 0.26, 0.24); // …and the fall out of it
    r.air(0.0, 0.10, 0.16, 1200, 500, 0.26, 3.0);
    r.master(1.3, 2200);
}

fn mkKoboldDie(r: *Rack) void {
    // The yelp that does not recover: it starts as the hurt voice and comes apart, dropping through a
    // rattle into nothing. The body under it is what stops it reading as a bird.
    r.growl(0.0, 0.18, 216, 326, 0.9, 0.18, 0.08);
    r.growl(0.09, 0.48, 194, 78, 0.62, 0.30, 0.14);
    r.grit(0.26, 0.34, 0.24, 1100, 0.75, 2.4); // …a wet rattle in the throat
    r.body(0.30, 0.26, 96, 36, 0.44, 2.8); // …and the body going down
    r.master(1.35, 1900);
}

fn mkFlaskDrink(r: *Rack) void {
    // Cork, then three glugs, then the warm bloom of it taking hold. The glugs are the whole
    // character: a rising body per swallow, unevenly spaced, because a bottle empties in gulps and
    // an even rhythm is the one thing that would make it read as a machine.
    // THE TINK (owner's ask) — glass being knocked, right at the front. Two thin high partials with
    // a fast decay: it is the one bright, hard sound in a voice that is otherwise all liquid, and
    // that contrast is exactly what makes the whole thing read as a BOTTLE rather than a gulp.
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
    // DRIED MEAT: a tear, then chewing. The opposite of the flask beside it — that voice is glass
    // and liquid and this one has no ring in it anywhere, because nothing here is hard. The tear is
    // grit with the grain size up (fibres letting go one at a time, not a hiss), and the three
    // chews are unevenly spaced for the same reason the flask's glugs are.
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
    // A LID COMING UP, in the three parts it actually has: the lock giving (a hard iron snap), the HINGE
    // turning under load (a long dry grind, which is the part that says heavy), and the boards knocking
    // as the lid goes over past its balance. The grind is the whole voice — a chest that opens with one
    // click reads as a lunchbox.
    r.tick(0.0, 0.55, 4200);
    r.ring(0.0, 0.16, 620, 0.34, 6.0, 3); // the lock plate
    r.grit(0.06, 0.52, 0.30, 1100, 0.85, 1.1); // the hinge, coarse and slow
    r.body(0.06, 0.30, 132, 88, 0.40, 1.6); // …the mass of it turning
    r.tick(0.60, 0.42, 2600); // the lid arriving, over
    r.body(0.60, 0.16, 108, 58, 0.46, 4.0);
    r.master(2.0, 3200);
}

fn mkItemGet(r: *Rack) void {
    // SOMETHING GAINED. Grace-adjacent, deliberately: it is the same warm bloom the priest's heal borrows
    // and the ember gives off, because in this world every good thing is the same gold. Short — you may
    // pick up eight of these in one chest and a fanfare eight times over is a joke.
    r.ring(0.0, 0.34, 784, 0.46, 3.2, 3);
    r.ring(0.02, 0.28, 1176, 0.22, 4.4, 2);
    r.air(0.0, 0.20, 0.12, 2400, 5200, 0.45, 2.6);
    r.master(1.9, 6000);
}

fn mkFlaskCycle(r: *Rack) void {
    // Swapping which flask is up: a dry glassy tap on the belt. Chrome, so it stays small — this
    // fires on a D-pad press and nothing about it is an event.
    r.tick(0.0, 0.30, 6000);
    r.body(0.0, 0.06, 720, 520, 0.45, 6.5);
    r.masterX(1.4, 5200, CRUSH_BITS - 1.0, CRUSH_HOLD); // crushed harder — it IS a UI blip
}

// ── the world and the chrome ────────────────────────────────────────────────────────────

fn mkKill(r: *Rack) void {
    // A KILL IS A THUD (owner's call, twice over: no bell, no jingle). This was a chime, then a
    // rising airy dissipation, and both were the same mistake in different clothes — a kill was
    // announcing itself as an ACHIEVEMENT when the thing that actually happened is that a body
    // stopped. So: weight arriving on the ground, and nothing else. No pitch to hum along to, no
    // reward cue, no rising anything. The payout used to add a second little two-note lift on the
    // same frame; that voice is gone rather than quietened, because the fix for a jingle is not a
    // smaller jingle.
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
    // THE BED. Eight seconds of moving air under the whole game, re-triggered when it runs out. Its
    // job is to stop silence sounding like the audio is broken, so it sits well under everything
    // and it never resolves.
    //
    // FOUR LAYERS, each on its own gust clock (owner: more complex, more subtle layers). One noise
    // band is a hiss; what makes air read as WEATHER is that its bands move independently — the low
    // body swells while the whistle is dying, the grit arrives late on a gust, and the moan is on a
    // clock so slow you never hear it start. Every rate below is incommensurate with every other,
    // which is also what stops an 8-second buffer having a findable loop point.
    var body = Svf{};
    var whistle = Svf{};
    var top = Pole{};
    var moan = Svf{};
    // PER-TAKE GUST PHASES. The bed is baked TWICE from different seeds and the two takes are played
    // hard left and hard right (see `bed`), which is the only way a stereo pair can put you INSIDE
    // weather rather than in front of it. The noise decorrelates itself, but the gust clocks were pure
    // functions of `t`, so both takes swelled on exactly the same frame — and a gust that arrives in
    // both ears at once collapses the field back to a point in the middle. Rolled per take, the wind
    // crosses you.
    const q1 = r.rng.angle();
    const q2 = r.rng.angle();
    const q3 = r.rng.angle();
    var i: usize = 0;
    while (i < r.n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / SRF;
        // The gusts. Three clocks, and the layers below take DIFFERENT mixes of them, so no two
        // layers peak together.
        const g1 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.083 * t + q1);
        const g2 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.031 * t + 2.1 + q2);
        const g3 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.157 * t + 4.4 + q3);
        const nz = r.rng.signed();

        // 1. THE BODY — a low, wide band. The weight of moving air; almost all of the level.
        const b = body.step(nz, 150.0 + 380.0 * g2, 0.35).bp;
        // 2. THE WHISTLE — a narrow resonant band drifting through the mids: air over stone and
        //    long grass. Resonant enough to have a pitch, quiet enough that you never name it.
        const w = whistle.step(nz, 620.0 + 1500.0 * g1, 0.86).bp;
        // 3. THE SIBILANCE — a soft top, gated hard by its own gust so it only arrives on the
        //    peaks. This is the layer that makes a gust sound like it ARRIVES rather than swells.
        const s = top.step(nz, 5200) * mathx.smoothstep(0.55, 1.0, g3);
        // 4. THE MOAN — a very low, very slow band under everything. Sub-audible on its own; it is
        //    what gives the plain a size.
        const m = moan.step(nz, 52.0 + 34.0 * g3, 0.55).bp;

        // ── THE MIX, RE-BALANCED FOR DISTANCE (owner: the bed should sound further away) ──────────
        // `norm` sets the LEVEL, so this is purely about WHERE the wind is, and the answer is spectral:
        // air absorbs high frequencies far faster than low ones (ISO 9613-2 puts 4 kHz at roughly
        // fifteen times the loss per hundred metres that 250 Hz takes), so near air is bright and
        // distant air is nothing but weight. The SIBILANCE is the layer that says "this is happening at
        // your ears" — cut hard. The BODY and the MOAN are what survive the crossing, and they carry
        // the size of the plain, so they come up. Turning the whole thing down could never do this: it
        // would only have made a near sound quiet, which the ear reads as a small source close by.
        work[i] = b * (0.30 + 0.70 * g2) * 0.94 +
            w * (0.10 + 0.50 * g1) * 0.20 +
            s * 0.05 +
            m * 0.68;
    }
    // THE BIRDS USED TO LIVE IN HERE, and could not be heard: the bed's own gain is 0.055 (owner's
    // call, and right), so a call mixed into this buffer went out at a twentieth of the level it was
    // written at. Worse, being part of an 8-second loop meant the same five phrases in the same
    // order for the whole session. They are `Id.birds` now — their own voice, at their own level,
    // on their own slow clock (see `mkBirds` and `ambience`).
    r.norm(0.42);
    r.sat(1.2);
    r.crush(CRUSH_BITS + 1.5, CRUSH_HOLD); // gentler than the house: a crushed noise bed hisses
    // 1400, down from 2600 — the AIR ABSORPTION of a few hundred metres of it, which is the cue that
    // actually reads as distance (see the mix above). It also lets the birds through: they were given
    // a brighter master than the house on the grounds that "a call has to get out from under the
    // wind", and with the bed's own top gone they get out from under a darker one.
    r.warm(AIR_FAR_BED);
    r.wow(0.003, 0.4);
    r.hiss(0.035); // …and less tape hiss: hiss is the MEDIUM, and a medium you can hear is a near one
    r.norm(0.62);
    r.ends(0.9, 0.9); // long crossfade ends, so the re-trigger seam is inaudible
}

// ── SPARSE DIGITAL BIRDCALLS ── one phrase, sometimes answered by a second. Deliberately CHIPTUNE:
// stepped semitone intervals, narrow pulse waves, no glide — the world is a golden-hour ruin seen
// through a retro filter, and a naturalistic bird would be the one thing in it pretending not to be.
//
// Its own voice rather than part of the wind (see mkWind): a bird has to be AUDIBLE, and the bed is
// deliberately not. Four takes, and `ambience` spaces them minutes apart across a session, so what
// you get is the odd call from somewhere out on the plain rather than a dawn chorus on a loop.
fn mkBirds(r: *Rack) void {
    // Pitched a little lower than they were (1750-2900 → 1550-2500): the very top of a whistle is what
    // a long crossing of air eats first, so a distant call is not just quieter, it is a rounder note.
    r.chirp(0.04, r.rng.range(0.55, 0.85), r.rng.range(1550, 2500));
    // …and now and then another one answers it, a little further off.
    if (r.rng.float() < 0.45) r.chirp(r.rng.range(0.42, 0.72), r.rng.range(0.28, 0.48), r.rng.range(1700, 2700));
    // 2100, not the old 4200. That number was set "brighter than the house cutoff" so a call could get
    // out from under the wind — but brightness is exactly what a sound a hundred metres off does NOT
    // have, so it bought audibility by putting the bird in the room with you. It gets out from under
    // the bed now because the BED went dark too (see mkWind's warm), which is the honest way round:
    // both are far, and neither is competing for the top of the spectrum.
    r.masterX(1.1, AIR_FAR_CALL, CRUSH_BITS + 1.0, CRUSH_HOLD);
}

// ── THE SECOND BIRD ── and it is deliberately the OPPOSITE of `mkBirds`. That one JUMPS between
// stepped semitones and holds each note flat (a machine's idea of a bird, which is the house style);
// this one SLURS — a glide between notes is the single cue that separates a fluted whistle from a
// blip, and having both is what stops the plain sounding like it has one bird on it. Built out of
// `body`, whose exponential pitch glide IS a slur; nothing else in the rack does one.
fn mkBirdsong(r: *Rack) void {
    const f0 = r.rng.range(1050, 1650);
    const up = f0 * r.rng.range(1.20, 1.55);
    r.body(0.05, 0.16, f0, up, 0.75, 3.2); // the up-slur…
    r.body(0.26, 0.22, up, f0 * r.rng.range(0.80, 0.95), 0.60, 2.6); // …and back down past where it started
    // …and now and then a third note on the end of the phrase, so the motif is not always the same
    // length. A call you can predict the shape of stops registering after the second one.
    if (r.rng.float() < 0.5) r.body(0.56, 0.18, f0 * 1.1, f0 * 1.45, 0.40, 3.0);
    r.air(0.05, 0.09, 0.06, 2600, 1400, 0.5, 4.0); // the breath at the front of it
    r.masterX(1.1, AIR_FAR_CALL, CRUSH_BITS + 1.0, CRUSH_HOLD);
}

// ── THE OWL ── a tawny owl's phrase, which is the one birdcall everybody can name: a short "hoo",
// a beat of NOTHING, then the long falling "hu-hoooo". The gap is the whole character — a hoot
// without it is just a note, and the pause is what makes the second half arrive.
//
// ── AND IT WAS THE MOSQUITO, twice. `growl` carries a hard-coded 5.5→8.5 Hz / 3.5% vibrato, which is
// right for a throat under load and is a culicine wingbeat on a long quiet sustained tone. So the tone
// comes off `growl`: `body` is a bare sine with no vibrato, two a fifth apart give the HOLLOW the formant
// sweep was for, and the `air` comes up because a real hoot is mostly breath.
fn mkOwl(r: *Rack) void {
    // "hoo…" — short, and already breath-led.
    r.body(0.0, 0.22, 330, 316, 0.60, 2.6);
    r.body(0.0, 0.20, 495, 474, 0.16, 3.4); // …a fifth over, for the hollow
    r.air(0.0, 0.20, 0.34, 1000, 560, 0.42, 2.6);
    // "…hu-hoooo" — falling away. Shorter than the old 0.85 s: a sustain long enough to hum along with is
    // a sustain long enough to hear a waver in.
    r.body(0.60, 0.52, 352, 268, 0.95, 1.9);
    r.body(0.60, 0.46, 528, 402, 0.22, 2.6);
    r.air(0.60, 0.44, 0.40, 1150, 520, 0.42, 2.0);
    r.body(0.62, 0.50, 176, 142, 0.28, 1.7); // an octave under, for the woody chest of it
    r.masterX(1.15, AIR_FAR_CRY, CRUSH_BITS + 1.0, CRUSH_HOLD);
}

// (THE WOLF HOWL lived here and is GONE — owner: "get rid of howl entirely". It was the "skeeter": a
// sustained ~440 Hz tone carrying `growl`s 5.5-8.5 Hz / 3.5% vibrato, i.e. culicine wingbeat with a
// wingbeat waver on it, and rolled out to 240 m so what usually arrived was a QUIET one — the exact
// condition for hearing an insect beside your ear instead of an animal across a valley. Dropping the
// fundamental to ~260 Hz and roughening the drive was tried first; the owner's answer was to cut it,
// so this is NOT a tuning problem waiting to be reopened.
//
// CUTTING IT DID NOT FIX THE MOSQUITO — it was never the wolf, it is the RECIPE SHAPE: a long, clean,
// quiet, SUSTAINED `growl` heard from a distance. The OWL was built the same way. The rule: **`growl` is
// for SHORT, LOUD, ROUGH things**; for anything sustained and quiet use `body`, which has no vibrato.)

// ── THE CRICKETS ── the other BED, and shaped nothing like the wind's, which is the point. The wind is
// ONE continuous thing; crickets are MANY discrete ones — a chirp is three to five hard ~4.5 kHz pulses,
// a fifth of a second, two or three times a second. So this is N INDIVIDUALS with their own pitch, rate,
// pulse count and place in the cycle: run them off one clock and a field becomes a rhythm section.
//
// It is also the one ambient voice rendered BRIGHT (AIR_NEAR_GRASS) — crickets are in the grass at your
// feet, and the spectral tilt is what says so. Baked twice and hard-panned like the wind (`bed`).
//
// A "MOSQUITO" COMPLAINT IS NOT THIS VOICE. It was condemned once on exactly that reasoning and restored
// unchanged; the whine was a sustained `growl` in the CALLS. A mosquito is not bright — it is a faint
// sustained tone with a ~6 Hz waver. Look at fundamentals and vibrato, not the top octave.
const CRICKETS = 7; // individuals near enough to be heard APART; past that it is a chirr, not a field
const CRICKET_SING: f32 = 0.22; // fraction of its own cycle one cricket is actually singing

fn mkCrickets(r: *Rack) void {
    var hz: [CRICKETS]f32 = undefined; // stridulation pitch — species and body size
    var rate: [CRICKETS]f32 = undefined; // chirps per second
    var at: [CRICKETS]f32 = undefined; // …and where in its own cycle this one starts
    var amp: [CRICKETS]f32 = undefined; // how near it is
    var pulses: [CRICKETS]f32 = undefined; // pulses per chirp
    var ph: [CRICKETS]f32 = [_]f32{0} ** CRICKETS; // accumulated, not f*t: at 8 s an f32 product of a
    //   4 kHz phase has lost its low bits and the pitch wobbles audibly
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
            // A saw DOWN per pulse (a hard front, a fast fade) under one arch across the whole
            // chirp: that pulse train is what makes it a chirr rather than a beep.
            const pulse = 1.0 - (p - @floor(p));
            s += mathx.sinf(std.math.tau * ph[k]) * pulse * pulse * mathx.sinf(std.math.pi * w) * amp[k];
        }
        // The seven get a resonant band so they have a BODY instead of being bare sines…
        const near = band.step(s, 4300, 0.42).bp;
        // …and under them, the hundreds too far away to hear apart: a soft filtered hiss on a slow
        // swell. Without it the field has a countable number of crickets in it, which is the tell.
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


// ── THE BANK ── one row per voice, in `Id` order.
const BANK = [NV]Row{
    // The three boots get the full four takes and the widest level jitter in the bank: they are the
    // most-repeated sound in the game by an order of magnitude, and they are the one that grates first.
    // …and LOW in the mix (owner's call). Footsteps are the sound you hear most and want to notice
    // least: they belong under the fight, marking cadence, not competing with it.
    // …and dropped a further ~40% (owner: too loud). REPETITION is why they read louder than their
    // number: a boot lands ~twice a second forever, and a sound at a given level that never stops is
    // heard as much louder than the same level heard once — which is the one thing a per-voice gain
    // cannot see. The three keep their RATIO, because walk < run < sprint is load-bearing: hearing
    // which boot you are in is part of knowing how fast you are going (see mkStepSprint).
    .{ .make = mkStepSoft, .gain = 0.075, .jit = 0.13, .vjit = 0.30, .vars = 4, .poly = 3 },
    .{ .make = mkStepHard, .gain = 0.100, .jit = 0.12, .vjit = 0.26, .vars = 4, .poly = 3 },
    .{ .make = mkStepSprint, .gain = 0.120, .jit = 0.11, .vjit = 0.24, .vars = 4, .poly = 3 },
    // A ROLL IS QUIET. You make it constantly and it is your own body on the ground, not an impact —
    // at 0.55 it was competing with the sword (owner: "too loud").
    .{ .make = mkRoll, .gain = 0.30, .jit = 0.09, .vjit = 0.14, .vars = 2 },
    // SUBTLE (owner's call). `master` normalizes every voice's peak, so a swing's LEVEL is only ever
    // this number — reshaping the whoosh made it stop sounding silly, and this is what makes it stop
    // shouting. It now sits under the hit it leads into, which is the sound that should land.
    // `poly` on the heavy too: a chained R2 must not cut its own predecessor off mid-whoosh.
    // MORE TAKES + WIDER JITTER on everything a fight repeats: repetition is its own kind of abrasive.
    .{ .make = mkSwingLight, .gain = 0.26, .jit = 0.16, .vjit = 0.22, .vars = 5, .poly = 3 },
    .{ .make = mkSwingHeavy, .gain = 0.34, .jit = 0.12, .vjit = 0.16, .vars = 4, .poly = 2 },
    .{ .make = mkHitLight, .gain = 0.68, .jit = 0.19, .vjit = 0.24, .vars = 6, .poly = 4 },
    .{ .make = mkHitHeavy, .gain = 0.82, .jit = 0.15, .vjit = 0.20, .vars = 5, .poly = 3 },
    .{ .make = mkHurt, .gain = 0.70, .jit = 0.17, .vjit = 0.20, .vars = 5 },
    .{ .make = mkHurtHeavy, .gain = 0.86, .jit = 0.13, .vjit = 0.16, .vars = 4 },
    .{ .make = mkStagger, .gain = 0.55, .jit = 0.16, .vjit = 0.20, .vars = 4 },
    // A BLOCK IS HEARD OFTEN, so it takes the footsteps' treatment: many takes, wide jitter, and a
    // level under the hit it is answering. `poly` because a warband lands three of these on you in
    // the same second and each one has to sound.
    .{ .make = mkGuardBlock, .gain = 0.62, .jit = 0.18, .vjit = 0.24, .vars = 5, .poly = 4 },
    // The BREAK is once a fight at most, and it is the cue to get out. Loud, and no jitter worth
    // the name — this one is allowed to sound like itself every time.
    .{ .make = mkGuardBreak, .gain = 0.92, .jit = 0.05, .vjit = 0.06, .vars = 2, .poly = 1 },
    .{ .make = mkRefused, .gain = 0.34, .jit = 0.06, .vjit = 0.08, .vars = 2 },
    .{ .make = mkDeath, .gain = 0.95, .jit = 0.0, .vjit = 0.0, .poly = 1 },
    .{ .make = mkRespawn, .gain = 0.55, .jit = 0.0, .vjit = 0.0, .poly = 1 },
    // THE TOADS ARE SMALL AND CLOSE. Their aggro radius is 11 m and they bite at 1.45, so 30 m of
    // reach covers everything a toad can do to you with room over — and stops a knot you cannot see
    // filling the plain with wet noises, which is what the old shared 46 m did.
    .{ .make = mkToadHop, .gain = 0.40, .jit = 0.15, .vjit = 0.26, .vars = 4, .poly = 4, .reach = 30 },
    .{ .make = mkToadLunge, .gain = 0.62, .jit = 0.12, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 34 },
    .{ .make = mkToadGape, .gain = 0.46, .jit = 0.14, .vjit = 0.20, .vars = 3, .poly = 3, .reach = 26 },
    .{ .make = mkToadChomp, .gain = 0.62, .jit = 0.13, .vjit = 0.18, .vars = 3, .poly = 3, .reach = 30 },
    .{ .make = mkToadHurt, .gain = 0.58, .jit = 0.14, .vjit = 0.20, .vars = 3, .poly = 3, .reach = 30 },
    .{ .make = mkToadDie, .gain = 0.66, .jit = 0.11, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 34 },
    // The nock/draw creak sits WELL under the loose (owner's call): it is a tell you register at
    // the edge of hearing, and the twang is the one that has to cut through.
    .{ .make = mkBowDraw, .gain = 0.17, .jit = 0.10, .vjit = 0.18, .vars = 3, .poly = 3, .reach = 44 },
    // THE TWANG REACHES FURTHEST OF THE TWO, and by design: it is the one cue in the fight that means
    // MOVE, and an archer shoots from 8-20 m — so its range carries well past its own band, where the
    // creak of the draw only has to be heard from inside it.
    .{ .make = mkBowLoose, .gain = 0.58, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 3, .reach = 64 },
    .{ .make = mkArrowHit, .gain = 0.72, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 3 },
    // The earth is the miss and therefore the one you hear most — quietest of the four, widest
    // variance, so a volley into the dirt never reads as one sample on repeat.
    // An arrow thunking off the pillar you ducked behind is the game telling you cover WORKED, so the
    // four impacts have to reach past the range they were loosed from.
    .{ .make = mkArrowDirt, .gain = 0.34, .jit = 0.15, .vjit = 0.28, .vars = 4, .poly = 4, .reach = 38 },
    .{ .make = mkArrowWood, .gain = 0.56, .jit = 0.12, .vjit = 0.20, .vars = 4, .poly = 4, .reach = 44 },
    .{ .make = mkArrowStone, .gain = 0.50, .jit = 0.13, .vjit = 0.22, .vars = 4, .poly = 4, .reach = 48 },
    .{ .make = mkArrowMetal, .gain = 0.52, .jit = 0.11, .vjit = 0.18, .vars = 3, .poly = 3, .reach = 52 },
    .{ .make = mkBoneHurt, .gain = 0.62, .jit = 0.12, .vjit = 0.20, .vars = 4, .poly = 3, .reach = 44 },
    .{ .make = mkBoneDie, .gain = 0.68, .jit = 0.09, .vjit = 0.12, .vars = 3, .reach = 54 },
    // ── THE GIANT IS THE FURTHEST-CARRYING THING IN THE WORLD, and that IS his presence. Everything
    // about him is an octave down and half a second longer (see the ogre block above); low frequencies
    // are also what survive a couple of hundred metres of air, so the physics and the character agree
    // for once. You should hear him walking long before you can see which ruin he is behind.
    .{ .make = mkOgreStep, .gain = 0.60, .jit = 0.08, .vjit = 0.20, .vars = 4, .poly = 3, .reach = 115 },
    .{ .make = mkOgreRoar, .gain = 0.80, .jit = 0.06, .vjit = 0.10, .vars = 3, .reach = 135 },
    .{ .make = mkOgreSlam, .gain = 1.00, .jit = 0.06, .vjit = 0.08, .vars = 3, .reach = 135 },
    .{ .make = mkOgreSwipe, .gain = 0.72, .jit = 0.07, .vjit = 0.12, .vars = 3, .reach = 85 },
    .{ .make = mkOgreHurt, .gain = 0.66, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3, .reach = 80 },
    .{ .make = mkOgreDie, .gain = 0.92, .jit = 0.0, .vjit = 0.0, .poly = 1, .reach = 135 },
    // ── THE KOBOLDS ── WIDE pitch jitter and four takes on everything you hear often, because a pack
    // is the worst case for repetition: five of them yipping the same recording is the single most
    // obviously fake noise a game can make, and there are up to seventy-two of these. Short reaches
    // too — they are small, and a scavenger you can hear from the far side of the plaza is an ogre.
    // The SNARL is the commit and the most PRESENT thing they do — one per flurry, carrying further than
    // the swing it precedes, because it is a cue and the swing is only a noise. SIX takes and the widest
    // pitch jitter in the bank: a warband is the worst case in the game for repetition, and this is the
    // voice you hear most of.
    .{ .make = mkKoboldSnarl, .gain = 0.62, .jit = 0.22, .vjit = 0.24, .vars = 6, .poly = 3, .reach = 58 },
    .{ .make = mkKoboldChop, .gain = 0.38, .jit = 0.22, .vjit = 0.28, .vars = 6, .poly = 4, .reach = 40 },
    // The HEAVE has to carry: it is the cue that says come back in, and you will often have backed
    // off to hear it. Loudest and furthest of the family, deliberately.
    .{ .make = mkKoboldHeave, .gain = 0.58, .jit = 0.18, .vjit = 0.24, .vars = 5, .poly = 2, .reach = 62 },
    // …and so must the CAST, for the same reason and more so — it is a thing you have to cross a
    // field to stop, so it has to be audible from where you would have to leave.
    // The REACH stays long — it is the cue to rush the back line and must read across a plaza — but the
    // level comes well down (owner: "too loud"). Those are separate dials on purpose: `reach` decides how
    // far it is still audible, `gain` how loud it is when you are standing next to him.
    .{ .make = mkKoboldCast, .gain = 0.30, .jit = 0.05, .vjit = 0.08, .vars = 3, .poly = 2, .reach = 78 },
    // The quietest positive cue in the game, and lowered twice on the owner's call. A chime is a narrow
    // tone with nothing masking it, so it carries at a level that would be inaudible on a broadband
    // voice — the number has to go further down than it looks like it should.
    .{ .make = mkKoboldHeal, .gain = 0.11, .jit = 0.06, .vjit = 0.10, .vars = 3, .poly = 3, .reach = 54 },
    .{ .make = mkKoboldWhirl, .gain = 0.42, .jit = 0.20, .vjit = 0.24, .vars = 5, .poly = 3, .reach = 44 },
    .{ .make = mkKoboldSling, .gain = 0.50, .jit = 0.13, .vjit = 0.18, .vars = 4, .poly = 4, .reach = 52 },
    .{ .make = mkKoboldBite, .gain = 0.56, .jit = 0.20, .vjit = 0.26, .vars = 6, .poly = 3, .reach = 40 },
    .{ .make = mkKoboldHurt, .gain = 0.60, .jit = 0.24, .vjit = 0.30, .vars = 6, .poly = 4, .reach = 48 },
    .{ .make = mkKoboldDie, .gain = 0.68, .jit = 0.18, .vjit = 0.22, .vars = 5, .poly = 3, .reach = 58 },
    .{ .make = mkFlaskDrink, .gain = 0.52, .jit = 0.06, .vjit = 0.10, .vars = 2, .poly = 2 },
    .{ .make = mkFlaskCycle, .gain = 0.30, .jit = 0.07, .vjit = 0.08, .vars = 2, .poly = 3 },
    // Quieter than the flask: eating is not an emergency, and the sound of it should not be one.
    .{ .make = mkEat, .gain = 0.40, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 2 },
    // A CHEST CARRIES: it is a landmark event and you will be standing over it, but somebody across the
    // plaza should hear the hinge. Almost no jitter on either — a chest opens the same way every time,
    // and this is one of the few voices in the bank that is not one of a crowd.
    .{ .make = mkChestOpen, .gain = 0.72, .jit = 0.04, .vjit = 0.06, .vars = 2, .poly = 2, .reach = 70 },
    .{ .make = mkItemGet, .gain = 0.44, .jit = 0.05, .vjit = 0.08, .vars = 3, .poly = 4 },
    .{ .make = mkKill, .gain = 0.55, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 4 },
    .{ .make = mkMenuMove, .gain = 0.30, .jit = 0.06, .vjit = 0.08, .vars = 2, .poly = 3 },
    .{ .make = mkMenuPick, .gain = 0.38, .jit = 0.03, .vjit = 0.05 },
    .{ .make = mkMenuBack, .gain = 0.32, .jit = 0.03, .vjit = 0.05 },
    // MUCH quieter (owner's call). A bed you can pick out is a bed that is too loud: its whole job
    // is to stop silence reading as broken audio, and it does that at a level you only notice when
    // it stops.
    //
    // TWO TAKES, and `gain` is now PER CHANNEL. The bed plays both at once, hard left and hard right
    // (`bed`), and the arithmetic of that is not obvious: raylib's pan law is 0.5·x·(3−x²), so a
    // hard-panned sound is ~3.2 dB LOUDER in its own ear than a centred one is in either, and two
    // uncorrelated takes sum by power rather than by amplitude. Per ear that lands 0.030 × 2 within a
    // whisker of the old centred 0.055, so this is a small real drop on top of a much wider field —
    // which is the half of "further away" that lowering it could never buy.
    .{ .make = mkWind, .gain = 0.030, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
    // …and the birds are now POSITIONED (see `ambience`), so this gain is the level of a call at the
    // near end of the band rather than of one at your ear: the distance curve takes 30-80% back off it
    // depending on where the call was rolled. Four takes and wide pitch jitter: the same bird twice
    // running is worse than no bird at all.
    // ── THE ANIMAL CALLS ── all four dropped a further ~30% on top of the family trim (owner). The
    // trim alone could not do it: a multiplier moves the whole family together, and what was wanted was
    // the ANIMALS down RELATIVE to the air they sit in — so the cut lives in these four rows, which is
    // exactly what a row's gain is for (the balance inside its own family).
    .{ .make = mkBirds, .gain = 0.20, .mix = .ambience, .jit = 0.14, .vjit = 0.22, .vars = 4, .poly = 2, .reach = 210 },
    // The FLUTED bird sits a touch under the chiptune one: it is a purer tone, and a pure tone at the
    // same peak reads louder than a pulse train does (nothing masks it).
    .{ .make = mkBirdsong, .gain = 0.17, .mix = .ambience, .jit = 0.13, .vjit = 0.22, .vars = 4, .poly = 2, .reach = 200 },
    // THE OWL IS RARE AND IT IS ALLOWED TO BE HEARD. Where a bird is scenery, one hoot every half
    // minute is an EVENT — so it goes out louder than either bird and gets three real takes, since a
    // sound you hear twice an hour must never be recognisable as the same recording.
    .{ .make = mkOwl, .gain = 0.24, .mix = .ambience, .jit = 0.08, .vjit = 0.14, .vars = 3, .poly = 2, .reach = 170 },
    // The chirr, at bed level: its whole job is that you only notice it when it stops (see mkWind's
    // row). `poly = 1` and two takes, like the wind — `bed` plays both at once and nothing overlaps.
    //
    // AND IT SITS A THIRD OF THE WIND'S NUMBER, which looks wrong and is not. `master`/`norm` set the
    // PEAK, so at 0.042 this was landing at the same peak amplitude as the bed — and it was WAY too
    // loud (owner), for two reasons that both cost about 6 dB and neither of which peak level can see:
    //   BRIGHTNESS. The chirr lives at ~4 kHz, which is the very top of human sensitivity; the wind's
    //   energy is under 1.4 kHz, where the ear gives away most of a decade. Equal amplitude at those
    //   two places is nothing like equal loudness.
    //   TRANSIENTS. A cricket is a train of hard pulse fronts, so its RMS is far below its peak and it
    //   still pops out of a mix — where smooth noise at the same peak is simply a floor.
    // So do NOT "correct" this back toward the wind's 0.030 on the grounds that they are both beds.
    .{ .make = mkCrickets, .gain = 0.010, .mix = .ambience, .jit = 0.0, .vjit = 0.0, .vars = 2, .poly = 1 },
};

/// How long each voice renders for. Kept beside the bank rather than inside each renderer so the
/// memory cost of the whole thing is readable in one place: at 22 kHz, one second is 44 KB.
fn seconds(id: Id) f32 {
    return switch (id) {
        // The two BEDS are the only long ones, and they are deliberately DIFFERENT lengths: equal
        // loops would re-trigger together for the whole session, and two textures repeating in
        // lockstep is a loop you can hear even when neither is audible on its own.
        .wind => 8.0,
        .crickets => 7.3,
        .death => 3.2,
        .owl => 1.6, // …hoo, a beat of nothing, then hu-hoooo
        .ogre_die => 2.2,
        .respawn => 1.4,
        .bone_die, .toad_die, .ogre_roar => 1.1,
        // The priest's tell runs the length of its own cast (kobold.CAST_DUR is 1.25) — a voice that
        // ended early would stop being a tell halfway through the thing it is telling you about.
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
        else => 0.5,
    };
}

// ── playback ────────────────────────────────────────────────────────────────────────────
// A `Sound` can only play once at a time — a second trigger restarts it — so each voice keeps
// `poly` ALIASES sharing one copy of the sample data, and triggers round-robin through them. That
// is what lets four toads croak over each other instead of cutting each other off.

/// HOW MANY SEPARATE TAKES a voice may be rendered as. Raised 4 → 6 for the combat set on the owner's
/// "more randomized": four takes of a sound you hear a thousand times in a session is audibly four, and
/// repetition is its own kind of abrasive. It costs only what the rows that ASK for six cost — a take is
/// rendered and stored per `vars`, not per MAX_VARS — and a voice's buffer is its own `length` seconds,
/// which for every one of these is under half a second.
const MAX_VARS = 6;
const MAX_POLY = 4;

/// THE OUTPUT LEVEL, in one place. It was stated as a literal `0.85` twice — once in `init` and
/// again in `mute`'s un-mute arm — so dialling the game down would have held only until the editor
/// was opened and closed, at which point it silently went back to the old value.
const MASTER_VOL: f32 = 0.85;

const Slot = struct {
    snd: [MAX_VARS][MAX_POLY]rl.Sound = undefined,
    owned: [MAX_VARS]rl.Sound = undefined, // alias 0 owns the data; the rest borrow it
    next: u8 = 0,
};

var slots: [NV]Slot = undefined;
var ready = false;
// The PLAYBACK rng — per-trigger pitch wobble only. Deliberately NOT seeded off the clock: two
// runs of the same fight should sound the same, for the same reason two runs place the same rocks.
var rng = mathx.Rng.init(0x50FA5);
var muted = false;

// The listener, set once a frame by game.zig. A module-level listener rather than a parameter on
// every call because the alternative is threading a camera through the toad's chomp — and every
// foe would then have to know what a camera is to make a noise.
var lisPos: rl.Vector3 = mathx.zero3;
var lisRight: rl.Vector3 = mathx.v3(1, 0, 0);

/// The DEFAULT reach, for a voice whose row does not say otherwise (see `Row.reach`, which is where
/// the interesting ones live). Only voices played through `world()` care.
const FALLOFF: f32 = 46.0;

// ── DIRECTION ───────────────────────────────────────────────────────────────────────────
// What a stereo pair can and cannot tell you, so nobody has to re-derive it:
//
//   AZIMUTH is real and cheap — an inter-channel level difference is most of how you place a sound
//   left or right, and it survives distance unchanged, so `PAN_WIDTH` applies at any range.
//   FRONT vs BACK is not. We resolve that from spectral notches the outer ear cuts into sound
//   arriving from behind, and reproducing it needs an HRTF and headphones. With two speakers and a
//   level control there is no honest cue, so `REAR_DUCK` is a NUDGE and nothing more.
//   ELEVATION is likewise unavailable, which is why nothing here reads Y.
//
/// How far off centre a source dead abeam is panned. Short of hard, deliberately: a sound that
/// vanishes from one ear reads as a broken channel, and the camera sits only a few metres behind the
/// hero, so nothing in gameplay is ever truly abeam of the ears.
const PAN_WIDTH: f32 = 0.42;
/// …and inside this radius the pan CLOSES TO CENTRE. A source on top of the listener has a bearing
/// that is arithmetically fine and perceptually meaningless: a toad chewing on your leg crosses from
/// one side of you to the other in a single frame, and panning that honestly strobes the sound
/// between the speakers. Real hearing does the same thing — at arm's length the direction of a sound
/// stops being the thing you notice about it.
const PAN_NEAR: f32 = 1.4;
/// How much a source DIRECTLY BEHIND the listener is ducked, as a fraction. Kept small on purpose,
/// and the reason is gameplay rather than physics: your own head really does shadow a rear source by
/// several dB, but this is a game where the thing behind you is the thing that kills you, so the cue
/// is set where it disambiguates a bearing and nowhere near where it could hide an ogre. Zero it and
/// nothing breaks — front and back simply become one bearing again.
const REAR_DUCK: f32 = 0.10;
/// Distance PITCH droop, at full reach. This is standing in for air absorption, which is the cue we
/// cannot have: a distant sound is dull, and raylib gives us no filter on a playing voice — only
/// volume, pitch and pan. Resampling down drags the spectral centroid the same way a lowpass does and
/// lengthens the transients besides, which is the other thing distance does to a sound. It is a proxy
/// and it is small; the voices that are ALWAYS far (the wind, the birds) get the real thing baked into
/// them instead, because a synthesized bank can simply be rendered dark.
const PITCH_DROOP: f32 = 0.05;
/// The bed's two channels, as pan values. Not 1/0: see `bed`.
const BED_PAN: f32 = 0.93;

/// PAN FOR A BEARING — and the one place the sign of it is decided, because raylib's `pan` is NOT a
/// left-to-right position. It is the LEFT channel's own gain, with the right taking `1 - pan`
/// (raudio.c's `MixAudioFrames`: `const float left = buffer->pan; const float right = 1.0f - left;`).
/// raylib's header says only "(0.5 is center)" and never which end is which, so the obvious reading is
/// backwards — and this file had it backwards, mirroring every positional sound in the game: a foe on
/// your right came out of the left speaker.
///
/// So `side` (+1 = the source is to SCREEN-RIGHT, off camera.rightXZ) has to SUBTRACT here.
fn panFor(side: f32, width: f32) f32 {
    return mathx.clampF(0.5 - width * side, 0.04, 0.96);
}

/// Build the whole bank. ~40 voices, most under half a second — a few hundred milliseconds of
/// synthesis at launch, once. Silently does nothing if the audio device refuses to open, so a box
/// with no sound card runs the game rather than failing to start.
pub fn init() void {
    rl.initAudioDevice();
    if (!rl.isAudioDeviceReady()) return;
    rl.setMasterVolume(MASTER_VOL);
    inline for (@typeInfo(Id).@"enum".fields, 0..) |f, idx| {
        const id: Id = @enumFromInt(f.value);
        const row = BANK[idx];
        var v: u8 = 0;
        while (v < row.vars) : (v += 1) {
            // Seeded per voice AND per variant, so the bank is bit-identical every launch (the
            // determinism law applies to ears too — a sound that differs run to run cannot be tuned).
            var r = Rack.init(0x9E3779B9 *% (idx + 1) +% v, seconds(id));
            row.make(&r);
            slots[idx].snd[v][0] = bake(&r);
            slots[idx].owned[v] = slots[idx].snd[v][0];
            var p: u8 = 1;
            while (p < row.poly) : (p += 1) slots[idx].snd[v][p] = rl.loadSoundAlias(slots[idx].owned[v]);
        }
        slots[idx].next = 0;
    }
    ready = true;
}

/// Upload the rack as a mono 16-bit Sound. The staging buffer is BSS and raylib COPIES on load, so
/// nothing here is allocated and nothing has to be freed on the way out.
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
    ready = false;
    rl.closeAudioDevice();
}

/// Where the ears are. Call once a frame, after the camera has settled — `right` is the camera's
/// ground-plane screen-right (camera.rightXZ), which is what the pan is measured against.
pub fn listen(pos: rl.Vector3, right: rl.Vector3) void {
    lisPos = pos;
    lisRight = right;
}

/// ONE VOICE'S DIALS, for the editor's JUKEBOX to print beside whatever it is auditioning: the
/// numbers you need in front of you while judging a sound are the same ones you would be retuning.
/// A VIEW of the row rather than the row itself — `make` is a renderer pointer nothing outside this
/// file can do anything with, and a public `Row` is an invitation to build a second bank.
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

/// Silence the world without tearing the device down — the editor uses it, since a map you are
/// dressing should not be croaking at you.
pub fn mute(on: bool) void {
    if (muted == on) return;
    muted = on;
    if (ready) rl.setMasterVolume(if (on) 0.0 else MASTER_VOL);
}

/// Trigger a voice at the listener (UI, and anything that happens TO the player). `vol` and `pan`
/// scale the row's own gain; the per-trigger pitch jitter is applied here, which is the thing that
/// stops a hundred footsteps reading as one sample on a loop.
pub fn play(id: Id) void {
    emit(id, 1.0, 0.5, 1.0);
}

/// …with an explicit strength, for the beats that come in degrees (a light vs a heavy).
pub fn playAt(id: Id, vol: f32) void {
    emit(id, vol, 0.5, 1.0);
}

/// Trigger a voice somewhere in the WORLD: attenuated by distance and panned across the camera.
/// Beyond FALLOFF it costs nothing at all — the test is two subtractions before any state is touched.
pub fn world(id: Id, at: rl.Vector3) void {
    if (!ready) return;
    const row = BANK[@intFromEnum(id)];
    // SQUARED for the reject, and that is what makes the early-out the cheap thing this voice's own
    // test claims it is: `distXZ` is a square ROOT, and it was being paid on every call by every
    // foe on the map — including the great majority that are out of earshot and return one line
    // later. The root is now only taken by the sounds that will actually be heard.
    const d2 = mathx.dist2XZ(at, lisPos);
    if (d2 > row.reach * row.reach) return;
    const d = @sqrt(d2);
    // Inverse-square-ish, squared again at the tail so distant sounds fall away rather than
    // hanging at a constant murmur across the whole plain. Over the voice's OWN reach now, so the
    // curve has the same shape for a croak and for a giant and only its scale differs.
    const k = 1.0 - d / row.reach;
    const near = d / row.reach; // 0 underfoot → 1 at the edge of earshot
    const to = mathx.dirXZ(lisPos, at);
    const side = to.x * lisRight.x + to.z * lisRight.z;
    // FORWARD is derived from the stored right vector rather than being a third thing to pass in and
    // keep in step: on the ground plane `perpXZ(right)` IS camera-forward for this codebase's basis
    // (right is (−cos yaw, 0, sin yaw), so its perpendicular is (sin yaw, 0, cos yaw) = headingDir).
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
    // Round-robin the alias AND the variant off one counter: `poly` and `vars` are coprime often
    // enough that stepping both together decorrelates which take you hear from which slot it lands
    // in, and when they are not, the pitch jitter covers it.
    const pick = s.next;
    s.next = (s.next + 1) % (row.vars * row.poly);
    trigger(s.snd[pick % row.vars][pick / row.vars % row.poly], row, vol, pan, pitchScale);
}

/// Set one alias up and start it. Split out of `emit` because the BED does not round-robin — it plays
/// two specific takes at two specific pans — and the four raylib calls that turn a row plus a volume
/// into a playing sound must not exist twice (the wind bed was the one voice whose level was applied
/// outside this path once already, and it silently ignored how a row's gain is meant to map).
fn trigger(snd: rl.Sound, row: Row, vol: f32, pan: f32, pitchScale: f32) void {
    // Pitch AND level wobble, both per trigger. The level one is deliberately one-sided-ish (it
    // only ever takes away) so a jittered step can never be LOUDER than the tuned gain — variance
    // must not turn into the occasional bang.
    const vj = 1.0 - @abs(rng.signed()) * row.vjit;
    // …and the FAMILY trim, here rather than baked into each row's gain: this is the one place a
    // row's number becomes a raylib volume, so it is the only place the two can be composed without
    // one of the forty-seven rows quietly missing out (see `Submix`).
    rl.setSoundVolume(snd, mathx.clampF(row.gain * submixTrim(row.mix) * vol * vj, 0, 1));
    rl.setSoundPitch(snd, (1.0 + rng.signed() * row.jit) * pitchScale);
    rl.setSoundPan(snd, pan);
    rl.playSound(snd);
}

/// ── THE BED, IN TWO CHANNELS ────────────────────────────────────────────────────────────
/// Play a voice's first two takes at once, one pushed left and one right. This is the whole of what
/// makes an ambient bed ENVELOPING rather than a thing in front of you, and it is not a volume
/// question: two ears fed the same buffer hear ONE SOURCE, located between the speakers, however
/// quiet it is. Feed them two independently-seeded renders of the same recipe and there is no single
/// place for the sound to be, so it stops having a location and becomes the air you are standing in.
/// (Same reason the takes' gust clocks are rolled per take — see mkWind.)
///
/// Not panned fully to 1.0 / 0.0: a channel that is completely absent from one ear reads as a fault
/// rather than as width, and it collapses badly the moment somebody listens on one speaker.
fn bed(id: Id, vol: f32) void {
    if (!ready or muted) return;
    const idx = @intFromEnum(id);
    const row = BANK[idx];
    const s = &slots[idx];
    trigger(s.snd[0][0], row, vol, BED_PAN, 1.0);
    if (row.vars > 1) trigger(s.snd[1][0], row, vol, 1.0 - BED_PAN, 1.0);
}

/// ── THE LOOPING BEDS ── played as a hard-panned PAIR (see `bed`) and re-triggered when they run out.
/// Two of them now, moving air and the insect chirr, and they are separate VOICES rather than one
/// buffer holding both for the same reason the birds were lifted out of the wind: baked together they
/// would loop together, and two textures that repeat in lockstep is a loop you can hear. Their lengths
/// are deliberately coprime-ish (8.0 / 7.3) so the pair never re-aligns inside a session.
const BEDS = [_]Id{ .wind, .crickets };

/// ── ONE SPARSE AMBIENT CALL ── which voice, how long between them, and how far out it is rolled.
///
/// A TABLE, because there are three of these now and they differ in nothing but those numbers.
/// Written out per voice it is three copies of the same clock, and the day one of them silently stops
/// firing there is nothing to compare the broken one against.
///
/// THE GAPS ARE LONG AND WIDELY SPREAD, and that is the whole design: the point of a call is that you
/// NOTICE it, which needs enough silence in front of it that you had stopped expecting one. The rarer
/// the voice, the wider its band — a bird every ten seconds is scenery, an owl every minute is
/// the world telling you where you are.
///
/// AND EACH IS ROLLED A DISTANCE, never played at the ear. `world()` then puts it at a bearing and at
/// the level that distance earns, so what you get across a session is calls from all over the plain at
/// every level from clear to barely-there. Nothing is rolled nearer than `distLo`: there is no bird you
/// are standing next to in this world, and pretending otherwise is what once put them inside your head.
const Call = struct {
    id: Id,
    gapLo: f32,
    gapHi: f32,
    distLo: f32,
    distHi: f32,
    /// How long the FIRST one holds off. Staggered across the table so they don't all land together
    /// in the first half-minute — and all past the menu, so none of them fires behind the pause card.
    first: f32,
};

const CALLS = [_]Call{
    .{ .id = .birds, .gapLo = 9, .gapHi = 26, .distLo = 26, .distHi = 120, .first = 4 },
    .{ .id = .birdsong, .gapLo = 11, .gapHi = 31, .distLo = 30, .distHi = 140, .first = 9 },
    // Rarer than either bird by a factor of three, and further out: an owl is a thing you hear
    // occasionally from somewhere in the ruins, not a resident of the tree you are standing under.
    // …and the RAREST and FURTHEST of the calls. Nothing was re-tuned to inherit that when the wolf was
    // cut: "furthest-carrying" is a consequence of a voice's character, not a post to be filled, and
    // manufacturing a replacement for it is how the mosquito got made.
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
    // Take 0 is the LEFT channel of a bed and both takes are the same length, so asking raylib whether
    // that one is still running is the whole re-trigger test for the pair.
    for (BEDS) |b| {
        if (!rl.isSoundPlaying(slots[@intFromEnum(b)].snd[0][0])) bed(b, 1.0);
    }
    // Every sparse call rides its OWN clock rather than a bed's loop: baked into the wind buffer the
    // birds repeated with it, five phrases in the same order for ever (see mkWind).
    for (CALLS, 0..) |c, i| {
        callWait[i] -= dt;
        if (callWait[i] > 0) continue;
        callWait[i] = rng.range(c.gapLo, c.gapHi);
        const a = rng.angle();
        const d = rng.range(c.distLo, c.distHi);
        world(c.id, mathx.v3(lisPos.x + mathx.cosf(a) * d, lisPos.y, lisPos.z + mathx.sinf(a) * d));
    }
}

/// WHAT AN ARROW ENDED UP IN → which impact you hear. `null` is the bare earth (the miss), which is
/// the commonest case by far and has its own duller voice. It lives here, beside the four voices it
/// chooses between, rather than as a switch in the frame loop: the loop's version collapsed `null`
/// and `.stone` together with an `orelse` and then had to re-test for null INSIDE the `.stone` arm
/// to pull them apart again, which is a mapping written twice and legible neither time.
pub fn arrowImpact(surf: ?@import("collision.zig").Surface) Id {
    const s = surf orelse return .arrow_dirt;
    return switch (s) {
        .stone => .arrow_stone,
        .wood => .arrow_wood,
        .metal => .arrow_metal,
    };
}

// ── invariants under test (pure synthesis — no device needed) ───────────────────────────
comptime {
    // The table is positional: a voice added to `Id` without a row lands on its neighbour's
    // renderer, which is silent-and-wrong rather than a compile error unless this is here.
    std.debug.assert(BANK.len == NV);
    // …and a row's `vars`/`poly` INDEX a fixed [MAX_VARS][MAX_POLY] array. Nothing checked them,
    // so `.vars = 5` on any row would have written one Sound past the end of that voice's slot and
    // into the next one's — a silent out-of-bounds in a release build, from a one-character edit to
    // a table that reads like pure tuning data. `poly` must also be at least 1 or the voice would
    // be baked and then never given an alias to play through.
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
    // Catches the two ways a recipe fails without anyone noticing: a layer that cancels itself to
    // nothing, and one that runs away and clips the whole buffer to a square wave.
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
    // `world` is the one path that can be called thousands of times a frame by a knot of foes, so
    // its early-out has to be real; and a pan that leaves the 0..1 range is a raylib assert.
    listen(mathx.zero3, mathx.v3(1, 0, 0));
    try std.testing.expect(mathx.distXZ(mathx.v3(FALLOFF + 1, 0, 0), lisPos) > FALLOFF);
    const near = 1.0 - 0.0 / FALLOFF;
    const far = 1.0 - (FALLOFF * 0.9) / FALLOFF;
    try std.testing.expect(near * near > far * far * 50.0); // a real curve, not a plateau
}

test "PAN IS THE LEFT CHANNEL'S GAIN — a source on your right must pan DOWN, not up" {
    // THE bug this pins, and it is worth a test of its own because the mistake is the natural reading
    // of the API. raylib's mixer takes `pan` as the LEFT gain and gives the right `1 - pan`
    // (raudio.c MixAudioFrames), while its header says only "(0.5 is center)". So `0.5 + width*side`
    // — which is what any of us would write — sends a foe on your right out of the LEFT speaker, and
    // every positional sound in the game was mirrored. If somebody ever "fixes" the sign back, this
    // fails instead of the game quietly lying about which way to turn.
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
    // A bearing at arm's length is arithmetically fine and perceptually meaningless: a toad chewing
    // your leg crosses from one side to the other in a frame, and panning that honestly flicks the
    // sound between the speakers.
    const onTop = PAN_WIDTH * mathx.smoothstep(0, PAN_NEAR, 0.05);
    const clear = PAN_WIDTH * mathx.smoothstep(0, PAN_NEAR, 4.0);
    try std.testing.expect(onTop < 0.02); // effectively centred
    try std.testing.expectApproxEqAbs(PAN_WIDTH, clear, 1e-6); // and full width once it is off you
}

test "reach is per VOICE: a giant carries, a toad does not, a bird carries furthest" {
    // The soundscape's whole legibility rests on this ordering — one shared range for everything is
    // how you end up hearing toads through terrain and missing a slam across the plaza.
    const reach = struct {
        fn of(id: Id) f32 {
            return BANK[@intFromEnum(id)].reach;
        }
    }.of;
    try std.testing.expect(reach(.toad_chomp) < reach(.bow_loose));
    try std.testing.expect(reach(.bow_loose) < reach(.ogre_slam));
    try std.testing.expect(reach(.ogre_slam) < reach(.birds));
    // The BIRDS carry furthest of anything in the world, and the ordering ends there.
    // The archer's TWANG is the cue to move and must outrange the creak of the draw that precedes it.
    try std.testing.expect(reach(.bow_loose) > reach(.bow_draw));
    // A toad's world is 11 m wide (its aggro radius), so its voice must comfortably cover that and
    // not much more.
    try std.testing.expect(reach(.toad_chomp) > 12.0 and reach(.toad_chomp) < 40.0);
    // …and every voice has to be able to be heard at all.
    for (BANK) |row| try std.testing.expect(row.reach > 1.0);
}

test "every sparse call is rolled INSIDE its own reach, and none of them is rolled at your ear" {
    // Two ways the CALLS table can be wrong and neither shows on screen: a `distHi` past the voice's
    // own `reach` makes the far half of the band SILENCE (`world` early-outs, so the call simply never
    // happens and the clock has already been spent), and a `distLo` near zero puts the thing in your
    // head — which is the bug the birds were moved off `play` to fix in the first place.
    for (CALLS) |c| {
        const row = BANK[@intFromEnum(c.id)];
        try std.testing.expect(c.distHi < row.reach);
        try std.testing.expect(c.distLo > 10.0 and c.distLo < c.distHi);
        // …and a gap band that is a real band, so no voice fires on a fixed metronome.
        try std.testing.expect(c.gapLo > 0 and c.gapHi > c.gapLo * 1.5);
        try std.testing.expect(c.first > 1.0); // never behind the pause card at launch
    }
    // RARITY ORDER, which is the whole shape of the canopy: birds are scenery, the owl is the event.
    // Pinned because it is the thing a retune would quietly invert. (There was a third rung — the wolf,
    // rarer again — and it is gone; the owl inherits being the rarest without being re-tuned for it.)
    try std.testing.expect(CALLS[2].gapLo > CALLS[0].gapLo * 2.0); // owl vs birds
    try std.testing.expect(CALLS.len == 3);
}

test "THE BACKGROUND IS BACKGROUND — the ambience trim, and only the ambience" {
    // Every bed and every sparse call pays the trim: an ambient voice left on `.game` is the one that
    // ends up loudest in its own group with nothing to compare it against.
    for (BEDS) |b| try std.testing.expectEqual(Submix.ambience, BANK[@intFromEnum(b)].mix);
    for (CALLS) |c| try std.testing.expectEqual(Submix.ambience, BANK[@intFromEnum(c.id)].mix);
    try std.testing.expect(TRIM_AMBIENCE > 0 and TRIM_AMBIENCE < 1.0);

    // AND NOTHING ELSE DOES — asserted so the reverted `.creature` trim (see `Submix`) cannot come back
    // by accident. Exactly the beds and the calls are trimmed; no combat voice is.
    var trimmed: usize = 0;
    for (BANK) |row| {
        if (row.mix == .ambience) trimmed += 1;
    }
    try std.testing.expectEqual(BEDS.len + CALLS.len, trimmed);
    for ([_]Id{ .toad_chomp, .toad_die, .ogre_slam, .ogre_roar, .bone_die, .hit_heavy, .hurt }) |id| {
        try std.testing.expectEqual(Submix.game, BANK[@intFromEnum(id)].mix);
    }

    // THE BEDS SIT UNDER THE CALLS, which is what makes one a floor and the other an event: a bed you
    // can pick out is a bed that is too loud.
    var loudBed: f32 = 0;
    for (BEDS) |b| loudBed = mathx.maxF(loudBed, BANK[@intFromEnum(b)].gain);
    for (CALLS) |c| try std.testing.expect(BANK[@intFromEnum(c.id)].gain > loudBed);
}

test "every BED has two takes to pan, and they do not loop in lockstep" {
    // BEDS MUST NOT SHARE A LENGTH: equal-length beds re-trigger on the same frame for the whole
    // session, and two textures repeating in lockstep is a loop you can hear even when neither is
    // audible alone. Stated for however many beds there are rather than pinning the count.
    // (This block claimed the crickets had been REMOVED. They are in `BEDS` — they were deleted once
    // and restored unchanged, and the comment did not come back with them.)
    var i: usize = 0;
    while (i < BEDS.len) : (i += 1) {
        // Played through `bed`, which needs two takes to have two channels to pan hard apart.
        try std.testing.expect(BANK[@intFromEnum(BEDS[i])].vars >= 2);
        var j = i + 1;
        while (j < BEDS.len) : (j += 1) try std.testing.expect(seconds(BEDS[i]) != seconds(BEDS[j]));
    }
}

test "a source BEHIND you is ducked, but nowhere near enough to hide it" {
    // Front/back cannot be resolved by a stereo pan (it takes the outer ear's own spectral notches),
    // so this is a nudge. It is deliberately tiny: in a game where the thing behind you is the thing
    // that kills you, a rear cue that actually worked would be a bug.
    const ahead = 1.0 - REAR_DUCK * 0.5 * (1.0 - 1.0);
    const behind = 1.0 - REAR_DUCK * 0.5 * (1.0 - -1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), ahead, 1e-6);
    try std.testing.expect(behind < ahead);
    try std.testing.expect(behind > 0.85); // still unmistakably audible
}

test "the BED's two takes are decorrelated — that IS its width, and it is checkable" {
    // The claim `bed` rests on: two ears fed the same buffer hear one source between the speakers,
    // and two independent renders of the same recipe have no single place to be. If the takes ever
    // came out correlated — a shared seed, a gust clock that is a pure function of `t`, a `make` that
    // stopped drawing from the rng — the bed would silently collapse back to a point and nothing on
    // screen would say so. Measured as the zero-lag normalised cross-correlation of the takes that
    // actually ship, seeded with `init`'s own expression.
    // usize, like `init`'s loop index: `Id`'s tag type is a u6, and the seed expression below
    // overflows it long before it reaches Rack.init.
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
    // `mkWind`'s gain came down from 0.055 to 0.030 and the comment claims that lands within a
    // whisker of the old per-ear level while being a small real drop. That is not obvious arithmetic —
    // raylib's pan law makes a hard-panned take LOUDER in its own ear than a centred one is in either,
    // and two uncorrelated takes sum by power — so it is asserted rather than believed.
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
    // The BED is noise, so its brightness is measurable: a zero-crossing rate is the cheap honest
    // proxy for spectral centroid, and for a noise band it tracks it closely. Held against the NEAR
    // voices it shares the mix with — that gap is the whole of "the wind sounds further away", and it
    // is a thing lowering the gain could never have produced.
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

    // THE BIRDS ARE NOT MEASURED THIS WAY, and the reason is worth writing down: a chirp is PITCHED,
    // so its zero-crossing rate is set by its fundamental and barely moves when you take the reedy
    // harmonics off the top. Measured, the call came out at 5026 crossings/sec against a sword
    // swing's 5032 — an assertion that passes by a tenth of a percent is not a test, it is a
    // coincidence waiting to be retuned. So the bird's distance is held where the decision actually
    // lives: the cutoff it is rendered through.
    try std.testing.expect(AIR_FAR_CALL < AIR_NEAR_DARKEST);
    try std.testing.expect(AIR_FAR_BED < AIR_FAR_CALL); // the bed is the furthest thing in the world
    // The two big LOW cries are darker again than a bird's whistle — they are further out AND low to
    // begin with, so what crosses the plain is the fundamental and almost none of the throat.
    try std.testing.expect(AIR_FAR_CRY < AIR_FAR_CALL);
    try std.testing.expect(AIR_FAR_CRY < AIR_NEAR_DARKEST);
    // …and neither so dark it stops being the thing it is: a bird still has to be a whistle (its band
    // tops out at 2500 Hz) and wind still has to have air in it, not just rumble.
    try std.testing.expect(AIR_FAR_CALL > 1200 and AIR_FAR_BED > 800);
    // THE CRICKETS ARE THE EXCEPTION, and the ONE ambient voice on the near side of the line: they are
    // in the grass at your feet, and the spectral tilt is the only thing that says so. Rendered as dark
    // as the wind the whole insect field moves to the horizon — which is not where crickets are.
    try std.testing.expect(AIR_NEAR_GRASS > AIR_NEAR_DARKEST);
    // …and every one of the FAR voices stays on the far side of it.
    for ([_]f32{ AIR_FAR_BED, AIR_FAR_CALL, AIR_FAR_CRY }) |cut| {
        try std.testing.expect(cut < AIR_NEAR_DARKEST);
    }
}

test "NO SUSTAINED CALL SITS IN THE MOSQUITO BAND" {
    // WHY THIS TEST EXISTS, since the voice it was written for has been deleted: the wolf howl read to
    // the owner as "a skeeter", and the mechanism generalises. `growl` puts a 5.5-8.5 Hz vibrato at 3.5%
    // depth on EVERY voice it makes, so any voice that HOLDS a near-pure tone near culicine wingbeat
    // (~350-650 Hz) is a mosquito with extra steps — and a call rolled out to a couple of hundred metres
    // arrives quiet, which is exactly the condition for hearing an insect at your ear rather than an
    // animal across a valley. The howl was cut rather than retuned, but the trap is still in `growl` and
    // the next long cry somebody writes will walk into it.
    //
    // So what is pinned is the RULE, on the surviving long voices: no ambient call may be both SUSTAINED
    // and in that band.
    const MOSQUITO_LO: f32 = 350.0;
    const HELD: f32 = 0.55; // a "held" cry — anything shorter is a hoot or a chirp, and safe
    for (CALLS) |c| {
        if (seconds(c.id) < HELD) continue;
        // The OWL is the only one left over the threshold, and it is legal because it is a two-note
        // HOOT: its notes are 0.26 s and 0.85 s of a 1.6 s buffer with silence between them, so there is
        // no continuous tone for the vibrato to turn into a wingbeat — which is precisely why it never
        // sounded like an insect and the howl did. Asserted as a property of its LENGTH rather than by
        // reading its pitches, because the pitches are inside the recipe and the shape is what matters.
        try std.testing.expect(seconds(c.id) < 2.0);
    }
    // …and the band itself is where it says it is, so the number above cannot silently drift.
    try std.testing.expect(MOSQUITO_LO > 300.0 and MOSQUITO_LO < 500.0);
}

test "THE NOISE FLOOR IS THE CRUSH'S, and it has to stay down" {
    // Owner's note was "all sfx have too much hiss", and the dial that looks responsible — the tape
    // `hiss()` layer — is ~28 dB below the thing actually making the noise. It is the CRUSH: see
    // CRUSH_BITS for the full arithmetic. Pinned here in two ways so neither half can come back.

    // 1. THE CONSTANTS, exactly. One quantiser step is the noise floor's whole story, and it is
    //    computable without rendering anything: step = 1 / (2^bits · 0.5).
    const step = 1.0 / (std.math.pow(f32, 2.0, CRUSH_BITS) * 0.5);
    const stepDb = 20.0 * std.math.log10(step);
    try std.testing.expect(stepDb < -36.0); // …at 5.5 bits this was −27 dB, and audibly so
    // The textbook ±1 LSB TPDF is a SIXTEEN-BIT rule; at this step size it doubled the quantiser's
    // own noise power for linearity nobody can hear. Anything at or over 1 is that fault returning.
    try std.testing.expect(DITHER_LSB < 0.6 and DITHER_LSB > 0.15); // …but still enough to break a staircase
    // The HOLD is the lo-fi character and is deliberately NOT the thing that was turned down — it
    // costs no noise floor at all, so a future "make it crunchier" belongs here and not in the bits.
    try std.testing.expect(CRUSH_HOLD >= 2);

    // 2. THE CHAIN ITSELF, measured on a CONTROLLED voice rather than by sweeping the bank. A
    //    bank-wide "quietest window" test cannot work: the two BEDS are continuous by design, so
    //    their quietest stretch is full signal and they would fail a floor test while being exactly
    //    right. What is wanted is the floor `master` leaves BEHIND a sound, so: one short thump at
    //    the head of a long buffer, mastered like anything else, and measure the dead air after it.
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
    // MEASURED: −34.7 dBFS at 5.5 bits with ±1 LSB dither, −50.8 dBFS as it stands. That 16 dB is
    // the whole of the owner's "all sfx have too much hiss", and it was identical for all 47 voices
    // because `norm` runs after the crush — hence "all", rather than a list of three.
    try std.testing.expect(tailDb < -44.0);
}
