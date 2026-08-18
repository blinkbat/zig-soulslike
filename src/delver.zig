const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");
const heromod = @import("hero.zig"); // …only for the SPEEDS its own chase is bracketed against, in tests

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

// THE DELVER — the first thing that goes UNDER the world.
const HIDE = rgba(8, 8, 11, 255); // the big smooth back — the biggest face on it, so the darkest
const HIDE_LO = rgba(12, 11, 15, 255); // belly and flanks
const PLATE = rgba(17, 16, 21, 255); // the sunk dorsal plates
const CLAW = rgba(44, 40, 32, 255); // horn: SMALL and proud, so it is the one thing here allowed to run pale
/// …AND THE WORN TIPS, paler still. The claws are the one part of this animal the eye is meant to find first
/// and the ends of them are what it finds: bone-dry horn, polished by the ground it digs.
const CLAW_LT = rgba(96, 88, 70, 255);
const SNOUT = rgba(20, 17, 14, 255);
const EYE = rgba(70, 66, 54, 255); // tiny and milky — it does not live by them
const SOIL = rgba(24, 19, 14, 255); // the mound MESH — an albedo, so it is authored near-black like the rest
const SOIL_DK = rgba(15, 12, 9, 255);
/// …AND THE CLODS IT THROWS, WHICH ARE NOT THE SAME NUMBERS. Particles go through `drawSphereEx` unlit, so a
/// particle colour is a LITERAL SCREEN VALUE (`foe.DUST`'s own, 150,132,96) where a mesh colour is an albedo.
const CLOD = rgba(148, 120, 84, 220);
const CLOD_DK = rgba(106, 84, 58, 210);

/// Its stature REARED, crown off the ground. On all fours its back is barely over the hero's knee.
pub const H: f32 = 1.55;

pub const AGGRO_R: f32 = 14.0;
const HOME_R: f32 = 2.5;

const BODY_R: f32 = 0.62;
const HURT_R: f32 = 0.95;
const CENTER_F: f32 = 0.42; // of H
/// Half the body's own length, which is the lever a root pitch swings its ends through (see `pose`).
const BODY_HALF: f32 = 0.80;
const TOP_F: f32 = 0.66; // standing crown, not the reared one — this is what a bar hangs off

const HP_MAX: f32 = 118.0;
const POISE_MAX: f32 = 26.0; // three hero lights to flinch it: a plated back shrugs one off
const STANCE_MAX: f32 = 58.0;
/// PACKED EARTH OVER A DAMP HIDE. Fire smoulders on wet clay; a digger stiffens in the cold, and a bolt
/// EARTHS straight through the one creature in the world that is part of the ground.
const RESISTS = combat.resists(.{ .fire = 20, .cold = -30, .lightning = -40 });
pub const SOULS: u32 = 155;

/// The surfaced stroke — one forelimb round in a flat arc. Ordinary, parryable, and not why you are here.
pub const CLAW_HIT = combat.Hit{ .dmg = 15, .poise = 20, .stance = 6 };
/// …AND THE BURST, which is. The heaviest thing it has, under the ogre's slam because the tell is long and
/// the counter is your feet.
pub const BURST_HIT = combat.Hit{ .dmg = 28, .poise = 42, .stance = 18 };
/// HOW FAR ROUND THE HOLE IT REACHES — the whole of the "small AOE" (owner's call). A radius and not a swept
/// limb: what arrives is the ground opening, and the ground has no edge to sweep.
pub const BURST_R: f32 = 1.9;

const WALK_SPEED: f32 = 2.2;
/// …and what it moves at once it has SEEN him, which is the difference between a creature crossing a field
/// and a creature coming for you. Under the hero's sprint — you can still break away — and over his run, so
/// backing off is a decision that costs ground rather than a free reset.
const CHASE_SPEED: f32 = 3.9;
/// It turns HARD on the surface: a burrower's whole body is a shoulder, and out of the ground the one thing
/// it should not be is easy to walk around.
const TURN_RATE: f32 = 4.2;
/// WHAT THE POSED CLAW ACTUALLY REACHES off the creature's own axis. **MEASURED, NOT ARGUED** — a test walks
/// the stroke frame by frame and brackets this from both sides, which is what caught the first pass declaring
/// 2.9 m off a limb that arrived at 1.19.
const CLAW_REACH: f32 = 1.75;
/// …and the fatness the swept test carries, which is the other half of what the stroke covers.
const CLAW_SWEEP_R: f32 = 0.34;
/// **THE DECISION IS TAKEN AT THE RANGE THE BLOW LANDS AT**, never at a number beside it, or it spends half a
/// second on a guaranteed miss (the ogre's swipe-inner lesson).
const CLAW_BAND: f32 = CLAW_REACH + CLAW_SWEEP_R;
const CLAW_KEEP: f32 = CLAW_BAND - 0.5; // …and inside this it stops closing
pub const CLAW_WIND: f32 = 0.48; // >= foe.TELL_MIN, and the shoulder travels the whole of it
const CLAW_STRIKE: f32 = 0.20;
/// **AND IT IS VICIOUS ON ITS FEET, NOT ONLY UNDER THEM** (owner: more vicious even when not underground).
/// The surface kit was a courtesy — one stroke every 1.9 s off a body that walked at 2.2 m/s, so a delver
/// caught above ground was a punching bag between dives and the whole creature lived in the burrow. The
/// recovery is shorter, the cooldown is most of a second off, and it CLOSES rather than ambling: the thing
/// that goes under the world is not supposed to be safe to stand next to when it comes out of it.
const CLAW_RECOVER: f32 = 0.40;
const CLAW_CD: f32 = 1.05;

// THE DIVE, AND EVERYTHING UNDER IT.
pub const DIVE_WIND: f32 = 0.62; // reared right up on its hind legs, forelimbs overhead: its biggest silhouette
const DIVE_DUR: f32 = 0.42; // …and it drills, nose first
/// **IT STAYS DOWN** (owner's call). It may not surge until it has been under this long, whatever it finds
/// on the way — a burrower that pops straight back up is a creature with a dodge, not a creature with a
/// burrow.
const UNDER_MIN: f32 = 2.6;
/// …and never longer than this, or a player who keeps walking is fighting nothing at all.
const UNDER_MAX: f32 = 7.0;
const UNDER_SPEED: f32 = 4.8; // faster than its walk: closing the ground is what being under BUYS it
const UNDER_TURN: f32 = 2.6; // …and it corners worse, because it is ploughing
/// HOW FAR UNDER THE GROUND ITS BODY RIDES. See the comptime assert below: this number is what makes it
/// unhittable while it is down, and nothing else does.
pub const UNDER_DEPTH: f32 = 2.6;
const SURGE_LOCK_R: f32 = 1.0; // it wants to be UNDER him before it commits
/// THE MOUND'S TWO SIZES, NAMED ONCE. Written out at each of the three sites that set them they were the same
/// four literals in three places, and the swell's start had to agree with the travelling ridge's rest or the
/// dome jumped on the frame the mound stopped.
const MOUND_TRAVEL_R: f32 = 1.05;
const MOUND_TRAVEL_H: f32 = 0.28;

/// **THE TELL IS THROWN EARTH, NOT A SWELLING DOME** (owner: instead of distending the bump, steadily add
/// particles until he jumps out). The dome grew to `BURST_R * 0.86` and stood there — a mound inflating is a
/// slow, soft read at exactly the moment the read has to be urgent, and a shape held for over a second stops
/// being motion at all. What replaces it is a spray that BUILDS: a few clods at the commit, a fountain by the
/// end, so the ground comes apart harder every frame and the eye is pulled by CHANGE rather than by size.
/// The disc the blow lands on is still exactly `BURST_R` — the picture has simply stopped lying about it by
/// being smaller than the thing it announces.
///
/// The mound itself HOLDS at its travelling size right to the burst, which is what keeps the spot honest: the
/// ridge stopped there, and that is where it comes out.
const MOUND_SWELL_R: f32 = MOUND_TRAVEL_R;
const MOUND_SWELL_H: f32 = MOUND_TRAVEL_H;
/// Clods a second at the START of the tell and at its END.
const SURGE_SPRAY_0: f32 = 14.0;
const SURGE_SPRAY_1: f32 = 190.0;
/// …and the CURVE it builds along. Over 1 so most of the growth is LATE: a linear ramp spends its first half
/// at a rate the player reads as ambient churn and then has nowhere left to go.
const SURGE_SPRAY_CURVE: f32 = 2.4;
/// How much harder the clods are thrown by the end. Rate alone is more of the same; the earth has to go UP.
const SURGE_SPRAY_LIFT: f32 = 2.6;
/// THE TELL, AND IT IS THE LONGEST THING IT DOES. The mound STOPS, the earth domes up over the spot and
/// throws dirt; the blow lands where it stopped. Bracketed from below by its own dive wind, because the one
/// move that arrives from a direction the camera cannot be turned toward may not be the one you get least
/// warning of (the Bone Knight's fall, one creature along) — and bracketed again by what it costs to get out
/// of the ring, which is the assert below. It is on TOP of a mound that has been visible the whole way in:
/// this is the final commit, not the whole warning.
pub const SURGE_DUR: f32 = 1.15;
pub const BURST_RISE: f32 = 0.28; // it comes up out of the hole
const BURST_RECOVER: f32 = 0.95; // …and stands there half-buried, shaking soil off: the punish window
const DIVE_CD: f32 = 6.5;
/// **THE CHURN IS A RETRIGGER, NOT A LOOP** (the leechfly's whine idiom — raylib cannot loop a synthesized
/// take), and the voice is cut a hair longer than this so consecutive ones overlap. It is what a player
/// looking the wrong way has instead of the mound, so it is the one thing about this creature that reaches
/// further than it can see.
pub const CHURN_EVERY: f32 = 0.72;
/// The stride the limb phase is measured in — one number, read by the surface walk and by the swim under it.
const STRIDE: f32 = 0.92;

comptime {
    // **SUBMERGED IT CANNOT BE STRUCK, AND THAT IS GEOMETRY RATHER THAN A GUARD IN `tryHit`.** Its hurt
    // sphere is measured off `pos.y` like everything else's (`foe.bodyPoint`, with the depth as a NEGATIVE
    // lift), so at `UNDER_DEPTH` the top of it sits this far under the ground he is standing on — further
    // than any blade of his reaches below his own boots, and the swept test then refuses it on its own.
    // A creature that needed a special case here would need one at every future site that swings anything.
    //
    // **AND IT HOLDS AT EVERY SCALE THE MAP CAN POST, which is why this may be written in bare constants.**
    // `depth` is in SCALE-1 METRES and `ride()` is what multiplies it (`-depth * scale`), so every term below
    // is the same multiple of `scale` and the whole inequality is scale-invariant. Read the other way — depth
    // as world metres — it looks like a check that only pins scale 1, and "fixing" that by scaling `depth`
    // at its writers double-scales the burrow and surfaces a small delver. The test below is the pin.
    std.debug.assert(UNDER_DEPTH - CENTER_F * H - HURT_R > 0.8);
    // …and the whole of it is a state the hero is warned into: the surge outlasts the dive's own wind.
    std.debug.assert(SURGE_DUR > DIVE_WIND and DIVE_WIND >= foe.TELL_MIN and CLAW_WIND >= foe.TELL_MIN);
    // A COMMITTED SPOT HE CAN GET OFF, and the price of standing still. He starts at the CENTRE — it came
    // up under him — so what he has to clear is the whole radius plus his own footprint. A RUN does it with
    // room to spare and a ROLL does it outright; a WALK covers 1.96 m of the 2.26 and is deliberately not
    // enough, or the move is a tax on being anywhere rather than a thing you answer. The hero's own figures
    // are written out here rather than imported for `foe.HERO_*`'s reason: this file sits below `hero.zig`.
    std.debug.assert(SURGE_DUR * 3.4 > BURST_R + foe.HERO_R); // RUN_SPEED
    std.debug.assert(SURGE_DUR > 0.70 + 0.30); // ROLL_DUR, plus a beat to read the mound and press it
}

