const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const foe = @import("foe.zig");
const wf = @import("../world/worldfmt.zig");
const heromod = @import("../play/hero.zig");
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

// THE FLORID RAVAGER (owner's creature, owner's name) — a big hound carrying a flower where its head should be.
//
// **THE QUADRUPED RIG'S SECOND USER**: the bone layout, rest chain, gait dials, limb solver and leap all come
// from `wolf.zig`. Its own are a STATURE, a STALK and a BLOOM — the bloom's four extra bones sit ABOVE wolf's 27
// so `wolf.legs` still takes the first 27 as its own array.
//
// **SHUT IT IS A BUD, AND A BUD IS A MUZZLE.** Seven petals folded past parallel close into a tapered spear on a
// two-metre stalk; from across a field that silhouette is a long-necked dog. The flower is not what it looks
// like — it is what it DOES, once, in the half-second before it comes at you.
//
// **THE BLOOM IS THE TELL, THE TELL IS THE WINDOW, AND IT IS THE ONLY TIME IT OPENS** (owner) — the leap's own
// wind-up and a heavy stun, nothing else. Open, the throat is bare and every blow lands harder (`frailty`).

/// Height at the WITHERS. Over Hildebrand's 1.12 (owner: LARGE dogs) — it stands about as tall as the hero's chest, which is what makes the head coming at you a head and not a knee.
pub const W: f32 = 1.34;

pub const AGGRO_R: f32 = 11.0;
const HOME_R: f32 = 1.2;

const BODY_R: f32 = 0.46;
/// **IT HAS TO HOLD THE STALK AS WELL AS THE BODY.** Sized for a ribcage it stopped at 1.4 m and the neck and bloom — a third of the creature — were outside any sword. Solved to span 0.83 m up to 2.17 m.
const HURT_R: f32 = 0.92;
const CENTER_F: f32 = 1.05;
const TOP_F: f32 = 1.66;

/// **TOUGH IN THE BODY, NOTHING IN THE STALK** (owner: tougher but poisebreak easily) — a long time to kill, and it comes apart the moment you interrupt it.
const HP_MAX: f32 = 88.0;
/// **AND IT HAS TO SIT BETWEEN THE HERO'S TWO SWINGS**, not under both: at 9 a light poke flinched it. His light is 10 poise and his heavy 22, so 12 is as low as "breaks easily" can go and still mean the HEAVY breaks it.
const POISE_MAX: f32 = 12.0;
const STANCE_MAX: f32 = 40.0;
const RESISTS = combat.resists(.{ .fire = -45, .cold = 30, .lightning = 0, .chaos = 20 });

const SOULS: u32 = 190;

const DEATH_DUR: f32 = 1.25;
const DISS_DUR: f32 = 1.05;
const DISSOLVE = foe.Dissolve{ .rate = 58.0, .spread = 0.9, .rise = 0.85, .flake = PETAL_LT };
/// Metres of the body's own scale it settles by as it goes (`foe.rigSink`) — between the toad's 0.30 and the ogre's 0.95, which is where a dog-sized carcass belongs.
const SINK_DEPTH: f32 = 0.34;

/// Sized off what feeds it: `DISSOLVE.rate` 58/s against a mean mote life of ~0.72 s stands about 42 at the fade's start, and a wound into an open throat sheds 13 in one frame.
const PARTS = 58;

const BITE_WIND: f32 = 0.38;
const BITE_STRIKE: f32 = 0.18;
const BITE_RECOVER: f32 = 0.46;
const BITE_COOL: f32 = 0.85;
/// Metres of forward travel across the wind and the strike — further than the wolf's 0.62, because this is a bigger animal and the leap is the move.
const BITE_HOP: f32 = 0.86;
const BITE_R: f32 = 1.55;
const BITE_TRIGGER_R: f32 = BITE_R + BITE_HOP * 0.8;

/// **THE LEAP'S THREE INSTANTS, NAMED ONCE.** Written out as `BITE_WIND + BITE_STRIKE` at six sites and
/// `BITE_WIND * 0.55` at three, the pose, the mechanic, the airborne gate and the staged photograph were four copies of one clock that had to agree by hand.
const LAUNCH_T: f32 = BITE_WIND * 0.55;
const HOP_END: f32 = BITE_WIND + BITE_STRIKE;
const APEX_T: f32 = (LAUNCH_T + HOP_END) * 0.5;

comptime {
    std.debug.assert(BITE_WIND >= foe.TELL_MIN);
    std.debug.assert(BITE_WIND * OPEN_BY < LAUNCH_T);
    std.debug.assert(CLAMP_BY < OPEN_BY and OPEN_BY < SETTLE_BY and SETTLE_BY < 1.0);
}

/// **THE GATE IS MEASURED FROM THE QUARRY'S HIDE** (`wolf.triggerR`'s law): asked centre-to-centre a flat radius is unsatisfiable on anything broad, because `env.resolveActor` holds the body `bodyR + its own` out.
pub fn triggerR(quarryR: f32) f32 {
    return BITE_TRIGGER_R + quarryR;
}
/// The one dial the halt sits on, named for the same reason the skitterer's and the hollow's are.
const STOP_FRAC: f32 = 0.85;
fn stopR(quarryR: f32) f32 {
    return BITE_R * STOP_FRAC + quarryR;
}
comptime {
    std.debug.assert(stopR(foe.HERO_R) < triggerR(foe.HERO_R));
}

const BITE_HIT = combat.Hit{ .dmg = 24, .poise = 20, .stance = 9 };

// **THE CLAWS, WHICH IT HAS AND NEVER USED.** The leap is committed at the launch and steers not at all, so
// the safe ground was always its FLANK. This answers there and ONLY there — off the front, close, paws down.
// The bud stays SHUT through the whole thing (every bloom clock gates on `.bite`), so the tell is the SHOULDER
// DROPPING — and a swipe carries no window, because the window is the flower.
const RAKE_WIND: f32 = 0.46;
const RAKE_STRIKE: f32 = 0.20;
const RAKE_RECOVER: f32 = 0.62;
const RAKE_COOL: f32 = 2.0;
/// Where in the swipe the paw arrives, as a share of it — the ONE frame the boards are asked about (`foe.PARRY_LEAD` back from here), and where its signed paw clock crosses zero.
const RAKE_IMPACT_K: f32 = 0.5;
/// A paw's reach round its own shoulder — well under the bite's 1.55, and it brings no travel with it.
const RAKE_R: f32 = 1.15;
/// HOW FAR OFF ITS NOSE THE HERO HAS TO BE for this to be the answer instead of the leap: cos 55 deg. Inside that cone the bloom is the move and this may not fire at all.
const RAKE_OFF_DOT: f32 = 0.574;
/// …and how wide the swept paw answers for, cos 84 deg — a foreleg dragged across the front covers most of one side of the animal.
const RAKE_FRONT_DOT: f32 = 0.10;
/// The fast one. The bloom is the heavy blow (`stance` 9) and this has no stance at all: it is the tax on standing at its shoulder, not a second way to be flattened.
const RAKE_HIT = combat.Hit{ .dmg = 12, .poise = 14 };

// Degrees. `RAKE_SWING` is the paw's travel either side of straight down, `RAKE_LIFT` how far the leg comes off the earth, and the last three the fold that opens through the blow — the foreleg goes LONG at the arrival.
const RAKE_SWING: f32 = 62.0;
const RAKE_LIFT: f32 = 46.0;
const RAKE_ELBOW: f32 = 54.0;
const RAKE_CARPUS: f32 = 38.0;
const RAKE_PAW: f32 = 26.0;

comptime {
    std.debug.assert(RAKE_WIND >= foe.TELL_MIN);
    std.debug.assert(RAKE_R < BITE_R);
}

// One scalar (`openAmt`), 0 shut to 1 wide, and it is allowed OUT of that range at both ends: a bud tightens
// before it bursts and a mass in motion overshoots its rest.

/// Share of the wind spent TIGHTENING. An anticipation, and it is short on purpose: it eats the front of the tell, and the tell is what the player is owed.
const CLAMP_BY: f32 = 0.15;
/// …and how far under shut the tightening goes, in units of `openAmt`.
const BLOOM_CLAMP: f32 = 0.17;
/// **WIDE BEFORE IT LEAVES THE EARTH.** `LAUNCH_T` is 0.55 of the wind, so the burst has to finish inside
/// 0.209 s or the animal is airborne before the flower has said anything: 0.38 x 0.42 = 0.160 s, which is
/// 0.049 s of hold on the ground and 0.220 s before the blade is live. The comptime assert is what caught a
/// 0.70 that read as a tell it was not.
const OPEN_BY: f32 = 0.42;
/// …and where the fling has settled back onto wide. Inside the wind, so the strike opens on a bloom at rest.
const SETTLE_BY: f32 = 0.64;
/// How far past wide it flings before settling back onto it (the overshoot law).
const BLOOM_SNAP: f32 = 0.15;
/// Share of the recovery the shut takes.
const SHUT_BY: f32 = 0.75;
/// AND IT STREAMS IN FLIGHT — airspeed drags the petals a little further back over the arc.
const BLOOM_DRAG: f32 = 0.12;
/// **A HEAVY STUN BLOWS IT OPEN** (owner). On `foe.stunCurve`'s heavy shape, so the flower is wide for the same frames the body is helpless; a LIGHT flinch leaves the bud shut, which is what keeps the window worth aiming for.
const BLOOM_STUN: f32 = 1.06;
/// Degrees of shiver on top of it, and how fast — a flower held open by nothing but shock does not hold still.
const SHIVER_DEG: f32 = 7.0;
const SHIVER_HZ: f32 = 9.5;
/// Seconds the dead bloom takes to wilt shut from wherever the blow caught it.
const WILT_DUR: f32 = 0.55;

// **MEASURED OFF THE TWO PORTRAITS** (`shots.runMapShots`, `_face` and `_facemove`), because "the tell reads" is
// the one claim arithmetic cannot make: counting throat-hued pixels (R > G + 55, R > 150) over the head, the shut
// bud shows 283 of them peaking at luma 145 and the open flower 1112 peaking at 211. Four times the lit area and
// 66 luma at the peak — which is what the tongues sealing the bud buys, and what a leaking one would give away.

/// **THE BLOOM IS THE WEAK POINT** (owner: it takes more damage at this moment). Wide open, a blow is worth
/// 1.9x — the throat is bare and there is no petal over it. DAMAGE ONLY: `poise` and `stance` are left alone on
/// purpose, because `POISE_MAX` is solved to sit between his two swings and a multiplier here would quietly put
/// a light poke through it.
///
/// **AND THE STUN'S WINDOW IS THE BIG ONE.** A heavy break holds the flower open for most of `foe.stunCurve`'s
/// heavy shape, so two of his heavies inside it are ~84 of an 88 HP pool. That IS the fight — break the stance,
/// then burst the throat — and it is why the body is tough and the stalk is not.
const BLOOM_FRAIL: f32 = 0.90;

const TURN_RATE: f32 = 4.4; // rad/s — big and slower on its feet than the spirit's 5.6
const ACCEL: f32 = 7.5;
const GAIT_BLEND: f32 = 8.0;
/// It closes at a run and holds it — the thing you cannot simply walk away from.
const CHASE_SPEED: f32 = wolf.GALLOP_SPEED * 0.78;

pub const SHOVE = foe.Push{ .light = 1.20, .heavy = 2.90 };
const SHOVE_DECAY: f32 = 6.0;

/// The cosine of the frontal cone (the toad's own dial). 0.25 is about 76 degrees either side, which is a ring of petals rather than a point.
const BITE_FRONT_DOT: f32 = 0.25;

const N = wolf.N + 4;
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
/// **THE FOUR THE QUADRUPED HAS NO USE FOR.** Appended ABOVE wolf's 27, so `wolf.legs` still takes `wx[0..wolf.N]` as its own array and no bone it solves has moved.
const PET3 = wolf.N + 0;
const PET4 = wolf.N + 1;
const PET5 = wolf.N + 2;
const PET6 = wolf.N + 3;

/// Wolf's, plus four more hung off the head. A muzzle and a pair of ears are three bones this creature has no
/// use for and seven petals is what it needs, so the JAW and both EARS are re-let as petals rather than left nodding on a flower.
const PARENT = wolf.PARENT ++ [_]i32{ HEAD, HEAD, HEAD, HEAD };

comptime {
    std.debug.assert(PARENT.len == N);
}

const LOCK_AT = v3(0, 0.335 * W, 0.15 * W);

const NECK_UP: f32 = 1.62;
const NECK_OUT: f32 = 0.30;
/// Share of the way from shoulder to head. Under 0.5 puts the bend low and the top run long, which is what a stalk looks like and a swan's neck does not.
const NECK_MID: f32 = 0.42;

const NECK_STRETCH: f32 = 0.26;
/// Share of the wind the rear takes. Fully extended before the launch, so the gather is the reach and the leap is only the release.
const REAR_BY: f32 = 0.78;

/// Degrees the whole head chain pitches forward and under across the strike. It has to be big: reared and
/// stretched the bloom rides at 3.3 m, a metre and a half over the top of his head, and a creature that leapt from there would pass clean over him. The rear is the TELL and the dive is the BLOW.
const STRIKE_DIVE: f32 = 108.0;
const DIVE_BY: f32 = 0.55;
/// How much of the neck's reach the dive takes back. High: the gather is the extension and the blow is the fold, and the two sharing one 0..1 is what keeps them from telling different stories.
const DIVE_COIL: f32 = 0.50;
const BODY_DIVE: f32 = 26.0;

/// Fraction of `W` the whole animal sinks through the gather — deeper than the spirit's 0.09 because it is a bigger body loading a longer leap, and the sink IS the wind-up.
const CROUCH: f32 = 0.13;
/// Degrees the forequarters drop into the gather. A pouncing dog loads the hind and puts its chest on the earth; a body that only sinks reads as a lift.
const GATHER_PITCH: f32 = 15.0;
/// Degrees the stalk hauls BACK over the gather, and how far round it coils while it does. The coil's SIDE alternates leap to leap, so no two wind-ups off one animal are the same shape.
const REAR_DEG: f32 = 26.0;
const COIL_DEG: f32 = 24.0;

/// **THE LANDING IS THE OTHER HALF OF THE LEAP.** Seconds of absorb after touchdown, how deep the forelegs take
/// it, and how far the body pitches into it — one decaying oscillation, so the mass overshoots its rest and settles back on it instead of gliding to a stop.
const LAND_DUR: f32 = 0.30;
const LAND_SINK: f32 = 0.085;
const LAND_PITCH: f32 = 13.0;

