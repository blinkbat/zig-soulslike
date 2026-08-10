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

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;

// THE PALETTE. A BIG SMOOTH MASS NEEDS A NEARLY-BLACK ALBEDO (AGENTS.md) and this thing is four smooth
// masses, so the separation is HUE — cold blue-black chitin against a warm blood-brown abdomen.
const CHITIN = rgba(21, 20, 26, 255); // thorax and head: blue-black, the shell
const CHITIN_LT = rgba(38, 36, 46, 255);
const CHITIN_DK = rgba(9, 9, 12, 255);
/// THE ABDOMEN IS WARM, and it is the one place on the creature that says what it lives on. Empty it is
/// nearly as dark as the shell; `gorge` lerps it toward the full tone as it drinks.
const SAC = rgba(46, 24, 22, 255);
const SAC_FULL = rgba(122, 26, 26, 255);
const SAC_DK = rgba(20, 11, 10, 255);
const BEAK = rgba(30, 24, 20, 255); // the proboscis — horn, not shell
const BEAK_TIP = rgba(58, 46, 38, 255);
const LEG = rgba(16, 15, 20, 255);
/// THE WING. NEARLY BLACK and NORMALLY LIT (alpha 255): the emissive channel runs the other way — a low
/// alpha is SELF-lit, and at 74 the membrane ignored the sun and came back a pale feather. A big smooth
/// face has to start near-black on this key (AGENTS.md), and what makes it read as a membrane rather than a
/// paddle is the VEINS across it, which are the one thing on a wing that is not see-through.
const WING = rgba(27, 29, 39, 255);
const WING_RIB = rgba(72, 74, 92, 255);
/// THE EYES, and they are the whole read at range: two dark beads that come ALIGHT while it drinks.
const EYE = rgba(38, 9, 10, 255);
const EYE_LIT = rgba(255, 52, 40, 255);
// FX. The blood it takes is the one red in the effects; the chitin chip is the body's own.
const BLOOD = rgba(126, 20, 18, 235);
const CHIP = rgba(74, 70, 86, 235);

/// ITS OWN STATURE — nose to tail, and NOT the shared humanoid scaffold: it has no legs to walk on. SIZED
/// AGAINST A TOAD, then grown (owner): 1.3 m of body with a wingspan half again as wide.
pub const H: f32 = 1.3;

/// WHERE IT FLIES. `pos.y` is the ground under it (the one law every creature obeys) and `hover` is what it
/// is holding itself off that by — the same field the shade has, except this one MOVES.
const HOVER_LOW: f32 = 1.18; // the attack height: its beak at the hero's chest
const HOVER_IDLE: f32 = 1.75; // …and where it loiters when nothing has annoyed it
/// **OUT OF YOUR RANGE** (owner's whole point). The hero's blade sweeps a capsule off his own shoulder and
/// cannot reach a body four and a half metres up — but an ARROW can, and so can a bolt. That is the trade.
const HOVER_HIGH: f32 = 4.6;
const CLIMB_RATE: f32 = 8.5; // it ZOOMS — up out of a swing in a third of a second
const DIVE_RATE: f32 = 7.0;
const SETTLE_RATE: f32 = 3.2; // …and eases the last of it, or the hover reads as a lift shaft

pub const AGGRO_R: f32 = 15.0;
const BODY_R: f32 = 0.30;
const HURT_R: f32 = 0.40;
/// Fractions of stature, off `pos.y + hover`: the hurt sphere's centre, and where the HP bar hangs.
const CENTER_F: f32 = 0.10;
const TOP_F: f32 = 0.34;
/// The reticle's seat in the HEAD's own frame — between the two eyes, which is the only part of this
/// creature you can pick out while it is moving.
const LOCK_AT = v3(0, 0.03 * H, 0.10 * H);

const STALK_SPEED: f32 = 4.7; // faster than a sprint: you do not outrun it, you make it miss
const CIRCLE_SPEED: f32 = 4.1;
const TURN_RATE: f32 = 9.5; // …and it turns like a fly, which is to say almost instantly

const HP_MAX: f32 = 30.0; // fragile: the whole defence is being off the ground
const POISE_MAX: f32 = 7.0; // BELOW the hero's light poise damage — anything that connects swats it
const STANCE_MAX: f32 = 20.0;
/// A THIN MEMBRANE AND A BELLY FULL OF BLOOD. Fire is the answer and it is not close: the wings go up and
/// the thing drops. Cold slows it; the chaos it carries is what it has been drinking.
const RESISTS = combat.resists(.{ .fire = -55, .cold = -25, .chaos = 35 });
pub const RUNES: u32 = 95;

const DEATH_DUR: f32 = 0.85; // the wings stop and it falls out of the air
const DISS_DUR: f32 = 0.8;
/// …and the cloud it goes out in: a small body, close and quick.
const DISSOLVE = foe.Dissolve{ .rate = 30.0, .spread = 0.45, .rise = 0.30, .flake = CHIP };
const SHOVE_DECAY: f32 = 8.0;

// THE FEED — the one move it has, and the reason the creature exists.

/// THE BEAK GOING IN. A real blow: it carries a direction, the boards can catch it and a roll beats it.
/// Slight on purpose — this is not how it hurts you, it is how it gets HOLD of you.
pub const STAB_HIT = combat.Hit{ .dmg = 9, .poise = 9 };
/// …AND THE SWALLOW, billed EVERY FRAME while it is on you (`hero.burn` → `combat.Vitals.drip`). Written per
/// SECOND and scaled by `dt` at the site, because that is the only honest way to read a hold's damage.
pub const DRINK_DPS: f32 = 22.0;
/// HOW MUCH OF WHAT IT TAKES COMES BACK TO IT (owner: "leeches some of your life back to him"). SOME, not
/// all: a flyer that heals for everything it drinks is a stalemate against a player without a bow.
const LEECH_SHARE: f32 = 0.55;
const DRINK_DUR: f32 = 1.45; // how long it will hold on if nothing shakes it off
/// …and how often the pull of it is heard under the wingbeat. THINNED from 0.48: a hold runs for seconds and
/// a swallow twice a second is texture pretending to be an event. The BEAK GOING IN is the event.
const DRINK_EVERY: f32 = 0.80;
const FEED_CD: f32 = 3.4;
/// How far the beak reaches, off its own centre. Short — it has to be ON you.
const STAB_R: f32 = 1.30;
/// …and the arc it reaches through. A mosquito on your back is not one you can be stabbed by: the move
/// tests its OWN band (the ogre's law), and a wide-open bubble landed blows the shield could never answer.
const FEED_ARC: f32 = 62.0;
/// …and how high it can be and still have the beak on him. Its OWN number and not the sword`s: this is the
/// reach of a thing hanging off him, where `HOVER_HIGH` is about what a blade can answer.
const FEED_CEIL: f32 = HOVER_LOW + 0.8;

const WIND_DUR: f32 = 0.34; // the rear-back. Clears `foe.TELL_MIN` (0.30) — no attack comes out of nowhere
const STAB_DUR: f32 = 0.16;
const RECOVER_DUR: f32 = 0.45;

// THE CLIMB — "zoom up out of your range", and the thing nothing else in the game does.

/// How close he has to be before it wants out. Inside its own feeding band on purpose: it does not climb
/// away from a meal, it climbs away from a SWORD.
const THREAT_R: f32 = 2.0;
const CLIMB_CD: f32 = 3.8; // an evade you can spam is a wall (the archer's backstep law)
const PERCH_DUR: f32 = 1.5; // how long it hangs up there before it comes back down for you
/// A landed blow keeps it wanting out this long. Over `CLIMB_CD`, so a hit always buys the climb it is meant
/// to — and finite, or one arrow leaves it yo-yoing on its cooldown for the rest of the map.
const SPOOK_DUR: f32 = 5.0;

