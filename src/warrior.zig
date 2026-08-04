const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const heromod = @import("hero.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");
const archermod = @import("archer.zig"); // THE SAME DEAD MAN — his bones, his scale, his feet
const propart = @import("propart.zig"); // the world's own iron, so his kit is the world's ironwork

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// TWO ROLES OF ONE CORPSE: the archer's skeleton with something else in its fist.

const IRON = propart.IRON; // the world's iron — a warrior's kit is the world's ironwork, not its own
const IRON_LT = rgba(52, 50, 46, 255); // caught-light on a bevel / a knuckle of a flange
const IRON_DK = rgba(19, 18, 17, 255); // the shadowed side of everything forged
const RUST = rgba(66, 42, 24, 255); // grave-rust, in the pits and along the welds
const STEEL = rgba(96, 100, 108, 190); // a kept edge — slightly self-lit, so the blade is the read
const STEEL_DK = rgba(38, 40, 45, 255); // the flat behind that edge
const HAFT = rgba(38, 27, 17, 255); // dark, dried haft-wood
const HAFT_LT = rgba(54, 39, 25, 255);
const WRAP = rgba(44, 33, 24, 255); // cracked leather, on every grip
const BOARD = rgba(48, 35, 25, 255); // the shield's limewood boards…
const BOARD_LT = rgba(70, 53, 37, 255); // …which are not all one plank and not all one tone
const BOARD_DK = rgba(30, 22, 16, 255);
const BLAZON = rgba(74, 32, 30, 255); // what is left of a device nobody remembers

// FX palette. DUST and MOTE are the WORLD's, not this creature's (see foe.zig).
const DUST = foe.DUST;
const MOTE = foe.MOTE;
const CHIP = rgba(150, 140, 116, 235); // bone, knocked off in flakes — these things do not bleed
const SPARK = rgba(255, 208, 128, 240); // iron on iron, off the boards
const SPLINTER = rgba(86, 64, 44, 240); // …and the boards themselves, when they finally go

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
const SHL = heromod.SHL; // shoulder L — the SHIELD arm (and the greatsword's second hand)
const ELL = heromod.ELL;
const WRL = heromod.WRL;
const SHR = heromod.SHR; // shoulder R — the WEAPON arm
const ELR = heromod.ELR;
const WRR = heromod.WRR;
const WPN = heromod.HELD; // mace or greatsword, in the shared weapon slot

const H: f32 = heromod.H;
const REST = heromod.restHumanoid(heromod.HIP_HALF, heromod.SHOULDER_HALF, H);
/// A HAND TALLER AGAIN THAN THE ARCHER (owner: "make them a bit bigger too") — the same corpses out of
/// the same ground, but the ones buried holding iron were the big men. DERIVED off the archer's own
/// stature, which is itself derived off the hero's, so nothing here is a magic 1.26.
pub const SCALE = archermod.SCALE + 0.155 / H;
const solePatches = archermod.solePatches;

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;
const lerpF = mathx.lerpF;
const setLocal = heromod.setHumanoid;

/// The fist centre in the wrist frame — the archer's own grip anchor, because it is the same hand.
const FIST_Y = -0.05 * H;
const FIST_Z = 0.02 * H;

/// THE WEAPON IN THE FIST. Both kits are authored pointing UP off the grip (they were built in the
/// archer's bow frame, whose +Y runs back up the forearm), so the fit FLIPS them — and after it
/// `wpnTilt` means what the hero's own `GRIP_PITCH` means: degrees the weapon leads FORWARD of the
/// forearm line, 0 straight down it and away from the elbow.
fn wpnFit(tilt: f32) rl.Matrix {
    return mul(ry(180.0), rx(180.0 - tilt));
}

/// A SWING KEEPS THE WEAPON'S OWN ATTITUDE SMOOTH, NOT ITS WRIST ANGLE. Hold `wpnTilt` steady through a
/// 220-degree shoulder sweep and the weapon is radial to the arm at the bottom of the arc, which for two
/// metres of steel on a two-and-a-half-metre skeleton means the point goes UNDER THE TURF — measured at
/// 0.44 m beneath it, beside his own boot. So the mace's blow and the diagonal author where the kit POINTS
/// (degrees forward of straight down: 0 down, 90 level, 180 stood on end) and this hands the wrist
/// whatever that costs. The LUNGE does not: a thrust is the ARM travelling, and its wrist angle is the
/// honest thing to author.
fn swingTilt(windAtt: f32, endAtt: f32, k: f32, armSh: f32) f32 {
    return lerpF(windAtt, endAtt, k) - armSh;
}

/// THE KIT'S OWN LENGTHS off the fist, in stature. The MESHES are built from these and so is the hurt
/// segment below — one set of numbers, because a blade lengthened in the modeller that keeps the reach it
/// had is the whole failure this file was rewritten to end.
const MACE_HEAD = 0.30 * H; // fist → the drum's centre
const MACE_CAP = 0.062 * H; // …and on past it to the spike over the drum
const GS_GUARD = 0.115 * H; // fist → the crossguard
const GS_BLADE = 0.76 * H; // guard → the point
const MACE_FLANGE = 0.046 * H; // …and their WIDTHS: the flanges' stand-off off the drum…
const GS_HALF_W = 0.049 * H; // …and the blade at its broadest, just above the guard

/// THE BUSINESS END of each kit, grip end → far end, in the SAME authored frame as the mesh: ride these
/// through `xf[WPN]` and you have the weapon's own segment in world space, exactly as the hero's blade
/// rides `BLADE_BASE`/`BLADE_TIP` through his. What a warrior HITS is this segment and nothing else.
const KIT_SEG = [SPEC.len][2]rl.Vector3{
    .{ v3(0, FIST_Y - 0.02 * H, FIST_Z), v3(0, FIST_Y + MACE_HEAD + MACE_CAP, FIST_Z) }, // fist → the head
    .{ v3(0, FIST_Y + GS_GUARD, FIST_Z), v3(0, FIST_Y + GS_GUARD + GS_BLADE, FIST_Z) }, // guard → point
};
/// …and how fat that segment swings — THE KIT'S OWN WIDEST PART, off the same numbers the meshes are
/// built from. `foe.HERO_REACH` is added on top at the test, the slack every foe in the game is given.
const KIT_R = [SPEC.len]f32{ MACE_FLANGE, GS_HALF_W };

pub const Role = enum { shieldman, greatsword };

comptime {
    // A CONTIGUOUS RUN off `shieldman`, in role order — `roleOf`/`kindOf` are an ordinal shift.
    for (@typeInfo(Role).@"enum".fields, 0..) |f, i| {
        const fk: wf.FoeKind = @enumFromInt(@intFromEnum(wf.FoeKind.shieldman) + i);
        if (!std.mem.eql(u8, f.name, @tagName(fk))) {
            @compileError("warrior: wf.FoeKind." ++ @tagName(fk) ++ " is not in the warriors' contiguous run");
        }
    }
}

/// A map foe kind → the role it posts, or null if it is not a skeletal warrior at all.
pub fn roleOf(k: wf.FoeKind) ?Role {
    const lo = @intFromEnum(wf.FoeKind.shieldman);
    const i = @intFromEnum(k);
    if (i < lo or i >= lo + SPEC.len) return null;
    return @enumFromInt(i - lo);
}

/// …and back.
pub fn kindOf(r: Role) wf.FoeKind {
    return @enumFromInt(@intFromEnum(wf.FoeKind.shieldman) + @intFromEnum(r));
}

/// ONE MOVE. A role's whole moveset is a slice of these, and the state machine reads nothing else —
/// which is what lets the greatsword carry two answers without a second state machine to keep in step.
const Attack = struct {
    /// HOW FAR THE WEAPON ITSELF GETS, pre-scale and MEASURED off the posed kit (`kitSweep`, and the
    /// tests that re-assert it). It is the AI's trigger range and nothing else: what the blow HITS is
    /// the swept weapon (`tryReach`), so this number cannot quietly grow a hurt box the swing never
    /// enters. It shipped that way once — a mace whose head never left 0.6 m of his own axis, firing a
    /// 2.8 m sector.
    reachOut: f32,
    /// THE CLOCK.
    windDur: f32,
    swingDur: f32,
    /// Fraction into the swing the weapon goes LIVE — from here to the end of the stroke the kit's own
    /// swept segment is what decides, so this only has to be early enough not to miss the arc's start.
    impactK: f32,
    recoverDur: f32,
    cd: f32,
    hit: combat.Hit,
    /// UNINTERRUPTIBLE while winding and swinging: damage lands, stagger does not.
    hyper: bool = false,
    /// Strokes in the combo. Only the FIRST carries the tell (and the leap); the rest follow on
    /// `chainWind`, because a combo whose second swing re-telegraphs is two attacks, not a combo.
    strokes: u8 = 1,
    chainWind: f32 = 0,
    /// Ground the first stroke covers as a committed LEAP, and how high off the earth it goes.
    lunge: f32 = 0,
    hop: f32 = 0,
    /// …and the plainer version of the same thing: ground a stroke carries him forward, no height.
    step: f32 = 0,
    /// The weapon reaches the EARTH at impact — a crater, and the dust that goes with it.
    crash: bool = false,
};

/// THE MACE: short, and no longer FAST (owner: "mace skels swing too fast"). Its threat is that the
/// boards make him hard to answer, not that the blow arrives before you can read it.
const MACE = Attack{
    .reachOut = 1.23, // MEASURED off the posed head: its own furthest, out in front of him at the blow
    .windDur = 0.64, // was 0.40 — the whole point of the retune
    .swingDur = 0.30,
    .impactK = 0.26,
    .recoverDur = 0.74,
    .cd = 1.55,
    .hit = .{ .dmg = 14, .poise = 17 },
    .step = MACE_STEP,
};

/// THE DIAGONAL SLAM: the long tell, the long reach, and the one thing in this file you cannot stop.
const SLAM = Attack{
    .reachOut = 2.18, // MEASURED: near three metres of reach, cocked high and driven down through
    .windDur = 1.05,
    .swingDur = 0.30,
    .impactK = 0.24,
    .recoverDur = 1.15,
    .cd = 2.20,
    .hit = .{ .dmg = 30, .poise = 40, .stance = 18 },
    .hyper = true,
    .crash = true,
};

/// THE LUNGE (owner's call): his QUICK answer, two strokes, and INTERRUPTIBLE — the thing you punish
/// when you have learned to walk out of the slam. It opens with a little LEAP, so it also closes ground.
const LUNGE = Attack{
    .reachOut = 1.98, // MEASURED: the point driven straight out — shorter than the slam's whole arc
    .windDur = 0.34,
    .swingDur = 0.26,
    .impactK = 0.46,
    .recoverDur = 0.66,
    .cd = 3.10,
    .hit = .{ .dmg = 17, .poise = 22 },
    .strokes = 2,
    .chainWind = 0.19,
    .lunge = 1.55,
    .hop = 0.40,
};

const MOVES_SHIELDMAN = [_]Attack{MACE};
const MOVES_GREATSWORD = [_]Attack{ SLAM, LUNGE };

/// ONE ROW PER ROLE. The body, the gait, the bones, the death and the reactions are shared — exactly
/// as the warband's three roles share theirs — so what is left in here is the kit and the numbers.
const Spec = struct {
    hp: f32,
    poise: f32,
    stance: f32,
    /// Ground speed, as a fraction of the hero's walk.
    speed: f32,
    bodyR: f32,
    hurtR: f32,
    runes: u32,
    moves: []const Attack,
};

const SPEC = [_]Spec{
    .{ .hp = 92, .poise = 15, .stance = 42, .speed = 0.86, .bodyR = 0.36, .hurtR = 0.44, .runes = 180, .moves = &MOVES_SHIELDMAN },
    .{ .hp = 124, .poise = 26, .stance = 58, .speed = 0.74, .bodyR = 0.38, .hurtR = 0.46, .runes = 280, .moves = &MOVES_GREATSWORD },
};

fn spec(r: Role) *const Spec {
    return &SPEC[@intFromEnum(r)];
}

comptime {
    std.debug.assert(SPEC.len == @typeInfo(Role).@"enum".fields.len);
    for (SPEC) |s| std.debug.assert(s.moves.len > 0); // a foe with no answer is scenery
}

/// THE WIDEST MOVESET ANY ROLE HAS, off the table itself — the per-move cooldowns and the readiness
/// scratch are sized from this, so giving a role a third move cannot silently index past either.
const MAX_MOVES = blk: {
    var m: usize = 0;
    for (SPEC) |s| m = @max(m, s.moves.len);
    break :blk m;
};

const AGGRO_R = 20.0; // a sentry of the fallen city: it sees you well before it can reach you
const TURN_RATE = 4.6; // rad/s — slower than the hero, quicker than the ogre
const SWING_TURN = 3.0; // rad/s it keeps pivoting THROUGH the swing, so a stroll sideways is not enough
const WALK_SPEED = heromod.WALK_SPEED;
const CIRCLE_DUR = 1.1; // how long one sidestep behind the shield lasts before he re-decides
const CRASH_LOW = 0.30; // m above his own feet the point must get down to before the earth answers
const DEATH_DUR = 1.15;
const DISS_DUR = 0.9;
const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 7.0;
const A_BOB = heromod.A_BOB;
const A_PROT = 3.8; // deg of pelvic transverse rotation — a soldier walks squarer than a scavenger

/// DRY BONE AND NOTHING ELSE — the archer's table, because it is the archer's body (see AGENTS.md's
/// resistance table): it burns, and there is no flesh in it for cold to bite or a poison to find.
const RESISTS = combat.resists(.{ .fire = -35, .cold = 60, .chaos = 45 });

/// HIS BOARDS ARE THIN (owner's call): four of the hero's lights or two of his heavies empty this, and
/// an emptied bar under a blow SHATTERS THE SHIELD — see `caught`.
const SHIELD_STAM: f32 = 62.0;
/// …and the arc those boards actually cover, which is the hero's own — getting round it is the answer.
const GUARD_ARC = combat.GUARD_ARC;

const PELVIS_SHARE: f32 = 0.15; // BIG BODIES HINGE AT THE WAIST: the pelvis takes only this much lean

// THE CARRY — where each armament rides when nothing is happening.
const CARRY_SH = 6.0;
const CARRY_EL = -18.0;
const CARRY_ABD = 12.0;
/// `wpnTilt` MEANS WHAT THE HERO'S `GRIP_PITCH` MEANS (see `wpnFit`): degrees the weapon leads FORWARD
/// of the forearm line, 0 straight down it and away from the elbow. So a carry is a big number — both
/// kits are SHOULDERED at rest, raked right back over the fist — and a blow is a small one, because a
/// blow is the weapon out on the end of the arm.
const MACE_CARRY_TILT = 142.0;
const GS_CARRY_TILT = 118.0; // a greatsword rides point-back over the shoulder line, or it drags
const GS_CARRY_SH = -22.0; // …which needs the arm up, not hanging
const GS_CARRY_ABD = 26.0;

// THE GUARD — the shieldman turtled behind the boards. THE SIGN HERE IS POSITIVE-IS-FORWARD, which is
// the inverse of the archer's own shoulder channel because `poseUpper` negates on the way in; authored
// negative (the obvious reading) the arm swings BACK and the boards end up hanging at his hip, covering
// his shin and nothing else. That is exactly how this shipped the first time.
const GUARD_OFF_SH = 58.0; // the shield arm comes UP and ACROSS…
const GUARD_OFF_ABD = 26.0;
const GUARD_OFF_EL = -78.0;
const GUARD_TWIST = -22.0; // …and he turns his weapon side away, presenting the boards
const GUARD_LEAN = 9.0;
const GUARD_SH = 24.0; // the mace cocked back behind the shield, ready
const GUARD_EL = -52.0;
/// With the boards gone he has nothing to hide behind: he squares up and carries the mace two-handed-ish.
const NAKED_TWIST = -6.0;