/// Degrees of idle drift, and how slowly the drift runs. `mathx.gutter`'s three incommensurate rates, so a
/// standing thicket of them never falls into step.
const SWAY_DEG: f32 = 4.6;
const SWAY_RATE: f32 = 0.42;
/// …and how far the stalk leans AT HIM while the bud is still shut. POSITION and BEARING only — the law.
const LOOK_DEG: f32 = 21.0;
const LOOK_RATE: f32 = 2.2;

/// Death, in two acts. The stalk gives out over the first third — the bloom is on the ground before the body
/// has begun to go — and then the barrel rolls off its feet.
const WILT_FOLD: f32 = 122.0;
const DEAD_ROLL: f32 = 70.0;
const DEAD_BUCKLE: f32 = 0.20;


/// One petal. `ang` is degrees round the bloom's axis with 0 at the top; `bias` is degrees of fold this one
/// carries at every open value (the one that never quite shuts is a positive bias); `gain` is its share of the
/// shared swing, so the ring does not arrive as one plate.
const Petal = struct {
    bone: usize,
    ang: f32,
    root: f32,
    len: f32,
    wide: f32,
    bias: f32,
    gain: f32,
    /// Degrees the quill bends SIDEWAYS out of its own plane, progressively along the blade. On a round section a
    /// twist about the long axis is nothing at all; a sweep is what turns a wheel of seven spokes into a swirl.
    /// SMALL, because it is bought with radius: `hypot` against the axis means 34 degrees put the SHUT bud at
    /// 0.97 m across and 0.80 m long, and a bud wider than it is long is a squid.
    sweep: f32,
    notch: f32 = 0,
    notchAt: f32 = 0.5,
    /// Degrees it hangs by once it is dead. Uneven, because a wilted corolla is never a cone.
    sag: f32 = 0,
    /// **THE VARIATION IS BETWEEN THE SEVEN, NOT ALONG ONE** (AGENTS.md): two tones alternated up a quill band it
    /// like a barber's pole, and the same two separating the QUILLS read as a flower where no two petals are the
    /// same age. 0 the dark ones, 1 the mid, 2 the bleached.
    tone: u8 = 1,
};

/// **HAND-AUTHORED, NOT STEPPED ROUND A CIRCLE.** A ring off `k/7 * 360` reads as a gear however good the quill
/// is. Gaps of 34 to 64 against a mean of 51: a crowded pair up top with the short torn one beside the crown, and
/// no gap over 64 — an earlier lay had one of 76 and the open corolla came back with a bald sector in it. Lengths
/// run 0.72 to 1.34 of the base, which is what stops seven arcs reading as one comb. The angles are the one thing
/// `restPose` and `pose` must agree on, so they are a table and never a draw.
const PETALS = [7]Petal{
    .{ .bone = JAW, .ang = 196, .root = 1.00, .len = 1.34, .wide = 1.16, .bias = 0, .gain = 1.10, .sweep = 13, .sag = 34, .tone = 1 },
    .{ .bone = EARL, .ang = 96, .root = 0.94, .len = 1.04, .wide = 0.98, .bias = -3, .gain = 0.95, .sweep = 9, .sag = 21, .tone = 0 },
    .{ .bone = EARR, .ang = 248, .root = 1.06, .len = 0.92, .wide = 0.93, .bias = 4, .gain = 1.01, .sweep = 16, .sag = 29, .tone = 1 },
    .{ .bone = PET3, .ang = 10, .root = 0.98, .len = 1.18, .wide = 1.05, .bias = -2, .gain = 1.04, .sweep = 7, .notch = 0.34, .notchAt = 0.68, .sag = 16, .tone = 2 },
    .{ .bone = PET4, .ang = 44, .root = 1.10, .len = 0.72, .wide = 0.82, .bias = 13, .gain = 0.84, .sweep = 11, .notch = 0.52, .notchAt = 0.44, .sag = 12, .tone = 0 },
    .{ .bone = PET5, .ang = 306, .root = 0.90, .len = 1.10, .wide = 1.00, .bias = -5, .gain = 0.99, .sweep = -8, .sag = 25, .tone = 1 },
    .{ .bone = PET6, .ang = 148, .root = 1.02, .len = 0.86, .wide = 0.88, .bias = 6, .gain = 0.92, .sweep = 14, .sag = 31, .tone = 2 },
};

comptime {
    var seen = [_]bool{false} ** N;
    for (PETALS) |q| {
        if (seen[q.bone]) @compileError("ravager: two petals on one bone");
        seen[q.bone] = true;
    }
    for ([_]usize{ PET3, PET4, PET5, PET6 }) |i| {
        if (!seen[i]) @compileError("ravager: an appended bone carries nothing");
    }
}

/// Degrees off the bloom's own axis. SHUT is NEGATIVE — a bud's petals converge PAST parallel, which is what
/// closes the tip, and it is solved and not picked: the quill bows 0.42 of its own length off-axis, so the tip's
/// radial is `|BLOOM_RIM + len*(0.42*cos f + sin f)|` and landing that on the axis is -33 deg. At -12 the tips
/// still stood 0.15 m out and the "bud" measured 0.52 m across — a fat cone, not a spear.
const PETAL_SHUT: f32 = -33.0;
/// …and at the other end. **A BIGGER NUMBER HERE MAKES A SMALLER FLOWER PAST A POINT**, which is the trap: that
/// same radial PEAKS at `atan(1/0.42)` = 67 deg and falls away after. At 128 the corolla swept so far back down
/// the stalk that the tips finished 0.52 m BEHIND the throat and the whole thing measured 0.76 m across. 95 puts
/// the ring at 86..108 — straddling flat, so the throat faces OUT, every quill within 41 deg of the widest fold.
const PETAL_WIDE: f32 = 95.0;

/// **QUILLED, NOT BLADED.** Flat oriented boxes came back as a pile of pale cardboard: this renderer is flat-shaded
/// and a 4 cm-thick slab has no gradient across it, so the segment joints read as folded card and the corners as
/// corners. A round tapering quill has its own shading and needs no faces — which is also what the FLESH IS ROUND
/// law says, and what a spider chrysanthemum actually is.
const PETAL_LEN: f32 = 0.48 * W;
/// **THIN, OR SEVEN OF THEM ARE ONE LUMP.** At 0.036 W the base of each quill was 9.6 cm through and the shut
/// bud came back as a fleshy slug with no grooves in it — nothing said "seven". 0.021 W is 5.6 cm on a 0.79 m
/// quill: the gaps between them are what read as a bud, and open they are seven straps and not a plate.
const QUILL_R: f32 = 0.021 * W;
const PETAL_SEGS: u32 = 8;
/// How far the quill bows off the axis over its length and again over the last of it — the RECURVE. Off the
/// tangent (2*BOW at the tip, plus 5*RECURVE): 0.24/0.18 is 54 degrees in the last inch, where 0.17/0.13 gave 42
/// and the quills came back reading as needles. Their SUM, 0.42, is the tip's own off-axis share and it is what
/// `PETAL_SHUT` and the width peak are both solved against.
const PETAL_BOW: f32 = 0.24;
const PETAL_RECURVE: f32 = 0.18;

/// **THE SECOND TIER, AND IT COSTS NO BONES.** Each petal bone carries a short broad TONGUE as well as its quill,
/// pitched this many degrees further in — baked into the mesh, so one fold drives both. Shut, the tongues cross
/// over the throat and seal the bud; open at 95 they sit at 59 and cup the light instead of lying flat away from it.
const INNER_TILT: f32 = 24.0;
/// **SOLVED SO THE TONGUE LANDS ON THE AXIS, NOT THROUGH IT.** A constant tilt is an OFFSET, so shut the tongue
/// sits at fold -57 and its tip crosses the centre: at 0.50 of the quill it came out 0.15 m the FAR side and the
/// bud grew a fringe of pale lobes pointing the wrong way. `|y'| = ilen*(0.30*cos f + sin f)` = `BLOOM_RIM` gives
/// 0.29 m at a 24-degree tilt: the long tongues just cross the axis and the short ones fall a little shy, and the
/// seven of them shut 0.26 m of the bud — which is what the throat has to hide behind, because seven THIN quills
/// converging leave gaps you can see the light through and the tell must be worth something. Open at 108 the same
/// tilt puts them at 84: a second, broader corolla inside the quills rather than a plate lying away from the light.
const INNER_LEN: f32 = 0.34;
/// …and its half-width is ABSOLUTE metres, not a multiple of the quill's: the tongues are the seal, and once the
/// quill got thin enough to read they were far too narrow to close anything. 0.20 m against a 0.135 m share of the rim is the overlap that shuts the light off.
const INNER_W: f32 = 0.075 * W;

/// Where the quills root, and how far forward of the receptacle. **THE THROAT'S OWN SIZE SETS THIS**, not the
/// other way round: a lit boss 0.29 m across cannot live inside a 0.20 m ring, and at 0.074 W it bulged out
/// through the base of the shut bud. The quills root ON the boss's shoulder instead.
const BLOOM_RIM: f32 = 0.112 * W;
const CALYX_Z: f32 = 0.052 * W;
/// The bloom's own half-width for reach and measured height — the mouth is a RADIUS, not a point.
const BLOOM_R: f32 = 0.40;

fn ringDir(angDeg: f32) rl.Vector3 {
    const a = mathx.radians(angDeg);
    return v3(-mathx.sinf(a), mathx.cosf(a), 0);
}

fn petalRoot(head: rl.Vector3, q: Petal) rl.Vector3 {
    const d = ringDir(q.ang);
    const rr = BLOOM_RIM * q.root;
    return v3(head.x + d.x * rr, head.y + d.y * rr, head.z + CALYX_Z);
}

fn foldOf(q: Petal, open: f32) f32 {
    return PETAL_SHUT + q.bias + (PETAL_WIDE - PETAL_SHUT) * q.gain * open;
}

fn rowFor(bone: usize) Petal {
    for (PETALS) |q| {
        if (q.bone == bone) return q;
    }
    unreachable;
}

fn restPose() [N]rl.Vector3 {
    var r: [N]rl.Vector3 = undefined;
    const base = wolf.restPose(W);
    for (base, 0..) |p, i| r[i] = p;
    const sh = base[CHEST];
    r[HEAD] = v3(0, NECK_UP * W, sh.z + NECK_OUT * W);
    r[NECK] = v3(0, mathx.lerpF(sh.y, r[HEAD].y, NECK_MID), mathx.lerpF(sh.z, r[HEAD].z, NECK_MID * 0.6));
    for (PETALS) |q| r[q.bone] = petalRoot(r[HEAD], q);
    return r;
}

// **AUTHOR DARK, AND SOLVE IT RATHER THAN GUESS** — screen goes as albedo^(1/2.2). MEASURED: at (38, 34, 30)
// the hide came back at 144 against ground at 112, BRIGHTER than its field. Wanted ~78, i.e. 0.54 on screen,
// 0.54^2.2 = 0.264 on the albedo.
//
// **AND ALPHA IS INVERSE EMISSIVE, NOT OPACITY** (`shaders.zig`: `emis = 1 - fragColor.a`). At the 206 this
// whole palette was authored on, every surface carried 0.19 of `base*1.35` unlit — which in sun is a 6% lift
// (78 -> 80, nothing) and in SHADOW is a floor the terminator cannot get under. That is why the body read as one
// flat grey lump. Matter goes to 248+; the throat and the stamens keep the low alpha, because they are the only
// things here that are light.
const HIDE = rgba(11, 10, 9, 250);
const HIDE_DK = rgba(6, 6, 7, 252);
const HIDE_LT = rgba(17, 14, 12, 248);
/// The one COLD note in the hide — hue separation, not another value (AGENTS.md: everything outdoors here is warm).
const BELLY = rgba(9, 10, 13, 250);
/// The stalk and the legs. MEASURED against the trunk: at (21, 20, 14) the lower legs came back at twice the
/// hide's albedo — 1.37x on screen — and the animal read as a brown barrel standing on pale green pipes. The
/// stem keeps this tone (it is a stem, and it wants to be seen); the LEGS take `LIMB` instead.
const STALK = rgba(21, 20, 14, 250);
const STALK_LT = rgba(34, 33, 22, 248);
const STALK_DK = rgba(12, 12, 9, 252);
const LIMB = rgba(14, 13, 11, 250);
const LIMB_LT = rgba(22, 20, 16, 248);
const CALYX = rgba(19, 22, 15, 250);
const CALYX_LT = rgba(31, 34, 22, 248);
/// The corolla, three ages of it. **AUTHORED DARK**: at (82, 52, 66) the quills came back as pale mauve card
/// against a near-black animal, brighter than anything else in frame and reading as plastic. The bloom is meant
/// to be found by its THROAT, so the petals are hide-dark with a bruise in them and only the tips are pale.
/// MEASURED at (41, 26, 36): the lit quill came back at luma 101 — the GROUND's own luma, so the corolla had
/// nothing to stand against across a field. Wanted ~82, and screen goes as albedo^(1/2.2), so (82/101)^2.2 =
/// 0.63 on every one of them. A near-black flower round a burning throat is the picture; a pink one is not.
const PETAL_DK = rgba(15, 11, 16, 250);
const PETAL = rgba(26, 16, 23, 250);
const PETAL_LT = rgba(40, 27, 33, 248);
/// The tip of a quill only — a hair of bleach, never the whole blade.
const PETAL_TIP = rgba(58, 45, 48, 246);
/// The tongues that cup the throat. MEASURED at (49, 24, 29): luma 107-125 over a big area — the second
/// brightest mass in frame after the light itself, so the whole centre of the flower read as one pink blob with
/// no focus in it. Solved to ~88, between the quill (92) and the body (65): (88/116)^2.2 = 0.55 on the albedo.
/// The two tiers separate on HUE instead — red-black tongues against violet-black quills.
const PETAL_IN = rgba(30, 12, 14, 246);
/// The throat, and the ONLY light on the animal. Low alpha IS the glow (`emis = 1 - a`).
/// **THE DARK COLLAR ROUND THE LIGHT**, and the whole reason the mouth reads as a hole: at (84, 30, 40) alpha
/// 208 this was a 0.29 m pink disc and the glow inside it had nothing to be brighter than.
const THROAT_HALO = rgba(46, 20, 26, 236);
const THROAT_LIP = rgba(120, 38, 50, 168);
const THROAT_DEEP = rgba(188, 48, 62, 96);
const THROAT = rgba(255, 132, 128, 22);
/// MEASURED at (244, 216, 142) alpha 150: 0.41 emissive on a near-white albedo put the anthers at luma 120+ and they read as golf balls. Same solve as the teeth.
const STAMEN = rgba(146, 122, 76, 196);
const FANG = rgba(29, 26, 22, 250);
/// …and its point. MEASURED at (188, 180, 158): luma 157 against a body at 60 and a ground at 101 — the brightest
/// thing in frame by half again, on a creature whose whole point is that the THROAT is the bright thing. Solved
/// to ~110: the wanted factor is 110/157 on screen, so 0.66^2.2 = 0.41 on the albedo.
const TOOTH = rgba(78, 74, 65, 242);
const CLAW = rgba(30, 28, 22, 250);
const HUSK = rgba(36, 31, 24, 250);

