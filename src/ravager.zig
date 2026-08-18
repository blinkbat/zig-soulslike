const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const heromod = @import("hero.zig");
const wolf = @import("wolf.zig");

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

// THE FLORID RAVAGER (owner's creature, owner's name) — a big hound with an open flower for a head.
//
// **IT IS THE QUADRUPED RIG'S SECOND USER, AND THAT IS THE WHOLE REASON IT COULD BE WRITTEN AT ALL.** The bone
// layout, the rest chain, Hildebrand's two gait dials, the limb solver and the leap all come out of `wolf.zig`
// (`wolf.restPose`, `wolf.legs`, `wolf.gaitAt`, `wolf.limbPhases`, `wolf.strideFor`, and the leap's own
// `wolf.BITE_HOP_UP`/`BITE_PITCH`). What is honestly its own is a STATURE and a HEAD — everything else here
// would have been a transcription, which the rig law forbids outright.
//
// **THE BLOOM IS THE TELL AND THE TELL IS THE WHOLE FIGHT.** Shut it is a knot on a neck and the animal is
// stalking; open it is a gaping ring of petals and the leap is already coming. One scalar (`open`) drives the
// petals, and it is read off the bite's own clock rather than kept as a second timer, so the picture cannot
// promise a lunge the mechanic is not throwing.

/// Height at the WITHERS. Over Hildebrand's 1.12 (owner: LARGE dogs) — it stands about as tall as the hero's
/// chest, which is what makes the head coming at you a head and not a knee.
pub const W: f32 = 1.34;

pub const AGGRO_R: f32 = 11.0;
/// …and how far from its post it will settle back to.
const HOME_R: f32 = 1.2;

const BODY_R: f32 = 0.46;
/// **THE HURT SPHERE HAS TO HOLD THE STALK AS WELL AS THE BODY.** Sized for a quadruped's ribcage it stopped
/// at 1.4 m and the whole neck and bloom — over a third of the creature, and the part the player is aiming at
/// — stood outside anything a sword could reach. Centre and radius are solved to span the barrel's own middle
/// (0.83 m) up to the bloom (2.17 m), which is what makes it one animal to hit rather than a dog with a
/// decoration floating over it.
const HURT_R: f32 = 0.92;
const CENTER_F: f32 = 1.05;
/// …and the CROWN is the bloom, not the withers. `topWorld` is what a bar is anchored over and what a flyer
/// clears; left at the back's own height both sat inside the creature.
const TOP_F: f32 = 1.66;

/// Sturdier than a sporeling and well under a skeleton warrior: it is a fast body that has to be answered, not
/// a wall. Poise sized so ONE hero heavy (22) flinches it and a light (10) does not — a hound you can stunlock
/// with a spam of R1 is not a hound.
const HP_MAX: f32 = 62.0;
const POISE_MAX: f32 = 18.0;
const STANCE_MAX: f32 = 40.0;
/// PLANT FLESH. Fire is what answers it and cold is what it does not care about — the sporeling's sheet, one
/// creature up in size, and the reason a fire arrow is worth spending on a pack of these.
const RESISTS = combat.resists(.{ .fire = -45, .cold = 30, .lightning = 0, .chaos = 20 });

const SOULS: u32 = 95;

const DEATH_DUR: f32 = 1.25;
const DISS_DUR: f32 = 1.05;
/// It sheds PETALS, not bone or chitin — the one line of the shared dissolve that is this creature's own.
const DISSOLVE = foe.Dissolve{ .rate = 58.0, .spread = 0.9, .rise = 0.85, .flake = PETAL_LT };

/// Sized off what feeds it: `DISSOLVE.rate` 58/s against a mean mote life of ~0.72 s stands about 42 at the
/// fade's start, and the bloom's own puff is at most 8 in a frame.
const PARTS = 56;

// THE BITE. It is the wolf's pounce with a bloom on the end of it, and the clocks are its own: heavier animal,
// longer gather, and a recovery you can actually punish.
const BITE_WIND: f32 = 0.38;
const BITE_STRIKE: f32 = 0.18;
const BITE_RECOVER: f32 = 0.46;
const BITE_COOL: f32 = 0.85;
/// Metres of forward travel across the wind and the strike — further than the wolf's 0.62, because this is a
/// bigger animal and the leap is the move.
const BITE_HOP: f32 = 0.86;
/// HOW FAR OUT THE BLOOM OPENS — ONE definition, the gate the whole behaviour turns on.
const BITE_R: f32 = 1.55;
const BITE_TRIGGER_R: f32 = BITE_R + BITE_HOP * 0.8;

/// **THE LEAP'S THREE INSTANTS, NAMED ONCE.** `LAUNCH_T` is the frame it leaves the earth, `HOP_END` the
/// frame it is back on it, and `APEX_T` the top of the arc between them. Written out as
/// `BITE_WIND + BITE_STRIKE` at six sites and `BITE_WIND * 0.55` at three, the pose, the mechanic, the
/// airborne gate and the staged photograph were four copies of one clock that had to agree by hand.
const LAUNCH_T: f32 = BITE_WIND * 0.55;
const HOP_END: f32 = BITE_WIND + BITE_STRIKE;
const APEX_T: f32 = (LAUNCH_T + HOP_END) * 0.5;

comptime {
    // **NO ATTACK COMES OUT OF NOWHERE** (`foe.TELL_MIN`), and this one is the slowest gather of any hound in
    // the game because the bloom opening IS the tell and it has to be readable across a field.
    std.debug.assert(BITE_WIND >= foe.TELL_MIN);
    // …and the opening is over well before the blow, or the tell arrives with the teeth.
    std.debug.assert(OPEN_BY < 1.0);
}

/// **THE GATE IS MEASURED FROM THE QUARRY'S HIDE** (`wolf.triggerR`'s law, and for its reason: asked
/// centre-to-centre a flat radius is unsatisfiable on anything broad, because `env.resolveActor` holds the
/// body `bodyR + its own` out and it circles a creature it can never trigger on).
pub fn triggerR(quarryR: f32) f32 {
    return BITE_TRIGGER_R + quarryR;
}
fn stopR(quarryR: f32) f32 {
    return BITE_R * 0.85 + quarryR;
}

/// WHAT THE JAWS DO. Heavier than the spirit's 21 and it carries real stance: this is a foe, and a pack of
/// them landing on you is meant to be the thing that breaks a guard.
const BITE_HIT = combat.Hit{ .dmg = 24, .poise = 20, .stance = 9 };

/// **HOW FAR THROUGH THE WIND THE BLOOM IS FULLY OPEN**, as a fraction of it. Well short of 1 so the gape is
/// finished and HELD before the animal leaves the ground — a flower still opening as the body arrives is a
/// tell you read at the same moment as the blow, which is not a tell.
const OPEN_BY: f32 = 0.62;
/// …and how long it takes to shut again once the strike is over, as a fraction of the recovery. Slower than it
/// opened: a mass in motion settles back onto its rest rather than snapping to it.
const SHUT_BY: f32 = 0.75;
/// **HOW WIDE THE ATTACK GOES, AS A MULTIPLE OF THE ALREADY-WIDE APPROACH GAPE.** Over 1 by a clear margin or
/// the second tier is not a tell — the player has to be able to see the difference between "it has noticed
/// you" and "it is coming", at the distance the leap is thrown from.
const ATTACK_OPEN: f32 = 1.62;
/// WHERE THE BLOOM STARTS TO WAKE and where it is at its full approach gape. The near end is the leap's own
/// trigger ring, so it is ALREADY at its widest on the frame the leap can be chosen: the attack tier then has
/// somewhere to go, and the opening is never news that arrives with the blow.
const NEAR_FAR: f32 = AGGRO_R * 0.8;
const NEAR_WIDE: f32 = BITE_TRIGGER_R + foe.HERO_R;
/// …and how fast it gets there. Slow enough to read as a thing unfurling rather than a shutter.
const NEAR_RATE: f32 = 2.4;

const TURN_RATE: f32 = 4.4; // rad/s — big and slower on its feet than the spirit's 5.6
const ACCEL: f32 = 7.5;
const GAIT_BLEND: f32 = 8.0;
/// It closes at a run and holds it — the thing you cannot simply walk away from.
const CHASE_SPEED: f32 = wolf.GALLOP_SPEED * 0.78;

pub const SHOVE = foe.Push{ .light = 1.20, .heavy = 2.90 };
const SHOVE_DECAY: f32 = 6.0;

/// How far down the jaw bone the bloom's throat sits, as a fraction of `W` — the point the mouth's height is
/// measured at, the wolf's `JAW_REACH` one creature along.
const JAW_REACH: f32 = 0.13;
/// …AND THE BLOOM'S OWN HALF-WIDTH, which is what its reach and its measured height are both taken over: a
/// ring of petals closing on you is a mouth the size of the head, not a set of teeth, so the mouth is a
/// radius and not a point.
const BLOOM_R: f32 = 0.30;
/// HOW FAR OFF ITS NOSE THE BLOOM STILL CATCHES HIM — the cosine of the frontal cone (the toad's own dial).
/// 0.25 is about 76 degrees either side, which is a ring of petals rather than a point.
const BITE_FRONT_DOT: f32 = 0.25;

