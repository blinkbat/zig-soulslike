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


// The shared helpers from mathx (single source for the "a-first" convention across rigs).
const rx = mathx.rx;
const ry = mathx.ry;
const tr = mathx.tr;
const scaleM = mathx.scaleM;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const place = mathx.placeAt; // the shared joint placer — see mathx

const HIDE = rgba(34, 38, 23, 255); // dark bog olive (a night thing)
const HIDE_DK = rgba(20, 23, 14, 255); // warts, shadow, mottling — near-black
const HIDE_LT = rgba(52, 55, 34, 255); // ridge / caught-light humps
const BELLY = rgba(64, 62, 42, 255); // dark, sickly underside
const SAC = rgba(80, 74, 48, 255); // throat sac — a touch paler so its distend reads
const MAW = rgba(104, 34, 28, 255); // mouth interior — a sickly oxblood RED, lighter than the hide so the open maw reads as a cavern
const TONGUE = rgba(126, 56, 48, 255);
const TOOTH = rgba(166, 156, 126, 255); // pale bone — pops hard against the dark hide
const TOOTH_DK = rgba(126, 116, 90, 255);
const EYE = rgba(252, 196, 84, 96);
const EYE_HOT = rgba(255, 62, 34, 62);
const PUPIL = rgba(10, 8, 6, 255);
const CLAW = rgba(28, 26, 20, 255);

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
const P_HIP = v3(0.40, 0.24, -0.06); // back-leg hip
const P_KNEE = v3(0.47, 0.46, 0.00); // back-leg knee
const P_SHOULDER = v3(0.22, 0.26, 0.22); // front-leg shoulder

/// The reticle's seat in the BODY part's own frame, whose origin is the ground SEAT (+Y up, +Z forward) —
/// so this is the brow, a little forward of centre, and not a height above the earth.
const LOCK_AT = v3(0, 0.30, 0.06);
const BODY_CY = 0.34; // body-centre height (for the camera focus + hurt sphere)
const HURT_R = 0.46; // hurt-sphere radius (world units, pre per-toad scale)
const BODY_R = 0.55; // ground-footprint radius for collision (pre per-toad scale) — matches the

// Global size multiplier for the whole knot (each toad's own `scale` rides on top).
pub const SCALE = 1.4;

// Locomotion & senses (world units / seconds).
pub const AGGRO_R = 11.0; // notices the hero within this
/// CLOSE ENOUGH TO ITS OWN PATCH to stop hopping back to it. Deliberately TIGHTER than the tether's
/// `foe.LEASH_HOME_R` — that is the radius a leash stops pulling at, this is a small animal's idea of having
/// got home — and named rather than left a bare literal inside `decide`.
const HOME_R = 2.2;
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
const LUNGE_COIL = 0.82; // the readable wind-up tell — a LONG, deep, unmistakable load (slow to wind, so it reads early)
const LUNGE_FLIGHT = 0.34;
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

// Leg fold: legExt 0 = fully coiled, 1 = fully extended; the sit pose is REST_EXT.
const REST_EXT = 0.34;
const HIP_SWING = 66.0; // + extends the thigh back-and-down (push-off)
const KNEE_STRAIGHTEN = 104.0; // + straightens the knee out of its tuck
const FLASH_DUR = foe.FLASH_DUR; // how long a landed hit flares the toad blood-red (gfx hitFlash) + the debug wires
const SHOVE_DECAY = 7.0; // 1/s — the hit shove bleeds off fast (a jolt off the blow, not a slide)
const DISS_DUR = 0.95; // seconds the corpse takes to dissipate into motes once the collapse is done
/// …and the cloud it goes out in: a low, close body, so it comes off nearer the ground than a man's does.
const DISSOLVE = foe.Dissolve{ .rate = 44.0, .spread = 0.55, .rise = 0.35 };

const FX_MAX = 40; // per-toad budget (ring buffer — the oldest particle is overwritten)
const DUST = foe.DUST; // kicked-up bog dust — the SHARED one (see foe.zig: it was two copies)
const EMBER = rgba(252, 196, 84, 150); // amber charge glow — the lamp-eye colour, gathering (kept sheer so glints layer, not blob)
const SPIT = rgba(176, 190, 150, 140); // pale sickly drool / spit fling
const BLOOD = rgba(112, 22, 16, 235); // hit spray — dark oxblood, kin to the maw (unlit droplets).

const HP_MAX = 46.0;
const POISE_MAX = 8.0; // BELOW the hero's light poise damage (10): every landed light
const STANCE_MAX = 26.0; // low — a few flinches cascade into the heavy stagger (3rd chained light crumples)
/// A WET THING OUT OF A BOG: fire has to boil the water off it first, and cold-blooded means the cold
/// bites and the wet hide conducts. Fire is the only one of the four anything deals today (the hero's
/// fire arrow); the rest are the creature's nature, waiting on a source.
const RESISTS = combat.resists(.{ .fire = 40, .cold = -30, .lightning = -25 });
const CHOMP_HIT = combat.Hit{ .dmg = 13, .poise = 15 }; // eased down from 16 (owner: lower dmg a bit)
const LUNGE_HIT = combat.Hit{ .dmg = 19, .poise = 26, .stance = 8 }; // eased down from 24 — still a real slam
const HERO_REACH = foe.HERO_REACH; // hero footprint added to the toad's attack range for the hit test
/// HOW LONG BEFORE THE SLAM LANDS IT CAN STILL BE CAUGHT — the game's own number (`foe.PARRY_LEAD`), so the
/// timing a player learned off a giant's club is the timing that swats a toad out of the air. THE LEAP AND
/// NOTHING ELSE OF ITS has a window; see `Frog.toImpact` for why the hop and the chomp are out.
const PARRY_LEAD = foe.PARRY_LEAD;

