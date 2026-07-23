const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// ── THE GAPING TOAD ───────────────────────────────────────────────────────────────────
// A creative first enemy for the Lands-Between plain: a squat, warty bog-toad about 2/3 the
// hero's mass, all mouth and teeth. It doesn't walk — it HOPS, coiling low then firing off
// its haunches; it closes the last gap with a committed LUNGE that leaves it winded and
// wide open (the "recovery window"); and up close it gapes its throat sac and CHOMPS.
//
// Same rendering discipline as the hero (procedural Builder meshes + a per-part matrix
// rig, drawn with drawMesh through one scene-shader material so it lights + casts shadows
// like everything else). But where the hero is an anthropometric FK skeleton, the toad is
// a shallow 9-part rig whose LIFE comes from SQUASH & STRETCH — the coil, the airborne
// stretch, the landing splat, the throat balloon — plus a hinged jaw and folding haunches.
//
// ART DIRECTION (the DESIRED feel — exaggerated + readable, per the game's combat feel):
//   IDLE   : sits low and breathing, throat pulsing, the odd twitch/turn. Alive, waiting.
//   HOP    : the frog verb. COIL (squash down, knees over the back, a beat of anticipation)
//            → LAUNCH (haunches fire straight, body STRETCHES thin, nose up) → a clean
//            ballistic ARC → LAND (front legs reach, body SPLATS wide, absorbs). Somewhat
//            fast: it keeps bounding, small settles between hops.
//   LUNGE  : a big committed leap to close distance — a DEEP readable coil (the tell),
//            a long flat arc aimed at the hero, then a heavy landing into a RECOVERY: it
//            lands splayed and spent for a beat, unable to act. That beat is the opening.
//   CHOMP  : in bite range it rears, the throat sac BALLOONS + the jaw gapes wide (the
//            tell), then a fast SNAP forward — jaws slam, head thrusts — and a short recover.
//   Nothing parks dead: hops overshoot into a splat, the chomp recoils, idle keeps breathing.
//
// Hits: the hero's swept blade capsule is tested against each toad's hurt sphere (one hit
// per swing, latched). We TRACK the count and nothing more — no flinch, no damage, no death
// yet (scope: creature + AI). The hit plumbing is here so combat drops straight in later.

// ── matrix shorthand (raylib TRS: mul(a,b) applies a FIRST then b) ──────────────────────
// The shared helpers from mathx (single source for the "a-first" convention across rigs).
const rx = mathx.rx;
const ry = mathx.ry;
const tr = mathx.tr;
const scaleM = mathx.scaleM;
const mul = mathx.mul;
const mul3 = mathx.mul3;
// Place a part authored at its joint origin: rotate/scale (`anim`) about that origin, shift
// to the joint's rest offset in the parent frame, then into the parent's world. Mirrors the
// hero's setLocal (world = animRot ∘ translate(offset) ∘ parentWorld).
fn place(off: rl.Vector3, anim: rl.Matrix, parent: rl.Matrix) rl.Matrix {
    return mul3(anim, tr(off.x, off.y, off.z), parent);
}

// ── palette (pre-gamma dark — the scene shader gammas output, so these lift a lot) ──────
// A bog thing tuned to the dry-gold/scrub Limgrave palette: dark olive hide, a pale sickly
// belly + throat, a blood-dark maw, pale bone teeth that POP, and faintly grace-gold eyes.
const HIDE = rgba(34, 38, 23, 255); // dark bog olive (a night thing)
const HIDE_DK = rgba(20, 23, 14, 255); // warts, shadow, mottling — near-black
const HIDE_LT = rgba(52, 55, 34, 255); // ridge / caught-light humps
const BELLY = rgba(64, 62, 42, 255); // dark, sickly underside
const SAC = rgba(80, 74, 48, 255); // throat sac — a touch paler so its distend reads
const MAW = rgba(104, 34, 28, 255); // mouth interior — a sickly oxblood RED, lighter than the hide so the open maw reads as a cavern
const TONGUE = rgba(126, 56, 48, 255);
const TOOTH = rgba(166, 156, 126, 255); // pale bone — pops hard against the dark hide
const TOOTH_DK = rgba(126, 116, 90, 255);
// The eyes GLOW: a low alpha drives the shader's emissive channel hard, so this bright
// amber-gold burns through shadow and haze like the grace ember — lamp-eyes in the dark.
const EYE = rgba(252, 196, 84, 96);
const PUPIL = rgba(10, 8, 6, 255);
const CLAW = rgba(28, 26, 20, 255);

// ── rig parts (each = one mesh + one world matrix) ──────────────────────────────────────
const NP = 9;
const BODY = 0; // trunk + fused upper head/jaw + brow + eyes + warts (squashes about the seat)
const LJAW = 1; // lower jaw (hinges open at the back of the mouth)
const THROAT = 2; // throat sac (inflates)
const HAUNCH_L = 3; // back-left thigh (hip pivot)
const SHANK_L = 4; // back-left shank + webbed foot (knee pivot)
const HAUNCH_R = 5;
const SHANK_R = 6;
const ARM_L = 7; // front-left leg (small; shoulder pivot)
const ARM_R = 8;

// Rest joint locations in the body frame (origin at the ground seat, +Y up, +Z forward).
const P_JAW = v3(0, 0.24, 0.02); // jaw hinge, back of the mouth
const P_SAC = v3(0, 0.12, 0.24); // throat-sac centre, slung under the chin
const P_HIP = v3(0.40, 0.24, -0.06); // back-leg hip — OUT on the flank, clear of the body dome
const P_KNEE = v3(0.47, 0.46, 0.00); // back-leg knee — HIGH and OUT, so the folded haunch bulges in silhouette
const P_SHOULDER = v3(0.22, 0.26, 0.22); // front-leg shoulder

// ── dimensions / tuning ─────────────────────────────────────────────────────────────
const BODY_CY = 0.34; // body-centre height (for the camera focus + hurt sphere)
const HURT_R = 0.46; // hurt-sphere radius (world units, pre per-toad scale)
const BODY_R = 0.55; // ground-footprint radius for collision (pre per-toad scale) — matches the
//   broad body + splayed haunches so toads don't interpenetrate (frog-on-frog was too forgiving)

// Global size multiplier for the whole knot (each toad's own `scale` rides on top). Bumped
// so they read BIG and heavy — broad, roughly waist-high, a real threat rather than a pet.
pub const SCALE = 1.4;

// Locomotion & senses (world units / seconds).
const AGGRO_R = 11.0; // notices the hero within this
const LUNGE_R = 5.6; // will commit a lunge inside this (but outside bite range)
const BITE_R = 1.45; // chomps inside this
const HOP_REACH = 1.95; // ground covered by an approach hop
const HOP_APEX = 0.62; // approach-hop peak height
const LUNGE_APEX = 1.15; // lunge arc peak height
const KEEP_OFF = BITE_R - 0.25; // an approach hop stops here, just shy of bite range

