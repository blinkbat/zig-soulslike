const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
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
const approach = mathx.approach;
const setLocal = heromod.setHumanoid;

// THE SALT HUSK (owner's creature, owner's brief) — a body the dried lake took all the water out of, walking
// under a crust of salt. **THE DEATH IS THE ATTACK.** It is the weakest thing on the field and the only one
// whose kill is the dangerous part.
//
// **AND IT IS A FUSE, NOT A TRAP.** The crust cracks, it swells, and it holds for its own roll of
// `BURST_FUSE` — and only then does it go. That window is over the tell floor and long enough to RUN out of
// (walking is not enough; the test measures both), so the burst is something you were shown and chose to
// stand in. A trap that kills you for a killing blow you could not have known about is the one thing this
// must not be.
//
// **THEY CHAIN.** A burst that finishes another husk lights its fuse too, so a line of them is a line of
// fuses — the reason to kill them one at a time, from range, or in the right order.

/// **A MAN-SHAPE STANDS OVER THE HERO** (owner: all humanoids bigger than us) — asserted below.
pub const H: f32 = 2.00;
const HIP_HALF = heromod.HIP_HALF * 0.88;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 0.92;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);

const N = heromod.N;
const ROOT = heromod.ROOT;
const SPINE = heromod.SPINE;
const CHEST = heromod.CHEST;
const NECK = heromod.NECK;
const SKULL = heromod.HEAD;
const HIPL = heromod.HIPL;
const KNEEL = heromod.KNEEL;
const ANKL = heromod.ANKL;
const HIPR = heromod.HIPR;
const KNEER = heromod.KNEER;
const ANKR = heromod.ANKR;
const SHL = heromod.SHL;
const ELL = heromod.ELL;
const WRL = heromod.WRL;
const SHR = heromod.SHR;
const ELR = heromod.ELR;
const WRR = heromod.WRR;
const HELD = heromod.HELD;

const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.042 * H, .toe = 0.168 * H, .halfW = 0.054 * H, .drop = 0.034 * H },
    .{ .bone = ANKR, .heel = 0.042 * H, .toe = 0.168 * H, .halfW = 0.054 * H, .drop = 0.034 * H },
};

// The crust is the brightest thing it has and the body under it is the darkest — the contrast IS the creature,
// and it is what makes the swell readable at the moment it matters.
const CRUST = rgba(196, 194, 186, 255);
const CRUST_LT = rgba(224, 223, 216, 255);
const RIME = rgba(238, 240, 236, 255);
const FLESH = rgba(58, 48, 38, 255);
const FLESH_DK = rgba(34, 28, 22, 255);
const SOCKET = rgba(12, 11, 10, 255);
const BRINE = rgba(206, 210, 198, 210);
const BRINE_THIN = rgba(228, 230, 224, 70);

pub const AGGRO_R: f32 = 12.0;
const HOME_R: f32 = 2.2;
const WALK_SPEED: f32 = heromod.WALK_SPEED * 0.50;
const CHASE_SPEED: f32 = heromod.WALK_SPEED * 0.88;
const ACCEL: f32 = 2.4;
const TURN_RATE: f32 = 2.0;

const BODY_R: f32 = 0.40;
const HURT_R: f32 = 0.60;
const CENTER_F: f32 = 0.56;
const TOP_F: f32 = 1.00;

/// **THE WEAKEST BODY ON THE FIELD, ON PURPOSE.** Dying easily is the whole trap: it invites the greedy
/// finishing blow that the burst is priced against.
const HP_MAX: f32 = 70.0;
const POISE_MAX: f32 = 10.0;
const STANCE_MAX: f32 = 20.0;
/// Salt-cured and bone dry: nothing left to rot and nothing left to freeze. Lightning runs straight through it.
const RESISTS = combat.resists(.{ .chaos = 60, .cold = 30, .fire = 15, .lightning = -35 });
pub const SOULS: u32 = 95;

const CLOUT_R: f32 = 1.72;
const CLOUT_FRONT_DOT: f32 = 0.45;
const CLOUT_WIND: f32 = 0.42;
const CLOUT_STRIKE: f32 = 0.18;
const CLOUT_RECOVER: f32 = 0.66;
const CLOUT_CD: f32 = 2.2;
/// Feeble, and it has to be: everything this creature is worth is in the burst. **NO STANCE** — `Hit.heavy`
/// is `stance > 0`, and the weakest blow on the field reading as a heavy one is the beat lying about it.
pub const CLOUT_HIT = combat.Hit{ .dmg = 9, .poise = 8 };

// **THE BURST.** The one blow that matters, and the only one in the game a corpse throws.
pub const SHATTER_R: f32 = 3.20;
/// Seconds between the killing blow and the burst, before the jitter below.
pub const BURST_FUSE: f32 = 0.85;
/// **EVERY HUSK'S FUSE IS ITS OWN LENGTH.** Without this a cluster lit by one burst goes off on ONE FRAME —
/// an instant wipe with a single tell, rather than the run of separate cracks a player can read and walk out
/// of. Rolled at ignition off the body's own stream, so it is a property of the husk and not of the frame.
pub const FUSE_LO: f32 = 0.85;
pub const FUSE_HI: f32 = 1.30;
/// Salt in an open cut. It is `bleed` and not an element, so no ward answers it and only a longer bar does.
pub const SHATTER_BLEED: f32 = 34.0;
pub const SHATTER_HIT = combat.Hit{
    .dmg = 26,
    .poise = 20,
    .stance = 12,
    .dose = combat.Doses.one(.bleed, SHATTER_BLEED),
};