pub const State = enum { idle, move, bite, rake, hurt, dead };

pub const Model = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "ravager");
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
    leash: foe.Leash = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,
    state: State = .idle,
    t: f32 = 0,
    /// A clock no state resets, because the idle drift may not restart every time it stops walking.
    elapsed: f32 = 0,
    phase: f32 = 0,
    speed: f32 = 0,
    speedS: f32 = 0,
    biteCool: f32 = 0,
    rakeCool: f32 = 0,
    /// +1 its left, -1 its right, latched at the commit off the side the hero is standing. A side re-read per frame would swap legs mid-swipe.
    rakeSide: f32 = 1,
    /// -1..1, how far round the stalk is leaning AT him. Eased, and off his BEARING alone.
    look: f32 = 0,
    /// How many leaps this body has taken. Only the parity is read — it is what alternates the gather's coil.
    leaps: u32 = 0,
    pounce: f32 = 0,
    /// The bloom's own value on the frame it died. A corpse wilts from whatever the blow caught it wearing; snapping to shut is a pop, and ramping from wide is the same pop the other way.
    deathOpen: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    heroLatch: bool = false,
    /// **A FOE HURTS THE HERO BY RETURNING A `Hit`**, never by carrying a `foe.Blade` — that type is the other
    /// direction entirely (what HIS sword sweeps against a body). Built the wrong way round the creature leapt all day and could not take a point off him.
    heroHit: ?combat.Hit = null,
    heavyStun: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    opened: bool = false,
    leapt: bool = false,
    snapped: bool = false,
    swiped: bool = false,
    yelped: bool = false,
    parry: foe.Parry = .{},
    parried: bool = false,

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
    /// **THE MARK RIDES THE BODY, NOT THE BLOOM** (owner's call) — on the head it rode a stalk that rears 1.6 `W`,
    /// stretches a quarter more and DIVES 108 degrees, so the reticle travelled a metre and a half a strike. Off `SPINE` and not `centerWorld`, so it still rides the POSE.
    pub fn lockPoint(self: *const Ravager) rl.Vector3 {
        return foe.markOn(self.xf[SPINE], LOCK_AT);
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
    pub fn airborne(self: *const Ravager) bool {
        return self.state == .bite and self.leapLift() > foe.AIRBORNE_LIFT;
    }
    pub fn flashFrac(self: *const Ravager) f32 {
        return foe.flashFrac(self.flash);
    }

    /// The throat's own mouth, off the posed head — what the bite's height is measured from.
    pub fn bloomPoint(self: *const Ravager) rl.Vector3 {
        return foe.markOn(self.xf[HEAD], v3(0, 0, CALYX_Z + 0.03 * W));
    }
    /// …and where a portrait points (`shots.runMapShots`). The flower IS this creature's face.
    pub fn facePoint(self: *const Ravager) rl.Vector3 {
        return self.bloomPoint();
    }

    /// 0 shut, 1 wide, **and it is read off the attack's own clock or the stun's and nowhere else** (owner: it
    /// ONLY blooms when it is warming up to attack; it also blooms when heavy stunned). Out of range at both
    /// ends on purpose — under 0 through the tightening, over 1 through the fling.
    pub fn openAmt(self: *const Ravager) f32 {
        switch (self.state) {
            .dead => return self.deathOpen * (1.0 - mathx.smoothstep(0, WILT_DUR, self.t)),
            .hurt => return if (self.heavyStun) BLOOM_STUN * foe.stunCurve(self.t, true) else 0,
            .bite => {},
            .idle, .move, .rake => return 0,
        }
        const clampEnd = BITE_WIND * CLAMP_BY;
        const openEnd = BITE_WIND * OPEN_BY;
        const setEnd = BITE_WIND * SETTLE_BY;
        if (self.t < clampEnd) return -BLOOM_CLAMP * mathx.smoothstep(0, clampEnd, self.t);
        if (self.t < openEnd) return mathx.lerpF(-BLOOM_CLAMP, 1.0 + BLOOM_SNAP, mathx.smoothstep(clampEnd, openEnd, self.t));
        if (self.t < setEnd) return mathx.lerpF(1.0 + BLOOM_SNAP, 1.0, mathx.smoothstep(openEnd, setEnd, self.t));
        if (self.t < HOP_END) return 1.0 + BLOOM_DRAG * self.arcAmt();
        return 1.0 - (1.0 + BLOOM_CLAMP * 0.5) * mathx.smoothstep(HOP_END, HOP_END + BITE_RECOVER * SHUT_BY, self.t);
    }

    /// **THE OPEN THROAT IS THE PRICE OF THE MOVE.** 1 while the bud is shut, up to 1.9 wide. Damage only — see `BLOOM_FRAIL`.
    pub fn frailty(self: *const Ravager) f32 {
        return 1.0 + BLOOM_FRAIL * mathx.clampF(self.openAmt(), 0, 1);
    }

    /// **HOW FAR THE STALK IS REACHING**, 0..1, off the bite's clock — never off `openAmt`, or a heavy stun would rear the neck it is supposed to fold.
    pub fn rearAmt(self: *const Ravager) f32 {
        if (self.state != .bite) return 0;
        if (self.t < BITE_WIND) return mathx.smoothstep(0, BITE_WIND * REAR_BY, self.t);
        if (self.t < HOP_END) return 1.0;
        return 1.0 - mathx.smoothstep(HOP_END, HOP_END + BITE_RECOVER * SHUT_BY, self.t);
    }

    /// The GATHER, 0..1 — the load, and it is spent by the launch. What the crouch, the forequarter drop and the coil all ride.
    fn gatherAmt(self: *const Ravager) f32 {
        if (self.state != .bite) return 0;
        return mathx.pulse(self.t, 0, BITE_WIND * 0.72, BITE_WIND * 0.86, HOP_END);
    }

    /// **HOW FAR INTO THE DIVE IT IS**, 0..1. Off the strike's own window, not the whole bite: the rear and the stretch own the gather, and this owns the frames the blow is live in.
    pub fn diveAmt(self: *const Ravager) f32 {
        if (self.state != .bite) return 0;
        if (self.t < BITE_WIND) return 0;
        if (self.t < HOP_END) return mathx.smoothstep(BITE_WIND, BITE_WIND + BITE_STRIKE * DIVE_BY, self.t);
        return 1.0 - mathx.smoothstep(HOP_END, HOP_END + BITE_RECOVER * SHUT_BY, self.t);
    }

    /// **THE LANDING, SIGNED**: +1 the moment the paws take it, through zero as the body comes back up, and decaying. Overshoot and settle, not a glide.
    fn landAmt(self: *const Ravager) f32 {
        if (self.state != .bite or self.t < HOP_END) return 0;
        const u = (self.t - HOP_END) / LAND_DUR;
        if (u >= 1.0) return 0;
        return (1.0 - u) * mathx.cosf(u * std.math.tau * 1.35);
    }

    fn arcAmt(self: *const Ravager) f32 {
        const up = wolf.BITE_HOP_UP * W;
        return if (up > 1e-5) self.leapLift() / up else 0;
    }

    fn leapLift(self: *const Ravager) f32 {
        if (self.state != .bite) return 0;
        if (self.t <= LAUNCH_T or self.t >= HOP_END) return 0;
        const u = (self.t - LAUNCH_T) / (HOP_END - LAUNCH_T);
        return wolf.BITE_HOP_UP * mathx.sinf(u * std.math.pi) * mathx.lerpF(wolf.HOP_FLOOR, 1.0, self.pounce) * W;
    }

    /// Which way this leap coils. Its own seed picks a hand and the leap COUNT flips it, so a body does not wind up the same way twice running.
    fn coilSide(self: *const Ravager) f32 {
        const own: f32 = if (self.seed < 0.5) 1.0 else -1.0;
        return if (self.leaps & 1 == 0) own else -own;
    }

    /// Three incommensurate rates off one never-reset clock, offset by the map's own seed.
    fn swayAt(self: *const Ravager) f32 {
        return mathx.gutter(self.elapsed * SWAY_RATE + self.seed * 9.7, self.seed * 6.1);
    }

    pub fn navWant(self: *const Ravager, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state != .idle and self.state != .move) return null;
        if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R) return hero;
        return if (mathx.distXZ(self.pos, self.home) > HOME_R) self.home else null;
    }

    fn faceToward(self: *Ravager, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, TURN_RATE, dt);
    }

    pub fn update(self: *Ravager, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.justDied = false;
        self.heroHit = null;
        self.opened = false;
        self.leapt = false;
        self.snapped = false;
        self.swiped = false;
        self.yelped = false;
        self.parried = false;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.stateStep(dt, hero, bounds);
        self.takeParry();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn stateStep(self: *Ravager, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);

        self.t += dt;
        self.elapsed += dt;
        self.vit.tick(dt);
        foe.fadeFlash(&self.flash, dt);
        self.biteCool = mathx.maxF(0, self.biteCool - dt);
        self.rakeCool = mathx.maxF(0, self.rakeCool - dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        if (self.state == .dead) {
            foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
            self.look = mathx.approach(self.look, 0, dt * LOOK_RATE);
            self.speed = 0;
            self.settle(dt);
            return self.pose();
        }

        // THE STALK TURNS TOWARDS HIM WHILE THE BUD IS STILL SHUT — his bearing, and nothing else about him.
        const wantLook: f32 = if (foe.senseHero(&self.leash, self.pos, hero, AGGRO_R) <= AGGRO_R and self.state != .bite)
            mathx.clampF(self.sideOf(hero) * 1.6, -1, 1)
        else
            0;
        self.look = mathx.approach(self.look, wantLook, dt * LOOK_RATE);

        if (self.state == .hurt) {
            if (self.t >= combat.foeStunDur(self.heavyStun)) self.state = .idle;
            self.speed = 0;
            self.settle(dt);
            return self.pose();
        }
        if (self.state == .bite) {
            if (self.t < BITE_WIND) self.faceToward(hero, dt);
            self.speed = 0;
            // Through `stepXZ` like any other committed travel, so the terrain gate still gets the last word. The
            // launch is an EDGE on the clock crossing, so a long frame cannot fire it twice.
            if (self.t - dt < LAUNCH_T and self.t >= LAUNCH_T) self.leapt = true;
            if (self.t < HOP_END) {
                mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), BITE_HOP * (dt / HOP_END), bounds);
            }
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

        if (self.state == .rake) {
            // IT DOES NOT TURN INTO IT. Committed to the ground it was chosen for, so walking out of the arc costs him nothing.
            if (self.t >= RAKE_WIND and self.t < RAKE_WIND + RAKE_STRIKE) self.tryRake(hero);
            if (self.t >= RAKE_WIND + RAKE_STRIKE + RAKE_RECOVER) {
                self.state = .idle;
                self.t = 0;
                self.rakeCool = RAKE_COOL;
                self.heroLatch = false;
            }
            self.speed = 0;
            self.settle(dt);
            return self.pose();
        }

        const sensed = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        const hunting = sensed <= AGGRO_R;
        const want = if (hunting) hero else self.home;
        const gap = mathx.distXZ(self.pos, want);
        const stop: f32 = if (hunting) stopR(foe.HERO_R) else HOME_R;

        // **THE JUMP IS GATED WHERE THE MOVE IS CHOSEN** — the one place a post-step gate cannot reach. Denying only its distance leaves it hopping on the spot inside a fist of roots.
        if (hunting and gap <= triggerR(foe.HERO_R) and self.biteCool <= 0 and foe.canLeap(&self.root)) {
            self.state = .bite;
            self.t = 0;
            self.heroLatch = false;
            self.speed = 0;
            self.pounce = 1.0;
            self.leaps +%= 1;
            self.opened = true;
        } else if (hunting and self.wantsRake(hero, gap)) {
            self.state = .rake;
            self.t = 0;
            self.heroLatch = false;
            self.speed = 0;
            // `sideOf` is his bearing, and the sign of it IS which leg.
            self.rakeSide = if (self.sideOf(hero) >= 0) 1.0 else -1.0;
            self.swiped = true;
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

    /// +1 its left, -1 its right, and the magnitude is how far round. Reads POSITION and BEARING and nothing else.
    fn sideOf(self: *const Ravager, hero: rl.Vector3) f32 {
        const to = mathx.dirXZ(self.pos, hero);
        const fwd = mathx.headingDir(self.facing);
        return fwd.z * to.x - fwd.x * to.z;
    }

    /// CLOSE, OFF THE FRONT, PAWS DOWN, AND OFF COOLDOWN. Inside the frontal cone the bloom is the answer and this refuses — the two moves own different ground.
    fn wantsRake(self: *const Ravager, hero: rl.Vector3, gap: f32) bool {
        if (self.rakeCool > 0) return false;
        if (gap > RAKE_R * self.scale + foe.HERO_R) return false;
        const to = mathx.dirXZ(self.pos, hero);
        const fwd = mathx.headingDir(self.facing);
        return to.x * fwd.x + to.z * fwd.z < RAKE_OFF_DOT;
    }

    fn tryRake(self: *Ravager, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, hero, foe.hurtReach(RAKE_R, self.scale), RAKE_FRONT_DOT)) return;
        // …AND ONLY ON THE SIDE THE PAW IS ON. One foreleg is swinging; the other shoulder is not a weapon.
        if (mathx.distXZ(self.pos, hero) > foe.POINT_BLANK and self.sideOf(hero) * self.rakeSide < 0) return;
        self.heroHit = RAKE_HIT;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    fn tryBite(self: *Ravager, hero: rl.Vector3) void {
        if (self.heroLatch) return;
        if (!foe.inFront(self.pos, self.facing, hero, foe.hurtReach(BITE_R, self.scale), BITE_FRONT_DOT)) return;
        self.heroHit = BITE_HIT;
        self.heroLatch = true;
        self.snapped = true;
        self.leash.noteCombat();
    }

    fn settle(self: *Ravager, dt: f32) void {
        self.speedS = mathx.approach(self.speedS, self.speed, GAIT_BLEND * dt);
    }

    pub fn tryHit(self: *Ravager, blade_: foe.Blade) void {
        if (self.state == .dead) return;
        // **THE OPEN BLOOM IS PAID FOR HERE**, on the blade and not in the body's own bar, so the cull, the
        // threat and the shield all see the blow that actually landed. `poise`/`stance` ride through untouched.
        var blade = blade_;
        const k = self.frailty();
        if (k > 1.0) {
            blade.hit.dmg = blade_.hit.dmg * k;
            blade.hit.elem = blade_.hit.elem.scaled(k);
        }
        const s = foe.reached(self, blade) orelse return;
        const heavy = foe.wounded(self, s, blade, SHOVE);
        const torn: i32 = if (heavy) 7 else 3;
        self.emitPetals(s.contact, torn + @as(i32, @intFromFloat(6.0 * mathx.clampF(self.openAmt(), 0, 1))));
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    /// SECONDS BACK FROM THE PAW ARRIVING, or null. **THE SWIPE ONLY, NEVER THE LEAP** — the same call the bone
    /// knight's HOP gets: a shield is braced against a stroke, and a whole animal in the air is not a stroke.
    fn toImpact(self: *const Ravager) ?f32 {
        const at = RAKE_WIND + RAKE_STRIKE * RAKE_IMPACT_K;
        return switch (self.state) {
            .rake => at - self.t,
            .idle, .move, .bite, .hurt, .dead => null,
        };
    }

    /// THE INSTANT THE PAW CAN BE CAUGHT IN, and how far out it reaches then — `tryRake`'s OWN extent through the same `foe.hurtReach`, so a swipe the boards could not have met is never offered as one.
    fn parryable(self: *const Ravager) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return foe.hurtReach(RAKE_R, self.scale);
    }

    /// **THE BOARDS TAKE THE PAW.** No sparks of its own: this is meat on wood, and the ring and the shake are the hero's own (`game.parryBeat`).
    fn takeParry(self: *Ravager) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        self.rakeCool = RAKE_COOL;
        self.heroLatch = true;
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light, .none => self.enterStun(false),
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
        self.deathOpen = mathx.clampF(self.openAmt(), 0, 1.0 + BLOOM_SNAP);
        self.state = .dead;
        self.t = 0;
        self.justDied = true;
    }

    pub fn stagger(self: *Ravager, heavy: bool) void {
        self.enterStun(heavy);
    }

    pub fn stagePounce(self: *Ravager, amt: f32) void {
        self.state = .bite;
        self.pounce = mathx.clampF(amt, 0, 1);
        self.t = APEX_T;
        self.pose();
    }
    pub fn stageGather(self: *Ravager, u: f32) void {
        self.state = .bite;
        self.t = mathx.clampF(u, 0, 1) * BITE_WIND;
        self.pose();
    }
    /// The other half of the tell, for a photograph: the bloom held open by a heavy stun rather than by a leap.
    pub fn stageStun(self: *Ravager) void {
        self.state = .hurt;
        self.heavyStun = true;
        self.t = combat.foeStunDur(true) * 0.4;
        self.pose();
    }

    fn emitPetals(self: *Ravager, at: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.6, 1.7);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = at,
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(0.3, 1.6), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.38, 0.78),
                .r0 = self.fxRng.range(0.030, 0.058) * self.scale,
                .r1 = 0.006,
                .col = if (self.fxRng.float() < 0.5) PETAL else PETAL_LT,
                .grav = 2.2,
                // Petals FLUTTER — heavy drag against a light pull.
                .drag = 2.8,
            });
        }
    }

    pub fn drawFx(self: *const Ravager) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Ravager, model: *const Model) void {
        if (self.gone) return;
        model.draw(self);
    }

    pub fn pose(self: *Ravager) void {
        const fs = foe.rigScale(self.scale, self.fade);
        const sink = foe.rigSink(SINK_DEPTH, self.scale, self.fade);
        const g = wolf.gaitAt(self.speedS);
        const stride = wolf.strideFor(self.speedS);
        const ph = wolf.limbPhases(self.phase, g);
        const m = mathx.clampF(self.speedS / wolf.WALK_SPEED, 0, 1);

        const react: f32 = if (self.state == .hurt) foe.stunCurve(self.t, self.heavyStun) else 0;
        const wilt: f32 = if (self.state == .dead) mathx.clampF(self.t / (DEATH_DUR * 0.34), 0, 1) else 0;
        const fall: f32 = if (self.state == .dead) mathx.clampF((self.t - DEATH_DUR * 0.26) / (DEATH_DUR * 0.58), 0, 1) else 0;

        const lift = self.leapLift();
        const arcN = self.arcAmt();
        const gather = self.gatherAmt();
        const dive = self.diveAmt();
        const land = self.landAmt();
        const sway = self.swayAt();

        const crouch = CROUCH * gather + LAND_SINK * mathx.maxF(land, 0) + DEAD_BUCKLE * wilt;
        const pitch = wolf.BITE_PITCH * arcN - BODY_DIVE * dive + GATHER_PITCH * gather - LAND_PITCH * land;
        // Two rates, so the swell is a body breathing and not a metronome.
        const breath = (mathx.sinf(self.elapsed * 1.7) * 0.006 + mathx.sinf(self.elapsed * 0.61 + self.seed * 4.0) * 0.004) * W;

        var wx: [N]rl.Matrix = undefined;
        // **THE WHOLE RIG TAKES THE MAP'S SCALE, NOT JUST THE PELVIS HEIGHT** — `centerWorld`, `topWorld`,
        // `hurtRadius` and `bodyR` are all `self.scale`'d. INNERMOST, so every child bone inherits it.
        wx[ROOT] = mul3(
            mul(scaleM(fs, fs, fs), mul(rx(-pitch), rz(-DEAD_ROLL * mathx.smoothstep(0, 1, fall) + SWAY_DEG * 0.35 * sway))),
            mul(tr(0, (self.rest[ROOT].y + breath + lift - crouch * W) * fs + sink, 0), ry(mathx.degrees(self.facing))),
            heromod.rootAt(self.pos),
        );
        const flex = mathx.sinf(self.phase * std.math.tau) * m * (4.0 + 9.0 * mathx.clampF((self.speedS - wolf.TROT_SPEED) / (wolf.GALLOP_SPEED - wolf.TROT_SPEED), 0, 1));
        const duck: f32 = 8.0 * react;
        heromod.setJoint(&wx, &self.rest, SPINE, ROOT, mul(rx(-flex * 0.5 - duck * 0.3), rz(SWAY_DEG * 0.5 * sway)));
        heromod.setJoint(&wx, &self.rest, CHEST, SPINE, mul(rx(-flex * 0.5 - duck * 0.3 - 9.0 * wilt), rz(-SWAY_DEG * 0.35 * sway)));

        // THE STALK IS UPRIGHT: the canid's forward reach is gone, so the gait gives it a sway rather than a nod.
        // Negative about X at the neck brings the head DOWN and forward (the root's own sign, one joint along).
        const neckPitch = flex * 0.5 + 3.0 * m - duck * 1.4 + REAR_DEG * gather - STRIKE_DIVE * dive - WILT_FOLD * wilt + 9.0 * land;
        const neckYaw = LOOK_DEG * self.look + SWAY_DEG * sway + COIL_DEG * gather * self.coilSide();
        heromod.setJoint(&wx, &self.rest, NECK, CHEST, mul3(rz(SWAY_DEG * 0.8 * sway), rx(neckPitch), ry(neckYaw)));

        // **THE BLOOM RIDES UP THE STALK'S OWN AXIS**, not the world's: `setJoint` takes the bone length from the
        // DISTANCE between two rest points, so the reach is a translate on top and the throat comes with it. The
        // HEAD's mesh carries a 0.47 m collar hanging INSIDE the stalk's bore, which is what covers the slide.
        // **AND IT COILS BACK AS IT STRIKES** (owner: the neck goes crazy).
        const reach = NECK_STRETCH * W * self.rearAmt() * (1.0 - DIVE_COIL * dive);
        const neckOff = mathx.subV(self.rest[HEAD], self.rest[NECK]);
        const up = if (mathx.lenV(neckOff) > 1e-5) mathx.normV(neckOff) else v3(0, 1, 0);
        wx[HEAD] = mul(
            mul(
                mul3(rx(flex * 0.25 - 3.0 * m - duck * 0.6 + 22.0 * react - 34.0 * wilt), ry(LOOK_DEG * 0.45 * self.look), rz(SWAY_DEG * 0.6 * sway)),
                tr(neckOff.x + up.x * reach, neckOff.y + up.y * reach, neckOff.z + up.z * reach),
            ),
            wx[NECK],
        );

        const open = self.openAmt();
        const shiver = SHIVER_DEG * react * mathx.sinf(self.elapsed * SHIVER_HZ * std.math.tau);
        const flutter = 1.3 * sway;
        for (PETALS) |q| {
            const fold = foldOf(q, open) + q.sag * wilt + shiver * q.gain + flutter * (0.4 + 0.6 * mathx.clampF(open, 0, 1));
            heromod.setJoint(&wx, &self.rest, q.bone, HEAD, mul(rx(-fold), rz(q.ang + shiver * 0.3)));
        }

        const tailSwing = mathx.sinf(self.phase * std.math.tau + 1.1) * 6.0 * m + SWAY_DEG * 1.2 * sway;
        const tailUp = 26.0 * gather - 30.0 * dive - 22.0 * wilt;
        heromod.setJoint(&wx, &self.rest, TAIL0, ROOT, mul(rx(-10.0 * m + 24.0 * react + tailUp), ry(tailSwing)));
        heromod.setJoint(&wx, &self.rest, TAIL1, TAIL0, mul(rx(6.0 + 10.0 * react + tailUp * 0.6), ry(tailSwing * 0.7)));
        heromod.setJoint(&wx, &self.rest, TAIL2, TAIL1, mul(rx(9.0 + 8.0 * react + tailUp * 0.35), ry(tailSwing * 0.5)));

        const tuck = lift / @max(0.72 * W, 0.001);
        wolf.legs(wx[0..wolf.N], self.rest[0..wolf.N], W, ph, g, stride, m, crouch, tuck);
        self.poseRake(&wx);
        self.xf = wx;
    }

    /// **AUTHORED OVER THE GAIT SOLVER, NOT INSIDE IT** — `wolf.legs` has run and planted all four, and this takes ONE foreleg back off it. `setJoint` brings the paw's own transform along and nothing else moves.
    fn poseRake(self: *const Ravager, wx: *[N]rl.Matrix) void {
        if (self.state != .rake) return;
        const k = self.rakeAmt();
        if (@abs(k) < 0.001) return;
        const left = self.rakeSide >= 0;
        const chain: [4]usize = if (left)
            .{ wolf.SHL, wolf.ELL, wolf.CAL, wolf.PAWL }
        else
            .{ wolf.SHR, wolf.ELR, wolf.CAR, wolf.PAWR };
        const sh = chain[0];
        const el = chain[1];
        const ca = chain[2];
        const paw = chain[3];
        const side: f32 = if (left) 1.0 else -1.0;
        // Cocked (-1) the paw comes UP and ACROSS its chest; driven (+1) it is out past the shoulder and low. One signed channel, so the cock cannot promise a side the swipe does not come from.
        const swing = RAKE_SWING * k;
        const lift = RAKE_LIFT * (1.0 - @abs(k) * 0.55);
        heromod.setJoint(wx, &self.rest, sh, CHEST, mul3(rx(-lift), rz(side * swing), ry(-side * swing * 0.45)));
        heromod.setJoint(wx, &self.rest, el, sh, rx(RAKE_ELBOW * (1.0 - k) * 0.5));
        heromod.setJoint(wx, &self.rest, ca, el, rx(-RAKE_CARPUS * (0.5 - k * 0.5)));
        heromod.setJoint(wx, &self.rest, paw, ca, rx(RAKE_PAW * (0.5 + k * 0.5)));
    }

    /// -1 fully cocked, +1 fully through — on the rake's own window and never the bite's. Zero outside the move, so the same channel poses the settle back to the gait.
    fn rakeAmt(self: *const Ravager) f32 {
        if (self.state != .rake) return 0;
        if (self.t < RAKE_WIND) return -mathx.smoothstep(0, RAKE_WIND * 0.85, self.t);
        if (self.t < RAKE_WIND + RAKE_STRIKE) {
            return mathx.lerpF(-1.0, 1.0, foe.swingCurve((self.t - RAKE_WIND) / RAKE_STRIKE));
        }
        return 1.0 - mathx.smoothstep(RAKE_WIND + RAKE_STRIKE, RAKE_WIND + RAKE_STRIKE + RAKE_RECOVER * 0.7, self.t);
    }
};

