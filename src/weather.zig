const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;

// **THE WEATHER — INTERMITTENT RAIN, TWO STRENGTHS, AND THE STORM'S OWN LIGHTNING** (owner's ask). It is a
// CLOCK and a PICTURE, and they are deliberately separate: `Weather` is pure numbers that a test can run for
// an hour of game time in a millisecond, and `Rain` is one mesh drawn a few times over the top of it.
//
// **IT IS SPACED OUT, NOT WEATHER-SYSTEM SIMULATION.** Rain arrives, stays a while, and goes; between storms
// there are minutes of nothing. A world where it is always about to rain reads as a weather TOGGLE, and one
// where it rains constantly is a filter over the game rather than an event in it.
//
// **AND IT COSTS ONE MESH.** The streaks are a single cell of rain — a disc of them one `CELL_H` tall — drawn
// STACKED up the camera's own column and scrolled by a wrapping phase, so a downpour is a handful of draw
// calls of the same buffer rather than a particle system with thousands of live motes. `drawParticles` is
// what rain must NOT be: at one immediate-mode sphere per drop this would cost more than the whole world.

// ── THE CLOCK ───────────────────────────────────────────────────────────────────────────────────────────

/// How long the sky stays clear between storms. Long, and RANGED, because the thing that makes weather read
/// as weather is that you cannot tell when it is coming — at a fixed gap it is a metronome.
pub const DRY_LO: f32 = 150.0;
pub const DRY_HI: f32 = 420.0;
/// **THE FIRST GAP IS ITS OWN, AND IT IS SHORT** (owner: played for a while and saw no rain). The ordinary
/// dry spell is minutes long on purpose — but the stream is SEEDED once at startup (`game.init`), so a long
/// opening draw is not bad luck ONCE, it is the same long wait on every launch of the build, forever.
/// Measured at the game's own seed the opening drew **394 s**: six and a half minutes of uninterrupted play
/// before the sky did anything, and the clock only runs while no menu, fire or conversation is up. The first
/// storm has to land inside a session or nobody ever learns the sky does this.
pub const OPEN_LO: f32 = 45.0;
pub const OPEN_HI: f32 = 110.0;
/// …and how long one lasts. Under a minute is a shower nobody registers; past three it stops being an event.
pub const WET_LO: f32 = 55.0;
pub const WET_HI: f32 = 145.0;
/// **IT ARRIVES AND LEAVES OVER A REAL SPAN.** Weather that snaps on is a switch being thrown; the ramp is
/// what makes it something you notice happening. OUT is slower than IN — a shower stops raining in a hurry
/// and the last of it hangs about, which is also the order that never strands the audio bed mid-swell.
pub const RAMP_IN: f32 = 9.0;
pub const RAMP_OUT: f32 = 14.0;

/// **AND IT DOES NOT SIT AT ONE LEVEL WHILE IT IS THERE** (owner: vary the heaviness a bit as it storms). A
/// storm held at its top is a FILTER over the game — the sheet is the same sheet for two minutes and the ear
/// stops hearing the bed. So the level breathes under its own top: two slow swells beating against each other,
/// on periods that do not divide (17.5 s and 30), so a lull never lands twice in the same place in a storm.
///
/// **HOW FAR UNDER ITS TOP A LULL TAKES IT.** Deep enough to see — at a moderate storm the second sheet swings
/// from a fifth of itself to full over one swell (`copyFade`), which is the density visibly moving — and short
/// of the levels other things key off: the flash needs `FLASH_AT` and the lull bottoms out well over it, so
/// lightning cannot switch off inside its own storm.
pub const GUST_DEEP: f32 = 0.30;
const GUST_A: f32 = 17.5;
const GUST_B: f32 = 30.0;
/// The two together close on a full swell at 179 s, so the clock wraps on their common period rather than
/// counting seconds forever — `t`'s own reason one field along.
const GUST_WRAP: f32 = 210.0;

/// 0..1, 1 at the fullest — what the top is multiplied down FROM, never up.
pub fn gustAt(t: f32) f32 {
    const a = 0.5 + 0.5 * mathx.sinf(std.math.tau * t / GUST_A);
    const b = 0.5 + 0.5 * mathx.sinf(std.math.tau * t / GUST_B + 1.7);
    return 1.0 - GUST_DEEP * (1.0 - (a * 0.6 + b * 0.4));
}

/// The two strengths, and what each tops out at (`Weather.rain`). GENTLE is a wash you can see through;
/// MODERATE is the one with the sky in it.
pub const Kind = enum { gentle, moderate };
pub const GENTLE_TOP: f32 = 0.52;
pub const MODERATE_TOP: f32 = 1.0;
/// How often the storm that arrives is the heavier one. Under half on purpose: the moderate one carries the
/// lightning, and the thing that makes a flash worth anything is that most rain does not have one.
pub const MODERATE_ODDS: f32 = 0.38;

/// **LIGHTNING IS THE MODERATE STORM'S ALONE, AND ONLY ONCE IT HAS ARRIVED.** Under this the sky is not yet
/// dark enough for a flash to read as anything but a bug.
pub const FLASH_AT: f32 = 0.62;
pub const FLASH_GAP_LO: f32 = 7.0;
pub const FLASH_GAP_HI: f32 = 26.0;
/// The strike itself: a hard spike, a dark beat, and a second lower flicker — a single ramp reads as a lamp
/// being switched, and the double is what says ELECTRICITY.
pub const FLASH_DUR: f32 = 0.42;

/// HOW FAR OFF THE STRIKE IS, in metres — and it is the honest reason the thunder is late (`SOUND_MPS`).
/// Nothing is closer than `STRIKE_LO`: a strike on top of you wants a crack, a lit sky and a shaken camera,
/// which is a different move than this one and belongs to whatever asks for it.
pub const STRIKE_LO: f32 = 380.0;
pub const STRIKE_HI: f32 = 2600.0;
pub const SOUND_MPS: f32 = 343.0;
/// …and how loud it comes back, near against far. Not an inverse square: thunder at two kilometres is quieter
/// AND duller, and the dullness is the voice's own (`audio.mkThunder`); this is only the level.
pub const BOOM_NEAR: f32 = 1.0;
pub const BOOM_FAR: f32 = 0.34;

/// ONE STRIKE STILL ON ITS WAY — how long until the roll lands and how loud it is when it does.
pub const Peal = struct { in: f32 = 0, gain: f32 = 0 };
/// **HOW MANY CAN BE IN THE AIR AT ONCE, AND IT IS ARITHMETIC OVER WHAT FEEDS IT** (the ring law): the
/// longest travel is `STRIKE_HI / SOUND_MPS` = 7.58 s and the soonest a second strike can follow is
/// `FLASH_GAP_LO` = 7.0, so a SINGLE slot silently dropped the first roll every time the two overlapped —
/// a flash you saw and never heard. Plus one, because a peal due on a full frame lands the next one.
pub const PEALS: usize = @intFromFloat(@ceil(STRIKE_HI / SOUND_MPS / FLASH_GAP_LO) + 1);

comptime {
    // …and the size is checked against the thing it is sized off, or it is a round number after all.
    std.debug.assert(@as(f32, @floatFromInt(PEALS)) * FLASH_GAP_LO > STRIKE_HI / SOUND_MPS);
}

/// **HOW MUCH OF THE LIGHT THE CLOUD TAKES** — the overcast wash, at full rain. Subtle: this sits over the
/// whole frame, and a storm that dims the world past this reads as dusk arriving rather than as cloud.
pub const DIM_MAX: f32 = 0.17;