// THE PLOUGH — the burrow's OTHER way out, and the answer to a player who simply keeps walking.
pub const PLOUGH_HIT = combat.Hit{ .dmg = 20, .poise = 30, .stance = 12 };
/// How wide the furrow bites either side of the line it runs.
pub const PLOUGH_R: f32 = 1.15;
/// THE TELL, AND IT IS A DIFFERENT PICTURE FROM THE SURGE'S: the ridge STRAIGHTENS AND STRETCHES instead of
/// stopping and doming. Shorter than `SURGE_DUR` on purpose — the ground it threatens is a line you step off
/// rather than a circle you have to clear — and still well past `foe.TELL_MIN`.
pub const PLOUGH_WIND: f32 = 0.55;
const PLOUGH_DUR: f32 = 0.85; // …and the run itself
const PLOUGH_SPEED: f32 = 9.2; // near twice its swim: this is the charge, and it is the fastest thing it does
/// THE BAND IT COMMITS FROM. Outside the burst's own lock ring, so the two moves can never both be on the
/// table, and inside what the run can actually cover — a charge that stops short is a charge you walk out of.
const PLOUGH_R_MIN: f32 = 3.0;
const PLOUGH_R_MAX: f32 = PLOUGH_SPEED * PLOUGH_DUR * 0.8;
/// …and how far off its nose he may be when it commits. It is ploughing, not steering.
const PLOUGH_ARC: f32 = 38.0;
/// **THE RIDGE STRETCHES, IT DOES NOT SWELL — that IS the tell, and it is the whole reason the two exits can
/// be told apart.** The mound's matrix scales X and Z together off `moundR`, so a plough that only raised
/// that number drew the surge's own dome a little bigger: two moves, one picture, and no read at all. The
/// stretch is a separate factor applied along the mesh's own +Z, which `ry(facing)` has already turned onto
/// the heading — so the heap gets LONGER down the line it is about to run and barely wider.
const MOUND_PLOUGH_R: f32 = MOUND_TRAVEL_R * 1.1;
const MOUND_PLOUGH_H: f32 = MOUND_TRAVEL_H * 1.45;
const MOUND_PLOUGH_LONG: f32 = 2.8;

// THE RAKE — the backhand the claw comes back on.
pub const RAKE_HIT = combat.Hit{ .dmg = 12, .poise = 16, .stance = 5 };
/// **AND IT IS STILL LONG ENOUGH TO BE CAUGHT ON, WHICH IS WHAT SIZES IT FROM BELOW.** It carries a parry
/// window like the opener does, and `foe.PARRY_LEAD` brackets every wind in the game from above (the toad's
/// `LUNGE_COIL` and the brood's `BITE_WINDUP` were both pushed up for exactly this). At 0.33 the game's one
/// difficulty dial covered 55% of this tell against under half of the claw's beside it — the same move twice
/// at two difficulties, and nothing pinned it.
pub const RAKE_WIND: f32 = 0.40;
const RAKE_STRIKE: f32 = 0.18;
/// …and it is a ROLL, not a guarantee. A creature whose combo always comes is one you answer by rote.
const RAKE_CHANCE: f32 = 0.55;

comptime {
    // Every wind in the creature clears the no-attack-from-nowhere floor, the new pair included.
    std.debug.assert(PLOUGH_WIND >= foe.TELL_MIN and RAKE_WIND >= foe.TELL_MIN);
    // …and the RETURN is the quick one, or there is no reason to have thrown it.
    std.debug.assert(RAKE_WIND < CLAW_WIND);
    // …AND BOTH PARRYABLE STROKES ARE BRACKETED BY THE ONE DIAL, not just the opener: a window worth more than
    // half the tell in front of it is the same move at a second difficulty.
    std.debug.assert(foe.PARRY_LEAD < RAKE_WIND * 0.5 and foe.PARRY_LEAD < CLAW_WIND * 0.5);
    // THE TWO BURROW EXITS ANSWER TWO RANGES AND MAY NOT OVERLAP: inside the lock ring it is the burst's, and
    // the plough only exists out past it.
    std.debug.assert(PLOUGH_R_MIN > SURGE_LOCK_R and PLOUGH_R_MAX > PLOUGH_R_MIN);
    // …and THE BURST STAYS THE HEAVY ONE. `game.zig` sizes the shake and the pad off `hit.stance >=
    // BURST_HIT.stance`, so a plough that matched it would be felt as the ground opening under him.
    std.debug.assert(PLOUGH_HIT.stance < BURST_HIT.stance and RAKE_HIT.stance < BURST_HIT.stance);
    // …and the return is the lighter half of the pair it belongs to.
    std.debug.assert(RAKE_HIT.dmg < CLAW_HIT.dmg);
}

const DEATH_DUR: f32 = 1.15;
const DISS_DUR: f32 = 1.05;
const SHOVE_DECAY: f32 = 7.0;
const DISSOLVE = foe.Dissolve{ .rate = 58.0, .spread = 0.9, .rise = 0.75, .flake = CLOD };

/// Sized by ARITHMETIC over the worst frame (the ring law), and the worst frame is the PLOUGH'S LAST one, not
/// the burst's: the furrow can land its blow on the same frame the run ends, so the 12-clod hit burst and the
/// 40 of `burstDirt` go in together — on top of what the run itself left resident, which is `emitWake` at 22/s
/// and `emitSpray` at 24/s against lives of 0.3-0.7 s, about 22. That is 74 against the 72 this used to be,
/// and a ring that overwrites its oldest does it SILENTLY. 96 clears it with room for the shove's dust.
const PARTS = 96;

// The rig — ten bones of digger. Not the humanoid scaffold: it has no waist to hinge at and its forelimbs
// are the only thing on it that reaches.
const N = 10;
const BODY = 0;
const HEAD = 1;
const ARML = 2;
const ARMR = 3;
const CLAWL = 4;
const CLAWR = 5;
const HINDL = 6;
const HINDR = 7;
const TAIL = 8;
/// THE MOUND IS NOT PART OF THE BODY. It is the ground the body is under, so it hangs off nothing: its
/// matrix is built in WORLD space at the surface, and it is the only thing you can see while it is down.
const MOUND = 9;

const REST = [N]rl.Vector3{
    v3(0, 0, 0),
    v3(0, 0.30 * H, 0.66),
    v3(0.34, 0.26 * H, 0.34),
    v3(-0.34, 0.26 * H, 0.34),
    v3(0.12, -0.14, 0.44),
    v3(-0.12, -0.14, 0.44),
    v3(0.30, 0.21 * H, -0.48),
    v3(-0.30, 0.21 * H, -0.48),
    v3(0, 0.26 * H, -0.82),
    v3(0, 0, 0),
};

/// The far end of the middle digging claw, in the claw bone's own frame — what the stroke actually swings,
/// and what `parryable` hands over as its reach. MEASURED off the mesh, never argued (the ogre's club law).
const CLAW_TIP = v3(0, -0.16, 0.78);

const State = enum { idle, walk, claw, rake, recover, dive, under, surge, plough, burst, heave, stunlight, stunheavy, dead };