// Flight feel.
const WING_HZ_FLY: f32 = 26.0; // beats a second in the air — a blur, which is the point
const WING_HZ_HOVER: f32 = 20.0;
const WING_SWEEP: f32 = 62.0; // degrees either side of level
const BANK_MAX: f32 = 26.0; // how far it rolls into a turn
const PITCH_MAX: f32 = 22.0; // …and noses down into a dive
const BOB_AMP: f32 = 0.035 * H; // the hover's own unsteadiness
const BOB_HZ: f32 = 3.1;
/// THE WHINE COMES AND GOES (owner: it was too constant). raylib cannot loop a synthesized take, so a note
/// is a short voice retriggered — but retriggered forever it is a drill. A phrase is a run of overlapping
/// takes, and between phrases it says nothing; hushes outlast phrases, so mostly you should not hear it.
const WHINE_EVERY: f32 = 0.26; // the retrigger INSIDE a phrase, under the take's own 0.32 so they overlap
const PHRASE_MIN: f32 = 0.30;
const PHRASE_MAX: f32 = 0.95;
const HUSH_MIN: f32 = 1.30;
const HUSH_MAX: f32 = 4.20;

const PARTS = 40;

// The rig. Fifteen joints, and not one of them a leg to stand on.
const N = 15;
const ROOT = 0; // the thorax: everything hangs off it and it is what flies
const ABDO = 1; // the abdomen's first segment, hung back and down
const ABDO2 = 2; // …and the taper past it
const HEAD = 3;
const PROB = 4; // the proboscis
const EYEL = 5;
const EYER = 6;
const WINGL = 7;
const WINGR = 8;
const LEG_0 = 9;
/// SIX LEGS, three a side, one bone each. The KINK is authored into the mesh rather than given a second
/// joint apiece: what a leg needs from the pose is a dangle and a curl, not twelve bones of rig.
const LEG_N = 6;

const SH_HALF: f32 = 0.085 * H; // where a wing roots, off the thorax's midline
const EYE_HALF: f32 = 0.062 * H;

/// Each joint's rest offset IN ITS PARENT'S FRAME. The thorax is the origin; +Z is forward.
const REST = blk: {
    var r = [_]rl.Vector3{mathx.zero3} ** N;
    r[ROOT] = v3(0, 0, 0);
    r[ABDO] = v3(0, -0.020 * H, -0.145 * H);
    r[ABDO2] = v3(0, -0.010 * H, -0.335 * H);
    r[HEAD] = v3(0, 0.010 * H, 0.150 * H);
    r[PROB] = v3(0, -0.045 * H, 0.075 * H);
    r[EYEL] = v3(EYE_HALF, 0.030 * H, 0.048 * H);
    r[EYER] = v3(-EYE_HALF, 0.030 * H, 0.048 * H);
    r[WINGL] = v3(SH_HALF, 0.070 * H, -0.020 * H);
    r[WINGR] = v3(-SH_HALF, 0.070 * H, -0.020 * H);
    // Three pairs down the thorax, front to back, each a little wider and a little further under.
    for (0..LEG_N) |i| {
        const pair = i / 2;
        const side: f32 = if (i % 2 == 0) 1 else -1;
        const fz = 0.075 - 0.075 * @as(f32, @floatFromInt(pair)); // +front, 0, −back
        r[LEG_0 + i] = v3(side * 0.055 * H, -0.048 * H, fz * H);
    }
    break :blk r;
};

/// WHICH PAIR A LEG BELONGS TO, and which side — the pose reads both and the mesh builder reads the pair.
fn legPair(i: usize) usize {
    return i / 2;
}
fn legSide(i: usize) f32 {
    return if (i % 2 == 0) 1 else -1;
}

/// THE FEED'S CLOCK, for anything aiming at a beat inside it (`shots.zig`). Off the constants themselves, so
/// a retuned window still photographs the beat it is named after rather than a literal number of seconds.
pub fn feedClock() struct { wind: f32, stab: f32, drink: f32 } {
    return .{ .wind = WIND_DUR, .stab = STAB_DUR, .drink = DRINK_DUR };
}

const State = enum { idle, stalk, circle, wind, stab, drink, recover, climb, perch, dive, stunlight, stunheavy, dead };

/// PURE DECISION — a function of range and cooldowns, so the bands are testable without a world.
const Choice = enum { hold, close, circle, feed };
fn classify(dist: f32, feedReady: bool) Choice {
    if (dist > AGGRO_R) return .hold;
    if (dist <= STAB_R) return if (feedReady) .feed else .circle;
    if (dist > STAB_R + 1.4) return .close;
    return .circle;
}

/// THE CLIMB'S OWN GATE, `shade.wantsBlink`'s shape and for its reasons. `spooked` is what a landed blow
/// leaves behind: it does not zoom out of the stagger itself — that would erase the punish window — it goes
/// the moment the flinch lets go. AND THE ROOTS REFUSE IT OUTRIGHT (`foe.canLeap`): a climb leaves the
/// earth, so it is gated where the move is CHOSEN, and rooted the sword finally gets to answer it.
fn wantsClimb(dist: f32, cd: f32, spooked: bool, s: State, rooted: bool) bool {
    if (cd > 0 or rooted) return false;
    if (!spooked and dist > THREAT_R) return false;
    return switch (s) {
        .idle, .stalk, .circle, .recover => true,
        .wind, .stab, .drink, .climb, .perch, .dive, .stunlight, .stunheavy, .dead => false,
    };
}

/// What one frame of this creature did that the world outside it has to answer for.
pub const Act = union(enum) {
    none,
    /// The beak went in — a BLOW, and it goes through `?foe.Blow` like every other creature's.
    stab: combat.Hit,
    /// …and this frame's swallow, which is a HOLD and goes through `hero.burn`.
    drink: combat.Hit,
};

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("leechfly material");
        mat.shader = shader;
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, f: *const Leechfly) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, f.xf[i]);
    }
};