const LUNGE_IMPACT_R = 1.9; // frontal slam reach from the seat
const LUNGE_FRONT_DOT = 0.25; // hero must lie within the frontal arc (~±76°) to be caught
const LUNGE_IMPACT_FWD = 0.6; // dust-burst / impact-zone centre, this far ahead of the seat (pre-scale)
/// Embers a second dragged off the body through the lunge's flight (`emitLungeTrail`).
const TRAIL_RATE: f32 = 150.0;
const DEATH_DUR = 1.25; // collapse-and-still before the corpse is removed from play
/// SOULS a toad is worth.
pub const SOULS: u32 = 60;

const State = enum { idle, hop, lunge, recover, chomp, stunlight, stunheavy, dead };

const Choice = enum { rest, hop, lunge, chomp, wait };
fn classify(dist: f32, lungeReady: bool, chompReady: bool, rooted: bool) Choice {
    if (dist <= BITE_R) return if (chompReady) .chomp else .wait; // too close to hop; hold for the bite
    // ROOTED, AND A TOAD TRAVELS BY LEAVING THE GROUND — the hop and the lunge both do, so both are refused
    // (`foe.canLeap`) and there is nothing left but to wait the grip out. The JAWS are the branch above and
    // still work: the roots take the feet, not the mouth.
    if (rooted) return .wait;
    if (dist > AGGRO_R) return .rest;
    if (dist <= LUNGE_R and lungeReady) return .lunge;
    return .hop;
}

const Particle = foe.Particle;

pub const Model = struct {
    mesh: [NP]rl.Mesh,
    /// THE IRISES, twice: calm amber and hot RED.
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
        rl.drawMesh(self.eyes[@intFromBool(hot)], self.mat, xf[BODY]);
    }
};