comptime {
    std.debug.assert(H > heromod.H);
    std.debug.assert(CLOUT_WIND >= foe.TELL_MIN);
    // The SHORTEST fuse any husk can roll is what the tell floor has to be measured against.
    std.debug.assert(BURST_FUSE * FUSE_LO >= foe.TELL_MIN * 2.0);
    // The burst has to out-reach its own body by a real margin, or "step out" is not an instruction.
    std.debug.assert(SHATTER_R > BODY_R * 4.0);
}

const DEATH_DUR: f32 = 0.30;
const DISS_DUR: f32 = 0.55;
const SHOVE_DECAY: f32 = 8.0;
const DISSOLVE = foe.Dissolve{ .rate = 52.0, .spread = 0.7, .rise = 0.5, .flake = CRUST };

const A_PROT: f32 = 2.8;
const HUNCH: f32 = 11.0;
const PELVIS_SHARE: f32 = 1.0 / 6.0;

const FUSE_RATE: f32 = 90.0;
const SHARD_PARTS = 46;
const HIT_GRIT_LIGHT = 4;
const HIT_GRIT_HEAVY = 9;
const PARTS = 128;
comptime {
    std.debug.assert(@as(f32, PARTS) >= FUSE_RATE * 0.5 +
        @as(f32, @floatFromInt(SHARD_PARTS + foe.hitParts(HIT_GRIT_HEAVY) + foe.WOUND_PARTS)));
}

/// `bursting` is the fuse: dead for every purpose the game asks about, still standing, and about to go.
const State = enum { idle, walk, clout, bursting, stunlight, stunheavy, dead };

const Choice = enum { rest, hold, close, clout };

/// **A BAND IS ASKED THE WAY THE STROKE BILLS IT** (`foe.hurtReach`, the ogre's `slamReach` law).
/// Measured edge to edge against a centre-to-centre bill, the band ran 0.21 m past the reach at scale 1
/// and 0.87 m at `wf.FOE_SCALE_LO` — and a body stops closing the frame its band takes it, so that
/// sliver was where the clout was always thrown and never billed.
fn classify(sensed: f32, homeGap: f32, scale: f32, cloutReady: bool, rooted: bool) Choice {
    if (sensed > AGGRO_R) return if (homeGap > HOME_R) .hold else .rest;
    if (sensed <= foe.hurtReach(CLOUT_R, scale) and cloutReady) return .clout;
    if (rooted) return .rest;
    return .close;
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        return .{ .bone = buildBones(), .mat = gfx.material(shader, "salt husk") };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, h: *const Husk) void {
        for (0..HELD) |i| rl.drawMesh(self.bone[i], self.mat, h.xf[i]);
    }
};

