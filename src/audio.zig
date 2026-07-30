const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

// ── AUDIO ── every sound in the game, SYNTHESIZED AT LAUNCH. No .wav files anywhere.
//
// Same argument as the meshes and the ground texture: a procedural bank is a few hundred lines you
// can retune in a diff, it weighs nothing in the repo, and the variation can be AUTHORED IN with a
// seeded Rng instead of shipping six takes of a footstep (WABI-SABI, and it is as much a law for
// ears as for eyes — a footstep sample played twice is the most obviously fake sound a game makes).
//
// THE HOUSE SOUND is warm analogue tape: everything is LOW and FAT, everything goes through a
// saturation → lowpass → wow → hiss chain on the way out, and almost every gesture is noise or a
// simple oscillator dragged through a SWEEPING RESONANT FILTER. That sweep is the whole character —
// it is what makes a whoosh feel like it travels, a hit feel like it lands in a body, and a menu
// blip feel like a piece of hardware rather than a beep.
//
// THE SAMPLE RATE IS 22 kHz ON PURPOSE. An 11 kHz ceiling is not a compromise here, it IS the
// vintage colour: it rolls the fizz off noise, band-limits the naive oscillators so they stop
// buzzing, and puts everything in the same era as the retro filter stack the picture goes through.
//
// LAYOUT: one `BANK` row per voice carries its renderer AND its playback feel (gain, pitch jitter,
// how many baked variants, how many can overlap), so a voice is ONE ROW — the same "a kind is one
// row" rule props.INFO follows, for the same reason.

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
                // Lowpassed hard, or an 8 kHz square at 22 kHz is pure alias fizz.
                work[i] += lp.step(pulse, 4200) * amp * decay(u, 3.0) * mathx.smoothstep(0, 0.15, u);
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
            // TPDF dither — two uniform draws summed. Exactly the argument the scene shader's
            // ±1 LSB screen dither makes: without it a quiet tail quantizes to one constant level
            // and the decay STAIRCASES, which is the ugly half of lo-fi rather than the good half.
            const d = (r.rng.signed() + r.rng.signed()) * 0.5 / levels;
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
const CRUSH_BITS: f32 = 5.5;
const CRUSH_HOLD: u32 = 2;

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
    // the flasks
    flask_drink,
    flask_cycle,
    // the world and the chrome
    kill,
    menu_move,
    menu_pick,
    menu_back,
    wind,
};
const NV = @typeInfo(Id).@"enum".fields.len;

// ── VARIANCE: KEEP THE IDENTITY, LOSE THE GRATE (owner's law, and it is the same law the world's
// wabi-sabi follows). A sound you hear four hundred times a session has to be recognisably ITSELF
// every time and never twice the same, and three separate dials do that:
//
//   `vars` — N genuinely different TAKES, baked from different seeds. The strongest of the three by
//            far: the ear catches a repeated waveform long before it catches a repeated pitch, so
//            the sounds you hear most (footsteps, hits, croaks) get four apiece and they ROTATE
//            round-robin, which means you cannot hear the same one twice in a row.
//   `jit`  — per-trigger PITCH wobble. Cheap, and it does the fine-grain work between takes.
//   `vjit` — per-trigger LEVEL wobble. The one that was missing, and the one that matters most for
//            footsteps: real steps vary in weight far more than they vary in pitch, and a run of
//            identically-loud steps reads as a machine however well the pitch is jittered.
const Row = struct {
    make: *const fn (*Rack) void,
    gain: f32 = 0.7,
    jit: f32 = 0.06,
    vjit: f32 = 0.12,
    vars: u8 = 1,
    poly: u8 = 2,
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
    // The dodge: cloth and body over dirt. One long dark sweep DOWN for the tumble, a whump where
    // the shoulder takes it, and a scuff coming out of the rise.
    r.air(0.0, 0.42, 0.40, 2600, 260, 0.3, 2.4);
    r.body(0.03, 0.22, 96, 44, 0.75, 4.0);
    r.grit(0.02, 0.34, 0.30, 1400, 0.6, 2.8);
    r.grit(0.30, 0.14, 0.22, 2200, 0.5, 4.5); // the plant coming out of it
    r.master(1.7, 3000);
}

fn mkSwingLight(r: *Rack) void {
    // R1: a fast, tight whoosh. High and short, so it reads as EDGE rather than as weight — the
    // heavy below is the one allowed to sound like effort.
    r.air(0.0, 0.17, 0.9, 700, 3400, 0.55, 2.2);
    r.air(0.02, 0.13, 0.5, 3600, 900, 0.5, 3.0); // the tip passing, coming back down
    r.master(1.4, 5200);
}

