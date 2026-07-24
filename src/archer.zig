const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const heromod = @import("hero.zig");
const foe = @import("foe.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// ── THE SKELETAL ARCHER ─────────────────────────────────────────────────────────────────
// The second foe: a bare-bones skeleton that KITES — it holds a range band off the hero,
// looses slowish lightly-homing arrows that stick where they land and fade, and never melees
// (the opening is closing the gap). One-and-done death (collapse → dissipate; no ER reform).
//
// FOUNDED ON THE HUMANOID MODEL (owner's brief): it reuses the hero's real anthropometry
// (Drillis & Contini segment fractions), the same forward-kinematics scaffold (a per-bone
// world matrix chained down a parent hierarchy, `draw()` replays it in both the depth + lit
// passes), and the hero's NORMATIVE GAIT tables (heromod.HIP_FLEX/… + sampleCurve, now pub)
// so the skeleton walks on the same science instead of a duplicated cycle. What differs is
// the SKIN — bone meshes, not the Tarnished's armour — and the animation: an archer's
// nock / draw / hold / loose instead of sword cuts. Rig scaffold (parent/rest/setLocal) is
// re-stated locally so the archer's weapon bone (a BOW, not a sword) stays independent; if a
// third humanoid ever appears, lift the scaffold into a shared module then.
//
// Rendering discipline matches hero/frog: procedural Builder meshes drawn with drawMesh
// through one scene-shader material, so it lights + casts shadows like everything else.

// ── palette (pre-gamma dark — the scene shader gammas output, so pale bone is authored at a
// MODERATE value and lifts to ivory; hollows are near-black so sockets/gaps read empty) ────
const BONE = rgba(150, 142, 118, 255); // weathered ivory
const BONE_DK = rgba(96, 90, 74, 255); // shadowed recesses / old bone
const BONE_LT = rgba(176, 168, 146, 255); // caught-light ridges
const SOCKET = rgba(16, 14, 12, 255); // eye sockets, nasal cavity, rib gaps — hollow
const TEETH = rgba(196, 188, 164, 255); // pale teeth, pop against the skull
const BOWWOOD = rgba(44, 31, 19, 255); // dark horn-and-wood bow
const BOWWOOD_LT = rgba(60, 44, 28, 255);
const STRINGCOL = rgba(150, 144, 124, 255); // pale sinew string
const ARROW_SHAFT = rgba(72, 58, 38, 255); // arrow shaft (wood)
const ARROW_HEAD = rgba(120, 126, 134, 255); // steel pile
const ARROW_FLETCH = rgba(84, 72, 56, 255); // feather fletching

// ── rig: an 18-bone humanoid, same joint layout + parenting as the hero (the shared model),
// with the weapon slot repurposed as the BOW. Bow rides the RIGHT wrist (a left-hand-draw
// archer) — reusing the hero's weapon-on-right convention so the FK scaffold lines up. ─────
const N = 18;
const ROOT = 0; // pelvis
const SPINE = 1; // lumbar column
const CHEST = 2; // ribcage + shoulder girdle
const NECK = 3;
const SKULL = 4;
const HIPL = 5;
const KNEEL = 6;
const ANKL = 7;
const HIPR = 8;
const KNEER = 9;
const ANKR = 10;
const SHL = 11; // shoulder L (the DRAW arm)
const ELL = 12;
const WRL = 13;
const SHR = 14; // shoulder R (the BOW arm)
const ELR = 15;
const WRR = 16;
const BOW = 17; // the drawn bow, parented to the right wrist

const parent = [N]i32{ -1, ROOT, SPINE, CHEST, NECK, ROOT, HIPL, KNEEL, ROOT, HIPR, KNEER, CHEST, SHL, ELL, CHEST, SHR, ELR, WRR };

// Stature + segment lengths: the hero's exact anthropometry (Drillis & Contini 1966 / Winter),
// so the skeleton is a real human frame. H is imported; the fractions match hero.zig's table.
const H: f32 = heromod.H;
const SEG_THIGH = 0.245;
const SEG_SHANK = 0.246;
const SEG_UPARM = 0.188;
const SEG_FOREARM = 0.145;

fn restPositions() [N]rl.Vector3 {
    const hx = 0.090; // hip half-separation
    const sx = 0.150; // shoulder half-separation
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, 0.530, 0);
    r[SPINE] = v3(0, 0.640, 0);
    r[CHEST] = v3(0, 0.760, 0);
    r[NECK] = v3(0, 0.815, 0);
    r[SKULL] = v3(0, 0.885, 0);
    r[HIPL] = v3(hx, 0.530, 0);
    r[KNEEL] = v3(hx, 0.285, 0);
    r[ANKL] = v3(hx, 0.039, 0);
    r[HIPR] = v3(-hx, 0.530, 0);
    r[KNEER] = v3(-hx, 0.285, 0);
    r[ANKR] = v3(-hx, 0.039, 0);
    r[SHL] = v3(sx, 0.818, 0);
    r[ELL] = v3(sx, 0.630, 0);
    r[WRL] = v3(sx, 0.485, 0);
    r[SHR] = v3(-sx, 0.818, 0);
    r[ELR] = v3(-sx, 0.630, 0);
    r[WRR] = v3(-sx, 0.485, 0);
    r[BOW] = v3(-sx, 0.485, 0); // zero offset from the wrist; bow mesh authored in the wrist frame
    for (&r) |*p| p.* = v3(p.x * H, p.y * H, p.z * H);
    return r;
}

// matrix shorthand (shared mathx TRS — mul(a,b) applies a FIRST then b)
const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleV = mathx.scaleV;
const scaleM = mathx.scaleM;

// world(child) = animRot ∘ translate(offset) ∘ world(parent) — the hero's exact convention.
fn setLocal(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    const p: usize = @intCast(parent[i]);
    const off = mathx.subV(rest[i], rest[p]);
    const local = mul(animRot, tr(off.x, off.y, off.z));
    wx[i] = mul(local, wx[p]);
}