pub const Husk = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// **THE FIELD A UNIT OWES ITS ORDERS** (`foe.Post`), stamped at spawn off the map's `ai=` and `wp=`.
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    cloutCd: f32 = 0,
    speed: f32 = 0,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    /// One-frame, read by the group after `update`: the crust let go here.
    burstAt: ?rl.Vector3 = null,
    /// This body's own fuse, rolled at ignition. Zero until it is lit.
    fuse: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    heroLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    justDied: bool = false,
    parry: foe.Parry = .{},
    parried: bool = false,
    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    aiRng: mathx.Rng = mathx.Rng.init(2),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = REST,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Husk {
        var h = Husk{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        h.fxRng = foe.fxStream(seed, 39371.0, 0x5A17);
        h.aiRng = foe.fxStream(seed, 22307.0, 17);
        h.cloutCd = seed * 0.7;
        h.pose();
        return h;
    }

    pub fn centerWorld(self: *const Husk) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, 0);
    }
    pub fn lockPoint(self: *const Husk) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], v3(0, 0.03 * H, 0));
    }
    pub fn topWorld(self: *const Husk) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Husk) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Husk) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Husk) bool {
        return !self.gone;
    }
    /// **A LIT FUSE IS ALREADY A CORPSE.** `dying` is what `foe.corporeal` asks, so a husk on its fuse stops
    /// being a collider and stops being a target the moment the killing blow lands — the burst is not a second
    /// health bar, and hitting one again may not put the fuse out.
    pub fn dying(self: *const Husk) bool {
        return self.state == .bursting or self.state == .dead;
    }
    pub fn staggered(self: *const Husk) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.dying();
    }
    pub fn airborne(_: *const Husk) bool {
        return false;
    }
    pub fn flashFrac(self: *const Husk) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn kind(_: *const Husk) wf.FoeKind {
        return .salt_husk;
    }
    pub fn fusing(self: *const Husk) bool {
        return self.state == .bursting;
    }
    /// 0 at the killing blow, 1 the instant it goes.
    pub fn fuseAmt(self: *const Husk) f32 {
        if (self.state != .bursting or self.fuse <= 0) return 0;
        return mathx.clampF(self.t / self.fuse, 0, 1);
    }

    pub fn navWant(self: *const Husk, quarry: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .walk) return null;
        if (foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R) <= AGGRO_R) return quarry;
        if (foe.postAim(self)) |go| return go;
        return if (mathx.distXZ(self.pos, foe.homeFor(self)) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Husk, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    fn cloutAmt(self: *const Husk) f32 {
        if (self.state != .clout) return 0;
        if (self.t < CLOUT_WIND) return -mathx.smoothstep(0, CLOUT_WIND * 0.9, self.t);
        const s = self.t - CLOUT_WIND;
        if (s < CLOUT_STRIKE) return lerpF(-1.0, 1.0, foe.swingCurve(s / CLOUT_STRIKE));
        return 1.0 - mathx.smoothstep(CLOUT_STRIKE, CLOUT_STRIKE + CLOUT_RECOVER * 0.7, s);
    }

    fn stunAmount(self: *const Husk) f32 {
        if (self.state != .stunlight and self.state != .stunheavy) return 0;
        return foe.stunCurve(self.t, self.state == .stunheavy);
    }

    pub fn update(self: *Husk, dt: f32, quarry: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.burstAt = null;
        self.justDied = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterBurst();
        if (grip.downed) self.stagger(true);
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.cloutCd = mathx.maxF(0, self.cloutCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), quarry, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        var movedDist: f32 = 0;
        var moveSpeed: f32 = 0;
        var moveYaw: ?f32 = null;

        switch (self.state) {
            .bursting => {
                self.speed = 0;
                self.emitFuse(dt);
                if (self.t >= self.fuse) self.blow();
            },
            .dead => {
                self.speed = 0;
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .stunlight, .stunheavy => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .clout => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t < CLOUT_WIND) self.faceToward(quarry, dt);
                const s = self.t - CLOUT_WIND;
                if (s >= 0 and s < CLOUT_STRIKE) self.tryClout(quarry);
                if (self.t >= CLOUT_WIND + CLOUT_STRIKE + CLOUT_RECOVER) {
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .idle, .walk => {
                const sensed = foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R);
                const homeGap = mathx.distXZ(self.pos, foe.homeFor(self));
                switch (classify(sensed, homeGap, self.scale, self.cloutCd <= 0, self.root.held())) {
                    .rest => {
                        if (sensed <= AGGRO_R) self.faceToward(quarry, dt);
                        // **ORDERS ARE WHAT IT DOES BEFORE IT HAS SEEN ANYBODY** (`foe.postAmble`), refused inside the ring.
                        self.state = if (foe.postAmble(self, dt, bounds, WALK_SPEED, ACCEL, sensed, AGGRO_R, TURN_RATE, &movedDist, &moveSpeed, &moveYaw)) .walk else .idle;
                    },
                    .clout => {
                        self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                        self.cloutCd = CLOUT_CD * self.aiRng.range(0.85, 1.25);
                        self.heroLatch = false;
                        self.enter(.clout);
                    },
                    .hold, .close => |ch| {
                        const to = if (ch == .hold) self.home else quarry;
                        const want = if (ch == .hold) WALK_SPEED else CHASE_SPEED;
                        self.faceToward(self.nav.aim(self.pos, to), dt);
                        self.speed = approach(self.speed, want, ACCEL * dt);
                        foe.stride(self, dt, bounds, &movedDist, &moveSpeed, &moveYaw);
                        self.state = .walk;
                    },
                }
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.pose();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn tryClout(self: *Husk, quarry: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, quarry, foe.hurtReach(CLOUT_R, self.scale), CLOUT_FRONT_DOT)) return;
        self.heroHit = CLOUT_HIT;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    pub fn tryHit(self: *Husk, blade: foe.Blade) void {
        // **A LIT FUSE CANNOT BE PUT OUT** — nor hit again for a second set of souls.
        if (self.dying()) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 1.0, .heavy = 1.7 });
        self.grit(s.contact, s.dir, foe.hitParts(if (heavy) HIT_GRIT_HEAVY else HIT_GRIT_LIGHT));
        switch (s.reaction) {
            .death => self.enterBurst(),
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    /// **THE ONE DOOR A HUSK DIES THROUGH**, whatever killed it — a blade, a meter, or another husk's burst.
    /// `justDied` fires HERE, at the killing blow, not at the burst: souls and the drop are the kill's, and a
    /// player who walks away during the fuse is still owed them.
    pub fn enterBurst(self: *Husk) void {
        if (self.dying()) return;
        self.heroLatch = false;
        self.vit.dead = true;
        self.fuse = BURST_FUSE * self.aiRng.range(FUSE_LO, FUSE_HI);
        self.enter(.bursting);
        self.justDied = true;
        sfx.world(.bone_hurt, self.pos);
    }

    fn blow(self: *Husk) void {
        self.burstAt = self.centerWorld();
        self.shards();
        sfx.world(.shroom_puff, self.pos);
        self.enter(.dead);
    }

    fn enter(self: *Husk, s: State) void {
        self.state = s;
        self.t = 0;
    }
    fn enterStun(self: *Husk, s: State) void {
        self.heroLatch = false;
        self.enter(s);
    }
    pub fn stagger(self: *Husk, heavy: bool) void {
        if (self.dying()) return;
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugBurst(self: *Husk) void {
        self.enterBurst();
    }
    pub fn debugKill(self: *Husk) void {
        self.enterBurst();
    }

    const GRIT_SPRAY = foe.Spray{
        .fanLo = 0.20,
        .fanHi = 0.90,
        .upLo = 0.3,
        .upHi = 1.4,
        .lifeLo = 0.30,
        .lifeHi = 0.62,
        .rLo = 0.012,
        .rHi = 0.028,
        .r1 = 0.008,
        .col = CRUST,
        .col1 = BRINE_THIN,
        .grav = foe.DUST_GRAV,
        .bounce = 0.3,
    };
    fn grit(self: *Husk, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, 2.2, self.scale, GRIT_SPRAY);
    }

    /// **THE SHARDS GO OUT FLAT AND THEY GO OUT FAR** — the mote reach is the blow's reach, because the ring
    /// of salt IS how a player learns where `SHATTER_R` ends.
    fn shards(self: *Husk) void {
        const c = self.centerWorld();
        var i: i32 = 0;
        while (i < SHARD_PARTS) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.55, 1.0) * SHATTER_R * self.scale * 1.6;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = c,
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.4, 2.2), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.45, 0.85),
                .r0 = self.fxRng.range(0.018, 0.040),
                .r1 = 0.008,
                .col = RIME,
                .col1 = BRINE_THIN,
                .grav = foe.DUST_GRAV * 1.4,
                .stretch = 0.03,
            });
        }
    }

    /// The crust venting through its own cracks. It accelerates over the fuse, so the last third of the window
    /// looks like the last third of the window.
    fn emitFuse(self: *Husk, dt: f32) void {
        const u = self.fuseAmt();
        var owed = foe.emitDue(&self.fxAccum, dt, FUSE_RATE * (0.25 + 0.75 * u * u));
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.05, 0.22) * H * self.scale;
            const y = self.fxRng.float() * TOP_F * H * self.scale;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + y, self.pos.z + mathx.sinf(a) * rr),
                .v = v3(mathx.cosf(a) * (0.4 + 1.6 * u), self.fxRng.range(0.3, 1.1), mathx.sinf(a) * (0.4 + 1.6 * u)),
                .life = self.fxRng.range(0.20, 0.46),
                .r0 = self.fxRng.range(0.020, 0.042),
                .r1 = 0.010,
                .col = BRINE,
                .col1 = BRINE_THIN,
                .grav = 0.6,
                .drag = 3.0,
            });
        }
    }

    pub fn drawFx(self: *const Husk) void {
        foe.drawParticles(&self.parts);
    }
    pub fn draw(self: *const Husk, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Husk) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(foe.SINK_HUMANOID, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.4, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();
        const m = self.moving * (1.0 - dk);
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);
        const clout = self.cloutAmt();
        // **THE SWELL IS THE TELL.** It rears back, opens out and inflates over the fuse — a silhouette
        // change, not a colour change, so it reads at range and in any light.
        const fuse = self.fuseAmt();
        const swell = 1.0 + 0.26 * fuse * fuse;

        var wx: [N]rl.Matrix = undefined;
        const pelvY = if (dead) lerpF(hipY, 0.30 * H, dk) else hipY + pel.bob - pel.dip + 0.10 * H * fuse;
        wx[ROOT] = mul(scaleM(fs * swell, fs * swell, fs * swell), mul3(
            mul3(rz(8.0 * dk), rx(PELVIS_SHARE * (HUNCH + 12.0 * mathx.maxF(0, clout) - 20.0 * stun - 26.0 * fuse + 40.0 * dk)), ry(pel.prot)),
            mul(tr(pel.sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));
        if (!dead) {
            heromod.legChain(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.pos.y, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        } else {
            heromod.deadLegs(&wx, self.rest, dk);
        }
        const waist = (1.0 - PELVIS_SHARE) * (HUNCH + 12.0 * mathx.maxF(0, clout) - 20.0 * stun - 26.0 * fuse + 40.0 * dk);
        self.poseUpper(&wx, waist, clout, stun, dk, fuse, pel.prot);
        self.xf = wx;
    }

    fn poseUpper(self: *Husk, wx: *[N]rl.Matrix, waist: f32, clout: f32, stun: f32, dk: f32, fuse: f32, prot: f32) void {
        const rest = self.rest;
        const m = self.moving * (1.0 - dk);
        const wonk = (self.seed - 0.5) * 5.0;
        // **NOT QUITE DEAD.** No breath in a salt-cured body — what it has is a SETTLING LIST, a couple of
        // degrees on `gutter`'s three incommensurate rates, the trunk arriving before the skull. Bolt still,
        // it read as a prop; a corpse that stands is a corpse that balances.
        const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk);
        const settle = mathx.gutter(self.elapsed * 0.30 + self.seed * 8.1, self.seed * 3.7) * idleAmt;
        const settleLag = mathx.gutter(self.elapsed * 0.30 - 0.7 + self.seed * 8.1, self.seed * 3.7) * idleAmt;

        setLocal(wx, SPINE, rest, mul3(rx(waist * 0.44), ry(-0.3 * prot), rz(wonk * 0.5 + 1.7 * settle)));
        setLocal(wx, CHEST, rest, mul3(rx(waist * 0.56 + 0.6 * settleLag), ry(-0.45 * prot), rz(-wonk * 0.3 - 1.2 * settleLag)));
        setLocal(wx, NECK, rest, rx(-8.0 * clout + 6.0 * dk - 4.0 * stun - 18.0 * fuse));
        setLocal(wx, SKULL, rest, mul3(rx(-14.0 * clout + 12.0 * dk - 20.0 * stun - 26.0 * fuse + 0.9 * settle), ry(-0.4 * prot), rz(wonk + 1.5 * settleLag)));

        // Arms out and away as it swells: the body opening is what "about to come apart" looks like.
        const armStun = -40.0 * stun;
        const swing = -10.0 * heromod.armSwing(self.phase) * m * @abs(self.fwdB);
        const haul = -70.0 * mathx.maxF(0, -clout);
        const drive = 48.0 * mathx.maxF(0, clout);
        inline for (.{ SHL, SHR }, .{ ELL, ELR }, .{ WRL, WRR }, .{ 1.0, -1.0 }) |sh, el, wr, side| {
            const s = if (side > 0) swing else -swing;
            setLocal(wx, sh, rest, mul3(
                rx(-(5.0 + s) + haul - drive + armStun - 26.0 * fuse - 18.0 * dk),
                ry(0),
                rz(side * (10.0 + 3.0 * @abs(wonk) + 44.0 * fuse)),
            ));
            setLocal(wx, el, rest, rx(-(28.0 + 18.0 * @abs(clout)) * (1.0 - 0.7 * fuse)));
            setLocal(wx, wr, rest, rz(side * 5.0));
        }
    }
};