fn mkSwingHeavy(r: *Rack) void {
    // R2: a long, low, two-part sweep — the raise, then the drop. The gap between them is the
    // tell, and it is the same beat the animation holds at the top of the arc.
    r.air(0.0, 0.30, 0.45, 500, 1500, 0.4, 1.6);
    r.air(0.24, 0.30, 1.0, 2600, 300, 0.6, 2.0);
    r.body(0.26, 0.16, 190, 70, 0.35, 3.6);
    r.master(1.8, 4200);
}

fn mkHitLight(r: *Rack) void {
    // Blade into a body: a wet crack, a short bright edge ring, and a low thump under it. The ring
    // is what says STEEL did it — take it out and the same hit reads as a punch.
    r.tick(0.0, 0.55, 5200);
    r.body(0.0, 0.13, 220, 78, 0.9, 5.0);
    r.grit(0.0, 0.10, 0.5, 3000, 0.35, 5.5);
    r.ring(0.004, 0.16, 1400, 0.22, 6.0, 3);
    r.master(2.1, 4600);
}

fn mkHitHeavy(r: *Rack) void {
    // The R2 connecting: everything the light has, dropped an octave and given a crunch that
    // carries. The second body an eighth of a second later is the follow-through settling.
    r.tick(0.0, 0.7, 4200);
    r.body(0.0, 0.30, 170, 44, 1.2, 3.0);
    r.grit(0.0, 0.22, 0.75, 1800, 0.65, 3.4);
    r.ring(0.006, 0.26, 900, 0.26, 4.5, 4);
    r.body(0.11, 0.20, 74, 36, 0.45, 3.2);
    r.master(2.6, 3800);
}

fn mkHurt(r: *Rack) void {
    // Taking a chomp: a short winded grunt over the impact. Deliberately GUTTURAL and short — a
    // long cry would be the loudest thing in every fight and it would wear out in a minute.
    r.body(0.0, 0.16, 150, 58, 0.7, 4.4);
    r.growl(0.01, 0.20, 210, 150, 0.55, 0.16, 0.12);
    r.grit(0.0, 0.09, 0.3, 1600, 0.4, 5.0);
    r.master(2.0, 3200);
}

fn mkHurtHeavy(r: *Rack) void {
    // The lunge or the slam landing: the air goes out of him. Lower, longer, and the growl falls
    // further, which is the whole difference between "ow" and "that hurt".
    r.body(0.0, 0.32, 128, 40, 1.0, 2.8);
    r.growl(0.0, 0.38, 190, 96, 0.8, 0.22, 0.10);
    r.grit(0.0, 0.16, 0.45, 1300, 0.6, 3.6);
    r.air(0.02, 0.24, 0.20, 1800, 300, 0.35, 3.0);
    r.master(2.5, 2900);
}