/// ONE STORM'S WHOLE STATE, and every number in it is seconds or 0..1. Pure: no raylib, no audio, no clock but
/// the `dt` it is handed — which is what lets a test run a day of weather without a window.
pub const Weather = struct {
    rng: mathx.Rng,
    kind: Kind = .gentle,
    /// Is a storm ON — its own clock running down. The LEVEL lags this by the ramp, which is the whole point.
    wet: bool = false,
    /// Seconds left in whichever half of the cycle is running.
    left: f32 = 0,
    /// 0..1, eased. **THE ONE NUMBER EVERYTHING ELSE READS** — the mesh's opacity, the bed's level, the wash.
    level: f32 = 0,
    /// Seconds since the last strike, or negative for none in flight.
    flashT: f32 = -1,
    /// …and until the next one.
    nextFlash: f32 = 0,
    /// **EVERY STRIKE STILL ON ITS WAY** — a strike's SOUND is late by its own distance, which is the one
    /// piece of physics this file keeps. A RING rather than one slot (`PEALS`), because the travel outlasts
    /// the gap between strikes and a single slot dropped the older roll without a word.
    peals: [PEALS]Peal = [_]Peal{.{}} ** PEALS,
    npeals: usize = 0,
    boomGain: f32 = 0,
    /// One-frame edge, read and cleared through `thunder()` — `justDied`'s rule.
    boomNow: bool = false,
    /// The rain's own running time, so the fall phase does not read a wall clock: `--shot` steps a fixed dt
    /// and has to draw the same frame twice.
    t: f32 = 0,
    /// …and the SWELL's own, which is a separate clock for the same reason `t` is one at all: that one wraps
    /// on a cell of fall (a fifth of a second) and this one on the two gusts' common period (`GUST_WRAP`).
    /// FREE-RUNNING through the dry spells, so consecutive storms do not all open on the same swell.
    gustT: f32 = 0,

    pub fn init(seed: u64) Weather {
        var w = Weather{ .rng = mathx.Rng.init(seed) };
        // IT DOES NOT OPEN IN THE RAIN — but it opens on the SHORT gap (`OPEN_LO`), not the long one, so the
        // first storm of a session is something you actually see. After that it settles into the real rhythm.
        w.left = w.rng.range(OPEN_LO, OPEN_HI);
        return w;
    }

    /// What a storm of this kind tops out at.
    pub fn topFor(k: Kind) f32 {
        return switch (k) {
            .gentle => GENTLE_TOP,
            .moderate => MODERATE_TOP,
        };
    }

    pub fn tick(self: *Weather, dt: f32) void {
        // **THE FALL CLOCK WRAPS ON ITS OWN CELL** — `t` exists only to drive a phase that is already modulo
        // `CELL_H`, and an f32 that has been counting seconds since the game booted has lost the low bits that
        // phase is made of (`audio.mkCrickets`' note, one system along). Wrapped here, it never grows at all.
        self.t = @mod(self.t + dt, CELL_H / FALL_MPS);
        self.gustT = @mod(self.gustT + dt, GUST_WRAP);
        self.boomNow = false;
        self.left -= dt;
        if (self.left <= 0) {
            self.wet = !self.wet;
            if (self.wet) {
                self.kind = if (self.rng.float() < MODERATE_ODDS) .moderate else .gentle;
                self.left = self.rng.range(WET_LO, WET_HI);
                self.nextFlash = self.rng.range(FLASH_GAP_LO, FLASH_GAP_HI);
            } else {
                self.left = self.rng.range(DRY_LO, DRY_HI);
            }
        }
        // THE LEVEL WALKS TO WHAT THE CLOCK ASKED FOR. `approach` is the shared ease, so weather arrives the
        // way every other continuous thing in this game does.
        // …AND THE SWELL RIDES ON THE TOP, not on the level: it is what the storm is ASKING for, so the ramp
        // still owns how fast the sheet may move and the gust cannot become a step (`gustAt`).
        const want: f32 = if (self.wet) topFor(self.kind) * gustAt(self.gustT) else 0;
        const secs = if (want > self.level) RAMP_IN else RAMP_OUT;
        self.level = mathx.approach(self.level, want, dt / secs);

        // …AND THE STORM'S OWN LIGHTNING, which is the moderate one's and only once it has really arrived.
        if (self.flashT >= 0) {
            self.flashT += dt;
            if (self.flashT > FLASH_DUR) self.flashT = -1;
        }
        if (self.kind == .moderate and self.wet and self.level >= FLASH_AT) {
            self.nextFlash -= dt;
            if (self.nextFlash <= 0) {
                self.nextFlash = self.rng.range(FLASH_GAP_LO, FLASH_GAP_HI);
                self.flashT = 0;
                const far = self.rng.range(STRIKE_LO, STRIKE_HI);
                const u = (far - STRIKE_LO) / (STRIKE_HI - STRIKE_LO);
                // REFUSED RATHER THAN OVERWRITING THE OLDEST — the ring is sized so it cannot come up
                // (`PEALS`), and a silent overwrite is exactly the bug this replaced.
                if (self.npeals < PEALS) {
                    self.peals[self.npeals] = .{ .in = far / SOUND_MPS, .gain = mathx.lerpF(BOOM_NEAR, BOOM_FAR, u) };
                    self.npeals += 1;
                }
            }
        }
        // THE SOUND IS STILL COMING even if the rain has stopped — a strike you saw is a strike you hear.
        // **ONE ROLL A FRAME**: `thunder` is a single edge, so two peals due together land on consecutive
        // frames rather than one of them being lost. A sixtieth of a second is nothing against a 7 s travel.
        var i: usize = 0;
        while (i < self.npeals) : (i += 1) self.peals[i].in -= dt;
        var due: ?usize = null;
        for (self.peals[0..self.npeals], 0..) |p, k| {
            if (p.in > 0) continue;
            if (due == null or p.in < self.peals[due.?].in) due = k; // the one that has waited longest
        }
        if (due) |k| {
            self.boomGain = self.peals[k].gain;
            self.boomNow = true;
            self.npeals -= 1;
            self.peals[k] = self.peals[self.npeals];
        }
    }

    /// 0..1 — what the mesh, the bed and the wash all read.
    pub fn rain(self: *const Weather) f32 {
        return self.level;
    }

    /// **THE WHITE, 0..1** — a hard spike, a dark beat, then a lower second flicker. Shaped here rather than at
    /// the draw so the overlay and any test are reading one curve.
    pub fn flash(self: *const Weather) f32 {
        if (self.flashT < 0) return 0;
        const u = self.flashT / FLASH_DUR;
        if (u < 0.16) return 1.0 - u / 0.16 * 0.35; // the strike itself, barely off full
        if (u < 0.34) return 0.10; // the dark beat between the two — what makes it read as a flicker
        if (u < 0.52) return 0.62 * (1.0 - (u - 0.34) / 0.18); // …and the second, lower
        return 0.10 * (1.0 - (u - 0.52) / 0.48); // the afterglow going out
    }

    /// The thunder that just arrived, as a gain — a ONE-FRAME edge, null on every other frame.
    pub fn thunder(self: *const Weather) ?f32 {
        return if (self.boomNow) self.boomGain else null;
    }

    /// How much of the light the cloud is taking, 0..1 of `DIM_MAX`.
    pub fn dim(self: *const Weather) f32 {
        return self.level * DIM_MAX;
    }

    /// **THE DEBUG ROW'S OWN CYCLE — dry, gentle, moderate, dry** (`menu.DBG_WEATHER`). It is the day clock's
    /// scrub row one system along, and for the same reason: weather arrives on a clock measured in MINUTES,
    /// so "does it work" is not a question anybody can sit and answer without a way to ask it directly.
    pub fn cycleForce(self: *Weather) void {
        if (!self.wet) return self.force(.gentle, FORCE_DUR);
        if (self.kind == .gentle) return self.force(.moderate, FORCE_DUR);
        self.clear();
    }

    /// How long a FORCED storm runs before the ordinary cycle has it back. Long enough to walk somewhere and
    /// look at it, short enough that leaving it on is not a decision.
    pub const FORCE_DUR: f32 = 180.0;

    /// BACK TO THE SKY'S OWN BUSINESS — the level ramps out on its own (`RAMP_OUT`), which is the point: this
    /// is the storm ENDING, not the storm being deleted.
    pub fn clear(self: *Weather) void {
        self.wet = false;
        self.left = self.rng.range(OPEN_LO, OPEN_HI);
        self.flashT = -1;
        self.nextFlash = 0;
    }

    /// What the debug row says it is doing. The LEVEL rather than `wet`, because the ramp is most of what
    /// there is to watch and a row reading "Dry" over a sky still emptying itself would be lying.
    pub fn says(self: *const Weather) [:0]const u8 {
        if (self.level <= 0.02) return "Weather: Dry";
        return switch (self.kind) {
            .gentle => if (self.wet) "Weather: Gentle" else "Weather: Gentle (clearing)",
            .moderate => if (self.wet) "Weather: Moderate" else "Weather: Moderate (clearing)",
        };
    }

    /// **FORCE ONE ON** — the shot harness and the debug row, never the fight. `secs` is how long it runs.
    pub fn force(self: *Weather, k: Kind, secs: f32) void {
        self.kind = k;
        self.wet = true;
        self.left = secs;
        self.level = topFor(k);
        self.nextFlash = 0.01;
    }
};

// ── THE PICTURE ─────────────────────────────────────────────────────────────────────────────────────────