const CAP_N = wf.MAX_PER_KIND;

pub const Pan = struct {
    model: Model,
    husks: [CAP_N]Husk = undefined,
    n: usize = 0,
    /// One-frame count for the beat: how many crusts let go this frame.
    burstsThisFrame: u32 = 0,

    pub fn init(shader: rl.Shader) Pan {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Pan) []Husk {
        return self.husks[0..self.n];
    }
    pub fn liveConst(self: *const Pan) []const Husk {
        return self.husks[0..self.n];
    }
    pub fn reset(self: *Pan, m: *const wf.Map) void {
        self.burstsThisFrame = 0;
        foe.resetGroup(Husk, &self.husks, &self.n, m, .salt_husk);
    }
    pub fn clear(self: *Pan) void {
        self.n = 0;
        self.burstsThisFrame = 0;
    }
    pub fn setShader(self: *Pan, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Pan, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }

    pub fn update(self: *Pan, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        self.burstsThisFrame = 0;
        var worst: ?foe.Blow = null;
        var i: usize = 0;
        while (i < self.n) : (i += 1) {
            const h = &self.husks[i];
            if (h.update(dt, h.threat.aim(hero), bounds, blade)) |hit| foe.worseBlow(&worst, hit, h.pos, &h.threat);
            if (h.burstAt) |at| {
                self.burstsThisFrame += 1;
                const r = foe.hurtReach(SHATTER_R, h.scale);
                if (mathx.distXZ(at, hero) <= r) foe.worseBlow(&worst, SHATTER_HIT, at, &h.threat);
                self.splash(i, at, r);
            }
        }
        return worst;
    }

    /// **THEY CHAIN.** A burst that finishes a neighbour lights its fuse, and its fuse is its own — so a line
    /// of husks goes off as a run of separate cracks rather than all at once, which is what makes running
    /// through them a readable mistake instead of an instant one.
    fn splash(self: *Pan, from: usize, at: rl.Vector3, r: f32) void {
        var j: usize = 0;
        while (j < self.n) : (j += 1) {
            if (j == from) continue;
            const o = &self.husks[j];
            if (!o.alive() or o.dying()) continue;
            if (mathx.distXZ(at, o.centerWorld()) > r + o.hurtRadius()) continue;
            if (o.vit.hit(SHATTER_HIT) == .death) o.enterBurst();
        }
    }

    pub fn fusingCount(self: *const Pan) u32 {
        var n: u32 = 0;
        for (self.liveConst()) |*h| {
            if (h.fusing()) n += 1;
        }
        return n;
    }

    pub fn draw(self: *const Pan, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Pan) void {
        for (self.liveConst()) |*h| h.drawFx();
    }
    pub fn pierce(self: *Pan, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Pan) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn anyParried(self: *const Pan) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn soulsDropped(self: *const Pan) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Pan) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Pan) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn buildBones() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = chestMesh();
    mesh[NECK] = neckMesh();
    mesh[SKULL] = skullMesh();
    mesh[HIPL] = thighMesh(1.0);
    mesh[KNEEL] = shinMesh(1.0);
    mesh[ANKL] = footMesh(1.0);
    mesh[HIPR] = thighMesh(-1.0);
    mesh[KNEER] = shinMesh(-1.0);
    mesh[ANKR] = footMesh(-1.0);
    mesh[SHL] = upperArmMesh(1.0);
    mesh[ELL] = forearmMesh(1.0);
    mesh[WRL] = handMesh(1.0);
    mesh[SHR] = upperArmMesh(-1.0);
    mesh[ELR] = forearmMesh(-1.0);
    mesh[WRR] = handMesh(-1.0);
    return mesh;
}

