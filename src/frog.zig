const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// ── THE GAPING TOAD ───────────────────────────────────────────────────────────────────
// A squat warty bog-toad, ~2/3 the hero's mass, all mouth and teeth. It doesn't walk — it HOPS,
// coiling low then firing off its haunches; it closes the last gap with a committed LUNGE that
// leaves it winded and wide open; up close it gapes its throat sac and CHOMPS.
//
// Where the hero is an anthropometric FK skeleton, the toad is a shallow 9-part rig whose LIFE
// is SQUASH & STRETCH — the coil, the airborne stretch, the landing splat, the throat balloon —
// plus a hinged jaw and folding haunches.
//
// ART DIRECTION (exaggerated + readable):
//   IDLE  : low and breathing, throat pulsing, the odd twitch. Alive, waiting.
//   HOP   : the frog verb. COIL (squash, knees over the back, a beat of anticipation) → LAUNCH
//           (haunches fire, body STRETCHES thin, nose up) → ballistic arc → LAND (front legs
//           reach, body SPLATS wide). It keeps bounding, small settles between.
//   LUNGE : a big committed leap — a DEEP readable coil, a long flat arc, then a heavy landing
//           into a RECOVERY where it lies splayed and spent. That beat is the opening.
//   CHOMP : it rears, the sac BALLOONS and the jaw gapes (the tell), then a fast SNAP.
//   Nothing parks dead: hops overshoot into a splat, the chomp recoils, idle keeps breathing.
//
// Combat is the SHARED path — foe.strike for the hero's blade, combat.Vitals for the meters,
// death into a grace-mote dissipation. See foe.zig's contract.

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
/// …and the same lamp turned RED for the lunge (owner's call): the tell arrives with the coil and leaves
/// on the landing, so the one thing on the toad you were already watching is what announces the pounce.
/// HOTTER as well as redder — a lower alpha drives the emissive harder, so it flares rather than just
/// changing hue, which is what makes it read across a field.
const EYE_HOT = rgba(255, 62, 34, 62);
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
const LUNGE_APEX = 1.28; // lunge arc peak height — a big, violent pounce
const KEEP_OFF = BITE_R - 0.25; // an approach hop stops here, just shy of bite range

// Phase durations (seconds).
const HOP_COIL = 0.16;
const HOP_FLIGHT = 0.40;
const HOP_LAND = 0.16;
const HOP_SETTLE_AGGRO = 0.07; // brief settle between bounds when hunting (keeps it fast)
const LUNGE_COIL = 0.70; // the readable wind-up tell — a LONG, deep, unmistakable load (slow to wind, so it reads early)
const LUNGE_FLIGHT = 0.34; // …then FIRES fast — a short, violent leap once it commits
const LUNGE_LAND = 0.12;
const RECOVER_DUR = 0.78; // the winded, wide-open window after a lunge
const CHOMP_GAPE = 0.42; // sac balloons, jaw yawns (the tell) — held long so the bite reads early
const CHOMP_SNAP = 0.11; // jaws slam
const CHOMP_RECOVER = 0.42;
const CHOMP_JAW = 64.0; // how wide the maw yawns (deg) — a big, readable gape
const CHOMP_SAC = 1.95; // throat-sac inflate at full gape (scale)
const LUNGE_CD = 2.1; // cooldowns keep it from spamming
const CHOMP_CD = 0.7;
const TURN_RATE = 5.0; // rad/s (~285°/s) — the toad's MAX TURNING SPEED everywhere (idle
//   tracking, coil steering; THE turn-feel knob). Hops/lunges LAUNCH ALONG THE BODY, never
//   snapping onto the hero — so a tight strafe still beats the committed leaps.

// Leg fold: legExt 0 = fully coiled, 1 = fully extended; the sit pose is REST_EXT. Hip &
// knee rotate away from the authored sit pose by these swings across the 0..1 range.
const REST_EXT = 0.34;
const HIP_SWING = 66.0; // + extends the thigh back-and-down (push-off)
const KNEE_STRAIGHTEN = 104.0; // + straightens the knee out of its tuck
const FLASH_DUR = foe.FLASH_DUR; // how long a landed hit flares the toad blood-red (gfx hitFlash) + the debug wires
const SHOVE_DECAY = 7.0; // 1/s — the hit shove bleeds off fast (a jolt off the blow, not a slide)
const DISS_DUR = 0.95; // seconds the corpse takes to dissipate into motes once the collapse is done

// ── telegraph FX ────────────────────────────────────────────────────────────────────
// A tiny per-toad particle pool (unlit spheres drawn in the lit pass) that SELLS the tells:
// dust dug up as the lunge loads, an amber charge glow gathering at the maw, drool flung on
// the gape, and a big radial dust SLAM at the impact point on a lunge landing.
const FX_MAX = 40; // per-toad budget (ring buffer — the oldest particle is overwritten)
const DUST = foe.DUST; // kicked-up bog dust — the SHARED one (see foe.zig: it was two copies)
const EMBER = rgba(252, 196, 84, 150); // amber charge glow — the lamp-eye colour, gathering (kept sheer so glints layer, not blob)
const SPIT = rgba(176, 190, 150, 140); // pale sickly drool / spit fling
const BLOOD = rgba(112, 22, 16, 235); // hit spray — dark oxblood, kin to the maw (unlit droplets). The
//   toad's OWN: the ogre bleeds a darker ichor, which is why this one stays local.
const MOTE = foe.MOTE; // death dissipation — the shared grace-gold every corpse goes out in