// THE BONES ARE THE QUADRUPED RIG'S, WHOLE — indices, parents, count. Named locally so the pose below reads
// like the wolf's does, never re-declared.
const N = wolf.N;
const ROOT = wolf.ROOT;
const SPINE = wolf.SPINE;
const CHEST = wolf.CHEST;
const NECK = wolf.NECK;
const HEAD = wolf.HEAD;
const JAW = wolf.JAW;
const TAIL0 = wolf.TAIL0;
const TAIL1 = wolf.TAIL1;
const TAIL2 = wolf.TAIL2;
const EARL = wolf.EARL;
const EARR = wolf.EARR;

/// **THE PETALS RIDE THE EARS' AND THE JAW'S BONES**, which is why this creature needed no new joints: the rig
/// already carries two symmetrical things off the head and one hinge under it, and a bloom is exactly that —
/// a ring that opens. The outer petals are drawn onto `EARL`/`EARR`, the lower ones onto `JAW`, and the collar
/// onto `HEAD`. A bloom authored as eight new bones would have been eight bones for a mesh that turns as one.
const PETALS_PER_SIDE = 3;

// **THE NECK IS THE ONE THING IT DOES NOT TAKE FROM THE CANID** (owner: a long neck that is upright and can
// stretch a bit — a giraffe flower). `wolf.restPose` carries a wolf's: short, thick, and reaching FORWARD, so
// the skull sits at the withers and level with the back. That is a dog. A bloom on a stalk is the opposite
// shape — the neck goes UP out of the shoulders and the head is carried well above the line of the spine, and
// the silhouette from across a field is a body with a flower standing over it.

/// How high above the withers the bloom is carried, as a fraction of `W`. Over 1 by a clear margin: the head
/// has to break the line of the back or it is a dog with a big face.
const NECK_UP: f32 = 1.62;
/// …and how far FORWARD of the shoulder, which is small — an upright stalk leans, it does not reach.
const NECK_OUT: f32 = 0.30;
/// Where the neck's own midpoint sits, as a share of the way from the shoulder to the head. Under 0.5 puts the
/// bend low and the top run long, which is what a stalk looks like and a swan's neck does not.
const NECK_MID: f32 = 0.42;

/// **AND IT STRETCHES.** How much further the head reaches at full extension, as a fraction of the neck's own
/// length. A few tenths: the ask was "a bit", and a neck that doubles is a telescope. It rides the same clock
/// as the bloom's second tier, so the stretch and the wide gape are ONE movement — the thing rears up and
/// opens as it comes, which is the whole read.
const NECK_STRETCH: f32 = 0.26;

/// **AND THEN IT STRIKES DOWN, WHICH IS THE OTHER HALF OF HAVING A NECK LIKE THAT.** Degrees the whole head
/// chain pitches forward and under across the strike. It has to be big: reared and stretched the bloom rides
/// at 3.3 m, which is a metre and a half over the top of his head — a creature that leapt from there would
/// pass clean over him every time. The rear is the TELL and the dive is the BLOW, and both are the neck.
const STRIKE_DIVE: f32 = 152.0;
/// Where in the strike the dive is complete, as a fraction of it. Early: the bloom has to already be down at
/// his chest for most of the window it is allowed to bite in.
const DIVE_BY: f32 = 0.55;
/// …and how far the BODY tips over with it. Small against the neck's own 152: the stalk does the diving and
/// the body only follows, or the animal reads as falling on its face rather than striking.
const BODY_DIVE: f32 = 26.0;

/// THE REST CHAIN — the quadruped's body with this creature's own head on it. Both the mesh builder and the
/// spawn take it from here, so a neck moved is a neck moved in the picture too.
fn restPose() [N]rl.Vector3 {
    var r = wolf.restPose(W);
    const sh = r[CHEST];
    // The head, high and only just forward of the shoulder…
    r[HEAD] = v3(0, NECK_UP * W, sh.z + NECK_OUT * W);
    // …the neck's own joint on the way up to it, low so the long run is the top half.
    r[NECK] = v3(0, mathx.lerpF(sh.y, r[HEAD].y, NECK_MID), mathx.lerpF(sh.z, r[HEAD].z, NECK_MID * 0.6));
    // …and the bloom's parts carried with it, at the offsets off the head they always had.
    r[JAW] = v3(0, r[HEAD].y - 0.035 * W, r[HEAD].z + 0.073 * W);
    r[EARL] = v3(0.050 * W, r[HEAD].y + 0.075 * W, r[HEAD].z - 0.055 * W);
    r[EARR] = v3(-0.050 * W, r[HEAD].y + 0.075 * W, r[HEAD].z - 0.055 * W);
    return r;
}

// THE PALETTE. **AUTHOR DARK, AND SOLVE IT RATHER THAN GUESS** — the chain is albedo x 1.72 -> linear ->
// gamma 1/2.2, so screen goes as albedo^(1/2.2) and a factor you want on screen is that factor^2.2 on the
// albedo. MEASURED off the render: at (38, 34, 30) the hide came back at 144 against ground sampled at 112,
// i.e. the animal was BRIGHTER than the field it stands in. Wanted ~78, which is 0.54 on screen and
// 0.54^2.2 = 0.264 on the albedo — hence these. The bigger and smoother the mass, the darker it must start. The bloom is the one thing allowed to be bright, and it is bright because
// it is the read: a dark animal with a pale gaping ring where a face should be.
const HIDE = rgba(10, 9, 8, 206);
const HIDE_LT = rgba(15, 13, 11, 190);
const HIDE_DK = rgba(6, 6, 5, 210);
/// The petals' faces — a bruised violet-white, warm enough to sit in this world's light and pale enough to be
/// the brightest thing on the creature by a clear margin.
const PETAL = rgba(72, 60, 71, 214);
const PETAL_LT = rgba(88, 76, 85, 196);
/// …and their BACKS, which are what you see while it is shut. Nearly the hide: a closed bloom is a knot.
const PETAL_BACK = rgba(28, 22, 26, 208);
/// **THE THROAT, AND IT GLOWS — WHICH IS A NIGHT PROBLEM BEFORE IT IS A LOOK** (owner). Vertex alpha is the
/// emissive channel and LOWER is more self-lit, so this is authored far under everything else on the body:
/// after dark the hide is a black shape against black wood and the only thing that says a pack is coming is
/// the ring of gullets. It is the one part of the creature that may be BRIGHT — the author-dark rule is about
/// surfaces the sun lights, and this one lights itself.
///
/// Two shells: a hot core and a wider, dimmer halo over it, because a single blob at one value reads as a
/// painted dot and what is wanted is something with depth down it.
const THROAT = rgba(255, 122, 132, 26);
const THROAT_DEEP = rgba(196, 54, 72, 58); // …the mouth of it, redder and set further in
const THROAT_HALO = rgba(214, 96, 128, 104); // …and the light spilling onto the petals round it
/// The stamens catch that light and carry it out over the ring, which is what stops the glow being a hole.
const STAMEN = rgba(248, 226, 150, 62);
const CLAW = rgba(8, 7, 6, 214);

pub const State = enum { idle, move, bite, hurt, dead };

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("ravager material");
        mat.shader = shader;
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, r: *const Ravager) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, r.xf[i]);
    }
};