// ── locomotion / senses (world units / seconds) ─────────────────────────────────────────
pub const SCALE = 1.0; // archers stand at the hero's height — no global bump (unlike the toads)
const WALK_SPEED = heromod.WALK_SPEED * 0.95; // a wary, unhurried reposition
const AGGRO_R = 24.0; // notices + engages the hero within this (ranged, so wider than the toad)
const RANGE_MIN = 8.0; // too close → back off to re-open the shot
const RANGE_MAX = 20.0; // out past here → step in to close to band
const TURN_RATE = 6.0; // rad/s — tracks the hero (light aim tracking)
const BODY_R = 0.34; // ground footprint (matches the hero's HERO_R feel)
const HURT_R = 0.42; // hurt-sphere radius for the hero's blade
// Pelvis walk oscillation — the hero's amplitudes, so the shared gait reads as one humanoid.
const A_BOB = 0.024 * H;
const A_SWAY = 0.009 * H;

// ── archery timing (seconds) — a readable draw so the tell lands early, then a quick loose ─
const DRAW_DUR = 0.85; // raise + pull to full draw (the tell)
const HOLD_DUR = 0.45; // settle at full draw, aiming
const LOOSE_DUR = 0.14; // the release snap
const RECOVER_DUR = 0.55; // lower the bow, reset
const RELOAD_CD = 1.1; // beat between shots (nock the next)
const REPOSITION_DUR = 1.6; // how long a kite step lasts before re-deciding

// ── combat vitals (a skeleton is brittle: low-ish HP, modest poise) ─────────────────────
const HP_MAX = 58.0;
const POISE_MAX = 14.0; // a clean light hit still flinches it out of a draw
const STANCE_MAX = 30.0;
pub const ARROW_HIT = combat.Hit{ .dmg = 16, .poise = 10 }; // eased down from 20 (owner: lower dmg a bit)
const DEATH_DUR = 1.15; // collapse-and-still before the corpse dissipates
const DISS_DUR = 0.9; // dissipation into bone-dust + grace motes
const FLASH_DUR = 0.20;
const SHOVE_DECAY = 7.0;

// ── the arrow (a projectile, pooled) ────────────────────────────────────────────────────
// Slowish flight with LIGHT homing toward the hero (a gentle curve, not a lock-on), then it
// STICKS where it lands (ground / near the hero) and fades. Plain data + a tiny integrator.
const ARROW_SPEED = 15.0; // world units/s — slowish, dodgeable
const ARROW_HOMING = 2.2; // rad/s the heading may bend toward the hero (LIGHT tracking)
const ARROW_GRAV = 3.0; // gentle drop so long shots arc
const ARROW_LIFE = 3.5; // seconds airborne before it gives up (falls + sticks)
const ARROW_STICK_FADE = 1.4; // seconds a stuck arrow lingers, then fades
const ARROW_HIT_R = 0.5; // hero footprint the arrow must reach to connect

pub const Arrow = struct {
    pos: rl.Vector3 = mathx.zero3,
    vel: rl.Vector3 = mathx.zero3,
    live: bool = false,
    stuck: bool = false,
    age: f32 = 0, // in flight: seconds airborne; stuck: seconds since it stuck (fade timer)
    hit: bool = false, // it connected with the hero this frame (game.zig reads + clears)
};

// Loose an arrow from `from` toward `target`, with a little loft so the shot ARCS toward a
// (usually lower) target over distance — the light homing in stepArrow refines the rest.
pub fn launchArrow(from: rl.Vector3, target: rl.Vector3) Arrow {
    var d = mathx.subV(target, from);
    const dist = mathx.lenV(d);
    d = if (dist < 1e-3) v3(0, 0, 1) else mathx.scaleV(d, 1.0 / dist);
    var vel = mathx.scaleV(d, ARROW_SPEED);
    vel.y += ARROW_SPEED * 0.10 + dist * 0.04; // loft, to counter the drop across the gap
    return .{ .pos = from, .vel = vel, .live = true };
}

// Advance one arrow a frame: LIGHT homing (a gentle heading bend toward the hero — never a
// hard lock, so a sidestep beats it), gravity arc, then STICK on the hero / ground / expiry.
// Sets `hit` the frame it strikes the hero; a stuck arrow ages out and clears `live` (drawn
// shrinking away meanwhile — see arrowXform). `heroCenterY` = the hero's centre-of-mass height.
pub fn stepArrow(a: *Arrow, hero: rl.Vector3, heroCenterY: f32, dt: f32) void {
    if (!a.live) return;
    if (a.stuck) {
        a.age += dt;
        if (a.age >= ARROW_STICK_FADE) a.live = false;
        return;
    }
    a.age += dt;
    const target = v3(hero.x, heroCenterY, hero.z);
    const spd = mathx.lenV(a.vel);
    if (spd > 1e-3) {
        const cur = mathx.scaleV(a.vel, 1.0 / spd);
        const to = mathx.normV(mathx.subV(target, a.pos));
        // bend the HEADING toward the hero by a small fraction/second (keeps its speed) — but
        // only while still closing, so a shot that's been dodged flies PAST instead of U-turning.
        if (cur.x * to.x + cur.y * to.y + cur.z * to.z > 0.2) {
            const bent = mathx.normV(mathx.lerpV(cur, to, mathx.clampF(ARROW_HOMING * dt, 0, 1)));
            a.vel = mathx.scaleV(bent, spd);
        }
    }
    a.vel.y -= ARROW_GRAV * dt;
    a.pos = mathx.addV(a.pos, mathx.scaleV(a.vel, dt));
    if (mathx.distXZ(a.pos, hero) <= ARROW_HIT_R and @abs(a.pos.y - heroCenterY) <= 0.85) {
        a.hit = true;
        a.stuck = true;
        a.age = 0;
    } else if (a.pos.y <= 0.02 or a.age >= ARROW_LIFE) {
        a.pos.y = mathx.maxF(a.pos.y, 0.02); // stuck in the earth where it landed
        a.stuck = true;
        a.age = 0;
    }
}

