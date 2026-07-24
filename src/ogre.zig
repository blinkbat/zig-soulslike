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

// ── THE ONE-EYED OGRE ───────────────────────────────────────────────────────────────────
// The third foe: a GIANT — roughly twice the hero's height — hunched, humanoid-LEANING but
// misshapen, dragging an enormous knotted club. A sad figure (heavy brow, downcast single
// eye, a slumped weary carriage) that is nonetheless a real threat: HIGH POISE (it shrugs off
// single lights — you must land sustained pressure to stagger it) and a slow, ground-eating
// approach into a big committed OVERHEAD CLUB SLAM. Only the one attack for now (the brief
// promises a tricky array later — the state machine is laid out so more drop in beside it).
//
// FOUNDED ON THE HUMANOID MODEL (owner's rule, see AGENTS.md + archer.zig): it reuses the
// hero's real anthropometry scaffold — the same 18-bone parent hierarchy + FK convention —
// and, crucially, LOCOMOTES ON THE HERO'S NORMATIVE GAIT (heromod.advanceGait + legChain),
// never a bespoke walk. What differs is the SKIN (a hulking mis-proportioned frame: barrel
// chest, long heavy arms, a low small head with ONE eye) and the UPPER body (the club carry +
// the overhead slam ride on top of the shared legs). The weapon slot is repurposed as the
// CLUB. Because the whole rig scales up (SCALE), the stride phase is fed a scale-corrected
// distance so the giant's long legs don't skate (see update()).
//
// Rendering discipline matches hero/frog/archer: procedural Builder meshes drawn with drawMesh
// through one scene-shader material, so it lights + casts shadows like everything else.

// ── palette (pre-gamma dark — the scene shader gammas output, so mid values lift) ──────────
// An ashen, weathered grey-tan hide (a sorrowful stone-giant, warm enough for the golden-hour
// world), a paler scarred belly, near-black hollows, pale bone tusks + nails, and ONE eye that
// glows a dull, tired amber — a lonely lamp, not a fierce glare (the sad read).
const HIDE = rgba(58, 52, 43, 255); // ashen grey-tan hide
const HIDE_DK = rgba(36, 32, 26, 255); // shadowed folds / warts — near-black
const HIDE_LT = rgba(80, 72, 59, 255); // caught-light ridges / knuckles
const BELLY = rgba(72, 65, 52, 255); // paler, scarred underside
const SCAR = rgba(92, 82, 66, 255); // old scar tissue / calloused patches
const EYE = rgba(236, 194, 108, 92); // the single eye — dull tired amber (low alpha = emissive)
const EYE_RIM = rgba(28, 24, 18, 255); // heavy wet socket rim
const PUPIL = rgba(10, 8, 6, 255);
const TUSK = rgba(150, 140, 116, 255); // pale bone tusks + nails, pop against the hide
const TUSK_DK = rgba(112, 104, 84, 255);
const RAG = rgba(46, 40, 33, 255); // a filthy loin-rag (a scrap of pathos, keeps it un-goofy)
const CLUB_WOOD = rgba(40, 30, 20, 255); // dark bog-oak haft
const CLUB_WOOD_LT = rgba(58, 44, 28, 255); // grain highlight
const CLUB_STONE = rgba(52, 50, 47, 255); // lashed-on stone / rusted iron lumps
const CLUB_IRON = rgba(64, 58, 52, 255);

// ── rig: an 18-bone humanoid, the hero's exact joint layout + parenting (the shared model),
// with the weapon slot repurposed as the CLUB, parented to the RIGHT wrist. ────────────────
const N = 18;
const ROOT = 0; // pelvis
const SPINE = 1; // lumbar
const CHEST = 2; // barrel ribcage + shoulder girdle
const NECK = 3;
const SKULL = 4;
const HIPL = 5;
const KNEEL = 6;
const ANKL = 7;
const HIPR = 8;
const KNEER = 9;
const ANKR = 10;
const SHL = 11; // shoulder L (the OFF arm)
const ELL = 12;
const WRL = 13;
const SHR = 14; // shoulder R (the CLUB arm)
const ELR = 15;
const WRR = 16;
const CLUB = 17; // the great club, parented to the right wrist

const parent = [N]i32{ -1, ROOT, SPINE, CHEST, NECK, ROOT, HIPL, KNEEL, ROOT, HIPR, KNEER, CHEST, SHL, ELL, CHEST, SHR, ELR, WRR };

const H: f32 = heromod.H;
// Ogre proportions (fractions of H): the LEGS keep the hero's segment lengths so the shared
// gait reads honestly; the ARMS run long + heavy (an apish drag), the frame wide. Bulk comes
// from the beefy meshes + the hunch (posed), not from warping the leg chain the gait expects.
const SEG_THIGH = 0.245;
const SEG_SHANK = 0.246;
const SEG_UPARM = 0.210; // long, heavy arms — but not so long they knuckle-drag + hide the legs
const SEG_FOREARM = 0.170;

fn restPositions() [N]rl.Vector3 {
    const hx = 0.135; // wide hip half-separation (a broad base)
    const sx = 0.235; // wide, slumped shoulders
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, 0.530, 0);
    r[SPINE] = v3(0, 0.645, 0);
    r[CHEST] = v3(0, 0.775, 0);
    r[NECK] = v3(0, 0.820, 0);
    r[SKULL] = v3(0, 0.885, 0);
    r[HIPL] = v3(hx, 0.530, 0);
    r[KNEEL] = v3(hx, 0.285, 0);
    r[ANKL] = v3(hx, 0.039, 0);
    r[HIPR] = v3(-hx, 0.530, 0);
    r[KNEER] = v3(-hx, 0.285, 0);
    r[ANKR] = v3(-hx, 0.039, 0);
    r[SHL] = v3(sx, 0.800, 0);
    r[ELL] = v3(sx, 0.565, 0);
    r[WRL] = v3(sx, 0.370, 0);
    r[SHR] = v3(-sx, 0.800, 0);
    r[ELR] = v3(-sx, 0.565, 0);
    r[WRR] = v3(-sx, 0.370, 0);
    r[CLUB] = v3(-sx, 0.370, 0); // zero offset from the wrist; club mesh authored in the wrist frame
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
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;

// world(child) = animRot ∘ translate(offset) ∘ world(parent) — the hero's exact convention.
fn setLocal(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    const p: usize = @intCast(parent[i]);
    const off = mathx.subV(rest[i], rest[p]);
    const local = mul(animRot, tr(off.x, off.y, off.z));
    wx[i] = mul(local, wx[p]);
}

// ── scale / locomotion / senses ───────────────────────────────────────────────────────────
pub const SCALE = 2.5; // a towering giant — ~2.2x the hero's stature to the crown
const WALK_SPEED = heromod.WALK_SPEED * 0.72; // a slow, ground-eating lumber (long legs cover it)
const AGGRO_R = 18.0; // it sees you coming from far off (it's huge)
const SLAM_R = 4.0; // starts the overhead slam within this (long club reach)
const TURN_RATE = 2.4; // rad/s — PONDEROUS: a giant is out-turned, so circling it is the counter
const BODY_R = 0.55; // ground footprint (pre-scale) — broad
const HURT_R = 0.72; // hurt-sphere radius the hero's blade tests against (pre-scale) — a big target
// Pelvis walk oscillation — the hero's amplitudes (heavier), scaled with the body at draw.
const A_BOB = 0.030 * H;
const A_SWAY = 0.014 * H;

