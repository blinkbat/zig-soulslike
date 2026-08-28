const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;
const placeAt = mathx.placeAt;

// THE SLUMBER BLOOM — a FIXTURE (`foe.Gait.rooted`) and the only thing in the world that fills a SLEEP meter.
// **NO BLOW AT ALL**: it swells, it vents, and the gas puts you on the floor next to whatever else is in the
// room. Its counter is that it cannot follow you.
//
// **THE TELL IS THE SWELL AND IT IS THE WHOLE FIGHT** — 0.9 s of the bulb inflating with the gills clamped, three
// times `foe.TELL_MIN` and long enough to leave at a walk.

// **SOLVED, NOT PICKED** (AGENTS.md): `albedo = screen^2.2 / 1.72`. Authored by eye at a mid 96,100,142 the cap
// came back at 213/255 — a white ball on a stick. HUE separates these as much as value, because a smooth mass
// this size loses value under the key.
//
//   cap 0.42 screen -> 21    crown 0.58 -> 45    gill 0.72 -> 72    deep 0.38 -> 18    mat 0.42 -> 22
/// The sleep meter's own family (`hud.ailTint(.sleep)`): the thing that puts you under is the colour of the bar.
const CAP_SKIN = rgba(20, 21, 38, 255);
const CAP_SKIN_DK = rgba(9, 10, 20, 255);
const CAP_BLOOM = rgba(42, 45, 66, 255);
const GILL_PALE = rgba(76, 73, 64, 255);
const GILL_DEEP = rgba(19, 18, 18, 255);
/// **ITS OWN STALK, NOT `propart`'S** — that one is authored for shade and comes back pale in the open.
const STIPE = rgba(38, 35, 28, 255);
const STIPE_DK = rgba(22, 20, 16, 255);
// **AND THE MAT IS NOT THE BRIGHTEST THING ON THE BODY.** Sampled at 0.59 against a 0.37 ground it was a pale
// saucer pulling the eye off the bulb that carries the tell.
const MYCEL = rgba(26, 24, 20, 255);
/// The gas: gone by the rim, so it is a wall you can see the edge of.
const HAZE = rgba(158, 166, 214, 96);
const HAZE_THIN = rgba(196, 200, 226, 30);

pub const H: f32 = 1.35;

pub const AGGRO_R: f32 = 9.0;
/// **IT OPENS BEFORE IT CAN REACH YOU** (the rooted's law) — the wake ring is outside the gas.
const WAKE_R: f32 = 7.6;

const BODY_R: f32 = 0.52;
const HURT_R: f32 = 0.72;
const CENTER_F: f32 = 0.56;
const TOP_F: f32 = 1.02;

const HP_MAX: f32 = 58.0;
const POISE_MAX: f32 = 18.0;
const STANCE_MAX: f32 = 30.0;
/// A PLANT ANSWERED WITH FIRE (the sporeling's column, harder) — chaos slides off the thing that makes chaos.
const RESISTS = combat.resists(.{ .fire = -60, .cold = 10, .lightning = -15, .chaos = 70 });
pub const SOULS: u32 = 130;

/// **LIVE ONLY WHILE THE THING IS VENTING.** No lingering cloud object — the sporeling owns that pattern
/// (`shroom.Cluster.clouds`), and a second invisible soak is a second thing to be hurt by with nothing to blame.
pub const POUR_R: f32 = 5.0;
pub const POUR_DUR: f32 = 2.0;
/// **AT THE THROAT, WHICH IS NOT WHAT A WHOLE POUR DELIVERS.** The pressure tails off (`POUR_TAIL`), so what
/// lands is the AREA under that curve. A pin over the PEAK read 110 against a 100 meter while the thing was
/// really handing out 80 and could put nobody under.
pub const POUR_BUILD: f32 = 70.0;
/// The pressure lost by the far end, as `1 - POUR_TAIL*u^2`: a pour that comes out flat and stops dead is a switch.
const POUR_TAIL: f32 = 0.65;
/// The area under it, solved: the integral of `1 - k*u^2` on [0,1] is `1 - k/3`.
const POUR_SHAPE: f32 = 1.0 - POUR_TAIL / 3.0;

const SWELL_DUR: f32 = 0.90;
const RECOVER_DUR: f32 = 1.30;
const POUR_CD: f32 = 6.5;
const WAKE_DUR: f32 = 0.65;

