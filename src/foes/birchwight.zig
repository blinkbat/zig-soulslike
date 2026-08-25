const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
const elemfx = @import("../gfx/elemfx.zig");

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

// THE BIRCHWIGHT (owner's creature, owner's brief) — a dead birch standing up and walking, and **THE FIRE IS
// THE WHOLE FIGHT, BOTH WAYS**. Nothing else in the game has a counter that is also an escalation.
//
// **BIRCH BARK IS 10-25% BETULIN**, an oily terpene, which is why it takes a flame wet or green and why it is
// the firestarter every woodsman carries. That is the creature: unlit it is a slow, heavy, high-poise thing
// you grind down; CAUGHT it is half again as fast and every blow it lands sets you alight too.
//
// **AND CATCHING IT KILLS IT.** `LIT_DPS` burns it down on its own clock, so putting a torch to one is a
// decision to end the fight in fifteen seconds instead of forty — on much worse terms. The player is allowed
// to want either.
//
// **A CAUGHT ONE LIGHTS THE NEXT ONE** (`SPREAD_R`). In a stand of them the torch is a mistake; alone it is a
// tool. Same creature, opposite answer, and the map is what decides which.

pub const H: f32 = 2.15;
const HIP_HALF = heromod.HIP_HALF * 0.78;
const SHOULDER_HALF = heromod.SHOULDER_HALF * 0.86;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);

const N = heromod.N;
const ROOT = heromod.ROOT;
const SPINE = heromod.SPINE;
const CHEST = heromod.CHEST;
const NECK = heromod.NECK;
const CROWN = heromod.HEAD;
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
/// The boughs ARE the arms. Bone 17 is never posed and never drawn — `Model.draw` walks `0..HELD`.
const HELD = heromod.HELD;

const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.030 * H, .toe = 0.120 * H, .halfW = 0.052 * H, .drop = 0.026 * H },
    .{ .bone = ANKR, .heel = 0.030 * H, .toe = 0.120 * H, .halfW = 0.052 * H, .drop = 0.026 * H },
};

// **BIRCH IS THE ONE PALE TREE, AND PALE IS THE WHOLE POINT** — every other body on this field is authored
// dark. **SOLVED OFF THE CHAIN, NOT PICKED**: `gfx`'s own ladder is albedo 76 -> screen 188 and 109 -> 222,
// and anything over 148 clips white. Authored at 168 the trunk clipped and the creature read as a bare
// mannequin with no bark on it at all; at 92 it samples ~205 — the palest body on the field and still a
// surface, with the lenticels able to sit dark against it.
const BARK = rgba(92, 89, 82, 255);
const BARK_LT = rgba(116, 113, 106, 255);
const LENTICEL = rgba(38, 36, 32, 255);
const HEARTWOOD = rgba(58, 46, 34, 255);
const ROT = rgba(42, 40, 30, 255);
const KNOTHOLE = rgba(14, 13, 11, 255);
const EMBER_EYE = rgba(232, 128, 40, 255);

pub const AGGRO_R: f32 = 13.0;
const HOME_R: f32 = 2.6;
const WALK_SPEED: f32 = heromod.WALK_SPEED * 0.44;
const CHASE_SPEED: f32 = heromod.WALK_SPEED * 0.72;
const ACCEL: f32 = 2.0;
const TURN_RATE: f32 = 1.5;

const BODY_R: f32 = 0.38;
const HURT_R: f32 = 0.60;
const CENTER_F: f32 = 0.58;
const TOP_F: f32 = 1.02;

const HP_MAX: f32 = 180.0;
/// **DEAD WOOD DOES NOT FLINCH.** There is no physical resistance column in this game (armour is its own
/// number), so "heavy and dense" is spent on POISE — light spam does not interrupt a bough.
const POISE_MAX: f32 = 34.0;
const STANCE_MAX: f32 = 38.0;
/// Fire is the answer twice over: the damage AND the catch. Lightning is the second — it is still a tree.
const RESISTS = combat.resists(.{ .fire = -85, .lightning = -20, .cold = 25, .chaos = 40 });
pub const SOULS: u32 = 210;

const BOUGH_R: f32 = 2.30;
const BOUGH_FRONT_DOT: f32 = 0.34;
const BOUGH_WIND: f32 = 0.86;
const BOUGH_STRIKE: f32 = 0.22;
const BOUGH_RECOVER: f32 = 0.95;
const BOUGH_CD: f32 = 3.0;
pub const BOUGH_HIT = combat.Hit{ .dmg = 22, .poise = 22, .stance = 14 };
/// What the same swing carries once it is alight — added on top, so the LIT blow is the unlit one plus fire.
pub const LIT_FIRE: f32 = 14.0;