// ── slam timing (seconds) — a LONG readable wind-up (the tell lands early), a fast crash, and
// a long winded recovery (the punish window a giant's slow attack must give). ───────────────
const WINDUP_DUR = 0.90; // rear the club overhead — the unmistakable tell
const SLAM_DUR = 0.22; // …then FIRE: a fast downward crash
const SLAM_IMPACT_K = 0.72; // fraction into the slam the club meets the ground (impact frame)
const RECOVER_DUR = 1.20; // hunched over the buried club, spent + wide open
const SLAM_CD = 1.3; // beat between slams
const FLASH_DUR = 0.20;
const SHOVE_DECAY = 6.0;

// ── combat vitals (a mini-boss: high poise so single lights won't interrupt it — the brief's
// "higher poise" — a long HP bar, and a stance meter that only breaks under sustained pressure) ─
const HP_MAX = 300.0;
const POISE_MAX = 30.0; // 3 fast hero-lights (poise 10) to flinch once; a lone light is shrugged off
const STANCE_MAX = 90.0; // keep the pressure on to reach the heavy stance-break
pub const SLAM_HIT = combat.Hit{ .dmg = 28, .poise = 44, .stance = 20 }; // a crushing body-blow (heavy); dmg eased down from 34
const DEATH_DUR = 1.7; // a slow, weighty topple — a giant falls hard (and sadly)
const DISS_DUR = 1.1; // dissipation into grace-gold motes (ER-consistent with frog/archer)

// What the hero's OWN attack does back is decided by hero.attackHit(); these constants are the
// blows the OGRE lands. The slam only catches a hero in the FRONTAL crush zone (see tryImpact).
const HERO_REACH = 0.55; // hero footprint added to the slam reach
const SLAM_IMPACT_R = 1.65; // frontal crush reach from the seat (pre-scale — the club is long)
const SLAM_FRONT_DOT = 0.15; // hero must lie within the frontal arc (~±81°) to be crushed
const SLAM_IMPACT_FWD = 1.5; // dust-burst / crush-zone centre, this far ahead of the seat (pre-scale)

// ── posture channel constants (degrees) — the club carry + the slam arc + the sad idle ─────
const HUNCH = 9.0; // base forward stoop — stooped + weary, but still standing TALL (imposing)
const CARRY_SH = -20.0; // club arm hangs forward-and-down (dragging the club)
const CARRY_EL = -20.0; // arms hang fairly straight (long + heavy), not hugged in
const OVER_SH = -182.0; // upper arm thrown straight UP (the club rears overhead, not behind)
const WIND_EL = -42.0; // only a light cock, so the club points HIGH over the head, not back
const SLAM_SH = -42.0; // club crashed forward-and-down into the earth
const SLAM_EL = -6.0; // elbow driven near-straight through the blow
const OFF_SH = -14.0; // off arm rests low
const OFF_EL = -18.0;
const HEAD_DROOP = 20.0; // downcast, sad at rest (+ = looks down)

// ── idle life + attack footwork (a big fella is never a frozen statue) ─────────────────────
// The leg rest-stance constants are the hero's (legChain uses these), re-stated so the idle /
// braced legs line up exactly with the shared walk when it kicks in (no jump at the hand-off).
const HIP_ADDUCT = 2.0;
const FOOT_TOEOUT = 6.0;
const IDLE_KNEE = 4.0;
const IDLE_RATE = 1.5; // rad/s of the slow weight-shift cycle (~4.2 s period — heavy, unhurried)
const BREATHE_RATE = 1.05; // rad/s of the breathing bob
const A_BREATHE = 0.012 * H; // idle breathing rise/fall of the pelvis
const A_IDLE_SWAY = 0.020 * H; // idle lateral weight-sway (rocks foot to foot)
const IDLE_ROLL = 3.2; // deg the torso rolls toward the weighted foot
const STANCE_WIDEN = 9.0; // deg the feet plant wider when bracing for a slam

// ── telegraph FX (a small unlit particle pool — dust, blood, death motes; like the toad's) ──
const FX_MAX = 56;
const DUST = rgba(150, 132, 96, 175); // kicked-up dust (warm tan; unlit, so lift the value)
const BLOOD = rgba(84, 20, 16, 235); // dark ichor spray on a landed blow
const MOTE = rgba(252, 198, 92, 170); // death dissipation — grace-gold motes

const Particle = struct {
    p: rl.Vector3 = mathx.zero3,
    v: rl.Vector3 = mathx.zero3,
    life: f32 = 0,
    max: f32 = 1,
    r0: f32 = 0.05,
    r1: f32 = 0.05,
    col: rl.Color = DUST,
    grav: f32 = 0,
};

// The hero's blade as plain data (the shared foe standard). Re-exported for symmetry.
pub const Blade = foe.Blade;

// idle/approach/windup/slam/recover are the live behaviours; the last three are REACTIONS
// (interrupts) — a light flinch, the heavy stance-break, and death.
const State = enum { idle, approach, windup, slam, recover, stunlight, stunheavy, dead };

// Pure attack decision — a function of range + cooldown, so it's unit-testable without a world.
const Choice = enum { slam, approach, wait, idle };
fn classify(dist: f32, slamReady: bool) Choice {
    if (dist > AGGRO_R) return .idle; // hasn't noticed / has disengaged
    if (dist <= SLAM_R) return if (slamReady) .slam else .wait; // in reach: crush when ready, else loom
    return .approach; // close the gap
}

// The shared ogre meshes + material (built once, like the toad's / archer's).
pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("ogre material");
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