/// The crust is grown ON, in lumps, never painted: a salt flat crystallises in plates and the silhouette has
/// to be lumpy or the creature is a pale man.
fn crustOn(b: *Builder, rng: *mathx.Rng, c: rl.Vector3, r: rl.Vector3, n: u32) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const a = rng.angle();
        const up = rng.range(-1.0, 1.0);
        const sz = rng.range(0.16, 0.40);
        b.addBlob(
            v3(c.x + mathx.cosf(a) * r.x * 0.86, c.y + up * r.y * 0.8, c.z + mathx.sinf(a) * r.z * 0.86),
            v3(r.x * sz, r.y * sz * 0.7, r.z * sz),
            5,
            5,
            if (rng.float() < 0.35) RIME else CRUST,
        );
    }
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A00);
    b.setMat(.skin);
    b.addBlob(v3(0, 0, 0), v3(0.082 * H, 0.066 * H, 0.072 * H), 9, 6, FLESH);
    crustOn(&b, &rng, v3(0, 0, 0), v3(0.082 * H, 0.066 * H, 0.072 * H), 5);
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A01);
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.074 * H, 0), 0.058 * H, 0.070 * H, 9, FLESH_DK);
    crustOn(&b, &rng, v3(0, 0.036 * H, 0), v3(0.064 * H, 0.038 * H, 0.058 * H), 5);
    return b.toMesh();
}

fn chestMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A02);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.038 * H, 0), v3(0.098 * H, 0.080 * H, 0.080 * H), 10, 7, FLESH);
    b.addBlob(v3(0, -0.004 * H, 0.008 * H), v3(0.086 * H, 0.050 * H, 0.072 * H), 9, 6, FLESH_DK);
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const y = 0.004 * H + @as(f32, @floatFromInt(i)) * 0.020 * H;
        b.addCapsule(v3(-0.048 * H, y, 0.056 * H), v3(0.048 * H, y, 0.054 * H), 0.008 * H, 0.008 * H, 5, CRUST_LT);
    }
    crustOn(&b, &rng, v3(0, 0.038 * H, 0), v3(0.098 * H, 0.080 * H, 0.080 * H), 9);
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.044 * H, -0.004 * H), 0.022 * H, 0.024 * H, 7, FLESH_DK);
    return b.toMesh();
}