pub const Frog = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// THE WAND'S ROOTS, when they have hold of it (combat.Root) — stamped from outside, like the leash's eyes.
    root: combat.Root = .{},
    /// THE RIME BREATH'S COLD (`combat.Chill`) — stamped from outside like the roots, and billed through the
    /// same `foe.grip`. The field is what opts a creature into the cone at all (`game.rimeBreathe`).
    chill: combat.Chill = .{},
    /// …and THE HERO'S SHIELD, stamped the same way (`game.markParry`). Read only inside its own leap window.
    parry: foe.Parry = .{},
    /// THE SHIELD CAUGHT THE LEAP THIS FRAME — a ONE-FRAME flag, `justDied`'s exactly: reset at the top of
    /// `update`, set where the catch happens, read by the group (`Knot.anyParried`) after.
    parried: bool = false,
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

    sy: f32 = 1, // body vertical scale (squash<1 / stretch>1)
    sxz: f32 = 1, // body horizontal scale (volume-ish conserved)
    lift: f32 = 0, // world-Y hop height
    pitch: f32 = 0, // body pitch (deg; + = nose down)
    legExt: f32 = REST_EXT,
    arm: f32 = 0, // front-leg forward reach 0..1
    jaw: f32 = 0, // lower-jaw open (deg)
    sac: f32 = 1, // throat-sac inflate scale

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0, // total blows landed (debug read-out)
    hitLatch: bool = false, // one hit per swing: set on contact, cleared when the blade goes inactive
    flash: f32 = 0, // blood-red body flash after a registered hit (fades over FLASH_DUR)
    shove: rl.Vector3 = mathx.zero3, // knockback velocity a landed blow imparts (decays fast)
    heroHit: ?combat.Hit = null, // this frame's blow ON THE HERO (chomp/lunge connect), read by game.zig
    heroLatch: bool = false, // one hero-hit per attack action (chomp/lunge)
    justDied: bool = false, // true only on the frame a blow kills it (game.zig keys the kill beat off this)
    /// WHO IT IS FIGHTING (`foe.Threat`) — embedded here and stamped by the game, `Leash`'s own law. The
    /// creature never asks what a spirit is; it is handed a target in the argument it calls `hero`.
    threat: foe.Threat = .{},
    /// …AND THE WAY ROUND WHAT IS IN THE WAY (`foe.Nav`), stamped the same way and for the same reason.
    nav: foe.Nav = .{},
    fade: f32 = 0, // death dissipation 0..1 — pose() shrinks + sinks the corpse by it
    gone: bool = false, // corpse removed from play (dissipation finished) — skipped everywhere

    // Telegraph FX: a ring of particles, a rate-based emit carry so trickles are frame-rate independent,
    // and a seeded RNG for the scatter.
    parts: [FX_MAX]Particle = [_]Particle{.{}} ** FX_MAX,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [NP]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Frog {
        var f = Frog{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * SCALE, .seed = seed };
        f.fxRng = foe.fxStream(seed, 104729.0, 1); // per-toad scatter, deterministic
        f.idleWait = 1.0 + seed * 2.0;
        f.resolveIdle();
        f.pose();
        return f;
    }

    // Heights measured from `pos.y`
    pub fn centerWorld(self: *const Frog) rl.Vector3 {
        return foe.bodyPoint(self.pos, BODY_CY, self.scale, self.lift);
    }
    pub fn hurtRadius(self: *const Frog) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Frog) f32 {
        return BODY_R * self.scale;
    }
    /// THE MARK RIDES THE BROW. `xf[BODY]` carries the SQUASH as well as the hop, so the mark now flattens
    /// with the toad as it gathers for a lunge and rides it up through the whole arc — where a height off
    /// the ground sat still through the one animation this creature is mostly made of.
    pub fn lockPoint(self: *const Frog) rl.Vector3 {
        return foe.markOn(self.xf[BODY], LOCK_AT);
    }
    // Airborne mid-hop/lunge — ground collision leaves it be while it's in the air.
    pub fn airborne(self: *const Frog) bool {
        return self.lift > foe.AIRBORNE_LIFT;
    }
    // Top of the domed back in world space — where the floating HP bar rides.
    pub fn topWorld(self: *const Frog) rl.Vector3 {
        return foe.bodyPoint(self.pos, 0.80, self.scale, self.lift);
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

    fn faceToward(self: *Frog, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt); // shared — see foe.zig
    }

    /// WHERE IT IS TRYING TO GO (`game.markWay`), asked while it is SITTING: a toad travels in committed hops, so
    /// the stamp has to be standing ready on the frame the next one is chosen. Whichever errand it is on — him,
    /// or the post it wandered off.
    pub fn navWant(self: *const Frog, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle) return null;
        if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) return hero;
        return if (mathx.distXZ(self.pos, self.home) > HOME_R) self.home else null;
    }

    // Begin a hop toward `to` (clamped to bounds); `lunge` = the big committed leap.
    pub fn startHop(self: *Frog, to: rl.Vector3, bounds: f32, lunge: bool) void {
        self.hopAim = mathx.clampXZ(v3(to.x, 0, to.z), bounds);
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

    /// SECONDS UNTIL THE SLAM LANDS, counted from the start of the leap so the coil and the arc are ONE
    /// continuous countdown — null when it is not throwing one. `tryImpact` fires the frame the toad touches
    /// down, so the window shuts there by construction: a caught leap is one that never arrived.
    fn toImpact(self: *const Frog) ?f32 {
        return switch (self.state) {
            .lunge => (LUNGE_COIL + self.hopDur) - self.t,
            .idle, .hop, .recover, .chomp, .stunlight, .stunheavy, .dead => null,
        };
    }

    /// THE INSTANT THE LEAP CAN BE CAUGHT IN, and how far out it reaches then — `tryImpact`'s OWN extent, and
    /// UNSCALED exactly as that test is (the ogre's `slamReach` law: the parry's reach is the blow's reach).
    fn parryable(self: *const Frog) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return LUNGE_IMPACT_R + HERO_REACH;
    }

    /// THE BOARDS TAKE THE LEAP. `enterStun` is what kills it: the `.lunge` state is gone, so `updateHop` never
    /// reaches its landing and `tryImpact` never fires. The toad COMES STRAIGHT DOWN — both stun resolvers write
    /// `lift` from scratch, so a body caught mid-air is on the ground on the frame it is caught.
    fn takeParry(self: *Frog) void {
        const reach = self.parryable() orelse return;
        if (!self.parry.catches(self.pos, reach)) return;
        self.parried = true;
        self.flash = FLASH_DUR;
        self.leash.noteCombat();
        // Back on its own cooldown though it never finished, or it comes out of the sprawl into the leap it was
        // just denied.
        self.lungeCd = LUNGE_CD;
        // THE EARTH IT WAS ABOUT TO HIT, thrown up where it comes down instead — a body this size stopped in
        // mid-air still arrives somewhere.
        self.dustBurst(self.pos, 14, 2.2, 0.20);
        sfx.world(.toad_hurt, self.pos);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(), // a parry takes no HP today; the day one does, it kills like anything
            .heavy => self.enterStun(.stunheavy),
            // A stance that HELD is still a leap swatted out of the air: the slam dies either way, into the
            // short flinch rather than the wide-open sprawl.
            .light, .none => self.enterStun(.stunlight),
        }
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
    fn tryBite(self: *Frog, hero: rl.Vector3, range: f32, h: combat.Hit) void {
        if (self.heroLatch) return;
        if (mathx.distXZ(self.pos, hero) <= range + HERO_REACH) {
            self.heroHit = h;
            self.heroLatch = true;
            self.leash.noteCombat(); // a blow landed is a fight in progress — the tether waits
        }
    }
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
        self.leash.noteCombat();
    }

    // Advance AI + animation for one frame; `hero` drives senses, `blade` the hero's swing.
    pub fn update(self: *Frog, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            self.updateFx(dt); // a removed corpse's last motes keep drifting out
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        self.parried = false;
        // THE ROOTS HAVE THE FEET (foe.grip) — the state machine runs, the jaws still work, and XZ goes back
        // wherever it tried to travel. Every move a toad has BESIDES the jaws is a leap, so `classify` refuses
        // the lot of them while the grip is on rather than hopping it on the spot (`foe.canLeap`).
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        self.vit.tick(dt); // poise/stance regenerate between hits (relent and it recovers)
        self.elapsed += dt;
        self.lungeCd = mathx.maxF(0, self.lungeCd - dt);
        self.chompCd = mathx.maxF(0, self.chompCd - dt);
        foe.fadeFlash(&self.flash, dt);
        self.t += dt;
        // THE TETHER: drawn a long way from its lily patch and left alone, it goes back (foe.Leash).
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        self.updateFx(dt); // advance live particles (bursts from any state keep animating)
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt); // the knockback off a landed blow
        // THE SHIELD, asked BEFORE the state machine runs this frame's arc — a catch has to kill the slam it
        // caught, and by the time `tryImpact` has run the body has already landed on him.
        self.takeParry();

        switch (self.state) {
            .idle => self.updateIdle(dt, hero, bounds),
            .hop => self.updateHop(dt, hero, bounds, HOP_COIL, self.hopDur, HOP_LAND),
            .lunge => self.updateHop(dt, hero, bounds, LUNGE_COIL, self.hopDur, LUNGE_LAND),
            .recover => {
                self.resolveRecover();
                if (self.t >= RECOVER_DUR) self.enterIdle(0.02);
            },
            .chomp => self.updateChomp(dt, hero),
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
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
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

    // Decide what to do next (called when a hop/chomp/recovery finishes, and on the idle timer).
    fn decide(self: *Frog, hero: rl.Vector3, bounds: f32) void {
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        switch (classify(d, self.lungeCd <= 0, self.chompCd <= 0, !foe.canLeap(&self.root))) {
            .chomp => {
                self.chompCd = CHOMP_CD;
                self.startChomp();
            },
            .lunge => {
                self.lungeCd = LUNGE_CD;
                // Land just short of the hero (don't leap past them).
                const dir = mathx.dirXZ(self.pos, hero);
                const reach = mathx.minF(mathx.maxF(0, d - KEEP_OFF), LUNGE_R);
                self.startHop(v3(self.pos.x + dir.x * reach, 0, self.pos.z + dir.z * reach), bounds, true);
            },
            .hop => {
                // …ROUND WHAT IS IN THE WAY (`foe.Nav`), and the bend goes in HERE, at the choose: a hop is
                // committed the moment it starts, so a heading bent mid-arc would only bend the arc. The LUNGE
                // is deliberately left straight — that one is the attack, and it goes where it was aimed.
                const dir = self.nav.along(mathx.dirXZ(self.pos, hero));
                const reach = mathx.minF(HOP_REACH, mathx.maxF(0, d - KEEP_OFF));
                self.startHop(v3(self.pos.x + dir.x * reach, 0, self.pos.z + dir.z * reach), bounds, false);
            },
            .wait => self.enterIdle(0.12), // in bite range, chomp cooling down — hold a beat
            .rest => {
                // Out of aggro: hop home if we've wandered, else sit and wait.
                if (mathx.distXZ(self.pos, self.home) > HOME_R) {
                    const dir = self.nav.along(mathx.dirXZ(self.pos, self.home));
                    self.startHop(v3(self.pos.x + dir.x * HOP_REACH, 0, self.pos.z + dir.z * HOP_REACH), bounds, false);
                } else self.enterIdle(1.4 + self.seed * 2.2);
            },
        }
    }

    fn updateIdle(self: *Frog, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
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
            if (self.isLunge) self.faceToward(self.hopAim, dt) else self.faceToward(hero, dt);
            const k = mathx.smoothstep(0, coil, self.t);
            self.resolveCoil(k, self.isLunge);
            if (self.isLunge) self.emitCoil(dt, k); // dust dug up + amber charge — the big tell
        } else if (self.t < coil + flight) {
            if (!self.launched) {
                self.launched = true;
                self.hopFrom = self.pos;
                const f = self.fdir();
                self.hopTo = mathx.clampXZ(v3(self.pos.x + f.x * self.hopReach, 0, self.pos.z + f.z * self.hopReach), bounds);
            }
            const s = (self.t - coil) / flight; // 0..1 across the arc
            // Advance horizontally by an INCREMENT (velocity·dt), NOT an absolute lerp from a stale
            // `hopFrom`: a collision nudge mid-arc then deflects the leap rather than snapping the toad
            // back to its takeoff point on the next frame.
            const inv = 1.0 / flight;
            self.pos.x += (self.hopTo.x - self.hopFrom.x) * inv * dt;
            self.pos.z += (self.hopTo.z - self.hopFrom.z) * inv * dt;
            self.resolveFlight(s);
            if (self.isLunge) self.emitLungeTrail(dt, s);
        } else {
            const k = mathx.smoothstep(0, land, self.t - coil - flight);
            self.resolveLand(k);
            // Fire the impact dust ONCE, the frame we touch down (a big front-slam telegraph).
            if ((self.t - dt) < coil + flight) {
                // …at its FEET, which `pos` already is now that it carries the ground height.
                if (self.isLunge) self.dustBurst(self.impactWorld(), 32, 4.4, 0.30) else self.dustBurst(self.pos, 8, 1.8, 0.16);
                // The slam connects on the SAME edge — the parry window shuts at touchdown, so a blow
                // still live through the sprawl would be one caught "after it hit you".
                if (self.isLunge) self.tryImpact(hero, LUNGE_HIT);
            }
        }
        mathx.holdXZ(&self.pos, bounds);
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
            const k = foe.swingCurve(self.t / CHOMP_GAPE);
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
        const splat = mathx.pulse(k, 0, 0.45, 0.45, 1.0);
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
        self.jaw = CHOMP_JAW * k;
        self.sac = 1.0 + (CHOMP_SAC - 1.0) * k; // throat balloons
        self.legExt = mathx.lerpF(REST_EXT, 0.22, k); // rocks back onto the haunches
        self.arm = 0.2 * k;
    }
    fn resolveSnap(self: *Frog, s: f32) void {
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

    fn resolveStunLight(self: *Frog) void {
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
        self.base();
        const u = mathx.clampF(self.t / combat.FOE_HEAVY_STUN_DUR, 0, 1);
        const down = mathx.pulse(u, 0, 0.16, 0.74, 1.0); // slam, gather at the end
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

    pub fn tryHit(self: *Frog, blade: foe.Blade) void {
        if (self.state == .dead) return; // no hitting a corpse
        const s = foe.reached(self, blade) orelse return;
        // The blow READS at the wound: blood flung along the sweep, body knocked the same way.
        const heavyBlow = foe.wounded(self, s, blade, .{ .light = 1.25, .heavy = 1.9 });
        self.bloodBurst(s.contact, s.dir, if (heavyBlow) 14 else 9, if (heavyBlow) 2.6 else 1.9);
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

    /// THE LUNGE'S WAKE — the thing that makes a leap read as dangerous rather than as a jump.
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

    fn bloodBurst(self: *Frog, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        const parts = foe.hitParts(n); // the field's one dial (`foe.HIT_PARTS`)
        var i: i32 = 0;
        while (i < parts) : (i += 1) {
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

    // Unit facing vector on the ground (matches startHop's atan2(x, z) convention).
    fn fdir(self: *const Frog) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    // The front-slam / dust-burst centre, a short reach ahead of the seat (rides the lift).
    fn impactWorld(self: *const Frog) rl.Vector3 {
        const d = self.fdir();
        return v3(self.pos.x + d.x * LUNGE_IMPACT_FWD * self.scale, self.pos.y + 0.04, self.pos.z + d.z * LUNGE_IMPACT_FWD * self.scale);
    }
    // Roughly the mouth/throat in world space (where charge gathers + drool strings from).
    fn mouthWorld(self: *const Frog) rl.Vector3 {
        const d = self.fdir();
        return v3(self.pos.x + d.x * 0.52 * self.scale, self.pos.y + 0.32 * self.scale + self.lift, self.pos.z + d.z * 0.52 * self.scale);
    }
    // The pool plumbing is the shared one (foe.zig) — these just name the toad's own ring.
    fn emit(self: *Frog, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.parts, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }
    fn updateFx(self: *Frog, dt: f32) void {
        foe.tickParticles(&self.parts, dt, self.pos.y); // dust settles on the ground IT is standing on
    }
    // A radial fan of dust from `c` (the lunge slam / a hop's smaller landing puff).
    fn dustBurst(self: *Frog, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(0.5, 1.0) * spd * self.scale;
            const vel = v3(mathx.cosf(a) * s, self.fxRng.range(0.6, 2.2), mathx.sinf(a) * s);
            self.emit(v3(c.x, self.pos.y + 0.05, c.z), vel, self.fxRng.range(0.35, 0.62), self.fxRng.range(0.06, 0.12) * self.scale, big * self.fxRng.range(0.8, 1.3) * self.scale, DUST, 4.5);
        }
    }
    fn emitCoil(self: *Frog, dt: f32, k: f32) void {
        self.fxAccum += (12.0 + 40.0 * k) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.18, 0.5) * self.scale;
            const bp = v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.04, self.pos.z + mathx.sinf(a) * rr);
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
        foe.drawParticles(&self.parts);
    }

    pub fn pose(self: *Frog) void {
        const fs = self.scale * (1.0 - 0.85 * self.fade);
        const sink = -0.30 * self.scale * self.fade;
        // Body frame → world (per-toad uniform scale, pitch, face, then place at the seat).
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

    /// EYES UP: the lunge's wind-up and its flight, and nothing else.
    pub fn eyesHot(self: *const Frog) bool {
        return self.state == .lunge;
    }

    pub fn draw(self: *const Frog, model: *const Model) void {
        model.draw(&self.xf, self.eyesHot());
    }
};

const CAP: usize = wf.MAX_PER_KIND;

pub const Knot = struct {
    model: Model,
    frogs: [CAP]Frog = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Knot {
        return .{ .model = Model.init(shader) };
    }
    // Re-home every toad, alive and fresh (a hero death reloads the world, ER-style).
    pub fn reset(self: *Knot, m: *const wf.Map) void {
        foe.resetGroup(Frog, &self.frogs, &self.n, m, .toad);
    }
    /// The toads this map actually posted.
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
    /// THE HERO'S SHIELD, STAMPED ON EVERY MEMBER (`game.markParry`) — the leash's own pattern, and set before
    /// `update` so a window is read on the frame it is open rather than the one after.
    pub fn setParry(self: *Knot, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    /// …and whether any of them was caught on it this frame. A ONE-FRAME edge, `anyDied`'s, read after `update`.
    pub fn anyParried(self: *const Knot) bool {
        return foe.anyParried(self.liveConst());
    }
    // Returns the STRONGEST blow any toad landed this frame (null if none) and which toad threw it.
    pub fn update(self: *Knot, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Knot, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Knot) void {
        for (self.liveConst()) |*f| f.drawFx();
    }
    // The shared Group roll-ups (foe.zig) — identical for every foe, so they live there.
    pub fn pierce(self: *Knot, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Knot) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Knot) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Knot) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Knot) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

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

const ToothRow = struct {
    seed: u64,
    tuskLen: f32,
    toothLen: f32,
    tuskRad: f32,
    toothRad: f32,
    dirY: f32, // -1 = hang down (uppers), +1 = point up (lowers)
    zlean: f32, // base forward lean of each tooth
    z0: f32, // row's z origin at the lip line
    zCurve: f32 = 0, // the row follows the mouth's ARC — end teeth root back into the jowls, not in the air
    shift: rl.Vector3 = mathx.zero3,
};
fn toothRow(b: *Builder, cfg: ToothRow) void {
    var trng = mathx.Rng.init(cfg.seed);
    var i: i32 = -4;
    while (i <= 4) : (i += 1) {
        if (trng.float() < 0.14) continue; // a missing tooth
        const fx = @as(f32, @floatFromInt(i)) * 0.064 + trng.range(-0.016, 0.016); // uneven spacing
        const tusk = @abs(i) >= 3 and trng.float() < 0.8;
        const broken = trng.float() < 0.15; // a snapped-off stub
        const len = (if (tusk) cfg.tuskLen else cfg.toothLen) * (if (broken) trng.range(0.3, 0.5) else trng.range(0.72, 1.25));
        const rad = (if (tusk) cfg.tuskRad else cfg.toothRad) * trng.range(0.8, 1.2);
        const dir = v3(trng.range(-0.13, 0.13), cfg.dirY, cfg.zlean + trng.range(-0.05, 0.10)); // each leans its own way
        const y = 0.235 + trng.range(-0.008, 0.012);
        const z = cfg.z0 - cfg.zCurve * fx * fx;
        tooth(b, v3(fx - cfg.shift.x, y - cfg.shift.y, z - cfg.shift.z), dir, len, rad, if (trng.float() < 0.5) TOOTH else TOOTH_DK);
    }
}

fn eyeMesh(col: rl.Color) rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    for ([_]f32{ -1, 1 }) |sgn| {
        const k: f32 = if (sgn < 0) 1.0 else 0.92; // uneven pair, matching the mounds — the left lamp is the big one
        const ex = 0.19 * sgn;
        const cy = mathx.lerpF(0.525, 0.585, k); // sunk into the lid — the glow shows FORWARD, a glint over the crown, never a bare bulb behind
        b.addBlob(v3(ex, cy, 0.34), v3(0.10 * k, 0.055 * k, 0.095 * k), 7, 12, col); // the lamp, doming out of its turret
        b.addBlob(v3(ex, cy + 0.002, 0.34 + 0.095 * k - 0.008), v3(0.018, 0.038, 0.017), 5, 8, PUPIL); // slit pupil breaking the glass
    }
    return b.toMesh();
}