pub const Ogre = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    slamCd: f32 = 0,
    elapsed: f32 = 0,
    slammed: bool = false, // one crush per slam (the impact burst + hero hit are latched)

    // posture channels (degrees) resolved each frame by the state, read by pose().
    clubShoulder: f32 = CARRY_SH,
    clubElbow: f32 = CARRY_EL,
    offShoulder: f32 = OFF_SH,
    offElbow: f32 = OFF_EL,
    bodyLean: f32 = HUNCH,
    headPitch: f32 = HEAD_DROOP,
    legBrace: f32 = 0, // 0 = loose stance, 1 = feet planted + knees loaded (bracing a slam)

    // shared humanoid GAIT STATE (hero.advanceGait drives these; hero.legChain animates the legs)
    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,
    prevPhase: f32 = 0, // for footfall dust on the stride half-cycles

    // combat
    vit: combat.Vitals = combat.Vitals.init(HP_MAX, POISE_MAX, STANCE_MAX),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null, // this frame's blow ON THE HERO (the slam connects), read by game.zig
    heroLatch: bool = false, // one hero-hit per slam
    justDied: bool = false,
    fade: f32 = 0,
    gone: bool = false,

    // telegraph FX
    fx: [FX_MAX]Particle = [_]Particle{.{}} ** FX_MAX,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Ogre {
        var o = Ogre{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * SCALE, .seed = seed };
        o.rest = restPositions();
        o.fxRng = mathx.Rng.init(@as(u64, @intFromFloat(seed * 88883.0)) +% 7);
        o.pose();
        return o;
    }

    // ── foe-contract accessors (heights in world units, so they ride the giant scale) ───────
    pub fn centerWorld(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, 0.60 * H * self.scale, self.pos.z); // chest-ish mass centre
    }
    pub fn hurtRadius(self: *const Ogre) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Ogre) f32 {
        return BODY_R * self.scale;
    }
    pub fn lockPoint(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, 0.62 * H * self.scale, self.pos.z);
    }
    pub fn topWorld(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, 1.02 * H * self.scale, self.pos.z);
    }
    // The head, roughly — for framing the face close-up (the single eye) in --shot.
    pub fn headWorld(self: *const Ogre) rl.Vector3 {
        return v3(self.pos.x, 0.86 * H * self.scale, self.pos.z);
    }
    pub fn alive(self: *const Ogre) bool {
        return !self.gone;
    }
    pub fn staggered(self: *const Ogre) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn dying(self: *const Ogre) bool {
        return self.state == .dead;
    }
    pub fn flashFrac(self: *const Ogre) f32 {
        return mathx.clampF(self.flash / FLASH_DUR, 0, 1);
    }
    // Grounded always (no hops) — collision keeps it out of the hero/world.
    pub fn airborne(self: *const Ogre) bool {
        _ = self;
        return false;
    }

    fn fdir(self: *const Ogre) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Ogre, target: rl.Vector3, dt: f32) void {
        const d = mathx.dirXZ(self.pos, target);
        if (mathx.lenXZ(d) < 1e-3) return;
        self.facing = mathx.approachAngle(self.facing, mathx.headingXZ(d), TURN_RATE * dt);
    }

    // ── per-frame update; returns the blow the ogre landed on the HERO this frame (null if
    // none / it's a corpse). Mirrors the toad: vitals tick, the state machine runs, the shared
    // gait advances, pose() builds the matrices, and the hero's blade is applied LAST (tryHit),
    // so a kill sets justDied for exactly this frame's beat (reset at the top). ───────────────
    pub fn update(self: *Ogre, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            self.updateFx(dt);
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        self.vit.tick(dt);
        self.elapsed += dt;
        self.slamCd = mathx.maxF(0, self.slamCd - dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        self.t += dt;
        self.updateFx(dt);
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;

        // Hit shove — a jolt off a landed blow (a giant barely budges, so it decays fast).
        if (mathx.lenXZ(self.shove) > 0.01) {
            self.pos.x = mathx.clampF(self.pos.x + self.shove.x * dt, -bounds, bounds);
            self.pos.z = mathx.clampF(self.pos.z + self.shove.z * dt, -bounds, bounds);
            self.shove = mathx.scaleV(self.shove, mathx.maxF(0, 1.0 - SHOVE_DECAY * dt));
        }

        const d = mathx.distXZ(self.pos, hero);
        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.setCarry(dt);
                if (self.t >= 0.2) self.decide(d);
            },
            .approach => {
                self.faceToward(hero, dt);
                const f = self.fdir();
                const moved = WALK_SPEED * dt;
                self.pos.x = mathx.clampF(self.pos.x + f.x * moved, -bounds, bounds);
                self.pos.z = mathx.clampF(self.pos.z + f.z * moved, -bounds, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(f); // travels along facing → forward gait
                self.setCarry(dt);
                if (d <= SLAM_R or d > AGGRO_R) self.decide(d);
            },
            .windup => {
                self.faceToward(hero, dt * 0.4); // a little tracking while rearing (committed tell)
                const k = mathx.smoothstep(0, WINDUP_DUR, self.t);
                self.setWindup(k);
                self.emitStrain(dt, k); // gravel trickles as it plants + loads
                if (self.t >= WINDUP_DUR) self.enter(.slam);
            },
            .slam => {
                const k = mathx.smoothstep(0, SLAM_DUR, self.t);
                self.setSlam(k);
                if (self.t >= SLAM_DUR * SLAM_IMPACT_K) {
                    self.tryImpact(hero, SLAM_HIT); // the club meets the earth — FRONT crush zone
                    if (!self.slammed) {
                        self.slammed = true;
                        self.dustBurst(self.impactWorld(), 40, 5.2, 0.42); // a big radial slam of dust
                    }
                }
                if (self.t >= SLAM_DUR) {
                    self.slamCd = SLAM_CD;
                    self.enter(.recover);
                }
            },
            .recover => {
                self.setRecover(mathx.clampF(self.t / RECOVER_DUR, 0, 1));
                if (self.t >= RECOVER_DUR) self.enterIdle();
            },
            .stunlight => if (self.t >= combat.LIGHT_STUN_DUR) self.enterIdle(),
            .stunheavy => if (self.t >= combat.HEAVY_STUN_DUR) self.enterIdle(),
            .dead => {
                if (self.t >= DEATH_DUR) {
                    self.fade = mathx.smoothstep(DEATH_DUR, DEATH_DUR + DISS_DUR, self.t);
                    self.emitDissolve(dt);
                    if (self.t >= DEATH_DUR + DISS_DUR) self.gone = true;
                }
            },
        }

        // Drive the SHARED humanoid gait. The stride phase is fed a SCALE-CORRECTED distance so
        // the giant's long legs cycle at the right cadence for their reach (no skating).
        const gaitSpeed: f32 = if (movedDist > 0) WALK_SPEED else 0;
        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, gaitSpeed, moveYaw, self.facing);
        self.footfalls(); // heavy dust puffs as each foot plants (sells the weight)
        self.pose();
        self.tryHit(blade); // hero's blade AFTER the state machine (like the toad); a kill here
        //   flags justDied for this frame's kill beat, cleared at the top of the next update.
        return self.heroHit;
    }

    fn enter(self: *Ogre, s: State) void {
        self.state = s;
        self.t = 0;
        if (s == .slam) {
            self.slammed = false;
            self.heroLatch = false; // a fresh slam gets one chance to crush the hero
        }
    }
    fn enterIdle(self: *Ogre) void {
        self.state = .idle;
        self.t = 0;
    }
    fn enterStun(self: *Ogre, s: State) void {
        self.state = s; // the interrupt drops any in-progress slam (nothing lands)
        self.t = 0;
        self.slammed = false;
    }
    fn enterDeath(self: *Ogre) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    // Pick the next action from range + cooldown. In reach + ready → the overhead slam; in reach
    // but cooling → loom (a short idle beat, menacing); too far → close in; disengaged → drift home.
    fn decide(self: *Ogre, dist: f32) void {
        switch (classify(dist, self.slamCd <= 0)) {
            .slam => self.enter(.windup),
            .approach => self.enter(.approach),
            .wait => self.enterIdle(),
            .idle => {
                if (mathx.distXZ(self.pos, self.home) > 3.0) {
                    self.enter(.approach); // wandered — trudge back toward home (faceToward handles it)
                } else self.enterIdle();
            },
        }
    }

    // ── the hero's blade lands on the ogre (the SHARED foe.strike behaviour) ────────────────
    fn tryHit(self: *Ogre, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), blade) orelse return;
        self.hits += 1;
        self.flash = FLASH_DUR;
        const heavyBlow = blade.hit.stance > 0;
        self.bloodBurst(s.contact, s.dir, if (heavyBlow) 16 else 10, if (heavyBlow) 2.8 else 2.0);
        // A giant barely gives — a much smaller shove than the toad's, so hits read as glancing off bulk.
        self.shove = mathx.scaleV(s.dir, if (heavyBlow) 0.7 else 0.4);
        switch (s.reaction) {
            .death => {
                self.bloodBurst(s.contact, s.dir, 14, 2.4);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {}, // shrugged off (its high poise) — the slam windup rolls on
        }
    }

    // The slam CRUSH: like the toad's lunge impact — FRONT-only. The hero must be inside the
    // club's reach AND within the frontal arc; a hero beside or behind the giant is clear.
    fn tryImpact(self: *Ogre, hero: rl.Vector3, h: combat.Hit) void {
        if (self.heroLatch) return;
        const d = mathx.distXZ(self.pos, hero);
        if (d > SLAM_IMPACT_R * self.scale + HERO_REACH) return;
        const to = mathx.dirXZ(self.pos, hero);
        const fwd = self.fdir();
        const front = to.x * fwd.x + to.z * fwd.z;
        if (d > 0.5 and front < SLAM_FRONT_DOT) return; // off to the side / behind the crush
        self.heroHit = h;
        self.heroLatch = true;
    }

    // Debug hooks for the --shot harness (force a pose in isolation).
    pub fn debugSlam(self: *Ogre) void {
        self.enter(.windup);
    }
    pub fn debugStagger(self: *Ogre, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Ogre) void {
        self.enterDeath();
    }

    // ── posture resolvers (set the channel fields for the current beat) ─────────────────────
    fn setCarry(self: *Ogre, dt: f32) void {
        // Ease everything toward the weary carry; slow breathing + a heavy weight-sway ride on
        // top so it's ALIVE at rest — the club rocks, the head lolls with the shifting weight.
        const e = dt * 6.0;
        const breathe = mathx.sinf(self.elapsed * BREATHE_RATE + self.seed * 6.28);
        const rock = mathx.sinf(self.elapsed * IDLE_RATE + self.seed * 6.28); // the weight-shift phase
        self.clubShoulder = mathx.approach(self.clubShoulder, CARRY_SH + 3.0 * rock, e); // the heavy club swings
        self.clubElbow = mathx.approach(self.clubElbow, CARRY_EL + 2.5 * breathe, e);
        self.offShoulder = mathx.approach(self.offShoulder, OFF_SH - 2.5 * rock, e);
        self.offElbow = mathx.approach(self.offElbow, OFF_EL, e);
        self.bodyLean = mathx.approach(self.bodyLean, HUNCH + 1.5 * breathe, e);
        self.headPitch = mathx.approach(self.headPitch, HEAD_DROOP + 2.0 * breathe + 2.5 * rock, e); // head lolls
        self.legBrace = mathx.approach(self.legBrace, 0, e);
    }
    fn setWindup(self: *Ogre, k: f32) void {
        // Rear the club overhead, arch back, PLANT the feet + load the knees — the tell.
        self.clubShoulder = lerpF(CARRY_SH, OVER_SH, k);
        self.clubElbow = lerpF(CARRY_EL, WIND_EL, k);
        self.offShoulder = lerpF(OFF_SH, -74.0, k); // off arm flings out for balance
        self.offElbow = lerpF(OFF_EL, -44.0, k);
        self.bodyLean = lerpF(HUNCH, -24.0, k); // arch back
        self.headPitch = lerpF(HEAD_DROOP, -18.0, k); // eye lifts to the target
        self.legBrace = lerpF(0, 0.55, k); // set the feet + sink into the load
    }
    fn setSlam(self: *Ogre, k: f32) void {
        // FIRE: the club whips down through a chop arc, the whole body driving hard forward.
        self.clubShoulder = lerpF(OVER_SH, SLAM_SH, k);
        self.clubElbow = lerpF(WIND_EL, SLAM_EL, k);
        self.offShoulder = lerpF(-74.0, 8.0, k);
        self.offElbow = lerpF(-44.0, -22.0, k);
        self.bodyLean = lerpF(-24.0, 44.0, k); // whip forward, over the blow
        self.headPitch = lerpF(-18.0, 24.0, k);
        self.legBrace = lerpF(0.55, 0.72, k); // drive off the deeply-bent legs
    }
    fn setRecover(self: *Ogre, u: f32) void {
        // Spent + doubled over the buried club for most of it, gathering upright only at the end
        // (a big, honest, wide-open punish window). Heaving breaths sell the exhaustion.
        const spent = 1.0 - mathx.smoothstep(0.7, 1.0, u);
        const heave = 3.0 * mathx.sinf(self.elapsed * 7.0) * spent;
        self.clubShoulder = lerpF(CARRY_SH, SLAM_SH, spent); // leaning on the planted club
        self.clubElbow = lerpF(CARRY_EL, SLAM_EL, spent);
        self.offShoulder = lerpF(OFF_SH, -8.0, spent);
        self.offElbow = lerpF(OFF_EL, -34.0, spent);
        self.bodyLean = lerpF(HUNCH, 46.0, spent);
        self.headPitch = lerpF(HEAD_DROOP, 34.0 + heave, spent);
        self.legBrace = lerpF(0, 0.85, spent); // splayed + buckled, bearing weight on the club
    }

    fn stunAmount(self: *const Ogre) f32 {
        if (self.state == .stunlight) {
            const u = mathx.clampF(self.t / combat.LIGHT_STUN_DUR, 0, 1);
            return mathx.sinf(u * std.math.pi);
        } else if (self.state == .stunheavy) {
            const u = mathx.clampF(self.t / combat.HEAVY_STUN_DUR, 0, 1);
            return mathx.smoothstep(0, 0.12, u) * (1.0 - mathx.smoothstep(0.78, 1.0, u));
        }
        return 0;
    }

    // ── pose: build the 18 bone matrices for this frame ─────────────────────────────────────
    pub fn pose(self: *Ogre) void {
        const fs = self.scale * (1.0 - 0.55 * self.fade);
        const sink = -0.95 * self.scale * self.fade; // the corpse sinks as it dissipates
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.55, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();
        const light = self.state == .stunlight;
        const heavy = self.state == .stunheavy;
        const lstun: f32 = if (light) stun else 0;
        const hstun: f32 = if (heavy) stun else 0;

        // Shared humanoid walk bob + weight-sway on the pelvis (quieting on collapse).
        const m = self.moving * (1.0 - dk);
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const sway = A_SWAY * mathx.sinf(twoPi * self.phase) * m +
            A_SWAY * self.latB * mathx.cosf(twoPi * self.phase) * m;

        // Idle LIFE (fades out as the walk takes over): a slow breathing bob + a heavy weight-
        // shift that rocks the pelvis foot to foot and rolls the torso — so it's never a statue.
        const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk);
        const wshift = mathx.sinf(self.elapsed * IDLE_RATE + self.seed * 6.28); // −1..1 weight phase
        const idleBob = A_BREATHE * mathx.sinf(self.elapsed * BREATHE_RATE + self.seed * 3.0) * idleAmt;
        const idleSway = A_IDLE_SWAY * wshift * idleAmt;

        var wx: [N]rl.Matrix = undefined;
        // Body pitch: base hunch/attack lean, a huge RECOIL back on a light flinch, a heavy
        // forward SAG on a stance-break, and a full topple forward on death.
        const leanX = self.bodyLean * (1.0 - dk) - 40.0 * lstun + 34.0 * hstun + 84.0 * dk;
        const rollZ = 16.0 * dk + 9.0 * hstun + IDLE_ROLL * wshift * idleAmt; // keels on death/stagger; rocks at idle
        const drop = -0.24 * H * hstun; // pelvis sinks on the heavy stagger (toward a knee)
        const collapse = lerpF(hipY, 0.32 * H, dk);
        const pelvY = (if (dead) collapse else hipY + bob + idleBob + drop) + sink;
        // The pelvis HEIGHT (and sway) must scale by `fs` too: the leg-offset children ride
        // through scaleM, so the pelvis-joint world height has to scale in lockstep or the legs
        // sink underground at SCALE≠1 (the hero/archer never hit this — they're ~1×). The world
        // placement tr(pos) stays unscaled. scaleM FIRST → the giant scales about its own pelvis.
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul(rz(rollZ), rx(leanX)),
            mul(tr((sway + idleSway) * fs, pelvY * fs, 0), ry(facingDeg)),
            tr(self.pos.x, 0, self.pos.z),
        ));

        // Legs. WALKING → the SHARED hero gait (alternating, independent — the owner's humanoid
        // rule). Otherwise (idle / mid-attack) → an independent weight-SHIFT (the free leg's knee
        // softens as weight rocks off it) plus a braced stance when loading a slam — so the legs
        // are never two frozen pillars. DEAD → the crumple in poseUpper owns them.
        if (!dead) {
            if (self.moving > 0.25) {
                heromod.legChain(&wx, self.rest, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, ANKL);
                heromod.legChain(&wx, self.rest, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, ANKR);
            } else {
                const leftFree = mathx.clampF(-wshift, 0, 1) * idleAmt; // left leg relaxes when weight rocks right
                const rightFree = mathx.clampF(wshift, 0, 1) * idleAmt;
                self.legPose(&wx, 1.0, leftFree, self.legBrace, HIPL, KNEEL, ANKL);
                self.legPose(&wx, -1.0, rightFree, self.legBrace, HIPR, KNEER, ANKR);
            }
        }
        self.poseUpper(&wx, dk, lstun, hstun, dead);
        self.xf = wx;
    }

    // One leg posed for the standing beats (idle / mid-attack), NOT the walk (that's legChain).
    // `free` 0→1 = how relaxed/unweighted this leg is (its knee softens + the heel eases up);
    // `brace` 0→1 = the slam load (BOTH legs sink + plant wider). Matches legChain's rest stance
    // constants (HIP_ADDUCT/FOOT_TOEOUT/IDLE_KNEE) so the hand-off to the walk doesn't pop.
    fn legPose(self: *const Ogre, wx: *[N]rl.Matrix, side: f32, free: f32, brace: f32, hip: usize, knee: usize, ank: usize) void {
        const hipFlex = 8.0 * brace + 5.0 * free;
        const kneeFlex = IDLE_KNEE + 32.0 * brace + 18.0 * free;
        const splay = STANCE_WIDEN * brace; // feet plant wider under the load
        setLocal(wx, hip, self.rest, mul(rx(-hipFlex), rz(-side * HIP_ADDUCT + side * splay)));
        setLocal(wx, knee, self.rest, rx(kneeFlex));
        setLocal(wx, ank, self.rest, mul(rx(hipFlex * 0.5 - 8.0 * free), ry(side * FOOT_TOEOUT))); // free heel eases up
    }

    // Spine, the small low head, the two arms + the club, and (only when DEAD, or a HEAVY sag)
    // the buckling legs. Alive, hero.legChain owns the legs; this lays the ogre body on top.
    fn poseUpper(self: *Ogre, wx: *[N]rl.Matrix, dk: f32, lstun: f32, hstun: f32, dead: bool) void {
        const rest = self.rest;
        // Curl the spine into the hunch; the stance-break folds it further, a flinch throws it back.
        const spineFlex = 6.0 + 26.0 * dk + 18.0 * hstun - 22.0 * lstun;
        setLocal(wx, SPINE, rest, rx(spineFlex * 0.5));
        setLocal(wx, CHEST, rest, rx(spineFlex * 0.4));
        // Head: hangs low + sad, sighting the target only on a windup; lolls on death/stagger.
        setLocal(wx, NECK, rest, rx(self.headPitch * 0.35 + 8.0 * dk));
        setLocal(wx, SKULL, rest, rx(self.headPitch * 0.6 + 14.0 * dk + 16.0 * hstun - 26.0 * lstun));

        // Legs buckle under a full collapse (death) or a heavy stance-break (drops toward a knee).
        const buckle = mathx.maxF(dk, 0.7 * hstun);
        if (dead or hstun > 0.05) {
            setLocal(wx, HIPL, rest, mul(rx(-58.0 * buckle), rz(-4.0)));
            setLocal(wx, KNEEL, rest, rx(6.0 + 104.0 * buckle));
            setLocal(wx, ANKL, rest, ry(6.0));
            setLocal(wx, HIPR, rest, mul(rx(-44.0 * buckle), rz(4.0)));
            setLocal(wx, KNEER, rest, rx(6.0 + 88.0 * buckle));
            setLocal(wx, ANKR, rest, ry(-6.0));
        }

        // ── the ARMS ──
        // Off arm (left): rests low, flings out for balance on the windup, thrown up on a flinch.
        const armFly = -66.0 * lstun;
        setLocal(wx, SHL, rest, mul(rx(self.offShoulder + armFly * 0.6 - 18.0 * dk), rz(14.0)));
        setLocal(wx, ELL, rest, rx(self.offElbow));
        setLocal(wx, WRL, rest, rl.math.matrixIdentity());
        // Club arm (right): the whole slam arc rides this shoulder + elbow; the flinch flings it up.
        setLocal(wx, SHR, rest, mul(rx(self.clubShoulder + armFly - 22.0 * dk), rz(-14.0)));
        setLocal(wx, ELR, rest, rx(self.clubElbow));
        setLocal(wx, WRR, rest, rl.math.matrixIdentity());
        // The club rides the wrist frame; a slight tilt so the head hangs a touch off the arm line.
        setLocal(wx, CLUB, rest, rx(8.0));
    }

    // ── telegraph FX (emit / integrate / draw) ──────────────────────────────────────────────
    fn impactWorld(self: *const Ogre) rl.Vector3 {
        const d = self.fdir();
        return v3(self.pos.x + d.x * SLAM_IMPACT_FWD * self.scale, 0.05, self.pos.z + d.z * SLAM_IMPACT_FWD * self.scale);
    }
    fn emit(self: *Ogre, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        self.fx[self.fxHead] = .{ .p = p, .v = vel, .life = life, .max = life, .r0 = r0, .r1 = r1, .col = col, .grav = grav };
        self.fxHead = (self.fxHead + 1) % FX_MAX;
    }
    fn updateFx(self: *Ogre, dt: f32) void {
        for (&self.fx) |*q| {
            if (q.life <= 0) continue;
            q.life -= dt;
            q.p.x += q.v.x * dt;
            q.p.y += q.v.y * dt;
            q.p.z += q.v.z * dt;
            q.v.y -= q.grav * dt;
            if (q.p.y < 0) q.p.y = 0;
        }
    }
    // A radial fan of dust from `c` (the slam crush; scaled up for the giant).
    fn dustBurst(self: *Ogre, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(0.5, 1.0) * spd * self.scale;
            const vel = v3(mathx.cosf(a) * s, self.fxRng.range(0.8, 3.0), mathx.sinf(a) * s);
            self.emit(v3(c.x, 0.06, c.z), vel, self.fxRng.range(0.4, 0.7), self.fxRng.range(0.08, 0.16) * self.scale, big * self.fxRng.range(0.8, 1.3) * self.scale, DUST, 4.5);
        }
    }
    // Windup STRAIN trickle: gravel + dust dug up around the feet as it plants and loads.
    fn emitStrain(self: *Ogre, dt: f32, k: f32) void {
        self.fxAccum += (6.0 + 22.0 * k) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.3, 0.9) * self.scale;
            const bp = v3(self.pos.x + mathx.cosf(a) * rr, 0.05, self.pos.z + mathx.sinf(a) * rr);
            self.emit(bp, v3(self.fxRng.signed() * 0.3, self.fxRng.range(0.3, 1.0), self.fxRng.signed() * 0.3), self.fxRng.range(0.3, 0.5), self.fxRng.range(0.05, 0.11) * self.scale, self.fxRng.range(0.1, 0.18) * self.scale, DUST, 3.5);
        }
    }
    // Heavy footfall dust: a puff under the planting foot as the stride phase crosses 0.0 / 0.5.
    fn footfalls(self: *Ogre) void {
        if (self.moving < 0.4) {
            self.prevPhase = self.phase;
            return;
        }
        const crossed = (self.prevPhase < 0.5 and self.phase >= 0.5) or (self.phase < self.prevPhase); // 0.5 or the wrap past 0.0
        if (crossed) {
            const side: f32 = if (self.phase < 0.5) 1.0 else -1.0; // which foot just landed
            const f = self.fdir();
            const rr = 0.13 * H * self.scale;
            const foot = v3(self.pos.x - f.z * side * rr, 0.05, self.pos.z + f.x * side * rr);
            self.dustBurst(foot, 6, 1.4, 0.14);
        }
        self.prevPhase = self.phase;
    }
    // Dark ichor flung from the contact point along the blade's sweep.
    fn bloodBurst(self: *Ogre, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.4, 1.0) * spd;
            const vel = v3(
                dir.x * sp + mathx.cosf(a) * self.fxRng.range(0.2, 1.0),
                self.fxRng.range(0.8, 2.8),
                dir.z * sp + mathx.sinf(a) * self.fxRng.range(0.2, 1.0),
            );
            self.emit(at, vel, self.fxRng.range(0.3, 0.55), self.fxRng.range(0.04, 0.08) * self.scale, 0.01, BLOOD, 7.5);
        }
    }
    // Death dissipation: grace-gold motes rising off the sinking corpse (ER-consistent).
    fn emitDissolve(self: *Ogre, dt: f32) void {
        self.fxAccum += 70.0 * (1.0 - 0.6 * self.fade) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.1, 1.0) * self.scale * (1.0 - 0.6 * self.fade);
            const p = v3(self.pos.x + mathx.cosf(a) * rr, self.fxRng.range(0.05, 0.7) * self.scale, self.pos.z + mathx.sinf(a) * rr);
            if (self.fxRng.float() < 0.75) {
                self.emit(p, v3(self.fxRng.signed() * 0.3, self.fxRng.range(0.5, 1.5), self.fxRng.signed() * 0.3), self.fxRng.range(0.6, 1.1), self.fxRng.range(0.04, 0.09) * self.scale, 0.004, MOTE, -0.7);
            } else {
                self.emit(p, v3(self.fxRng.signed() * 0.4, self.fxRng.range(0.1, 0.5), self.fxRng.signed() * 0.4), self.fxRng.range(0.35, 0.7), self.fxRng.range(0.06, 0.13) * self.scale, 0.012, DUST, 2.0);
            }
        }
    }
    pub fn drawFx(self: *const Ogre) void {
        for (&self.fx) |*q| {
            if (q.life <= 0) continue;
            const frac = mathx.clampF(q.life / q.max, 0, 1);
            const rad = lerpF(q.r1, q.r0, frac);
            const a = mathx.u8f(@as(f32, @floatFromInt(q.col.a)) * frac);
            rl.drawSphereEx(q.p, rad, 6, 8, mathx.withAlpha(q.col, a));
        }
    }

    pub fn draw(self: *const Ogre, model: *const Model) void {
        model.draw(&self.xf);
    }
};