fn skullMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A03);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.018 * H, 0.002 * H), v3(0.044 * H, 0.050 * H, 0.050 * H), 9, 7, FLESH);
    b.addBlob(v3(0, -0.012 * H, 0.024 * H), v3(0.030 * H, 0.024 * H, 0.030 * H), 7, 5, FLESH_DK);
    b.setMat(.plain);
    b.addBlob(v3(0.018 * H, 0.022 * H, 0.040 * H), v3(0.012 * H, 0.012 * H, 0.008 * H), 5, 5, SOCKET);
    b.addBlob(v3(-0.018 * H, 0.022 * H, 0.040 * H), v3(0.012 * H, 0.012 * H, 0.008 * H), 5, 5, SOCKET);
    b.setMat(.skin);
    crustOn(&b, &rng, v3(0, 0.024 * H, -0.010 * H), v3(0.044 * H, 0.050 * H, 0.046 * H), 6);
    return b.toMesh();
}

fn thighMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0x5A04 else 0x5A05);
    b.setMat(.skin);
    const len = heromod.SEG_THIGH * H;
    b.addCapsule(v3(0, 0, 0), v3(side * 0.008 * H, -len, 0), 0.038 * H, 0.028 * H, 8, FLESH);
    b.addBlob(v3(0, 0.004 * H, 0), v3(0.042 * H, 0.040 * H, 0.042 * H), 7, 5, FLESH);
    crustOn(&b, &rng, v3(0, -len * 0.5, 0), v3(0.038 * H, 0.104 * H, 0.034 * H), 4);
    return b.toMesh();
}

fn shinMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0x5A06 else 0x5A07);
    b.setMat(.skin);
    const len = heromod.SEG_SHANK * H;
    b.addCapsule(v3(0, 0, 0), v3(side * 0.004 * H, -len, 0.004 * H), 0.028 * H, 0.018 * H, 8, FLESH_DK);
    b.addBlob(v3(0, 0.002 * H, 0), v3(0.032 * H, 0.030 * H, 0.032 * H), 6, 5, FLESH);
    crustOn(&b, &rng, v3(0, -len * 0.45, 0), v3(0.028 * H, 0.100 * H, 0.026 * H), 3);
    return b.toMesh();
}

fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0.004 * H, -0.026 * H), v3(side * 0.006 * H, -0.004 * H, 0.084 * H), 0.026 * H, 0.019 * H, 7, CRUST);
    return b.toMesh();
}

fn upperArmMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0x5A08 else 0x5A09);
    b.setMat(.skin);
    const len = heromod.SEG_UPARM * H;
    b.addCapsule(v3(0, 0, 0), v3(side * 0.010 * H, -len, 0), 0.028 * H, 0.020 * H, 7, FLESH);
    b.addBlob(v3(0, 0.004 * H, 0), v3(0.032 * H, 0.030 * H, 0.032 * H), 6, 5, FLESH);
    crustOn(&b, &rng, v3(0, -len * 0.5, 0), v3(0.028 * H, 0.082 * H, 0.026 * H), 3);
    return b.toMesh();
}

fn forearmMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    const len = heromod.SEG_FOREARM * H;
    b.addCapsule(v3(0, 0, 0), v3(side * 0.008 * H, -len, 0), 0.021 * H, 0.014 * H, 7, FLESH_DK);
    b.addBlob(v3(0, 0.002 * H, 0), v3(0.024 * H, 0.023 * H, 0.024 * H), 6, 5, FLESH);
    return b.toMesh();
}

fn handMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, -0.014 * H, 0.004 * H), v3(0.018 * H, 0.020 * H, 0.016 * H), 6, 5, CRUST);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const f = @as(f32, @floatFromInt(i)) - 1.0;
        b.addCapsule(
            v3(side * f * 0.010 * H, -0.024 * H, 0.006 * H),
            v3(side * f * 0.015 * H, -0.050 * H, 0.016 * H),
            0.006 * H,
            0.003 * H,
            5,
            CRUST_LT,
        );
    }
    return b.toMesh();
}