// **THE CATCH.** `lit` is 0..1 of a meter that raw fire fills and that leaks back down; at 1 it LATCHES
// (`caught`) and never goes out. Two dials so a stray fire arrow cannot light one by accident and a torch
// held on it can.
/// Raw fire damage to take one from cold to caught. A fire arrow is 8-ish, so it is a committed act.
pub const LIGHT_AT: f32 = 40.0;
/// Per second the partial meter leaks. Well over one fire arrow's worth a second, so it must be SUSTAINED.
const LIT_DECAY: f32 = 0.35;
/// **CATCHING IT KILLS IT** — its own bark burns it down over `HP_MAX / LIT_DPS` = 15 s (printed by the test).
pub const LIT_DPS: f32 = 12.0;
/// Half again as fast, on the feet AND on the swing.
pub const LIT_HASTE: f32 = 1.55;
/// A caught one lights the next one: within this, per second, of the neighbour's own meter.
pub const SPREAD_R: f32 = 2.0;
const SPREAD_RATE: f32 = 0.85;

comptime {
    std.debug.assert(BOUGH_WIND >= foe.TELL_MIN);
    // The wind stays a real tell even at full haste, or lighting one makes its only blow unreactable.
    std.debug.assert(BOUGH_WIND / LIT_HASTE >= foe.TELL_MIN);
    std.debug.assert(LIT_DECAY * LIGHT_AT > 12.0);
}

const DEATH_DUR: f32 = 1.35;
const DISS_DUR: f32 = 1.1;
const SHOVE_DECAY: f32 = 6.0;
const DISSOLVE = foe.Dissolve{ .rate = 38.0, .spread = 0.45, .rise = 0.6, .flake = BARK };

const A_PROT: f32 = 1.4;
const SWAY: f32 = 3.2;
const PELVIS_SHARE: f32 = 1.0 / 7.0;

const FLAME_RATE_LIT: f32 = 64.0;
const SMOKE_RATE: f32 = 10.0;
const HIT_CHIP_LIGHT = 5;
const HIT_CHIP_HEAVY = 11;
const PARTS = 68;
comptime {
    std.debug.assert(@as(f32, PARTS) >= FLAME_RATE_LIT * 0.52 +
        @as(f32, @floatFromInt(foe.hitParts(HIT_CHIP_HEAVY) + foe.WOUND_PARTS)));
}

const State = enum { idle, walk, bough, stunlight, stunheavy, dead };

const Choice = enum { rest, hold, close, bough };

fn classify(gap: f32, sensed: f32, homeGap: f32, boughReady: bool, rooted: bool) Choice {
    if (sensed > AGGRO_R) return if (homeGap > HOME_R) .hold else .rest;
    if (gap <= BOUGH_R and boughReady) return .bough;
    if (rooted) return .rest;
    return .close;
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        return .{ .bone = buildBones(), .mat = gfx.material(shader, "birchwight") };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, w: *const Wight) void {
        for (0..HELD) |i| rl.drawMesh(self.bone[i], self.mat, w.xf[i]);
    }
};