// THE MACE SWING. A REAL overarm blow in four parts and not a lerp between two poses: he gathers, he
// cocks, he steps INTO it, and he follows through past his own centre line. THE ARM GOES LONG AT THE
// BLOW — an elbow still folded at impact keeps the head inside his own silhouette, which is what "the
// weapon barely moves but I get hit" was: 0.20 m of head travel behind a 2.8 m hurt box.
const MACE_GATHER_SH = -22.0; // a small settle DOWN and back before the arm goes up (anticipation)
const MACE_GATHER_EL = -38.0;
const MACE_WIND_SH = -140.0; // …then hauled up and BACK, the head carried over his own skull
const MACE_WIND_EL = -22.0;
const MACE_WIND_ABD = 52.0; // …and OUT, so the cock breaks his outline instead of hiding behind it
const MACE_WIND_TWIST = -38.0;
const MACE_WIND_LEAN = -14.0; // he stands UP into the cock, which is what sells the drop after it
const MACE_WIND_TILT = -104.0; // MEASURED: the head above the crown, which is the whole of the tell
const MACE_HIT_SH = 82.0; // driven forward and down, the whole arm out ahead of him
const MACE_HIT_EL = -14.0; // …and near STRAIGHT: this is where the reach comes from
const MACE_HIT_ABD = -4.0;
const MACE_HIT_TWIST = 34.0;
const MACE_OVER_SH = 6.0; // deg the shoulder carries PAST the blow — the overswing
const MACE_HIT_SWEEP = 14.0; // barely across him — an overarm blow lands in FRONT, not off his hip
const MACE_HIT_LEAN = 30.0; // the trunk folds over the blow — the mace is heavy and it goes DOWN
/// WHERE THE HEAD ENDS UP POINTING, as an ATTITUDE and not a wrist angle — see `swingTilt`. It comes
/// over the top and finishes below the blow, which is what makes a heavy stroke land THROUGH a man.
const MACE_END_ATT = 45.0;
const MACE_WIND_ATT = MACE_WIND_SH + MACE_WIND_TILT + 360.0; // the cock's own attitude, wound forward
/// HE STEPS INTO IT. A blow thrown off planted feet reads as a man swatting a fly.
const MACE_STEP = 0.44; // metres of ground the swing carries him forward, pre-scale

// THE DIAGONAL SLAM — high over the right shoulder, down across to the left hip. UNINTERRUPTIBLE.
const GS_WIND_SH = -146.0; // hauled up and BACK, both hands, the blade behind the skull
const GS_WIND_EL = -50.0;
const GS_WIND_ABD = 34.0;
const GS_WIND_TWIST = -48.0; // the whole trunk coils over the back hip
const GS_WIND_LEAN = -18.0; // and arches back under the weight of it
const GS_WIND_TILT = -56.0; // MEASURED: better than three metres up, point over his own skull — the tell
const GS_HIT_SH = 74.0; // driven down and THROUGH, finishing past his off hip
const GS_HIT_EL = -18.0;
const GS_HIT_ABD = -12.0;
const GS_HIT_TWIST = 44.0;
const GS_HIT_SWEEP = 26.0;
const GS_HIT_LEAN = 34.0; // the fold at the waist is what carries the point to the ground
/// …and the blade's, which finishes STEEP: the point ploughs into the earth, and that is the crater.
const GS_END_ATT = 38.0;
const GS_WIND_ATT = GS_WIND_SH + GS_WIND_TILT + 360.0;
/// The wrist angles those two attitudes leave the kit at, for the recoveries to pick the stroke up from.
const MACE_END_TILT = MACE_END_ATT - (MACE_HIT_SH + MACE_OVER_SH);
const GS_END_TILT = GS_END_ATT - GS_HIT_SH;

// THE LUNGE — a low, flat thrust off a little leap, and then a return cut on the way down.
const LUNGE_WIND_SH = -50.0; // chambered back at the hip, point forward: nothing overhead about it
const LUNGE_WIND_EL = -72.0;
const LUNGE_WIND_ABD = 8.0;
const LUNGE_WIND_TWIST = -30.0;
const LUNGE_WIND_LEAN = -6.0;
const LUNGE_WIND_TILT = 60.0; // MEASURED: cocked back level at his own ribs, point already at your chest
const LUNGE_HIT_SH = 50.0; // driven straight out — the arms go LONG, which is what makes it read
const LUNGE_HIT_EL = -12.0;
const LUNGE_HIT_ABD = -6.0;
const LUNGE_HIT_TWIST = 24.0;
const LUNGE_HIT_SWEEP = 12.0;
const LUNGE_HIT_LEAN = 22.0; // out over the lead foot, committed
const LUNGE_HIT_TILT = 56.0; // MEASURED: the point stays LEVEL, at chest height — never over your head
/// A LEAP IS ONE KNEE UP (kobold.zig's law, and it is the same law here): the lead knee is thrown to
/// the chest with the trail leg left extended behind. Both legs tucked to one amount is a hop.
const LEAP_LEAD_HIP = 68.0;
const LEAP_LEAD_KNEE = 82.0;
const LEAP_TRAIL_HIP = 26.0;
const LEAP_TRAIL_KNEE = 22.0;
const LEAP_TOE = 20.0;

/// A GUARD BREAK PUTS HIM ON HIS KNEE (owner's call), AND THE BOARDS DO NOT SURVIVE IT. This is the
/// biggest reaction in the file by a distance, and it is permanent: he fights on with no shield at all.
const BREAK_ARM = 104.0; // the shield arm thrown wide as the boards are smashed off it
const BREAK_STEP = 2.4; // world/s he is driven back off the blow that emptied him
const KNEEL_IN = 0.24; // seconds to go DOWN — fast, it is a collapse
const KNEEL_OUT = 0.62; // …and to get back up, which is slow, and is the punish window
const KNEEL_SINK = 0.315; // fraction of H the pelvis drops onto the knee
const KNEEL_LEAD_HIP = 62.0; // the lead leg braced out in front, foot planted
const KNEEL_LEAD_KNEE = 68.0;
const KNEEL_TRAIL_HIP = 14.0; // …and the trail leg folded right under him, shin on the ground
const KNEEL_TRAIL_KNEE = 122.0;
const KNEEL_FOLD = 19.0; // deg the trunk folds over the planted knee — BEATEN, not face-down
const KNEEL_HEAD = 40.0; // …and the skull hangs

const NPART = 30; // per warrior — a muster can be 48 of them, so this is a ring buffer and stays one

const State = enum { idle, approach, circle, wind, swing, recover, stunlight, stunheavy, guardbreak, dead };

/// What it should be doing THIS decision, off range alone — pure, so it is testable without a world.
const Choice = enum { strike, circle, approach, hold };
fn classify(r: Role, dist: f32, scale: f32, ready: []const bool) Choice {
    if (dist > AGGRO_R) return .hold;
    const moves = spec(r).moves;
    var anyInReach = false;
    for (moves, 0..) |a, i| {
        if (dist > triggerR(a, scale)) continue;
        anyInReach = true;
        if (ready[i]) return .strike;
    }
    if (!anyInReach) return .approach;
    // In reach with nothing to throw: the shieldman WALKS THE FIGHT DOWN behind his boards, where the
    // greatsword — who has no boards and no speed — simply squares up and waits out his own weight.
    return if (r == .shieldman) .circle else .hold;
}

/// How far out a move can be STARTED from. A leap closes most of its own ground, so the lunge may be
/// thrown from well outside the reach the blade itself has when it lands.
fn triggerR(a: Attack, scale: f32) f32 {
    return a.reachOut * scale + a.lunge * 0.85 * scale + foe.HERO_REACH;
}

/// Which move to throw: the FURTHEST-reaching one that is both in range and off cooldown, so the
/// greatsword opens at distance with the slam and keeps the lunge for when you have closed on him.
fn pick(r: Role, dist: f32, scale: f32, ready: []const bool) ?usize {
    const moves = spec(r).moves;
    var best: ?usize = null;
    var bestR: f32 = -1;
    for (moves, 0..) |a, i| {
        if (!ready[i] or dist > triggerR(a, scale)) continue;
        if (a.reachOut > bestR) {
            bestR = a.reachOut;
            best = i;
        }
    }
    return best;
}

/// ONE MOVE'S CLOCK, for the shot harness to aim its beats WITH instead of copying seconds out of the
/// table by hand: a portrait pinned to a literal 0.58 s silently photographs a different beat the next
/// time the timing is tuned, and the whole point of the mace beats is that they show the anticipation.
pub const Clock = struct { wind: f32, swing: f32, chain: f32, recover: f32 };
pub fn moveClock(role: Role, mv: usize) Clock {
    const moves = spec(role).moves;
    const a = moves[@min(mv, moves.len - 1)];
    return .{ .wind = a.windDur, .swing = a.swingDur, .chain = a.chainWind, .recover = a.recoverDur };
}