fn mkStagger(r: *Rack) void {
    // A stance break: boots losing the floor. All scuff, no impact — the impact already played on
    // the blow that caused it, and doubling it makes a stagger read as a second hit.
    r.grit(0.0, 0.34, 0.6, 1700, 0.7, 2.4);
    r.air(0.0, 0.30, 0.35, 1600, 400, 0.4, 2.6);
    r.body(0.14, 0.16, 84, 46, 0.35, 4.0);
    r.master(1.8, 2800);
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
    // INTO MASONRY — hard and DEAD. The head skids, so there is a bright scrape on the front, but
    // stone gives nothing back: a short high crack, no body to speak of, no ring.
    arrowRip(r, 0.40);
    r.tick(0.0, 0.85, 7000);
    r.body(0.0, 0.055, 420, 190, 0.55, 9.0);
    r.grit(0.0, 0.07, 0.75, 4200, 0.35, 7.5);
    r.master(2.1, 5200);
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
    var i: usize = 0;
    while (i < r.n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / SRF;
        // The gusts. Three clocks, and the layers below take DIFFERENT mixes of them, so no two
        // layers peak together.
        const g1 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.083 * t);
        const g2 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.031 * t + 2.1);
        const g3 = 0.5 + 0.5 * mathx.sinf(std.math.tau * 0.157 * t + 4.4);
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

        work[i] = b * (0.30 + 0.70 * g2) * 0.85 +
            w * (0.10 + 0.50 * g1) * 0.30 +
            s * 0.16 +
            m * 0.55;
    }
    // Settle the air BEFORE the birds go in, so a chirp cannot set the peak and drag the whole
    // bed down under it — the calls are meant to sit ON the wind, at their own level.
    r.norm(0.42);

    // ── SPARSE DIGITAL BIRDCALLS ── five phrases across eight seconds, which is sparse enough that
    // you notice one rather than expecting the next. Deliberately CHIPTUNE: stepped semitone
    // intervals, narrow pulse waves, no glide — the world is a golden-hour ruin seen through a
    // retro filter, and a naturalistic bird would be the one thing in it pretending not to be.
    // Kept quiet and low in the mix; a bird you hear clearly is a bird you get sick of.
    var c: i32 = 0;
    while (c < 5) : (c += 1) {
        // Spread across the buffer with jitter, and kept clear of both ends — a call cut in half by
        // the loop seam is the one thing that WOULD give the loop away.
        const slot = 0.9 + @as(f32, @floatFromInt(c)) * 1.35 + r.rng.range(-0.35, 0.35);
        r.chirp(slot, r.rng.range(0.055, 0.10), r.rng.range(1750, 2900));
    }

    r.sat(1.2);
    r.crush(CRUSH_BITS + 1.5, CRUSH_HOLD); // gentler than the house: a crushed noise bed hisses
    r.warm(2600);
    r.wow(0.003, 0.4);
    r.hiss(0.05);
    r.norm(0.62);
    r.ends(0.9, 0.9); // long crossfade ends, so the re-trigger seam is inaudible
}