/// PURE DECISION. `rooted` refuses the dive alone: the claw is a swing and a creature held by the ankles may
/// still swing.
const Choice = enum { rest, wait, walk, claw, dive };
fn classify(dist: f32, clawReady: bool, diveReady: bool, rooted: bool) Choice {
    if (dist > AGGRO_R) return .rest;
    // It would rather go under than trade: the burrow is the creature, and the claw is what it does while
    // the burrow is cooling.
    if (diveReady and !rooted) return .dive;
    if (dist <= CLAW_BAND and clawReady) return .claw;
    if (dist > CLAW_KEEP) return .walk;
    return .wait;
}

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("delver material");
        mat.shader = shader;
        return .{ .mesh = buildMeshes(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    /// The one draw that skips bones, and both halves earn it: a MOUND on a creature standing in the open is
    /// a heap of earth following it about, and a BODY drawn two and a half metres under the terrain is a
    /// shadow cast onto the ground it is beneath. Asked here rather than in `pose`, so both passes agree.
    pub fn draw(self: *const Model, d: *const Delver) void {
        const buried = d.deep();
        for (0..N) |i| {
            if (i == MOUND) {
                if (!d.mounded()) continue;
            } else if (buried) continue;
            rl.drawMesh(self.mesh[i], self.mat, d.xf[i]);
        }
    }
};

pub const Delver = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// THE WAND'S ROOTS, stamped from outside like every creature's — and the one thing they take from this
    /// creature is the ground under it.
    root: combat.Root = .{},
    /// THE RIME BREATH'S COLD (`combat.Chill`) — stamped from outside like the roots, and billed through the
    /// same `foe.grip`. Submerged there is nothing to breathe on: the cone is tested against a body the
    /// hurt sphere has already sunk out of reach of.
    chill: combat.Chill = .{},
    /// …AND THE HERO'S SHIELD (`game.markParry`), read only inside the claw's own window.
    parry: foe.Parry = .{},
    /// The boards caught the claw this frame — a ONE-FRAME flag, `justDied`'s exactly.
    parried: bool = false,
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    idleWait: f32 = 0.3,
    clawCd: f32 = 0,
    diveCd: f32 = 0,
    heroLatch: bool = false,
    /// The return has already been thrown off THIS stroke — one backhand per gather, never a mill.
    raked: bool = false,
    homing: bool = false,
    /// It went under this frame, and it broke the surface this frame — one-frame edges the GROUP reads, which
    /// is what lets the game put a shake and a low rumble under a tell arriving from off screen.
    surged: bool = false,

    /// HOW FAR UNDER ITS OWN GROUND THE BODY IS RIDING, metres. 0 at the surface; every world point on it is
    /// measured with this as a NEGATIVE lift, so the whole creature goes down together and nothing has to be
    /// told about it twice.
    depth: f32 = 0,
    moundR: f32 = 0,
    moundH: f32 = 0,
    /// **HOW FAR INTO THE SURGE'S BUILD IT IS**, 0..1 — read by `emitSpray` so the clods are thrown harder as
    /// well as thicker. A field rather than a second clock: the shape is `updateSurge`'s alone.
    surgeK: f32 = 0,
    /// …and how far the heap is drawn OUT ALONG ITS HEADING, as a multiple of its width. 1 is the round
    /// travelling mound and the surge's dome; the plough is the only thing that moves it (`MOUND_PLOUGH_LONG`).
    moundLong: f32 = 1,
    churn: f32 = 0,

    // pose channels
    rear: f32 = 0, // 0 on all fours … 1 up on the hind legs, forelimbs overhead
    drill: f32 = 0, // nose-down pitch through the dive
    swing: f32 = 0, // -1..1, the forelimb round its arc
    crouch: f32 = 0,
    gait: f32 = 0, // limb phase, advanced by GROUND COVERED and never by time
    shudder: f32 = 0, // the surge's tremble, on the mound and on nothing else

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    justDied: bool = false,
    /// WHO IT IS FIGHTING (`foe.Threat`) — embedded here, stamped by the game.
    threat: foe.Threat = .{},
    /// …AND THE WAY ROUND WHAT IS IN THE WAY (`foe.Nav`). Only the SURFACE walk reads it: a thing under the
    /// ground goes under whatever the probe was going to steer it round, and `markWays` skips it on its own
    /// while it is down (`airborne`).
    nav: foe.Nav = .{},
    fade: f32 = 0,
    gone: bool = false,

    clawWas: [2]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** 2,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    aiRng: mathx.Rng = mathx.Rng.init(2),

    xf: [N]rl.Matrix = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Delver {
        var d = Delver{ .pos = home, .home = home, .facing = faceYaw, .scale = scale, .seed = seed };
        d.fxRng = foe.fxStream(seed, 51473.0, 0xD31E);
        d.aiRng = foe.fxStream(seed, 29399.0, 7);
        d.idleWait = 0.2 + seed * 0.5;
        d.diveCd = DIVE_CD * (0.25 + seed * 0.5); // no two of them go under on the same beat
        d.pose();
        d.clawWas = d.clawSeg();
        return d;
    }

    /// Every world point on it carries the depth as a negative lift, so a bar, a reticle and a hurt sphere
    /// all sink with the body rather than hanging in the air over the hole it went down.
    fn ride(self: *const Delver) f32 {
        return -self.depth * self.scale;
    }
    pub fn centerWorld(self: *const Delver) rl.Vector3 {
        return foe.bodyPoint(self.pos, CENTER_F * H, self.scale, self.ride());
    }
    /// THE MARK RIDES THE SKULL — it rears, it drills and it dips, and the mark goes with it.
    pub fn lockPoint(self: *const Delver) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0.06, 0.10));
    }
    pub fn topWorld(self: *const Delver) rl.Vector3 {
        return foe.bodyPoint(self.pos, TOP_F * H, self.scale, self.ride());
    }
    pub fn hurtRadius(self: *const Delver) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Delver) f32 {
        return BODY_R * self.scale;
    }
    pub fn alive(self: *const Delver) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Delver) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Delver) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    /// **IT IS UNDER THE WORLD'S TRAFFIC RATHER THAN OVER IT, AND THAT IS THE SAME ANSWER TO EVERY QUESTION
    /// THIS PREDICATE IS ACTUALLY ASKED.** `airborne` gates six things in `game.zig` and a submerged digger
    /// wants every one of them: no terrain riser rule (it is not walking on the surface), no shoulder from
    /// the hero or from another body, no steering (it goes UNDER what the probe would bend it round), no
    /// jaws from the wolf, and no spirit handed to it. It is NOT exempt from `env.resolveActor` — burrow
    /// through a wall and there is nowhere to come back up from — which is the leechfly's own trade.
    pub fn airborne(self: *const Delver) bool {
        return self.depth > foe.AIRBORNE_LIFT;
    }
    /// Deep enough that the body is inside the earth: nothing of it is drawn, and nothing of it can be hit.
    pub fn deep(self: *const Delver) bool {
        return self.depth >= UNDER_DEPTH - 1e-3;
    }
    /// …and whether there is a ridge of moving earth to see. THE ONLY THING VISIBLE while it is down.
    pub fn mounded(self: *const Delver) bool {
        return self.moundR > 1e-3;
    }
    /// **YOU CANNOT FIX ON WHAT IS UNDER THE GROUND** (owner's call) — the Rooted's `hidden` predicate, which
    /// `game.disguised` finds by `@hasDecl` and every targeting site already asks. A held lock DROPS the frame
    /// it goes under, the flick skips it, a fresh press cannot take it, no bar hangs over the hole and the
    /// wolf stops trying to bite two and a half metres of earth. Coming back up is a re-acquire, and that is
    /// the point of the move: the camera is yours again and it is your problem where the mound went.
    pub fn hidden(self: *const Delver) bool {
        return self.deep();
    }
    pub fn flashFrac(self: *const Delver) f32 {
        return foe.flashFrac(self.flash);
    }

    fn fdir(self: *const Delver) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn clawSeg(self: *const Delver) [2]rl.Vector3 {
        return .{ foe.markOn(self.xf[CLAWR], mathx.zero3), foe.markOn(self.xf[CLAWR], CLAW_TIP) };
    }
    /// WHERE IT IS TRYING TO WALK (`game.markWay`) — the surface walk and nothing else.
    pub fn navWant(self: *const Delver, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .walk and self.state != .idle) return null;
        if (self.airborne()) return null;
        if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) return hero;
        return if (mathx.distXZ(self.pos, self.home) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Delver, target: rl.Vector3, rate: f32, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, rate, dt);
    }

    /// Where it is actually going: him, or its own post — once the tether has let go, or once the decision
    /// itself was to walk home (`homing`). Both, or a creature told to go home walks at a hero forty metres
    /// off, which is the sporeling's own bug one file along.
    fn goingFor(self: *const Delver, hero: rl.Vector3) rl.Vector3 {
        return if (self.homing or self.leash.goingHome()) self.home else hero;
    }

    pub fn update(self: *Delver, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        self.parried = false;
        self.surged = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.clawCd = mathx.maxF(0, self.clawCd - dt);
        self.diveCd = mathx.maxF(0, self.diveCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        switch (self.state) {
            .idle => self.updateIdle(dt, hero),
            .walk => self.updateWalk(dt, hero, bounds),
            .claw => self.updateClaw(dt, hero),
            .rake => self.updateRake(dt, hero),
            .recover => {
                self.swing = mathx.approach(self.swing, 0, dt * 3.2);
                self.crouch = mathx.approach(self.crouch, 0.05, dt * 1.4);
                self.rear = mathx.approach(self.rear, 0, dt * 2.2);
                if (self.t >= CLAW_RECOVER) self.enterIdle(0.12);
            },
            // THE BURST'S OWN OPENING, and it is the longer of the two on purpose: what it pays for a move
            // with no window on it is the time you get afterwards. Half-buried, shaking soil off its back.
            .heave => {
                // **THE ONE TAIL BOTH WAYS OUT OF THE GROUND SHARE.** The burst arrives here already at the
                // surface (its own rise did that); the PLOUGH arrives here still buried at the end of its
                // furrow, so the depth is eased out here rather than in a second rise of its own — one place
                // that says "it is coming up", and `Model.draw` and the lock both key off the same number.
                self.depth = mathx.approach(self.depth, 0, dt * 9.0);
                const k = mathx.smoothstep(0, BURST_RECOVER, self.t);
                self.rear = lerpF(0.58, 0, k);
                self.swing = lerpF(0.45, 0, k) + 0.09 * mathx.sinf(self.t * 21.0) * (1.0 - k); // the shake-off
                self.crouch = lerpF(0.30, 0.05, k);
                if (self.t < BURST_RECOVER * 0.4) self.emitScuff(dt);
                if (self.t >= BURST_RECOVER) self.enterIdle(0.12);
            },
            .dive => self.updateDive(dt, hero),
            .under => self.updateUnder(dt, hero, bounds),
            .surge => self.updateSurge(dt),
            .plough => self.updatePlough(dt, hero, bounds),
            .burst => self.updateBurst(dt, hero),
            .stunlight, .stunheavy => {
                // KNOCKED BACK ONTO ITS HAUNCHES, forelimbs up and useless. It cannot be flinched while it is
                // under — nothing down there is taking a blow — so this is always a surfaced pose.
                self.rear = mathx.approach(self.rear, 0.34 * foe.stunCurve(self.t, self.state == .stunheavy), dt * 6.0);
                self.crouch = mathx.approach(self.crouch, 0.16, dt * 5.0);
                self.swing = mathx.approach(self.swing, 0, dt * 4.0);
                // **AND A BODY HALFWAY OUT OF THE GROUND IS NOT FLINCHED THE REST OF THE WAY INSTANTLY.** The
                // rise is the one window it CAN be hit in, so this is the common case, and `enterStun` zeroing
                // the depth teleported three quarters of a creature up out of the earth on one frame (the
                // knight's floored-body lesson, one creature down). It finishes coming up, quickly.
                self.depth = mathx.approach(self.depth, 0, dt * 5.0);
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enterIdle(0.14);
            },
            .dead => {
                self.rear = mathx.approach(self.rear, 0, dt * 3.0);
                self.crouch = mathx.approach(self.crouch, 0.62, dt * 1.6); // it settles onto its own belly
                self.drill = mathx.approach(self.drill, 12.0, dt * 40.0);
                self.depth = mathx.approach(self.depth, 0, dt * 3.4); // …coming up first if it died down there
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        self.settleMound(dt);
        self.pose();
        // The stroke is tested off the POSED claw, so the reach is whatever the animation actually did.
        const now = self.clawSeg();
        // WHICH BLOW THE LIMB IS CARRYING THIS FRAME, if any — one window per stroke, and the RETURN goes
        // through the same swept test off the same posed claw rather than a second copy of it.
        const swung: ?combat.Hit = switch (self.state) {
            .claw => if (self.t >= CLAW_WIND and self.t < CLAW_WIND + CLAW_STRIKE) CLAW_HIT else null,
            .rake => if (self.t >= RAKE_WIND and self.t < RAKE_WIND + RAKE_STRIKE) RAKE_HIT else null,
            else => null,
        };
        if (swung) |h| {
            if (!self.heroLatch and foe.weaponReaches(self.clawWas, now, hero, CLAW_SWEEP_R * self.scale)) {
                self.heroLatch = true;
                self.heroHit = h;
                self.leash.noteCombat();
            }
        }
        self.clawWas = now;
        self.takeParry();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn updateIdle(self: *Delver, dt: f32, hero: rl.Vector3) void {
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        if (d <= AGGRO_R) self.faceToward(self.goingFor(hero), TURN_RATE, dt);
        // Three clocks that never line up (the wanderer's law): a breath, a shoulder roll, a snout that casts
        // about. A digger standing still is still SMELLING for you.
        const br = mathx.sinf(self.elapsed * (1.5 + 0.3 * self.seed) + self.seed * 6.28);
        self.crouch = mathx.approach(self.crouch, 0.05 + 0.025 * br, dt * 3.0);
        self.rear = mathx.approach(self.rear, 0.04 + 0.03 * mathx.sinf(self.elapsed * 0.9 + self.seed * 4.0), dt * 2.0);
        self.swing = mathx.approach(self.swing, 0.06 * mathx.sinf(self.elapsed * 1.3 + self.seed * 11.0), dt * 2.0);
        self.drill = mathx.approach(self.drill, 0, dt * 60.0);
        if (self.t >= self.idleWait) self.decide(d);
    }

    fn updateWalk(self: *Delver, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const to = self.goingFor(hero);
        // It walks where it is LOOKING — a low four-limbed body does not strafe — so the way round is read
        // through `Nav.aim` (the ogre's reading, not the kobold's).
        self.faceToward(self.nav.aim(self.pos, to), TURN_RATE, dt);
        // **IT WALKS HOME AND IT RUNS AT HIM.** One speed for both was what made a surfaced delver something
        // you could simply stroll away from — and a creature whose whole threat is the ambush has to be able
        // to make you deal with it when the ambush is over.
        const moved = (if (self.homing) WALK_SPEED else CHASE_SPEED) * self.scale * dt;
        mathx.stepXZ(&self.pos, self.fdir(), moved, bounds);
        // PHASE OFF DISTANCE, never time, or the limbs skate the moment anything scales the speed.
        self.gait += moved / (STRIDE * self.scale);
        self.crouch = 0.10 + 0.035 * mathx.sinf(self.gait * std.math.tau * 2.0);
        self.rear = mathx.approach(self.rear, 0, dt * 3.0);
        self.swing = 0.24 * mathx.sinf(self.gait * std.math.tau);
        self.emitScuff(dt);
        if (self.homing and mathx.distXZ(self.pos, self.home) <= HOME_R) {
            self.homing = false;
            self.enterIdle(0.4);
            return;
        }
        if (self.t >= 0.22) self.decide(foe.senseHero(&self.leash, self.pos, hero, AGGRO_R));
    }

    fn updateClaw(self: *Delver, dt: f32, hero: rl.Vector3) void {
        if (self.t < CLAW_WIND) {
            self.faceToward(hero, TURN_RATE * 0.6, dt);
            // THE PICTURE OF THE GATHER IS THE TELL: the whole limb travels hard AWAY from where the stroke
            // takes it, and the body loads up behind it rather than standing still holding a pose.
            const u = mathx.smoothstep(0, CLAW_WIND, self.t);
            self.swing = lerpF(0, -1.0, u);
            self.rear = lerpF(0, 0.72, u); // it REARS to strike — a badger's rake, not a dog's snap
            self.crouch = lerpF(0.05, -0.10, u);
        } else if (self.t < CLAW_WIND + CLAW_STRIKE) {
            const u = (self.t - CLAW_WIND) / CLAW_STRIKE;
            self.swing = lerpF(-1.0, 1.0, foe.swingCurve(u)); // the one arc shape in the game
            self.rear = lerpF(0.72, 0.24, u); // …and comes DOWN through the stroke, which is where the weight is
            self.crouch = lerpF(-0.10, 0.16, u);
        } else if (self.wantsRake(hero)) {
            self.raked = true;
            self.heroLatch = false; // the return is its OWN blow, and one hit per stroke means per STROKE
            sfx.world(.delver_claw, self.pos);
            self.enter(.rake);
        } else {
            self.enter(.recover);
        }
    }

    /// **DOES THE STROKE COME BACK.** Rolled once per gather, and only while he is still standing in it — a
    /// backhand thrown at empty air is the creature announcing that the punish was free after all.
    fn wantsRake(self: *Delver, hero: rl.Vector3) bool {
        if (self.raked) return false;
        if (mathx.distXZ(self.pos, hero) > CLAW_BAND) return false;
        return self.aiRng.float() < RAKE_CHANCE;
    }

    /// THE RETURN. It carries on from where the first stroke FINISHED rather than resetting to a cocked
    /// shoulder — that is what makes the pair read as one movement, and what makes the second half as quick
    /// as it is.
    fn updateRake(self: *Delver, dt: f32, hero: rl.Vector3) void {
        if (self.t < RAKE_WIND) {
            self.faceToward(hero, TURN_RATE * 0.9, dt);
            const u = mathx.smoothstep(0, RAKE_WIND, self.t);
            self.swing = lerpF(1.0, 0.88, u); // barely gathers: the arm is already out there
            self.rear = lerpF(0.24, 0.54, u); // …and the weight goes back up over it
            self.crouch = lerpF(0.16, -0.04, u);
        } else if (self.t < RAKE_WIND + RAKE_STRIKE) {
            const u = (self.t - RAKE_WIND) / RAKE_STRIKE;
            self.swing = lerpF(0.88, -1.0, foe.swingCurve(u)); // back ACROSS the body, on the one arc shape
            self.rear = lerpF(0.54, 0.18, u);
            self.crouch = lerpF(-0.04, 0.14, u);
        } else {
            self.enter(.recover);
        }
    }

    /// IS HE IN FRONT OF IT AT ALL — down its nose and not already on top of it. It is ploughing, not
    /// steering: what it commits to is the heading it already has.
    fn aheadOf(self: *const Delver, to: rl.Vector3) bool {
        if (mathx.distXZ(self.pos, to) < PLOUGH_R_MIN * self.scale) return false;
        const dir = mathx.dirXZ(self.pos, to);
        if (mathx.lenXZ(dir) < 1e-4) return false;
        return combat.withinArc(mathx.headingXZ(dir), self.facing, PLOUGH_ARC);
    }

    /// …and IN RANGE OF A RUN as well, which is what it asks before its patience is up. Past `PLOUGH_R_MAX`
    /// the furrow stops short of him, and a charge you walk out of the end of is not a charge.
    fn linedUp(self: *const Delver, to: rl.Vector3) bool {
        return self.aheadOf(to) and mathx.distXZ(self.pos, to) <= PLOUGH_R_MAX * self.scale;
    }

    /// **THE LINE IS COMMITTED THE FRAME THE RIDGE STRAIGHTENS**, which is the surge's law with the picture
    /// swapped: what the earth is doing IS where the blow lands, so the read stays honest. It keeps crawling
    /// through the wind — a mound that STOPPED would be saying the burst's sentence — but it stops TURNING,
    /// and the heap stretches out along the heading it is about to run down.
    fn updatePlough(self: *Delver, dt: f32, hero: rl.Vector3, bounds: f32) void {
        self.depth = UNDER_DEPTH;
        if (self.t < PLOUGH_WIND) {
            const u = mathx.smoothstep(0, PLOUGH_WIND, self.t);
            mathx.stepXZ(&self.pos, self.fdir(), UNDER_SPEED * 0.45 * self.scale * dt, bounds);
            self.moundR = lerpF(MOUND_TRAVEL_R, MOUND_PLOUGH_R, u);
            self.moundH = lerpF(MOUND_TRAVEL_H, MOUND_PLOUGH_H, u);
            self.moundLong = lerpF(1.0, MOUND_PLOUGH_LONG, u); // …and it DRAWS OUT down the heading

            self.shudder = u * 0.6; // it trembles less than the surge does: this one is about to MOVE
            self.emitSpray(dt, 10.0 + 22.0 * u);
            return;
        }
        const u = mathx.clampF((self.t - PLOUGH_WIND) / PLOUGH_DUR, 0, 1);
        // IT WINDS UP INTO THE RUN AND COMES OFF THE THROTTLE AT THE END, which is what stops the furrow
        // ending on a hard edge and gives the last metre of it a lip to come up out of.
        const speed = PLOUGH_SPEED * lerpF(0.55, 1.0, mathx.smoothstep(0, 0.30, u)) *
            (1.0 - 0.5 * mathx.smoothstep(0.75, 1.0, u));
        const was = self.pos;
        mathx.stepXZ(&self.pos, self.fdir(), speed * self.scale * dt, bounds);
        self.gait += speed * dt / (STRIDE * self.scale);
        self.emitWake(dt);
        self.emitSpray(dt, 24.0);
        // **THE FURROW IS A SWEPT SEGMENT.** At nine metres a second it covers fifteen centimetres a frame,
        // and a point test against a body 0.36 m across steps straight over him about half the time.
        if (!self.heroLatch and self.furrowed(was, hero)) {
            self.heroLatch = true;
            self.heroHit = PLOUGH_HIT;
            self.leash.noteCombat();
            self.dirtBurst(v3(hero.x, self.pos.y + 0.08, hero.z), 12, 3.0, 0.20);
        }
        if (u >= 1.0) {
            sfx.world(.delver_burst, self.pos);
            self.burstDirt();
            self.armDive();
            self.enter(.heave); // …and it comes up through the shared tail, still half buried
        }
    }

    /// Did the furrow pass under him between two frames — the swept test at a tenth of `foe.weaponReaches`'
    /// cost, because this is a circle travelling on the ground rather than a limb with a length.
    fn furrowed(self: *const Delver, was: rl.Vector3, hero: rl.Vector3) bool {
        const q = mathx.closestOnSegXZ(hero, was, self.pos);
        return mathx.distXZ(hero, q) <= PLOUGH_R * self.scale + foe.HERO_R;
    }

    fn updateDive(self: *Delver, dt: f32, hero: rl.Vector3) void {
        if (self.t < DIVE_WIND) {
            self.faceToward(self.goingFor(hero), TURN_RATE, dt);
            // UP ON ITS HIND LEGS, forelimbs overhead — the biggest it ever is, and the only frame of this
            // creature you can read from across the field.
            const u = mathx.smoothstep(0, DIVE_WIND, self.t);
            self.rear = lerpF(0, 1.0, u);
            self.swing = lerpF(0, -0.7, u);
            self.crouch = lerpF(0.05, -0.22, u);
            self.drill = lerpF(0, -18.0, u);
            if (self.t >= DIVE_WIND * 0.6) self.emitScrape(dt);
            return;
        }
        // RE-ASKED AT THE LAUNCH: a root closing during the wind arrives after the choose site, and a leap
        // is the one thing the grip refuses outright (`foe.canLeap`).
        if (!foe.canLeap(&self.root)) {
            sfx.world(.delver_hurt, self.pos);
            self.enter(.recover);
            return;
        }
        const u = mathx.clampF((self.t - DIVE_WIND) / DIVE_DUR, 0, 1);
        self.rear = lerpF(1.0, 0, u);
        self.drill = lerpF(-18.0, 62.0, u); // nose first, tail last
        self.swing = lerpF(-0.7, 0.8, u); // …and it hauls itself down with both forelimbs
        self.depth = UNDER_DEPTH * u;
        self.emitSpray(dt, 26.0);
        if (u >= 1.0) self.enter(.under);
    }

    fn updateUnder(self: *Delver, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const to = self.goingFor(hero);
        self.depth = UNDER_DEPTH;
        self.faceToward(to, UNDER_TURN, dt);
        mathx.stepXZ(&self.pos, self.fdir(), UNDER_SPEED * self.scale * dt, bounds);
        self.gait += UNDER_SPEED * dt / (STRIDE * self.scale); // still swimming, out of sight
        self.drill = 0;
        self.emitWake(dt);
        self.churn += dt;
        if (self.churn >= CHURN_EVERY) {
            self.churn -= CHURN_EVERY;
            sfx.world(.delver_churn, self.pos);
        }
        // IT STAYS DOWN (`UNDER_MIN`) and then comes up when it is under him — or wherever it happens to be
        // once the patience runs out, so a player who simply walks does not fight a mound forever.
        if (self.t < UNDER_MIN) return;
        // UNDER HIM: the ground opens where he is standing.
        if (mathx.distXZ(self.pos, to) <= SURGE_LOCK_R + self.bodyR()) return self.enterSurge();
        // OUT IN FRONT AND IN RANGE OF A RUN: it stops trying to get under him — that is a chase it will not
        // win against a sprint — and drives the ridge down the ground he is running over instead.
        if (self.linedUp(to)) return self.enterPlough();
        // **AND ITS PATIENCE RUNS OUT DOWN THE LINE, NOT ON THE SPOT.** A surge at ground he left ten metres
        // back is the move spent on nothing; the plough at least covers the gap and arrives near him, which
        // is what this exit was always for. On the spot only if he is not in front of it at all.
        if (self.t >= UNDER_MAX) {
            if (self.aheadOf(to)) return self.enterPlough();
            return self.enterSurge();
        }
    }

    fn enterSurge(self: *Delver) void {
        sfx.world(.delver_surge, self.pos);
        self.surged = true;
        self.enter(.surge);
    }

    fn enterPlough(self: *Delver) void {
        sfx.world(.delver_churn, self.pos);
        // The GROUP reads this edge for the shake and the low rumble (`Warrens.anySurged`), and a tell arriving
        // from off screen is exactly what that exists for — this one as much as the burst's.
        self.surged = true;
        self.heroLatch = false;
        self.enter(.plough);
    }

    /// **THE SPOT IS COMMITTED THE FRAME THE MOUND STOPS.** Nothing moves through the whole of the tell: what
    /// the earth is doing IS where the blow lands, so the counter is your feet and the read is honest.
    fn updateSurge(self: *Delver, dt: f32) void {
        self.depth = UNDER_DEPTH;
        const u = mathx.smoothstep(0, SURGE_DUR, self.t);
        // IT SWELLS TO THE RING IT IS ANNOUNCING and no further — the dome IS the picture of where the blow
        // lands, so a bigger one promises ground the burst never reaches. And it stays LOW: what the player
        // has to see over it is his own feet.
        // THE MOUND HOLDS ITS SIZE and the SPRAY is what builds (`SURGE_SPRAY_*`).
        self.moundR = MOUND_SWELL_R;
        self.moundH = MOUND_SWELL_H;
        self.shudder = u;
        self.surgeK = std.math.pow(f32, u, SURGE_SPRAY_CURVE);
        self.emitSpray(dt, lerpF(SURGE_SPRAY_0, SURGE_SPRAY_1, self.surgeK));
        if (self.t >= SURGE_DUR) {
            sfx.world(.delver_burst, self.pos);
            self.enter(.burst);
        }
    }

    fn updateBurst(self: *Delver, dt: f32, hero: rl.Vector3) void {
        const u = mathx.clampF(self.t / BURST_RISE, 0, 1);
        self.depth = UNDER_DEPTH * (1.0 - u);
        // IT COMES UP CLAWS AND NOSE FIRST and only then drops onto them. Brought level across the rise it
        // surfaced already prone, which reads as a mole coming out rather than the ground erupting.
        self.rear = lerpF(1.0, 0.58, u);
        self.swing = lerpF(-0.85, 0.45, u);
        self.drill = lerpF(-52.0, -14.0, u);
        self.shudder = 0;
        // AND THE HEAP GOES AS THE BODY COMES THROUGH IT. Held at full size for the whole rise it vanished on
        // one frame — a mound that was there and then simply was not, with a creature standing where it had
        // been. The earth is what it is coming out OF, so it comes apart as it does.
        self.moundR = lerpF(MOUND_SWELL_R, 0, u);
        self.moundH = lerpF(MOUND_SWELL_H, 0, u * u);
        if ((self.t - dt) <= 0 and self.t > 0) {
            // The blow is on the OPENING frame, and its reach is a RADIUS — the ground opening has no edge to
            // sweep. Its `from` is the hole itself, so stood dead on it there is no bearing and the boards
            // cannot answer it (the zero-`fromDir` rule); caught at the rim, they can.
            self.burstDirt();
            if (mathx.distXZ(self.pos, hero) <= BURST_R * self.scale + foe.HERO_R) {
                self.heroHit = BURST_HIT;
                self.leash.noteCombat();
            }
        }
        if (self.t >= BURST_RISE) {
            self.depth = 0;
            self.moundR = 0;
            self.moundH = 0;
            self.surgeK = 0;
            self.armDive();
            self.enter(.heave);
        }
    }

    /// **THE COOLDOWN IS SPENT ON THE SURFACE, NOT ON THE BURROW.** Stamped where it went DOWN it was being run
    /// off by the very thing it gates: the under, the surge, the rise and the opening come to about five seconds
    /// of it, so the window you actually get to hit the creature in was whatever was left over — and a burrow
    /// that ran to `UNDER_MAX` left none at all and re-dived on the frame it finished getting up. Armed here,
    /// the dial means the seconds it stands in front of you.
    fn armDive(self: *Delver) void {
        self.diveCd = DIVE_CD * self.aiRng.range(0.85, 1.25);
    }

    fn decide(self: *Delver, d: f32) void {
        const pick = classify(d, self.clawCd <= 0, self.diveCd <= 0, !foe.canLeap(&self.root));
        if (pick != .rest) self.homing = false; // anything but resting is a decision about HIM
        switch (pick) {
            .rest => {
                if (mathx.distXZ(self.pos, self.home) > HOME_R) {
                    self.homing = true;
                    self.enter(.walk);
                } else self.enterIdle(0.5 + self.seed * 0.5);
            },
            .wait => self.enterIdle(0.24),
            .walk => self.enter(.walk),
            .claw => {
                self.clawCd = CLAW_CD * self.aiRng.range(0.85, 1.3);
                self.heroLatch = false;
                self.raked = false; // a fresh gather is owed its own return
                sfx.world(.delver_claw, self.pos);
                self.enter(.claw);
            },
            .dive => {
                sfx.world(.delver_dig, self.pos);
                self.enter(.dive);
            },
        }
    }

    /// The mound has a life of its own on the way in and the way out — it is a heap of earth, and a heap of
    /// earth does not appear on one frame. Driven off what the BODY is doing rather than off a clock beside
    /// it, so the two can never disagree about whether there is anything down there.
    fn settleMound(self: *Delver, dt: f32) void {
        const wantR: f32 = switch (self.state) {
            .dive => MOUND_TRAVEL_R * mathx.clampF(self.depth / UNDER_DEPTH, 0, 1),
            .under => MOUND_TRAVEL_R,
            // The three that drive the heap themselves — the two tells and the rise — hand back their own.
            .surge, .plough, .burst => self.moundR,
            else => 0,
        };
        const wantH: f32 = switch (self.state) {
            .dive => MOUND_TRAVEL_H * mathx.clampF(self.depth / UNDER_DEPTH, 0, 1),
            .under => MOUND_TRAVEL_H + 0.05 * mathx.sinf(self.gait * std.math.tau),
            .surge, .plough, .burst => self.moundH,
            else => 0,
        };
        // Only the plough draws the heap out; everything else is round, and a furrow that has run its course
        // pulls back in rather than snapping.
        const wantLong: f32 = if (self.state == .plough) self.moundLong else 1.0;
        self.moundR = mathx.approach(self.moundR, wantR, dt * 5.0);
        self.moundH = mathx.approach(self.moundH, wantH, dt * 5.0);
        self.moundLong = mathx.approach(self.moundLong, wantLong, dt * 6.0);
        if (self.state != .surge and self.state != .plough) self.shudder = mathx.approach(self.shudder, 0, dt * 4.0);
    }

    fn enter(self: *Delver, s: State) void {
        self.state = s;
        self.t = 0;
    }
    fn enterIdle(self: *Delver, wait: f32) void {
        self.state = .idle;
        self.t = 0;
        self.idleWait = wait;
        // THE SURGE'S BUILD GOES WITH IT. Left standing, the next thing this creature does inherits the
        // fountain — a scuff or a dive wind throwing clods at the tell's own peak rate, which is the surge
        // announcing itself when nothing is coming.
        self.surgeK = 0;
    }
    /// A BLOW NEVER LANDS ON SOMETHING SUBMERGED, so a stun always finds it on the surface — but the depth is
    /// cleared here anyway, because a stagger arriving on the rise must not strand it half in the ground.
    fn enterStun(self: *Delver, s: State) void {
        self.enter(s);
        self.moundR = 0;
        self.moundH = 0;
        self.heroLatch = false;
    }
    fn enterDeath(self: *Delver) void {
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    pub fn debugDive(self: *Delver) void {
        self.diveCd = 0;
        self.enter(.dive);
    }
    pub fn debugClaw(self: *Delver) void {
        self.heroLatch = false;
        self.raked = false;
        self.enter(.claw);
    }
    pub fn debugRake(self: *Delver) void {
        self.heroLatch = false;
        self.raked = true;
        self.enter(.rake);
    }
    /// Staged from UNDER, because that is the only place it can come from: the depth and the travelling ridge
    /// are what the tell is drawn against.
    pub fn debugPlough(self: *Delver) void {
        self.heroLatch = false;
        self.depth = UNDER_DEPTH;
        self.moundR = MOUND_TRAVEL_R;
        self.moundH = MOUND_TRAVEL_H;
        self.enter(.plough);
    }
    pub fn debugKill(self: *Delver) void {
        self.enterDeath();
    }
    pub fn debugStagger(self: *Delver, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }

    /// WHAT CARRIES A BLOW AND HOW LONG UNTIL IT LANDS — exhaustive over the states, so one added later has
    /// to say. **THE BURST IS DELIBERATELY OUT**, and it is the same decision the Bone Knight's fall is: there
    /// is nothing to catch in the ground opening under you, and boards that stopped it would be the answer to
    /// the move this creature exists for. Its counter is the mound and the roll — which is why the tell is
    /// the longest thing it does.
    fn toImpact(self: *const Delver) ?f32 {
        return switch (self.state) {
            .claw => CLAW_WIND - self.t,
            // …AND THE RETURN IS CATCHABLE TOO. It is quicker than the opener, so the window opens later in
            // real time — which is the whole of what makes the pair a rhythm rather than two strokes.
            .rake => RAKE_WIND - self.t,
            // **THE PLOUGH IS OUT WITH THE BURST**, and for the same reason: there is nothing to catch in a
            // furrow coming up under you. Its counter is the line and your feet, which is why its ridge
            // straightens half a second before it runs.
            .idle, .walk, .recover, .dive, .under, .surge, .plough, .burst, .heave, .stunlight, .stunheavy, .dead => null,
        };
    }

    fn parryable(self: *const Delver) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return CLAW_BAND + foe.HERO_REACH;
    }

    fn takeParry(self: *Delver) void {
        const reach = self.parryable() orelse return;
        if (!self.parry.catches(self.pos, reach)) return;
        self.parried = true;
        self.flash = foe.FLASH_DUR;
        self.leash.noteCombat();
        self.clawCd = CLAW_CD; // gathered again before it throws the stroke twice
        self.heroLatch = false;
        sfx.world(.delver_hurt, self.pos);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
    }

    pub fn tryHit(self: *Delver, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, .{ .light = 0.7, .heavy = 1.15 }); // heavy and low: it barely gives
        self.dirtBurst(s.contact, if (heavy) 9 else 5, 2.0, 0.13);
        sfx.world(.delver_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                sfx.world(.delver_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn emit(self: *Delver, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.parts, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }
    fn dirtBurst(self: *Delver, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        const parts = foe.hitParts(n); // the field's one dial (`foe.HIT_PARTS`)
        var i: i32 = 0;
        while (i < parts) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.4, 1.0) * spd;
            self.emit(c, v3(mathx.cosf(a) * sp, self.fxRng.range(0.6, 2.0), mathx.sinf(a) * sp), self.fxRng.range(0.3, 0.6), self.fxRng.range(0.05, 0.10), big, foe.DUST, 5.0);
        }
    }
    /// THE HOLE OPENING — clods thrown out and up, in the mound's own warm soil rather than in dust: what
    /// arrives is EARTH, and a grey puff would say the creature exhaled.
    fn burstDirt(self: *Delver) void {
        var i: i32 = 0;
        while (i < 26) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.5, 1.0) * 4.2;
            self.emit(
                v3(self.pos.x + mathx.cosf(a) * 0.4, self.pos.y + 0.10, self.pos.z + mathx.sinf(a) * 0.4),
                v3(mathx.cosf(a) * sp, self.fxRng.range(2.4, 5.2), mathx.sinf(a) * sp),
                self.fxRng.range(0.55, 0.9),
                self.fxRng.range(0.07, 0.15),
                0.03,
                if (self.fxRng.float() < 0.35) CLOD_DK else CLOD,
                9.0,
            );
        }
        self.dirtBurst(v3(self.pos.x, self.pos.y + 0.06, self.pos.z), 14, 3.4, 0.24);
    }
    /// The ridge of earth it pushes ahead of itself — laid at the SURFACE, since that is the only place any
    /// of this is visible from.
    fn emitWake(self: *Delver, dt: f32) void {
        self.fxAccum += 22.0 * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.3, 1.0) * self.moundR * self.scale;
            const back = mathx.scaleV(self.fdir(), -self.fxRng.range(0.1, 0.7));
            self.emit(
                v3(self.pos.x + back.x + mathx.cosf(a) * rr, self.pos.y + 0.08, self.pos.z + back.z + mathx.sinf(a) * rr),
                v3(mathx.cosf(a) * 0.5, self.fxRng.range(0.5, 1.5), mathx.sinf(a) * 0.5),
                self.fxRng.range(0.35, 0.7),
                self.fxRng.range(0.05, 0.11),
                0.03,
                if (self.fxRng.float() < 0.4) CLOD_DK else CLOD,
                6.0,
            );
        }
    }
    /// The earth jetting off the dome while it gathers, and off the drill on the way down.
    fn emitSpray(self: *Delver, dt: f32, rate: f32) void {
        if (rate <= 0) return;
        const kick = 1.0 + (SURGE_SPRAY_LIFT - 1.0) * self.surgeK;
        self.fxAccum += rate * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.2, 1.0) * mathx.maxF(0.5, self.moundR) * self.scale;
            self.emit(
                v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.06, self.pos.z + mathx.sinf(a) * rr),
                // …AND HARDER AS IT BUILDS. `surgeK` is 0 everywhere but the surge, so every other caller of
                // this emitter throws exactly what it always did.
                v3(mathx.cosf(a) * 0.8 * kick, self.fxRng.range(1.2, 3.0) * kick, mathx.sinf(a) * 0.8 * kick),
                self.fxRng.range(0.3, 0.6) * (1.0 + 0.5 * self.surgeK),
                self.fxRng.range(0.05, 0.11),
                0.03,
                if (self.fxRng.float() < 0.4) CLOD_DK else CLOD,
                7.5,
            );
        }
    }
    /// Its claws raking the ground as it loads the dive — small, at its feet, and the one cue that says the
    /// rear is going somewhere.
    fn emitScrape(self: *Delver, dt: f32) void {
        self.fxAccum += 14.0 * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const f = self.fdir();
            const a = self.fxRng.angle();
            self.emit(
                v3(self.pos.x + f.x * 0.5 + mathx.cosf(a) * 0.3, self.pos.y + 0.05, self.pos.z + f.z * 0.5 + mathx.sinf(a) * 0.3),
                v3(-f.x * 1.6, self.fxRng.range(0.4, 1.2), -f.z * 1.6),
                self.fxRng.range(0.25, 0.5),
                self.fxRng.range(0.04, 0.08),
                0.02,
                CLOD_DK,
                6.0,
            );
        }
    }
    fn emitScuff(self: *Delver, dt: f32) void {
        self.fxAccum += 5.0 * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            self.emit(
                v3(self.pos.x + mathx.cosf(a) * 0.4, self.pos.y + 0.03, self.pos.z + mathx.sinf(a) * 0.4),
                v3(mathx.cosf(a) * 0.3, self.fxRng.range(0.2, 0.6), mathx.sinf(a) * 0.3),
                self.fxRng.range(0.2, 0.4),
                0.05,
                0.10,
                foe.DUST,
                4.0,
            );
        }
    }
    pub fn drawFx(self: *const Delver) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Delver, model: *const Model) void {
        model.draw(self);
    }

    pub fn pose(self: *Delver) void {
        const fs = self.scale * (1.0 - 0.5 * self.fade);
        // **A ROOT PITCH ROTATES ABOUT THE POINT ON THE GROUND**, so a body this long tipped either way drives
        // one end straight through the floor — the hero's own no-root-pitch trap, on a creature that has no
        // waist to hinge at instead. Lifted by exactly what the tip sinks (half its own length x sin), both
        // ends stay on the earth; and the lift FADES OUT with the depth, because once it is going down
        // through the ground that is the whole idea.
        const sink = mathx.sinf(mathx.radians(@abs(self.drill))) * BODY_HALF;
        const clear = sink * (1.0 - mathx.clampF(self.depth / UNDER_DEPTH, 0, 1)) * fs;
        const root = mul3(
            mul(scaleM(fs, fs, fs), rx(self.drill)),
            ry(mathx.degrees(self.facing)),
            tr(self.pos.x, self.pos.y + self.ride() + clear, self.pos.z),
        );
        self.xf[BODY] = root;

        // THE HEAD LEADS EVERYTHING. It dips as the body loads, comes up with the rear, and drives down
        // through the drill — staggered off the trunk's own channels rather than moving with them, or the
        // whole creature reads as one welded block (`ogre.poseUpper`'s law at a tenth the size).
        const headPitch = -22.0 * self.rear + 16.0 * self.crouch + 10.0 * self.swing;
        const headYaw = 12.0 * self.swing;
        self.xf[HEAD] = mul(mul3(ry(headYaw), rx(headPitch), tr(REST[HEAD].x, REST[HEAD].y + 0.10 * self.rear, REST[HEAD].z)), root);

        // The forelimbs. `swing` is the stroke: -1 cocked behind the shoulder, +1 carried through across the
        // front. The off limb does HALF of it — a body swinging one arm and holding the other still is a
        // mannequin with a wing.
        for ([_]usize{ ARML, ARMR }, [_]usize{ CLAWL, CLAWR }, [_]f32{ 1, -1 }) |ai, ci, sgn| {
            const own = if (sgn < 0) self.swing else self.swing * 0.45;
            const shoulder = -74.0 * self.rear - 34.0 * own;
            const abd = 16.0 + 26.0 * self.rear + 10.0 * @abs(own);
            const hip = v3(REST[ai].x, REST[ai].y - 0.12 * self.crouch, REST[ai].z);
            self.xf[ai] = mul(mul3(rz(sgn * abd), rx(shoulder), tr(hip.x, hip.y, hip.z)), root);
            // THE ARM GOES LONG AT THE STRIKE (the warriors' law): a folded elbow keeps the claws inside its
            // own silhouette however far the numbers say they reach.
            const elbow = 40.0 - 46.0 * own - 26.0 * self.rear;
            self.xf[ci] = mul(mul(rx(elbow), tr(REST[ci].x, REST[ci].y, REST[ci].z)), self.xf[ai]);
        }

        // The hind legs carry the rear and the gait. THE BRACE TAKES UP IN THE KNEE — a reared digger is
        // standing on these, not squatting.
        const step = mathx.sinf(self.gait * std.math.tau);
        for ([_]usize{ HINDL, HINDR }, [_]f32{ 1, -1 }) |bi, sgn| {
            const ph = step * sgn;
            const hipA = 18.0 * self.rear + 26.0 * ph - 20.0 * self.crouch;
            self.xf[bi] = mul(mul3(rz(sgn * 10.0), rx(hipA), tr(REST[bi].x, REST[bi].y - 0.14 * self.crouch, REST[bi].z)), root);
        }

        // …and the tail counter-swings the lot, a beat late.
        const tailA = 34.0 * self.rear - 20.0 * self.swing;
        self.xf[TAIL] = mul(mul3(ry(-14.0 * self.swing), rx(tailA), tr(REST[TAIL].x, REST[TAIL].y, REST[TAIL].z)), root);

        // THE MOUND IS IN WORLD SPACE AT THE SURFACE and hangs off nothing — the body's matrix is metres
        // under the ground by now, and a heap of earth parented to it would be buried with it.
        const sh = self.shudder;
        const throb = 1.0 + 0.06 * sh * mathx.sinf(self.elapsed * 26.0);
        const mr = self.moundR * self.scale * throb;
        const mh = self.moundH * self.scale * throb;
        // The mesh's own +Z is the heading once `ry(facing)` below has turned it, so the stretch goes on Z
        // alone — a ridge drawn out down the line it is running, and a round heap at `moundLong` 1.
        self.xf[MOUND] = mul3(
            mul(scaleM(mr, mh, mr * self.moundLong), rz(2.6 * sh * mathx.sinf(self.elapsed * 31.0))),
            ry(mathx.degrees(self.facing)),
            tr(self.pos.x, self.pos.y + 0.02, self.pos.z),
        );
    }
};