// The draw matrix for one arrow: orient the mesh's +Z (its flight axis) along the velocity
// (yaw + pitch), placed at pos, shrinking over the back half of a stuck arrow's fade.
pub fn arrowXform(a: *const Arrow) rl.Matrix {
    const spd = mathx.lenV(a.vel);
    const dir = if (spd > 1e-3) mathx.scaleV(a.vel, 1.0 / spd) else v3(0, -1, 0);
    const yaw = mathx.degrees(std.math.atan2(dir.x, dir.z));
    const pitch = mathx.degrees(std.math.asin(mathx.clampF(-dir.y, -1, 1))); // +pitch = nose down
    const fade = if (a.stuck) 1.0 - mathx.smoothstep(ARROW_STICK_FADE * 0.5, ARROW_STICK_FADE, a.age) else 1.0;
    const s = mathx.clampF(fade, 0.06, 1.0);
    return mul(scaleM(s, s, s), mul3(rx(pitch), ry(yaw), tr(a.pos.x, a.pos.y, a.pos.z)));
}

// ── animation state ─────────────────────────────────────────────────────────────────────
// idle → (in band) draw → hold → loose → recover → reload; reposition when out of band. The
// last three are REACTIONS (interrupts): a light flinch, the heavy stance-break, and death.
const State = enum { idle, draw, hold, loose, recover, reposition, stunlight, stunheavy, dead };

// Pure kite decision — a function of range + reload, so it's unit-testable without a world.
const Choice = enum { shoot, back_off, close_in, hold_ground };
fn classify(dist: f32, reloaded: bool) Choice {
    if (dist > AGGRO_R) return .hold_ground; // hasn't noticed / disengaged
    if (dist < RANGE_MIN) return .back_off; // too close — kite out
    if (dist > RANGE_MAX) return .close_in; // too far — step in
    return if (reloaded) .shoot else .hold_ground; // in band: fire when nocked
}

// ── the shared skeleton meshes + material (built once, like the toad's) ──────────────────
pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("archer material");
        mat.shader = shader;
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, xf: *const [N]rl.Matrix) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, xf[i]);
    }
};

