const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const heromod = @import("hero.zig"); // THE SHARED RIG HELPERS — `setJoint` and `rootAt`, which every creature poses through

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

// THE FEN LURKER (owner's creature, owner's brief) — a thing that lives UNDER the painted water and comes up
// when you wade.
//
// **IT IS THE FIRST THING IN THIS WORLD THAT THE WATER IS FOR.** The sheet of water has been authored since
// the map was: one level plane, painted, walked through, slowing him down and drowning him past `WADE_MAX` —
// and nothing at all lived in it. Every creature before this one fights on the dirt beside it.
//
// **THE COUNTER IS DRY LAND, AND THAT IS THE WHOLE FIGHT.** It is a FIXTURE (the rooted's shelf): it never
// travels, it guards the pool it is in, and it cannot follow you out. What it sells is that the water is the
// short way and the shore is the long way round — so every one of these is a question about whether you are
// in a hurry.
//
// **AND IT IS ONLY THERE WHILE IT IS UP.** Sunk it is a wake on the surface: no bar, no reticle, and a sword
// through it hits water (the delver's law, `hidden`). You do not fight this creature at a time of your
// choosing; you make it come up by standing where it can feel you, and the window is the one it gives you.

/// How far out of the water the head rides at full surge, in metres — its own stature, and everything on the
/// rig is a fraction of it. Over the hero's own 1.8 so the thing that comes up is looking DOWN at him.
pub const H: f32 = 2.55;

/// It feels this far through the water. Generous, because it cannot come after you: the ring is what makes
/// crossing a pool a decision rather than a surprise.
pub const AGGRO_R: f32 = 9.0;

/// **HOW DEEP HE HAS TO BE STANDING FOR IT TO FEEL HIM AT ALL.** Ankle-deep is enough: the trigger is being
/// IN the water rather than being far into it, or the creature would only ever answer the one strip of pool
/// nobody crosses anyway. Well under `env.WADE_MAX` (1.37), which is the depth that refuses him outright.
pub const WADE_MIN: f32 = 0.30;

/// …AND HOW DEEP ITS OWN POST HAS TO BE for it to be able to sink at all. A lurker posted on dry ground by a
/// careless map is a lurker with nowhere to hide, and the honest answer is that it simply stays up and
/// fights — never that it vanishes standing in a field.
pub const POOL_MIN: f32 = 0.22;

const BODY_R: f32 = 0.52;
/// **THE HURT SPHERE IS UP THE NECK, NOT DOWN IN THE COIL.** What a sword can reach of this creature is the
/// part that came out of the water, and fitted to the coil at the waterline the sphere sat at his shins with
/// two metres of neck and a head standing outside anything he could swing at. Solved to span the surface up
/// past the head at full surge.
const HURT_R: f32 = 0.98;
const CENTER_F: f32 = 0.62;
/// …and the CROWN is the head at full surge, which is what a bar hangs over and what a flyer clears.
const TOP_F: f32 = 1.12;

/// Sturdier than a sporeling, under a rooted's 130: it is a real body, and the fight is short because you
/// choose when it starts and it chooses when it ends.
const HP_MAX: f32 = 78.0;
/// It flinches off a hero heavy (22) and not off a light (10) — the ravager's own sizing, because a thing
/// with a window this narrow may not be stunlockable inside it.
const POISE_MAX: f32 = 20.0;
const STANCE_MAX: f32 = 36.0;
/// **WET FLESH IN STANDING WATER, AND THAT IS THE FIRST REAL LIGHTNING TARGET IN THE GAME.** Fire is most of
/// the way useless on a thing that lives submerged, cold it has lived in all its life — and the levin strike,
/// the thundercrock and the storm-tipped shaft have been in the world with nothing that especially minded
/// them. A creature standing in its own conductor is what makes that arm worth carrying.
const RESISTS = combat.resists(.{ .fire = 45, .cold = 25, .lightning = -60, .chaos = 0 });

pub const SOULS: u32 = 170;

const DEATH_DUR: f32 = 1.15;
const DISS_DUR: f32 = 1.0;
/// It sheds SILT AND WATER, not bone or chitin — the one line of the shared dissolve that is its own.
const DISSOLVE = foe.Dissolve{ .rate = 60.0, .spread = 0.95, .rise = 0.55, .flake = SILT };
const PARTS = 72;

// ── THE MOVE, AND IT IS THE ONLY ONE ───────────────────────────────────────────────────────────────────
//
// One creature, one stroke. It is a fixture with a window: a second attack would be a second thing to read
// inside a window that is already the whole of what the player is being asked to judge.

/// **THE SURGE IS THE TELL AND IT IS LONG.** What is being read is not the lash — a head coming down out of
/// two metres is legible by itself — it is that the water broke at all. Well over `foe.TELL_MIN`, and the
/// wake starts before the body does (`WAKE_LEAD`).
const SURGE_DUR: f32 = 0.72;
const LASH_DUR: f32 = 0.20;
const RECOVER_DUR: f32 = 0.62;
/// How long it takes to go back under, and it is SLOW: the sink is the punish window, so a creature that
/// dropped out of reach the frame its stroke ended would be a creature with no cost at all.
const SINK_DUR: f32 = 0.85;
/// …and how long it waits down there before it can come up again.
const REST_DUR: f32 = 1.10;

/// **THE WAKE LEADS THE BODY.** Seconds of surface disturbance before anything breaks it — the one warning
/// that arrives while he can still be somewhere else, and the reason this creature is not a gotcha.
const WAKE_LEAD: f32 = 0.45;

/// WHAT THE HEAD DOES. Heavy on poise and it carries stance: it is a mass falling out of the air, and the
/// thing it is meant to punish is being caught mid-swing in water you cannot roll in.
pub const LASH_HIT = combat.Hit{ .dmg = 26, .poise = 24, .stance = 11 };

/// How far out the head reaches at the strike, off the creature's own centre — MEASURED off the posed rig by
/// the test at the foot of this file, never guessed.
const LASH_R: f32 = 2.35;
/// …and the frontal cone, the toad's own dial: a head that whipped past him does not take him in the back.
const LASH_FRONT_DOT: f32 = 0.30;
/// THE HEAD'S OWN HALF-WIDTH, which its reach and its measured height are both taken over — a flat skull
/// coming down is a mass, not a point.
const HEAD_R: f32 = 0.34;

const TURN_RATE: f32 = 2.2; // rad/s — it pivots on a coil, and being out-turned is half of leaving

pub const SHOVE = foe.Push{ .light = 0.55, .heavy = 1.30 }; // it is anchored: a blow rocks it, it does not move it
const SHOVE_DECAY: f32 = 9.0;

// ── THE RIG ────────────────────────────────────────────────────────────────────────────────────────────
//
// **ITS OWN CHAIN, AND THAT IS NOT THE SCAFFOLD LAW BEING BROKEN.** `hero.restHumanoid` is shared because
// eleven creatures are honestly a man's layout at another size; the quadruped's is shared for the same
// reason. A neck is a RUN OF EQUAL SEGMENTS with a head on it — no pelvis, no girdle, no limbs — and
// transcribing eighteen humanoid joints to leave fifteen of them at rest would be the copy the law forbids,
// not the reuse it asks for.

pub const N = 10;
const ROOT = 0;
const S0 = 1;
const S1 = 2;
const S2 = 3;
const S3 = 4;
const S4 = 5;
const HEAD = 6;
const JAW = 7;
const BARBL = 8;
const BARBR = 9;
/// The neck's own segments, root-most first — named so the pose can walk them rather than write five lines.
const NECK = [_]usize{ S0, S1, S2, S3, S4 };
pub const PARENT = [N]i32{ -1, ROOT, S0, S1, S2, S3, S4, HEAD, HEAD, HEAD };