fn bodyMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4207);
    b.setMat(.hide);
    // Trunk: a squat dome — wide at the seat, humping up and back to the crown (apex set REAR so the profile leans forward).
    b.addBlob(v3(0, 0.26, -0.02), v3(0.42, 0.27, 0.45), 9, 15, HIDE);
    b.addBlob(v3(0.02, 0.43, -0.13), v3(0.29, 0.20, 0.29), 8, 13, HIDE); // the humped crown, a shade off-line
    b.addBlob(v3(-0.03, 0.28, -0.36), v3(0.19, 0.15, 0.15), 7, 12, HIDE_DK); // shadowed rump
    b.setMat(.skin);
    b.addBlob(v3(0, 0.13, 0.10), v3(0.27, 0.13, 0.27), 8, 13, BELLY); // pale sickly belly, low + front
    b.setMat(.hide);

    // The head: one broad jowled mass jutting at the mouth line (~y0.24), never a slab.
    b.addBlob(v3(0, 0.345, 0.30), v3(0.33, 0.13, 0.22), 9, 15, HIDE);
    for ([_]f32{ -1, 1 }) |sgn| {
        const k: f32 = if (sgn < 0) 1.06 else 0.96; // jowls uneven
        b.addBlob(v3(sgn * 0.215, 0.315, 0.34), v3(0.145 * k, 0.10 * k, 0.15 * k), 7, 12, HIDE);
    }
    b.addBlob(v3(0, 0.26, 0.44), v3(0.32, 0.05, 0.10), 8, 14, HIDE_DK); // upper lip roll over the tooth line
    b.setMat(.skin); // moist mouth tissue — soft mottle, not warty
    b.addBlob(v3(0, 0.30, 0.30), v3(0.24, 0.035, 0.17), 6, 12, MAW); // roof of the mouth (gape not hollow)
    b.addBlob(v3(0, 0.25, 0.16), v3(0.21, 0.085, 0.10), 6, 11, MAW); // gullet — a dark cavern behind the teeth when agape
    b.setMat(.hide);

    for ([_]f32{ -1, 1 }) |sgn| {
        const k: f32 = if (sgn < 0) 1.0 else 0.92; // the left turret bigger and higher
        const ex = 0.19 * sgn;
        b.addBlob(v3(ex, 0.45, 0.30), v3(0.135 * k, 0.075, 0.125), 7, 12, HIDE_DK); // brow socket
        b.addBlob(v3(ex, mathx.lerpF(0.44, 0.50, k), 0.31), v3(0.125 * k, 0.115 * k, 0.115 * k), 8, 13, HIDE_LT); // eye mound
        b.addBlob(v3(ex, mathx.lerpF(0.515, 0.575, k), 0.285), v3(0.115 * k, 0.055, 0.095 * k), 7, 12, HIDE_LT); // the heavy lid hooding the lamp's rear — glow faces FORWARD
    }
    // Nostrils at the snout tip — an unmatched pair.
    b.addBlob(v3(0.085, 0.395, 0.495), v3(0.023, 0.018, 0.023), 5, 8, HIDE_DK);
    b.addBlob(v3(-0.072, 0.402, 0.50), v3(0.019, 0.016, 0.020), 5, 8, HIDE_DK);

    toothRow(&b, .{ .seed = 9173, .tuskLen = 0.21, .toothLen = 0.13, .tuskRad = 0.046, .toothRad = 0.030, .dirY = -1, .zlean = 0.10, .z0 = 0.50, .zCurve = 0.55 });

    // Warty humps scattered over the domed back (deterministic seed, like the flora clumps).
    var w: i32 = 0;
    while (w < 17) : (w += 1) {
        const a = rng.angle();
        const h = rng.range(0.30, 0.50);
        const rr = mathx.lerpF(0.40, 0.16, (h - 0.28) / 0.32) - 0.02; // ride the dome surface, sunk most of the way in
        const wx = mathx.cosf(a) * rr;
        const wz = -0.05 + mathx.sinf(a) * rr;
        const ws = rng.range(0.026, 0.050);
        b.addBlob(v3(wx, h, wz), v3(ws, ws * rng.range(0.45, 0.7), ws * rng.range(0.8, 1.25)), 5, 9, if (rng.float() < 0.5) HIDE_DK else HIDE_LT);
    }
    return b.toMesh();
}