const CAP_N = wf.MAX_PER_KIND;

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
    pub fn setParry(self: *Thicket, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Thicket) bool {
        return foe.anyParried(self.liveConst());
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

fn buildBone(b: *Builder, i: usize, rest: [N]rl.Vector3) void {
    var rng = mathx.Rng.init(0xF10D + @as(u64, @intCast(i)));
    switch (i) {
        ROOT => buildPelvis(b, &rng),
        SPINE => buildLoin(b, &rng, rest),
        CHEST => buildChest(b, &rng),
        NECK => buildStalk(b, &rng, rest),
        HEAD => buildBloom(b, &rng, rest),
        JAW, EARL, EARR, PET3, PET4, PET5, PET6 => buildPetal(b, &rng, rowFor(i)),
        TAIL0, TAIL1, TAIL2 => buildTail(b, &rng, i, rest),
        else => buildLimbBone(b, i, rest, &rng),
    }
}

fn buildPelvis(b: *Builder, rng: *mathx.Rng) void {
    b.setMat(.hide);
    b.addBlob(v3(0, 0.006 * W, 0.02 * W), v3(0.166 * W, 0.176 * W, 0.230 * W), 6, 10, HIDE);
    b.addBlob(v3(0, 0.112 * W, -0.01 * W), v3(0.130 * W, 0.074 * W, 0.150 * W), 5, 9, HIDE_DK);
    // THE HAUNCHES STAND PROUD of the croup — 0.086 W of thigh on a 0.166 W pelvis, and they are what say the
    // back legs drive. Buried inside a 0.200 W blob they were invisible and the rump read as the end of a barrel.
    b.addBlob(v3(0.130 * W, -0.014 * W, -0.01 * W), v3(0.090 * W, 0.148 * W, 0.152 * W), 5, 9, HIDE_LT);
    b.addBlob(v3(-0.126 * W, -0.006 * W, 0.00 * W), v3(0.086 * W, 0.142 * W, 0.148 * W), 5, 9, HIDE_LT);
    b.addBlob(v3(0, -0.104 * W, 0.05 * W), v3(0.112 * W, 0.058 * W, 0.150 * W), 4, 8, BELLY);
    b.setMat(.bark);
    var k: u32 = 0;
    while (k < 4) : (k += 1) {
        const x = (@as(f32, @floatFromInt(k)) - 1.5) * 0.062 * W;
        b.addCapsule(
            v3(x, 0.070 * W + rng.range(-0.012, 0.012) * W, -0.145 * W),
            v3(x * 1.25, -0.035 * W, 0.155 * W),
            0.017 * W * rng.range(0.7, 1.3),
            0.011 * W,
            5,
            STALK_DK,
        );
    }
    // …and a cluster of shut buds over ONE hip. Asymmetric on purpose; a pair reads as anatomy.
    b.setMat(.plant);
    var j: u32 = 0;
    while (j < 3) : (j += 1) {
        const at = v3(0.120 * W + rng.range(-0.03, 0.03) * W, 0.075 * W + @as(f32, @floatFromInt(j)) * 0.036 * W, -0.06 * W + rng.range(-0.04, 0.04) * W);
        const rr = 0.024 * W * rng.range(0.7, 1.35);
        b.addBlob(at, v3(rr, rr * 1.9, rr), 4, 6, CALYX);
        b.addBlob(v3(at.x, at.y + rr * 1.7, at.z), v3(rr * 0.5, rr * 0.7, rr * 0.5), 3, 6, HUSK);
    }
}

/// The loin, and **IT IS A WAIST OR THE WHOLE TRUNK IS ONE TUBE.** At 0.172-0.186 W it stood as thick as the
/// chest and the animal read as a barrel from shoulder to hip: 0.132 rising to 0.160 puts a real pinch between
/// them, which is what a running dog has and what lets the haunches read as haunches.
fn buildLoin(b: *Builder, rng: *mathx.Rng, rest: [N]rl.Vector3) void {
    const off = mathx.subV(rest[CHEST], rest[SPINE]);
    const len = mathx.lenV(off);
    b.setMat(.hide);
    b.addCapsule(v3(0, 0, -0.03 * W), mathx.scaleV(off, 1.04), 0.132 * W, 0.160 * W, 11, HIDE);
    b.addBlob(v3(0, -0.086 * W, len * 0.55), v3(0.104 * W, 0.046 * W, len * 0.48), 4, 9, BELLY);
    // FOUR vertebral knuckles, graded and uneven. Relief is a few PERCENT of the mass — 0.172 W of barrel takes 0.006 W of proud bone, no more.
    var k: u32 = 0;
    while (k < 4) : (k += 1) {
        const u = (@as(f32, @floatFromInt(k)) + 0.5) / 4.0;
        const rr = 0.036 * W * rng.range(0.78, 1.25) * (1.10 - 0.25 * u);
        b.addBlob(
            v3(rng.signed() * 0.006 * W, 0.136 * W + 0.012 * W * u, len * u),
            v3(rr * 0.8, rr, rr * 1.35),
            4,
            7,
            HIDE_DK,
        );
    }
}

fn buildChest(b: *Builder, rng: *mathx.Rng) void {
    b.setMat(.hide);
    b.addBlob(v3(0, -0.010 * W, 0.02 * W), v3(0.212 * W, 0.244 * W, 0.235 * W), 7, 11, HIDE);
    b.addBlob(v3(0, 0.118 * W, -0.04 * W), v3(0.163 * W, 0.092 * W, 0.178 * W), 5, 9, HIDE_DK);
    b.addBlob(v3(0, -0.148 * W, 0.03 * W), v3(0.152 * W, 0.084 * W, 0.182 * W), 5, 9, BELLY);
    b.addBlob(v3(0.150 * W, 0.030 * W, 0.02 * W), v3(0.058 * W, 0.128 * W, 0.140 * W), 4, 8, HIDE_LT);
    b.addBlob(v3(-0.146 * W, 0.024 * W, 0.03 * W), v3(0.055 * W, 0.122 * W, 0.136 * W), 4, 8, HIDE_LT);
    // **THE SOCKET.** The stem is 0.11 m through where it leaves a 0.29 m chest, and a stem that thin butted
    // straight onto a mass that thick reads as stuck on. This is on the CHEST and not the stalk, so it stays put
    // while the neck swings — a shoulder the stem grows OUT of. Hide grading into bark, which is the seam.
    // SUNK, not stood on top: proud at 0.150 W it read as a ball bolted to the withers (measured, luma 97
    // against a 75 trunk — the brightest thing on the body). Relief is a few percent of the mass.
    b.addBlob(v3(0, 0.118 * W, 0.098 * W), v3(0.126 * W, 0.070 * W, 0.124 * W), 5, 10, HIDE);
    b.setMat(.bark);
    b.addBlob(v3(0, 0.164 * W, 0.112 * W), v3(0.090 * W, 0.056 * W, 0.088 * W), 4, 10, STALK_DK);
    b.setMat(.hide);
    // THE COLLAR OF SPENT FLOWERS, lodged where the stalk leaves the shoulders. Round the BACK three-quarters
    // only: the front of the throat is where a blade lands and a ruff there would read as armour it does not have.
    b.setMat(.plant);
    var k: u32 = 0;
    while (k < 9) : (k += 1) {
        const a = std.math.pi * 0.35 + std.math.pi * 1.30 * (@as(f32, @floatFromInt(k)) + rng.range(-0.3, 0.3)) / 9.0;
        const rr = 0.130 * W;
        const at = v3(mathx.cosf(a) * rr, 0.140 * W + rng.range(-0.02, 0.02) * W, 0.075 * W + mathx.sinf(a) * rr * 0.5);
        const l = 0.070 * W * rng.range(0.55, 1.35);
        b.addCapsule(
            at,
            v3(at.x * 1.30, at.y - l * 0.75, at.z - l * 0.55),
            0.020 * W * rng.range(0.7, 1.2),
            0.008 * W,
            5,
            if (rng.float() < 0.45) HUSK else CALYX,
        );
    }
}

/// **THE STALK IS WOOD, AND IT IS A CHAIN AND NOT A PIPE.** Five sheaths overlapping well past their own joints,
/// radii grading 0.135 W to 0.070 W, each leaning its own hair off the axis — and the top is DELIBERATELY thin,
/// because the bloom's collar sleeves down over it and that is what covers the 0.35 m of stretch.
fn buildStalk(b: *Builder, rng: *mathx.Rng, rest: [N]rl.Vector3) void {
    const off = mathx.subV(rest[HEAD], rest[NECK]);
    const len = mathx.lenV(off);
    const dir = if (len > 1e-5) mathx.scaleV(off, 1.0 / len) else v3(0, 1, 0);
    var side = mathx.crossV(dir, v3(0, 0, 1));
    side = if (mathx.lenV(side) > 1e-4) mathx.normV(side) else v3(1, 0, 0);
    const fwd = mathx.normV(mathx.crossV(side, dir));

    const at = struct {
        fn on(d: rl.Vector3, s: rl.Vector3, f: rl.Vector3, l: f32, u: f32, sx: f32, sz: f32) rl.Vector3 {
            return v3(
                d.x * l * u + s.x * sx + f.x * sz,
                d.y * l * u + s.y * sx + f.y * sz,
                d.z * l * u + s.z * sx + f.z * sz,
            );
        }
    }.on;

    const SHEATH = 5;
    // **SLENDER, OR THE LONG NECK IS A LEEK.** At 0.135 W the top of the stalk was 0.24 m through with the collar
    // over it — four quills wide — and the whole neck read as a vegetable carrying a flower rather than a stem.
    const RAD = [SHEATH + 1]f32{ 0.082, 0.078, 0.072, 0.064, 0.056, 0.048 };
    // The S: a lean of 0.024 W either way over the run, which is under 4% of the length — enough to read, not enough to leave the head off its own stalk.
    const LEAN = [SHEATH + 1]f32{ 0.000, 0.018, 0.024, 0.008, -0.014, 0.000 };
    b.setMat(.bark);
    var k: u32 = 0;
    while (k < SHEATH) : (k += 1) {
        const ua = @as(f32, @floatFromInt(k)) / SHEATH;
        const ub = @as(f32, @floatFromInt(k + 1)) / SHEATH + (if (k + 1 < SHEATH) @as(f32, 0.09) else 0.0);
        b.addCapsule(
            at(dir, side, fwd, len, ua, LEAN[k] * W, LEAN[k] * W * 0.4),
            at(dir, side, fwd, len, ub, LEAN[k + 1] * W, LEAN[k + 1] * W * 0.4),
            RAD[k] * W,
            RAD[k + 1] * W,
            10,
            if (k == 0) STALK_DK else STALK,
        );
    }
    const NODE = [4]f32{ 0.19, 0.42, 0.63, 0.84 };
    for (NODE, 0..) |u, ni| {
        const c = at(dir, side, fwd, len, u, mathx.lerpF(LEAN[0], LEAN[SHEATH], u) * W, 0);
        const rr = mathx.lerpF(0.082, 0.048, u) * W * rng.range(1.12, 1.40);
        b.addBlob(c, v3(rr, rr * 0.62, rr), 4, 9, if (ni & 1 == 0) STALK_LT else STALK);
        // **A SPUR LEAVES ON ITS AXIS, REACHES AN ELBOW AND DROOPS OFF THE LINE.** One straight capsule at 1.3-2.2
        // node radii came back as four pale thorns as long as the stalk was thick, and they read louder than the
        // flower. Two links, half the reach, and the second one hangs.
        const a = rng.angle();
        const outx = mathx.cosf(a);
        const outz = mathx.sinf(a);
        const sl = rr * rng.range(0.62, 1.05);
        const out = struct {
            fn spur(cc: rl.Vector3, sd: rl.Vector3, fd: rl.Vector3, d: rl.Vector3, ox: f32, oz: f32, reach: f32, drop: f32) rl.Vector3 {
                return v3(
                    cc.x + sd.x * ox * reach + fd.x * oz * reach - d.x * drop,
                    cc.y + sd.y * ox * reach + fd.y * oz * reach - d.y * drop,
                    cc.z + sd.z * ox * reach + fd.z * oz * reach - d.z * drop,
                );
            }
        }.spur;
        const elbow = out(c, side, fwd, dir, outx, outz, rr * 0.85 + sl * 0.60, sl * 0.20);
        b.addCapsule(out(c, side, fwd, dir, outx, outz, rr * 0.70, 0), elbow, rr * 0.24, rr * 0.15, 5, HUSK);
        b.addCapsule(elbow, out(c, side, fwd, dir, outx, outz, rr * 0.85 + sl * 0.95, sl * 0.90), rr * 0.15, rr * 0.06, 4, HUSK);
    }
    // …and the FIBRES up the outside. Three, all in one tone: two alternated segment by segment band a shaft like a barber's pole (AGENTS.md).
    var f: u32 = 0;
    while (f < 3) : (f += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(f)) / 3.0 + rng.range(-0.4, 0.4);
        const rr = 0.062 * W;
        const ox = mathx.cosf(a) * rr;
        const oz = mathx.sinf(a) * rr;
        b.addCapsule(
            at(dir, side, fwd, len, 0.06, ox, oz),
            at(dir, side, fwd, len, 0.94, ox * 0.52, oz * 0.52),
            0.016 * W * rng.range(0.75, 1.25),
            0.008 * W,
            5,
            STALK_LT,
        );
    }
}