const CAP_N = wf.MAX_PER_KIND;

pub const Warrens = struct {
    model: Model,
    delvers: [CAP_N]Delver = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Warrens {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Warrens) []Delver {
        return self.delvers[0..self.n];
    }
    pub fn liveConst(self: *const Warrens) []const Delver {
        return self.delvers[0..self.n];
    }
    pub fn reset(self: *Warrens, m: *const wf.Map) void {
        foe.resetGroup(Delver, &self.delvers, &self.n, m, .delver);
    }
    pub fn setShader(self: *Warrens, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Warrens, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Warrens) bool {
        return foe.anyParried(self.liveConst());
    }
    /// ONE OF THEM COMMITTED TO A BURST THIS FRAME — a ONE-FRAME edge, `anyDied`'s. What it buys is the third
    /// channel of the tell: the mound and the noise are no use to a player whose camera is pointed at the
    /// horizon, and the ground going under your own feet is a thing you should FEEL.
    pub fn anySurged(self: *const Warrens) bool {
        for (self.liveConst()) |*d| {
            if (d.surged) return true;
        }
        return false;
    }
    pub fn update(self: *Warrens, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Warrens, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Warrens) void {
        for (self.liveConst()) |*d| d.drawFx();
    }
    pub fn pierce(self: *Warrens, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Warrens) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Warrens) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Warrens) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Warrens) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[BODY] = bodyMesh();
    mesh[HEAD] = headMesh();
    mesh[ARML] = armMesh(1);
    mesh[ARMR] = armMesh(-1);
    mesh[CLAWL] = clawMesh(1);
    mesh[CLAWR] = clawMesh(-1);
    mesh[HINDL] = hindMesh(1);
    mesh[HINDR] = hindMesh(-1);
    mesh[TAIL] = tailMesh();
    mesh[MOUND] = moundMesh();
    return mesh;
}