pub const Model = struct {
    bone: [N]rl.Mesh, // the bare skeleton; `bone[WPN]` is UNDEFINED and never drawn (see archer.boneMeshes)
    kit: [SPEC.len]rl.Mesh, // what is in the fist, by role
    shield: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("warrior material");
        mat.shader = shader;
        const kit = [_]rl.Mesh{ maceMesh(), greatswordMesh() };
        var bone = archermod.boneMeshes();
        // `boneMeshes` hands back the HELD slot UNDEFINED, and the draw loop skips it — but a struct
        // with undefined bytes in it still gets COPIED out of here, and reading undefined memory is
        // illegal behaviour whether or not anybody draws it. Give it something real.
        bone[WPN] = kit[0];
        return .{ .bone = bone, .kit = kit, .shield = shieldMesh(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, w: *const Warrior) void {
        for (0..N) |i| {
            if (i == WPN) continue; // the weapon slot is the ROLE's, not the skeleton's
            rl.drawMesh(self.bone[i], self.mat, w.xf[i]);
        }
        rl.drawMesh(self.kit[@intFromEnum(w.role)], self.mat, w.xf[WPN]);
        // THE SHIELD IS NOT A BONE — it rides the left wrist, the pattern hero.zig set for its own.
        // …and once it has been broken off him there is nothing there to draw, ever again.
        if (w.role == .shieldman and !w.shieldGone) rl.drawMesh(self.shield, self.mat, mul(shieldFit(), w.xf[WRL]));
    }
};

pub const Warrior = struct {
    role: Role = .shieldman,
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    /// ITS TETHER to `home`, and how hard the player has provoked it (see foe.Leash).
    leash: foe.Leash = .{},
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    /// WHICH MOVE is in progress, and how far into its combo — an index into `spec(role).moves`.
    atk: usize = 0,
    stroke: u8 = 0,
    /// …and one cooldown PER MOVE, so a spent slam does not lock out the lunge.
    cds: [MAX_MOVES]f32 = [_]f32{0} ** MAX_MOVES,
    dealt: bool = false, // one blow per stroke, latched
    crashed: bool = false, // …and one crater per stroke
    heroHit: ?combat.Hit = null, // this frame's blow ON the hero, read by the Muster
    moveDir: rl.Vector3 = mathx.zero3,
    homing: bool = false,
    /// The committed leap: ground already covered (so travel integrates once) and height off the earth.
    leapDone: f32 = 0,
    hop: f32 = 0,
    /// Was the shield covering the hero's bearing at the top of THIS frame? `tryHit` reads it, because
    /// a blade arrives knowing nothing about where the hero is standing.
    covered: bool = false,
    /// THE BOARDS ARE OFF HIM FOR GOOD. Set by the guard break and never cleared: a broken shield is
    /// broken (owner's call), so the fight after it is a different fight.
    shieldGone: bool = false,
    /// THE SHIELDMAN'S OWN POOL. The greatsword carries one too and never spends it — a second struct
    /// for "the one with a shield" would fork the pose, the gait and the state machine along with it.
    stam: combat.Stamina = combat.Stamina.initFoe(SHIELD_STAM),
    blockT: f32 = mathx.LONG_AGO, // seconds since the boards last caught something (the recoil)

    // posture channels (degrees), resolved by the state and read by pose()
    armSh: f32 = CARRY_SH,
    armEl: f32 = CARRY_EL,
    armAbd: f32 = CARRY_ABD,
    armSweep: f32 = 0, // the weapon arm's HORIZONTAL swing across his front — what makes a diagonal
    wpnTilt: f32 = MACE_CARRY_TILT, // the weapon's rake in the fist
    offSh: f32 = CARRY_SH,
    offEl: f32 = CARRY_EL,
    offAbd: f32 = -CARRY_ABD,
    bodyLean: f32 = 4.0,
    twist: f32 = 0,
    headPitch: f32 = 2.0,
    headYaw: f32 = 0,
    legBrace: f32 = 0,

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,
    prevPhase: f32 = 0, // footfall dust fires on the stride half-cycles

    vit: combat.Vitals = combat.Vitals.initFoe(SPEC[0].hp, SPEC[0].poise, SPEC[0].stance).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    head: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,
    /// THE KIT'S SWEEP ACROSS ONE FRAME — where the weapon was and where it is. `tryReach` tests the
    /// ground between the two, because a whipped head covers half a metre in a frame and a blow that
    /// only tests endpoints passes clean through a body.
    wpnWas: [2]rl.Vector3 = .{ mathx.zero3, mathx.zero3 },
    wpnIs: ?[2]rl.Vector3 = null, // null until the first pose: a foe's first frame sweeps from nowhere
    /// Is the kit LIVE this frame? Set by the swing, spent AFTER `pose()` — the hurt shape is the posed
    /// weapon, so it cannot be tested before the pose it is measured off exists.
    live: bool = false,

    pub fn spawnAs(role: Role, home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Warrior {
        const sp = spec(role);
        var w = Warrior{
            .role = role,
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .vit = combat.Vitals.initFoe(sp.hp, sp.poise, sp.stance).withRes(RESISTS),
        };
        w.rest = REST;
        w.fxRng = foe.fxStream(seed, 71237.0, 11);
        for (&w.cds) |*c| c.* = 0.3 + seed * 0.9; // stagger a line of them out of lockstep
        w.setCarryInstant();
        w.pose();
        return w;
    }

    fn move(self: *const Warrior) Attack {
        const moves = spec(self.role).moves;
        return moves[@min(self.atk, moves.len - 1)];
    }

    // EVERY WORLD POINT IS MEASURED FROM `pos.y` PLUS `hop` — the lunge lifts the whole rig off the
    // earth, and a hurt sphere pinned to the ground would sit at his feet for the whole leap.
    pub fn centerWorld(self: *const Warrior) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + archermod.CENTER_F * H * self.scale + self.hop, self.pos.z);
    }
    pub fn hurtRadius(self: *const Warrior) f32 {
        return spec(self.role).hurtR * self.scale;
    }
    pub fn bodyR(self: *const Warrior) f32 {
        return spec(self.role).bodyR * self.scale;
    }
    pub fn lockPoint(self: *const Warrior) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + archermod.LOCK_F * H * self.scale + self.hop, self.pos.z);
    }
    pub fn topWorld(self: *const Warrior) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + archermod.TOP_F * H * self.scale + self.hop, self.pos.z);
    }
    pub fn alive(self: *const Warrior) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Warrior) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Warrior) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .guardbreak or self.state == .dead;
    }
    pub fn flashFrac(self: *const Warrior) f32 {
        return foe.flashFrac(self.flash);
    }
    /// Off the ground only through the lunge's leap — the one time either of them leaves the earth.
    pub fn airborne(self: *const Warrior) bool {
        return self.hop > foe.AIRBORNE_LIFT;
    }
    pub fn runeValue(self: *const Warrior) u32 {
        return spec(self.role).runes;
    }
    pub fn kind(self: *const Warrior) wf.FoeKind {
        return kindOf(self.role);
    }
    /// HOW MUCH GUARD IS LEFT — the HUD does not draw it, but the shot harness and the tests read it.
    pub fn guardFrac(self: *const Warrior) f32 {
        return if (self.role == .shieldman and !self.shieldGone) self.stam.frac() else 0;
    }

    /// THE BOARDS ARE UP: his own choice of state, never while the bar is spent, and NEVER AGAIN once
    /// they have been broken off him.
    pub fn guardUp(self: *const Warrior) bool {
        if (self.role != .shieldman or self.gone or self.shieldGone) return false;
        if (self.stam.winded) return false;
        return switch (self.state) {
            .idle, .approach, .circle, .wind => true,
            .swing, .recover, .stunlight, .stunheavy, .guardbreak, .dead => false,
        };
    }

    /// COMMITTED AND UNSTOPPABLE (owner's call) — a property of the MOVE, not of the creature, which is
    /// what lets the greatsword also carry a quick combo you CAN interrupt.
    pub fn hyperArmor(self: *const Warrior) bool {
        if (self.state != .wind and self.state != .swing) return false;
        return self.move().hyper;
    }

    fn fdir(self: *const Warrior) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Warrior, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }
    /// The hero's bearing off his facing, in degrees (0 = dead ahead, ±180 = behind him).
    fn bearingTo(self: *const Warrior, hero: rl.Vector3) f32 {
        const d = mathx.dirXZ(self.pos, hero);
        if (mathx.lenXZ(d) < 1e-3) return 0;
        return mathx.degrees(mathx.wrapPi(mathx.headingXZ(d) - self.facing));
    }

    /// Returns this frame's blow ON the hero, if the stroke reached him.
    pub fn update(self: *Warrior, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y); // the last motes keep drifting out
            return null;
        }
        self.heroHit = null;
        self.justDied = false; // one-frame flag: re-set below only if this frame's blade kills it
        self.live = false;
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        // The guard refills only while it is DOWN — holding boards up is not a rest, and a shieldman
        // who recovered behind his own shield could never be broken by pressure.
        self.stam.tick(dt, false, self.guardUp());
        self.blockT += dt;
        for (&self.cds) |*c| c.* = mathx.maxF(0, c.* - dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        self.leash.tick(dt, mathx.distXZ(self.pos, self.home));
        foe.tickParticles(&self.parts, dt, self.pos.y);

        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const sp = spec(self.role);
        const a = self.move();
        const d = foe.sensedDist(&self.leash, mathx.distXZ(self.pos, hero), AGGRO_R);
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;

        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.setCarry(dt);
                if (self.t >= 0.18) self.decide(d);
            },
            .approach => {
                const tgt = if (self.homing) self.home else hero;
                self.faceToward(tgt, dt);
                const f = self.fdir();
                const moved = WALK_SPEED * sp.speed * dt;
                mathx.stepXZ(&self.pos, f, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(f);
                self.setCarry(dt);
                if (self.homing) {
                    if (d <= AGGRO_R) {
                        self.homing = false;
                        self.decide(d);
                    } else if (mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) self.enter(.idle);
                } else if (d <= self.longestTrigger() or d > AGGRO_R) self.decide(d);
            },
            .circle => {
                // A REAL SIDESTEP, so the shared strafe gait drives it: he keeps the hero square on and
                // travels across, which is what "walking a fight down behind a shield" looks like.
                self.faceToward(hero, dt);
                const moved = WALK_SPEED * sp.speed * 0.72 * dt;
                mathx.stepXZ(&self.pos, self.moveDir, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(self.moveDir);
                self.setCarry(dt);
                if (self.t >= CIRCLE_DUR) self.decide(d);
            },
            .wind => {
                // The tell TRACKS, but only a little: it is a commitment, not a turret.
                self.faceToward(hero, dt * 0.5);
                const dur = self.windDur();
                self.setWind(mathx.smoothstep(0, dur * 0.88, self.t));
                // GRIT COMES UP OFF THE TELL, whichever move it is: he plants and loads, and a windup
                // you cannot see is a windup you cannot answer. The heavy ones drag up more of it.
                const load: f32 = if (a.hyper) 1.4 else 0.85;
                if (self.stroke == 0) self.emitGather(dt, mathx.clampF(self.t / dur, 0, 1) * load);
                if (self.t >= dur) self.enter(.swing);
            },
            .swing => {
                foe.faceToward(self.pos, &self.facing, hero, SWING_TURN, dt);
                const k = mathx.clampF(self.t / a.swingDur, 0, 1);
                self.setSwing(mathx.smoothstep(0, a.swingDur, self.t));
                self.flyStroke(k, bounds); // the leap, or the step into a plain blow
                if (self.t >= a.swingDur * a.impactK) self.live = true;
                if (self.t >= a.swingDur) {
                    self.hop = 0;
                    if (self.stroke + 1 < a.strokes) {
                        self.stroke += 1;
                        self.enter(.wind); // straight into the follow-up: no second tell
                    } else {
                        self.cds[self.atk] = a.cd;
                        self.enter(.recover);
                    }
                }
            },
            .recover => {
                self.setRecover(mathx.clampF(self.t / a.recoverDur, 0, 1));
                if (self.t >= a.recoverDur) self.decide(d);
            },
            .stunlight => {
                self.easeNeutral(dt);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enter(.idle);
            },
            .stunheavy => {
                self.easeNeutral(dt);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enter(.idle);
            },
            .guardbreak => {
                self.easeNeutral(dt);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enter(.idle);
            },
            .dead => {
                self.easeNeutral(dt);
                if (self.t >= DEATH_DUR) {
                    self.fade = mathx.smoothstep(DEATH_DUR, DEATH_DUR + DISS_DUR, self.t);
                    self.emitDissolve(dt);
                    if (self.t >= DEATH_DUR + DISS_DUR) self.gone = true;
                }
            },
        }

        // Settled BEFORE the blade, so a hit this frame is judged against the guard he actually held.
        self.covered = self.guardUp() and @abs(self.bearingTo(hero)) <= GUARD_ARC;

        const gaitSpeed: f32 = if (movedDist > 0) WALK_SPEED * sp.speed else 0;
        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, gaitSpeed, moveYaw, self.facing);
        self.footfalls();
        self.pose();
        // THE BLOW IS JUDGED AFTER THE POSE, because the hurt shape IS the posed weapon: what the kit
        // swept this frame, and where its point got to.
        if (self.live) self.tryReach(hero);
        if (self.state == .swing) self.crashIn();
        self.tryHit(blade); // the hero's blade LAST, so a kill flags justDied for this frame's beat
        return self.heroHit;
    }

    /// The wind for the stroke in hand: the FIRST one carries the tell, the rest of a combo do not.
    fn windDur(self: *const Warrior) f32 {
        const a = self.move();
        return if (self.stroke == 0 or a.chainWind <= 0) a.windDur else a.chainWind;
    }
    fn longestTrigger(self: *const Warrior) f32 {
        var r: f32 = 0;
        for (spec(self.role).moves) |a| r = mathx.maxF(r, triggerR(a, self.scale));
        return r;
    }

    /// THE COMMITTED TRAVEL OF A STROKE — the lunge's LITTLE LEAP (owner's call) and the mace's step into
    /// its own blow, which is the same thing without the height. INTEGRATED off a curve rather than added
    /// per frame, so the ground covered is exact however the frame rate wobbles, as the archer's backstep
    /// is. A blow thrown off planted feet reads as a man swatting a fly.
    fn flyStroke(self: *Warrior, k: f32, bounds: f32) void {
        const a = self.move();
        const offEarth = a.lunge > 0 and self.stroke == 0; // …the other kind is a step, and stays down
        const dist = if (offEarth) a.lunge else a.step;
        if (dist <= 0) return;
        const e = 1.0 - (1.0 - k) * (1.0 - k); // fast out of the gather, easing into the landing
        const want = dist * self.scale * e;
        mathx.stepXZ(&self.pos, self.fdir(), want - self.leapDone, bounds);
        self.leapDone = want;
        if (!offEarth) return; // …and the rest of this is the leap's own height and its two plumes
        const wasUp = self.hop > foe.AIRBORNE_LIFT;
        self.hop = a.hop * self.scale * mathx.sinf(k * std.math.pi);
        // THE KICK OFF THE GROUND (owner: bigger fx on that). Thrown BACKWARD, against the travel, and
        // it is the biggest plume either of them makes short of the slam's own crater.
        if (!wasUp and self.hop > foe.AIRBORNE_LIFT) self.kickBurst(-1.0, 26, 4.6);
        // TOUCHDOWN, and it gets its own — a landing you cannot hear or see is a slide.
        if (wasUp and self.hop <= foe.AIRBORNE_LIFT) {
            self.kickBurst(1.0, 30, 4.2);
            self.grit(self.pos, 10);
            sfx.world(.step_hard, self.pos);
        }
    }

    /// A plume off the feet thrown along (or against) the facing: the two ends of a leap, and what
    /// makes it read as a creature PUSHING off the earth rather than sliding along it.
    fn kickBurst(self: *Warrior, along: f32, n: i32, spd: f32) void {
        const f = self.fdir();
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(0.5, 1.0) * spd * self.scale;
            self.emit(
                v3(self.pos.x + self.fxRng.signed() * 0.22, self.pos.y + 0.04, self.pos.z + self.fxRng.signed() * 0.22),
                v3(f.x * along * s + mathx.cosf(a) * s * 0.45, self.fxRng.range(1.1, 3.4), f.z * along * s + mathx.sinf(a) * s * 0.45),
                self.fxRng.range(0.42, 0.80),
                self.fxRng.range(0.08, 0.19) * self.scale,
                0.34 * self.fxRng.range(0.8, 1.4) * self.scale,
                DUST,
                3.6,
            );
        }
    }

    /// The crater at the end of a slam: the blade really does reach the earth, so the earth answers —
    /// AT THE POSED POINT, which is where the steel actually is, and not a fraction of a reach number.
    fn crashIn(self: *Warrior) void {
        if (self.crashed or !self.move().crash) return;
        const tip = self.wpnHere()[1];
        if (tip.y > self.pos.y + CRASH_LOW * self.scale) return; // the point has not got down there yet
        self.crashed = true;
        const at = v3(tip.x, self.pos.y, tip.z);
        self.dustBurst(at, 34, 5.2, 0.40);
        self.grit(at, 14);
        sfx.world(.ogre_slam, at); // the game's one "heavy thing meets earth" voice, at the crater
    }

    fn enter(self: *Warrior, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
        self.crashed = false;
        // …and the kit goes dead WITH the state, or a combo's follow-up lands its predecessor's stroke
        // off one pose: `dealt` is re-armed here, and the hurt test runs after this in the same frame.
        self.live = false;
        if (s != .wind and s != .swing) {
            self.stroke = 0;
            self.leapDone = 0;
            self.hop = 0;
        }
        if (s == .wind and self.stroke == 0) self.leapDone = 0;
        switch (s) {
            // THE TELL HAS A VOICE, and it is the only warning the slam gives you.
            .wind => {
                if (self.stroke > 0) return; // a combo's follow-up does not re-announce itself
                const a = self.move();
                sfx.world(if (a.hyper) .swing_heavy else .swing_light, self.pos);
                if (a.lunge > 0) self.dustBurst(self.pos, 14, 2.4, 0.22); // he digs in to jump
            },
            .swing => if (self.role == .shieldman) sfx.world(.swing_light, self.pos),
            else => {},
        }
    }
    fn enterStun(self: *Warrior, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
        self.crashed = false;
        self.live = false;
        self.stroke = 0;
        self.leapDone = 0;
        self.hop = 0; // caught in the air: he comes straight down
        self.homing = false;
    }
    fn enterDeath(self: *Warrior) void {
        self.enterStun(.dead);
        self.justDied = true;
    }

    fn decide(self: *Warrior, dist: f32) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            return self.enter(.approach);
        }
        var ready: [MAX_MOVES]bool = [_]bool{false} ** MAX_MOVES;
        const n = spec(self.role).moves.len;
        for (0..n) |i| ready[i] = self.cds[i] <= 0;
        switch (classify(self.role, dist, self.scale, ready[0..n])) {
            .strike => {
                self.atk = pick(self.role, dist, self.scale, ready[0..n]) orelse 0;
                self.stroke = 0;
                self.enter(.wind);
            },
            .circle => {
                // Which way he goes round is HIS, and it is seeded — a pair must not orbit as one body.
                const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
                self.moveDir = mathx.scaleV(mathx.perpXZ(self.fdir()), side);
                self.enter(.circle);
            },
            .approach => {
                self.homing = false;
                self.enter(.approach);
            },
            .hold => {
                if (mathx.distXZ(self.pos, self.home) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.enter(.approach);
                } else self.enter(.idle);
            },
        }
    }

    /// THIS FRAME'S segment, off the stamp `pose()` already took — the blow and the crater are judged
    /// after the pose, so recomputing it is both wasted matrix work and a second place for "where the
    /// weapon is" to live.
    fn wpnHere(self: *const Warrior) [2]rl.Vector3 {
        return self.wpnIs orelse self.weaponSeg();
    }

    /// THE WEAPON'S OWN SEGMENT IN WORLD SPACE, straight off the posed bone — the ogre's law
    /// (`clubLowWorld`) carried the whole way: nothing about a blow is guessed from the creature's yaw.
    pub fn weaponSeg(self: *const Warrior) [2]rl.Vector3 {
        const s = KIT_SEG[@intFromEnum(self.role)];
        return .{
            rl.math.vector3Transform(s[0], self.xf[WPN]),
            rl.math.vector3Transform(s[1], self.xf[WPN]),
        };
    }

    /// THE STROKE'S HURT SHAPE IS THE KIT ITSELF: what it swept this frame, judged by `foe.weaponReaches`
    /// against the column the hero stands in, and latched to one blow per stroke. It can only land where
    /// the weapon actually went, which is the whole point — the sector this replaced fired at 2.8 m off a
    /// mace head that never left 0.6 m of his own chest.
    fn tryReach(self: *Warrior, hero: rl.Vector3) void {
        if (self.dealt) return;
        const r = KIT_R[@intFromEnum(self.role)] * self.scale + foe.HERO_REACH;
        if (!foe.weaponReaches(self.wpnWas, self.wpnHere(), hero, r)) return;
        self.heroHit = self.move().hit;
        self.dealt = true;
        self.leash.noteCombat(); // a blow landed is a fight in progress — the tether waits
    }

    pub fn tryHit(self: *Warrior, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const blocked = self.covered;
        var b = blade;
        if (blocked) {
            b.hit = combat.guardChip(blade.hit);
        } else if (self.hyperArmor()) {
            // THE DAMAGE LANDS, THE STAGGER DOES NOT: poise and stance belong to the blow, so taking
            // them off it is the whole of "uninterruptible" and needs no second reaction path.
            b.hit = .{ .dmg = blade.hit.dmg, .elem = blade.hit.elem };
        }
        const s = foe.strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), b) orelse return;
        self.leash.noteCombat();
        if (blade.pierce) {
            self.leash.provoke();
            self.facing = mathx.headingXZ(mathx.scaleV(s.dir, -1));
        }
        if (blocked) return self.caught(blade.hit, s);
        self.hits += 1;
        self.flash = FLASH_DUR;
        const heavyBlow = blade.hit.stance > 0;
        self.shove = mathx.scaleV(s.dir, if (heavyBlow) 1.9 else 1.2);
        // THESE THINGS DO NOT BLEED — a struck skeleton sheds CHIPS, and they are the whole read.
        self.chips(s.contact, s.dir, if (heavyBlow) 20 else 12, if (heavyBlow) 3.4 else 2.4);
        sfx.world(.bone_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                self.chips(s.contact, s.dir, 22, 3.0);
                sfx.world(.bone_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    /// THE BOARDS TOOK IT. Billed on the RAW blow (the arm behind a burning arrow does not know what
    /// the bones resist), and the chip has already gone through `strike` above.
    fn caught(self: *Warrior, raw: combat.Hit, s: foe.Strike) void {
        self.blockT = 0;
        self.stam.spend(combat.guardStamina(raw));
        self.shove = mathx.scaleV(self.fdir(), -0.6); // he gives ground, he does not flinch
        self.sparks(s.contact, s.dir, 14);
        if (s.reaction == .death) {
            // Chipped to death behind his own shield — that is a death, not a block.
            self.hits += 1;
            self.flash = FLASH_DUR;
            sfx.world(.bone_die, self.pos);
            return self.enterDeath();
        }
        if (self.stam.cur > 0) {
            sfx.world(.guard_block, self.pos);
            return;
        }
        self.breakGuard(s.contact);
    }

    /// THE GUARD BREAKS. He goes down on one knee and the boards are smashed off his arm for good —
    /// a heavy stagger the vitals never returned (the chip that emptied him was a plain damage hit),
    /// so the reaction and its poise immunity are armed here.
    fn breakGuard(self: *Warrior, at: rl.Vector3) void {
        sfx.world(.guard_break, self.pos);
        self.flash = FLASH_DUR;
        self.shove = mathx.scaleV(self.fdir(), -BREAK_STEP);
        self.shatter(at);
        self.shieldGone = true;
        self.vit.beginStun(.heavy);
        self.enterStun(.guardbreak);
    }

    // Debug hooks for the --shot harness (force a pose in isolation).
    pub fn debugSwing(self: *Warrior, which: usize) void {
        self.atk = @min(which, spec(self.role).moves.len - 1);
        self.stroke = 0;
        self.enter(.wind);
    }
    pub fn debugBlock(self: *Warrior) void {
        self.enter(.idle);
        self.blockT = 0;
    }
    pub fn debugBreak(self: *Warrior) void {
        self.stam.cur = 0;
        self.stam.winded = true;
        self.breakGuard(self.centerWorld());
    }
    pub fn debugStagger(self: *Warrior, heavy: bool) void {
        self.enterStun(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Warrior) void {
        self.enterDeath();
    }

    fn carryTilt(self: *const Warrior) f32 {
        return if (self.role == .greatsword) GS_CARRY_TILT else MACE_CARRY_TILT;
    }
    fn carrySh(self: *const Warrior) f32 {
        return if (self.role == .greatsword) GS_CARRY_SH else CARRY_SH;
    }
    fn carryAbd(self: *const Warrior) f32 {
        return if (self.role == .greatsword) GS_CARRY_ABD else CARRY_ABD;
    }

    fn setCarryInstant(self: *Warrior) void {
        self.armSh = self.carrySh();
        self.armAbd = self.carryAbd();
        self.wpnTilt = self.carryTilt();
    }

    /// The idle / walking carry — and, for the shieldman, the GUARD, which is simply his carry with the
    /// boards up: one target set, eased, so raising and dropping the shield can never snap.
    fn setCarry(self: *Warrior, dt: f32) void {
        const e = dt * 7.0;
        const breathe = mathx.sinf(self.elapsed * 1.15 + self.seed * 6.28);
        const stalk = self.moving;
        const up: f32 = if (self.guardUp()) 1 else 0;
        // THE RECOIL OF A CAUGHT BLOW GOES INTO THE MAN, NOT THE ARM (hero.zig's own rule): a deep
        // sink and a step back, so a blow he CAUGHT never looks like one that knocked his guard aside.
        const rec = mathx.maxF(0, 1.0 - self.blockT / 0.28);

        if (self.role == .greatsword) {
            // BOTH HANDS ON THE HILT — the off arm has nowhere else to be, so it tracks the weapon arm.
            self.armSh = mathx.approach(self.armSh, GS_CARRY_SH + 3.0 * breathe - 6.0 * stalk, e);
            self.armEl = mathx.approach(self.armEl, CARRY_EL - 10.0, e);
            self.armAbd = mathx.approach(self.armAbd, GS_CARRY_ABD + 2.0 * breathe, e);
            self.offSh = mathx.approach(self.offSh, GS_CARRY_SH - 16.0, e);
            self.offEl = mathx.approach(self.offEl, -58.0, e);
            self.offAbd = mathx.approach(self.offAbd, -34.0, e);
            self.bodyLean = mathx.approach(self.bodyLean, 5.0 + 1.2 * breathe + 5.0 * stalk, e);
            self.twist = mathx.approach(self.twist, -8.0, e);
        } else if (self.shieldGone) {
            // NO BOARDS LEFT: he squares up and holds the mace out in front of him with nothing behind
            // it — the silhouette itself says the fight has changed.
            self.armSh = mathx.approach(self.armSh, CARRY_SH + 14.0 + 3.0 * breathe, e);
            self.armEl = mathx.approach(self.armEl, CARRY_EL - 26.0, e);
            self.armAbd = mathx.approach(self.armAbd, CARRY_ABD + 4.0, e);
            self.offSh = mathx.approach(self.offSh, CARRY_SH - 8.0, e); // the empty arm just hangs
            self.offEl = mathx.approach(self.offEl, CARRY_EL - 6.0, e);
            self.offAbd = mathx.approach(self.offAbd, -CARRY_ABD - 4.0, e);
            self.bodyLean = mathx.approach(self.bodyLean, 6.0 + 1.2 * breathe + 5.0 * stalk, e);
            self.twist = mathx.approach(self.twist, NAKED_TWIST, e);
        } else {
            self.armSh = mathx.approach(self.armSh, lerpF(CARRY_SH + 3.0 * breathe, GUARD_SH, up), e);
            self.armEl = mathx.approach(self.armEl, lerpF(CARRY_EL, GUARD_EL, up), e);
            self.armAbd = mathx.approach(self.armAbd, CARRY_ABD + 2.0 * breathe, e);
            self.offSh = mathx.approach(self.offSh, lerpF(CARRY_SH, GUARD_OFF_SH, up) + 16.0 * rec, e);
            self.offEl = mathx.approach(self.offEl, lerpF(CARRY_EL, GUARD_OFF_EL, up) - 10.0 * rec, e);
            self.offAbd = mathx.approach(self.offAbd, lerpF(-CARRY_ABD, GUARD_OFF_ABD, up), e);
            self.bodyLean = mathx.approach(self.bodyLean, lerpF(4.0 + 1.2 * breathe, GUARD_LEAN, up) + 4.0 * stalk + 11.0 * rec, e);
            self.twist = mathx.approach(self.twist, lerpF(0, GUARD_TWIST, up), e);
        }
        self.armSweep = mathx.approach(self.armSweep, 0, e);
        self.wpnTilt = mathx.approach(self.wpnTilt, self.carryTilt(), e);
        self.headPitch = mathx.approach(self.headPitch, 2.0 + 1.5 * breathe - 6.0 * stalk + 9.0 * rec, e);
        self.legBrace = mathx.approach(self.legBrace, 0.18 * up + 0.55 * rec, e);
    }

    fn easeNeutral(self: *Warrior, dt: f32) void {
        const e = dt * 4.5;
        self.armSh = mathx.approach(self.armSh, self.carrySh(), e);
        self.armEl = mathx.approach(self.armEl, CARRY_EL, e);
        self.armAbd = mathx.approach(self.armAbd, self.carryAbd(), e);
        self.armSweep = mathx.approach(self.armSweep, 0, e);
        self.wpnTilt = mathx.approach(self.wpnTilt, self.carryTilt(), e);
        self.offSh = mathx.approach(self.offSh, CARRY_SH, e);
        self.offEl = mathx.approach(self.offEl, CARRY_EL, e);
        self.offAbd = mathx.approach(self.offAbd, -CARRY_ABD, e);
        self.bodyLean = mathx.approach(self.bodyLean, 4.0, e);
        self.twist = mathx.approach(self.twist, 0, e * 2.0);
        self.headPitch = mathx.approach(self.headPitch, 2.0, e);
        self.legBrace = mathx.approach(self.legBrace, 0, e);
    }

    fn setWind(self: *Warrior, k: f32) void {
        const kArm = k * @sqrt(k); // the loaded arm trails the body and arrives late
        const a = self.move();
        if (a.hyper) return self.setSlamWind(k, kArm);
        if (a.lunge > 0) return self.setLungeWind(k, kArm);
        self.setMaceWind(k, kArm);
    }

    /// THE MACE WINDUP, rebuilt (owner: "swing anim needs a lot of work"). It is three beats, not one
    /// lerp: a GATHER down and back, the arm swinging UP behind the shoulder, then a held shiver at the
    /// top. The gather is the part that was missing — an arm that starts travelling on frame one has no
    /// anticipation in it, and that reads as fast and weightless however long the clock is.
    fn setMaceWind(self: *Warrior, k: f32, kArm: f32) void {
        const gather = mathx.pulse(k, 0, 0.16, 0.30, 0.52); // peaks early, gone by the halfway mark
        const raise = mathx.smoothstep(0.24, 1.0, kArm);
        const shiver = mathx.sinf(self.t * 34.0) * 1.5 * mathx.smoothstep(0.80, 1.0, k);
        self.armSh = lerpF(GUARD_SH, MACE_GATHER_SH, gather) + (MACE_WIND_SH - GUARD_SH) * raise + shiver;
        self.armEl = lerpF(GUARD_EL, MACE_GATHER_EL, gather) + (MACE_WIND_EL - GUARD_EL) * raise;
        self.armAbd = lerpF(CARRY_ABD, MACE_WIND_ABD, raise);
        self.armSweep = lerpF(0, -24.0, raise); // taken round BEHIND his weapon side, not straight up
        self.wpnTilt = lerpF(MACE_CARRY_TILT, MACE_WIND_TILT, raise) + shiver * 0.8;
        // THE BOARDS STAY UP through the whole windup — that is the shieldman's whole shape. With the
        // shield gone the same arm counters instead, because a man swinging one-handed has to.
        if (self.shieldGone) {
            self.offSh = lerpF(CARRY_SH - 8.0, -30.0, raise);
            self.offEl = lerpF(CARRY_EL - 6.0, -46.0, raise);
            self.offAbd = lerpF(-CARRY_ABD - 4.0, -22.0, raise);
        } else {
            self.offSh = lerpF(GUARD_OFF_SH, GUARD_OFF_SH + 6.0, k);
            self.offEl = GUARD_OFF_EL;
            self.offAbd = lerpF(GUARD_OFF_ABD, GUARD_OFF_ABD - 8.0, k);
        }
        // He SINKS on the gather and STANDS UP into the cock — the two together are the load.
        self.bodyLean = lerpF(GUARD_LEAN, GUARD_LEAN + 9.0, gather) + (MACE_WIND_LEAN - GUARD_LEAN) * raise;
        self.twist = lerpF(GUARD_TWIST, MACE_WIND_TWIST, raise);
        self.headPitch = lerpF(2.0, -8.0, raise);
        self.legBrace = lerpF(0.18, 0.30, gather) + 0.28 * raise;
    }

    fn setSlamWind(self: *Warrior, k: f32, kArm: f32) void {
        const shiver = mathx.sinf(self.t * 30.0) * 1.6 * mathx.smoothstep(0.72, 1.0, k);
        self.armSh = lerpF(GS_CARRY_SH, GS_WIND_SH, kArm) + shiver;
        self.armEl = lerpF(CARRY_EL - 10.0, GS_WIND_EL, kArm);
        self.armAbd = lerpF(GS_CARRY_ABD, GS_WIND_ABD, kArm);
        self.armSweep = lerpF(0, -26.0, kArm); // cocked round BEHIND his weapon side
        self.wpnTilt = lerpF(GS_CARRY_TILT, GS_WIND_TILT, kArm) + shiver * 0.7;
        self.offSh = lerpF(GS_CARRY_SH - 16.0, GS_WIND_SH + 26.0, kArm); // the second hand stays on it
        self.offEl = lerpF(-58.0, -80.0, kArm);
        self.offAbd = lerpF(-34.0, -12.0, kArm);
        self.bodyLean = lerpF(5.0, GS_WIND_LEAN, k);
        self.twist = lerpF(-8.0, GS_WIND_TWIST, k);
        self.headPitch = lerpF(2.0, -12.0, k); // the empty sockets come up onto you
        self.legBrace = lerpF(0, 0.62, k);
    }

    /// THE LUNGE'S GATHER: low and COILED, nothing overhead — the read that says this one is quick.
    fn setLungeWind(self: *Warrior, k: f32, kArm: f32) void {
        self.armSh = lerpF(GS_CARRY_SH, LUNGE_WIND_SH, kArm);
        self.armEl = lerpF(CARRY_EL - 10.0, LUNGE_WIND_EL, kArm);
        self.armAbd = lerpF(GS_CARRY_ABD, LUNGE_WIND_ABD, kArm);
        self.armSweep = lerpF(0, -14.0, kArm);
        self.wpnTilt = lerpF(GS_CARRY_TILT, LUNGE_WIND_TILT, kArm); // the point comes DOWN and level, at you
        self.offSh = lerpF(GS_CARRY_SH - 16.0, LUNGE_WIND_SH - 20.0, kArm);
        self.offEl = lerpF(-58.0, -76.0, kArm);
        self.offAbd = lerpF(-34.0, -26.0, kArm);
        self.bodyLean = lerpF(5.0, LUNGE_WIND_LEAN, k);
        self.twist = lerpF(-8.0, LUNGE_WIND_TWIST, k);
        self.headPitch = lerpF(2.0, -4.0, k);
        self.legBrace = lerpF(0, 0.86, k); // he crouches HARD — the leap has to come from somewhere
    }

    fn setSwing(self: *Warrior, k: f32) void {
        const kW = 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k); // the whip: nearly all of it up front
        const a = self.move();
        if (a.hyper) return self.setSlamSwing(kW, k);
        if (a.lunge > 0) return self.setLungeSwing(kW, k);
        self.setMaceSwing(kW, k);
    }

    /// THE MACE STROKE. The head travels a real ARC — up behind the shoulder, over, down and ACROSS —
    /// and the body goes with it: the trunk folds, the shoulder yoke drives through, the wrist whips at
    /// the end, and the whole man overshoots past his own centre line instead of stopping dead.
    fn setMaceSwing(self: *Warrior, kW: f32, k: f32) void {
        const over = mathx.smoothstep(0.72, 1.0, k); // the overswing, which carries him past the target
        self.armSh = lerpF(MACE_WIND_SH, MACE_HIT_SH, kW) + MACE_OVER_SH * over;
        self.armEl = lerpF(MACE_WIND_EL, MACE_HIT_EL, kW);
        self.armAbd = lerpF(MACE_WIND_ABD, MACE_HIT_ABD, kW);
        self.armSweep = lerpF(-24.0, MACE_HIT_SWEEP, kW) + 8.0 * over;
        self.wpnTilt = swingTilt(MACE_WIND_ATT, MACE_END_ATT, k, self.armSh);
        // AND THE SHIELD COMES DOWN WITH THE BLOW — the window you were waiting for.
        self.offSh = lerpF(if (self.shieldGone) -30.0 else GUARD_OFF_SH + 6.0, -16.0, kW);
        self.offEl = lerpF(if (self.shieldGone) -46.0 else GUARD_OFF_EL, -36.0, kW);
        self.offAbd = lerpF(if (self.shieldGone) -22.0 else GUARD_OFF_ABD - 8.0, -34.0, kW);
        self.bodyLean = lerpF(MACE_WIND_LEAN, MACE_HIT_LEAN, k);
        self.twist = lerpF(MACE_WIND_TWIST, MACE_HIT_TWIST, kW);
        self.headPitch = lerpF(-8.0, 22.0, kW);
        self.legBrace = lerpF(0.46, 0.66, k);
    }

    fn setSlamSwing(self: *Warrior, kW: f32, k: f32) void {
        // THE POINT CROSSES CHEST HEIGHT AND THEN GOES ON INTO THE EARTH: the hit pose is the middle of
        // the arc, not its end, and `over` is what carries the steel the rest of the way down.
        self.armSh = lerpF(GS_WIND_SH, GS_HIT_SH, kW);
        self.armEl = lerpF(GS_WIND_EL, GS_HIT_EL, kW);
        self.armAbd = lerpF(GS_WIND_ABD, GS_HIT_ABD, kW);
        self.armSweep = lerpF(-26.0, GS_HIT_SWEEP, kW); // ACROSS him — this is the diagonal
        self.wpnTilt = swingTilt(GS_WIND_ATT, GS_END_ATT, k, self.armSh);
        self.offSh = lerpF(GS_WIND_SH + 26.0, GS_HIT_SH - 18.0, kW);
        self.offEl = lerpF(-80.0, -30.0, kW);
        self.offAbd = lerpF(-12.0, -44.0, kW);
        self.bodyLean = lerpF(GS_WIND_LEAN, GS_HIT_LEAN, k); // the fold at the waist drives it down
        self.twist = lerpF(GS_WIND_TWIST, GS_HIT_TWIST, kW);
        self.headPitch = lerpF(-12.0, 26.0, kW);
        self.legBrace = lerpF(0.62, 0.9, k);
    }

    fn setLungeSwing(self: *Warrior, kW: f32, k: f32) void {
        // Stroke 0 goes OUT (the thrust off the leap); stroke 1 comes back ACROSS (the return cut), so
        // the pair reads as one combo and not as the same swing played twice.
        const back = self.stroke > 0;
        const sweepTo: f32 = if (back) -46.0 else LUNGE_HIT_SWEEP;
        const twistTo: f32 = if (back) -20.0 else LUNGE_HIT_TWIST;
        self.armSh = lerpF(LUNGE_WIND_SH, LUNGE_HIT_SH, kW);
        self.armEl = lerpF(LUNGE_WIND_EL, LUNGE_HIT_EL, kW);
        self.armAbd = lerpF(LUNGE_WIND_ABD, LUNGE_HIT_ABD, kW);
        self.armSweep = lerpF(-14.0, sweepTo, kW);
        self.wpnTilt = lerpF(LUNGE_WIND_TILT, if (back) 34.0 else LUNGE_HIT_TILT, kW);
        self.offSh = lerpF(LUNGE_WIND_SH - 20.0, LUNGE_HIT_SH - 14.0, kW);
        self.offEl = lerpF(-76.0, -22.0, kW);
        self.offAbd = lerpF(-26.0, -30.0, kW);
        self.bodyLean = lerpF(LUNGE_WIND_LEAN, LUNGE_HIT_LEAN, k);
        self.twist = lerpF(LUNGE_WIND_TWIST, twistTo, kW);
        self.headPitch = lerpF(-4.0, 14.0, kW);
        self.legBrace = lerpF(0.86, 0.34, k); // the crouch RELEASES: that release is the leap
    }

    fn setRecover(self: *Warrior, u: f32) void {
        // How much of the swing is still in him: all of it at the start, none of it by the end.
        const over = 1.0 - mathx.smoothstep(0.30, 1.0, u);
        const heave = mathx.sinf(self.elapsed * 8.0) * 2.4 * over;
        const a = self.move();
        if (a.hyper) {
            // SPENT: the point is in the dirt off his off side and he has to haul it back up.
            self.armSh = lerpF(GS_CARRY_SH, GS_HIT_SH, over) + heave * 0.5;
            self.armEl = lerpF(CARRY_EL - 10.0, GS_HIT_EL, over);
            self.armAbd = lerpF(GS_CARRY_ABD, GS_HIT_ABD, over);
            self.armSweep = lerpF(0, GS_HIT_SWEEP, over);
            self.wpnTilt = lerpF(GS_CARRY_TILT, GS_END_TILT, over);
            self.offSh = lerpF(GS_CARRY_SH - 16.0, GS_HIT_SH - 18.0, over);
            self.offEl = lerpF(-58.0, -30.0, over);
            self.offAbd = lerpF(-34.0, -44.0, over);
            self.bodyLean = lerpF(5.0, GS_HIT_LEAN + 6.0, over) + heave;
            self.twist = lerpF(-8.0, GS_HIT_TWIST, over);
            self.headPitch = lerpF(2.0, 30.0, over);
            self.legBrace = lerpF(0, 0.85, over);
            return;
        }
        if (a.lunge > 0) {
            // Out over the lead foot with the blade across him, gathering himself back up. Shorter than
            // the slam's collapse on purpose — this is the move you punish, but only just.
            self.armSh = lerpF(GS_CARRY_SH, -30.0, over);
            self.armEl = lerpF(CARRY_EL - 10.0, -26.0, over);
            self.armAbd = lerpF(GS_CARRY_ABD, -8.0, over);
            self.armSweep = lerpF(0, -40.0, over);
            self.wpnTilt = lerpF(GS_CARRY_TILT, 92.0, over); // the blade left lying across his front
            self.offSh = lerpF(GS_CARRY_SH - 16.0, -40.0, over);
            self.offEl = lerpF(-58.0, -24.0, over);
            self.offAbd = lerpF(-34.0, -28.0, over);
            self.bodyLean = lerpF(5.0, LUNGE_HIT_LEAN + 4.0, over) + heave * 0.6;
            self.twist = lerpF(-8.0, -18.0, over);
            self.headPitch = lerpF(2.0, 18.0, over);
            self.legBrace = lerpF(0, 0.55, over);
            return;
        }
        const rest: f32 = if (self.shieldGone) CARRY_SH - 8.0 else CARRY_SH;
        self.armSh = lerpF(CARRY_SH, MACE_HIT_SH + 6.0, over);
        self.armEl = lerpF(CARRY_EL, MACE_HIT_EL, over);
        self.armAbd = lerpF(CARRY_ABD, MACE_HIT_ABD, over);
        self.armSweep = lerpF(0, MACE_HIT_SWEEP + 8.0, over);
        self.wpnTilt = lerpF(MACE_CARRY_TILT, MACE_END_TILT, over);
        self.offSh = lerpF(rest, -16.0, over);
        self.offEl = lerpF(CARRY_EL, -36.0, over);
        self.offAbd = lerpF(-CARRY_ABD, -34.0, over);
        self.bodyLean = lerpF(4.0, MACE_HIT_LEAN, over) + heave * 0.5;
        self.twist = lerpF(0, MACE_HIT_TWIST, over);
        self.headPitch = lerpF(2.0, 22.0, over);
        self.legBrace = lerpF(0, 0.55, over);
    }

    fn stunAmount(self: *const Warrior) f32 {
        return switch (self.state) {
            .stunlight => mathx.sinf(mathx.clampF(self.t / combat.FOE_LIGHT_STUN_DUR, 0, 1) * std.math.pi),
            .stunheavy, .guardbreak => mathx.pulse(mathx.clampF(self.t / combat.FOE_HEAVY_STUN_DUR, 0, 1), 0, 0.13, 0.72, 1.0),
            else => 0,
        };
    }

    /// HOW FAR DOWN ON HIS KNEE HE IS, 0..1 — fast down, held, and slow back up, because the getting up
    /// is the punish window and the going down is a collapse.
    fn kneelAmount(self: *const Warrior) f32 {
        if (self.state != .guardbreak) return 0;
        const d = combat.FOE_HEAVY_STUN_DUR;
        return mathx.smoothstep(0, KNEEL_IN, self.t) * (1.0 - mathx.smoothstep(d - KNEEL_OUT, d, self.t));
    }

    pub fn pose(self: *Warrior) void {
        const fs = self.scale * (1.0 - 0.7 * self.fade);
        const sink = -0.55 * self.scale * self.fade; // the corpse sinks as it dissipates
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.45, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();
        const kn = self.kneelAmount();

        const m = self.moving * (1.0 - dk) * (1.0 - kn);
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const latW = @abs(self.latB) * m;
        const sway = heromod.strafeSway(latW, 0) * mathx.sinf(twoPi * self.phase) * m;
        const prot = A_PROT * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB) +
            heromod.strafeProt(self.phase, self.latB, m);
        const dip = heromod.STRAFE_DIP * latW;
        // THE LEGS TAKE THE BRACE IN THE KNEES, they do not squat (owner's law) — this is only the
        // small pelvis drop that a real knee bend costs. The KNEEL's drop is a different order of thing.
        const braceSink = 0.030 * H * self.legBrace + KNEEL_SINK * H * kn;

        var wx: [N]rl.Matrix = undefined;
        const collapse = mathx.lerpF(hipY, 0.22 * H, dk);
        // …AND THE WAIST IS WHERE HE FOLDS: the pelvis takes PELVIS_SHARE of the lean and no more.
        const pitchRoot = (self.bodyLean * PELVIS_SHARE) + 20.0 * dk - 24.0 * stun * (1.0 - kn) + 4.0 * kn;
        const pelvY = if (dead) collapse else hipY + bob - dip - braceSink;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(9.0 * dk), rx(pitchRoot), ry(prot + self.twist * 0.22)),
            mul(tr(sway * fs, pelvY * fs + sink + self.hop, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));

        // hero.legChain owns the legs whenever nothing else has taken them: the death crumple, the
        // KNEEL and the LEAP each pose them outright, and they are mutually exclusive by construction.
        const legsTaken = dead or kn > 0.001 or self.leaping();
        if (!legsTaken) {
            heromod.legChain(&wx, &self.rest, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        }
        self.poseUpper(&wx, dk, stun, kn, dead, prot);
        self.xf = wx;
        // …and the kit's own sweep is stamped LAST, off the pose that was just built.
        const seg = self.weaponSeg();
        self.wpnWas = self.wpnIs orelse seg;
        self.wpnIs = seg;
    }

    fn leaping(self: *const Warrior) bool {
        return self.state == .swing and self.stroke == 0 and self.move().lunge > 0;
    }

    fn poseUpper(self: *Warrior, wx: *[N]rl.Matrix, dk: f32, stun: f32, kn: f32, dead: bool, prot: f32) void {
        const rest = self.rest;
        const wonk = (self.seed - 0.5) * 6.0; // each one stands its own crooked way (cosmetic only)
        const brk = if (self.state == .guardbreak) stun else 0; // the break's own, bigger reaction
        // The trunk carries the REST of the lean the pelvis did not take, split up the spine. ONCE HE IS
        // DOWN THE KNEEL OWNS THE TRUNK: the generic stagger arches BACK and the kneel folds FORWARD, so
        // left to fight each other they cancel into a man doing nothing in particular.
        const spineX = self.bodyLean * (1.0 - PELVIS_SHARE) + 22.0 * dk - 22.0 * stun * (1.0 - kn) + KNEEL_FOLD * kn;

        setLocal(wx, SPINE, rest, mul3(rx(spineX * 0.45), ry(-0.35 * prot + self.twist * 0.4), rz(wonk * 0.5)));
        setLocal(wx, CHEST, rest, mul3(rx(spineX * 0.55), ry(-0.5 * prot + self.twist * 0.6), rz(-wonk * 0.3)));
        setLocal(wx, NECK, rest, rx(self.headPitch * 0.4 + 12.0 * dk - 10.0 * stun * (1.0 - kn) + KNEEL_HEAD * kn * 0.4));
        setLocal(wx, SKULL, rest, mul3(
            rx(self.headPitch * 0.6 + 20.0 * dk - (32.0 * stun + 24.0 * brk) * (1.0 - kn) + KNEEL_HEAD * kn * 0.6),
            ry(self.headYaw - self.twist * 0.3),
            rz(wonk + 14.0 * dk),
        ));

        if (dead) {
            setLocal(wx, HIPL, rest, mul(rx(-58.0 * dk), rz(-3.0)));
            setLocal(wx, KNEEL, rest, rx(8.0 + 98.0 * dk));
            setLocal(wx, ANKL, rest, ry(7.0));
            setLocal(wx, HIPR, rest, mul(rx(-50.0 * dk), rz(3.0)));
            setLocal(wx, KNEER, rest, rx(8.0 + 90.0 * dk));
            setLocal(wx, ANKR, rest, ry(-7.0));
        } else if (kn > 0.001) {
            // DOWN ON ONE KNEE: the LEAD leg braced out in front with the foot planted, the TRAIL leg
            // folded right under him so the shin lies on the ground. Symmetric legs would be a squat.
            setLocal(wx, HIPL, rest, mul(rx(-KNEEL_LEAD_HIP * kn), rz(-4.0)));
            setLocal(wx, KNEEL, rest, rx(8.0 + KNEEL_LEAD_KNEE * kn));
            setLocal(wx, ANKL, rest, rx(-16.0 * kn));
            setLocal(wx, HIPR, rest, mul(rx(KNEEL_TRAIL_HIP * kn), rz(5.0)));
            setLocal(wx, KNEER, rest, rx(8.0 + KNEEL_TRAIL_KNEE * kn));
            setLocal(wx, ANKR, rest, rx(26.0 * kn)); // the toe turns under, taking his weight
        } else if (self.leaping()) {
            // A LEAP IS ONE KNEE UP (kobold.zig's law): lead knee to the chest, trail leg left extended
            // behind, and both come forward to catch him. Both tucked alike is a hop, not a lunge.
            const u = mathx.clampF(self.t / self.move().swingDur, 0, 1);
            const air = mathx.sinf(u * std.math.pi);
            const land = mathx.smoothstep(0.62, 1.0, u);
            setLocal(wx, HIPL, rest, mul(rx(-(LEAP_LEAD_HIP * air - 30.0 * land)), rz(-4.0)));
            setLocal(wx, KNEEL, rest, rx(8.0 + LEAP_LEAD_KNEE * air - 40.0 * land));
            setLocal(wx, ANKL, rest, rx(-LEAP_TOE * air));
            setLocal(wx, HIPR, rest, mul(rx(LEAP_TRAIL_HIP * air - 26.0 * land), rz(5.0)));
            setLocal(wx, KNEER, rest, rx(8.0 + LEAP_TRAIL_KNEE * air + 34.0 * land));
            setLocal(wx, ANKR, rest, rx(-LEAP_TOE * 0.7 * air));
        }

        // REACTIONS ARE HUGE: both arms are flung on a stagger, and a GUARD BREAK throws the shield
        // arm wide open as the boards are smashed off it — the read that says the window is now.
        const armStun = -66.0 * stun;
        setLocal(wx, SHR, rest, mul3(
            rx(-(self.armSh) - 26.0 * dk + armStun + 30.0 * kn),
            rz(-self.armAbd + wonk * 0.4),
            ry(-self.armSweep),
        ));
        setLocal(wx, ELR, rest, rx(self.armEl - 24.0 * kn));
        setLocal(wx, WRR, rest, rz(-5.0));
        setLocal(wx, WPN, rest, wpnFit(self.wpnTilt));

        setLocal(wx, SHL, rest, mul3(
            rx(-(self.offSh) - 22.0 * dk + armStun - BREAK_ARM * brk),
            rz(-self.offAbd - wonk * 0.4 - 38.0 * brk),
            ry(self.armSweep * 0.35),
        ));
        setLocal(wx, ELL, rest, rx(self.offEl + 44.0 * brk));
        setLocal(wx, WRL, rest, rz(6.0));
    }

    // ── FX ────────────────────────────────────────────────────────────────────────────────────────
    // A skeleton does not bleed, so every burst here is DUST, BONE or IRON. The shared pool, shape and
    // integrator are foe.zig's; only the bursts are this creature's.

    fn emit(self: *Warrior, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.parts, &self.head, p, vel, life, r0, r1, col, grav);
    }

    /// A radial fan of dust off the ground at `c`.
    fn dustBurst(self: *Warrior, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(0.45, 1.0) * spd * self.scale;
            const vel = v3(mathx.cosf(a) * s, self.fxRng.range(0.7, 2.6), mathx.sinf(a) * s);
            self.emit(v3(c.x, self.pos.y + 0.05, c.z), vel, self.fxRng.range(0.38, 0.68), self.fxRng.range(0.07, 0.15) * self.scale, big * self.fxRng.range(0.8, 1.3) * self.scale, DUST, 4.2);
        }
    }
    /// …and the heavier stuff a crater throws, which arcs instead of drifting.
    fn grit(self: *Warrior, c: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(1.2, 3.4) * self.scale;
            self.emit(
                v3(c.x, self.pos.y + 0.08, c.z),
                v3(mathx.cosf(a) * s, self.fxRng.range(2.4, 5.2), mathx.sinf(a) * s),
                self.fxRng.range(0.45, 0.85),
                self.fxRng.range(0.025, 0.055) * self.scale,
                0.012,
                CHIP,
                9.0,
            );
        }
    }
    /// BONE CHIPS off a landed blow, thrown along the blade's own sweep.
    fn chips(self: *Warrior, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.4, 1.0) * spd;
            self.emit(
                at,
                v3(dir.x * sp + mathx.cosf(a) * self.fxRng.range(0.2, 1.1), self.fxRng.range(0.9, 3.0), dir.z * sp + mathx.sinf(a) * self.fxRng.range(0.2, 1.1)),
                self.fxRng.range(0.32, 0.60),
                self.fxRng.range(0.022, 0.050) * self.scale,
                0.008,
                CHIP,
                8.0,
            );
        }
    }
    /// IRON ON IRON: the rim of the boards taking a blade. Short, hot and gone.
    fn sparks(self: *Warrior, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(1.4, 4.2);
            self.emit(
                at,
                v3(-dir.x * sp * 0.5 + mathx.cosf(a) * sp * 0.6, self.fxRng.range(1.2, 3.6), -dir.z * sp * 0.5 + mathx.sinf(a) * sp * 0.6),
                self.fxRng.range(0.16, 0.34),
                self.fxRng.range(0.014, 0.030),
                0.002,
                SPARK,
                6.0,
            );
        }
    }
    /// THE BOARDS GO. The biggest burst this creature has, and it happens exactly once in its life.
    fn shatter(self: *Warrior, at: rl.Vector3) void {
        var i: i32 = 0;
        while (i < 26) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(1.6, 5.0) * self.scale;
            const wood = self.fxRng.float() < 0.72;
            self.emit(
                v3(at.x + self.fxRng.signed() * 0.18, at.y + self.fxRng.signed() * 0.26, at.z + self.fxRng.signed() * 0.18),
                v3(mathx.cosf(a) * sp, self.fxRng.range(1.4, 4.6), mathx.sinf(a) * sp),
                self.fxRng.range(0.5, 0.95),
                self.fxRng.range(0.03, 0.075) * self.scale,
                0.010,
                if (wood) SPLINTER else CHIP,
                8.5,
            );
        }
        self.sparks(at, self.fdir(), 12);
    }
    /// The gather before a leap: grit dragged up as he digs his heels in.
    fn emitGather(self: *Warrior, dt: f32, k: f32) void {
        self.fxAccum += (5.0 + 26.0 * k) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.2, 0.7) * self.scale;
            self.emit(
                v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.04, self.pos.z + mathx.sinf(a) * rr),
                v3(self.fxRng.signed() * 0.5, self.fxRng.range(0.3, 1.3), self.fxRng.signed() * 0.5),
                self.fxRng.range(0.28, 0.5),
                self.fxRng.range(0.03, 0.07) * self.scale,
                0.012,
                DUST,
                3.0,
            );
        }
    }
    /// A PUFF UNDER EACH FOOT. Cheap, and it is most of what makes a walk feel like it has weight.
    fn footfalls(self: *Warrior) void {
        if (self.moving < 0.35 or self.staggered()) {
            self.prevPhase = self.phase;
            return;
        }
        const crossed = @floor(self.phase * 2.0) != @floor(self.prevPhase * 2.0);
        self.prevPhase = self.phase;
        if (!crossed) return;
        const side = mathx.perpXZ(self.fdir());
        const s: f32 = if (@mod(@floor(self.phase * 2.0), 2.0) == 0) 1.0 else -1.0;
        const at = v3(self.pos.x + side.x * 0.16 * s * self.scale, self.pos.y, self.pos.z + side.z * 0.16 * s * self.scale);
        self.dustBurst(at, 3, 0.9, 0.10);
    }
    /// Death dissipation: grace-gold motes rising off the sinking corpse (ER-consistent).
    fn emitDissolve(self: *Warrior, dt: f32) void {
        self.fxAccum += 54.0 * (1.0 - 0.6 * self.fade) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.1, 0.85) * self.scale * (1.0 - 0.6 * self.fade);
            const p = v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + self.fxRng.range(0.05, 0.7) * self.scale, self.pos.z + mathx.sinf(a) * rr);
            if (self.fxRng.float() < 0.78) {
                self.emit(p, v3(self.fxRng.signed() * 0.3, self.fxRng.range(0.5, 1.5), self.fxRng.signed() * 0.3), self.fxRng.range(0.6, 1.1), self.fxRng.range(0.035, 0.08) * self.scale, 0.004, MOTE, -0.7);
            } else {
                self.emit(p, v3(self.fxRng.signed() * 0.4, self.fxRng.range(0.1, 0.5), self.fxRng.signed() * 0.4), self.fxRng.range(0.3, 0.65), self.fxRng.range(0.05, 0.11) * self.scale, 0.010, CHIP, 3.0);
            }
        }
    }
    pub fn drawFx(self: *const Warrior) void {
        foe.drawParticles(&self.parts);
    }

    pub fn draw(self: *const Warrior, model: *const Model) void {
        model.draw(self);
    }
};