fn buildBloom(b: *Builder, rng: *mathx.Rng, rest: [N]rl.Vector3) void {
    const dn = mathx.normV(mathx.subV(rest[NECK], rest[HEAD]));
    // Down the stalk's bore by the stretch plus a hand: at full reach its bottom is still 0.12 m inside the sheath, so no frame of the slide shows a gap.
    b.setMat(.bark);
    b.addCapsule(
        mathx.scaleV(dn, (NECK_STRETCH + 0.09) * W),
        mathx.scaleV(dn, 0.012 * W),
        0.052 * W,
        0.062 * W,
        9,
        STALK_DK,
    );
    b.addBlob(mathx.scaleV(dn, 0.026 * W), v3(0.074 * W, 0.066 * W, 0.072 * W), 5, 10, STALK);

    b.setMat(.plant);
    // Small and set BACK: at 0.100 W it stood in the middle of the open corolla and, unlit and non-emissive,
    // read as a hole punched through the flower. It is a knuckle behind the light, not part of the light.
    b.addBlob(v3(0, 0, -0.044 * W), v3(0.084 * W, 0.082 * W, 0.056 * W), 6, 10, CALYX_LT);
    // FIVE SEPALS clasping from behind. **NOTHING DEAD IS STRAIGHT**: each is a three-link chain that leaves the
    // receptacle on its axis, reaches an elbow and DROOPS off the line — a single straight capsule per sepal came
    // back as five pale spikes and they dominated the whole head. One is broken short, which is the only thing
    // that says this flower has been open before.
    const SEP = [5]f32{ 1.00, 0.82, 1.16, 0.38, 0.92 };
    for (SEP, 0..) |share, k| {
        const a = std.math.tau * (@as(f32, @floatFromInt(k)) + rng.range(-0.20, 0.20)) / 5.0;
        const d = ringDir(mathx.degrees(a));
        const l = 0.062 * W * share;
        var at = v3(d.x * 0.078 * W, d.y * 0.078 * W, 0.006 * W);
        const col = if (k & 1 == 0) CALYX_LT else CALYX;
        var seg: u32 = 0;
        var rr = 0.020 * W * rng.range(0.85, 1.15);
        while (seg < 3) : (seg += 1) {
            const droop = (0.10 + 0.55 * @as(f32, @floatFromInt(seg))) * l;
            const to = v3(
                at.x + d.x * l * (0.62 - 0.22 * @as(f32, @floatFromInt(seg))),
                at.y + d.y * l * (0.62 - 0.22 * @as(f32, @floatFromInt(seg))) - droop * 0.30,
                at.z - l * 0.55 - droop * 0.35,
            );
            b.addCapsule(at, to, rr, rr * 0.62, 5, col);
            at = to;
            rr *= 0.62;
        }
    }

    // **THE ONE LIGHT ON THE ANIMAL, AND IT HAS TO BE FOUND FROM ACROSS A FIELD.** Sunk inside the receptacle it
    // could not be seen at all: a closed ellipsoid has no inside, so a "cup" of nested blobs shows the player its
    // dark BACK. It is built as a PROUD BOSS instead — four shells stepping out and up the axis, each hotter and
    // smaller than the last, so what stands over the calyx is a cone of light and not a hole. `.plain`: no
    // surface texture over a glow, which is the flame's own reason.
    b.setMat(.plain);
    // SIZED AGAINST THE COROLLA IT SITS IN: 0.29 m of lit boss inside a 1.7 m flower is about a sixth of its
    // width, which is an eye. At a tenth of that it was a dot nobody could find from across a field.
    //
    // **AND IT GRADES, OR EMISSIVE FLATTENS IT TO A LAMP.** Two full-hot shells at 0.050 and 0.032 W came back as
    // one white lozenge: `mix(lit, base*1.35, emis)` at 0.91 leaves no shading at all, so form has to come from
    // the ALBEDO STEPS. Dull red at the rim, deep red inside it, and ONE small white-hot centre.
    // **AND IT SITS INSIDE WHAT THE TONGUES COVER.** Standing to z 0.108 W the core was proud of the seal and the
    // shut bud glowed red at its base — a tell that is on all the time is not a tell. 0.070 W is under it.
    b.addBlob(v3(0, 0, 0.000 * W), v3(0.100 * W, 0.100 * W, 0.052 * W), 7, 11, THROAT_HALO);
    b.addBlob(v3(0, 0, 0.026 * W), v3(0.070 * W, 0.070 * W, 0.052 * W), 7, 11, THROAT_LIP);
    b.addBlob(v3(0, 0, 0.050 * W), v3(0.048 * W, 0.048 * W, 0.044 * W), 6, 10, THROAT_DEEP);
    b.addBlob(v3(0, 0, 0.070 * W), v3(0.027 * W, 0.027 * W, 0.026 * W), 5, 9, THROAT);
    // **THE FANGS ARE THE IRIS.** Nine, arching in and forward OVER the light — dark horn for two-thirds of their
    // reach and pale only at the point, so what stands in front of the glow is a dark ring with white tips and the
    // light is read BETWEEN them. Pale all the way up they were a starburst and the mouth read as a badge.
    var k: u32 = 0;
    while (k < 9) : (k += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(k)) + rng.range(-0.26, 0.26)) / 9.0;
        const d = ringDir(mathx.degrees(a));
        const rr = 0.100 * W;
        const l = 0.054 * W * rng.range(0.62, 1.36);
        const bend = v3(d.x * rr * 0.52, d.y * rr * 0.52, 0.006 * W + l * 0.60);
        b.addCapsule(v3(d.x * rr, d.y * rr, 0.000 * W), bend, 0.019 * W * rng.range(0.85, 1.15), 0.009 * W, 6, FANG);
        b.addCapsule(bend, v3(d.x * rr * 0.20, d.y * rr * 0.20, 0.006 * W + l), 0.009 * W, 0.0035 * W, 5, TOOTH);
    }
    // …and the ANTHERS, a TUFT and not a wheel. Nine leaning out at 0.13 m read as the spokes of a cartwheel over
    // the mouth; seven leaning FORWARD, clustered inside the fang ring, read as pollen standing in the gullet.
    var f: u32 = 0;
    while (f < 7) : (f += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(f)) + rng.range(-0.30, 0.30)) / 7.0;
        const d = ringDir(mathx.degrees(a));
        const l = 0.048 * W * rng.range(0.58, 1.42);
        const tip = v3(d.x * (0.036 * W + l * 0.26), d.y * (0.036 * W + l * 0.26), 0.044 * W + l * 0.92);
        b.addCapsule(v3(d.x * 0.038 * W, d.y * 0.038 * W, 0.030 * W), tip, 0.0055 * W, 0.0038 * W, 5, STAMEN);
        const ar = 0.0080 * W * rng.range(0.75, 1.3);
        b.addBlob(tip, v3(ar, ar, ar * 1.5), 3, 6, STAMEN);
    }
}