comptime {
    std.debug.assert(SWELL_DUR >= foe.TELL_MIN);
    // A WHOLE POUR FILLS A METER AND HALF OF ONE DOES NOT — both over the AREA. Too little and it is scenery,
    // too much and the tell is decoration. The half integrates on [0, 0.5], which is not half the whole.
    const row = combat.ailRow(.sleep);
    std.debug.assert(POUR_DUR * POUR_BUILD * POUR_SHAPE > row.max);
    const halfArea = 0.5 - POUR_TAIL * 0.125 / 3.0;
    std.debug.assert(POUR_DUR * POUR_BUILD * halfArea < row.max);
    std.debug.assert(POUR_R < WAKE_R and WAKE_R < AGGRO_R);
}

const DEATH_DUR: f32 = 0.75;
const DISS_DUR: f32 = 0.85;
const DISSOLVE = foe.Dissolve{ .rate = 54.0, .spread = 0.75, .rise = 0.9, .flake = GILL_PALE };

const SWAY_HZ: f32 = 0.21;
const SWAY_DEG: f32 = 2.6;
const BREATHE_HZ: f32 = 0.34;

const VENT_RATE: f32 = 96.0;
const VENT_LIFE_HI: f32 = 1.4;
const SWELL_MOTES = 10;
const HIT_PUFF_LIGHT = 4;
const HIT_PUFF_HEAVY = 9;
/// Sized by ARITHMETIC over the worst frame (the ring law): the vent's residents plus a heavy blow inside the pour.
const PARTS = 176;
comptime {
    std.debug.assert(@as(f32, PARTS) >= VENT_RATE * VENT_LIFE_HI +
        @as(f32, @floatFromInt(SWELL_MOTES + foe.hitParts(HIT_PUFF_HEAVY) + foe.WOUND_PARTS)));
}

const N = 9;
const ROOT = 0;
const STIPE_B = 1;
const BULB = 2;
const GILL_0 = 3;
const GILL_N = 6;

const STIPE_Y: f32 = 0.06 * H;
const BULB_Y: f32 = 0.62 * H;
/// **UNDER THE BULB, NOT INSIDE IT.** At 0.50 against a bulb spanning 0.42 to 0.82, six lobes were posed and
/// drawn entirely within the mass that hid them. The underside is 0.62 - 0.085 - 0.100 = 0.435.
const GILL_Y: f32 = 0.40 * H;
const GILL_R: f32 = 0.155 * H;

comptime {
    // Clear the mass, or the skirt is invisible and the creature is a ball on a stick.
    std.debug.assert(GILL_Y < BULB_Y - 0.085 * H - 0.100 * H);
    // …and INSIDE it across, so the lobes come from under a rim rather than floating off the sides.
    std.debug.assert(GILL_R < 0.235 * H);
}

const REST = blk: {
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, 0, 0);
    r[STIPE_B] = v3(0, STIPE_Y, 0);
    r[BULB] = v3(0, BULB_Y, 0);
    for (0..GILL_N) |i| {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / GILL_N;
        r[GILL_0 + i] = v3(@cos(a) * GILL_R, GILL_Y, @sin(a) * GILL_R * 0.9);
    }
    break :blk r;
};

/// **NO TWO GILLS THE SAME.** One mesh set is shared by every bloom, so the wabi-sabi is between the six lobes
/// of one and never between the instances (the barber's-pole law, at the right scale).
// **AND A GILL IS UNDER THE CAP, NOT PAST IT.** At 0.28..0.46 these ran to 0.62 m against a rim 0.317 m out and
// dived past the mat as PLANKS. Off the rim instead: a 0.209 m collar plus 0.16..0.24 puts the tips at 0.42 m.
const GILL_LEN = [GILL_N]f32{ 0.22, 0.16, 0.24, 0.18, 0.20, 0.155 };
const GILL_DROOP = [GILL_N]f32{ 20.0, 32.0, 16.0, 27.0, 23.0, 35.0 };

pub const State = enum { dormant, wake, idle, swell, pour, recover, stunlight, stunheavy, dead };

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        return .{ .mesh = buildMeshes(), .mat = gfx.material(shader, "slumber bloom") };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, b: *const Bloom) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, b.xf[i]);
    }
};