/// ONE CELL of rain: a disc of streaks `CELL_H` tall, drawn stacked and scrolled. The height is what the fall
/// phase wraps on, so it may never be changed without the draw agreeing — they are one number.
pub const CELL_H: f32 = 5.0;
/// …and how far out it reaches (owner: spread rain out into the distance). At 11.5 m the sheet ENDED — a wall
/// of rain a stone's throw off with clear air behind it, which is why the storm read as something happening to
/// the lens rather than to the field. **AND THE SPREAD IS ALSO THE THINNING**: the streaks are distributed by
/// area (`@sqrt`), so trebling the disc drops the density in front of his face by the same factor while the
/// count barely moves — the near field is what "too heavy" was made of, and the far field costs almost no fill
/// because a streak twenty metres out covers a few pixels. The haze is what finally eats it.
pub const CELL_R: f32 = 24.0;
/// **AND THE RIM FADES OUT RATHER THAN STOPPING** (owner: if you look around the rain ends abruptly). Density
/// was flat right up to `CELL_R` and then nothing at all, so the sheet had a WALL at its own edge — you were
/// standing in a cylinder of rain and could see the far side of it. Past this share of the radius the streaks
/// thin toward nothing: the WIDTH goes out (which is what screen coverage is made of) and the length only
/// part-way, so the last legible ones are still streak-shaped rather than grains.
const TAPER_FROM: f32 = 0.58;
/// How many cells are stacked up the camera's column. Four puts the top of the rain 15 m up, which is over
/// the tallest thing a player stands next to.
pub const STACKS: usize = 4;
/// …and one below him, so looking DOWN a slope still has rain in front of the ground.
pub const STACK_UNDER: f32 = 1.0;

/// Streaks in one cell. **THE ONE PERFORMANCE DIAL, AND THE ONE DENSITY DIAL** — it is what "how hard it is
/// raining" is actually made of, and it moves BOTH strengths together (owner: all forms of rain too heavy).
/// At 820 in an 11.5 m disc the gentle shower was a curtain and the storm was a wall; a test prints the
/// triangles it buys, and the DENSITY it works out to against `CELL_R` — which is the number that reads.
pub const STREAKS: usize = 1000;

/// A drop's own shape. Long and thin: what says rain is the STREAK, not the drop, and a short mark reads as
/// snow or grain. The pair is a range, because uniform lengths read as a screen effect.
const LEN_LO: f32 = 0.40;
const LEN_HI: f32 = 0.92;
const WIDE_LO: f32 = 0.008;
const WIDE_HI: f32 = 0.016;

/// **WHICH WAY THE WEATHER IS COMING FROM**, as metres of drift per metre of fall — the same slant for every
/// streak, in WORLD space, so turning the camera turns the rain rather than the rain following the lens.
/// **MEASURED OFF THE FIRST FRAME OF IT, NOT ARGUED.** At 0.17 a 0.9 m streak leans 15 cm over its whole
/// length, which at any framing a player actually uses reads as vertical — and vertical rain is a screen
/// effect. This is a real lean without becoming a gale (that would want the flora bending with it).
const SLANT_X: f32 = 0.30;
const SLANT_Z: f32 = -0.12;

/// Metres a second, at the top of the fall. Real rain runs 7-9; this sits over that, because a game's rain
/// has to read at a glance and in a still frame — but only just over (owner: all rain falls too quickly). At
/// 21 a 0.9 m streak crossed twenty-three times its own body every second, which is not fall, it is a
/// SMEAR: the sheet read as vertical scan lines with the individual drops gone.
pub const FALL_MPS: f32 = 13.0;

/// The colour of the water itself. Cold and pale, and the ALPHA is the EMISSIVE channel (`gfx` law, `emis =
/// 1 - a/255`): well under half, so a streak carries its own light and stays legible against a dark hillside
/// as well as against the sky. It is not white — white rain reads as sparks.
const DROP_HEAD = rgba(176, 190, 205, 96);
/// …and the TAIL is fainter, which is what makes it a streak rather than a stick. Built as two segments so
/// the fade is in the geometry (`propfx`'s pillar, one system along).
const DROP_TAIL = rgba(150, 166, 186, 150);

/// How see-through the whole sheet is at full rain — the `fade` uniform, which is the only opacity the scene
/// shader has for a solid material. Low: rain is a hundred faint marks, never a curtain.
pub const OPACITY: f32 = 0.26;
/// Where the SECOND copy of the cell comes in — the heavier storm is the same mesh again, offset in XZ and
/// half a cell in Y, which thickens the density for a few more draw calls and no more memory.
pub const DOUBLE_AT: f32 = 0.60;
/// …and how solid it ever gets. **UNDER ONE ON PURPOSE**: a full second sheet is twice the blended fill of
/// the storm below it for a density step the eye reads as "more rain", not as double.
pub const COPY_TOP: f32 = 0.72;
/// The copy is a cell SHORTER than the column under it — it already starts half a cell up, so its top stack
/// sits 17 m over the eye, which is sky nobody is looking at.
pub const COPY_STACKS: usize = STACKS - 1;
/// **AND IT IS OFFSET IN Y, BARELY IN XZ** (owner: rain only on the front right). A 5 m sideways shift of a
/// disc this size put the heavy sheet's overlap — its whole doubled density — off to one quarter, with the
/// opposite side left at single strength and its taper 5 m nearer: the storm was visibly lopsided. Half a cell
/// of HEIGHT is what actually decorrelates the two, and it moves nothing sideways at all.
const COPY_OFF = v3(1.6, CELL_H * 0.5, -1.1);

/// **HOW MUCH OF THE SECOND SHEET IS THERE**, 0 at `DOUBLE_AT` and `COPY_TOP` at a full storm. It is a RAMP
/// and not a threshold, and it is out here rather than inside the draw so a test can step it: switched at
/// `DOUBLE_AT` the heavy storm's second sheet arrived and left between two frames — a cell of rain appearing
/// whole while the level either side of it was still easing (owner: "starts/stops too suddenly").
pub fn copyFade(level: f32) f32 {
    if (level <= DOUBLE_AT) return 0;
    return mathx.clampF((level - DOUBLE_AT) / (MODERATE_TOP - DOUBLE_AT), 0, 1) * COPY_TOP;
}

/// **BUILT ONCE AND PERMANENT** — there is no `unload` and there may not be one: this model's material holds
/// the SCENE shader, and `rl.unloadModel` unloads the material's shader (AGENTS.md's own terrain-tile crash).
/// Everything else drawn through `gfx.Scene` is kept for the process's life on exactly that reasoning.
pub const Rain = struct {
    model: rl.Model,

    pub fn build(shader: rl.Shader) Rain {
        var b = gfx.Builder.init();
        // `.plain`, the emissive path a glow already uses — see `propfx.pickupMesh`'s note. Rain is water, but
        // `.water` is the SHEET's material (its own ripple and tone) and a streak is not a surface.
        b.setMat(.plain);
        b.setAnimY(0); // rain does not sway: `windAmt` is the flora path and this is not flora
        var rng = mathx.Rng.init(0x2A11_D40D);
        for (0..STREAKS) |_| {
            const a = rng.angle();
            // `@sqrt` for a UNIFORM disc — without it every cell is a column of rain with a bare rim.
            const rr = CELL_R * @sqrt(rng.float());
            const x = mathx.cosf(a) * rr;
            const z = mathx.sinf(a) * rr;
            const y = rng.float() * CELL_H;
            // THE OUTER BAND THINS TO NOTHING, so the sheet has no far wall (`TAPER_FROM`). Baked into the
            // GEOMETRY because it has to be: vertex alpha here is the EMISSIVE channel (`gfx` law) and the
            // `fade` uniform is per-DRAW, so a per-streak opacity is the one thing this renderer cannot do.
            const t = mathx.smoothstep(TAPER_FROM * CELL_R, CELL_R, rr);
            const taper = 1.0 - t;
            const len = rng.range(LEN_LO, LEN_HI) * mathx.lerpF(0.55, 1.0, taper);
            const wide = rng.range(WIDE_LO, WIDE_HI) * taper;
            streak(&b, v3(x, y, z), len, wide);
        }
        return .{ .model = b.toModel(shader) };
    }

    /// **THE WHOLE STORM, IN `STACKS` DRAW CALLS** (twice that at the heavier end). The cell is drawn up the
    /// camera's own column and slid down by a phase that WRAPS on `CELL_H`, so the seam between one cell and
    /// the next never arrives — there is no beginning or end to fall off.
    ///
    /// It is drawn LAST, after every opaque thing, with the depth mask off (`Scene.beginFade`) — a streak is a
    /// half-there surface and may not write depth over the world behind it. It is still depth TESTED, which is
    /// what puts the rain behind a wall you are standing under rather than over it.
    /// **CENTRED ON THE MAN, NOT ON THE LENS** (owner: rain must project on all sides of the hero). `at` is his
    /// ground point and `eye` is only where the column is stacked FROM. On the camera the disc reached 24 m
    /// behind the lens and only 19 ahead of the hero — the short side being the side the frame is looking at.
    /// And it has to be a point the CAMERA DOES NOT ROTATE: any lead taken off the camera's own forward slides
    /// the whole sheet sideways when you turn, which is 40 m/s of rain drifting for no physical reason.
    pub fn draw(self: *const Rain, scene: *gfx.Scene, eye: rl.Vector3, at: rl.Vector3, level: f32, t: f32) void {
        if (level <= 0.02) return;
        const lv = mathx.clampF(level, 0, 1);
        const phase = @mod(t * FALL_MPS, CELL_H);
        const baseY = @floor(eye.y) - STACK_UNDER * CELL_H - phase;
        scene.beginFade(OPACITY * lv);
        self.column(v3(at.x, baseY, at.z), STACKS);
        // THE HEAVIER STORM IS THE SAME CELL AGAIN, offset so the two do not pair up into visible twins —
        // and FADED UP over the top of the ramp (`copyFade`) rather than switched on at a level.
        const cf = copyFade(lv);
        if (cf > 0.004) {
            scene.setFade(OPACITY * lv * cf);
            self.column(v3(at.x + COPY_OFF.x, baseY + COPY_OFF.y, at.z + COPY_OFF.z), COPY_STACKS);
        }
        scene.endFade();
    }

    fn column(self: *const Rain, at: rl.Vector3, stacks: usize) void {
        for (0..stacks) |s| {
            const y = at.y + @as(f32, @floatFromInt(s)) * CELL_H;
            rl.drawModelEx(self.model, v3(at.x, y, at.z), v3(0, 1, 0), 0, v3(1, 1, 1), rl.Color.white);
        }
    }
};