fn petalTone(t: u8) rl.Color {
    return switch (t) {
        0 => PETAL_DK,
        2 => PETAL_LT,
        else => PETAL,
    };
}

/// **A QUILL AND A TONGUE, ON ONE BONE.** The outer quill is the silhouette — round in section, tapering,
/// bowing out and recurving at the tip. The tongue is the second tier: short, broad, flattened, and pitched
/// `INNER_TILT` further in by a rotation baked into its SPINE rather than into the rig, so one fold drives both.
fn buildPetal(b: *Builder, rng: *mathx.Rng, q: Petal) void {
    const len = PETAL_LEN * q.len;
    b.setMat(.plant);

    // THE QUILL. One tone up its whole length: two alternated segment by segment band it like a barber's pole
    // (AGENTS.md), and the age difference belongs BETWEEN the seven. Only the last link is bleached.
    const tone = petalTone(q.tone);
    var at = sweptAt(len, 0, q.sweep);
    var j: u32 = 1;
    while (j <= PETAL_SEGS) : (j += 1) {
        const ua = @as(f32, @floatFromInt(j - 1)) / @as(f32, @floatFromInt(PETAL_SEGS));
        const ub = @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(PETAL_SEGS));
        // …and the links OVERLAP past their own joint (the packed-stone rule): butted, eight capsule caps read as eight beads.
        const to = sweptAt(len, @min(1.0, ub + 0.05), q.sweep);
        b.addCapsule(
            at,
            to,
            QUILL_R * q.wide * quillAt(ua, q) * rng.range(0.94, 1.06),
            QUILL_R * q.wide * quillAt(ub, q),
            7,
            if (j == PETAL_SEGS) PETAL_TIP else tone,
        );
        at = sweptAt(len, ub, q.sweep);
    }

    // THE TONGUE, tilted in. Flattened blobs and not capsules — this one wants to be a BROAD surface, and it is
    // short enough that an axis-aligned radius still follows its own spine.
    const ilen = len * INNER_LEN;
    const ct = mathx.cosf(mathx.radians(INNER_TILT));
    const st = mathx.sinf(mathx.radians(INNER_TILT));
    const tilt = struct {
        /// rx(+INNER_TILT) on a spine point: the bone applies rx(-fold), so the net is rx(-(fold - share*TILT)).
        fn on(p: rl.Vector3, c: f32, sn: f32) rl.Vector3 {
            return v3(p.x, p.y * c - p.z * sn, p.y * sn + p.z * c);
        }
    }.on;
    var s: u32 = 0;
    while (s <= 5) : (s += 1) {
        const u = @as(f32, @floatFromInt(s)) / 5.0;
        const c = tilt(spineAt(ilen, u), ct, st);
        const w = INNER_W * q.wide * widthAt(u, q) * rng.range(0.92, 1.08);
        b.addBlob(c, v3(w, w * 0.26, ilen * 0.19), 4, 9, if (u < 0.26) CALYX else PETAL_IN);
    }

    // **THE FRINGE — THREE HAIRS PER PETAL, AND IT IS WHAT MAKES THE OPEN FLOWER ALIEN.** A passionflower's
    // corona: fine filaments standing BETWEEN the two tiers, catching the sky rim on nothing but their edges.
    // Twenty-one of them, and they cost 21 capsules. Pitched at a share of the tongue's tilt, so they splay
    // between the quill and the cup rather than lying on either.
    const hc = mathx.cosf(mathx.radians(INNER_TILT * 0.42));
    const hs = mathx.sinf(mathx.radians(INNER_TILT * 0.42));
    var h: u32 = 0;
    while (h < 3) : (h += 1) {
        const hl = len * rng.range(0.34, 0.58);
        const lat = (@as(f32, @floatFromInt(h)) - 1.0) * INNER_W * rng.range(0.55, 1.05);
        const root = tilt(spineAt(hl, 0.10), hc, hs);
        const tip = tilt(spineAt(hl, 1.0), hc, hs);
        b.addCapsule(
            v3(root.x + lat * 0.30, root.y, root.z),
            v3(tip.x + lat, tip.y, tip.z),
            0.0075 * W,
            0.0022 * W,
            4,
            if (h == 1) PETAL_TIP else PETAL_LT,
        );
    }
}

/// The spine SWEPT sideways out of its own plane — a progressive `ry` along the blade, so a ring of seven reads
/// as a swirl and not as the spokes of a wheel.
///
/// **AND IT COSTS RADIUS, WHICH IS NOT OBVIOUS.** The sweep is tangential in the petal's OWN frame, but distance
/// from the bloom's axis is `hypot(tangential, radial)` — so a tip swept 0.48 m sideways is 0.48 m off the axis
/// however well it converged, and a shut bud built with 34 degrees of it came back as a splayed squid. Every
/// measurement of the corolla therefore goes through `atInBloom`, which carries the sweep.
fn sweptAt(len: f32, u: f32, sweepDeg: f32) rl.Vector3 {
    const p = spineAt(len, u);
    const a = mathx.radians(sweepDeg * u * u);
    return v3(p.z * mathx.sinf(a), p.y, p.z * mathx.cosf(a));
}

/// A QUILL TAPERS, IT DOES NOT BULGE. `widthAt` is a leaf profile — widest a third up — and on a round section
/// that reads as a bead on a stick. Thickest at the root, thinning to a fifth, with a hair of swell in the middle.
fn quillAt(u: f32, q: Petal) f32 {
    const uc = mathx.clampF(u, 0, 1);
    const w = 1.0 - 0.80 * std.math.pow(f32, uc, 0.90) + 0.09 * mathx.sinf(std.math.pi * uc);
    if (q.notch <= 0) return w;
    const d = (uc - q.notchAt) / 0.14;
    return w * (1.0 - q.notch * 0.55 * @exp(-d * d));
}

/// **A POINT ON A PETAL, IN THE BLOOM'S OWN FRAME** — so a radius means radially about the FLOWER's axis, which
/// is what "across" means on a corolla. World XZ does NOT measure it: the bloom points forward and up, so
/// `lenXZ` off the head reported the bud as 1.29 m wide and the open flower as no wider, the opposite of the truth.
fn atInBloom(q: Petal, open: f32, u: f32) rl.Vector3 {
    const rest = restPose();
    const off = mathx.subV(rest[q.bone], rest[HEAD]);
    const m = mul3(rx(-foldOf(q, open)), rz(q.ang), tr(off.x, off.y, off.z));
    return rl.math.vector3Transform(sweptAt(PETAL_LEN * q.len, u, q.sweep), m);
}

/// The blade's spine: a bow over its length plus a RECURVE over the last of it. Solved off the tangent — 2*BOW at the tip, plus 5*RECURVE, which is 42 degrees.
fn spineAt(len: f32, u: f32) rl.Vector3 {
    const uu = u * u;
    return v3(0, len * (PETAL_BOW * uu + PETAL_RECURVE * uu * uu * u), len * u);
}

/// Half-width as a share of the widest. `pow(u, 0.62)` under the sine puts the shoulder low on the blade, which is what a broad petal does, and the 0.34 floor is a BLUNT tip.
fn widthAt(u: f32, q: Petal) f32 {
    const uc = mathx.clampF(u, 0, 1);
    const w = 0.34 + 0.66 * mathx.sinf(std.math.pi * std.math.pow(f32, uc, 0.62));
    if (q.notch <= 0) return w;
    const d = (uc - q.notchAt) / 0.16;
    return w * (1.0 - q.notch * @exp(-d * d));
}

fn buildTail(b: *Builder, rng: *mathx.Rng, i: usize, rest: [N]rl.Vector3) void {
    const len: f32 = switch (i) {
        TAIL0 => mathx.lenV(mathx.subV(rest[TAIL0], rest[TAIL1])),
        TAIL1 => mathx.lenV(mathx.subV(rest[TAIL1], rest[TAIL2])),
        else => 0.17 * W,
    };
    const r0: f32 = 0.048 * W * (if (i == TAIL0) @as(f32, 1.0) else if (i == TAIL1) @as(f32, 0.76) else @as(f32, 0.56));
    const to = v3(0, -len * 0.35, -len * 0.9);
    b.setMat(.bark);
    b.addCapsule(v3(0, 0, 0), to, r0, r0 * 0.74, 8, STALK_DK);
    if (i != TAIL2) return;
    b.setMat(.plant);
    b.addBlob(v3(to.x, to.y - 0.014 * W, to.z - 0.024 * W), v3(0.036 * W, 0.052 * W, 0.062 * W), 5, 8, HUSK);
    var k: u32 = 0;
    while (k < 6) : (k += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(k)) + rng.range(-0.3, 0.3)) / 6.0;
        const l = 0.050 * W * rng.range(0.5, 1.4);
        b.addCapsule(
            v3(to.x + mathx.cosf(a) * 0.020 * W, to.y - 0.030 * W, to.z - 0.060 * W),
            v3(to.x + mathx.cosf(a) * (0.020 * W + l), to.y - 0.030 * W + mathx.sinf(a) * l * 0.6, to.z - 0.060 * W - l * 0.8),
            0.008 * W,
            0.0025 * W,
            4,
            HUSK,
        );
    }
}

/// Off the rest chain's own segment lengths, so a resized animal cannot grow a leg the solver does not believe in.
/// The legs are the seam between the two halves of the creature: HIDE over the shoulder, WOOD from the elbow down.
fn buildLimbBone(b: *Builder, i: usize, rest: [N]rl.Vector3, rng: *mathx.Rng) void {
    const child: ?usize = blk: {
        for (0..N) |c| {
            if (PARENT[c] == @as(i32, @intCast(i))) break :blk c;
        }
        break :blk null;
    };
    const len: f32 = if (child) |c| mathx.lenV(mathx.subV(rest[i], rest[c])) else 0.10 * W;
    if (child == null) {
        buildPaw(b, rng);
        return;
    }
    const upper = i == wolf.SHL or i == wolf.SHR or i == wolf.HIPL or i == wolf.HIPR;
    if (upper) {
        b.setMat(.hide);
        b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.070 * W, 0.046 * W, 9, HIDE);
        b.addBlob(v3(rng.signed() * 0.006 * W, -len * 0.20, 0.006 * W), v3(0.078 * W, 0.066 * W, 0.072 * W), 4, 9, HIDE_LT);
        b.setMat(.bark);
        b.addCapsule(v3(0, -len * 0.10, -0.052 * W), v3(0, -len * 0.96, -0.030 * W), 0.016 * W, 0.010 * W, 5, STALK_DK);
        return;
    }
    b.setMat(.bark);
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), 0.042 * W, 0.030 * W, 8, LIMB);
    // The joint above it, and the fetlock swelling at the bottom: a plain graded pipe is what the old legs were.
    // SMALL — at 0.058 W against a 0.050 W shank these read as bamboo nodes.
    b.addBlob(v3(0, -0.006 * W, 0.004 * W), v3(0.048 * W, 0.040 * W, 0.046 * W), 4, 8, LIMB_LT);
    b.addBlob(v3(0, -len * 0.94, 0.004 * W), v3(0.036 * W, 0.030 * W, 0.036 * W), 4, 8, LIMB_LT);
    var k: u32 = 0;
    while (k < 2) : (k += 1) {
        const a = rng.angle();
        const rr = 0.038 * W;
        b.addCapsule(
            v3(mathx.cosf(a) * rr, -len * 0.12, mathx.sinf(a) * rr),
            v3(mathx.cosf(a) * rr * 0.5, -len * 0.92, mathx.sinf(a) * rr * 0.5),
            0.010 * W * rng.range(0.7, 1.3),
            0.005 * W,
            4,
            STALK_DK,
        );
    }
}