pub const Bloom = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// Its FEET are a no-op, but `foe.grip` also bills a held spell's chaos — left out, a cast on this creature
    /// is focus spent for nothing (the rooted's lesson).
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .dormant,
    t: f32 = 0,
    elapsed: f32 = 0,
    cd: f32 = 0,

    /// The unfold, 0 shut to 1 open.
    open: f32 = 0,
    /// ON TOP of `open`: the swell is the tell, so it may not be the unfold's fraction.
    swell: f32 = 0,
    /// The ONE number the gas, the motes and the sound all read.
    vent: f32 = 0,
    breathe: f32 = 0,
    sway: f32 = 0,
    swelled: bool = false,
    vented: bool = false,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    yelped: bool = false,
    threat: foe.Threat = .{},
    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Bloom {
        var b = Bloom{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        b.fxRng = foe.fxStream(seed, 5171.0, 0x8B00D);
        b.cd = seed * POUR_CD;
        b.pose();
        return b;
    }

    pub fn centerWorld(self: *const Bloom) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, 0);
    }
    pub fn lockPoint(self: *const Bloom) rl.Vector3 {
        return foe.markOn(self.xf[BULB], mathx.zero3);
    }
    pub fn topWorld(self: *const Bloom) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Bloom) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Bloom) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Bloom) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Bloom) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Bloom) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(self: *const Bloom) bool {
        _ = self;
        return false;
    }
    pub fn flashFrac(self: *const Bloom) f32 {
        return foe.flashFrac(self.flash);
    }
    /// **SCENERY UNTIL YOU WALK UP ON IT** (the snag's read) — the lock-on and the spirit's quarry both skip it.
    pub fn hidden(self: *const Bloom) bool {
        return self.state == .dormant;
    }
    /// Where the gas leaves from, and where the swell reads biggest.
    pub fn ventWorld(self: *const Bloom) rl.Vector3 {
        return foe.markOn(self.xf[BULB], v3(0, 0.10 * H, 0));
    }

    /// Zero unless this one is venting. `combat.Vitals.ailRate` is where the waker's nail is answered.
    pub fn breath(self: *const Bloom, hero: rl.Vector3) f32 {
        if (self.gone or self.vent <= 0.01) return 0;
        if (mathx.distXZ(self.pos, hero) > POUR_R * self.scale) return 0;
        return POUR_BUILD * self.vent;
    }

    pub fn update(self: *Bloom, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) void {
        _ = bounds;
        self.swelled = false;
        self.vented = false;
        self.yelped = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return;
        }
        self.justDied = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        self.cd = mathx.maxF(0, self.cd - dt);
        foe.tickFixedLeash(&self.leash, dt, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);

        const d = mathx.distXZ(self.pos, hero);
        var wantVent: f32 = 0;

        switch (self.state) {
            .dormant => {
                self.open = mathx.approach(self.open, 0, dt * 1.5);
                self.swell = mathx.approach(self.swell, 0, dt * 2.0);
                if (d <= WAKE_R) self.beginWake();
            },
            .wake => {
                // `max` and not a bare assign: woken again mid-shut it picks up wherever the fold had got to.
                self.open = mathx.maxF(self.open, mathx.smoothstep(0, WAKE_DUR, self.t));
                if (self.t >= WAKE_DUR) self.enter(.idle);
            },
            .idle => {
                self.open = mathx.approach(self.open, 1.0, dt * 2.6);
                self.swell = mathx.approach(self.swell, 0, dt * 1.8);
                if (d > WAKE_R) {
                    self.enter(.dormant);
                } else if (self.cd <= 0 and d <= POUR_R * self.scale) {
                    self.enter(.swell);
                }
            },
            // THE TELL. The gills CLAMP while the bulb fills, so the silhouette says "about to" in two channels
            // and neither is a colour change.
            .swell => {
                const u = mathx.clampF(self.t / SWELL_DUR, 0, 1);
                self.swell = mathx.smoothstep(0, 1, u);
                self.open = mathx.approach(self.open, 1.0 - 0.45 * self.swell, dt * 3.0);
                if (self.t >= SWELL_DUR) {
                    self.enter(.pour);
                    self.vented = true;
                    // ON THIS FRAME, not the next: an open throat with no gas in it tells the player nothing.
                    wantVent = 1;
                }
            },
            .pour => {
                const u = mathx.clampF(self.t / POUR_DUR, 0, 1);
                // A MASS IN MOTION OVERSHOOTS ITS REST: the gills fling past open as the pressure goes.
                self.open = mathx.approach(self.open, 1.0 + 0.28 * (1.0 - u), dt * 7.0);
                self.swell = mathx.approach(self.swell, 0, dt * 1.6);
                wantVent = mathx.clampF(1.0 - u * u * POUR_TAIL, 0, 1);
                if (self.t >= POUR_DUR) {
                    self.cd = POUR_CD;
                    self.enter(.recover);
                }
            },
            .recover => {
                self.open = mathx.approach(self.open, 0.72, dt * 2.2);
                self.swell = mathx.approach(self.swell, 0, dt * 2.4);
                if (self.t >= RECOVER_DUR) self.enter(.idle);
            },
            .stunlight, .stunheavy => {
                self.open = mathx.approach(self.open, 0.35, dt * 5.0);
                self.swell = mathx.approach(self.swell, 0, dt * 6.0);
                if (!self.vit.stunned()) self.enter(.idle);
            },
            .dead => {
                self.open = mathx.approach(self.open, 0, dt * 1.2);
                self.swell = mathx.approach(self.swell, 0, dt * 3.0);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        // **A PRESSURISED BAG OPENS AT FULL PRESSURE.** Snap ON, ease OFF — an eased rise cost a tenth of the
        // pour's area, the quiet shortfall `POUR_SHAPE` is solved to rule out.
        self.vent = if (wantVent > self.vent) wantVent else mathx.approach(self.vent, wantVent, dt * 9.0);
        if (self.state == .swell and !self.swelled and self.t < dt * 1.5) self.swelled = true;
        self.breathe = mathx.sinf((self.elapsed + self.seed * 5.0) * BREATHE_HZ * std.math.tau);
        self.sway = mathx.sinf((self.elapsed + self.seed * 7.0) * SWAY_HZ * std.math.tau) * SWAY_DEG * self.open;
        self.emitVent(dt);
        if (self.state == .swell) self.emitDraw(dt);
        self.pose();
        self.tryHit(blade);
    }

    fn enter(self: *Bloom, s: State) void {
        self.state = s;
        self.t = 0;
    }

    fn beginWake(self: *Bloom) void {
        sfx.world(.shroom_puff, self.centerWorld());
        self.enter(.wake);
        self.swelled = true;
    }

    fn enterStun(self: *Bloom, s: State) void {
        self.enter(s);
        self.vit.beginStun(if (s == .stunheavy) .heavy else .light);
    }

    fn enterDeath(self: *Bloom) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    pub fn debugKill(self: *Bloom) void {
        self.enterDeath();
    }
    /// **A STAGGER CUTS THE POUR OFF MID-BREATH** — the whole reward for going in after it, and the reason the
    /// cooldown is spent here and not only at the far end of `pour`.
    pub fn stagger(self: *Bloom, heavy: bool) void {
        if (self.state == .pour) self.cd = POUR_CD;
        self.vent = 0;
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugWake(self: *Bloom) void {
        if (self.state == .dormant) self.beginWake();
    }
    pub fn debugPour(self: *Bloom) void {
        self.open = 1;
        self.cd = 0;
        self.enter(.swell);
    }

    pub fn tryHit(self: *Bloom, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        if (self.state == .dormant) self.beginWake();
        // NOTHING SHOVES IT (the fixture's rule) — `foe.wounded` writes the field either way, and a real number
        // slides a thing whose whole design is that it cannot move.
        const heavy = foe.wounded(self, s, blade, .{ .light = 0, .heavy = 0 });
        self.puff(s.contact, foe.hitParts(if (heavy) HIT_PUFF_HEAVY else HIT_PUFF_LIGHT));
        self.yelped = true;
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.stagger(true),
            .light => self.stagger(false),
            .none => {},
        }
    }

    /// The same dust the pour is made of, thrown rather than exhaled.
    fn puff(self: *Bloom, at: rl.Vector3, motes: i32) void {
        var i: i32 = 0;
        while (i < motes) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.5, 1.0) * 2.1;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + self.fxRng.signed() * 0.08, at.y + self.fxRng.signed() * 0.08, at.z + self.fxRng.signed() * 0.08),
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.4, 1.5), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.5, 1.1),
                .r0 = self.fxRng.range(0.030, 0.070) * self.scale,
                .r1 = self.fxRng.range(0.010, 0.026) * self.scale,
                .col = if (self.fxRng.float() < 0.45) GILL_PALE else HAZE,
                .col1 = HAZE_THIN,
                .grav = 0.5,
                .drag = 3.4,
            });
        }
    }

    /// **THE GAS FILLS THE RING IT DOSES.** sqrt of a uniform spreads the motes EVENLY over the disc; linear in
    /// radius piles them at the throat and the edge you have to be outside of is invisible.
    fn emitVent(self: *Bloom, dt: f32) void {
        if (self.vent <= 0.01) return;
        const from = self.ventWorld();
        const r = POUR_R * self.scale;
        self.fxAccum += VENT_RATE * self.vent * dt;
        while (self.fxAccum >= 1.0) : (self.fxAccum -= 1.0) {
            const a = self.fxRng.angle();
            const rad = r * @sqrt(self.fxRng.float());
            const out = v3(mathx.cosf(a), 0, mathx.sinf(a));
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(from.x + out.x * rad * 0.12, from.y - self.fxRng.range(0, 0.35) * H * self.scale, from.z + out.z * rad * 0.12),
                // Outward and BARELY up: heavier than air, so it is a thing on the floor with a near edge you
                // can see rather than a fog the camera sits in.
                .v = v3(out.x * rad * 0.9, self.fxRng.range(-0.05, 0.55), out.z * rad * 0.9),
                .life = self.fxRng.range(0.7, VENT_LIFE_HI),
                .r0 = self.fxRng.range(0.10, 0.24) * self.scale,
                .r1 = self.fxRng.range(0.16, 0.40) * self.scale,
                .col = HAZE,
                .col1 = HAZE_THIN,
                .grav = 0.22,
                .drag = 1.5,
            });
        }
    }

    /// The one emitter in the game that runs BACKWARDS: motes pulled in toward the throat.
    fn emitDraw(self: *Bloom, dt: f32) void {
        if (self.fxRng.float() > dt * @as(f32, SWELL_MOTES)) return;
        const to = self.ventWorld();
        const a = self.fxRng.angle();
        const rad = self.fxRng.range(0.9, 2.2) * self.scale;
        const p = v3(to.x + mathx.cosf(a) * rad, to.y - self.fxRng.range(0, 0.5), to.z + mathx.sinf(a) * rad);
        const pull = 2.4;
        foe.emitPart(&self.parts, &self.fxHead, .{
            .p = p,
            .v = mathx.scaleV(mathx.normV(mathx.subV(to, p)), pull),
            .life = rad / pull,
            .r0 = self.fxRng.range(0.030, 0.062) * self.scale,
            .r1 = 0.008,
            .col = HAZE,
            .col1 = CAP_BLOOM,
            .drag = 0,
        });
    }

    pub fn drawFx(self: *const Bloom) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Bloom, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Bloom) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const root = mul3(
            scaleM(fs, fs, fs),
            ry(mathx.degrees(self.facing)),
            tr(self.pos.x, self.pos.y, self.pos.z),
        );
        self.xf[ROOT] = root;

        // The stalk takes the sway and NOTHING ELSE: leaned at the root it slides on its own mycelium.
        self.xf[STIPE_B] = placeAt(REST[STIPE_B], mul(rx(self.sway), rz(self.sway * 0.6)), root);

        // A SCALE and not a translate — the swell is a real change of mass, and a bag under pressure goes wide
        // before it goes tall.
        const fat = 1.0 + 0.30 * self.swell + 0.020 * self.breathe;
        const tall = 1.0 + 0.13 * self.swell + 0.014 * self.breathe;
        self.xf[BULB] = placeAt(REST[BULB], mul(
            scaleM(fat, tall, fat),
            rx(self.sway * 1.4),
        ), self.xf[STIPE_B]);

        for (0..GILL_N) |i| {
            const b = GILL_0 + i;
            const fi: f32 = @floatFromInt(i);
            // Each lobe has its OWN droop, so the six do not move as one plate.
            const droop = lerpF(-74.0, GILL_DROOP[i], mathx.clampF(self.open, 0, 1.3));
            const flutter = mathx.sinf((self.elapsed + self.seed * 4.0) * (1.7 + 0.29 * fi) * std.math.tau) * 3.2 * self.vent;
            const a = std.math.tau * fi / GILL_N;
            self.xf[b] = placeAt(REST[b], mul3(
                ry(mathx.degrees(a)),
                rx(droop + flutter),
                scaleM(1, 1, 1.0 + 0.10 * self.swell),
            ), self.xf[STIPE_B]);
        }
    }
};

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = emptyMesh();
    mesh[STIPE_B] = stipeMesh();
    mesh[BULB] = bulbMesh();
    for (0..GILL_N) |i| mesh[GILL_0 + i] = gillMesh(GILL_LEN[i], 611 + @as(u64, i));
    return mesh;
}