pub const Wight = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
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
    boughCd: f32 = 0,
    speed: f32 = 0,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    /// 0..1 of the catch. Fire fills it, `LIT_DECAY` empties it, and at 1 `caught` latches for good.
    lit: f32 = 0,
    caught: bool = false,
    /// One-frame edge for the beat that says so.
    justCaught: bool = false,

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

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Wight {
        var w = Wight{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        w.fxRng = foe.fxStream(seed, 60919.0, 0xB18C);
        w.aiRng = foe.fxStream(seed, 27011.0, 13);
        w.boughCd = seed * 1.0;
        w.pose();
        return w;
    }

    pub fn centerWorld(self: *const Wight) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, 0);
    }
    pub fn lockPoint(self: *const Wight) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], v3(0, 0.04 * H, 0));
    }
    pub fn topWorld(self: *const Wight) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Wight) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Wight) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Wight) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Wight) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Wight) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn airborne(_: *const Wight) bool {
        return false;
    }
    pub fn flashFrac(self: *const Wight) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn kind(_: *const Wight) wf.FoeKind {
        return .birchwight;
    }

    /// **ONE DIAL DRIVES EVERY FAST THING IT DOES**, so the fight speeding up is one number and not five.
    pub fn haste(self: *const Wight) f32 {
        return if (self.caught) LIT_HASTE else 1.0;
    }
    /// The blow it is actually carrying — the unlit one, plus fire once the bark has taken.
    pub fn boughHit(self: *const Wight) combat.Hit {
        var h = BOUGH_HIT;
        if (self.caught) h.elem = combat.elems(.{ .fire = LIT_FIRE });
        return h;
    }
    fn windDur(self: *const Wight) f32 {
        return BOUGH_WIND / self.haste();
    }
    fn strikeDur(self: *const Wight) f32 {
        return BOUGH_STRIKE / self.haste();
    }
    fn recoverDur(self: *const Wight) f32 {
        return BOUGH_RECOVER / self.haste();
    }

    /// **THE ONE DOOR THE BARK CATCHES THROUGH**, so a torch, an arrow, a spell and a neighbour cannot each
    /// have their own arithmetic. `raw` is fire BEFORE resistance: the creature's fire weakness is already
    /// spent on the damage, and billing it twice would make one arrow light a tree.
    pub fn kindle(self: *Wight, raw: f32) void {
        if (self.caught or self.state == .dead or raw <= 0) return;
        self.lit = mathx.clampF(self.lit + raw / LIGHT_AT, 0, 1);
        if (self.lit >= 1.0) {
            self.caught = true;
            self.justCaught = true;
            sfx.world(.shroom_fling, self.pos);
        }
    }

    pub fn navWant(self: *const Wight, quarry: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .walk) return null;
        if (foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R) <= AGGRO_R) return quarry;
        return if (mathx.distXZ(self.pos, self.home) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Wight, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE * self.haste(), dt);
    }

    /// -1 hauled overhead, +1 driven into the ground, easing back to 0 across the recovery.
    fn boughAmt(self: *const Wight) f32 {
        if (self.state != .bough) return 0;
        const wind = self.windDur();
        if (self.t < wind) return -mathx.smoothstep(0, wind * 0.94, self.t);
        const s = self.t - wind;
        const str = self.strikeDur();
        if (s < str) return lerpF(-1.0, 1.0, foe.swingCurve(s / str));
        return 1.0 - mathx.smoothstep(str, str + self.recoverDur() * 0.7, s);
    }

    fn stunAmount(self: *const Wight) f32 {
        if (self.state != .stunlight and self.state != .stunheavy) return 0;
        return foe.stunCurve(self.t, self.state == .stunheavy);
    }

    pub fn update(self: *Wight, dt: f32, quarry: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        self.justCaught = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.boughCd = mathx.maxF(0, self.boughCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, quarry, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
        self.tickFire(dt);

        var movedDist: f32 = 0;
        var moveSpeed: f32 = 0;
        var moveYaw: ?f32 = null;

        switch (self.state) {
            .dead => {
                self.speed = 0;
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .stunlight, .stunheavy => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .bough => {
                self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                const wind = self.windDur();
                if (self.t < wind) self.faceToward(quarry, dt);
                const s = self.t - wind;
                if (s >= 0 and s < self.strikeDur()) self.tryBough(quarry);
                if (self.t >= wind + self.strikeDur() + self.recoverDur()) {
                    self.heroLatch = false;
                    self.enter(.idle);
                }
            },
            .idle, .walk => {
                const sensed = foe.senseHero(&self.leash, self.pos, quarry, AGGRO_R);
                const gap = mathx.maxF(0, sensed - foe.HERO_R - self.bodyR());
                const homeGap = mathx.distXZ(self.pos, self.home);
                switch (classify(gap, sensed, homeGap, self.boughCd <= 0, self.root.held())) {
                    .rest => {
                        if (sensed <= AGGRO_R) self.faceToward(quarry, dt);
                        self.speed = approach(self.speed, 0, ACCEL * dt);
                        self.state = .idle;
                    },
                    .bough => {
                        self.speed = approach(self.speed, 0, ACCEL * 2.0 * dt);
                        self.boughCd = BOUGH_CD / self.haste() * self.aiRng.range(0.85, 1.2);
                        self.heroLatch = false;
                        self.enter(.bough);
                    },
                    .hold, .close => |ch| {
                        const to = if (ch == .hold) self.home else quarry;
                        const want = (if (ch == .hold) WALK_SPEED else CHASE_SPEED) * self.haste();
                        self.faceToward(self.nav.aim(self.pos, to), dt);
                        self.speed = approach(self.speed, want, ACCEL * dt);
                        moveSpeed = self.speed;
                        const moved = moveSpeed * dt * self.chill.travel();
                        const way = self.nav.along(mathx.headingDir(self.facing));
                        mathx.stepXZ(&self.pos, way, moved, bounds);
                        movedDist = moved;
                        moveYaw = mathx.headingXZ(way);
                        self.state = .walk;
                    },
                }
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.emitFire(dt);
        self.pose();
        self.tryHit(blade);
        return self.heroHit;
    }

    /// **CAUGHT, IT IS BURNING ITSELF DOWN.** Billed as a `drip` so nothing it does can build its own meters
    /// off it, and so the death goes through the ordinary door.
    fn tickFire(self: *Wight, dt: f32) void {
        if (self.state == .dead) return;
        if (!self.caught) {
            self.lit = mathx.maxF(0, self.lit - LIT_DECAY * dt);
            return;
        }
        // `gore` — no element, so its own fire resistance cannot make it fireproof against its own bark.
        _ = self.vit.drip(.{ .gore = LIT_DPS * dt });
        if (self.vit.dead) self.enterDeath();
    }

    fn tryBough(self: *Wight, quarry: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, quarry, foe.hurtReach(BOUGH_R, self.scale), BOUGH_FRONT_DOT)) return;
        self.heroHit = self.boughHit();
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    pub fn tryHit(self: *Wight, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        // **THE BARK READS THE BLOW ITSELF**, before the reaction, so a killing fire blow still lit it on the
        // way past — which is what makes a lit corpse look like the thing that killed it.
        self.kindle(blade.hit.elem.at(.fire));
        const heavy = foe.wounded(self, s, blade, .{ .light = 0.35, .heavy = 0.9 });
        self.chips(s.contact, s.dir, foe.hitParts(if (heavy) HIT_CHIP_HEAVY else HIT_CHIP_LIGHT));
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn enter(self: *Wight, s: State) void {
        self.state = s;
        self.t = 0;
    }
    fn enterStun(self: *Wight, s: State) void {
        self.heroLatch = false;
        self.enter(s);
    }
    fn enterDeath(self: *Wight) void {
        if (self.state == .dead) return;
        self.heroLatch = false;
        self.enter(.dead);
        self.justDied = true;
    }
    pub fn stagger(self: *Wight, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugBough(self: *Wight) void {
        self.heroLatch = false;
        self.enter(.bough);
    }
    pub fn debugLight(self: *Wight) void {
        self.kindle(LIGHT_AT);
    }
    pub fn debugKill(self: *Wight) void {
        self.enterDeath();
    }

    const CHIP_SPRAY = foe.Spray{
        .fanLo = 0.25,
        .fanHi = 0.95,
        .upLo = 0.3,
        .upHi = 1.5,
        .lifeLo = 0.35,
        .lifeHi = 0.75,
        .rLo = 0.016,
        .rHi = 0.034,
        .r1 = 0.010,
        .col = BARK,
        .col1 = ROT,
        .grav = foe.DUST_GRAV,
        .bounce = 0.25,
    };
    fn chips(self: *Wight, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, 2.6, self.scale, CHIP_SPRAY);
    }

    /// **THE CATCH IS VISIBLE BEFORE IT LATCHES** — smoke off a kindling one, flame off a caught one. A player
    /// who cannot see the meter filling cannot decide whether to keep the torch on it.
    fn emitFire(self: *Wight, dt: f32) void {
        if (self.state == .dead or (self.lit <= 0.02 and !self.caught)) return;
        const rate = if (self.caught) FLAME_RATE_LIT else SMOKE_RATE * self.lit;
        var owed = foe.emitDue(&self.fxAccum, dt, rate);
        const sig = elemfx.sig(.fire);
        while (owed > 0) : (owed -= 1) {
            // Up the trunk from the feet: a tree takes from the bottom, and a mote at the crown of an
            // ankle-high flame is the picture disagreeing with the meter.
            const up = self.fxRng.float() * (if (self.caught) 1.0 else self.lit);
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.02, 0.07) * H * self.scale;
            const at = v3(
                self.pos.x + mathx.cosf(a) * rr,
                self.pos.y + up * TOP_F * H * self.scale,
                self.pos.z + mathx.sinf(a) * rr,
            );
            const flame = self.caught;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = at,
                .v = v3(self.fxRng.signed() * 0.2, self.fxRng.range(0.4, 1.3), self.fxRng.signed() * 0.2),
                .life = self.fxRng.range(if (flame) 0.26 else 0.6, if (flame) 0.52 else 1.1),
                .r0 = if (flame) sig.r0 else 0.05,
                .r1 = if (flame) sig.r1 * 1.5 else 0.16,
                .col = if (flame) sig.core else ROT,
                .col1 = if (flame) sig.ash else foe.DUST_THIN,
                .grav = if (flame) sig.grav else -0.5,
                .drag = sig.drag,
            });
        }
    }

    pub fn drawFx(self: *const Wight) void {
        foe.drawParticles(&self.parts);
    }
    pub fn draw(self: *const Wight, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Wight) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(foe.SINK_HUMANOID, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;
        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.6, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();
        const m = self.moving * (1.0 - dk);
        const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);
        const bough = self.boughAmt();

        // A standing tree does not hunch. It LEANS, slowly, and the lean is most of the idle.
        const creak = SWAY * mathx.sinf(self.elapsed * 0.42 + self.seed * 6.28) * (1.0 - m);
        const bodyPitch = 20.0 * mathx.maxF(0, bough) - 12.0 * mathx.maxF(0, -bough) - 18.0 * stun + 74.0 * dk;
        const leanX = PELVIS_SHARE * bodyPitch;
        const waist = (1.0 - PELVIS_SHARE) * bodyPitch;
        const lumber = 2.4 * mathx.sinf(std.math.tau * self.phase) * m;

        var wx: [N]rl.Matrix = undefined;
        // **A FELLED TREE GOES OVER, IT DOES NOT SIT DOWN** — the death is a topple about the ankles, so the
        // pelvis barely drops and the whole length of it swings through the pitch instead.
        const pelvY = if (dead) lerpF(hipY, hipY * 0.72, dk) else hipY + pel.bob - pel.dip;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(creak * 0.6 + lumber * 0.4 + 6.0 * dk), rx(leanX), ry(pel.prot)),
            mul(tr(pel.sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));
        if (!dead) {
            heromod.legChain(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.pos.y, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        } else {
            heromod.deadLegs(&wx, self.rest, dk);
        }
        self.poseUpper(&wx, waist, bough, stun, dk, pel.prot, lumber, creak);
        self.xf = wx;
    }

    fn poseUpper(self: *Wight, wx: *[N]rl.Matrix, waist: f32, bough: f32, stun: f32, dk: f32, prot: f32, lumber: f32, creak: f32) void {
        const rest = self.rest;
        const m = self.moving * (1.0 - dk);
        const lean = (self.seed - 0.5) * 8.0;

        setLocal(wx, SPINE, rest, mul3(rx(waist * 0.40), ry(-0.25 * prot), rz(lean * 0.4 + creak * 0.5 - 0.3 * lumber)));
        setLocal(wx, CHEST, rest, mul3(rx(waist * 0.60), ry(-0.4 * prot), rz(lean * 0.3 + creak * 0.4 - 0.2 * lumber)));
        setLocal(wx, NECK, rest, rx(-6.0 * bough + 5.0 * dk - 4.0 * stun));
        setLocal(wx, CROWN, rest, mul3(rx(-12.0 * bough + 10.0 * dk - 20.0 * stun), ry(-0.3 * prot), rz(lean + creak)));

        // **BOTH BOUGHS COME OVERHEAD AND COME DOWN TOGETHER** — the tell is the whole tree rearing back, and
        // at this stature it is readable from further out than the swing can reach.
        const armStun = -34.0 * stun;
        const swing = -7.0 * heromod.armSwing(self.phase) * m * @abs(self.fwdB);
        const haul = -128.0 * mathx.maxF(0, -bough);
        const drive = 84.0 * mathx.maxF(0, bough);
        inline for (.{ SHL, SHR }, .{ ELL, ELR }, .{ WRL, WRR }, .{ 1.0, -1.0 }) |sh, el, wr, side| {
            const s = if (side > 0) swing else -swing;
            setLocal(wx, sh, rest, mul3(rx(-(10.0 + s) + haul - drive + armStun - 14.0 * dk), ry(0), rz(side * (18.0 + 6.0 * @abs(lean)))));
            setLocal(wx, el, rest, rx(-(14.0 + 16.0 * @abs(bough))));
            setLocal(wx, wr, rest, rz(side * 4.0));
        }
    }
};