fn bodyMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xD31E);
    b.setMat(.skin);
    // LONG AND LOW. A digger is a wedge lying on the ground, not a boulder standing on it: the first pass
    // was 0.87 m tall on a 1.55 m creature and read as a tortoise.
    b.addBlob(v3(0, 0.26 * H, -0.08), v3(0.42, 0.17 * H, 0.80), 8, 14, HIDE); // the long hump
    b.addBlob(v3(0, 0.30 * H, 0.30), v3(0.40, 0.15 * H, 0.38), 7, 13, HIDE); // the digger's shoulders, proud
    b.addBlob(v3(0, 0.14 * H, 0.04), v3(0.36, 0.09 * H, 0.66), 6, 12, HIDE_LO); // its belly, near the ground
    b.addBlob(v3(0, 0.22 * H, -0.66), v3(0.30, 0.13 * H, 0.28), 6, 12, HIDE_LO); // the rump
    // THE DORSAL PLATES. Relief is subtle: a few PERCENT of the mass's radius proud, sunk most of the way
    // in, and dealt UNEVEN — the variation is between the plates, never banded along one.
    var i: i32 = 0;
    while (i < 8) : (i += 1) {
        const u = @as(f32, @floatFromInt(i)) / 7.0;
        const z = 0.50 - u * 1.24; // down the spine, front to rump — never stacked on the crown
        const taper = 1.0 - 0.45 * u;
        b.addBlob(
            v3(rng.signed() * 0.04, (0.26 + 0.155) * H - 0.05 * u * u, z),
            v3(rng.range(0.16, 0.26) * taper, rng.range(0.024, 0.042), rng.range(0.08, 0.12)),
            5,
            10,
            PLATE,
        );
    }
    return b.toMesh();
}