// ── a lone ogre (a "Grief" — one sorrowful giant haunting the deep ruins). The Group shell
// mirrors the Knot/Line so game.zig iterates it generically; COUNT stays 1 for now (bump it
// and add homes to field more). ────────────────────────────────────────────────────────────
const COUNT = 1;
const Home = struct { x: f32, z: f32, yaw: f32, scale: f32, seed: f32 };
const homes = [COUNT]Home{
    // Deep down the avenue, past the toads + archers — the climax of the approach. Faces back
    // up the avenue (+Z) so the hero meets its eye as they close in.
    .{ .x = 3.0, .z = -50.0, .yaw = 0.0, .scale = 1.0, .seed = 0.4 },
};

pub const Grief = struct {
    model: Model,
    ogres: [COUNT]Ogre = undefined,

    pub fn init(shader: rl.Shader) Grief {
        var g = Grief{ .model = Model.init(shader) };
        for (homes, 0..) |h, i| g.ogres[i] = Ogre.spawn(mathx.ground(h.x, h.z), h.yaw, h.scale, h.seed);
        return g;
    }
    pub fn setShader(self: *Grief, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    // Advance the group; returns the STRONGEST blow any ogre landed on the hero this frame.
    pub fn update(self: *Grief, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        var worst: ?combat.Hit = null;
        for (&self.ogres) |*o| {
            if (o.update(dt, hero, bounds, blade)) |h| {
                if (worst == null or h.dmg > worst.?.dmg) worst = h;
            }
        }
        return worst;
    }
    pub fn draw(self: *const Grief, scene: ?*gfx.Scene) void {
        for (&self.ogres) |*o| {
            if (!o.alive()) continue;
            if (scene) |sc| sc.setFlash(0.85 * o.flashFrac());
            o.draw(&self.model);
        }
        if (scene) |sc| sc.setFlash(0);
    }
    pub fn drawFx(self: *const Grief) void {
        for (&self.ogres) |*o| o.drawFx();
    }
    pub fn anyDied(self: *const Grief) bool {
        for (&self.ogres) |*o| {
            if (o.justDied) return true;
        }
        return false;
    }
    pub fn totalHits(self: *const Grief) u32 {
        var n: u32 = 0;
        for (&self.ogres) |*o| n += o.hits;
        return n;
    }
    pub fn aliveCount(self: *const Grief) u32 {
        var n: u32 = 0;
        for (&self.ogres) |*o| {
            if (o.alive()) n += 1;
        }
        return n;
    }
};

// ── bone meshes (authored at the joint origin, hero-local axes; lengths in units of H) ──────
fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = torsoMesh();
    mesh[NECK] = neckMesh();
    mesh[SKULL] = headMesh();
    mesh[HIPL] = thighMesh();
    mesh[KNEEL] = shinMesh();
    mesh[ANKL] = footMesh(1.0);
    mesh[HIPR] = thighMesh();
    mesh[KNEER] = shinMesh();
    mesh[ANKR] = footMesh(-1.0);
    mesh[SHL] = upperArmMesh();
    mesh[ELL] = forearmMesh();
    mesh[WRL] = fistMesh();
    mesh[SHR] = upperArmMesh();
    mesh[ELR] = forearmMesh();
    mesh[WRR] = fistMesh();
    mesh[CLUB] = clubMesh();
    return mesh;
}