fn emptyMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plant);
    b.addBlob(mathx.zero3, v3(0.004, 0.004, 0.004), 3, 4, STIPE_DK);
    return b.toMesh();
}

/// **A COLUMN OF FLESH, NOT A PIPE** — capsules, off the vertical, because nothing that grew is plumb.
fn stipeMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB100);
    b.setMat(.plant);
    const segs: f32 = 4;
    var y: f32 = 0;
    var cx: f32 = 0;
    var cz: f32 = 0;
    const lean = rng.angle();
    var i: f32 = 0;
    while (i < segs) : (i += 1) {
        const t = i / (segs - 1);
        const h = 0.56 * H / segs;
        const r0 = lerpF(0.115, 0.082, t) * H * rng.range(0.94, 1.06);
        const r1 = lerpF(0.115, 0.082, t + 1.0 / segs) * H;
        b.addCapsule(
            v3(cx, y, cz),
            v3(cx + mathx.cosf(lean) * 0.010 * H, y + h, cz + mathx.sinf(lean) * 0.010 * H),
            r0,
            r1,
            11,
            if (@mod(i, 2) == 0) STIPE else STIPE_DK,
        );
        y += h;
        cx += mathx.cosf(lean) * 0.010 * H + rng.signed() * 0.006 * H;
        cz += mathx.sinf(lean) * 0.010 * H + rng.signed() * 0.006 * H;
    }
    // A plant with no ground contact is a plant floating. THREE overlapping lobes and not one ellipse: a perfect
    // disc at the foot of it read as a saucer.
    b.addBlob(v3(0, 0.014 * H, 0), v3(0.26 * H, 0.028 * H, 0.23 * H), 3, 11, MYCEL);
    var m: usize = 0;
    while (m < 3) : (m += 1) {
        const a = rng.angle();
        const d = rng.range(0.08, 0.19) * H;
        b.addBlob(
            v3(mathx.cosf(a) * d, 0.010 * H, mathx.sinf(a) * d),
            v3(rng.range(0.10, 0.19) * H, 0.022 * H, rng.range(0.09, 0.17) * H),
            3,
            9,
            if (m == 1) STIPE_DK else MYCEL,
        );
    }
    var c: usize = 0;
    while (c < 5) : (c += 1) {
        const a = rng.angle();
        const d = rng.range(0.16, 0.34) * H;
        b.addCapsule(
            v3(0, 0.016 * H, 0),
            v3(mathx.cosf(a) * d, 0.008 * H, mathx.sinf(a) * d),
            0.020 * H,
            0.006 * H,
            5,
            MYCEL,
        );
    }
    return b.toMesh();
}