/// ONE STREAK — two crossed cards, in two segments each, leaning down the wind. **CROSSED, because a single
/// card is INVISIBLE edge-on**: rain seen from the side of its own quad is rain that disappears when you turn.
/// Two segments, because the tail has to fade — one flat card reads as a dropped matchstick.
fn streak(b: *gfx.Builder, foot: rl.Vector3, len: f32, wide: f32) void {
    const half = len * 0.5;
    const mid = v3(foot.x + SLANT_X * half, foot.y + half, foot.z + SLANT_Z * half);
    const top = v3(foot.x + SLANT_X * len, foot.y + len, foot.z + SLANT_Z * len);
    const w = wide * 0.5;
    // The HEAD is the bottom (a drop falls head-down), so the bright end is the low one.
    for ([_]rl.Vector3{ v3(w, 0, 0), v3(0, 0, w) }) |off| {
        card(b, foot, mid, off, DROP_HEAD, DROP_TAIL);
        card(b, mid, top, off, DROP_TAIL, fade(DROP_TAIL));
    }
}

/// …and its far end goes out entirely, so the streak ENDS instead of stopping.
fn fade(c: rl.Color) rl.Color {
    return rgba(c.r, c.g, c.b, 205);
}

fn card(b: *gfx.Builder, a: rl.Vector3, c: rl.Vector3, off: rl.Vector3, ca: rl.Color, cc: rl.Color) void {
    const n = v3(0, 1, 0); // the normal barely matters at this emissive — the streak is nearly self-lit
    b.quadFade(
        v3(a.x - off.x, a.y, a.z - off.z),
        v3(a.x + off.x, a.y, a.z + off.z),
        v3(c.x + off.x, c.y, c.z + off.z),
        v3(c.x - off.x, c.y, c.z - off.z),
        n,
        ca,
        cc,
    );
}

/// **THE STORM OVER THE WHOLE FRAME** — the cloud's own dimming and the lightning, as two rectangles. Drawn
/// inside the retro pass (`game.drawScene`), because both are things happening to the WORLD's light: put after
/// the filter they read as a UI flash sitting on top of the picture.
pub fn drawOverlay(w: i32, h: i32, dimAmt: f32, flashAmt: f32) void {
    if (dimAmt > 0.004) {
        // A cold slate, not black: cloud takes the warmth out of the light before it takes the light.
        rl.drawRectangle(0, 0, w, h, rgba(26, 32, 44, mathx.u8f(255.0 * mathx.clampF(dimAmt, 0, 1))));
    }
    if (flashAmt > 0.004) {
        const a = mathx.clampF(flashAmt, 0, 1);
        // Two passes: a wide pale wash and a brighter core, so the strike has some shape to it rather than
        // being one flat white frame.
        // **MEASURED OFF THE SHOT.** At 120/70 the strike whited the frame out — every contour gone, which
        // reads as fog arriving rather than as light. A flash you can still see the world through is the one
        // that says something happened to the SKY.
        rl.drawRectangle(0, 0, w, h, rgba(198, 210, 236, mathx.u8f(74.0 * a)));
        rl.drawRectangle(0, 0, w, h, rgba(236, 242, 255, mathx.u8f(46.0 * a * a)));
    }
}

test "IT RAINS SOMETIMES, NOT OFTEN AND NOT NEVER — and never twice on the same clock" {
    var w = Weather.init(0xBEEF);
    const dt = 1.0 / 60.0;
    var wet: f32 = 0;
    var storms: usize = 0;
    var wasWet = false;
    var gapLo: f32 = 1e9;
    var gapHi: f32 = 0;
    var gap: f32 = 0;
    var t: f32 = 0;
    while (t < 3600.0) : (t += dt) { // an hour of it
        w.tick(dt);
        if (w.wet) {
            wet += dt;
            if (!wasWet) {
                storms += 1;
                if (storms > 1) {
                    gapLo = @min(gapLo, gap);
                    gapHi = @max(gapHi, gap);
                }
                gap = 0;
            }
        } else gap += dt;
        wasWet = w.wet;
    }
    const share = wet / 3600.0;
    std.debug.print("\n  weather: {d} storms an hour, raining {d:.0}% of the time, dry gaps {d:.0}..{d:.0} s\n", .{ storms, share * 100, gapLo, gapHi });
    // INTERMITTENT: it happens, and it is not the weather most of the time.
    try std.testing.expect(storms >= 4 and storms <= 20);
    try std.testing.expect(share > 0.10 and share < 0.45);
    // …and the gaps are SPACED and VARIED — a fixed gap is a metronome, which is the one thing weather is not.
    try std.testing.expect(gapLo >= DRY_LO - 1.0);
    try std.testing.expect(gapHi <= DRY_HI + 1.0);
    try std.testing.expect(gapHi - gapLo > 30.0);
}

test "IT ARRIVES AND LEAVES OVER A SPAN — the level never steps, and it always comes back to nothing" {
    var w = Weather.init(7);
    const dt = 1.0 / 60.0;
    var prev = w.level;
    var peak: f32 = 0;
    var biggest: f32 = 0;
    var t: f32 = 0;
    while (t < 2400.0) : (t += dt) {
        w.tick(dt);
        biggest = @max(biggest, @abs(w.level - prev));
        peak = @max(peak, w.level);
        prev = w.level;
        try std.testing.expect(w.level >= 0 and w.level <= MODERATE_TOP + 1e-4);
    }
    // No step: the biggest one-frame move is under what the ramp allows, with a frame of slack.
    try std.testing.expect(biggest <= dt / RAMP_IN * 1.2);
    // …and it really did rain: at LEAST what the deepest lull of a gentle storm is worth (`GUST_DEEP`), since
    // a storm's top is now what the swell is riding on rather than a level it sits at.
    try std.testing.expect(peak >= GENTLE_TOP * (1.0 - GUST_DEEP) - 0.02);
}

test "A STORM BREATHES — the level moves under its own top, and never over it or under the flash" {
    var w = Weather.init(21);
    w.force(.moderate, 600.0);
    const dt = 1.0 / 60.0;
    var lo: f32 = 1e9;
    var hi: f32 = -1e9;
    var prev = w.level;
    var biggest: f32 = 0;
    var t: f32 = 0;
    // Past one full beat of the two swells, so both ends of the breath are in the sample.
    while (t < GUST_WRAP) : (t += dt) {
        w.tick(dt);
        if (t > RAMP_OUT) { // …after the forced top has settled onto the swell it is riding
            lo = @min(lo, w.level);
            hi = @max(hi, w.level);
        }
        biggest = @max(biggest, @abs(w.level - prev));
        prev = w.level;
        try std.testing.expect(w.level <= MODERATE_TOP + 1e-4); // the top is a CEILING, never a mid-point
    }
    std.debug.print("\n  weather: a moderate storm breathes {d:.2}..{d:.2} of full\n", .{ lo, hi });
    try std.testing.expect(hi - lo > 0.12); // it is a swell you can see…
    try std.testing.expect(biggest <= dt / RAMP_IN * 1.2); // …and never a step: the ramp still owns the move
    // **THE LULL MAY NOT REACH DOWN TO WHAT ELSE KEYS OFF THE LEVEL.** Lightning gates on `FLASH_AT`, so a
    // breath that dipped under it would switch the storm's own sky off and on again.
    try std.testing.expect(MODERATE_TOP * (1.0 - GUST_DEEP) > FLASH_AT);
    // …and the gust is a multiplier DOWN from the top, never up: 1 is its ceiling.
    var u: f32 = 0;
    while (u < GUST_WRAP) : (u += 0.37) {
        const g = gustAt(u);
        try std.testing.expect(g > 1.0 - GUST_DEEP - 1e-5 and g <= 1.0 + 1e-5);
    }
}