pub const Leechfly = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// THE WAND'S ROOTS, when they have hold of it — stamped from outside, like the leash's eyes. On this
    /// creature they are the counter to the whole design: rooted, it cannot climb (`wantsClimb`).
    root: combat.Root = .{},
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    dealt: bool = false, // one stab per strike, latched
    feedCd: f32 = 0,
    climbCd: f32 = 0,
    spookLeft: f32 = 0,
    driftDir: rl.Vector3 = mathx.zero3,
    orbitSign: f32 = 1,
    whineT: f32 = 0,
    /// How much of the current whine PHRASE is left; 0 means it is between phrases and `whineT` is holding
    /// the silence. See `beatWings`.
    phraseLeft: f32 = 0,

    /// HOW HIGH IT IS FLYING, in metres off the ground under it. The one field that makes this creature what
    /// it is: every world point it has is measured off `pos.y + hover`.
    hover: f32 = HOVER_IDLE,
    /// …and where it is trying to be, which the state machine sets and `flyTo` walks it to.
    hoverTo: f32 = HOVER_IDLE,

    // Posture channels, resolved by the state and read by pose().
    wingPhase: f32 = 0,
    bank: f32 = 0,
    pitch: f32 = 0,
    /// 0 = the beak tucked under, 1 = thrown out in front. The whole tell of the feed.
    lunge: f32 = 0,
    /// 0 = an empty belly, 1 = swollen with what it has taken. Fills as it drinks and stays full — it does
    /// not give it back, and a fed one you failed to kill is a thing you can SEE you failed to kill.
    gorge: f32 = 0,
    /// The eyes coming alight, which is what says the drain is happening (owner's call). Its own channel and
    /// not `gorge`, because it is the ACT that lights them, not the belly.
    glow: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    fade: f32 = 0,
    gone: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Leechfly {
        var f = Leechfly{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        f.fxRng = foe.fxStream(seed, 61441.0, 0xB10D);
        f.orbitSign = if (seed < 0.5) 1 else -1;
        f.wingPhase = seed; // a swarm beating in lockstep is one insect with echoes
        // STAGGERED HARD ACROSS THE SWARM: on one clock five of them whine and fall silent together, which is
        // a chorus and not five insects. The first hush is most of a full one, so a fresh field is quiet.
        f.whineT = seed * (HUSH_MIN + HUSH_MAX) * 0.5;
        f.phraseLeft = seed * PHRASE_MAX;
        f.feedCd = seed * FEED_CD;
        f.pose();
        return f;
    }

    // EVERY WORLD POINT IS MEASURED OFF `pos.y` PLUS THE HOVER — `pos.y` is the ground under it and `hover`
    // is how far it is flying above that, so one over a bank keeps its bar over its own head.
    fn lift(self: *const Leechfly) f32 {
        return self.hover * self.scale;
    }
    pub fn centerWorld(self: *const Leechfly) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, self.lift());
    }
    /// THE MARK RIDES THE HEAD, and this creature is why the rule earns its keep twice: it bobs on its own
    /// wingbeat AND climbs four metres in a third of a second. A height off the ground would hold the reticle in the grass while the thing it names went over the treeline.
    pub fn lockPoint(self: *const Leechfly) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], LOCK_AT);
    }
    pub fn topWorld(self: *const Leechfly) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, self.lift());
    }
    pub fn hurtRadius(self: *const Leechfly) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Leechfly) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Leechfly) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Leechfly) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Leechfly) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    /// IT IS ALWAYS AIRBORNE, which exempts it from the terrain gate and from being shouldered by anything on
    /// the ground. NOT exempt from `env.resolveActor`: fly through a wall and there is nowhere to come back from.
    pub fn airborne(self: *const Leechfly) bool {
        return !self.gone;
    }
    pub fn flashFrac(self: *const Leechfly) f32 {
        return foe.flashFrac(self.flash);
    }
    /// Where the beak's point is this frame — what the feed is measured from and where its blood flies off.
    pub fn beakWorld(self: *const Leechfly) rl.Vector3 {
        return foe.markOn(self.xf[PROB], v3(0, 0, PROB_LEN * H));
    }

    pub fn update(self: *Leechfly, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) Act {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return .none;
        }
        self.justDied = false; // one-frame flag, reset at the TOP (the foe contract's own rule)
        // THE ROOTS HAVE IT. The flight is given back as a post-step gate and the beak still goes in; the
        // CLIMB is the one thing refused outright, at the choose site below — see `wantsClimb`.
        const grip = foe.grip(&self.root, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        self.feedCd = mathx.maxF(0, self.feedCd - dt);
        self.climbCd = mathx.maxF(0, self.climbCd - dt);
        self.spookLeft = mathx.maxF(0, self.spookLeft - dt);
        self.leash.tick(dt, mathx.distXZ(self.pos, self.home), mathx.distXZ(self.pos, hero), AGGRO_R);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
        foe.tickParticles(&self.parts, dt, self.pos.y);

        var act: Act = .none;
        const d = foe.sensedDist(&self.leash, mathx.distXZ(self.pos, hero), AGGRO_R);

        switch (self.state) {
            .idle => {
                self.hoverTo = HOVER_IDLE;
                self.easeRest(dt);
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.decide(d, hero);
            },
            .stalk => {
                self.hoverTo = HOVER_LOW;
                self.easeRest(dt);
                self.faceToward(hero, dt);
                self.flyXZ(self.driftDir, STALK_SPEED, dt, bounds);
                self.decide(d, hero);
            },
            .circle => {
                self.hoverTo = HOVER_LOW;
                self.easeRest(dt);
                self.faceToward(hero, dt);
                self.flyXZ(self.driftDir, CIRCLE_SPEED, dt, bounds);
                if (self.t >= 0.85) self.decide(d, hero) else self.aimOrbit(hero);
            },
            // THE REAR-BACK. It pulls up and away before it comes in, which is the whole tell: straight to
            // the beak there is no frame of this move you could have answered.
            .wind => {
                self.hoverTo = HOVER_LOW + 0.30;
                self.faceToward(hero, dt);
                self.lunge = mathx.approach(self.lunge, -0.45, dt * 6.0);
                self.pitch = mathx.approach(self.pitch, -14.0, dt * 90.0);
                if (self.t >= WIND_DUR) self.enter(.stab);
            },
            .stab => {
                self.hoverTo = HOVER_LOW;
                const u = mathx.clampF(self.t / STAB_DUR, 0, 1);
                self.lunge = lerpF(-0.45, 1.0, foe.swingCurve(u));
                self.pitch = mathx.approach(self.pitch, 16.0, dt * 140.0);
                if (!self.dealt and u >= 0.45 and self.holds(hero)) {
                    self.dealt = true;
                    self.leash.noteCombat();
                    sfx.world(.leech_stab, self.beakWorld());
                    act = .{ .stab = STAB_HIT };
                }
                if (self.t >= STAB_DUR) self.enter(if (self.dealt) .drink else .recover);
            },
            // THE SWALLOW. A HOLD and not a blow: billed every frame through `hero.burn`, and it ends the
            // moment he is no longer under the beak — which is what makes the ROLL the answer to it.
            .drink => {
                self.hoverTo = HOVER_LOW;
                self.lunge = mathx.approach(self.lunge, 0.86, dt * 8.0);
                self.pitch = mathx.approach(self.pitch, 20.0, dt * 60.0);
                self.glow = mathx.approach(self.glow, 1.0, dt * 5.0);
                if (!self.holds(hero) or self.t >= DRINK_DUR) {
                    self.enter(.recover);
                } else {
                    // …and it stays ON him: a mosquito that drifts off while it drinks is one you never
                    // had to shake, so it closes any gap he opens without leaving its own reach.
                    self.faceToward(hero, dt);
                    self.clingTo(hero, dt, bounds);
                    // THE PULL, on its own slow cadence under the wingbeat. Off a CROSSING of the state's own
                    // clock (the ogre's footfall idiom) rather than a field, so nothing needs resetting.
                    if (@floor(self.t / DRINK_EVERY) != @floor((self.t - dt) / DRINK_EVERY)) {
                        sfx.world(.leech_drink, self.beakWorld());
                    }
                    act = .{ .drink = self.sip(dt) };
                }
            },
            .recover => {
                self.hoverTo = HOVER_LOW;
                self.easeRest(dt);
                self.faceToward(hero, dt);
                if (self.t >= RECOVER_DUR) self.decide(d, hero);
            },
            // ZOOMING UP OUT OF YOUR RANGE — the move the whole creature is built around.
            .climb => {
                self.hoverTo = HOVER_HIGH;
                self.easeRest(dt);
                self.faceToward(hero, dt);
                self.pitch = mathx.approach(self.pitch, -30.0, dt * 120.0);
                if (self.hover >= HOVER_HIGH - 0.15) self.enter(.perch);
            },
            // …and hanging there, out of reach, working round behind him before it comes back down.
            .perch => {
                self.hoverTo = HOVER_HIGH;
                self.easeRest(dt);
                self.faceToward(hero, dt);
                self.aimOrbit(hero);
                self.flyXZ(self.driftDir, CIRCLE_SPEED * 0.8, dt, bounds);
                if (self.t >= PERCH_DUR) self.enter(.dive);
            },
            .dive => {
                self.hoverTo = HOVER_LOW;
                self.faceToward(hero, dt);
                self.pitch = mathx.approach(self.pitch, PITCH_MAX, dt * 120.0);
                self.driftDir = mathx.dirXZ(self.pos, hero);
                self.flyXZ(self.driftDir, STALK_SPEED, dt, bounds);
                if (self.hover <= HOVER_LOW + 0.20) self.decide(d, hero);
            },
            .stunlight => {
                // A SWATTED FLY DROPS. It does not hold its station through a flinch — the height sagging is
                // most of what a hit on this creature LOOKS like, and it is the window to hit it again in.
                self.hoverTo = HOVER_LOW * 0.55;
                self.easeRest(dt);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enter(.idle);
            },
            .stunheavy => {
                self.hoverTo = HOVER_LOW * 0.35;
                self.easeRest(dt);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enter(.idle);
            },
            .dead => {
                // IT FALLS OUT OF THE AIR. The wings stop, the hover runs out from under it, and only then
                // does the shared tail take it (`foe.dissipate`).
                self.hoverTo = 0;
                self.lunge = mathx.approach(self.lunge, -0.2, dt * 2.0);
                self.pitch = mathx.approach(self.pitch, 62.0, dt * 90.0);
                self.bank = mathx.approach(self.bank, 74.0, dt * 80.0);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        // THE CLIMB IS ASKED LAST, off the state the frame settled into — asked before the machine it fires
        // on the frame a stun ENDS and eats its own launch, which reads as a stutter and not a jump.
        if (wantsClimb(d, self.climbCd, self.spookLeft > 0, self.state, !foe.canLeap(&self.root))) self.enterClimb();

        self.flyTo(dt);
        self.beatWings(dt);
        self.pose();
        self.tryHit(blade); // the hero's blade AFTER the machine, so a kill sets justDied for THIS frame
        return act;
    }

    /// THIS FRAME'S SWALLOW, and the creature takes its share of it here. Billed per SECOND and scaled by
    /// `dt`, which is the only honest way to write a hold's damage.
    /// IT HEALS OFF WHAT IT BILLS, not off what the hero actually lost — the same figure today, since nothing
    /// grants the hero resistances yet, but this is the line that has to start asking the day one does.
    fn sip(self: *Leechfly, dt: f32) combat.Hit {
        const h = combat.Hit{ .dmg = DRINK_DPS * dt };
        _ = self.vit.heal(h.dmg * LEECH_SHARE);
        self.gorge = mathx.minF(1.0, self.gorge + dt / DRINK_DUR);
        self.bloodMotes();
        return h;
    }

    /// How far the beak actually reaches in world units — its own scale, since a big one has a long one.
    pub fn stabReach(self: *const Leechfly) f32 {
        return (STAB_R + foe.HERO_REACH) * self.scale;
    }

    /// Is he under the beak — near enough, IN FRONT of it, and is the creature low enough to have got there?
    /// The height is not a nicety: perched at four metres the XZ distance says it is on top of him.
    pub fn holds(self: *const Leechfly, hero: rl.Vector3) bool {
        if (self.hover > FEED_CEIL) return false;
        if (mathx.distXZ(self.pos, hero) > self.stabReach()) return false;
        const to = mathx.dirXZ(self.pos, hero);
        if (mathx.lenXZ(to) < 1e-4) return true; // right on top of him: no bearing to be wrong about
        return @abs(mathx.degrees(mathx.wrapPi(mathx.headingXZ(to) - self.facing))) <= FEED_ARC;
    }

    /// WALK THE HOVER toward what the state asked for. Up is faster than down, and the last of either is
    /// EASED — a linear arrival at a height reads as a lift stopping at a floor.
    fn flyTo(self: *Leechfly, dt: f32) void {
        const gap = self.hoverTo - self.hover;
        const rate = if (gap > 0) CLIMB_RATE else DIVE_RATE;
        const ease = mathx.clampF(@abs(gap) / 0.6, 0.18, 1.0);
        self.hover = mathx.approach(self.hover, self.hoverTo, rate * ease * dt + SETTLE_RATE * 0.02 * dt);
    }

    /// One step of flight across the ground, and the BANK that goes with it. Travel is `mathx.stepXZ` like
    /// everything else — the height is the only thing about this creature's movement that is its own.
    fn flyXZ(self: *Leechfly, dir: rl.Vector3, speed: f32, dt: f32, bounds: f32) void {
        mathx.stepXZ(&self.pos, dir, speed * dt, bounds);
        // Roll INTO the turn, off how far the travel is off its nose. A flyer that stays level through a
        // hard turn reads as a sprite being dragged about.
        const off = mathx.wrapPi(mathx.headingXZ(dir) - self.facing);
        self.bank = mathx.approach(self.bank, mathx.clampF(mathx.degrees(off) * 0.5, -BANK_MAX, BANK_MAX), dt * 180.0);
    }

    /// STAY ON HIM while it drinks: close whatever gap he opens, but never past the reach — it is holding on,
    /// not chasing. Without this a hero who backs off one step is free of it and the drink was never a hold.
    fn clingTo(self: *Leechfly, hero: rl.Vector3, dt: f32, bounds: f32) void {
        const want = self.stabReach() * 0.42;
        const gap = mathx.distXZ(self.pos, hero) - want;
        if (gap <= 0) return;
        mathx.stepXZ(&self.pos, mathx.dirXZ(self.pos, hero), mathx.minF(gap, STALK_SPEED * dt), bounds);
    }

    /// THE WINGBEAT, and its own whine with it. The phase runs on its own clock and NOT on travel — a fly
    /// hovering dead still is beating hardest of all, which is the opposite of how a gait works.
    fn beatWings(self: *Leechfly, dt: f32) void {
        if (self.state == .dead) {
            self.wingPhase += dt * 2.0; // guttering out as it falls
            return;
        }
        const moving = self.state == .stalk or self.state == .dive or self.state == .climb;
        self.wingPhase += dt * (if (moving) WING_HZ_FLY else WING_HZ_HOVER);
        // …AND THE NOTE IS PHRASED, not held. `whineT` doubles as both clocks: inside a phrase it is the
        // retrigger, at the end of one it is set to the whole HUSH — so the silence needs no second field.
        self.whineT -= dt;
        if (self.whineT > 0) return;
        if (self.phraseLeft > 0) {
            self.phraseLeft -= WHINE_EVERY;
            self.whineT = WHINE_EVERY;
            sfx.world(.leech_wing, self.centerWorld());
            return;
        }
        self.whineT = self.fxRng.range(HUSH_MIN, HUSH_MAX);
        self.phraseLeft = self.fxRng.range(PHRASE_MIN, PHRASE_MAX);
    }

    fn faceToward(self: *Leechfly, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    fn easeRest(self: *Leechfly, dt: f32) void {
        self.lunge = mathx.approach(self.lunge, 0, dt * 5.0);
        self.pitch = mathx.approach(self.pitch, 0, dt * 90.0);
        self.glow = mathx.approach(self.glow, 0, dt * 2.2);
    }

    fn enter(self: *Leechfly, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
    }

    fn enterClimb(self: *Leechfly) void {
        self.climbCd = CLIMB_CD;
        self.spookLeft = 0;
        sfx.world(.leech_wing, self.centerWorld());
        self.enter(.climb);
    }

    fn decide(self: *Leechfly, dist: f32, hero: rl.Vector3) void {
        if (self.leash.goingHome()) {
            self.driftDir = mathx.dirXZ(self.pos, self.home);
            return self.enter(.stalk);
        }
        switch (classify(dist, self.feedCd <= 0)) {
            .hold => self.enter(.idle),
            .close => {
                self.driftDir = mathx.dirXZ(self.pos, hero);
                self.enter(.stalk);
            },
            .circle => {
                self.aimOrbit(hero);
                self.enter(.circle);
            },
            .feed => {
                self.feedCd = FEED_CD;
                self.enter(.wind);
            },
        }
    }

    /// A leg of an orbit round him, at whatever radius it is already holding.
    fn aimOrbit(self: *Leechfly, hero: rl.Vector3) void {
        const to = mathx.dirXZ(hero, self.pos);
        self.driftDir = mathx.normV(v3(-to.z * self.orbitSign, 0, to.x * self.orbitSign));
    }

    fn enterStun(self: *Leechfly, s: State) void {
        self.enter(s);
        self.vit.beginStun(if (s == .stunheavy) .heavy else .light);
    }

    fn enterDeath(self: *Leechfly) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    pub fn debugKill(self: *Leechfly) void {
        self.enterDeath();
    }

    pub fn debugStagger(self: *Leechfly, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }

    /// FORCE THE FEED for the shot harness, at ATTACK HEIGHT: a fresh one loiters at `HOVER_IDLE`, so a
    /// photograph of the beak going in would be one of it going in half a metre over his head.
    /// `runFor` is how long the caller means to step it. The wind and the drink are entered DIRECTLY, because
    /// the chain only fires with a hero under the beak and the harness's hero is a position, not a body.
    ///
    pub fn debugFeedFrom(self: *Leechfly, runFor: f32) void {
        self.hover = HOVER_LOW;
        self.hoverTo = HOVER_LOW;
        self.feedCd = FEED_CD;
        self.climbCd = CLIMB_CD; // …and it must not zoom off mid-portrait
        if (runFor >= WIND_DUR + STAB_DUR) {
            self.enter(.drink);
            self.glow = 0.75;
            self.gorge = 0.45;
        } else {
            self.enter(.wind);
        }
    }

    /// …and force the climb, for the one frame that shows what this creature is.
    pub fn debugClimb(self: *Leechfly) void {
        self.climbCd = CLIMB_CD;
        self.enter(.climb);
    }

    pub fn tryHit(self: *Leechfly, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        self.spookLeft = SPOOK_DUR; // …and it goes up the moment it is done flinching (`wantsClimb`)
        const heavy = foe.wounded(self, s, blade, .{ .light = 1.6, .heavy = 2.6 });
        self.splatter(s.contact, s.dir, if (heavy) 14 else 8);
        sfx.world(.leech_hurt, self.centerWorld());
        switch (s.reaction) {
            .death => {
                sfx.world(.leech_die, self.centerWorld());
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn emit(self: *Leechfly, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.parts, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }

    /// WHAT COMES OUT OF A STRUCK ONE — blood it has already taken, and chips of its own shell. A fed one
    /// bleeds redder, which is the same `gorge` the belly is drawn off: what it is full of is what spills.
    fn splatter(self: *Leechfly, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.5, 1.0) * 2.4;
            const wet = self.fxRng.float() < 0.35 + 0.5 * self.gorge;
            self.emit(
                v3(at.x + self.fxRng.signed() * 0.06, at.y + self.fxRng.signed() * 0.06, at.z + self.fxRng.signed() * 0.06),
                v3(dir.x * sp + mathx.cosf(a) * sp * 0.5, self.fxRng.range(0.6, 2.4), dir.z * sp + mathx.sinf(a) * sp * 0.5),
                self.fxRng.range(0.28, 0.55),
                self.fxRng.range(0.02, 0.045) * self.scale,
                0.006,
                if (wet) BLOOD else CHIP,
                6.5,
            );
        }
    }

    /// THE STREAM GOING THE WRONG WAY. Every other drain in the game throws motes off the hero toward the
    /// thing taking them (`shade.drainMotes`) and so does this one — it is the one picture that says whose
    /// blood it is. Thrown from the BEAK, since that is where it is going in.
    fn bloodMotes(self: *Leechfly) void {
        // Rate-limited by the RNG and NOT by an accumulator: `fxAccum` belongs to the dissolve, and a second
        // thing stepping it would have the corpse coming apart at whatever rate it had last drunk at.
        if (self.fxRng.float() > 0.55) return;
        const tip = self.beakWorld();
        const to = self.centerWorld();
        const life = self.fxRng.range(0.14, 0.22);
        const d = mathx.subV(to, tip);
        self.emit(
            v3(tip.x + self.fxRng.signed() * 0.05, tip.y + self.fxRng.signed() * 0.05, tip.z + self.fxRng.signed() * 0.05),
            mathx.scaleV(d, 1.0 / life),
            life,
            self.fxRng.range(0.018, 0.032) * self.scale,
            0.005,
            BLOOD,
            -0.4, // they RIDE UP the beak, which is the direction that says it is being taken
        );
    }

    /// UNLIT OVER THE OPAQUE PASS, like every group's — the particles, and the EYES coming alight while it
    /// drinks. The eyes are drawn here rather than lit in the mesh because the mesh's own emissive is a fixed
    /// vertex channel: it cannot brighten, and brightening is the entire cue.
    pub fn drawFx(self: *const Leechfly) void {
        foe.drawParticles(&self.parts);
        if (self.glow <= 0.02 or self.gone) return;
        const a = mathx.clampF(self.glow, 0, 1);
        const r = EYE_R * H * self.scale;
        for ([_]usize{ EYEL, EYER }) |b| {
            const p = foe.markOn(self.xf[b], mathx.zero3);
            rl.drawSphereEx(p, r * (1.10 + 0.10 * a), 8, 10, mathx.withAlpha(EYE_LIT, mathx.u8f(230.0 * a)));
            // …and the bloom off it, big and faint, or two hard beads read as painted-on dots.
            rl.drawSphereEx(p, r * (2.1 + 0.7 * a), 8, 10, mathx.withAlpha(EYE_LIT, mathx.u8f(60.0 * a)));
        }
    }

    pub fn draw(self: *const Leechfly, model: *const Model) void {
        model.draw(self);
    }

    /// ONE WORLD MATRIX PER BONE, once a frame. `draw` only replays them, so the silhouette and the shadow
    /// can never disagree (the hero's law, and it holds for everything with a rig).
    pub fn pose(self: *Leechfly) void {
        // The whole body shrinks into the dissipation, and SINKS as it goes: a corpse fading at flight
        // height is a thing that never fell.
        const fs = self.scale * (1.0 - 0.7 * self.fade);
        const bob = mathx.sinf((self.elapsed + self.seed) * BOB_HZ * std.math.tau) * BOB_AMP * self.scale;
        const root = mul3(
            scaleM(fs, fs, fs),
            mul(rz(self.bank), mul(rx(self.pitch), ry(mathx.degrees(self.facing)))),
            tr(self.pos.x, self.pos.y + self.lift() + bob, self.pos.z),
        );
        self.xf[ROOT] = mul(place(REST[ROOT]), root);

        // THE ABDOMEN DROOPS AND SWINGS. It is the heaviest thing on the creature and hangs off a hinge: it
        // lags the pitch rather than following it, and lifts as the belly fills — a full one is carried.
        // NEGATIVE IS DOWN here: at +26 it stood off the thorax like a wasp's gaster, which is a hornet's
        // silhouette and not a mosquito's.
        const droop = -(15.0 - 11.0 * self.gorge) + self.pitch * 0.45;
        const swing = mathx.sinf((self.elapsed * 1.7 + self.seed) * std.math.tau) * 4.0;
        self.xf[ABDO] = mul(mul(rx(droop), place(REST[ABDO])), self.xf[ROOT]);
        self.xf[ABDO2] = mul(mul(rx(9.0 + swing), place(REST[ABDO2])), self.xf[ABDO]);

        // THE HEAD leads the lunge and the beak leads the head, so the two together carry the strike further
        // than either could — and the pitch is what aims the point at him rather than at the sky.
        const headPitch = 8.0 + 26.0 * self.lunge;
        self.xf[HEAD] = mul(mul(rx(headPitch), place(REST[HEAD])), self.xf[ROOT]);
        const probPitch = 46.0 - 34.0 * self.lunge; // tucked under at rest, level and forward at full reach
        self.xf[PROB] = mul(mul(rx(probPitch), place(REST[PROB])), self.xf[HEAD]);
        self.xf[EYEL] = mul(place(REST[EYEL]), self.xf[HEAD]);
        self.xf[EYER] = mul(place(REST[EYER]), self.xf[HEAD]);

        // THE WINGS. A beat is one sweep up-and-back and one down-and-forward, and the FEATHERING — the
        // wing rolling over at each end of the stroke — is what stops two flat paddles reading as a
        // cardboard bird. Left and right are mirrored through the sign, never authored twice.
        const beat = mathx.sinf(self.wingPhase * std.math.tau);
        const feather = mathx.cosf(self.wingPhase * std.math.tau);
        const amp = if (self.state == .dead) WING_SWEEP * 0.15 else WING_SWEEP;
        for ([_]usize{ WINGL, WINGR }, [_]f32{ 1, -1 }) |b, side| {
            const flap = beat * amp * side;
            const twist = feather * 34.0 * side;
            self.xf[b] = mul(mul3(ry(twist), rz(flap), place(REST[b])), self.xf[ROOT]);
        }

        // THE LEGS DANGLE, and UNEVENLY — six identical trailing wires is a rake. Each pair swings on its own
        // phase off the wingbeat, and the front pair reaches forward while the back pair trails.
        for (0..LEG_N) |i| {
            const pair = legPair(i);
            const side = legSide(i);
            const ph = self.wingPhase * std.math.tau + @as(f32, @floatFromInt(pair)) * 1.9 + self.seed * 3.0;
            const kick = mathx.sinf(ph) * 7.0;
            const reach = 34.0 - 30.0 * @as(f32, @floatFromInt(pair)); // front reaches, back trails
            const splay = (14.0 + 8.0 * @as(f32, @floatFromInt(pair))) * side;
            self.xf[LEG_0 + i] = mul(mul3(rz(splay), rx(reach + kick), place(REST[LEG_0 + i])), self.xf[ROOT]);
        }
    }
};

fn place(p: rl.Vector3) rl.Matrix {
    return tr(p.x, p.y, p.z);
}

// FLESH IS ROUND (AGENTS.md): every mass here is `addBlob`/`addCapsule`. The only flat things on the
// creature are the wing membranes, which are flat because a wing is.

/// How long the proboscis is, in stature. Read by `beakWorld` as well as by the builder, so the point the
/// feed is measured from IS the point the mesh draws (the ogre's `clubLowWorld` law).
const PROB_LEN: f32 = 0.30;
const EYE_R: f32 = 0.048;

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = thoraxMesh();
    mesh[ABDO] = abdomenMesh(0);
    mesh[ABDO2] = abdomenMesh(1);
    mesh[HEAD] = headMesh();
    mesh[PROB] = probMesh();
    mesh[EYEL] = eyeMesh(1);
    mesh[EYER] = eyeMesh(-1);
    mesh[WINGL] = wingMesh(1);
    mesh[WINGR] = wingMesh(-1);
    for (0..LEG_N) |i| mesh[LEG_0 + i] = legMesh(i);
    return mesh;
}

/// THE THORAX — a humped barrel, taller than it is wide, with the wing roots standing proud of it. Seeded
/// wonk on every lump: a single mesh still wants its own asymmetry, or it reads as a lathe part.
fn thoraxMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x1EEC4);
    b.addBlob(v3(0, 0, 0), v3(0.088 * H, 0.098 * H, 0.132 * H), 9, 14, CHITIN);
    // The hump over the wing roots, sunk most of the way in — RELIEF IS SUBTLE (a few percent of the mass).
    b.addBlob(v3(0, 0.058 * H, -0.010 * H), v3(0.066 * H, 0.052 * H, 0.086 * H), 7, 12, CHITIN_LT);
    // A collar where the head joins, and the pinch behind it where the abdomen does.
    b.addBlob(v3(0, 0.004 * H, 0.104 * H), v3(0.062 * H, 0.062 * H, 0.040 * H), 6, 12, CHITIN_DK);
    b.addBlob(v3(0, -0.014 * H, -0.126 * H), v3(0.050 * H, 0.048 * H, 0.036 * H), 6, 12, CHITIN_DK);
    // Two bristle ridges down the back, uneven — the shell's own break-up (a dark smooth mass reads as
    // plastic without breaks, AGENTS.md).
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const t = -0.06 + 0.032 * @as(f32, @floatFromInt(i));
        const w = rng.range(0.85, 1.2);
        b.addBlob(v3(rng.signed() * 0.006 * H, 0.088 * H * w, t * H), v3(0.010 * H, 0.014 * H * w, 0.012 * H), 4, 7, CHITIN_DK);
    }
    return b.toMesh();
}