/// **ROUND BECAUSE IT IS FLESH**, and three blobs rather than one: a single ellipsoid this size is a beach ball.
fn bulbMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xB101);
    b.setMat(.plant);
    b.addBlob(mathx.zero3, v3(0.235 * H, 0.200 * H, 0.222 * H), 6, 13, CAP_SKIN);
    b.addBlob(v3(rng.signed() * 0.012 * H, 0.070 * H, rng.signed() * 0.010 * H), v3(0.185 * H, 0.135 * H, 0.176 * H), 5, 12, CAP_BLOOM);
    b.addBlob(v3(0, -0.085 * H, 0.010 * H), v3(0.196 * H, 0.100 * H, 0.186 * H), 5, 11, CAP_SKIN_DK);
    b.addCylinder(v3(0, 0.120 * H, 0), v3(0, 0.168 * H, 0), 0.070 * H, 0.086 * H, 11, CAP_SKIN_DK);
    b.addBlob(v3(0, 0.108 * H, 0), v3(0.062 * H, 0.026 * H, 0.062 * H), 3, 9, GILL_DEEP);
    // A FEW PERCENT OF THE MASS, not a tenth (the relief law). At 0.030 seated on the surface these were PEGS
    // stuck in a ball; halved and seated INSIDE the 0.235 bulb, a couple of cm of a thirty-cm mass stays proud.
    var w: usize = 0;
    while (w < 11) : (w += 1) {
        const a = rng.angle();
        const el = rng.range(-0.5, 0.9);
        const rr = rng.range(0.010, 0.018) * H;
        const d = 0.208 * H;
        b.addBlob(
            v3(mathx.cosf(a) * d * @cos(el), 0.200 * H * @sin(el), mathx.sinf(a) * d * @cos(el)),
            v3(rr, rr * 0.7, rr),
            2,
            7,
            if (rng.float() < 0.5) CAP_BLOOM else GILL_PALE,
        );
    }
    return b.toMesh();
}