fn headMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0, 0.04), v3(0.22, 0.16, 0.26), 7, 13, HIDE); // the skull, wedged
    b.addCapsule(v3(0, -0.02, 0.18), v3(0, -0.06, 0.38), 0.14, 0.09, 9, SNOUT); // the wedge of a snout
    b.addBlob(v3(0, -0.06, 0.41), v3(0.10, 0.075, 0.07), 5, 10, SNOUT); // its blunt nose pad
    b.addBlob(v3(0, 0.09, 0.12), v3(0.185, 0.042, 0.18), 5, 11, PLATE); // the digging plate over the brow
    // Tiny and sunk: it does not live by them, and a pair of lamps on a burrower reads as a lizard.
    b.setMat(.plain);
    b.addBlob(v3(0.13, 0.01, 0.20), v3(0.030, 0.026, 0.026), 4, 8, EYE);
    b.addBlob(v3(-0.13, 0.01, 0.20), v3(0.030, 0.026, 0.026), 4, 8, EYE);
    return b.toMesh();
}

fn armMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(0, 0, 0), v3(0.19, 0.18, 0.19), 5, 10, HIDE); // the shoulder ball
    b.addCapsule(v3(0, -0.02, 0.02), v3(side * 0.12, -0.14, 0.44), 0.155, 0.125, 9, HIDE_LO);
    return b.toMesh();
}

fn clawMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.05, -0.09, 0.40), 0.125, 0.10, 9, HIDE_LO); // the forearm
    b.addBlob(v3(side * 0.05, -0.10, 0.44), v3(0.14, 0.11, 0.13), 5, 10, HIDE_LO); // the pad it digs on
    b.setMat(.plain);
    // **THE CLAWS ARE THE CREATURE'S POINT AND THEY HAVE TO LOOK IT** (owner: more pronounced claws and
    // nails). At 0.04 thick and 0.22 long they were three scratches on the end of a pad — a digging animal's
    // whole argument is its hands, and on a body this dark the only thing that carries at distance is the pale
    // horn on the front of it. Half again as long, half again as thick at the root, and hooked DOWN and UNDER
    // rather than laid flat, which is what says they are for tearing earth rather than for standing on.
    //
    // Still THREE, still uneven, still longest in the middle, and **still none of them ends in a point** — the
    // tip is a blunt capsule cap, because a rosette of needles is a hub of spokes. What makes them read as
    // sharp is the TAPER (0.062 to 0.020, a hair over 3:1) and the hook, never a spike.
    inline for (.{
        .{ 0.11, -0.12, 0.50, 0.13, -0.30, 0.92, 0.056, 0.020 }, // outer
        .{ 0.00, -0.13, 0.51, 0.00, -0.33, 1.02, 0.062, 0.022 }, // middle, the longest
        .{ -0.09, -0.12, 0.49, -0.12, -0.28, 0.87, 0.050, 0.019 }, // inner
    }) |c| {
        // A KNUCKLE AT THE ROOT of each, so the horn comes OUT of something instead of being stuck on.
        b.addBlob(v3(side * c[0], c[1] + 0.01, c[2] - 0.02), v3(c[6] * 1.5, c[6] * 1.4, c[6] * 1.6), 5, 8, HIDE_LO);
        // …AND THE HORN IN TWO SEGMENTS, so the hook is a curve and not a straight spike leaning down.
        const mx = side * (c[0] + c[3]) * 0.5;
        const my = (c[1] + c[4]) * 0.5 + 0.035; // …the bend rides ABOVE the chord, which is what hooks it
        const mz = (c[2] + c[5]) * 0.5;
        b.addCapsule(v3(side * c[0], c[1], c[2]), v3(mx, my, mz), c[6], c[6] * 0.72, 7, CLAW);
        b.addCapsule(v3(mx, my, mz), v3(side * c[3], c[4], c[5]), c[6] * 0.72, c[7], 7, CLAW);
        // …and a blunt cap on the end of it. NOTHING ENDS IN A POINT.
        b.addBlob(v3(side * c[3], c[4], c[5]), v3(c[7] * 1.1, c[7] * 1.1, c[7] * 1.2), 4, 7, CLAW_LT);
    }
    return b.toMesh();
}