test "THE FLASH IS THE MODERATE STORM'S ALONE, and the thunder is LATE by its own distance" {
    // A gentle storm, forced, never flashes however long it runs.
    var g = Weather.init(11);
    g.force(.gentle, 600.0);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < 300.0) : (t += dt) {
        g.tick(dt);
        try std.testing.expectEqual(@as(f32, 0), g.flash());
        try std.testing.expect(g.thunder() == null);
    }

    // …and a moderate one does, with the sound arriving after the light and never before it.
    var m = Weather.init(12);
    m.force(.moderate, 600.0);
    var flashes: usize = 0;
    var booms: usize = 0;
    var sinceFlash: f32 = -1;
    var lagLo: f32 = 1e9;
    var lagHi: f32 = 0;
    t = 0;
    while (t < 300.0) : (t += dt) {
        const wasFlashing = m.flashT >= 0;
        m.tick(dt);
        if (!wasFlashing and m.flashT >= 0) {
            flashes += 1;
            sinceFlash = 0;
        } else if (sinceFlash >= 0) sinceFlash += dt;
        if (m.thunder()) |gain| {
            booms += 1;
            try std.testing.expect(gain > 0 and gain <= BOOM_NEAR);
            try std.testing.expect(sinceFlash > STRIKE_LO / SOUND_MPS - 0.05); // light first, always
            lagLo = @min(lagLo, sinceFlash);
            lagHi = @max(lagHi, sinceFlash);
        }
    }
    // …and the one still in the air when the loop ended gets to land: a strike is heard EVENTUALLY.
    t = 0;
    while (t < STRIKE_HI / SOUND_MPS + 1.0) : (t += dt) {
        m.nextFlash = 1e9; // no new ones — this is the drain, not more weather
        m.tick(dt);
        if (m.thunder()) |_| booms += 1;
    }
    std.debug.print("  lightning: {d} strikes in 5 min, thunder {d:.1}..{d:.1} s behind the light\n", .{ flashes, lagLo, lagHi });
    try std.testing.expect(flashes > 5);
    try std.testing.expectEqual(flashes, booms); // every strike is heard, eventually
    try std.testing.expect(lagHi <= STRIKE_HI / SOUND_MPS + 0.1);
}

test "TWO STRIKES CAN BE IN THE AIR AT ONCE, and NEITHER roll is lost" {
    // THE BUG: one `boomIn` slot. The longest travel outlasts the shortest gap between strikes, so a strike
    // fired while a roll was still on its way silently replaced it — a flash you saw and never heard, at a
    // rate no fixed-seed test was ever going to catch.
    try std.testing.expect(STRIKE_HI / SOUND_MPS > FLASH_GAP_LO);
    const dt = 1.0 / 60.0;

    // The overlap MADE TO HAPPEN rather than waited for: it is under a percent of strikes, which is why no
    // fixed seed caught it and why `flashes == booms` passed for as long as it did.
    var w = Weather.init(1);
    w.force(.moderate, 600.0);
    w.nextFlash = 1e9; // no NEW strike under the two being watched
    w.peals[0] = .{ .in = STRIKE_HI / SOUND_MPS, .gain = BOOM_FAR }; // the far one, seen first…
    w.peals[1] = .{ .in = 0.40, .gain = BOOM_NEAR }; // …and a near one seen a gap later
    w.npeals = 2;
    var heard: [PEALS]f32 = undefined;
    var n: usize = 0;
    var t: f32 = 0;
    while (t < STRIKE_HI / SOUND_MPS + 1.0) : (t += dt) {
        w.tick(dt);
        if (w.thunder()) |gain| {
            try std.testing.expect(n < PEALS);
            heard[n] = gain;
            n += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), n); // BOTH — one slot heard exactly one of them
    try std.testing.expectEqual(BOOM_NEAR, heard[0]); // the near one lands first…
    try std.testing.expectEqual(BOOM_FAR, heard[1]); // …and the far one is still on its way

    // …AND TWO DUE ON ONE FRAME LAND ON CONSECUTIVE FRAMES rather than one being dropped: `thunder` is a
    // single edge, and a sixtieth of a second is nothing against a seven-second travel.
    w.peals[0] = .{ .in = 0.001, .gain = BOOM_NEAR };
    w.peals[1] = .{ .in = 0.001, .gain = BOOM_FAR };
    w.npeals = 2;
    w.tick(dt);
    try std.testing.expect(w.thunder() != null);
    try std.testing.expectEqual(@as(usize, 1), w.npeals);
    w.tick(dt);
    try std.testing.expect(w.thunder() != null);
    try std.testing.expectEqual(@as(usize, 0), w.npeals);
}

test "THE STRIKE IS A DOUBLE, NOT A LAMP — and it is over inside half a second" {
    var w = Weather.init(3);
    w.force(.moderate, 60.0);
    w.flashT = 0;
    var peakEarly: f32 = 0;
    var dip: f32 = 1;
    var peakLate: f32 = 0;
    var u: f32 = 0;
    while (u <= 1.0) : (u += 0.01) {
        w.flashT = u * FLASH_DUR;
        const f = w.flash();
        if (u < 0.16) peakEarly = @max(peakEarly, f);
        if (u > 0.18 and u < 0.32) dip = @min(dip, f);
        if (u > 0.36 and u < 0.50) peakLate = @max(peakLate, f);
    }
    try std.testing.expect(peakEarly > 0.9); // the strike
    try std.testing.expect(dip < 0.2); // the dark beat, which is what makes it a flicker
    try std.testing.expect(peakLate > 0.3 and peakLate < peakEarly); // …and the second, lower
    w.flashT = FLASH_DUR + 0.001;
    w.nextFlash = 1e9; // …and NOT because a new one started: the strike under test is the one that ended
    w.tick(1.0 / 60.0);
    try std.testing.expectEqual(@as(f32, 0), w.flash());
}

test "THE SHEET IS A HANDFUL OF DRAW CALLS, and its cost is written down" {
    // ONE MESH, drawn stacked. This is the whole performance argument for the system, so it is a number here
    // rather than a claim in a comment: a particle rain of this density would be thousands of live motes and
    // one immediate-mode sphere each (`foe.drawParticles`), which is more than the world costs.
    const tris = STREAKS * 2 * 2 * 2; // two crossed cards, two segments each, two triangles a quad
    const gentleDraws = STACKS;
    const heavyDraws = STACKS + COPY_STACKS;
    // …and what it actually COSTS is the blended fill, which the copy pays only `COPY_TOP` of.
    const heavyFill = @as(f32, @floatFromInt(STACKS)) + @as(f32, @floatFromInt(COPY_STACKS)) * COPY_TOP;
    // …and the number that actually READS: streaks per square metre of ground the cell covers.
    const density = @as(f32, @floatFromInt(STREAKS)) / (std.math.pi * CELL_R * CELL_R);
    std.debug.print("  rain: {d} tris in the cell, {d} draws gentle / {d} moderate ({d} tris on screen, {d:.2} columns of fill), {d:.2} streaks/m2 out to {d:.0} m\n", .{ tris, gentleDraws, heavyDraws, tris * heavyDraws, heavyFill, density, CELL_R });
    // A SHEET YOU CAN SEE THROUGH. At 820 streaks in an 11.5 m disc this was 1.97/m2 — a curtain up against
    // the lens (owner: all forms of rain too heavy), and the near field is where every one of those pixels was.
    try std.testing.expect(density < 1.0);
    try std.testing.expect(heavyDraws <= 8); // the storm is a rounding error in the draw-call budget
    try std.testing.expect(tris * heavyDraws < 60_000); // …and in the triangle one
    try std.testing.expect(heavyFill < @as(f32, @floatFromInt(STACKS)) * 1.6); // …and the peak is not double
    // …and the mesh is built ONCE: the level changes what is drawn, never what is built.
    try std.testing.expect(DOUBLE_AT > GENTLE_TOP); // so the gentle storm never pays for the second column
}