// Lower jaw — authored about the hinge (P_JAW) at the origin, extending forward.
fn lowerJawMesh() rl.Mesh {
    var b = Builder.init();
    // Author in body-frame targets, shifted so the hinge sits at the origin.
    const j = struct {
        fn at(bx: f32, by: f32, bz: f32) rl.Vector3 {
            return v3(bx - P_JAW.x, by - P_JAW.y, bz - P_JAW.z);
        }
    }.at;
    b.setMat(.hide);
    b.addBlob(j(0, 0.18, 0.26), v3(0.31, 0.055, 0.25), 8, 14, HIDE); // the jaw's shovel mass
    for ([_]f32{ -1, 1 }) |sgn| {
        const k: f32 = if (sgn < 0) 1.05 else 0.95; // rami uneven
        b.addBlob(j(sgn * 0.20, 0.19, 0.18), v3(0.12 * k, 0.05, 0.16 * k), 6, 11, HIDE);
    }
    b.setMat(.skin);
    b.addBlob(j(0, 0.145, 0.26), v3(0.28, 0.05, 0.22), 7, 12, BELLY); // pale chin underside
    b.addBlob(j(0, 0.225, 0.30), v3(0.24, 0.025, 0.16), 6, 12, TONGUE); // fleshy floor
    b.addBlob(j(0, 0.235, 0.36), v3(0.10, 0.022, 0.09), 5, 9, TONGUE); // the tongue's fat root hump
    b.setMat(.hide);
    b.addBlob(j(0, 0.235, 0.47), v3(0.30, 0.032, 0.062), 8, 14, HIDE_DK); // lower lip rim
    toothRow(&b, .{ .seed = 6421, .tuskLen = 0.19, .toothLen = 0.115, .tuskRad = 0.042, .toothRad = 0.028, .dirY = 1, .zlean = 0.08, .z0 = 0.49, .zCurve = 0.55, .shift = P_JAW });
    return b.toMesh();
}