const CAP_N = wf.MAX_PER_KIND;

pub const Stand = struct {
    model: Model,
    wights: [CAP_N]Wight = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Stand {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Stand) []Wight {
        return self.wights[0..self.n];
    }
    pub fn liveConst(self: *const Stand) []const Wight {
        return self.wights[0..self.n];
    }
    pub fn reset(self: *Stand, m: *const wf.Map) void {
        foe.resetGroup(Wight, &self.wights, &self.n, m, .birchwight);
    }
    pub fn clear(self: *Stand) void {
        self.n = 0;
    }
    pub fn setShader(self: *Stand, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Stand, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }

    pub fn update(self: *Stand, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        self.spread(dt);
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }

    /// **A CAUGHT ONE LIGHTS THE NEXT ONE.** Read off the caught bodies and written onto the cold ones in one
    /// pass, so the order of the group cannot decide who catches — and a body already caught is skipped, or a
    /// pair of them would sit trading a meter that is already full.
    fn spread(self: *Stand, dt: f32) void {
        var anyLit = false;
        for (self.liveConst()) |*w| {
            if (w.caught and w.state != .dead) anyLit = true;
        }
        if (!anyLit) return;
        var i: usize = 0;
        while (i < self.n) : (i += 1) {
            const w = &self.wights[i];
            if (w.caught or w.state == .dead or !w.alive()) continue;
            var near = false;
            for (self.liveConst()) |*o| {
                if (!o.caught or o.state == .dead) continue;
                if (mathx.distXZ(o.pos, w.pos) <= SPREAD_R * (o.scale + w.scale) * 0.5) near = true;
            }
            if (near) w.kindle(SPREAD_RATE * LIGHT_AT * dt);
        }
    }

    pub fn litCount(self: *const Stand) u32 {
        var n: u32 = 0;
        for (self.liveConst()) |*w| {
            if (w.caught and w.alive()) n += 1;
        }
        return n;
    }
    pub fn anyCaught(self: *const Stand) bool {
        for (self.liveConst()) |*w| {
            if (w.justCaught) return true;
        }
        return false;
    }

    pub fn draw(self: *const Stand, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Stand) void {
        for (self.liveConst()) |*w| w.drawFx();
    }
    pub fn pierce(self: *Stand, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Stand) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn anyParried(self: *const Stand) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn soulsDropped(self: *const Stand) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Stand) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Stand) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn buildBones() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = boleMesh(0.086, 0.078, 0.090, 0x8100);
    mesh[SPINE] = boleMesh(0.078, 0.070, 0.128, 0x8101);
    mesh[CHEST] = trunkMesh();
    mesh[NECK] = boleMesh(0.038, 0.034, 0.062, 0x8103);
    mesh[CROWN] = crownMesh();
    mesh[HIPL] = limbMesh(1.0, heromod.SEG_THIGH, 0.046, 0.036, 0x8104);
    mesh[KNEEL] = limbMesh(1.0, heromod.SEG_SHANK, 0.034, 0.026, 0x8105);
    mesh[ANKL] = rootFootMesh(1.0);
    mesh[HIPR] = limbMesh(-1.0, heromod.SEG_THIGH, 0.046, 0.036, 0x8106);
    mesh[KNEER] = limbMesh(-1.0, heromod.SEG_SHANK, 0.034, 0.026, 0x8107);
    mesh[ANKR] = rootFootMesh(-1.0);
    mesh[SHL] = limbMesh(1.0, heromod.SEG_UPARM, 0.036, 0.028, 0x8108);
    mesh[ELL] = limbMesh(1.0, heromod.SEG_FOREARM, 0.028, 0.020, 0x8109);
    mesh[WRL] = twigMesh(1.0);
    mesh[SHR] = limbMesh(-1.0, heromod.SEG_UPARM, 0.036, 0.028, 0x810A);
    mesh[ELR] = limbMesh(-1.0, heromod.SEG_FOREARM, 0.028, 0.020, 0x810B);
    mesh[WRR] = twigMesh(-1.0);
    return mesh;
}