/// How long one neck segment is, as a fraction of `H`. Five of them plus the head's own run is the whole
/// stature, so this is the number the rig is actually built out of.
const SEG: f32 = 0.185;

/// THE REST CHAIN — straight up out of the coil. Both the mesh builder and the pose take it from here, so a
/// segment lengthened is one lengthened in the picture too.
///
/// **ABSOLUTE POSITIONS, NOT OFFSETS FROM THE PARENT** — which is `hero.restHumanoid`'s convention and every
/// other rig's in the game. Written as offsets this file needed its own `setJoint` (a second way to do the one
/// operation every creature does) and its own `rootAt`; on the house convention both are `hero`'s, and the
/// only thing this rig has that the others do not is its own shape.
fn restPose() [N]rl.Vector3 {
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, 0, 0);
    var y: f32 = 0;
    for (NECK, 0..) |b, i| {
        y += if (i == 0) SEG * H * 0.6 else SEG * H;
        r[b] = v3(0, y, 0);
    }
    r[HEAD] = v3(0, y + SEG * H * 0.85, 0);
    // The jaw hangs UNDER the head and a little forward of it; the barbels sit either side of the snout.
    r[JAW] = v3(r[HEAD].x, r[HEAD].y - 0.030 * H, r[HEAD].z + 0.055 * H);
    r[BARBL] = v3(r[HEAD].x + 0.055 * H, r[HEAD].y - 0.010 * H, r[HEAD].z + 0.070 * H);
    r[BARBR] = v3(r[HEAD].x - 0.055 * H, r[HEAD].y - 0.010 * H, r[HEAD].z + 0.070 * H);
    return r;
}

// ── THE PALETTE ────────────────────────────────────────────────────────────────────────────────────────
//
// **AUTHOR DARK, AND SOLVE IT** — albedo x 1.72 -> linear -> gamma 1/2.2, so screen goes as albedo^(1/2.2)
// and the bigger and smoother the mass the darker it must start. A wet hide is the smoothest thing in this
// world and it comes up against a WATER SHEET rather than against the field, which is the brighter backdrop
// of the two: so this is authored under the ravager's own hide, not level with it.

/// THE HIDE — a drowned green-black, and it may not go warm: everything else outdoors here is warm, and the
/// one thing that says "this came out of the water" before it moves is that it does not match the bank.
const HIDE = rgba(9, 13, 11, 208);
const HIDE_LT = rgba(14, 19, 16, 194);
const HIDE_DK = rgba(5, 8, 7, 214);
/// The BELLY and the throat, pale and slack — the underside of anything that lives face-down in silt.
const BELLY = rgba(48, 52, 42, 200);
/// The silt it sheds and dies into.
const SILT = rgba(74, 68, 52, 190);
/// **THE EYES, AND THEY ARE THE ONLY BRIGHT THING ON IT.** Vertex alpha is the emissive channel and LOWER is
/// more self-lit: after dark, over black water, the two lamps coming up are the whole of the warning. Pale
/// green rather than the ravager's hot pink — two creatures whose read is a light in the dark may not be the
/// same light.
const EYE = rgba(180, 226, 150, 40);
/// …and the GULLET behind the teeth, which is what opens on the lash.
const GULLET = rgba(122, 44, 48, 96);
const TOOTH = rgba(206, 200, 176, 235);

pub const State = enum { sunk, surge, lash, recover, sink, hurt, dead };

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("fen lurker material");
        mat.shader = shader;
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, l: *const Lurker) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, l.xf[i]);
    }
};