/// THE ABDOMEN, in two segments that taper — and NOTHING ENDS IN A POINT: the far end is a blunt, rounded
/// stub, not a needle. Segment 0 is the fat one the blood goes into.
fn abdomenMesh(seg: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5AC0 + @as(u64, seg));
    // LONG AND SLENDER, not a sausage. At 0.070 radius over 0.27 of stature the first segment was as thick
    // as it was long and the creature read as a bee — the taper is what says which insect this is.
    const fat: f32 = if (seg == 0) 1.0 else 0.72;
    const len: f32 = if (seg == 0) 0.175 else 0.165;
    b.addCapsule(
        v3(0, 0, 0),
        v3(0, -0.010 * H, -len * H * 2.0),
        0.049 * H * fat,
        0.034 * H * fat,
        12,
        if (seg == 0) SAC else SAC_DK,
    );
    // The BANDS — a mosquito's abdomen is ringed, and the rings are what make a smooth taper read as a body.
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const t = 0.20 + 0.26 * @as(f32, @floatFromInt(i));
        const w = rng.range(0.9, 1.08);
        b.addBlob(
            v3(0, -0.010 * H * t, -len * H * 2.0 * t),
            v3(0.050 * H * fat * (1.0 - 0.26 * t) * w, 0.046 * H * fat * (1.0 - 0.26 * t), 0.010 * H),
            5,
            11,
            SAC_DK,
        );
    }
    // …and the FULL tone showing between them, which is what the belly reads as when it has drunk.
    if (seg == 0) b.addBlob(v3(0, -0.005 * H, -0.095 * H), v3(0.043 * H, 0.039 * H, 0.062 * H), 6, 12, SAC_FULL);
    // The blunt snap at the end — a rounded cap, never a taper to nothing.
    if (seg == 1) b.addBlob(v3(0, -0.012 * H, -len * H * 2.04), v3(0.022 * H, 0.021 * H, 0.020 * H), 5, 10, SAC_DK);
    return b.toMesh();
}