// Throat sac — authored about P_SAC at the origin; a pale distendable pouch under the chin.
fn throatMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin); // stretched membrane — soft mottle, no warts
    b.addBlob(v3(0, -0.025, 0.01), v3(0.24, 0.11, 0.20), 8, 13, SAC);
    b.addBlob(v3(0.015, -0.075, 0.07), v3(0.165, 0.065, 0.14), 7, 11, SAC); // the droop, slung a shade off-centre
    return b.toMesh();
}

// Back-leg thigh — authored at the hip origin, a fat haunch reaching up to the folded knee.
fn thighMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0xF60601 else 0xF60602);
    b.setMat(.hide);
    const knee = v3((P_KNEE.x - P_HIP.x) * side, P_KNEE.y - P_HIP.y, P_KNEE.z - P_HIP.z);
    b.addCapsule(v3(0, 0, 0), knee, 0.19, 0.125, 12, HIDE);
    const bulge = v3(knee.x * 0.42, knee.y * 0.42 + 0.02, knee.z * 0.42 - 0.03);
    b.addBlob(bulge, v3(0.215 * rng.range(0.95, 1.05), 0.185, 0.20 * rng.range(0.95, 1.06)), 8, 13, HIDE_LT); // the great haunch muscle, its own size each side
    b.addBlob(knee, v3(0.135, 0.125, 0.13), 7, 12, HIDE); // knee knuckle
    return b.toMesh();
}