// Phase durations (seconds).
const HOP_COIL = 0.16;
const HOP_FLIGHT = 0.40;
const HOP_LAND = 0.16;
const HOP_SETTLE_AGGRO = 0.07; // brief settle between bounds when hunting (keeps it fast)
const LUNGE_COIL = 0.34; // the readable wind-up tell
const LUNGE_FLIGHT = 0.52;
const LUNGE_LAND = 0.12;
const RECOVER_DUR = 0.78; // the winded, wide-open window after a lunge
const CHOMP_GAPE = 0.30; // sac balloons, jaw yawns (the tell)
const CHOMP_SNAP = 0.11; // jaws slam
const CHOMP_RECOVER = 0.42;
const CHOMP_JAW = 64.0; // how wide the maw yawns (deg) — a big, readable gape
const CHOMP_SAC = 1.95; // throat-sac inflate at full gape (scale)
const LUNGE_CD = 2.1; // cooldowns keep it from spamming
const CHOMP_CD = 0.7;
const TURN_RATE = 7.0; // rad/s the toad yaws toward its target (between hops / while idle)

// Leg fold: legExt 0 = fully coiled, 1 = fully extended; the sit pose is REST_EXT. Hip &
// knee rotate away from the authored sit pose by these swings across the 0..1 range.
const REST_EXT = 0.34;
const HIP_SWING = 66.0; // + extends the thigh back-and-down (push-off)
const KNEE_STRAIGHTEN = 104.0; // + straightens the knee out of its tuck
const FLASH_DUR = 0.20; // debug-only: how long a registered hit tints the hurt sphere

// The hero's blade this frame, handed in as plain data so the toad stays decoupled from the
// hero rig. Endpoints are guard→tip; the *0 pair is last frame's, for a swept test.
pub const Blade = struct {
    active: bool = false,
    r: f32 = 0,
    a: rl.Vector3 = mathx.zero3,
    b: rl.Vector3 = mathx.zero3,
    a0: rl.Vector3 = mathx.zero3,
    b0: rl.Vector3 = mathx.zero3,
    hit: combat.Hit = .{}, // HP/poise/stance the swing deals (light vs heavy set by game.zig)
};

// ── vitals (LOW poise, per the brief: "frogs have low poise") ──────────────────────────
const HP_MAX = 46.0;
const POISE_MAX = 12.0; // low — a couple of hits flinch it
const STANCE_MAX = 26.0; // low — a few flinches cascade into the heavy stagger
// What the toad's own attacks do to the HERO (guard→tip data flows the other way; these
// are handed out when a chomp SNAP / lunge SLAM connects). The lunge is a heavy body-blow.
const CHOMP_HIT = combat.Hit{ .dmg = 11, .poise = 15 };
const LUNGE_HIT = combat.Hit{ .dmg = 17, .poise = 26, .stance = 8 };
const HERO_REACH = 0.55; // hero footprint added to the toad's attack range for the hit test
const DEATH_DUR = 1.25; // collapse-and-still before the corpse is removed from play

// idle, hop, lunge, recover, chomp are the live behaviours; the last three are REACTIONS
// (interrupts) — a light flinch, the heavy stance-break stagger, and death.
const State = enum { idle, hop, lunge, recover, chomp, stunlight, stunheavy, dead };

// What the toad decides to do when it's free to act — a PURE function of range + cooldowns,
// so the decision logic is unit-testable without a GPU/world.
const Choice = enum { rest, hop, lunge, chomp, wait };
fn classify(dist: f32, lungeReady: bool, chompReady: bool) Choice {
    if (dist > AGGRO_R) return .rest;
    if (dist <= BITE_R) return if (chompReady) .chomp else .wait; // too close to hop; hold for the bite
    if (dist <= LUNGE_R and lungeReady) return .lunge;
    return .hop;
}

// The shared toad meshes + material (built once, like env.models); every Frog draws these
// with its own per-part matrices. Meshes live the whole program (leak at exit — fine).
pub const Model = struct {
    mesh: [NP]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("frog material");
        mat.shader = shader;
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, xf: *const [NP]rl.Matrix) void {
        for (0..NP) |i| rl.drawMesh(self.mesh[i], self.mat, xf[i]);
    }
};