/// **THE LENTICELS ARE THE WHOLE TREE.** Birch is a pale bole with dark horizontal dashes; without them the
/// mesh is a white pipe and reads as bone, which is the one thing on this field it must not be mistaken for.
fn lenticels(b: *Builder, rng: *mathx.Rng, len: f32, r: f32, n: u32) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const y = -len * H * rng.range(0.08, 0.94);
        const a = rng.angle();
        const w = rng.range(0.30, 0.70) * r * H;
        const cx = mathx.cosf(a) * r * H * 0.93;
        const cz = mathx.sinf(a) * r * H * 0.93;
        b.addCapsule(
            v3(cx - mathx.sinf(a) * w, y, cz + mathx.cosf(a) * w),
            v3(cx + mathx.sinf(a) * w, y + rng.range(-0.002, 0.002) * H, cz - mathx.cosf(a) * w),
            0.0090 * H,
            0.0075 * H,
            4,
            LENTICEL,
        );
    }
}

fn boleMesh(rTop: f32, rBot: f32, len: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, -len * H, 0), rTop * H, rBot * H, 10, BARK);
    b.setMat(.plain);
    lenticels(&b, &rng, len, rBot, 11);
    return b.toMesh();
}

/// The chest is where the tree DIED: a split bole with the heartwood open down the front and a knothole in it.
fn trunkMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x8102);
    b.setMat(.skin);
    b.addCapsule(v3(0, -0.010 * H, 0), v3(0, 0.078 * H, 0), 0.082 * H, 0.092 * H, 11, BARK);
    b.addBlob(v3(0, 0.062 * H, -0.010 * H), v3(0.086 * H, 0.032 * H, 0.078 * H), 9, 6, BARK_LT);
    b.setMat(.plain);
    b.addCapsule(v3(0, -0.006 * H, 0.062 * H), v3(0, 0.058 * H, 0.058 * H), 0.030 * H, 0.024 * H, 7, HEARTWOOD);
    b.addBlob(v3(0, 0.026 * H, 0.076 * H), v3(0.020 * H, 0.024 * H, 0.012 * H), 6, 5, KNOTHOLE);
    lenticels(&b, &rng, 0.078, 0.086, 15);
    return b.toMesh();
}