fn shankMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0x5A4E01 else 0x5A4E02);
    b.setMat(.hide);
    // Foot target relative to the knee (knee sits at P_KNEE in the body frame; foot ~ground, forward + slightly out).
    const foot = v3(-0.10 * side, 0.0 - P_KNEE.y, 0.16 - P_KNEE.z);
    b.addCapsule(v3(0, 0, 0), foot, 0.11, 0.05, 10, HIDE); // shin
    // Webbed foot: a soft pad + three splayed toes fanning forward, each its own length.
    const heel = foot;
    b.addBlob(v3(heel.x, heel.y + 0.015, heel.z + 0.05), v3(0.16, 0.028, 0.15), 6, 11, HIDE_DK);
    for ([_]f32{ -1, 0, 1 }) |t| {
        const tl = rng.range(0.17, 0.215);
        const toe = v3(heel.x + t * (0.115 + rng.range(-0.01, 0.015)), heel.y + 0.005, heel.z + tl);
        b.addCapsule(v3(heel.x + t * 0.05, heel.y + 0.02, heel.z + 0.05), toe, 0.030, 0.014, 6, HIDE_DK);
        b.addBlob(v3(toe.x, toe.y, toe.z + 0.015), v3(0.014, 0.011, 0.026), 4, 7, CLAW); // little claw tip
    }
    return b.toMesh();
}

// Front leg — authored at the shoulder origin; small, splayed, planting forward.
fn armMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0xA2601 else 0xA2602);
    b.setMat(.hide);
    const hand = v3(0.02 * side, -0.26, 0.16);
    b.addCapsule(v3(0, 0, 0), hand, 0.072, 0.043, 9, HIDE);
    b.addBlob(v3(hand.x, hand.y - 0.006, hand.z + 0.03), v3(0.105, 0.026, 0.10), 5, 9, HIDE_DK); // splayed hand pad
    for ([_]f32{ -1, 0, 1 }) |t| {
        const fl = rng.range(0.05, 0.075);
        b.addCapsule(v3(hand.x + t * 0.045, hand.y - 0.004, hand.z + 0.06), v3(hand.x + t * 0.055, hand.y - 0.008, hand.z + 0.06 + fl), 0.014, 0.008, 5, HIDE_DK);
        b.addBlob(v3(hand.x + t * 0.056, hand.y - 0.008, hand.z + 0.065 + fl), v3(0.010, 0.009, 0.016), 4, 7, CLAW);
    }
    return b.toMesh();
}


test "THE LEAP IS AN INSTANT FROM BEING SWATTED, and nothing else the toad does is catchable" {
    try std.testing.expect(PARRY_LEAD > 0);
    // An INSTANT, not a slice of the tell: its 0.70 s coil must not be catchable for a fifth of itself.
    try std.testing.expect(PARRY_LEAD < LUNGE_COIL * 0.25);
    // …and it falls inside the FLIGHT, which is what makes the catch a body swatted out of the air.
    try std.testing.expect(PARRY_LEAD < LUNGE_FLIGHT);

    var f = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    f.startHop(mathx.ground(0, 4), 60.0, true);
    const impact = LUNGE_COIL + f.hopDur;
    // MEASURED off the state machine: walk the leap from the first frame of its coil and collect the span that
    // is actually parryable. ONE clock here — coil, arc and landing are all `.lunge`.
    const step = 1.0 / 600.0;
    var open: f32 = -1;
    var shut: f32 = -1;
    var elapsed: f32 = 0;
    while (elapsed <= impact) : (elapsed += step) {
        f.t = elapsed;
        if (f.parryable() != null) {
            if (open < 0) open = elapsed;
            shut = elapsed;
        }
    }
    try std.testing.expect(open > 0);
    // It ENDS where the body arrives — the frame `tryImpact` fires — and it is exactly the lead long.
    try std.testing.expectApproxEqAbs(impact, shut, 2.0 * step);
    try std.testing.expectApproxEqAbs(PARRY_LEAD, shut - open, 3.0 * step);
    // …and the reach it is offered at is the SLAM's own, never a second number.
    try std.testing.expectApproxEqAbs(LUNGE_IMPACT_R + HERO_REACH, f.parryable().?, 1e-5);

    // THE APPROACH HOP CARRIES NO BLOW, and the CHOMP is deliberately out: jaws you step out of.
    for ([_]State{ .idle, .hop, .recover, .chomp, .stunlight, .stunheavy, .dead }) |s| {
        f.state = s;
        f.t = 0;
        try std.testing.expect(f.parryable() == null);
        f.t = CHOMP_GAPE - PARRY_LEAD * 0.5; // …including exactly where a bite's window WOULD have been
        try std.testing.expect(f.parryable() == null);
    }
}