pub const Archer = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    reloadCd: f32 = 0,
    elapsed: f32 = 0,
    drawAmt: f32 = 0, // 0 = bow lowered, 1 = full draw (drives the pose)
    kiteDir: rl.Vector3 = mathx.zero3, // world XZ direction of the current reposition
    looseFired: bool = false, // one arrow per loose (latched)

    // Shared humanoid GAIT STATE — hero.advanceGait drives these, hero.legChain animates the
    // legs (the player's walk + strafe/backpedal). fwdB/latB = travel direction vs facing.
    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    // combat
    vit: combat.Vitals = combat.Vitals.init(HP_MAX, POISE_MAX, STANCE_MAX),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    fade: f32 = 0,
    gone: bool = false,

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Archer {
        var a = Archer{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * SCALE, .seed = seed };
        a.rest = restPositions();
        a.reloadCd = 0.4 + seed; // stagger the volley so a line doesn't fire in lockstep
        a.pose();
        return a;
    }

    pub fn centerWorld(self: *const Archer) rl.Vector3 {
        return v3(self.pos.x, 0.95 * H * self.scale, self.pos.z);
    }
    pub fn hurtRadius(self: *const Archer) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Archer) f32 {
        return BODY_R * self.scale;
    }
    pub fn lockPoint(self: *const Archer) rl.Vector3 {
        return v3(self.pos.x, 0.90 * H * self.scale, self.pos.z);
    }
    pub fn topWorld(self: *const Archer) rl.Vector3 {
        return v3(self.pos.x, 1.15 * H * self.scale, self.pos.z);
    }
    pub fn alive(self: *const Archer) bool {
        return !self.gone;
    }
    pub fn staggered(self: *const Archer) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn dying(self: *const Archer) bool {
        return self.state == .dead;
    }
    pub fn flashFrac(self: *const Archer) f32 {
        return mathx.clampF(self.flash / FLASH_DUR, 0, 1);
    }
    // Airborne never happens (no hops) — always grounded for collision.
    pub fn airborne(self: *const Archer) bool {
        _ = self;
        return false;
    }

    fn faceToward(self: *Archer, target: rl.Vector3, dt: f32) void {
        const d = mathx.dirXZ(self.pos, target);
        if (mathx.lenXZ(d) < 1e-3) return;
        self.facing = mathx.approachAngle(self.facing, mathx.headingXZ(d), TURN_RATE * dt);
    }

    // The nock point (where the arrow sits at full draw) ~ the bow hand, in world space.
    pub fn nockWorld(self: *const Archer) rl.Vector3 {
        const f = mathx.headingDir(self.facing);
        return v3(self.pos.x + f.x * 0.30 * self.scale, 1.02 * H * self.scale, self.pos.z + f.z * 0.30 * self.scale);
    }

    // ── per-frame update; returns true the frame it LOOSES (game.zig spawns the arrow). The
    // hero's `blade` is applied at the END (via tryHit) so a kill sets justDied for exactly THIS
    // frame's beat — the top-of-frame reset below makes it a true one-frame flag (was the
    // nonstop-shake bug when tryHit ran externally and justDied never cleared). ────────────────
    pub fn update(self: *Archer, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) bool {
        if (self.gone) return false;
        self.justDied = false; // one-frame flag: re-set below only if a blade kills it this frame
        self.elapsed += dt;
        self.vit.tick(dt);
        self.reloadCd = mathx.maxF(0, self.reloadCd - dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        self.t += dt;
        var loosed = false;
        var movedDist: f32 = 0; // this frame's walk distance + heading → the shared gait
        var moveYaw: ?f32 = null;

        if (mathx.lenXZ(self.shove) > 0.01) {
            self.pos.x = mathx.clampF(self.pos.x + self.shove.x * dt, -bounds, bounds);
            self.pos.z = mathx.clampF(self.pos.z + self.shove.z * dt, -bounds, bounds);
            self.shove = mathx.scaleV(self.shove, mathx.maxF(0, 1.0 - SHOVE_DECAY * dt));
        }

        const d = mathx.distXZ(self.pos, hero);
        switch (self.state) {
            .idle => {
                self.drawAmt = mathx.approach(self.drawAmt, 0, dt * 4.0);
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.decide(d);
            },
            .draw => {
                self.faceToward(hero, dt); // track while pulling
                self.drawAmt = mathx.smoothstep(0, DRAW_DUR, self.t);
                if (self.t >= DRAW_DUR) self.enter(.hold);
            },
            .hold => {
                self.faceToward(hero, dt);
                self.drawAmt = 1.0;
                if (self.t >= HOLD_DUR) self.enter(.loose);
            },
            .loose => {
                if (!self.looseFired) {
                    self.looseFired = true;
                    loosed = true; // game.zig spawns the arrow at nockWorld toward the hero
                }
                self.drawAmt = mathx.lerpF(1.0, 0.0, mathx.smoothstep(0, LOOSE_DUR, self.t)); // string snaps home
                if (self.t >= LOOSE_DUR) {
                    self.reloadCd = RELOAD_CD;
                    self.enter(.recover);
                }
            },
            .recover => {
                self.faceToward(hero, dt);
                self.drawAmt = mathx.approach(self.drawAmt, 0, dt * 3.0);
                if (self.t >= RECOVER_DUR) self.decide(d);
            },
            .reposition => {
                self.drawAmt = mathx.approach(self.drawAmt, 0, dt * 3.0);
                // Step along the committed kite direction while FACING the hero — so travel-vs-
                // facing feeds the shared gait as a STRAFE (lateral) or BACKPEDAL (kiting out).
                self.faceToward(hero, dt);
                const moved = WALK_SPEED * dt;
                self.pos.x = mathx.clampF(self.pos.x + self.kiteDir.x * moved, -bounds, bounds);
                self.pos.z = mathx.clampF(self.pos.z + self.kiteDir.z * moved, -bounds, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(self.kiteDir);
                if (self.t >= REPOSITION_DUR) self.decide(d);
            },
            .stunlight => {
                if (self.t >= combat.LIGHT_STUN_DUR) self.enter(.idle);
            },
            .stunheavy => {
                if (self.t >= combat.HEAVY_STUN_DUR) self.enter(.idle);
            },
            .dead => {
                if (self.t >= DEATH_DUR) {
                    self.fade = mathx.smoothstep(DEATH_DUR, DEATH_DUR + DISS_DUR, self.t);
                    if (self.t >= DEATH_DUR + DISS_DUR) self.gone = true;
                }
            },
        }

        // Drive the SHARED humanoid gait (the walk/strafe legs come from hero.legChain in pose()).
        const gaitSpeed: f32 = if (movedDist > 0) WALK_SPEED else 0;
        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist, gaitSpeed, moveYaw, self.facing);
        self.pose();
        self.tryHit(blade); // hero's blade AFTER the state machine (like the toad); a kill here
        //   flags justDied for this frame's kill beat, cleared at the top of the next update.
        return loosed;
    }

    fn enter(self: *Archer, s: State) void {
        self.state = s;
        self.t = 0;
        self.looseFired = false;
    }

    // Pick the next action from range + reload (kite AI). A too-close hero drives a back-off
    // step directly AWAY; too-far steps in; in-band-and-nocked draws a shot; else holds.
    fn decide(self: *Archer, dist: f32) void {
        switch (classify(dist, self.reloadCd <= 0)) {
            .shoot => self.enter(.draw),
            .back_off => {
                self.kiteDir = self.awayDir();
                self.enter(.reposition);
            },
            .close_in => {
                self.kiteDir = mathx.scaleV(self.awayDir(), -1); // toward the hero
                self.enter(.reposition);
            },
            .hold_ground => self.enter(.idle),
        }
    }
    // Unit direction pointing straight away from the hero, from the archer's facing (it faces
    // the hero, so −facing is "away"); a little seeded skew so a line doesn't retreat as one.
    fn awayDir(self: *const Archer) rl.Vector3 {
        const skew = (self.seed - 0.5) * 0.7;
        const yaw = self.facing + std.math.pi + skew;
        return mathx.headingDir(yaw);
    }

    fn enterStun(self: *Archer, s: State) void {
        self.state = s;
        self.t = 0;
        self.drawAmt = 0; // interrupted mid-draw — no shot leaves the bow
        self.looseFired = false;
    }
    fn enterDeath(self: *Archer) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    // ── the hero's blade lands on the skeleton (the SHARED foe.strike behaviour) ───────────
    fn tryHit(self: *Archer, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), blade) orelse return;
        self.hits += 1;
        self.flash = FLASH_DUR;
        const heavyBlow = blade.hit.stance > 0;
        self.shove = mathx.scaleV(s.dir, if (heavyBlow) 1.8 else 1.15); // a bone-clatter jolt off the blow
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    // ── pose: build the 18 bone matrices for this frame ───────────────────────────────────
    pub fn pose(self: *Archer) void {
        const fs = self.scale * (1.0 - 0.7 * self.fade);
        const sink = -0.55 * self.scale * self.fade; // corpse sinks as it dissipates
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        // Death crumple: fold + topple as it collapses (reaction pose lives entirely here).
        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.45, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        // Stagger: a big recoil back off the blow (light = a pulse, heavy = a sustained reel).
        const stunAmt = self.stunAmount();

        // Shared humanoid WALK: a bob + weight-sway ride the pelvis (quieting on collapse), and
        // the legs animate via hero.legChain below — the player's walk + strafe/backpedal footing.
        const m = self.moving * (1.0 - dk);
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const sway = A_SWAY * mathx.sinf(twoPi * self.phase) * m +
            A_SWAY * self.latB * mathx.cosf(twoPi * self.phase) * m; // weight rides onto the planting foot

        var wx: [N]rl.Matrix = undefined;
        const collapse = mathx.lerpF(hipY, 0.22 * H, dk); // pelvis drops on death
        const pitchBody = 20.0 * dk - 26.0 * stunAmt; // topple forward dead / arch back stunned
        // scaleM FIRST → the whole skeleton scales about its pelvis (per-archer size + the
        // death-dissipation shrink `fs`); the world placement `tr(pos)` stays unscaled.
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul(rz(10.0 * dk), rx(pitchBody)),
            mul(tr(sway, (if (dead) collapse else hipY + bob) + sink, 0), ry(facingDeg)),
            tr(self.pos.x, 0, self.pos.z),
        ));

        // Legs: the SHARED walk/strafe (runB = 0 — the archer only walks). When DEAD the crumple
        // in poseUpper owns the legs instead.
        if (!dead) {
            heromod.legChain(&wx, self.rest, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, ANKL);
            heromod.legChain(&wx, self.rest, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, ANKR);
        }
        self.poseUpper(&wx, dk, stunAmt, dead);
        self.xf = wx;
    }

    fn stunAmount(self: *const Archer) f32 {
        if (self.state == .stunlight) {
            const u = mathx.clampF(self.t / combat.LIGHT_STUN_DUR, 0, 1);
            return mathx.sinf(u * std.math.pi);
        } else if (self.state == .stunheavy) {
            const u = mathx.clampF(self.t / combat.HEAVY_STUN_DUR, 0, 1);
            return mathx.smoothstep(0, 0.14, u) * (1.0 - mathx.smoothstep(0.7, 1.0, u));
        }
        return 0;
    }

    // Spine, head, the archery arms, and (only when DEAD) the buckling legs. `dk` = death
    // collapse, `stun` = recoil. Alive, the LEGS come from hero.legChain in pose() (the shared
    // walk/strafe) — this only lays the archery upper body on top.
    fn poseUpper(self: *Archer, wx: *[N]rl.Matrix, dk: f32, stun: f32, dead: bool) void {
        const dr = self.drawAmt; // 0..1 draw amount
        const rest = self.rest;
        // Spine: a slight forward set at the ready, curling on death, arching back when stunned.
        const spineX = 4.0 + 22.0 * dk - 20.0 * stun;
        setLocal(wx, SPINE, rest, rx(spineX * 0.5));
        setLocal(wx, CHEST, rest, mul(rx(spineX * 0.5), ry(-8.0 * dr))); // torso blades slightly as it draws
        setLocal(wx, NECK, rest, rx(3.0 + 12.0 * dk - 8.0 * stun));
        // Head: sights down the arrow toward the target at the ready; hangs on death.
        setLocal(wx, SKULL, rest, mul(rx(6.0 + 20.0 * dk - 30.0 * stun), ry(6.0 * dr)));

        // Legs buckle under the crumple ONLY when dead; alive, hero.legChain (pose()) owns them.
        if (dead) {
            setLocal(wx, HIPL, rest, mul(rx(-60.0 * dk), rz(-3.0)));
            setLocal(wx, KNEEL, rest, rx(8.0 + 100.0 * dk));
            setLocal(wx, ANKL, rest, ry(7.0));
            setLocal(wx, HIPR, rest, mul(rx(-52.0 * dk), rz(3.0)));
            setLocal(wx, KNEER, rest, rx(8.0 + 92.0 * dk));
            setLocal(wx, ANKR, rest, ry(-7.0));
        }

        // ── the ARMS — the archer read ──
        // Right arm = the BOW arm: extends toward the target (shoulder raised forward to
        // horizontal), elbow near-straight, so the bow is held out front. Barely moves.
        const armStun = -70.0 * stun; // arms fly up when hit
        const bowShFwd = -86.0 + armStun;
        setLocal(wx, SHR, rest, mul(rx(bowShFwd - 30.0 * dk), rz(-9.0)));
        setLocal(wx, ELR, rest, rx(-(10.0 + 4.0 * dr)));
        setLocal(wx, WRR, rest, rz(-6.0));
        // The bow arm tilts ~-100° forward to aim; rx(100) stands the bow VERTICAL, and ry(180)
        // faces it the right way — string toward the archer, limbs bowing out to the target.
        setLocal(wx, BOW, rest, mul(ry(180.0), rx(100.0)));

        // Left arm = the DRAW arm: from a low ready it RAISES and the elbow FOLDS to bring the
        // hand back to the face anchor as `draw` → 1 (the pull), the elbow riding high. On the
        // loose it snaps forward (draw → 0). A high draw elbow is the signature archer shape.
        const drawShFwd = mathx.lerpF(-30.0, -80.0, dr) + armStun;
        const drawElbow = mathx.lerpF(20.0, 148.0, dr); // fold to full draw
        const elbowHigh = 22.0 * dr; // the drawing elbow rides up
        setLocal(wx, SHL, rest, mul3(rx(drawShFwd - 30.0 * dk), ry(-18.0 * dr), rz(9.0 + elbowHigh)));
        setLocal(wx, ELL, rest, rx(-drawElbow));
        setLocal(wx, WRL, rest, rl.math.matrixIdentity());
    }

    pub fn draw(self: *const Archer, model: *const Model) void {
        model.draw(&self.xf);
    }
};