/// No face. A crown of dead twigs and one ember caught in the fork where a bird's nest went — the only warm
/// thing on it before it catches, and what a player's eye finds in a stand of them.
fn crownMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x8C0E);
    b.setMat(.skin);
    b.addCapsule(v3(0, -0.010 * H, 0), v3(0, 0.030 * H, 0), 0.034 * H, 0.030 * H, 8, BARK);
    var i: u32 = 0;
    while (i < 9) : (i += 1) {
        const a = rng.angle();
        const up = rng.range(0.045, 0.098) * H;
        const out = rng.range(0.028, 0.072) * H;
        b.addCapsule(
            v3(0, 0.022 * H, 0),
            v3(mathx.cosf(a) * out, 0.022 * H + up, mathx.sinf(a) * out),
            0.008 * H,
            0.0025 * H,
            5,
            ROT,
        );
    }
    b.setMat(.plain);
    b.addBlob(v3(0.012 * H, 0.030 * H, 0.026 * H), v3(0.011 * H, 0.010 * H, 0.009 * H), 5, 5, EMBER_EYE);
    return b.toMesh();
}

fn limbMesh(side: f32, len: f32, rTop: f32, rBot: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.008 * H, -len * H, 0), rTop * H, rBot * H, 8, BARK);
    // The knot at the joint: bark over the socket, and what stops the limb reading as a cut pipe.
    b.addBlob(v3(0, 0.004 * H, 0), v3(rTop * 1.16 * H, rTop * 1.05 * H, rTop * 1.16 * H), 7, 5, BARK);
    b.setMat(.plain);
    lenticels(&b, &rng, len, rBot, 8);
    return b.toMesh();
}