/// A fan of blades on a fleshy spine. Blunt at the tip: nothing here ends in a point.
fn gillMesh(len: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.plant);
    const L = len * H;
    b.addCapsule(mathx.zero3, v3(0, 0, L), 0.036 * H, 0.024 * H, 7, CAP_SKIN_DK);
    b.addBlob(v3(0, 0, L), v3(0.030 * H, 0.020 * H, 0.026 * H), 3, 7, CAP_SKIN);
    // **A GILL IS A PLATE ON EDGE: THIN ACROSS, DEEP ALONG, HANGING DOWN.** Built the other way round — big
    // tangential half-width, almost no height — six lobes came back as a stack of CRATES on a pole. The axes are
    // `addBox(centre, tangential, vertical, radial)`, so the first must be SMALL and the other two must not.
    const segs = 4;
    var i: usize = 0;
    while (i < segs) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / segs;
        const t1 = @as(f32, @floatFromInt(i + 1)) / segs;
        const zc = L * (t0 + t1) * 0.5;
        const drop = lerpF(0.072, 0.026, (t0 + t1) * 0.5) * H * rng.range(0.9, 1.1);
        b.addBox(
            v3(0, -0.010 * H - drop, zc),
            v3(0.009 * H, 0, 0),
            v3(0, drop, 0),
            v3(0, 0, L * (t1 - t0) * 0.5),
            if (i % 2 == 0) GILL_PALE else GILL_DEEP,
        );
    }
    // TWO SHORT ONES either side, so a lobe is a set of plates and not one fin — outer half only, because the
    // crowding on a cap is at the rim and never at the stalk.
    for ([_]f32{ -1.0, 1.0 }) |side| {
        const from = rng.range(0.34, 0.52);
        const to = rng.range(0.78, 0.96);
        const drop = rng.range(0.030, 0.052) * H;
        b.addBox(
            v3(side * rng.range(0.026, 0.042) * H, -0.010 * H - drop, L * (from + to) * 0.5),
            v3(0.008 * H, 0, 0),
            v3(0, drop, 0),
            v3(0, 0, L * (to - from) * 0.5),
            GILL_DEEP,
        );
    }
    return b.toMesh();
}