// ── a group of archers (perched in the ruins, waking as the hero advances) ────────────────
const COUNT = 2;
const Home = struct { x: f32, z: f32, yaw: f32, scale: f32, seed: f32 };
const homes = [COUNT]Home{
    // Set among the columns/graves off the avenue, flanking the toad knot's ground.
    .{ .x = -16.0, .z = -22.0, .yaw = mathx.radians(60), .scale = 1.0, .seed = 0.2 },
    .{ .x = 17.5, .z = -34.0, .yaw = mathx.radians(210), .scale = 1.04, .seed = 0.7 },
};

pub const Line = struct {
    model: Model,
    archers: [COUNT]Archer = undefined,

    pub fn init(shader: rl.Shader) Line {
        var l = Line{ .model = Model.init(shader) };
        for (homes, 0..) |h, i| l.archers[i] = Archer.spawn(mathx.ground(h.x, h.z), h.yaw, h.scale, h.seed);
        return l;
    }
    pub fn setShader(self: *Line, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Line, scene: ?*gfx.Scene) void {
        for (&self.archers) |*a| {
            if (!a.alive()) continue;
            if (scene) |sc| sc.setFlash(0.85 * a.flashFrac());
            a.draw(&self.model);
        }
        if (scene) |sc| sc.setFlash(0);
    }
    pub fn anyDied(self: *const Line) bool {
        for (&self.archers) |*a| {
            if (a.justDied) return true;
        }
        return false;
    }
    pub fn totalHits(self: *const Line) u32 {
        var n: u32 = 0;
        for (&self.archers) |*a| n += a.hits;
        return n;
    }
    pub fn aliveCount(self: *const Line) u32 {
        var n: u32 = 0;
        for (&self.archers) |*a| {
            if (a.alive()) n += 1;
        }
        return n;
    }
};