/// THE HEAD — small, round, and mostly eye socket. The bulge is the eyes' own mesh; this is what they sit in.
fn headMesh() rl.Mesh {
    var b = Builder.init();
    b.addBlob(v3(0, 0, 0), v3(0.062 * H, 0.058 * H, 0.058 * H), 7, 12, CHITIN);
    b.addBlob(v3(0, 0.026 * H, -0.010 * H), v3(0.044 * H, 0.032 * H, 0.040 * H), 5, 10, CHITIN_LT);
    // The two ANTENNAE, off the brow and swept back — thin, kinked, and never straight.
    for ([_]f32{ 1, -1 }) |s| {
        const a0 = v3(s * 0.030 * H, 0.044 * H, 0.026 * H);
        const a1 = v3(s * 0.062 * H, 0.086 * H, -0.020 * H);
        const a2 = v3(s * 0.070 * H, 0.108 * H, -0.076 * H);
        b.addCapsule(a0, a1, 0.0075 * H, 0.0055 * H, 6, CHITIN_DK);
        b.addCapsule(a1, a2, 0.0055 * H, 0.0030 * H, 6, CHITIN_DK);
        b.addBlob(a2, v3(0.005 * H, 0.005 * H, 0.005 * H), 4, 7, CHITIN_DK); // a blunt end, not a point
    }
    return b.toMesh();
}

