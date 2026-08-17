const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const heromod = @import("hero.zig");
const anim = @import("anim.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");
const archermod = @import("archer.zig"); // the dead man's own bone palette, chips and dissolve
const ogremod = @import("ogre.zig"); // …and the giant this one has to stand taller than
const propart = @import("propart.zig"); // the world's own ironwork, so his plate is the world's iron
const elemfx = @import("elemfx.zig"); // …and the elements' own language, for what phase two puts on the blade

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// NEAR-BLACK AND ONLY JUST COOL. A cuirass is the largest sunward face on the creature, so anything mid-dark
// comes back off it pale; what breaks it up is FORM, never a lighter tone. Everything outdoors here is warm,
// so the hue is what separates a mass this large — but past a B−R of about sixteen points it reads as BLUE
// ARMOUR, which is a costume. Gunmetal keeps the separation and still reads as worked metal.
// Solved through the chain's measured constant: screen ~ 22.7 x albedo^(1/2.2) on the chest, ~30.3 on the
// door, which faces the sun square. Shadowed plate to caught rim runs 43 -> 58 -> 80 -> 112.
const IRON = rgba(13, 15, 20, 255);
const IRON_LT = rgba(42, 46, 54, 255); // caught-light edges and rolled rims
const IRON_MD = rgba(22, 25, 31, 255); // the mid tone bands and courses read against the field in
const IRON_DK = rgba(6, 7, 10, 255); // the shadowed inside of a plate, and the seam between two
/// HIS OWN RUST, not the world's: the door's rim capsules are 2.5 m long, so `propart.RUST` lands at 178 on
/// screen — over the ground behind him and over his own plate, which inverts the value hierarchy and competes
/// with the visor's ember. Solved back down the chain to land near 120: still rust, no longer trim.
const RUST = rgba(24, 16, 10, 255);
const BRASS = rgba(66, 51, 22, 255); // fittings, gone dull
const STRAP = rgba(34, 26, 19, 255);
// THE BONE UNDERNEATH IS THE ARCHER'S — the same body at four times the mass, READ rather than transcribed.
const BONE = archermod.BONE;
const BONE_DK = archermod.BONE_DK;
const BONE_LT = archermod.BONE_LT;
/// **…BUT WHAT SHOWS ON THE OUTSIDE OF THE SUIT IS HIS OWN** (owner: more skeletal and scary). The archer's
/// bone is right on a bare skeleton lit from any angle and comes off THIS sun at 237 of 255 — which is why
/// the first pass at a Bone Knight read as litter scattered over a blue-black mass and got deleted. Deleting
/// it left a creature whose name is doing work the model refuses to: he is iron with a jawbone. Solved DOWN
/// the same chain the plate was, to land near 140 on his chest — over the plate's brightest rim (112) so it
/// reads as a different substance, under the ground (126) on hue so it never becomes the brightest thing in
/// the frame. Placed as FEW LARGE MASSES at the joints the plate has to gap at anyway, never as flecks.
const KBONE = rgba(57, 52, 44, 255);
const KBONE_LT = rgba(90, 83, 70, 255);
const KBONE_DK = rgba(30, 27, 23, 255);
/// THE ONE THING ON HIM THAT IS ALIVE: a cold ember down the visor slit. Low alpha IS the emissive channel,
/// so this is the only part of the creature that reads at night or in his own shadow.
const EMBER = rgba(228, 118, 52, 54);
const SOCKET = rgba(12, 10, 9, 255); // the dark behind the slit, so the helm reads as HOLLOW
/// …and the same fire on the GROUND, marking the disc the slam is about to bill (`slamRingTell`). Opaque
/// where the visor's is a low-alpha glow: this one has to be legible against lit dust in daylight, which is
/// the one thing the crater's tan-on-tan motes were not.
const EMBER_MARK = rgba(232, 122, 46, 235);

const DUST = foe.DUST;
const CHIP = archermod.BONE_CHIP;
const SPARK = rgba(255, 206, 126, 240);

/// **THE PLATE IS MATTE, AND THAT IS NOT A TASTE CALL.** `gfx.Mat.steel` carries a deliberately blinding
/// tight specular lobe (`shaders.zig`: "steel POPS"), which is exactly right on a blade and catastrophic on a
/// face the size of a door: the first pass authored the whole suit in it and the tower shield came back as a
/// blank white sheet with the creature invisible behind it. Blackened iron is matte anyway. `.steel` is kept
/// for what is SMALL AND PROUD — rims, rivets, quillons, the blade — which is where a glint says "metal".
const PLATE = gfx.Mat.plain;
const BRIGHT = gfx.Mat.steel;

/// The SWIPES' ribbon only. A shield bash points down the camera and has no edge to leave a wake.
// **SIZED AGAINST THIS CREATURE, NOT COPIED OFF THE WARRIOR.** These began as his dials, and on a blade this
// long sweeping 110 deg they came out as an opaque pale SHEET wider and taller than the knight — the
// feedback law's other failure exactly: it hid the creature it exists to point at, and a strip of the stroke
// showed four frames in which the swing was completely invisible behind its own wake. The AREA is not
// negotiable on a blade this long, so the three dials that are: span only the outer half of the edge, live
// well inside the stroke so the whole arc is never resident at once, and carry half the alpha. The sweep's
// tip covers ~200 deg at five metres, so the life is shorter again than the cleave's ever was.
const TRAIL_N = 24;
const TRAIL_LIFE = 0.13; // well under the strike, so what is on screen is a wake and not the whole sweep
const TRAIL_ROOT = 0.46; // fraction down the blade the ribbon spans from → the point
const TRAIL_PEAK = 88.0;

// THE SHARED 18-BONE SCAFFOLD (hero.zig). Only `hx`, `sx` and the stature are honestly this creature's; the
// joint layout is not transcribed here on purpose.
const N = heromod.N;
const ROOT = heromod.ROOT;
const SPINE = heromod.SPINE;
const CHEST = heromod.CHEST;
const NECK = heromod.NECK;
const SKULL = heromod.HEAD;
const HIPL = heromod.HIPL;
const KNEEL = heromod.KNEEL;
const ANKL = heromod.ANKL;
const HIPR = heromod.HIPR;
const KNEER = heromod.KNEER;
const ANKR = heromod.ANKR;
const SHL = heromod.SHL; // the SHIELD arm
const ELL = heromod.ELL;
const WRL = heromod.WRL;
const SHR = heromod.SHR; // the SWORD arm
const ELR = heromod.ELR;
const WRR = heromod.WRR;
const WPN = heromod.HELD;

const H: f32 = heromod.H;
const HIP_HALF = 0.112; // a broad base — he is a wall on legs
const SHOULDER_HALF = 0.216; // …and pauldrons wide enough to carry the door on one of them
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;
const setLocal = heromod.setHumanoid;

/// BIGGER THAN THE OGRE (owner's call), and DERIVED off him so the one fact that makes this creature what it
/// is cannot quietly stop being true the next time the giant's dial is walked. A test pins the crowns.
pub const SCALE = ogremod.SCALE * 1.28;

/// Where a sabaton meets the earth, MEASURED off `footMesh` — `hero.legChain` levels the ankle against this
/// every frame so the plate cannot rake through the ground.
const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.064 * H, .toe = 0.200 * H, .halfW = 0.063 * H, .drop = 0.041 * H },
    .{ .bone = ANKR, .heel = 0.064 * H, .toe = 0.200 * H, .halfW = 0.063 * H, .drop = 0.041 * H },
};

pub const AGGRO_R = 22.0; // he is a landmark: you are in his fight well before you are in his reach
/// SLOW OFF THE MARK AND SLOWER ROUND (owner: you have to keep getting behind him). This is the number the
/// whole creature is built on, and it is sized against the ANGULAR rate a walking player can carry round a
/// body this wide — which is small, because the radius is: at his own closest approach the hero circles him
/// at only 0.80 rad/s, so anything near a normal creature's turn (the ogre's 3.4) leaves him no back at all.
/// A test brackets it from above. At 33 deg/s a full about-face costs him five seconds.
/// **HE STILL LOSES A CONTINUOUS ORBIT, AND HE STILL SHOULD** — but the drift is no longer glacial, and
/// crucially it is no longer the only thing he can do about his own flank. The STEP-TURN is (`STEPTURN`).
/// Kept under the rate a walking hero carries round him (~0.80 rad/s at his closest approach) so circling
/// still WINS ground; what it no longer does is win it for free while he stands there like a lamp post.
const TURN_RATE = 0.68; // rad/s
/// …and this much while a stroke is already committed. STILL under `TURN_RATE` — commitment has to cost him
/// tracking or there is no window — but it was 0.40, and against a hero carrying 0.80 rad/s round him a
/// committed stroke shed 32 deg of bearing before it ever arrived, on top of whatever it committed at. So it
/// missed a walking player every time (owner: the swings don't often hit). A test measures the LATERAL miss at
/// the impact frame against the kit's own half-width rather than arguing about the rate.
const SWING_TURN = 0.55;
/// HOW FAST HE PUTS HIS BACK TO YOU as the fall loads. Deliberately the slowest of the three: the strip has
/// to be something a moving player can step out of, and this is the dial that decides how long he gets.
const FALL_AIM = 0.34;
/// A HAIR UNDER THE HERO'S OWN WALK (owner: inevitable). Backpedalling barely opens the gap and only a run
/// truly does — and the CHARGE is what a run buys. His strides are the shared gait at his own scale: 4.4 m
/// of ground a cycle, one footfall every second and a half. Cadence is what says five metres of mass.
const WALK_SPEED = heromod.WALK_SPEED * 0.94;

const BODY_R = 0.60; // ground footprint, pre-scale — broad
const HURT_R = 0.78; // the hurt sphere the hero's blade tests, pre-scale
/// WHERE THAT SPHERE IS CENTRED, in the PELVIS BONE's own frame. It is not a height off his feet, and that is
/// the whole point: he spends real seconds of every fight flat on his back, and a sphere pinned to 2.9 m would
/// hang in the air over a body lying on the ground. Read off the posed bone, it goes down when he does.
const CENTER_AT = v3(0, 0.02 * H, 0);
/// THE RETICLE RIDES THE CHEST, NOT THE SKULL — the ogre's rule and its reason: his crown is over five metres
/// up and a mark bolted to it would have the camera craning at the sky all fight.
const LOCK_AT = v3(0, -0.03 * H, 0);
/// …and the HP bar's anchor, off the HELM's own bone for `CENTER_AT`'s reason.
const TOP_AT = v3(0, 0.088 * H, 0);

// THE TOWER SHIELD. The creature IS this thing: everything else about him exists to make you walk round it.
//
// **IT IS WIDER THAN A MAN'S BOARDS AND IT DOES NOT BREAK** (owner). No stamina pool at all: a shield that
// breaks turns "get behind him" into "hit the front until it falls off", which is not this fight.
/// **DERIVED OFF THE DOOR, NOT CHOSEN** (owner: it blocks attacks beyond its visual). The half-angle the
/// door's widest chord subtends from his body axis, rounded DOWN so the picture is always at least as wide as
/// the mechanic — a bearing in doubt does not get blocked. A boundary the player cannot see reads as cheating,
/// and widening the board now widens the block by construction.
const TOWER_ARC = towerArc();
fn towerArc() f32 {
    // The wider chord against how far the door's FACE actually stands in front of his body axis — a real
    // triangle, so the answer is its angle. Measured this way the old 105 was not close: 2.7 m of plank
    // 0.8 m in front of him occludes about 35 deg either side, and he was eating blows from 105.
    const half = @max(SH_CHORD_L, SH_CHORD_R);
    const out = CHEST_FRONT_Z + SH_STANDOFF + SH_CURVE_R * @cos(SH_ARC_L);
    // …PLUS what the swept KIT is worth. `shielded` asks the bearing of the blade's own midpoint, and a
    // man at the edge of the door swinging two metres of steel puts that midpoint well inside it. This is
    // the one part that is not pure trigonometry, and it is small and named rather than baked into a
    // single hand-picked number the picture was never checked against.
    return combat.subtendedArc(half, out) + TOWER_SWEPT_ALLOW;
}
/// See `towerArc`. Deliberately modest: every degree here is a degree of blocking the player cannot see.
const TOWER_SWEPT_ALLOW = 17.0;
/// …and what it eats. Over the hero's own `GUARD_NEGATE` (0.85) on purpose: chipping him down from the front
/// is slow, and the only way to real DAMAGE is round the side.
const TOWER_NEGATE: f32 = 0.93;
/// **BUT THE DOOR DOES NOT EAT THE FOOTING** (the reference's stance loop — ELDEN_RING.md §7: 80 stance,
/// ~13/s regen, "~6 s of pressure window" ending in a critical). `combat.guardChip` is right for a man's
/// boards, where a caught blow is meant to be a non-event; on a wall with no stamina pool behind it, it meant
/// frontal pressure could never earn ANYTHING — no damage, no poise, no stance, forever — so the only
/// openings in the fight were the ones he handed out himself. A share of the stance comes through the wood:
/// the SHIELD still never breaks (owner's law) and the man behind it can be worn down to a stagger.
/// **AND IT IS A SLOW PLAN, NOT A FAST ONE** (owner: he stuns too easily). At 0.34 a third of every blow's
/// footing went through the wood, and against a `STANCE_MAX` sized for three PARRIES that meant a handful of
/// ordinary swings on the front broke a boss — the exact opposite of the wall this creature is. The pass-
/// through exists so frontal pressure earns SOMETHING rather than nothing; it is not meant to be the
/// efficient way through him, and flanking has to stay strictly better.
const TOWER_STANCE_PASS: f32 = 0.15;

/// THE SWIPE'S OWN OPENING — how far into the stroke the door has left his front, and how far into the
/// recovery it comes back. It opens INSIDE the first third: the blade lands at `impactK` 0.22-0.55, so a door
/// that waited for the impact frame would be shut for the whole beat the player is actually reading. And it
/// shuts LATE, over the back half of the recover, because the recovery IS the punish window and a wall that
/// re-forms the instant the blade stops has not paid for the stroke at all.
const SWIPE_OPEN_K: f32 = 0.30;
const SWIPE_SHUT_K0: f32 = 0.45;
const SWIPE_SHUT_K1: f32 = 0.90;
/// …and how far the arm actually carries it — the picture of the same channel, in the shoulder's own degrees.
/// The door comes DOWN off its guard height, ABDUCTS away from his chest and YAWS edge-on: three channels,
/// because one of them alone reads as a shrug rather than a wall being swung out of the way.
const SWIPE_SH: f32 = 26.0;
const SWIPE_ABD: f32 = 30.0;
const SWIPE_YAW: f32 = 46.0;

/// HOW FAR OFF DEAD-BEHIND THE HERO MUST BE for the fall to be worth throwing. NOT `TOWER_ARC`: the crush
/// strip is a STRIP, about a metre and a half either side of his spine, so at three metres out it subtends
/// nothing like the whole sector his shield cannot face. A MOVE THAT CANNOT LAND IS NOT A DECISION.
/// The gap between this and `TOWER_ARC` is the safe pocket, and it is his QUARTER rather than his back.
const FALL_SECTOR = 44.0;

/// …AND HOW FAR OFF HIS FACING A STROKE CAN LAND, for the same law one move up. Both his swings are aimed
/// down his own front — the bash goes straight forward and the swipes come across it — and neither is a
/// sector test, it is the SWEPT kit. At a bearing past this the kit simply travels past you, so a swing
/// chosen there is a second and a half spent on a guaranteed miss. He turns instead.
/// At 50 he committed from half a sector out and then DRIFTED, so the initial error and the drift added up to
/// a guaranteed miss. The drift is what the swing has to pay for; the error it starts with is free to refuse,
/// so he squares up properly first and turning is what he does instead.
const SWING_BEARING = 24.0;

// HIS POSES, AND THE MOVES AS SEQUENCES OF THEM.
//
// Everything below replaces pairs of `WIND_*`/`HIT_*` constants lerped by one `k`. A move is now a
// list of KEY POSES on a 0..1 clock that runs across the WHOLE move — wind, strike and recover as one
// track — which also retires the three-functions-that-must-agree-at-the-seams problem: `setSweepWind`
// ended where `setSweep` began only because someone kept them in step by hand.

const Chan = [Knight.CHAN_N]f32;

/// A POSE, written as edits to his GUARD. Defaults are what he stands in, so a key says only what MOVES —
/// which is how a pose reads as a pose rather than as twelve numbers.
const P = struct {
    brace: f32 = 0.16,
    lean: f32 = GUARD_LEAN,
    twist: f32 = GUARD_TWIST,
    head: f32 = 3.0,
    armSh: f32 = CARRY_SH,
    offSh: f32 = GUARD_SH,
    armAbd: f32 = CARRY_ABD,
    offAbd: f32 = GUARD_ABD,
    armSweep: f32 = 0,
    armEl: f32 = CARRY_EL,
    offEl: f32 = GUARD_EL,
    tilt: f32 = CARRY_TILT,

    pub fn chan(self: P) Chan {
        var c: Chan = undefined;
        c[Knight.CH_BRACE] = self.brace;
        c[Knight.CH_LEAN] = self.lean;
        c[Knight.CH_TWIST] = self.twist;
        c[Knight.CH_HEAD] = self.head;
        c[Knight.CH_ARM_SH] = self.armSh;
        c[Knight.CH_OFF_SH] = self.offSh;
        c[Knight.CH_ARM_ABD] = self.armAbd;
        c[Knight.CH_OFF_ABD] = self.offAbd;
        c[Knight.CH_ARM_SWEEP] = self.armSweep;
        c[Knight.CH_ARM_EL] = self.armEl;
        c[Knight.CH_OFF_EL] = self.offEl;
        c[Knight.CH_TILT] = self.tilt;
        return c;
    }
};

/// ONE KEY OF A MOVE: when, what pose, and how it is arrived at from the key before it. The key type and
/// the sampler are `anim.Pose`'s — shared, so a second creature's tracks cannot drift off this one's.
const PoseKey = anim.Pose(P).PoseKey;
const samplePose = anim.Pose(P).sample;

/// **THE SPRING THE WHOLE BODY HANGS OFF.** Under-damped on his feet, so a pose he takes carries past its
/// rest and settles back onto it — the reactions law, as a property of the rig rather than something each
/// move has to remember. `FALLOFF` is what makes the mass flow outward: each channel down the root→tip list
/// is pulled a little less hard than the one before it, so the blade arrives after the arm, which arrives
/// after the trunk. Tuned on the stroke strips, which is the only place a number like this is ever right.
/// **AND IT MUST BE STIFF ENOUGH TO TRACK THE FASTEST THING HE DOES** (owner: his shield bash is goofy,
/// his arm doesn't move?). It was 340, which is a natural period of 0.34 s — LONGER than the bash's whole
/// 0.22 s strike. The spring could not follow the stroke at all: the arm set off, got a third of the way,
/// and the move was over. A hundred and twelve degrees of shoulder swing arrived on screen as a twitch.
/// A spring layer under an animation has to be fast enough to be a WEIGHT on the pose, not a replacement
/// for it — the period belongs well inside the shortest strike, and the overshoot comes from `zeta`.
const SPRING_STIFF: f32 = 1900.0; // period ~0.14 s, comfortably inside the 0.22 s bash
const SPRING_ZETA: f32 = 0.72; // under 1: it overshoots. Weight lives just under 1.
const SPRING_FALLOFF: f32 = 0.94;
/// …and OFF HIS FEET he is one rigid thing meeting the ground. Critically damped and stiffer, or five
/// metres of armour lying on the earth wobbles like aspic.
const SPRING_STIFF_DOWN: f32 = 2800.0;

/// A MOVE'S ANIMATION, as three keyed tracks on the three clocks the mechanics already run. Kept as three
/// rather than one track over the whole move because the PHASE BOUNDARIES are mechanical — the wind's
/// length varies (`windHold`, `STRING_WIND_MUL`), the strike's does not, and the impact frame is billed at
/// `strikeDur * impactK` — so one normalised clock would slide the pose off the beat it belongs to.
///
/// **THE SEAMS ARE PINNED BY A TEST**: a phase's first key must equal the previous phase's last. Three
/// functions that only lined up because somebody kept them in step by hand is exactly how `setSweepWind`
/// and `setSweep` drifted apart.
const MoveKeys = struct {
    wind: []const PoseKey,
    strike: []const PoseKey,
    recover: []const PoseKey,
};

/// **HOW HARD A MOVE HITS, SAID OUT LOUD** (owner: light and heavy, I can't tell the difference here).
/// The reference's own rule is "one unique gross silhouette per attack", and this creature broke it: every
/// gather was the same dust, the same clock shape and the same body language, so the only way to know
/// whether the thing coming at you cost 22 or 40 was to have already been hit by it. That is memorisation
/// of a LOOKUP TABLE, not of a fight.
///
/// A move's weight is now declared, and three channels say it before the blow arrives — the GATHER's fire
/// (heavies pull ember up off the ground and lights do not), the wind's length, and the depth of the brace.
/// The player learns one rule — *fire means get out, no fire means you can trade* — and every move in the
/// kit resolves under it.
const Weight = enum {
    /// Quick, cheap, thrown from behind the wall: the thrust and the bash. Trade with these.
    light,
    /// Committed, expensive, and they open his own guard: the sweeps. Step out or punish.
    heavy,
    /// The ones that end in the earth and cost you the fight if you eat them: the overhead, the slam, the
    /// charge, the fall. These are the ones the ember is really for.
    crushing,

    fn ember(self: Weight) f32 {
        return switch (self) {
            .light => 0,
            .heavy => 0.55,
            .crushing => 1.0,
        };
    }
};

const Attack = struct {
    /// The AI's TRIGGER RANGE and the parry window's reach — pre-scale, MEASURED off the posed kit at the
    /// impact frame (a test at the foot of this file re-measures it). What the blow actually HITS is the swept
    /// kit, so this can never grow a hurt box the stroke never enters.
    reachOut: f32,
    windDur: f32,
    strikeDur: f32,
    /// Fraction into the stroke the kit goes live.
    impactK: f32,
    recoverDur: f32,
    cd: f32,
    hit: combat.Hit,
    /// What the gather TELLS the player it is worth. A test pins it against the row's own damage, so a move
    /// can never quietly advertise itself as something it is not — which is the whole failure this fixes.
    weight: Weight,
    /// **HOW FAR OFF SQUARE THIS MOVE MAY BE THROWN** (owner: his front-facing attacks must cover his front).
    /// PER MOVE, because the honest limit is what that stroke's own kit sweeps: the BASH keeps the tight door
    /// (`SH_RAM_HALF` subtends 26 deg at the range it arrives, and a ram thrown wider is thrown at nothing),
    /// while the SWORD moves get the front they can genuinely reach across. One number for the whole kit left
    /// the safest square on the board directly in front of the boss.
    bearing: f32,
};

// THE KIT IS THE ANOR LONDO SENTINEL'S (docs/GIANT_KNIGHTS.md), five weapon strokes and a slam, run on the
// Elden Ring knight brain (docs/ELDEN_RING.md §7): distance bands + dice odds, the guard held THROUGH the
// sword moves, and roll-catch timing living in the FOLLOW-UPS (the delayed second sweep, the thrust's
// quick-swing chain, the overhead's hitched drop) rather than in faster winds.

/// THE SWEEP — the right-to-left scything arc, thrown one-handed with the door still on his front. It is
/// deliberately WIDE of his facing (the Sentinel's sweep "can strike players even behind them"): the whole
/// torso swings through, so it is his answer to being circled as much as to being faced.
const SWEEP = Attack{
    .reachOut = 1.92, // MEASURED: the point crosses 5.65 m out across the stroke
    // LONGER, AND BOTH ASKS ARE THE SAME ASK: a sweep that covers his whole front has further to turn to
    // aim, and a sweep you can READ is one whose gather you get to see. The bearing it may be started from
    // is sized off this (`SWEEP_BEARING`), so the two may not drift apart.
    .windDur = 1.00,
    .strikeDur = 0.42, // ~200 deg of arc needs real travel time, or the whip is invisible
    .impactK = 0.22, // live early: the arc IS the hit, not one frame at its end
    .recoverDur = 1.35,
    .cd = 3.60,
    .hit = SWEEP_HIT,
    .weight = .heavy,
    .bearing = SWEEP_BEARING, // its arc reaches past his own far shoulder
};

/// …AND THE SECOND SWEEP, SAME DIRECTION, chained on a roll — the Sentinel's own authored roll-catch: the
/// second "is slightly delayed and will chop you down if you roll too early". Also what the THRUST chains
/// into ("may be followed up with a quick horizontal swing"). Never chosen on its own.
const SWEEP2 = Attack{
    .reachOut = 1.90,
    // "slightly delayed" — a re-cock long enough to be a real tell, short enough to catch a hasty roll. It
    // came down with the rest of the kit but has a FLOOR: `foe.PARRY_LEAD` (0.18 s) may never be more than
    // a fifth or so of a wind, or the window stops being an instant and becomes a slice of the telegraph.
    .windDur = 0.48,
    .strikeDur = 0.34,
    .impactK = 0.25,
    .recoverDur = 1.40,
    .cd = 3.60, // shares the sweep's clock, dealt when the CHAIN ends — a double costs more rest
    .hit = SWEEP2_HIT,
    .weight = .heavy,
    .bearing = SWEEP_BEARING,
};

/// THE OVERHEAD SLAM — the big one: "a bit of a wind up, easier dodged than blocked", with the Godrick
/// knights' DELAYED DOWNSWING rolled onto it (`windHold`), and "very poor tracking" once launched — the
/// strike turns not at all, so committing to a line is the price of the damage.
const OVERHEAD = Attack{
    .reachOut = 1.83, // MEASURED off the posed tip across the stroke: 5.37 m — the drop's follow-through
    // carries the blade a little past where the old two-pose lerp stopped it, and the declared reach is
    // re-measured rather than argued (the test at the foot of this file walks the stroke frame by frame).
    .windDur = 0.88,
    .strikeDur = 0.30,
    .impactK = 0.55,
    .recoverDur = 1.50, // the blade ends in the earth and stays there a beat — the End Pose IS the window
    .cd = 4.50,
    .hit = OVERHEAD_HIT,
    .weight = .crushing,
    // A falling blade crosses his whole front on the way down; it does not need to be aimed at his nose.
    .bearing = 42.0,
};

/// THE THRUST — "longest range of them all, only used when no other attacks will reach": the mid-range
/// answer, the gap-filler between the big cooldowns (its own clock is the shortest he has), and the GUARD
/// COUNTER — a blow caught on the door may be answered with exactly this, at once (`riposteArm`).
const THRUST = Attack{
    .reachOut = 1.70, // MEASURED off the posed point alone: 4.99 m — the LUNGE is on top (`thrustBandR`)
    .windDur = 0.50,
    .strikeDur = 0.26,
    .impactK = 0.55,
    .recoverDur = 0.95,
    .cd = 1.80,
    .hit = THRUST_HIT,
    .weight = .light,
    // A point can be aimed, and the lunge behind it carries him onto the line.
    .bearing = 38.0,
};

/// WHERE THE THRUST CAN BE CHOSEN FROM: the posed point PLUS the lunge under it — "longest range of them
/// all, only used when no other attacks will reach" has to be true of the band, and the lunge is half the
/// band. One helper, read by `classify`, `longestTrigger` and the tests alike.
fn thrustBandR(scale: f32) f32 {
    return triggerR(THRUST, scale) + THRUST_STEP * scale;
}

/// THE SHIELD BASH — the proximity tax (the Tower Knight's boot, the Crucible's shield shove): quick,
/// short, knocks you off his boots. The answer to hugging the wall.
const BASH = Attack{
    .reachOut = 0.78, // MEASURED: the door's own face, pulled onto his chest, arrives 2.29 m off his axis
    .windDur = 0.54,
    .strikeDur = 0.22,
    .impactK = 0.44,
    .recoverDur = 0.85,
    .cd = 2.60,
    .hit = BASH_HIT,
    .weight = .light,
    // THE ONE THAT STAYS TIGHT: SH_RAM_HALF subtends 26 deg at the range it arrives, and the bowed
    // edges cannot be driven into anybody — a ram thrown wider than its own face is a ram thrown at air.
    .bearing = 26.0,
};

/// **THE SWAT — HIS SIDES ARE NOT FREE ANY MORE** (owner: quick swipes with shield or sword depending on
/// side; his side is too vulnerable). Everything he owned was aimed down his FRONT and took the better part
/// of a second to arrive, so standing off either shoulder was a place you could live: the pivot step and the
/// sweep both take real time, and a player who kept pace with them simply stayed there.
///
/// This is the short answer. One row, ONE clock, and TWO pictures picked by which side you are on — the door
/// backhanded across on the shield side, the blade flicked out low on the sword side. It is the quickest
/// thing he does by a distance, it barely reaches, and it does almost nothing: it exists to make you MOVE,
/// which is what having a flank cost him before.
const SWAT = Attack{
    // MEASURED at 4.96 m. **IT IS QUICK, NOT SHORT** — and that distinction is the honest one: the blade is
    // three metres of rigid steel bolted to his wrist, so even with the elbow shut the tip covers ground.
    // What makes this a flick is the CLOCK (a third of a second of gather against the sweep's four fifths)
    // and the damage, not the radius. The shield-side picture is genuinely short; the sword side is a long
    // arm moving fast, which is exactly what a greatsword backhand is.
    .reachOut = 1.69,
    // **IT IS READ, NOT REACTED TO** (owner: swipes should be tricky to dodge due to TIMING, not due to
    // coming out near-instantly — "fuck that"). At 0.34 it sat on `foe.TELL_MIN` and the honest answer to it
    // was to already be rolling, which is not a read, it is a coin. The gather is now plainly visible; what
    // makes it hard is WHEN it lands (`SWAT_HANG`), not that it arrives before you can see it.
    .windDur = 0.52,
    .strikeDur = 0.16,
    .impactK = 0.40,
    .recoverDur = 0.42,
    .cd = 1.50,
    .hit = SWAT_HIT,
    .weight = .light,
    // The widest, because it is the SIDE answer: it exists to reach what the front moves cannot.
    .bearing = FLANK_BEARING,
};
pub const SWAT_HIT = combat.Hit{ .dmg = 14, .poise = 22, .stance = 6 };

pub const SWEEP_HIT = combat.Hit{ .dmg = 30, .poise = 42, .stance = 14 };
pub const SWEEP2_HIT = combat.Hit{ .dmg = 26, .poise = 36, .stance = 12 };
pub const OVERHEAD_HIT = combat.Hit{ .dmg = 40, .poise = 50, .stance = 20 };
pub const THRUST_HIT = combat.Hit{ .dmg = 22, .poise = 26, .stance = 8 };
pub const BASH_HIT = combat.Hit{ .dmg = 27, .poise = 36, .stance = 12 };

// THE SHIELD SLAM — the Sentinel's, verbatim: "long build up time, mega damage and a small AoE", and it
// "leaves a huge opening". The door is hauled UP off his front — the one silhouette nothing else he does
// has, and the ONE time the wall leaves the fight — and driven into the earth ahead of him, the blow a
// disc round the crater (reaching a little past his own feet, the Tower Knight's rear-reaching slam).
// **A RUN CLEARS IT AND A WALK DOES NOT** (the delver's law, tested below with the hero's own speeds).
const SLAM = struct {
    windDur: f32, // the haul UP — long, and the front is open for the whole of it
    strikeDur: f32,
    impactK: f32, // fraction into the drive the earth answers
    recoverDur: f32, // "leaves a huge opening" — the longest recover on his feet
    cd: f32,
    fwd: f32, // pre-scale: how far ahead of his axis the crater lands
    r: f32, // pre-scale radius of the blow around it
    hit: combat.Hit,
}{
    // Shortened with the rest of the kit (owner: the wind-ups are too long) but NOT as far: this one is
    // bracketed from below by its own counter — a RUN has to clear the crater's disc inside the tell, and a
    // walk deliberately must not (the delver's law, measured against the hero's own speeds in a test).
    .windDur = 1.22,
    .strikeDur = 0.42,
    .impactK = 0.50,
    .recoverDur = 1.70,
    .cd = 8.00,
    .fwd = 0.62,
    .r = 1.28,
    .hit = SLAM_HIT,
};
pub const SLAM_HIT = combat.Hit{ .dmg = 34, .poise = 52, .stance = 24 };

// **PHASE TWO — HE CHARGES THE SWORD** (owner: at half health, have him lift his sword and charge it with
// chaos particles; in this phase his attacks do AoE impacts).
//
// The reference's own way of doing this is the Tree Sentinel's: the phase turn is announced by ONE FIXED
// SIGNATURE MOVE at an exact HP fraction, so it is an event the player recognises rather than a gradual
// drift they only notice afterwards. This is that move — he plants, hauls the blade up over the helm and
// holds it while CHAOS gathers onto the steel, and from then on every blow he lands opens a burst of it.
//
// It is a full stop, and a long one: it is the biggest free window in the fight, deliberately, because the
// second half of the fight is harder and the player should be paid for reaching it. Nothing about it is a
// surprise — the bar is right there and the awakening cannot be interrupted.
const AWAKEN = struct {
    /// The HP fraction it fires at. Half, exactly (owner).
    at: f32,
    liftDur: f32, // the blade going up
    holdDur: f32, // …and the charge itself, which is the window
    settleDur: f32,
}{
    .at = 0.5,
    .liftDur = 0.70,
    .holdDur = 1.45,
    .settleDur = 0.55,
};

// **AND IT HAS ITS OWN TOP POSE** (owner: he holds the sword too far back when charging for phase two). It
// borrowed the OVERHEAD's wind, which is a headsman's cock-back and wrong for this on every channel: the
// elbow folded to −32 lays the blade back OVER the helm, the trunk arched 20 deg further behind it, and the
// helm itself then sits in front of the one thing the move exists to show. A charge has to be SEEN. So the
// arm goes up nearly STRAIGHT and the steel stands PLUMB in front of the crown, where the chaos gathering on
// it is against the sky instead of behind his own head.
const AWK_SH = -160.0; // up, a hair forward of vertical rather than past it
const AWK_EL = -4.0; // …and the elbow OPEN: this is what was laying the blade back
const AWK_ABD = 3.0; // pulled in over his centre line, not out on the arm's own plane
const AWK_TILT = 24.0; // rakes the blade back onto plumb against the arm's forward lean
const AWK_ARCH = 7.0; // deg the trunk gives back under it — a body taking a weight, not a limbo

/// **WHAT THE CHAOS ADDS TO EVERY BLOW ONCE HE IS LIT.** A disc round the impact, on top of whatever the
/// stroke already did — so the phase changes the SPACING of the fight rather than just its numbers: in
/// phase one you may stand just outside a swing, and in phase two that ground belongs to the blast.
/// Deliberately light on damage and heavy on radius, because the point is where you have to be, not how
/// much it takes.
const CHAOS_BLAST = struct {
    r: f32, // pre-scale radius round the impact point
    hit: combat.Hit,
}{
    .r = 0.62,
    .hit = .{ .dmg = 9, .poise = 18, .stance = 5, .elem = combat.elems(.{ .chaos = 11 }) },
};

// **THE HEAVY ONES LEAVE SOMETHING STANDING** (owner's phase two). The blast taxes where you ARE; this taxes
// where you may STAND, so a stroke that missed still fouls the ground it hit.
//
// **WHICH ATTACKS IS THE `Weight` RULE, NOT A LIST** — what leaves gas is what showed FIRE on the gather,
// which is the tell the player has already learned. The FALL and the CHARGE are excluded though both show it:
// each is a position-denial move whose counter IS ground, so fouling where it ends taxes its own answer. The
// rule is "what showed fire and STOPPED somewhere".
pub const GAS_LIFE: f32 = 4.2;
/// The fraction of that life it HANGS at full before it starts going out. Past this it thins on every
/// channel at once (`fade`).
const GAS_HANG: f32 = 0.42;
/// Pre-scale, and DELIBERATELY under the blast's own reach: the disc is the tax for being there, this is the
/// tax for staying. A hazard you cannot walk out of is not a hazard, it is a smaller arena.
pub const GAS_R: f32 = 1.00;
const GAS_GROW: f32 = 0.40;
/// **THREE, NOT FIVE.** The cap is what the ground looks like at worst, not a pool size: five overlapping
/// clouds is a floor, and the move is supposed to shape where you stand rather than replace it.
const GAS_CAP: usize = 3;
/// It DOSES rather than draining. Poison buildup may be continuous (`shroom.spores`) because the meter it
/// feeds is drawn every frame; damage may not — a per-frame nibble is a hurt beat, a flash and a rumble
/// sixty times a second. So it arrives in bites you can count, and one clock serves the whole field: standing
/// in two clouds is one bad decision, not two.
const GAS_DOSE_EVERY: f32 = 0.55;
const GAS_HIT = combat.Hit{ .dmg = 6, .poise = 0, .stance = 0, .elem = combat.elems(.{ .chaos = 8 }) };
/// No poise and no stance ON PURPOSE: a hazard that staggers is a hazard that can kill you while you are not
/// allowed to move, and the counter to standing in gas has to be walking out of it.
/// **A VOLUME, NOT A SPARKLE — AND NOT A WALL OF BEACH BALLS.** The motion and the hue stay chaos's; the
/// SIZE, the DWELL and the DENSITY are the cloud's. Chaos's own mote is alpha 210 because a spark is a bright
/// hard point, and at cloud size that same alpha is an opaque sphere that buries the boss behind it.
const GAS_ALPHA: u8 = 104;
const GAS_RATE: f32 = 68.0;
const GAS_PUFF_LO: f32 = 1.15;
const GAS_PUFF_HI: f32 = 1.90;
const GAS_H: f32 = 1.35; // …and it stands to his own waist: a knee-high haze is something you step over
const GAS_DRIFT: f32 = 0.26; // m/s inward — chaos GOES THE WRONG WAY, and at a cloud's pace, not a spark's
const GAS_PARTS = 132;
comptime {
    std.debug.assert(@as(f32, @floatFromInt(GAS_PARTS)) >= GAS_RATE * GAS_PUFF_HI);
    std.debug.assert(GAS_HIT.poise == 0 and GAS_HIT.stance == 0);
}

/// Chaos's own hue at the cloud's density — the one thing a call site is allowed to move, and `f` is how
/// much cloud is left (`Gas.fade`), so a mote laid late is born fainter than one laid at full hang.
fn gasTint(c: rl.Color, f: f32) rl.Color {
    const a: f32 = @as(f32, @floatFromInt(GAS_ALPHA)) * mathx.clampF(f, 0, 1);
    return rl.Color{ .r = c.r, .g = c.g, .b = c.b, .a = @intFromFloat(a) };
}

/// ONE CLOUD. `shroom.Cloud`'s shape — grow, hang, thin — in chaos rather than spores, and the motion is
/// `elemfx`'s own signature for the element: chaos GOES THE WRONG WAY, so these are laid on the rim and fall
/// INWARD. That is the one thing that tells it apart from the sporeling's cloud with the colour taken away.
pub const Gas = struct {
    pos: rl.Vector3 = mathx.zero3,
    scale: f32 = 1.0,
    t: f32 = 0,
    live: bool = false,
    parts: [GAS_PARTS]foe.Particle = [_]foe.Particle{.{}} ** GAS_PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0x6A50),

    /// **HOW MUCH CLOUD IS LEFT** — 1 while it hangs, 0 where it ends, and it drives the RATE, the ALPHA and
    /// the RADIUS together (owner: they seemingly don't dissipate). The first pass thinned only the radius
    /// and only over the last 0.8 s, while emitting at full rate and full alpha right up to the cut: so it
    /// stood there at full strength and then stopped, which reads as a cloud that never goes out — and with
    /// a heavy stroke every few seconds, five of them overlapping never let the ground look clear.
    ///
    /// **AND IT IS ALSO THE MECHANIC'S OWN END**, so what you can see and what can hurt you agree: the disc
    /// stops covering at `GAS_LIFE`, and by then there is almost nothing drawn to walk into.
    fn fade(self: *const Gas) f32 {
        return 1.0 - mathx.smoothstep(GAS_LIFE * GAS_HANG, GAS_LIFE, self.t);
    }
    pub fn radius(self: *const Gas) f32 {
        const grow = mathx.smoothstep(0, GAS_GROW, self.t);
        return GAS_R * self.scale * grow * (0.55 + 0.45 * self.fade());
    }
    pub fn covers(self: *const Gas, p: rl.Vector3) bool {
        return self.live and self.t < GAS_LIFE and mathx.distXZ(self.pos, p) <= self.radius();
    }
    pub fn update(self: *Gas, dt: f32) void {
        // BEFORE the live gate (`brood.Pool.update`'s rule): a puff laid on the cloud's last frame still has
        // up to `GAS_PUFF_HI` to run, and a pool nobody ticks again is one frozen in the air until the slot
        // is reused — three heavy strokes away, or never.
        foe.tickParticles(&self.parts, dt, self.pos.y);
        if (!self.live) return;
        self.t += dt;
        if (self.t >= GAS_LIFE) {
            self.live = false;
            return;
        }
        // Laid on the RIM and drawn in — the cloud says where it stops (the sporeling's lesson: a gradient
        // has no line to be on the safe side of) and then churns, which is chaos's own inward signature.
        const s = elemfx.sig(.chaos); // the COLOUR is never picked at a call site (elemfx's law)
        // THE RATE AND THE ALPHA GO OUT WITH THE RADIUS. Thinning only the disc while still laying motes at
        // full density is what made it read as permanent.
        const f = self.fade();
        self.fxAccum += GAS_RATE * f * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            // ONE IN THREE ON THE RIM, the rest THROUGH the disc — the sporeling's rule, and the first pass
            // here kept only the rim half of it: a ring of motes with nothing inside reads as scattered
            // litter, not as a volume. `@sqrt` because a uniform radius crowds the middle of a disc.
            const rim = self.fxRng.float() < 0.34;
            const rr = self.radius() * (if (rim) self.fxRng.range(0.88, 1.0) else @sqrt(self.fxRng.float()) * 0.86);
            const dir = v3(mathx.cosf(a), 0, mathx.sinf(a));
            const from = v3(
                self.pos.x + dir.x * rr,
                self.pos.y + self.fxRng.range(0.05, GAS_H * self.scale),
                self.pos.z + dir.z * rr,
            );
            foe.emitParticle(
                &self.parts,
                &self.fxHead,
                from,
                v3(-dir.x * GAS_DRIFT, self.fxRng.range(-0.03, 0.09), -dir.z * GAS_DRIFT),
                self.fxRng.range(GAS_PUFF_LO, GAS_PUFF_HI),
                self.fxRng.range(0.12, 0.20),
                self.fxRng.range(0.26, 0.38),
                gasTint(if (self.fxRng.float() < 0.34) s.edge else s.core, f),
                0, // chaos obeys nothing, the ground included
            );
        }
    }
    pub fn drawFx(self: *const Gas) void {
        foe.drawParticles(&self.parts);
    }
};

// **THE LEAP — HE LEAVES THE GROUND TO GET HIS FRONT BACK** (owner's). The pivot step answers a flank on the
// ground; this answers having ALREADY lost the argument — caught with his back to you and nothing gathered,
// he coils, bounds away, turns in the air and lands squared. It re-faces and re-spaces in one beat.
//
// **AND IT COSTS HIM HIS OWN REACH**, so reading the coil buys a free approach rather than a punish — which is
// what stops a get-out-of-jail move being strictly good. A LEAP in the roots' sense (`foe.canLeap`): a
// creature held by the ankles cannot leave the earth.
const LEAP = struct {
    windDur: f32, // the coil — deep, and the one frame that says it is coming
    flightDur: f32,
    landDur: f32,
    dist: f32, // pre-scale metres of ground he puts between you
    rise: f32, // …and how far off the earth he actually gets
    cd: f32,
    /// How much faster he may turn ACROSS the flight. The re-face IS the move, so this is generous — but it
    /// only applies here, and between leaps he is as out-turned as ever.
    turnMul: f32,
}{
    .windDur = 0.30,
    .flightDur = 0.46,
    .landDur = 0.32,
    .dist = 1.45,
    .rise = 0.40,
    // **HE REACHES FOR IT OFTEN** (owner: make him more inclined to jump to reposition). At 7 s it was a
    // once-a-fight curiosity; at this it is a real part of how he holds his ground, and it is the fastest
    // re-face he owns. It still costs him his reach every time, so leaning on it is a trade and not a tic.
    .cd = 3.6,
    .turnMul = 5.5,
};

// **THE STEP-TURN — HE PROTECTS HIS SIDES, AGGRESSIVELY** (owner: he needs to step aggressively and turn
// fast; step-turn; he needs to protect his sides more aggressively).
//
// How a man carrying five metres of armour ACTUALLY changes which way he is pointing: plant the near foot,
// drive off the far one, swing the whole mass round in one committed beat.
//
// **IT IS NOT A TURN-RATE BUFF.** Between step-turns he is as out-turned as ever, so the flank is still real
// — what has gone is holding it standing still. It costs him a plant you can hear, a cooldown and no blow on
// the end, so a player who keeps MOVING makes him spend it and then owns the side he stepped away from.
const STEPTURN = struct {
    windDur: f32, // the load onto the plant foot — short, but it is a tell
    turnDur: f32, // …and the drive round
    settleDur: f32,
    /// The most bearing one step may eat, in degrees. Sized so a step CLOSES a flank but does not reach the
    /// back: getting behind him still takes more than one of his mistakes.
    sweep: f32,
    /// …and the least that is worth spending one on. Under this he just drifts, which is what `TURN_RATE`
    /// is for — a step-turn to trim four degrees would read as a twitch.
    least: f32,
    cd: f32,
}{
    .windDur = 0.22,
    .turnDur = 0.30,
    .settleDur = 0.24,
    .sweep = 62.0,
    .least = 22.0,
    .cd = 1.15,
};
/// Degrees the SHOULDERS lead the hips through the pivot and unwind back onto them. A turn where the trunk
/// and the feet arrive together is a turntable; a body leads with its shoulders and is dragged after them.
const STEP_LEAD = 26.0;

/// **HOW MUCH OF THE COIL A CHAINED LEAP SKIPS** (owner: the swipe-and-leap on his side should be a bit
/// faster and more evil). Off a swat he is already low and loaded — the flick did the gathering — so the
/// two moves run as ONE beat and the player gets no gap to answer in. Thrown cold the leap keeps its full
/// tell, because five metres of armour leaving the ground out of nowhere is what this game's laws refuse.
const LEAP_CHAIN_WIND: f32 = 0.34;

/// **HOW OFTEN A FLANK BLOW GETS ANSWERED** (`counterFlank`). Short enough that hitting his side is a
/// conversation rather than a free lunch, long enough that a flurry does not lock him into countering
/// forever — the window you earn by staggering him has to stay worth more than the one you get for poking.
const COUNTER_CD: f32 = 1.9;

/// How much further than its own trigger the SWAT will reach for somebody actively ORBITING him. Over 1
/// because a circler is moving across his front and the flick is thrown where he will BE — and because the
/// whole point is that an orbit cannot be held for free at any radius the flick can touch.
const SWAT_ORBIT_BAND: f32 = 1.2;

/// Radians a second of bearing sweep that counts as being ORBITED. Under the 0.80 rad/s a walking hero
/// carries at the knight's own closest approach, so honest circling trips it and drifting does not.
const CIRCLE_RATE: f32 = 0.45;

/// **WHAT IT TAKES TO MAKE HIM MOVE HIS FEET INSTEAD OF SWINGING** (owner: he jumps a bit too often;
/// sometimes he should simply attack more rather than reposition — and he should reposition if he's taking
/// heavy damage in his current position). A share of his own bar, taken where he is STANDING (`foe.Sense`).
///
/// It exists because being circled was the ONLY reason he ever left a spot, and orbiting him is what a
/// player does all fight — so the hop came up on a clock rather than on a reason, and it read as a tic. Now
/// the same orbit against a knight nobody is hurting is answered with the kit (the swat is already written
/// for exactly that), and the ground answers are what being HURT here buys. 12 % is about two hero heavies
/// or a committed light string inside one `PRESSURE_HALFLIFE` — enough that trading with him moves him, not
/// so much that a poke does.
const REPOSITION_AT: f32 = 0.12;

// THE SIDESTEP HOP — the Sentinel's liveliness: "surprisingly quick to respond to your movements, often
// jumping out of the way". One discrete weight shift sideways that re-squares him on a circling player —
// NOT a turn-rate buff: between hops he is still the most out-turned thing in the game, so the flank still
// exists; the hop is what keeps holding it from being a statue you orbit.
const HOP = struct {
    windDur: f32, // the knee-dip gather
    airDur: f32, // the shift itself
    settleDur: f32,
    dist: f32, // pre-scale ground covered sideways
    cd: f32,
    turnMul: f32, // how much faster he may turn across the hop — the hop IS the re-face
}{
    .windDur = 0.34,
    .airDur = 0.30,
    .settleDur = 0.42,
    .dist = 0.55,
    .cd = 5.0,
    .turnMul = 3.4,
};

// THE CHARGE — the answer to staying away (owner's ask). Stand out of his reach long enough and he lowers
// behind the door and comes THROUGH where you were standing: a wall arriving at twice a sprint.
// **THE LINE IS COMMITTED AT THE LAUNCH** (the delver's plough, standing up): the wind tracks, the travel
// does not, so the counter is the SIDESTEP — a walking player clears the ram's width with seconds to spare,
// and a player who only ever runs straight away is exactly who it catches.
const CHARGE = struct {
    windDur: f32,
    speed: f32, // world m/s at full tilt
    accel: f32, // seconds to reach it
    overrun: f32, // metres past where you STOOD that he keeps going — he cannot stop a wall on a mark
    range: f32, // the most ground a charge may ever cover
    brakeDur: f32, // the skid at the end of it
    recoverDur: f32,
    cd: f32,
    far: f32, // he is being kept at range when you are past this…
    patience: f32, // …for this long, accumulated
    hit: combat.Hit,
}{
    .windDur = 0.78,
    .speed = 7.6,
    .accel = 0.35,
    .overrun = 2.6,
    .range = 26.0,
    .brakeDur = 0.85,
    .recoverDur = 1.05,
    .cd = 9.0,
    .far = 10.5,
    .patience = 4.0,
    .hit = CHARGE_HIT,
};
pub const CHARGE_HIT = combat.Hit{ .dmg = 32, .poise = 52, .stance = 22 };
/// THE HARDEST THING TO READ, SO VERY NEARLY THE LIGHTEST HIT HE HAS (owner: it must not be a one-shot).
///
/// **AND THE ONE-SHOT WAS NEVER THIS NUMBER** (owner's own read: the fall and the AoE hit at once). It was
/// `tryCrush` running unlatched — `dealt` guarded the thud, the shake and the dust and not the BLOW, so the
/// strip re-armed `heroHit` every frame from the impact to the end of the fall and billed this a dozen-plus
/// times in a third of a second. Cutting the damage would only have made the multi-hit cheaper; the fix is
/// at the call site and the number is now free to be what the design always said it should be.
///
/// Which is LIGHT: everything on him hits harder except the thrust, and that is the point rather than a
/// concession. **Its price to the player is POSITION, never health.** It keeps the biggest POISE and STANCE
/// in the game — still the heaviest REACTION anything here produces, and a test pins both above every other
/// move — and its price to HIM is the longest opening he owns.
pub const FALL_HIT = combat.Hit{ .dmg = 24, .poise = 64, .stance = 32 };

// THE FALL — he goes over BACKWARD to squash whatever is behind him, lies there, rolls onto his front and
// levers himself up. It is the whole of what makes his back dangerous, and its aftermath is the whole of what
// makes his back worth getting to.
/// HE STOPS TURNING, ROCKS FORWARD AND PUTS HIS BACK TO YOU — the tell, and it is **the longest thing he
/// does** (owner: it needs more tell). At 0.82 it was shorter than the big swing's own haul, so the one
/// move with no parry and no block behind it was read in less time than the one you can catch on the boards.
/// A test now pins it above every wind he has rather than merely above `foe.TELL_MIN`.
const FALL_WIND_DUR = 1.45;
const FALL_DUR = 0.44; // …and then goes, accelerating the whole way
const FALL_IMPACT_K = 0.86; // fraction into the topple his shoulders meet the earth (MEASURED off the pose)
const DOWN_DUR = 2.10; // flat on his back. THIS IS THE PUNISH WINDOW and it is the longest in the game
const ROLL_DUR = 0.72; // over onto his front, in one heave
const RISE_DUR = 1.15; // …and up off the shield, slowly
const FALL_CD = 8.00;
/// HOW FAR BEHIND HIM THE BODY LANDS and HOW WIDE IT LIES — both DERIVED off the rig, in the same
/// times-`scale` units the reaches use, because the strip is not a number chosen beside the creature: it is
/// exactly the ground five metres of armour covers when it goes over. A test brackets the length against his
/// own crown from both sides.
const FALL_LEN = 0.95 * H; // his own standing length
const FALL_HALF_W = SHOULDER_HALF * H * 1.05; // …and his own shoulders, plus the door on one of them
const FALL_BACK_SLACK = 0.30; // times `scale`: how far IN FRONT of his heels the strip still bites
const TOPPLE_DEG = 92.0; // deg of rotation from standing to flat — a hair past, so he is truly down
const LIE_LIFT = 0.34; // pre-scale: half the thickness of an armoured body, so he lies ON the ground
const ROLL_SHIFT = 0.30; // pre-scale: the ground a body crosses rolling over its own thickness
/// …and how far it HEAVES UP over its own side to cross it. Without this the roll was a rotation with no
/// vertical in it at all — the helm moved 13 cm across the whole move, which is a crate turning over rather
/// than a body getting its front under itself.
const ROLL_HUMP = 0.26; // pre-scale
/// How far PAST upright the rise carries before it settles back (`TOPPLE_DEG` units, so 0.06 is ~5.5 deg).
/// A MASS IN MOTION OVERSHOOTS ITS REST — a `smoothstep` that arrives exactly on it is the glide the law
/// forbids, and it was what the old rise did.
const RISE_OVERSHOOT = 0.07;

/// A BATTLE OF ATTRITION (owner's ask): raised with the moveset, because every move he gained also gave the
/// player an opening — the stomp's recover, the charge's skid, the sweeps' stowed door. More doors in, more
/// wall to get through.
/// **THE FIRST BOSS, AND HE LASTS LIKE ONE** (owner: give him more HP). The number is not difficulty on its
/// own — everything else in this file is what makes him hard — but it is what gives the fight ROOM: a
/// player has to get the flank loop right several times over, which is where memorisation actually happens.
/// At 640 a good run was over before his rotation had repeated enough to be learned.
const HP_MAX = 900.0;
/// **HE IS A BOSS AND HE DOES NOT FLINCH AT A POKE** (owner: he stuns too easily). At 46 he was five hero
/// lights from a flinch and his poise refilled between them — which on a creature whose whole read is
/// "commit and pay for it" meant a player who simply kept swinging could keep him reeling and never learn a
/// single tell. A flinch has to be EARNED off a heavy or off a real string, so the pool is sized past what
/// light spam can reach and the fight goes back to being about openings.
const POISE_MAX = 78.0;
/// …and the STANCE bar behind it, which is what a punish window is actually bought with. Sized so three
/// PARRIES still break it (`combat.PARRY_HIT` 46 x 3 = 138) — the parry stays the fast way in, and it is a
/// committed read that deserves to be — while ordinary blows take real work.
const STANCE_MAX = 138.0;
/// DRY BONE IN A SUIT — the archer's own table, because it is the archer's body (see AGENTS.md). Fire is the
/// answer to him and the wand is very nearly useless, which is an honest trade and not an oversight.
const RESISTS = combat.resists(.{ .fire = -35, .cold = 60, .chaos = 45 });
/// SOULS the Bone Knight is worth — near three ogres.
pub const SOULS: u32 = 2400;
const DEATH_DUR = 2.20; // a slow, weighty topple — and this one goes over FORWARD, onto his face
const DISS_DUR = 1.40;
/// Sized to the mass going out in it: five metres of armoured skeleton sheds a far wider cloud than a man.
const DISSOLVE = foe.Dissolve{ .rate = 82.0, .spread = 1.15, .rise = 0.72, .flake = CHIP };

const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 6.0;
const HERO_REACH = foe.HERO_REACH;
const PARRY_LEAD = foe.PARRY_LEAD;

/// Per knight, and it is a RING, so its size is arithmetic over the worst frame anything here emits: the
/// FALL's impact is `dustBurst(48)` + `grit(20)` + `plantBurst` (2 x 10) = 88 slots on one frame. At 88 the
/// head lands back where it started and `floorBurst`'s walk would read as empty, so it is the next size up.
/// …and the GATHER'S FIRE now runs alongside all of that: a crushing wind emits up to ~90 embers a second
/// for over a second, with lives long enough that seventy-odd are resident at the top of the haul. At 112
/// the ring recycled its own tell out from under itself — the column thinned back to a scatter exactly as
/// the wind reached the point the player most needs to read it.
const NPART = 208;

const PELVIS_SHARE = 0.14; // BIG BODIES HINGE AT THE WAIST: what the pelvis may take of any body pitch
const STUN_EASE_DEG = 240.0; // how fast a staggered body gives its posture back (the ogre's law: DEGREES)
const STUN_EASE_FRAC = 4.0;
const A_BOB = heromod.A_BOB;
const A_PROT = 5.0; // deg of pelvic transverse rotation — a heavy, square tread

// THE CARRY (owner's ask: a large sword carried out to the side). The arm hangs off the shoulder, ABDUCTED
// clear of his own hip, and the blade continues it — point down and out, a metre of steel standing off his
// sword side and the tip riding just clear of the ground. Nothing else on the field carries low, so the
// silhouette says which creature this is before the door does. A test pins the tip LOW, OUT, and off the
// earth, because "out to the side" is a picture and pictures drift.
const CARRY_SH = 14.0; // hangs, leading a hair forward of plumb
const CARRY_EL = -18.0;
const CARRY_ABD = 8.0; // …and OUT — the blade's own length does most of the standing-off
/// `wpnTilt` is deg the blade leads FORWARD of the forearm line — the hero's `GRIP_PITCH` convention.
/// MEASURED off the posed tip, not argued from the convention: at 22 the blade stood straight out SIDEWAYS
/// (a four-metre wing at hip height) and at 96 it pointed at the sky. This is where the tip actually hangs
/// low off his side.
const CARRY_TILT = 14.0;
// **THE DOOR IS CARRIED AGAINST HIM, NOT OUT ON AN ARM** (owner: it has to keep the shield close to the body
// if it is going to block all frontal). MEASURED at sh52/el−92/abd44 the shield hand stood 1.82 m in front of
// his own chest bone and the door's hub 2.15 m — a wall held at arm's length, with daylight between it and
// the man it is supposed to be shutting. The shoulder comes down out of the reach, the elbow folds the
// forearm across his chest instead of out in front of it, and `SH_STANDOFF` takes the rest.
const GUARD_SH = 6.0; // the shield arm folded hard ACROSS — the door is carried on his middle…
const GUARD_EL = -126.0;
const GUARD_ABD = 12.0;
const GUARD_TWIST = -18.0; // …and he turns his sword side away, presenting the door
const GUARD_LEAN = 7.0;

// THE BASH: gather back onto the rear foot, then the whole body behind the shield.
// **THE GATHER IS THE TELL, SO IT IS BIG** (owner: the telegraphs need more). Authored a few degrees off the
// carry it moved the shoulder 22 deg and the lean 16 across the whole wind — a strip of the wind frame by
// frame showed SIX frames in which nothing visibly happened, which under this game's own reaction law is a
// committed action that shows nothing. Every channel now travels clearly AWAY from where the strike takes it:
// the door hauled back and across, the elbow deeply folded, the shoulders wound off, the weight over the heels.
// …and these are the SAME HAULS as before off the new carry (−44 deg of shoulder, −24 of elbow, +8 of
// abduction). Written as absolutes they are the one thing that quietly loses a tell when the guard pose
// moves: at the old GUARD_SH of 52 a wind to 8 was a 44 deg gather, and at the new 6 it would be nothing.
const BASH_WIND_SH = -38.0;
const BASH_WIND_EL = -150.0;
const BASH_WIND_ABD = 20.0;
const BASH_WIND_TWIST = -58.0;
const BASH_WIND_LEAN = -22.0;
const BASH_HIT_SH = 74.0; // the arm goes LONG — this is where the reach comes from
const BASH_HIT_EL = -14.0;
const BASH_HIT_ABD = 6.0;
const BASH_HIT_TWIST = 30.0;
const BASH_HIT_LEAN = 22.0;
const BASH_STEP = 0.52; // metres of ground the shove carries him, pre-scale

// THE SWEEP: the sword arm hauled up, OUT and round behind his sword side — the blade climbs off the ground
// it was hanging at and cocks level behind him, which is a tell that reads from every bearing because it
// changes his whole outline. The stroke is the arm yawed hard ACROSS his front (`armSweep`) with the trunk
// driving it, the blade held tip-down of level so the arc crosses a man's chest and not his hair — and it
// is hauled WELL past his far shoulder (the Sentinel's near-360: being behind him is not being safe).
// **THE DOOR NEVER LEAVES HIS FRONT FOR IT** (docs/ELDEN_RING.md §7: the guard is held while attacking):
// the off arm braces, it does not counterweight. Only the SLAM takes the wall out of the fight.
const SWP_WIND_SH = 42.0; // the arm comes up toward level…
const SWP_WIND_EL = -14.0;
const SWP_WIND_ABD = 66.0; // …and OUT, near horizontal
const SWP_WIND_SWEEP = -64.0; // …cocked round behind him
const SWP_WIND_TWIST = -46.0; // the shoulders wound off with it
const SWP_WIND_LEAN = -12.0; // hung back over the rear foot
const SWP_WIND_TILT = 60.0; // the blade near level, tip trailing
const SWP_HIT_SWEEP = 102.0; // …and hauled through past his far shoulder — the arc reaches round his flank
const SWP_HIT_TWIST = 44.0;
const SWP_HIT_LEAN = 34.0; // the fold helps dip the arc into a man's height…
const SWP_HIT_TILT = 10.0;
const SWP_HIT_SH = 30.0;
const SWP_HIT_ABD = 14.0; // …and the ARM DROPPING is most of it: the arc is a falling diagonal, not a level hoop

// THE SECOND SWEEP: re-cocked PART way and thrown down the SAME line (the Sentinel's double is two
// right-to-left strokes, not a backhand) — lower, so ducking the first is not an answer to the second.
const SW2_WIND_SWEEP = -42.0; // hauled back most of the way round…
const SW2_WIND_TILT = 44.0;
const SW2_HIT_SWEEP = 96.0; // …and through again, the same way
const SW2_HIT_TWIST = 40.0;
const SW2_HIT_LEAN = 38.0; // deeper: the second runs at the waist
const SW2_HIT_TILT = 26.0; // …but the edge stays out of the turf (it measured -0.65 m too low once)

// THE OVERHEAD: the blade hauled straight up over the helm — the one silhouette where steel stands ABOVE
// him — hangs there (`windHold`, the delayed downswing), and comes down a committed line into the earth.
const OVR_WIND_SH = -148.0; // the arm straight up…
const OVR_WIND_EL = -24.0;
const OVR_WIND_ABD = 10.0;
const OVR_WIND_TILT = -30.0; // …blade continuing it skyward (measured, like every tilt here)
const OVR_WIND_LEAN = -14.0; // hung back
const OVR_WIND_TWIST = -18.0;
const OVR_HIT_SH = 64.0; // the arm driven down his front…
const OVR_HIT_TILT = -12.0; // …the blade staying ON it — read off the tip map: at +66 the arc dug at his
const OVR_HIT_EL = -8.0; // own boots mid-swing (y -0.75 at z 1.2) and then ENDED at chest height
const OVR_HIT_LEAN = 32.0; // the waist pays the last of it
const OVR_HIT_TWIST = 10.0;

// THE STROKES, AS SEQUENCES OF POSES.
//
// Each was two constants and a curve. Read the key lists as an animator's track: the gather LOADS (and
// settles back a hair before it fires — anticipation is a mass winding, not a mass being placed), the
// strike SNAPS, and the recover carries THROUGH its end pose before drifting home, because a five-metre
// stroke does not stop where it lands. The `.snap` ease is the two-to-four active frames the reference
// measures; the `.hold` is a bait; the extra key just past the strike is the FOLLOW-THROUGH, which is
// the single thing whose absence made all of this read as a mannequin being posed.

const SWEEP_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        // The blade PEELS off the ground first — the arm leads, the trunk has not committed yet, and the
        // player's first frame of information is the steel leaving the turf.
        .{ .t = 0.22, .p = .{ .armSh = 30, .armAbd = 40, .armSweep = -26, .tilt = 40, .lean = 2, .twist = -26, .brace = 0.30 }, .ease = .decel },
        // …then the whole body winds off it, and the weight goes back over the rear foot.
        .{ .t = 0.74, .p = .{ .armSh = SWP_WIND_SH, .armEl = SWP_WIND_EL, .armAbd = SWP_WIND_ABD, .armSweep = SWP_WIND_SWEEP, .tilt = SWP_WIND_TILT, .lean = SWP_WIND_LEAN, .twist = SWP_WIND_TWIST, .head = -10, .brace = 0.60 }, .ease = .accel },
        // …and it SETTLES BACK a few degrees at the top. A gather that arrives and stops reads as a pause;
        // a gather that eases back into itself reads as a body about to move, which is the whole tell.
        .{ .t = 1.00, .p = .{ .armSh = SWP_WIND_SH - 6, .armEl = SWP_WIND_EL, .armAbd = SWP_WIND_ABD + 4, .armSweep = SWP_WIND_SWEEP - 8, .tilt = SWP_WIND_TILT + 6, .lean = SWP_WIND_LEAN - 3, .twist = SWP_WIND_TWIST - 5, .head = -10, .brace = 0.66 }, .ease = .decel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .armSh = SWP_WIND_SH - 6, .armEl = SWP_WIND_EL, .armAbd = SWP_WIND_ABD + 4, .armSweep = SWP_WIND_SWEEP - 8, .tilt = SWP_WIND_TILT + 6, .lean = SWP_WIND_LEAN - 3, .twist = SWP_WIND_TWIST - 5, .head = -10, .brace = 0.66 } },
        // THE ARC, and nearly all of it is over by a third of the way in.
        .{ .t = 0.34, .p = .{ .armSh = SWP_HIT_SH + 6, .armEl = -6, .armAbd = SWP_HIT_ABD + 10, .armSweep = 62, .tilt = SWP_HIT_TILT + 16, .lean = SWP_HIT_LEAN - 10, .twist = 20, .head = 10, .brace = 0.84 }, .ease = .snap },
        // …and it OVERSHOOTS past where it was aimed before the body catches it. This is the follow-through.
        .{ .t = 0.74, .p = .{ .armSh = SWP_HIT_SH - 8, .armEl = -6, .armAbd = SWP_HIT_ABD - 6, .armSweep = SWP_HIT_SWEEP + 14, .tilt = SWP_HIT_TILT - 8, .lean = SWP_HIT_LEAN + 6, .twist = SWP_HIT_TWIST + 8, .head = 18, .brace = 0.90 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .armSh = SWP_HIT_SH, .armEl = -6, .armAbd = SWP_HIT_ABD, .armSweep = SWP_HIT_SWEEP, .tilt = SWP_HIT_TILT, .lean = SWP_HIT_LEAN, .twist = SWP_HIT_TWIST, .head = 16, .brace = 0.86 } },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .armSh = SWP_HIT_SH, .armEl = -6, .armAbd = SWP_HIT_ABD, .armSweep = SWP_HIT_SWEEP, .tilt = SWP_HIT_TILT, .lean = SWP_HIT_LEAN, .twist = SWP_HIT_TWIST, .head = 16, .brace = 0.86 } },
        // THE END POSE IS HELD — the punish window, shown. He is hauled round with the blade out past his
        // far shoulder and his weight on the wrong foot, and he stays there long enough to be hit for it.
        .{ .t = 0.40, .p = .{ .armSh = SWP_HIT_SH - 4, .armEl = -8, .armAbd = SWP_HIT_ABD - 2, .armSweep = SWP_HIT_SWEEP + 4, .tilt = SWP_HIT_TILT - 4, .lean = SWP_HIT_LEAN + 2, .twist = SWP_HIT_TWIST + 3, .head = 14, .brace = 0.80 }, .ease = .decel },
        // …then he gathers himself back behind the door, heavily.
        .{ .t = 1.00, .p = .{ .brace = 0.20 }, .ease = .decel },
    },
};

const SWEEP2_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{ .armSh = SWP_HIT_SH, .armEl = -6, .armAbd = SWP_HIT_ABD, .armSweep = SWP_HIT_SWEEP, .tilt = SWP_HIT_TILT, .lean = SWP_HIT_LEAN, .twist = SWP_HIT_TWIST, .head = 16, .brace = 0.86 } },
        // "Slightly delayed" — the re-cock is SHORT and it is the roll-catch. He hauls it back most of the
        // way, not all, and the shoulders lead so the second stroke is already coming as the first settles.
        .{ .t = 1.00, .p = .{ .armSh = SWP_HIT_SH + 10, .armEl = -6, .armAbd = SWP_HIT_ABD + 12, .armSweep = SW2_WIND_SWEEP, .tilt = SW2_WIND_TILT, .lean = SWP_HIT_LEAN - 20, .twist = SW2_WIND_SWEEP * 0.4, .head = -4, .brace = 0.70 }, .ease = .accel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .armSh = SWP_HIT_SH + 10, .armEl = -6, .armAbd = SWP_HIT_ABD + 12, .armSweep = SW2_WIND_SWEEP, .tilt = SW2_WIND_TILT, .lean = SWP_HIT_LEAN - 20, .twist = SW2_WIND_SWEEP * 0.4, .head = -4, .brace = 0.70 } },
        .{ .t = 0.30, .p = .{ .armSh = SWP_HIT_SH - 2, .armEl = -6, .armAbd = SWP_HIT_ABD + 4, .armSweep = 58, .tilt = SW2_HIT_TILT + 14, .lean = SW2_HIT_LEAN - 12, .twist = 18, .head = 12, .brace = 0.86 }, .ease = .snap },
        .{ .t = 0.72, .p = .{ .armSh = SWP_HIT_SH - 10, .armEl = -6, .armAbd = SWP_HIT_ABD - 4, .armSweep = SW2_HIT_SWEEP + 12, .tilt = SW2_HIT_TILT - 6, .lean = SW2_HIT_LEAN + 5, .twist = SW2_HIT_TWIST + 7, .head = 20, .brace = 0.92 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .armSh = SWP_HIT_SH - 4, .armEl = -6, .armAbd = SWP_HIT_ABD, .armSweep = SW2_HIT_SWEEP, .tilt = SW2_HIT_TILT, .lean = SW2_HIT_LEAN, .twist = SW2_HIT_TWIST, .head = 18, .brace = 0.88 } },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .armSh = SWP_HIT_SH - 4, .armEl = -6, .armAbd = SWP_HIT_ABD, .armSweep = SW2_HIT_SWEEP, .tilt = SW2_HIT_TILT, .lean = SW2_HIT_LEAN, .twist = SW2_HIT_TWIST, .head = 18, .brace = 0.88 } },
        .{ .t = 0.44, .p = .{ .armSh = SWP_HIT_SH - 8, .armEl = -8, .armAbd = SWP_HIT_ABD - 3, .armSweep = SW2_HIT_SWEEP + 5, .tilt = SW2_HIT_TILT - 5, .lean = SW2_HIT_LEAN + 3, .twist = SW2_HIT_TWIST + 4, .head = 16, .brace = 0.82 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .brace = 0.20 }, .ease = .decel },
    },
};

const OVER_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        // Up the FRONT, not round the side — the one silhouette with steel standing above the helm, and it
        // has to be readable from every bearing, so the climb is the whole first half.
        .{ .t = 0.58, .p = .{ .armSh = OVR_WIND_SH + 30, .armEl = OVR_WIND_EL - 10, .armAbd = OVR_WIND_ABD + 6, .tilt = OVR_WIND_TILT + 24, .lean = -6, .twist = -14, .head = -8, .brace = 0.38 }, .ease = .decel },
        .{ .t = 0.86, .p = .{ .armSh = OVR_WIND_SH, .armEl = OVR_WIND_EL, .armAbd = OVR_WIND_ABD, .tilt = OVR_WIND_TILT, .lean = OVR_WIND_LEAN, .twist = OVR_WIND_TWIST, .head = -14, .brace = 0.55 }, .ease = .accel },
        // THE HANG. `.hold` so the pose does not creep while `windHold` runs — a drifting bait is a bait the
        // player reads as the swing already starting, which is the whole reason the delay exists.
        .{ .t = 1.00, .p = .{ .armSh = OVR_WIND_SH, .armEl = OVR_WIND_EL, .armAbd = OVR_WIND_ABD, .tilt = OVR_WIND_TILT, .lean = OVR_WIND_LEAN, .twist = OVR_WIND_TWIST, .head = -14, .brace = 0.55 }, .ease = .hold },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .armSh = OVR_WIND_SH, .armEl = OVR_WIND_EL, .armAbd = OVR_WIND_ABD, .tilt = OVR_WIND_TILT, .lean = OVR_WIND_LEAN, .twist = OVR_WIND_TWIST, .head = -14, .brace = 0.55 } },
        // The elbow SHORTENS through the middle of the drop — a real hammer blow pulls its radius in past
        // the body — which is also what keeps the tip out of the turf at his own boots mid-arc.
        .{ .t = 0.42, .p = .{ .armSh = 10, .armEl = OVR_WIND_EL - 34, .armAbd = 8, .tilt = -22, .lean = 12, .twist = 0, .head = 6, .brace = 0.74 }, .ease = .snap },
        // …into the earth, and PAST where it was aimed: the blade buries and the body keeps going over it.
        .{ .t = 0.80, .p = .{ .armSh = OVR_HIT_SH + 8, .armEl = OVR_HIT_EL, .armAbd = 6, .tilt = OVR_HIT_TILT - 6, .lean = OVR_HIT_LEAN + 7, .twist = OVR_HIT_TWIST + 4, .head = 24, .brace = 0.94 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .armSh = OVR_HIT_SH, .armEl = OVR_HIT_EL, .armAbd = 6, .tilt = OVR_HIT_TILT, .lean = OVR_HIT_LEAN, .twist = OVR_HIT_TWIST, .head = 22, .brace = 0.90 } },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .armSh = OVR_HIT_SH, .armEl = OVR_HIT_EL, .armAbd = 6, .tilt = OVR_HIT_TILT, .lean = OVR_HIT_LEAN, .twist = OVR_HIT_TWIST, .head = 22, .brace = 0.90 } },
        // THE BLADE STAYS IN THE EARTH and he has to drag himself off it. The longest held pose he owns,
        // and the one the whole move is priced around.
        .{ .t = 0.52, .p = .{ .armSh = OVR_HIT_SH - 3, .armEl = OVR_HIT_EL - 3, .armAbd = 6, .tilt = OVR_HIT_TILT - 2, .lean = OVR_HIT_LEAN + 2, .twist = OVR_HIT_TWIST, .head = 20, .brace = 0.86 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .brace = 0.20 }, .ease = .decel },
    },
};

const THRUST_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        // The point comes ON to him early and STAYS there — the line is the tell — while the fist chambers
        // back to the hip and the door lifts a hand's width (the Banished Knight's off-arm tell).
        .{ .t = 0.46, .p = .{ .armSh = THR_WIND_SH + 14, .armEl = THR_WIND_EL + 10, .armAbd = THR_WIND_ABD - 6, .tilt = THR_WIND_TILT - 6, .offSh = GUARD_SH - THR_OFF_RISE * 0.5, .lean = 0, .twist = GUARD_TWIST - 4, .brace = 0.28 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .armSh = THR_WIND_SH, .armEl = THR_WIND_EL, .armAbd = THR_WIND_ABD, .tilt = THR_WIND_TILT, .offSh = GUARD_SH - THR_OFF_RISE, .lean = THR_WIND_LEAN, .twist = GUARD_TWIST - 10, .brace = 0.44 }, .ease = .accel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .armSh = THR_WIND_SH, .armEl = THR_WIND_EL, .armAbd = THR_WIND_ABD, .tilt = THR_WIND_TILT, .offSh = GUARD_SH - THR_OFF_RISE, .lean = THR_WIND_LEAN, .twist = GUARD_TWIST - 10, .brace = 0.44 } },
        // The shortest, hardest snap he has — the whole point of the move is that it arrives.
        .{ .t = 0.28, .p = .{ .armSh = THR_HIT_SH + 4, .armEl = THR_HIT_EL, .armAbd = CARRY_ABD,.tilt = THR_HIT_TILT, .offSh = GUARD_SH - 4, .lean = THR_HIT_LEAN + 4, .twist = 8, .head = 8, .brace = 0.80 }, .ease = .snap },
        .{ .t = 1.00, .p = .{ .armSh = THR_HIT_SH, .armEl = THR_HIT_EL, .armAbd = CARRY_ABD,.tilt = THR_HIT_TILT, .offSh = GUARD_SH, .lean = THR_HIT_LEAN, .twist = 4, .head = 6, .brace = 0.72 }, .ease = .decel },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .armSh = THR_HIT_SH, .armEl = THR_HIT_EL, .armAbd = CARRY_ABD,.tilt = THR_HIT_TILT, .lean = THR_HIT_LEAN, .twist = 4, .head = 6, .brace = 0.72 } },
        .{ .t = 0.36, .p = .{ .armSh = THR_HIT_SH - 6, .armEl = THR_HIT_EL - 4, .armAbd = CARRY_ABD,.tilt = THR_HIT_TILT - 4, .lean = THR_HIT_LEAN + 3, .twist = 2, .head = 4, .brace = 0.64 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .brace = 0.20 }, .ease = .decel },
    },
};

const BASH_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        // THE DOOR HAULS BACK AND ACROSS, hard and early: every channel travels AWAY from where the strike
        // takes it. The old wind moved the shoulder 22 deg over its whole length and a frame strip showed
        // six frames in which nothing visibly happened.
        .{ .t = 0.52, .p = .{ .offSh = BASH_WIND_SH + 10, .offEl = BASH_WIND_EL + 12, .offAbd = BASH_WIND_ABD - 4, .armSh = CARRY_SH - 8, .lean = BASH_WIND_LEAN + 8, .twist = BASH_WIND_TWIST + 16, .head = -4, .brace = 0.36 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .offSh = BASH_WIND_SH, .offEl = BASH_WIND_EL, .offAbd = BASH_WIND_ABD, .armSh = CARRY_SH - 12, .armEl = CARRY_EL - 10, .armAbd = CARRY_ABD + 8, .tilt = CARRY_TILT + 10, .lean = BASH_WIND_LEAN, .twist = BASH_WIND_TWIST, .head = -6, .brace = 0.50 }, .ease = .accel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .offSh = BASH_WIND_SH, .offEl = BASH_WIND_EL, .offAbd = BASH_WIND_ABD, .armSh = CARRY_SH - 12, .armEl = CARRY_EL - 10, .armAbd = CARRY_ABD + 8, .tilt = CARRY_TILT + 10, .lean = BASH_WIND_LEAN, .twist = BASH_WIND_TWIST, .head = -6, .brace = 0.50 } },
        .{ .t = 0.30, .p = .{ .offSh = BASH_HIT_SH + 6, .offEl = BASH_HIT_EL, .offAbd = BASH_HIT_ABD, .armSh = CARRY_SH + 18, .armEl = CARRY_EL, .armAbd = CARRY_ABD - 6, .lean = BASH_HIT_LEAN + 6, .twist = BASH_HIT_TWIST + 6, .head = 14, .brace = 0.76 }, .ease = .snap },
        .{ .t = 1.00, .p = .{ .offSh = BASH_HIT_SH, .offEl = BASH_HIT_EL, .offAbd = BASH_HIT_ABD, .armSh = CARRY_SH + 18, .armEl = CARRY_EL, .armAbd = CARRY_ABD - 6, .lean = BASH_HIT_LEAN, .twist = BASH_HIT_TWIST, .head = 14, .brace = 0.72 }, .ease = .decel },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .offSh = BASH_HIT_SH, .offEl = BASH_HIT_EL, .offAbd = BASH_HIT_ABD, .armSh = CARRY_SH + 18, .armEl = CARRY_EL, .armAbd = CARRY_ABD - 6, .lean = BASH_HIT_LEAN, .twist = BASH_HIT_TWIST, .head = 14, .brace = 0.72 } },
        .{ .t = 0.42, .p = .{ .offSh = BASH_HIT_SH - 8, .offEl = BASH_HIT_EL - 6, .offAbd = BASH_HIT_ABD, .armSh = CARRY_SH + 10, .lean = BASH_HIT_LEAN + 3, .twist = BASH_HIT_TWIST - 4, .head = 10, .brace = 0.62 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .brace = 0.20 }, .ease = .decel },
    },
};

/// **THE SLAM, WHICH WAS THE WORST OF THEM** (owner: busted looking, cuts through his model, bad AoE tell).
/// Three separate failures met on this move: the door pitched about a grip near its own top edge so it
/// scythed through his chest (`slamCarry`/`SH_CENTRE_Y` fix that), the disc was never drawn before it landed
/// (`slamRingTell`), and the body itself was two poses — so the biggest, slowest, most committed thing he
/// owns had no gather, no hang at the top and no recoil. It is the one move where the wall LEAVES, which
/// makes it the one silhouette the player has to be able to read from across the arena.
const SLAM_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        // He SINKS first. A five-metre body about to lift a four-metre door drops into its own knees
        // before anything goes up, and that dip is the earliest frame the move is legible from.
        .{ .t = 0.20, .p = .{ .offSh = GUARD_SH + 16, .offEl = GUARD_EL + 8, .lean = 16, .head = 8, .brace = 0.62 }, .ease = .decel },
        // …then the haul, and it is the whole middle of the move: the door climbs off his front and the
        // chest comes bare under it. `guardUp` opens across this, so it has to be SEEN to open.
        .{ .t = 0.74, .p = .{ .offSh = SLM_WIND_SH + 22, .offEl = SLM_WIND_EL - 8, .offAbd = SLM_WIND_ABD - 6, .armSh = CARRY_SH - 20, .armEl = CARRY_EL - 10, .armAbd = CARRY_ABD + 10, .armSweep = -14, .lean = SLM_WIND_LEAN + 6, .twist = SLM_WIND_TWIST - 4, .head = -8, .brace = 0.50 }, .ease = .accel },
        // …to the top, hung back over his heels with the door overhead and his whole front open.
        .{ .t = 0.92, .p = .{ .offSh = SLM_WIND_SH, .offEl = SLM_WIND_EL, .offAbd = SLM_WIND_ABD, .armSh = CARRY_SH - 26, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -18, .lean = SLM_WIND_LEAN, .twist = SLM_WIND_TWIST, .head = -12, .brace = 0.62 }, .ease = .decel },
        // THE HANG. Dead still at the top — the longest look at his chest the fight ever offers, and a
        // pose that creeps here is a pose that tells the player the drive has already started.
        .{ .t = 1.00, .p = .{ .offSh = SLM_WIND_SH, .offEl = SLM_WIND_EL, .offAbd = SLM_WIND_ABD, .armSh = CARRY_SH - 26, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -18, .lean = SLM_WIND_LEAN, .twist = SLM_WIND_TWIST, .head = -12, .brace = 0.62 }, .ease = .hold },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .offSh = SLM_WIND_SH, .offEl = SLM_WIND_EL, .offAbd = SLM_WIND_ABD, .armSh = CARRY_SH - 26, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -18, .lean = SLM_WIND_LEAN, .twist = SLM_WIND_TWIST, .head = -12, .brace = 0.62 } },
        // THE DRIVE — the whole body behind it, and it is nearly over by a third: this is where the door
        // meets the earth, and the impact frame is billed inside it (`SLAM.impactK`).
        .{ .t = 0.36, .p = .{ .offSh = SLM_HIT_SH + 10, .offEl = SLM_HIT_EL, .offAbd = 12, .armSh = CARRY_SH + 6, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -10, .lean = SLM_HIT_LEAN + 8, .twist = SLM_HIT_TWIST - 4, .head = 22, .brace = 0.94 }, .ease = .snap },
        // …and the RECOIL. The earth answers: the arm rebounds a few degrees and the body rides up over
        // its own blow before settling onto it. This is the beat that says something heavy hit something
        // solid, and a two-pose lerp has nowhere to put it.
        .{ .t = 0.62, .p = .{ .offSh = SLM_HIT_SH - 9, .offEl = SLM_HIT_EL - 5, .offAbd = 12, .armSh = CARRY_SH + 12, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -6, .lean = SLM_HIT_LEAN - 6, .twist = SLM_HIT_TWIST, .head = 14, .brace = 0.80 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .offSh = SLM_HIT_SH, .offEl = SLM_HIT_EL, .offAbd = 12, .armSh = CARRY_SH + 12, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -6, .lean = SLM_HIT_LEAN, .twist = SLM_HIT_TWIST, .head = 20, .brace = 0.92 }, .ease = .decel },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .offSh = SLM_HIT_SH, .offEl = SLM_HIT_EL, .offAbd = 12, .armSh = CARRY_SH + 12, .armEl = CARRY_EL - 12, .armAbd = CARRY_ABD + 14, .armSweep = -6, .lean = SLM_HIT_LEAN, .twist = SLM_HIT_TWIST, .head = 20, .brace = 0.92 } },
        // "IT LEAVES A HUGE OPENING" — the door is IN THE GROUND and he is folded over it. The longest
        // held pose on his feet, and the whole price of the move.
        .{ .t = 0.46, .p = .{ .offSh = SLM_HIT_SH - 4, .offEl = SLM_HIT_EL - 4, .offAbd = 12, .armSh = CARRY_SH + 8, .armEl = CARRY_EL - 10, .armAbd = CARRY_ABD + 10, .lean = SLM_HIT_LEAN + 3, .twist = SLM_HIT_TWIST, .head = 18, .brace = 0.86 }, .ease = .decel },
        // …then he drags it back up out of the crater, heavily, and the wall re-forms.
        .{ .t = 1.00, .p = .{ .brace = 0.22 }, .ease = .decel },
    },
};

/// **THE FALLBACK** (owner: it is too stiff). It was the stiffest thing in the game and the reason is
/// visible in one line of the old code: `setFalling` clamped both arms to one pose, zeroed the brace and
/// lerped the lean — so five metres of armour went over as a single welded plank rotating about its heels.
/// A body going over backwards does not do that. The arms fly OFF the body (the reflex nobody can suppress),
/// the legs come UP as the top goes down because the pivot is the heels, and the helm lags the trunk and
/// then whips. None of that could exist in a two-pose lerp; all of it is keys.
const FALL_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        // THE ROCK FORWARD ONTO HIS TOES — the tell, and it is deliberately the longest thing he does,
        // because this is the move the boards cannot answer.
        .{ .t = 0.34, .p = .{ .lean = FALL_WIND_GATHER, .offSh = GUARD_SH + 8, .armSh = CARRY_SH + 10, .head = 10, .brace = 0.44 }, .ease = .decel },
        // …then he stops tracking, the shoulders square, and he begins going back past the vertical.
        .{ .t = 0.78, .p = .{ .lean = FALL_WIND_LEAN * 0.5, .offSh = FALL_SH + 14, .offEl = FALL_EL + 20, .offAbd = 14, .armSh = FALL_SH + 16, .armEl = FALL_EL + 24, .armAbd = 16, .tilt = 70, .twist = -6, .head = -18, .brace = 0.24 }, .ease = .accel },
        .{ .t = 1.00, .p = .{ .lean = FALL_WIND_LEAN, .offSh = FALL_SH, .offEl = FALL_EL, .offAbd = 10, .armSh = FALL_SH, .armEl = FALL_EL, .armAbd = 8, .tilt = 110, .twist = 0, .head = -30, .brace = 0 }, .ease = .decel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .lean = FALL_WIND_LEAN, .offSh = FALL_SH, .offEl = FALL_EL, .offAbd = 10, .armSh = FALL_SH, .armEl = FALL_EL, .armAbd = 8, .tilt = 110, .twist = 0, .head = -30, .brace = 0 } },
        // GOING OVER: the arms come OFF him. A falling body throws its limbs out and this is the single
        // biggest difference between a man toppling and a plank toppling.
        .{ .t = 0.34, .p = .{ .lean = -14, .offSh = FALL_SH - 40, .offEl = FALL_EL + 46, .offAbd = 44, .armSh = FALL_SH - 52, .armEl = FALL_EL + 38, .armAbd = 52, .armSweep = -18, .tilt = 84, .head = -34, .brace = 0.30 }, .ease = .decel },
        // …and the knees come UP as the top goes down: he is pivoting about his heels, not his middle.
        .{ .t = 0.70, .p = .{ .lean = -2, .offSh = FALL_SH - 22, .offEl = FALL_EL + 28, .offAbd = 30, .armSh = FALL_SH - 30, .armEl = FALL_EL + 20, .armAbd = 36, .armSweep = -10, .tilt = 96, .head = -12, .brace = 0.55 }, .ease = .linear },
        // THE LANDING, and the limbs arrive AFTER the back does — which is what the springs then ring out.
        .{ .t = 1.00, .p = .{ .lean = 4, .offSh = FALL_SH, .offEl = FALL_EL, .offAbd = 6, .armSh = FALL_SH, .armEl = FALL_EL, .armAbd = 8, .tilt = FLOORED_TILT, .head = -4, .brace = 0 }, .ease = .snap },
    },
    // The floored poses are their own states (`easeFloored`, `setRollover`, the rise), so this track ends
    // at the landing — the body on the ground is not a recovery, it is three separate pictures.
    .recover = &.{
        .{ .t = 0.00, .p = .{ .lean = 4, .offSh = FALL_SH, .offEl = FALL_EL, .offAbd = 6, .armSh = FALL_SH, .armEl = FALL_EL, .armAbd = 8, .tilt = FLOORED_TILT, .head = -4, .brace = 0 } },
        .{ .t = 1.00, .p = .{ .lean = 4, .offSh = FALL_SH, .offEl = FALL_EL, .offAbd = 6, .armSh = FALL_SH, .armEl = FALL_EL, .armAbd = 8, .tilt = FLOORED_TILT, .head = -4, .brace = 0 } },
    },
};

/// **THE SHOVE — THE DOOR DRIVEN ACROSS HIS SWORD SIDE** (owner: he has no defence on his right side, needs
/// a shield push attack). His shield is his LEFT arm, so his sword side has never had an answer at all: the
/// bash goes straight down his front and the sweep needs a bearing the arc can reach, which left standing
/// off his right shoulder as the one free square on the board. This is the reference's own answer, verbatim
/// — "dodging to a shielded knight's side/rear triggers predictable shield bash counterattacks" — and it is
/// PREDICTABLE on purpose: a long, obvious haul across his chest, so the flank stays the way in and stops
/// being a place to stand still in.
///
/// It is the bash's own row and window (same parry, same clocks); what differs is where the door goes, and
/// that the door LEAVING his front to do it opens the guard on the way — the shove is not free for him.
const SHOVE_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        // Hauled back HARD across to his shield side first — the gather is the whole tell, and it winds
        // the opposite way to where it is going.
        .{ .t = 0.56, .p = .{ .offSh = SHV_WIND_SH + 8, .offEl = SHV_WIND_EL, .offAbd = GUARD_ABD + 4, .armSh = CARRY_SH - 14, .lean = -16, .twist = BASH_WIND_TWIST - 14, .head = -8, .brace = 0.42 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .offSh = SHV_WIND_SH, .offEl = SHV_WIND_EL, .offAbd = GUARD_ABD + 8, .armSh = CARRY_SH - 18, .armAbd = CARRY_ABD + 12, .lean = -22, .twist = BASH_WIND_TWIST - 20, .head = -10, .brace = 0.56 }, .ease = .accel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .offSh = SHV_WIND_SH, .offEl = SHV_WIND_EL, .offAbd = GUARD_ABD + 8, .armSh = CARRY_SH - 18, .armAbd = CARRY_ABD + 12, .lean = -22, .twist = BASH_WIND_TWIST - 20, .head = -10, .brace = 0.56 } },
        // …and DRIVEN across his front onto the sword side, the whole trunk turning behind it. **THE ELBOW
        // STAYS FOLDED.** Inherited from the bash's own hit pose it opened to −21 from the guard's −126,
        // which drops the fist most of a metre — and the door hangs off the fist, so the wall ended up
        // standing on the ground at his knees with his pauldron out over the top of it. What carries the
        // door across is the BODY and `SHOVE_CARRY_X`, never the arm reaching for it.
        .{ .t = 0.32, .p = .{ .offSh = SHV_HIT_SH + 6, .offEl = SHV_HIT_EL, .offAbd = GUARD_ABD + 12, .armSh = CARRY_SH + 14, .armAbd = CARRY_ABD - 8, .lean = 16, .twist = BASH_HIT_TWIST + 26, .head = 12, .brace = 0.82 }, .ease = .snap },
        .{ .t = 0.68, .p = .{ .offSh = SHV_HIT_SH - 5, .offEl = SHV_HIT_EL - 4, .offAbd = GUARD_ABD + 16, .armSh = CARRY_SH + 18, .armAbd = CARRY_ABD - 10, .lean = 10, .twist = BASH_HIT_TWIST + 34, .head = 8, .brace = 0.74 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .offSh = SHV_HIT_SH, .offEl = SHV_HIT_EL, .offAbd = GUARD_ABD + 14, .armSh = CARRY_SH + 16, .armAbd = CARRY_ABD - 10, .lean = 12, .twist = BASH_HIT_TWIST + 30, .head = 10, .brace = 0.78 } },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .offSh = SHV_HIT_SH, .offEl = SHV_HIT_EL, .offAbd = GUARD_ABD + 14, .armSh = CARRY_SH + 16, .armAbd = CARRY_ABD - 10, .lean = 12, .twist = BASH_HIT_TWIST + 30, .head = 10, .brace = 0.78 } },
        // THE DOOR IS OFF HIS FRONT AND HE HAS TO BRING IT BACK — the price of covering that flank at all,
        // and the window the player earns for baiting it.
        .{ .t = 0.48, .p = .{ .offSh = SHV_HIT_SH - 6, .offEl = SHV_HIT_EL - 6, .offAbd = GUARD_ABD + 8, .armSh = CARRY_SH + 10, .lean = 10, .twist = BASH_HIT_TWIST + 20, .head = 8, .brace = 0.66 }, .ease = .decel },
        .{ .t = 1.00, .p = .{ .brace = 0.20 }, .ease = .decel },
    },
};
/// The shove's off-arm, kept NEAR THE GUARD rather than near the bash's punch: the door has to stay at the
/// height it is carried at, because the height is what makes it a wall and not a gate lying in the yard.
const SHV_WIND_SH = -14.0;
const SHV_WIND_EL = -138.0;
const SHV_HIT_SH = 34.0;
const SHV_HIT_EL = -104.0;
/// **AND IT TRAVELS ACROSS HIM, IT DOES NOT SWING AROUND HIM.** First pass hauled the door with the
/// shoulder's own yaw and abduction, which rotates four metres of plank about a grip near its top edge —
/// the slam's mistake in a different move — and it ended up a vertical slab out to one side with the entire
/// knight hidden behind it. A shove PUSHES: the face stays roughly square and the door slides laterally
/// across his front onto the sword side. The yaw is now only the turn of the face INTO the push.
const SHOVE_YAW = 26.0;
/// How far across his own body the door travels to do it, in his body frame (`shieldXf`). Toward the SWORD
/// side, which is local −x: his shield is his left arm.
const SHOVE_CARRY_X = 0.30 * H;
/// …and a little forward, so it is a push and not a slide.
const SHOVE_CARRY_Z = 0.10 * H;
/// …and how far out it will reach for someone stood on that flank, as a multiple of the bash's own trigger.
/// Over 1 because the door travels ACROSS to get there and sweeps ground the straight bash never touches.
const SHOVE_BAND = 1.25;
/// …and the SHIELD side's haul as a fraction of the bash's own gather (owner: a quick shield bash there —
/// hugging that flank is still too easy). Over there the wall does not have to cross his body to arrive, so
/// the short gather is the geometry telling the truth rather than a discount. Still comfortably a telegraph
/// (a test pins it past `foe.TELL_MIN`) — the answer to that flank is quick, never invisible.
const SHOVE_SHIELD_WIND = 0.60;
/// The longest the FLICK may hang at the top of its gather. Half the swings drop on the beat and the rest
/// wait — the overhead's bait at the flick's scale, and the whole of why a readable swat is still hard.
const SWAT_HANG: f32 = 0.26;

/// THE SWAT ON HIS SWORD SIDE: the blade flicked out low and back, from the carry, barely a gather. It is
/// the fastest thing in the file and it looks it — one beat out, one beat back.
const SWAT_SWORD_KEYS = MoveKeys{
    // **THE ELBOW STAYS SHUT.** The blade is 0.57·H of rigid steel bolted to the wrist, so ANY straightening
    // of the arm throws its tip five metres out — the first pass measured 5.68 m off a move declared at 3.09
    // and it was not a flick at all, it was the sweep with a shorter clock. A short sword move on a giant is
    // made by keeping the arm SHUT and turning the trunk: the hand travels, the tip barely does.
    // **AND IT STAYS LOW.** With the elbow shut and the tilt raised, the blade rode at HIS chest — 3.4 m,
    // two and a half metres over the head of the man it is aimed at, which is the giant's-height trap this
    // file already has a test for. A backhand at a man's chest keeps the arm hanging and the tilt near the
    // CARRY: the blade sweeps across low and the motion is the trunk's, not the shoulder's.
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 1.00, .p = .{ .armSweep = -30, .armAbd = CARRY_ABD + 14, .twist = GUARD_TWIST - 14, .lean = 3, .brace = 0.32 }, .ease = .accel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .armSweep = -30, .armAbd = CARRY_ABD + 14, .twist = GUARD_TWIST - 14, .lean = 3, .brace = 0.32 } },
        // Driven ENTIRELY by the sweep channel and the trunk, off the carry pose — which is the one pose on
        // him already measured to hold the tip below his own knee. The shoulder does not lift at all.
        .{ .t = 0.38, .p = .{ .armSweep = 46, .armAbd = CARRY_ABD + 22, .twist = GUARD_TWIST + 22, .lean = 12, .head = 8, .brace = 0.58 }, .ease = .snap },
        .{ .t = 1.00, .p = .{ .armSweep = 36, .armAbd = CARRY_ABD + 18, .twist = GUARD_TWIST + 15, .lean = 9, .head = 6, .brace = 0.52 }, .ease = .decel },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .armSweep = 36, .armAbd = CARRY_ABD + 18, .twist = GUARD_TWIST + 15, .lean = 9, .head = 6, .brace = 0.52 } },
        .{ .t = 1.00, .p = .{ .brace = 0.18 }, .ease = .decel },
    },
};

/// …AND ON HIS SHIELD SIDE it is the DOOR backhanded across — same clock, same reach, other arm. Which one
/// you get is decided by where you are standing, so the two together are one rule: *do not stand still
/// beside him*.
const SWAT_SHIELD_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 1.00, .p = .{ .offSh = GUARD_SH - 26, .offEl = GUARD_EL - 14, .offAbd = GUARD_ABD + 22, .twist = GUARD_TWIST - 20, .lean = 2, .brace = 0.34 }, .ease = .accel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = .{ .offSh = GUARD_SH - 26, .offEl = GUARD_EL - 14, .offAbd = GUARD_ABD + 22, .twist = GUARD_TWIST - 20, .lean = 2, .brace = 0.34 } },
        .{ .t = 0.38, .p = .{ .offSh = GUARD_SH + 30, .offEl = GUARD_EL + 26, .offAbd = GUARD_ABD + 46, .twist = GUARD_TWIST + 24, .lean = 12, .head = 8, .brace = 0.62 }, .ease = .snap },
        .{ .t = 1.00, .p = .{ .offSh = GUARD_SH + 22, .offEl = GUARD_EL + 18, .offAbd = GUARD_ABD + 36, .twist = GUARD_TWIST + 17, .lean = 9, .head = 6, .brace = 0.56 }, .ease = .decel },
    },
    .recover = &.{
        .{ .t = 0.00, .p = .{ .offSh = GUARD_SH + 22, .offEl = GUARD_EL + 18, .offAbd = GUARD_ABD + 36, .twist = GUARD_TWIST + 17, .lean = 9, .head = 6, .brace = 0.56 } },
        .{ .t = 1.00, .p = .{ .brace = 0.18 }, .ease = .decel },
    },
};

/// Which track a move runs on. Exhaustive, so a move added later has to say what it looks like.
fn keysFor(mv: usize) MoveKeys {
    return switch (mv) {
        SWEEP_I => SWEEP_KEYS,
        SWEEP2_I => SWEEP2_KEYS,
        OVER_I => OVER_KEYS,
        THRUST_I => THRUST_KEYS,
        else => BASH_KEYS,
    };
}
/// …and the bash has TWO pictures on one row: straight down his front, or hauled across his sword side.
fn bashKeys(shoving: bool) MoveKeys {
    return if (shoving) SHOVE_KEYS else BASH_KEYS;
}
/// …and the SWAT likewise, picked by which shoulder you are standing off.
fn swatKeys(shieldSide: bool) MoveKeys {
    return if (shieldSide) SWAT_SHIELD_KEYS else SWAT_SWORD_KEYS;
}

// THE THRUST: the fist drawn back to the hip with the blade LEVEL at the target — and the door rises a
// hand's width above its guard height, which is the Banished Knight's own stab tell: the silhouette change
// is on the OFF arm. The strike is the arm thrown long with a half-step of lunge behind it.
const THR_WIND_SH = 26.0;
const THR_WIND_EL = -52.0; // the fist chambered back…
const THR_WIND_ABD = 14.0;
const THR_WIND_TILT = 60.0; // …point held ON HIM — which on a man a third his height means angled DOWN
const THR_WIND_LEAN = -8.0;
const THR_OFF_RISE = 9.0; // deg the shield shoulder lifts — the off-arm tell
const THR_HIT_SH = 54.0; // the arm goes LONG…
const THR_HIT_EL = -4.0;
const THR_HIT_TILT = 14.0; // …and the point DOWN the line to a hero's chest — read off the tip map, not argued
const THR_HIT_LEAN = 20.0; // the lunge
const THRUST_STEP = 0.60; // pre-scale metres of ground the lunge carries him — half the move's whole band

// THE SLAM: the door itself hauled UP — face skyward at the top, the one time his front stands open — and
// driven into the earth ahead of him. The sword arm swings back as ballast; the body coils and then folds
// through the drive.
const SLM_WIND_SH = -132.0; // the shield arm hauls the door overhead
const SLM_WIND_EL = -30.0;
const SLM_WIND_ABD = 26.0;
const SLM_WIND_LEAN = -18.0;
const SLM_WIND_TWIST = 14.0;
const SLM_HIT_SH = 64.0; // …and drives it down-forward
const SLM_HIT_EL = -10.0;
const SLM_HIT_LEAN = 36.0;
const SLM_HIT_TWIST = -8.0;
/// The door's own pitch through the move (`slamPitch`, applied in `shieldXf`): hauled up it turns FACE
/// SKYWARD, driven down it slams FACE INTO THE EARTH — the mesh tells the same story as the blow.
const SLM_PITCH_UP = -56.0; // shy of edge-on: a door pitched flat to the sky vanishes from the man under it
/// …and RAKED into the earth at the end of it, not laid flat on top of it. At 84 the door finished dead
/// horizontal and read as a table someone had put down; a slam drives the leading edge IN and leaves the
/// board standing off the ground behind it, which is also the shape the crater and the recovery need.
const SLM_PITCH_DOWN = 66.0;
/// THE DOOR'S OWN TRAVEL (`slamCarry`), in his body frame — UP clear of his crown on the haul, then DOWN and
/// FORWARD to meet the ground ahead of his boots. Without these the move was a pure pitch about a grip that
/// sits near the door's top edge, which swings its whole body through his chest. Verified on the shot, which
/// is the only way a number like this is ever right.
/// **AND THE CARRY IS ON TOP OF WHATEVER THE ARM IS ALREADY DOING**, which is the trap here: authored as
/// if it had to move the door the whole way, the drive's `fwd` stacked on the arm's own swing and threw
/// four metres of shield a body-length PAST the crater it is supposed to be planting in — the shot showed
/// the door lying flat on the ground somewhere off his shoulder. The arm does most of the travel; these are
/// only what the arm cannot reach. Verified on the shot, which is the only way a number like this is right.
const SLM_CARRY_UP = 0.60 * H;
const SLM_CARRY_END_Y = -0.10 * H;
const SLM_CARRY_FWD = 0.20 * H;

// THE CHARGE. The wind lowers him BEHIND the door — brace deep, trunk dropped, the sword trailing straight
// back like a rudder — and the travel keeps that shape with the stride running under it. The brake rears
// him back off his own momentum with the door swung out, which is the opening the sidestep earns.
const CHG_LEAN = 22.0;
const CHG_OFF_SH = 34.0; // the door braced square, taking the field with it
const CHG_OFF_EL = -96.0;
const CHG_ARM_SH = -38.0; // the sword arm swept back behind him
const CHG_ARM_ABD = 30.0;
const CHG_ARM_SWEEP = -30.0;
const CHG_TILT = 12.0;
const BRAKE_LEAN = -26.0; // hauled back over his heels through the skid
const BRAKE_OFF_SH = -20.0; // the door thrown wide off the line
const BRAKE_OFF_ABD = 44.0;

/// Lowered behind the door, ready to come through the field.
const P_CHG = P{ .armSh = CHG_ARM_SH, .armEl = -16.0, .armAbd = CHG_ARM_ABD, .armSweep = CHG_ARM_SWEEP, .tilt = CHG_TILT, .offSh = CHG_OFF_SH, .offEl = CHG_OFF_EL, .offAbd = GUARD_ABD + 6.0, .lean = CHG_LEAN, .twist = -10.0, .head = 10.0, .brace = 0.72 };
/// …the same shape with the coil released into the run: the stride has the legs, so the brace lets go.
const P_CHG_RUN = P{ .armSh = CHG_ARM_SH, .armEl = -16.0, .armAbd = CHG_ARM_ABD, .armSweep = CHG_ARM_SWEEP, .tilt = CHG_TILT, .offSh = CHG_OFF_SH, .offEl = CHG_OFF_EL, .offAbd = GUARD_ABD + 6.0, .lean = CHG_LEAN, .twist = -10.0, .head = 10.0, .brace = 0.30 };
/// The skid's peak: reared over his heels against his own momentum, the door swinging off the line.
const P_SKID = P{ .armSh = CHG_ARM_SH, .armEl = -16.0, .armAbd = CHG_ARM_ABD, .armSweep = CHG_ARM_SWEEP, .tilt = CHG_TILT, .offSh = BRAKE_OFF_SH, .offEl = GUARD_EL + 30.0, .offAbd = BRAKE_OFF_ABD, .lean = BRAKE_LEAN, .twist = 14.0, .head = -12.0, .brace = 0.85 };
/// …and where the skid leaves him: door wide, weight back, the opening the sidestep just earned. This is
/// the recover's held End Pose, so the brake ENDS here — the old pair re-hauled the door wide again on the
/// state seam, a pop the springs were quietly eating.
const P_SKID_END = P{ .armSh = CARRY_SH + 4.0, .armEl = CARRY_EL, .armAbd = CARRY_ABD + 10.0, .offSh = BRAKE_OFF_SH, .offEl = GUARD_EL + 30.0, .offAbd = BRAKE_OFF_ABD, .lean = BRAKE_LEAN + 8.0, .twist = 14.0, .head = -12.0, .brace = 0.45 };

/// THE CHARGE, off its own keyed tracks like everything else he does: a sink, the lowering behind the door,
/// the held travel shape, and the skid (`recover` here is the BRAKE — the post-brake ease home is `CHG_REC`).
const CHARGE_KEYS = MoveKeys{
    .wind = &.{
        .{ .t = 0.00, .p = .{} },
        // He sinks first — the same earliest-legible frame as the slam's dip — and the sword arm starts back.
        .{ .t = 0.30, .p = .{ .lean = GUARD_LEAN + 8, .head = 8, .brace = 0.52, .offSh = GUARD_SH + 6, .offEl = GUARD_EL + 4, .armSh = CARRY_SH - 12, .armSweep = -10 }, .ease = .decel },
        .{ .t = 1.00, .p = P_CHG, .ease = .accel },
    },
    .strike = &.{
        .{ .t = 0.00, .p = P_CHG },
        .{ .t = 0.30, .p = P_CHG_RUN, .ease = .decel },
        .{ .t = 1.00, .p = P_CHG_RUN },
    },
    .recover = &.{
        .{ .t = 0.00, .p = P_CHG_RUN },
        .{ .t = 0.38, .p = P_SKID, .ease = .decel },
        .{ .t = 1.00, .p = P_SKID_END },
    },
};
/// Seconds into the travel the coil finishes releasing — the strike track's own clock, since the travel's
/// LENGTH varies with where you stood.
const CHG_LOOSE = 0.30;
/// After the brake: the End Pose held, then home. `END_HOLD`'s law, as keys.
const CHG_REC = [_]PoseKey{
    .{ .t = 0.00, .p = P_SKID_END },
    .{ .t = END_HOLD, .p = P_SKID_END },
    .{ .t = 1.00, .p = .{}, .ease = .decel },
};

// THE HOP: a knee-dip, one sideways bound with the door kept square to him, a heavy settle. The body BANKS
// into the travel a few degrees — a five-metre statue does not glide sideways level.
const HOP_BANK = 8.0;

/// HOW LONG A RECOVER HOLDS ITS END POSE before easing home (fraction of the recover) — the five-phase
/// contract's held End Pose (docs/ELDEN_RING.md §7): an attack that flows straight back to the carry reads
/// as rubber, and the held pose IS the punish window being SHOWN.
const END_HOLD = 0.32;

// THE FALL's own posture. He goes RIGID — a felled statue, not a man tripping.
// **AND THE TELL TRAVELS, not just lasts** (owner: it needs more tell). At −13 deg of hang-back off a 7 deg
// carry the whole gather moved the trunk twenty degrees across the longest wind in the game, which is a
// committed move showing almost nothing. He now rocks a clear 24 deg FORWARD over his toes and then hangs
// 30 deg back past the vertical — a mass visibly going over before it goes.
const FALL_WIND_LEAN = -30.0; // rocks FORWARD first (anticipation), then hangs back over his heels
const FALL_WIND_GATHER = 24.0;
// BOTH ARMS CLAMP IN OVER THE CHEST as he goes — and these are read against the GUARD pose, so they moved
// with it. Authored at 24/−38 against a guard of 52/−92 they were a fold INWARD; against the new 6/−126 the
// same numbers OPENED the arm and swung the door out edge-on beside him through the whole tell, which is the
// one move where the door is what lands on you.
const FALL_SH = 4.0;
const FALL_EL = -100.0;
const FLOORED_TILT = 4.0; // where the blade sits while he is off his feet — a short walk from the carry
const RISE_KNEE = 92.0; // the knee that comes under him
const RISE_HIP = 72.0;

const GATHER_HEAVY = 1.5; // grit a tell drags up, by what is loading
const GATHER_FALL = 1.9;
const GATHER_PLAIN = 0.95;

const State = enum {
    idle,
    approach,
    hop,
    /// **THE PIVOT STEP** — how a man in five metres of armour actually changes which way he is pointing.
    stepturn,
    /// …and the LEAP, for when the ground answer is already too late: he coils, bounds away, turns in the
    /// air and lands facing you.
    leapwind,
    leap,
    /// PHASE TWO'S ONE SIGNATURE MOVE: the blade hauled up and held while chaos gathers onto it.
    awaken,
    sweepwind,
    sweep,
    chainwind,
    sweep2,
    overwind,
    over,
    thrustwind,
    thrust,
    bashwind,
    bash,
    /// The quick side answer (`SWAT`) — door on the shield side, blade on the sword side.
    swatwind,
    swat,
    slamwind,
    slam,
    chargewind,
    charge,
    brake,
    recover,
    fallwind,
    fall,
    downed,
    rollover,
    rise,
    stunlight,
    stunheavy,
    dead,
};

/// Which move a stroke/recovery belongs to. The FALL is deliberately in here: its recovery is three states
/// of its own rather than a row of `.recover`, because getting up is not the same shape as unwinding a swing.
const Blow = enum { sweep, sweep2, over, thrust, bash, swat, slam, charge, fall };

const MOVES = [_]Attack{ SWEEP, OVERHEAD, THRUST, BASH, SWEEP2, SWAT };
pub const SWEEP_I = 0;
pub const OVER_I = 1;
pub const THRUST_I = 2;
pub const BASH_I = 3;
pub const SWEEP2_I = 4;
pub const SWAT_I = 5;

comptime {
    // **THE INDICES ARE PINNED TO THE ROWS THEY NAME.** They are hand-written ordinals mirroring `MOVES`'
    // ORDER, and every one of `keysFor`, `routeFor`, `windState`, `cdSlot`, `blowOf`, the `cds` array and
    // `takeParry`'s SWEEP2→SWEEP chain resolves through them — so inserting a seventh stroke anywhere but the
    // end, or reordering the table, silently re-points the whole kit and still compiles. `FOE_GROUPS`'
    // arrangement in `game.zig`: a table that cannot be derived is cross-checked against the one it mirrors.
    const named = .{ .{ SWEEP_I, SWEEP }, .{ OVER_I, OVERHEAD }, .{ THRUST_I, THRUST }, .{ BASH_I, BASH }, .{ SWEEP2_I, SWEEP2 }, .{ SWAT_I, SWAT } };
    if (named.len != MOVES.len) @compileError("knight: MOVES and the *_I indices disagree on how many strokes there are");
    for (named) |row| {
        if (!std.meta.eql(MOVES[row[0]], row[1])) @compileError("knight: a *_I index no longer names its own row of MOVES");
    }
    // …and `classify` only ever picks out of the FIRST `CHOOSE_N`, so the chain-only strokes must sit past it.
    std.debug.assert(CHOOSE_N <= MOVES.len and SWEEP2_I >= CHOOSE_N and SWAT_I >= CHOOSE_N);
}
/// …and only the first four are `classify`'s to pick: the second sweep exists as a chain — off a finished
/// sweep (the Sentinel's delayed double) or off a thrust (its documented quick-swing follow-up).
const CHOOSE_N = 4;

/// The SWEEP may be thrown well off square — its arc reaches past his own far shoulder, so its aim is
/// honestly loose where the bash/overhead/thrust are held to `SWING_BEARING`'s tight door.
/// **THE SWEEP ANSWERS HIS WHOLE FRONT** (owner: he needs readable sweeps that reach the entire front). At
/// 55 a quarter of his own frontal arc was ground no sweep would ever be thrown at, which is the "safest
/// square on the board" failure one ring further out. Widened, and the GATHER is lengthened with it
/// (`SWEEP.windDur`) so the wind can still close what the bearing now promises — a wider stroke bought with
/// a longer tell is exactly the trade asked for, since the same change is what makes it readable.
const SWEEP_BEARING = 72.0;
/// …AND HOW WIDE A BEARING A SWEEP MAY BE *STARTED* FROM, which is a different question from where it may
/// LAND. The gather is the aim: `sweepwind` turns at his full `TURN_RATE` for its whole 1.15 s, which carries
/// about 38 deg, so a sweep begun out here arrives inside `SWEEP_BEARING` under its own steam. Sized so the
/// wind can actually close the gap — past this he squares up first, which is what he did with the whole
/// flank before. A test walks the wind and pins that the arrival is inside the door.
/// **AND IT MOVES WITH THE WIND IT DEPENDS ON.** The gather carries `TURN_RATE x SWEEP.windDur` of bearing
/// — about 31 deg now the winds are shortened (owner: his wind-ups are too long) — so this is
/// `SWEEP_BEARING` plus that and no more. Authored as a free number it silently became a promise the
/// shortened gather could not keep, and he threw sweeps at places the arc was never going to reach. A test
/// walks the wind frame by frame and pins the arrival inside the door.
const FLANK_BEARING = SWEEP_BEARING + 28.0;

/// **THE WHOLE STRING IS ONE COMMITMENT, AND THE DEBT IS PAID AT THE FINISHER** (docs/ELDEN_RING.md §7: the
/// Crucible's strings run "1-4 hits, variable", recovery "3-4 frames mid-combo but 23-24 frames at combo
/// end"). Every stroke here used to be an island — full wind, full recover, then a three-to-nine second
/// cooldown — so the fight was a metronome of single pokes with dead air between them, and `classify` spent
/// most of its returns on `.wait`. What may follow what, and nothing follows the OVERHEAD: its blade ends in
/// the earth and the held End Pose IS the window that move is priced around.
fn stringNext(cur: usize) ?usize {
    return switch (cur) {
        SWEEP_I => SWEEP2_I, // the Sentinel's authored double, same direction, "slightly delayed"
        SWEEP2_I => THRUST_I, // …and he steps through the second arc onto the point
        THRUST_I => SWEEP2_I, // the reference's own "may be followed up with a quick horizontal swing"
        BASH_I => THRUST_I, // shoved off his boots and stabbed on the way out
        else => null,
    };
}
/// **AND A COMBO IS A FIXED ROUTE, NOT A COIN FLIP AT EVERY LINK** (owner: longer combos; memorization, not
/// luck). Rolled continuation means the same opener runs two hits one time and four the next, so the player
/// can never learn where a string ENDS — and where it ends is the punish window, which is the only thing
/// the string exists to sell. Each opener now has ONE route it always walks. The thing the player reads is
/// WHICH opener he chose, which is a silhouette, and from there the whole string is known: what is coming,
/// how many, and exactly when it is over.
///
/// Longer than the old two-or-three, because a route you can recite is one you can survive.
fn routeFor(mv: usize) []const usize {
    return switch (mv) {
        // The Sentinel's authored double, then he steps through the second arc onto the point, and the
        // FLICK on the end — which is the link that catches somebody who read the first three and moved in.
        SWEEP_I => &[_]usize{ SWEEP2_I, THRUST_I, SWAT_I },
        // Shoved off his boots, stabbed on the way out, and the yard cleared behind it.
        BASH_I => &[_]usize{ THRUST_I, SWEEP_I, SWEEP2_I },
        // The reference's own "may be followed up with a quick horizontal swing", and then the double.
        THRUST_I => &[_]usize{ SWEEP2_I, THRUST_I },
        SWEEP2_I => &[_]usize{ THRUST_I, SWAT_I },
        // **THE SWAT OPENS THE LONG ONE** (owner: mixups and surprises — swat and leap and sweep). A flick
        // costs him almost nothing, so it is the cheapest way into a real string: the player who learns to
        // treat it as harmless is the player it is written for. Four links, and it ends on the overhead —
        // the one move with no route out of it, so the string's end is always the same held pose.
        SWAT_I => &[_]usize{ THRUST_I, SWEEP_I, OVER_I },
        // NOTHING follows the overhead. Its blade ends in the earth and the held End Pose IS its window —
        // a route out of it would be selling the same window twice.
        else => &[_]usize{},
    };
}
/// …and the mid-string wind, as a fraction of the move's own. Floored at `foe.TELL_MIN` — a link is still an
/// attack and no attack in this game comes out of nowhere — but a string that re-wound in full between hits
/// would just be three separate moves with the recovery deleted.
const STRING_WIND_MUL: f32 = 0.55;
/// How much dearer each extra link makes the rest afterwards. A flurry buys the player a longer quiet.
const STRING_CD_PER_LINK: f32 = 0.22;

/// Seconds into a wind by which both feet are down (`planted`). Under every wind he has, so the plant is
/// always finished before the stroke it is bracing.
const PLANT_IN: f32 = 0.30;

/// **WHAT EACH OF HIS LANDINGS IS WORTH THROUGH THE LENS AND THE PAD** (owner: needs more shake/particle
/// impact). Only three things used to shake the frame at all — the fall, the crater and the charge's skid —
/// so the moves the player meets most often, the ones that actually land on him, arrived silently as far as
/// the camera was concerned. Every impact this creature makes now has weight behind it, scaled to the mass
/// that arrived: the body going over is still the biggest thing that happens, and nothing may outrank it.
const QUAKE_FALL: f32 = 0.46;
const QUAKE_CRATER: f32 = 0.40;
/// The charge has no landing of its own on this ladder: what it hits arrives through `heroTakes` as a blow,
/// and what it MISSES is the skid below. A `QUAKE_CHARGE` sat here unused, which read as a row nobody had
/// wired rather than as a move the ladder deliberately does not cover.
const QUAKE_BRAKE: f32 = 0.24;
const QUAKE_SWEEP: f32 = 0.20;
const QUAKE_OVER: f32 = 0.30; // the blade ENDS in the earth — this one is a landing, not a swing
const QUAKE_BASH: f32 = 0.22;
const QUAKE_REPEL: f32 = 0.14; // …and the smallest, because it happens most
const QUAKE_STEP: f32 = 0.07; // five metres of armour walking is felt, faintly, every footfall

/// HALF THE DISTANCE BETWEEN HIS BOOTS, pre-scale — the radius each foot sweeps when he turns on the spot.
/// It is what converts a yaw rate into the ground his feet actually cover, so a pivot drives the gait.
const TURN_STANCE_HALF: f32 = 0.105;

/// The wind a move opens in. One table, because `decide` and the string both pick a state off a move index
/// and two copies of this switch is two places for a move to route to the wrong gather.
fn windFor(mv: usize) State {
    return switch (mv) {
        SWEEP_I => .sweepwind,
        OVER_I => .overwind,
        THRUST_I => .thrustwind,
        SWEEP2_I => .chainwind,
        else => .bashwind,
    };
}

const Choice = enum { fall, slam, hop, charge, strike, approach, wait, hold, stepturn, leap };

/// Pure, so the whole of his decision-making is testable without a world — and shaped like the brain the
/// reference actually runs (docs/ELDEN_RING.md §7): DISTANCE BANDS with DICE ODDS inside each, so no range
/// names one move and no punish count can be memorized off the range alone. `roll` is the frame's die
/// (0..1), passed IN so the function stays pure. `circling` is "the bearing is moving fast" — the hero
/// orbiting — which is the one thing the HOP answers.
const Decision = struct { what: Choice, mv: usize = SWEEP_I, shove: bool = false, shoveShield: bool = false };

// **HE IS LEARNED, NOT ROLLED** (owner: tough but fair, requiring memorization, not luck).
//
// The brain was distance bands with DICE inside each, and this file used to argue that as a virtue — "no
// punish count can be memorized off spacing alone". That is the wrong target. A die cannot be learned, only
// survived: it makes a fight that is different every attempt, which reads as luck however fair the numbers
// are. What the reference actually does is the Tree Sentinel's — attack choice is POSITIONALLY DETERMINISTIC
// and "stand on the shield side" is a rule players write down.
//
// So each band-and-side has an ORDERED PATTERN and he walks it. Stand still and you can recite what is
// coming; move and you get the other pattern, mid-rotation. The variety comes from the player's own feet,
// which is the only place variety is ever worth having, and every death is a thing you could have known.
const BOOTS_SWORD = [_]usize{ BASH_I, SWAT_I, SWEEP_I, BASH_I, THRUST_I };
const BOOTS_SHIELD = [_]usize{ SWEEP_I, BASH_I, SWAT_I, SWEEP_I, OVER_I };
const RANGE_SWORD = [_]usize{ SWEEP_I, THRUST_I, SWAT_I, SWEEP_I, OVER_I };
const RANGE_SHIELD = [_]usize{ OVER_I, SWEEP_I, THRUST_I, SWAT_I, OVER_I };

/// Walk a pattern from `cursor`, taking the first entry that is actually available — a move on cooldown is
/// SKIPPED, never waited for, and the player just watched him spend it so the skip is legible too. The
/// tight-bearing moves still refuse a bearing their arc cannot reach.
fn pick(pattern: []const usize, cursor: usize, off: f32, ready: []const bool, stepReady: bool) Decision {
    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        const mv = pattern[(cursor + i) % pattern.len];
        if (!ready[mv]) continue;
        // **EACH MOVE ANSWERS FOR ITS OWN FRONT** (`Attack.bearing`). One global `tight` at 24 deg meant
        // anything past a narrow cone was answered only by the sweep, so standing forty degrees off his
        // nose — squarely in front of the door — was the safest ground on the board.
        if (off > MOVES[mv].bearing) continue;
        return .{ .what = .strike, .mv = mv };
    }
    // NOTHING IN THE PATTERN IS UP — so he SQUARES UP rather than looming. Every `.wait` on this creature
    // was a second of him doing nothing while being hit, and he had four of them.
    if (stepReady and off >= STEPTURN.least) return .{ .what = .stepturn };
    return .{ .what = .wait };
}

fn classify(dist: f32, bearingDeg: f32, scale: f32, fallReady: bool, slamReady: bool, chargeReady: bool, hopReady: bool, stepReady: bool, leapReady: bool, circling: bool, pressed: bool, cursor: usize, ready: []const bool) Decision {
    if (dist > AGGRO_R) return .{ .what = .hold };
    const b = @abs(bearingDeg);
    // WHICH SIDE OF HIM YOU ARE ON IS A RULE YOU CAN LEARN (the Tree Sentinel's grammar — ELDEN_RING.md §7:
    // attack choice is positionally deterministic, and "stand on the shield side" is the documented player
    // rule). His shield is his LEFT arm, which is a POSITIVE bearing here: over there the door is between
    // you and everything, so what he can throw is the slow, committed, well-signalled half of the kit. Come
    // round to his sword side and the fast half opens up. Range dices WHICH move; the side dices HOW BIG.
    const shieldSide = bearingDeg > 0;
    // BEHIND HIM IS WHERE HE FALLS. Dead behind and inside his own length; with the fall cooling, the hop
    // re-squares him on a circler, and otherwise he turns — which is what shuts the flank.
    if (b >= 180.0 - FALL_SECTOR) {
        if (fallReady and dist <= crushLen(scale)) return .{ .what = .fall };
        // **CAUGHT BEHIND WITH THE FALL COLD, HE LEAVES — IF IT IS COSTING HIM.** The pivot step takes more
        // than one beat to bring his front back from dead behind, by design, so with a man on his spine
        // inside his own length ACTUALLY HURTING HIM the honest answer is to buy ground and land facing him.
        // It costs him his reach, which is the trade that stops it being strictly good.
        //
        // **AND WITH NOBODY HURTING HIM HE STEPS INSTEAD** (owner: sometimes he should simply attack more
        // rather than reposition). Standing behind a boss you are not damaging is not a threat, and leaving
        // over it is what made the leap read as a tic rather than as an answer.
        if (leapReady and pressed and dist <= crushLen(scale) * 0.9) return .{ .what = .leap };
        if (hopReady and circling and pressed) return .{ .what = .hop };
        // …and with both spent he does not stand there rotating: he STEPS round (owner: he needs to protect
        // his sides more aggressively). It takes more than one step to get his front back from dead behind,
        // which is what keeps the back worth reaching for.
        if (stepReady) return .{ .what = .stepturn };
        return .{ .what = .wait };
    }
    // THE WIDE FLANK, AND IT IS NO LONGER FREE. It used to be the one place the answer was `.wait` — he
    // turned at 33 deg/s and did nothing, so parking on his quarter was a punching bag and the whole fight
    // was a treadmill. The SWEEP is what reaches out here: its arc carries past his own far shoulder, and
    // its wind is a full second of him visibly planting and squaring onto you (`sweepwind` turns at his full
    // rate — the gather IS the aim). So the flank is still the way in, but standing in it is not.
    if (b > SWEEP_BEARING) {
        // **THE SWORD SIDE HAS AN ANSWER NOW** (owner: no defence on his right side). His shield is his
        // LEFT arm — a positive bearing here — so standing off his RIGHT shoulder inside his own reach was
        // the one square on the board with nothing aimed at it: the bash goes down his front, the sweep
        // needs a bearing its arc can reach, and the hop only re-squares him. The SHOVE hauls the door
        // across onto that side, and it is checked before the sweep because it is the closer answer.
        // **AND THE QUICKEST ANSWER COMES FIRST.** The SWAT is a third of a second of gather against the
        // sweep's four fifths and the shove's half, so it is what actually reaches somebody standing beside
        // him — the slower answers were all outpaced by simply keeping up with his shoulder. Which picture
        // you get is which side you chose: the door on his shield side, the blade on his sword side.
        // …and it is a SIDE answer, not a back one: past what his shoulders can turn on, a flick reaches
        // nothing and the honest response is the pivot step below.
        if (b <= FLANK_BEARING and ready[SWAT_I] and dist <= triggerR(MOVES[SWAT_I], scale)) {
            return .{ .what = .strike, .mv = SWAT_I };
        }
        // **AND A CIRCLER GETS ONE THROWN AT HIM WHEREVER HE IS** (owner: a swipe on either side to make you
        // dodge, so you can't just circle forever). Orbiting used to beat everything out here on its own:
        // the sweep needs a bearing its arc can reach, the shove needs the sword side, and the pivot step
        // just watched you go past. The swat is a third of a second and it comes out on whichever side you
        // are on, so holding an orbit now costs a dodge every time it comes up.
        if (circling and ready[SWAT_I] and dist <= triggerR(MOVES[SWAT_I], scale) * SWAT_ORBIT_BAND) {
            return .{ .what = .strike, .mv = SWAT_I };
        }
        // **NEITHER SHOULDER IS A FREE LAP** (owner). A wall between you and him stops blows, it does not
        // throw them, so the flank he was best equipped to punish from was the one nothing came out of. Same
        // row and window either way; what differs is where the door goes — ACROSS his front onto the sword
        // side, or OUT along the shield side, where the haul is SHORT (`SHOVE_SHIELD_WIND`). It fires on
        // PRESENCE on both, and it answers for its own front like everything else (`FLANK_BEARING`): a door
        // thrown past that is a promised miss.
        if (b <= FLANK_BEARING and ready[BASH_I] and dist <= triggerR(MOVES[BASH_I], scale) * SHOVE_BAND) {
            return .{ .what = .strike, .mv = BASH_I, .shove = true, .shoveShield = shieldSide };
        }
        // **AND THE GROUND ANSWERS ARE BOUGHT WITH DAMAGE, NOT WITH BEING WALKED AROUND** (owner: he jumps a
        // bit too often; he should reposition if he's taking heavy damage in his current position). Being
        // orbited is what a player does for the whole fight, so an orbit alone put the hop on a clock and it
        // read as a tic. The swat above already answers a circler — with the kit, which is what a boss
        // should answer with — and the feet answer the thing the kit cannot: this spot is costing him.
        if (hopReady and circling and pressed) return .{ .what = .hop };
        if (b <= FLANK_BEARING and ready[SWEEP_I] and dist <= triggerR(MOVES[SWEEP_I], scale)) {
            return .{ .what = .strike, .mv = SWEEP_I };
        }
        // **AND THE LAST WORD ON HIS FLANK IS A STEP, NOT A SHRUG.** `.wait` here was the passive answer
        // that made standing off his shoulder free; the pivot step is the aggressive one, and it is what
        // turns "walk round him once" into "keep moving or he gets his front back".
        // **AND HE WILL LEAVE RATHER THAN GRIND ROUND — ONCE IT IS COSTING HIM** (owner: more inclined to
        // jump to reposition, then: he jumps a bit too often). Out past what the sweep's gather can close,
        // the pivot step needs several beats to bring his front back, so with real damage landing on this
        // patch the leap is what he takes and he lands with the argument already won. Unpressed he grinds
        // round on his feet, which is the beat a player needs to actually get a swing in.
        if (leapReady and pressed and b > FLANK_BEARING) return .{ .what = .leap };
        if (stepReady and b >= STEPTURN.least) return .{ .what = .stepturn };
        return .{ .what = .wait };
    }
    // ON HIS BOOTS: the proximity taxes — the bash shoves you off, the slam buries you, the sweep clears
    // the whole yard. **AND WHICH ONE IS A ROTATION, NOT A DIE** (see `PATTERNS`).
    if (dist <= triggerR(MOVES[BASH_I], scale)) {
        if (slamReady and cursor % 3 == 2) return .{ .what = .slam };
        return pick(if (shieldSide) &BOOTS_SHIELD else &BOOTS_SWORD, cursor, b, ready, stepReady);
    }
    // SWORD RANGE: the big three. Shield side leans on the OVERHEAD (the longest wind, the held End Pose);
    // sword side leans on the sweep and the thrust — the Tree Sentinel's learnable "stand on the shield
    // side" rule, which only teaches anything if the sides genuinely differ and genuinely repeat.
    if (dist <= triggerR(MOVES[SWEEP_I], scale)) {
        return pick(if (shieldSide) &RANGE_SHIELD else &RANGE_SWORD, cursor, b, ready, stepReady);
    }
    // THE THRUST'S OWN BAND — "only used when no other attacks will reach": the posed point plus the lunge
    // under it. It is also the shortest clock he has, which is what keeps a spacing fight from being a
    // staring contest.
    if (dist <= thrustBandR(scale)) {
        if (b <= THRUST.bearing and ready[THRUST_I]) return .{ .what = .strike, .mv = THRUST_I };
        if (stepReady and b >= STEPTURN.least) return .{ .what = .stepturn };
        return .{ .what = .wait };
    }
    // OUT OF REACH ENTIRELY: kept there long enough, he comes to you all at once; otherwise he walks.
    if (chargeReady and dist >= CHARGE.far * 0.75) return .{ .what = .charge };
    return .{ .what = .approach };
}

fn triggerR(a: Attack, scale: f32) f32 {
    return a.reachOut * scale + HERO_REACH;
}

/// HOW FAR BEHIND HIM THE FALL REACHES, hero footprint included — the crush test, the AI's own band and the
/// length test all ask this one function.
fn crushLen(scale: f32) f32 {
    return FALL_LEN * scale + HERO_REACH;
}

/// Grip end -> far end of the sword, in the mesh's own authored frame: ridden through `xf[WPN]` this IS the
/// blade's world segment, and it is the only thing the swipes hit with.
const FIST_Y = -0.05 * H;
const FIST_Z = 0.02 * H;
const SW_GUARD = 0.130 * H; // fist -> crossguard
/// GUARD -> POINT, and it is bracketed from ABOVE by what the sweep is allowed to reach. Authored at 0.84·H
/// — the warrior's own proportion — the first blade measured 4.45 m and the stroke arrived 6.9 m off his
/// axis, which out-ranges the ogre's whole sweep and makes walking round him pointless. At 0.57·H it is
/// still a greatsword by proportion and the stroke lands where a boss's stroke should.
const SW_BLADE = 0.57 * H;
/// …and the blade at its broadest, which is also the swipes' hurt radius. It WAS 0.032·H — 0.34 m across on
/// a near-3 m edge, about 8:1, a PLANK where a greatsword is nearer 20:1 (the logged gap). At 0.019·H the
/// proportion is a blade's and the mechanic barely moves: `HERO_REACH` dominates the hurt radius.
const SW_HALF_W = 0.019 * H;
const SW_SEG = [2]rl.Vector3{
    v3(0, FIST_Y + SW_GUARD, FIST_Z),
    v3(0, FIST_Y + SW_GUARD + SW_BLADE, FIST_Z),
};

/// The sword is authored pointing UP off the grip, so the fit flips it. After that `wpnTilt` means what
/// `hero.GRIP_PITCH` means: degrees the blade leads forward of the forearm line.
fn wpnFit(tilt: f32) rl.Matrix {
    return mul(ry(180.0), rx(180.0 - tilt));
}

/// For the shot harness to aim its beats with — a portrait pinned to a literal 0.6 s silently photographs a
/// different beat the next time the timing moves.
pub fn moveClock(mv: usize) foe.Clock {
    const a = MOVES[@min(mv, MOVES.len - 1)];
    return .{ .wind = a.windDur, .strike = a.strikeDur, .recover = a.recoverDur };
}
/// …and the FALL's, whose recovery is three states rather than one.
pub const FallClock = struct { wind: f32, drop: f32, down: f32, roll: f32, rise: f32 };
pub fn fallClock() FallClock {
    return .{ .wind = FALL_WIND_DUR, .drop = FALL_DUR, .down = DOWN_DUR, .roll = ROLL_DUR, .rise = RISE_DUR };
}
/// …the SLAM's…
pub fn slamClock() foe.Clock {
    return .{ .wind = SLAM.windDur, .strike = SLAM.strikeDur, .recover = SLAM.recoverDur };
}
/// …and the CHARGE's, whose "strike" is however long the committed run lasts at most.
pub fn chargeClock() foe.Clock {
    return .{ .wind = CHARGE.windDur, .strike = CHARGE.range / CHARGE.speed, .recover = CHARGE.brakeDur + CHARGE.recoverDur };
}
/// …and the two repositioning moves, for the harness only: the instant the LEAP is highest off the earth,
/// and the middle of the PIVOT STEP's drive. Framing is part of the test, and both of these are one frame
/// each — shot anywhere else they are a knight standing still.
/// …and deep into the awakening's HOLD, which is where the chaos on the blade is thickest.
pub fn awakenPeak() f32 {
    return AWAKEN.liftDur + AWAKEN.holdDur * 0.85;
}
pub fn leapPeak() f32 {
    return LEAP.windDur + LEAP.flightDur * 0.5;
}
pub fn stepTurnMid() f32 {
    return STEPTURN.windDur + STEPTURN.turnDur * 0.6;
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    shield: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("knight material");
        mat.shader = shader;
        return .{ .bone = buildMeshes(), .shield = shieldMesh(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, k: *const Knight) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, k.xf[i]);
        // THE DOOR IS NOT A BONE — it rides the left wrist, `hero.shieldFit`'s pattern (see `shieldXf`).
        rl.drawMesh(self.shield, self.mat, k.shXf);
    }
};

pub const Knight = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// THE WAND'S ROOTS (combat.Root) — stamped from outside, like the leash's eyes. They do NOT gate the
    /// fall: holding a man's feet is very nearly how you make him fall over.
    root: combat.Root = .{},
    /// THE RIME BREATH'S COLD (`combat.Chill`) — stamped from outside like the roots, and billed through the
    /// same `foe.grip`. On him it is worth more than on anything else: he is already out-turned, and taking
    /// his TRAVEL is what buys the walk round the door.
    chill: combat.Chill = .{},
    /// …and THE HERO'S SHIELD, stamped the same way (`game.markParry`). Read only inside his own windows.
    parry: foe.Parry = .{},
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    /// Which move is in progress — an index into `MOVES` — and which family the recovery is serving.
    atk: usize = SWEEP_I,
    blow: Blow = .sweep,
    cds: [MOVES.len]f32 = [_]f32{0} ** MOVES.len,
    fallCd: f32 = 0,
    slamCd: f32 = 0,
    chargeCd: f32 = 0,
    hopCd: f32 = 0,
    /// The pivot step's own clock — it is a commitment with a plant you can hear, not a free re-face.
    stepCd: f32 = 0,
    leapCd: f32 = 0,
    /// …and the flank ANSWER's own clock (`counterFlank`).
    counterCd: f32 = 0,
    /// **IS THE SWORD LIT** — phase two, and the one flag the second half of the fight hangs off. It is a
    /// LATCH: nothing turns it back off, because a boss that de-escalates is a boss whose phase means
    /// nothing.
    lit: bool = false,
    awoken: bool = false, // …and the awakening fires exactly once, whatever the bar does afterwards
    /// A move CHAINED off the end of a pivot step, or null for a plain re-face. The flank counter is a
    /// step-turn plus this — he has to turn onto you before he can answer, and you can watch him do it.
    stepThen: ?usize = null,
    /// HOW FAR OFF THE EARTH HE IS mid-leap (world units, rides the ROOT translate — the archer's `hop`),
    /// and the line the flight was committed to. `airborne` reads the first.
    air: f32 = 0,
    leapDir: rl.Vector3 = mathx.zero3,
    /// Was this leap CHAINED off a flank swipe — the fast, mean one (`leapWind`).
    leapChained: bool = false,
    /// SECONDS HE HAS BEEN KEPT AT RANGE — the charge's fuse. It fills while the fight is on and you are
    /// past `CHARGE.far`, drains twice as fast when you close, so ducking in and out does not bank one.
    farT: f32 = 0,
    /// Seconds the blade HANGS at the top of the overhead before it drops — the Godrick knights' delayed
    /// downswing, rolled fresh per swing (the ogre's `windHold`): the tell varies, the parry does not,
    /// since the window reads the DROP.
    windHold: f32 = 0,
    /// THE GUARD COUNTER'S OWN CLOCK — the reference's "performs a Guard Counter if an attack lands on
    /// their shield". `caught` rolls the riposte off a blow that already struck HIS OWN door — world state,
    /// not the player's buttons: NO INPUT READING, EVER is the law it is written against.
    riposteCd: f32 = 0,
    /// HOW MANY LINKS OF THE CURRENT STRING ARE ALREADY THROWN, and which clocks it owes when it ends. The
    /// whole string is one commitment (`billString`), so nothing is billed until the finisher — and an
    /// interrupt bills it too, or a stagger would hand him a flurry with every cooldown still empty.
    strung: u8 = 0,
    strungUsed: [MOVES.len]bool = [_]bool{false} ** MOVES.len,
    /// WHICH MOVE OPENED THE STRING — the route is looked up off this and not off the link in progress, so
    /// the whole combo is decided by the one silhouette the player actually got to read.
    opener: usize = SWEEP_I,
    /// WHERE HE IS IN THIS BAND'S PATTERN (`BOOTS_*`/`RANGE_*`). Advanced once per committed strike, so a
    /// player who watches can recite what is coming — which is the entire difference between memorising a
    /// boss and gambling against one.
    cursor: usize = 0,
    /// THE BODY CHASING ITS POSE (`settlePose`). Continuous by construction, so it is also what makes every
    /// interrupt — a stagger, a parry, a cut recovery, a string link — ease instead of teleport.
    springs: anim.SpringBank(CHAN_N) = .{},
    /// Its own accumulator, beside `fxAccum` — the slam's ring tell runs at the same time as the gather and
    /// one counter shared between two emitters is two emitters stealing each other's motes.
    ringAccum: f32 = 0,
    /// …and the gather's FIRE has its own too (`emitGather`): the ember and the dust run together, and one
    /// counter shared between two emitters is two emitters stealing each other's motes.
    emberAccum: f32 = 0,
    /// Which way the hop goes — the sign of the bearing it answers.
    hopSide: f32 = 1,
    /// **HOW THE FIGHT IS GOING** (`foe.Sense`): the bearing's own measured rate and what standing here has
    /// cost him. Both were his alone and hand-rolled; they are the shared layer now because every creature
    /// that ever wants to leave a spot has to ask the same two questions.
    sense: foe.Sense = .{},
    dealt: bool = false, // one blow per stroke, latched
    strikeFelt: bool = false, // …and one shake and one burst of dust per stroke, on the same rule
    /// WHERE A CLOUD OF CHAOS GAS IS TO BE LAID THIS FRAME, or null. A one-frame flag on `quake`'s rule: the
    /// knight reports it and the GROUP owns the cloud, because a cloud outlives the stroke that made it and
    /// has to keep burning after the body that laid it has fallen over.
    gasAt: ?rl.Vector3 = null,
    /// Is the bash in progress the SHOVE — the door hauled across onto his sword side rather than driven
    /// down his front. One row, two pictures; set at the choose and read by the pose, the guard and the blow.
    shoving: bool = false,
    /// …and WHICH WAY it hauls: across his front onto the sword side, or out along the shield side. One
    /// number, `shoveDir`, so the pose, the door's carry and its yaw cannot disagree about where it went.
    shoveShield: bool = false,
    /// …and which side the SWAT is answering: the door on his shield side, the blade on his sword side.
    swatShield: bool = false,
    /// Where his body already WAS when he died — both channels, see `enterDeath`.
    deathFrom: f32 = 0,
    rollFrom: f32 = 0,
    thud: f32 = 0, // the body's ground-bounce after the fall lands (a decaying ring)
    /// THE GROUND SHOOK THIS FRAME — a one-frame magnitude (`justDied`'s rule), read by the group: the fall
    /// landing, the stomp's ring, the charge slamming to its stop. The pad and the lens answer it.
    quake: f32 = 0,
    /// The charge's COMMITTED length, fixed at the launch — where you STOOD plus the overrun.
    chargeLen: f32 = 0,
    heroHit: ?combat.Hit = null,
    homing: bool = false,
    strokeDone: f32 = 0, // ground already covered by a committed move's travel, so it integrates once

    /// THE HERO'S SHIELD CAUGHT A STROKE THIS FRAME — a ONE-FRAME flag (`justDied`'s), reset at the top of
    /// `update` and read by the group after.
    parried: bool = false,
    /// Was the door UP at the top of THIS frame. The BEARING is not in it: that belongs to the blow.
    covered: bool = false,
    /// HOW MANY BLOWS THE DOOR HAS EATEN. Not a `hits` — a block is not a body taking a blow — but it IS a
    /// blow that stopped here, which is the only way `foe.pierceGroup` can know a shaft was spent.
    blocks: u32 = 0,
    blockT: f32 = mathx.LONG_AGO,

    // posture channels (degrees), resolved by the state and read by pose()
    armSh: f32 = CARRY_SH,
    armEl: f32 = CARRY_EL,
    armAbd: f32 = CARRY_ABD,
    armSweep: f32 = 0,
    wpnTilt: f32 = CARRY_TILT,
    offSh: f32 = GUARD_SH,
    offEl: f32 = GUARD_EL,
    offAbd: f32 = GUARD_ABD,
    bodyLean: f32 = GUARD_LEAN,
    twist: f32 = GUARD_TWIST,
    headPitch: f32 = 3.0,
    headYaw: f32 = 0,
    legBrace: f32 = 0,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,
    prevPhase: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),
    /// The DECISION stream, its own so a dust-budget change cannot re-deal the fight.
    aiRng: mathx.Rng = mathx.Rng.init(2),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,
    /// The rig's ORIENTATION alone — yaw, topple and roll, with none of the spine in it. Stamped by `pose`
    /// and read by `shieldXf`, so the door can never be derived from a second copy of where his body is.
    bodyXf: rl.Matrix = undefined,
    shXf: rl.Matrix = undefined,
    /// Where the sword and the door were and are. The hurt tests run BETWEEN them: a stroke this size covers
    /// most of a metre in a frame, and an endpoint-only test passes clean through a body.
    wpnWas: [2]rl.Vector3 = .{ mathx.zero3, mathx.zero3 },
    wpnIs: ?[2]rl.Vector3 = null,
    shWas: [2]rl.Vector3 = .{ mathx.zero3, mathx.zero3 },
    shIs: ?[2]rl.Vector3 = null,
    /// Set by the stroke, spent AFTER `pose()`: the hurt shape IS the posed kit.
    live: bool = false,
    trail: foe.Trail(TRAIL_N) = .{},

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Knight {
        var k = Knight{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * SCALE, .seed = seed };
        k.rest = REST;
        k.fxRng = foe.fxStream(seed, 64871.0, 23);
        k.aiRng = foe.fxStream(seed, 39079.0, 29);
        for (&k.cds) |*c| c.* = 0.3 + seed * 0.8;
        // **THE SPRINGS ARE SEATED AT HIS GUARD, NOT AT ZERO.** A `SpringBank` comes up with every value at
        // 0, and 0 is a real pose — arms straight down — so a knight spawned and drawn before the bank had
        // time to settle stood there with the door hanging round his knees. It is the defaulted-field law
        // one layer along: the field's default runs, it is just not the default anyone wanted.
        k.springs.seat(k.chanGet());
        k.pose();
        return k;
    }

    fn move(self: *const Knight) Attack {
        return MOVES[@min(self.atk, MOVES.len - 1)];
    }

    // EVERY WORLD POINT ON HIM COMES OFF A POSED BONE, not off a height above his feet — see `CENTER_AT`.
    pub fn centerWorld(self: *const Knight) rl.Vector3 {
        return foe.markOn(self.xf[ROOT], CENTER_AT);
    }
    pub fn hurtRadius(self: *const Knight) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Knight) f32 {
        return BODY_R * self.scale;
    }
    pub fn lockPoint(self: *const Knight) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], LOCK_AT);
    }
    pub fn topWorld(self: *const Knight) rl.Vector3 {
        return foe.markOn(self.xf[SKULL], TOP_AT);
    }
    pub fn alive(self: *const Knight) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Knight) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Knight) bool {
        return switch (self.state) {
            .stunlight, .stunheavy, .downed, .rollover, .rise, .dead => true,
            else => false,
        };
    }
    pub fn flashFrac(self: *const Knight) f32 {
        return foe.flashFrac(self.flash);
    }
    /// He never leaves the ground: the topple is a ROTATION, and his feet are on the earth all through it.
    /// **HE LEAVES THE EARTH EXACTLY ONCE**, and only for the leap (the archer's `hop`, same threshold). It
    /// is what `game.zig` asks before it puts a terrain riser, a shoulder or a steering probe on him — all
    /// of which are rules for FEET, and none of which apply to a body in the air.
    pub fn airborne(self: *const Knight) bool {
        return self.air > foe.AIRBORNE_LIFT;
    }
    pub fn kind(self: *const Knight) wf.FoeKind {
        _ = self;
        return .bone_knight;
    }
    pub fn blocksTaken(self: *const Knight) u32 {
        return self.blocks;
    }
    /// IS THE DOOR BETWEEN YOU AND HIM THIS FRAME. The guard is held while he WALKS and through the moves
    /// thrown from behind it — the thrust goes past the door's edge and the bash IS the door — but **A
    /// COMMITTED SWORD STROKE TAKES IT OFF HIS FRONT**, which is the reference's own condition and the whole
    /// frontal read: "they're basically impossible to kill when attacking from the front IF THEY'RE NOT IN AN
    /// ATTACK ANIMATION" (GIANT_KNIGHTS.md). Held through every stroke instead, the front had no answer at
    /// all and reading a tell bought the player nothing but survival. The SLAM is still the other way in —
    /// the door leaves the fight entirely — and both openings are pictures before they are mechanics
    /// (`swipeOpen`, `slamLift`), because a front that is mechanically open must be seen to be open.
    pub fn guardUp(self: *const Knight) bool {
        if (self.gone) return false;
        return switch (self.state) {
            // …and the PIVOT STEP keeps it square: he is re-facing BEHIND the door, which is the point of it.
            .idle, .approach, .hop, .stepturn, .leapwind, .leap, .awaken, .sweepwind, .chainwind, .overwind, .thrustwind, .thrust, .swatwind, .swat, .chargewind, .charge, .brake, .fallwind => true,
            // THE BASH KEEPS THE GUARD — the door IS the blow — unless it is the SHOVE, which buys the
            // sword-side flank by taking the wall off his front to get there.
            .bashwind, .bash => self.shoveAcross() < 0.5,
            // THE SWIPES: the shield arm pays for the stroke, so the door turns off his front as it travels.
            .sweep, .sweep2, .over => self.swipeOpen() < 0.5,
            .slamwind => self.t < SLAM.windDur * 0.30, // the haul IS the front opening, visibly
            .recover => switch (self.blow) {
                .slam => false,
                // …and it does not snap back on the impact frame: the door is still off his front through the
                // head of the recovery, which is what makes the punish window a window and not a frame.
                .sweep, .sweep2, .over => self.swipeOpen() < 0.5,
                .bash => self.shoveAcross() < 0.5,
                else => true,
            },
            .slam, .fall, .downed, .rollover, .rise, .stunlight, .stunheavy, .dead => false,
        };
    }

    /// HOW FAR THE DOOR HAS SWUNG OFF HIS FRONT TO PAY FOR A SWIPE: 0 square across his chest, 1 hauled fully
    /// out and edge-on. `guardUp`'s other picture (`slamLift` is the slam's), and the two may never disagree
    /// — a test pins the pair. It opens EARLY in the stroke, because the door has to be gone before the blade
    /// arrives or the opening is one the player cannot use, and it closes over the head of the recovery.
    /// HOW FAR THE DOOR HAS TRAVELLED ACROSS ONTO HIS SWORD SIDE for the shove: 0 on guard, 1 fully across.
    /// `guardUp` reads it too — the flank he is covering is bought with the front, which is what stops the
    /// shove being a free answer to the one square he had no answer for.
    /// WHICH WAY THE DOOR IS BEING HAULED: −1 across his front onto the sword side, +1 out along the shield
    /// side. The magnitude is `shoveAcross`; this is only the sign, and every site that moves the wall reads
    /// it rather than assuming the sword side the way the first pass did.
    fn shoveDir(self: *const Knight) f32 {
        return if (self.shoveShield) 1.0 else -1.0;
    }
    fn shoveAcross(self: *const Knight) f32 {
        if (!self.shoving) return 0;
        return switch (self.state) {
            .bashwind => mathx.smoothstep(0.55, 1.0, self.t / self.windDur()) * 0.25,
            .bash => 0.25 + 0.75 * mathx.smoothstep(0, BASH.strikeDur * 0.40, self.t),
            .recover => if (self.blow == .bash)
                1.0 - mathx.smoothstep(self.recoverDur() * 0.35, self.recoverDur() * 0.92, self.t)
            else
                0,
            else => 0,
        };
    }

    fn swipeOpen(self: *const Knight) f32 {
        const swipe = switch (self.state) {
            .sweep, .sweep2, .over => true,
            .recover => switch (self.blow) {
                .sweep, .sweep2, .over => false,
                else => return 0,
            },
            else => return 0,
        };
        if (swipe) {
            const dur = self.move().strikeDur;
            return mathx.smoothstep(0, dur * SWIPE_OPEN_K, self.t);
        }
        const dur = self.recoverDur();
        return 1.0 - mathx.smoothstep(dur * SWIPE_SHUT_K0, dur * SWIPE_SHUT_K1, self.t);
    }
    /// HOW FAR OVER HE IS: 0 standing, 1 flat on his back, and NEGATIVE is forward — which is the only
    /// direction this creature ever dies in. ONE channel, so the picture, the mark, the bar and the crush
    /// strip cannot tell four different stories about where his body is.
    fn toppleAmt(self: *const Knight) f32 {
        return switch (self.state) {
            // A TOPPLE ACCELERATES. A symmetric ease reads as a controlled lie-down; `u^2` is the arc a mass
            // going over its own base actually takes, and it arrives a hair PAST flat.
            .fall => mathx.minF(1.0, mathx.clampF(self.t / FALL_DUR, 0, 1) * mathx.clampF(self.t / FALL_DUR, 0, 1) * 1.08),
            .downed, .rollover => 1.0,
            // **HE COMES UP OFF HIS FRONT, WHICH IS THE SIDE THE ROLL LEFT HIM ON** — so the topple comes off
            // the NEGATIVE side. `enter(.rise)` turned him about for it; see `turnAbout`.
            // Up in ONE heave off the shield, overshooting upright and settling back onto it (the reactions law).
            .rise => -(1.0 - mathx.smoothstep(RISE_DUR * 0.30, RISE_DUR * 0.84, self.t)) +
                RISE_OVERSHOOT * mathx.pulse(self.t / RISE_DUR, 0.74, 0.86, 0.90, 1.0),
            // **AND A BODY ALREADY ON THE GROUND DOES NOT GET UP TO FALL OVER.** Starting the crumple from
            // `deathFrom` is only half of it: a plain lerp to −1 from a body flat on its BACK passes through
            // ZERO on the way, and zero is STANDING — so a knight killed in his own punish window rose to his
            // feet and toppled forward, which is the exact frame `deathFrom` was added to stop. Past halfway
            // over he is already lying down, and lying down is where he stays.
            .dead => if (@abs(self.deathFrom) > 0.5)
                self.deathFrom
            else
                lerpF(self.deathFrom, -1.0, mathx.smoothstep(0, DEATH_DUR * 0.62, self.t)),
            else => 0,
        };
    }
    /// …AND HOW FAR ROUND HIS OWN LONG AXIS: 0 on his back, 1 face-down. Applied inside the rig's local
    /// frame, so standing it would be a spin on the spot and lying down it is a barrel roll — one rotation,
    /// two readings, and the topple above is what picks which.
    ///
    /// **THE RISE DOES NOT UNWIND IT** (owner: the rolling / getting up part is bad). It used to, and that is
    /// exactly what the move looked like: he heaved onto his front and then rolled straight back onto his
    /// back to stand up off it, so the roll bought nothing and read as a crate rocking twice. Lying on his
    /// back with his head behind his heels, a barrel roll leaves him face-DOWN with his head still behind
    /// them — which in his OWN frame is a body fallen FORWARD and turned about. `turnAbout` writes it as
    /// that, exactly, and the two descriptions are the same matrix, so nothing moves on the frame it swaps.
    fn rollAmt(self: *const Knight) f32 {
        return switch (self.state) {
            // Gathered, then over in one heave — a linear ramp is a body on a rotisserie.
            .rollover => mathx.smoothstep(ROLL_DUR * 0.12, ROLL_DUR * 0.92, self.t),
            // …and killed MID-HEAVE the barrel stays where it got to, `deathFrom`'s reason on the other
            // channel: unwound to square, a body caught half on its side snapped flat on the death frame.
            .dead => self.rollFrom,
            else => 0,
        };
    }
    /// HOW FAR THE DOOR HAS LEFT HIS FRONT FOR THE SLAM: 0 on guard, 1 hauled fully up. THE PICTURE OF
    /// `guardUp`, and it may never disagree with it — a front that is mechanically open must be seen to be
    /// open. (The door's position already follows the shield FIST, so most of the travel is the arm's; this
    /// channel drives the door's own PITCH — face skyward at the top, face into the earth at the bottom.)
    fn slamLift(self: *const Knight) f32 {
        return switch (self.state) {
            .slamwind => mathx.smoothstep(SLAM.windDur * 0.10, SLAM.windDur * 0.70, self.t),
            .slam => 1.0,
            .recover => if (self.blow == .slam)
                1.0 - mathx.smoothstep(self.recoverDur() * 0.30, self.recoverDur() * 0.85, self.t)
            else
                0,
            else => 0,
        };
    }
    /// HOW FAR INTO THE DRIVE the door is — 0 still overhead, 1 buried. Shared by the pitch and the carry,
    /// because they are two halves of one arc and two clocks would let the face point somewhere the door
    /// is not.
    fn slamDrive(self: *const Knight) f32 {
        return switch (self.state) {
            .slam => mathx.clampF(self.t / (SLAM.strikeDur * SLAM.impactK), 0, 1),
            .recover => if (self.blow == .slam) 1.0 - mathx.smoothstep(0, self.recoverDur() * 0.5, self.t) else 0,
            else => 0,
        };
    }
    /// …and the door's pitch off that channel plus the strike's own drive.
    fn slamPitch(self: *const Knight) f32 {
        const up = SLM_PITCH_UP * self.slamLift();
        return up + (SLM_PITCH_DOWN - SLM_PITCH_UP) * self.slamDrive() * self.slamLift();
    }
    /// **WHERE THE DOOR ITSELF TRAVELS THROUGH THE SLAM**, in his own body frame and on top of whatever the
    /// arm is doing (owner: the slam is busted looking and cuts through his model).
    ///
    /// The move used to be a PITCH AND NOTHING ELSE: the hub kept riding the fist while the face rotated,
    /// and since the door is gripped like a pavise — the hand ~80 % of the way up its own height — pitching
    /// it about that grip swung four fifths of four and a half metres of plank straight through the man
    /// carrying it. The haul laid it flat THROUGH his chest and out of his back; the drive buried it inside
    /// him and it vanished from the frame entirely at the impact. A shield slam is the door being CARRIED —
    /// up clear of his crown, then down into the earth ahead of his boots — and the arm alone cannot do
    /// that, because the fist moves about a metre and the door is four.
    fn slamCarry(self: *const Knight) rl.Vector3 {
        const lift = self.slamLift();
        if (lift <= 0) return mathx.zero3;
        const drive = self.slamDrive();
        const up = SLM_CARRY_UP * (1.0 - drive) + SLM_CARRY_END_Y * drive;
        const fwd = SLM_CARRY_FWD * drive;
        return v3(0, up * lift, fwd * lift);
    }

    /// How long THIS recovery runs — the move rows carry their own; the slam and charge are not rows.
    fn recoverDur(self: *const Knight) f32 {
        return switch (self.blow) {
            .sweep, .sweep2, .over, .thrust, .bash, .swat => MOVES[@min(self.atk, MOVES.len - 1)].recoverDur,
            .slam => SLAM.recoverDur,
            .charge => CHARGE.recoverDur,
            .fall => RISE_DUR, // unreachable in practice: the fall recovers through its own three states
        };
    }

    /// HOW FIRMLY BOTH FEET ARE DOWN: 0 free to stride, 1 planted for a stroke. Ramped over the wind rather
    /// than switched, because a stride that stops on one frame is the thing it was added to stop. The CHARGE
    /// and the APPROACH are travel and keep their gait; everything else he commits to, he commits to standing.
    fn planted(self: *const Knight) f32 {
        return switch (self.state) {
            .sweepwind, .chainwind, .overwind, .thrustwind, .bashwind, .slamwind, .fallwind => mathx.smoothstep(0, PLANT_IN, self.t),
            .sweep, .sweep2, .over, .thrust, .bash, .slam => 1.0,
            .recover => 1.0 - mathx.smoothstep(self.recoverDur() * 0.55, self.recoverDur(), self.t),
            else => 0,
        };
    }
    /// IS A COMBO ALREADY RUNNING — one link in or more. What hyper-armour is granted off, and deliberately
    /// NOT true of the opener: the first swing of a string is interruptible like anything else, so reading
    /// a tell and punishing it still works. What it refuses is being mashed out of a string mid-way.
    fn inString(self: *const Knight) bool {
        return self.strung > 0;
    }
    /// Is he off his feet at all — the one predicate the legs, the gait and the FX all branch on.
    fn floored(self: *const Knight) bool {
        return switch (self.state) {
            .fall, .downed, .rollover, .rise => true,
            else => false,
        };
    }

    fn fdir(self: *const Knight) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Knight, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }
    /// The hero's bearing off his facing, in degrees (0 dead ahead, +-180 behind).
    fn bearingTo(self: *const Knight, hero: rl.Vector3) f32 {
        const d = mathx.dirXZ(self.pos, hero);
        if (mathx.lenXZ(d) < 1e-3) return 0;
        return mathx.degrees(mathx.wrapPi(mathx.headingXZ(d) - self.facing));
    }

    /// WHERE HE IS TRYING TO WALK, or null when he is not walking anywhere (`game.markWay`). The APPROACH
    /// only: he walks where he is LOOKING and he never strafes, so a bent heading under a committed stroke
    /// would aim the blow at the wall.
    pub fn navWant(self: *const Knight, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .approach) return null;
        return if (self.homing) self.home else hero;
    }

    pub fn update(self: *Knight, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        self.parried = false;
        self.live = false;
        self.quake = 0;
        self.gasAt = null;
        // THE ROOTS HAVE THE FEET AND NOTHING ELSE. Held unconditionally: he cannot leave the ground.
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.blockT += dt;
        for (&self.cds) |*c| c.* = mathx.maxF(0, c.* - dt);
        self.fallCd = mathx.maxF(0, self.fallCd - dt);
        self.slamCd = mathx.maxF(0, self.slamCd - dt);
        self.chargeCd = mathx.maxF(0, self.chargeCd - dt);
        self.hopCd = mathx.maxF(0, self.hopCd - dt);
        self.stepCd = mathx.maxF(0, self.stepCd - dt);
        self.leapCd = mathx.maxF(0, self.leapCd - dt);
        self.counterCd = mathx.maxF(0, self.counterCd - dt);
        self.riposteCd = mathx.maxF(0, self.riposteCd - dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        self.thud = mathx.maxF(0, self.thud - dt * 2.8);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        self.trail.age(dt);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const a = self.move();
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        const bearing = self.bearingTo(hero);
        const faceWas = self.facing; // …so a PIVOT can be given to the legs; see below
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        // THE CHARGE'S FUSE: it fills while the fight is on and you are keeping out of his reach, and it
        // drains twice as fast when you close — banked patience is not a thing you carry into his arms.
        const fighting = self.leash.roused() or d <= AGGRO_R;
        if (fighting and d > CHARGE.far and !self.leash.goingHome()) {
            self.farT += dt;
        } else {
            self.farT = mathx.maxF(0, self.farT - dt * 2.0);
        }

        // HOW THE FIGHT IS GOING, measured off the world like everything else: how fast his bearing is
        // walking round the facing, and what this patch of ground has cost him. Never the stick, never a
        // button. `settled` is false through the moves that carry HIM, or his own travel reads as an orbit.
        self.sense.tick(dt, self.pos, mathx.radians(bearing), self.bodyR(), switch (self.state) {
            .hop, .leapwind, .leap, .chargewind, .charge, .brake => false,
            else => true,
        });

        // THE SHIELD, asked BEFORE the state machine runs this frame's stroke — a catch has to kill the blow
        // it caught, and by the time the hurt test has run the blow is already dealt.
        self.takeParry();
        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.setCarry(dt);
                if (self.t >= 0.18) self.decide(d, bearing);
            },
            .approach => {
                const tgt = if (self.homing) self.home else hero;
                self.faceToward(self.nav.aim(self.pos, tgt), dt);
                const f = self.fdir();
                moveSpeed = WALK_SPEED;
                const moved = moveSpeed * dt;
                mathx.stepXZ(&self.pos, f, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(f);
                self.setCarry(dt);
                if (self.homing) {
                    if (d <= AGGRO_R) {
                        self.homing = false;
                        self.decide(d, bearing);
                    } else if (mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) self.enterIdle();
                } else if (d <= self.longestTrigger() or d > AGGRO_R or self.wantsFall(d, bearing) or self.chargeReady()) {
                    self.decide(d, bearing);
                }
            },
            // ONE DISCRETE WEIGHT SHIFT SIDEWAYS — the Sentinel's "surprisingly quick to respond, often
            // jumping out of the way". The hop is the one window his slow turn opens wide (`HOP.turnMul`),
            // because the hop IS the re-face; between hops he is as out-turned as ever, so the flank the
            // whole creature is built round still exists.
            .hop => {
                foe.faceToward(self.pos, &self.facing, hero, TURN_RATE * HOP.turnMul, dt);
                self.setHop(self.t);
                const t0 = HOP.windDur;
                const t1 = HOP.windDur + HOP.airDur;
                if (self.t >= t0 and self.t <= t1) {
                    const u = mathx.clampF((self.t - t0) / HOP.airDur, 0, 1);
                    const want = HOP.dist * self.scale * mathx.smoothstep(0, 1, u);
                    const f = self.fdir();
                    mathx.stepXZ(&self.pos, v3(f.z * self.hopSide, 0, -f.x * self.hopSide), want - self.strokeDone, bounds);
                    self.strokeDone = want;
                }
                if (!self.dealt and self.t >= t1) {
                    self.dealt = true; // the landing, once
                    self.plantBurst();
                    sfx.world(.step_hard, self.pos);
                }
                if (self.t >= t1 + HOP.settleDur) self.enterIdle();
            },
            // **THE PIVOT STEP.** The wind loads onto the plant foot, the drive swings his whole mass round
            // in one beat, and the settle is a mass arriving rather than easing. He aims at the hero the
            // whole way, but the RATE is the step's, not his own — this is the one thing on him that turns
            // fast, and it is a committed action with a plant, a cooldown and no blow on the end of it.
            // **THE AWAKENING.** He plants, hauls the blade over the helm and HOLDS it while chaos gathers
            // onto the steel. Nothing tracks, nothing lands, nothing can interrupt it — it is a full stop
            // and the largest free window in the fight, which is what the player is paid for getting here.
            .awaken => {
                self.setAwaken(self.t);
                self.emitAwaken(dt);
                if (self.t >= AWAKEN.liftDur + AWAKEN.holdDur + AWAKEN.settleDur) {
                    self.lit = true; // …and from here every blow he lands opens a burst of it
                    self.quake = mathx.maxF(self.quake, QUAKE_CRATER);
                    sfx.world(.ogre_roar, self.pos);
                    self.chaosBurst(self.centerWorld(), 30);
                    self.decide(d, bearing);
                }
            },
            // THE COIL. He sinks, the door comes in tight, and everything loads DOWN — the one silhouette
            // that reads as a body about to leave the ground.
            .leapwind => {
                foe.faceToward(self.pos, &self.facing, hero, TURN_RATE, dt);
                self.setLeap(self.t);
                if (self.t >= self.leapWind()) {
                    // THE LINE IS AWAY FROM HIM, committed at the launch (the charge's own law): what he is
                    // buying is GROUND, and a flight that steered would be a chase.
                    self.leapDir = mathx.dirXZ(hero, self.pos);
                    if (mathx.lenXZ(self.leapDir) < 1e-4) self.leapDir = mathx.scaleV(self.fdir(), -1);
                    self.enter(.leap);
                }
            },
            .leap => {
                // …but the TURN is free across it, because where he is POINTING when he lands is the move.
                foe.faceToward(self.pos, &self.facing, hero, TURN_RATE * LEAP.turnMul, dt);
                self.setLeap(self.leapWind() + self.t);
                const u = mathx.clampF(self.t / LEAP.flightDur, 0, 1);
                const want = LEAP.dist * self.scale * mathx.smoothstep(0, 1, u);
                mathx.stepXZ(&self.pos, self.leapDir, want - self.strokeDone, bounds);
                self.strokeDone = want;
                self.air = LEAP.rise * self.scale * mathx.sinf(u * std.math.pi);
                if (!self.dealt and self.t >= LEAP.flightDur) {
                    self.dealt = true; // the landing, once
                    self.air = 0;
                    self.plantBurst();
                    self.dustBurst(self.pos, 14, 2.6, 0.26);
                    self.quake = mathx.maxF(self.quake, QUAKE_BRAKE);
                    sfx.world(.step_hard, self.pos);
                }
                if (self.t >= LEAP.flightDur) self.air = 0;
                if (self.t >= LEAP.flightDur + LEAP.landDur) self.decide(d, bearing);
            },
            .stepturn => {
                const t0 = STEPTURN.windDur;
                const t1 = t0 + STEPTURN.turnDur;
                if (self.t >= t0 and self.t <= t1) {
                    const rate = mathx.radians(STEPTURN.sweep) / STEPTURN.turnDur;
                    foe.faceToward(self.pos, &self.facing, hero, rate, dt);
                }
                self.setStepTurn(self.t);
                if (!self.dealt and self.t >= t1) {
                    self.dealt = true; // the foot arriving, once
                    self.plantBurst();
                    self.quake = mathx.maxF(self.quake, QUAKE_STEP * 2.2);
                    sfx.world(.step_hard, self.pos);
                }
                // …AND A PIVOT MAY BE CHAINED INTO A BLOW (`stepThen`). This is what a flank counter is now:
                // he turns onto you with a real step you can watch, and the answer comes off the end of it.
                if (self.t >= t1 + STEPTURN.settleDur) {
                    if (self.stepThen) |mv| {
                        self.stepThen = null;
                        self.atk = mv;
                        self.opener = mv;
                        self.strung = 0;
                        self.enter(windFor(mv));
                    } else self.decide(d, bearing);
                }
            },
            .sweepwind, .chainwind, .overwind, .thrustwind, .bashwind, .swatwind => {
                // THE SWEEP'S GATHER IS ITS AIM (`FLANK_BEARING`): it is the one stroke chosen from off his
                // front, so its wind gets his full turn to square up in — a whole second of him planting and
                // coming round, which is the tell. Everything else is aimed down a front he is already on,
                // so its wind only trims.
                const windTurn: f32 = if (self.state == .sweepwind) 1.0 else 0.45;
                self.faceToward(hero, dt * windTurn);
                const dur = self.windDur();
                // ACROSS THE WHOLE GATHER, not smoothstepped into 90 % of it: the track owns its own shape
                // now, including the settle-back at the top and the overhead's `.hold` bait, and an outer
                // easing curve laid over a keyed one is two animators fighting.
                self.setWindKeys(self.t / dur);
                // THE GATHER'S FIRE IS THE MOVE'S OWN DECLARED WEIGHT, read off the row rather than
                // re-guessed here — so a move can never be tuned harder without its tell following it.
                const w = a.weight;
                const load: f32 = if (w == .light) GATHER_PLAIN else GATHER_HEAVY;
                self.emitGather(dt, mathx.clampF(self.t / dur, 0, 1) * load, w);
                if (self.t >= dur) self.enter(switch (self.state) {
                    .sweepwind => .sweep,
                    .chainwind => .sweep2,
                    .overwind => .over,
                    .thrustwind => .thrust,
                    .swatwind => .swat,
                    else => .bash,
                });
            },
            .sweep, .sweep2, .over, .thrust, .bash, .swat => {
                // THE OVERHEAD HAS "VERY POOR TRACKING" BY DESIGN — the line is committed at the drop, so
                // stepping off it is the whole answer. Everything else keeps the ordinary strike tracking.
                const turn: f32 = if (self.state == .over) 0.0 else SWING_TURN;
                foe.faceToward(self.pos, &self.facing, hero, turn, dt);
                const k = mathx.clampF(self.t / a.strikeDur, 0, 1);
                self.setStrike(foe.swingCurve(k));
                self.driveBash(k, bounds);
                self.driveThrust(k, bounds);
                // **THE STROKE ITSELF IS FELT** (owner: needs more shake/particle impact). Only the fall,
                // the crater and the skid ever moved the lens, so the four moves that actually arrive on
                // him did so in silence. Fired ONCE at the impact frame off `dealt`'s own latch rule, and
                // sized by what lands: the overhead ends in the EARTH, so it is a landing and not a swing.
                if (!self.strikeFelt and self.t >= a.strikeDur * a.impactK) {
                    self.strikeFelt = true;
                    self.quake = @max(self.quake, switch (self.state) {
                        .over => QUAKE_OVER,
                        .bash => QUAKE_BASH,
                        else => QUAKE_SWEEP,
                    });
                    // …and the ground answers where the kit went, not where he is standing.
                    const seg = if (self.state == .bash) self.shieldHere() else self.wpnHere();
                    if (self.state == .over) {
                        self.dustBurst(seg[1], 20, 3.4, 0.34);
                        self.grit(seg[1], 12);
                        sfx.world(.ogre_slam, seg[1]);
                    } else {
                        self.dustBurst(v3(seg[1].x, self.pos.y, seg[1].z), 9, 2.2, 0.20);
                    }
                    // **AND ONCE HE IS LIT THE HEAVY ONES FOUL THE GROUND THEY HIT.** Laid here rather than
                    // in `tryReach` on purpose: a stroke that MISSED still leaves its cloud, which is what
                    // makes this a spacing move and not a second damage number bolted onto a hit.
                    if (self.lit and a.weight != .light) {
                        self.gasAt = v3(seg[1].x, self.pos.y, seg[1].z);
                    }
                }
                if (self.t >= a.strikeDur * a.impactK) self.live = true;
                if (self.t >= a.strikeDur) {
                    // THE STRING IS ROLLED AT THE EXIT, and only at a man still in front of him: a backhand
                    // at empty air announces the punish was free after all. This is also where the roll-catch
                    // lives (the reference, both games) — the second sweep's delayed re-cock is a link like
                    // any other, so what catches an early roll is the string's own variable length.
                    self.strungUsed[self.cdSlot()] = true;
                    const chase = @abs(self.bearingTo(hero));
                    // **THE SWIPE-AND-LEAP** (owner: when you're on his side it should be a bit faster and
                    // more evil). The flick already reaches your flank; this is what it BUYS him. Taken
                    // straight off the strike with NO recovery in between — the two moves are one beat — so
                    // what the player gets is a swat at his legs and then five metres of armour already in
                    // the air, landing squared up before the flinch is over. It is only ever thrown from a
                    // flank, because from the front it would just be him running away.
                    if (self.atk == SWAT_I and chase > SWEEP_BEARING and self.leapCd <= 0 and foe.canLeap(&self.root)) {
                        self.billString();
                        self.leapCd = LEAP.cd * self.aiRng.range(0.85, 1.25);
                        self.leapChained = true; // …and it comes out on a shortened coil: this is the fast one
                        self.enter(.leapwind);
                    } else {
                        // **THE ROUTE IS WALKED, NOT ROLLED.** He commits to the whole string he opened
                        // with — that is what makes it learnable and what makes its END a punish window you
                        // can plan for. The only things that cut it short are the player LEAVING: out of the
                        // next link's reach, or round past where its arc can go. Neither is luck; both are
                        // your feet.
                        const nxt: ?usize = blk: {
                            const route = routeFor(self.opener);
                            if (self.strung >= route.len) break :blk null;
                            const n = route[self.strung];
                            if (chase >= SWEEP_BEARING + 15.0) break :blk null;
                            if (d > triggerR(MOVES[n], self.scale) * 1.25) break :blk null;
                            break :blk n;
                        };
                        if (nxt) |n| {
                            self.strung += 1;
                            self.atk = n;
                            self.enter(windFor(n));
                        } else {
                            self.billString();
                            self.enter(.recover);
                        }
                    }
                }
            },
            // THE DOOR ITSELF, HAULED UP AND DRIVEN INTO THE EARTH — "long build up time, mega damage and a
            // small AoE", and the one time the wall leaves his front: `guardUp` opens over the haul, which
            // is the longest look at his chest the fight ever offers.
            .slamwind => {
                self.faceToward(hero, dt * 0.40);
                self.setSlamWind(mathx.smoothstep(0, SLAM.windDur * 0.9, self.t));
                self.emitGather(dt, mathx.clampF(self.t / SLAM.windDur, 0, 1) * GATHER_HEAVY, .crushing);
                self.slamRingTell(dt);
                if (self.t >= SLAM.windDur) self.enter(.slam);
            },
            .slam => {
                const k = mathx.clampF(self.t / SLAM.strikeDur, 0, 1);
                self.setSlam(foe.swingCurve(k));
                if (!self.dealt and self.t >= SLAM.strikeDur * SLAM.impactK) {
                    self.dealt = true;
                    self.trySlam(hero);
                    self.slamCrater();
                    self.thud = 0.70;
                    self.quake = QUAKE_CRATER;
                    // …and lit, the crater FUMES. Off `slamMark` like the blow, the dust and the tests, so
                    // the cloud stands exactly where the disc was rather than near it.
                    if (self.lit) self.gasAt = self.slamMark();
                }
                if (self.t >= SLAM.strikeDur) {
                    self.slamCd = SLAM.cd * self.aiRng.range(0.85, 1.4);
                    self.enter(.recover);
                }
            },
            .chargewind => {
                // The one wind allowed to really AIM (1.4x his own turn): what you dodge is the TRAVEL,
                // and a charge that cannot point at you is a move that never lands at all.
                foe.faceToward(self.pos, &self.facing, hero, TURN_RATE * 1.4, dt);
                self.setChargeWind(mathx.clampF(self.t / CHARGE.windDur, 0, 1));
                self.emitGather(dt, mathx.clampF(self.t / CHARGE.windDur, 0, 1) * GATHER_HEAVY, .crushing);
                if (self.t >= CHARGE.windDur) {
                    // THE LINE IS COMMITTED HERE: where you stand, plus the overrun a wall cannot help.
                    self.chargeLen = mathx.minF(mathx.distXZ(self.pos, hero) + CHARGE.overrun, CHARGE.range);
                    self.enter(.charge);
                }
            },
            .charge => {
                // NO STEERING AT ALL — the delver's plough: the counter is the line, so the line holds.
                self.setCharge(self.t);
                const f = self.fdir();
                const want = mathx.minF(chargeDist(self.t), self.chargeLen);
                const step = want - self.strokeDone;
                mathx.stepXZ(&self.pos, f, step, bounds);
                self.strokeDone = want;
                movedDist = step;
                moveYaw = mathx.headingXZ(f);
                moveSpeed = CHARGE.speed;
                self.chargeWake(dt);
                if (self.t >= 0.08) self.live = true; // a breath of grace off the line, then the wall is on
                if (want >= self.chargeLen) self.enter(.brake);
            },
            .brake => {
                self.setBrake(mathx.clampF(self.t / CHARGE.brakeDur, 0, 1));
                // The skid: what is left of the speed, integrated out to nothing over the brake.
                const f = self.fdir();
                const want = brakeDist(self.t);
                const step = want - self.strokeDone;
                mathx.stepXZ(&self.pos, f, step, bounds);
                self.strokeDone = want;
                movedDist = step;
                moveYaw = mathx.headingXZ(f);
                moveSpeed = CHARGE.speed * (1.0 - mathx.clampF(self.t / CHARGE.brakeDur, 0, 1));
                if (self.t >= CHARGE.brakeDur) {
                    self.chargeCd = CHARGE.cd * self.aiRng.range(0.85, 1.35);
                    self.enter(.recover);
                }
            },
            .recover => {
                const dur = self.recoverDur();
                self.setRecover(mathx.clampF(self.t / dur, 0, 1));
                if (self.t >= dur) self.decide(d, bearing);
            },
            // HE PUTS HIS BACK TO YOU. Nothing else in the game steers AWAY from the hero, and that is the
            // whole tell: the moment he stops tracking and starts presenting his spine, the strip is loading.
            .fallwind => {
                foe.faceToward(self.pos, &self.facing, self.awayFrom(hero), FALL_AIM, dt);
                self.setFallWind(mathx.clampF(self.t / FALL_WIND_DUR, 0, 1));
                self.emitGather(dt, mathx.clampF(self.t / FALL_WIND_DUR, 0, 1) * GATHER_FALL, .crushing);
                if (self.t >= FALL_WIND_DUR) self.enter(.fall);
            },
            .fall => {
                self.setFalling(mathx.clampF(self.t / FALL_DUR, 0, 1));
                // **THE BODY LANDS ON YOU ONCE** (owner: the fall + AoE hit at once). `dealt` latched the
                // thud, the shake and the dust — and NOT the blow, so `tryCrush` re-armed `heroHit` every
                // frame from the impact to the end of the fall. At sixty frames a second that is the strip
                // billing FALL_HIT a dozen-plus times in a third of a second, which is what actually made
                // the move a one-shot: no damage number was ever going to fix it, and lowering it just made
                // the multi-hit cheaper. One landing, one blow, on the frame the body arrives.
                if (!self.dealt and self.t >= FALL_DUR * FALL_IMPACT_K) {
                    self.dealt = true;
                    self.tryCrush(hero, FALL_HIT);
                    self.thud = 1.0;
                    self.quake = QUAKE_FALL;
                    self.slamGround();
                }
                if (self.t >= FALL_DUR) self.enter(.downed);
            },
            .downed => {
                self.easeFloored(dt);
                if (self.t >= DOWN_DUR) self.enter(.rollover);
            },
            .rollover => {
                self.setRollover(mathx.clampF(self.t / ROLL_DUR, 0, 1));
                self.driveRoll(bounds);
                if (self.t >= ROLL_DUR) self.enter(.rise);
            },
            .rise => {
                self.setRise(mathx.clampF(self.t / RISE_DUR, 0, 1));
                if (self.t >= RISE_DUR) {
                    self.fallCd = FALL_CD * self.aiRng.range(0.8, 1.4);
                    self.enterIdle();
                }
            },
            .stunlight => {
                self.easeNeutral(dt);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enterIdle();
            },
            .stunheavy => {
                self.easeNeutral(dt);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enterIdle();
            },
            .dead => {
                self.easeNeutral(dt);
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            },
        }

        // THE BODY CHASES WHATEVER THE STATE MACHINE JUST ASKED FOR — once, here, so no move can forget.
        self.settlePose(dt);

        // Settled BEFORE the blade, so a hit this frame is judged against the guard he actually held.
        self.covered = self.guardUp();

        // **A PIVOT IS A SEQUENCE OF SIDESTEPS, AND HIS FEET HAVE TO TAKE THEM** (owner: he turns in place
        // without leg movement like a weirdo). `legChain` is driven by GROUND COVERED, and turning on the
        // spot covers none — so the whole body yawed as one welded piece with two boots painted on the
        // floor, which on the slowest-turning creature in the game is most of what you watch him do. The
        // feet DO travel through a pivot: each sweeps an arc about the body's axis, so that arc is handed
        // to the gait as lateral distance and the rig's own crossing sidestep answers it. `planted` still
        // holds them down through a committed stroke, which is where a shuffle would be wrong.
        if (moveYaw == null) {
            const dyaw = mathx.wrapPi(self.facing - faceWas);
            const arc = @abs(dyaw) * TURN_STANCE_HALF * H * self.scale;
            if (arc > 1e-5) {
                movedDist += arc;
                moveSpeed = mathx.maxF(moveSpeed, arc / mathx.maxF(dt, 1e-4));
                const f = self.fdir();
                const sign: f32 = if (dyaw > 0) 1.0 else -1.0;
                moveYaw = mathx.headingXZ(v3(f.z * sign, 0, -f.x * sign));
            }
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.footfalls();
        self.pose();
        // THE BLOW IS JUDGED AFTER THE POSE, because the hurt shape IS the posed kit.
        if (self.live) self.tryReach(hero);
        switch (self.state) {
            .sweep, .sweep2, .over, .thrust => {
                const seg = self.wpnHere();
                self.trail.push(seg[0], seg[1], self.wpnWas[1], TRAIL_ROOT);
            },
            else => {},
        }
        self.tryHit(blade); // the hero's blade LAST, so a kill flags justDied for this frame's beat
        return self.heroHit;
    }

    /// GROUND COVERED t SECONDS INTO THE CHARGE — the closed form (the jump's integrator law): a linear
    /// spin-up over `accel`, then flat out. Added per frame it under-travels by half an accel every launch.
    fn chargeDist(t: f32) f32 {
        const ta = mathx.minF(t, CHARGE.accel);
        const ramp = CHARGE.speed * ta * ta / (2.0 * CHARGE.accel);
        return ramp + CHARGE.speed * mathx.maxF(0, t - CHARGE.accel);
    }
    /// …and the SKID's, from full tilt to nothing over the brake.
    fn brakeDist(t: f32) f32 {
        const tb = mathx.minF(t, CHARGE.brakeDur);
        return CHARGE.speed * (tb - tb * tb / (2.0 * CHARGE.brakeDur));
    }

    /// The point on the far side of him from the hero — what the fall steers at.
    fn awayFrom(self: *const Knight, hero: rl.Vector3) rl.Vector3 {
        const back = mathx.dirXZ(hero, self.pos);
        return v3(self.pos.x + back.x, self.pos.y, self.pos.z + back.z);
    }

    fn windDur(self: *const Knight) f32 {
        // THE HANG BELONGS TO THE OVERHEAD **AND THE SWAT** (owner: tricky through timing, not speed). Both
        // are moves whose whole difficulty is WHEN, so both bait; the difference is scale — the overhead
        // hangs for most of a second, the flick for a beat.
        const held = switch (self.state) {
            .overwind, .swatwind => self.windHold,
            else => 0,
        };
        // …AND THE DOOR COMES QUICKER ON THE SHIELD SIDE (owner: a quick shield bash on his shield side —
        // still too easy to hug it). The haul is SHORTER over there because the wall starts there: it has
        // no body to cross, which is the honest reason a flank answer can be fast without being a lie.
        const base = if (self.shoving and self.shoveShield and (self.state == .bashwind))
            self.move().windDur * SHOVE_SHIELD_WIND + held
        else
            self.move().windDur + held;
        // MID-STRING THE GATHER IS SHORT — the reference's own shape, where the recovery collapses inside a
        // combo and the whole debt arrives at the finisher. Floored at `foe.TELL_MIN` so a link is still a
        // telegraph: no attack in this game comes out of nowhere, strings included.
        if (self.strung == 0) return base;
        return mathx.maxF(base * STRING_WIND_MUL, foe.TELL_MIN);
    }
    /// WHICH CLOCK A MOVE BILLS. The second sweep has none of its own — it is the same move thrown twice, so
    /// it rides the sweep's, which is what stops a double costing the same rest as a single.
    fn cdSlot(self: *const Knight) usize {
        return if (self.atk == SWEEP2_I) SWEEP_I else self.atk;
    }
    /// THE DEBT, PAID ONCE, AT THE END OF THE STRING. Every move the string spent goes on its clock together
    /// and dearer the longer it ran (`STRING_CD_PER_LINK`) — with the jitter every cooldown in this file
    /// carries (the ogre's law: a boss whose moves beat in phase is one you read once and never again).
    fn billString(self: *Knight) void {
        const dearer = 1.0 + STRING_CD_PER_LINK * @as(f32, @floatFromInt(self.strung));
        for (&self.strungUsed, 0..) |*u, i| {
            if (!u.*) continue;
            u.* = false;
            self.cds[i] = MOVES[i].cd * dearer * self.aiRng.range(0.82, 1.45);
        }
        self.strung = 0;
    }
    fn longestTrigger(self: *const Knight) f32 {
        var r: f32 = thrustBandR(self.scale);
        for (MOVES[0..CHOOSE_N]) |a| r = mathx.maxF(r, triggerR(a, self.scale));
        return r;
    }
    fn wantsFall(self: *const Knight, dist: f32, bearingDeg: f32) bool {
        return self.fallCd <= 0 and @abs(bearingDeg) >= 180.0 - FALL_SECTOR and dist <= crushLen(self.scale);
    }
    /// THE FUSE HAS BURNT AND THE MOVE IS THERE TO SPEND. `foe.canLeap` gates it like every committed travel
    /// (the kobold's dash, the archer's backstep): denied only its distance, a rooted charge is a wall
    /// running on the spot inside a fist of roots.
    fn chargeReady(self: *const Knight) bool {
        return self.farT >= CHARGE.patience and self.chargeCd <= 0 and foe.canLeap(&self.root);
    }

    /// The bash's shove forward. INTEGRATED off a curve rather than added per frame, so the ground covered is
    /// exact however the frame rate wobbles (the archer's backstep's law).
    fn driveBash(self: *Knight, k: f32, bounds: f32) void {
        if (self.state != .bash) return;
        const e = 1.0 - (1.0 - k) * (1.0 - k);
        const want = BASH_STEP * self.scale * e;
        mathx.stepXZ(&self.pos, self.fdir(), want - self.strokeDone, bounds);
        self.strokeDone = want;
    }
    /// …and the thrust's LUNGE, same law: the body goes with the point, or five metres of reach come out of
    /// a stationary shoulder and read as a pool cue.
    fn driveThrust(self: *Knight, k: f32, bounds: f32) void {
        if (self.state != .thrust) return;
        const e = 1.0 - (1.0 - k) * (1.0 - k);
        const want = THRUST_STEP * self.scale * e;
        mathx.stepXZ(&self.pos, self.fdir(), want - self.strokeDone, bounds);
        self.strokeDone = want;
    }

    /// …AND THE GROUND THE ROLL CROSSES GOES THROUGH `pos` TOO, for the same reason and one more: as an
    /// offset inside the pose it was a body DRAWN a metre from where its hurt sphere and its collider stood,
    /// and it had to snap back to nothing the instant `turnAbout` cleared the roll. Integrated off the roll's
    /// own curve there is nothing to snap and the body is where it looks.
    fn driveRoll(self: *Knight, bounds: f32) void {
        if (self.state != .rollover) return;
        const f = self.fdir();
        const want = ROLL_SHIFT * self.scale * self.rollAmt();
        mathx.stepXZ(&self.pos, v3(f.z, 0, -f.x), want - self.strokeDone, bounds);
        self.strokeDone = want;
    }

    /// **THE TWELVE POSTURE CHANNELS ARE THE WHOLE OF HIS ANIMATION, AND THEY ARE NOW TARGETS.**
    ///
    /// They used to be written two incompatible ways — `setCarry`/`easeNeutral`/`easeFloored` APPROACH
    /// their targets, every attack wrote them ABSOLUTELY off its own `k` — so a stroke's first frame wrote
    /// `lerpF(CARRY_SH, …, 0)` = `CARRY_SH` outright however far from carry the body actually was, and any
    /// interrupt teleported the whole upper body on one frame. Worse, an attack was only ever TWO poses with
    /// a curve between them, which is a shape with nowhere to put a gather, a hang, a snap or a recoil.
    ///
    /// Both are the same fix, and it is Overgrowth's (Rosen, GDC 2014): the pose is a TARGET and the body
    /// CHASES it. `anim.Spring` makes every transition continuous by construction — a spring's output moves
    /// by velocity, so it cannot jump however far its target does, which retires the hand-rolled cross-fade
    /// this used to need — and the bank lags each channel by its index, so the mass flows outward on its own.
    const CHAN_N = 12;

    /// **ROOT-MOST TO TIP-MOST, AND THE ORDER IS LOAD-BEARING**: `anim.SpringBank` lags a channel by its
    /// INDEX, so this list IS the path the motion travels down. Feet, then waist, then trunk, then head,
    /// then shoulders, then the elbows, and the BLADE last — it trails everything, which is what
    /// `setStrike`'s hand-rolled sqrt/linear/squared triple was approximating one creature at a time.
    const CH_BRACE = 0;
    const CH_LEAN = 1;
    const CH_TWIST = 2;
    const CH_HEAD = 3;
    const CH_ARM_SH = 4;
    const CH_OFF_SH = 5;
    const CH_ARM_ABD = 6;
    const CH_OFF_ABD = 7;
    const CH_ARM_SWEEP = 8;
    const CH_ARM_EL = 9;
    const CH_OFF_EL = 10;
    const CH_TILT = 11;

    fn chanGet(self: *const Knight) Chan {
        var c: Chan = undefined;
        c[CH_BRACE] = self.legBrace;
        c[CH_LEAN] = self.bodyLean;
        c[CH_TWIST] = self.twist;
        c[CH_HEAD] = self.headPitch;
        c[CH_ARM_SH] = self.armSh;
        c[CH_OFF_SH] = self.offSh;
        c[CH_ARM_ABD] = self.armAbd;
        c[CH_OFF_ABD] = self.offAbd;
        c[CH_ARM_SWEEP] = self.armSweep;
        c[CH_ARM_EL] = self.armEl;
        c[CH_OFF_EL] = self.offEl;
        c[CH_TILT] = self.wpnTilt;
        return c;
    }
    fn chanSet(self: *Knight, c: Chan) void {
        self.legBrace = c[CH_BRACE];
        self.bodyLean = c[CH_LEAN];
        self.twist = c[CH_TWIST];
        self.headPitch = c[CH_HEAD];
        self.armSh = c[CH_ARM_SH];
        self.offSh = c[CH_OFF_SH];
        self.armAbd = c[CH_ARM_ABD];
        self.offAbd = c[CH_OFF_ABD];
        self.armSweep = c[CH_ARM_SWEEP];
        self.armEl = c[CH_ARM_EL];
        self.offEl = c[CH_OFF_EL];
        self.wpnTilt = c[CH_TILT];
    }

    /// THE FRAME'S TARGET POSE, chased by the bank. Written by whatever the state machine decided and then
    /// settled once, at the end of `update`, in one place — so no move can forget to be continuous.
    fn settlePose(self: *Knight, dt: f32) void {
        var want = self.chanGet();
        // Off his feet the body is one rigid thing meeting the ground: stiff and critically damped, or the
        // corpse jellies. Standing, he is a mass — under-damped, so every pose he takes overshoots and
        // settles onto itself (the reactions law, finally a property of the rig and not a per-move chore).
        // **THE FALL ITSELF IS NOT "DOWN"** — it is the liveliest thing he does, and stiffening it was
        // stiffening the exact move that was complained about. Only a body already ON the ground is rigid.
        const down = switch (self.state) {
            .downed, .rollover, .rise, .dead => true,
            else => false,
        };
        const stiff: f32 = if (down) SPRING_STIFF_DOWN else SPRING_STIFF;
        const zeta: f32 = if (down) 1.0 else SPRING_ZETA;
        self.springs.chase(&want, stiff, zeta, SPRING_FALLOFF, dt);
        self.chanSet(want);
    }

    fn enter(self: *Knight, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
        self.strikeFelt = false;
        self.live = false;
        self.strokeDone = 0;
        switch (s) {
            .bashwind, .thrustwind => {
                self.blow = if (s == .bashwind) .bash else .thrust;
                sfx.world(.swing_light, self.pos);
            },
            .sweepwind => {
                self.blow = .sweep;
                sfx.world(.swing_heavy, self.pos);
            },
            .chainwind => {
                self.blow = .sweep2;
                sfx.world(.swing_light, self.pos);
            },
            .overwind => {
                self.blow = .over;
                // THE DELAYED DOWNSWING, rolled at the rear, never authored: two overheads in five drop on
                // the beat and the rest HANG at the top — the reference's own bait, the tell staying honest
                // because the release cue is the blade starting to move, not the clock.
                self.windHold = if (self.aiRng.float() < 0.45) 0 else self.aiRng.range(0.25, 0.80);
                sfx.world(.swing_heavy, self.pos);
            },
            .slamwind => {
                self.blow = .slam;
                sfx.world(.ogre_heave, self.pos);
            },
            .hop => {
                self.dealt = false;
                sfx.world(.ogre_step, self.pos);
            },
            // **EVERY COMMITTED MOVE SAYS SO OUT LOUD** (owner: give him audio cues). The three newest were
            // silent, which on a creature whose whole design is "watch him and answer" is a tell deleted:
            // the pad and the lens can be pointed anywhere, and sound is the one channel that cannot miss.
            // Each is the voice that matches the MASS involved, not a generic whoosh.
            .stepturn => {
                self.leapChained = false;
                sfx.world(.ogre_step, self.pos); // armour shifting its weight onto a foot
            },
            .leapwind => {
                sfx.world(.ogre_heave, self.pos); // the coil — a body loading to leave the ground
            },
            .leap => sfx.world(.skel_lunge, self.pos), // the launch: the game's own "it is coming at you"
            .swatwind => {
                // THE FLICK BAITS TOO, on the overhead's own rule at a third of its scale. This is what
                // "tricky through TIMING" is: the gather is plain to see, the release is not.
                self.windHold = if (self.aiRng.float() < 0.5) 0 else self.aiRng.range(0.10, SWAT_HANG);
                sfx.world(.swing_light, self.pos);
            },
            .awaken => {
                self.leapChained = false;
                sfx.world(.ogre_roar, self.pos); // the phase turn, and it should carry across the arena
            },
            .chargewind => {
                self.blow = .charge;
                sfx.world(.ogre_roar, self.pos);
                self.plantBurst();
            },
            .charge => {
                sfx.world(.ogre_heave, self.pos);
                self.plantBurst();
            },
            .brake => {
                self.quake = QUAKE_BRAKE;
                sfx.world(.step_hard, self.pos);
            },
            .fallwind => {
                self.blow = .fall;
                sfx.world(.ogre_roar, self.pos);
                self.plantBurst();
            },
            // THE MOMENT HE COMMITS, in all three channels the parry's law asks for: a heave, dust off both
            // feet (legible from every angle a five-metre stroke foreshortens to nothing in), and the
            // shoulders driving over in the pose behind it.
            .sweep, .sweep2, .over, .thrust, .bash => {
                sfx.world(.ogre_heave, self.pos);
                self.plantBurst();
            },
            // …and the SWAT gets the light whoosh instead of the heave. A flick that grunts like a
            // committed stroke is a flick that lies about its weight, which is the whole thing the `Weight`
            // enum exists to stop happening in the picture.
            .swat => sfx.world(.ogre_swipe, self.pos),
            .slam => sfx.world(.ogre_heave, self.pos),
            .rollover => sfx.world(.step_hard, self.pos),
            .rise => {
                self.turnAbout();
                sfx.world(.ogre_step, self.pos);
            },
            else => {},
        }
    }

    /// **THE ROLL IS WRITTEN OFF AT THE RISE, NOT UNWOUND BY IT** (see `rollAmt`). Face-down with his head
    /// still behind his heels IS a body fallen forward and turned about, so that is what he becomes: the yaw
    /// takes the half turn and the topple takes the sign. The two poses are the same matrix — `Ry(180)·Rx(θ)`
    /// is `Rx(−θ)·Ry(180)` — so the swap is invisible on the frame it happens, which is the only reason it
    /// may be done at all. He therefore stands up FACING the man he just landed on, which is honest: the head
    /// that went over backward is the end of him that is now nearest you.
    fn turnAbout(self: *Knight) void {
        self.facing = mathx.wrapPi(self.facing + std.math.pi);
    }
    fn enterIdle(self: *Knight) void {
        self.state = .idle;
        self.t = 0;
        self.homing = false;
    }
    fn enterStun(self: *Knight, s: State) void {
        // A STRING CUT SHORT STILL OWES ITS CLOCKS. Left unbilled, being staggered out of a flurry was a
        // reward for him: he came out of the stumble with every move he had just spent still ready.
        self.billString();
        self.state = s;
        self.t = 0;
        self.dealt = false;
        self.live = false;
        self.strokeDone = 0;
        self.homing = false;
    }
    /// WHERE HIS BODY ALREADY WAS when it died, so the crumple starts from there. Killed during the punish
    /// window the death began from STANDING — a corpse flat on its back snapped upright and then fell over
    /// forwards, which is the one frame that undoes the whole opening it was killed in.
    fn enterDeath(self: *Knight) void {
        self.deathFrom = self.toppleAmt();
        self.rollFrom = self.rollAmt();
        self.enterStun(.dead);
        self.justDied = true;
    }

    /// Is the hero WALKING ROUND HIM fast enough that turning is a losing game — what the hop answers.
    /// The threshold sits under the rate a walking hero carries at his own closest approach (0.80 rad/s),
    /// so honest circling triggers it and drifting does not.
    fn circled(self: *const Knight) bool {
        return self.sense.circling(CIRCLE_RATE);
    }

    /// **IS STANDING HERE ACTUALLY COSTING HIM** — the second half of every decision to move his feet, and
    /// the half that did not exist.
    fn pressed(self: *const Knight) bool {
        return self.sense.pressed(HP_MAX, REPOSITION_AT);
    }

    fn decide(self: *Knight, dist: f32, bearingDeg: f32) void {
        // **HALF HEALTH IS THE PHASE TURN, AND IT OUTRANKS EVERY OTHER DECISION** (owner). Checked here —
        // the one place he chooses what to do next — so it can never land mid-stroke and cut a blow the
        // player had already read. It fires once (`awoken`) and the flag it sets never clears.
        if (!self.awoken and self.vit.hpFrac() <= AWAKEN.at and self.leash.roused()) {
            self.awoken = true;
            self.billString();
            return self.enter(.awaken);
        }
        if (self.leash.goingHome()) {
            self.homing = true;
            return self.enter(.approach);
        }
        var ready: [MOVES.len]bool = undefined;
        for (&ready, 0..) |*r, i| r.* = self.cds[i] <= 0;
        // The pivot step is FEET, not a leap — the roots hold it like any other step, and `foe.grip` is what
        // refuses the travel. It is gated on its own clock only.
        const dec = classify(dist, bearingDeg, self.scale, self.fallCd <= 0, self.slamCd <= 0, self.chargeReady(), self.hopCd <= 0 and foe.canLeap(&self.root), self.stepCd <= 0, self.leapCd <= 0 and foe.canLeap(&self.root), self.circled(), self.pressed(), self.cursor, &ready);
        switch (dec.what) {
            .fall => self.enter(.fallwind),
            .slam => self.enter(.slamwind),
            .hop => {
                self.hopSide = if (bearingDeg >= 0) 1.0 else -1.0;
                self.hopCd = HOP.cd * self.aiRng.range(0.8, 1.3);
                self.enter(.hop);
            },
            .stepturn => {
                self.stepCd = STEPTURN.cd * self.aiRng.range(0.85, 1.25);
                self.enter(.stepturn);
            },
            .leap => {
                self.leapCd = LEAP.cd * self.aiRng.range(0.85, 1.25);
                self.enter(.leapwind);
            },
            .charge => {
                self.farT = 0;
                self.enter(.chargewind);
            },
            .strike => {
                self.atk = dec.mv;
                self.opener = dec.mv; // the ROUTE is the opener's, not the link's
                self.shoving = dec.shove;
                self.shoveShield = dec.shoveShield;
                self.swatShield = bearingDeg > 0; // the door on his shield side, the blade on his sword side
                self.cursor +%= 1; // …and the band's pattern advances, so watching him teaches you it
                self.enter(windFor(dec.mv));
            },
            .approach => {
                self.homing = false;
                self.enter(.approach);
            },
            .wait => {
                self.homing = false;
                self.enterIdle();
            },
            .hold => {
                if (mathx.distXZ(self.pos, self.home) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.enter(.approach);
                } else self.enterIdle();
            },
        }
    }

    /// Off the stamp `pose()` already took — recomputing it is a second place for "where the kit is".
    fn wpnHere(self: *const Knight) [2]rl.Vector3 {
        return self.wpnIs orelse self.weaponSeg();
    }
    fn shieldHere(self: *const Knight) [2]rl.Vector3 {
        return self.shIs orelse self.shieldSeg();
    }
    /// Straight off the posed bone (the ogre's `clubLowWorld` law): nothing about a blow is guessed from yaw.
    pub fn weaponSeg(self: *const Knight) [2]rl.Vector3 {
        return .{
            rl.math.vector3Transform(SW_SEG[0], self.xf[WPN]),
            rl.math.vector3Transform(SW_SEG[1], self.xf[WPN]),
        };
    }
    /// …and the door's own leading face, bottom to top, off the matrix `pose` built for it.
    pub fn shieldSeg(self: *const Knight) [2]rl.Vector3 {
        return .{
            rl.math.vector3Transform(SH_LOW, self.shXf),
            rl.math.vector3Transform(SH_HIGH, self.shXf),
        };
    }

    /// The hurt shape IS the kit: what it swept this frame, against the column the hero stands in, latched to
    /// one blow per stroke — never a yaw-guessed sector. The door leads the bash AND the charge; the sword
    /// moves are the blade. **THE DOOR'S HURT WIDTH IS THE RAM, NOT THE WRAP** (`SH_RAM_HALF`): the curved
    /// edges bow back toward him, and iron behind the leading face cannot be what hit you.
    fn tryReach(self: *Knight, hero: rl.Vector3) void {
        if (self.dealt) return;
        const door = self.state == .bash or self.state == .charge;
        const r = (if (door) SH_RAM_HALF else SW_HALF_W) * self.scale + HERO_REACH;
        const was = if (door) self.shWas else self.wpnWas;
        const now = if (door) self.shieldHere() else self.wpnHere();
        if (!foe.weaponReaches(was, now, hero, r)) return;
        self.heroHit = if (self.state == .charge) CHARGE.hit else self.move().hit;
        // **AND ONCE HE IS LIT, EVERY BLOW OPENS A DISC OF CHAOS** (owner: in this phase his attacks do AoE
        // impacts). Added to the stroke's own `Hit` rather than billed separately, so it goes through the
        // hero's resists and his guard exactly like everything else does — a second damage path would be a
        // second set of rules nobody could learn. What it really changes is SPACING: ground that was safe
        // just outside a swing in phase one belongs to the blast in phase two.
        if (self.lit) {
            var h = self.heroHit.?;
            h.dmg += CHAOS_BLAST.hit.dmg;
            h.poise += CHAOS_BLAST.hit.poise;
            h.stance += CHAOS_BLAST.hit.stance;
            h.elem = h.elem.plus(CHAOS_BLAST.hit.elem);
            self.heroHit = h;
            self.chaosBurst(now[1], 18);
            self.quake = mathx.maxF(self.quake, QUAKE_BASH);
        }
        self.dealt = true;
        self.leash.noteCombat();
        // A CHARGE DOES NOT STOP FOR WHAT IT HIT — he ploughs through; the brake is where HE chose to stop.
    }

    /// THE SLAM'S BLOW: a disc round the crater the door just made, a body-length ahead of him — and wide
    /// enough to reach a little past his own boots (the Tower Knight's slam hits "even a few paces behind").
    /// Its `from` is his own `pos` (the group hands every blow the body's position), so hugging him leaves
    /// almost no bearing to block across — and there is no parry window at all (`toImpact`): the counter is
    /// DISTANCE, bought during the longest wind he has on his feet.
    fn trySlam(self: *Knight, hero: rl.Vector3) void {
        const at = self.slamMark();
        if (mathx.distXZ(at, hero) > SLAM.r * self.scale + HERO_REACH) return;
        self.heroHit = SLAM.hit;
        self.leash.noteCombat();
    }
    /// Where the door lands — one definition for the blow, the crater FX and the tests.
    /// The crater's world spot, for the harness — framing is part of the test, and this move's whole point
    /// lands a body-length off his own axis.
    pub fn slamMarkOf(self: *const Knight) rl.Vector3 {
        return self.slamMark();
    }
    fn slamMark(self: *const Knight) rl.Vector3 {
        const f = self.fdir();
        return v3(self.pos.x + f.x * SLAM.fwd * self.scale, self.pos.y, self.pos.z + f.z * SLAM.fwd * self.scale);
    }

    /// THE CRUSH: the ground his body sweeps as it goes over — a STRIP down the line BEHIND him, from a hair
    /// in front of his heels out to his own length. The whole reason his back is not a free ride.
    fn tryCrush(self: *Knight, hero: rl.Vector3, h: combat.Hit) void {
        const to = v3(hero.x - self.pos.x, 0, hero.z - self.pos.z);
        const back = mathx.scaleV(self.fdir(), -1);
        const axial = to.x * back.x + to.z * back.z;
        const lateral = @abs(to.x * back.z - to.z * back.x);
        if (axial < -FALL_BACK_SLACK * self.scale or axial > crushLen(self.scale)) return;
        if (lateral > FALL_HALF_W * self.scale + HERO_REACH) return;
        self.heroHit = h;
        self.leash.noteCombat();
    }

    /// SECONDS UNTIL THIS STROKE'S BLOW LANDS, counted ACROSS the wind->strike boundary so the tell and the
    /// stroke are ONE continuous countdown. EXHAUSTIVE, so a state added later has to say whether it carries
    /// a blow — and the FALL's, the SLAM's and the CHARGE's rows say NULL on purpose: see `parryable`.
    fn toImpact(self: *const Knight) ?f32 {
        const a = self.move();
        const live = a.strikeDur * a.impactK;
        return switch (self.state) {
            .sweepwind, .chainwind, .overwind, .thrustwind, .bashwind => (self.windDur() - self.t) + live,
            .sweep, .sweep2, .over, .thrust, .bash => live - self.t,
            // **THE SWAT HAS NO PARRY WINDOW, AND THAT IS A DECISION.** It is the Tower Knight's boot — the
            // reference's own proximity tax, "fast, weak, tiny area" — and boards that caught it would make
            // standing beside him safe again, which is the one thing the move exists to stop. Its counter is
            // your feet, it barely reaches, and it takes 14. Everything that is a real STROKE stays
            // parryable (the Crucible contract); this is a flick, and it says so by being the only weapon
            // move in the file that pays no window.
            .swatwind, .swat => null,
            .idle, .approach, .hop, .stepturn, .leapwind, .leap, .awaken, .slamwind, .slam, .chargewind, .charge, .brake, .recover, .fallwind, .fall, .downed, .rollover, .rise, .stunlight, .stunheavy, .dead => null,
        };
    }

    /// THE INSTANT THE KIT CAN BE CAUGHT IN, and how far out it reaches then.
    ///
    /// **EVERY WEAPON STROKE IS PARRYABLE AND NOTHING ELSE IS** — the Crucible Knight's own contract. The
    /// FALL, the SLAM and the CHARGE have no window, and each is a decision: there is nothing to catch in
    /// five metres of armour going over, in the door itself meeting the earth, or in a wall arriving at
    /// twice a sprint — and boards that stopped those would be the answer to the three moves that exist to
    /// move your FEET. Their counters are the roll, distance, and the sidestep.
    fn parryable(self: *const Knight) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return self.parryReach(self.move());
    }
    /// Where the kit ARRIVES at the impact frame, hero footprint included — the MOVE's own, never one number
    /// for the creature.
    fn parryReach(self: *const Knight, a: Attack) f32 {
        return a.reachOut * self.scale + HERO_REACH;
    }

    /// THE HERO'S SHIELD TAKES THE STROKE. `enterStun` is what kills it — the kit goes dead and nothing
    /// lands. THE ATTACK ALWAYS DIES; THE HEAVY STUN IS EARNED: the boards deal STANCE and nothing else, so
    /// whether a catch is a stumble or a punish window is the same bar the sword has been chipping — and 130
    /// takes three of them.
    fn takeParry(self: *Knight) void {
        const reach = self.parryable() orelse return;
        if (!self.parry.catches(self.pos, reach)) return;
        self.parried = true;
        self.flash = FLASH_DUR;
        self.leash.noteCombat();
        // The move goes on its own cooldown though it never finished: the kit has to be gathered again, or he
        // walks out of the stumble straight into the stroke he was just denied. A caught SECOND sweep bills
        // the first's clock — the chain is one move as far as the rest of the fight is concerned.
        self.cds[self.cdSlot()] = self.move().cd;
        // THE SWING VISIBLY STARTS (the ogre's rule): caught in the last instant of a WIND, a plain stun ate
        // the whole stroke and he reeled off a blade that never moved — a parry on empty air.
        switch (self.state) {
            .bashwind, .thrustwind => self.setStrike(0.32),
            .sweepwind, .chainwind, .overwind => self.setStrike(0.28),
            else => {},
        }
        // STRUCK IRON off the kit's own far end, thrown back the way it came.
        const far = if (self.state == .bash or self.state == .bashwind) self.shieldHere()[1] else self.wpnHere()[1];
        self.sparks(far, mathx.dirXZ(self.parry.at, self.pos), 18);
        sfx.world(.bone_hurt, self.pos);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
    }

    /// DID THE DOOR STAND BETWEEN HIM AND *THIS* BLOW. The shield is a DIRECTION, so what decides a block is
    /// where the blow CAME FROM, never where he is looking — asked of the BLADE's own segment, since with a
    /// spirit on the field he may be squared up to the wolf.
    fn shielded(self: *const Knight, blade: foe.Blade) bool {
        if (!self.covered) return false;
        const at = mathx.lerpV(blade.a, blade.b, 0.5);
        const d = mathx.dirXZ(self.pos, at);
        if (mathx.lenXZ(d) < 1e-4) return true; // no bearing to be wrong about — the harness's forced block
        return combat.withinArc(mathx.headingXZ(d), self.facing, TOWER_ARC);
    }

    pub fn tryHit(self: *Knight, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const blocked = self.shielded(blade);
        var b = blade;
        if (blocked) {
            b.hit = combat.guardChip(blade.hit, TOWER_NEGATE);
            // …AND THE FOOTING COMES THROUGH THE WOOD (`TOWER_STANCE_PASS`). No poise — the door may never
            // flinch him, that is what it is for — but the stance bar behind it is reachable, so sustained
            // frontal pressure ends in a break instead of ending in nothing.
            b.hit.stance = blade.hit.stance * TOWER_STANCE_PASS;
        }
        const s = foe.reached(self, b) orelse return;
        if (blocked) return self.caught(s);
        const heavyBlow = foe.wounded(self, s, blade, .{ .light = 0.30, .heavy = 0.55 });
        // …and the SPOT is billed for it (`foe.Sense`). What earns him the ground answers is damage taken
        // where he is standing — never a swing, a roll or a press, which is the NO INPUT READING law kept
        // the same way `counterFlank` keeps it: this is a blow that already landed on his own body.
        self.sense.hurt(b.hit.dmg);
        self.chips(s.contact, s.dir, if (heavyBlow) 22 else 13, if (heavyBlow) 3.6 else 2.5);
        sfx.world(.bone_hurt, self.pos);
        // **ALREADY ON THE GROUND IS THE REACTION.** A flinch state carries no topple, so a heavy landing on
        // a body flat on its back SNAPPED him upright — and that is the one window the whole creature is
        // built to hand you, so the reward for using it was the reward ending. The damage, the flash, the
        // chips and the stance all still land; only the state change is refused, and death still goes
        // through because `enterDeath` now crumples from where the body already lay.
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, 26, 3.2);
                sfx.world(.bone_die, self.pos);
                self.enterDeath();
            },
            // **HE IS NOT FLINCHED OUT OF A COMBO HE HAS ALREADY STARTED** (the reference verbatim: "can't
            // interrupt them while they're doing the triple stabby jab" — hyperarmor on the string). This
            // is the counter to answering the whole fight by mashing into him: once a route is running the
            // light flinch is refused and the string finishes. A STANCE BREAK still stops him — the earned
            // punish is never taken away — and the damage, flash, chips and stance all land regardless. It
            // is fair because the string announced itself: you watched the opener.
            .heavy => if (!self.floored()) self.enterStun(.stunheavy),
            .light => if (!self.floored() and !self.inString()) self.enterStun(.stunlight),
            // **A BLOW THAT DOES NOT MOVE HIM GETS ANSWERED** (owner: react very strongly to side attacks;
            // more countering, less slow rotating). Shrugging a hit off used to mean literally nothing
            // happened — he carried on turning at 33 deg/s while you hit him again — which is the single
            // most passive thing this creature did. Now the flank is a CONVERSATION: hit him where the door
            // is not and, if he did not flinch, he comes round on you at once.
            .none => self.counterFlank(s),
        }
    }

    /// **HE ANSWERS A FLANK BLOW HE SHRUGGED OFF** (owner: react very strongly to side attacks; more
    /// countering, less slow rotating).
    ///
    /// It reads a blow that ALREADY LANDED ON HIS OWN BODY and the bearing it came from — world state, so the
    /// NO INPUT READING law is observed. It never reads a swing, a roll, a flask or a press.
    ///
    /// WHERE you hit him picks the answer: either shoulder gets the SWAT back down the line, his SPINE gets
    /// the LEAP. Clocked, refused out of anything committed, and refused outright if the blow STAGGERED him —
    /// an earned stagger is never taken back.
    fn counterFlank(self: *Knight, s: foe.Strike) void {
        if (self.counterCd > 0 or self.floored()) return;
        switch (self.state) {
            .idle, .approach, .recover, .stepturn => {},
            else => return, // never out of a committed stroke, a gather, a charge or a stun
        }
        const from = mathx.headingXZ(mathx.scaleV(s.dir, -1));
        // Taken ONCE and signed: WHICH side is the sign and HOW FAR ROUND is the magnitude, and the two were
        // being derived from the same expression written out twice.
        const off = mathx.degrees(mathx.wrapPi(from - self.facing));
        const b = @abs(off);
        if (b <= TOWER_ARC) return; // it landed on his FRONT — that is the door's business, not this
        self.counterCd = COUNTER_CD * self.aiRng.range(0.85, 1.2);
        if (b >= 180.0 - FALL_SECTOR and self.leapCd <= 0 and foe.canLeap(&self.root)) {
            self.leapCd = LEAP.cd * self.aiRng.range(0.85, 1.25);
            return self.enter(.leapwind);
        }
        // **HE PIVOTS ONTO IT — HE DOES NOT SNAP** (owner: he turns on a dime to hit you on his side, he
        // should have to step-turn not instant). The first pass wrote the facing straight onto the blow,
        // which gave him a free instant re-face on every flank hit and made the whole flank pointless: you
        // could not get behind a creature that arrived facing you. He now pays for the turn with the same
        // PIVOT STEP everything else uses, and the swat is CHAINED off its end (`stepThen`) — so the answer
        // is a real two-beat move you can see coming and step out of, and the ground he covers to make it
        // is ground you can use.
        self.swatShield = off > 0;
        self.stepThen = SWAT_I;
        self.stepCd = STEPTURN.cd * self.aiRng.range(0.85, 1.25);
        self.enter(.stepturn);
    }

    /// THE DOOR TOOK IT. No stamina pool and no break: he gives a hand's width of ground and nothing else,
    /// which is exactly what makes the front the wrong place to be — **and the door ANSWERS** (the
    /// reference's enemy guard counter): a blow that lands on his shield may buy an immediate thrust back
    /// down the line it came from. Rolled and clocked, so the front is dangerous rather than metronomic;
    /// read off a blow that already struck HIS OWN body, which is world state and not the player's buttons.
    fn caught(self: *Knight, s: foe.Strike) void {
        self.blockT = 0;
        self.blocks += 1;
        self.shove = mathx.scaleV(self.fdir(), -0.35);
        self.sparks(s.contact, s.dir, 16);
        if (s.reaction == .death) {
            // Chipped to death behind his own shield — that is a death, not a block.
            self.hits += 1;
            self.flash = FLASH_DUR;
            sfx.world(.bone_die, self.pos);
            return self.enterDeath();
        }
        // THE REFUSAL, in the wall's own register (`audio.mkKnightRepel`) — the family's `foe_guarded` voice
        // one size up, so "my swing did nothing" reads the same on him as on a shieldman while still saying
        // WHICH thing refused it. And the door SHOVES the frame: a blow turned by four metres of plank is
        // something the player should feel refused by.
        sfx.world(.knight_repel, self.pos);
        self.quake = mathx.maxF(self.quake, QUAKE_REPEL);
        self.dustBurst(s.contact, 6, 1.2, 0.14);
        // **THE STANCE BAR BEHIND THE DOOR CAN BREAK** — the reference's pressure window, and the only thing
        // frontal work has ever been able to earn here. The SHIELD is untouched: it never breaks and it comes
        // straight back up off the stagger. A break outranks the riposte, since he is in no state to throw it.
        if (s.reaction == .heavy) {
            self.hits += 1;
            self.flash = FLASH_DUR;
            self.grit(s.contact, 14);
            sfx.world(.bone_hurt, self.pos);
            if (!self.floored()) self.enterStun(.stunheavy);
            return;
        }
        if ((self.state == .idle or self.state == .approach) and self.riposteCd <= 0 and self.aiRng.float() < 0.60) {
            self.riposteCd = 3.5;
            self.atk = THRUST_I;
            self.enter(.thrustwind);
        }
    }

    // Debug hooks for the --shot harness (force a beat in isolation).
    pub fn debugBash(self: *Knight) void {
        self.atk = BASH_I;
        self.shoving = false;
        self.shoveShield = false;
        self.enter(.bashwind);
    }
    /// `shield` picks WHICH WAY the door is hauled — stated, like `debugSwat`'s side, because left to
    /// whatever the last choose happened to set it the harness photographs a different move run to run.
    pub fn debugShove(self: *Knight, shield: bool) void {
        self.atk = BASH_I;
        self.shoving = true;
        self.shoveShield = shield;
        self.enter(.bashwind);
    }
    pub fn debugSweep(self: *Knight) void {
        self.atk = SWEEP_I;
        self.enter(.sweepwind);
    }
    pub fn debugSweep2(self: *Knight) void {
        self.atk = SWEEP2_I;
        self.enter(.chainwind);
    }
    pub fn debugOverhead(self: *Knight) void {
        self.atk = OVER_I;
        self.enter(.overwind);
        self.windHold = 0; // a framing counted in frames has to land on the same pose every run
    }
    pub fn debugThrust(self: *Knight) void {
        self.atk = THRUST_I;
        self.enter(.thrustwind);
    }
    pub fn debugSlam(self: *Knight) void {
        self.enter(.slamwind);
    }
    pub fn debugAwaken(self: *Knight) void {
        self.awoken = true;
        self.enter(.awaken);
    }
    pub fn debugLeap(self: *Knight) void {
        self.enter(.leapwind);
    }
    pub fn debugStepTurn(self: *Knight) void {
        self.enter(.stepturn);
    }
    pub fn debugSwat(self: *Knight, shieldSide: bool) void {
        self.atk = SWAT_I;
        self.swatShield = shieldSide;
        self.enter(.swatwind);
    }
    pub fn debugHop(self: *Knight, side: f32) void {
        self.hopSide = side;
        self.enter(.hop);
    }
    pub fn debugCharge(self: *Knight) void {
        self.enter(.chargewind);
    }
    pub fn debugFall(self: *Knight) void {
        self.enter(.fallwind);
    }
    pub fn debugStagger(self: *Knight, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Knight) void {
        self.enterDeath();
    }

    fn setCarry(self: *Knight, dt: f32) void {
        const e = dt * 6.0;
        const breathe = mathx.sinf(self.elapsed * 0.95 + self.seed * 6.28);
        const stalk = self.moving;
        // THE RECOIL OF A CAUGHT BLOW GOES INTO THE MAN, NOT THE ARM (hero.zig's rule): a sink and a step
        // back, so a blow the door CAUGHT never looks like one that knocked it aside.
        const rec = mathx.maxF(0, 1.0 - self.blockT / 0.26);
        self.armSh = mathx.approach(self.armSh, CARRY_SH + 2.5 * breathe - 4.0 * stalk, e);
        self.armEl = mathx.approach(self.armEl, CARRY_EL, e);
        self.armAbd = mathx.approach(self.armAbd, CARRY_ABD + 2.0 * breathe, e);
        self.armSweep = mathx.approach(self.armSweep, -5.0 * stalk, e); // the low blade TRAILS the stride
        self.wpnTilt = mathx.approach(self.wpnTilt, CARRY_TILT, e);
        self.offSh = mathx.approach(self.offSh, GUARD_SH + 14.0 * rec, e);
        self.offEl = mathx.approach(self.offEl, GUARD_EL - 8.0 * rec, e);
        self.offAbd = mathx.approach(self.offAbd, GUARD_ABD + 1.5 * breathe, e);
        self.bodyLean = mathx.approach(self.bodyLean, GUARD_LEAN + 1.0 * breathe + 5.0 * stalk + 10.0 * rec, e);
        self.twist = mathx.approach(self.twist, GUARD_TWIST, e);
        self.headPitch = mathx.approach(self.headPitch, 3.0 + 1.4 * breathe - 5.0 * stalk + 8.0 * rec, e);
        self.legBrace = mathx.approach(self.legBrace, 0.16 + 0.5 * rec, e);
    }

    /// A STAGGERED BODY GIVES UP ITS POSTURE, and `approach` steps in the units of what it is moving — so ONE
    /// rate cannot serve an angle and a fraction (the ogre's forty-second club arm).
    fn easeNeutral(self: *Knight, dt: f32) void {
        const d = dt * STUN_EASE_DEG;
        self.armSh = mathx.approach(self.armSh, CARRY_SH, d);
        self.armEl = mathx.approach(self.armEl, CARRY_EL, d);
        self.armAbd = mathx.approach(self.armAbd, CARRY_ABD, d);
        self.armSweep = mathx.approach(self.armSweep, 0, d);
        self.wpnTilt = mathx.approach(self.wpnTilt, CARRY_TILT, d * 2.0);
        self.offSh = mathx.approach(self.offSh, GUARD_SH, d);
        self.offEl = mathx.approach(self.offEl, GUARD_EL, d);
        self.offAbd = mathx.approach(self.offAbd, GUARD_ABD, d);
        self.bodyLean = mathx.approach(self.bodyLean, GUARD_LEAN, d);
        self.twist = mathx.approach(self.twist, GUARD_TWIST, d * 2.0);
        self.headPitch = mathx.approach(self.headPitch, 3.0, d);
        self.legBrace = mathx.approach(self.legBrace, 0, dt * STUN_EASE_FRAC);
    }

    /// …and a FLOORED one gives it up differently: the arms stay clamped over the chest and the legs stay
    /// straight, because what says "he is down" is the whole body being one rigid thing on the ground.
    fn easeFloored(self: *Knight, dt: f32) void {
        const d = dt * 120.0;
        self.armSh = mathx.approach(self.armSh, FALL_SH, d);
        self.armEl = mathx.approach(self.armEl, FALL_EL, d);
        self.armAbd = mathx.approach(self.armAbd, 8.0, d);
        self.armSweep = mathx.approach(self.armSweep, 0, d);
        // The blade barely moves as he goes over: a falling knight does not rearrange his sword, and the
        // topple carries it with the arm. A long travel from the carry would windmill it through the fall.
        self.wpnTilt = mathx.approach(self.wpnTilt, FLOORED_TILT, d);
        self.offSh = mathx.approach(self.offSh, FALL_SH, d);
        self.offEl = mathx.approach(self.offEl, FALL_EL, d);
        self.offAbd = mathx.approach(self.offAbd, 6.0, d);
        self.bodyLean = mathx.approach(self.bodyLean, 2.0, d);
        self.twist = mathx.approach(self.twist, 0, d);
        self.headPitch = mathx.approach(self.headPitch, -6.0, d); // the helm tips back off the ground
        self.legBrace = mathx.approach(self.legBrace, 0, dt * STUN_EASE_FRAC);
    }

    /// THE STRIKES RUN ON STAGGERED CLOCKS (the welded-block law, enforced here rather than remembered):
    /// the TRUNK leads, the ARM whips after it, the BLADE trails the arm — three curves off one `k`, so the
    /// mass visibly flows outward instead of every joint peaking on the same frame.
    /// **THE STROKE, OFF ITS OWN KEYED TRACK.** It used to compute three curves off one `k` — sqrt for the
    /// trunk, cubed for the arm, squared for the blade — to fake an outward lag by hand, and then lerp
    /// twelve channels between two constants. The lag is `anim.SpringBank`'s job now, and the SHAPE is the
    /// key list's, which is why a stroke can finally have a settle-back, a snap and a follow-through.
    fn setStrike(self: *Knight, k: f32) void {
        self.chanSet(samplePose(self.trackFor().strike, k));
    }
    /// The move's track, with the two-picture rows resolved (`shoving` for the bash, `swatSide` for the swat).
    fn trackFor(self: *const Knight) MoveKeys {
        return switch (self.atk) {
            BASH_I => bashKeys(self.shoving),
            SWAT_I => swatKeys(self.swatShield),
            else => keysFor(self.atk),
        };
    }
    /// …and the gather. `.hold` on the overhead's last key is what makes `windHold` a bait rather than a
    /// drift, so the wind's own clock may exceed 1 and the pose simply stops travelling.
    fn setWindKeys(self: *Knight, k: f32) void {
        self.chanSet(samplePose(self.trackFor().wind, k));
    }

    /// THE DOOR HAULED OVERHEAD — the slam's wind. The whole silhouette inverts: the wall that has covered
    /// him all fight stands in the air with his chest bare under it, and `guardUp` says exactly that.
    /// Off `SLAM_KEYS` now — a sink, a haul, and a dead-still hang at the top. The shiver stays: it is a
    /// body STRAINING under four metres of door, and it rides ON the keyed pose rather than instead of it.
    fn setSlamWind(self: *Knight, k: f32) void {
        self.chanSet(samplePose(SLAM_KEYS.wind, k));
        const shiver = mathx.sinf(self.t * 24.0) * 1.5 * mathx.smoothstep(0.72, 1.0, mathx.minF(k, 1.0));
        self.offSh += shiver;
        self.bodyLean += shiver * 0.4;
    }

    /// …AND DRIVEN INTO THE EARTH: the trunk folds through it, the knees take the landing, and the door
    /// stays down a beat — the "huge opening" the reference promises for reading it.
    /// The drive, the earth's answer, and the recoil off it — `SLAM_KEYS.strike`.
    fn setSlam(self: *Knight, kW: f32) void {
        self.chanSet(samplePose(SLAM_KEYS.strike, kW));
    }

    /// ONE WEIGHT SHIFT SIDEWAYS: dip, bound, heavy settle — banked a few degrees into the travel, the door
    /// kept square to him the whole way. What reads is the mass leaving the ground AT ALL.
    fn setHop(self: *Knight, t: f32) void {
        const t0 = HOP.windDur;
        const t1 = HOP.windDur + HOP.airDur;
        const dip = mathx.smoothstep(0, t0, mathx.minF(t, t0)) * (1.0 - mathx.smoothstep(t0, t0 + 0.10, t));
        const air = mathx.clampF((t - t0) / HOP.airDur, 0, 1) * (1.0 - mathx.smoothstep(t1, t1 + 0.06, t));
        const settle = mathx.smoothstep(t1, t1 + HOP.settleDur * 0.8, t);
        const bank = HOP_BANK * self.hopSide * air * (1.0 - settle);
        self.armSh = CARRY_SH;
        self.armEl = CARRY_EL;
        self.armAbd = CARRY_ABD + 6.0 * air;
        self.armSweep = -4.0 * air * self.hopSide;
        self.wpnTilt = CARRY_TILT;
        self.offSh = GUARD_SH;
        self.offEl = GUARD_EL;
        self.offAbd = GUARD_ABD;
        self.bodyLean = GUARD_LEAN + 3.0 * air;
        self.twist = GUARD_TWIST + bank; // the bank rides the twist channel: cosmetic, never the door's arc
        self.headPitch = 3.0;
        // The knees: deep dip, airborne release, and a settle that OVERSHOOTS (a mass arriving, not easing).
        self.legBrace = 0.16 + 0.55 * dip + 0.30 * mathx.pulse(mathx.clampF((t - t1) / HOP.settleDur, 0, 1), 0, 0.25, 0.45, 0.95);
    }

    /// THE AWAKENING'S POSE. He plants both feet, hauls the blade up the FRONT of him and holds it over the
    /// helm with the door still square — the overhead's silhouette held ten times as long, which is the
    /// point: the player has already learned to read steel above the helm as danger, and this is that
    /// picture with nothing coming out of it. The hold SHIVERS, because he is straining against what is
    /// gathering on the blade rather than posing.
    fn setAwaken(self: *Knight, t: f32) void {
        const lift = mathx.smoothstep(0, AWAKEN.liftDur, t);
        const hold = mathx.smoothstep(AWAKEN.liftDur, AWAKEN.liftDur + 0.25, t);
        const done = mathx.smoothstep(AWAKEN.liftDur + AWAKEN.holdDur, AWAKEN.liftDur + AWAKEN.holdDur + AWAKEN.settleDur, t);
        const shiver = mathx.sinf(self.elapsed * 30.0) * 2.2 * hold * (1.0 - done);
        self.armSh = lerpF(CARRY_SH, AWK_SH, lift) + shiver;
        self.armEl = lerpF(CARRY_EL, AWK_EL, lift);
        self.armAbd = lerpF(CARRY_ABD, AWK_ABD, lift);
        self.armSweep = 0;
        self.wpnTilt = lerpF(CARRY_TILT, AWK_TILT, lift) + shiver * 0.5;
        self.offSh = GUARD_SH + 10.0 * lift;
        self.offEl = GUARD_EL;
        self.offAbd = GUARD_ABD + 4.0 * lift;
        // He arches BACK under it and comes down onto his heels as it takes — a body accepting a weight.
        self.bodyLean = GUARD_LEAN - AWK_ARCH * lift + 26.0 * done;
        self.twist = GUARD_TWIST;
        self.headPitch = 3.0 - 22.0 * lift + 30.0 * done; // the helm follows the blade up, then drops
        self.legBrace = 0.16 + 0.44 * lift + 0.30 * done * (1.0 - done);
    }

    /// THE CHAOS GATHERING ONTO THE STEEL. It runs `elemfx`'s own signature (`gather` pulls INWARD, and
    /// chaos is the element that goes the wrong way) onto the BLADE's live segment, so the fire is on the
    /// weapon rather than floating near it — which is what makes the picture read as the sword being
    /// charged rather than as weather.
    fn emitAwaken(self: *Knight, dt: f32) void {
        const seg = self.wpnHere();
        // **IT HAS TO LOOK LIKE THE SWORD IS BEING CHARGED, NOT LIKE WEATHER.** The first pass drew about a
        // dozen motes over a metre of air around the blade and the shot came back with four faint specks —
        // a phase turn nobody would notice. Dense, and pulled TIGHT onto the steel: `gather` runs inward, so
        // a small radius makes them converge on the edge instead of drifting past it.
        const k = mathx.clampF(self.t / (AWAKEN.liftDur + AWAKEN.holdDur), 0, 1);
        self.emberAccum += (30.0 + 210.0 * k) * dt;
        while (self.emberAccum >= 1.0) {
            self.emberAccum -= 1.0;
            const at = mathx.lerpV(seg[0], seg[1], self.fxRng.float());
            elemfx.gather(&self.parts, &self.fxHead, &self.fxRng, at, .chaos, 1, 0.22 + 0.26 * k, self.scale * 0.5);
        }
    }

    /// …AND WHAT EVERY BLOW OPENS ONCE HE IS LIT. `burst` is the outward verb; chaos's own signature makes
    /// it travel INWARD, which is the one thing that tells this element apart with the colour taken away.
    fn chaosBurst(self: *Knight, at: rl.Vector3, n: usize) void {
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, mathx.zero3, .chaos, n, self.scale * 0.7);
    }

    /// HOW LONG THE COIL RUNS. **Chained straight off a swat it is far shorter** (owner: the swipe-and-leap
    /// on his side should be a bit faster and more evil) — he is already low and loaded from the flick, so
    /// there is nothing left to gather. Thrown cold it keeps its full tell, because a five-metre body
    /// leaving the ground out of nowhere is exactly the kind of thing this game's own laws refuse.
    fn leapWind(self: *const Knight) f32 {
        return if (self.leapChained) LEAP.windDur * LEAP_CHAIN_WIND else LEAP.windDur;
    }

    /// THE LEAP'S POSE, across the whole move (`t` counted from the coil). Three beats: LOAD — everything
    /// sinks and folds in, which is what a body about to jump looks like from any angle; FLIGHT — he
    /// EXTENDS, knees released, the door tucked across him and the sword trailing; LAND — the knees eat it
    /// and overshoot before settling. It is the one thing he does with no blow on the end, so all of the
    /// information in it is postural.
    fn setLeap(self: *Knight, t: f32) void {
        const t0 = LEAP.windDur;
        const t1 = t0 + LEAP.flightDur;
        const load = mathx.smoothstep(0, t0, mathx.minF(t, t0)) * (1.0 - mathx.smoothstep(t0, t0 + 0.08, t));
        const air = mathx.clampF((t - t0) / LEAP.flightDur, 0, 1) * (1.0 - mathx.smoothstep(t1, t1 + 0.07, t));
        const land = mathx.smoothstep(t1, t1 + LEAP.landDur * 0.7, t);
        self.armSh = CARRY_SH - 26.0 * load + 16.0 * air;
        self.armEl = CARRY_EL - 30.0 * load - 10.0 * air;
        self.armAbd = CARRY_ABD + 6.0 * load + 20.0 * air;
        self.armSweep = -8.0 * air; // the blade trails the flight
        self.wpnTilt = CARRY_TILT + 22.0 * air;
        // THE DOOR COMES IN TIGHT AND STAYS THERE. He is not blocking with it, he is carrying it clear of
        // his own legs — and it never leaves his front, which is why the leap is not an opening.
        self.offSh = GUARD_SH + 12.0 * load + 6.0 * air;
        self.offEl = GUARD_EL - 8.0 * load;
        self.offAbd = GUARD_ABD + 4.0 * load;
        self.bodyLean = GUARD_LEAN + 16.0 * load - 12.0 * air + 8.0 * land * (1.0 - land);
        self.twist = GUARD_TWIST;
        self.headPitch = 3.0 + 8.0 * load - 6.0 * air;
        // Deep coil, RELEASED in the air (a jump is legs going straight), and a landing that overshoots.
        self.legBrace = 0.16 + 0.72 * load - 0.14 * air +
            0.40 * mathx.pulse(mathx.clampF((t - t1) / LEAP.landDur, 0, 1), 0, 0.20, 0.42, 0.95);
    }

    /// THE PIVOT STEP'S POSE: he DIPS onto the plant foot, drives round with the shoulders leading the hips
    /// (which is what a pivot is), and the settle OVERSHOOTS and comes back — a mass arriving. The door
    /// stays square across his front the whole way: he is re-facing BEHIND it, which is the entire point.
    fn setStepTurn(self: *Knight, t: f32) void {
        const t0 = STEPTURN.windDur;
        const t1 = t0 + STEPTURN.turnDur;
        const dip = mathx.smoothstep(0, t0, mathx.minF(t, t0)) * (1.0 - mathx.smoothstep(t1, t1 + 0.10, t));
        const drive = mathx.clampF((t - t0) / STEPTURN.turnDur, 0, 1);
        const settle = mathx.smoothstep(t1, t1 + STEPTURN.settleDur * 0.7, t);
        // The trunk LEADS the feet and unwinds onto them — a body turning, not a turntable.
        const lead = mathx.pulse(t / (t1 + STEPTURN.settleDur), 0.10, 0.42, 0.58, 1.0);
        self.armSh = CARRY_SH - 8.0 * dip;
        self.armEl = CARRY_EL;
        self.armAbd = CARRY_ABD + 10.0 * drive * (1.0 - settle);
        self.armSweep = -12.0 * lead;
        self.wpnTilt = CARRY_TILT + 6.0 * drive;
        self.offSh = GUARD_SH + 6.0 * dip;
        self.offEl = GUARD_EL;
        self.offAbd = GUARD_ABD + 4.0 * dip;
        self.bodyLean = GUARD_LEAN + 9.0 * dip - 4.0 * settle;
        self.twist = GUARD_TWIST + STEP_LEAD * lead;
        self.headPitch = 3.0 - 6.0 * dip;
        // Deep dip, release through the drive, and a settle that overshoots (the reactions law).
        self.legBrace = 0.16 + 0.52 * dip + 0.26 * mathx.pulse(mathx.clampF((t - t1) / STEPTURN.settleDur, 0, 1), 0, 0.22, 0.44, 0.95);
    }

    /// LOWERED BEHIND THE DOOR: brace deep, trunk dropped, the sword trailed straight back like a rudder.
    /// Off `CHARGE_KEYS` — the shiver stays, a body straining against its own held launch.
    fn setChargeWind(self: *Knight, k: f32) void {
        self.chanSet(samplePose(CHARGE_KEYS.wind, k));
        const shiver = mathx.sinf(self.t * 24.0) * 1.4 * mathx.smoothstep(0.60, 1.0, mathx.minF(k, 1.0));
        self.bodyLean += shiver;
    }

    /// …and the travel HOLDS that shape while the stride runs under it — the coil releasing into the run is
    /// the track's own first beat (`CHG_LOOSE`), because the travel's length varies with where you stood.
    fn setCharge(self: *Knight, t: f32) void {
        self.chanSet(samplePose(CHARGE_KEYS.strike, mathx.clampF(t / CHG_LOOSE, 0, 1)));
    }

    /// THE SKID: hauled back over his heels with the door thrown wide off the line — the opening the
    /// sidestep just earned — ending on the End Pose the recover then holds (`CHARGE_KEYS.recover`).
    fn setBrake(self: *Knight, u: f32) void {
        self.chanSet(samplePose(CHARGE_KEYS.recover, u));
    }

    /// THE RECOVER HOLDS ITS END POSE (`END_HOLD`) BEFORE IT EASES HOME — the five-phase contract's held
    /// End Pose: the blade in the earth, the door in the crater, the lunge at full stretch. The hold IS the
    /// punish window being shown; an attack that flows straight back to the carry reads as rubber.
    /// EVERY BLOW RECOVERS OFF ITS OWN TRACK now, which is where the held End Pose and the drag back out of
    /// it are authored. The old hand-written branches survived here a while after the tracks landed — five
    /// of them unreachable, and the SWAT quietly recovering off the BASH's track instead of its own.
    fn setRecover(self: *Knight, u: f32) void {
        const track = switch (self.blow) {
            .sweep => SWEEP_KEYS,
            .sweep2 => SWEEP2_KEYS,
            .over => OVER_KEYS,
            .thrust => THRUST_KEYS,
            .bash => bashKeys(self.shoving),
            .swat => swatKeys(self.swatShield),
            .slam => SLAM_KEYS,
            .charge => return self.chanSet(samplePose(&CHG_REC, u)),
            // The fall's aftermath is its own three states (downed/rollover/rise) and never passes through
            // here; its track holds the floored pose, so a stray route is a body lying still, not a glitch.
            .fall => FALL_KEYS,
        };
        self.chanSet(samplePose(track.recover, u));
    }

    /// THE TELL. He rocks FORWARD over his toes first — the anticipation every mass owes — and then hangs
    /// back over his heels with the door clamped across his chest, and the knees LOCK. Nothing else on him
    /// straightens its legs to attack.
    fn setFallWind(self: *Knight, k: f32) void {
        self.chanSet(samplePose(FALL_KEYS.wind, k));
        const shiver = mathx.sinf(self.t * 24.0) * 1.6 * mathx.smoothstep(0.66, 1.0, mathx.minF(k, 1.0));
        self.bodyLean += shiver;
    }

    fn setFalling(self: *Knight, k: f32) void {
        self.chanSet(samplePose(FALL_KEYS.strike, k));
    }

    /// THE HEAVE ONTO HIS FRONT. **A RIGID BODY CANNOT ROLL** — both arms clamped over the chest and both
    /// legs straight is why this read as a crate turning over (owner). The sword arm is THROWN across him
    /// first and the body follows it, the shield elbow drives him off the ground, and the shoulders lead the
    /// hips (`twist`), which is what a roll actually is.
    fn setRollover(self: *Knight, u: f32) void {
        const throwArm = mathx.pulse(u, 0, 0.30, 0.50, 0.92);
        const drive = mathx.pulse(u, 0.06, 0.34, 0.62, 1.0);
        self.armSh = FALL_SH - 54.0 * throwArm;
        self.armEl = FALL_EL - 32.0 * throwArm;
        self.armAbd = 8.0 + 36.0 * throwArm;
        self.armSweep = -28.0 * throwArm;
        self.wpnTilt = FLOORED_TILT;
        self.offSh = FALL_SH + 32.0 * drive;
        self.offEl = FALL_EL - 46.0 * drive;
        self.offAbd = 6.0 + 28.0 * drive;
        self.bodyLean = 2.0 + 16.0 * throwArm;
        self.twist = -24.0 * throwArm; // the shoulders go first and the hips are dragged after them
        self.headPitch = -6.0 + 18.0 * throwArm;
        self.legBrace = 0;
    }

    /// UP OFF THE SHIELD, and it is the slowest thing he does. He is on his FRONT by now (`turnAbout`), so
    /// the knee that comes under him is what makes it a rise and not a hoist.
    fn setRise(self: *Knight, u: f32) void {
        const push = mathx.pulse(u, 0.10, 0.40, 0.58, 0.92); // the heave on the shield arm
        const up = mathx.smoothstep(0.34, 1.0, u);
        self.offSh = lerpF(FALL_SH, GUARD_SH, up) - 34.0 * push;
        self.offEl = lerpF(FALL_EL, GUARD_EL, up) - 26.0 * push;
        self.offAbd = lerpF(6.0, GUARD_ABD, up) + 20.0 * push;
        self.armSh = lerpF(FALL_SH, CARRY_SH, up);
        self.armEl = lerpF(FALL_EL, CARRY_EL, up);
        self.armAbd = lerpF(8.0, CARRY_ABD, up);
        self.wpnTilt = lerpF(FLOORED_TILT, CARRY_TILT, up);
        self.bodyLean = lerpF(2.0, GUARD_LEAN, up) + 22.0 * push;
        self.twist = lerpF(0, GUARD_TWIST, up);
        self.headPitch = lerpF(-6.0, 3.0, up) + 14.0 * push;
        self.legBrace = mathx.pulse(u, 0.18, 0.52, 0.70, 1.0);
    }

    fn stunAmount(self: *const Knight) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t, false),
            .stunheavy => foe.stunCurve(self.t, true),
            else => 0,
        };
    }

    /// The whole rig's scale, dissipation included. ONE definition: the door is not a bone and has to arrive
    /// at the same number `pose` did, or it shrinks on a different curve to the arm holding it.
    pub fn rigScale(self: *const Knight) f32 {
        return self.scale * (1.0 - 0.62 * self.fade);
    }

    pub fn pose(self: *Knight) void {
        const fs = self.rigScale();
        const sink = -0.9 * self.scale * self.fade;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const stun = self.stunAmount();
        const topple = self.toppleAmt();
        const roll = self.rollAmt();
        const down = @abs(topple);

        // A GIANT SWINGS BY PLANTING. `legChain` owns the legs off `moving`, which only knows whether ground
        // was covered — so a stroke thrown out of a walk kept its stride running underneath it and the
        // upper body swung on top of a body still strolling. The committed states put both feet down.
        const m = self.moving * (1.0 - down) * (1.0 - self.planted());
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const sway = heromod.strafeSway(0, 0) * mathx.sinf(twoPi * self.phase) * m;
        const prot = A_PROT * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB);
        // THE LEGS TAKE THE BRACE IN THE KNEES, they do not squat: only the small pelvis drop a real knee
        // bend costs.
        const braceSink = 0.034 * H * self.legBrace;

        var wx: [N]rl.Matrix = undefined;
        const bodyPitch = self.bodyLean * (1.0 - down) - 26.0 * stun;
        const pitchRoot = bodyPitch * PELVIS_SHARE;
        // …and once he is over, the RING: a mass in motion overshoots its rest and settles back onto it, so
        // the body bounces once off the earth rather than arriving and stopping.
        // **ITS PHASE IS THE DECAY ITSELF, NOT A CLOCK BESIDE IT.** Read off `self.t` the ring restarted from
        // zero on every state change while `thud` was still ringing, and `.fall`→`.downed` lands inside it —
        // which snapped the whole body a quarter of a metre down its own length on that frame. Driven off
        // `thud` it starts at 0 when the thud is armed, rings out over exactly three half-cycles, and is back
        // at 0 when the decay is: continuous at both ends and blind to which state is holding it.
        const ring = self.thud * mathx.sinf((1.0 - self.thud) * 3.0 * std.math.pi);
        // …and the roll HEAVES the body up over its own side and drops it on the far one. Half a period of a
        // sine over the roll, so it is back on the ground at both ends of it.
        const hump = ROLL_HUMP * mathx.sinf(std.math.pi * roll);
        // …and `air` is the LEAP's own height off the earth (the archer's `hop`), in world units already, so
        // it is added outside the scale like the sink is.
        const lieLift = (LIE_LIFT * down + 0.10 * ring + hump) * self.scale + self.air;
        const pelvY = hipY + bob - braceSink;

        // ONE ORIENTATION FOR THE WHOLE BODY — the roll about his own long axis inside the rig, the topple
        // about the ground between his feet, then his yaw. Stamped, because the door reads it back.
        self.bodyXf = mul3(ry(180.0 * roll), rx(-TOPPLE_DEG * topple), ry(facingDeg));
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(0), rx(pitchRoot), ry(prot + self.twist * 0.20 + 180.0 * roll)),
            mul3(tr(sway * fs, pelvY * fs + sink, 0), rx(-TOPPLE_DEG * topple), tr(0, lieLift, 0)),
            mul(ry(facingDeg), heromod.rootAt(self.pos)),
        ));

        // `hero.legChain` owns the legs whenever nothing else has taken them: the fall, the rise and the
        // death crumple each pose them outright, and they are mutually exclusive by construction.
        if (!dead and !self.floored()) {
            heromod.legChain(&wx, &self.rest, self.phase, m, 0, self.fwdB, 0, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.phase + 0.5, m, 0, self.fwdB, 0, -1.0, HIPR, KNEER, solePatches[1]);
        }
        self.poseUpper(&wx, stun, dead, prot, bodyPitch);
        self.xf = wx;
        // …and the kit's own sweep is stamped LAST, off the pose that was just built.
        self.shXf = shieldXf(self);
        const seg = self.weaponSeg();
        self.wpnWas = self.wpnIs orelse seg;
        self.wpnIs = seg;
        const sh = self.shieldSeg();
        self.shWas = self.shIs orelse sh;
        self.shIs = sh;
    }

    fn poseUpper(self: *Knight, wx: *[N]rl.Matrix, stun: f32, dead: bool, prot: f32, bodyPitch: f32) void {
        const rest = self.rest;
        const wonk = (self.seed - 0.5) * 5.0; // each one stands its own crooked way (cosmetic only)
        const waist = bodyPitch * (1.0 - PELVIS_SHARE);
        const dk = if (dead) mathx.smoothstep(0, DEATH_DUR * 0.5, self.t) else 0;
        const rise = if (self.state == .rise) mathx.pulse(self.t / RISE_DUR, 0.18, 0.52, 0.70, 1.0) else 0;

        setLocal(wx, SPINE, rest, mul3(rx(waist * 0.44), ry(-0.35 * prot + self.twist * 0.40), rz(wonk * 0.5)));
        setLocal(wx, CHEST, rest, mul3(rx(waist * 0.56), ry(-0.5 * prot + self.twist * 0.60), rz(-wonk * 0.3)));
        setLocal(wx, NECK, rest, rx(self.headPitch * 0.4 - 8.0 * stun + 10.0 * dk));
        setLocal(wx, SKULL, rest, mul3(
            rx(self.headPitch * 0.6 - 28.0 * stun + 18.0 * dk),
            ry(self.headYaw - self.twist * 0.3),
            rz(wonk + 10.0 * dk),
        ));

        if (dead) {
            // He goes over FORWARD onto his face, which is the one thing that separates a death from the
            // fall he does on purpose — and the legs buckle rather than staying locked.
            setLocal(wx, HIPL, rest, mul(rx(34.0 * dk), rz(-4.0)));
            setLocal(wx, KNEEL, rest, rx(8.0 + 74.0 * dk));
            setLocal(wx, ANKL, rest, rx(18.0 * dk));
            setLocal(wx, HIPR, rest, mul(rx(28.0 * dk), rz(4.0)));
            setLocal(wx, KNEER, rest, rx(8.0 + 62.0 * dk));
            setLocal(wx, ANKR, rest, rx(14.0 * dk));
        } else if (self.floored()) {
            // ONE KNEE COMES UNDER HIM on the rise and the other stays out — symmetric legs would be a
            // sit-up. Flat, both are straight: a felled statue does not bend. …and the TOP LEG is thrown
            // over on the roll, because that is the half of a roll the arms cannot do.
            const cross = if (self.state == .rollover) mathx.pulse(self.t / ROLL_DUR, 0, 0.26, 0.54, 0.96) else 0;
            setLocal(wx, HIPL, rest, mul(rx(-RISE_HIP * rise - 30.0 * cross), rz(-4.0 - 20.0 * cross)));
            setLocal(wx, KNEEL, rest, rx(4.0 + RISE_KNEE * rise + 46.0 * cross));
            setLocal(wx, ANKL, rest, rx(-14.0 * rise));
            setLocal(wx, HIPR, rest, mul(rx(-8.0 * rise - 6.0 * cross), rz(4.0)));
            setLocal(wx, KNEER, rest, rx(4.0 + 20.0 * rise + 12.0 * cross));
            setLocal(wx, ANKR, rest, rx(8.0 * rise));
        }

        const armStun = -58.0 * stun;
        setLocal(wx, SHR, rest, mul3(
            rx(-self.armSh + armStun - 20.0 * dk),
            rz(-self.armAbd + wonk * 0.4),
            ry(-self.armSweep),
        ));
        setLocal(wx, ELR, rest, rx(self.armEl));
        setLocal(wx, WRR, rest, rz(-4.0));
        setLocal(wx, WPN, rest, wpnFit(self.wpnTilt));

        // THE DOOR PAYS FOR THE SWIPE. Applied here rather than in each `set*` so the picture cannot drift
        // from `guardUp` one stroke at a time — both ends read `swipeOpen`, and a test pins them together.
        const open = self.swipeOpen();
        // …and the SHOVE hauls it the other way entirely: across his front onto his sword side. Same slot,
        // opposite sign, and the two can never both be running (a swipe is the sword arm's move).
        const across = self.shoveAcross();
        setLocal(wx, SHL, rest, mul3(
            rx(-(self.offSh - SWIPE_SH * open) + armStun - 16.0 * dk),
            rz(-(self.offAbd + SWIPE_ABD * open) - wonk * 0.4),
            ry(self.armSweep * 0.30 + SWIPE_YAW * open + SHOVE_YAW * across * self.shoveDir()),
        ));
        setLocal(wx, ELL, rest, rx(self.offEl));
        setLocal(wx, WRL, rest, rz(5.0));
    }

    // He does not bleed: every burst here is DUST, BONE or struck IRON.

    fn emit(self: *Knight, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.parts, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }

    fn dustBurst(self: *Knight, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(0.45, 1.0) * spd * self.scale;
            self.emit(
                v3(c.x, self.pos.y + 0.06, c.z),
                v3(mathx.cosf(a) * s, self.fxRng.range(0.8, 3.0), mathx.sinf(a) * s),
                self.fxRng.range(0.42, 0.76),
                self.fxRng.range(0.08, 0.17) * self.scale,
                big * self.fxRng.range(0.8, 1.35) * self.scale,
                DUST,
                4.4,
            );
        }
    }
    fn grit(self: *Knight, c: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(1.3, 3.6) * self.scale;
            self.emit(
                v3(c.x, self.pos.y + 0.09, c.z),
                v3(mathx.cosf(a) * s, self.fxRng.range(2.6, 5.6), mathx.sinf(a) * s),
                self.fxRng.range(0.48, 0.9),
                self.fxRng.range(0.026, 0.058) * self.scale,
                0.012,
                CHIP,
                9.0,
            );
        }
    }
    fn chips(self: *Knight, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        const parts = foe.hitParts(n); // the field's one dial (`foe.HIT_PARTS`)
        var i: i32 = 0;
        while (i < parts) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.4, 1.0) * spd;
            self.emit(
                at,
                v3(dir.x * sp + mathx.cosf(a) * self.fxRng.range(0.2, 1.2), self.fxRng.range(0.9, 3.2), dir.z * sp + mathx.sinf(a) * self.fxRng.range(0.2, 1.2)),
                self.fxRng.range(0.34, 0.64),
                self.fxRng.range(0.024, 0.055) * self.scale,
                0.008,
                CHIP,
                8.0,
            );
        }
    }
    fn sparks(self: *Knight, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(1.5, 4.4);
            self.emit(
                at,
                v3(-dir.x * sp * 0.5 + mathx.cosf(a) * sp * 0.6, self.fxRng.range(1.2, 3.8), -dir.z * sp * 0.5 + mathx.sinf(a) * sp * 0.6),
                self.fxRng.range(0.16, 0.34),
                self.fxRng.range(0.015, 0.032),
                0.002,
                SPARK,
                6.0,
            );
        }
    }
    /// BOTH FEET SETTING as a stroke is thrown — the visible half of the commit tell. Off the FEET rather
    /// than the kit: a giant swings by planting, and dust on the ground is legible from every angle a
    /// five-metre stroke foreshortens to nothing in.
    fn plantBurst(self: *Knight) void {
        const f = self.fdir();
        for ([_]f32{ -1, 1 }) |side| {
            const rr = 0.40 * self.scale;
            const at = v3(self.pos.x - f.z * side * rr, self.pos.y + 0.05, self.pos.z + f.x * side * rr);
            self.dustBurst(at, 10, 2.1, 0.22);
        }
    }
    /// THE BODY MEETING THE EARTH — a wall of dust down the whole strip he has just filled, not a puff at his
    /// feet: what has to read is the LENGTH of what landed on you.
    fn slamGround(self: *Knight) void {
        const back = mathx.scaleV(self.fdir(), -1);
        const mid = v3(self.pos.x + back.x * 0.55 * FALL_LEN * self.scale, self.pos.y, self.pos.z + back.z * 0.55 * FALL_LEN * self.scale);
        const from = self.fxHead;
        self.dustBurst(mid, 48, 5.8, 0.52);
        self.grit(mid, 20);
        foe.floorBurst(&self.parts, from, self.fxHead, self.pos.y);
        sfx.world(.ogre_slam, mid);
    }
    /// **THE DISC IS DRAWN BEFORE IT IS BILLED** (owner: bad indication of its AoE). The slam had no ground
    /// tell at all — the only thing marking where a metre-and-a-quarter disc was about to land was dust
    /// AFTER it landed, which is a report and not a warning. The blow's own circle is walked during the
    /// WIND, one mote at a time round the circumference, thickening as the haul climbs: the player is shown
    /// the ring he has to be out of while there is still time to leave it. It reads `slamMark` and `SLAM.r`,
    /// the same two the blow and the crater do, so the picture can never promise a smaller circle than the
    /// mechanic bills — and it is EMBER rather than dust, because tan on tan is what made the crater
    /// unreadable and a warning that cannot be seen is not a warning.
    fn slamRingTell(self: *Knight, dt: f32) void {
        const k = mathx.clampF(self.t / SLAM.windDur, 0, 1);
        self.ringAccum += (10.0 + 52.0 * k) * dt;
        const at = self.slamMark();
        const reach = SLAM.r * self.scale;
        while (self.ringAccum >= 1.0) {
            self.ringAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = reach * self.fxRng.range(0.94, 1.04);
            self.emit(
                v3(at.x + mathx.cosf(a) * rr, self.pos.y + 0.04, at.z + mathx.sinf(a) * rr),
                v3(0, self.fxRng.range(0.5, 1.6) * (0.4 + k), 0),
                self.fxRng.range(0.30, 0.55),
                self.fxRng.range(0.030, 0.062) * self.scale,
                0.010,
                EMBER_MARK,
                0.9,
            );
        }
    }

    /// THE SLAM'S CRATER, drawn by the dust itself: motes thrown OUTWARD from where the door landed, their
    /// speed solved so the front arrives at the blow's true radius inside its own life — the picture and the
    /// blow share `SLAM.r` and `slamMark`, so the FX cannot promise a smaller ring than the mechanic bills.
    fn slamCrater(self: *Knight) void {
        const at = self.slamMark();
        const reach = SLAM.r * self.scale;
        var i: i32 = 0;
        // Emitted DENSE and finishing BIG: dust is tan on tan ground (the delver's colour lesson, the other
        // way round), so what makes the ring read is the count and the billow, not the hue.
        while (i < 44) : (i += 1) {
            const a = self.fxRng.angle();
            const life = self.fxRng.range(0.40, 0.62);
            const sp = reach / life * self.fxRng.range(0.75, 1.0);
            self.emit(
                v3(at.x + mathx.cosf(a) * 0.4 * self.scale, self.pos.y + 0.10, at.z + mathx.sinf(a) * 0.4 * self.scale),
                v3(mathx.cosf(a) * sp, self.fxRng.range(0.5, 1.7), mathx.sinf(a) * sp),
                life,
                self.fxRng.range(0.11, 0.19) * self.scale,
                0.42 * self.fxRng.range(0.8, 1.3) * self.scale,
                DUST,
                4.2,
            );
        }
        self.grit(at, 18);
        sfx.world(.ogre_slam, at);
    }
    /// The dust the charge PLOUGHS up — a wake off the heels, thin and continuous, so the travel reads as
    /// mass moving earth rather than a mesh sliding.
    fn chargeWake(self: *Knight, dt: f32) void {
        self.fxAccum += 46.0 * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const back = mathx.scaleV(self.fdir(), -1);
            const side = self.fxRng.signed() * 0.45 * self.scale;
            // LOFTED, or the puffs settle onto the floor plane and read as stains rather than a wake.
            self.emit(
                v3(self.pos.x + back.x * 0.5 * self.scale - back.z * side, self.pos.y + 0.18, self.pos.z + back.z * 0.5 * self.scale + back.x * side),
                v3(back.x * self.fxRng.range(1.2, 2.8) * self.scale, self.fxRng.range(1.6, 3.4), back.z * self.fxRng.range(1.2, 2.8) * self.scale),
                self.fxRng.range(0.34, 0.60),
                self.fxRng.range(0.08, 0.15) * self.scale,
                0.34 * self.fxRng.range(0.8, 1.2) * self.scale,
                DUST,
                2.2,
            );
        }
    }
    /// **THE GATHER SAYS WHAT THE MOVE IS WORTH** (owner: light and heavy, I can't tell the difference).
    /// Every wind used to throw the same dust at the same rate, so the only thing separating a 22-damage
    /// poke from a 40-damage crusher was how long it took — which is a difference you cannot see while it is
    /// happening. `w` is the move's declared `Weight`, and it buys FIRE: nothing on a light, a rim of ember
    /// on a heavy, a full column on a crusher. One rule for the player to learn, and it covers the whole kit.
    fn emitGather(self: *Knight, dt: f32, k: f32, w: Weight) void {
        self.fxAccum += (6.0 + 28.0 * k) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.2, 0.8) * self.scale;
            self.emit(
                v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.05, self.pos.z + mathx.sinf(a) * rr),
                v3(self.fxRng.signed() * 0.5, self.fxRng.range(0.3, 1.4), self.fxRng.signed() * 0.5),
                self.fxRng.range(0.28, 0.52),
                self.fxRng.range(0.035, 0.08) * self.scale,
                0.014,
                DUST,
                3.2,
            );
        }
        // …AND THE FIRE, which is the part that is actually legible at five metres in his own shadow. It
        // RISES off the ground round his boots and thickens as the gather loads, so it says both "this one
        // is heavy" and "it is nearly here" — the two things the player has to know before it lands.
        // **AND IT HAS TO BE DENSE ENOUGH TO BE A COLUMN.** First pass emitted about fifteen motes spread
        // over a three-metre ring and the shot came back with a single orange dot beside his boot — a tell
        // nobody can see is not a tell. Rate up hard, radius pulled IN so they read as one rising body of
        // fire rather than a scatter, and the life long enough that they overlap.
        const fire = w.ember();
        if (fire <= 0) return;
        self.emberAccum += (14.0 + 78.0 * k) * fire * dt;
        while (self.emberAccum >= 1.0) {
            self.emberAccum -= 1.0;
            const a = self.fxRng.angle();
            // **WIDER THAN THE DOOR, because the player is standing in front of it.** Pulled in tight the
            // fire rose entirely behind four and a half metres of shield and could only be seen from the
            // one bearing the fight is never fought from. The ring now straddles the door's own chord, so
            // there is flame either side of his silhouette from square on.
            const rr = self.fxRng.range(0.52, 1.18) * self.scale;
            self.emit(
                v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.04, self.pos.z + mathx.sinf(a) * rr),
                v3(self.fxRng.signed() * 0.2, self.fxRng.range(2.2, 5.4) * (0.6 + 0.6 * fire), self.fxRng.signed() * 0.2),
                self.fxRng.range(0.46, 0.86),
                self.fxRng.range(0.038, 0.082) * self.scale * (0.7 + 0.5 * fire),
                0.010,
                EMBER_MARK,
                -0.7, // it RISES: fire is the one thing here that does not fall (the elements' own law)
            );
        }
    }
    fn footfalls(self: *Knight) void {
        if (self.moving < 0.4 or self.staggered()) {
            self.prevPhase = self.phase;
            return;
        }
        const crossed = (self.prevPhase < 0.5 and self.phase >= 0.5) or (self.phase < self.prevPhase);
        self.prevPhase = self.phase;
        if (!crossed) return;
        const side: f32 = if (self.phase < 0.5) 1.0 else -1.0;
        const f = self.fdir();
        const rr = 0.13 * H * self.scale;
        const at = v3(self.pos.x - f.z * side * rr, self.pos.y + 0.05, self.pos.z + f.x * side * rr);
        self.dustBurst(at, 9, 1.7, 0.19);
        // FIVE METRES OF ARMOUR WALKING IS FELT, faintly, every footfall — the cheapest thing on the list
        // that says how heavy he is, and it runs the whole fight rather than once a minute.
        self.quake = mathx.maxF(self.quake, QUAKE_STEP);
        sfx.world(.ogre_step, at);
    }
    pub fn drawFx(self: *const Knight) void {
        foe.drawParticles(&self.parts);
        self.trail.draw(TRAIL_LIFE, foe.WAKE, TRAIL_PEAK);
    }

    pub fn draw(self: *const Knight, model: *const Model) void {
        model.draw(self);
    }
};

const CAP = wf.MAX_PER_KIND;

/// THE VIGIL — what is left standing watch over the fallen city.
pub const Vigil = struct {
    model: Model,
    knights: [CAP]Knight = undefined,
    n: usize = 0,
    /// THE FIELD'S CHAOS GAS — the group's, not the knight's, because a cloud has to keep burning after the
    /// body that laid it has fallen over. Ring-buffered like the sporeling's clouds: the oldest goes.
    gas: [GAS_CAP]Gas = [_]Gas{.{}} ** GAS_CAP,
    gasHead: usize = 0,
    /// …and ONE dose clock for the whole field (see `GAS_DOSE_EVERY`).
    gasT: f32 = 0,

    pub fn init(shader: rl.Shader) Vigil {
        return .{ .model = Model.init(shader) };
    }
    /// The knights this map posted — never iterate the whole array, the tail is `undefined`.
    pub fn live(self: *Vigil) []Knight {
        return self.knights[0..self.n];
    }
    pub fn liveConst(self: *const Vigil) []const Knight {
        return self.knights[0..self.n];
    }
    pub fn reset(self: *Vigil, m: *const wf.Map) void {
        self.clearGas();
        foe.resetGroup(Knight, &self.knights, &self.n, m, .bone_knight);
    }
    /// EMPTY THE FIELD — the members AND the gas (`shroom.Cluster.clear`'s rule: a clear that swept only the
    /// extras left the hazard burning in an empty arena, and at a bonfire).
    pub fn clear(self: *Vigil) void {
        self.n = 0;
        self.clearGas();
    }
    fn clearGas(self: *Vigil) void {
        for (&self.gas) |*g| g.* = .{};
        self.gasHead = 0;
        self.gasT = 0;
    }
    fn spawnGas(self: *Vigil, at: rl.Vector3, scale: f32) void {
        self.gas[self.gasHead] = .{
            .pos = at,
            .scale = scale,
            .live = true,
            .fxRng = foe.fxStream(at.x + at.z, 641.0, 0x6A50),
        };
        self.gasHead = (self.gasHead + 1) % GAS_CAP;
    }
    /// WHAT STANDING IN IT COSTS, asked once a frame after the update. Null outside every cloud, and null
    /// between doses — `GAS_DOSE_EVERY` is what keeps a damaging hazard from being sixty hurt beats a second.
    pub fn gasDose(self: *Vigil, dt: f32, hero: rl.Vector3) ?foe.Blow {
        var inIt: ?rl.Vector3 = null;
        for (&self.gas) |*g| {
            if (g.covers(hero)) inIt = g.pos;
        }
        const at = inIt orelse {
            // Stepping out RE-ARMS it, so walking through a cloud's edge is never a free crossing and the
            // next one you stand in bites on its own schedule rather than inheriting the last one's.
            self.gasT = 0;
            return null;
        };
        self.gasT += dt;
        if (self.gasT < GAS_DOSE_EVERY) return null;
        self.gasT -= GAS_DOSE_EVERY;
        return .{ .hit = GAS_HIT, .from = at, .on = .hero };
    }
    pub fn fuming(self: *const Vigil, hero: rl.Vector3) bool {
        for (&self.gas) |*g| {
            if (g.covers(hero)) return true;
        }
        return false;
    }
    pub fn setShader(self: *Vigil, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Vigil, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Vigil) bool {
        return foe.anyParried(self.liveConst());
    }
    /// THE GROUND SHOOK — the worst of this frame's quakes (a one-frame magnitude, like `justDied`): the
    /// fall landing, the stomp, the charge slamming to its stop. The game turns it into shake + rumble, so
    /// the moves that move the EARTH are felt even when they missed.
    pub fn quakeAmt(self: *const Vigil) f32 {
        var q: f32 = 0;
        for (self.liveConst()) |*k| q = mathx.maxF(q, k.quake);
        return q;
    }
    /// THE BOSS ON THIS FIELD, if a fight with one is on: the first knight that is fighting and still
    /// standing on it — an INDEX, so the caller can also name him to the floating-bar pass. `alive()` holds
    /// through the death collapse on purpose: the bar drains and lingers over the body going to gold, and
    /// leaves the screen with it.
    pub fn boss(self: *const Vigil, hero: rl.Vector3) ?usize {
        for (self.liveConst(), 0..) |*k, i| {
            if (!k.alive()) continue;
            if (k.leash.roused() or mathx.distXZ(k.pos, hero) <= AGGRO_R) return i;
        }
        return null;
    }
    pub fn update(self: *Vigil, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        const blow = foe.groupBlow(self.live(), dt, hero, bounds, blade);
        for (self.live()) |*k| {
            if (k.gasAt) |at| self.spawnGas(at, k.scale);
        }
        for (&self.gas) |*g| g.update(dt);
        return blow;
    }
    pub fn draw(self: *const Vigil, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Vigil) void {
        for (self.liveConst()) |*k| k.drawFx();
        for (&self.gas) |*g| g.drawFx();
    }
    pub fn pierce(self: *Vigil, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Vigil) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Vigil) u32 {
        return foe.soulsDropped(self.liveConst(), SOULS);
    }
    pub fn totalHits(self: *const Vigil) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Vigil) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

// Plate over old bone. `addBox`/`addCube` is right here — this is iron, and the round-mass law is about
// FLESH — but a cuirass is still the biggest sunward face in the game, so it is near-black and what breaks
// it up is fluting and rivets rather than a lighter tone.

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = cuirassMesh();
    mesh[NECK] = gorgetMesh();
    mesh[SKULL] = helmMesh();
    mesh[HIPL] = thighMesh(1.0, 311);
    mesh[KNEEL] = shinMesh(312);
    mesh[ANKL] = footMesh(1.0);
    mesh[HIPR] = thighMesh(-1.0, 314);
    mesh[KNEER] = shinMesh(315);
    mesh[ANKR] = footMesh(-1.0);
    mesh[SHL] = upperArmMesh(1.0, 0.98);
    mesh[ELL] = forearmMesh(1.0, 0.98);
    mesh[WRL] = gauntletMesh(true);
    mesh[SHR] = upperArmMesh(-1.0, 1.06); // the sword arm carries the heavier plate
    mesh[ELR] = forearmMesh(-1.0, 1.06);
    mesh[WRR] = gauntletMesh(false);
    mesh[WPN] = swordMesh();
    return mesh;
}

/// A FEW POINTS OF VALUE EITHER SIDE OF ONE TONE — hammer marks, not a second colour. This is what keeps a
/// wall of bands one substance instead of a barber's pole (see `shieldMesh`).
fn shade(c: rl.Color, d: f32) rl.Color {
    return rgba(
        mathx.u8f(mathx.clampF(@as(f32, @floatFromInt(c.r)) + d, 0, 255)),
        mathx.u8f(mathx.clampF(@as(f32, @floatFromInt(c.g)) + d, 0, 255)),
        mathx.u8f(mathx.clampF(@as(f32, @floatFromInt(c.b)) + d, 0, 255)),
        c.a,
    );
}


// (The suit is SEALED now — the old bone-shaft-in-the-gap helper is gone with the gaps. The one bone note
// left is the jaw under the helm; the rest of what says "Bone Knight" is the resist sheet and the name.)

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4201);
    b.setMat(PLATE);
    // THE WAIST HAS A CORE, and it is the masonry law on a body: the faulds and the belt are only the FACING,
    // and a hoop of leather round nothing is a hoop you see the sunlit inside of. It is a CLOSED box (an
    // `addCylinder` here is one more open cut-pipe end) sized just inside the belt's 0.140·H, and it overlaps
    // well past both the top lame below it and the cuirass above.
    b.addRoundBox(v3(0, 0.036 * H, 0), v3(0.216 * H, 0.150 * H, 0.180 * H), 0.048 * H, 3, 11, IRON_DK);
    // THE SKIRT: one smooth flared bell under the belt and SEVEN long tassets hanging round it, each its
    // own length with a slight outward cant. The old four stacked, lipped lames read as a barrel — the
    // statue reads through FEWER, LONGER masses, and the wabi lives between the plates.
    b.addCylinder(v3(0, -0.006 * H, 0), v3(0, -0.075 * H, 0), 0.128 * H, 0.140 * H, 12, IRON_DK);
    // **AND THE HEM IS RAGGED.** At 0.072-0.108 they all ended within a few centimetres of each other and the
    // skirt read as one box with a straight bottom edge — the flattest line on the creature, and the one the
    // eye uses to decide whether a thing was moulded in a press. The lengths now genuinely differ, one plate
    // is half torn away, and each hangs at its own cant.
    var i: usize = 0;
    while (i < 7) : (i += 1) {
        const a = (@as(f32, @floatFromInt(i)) + 0.5) / 7.0 * std.math.tau;
        const rr = 0.136 * H;
        const torn = i == 4;
        const len = if (torn) 0.038 * H else rng.range(0.062, 0.148) * H;
        const outw = v3(mathx.cosf(a), 0, mathx.sinf(a));
        const tang = v3(-mathx.sinf(a), 0, mathx.cosf(a));
        const cant = rng.range(-0.020, 0.026) * H;
        b.addBox(
            v3(outw.x * rr, -0.078 * H - len * 0.5, outw.z * rr),
            mathx.scaleV(tang, rng.range(0.046, 0.064) * H),
            v3(outw.x * (0.014 * H + cant), len * 0.5, outw.z * (0.014 * H + cant)),
            mathx.scaleV(outw, 0.009 * H),
            switch (i % 3) {
                0 => IRON,
                1 => IRON_MD,
                else => IRON_DK,
            },
        );
    }
    // THE BONE SHOWS WHERE THE PLATE HAS GONE (owner: more skeletal). One femur head standing in the gap the
    // torn tasset leaves — a single large mass at a joint the suit genuinely opens at, which is the placement
    // rule the first bone pass broke by scattering flecks over sealed plate.
    b.addBlob(v3(mathx.cosf(4.5 / 7.0 * std.math.tau) * 0.118 * H, -0.128 * H, mathx.sinf(4.5 / 7.0 * std.math.tau) * 0.118 * H), v3(0.030 * H, 0.052 * H, 0.028 * H), 6, 10, KBONE);
    b.setMat(.leather);
    // A BELT GOES ROUND HIM, SO ITS AXIS IS VERTICAL. Authored across his hips instead it was a 1.5 m drum
    // wider than it was long, and its two flat caps — sunlit, and the only warm thing on a blue-black
    // creature — filled his whole BACK: the one side of him the fight is about. Radius over the faulds'
    // 0.132·H so the band sits proud of the skirt, and 11 sides to match theirs.
    b.addCylinder(v3(0, 0.034 * H, 0), v3(0, 0.078 * H, 0), 0.140 * H, 0.140 * H, 11, STRAP);
    b.setMat(BRIGHT);
    b.addBox(v3(0, 0.056 * H, 0.138 * H), v3(0.036 * H, 0, 0), v3(0, 0.030 * H, 0), v3(0, 0, 0.010 * H), BRASS); // the buckle
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4229);
    b.setMat(PLATE);
    // THE SUIT IS SEALED (the Sentinel ref: a statue, not a corpse with gaps): one smooth waist column
    // where the spine bones used to show, overlapping the pelvis core below and the cuirass ribs above.
    b.addRoundBox(v3(0, 0.056 * H, -0.008 * H), v3(0.190 * H, 0.150 * H, 0.164 * H), 0.055 * H, 3, 11, IRON_DK);
    // A short mail skirt over the gap, hanging in strips rather than as one bib.
    for ([_]f32{ -0.070, -0.024, 0.024, 0.070 }) |sx| {
        b.addBox(
            v3(sx * H, 0.048 * H, 0.062 * H * rng.range(0.9, 1.05)),
            v3(0.024 * H, 0, 0),
            v3(rng.range(-0.006, 0.006) * H, 0.058 * H, 0),
            v3(0, 0, 0.007 * H),
            if (rng.float() < 0.3) RUST else IRON_DK,
        );
    }
    return b.toMesh();
}

/// THE CUIRASS — the biggest single face on the creature. Near-black, fluted, and BROKEN: a raised medial
/// ridge, a rolled neck line, rivets down the sides, and one pauldron riding proud of each shoulder.
/// THE CUIRASS'S OWN BOX, named because the DOOR is measured against its front face and a hand-derived
/// `0.208/2 − 0.006` at the test site is a number that silently stops describing his chest the first time the
/// breastplate is re-authored. `addRoundBox` takes a FULL size (`addCube`'s rule), hence the halving.
const CUIRASS_C = v3(0, 0.016 * H, -0.006 * H);
const CUIRASS_SIZE = v3(0.318 * H, 0.176 * H, 0.208 * H);
/// …and where the front of him actually is, in the CHEST bone's own frame.
pub const CHEST_FRONT_Z = CUIRASS_C.z + CUIRASS_SIZE.z * 0.5;

fn cuirassMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4243);
    b.setMat(PLATE);
    // THE BARREL: one big rounded mass with a deep corner radius — the statue's chest, form over greeble.
    b.addRoundBox(CUIRASS_C, CUIRASS_SIZE, 0.072 * H, 4, 12, IRON);
    // **AND IT NARROWS TO THE WAIST.** A chest as wide at the belt as at the shoulders is a BOX, and a box
    // with rounded corners is the lego man exactly: no taper anywhere, so no form anywhere. Two courses
    // stepping in under the ribs give the one line the whole torso is read off.
    b.addRoundBox(v3(0, -0.050 * H, 0.004 * H), v3(0.258 * H, 0.084 * H, 0.184 * H), 0.056 * H, 3, 11, IRON_MD);
    b.addRoundBox(v3(0, -0.092 * H, 0.006 * H), v3(0.206 * H, 0.060 * H, 0.158 * H), 0.048 * H, 3, 11, IRON_DK);
    // THE RIBCAGE, IN THE PLATE ITSELF (owner: more skeletal). Not bones bolted on — that is the litter that
    // got bone deleted from him last time — but the breastplate FORGED as a ribcage: paired courses sweeping
    // down and out from the medial ridge, each sunk into shadow at its lower edge, so the chest reads as a
    // ribbed thing under raking light and as one smooth statue mass in silhouette. Uneven, because a rib
    // cage is, and because a regular one is the corduroy this was rejected as before.
    for ([_]usize{ 0, 1, 2, 3 }) |ri| {
        const fy = 0.086 * H - @as(f32, @floatFromInt(ri)) * 0.036 * H;
        const spanX = (0.104 + 0.016 * @as(f32, @floatFromInt(ri))) * H;
        for ([_]f32{ -1, 1 }) |sx| {
            const drop = rng.range(0.010, 0.026) * H;
            b.addCapsule(
                v3(sx * 0.014 * H, fy + rng.range(-0.004, 0.004) * H, 0.100 * H),
                v3(sx * spanX, fy - drop, 0.074 * H),
                rng.range(0.013, 0.018) * H,
                rng.range(0.009, 0.013) * H,
                8,
                IRON_MD,
            );
            // …and the shadow under each, which is what actually makes a rib read as a rib.
            b.addCapsule(
                v3(sx * 0.014 * H, fy - drop * 0.9, 0.096 * H),
                v3(sx * spanX * 0.96, fy - drop * 1.8, 0.070 * H),
                0.010 * H,
                0.007 * H,
                7,
                IRON_DK,
            );
        }
    }
    // THE MEDIAL RIDGE — the sternum the ribs run off, and now it has something to be the middle of.
    b.addBox(v3(0, 0.020 * H, 0.106 * H), v3(0.020 * H, 0, 0), v3(0, 0.150 * H, 0), v3(0, 0, 0.016 * H), IRON_LT);
    // THE PAULDRONS, on the chest rather than the arm so a stroke cannot swing them off the shoulder —
    // and each is ONE SMOOTH MASS, a dome over a blob: the Sentinel reads as statuary because its shoulders
    // are boulders, not boxes. The sword side is bigger; asymmetry is the point.
    // **AND THE TWO ARE NOT TWINS.** At 1.12 against 1.0 they read as a matched pair on a symmetric box,
    // which is half of why he was a toy: the eye finds bilateral symmetry instantly and calls it moulded.
    // The sword shoulder is markedly the heavier and rides lower and further back; the shield shoulder is
    // tucked up under the door it carries. Cosmetic only — the mechanics measure off `SHOULDER_HALF`.
    for ([_]f32{ 1, -1 }) |side| {
        const sword = side < 0;
        const big: f32 = if (sword) 1.26 else 0.92;
        const reach: f32 = if (sword) 1.02 else 0.94;
        const tilt: f32 = if (sword) 0.38 else 0.16;
        const sx = side * SHOULDER_HALF * H * reach;
        const sy: f32 = if (sword) 0.034 * H else 0.062 * H;
        // **THE CAP IS THE LIT SIDE.** Authored in `IRON_DK` it was fine against the old mid-grey plate and
        // became a black hole the moment the field went near-black — two dark craters where the shoulders
        // should be, which is most of what still read as amateurish. The dome catches the sky, the blob
        // under it is the mass, and the dark belongs UNDERNEATH.
        b.addBlob(v3(sx, sy, -0.006 * H), v3(0.116 * H * big, 0.086 * H * big, 0.148 * H * big), 7, 12, IRON);
        b.addDome(v3(sx, sy + 0.044 * H, -0.006 * H), v3(side * tilt, 1.0, 0), 0.092 * H * big, 12, IRON_MD);
        b.addBlob(v3(sx, sy - 0.052 * H, -0.006 * H), v3(0.104 * H * big, 0.040 * H * big, 0.132 * H * big), 6, 11, IRON_DK);
        // The lame hanging off the heavier one, and nothing off the other — a suit repaired, not moulded.
        if (sword) {
            b.addBox(
                v3(sx * 1.06, sy - 0.072 * H, -0.004 * H),
                v3(0.062 * H, 0, 0),
                v3(0.010 * H, 0.046 * H, 0),
                v3(0, 0, 0.078 * H),
                IRON_MD,
            );
        }
    }
    // …and everything PROUD of the plate is where the metal is allowed to glint.
    b.setMat(BRIGHT);
    b.addCylinder(v3(0, 0.176 * H, -0.006 * H), v3(0, 0.190 * H, -0.006 * H), 0.106 * H, 0.094 * H, 11, IRON_LT); // the neck's rolled rim
    for ([_]f32{ 1, -1 }) |side| {
        const big: f32 = if (side < 0) 1.10 else 1.0;
        const sx = side * SHOULDER_HALF * H;
        b.addCapsule(
            v3(sx * 0.60, 0.108 * H, 0.030 * H),
            v3(sx * 1.30, 0.078 * H, 0.010 * H),
            0.020 * H * big,
            0.016 * H * big,
            8,
            IRON_LT,
        ); // the rolled crest along it
    }
    // …and the brass fittings go back to PLATE. Under `BRIGHT` a pair of warm studs at shoulder height read
    // as two lit eyes on the front of him — the one thing on this creature that is supposed to be a light is
    // the ember down the visor, and nothing else may compete with it.
    b.setMat(PLATE);
    for ([_]f32{ 1, -1 }) |side| {
        const sx = side * SHOULDER_HALF * H;
        b.addBlob(v3(sx * 1.02, -0.010 * H, 0.048 * H), v3(0.022 * H, 0.022 * H, 0.018 * H), 5, 9, if (side < 0) RUST else BRASS);
    }
    b.setMat(BRIGHT);
    var r: i32 = 0;
    while (r < 10) : (r += 1) {
        const a = rng.angle();
        const yy = rng.range(-0.10, 0.14) * H;
        const rr = 0.300 * H;
        b.addBlob(
            v3(mathx.cosf(a) * rr, yy, mathx.sinf(a) * rr * 0.68 - 0.006 * H),
            v3(0.011 * H, 0.011 * H, 0.011 * H),
            4,
            8,
            if (rng.float() < 0.35) RUST else IRON_LT,
        ); // rivets
    }
    // **THE SUIT HAS BEEN WORN, NOT MOULDED** (owner: more wabi-sabi and interesting). A sealed mass with a
    // few tidy rivets is a casting; what says a thing has stood in a field for a century is DAMAGE, and it
    // has to be asymmetric or it is pattern. Four dents, none of them mirrored, sunk most of the way in
    // (relief is subtle) and each with its own bright torn rim where the metal folded.
    b.setMat(PLATE);
    for ([_]struct { x: f32, y: f32, s: f32 }{
        .{ .x = -0.086, .y = 0.062, .s = 1.20 },
        .{ .x = 0.104, .y = -0.014, .s = 0.85 },
        .{ .x = -0.032, .y = -0.070, .s = 1.05 },
        .{ .x = 0.062, .y = 0.096, .s = 0.70 },
    }) |d| {
        const w = 0.030 * H * d.s;
        b.addBlob(v3(d.x * H, d.y * H, 0.098 * H), v3(w, w * rng.range(0.6, 1.1), 0.012 * H), 6, 10, IRON_DK);
        b.setMat(BRIGHT);
        b.addCapsule(
            v3(d.x * H - w, d.y * H + w * 0.5, 0.104 * H),
            v3(d.x * H + w * rng.range(0.7, 1.2), d.y * H + w * rng.range(-0.4, 0.8), 0.104 * H),
            0.005 * H,
            0.004 * H,
            6,
            IRON_LT,
        ); // the torn lip where the plate folded
        b.setMat(PLATE);
    }
    // …and ONE GOUGE that went through, with old bone showing in it. The whole of why he is the BONE Knight
    // to look at, placed where the plate genuinely failed rather than scattered over a sealed suit.
    b.addBlob(v3(-0.118 * H, 0.028 * H, 0.088 * H), v3(0.026 * H, 0.044 * H, 0.026 * H), 6, 10, SOCKET);
    b.addBlob(v3(-0.118 * H, 0.030 * H, 0.082 * H), v3(0.015 * H, 0.030 * H, 0.014 * H), 5, 9, KBONE);
    return b.toMesh();
}

fn gorgetMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    b.addCylinder(v3(0, -0.006 * H, 0), v3(0, 0.052 * H, 0), 0.040 * H, 0.036 * H, 8, BONE_DK); // the vertebrae inside
    b.addCylinder(v3(0, 0.002 * H, -0.002 * H), v3(0, 0.048 * H, -0.002 * H), 0.070 * H, 0.062 * H, 11, IRON);
    b.setMat(BRIGHT);
    b.addCylinder(v3(0, 0.048 * H, -0.002 * H), v3(0, 0.058 * H, -0.002 * H), 0.066 * H, 0.058 * H, 11, IRON_LT);
    return b.toMesh();
}

/// THE GREAT HELM — ONE SMOOTH SKULL of iron (the statue's head, deliberately small over the pauldrons: a
/// small head is what makes the body read giant), a rolled brow, one narrow slit, and a cold ember behind
/// it — the only part of the creature that reads at night or in its own shadow. The jaw of the old skull
/// still shows below the rim: the one bone note left on a sealed suit, and the whole of why he is the BONE
/// Knight to look at.
fn helmMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4271);
    b.setMat(PLATE);
    // The shell: a single tall ovoid with a domed crown — no box under it, nothing to read as corners.
    b.addBlob(v3(0, 0.018 * H, 0.002 * H), v3(0.048 * H, 0.066 * H, 0.053 * H), 8, 14, IRON);
    b.addDome(v3(0, 0.058 * H, 0.000 * H), v3(0, 1, 0), 0.047 * H, 12, IRON_DK);
    // **AND THE HELM IS SHAPED AS A SKULL, NOT A HELMET WITH A SLOT** (owner: more skeletal and scary). One
    // narrow letterbox on a smooth egg is a mail-slot: at any distance it reads as a bucket. A skull reads by
    // TWO DEEP SOCKETS with a nasal between them and a brow overhanging both, so that is what is cut into the
    // face — and the ember burns in each socket rather than smearing across a slit, which is what makes a
    // head at five metres look back at you.
    for ([_]f32{ -1, 1 }) |sx| {
        const ox = sx * 0.021 * H;
        const oy = 0.026 * H + sx * 0.002 * H; // uneven: nothing on him is symmetric
        b.addBlob(v3(ox, oy, 0.041 * H), v3(0.016 * H, 0.015 * H, 0.014 * H), 6, 10, SOCKET);
        b.addBlob(v3(ox, oy, 0.045 * H), v3(0.010 * H, 0.009 * H, 0.006 * H), 5, 9, EMBER);
    }
    // The nasal between them, and the deep triangular void under it where a nose would not be.
    b.addCapsule(v3(0, 0.046 * H, 0.045 * H), v3(0, 0.008 * H, 0.048 * H), 0.008 * H, 0.006 * H, 7, IRON_MD);
    b.addBlob(v3(0, 0.004 * H, 0.043 * H), v3(0.009 * H, 0.011 * H, 0.008 * H), 5, 9, SOCKET);
    // The cheekbones: the one piece of relief that turns an egg into a face.
    for ([_]f32{ -1, 1 }) |sx| {
        b.addCapsule(
            v3(sx * 0.012 * H, 0.012 * H, 0.046 * H),
            v3(sx * 0.044 * H, 0.022 * H, 0.026 * H),
            0.010 * H,
            0.007 * H,
            7,
            IRON_MD,
        );
    }
    // Three breaths cut low on the face, uneven.
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const y = -0.016 * H - @as(f32, @floatFromInt(i)) * 0.011 * H;
        const w = rng.range(0.014, 0.026) * H;
        b.addBox(v3(rng.range(-0.008, 0.008) * H, y, 0.044 * H), v3(w, 0, 0), v3(0, 0.003 * H, 0), v3(0, 0, 0.006 * H), SOCKET);
    }
    // The comb: one smooth low ridge fore-to-aft, swelling at the rear — a statue's crown, not a fin, and
    // NOTHING ENDS IN A POINT.
    b.addCapsule(v3(0, 0.074 * H, 0.028 * H), v3(0, 0.086 * H, -0.036 * H), 0.014 * H, 0.019 * H, 9, IRON_DK);
    b.setMat(BRIGHT);
    b.addCapsule(v3(-0.046 * H, 0.040 * H, 0.036 * H), v3(0.046 * H, 0.040 * H, 0.036 * H), 0.011 * H, 0.009 * H, 8, IRON_LT); // the brow, rolled
    b.setMat(PLATE);
    // THE JAW UNDER THE RIM — his own bone (`KBONE`), not the archer's: at 237 of 255 this one mass was the
    // brightest thing on the whole creature and read as a bandage.
    b.addBox(v3(0, -0.046 * H, 0.036 * H), v3(0.036 * H, 0, 0), v3(0, 0.014 * H, 0), v3(0, 0, 0.030 * H), KBONE); // the jaw, showing
    b.addBlob(v3(-0.032 * H, -0.044 * H, 0.020 * H), v3(0.011 * H, 0.014 * H, 0.012 * H), 5, 9, KBONE_LT);
    b.addBlob(v3(0.031 * H, -0.047 * H, 0.018 * H), v3(0.010 * H, 0.013 * H, 0.011 * H), 5, 9, KBONE_DK); // and uneven either side
    // …and the TEETH under it, which is the whole difference between a chin-guard and a skull.
    for ([_]i32{ 0, 1, 2, 3, 4 }) |ti| {
        const tx = (-0.026 + 0.013 * @as(f32, @floatFromInt(ti))) * H;
        b.addBox(
            v3(tx + rng.range(-0.002, 0.002) * H, -0.038 * H, 0.049 * H),
            v3(0.0045 * H, 0, 0),
            v3(0, rng.range(0.006, 0.011) * H, 0),
            v3(0, 0, 0.004 * H),
            if (rng.float() < 0.25) SOCKET else KBONE_LT,
        );
    }
    return b.toMesh();
}

// EVERY LIMB IS A SEALED ARMOURED COLUMN (the Sentinel ref: a statue, not a corpse with gaps). Each plate
// course OVERLAPS the joint below it, so nothing pale peeks through however the joints bend — the old bone
// shafts came back off this sun at 237 of 255 and read as clutter on a blue-black mass.
fn thighMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const len = REST[HIPL].y - REST[KNEEL].y;
    b.setMat(PLATE);
    // The cuisse in two overlapping courses — a COLUMN, thick as statuary.
    b.addRoundBox(v3(side * 0.004 * H, -len * 0.24, 0.006 * H), v3(0.148 * H, len * 0.66, 0.136 * H), 0.050 * H, 3, 11, IRON);
    b.addRoundBox(v3(0, -len * 0.66, 0.008 * H), v3(0.128 * H, len * 0.54, 0.118 * H), 0.044 * H, 3, 11, shade(IRON, rng.range(-4.0, 4.0)));
    // The poleyn: one smooth boulder riding the knee, overlapping cuisse AND greave.
    b.addBlob(v3(side * 0.006 * H, -len * 0.98, 0.020 * H), v3(0.064 * H, 0.060 * H, 0.062 * H), 6, 11, IRON_DK);
    b.setMat(.leather);
    b.addCylinder(v3(0, -len * 0.44, 0), v3(0, -len * 0.44 - 0.012 * H, 0), 0.078 * H, 0.078 * H, 9, STRAP);
    return b.toMesh();
}

fn shinMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const len = REST[KNEEL].y - REST[ANKL].y;
    b.setMat(PLATE);
    // The greave: one column, flaring into a bell over the sabaton so the ankle gap is covered too.
    b.addRoundBox(v3(0, -len * 0.42, 0.006 * H), v3(0.122 * H, len * 0.74, 0.112 * H), 0.044 * H, 3, 11, shade(IRON, rng.range(-3.0, 3.0)));
    b.addCylinder(v3(0, -len * 0.82, 0.004 * H), v3(0, -len * 1.02, 0.004 * H), 0.056 * H, 0.066 * H, 11, IRON_DK);
    b.setMat(BRIGHT);
    b.addCapsule(v3(0, -len * 0.14, 0.058 * H), v3(0, -len * 0.72, 0.052 * H), 0.011 * H, 0.009 * H, 8, IRON_LT); // the shin ridge
    return b.toMesh();
}

/// THE SABATON — the footprint `solePatches` is measured off. Its underside sits on the ankle plane.
/// BIG: a statue stands on plinth feet, and underscaled boots are half of what reads as a toy.
fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4283);
    b.setMat(PLATE);
    b.addRoundBox(v3(0, -0.016 * H, 0.052 * H), v3(0.126 * H, 0.050 * H, 0.238 * H), 0.024 * H, 3, 10, IRON);
    // Overlapping lames across the toes, each a hair narrower and NOT evenly spaced.
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const z = 0.088 * H + @as(f32, @floatFromInt(i)) * 0.034 * H * rng.range(0.9, 1.12);
        b.addBox(v3(0, -0.002 * H, z), v3(0.058 * H - @as(f32, @floatFromInt(i)) * 0.005 * H, 0, 0), v3(0, 0.016 * H, 0), v3(0, 0, 0.010 * H), if (i % 2 == 0) IRON_LT else IRON_DK);
    }
    b.addBlob(v3(side * 0.044 * H, -0.002 * H, -0.034 * H), v3(0.040 * H, 0.038 * H, 0.038 * H), 5, 10, IRON_DK); // the heel
    b.setMat(BRIGHT);
    b.addCapsule(v3(0, -0.012 * H, 0.176 * H), v3(0, -0.002 * H, 0.208 * H), 0.030 * H, 0.023 * H, 8, RUST); // a blunt toe cap
    return b.toMesh();
}

fn upperArmMesh(side: f32, big: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 4297 else 4327);
    const len = REST[SHL].y - REST[ELL].y;
    b.setMat(PLATE);
    // The rerebrace: one sealed course from under the pauldron down over the elbow line…
    b.addRoundBox(v3(0, -len * 0.44, 0.004 * H), v3(0.098 * H * big, len * 0.92, 0.090 * H * big), 0.036 * H, 3, 11, shade(IRON, rng.range(-3.0, 3.0)));
    // …and the couter, a smooth boulder over the joint itself.
    b.addBlob(v3(0, -len * 0.98, 0.008 * H), v3(0.052 * H * big, 0.048 * H, 0.050 * H * big), 6, 11, IRON_DK);
    return b.toMesh();
}

fn forearmMesh(side: f32, big: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 4337 else 4349);
    const len = REST[ELL].y - REST[WRL].y;
    b.setMat(PLATE);
    // The vambrace: one sealed course, swelling toward the cuff so the wrist gap is covered by the gauntlet.
    b.addRoundBox(v3(0, -len * 0.46, 0.004 * H), v3(0.086 * H * big, len * 0.94, 0.078 * H * big), 0.032 * H, 3, 11, shade(IRON, rng.range(-3.0, 3.0)));
    b.setMat(.leather);
    b.addCylinder(v3(0, -len * 0.26, 0), v3(0, -len * 0.26 - 0.009 * H, 0), 0.052 * H * big, 0.052 * H * big, 9, STRAP);
    return b.toMesh();
}

fn gauntletMesh(off: bool) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (off) 4357 else 4363);
    b.setMat(PLATE);
    b.addRoundBox(v3(0, FIST_Y * 0.5, FIST_Z), v3(0.062 * H, 0.070 * H, 0.058 * H), 0.020 * H, 3, 10, IRON);
    b.setMat(BRIGHT);
    // Knuckle plates, uneven, blunt — no fingers ending in points.
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const x = (-0.030 + @as(f32, @floatFromInt(i)) * 0.020) * H;
        const r = rng.range(0.011, 0.016) * H;
        b.addBlob(v3(x, FIST_Y - 0.010 * H, FIST_Z + 0.036 * H), v3(r, r, r * 1.2), 5, 9, if (i % 2 == 0) IRON_LT else IRON_DK);
    }
    b.addCylinder(v3(0, FIST_Y * 0.5 + 0.070 * H, FIST_Z), v3(0, FIST_Y * 0.5 + 0.082 * H, FIST_Z), 0.058 * H, 0.050 * H, 10, IRON_LT); // the cuff
    if (off) {
        b.setMat(.leather);
        b.addCylinder(v3(-0.056 * H, FIST_Y * 0.5, FIST_Z), v3(0.056 * H, FIST_Y * 0.5, FIST_Z), 0.020 * H, 0.020 * H, 7, STRAP); // the shield strap
    }
    return b.toMesh();
}

/// HIS SWORD. A broad, tired blade — authored in the RIGHT-WRIST frame about the fist, pointing UP off the
/// grip, so `wpnFit` turns it onto the arm. The hurt segment (`SW_SEG`) reads the same numbers.
fn swordMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4373);
    const fy = FIST_Y;
    const fz = FIST_Z;
    const guardY = fy + SW_GUARD;
    const tipY = guardY + SW_BLADE;

    b.setMat(.leather);
    // The grip: two hands' worth and no more. At 0.24·H of leather below the fist the pommel hung 1.27 m
    // past his hand and read as a second stick off his hip (the logged gap).
    b.addCylinder(v3(0, fy + 0.090 * H, fz), v3(0, fy - 0.086 * H, fz), 0.019 * H, 0.019 * H, 8, STRAP);
    // …AND THE BLADE IS PLATE TOO. A glint is right on a sword and this one is three metres long: under
    // `BRIGHT` its flat came back as a white plank longer than the hero is tall. Only its EDGES glint.
    b.setMat(PLATE);
    b.addBlob(v3(0, fy - 0.100 * H, fz), v3(0.030 * H, 0.024 * H, 0.030 * H), 6, 10, IRON_LT); // the pommel
    for ([_]f32{ 1, -1 }) |side| {
        const armLen = 0.104 * H * (if (side > 0) @as(f32, 1.0) else 0.88); // uneven quillons
        b.addBox(
            v3(side * armLen * 0.5, guardY, fz),
            v3(side * armLen, 0, 0),
            v3(0, 0.014 * H, 0),
            v3(0, 0, 0.016 * H),
            IRON,
        );
        b.addCapsule(
            v3(side * armLen, guardY, fz),
            v3(side * (armLen + 0.014 * H), guardY - 0.006 * H, fz),
            0.013 * H,
            0.009 * H,
            7,
            IRON_LT,
        ); // …turning down and blunting off
    }
    b.addCylinder(v3(0, guardY, fz), v3(0, guardY + 0.034 * H, fz), 0.020 * H, 0.016 * H, 8, IRON_DK);
    // The blade in three tapering runs. `addBox` is a parallelepiped, so a taper is boxes meeting at width.
    // Fractions of the BLADE's own length, so shortening it re-spaces the runs instead of leaving a stub
    // with a full-length fuller down it.
    const seg = [_]f32{ 0.04, 0.40, 0.76, 0.96 };
    const halfW = [_]f32{ SW_HALF_W / H, SW_HALF_W / H * 0.90, SW_HALF_W / H * 0.72, SW_HALF_W / H * 0.42 };
    const halfT = [_]f32{ 0.0080, 0.0070, 0.0056, 0.0038 };
    for (0..3) |s| {
        const y0 = guardY + seg[s] * SW_BLADE;
        const y1 = guardY + seg[s + 1] * SW_BLADE;
        b.addBox(
            v3(0, (y0 + y1) * 0.5, fz),
            v3((halfW[s] + halfW[s + 1]) * 0.5 * H, 0, 0),
            v3(0, (y1 - y0) * 0.5, 0),
            v3(0, 0, halfT[s] * H),
            if (s == 1) IRON_DK else IRON,
        );
    }
    // THE FULLER IS SUNK, not stood off — only its edge breaks the flat.
    b.addBox(v3(0, guardY + 0.42 * SW_BLADE, fz), v3(0.015 * H, 0, 0), v3(0, 0.32 * SW_BLADE, 0), v3(0, 0, 0.009 * H), IRON_DK);
    // …and the GROUND EDGES either side of it, which is the one part of a blade that should catch the sun.
    b.setMat(BRIGHT);
    b.addCapsule(v3(0, guardY + seg[3] * SW_BLADE, fz), v3(0, tipY, fz), 0.017 * H, 0.005 * H, 7, IRON_LT);
    for ([_]f32{ 1, -1 }) |side| {
        b.addCapsule(
            v3(side * SW_HALF_W * 0.96, guardY + 0.06 * SW_BLADE, fz),
            v3(side * SW_HALF_W * 0.42, guardY + 0.92 * SW_BLADE, fz),
            0.005 * H,
            0.004 * H,
            5,
            IRON_LT,
        );
    }
    b.setMat(PLATE);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const y = guardY + rng.range(0.12, 0.86) * SW_BLADE;
        const side: f32 = if (rng.float() < 0.5) 1 else -1;
        b.addBox(
            v3(side * 0.044 * H, y, fz),
            v3(side * rng.range(0.010, 0.020) * H, 0, 0),
            v3(0, rng.range(0.006, 0.014) * H, 0),
            v3(0, 0, 0.010 * H),
            RUST,
        ); // notches out of the edge — nothing dead is unmarked
    }
    return b.toMesh();
}

// Authored FACE-ON: outward normal +Z at its middle, the grip at the origin, the top at +SH_TOP and the
// foot at -SH_BOT. **AND IT IS CURVED** (owner's ask: a big curved tower shield that wraps around his side):
// the face is an arc of a vertical cylinder whose axis stands BEHIND the grip, built as upright STAVES laid
// around it — a scutum at fortress scale, not a kite and not a slab. The wrap is deliberately UNEVEN about
// the grip: it runs further round his shield side than his sword side, so the left flank is visibly
// enclosed and the sword has somewhere to come round on the right.

// SIZED BETWEEN TWO FAILURES, the feedback law's: under, it is a buckler on a giant; over, it HIDES THE
// CREATURE IT EXISTS TO DEFINE — the first flat pass ran 4.0 m tall and every portrait came back as a blank
// door with nothing behind it. The curve is what buys width without slab: the CHORD spans well past his
// pauldrons both sides, and the extra iron recedes toward him instead of standing in the lens.
// …and it is GRIPPED HIGH, the way a pavise is, so it hangs from his fist rather than being balanced on it.
/// **THE DOOR IS FULL-HEIGHT** (owner: since he is tall his shield must be tall — the front may not be a
/// place to mash his legs from). It hangs from the pavise grip at his wrist: the top edge rides at his
/// chin, clear of the helm, and the foot at his ankles, clear of the turf — the Sentinel's wall, "more like
/// a wall than a shield", with no gap under it worth crawling for.
const SH_TOP = 0.150 * H; // → the top edge at ~4.7 m: his chin, and the helm stands clear of it
const SH_BOT = 0.700 * H; // → the foot at ~0.2 m: his ankles, a hand off the ground
/// The cylinder the staves lie on, and the two half-arcs they cover — a shade more round his shield side.
/// The chords these subtend are the honest coverage figures, asserted at comptime against his own
/// shoulders: sized by eye the first flat door was narrower than the man behind it.
const SH_CURVE_R = 0.46 * H;
/// **WIDENED SO THE PICTURE CAN CARRY THE MECHANIC** (owner: the shield blocks attacks beyond its
/// visual). `TOWER_ARC` is derived off these now, so the only way to buy coverage is to build door — which
/// is the right way round. At 34/30 the honest occlusion was ~35 deg either side against a mechanic
/// claiming 105; the door has to WRAP to be a wall, not just stand there being tall.
const SH_ARC_L = mathx.radians(38.0);
const SH_ARC_R = mathx.radians(34.0);
pub const SH_CHORD_L = SH_CURVE_R * @sin(mathx.radians(38.0));
pub const SH_CHORD_R = SH_CURVE_R * @sin(mathx.radians(34.0));
/// …and how deep the gentle bow folds back at the edges — a scutum's curve, not a barrel's: the TALL
/// proportion is the identity now, the curve only keeps the slab from reading as a plank.
pub const SH_SAG_L = SH_CURVE_R * (1.0 - @cos(mathx.radians(34.0)));
comptime {
    // The door must out-span the man behind it BOTH sides of the grip (owner: it does not cover enough),
    // carry a real bow, and stand TALLER THAN IT IS WIDE by a wall's proportion (owner: tall).
    std.debug.assert(SH_CHORD_R > SHOULDER_HALF * H * 1.02);
    std.debug.assert(SH_CHORD_L > SHOULDER_HALF * H * 1.08);
    std.debug.assert(SH_SAG_L > 0.05 * H);
    std.debug.assert((SH_TOP + SH_BOT) > (SH_CHORD_L + SH_CHORD_R) * 1.55);
}
/// THE RAM: the near-flat middle of the arc, which is the only part of a curved door that can actually be
/// driven INTO you — the bash's and the charge's hurt half-width. On the flat door one `SH_HALF` served the
/// mesh and the blow alike; on a wrap they honestly part company, because iron a metre back round the curve
/// cannot be what hit you. `asin(SH_RAM_HALF / BASH.reachOut)` is also what the accuracy test measures the
/// swing against.
pub const SH_RAM_HALF = SH_CURVE_R * @sin(mathx.radians(24.0));
const SH_THICK = 0.030 * H;
const SH_STAVES = 9;
/// WHERE THE DOOR'S OWN CENTRE SITS RELATIVE TO ITS GRIP — negative, because it is gripped high like a
/// pavise. Any rotation of the door has to be taken about THIS and not about the hub: the grip is up near
/// the top edge, so a pitch about it sweeps the whole face through whatever is standing behind it, which is
/// always the knight. `shieldXf` brackets the slam's pitch with it.
const SH_CENTRE_Y = (SH_TOP - SH_BOT) * 0.5;
/// How much of its own slot a stave fills, and how far the odd ones stand proud of the even. **UNDER 1, ON
/// PURPOSE**: at 1.06 the staves overlapped into one continuous sheet and the whole door sampled as a single
/// flat tone. A shield reads as planks because the joints are visible, and the joint is what the backing
/// board behind is there to be seen through.
const SH_STAVE_FILL = 0.90;
const SH_STAVE_PROUD = 0.012 * H;
/// **THE DOOR'S OWN IRON, DARKER THAN THE SUIT'S.** It faces the sun square where his chest is angled away,
/// so the same albedo comes off it half again as bright (measured: 112 against the cuirass's 84) — which is
/// how the biggest mass on the creature ended up the BRIGHTEST thing in the frame and read as one more slab
/// of the warm cliffs behind him. Solved to land near 62 on screen: below the ground, and cold.
const SH_FIELD = rgba(8, 9, 13, 255);
/// …and what the bands and the rim are, so they read as iron laid ON the field rather than more of it.
const SH_BAND = rgba(23, 26, 32, 255);
/// How far off his FIST the door rides, along his own front. It is CENTRE-GRIPPED behind a boss, not strapped
/// to the forearm, so it needs a hand's depth and no more: the fist sits behind the boss and the face is the
/// next thing along. At 0.108·H it stood 0.57 m off the hand and at 0.062·H 0.33 m — both a door carried at
/// arm's length rather than a man sheltering behind one (owner, twice). The arm coming back onto his chest
/// (`GUARD_*`) is the other and larger half of the same fix.
const SH_STANDOFF = 0.028 * H;

/// The two points on its leading FACE that the ram's swept hurt test runs between (`shieldSeg`).
/// **THEY SPAN THE WHOLE DOOR, because the whole door is what arrives.** At 0.78 of it the segment's bottom
/// measured 1.29 m off the ground against a hero whose chest is at 1.12 m and whose crown is 1.80 m — so three
/// metres of iron came at him and the hurt test clipped the top of his head (owner: the swings go right over
/// my head). The mesh reached his shins the whole time: the PICTURE was right and the mechanic disagreed with
/// it, which is the failure `stowAmt` was written for one layer up. A test pins the height as well as the
/// reach, because outward reach was measured and this never was.
const SH_LOW = v3(0, -SH_BOT, SH_THICK);
const SH_HIGH = v3(0, SH_TOP, SH_THICK);

/// A point on the arc's midline: `a` radians round the curve (+ = the wrap side), `y` up the stave,
/// `out` metres proud of the face along that stave's own normal. The ONE piece of arc arithmetic, so the
/// staves, the rims, the bands and the rivets cannot each bend a slightly different door.
fn arcAt(a: f32, y: f32, out: f32) rl.Vector3 {
    return v3(
        @sin(a) * (SH_CURVE_R + out),
        y,
        @cos(a) * (SH_CURVE_R + out) - SH_CURVE_R,
    );
}

fn shieldMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(4391);
    b.setMat(PLATE);
    // **THE BACKING BOARD, BEHIND EVERYTHING** (the packed-stone law on a shield): the staves are the FACING,
    // and without a substrate every seam between them leaks the sky behind him. Sunk most of a stave's
    // thickness back so it is never the surface, only the dark the seams open onto.
    {
        const am = (SH_ARC_L - SH_ARC_R) * 0.5;
        const halfW = SH_CURVE_R * (SH_ARC_L + SH_ARC_R) * 0.5 * 1.02;
        const n = v3(@sin(am), 0, @cos(am));
        const mid = (SH_TOP - SH_BOT) * 0.5;
        b.addBox(
            arcAt(am, mid, -SH_THICK * 0.55),
            v3(n.z * halfW, 0, -n.x * halfW),
            v3(0, (SH_TOP + SH_BOT) * 0.5 * 0.97, 0),
            v3(n.x * SH_THICK * 0.30, 0, n.z * SH_THICK * 0.30),
            IRON_DK,
        );
    }
    // THE STAVES, upright around the arc — and **THEY ARE SEPARATED, NOT BUTTED**. Overlapped by 1.06 they
    // fused into one continuous face and the door came off the render as a single flat slab at 112,107,107:
    // a fridge, not a made thing. A pavise reads as PLANKS because you can see the joints, so each stave now
    // sits a little proud of its neighbours' gaps on ALTERNATING depths, and the backing board behind shows
    // through as a dark line down every seam. The variation is still VALUE inside one iron — a second hue
    // across the biggest face in the game is a barber's pole — but it is a range that can actually be seen.
    // The bottoms are ragged, the TOP ARCHES, and the whole door TAPERS toward its foot.
    var i: usize = 0;
    while (i < SH_STAVES) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / SH_STAVES;
        const t1 = @as(f32, @floatFromInt(i + 1)) / SH_STAVES;
        const a0 = mathx.lerpF(-SH_ARC_R, SH_ARC_L, t0);
        const a1 = mathx.lerpF(-SH_ARC_R, SH_ARC_L, t1);
        const am = (a0 + a1) * 0.5;
        // **THE STAVES ARE NOT SIBLINGS** (owner: more wabi-sabi). At one width apiece with a 3-point value
        // wobble they were an extrusion with lines drawn on it. Each is now its own plank: its own width,
        // its own foot, its own depth — and the variation lives BETWEEN the staves, which is the scale the
        // house style actually calls for.
        const halfW = SH_CURVE_R * (a1 - a0) * 0.5 * SH_STAVE_FILL * rng.range(0.80, 1.16);
        const foot = -SH_BOT + rng.range(0.0, 0.075) * H; // uneven ends — a made thing, not an extrusion
        const crownDrop = @abs(am) / SH_ARC_L; // 0 at the middle, 1 at the far edge
        const top = SH_TOP - 0.050 * H * crownDrop * crownDrop;
        const mid = (top + foot) * 0.5;
        const halfH = (top - foot) * 0.5;
        const n = v3(@sin(am), 0, @cos(am));
        // Alternating depth, so the seam has a real edge to cast into rather than a painted line.
        const proud = (if (i % 2 == 0) SH_STAVE_PROUD else 0.0) + rng.range(-0.003, 0.004) * H;
        b.addBox(
            arcAt(am, mid, proud),
            v3(n.z * halfW, 0, -n.x * halfW), // the stave's own tangent
            v3(0, halfH, 0),
            v3(n.x * SH_THICK * 0.5, 0, n.z * SH_THICK * 0.5),
            shade(SH_FIELD, rng.range(-6.0, 6.0)),
        );
        // …AND ONE PLANK IS SPLIT. A century of catching greatswords does not leave nine identical boards:
        // a shallow wedge bitten out of one edge, low, where a blade would have found it.
        if (i == 6) {
            b.addBox(
                arcAt(am + (a1 - a0) * 0.34, foot + (top - foot) * 0.30, proud + 0.006 * H),
                v3(n.z * halfW * 0.42, 0, -n.x * halfW * 0.42),
                v3(0, (top - foot) * 0.11, 0),
                v3(n.x * SH_THICK * 0.34, 0, n.z * SH_THICK * 0.34),
                SOCKET,
            );
        }
    }
    // THREE REINFORCING BANDS follow the arc — short runs per stave, each laid on its own normal, so the
    // banding curves with the door instead of chording across it. Three, because the door is a storey tall
    // now: two left the lower half a bare field.
    // …and they are LIGHTER THAN THE FIELD AND GENUINELY PROUD OF IT. Laid in `IRON_DK` a fraction of a
    // stave's thickness above a field of the same near-black, they were three lines nobody could see: the
    // relief law's other failure, which is authoring a few centimetres onto a mass four and a half metres
    // tall. On a face this size the band IS the structure, so it is banked out past the proudest stave and
    // carries the tone the eye can find the door's shape by.
    for ([_]f32{ 0.02, -0.34, -0.62 }) |ty| {
        var s: usize = 0;
        while (s < SH_STAVES) : (s += 1) {
            const am = mathx.lerpF(-SH_ARC_R, SH_ARC_L, (@as(f32, @floatFromInt(s)) + 0.5) / SH_STAVES);
            const halfW = SH_CURVE_R * (SH_ARC_L + SH_ARC_R) / SH_STAVES * 0.5 * 1.14;
            const n = v3(@sin(am), 0, @cos(am));
            b.addBox(
                arcAt(am, ty * H + rng.range(-0.004, 0.004) * H, SH_STAVE_PROUD + 0.014 * H),
                v3(n.z * halfW, 0, -n.x * halfW),
                v3(0, rng.range(0.026, 0.034) * H, 0),
                v3(n.x * 0.014 * H, 0, n.z * 0.014 * H),
                // NO RUST IN THE BANDS. A warm patch on a cold near-black field is the brightest, most
                // saturated thing on the door however dark the albedo — one roll in five came back as a
                // scatter of tan rectangles that read as labels stuck to it. The rust lives on the RIM,
                // where it is an edge and not a patch.
                SH_BAND,
            );
        }
    }
    // The rim, hammered round the curved edge in short lengths — the top binding FOLLOWS THE CROWN, the
    // foot's binding partly lost to the centuries, and both standing edges rolled. Still PLATE: two metres
    // of `BRIGHT` came back as a bar of pure white across the door.
    const topAt = struct {
        fn of(a: f32) f32 {
            const drop = @abs(a) / SH_ARC_L;
            return SH_TOP - 0.050 * H * drop * drop;
        }
    }.of;
    var s: usize = 0;
    while (s < SH_STAVES) : (s += 1) {
        const a0 = mathx.lerpF(-SH_ARC_R, SH_ARC_L, @as(f32, @floatFromInt(s)) / SH_STAVES);
        const a1 = mathx.lerpF(-SH_ARC_R, SH_ARC_L, @as(f32, @floatFromInt(s + 1)) / SH_STAVES);
        b.addCapsule(arcAt(a0, topAt(a0) - 0.006 * H, 0.004 * H), arcAt(a1, topAt(a1) - 0.006 * H, 0.004 * H), 0.016 * H, 0.014 * H, 7, IRON_LT);
        if (s < SH_STAVES - 2) { // the foot binding stops short: a length of it is gone
            b.addCapsule(arcAt(a0, -SH_BOT + 0.008 * H, 0.004 * H), arcAt(a1, -SH_BOT + 0.008 * H, 0.004 * H), 0.013 * H, 0.011 * H, 7, RUST);
        }
    }
    b.addCapsule(arcAt(-SH_ARC_R, topAt(-SH_ARC_R) - 0.010 * H, 0.004 * H), arcAt(-SH_ARC_R, -SH_BOT + 0.050 * H, 0.004 * H), 0.015 * H, 0.012 * H, 8, IRON_LT);
    b.addCapsule(arcAt(SH_ARC_L, topAt(SH_ARC_L) - 0.010 * H, 0.004 * H), arcAt(SH_ARC_L, -SH_BOT + 0.024 * H, 0.004 * H), 0.015 * H, 0.012 * H, 8, if (rng.float() < 0.5) RUST else IRON_LT);
    // **AND THE DEVICE IS STRUCTURE, NOT A PICTURE.** A skull was tried here and came back a pale beige egg
    // with two dots in the middle of the biggest face in the game — a cartoon, and the exact charge the
    // creature was already up on. What a pavise this size actually carries is the IRONWORK that stops it
    // folding: a heavy cross-brace bolted over the staves, the one thing whose shape says "four metres of
    // door" instead of "picture of a door". The bone on this creature belongs on the BODY, where it is a
    // joint the plate has opened at, and not painted onto his front.
    const cross = arcAt(0.02, -0.075 * H, SH_STAVE_PROUD + 0.016 * H);
    {
        var cs: usize = 0;
        while (cs < SH_STAVES) : (cs += 1) { // the horizontal arm follows the bow, like the bands
            const a0 = mathx.lerpF(-SH_ARC_R, SH_ARC_L, @as(f32, @floatFromInt(cs)) / SH_STAVES);
            const a1 = mathx.lerpF(-SH_ARC_R, SH_ARC_L, @as(f32, @floatFromInt(cs + 1)) / SH_STAVES);
            b.addCapsule(
                arcAt(a0, cross.y, SH_STAVE_PROUD + 0.016 * H),
                arcAt(a1, cross.y, SH_STAVE_PROUD + 0.016 * H),
                0.024 * H,
                0.021 * H,
                8,
                IRON_LT,
            );
        }
    }
    b.addCapsule( // …and the upright, running most of the door's height
        arcAt(0.02, SH_TOP - 0.090 * H, SH_STAVE_PROUD + 0.016 * H),
        arcAt(0.02, -SH_BOT + 0.120 * H, SH_STAVE_PROUD + 0.016 * H),
        0.026 * H,
        0.022 * H,
        8,
        IRON_LT,
    );
    b.setMat(BRIGHT);
    b.addBlob(cross, v3(0.046 * H, 0.046 * H, 0.026 * H), 6, 11, IRON_MD); // the plate over the join
    var r: i32 = 0;
    while (r < 12) : (r += 1) {
        const a = rng.range(-0.9, 0.9);
        b.addBlob(
            arcAt(mathx.lerpF(-SH_ARC_R, SH_ARC_L, a * 0.5 + 0.5), rng.range(-SH_BOT * 0.85, SH_TOP * 0.9), SH_STAVE_PROUD + 0.014 * H),
            v3(0.012 * H, 0.012 * H, 0.009 * H),
            4,
            8,
            if (rng.float() < 0.4) RUST else IRON_LT,
        ); // rivets
    }
    b.setMat(.leather);
    b.addCylinder(v3(-0.060 * H, 0.020 * H, -0.014 * H), v3(0.060 * H, 0.020 * H, -0.014 * H), 0.014 * H, 0.014 * H, 7, STRAP);
    return b.toMesh();
}

/// THE DOOR IS SQUARE TO THE MAN, NOT TO HIS FOREARM (`hero.shieldFit`'s law and `warrior.shieldXf`'s):
/// POSITION off the fist, ORIENTATION off the rig's own body frame — which for this creature includes the
/// TOPPLE, or the shield would stand up on end while the body it belongs to lies on the ground.
fn shieldXf(k: *const Knight) rl.Matrix {
    const fs = k.rigScale();
    // THE GRIP IS AT THE WRIST AND THE STANDOFF IS ALONG HIS OWN FRONT — never along the forearm's local Z,
    // which the guard pose has pointing at the sky: taken from the wrist frame it carried the grip 0.67 m
    // ABOVE his own wrist and put the door's top edge over his crown. So the position is the fist and the
    // offset is rotated by the BODY, which is the same frame the face is squared to.
    const fist = rl.math.vector3Transform(v3(0, FIST_Y, FIST_Z), k.xf[WRL]);
    // …AND PULLED ONTO HIS CENTRE LINE. The grip is out on the end of an arm, and a door left hanging where
    // the hand is covers one leg — it has to cover the MAN. Derived off the shoulder half-width, so it stays
    // on the middle of him if the frame is ever rebuilt.
    const carry = k.slamCarry();
    // …and the SHOVE slides it across his front onto the sword side (`shoveAcross`). A lateral carry, not a
    // rotation: the door has to stay a wall travelling across him, not a slab swung out on the end of an arm.
    const push = k.shoveAcross();
    const off = rl.math.vector3Transform(
        mathx.scaleV(v3(
            -SHOULDER_HALF * H * 0.80 + SHOVE_CARRY_X * push * k.shoveDir(),
            carry.y,
            SH_STANDOFF + carry.z + SHOVE_CARRY_Z * push,
        ), fs),
        k.bodyXf,
    );
    const hub = mathx.addV(fist, off);
    // THE SLAM CARRIES THE DOOR AND PITCHES IT **ABOUT ITS OWN CENTRE** (`slamCarry`/`slamPitch`) — face
    // skyward over his crown on the haul, face into the earth ahead of his boots on the drive. Taken about
    // the GRIP, which sits near the door's TOP edge, the same pitch swung four fifths of a four-metre plank
    // straight through the man carrying it: that is the move reading busted and cutting through his model.
    // Both channels are still `slamLift`'s, so the picture cannot disagree with `guardUp`.
    return mul3(
        scaleM(fs, fs, fs),
        mul3(
            mul3(tr(0, -SH_CENTRE_Y, 0), rx(k.slamPitch()), tr(0, SH_CENTRE_Y, 0)),
            mul(rx(-6.0), rz(3.0)),
            k.bodyXf,
        ),
        tr(hub.x, hub.y, hub.z),
    );
}

test "HE ROLLS ONTO HIS FRONT AND STAYS THERE — the rise does not roll him back onto his back first" {
    // Owner: the rolling / getting up part is bad. It WAS: `rollAmt` unwound across the first 42% of the
    // rise, so he heaved onto his face and immediately rolled back onto his spine to stand up off it — the
    // roll bought nothing and the whole move read as a crate rocking twice. Measured on the ONE channel that
    // says where his body is, plus the helm, which is what the eye actually follows.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.debugFall();
    const dt = 1.0 / 120.0;
    var t: f32 = 0;
    var rollPeak: f32 = 0;
    var seam: f32 = 0; // the biggest one-frame jump of the helm anywhere in the move
    var humpTop: f32 = 0; // …and how far the body heaves up over its own side to cross it
    var overshot = false;
    var prev = k.topWorld();
    var flat: f32 = 1e9;
    while (t < FALL_WIND_DUR + FALL_DUR + DOWN_DUR + ROLL_DUR + RISE_DUR + 0.25) : (t += dt) {
        _ = k.update(dt, v3(0, 0, -4), 200.0, .{});
        const helm = k.topWorld();
        if (k.state == .downed) flat = mathx.minF(flat, helm.y);
        if (k.state == .rollover) {
            rollPeak = mathx.maxF(rollPeak, k.rollAmt());
            humpTop = mathx.maxF(humpTop, helm.y);
        }
        // THE ROLL IS NEVER UNDONE: once he is on his front he stays on it until he is standing.
        if (k.state == .rise) try std.testing.expectApproxEqAbs(@as(f32, 0), k.rollAmt(), 1e-6);
        if (k.state == .rise and k.toppleAmt() > 0.01) overshot = true;
        if (t > FALL_WIND_DUR) seam = mathx.maxF(seam, @sqrt((helm.x - prev.x) * (helm.x - prev.x) +
            (helm.y - prev.y) * (helm.y - prev.y) + (helm.z - prev.z) * (helm.z - prev.z)));
        prev = helm;
    }
    try std.testing.expect(rollPeak > 0.99); // he really does go all the way over…
    try std.testing.expect(humpTop > flat + 0.4); // …heaving up over his own side to do it…
    try std.testing.expect(overshot); // …and the rise carries PAST upright and settles back onto it.
    // **AND THE SWAP IS INVISIBLE.** `turnAbout` describes one pose two ways (`Ry(180)·Rx(θ)` is
    // `Rx(−θ)·Ry(180)`), so nothing may move on the frame it happens — a seam here is a body teleporting.
    std.debug.print("\n  roll/rise: flat helm {d:.2}, hump to {d:.2}, worst one-frame move {d:.3} m\n", .{ flat, humpTop, seam });
    try std.testing.expect(seam < 0.35);
    // …and he ends up on his feet, facing the man he landed on rather than away from him.
    try std.testing.expectEqual(State.idle, k.state);
    try std.testing.expect(@abs(mathx.wrapPi(k.facing - std.math.pi)) < 0.5);
}

test "A BODY ALREADY ON THE GROUND CANNOT BE FLINCHED UPRIGHT — the punish window survives being used" {
    // A stun state carries NO topple, so a heavy landing on a downed knight snapped five metres of armour
    // instantly upright: the reward for reading the fall was the reward ending the moment you took it.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.state = .downed;
    k.t = DOWN_DUR * 0.4;
    k.easeFloored(1.0);
    k.pose();
    const before = k.vit.hp;
    const p = k.centerWorld();
    k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 30, .poise = 99, .stance = 60 } });
    try std.testing.expectEqual(State.downed, k.state); // still down…
    try std.testing.expect(k.vit.hp < before); // …and it still hurt him, which is the whole point
    try std.testing.expectEqual(@as(u32, 1), k.hits);
    // …but a killing blow is still a death, and the corpse crumples from where the body already LAY.
    k.hitLatch = false; // a second swing, not the same one twice (`foe.reached`'s one-hit latch)
    k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = HP_MAX, .poise = 1, .stance = 1 } });
    try std.testing.expectEqual(State.dead, k.state);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), k.deathFrom, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), k.toppleAmt(), 1e-6); // no snap upright on frame one…
    // …AND NOT ON ANY FRAME AFTER IT EITHER. Pinning only frame one is what let the first pass through: the
    // crumple started correctly at 1.0 and then lerped to −1, passing through ZERO — which is standing — so
    // the corpse rose to its feet in the middle of its own death and fell forward off them.
    var t: f32 = 0;
    var nearest: f32 = 1e9;
    while (t < DEATH_DUR) : (t += 1.0 / 60.0) {
        k.t = t;
        nearest = mathx.minF(nearest, @abs(k.toppleAmt()));
    }
    std.debug.print("\n  killed flat: the body never comes back closer than {d:.2} of upright\n", .{nearest});
    try std.testing.expect(nearest > 0.8);
    // …and a knight killed ON HIS FEET still goes over forward, which is the whole picture of his death.
    var up = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    up.debugKill();
    up.t = DEATH_DUR;
    try std.testing.expect(up.toppleAmt() < -0.8);
}

test "THE SWORD RIDES LOW OFF HIS SIDE — out, down, and clear of the earth" {
    // The carry IS the ask (owner: a large sword carried out to the side), so all three halves of the
    // picture are pinned off the POSED bone: OUT — the point stands off his own hip line on the sword side;
    // DOWN — it hangs below his knee, which nothing else on the field does; CLEAR — it does not furrow the
    // ground he is standing on, and it does not cross his midline onto the shield side.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3); // faces +Z, sword arm on his right (−X)
    k.setCarry(1.0);
    k.pose();
    const tip = k.weaponSeg()[1];
    const knee = k.xf[KNEER].m13;
    std.debug.print("\n  carry: tip at x {d:.2} y {d:.2} z {d:.2} (knee {d:.2}, hip half {d:.2})\n", .{
        tip.x, tip.y, tip.z, knee, HIP_HALF * H * k.scale,
    });
    try std.testing.expect(tip.x < -HIP_HALF * H * k.scale); // OUT, on his sword side
    try std.testing.expect(tip.y < knee); // DOWN past his own knee
    try std.testing.expect(tip.y > 0.10); // …and off the turf
    try std.testing.expect(tip.z > -0.3 * k.scale); // hanging at his side, not trailed out behind his back
}

test "THE DOOR IS A FULL-HEIGHT WALL — ankle to chin, bowed, and the creature still visible over it" {
    // The owner's own sizing law (since he is tall, his shield must be tall — the front may not be a place
    // to mash his legs from), MEASURED off the posed rig rather than eyeballed off a portrait. It has to
    // shut the whole body it defends, and it may not BE the creature: the helm rides clear.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.setCarry(1.0);
    k.pose();
    const hub = rl.math.vector3Transform(mathx.zero3, k.shXf);
    const low = hub.y - SH_BOT * k.scale;
    const high = hub.y + SH_TOP * k.scale;
    const crown = k.topWorld().y;
    const knee = k.xf[KNEEL].m13;
    std.debug.print("\n  door: foot {d:.2} m, top {d:.2} m (knee {d:.2}, crown {d:.2})\n", .{ low, high, knee, crown });
    try std.testing.expect(low < knee * 0.35); // …down past the shin to the ankle: no leg to mash
    try std.testing.expect(low > 0.05); // …and not ploughing the turf
    try std.testing.expect(high > crown * 0.82); // …up to the chin
    try std.testing.expect(high < crown - 0.25); // …and the helm stands clear of it

    // **AND IT IS A BOWED WALL, TALLER THAN IT IS WIDE** — the scutum's curve on the Sentinel's slab.
    // Measured off the POSED edges: he faces +Z, so both edges bow BACK toward him.
    const mid = rl.math.vector3Transform(arcAt(0, 0, 0), k.shXf);
    const edgeL = rl.math.vector3Transform(arcAt(SH_ARC_L, 0, 0), k.shXf);
    const edgeR = rl.math.vector3Transform(arcAt(-SH_ARC_R, 0, 0), k.shXf);
    std.debug.print("  bow: mid z {d:.2}, left edge z {d:.2} (x {d:.2}), right edge z {d:.2} (x {d:.2})\n", .{
        mid.z, edgeL.z, edgeL.x, edgeR.z, edgeR.x,
    });
    try std.testing.expect(edgeL.z < mid.z - SH_SAG_L * k.scale * 0.7);
    try std.testing.expect(edgeR.z < mid.z - 0.02 * H * k.scale);
    try std.testing.expect(edgeL.x > SHOULDER_HALF * H * k.scale); // …and it out-spans his shoulders both sides
    try std.testing.expect(@abs(edgeR.x) > SHOULDER_HALF * H * k.scale);

    // **AND IT IS HELD AGAINST HIM** (owner: it has to keep the shield close to the body if it is going to
    // block all frontal). BRACKETED FROM BOTH SIDES and measured off the CHEST, not off `bodyR` — the old
    // assertion asked only that the hub stood past 0.8 of his ground FOOTPRINT, which is 1.4 m and is not a
    // fact about his chest at all: it PINNED the door at arm's length, and it passed with 2.15 m of daylight
    // behind it. Under, the face is inside his own cuirass; over, it is a wall he is walking behind.
    const chestZ = k.xf[CHEST].m14;
    const front = chestZ + CHEST_FRONT_Z * k.scale; // the cuirass's own face, off its own box
    const back = hub.z - SH_THICK * k.scale; // …and the door's back face, which is what closes on it
    std.debug.print("\n  door: cuirass face {d:.2}, door back face {d:.2} → {d:.2} m of daylight\n", .{ front, back, back - front });
    try std.testing.expect(back > front); // it is not worn inside his chest…
    // …and the gap is a FIST, not an arm. A centre-gripped door cannot come closer than his own folded fist,
    // which for a body this size is about two thirds of a metre; it was 1.6 m.
    try std.testing.expect(back < front + 0.25 * k.scale);
    // …and it is pulled onto his CENTRE LINE rather than left out where the hand is — the wrap does the
    // reaching round his side, never the hub drifting off his middle.
    try std.testing.expect(@abs(hub.x) < SH_CHORD_R * k.scale * 0.45);
}

test "HE IS BIGGER THAN THE OGRE, and that is the one fact the creature is built on" {
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    var giant = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(k.topWorld().y > giant.topWorld().y);
    // …and by a real margin, not by a rounding: a boss the same height as a field enemy is not a boss.
    try std.testing.expect(k.topWorld().y > giant.topWorld().y * 1.15);
    // THE CRUSH STRIP IS HIS OWN LENGTH, so the ground the fall bills is the ground the body lands on.
    try std.testing.expect(crushLen(k.scale) >= k.topWorld().y * 0.85);
    try std.testing.expect(crushLen(k.scale) <= k.topWorld().y * 1.15);
}

test "THE DOOR COVERS HIS FRONT AND NOTHING ELSE — and the fall answers exactly the sector it cannot" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3); // faces +Z
    k.covered = true;
    const at = struct {
        fn it(deg: f32, r: f32) foe.Blade {
            const a = mathx.radians(deg);
            const p = v3(mathx.sinf(a) * r, 1.0, mathx.cosf(a) * r);
            return .{ .active = true, .a = p, .b = p };
        }
    }.it;
    try std.testing.expect(k.shielded(at(0, 4.0))); // dead ahead
    try std.testing.expect(k.shielded(at(TOWER_ARC - 3.0, 4.0)));
    try std.testing.expect(!k.shielded(at(TOWER_ARC + 3.0, 4.0))); // past the edge of the door
    try std.testing.expect(!k.shielded(at(180.0, 4.0))); // NOTHING ON HIS BACK
    // **THE DOOR IS WIDER THAN A MAN'S BOARDS IN METRES, WHICH IS THE CLAIM THAT WAS EVER TRUE** (owner:
    // it blocks attacks beyond its visual). It used to be asserted in DEGREES against `combat.GUARD_ARC`,
    // and it passed at 105 either side — off a plank whose face, measured against his own chest, occludes
    // barely a third of that. A creature cannot be allowed to eat blows that visibly sail past the outside
    // of its shield: the player learns the boundary he can SEE, and a hidden one reads as the fight
    // cheating. `TOWER_ARC` is now derived off these chords, so coverage can only be bought by building
    // door — and what makes it a wall is its SIZE, which is what this pins.
    try std.testing.expect(SH_CHORD_L + SH_CHORD_R > 0.45 * H);
    try std.testing.expect(TOWER_ARC > 40.0 and TOWER_ARC < 60.0);
    // …and it is still strictly wider than the sector the FALL answers, so the two never claim a bearing.
    try std.testing.expect(180.0 - FALL_SECTOR > TOWER_ARC);
    // The FALL's sector lies strictly outside the door's, so the two never claim one bearing…
    try std.testing.expect(180.0 - FALL_SECTOR > TOWER_ARC);
    // …and the gap between them is the SAFE POCKET: his quarter, not his back.
    try std.testing.expect(180.0 - FALL_SECTOR - TOWER_ARC > 20.0);
    // A dropped guard is a dropped guard whatever the bearing.
    k.covered = false;
    try std.testing.expect(!k.shielded(at(0, 4.0)));
}

test "A BLOW ON THE DOOR TAKES NO POISE, BUT THE FOOTING BEHIND IT CAN BE WORN THROUGH" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.state = .idle;
    k.covered = true;
    const before = k.vit.hp;
    const stanceBefore = k.vit.stance;
    // A heavy, square onto the front, from just outside his hurt sphere's own centre.
    const p = v3(0, 2.6, k.hurtRadius() * 0.5);
    k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 40, .poise = 90, .stance = 60 } });
    try std.testing.expectEqual(@as(u32, 1), k.blocks);
    try std.testing.expectEqual(State.idle, k.state); // ONE blow is not a break — he did not move
    try std.testing.expect(k.vit.poise == k.vit.poiseMax); // …and the door never lets a FLINCH through
    try std.testing.expect(k.vit.stance < stanceBefore); // …but the footing went
    try std.testing.expect(k.vit.hp < before); // …and chip got through, and chip can kill
    try std.testing.expect(k.vit.hp > before - 40.0 * 0.5);
    // KEEP AT IT AND HE BREAKS. This is the whole reason the change exists: frontal pressure used to earn
    // literally nothing — no damage worth the name, no poise, no stance — so the only openings in the fight
    // were the ones he handed out. The SHIELD still does not break; the man behind it does.
    var pressed = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    pressed.state = .idle;
    var swings: u32 = 0;
    while (swings < 40 and !pressed.staggered()) : (swings += 1) {
        pressed.covered = true;
        pressed.hitLatch = false; // a fresh swing each time, not one blade resting on him
        pressed.vit.hp = HP_MAX; // the stance is what is on trial here, not the chip's arithmetic
        pressed.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 1, .poise = 90, .stance = 60 } });
    }
    try std.testing.expect(pressed.staggered());
    try std.testing.expect(swings > 2); // …and it is expensive: not a two-hit answer to the whole creature
    try std.testing.expect(pressed.blocks == swings); // every one of them was BLOCKED — the door held
    // …and the same blow ROUND THE BACK is the whole thing.
    var back = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    back.state = .idle;
    back.covered = true;
    const q = v3(0, 2.6, -k.hurtRadius() * 0.5);
    back.tryHit(.{ .active = true, .r = 0.2, .a = q, .b = q, .a0 = q, .b0 = q, .hit = .{ .dmg = 40, .poise = 90, .stance = 60 } });
    try std.testing.expectEqual(@as(u32, 0), back.blocks);
    try std.testing.expectEqual(@as(u32, 1), back.hits);
    try std.testing.expect(back.staggered());
}

test "THE STRING IS ONE COMMITMENT — variable length, capped, and the debt paid at the finisher" {
    // Nothing may follow the OVERHEAD: its blade ends in the earth and the held End Pose IS its window.
    try std.testing.expect(stringNext(OVER_I) == null);
    for ([_]usize{ SWEEP_I, SWEEP2_I, THRUST_I, BASH_I }) |mv| try std.testing.expect(stringNext(mv) != null);
    // …and a link is still a telegraph however deep the string runs (`foe.TELL_MIN`, floored in `windDur`).
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    for ([_]usize{ SWEEP_I, SWEEP2_I, THRUST_I, BASH_I }) |mv| {
        k.atk = mv;
        k.state = windFor(mv);
        k.windHold = 0;
        k.strung = 1;
        const strungWind = k.windDur();
        k.strung = 0;
        try std.testing.expect(strungWind >= foe.TELL_MIN);
        try std.testing.expect(strungWind < k.windDur()); // …and genuinely shorter than the opener's
    }
    // THE DEBT ARRIVES ONCE, AT THE END, and it covers every move the string spent — not just the last.
    k.strung = 2;
    k.cds = [_]f32{0} ** MOVES.len; // spawn staggers them; this test is about what BILLING writes
    k.strungUsed = [_]bool{false} ** MOVES.len;
    k.strungUsed[SWEEP_I] = true;
    k.strungUsed[THRUST_I] = true;
    k.billString();
    try std.testing.expect(k.cds[SWEEP_I] > 0 and k.cds[THRUST_I] > 0);
    try std.testing.expect(k.cds[BASH_I] == 0); // …and nothing it did not spend
    try std.testing.expectEqual(@as(u8, 0), k.strung);
    // …dearer than a single would have been, because a flurry buys the player a longer quiet.
    try std.testing.expect(k.cds[SWEEP_I] > SWEEP.cd * 0.82);
    // AND AN INTERRUPT STILL BILLS IT. Left unbilled, being staggered out of a flurry was a reward: he came
    // out of the stumble with every move he had just spent still ready.
    var cut = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    cut.strung = 1;
    cut.strungUsed[SWEEP_I] = true;
    cut.enterStun(.stunheavy);
    try std.testing.expect(cut.cds[SWEEP_I] > 0);
    try std.testing.expectEqual(@as(u8, 0), cut.strung);
}

test "THE FLANK IS NOT A PLACE TO STAND — the sweep reaches it, and its own gather is the aim" {
    // A man parked on his quarter used to be answered by `.wait` and nothing else: he turned at 33 deg/s
    // while you hit him, which is the treadmill the whole fight had become.
    const scale = SCALE;
    const r = triggerR(SWEEP, scale) * 0.8;
    // THE SWAT IS THE FIRST ANSWER OUT HERE — it is the quickest thing he has and the flank is what it is
    // for. With it spent, the SWEEP is what still reaches, and its gather is its aim.
    var noSwat = [_]bool{ true, true, true, true, true, true };
    noSwat[SWAT_I] = false;
    var found = false;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const dec = classify(r, SWEEP_BEARING + 20.0, scale, false, false, false, false, false, false, false, false, i, &noSwat);
        if (dec.what == .strike and dec.mv == SWEEP_I) found = true;
    }
    try std.testing.expect(found);
    try std.testing.expectEqual(@as(usize, SWAT_I), classify(r, SWEEP_BEARING + 20.0, scale, false, false, false, false, false, false, false, false, 0, &[_]bool{ true, true, true, true, true, true }).mv);
    // …but past what the gather can close, he squares up first rather than throwing at a place the arc will
    // never reach — the SWING_BEARING law, one band out.
    const far = classify(r, FLANK_BEARING + 10.0, scale, false, false, false, false, false, false, false, false, 0, &[_]bool{ true, true, true, true, true, true });
    try std.testing.expect(far.what != .strike);

    // AND THE GATHER GENUINELY CLOSES IT. Walked frame by frame at his real turn rate, a sweep started at
    // the widest legal bearing arrives inside the door the arc can actually cover.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const rad = mathx.radians(FLANK_BEARING);
    const hero = v3(mathx.sinf(rad) * r, 0, mathx.cosf(rad) * r);
    k.atk = SWEEP_I;
    k.enter(.sweepwind);
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < SWEEP.windDur) : (t += dt) {
        foe.faceToward(k.pos, &k.facing, hero, TURN_RATE, dt);
    }
    try std.testing.expect(@abs(k.bearingTo(hero)) < SWEEP_BEARING);
}

test "THE POSE DOES NOT TELEPORT — the body CHASES its target, so no interrupt can snap it" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt = 1.0 / 60.0;
    // Deep into a sweep, settled, where the channels are as far from carry as they ever get…
    k.atk = SWEEP_I;
    k.enter(.sweep);
    k.t = SWEEP.strikeDur;
    var n: u32 = 0;
    while (n < 40) : (n += 1) {
        k.setStrike(1.0);
        k.settlePose(dt);
    }
    const mid = k.chanGet();
    // …and then interrupted, which is where the whole upper body used to teleport on one frame.
    k.enterStun(.stunheavy);
    k.easeNeutral(dt);
    k.settlePose(dt);
    const after = k.chanGet();
    for (mid, after) |was, now| try std.testing.expect(@abs(now - was) < 12.0);
    // …and it does GET there — a spring that never arrives is just lag.
    n = 0;
    while (n < 240) : (n += 1) {
        k.easeNeutral(dt);
        k.settlePose(dt);
    }
    try std.testing.expectApproxEqAbs(CARRY_SH, k.armSh, 3.0);
    // THE SPRING OVERSHOOTS ON HIS FEET AND DOES NOT OFF THEM: a body is a mass, a corpse is a sack.
    try std.testing.expect(SPRING_ZETA < 1.0);
    try std.testing.expect(SPRING_STIFF_DOWN > SPRING_STIFF);
    // …and the chain lags outward, which is what the hand-rolled sqrt/squared triple was faking.
    try std.testing.expect(SPRING_FALLOFF < 1.0 and SPRING_FALLOFF > 0.8);
}

test "LIGHT AND HEAVY ARE TELLABLE APART BEFORE THEY LAND, and a move cannot lie about its weight" {
    // Owner: light and heavy, I can't tell the difference here. Every gather threw the same dust at the
    // same rate, so the only way to know what was coming was to have already been hit by it.
    var lightest: f32 = 1e9;
    var heaviest: f32 = 0;
    for (MOVES) |a| {
        switch (a.weight) {
            .light => lightest = @min(lightest, a.hit.dmg),
            .heavy, .crushing => heaviest = @max(heaviest, a.hit.dmg),
        }
        // THE TELL MAY NEVER UNDERSTATE THE BLOW. A move tuned harder without its gather following it is
        // exactly the lie this enum exists to make impossible.
        if (a.hit.dmg >= 34) try std.testing.expect(a.weight == .crushing);
        if (a.hit.dmg <= 27) try std.testing.expect(a.weight != .crushing);
    }
    try std.testing.expect(lightest < heaviest);
    // THE FIRE IS THE RULE THE PLAYER LEARNS: none on a light, some on a heavy, most on a crusher.
    try std.testing.expectApproxEqAbs(@as(f32, 0), Weight.light.ember(), 1e-6);
    try std.testing.expect(Weight.heavy.ember() > 0 and Weight.heavy.ember() < Weight.crushing.ember());
}

test "A COMBO IS A ROUTE HE WALKS, and its END is a window you can plan for" {
    // Owner: longer combos, and memorization not luck. Rolled continuation meant the same opener ran two
    // hits one time and four the next, so the player could never learn where a string ENDS — and the end is
    // the punish window, which is the only thing a string is for.
    for ([_]usize{ SWEEP_I, BASH_I, THRUST_I, SWEEP2_I, SWAT_I }) |mv| {
        const route = routeFor(mv);
        try std.testing.expect(route.len >= 1);
        try std.testing.expect(route[0] != mv); // a route never opens with what it followed: that is a stutter
        // …and no route may run through the OVERHEAD except as its LAST link, because nothing follows it:
        // a string that hit the overhead in the middle would simply stop there, silently.
        for (route, 0..) |link, i| {
            if (link == OVER_I) try std.testing.expectEqual(route.len - 1, i);
        }
    }
    // NOTHING FOLLOWS THE OVERHEAD. Its blade ends in the earth and the held End Pose IS its window.
    try std.testing.expectEqual(@as(usize, 0), routeFor(OVER_I).len);
    // The longest string he owns is genuinely long now, and every link is still a real telegraph.
    var longest: usize = 0;
    for ([_]usize{ SWEEP_I, BASH_I, THRUST_I, SWEEP2_I, SWAT_I }) |mv| longest = @max(longest, routeFor(mv).len);
    try std.testing.expect(longest >= 3);
    // **THE ROUTES ARE NOT THE SAME ROUTE.** Mix-ups are only mix-ups if the openers lead somewhere
    // different — four identical strings would be one string with four names.
    {
        var distinct: u32 = 0;
        for ([_]usize{ SWEEP_I, BASH_I, THRUST_I, SWAT_I }) |a| {
            for ([_]usize{ SWEEP_I, BASH_I, THRUST_I, SWAT_I }) |b2| {
                if (a >= b2) continue;
                const ra = routeFor(a);
                const rb = routeFor(b2);
                if (ra.len != rb.len or !std.mem.eql(usize, ra, rb)) distinct += 1;
            }
        }
        try std.testing.expectEqual(@as(u32, 6), distinct); // all four openers lead somewhere of their own
    }
    for (MOVES) |a| try std.testing.expect(a.windDur >= foe.TELL_MIN);

    // **AND HE IS NOT MASHED OUT OF ONE HE HAS ALREADY STARTED** (the reference's hyperarmor on the string).
    // The OPENER is interruptible like anything else — reading a tell and punishing it still works.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.strung = 0;
    try std.testing.expect(!k.inString());
    k.strung = 1;
    try std.testing.expect(k.inString());
    // A light blow mid-string does NOT stop him…
    const p = v3(0, 2.6, -k.hurtRadius() * 0.5); // behind him, so the door is not in it
    k.atk = SWEEP2_I;
    k.enter(.sweep2);
    k.strung = 1;
    k.vit.poise = 1; // primed, so the blow resolves as a light break
    k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 4, .poise = 40, .stance = 1 } });
    try std.testing.expect(!k.staggered());
    try std.testing.expectEqual(State.sweep2, k.state);
    // …but a STANCE BREAK still does. The earned punish is never taken away.
    var b2 = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    b2.atk = SWEEP2_I;
    b2.enter(.sweep2);
    b2.strung = 1;
    b2.vit.stance = 1;
    b2.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 4, .poise = 10, .stance = 40 } });
    try std.testing.expect(b2.staggered());
}

test "HE DOES NOT FLINCH AT A POKE — a boss's poise is past what light spam can reach" {
    // Owner: he stuns too easily. Two causes, and both were mine: a poise pool a handful of lights could
    // empty, and a third of every blocked blow's footing coming through the door.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const p = v3(0, 2.6, -k.hurtRadius() * 0.5);
    var pokes: u32 = 0;
    while (pokes < 4) : (pokes += 1) {
        k.hitLatch = false;
        k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 6, .poise = 14, .stance = 3 } });
    }
    try std.testing.expect(!k.staggered()); // four light pokes are not a stagger on a boss
    // …and the PARRY is still the fast way in, because it is a committed read that deserves to be.
    try std.testing.expect(combat.PARRY_HIT.stance * 3 >= STANCE_MAX);
    // …while chip through the door is deliberately the SLOW way: flanking has to stay strictly better.
    try std.testing.expect(TOWER_STANCE_PASS < 0.25);
}

test "A FLANK BLOW HE SHRUGS OFF IS ANSWERED — he counters, he does not stand there turning" {
    // Owner: react very strongly to side attacks; more countering, less slow rotating. Shrugging a hit used
    // to mean nothing happened at all — he carried on rotating at 33 deg/s while being hit again.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    // Off his shoulder and INSIDE the hurt sphere: he faces +Z, so a blow out on +X is well past TOWER_ARC.
    const side = v3(k.hurtRadius() * 0.6, 2.6, 0);
    k.state = .idle;
    k.tryHit(.{ .active = true, .r = 0.2, .a = side, .b = side, .a0 = side, .b0 = side, .hit = .{ .dmg = 6, .poise = 2, .stance = 1 } });
    // **HE PIVOTS ONTO IT — HE DOES NOT SNAP** (owner: he turns on a dime, he should have to step-turn).
    // The answer is the step, with the swat CHAINED off its end, so the whole thing is two beats you can
    // watch and step out of rather than a free instant re-face.
    try std.testing.expectEqual(State.stepturn, k.state);
    try std.testing.expectEqual(@as(?usize, SWAT_I), k.stepThen);
    try std.testing.expect(k.counterCd > 0); // …and it is clocked, so a flurry cannot lock him into it
    // …and he is NOT facing the blow yet: the turn is the step's to do, at the step's own rate.
    try std.testing.expect(@abs(k.bearingTo(side)) > 40.0);

    // …BUT NOT ON HIS FRONT: that is the door's business (`caught`), not this.
    var front = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    front.state = .idle;
    const ahead = v3(0, 2.6, front.hurtRadius() * 0.6);
    front.tryHit(.{ .active = true, .r = 0.2, .a = ahead, .b = ahead, .a0 = ahead, .b0 = ahead, .hit = .{ .dmg = 6, .poise = 2, .stance = 1 } });
    try std.testing.expectEqual(State.idle, front.state);

    // …AND NEVER INSTEAD OF A STAGGER. An earned punish window is never taken back.
    var broke = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    broke.state = .idle;
    broke.vit.stance = 1;
    broke.tryHit(.{ .active = true, .r = 0.2, .a = side, .b = side, .a0 = side, .b0 = side, .hit = .{ .dmg = 6, .poise = 2, .stance = 60 } });
    try std.testing.expect(broke.staggered());

    // …and never out of something committed, or he would cancel his own stroke to answer a poke.
    var mid = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    mid.atk = SWEEP_I;
    mid.enter(.sweep);
    mid.tryHit(.{ .active = true, .r = 0.2, .a = side, .b = side, .a0 = side, .b0 = side, .hit = .{ .dmg = 6, .poise = 2, .stance = 1 } });
    try std.testing.expectEqual(State.sweep, mid.state);

    // ON HIS SPINE a flick reaches nothing, so the answer is the LEAP: he buys ground and lands facing you.
    var back = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    back.state = .idle;
    const behind = v3(0, 2.6, -back.hurtRadius() * 0.6);
    back.tryHit(.{ .active = true, .r = 0.2, .a = behind, .b = behind, .a0 = behind, .b0 = behind, .hit = .{ .dmg = 6, .poise = 2, .stance = 1 } });
    try std.testing.expectEqual(State.leapwind, back.state);
}

test "PHASE TWO AT HALF HEALTH — he lights the sword, and from then on every blow opens a disc" {
    // Owner: at half health he lifts his sword and charges it with chaos; in this phase his attacks do AoE
    // impacts. The reference's own shape (Tree Sentinel): ONE fixed signature move at an exact fraction, so
    // the turn is an event you recognise rather than a drift you notice afterwards.
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), AWAKEN.at, 1e-6);

    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.leash.provoke();
    try std.testing.expect(!k.lit);
    // Above the line he carries on as normal…
    k.vit.hp = k.vit.hpMax * 0.6;
    k.decide(6.0, 0);
    try std.testing.expect(k.state != .awaken);
    // …and the moment the bar crosses it, the awakening outranks every other decision.
    k.vit.hp = k.vit.hpMax * 0.5;
    k.decide(6.0, 0);
    try std.testing.expectEqual(State.awaken, k.state);
    try std.testing.expect(!k.lit); // …not yet: the charge has to finish first

    // IT IS A FULL STOP AND THE LARGEST FREE WINDOW IN THE FIGHT — nothing lands during it.
    const dt = 1.0 / 120.0;
    var t: f32 = 0;
    const far = v3(0, 0, 40.0);
    while (t < AWAKEN.liftDur + AWAKEN.holdDur + AWAKEN.settleDur + 0.05) : (t += dt) {
        try std.testing.expect(k.update(dt, far, 400.0, .{}) == null);
    }
    try std.testing.expect(k.lit);

    // …AND IT FIRES ONCE. Healing him, or anything else the bar does later, may not re-run it.
    k.vit.hp = k.vit.hpMax;
    k.vit.hp = k.vit.hpMax * 0.2;
    k.decide(6.0, 0);
    try std.testing.expect(k.state != .awaken);
    try std.testing.expect(k.lit); // …and the flag is a LATCH: a boss that de-escalates has no phase

    // EVERY BLOW NOW CARRIES THE DISC, folded into the stroke's own `Hit` so it meets resists and the guard
    // exactly like the rest of it — a second damage path would be a second set of rules nobody can learn.
    try std.testing.expect(CHAOS_BLAST.hit.elem.at(.chaos) > 0);
    // THE GAS IS THE SAME PHASE, ONE BEAT LATER: the disc taxes where you were, the cloud taxes where you
    // may stand. It is the lighter of the two per bite and it carries no reaction at all.
    try std.testing.expect(GAS_HIT.dmg < CHAOS_BLAST.hit.dmg);
    try std.testing.expect(GAS_HIT.poise == 0 and GAS_HIT.stance == 0);
    try std.testing.expect(GAS_HIT.elem.at(.chaos) > 0);
    try std.testing.expect(CHAOS_BLAST.hit.dmg < SWEEP_HIT.dmg); // light on damage…
    try std.testing.expect(CHAOS_BLAST.r > 0.5); // …and heavy on radius: it changes SPACING, not numbers
}

test "PHASE TWO'S GAS: the heavy strokes foul the ground, the flick does not, and only once he is lit" {
    // **WHICH ATTACKS IS THE `Weight` RULE.** Whatever the kit becomes, the moves that show fire in the
    // gather are the moves that leave a cloud — so the player never learns a second list.
    var anyHeavy = false;
    var anyLight = false;
    for (MOVES) |a| {
        if (a.weight == .light) anyLight = true else anyHeavy = true;
    }
    try std.testing.expect(anyHeavy and anyLight); // the rule has to divide the kit, or it is not a rule
    try std.testing.expect(MOVES[SWAT_I].weight == .light); // …and the flick is on the safe side of it

    // PHASE ONE LEAVES NOTHING. `lit` is the whole gate, so the first half of the fight is on clean ground.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.lit = false;
    k.atk = SWEEP_I;
    k.enter(.sweep);
    var f: usize = 0;
    while (f < 60) : (f += 1) {
        _ = k.update(1.0 / 60.0, v3(0, 0, 3.0), 60, .{});
        try std.testing.expect(k.gasAt == null);
    }

    // …AND LIT, THE SAME STROKE FOULS IT — on the MISS as much as the hit, which is what makes it spacing.
    var g = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    g.lit = true;
    g.atk = SWEEP_I;
    g.enter(.sweep);
    var laid = false;
    f = 0;
    while (f < 120 and !laid) : (f += 1) {
        _ = g.update(1.0 / 60.0, v3(0, 0, 40.0), 60, .{}); // a hero far out of reach: nothing was HIT
        if (g.gasAt != null) laid = true;
    }
    try std.testing.expect(laid);
}

test "the gas DOSES on its own clock, re-arms when he steps out, and thins to nothing" {
    var v = Vigil{ .model = undefined };
    const at = mathx.zero3;
    v.spawnGas(at, 1.0);
    // It has to GROW before it bites — a cloud that covers its full radius on frame one is a trap, not a
    // hazard you can see arriving.
    try std.testing.expect(v.gas[0].radius() < GAS_R);
    var t: f32 = 0;
    while (t < GAS_GROW * 2) : (t += 1.0 / 60.0) v.gas[0].update(1.0 / 60.0);
    try std.testing.expect(v.gas[0].covers(at));

    // STANDING IN IT: bites arrive on `GAS_DOSE_EVERY` and not once a frame.
    var bites: usize = 0;
    t = 0;
    while (t < GAS_DOSE_EVERY * 3.0) : (t += 1.0 / 60.0) {
        if (v.gasDose(1.0 / 60.0, at) != null) bites += 1;
    }
    try std.testing.expect(bites >= 2 and bites <= 4);

    // STEPPING OUT stops it dead and re-arms the clock, so an edge is never crossed for free.
    const outside = v3(GAS_R * 4.0, 0, 0);
    try std.testing.expect(v.gasDose(1.0 / 60.0, outside) == null);
    try std.testing.expectApproxEqAbs(@as(f32, 0), v.gasT, 1e-6);

    // …and it does not burn forever.
    t = 0;
    while (t < GAS_LIFE + 0.5) : (t += 1.0 / 60.0) v.gas[0].update(1.0 / 60.0);
    try std.testing.expect(!v.gas[0].covers(at));
    try std.testing.expect(v.gasDose(1.0 / 60.0, at) == null);

    // …AND ITS LAST PUFFS GO OUT WITH IT. `drawFx` draws the pool whether or not the cloud is live, and a
    // mote laid on the last frame carries up to `GAS_PUFF_HI` — gated behind `live` the pool stopped being
    // ticked here and hung in the air until a third heavy stroke recycled the slot.
    t = 0;
    while (t < GAS_PUFF_HI + 0.05) : (t += 1.0 / 60.0) v.gas[0].update(1.0 / 60.0);
    for (v.gas[0].parts) |p| try std.testing.expect(p.life <= 0);
}

test "THE SWIPE-AND-LEAP — one beat, not two, and only ever off a flank" {
    // Owner: the swipe-and-leap when you're on his side should be a bit faster and more evil. The point is
    // that there is NO RECOVERY between them — the flick and the bound are one exchange.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.atk = SWAT_I;
    k.opener = SWAT_I;
    k.enter(.swat);
    k.leapCd = 0;
    const flank = v3(4.0, 0, 0.4); // off his shoulder: he faces +Z
    const dt = 1.0 / 120.0;
    var t: f32 = 0;
    while (t < SWAT.strikeDur + 0.05 and k.state == .swat) : (t += dt) _ = k.update(dt, flank, 400.0, .{});
    try std.testing.expectEqual(State.leapwind, k.state);
    try std.testing.expect(k.leapChained);
    // …AND THE COIL IS SHORT, because the flick already did the gathering. That is the "faster" half.
    try std.testing.expect(k.leapWind() < LEAP.windDur);
    try std.testing.expect(LEAP_CHAIN_WIND < 1.0);

    // FROM THE FRONT IT IS NOT THROWN AT ALL — there it would just be him running away.
    var sq = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    sq.atk = SWAT_I;
    sq.opener = SWAT_I;
    sq.enter(.swat);
    sq.leapCd = 0;
    const ahead = v3(0, 0, 4.0);
    t = 0;
    while (t < SWAT.strikeDur + 0.05 and sq.state == .swat) : (t += dt) _ = sq.update(dt, ahead, 400.0, .{});
    try std.testing.expect(sq.state != .leapwind);

    // …and a COLD leap keeps its full tell: five metres of armour may not leave the ground out of nowhere.
    var cold = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    cold.enter(.leapwind);
    try std.testing.expect(!cold.leapChained);
    try std.testing.expectApproxEqAbs(LEAP.windDur, cold.leapWind(), 1e-6);
    try std.testing.expect(cold.leapWind() >= foe.TELL_MIN);
}

test "THE LEAP — he buys ground and lands facing you, and the roots refuse it" {
    // Owner: give him a leap he can use to quickly turn and face you; he jumps up and away facing you.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    // Standing on his SPINE, inside his own length, with nothing gathered: the pivot step needs more than
    // one beat to bring his front round from back there, so he leaves instead.
    const ready = [_]bool{ true, true, true, true, true, true };
    // **AND IT IS BOUGHT WITH DAMAGE, NOT WITH BEING STOOD BEHIND** (owner: he jumps a bit too often).
    const dec = classify(crushLen(k.scale) * 0.6, 180.0, k.scale, false, false, false, false, false, true, false, true, 0, &ready);
    try std.testing.expectEqual(Choice.leap, dec.what);
    // …and the same place with nobody hurting him is a STEP, which is the beat a player needs to get a
    // swing in. This is the whole retune: the ground answers cost him something now.
    const unpressed = classify(crushLen(k.scale) * 0.6, 180.0, k.scale, false, false, false, false, true, true, false, false, 0, &ready);
    try std.testing.expectEqual(Choice.stepturn, unpressed.what);
    // …but the FALL outranks it: with that gathered, a man stood there is a punish and not a problem.
    const withFall = classify(crushLen(k.scale) * 0.6, 180.0, k.scale, true, false, false, false, false, true, false, true, 0, &ready);
    try std.testing.expectEqual(Choice.fall, withFall.what);

    // IT ACTUALLY LEAVES THE GROUND, TRAVELS AWAY, AND LANDS FACING HIM.
    const hero = v3(0, 0, -3.0); // behind him: he faces +Z
    k.facing = 0;
    k.enter(.leapwind);
    const dt = 1.0 / 120.0;
    var t: f32 = 0;
    var peak: f32 = 0;
    var flew = false;
    const startZ = k.pos.z;
    while (t < LEAP.windDur + LEAP.flightDur + LEAP.landDur + 0.1) : (t += dt) {
        _ = k.update(dt, hero, 400.0, .{});
        peak = @max(peak, k.air);
        if (k.airborne()) flew = true;
    }
    try std.testing.expect(flew and peak > foe.AIRBORNE_LIFT * 4.0);
    try std.testing.expect(k.pos.z > startZ + 0.5); // AWAY from the man behind him…
    try std.testing.expectApproxEqAbs(@as(f32, 0), k.air, 1e-4); // …back on the earth at the end…
    try std.testing.expect(@abs(k.bearingTo(hero)) < 40.0); // …and squared onto him
    // AND IT IS A LEAP IN THE ROOTS' SENSE: a body held by the ankles cannot leave the earth.
    var held = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    held.root.grab();
    try std.testing.expect(!foe.canLeap(&held.root));
}

test "THE SWORD SIDE HAS AN ANSWER — the shove, and it pays for that flank with his front" {
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const ready = [_]bool{ true, true, true, true, true, true };
    const near = triggerR(BASH, k.scale) * 0.9;
    // His shield is his LEFT arm, which is a POSITIVE bearing. Stood off his RIGHT shoulder inside his own
    // reach used to be the one square with nothing aimed at it: hop if you moved, `.wait` if you did not.
    // With the quick SWAT spent (it is the first thing he reaches for out here), the shove is the answer.
    var noSwat = ready;
    noSwat[SWAT_I] = false;
    const sword = classify(near, -(SWEEP_BEARING + 12.0), k.scale, false, false, false, true, false, false, false, false, 0, &noSwat);
    try std.testing.expectEqual(Choice.strike, sword.what);
    try std.testing.expectEqual(@as(usize, BASH_I), sword.mv);
    try std.testing.expect(sword.shove);
    try std.testing.expect(!sword.shoveShield); // …hauled ACROSS his front to get there
    // …AND THE SHIELD SIDE GETS ONE TOO, hauled the other way. A wall between you and him stops blows; it
    // does not throw them, and that flank used to be a lap you could walk for free.
    // …bought with DAMAGE over here (the last `true`), because the sweep already owns the standing case.
    const shield = classify(near, SWEEP_BEARING + 12.0, k.scale, false, false, false, false, false, false, false, true, 0, &noSwat);
    try std.testing.expect(shield.shove);
    try std.testing.expect(shield.shoveShield);
    // …and the two really are opposite hauls, which is the one thing `shoveDir` exists to keep honest.
    var sw = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    sw.shoveShield = false;
    var sh2 = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    sh2.shoveShield = true;
    try std.testing.expect(sw.shoveDir() * sh2.shoveDir() < 0);
    // THE FRONT IS THE PRICE. The door leaves his chest to reach across, and `guardUp` says so — a flank
    // answer that cost him nothing would just be one more thing with no counter.
    var s = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    s.atk = BASH_I;
    s.shoving = true;
    s.enter(.bash);
    s.t = BASH.strikeDur * 0.6;
    try std.testing.expect(s.shoveAcross() > 0.5);
    try std.testing.expect(!s.guardUp());
    // …and the ordinary bash keeps it, because there the door IS the blow.
    s.shoving = false;
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.shoveAcross(), 1e-6);
    try std.testing.expect(s.guardUp());
    // It is still a real telegraph and a real window — the bash's own row, so it cannot come out faster
    // than a move the player has already learned to read.
    try std.testing.expect(BASH.windDur >= foe.TELL_MIN);
    for ([_][]const PoseKey{ SHOVE_KEYS.wind, SHOVE_KEYS.strike, SHOVE_KEYS.recover }) |list| {
        try std.testing.expectApproxEqAbs(@as(f32, 0), list[0].t, 1e-6);
        try std.testing.expectApproxEqAbs(@as(f32, 1), list[list.len - 1].t, 1e-6);
    }
    const wEnd = samplePose(SHOVE_KEYS.wind, 1.0);
    const sStart = samplePose(SHOVE_KEYS.strike, 0.0);
    for (wEnd, sStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
}

test "THE PHASES MEET — a stroke's wind, strike and recover are one continuous track" {
    // Three functions that lined up only because somebody kept them in step by hand is exactly how
    // `setSweepWind` and `setSweep` drifted apart, and a seam in a pose is a POP on the frame it crosses.
    for ([_]usize{ SWEEP_I, SWEEP2_I, OVER_I, THRUST_I, BASH_I }) |mv| {
        const m = keysFor(mv);
        const windEnd = samplePose(m.wind, 1.0);
        const strikeStart = samplePose(m.strike, 0.0);
        const strikeEnd = samplePose(m.strike, 1.0);
        const recStart = samplePose(m.recover, 0.0);
        for (windEnd, strikeStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
        for (strikeEnd, recStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
        // …and every track is ordered and covers its whole clock, or a key silently never plays.
        for ([_][]const PoseKey{ m.wind, m.strike, m.recover }) |list| {
            try std.testing.expect(list.len >= 2);
            try std.testing.expectApproxEqAbs(@as(f32, 0), list[0].t, 1e-6);
            try std.testing.expectApproxEqAbs(@as(f32, 1), list[list.len - 1].t, 1e-6);
            var i: usize = 1;
            while (i < list.len) : (i += 1) try std.testing.expect(list[i].t > list[i - 1].t);
        }
    }
    // THE CHARGE'S SEAMS TOO — four phases, so three of them: wind→travel, travel→brake (its `recover`
    // slot), and brake→the post-brake ease home. The old brake/recover pair re-hauled the door wide across
    // the state seam, a pop the springs were quietly eating; keys make it a claim a test can hold.
    {
        const windEnd = samplePose(CHARGE_KEYS.wind, 1.0);
        const runStart = samplePose(CHARGE_KEYS.strike, 0.0);
        const runEnd = samplePose(CHARGE_KEYS.strike, 1.0);
        const brakeStart = samplePose(CHARGE_KEYS.recover, 0.0);
        const brakeEnd = samplePose(CHARGE_KEYS.recover, 1.0);
        const recStart = samplePose(&CHG_REC, 0.0);
        for (windEnd, runStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
        for (runEnd, brakeStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
        for (brakeEnd, recStart) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-4);
    }
}

test "EVERY STROKE HAS A SHAPE, NOT TWO POSES — a gather that loads, a snap, and a follow-through" {
    // The charge this is written against: as `lerpF(WIND, HIT, k)` a stroke could only travel from one pose
    // to the other at varying speed. These are the three things a shape has that a lerp cannot.
    for ([_]usize{ SWEEP_I, SWEEP2_I, OVER_I, THRUST_I, BASH_I }) |mv| {
        const m = keysFor(mv);
        // A STRIKE SNAPS: most of its travel is over early. Measured on the channel that moves furthest.
        const s0 = samplePose(m.strike, 0.0);
        const s1 = samplePose(m.strike, 1.0);
        var far: usize = 0;
        var span: f32 = 0;
        for (s0, s1, 0..) |a, b, i| {
            if (@abs(b - a) > span) {
                span = @abs(b - a);
                far = i;
            }
        }
        try std.testing.expect(span > 20.0); // the stroke genuinely travels
        const third = samplePose(m.strike, 0.34)[far];
        const done = @abs(third - s0[far]) / span;
        try std.testing.expect(done > 0.55); // …and over half of it is spent in the first third
        // A FOLLOW-THROUGH: somewhere in the strike a channel goes PAST where it ends up. Five metres of
        // steel does not stop where it lands, and its absence is what read as a mannequin being posed.
        var overshot = false;
        var u: f32 = 0;
        while (u <= 1.0) : (u += 0.02) {
            const v = samplePose(m.strike, u);
            for (v, s0, s1) |now, a, b| {
                const hi = @max(a, b);
                const lo = @min(a, b);
                if (now > hi + 2.0 or now < lo - 2.0) overshot = true;
            }
        }
        try std.testing.expect(overshot);
    }
    // …and the OVERHEAD's hang does not creep, which is what makes `windHold` a bait and not a leak.
    const w = OVER_KEYS.wind;
    try std.testing.expectEqual(anim.Ease.hold, w[w.len - 1].ease);
}

test "A MOVE IS A SEQUENCE OF POSES, and the last one HOLDS — the End Pose is the punish window" {
    const keys = [_]PoseKey{
        .{ .t = 0.00, .p = .{} },
        .{ .t = 0.45, .p = .{ .armSh = -120, .lean = -22 }, .ease = .accel },
        .{ .t = 0.55, .p = .{ .armSh = -120, .lean = -22 }, .ease = .hold },
        .{ .t = 0.70, .p = .{ .armSh = 70, .lean = 34 }, .ease = .snap },
    };
    // The gather is somewhere between the two, not at either…
    const gather = samplePose(&keys, 0.25);
    try std.testing.expect(gather[Knight.CH_ARM_SH] < CARRY_SH and gather[Knight.CH_ARM_SH] > -120);
    // …the HANG does not creep, which is what makes a delayed downswing bait a roll instead of leaking it…
    const hangA = samplePose(&keys, 0.47);
    const hangB = samplePose(&keys, 0.54);
    try std.testing.expectApproxEqAbs(hangA[Knight.CH_ARM_SH], hangB[Knight.CH_ARM_SH], 1e-4);
    // …the strike is nearly over a quarter of the way through it (a strike, not a reach)…
    const quarter = samplePose(&keys, 0.55 + 0.15 * 0.25);
    try std.testing.expect(quarter[Knight.CH_ARM_SH] > -120 + (70 - -120) * 0.6);
    // …and past the last key it HOLDS, for as long as the recover runs.
    const end = samplePose(&keys, 1.0);
    const wayPast = samplePose(&keys, 4.0);
    try std.testing.expectApproxEqAbs(@as(f32, 70), end[Knight.CH_ARM_SH], 1e-4);
    try std.testing.expectApproxEqAbs(end[Knight.CH_ARM_SH], wayPast[Knight.CH_ARM_SH], 1e-6);
}

test "THE BODY LANDS ON YOU ONCE — every blow he owns is latched, and the fall's was not" {
    // The fall billed `FALL_HIT` on EVERY frame from the impact to the end of the fall, because `dealt`
    // latched the thud and the dust and not the blow. That is the one-shot, and no damage value fixes it.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    k.debugFall();
    const behind = v3(0, 0, -crushLen(k.scale) * 0.5); // dead in the strip, and staying there
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var landed: u32 = 0;
    while (t < FALL_WIND_DUR + FALL_DUR + 0.2) : (t += dt) {
        if (k.update(dt, behind, 400.0, .{}) != null) landed += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), landed);
    // …and it is not the hardest hit on him, because it is the hardest to read: only the thrust is lighter.
    // Most of the kit hits harder than the body landing on you does, which is the point: its price is
    // POSITION. (The SWAT is under it — that one is a flick whose whole job is to move your feet.)
    var heavier: u32 = 0;
    for (MOVES) |a| {
        if (a.hit.dmg > FALL_HIT.dmg) heavier += 1;
    }
    try std.testing.expect(heavier >= MOVES.len - 2);
    try std.testing.expect(SLAM_HIT.dmg > FALL_HIT.dmg and CHARGE_HIT.dmg > FALL_HIT.dmg);
}

test "THE FALL LANDS BEHIND HIM AND NOWHERE ELSE" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3); // faces +Z, so his back is -Z
    const reach = crushLen(k.scale);
    // Dead behind, inside his own length: crushed.
    k.heroHit = null;
    k.tryCrush(v3(0, 0, -reach * 0.6), FALL_HIT);
    try std.testing.expect(k.heroHit != null);
    // Dead AHEAD of him: the strip does not go that way.
    k.heroHit = null;
    k.tryCrush(v3(0, 0, reach * 0.6), FALL_HIT);
    try std.testing.expect(k.heroHit == null);
    // Behind but past his length.
    k.heroHit = null;
    k.tryCrush(v3(0, 0, -reach - 1.5), FALL_HIT);
    try std.testing.expect(k.heroHit == null);
    // Behind but off to the SIDE of the strip — which is what makes rolling sideways the answer.
    k.heroHit = null;
    k.tryCrush(v3(FALL_HALF_W * k.scale + HERO_REACH + 1.2, 0, -reach * 0.6), FALL_HIT);
    try std.testing.expect(k.heroHit == null);
}

test "THE BANDS AND THE PATTERNS: falls behind, hops when circled, and repeats so he can be learned" {
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const ready = [_]bool{ true, true, true, true, true, true };
    const cold = [_]bool{ false, false, false, false, false, false };
    const boots = triggerR(BASH, k.scale) * 0.8;
    const mid0 = (triggerR(BASH, k.scale) + triggerR(SWEEP, k.scale)) * 0.5;

    // **THE SAME PLACE TWICE GIVES THE SAME ANSWER TWICE** (owner: memorization, not luck). This is the
    // whole change: `classify` is pure and its only variable input is now the CURSOR, so a player standing
    // still sees a rotation he can recite instead of a die he can only survive.
    for ([_]usize{ 0, 1, 2, 3, 4, 5 }) |c| {
        const a = classify(mid0, 0, k.scale, false, false, false, false, false, false, false, false, c, &ready);
        const b2 = classify(mid0, 0, k.scale, false, false, false, false, false, false, false, false, c, &ready);
        try std.testing.expectEqual(a.what, b2.what);
        try std.testing.expectEqual(a.mv, b2.mv);
    }
    // …and it is a ROTATION, not one move on repeat: walking the cursor covers more than one answer.
    {
        var seen = [_]bool{false} ** MOVES.len;
        for ([_]usize{ 0, 1, 2, 3 }) |c| {
            const dec = classify(mid0, 0, k.scale, false, false, false, false, false, false, false, false, c, &ready);
            if (dec.what == .strike) seen[dec.mv] = true;
        }
        var kinds: u32 = 0;
        for (seen) |s| {
            if (s) kinds += 1;
        }
        try std.testing.expect(kinds >= 2);
    }
    // …and the two SIDES genuinely differ, which is what makes "stand on the shield side" a rule worth
    // learning rather than a thing somebody wrote in a comment.
    {
        // Inside `SWING_BEARING`, because off square only the sweep may be thrown at all and both sides
        // would correctly agree on it � which is a different law, tested above.
        var differs = false;
        for ([_]usize{ 0, 1, 2, 3 }) |c| {
            const l = classify(mid0, SWING_BEARING - 6.0, k.scale, false, false, false, false, false, false, false, false, c, &ready);
            const r = classify(mid0, -(SWING_BEARING - 6.0), k.scale, false, false, false, false, false, false, false, false, c, &ready);
            if (l.mv != r.mv) differs = true;
        }
        try std.testing.expect(differs);
    }

    // Dead behind him with the fall gathered: he falls, and it outranks a pressed hop.
    try std.testing.expectEqual(Choice.fall, classify(crushLen(k.scale) * 0.7, 180.0, k.scale, true, true, false, true, false, false, true, true, 0, &ready).what);
    // …with it cooling, the hero ORBITING **and the spot costing him**, the hop re-squares him.
    try std.testing.expectEqual(Choice.hop, classify(crushLen(k.scale) * 0.7, 180.0, k.scale, false, true, false, true, false, false, true, true, 0, &ready).what);
    // **AND THE SAME ORBIT WITH NOBODY HURTING HIM IS NOT A REASON TO MOVE** (owner: he jumps a bit too
    // often; sometimes he should simply attack more). This one line is the retune.
    try std.testing.expectEqual(Choice.wait, classify(crushLen(k.scale) * 0.7, 180.0, k.scale, false, true, false, true, false, false, true, false, 0, &ready).what);
    try std.testing.expectEqual(Choice.wait, classify(crushLen(k.scale) * 0.7, 180.0, k.scale, false, true, false, true, false, false, false, false, 0, &ready).what);
    // THE WIDE FLANK: hop on a circler — and **THE CAMPER IS NO LONGER FREE.** Standing off his shoulder
    // used to return `.wait`, so he turned at 33 deg/s and did nothing while you hit him, which is the
    // treadmill the whole fight had become. The SWEEP reaches out here now; its gather is its aim.
    const flank = SWEEP_BEARING + 15.0;
    // THE SWAT LEADS OUT HERE — the quickest answer to somebody standing beside him. Everything else is
    // what he reaches for once it is spent.
    // …and it leads even when the spot IS costing him: the kit answers a circler before the feet do.
    try std.testing.expectEqual(@as(usize, SWAT_I), classify(boots, flank, k.scale, true, true, false, true, false, false, true, true, 0, &ready).mv);
    var noSwat = ready;
    noSwat[SWAT_I] = false;
    // …and with the door spent as well, the FEET are still what is left: the hop did not go anywhere.
    var coldBash = noSwat;
    coldBash[BASH_I] = false;
    // **AND THE DOOR ANSWERS BEFORE THE FEET DO, ON EITHER SHOULDER** (owner, twice: no shield-side danger,
    // you can circle freely; then, after playing it, still too easy to hug the shield side). With the flick
    // spent this used to be the hop — he left the argument rather than winning it, on the one flank he is
    // best equipped to punish from. It is the same row both ways; only `shoveShield` differs, and STANDING
    // THERE IS ENOUGH: gating it on damage was too quiet a rule to answer a patient camper.
    for ([_]f32{ flank, -flank }) |b| {
        const d = classify(boots, b, k.scale, true, true, false, true, false, false, true, false, 0, &noSwat);
        try std.testing.expectEqual(Choice.strike, d.what);
        try std.testing.expectEqual(@as(usize, BASH_I), d.mv);
        try std.testing.expect(d.shove);
        try std.testing.expect(d.shoveShield == (b > 0)); // hauled onto whichever side you chose
    }
    // …and with the DOOR spent too the SWEEP is what is left out here, so it has not been eaten — it is
    // queued behind the quicker answers, which is the order the whole flank is built in.
    try std.testing.expectEqual(@as(usize, SWEEP_I), classify(boots, flank, k.scale, true, true, false, true, false, false, false, false, 0, &coldBash).mv);
    // …and with the flick AND the door spent and the spot costing him, the FEET are still there.
    try std.testing.expectEqual(Choice.hop, classify(boots, -flank, k.scale, true, true, false, true, false, false, true, true, 0, &coldBash).what);
    // …and with the sweep spent he turns, because a stroke thrown at a bearing the arc cannot reach is a
    // second and a half spent on a guaranteed miss.
    try std.testing.expectEqual(Choice.wait, classify(boots, flank, k.scale, true, true, false, true, false, false, false, false, 0, &cold).what);
    // Past what the gather can close, he squares up first whatever is ready.
    try std.testing.expectEqual(Choice.wait, classify(boots, FLANK_BEARING + 10.0, k.scale, true, true, false, true, false, false, false, false, 0, &ready).what);
    // ON HIS BOOTS the SLAM keeps its own slot in the rotation, so it lands on a beat rather than a roll.
    try std.testing.expectEqual(Choice.slam, classify(boots, 0, k.scale, false, true, false, false, false, false, false, false, 2, &ready).what);
    // …and off square only the SWEEP may be thrown, whatever the pattern wanted.
    const mid = mid0;
    // **HIS FRONT ATTACKS COVER HIS FRONT** (owner: too easy to just be in front of his shield). Standing
    // thirty-odd degrees off his nose — squarely inside the arc the door blocks — used to be answered only
    // by the sweep, which made the ground directly in front of a boss the safest on the board. Every sword
    // move reaches there now; the BASH is the one that stays tight, because its ram genuinely cannot.
    try std.testing.expect(classify(mid, 34.0, k.scale, true, false, false, false, false, false, false, false, 0, &ready).what == .strike);
    try std.testing.expect(OVERHEAD.bearing > 34.0 and THRUST.bearing > 34.0);
    try std.testing.expect(BASH.bearing < 34.0);
    // …and each move's own limit is honest about its kit: the ram's face subtends about 26 deg at the range
    // it arrives, and nothing may be thrown wider than the thing on the end of it is wide.
    for (MOVES) |a| try std.testing.expect(a.bearing <= FLANK_BEARING);
    // A move on COOLDOWN is skipped, never waited for — the player watched him spend it, so the skip reads.
    {
        var one = [_]bool{ false, false, false, false, false, false };
        one[SWEEP_I] = true;
        try std.testing.expectEqual(@as(usize, SWEEP_I), classify(mid, 0, k.scale, false, false, false, false, false, false, false, false, 1, &one).mv);
    }
    // THE THRUST'S OWN BAND — "only used when no other attacks will reach": the point plus the lunge.
    const long = (triggerR(SWEEP, k.scale) + thrustBandR(k.scale)) * 0.5;
    try std.testing.expectEqual(@as(usize, THRUST_I), classify(long, 0, k.scale, true, true, true, true, false, false, false, false, 0, &ready).mv);
    try std.testing.expect(thrustBandR(k.scale) > triggerR(SWEEP, k.scale)); // …and it really is his longest arm
    // In reach with nothing gathered he looms; out of reach he closes; out of his world he holds.
    try std.testing.expectEqual(Choice.wait, classify(boots, 0, k.scale, false, false, false, false, false, false, false, false, 0, &cold).what);
    try std.testing.expectEqual(Choice.approach, classify(thrustBandR(k.scale) + 4.0, 0, k.scale, true, false, false, false, false, false, false, false, 0, &ready).what);
    try std.testing.expectEqual(Choice.hold, classify(AGGRO_R + 1.0, 0, k.scale, true, true, true, true, false, false, true, true, 0, &ready).what);
    // THE CHARGE IS THE ANSWER TO RANGE AND NOTHING ELSE: patience burnt, he charges from out of reach —
    // never from inside his own sword length, where it would be a shove nobody can read.
    try std.testing.expectEqual(Choice.charge, classify(CHARGE.far + 3.0, 0, k.scale, true, false, true, false, false, false, false, false, 0, &ready).what);
    try std.testing.expectEqual(Choice.strike, classify(boots, 0, k.scale, true, false, true, false, false, false, false, false, 0, &ready).what);
}

test "THE WINDOW IS AN INSTANT BEFORE THE HIT, on all five strokes — and the FALL, SLAM, CHARGE and HOP have none" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const windOf = [_]State{ .sweepwind, .overwind, .thrustwind, .bashwind, .chainwind, .swatwind };
    const strikeOf = [_]State{ .sweep, .over, .thrust, .bash, .sweep2, .swat };
    for (MOVES, 0..) |a, mv| {
        // THE SWAT IS THE ONE WEAPON MOVE WITH NO WINDOW — the proximity tax, written at `toImpact`. It is
        // checked below with the other unparryables rather than skipped quietly.
        if (mv == SWAT_I) continue;
        const impact = a.strikeDur * a.impactK;
        // It is an INSTANT, not a slice of the tell: a 1.2 s haul may not be catchable for a fifth of it.
        try std.testing.expect(PARRY_LEAD < a.windDur * 0.4);
        const step = 1.0 / 600.0;
        var open: f32 = -1;
        var shut: f32 = -1;
        var elapsed: f32 = 0;
        k.atk = mv;
        k.windHold = 0;
        while (elapsed <= a.windDur + impact) : (elapsed += step) {
            if (elapsed > a.windDur) {
                k.state = strikeOf[mv];
                k.t = elapsed - a.windDur;
            } else {
                k.state = windOf[mv];
                k.t = elapsed;
            }
            if (k.parryable() != null) {
                if (open < 0) open = elapsed;
                shut = elapsed;
            }
        }
        try std.testing.expect(open > 0);
        // …and it SHUTS AT THE IMPACT FRAME by construction, so a caught blow is one that never landed.
        try std.testing.expectApproxEqAbs(a.windDur + impact, shut, 2.0 * step);
        try std.testing.expectApproxEqAbs(PARRY_LEAD, shut - open, 3.0 * step);
    }
    // EVERY WEAPON STROKE IS PARRYABLE AND NOTHING ELSE IS (the Crucible contract) — the fall, the slam,
    // the charge and the hop are each answered by FEET, and each says so at `toImpact`.
    for ([_]State{ .fallwind, .fall, .downed, .rollover, .rise, .slamwind, .slam, .chargewind, .charge, .brake, .hop, .stepturn, .swatwind, .swat, .idle, .approach, .recover, .stunlight, .stunheavy, .dead }) |s| {
        k.state = s;
        k.t = 0;
        try std.testing.expect(k.parryable() == null);
        k.t = 0.2;
        try std.testing.expect(k.parryable() == null);
    }
}

test "EACH STROKE'S DECLARED REACH IS WHAT THE KIT ACTUALLY ARRIVES AT" {
    // `reachOut` is the AI's trigger radius AND the parry window's reach, so it may never promise LESS than
    // the blow delivers (a stroke that reaches past its own window is unparryable at its own tip) and never
    // much more (a trigger radius the kit cannot cross is a committed second spent on a guaranteed miss).
    const dt = 1.0 / 600.0;
    const strikeOf = [_]State{ .sweep, .over, .thrust, .bash, .sweep2, .swat };
    for (MOVES, 0..) |a, mv| {
        var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
        k.atk = mv;
        k.windHold = 0;
        // The SWAT's reach is its SWORD-side picture: the blade goes further than the door does, so that is
        // the one the declared radius has to cover.
        k.swatShield = false;
        k.state = strikeOf[mv];
        k.t = 0;
        var reached: f32 = 0;
        while (k.t <= a.strikeDur) : (k.t += dt) {
            k.setStrike(foe.swingCurve(mathx.clampF(k.t / a.strikeDur, 0, 1)));
            k.pose();
            const seg = if (mv == BASH_I) k.shieldSeg() else k.weaponSeg();
            for (seg) |p| reached = mathx.maxF(reached, mathx.distXZ(k.pos, p));
        }
        const declared = a.reachOut * k.scale;
        std.debug.print("\n  {s}: declared {d:.2} m, kit arrives {d:.2} m\n", .{ moveName(mv), declared, reached });
        try std.testing.expect(declared >= reached - 0.05);
        try std.testing.expect(declared <= reached + 0.65);
    }
}

fn moveName(mv: usize) []const u8 {
    return switch (mv) {
        SWEEP_I => "sweep ",
        OVER_I => "over  ",
        THRUST_I => "thrust",
        BASH_I => "bash  ",
        else => "sweep2",
    };
}

test "EVERY STROKE COMES DOWN INTO THE HERO'S OWN HEIGHT BAND — a giant's kit swung at a giant's height MISSES" {
    // A five-metre creature authored entirely in its own units sweeps its kit through ITS chest, which is
    // 2.5 m over the head of the man it is swinging at (owner: the swings go right over my head). Outward
    // reach was measured and pinned; the HEIGHT never was, and it is the half that decides whether a blow can
    // land at all. Every live stroke must dip to somewhere a 1.8 m body actually occupies.
    const dt = 1.0 / 120.0;
    const strikeOf = [_]State{ .sweep, .over, .thrust, .bash, .sweep2, .swat };
    for (MOVES, 0..) |a, mv| {
        var k = Knight.spawn(mathx.ground(0, 0), 0, 1.0, 0.33);
        k.windHold = 0;
        k.atk = mv;
        k.swatShield = false; // the sword-side picture: the one that has to reach a man's chest
        k.state = strikeOf[mv];
        k.t = 0;
        var lowest: f32 = 1e9;
        while (k.t <= a.strikeDur) : (k.t += dt) {
            k.setStrike(foe.swingCurve(mathx.clampF(k.t / a.strikeDur, 0, 1)));
            k.pose();
            const seg = if (mv == BASH_I) k.shieldSeg() else k.weaponSeg();
            for (seg) |p| lowest = mathx.minF(lowest, p.y - k.pos.y);
        }
        // NOT "below his crown" — that is a graze off the top of his head and it is what the bash was doing.
        // It has to arrive where a body IS, so: chest height on a standing hero.
        std.debug.print("\n  {s}: kit dips to {d:.2} m (hero crown {d:.2}, chest {d:.2})\n", .{ moveName(mv), lowest, heromod.H, heromod.H * 0.62 });
        try std.testing.expect(lowest < heromod.H * 0.62);
    }
}

test "EVERY BONE GETS A MATRIX IN EVERY STATE, and the body really does go over and come back up" {
    var k = Knight.spawn(mathx.ground(3, -2), mathx.radians(40), 1.0, 0.41);
    const crown = k.topWorld().y - k.pos.y;
    // Drive the whole fall through the state machine with the hero parked dead behind him.
    const hero = v3(3.0 - mathx.sinf(mathx.radians(40)) * 3.0, 0, -2.0 - mathx.cosf(mathx.radians(40)) * 3.0);
    k.debugFall();
    var t: f32 = 0;
    var lowest = crown;
    var wasDown = false;
    while (t < FALL_WIND_DUR + FALL_DUR + DOWN_DUR + ROLL_DUR + RISE_DUR + 0.3) : (t += 1.0 / 60.0) {
        _ = k.update(1.0 / 60.0, hero, 200.0, .{});
        for (k.xf) |m| try std.testing.expect(!std.math.isNan(m.m12) and !std.math.isNan(m.m13));
        const h = k.topWorld().y - k.pos.y;
        lowest = mathx.minF(lowest, h);
        if (k.state == .downed) wasDown = true;
    }
    try std.testing.expect(wasDown);
    // FLAT ON HIS BACK the helm is near the ground and the body is BEHIND him — not standing, not sunk.
    try std.testing.expect(lowest < crown * 0.35);
    try std.testing.expect(lowest > -0.6);
    // …and he is back on his feet at the end of it, with the fall on its cooldown.
    try std.testing.expectApproxEqAbs(crown, k.topWorld().y - k.pos.y, crown * 0.12);
    try std.testing.expect(k.fallCd > 0);
}

test "THE PUNISH WINDOW IS REAL — flat on his back, the mark and the hurt sphere come down with him" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const standMark = k.lockPoint().y;
    const standHurt = k.centerWorld().y;
    k.state = .downed;
    k.t = DOWN_DUR * 0.5;
    k.easeFloored(1.0);
    k.pose();
    try std.testing.expect(k.lockPoint().y < standMark * 0.4);
    try std.testing.expect(k.centerWorld().y < standHurt * 0.4);
    // …and the body is behind his feet, which is where the player has to stand to use the window.
    try std.testing.expect(k.centerWorld().z < -k.bodyR() * 0.5);
    // The door is DOWN the whole time he is off his feet: this window is not one you have to walk round.
    for ([_]State{ .fall, .downed, .rollover, .rise }) |s| {
        k.state = s;
        try std.testing.expect(!k.guardUp());
    }
    // …and the SLAM is the other way in — the door itself leaves the fight.
    k.state = .slam;
    try std.testing.expect(!k.guardUp());
    // THE COMMITTED SWIPES OPEN HIS FRONT AND THE REST DO NOT. The reference's condition is the whole
    // sentence — impossible from the front "IF THEY'RE NOT IN AN ATTACK ANIMATION" — so a stroke is the
    // player's frontal window, and the thrust (past the door's edge) and the bash (the door IS the blow)
    // are the two that keep it.
    for ([_]struct { s: State, mv: usize }{
        .{ .s = .sweep, .mv = SWEEP_I },
        .{ .s = .sweep2, .mv = SWEEP2_I },
        .{ .s = .over, .mv = OVER_I },
    }) |c| {
        k.state = c.s;
        k.atk = c.mv;
        k.t = 0;
        try std.testing.expect(k.guardUp()); // …still shut on the first frame: the arm has to carry it out
        k.t = k.move().strikeDur;
        try std.testing.expect(!k.guardUp());
    }
    for ([_]State{ .thrust, .bash, .charge, .hop }) |s| {
        k.state = s;
        for ([_]f32{ 0, 0.12, 0.24 }) |t| {
            k.t = t;
            try std.testing.expect(k.guardUp());
        }
    }
}

test "THE DOOR IS SEEN TO LEAVE — the picture of the guard cannot disagree with the guard" {
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    // Square to his front for everything he does standing behind it — the walk, the gathers, the two strokes
    // thrown from behind the wall, and the charge that IS the wall.
    for ([_]State{ .idle, .approach, .hop, .sweepwind, .chainwind, .overwind, .thrustwind, .thrust, .bashwind, .bash, .chargewind, .charge, .brake, .fallwind }) |s| {
        k.state = s;
        for ([_]f32{ 0, 0.2 }) |t| {
            k.t = t;
            try std.testing.expect(k.guardUp());
            try std.testing.expectApproxEqAbs(@as(f32, 0), k.slamLift(), 1e-6);
            try std.testing.expectApproxEqAbs(@as(f32, 0), k.swipeOpen(), 1e-6);
        }
    }
    // …AND THE SWIPES CARRY IT OFF HIS FRONT, picture and mechanic on one channel. The door is gone before
    // the blade arrives, still gone at the end of the stroke, and back by the end of the recovery — and
    // `guardUp` flips exactly where `swipeOpen` crosses its half, which is what "seen to leave" means.
    for ([_]struct { s: State, mv: usize }{
        .{ .s = .sweep, .mv = SWEEP_I },
        .{ .s = .sweep2, .mv = SWEEP2_I },
        .{ .s = .over, .mv = OVER_I },
    }) |c| {
        k.state = c.s;
        k.atk = c.mv;
        const a = k.move();
        k.t = 0;
        try std.testing.expectApproxEqAbs(@as(f32, 0), k.swipeOpen(), 1e-6);
        k.t = a.strikeDur * a.impactK;
        try std.testing.expect(k.swipeOpen() > 0.5); // open BEFORE the kit goes live, or it is no window
        k.t = a.strikeDur;
        try std.testing.expect(k.swipeOpen() > 0.99 and !k.guardUp());
        // …and the recovery holds it open through its head — the punish window is the recovery.
        k.state = .recover;
        k.blow = switch (c.mv) {
            SWEEP_I => .sweep,
            SWEEP2_I => .sweep2,
            else => .over,
        };
        k.t = 0;
        try std.testing.expect(k.swipeOpen() > 0.99 and !k.guardUp());
        k.t = k.recoverDur();
        try std.testing.expectApproxEqAbs(@as(f32, 0), k.swipeOpen(), 1e-6);
        try std.testing.expect(k.guardUp());
    }
    // …and HAULED OFF IT for the slam: the guard opens WHILE the haul is still climbing — a front that
    // opened on the impact frame would be a front that was never open — and the door is fully lifted
    // through the strike.
    k.state = .slamwind;
    k.t = SLAM.windDur * 0.6;
    try std.testing.expect(!k.guardUp());
    try std.testing.expect(k.slamLift() > 0.5);
    k.state = .slam;
    k.t = 0;
    try std.testing.expect(!k.guardUp());
    try std.testing.expectApproxEqAbs(@as(f32, 1), k.slamLift(), 1e-6);
    // A sword move's recovery keeps the guard (it never left); the slam's brings the door back up over it.
    k.state = .recover;
    k.t = 0;
    k.blow = .bash;
    try std.testing.expect(k.guardUp() and k.slamLift() == 0);
    k.blow = .slam;
    try std.testing.expect(!k.guardUp());
    try std.testing.expect(k.slamLift() > 0.9);
    k.t = SLAM.recoverDur;
    try std.testing.expectApproxEqAbs(@as(f32, 0), k.slamLift(), 1e-6);
    // Off his feet the door goes down WITH him — the topple is what moves it, never the lift.
    for ([_]State{ .fall, .downed, .rollover, .rise }) |s| {
        k.state = s;
        k.t = 0.3;
        try std.testing.expectApproxEqAbs(@as(f32, 0), k.slamLift(), 1e-6);
    }
}

test "NO ATTACK COMES OUT OF NOWHERE, and the fall's tell is the longest thing he does" {
    for (MOVES) |a| try std.testing.expect(a.windDur >= foe.TELL_MIN);
    try std.testing.expect(SLAM.windDur >= foe.TELL_MIN);
    try std.testing.expect(CHARGE.windDur >= foe.TELL_MIN);
    try std.testing.expect(FALL_WIND_DUR >= foe.TELL_MIN);
    // **AND IT IS LONGER THAN EVERY WIND HE HAS** (owner: it needs more tell). The old assertion asked only
    // that the whole countdown beat 0.65 of a wind, which let the one move with no parry and no block behind
    // it be the one you got least time to read. Its counter is the ROLL and the read, so the read has to be
    // worth more than any of them — the slam's haul and the charge's dig included.
    for (MOVES) |a| try std.testing.expect(FALL_WIND_DUR > a.windDur);
    try std.testing.expect(FALL_WIND_DUR > SLAM.windDur);
    try std.testing.expect(FALL_WIND_DUR > CHARGE.windDur);
    // AND THE AFTERMATH IS THE REWARD: the longest opening in the game, and longer than any recovery he has.
    const opening = DOWN_DUR + ROLL_DUR + RISE_DUR;
    for (MOVES) |a| try std.testing.expect(opening > a.recoverDur * 2.0);
    try std.testing.expect(opening > SLAM.recoverDur * 1.8);
    try std.testing.expect(opening > CHARGE.brakeDur + CHARGE.recoverDur);
    try std.testing.expect(opening > combat.FOE_HEAVY_STUN_DUR);
    // …and he cannot spend it twice in a row: the cooldown outlasts getting up.
    try std.testing.expect(FALL_CD > opening);
    // THE FALL STAYS THE HEAVIEST THING HE DOES — `game.BLOW_HEAVIEST` and the felt-beat split both key off
    // it, so no new move may quietly out-poise the body itself landing on you.
    for (MOVES) |a| try std.testing.expect(FALL_HIT.poise > a.hit.poise and FALL_HIT.stance > a.hit.stance);
    try std.testing.expect(FALL_HIT.poise > SLAM_HIT.poise and FALL_HIT.stance > SLAM_HIT.stance);
    try std.testing.expect(FALL_HIT.poise > CHARGE_HIT.poise and FALL_HIT.stance > CHARGE_HIT.stance);
    // THE THRUST IS THE GAP-FILLER: the shortest clock he has, or a spacing fight is a staring contest.
    for ([_]usize{ SWEEP_I, OVER_I, BASH_I }) |i| try std.testing.expect(THRUST.cd < MOVES[i].cd);
    try std.testing.expect(THRUST.cd < SLAM.cd and THRUST.cd < CHARGE.cd and THRUST.cd < FALL_CD);
}

test "HE IS OUT-TURNED, which is the only reason a flank exists at all" {
    // A hero walking a circle at his own closest approach must out-turn him, or there is no getting behind.
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const r = k.bodyR() + foe.HERO_R;
    const heroRate = heromod.WALK_SPEED / r; // rad/s the player can carry round him on foot
    try std.testing.expect(heroRate > TURN_RATE * 1.15);
    // …and a committed stroke lets go of the tracking, which is where the window actually opens.
    try std.testing.expect(SWING_TURN < TURN_RATE);
    try std.testing.expect(FALL_AIM < TURN_RATE);

    // **AND THE BASH MUST STILL LAND ON A MAN WHO IS WALKING**, which is the half nothing measured. A swing
    // that cannot reach a moving target is not a difficulty dial, it is a move that does not exist: he shed
    // 32 deg of bearing across a commit and started up to 50 deg out, so it missed every circling player.
    // Measured as the LATERAL miss at the impact frame against the kit's own half-width.
    // THE ANGLE THE RAM ITSELF SUBTENDS at the range it arrives — the one honest measure of "aimed at him",
    // because a stroke is only ever as accurate as the thing on the end of it is wide. The RAM, not the
    // wrap's whole chord: the curved edges cannot be driven into anybody.
    const kitHalf = std.math.asin(SH_RAM_HALF / BASH.reachOut);
    const commit = BASH.windDur + BASH.strikeDur * BASH.impactK;
    const drift = (heroRate - SWING_TURN) * commit; // rad of bearing the stroke loses while committed
    std.debug.print("\n  hero {d:.2} rad/s, bash commit {d:.2} s → drift {d:.0} deg; the ram subtends {d:.0} deg\n", .{
        heroRate, commit, mathx.degrees(drift), mathx.degrees(kitHalf),
    });
    // ONE: the drift a commit sheds may not BY ITSELF carry the door off a man who was squared up. It was 32
    // deg against a 25 deg door, so a player who did nothing but walk was missed by geometry alone.
    try std.testing.expect(drift < kitHalf);
    // TWO: he may not commit at a bearing his own kit does not already cover. Anything wider is a swing thrown
    // at a place the door was never going to arrive, which is a second and a half spent on a guaranteed miss.
    try std.testing.expect(mathx.radians(SWING_BEARING) <= kitHalf);
    // …and the two together are what leaves the DODGE intact: squared up you are hit, and circling out through
    // the sector edge you are not. That is the fight, and neither half of it is an accident now.

    // THE SWEEP IS NOT HELD TO THAT, AND THAT IS THE DESIGN. Its commit is over a second and its kit is a
    // blade's edge, so a walking player leaves it — the big swipe is the one you step out of (or through),
    // and the bash is the punish for standing in front of him. Pinned so the pair cannot become one move.
    try std.testing.expect(SWEEP.windDur > BASH.windDur * 1.4);
}

test "THE SLAM IS OUTRUN, NOT OUT-TRADED — a run clears the crater's disc and a walk does not" {
    // The delver's law with the door for a fist, measured with the hero's own numbers: from the WORST spot
    // (standing on the very mark the door will land on), the haul plus the lead-in to the earth answering
    // is enough for a RUN to be outside the disc with margin — and deliberately NOT enough for a WALK.
    const k = Knight.spawn(mathx.zero3, 0, 1.0, 0.3); // faces +Z
    const tell = SLAM.windDur + SLAM.strikeDur * SLAM.impactK;
    const ring = SLAM.r * k.scale + HERO_REACH;
    std.debug.print("\n  slam: disc {d:.2} m, tell {d:.2} s -> run reaches {d:.2}, walk {d:.2}\n", .{
        ring, tell, heromod.RUN_SPEED * tell, heromod.WALK_SPEED * tell,
    });
    try std.testing.expect(heromod.RUN_SPEED * tell > ring + 0.4);
    try std.testing.expect(heromod.WALK_SPEED * tell < ring - 0.1);
    // …and the blow is the DISC round the crater it claims: inside is hit, outside is not — and it reaches
    // a little past his own boots (the Tower Knight's slam hits "even a few paces behind him"), so hugging
    // his back through the haul is not the answer either. The answer is leaving.
    var s = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    const mark = s.slamMark();
    s.heroHit = null;
    s.trySlam(v3(mark.x, 0, mark.z + ring - 0.2));
    try std.testing.expect(s.heroHit != null);
    s.heroHit = null;
    s.trySlam(v3(0, 0, -1.0)); // a stride behind his own heels: still inside the disc
    try std.testing.expect(s.heroHit != null);
    s.heroHit = null;
    s.trySlam(v3(mark.x, 0, mark.z + ring + 0.3));
    try std.testing.expect(s.heroHit == null);
}

test "THE CHARGE ANSWERS STAYING AWAY, AND THE LINE IS COMMITTED AT THE LAUNCH" {
    // A player who KEEPS his distance — really keeps it, frame by frame — is what fills the fuse: the test
    // kites him at 13 m, which no amount of his own walking can close, and the charge must come.
    var k = Knight.spawn(mathx.zero3, 0, 1.0, 0.31);
    k.leash.provoke(); // an arrow from range is how this fight usually starts
    const dt = 1.0 / 60.0;
    var t: f32 = 0;
    var launched = false;
    var hero = v3(0, 0, 13.0);
    while (t < 14.0 and !launched) : (t += dt) {
        _ = k.update(dt, hero, 400.0, .{});
        const away = mathx.dirXZ(k.pos, hero);
        const norm = if (mathx.lenXZ(away) > 1e-3) away else v3(0, 0, 1);
        hero = v3(k.pos.x + norm.x * 13.0, 0, k.pos.z + norm.z * 13.0); // the kite: always 13 m off him
        if (k.state == .chargewind) launched = true;
    }
    try std.testing.expect(launched);
    // Let the wind finish aiming, then note the committed line and KEEP MOVING the hero sideways: the
    // travel may not bend after it — the sidestep must win by construction, not by a tuning accident.
    while (k.state == .chargewind) : (t += dt) _ = k.update(dt, hero, 400.0, .{});
    try std.testing.expectEqual(State.charge, k.state);
    const line = k.facing;
    const lenAtLaunch = k.chargeLen;
    var ran: f32 = 0;
    while (k.state == .charge) : (t += dt) {
        const side = v3(k.pos.x - mathx.headingDir(line).z * 8.0, 0, k.pos.z + mathx.headingDir(line).x * 8.0);
        _ = k.update(dt, side, 400.0, .{});
        try std.testing.expectApproxEqAbs(line, k.facing, 1e-4); // NO steering, none at all
        // `enter(.brake)` zeroes `strokeDone` on the transition frame, so the run's length is its peak.
        ran = mathx.maxF(ran, k.strokeDone);
    }
    std.debug.print("\n  charge: committed {d:.1} m, ran {d:.1} m, then the skid\n", .{ lenAtLaunch, ran });
    try std.testing.expectApproxEqAbs(lenAtLaunch, ran, 0.30); // it covers the line it promised…
    try std.testing.expectEqual(State.brake, k.state); // …and pays for the stop
    while (k.state == .brake or k.state == .recover) : (t += dt) _ = k.update(dt, hero, 400.0, .{});
    try std.testing.expect(k.chargeCd > 0); // …and cannot turn straight round and do it again
    try std.testing.expect(k.farT < CHARGE.patience); // the fuse was spent, not banked
}

test "NO FOLLOW-UP CHAINS AT A MAN WHO IS ALREADY BEHIND HIM" {
    // The chain is a ROLL, so what is tested is the constraint and not the dice: with the hero walked round
    // his back by the time the sweep lands, no seed may hand him a second stroke at empty air.
    var seed: f32 = 0.05;
    while (seed < 1.0) : (seed += 0.17) {
        var k = Knight.spawn(mathx.zero3, 0, 1.0, seed);
        k.debugSweep();
        const dt = 1.0 / 60.0;
        var t: f32 = 0;
        const behind = v3(0, 0, -6.0); // he faces +Z and turns at 0.58 rad/s: this stays behind him
        while (t < SWEEP.windDur + SWEEP.strikeDur + 0.1) : (t += dt) {
            _ = k.update(dt, behind, 400.0, .{});
            try std.testing.expect(k.state != .chainwind and k.state != .sweep2);
        }
    }
}

test "THE GUARD COUNTER ANSWERS THE DOOR AND ONLY THE DOOR — and never off a body already committed" {
    // A blow CAUGHT ON THE SHIELD may buy an immediate thrust (the reference's guard counter). It reads a
    // blow that landed on his own body, never the player's buttons — and a knight mid-move or mid-stagger
    // has no counter to give, so the trigger lives in `caught` alone.
    var found = false;
    var seed: f32 = 0.03;
    while (seed < 1.0) : (seed += 0.11) {
        var k = Knight.spawn(mathx.zero3, 0, 1.0, seed);
        k.state = .idle;
        k.covered = true;
        const p = v3(0, 2.6, k.hurtRadius() * 0.5); // square onto the front: the door eats it
        k.tryHit(.{ .active = true, .r = 0.2, .a = p, .b = p, .a0 = p, .b0 = p, .hit = .{ .dmg = 10, .poise = 5, .stance = 4 } });
        try std.testing.expectEqual(@as(u32, 1), k.blocks);
        if (k.state == .thrustwind) {
            found = true;
            try std.testing.expect(k.riposteCd > 0); // …and it is clocked, so the front is not a metronome
        } else {
            try std.testing.expectEqual(State.idle, k.state); // refused rolls leave him exactly as he was
        }
    }
    try std.testing.expect(found); // across nine seeds the 60% roll must fire at least once
    // …and a blow on the door of a knight already swinging changes nothing about his stroke.
    var mid = Knight.spawn(mathx.zero3, 0, 1.0, 0.3);
    mid.debugSweep();
    mid.covered = true;
    const q = v3(0, 2.6, mid.hurtRadius() * 0.5);
    mid.tryHit(.{ .active = true, .r = 0.2, .a = q, .b = q, .a0 = q, .b0 = q, .hit = .{ .dmg = 10, .poise = 5, .stance = 4 } });
    try std.testing.expectEqual(State.sweepwind, mid.state);
}

test "EVERY NEW STATE POSES EVERY BONE — the slam, the hop and the charge drive clean through" {
    var k = Knight.spawn(mathx.ground(2, 1), mathx.radians(30), 1.0, 0.4);
    const hero = mathx.ground(2, 9);
    const dt = 1.0 / 60.0;
    k.debugSlam();
    var t: f32 = 0;
    var ringPeak: usize = 0;
    while (t < SLAM.windDur + SLAM.strikeDur + SLAM.recoverDur + 0.2) : (t += dt) {
        _ = k.update(dt, hero, 400.0, .{});
        for (k.xf) |m| try std.testing.expect(!std.math.isNan(m.m12) and !std.math.isNan(m.m13));
        var live: usize = 0;
        for (k.parts) |p| {
            if (p.life > 0) live += 1;
        }
        ringPeak = @max(ringPeak, live);
    }
    // The disc is DRAWN BY THE DUST (`slamCrater`), so a slam that emitted nothing is a blow with no picture.
    std.debug.print("\n  slam fx: {d} particles live at the peak\n", .{ringPeak});
    try std.testing.expect(ringPeak >= 30);
    k.debugHop(1.0);
    t = 0;
    const before = k.pos;
    while (t < HOP.windDur + HOP.airDur + HOP.settleDur + 0.1) : (t += dt) {
        _ = k.update(dt, hero, 400.0, .{});
        for (k.xf) |m| try std.testing.expect(!std.math.isNan(m.m12) and !std.math.isNan(m.m13));
    }
    // The hop MOVED him — roughly its own promised ground, sideways — and clean back to a standing state.
    std.debug.print("  hop: covered {d:.2} m of {d:.2} promised\n", .{ mathx.distXZ(before, k.pos), HOP.dist * k.scale });
    try std.testing.expect(mathx.distXZ(before, k.pos) > HOP.dist * k.scale * 0.7);
    k.debugCharge();
    t = 0;
    var wakePeak: usize = 0;
    while (t < CHARGE.windDur + CHARGE.range / CHARGE.speed + CHARGE.brakeDur + CHARGE.recoverDur + 0.2) : (t += dt) {
        _ = k.update(dt, hero, 400.0, .{});
        for (k.xf) |m| try std.testing.expect(!std.math.isNan(m.m12) and !std.math.isNan(m.m13));
        if (k.state == .charge) {
            var live: usize = 0;
            for (k.parts) |p| {
                if (p.life > 0) live += 1;
            }
            wakePeak = @max(wakePeak, live);
        }
    }
    // The travel is DRESSED BY ITS WAKE (`chargeWake`) — a wall crossing ground with nothing coming off it
    // is a mesh sliding, and the mass is the whole read.
    std.debug.print("  charge fx: {d} wake particles live at the peak\n", .{wakePeak});
    try std.testing.expect(wakePeak >= 16);
}