// A thick tapered limb segment `a`→`e` with a fatter articular knob at each end.
fn limb(b: *Builder, a: rl.Vector3, e: rl.Vector3, r0: f32, r1: f32, col: rl.Color) void {
    b.addCylinder(a, e, r0, r1, 9, col);
    b.addCylinder(v3(a.x, a.y + r0 * 0.5, a.z), v3(a.x, a.y - r0 * 0.5, a.z), r0 * 1.35, r0 * 1.35, 8, HIDE_LT);
    b.addCylinder(v3(e.x, e.y + r1 * 0.5, e.z), v3(e.x, e.y - r1 * 0.5, e.z), r1 * 1.3, r1 * 1.3, 8, HIDE_LT);
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCube(v3(0, 0.0, 0), v3(0.20 * H, 0.10 * H, 0.15 * H), HIDE); // broad pelvic block
    b.addCube(v3(0, -0.05 * H, 0.06 * H), v3(0.17 * H, 0.06 * H, 0.11 * H), BELLY); // low belly / groin
    b.setMat(.cloth);
    // a filthy loin-rag hanging off the hips (front + back flaps) — a scrap of pathos
    b.addBox(v3(0, -0.02 * H, 0.14 * H), v3(0.16 * H, 0, 0), v3(0, -0.11 * H, 0.01 * H), v3(0, 0, 0.02 * H), RAG);
    b.addBox(v3(0, -0.02 * H, -0.13 * H), v3(0.14 * H, 0, 0), v3(0, -0.10 * H, -0.01 * H), v3(0, 0, 0.02 * H), RAG);
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCylinder(v3(0, 0, 0), v3(0, 0.13 * H, 0), 0.15 * H, 0.19 * H, 10, HIDE); // thick waist widening to the chest
    return b.toMesh();
}