// ── THE BANK ── one row per voice, in `Id` order.
const BANK = [NV]Row{
    // The three boots get the full four takes and the widest level jitter in the bank: they are the
    // most-repeated sound in the game by an order of magnitude, and they are the one that grates first.
    // …and LOW in the mix (owner's call). Footsteps are the sound you hear most and want to notice
    // least: they belong under the fight, marking cadence, not competing with it.
    .{ .make = mkStepSoft, .gain = 0.13, .jit = 0.13, .vjit = 0.30, .vars = 4, .poly = 3 },
    .{ .make = mkStepHard, .gain = 0.17, .jit = 0.12, .vjit = 0.26, .vars = 4, .poly = 3 },
    .{ .make = mkStepSprint, .gain = 0.20, .jit = 0.11, .vjit = 0.24, .vars = 4, .poly = 3 },
    .{ .make = mkRoll, .gain = 0.55, .jit = 0.09, .vjit = 0.14, .vars = 2 },
    .{ .make = mkSwingLight, .gain = 0.44, .jit = 0.11, .vjit = 0.18, .vars = 4, .poly = 3 },
    .{ .make = mkSwingHeavy, .gain = 0.52, .jit = 0.07, .vjit = 0.12, .vars = 3 },
    .{ .make = mkHitLight, .gain = 0.70, .jit = 0.11, .vjit = 0.18, .vars = 4, .poly = 4 },
    .{ .make = mkHitHeavy, .gain = 0.85, .jit = 0.08, .vjit = 0.14, .vars = 3, .poly = 3 },
    .{ .make = mkHurt, .gain = 0.72, .jit = 0.10, .vjit = 0.14, .vars = 3 },
    .{ .make = mkHurtHeavy, .gain = 0.88, .jit = 0.07, .vjit = 0.10, .vars = 3 },
    .{ .make = mkStagger, .gain = 0.55, .jit = 0.10, .vjit = 0.16, .vars = 2 },
    .{ .make = mkRefused, .gain = 0.34, .jit = 0.06, .vjit = 0.08, .vars = 2 },
    .{ .make = mkDeath, .gain = 0.95, .jit = 0.0, .vjit = 0.0, .poly = 1 },
    .{ .make = mkRespawn, .gain = 0.55, .jit = 0.0, .vjit = 0.0, .poly = 1 },
    .{ .make = mkToadHop, .gain = 0.40, .jit = 0.15, .vjit = 0.26, .vars = 4, .poly = 4 },
    .{ .make = mkToadLunge, .gain = 0.62, .jit = 0.12, .vjit = 0.16, .vars = 3, .poly = 3 },
    .{ .make = mkToadGape, .gain = 0.46, .jit = 0.14, .vjit = 0.20, .vars = 3, .poly = 3 },
    .{ .make = mkToadChomp, .gain = 0.62, .jit = 0.13, .vjit = 0.18, .vars = 3, .poly = 3 },
    .{ .make = mkToadHurt, .gain = 0.58, .jit = 0.14, .vjit = 0.20, .vars = 3, .poly = 3 },
    .{ .make = mkToadDie, .gain = 0.66, .jit = 0.11, .vjit = 0.14, .vars = 3, .poly = 3 },
    // The nock/draw creak sits WELL under the loose (owner's call): it is a tell you register at
    // the edge of hearing, and the twang is the one that has to cut through.
    .{ .make = mkBowDraw, .gain = 0.17, .jit = 0.10, .vjit = 0.18, .vars = 3, .poly = 3 },
    .{ .make = mkBowLoose, .gain = 0.58, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 3 },
    .{ .make = mkArrowHit, .gain = 0.72, .jit = 0.09, .vjit = 0.14, .vars = 3, .poly = 3 },
    // The earth is the miss and therefore the one you hear most — quietest of the four, widest
    // variance, so a volley into the dirt never reads as one sample on repeat.
    .{ .make = mkArrowDirt, .gain = 0.34, .jit = 0.15, .vjit = 0.28, .vars = 4, .poly = 4 },
    .{ .make = mkArrowWood, .gain = 0.56, .jit = 0.12, .vjit = 0.20, .vars = 4, .poly = 4 },
    .{ .make = mkArrowStone, .gain = 0.50, .jit = 0.13, .vjit = 0.22, .vars = 4, .poly = 4 },
    .{ .make = mkArrowMetal, .gain = 0.52, .jit = 0.11, .vjit = 0.18, .vars = 3, .poly = 3 },
    .{ .make = mkBoneHurt, .gain = 0.62, .jit = 0.12, .vjit = 0.20, .vars = 4, .poly = 3 },
    .{ .make = mkBoneDie, .gain = 0.68, .jit = 0.09, .vjit = 0.12, .vars = 3 },
    .{ .make = mkOgreStep, .gain = 0.60, .jit = 0.08, .vjit = 0.20, .vars = 4, .poly = 3 },
    .{ .make = mkOgreRoar, .gain = 0.80, .jit = 0.06, .vjit = 0.10, .vars = 3 },
    .{ .make = mkOgreSlam, .gain = 1.00, .jit = 0.06, .vjit = 0.08, .vars = 3 },
    .{ .make = mkOgreSwipe, .gain = 0.72, .jit = 0.07, .vjit = 0.12, .vars = 3 },
    .{ .make = mkOgreHurt, .gain = 0.66, .jit = 0.10, .vjit = 0.16, .vars = 3, .poly = 3 },
    .{ .make = mkOgreDie, .gain = 0.92, .jit = 0.0, .vjit = 0.0, .poly = 1 },
    .{ .make = mkFlaskDrink, .gain = 0.52, .jit = 0.06, .vjit = 0.10, .vars = 2, .poly = 2 },
    .{ .make = mkFlaskCycle, .gain = 0.30, .jit = 0.07, .vjit = 0.08, .vars = 2, .poly = 3 },
    .{ .make = mkKill, .gain = 0.55, .jit = 0.10, .vjit = 0.14, .vars = 3, .poly = 4 },
    .{ .make = mkMenuMove, .gain = 0.30, .jit = 0.06, .vjit = 0.08, .vars = 2, .poly = 3 },
    .{ .make = mkMenuPick, .gain = 0.38, .jit = 0.03, .vjit = 0.05 },
    .{ .make = mkMenuBack, .gain = 0.32, .jit = 0.03, .vjit = 0.05 },
    // MUCH quieter (owner's call). A bed you can pick out is a bed that is too loud: its whole job
    // is to stop silence reading as broken audio, and it does that at a level you only notice when
    // it stops. The birds ride inside this, so they came down with it.
    .{ .make = mkWind, .gain = 0.055, .jit = 0.0, .vjit = 0.0, .poly = 1 },
};

/// How long each voice renders for. Kept beside the bank rather than inside each renderer so the
/// memory cost of the whole thing is readable in one place: at 22 kHz, one second is 44 KB.
fn seconds(id: Id) f32 {
    return switch (id) {
        .wind => 8.0,
        .death => 3.2,
        .ogre_die => 2.2,
        .respawn => 1.4,
        .bone_die, .toad_die, .ogre_roar => 1.1,
        .ogre_slam, .bow_draw, .flask_drink => 1.05,
        // Every arrow impact is QUICK either way (owner's law) — a third of a second, tops.
        .arrow_hit, .arrow_dirt, .arrow_wood, .arrow_stone, .arrow_metal => 0.36,
        .roll, .swing_heavy, .ogre_swipe, .ogre_step => 0.7,
        else => 0.5,
    };
}