test "THE DEATH IS THE ATTACK — and it is a FUSE, so it can be walked out of" {
    var p = Pan{ .model = undefined };
    p.husks[0] = Husk.spawn(mathx.zero3, 0, 1.0, 0.3);
    p.n = 1;
    // He stands well inside the burst and never moves: he takes it.
    const inside = v3(0, 0, SHATTER_R * 0.5);
    p.husks[0].debugBurst();
    try std.testing.expect(p.husks[0].fusing());
    var took: ?foe.Blow = null;
    var t: f32 = 0;
    while (t < BURST_FUSE * FUSE_HI + 0.2) : (t += 1.0 / 60.0) {
        if (p.update(1.0 / 60.0, inside, 400, .{})) |b| took = b;
    }
    try std.testing.expect(took != null);
    try std.testing.expectApproxEqAbs(SHATTER_HIT.dmg, took.?.hit.dmg, 1e-4);
    std.debug.print("\n  salt husk: {d:.2} s of fuse, {d:.1} m of burst, {d:.0} dmg + {d:.0} bleed\n", .{ BURST_FUSE, SHATTER_R, SHATTER_HIT.dmg, SHATTER_BLEED });

    // **THE ESCAPE IS A RUN, NOT A STROLL — AND THAT GAP IS THE PRICE.** Measured off the reach the burst
    // actually bills at (`foe.hurtReach`: its own radius plus his). From where the killing blow was thrown,
    // walking does not clear it inside the fuse and running does; both are asserted, because the design is
    // the distance between those two answers and not either one of them.
    const reach = foe.hurtReach(SHATTER_R, 1.0);
    const from: f32 = 1.5; // melee range — where the blow that killed it came from
    const owed = reach - from;
    // **BOTH ENDS OF THE JITTER**, and each leg's fuse is FORCED rather than rolled: a pin that holds only
    // for the length this seed happened to draw is not a pin. A run clears the shortest fuse; a walk fails to
    // clear even the longest.
    const worst = BURST_FUSE * FUSE_LO;
    const best = BURST_FUSE * FUSE_HI;
    std.debug.print("  burst bills at {d:.2} m; from {d:.1} m that is {d:.2} m — {d:.2} m/s on the short fuse, {d:.2} on the long\n", .{ reach, from, owed, owed / worst, owed / best });
    try std.testing.expect(owed / worst < heromod.RUN_SPEED);
    try std.testing.expect(owed / best > heromod.WALK_SPEED);

    for ([_]struct { name: []const u8, speed: f32, fuse: f32, clears: bool }{
        .{ .name = "walk, long fuse ", .speed = heromod.WALK_SPEED, .fuse = best, .clears = false },
        .{ .name = "run,  short fuse", .speed = heromod.RUN_SPEED, .fuse = worst, .clears = true },
    }) |leg| {
        var q = Pan{ .model = undefined };
        q.husks[0] = Husk.spawn(mathx.zero3, 0, 1.0, 0.3);
        q.n = 1;
        q.husks[0].debugBurst();
        q.husks[0].fuse = leg.fuse;
        var hit: ?foe.Blow = null;
        var at = v3(0, 0, from);
        t = 0;
        while (t < best + 0.2) : (t += 1.0 / 60.0) {
            at.z += leg.speed * (1.0 / 60.0);
            if (q.update(1.0 / 60.0, at, 400, .{})) |b| hit = b;
        }
        std.debug.print("  {s} out from {d:.1} m reaches {d:.2} m: {s}\n", .{ leg.name, from, at.z, if (hit == null) "CLEAR" else "caught" });
        try std.testing.expectEqual(leg.clears, hit == null);
    }
}

test "A LIT FUSE CANNOT BE PUT OUT, AND IT IS NOT A SECOND HEALTH BAR" {
    var h = Husk.spawn(mathx.zero3, 0, 1.0, 0.3);
    h.debugBurst();
    try std.testing.expect(h.dying());
    try std.testing.expect(!foe.corporeal(&h));
    const hitsBefore = h.hits;
    const blade = foe.Blade{
        .active = true,
        .r = 0.4,
        .a = h.centerWorld(),
        .b = h.centerWorld(),
        .a0 = h.centerWorld(),
        .b0 = h.centerWorld(),
        .hit = .{ .dmg = 60 },
    };
    h.tryHit(blade);
    try std.testing.expectEqual(hitsBefore, h.hits);
    try std.testing.expect(h.fusing());
    h.stagger(true);
    try std.testing.expect(h.fusing());
}

test "THE KILL IS BILLED AT THE KILLING BLOW, NOT AT THE BURST" {
    var h = Husk.spawn(mathx.zero3, 0, 1.0, 0.3);
    h.debugBurst();
    try std.testing.expect(h.justDied);
    // …and it is a ONE-FRAME edge, so the fuse does not bill it again every frame it stands there.
    var fired: u32 = 0;
    var t: f32 = 0;
    while (t < BURST_FUSE * FUSE_HI + 0.4) : (t += 1.0 / 60.0) {
        _ = h.update(1.0 / 60.0, v3(0, 0, 40), 400, .{});
        if (h.justDied) fired += 1;
    }
    try std.testing.expectEqual(@as(u32, 0), fired);
}

test "A BURST DOES NOT HARVEST THE CLUSTER — a whole neighbour survives it, and that is the exploit gate" {
    var p = Pan{ .model = undefined };
    p.husks[0] = Husk.spawn(mathx.zero3, 0, 1.0, 0.3);
    p.husks[1] = Husk.spawn(v3(0, 0, SHATTER_R * 0.6), 0, 1.0, 0.5);
    p.n = 2;
    p.husks[0].debugBurst();
    const away = v3(400, 0, 400);
    var t: f32 = 0;
    while (t < BURST_FUSE * FUSE_HI * 2.0) : (t += 1.0 / 60.0) _ = p.update(1.0 / 60.0, away, 400, .{});
    // It was hurt, badly, and it is still standing: one kill may not pay out a line of them.
    try std.testing.expect(!p.husks[1].dying());
    try std.testing.expect(p.husks[1].vit.hp < HP_MAX);
    std.debug.print("  a burst leaves a whole neighbour on {d:.0}/{d:.0} hp — hurt, not harvested\n", .{ p.husks[1].vit.hp, HP_MAX });
    try std.testing.expect(SHATTER_HIT.dmg < HP_MAX);
}