pub const Ravager = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    /// ITS EYES ON HIM (`foe.Leash`) — embedded by the creature, stamped by the game.
    leash: foe.Leash = .{},
    /// The wand's roots, and the rime's cold. Both stamped from outside and both billed through `foe.grip`.
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    /// WHO IT IS FIGHTING (`foe.Threat`), and THE WAY ROUND WHAT IS IN THE WAY (`foe.Nav`) — the same
    /// arrangement every creature on the field has.
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,
    state: State = .idle,
    t: f32 = 0,
    /// Gait phase, 0..1, advanced by DISTANCE and never by time — the hero's law, and why the paws do not skate.
    phase: f32 = 0,
    speed: f32 = 0,
    speedS: f32 = 0,
    biteCool: f32 = 0,
    /// **HOW AWAKE THE BLOOM IS**, 0..1, eased toward what the distance asks for (`NEAR_FAR`..`NEAR_WIDE`).
    /// A LEVEL and not an event: it has to be able to fall again when he backs off, and it may not step.
    nearK: f32 = 0,
    /// **HOW MUCH LEAP THE BITE IN FLIGHT IS THROWING**, latched at the commit — a body that walks away
    /// mid-leap does not shrink the leap already in the air. Always the full thing today (see the choose); it
    /// stays a dial because a second, shorter snap is the obvious next move to give this creature.
    pounce: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    /// **THE INCOMING LATCH, AND IT IS `foe.reached`'S** — one swing of HIS, one wound. Never touched here:
    /// cleared on the creature's own clock it would hand a single hero swing a second bite of the same body.
    hitLatch: bool = false,
    /// …AND THE OUTGOING ONE, WHICH IS A DIFFERENT FACT (the frog's `heroLatch`): one leap, one blow, however
    /// many frames the strike window is live for.
    heroLatch: bool = false,
    /// THIS FRAME'S BLOW ON WHOEVER IT IS FIGHTING, read straight back out of `update`. **A FOE HURTS THE HERO
    /// BY RETURNING A `Hit`**, never by carrying a `foe.Blade` — that type is the other direction entirely
    /// (what HIS sword sweeps against a body). Built the wrong way round the creature leapt all day and could
    /// not take a point off him, and the swept capsule it maintained per frame fed nothing at all.
    heroHit: ?combat.Hit = null,
    heavyStun: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    /// Its voices' one-frame edges, cleared with `justDied` at the top of `update`. The creature says WHEN;
    /// `game.zig` owns the speaker, or a creature would play through the pause card and the shot harness.
    opened: bool = false,
    /// …and the frame it LEAVES THE GROUND, which is a different beat from the bloom opening: the tell and
    /// the commit are two thirds of a second apart and the whole fight is learned in that gap.
    leapt: bool = false,
    snapped: bool = false,
    yelped: bool = false,

    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    rest: [N]rl.Vector3 = undefined,
    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Ravager {
        var r = Ravager{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale,
            .seed = seed,
            .rest = restPose(),
        };
        r.fxRng = foe.fxStream(seed, 51787.0, 0x1F10);
        r.pose();
        return r;
    }

    pub fn kind(_: *const Ravager) wf.FoeKind {
        return .florid_ravager;
    }

    pub fn centerWorld(self: *const Ravager) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * W, self.scale, 0);
    }
    /// THE MARK RIDES THE BLOOM — the part of it you are watching anyway.
    pub fn lockPoint(self: *const Ravager) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0.06 * W, 0.04 * W));
    }
    pub fn topWorld(self: *const Ravager) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * W, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Ravager) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Ravager) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Ravager) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Ravager) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Ravager) bool {
        return self.state == .hurt or self.state == .dead;
    }
    /// It leaves the earth on the leap, and `game.gateTerrain` reads this to leave a flying body alone.
    pub fn airborne(self: *const Ravager) bool {
        return self.state == .bite and self.leapLift() > foe.AIRBORNE_LIFT;
    }
    pub fn flashFrac(self: *const Ravager) f32 {
        return foe.flashFrac(self.flash);
    }

    /// WHERE THE BLOOM'S THROAT IS — one definition, because the spawn and the game's per-frame stamp both
    /// need it and as two copies the offset down the jaw was a literal that had to agree with itself.
    pub fn jawPoint(self: *const Ravager) rl.Vector3 {
        return foe.markOn(self.xf[JAW], v3(0, 0, JAW_REACH * W));
    }

    /// HOW OPEN THE BLOOM IS, 0..1 — **read off the bite's own clock and nowhere else**, so the picture and
    /// the mechanic cannot tell a different story about when the thing is coming. Shut in every other state.
    /// **THE BLOOM HAS TWO TIERS AND THE SECOND ONE IS THE TELL** (owner: open as he gets close, very wide;
    /// wider still when it attacks). 0 shut, 1 the wide-awake gape it wears the whole time he is near it, and
    /// past 1 up to `ATTACK_OPEN` for the leap. The two have to be a RANGE and not a switch: a flower that is
    /// already all the way out while it stalks has nothing left to say when the leap comes, and one that only
    /// opens on the attack is a dog with a knot on its neck until the frame it kills you.
    ///
    /// The approach tier is a SMOOTHED level (`nearK`) and the attack tier is the bite's own clock — so the
    /// first cannot pop as he crosses a threshold and the second cannot disagree with the mechanic.
    pub fn openAmt(self: *const Ravager) f32 {
        const near = self.nearK;
        if (self.state != .bite) return near;
        // …AND IT OPENS FROM WHEREVER IT ALREADY WAS. Driven from 0 the gape SNAPS shut on the frame the leap
        // is chosen and re-opens, which is the one frame the player is reading.
        const k: f32 = if (self.t < BITE_WIND)
            mathx.smoothstep(0, BITE_WIND * OPEN_BY, self.t)
        else if (self.t < HOP_END)
            1.0
        else
            1.0 - mathx.smoothstep(HOP_END, HOP_END + BITE_RECOVER * SHUT_BY, self.t);
        return mathx.lerpF(near, ATTACK_OPEN, k);
    }

    /// **HOW FAR THE NECK IS REACHING**, 0..1 — the bloom's own dial normalised, so the stalk rears as the
    /// flower opens and the two can never tell different stories. Past the approach gape it keeps going: the
    /// leap is the head arriving, and the neck going with it is most of what makes it arrive.
    pub fn stretchAmt(self: *const Ravager) f32 {
        return mathx.clampF(self.openAmt() / ATTACK_OPEN, 0, 1);
    }

    /// **HOW FAR INTO THE DIVE IT IS**, 0..1. Off the strike's own window, not the whole bite: the rear and
    /// the stretch own the gather, and this owns the frames the blow is live in.
    pub fn diveAmt(self: *const Ravager) f32 {
        if (self.state != .bite) return 0;
        if (self.t < BITE_WIND) return 0;
        if (self.t < HOP_END) return mathx.smoothstep(BITE_WIND, BITE_WIND + BITE_STRIKE * DIVE_BY, self.t);
        // …and it comes back UP across the recovery, which is the creature re-cocking itself.
        return 1.0 - mathx.smoothstep(HOP_END, HOP_END + BITE_RECOVER * SHUT_BY, self.t);
    }

    /// The leap's arc, 0 at the ground — shared by the pose and by `airborne`, so a body drawn in the air is
    /// a body the terrain gate agrees is in the air.
    fn leapLift(self: *const Ravager) f32 {
        if (self.state != .bite) return 0;
        if (self.t <= LAUNCH_T or self.t >= HOP_END) return 0;
        const u = (self.t - LAUNCH_T) / (HOP_END - LAUNCH_T);
        return wolf.BITE_HOP_UP * mathx.sinf(u * std.math.pi) * mathx.lerpF(wolf.HOP_FLOOR, 1.0, self.pounce) * W;
    }


    /// WHERE IT IS TRYING TO WALK (`game.markWay`) — **ONLY THE TRAVEL STATE.** A heading bent under a
    /// committed leap aims the blow at the wall.
    pub fn navWant(self: *const Ravager, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .move) return null;
        if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) return hero;
        return if (mathx.distXZ(self.pos, self.home) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Ravager, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    /// ONE FRAME. Returns the blow it landed on whoever it is fighting, or null.
    /// ONE FRAME. **`blade` IS HIS SWORD** and it is taken ONCE, at the bottom, after the pose — every live
    /// state has to be hittable, and the state machine below has an exit per state. Discarded in the signature
    /// the creature was simply invulnerable: `tryHit` never ran, and nothing anywhere else calls it.
    pub fn update(self: *Ravager, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        // **CLEARED BEFORE THE `gone` BRANCH, NOT AFTER IT** (the necromancer's law, and the mushroom mage's).
        // Reset inside `stateStep` these are reset only on the LIVE path, so a body that leaves the field
        // holding one holds it for good — and `game.zig` reads all five off `thicket.live()`, which still
        // carries the gone members, so a latched `snapped` is that voice every frame forever.
        self.justDied = false;
        self.heroHit = null;
        self.opened = false;
        self.leapt = false;
        self.snapped = false;
        self.yelped = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.stateStep(dt, hero, bounds);
        // AFTER THE POSE (`step` ends on one), so the swept test meets the body where it is drawn this frame
        // rather than where it stood last.
        self.tryHit(blade);
        return self.heroHit;
    }

    fn stateStep(self: *Ravager, dt: f32, hero: rl.Vector3, bounds: f32) void {
        // **DENYING MOVEMENT IS A POST-STEP GATE, NOT A GUARD AT EACH MOVER**, and a jump is the one thing it
        // refuses outright — gated at the CHOOSE below (`foe.canLeap`), because a leap does not travel.
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();

        self.t += dt;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        self.biteCool = mathx.maxF(0, self.biteCool - dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
        // **THE APPROACH GAPE, DRIVEN OFF THE PLAIN DISTANCE** — not off `senseHero`, which is blind while it
        // is walking home: a hound heading back to its post with the man beside it should still be gaping.
        // A dead one shuts, which is most of what says it is dead from across a field.
        const seeR = mathx.distXZ(self.pos, hero);
        const wantOpen: f32 = if (self.state == .dead) 0 else mathx.clampF((NEAR_FAR - seeR) / (NEAR_FAR - NEAR_WIDE), 0, 1);
        self.nearK = mathx.approach(self.nearK, wantOpen, NEAR_RATE * dt);

        if (self.state == .dead) {
            foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            self.speed = 0;
            self.settle(dt);
            return self.pose();
        }
        if (self.state == .hurt) {
            if (self.t >= combat.foeStunDur(self.heavyStun)) self.state = .idle;
            self.speed = 0;
            self.settle(dt);
            return self.pose();
        }
        if (self.state == .bite) {
            // **THE LINE IS COMMITTED AT THE LAUNCH** (the delver's law, the knight's charge's law): what you
            // dodge is the TRAVEL, so it aims through the GATHER — while the bloom is opening and telling you
            // it is coming — and steers not at all once it has left the ground. Tracked all the way in, the
            // leap is a homing missile and the tell the whole creature is built round buys the player nothing.
            if (self.t < BITE_WIND) self.faceToward(hero, dt);
            self.speed = 0;
            // THE LEAP CARRIES IT IN, through `stepXZ` like any other committed travel so the terrain gate
            // still gets the last word.
            // THE LAUNCH IS AN EDGE, caught by the clock CROSSING it — a long frame cannot fire it twice and
            // a short one cannot miss it (`hero.updateShot`'s rule).
            if (self.t - dt < LAUNCH_T and self.t >= LAUNCH_T) self.leapt = true;
            if (self.t < HOP_END) {
                mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), BITE_HOP * (dt / HOP_END), bounds);
            }
            // **THE IMPACT.** Anywhere inside the strike window, once: the bloom is a ring the size of the
            // head, so what it needs is a reach and a FRONT — a leap that went past him does not bite him in
            // the back of the neck on its way down.
            if (self.t >= BITE_WIND and self.t < HOP_END) self.tryBite(hero);
            if (self.t >= HOP_END + BITE_RECOVER) {
                self.state = .idle;
                self.t = 0;
                self.biteCool = BITE_COOL;
                self.heroLatch = false;
            }
            self.settle(dt);
            return self.pose();
        }

        const sensed = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        const hunting = sensed <= AGGRO_R;
        const want = if (hunting) hero else self.home;
        const gap = mathx.distXZ(self.pos, want);
        const stop: f32 = if (hunting) stopR(foe.HERO_R) else HOME_R;

        // **THE JUMP IS GATED WHERE THE MOVE IS CHOSEN** — the one place a post-step gate cannot reach. Held
        // by the ankles it may not leap, and denying only its distance leaves it hopping on the spot inside a
        // fist of roots.
        if (hunting and gap <= triggerR(foe.HERO_R) and self.biteCool <= 0 and foe.canLeap(&self.root)) {
            self.state = .bite;
            self.t = 0;
            self.heroLatch = false;
            self.speed = 0;
            // **THE FULL LEAP, ALWAYS.** `wolf.pounceFor` is Hildebrand's dial and it exists because a SPIRIT
            // bites whatever it is set on — a snag one fight and a giant the next. This one only ever comes
            // for the hero, and the leap is not a reach adjustment here: it IS the attack.
            self.pounce = 1.0;
            self.opened = true; // ON THE GATHER: the bloom is the tell, and it leads the blow
        } else if (gap > stop) {
            self.faceToward(self.nav.aim(self.pos, want), dt);
            const wantSpeed: f32 = if (hunting) CHASE_SPEED else wolf.TROT_SPEED;
            self.speed = mathx.approach(self.speed, wantSpeed, ACCEL * dt);
            const step = self.speed * dt * self.chill.travel();
            mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), step, bounds);
            self.phase = wolf.wrap01(self.phase + step / wolf.strideFor(self.speed));
            self.state = .move;
        } else {
            self.faceToward(want, dt);
            self.speed = mathx.approach(self.speed, 0, ACCEL * dt);
            self.state = .idle;
        }
        self.settle(dt);
        self.pose();
    }

    /// ONE LEAP, ONE BLOW. Reach off the bloom's own gape plus his hide (`foe.HERO_REACH`), and a FRONTAL
    /// cone: `foe.HERO_LOW`..`HERO_HIGH` is the column, and the bloom sweeps the whole of it across the
    /// strike (a test pins that), so height needs no second test here — only where he is standing.
    fn tryBite(self: *Ravager, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        const d = mathx.distXZ(self.pos, hero);
        if (d > BITE_R + foe.HERO_REACH) return;
        const to = mathx.dirXZ(self.pos, hero);
        const fwd = mathx.headingDir(self.facing);
        const front = to.x * fwd.x + to.z * fwd.z;
        if (d > 0.35 and front < BITE_FRONT_DOT) return;
        self.heroHit = BITE_HIT;
        self.heroLatch = true;
        self.snapped = true;
        self.leash.noteCombat(); // a blow landed is a fight in progress — the tether waits
    }

    fn settle(self: *Ravager, dt: f32) void {
        self.speedS = mathx.approach(self.speedS, self.speed, GAIT_BLEND * dt);
    }

    /// A BLOW LANDING ON IT. **TWO SHARED CALLS AND THEN WHAT IS MINE** — the swept test, the one-hit latch,
    /// the anti-cheese rouse and the facing snap; then the hit count, the flash and the shove.
    pub fn tryHit(self: *Ravager, blade_: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade_) orelse return;
        const heavy = foe.wounded(self, s, blade_, SHOVE);
        self.emitPetals(s.contact, if (heavy) 7 else 3);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    fn enterStun(self: *Ravager, heavy: bool) void {
        self.state = .hurt;
        self.t = 0;
        self.heavyStun = heavy;
        self.yelped = true;
    }

    fn enterDeath(self: *Ravager) void {
        if (self.state == .dead) return;
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    pub fn debugStagger(self: *Ravager, heavy: bool) void {
        self.enterStun(heavy);
    }

    /// Stage the bloom OPEN at the top of the leap, for the harness and for the measurement — a pose and
    /// nothing else: no blow, no travel, no cooldown spent (`wolf.stagePounce`'s pattern).
    pub fn stagePounce(self: *Ravager, amt: f32) void {
        self.state = .bite;
        self.pounce = mathx.clampF(amt, 0, 1);
        self.t = APEX_T;
        self.pose();
    }
    /// …and the GATHER, which is the frame the tell is judged on.
    pub fn stageGather(self: *Ravager, u: f32) void {
        self.state = .bite;
        self.t = mathx.clampF(u, 0, 1) * BITE_WIND;
        self.pose();
    }

    fn emitPetals(self: *Ravager, at: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.6, 1.7);
            foe.emitParticle(
                &self.parts,
                &self.fxHead,
                at,
                v3(mathx.cosf(a) * sp, self.fxRng.range(0.3, 1.6), mathx.sinf(a) * sp),
                self.fxRng.range(0.30, 0.62),
                self.fxRng.range(0.030, 0.058) * self.scale,
                0.006,
                if (self.fxRng.float() < 0.5) PETAL else PETAL_LT,
                2.2, // they FALL — a petal is not a spark
            );
        }
    }

    pub fn drawFx(self: *const Ravager) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Ravager, model: *const Model) void {
        if (self.gone) return;
        model.draw(self);
    }

    /// THE POSE. One world matrix per bone, once a frame — `draw` only replays them.
    pub fn pose(self: *Ravager) void {
        const g = wolf.gaitAt(self.speedS);
        const stride = wolf.strideFor(self.speedS);
        const ph = wolf.limbPhases(self.phase, g);
        const m = mathx.clampF(self.speedS / wolf.WALK_SPEED, 0, 1);
        const s = self.scale;
        const breath = mathx.sinf(self.t * 1.7) * 0.007 * W;
        const react: f32 = if (self.state == .hurt) foe.stunCurve(self.t, self.heavyStun) else 0;
        const fall: f32 = if (self.state == .dead) mathx.clampF(self.t / (DEATH_DUR * 0.7), 0, 1) else 0;

        // THE LEAP: it sinks through the gather, leaves the ground across the strike, and pitches NOSE-UP the
        // whole way — the spirit's own arc (`wolf.BITE_PITCH`), and the reason the bloom arrives at a chest
        // rather than at a shin. One curve drives lift and pitch together.
        const lift = self.leapLift();
        const arcN = if (wolf.BITE_HOP_UP * W > 1e-5) lift / (wolf.BITE_HOP_UP * W) else 0;
        // **NOSE UP TO REAR, NOSE DOWN TO STRIKE.** The wolf's arc is nose-up the whole way because its mouth
        // is at the front of it; this one's is at the top of a stalk, so keeping the body tipped back through
        // the blow holds the bloom above his head at the exact moment it is supposed to be in his chest.
        const pitch = wolf.BITE_PITCH * arcN - BODY_DIVE * self.diveAmt();
        var crouch: f32 = 0;
        if (self.state == .bite) {
            crouch = CROUCH * mathx.smoothstep(0, BITE_WIND * 0.8, self.t) * (1.0 - mathx.smoothstep(BITE_WIND, HOP_END, self.t));
        }

        var wx: [N]rl.Matrix = undefined;
        // **THE WHOLE RIG TAKES THE MAP'S SCALE, NOT JUST THE PELVIS HEIGHT.** `centerWorld`, `topWorld`,
        // `hurtRadius` and `bodyR` are every one of them `self.scale`'d, so a rig drawn at 1 hangs a bigger
        // hurt sphere, mark and bar round a body that never grew. Innermost, so every child bone inherits it
        // through the parent chain, and every vertical offset goes through it as well — at scale 1 this is
        // exactly the expression it always was.
        wx[ROOT] = mul3(
            mul(scaleM(s, s, s), mul(rx(-pitch), rz(-70.0 * mathx.smoothstep(0, 1, fall)))),
            mul(tr(0, (self.rest[ROOT].y + breath + lift - crouch * W - 0.10 * W * fall) * s, 0), ry(mathx.degrees(self.facing))),
            heromod.rootAt(self.pos),
        );
        // The spine bows once a stride — a bounding canid's back is half its stride.
        const flex = mathx.sinf(self.phase * std.math.tau) * m * (4.0 + 9.0 * mathx.clampF((self.speedS - wolf.TROT_SPEED) / (wolf.GALLOP_SPEED - wolf.TROT_SPEED), 0, 1));
        const duck: f32 = 8.0 * react;
        heromod.setJoint(&wx, &self.rest, SPINE, ROOT, rx(-flex * 0.5 - duck * 0.3));
        heromod.setJoint(&wx, &self.rest, CHEST, SPINE, rx(-flex * 0.5 - duck * 0.3));
        // THE NECK, and it is UPRIGHT: the canid's forward reach is gone, so what the gait does to it is a
        // sway rather than a nod. It still ducks hard on a reaction — a stalk hit in the middle folds.
        // …AND IT DIVES ON THE STRIKE. Negative about X at the neck brings the head DOWN and forward (the
        // root's own sign, one joint along), which is what puts a bloom carried at 2.2 m into a man's chest.
        heromod.setJoint(&wx, &self.rest, NECK, CHEST, rx(flex * 0.5 + 3.0 * m - duck * 1.4 - STRIKE_DIVE * self.diveAmt()));
        // **AND THE HEAD STRETCHES UP THE NECK'S OWN AXIS**, not along the world's: `setJoint` takes the bone's
        // length from the DISTANCE between two rest points, so the reach is added as a translate on top of it
        // and the mesh, the bloom and everything measured off `jawPoint` all come with it for free.
        const reach = NECK_STRETCH * W * self.stretchAmt();
        const neckOff = mathx.subV(self.rest[HEAD], self.rest[NECK]);
        const up = if (mathx.lenV(neckOff) > 1e-5) mathx.normV(neckOff) else v3(0, 1, 0);
        wx[HEAD] = mul(
            mul(rx(flex * 0.25 - 3.0 * m - duck * 0.6), tr(neckOff.x + up.x * reach, neckOff.y + up.y * reach, neckOff.z + up.z * reach)),
            wx[NECK],
        );
        // **THE BLOOM.** `JAW` carries the lower half of the ring and the ears the outer petals, so one scalar
        // opens all of it — and the same scalar the mechanic's clock produced.
        const open = self.openAmt();
        heromod.setJoint(&wx, &self.rest, JAW, HEAD, rx(PETAL_GAPE * open));
        // The outer petals sweep BACK and OUT as it opens. `rz` splays them off the head's axis and `rx` lays
        // them back — a flower opens by folding away from its own throat, not by hinging like a mouth.
        const splay = PETAL_SPLAY * open;
        const layback = PETAL_BACK_ANG * open - 52.0 * react; // …and they clamp shut on a reaction
        heromod.setJoint(&wx, &self.rest, EARL, HEAD, mul(rx(layback), rz(-splay - 8.0)));
        heromod.setJoint(&wx, &self.rest, EARR, HEAD, mul(rx(layback), rz(splay + 8.0)));
        // The tail is a stiff rope of stem, not a brush: it swings against the gait and drops when hurt.
        const tailSwing = mathx.sinf(self.phase * std.math.tau + 1.1) * 6.0 * m;
        heromod.setJoint(&wx, &self.rest, TAIL0, ROOT, mul(rx(-10.0 * m + 24.0 * react), ry(tailSwing)));
        heromod.setJoint(&wx, &self.rest, TAIL1, TAIL0, mul(rx(6.0 + 10.0 * react), ry(tailSwing * 0.7)));
        heromod.setJoint(&wx, &self.rest, TAIL2, TAIL1, mul(rx(9.0 + 8.0 * react), ry(tailSwing * 0.5)));
        // …AND ALL FOUR LEGS THROUGH THE SHARED SOLVER. `tuck` folds the paws up under a body in the air.
        const tuck = lift / @max(0.72 * W, 0.001);
        wolf.legs(&wx, &self.rest, W, ph, g, stride, m, crouch, tuck);
        self.xf = wx;
    }
};