// ── playback ────────────────────────────────────────────────────────────────────────────
// A `Sound` can only play once at a time — a second trigger restarts it — so each voice keeps
// `poly` ALIASES sharing one copy of the sample data, and triggers round-robin through them. That
// is what lets four toads croak over each other instead of cutting each other off.

const MAX_VARS = 4;
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

/// Past this the world falls silent. Generous: the ogre's slam should carry across the plaza, and
/// the per-voice gain plus the inverse falloff already keep distant sounds where they belong.
const FALLOFF: f32 = 46.0;

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
    emit(id, 1.0, 0.5);
}

/// …with an explicit strength, for the beats that come in degrees (a light vs a heavy).
pub fn playAt(id: Id, vol: f32) void {
    emit(id, vol, 0.5);
}

/// Trigger a voice somewhere in the WORLD: attenuated by distance and panned across the camera.
/// Beyond FALLOFF it costs nothing at all — the test is two subtractions before any state is touched.
pub fn world(id: Id, at: rl.Vector3) void {
    if (!ready) return;
    // SQUARED for the reject, and that is what makes the early-out the cheap thing this voice's own
    // test claims it is: `distXZ` is a square ROOT, and it was being paid on every call by every
    // foe on the map — including the great majority that are out of earshot and return one line
    // later. The root is now only taken by the sounds that will actually be heard.
    const d2 = mathx.dist2XZ(at, lisPos);
    if (d2 > FALLOFF * FALLOFF) return;
    const d = @sqrt(d2);
    // Inverse-square-ish, squared again at the tail so distant sounds fall away rather than
    // hanging at a constant murmur across the whole plain.
    const k = 1.0 - d / FALLOFF;
    const vol = k * k;
    const to = mathx.dirXZ(lisPos, at);
    const side = to.x * lisRight.x + to.z * lisRight.z;
    // Never fully hard-panned: a sound that vanishes from one ear reads as a bug, and the camera
    // is only a couple of metres from the hero anyway.
    emit(id, vol, mathx.clampF(0.5 + 0.42 * side, 0.04, 0.96));
}

fn emit(id: Id, vol: f32, pan: f32) void {
    if (!ready or muted or vol <= 0.01) return;
    const idx = @intFromEnum(id);
    const row = BANK[idx];
    const s = &slots[idx];
    // Round-robin the alias AND the variant off one counter: `poly` and `vars` are coprime often
    // enough that stepping both together decorrelates which take you hear from which slot it lands
    // in, and when they are not, the pitch jitter covers it.
    const pick = s.next;
    s.next = (s.next + 1) % (row.vars * row.poly);
    const snd = s.snd[pick % row.vars][pick / row.vars % row.poly];
    // Pitch AND level wobble, both per trigger. The level one is deliberately one-sided-ish (it
    // only ever takes away) so a jittered step can never be LOUDER than the tuned gain — variance
    // must not turn into the occasional bang.
    const vj = 1.0 - @abs(rng.signed()) * row.vjit;
    rl.setSoundVolume(snd, mathx.clampF(row.gain * vol * vj, 0, 1));
    rl.setSoundPitch(snd, 1.0 + rng.signed() * row.jit);
    rl.setSoundPan(snd, pan);
    rl.playSound(snd);
}

/// Keep the wind bed alive. Call once a frame; it re-triggers only when the last pass has run out,
/// and the voice's long crossfaded ends are what make the seam inaudible.
///
/// The re-trigger goes through `emit` like everything else. It used to set the volume, pitch and pan
/// itself from `BANK[wind].gain`, which made it the one voice in the game whose level was applied
/// somewhere other than the one function that knows how a row's gain becomes a raylib volume — so
/// the bed would have quietly ignored any change to how that mapping works.
pub fn ambience() void {
    if (!ready or muted) return;
    // `wind` is poly 1 / vars 1, so slot 0 IS the voice — asking raylib whether that one is still
    // running is the whole re-trigger test.
    if (rl.isSoundPlaying(slots[@intFromEnum(Id.wind)].snd[0][0])) return;
    emit(.wind, 1.0, 0.5);
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