fn torsoMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    // A barrel chest, humped over the shoulders (the hunch); a paler scarred sternum.
    b.addCylinder(v3(0, -0.02 * H, -0.01 * H), v3(0, 0.10 * H, -0.03 * H), 0.24 * H, 0.20 * H, 12, HIDE);
    b.addCube(v3(0, 0.03 * H, -0.10 * H), v3(0.16 * H, 0.13 * H, 0.06 * H), HIDE_DK); // humped upper back
    b.addCube(v3(0, 0.0, 0.14 * H), v3(0.15 * H, 0.11 * H, 0.05 * H), BELLY); // sternum plate
    b.addCube(v3(0, -0.03 * H, 0.13 * H), v3(0.12 * H, 0.05 * H, 0.05 * H), SCAR); // old scar across the ribs
    // heavy sloped shoulders (the club side a touch bigger — the working arm)
    b.addCylinder(v3(0.20 * H, 0.06 * H, 0), v3(0.30 * H, 0.02 * H, 0), 0.13 * H, 0.11 * H, 9, HIDE_LT); // L trapezius
    b.addCylinder(v3(-0.20 * H, 0.06 * H, 0), v3(-0.31 * H, 0.02 * H, 0), 0.14 * H, 0.12 * H, 9, HIDE_LT); // R trapezius (club arm)
    // a scatter of warty lumps over the back + shoulders (seeded — wabi-sabi, deterministic)
    var rng = mathx.Rng.init(7321);
    var w: i32 = 0;
    while (w < 14) : (w += 1) {
        const a = rng.angle();
        const yy = rng.range(-0.02, 0.12) * H;
        const rr = 0.20 * H;
        b.addCube(v3(mathx.cosf(a) * rr, yy, mathx.sinf(a) * rr * 0.8 - 0.02 * H), v3(rng.range(0.02, 0.045) * H, rng.range(0.015, 0.03) * H, rng.range(0.02, 0.045) * H), if (rng.float() < 0.5) HIDE_DK else HIDE_LT);
    }
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    // A short, thick, forward-set neck (the head sits low + jutting — the hunched, sad carriage).
    b.addCylinder(v3(0, 0, 0), v3(0, 0.05 * H, 0.03 * H), 0.10 * H, 0.09 * H, 9, HIDE);
    return b.toMesh();
}