pub const Frog = struct {
    // placement / heading
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,
    scale: f32 = 1.0, // per-toad size jitter
    seed: f32 = 0, // per-toad phase offset so a knot never moves in lockstep

    // state machine
    state: State = .idle,
    t: f32 = 0, // seconds into the current state / phase
    idleWait: f32 = 0, // idle: seconds until the next decision
    lungeCd: f32 = 0,
    chompCd: f32 = 0,
    elapsed: f32 = 0,
    hopFrom: rl.Vector3 = mathx.zero3,
    hopTo: rl.Vector3 = mathx.zero3,
    hopApex: f32 = 0,
    hopDur: f32 = 0, // this hop's flight time (scales with reach)
    isLunge: bool = false, // the in-flight hop is a lunge (→ recovery on landing)

    // resolved animation channels (read by pose())
    sy: f32 = 1, // body vertical scale (squash<1 / stretch>1)
    sxz: f32 = 1, // body horizontal scale (volume-ish conserved)
    lift: f32 = 0, // world-Y hop height
    pitch: f32 = 0, // body pitch (deg; + = nose down)
    legExt: f32 = REST_EXT,
    arm: f32 = 0, // front-leg forward reach 0..1
    jaw: f32 = 0, // lower-jaw open (deg)
    sac: f32 = 1, // throat-sac inflate scale

    // combat
    vit: combat.Vitals = combat.Vitals.init(HP_MAX, POISE_MAX, STANCE_MAX),
    hits: u32 = 0, // total blows landed (debug read-out)
    hitLatch: bool = false, // one hit per swing: set on contact, cleared when the blade goes inactive
    flash: f32 = 0, // debug: fades after a registered hit
    heroHit: ?combat.Hit = null, // this frame's blow ON THE HERO (chomp/lunge connect), read by game.zig
    heroLatch: bool = false, // one hero-hit per attack action (chomp/lunge)
    gone: bool = false, // corpse removed from play (death anim finished) — skipped everywhere

    xf: [NP]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Frog {
        var f = Frog{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * SCALE, .seed = seed };
        f.idleWait = 1.0 + seed * 2.0;
        f.resolveIdle();
        f.pose();
        return f;
    }

    pub fn centerWorld(self: *const Frog) rl.Vector3 {
        return v3(self.pos.x, BODY_CY * self.scale + self.lift, self.pos.z);
    }
    pub fn hurtRadius(self: *const Frog) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Frog) f32 {
        return BODY_R * self.scale;
    }
    // The point the lock-on reticle rides — the centre of the body mass (not the head), so
    // the dot sits on the bulk of the toad.
    pub fn lockPoint(self: *const Frog) rl.Vector3 {
        return v3(self.pos.x, 0.30 * self.scale + self.lift, self.pos.z);
    }
    // Airborne mid-hop/lunge — ground collision leaves it be while it's in the air.
    pub fn airborne(self: *const Frog) bool {
        return self.lift > 0.04;
    }
    // Top of the domed back in world space — where the floating HP bar rides.
    pub fn topWorld(self: *const Frog) rl.Vector3 {
        return v3(self.pos.x, 0.80 * self.scale + self.lift, self.pos.z);
    }
    // A live combatant (a corpse whose death anim has finished is skipped everywhere).
    pub fn alive(self: *const Frog) bool {
        return !self.gone;
    }
    // Reeling from a stagger or dying — the wide-open window / no threat.
    pub fn staggered(self: *const Frog) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }

    // ── actions ─────────────────────────────────────────────────────────────────────
    fn faceToward(self: *Frog, target: rl.Vector3, dt: f32) void {
        const d = mathx.dirXZ(self.pos, target);
        if (mathx.lenXZ(d) < 1e-3) return;
        self.facing = mathx.approachAngle(self.facing, std.math.atan2(d.x, d.z), TURN_RATE * dt);
    }

    // Begin a hop toward `to` (clamped to bounds). `lunge` = the big committed leap.
    pub fn startHop(self: *Frog, to: rl.Vector3, bounds: f32, lunge: bool) void {
        self.facing = std.math.atan2(to.x - self.pos.x, to.z - self.pos.z);
        self.hopFrom = self.pos;
        self.hopTo = v3(mathx.clampF(to.x, -bounds, bounds), 0, mathx.clampF(to.z, -bounds, bounds));
        self.isLunge = lunge;
        self.hopApex = if (lunge) LUNGE_APEX else HOP_APEX;
        const reach = mathx.distXZ(self.hopFrom, self.hopTo);
        self.hopDur = if (lunge) LUNGE_FLIGHT else HOP_FLIGHT * mathx.clampF(0.5 + reach / HOP_REACH, 0.6, 1.5);
        self.state = if (lunge) .lunge else .hop;
        self.t = 0;
        self.heroLatch = false; // a fresh action gets one chance to land on the hero
    }
    pub fn startChomp(self: *Frog) void {
        self.state = .chomp;
        self.t = 0;
        self.heroLatch = false;
    }
    fn enterStun(self: *Frog, s: State) void {
        self.state = s; // the interrupt drops any in-progress attack (nothing lands)
        self.t = 0;
        self.heroLatch = false;
    }
    fn enterDeath(self: *Frog) void {
        self.state = .dead;
        self.t = 0;
        self.heroLatch = false;
    }
    // Screenshot-harness hooks: force a reaction so --shot can frame the poses in isolation.
    pub fn debugStagger(self: *Frog, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Frog) void {
        self.enterDeath();
    }
    // Land the toad's OWN attack on the hero, once per action: if the hero is within reach,
    // stash the blow in heroHit for game.zig to apply to the hero's vitals.
    fn tryBite(self: *Frog, hero: rl.Vector3, range: f32, h: combat.Hit) void {
        if (self.heroLatch) return;
        if (mathx.distXZ(self.pos, hero) <= range + HERO_REACH) {
            self.heroHit = h;
            self.heroLatch = true;
        }
    }

    // ── per-frame update ──────────────────────────────────────────────────────────────
    // Advance AI + animation for one frame; `hero` drives senses, `blade` the hero's swing.
    // Returns the blow this toad landed on the HERO this frame (null if none / it's a corpse).
    pub fn update(self: *Frog, dt: f32, hero: rl.Vector3, bounds: f32, blade: Blade) ?combat.Hit {
        if (self.gone) return null;
        self.heroHit = null;
        self.vit.tick(dt); // poise/stance regenerate between hits (relent and it recovers)
        self.elapsed += dt;
        self.lungeCd = mathx.maxF(0, self.lungeCd - dt);
        self.chompCd = mathx.maxF(0, self.chompCd - dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        self.t += dt;

        switch (self.state) {
            .idle => self.updateIdle(dt, hero, bounds),
            .hop => self.updateHop(dt, hero, bounds, HOP_COIL, self.hopDur, HOP_LAND),
            .lunge => self.updateHop(dt, hero, bounds, LUNGE_COIL, self.hopDur, LUNGE_LAND),
            .recover => {
                self.resolveRecover();
                if (self.t >= RECOVER_DUR) self.enterIdle(0.02);
            },
            .chomp => self.updateChomp(dt, hero),
            // ── reactions (interrupts) ──
            .stunlight => {
                self.resolveStunLight();
                if (self.t >= combat.LIGHT_STUN_DUR) self.enterIdle(0.02);
            },
            .stunheavy => {
                self.resolveStunHeavy();
                if (self.t >= combat.HEAVY_STUN_DUR) self.enterIdle(0.06);
            },
            .dead => {
                self.resolveDeath();
                if (self.t >= DEATH_DUR) self.gone = true;
            },
        }

        self.pose();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn enterIdle(self: *Frog, wait: f32) void {
        self.state = .idle;
        self.t = 0;
        self.idleWait = wait;
    }

    // Decide what to do next (called when a hop/chomp/recovery finishes, and on the idle
    // timer). Chomp when close, lunge to close the gap, else keep bounding in; drift home
    // and rest when the hero is out of range.
    fn decide(self: *Frog, hero: rl.Vector3, bounds: f32) void {
        const d = mathx.distXZ(self.pos, hero);
        switch (classify(d, self.lungeCd <= 0, self.chompCd <= 0)) {
            .chomp => {
                self.chompCd = CHOMP_CD;
                self.startChomp();
            },
            .lunge => {
                self.lungeCd = LUNGE_CD;
                // Land just short of the hero (don't leap past them).
                const dir = mathx.dirXZ(self.pos, hero);
                const reach = mathx.minF(d - KEEP_OFF, LUNGE_R);
                self.startHop(v3(self.pos.x + dir.x * reach, 0, self.pos.z + dir.z * reach), bounds, true);
            },
            .hop => {
                const dir = mathx.dirXZ(self.pos, hero);
                const reach = mathx.minF(HOP_REACH, mathx.maxF(0, d - KEEP_OFF));
                self.startHop(v3(self.pos.x + dir.x * reach, 0, self.pos.z + dir.z * reach), bounds, false);
            },
            .wait => self.enterIdle(0.12), // in bite range, chomp cooling down — hold a beat
            .rest => {
                // Out of aggro: hop home if we've wandered, else sit and wait.
                if (mathx.distXZ(self.pos, self.home) > 2.2) {
                    const dir = mathx.dirXZ(self.pos, self.home);
                    self.startHop(v3(self.pos.x + dir.x * HOP_REACH, 0, self.pos.z + dir.z * HOP_REACH), bounds, false);
                } else self.enterIdle(1.4 + self.seed * 2.2);
            },
        }
    }

    fn updateIdle(self: *Frog, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const d = mathx.distXZ(self.pos, hero);
        if (d <= AGGRO_R) self.faceToward(hero, dt); // lock eyes the moment it wakes
        self.resolveIdle();
        // React fast when the hero is in range; laze otherwise.
        const wait = if (d <= AGGRO_R) mathx.minF(self.idleWait, 0.16) else self.idleWait;
        if (self.t >= wait) self.decide(hero, bounds);
    }

    fn updateHop(self: *Frog, dt: f32, hero: rl.Vector3, bounds: f32, coil: f32, flight: f32, land: f32) void {
        const total = coil + flight + land;
        if (self.t < coil) {
            // COIL: hold at the takeoff spot, still steering onto the target, and load.
            if (!self.isLunge) self.faceToward(hero, dt);
            const k = mathx.smoothstep(0, coil, self.t);
            self.resolveCoil(k, self.isLunge);
        } else if (self.t < coil + flight) {
            const s = (self.t - coil) / flight; // 0..1 across the arc
            // Advance horizontally by an INCREMENT (velocity·dt), NOT an absolute lerp from a
            // stale hopFrom: this way a collision nudge mid-arc just deflects the leap instead
            // of the next frame snapping the toad back to its takeoff point (the "warp" bug).
            const inv = 1.0 / flight;
            self.pos.x += (self.hopTo.x - self.hopFrom.x) * inv * dt;
            self.pos.z += (self.hopTo.z - self.hopFrom.z) * inv * dt;
            self.resolveFlight(s);
        } else {
            // Landed: hold wherever we ended up (collision may still adjust it) and splat —
            // do NOT re-snap to hopTo, which would clobber a collision push on touchdown.
            const k = mathx.smoothstep(0, land, self.t - coil - flight);
            self.resolveLand(k);
            if (self.isLunge) self.tryBite(hero, BITE_R + 0.5, LUNGE_HIT); // the body-slam connects
        }
        self.pos.x = mathx.clampF(self.pos.x, -bounds, bounds);
        self.pos.z = mathx.clampF(self.pos.z, -bounds, bounds);
        if (self.t >= total) {
            if (self.isLunge) {
                self.state = .recover; // land the lunge into the wide-open window
                self.t = 0;
            } else {
                self.enterIdle(HOP_SETTLE_AGGRO);
            }
        }
    }

    fn updateChomp(self: *Frog, dt: f32, hero: rl.Vector3) void {
        if (self.t < CHOMP_GAPE) {
            self.faceToward(hero, dt); // track the target while gaping
            self.resolveGape(mathx.smoothstep(0, CHOMP_GAPE, self.t));
        } else if (self.t < CHOMP_GAPE + CHOMP_SNAP) {
            self.resolveSnap((self.t - CHOMP_GAPE) / CHOMP_SNAP);
            self.tryBite(hero, BITE_R, CHOMP_HIT); // jaws slam shut on the hero
        } else {
            self.resolveChompRecover(mathx.smoothstep(0, CHOMP_RECOVER, self.t - CHOMP_GAPE - CHOMP_SNAP));
            if (self.t >= CHOMP_GAPE + CHOMP_SNAP + CHOMP_RECOVER) self.enterIdle(0.1);
        }
    }

    // ── animation channel resolvers (each sets the pose fields for its beat) ────────────
    fn base(self: *Frog) void {
        self.sy = 1;
        self.sxz = 1;
        self.lift = 0;
        self.pitch = 0;
        self.legExt = REST_EXT;
        self.arm = 0;
        self.jaw = 0;
        self.sac = 1;
    }
    fn resolveIdle(self: *Frog) void {
        self.base();
        // Alive at rest: a slow breathing bob in the body + a pulsing throat.
        const br = mathx.sinf(self.elapsed * 1.8 + self.seed * 6.28);
        self.sy = 1.0 + 0.03 * br;
        self.sxz = 1.0 - 0.02 * br;
        self.sac = 1.0 + 0.06 * mathx.sinf(self.elapsed * 2.3 + self.seed * 3.0);
        self.jaw = 1.5 + 1.5 * mathx.maxF(0, br); // faint mouth working
    }
    fn resolveCoil(self: *Frog, k: f32, lunge: bool) void {
        self.base();
        const deep: f32 = if (lunge) 1.15 else 1.0; // the lunge coils deeper (bigger tell)
        self.sy = 1.0 - 0.30 * k * deep; // squash down
        self.sxz = 1.0 + 0.18 * k * deep; // spread wide
        self.legExt = mathx.lerpF(REST_EXT, 0.05, k); // knees stack up over the back
        self.pitch = -6.0 * k * deep; // nose tips up, ready to leap
        self.arm = 0.15 * k;
        self.sac = 1.0 + 0.10 * k;
    }
    fn resolveFlight(self: *Frog, s: f32) void {
        self.lift = self.hopApex * 4.0 * s * (1.0 - s); // parabola, peak at s=0.5
        // Explosive extend off the launch, trailing long, tucking a touch before landing.
        const launch = 1.0 - mathx.smoothstep(0.0, 0.32, s);
        const preland = mathx.smoothstep(0.72, 1.0, s);
        self.legExt = mathx.clampF(1.0 - 0.35 * preland, 0.0, 1.0);
        self.sy = 1.0 + 0.20 * launch - 0.10 * preland; // stretch off the ground, splat-prep late
        self.sxz = 1.0 - 0.12 * launch + 0.06 * preland;
        self.pitch = mathx.lerpF(-14.0, 16.0, s); // nose up on the rise, down on the dive
        self.arm = mathx.smoothstep(0.55, 1.0, s); // front legs reach out to catch the ground
        self.jaw = 2.0;
        self.sac = 1.0;
    }
    fn resolveLand(self: *Frog, k: f32) void {
        // SPLAT then rebound: absorb wide + low, settle back toward the sit.
        const splat = mathx.smoothstep(0, 0.45, k) * (1.0 - mathx.smoothstep(0.45, 1.0, k));
        self.lift = 0;
        self.sy = 1.0 - 0.26 * splat;
        self.sxz = 1.0 + 0.16 * splat;
        self.legExt = mathx.lerpF(0.2, REST_EXT, k);
        self.arm = 1.0 - k;
        self.pitch = 8.0 * (1.0 - k);
        self.jaw = 2.0;
        self.sac = 1.0;
    }
    fn resolveRecover(self: *Frog) void {
        // Winded + wide open: belly-low, splayed, panting. Eases back to a sit at the end.
        const u = mathx.clampF(self.t / RECOVER_DUR, 0, 1);
        const out = 1.0 - mathx.smoothstep(0.7, 1.0, u); // spent for most of it, gathers at the end
        const pant = mathx.sinf(self.elapsed * 9.0);
        self.lift = 0;
        self.sy = mathx.lerpF(1.0, 0.80, out); // flattened
        self.sxz = mathx.lerpF(1.0, 1.14, out); // sprawled
        self.legExt = mathx.lerpF(REST_EXT, 0.12, out); // haunches splayed out flat
        self.pitch = 7.0 * out;
        self.arm = 0.5 * out;
        self.jaw = 8.0 * out + 3.0 * pant * out; // gulping for air
        self.sac = 1.0 + (0.18 + 0.10 * pant) * out;
    }
    fn resolveGape(self: *Frog, k: f32) void {
        self.base();
        self.sy = 1.0 - 0.06 * k; // hunker
        self.sxz = 1.0 + 0.05 * k;
        self.pitch = -13.0 * k; // rears the head back…
        self.jaw = CHOMP_JAW * k; // …and YAWNS wide open (the tell)
        self.sac = 1.0 + (CHOMP_SAC - 1.0) * k; // throat balloons
        self.legExt = mathx.lerpF(REST_EXT, 0.22, k); // rocks back onto the haunches
        self.arm = 0.2 * k;
    }
    fn resolveSnap(self: *Frog, s: f32) void {
        // Jaws SLAM and the whole head thrusts forward.
        self.jaw = mathx.lerpF(CHOMP_JAW, 0.0, mathx.smoothstep(0, 0.55, s));
        self.pitch = mathx.lerpF(-13.0, 14.0, s); // whips down into the bite
        self.sac = mathx.lerpF(CHOMP_SAC, 0.9, s); // deflates as it clamps
        self.sy = 1.0 + 0.05 * s;
        self.sxz = 1.0 - 0.03 * s;
        self.lift = 0;
        self.legExt = 0.30;
        self.arm = 0.2;
    }
    fn resolveChompRecover(self: *Frog, k: f32) void {
        // Ease everything back to the sit; a touch of recoil so it doesn't park dead.
        const rc = mathx.sinf(k * std.math.pi) * (1.0 - k);
        self.sy = 1.0 - 0.03 * rc;
        self.sxz = 1.0 + 0.02 * rc;
        self.lift = 0;
        self.pitch = mathx.lerpF(12.0, 0.0, k);
        self.jaw = 3.0 * (1.0 - k);
        self.sac = mathx.lerpF(0.9, 1.0, k);
        self.legExt = mathx.lerpF(0.30, REST_EXT, k);
        self.arm = 0.2 * (1.0 - k);
    }

    // ── reaction poses (the two-tier stagger + death) ──────────────────────────────────
    fn resolveStunLight(self: *Frog) void {
        // A big, unmistakable FLINCH: the toad REARS back and UP off the blow, jaw gaping,
        // recoiling clear of the ground, then slams back down as it eases home.
        self.base();
        const u = mathx.clampF(self.t / combat.LIGHT_STUN_DUR, 0, 1);
        const j = mathx.sinf(u * std.math.pi); // 0 → 1 → 0 over the flinch
        self.pitch = -30.0 * j; // whole body thrown back
        self.sy = 1.0 - 0.22 * j;
        self.sxz = 1.0 + 0.15 * j;
        self.jaw = 30.0 * j; // a pained gape
        self.legExt = mathx.lerpF(REST_EXT, 0.66, j); // rears up on the haunches
        self.lift = 0.16 * j; // recoils clear off the ground
        self.sac = 1.0 + 0.14 * j;
    }
    fn resolveStunHeavy(self: *Frog) void {
        // STANCE BROKEN — it CRUMPLES: slams flat and wide, splayed and reeling, jaw lolling,
        // wide open the whole beat (ER's stance break; the critical/riposte comes later).
        self.base();
        const u = mathx.clampF(self.t / combat.HEAVY_STUN_DUR, 0, 1);
        const down = mathx.smoothstep(0, 0.16, u) * (1.0 - mathx.smoothstep(0.74, 1.0, u)); // slam, gather at the end
        const reel = mathx.sinf(self.elapsed * 8.0);
        self.lift = 0;
        self.sy = mathx.lerpF(1.0, 0.56, down); // flattened
        self.sxz = mathx.lerpF(1.0, 1.32, down); // sprawled
        self.legExt = mathx.lerpF(REST_EXT, 0.05, down); // haunches splayed out flat
        self.pitch = 13.0 * down;
        self.jaw = 20.0 * down + 4.0 * reel * down; // gulping, dazed
        self.sac = 1.0 + 0.22 * down;
        self.arm = 0.7 * down;
    }
    fn resolveDeath(self: *Frog) void {
        // Collapse and go still — flattens right out, jaw agape, no recovery.
        self.base();
        const k = mathx.smoothstep(0, 0.4, mathx.clampF(self.t / DEATH_DUR, 0, 1));
        self.lift = 0;
        self.sy = mathx.lerpF(1.0, 0.30, k);
        self.sxz = mathx.lerpF(1.0, 1.40, k);
        self.legExt = mathx.lerpF(REST_EXT, 0.02, k);
        self.pitch = 15.0 * k;
        self.jaw = 15.0 * k;
        self.sac = mathx.lerpF(1.0, 0.85, k);
    }

    // ── the hero's blade lands on the toad (latched one-per-swing) ───────────────────────
    fn tryHit(self: *Frog, blade: Blade) void {
        if (self.state == .dead) return; // no hitting a corpse
        if (!blade.active) {
            self.hitLatch = false; // window closed → the next swing may land again
            return;
        }
        if (self.hitLatch) return;
        const c = self.centerWorld();
        const reach = self.hurtRadius() + blade.r;
        // Swept: test this frame's blade segment AND last frame's, so a fast arc can't skip
        // the toad between frames.
        if (distPointSeg(c, blade.a, blade.b) <= reach or distPointSeg(c, blade.a0, blade.b0) <= reach) {
            self.hits += 1;
            self.hitLatch = true;
            self.flash = FLASH_DUR;
            // Damage + the two-tier stagger (poise → light flinch; stance → heavy stagger).
            switch (self.vit.hit(blade.hit)) {
                .death => self.enterDeath(),
                .heavy => self.enterStun(.stunheavy),
                .light => self.enterStun(.stunlight),
                .none => {},
            }
        }
    }

    // ── pose: build the 9 world matrices from the resolved channels ─────────────────────
    pub fn pose(self: *Frog) void {
        const fs = self.scale;
        // Body frame → world (per-toad uniform scale, pitch, face, then place at the seat).
        // NO squash here — the legs hang off this so they keep their size; squash rides BODY.
        const bframe = mul(
            scaleM(fs, fs, fs),
            mul3(rx(self.pitch), ry(mathx.degrees(self.facing)), tr(self.pos.x, self.lift, self.pos.z)),
        );
        const squash = scaleM(self.sxz, self.sy, self.sxz); // about the seat: flatten/widen or stretch

        var wx: [NP]rl.Matrix = undefined;
        wx[BODY] = mul(squash, bframe);
        wx[LJAW] = place(P_JAW, rx(self.jaw), wx[BODY]); // jaw + trunk share the squash
        wx[THROAT] = place(P_SAC, scaleM(self.sac, self.sac, self.sac), wx[BODY]);

        // Back legs: hip + knee fold off the (unsquashed) body frame.
        const hipDeg = (self.legExt - REST_EXT) * HIP_SWING;
        const kneeDeg = (self.legExt - REST_EXT) * KNEE_STRAIGHTEN;
        const kneeOff = v3(P_KNEE.x - P_HIP.x, P_KNEE.y - P_HIP.y, P_KNEE.z - P_HIP.z);
        wx[HAUNCH_L] = place(P_HIP, rx(-hipDeg), bframe);
        wx[SHANK_L] = place(kneeOff, rx(kneeDeg), wx[HAUNCH_L]);
        const hipR = v3(-P_HIP.x, P_HIP.y, P_HIP.z);
        const kneeOffR = v3(-kneeOff.x, kneeOff.y, kneeOff.z);
        wx[HAUNCH_R] = place(hipR, rx(-hipDeg), bframe);
        wx[SHANK_R] = place(kneeOffR, rx(kneeDeg), wx[HAUNCH_R]);

        // Front legs: a small forward reach.
        const armDeg = -28.0 * self.arm;
        wx[ARM_L] = place(P_SHOULDER, rx(armDeg), bframe);
        wx[ARM_R] = place(v3(-P_SHOULDER.x, P_SHOULDER.y, P_SHOULDER.z), rx(armDeg), bframe);
        self.xf = wx;
    }

    pub fn draw(self: *const Frog, model: *const Model) void {
        model.draw(&self.xf);
    }
};

// ── a KNOT of toads (a group of toads is literally a "knot") ────────────────────────────
// The shared model + the live instances. game.zig owns one of these; the meadow is dressed
// with the knot the way env.zig dresses it with props.
const COUNT = 4;

// Homes sit ≥12 m off the x≈0 avenue so a straight run down the path doesn't wake them (and
// so the hero-gait --shot stays clean) — they guard the flanks and the graveyard, waking
// when the player veers into the ruins. Seeds/scales vary so the knot never moves as one.
const Home = struct { x: f32, z: f32, yaw: f32, scale: f32, seed: f32 };
const homes = [COUNT]Home{
    .{ .x = 13.5, .z = -14.0, .yaw = mathx.radians(215), .scale = 1.08, .seed = 0.0 },
    .{ .x = -13.0, .z = -20.0, .yaw = mathx.radians(70), .scale = 0.94, .seed = 0.37 },
    .{ .x = 14.5, .z = -8.0, .yaw = mathx.radians(250), .scale = 1.0, .seed = 0.61 },
    .{ .x = -12.5, .z = -27.0, .yaw = mathx.radians(120), .scale = 1.14, .seed = 0.83 },
};

pub const Knot = struct {
    model: Model,
    frogs: [COUNT]Frog = undefined,

    pub fn init(shader: rl.Shader) Knot {
        var k = Knot{ .model = Model.init(shader) };
        for (homes, 0..) |h, i| {
            k.frogs[i] = Frog.spawn(mathx.ground(h.x, h.z), h.yaw, h.scale, h.seed);
        }
        return k;
    }
    pub fn setShader(self: *Knot, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    // Advance the whole knot; returns the STRONGEST blow any toad landed on the hero this
    // frame (null if none), for game.zig to apply to the hero's vitals.
    pub fn update(self: *Knot, dt: f32, hero: rl.Vector3, bounds: f32, blade: Blade) ?combat.Hit {
        var worst: ?combat.Hit = null;
        for (&self.frogs) |*f| {
            if (f.update(dt, hero, bounds, blade)) |h| {
                if (worst == null or h.dmg > worst.?.dmg) worst = h;
            }
        }
        return worst;
    }
    pub fn draw(self: *const Knot) void {
        for (&self.frogs) |*f| if (f.alive()) f.draw(&self.model);
    }
    pub fn totalHits(self: *const Knot) u32 {
        var n: u32 = 0;
        for (&self.frogs) |*f| n += f.hits;
        return n;
    }
    // How many toads are still standing (for a debug read-out / future clear-the-knot logic).
    pub fn aliveCount(self: *const Knot) u32 {
        var n: u32 = 0;
        for (&self.frogs) |*f| {
            if (f.alive()) n += 1;
        }
        return n;
    }
};

// ── the toad mesh (authored in the body frame; joints authored at their own origin) ─────
fn buildMeshes() [NP]rl.Mesh {
    var mesh: [NP]rl.Mesh = undefined;
    mesh[BODY] = bodyMesh();
    mesh[LJAW] = lowerJawMesh();
    mesh[THROAT] = throatMesh();
    mesh[HAUNCH_L] = thighMesh();
    mesh[SHANK_L] = shankMesh(1.0);
    mesh[HAUNCH_R] = thighMesh();
    mesh[SHANK_R] = shankMesh(-1.0);
    mesh[ARM_L] = armMesh();
    mesh[ARM_R] = armMesh();
    return mesh;
}

// A conical tooth from `bpos` along `dir` (unit) for `len`, base radius `r`.
fn tooth(b: *Builder, bpos: rl.Vector3, dir: rl.Vector3, len: f32, r: f32, col: rl.Color) void {
    b.addCylinder(bpos, v3(bpos.x + dir.x * len, bpos.y + dir.y * len, bpos.z + dir.z * len), r, 0.004, 5, col);
}

// One ragged row of nine teeth — uneven size/lean/spacing, the odd gap and snapped-off stub,
// bigger tusks at the corners. Seeded so the build stays deterministic. Shared by the upper
// (body) and lower (jaw) rows, which differ ONLY in these params; `shift` rebases the row
// into the jaw's local frame (P_JAW) for the lower teeth (zero for the uppers).
const ToothRow = struct {
    seed: u64,
    tuskLen: f32,
    toothLen: f32,
    tuskRad: f32,
    toothRad: f32,
    dirY: f32, // -1 = hang down (uppers), +1 = point up (lowers)
    zlean: f32, // base forward lean of each tooth
    z0: f32, // row's z origin at the lip line
    shift: rl.Vector3 = mathx.zero3,
};
fn toothRow(b: *Builder, cfg: ToothRow) void {
    var trng = mathx.Rng.init(cfg.seed);
    var i: i32 = -4;
    while (i <= 4) : (i += 1) {
        if (trng.float() < 0.14) continue; // a missing tooth
        const fx = @as(f32, @floatFromInt(i)) * 0.072 + trng.range(-0.016, 0.016); // uneven spacing
        const tusk = @abs(i) >= 3 and trng.float() < 0.8;
        const broken = trng.float() < 0.15; // a snapped-off stub
        const len = (if (tusk) cfg.tuskLen else cfg.toothLen) * (if (broken) trng.range(0.3, 0.5) else trng.range(0.72, 1.25));
        const rad = (if (tusk) cfg.tuskRad else cfg.toothRad) * trng.range(0.8, 1.2);
        const dir = v3(trng.range(-0.13, 0.13), cfg.dirY, cfg.zlean + trng.range(-0.05, 0.10)); // each leans its own way
        const y = 0.235 + trng.range(-0.008, 0.012);
        tooth(b, v3(fx - cfg.shift.x, y - cfg.shift.y, cfg.z0 - cfg.shift.z), dir, len, rad, if (trng.float() < 0.5) TOOTH else TOOTH_DK);
    }
}

// A squat, hunched toad: a fat vertical dome (belly widening to a humped back) with a broad
// warty head + bulging eyes jutting forward at the mouth line. Compact, wider than long. The
// lower jaw + throat sac are separate (animated) parts.
fn bodyMesh() rl.Mesh {
    var b = Builder.init();
    // Body: a fat dome — belly (bottom) widening up to the midsection, then humping up and
    // narrowing to the back crown (apex set a touch REAR so the profile leans forward). Many
    // sides so it reads round from every angle (no lizard tail).
    b.addCylinder(v3(0, 0.02, -0.02), v3(0, 0.28, -0.03), 0.24, 0.42, 14, HIDE); // lower/mid
    b.addCylinder(v3(0, 0.28, -0.03), v3(0, 0.60, -0.10), 0.42, 0.15, 14, HIDE); // humped back
    b.addCube(v3(0, 0.10, 0.08), v3(0.46, 0.16, 0.44), BELLY); // pale sickly belly, low + front

    // Broad head jutting forward at the mouth line (~y0.24), warty brow above.
    b.addCube(v3(0, 0.34, 0.34), v3(0.62, 0.24, 0.34), HIDE); // head block / brow
    b.addCube(v3(0, 0.255, 0.46), v3(0.58, 0.09, 0.16), HIDE_DK); // upper lip / snout rim
    b.addCube(v3(0, 0.30, 0.32), v3(0.48, 0.06, 0.34), MAW); // roof of the mouth (gape not hollow)
    b.addCube(v3(0, 0.25, 0.18), v3(0.42, 0.16, 0.14), MAW); // gullet — a dark cavern behind the teeth when agape

    // Bulging eyes on top of the head, set wide — bony brow, amber emissive dome, slit pupil.
    for ([_]f32{ -1, 1 }) |sgn| {
        const ex = 0.19 * sgn;
        b.addCube(v3(ex, 0.46, 0.30), v3(0.24, 0.13, 0.24), HIDE_DK); // brow socket
        b.addCylinder(v3(ex, 0.43, 0.31), v3(ex, 0.63, 0.31), 0.135, 0.085, 9, HIDE_LT); // eye mound
        b.addCylinder(v3(ex, 0.575, 0.315), v3(ex, 0.645, 0.32), 0.10, 0.05, 9, EYE); // amber iris (emissive)
        b.addCube(v3(ex, 0.62, 0.36), v3(0.038, 0.07, 0.038), PUPIL); // slit pupil, facing forward
    }
    // Nostrils at the snout tip.
    b.addCube(v3(0.08, 0.40, 0.54), v3(0.035, 0.035, 0.035), HIDE_DK);
    b.addCube(v3(-0.08, 0.40, 0.54), v3(0.035, 0.035, 0.035), HIDE_DK);

    // Upper teeth: a RAGGED row hanging from the lip — uneven size / lean / spacing, the odd
    // gap and snapped-off stub, big tusks near the corners. Wabi-sabi: no two alike (seeded,
    // so the build stays deterministic).
    toothRow(&b, .{ .seed = 9173, .tuskLen = 0.21, .toothLen = 0.13, .tuskRad = 0.046, .toothRad = 0.030, .dirY = -1, .zlean = 0.10, .z0 = 0.50 });

    // Warty humps scattered over the domed back (deterministic seed, like the flora clumps).
    var rng = mathx.Rng.init(4207);
    var w: i32 = 0;
    while (w < 13) : (w += 1) {
        const a = rng.angle();
        const h = rng.range(0.30, 0.56);
        const rr = mathx.lerpF(0.40, 0.16, (h - 0.28) / 0.32) - 0.015; // ride the dome surface
        const wx = mathx.cosf(a) * rr;
        const wz = -0.05 + mathx.sinf(a) * rr;
        b.addCube(v3(wx, h, wz), v3(rng.range(0.05, 0.09), rng.range(0.03, 0.055), rng.range(0.05, 0.09)), if (rng.float() < 0.5) HIDE_DK else HIDE_LT);
    }
    return b.toMesh();
}

// Lower jaw — authored about the hinge (P_JAW) at the origin, extending forward. Slab, gum,
// upward teeth, a tongue; opens by rotating about X.
fn lowerJawMesh() rl.Mesh {
    var b = Builder.init();
    // Author in body-frame targets, shifted so the hinge sits at the origin.
    const j = struct {
        fn at(bx: f32, by: f32, bz: f32) rl.Vector3 {
            return v3(bx - P_JAW.x, by - P_JAW.y, bz - P_JAW.z);
        }
    }.at;
    b.addCube(j(0, 0.185, 0.28), v3(0.58, 0.09, 0.46), HIDE); // jaw slab
    b.addCube(j(0, 0.14, 0.26), v3(0.52, 0.07, 0.42), BELLY); // pale chin underside
    b.addCube(j(0, 0.225, 0.34), v3(0.48, 0.03, 0.30), TONGUE); // fleshy floor / tongue
    b.addCube(j(0, 0.235, 0.49), v3(0.50, 0.05, 0.09), HIDE_DK); // lower lip rim
    // Lower teeth point UP from the rim — the same ragged wabi-sabi treatment, a different
    // seed so they don't mirror the uppers (they interlock unevenly).
    toothRow(&b, .{ .seed = 6421, .tuskLen = 0.19, .toothLen = 0.115, .tuskRad = 0.042, .toothRad = 0.028, .dirY = 1, .zlean = 0.08, .z0 = 0.49, .shift = P_JAW });
    return b.toMesh();
}

// Throat sac — authored about P_SAC at the origin; a pale distendable pouch under the chin.
fn throatMesh() rl.Mesh {
    var b = Builder.init();
    b.addCylinder(v3(0, 0.06, 0), v3(0, -0.04, 0.01), 0.19, 0.24, 10, SAC);
    b.addCylinder(v3(0, -0.04, 0.01), v3(0, -0.13, 0.01), 0.24, 0.12, 10, SAC);
    b.addCube(v3(0, -0.02, 0.05), v3(0.34, 0.18, 0.24), SAC); // fill the pouch out front
    return b.toMesh();
}

// Back-leg thigh — authored at the hip origin, a fat haunch reaching up to the folded knee.
fn thighMesh() rl.Mesh {
    var b = Builder.init();
    const knee = v3(P_KNEE.x - P_HIP.x, P_KNEE.y - P_HIP.y, P_KNEE.z - P_HIP.z);
    b.addCylinder(v3(0, 0, 0), knee, 0.20, 0.13, 10, HIDE);
    b.addCylinder(v3(0, 0.03, -0.02), v3(knee.x * 0.55, knee.y * 0.55, knee.z * 0.55 - 0.03), 0.225, 0.17, 10, HIDE_LT); // big muscle bulge
    return b.toMesh();
}

// Back-leg shank + webbed foot — authored at the knee origin, dropping down-forward to the
// ground. `side` mirrors the toe splay. The long foot is the frog read.
fn shankMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    // Foot target relative to the knee (knee sits at P_KNEE in the body frame; foot ~ground,
    // forward + slightly out).
    const foot = v3(-0.10 * side, 0.0 - P_KNEE.y, 0.16 - P_KNEE.z);
    b.addCylinder(v3(0, 0, 0), foot, 0.115, 0.05, 8, HIDE); // shin
    // Webbed foot: a flat pad + three splayed toes fanning forward.
    const heel = foot;
    b.addCube(v3(heel.x, heel.y + 0.015, heel.z + 0.05), v3(0.17, 0.035, 0.15), HIDE_DK);
    for ([_]f32{ -1, 0, 1 }) |t| {
        const toe = v3(heel.x + t * 0.12, heel.y + 0.005, heel.z + 0.20);
        b.addCylinder(v3(heel.x + t * 0.05, heel.y + 0.02, heel.z + 0.05), toe, 0.032, 0.012, 5, HIDE_DK);
        b.addCube(v3(toe.x, toe.y, toe.z + 0.01), v3(0.03, 0.015, 0.045), CLAW); // little claw tip
    }
    return b.toMesh();
}

// Front leg — authored at the shoulder origin; small, splayed, planting forward.
fn armMesh() rl.Mesh {
    var b = Builder.init();
    const hand = v3(0.02, -0.26, 0.16);
    b.addCylinder(v3(0, 0, 0), hand, 0.075, 0.045, 8, HIDE);
    b.addCube(v3(hand.x, hand.y - 0.005, hand.z + 0.03), v3(0.12, 0.03, 0.11), HIDE_DK); // splayed hand
    for ([_]f32{ -1, 0, 1 }) |t| {
        b.addCube(v3(hand.x + t * 0.05, hand.y - 0.005, hand.z + 0.10), v3(0.022, 0.02, 0.06), CLAW);
    }
    return b.toMesh();
}

// Shortest distance from point `p` to segment `a`-`b` (swept-blade hit test).
fn distPointSeg(p: rl.Vector3, a: rl.Vector3, b: rl.Vector3) f32 {
    const ab = mathx.subV(b, a);
    const denom = mathx.lenV(ab);
    if (denom < 1e-6) return mathx.lenV(mathx.subV(p, a));
    const t = mathx.clampF((mathx.subV(p, a).x * ab.x + mathx.subV(p, a).y * ab.y + mathx.subV(p, a).z * ab.z) / (denom * denom), 0, 1);
    const proj = v3(a.x + ab.x * t, a.y + ab.y * t, a.z + ab.z * t);
    return mathx.lenV(mathx.subV(p, proj));
}

// ── invariants under test (pure logic only — meshes/poses need a GPU window) ────────────
test "classify: ranges pick chomp < lunge < hop < rest, and cooldowns gate" {
    try std.testing.expectEqual(Choice.rest, classify(AGGRO_R + 1, true, true));
    try std.testing.expectEqual(Choice.hop, classify((LUNGE_R + AGGRO_R) * 0.5, true, true));
    try std.testing.expectEqual(Choice.lunge, classify(LUNGE_R - 0.5, true, true));
    try std.testing.expectEqual(Choice.hop, classify(LUNGE_R - 0.5, false, true)); // lunge cooling → hop in
    try std.testing.expectEqual(Choice.chomp, classify(BITE_R - 0.2, true, true));
    try std.testing.expectEqual(Choice.wait, classify(BITE_R - 0.2, true, false)); // in bite range, chomp cooling
}

test "range thresholds are ordered and inside senses" {
    try std.testing.expect(BITE_R < LUNGE_R and LUNGE_R < AGGRO_R);
    try std.testing.expect(KEEP_OFF < BITE_R);
}

test "distPointSeg: endpoint, midpoint, and perpendicular cases" {
    const a = v3(0, 0, 0);
    const b = v3(2, 0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 1), distPointSeg(v3(1, 1, 0), a, b), 1e-5); // perpendicular
    try std.testing.expectApproxEqAbs(@as(f32, 1), distPointSeg(v3(-1, 0, 0), a, b), 1e-5); // past the end → to endpoint
    try std.testing.expectApproxEqAbs(@as(f32, 0), distPointSeg(v3(1, 0, 0), a, b), 1e-5); // on the segment
}

test "a hop's flight parabola starts and ends on the ground and peaks at the apex" {
    var f = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    f.hopApex = HOP_APEX;
    f.resolveFlight(0.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), f.lift, 1e-5);
    f.resolveFlight(1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), f.lift, 1e-5);
    f.resolveFlight(0.5);
    try std.testing.expectApproxEqAbs(HOP_APEX, f.lift, 1e-5);
}