// ── vitals (LOW poise, per the brief: "frogs have low poise") ──────────────────────────
const HP_MAX = 46.0;
const POISE_MAX = 8.0; // BELOW the hero's light poise damage (10): every landed light
//   FLINCHES a full-poise toad, so a clean hit on a coil/gape windup always interrupts and
//   RESETS the attack (the cooldown set at attack start keeps it from instantly resuming).
const STANCE_MAX = 26.0; // low — a few flinches cascade into the heavy stagger (3rd chained light crumples)
// What the toad's own attacks do to the HERO (guard→tip data flows the other way; these
// are handed out when a chomp SNAP / lunge SLAM connects). The lunge is a heavy body-blow.
const CHOMP_HIT = combat.Hit{ .dmg = 13, .poise = 15 }; // eased down from 16 (owner: lower dmg a bit)
const LUNGE_HIT = combat.Hit{ .dmg = 19, .poise = 26, .stance = 8 }; // eased down from 24 — still a real slam
const HERO_REACH = foe.HERO_REACH; // hero footprint added to the toad's attack range for the hit test
// The lunge is a body-SLAM that crashes down in FRONT of the toad: only a hero inside the
// frontal impact zone is crushed (one beside or behind is clear), matching the forward dust
// burst. Reach is from the seat; the arc gate is what makes it front-only.
const LUNGE_IMPACT_R = 1.9; // frontal slam reach from the seat
const LUNGE_FRONT_DOT = 0.25; // hero must lie within the frontal arc (~±76°) to be caught
const LUNGE_IMPACT_FWD = 0.6; // dust-burst / impact-zone centre, this far ahead of the seat (pre-scale)
/// Embers a second dragged off the body through the lunge's flight (`emitLungeTrail`). High, because the
/// flight is `LUNGE_FLIGHT` long — a rate that reads as continuous over a third of a second has to be.
const TRAIL_RATE: f32 = 150.0;
const DEATH_DUR = 1.25; // collapse-and-still before the corpse is removed from play
/// RUNES a toad is worth. The cheapest kill in the world and the yardstick the other two are set
/// against: an archer is two of these, the giant fifteen.
pub const RUNES: u32 = 60;

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

// One telegraph particle — the SHARED shape + integrator + draw (foe.zig); only the AUTHORING of
// the bursts below (dust / charge / drool / blood / motes) is the toad's own.
const Particle = foe.Particle;