test "A CAUGHT LEAP NEVER ARRIVES, and the toad comes straight down out of the air" {
    var f = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // faces +Z
    const hero = v3(0, 0, 1.5);
    f.startHop(hero, 60.0, true);
    f.facing = 0; // squarely at him, whatever `startHop` aimed
    f.t = LUNGE_COIL + f.hopDur - PARRY_LEAD * 0.5;
    f.lift = 0.9; // mid-arc: well off the ground
    // The boards up but pointed the WRONG WAY: nothing is caught (`foe.Parry` uses the block's own arc).
    f.parry = .{ .live = true, .at = hero, .facing = 0 };
    f.takeParry();
    try std.testing.expect(!f.parried and f.state == .lunge); // the body keeps coming
    // …and squared onto it, it is swatted. Its stance is well under one catch, so this is the sprawl.
    f.parry = .{ .live = true, .at = hero, .facing = std.math.pi }; // hero faces -Z, i.e. at it
    f.takeParry();
    try std.testing.expect(f.parried);
    try std.testing.expect(f.state == .stunlight or f.state == .stunheavy);
    try std.testing.expect(!f.heroLatch); // the slam it never got to is re-armed, not spent
    try std.testing.expect(f.lungeCd > 0); // …and it cannot pounce straight back out of the sprawl
    // IT COMES STRAIGHT DOWN: the stun resolvers write `lift` from scratch, so one frame of the reaction is
    // enough to put a body caught in mid-air back on the earth.
    _ = f.update(1.0 / 60.0, hero, 60.0, .{});
    try std.testing.expect(!f.airborne());
}

test "classify: ranges pick chomp < lunge < hop < rest, and cooldowns gate" {
    try std.testing.expectEqual(Choice.rest, classify(AGGRO_R + 1, true, true, false));
    try std.testing.expectEqual(Choice.hop, classify((LUNGE_R + AGGRO_R) * 0.5, true, true, false));
    try std.testing.expectEqual(Choice.lunge, classify(LUNGE_R - 0.5, true, true, false));
    try std.testing.expectEqual(Choice.hop, classify(LUNGE_R - 0.5, false, true, false)); // lunge cooling → hop in
    try std.testing.expectEqual(Choice.chomp, classify(BITE_R - 0.2, true, true, false));
    try std.testing.expectEqual(Choice.wait, classify(BITE_R - 0.2, true, false, false)); // in bite range, chomp cooling
}

test "ROOTED, A TOAD HAS ONLY ITS JAWS — every other move it owns leaves the ground" {
    // The hop and the lunge both go, at every range that would otherwise want one…
    try std.testing.expectEqual(Choice.wait, classify(LUNGE_R - 0.5, true, true, true));
    try std.testing.expectEqual(Choice.wait, classify((LUNGE_R + AGGRO_R) * 0.5, true, true, true));
    try std.testing.expectEqual(Choice.wait, classify(AGGRO_R + 1, true, true, true)); // …the hop HOME included
    // …and the bite does not: the roots take the feet, not the mouth.
    try std.testing.expectEqual(Choice.chomp, classify(BITE_R - 0.2, true, true, true));
}

test "a held toad never leaves the earth, and pounces again the moment it is let go" {
    var f = Frog.spawn(mathx.zero3, 0, 1, 0.4);
    f.root.grab();
    var t: f32 = 0;
    while (t < combat.ROOT_HOLD * 0.9) : (t += 1.0 / 60.0) {
        _ = f.update(1.0 / 60.0, v3(0, 0, LUNGE_R - 0.5), 500.0, .{});
        try std.testing.expect(!f.airborne());
        try std.testing.expect(f.lift <= 0.0001);
    }
    f.root.release();
    var left = false;
    t = 0;
    while (t < 3.0) : (t += 1.0 / 60.0) {
        _ = f.update(1.0 / 60.0, v3(0, 0, LUNGE_R - 0.5), 500.0, .{});
        if (f.airborne()) left = true;
    }
    try std.testing.expect(left);
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

test "AN ARROW AGGROS IT FROM OUTSIDE ITS OWN SENSES, and it comes for him" {
    var f = Frog.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    const hero = mathx.ground(0, AGGRO_R + 30); // FAR outside what it can see
    // Left alone it does not care.
    var k: u32 = 0;
    while (k < 120) : (k += 1) _ = f.update(1.0 / 60.0, hero, 200, .{});
    try std.testing.expect(!f.leash.roused());
    try std.testing.expect(mathx.distXZ(f.pos, hero) > AGGRO_R);
    // …and it reasons as if he were not there, because he is not.
    try std.testing.expect(foe.sensedDist(&f.leash, mathx.distXZ(f.pos, hero), AGGRO_R) > AGGRO_R);

    // ONE SHAFT, arriving from his direction.
    const shaftAt = f.centerWorld();
    const blade = foe.Blade{
        .active = true,
        .pierce = true,
        .r = 0.4,
        .a = mathx.addV(shaftAt, mathx.v3(0, 0, 2)),
        .b = mathx.addV(shaftAt, mathx.v3(0, 0, -0.2)),
        .a0 = mathx.addV(shaftAt, mathx.v3(0, 0, 2)),
        .b0 = mathx.addV(shaftAt, mathx.v3(0, 0, -0.2)),
        .hit = .{ .dmg = 5, .poise = 1 },
    };
    const before = f.hits;
    f.tryHit(blade);
    try std.testing.expect(f.hits > before);
    try std.testing.expect(f.leash.roused());
    try std.testing.expect(foe.sensedDist(&f.leash, mathx.distXZ(f.pos, hero), AGGRO_R) <= AGGRO_R);
    try std.testing.expect(@abs(mathx.wrapPi(f.facing - mathx.headingXZ(mathx.v3(0, 0, 1)))) < 0.2);
    // …and it actually CLOSES the ground rather than merely being annoyed — and KEEPS closing.
    const startD = mathx.distXZ(f.pos, hero);
    k = 0;
    while (k < 240) : (k += 1) _ = f.update(1.0 / 60.0, hero, 200, .{});
    try std.testing.expect(f.leash.roused());
    try std.testing.expect(mathx.distXZ(f.pos, hero) < startD - 5.0);
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

test "NO ATTACK COMES OUT OF NOWHERE: the gape and the coil are both real tells" {
    try std.testing.expect(CHOMP_GAPE >= foe.TELL_MIN);
    try std.testing.expect(LUNGE_COIL >= foe.TELL_MIN);
    // The lunge is the committed one, so it announces itself for longer than the bite does.
    try std.testing.expect(LUNGE_COIL > CHOMP_GAPE);
}