/// THE PROBOSCIS. A tapered capsule and NOT a bare cylinder — a cylinder is capless and shows its own culled
/// interior at the tip, which on the sharpest thing in the creature's silhouette is the one place it shows.
fn probMesh() rl.Mesh {
    var b = Builder.init();
    const tip = v3(0, 0, PROB_LEN * H);
    b.addCapsule(v3(0, 0, 0), tip, 0.0125 * H, 0.0032 * H, 8, BEAK);
    // The sheath's two halves, splayed a hair off the shaft, which is what a mosquito's mouthparts do.
    for ([_]f32{ 1, -1 }) |s| {
        b.addCapsule(
            v3(s * 0.008 * H, -0.004 * H, 0.020 * H),
            v3(s * 0.014 * H, -0.010 * H, PROB_LEN * H * 0.72),
            0.0042 * H,
            0.0018 * H,
            6,
            BEAK_TIP,
        );
    }
    // A collar at the root, so the beak reads as fitted into the head and not stuck on it.
    b.addBlob(v3(0, 0, 0.010 * H), v3(0.018 * H, 0.017 * H, 0.012 * H), 5, 10, CHITIN_DK);
    return b.toMesh();
}

/// A BULGED EYE — a hemisphere's worth of blob standing proud of the head, faceted low so the sun catches
/// one plane at a time. The dark bead is the whole read at range; `drawFx` is what lights it.
fn eyeMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.addBlob(v3(0, 0, 0), v3(EYE_R * H, EYE_R * H * 1.18, EYE_R * H * 1.06), 6, 10, EYE);
    // The wet highlight, tiny and off-centre — it is what makes a bead look like an eye.
    b.addBlob(v3(side * 0.016 * H, 0.020 * H, 0.028 * H), v3(0.008 * H, 0.008 * H, 0.007 * H), 4, 8, rgba(104, 30, 26, 210));
    return b.toMesh();
}