// The shared toad meshes + material (built once, like env.models); every Frog draws these
// with its own per-part matrices. Meshes live the whole program (leak at exit — fine).
pub const Model = struct {
    mesh: [NP]rl.Mesh,
    /// THE IRISES, twice: calm amber and hot RED. Their own mesh rather than part of the head because a
    /// baked vertex colour cannot change, and the eyes going red is a TELL — it has to arrive with the
    /// wind-up and leave with the landing. Two small meshes and an index is the whole mechanism; the
    /// alternative was a per-draw tint uniform, which would redden the warts and the teeth with them.
    eyes: [2]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("frog material");
        mat.shader = shader;
        return .{ .mesh = buildMeshes(), .eyes = [2]rl.Mesh{ eyeMesh(EYE), eyeMesh(EYE_HOT) }, .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, xf: *const [NP]rl.Matrix, hot: bool) void {
        for (0..NP) |i| rl.drawMesh(self.mesh[i], self.mat, xf[i]);
        // On the BODY's matrix, which is the part the eyes are authored in (see `bodyMesh`).
        rl.drawMesh(self.eyes[@intFromBool(hot)], self.mat, xf[BODY]);
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
    hopAim: rl.Vector3 = mathx.zero3, // the INTENT point committed at decision (steered onto through the coil)
    hopReach: f32 = 0, // ground distance the leap covers (committed at decision)
    launched: bool = false, // takeoff done — hopTo re-aimed along the body (see updateHop)
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
    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX),
    hits: u32 = 0, // total blows landed (debug read-out)
    hitLatch: bool = false, // one hit per swing: set on contact, cleared when the blade goes inactive
    flash: f32 = 0, // blood-red body flash after a registered hit (fades over FLASH_DUR)
    shove: rl.Vector3 = mathx.zero3, // knockback velocity a landed blow imparts (decays fast)
    heroHit: ?combat.Hit = null, // this frame's blow ON THE HERO (chomp/lunge connect), read by game.zig
    heroLatch: bool = false, // one hero-hit per attack action (chomp/lunge)
    justDied: bool = false, // true only on the frame a blow kills it (game.zig keys the kill beat off this)
    fade: f32 = 0, // death dissipation 0..1 — pose() shrinks + sinks the corpse by it
    gone: bool = false, // corpse removed from play (dissipation finished) — skipped everywhere

    // telegraph FX (see the FX tuning block): a ring buffer of particles, a rate-based emit
    // carry so trickles are frame-rate independent, and a seeded RNG for the scatter.
    fx: [FX_MAX]Particle = [_]Particle{.{}} ** FX_MAX,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [NP]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Frog {
        var f = Frog{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * SCALE, .seed = seed };
        // @abs first: @intFromFloat into an UNSIGNED type is illegal behaviour for a negative
        // input, and `spawn` is public with no documented seed sign (a -0.5 wabi-sabi seed would
        // panic in Debug/ReleaseSafe). Every current seed is >= 0, so the field is unchanged.
        f.fxRng = mathx.Rng.init(@as(u64, @intFromFloat(@abs(seed) * 104729.0)) +% 1); // per-toad scatter, deterministic
        f.idleWait = 1.0 + seed * 2.0;
        f.resolveIdle();
        f.pose();
        return f;
    }

    // Heights measured from `pos.y` — THE GROUND UNDER IT — plus `lift`, which is the hop's height above
    // that ground. Pinned to the datum instead, a toad on a bank keeps its hurt sphere down in the field.
    pub fn centerWorld(self: *const Frog) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + BODY_CY * self.scale + self.lift, self.pos.z);
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
        return v3(self.pos.x, self.pos.y + 0.30 * self.scale + self.lift, self.pos.z);
    }
    // Airborne mid-hop/lunge — ground collision leaves it be while it's in the air.
    pub fn airborne(self: *const Frog) bool {
        return self.lift > 0.04;
    }
    // Top of the domed back in world space — where the floating HP bar rides.
    pub fn topWorld(self: *const Frog) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + 0.80 * self.scale + self.lift, self.pos.z);
    }
    // A live combatant (a corpse whose death anim has finished is skipped everywhere).
    pub fn alive(self: *const Frog) bool {
        return !self.gone;
    }
    // Reeling from a stagger or dying — the wide-open window / no threat.
    pub fn staggered(self: *const Frog) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    // Collapsed/dissipating — a corpse (HP bar hides, nothing should read it as a threat).
    pub fn dying(self: *const Frog) bool {
        return self.state == .dead;
    }
    // Normalized 0..1 strength of the blood-red hit flash (drives gfx's hitFlash uniform).
    pub fn flashFrac(self: *const Frog) f32 {
        return foe.flashFrac(self.flash);
    }

    // ── actions ─────────────────────────────────────────────────────────────────────
    fn faceToward(self: *Frog, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt); // shared — see foe.zig
    }

    // Begin a hop toward `to` (clamped to bounds); `lunge` = the big committed leap.
    // NO snap-turn: the intent point is only an AIM — the toad steers onto it through the coil
    // and the leap LAUNCHES ALONG THE BODY at takeoff, so circling a coiled toad gets around it.
    pub fn startHop(self: *Frog, to: rl.Vector3, bounds: f32, lunge: bool) void {
        self.hopAim = v3(mathx.clampF(to.x, -bounds, bounds), 0, mathx.clampF(to.z, -bounds, bounds));
        self.hopReach = mathx.distXZ(self.pos, self.hopAim);
        self.hopFrom = self.pos;
        self.hopTo = self.hopAim; // provisional — re-aimed along facing at launch
        self.launched = false;
        self.isLunge = lunge;
        self.hopApex = if (lunge) LUNGE_APEX else HOP_APEX;
        self.hopDur = if (lunge) LUNGE_FLIGHT else HOP_FLIGHT * mathx.clampF(0.5 + self.hopReach / HOP_REACH, 0.6, 1.5);
        self.state = if (lunge) .lunge else .hop;
        self.t = 0;
        self.heroLatch = false; // a fresh action gets one chance to land on the hero
        // The LUNGE announces itself at the top of its long coil — that croak IS the tell, and it
        // has to arrive with the wind-up rather than with the leap or it teaches nothing.
        sfx.world(if (lunge) .toad_lunge else .toad_hop, self.pos);
    }
    pub fn startChomp(self: *Frog) void {
        self.state = .chomp;
        self.t = 0;
        self.heroLatch = false;
        sfx.world(.toad_gape, self.pos); // the sac ballooning: the bite's own tell
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
        self.justDied = true; // game.zig keys the kill beat (rumble/shake) off this frame
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
    // The lunge SLAM: like tryBite, but FRONT-only — the hero must be inside the reach AND
    // within the toad's frontal arc. A hero beside or behind the landing is clear (unless
    // they're standing right on top of it), matching the dust burst thrown out front.
    fn tryImpact(self: *Frog, hero: rl.Vector3, h: combat.Hit) void {
        if (self.heroLatch) return;
        const d = mathx.distXZ(self.pos, hero);
        if (d > LUNGE_IMPACT_R + HERO_REACH) return;
        const to = mathx.dirXZ(self.pos, hero);
        const fwd = self.fdir();
        const front = to.x * fwd.x + to.z * fwd.z; // cos of the angle from facing to the hero
        if (d > 0.35 and front < LUNGE_FRONT_DOT) return; // off to the side / behind the slam
        self.heroHit = h;
        self.heroLatch = true;
    }

    // ── per-frame update ──────────────────────────────────────────────────────────────
    // Advance AI + animation for one frame; `hero` drives senses, `blade` the hero's swing.
    // Returns the blow this toad landed on the HERO this frame (null if none / it's a corpse).
    pub fn update(self: *Frog, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            self.updateFx(dt); // a removed corpse's last motes keep drifting out
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        self.vit.tick(dt); // poise/stance regenerate between hits (relent and it recovers)
        self.elapsed += dt;
        self.lungeCd = mathx.maxF(0, self.lungeCd - dt);
        self.chompCd = mathx.maxF(0, self.chompCd - dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        self.t += dt;
        self.updateFx(dt); // advance live particles (bursts from any state keep animating)
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt); // the knockback off a landed blow

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
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enterIdle(0.02);
            },
            .stunheavy => {
                self.resolveStunHeavy();
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enterIdle(0.06);
            },
            .dead => {
                self.resolveDeath();
                // The corpse DISSIPATES, ER-style: once the collapse settles it breaks
                // into rising grace-gold motes while pose() shrinks + sinks it away —
                // never a hard vanish. Only then is the slot retired.
                if (self.t >= DEATH_DUR) {
                    self.fade = mathx.smoothstep(DEATH_DUR, DEATH_DUR + DISS_DUR, self.t);
                    self.emitDissolve(dt);
                    if (self.t >= DEATH_DUR + DISS_DUR) self.gone = true;
                }
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
                // Land just short of the hero (don't leap past them). FLOORED AT 0 like the hop
                // below it: `classify` only returns `.lunge` past BITE_R and KEEP_OFF is inside
                // that, so the difference is positive today — but the two branches computing the
                // same "stop short of him" distance with only one of them guarded means a retune
                // that lifted KEEP_OFF to BITE_R would make the toad lunge BACKWARDS, away from
                // the hero, with nothing in the code to say so (the relation is asserted in a test
                // and nowhere else).
                const dir = mathx.dirXZ(self.pos, hero);
                const reach = mathx.minF(mathx.maxF(0, d - KEEP_OFF), LUNGE_R);
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
            // COIL: hold at the takeoff spot, steering at the CAPPED turn rate, and load.
            // A hop tracks the live hero; a lunge steers only onto its COMMITTED aim point
            // (where you WERE at the decision) — the long tell stays honestly dodgeable.
            if (self.isLunge) self.faceToward(self.hopAim, dt) else self.faceToward(hero, dt);
            const k = mathx.smoothstep(0, coil, self.t);
            self.resolveCoil(k, self.isLunge);
            if (self.isLunge) self.emitCoil(dt, k); // dust dug up + amber charge — the big tell
        } else if (self.t < coil + flight) {
            if (!self.launched) {
                // TAKEOFF: the leap goes where the BODY points (however far the coil's
                // capped steering actually got), with the reach committed at decision.
                self.launched = true;
                self.hopFrom = self.pos;
                const f = self.fdir();
                self.hopTo = v3(
                    mathx.clampF(self.pos.x + f.x * self.hopReach, -bounds, bounds),
                    0,
                    mathx.clampF(self.pos.z + f.z * self.hopReach, -bounds, bounds),
                );
            }
            const s = (self.t - coil) / flight; // 0..1 across the arc
            // Advance horizontally by an INCREMENT (velocity·dt), NOT an absolute lerp from a
            // stale hopFrom: this way a collision nudge mid-arc just deflects the leap instead
            // of the next frame snapping the toad back to its takeoff point (the "warp" bug).
            const inv = 1.0 / flight;
            self.pos.x += (self.hopTo.x - self.hopFrom.x) * inv * dt;
            self.pos.z += (self.hopTo.z - self.hopFrom.z) * inv * dt;
            self.resolveFlight(s);
            if (self.isLunge) self.emitLungeTrail(dt, s);
        } else {
            // Landed: hold wherever we ended up (collision may still adjust it) and splat —
            // do NOT re-snap to hopTo, which would clobber a collision push on touchdown.
            const k = mathx.smoothstep(0, land, self.t - coil - flight);
            self.resolveLand(k);
            // Fire the impact dust ONCE, the frame we touch down (a big front-slam telegraph).
            if ((self.t - dt) < coil + flight) {
                // …at its FEET, which `pos` already is now that it carries the ground height.
                if (self.isLunge) self.dustBurst(self.impactWorld(), 32, 4.4, 0.30) else self.dustBurst(self.pos, 8, 1.8, 0.16);
            }
            if (self.isLunge) self.tryImpact(hero, LUNGE_HIT); // the body-slam connects — FRONT zone only
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
            const k = mathx.smoothstep(0, CHOMP_GAPE, self.t);
            self.resolveGape(k);
            self.emitGape(dt, k); // amber charge gathers + drool strings from the maw
        } else if (self.t < CHOMP_GAPE + CHOMP_SNAP) {
            if ((self.t - dt) < CHOMP_GAPE) {
                self.spitSpray(); // jaws slam → a spray flung forward
                sfx.world(.toad_chomp, self.pos);
            }
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
        const deep: f32 = if (lunge) 1.75 else 1.0; // the lunge coils MUCH deeper (a bigger, longer, more violent tell)
        self.sy = 1.0 - 0.30 * k * deep; // squash down
        self.sxz = 1.0 + 0.18 * k * deep; // spread wide
        self.legExt = mathx.lerpF(REST_EXT, 0.05, k); // knees stack up over the back
        self.pitch = -6.0 * k * deep; // nose tips up, ready to leap
        self.arm = 0.15 * k;
        // The throat swells + jaw cracks open on a lunge load — extra read that a big one's coming.
        const sacGain: f32 = if (lunge) 0.28 else 0.10;
        self.sac = 1.0 + sacGain * k;
        self.jaw = if (lunge) 12.0 * k else 0.0;
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
        const u = mathx.clampF(self.t / combat.FOE_LIGHT_STUN_DUR, 0, 1);
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
        const u = mathx.clampF(self.t / combat.FOE_HEAVY_STUN_DUR, 0, 1);
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
    fn tryHit(self: *Frog, blade: foe.Blade) void {
        if (self.state == .dead) return; // no hitting a corpse
        // The SHARED strike behaviour (foe.zig): swept hurt-sphere test + one-hit latch +
        // damage; returns the contact + sweep dir + reaction. The toad lays ITS FX on top.
        const s = foe.strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), blade) orelse return;
        self.hits += 1;
        self.flash = FLASH_DUR;
        const heavyBlow = blade.hit.stance > 0;
        // The blow READS at the wound: blood flung along the sweep, body knocked the same way.
        self.bloodBurst(s.contact, s.dir, if (heavyBlow) 14 else 9, if (heavyBlow) 2.6 else 1.9);
        self.shove = mathx.scaleV(s.dir, if (heavyBlow) 1.9 else 1.25);
        sfx.world(.toad_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                self.bloodBurst(s.contact, s.dir, 10, 2.2); // the killing blow bleeds extra
                sfx.world(.toad_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    /// THE LUNGE'S WAKE — the thing that makes a leap read as dangerous rather than as a jump. Two layers,
    /// emitted every frame of the flight and NOT rate-gated: a leap is a third of a second, and a trail
    /// with gaps in it is a trail you do not see at all.
    ///
    ///  - CHARGE, dragged off the body: amber embers with a NEGATIVE gravity, so the wake hangs in the air
    ///    behind it and marks the path the slam is coming down.
    ///  - DUST, torn off the ground under it, thrown backwards along the arc — that back-spray is what
    ///    says "this is being propelled" instead of "this is falling".
    ///
    /// Heaviest at the START of the arc (`1 - s`), where the speed is: a wake that thickened on the way
    /// down would read as braking.
    fn emitLungeTrail(self: *Frog, dt: f32, s: f32) void {
        const c = self.centerWorld();
        const back = mathx.scaleV(self.fdir(), -1);
        const heavy = 1.0 - 0.55 * s;
        var i: u32 = 0;
        const n: u32 = @intFromFloat(@max(1.0, TRAIL_RATE * heavy * dt));
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const r = self.fxRng.range(0.05, 0.42) * self.scale;
            self.emit(
                v3(c.x + mathx.cosf(a) * r, c.y + self.fxRng.signed() * 0.30 * self.scale, c.z + mathx.sinf(a) * r),
                v3(back.x * self.fxRng.range(0.5, 2.2), self.fxRng.range(-0.1, 0.7), back.z * self.fxRng.range(0.5, 2.2)),
                self.fxRng.range(0.26, 0.58),
                self.fxRng.range(0.030, 0.075) * self.scale,
                0.004,
                EMBER,
                -0.55,
            );
        }
        // …and the ground it is skimming, kicked up behind the feet.
        if (self.fxRng.float() < dt * 44.0 * heavy) {
            self.emit(
                v3(self.pos.x + self.fxRng.signed() * 0.3 * self.scale, self.pos.y + 0.05, self.pos.z + self.fxRng.signed() * 0.3 * self.scale),
                v3(back.x * self.fxRng.range(1.0, 2.6), self.fxRng.range(0.5, 1.6), back.z * self.fxRng.range(1.0, 2.6)),
                self.fxRng.range(0.3, 0.62),
                self.fxRng.range(0.05, 0.12) * self.scale,
                0.01,
                foe.DUST,
                2.6,
            );
        }
    }

    // A burst of dark blood flung from the CONTACT POINT, biased along the blade's sweep
    // (with a little radial scatter and lob) — gravity brings it down fast so the ground
    // catches the spatter. Unlit, like all the telegraph FX.
    fn bloodBurst(self: *Frog, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.4, 1.0) * spd;
            const vel = v3(
                dir.x * sp + mathx.cosf(a) * self.fxRng.range(0.15, 0.8),
                self.fxRng.range(0.7, 2.4),
                dir.z * sp + mathx.sinf(a) * self.fxRng.range(0.15, 0.8),
            );
            self.emit(at, vel, self.fxRng.range(0.28, 0.5), self.fxRng.range(0.028, 0.055) * self.scale, 0.008, BLOOD, 7.5);
        }
    }

    // Death dissipation trickle: grace-gold motes rising off the sinking corpse, cut with
    // a little settling dust. Runs every frame of the fade (rate-based, like emitCoil).
    fn emitDissolve(self: *Frog, dt: f32) void {
        self.fxAccum += 44.0 * (1.0 - 0.6 * self.fade) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.05, 0.55) * self.scale * (1.0 - 0.6 * self.fade);
            const p = v3(self.pos.x + mathx.cosf(a) * rr, self.fxRng.range(0.03, 0.35) * self.scale, self.pos.z + mathx.sinf(a) * rr);
            if (self.fxRng.float() < 0.75) {
                self.emit(p, v3(self.fxRng.signed() * 0.25, self.fxRng.range(0.5, 1.3), self.fxRng.signed() * 0.25), self.fxRng.range(0.5, 1.0), self.fxRng.range(0.025, 0.06) * self.scale, 0.003, MOTE, -0.7);
            } else {
                self.emit(p, v3(self.fxRng.signed() * 0.3, self.fxRng.range(0.1, 0.4), self.fxRng.signed() * 0.3), self.fxRng.range(0.3, 0.6), self.fxRng.range(0.04, 0.09) * self.scale, 0.01, DUST, 2.0);
            }
        }
    }

    // ── telegraph FX (emit / integrate / draw) ─────────────────────────────────────────
    // Unit facing vector on the ground (matches startHop's atan2(x, z) convention).
    fn fdir(self: *const Frog) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    // The front-slam / dust-burst centre, a short reach ahead of the seat (rides the lift).
    fn impactWorld(self: *const Frog) rl.Vector3 {
        const d = self.fdir();
        return v3(self.pos.x + d.x * LUNGE_IMPACT_FWD * self.scale, 0.04, self.pos.z + d.z * LUNGE_IMPACT_FWD * self.scale);
    }
    // Roughly the mouth/throat in world space (where charge gathers + drool strings from).
    fn mouthWorld(self: *const Frog) rl.Vector3 {
        const d = self.fdir();
        return v3(self.pos.x + d.x * 0.52 * self.scale, 0.32 * self.scale + self.lift, self.pos.z + d.z * 0.52 * self.scale);
    }
    // The pool plumbing is the shared one (foe.zig) — these just name the toad's own ring.
    fn emit(self: *Frog, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.fx, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }
    fn updateFx(self: *Frog, dt: f32) void {
        foe.tickParticles(&self.fx, dt, self.pos.y); // dust settles on the ground IT is standing on
    }
    // A radial fan of dust from `c` (the lunge slam / a hop's smaller landing puff). `spd`
    // scales the outward throw, `big` the puff radius — both ×scale for a heavy toad.
    fn dustBurst(self: *Frog, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(0.5, 1.0) * spd * self.scale;
            const vel = v3(mathx.cosf(a) * s, self.fxRng.range(0.6, 2.2), mathx.sinf(a) * s);
            self.emit(v3(c.x, 0.05, c.z), vel, self.fxRng.range(0.35, 0.62), self.fxRng.range(0.06, 0.12) * self.scale, big * self.fxRng.range(0.8, 1.3) * self.scale, DUST, 4.5);
        }
    }
    // Lunge COIL trickle: dust dug up around the haunches (ramps with the load `k`) + amber
    // charge embers gathering + rising at the maw. Rate-based so it's frame-rate independent.
    fn emitCoil(self: *Frog, dt: f32, k: f32) void {
        self.fxAccum += (12.0 + 40.0 * k) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.18, 0.5) * self.scale;
            const bp = v3(self.pos.x + mathx.cosf(a) * rr, 0.04, self.pos.z + mathx.sinf(a) * rr);
            self.emit(bp, v3(self.fxRng.signed() * 0.4, self.fxRng.range(0.5, 1.5), self.fxRng.signed() * 0.4), self.fxRng.range(0.3, 0.5), self.fxRng.range(0.05, 0.10) * self.scale, self.fxRng.range(0.14, 0.24) * self.scale, DUST, 3.0);
            if (self.fxRng.float() < 0.6) { // an amber charge ember, gathering + drifting up
                const m = self.mouthWorld();
                self.emit(v3(m.x + self.fxRng.signed() * 0.22, m.y + self.fxRng.range(-0.08, 0.24), m.z + self.fxRng.signed() * 0.22), v3(self.fxRng.signed() * 0.22, self.fxRng.range(0.35, 0.95), self.fxRng.signed() * 0.22), self.fxRng.range(0.3, 0.55) + 0.4 * k, self.fxRng.range(0.03, 0.06) * self.scale, 0.004, EMBER, -0.6);
            }
        }
    }
    // Chomp GAPE trickle: charge embers gather at the yawning maw + heavy drool strings drip.
    fn emitGape(self: *Frog, dt: f32, k: f32) void {
        self.fxAccum += (10.0 + 30.0 * k) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const m = self.mouthWorld();
            self.emit(v3(m.x + self.fxRng.signed() * 0.22, m.y + self.fxRng.range(-0.05, 0.22), m.z + self.fxRng.signed() * 0.22), v3(self.fxRng.signed() * 0.2, self.fxRng.range(0.3, 0.8), self.fxRng.signed() * 0.2), self.fxRng.range(0.3, 0.55), self.fxRng.range(0.03, 0.06) * self.scale, 0.004, EMBER, -0.5);
            if (self.fxRng.float() < 0.5) { // a drool droplet, slung down + a touch forward
                const d = self.fdir();
                self.emit(v3(m.x, m.y - 0.06, m.z), v3(d.x * 0.5 + self.fxRng.signed() * 0.2, -0.2, d.z * 0.5 + self.fxRng.signed() * 0.2), self.fxRng.range(0.35, 0.6), self.fxRng.range(0.03, 0.05) * self.scale, 0.015 * self.scale, SPIT, 5.0);
            }
        }
    }
    // Chomp SNAP: a forward spray of spit as the jaws slam.
    fn spitSpray(self: *Frog) void {
        const m = self.mouthWorld();
        const d = self.fdir();
        var i: i32 = 0;
        while (i < 12) : (i += 1) {
            const spd = self.fxRng.range(1.6, 3.4);
            const vel = v3(d.x * spd + self.fxRng.signed() * 0.7, self.fxRng.range(0.2, 1.1), d.z * spd + self.fxRng.signed() * 0.7);
            self.emit(m, vel, self.fxRng.range(0.28, 0.5), self.fxRng.range(0.03, 0.05) * self.scale, 0.012 * self.scale, SPIT, 6.0);
        }
    }
    pub fn drawFx(self: *const Frog) void {
        foe.drawParticles(&self.fx);
    }

    // ── pose: build the 9 world matrices from the resolved channels ─────────────────────
    pub fn pose(self: *Frog) void {
        // Death dissipation: the whole rig shrinks about the seat and sinks into the
        // ground while the motes rise — the corpse melts away rather than blinking out.
        const fs = self.scale * (1.0 - 0.85 * self.fade);
        const sink = -0.30 * self.scale * self.fade;
        // Body frame → world (per-toad uniform scale, pitch, face, then place at the seat).
        // NO squash here — the legs hang off this so they keep their size; squash rides BODY.
        const bframe = mul(
            scaleM(fs, fs, fs),
            // `pos.y` is the ground under it, `lift` the hop above that ground.
            mul3(rx(self.pitch), ry(mathx.degrees(self.facing)), tr(self.pos.x, self.pos.y + self.lift + sink, self.pos.z)),
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

    /// EYES UP: the lunge's wind-up and its flight, and nothing else. Not the hop (a hop is travel, not an
    /// attack) and not the chomp (already inside your guard — a tell you cannot act on is decoration).
    /// So the red is exactly the window in which "get out of the way" is still useful advice.
    pub fn eyesHot(self: *const Frog) bool {
        return self.state == .lunge;
    }

    pub fn draw(self: *const Frog, model: *const Model) void {
        model.draw(&self.xf, self.eyesHot());
    }
};

// ── a KNOT of toads (a group of toads is literally a "knot") ────────────────────────────
// The shared model + the live instances. game.zig owns one of these; the meadow is dressed
// with the knot the way env.zig dresses it with props.
// WHERE the toads stand is the MAP's business now (`foe: toad …` records, placed with the
// editor's Foe tool) — the knot only knows how one behaves. The array is a fixed cap and `n`
// is how many the map actually posted.
const CAP: usize = wf.MAX_PER_KIND;

pub const Knot = struct {
    model: Model,
    frogs: [CAP]Frog = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Knot {
        return .{ .model = Model.init(shader) };
    }
    // Re-home every toad, alive and fresh (a hero death reloads the world, ER-style). The
    // shared Model is untouched — instances only. Body in foe.zig, like the roll-ups.
    pub fn reset(self: *Knot, m: *const wf.Map) void {
        foe.resetGroup(Frog, &self.frogs, &self.n, m, .toad);
    }
    /// The toads this map actually posted. Every caller iterates THIS, never the whole array —
    /// the tail is `undefined` and reading it is a crash waiting for a quiet afternoon.
    pub fn live(self: *Knot) []Frog {
        return self.frogs[0..self.n];
    }
    /// Read-only view, for the `*const Knot` paths (draw, the roll-ups).
    pub fn liveConst(self: *const Knot) []const Frog {
        return self.frogs[0..self.n];
    }
    pub fn setShader(self: *Knot, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    // Advance the whole knot; returns the STRONGEST blow any toad landed on the hero this
    // frame (null if none) AND which toad threw it, for game.zig to apply to the hero's vitals.
    pub fn update(self: *Knot, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    // `scene` non-null (the lit pass) flares each struck toad blood-red via the shared
    // hitFlash uniform; pass null from paths without per-actor flash (none today — the
    // depth pass reuses this too, where the uniform write is simply inert).
    pub fn draw(self: *const Knot, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    // Telegraph particles — drawn AFTER the meshes (unlit, semi-transparent), in the lit pass
    // only (never the shadow depth pass), so dust/charge/spit reads over the toads. Drawn for
    // GONE toads too: a dissipated corpse's last motes drift out instead of popping off.
    pub fn drawFx(self: *const Knot) void {
        for (self.liveConst()) |*f| f.drawFx();
    }
    // The shared Group roll-ups (foe.zig) — identical for every foe, so they live there.
    pub fn anyDied(self: *const Knot) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn runesDropped(self: *const Knot) u32 {
        return foe.runesDropped(self.liveConst(), RUNES);
    }
    pub fn totalHits(self: *const Knot) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Knot) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

// ── the toad mesh (authored in the body frame; joints authored at their own origin) ─────
fn buildMeshes() [NP]rl.Mesh {
    var mesh: [NP]rl.Mesh = undefined;
    mesh[BODY] = bodyMesh();
    mesh[LJAW] = lowerJawMesh();
    mesh[THROAT] = throatMesh();
    mesh[HAUNCH_L] = thighMesh(1.0);
    mesh[SHANK_L] = shankMesh(1.0);
    mesh[HAUNCH_R] = thighMesh(-1.0);
    mesh[SHANK_R] = shankMesh(-1.0);
    mesh[ARM_L] = armMesh(1.0);
    mesh[ARM_R] = armMesh(-1.0);
    return mesh;
}

// A conical tooth from `bpos` along `dir` (unit) for `len`, base radius `r`.
fn tooth(b: *Builder, bpos: rl.Vector3, dir: rl.Vector3, len: f32, r: f32, col: rl.Color) void {
    b.addCylinder(bpos, v3(bpos.x + dir.x * len, bpos.y + dir.y * len, bpos.z + dir.z * len), r, 0.004, 5, col);
}

// One ragged row of nine teeth — uneven size/lean/spacing, the odd gap and snapped stub,
// bigger tusks at the corners (seeded, deterministic). Shared by the upper (body) and lower
// (jaw) rows, differing ONLY in these params; `shift` rebases into the jaw's frame (P_JAW).
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
// warty head + bulging eyes at the mouth line, wider than long. The lower jaw + throat sac
// are separate (animated) parts.
/// THE IRISES ALONE, in whatever colour they are burning. Authored in the BODY's own space and at the same
/// coordinates the sockets in `bodyMesh` were cut for, so the two cannot drift apart. `.plain` because a
/// hide blotch over an emissive dome reads as a dirty lamp.
fn eyeMesh(col: rl.Color) rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    for ([_]f32{ -1, 1 }) |sgn| {
        const ex = 0.19 * sgn;
        b.addCylinder(v3(ex, 0.575, 0.315), v3(ex, 0.645, 0.32), 0.10, 0.05, 9, col);
        b.addCube(v3(ex, 0.62, 0.36), v3(0.038, 0.07, 0.038), PUPIL); // slit pupil, facing forward
    }
    return b.toMesh();
}

fn bodyMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    // Body: a fat dome — belly (bottom) widening up to the midsection, then humping up and
    // narrowing to the back crown (apex set a touch REAR so the profile leans forward). Many
    // sides so it reads round from every angle (no lizard tail).
    b.addCylinder(v3(0, 0.02, -0.02), v3(0, 0.28, -0.03), 0.24, 0.42, 14, HIDE); // lower/mid
    b.addCylinder(v3(0, 0.28, -0.03), v3(0, 0.60, -0.10), 0.42, 0.15, 14, HIDE); // humped back
    b.setMat(.skin);
    b.addCube(v3(0, 0.10, 0.08), v3(0.46, 0.16, 0.44), BELLY); // pale sickly belly, low + front
    b.setMat(.hide);

    // Broad head jutting forward at the mouth line (~y0.24), warty brow above.
    b.addCube(v3(0, 0.34, 0.34), v3(0.62, 0.24, 0.34), HIDE); // head block / brow
    b.addCube(v3(0, 0.255, 0.46), v3(0.58, 0.09, 0.16), HIDE_DK); // upper lip / snout rim
    b.setMat(.skin); // moist mouth tissue — soft mottle, not warty
    b.addCube(v3(0, 0.30, 0.32), v3(0.48, 0.06, 0.34), MAW); // roof of the mouth (gape not hollow)
    b.addCube(v3(0, 0.25, 0.18), v3(0.42, 0.16, 0.14), MAW); // gullet — a dark cavern behind the teeth when agape
    b.setMat(.hide);

    // Bulging eyes on top of the head, set wide — bony brow and mound HERE, the IRIS in its own mesh
    // (`eyeMesh`) so it can change colour with the toad's state. See `Model.draw`.
    for ([_]f32{ -1, 1 }) |sgn| {
        const ex = 0.19 * sgn;
        b.addCube(v3(ex, 0.46, 0.30), v3(0.24, 0.13, 0.24), HIDE_DK); // brow socket
        b.addCylinder(v3(ex, 0.43, 0.31), v3(ex, 0.63, 0.31), 0.135, 0.085, 9, HIDE_LT); // eye mound
    }
    // Nostrils at the snout tip.
    b.addCube(v3(0.08, 0.40, 0.54), v3(0.035, 0.035, 0.035), HIDE_DK);
    b.addCube(v3(-0.08, 0.40, 0.54), v3(0.035, 0.035, 0.035), HIDE_DK);

    // Upper teeth: a RAGGED row hanging from the lip — uneven size / lean / spacing, the odd gap
    // and snapped stub, big tusks near the corners (seeded, deterministic; no two alike).
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
    b.setMat(.hide);
    b.addCube(j(0, 0.185, 0.28), v3(0.58, 0.09, 0.46), HIDE); // jaw slab
    b.setMat(.skin);
    b.addCube(j(0, 0.14, 0.26), v3(0.52, 0.07, 0.42), BELLY); // pale chin underside
    b.addCube(j(0, 0.225, 0.34), v3(0.48, 0.03, 0.30), TONGUE); // fleshy floor / tongue
    b.setMat(.hide);
    b.addCube(j(0, 0.235, 0.49), v3(0.50, 0.05, 0.09), HIDE_DK); // lower lip rim
    // Lower teeth point UP from the rim — the same ragged wabi-sabi treatment, a different
    // seed so they don't mirror the uppers (they interlock unevenly).
    toothRow(&b, .{ .seed = 6421, .tuskLen = 0.19, .toothLen = 0.115, .tuskRad = 0.042, .toothRad = 0.028, .dirY = 1, .zlean = 0.08, .z0 = 0.49, .shift = P_JAW });
    return b.toMesh();
}

// Throat sac — authored about P_SAC at the origin; a pale distendable pouch under the chin.
fn throatMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin); // stretched membrane — soft mottle, no warts
    b.addCylinder(v3(0, 0.06, 0), v3(0, -0.04, 0.01), 0.19, 0.24, 10, SAC);
    b.addCylinder(v3(0, -0.04, 0.01), v3(0, -0.13, 0.01), 0.24, 0.12, 10, SAC);
    b.addCube(v3(0, -0.02, 0.05), v3(0.34, 0.18, 0.24), SAC); // fill the pouch out front
    return b.toMesh();
}