/// It walks on its own root ball — the picture of a thing that pulled itself out of the ground.
fn rootFootMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x800F);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.006 * H, 0.010 * H), v3(0.044 * H, 0.026 * H, 0.052 * H), 7, 5, ROT);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.range(-1.2, 1.2) + (if (side > 0) @as(f32, 0.3) else @as(f32, -0.3));
        b.addCapsule(
            v3(0, 0.004 * H, 0.008 * H),
            v3(mathx.sinf(a) * 0.050 * H, -0.014 * H, mathx.cosf(a) * 0.062 * H),
            0.010 * H,
            0.004 * H,
            5,
            ROT,
        );
    }
    return b.toMesh();
}

fn twigMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const f = (@as(f32, @floatFromInt(i)) - 1.5) / 1.5;
        b.addCapsule(
            v3(side * f * 0.012 * H, 0, 0),
            v3(side * f * 0.036 * H, -0.062 * H, 0.014 * H),
            0.010 * H,
            0.0025 * H,
            5,
            ROT,
        );
    }
    return b.toMesh();
}


test "IT TAKES A SUSTAINED FLAME, NOT A STRAY ARROW" {
    var w = Wight.spawn(mathx.zero3, 0, 1.0, 0.3);
    // One fire arrow's worth, then left alone: it smoulders and goes out.
    w.kindle(8.0);
    try std.testing.expect(!w.caught);
    try std.testing.expect(w.lit > 0);
    var t: f32 = 0;
    while (t < 2.0) : (t += 1.0 / 60.0) _ = w.update(1.0 / 60.0, v3(0, 0, 40), 400, .{});
    try std.testing.expectApproxEqAbs(@as(f32, 0), w.lit, 1e-4);
    try std.testing.expect(!w.caught);

    // Held on it, it catches — and once caught it never goes out.
    var lit = Wight.spawn(mathx.zero3, 0, 1.0, 0.3);
    var fed: f32 = 0;
    t = 0;
    while (t < 3.0 and !lit.caught) : (t += 1.0 / 60.0) {
        lit.kindle(18.0 * (1.0 / 60.0) * 6.0);
        fed += 18.0 * (1.0 / 60.0) * 6.0;
        _ = lit.update(1.0 / 60.0, v3(0, 0, 40), 400, .{});
    }
    std.debug.print("\n  birchwight: caught on {d:.0} raw fire (LIGHT_AT {d:.0}, leaking {d:.2}/s)\n", .{ fed, LIGHT_AT, LIT_DECAY });
    try std.testing.expect(lit.caught);
    t = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) _ = lit.update(1.0 / 60.0, v3(0, 0, 40), 400, .{});
    try std.testing.expect(lit.caught);
}

test "CATCHING IT KILLS IT — and the clock is its own bark, not your sword" {
    var w = Wight.spawn(mathx.zero3, 0, 1.0, 0.3);
    w.debugLight();
    try std.testing.expect(w.caught);
    var t: f32 = 0;
    while (t < 40.0 and w.state != .dead) : (t += 1.0 / 60.0) _ = w.update(1.0 / 60.0, v3(0, 0, 40), 400, .{});
    std.debug.print("  a caught birchwight burns down in {d:.1} s all on its own ({d:.0} hp at {d:.0}/s)\n", .{ t, HP_MAX, LIT_DPS });
    try std.testing.expect(w.state == .dead);
    try std.testing.expectApproxEqAbs(HP_MAX / LIT_DPS, t, 0.6);
}