/// How far the whole animal sinks through the gather, as a fraction of `W` — deeper than the spirit's 0.09
/// because it is a bigger body loading a longer leap, and the sink IS the wind-up you read the leap off.
const CROUCH: f32 = 0.13;
// **THE BLOOM'S THREE ANGLES, AND THEY ARE HUGE** (owner: it needs to open up huge and dramatic). At 46/38
// the flower PARTED; what is wanted is a thing that turns itself nearly inside out — petals thrown right back
// past the plane of the throat, so at full attack the head is a ring of tissue with a lit gullet in the
// middle of it and no silhouette left of the knot it was a second ago. The APPROACH tier is a share of these
// (`nearK`), so "very wide" and "wider still" are the same three dials read at two levels rather than two
// sets of numbers that can drift apart.
/// The LOWER half swings down and under…
const PETAL_GAPE: f32 = 74.0;
/// …the outer petals splay off the head's axis…
const PETAL_SPLAY: f32 = 62.0;
/// …and lay back PAST the throat's own plane, which is what "inside out" means and what a jaw can never do.
/// **NOT A MOUTH**: a jaw hinges at one point and a flower opens all round, so the outer pair have to leave on
/// both axes or the head reads as a beak.
const PETAL_BACK_ANG: f32 = -58.0;