// WHERE they stand is the MAP's business (`foe: shieldman …` / `foe: greatsword …` records).
pub const CAP = SPEC.len * wf.MAX_PER_KIND;

/// THE MUSTER — both roles in one array, for the warband's reason: they are one creature with two kits,
/// so the body, the gait, the bones, the death and the reactions are shared and only the kit and the
/// state machine differ.
pub const Muster = struct {
    model: Model,
    band: [CAP]Warrior = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Muster {
        return .{ .model = Model.init(shader) };
    }
    /// The posted warriors — never iterate the whole array, the tail is `undefined`.
    pub fn live(self: *Muster) []Warrior {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Muster) []const Warrior {
        return self.band[0..self.n];
    }

    /// RE-HOME from the map: every warrior spawn of either role, in FILE ORDER, built fresh.
    pub fn reset(self: *Muster, m: *const wf.Map) void {
        self.n = 0;
        for (m.foes[0..m.nfoes]) |h| {
            const role = roleOf(h.kind) orelse continue;
            if (self.n >= CAP) continue;
            // ON THE GROUND the map's own height field decides — a spawn table stores x/z only.
            self.band[self.n] = Warrior.spawnAs(role, v3(h.x, m.heightAt(h.x, h.z), h.z), mathx.radians(h.yaw), h.scale, h.seed);
            self.n += 1;
        }
    }

    pub fn setShader(self: *Muster, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Muster, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Muster) void {
        for (self.liveConst()) |*w| w.drawFx();
    }

    // The shared Group roll-ups (foe.zig).
    /// ONE OF THE HERO'S SHAFTS through the group — the first member it reaches takes it.
    pub fn pierce(self: *Muster, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Muster) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn totalHits(self: *const Muster) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Muster) u32 {
        return foe.aliveCount(self.liveConst());
    }
    /// RUNES paid out this frame — per ROLE, because a greatsword is worth half again a shieldman.
    pub fn runesDropped(self: *const Muster) u32 {
        var n: u32 = 0;
        for (self.liveConst()) |*w| {
            if (w.justDied) n += w.runeValue();
        }
        return n;
    }

    pub fn update(self: *Muster, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var blow: ?foe.Blow = null;
        for (self.live()) |*w| {
            if (w.update(dt, hero, bounds, blade)) |h| foe.worseBlow(&blow, h, w.pos);
        }
        return blow;
    }
};