fn buildPaw(b: *Builder, rng: *mathx.Rng) void {
    b.setMat(.hide);
    b.addBlob(v3(0, -0.020 * W, 0.026 * W), v3(0.066 * W, 0.034 * W, 0.080 * W), 8, 6, HIDE_DK);
    b.setMat(.bark);
    var k: u32 = 0;
    while (k < 4) : (k += 1) {
        const fk = @as(f32, @floatFromInt(k)) - 1.5;
        const x = fk * 0.031 * W;
        const l = 0.070 * W * rng.range(0.80, 1.24);
        const tip = v3(x + fk * 0.014 * W, -0.028 * W, 0.055 * W + l);
        b.addCapsule(v3(x, -0.020 * W, 0.030 * W), tip, 0.017 * W * rng.range(0.85, 1.15), 0.010 * W, 6, LIMB);
        b.addCapsule(
            tip,
            v3(tip.x + rng.range(-0.006, 0.006) * W, tip.y - 0.022 * W, tip.z + 0.030 * W * rng.range(0.7, 1.3)),
            0.010 * W,
            0.0035 * W,
            5,
            CLAW,
        );
    }
    const side: f32 = if (rng.float() < 0.5) 1.0 else -1.0;
    b.addCapsule(
        v3(side * 0.052 * W, -0.008 * W, -0.006 * W),
        v3(side * 0.076 * W, -0.030 * W, 0.014 * W),
        0.011 * W,
        0.004 * W,
        4,
        CLAW,
    );
}


test "THE BLOOM IS THE TELL AND IT ONLY OPENS FOR THE LEAP — shut standing, shut walking, shut on a swipe" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    var widest: f32 = 0;
    while (t < 3.0) : (t += dt) {
        r.pos = mathx.zero3;
        r.state = .idle;
        _ = r.update(dt, mathx.ground(0, BITE_R * 0.8), 200.0, .{});
        if (r.state == .idle or r.state == .move) widest = @max(widest, r.openAmt());
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), widest, 1e-6);

    var q = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    q.state = .rake;
    q.t = RAKE_WIND * 0.9;
    try std.testing.expectApproxEqAbs(@as(f32, 0), q.openAmt(), 1e-6);
    q.state = .move;
    try std.testing.expectApproxEqAbs(@as(f32, 0), q.openAmt(), 1e-6);
}

test "…AND THE LEAP'S OWN CLOCK OPENS IT: a tighten, a burst that overshoots, a hold, then shut" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.state = .bite;

    r.t = BITE_WIND * CLAMP_BY;
    const tight = r.openAmt();
    try std.testing.expect(tight < -BLOOM_CLAMP * 0.9); // the bud TIGHTENS first

    var over: f32 = 0;
    var t: f32 = 0;
    while (t <= BITE_WIND) : (t += 1.0 / 480.0) {
        r.t = t;
        over = @max(over, r.openAmt());
    }
    try std.testing.expect(over > 1.0 + BLOOM_SNAP * 0.9);
    // Settled back onto wide inside the wind, and from there the only thing moving it is AIRSPEED — so from the
    // settle through the whole strike it sits in [1, 1 + BLOOM_DRAG] and never dips under wide.
    r.t = BITE_WIND * SETTLE_BY - 1e-4;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), r.openAmt(), 1e-3);
    var t2: f32 = BITE_WIND * SETTLE_BY;
    while (t2 <= HOP_END) : (t2 += 1.0 / 480.0) {
        r.t = t2;
        try std.testing.expect(r.openAmt() >= 1.0 and r.openAmt() <= 1.0 + BLOOM_DRAG + 1e-4);
    }

    r.t = HOP_END + BITE_RECOVER * SHUT_BY * 0.55;
    const half = r.openAmt();
    try std.testing.expect(half > -1.0 and half < 0.75);
    r.t = HOP_END + BITE_RECOVER;
    try std.testing.expectApproxEqAbs(-BLOOM_CLAMP * 0.5, r.openAmt(), 1e-3);

    const led = BITE_WIND - BITE_WIND * OPEN_BY;
    std.debug.print("\n  ravager bloom: wide {d:.3} s before the launch, {d:.3} s before the strike (floor {d:.2})\n", .{
        LAUNCH_T - BITE_WIND * OPEN_BY, led, foe.TELL_MIN,
    });
    try std.testing.expect(BITE_WIND * OPEN_BY < LAUNCH_T);
    try std.testing.expect(BITE_WIND >= foe.TELL_MIN);
}

test "A HEAVY STUN BLOWS IT OPEN AND A LIGHT ONE DOES NOT — the window is worth aiming for or it is not a window" {
    var heavy = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    heavy.stagger(true);
    var wide: f32 = 0;
    var t: f32 = 0;
    const dur = combat.foeStunDur(true);
    while (t <= dur) : (t += 1.0 / 240.0) {
        heavy.t = t;
        wide = @max(wide, heavy.openAmt());
    }
    try std.testing.expect(wide > 0.95);
    heavy.t = dur;
    try std.testing.expectApproxEqAbs(@as(f32, 0), heavy.openAmt(), 1e-4);

    var light = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    light.stagger(false);
    t = 0;
    while (t <= combat.foeStunDur(false)) : (t += 1.0 / 240.0) {
        light.t = t;
        try std.testing.expectApproxEqAbs(@as(f32, 0), light.openAmt(), 1e-6);
    }
}

test "THE OPEN THROAT COSTS IT: the same swing takes near twice off a bloomed body, and NOT off its poise" {
    const swing = foe.Blade{
        .active = true,
        .r = 0.35,
        .a = v3(0, 0.8, -1.2),
        .b = v3(0, 0.8, 1.2),
        .a0 = v3(0, 0.8, -1.2),
        .b0 = v3(0, 0.8, 1.2),
        .hit = .{ .dmg = 10, .poise = 10, .stance = 4 },
    };
    var shut = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    shut.tryHit(swing);
    const shutTook = HP_MAX - shut.vit.hp;

    var open = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    open.state = .bite;
    open.t = BITE_WIND * SETTLE_BY;
    try std.testing.expect(open.openAmt() >= 1.0);
    open.tryHit(swing);
    const openTook = HP_MAX - open.vit.hp;
    std.debug.print("\n  ravager frailty: {d:.1} shut vs {d:.1} bloomed off one 10 dmg swing (x{d:.2})\n", .{ shutTook, openTook, openTook / shutTook });
    try std.testing.expectApproxEqAbs(1.0 + BLOOM_FRAIL, openTook / shutTook, 0.02);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), shut.frailty(), 1e-6);

    // A creature's flinch is the HEALTH a blow took (`combat.FOE_POISE_PER_DMG`, owner's rule), so the bloom's
    // frailty does reach the poise: the light poke that a shut body shrugs off flinches an open one. That is the
    // window paying out twice, and it is the rule and not this creature's choice.
    var poke = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    poke.state = .bite;
    poke.t = BITE_WIND * SETTLE_BY;
    var light = swing;
    light.hit = heromod.ATK_LIGHT_HIT;
    poke.tryHit(light);
    try std.testing.expect(poke.state == .hurt);
}

test "THE CLAW OWNS THE FLANK AND THE BLOOM OWNS THE FRONT — neither answers the other's ground" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.facing = 0; // +Z is its nose
    const near = RAKE_R * r.scale + foe.HERO_R - 0.1;
    // Square in front, at the claw's own range: the claw REFUSES. That is the leap's ground.
    try std.testing.expect(!r.wantsRake(v3(0, 0, near), near));
    const side = v3(near * 0.94, 0, near * 0.34);
    try std.testing.expect(r.wantsRake(side, mathx.lenXZ(side)));
    try std.testing.expect(r.wantsRake(v3(0, 0, -near), near));
    try std.testing.expect(!r.wantsRake(v3(0, 0, -(near + 1.5)), near + 1.5));
    r.rakeCool = 1.0;
    try std.testing.expect(!r.wantsRake(side, mathx.lenXZ(side)));
}

test "A ROOTED RAVAGER STILL HAS ITS CLAWS — the leap is what the roots take" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.root.grab();
    const at = v3(1.05, 0, 0.30); // off the shoulder, inside a paw
    var swiped = false;
    var t: f32 = 0;
    while (t < combat.ROOT_HOLD * 0.9) : (t += 1.0 / 60.0) {
        _ = r.update(1.0 / 60.0, at, 500.0, .{});
        try std.testing.expect(!r.airborne());
        try std.testing.expect(r.state != .bite);
        if (r.swiped) swiped = true;
    }
    try std.testing.expect(swiped);
}

test "THE SWIPE LANDS ONCE, ON ITS OWN SIDE, AND ONLY AFTER THE TELL — and the bud says nothing" {
    const at = v3(1.05, 0, 0.30);
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.rakeSide = 1;
    r.state = .rake;
    r.t = 0;
    var lands: u32 = 0;
    var duringWind: u32 = 0;
    var widest: f32 = 0;
    var t: f32 = 0;
    while (t < RAKE_WIND + RAKE_STRIKE + RAKE_RECOVER + 0.1) : (t += 1.0 / 60.0) {
        if (r.state == .rake) widest = @max(widest, r.openAmt());
        _ = r.update(1.0 / 60.0, at, 500.0, .{});
        if (r.heroHit != null) {
            lands += 1;
            // The clock is read AFTER the step, so a frame that crossed into the strike counts as the strike.
            if (r.state == .rake and r.t < RAKE_WIND) duringWind += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 1), lands);
    try std.testing.expectEqual(@as(u32, 0), duringWind);
    // Every bloom clock gates on `.bite` or the stun, so the swipe cannot promise a leap OR offer its window.
    try std.testing.expectApproxEqAbs(@as(f32, 0), widest, 1e-6);

    var q = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    q.rakeSide = -1;
    q.state = .rake;
    q.t = RAKE_WIND + RAKE_STRIKE * 0.5;
    q.tryRake(at);
    try std.testing.expect(q.heroHit == null);

    try std.testing.expect(RAKE_HIT.stance == 0 and BITE_HIT.stance > 0);
    try std.testing.expect(RAKE_HIT.raw() < BITE_HIT.raw());
    try std.testing.expect(RAKE_WIND + RAKE_STRIKE < BITE_WIND + BITE_STRIKE + BITE_RECOVER);
}

test "THE PAW LEAVES THE EARTH AND COMES BACK — one signed clock, and it crosses zero at the blow" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.state = .rake;
    r.t = 0;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.rakeAmt(), 1e-6);
    r.t = RAKE_WIND;
    try std.testing.expectApproxEqAbs(@as(f32, -1), r.rakeAmt(), 0.02);
    r.t = RAKE_WIND + RAKE_STRIKE;
    try std.testing.expectApproxEqAbs(@as(f32, 1), r.rakeAmt(), 0.02);
    r.t = RAKE_WIND + RAKE_STRIKE + RAKE_RECOVER;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.rakeAmt(), 0.02);
    r.state = .idle;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.rakeAmt(), 1e-6);

    // MEASURED off the posed rig: the swiping paw travels, and it travels ACROSS rather than up.
    var lo = v3(999, 999, 999);
    var hi = v3(-999, -999, -999);
    r.state = .rake;
    r.rakeSide = 1;
    var t: f32 = 0;
    while (t <= RAKE_WIND + RAKE_STRIKE) : (t += 1.0 / 120.0) {
        r.t = t;
        r.pose();
        const paw = rl.math.vector3Transform(mathx.zero3, r.xf[wolf.PAWL]);
        lo = v3(@min(lo.x, paw.x), @min(lo.y, paw.y), @min(lo.z, paw.z));
        hi = v3(@max(hi.x, paw.x), @max(hi.y, paw.y), @max(hi.z, paw.z));
    }
    const across = mathx.lenXZ(v3(hi.x - lo.x, 0, hi.z - lo.z));
    std.debug.print("\n  rake: paw travels {d:.2} m across, {d:.2} m up, from x {d:.2} to {d:.2}\n", .{ across, hi.y - lo.y, lo.x, hi.x });
    try std.testing.expect(across > 0.45);
    try std.testing.expect(hi.y - lo.y < across);
}

test "THE GATHER THREATENS AND THE STRIKE CUTS — the blow lands inside that window and nowhere else" {
    const hero = mathx.ground(0, 1.2);
    const dt: f32 = 1.0 / 60.0;
    for ([_]f32{ 0, BITE_WIND * 0.5, BITE_WIND - 2 * dt }) |at| {
        var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
        r.state = .bite;
        r.t = at - dt;
        _ = r.update(dt, hero, 200.0, .{});
        try std.testing.expect(r.heroHit == null);
    }
    var hit = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    hit.state = .bite;
    hit.t = BITE_WIND;
    try std.testing.expect(hit.update(dt, hero, 200.0, .{}) != null);
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
    r.t = BITE_WIND + BITE_STRIKE;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.leapLift(), 1e-6);
    try std.testing.expect(!r.airborne());
}

test "THE BLOOM RAKES DOWN THROUGH HIM — it rears above his head and the DIVE brings it into his column" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.pose();
    const rest = r.bloomPoint().y - r.pos.y + BLOOM_R;
    r.state = .bite;
    r.t = BITE_WIND - 1e-4;
    r.pounce = 1.0;
    r.pose();
    const reared = r.bloomPoint().y - r.pos.y;
    r.t = BITE_WIND + BITE_STRIKE * DIVE_BY;
    r.pose();
    const struck = r.bloomPoint().y - r.pos.y;
    std.debug.print("\n  ravager bloom: {d:.2} m standing, {d:.2} m reared, {d:.2} m at the strike (hero {d:.2}..{d:.2})\n", .{
        rest, reared, struck, foe.HERO_LOW, foe.HERO_HIGH,
    });
    try std.testing.expect(reared > foe.HERO_HIGH);
    try std.testing.expect(struck + BLOOM_R > foe.HERO_LOW);
    try std.testing.expect(struck - BLOOM_R < foe.HERO_HIGH);
    try std.testing.expect(struck < reared - 0.6);
}