const CAP_N = wf.MAX_PER_KIND;

/// THE PACK — a THICKET of them. Named for what it is rather than borrowed: `Grove` is the rooted's
/// group and a second one of that name is a collision that ends up worked around at the field.
/// Its `reset` and `draw` are ONE-LINE delegates to the shared pair — the `setFlash(0)` tail is what
/// a fourth hand-rolled copy would forget.
pub const Thicket = struct {
    model: Model,
    dogs: [CAP_N]Ravager = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Thicket {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Thicket) []Ravager {
        return self.dogs[0..self.n];
    }
    pub fn liveConst(self: *const Thicket) []const Ravager {
        return self.dogs[0..self.n];
    }
    pub fn reset(self: *Thicket, m: *const wf.Map) void {
        foe.resetGroup(Ravager, &self.dogs, &self.n, m, .florid_ravager);
    }
    pub fn clear(self: *Thicket) void {
        self.n = 0;
    }
    pub fn setShader(self: *Thicket, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn update(self: *Thicket, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Thicket, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Thicket) void {
        for (self.liveConst()) |*r| r.drawFx();
    }
    pub fn pierce(self: *Thicket, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Thicket) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Thicket) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Thicket) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Thicket) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

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

/// ONE BONE'S MESH, in that bone's own frame. **FLESH IS ROUND** — every mass here is `addBlob`/`addCapsule`;
/// the only flat things are the petals, which are cloth-thin by nature.
fn buildBone(b: *Builder, i: usize, rest: [N]rl.Vector3) void {
    var rng = mathx.Rng.init(0xF10D + @as(u64, @intCast(i)));
    switch (i) {
        ROOT => {
            // The haunches — the biggest single mass on the animal, and it carries the hind legs.
            b.addBlob(v3(0, 0, -0.04 * W), v3(0.21 * W, 0.23 * W, 0.26 * W), 10, 7, HIDE);
            b.addBlob(v3(0.12 * W, 0.02 * W, 0.02 * W), v3(0.10 * W, 0.15 * W, 0.16 * W), 8, 6, HIDE_LT);
            b.addBlob(v3(-0.12 * W, 0.02 * W, 0.02 * W), v3(0.10 * W, 0.15 * W, 0.16 * W), 8, 6, HIDE_LT);
        },
        SPINE => {
            const off = mathx.subV(rest[CHEST], rest[SPINE]);
            const len = mathx.lenV(off);
            b.addCapsule(v3(0, 0, 0), off, 0.19 * W, 0.19 * W, 10, HIDE);
            // The saddle — a darker ridge over the loin, and it is what breaks up the barrel.
            b.addBlob(v3(0, 0.15 * W, len * 0.5), v3(0.12 * W, 0.05 * W, len * 0.44), 8, 5, HIDE_DK);
        },
        CHEST => {
            b.addBlob(v3(0, 0.01 * W, 0.05 * W), v3(0.23 * W, 0.25 * W, 0.24 * W), 11, 8, HIDE);
            b.addBlob(v3(0, -0.13 * W, 0.06 * W), v3(0.18 * W, 0.13 * W, 0.20 * W), 9, 6, HIDE_LT);
        },
        NECK => {
            // **A BONE'S MESH RUNS ALONG THAT BONE, AND ON THIS RIG THAT IS NOT +Z.** `setJoint` only
            // translates and rotates — it does not orient the child frame — so a mesh authored down +Z is
            // right only for a creature whose next joint is straight ahead of this one. A wolf's head is; a
            // stalk's is straight UP, and built the wolf's way the neck lay out horizontally while the bloom
            // sat two metres over it with nothing joining them. Taken off the offset itself, the same code is
            // correct for both.
            const off = mathx.subV(rest[HEAD], rest[NECK]);
            const len = mathx.lenV(off);
            const dir = if (len > 1e-5) mathx.scaleV(off, 1.0 / len) else v3(0, 1, 0);
            b.addCapsule(v3(0, 0, 0), mathx.scaleV(dir, len * 0.96), 0.135 * W, 0.115 * W, 10, HIDE);
            // A COLLAR OF SEPALS where the neck meets the bloom — green-dark, and it is what stops the flower
            // reading as a mask stuck on a dog.
            var k: u32 = 0;
            while (k < 5) : (k += 1) {
                const a = @as(f32, @floatFromInt(k)) / 5.0 * std.math.tau + rng.range(-0.15, 0.15);
                const rr = 0.13 * W;
                // …AND THE COLLAR SITS AT THE TOP OF THAT SAME RUN, laid round it rather than round +Z.
                const up = mathx.scaleV(dir, len * 0.86);
                b.addBlob(
                    v3(up.x + mathx.cosf(a) * rr, up.y + mathx.sinf(a) * rr * 0.8, up.z),
                    v3(0.045 * W * rng.range(0.8, 1.25), 0.045 * W, 0.075 * W * rng.range(0.85, 1.2)),
                    6,
                    4,
                    PETAL_BACK,
                );
            }
        },
        HEAD => {
            // THE RECEPTACLE — the knot the bloom opens out of. Round, dark, and small: the petals are the
            // silhouette, so a big skull under them would fight the read.
            b.addBlob(v3(0, 0, 0.02 * W), v3(0.115 * W, 0.115 * W, 0.13 * W), 9, 7, PETAL_BACK);
            // THE THROAT, emissive, sunk most of the way in — relief is a few percent (`AGENTS.md`), and what
            // is wanted here is a glow out of a hollow rather than a proud ball. THREE SHELLS, deep to hot:
            // the deep one is the hole, the halo washes the petal bases so the light looks like it is coming
            // OUT of something, and the core is the only truly bright thing on the animal.
            b.addBlob(v3(0, 0, 0.055 * W), v3(0.105 * W, 0.105 * W, 0.045 * W), 9, 7, THROAT_HALO);
            b.addBlob(v3(0, 0, 0.085 * W), v3(0.078 * W, 0.078 * W, 0.050 * W), 8, 6, THROAT_DEEP);
            b.addBlob(v3(0, 0, 0.108 * W), v3(0.050 * W, 0.050 * W, 0.040 * W), 8, 6, THROAT);
            // The stamens, uneven, off a seeded Rng — WABI-SABI, and none of them ends in a point.
            var k: u32 = 0;
            while (k < 6) : (k += 1) {
                const a = @as(f32, @floatFromInt(k)) / 6.0 * std.math.tau + rng.range(-0.25, 0.25);
                const rr = 0.040 * W * rng.range(0.7, 1.3);
                const len = 0.075 * W * rng.range(0.75, 1.3);
                b.addCapsule(
                    v3(mathx.cosf(a) * rr, mathx.sinf(a) * rr, 0.10 * W),
                    v3(mathx.cosf(a) * rr * 1.5, mathx.sinf(a) * rr * 1.5, 0.10 * W + len),
                    0.011 * W,
                    0.013 * W,
                    5,
                    STAMEN,
                );
            }
            // THE UPPER PETALS — three a side, on the head itself, laid round the top of the ring.
            petalFan(b, &rng, 1.0, PETALS_PER_SIDE);
            petalFan(b, &rng, -1.0, PETALS_PER_SIDE);
        },
        JAW => {
            // THE LOWER HALF OF THE RING, which is the half that swings. Same petals, hung the other way up.
            petalFan(b, &rng, 1.0, 2);
            petalFan(b, &rng, -1.0, 2);
        },
        EARL, EARR => {
            // THE OUTER PAIR — the longest petals, and the ones whose splay is the tell at distance.
            const side: f32 = if (i == EARL) 1.0 else -1.0;
            petal(b, &rng, v3(0, 0, 0), side, 0.30 * W, 1.35);
        },
        TAIL0, TAIL1, TAIL2 => {
            const len: f32 = switch (i) {
                TAIL0 => mathx.lenV(mathx.subV(rest[TAIL0], rest[TAIL1])),
                TAIL1 => mathx.lenV(mathx.subV(rest[TAIL1], rest[TAIL2])),
                else => 0.16 * W,
            };
            const r0: f32 = 0.045 * W * (if (i == TAIL0) @as(f32, 1.0) else if (i == TAIL1) @as(f32, 0.8) else @as(f32, 0.62));
            b.addCapsule(v3(0, 0, 0), v3(0, -len * 0.35, -len * 0.9), r0, r0, 7, HIDE_DK);
        },
        else => buildLimbBone(b, i, rest, &rng),
    }
}