pub const Lurker = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// The wand's roots and the rime's cold, both stamped from outside and billed through `foe.grip`. The
    /// FEET half is a no-op on a thing that never travels; the BITE is not.
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    /// **HOW DEEP THE WATER IS, HERE AND UNDER ITS QUARRY** (`foe.Wade`) — stamped by `game.markWade`,
    /// because only the game can see this creature and `env`'s water field at once. THE FIELD IS THE OPT-IN:
    /// nothing else in the game carries one, and nothing else pays for the pass.
    wade: foe.Wade = .{},
    threat: foe.Threat = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,
    state: State = .sunk,
    t: f32 = 0,
    elapsed: f32 = 0,
    restT: f32 = 0,

    /// **HOW FAR OUT OF THE WATER IT IS**, 0..1 — one scalar, read off the state's own clock and nowhere
    /// else, so the picture cannot promise a body the mechanic says is not there. It is what the pose rides,
    /// what `hidden` is asked of, and what decides whether a sword can reach it.
    up: f32 = 0,
    /// …and HOW FAR THROUGH THE LASH, −1 (reared back) … 1 (thrown all the way down).
    swing: f32 = 0,
    /// The swing one and two segments late — the neck's mass flows root to tip on its own, and five segments
    /// peaking on one frame read as one welded pole however big the arc.
    swingL1: f32 = 0,
    swingL2: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    /// …AND THE OUTGOING ONE, which is a different fact: one lash, one blow, however many frames the strike
    /// window is live for.
    heroLatch: bool = false,
    heroHit: ?combat.Hit = null,
    heavyStun: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    /// The voices' one-frame edges, cleared at the top of `update`. The creature says WHEN; `game.zig` owns
    /// the speaker, or a creature would play through the pause card and the shot harness.
    broke: bool = false,
    lashed: bool = false,
    yelped: bool = false,
    sank: bool = false,

    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    rest: [N]rl.Vector3 = undefined,
    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Lurker {
        var l = Lurker{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale,
            .seed = seed,
            .rest = restPose(),
        };
        l.fxRng = foe.fxStream(seed, 60271.0, 0x3E7);
        l.restT = seed * REST_DUR; // stagger a line of them so a marsh does not surface in lockstep
        l.pose();
        return l;
    }

    pub fn kind(_: *const Lurker) wf.FoeKind {
        return .fen_lurker;
    }

    pub fn centerWorld(self: *const Lurker) rl.Vector3 {
        // **THE SPHERE RIDES THE SURGE.** Fixed at the coil it would be a hurt box floating over open water
        // while the body it belongs to was still down; taken off `up` it is where the creature actually is.
        return foe.bodyPoint(self.pos, CENTER_F * H * self.up, self.scale, 0);
    }
    pub fn lockPoint(self: *const Lurker) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0.02 * H, 0.05 * H));
    }
    /// **THE CROWN IS HOW TALL THE CREATURE IS, NOT HOW FAR UP IT HAPPENS TO BE.** Scaled by `up` it answered
    /// 0.43 m to anything that asked while the thing was down — and `shots.runMapShots` solves its whole
    /// camera off this BEFORE staging the pose, so it framed a creature the size of a stone and then the real
    /// one rose two and a half metres out of the top of the plate. Nothing was bought by the scaling either:
    /// no bar hangs over a sunk one because `disguised` reads `hidden` and skips it outright (`game.BarCtx`).
    pub fn topWorld(self: *const Lurker) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Lurker) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Lurker) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Lurker) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Lurker) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Lurker) bool {
        return self.state == .hurt or self.state == .dead;
    }
    /// It never leaves the ground it is standing on — coming up out of water is not flight, and the terrain
    /// gate has to keep holding it to its own bed.
    pub fn airborne(_: *const Lurker) bool {
        return false;
    }
    pub fn flashFrac(self: *const Lurker) f32 {
        return foe.flashFrac(self.flash);
    }

    /// **UNDER THE SURFACE, AND THEREFORE NOT THERE** — the reticle refuses it, no bar hangs over it, and
    /// `tryHit` returns without looking (the rooted's `hidden`, the delver's law about being down). ONE
    /// predicate, read off `up` and nothing else, so what a sword can reach is what the eye can see.
    pub fn hidden(self: *const Lurker) bool {
        return self.up <= SHOW_AT;
    }

    /// **AND NOTHING UNDER THE SURFACE IS IN HIS WAY.** A separate question from `hidden`, though today it is
    /// the same answer: that one is about being SEEN (the reticle, the bar, the sword), this one is about
    /// being SOLID. They have to be separate because the rooted answers them differently — a dormant snag is
    /// invisible as a creature and still very much a tree you walk into.
    ///
    /// Without it the hero swims into a wall he cannot see: `game.collideActors` pushes him out of every
    /// corporeal body whose crown clears his feet, and a sunk lurker's crown is its full 2.9 m.
    pub fn phased(self: *const Lurker) bool {
        return self.hidden();
    }

    /// WHERE THE JAWS ARE — one definition, because the blow's reach and the shot harness both need it and as
    /// two copies the offset down the head was a literal that had to agree with itself.
    pub fn jawPoint(self: *const Lurker) rl.Vector3 {
        return foe.markOn(self.xf[JAW], v3(0, 0, 0.10 * H));
    }

    /// Is the water where it is posted deep enough to hide in at all? A lurker a careless map put on dry
    /// ground STAYS UP and fights rather than sinking into a field — the honest failure, and the one a player
    /// can make sense of.
    pub fn pooled(self: *const Lurker) bool {
        return self.wade.here >= POOL_MIN;
    }

    /// **IS HE STANDING IN IT** — the whole trigger, and it is a fact about the GROUND HE IS ON. Never about
    /// what he pressed (the input-reading law): a thing under the surface feels a body in its water, and it
    /// would feel a spirit's paws exactly as well.
    fn feels(self: *const Lurker, hero: rl.Vector3) bool {
        if (self.wade.quarry < WADE_MIN) return false;
        return mathx.distXZ(self.pos, hero) <= AGGRO_R;
    }

    fn faceToward(self: *Lurker, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    fn enter(self: *Lurker, s: State) void {
        self.state = s;
        self.t = 0;
    }

    /// ONE FRAME. Returns the blow it landed on whoever it is fighting, or null.
    pub fn update(self: *Lurker, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        // **CLEARED BEFORE THE `gone` BRANCH** (the necromancer's law, and the mage's): reset only on the live
        // path, a body that left the field holding one holds it for good, and `game.zig` reads all five off a
        // `live()` that still carries the gone members.
        self.justDied = false;
        self.heroHit = null;
        self.broke = false;
        self.lashed = false;
        self.yelped = false;
        self.sank = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.stateStep(dt, hero, bounds);
        // AFTER THE POSE (`stateStep` ends on one), so the swept test meets the body where it is drawn this
        // frame rather than where it stood last.
        self.tryHit(blade);
        return self.heroHit;
    }

    fn stateStep(self: *Lurker, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();

        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        self.restT = mathx.maxF(0, self.restT - dt);
        // Measured from its POST, like every tether: the question is whether he has left its patch.
        self.leash.tick(dt, 0, mathx.distXZ(self.home, hero), AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        // **THE PLAY AREA'S OWN BOUND, not a sentinel.** It never travels under its own power, but a blow
        // still rocks it — and `applyShove` steps through the shared bounded step, so handed `LONG_AGO` the
        // one thing that CAN move this creature was the one thing allowed to move it out of the world.
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        switch (self.state) {
            .dead => {
                // IT SINKS AS IT GOES, which is most of what says it is finished from the bank.
                self.up = mathx.approach(self.up, 0, dt / SINK_DUR);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
            .hurt => {
                // **A STAGGER DOES NOT PUT IT UNDER.** The flinch is the punish window, and a creature that
                // used being hit as its cue to leave would be one you are never allowed to finish.
                self.up = mathx.approach(self.up, 1.0, dt * 2.2);
                if (self.t >= combat.foeStunDur(self.heavyStun)) self.enter(.recover);
            },
            // NOTHING BUT A WAKE. It does not turn, it does not rise, and it is not a creature until he is
            // standing in its water — or until a blade finds it, which cannot happen while it is down.
            .sunk => {
                self.up = mathx.approach(self.up, 0, dt / SINK_DUR);
                if (!self.pooled()) {
                    // NOWHERE TO HIDE: a lurker posted on dry ground simply stands up and fights.
                    if (self.feelsDry(hero)) self.begin(hero);
                    return self.settleAndPose(dt);
                }
                if (self.restT <= 0 and self.feels(hero)) self.begin(hero);
            },
            // **THE SURGE, AND IT IS THE TELL.** It aims through the whole of it and not after: what he is
            // reading is which way the head is pointed when it stops rising.
            .surge => {
                self.faceToward(hero, dt);
                self.up = mathx.smoothstep(0, SURGE_DUR, self.t);
                // COCKED BACK across the rise, so the head goes the wrong way first — the one thing that
                // says a stroke is coming rather than a body merely arriving.
                self.swing = -mathx.smoothstep(SURGE_DUR * 0.35, SURGE_DUR, self.t);
                if (self.t >= SURGE_DUR) {
                    self.enter(.lash);
                    self.lashed = true;
                }
            },
            .lash => {
                self.up = 1.0;
                const u = mathx.clampF(self.t / LASH_DUR, 0, 1);
                self.swing = lerpF(-1.0, 1.0, foe.swingCurve(u));
                // ANYWHERE INSIDE THE WINDOW, ONCE — a head is a mass the size of a shield, so what it needs
                // is a reach and a FRONT, not a moment.
                self.tryLash(hero);
                if (self.t >= LASH_DUR) self.enter(.recover);
            },
            .recover => {
                self.up = 1.0;
                self.swing = mathx.approach(self.swing, 0, dt * 2.6);
                self.heroLatch = false;
                if (self.t >= RECOVER_DUR) {
                    // **IT GOES DOWN WHEN HE IS OUT OF THE WATER, AND STAYS UP WHILE HE IS IN IT.** Which is
                    // the fight: leaving is the answer, and it is an answer you have to actually take.
                    if (self.canReach(hero)) {
                        self.enter(.surge);
                        self.t = SURGE_DUR * 0.45; // …already up, so the second stroke is a shorter gather
                    } else self.beginSink();
                }
            },
            .sink => {
                self.up = 1.0 - mathx.smoothstep(0, SINK_DUR, self.t);
                self.swing = mathx.approach(self.swing, 0, dt * 2.0);
                // **AND IT COMES STRAIGHT BACK UP IF HE STEPS BACK IN**, from wherever the sink had got to —
                // a creature you could bait down and then walk past would be a creature with no ring at all.
                if (self.pooled() and self.canReach(hero)) {
                    self.enter(.surge);
                    self.t = SURGE_DUR * self.up;
                    return self.settleAndPose(dt);
                }
                if (self.t >= SINK_DUR) {
                    self.restT = REST_DUR;
                    self.enter(.sunk);
                }
            },
        }
        self.settleAndPose(dt);
    }

    /// The gather, from wherever it already is — driven from 0 the body SNAPS under on the frame it commits.
    fn begin(self: *Lurker, hero: rl.Vector3) void {
        self.faceToward(hero, 1.0); // it has been feeling him the whole time: the first turn is free
        self.enter(.surge);
        self.heroLatch = false;
        self.broke = true; // ON THE GATHER: the water breaking is the tell, and it leads the blow
    }

    /// A lurker with no water to hide in answers to plain distance instead, since the depth test it would
    /// otherwise ask can never be true.
    fn feelsDry(self: *const Lurker, hero: rl.Vector3) bool {
        return mathx.distXZ(self.pos, hero) <= AGGRO_R;
    }

    /// Would it come up for him from here — the ONE question the surge, the resurface and the sink all ask,
    /// so the three cannot disagree about what "he is in my water" means.
    fn canReach(self: *const Lurker, hero: rl.Vector3) bool {
        if (self.leash.goingHome()) return false;
        return if (self.pooled()) self.feels(hero) else self.feelsDry(hero);
    }

    fn beginSink(self: *Lurker) void {
        self.enter(.sink);
        self.sank = true;
    }

    fn settleAndPose(self: *Lurker, dt: f32) void {
        // THE LAG IS THE NECK'S, NOT THE MOVE'S — exponential followers, ticked through every state including
        // the stuns, so the mass flows root to tip whatever the creature is doing.
        self.swingL1 = mathx.approach(self.swingL1, self.swing, dt * LAG_1);
        self.swingL2 = mathx.approach(self.swingL2, self.swingL1, dt * LAG_2);
        self.pose();
    }

    /// ONE LASH, ONE BLOW. Reach off the head's own span plus his hide (`foe.HERO_REACH`), and a FRONTAL cone.
    fn tryLash(self: *Lurker, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        const d = mathx.distXZ(self.pos, hero);
        if (d > LASH_R * self.scale + foe.HERO_REACH) return;
        const to = mathx.dirXZ(self.pos, hero);
        const fwd = mathx.headingDir(self.facing);
        if (d > 0.35 and to.x * fwd.x + to.z * fwd.z < LASH_FRONT_DOT) return;
        self.heroHit = LASH_HIT;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    /// A BLOW LANDING ON IT. **AND THE FIRST THING IT ASKS IS WHETHER THERE IS ANYTHING THERE** — under the
    /// surface a sword goes through water, which is the whole of what this creature sells.
    pub fn tryHit(self: *Lurker, blade_: foe.Blade) void {
        if (self.state == .dead or self.hidden()) return;
        const s = foe.reached(self, blade_) orelse return;
        const heavy = foe.wounded(self, s, blade_, SHOVE);
        self.splash(s.contact, if (heavy) 9 else 4);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    fn enterStun(self: *Lurker, heavy: bool) void {
        self.enter(.hurt);
        self.heavyStun = heavy;
        self.yelped = true;
    }

    fn enterDeath(self: *Lurker) void {
        if (self.state == .dead) return;
        self.enter(.dead);
        self.justDied = true;
    }

    pub fn debugStagger(self: *Lurker, heavy: bool) void {
        self.enterStun(heavy);
    }

    /// Stage the SURGE at its top, for the harness and for the measurement — a pose and nothing else: no
    /// blow, no cooldown spent (`wolf.stagePounce`'s pattern). `u` is how far through the tell.
    pub fn stageGather(self: *Lurker, u: f32) void {
        const k = mathx.clampF(u, 0, 1);
        self.state = .surge;
        self.t = k * SURGE_DUR;
        self.up = mathx.smoothstep(0, SURGE_DUR, self.t);
        self.swing = -mathx.smoothstep(SURGE_DUR * 0.35, SURGE_DUR, self.t);
        self.swingL1 = self.swing;
        self.swingL2 = self.swing;
        self.pose();
    }

    /// …and the LASH at its own moment, which is the frame the reach is judged on.
    pub fn stageLash(self: *Lurker, u: f32) void {
        const k = mathx.clampF(u, 0, 1);
        self.state = .lash;
        self.t = k * LASH_DUR;
        self.up = 1.0;
        self.swing = lerpF(-1.0, 1.0, foe.swingCurve(k));
        self.swingL1 = self.swing;
        self.swingL2 = self.swing;
        self.pose();
    }

    fn splash(self: *Lurker, at: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        const total = foe.hitParts(n);
        while (i < total) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.7, 2.1);
            foe.emitParticle(
                &self.parts,
                &self.fxHead,
                at,
                v3(mathx.cosf(a) * sp, self.fxRng.range(0.8, 2.6), mathx.sinf(a) * sp),
                self.fxRng.range(0.24, 0.50),
                self.fxRng.range(0.022, 0.050) * self.scale,
                0.005,
                if (self.fxRng.float() < 0.5) SPRAY else SILT,
                7.0, // WATER FALLS, and it falls hard: this is the one FX here that is not a mote
            );
        }
    }

    /// **THE WAKE — the only thing there is to see while it is down**, and it is emitted rather than posed
    /// because the body is not drawn at all down there. Off the accumulator (`foe.emitTicks`) so the ring is
    /// a RATE rather than a per-frame chance, and capped so one long frame cannot empty the pool.
    fn ripple(self: *Lurker, dt: f32) void {
        const n = foe.emitTicks(&self.fxAccum, dt, WAKE_RATE, foe.emitCap(WAKE_RATE));
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.25, 1.0) * WAKE_R * self.scale;
            const p = v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + WAKE_Y, self.pos.z + mathx.sinf(a) * rr);
            // OUTWARD AND FLAT — a ring spreading on a surface, never a puff going up: the one reads as
            // something moving under the water and the other reads as something already out of it.
            foe.emitParticle(
                &self.parts,
                &self.fxHead,
                p,
                v3(mathx.cosf(a) * WAKE_SPREAD, 0.02, mathx.sinf(a) * WAKE_SPREAD),
                self.fxRng.range(0.30, 0.62),
                self.fxRng.range(0.020, 0.038) * self.scale,
                0.055, // it GROWS: a ripple opens out as it goes
                SPRAY,
                0,
            );
        }
    }

    pub fn drawFx(self: *const Lurker) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Lurker, model: *const Model) void {
        // **NOTHING IS DRAWN WHILE IT IS UNDER.** The water sheet is opaque from above, so a body left drawn
        // down there is a creature lying in plain sight through the one surface that is meant to hide it —
        // and `hidden` is the same predicate the reticle and `tryHit` ask, so the three cannot disagree.
        if (self.gone or self.hidden()) return;
        model.draw(self);
    }

    /// THE POSE. One world matrix per bone, once a frame — `draw` only replays them.
    pub fn pose(self: *Lurker) void {
        const s = self.scale;
        const react: f32 = if (self.state == .hurt) foe.stunCurve(self.t, self.heavyStun) else 0;
        const fall: f32 = if (self.state == .dead) mathx.clampF(self.t / (DEATH_DUR * 0.7), 0, 1) else 0;
        // **THE WHOLE BODY RIDES `up`, AND IT RIDES IT AS A TRANSLATION.** Sunk it is simply below the sheet
        // rather than shrunk: a creature that scaled down into the water would read as one going away.
        const sink = -(1.0 - self.up) * SUBMERGE * H;
        // It breathes on its own slow clock, and only while it is up — a wake does not breathe.
        const breath = mathx.sinf(self.elapsed * 1.35 + self.seed * 6.28) * 0.010 * H * self.up;

        // **AND THE WHOLE BODY DIVES WITH THE STROKE, WHICH IS THE OTHER HALF OF HAVING A NECK.** A curled
        // chain moves the head SIDEWAYS more than down — five distributed bends keep far more height than one
        // hinge would, and MEASURED off the posed rig the jaws finished the lash at 2.04 m, which is over the
        // top of his head. The neck does the rearing and the BODY does the arriving. Forward only: it is a
        // dive, and a creature that also reared its whole coil would simply be standing further back.
        const dive = LASH_DIVE * mathx.maxF(0, self.swing);
        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            mul(scaleM(s, s, s), mul(rx(dive), rz(-38.0 * mathx.smoothstep(0, 1, fall)))),
            mul(tr(0, (sink + breath) * s, 0), ry(mathx.degrees(self.facing))),
            heromod.rootAt(self.pos),
        );

        // THE NECK — five segments, each taking a SHARE of the stroke and each later than the one below it.
        // The share rises toward the head (`SEG_BEND`), so the curve is a whip and not an arc struck about
        // one hinge, and the LAG is the bank's rather than each segment's own hand-rolled fraction.
        for (NECK, 0..) |b, i| {
            const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(NECK.len - 1));
            const lagged = switch (i) {
                0 => self.swing,
                1, 2 => self.swingL1,
                else => self.swingL2,
            };
            // THE REAR AND THE STROKE ARE ONE CHANNEL. Negative about X takes the head BACK over the coil and
            // positive brings it down and forward, which is the root's own sign one joint along.
            const bend = lerpF(SEG_BEND_LO, SEG_BEND_HI, u) * lagged;
            // …and a slow S the whole thing carries while it is simply standing there, so an idle lurker is
            // never a post. It dies away as the stroke takes over.
            const idle = mathx.sinf(self.elapsed * 1.1 - u * 2.2 + self.seed * 4.0) * IDLE_SWAY * (1.0 - @abs(lagged));
            heromod.setJoint(&wx, &self.rest, b, if (i == 0) ROOT else NECK[i - 1], mul(rx(bend + 14.0 * react * u), rz(idle)));
        }
        // THE HEAD, which carries the last of the stroke and counter-rotates the tail of it: a skull that
        // simply followed the neck reads as the end of a rope rather than as a thing aiming itself.
        heromod.setJoint(&wx, &self.rest, HEAD, S4, mul(rx(HEAD_BEND * self.swing - 26.0 * react), rz(-6.0 * self.swingL2)));
        // THE JAW opens across the stroke and clamps shut on a reaction.
        const gape = GAPE * mathx.clampF(self.swing * 0.5 + 0.5, 0, 1) * self.up - 34.0 * react;
        heromod.setJoint(&wx, &self.rest, JAW, HEAD, rx(gape));
        // THE BARBELS trail — they are the one part of it with no muscle, so they lag hardest and never lead.
        const trail = -18.0 * self.swingL2 + 10.0 * react;
        heromod.setJoint(&wx, &self.rest, BARBL, HEAD, mul(rx(trail), rz(-BARB_SPLAY - 5.0 * self.swingL2)));
        heromod.setJoint(&wx, &self.rest, BARBR, HEAD, mul(rx(trail), rz(BARB_SPLAY + 5.0 * self.swingL2)));
        self.xf = wx;
    }
};