test "…BUT IT IS A WORSE FIGHT WHILE IT BURNS: faster feet, faster swing, and the blow carries fire" {
    var cold = Wight.spawn(mathx.zero3, 0, 1.0, 0.3);
    var hot = Wight.spawn(mathx.zero3, 0, 1.0, 0.3);
    hot.debugLight();
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), cold.haste(), 1e-6);
    try std.testing.expectApproxEqAbs(LIT_HASTE, hot.haste(), 1e-6);
    try std.testing.expect(hot.windDur() < cold.windDur());
    try std.testing.expectApproxEqAbs(@as(f32, 0), cold.boughHit().elem.at(.fire), 1e-6);
    try std.testing.expectApproxEqAbs(LIT_FIRE, hot.boughHit().elem.at(.fire), 1e-6);
    // The tell survives the haste — that is the line the comptime assert holds and this one measures.
    std.debug.print("  bough wind {d:.2} s cold, {d:.2} s lit (floor {d:.2})\n", .{ cold.windDur(), hot.windDur(), foe.TELL_MIN });
    try std.testing.expect(hot.windDur() >= foe.TELL_MIN);
}

test "A CAUGHT ONE LIGHTS THE NEXT ONE — the torch is a mistake in a stand of them" {
    var s = Stand{ .model = undefined };
    s.wights[0] = Wight.spawn(mathx.zero3, 0, 1.0, 0.3);
    s.wights[1] = Wight.spawn(v3(0, 0, SPREAD_R * 0.8), 0, 1.0, 0.5);
    // Well outside the spread, and it must stay cold.
    s.wights[2] = Wight.spawn(v3(0, 0, SPREAD_R * 6.0), 0, 1.0, 0.7);
    s.n = 3;
    s.wights[0].debugLight();
    const away = v3(0, 0, 90);
    var t: f32 = 0;
    while (t < 4.0 and !s.wights[1].caught) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, away, 400, .{});
    std.debug.print("  spread: neighbour at {d:.1} m caught in {d:.2} s\n", .{ SPREAD_R * 0.8, t });
    try std.testing.expect(s.wights[1].caught);
    try std.testing.expect(!s.wights[2].caught);
    try std.testing.expectEqual(@as(u32, 2), s.litCount());
}

test "A FIRE BLOW LIGHTS IT THROUGH THE ORDINARY DOOR — the bark reads the blade, not a special case" {
    var w = Wight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const torch = foe.Blade{
        .active = true,
        .r = 0.3,
        .a = w.centerWorld(),
        .b = w.centerWorld(),
        .a0 = w.centerWorld(),
        .b0 = w.centerWorld(),
        .hit = .{ .dmg = 4, .elem = combat.elems(.{ .fire = LIGHT_AT }) },
    };
    w.tryHit(torch);
    try std.testing.expect(w.caught);
    // …and a steel blade of the same weight never lights one.
    var steel = Wight.spawn(mathx.zero3, 0, 1.0, 0.3);
    var b2 = torch;
    b2.hit = .{ .dmg = 40 };
    steel.tryHit(b2);
    try std.testing.expect(!steel.caught);
    try std.testing.expectApproxEqAbs(@as(f32, 0), steel.lit, 1e-6);
}

test "FIRE IS THE ANSWER AND LIGHTNING IS THE SECOND ONE" {
    const shot = 40.0;
    var fire = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    var levin = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    var rime = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = fire.hit(.{ .elem = combat.elems(.{ .fire = shot }) });
    _ = levin.hit(.{ .elem = combat.elems(.{ .lightning = shot }) });
    _ = rime.hit(.{ .elem = combat.elems(.{ .cold = shot }) });
    const tookFire = HP_MAX - fire.hp;
    const tookLevin = HP_MAX - levin.hp;
    const tookRime = HP_MAX - rime.hp;
    std.debug.print("  40 into a birchwight: fire {d:.0}, lightning {d:.0}, cold {d:.0}\n", .{ tookFire, tookLevin, tookRime });
    try std.testing.expect(tookFire > tookLevin and tookLevin > tookRime);
}

test "the pick is positional, and the bough is telegraphed once per swing" {
    try std.testing.expectEqual(Choice.bough, classify(BOUGH_R - 0.2, 2.5, 0, true, false));
    try std.testing.expectEqual(Choice.close, classify(BOUGH_R + 1.0, 4.0, 0, true, false));
    try std.testing.expectEqual(Choice.rest, classify(AGGRO_R, AGGRO_R + 1.0, 0, true, false));
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R, AGGRO_R + 1.0, HOME_R + 1.0, true, false));

    var w = Wight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 1.6);
    w.facing = mathx.headingXZ(mathx.dirXZ(w.pos, hero));
    w.debugBough();
    var landed: u32 = 0;
    var firstAt: f32 = 0;
    var t: f32 = 0;
    while (t < BOUGH_WIND + BOUGH_STRIKE + BOUGH_RECOVER + 0.1) : (t += 1.0 / 60.0) {
        if (w.update(1.0 / 60.0, hero, 400, .{}) != null) {
            if (landed == 0) firstAt = t;
            landed += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 1), landed);
    try std.testing.expect(firstAt >= foe.TELL_MIN);
}