// ─────────────────────────────────────────────────────────────────────────────────────────────────
// THE KIT. Bones come from `archer.boneMeshes`; everything below is what these two carry.

/// THE MACE — a short haft in the fist, a flanged iron head over it. Authored in the RIGHT-WRIST frame
/// about the fist, exactly as the archer's bow is, so the two armaments hang off one anchor.
fn maceMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(5507);
    const fy = FIST_Y;
    const fz = FIST_Z;
    const headY = fy + MACE_HEAD;

    b.setMat(.wood);
    b.addCylinder(v3(0, fy - 0.11 * H, fz), v3(0, headY + 0.008 * H, fz), 0.0135 * H, 0.0125 * H, 7, HAFT);
    b.setMat(.leather);
    b.addCylinder(v3(0, fy + 0.062 * H, fz), v3(0, fy - 0.070 * H, fz), 0.0165 * H, 0.0165 * H, 7, WRAP); // the grip
    b.setMat(.steel);
    b.addCapsule(v3(0, fy - 0.118 * H, fz), v3(0, fy - 0.098 * H, fz), 0.020 * H, 0.018 * H, 8, IRON); // butt cap
    b.addCylinder(v3(0, fy + 0.070 * H, fz), v3(0, fy + 0.082 * H, fz), 0.019 * H, 0.019 * H, 7, IRON_DK); // langet collar

    // THE HEAD: a squat drum with FIVE flanges standing off it, every one its own length and lean.
    b.addCapsule(v3(0, headY - 0.036 * H, fz), v3(0, headY + 0.034 * H, fz), 0.028 * H, 0.026 * H, 9, IRON);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = @as(f32, @floatFromInt(i)) * (std.math.tau / 5.0) + rng.range(-0.12, 0.12);
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        // RELIEF IS SUBTLE only for weathering — a flange is the WEAPON, and it stands proud on purpose;
        // its ROOT is still sunk most of the way into the drum so it is not a plate glued to a barrel.
        const out = MACE_FLANGE * rng.range(0.88, 1.10);
        const half = 0.030 * H * rng.range(0.85, 1.12);
        const cx = ca * out * 0.62;
        const cz = sa * out * 0.62;
        b.addBox(
            v3(cx, headY + rng.range(-0.006, 0.006) * H, fz + cz),
            v3(ca * out, 0, sa * out), // out along the radius
            v3(0, half, 0), // up
            v3(-sa * 0.0055 * H, 0, ca * 0.0055 * H), // and thin across it
            if (rng.float() < 0.3) RUST else IRON_LT,
        );
    }
    b.addCapsule(v3(0, headY + 0.034 * H, fz), v3(0, FIST_Y + MACE_HEAD + MACE_CAP, fz), 0.014 * H, 0.006 * H, 7, IRON_LT); // the cap spike
    return b.toMesh();
}