/// ONE PETAL — a blunt, slightly cupped blade of tissue. **NOTHING ENDS IN A POINT**: the tip is a capped
/// blob, so a rosette of these is a flower and not a hub of spokes.
fn petal(b: *Builder, rng: *mathx.Rng, at: rl.Vector3, side: f32, len: f32, wide: f32) void {
    const l = len * rng.range(0.84, 1.16); // uneven BETWEEN petals, which is where the variation reads
    const w = 0.075 * W * wide * rng.range(0.85, 1.15);
    const tipZ = at.z + l;
    // The blade: a flattened blob, cupped by sitting a paler one just proud of the inner face.
    b.addBlob(v3(at.x + side * w * 0.35, at.y, at.z + l * 0.5), v3(w, 0.016 * W, l * 0.52), 7, 4, PETAL_BACK);
    b.addBlob(v3(at.x + side * w * 0.35, at.y + 0.010 * W, at.z + l * 0.52), v3(w * 0.86, 0.012 * W, l * 0.46), 7, 4, PETAL);
    // …and the TIP, blunt and turned a little out of the blade's own line — nothing dead is straight.
    b.addBlob(v3(at.x + side * w * 0.5 + rng.range(-0.012, 0.012) * W, at.y + rng.range(-0.01, 0.01) * W, tipZ), v3(w * 0.55, 0.014 * W, 0.030 * W), 6, 4, PETAL_LT);
}

/// A FAN OF THEM off one bone, swept round the throat.
fn petalFan(b: *Builder, rng: *mathx.Rng, side: f32, n: u32) void {
    var k: u32 = 0;
    while (k < n) : (k += 1) {
        const t = (@as(f32, @floatFromInt(k)) + 0.5) / @as(f32, @floatFromInt(n));
        const a = side * (0.35 + t * 1.05) + rng.range(-0.10, 0.10);
        const rr = 0.085 * W;
        petal(
            b,
            rng,
            v3(mathx.cosf(a) * rr * side, mathx.sinf(a) * rr, 0.045 * W),
            side,
            0.20 * W,
            1.0,
        );
    }
}

/// THE LEGS, off the rest chain's own segment lengths so a resized animal cannot grow a leg the solver does
/// not believe in.
fn buildLimbBone(b: *Builder, i: usize, rest: [N]rl.Vector3, rng: *mathx.Rng) void {
    const child: ?usize = blk: {
        for (0..N) |c| {
            if (wolf.PARENT[c] == @as(i32, @intCast(i))) break :blk c;
        }
        break :blk null;
    };
    const len: f32 = if (child) |c| mathx.lenV(mathx.subV(rest[i], rest[c])) else 0.10 * W;
    const paw = child == null;
    if (paw) {
        // A PAW IS A PAD AND FOUR BLUNT CLAWS. Capped, because a cylinder is capless and an open end shows
        // its culled interior.
        b.addBlob(v3(0, -0.018 * W, 0.028 * W), v3(0.062 * W, 0.032 * W, 0.078 * W), 8, 5, HIDE_DK);
        var k: u32 = 0;
        while (k < 4) : (k += 1) {
            const x = (@as(f32, @floatFromInt(k)) - 1.5) * 0.030 * W;
            b.addCapsule(
                v3(x, -0.026 * W, 0.070 * W),
                v3(x + rng.range(-0.004, 0.004) * W, -0.030 * W, 0.098 * W),
                0.013 * W,
                0.008 * W,
                5,
                CLAW,
            );
        }
        return;
    }
    // Upper segments are thicker than lower ones — the taper is most of what says "leg".
    const upper = i == wolf.SHL or i == wolf.SHR or i == wolf.HIPL or i == wolf.HIPR;
    const r0: f32 = if (upper) 0.072 * W else 0.048 * W;
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), r0, r0, 8, if (upper) HIDE else HIDE_DK);
}