/// A WING: a long membrane on a leading-edge spar, with ribs across it. Authored along +X for the LEFT and
/// mirrored by `side`, and drawn as a thin flattened blob rather than a quad so it has an edge you can see
/// when it is side-on — which, beating, is most frames.
fn wingMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    const span = 0.52 * H;
    const SEG = 10;
    // THE MEMBRANE IS ONE STRIP, and it has to be: built as a row of `addBox` slabs it was a STAIRCASE, each
    // block's end walls standing proud of its neighbour's. Drawn BOTH WAYS ROUND, since Builder winding is
    // unchecked, face-down geometry is culled, and a wing presents its underside half of every beat.
    //
    var prevF = v3(0, 0, 0); // leading edge
    var prevB = v3(0, 0, 0); // …and trailing
    var i: u32 = 0;
    while (i <= SEG) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / SEG;
        // The outline: a chord that swells over the inner third and tapers to a rounded tip, on a leading
        // edge that itself rakes back. A rectangle here is a paddle and an ellipse is a leaf.
        const chord = 0.135 * H * @sqrt(mathx.clampF(1.0 - t * t * t * 0.98, 0, 1)) * (0.42 + 0.58 * @min(1.0, t * 4.0));
        const rake = -span * 0.26 * t * t;
        const f = v3(side * span * t, 0, rake);
        const bk = v3(side * span * t, -0.0015 * H * t, rake - chord);
        if (i > 0) {
            b.quad(prevF, f, bk, prevB, v3(0, 1, 0), WING);
            b.quad(prevB, bk, f, prevF, v3(0, -1, 0), WING);
        }
        prevF = f;
        prevB = bk;
    }
    // The leading-edge SPAR, which is the only part of a wing that is not see-through, and the thing the
    // whole membrane visibly hangs off when it is edge-on.
    b.addCapsule(v3(0, 0, 0), v3(side * span, 0, -span * 0.26), 0.0095 * H, 0.0030 * H, 6, WING_RIB);
    // …and the VEINS raking back off it, uneven — a wing's ribs are not a comb.
    var rng = mathx.Rng.init(0x711E6);
    var k: u32 = 0;
    while (k < 4) : (k += 1) {
        const t = 0.16 + 0.22 * @as(f32, @floatFromInt(k)) * rng.range(0.92, 1.08);
        const chord = 0.135 * H * @sqrt(mathx.clampF(1.0 - t * t * t * 0.98, 0, 1)) * (0.42 + 0.58 * @min(1.0, t * 4.0));
        const rake = -span * 0.26 * t * t;
        b.addCapsule(
            v3(side * span * t, 0, rake),
            v3(side * span * (t + 0.26), -0.0010 * H, rake - chord * 0.92),
            0.0032 * H,
            0.0014 * H,
            5,
            WING_RIB,
        );
    }
    return b.toMesh();
}

/// A LEG: femur out and down, tibia kinked back under, and a blunt tarsus. The KINK is here rather than in
/// the rig — a leg drawn as one capsule to a needle tip is a spear, and six of them a rosette of spokes.
fn legMesh(i: usize) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x1E60 + @as(u64, i));
    const side = legSide(i);
    const pair = legPair(i);
    const len = (0.150 + 0.026 * @as(f32, @floatFromInt(pair))) * H * rng.range(0.94, 1.06);
    const knee = v3(side * len * 0.62, -len * 0.44, -len * 0.16 * rng.range(0.7, 1.3));
    const foot = v3(side * len * 0.74, -len * 1.06, -len * 0.52 * rng.range(0.8, 1.2));
    b.addCapsule(v3(0, 0, 0), knee, 0.0105 * H, 0.0075 * H, 6, LEG);
    b.addCapsule(knee, foot, 0.0075 * H, 0.0035 * H, 6, LEG);
    b.addBlob(knee, v3(0.011 * H, 0.011 * H, 0.011 * H), 4, 8, CHITIN_DK); // the joint, so the kink has a hinge
    b.addBlob(foot, v3(0.006 * H, 0.006 * H, 0.006 * H), 4, 7, CHITIN_DK); // …and a blunt end
    return b.toMesh();
}


const CAP = wf.MAX_PER_KIND;

/// THE SWARM. Wrapped for the standard's reason (`foe.zig`): a group is what the game targets, spawns,
/// draws and rolls up, and a seventh hand-written call site is the one that gets forgotten.
pub const Swarm = struct {
    model: Model,
    flies: [CAP]Leechfly = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Swarm {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Swarm) []Leechfly {
        return self.flies[0..self.n];
    }
    pub fn liveConst(self: *const Swarm) []const Leechfly {
        return self.flies[0..self.n];
    }
    pub fn reset(self: *Swarm, m: *const wf.Map) void {
        foe.resetGroup(Leechfly, &self.flies, &self.n, m, .leechfly);
    }
    pub fn setShader(self: *Swarm, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Swarm, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Swarm) void {
        for (self.liveConst()) |*f| f.drawFx();
    }

    /// `sip` takes THIS FRAME'S swallow, a hold and not a blow — it goes to `hero.burn`, where the stab goes
    /// back as a `foe.Blow`. Two channels because they are two things, and the shield answers only one.
    pub fn update(
        self: *Swarm,
        dt: f32,
        hero: rl.Vector3,
        bounds: f32,
        blade: foe.Blade,
        ctx: anytype,
        comptime sip: fn (@TypeOf(ctx), combat.Hit) void,
    ) ?foe.Blow {
        var blow: ?foe.Blow = null;
        for (self.live()) |*f| {
            switch (f.update(dt, hero, bounds, blade)) {
                .none => {},
                .stab => |h| foe.worseBlow(&blow, h, f.pos),
                .drink => |h| sip(ctx, h),
            }
        }
        return blow;
    }

    // The shared group roll-ups (foe.zig) — one-line delegates, the standard's own rule.
    pub fn pierce(self: *Swarm, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Swarm) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn runesDropped(self: *const Swarm) u32 {
        return foe.runesDropped(self.liveConst(), RUNES);
    }
    pub fn totalHits(self: *const Swarm) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Swarm) u32 {
        return foe.aliveCount(self.liveConst());
    }
};