// ── bone meshes (authored at the joint origin, hero-local axes; lengths in units of H) ────
fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = ribcageMesh();
    mesh[NECK] = neckMesh();
    mesh[SKULL] = skullMesh();
    mesh[HIPL] = femurMesh();
    mesh[KNEEL] = tibiaMesh();
    mesh[ANKL] = footMesh(1.0);
    mesh[HIPR] = femurMesh();
    mesh[KNEER] = tibiaMesh();
    mesh[ANKR] = footMesh(-1.0);
    mesh[SHL] = humerusMesh();
    mesh[ELL] = forearmMesh();
    mesh[WRL] = handMesh();
    mesh[SHR] = humerusMesh();
    mesh[ELR] = forearmMesh();
    mesh[WRR] = handMesh();
    mesh[BOW] = bowMesh();
    return mesh;
}

// A bone: a slightly-tapered shaft with a fatter knob at each joint end (low-poly articular
// heads). `a`→`b` in the joint-local frame; `r` the shaft radius (units of H already applied).
fn bone(b: *Builder, a: rl.Vector3, e: rl.Vector3, r: f32, col: rl.Color) void {
    b.addCylinder(a, e, r, r * 0.9, 7, col);
    b.addCylinder(v3(a.x, a.y + r * 0.6, a.z), v3(a.x, a.y - r * 0.6, a.z), r * 1.7, r * 1.7, 7, BONE_LT); // head knob at a
    b.addCylinder(v3(e.x, e.y + r * 0.6, e.z), v3(e.x, e.y - r * 0.6, e.z), r * 1.6, r * 1.6, 7, BONE_LT); // head knob at e
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    // A bony pelvic girdle: a central sacrum block + two flared iliac blades.
    b.addCube(v3(0, -0.01 * H, -0.01 * H), v3(0.10 * H, 0.11 * H, 0.10 * H), BONE_DK); // sacrum
    b.addBox(v3(0.085 * H, 0.01 * H, 0.02 * H), v3(0.055 * H, 0.02 * H, 0.01 * H), v3(0.01 * H, 0.075 * H, 0.0), v3(0, 0, 0.06 * H), BONE); // left ilium blade
    b.addBox(v3(-0.085 * H, 0.01 * H, 0.02 * H), v3(0.055 * H, 0.02 * H, 0.01 * H), v3(-0.01 * H, 0.075 * H, 0.0), v3(0, 0, 0.06 * H), BONE); // right ilium blade
    b.addCube(v3(0, -0.06 * H, 0.01 * H), v3(0.14 * H, 0.05 * H, 0.09 * H), BONE_DK); // pubic mass
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    // A short stack of lumbar vertebrae from ROOT toward CHEST (~0.53→0.76 H, span ~0.12 H local).
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const y = 0.01 * H + @as(f32, @floatFromInt(i)) * 0.032 * H;
        b.addCube(v3(0, y, -0.02 * H), v3(0.055 * H, 0.02 * H, 0.05 * H), if (@mod(i, 2) == 0) BONE else BONE_DK); // vertebral body
        b.addCube(v3(0, y, -0.05 * H), v3(0.03 * H, 0.014 * H, 0.03 * H), BONE_DK); // spinous process, poking back
    }
    return b.toMesh();
}