test "THE BLOOM IS THE TELL: shut while it stalks, fully open BEFORE the blow, and shut again after" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.openAmt(), 1e-6); // nothing near it: a knot on a neck

    // …and the gather opens it. **FULLY open before the strike begins**, or the tell arrives with the teeth.
    r.state = .bite;
    r.t = BITE_WIND * OPEN_BY;
    try std.testing.expectApproxEqAbs(ATTACK_OPEN, r.openAmt(), 1e-3);
    r.t = BITE_WIND;
    try std.testing.expectApproxEqAbs(ATTACK_OPEN, r.openAmt(), 1e-6);
    r.t = BITE_WIND + BITE_STRIKE * 0.5;
    try std.testing.expectApproxEqAbs(ATTACK_OPEN, r.openAmt(), 1e-6);

    // …and it shuts across the recovery rather than snapping — a mass settles back onto its rest. Back down
    // to whatever the APPROACH tier is asking for, which with nobody near it is shut.
    r.t = BITE_WIND + BITE_STRIKE + BITE_RECOVER * SHUT_BY * 0.5;
    const half = r.openAmt();
    try std.testing.expect(half > 0.05 and half < ATTACK_OPEN * 0.95);
    r.t = BITE_WIND + BITE_STRIKE + BITE_RECOVER;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.openAmt(), 1e-6);

    // THE GATHER IS A REAL TELL — over the floor every creature owes (`foe.TELL_MIN`), and longer than the
    // spirit's, because a flower opening has to be legible from across a field.
    try std.testing.expect(BITE_WIND >= foe.TELL_MIN);
    try std.testing.expect(BITE_WIND * OPEN_BY >= foe.TELL_MIN * 0.6);
}

test "THE GATHER THREATENS AND THE STRIKE CUTS — the blow lands inside that window and nowhere else" {
    const hero = mathx.ground(0, 1.2); // squarely in front, well inside the bloom's reach
    // THROUGH THE GATHER: the bloom is opening and it has not bitten anybody yet.
    const dt: f32 = 1.0 / 60.0;
    // …staged one step SHORT of each instant, because `update` advances its own clock before it tests.
    for ([_]f32{ 0, BITE_WIND * 0.5, BITE_WIND - 2 * dt }) |at| {
        var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
        r.state = .bite;
        r.t = at - dt;
        _ = r.update(dt, hero, 200.0, .{});
        try std.testing.expect(r.heroHit == null);
    }
    // INSIDE THE STRIKE it lands…
    var hit = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    hit.state = .bite;
    hit.t = BITE_WIND;
    try std.testing.expect(hit.update(dt, hero, 200.0, .{}) != null);
    // …and through the RECOVERY it is over: a body still lying in the crater is not still being bitten.
    var done = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    done.state = .bite;
    done.t = BITE_WIND + BITE_STRIKE;
    try std.testing.expect(done.update(dt, hero, 200.0, .{}) == null);
}

test "IT LEAVES THE EARTH, and the body drawn in the air is the body the terrain gate agrees is airborne" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(!r.airborne());
    r.stagePounce(1.0);
    try std.testing.expect(r.leapLift() > foe.AIRBORNE_LIFT);
    try std.testing.expect(r.airborne()); // the one reads the other, so they cannot disagree
    // …and it is back down by the end of the strike.
    r.t = BITE_WIND + BITE_STRIKE;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.leapLift(), 1e-6);
    try std.testing.expect(!r.airborne());
}

test "THE BLOOM RAKES DOWN THROUGH HIM — it rears above his head and the DIVE brings it into his column" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.pose();
    const rest = r.jawPoint().y - r.pos.y + BLOOM_R;
    // REARED: at the top of the gather the bloom is over his crown, which is the whole silhouette of the tell.
    r.state = .bite;
    r.t = BITE_WIND - 1e-4;
    r.pounce = 1.0;
    r.pose();
    const reared = r.jawPoint().y - r.pos.y;
    // …AND DIVED: by the time the blow is live it is down in him.
    r.t = BITE_WIND + BITE_STRIKE * DIVE_BY;
    r.pose();
    const struck = r.jawPoint().y - r.pos.y;
    std.debug.print("\n  ravager bloom: {d:.2} m standing, {d:.2} m reared, {d:.2} m at the strike (hero {d:.2}..{d:.2})\n", .{
        rest, reared, struck, foe.HERO_LOW, foe.HERO_HIGH,
    });
    try std.testing.expect(reared > foe.HERO_HIGH); // it stands over him before it comes
    // **AND THE STRIKE LANDS IN THE COLUMN HE STANDS IN** (`foe.HERO_LOW`..`HERO_HIGH`). Over his skull or
    // into the dirt at his boots is a miss, and a creature that reared and never came down would do the first
    // of those every single time.
    try std.testing.expect(struck + BLOOM_R > foe.HERO_LOW);
    try std.testing.expect(struck - BLOOM_R < foe.HERO_HIGH);
    try std.testing.expect(struck < reared - 0.6); // the dive is a DIVE
}

test "IT IS A FOE, NOT A SPIRIT — its own tether, its own souls, and it answers for its own kind" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(wf.FoeKind.florid_ravager, r.kind());
    try std.testing.expect(r.alive() and !r.dying() and !r.staggered());
    // The contract's accessors all answer off ONE body, so a bar anchored on one and a reticle on another
    // cannot drift: the hurt sphere has to contain the mark.
    try std.testing.expect(r.hurtRadius() > r.bodyR());
    try std.testing.expect(r.topWorld().y > r.centerWorld().y);
    // The MARK rides the bloom, which on a quadruped is out at the end of a neck rather than over the body's
    // own centre — so it is allowed to sit outside the hurt sphere, but not by more than the body is long.
    const markOut = mathx.lenV(mathx.subV(r.centerWorld(), r.lockPoint()));
    std.debug.print("\n  ravager mark stands {d:.2} m off the hurt centre (sphere r {d:.2}, body r {d:.2})\n", .{ markOut, r.hurtRadius(), r.bodyR() });
    try std.testing.expect(markOut < r.hurtRadius() + r.bodyR() * 2.0);
    // …and a blow flinches it and a death ends it, through the shared reaction and nothing private.
    _ = r.vit.hit(.{ .dmg = 5, .poise = POISE_MAX + 1 });
    r.debugStagger(true);
    try std.testing.expect(r.staggered());
    r.vit.hp = 0;
    r.enterDeath();
    try std.testing.expect(r.dying() and r.justDied);
}

test "A LIGHT POKE DOES NOT FLINCH IT AND A HEAVY DOES — poise sized against the hero's own two swings" {
    var light = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(combat.HitResult.none, light.vit.hit(heromod.ATK_LIGHT_HIT));
    var heavy = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(combat.HitResult.light, heavy.vit.hit(heromod.ATK_HEAVY_HIT));
}

test "PLANT FLESH: fire is the answer to it and cold is not" {
    var burnt = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    var frozen = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const fire = combat.Hit{ .elem = combat.elems(.{ .fire = 20 }) };
    const cold = combat.Hit{ .elem = combat.elems(.{ .cold = 20 }) };
    try std.testing.expect(burnt.vit.damageFrom(fire) > 20.0); // it BURNS: a negative resistance amplifies
    try std.testing.expect(frozen.vit.damageFrom(cold) < 20.0);
    try std.testing.expect(burnt.vit.damageFrom(fire) > frozen.vit.damageFrom(cold));
}

test "THE LEAP IS COMMITTED AT THE LAUNCH — it aims while the bloom opens and steers not at all after" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.state = .bite;
    r.t = 0;
    // Through the GATHER it comes round onto him: the tell is also the aim.
    const side = mathx.ground(6, 0);
    var t: f32 = 0;
    while (t < BITE_WIND - 0.02) : (t += 1.0 / 60.0) _ = r.update(1.0 / 60.0, side, 200.0, .{});
    const aimed = r.facing;
    try std.testing.expect(@abs(mathx.wrapPi(aimed - mathx.headingXZ(mathx.dirXZ(r.pos, side)))) < 0.5);
    // …and once it is in the air, walking round it moves the facing NOT AT ALL, frame by frame.
    const behind = mathx.ground(-8, -6);
    while (t < BITE_WIND + BITE_STRIKE) : (t += 1.0 / 60.0) {
        _ = r.update(1.0 / 60.0, behind, 200.0, .{});
        try std.testing.expectApproxEqAbs(aimed, r.facing, 1e-5);
    }
}