test "THE HEAVY SHEET FADES, IT DOES NOT ARRIVE — no step anywhere on the ramp" {
    // THE BUG: the second sheet was `if (level >= DOUBLE_AT)`. A whole cell of rain appeared between two
    // frames on the way up and vanished the same way on the way down, while the level either side of it was
    // easing over nine seconds — the one visible step in a system whose whole point is that it has none.
    try std.testing.expectEqual(@as(f32, 0), copyFade(0));
    try std.testing.expectEqual(@as(f32, 0), copyFade(GENTLE_TOP)); // the gentle storm never draws it at all
    try std.testing.expectEqual(@as(f32, 0), copyFade(DOUBLE_AT));
    try std.testing.expectEqual(COPY_TOP, copyFade(MODERATE_TOP));

    var prev = copyFade(0);
    var biggest: f32 = 0;
    var lv: f32 = 0;
    while (lv <= MODERATE_TOP) : (lv += 1e-3) {
        const c = copyFade(lv);
        biggest = @max(biggest, @abs(c - prev));
        prev = c;
    }
    // A thousandth of level moves the sheet by about a thousandth of its top — no edge anywhere in the range.
    try std.testing.expect(biggest < COPY_TOP * 0.01);

    // …and the WHOLE ramp is what it fades over, which is seconds and not a frame.
    const secs = (MODERATE_TOP - DOUBLE_AT) * RAMP_IN;
    try std.testing.expect(secs > 3.0);
    std.debug.print("  rain: the heavy sheet fades up over {d:.1}s and out over {d:.1}s\n", .{ secs, (MODERATE_TOP - DOUBLE_AT) * RAMP_OUT });
}

test "THE FALL WRAPS ON THE CELL, so the sheet has no seam and no end" {
    // The phase is what the draw slides the column by, and it may never leave [0, CELL_H) — one metre past it
    // and a whole cell of rain pops a body length up the screen.
    var t: f32 = 0;
    while (t < 30.0) : (t += 1.0 / 60.0) {
        const phase = @mod(t * FALL_MPS, CELL_H);
        try std.testing.expect(phase >= 0 and phase < CELL_H);
    }
    // …and the column reaches over the tallest thing a player stands beside (the knight's 5.2 m crown).
    const tall = @as(f32, @floatFromInt(STACKS)) * CELL_H - STACK_UNDER * CELL_H;
    try std.testing.expect(tall > 5.5);
    // It also has to fall FASTER than it is long, or a streak crosses less than its own body in a frame and
    // the sheet reads as hanging string.
    try std.testing.expect(FALL_MPS > LEN_HI * 10.0);
}

test "THE FIRST STORM LANDS INSIDE A SESSION, at the seed the game actually ships" {
    // **THE BUG: A SEEDED STREAM MAKES A LONG OPENING DRAW PERMANENT.** At `DRY_LO..DRY_HI` the game's own
    // seed drew 394 s, and because the seed is fixed that was 394 s on EVERY launch of the build — the
    // feature was invisible unless you played six and a half minutes without opening a menu. Pinned at the
    // REAL seed, not a test one, because the whole failure was that one particular draw is the only draw
    // that ever happens.
    const SEED: u64 = 0x5701_A17E; // `game.init`'s own
    var w = Weather.init(SEED);
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var seen: f32 = -1;
    while (t < 600.0 and seen < 0) : (t += dt) {
        w.tick(dt);
        if (w.level > 0.02) seen = t; // …when it is actually ON SCREEN (`Rain.draw`'s own floor), not merely wet
    }
    std.debug.print("\n  weather: first rain visible {d:.0}s into a session (opening gap {d:.0}..{d:.0}s)\n", .{ seen, OPEN_LO, OPEN_HI });
    try std.testing.expect(seen > 0);
    try std.testing.expect(seen < OPEN_HI + RAMP_IN);
    // …AND IT STILL IS NOT RAINING WHEN YOU ARRIVE. The opening is short, not absent: walking out of the
    // boot screen into a downpour makes it the weather rather than an event in it.
    var fresh = Weather.init(SEED);
    fresh.tick(dt);
    try std.testing.expectEqual(@as(f32, 0), fresh.rain());

    // …AND EVERY SEED OPENS INSIDE THE SAME WINDOW, so this is the rule and not one lucky number.
    for ([_]u64{ 1, 2, 7, 0xBEEF, 0xD0D0, 0x5701_A17E }) |sd| {
        var g = Weather.init(sd);
        var u: f32 = 0;
        var got: f32 = -1;
        while (u < OPEN_HI + RAMP_IN + 1.0 and got < 0) : (u += dt) {
            g.tick(dt);
            if (g.level > 0.02) got = u;
        }
        try std.testing.expect(got > 0);
    }
}

// ── THE STRAY BANKS ─────────────────────────────────────────────────────────────────────────────────────
//
// **MIST THAT DRIFTS THROUGH, AND ONLY WHEN THE AIR IS ALREADY THICK** (owner: stray volumetric clouds, very
// translucent, gradient-based, flit around softly and slowly during foggy times — VERY slow). The haze
// (`gfx.HAZE_STORM`) is the AIR: it closes the distance evenly and has no shape at all. These are the shape —
// a few banks of it standing in the field, so the fog is somewhere you walk through rather than a value.
//
// **THE GRADIENT IS IN THE GEOMETRY, NOT IN A TEXTURE AND NOT IN SHELLS.** One bank is a CLUSTER of overlapping
// lumps scattered through a flattened volume with the density falling off outward, so the alpha COMPOUNDS where
// they pile up in the middle and thins toward the rim where they run out. That is what makes a soft edge
// without a per-vertex opacity — vertex alpha here is the EMISSIVE channel (`gfx`'s law) — and without three
// concentric shells, each of which would read as a ring. ONE DRAW per bank.
//
// **AND IT IS SLOWER THAN ANYTHING ELSE IN THE GAME.** `DRIFT_HI` is 0.16 m/s: a bank takes a minute and a half
// to cross its own width. Anything you can watch moving reads as a prop being slid; the whole point of this is
// that you never catch it moving, you only notice it has moved.

/// How many may stand at once. STRAY, so it is a handful — a field evenly filled with them is the haze again
/// with more draw calls.
pub const MIST_CAP: usize = 7;
/// **AND THREE SHAPES OF ONE**, the repeated-big-prop law: one cluster placed seven times is a periodic
/// pattern, and yaw does not hide it.
pub const MIST_KINDS: usize = 3;
/// Lumps in one bank, and how big each is against the bank's own radius. Many and small: the overlap IS the
/// gradient, and a cluster of four reads as four balls.
const LUMPS: usize = 22;
const LUMP_LO: f32 = 0.30;
const LUMP_HI: f32 = 0.52;
/// A bank is WIDE AND LOW — mist lies in a field, it does not hang in the air like a cloud.
const MIST_FLAT: f32 = 0.34;
/// Sides and segments on one lump. Cheap on purpose: at this opacity nothing here has a silhouette anybody can
/// count the facets of, and there are `LUMPS` of them in every bank.
const LUMP_SEGS: i32 = 5;
const LUMP_SIDES: i32 = 7;

/// How far out from the man a bank may stand, and how big one is ACROSS.
pub const MIST_R: f32 = 46.0;
const SIZE_LO: f32 = 7.0;
const SIZE_HI: f32 = 15.0;
/// …and how high its centre sits off the ground under it.
const RISE_LO: f32 = 0.5;
const RISE_HI: f32 = 2.4;

/// **VERY SLOW** (the owner's own word, twice). Metres a second: the fast end takes 90 s to cross a 15 m bank.
const DRIFT_LO: f32 = 0.045;
const DRIFT_HI: f32 = 0.160;
/// …and it BREATHES rather than only travelling — a slow bob and a slower turn on its own axis, both on periods
/// measured in tens of seconds. This is the "flit", and it is nearly imperceptible per frame by design.
const BOB: f32 = 0.30;
const BOB_SECS_LO: f32 = 26.0;
const BOB_SECS_HI: f32 = 48.0;
const SPIN_LO: f32 = 0.6; // degrees a second
const SPIN_HI: f32 = 2.4;