/// THE GREATSWORD — a long two-handed blade off the same fist anchor. Grip below the hand, crossguard
/// just above it, and better than a metre of steel over that: the REACH is the whole weapon.
fn greatswordMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(6611);
    const fy = FIST_Y;
    const fz = FIST_Z;
    const guardY = fy + GS_GUARD;
    // ABOVE THE GUARD, like every other feature of this blade. Measured off the FIST instead — which is
    // how it went in — it landed BELOW the last blade segment's own top, so the point was drawn pointing
    // down INSIDE the steel, the blade ended blunt, and the hurt segment stopped 0.12 m short of what you
    // could see. A weapon's reach cannot be judged against a mesh that disagrees with itself.
    const tipY = guardY + GS_BLADE;

    b.setMat(.wood);
    b.addCylinder(v3(0, fy - 0.155 * H, fz), v3(0, guardY, fz), 0.0125 * H, 0.0115 * H, 7, HAFT);
    b.setMat(.leather);
    b.addCylinder(v3(0, fy + 0.080 * H, fz), v3(0, fy - 0.145 * H, fz), 0.0155 * H, 0.0155 * H, 7, WRAP); // the long grip
    // Two binding rings, unevenly spaced — a wrap is bound where a hand wants it, not on a grid.
    for ([_]f32{ -0.104, 0.020 }) |gy| {
        b.addCylinder(v3(0, fy + gy * H, fz), v3(0, fy + (gy + 0.011) * H, fz), 0.0172 * H, 0.0172 * H, 7, HAFT_LT);
    }
    b.setMat(.steel);
    b.addCapsule(v3(0, fy - 0.170 * H, fz), v3(0, fy - 0.150 * H, fz), 0.0215 * H, 0.019 * H, 9, IRON); // the pommel

    // THE CROSSGUARD: a long bar across, its two arms deliberately unequal.
    for ([_]f32{ 1, -1 }) |side| {
        const armLen = 0.088 * H * (if (side > 0) @as(f32, 1.0) else 0.90);
        b.addBox(
            v3(side * armLen * 0.5, guardY, fz),
            v3(side * armLen, 0, 0),
            v3(0, 0.0115 * H, 0),
            v3(0, 0, 0.0135 * H),
            IRON,
        );
        b.addCapsule(
            v3(side * armLen, guardY, fz),
            v3(side * (armLen + 0.012 * H), guardY - 0.004 * H, fz),
            0.0105 * H,
            0.0065 * H,
            7,
            IRON_LT,
        ); // the quillon tips turn down and blunt off
    }
    b.addCylinder(v3(0, guardY, fz), v3(0, guardY + 0.030 * H, fz), 0.0165 * H, 0.0135 * H, 7, IRON_DK); // ricasso collar

    // THE BLADE: three tapering segments, so the profile narrows all the way to the point instead of
    // being a plank with a wedge stuck on the end.
    const seg = [_]f32{ 0.030, 0.300, 0.560, 0.700 }; // heights above the guard, in H
    const halfW = [_]f32{ GS_HALF_W / H, 0.045, 0.036, 0.020 };
    const halfT = [_]f32{ 0.0068, 0.0060, 0.0048, 0.0032 };
    for (0..3) |s| {
        const y0 = guardY + seg[s] * H;
        const y1 = guardY + seg[s + 1] * H;
        const w0 = halfW[s] * H;
        const w1 = halfW[s + 1] * H;
        const t0 = halfT[s] * H;
        // addBox is a parallelepiped, so a TAPER is two of them meeting at the mid-width.
        b.addBox(
            v3(0, (y0 + y1) * 0.5, fz),
            v3((w0 + w1) * 0.5, 0, 0),
            v3(0, (y1 - y0) * 0.5, 0),
            v3(0, 0, t0),
            if (s == 1) STEEL_DK else STEEL,
        );
    }
    b.addCapsule(v3(0, guardY + seg[3] * H, fz), v3(0, tipY, fz), 0.014 * H, 0.003 * H, 7, STEEL); // the point
    // THE FULLER IS SUNK, not stood off: only its edge breaks the flat (RELIEF IS SUBTLE).
    b.addBox(
        v3(0, guardY + 0.30 * H, fz),
        v3(0.013 * H, 0, 0),
        v3(0, 0.27 * H, 0),
        v3(0, 0, 0.0075 * H),
        STEEL_DK,
    );
    // …and the edge it has kept, a hair proud of each flat.
    for ([_]f32{ 1, -1 }) |side| {
        b.addCylinder(
            v3(side * 0.045 * H, guardY + 0.045 * H, fz),
            v3(side * 0.019 * H, guardY + 0.690 * H, fz),
            0.0032 * H,
            0.0022 * H,
            4,
            STEEL,
        );
    }
    // NICKS: three bites out of the edge, at their own heights and depths. It is a grave-goods blade.
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const y = guardY + rng.range(0.10, 0.62) * H;
        const side: f32 = if (rng.float() < 0.5) 1 else -1;
        const w = rng.range(0.010, 0.019) * H;
        b.addBox(
            v3(side * (0.040 * H), y, fz),
            v3(side * w, 0, 0),
            v3(0, rng.range(0.006, 0.013) * H, 0),
            v3(0, 0, 0.0080 * H),
            RUST,
        );
    }
    return b.toMesh();
}