// Back-leg thigh — authored at the hip origin, a fat haunch reaching up to the folded knee.
// `side` mirrors the outward lean so the RIGHT thigh reaches its own mirrored knee — else an
// unmirrored +x lean points it inward, short of the shank (matches shankMesh(side)).
fn thighMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    const knee = v3((P_KNEE.x - P_HIP.x) * side, P_KNEE.y - P_HIP.y, P_KNEE.z - P_HIP.z);
    b.addCylinder(v3(0, 0, 0), knee, 0.20, 0.13, 10, HIDE);
    b.addCylinder(v3(0, 0.03, -0.02), v3(knee.x * 0.55, knee.y * 0.55, knee.z * 0.55 - 0.03), 0.225, 0.17, 10, HIDE_LT); // big muscle bulge
    return b.toMesh();
}

// Back-leg shank + webbed foot — authored at the knee origin, dropping down-forward to the
// ground; `side` mirrors the toe splay. The long foot is the frog read.
fn shankMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
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

// Front leg — authored at the shoulder origin; small, splayed, planting forward. `side`
// mirrors the outward-x lean so the RIGHT arm isn't flipped inward (as thighMesh/shankMesh).
fn armMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    const hand = v3(0.02 * side, -0.26, 0.16);
    b.addCylinder(v3(0, 0, 0), hand, 0.075, 0.045, 8, HIDE);
    b.addCube(v3(hand.x, hand.y - 0.005, hand.z + 0.03), v3(0.12, 0.03, 0.11), HIDE_DK); // splayed hand
    for ([_]f32{ -1, 0, 1 }) |t| {
        b.addCube(v3(hand.x + t * 0.05, hand.y - 0.005, hand.z + 0.10), v3(0.022, 0.02, 0.06), CLAW);
    }
    return b.toMesh();
}