/// How far under its own stature the body sits when it is fully down. Over 1, so the head clears the surface
/// on the way out rather than the crown sitting level with it.
const SUBMERGE: f32 = 1.18;
/// **THE THRESHOLD `hidden` IS ASKED ON.** Low, so the reticle and the sword arrive the moment the water
/// actually breaks — set high, there was a visible head nothing could be aimed at.
const SHOW_AT: f32 = 0.06;

/// **THE STROKE'S SHARE PER NECK SEGMENT, AND THESE COMPOUND.** Each joint is rotated relative to its
/// PARENT, so what the head ends up at is the SUM down the chain plus its own — five segments and a skull.
/// Authored as though each were absolute (9 rising to 27, plus 34) the total rear came to 124 degrees and
/// the creature lay down flat on the water with its head out of frame. `TOTAL_BEND` below is the sum, and a
/// test pins it: a number that is only correct as an aggregate has to be checked as one.
const SEG_BEND_LO: f32 = 3.5;
const SEG_BEND_HI: f32 = 11.0;
/// …and the head's own, which is the biggest single term: the skull is what arrives.
const HEAD_BEND: f32 = 15.0;
/// **WHAT THE WHOLE CHAIN COMES TO AT FULL STROKE** — the five segments summed plus the head. A rear is a
/// neck cocked back over its own coil, which is well under a right angle; past that it is an animal lying
/// down, and it was.
const TOTAL_BEND: f32 = blk: {
    var sum: f32 = 0;
    for (0..NECK.len) |i| {
        const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(NECK.len - 1));
        sum += SEG_BEND_LO + (SEG_BEND_HI - SEG_BEND_LO) * u;
    }
    break :blk sum + HEAD_BEND;
};
comptime {
    // A REAR, NOT A COLLAPSE. Under a right angle by a clear margin at one end, and enough to be read as a
    // cocked stroke at the other — the tell is the head going the WRONG WAY first, and five degrees is not one.
    std.debug.assert(TOTAL_BEND > 35.0 and TOTAL_BEND < 80.0);
}
/// **HOW FAR THE WHOLE COIL TIPS OVER ACROSS THE STROKE.** Comparable to the chain's own total, because it
/// is doing comparable work: the neck rears and the body arrives. Solved against the measured jaw height, not
/// picked — at 0 the lash finished at 2.04 m, a third of a metre over his crown.
const LASH_DIVE: f32 = 46.0;
/// The two follower rates — the second is slower, so the tip is always the last thing to know.
const LAG_1: f32 = 15.0;
const LAG_2: f32 = 9.0;
/// The idle S, in degrees. Small: a thing holding station in water moves, it does not dance.
const IDLE_SWAY: f32 = 3.2;
/// How wide the jaws open at the bottom of the stroke, and how far the barbels are held off the snout.
const GAPE: f32 = 38.0;
const BARB_SPLAY: f32 = 26.0;