// THE KITE SHIELD. Authored FACE-ON — its face along +Z, the grip at the origin, the top at +SH_TOP
// and the point hanging at −SH_BOT — and turned onto the forearm by `shieldFit`.
const SH_TOP = 0.215 * H;
const SH_BOT = 0.415 * H;
const SH_HALF = 0.135 * H; // half-width at the shoulders
const SH_THICK = 0.017 * H;
const SH_ROWS = 11;
/// How far off the fist the boards ride. A kite shield is STRAPPED to the forearm, not centre-gripped
/// like the hero's round one, so this is small — the arm is behind the boards, not behind a boss.
const SH_STANDOFF = 0.085 * H;

/// The kite profile: half-width at `t`, 0 at the top edge and 1 at the point.
fn kiteHalf(t: f32) f32 {
    if (t <= 0.30) {
        // The rounded shoulders — an ellipse quarter, so the top is a dome and not a lid.
        const u = (0.30 - t) / 0.30;
        return SH_HALF * @sqrt(mathx.maxF(1.0 - u * u * 0.86, 0.02));
    }
    const u = (t - 0.30) / 0.70;
    return SH_HALF * mathx.maxF(1.0 - std.math.pow(f32, u, 1.35), 0.012);
}

fn shieldMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(7703);
    // THE BOARDS: horizontal planks down the kite, each its own width and tone — the four obvious
    // failures here are one slab, one colour, equal planks, and a rim that follows a perfect outline.
    b.setMat(.wood);
    var i: usize = 0;
    while (i < SH_ROWS) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / SH_ROWS;
        const t1 = @as(f32, @floatFromInt(i + 1)) / SH_ROWS;
        const y0 = mathx.lerpF(SH_TOP, -SH_BOT, t0);
        const y1 = mathx.lerpF(SH_TOP, -SH_BOT, t1);
        const w = mathx.maxF(kiteHalf((t0 + t1) * 0.5), 0.004 * H) * rng.range(0.97, 1.02);
        // A DISH, not a flat door: the middle of the boards stands proud of the rim toward whatever is
        // coming, and it is a couple of centimetres — the whole shield is only a hand thick.
        const dish = 0.020 * H * (1.0 - std.math.pow(f32, @abs((t0 + t1) - 0.62), 1.6));
        const col = switch (@mod(i, 3)) {
            0 => BOARD,
            1 => BOARD_LT,
            else => BOARD_DK,
        };
        b.addBox(
            v3(0, (y0 + y1) * 0.5, dish),
            v3(w, 0, 0),
            v3(0, (y0 - y1) * 0.5 + 0.002 * H, 0), // planks overlap a hair, or the seams leak daylight
            v3(0, 0, SH_THICK * 0.5),
            col,
        );
    }
    // THE IRON RIM, bound round the outline — short straps, each one its own length, and a gap or two.
    b.setMat(.steel);
    i = 0;
    while (i < SH_ROWS) : (i += 1) {
        if (rng.float() < 0.12) continue; // a strap lost to the centuries
        const t0 = @as(f32, @floatFromInt(i)) / SH_ROWS;
        const t1 = @as(f32, @floatFromInt(i + 1)) / SH_ROWS;
        const y0 = mathx.lerpF(SH_TOP, -SH_BOT, t0);
        const y1 = mathx.lerpF(SH_TOP, -SH_BOT, t1);
        const w0 = kiteHalf(t0);
        const w1 = kiteHalf(t1);
        for ([_]f32{ 1, -1 }) |side| {
            b.addCapsule(
                v3(side * w0, y0, 0.004 * H),
                v3(side * w1, y1, 0.004 * H),
                0.0072 * H * rng.range(0.9, 1.1),
                0.0068 * H,
                6,
                if (rng.float() < 0.35) RUST else IRON,
            );
        }
    }
    b.addCapsule(v3(-SH_HALF * 0.94, SH_TOP - 0.004 * H, 0.004 * H), v3(SH_HALF * 0.94, SH_TOP - 0.004 * H, 0.004 * H), 0.0078 * H, 0.0072 * H, 7, IRON); // the top binding
    // THE BOSS, and a cross-brace behind nothing — the two bits of iron a shield actually needs.
    b.addCapsule(v3(0, 0.012 * H, 0.020 * H), v3(0, 0.012 * H, 0.034 * H), 0.030 * H, 0.020 * H, 9, IRON_LT);
    b.addBox(v3(0, 0.012 * H, 0.026 * H), v3(SH_HALF * 0.82, 0, 0), v3(0, 0.0105 * H, 0), v3(0, 0, 0.005 * H), IRON_DK);
    // WHAT IS LEFT OF A DEVICE — a bar and a chevron, most of it worn off the boards.
    b.setMat(.cloth);
    b.addBox(v3(0, -0.115 * H, 0.028 * H), v3(kiteHalf(0.62) * 0.80, 0, 0), v3(0, 0.020 * H, 0), v3(0, 0, 0.002 * H), BLAZON);
    for ([_]f32{ 1, -1 }) |side| {
        b.addBox(
            v3(side * kiteHalf(0.75) * 0.34, -0.196 * H, 0.026 * H),
            v3(side * kiteHalf(0.75) * 0.40, 0.048 * H, 0),
            v3(0, 0.014 * H, 0),
            v3(0, 0, 0.002 * H),
            BLAZON,
        );
    }
    b.setMat(.leather);
    b.addCylinder(v3(-0.052 * H, 0.012 * H, -0.012 * H), v3(0.052 * H, 0.012 * H, -0.012 * H), 0.0085 * H, 0.0085 * H, 6, WRAP); // the forearm strap
    return b.toMesh();
}

/// THE SHIELD IS NOT A BONE (hero.zig's rule, and its pattern): it rides the LEFT WRIST's matrix. The
/// long axis of a strapped kite shield runs DOWN the forearm — which is the wrist frame's own −Y — so
/// the boards need no turning, only standing off the fist and raked a few degrees off the arm.
fn shieldFit() rl.Matrix {
    return mul(mul(rx(-9.0), rz(4.0)), tr(-0.028 * H, FIST_Y + 0.175 * H, FIST_Z + SH_STANDOFF));
}

test "the role table, the enum and the map's foe kinds agree" {
    try std.testing.expectEqual(Role.shieldman, roleOf(.shieldman).?);
    try std.testing.expectEqual(Role.greatsword, roleOf(.greatsword).?);
    try std.testing.expect(roleOf(.archer) == null); // …and its own kin are not folded into a role
    try std.testing.expect(roleOf(.toad) == null);
    try std.testing.expect(roleOf(.berserker) == null);
    try std.testing.expect(roleOf(.brood_sac) == null);
    for (0..SPEC.len) |i| {
        const r: Role = @enumFromInt(i);
        try std.testing.expectEqual(r, roleOf(kindOf(r)).?);
    }
}

test "the two movesets differ in every column that matters" {
    // GOOD REACH is the greatsword's whole identity, and the mace's is that it is the one you can trade with.
    try std.testing.expect(SLAM.reachOut > MACE.reachOut * 1.5);
    try std.testing.expect(SLAM.windDur > MACE.windDur * 1.5);
    try std.testing.expect(SLAM.hit.raw() > MACE.hit.raw() * 1.8);
    // …and it is PAID FOR with an opening: the recovery outlasts the mace's whole attack.
    try std.testing.expect(SLAM.recoverDur > MACE.windDur + MACE.swingDur);
    // Only the heavy one touches stance, so only it can stagger through the hero's own poise.
    try std.testing.expect(SLAM.hit.stance > 0 and MACE.hit.stance == 0);
    try std.testing.expect(spec(.greatsword).speed < spec(.shieldman).speed);
}

test "THE MACE IS NOT FAST ANY MORE, and its windup is most of why" {
    // Owner: "mace skels swing too fast". The tell has to be long enough to be a tell — comfortably
    // past the hero's own light swing, so reading it and answering it is a real exchange.
    try std.testing.expect(MACE.windDur > 0.55);
    try std.testing.expect(MACE.windDur > MACE.swingDur * 2.0);
    // …and the whole attack, tell to recovery, is over a second and a half.
    try std.testing.expect(MACE.windDur + MACE.swingDur + MACE.recoverDur > 1.5);
}

test "a long tell is readable: the slam's windup outlasts a roll" {
    // The one thing an uninterruptible attack owes you is TIME to be somewhere else.
    try std.testing.expect(SLAM.windDur > 0.7);
    try std.testing.expect(SLAM.windDur > SLAM.swingDur * 3.0);
}

test "THE LUNGE IS THE QUICK ONE, and it is the one you can stop" {
    // Owner: a quicker combo, INTERRUPTIBLE, with a little leap.
    try std.testing.expect(!LUNGE.hyper and SLAM.hyper);
    try std.testing.expect(LUNGE.windDur < SLAM.windDur * 0.4);
    try std.testing.expect(LUNGE.strokes > 1 and LUNGE.chainWind > 0);
    // A COMBO'S FOLLOW-UP DOES NOT RE-TELEGRAPH, or it is two attacks with a pause in the middle.
    try std.testing.expect(LUNGE.chainWind < LUNGE.windDur * 0.7);
    // The leap is little, not a pounce: it closes about its own reach and no more.
    try std.testing.expect(LUNGE.lunge > 1.4 and LUNGE.lunge < LUNGE.reachOut);
    try std.testing.expect(LUNGE.hop > 0.2 and LUNGE.hop < 0.7);
    // …and it is worth LESS per stroke than the slam, or there is no reason to ever use the slam.
    try std.testing.expect(LUNGE.hit.raw() * @as(f32, @floatFromInt(LUNGE.strokes)) > SLAM.hit.raw());
    try std.testing.expect(LUNGE.hit.raw() < SLAM.hit.raw());
    // It can be STARTED from further out than it reaches, because the leap covers the difference.
    try std.testing.expect(triggerR(LUNGE, 1.0) > LUNGE.reachOut + foe.HERO_REACH);
}

test "the greatsword answers at his own reach with the slam, and LEAPS the gap with the lunge" {
    const both = [_]bool{ true, true };
    // FURTHER OUT THAN THE BLADE GOES, only the move that closes its own ground is on the table.
    try std.testing.expect(triggerR(SLAM, 1.0) < 3.2 and triggerR(LUNGE, 1.0) > 3.2);
    try std.testing.expectEqual(@as(usize, 1), pick(.greatsword, 3.2, 1.0, &both).?);
    // …and out past even that leap he has no answer at all: he has to walk.
    try std.testing.expect(pick(.greatsword, triggerR(LUNGE, 1.0) + 0.5, 1.0, &both) == null);
    // Inside the blade's own reach both are in range, and the FURTHEST-reaching one wins.
    try std.testing.expectEqual(@as(usize, 0), pick(.greatsword, 1.2, 1.0, &both).?);
    // …and with the slam spent, the lunge is what answers.
    const slamSpent = [_]bool{ false, true };
    try std.testing.expectEqual(@as(usize, 1), pick(.greatsword, 1.2, 1.0, &slamSpent).?);
    // Nothing ready, nothing thrown.
    const none = [_]bool{ false, false };
    try std.testing.expect(pick(.greatsword, 1.2, 1.0, &none) == null);
}

test "range decides the action, and only the shieldman circles" {
    const s: f32 = 1.0;
    const ready = [_]bool{ true, true };
    const spent = [_]bool{ false, false };
    try std.testing.expectEqual(Choice.hold, classify(.shieldman, AGGRO_R + 1, s, ready[0..1]));
    try std.testing.expectEqual(Choice.approach, classify(.shieldman, 8.0, s, ready[0..1]));
    try std.testing.expectEqual(Choice.strike, classify(.shieldman, 1.0, s, ready[0..1]));
    // In reach with the swing on cooldown: the boards walk the fight down, the great blade waits.
    try std.testing.expectEqual(Choice.circle, classify(.shieldman, 1.0, s, spent[0..1]));
    try std.testing.expectEqual(Choice.hold, classify(.greatsword, 1.0, s, spent[0..2]));
    // The greatsword's reach really is longer — the same distance is a strike for one and a walk for the other.
    try std.testing.expectEqual(Choice.strike, classify(.greatsword, 3.0, s, ready[0..2]));
    try std.testing.expectEqual(Choice.approach, classify(.shieldman, 3.0, s, ready[0..1]));
}

test "THE SHIELD IS A DIRECTION, not a bubble, and it is DOWN through the swing" {
    var w = Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(w.guardUp());
    // The window is the swing and the recovery, and nothing else.
    for ([_]State{ .idle, .approach, .circle, .wind }) |s| {
        w.state = s;
        try std.testing.expect(w.guardUp());
    }
    for ([_]State{ .swing, .recover, .stunlight, .stunheavy, .guardbreak, .dead }) |s| {
        w.state = s;
        try std.testing.expect(!w.guardUp());
    }
    // …and a greatsword has no boards at all, in any state.
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.3);
    for ([_]State{ .idle, .approach, .wind, .swing }) |s| {
        g.state = s;
        try std.testing.expect(!g.guardUp());
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), g.guardFrac(), 1e-6);
}

test "BREAK THE GUARD AND IT IS BROKEN FOR GOOD: he kneels, the boards go, he never blocks again" {
    var w = Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    const light = heromod.ATK_LIGHT_HIT;
    var swings: u32 = 0;
    while (w.state != .guardbreak and swings < 20) : (swings += 1) {
        w.hitLatch = false;
        w.covered = true;
        w.tryHit(.{
            .active = true,
            .r = 0.5,
            .a = w.centerWorld(),
            .b = w.centerWorld(),
            .a0 = w.centerWorld(),
            .b0 = w.centerWorld(),
            .hit = light,
        });
    }
    // FOUR-ISH: enough that blocking is worth something, few enough that pressure beats it.
    try std.testing.expect(swings >= 3 and swings <= 5);
    try std.testing.expectEqual(State.guardbreak, w.state);
    try std.testing.expect(w.vit.stunned()); // a REAL heavy reaction, poise immunity and all
    // HE GOES DOWN ON A KNEE, and the pose is a kneel and not a squat: one leg braced, one folded under.
    w.t = KNEEL_IN;
    try std.testing.expect(w.kneelAmount() > 0.9);
    w.pose();
    // …AND THE BOARDS ARE GONE. Not "down until the bar refills" — gone.
    try std.testing.expect(w.shieldGone);
    w.stam.cur = w.stam.max;
    w.stam.winded = false;
    for ([_]State{ .idle, .approach, .circle, .wind }) |s| {
        w.state = s;
        try std.testing.expect(!w.guardUp());
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), w.guardFrac(), 1e-6);
    // …so the next blow from the front lands on him like any other.
    w.state = .idle;
    w.covered = w.guardUp() and true;
    try std.testing.expect(!w.covered);
    // The chip that got through is real, and it is a chip: he is hurt, nowhere near dead.
    try std.testing.expect(w.vit.hp < w.vit.hpMax and w.vit.hp > w.vit.hpMax * 0.85);
}