const CAP = wf.MAX_PER_KIND;

pub const Bed = struct {
    model: Model,
    blooms: [CAP]Bloom = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Bed {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Bed) []Bloom {
        return self.blooms[0..self.n];
    }
    pub fn liveConst(self: *const Bed) []const Bloom {
        return self.blooms[0..self.n];
    }
    pub fn reset(self: *Bed, m: *const wf.Map) void {
        foe.resetGroup(Bloom, &self.blooms, &self.n, m, .slumber_bloom);
    }
    pub fn setShader(self: *Bed, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Bed, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Bed) void {
        for (self.liveConst()) |*b| b.drawFx();
    }

    /// **IT HANDS BACK NO BLOW, EVER** — the gas is a per-frame build on its own channel (`breath`), so it cannot
    /// voice and shake the hero sixty times a second.
    pub fn update(self: *Bed, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) void {
        for (self.live()) |*b| b.update(dt, hero, bounds, blade);
    }

    /// The worst, not the sum: two rings overlapping is gas, not twice the gas (refreshed, never stacked).
    pub fn breath(self: *const Bed, hero: rl.Vector3) f32 {
        var worst: f32 = 0;
        for (self.liveConst()) |*b| worst = mathx.maxF(worst, b.breath(hero));
        return worst;
    }

    pub fn pierce(self: *Bed, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Bed) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Bed) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Bed) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Bed) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

test "it is scenery until you walk up on it, and scenery again when you leave" {
    var b = Bloom.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(b.hidden());
    try std.testing.expectApproxEqAbs(@as(f32, 0), b.open, 1e-4);

    const dt = 1.0 / 60.0;
    const near = v3(0, 0, WAKE_R - 0.5);
    var t: f32 = 0;
    while (t < WAKE_DUR + 0.2) : (t += dt) b.update(dt, near, 400, .{});
    try std.testing.expect(!b.hidden());
    try std.testing.expect(b.open > 0.9);

    const far = v3(0, 0, WAKE_R + 6.0);
    t = 0;
    while (t < 3.0) : (t += dt) b.update(dt, far, 400, .{});
    try std.testing.expect(b.hidden());
}