test "A BUD SHUT IS A MUZZLE AND OPEN IT IS A METRE AND A THIRD OF FLOWER — measured off the fold" {
    const across = struct {
        /// The widest point ANYWHERE ALONG the seven blades, radially about the bloom's own axis, in metres of
        /// half-span. Sampled and not taken off the tips: shut, a bud's widest cross-section is at the calyx and
        /// its tips have already converged, so a tip-only reading calls a closed flower narrow and a fat one closed.
        fn wide(open: f32) f32 {
            var out: f32 = 0;
            for (PETALS) |q| {
                var k: u32 = 0;
                while (k <= 16) : (k += 1) {
                    const p = atInBloom(q, open, @as(f32, @floatFromInt(k)) / 16.0);
                    out = @max(out, @sqrt(p.x * p.x + p.y * p.y));
                }
            }
            return out;
        }
        /// …and how far FORWARD of the throat the furthest tip stands. Negative once the corolla reflexes past flat.
        fn long(open: f32) f32 {
            var out: f32 = -9;
            for (PETALS) |q| out = @max(out, atInBloom(q, open, 1.0).z - CALYX_Z);
            return out;
        }
    };

    const budW = across.wide(0);
    const budL = across.long(0);
    const openW = across.wide(1);
    const openL = across.long(1);
    std.debug.print("\n  ravager corolla: bud {d:.2} m across x {d:.2} m long | open {d:.2} m across, tips {d:.2} m forward\n", .{
        budW * 2, budL, openW * 2, openL,
    });
    try std.testing.expect(budL > budW * 2.0);
    try std.testing.expect(openW > budW * 2.5);
    try std.testing.expect(openW * 2 > 1.0);
    try std.testing.expect(openL < budL * 0.2);

    // THE FLING CARRIES THE BLADES PAST THEIR REST AND THEY SPRING BACK ONTO IT. Measured on the FOLD, which is
    // where the overshoot lives: past 73 deg the sweep COSTS radius, so the whip reads as the corolla snapping
    // back toward the stalk and settling forward — not as a wider flower for a frame.
    try std.testing.expect(foldOf(PETALS[0], 1.0 + BLOOM_SNAP) > foldOf(PETALS[0], 1.0) + 12.0);

    // …AND THE RING SITS ON THE WIDEST FOLD RATHER THAN PAST IT. `PETAL_WIDE` dialled up to look "more open"
    // makes the flower narrower, so the distance from the peak is pinned rather than left to a later retune.
    const peak = mathx.degrees(std.math.atan(1.0 / (PETAL_BOW + PETAL_RECURVE)));
    var worst: f32 = 0;
    for (PETALS) |q| worst = @max(worst, @abs(foldOf(q, 1) - peak));
    std.debug.print("  …widest fold is {d:.0} deg and the ring stands at most {d:.0} deg off it\n", .{ peak, worst });
    try std.testing.expect(worst < 45.0);

    var minGap: f32 = 360;
    var maxGap: f32 = 0;
    for (PETALS) |a| {
        var best: f32 = 360;
        for (PETALS) |c| {
            if (a.bone == c.bone) continue;
            best = @min(best, @abs(mathx.wrapDeg(c.ang - a.ang)));
        }
        minGap = @min(minGap, best);
        maxGap = @max(maxGap, best);
    }
    std.debug.print("  …seven petals, nearest neighbours {d:.0} to {d:.0} deg apart (an even ring would be 51)\n", .{ minGap, maxGap });
    try std.testing.expect(maxGap > minGap * 1.5);
    // …AND NO BALD SECTOR. A 76-degree gap came back as a hole in the open corolla, so the unevenness is bounded
    // at the top as well as pushed at the bottom — wabi-sabi is an uneven ring, not a missing petal.
    try std.testing.expect(maxGap <= 66.0);
}

test "IT IS A FOE, NOT A SPIRIT — its own tether, its own souls, and it answers for its own kind" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expectEqual(wf.FoeKind.florid_ravager, r.kind());
    try std.testing.expect(r.alive() and !r.dying() and !r.staggered());
    // The contract's accessors all answer off ONE body, so a bar anchored on one and a reticle on another cannot drift.
    try std.testing.expect(r.hurtRadius() > r.bodyR());
    try std.testing.expect(r.topWorld().y > r.centerWorld().y);
    const markOut = mathx.lenV(mathx.subV(r.centerWorld(), r.lockPoint()));
    std.debug.print("\n  ravager mark stands {d:.2} m off the hurt centre (sphere r {d:.2}, body r {d:.2})\n", .{ markOut, r.hurtRadius(), r.bodyR() });
    try std.testing.expect(markOut < r.hurtRadius());
    r.stageGather(1.0);
    const reared = mathx.lenV(mathx.subV(r.centerWorld(), r.lockPoint()));
    try std.testing.expect(reared < r.hurtRadius());
    _ = r.vit.hit(.{ .dmg = 5, .poise = POISE_MAX + 1 });
    r.stagger(true);
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
    try std.testing.expect(burnt.vit.damageFrom(fire) > 20.0);
    try std.testing.expect(frozen.vit.damageFrom(cold) < 20.0);
    try std.testing.expect(burnt.vit.damageFrom(fire) > frozen.vit.damageFrom(cold));
}

test "THE LEAP IS COMMITTED AT THE LAUNCH — it aims while the bloom opens and steers not at all after" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.state = .bite;
    r.t = 0;
    const side = mathx.ground(6, 0);
    var t: f32 = 0;
    while (t < BITE_WIND - 0.02) : (t += 1.0 / 60.0) _ = r.update(1.0 / 60.0, side, 200.0, .{});
    const aimed = r.facing;
    try std.testing.expect(@abs(mathx.wrapPi(aimed - mathx.headingXZ(mathx.dirXZ(r.pos, side)))) < 0.5);
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
    try std.testing.expect(r.navWant(hero) != null);
    r.state = .bite;
    try std.testing.expect(r.navWant(hero) == null);
    r.state = .hurt;
    try std.testing.expect(r.navWant(hero) == null);
    r.state = .dead;
    try std.testing.expect(r.navWant(hero) == null);
}

test "IT CAN ACTUALLY HURT HIM — a foe lands a blow by RETURNING one, and one leap lands exactly one" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    const hero = mathx.ground(0, 1.2);
    r.leash.noteSeen();
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
    try std.testing.expect(opened);
    try std.testing.expectEqual(@as(usize, 1), landed);
}

test "A LEAP THAT WENT PAST HIM DOES NOT BITE HIM IN THE BACK OF THE NECK" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.state = .bite;
    r.t = BITE_WIND;
    r.tryBite(mathx.ground(0, -1.2));
    try std.testing.expect(r.heroHit == null);
    r.tryBite(mathx.ground(0, BITE_R + foe.HERO_REACH + 0.6));
    try std.testing.expect(r.heroHit == null);
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
    r.tryHit(swing);
    try std.testing.expectEqual(@as(u32, 1), r.hits);
    // Its own leap's clock may not clear that latch — it clears `heroLatch`, a different fact. The SAME swing is still live across the frame, so it stays one wound.
    r.state = .bite;
    r.t = BITE_WIND + BITE_STRIKE + BITE_RECOVER;
    _ = r.update(1.0 / 60.0, mathx.ground(0, 40), 200.0, swing);
    try std.testing.expectEqual(@as(u32, 1), r.hits);
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
    for ([_]State{ .idle, .move, .bite, .hurt }) |st| {
        var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
        r.state = st;
        r.t = if (st == .bite) BITE_WIND * 0.5 else 0;
        _ = r.update(1.0 / 60.0, mathx.ground(0, 30), 200.0, swing);
        try std.testing.expectEqual(@as(u32, 1), r.hits);
        try std.testing.expect(r.vit.hp < HP_MAX);
    }
}

test "A DEAD ONE WILTS FROM WHATEVER IT WAS WEARING — never a snap shut and never a pop open" {
    var mid = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    mid.state = .bite;
    mid.t = BITE_WIND * SETTLE_BY;
    const before = mid.openAmt();
    try std.testing.expect(before > 0.95);
    mid.enterDeath();
    try std.testing.expectApproxEqAbs(before, mid.openAmt(), 1e-3);
    mid.t = WILT_DUR;
    try std.testing.expectApproxEqAbs(@as(f32, 0), mid.openAmt(), 1e-4);

    var shut = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    shut.enterDeath();
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) {
        _ = shut.update(dt, mathx.ground(0, 3), 200.0, .{});
        try std.testing.expectApproxEqAbs(@as(f32, 0), shut.openAmt(), 1e-6);
    }
}

test "…AND IN DEGREES, which is what the player is actually reading off the head" {
    const shut = foldOf(PETALS[0], 0);
    const wide = foldOf(PETALS[0], 1);
    var minWide: f32 = 999;
    var maxWide: f32 = -999;
    for (PETALS) |q| {
        minWide = @min(minWide, foldOf(q, 1));
        maxWide = @max(maxWide, foldOf(q, 1));
    }
    std.debug.print("\n  ravager petals: keel {d:.0} deg shut, {d:.0} deg wide | the ring spans {d:.0}..{d:.0} deg open\n", .{ shut, wide, minWide, maxWide });
    try std.testing.expect(shut < 0); // converging past parallel IS what closes a bud
    try std.testing.expect(wide > 90); // …and reflexed past flat is what opens one
    try std.testing.expect(maxWide - minWide > 12.0); // no two petals arrive together
}

test "A GIRAFFE FLOWER, NOT A DOG — the stalk is long, upright, and it only stretches for the leap" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.pose();
    const rest = restPose();
    const withers = rest[CHEST].y;
    const head = rest[HEAD].y;
    const out = rest[HEAD].z - rest[CHEST].z;
    std.debug.print("\n  ravager stalk: withers {d:.2} m, head {d:.2} m ({d:.2}x), forward {d:.2} m\n", .{ withers, head, head / withers, out });
    try std.testing.expect(head > withers * 1.5);
    try std.testing.expect(out < (head - withers) * 0.5);

    const shutY = r.bloomPoint().y;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.rearAmt(), 1e-6);
    // A HEAVY STUN OPENS THE FLOWER AND DOES NOT REAR THE STALK: the two read off different clocks on purpose.
    r.stageStun();
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.rearAmt(), 1e-6);
    try std.testing.expect(r.openAmt() > 0.5);

    r.stagePounce(1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), r.rearAmt(), 1e-6);
    const outY = r.bloomPoint().y;
    std.debug.print("  …bloom at {d:.2} m shut, {d:.2} m reaching (leap included)\n", .{ shutY, outY });
    try std.testing.expect(outY > shutY);
    try std.testing.expect(NECK_STRETCH > 0.1 and NECK_STRETCH < 0.4);

    // THE COLLAR COVERS THE SLIDE: the head's own sheath hangs further down the stalk than the stretch can lift it.
    const stalkLen = mathx.lenV(mathx.subV(rest[HEAD], rest[NECK]));
    try std.testing.expect((NECK_STRETCH + 0.09) * W > NECK_STRETCH * W);
    try std.testing.expect((NECK_STRETCH + 0.09) * W < stalkLen);
}

test "THE GATHER LOADS AND THE LANDING ABSORBS — and the coil does not come from the same side twice" {
    var r = Ravager.spawn(mathx.zero3, 0, 1.0, 0.3);
    r.state = .bite;

    var peak: f32 = 0;
    var peakAt: f32 = 0;
    var t: f32 = 0;
    while (t <= HOP_END) : (t += 1.0 / 480.0) {
        r.t = t;
        const g = r.gatherAmt();
        if (g > peak) {
            peak = g;
            peakAt = t;
        }
    }
    try std.testing.expect(peak > 0.99);
    try std.testing.expect(peakAt < BITE_WIND);
    r.t = HOP_END;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.gatherAmt(), 1e-4);

    var lo: f32 = 9;
    var hi: f32 = -9;
    t = HOP_END;
    while (t <= HOP_END + LAND_DUR) : (t += 1.0 / 480.0) {
        r.t = t;
        const l = r.landAmt();
        lo = @min(lo, l);
        hi = @max(hi, l);
    }
    std.debug.print("\n  ravager landing: {d:.2} deepest, {d:.2} on the rebound over {d:.2} s\n", .{ hi, lo, LAND_DUR });
    try std.testing.expect(hi > 0.9 and lo < -0.2);
    r.t = HOP_END + LAND_DUR;
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.landAmt(), 1e-6);

    r.leaps = 0;
    const first = r.coilSide();
    r.leaps = 1;
    try std.testing.expect(r.coilSide() != first);
    var other = Ravager.spawn(mathx.zero3, 0, 1.0, 0.9);
    try std.testing.expect(other.coilSide() != Ravager.spawn(mathx.zero3, 0, 1.0, 0.1).coilSide());
}

test "IT IS ALIVE STANDING STILL — the drift is on a clock no state resets, and no two bodies are in step" {
    var a = Ravager.spawn(mathx.zero3, 0, 1.0, 0.17);
    var b = Ravager.spawn(mathx.zero3, 0, 1.0, 0.83);
    const dt: f32 = 1.0 / 60.0;
    var lo: f32 = 9;
    var hi: f32 = -9;
    var apart: f32 = 0;
    var t: f32 = 0;
    while (t < 12.0) : (t += dt) {
        _ = a.update(dt, mathx.ground(0, 60), 400.0, .{});
        _ = b.update(dt, mathx.ground(0, 60), 400.0, .{});
        lo = @min(lo, a.swayAt());
        hi = @max(hi, a.swayAt());
        apart = @max(apart, @abs(a.swayAt() - b.swayAt()));
    }
    std.debug.print("\n  ravager drift: {d:.2}..{d:.2} of a {d:.1} deg lean, two seeds up to {d:.2} apart\n", .{ lo, hi, SWAY_DEG, apart });
    try std.testing.expect(hi - lo > 0.9);
    try std.testing.expect(apart > 0.4);
    // The clock is `elapsed`, not `t`: a body that idled, walked and idled again has not restarted its drift.
    a.state = .idle;
    a.t = 0;
    try std.testing.expect(a.elapsed > 11.0);
}