test "the kneel is a KNEEL: down fast, up slow, and gone by the end of the stagger" {
    var w = Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    w.debugBreak();
    try std.testing.expectApproxEqAbs(@as(f32, 0), w.kneelAmount(), 1e-4); // t = 0: still standing
    w.t = KNEEL_IN;
    const down = w.kneelAmount();
    try std.testing.expect(down > 0.9); // …on the knee within a quarter of a second
    w.t = combat.FOE_HEAVY_STUN_DUR * 0.5;
    try std.testing.expect(w.kneelAmount() > 0.9); // …and he STAYS there
    w.t = combat.FOE_HEAVY_STUN_DUR;
    try std.testing.expectApproxEqAbs(@as(f32, 0), w.kneelAmount(), 1e-4); // back up as the stagger ends
    try std.testing.expect(KNEEL_OUT > KNEEL_IN * 2.0); // getting up is the slow half — that is the punish
    // The legs are ASYMMETRIC through it, or it is a squat: one hip flexes forward, the other does not.
    try std.testing.expect(KNEEL_TRAIL_KNEE > KNEEL_LEAD_KNEE * 1.5);
}

test "a blocked blow is not a hit: no hit-confirm, no flinch, no stance" {
    var w = Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    w.covered = true;
    const before = w.vit.stance;
    w.tryHit(.{
        .active = true,
        .r = 0.5,
        .a = w.centerWorld(),
        .b = w.centerWorld(),
        .a0 = w.centerWorld(),
        .b0 = w.centerWorld(),
        .hit = heromod.ATK_HEAVY_HIT, // a heavy carries stance, and the boards must eat that too
    });
    try std.testing.expectEqual(@as(u32, 0), w.hits);
    try std.testing.expectEqual(State.idle, w.state);
    try std.testing.expectApproxEqAbs(before, w.vit.stance, 1e-5);
    try std.testing.expect(w.stam.cur < w.stam.max);
}

test "UNINTERRUPTIBLE: the diagonal takes the damage and keeps coming — the LUNGE does not" {
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    g.debugSwing(0); // the slam
    const hpBefore = g.vit.hp;
    const HEAVIES: u32 = 4; // …kept short of lethal on purpose: this is about the stagger, not the kill
    std.debug.assert(@as(f32, HEAVIES) * heromod.ATK_HEAVY_HIT.dmg < spec(.greatsword).hp);
    var i: u32 = 0;
    while (i < HEAVIES) : (i += 1) {
        g.hitLatch = false;
        g.tryHit(.{
            .active = true,
            .r = 0.5,
            .a = g.centerWorld(),
            .b = g.centerWorld(),
            .a0 = g.centerWorld(),
            .b0 = g.centerWorld(),
            .hit = heromod.ATK_HEAVY_HIT,
        });
        try std.testing.expectEqual(State.wind, g.state); // never once flinched, at any point
    }
    try std.testing.expectApproxEqAbs(hpBefore - @as(f32, HEAVIES) * heromod.ATK_HEAVY_HIT.dmg, g.vit.hp, 0.01);
    try std.testing.expectEqual(@as(u32, HEAVIES), g.hits);

    // …AND THE LUNGE IS THE ANSWER TO HIM: the same blows, the same window, and it stops dead.
    var q = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    q.debugSwing(1); // the lunge
    try std.testing.expect(!q.hyperArmor());
    var j: u32 = 0;
    while (j < HEAVIES and q.state == .wind) : (j += 1) {
        q.hitLatch = false;
        q.tryHit(.{
            .active = true,
            .r = 0.5,
            .a = q.centerWorld(),
            .b = q.centerWorld(),
            .a0 = q.centerWorld(),
            .b0 = q.centerWorld(),
            .hit = heromod.ATK_HEAVY_HIT,
        });
    }
    try std.testing.expect(q.staggered());

    // ONLY DEATH STOPS THE SLAM — enough damage inside the same window still puts him down.
    var k = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    k.debugSwing(0);
    k.enter(.swing);
    k.vit.hp = 5;
    k.tryHit(.{
        .active = true,
        .r = 0.5,
        .a = k.centerWorld(),
        .b = k.centerWorld(),
        .a0 = k.centerWorld(),
        .b0 = k.centerWorld(),
        .hit = heromod.ATK_LIGHT_HIT,
    });
    try std.testing.expectEqual(State.dead, k.state);
}

test "a shieldman with his boards down takes a blow like anything else" {
    var w = Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    w.state = .recover; // the window his own swing opens
    w.covered = false;
    w.tryHit(.{
        .active = true,
        .r = 0.5,
        .a = w.centerWorld(),
        .b = w.centerWorld(),
        .a0 = w.centerWorld(),
        .b0 = w.centerWorld(),
        .hit = heromod.ATK_HEAVY_HIT,
    });
    try std.testing.expectEqual(@as(u32, 1), w.hits);
    try std.testing.expect(w.staggered());
    try std.testing.expectApproxEqAbs(w.stam.max, w.stam.cur, 1e-5); // the guard paid nothing: it was down
}

/// Drive one whole stroke on the real clock and hand back what it did: whether it reached a hero
/// standing `at` metres dead ahead, the weapon tip's furthest reach, the height it got to at the top of
/// the tell, and the lowest the tip ever went. EVERY hurt-shape test below is measured through here,
/// which is the ogre's law (`clubLowWorld`): re-tune a swing and these numbers move, on purpose.
const Swung = struct { hit: bool, maxD: f32, apex: f32, lowY: f32 };
fn swung(role: Role, mv: usize, stroke: u8, at: f32) Swung {
    var w = Warrior.spawnAs(role, mathx.zero3, 0, 1.0, 0.3);
    w.atk = mv;
    const a = w.move();
    const hero = v3(0, 0, at);
    var apex: f32 = 0;
    w.state = .wind;
    var t: f32 = 0;
    while (t < a.windDur) : (t += 1.0 / 60.0) {
        w.t = t;
        w.setWind(mathx.smoothstep(0, a.windDur * 0.88, t));
        w.pose();
        apex = @max(apex, w.weaponSeg()[1].y);
    }
    w.enter(.swing);
    w.stroke = stroke;
    var out = Swung{ .hit = false, .maxD = 0, .apex = apex, .lowY = 99 };
    t = 0;
    while (t < a.swingDur) : (t += 1.0 / 60.0) {
        w.t = t;
        w.setSwing(mathx.smoothstep(0, a.swingDur, t));
        w.pose();
        const tip = w.weaponSeg()[1];
        out.maxD = @max(out.maxD, mathx.distXZ(w.pos, tip));
        out.lowY = @min(out.lowY, tip.y);
        if (t < a.swingDur * a.impactK) continue;
        w.tryReach(hero);
        if (w.heroHit != null) out.hit = true;
    }
    return out;
}

test "THE HURT SHAPE IS THE POSED WEAPON: every stroke reaches what its own kit reaches, and no further" {
    // THE BUG THIS FILE SHIPPED WITH: a mace whose head never left 0.6 m of his own chest, firing an
    // annulus at 2.8 m. So the contract is now geometric — `reachOut` is a MEASUREMENT of the swing.
    for ([_]struct { r: Role, mv: usize }{
        .{ .r = .shieldman, .mv = 0 },
        .{ .r = .greatsword, .mv = 0 },
        .{ .r = .greatsword, .mv = 1 },
    }) |c| {
        var w = Warrior.spawnAs(c.r, mathx.zero3, 0, 1.0, 0.3);
        w.atk = c.mv;
        const a = w.move();
        const s = swung(c.r, c.mv, 0, 1.2);
        // The tell's own claim: the weapon really does get out to the reach the table advertises…
        try std.testing.expectApproxEqAbs(a.reachOut * w.scale, s.maxD, 0.14);
        // …it lands on a hero standing INSIDE that reach…
        try std.testing.expect(s.hit);
        try std.testing.expect(swung(c.r, c.mv, 0, a.reachOut * w.scale).hit);
        // …and it CANNOT land on one standing a stride past it, whatever the state machine believes.
        try std.testing.expect(!swung(c.r, c.mv, 0, a.reachOut * w.scale + 1.1).hit);
        // …and NOTHING lands while the weapon is still being wound: the tell is a promise, not a blow.
        var q = Warrior.spawnAs(c.r, mathx.zero3, 0, 1.0, 0.3);
        q.debugSwing(c.mv);
        var t: f32 = 0;
        while (t < a.windDur - 1.0 / 60.0) : (t += 1.0 / 60.0) {
            try std.testing.expect(q.update(1.0 / 60.0, v3(0, 0, 1.0), 500.0, .{}) == null);
        }
    }
}

test "A TELL YOU CAN SEE: both kits are carried ABOVE THE SKULL at the top of the windup" {
    // Owner: "windup hard to see". It shipped with the mace head at 1.34 m — chest height on its own
    // owner — so the cock did not break his silhouette at all. Judged against the SHOULDER line, which
    // is the thing a raised weapon has to clear to read as raised.
    const shoulder = REST[CHEST].y * SCALE;
    const mace = swung(.shieldman, 0, 0, 1.2);
    const slam = swung(.greatsword, 0, 0, 2.0);
    try std.testing.expect(mace.apex > shoulder * 1.30); // MEASURED 2.35 m: two thirds of a metre of daylight
    try std.testing.expect(slam.apex > shoulder * 1.60); // MEASURED 2.83 m — two metres of steel, stood on end
    try std.testing.expect(slam.apex > mace.apex); // …and the big one is the bigger tell
}

test "NO STROKE PLOUGHS THE TURF BESIDE HIM, and the slam's point really does reach the earth" {
    // A weapon held radial to the arm through the bottom of an arc goes UNDER the ground — this measured
    // 0.44 m beneath it, next to his own boot, which is why `swingTilt` drives the attitude instead.
    try std.testing.expect(swung(.shieldman, 0, 0, 1.2).lowY > 0.35);
    try std.testing.expect(swung(.greatsword, 1, 0, 2.0).lowY > 0.35);
    // The SLAM is the one exception, and only at the very end: the crater is the point in the dirt.
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.3);
    g.debugSwing(0);
    var t: f32 = 0;
    var crashed = false;
    while (t < SLAM.windDur + SLAM.swingDur and !crashed) : (t += 1.0 / 60.0) {
        _ = g.update(1.0 / 60.0, v3(0, 0, 2.2), 500.0, .{});
        crashed = g.crashed;
    }
    try std.testing.expect(crashed); // …and it fired off the POSED point, not off a fraction of a number
}

test "the stroke latches, so one swing lands once — and a COMBO gets one landing per stroke" {
    // ONE BLOW PER STROKE. The latch is re-armed by `enter`, and the kit goes dead with it, or a combo's
    // follow-up would land its predecessor's stroke off the pose it inherited.
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    g.debugSwing(0);
    const hero = v3(0, 0, 2.0);
    var lands: u32 = 0;
    var t: f32 = 0;
    while (t < SLAM.windDur + SLAM.swingDur + 0.1) : (t += 1.0 / 60.0) {
        if (g.update(1.0 / 60.0, hero, 500.0, .{}) != null) lands += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), lands);
    // …AND THE TWO-STROKE COMBO LANDS TWICE, which is the whole reason `strokes` exists.
    var q = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    q.debugSwing(1);
    lands = 0;
    t = 0;
    while (t < LUNGE.windDur + LUNGE.swingDur * 2 + LUNGE.chainWind + 0.2) : (t += 1.0 / 60.0) {
        if (q.update(1.0 / 60.0, v3(0, 0, LUNGE.lunge * q.scale + 1.4), 500.0, .{}) != null) lands += 1;
    }
    try std.testing.expectEqual(@as(u32, 2), lands);
}

test "HE STEPS INTO THE BLOW: the mace's stroke covers its own ground, and never leaves the earth" {
    // `MACE_STEP` was declared, documented ("a blow thrown off planted feet reads as a man swatting a
    // fly") and never read by anything — so the blow was thrown off planted feet. This is the guard.
    try std.testing.expect(MACE.step > 0.2);
    var m = Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    m.facing = 0; // +Z
    m.debugSwing(0);
    m.enter(.swing);
    var k: f32 = 0;
    while (k <= 1.0) : (k += 1.0 / 90.0) m.flyStroke(mathx.minF(k, 1.0), 500.0);
    m.flyStroke(1.0, 500.0);
    try std.testing.expectApproxEqAbs(MACE.step * m.scale, m.pos.z, 0.02);
    try std.testing.expectApproxEqAbs(@as(f32, 0), m.hop, 1e-4); // a STEP has no height in it
}

test "THE LEAP TRAVELS EXACTLY ITS OWN DISTANCE, and comes back to earth" {
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    g.facing = 0; // +Z
    g.debugSwing(1);
    g.enter(.swing);
    var peak: f32 = 0;
    var k: f32 = 0;
    while (k <= 1.0) : (k += 1.0 / 90.0) {
        g.flyStroke(mathx.minF(k, 1.0), 500.0);
        peak = @max(peak, g.hop);
    }
    g.flyStroke(1.0, 500.0);
    try std.testing.expectApproxEqAbs(LUNGE.lunge * g.scale, g.pos.z, 0.02); // …exactly, not approximately
    try std.testing.expect(peak > LUNGE.hop * g.scale * 0.9); // it really left the ground…
    try std.testing.expectApproxEqAbs(@as(f32, 0), g.hop, 1e-4); // …and it really came back down
    // AIRBORNE only in the middle of it, which is what exempts a committed jump from the terrain rule.
    g.hop = LUNGE.hop * g.scale;
    try std.testing.expect(g.airborne());
    g.hop = 0;
    try std.testing.expect(!g.airborne());
}

test "a skeleton burns and does not freeze, whatever is in its hands" {
    // ONE TABLE, because it is one body — the archer's, and it must stay the archer's.
    for ([_]Role{ .shieldman, .greatsword }) |r| {
        const w = Warrior.spawnAs(r, mathx.zero3, 0, 1.0, 0.2);
        try std.testing.expect(w.vit.res.at(.fire) < 0);
        try std.testing.expect(w.vit.res.at(.cold) > 0);
        try std.testing.expect(w.vit.res.at(.chaos) > 0);
    }
}

test "the kite profile is a kite: widest at the shoulders, a point at the bottom" {
    try std.testing.expect(kiteHalf(0.30) > kiteHalf(0.0)); // the top is domed, not square
    try std.testing.expectApproxEqAbs(SH_HALF, kiteHalf(0.30), 1e-4); // …and widest at the shoulders
    var t: f32 = 0.30;
    var prev = kiteHalf(t);
    while (t <= 1.0) : (t += 0.02) {
        const w = kiteHalf(t);
        try std.testing.expect(w <= prev + 1e-5); // and narrows monotonically from there down
        prev = w;
    }
    try std.testing.expect(kiteHalf(1.0) < SH_HALF * 0.05);
    // It is a TALL shield — it has to be, or it covers a skeleton a foot taller than the hero to the hip only.
    try std.testing.expect((SH_TOP + SH_BOT) > 0.55 * H);
}