test "NO BLOW AT ALL — the gas is the whole weapon, and it only runs while the thing is venting" {
    var b = Bloom.spawn(mathx.zero3, 0, 1.0, 0.2);
    const dt = 1.0 / 60.0;
    const at = v3(0, 0, 2.0);

    try std.testing.expectApproxEqAbs(@as(f32, 0), b.breath(at), 1e-6);

    var t: f32 = 0;
    var swellFrames: u32 = 0;
    var pourFrames: u32 = 0;
    var dosed: f32 = 0;
    while (t < WAKE_DUR + SWELL_DUR + POUR_DUR + 0.5) : (t += dt) {
        b.update(dt, at, 400, .{});
        if (b.state == .swell) {
            swellFrames += 1;
            // **NOTHING COMES OUT DURING THE TELL.** If it did, the tell would be the attack.
            try std.testing.expectApproxEqAbs(@as(f32, 0), b.breath(at), 1e-6);
        }
        if (b.state == .pour) pourFrames += 1;
        dosed += b.breath(at) * dt;
    }
    const swellSecs = @as(f32, @floatFromInt(swellFrames)) * dt;
    std.debug.print("\n  bloom: {d:.2} s of tell, then {d:.0} sleep over the pour against a {d:.0} meter\n", .{
        swellSecs, dosed, combat.ailRow(.sleep).max,
    });
    try std.testing.expect(swellSecs >= foe.TELL_MIN);
    try std.testing.expect(pourFrames > 0);
    try std.testing.expect(dosed > combat.ailRow(.sleep).max);
}

test "STEPPING OUT OF THE RING IS THE ANSWER, and it is not a small margin" {
    var b = Bloom.spawn(mathx.zero3, 0, 1.0, 0.4);
    const dt = 1.0 / 60.0;
    const inside = v3(0, 0, POUR_R - 0.6);
    const outside = v3(0, 0, POUR_R + 0.6);
    // Run it until it pours, not for a fixed window: `spawn` staggers the first cooldown off the seed so a bed
    // of them does not vent in unison.
    var t: f32 = 0;
    while (t < 20.0 and b.state != .pour) : (t += dt) b.update(dt, inside, 400, .{});
    try std.testing.expectEqual(State.pour, b.state);
    try std.testing.expect(b.breath(inside) > 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), b.breath(outside), 1e-6);

    // …and half a pour decays away rather than procing (`combat.AILS`' sleep row is the pressure, not a hit).
    var v = combat.Vitals.init(100, 50, 50);
    t = 0;
    while (t < POUR_DUR * 0.5) : (t += dt) {
        b.update(dt, inside, 400, .{});
        v.build(.sleep, b.breath(inside) * dt);
    }
    const half = v.ail(.sleep).meter;
    try std.testing.expect(!v.ailOn(.sleep));
    t = 0;
    while (t < 6.0) : (t += dt) _ = v.tickAils(dt);
    std.debug.print("  half a pour is {d:.0} sleep, and six seconds later {d:.0}\n", .{ half, v.ail(.sleep).meter });
    try std.testing.expect(half > 20);
    try std.testing.expectApproxEqAbs(@as(f32, 0), v.ail(.sleep).meter, 1e-4);
}

test "HITTING IT MID-POUR SHUTS THE GAS OFF — the one reward for going in after it" {
    var b = Bloom.spawn(mathx.zero3, 0, 1.0, 0.1);
    const dt = 1.0 / 60.0;
    const at = v3(0, 0, 1.5);
    b.debugPour();
    var t: f32 = 0;
    while (t < SWELL_DUR + 0.2) : (t += dt) b.update(dt, at, 400, .{});
    try std.testing.expectEqual(State.pour, b.state);
    try std.testing.expect(b.breath(at) > 0);

    b.stagger(true);
    b.update(dt, at, 400, .{});
    try std.testing.expectApproxEqAbs(@as(f32, 0), b.breath(at), 1e-6);
    try std.testing.expect(b.cd > POUR_CD * 0.9);
}

test "the six lobes are SIX, not one plate — no two the same length or droop" {
    for (0..GILL_N) |i| {
        for (GILL_LEN[i + 1 ..]) |other| try std.testing.expect(GILL_LEN[i] != other);
        for (GILL_DROOP[i + 1 ..]) |other| try std.testing.expect(GILL_DROOP[i] != other);
    }
    var b = Bloom.spawn(mathx.zero3, 0, 1.0, 0.5);
    b.open = 1;
    b.pose();
    // Six different tip heights: the only thing separating a bloom from an umbrella at any distance.
    var lo: f32 = 1e9;
    var hi: f32 = -1e9;
    for (0..GILL_N) |i| {
        const tip = rl.math.vector3Transform(v3(0, 0, GILL_LEN[i] * H), b.xf[GILL_0 + i]);
        lo = mathx.minF(lo, tip.y);
        hi = mathx.maxF(hi, tip.y);
    }
    std.debug.print("  gill tips span {d:.3} m of height\n", .{hi - lo});
    try std.testing.expect(hi - lo > 0.05);
}