fn headMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    // A small, low-browed head for the giant body — heavy overhanging brow, sunken cheeks, a
    // sagging underbite with a couple of pale tusks, and ONE large central eye that glows a
    // dull tired amber (the sorrowful lamp). Compact so the body reads all the more massive.
    b.addCylinder(v3(0, 0.02 * H, 0.01 * H), v3(0, 0.10 * H, 0.0), 0.115 * H, 0.085 * H, 10, HIDE); // cranium
    b.addCube(v3(0, 0.03 * H, 0.02 * H), v3(0.12 * H, 0.075 * H, 0.11 * H), HIDE); // face block
    // heavy brow, overhanging — a permanent frown (the sad read)
    b.addBox(v3(0, 0.075 * H, 0.10 * H), v3(0.14 * H, 0.02 * H, 0), v3(0, -0.006 * H, 0.03 * H), v3(0, 0.028 * H, 0), HIDE_DK);
    // the single eye — a deep wet socket, a glowing amber dome, a small forward pupil
    b.setMat(.skin);
    b.addCube(v3(0, 0.035 * H, 0.10 * H), v3(0.075 * H, 0.055 * H, 0.03 * H), EYE_RIM); // socket
    b.setMat(.plain); // glassy eye — no hide blotch over the emissive dome
    b.addCylinder(v3(0, 0.035 * H, 0.108 * H), v3(0, 0.035 * H, 0.135 * H), 0.058 * H, 0.042 * H, 12, EYE); // amber eyeball (emissive)
    b.addCube(v3(0, 0.03 * H, 0.14 * H), v3(0.018 * H, 0.024 * H, 0.012 * H), PUPIL); // downcast pupil
    b.setMat(.skin);
    // a squat broad nose + sunken cheeks
    b.addCube(v3(0, 0.0, 0.13 * H), v3(0.035 * H, 0.03 * H, 0.03 * H), HIDE_DK);
    b.addCube(v3(0.07 * H, -0.01 * H, 0.08 * H), v3(0.03 * H, 0.035 * H, 0.04 * H), HIDE_DK); // L cheek hollow
    b.addCube(v3(-0.07 * H, -0.01 * H, 0.08 * H), v3(0.03 * H, 0.035 * H, 0.04 * H), HIDE_DK); // R cheek hollow
    // a heavy sagging lower jaw / underbite
    b.addCube(v3(0, -0.055 * H, 0.09 * H), v3(0.10 * H, 0.03 * H, 0.075 * H), HIDE);
    b.setMat(.stone);
    // two pale tusks jutting up from the underbite (uneven — one bigger, wabi-sabi)
    b.addCylinder(v3(0.045 * H, -0.04 * H, 0.14 * H), v3(0.052 * H, 0.02 * H, 0.15 * H), 0.016 * H, 0.004 * H, 6, TUSK);
    b.addCylinder(v3(-0.05 * H, -0.045 * H, 0.14 * H), v3(-0.058 * H, 0.035 * H, 0.15 * H), 0.019 * H, 0.005 * H, 6, TUSK_DK);
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_THIGH * H, 0), 0.10 * H, 0.075 * H, HIDE); // massive thigh
    return b.toMesh();
}