fn hindMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(side * 0.06, -0.28, -0.06), 0.16, 0.12, 9, HIDE_LO); // thigh into shank
    b.addBlob(v3(side * 0.07, -0.34, 0.02), v3(0.13, 0.07, 0.17), 5, 10, HIDE_LO); // a broad flat foot
    return b.toMesh();
}

fn tailMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, -0.06, -0.34), 0.17, 0.10, 9, HIDE_LO);
    b.addBlob(v3(0, -0.08, -0.40), v3(0.10, 0.09, 0.10), 5, 10, HIDE_LO); // blunt: nothing here ends in a point
    return b.toMesh();
}

/// A UNIT ridge of earth — radius 1, height 1 — scaled to whatever the creature is doing under it. Warm
/// soil, uneven, with a scatter of clods sunk into its own flank so the dome is not one smooth bubble.
fn moundMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x50110);
    b.setMat(.stone);
    // A RIDGE ALONG THE WAY IT IS GOING, not a dome: what a burrower pushes up is a furrow, and a smooth
    // hemisphere came back reading as a beach ball dropped on the grass.
    b.addBlob(v3(0, -0.62, 0.08), v3(0.74, 1.30, 1.06), 6, 14, SOIL); // sunk deep — only the crest is proud
    b.addBlob(v3(0.10, -0.60, -0.32), v3(0.50, 1.12, 0.56), 5, 11, SOIL_DK); // a second lobe, off the line
    b.addBlob(v3(-0.08, -0.62, 0.48), v3(0.42, 1.16, 0.42), 5, 11, SOIL); // …and the nose of the furrow
    // The clods turned out along its flanks. Dealt UNEVEN and sunk most of the way in: relief is subtle,
    // and what these are for is stopping the crest reading as one smooth shell.
    var i: i32 = 0;
    while (i < 11) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.30, 0.80);
        const sz = rng.range(0.09, 0.19);
        // TALL IN UNIT SPACE ON PURPOSE. The mound's matrix scales XZ and Y by different factors (a wide low
        // ridge), so a lump authored round comes out a pancake laid on the shell — which is what the first
        // pass drew. Pre-stretched by the same ratio, it lands round.
        b.addBlob(
            v3(mathx.cosf(a) * rr * 0.62, rng.range(0.16, 0.52), mathx.sinf(a) * rr * 1.05),
            v3(sz, sz * 1.5, sz),
            4,
            9,
            if (rng.float() < 0.5) SOIL_DK else SOIL,
        );
    }
    return b.toMesh();
}

test "IT STAYS DOWN, and it comes up under him" {
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 9.0);
    d.debugDive();
    var under: f32 = 0;
    var burst = false;
    var fr: u32 = 0;
    while (fr < 60 * 20) : (fr += 1) {
        _ = d.update(1.0 / 60.0, hero, 400, .{});
        if (d.state == .under) under += 1.0 / 60.0;
        if (d.state == .burst) {
            burst = true;
            break;
        }
    }
    try std.testing.expect(burst);
    // The whole of the owner's ask: it may not pop straight back up, however quickly it gets there.
    try std.testing.expect(under >= UNDER_MIN);
    // …and it travelled: it comes up under HIM, not where it went down.
    try std.testing.expect(mathx.distXZ(d.pos, hero) < BURST_R);
    try std.testing.expect(mathx.distXZ(d.pos, mathx.zero3) > 4.0);
}

test "TWO WAYS OUT OF THE BURROW: under him it BURSTS, out in front of him it PLOUGHS" {
    // The whole of why there are two. STANDING STILL he is caught: it swims faster than he walks, gets
    // beneath him, and the ground opens under his feet.
    {
        var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
        const hero = v3(0, 0, 6.0);
        d.debugDive();
        var fr: u32 = 0;
        while (fr < 60 * 20 and d.state != .surge and d.state != .plough) : (fr += 1) {
            _ = d.update(1.0 / 60.0, hero, 400, .{});
        }
        try std.testing.expectEqual(State.surge, d.state);
    }
    // …and SPRINTING he cannot be — `SPRINT_SPEED` is over `UNDER_SPEED`, so the chase is one it will never
    // win. It stops trying to get under him and drives the ridge down the ground he is running over instead,
    // which is the one answer this creature did not have to a player who simply keeps walking.
    {
        var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
        var hero = v3(0, 0, 4.5);
        d.debugDive();
        var fr: u32 = 0;
        while (fr < 60 * 20 and d.state != .surge and d.state != .plough) : (fr += 1) {
            hero.z += 5.1 * (1.0 / 60.0); // the hero's own sprint, written out — this file sits below `hero.zig`
            _ = d.update(1.0 / 60.0, hero, 400, .{});
        }
        try std.testing.expectEqual(State.plough, d.state);
        // …and it went under for its full patience first either way: the burrow is not a thing you rush it
        // out of by running, only a thing you change the ENDING of.
        try std.testing.expect(d.depth >= UNDER_DEPTH - 1e-3);
    }
}

test "SUBMERGED IT IS UNDER THE GROUND AT EVERY SCALE THE MAP CAN POST, not just at 1" {
    // The comptime block above is written in bare constants, which READS like a check that can only speak for
    // scale 1 — and a map may post this creature anywhere in `wf.FOE_SCALE_LO..HI`. It is in fact
    // scale-invariant, because `depth` is in scale-1 metres and `ride()` is the thing that scales it. This
    // walks the band and measures the actual sphere, so the next reader who spots the same apparent gap and
    // scales `depth` at its writers gets told: that double-scales the burrow, and a 0.5 delver surfaces.
    for ([_]f32{ wf.FOE_SCALE_LO, 1.0, 1.4, wf.FOE_SCALE_HI }) |sc| {
        var d = Delver.spawn(mathx.zero3, 0, sc, 0.3);
        d.debugDive();
        var fr: u32 = 0;
        while (fr < 60 * 6 and !d.deep()) : (fr += 1) _ = d.update(1.0 / 60.0, v3(0, 0, 1.2), 400, .{});
        try std.testing.expect(d.deep());
        // The sphere the swept blade tests against, measured exactly as `foe.bodyPoint` builds it.
        const c = d.centerWorld();
        try std.testing.expect(c.y + d.hurtRadius() < d.pos.y);
    }
}

test "THE PLOUGH IS A LINE, and stepping off it is the whole counter" {
    const struck = struct {
        /// Run one furrow straight down +Z with the hero standing `off` metres to the side of it.
        fn at(off: f32) bool {
            var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
            const hero = v3(off, 0, 6.0);
            d.debugPlough();
            var fr: u32 = 0;
            while (fr < 60 * 4) : (fr += 1) {
                if (d.update(1.0 / 60.0, hero, 400, .{})) |h| return h.dmg == PLOUGH_HIT.dmg;
                if (d.state == .heave) return false; // the run finished and never reached him
            }
            return false;
        }
    }.at;
    try std.testing.expect(struck(0)); // dead on the line…
    try std.testing.expect(struck(PLOUGH_R * 0.5));
    // …and A STRIDE TO THE SIDE IS OUT. A furrow is a line and it goes past you, where the burst is a ring
    // you are standing in the middle of.
    try std.testing.expect(!struck(PLOUGH_R + foe.HERO_R + 1.0));
    // IT IS THE LIGHTER OF THE TWO, and `game.zig` splits the felt beat on exactly that.
    try std.testing.expect(PLOUGH_HIT.stance < BURST_HIT.stance);
}

test "THE CLAW COMES BACK — the surfaced window is a trade now, not a free hit" {
    // The RETURN is quicker than the opener, which is the whole of what makes the punish a decision.
    try std.testing.expect(RAKE_WIND < CLAW_WIND);
    // …and it is a ROLL, so the stream is walked until one comes rather than asserting it always does.
    var seen = false;
    var s: u32 = 0;
    while (s < 24 and !seen) : (s += 1) {
        var d = Delver.spawn(mathx.zero3, 0, 1.0, @as(f32, @floatFromInt(s)) / 24.0);
        const hero = v3(0, 0, 1.4); // well inside `CLAW_BAND`, and still there when the stroke finishes
        d.debugClaw();
        var fr: u32 = 0;
        while (fr < 60 * 3) : (fr += 1) {
            _ = d.update(1.0 / 60.0, hero, 400, .{});
            if (d.state == .rake) seen = true;
            if (d.state == .rake or d.state == .recover) break;
        }
    }
    try std.testing.expect(seen);

    // …AND NEVER AT A MAN WHO HAS ALREADY LEFT. A backhand thrown at empty air is the creature announcing
    // that the punish was free after all, which is the thing this move exists to stop.
    var far = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    const gone = v3(0, 0, CLAW_BAND + 4.0);
    far.debugClaw();
    var fr: u32 = 0;
    while (fr < 60 * 3) : (fr += 1) {
        _ = far.update(1.0 / 60.0, gone, 400, .{});
        try std.testing.expect(far.state != .rake);
        if (far.state == .recover) break;
    }
}

test "THE COOLDOWN IS SURFACE TIME — the burrow does not spend the dial that gates it" {
    // Armed where it went DOWN, the under, the surge, the rise and the opening ran most of `DIVE_CD` off
    // before the creature was ever standing in front of you — and a burrow that went to `UNDER_MAX` left
    // nothing at all, so it re-dived on the frame it finished getting up.
    try std.testing.expect(UNDER_MIN + SURGE_DUR + BURST_RISE + BURST_RECOVER > DIVE_CD * 0.5);
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 3.0);
    d.debugDive();
    var fr: u32 = 0;
    while (fr < 60 * 30 and d.state != .heave) : (fr += 1) _ = d.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expectEqual(State.heave, d.state);
    // It comes up with the WHOLE dial still in front of it, so the number means seconds on its feet.
    try std.testing.expect(d.diveCd > DIVE_CD * 0.8);
}

test "A BLOW ON THE RISE DOES NOT HAUL IT OUT OF THE GROUND" {
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.state = .burst;
    d.t = 0;
    d.depth = UNDER_DEPTH * 0.6;
    const was = d.depth;
    d.debugStagger(true);
    try std.testing.expectApproxEqAbs(was, d.depth, 1e-5); // the state change moves nothing by itself
    _ = d.update(1.0 / 60.0, v3(0, 0, 3), 400, .{});
    try std.testing.expect(d.depth < was); // …it finishes coming up
    try std.testing.expect(d.depth > was - 0.4); // …but over frames, not on one
}

test "SUBMERGED IT CANNOT BE STRUCK, and the sword answers it the moment it breaks the surface" {
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = v3(0, 0, 3.0);
    // A blade swept through the ground where it went down, every frame, for the whole burrow.
    const sword = foe.Blade{
        .active = true,
        .r = 0.2,
        .a = v3(-1.2, 0.9, 0),
        .b = v3(1.2, 0.2, 0),
        .a0 = v3(-1.2, 0.9, 0),
        .b0 = v3(1.2, 0.2, 0),
        .hit = .{ .dmg = 20, .poise = 30 },
    };
    d.debugDive();
    var fr: u32 = 0;
    while (fr < 60 * 8 and d.state != .under) : (fr += 1) _ = d.update(1.0 / 60.0, hero, 400, .{});
    try std.testing.expectEqual(State.under, d.state);
    const hitsWhenDown = d.hits;
    fr = 0;
    while (fr < 60) : (fr += 1) {
        d.hitLatch = false; // re-armed every frame: this is the most generous swing the hero could make
        _ = d.update(1.0 / 60.0, hero, 400, sword);
    }
    try std.testing.expectEqual(hitsWhenDown, d.hits);
    // …and on the surface the same blade lands, so what refused it was the DEPTH and not a stuck latch.
    d.depth = 0;
    d.state = .idle;
    d.hitLatch = false;
    d.pos = mathx.zero3;
    d.pose();
    d.tryHit(sword);
    try std.testing.expect(d.hits > hitsWhenDown);
}