// (A `distPointSeg` wrapper over `mathx.closestOnSegV` sat here with no caller but its own test —
// the blade test itself goes through `foe.strike`, which rides the mathx helper directly. The three
// assertions it carried were really about that helper, so they moved to mathx.zig, beside it.)

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

test "lunge impact catches the front zone, not the sides or behind" {
    // facing 0 → the toad faces +Z; the slam zone is out FRONT.
    var front = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    front.tryImpact(v3(0, 0, 1.0), LUNGE_HIT); // dead ahead, in reach
    try std.testing.expect(front.heroHit != null);

    var behind = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    behind.tryImpact(v3(0, 0, -1.0), LUNGE_HIT); // same distance, but behind
    try std.testing.expect(behind.heroHit == null);

    var beside = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    beside.tryImpact(v3(1.0, 0, 0), LUNGE_HIT); // off to the flank
    try std.testing.expect(beside.heroHit == null);

    var onTop = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    onTop.tryImpact(v3(0.1, 0, 0), LUNGE_HIT); // standing on it → caught regardless of arc
    try std.testing.expect(onTop.heroHit != null);

    var far = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    far.tryImpact(v3(0, 0, 99), LUNGE_HIT); // out front but way out of reach
    try std.testing.expect(far.heroHit == null);
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