/// How long one stands before it is re-seeded somewhere else, and the ramp at both ends. Banks do not pop: the
/// one thing a player may never see is one arriving.
/// How long one stands before it is re-seeded somewhere else, and the ramp at both ends. **THE RAMP IS VERY
/// SLOW** (owner: fade in and out very slowly) — nearly half a minute at each end, so a bank is never seen to
/// arrive or to go: what you notice is that the field has changed, never the change. The lives are long enough
/// that the ramp is a fraction of one rather than most of it (a test pins that).
const LIFE_LO: f32 = 110.0;
const LIFE_HI: f32 = 260.0;
const MIST_FADE: f32 = 26.0;

/// **THE CEILING ON ONE BANK'S OPACITY AT FULL FOG.** Very low — `OPACITY`'s own reasoning one system along: a
/// bank you cannot see the world through is a wall standing in the field (owner: should be less opaque).
pub const MIST_TOP: f32 = 0.10;

/// **AND IT THINS AS YOU WALK INTO IT, AND COMES BACK AS YOU LEAVE** (owner's own words). This is the one thing
/// that separates a VOLUME from a painted blob: real mist has no surface, so the moment a lens is inside it
/// there is nothing left to see — where a mesh gets bigger and more solid until it is a grey wall across the
/// frame. Measured against the BANK'S OWN RADIUS, so a big one starts giving way from further out; and off the
/// LENS rather than the man, because it is the camera that ends up inside it.
const NEAR_GONE: f32 = 0.80;
const NEAR_FULL: f32 = 2.30;
/// Under this the whole system ticks nothing and draws nothing. A clear day costs it one comparison.
pub const MIST_MIN: f32 = 0.02;

/// Cold, pale, and MOSTLY SELF-LIT (alpha is the emissive channel, `emis = 1 - a/255`): a smooth mass this big
/// taking the full key would read as a ball with a lit side, which is the one thing mist is not. It still takes
/// some of the hour, so a bank at night is a dark one.
const MIST_COL = rgba(196, 204, 214, 96);

/// ONE BANK.
const Bank = struct {
    pos: rl.Vector3 = mathx.zero3,
    /// Its own radius, and which of the three shapes it is.
    r: f32 = 0,
    kind: usize = 0,
    /// Metres a second on the ground plane, set once when it is seeded: a bank does not change its mind.
    vx: f32 = 0,
    vz: f32 = 0,
    yaw: f32 = 0,
    spin: f32 = 0,
    age: f32 = 0,
    life: f32 = 0,
    bobT: f32 = 0,
    bobSecs: f32 = 0,
};

/// **HOW MUCH OF A BANK IS LEFT AT THIS RANGE** — 0 with the lens inside it, 1 out past `NEAR_FULL` of its own
/// radius. Its own function because two things read it: the draw, and the test that pins the shape.
fn nearFade(bk: Bank, eye: rl.Vector3) f32 {
    const d = mathx.lenV(mathx.subV(bk.pos, eye));
    return mathx.smoothstep(NEAR_GONE * bk.r, NEAR_FULL * bk.r, d);
}

/// **THE BANKS, AND THEIR THREE MESHES.** Permanent like every other model in this file (`Rain`'s own note):
/// the material holds the scene shader and `rl.unloadModel` would take it with it.
pub const Mist = struct {
    models: [MIST_KINDS]rl.Model,
    banks: [MIST_CAP]Bank = [_]Bank{.{}} ** MIST_CAP,
    rng: mathx.Rng = mathx.Rng.init(0x511F_7A11),
    /// Have they been placed yet — the first foggy frame seeds them AROUND him rather than drifting them in
    /// from wherever the last spell left them standing.
    seeded: bool = false,

    pub fn build(shader: rl.Shader) Mist {
        var out: Mist = .{ .models = undefined };
        var rng = mathx.Rng.init(0x3A57_C10D);
        for (&out.models) |*m| m.* = clusterMesh(shader, &rng);
        return out;
    }

    /// ONE BANK'S MESH — lumps through a flattened disc, with the density falling off outward. Unit radius, so
    /// a bank is placed entirely by its own scale.
    fn clusterMesh(shader: rl.Shader, rng: *mathx.Rng) rl.Model {
        var b = gfx.Builder.init();
        b.setMat(.plain); // the emissive path, `Rain`'s own: mist is not a surface either
        b.setAnimY(0); // …and it does not sway: `windAmt` is the flora path and this is not flora
        for (0..LUMPS) |_| {
            const a = rng.angle();
            // `@sqrt` is the uniform disc; multiplying by `u` again pulls them BACK toward the middle, which
            // is what gives the cluster a falling-off rim instead of an edge.
            const u = rng.float();
            const rr = @sqrt(u) * u * 0.92;
            const lr = rng.range(LUMP_LO, LUMP_HI);
            b.addBlob(
                v3(mathx.cosf(a) * rr, rng.signed() * MIST_FLAT * 0.55, mathx.sinf(a) * rr),
                v3(lr, lr * MIST_FLAT, lr * rng.range(0.8, 1.25)),
                LUMP_SEGS,
                LUMP_SIDES,
                MIST_COL,
            );
        }
        return b.toModel(shader);
    }

    /// **HOW SOLID ONE BANK IS RIGHT NOW** — its own ramp in and out, how foggy it is at all, and HOW CLOSE THE
    /// LENS HAS COME (`NEAR_GONE`). Three factors that multiply, so none of them can be reached round.
    fn alphaOf(self: *const Mist, i: usize, fog: f32, eye: rl.Vector3) f32 {
        const bk = self.banks[i];
        if (bk.life <= 0) return 0;
        const inK = mathx.smoothstep(0, MIST_FADE, bk.age);
        const outK = 1.0 - mathx.smoothstep(bk.life - MIST_FADE, bk.life, bk.age);
        return MIST_TOP * mathx.clampF(fog, 0, 1) * inK * outK * nearFade(bk, eye);
    }

    /// Put one somewhere new. `first` may seed it anywhere in the ring; otherwise it comes in from the OUTER
    /// band, so a bank that has just gone out is replaced by one that still has to drift to you.
    fn seed(self: *Mist, i: usize, at: rl.Vector3, groundY: f32, first: bool) void {
        const a = self.rng.angle();
        const rr = if (first) MIST_R * @sqrt(self.rng.float()) else MIST_R * self.rng.range(0.72, 1.0);
        const spd = self.rng.range(DRIFT_LO, DRIFT_HI);
        const heading = self.rng.angle();
        self.banks[i] = .{
            .pos = v3(at.x + mathx.cosf(a) * rr, groundY + self.rng.range(RISE_LO, RISE_HI), at.z + mathx.sinf(a) * rr),
            .r = self.rng.range(SIZE_LO, SIZE_HI) * 0.5,
            .kind = @intFromFloat(self.rng.float() * @as(f32, @floatFromInt(MIST_KINDS)) * 0.999),
            .vx = mathx.cosf(heading) * spd,
            .vz = mathx.sinf(heading) * spd,
            .yaw = mathx.degrees(self.rng.angle()),
            .spin = self.rng.range(SPIN_LO, SPIN_HI) * (if (self.rng.float() < 0.5) @as(f32, -1) else 1),
            // …AND THEY ARE NOT ALL BORN TOGETHER: seeded mid-life, so the first foggy minute is not seven
            // banks fading up on one clock.
            .age = if (first) self.rng.range(0, LIFE_LO * 0.5) else 0,
            .life = self.rng.range(LIFE_LO, LIFE_HI),
            .bobT = self.rng.range(0, 60),
            .bobSecs = self.rng.range(BOB_SECS_LO, BOB_SECS_HI),
        };
    }

    /// THE DRIFT. `at` is the man, `groundY` the height under him, `fog` 0..1 — and at nothing it does nothing,
    /// which is what every clear day in the game pays for this.
    ///
    /// It drifts LEVEL rather than following the terrain under it: at 0.16 m/s nobody can tell, and sampling the
    /// heightfield per bank per frame cannot be justified by a picture nobody can see.
    pub fn tick(self: *Mist, dt: f32, at: rl.Vector3, groundY: f32, fog: f32) void {
        if (fog <= MIST_MIN) {
            self.seeded = false; // the next foggy spell places them around him rather than resuming
            return;
        }
        if (!self.seeded) {
            self.seeded = true;
            for (0..MIST_CAP) |i| self.seed(i, at, groundY, true);
            return;
        }
        for (0..MIST_CAP) |i| {
            const bk = &self.banks[i];
            bk.age += dt;
            bk.bobT += dt;
            bk.pos.x += bk.vx * dt;
            bk.pos.z += bk.vz * dt;
            bk.yaw += bk.spin * dt;
            // RE-SEEDED WHEN ITS TIME IS UP OR IT HAS WANDERED OFF, and never where you can watch it happen: a
            // bank past `MIST_R` is out beyond what the haze itself hides.
            if (bk.age >= bk.life or mathx.distXZ(bk.pos, at) > MIST_R * 1.35) self.seed(i, at, groundY, false);
        }
    }

    /// **ONE BANK AT A KNOWN PLACE AND FULL STRENGTH** — the shot harness's own (`game.forceMistForShot`,
    /// `Weather.force`'s arrangement). The field seeds itself out at 33..46 m because that is where weather
    /// belongs; a PHOTOGRAPH of a bank has to have one in the frame, mid-life and past both ramps.
    pub fn stageOne(self: *Mist, at: rl.Vector3, ahead: f32, facing: f32) void {
        self.seeded = true;
        for (&self.banks) |*b| b.* = .{};
        const d = mathx.headingDir(facing);
        self.banks[0] = .{
            .pos = v3(at.x + d.x * ahead, at.y + RISE_HI, at.z + d.z * ahead),
            .r = SIZE_HI * 0.5,
            .life = LIFE_HI,
            .age = LIFE_HI * 0.5, // mid-life: clear of the ramp in and well short of the ramp out
            .bobSecs = BOB_SECS_LO,
        };
    }

    /// **DRAWN WITH THE RAIN AND ON ITS TERMS** — last, no depth written, still depth TESTED, so a bank sits
    /// behind the tree it is behind. One draw each and no sort: at this opacity which of two banks is in front
    /// is not something anybody can see, and the alternative is a sort every frame for no picture.
    pub fn draw(self: *const Mist, scene: *gfx.Scene, eye: rl.Vector3, fog: f32) void {
        if (fog <= MIST_MIN) return;
        var any = false;
        for (0..MIST_CAP) |i| {
            const a = self.alphaOf(i, fog, eye);
            if (a <= 0.004) continue;
            // ONE begin/end for the whole field — the depth mask is global state, and toggling it seven times
            // is seven chances to leave it off (`Scene.beginFade`'s own law).
            if (!any) {
                scene.beginFade(a);
                any = true;
            } else scene.setFade(a);
            const bk = self.banks[i];
            const bob = mathx.sinf(std.math.tau * bk.bobT / bk.bobSecs) * BOB;
            const s = bk.r;
            rl.drawModelEx(
                self.models[@min(bk.kind, MIST_KINDS - 1)],
                v3(bk.pos.x, bk.pos.y + bob, bk.pos.z),
                v3(0, 1, 0),
                bk.yaw,
                v3(s, s, s),
                rl.Color.white,
            );
        }
        if (any) scene.endFade();
    }
};