/// THE WAKE. A rate rather than a count, because it runs the whole time the thing is down.
const WAKE_RATE: f32 = 16.0;
const WAKE_R: f32 = 0.85;
const WAKE_SPREAD: f32 = 0.55;
/// Where on the body's own axis the ripples are laid — at the SURFACE, which on a submerged creature is over
/// its head rather than at its feet.
const WAKE_Y: f32 = 0.06;
/// Thrown water, and it is the one pale thing this creature owns.
const SPRAY = rgba(150, 162, 152, 175);

const CAP_N = wf.MAX_PER_KIND;

/// THE MARSH — what a group of these is called, and what a line of them across a ford actually is.
/// `reset` and `draw` are ONE-LINE delegates to the shared pair; the `setFlash(0)` tail is what a
/// hand-rolled copy would forget.
pub const Marsh = struct {
    model: Model,
    eels: [CAP_N]Lurker = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Marsh {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Marsh) []Lurker {
        return self.eels[0..self.n];
    }
    pub fn liveConst(self: *const Marsh) []const Lurker {
        return self.eels[0..self.n];
    }
    pub fn reset(self: *Marsh, m: *const wf.Map) void {
        foe.resetGroup(Lurker, &self.eels, &self.n, m, .fen_lurker);
    }
    pub fn clear(self: *Marsh) void {
        self.n = 0;
    }
    pub fn setShader(self: *Marsh, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn update(self: *Marsh, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        // **THE WAKE IS TICKED FOR EVERY MEMBER, INCLUDING THE ONES DOING NOTHING** — it is the whole of what
        // a sunk lurker is, so it cannot live inside a state arm that only runs while something is happening.
        for (self.live()) |*l| {
            if (l.alive() and !l.dying() and l.hidden() and l.pooled()) l.ripple(dt);
        }
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Marsh, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Marsh) void {
        for (self.liveConst()) |*l| l.drawFx();
    }
    pub fn pierce(self: *Marsh, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Marsh) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Marsh) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Marsh) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Marsh) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