fn shinMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_SHANK * H, 0), 0.072 * H, 0.055 * H, HIDE); // thick calf
    return b.toMesh();
}

fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    const ay = 0.039 * H;
    b.addCube(v3(0, -ay + 0.03 * H, 0.06 * H), v3(0.075 * H, 0.045 * H, 0.14 * H), HIDE); // broad flat foot
    b.addCube(v3(0, -ay + 0.04 * H, -0.03 * H), v3(0.06 * H, 0.05 * H, 0.05 * H), HIDE_DK); // heel
    b.setMat(.stone);
    // three blunt toe-nails
    for ([_]f32{ -1, 0, 1 }) |t| {
        b.addCube(v3(t * 0.045 * H * side, -ay + 0.02 * H, 0.185 * H), v3(0.024 * H, 0.018 * H, 0.02 * H), TUSK_DK);
    }
    return b.toMesh();
}

fn upperArmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_UPARM * H, 0), 0.088 * H, 0.072 * H, HIDE); // heavy upper arm
    return b.toMesh();
}

fn forearmMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    limb(&b, v3(0, 0, 0), v3(0, -SEG_FOREARM * H, 0), 0.075 * H, 0.06 * H, HIDE); // thick forearm
    return b.toMesh();
}

fn fistMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCube(v3(0, -0.03 * H, 0.01 * H), v3(0.065 * H, 0.06 * H, 0.06 * H), HIDE); // big fist
    b.setMat(.stone);
    // four blunt knuckle-nails
    for ([_]f32{ -1.5, -0.5, 0.5, 1.5 }) |k| {
        b.addCube(v3(k * 0.028 * H, -0.02 * H, 0.06 * H), v3(0.014 * H, 0.02 * H, 0.016 * H), TUSK_DK);
    }
    return b.toMesh();
}

// The great club — authored in the RIGHT-WRIST frame, gripped near the top of the haft (at the
// fist) and extending DOWN the arm line (−Y), so it hangs/drags when the arm is low and rears
// overhead when the arm swings up. A gnarled bog-oak haft with a huge knotted head of lashed-on
// stone + rusted iron lumps at the far end. Wabi-sabi: uneven lumps, a seeded scatter.
fn clubMesh() rl.Mesh {
    var b = Builder.init();
    const gy = -0.03 * H; // grip centre in the wrist frame (at the fist)
    const gz = 0.02 * H; // a touch out front of the palm
    const headY = gy - 0.50 * H; // the head sits ~0.5 H down the haft — a STOUT bludgeon, not a pike
    b.setMat(.wood);
    // haft: a short butt above the fist, thickening down into the head; a hewn taper
    b.addCylinder(v3(0, gy + 0.11 * H, gz), v3(0, gy, gz), 0.034 * H, 0.042 * H, 8, CLUB_WOOD_LT); // butt above the grip
    b.addCylinder(v3(0, gy, gz), v3(0, gy - 0.26 * H, gz + 0.01 * H), 0.048 * H, 0.062 * H, 8, CLUB_WOOD); // haft
    b.addCylinder(v3(0, gy - 0.26 * H, gz + 0.01 * H), v3(0, headY + 0.10 * H, gz + 0.02 * H), 0.062 * H, 0.090 * H, 8, CLUB_WOOD); // flare into the head
    // the head: a fat knotted boulder-lump (big + round so it reads as heavy)
    b.setMat(.stone);
    b.addCylinder(v3(0, headY + 0.16 * H, gz + 0.02 * H), v3(0, headY - 0.17 * H, gz + 0.02 * H), 0.135 * H, 0.135 * H, 11, CLUB_STONE);
    b.addCube(v3(0, headY, gz + 0.02 * H), v3(0.15 * H, 0.16 * H, 0.15 * H), CLUB_STONE);
    // lashed-on stones + rusted iron lumps + a couple of driven spikes (seeded scatter — wabi-sabi)
    b.setMat(.steel);
    var rng = mathx.Rng.init(5119);
    var i: i32 = 0;
    while (i < 13) : (i += 1) {
        const a = rng.angle();
        const yy = headY + rng.range(-0.15, 0.16) * H;
        const rr = 0.135 * H;
        const cx = mathx.cosf(a) * rr;
        const cz = gz + 0.02 * H + mathx.sinf(a) * rr;
        const sz = rng.range(0.035, 0.075) * H;
        b.addCube(v3(cx, yy, cz), v3(sz, sz * rng.range(0.7, 1.2), sz), if (rng.float() < 0.5) CLUB_IRON else CLUB_STONE);
        if (rng.float() < 0.4) { // a driven iron spike poking out
            b.addCylinder(v3(cx, yy, cz), v3(cx * 1.8, yy, cz + (cz - (gz + 0.02 * H)) * 0.8 + 0.06 * H), 0.024 * H, 0.002 * H, 5, CLUB_IRON);
        }
    }
    return b.toMesh();
}

// ── invariants under test (pure logic only) ──────────────────────────────────────────────
test "slam AI: too close crushes when ready, else looms; too far closes; out of aggro idles" {
    try std.testing.expectEqual(Choice.idle, classify(AGGRO_R + 1, true)); // disengaged
    try std.testing.expectEqual(Choice.slam, classify(SLAM_R - 0.5, true)); // in reach, ready
    try std.testing.expectEqual(Choice.wait, classify(SLAM_R - 0.5, false)); // in reach, cooling → loom
    try std.testing.expectEqual(Choice.approach, classify((SLAM_R + AGGRO_R) * 0.5, true)); // gap to close
}

test "range band is ordered and sits inside aggro" {
    try std.testing.expect(SLAM_R < AGGRO_R);
}

test "higher poise: a single hero light does NOT flinch the ogre (only sustained pressure does)" {
    var vit = combat.Vitals.init(HP_MAX, POISE_MAX, STANCE_MAX);
    // One hero light (poise 10) vs the ogre's 30 poise → no reaction (it shrugs it off).
    try std.testing.expectEqual(combat.HitResult.none, vit.hit(heromod.ATK_LIGHT_HIT));
    // Three quick lights (no regen between) empty the 30 poise → the first flinch.
    _ = vit.hit(heromod.ATK_LIGHT_HIT);
    try std.testing.expectEqual(combat.HitResult.light, vit.hit(heromod.ATK_LIGHT_HIT));
}

test "slam crush catches the front zone, not the sides or behind" {
    var front = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // faces +Z
    front.tryImpact(v3(0, 0, 3.0), SLAM_HIT); // dead ahead, in reach
    try std.testing.expect(front.heroHit != null);

    var behind = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    behind.tryImpact(v3(0, 0, -3.0), SLAM_HIT); // same distance, behind
    try std.testing.expect(behind.heroHit == null);

    var far = Ogre.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    far.tryImpact(v3(0, 0, 99), SLAM_HIT); // out front but way out of reach
    try std.testing.expect(far.heroHit == null);
}