test "IT CLIMBS OUT OF SWORD REACH AND NOT OUT OF THE WORLD" {
    // The whole design in one assertion: perched, its body is above anything the hero's arm sweeps, and it
    // is still inside the bow's world — the climb takes the sword off the table and hands you the ranged kit.
    try std.testing.expect(HOVER_HIGH > 3.4); // clear of a swing off a 1.8 m man's shoulder
    try std.testing.expect(HOVER_HIGH < AGGRO_R); // …and not somewhere it has stopped being a fight
    try std.testing.expect(HOVER_LOW < HOVER_HIGH);

    var f = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    f.hover = HOVER_LOW;
    const low = f.centerWorld().y;
    f.hover = HOVER_HIGH;
    // THE HURT SPHERE WENT WITH IT — the thing a height stored anywhere but on the accessors would quietly
    // not do: the blade tests `centerWorld`, so a climb would be a cosmetic hop still swingable at.
    try std.testing.expect(f.centerWorld().y > low + 3.0);
    // …and it is above the arc of a blade swung off a 1.8 m man's shoulder.
    try std.testing.expect(f.centerWorld().y - f.hurtRadius() > 2.6);
}

test "the climb is a LEAP, so the roots refuse it" {
    // A climb does not travel, it leaves the earth — `foe.canLeap`'s own rule, and it is what makes the
    // wand the answer to a thing that will not come down.
    try std.testing.expect(wantsClimb(1.0, 0, false, .stalk, false)); // threatened, free: it goes
    try std.testing.expect(!wantsClimb(1.0, 0, false, .stalk, true)); // …held down, it cannot
    try std.testing.expect(!wantsClimb(1.0, 1.0, false, .stalk, false)); // …nor on its cooldown
    // A BLOW REACHES ANY RANGE, the shade's `spooked` rule: hit it and back off, it still goes up.
    try std.testing.expect(wantsClimb(AGGRO_R, 0, true, .stalk, false));
    // …but never out of a committed move, and never out of the flinch it would erase.
    for ([_]State{ .wind, .stab, .drink, .stunlight, .stunheavy, .dead, .climb, .perch, .dive }) |s| {
        try std.testing.expect(!wantsClimb(0.5, 0, true, s, false));
    }
}

test "THE FEED IS A BLOW AND THEN A HOLD, and the hold cannot reach from the sky" {
    // The stab is a real blow — it has weight, so a shield has something to bill and a roll something to beat.
    try std.testing.expect(STAB_HIT.raw() > 0 and STAB_HIT.poise > 0);
    // …and the swallow is per SECOND, which is the only honest way to write a hold.
    try std.testing.expect(DRINK_DPS > 0);
    try std.testing.expect(LEECH_SHARE > 0 and LEECH_SHARE < 1); // SOME of it, not all

    var f = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, STAB_R * 0.5);
    f.hover = HOVER_LOW;
    f.facing = 0; // looking down +Z, straight at him
    f.pose();
    try std.testing.expect(f.holds(hero));
    // PERCHED, IT HOLDS NOTHING. On XZ alone the distance says it is on top of him.
    f.hover = HOVER_HIGH;
    try std.testing.expect(!f.holds(hero));
    // …and nothing behind it is under the beak either (the ogre's law: a move tests its own band).
    f.hover = HOVER_LOW;
    try std.testing.expect(!f.holds(v3(0, 0, -STAB_R * 0.5)));
}

test "it drinks itself well, and only up to full" {
    var f = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    f.vit.hp = 10.0;
    const before = f.vit.hp;
    _ = f.sip(0.5);
    try std.testing.expect(f.vit.hp > before);
    try std.testing.expectApproxEqAbs(DRINK_DPS * 0.5 * LEECH_SHARE, f.vit.hp - before, 1e-3);
    // A belly fills as it goes, and it is what the abdomen is drawn off.
    try std.testing.expect(f.gorge > 0);
    // …and a full one cannot overfill.
    f.vit.hp = f.vit.hpMax;
    var k: u32 = 0;
    while (k < 20) : (k += 1) _ = f.sip(0.1);
    try std.testing.expectApproxEqAbs(f.vit.hpMax, f.vit.hp, 1e-4);
}

test "no attack comes out of nowhere" {
    try std.testing.expect(WIND_DUR >= foe.TELL_MIN);
}

test "the bands never leave a gap the decision falls through" {
    // Every range from nose to notice ring answers something, and outside it nothing.
    var d: f32 = 0;
    while (d <= AGGRO_R) : (d += 0.25) {
        _ = classify(d, true);
        _ = classify(d, false);
    }
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 0.1, true));
    try std.testing.expectEqual(Choice.feed, classify(STAB_R * 0.5, true));
    try std.testing.expectEqual(Choice.circle, classify(STAB_R * 0.5, false)); // on cooldown it waits, in close
    try std.testing.expectEqual(Choice.close, classify(AGGRO_R - 0.1, true));
}

test "THE MARK RIDES THE HEAD, four metres up as readily as one" {
    var f = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    f.hover = HOVER_LOW;
    f.pose();
    const low = f.lockPoint();
    f.hover = HOVER_HIGH;
    f.pose();
    const high = f.lockPoint();
    try std.testing.expect(high.y - low.y > 2.5);
    // …and it is on the HEAD, so the lunge moves it too — a fixed mark would sit still through the strike.
    f.lunge = 0;
    f.pose();
    const tucked = f.lockPoint();
    f.lunge = 1;
    f.pose();
    const thrown = f.lockPoint();
    try std.testing.expect(mathx.distXZ(tucked, thrown) > 0.01 or @abs(thrown.y - tucked.y) > 0.01);
}

test "the beak the feed is measured from IS the beak the mesh draws" {
    // `PROB_LEN` is read by both, so a retune of the model cannot leave the reach pointing at thin air.
    var f = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.3);
    f.hover = HOVER_LOW;
    f.facing = 0;
    f.lunge = 1;
    f.pose();
    const tip = f.beakWorld();
    const head = foe.markOn(f.xf[HEAD], mathx.zero3);
    try std.testing.expect(tip.z > head.z); // out in FRONT of the head at full reach
    try std.testing.expect(mathx.lenV(mathx.subV(tip, head)) > PROB_LEN * H * 0.5);
}

test "THE WHINE IS PHRASED, and the silence is most of it" {
    // Owner's rule, and the numbers are the rule: a fly you can hear all the time is a drill. Every hush
    // outlasts every phrase, so however the two roll there is more quiet than note.
    try std.testing.expect(HUSH_MIN > PHRASE_MAX);
    // …and a phrase is long enough to be a note rather than a blip — at least two overlapping takes.
    try std.testing.expect(PHRASE_MIN >= WHINE_EVERY);

    // A fresh swarm does not whine in chorus: the same seed that varies the wingbeat varies the schedule,
    // so five posted together are five insects and not one heard five times.
    const a = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.10);
    const b = Leechfly.spawn(mathx.zero3, 0, 1.0, 0.80);
    try std.testing.expect(@abs(a.whineT - b.whineT) > 0.5);
    try std.testing.expect(a.whineT > 0 and b.whineT > 0); // …and none of them opens on a note
}