// ── THE MESHES ─────────────────────────────────────────────────────────────────────────────────────────
//
// **FLESH IS ROUND**: every mass here is `addBlob`/`addCapsule`. The only near-flat things are the fins,
// which are membrane rather than body.

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    const rest = restPose();
    for (0..N) |i| {
        var b = Builder.init();
        buildBone(&b, i, rest);
        mesh[i] = b.toMesh();
    }
    return mesh;
}

fn buildBone(b: *Builder, i: usize, rest: [N]rl.Vector3) void {
    var rng = mathx.Rng.init(0xFE41 + @as(u64, @intCast(i)));
    switch (i) {
        ROOT => {
            // THE COIL AT THE WATERLINE — the biggest mass on it, and most of it is under the sheet. Wide and
            // low, so what breaks the surface first is a back rather than a neck.
            b.addBlob(v3(0, 0.02 * H, -0.02 * H), v3(0.30 * H, 0.16 * H, 0.34 * H), 11, 7, HIDE);
            b.addBlob(v3(0, -0.05 * H, 0.06 * H), v3(0.24 * H, 0.11 * H, 0.26 * H), 9, 6, BELLY);
            // …and the humped back over it, off-centre. One asymmetry high up does more than ten round a rim.
            b.addBlob(v3(0.03 * H, 0.11 * H, -0.06 * H), v3(0.19 * H, 0.09 * H, 0.22 * H), 9, 6, HIDE_DK);
            // THE DORSAL RIDGE — a run of blunt humps down the back, no two alike. WABI-SABI between them.
            var k: u32 = 0;
            while (k < 5) : (k += 1) {
                const t = @as(f32, @floatFromInt(k)) / 4.0;
                b.addBlob(
                    v3(rng.range(-0.02, 0.02) * H, 0.14 * H - t * 0.03 * H, (-0.16 + t * 0.30) * H),
                    v3(0.030 * H * rng.range(0.7, 1.3), 0.038 * H * rng.range(0.8, 1.4), 0.048 * H),
                    6,
                    4,
                    HIDE_DK,
                );
            }
        },
        S0, S1, S2, S3, S4 => {
            // A NECK SEGMENT — a capsule up its own bone's run, tapering toward the head, with a paler throat
            // laid down its front. Taken off the REST OFFSET of the segment above so a lengthened rig grows.
            const above: usize = if (i == S4) HEAD else i + 1;
            // OFF THE DIFFERENCE, because the rest chain is ABSOLUTE (`restPose`) — the ravager's own idiom,
            // and the reason a resized rig cannot grow a mesh the solver does not believe in.
            const len = mathx.lenV(mathx.subV(rest[above], rest[i]));
            const t = @as(f32, @floatFromInt(i - S0)) / @as(f32, @floatFromInt(NECK.len - 1));
            // **A NECK, NOT A TENTACLE.** At 0.135·H the base was 0.69 m through on a creature whose skull is
            // 0.75 m wide — measured off the render it read as an arm rather than as something with a head on
            // it. Sized against the HEAD instead: a neck is visibly narrower than the thing it carries.
            const r0 = lerpF(0.082, 0.058, t) * H;
            const r1 = lerpF(0.074, 0.052, t) * H;
            b.addCapsule(v3(0, 0, 0), v3(0, len * 0.98, 0), r0, r1, 10, HIDE);
            b.addCapsule(v3(0, 0.02 * len, r0 * 0.42), v3(0, len * 0.92, r1 * 0.40), r0 * 0.44, r1 * 0.42, 8, BELLY);
            // A collar of skin folds where two segments meet — what stops a neck reading as one turned pipe.
            var k: u32 = 0;
            while (k < 4) : (k += 1) {
                const a = @as(f32, @floatFromInt(k)) / 4.0 * std.math.tau + rng.range(-0.2, 0.2);
                b.addBlob(
                    v3(mathx.cosf(a) * r0 * 0.92, len * 0.12, mathx.sinf(a) * r0 * 0.92),
                    v3(0.026 * H * rng.range(0.8, 1.3), 0.030 * H, 0.026 * H),
                    5,
                    4,
                    HIDE_LT,
                );
            }
        },
        HEAD => {
            // **BROAD AND FLAT**, which is the read: everything else with a head in this world has a skull,
            // and this one has a shovel. Wider than it is tall by a clear margin.
            b.addBlob(v3(0, 0.010 * H, 0.055 * H), v3(HEAD_R * H * 0.86, 0.062 * H, 0.155 * H), 11, 7, HIDE);
            b.addBlob(v3(0, -0.012 * H, 0.030 * H), v3(HEAD_R * H * 0.72, 0.042 * H, 0.120 * H), 9, 6, BELLY);
            // THE SNOUT, blunt — **nothing ends in a point**, a hunting head least of all.
            b.addBlob(v3(0, 0.004 * H, 0.150 * H), v3(0.082 * H, 0.046 * H, 0.058 * H), 8, 6, HIDE_LT);
            // **THE EYES, HIGH ON THE SKULL AND SET WIDE** — a thing that hunts lying just under a surface
            // keeps them where they clear it first. Emissive, and the only bright pair on the creature.
            //
            // **AND THEY HAVE TO SIT PROUD OF THE DOME, WHICH IS THE ONE PLACE THE RELIEF LAW DOES NOT
            // APPLY.** Sunk the few percent everything else here is sunk (y 0.048 against a crown at 0.072)
            // they were INSIDE the mass — measured off the render, what showed on the head was the two brow
            // ridges reading as dark slots and no lamps at all. A surface the sun lights may be flush; a
            // surface that lights ITSELF has to be visible or it is not a light.
            b.addBlob(v3(0.086 * H, 0.064 * H, 0.058 * H), v3(0.030 * H, 0.028 * H, 0.030 * H), 6, 5, EYE);
            b.addBlob(v3(-0.084 * H, 0.063 * H, 0.056 * H), v3(0.029 * H, 0.027 * H, 0.029 * H), 6, 5, EYE);
            // …and the brow ridges BEHIND and BESIDE them rather than over them, so the lamps sit in
            // something without being roofed by it.
            b.addBlob(v3(0.094 * H, 0.050 * H, 0.010 * H), v3(0.038 * H, 0.020 * H, 0.048 * H), 6, 4, HIDE_DK);
            b.addBlob(v3(-0.092 * H, 0.049 * H, 0.008 * H), v3(0.037 * H, 0.019 * H, 0.047 * H), 6, 4, HIDE_DK);
            // THE UPPER TEETH, uneven, none of them long: this thing crushes, it does not spear.
            var k: u32 = 0;
            while (k < 7) : (k += 1) {
                const x = (@as(f32, @floatFromInt(k)) - 3.0) * 0.026 * H;
                const l = 0.020 * H * rng.range(0.6, 1.35);
                b.addCapsule(
                    v3(x, -0.026 * H, 0.100 * H + rng.range(-0.010, 0.010) * H),
                    v3(x + rng.range(-0.004, 0.004) * H, -0.026 * H - l, 0.104 * H),
                    0.008 * H,
                    0.005 * H,
                    5,
                    TOOTH,
                );
            }
        },
        JAW => {
            // THE LOWER JAW — a slab, and the gullet behind it is what the gape actually shows.
            b.addBlob(v3(0, -0.014 * H, 0.070 * H), v3(0.098 * H, 0.030 * H, 0.130 * H), 9, 6, HIDE);
            b.addBlob(v3(0, 0.004 * H, 0.060 * H), v3(0.078 * H, 0.020 * H, 0.105 * H), 8, 5, GULLET);
            var k: u32 = 0;
            while (k < 6) : (k += 1) {
                const x = (@as(f32, @floatFromInt(k)) - 2.5) * 0.028 * H;
                const l = 0.017 * H * rng.range(0.6, 1.3);
                b.addCapsule(
                    v3(x, 0.010 * H, 0.098 * H),
                    v3(x + rng.range(-0.004, 0.004) * H, 0.010 * H + l, 0.102 * H),
                    0.007 * H,
                    0.005 * H,
                    5,
                    TOOTH,
                );
            }
        },
        BARBL, BARBR => {
            // A BARBEL — a limp feeler off the snout, and it DROOPS off its own line to a blunt end: nothing
            // dead is straight and nothing ends in a point (`propwood.deadLimbInto`'s law, on flesh).
            const side: f32 = if (i == BARBL) 1.0 else -1.0;
            var at = v3(0, 0, 0);
            var k: u32 = 0;
            while (k < 3) : (k += 1) {
                const l = 0.070 * H * rng.range(0.8, 1.2);
                const to = v3(
                    at.x + side * l * 0.30 * rng.range(0.6, 1.4),
                    at.y - l * (0.20 + 0.22 * @as(f32, @floatFromInt(k))),
                    at.z + l * 0.72,
                );
                b.addCapsule(at, to, 0.014 * H / (1.0 + 0.4 * @as(f32, @floatFromInt(k))), 0.011 * H / (1.0 + 0.5 * @as(f32, @floatFromInt(k))), 5, HIDE_LT);
                at = to;
            }
            b.addBlob(at, v3(0.013 * H, 0.011 * H, 0.013 * H), 5, 4, BELLY); // the blunt end
        },
        else => {},
    }
}