test "THE DIVE IS A LEAP AND THE ROOTS REFUSE IT — at the choose AND at the launch" {
    // At the CHOOSE: rooted, the burrow is simply not on the list, whatever the cooldown says.
    try std.testing.expectEqual(Choice.dive, classify(6.0, true, true, false));
    try std.testing.expectEqual(Choice.walk, classify(6.0, true, true, true));
    try std.testing.expectEqual(Choice.claw, classify(CLAW_BAND - 0.2, true, false, true));
    try std.testing.expectEqual(Choice.rest, classify(AGGRO_R + 1.0, true, true, false));

    // …and at the LAUNCH, because a root closing during the wind arrives after the choose site.
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.debugDive();
    var fr: u32 = 0;
    while (fr < 60 * 2 and d.state == .dive and d.t < DIVE_WIND * 0.5) : (fr += 1) {
        _ = d.update(1.0 / 60.0, v3(0, 0, 5), 400, .{});
    }
    d.root.grab();
    fr = 0;
    while (fr < 60 * 2 and d.state == .dive) : (fr += 1) _ = d.update(1.0 / 60.0, v3(0, 0, 5), 400, .{});
    try std.testing.expect(d.state != .under);
    try std.testing.expectApproxEqAbs(@as(f32, 0), d.depth, 1e-5);
}

test "THE BURST IS A RING ROUND THE HOLE, and standing off it is the whole counter" {
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.state = .surge;
    d.t = SURGE_DUR;
    d.depth = UNDER_DEPTH;
    // Dead on the spot: it lands.
    var on = d;
    var hit: ?combat.Hit = null;
    var fr: u32 = 0;
    while (fr < 30 and hit == null) : (fr += 1) hit = on.update(1.0 / 60.0, v3(0.4, 0, 0.3), 400, .{});
    try std.testing.expect(hit != null);
    try std.testing.expectEqual(BURST_HIT.dmg, hit.?.dmg);
    // A step and a half off it: nothing at all. The mound stopped where it stopped.
    var off = d;
    hit = null;
    fr = 0;
    while (fr < 30 and hit == null) : (fr += 1) hit = off.update(1.0 / 60.0, v3(0, 0, BURST_R + 1.2), 400, .{});
    try std.testing.expect(hit == null);
}

test "BOTH STROKES ARE PARRYABLE AND THE BURST IS NOT, and the window is the game's own lead" {
    // ONE DIAL, BRACKETED ON BOTH OF THEM. The return went in at a wind the lead covered over half of, which
    // is the same stroke offered twice at two difficulties — and the opener's own bracket did not see it.
    try std.testing.expect(foe.PARRY_LEAD < CLAW_WIND * 0.5); // an instant before the blow, not a slice of the tell
    try std.testing.expect(foe.PARRY_LEAD < RAKE_WIND * 0.5);
    var d = Delver.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    const step = 1.0 / 600.0;
    // Each parryable stroke walked frame by frame: its window opens once, shuts AT its own impact frame, and
    // is exactly the game's own lead wide.
    const Stroke = struct { state: State, wind: f32, strike: f32 };
    for ([_]Stroke{
        .{ .state = .claw, .wind = CLAW_WIND, .strike = CLAW_STRIKE },
        .{ .state = .rake, .wind = RAKE_WIND, .strike = RAKE_STRIKE },
    }) |a| {
        var open: f32 = -1;
        var shut: f32 = -1;
        var elapsed: f32 = 0;
        d.state = a.state;
        while (elapsed <= a.wind + a.strike) : (elapsed += step) {
            d.t = elapsed;
            if (d.parryable() != null) {
                if (open < 0) open = elapsed;
                shut = elapsed;
            }
        }
        try std.testing.expect(open > 0);
        try std.testing.expectApproxEqAbs(a.wind, shut, 3.0 * step); // shuts AT the impact frame, by construction
        try std.testing.expectApproxEqAbs(foe.PARRY_LEAD, shut - open, 3.0 * step);
    }
    // NOTHING ELSE OF ITS CARRIES ONE — least of all the burst, which is the move it exists for.
    for ([_]State{ .idle, .walk, .recover, .dive, .under, .surge, .plough, .burst, .heave, .stunlight, .stunheavy, .dead }) |s| {
        d.state = s;
        d.t = 0;
        try std.testing.expect(d.parryable() == null);
        d.t = SURGE_DUR - foe.PARRY_LEAD * 0.5;
        try std.testing.expect(d.parryable() == null);
    }
}

test "A CAUGHT CLAW NEVER ARRIVES" {
    var d = Delver.spawn(mathx.ground(0, 0), 0, 1.0, 0.0); // faces +Z
    const hero = v3(0, 0, 2.0);
    d.state = .claw;
    d.t = CLAW_WIND - foe.PARRY_LEAD * 0.5;
    // Boards up, pointed the wrong way: the stroke keeps coming.
    d.parry = .{ .live = true, .at = hero, .facing = 0 };
    d.takeParry();
    try std.testing.expect(!d.parried and d.state == .claw);
    // …and squared onto it, it is caught and the stroke dies where it stood.
    d.parry = .{ .live = true, .at = hero, .facing = std.math.pi };
    d.takeParry();
    try std.testing.expect(d.parried);
    try std.testing.expect(d.state == .stunlight or d.state == .stunheavy);
    try std.testing.expect(d.clawCd > 0);
}

test "EVERY REACH IS MEASURED, NOT ARGUED — the claw arrives inside what `parryable` promises" {
    var d = Delver.spawn(mathx.ground(0, 0), 0, 1.0, 0.0);
    d.state = .claw;
    var far: f32 = 0;
    var elapsed: f32 = 0;
    while (elapsed <= CLAW_WIND + CLAW_STRIKE) : (elapsed += 1.0 / 240.0) {
        d.t = elapsed;
        d.updateClaw(1.0 / 240.0, v3(0, 0, 3));
        d.pose();
        const seg = d.clawSeg();
        far = mathx.maxF(far, mathx.distXZ(d.pos, seg[1]));
    }
    std.debug.print("\n  delver claw arrives at {d:.2} m against a declared {d:.2}; band {d:.2}, hero held {d:.2} out\n", .{ far, CLAW_REACH, CLAW_BAND, BODY_R + foe.HERO_R });
    try std.testing.expect(far <= CLAW_REACH); // never promised further than it goes…
    try std.testing.expect(far > CLAW_REACH * 0.9); // …nor short of what it promised
    // AND THE MOVE MUST BE ABLE TO LAND AT ALL: the colliders hold him `bodyR + HERO_R` off, so a band inside
    // that is a decision spent on a guaranteed miss every single time.
    try std.testing.expect(CLAW_BAND > BODY_R + foe.HERO_R + 0.3);
    // **AND HEIGHT IS ITS OWN QUESTION.** Its shoulders sit at 0.40 m, so the stroke only ever crosses a
    // standing man because the creature REARS for it — which is why the rear is in the wind and not a
    // flourish. Held flat the rake topped out under his knee, and three claws going past his boots while
    // `weaponReaches` reported a hit is the mesh and the mechanic saying opposite things.
    var high: f32 = 0;
    var rise: f32 = CLAW_WIND;
    while (rise <= CLAW_WIND + CLAW_STRIKE) : (rise += 1.0 / 240.0) {
        d.t = rise;
        d.updateClaw(1.0 / 240.0, v3(0, 0, 3));
        d.pose();
        for (d.clawSeg()) |q| high = mathx.maxF(high, q.y - d.pos.y);
    }
    std.debug.print("  …and the rake tops out at {d:.2} m (his knee is ~0.50, his chest 1.12)\n", .{high});
    try std.testing.expect(high > 0.60);
}

test "IT WALKS ITS LIMBS OFF DISTANCE, and a wandered one goes home" {
    var d = Delver.spawn(mathx.ground(6, 0), 0, 1.0, 0.3);
    d.home = mathx.zero3;
    d.diveCd = 999; // the burrow off the table: this is about the surface walk
    var fr: u32 = 0;
    while (fr < 60 * 20) : (fr += 1) {
        _ = d.update(1.0 / 60.0, v3(0, 0, 60), 400, .{});
        d.diveCd = 999;
    }
    try std.testing.expect(mathx.distXZ(d.pos, d.home) < HOME_R + 0.6);
    try std.testing.expect(d.gait > 1.0); // the phase came off the ground it covered
}

test "hurt in its own coin: a bolt earths through it, the cold stiffens it, fire smoulders" {
    const bolt = combat.Hit{ .elem = combat.elems(.{ .lightning = 20 }) };
    var v = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = v.hit(bolt);
    try std.testing.expect(v.hp < HP_MAX - 26.0); // -40 resist: twenty-eight of twenty
    var f = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS);
    _ = f.hit(combat.Hit{ .elem = combat.elems(.{ .fire = 20 }) });
    try std.testing.expect(f.hp > HP_MAX - 17.0);
}

test "THE SURFACE TELL IS A BUILDING SPRAY, NOT A SWELLING DOME — the mound holds and the earth escalates" {
    var d = Delver.spawn(mathx.zero3, 0, 1.0, 0.3);
    d.enter(.surge);
    // THE MOUND DOES NOT MOVE. Its size is what says where the blow lands, and a dome that grows through the
    // tell is a promise that keeps changing.
    var rates: [3]f32 = undefined;
    for ([_]f32{ 0.1, 0.5, 0.95 }, 0..) |frac, i| {
        d.t = SURGE_DUR * frac;
        d.updateSurge(0);
        try std.testing.expectApproxEqAbs(MOUND_TRAVEL_R, d.moundR, 1e-5);
        try std.testing.expectApproxEqAbs(MOUND_TRAVEL_H, d.moundH, 1e-5);
        rates[i] = lerpF(SURGE_SPRAY_0, SURGE_SPRAY_1, d.surgeK);
    }
    // …AND THE SPRAY CLIMBS, hard, and MOST OF IT LATE (the curve's whole reason).
    try std.testing.expect(rates[1] > rates[0] * 2.0);
    try std.testing.expect(rates[2] > rates[1] * 3.0);
    try std.testing.expect(rates[2] > SURGE_SPRAY_1 * 0.85);
    std.debug.print("\n  delver surge: spray {d:.0} -> {d:.0} -> {d:.0} clods/s, mound held at r {d:.2}\n", .{ rates[0], rates[1], rates[2], d.moundR });
    // …and it is CLEARED when the move ends, or the next thing it does inherits the fountain.
    d.enterIdle(0.2);
    try std.testing.expectApproxEqAbs(@as(f32, 0), d.surgeK, 1e-6);
}

test "IT IS VICIOUS ON ITS FEET TOO — it runs him down and its stroke comes round again quickly" {
    // OVER THE HERO'S RUN so backing off costs ground, and UNDER his sprint so it is still breakable.
    try std.testing.expect(CHASE_SPEED > heromod.RUN_SPEED);
    try std.testing.expect(CHASE_SPEED < heromod.SPRINT_SPEED);
    // …and it walks HOME at the old amble: the speed is what it does about HIM, not how it moves.
    try std.testing.expect(WALK_SPEED < heromod.RUN_SPEED);
    // THE STROKE COMES BACK. A claw every 1.9 s off a body that could not close was a punching bag between
    // dives; the whole cycle now fits inside what the dive alone used to cost.
    const cycle = CLAW_WIND + CLAW_STRIKE + CLAW_RECOVER + CLAW_CD;
    try std.testing.expect(cycle < 2.2);
    // …but the TELL is untouched: faster may never mean harder to read (`foe.TELL_MIN`, and the parry).
    try std.testing.expect(CLAW_WIND >= foe.TELL_MIN);
    try std.testing.expect(foe.PARRY_LEAD < CLAW_WIND * 0.5);
    std.debug.print("  delver surface: chases {d:.2} m/s (hero runs {d:.2}, sprints {d:.2}), claw cycle {d:.2} s\n", .{
        CHASE_SPEED, heromod.RUN_SPEED, heromod.SPRINT_SPEED, cycle,
    });
}