test "A BANK IS SLOWER THAN ANYTHING ELSE IN THE WORLD, and you never catch it arriving" {
    // VERY SLOW is the whole brief: the fast end has to take over a minute to cross its own body, or it reads
    // as a prop being slid across the field.
    const crossing = SIZE_HI / DRIFT_HI;
    std.debug.print("\n  mist: a {d:.0} m bank crosses its own width in {d:.0} s ({d:.3}..{d:.3} m/s), {d} banks of {d} lumps\n", .{ SIZE_HI, crossing, DRIFT_LO, DRIFT_HI, MIST_CAP, LUMPS });
    try std.testing.expect(crossing > 60.0);
    // …and it is orders under the rain's own fall, which is the other thing moving in the same frame.
    try std.testing.expect(DRIFT_HI < FALL_MPS * 0.02);
    // THE RAMP IS A REAL FRACTION OF A LIFE, or a re-seed is a pop somewhere in the field.
    try std.testing.expect(MIST_FADE * 2.0 < LIFE_LO);
    // …and a bank is TRANSLUCENT: two of them in a line is still a world you can see through.
    try std.testing.expect(MIST_TOP < 0.25);
    // …AND THE WHOLE FIELD IS CHEAPER THAN THE RAIN IT STANDS IN.
    const tris = MIST_CAP * LUMPS * @as(usize, @intCast(LUMP_SEGS * LUMP_SIDES * 2));
    std.debug.print("  ...and the whole field is {d} draws, {d} tris\n", .{ MIST_CAP, tris });
    try std.testing.expect(MIST_CAP <= STACKS + COPY_STACKS);
}

test "THE BANKS COST NOTHING ON A CLEAR DAY, and the first foggy frame places them around him" {
    var m = Mist{ .models = undefined };
    // Dry: it does not tick, does not seed, and draws nothing.
    m.tick(1.0 / 60.0, mathx.zero3, 0, 0);
    try std.testing.expect(!m.seeded);
    try std.testing.expectEqual(@as(f32, 0), m.alphaOf(0, 0, mathx.zero3));

    // The first foggy frame places every one of them, inside the ring, none at more than its ceiling. Judged
    // from a lens well outside the field, or the near fade is what is being measured instead.
    const far = v3(0, 2, -400);
    m.tick(1.0 / 60.0, mathx.zero3, 0, 1.0);
    try std.testing.expect(m.seeded);
    for (0..MIST_CAP) |i| {
        const bk = m.banks[i];
        try std.testing.expect(bk.life >= LIFE_LO and bk.life <= LIFE_HI);
        try std.testing.expect(mathx.distXZ(bk.pos, mathx.zero3) <= MIST_R + 1e-3);
        try std.testing.expect(bk.kind < MIST_KINDS);
        try std.testing.expect(m.alphaOf(i, 1.0, far) <= MIST_TOP + 1e-5);
        try std.testing.expect(bk.r >= SIZE_LO * 0.5 and bk.r <= SIZE_HI * 0.5);
    }

    // …AND THEY ARE RE-SEEDED RATHER THAN LOST: an hour of drift leaves the same seven standing, every one of
    // them still inside the ring, and none of it reads a wall clock.
    var t: f32 = 0;
    while (t < 3600.0) : (t += 1.0 / 30.0) {
        m.tick(1.0 / 30.0, mathx.zero3, 0, 1.0);
        for (0..MIST_CAP) |i| try std.testing.expect(mathx.distXZ(m.banks[i].pos, mathx.zero3) <= MIST_R * 1.36);
    }
    // …and a clear spell puts them away, so the next one does not resume from where the last left off.
    m.tick(1.0 / 60.0, mathx.zero3, 0, 0);
    try std.testing.expect(!m.seeded);
}

test "A BANK GIVES WAY AS YOU WALK INTO IT, AND COMES BACK AS YOU LEAVE" {
    // **THE THING THAT SEPARATES A VOLUME FROM A PAINTED BLOB** (owner: fade out as you near it and back in
    // when you step away). Mist has no surface, so a lens inside it has nothing left to look at — where a mesh
    // simply gets bigger and more solid until it is a grey wall across the frame.
    const bk = Bank{ .pos = mathx.zero3, .r = 6.0, .life = LIFE_HI, .age = LIFE_HI * 0.5 };
    try std.testing.expectEqual(@as(f32, 0), nearFade(bk, mathx.zero3)); // dead inside: nothing at all
    try std.testing.expectEqual(@as(f32, 0), nearFade(bk, v3(NEAR_GONE * bk.r * 0.99, 0, 0)));
    try std.testing.expectEqual(@as(f32, 1), nearFade(bk, v3(NEAR_FULL * bk.r + 0.01, 0, 0)));
    // …and MONOTONE across the whole approach, so walking in never brightens it for a step.
    var prev: f32 = 1.0;
    var d: f32 = NEAR_FULL * bk.r + 2.0;
    while (d >= 0) : (d -= 0.05) {
        const got = nearFade(bk, v3(d, 0, 0));
        try std.testing.expect(got <= prev + 1e-6);
        prev = got;
    }
    // IT IS THE LENS, NOT THE MAN: the camera is what ends up inside one, and it sits metres off him.
    try std.testing.expect(nearFade(bk, v3(0, 12.0, 0)) > 0.5); // …so height counts too, looking down on it

    // A BIG BANK STARTS GIVING WAY FROM FURTHER OUT, which is what makes it read as a volume of a size rather
    // than a sprite with one fade distance.
    var small = bk;
    small.r = 3.5;
    const at: f32 = 8.0;
    try std.testing.expect(nearFade(small, v3(at, 0, 0)) > nearFade(bk, v3(at, 0, 0)));

    // …AND THE SLOW RAMP IS A FRACTION OF A LIFE, not most of one: a bank has to STAND for a while between
    // arriving and going, or the field is nothing but ramps.
    try std.testing.expect(MIST_FADE * 3.0 < LIFE_LO);
    std.debug.print("  mist: {d:.0}s ramps inside a {d:.0}..{d:.0}s life, gone within {d:.1}x its radius, full past {d:.1}x\n", .{ MIST_FADE, LIFE_LO, LIFE_HI, NEAR_GONE, NEAR_FULL });
}