// ── TESTS ──────────────────────────────────────────────────────────────────────────────────────────────

test "IT IS A FOE, AND IT ANSWERS THE SHARED CONTRACT OFF ONE BODY" {
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(wf.FoeKind.fen_lurker, l.kind());
    try std.testing.expect(l.alive() and !l.dying() and !l.staggered());
    try std.testing.expect(!l.airborne());
    try std.testing.expect(l.hurtRadius() > l.bodyR());
    // A blow flinches it and a death ends it, through the shared reaction and nothing private.
    _ = l.vit.hit(.{ .dmg = 5, .poise = POISE_MAX + 1 });
    l.debugStagger(true);
    try std.testing.expect(l.staggered());
    l.vit.hp = 0;
    l.enterDeath();
    try std.testing.expect(l.dying() and l.justDied);
}

test "SUNK IT IS NOT THERE — no reticle, no bar, and a sword goes through the water" {
    const swing = foe.Blade{
        .active = true,
        .r = 0.4,
        .a = v3(0, 0.4, -2.0),
        .b = v3(0, 0.4, 2.0),
        .a0 = v3(0, 0.4, -2.0),
        .b0 = v3(0, 0.4, 2.0),
        .hit = .{ .dmg = 9, .poise = 3 },
    };
    var down = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(down.hidden()); // it comes up SUNK, which is the state it lives in
    down.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 0), down.hits); // …and nothing reached it
    try std.testing.expectApproxEqAbs(HP_MAX, down.vit.hp, 1e-4);

    // **AND UP IT IS AN ORDINARY BODY.** The whole creature is that one difference, so the same swing has to
    // land the moment the water has broken.
    var up = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    up.stageLash(0.5);
    try std.testing.expect(!up.hidden());
    up.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 1), up.hits);
    try std.testing.expect(up.vit.hp < HP_MAX);
}

test "A SUNK ONE IS NOT IN HIS WAY — no wall he cannot see, and it goes solid the moment it is up" {
    // **THE COLLISION SIDE OF THE SAME CLAIM `hidden` MAKES ABOUT THE SWORD**, and it is invisible when it is
    // wrong: `game.collideActors` pushes him out of every corporeal body whose CROWN clears his feet, and this
    // creature's crown is its full stature whether or not any of it is above the water. Left solid, wading
    // over one is walking into a wall in open water with nothing on screen to explain it.
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(l.hidden() and l.phased());
    // …AND THE CROWN STILL ANSWERS FULL HEIGHT while it is down, which is what makes the guard necessary
    // rather than incidental: the two facts have to be able to disagree.
    try std.testing.expect(l.topWorld().y - l.pos.y > H);

    // UP, it is an ordinary body again: solid, hittable, and in the way.
    l.stageGather(1.0);
    try std.testing.expect(!l.phased());
    try std.testing.expect(l.bodyR() > 0);
}

test "THE WATER IS THE TRIGGER, AND IT IS A FACT ABOUT THE GROUND HE IS ON" {
    const dt: f32 = 1.0 / 60.0;
    const near = mathx.ground(0, 3.0);
    // STANDING ON DRY LAND INSIDE ITS RING: it does not come up, however close he is.
    var dry = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    dry.wade = .{ .here = 1.0, .quarry = 0 };
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) _ = dry.update(dt, near, 200.0, .{});
    try std.testing.expect(dry.hidden());
    try std.testing.expectEqual(State.sunk, dry.state);

    // …AND ONE STEP INTO THE WATER BRINGS IT UP. Same distance, same everything, one number changed.
    var wet = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    wet.wade = .{ .here = 1.0, .quarry = WADE_MIN + 0.05 };
    wet.restT = 0;
    var broke = false;
    t = 0;
    while (t < 2.0) : (t += dt) {
        _ = wet.update(dt, near, 200.0, .{});
        if (wet.broke) broke = true;
    }
    try std.testing.expect(broke); // the water broke, and that edge is the voice's own
    try std.testing.expect(!wet.hidden());
}

test "THE SURGE IS A REAL TELL, and the wake leads the body out of the water" {
    // Over the floor every creature owes, and by a clear margin: what is being read is that the surface moved.
    try std.testing.expect(SURGE_DUR >= foe.TELL_MIN);
    try std.testing.expect(SURGE_DUR > LASH_DUR * 3.0);
    // …and the warning starts before anything breaks the surface at all.
    try std.testing.expect(WAKE_LEAD > 0 and WAKE_LEAD < SURGE_DUR);

    // THE BODY COMES UP ACROSS THE GATHER AND IS ALL THE WAY UP BEFORE THE STROKE — a creature still rising
    // as its head arrives is a tell you read at the same moment as the blow.
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.stageGather(0.0);
    try std.testing.expect(l.up < 0.05);
    l.stageGather(0.5);
    const half = l.up;
    try std.testing.expect(half > 0.1 and half < 0.95);
    l.stageGather(1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), l.up, 1e-5);
}

test "THE CROWN THE CAMERA FRAMES IS THE CROWN THE RIG ACTUALLY HAS" {
    // **`topWorld` IS A FORMULA AND THE RIG IS A CHAIN, AND NOTHING WAS CHECKING THEY AGREED.** Every framing
    // in the game is solved off `topWorld` (`shots.runMapShots`, the floating bar, a flyer's clearance), so a
    // `TOP_F` under the posed crown is a creature photographed with its head out of the top of the plate —
    // which is exactly what the first pass did.
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.stageGather(1.0);
    var crown: f32 = 0;
    for (0..N) |i| crown = @max(crown, foe.markOn(l.xf[i], mathx.zero3).y - l.pos.y);
    const said = l.topWorld().y - l.pos.y;
    std.debug.print("\n  fen lurker: posed crown {d:.2} m, topWorld says {d:.2} m\n", .{ crown, said });
    // The bar has to hang OVER it and a flyer has to clear it, so the formula may not come up short — and it
    // may not stand a mile over it either, or the creature is framed as a speck in the middle of the plate.
    try std.testing.expect(said >= crown);
    try std.testing.expect(said <= crown * 1.35);
    // **AND IT ANSWERS THE SAME WHILE THE THING IS DOWN**, because that is when the harness asks: every camera
    // in `shots.runMapShots` is solved before the pose is staged.
    var sunk = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(sunk.hidden());
    try std.testing.expectApproxEqAbs(said, sunk.topWorld().y - sunk.pos.y, 1e-5);
}