fn ribcageMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    // Thorax joint sits ~0.76 H; author the cage around it. Spine column up the back, a sternum
    // plate down the front, and paired ribs sweeping from the spine forward-and-down to the
    // sternum. Each rib = two straight segments (back→side, side→front) — a bent bar that reads
    // as a wrapping rib at game distance. The cage narrows top→bottom (chest tapers to waist).
    b.addCube(v3(0, 0.02 * H, -0.07 * H), v3(0.05 * H, 0.16 * H, 0.05 * H), BONE_DK); // thoracic spine
    b.addCube(v3(0, 0.03 * H, 0.075 * H), v3(0.04 * H, 0.13 * H, 0.015 * H), BONE_LT); // sternum plate
    // shoulder girdle: clavicles + scapular nubs so the arms hang off real bone
    b.addBox(v3(0.07 * H, 0.10 * H, 0.02 * H), v3(0.075 * H, 0.012 * H, 0.0), v3(0, 0.012 * H, 0), v3(0, 0, 0.02 * H), BONE); // L clavicle
    b.addBox(v3(-0.07 * H, 0.10 * H, 0.02 * H), v3(0.075 * H, 0.012 * H, 0.0), v3(0, 0.012 * H, 0), v3(0, 0, 0.02 * H), BONE); // R clavicle
    const levels = [_]f32{ 0.085, 0.045, 0.005, -0.035 }; // rib heights (H) off the joint
    const halfw = [_]f32{ 0.115, 0.125, 0.118, 0.095 }; // cage half-width at each level
    const fwd = [_]f32{ 0.085, 0.095, 0.088, 0.070 }; // sternum reach forward at each level
    for (0..levels.len) |li| {
        const y = levels[li] * H;
        const w = halfw[li] * H;
        const fz = fwd[li] * H;
        const rr = 0.011 * H;
        const col = if (@mod(li, 2) == 0) BONE else BONE_LT;
        for ([_]f32{ 1, -1 }) |sgn| {
            const spinePt = v3(0, y, -0.06 * H); // off the spine at the back
            const sidePt = v3(sgn * w, y - 0.006 * H, 0.01 * H); // widest point at the flank
            const frontPt = v3(sgn * 0.02 * H, y - 0.014 * H, fz); // meeting the sternum out front
            b.addCylinder(spinePt, sidePt, rr, rr, 5, col); // back → side
            b.addCylinder(sidePt, frontPt, rr, rr * 0.85, 5, col); // side → sternum
        }
    }
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    b.addCylinder(v3(0, 0, 0), v3(0, 0.070 * H, 0), 0.026 * H, 0.024 * H, 7, BONE_DK); // cervical column
    b.addCube(v3(0, 0.024 * H, 0), v3(0.03 * H, 0.02 * H, 0.03 * H), BONE); // a vertebra ring
    return b.toMesh();
}

fn skullMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    // Head joint ~0.885 H (chin line); cranium lands ~1.0 H. Cranium dome + brow, sunken eye
    // sockets + nasal cavity (near-black hollows), cheekbones, and a toothed upper + lower jaw.
    b.addCylinder(v3(0, 0.055 * H, -0.01 * H), v3(0, 0.11 * H, -0.01 * H), 0.075 * H, 0.052 * H, 9, BONE); // cranium crown
    b.addCube(v3(0, 0.055 * H, -0.005 * H), v3(0.135 * H, 0.075 * H, 0.135 * H), BONE); // cranium box
    b.addCube(v3(0, 0.072 * H, 0.058 * H), v3(0.12 * H, 0.028 * H, 0.03 * H), BONE_LT); // brow ridge
    // eye sockets (deep, dark)
    b.addCube(v3(0.042 * H, 0.05 * H, 0.062 * H), v3(0.05 * H, 0.045 * H, 0.03 * H), SOCKET);
    b.addCube(v3(-0.042 * H, 0.05 * H, 0.062 * H), v3(0.05 * H, 0.045 * H, 0.03 * H), SOCKET);
    b.addCube(v3(0, 0.03 * H, 0.07 * H), v3(0.022 * H, 0.04 * H, 0.025 * H), SOCKET); // nasal cavity
    b.addCube(v3(0.055 * H, 0.03 * H, 0.05 * H), v3(0.03 * H, 0.03 * H, 0.04 * H), BONE_DK); // L cheekbone
    b.addCube(v3(-0.055 * H, 0.03 * H, 0.05 * H), v3(0.03 * H, 0.03 * H, 0.04 * H), BONE_DK); // R cheekbone
    // upper jaw + a ragged tooth row, then the mandible
    b.addCube(v3(0, 0.012 * H, 0.055 * H), v3(0.085 * H, 0.03 * H, 0.055 * H), BONE); // maxilla
    b.addCube(v3(0, -0.012 * H, 0.05 * H), v3(0.09 * H, 0.028 * H, 0.06 * H), BONE_DK); // mandible
    var trng = mathx.Rng.init(4801);
    var i: i32 = -3;
    while (i <= 3) : (i += 1) {
        if (trng.float() < 0.12) continue; // a missing tooth
        const tx = @as(f32, @floatFromInt(i)) * 0.02 * H;
        b.addCube(v3(tx, -0.003 * H, 0.081 * H), v3(0.011 * H, 0.02 * H * trng.range(0.7, 1.2), 0.01 * H), TEETH);
    }
    return b.toMesh();
}

fn femurMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    bone(&b, v3(0, 0, 0), v3(0, -SEG_THIGH * H, 0), 0.026 * H, BONE);
    return b.toMesh();
}

fn tibiaMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    bone(&b, v3(0, 0, 0), v3(0, -SEG_SHANK * H, 0), 0.022 * H, BONE);
    b.addCylinder(v3(0.014 * H, -0.01 * H, 0.006 * H), v3(0.006 * H, -SEG_SHANK * H * 0.8, 0.004 * H), 0.008 * H, 0.006 * H, 5, BONE_DK); // fibula alongside
    return b.toMesh();
}

fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    const ay = 0.039 * H;
    b.addCube(v3(0, -ay + 0.02 * H, 0.05 * H), v3(0.05 * H, 0.03 * H, 0.13 * H), BONE_DK); // metatarsals / foot plate
    // three toe bones fanning forward
    for ([_]f32{ -1, 0, 1 }) |t| {
        b.addCylinder(v3(t * 0.018 * H * side, -ay + 0.015 * H, 0.10 * H), v3(t * 0.026 * H * side, -ay + 0.012 * H, 0.15 * H), 0.008 * H, 0.005 * H, 4, BONE);
    }
    b.addCube(v3(0, -ay + 0.03 * H, -0.02 * H), v3(0.035 * H, 0.04 * H, 0.04 * H), BONE); // heel / calcaneus
    return b.toMesh();
}