test "…BUT THEY DO CHAIN OFF A HURT ONE, and each keeps its OWN fuse so a line goes as a run" {
    var p = Pan{ .model = undefined };
    p.husks[0] = Husk.spawn(mathx.zero3, 0, 1.0, 0.3);
    p.husks[1] = Husk.spawn(v3(0, 0, SHATTER_R * 0.6), 0, 1.0, 0.5);
    p.husks[2] = Husk.spawn(v3(0, 0, SHATTER_R * 1.2), 0, 1.0, 0.7);
    // Far out of every reach: it must survive the whole run whatever the others do.
    p.husks[3] = Husk.spawn(v3(0, 0, SHATTER_R * 9.0), 0, 1.0, 0.9);
    p.n = 4;
    // Softened the way a fight softens them — which is what makes a cluster a chain rather than a queue.
    p.husks[1].vit.hp = SHATTER_HIT.dmg * 0.8;
    p.husks[2].vit.hp = SHATTER_HIT.dmg * 0.8;
    p.husks[3].vit.hp = SHATTER_HIT.dmg * 0.8;
    p.husks[0].debugBurst();

    const away = v3(400, 0, 400);
    var everSimultaneous: u32 = 0;
    var t: f32 = 0;
    while (t < BURST_FUSE * 5.0) : (t += 1.0 / 60.0) {
        _ = p.update(1.0 / 60.0, away, 400, .{});
        if (p.burstsThisFrame > 1) everSimultaneous += 1;
    }
    try std.testing.expect(p.husks[1].state == .dead);
    try std.testing.expect(p.husks[2].state == .dead);
    try std.testing.expect(!p.husks[3].dying());
    // **NEVER TWO ON ONE FRAME** — the run is what makes it readable instead of a single instant wipe.
    try std.testing.expectEqual(@as(u32, 0), everSimultaneous);
    std.debug.print("  chain: husks {d:.1} m apart go in a run, never on one frame; one at {d:.1} m stays cold\n", .{ SHATTER_R * 0.6, SHATTER_R * 9.0 });
}

test "IT DIES EASILY AND IT HITS FEEBLY — everything it is worth is in the burst" {
    try std.testing.expect(HP_MAX < 100.0);
    try std.testing.expect(SHATTER_HIT.dmg > CLOUT_HIT.dmg * 2.5);
    std.debug.print("  clout {d:.0} dmg against a burst of {d:.0}\n", .{ CLOUT_HIT.dmg, SHATTER_HIT.dmg });
    // The bleed is the real bill and no ward answers it — the row carries no element.
    try std.testing.expect(combat.ailRow(.bleed).elem == null);
    try std.testing.expect(SHATTER_HIT.dose.at(.bleed) > 0);
}

test "the pick is positional and the clout lands once per swing" {
    try std.testing.expectEqual(Choice.clout, classify(1.6, 0, 1.0, true, false));
    try std.testing.expectEqual(Choice.close, classify(3.0, 0, 1.0, true, false));
    try std.testing.expectEqual(Choice.rest, classify(AGGRO_R + 1.0, 0, 1.0, true, false));
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, HOME_R + 1.0, 1.0, true, false));

    var h = Husk.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 1.1);
    h.facing = mathx.headingXZ(mathx.dirXZ(h.pos, hero));
    h.enter(.clout);
    var landed: u32 = 0;
    var t: f32 = 0;
    while (t < CLOUT_WIND + CLOUT_STRIKE + CLOUT_RECOVER + 0.1) : (t += 1.0 / 60.0) {
        if (h.update(1.0 / 60.0, hero, 400, .{}) != null) landed += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), landed);
}

// **THE BAND IT STOPS CLOSING AT HAS TO BE A BAND IT CAN BILL FROM** (AGENTS.md: a move is judged by THROWING
// it, not by looking at it). The outer edge is asked of `classify` rather than re-derived here — which unit the
// band is written in is the thing under test.
test "THE BLOW LANDS ON THE MAN WHERE HE STANDS — thrown for real, anywhere its own band picks it" {
    const dt: f32 = 1.0 / 120.0;
    var misses: usize = 0;
    var thrown: usize = 0;
    var widest: f32 = 0;
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, wf.FOE_SCALE_HI }) |scale| {
        const probe = Husk.spawn(mathx.ground(0, 0), 0, scale, 0.31);
        const apart = foe.closestApproach(probe.bodyR());
        var lo: f32 = apart;
        var hi: f32 = AGGRO_R;
        for (0..48) |_| {
            const mid = (lo + hi) * 0.5;
            if (classify(mid, 0, scale, true, false) == Choice.clout) lo = mid else hi = mid;
        }
        const far = lo;
        widest = @max(widest, far - foe.hurtReach(CLOUT_R, scale));
        for ([_]f32{ 0, 30, 55 }) |deg| {
            for ([_]f32{ 0.0, 0.34, 0.67, 0.92, 1.0 }) |u| {
                const stand = lerpF(apart + 0.05, far - 0.002, u);
                if (classify(stand, 0, scale, true, false) != Choice.clout) continue;
                thrown += 1;
                const a = mathx.radians(deg);
                var c = Husk.spawn(mathx.ground(0, 0), 0, scale, 0.31);
                const hero = v3(@sin(a) * stand, 0, @cos(a) * stand);
                c.enter(.clout);
                var hit = false;
                var guard: usize = 0;
                while (guard < 2000) : (guard += 1) {
                    if (c.update(dt, hero, 400.0, .{}) != null) {
                        hit = true;
                        break;
                    }
                    if (c.state != .clout) break;
                }
                if (!hit) {
                    misses += 1;
                    std.debug.print("\n  x{d:.2} at {d:.2} m, {d:.0} deg off: MISSED — the band runs to {d:.2} m, the stroke bills to {d:.2}\n", .{ scale, stand, deg, far, foe.hurtReach(CLOUT_R, scale) });
                }
            }
        }
    }
    std.debug.print("\n  salthusk: {d} stands thrown across three scales, {d} billed nothing; band overruns its reach by at most {d:.2} m\n", .{ thrown, misses, widest });
    try std.testing.expectEqual(@as(usize, 0), misses);
    try std.testing.expect(widest <= 0.001);
}