test "THE HEAD RIDES ABOVE HIM AND THE LASH BRINGS IT DOWN INTO HIS COLUMN" {
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.stageGather(1.0);
    const reared = l.jawPoint().y - l.pos.y;
    l.stageLash(1.0);
    const struck = l.jawPoint().y - l.pos.y;
    std.debug.print("\n  fen lurker: jaws {d:.2} m reared, {d:.2} m at the strike (hero {d:.2}..{d:.2}), chain bends {d:.0} deg\n", .{
        reared, struck, foe.HERO_LOW, foe.HERO_HIGH, TOTAL_BEND,
    });
    // IT STANDS OVER HIM before it comes — a thing that surfaced at his knees is a thing he walks past.
    try std.testing.expect(reared > foe.HERO_HIGH);
    // **AND THE STROKE LANDS WHOLLY INSIDE THE COLUMN HE STANDS IN** (`foe.HERO_LOW`..`HERO_HIGH`), the
    // head's own half-width included. Over his skull or into the water at his boots is a miss, and a creature
    // that reared and never came down would do the first of those every single time — which is exactly what
    // it did until the coil learned to dive with the neck (`LASH_DIVE`).
    try std.testing.expect(struck - HEAD_R > foe.HERO_LOW);
    try std.testing.expect(struck + HEAD_R < foe.HERO_HIGH);
    // …AND THE DIVE IS A DIVE. Most of the creature's own stature between the two, or the rear was not a rear.
    try std.testing.expect(reared - struck > H * 0.5);
}

test "ONE LASH IS ONE BLOW, and one that went past him does not take him in the back" {
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.state = .lash;
    l.t = 0;
    // BEHIND IT, well inside the reach: the distance says yes and the FRONT says no.
    l.tryLash(mathx.ground(0, -1.5));
    try std.testing.expect(l.heroHit == null);
    // …and out past the head in front of it, which the reach refuses.
    l.tryLash(mathx.ground(0, LASH_R + foe.HERO_REACH + 0.8));
    try std.testing.expect(l.heroHit == null);
    // Squarely in front and in reach, it lands — once.
    l.tryLash(mathx.ground(0, 1.4));
    try std.testing.expect(l.heroHit != null);
    l.heroHit = null;
    l.tryLash(mathx.ground(0, 1.4));
    try std.testing.expect(l.heroHit == null); // the latch: one stroke, one wound
}

test "IT HURTS HIM BY RETURNING A BLOW, and one surge lands exactly one" {
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 1.0, .quarry = 1.0 };
    l.restT = 0;
    const hero = mathx.ground(0, 1.4);
    const dt: f32 = 1.0 / 60.0;
    var landed: usize = 0;
    var t: f32 = 0;
    while (t < 3.0) : (t += dt) {
        if (l.update(dt, hero, 200.0, .{})) |h| {
            landed += 1;
            try std.testing.expectApproxEqAbs(LASH_HIT.dmg, h.dmg, 1e-4);
        }
        if (landed > 0 and l.state != .lash) break;
    }
    try std.testing.expectEqual(@as(usize, 1), landed);
}

test "HE LEAVES THE WATER AND IT GOES DOWN — and stepping back in brings it straight back up" {
    const dt: f32 = 1.0 / 60.0;
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 1.0, .quarry = 1.0 };
    l.restT = 0;
    const wet = mathx.ground(0, 3.0);
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) _ = l.update(dt, wet, 200.0, .{});
    try std.testing.expect(!l.hidden());

    // HE STEPS OUT: the depth under HIM goes to nothing, and the creature has no reason to be up.
    l.wade.quarry = 0;
    t = 0;
    while (t < 4.0) : (t += dt) _ = l.update(dt, wet, 200.0, .{});
    try std.testing.expect(l.hidden());
    try std.testing.expectEqual(State.sunk, l.state);

    // …AND BACK IN. It comes up again rather than making him wait out a timer he cannot see.
    l.wade.quarry = 1.0;
    l.restT = 0;
    t = 0;
    while (t < 2.0) : (t += dt) _ = l.update(dt, wet, 200.0, .{});
    try std.testing.expect(!l.hidden());
}

test "A STAGGER DOES NOT PUT IT UNDER — the flinch is the punish window, not its way out" {
    const dt: f32 = 1.0 / 60.0;
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 1.0, .quarry = 1.0 };
    l.stageLash(0.5);
    l.debugStagger(true);
    var t: f32 = 0;
    while (t < combat.FOE_HEAVY_STUN_DUR * 0.8) : (t += dt) _ = l.update(dt, mathx.ground(0, 2.0), 200.0, .{});
    try std.testing.expect(!l.hidden()); // still up, still hittable, all the way through it
    try std.testing.expectEqual(State.hurt, l.state);
}

test "WET FLESH IN STANDING WATER: lightning is the answer to it and fire is not" {
    var struck = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    var burnt = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    const levin = combat.Hit{ .elem = combat.elems(.{ .lightning = 20 }) };
    const fire = combat.Hit{ .elem = combat.elems(.{ .fire = 20 }) };
    try std.testing.expect(struck.vit.damageFrom(levin) > 20.0); // a negative resistance AMPLIFIES
    try std.testing.expect(burnt.vit.damageFrom(fire) < 20.0);
    // …AND IT IS THE FIRST BODY IN THE GAME THAT ESPECIALLY MINDS LIGHTNING, which is what the levin strike
    // and the thundercrock have been waiting for.
    try std.testing.expect(struck.vit.damageFrom(levin) > burnt.vit.damageFrom(fire) * 2.0);
}

test "A LIGHT POKE DOES NOT FLINCH IT AND A HEAVY DOES — poise against the hero's own two swings" {
    var light = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(combat.HitResult.none, light.vit.hit(heromod.ATK_LIGHT_HIT));
    var heavy = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(combat.HitResult.light, heavy.vit.hit(heromod.ATK_HEAVY_HIT));
}

test "A LURKER WITH NO POOL STANDS UP AND FIGHTS rather than sinking into a field" {
    const dt: f32 = 1.0 / 60.0;
    var l = Lurker.spawn(mathx.zero3, 0, 1.0, 0.3);
    l.wade = .{ .here = 0, .quarry = 0 }; // posted on dry ground by a careless map
    try std.testing.expect(!l.pooled());
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) _ = l.update(dt, mathx.ground(0, 3.0), 200.0, .{});
    // It answers to plain distance instead — the honest failure, and one a player can make sense of.
    try std.testing.expect(!l.hidden());
}

test "THE NECK IS A WHIP, NOT A HINGE — the tip carries more of the stroke than the root does" {
    try std.testing.expect(SEG_BEND_HI > SEG_BEND_LO * 2.0);
    try std.testing.expect(HEAD_BEND > SEG_BEND_HI);
    // …and the lag runs the right way: the second follower is slower, so the tip is last to know.
    try std.testing.expect(LAG_2 < LAG_1);
}