test "STEERING IS ONLY THE TRAVEL STATE — a heading bent under a committed leap aims the blow at the wall" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = mathx.ground(0, 3);
    r.leash.noteSeen();
    try std.testing.expect(r.navWant(hero) != null); // idle, and he is inside its ring
    r.state = .bite;
    try std.testing.expect(r.navWant(hero) == null);
    r.state = .hurt;
    try std.testing.expect(r.navWant(hero) == null);
    r.state = .dead;
    try std.testing.expect(r.navWant(hero) == null);
}

test "IT CAN ACTUALLY HURT HIM — a foe lands a blow by RETURNING one, and one leap lands exactly one" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = mathx.ground(0, 1.2); // squarely in front, inside the bloom's reach
    r.leash.noteSeen();
    // Run it until the leap commits and then through the whole strike, counting what came back.
    var landed: usize = 0;
    var t: f32 = 0;
    var opened = false;
    while (t < 4.0) : (t += 1.0 / 60.0) {
        if (r.update(1.0 / 60.0, hero, 200.0, .{})) |h| {
            landed += 1;
            try std.testing.expectApproxEqAbs(BITE_HIT.dmg, h.dmg, 1e-4);
        }
        if (r.opened) opened = true;
        if (landed > 0 and r.state != .bite) break;
    }
    try std.testing.expect(opened); // the bloom told him it was coming…
    try std.testing.expectEqual(@as(usize, 1), landed); // …and ONE leap is ONE blow, not one a frame
}

test "A LEAP THAT WENT PAST HIM DOES NOT BITE HIM IN THE BACK OF THE NECK" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.state = .bite;
    r.t = BITE_WIND;
    // Behind it, and well inside the reach: the distance says yes and the FRONT says no.
    r.tryBite(mathx.ground(0, -1.2));
    try std.testing.expect(r.heroHit == null);
    // …and out past the bloom in front of it, which the reach refuses.
    r.tryBite(mathx.ground(0, BITE_R + foe.HERO_REACH + 0.6));
    try std.testing.expect(r.heroHit == null);
    // Squarely in front and in reach, it lands.
    r.tryBite(mathx.ground(0, 1.2));
    try std.testing.expect(r.heroHit != null);
}

test "THE INCOMING LATCH IS NOT THE OUTGOING ONE — one swing of his may not wound the same body twice" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const swing = foe.Blade{
        .active = true,
        .r = 0.3,
        .a = v3(0, 0.8, -1.0),
        .b = v3(0, 0.8, 1.0),
        .a0 = v3(0, 0.8, -1.0),
        .b0 = v3(0, 0.8, 1.0),
        .hit = .{ .dmg = 6, .poise = 2 },
    };
    r.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 1), r.hits);
    r.tryHit(swing); // the SAME swing, still live next frame
    try std.testing.expectEqual(@as(u32, 1), r.hits);
    // …and its own leap's clock may not clear that latch — it clears `heroLatch`, which is a different fact.
    // The SAME swing is still live across the frame, so it stays one wound.
    r.state = .bite;
    r.t = BITE_WIND + BITE_STRIKE + BITE_RECOVER;
    _ = r.update(1.0 / 60.0, mathx.ground(0, 40), 200.0, swing);
    try std.testing.expectEqual(@as(u32, 1), r.hits);
    // A SWING THAT ENDED AND A NEW ONE IS TWO WOUNDS, which is what the latch is for and not against.
    _ = r.update(1.0 / 60.0, mathx.ground(0, 40), 200.0, .{});
    r.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 2), r.hits);
}

test "HIS SWORD CAN ACTUALLY REACH IT — the blade is taken on every live state, not discarded" {
    const swing = foe.Blade{
        .active = true,
        .r = 0.35,
        .a = v3(0, 0.8, -1.2),
        .b = v3(0, 0.8, 1.2),
        .a0 = v3(0, 0.8, -1.2),
        .b0 = v3(0, 0.8, 1.2),
        .hit = .{ .dmg = 7, .poise = 3 },
    };
    // **EVERY LIVE STATE IS HITTABLE.** Ignored in the signature the creature was simply invulnerable, and
    // nothing else in the game calls `tryHit` for it — this is the only door.
    for ([_]State{ .idle, .move, .bite, .hurt }) |st| {
        var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
        r.state = st;
        r.t = if (st == .bite) BITE_WIND * 0.5 else 0;
        _ = r.update(1.0 / 60.0, mathx.ground(0, 30), 200.0, swing);
        try std.testing.expectEqual(@as(u32, 1), r.hits);
        try std.testing.expect(r.vit.hp < HP_MAX);
    }
}

test "THE BLOOM IS WIDE WHEN HE IS NEAR AND WIDER WHEN IT LEAPS — two tiers, and neither is a switch" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt: f32 = 1.0 / 60.0;
    // FAR OFF it is shut.
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) _ = r.update(dt, mathx.ground(0, NEAR_FAR + 6), 200.0, .{});
    try std.testing.expect(r.openAmt() < 0.05);

    // WALKED UP TO, it opens WIDE — and it eases there rather than stepping, so no two consecutive frames
    // jump by anything the eye would read as a shutter.
    var last = r.openAmt();
    var worst: f32 = 0;
    t = 0;
    while (t < 3.0) : (t += dt) {
        r.pos = mathx.zero3; // held: this is the bloom's dial under test, not the walk
        r.state = .idle;
        _ = r.update(dt, mathx.ground(0, NEAR_WIDE), 200.0, .{});
        worst = @max(worst, @abs(r.openAmt() - last));
        last = r.openAmt();
    }
    const near = r.openAmt();
    try std.testing.expect(near > 0.9); // VERY WIDE on approach…
    try std.testing.expect(worst < 0.09); // …and it unfurled, it did not snap

    // …AND THE ATTACK GOES WIDER STILL, by a margin the player can actually see.
    r.stagePounce(1.0);
    try std.testing.expect(r.openAmt() > near * 1.3);
    try std.testing.expectApproxEqAbs(ATTACK_OPEN, r.openAmt(), 1e-3);
    // The gape opens FROM where it already was, so choosing the leap cannot shut it for a frame first.
    r.state = .bite;
    r.t = 0;
    try std.testing.expectApproxEqAbs(near, r.openAmt(), 1e-3);
}

test "A DEAD ONE SHUTS — from across a field that is most of what says it is finished" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < 3.0) : (t += dt) _ = r.update(dt, mathx.ground(0, NEAR_WIDE), 200.0, .{});
    try std.testing.expect(r.openAmt() > 0.9);
    r.enterDeath();
    t = 0;
    while (t < 2.0) : (t += dt) _ = r.update(dt, mathx.ground(0, NEAR_WIDE), 200.0, .{});
    try std.testing.expect(r.openAmt() < 0.05);
}

test "…AND IN DEGREES, which is what the player is actually reading off the head" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < 3.0) : (t += dt) {
        r.pos = mathx.zero3;
        r.state = .idle;
        _ = r.update(dt, mathx.ground(0, NEAR_WIDE), 200.0, .{});
    }
    const near = r.openAmt();
    r.stagePounce(1.0);
    const atk = r.openAmt();
    std.debug.print("\n  ravager bloom: shut 0 deg | near {d:.0} deg gape, {d:.0} splay | attack {d:.0} deg gape, {d:.0} splay\n", .{
        PETAL_GAPE * near, PETAL_SPLAY * near, PETAL_GAPE * atk, PETAL_SPLAY * atk,
    });
    // VERY WIDE on approach and WIDER on the attack, in the angles the mesh is actually rotated by.
    try std.testing.expect(PETAL_GAPE * near > 40.0);
    try std.testing.expect(PETAL_GAPE * atk > PETAL_GAPE * near + 15.0);
}

test "A GIRAFFE FLOWER, NOT A DOG — the neck is long, upright, and it stretches with the bloom" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.pose();
    const rest = restPose();
    const withers = rest[CHEST].y;
    const head = rest[HEAD].y;
    // UPRIGHT: the head breaks the line of the back by a clear margin, and it is barely forward of the
    // shoulder. A canid carries it level and reaching out; that is the shape this is not.
    const out = rest[HEAD].z - rest[CHEST].z;
    std.debug.print("\n  ravager neck: withers {d:.2} m, head {d:.2} m ({d:.2}x), forward {d:.2} m\n", .{ withers, head, head / withers, out });
    try std.testing.expect(head > withers * 1.5);
    try std.testing.expect(out < (head - withers) * 0.5); // far more UP than OUT

    // …AND IT STRETCHES WITH THE BLOOM, on the one dial, so the stalk rears as the flower opens.
    const shut = r.jawPoint().y;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.stretchAmt(), 1e-6);
    r.stagePounce(1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), r.stretchAmt(), 1e-6);
    const outAt = r.jawPoint().y;
    std.debug.print("  …bloom at {d:.2} m shut, {d:.2} m reaching (leap included)\n", .{ shut, outAt });
    try std.testing.expect(outAt > shut);
    // A BIT, not a telescope (owner's word): the reach is a fraction of the neck, never a second neck.
    try std.testing.expect(NECK_STRETCH > 0.1 and NECK_STRETCH < 0.4);
}