fn humerusMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    bone(&b, v3(0, 0, 0), v3(0, -SEG_UPARM * H, 0), 0.022 * H, BONE);
    return b.toMesh();
}

fn forearmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    // Radius + ulna: two thin parallel bones for the skeletal read.
    bone(&b, v3(0.008 * H, 0, 0), v3(0.008 * H, -SEG_FOREARM * H, 0), 0.014 * H, BONE);
    b.addCylinder(v3(-0.012 * H, -0.004 * H, 0.004 * H), v3(-0.006 * H, -SEG_FOREARM * H, 0.002 * H), 0.012 * H, 0.009 * H, 6, BONE_DK);
    return b.toMesh();
}

fn handMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    b.addCube(v3(0, -0.03 * H, 0.005 * H), v3(0.035 * H, 0.05 * H, 0.03 * H), BONE_DK); // metacarpals / palm
    // four skeletal finger bones curling forward (a bony claw)
    for ([_]f32{ -1.5, -0.5, 0.5, 1.5 }) |fgr| {
        b.addCylinder(v3(fgr * 0.012 * H, -0.055 * H, 0.01 * H), v3(fgr * 0.014 * H, -0.075 * H, 0.03 * H), 0.007 * H, 0.004 * H, 4, BONE);
    }
    return b.toMesh();
}

// The bow, authored in the RIGHT-WRIST frame about the fist — a recurve held vertically, the
// grip at the hand, limbs sweeping up + down, a pale string on the near (target) side. Approx
// the curve with three tapered segments per limb; the string is one thin taut cylinder.
fn bowMesh() rl.Mesh {
    var b = Builder.init();
    const fy = -0.05 * H; // fist centre in the wrist frame (matches the hero's grip anchor)
    const fz = 0.02 * H; // held a touch out front of the palm
    b.setMat(.wood);
    // grip
    b.addCylinder(v3(0, fy + 0.05 * H, fz), v3(0, fy - 0.05 * H, fz), 0.016 * H, 0.016 * H, 6, BOWWOOD_LT);
    // upper limb (grip → mid → recurved tip), then lower limb mirrored
    const uy = [_]f32{ 0.05, 0.20, 0.34 };
    const uz = [_]f32{ 0.0, -0.02, 0.05 }; // sweeps back then recurves forward at the tip
    const ur = [_]f32{ 0.016, 0.012, 0.006 };
    for (0..2) |seg| {
        b.addCylinder(v3(0, fy + uy[seg] * H, fz + uz[seg] * H), v3(0, fy + uy[seg + 1] * H, fz + uz[seg + 1] * H), ur[seg] * H, ur[seg + 1] * H, 5, BOWWOOD);
        b.addCylinder(v3(0, fy - uy[seg] * H, fz + uz[seg] * H), v3(0, fy - uy[seg + 1] * H, fz + uz[seg + 1] * H), ur[seg] * H, ur[seg + 1] * H, 5, BOWWOOD);
    }
    // string: tip to tip, drawn taut on the near side (toward the archer, −z of the limbs' curve)
    b.setMat(.plain);
    const tipY = fy + uy[2] * H;
    const tipZ = fz + uz[2] * H;
    b.addCylinder(v3(0, tipY, tipZ), v3(0, fy - uy[2] * H, tipZ), 0.003 * H, 0.003 * H, 4, STRINGCOL);
    return b.toMesh();
}

// ── an arrow mesh (one shared model, drawn per live/stuck arrow oriented along its velocity) ─
pub fn arrowMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    // Authored along +Z (the flight axis); game.zig orients it to the velocity. ~0.7 m long.
    b.setMat(.wood);
    b.addCylinder(v3(0, 0, -0.35), v3(0, 0, 0.28), 0.008, 0.008, 5, ARROW_SHAFT); // shaft
    b.setMat(.steel);
    b.addCylinder(v3(0, 0, 0.28), v3(0, 0, 0.37), 0.018, 0.001, 5, ARROW_HEAD); // pile / head
    b.setMat(.cloth);
    // fletching: three vanes at the tail
    b.addBox(v3(0, 0.02, -0.30), v3(0.001, 0, 0), v3(0, 0.03, 0), v3(0, 0, 0.05), ARROW_FLETCH);
    b.addBox(v3(0.018, -0.012, -0.30), v3(0.001, 0, 0), v3(0.026, -0.017, 0), v3(0, 0, 0.05), ARROW_FLETCH);
    b.addBox(v3(-0.018, -0.012, -0.30), v3(0.001, 0, 0), v3(-0.026, -0.017, 0), v3(0, 0, 0.05), ARROW_FLETCH);
    return b.toModel(shader);
}

// ── invariants under test (pure logic only) ─────────────────────────────────────────────
test "kite AI: too close backs off, too far closes, in-band shoots when reloaded" {
    try std.testing.expectEqual(Choice.hold_ground, classify(AGGRO_R + 1, true)); // disengaged
    try std.testing.expectEqual(Choice.back_off, classify(RANGE_MIN - 1, true)); // crowded
    try std.testing.expectEqual(Choice.close_in, classify(RANGE_MAX + 1, true)); // too far
    try std.testing.expectEqual(Choice.shoot, classify((RANGE_MIN + RANGE_MAX) * 0.5, true)); // in band, nocked
    try std.testing.expectEqual(Choice.hold_ground, classify((RANGE_MIN + RANGE_MAX) * 0.5, false)); // in band, reloading
}

test "range band is ordered and sits inside aggro" {
    try std.testing.expect(RANGE_MIN < RANGE_MAX and RANGE_MAX < AGGRO_R);
}
