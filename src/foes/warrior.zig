const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const behave = @import("behave.zig");
const wf = @import("../world/worldfmt.zig");
const sfx = @import("../core/audio.zig");
const archermod = @import("archer.zig");
const propart = @import("../props/propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;


const IRON = propart.IRON;
const IRON_LT = rgba(52, 50, 46, 255);
const IRON_DK = rgba(19, 18, 17, 255);
const RUST = rgba(66, 42, 24, 255);
const STEEL = rgba(96, 100, 108, 190);
const STEEL_DK = rgba(38, 40, 45, 255);
const HAFT = rgba(38, 27, 17, 255);
const HAFT_LT = rgba(54, 39, 25, 255);
const WRAP = rgba(44, 33, 24, 255);
const BOARD = rgba(48, 35, 25, 255);
const BOARD_LT = rgba(70, 53, 37, 255);
const BOARD_DK = rgba(30, 22, 16, 255);
const BLAZON = rgba(74, 32, 30, 255);

const DUST = foe.DUST;
const CHIP = archermod.BONE_CHIP;
const CHIP_SPRAY = archermod.boneChips(1.1);
const SPARK = rgba(255, 208, 128, 240);
const SPARK_COOL = rgba(226, 116, 38, 200);
const SPLINTER = rgba(86, 64, 44, 240);

const TRAIL_N = 22;
/// Outlasts the 0.26 s stroke on purpose — the whip curve spends the travel in its first third, so a tighter life leaves the ribbon gone by the frame the point arrives.
const TRAIL_LIFE = 0.30;
const TRAIL_ROOT = 0.24;
const TRAIL_PEAK = 158.0;

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
const SHL = heromod.SHL;
const ELL = heromod.ELL;
const WRL = heromod.WRL;
const SHR = heromod.SHR;
const ELR = heromod.ELR;
const WRR = heromod.WRR;
const WPN = heromod.HELD;

const H: f32 = heromod.H;
const REST = heromod.restHumanoid(heromod.HIP_HALF, heromod.SHOULDER_HALF, H);
/// A HAND TALLER AGAIN THAN THE ARCHER (owner: "make them a bit bigger too"). DERIVED off the archer's own stature, which is itself derived off the hero's, so nothing here is a magic 1.26.
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

const FIST_Y = -0.05 * H;
const FIST_Z = 0.02 * H;

/// Both kits are authored pointing UP off the grip (built in the archer's bow frame, whose +Y runs back up the forearm), so the fit FLIPS them. After it, `wpnTilt` means degrees the weapon leads forward of the forearm line.
const wpnFit = heromod.staffFit;

/// Authors where the kit POINTS in the world (deg forward of straight down: 0 down, 90 level, 180 on end) and
/// hands the wrist whatever that costs. A `wpnTilt` held steady through a 220-deg sweep leaves the weapon radial to the arm at the bottom — measured 0.44 m under the turf beside his own boot. The LUNGE opts out.
fn swingTilt(windAtt: f32, endAtt: f32, k: f32, armSh: f32) f32 {
    return lerpF(windAtt, endAtt, k) - armSh;
}

/// The same trick with the ELBOW PAID FOR TOO. `swingTilt` reads the shoulder alone, honest while a wind keeps the elbow near straight (the mace's is -22); the horizontal's is not, and it MEASURED 0.8 m of blade height for 18 deg of fold. Relation: attitude = tilt + shoulder - elbow.
fn levelTilt(windAtt: f32, endAtt: f32, k: f32, armSh: f32, armEl: f32) f32 {
    return lerpF(windAtt, endAtt, k) - armSh + armEl;
}

const MACE_HEAD = 0.30 * H;
const MACE_CAP = 0.062 * H;
const GS_GUARD = 0.115 * H;
const GS_BLADE = 0.76 * H;
const MACE_FLANGE = 0.046 * H;
const GS_HALF_W = 0.049 * H;

const KIT_SEG = [SPEC.len][2]rl.Vector3{
    .{ v3(0, FIST_Y - 0.02 * H, FIST_Z), v3(0, FIST_Y + MACE_HEAD + MACE_CAP, FIST_Z) },
    .{ v3(0, FIST_Y + GS_GUARD, FIST_Z), v3(0, FIST_Y + GS_GUARD + GS_BLADE, FIST_Z) },
};
const KIT_R = [SPEC.len]f32{ MACE_FLANGE, GS_HALF_W };

pub const Role = enum { shieldman, greatsword };

comptime {
    // …and a SPEC ROW PER ROLE, which `kobold.zig` and `brood.zig` both pin and this did not: `roleOf` measures the run with `SPEC.len`, so a role added without a row returns null for its own kind and `spec()` walks off the end.
    if (SPEC.len != @typeInfo(Role).@"enum".fields.len) @compileError("warrior: a Role with no spec row");
    // A CONTIGUOUS RUN off `shieldman`, in role order — `roleOf`/`kindOf` are an ordinal shift.
    for (@typeInfo(Role).@"enum".fields, 0..) |f, i| {
        const fk: wf.FoeKind = @enumFromInt(@intFromEnum(wf.FoeKind.shieldman) + i);
        if (!std.mem.eql(u8, f.name, @tagName(fk))) {
            @compileError("warrior: wf.FoeKind." ++ @tagName(fk) ++ " is not in the warriors' contiguous run");
        }
    }
}

pub fn roleOf(k: wf.FoeKind) ?Role {
    const lo = @intFromEnum(wf.FoeKind.shieldman);
    const i = @intFromEnum(k);
    if (i < lo or i >= lo + SPEC.len) return null;
    return @enumFromInt(i - lo);
}

pub fn kindOf(r: Role) wf.FoeKind {
    return @enumFromInt(@intFromEnum(wf.FoeKind.shieldman) + @intFromEnum(r));
}

/// WHICH ANIMATION A ROW WEARS, and nothing else — `hyper`/`lunge`/`crash` still carry the MECHANICS. The pose functions used to sniff those columns for identity, which left a third greatsword stroke with no way to be anything but a slam.
const Style = enum { mace, slam, lunge, sweep };

const Attack = struct {
    style: Style,
    /// The AI's TRIGGER RANGE only, pre-scale and measured off the posed kit. What the blow hits is the swept weapon (`tryReach`), so this cannot grow a hurt box the swing never enters — it shipped that way once, a mace head that never left 0.6 m of his own axis firing a 2.8 m sector.
    reachOut: f32,
    windDur: f32,
    swingDur: f32,
    impactK: f32,
    recoverDur: f32,
    cd: f32,
    hit: combat.Hit,
    hyper: bool = false,
    strokes: u8 = 1,
    chainWind: f32 = 0,
    lunge: f32 = 0,
    hop: f32 = 0,
    step: f32 = 0,
    crash: bool = false,
};

const MACE = Attack{
    .style = .mace,
    .reachOut = 1.23, // MEASURED off the posed head: its own furthest, out in front of him at the blow
    .windDur = 0.64,
    .swingDur = 0.30,
    .impactK = 0.26,
    .recoverDur = 0.74,
    .cd = 1.55,
    .hit = .{ .dmg = 14, .poise = 17 },
    .step = MACE_STEP,
};


const SLAM = Attack{
    .style = .slam,
    .reachOut = 2.18, // MEASURED: near three metres of reach, cocked high and driven down through
    .windDur = 1.34,
    .swingDur = 0.30,
    .impactK = 0.24,
    .recoverDur = 1.62,
    .cd = 3.10,
    .hit = .{ .dmg = 30, .poise = 40, .stance = 18 },
    .hyper = true,
    .crash = true,
};

const LUNGE = Attack{
    .style = .lunge,
    .reachOut = 1.98, // MEASURED: the point driven straight out — shorter than the slam's whole arc
    // Was 0.34, which is a two-metre thrust arriving barely over the tell floor. It stays UNDER 0.4 of the slam's haul, because "the lunge is the quick one" is the pair's whole shape.
    .windDur = 0.52,
    .swingDur = 0.26,
    .impactK = 0.46,
    .recoverDur = 1.02,
    .cd = 3.90,
    .hit = .{ .dmg = 17, .poise = 22 },
    .strokes = 2,
    .chainWind = 0.30,
    .lunge = 1.55,
    .hop = 0.40,
};

/// THE STRAFE TAX. The slam is a vertical and the lunge a straight line: one sidestep answered the whole kit, so this is the stroke that owns the ground BESIDE him. `reachOut` and the arc it sweeps are both MEASURED (`swung`).
const SWEEP = Attack{
    .style = .sweep,
    // MEASURED: the tip gets 2.79 m out at full stretch. Held a hair UNDER the slam's 2.18 — `pick` answers at the longest reach in range, and the slam stays the greatsword's first word.
    .reachOut = 2.15,
    .windDur = 0.98,
    .swingDur = 0.34,
    .impactK = 0.30,
    .recoverDur = 1.45,
    .cd = 4.20,
    .hit = .{ .dmg = 24, .poise = 34, .stance = 10 },
    .step = SWEEP_STEP,
};

const MOVES_SHIELDMAN = [_]Attack{MACE};
const MOVES_GREATSWORD = [_]Attack{ SLAM, LUNGE, SWEEP };

/// HOW LONG BEFORE A BLOW LANDS IT CAN STILL BE CAUGHT — the game's own number (`foe.PARRY_LEAD`), the SAME one for all three moves. In SECONDS BEFORE THE HIT, since the impact frames differ wildly (mace 0.078 s into its stroke, slam 0.072, lunge 0.120).
const PARRY_LEAD = foe.PARRY_LEAD;

const Spec = struct {
    hp: f32,
    poise: f32,
    stance: f32,
    speed: f32,
    bodyR: f32,
    hurtR: f32,
    souls: u32,
    moves: []const Attack,
};

const SPEC = [_]Spec{
    .{ .hp = 92, .poise = 15, .stance = 42, .speed = 0.86, .bodyR = 0.36, .hurtR = 0.44, .souls = 180, .moves = &MOVES_SHIELDMAN },
    .{ .hp = 124, .poise = 26, .stance = 58, .speed = 0.74, .bodyR = 0.38, .hurtR = 0.46, .souls = 280, .moves = &MOVES_GREATSWORD },
};

fn spec(r: Role) *const Spec {
    return &SPEC[@intFromEnum(r)];
}

comptime {
    std.debug.assert(SPEC.len == @typeInfo(Role).@"enum".fields.len);
    for (SPEC) |s| std.debug.assert(s.moves.len > 0);
}

/// THE WIDEST MOVESET ANY ROLE HAS, off the table itself — the per-move cooldowns and the readiness scratch are sized from this, so giving a role a third move cannot silently index past either.
const MAX_MOVES = blk: {
    var m: usize = 0;
    for (SPEC) |s| m = @max(m, s.moves.len);
    break :blk m;
};

pub const AGGRO_R = 20.0;
const TURN_RATE = 4.6;
const SWING_TURN = 3.0;
const WALK_SPEED = heromod.WALK_SPEED;
const RUN_SPEED = heromod.RUN_SPEED;
const WALK_IN = 3.2;
const RUN_STALK = 1.2;
const CRASH_LOW = 0.30;
const GATHER_HEAVY = 1.4;
const GATHER_LEAP = 1.7;
const GATHER_PLAIN = 0.85;
const DEATH_DUR = archermod.DEATH_DUR;
const DISS_DUR = archermod.DISS_DUR;
const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 7.0;
const A_BOB = heromod.A_BOB;
const A_PROT = 3.8;

/// DRY BONE AND NOTHING ELSE — the archer's table, because it is the archer's body: it burns, and there is no flesh in it for cold to bite or a poison to find.
const RESISTS = combat.resists(.{ .fire = -35, .cold = 60, .chaos = 45 });

const SHIELD_STAM: f32 = 62.0;

const PELVIS_SHARE: f32 = 0.15;

const CARRY_SH = 6.0;
const CARRY_EL = -18.0;
const CARRY_ABD = 12.0;
/// `wpnTilt` is degrees the weapon leads FORWARD of the forearm line (0 = straight down it), so a shouldered carry is a big number and a blow — the weapon out on the arm's end — is small.
const MACE_CARRY_TILT = 142.0;
const GS_CARRY_TILT = 118.0;
const GS_CARRY_SH = -22.0;
const GS_CARRY_ABD = 26.0;

const GUARD_OFF_SH = 58.0;
const GUARD_OFF_ABD = 26.0;
const GUARD_OFF_EL = -78.0;
const GUARD_TWIST = -22.0;
const GUARD_LEAN = 9.0;
const GUARD_SH = 24.0;
const GUARD_EL = -52.0;
const NAKED_TWIST = -6.0;

// THE MACE SWING, in four beats: gather, cock, step into it, follow through past his centre line. THE ARM GOES LONG AT THE BLOW — a folded elbow at impact keeps the head inside his own silhouette, which is what "the weapon barely moves but I get hit" was: 0.20 m of head travel behind a 2.8 m hurt box.
const MACE_GATHER_SH = -22.0;
const MACE_GATHER_EL = -38.0;
const MACE_WIND_SH = -140.0;
const MACE_WIND_EL = -22.0;
const MACE_WIND_ABD = 52.0;
const MACE_WIND_TWIST = -38.0;
const MACE_WIND_LEAN = -14.0;
const MACE_WIND_TILT = -104.0; // MEASURED: the head above the crown, which is the whole of the tell
const MACE_HIT_SH = 82.0;
const MACE_HIT_EL = -14.0;
const MACE_HIT_ABD = -4.0;
const MACE_HIT_TWIST = 34.0;
const MACE_OVER_SH = 6.0;
const MACE_HIT_SWEEP = 14.0;
const MACE_HIT_LEAN = 30.0;
const MACE_END_ATT = 45.0;
const MACE_WIND_ATT = MACE_WIND_SH + MACE_WIND_TILT + 360.0;
const MACE_STEP = 0.44; // metres of ground the swing carries him forward, pre-scale

const GS_WIND_SH = -146.0;
const GS_WIND_EL = -50.0;
const GS_WIND_ABD = 34.0;
const GS_WIND_TWIST = -48.0;
const GS_WIND_LEAN = -18.0;
const GS_WIND_TILT = -56.0; // MEASURED: better than three metres up, point over his own skull — the tell
const GS_HIT_SH = 74.0;
const GS_HIT_EL = -18.0;
const GS_HIT_ABD = -12.0;
const GS_HIT_TWIST = 44.0;
const GS_HIT_SWEEP = 26.0;
const GS_HIT_LEAN = 34.0;
const GS_END_ATT = 38.0;
const GS_WIND_ATT = GS_WIND_SH + GS_WIND_TILT + 360.0;
const MACE_END_TILT = MACE_END_ATT - (MACE_HIT_SH + MACE_OVER_SH);
const GS_END_TILT = GS_END_ATT - GS_HIT_SH;

// THE HORIZONTAL. The blade is held LEVEL the whole way (the attitude barely moves, 96 deg to 88) and what travels is the SHOULDER'S YAW, `armSweep`, from behind his off hip to past his sword side. That is why a sidestep does not answer it, and why it never touches the turf.
const SWEEP_WIND_SH = 68.0;
const SWEEP_WIND_EL = -66.0;
const SWEEP_WIND_ABD = 28.0;
const SWEEP_WIND_TWIST = -54.0;
const SWEEP_WIND_LEAN = -7.0;
const SWEEP_WIND_SWEEP = -128.0;
const SWEEP_WIND_ATT = 78.0;
const SWEEP_HIT_SH = 82.0;
const SWEEP_HIT_EL = -58.0; // THE ARM STAYS LONG — a folded elbow keeps the tip inside his own silhouette
const SWEEP_HIT_ABD = 4.0;
const SWEEP_HIT_TWIST = 48.0;
const SWEEP_HIT_LEAN = 15.0;
const SWEEP_HIT_SWEEP = 84.0;
const SWEEP_END_ATT = 74.0;
const SWEEP_STEP = 0.52; // metres the stroke carries him forward, pre-scale
/// The two ends of the horizontal's tilt, SOLVED rather than typed: `levelTilt`'s own arithmetic (attitude - shoulder + elbow) at each end. Both the wind and the recover had it written out by hand.
const SWEEP_WIND_TILT = SWEEP_WIND_ATT - SWEEP_WIND_SH + SWEEP_WIND_EL;
const SWEEP_END_TILT = SWEEP_END_ATT - SWEEP_HIT_SH + SWEEP_HIT_EL;

const LUNGE_WIND_SH = -50.0;
const LUNGE_WIND_EL = -72.0;
const LUNGE_WIND_ABD = 8.0;
const LUNGE_WIND_TWIST = -30.0;
const LUNGE_WIND_LEAN = -6.0;
const LUNGE_WIND_TILT = 60.0; // MEASURED: cocked back level at his own ribs, point already at your chest
const LUNGE_HIT_SH = 50.0;
const LUNGE_HIT_EL = -12.0;
const LUNGE_HIT_ABD = -6.0;
const LUNGE_HIT_TWIST = 24.0;
const LUNGE_HIT_SWEEP = 12.0;
const LUNGE_HIT_LEAN = 22.0;
const LUNGE_HIT_TILT = 56.0; // MEASURED: the point stays LEVEL, at chest height — never over your head
const LEAP_LEAD_HIP = 68.0;
const LEAP_LEAD_KNEE = 82.0;
const LEAP_TRAIL_HIP = 26.0;
const LEAP_TRAIL_KNEE = 22.0;
const LEAP_TOE = 20.0;

const BREAK_ARM = 104.0;
const BREAK_STEP = 2.4;
const KNEEL_IN = 0.24;
const KNEEL_OUT = 0.62;
const KNEEL_SINK = 0.315;
const KNEEL_LEAD_HIP = 62.0;
const KNEEL_LEAD_KNEE = 68.0;
const KNEEL_TRAIL_HIP = 14.0;
const KNEEL_TRAIL_KNEE = 122.0;
const KNEEL_FOLD = 19.0;
const KNEEL_HEAD = 40.0;

/// ARITHMETIC over the worst frame (the ring law). At 56 A KILLING BLOW OVERFLOWED IT ON ITS OWN: `chips(20)` (30) + the death `chips(22)` (33) + the wound = 66 into 56. The real worst frame is that blow landing on the KICK, which lays `kickBurst`'s 36 and `grit`'s 18 together: 54 + 66 = 120.
const NPART = 124;
comptime {
    // THE RING LAW, EXECUTABLE: the kick's 36 + 18 with a killing heavy blow's two chip sprays and the shared wound.
    std.debug.assert(NPART >= 36 + 18 + foe.hitParts(20) + foe.hitParts(22) + foe.WOUND_PARTS);
}

const State = enum { idle, approach, circle, wind, swing, recover, stunlight, stunheavy, guardbreak, dead };

const Choice = enum { strike, circle, approach, wait, hold };
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
    return if (r == .shieldman) .circle else .wait;
}

fn triggerR(a: Attack, scale: f32) f32 {
    return foe.hurtReach(a.reachOut + a.lunge * 0.85, scale);
}

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

/// For the shot harness to aim its beats WITH: a portrait pinned to a literal 0.58 s silently photographs a different beat the next time the timing is tuned.
pub const Clock = struct { wind: f32, swing: f32, chain: f32, recover: f32 };
pub fn moveClock(role: Role, mv: usize) Clock {
    const moves = spec(role).moves;
    const a = moves[@min(mv, moves.len - 1)];
    return .{ .wind = a.windDur, .swing = a.swingDur, .chain = a.chainWind, .recover = a.recoverDur };
}

pub const Model = struct {
    bone: [N]rl.Mesh,
    kit: [SPEC.len]rl.Mesh,
    shield: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        const mat = gfx.material(shader, "warrior");
        const kit = [_]rl.Mesh{ maceMesh(), greatswordMesh() };
        var bone = archermod.boneMeshes();
        bone[WPN] = kit[0];
        return .{ .bone = bone, .kit = kit, .shield = shieldMesh(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, w: *const Warrior) void {
        for (0..N) |i| {
            if (i == WPN) continue;
            rl.drawMesh(self.bone[i], self.mat, w.xf[i]);
        }
        rl.drawMesh(self.kit[@intFromEnum(w.role)], self.mat, w.xf[WPN]);
        if (w.role == .shieldman and !w.shieldGone) rl.drawMesh(self.shield, self.mat, shieldXf(w));
    }
};

pub const Warrior = struct {
    role: Role = .shieldman,
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    parry: foe.Parry = .{},
    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    atk: usize = 0,
    stroke: u8 = 0,
    cds: [MAX_MOVES]f32 = [_]f32{0} ** MAX_MOVES,
    dealt: bool = false,
    crashed: bool = false,
    heroHit: ?combat.Hit = null,
    routine: behave.Routine = .{},
    homing: bool = false,
    leapDone: f32 = 0,
    hop: f32 = 0,
    leapt: bool = false,
    /// THE SHIELD CAUGHT HIS STROKE THIS FRAME — a one-frame flag, reset at the top of `update`. A latch would bill the beat sixty times a second for the whole stumble.
    parried: bool = false,
    covered: bool = false,
    shieldGone: bool = false,
    blocks: u32 = 0,
    stam: combat.Stamina = combat.Stamina.initFoe(SHIELD_STAM),
    blockT: f32 = mathx.LONG_AGO,

    // posture channels (degrees), resolved by the state and read by pose()
    armSh: f32 = CARRY_SH,
    armEl: f32 = CARRY_EL,
    armAbd: f32 = CARRY_ABD,
    armSweep: f32 = 0,
    wpnTilt: f32 = MACE_CARRY_TILT,
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
    prevPhase: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(SPEC[0].hp, SPEC[0].poise, SPEC[0].stance).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},
    heldOpen: bool = false,
    /// …AND A BODY MAY BE RAISED ONCE. A latch nothing clears (`shieldGone`'s arrangement): twice is a fight that cannot be won by killing things.
    wasRaised: bool = false,
    fade: f32 = 0,
    gone: bool = false,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,
    wpnWas: [2]rl.Vector3 = .{ mathx.zero3, mathx.zero3 },
    wpnIs: ?[2]rl.Vector3 = null,
    /// Set by the swing, spent AFTER `pose()`: the hurt shape IS the posed weapon, so it cannot be tested before the pose it is measured off exists.
    live: bool = false,
    trail: foe.Trail(TRAIL_N) = .{},

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
        for (&w.cds) |*c| c.* = 0.3 + seed * 0.9;
        w.setCarryInstant();
        w.pose();
        return w;
    }

    fn move(self: *const Warrior) Attack {
        const moves = spec(self.role).moves;
        return moves[@min(self.atk, moves.len - 1)];
    }

    pub fn centerWorld(self: *const Warrior) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], mathx.zero3);
    }
    pub fn hurtRadius(self: *const Warrior) f32 {
        return spec(self.role).hurtR * self.scale;
    }
    pub fn bodyR(self: *const Warrior) f32 {
        return spec(self.role).bodyR * self.scale;
    }
    pub fn lockPoint(self: *const Warrior) rl.Vector3 {
        return foe.markOn(self.xf[SKULL], archermod.LOCK_AT);
    }
    pub fn topWorld(self: *const Warrior) rl.Vector3 {
        return foe.bodyPoint(self.pos, archermod.TOP_F * H, self.scale, self.hop);
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
    pub fn airborne(self: *const Warrior) bool {
        return self.hop > foe.AIRBORNE_LIFT;
    }
    pub fn soulValue(self: *const Warrior) u32 {
        return spec(self.role).souls;
    }
    pub fn kind(self: *const Warrior) wf.FoeKind {
        return kindOf(self.role);
    }
    pub fn guardFrac(self: *const Warrior) f32 {
        return if (self.role == .shieldman and !self.shieldGone) self.stam.frac() else 0;
    }
    pub fn blocksTaken(self: *const Warrior) u32 {
        return self.blocks;
    }

    pub fn guardUp(self: *const Warrior) bool {
        if (self.role != .shieldman or self.gone or self.shieldGone) return false;
        if (self.stam.winded) return false;
        return switch (self.state) {
            .idle, .approach, .circle, .wind => true,
            .swing, .recover, .stunlight, .stunheavy, .guardbreak, .dead => false,
        };
    }

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

    pub fn navWant(self: *const Warrior, hero: rl.Vector3) ?rl.Vector3 {
        if (self.state == .approach) return if (self.homing) self.home else hero;
        if (self.state != .circle) return null;
        return self.routine.walkTo(self.pos, hero);
    }
    pub fn update(self: *Warrior, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.heroHit = null;
        self.justDied = false;
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);
        self.leapt = false;
        self.parried = false;
        self.live = false;
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.stam.tick(dt, false, self.guardUp());
        self.blockT += dt;
        for (&self.cds) |*c| c.* = mathx.maxF(0, c.* - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, self.home, hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        self.trail.age(dt);

        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const sp = spec(self.role);
        const a = self.move();
        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        self.takeParry();
        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.setCarry(dt);
                if (self.t >= 0.18) self.decide(d);
            },
            .approach => {
                const tgt = if (self.homing) self.home else hero;
                self.faceToward(self.nav.aim(self.pos, tgt), dt);
                const f = self.fdir();
                moveSpeed = self.approachSpeed(d);
                const moved = moveSpeed * dt;
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
                const w = self.routine.step(dt, .{ .at = self.pos, .facing = self.facing, .quarry = hero, .nav = self.nav });
                self.faceToward(w.look orelse hero, dt);
                if (w.go) |g| {
                    const go = mathx.dirXZ(self.pos, g);
                    if (mathx.lenXZ(go) > 1e-3) {
                        moveSpeed = WALK_SPEED * sp.speed * 0.72;
                        const moved = moveSpeed * dt;
                        mathx.stepXZ(&self.pos, go, moved, bounds);
                        movedDist = moved;
                        moveYaw = mathx.headingXZ(go);
                    }
                }
                self.setCarry(dt);
                if (!self.routine.running) self.decide(d);
            },
            .wind => {
                self.faceToward(hero, dt * 0.5);
                const dur = self.windDur();
                self.setWind(mathx.smoothstep(0, dur * 0.88, self.t));
                const load: f32 = switch (a.style) {
                    .slam, .sweep => GATHER_HEAVY,
                    .lunge => GATHER_LEAP,
                    .mace => GATHER_PLAIN,
                };
                if (self.stroke == 0) self.emitGather(dt, mathx.clampF(self.t / dur, 0, 1) * load);
                if (self.t >= dur) self.enter(.swing);
            },
            .swing => {
                foe.faceToward(self.pos, &self.facing, hero, SWING_TURN, dt);
                const k = mathx.clampF(self.t / a.swingDur, 0, 1);
                self.setSwing(foe.swingCurve(self.t / a.swingDur));
                self.flyStroke(k, bounds);
                if (self.t >= a.swingDur * a.impactK) self.live = true;
                if (self.t >= a.swingDur) {
                    self.hop = 0;
                    if (self.stroke + 1 < a.strokes) {
                        self.stroke += 1;
                        self.enter(.wind);
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
                foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, archermod.DISSOLVE);
            },
        }

        self.covered = self.guardUp();

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.footfalls();
        self.pose();
        if (self.live) self.tryReach(hero);
        if (self.state == .swing) self.crashIn();
        if (self.state == .swing and self.move().lunge > 0) {
            const seg = self.wpnHere();
            self.trail.push(seg[0], seg[1], self.wpnWas[1], TRAIL_ROOT);
        }
        self.tryHit(blade);
        return self.heroHit;
    }

    fn windDur(self: *const Warrior) f32 {
        const a = self.move();
        return if (self.stroke == 0 or a.chainWind <= 0) a.windDur else a.chainWind;
    }
    fn longestTrigger(self: *const Warrior) f32 {
        var r: f32 = 0;
        for (spec(self.role).moves) |a| r = mathx.maxF(r, triggerR(a, self.scale));
        return r;
    }
    fn walkInR(self: *const Warrior) f32 {
        return self.longestTrigger() + WALK_IN * self.scale;
    }
    /// Inside `walkInR`, or homeward, he walks. Slower than the hero's run either way. PUBLIC because it is one half of a CROSS-CREATURE comparison — the berserker is pinned above every skeleton that charges (`game.zig`).
    pub fn approachSpeed(self: *const Warrior, dist: f32) f32 {
        const base = spec(self.role).speed;
        if (self.homing or dist <= self.walkInR()) return WALK_SPEED * base;
        return RUN_SPEED * base;
    }
    fn runBlend(self: *const Warrior) f32 {
        const base = spec(self.role).speed;
        return mathx.clampF((self.speedS - WALK_SPEED * base) / ((RUN_SPEED - WALK_SPEED) * base), 0, 1);
    }

    fn flyStroke(self: *Warrior, k: f32, bounds: f32) void {
        const a = self.move();
        const offEarth = a.lunge > 0 and self.stroke == 0;
        const dist = if (offEarth) a.lunge else a.step;
        if (dist <= 0) return;
        const e = 1.0 - (1.0 - k) * (1.0 - k);
        const want = dist * self.scale * e;
        mathx.stepXZ(&self.pos, self.fdir(), want - self.leapDone, bounds);
        self.leapDone = want;
        if (!offEarth) return;
        const wasUp = self.hop > foe.AIRBORNE_LIFT;
        self.hop = a.hop * self.scale * mathx.sinf(k * std.math.pi);
        if (!wasUp and self.hop > foe.AIRBORNE_LIFT) {
            self.kickBurst(-1.0, 34, 6.2);
            self.grit(self.pos, 12);
            self.leapt = true;
        }
        if (wasUp and self.hop <= foe.AIRBORNE_LIFT) {
            self.kickBurst(1.0, 36, 5.0);
            self.grit(self.pos, 18);
            sfx.world(.step_hard, self.pos);
        }
    }

    fn kickBurst(self: *Warrior, along: f32, n: i32, spd: f32) void {
        const f = self.fdir();
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const B = comptime foe.Blast.of(foe.DUST_DRAG, 0.42, 0.80);
            const s = self.fxRng.range(0.5, 1.0) * spd * self.scale * B.boost;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(self.pos.x + self.fxRng.signed() * 0.22, self.pos.y + 0.04, self.pos.z + self.fxRng.signed() * 0.22),
                .v = v3(f.x * along * s + mathx.cosf(a) * s * 0.45, self.fxRng.range(1.1, 3.4) * B.boost, f.z * along * s + mathx.sinf(a) * s * 0.45),
                .life = B.life(&self.fxRng),
                .r0 = self.fxRng.range(0.08, 0.19) * self.scale,
                .r1 = 0.34 * self.fxRng.range(0.8, 1.4) * self.scale,
                .col = DUST,
                .col1 = foe.DUST_THIN,
                .grav = foe.DUST_GRAV,
                .drag = foe.DUST_DRAG,
            });
        }
    }

    fn crashIn(self: *Warrior) void {
        if (self.crashed or !self.move().crash) return;
        const tip = self.wpnHere()[1];
        if (tip.y > self.pos.y + CRASH_LOW * self.scale) return;
        self.crashed = true;
        const at = v3(tip.x, self.pos.y, tip.z);
        self.dustBurst(at, 34, 5.2, 0.40);
        self.grit(at, 14);
        sfx.world(.ogre_slam, at);
    }

    fn enter(self: *Warrior, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
        self.crashed = false;
        self.live = false;
        if (s != .wind and s != .swing) {
            self.stroke = 0;
            self.leapDone = 0;
            self.hop = 0;
        }
        if (s == .swing) self.leapDone = 0;
        switch (s) {
            .wind => {
                if (self.stroke > 0) return;
                switch (self.move().style) {
                    .lunge => {
                        sfx.world(.skel_lunge, self.pos);
                        self.dustBurst(self.pos, 26, 3.4, 0.34);
                        self.grit(self.pos, 10);
                    },
                    .slam, .sweep => sfx.world(.swing_heavy, self.pos),
                    .mace => sfx.world(.swing_light, self.pos),
                }
            },
            .swing => {
                if (self.role == .shieldman) sfx.world(.swing_light, self.pos);
                if (self.move().lunge > 0) sfx.world(.swing_heavy, self.pos);
            },
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
        self.hop = 0;
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
        const moves = spec(self.role).moves;
        const n = moves.len;
        const canLeap = foe.canLeap(&self.root);
        for (0..n) |i| ready[i] = self.cds[i] <= 0 and (canLeap or moves[i].hop <= 0);
        switch (classify(self.role, dist, self.scale, ready[0..n])) {
            .strike => {
                self.atk = pick(self.role, dist, self.scale, ready[0..n]) orelse 0;
                self.stroke = 0;
                self.enter(.wind);
            },
            .circle => {
                self.routine.start(&behave.FLANK, self.seed - 0.5);
                self.enter(.circle);
            },
            .approach => {
                self.homing = false;
                self.enter(.approach);
            },
            .wait => {
                self.homing = false;
                self.enter(.idle);
            },
            .hold => {
                if (mathx.distXZ(self.pos, self.home) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.enter(.approach);
                } else self.enter(.idle);
            },
        }
    }

    fn wpnHere(self: *const Warrior) [2]rl.Vector3 {
        return self.wpnIs orelse self.weaponSeg();
    }

    pub fn weaponSeg(self: *const Warrior) [2]rl.Vector3 {
        const s = KIT_SEG[@intFromEnum(self.role)];
        return .{
            rl.math.vector3Transform(s[0], self.xf[WPN]),
            rl.math.vector3Transform(s[1], self.xf[WPN]),
        };
    }

    /// HOW FAR OUT THE KIT ACTUALLY ARRIVES at the impact frame, hero footprint included — the MOVE's own rather than one number per warrior: a mace lands at 1.23 m, the slam at 2.18.
    fn parryReach(self: *const Warrior, a: Attack) f32 {
        return foe.hurtReach(a.reachOut, self.scale);
    }

    fn toImpact(self: *const Warrior) ?f32 {
        const a = self.move();
        const live = a.swingDur * a.impactK;
        return switch (self.state) {
            .wind => (self.windDur() - self.t) + live,
            .swing => live - self.t,
            .idle, .approach, .circle, .recover, .stunlight, .stunheavy, .guardbreak, .dead => null,
        };
    }

    /// THE INSTANT THE KIT CAN BE CAUGHT IN, and how far out it reaches then — null when there is nothing to catch. The window is the last `PARRY_LEAD` seconds of the blow's approach, so it shuts AT the impact frame by construction.
    fn parryable(self: *const Warrior) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return self.parryReach(self.move());
    }

    /// THE SHIELD TAKES THE STROKE, and HYPER ARMOUR IS NO DEFENCE AGAINST IT — `hyperArmor` refuses POISE off the blade and a parry deals none, so the one move you cannot interrupt is the one the boards can still stop outright.
    fn takeParry(self: *Warrior) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        self.cds[self.atk] = self.move().cd;
        self.sparks(self.wpnHere()[1], mathx.dirXZ(self.pos, self.parry.at), 16);
        sfx.world(.bone_hurt, self.pos);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(.stunheavy),
            .light, .none => self.enterStun(.stunlight),
        }
    }

    /// The hurt shape IS the kit: what it swept this frame, against the column the hero stands in, latched to one blow per stroke — never a yaw-guessed sector.
    fn tryReach(self: *Warrior, hero: rl.Vector3) void {
        if (self.dealt) return;
        const r = foe.hurtReach(KIT_R[@intFromEnum(self.role)], self.scale);
        if (!foe.weaponReaches(self.wpnWas, self.wpnHere(), hero, r)) return;
        self.heroHit = self.move().hit;
        self.dealt = true;
        self.leash.noteCombat();
    }

    fn shielded(self: *const Warrior, blade: foe.Blade) bool {
        if (!self.covered) return false;
        const at = mathx.lerpV(blade.a, blade.b, 0.5);
        const d = mathx.dirXZ(self.pos, at);
        if (mathx.lenXZ(d) < 1e-4) return true;
        return combat.withinGuardArc(mathx.headingXZ(d), self.facing);
    }

    pub fn tryHit(self: *Warrior, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const blocked = self.shielded(blade);
        var b = blade;
        if (blocked) {
            b.hit = combat.guardChip(blade.hit, combat.GUARD_NEGATE);

        } else if (self.hyperArmor()) {
            b.hit = .{ .dmg = blade.hit.dmg, .elem = blade.hit.elem };
        }
        const s = foe.reached(self, b) orelse return;
        if (blocked) return self.caught(blade.hit, s);
        const heavyBlow = foe.wounded(self, s, blade, .{ .light = 1.2, .heavy = 1.9 });
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

    fn caught(self: *Warrior, raw: combat.Hit, s: foe.Strike) void {
        self.blockT = 0;
        self.blocks += 1;
        self.stam.spend(combat.guardStamina(raw));
        self.shove = mathx.scaleV(self.fdir(), -0.6);
        self.sparks(s.contact, s.dir, 14);
        sfx.world(.foe_guarded, self.pos);
        if (s.reaction == .death) {
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

    fn breakGuard(self: *Warrior, at: rl.Vector3) void {
        sfx.world(.guard_break, self.pos);
        self.flash = FLASH_DUR;
        self.shove = mathx.scaleV(self.fdir(), -BREAK_STEP);
        self.shatter(at);
        self.shieldGone = true;
        self.vit.beginStun(.heavy);
        self.enterStun(.guardbreak);
    }

    pub fn raisable(self: *const Warrior) bool {
        return self.state == .dead and !self.gone and !self.wasRaised and self.t >= DEATH_DUR;
    }

    pub fn reraise(self: *Warrior, frac: f32) void {
        foe.rekindle(self, frac);
        self.wasRaised = true;
        self.enterStun(.stunlight);
        self.leash.noteCombat();
        self.pose();
    }

    pub fn debugSwing(self: *Warrior, which: usize) void {
        self.atk = @min(which, spec(self.role).moves.len - 1);
        self.stroke = 0;
        self.enter(.wind);
    }
    pub fn debugBreak(self: *Warrior) void {
        self.stam.cur = 0;
        self.stam.winded = true;
        self.breakGuard(self.centerWorld());
    }
    pub fn stagger(self: *Warrior, heavy: bool) void {
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

    fn setCarry(self: *Warrior, dt: f32) void {
        const e = dt * 7.0;
        const breathe = mathx.sinf(self.elapsed * 1.15 + self.seed * 6.28);
        const stalk = self.moving * (1.0 + RUN_STALK * self.runBlend());
        const up: f32 = if (self.guardUp()) 1 else 0;
        const rec = mathx.maxF(0, 1.0 - self.blockT / 0.28);

        if (self.role == .greatsword) {
            self.armSh = mathx.approach(self.armSh, GS_CARRY_SH + 3.0 * breathe - 6.0 * stalk, e);
            self.armEl = mathx.approach(self.armEl, CARRY_EL - 10.0, e);
            self.armAbd = mathx.approach(self.armAbd, GS_CARRY_ABD + 2.0 * breathe, e);
            self.offSh = mathx.approach(self.offSh, GS_CARRY_SH - 16.0, e);
            self.offEl = mathx.approach(self.offEl, -58.0, e);
            self.offAbd = mathx.approach(self.offAbd, -34.0, e);
            self.bodyLean = mathx.approach(self.bodyLean, 5.0 + 1.2 * breathe + 5.0 * stalk, e);
            self.twist = mathx.approach(self.twist, -8.0, e);
        } else if (self.shieldGone) {
            self.armSh = mathx.approach(self.armSh, CARRY_SH + 14.0 + 3.0 * breathe, e);
            self.armEl = mathx.approach(self.armEl, CARRY_EL - 26.0, e);
            self.armAbd = mathx.approach(self.armAbd, CARRY_ABD + 4.0, e);
            self.offSh = mathx.approach(self.offSh, CARRY_SH - 8.0, e);
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
        const kArm = k * @sqrt(k);
        switch (self.move().style) {
            .slam => self.setSlamWind(k, kArm),
            .lunge => self.setLungeWind(k, kArm),
            .sweep => self.setSweepWind(k, kArm),
            .mace => self.setMaceWind(k, kArm),
        }
    }

    fn setMaceWind(self: *Warrior, k: f32, kArm: f32) void {
        const gather = mathx.pulse(k, 0, 0.16, 0.30, 0.52);
        const raise = mathx.smoothstep(0.24, 1.0, kArm);
        const shiver = mathx.sinf(self.t * 34.0) * 1.5 * mathx.smoothstep(0.80, 1.0, k);
        self.armSh = lerpF(GUARD_SH, MACE_GATHER_SH, gather) + (MACE_WIND_SH - GUARD_SH) * raise + shiver;
        self.armEl = lerpF(GUARD_EL, MACE_GATHER_EL, gather) + (MACE_WIND_EL - GUARD_EL) * raise;
        self.armAbd = lerpF(CARRY_ABD, MACE_WIND_ABD, raise);
        self.armSweep = lerpF(0, -24.0, raise);
        self.wpnTilt = lerpF(MACE_CARRY_TILT, MACE_WIND_TILT, raise) + shiver * 0.8;
        if (self.shieldGone) {
            self.offSh = lerpF(CARRY_SH - 8.0, -30.0, raise);
            self.offEl = lerpF(CARRY_EL - 6.0, -46.0, raise);
            self.offAbd = lerpF(-CARRY_ABD - 4.0, -22.0, raise);
        } else {
            self.offSh = lerpF(GUARD_OFF_SH, GUARD_OFF_SH + 6.0, k);
            self.offEl = GUARD_OFF_EL;
            self.offAbd = lerpF(GUARD_OFF_ABD, GUARD_OFF_ABD - 8.0, k);
        }
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
        self.armSweep = lerpF(0, -26.0, kArm);
        self.wpnTilt = lerpF(GS_CARRY_TILT, GS_WIND_TILT, kArm) + shiver * 0.7;
        self.offSh = lerpF(GS_CARRY_SH - 16.0, GS_WIND_SH + 26.0, kArm);
        self.offEl = lerpF(-58.0, -80.0, kArm);
        self.offAbd = lerpF(-34.0, -12.0, kArm);
        self.bodyLean = lerpF(5.0, GS_WIND_LEAN, k);
        self.twist = lerpF(-8.0, GS_WIND_TWIST, k);
        self.headPitch = lerpF(2.0, -12.0, k);
        self.legBrace = lerpF(0, 0.62, k);
    }

    fn setSweepWind(self: *Warrior, k: f32, kArm: f32) void {
        const shiver = mathx.sinf(self.t * 32.0) * 1.4 * mathx.smoothstep(0.78, 1.0, k);
        self.armSh = lerpF(GS_CARRY_SH, SWEEP_WIND_SH, kArm) + shiver;
        self.armEl = lerpF(CARRY_EL - 10.0, SWEEP_WIND_EL, kArm);
        self.armAbd = lerpF(GS_CARRY_ABD, SWEEP_WIND_ABD, kArm);
        self.armSweep = lerpF(0, SWEEP_WIND_SWEEP, kArm);
        self.wpnTilt = lerpF(GS_CARRY_TILT, SWEEP_WIND_TILT, kArm) + shiver * 0.7;
        self.offSh = lerpF(GS_CARRY_SH - 16.0, SWEEP_WIND_SH - 12.0, kArm);
        self.offEl = lerpF(-58.0, -70.0, kArm);
        self.offAbd = lerpF(-34.0, -20.0, kArm);
        self.bodyLean = lerpF(5.0, SWEEP_WIND_LEAN, k);
        self.twist = lerpF(-8.0, SWEEP_WIND_TWIST, k);
        self.headPitch = lerpF(2.0, -4.0, k);
        self.legBrace = lerpF(0, 0.58, k);
    }

    fn setLungeWind(self: *Warrior, k: f32, kArm: f32) void {
        self.armSh = lerpF(GS_CARRY_SH, LUNGE_WIND_SH, kArm);
        self.armEl = lerpF(CARRY_EL - 10.0, LUNGE_WIND_EL, kArm);
        self.armAbd = lerpF(GS_CARRY_ABD, LUNGE_WIND_ABD, kArm);
        self.armSweep = lerpF(0, -14.0, kArm);
        self.wpnTilt = lerpF(GS_CARRY_TILT, LUNGE_WIND_TILT, kArm);
        self.offSh = lerpF(GS_CARRY_SH - 16.0, LUNGE_WIND_SH - 20.0, kArm);
        self.offEl = lerpF(-58.0, -76.0, kArm);
        self.offAbd = lerpF(-34.0, -26.0, kArm);
        self.bodyLean = lerpF(5.0, LUNGE_WIND_LEAN, k);
        self.twist = lerpF(-8.0, LUNGE_WIND_TWIST, k);
        self.headPitch = lerpF(2.0, -4.0, k);
        self.legBrace = lerpF(0, 0.86, k);
    }

    fn setSwing(self: *Warrior, k: f32) void {
        const kW = 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k);
        switch (self.move().style) {
            .slam => self.setSlamSwing(kW, k),
            .lunge => self.setLungeSwing(kW, k),
            .sweep => self.setSweepSwing(kW, k),
            .mace => self.setMaceSwing(kW, k),
        }
    }

    fn setMaceSwing(self: *Warrior, kW: f32, k: f32) void {
        const over = mathx.smoothstep(0.72, 1.0, k);
        self.armSh = lerpF(MACE_WIND_SH, MACE_HIT_SH, kW) + MACE_OVER_SH * over;
        self.armEl = lerpF(MACE_WIND_EL, MACE_HIT_EL, kW);
        self.armAbd = lerpF(MACE_WIND_ABD, MACE_HIT_ABD, kW);
        self.armSweep = lerpF(-24.0, MACE_HIT_SWEEP, kW) + 8.0 * over;
        self.wpnTilt = swingTilt(MACE_WIND_ATT, MACE_END_ATT, k, self.armSh);
        self.offSh = lerpF(if (self.shieldGone) -30.0 else GUARD_OFF_SH + 6.0, -16.0, kW);
        self.offEl = lerpF(if (self.shieldGone) -46.0 else GUARD_OFF_EL, -36.0, kW);
        self.offAbd = lerpF(if (self.shieldGone) -22.0 else GUARD_OFF_ABD - 8.0, -34.0, kW);
        self.bodyLean = lerpF(MACE_WIND_LEAN, MACE_HIT_LEAN, k);
        self.twist = lerpF(MACE_WIND_TWIST, MACE_HIT_TWIST, kW);
        self.headPitch = lerpF(-8.0, 22.0, kW);
        self.legBrace = lerpF(0.46, 0.66, k);
    }

    fn setSlamSwing(self: *Warrior, kW: f32, k: f32) void {
        self.armSh = lerpF(GS_WIND_SH, GS_HIT_SH, kW);
        self.armEl = lerpF(GS_WIND_EL, GS_HIT_EL, kW);
        self.armAbd = lerpF(GS_WIND_ABD, GS_HIT_ABD, kW);
        self.armSweep = lerpF(-26.0, GS_HIT_SWEEP, kW);
        self.wpnTilt = swingTilt(GS_WIND_ATT, GS_END_ATT, k, self.armSh);
        self.offSh = lerpF(GS_WIND_SH + 26.0, GS_HIT_SH - 18.0, kW);
        self.offEl = lerpF(-80.0, -30.0, kW);
        self.offAbd = lerpF(-12.0, -44.0, kW);
        self.bodyLean = lerpF(GS_WIND_LEAN, GS_HIT_LEAN, k);
        self.twist = lerpF(GS_WIND_TWIST, GS_HIT_TWIST, kW);
        self.headPitch = lerpF(-12.0, 26.0, kW);
        self.legBrace = lerpF(0.62, 0.9, k);
    }

    fn setSweepSwing(self: *Warrior, kW: f32, k: f32) void {
        self.armSh = lerpF(SWEEP_WIND_SH, SWEEP_HIT_SH, kW);
        self.armEl = lerpF(SWEEP_WIND_EL, SWEEP_HIT_EL, kW);
        self.armAbd = lerpF(SWEEP_WIND_ABD, SWEEP_HIT_ABD, kW);
        self.armSweep = lerpF(SWEEP_WIND_SWEEP, SWEEP_HIT_SWEEP, kW);
        self.wpnTilt = levelTilt(SWEEP_WIND_ATT, SWEEP_END_ATT, k, self.armSh, self.armEl);
        self.offSh = lerpF(SWEEP_WIND_SH - 12.0, SWEEP_HIT_SH - 22.0, kW);
        self.offEl = lerpF(-70.0, -34.0, kW);
        self.offAbd = lerpF(-20.0, -40.0, kW);
        self.bodyLean = lerpF(SWEEP_WIND_LEAN, SWEEP_HIT_LEAN, k);
        self.twist = lerpF(SWEEP_WIND_TWIST, SWEEP_HIT_TWIST, kW);
        self.headPitch = lerpF(-4.0, 10.0, kW);
        self.legBrace = lerpF(0.58, 0.72, k);
    }

    fn setLungeSwing(self: *Warrior, kW: f32, k: f32) void {
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
        self.legBrace = lerpF(0.86, 0.34, k);
    }

    fn setRecover(self: *Warrior, u: f32) void {
        const over = 1.0 - mathx.smoothstep(0.30, 1.0, u);
        const heave = mathx.sinf(self.elapsed * 8.0) * 2.4 * over;
        // EXHAUSTIVE, like `setWind` and `setSwing`: written as an if-chain falling through to the mace, a fifth style silently wore the club's recovery instead of failing to compile.
        switch (self.move().style) {
            .sweep => {
                self.armSh = lerpF(GS_CARRY_SH, SWEEP_HIT_SH, over) + heave * 0.5;
                self.armEl = lerpF(CARRY_EL - 10.0, SWEEP_HIT_EL, over);
                self.armAbd = lerpF(GS_CARRY_ABD, SWEEP_HIT_ABD, over);
                self.armSweep = lerpF(0, SWEEP_HIT_SWEEP, over);
                self.wpnTilt = lerpF(GS_CARRY_TILT, SWEEP_END_TILT, over);
                self.offSh = lerpF(GS_CARRY_SH - 16.0, SWEEP_HIT_SH - 22.0, over);
                self.offEl = lerpF(-58.0, -34.0, over);
                self.offAbd = lerpF(-34.0, -40.0, over);
                self.bodyLean = lerpF(5.0, SWEEP_HIT_LEAN + 5.0, over) + heave;
                self.twist = lerpF(-8.0, SWEEP_HIT_TWIST, over);
                self.headPitch = lerpF(2.0, 16.0, over);
                self.legBrace = lerpF(0, 0.70, over);
            },
            .slam => {
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
            },
            .lunge => {
                self.armSh = lerpF(GS_CARRY_SH, -30.0, over);
                self.armEl = lerpF(CARRY_EL - 10.0, -26.0, over);
                self.armAbd = lerpF(GS_CARRY_ABD, -8.0, over);
                self.armSweep = lerpF(0, -40.0, over);
                self.wpnTilt = lerpF(GS_CARRY_TILT, 92.0, over);
                self.offSh = lerpF(GS_CARRY_SH - 16.0, -40.0, over);
                self.offEl = lerpF(-58.0, -24.0, over);
                self.offAbd = lerpF(-34.0, -28.0, over);
                self.bodyLean = lerpF(5.0, LUNGE_HIT_LEAN + 4.0, over) + heave * 0.6;
                self.twist = lerpF(-8.0, -18.0, over);
                self.headPitch = lerpF(2.0, 18.0, over);
                self.legBrace = lerpF(0, 0.55, over);
            },
            .mace => {
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
            },
        }
    }

    fn stunAmount(self: *const Warrior) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t, false),
            .stunheavy, .guardbreak => foe.stunCurve(self.t, true),
            else => 0,
        };
    }

    fn kneelAmount(self: *const Warrior) f32 {
        if (self.state != .guardbreak) return 0;
        const d = combat.FOE_HEAVY_STUN_DUR;
        return mathx.smoothstep(0, KNEEL_IN, self.t) * (1.0 - mathx.smoothstep(d - KNEEL_OUT, d, self.t));
    }

    pub fn rigScale(self: *const Warrior) f32 {
        return foe.rigScale(self.scale, self.fade);
    }

    pub fn pose(self: *Warrior) void {
        const fs = self.rigScale();
        const sink = foe.rigSink(foe.SINK_HUMANOID, self.scale, self.fade);
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.45, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stun = self.stunAmount();
        const kn = self.kneelAmount();

        const m = self.moving * (1.0 - dk) * (1.0 - kn);
        const runB = self.runBlend() * (1.0 - dk) * (1.0 - kn);
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const latW = @abs(self.latB) * m;
        const sway = heromod.strafeSway(latW, runB) * mathx.sinf(twoPi * self.phase) * m;
        const prot = A_PROT * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB) +
            heromod.strafeProt(self.phase, self.latB, m);
        const dip = heromod.STRAFE_DIP * latW;
        // THE LEGS TAKE THE BRACE IN THE KNEES, they do not squat (owner's law) — only the small pelvis drop a real knee bend costs.
        const braceSink = 0.030 * H * self.legBrace + KNEEL_SINK * H * kn;

        var wx: [N]rl.Matrix = undefined;
        const collapse = mathx.lerpF(hipY, 0.22 * H, dk);
        const pitchRoot = (self.bodyLean * PELVIS_SHARE) + 20.0 * dk - 24.0 * stun * (1.0 - kn) + 4.0 * kn;
        const pelvY = if (dead) collapse else hipY + bob - dip - braceSink;
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(9.0 * dk), rx(pitchRoot), ry(prot + self.twist * 0.22)),
            mul(tr(sway * fs, pelvY * fs + sink + self.hop, 0), ry(facingDeg)),
            heromod.rootAt(self.pos),
        ));

        const legsTaken = dead or kn > 0.001 or self.leaping();
        if (!legsTaken) {
            heromod.legChain(&wx, &self.rest, self.pos.y, self.phase, m, runB, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.pos.y, self.phase + 0.5, m, runB, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        }
        self.poseUpper(&wx, dk, stun, kn, dead, prot);
        self.xf = wx;
        const seg = self.weaponSeg();
        self.wpnWas = self.wpnIs orelse seg;
        self.wpnIs = seg;
    }

    fn leaping(self: *const Warrior) bool {
        return self.state == .swing and self.stroke == 0 and self.move().lunge > 0;
    }

    fn poseUpper(self: *Warrior, wx: *[N]rl.Matrix, dk: f32, stun: f32, kn: f32, dead: bool, prot: f32) void {
        const rest = self.rest;
        const wonk = (self.seed - 0.5) * 6.0;
        const brk = if (self.state == .guardbreak) stun else 0;
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
            heromod.deadLegs(wx, rest, dk);
        } else if (kn > 0.001) {
            setLocal(wx, HIPL, rest, mul(rx(-KNEEL_LEAD_HIP * kn), rz(-4.0)));
            setLocal(wx, KNEEL, rest, rx(8.0 + KNEEL_LEAD_KNEE * kn));
            setLocal(wx, ANKL, rest, rx(-16.0 * kn));
            setLocal(wx, HIPR, rest, mul(rx(KNEEL_TRAIL_HIP * kn), rz(5.0)));
            setLocal(wx, KNEER, rest, rx(8.0 + KNEEL_TRAIL_KNEE * kn));
            setLocal(wx, ANKR, rest, rx(26.0 * kn));
        } else if (self.leaping()) {
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



    const PUFF = foe.Puff{
        .blast = foe.Blast.of(foe.DUST_DRAG, 0.38, 0.68),
        .spdLo = 0.45,
        .upLo = 0.7,
        .upHi = 2.6,
        .rLo = 0.07,
        .rHi = 0.15,
    };
    fn dustBurst(self: *Warrior, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        foe.puff(&self.parts, &self.fxHead, &self.fxRng, v3(c.x, self.pos.y + 0.05, c.z), n, spd, big, self.scale, PUFF);
    }
    fn grit(self: *Warrior, c: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(1.2, 3.4) * self.scale;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(c.x, self.pos.y + 0.08, c.z),
                .v = v3(mathx.cosf(a) * s, self.fxRng.range(2.4, 5.2), mathx.sinf(a) * s),
                .life = self.fxRng.range(0.45, 0.85),
                .r0 = self.fxRng.range(0.025, 0.055) * self.scale,
                .r1 = 0.012,
                .col = CHIP,
                .grav = 9.0,
                .stretch = 0.030,
                .bounce = 0.42,
            });
        }
    }
    fn chips(self: *Warrior, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        foe.spray(&self.parts, &self.fxHead, &self.fxRng, at, dir, n, spd, self.scale, CHIP_SPRAY);
    }
    fn sparks(self: *Warrior, at: rl.Vector3, dir: rl.Vector3, n: i32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(1.4, 4.2);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = at,
                .v = v3(-dir.x * sp * 0.5 + mathx.cosf(a) * sp * 0.6, self.fxRng.range(1.2, 3.6), -dir.z * sp * 0.5 + mathx.sinf(a) * sp * 0.6),
                .life = self.fxRng.range(0.16, 0.34),
                .r0 = self.fxRng.range(0.014, 0.030),
                .r1 = 0.002,
                .col = SPARK,
                .col1 = SPARK_COOL,
                .grav = 6.0,
                .stretch = 0.055,
                .bounce = 0.45,
                .add = true,
            });
        }
    }
    fn shatter(self: *Warrior, at: rl.Vector3) void {
        var i: i32 = 0;
        while (i < 26) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(1.6, 5.0) * self.scale;
            const wood = self.fxRng.float() < 0.72;
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(at.x + self.fxRng.signed() * 0.18, at.y + self.fxRng.signed() * 0.26, at.z + self.fxRng.signed() * 0.18),
                .v = v3(mathx.cosf(a) * sp, self.fxRng.range(1.4, 4.6), mathx.sinf(a) * sp),
                .life = self.fxRng.range(0.5, 0.95),
                .r0 = self.fxRng.range(0.03, 0.075) * self.scale,
                .r1 = 0.010,
                .col = if (wood) SPLINTER else CHIP,
                .grav = 8.5,
                .stretch = 0.035,
                .bounce = if (wood) 0.30 else 0.42,
            });
        }
        self.sparks(at, self.fdir(), 12);
    }
    fn emitGather(self: *Warrior, dt: f32, k: f32) void {
        const emitRate = (5.0 + 26.0 * k);
        var owed = foe.emitDue(&self.fxAccum, dt, emitRate);
        while (owed > 0) : (owed -= 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.2, 0.7) * self.scale;
            const B = comptime foe.Blast.of(foe.DUST_DRAG, 0.28, 0.5);
            foe.emitPart(&self.parts, &self.fxHead, .{
                .p = v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.04, self.pos.z + mathx.sinf(a) * rr),
                .v = v3(self.fxRng.signed() * 0.5 * B.boost, self.fxRng.range(0.3, 1.3) * B.boost, self.fxRng.signed() * 0.5 * B.boost),
                .life = B.life(&self.fxRng),
                .r0 = self.fxRng.range(0.03, 0.07) * self.scale,
                .r1 = 0.012,
                .col = DUST,
                .col1 = foe.DUST_THIN,
                .grav = foe.DUST_GRAV,
                .drag = foe.DUST_DRAG,
            });
        }
    }
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
    pub fn drawFx(self: *const Warrior) void {
        foe.drawParticles(&self.parts);
        self.trail.draw(TRAIL_LIFE, foe.WAKE, TRAIL_PEAK);
    }

    pub fn draw(self: *const Warrior, model: *const Model) void {
        model.draw(self);
    }
};

pub const CAP = SPEC.len * wf.MAX_PER_KIND;

pub const Muster = struct {
    model: Model,
    band: [CAP]Warrior = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Muster {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Muster) []Warrior {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Muster) []const Warrior {
        return self.band[0..self.n];
    }

    pub fn reset(self: *Muster, m: *const wf.Map) void {
        foe.resetRoles(Warrior, Role, &self.band, &self.n, m, roleOf);
    }

    pub fn setShader(self: *Muster, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn setParry(self: *Muster, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    /// …and whether any of them was caught on it this frame. A ONE-FRAME edge, `anyDied`'s, read after `update`.
    pub fn anyParried(self: *const Muster) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn draw(self: *const Muster, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Muster) void {
        for (self.liveConst()) |*w| w.drawFx();
    }

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
    /// ONE OF THEM LEFT THE GROUND THIS FRAME. The lunge is only ever thrown from inside its own trigger radius, so a leap is always near enough for the frame to be allowed to feel it.
    pub fn anyLeapt(self: *const Muster) bool {
        for (self.liveConst()) |*w| {
            if (w.leapt) return true;
        }
        return false;
    }
    pub fn soulsDropped(self: *const Muster) u32 {
        return foe.soulsEach(self.liveConst());
    }

    pub fn update(self: *Muster, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var blow: ?foe.Blow = null;
        for (self.live()) |*w| {
            if (w.update(dt, w.threat.aim(hero), bounds, blade)) |h| foe.worseBlow(&blow, h, w.pos, &w.threat);
        }
        return blow;
    }
};


fn maceMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(5507);
    const fy = FIST_Y;
    const fz = FIST_Z;
    const headY = fy + MACE_HEAD;

    b.setMat(.wood);
    b.addCylinder(v3(0, fy - 0.11 * H, fz), v3(0, headY + 0.008 * H, fz), 0.0135 * H, 0.0125 * H, 7, HAFT);
    b.setMat(.leather);
    b.addCylinder(v3(0, fy + 0.062 * H, fz), v3(0, fy - 0.070 * H, fz), 0.0165 * H, 0.0165 * H, 7, WRAP);
    b.setMat(.steel);
    b.addCapsule(v3(0, fy - 0.118 * H, fz), v3(0, fy - 0.098 * H, fz), 0.020 * H, 0.018 * H, 8, IRON);
    b.addCylinder(v3(0, fy + 0.070 * H, fz), v3(0, fy + 0.082 * H, fz), 0.019 * H, 0.019 * H, 7, IRON_DK);

    b.addCapsule(v3(0, headY - 0.036 * H, fz), v3(0, headY + 0.034 * H, fz), 0.028 * H, 0.026 * H, 9, IRON);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = @as(f32, @floatFromInt(i)) * (std.math.tau / 5.0) + rng.range(-0.12, 0.12);
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        const out = MACE_FLANGE * rng.range(0.88, 1.10);
        const half = 0.030 * H * rng.range(0.85, 1.12);
        const cx = ca * out * 0.62;
        const cz = sa * out * 0.62;
        b.addBox(
            v3(cx, headY + rng.range(-0.006, 0.006) * H, fz + cz),
            v3(ca * out, 0, sa * out),
            v3(0, half, 0),
            v3(-sa * 0.0055 * H, 0, ca * 0.0055 * H),
            if (rng.float() < 0.3) RUST else IRON_LT,
        );
    }
    b.addCapsule(v3(0, headY + 0.034 * H, fz), v3(0, FIST_Y + MACE_HEAD + MACE_CAP, fz), 0.014 * H, 0.006 * H, 7, IRON_LT);
    return b.toMesh();
}

fn greatswordMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(6611);
    const fy = FIST_Y;
    const fz = FIST_Z;
    const guardY = fy + GS_GUARD;
    // ABOVE THE GUARD, like every other feature of this blade — measured off the FIST it lands BELOW the last blade segment's top, drawing the point inside the steel and cutting the hurt segment 0.12 m short.
    const tipY = guardY + GS_BLADE;

    b.setMat(.wood);
    b.addCylinder(v3(0, fy - 0.155 * H, fz), v3(0, guardY, fz), 0.0125 * H, 0.0115 * H, 7, HAFT);
    b.setMat(.leather);
    b.addCylinder(v3(0, fy + 0.080 * H, fz), v3(0, fy - 0.145 * H, fz), 0.0155 * H, 0.0155 * H, 7, WRAP);
    for ([_]f32{ -0.104, 0.020 }) |gy| {
        b.addCylinder(v3(0, fy + gy * H, fz), v3(0, fy + (gy + 0.011) * H, fz), 0.0172 * H, 0.0172 * H, 7, HAFT_LT);
    }
    b.setMat(.steel);
    b.addCapsule(v3(0, fy - 0.170 * H, fz), v3(0, fy - 0.150 * H, fz), 0.0215 * H, 0.019 * H, 9, IRON);

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
        );
    }
    b.addCylinder(v3(0, guardY, fz), v3(0, guardY + 0.030 * H, fz), 0.0165 * H, 0.0135 * H, 7, IRON_DK);

    const seg = [_]f32{ 0.030, 0.300, 0.560, 0.700 };
    const halfW = [_]f32{ GS_HALF_W / H, 0.045, 0.036, 0.020 };
    const halfT = [_]f32{ 0.0068, 0.0060, 0.0048, 0.0032 };
    for (0..3) |s| {
        const y0 = guardY + seg[s] * H;
        const y1 = guardY + seg[s + 1] * H;
        const w0 = halfW[s] * H;
        const w1 = halfW[s + 1] * H;
        const t0 = halfT[s] * H;
        b.addBox(
            v3(0, (y0 + y1) * 0.5, fz),
            v3((w0 + w1) * 0.5, 0, 0),
            v3(0, (y1 - y0) * 0.5, 0),
            v3(0, 0, t0),
            if (s == 1) STEEL_DK else STEEL,
        );
    }
    b.addCapsule(v3(0, guardY + seg[3] * H, fz), v3(0, tipY, fz), 0.014 * H, 0.003 * H, 7, STEEL);
    b.addBox(
        v3(0, guardY + 0.30 * H, fz),
        v3(0.013 * H, 0, 0),
        v3(0, 0.27 * H, 0),
        v3(0, 0, 0.0075 * H),
        STEEL_DK,
    );
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

const SH_TOP = 0.215 * H;
const SH_BOT = 0.415 * H;
const SH_HALF = 0.135 * H;
const SH_THICK = 0.017 * H;
const SH_ROWS = 11;
const SH_STANDOFF = 0.085 * H;

fn kiteHalf(t: f32) f32 {
    if (t <= 0.30) {
        const u = (0.30 - t) / 0.30;
        return SH_HALF * @sqrt(mathx.maxF(1.0 - u * u * 0.86, 0.02));
    }
    const u = (t - 0.30) / 0.70;
    return SH_HALF * mathx.maxF(1.0 - std.math.pow(f32, u, 1.35), 0.012);
}

fn shieldMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(7703);
    b.setMat(.wood);
    var i: usize = 0;
    while (i < SH_ROWS) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / SH_ROWS;
        const t1 = @as(f32, @floatFromInt(i + 1)) / SH_ROWS;
        const y0 = mathx.lerpF(SH_TOP, -SH_BOT, t0);
        const y1 = mathx.lerpF(SH_TOP, -SH_BOT, t1);
        const w = mathx.maxF(kiteHalf((t0 + t1) * 0.5), 0.004 * H) * rng.range(0.97, 1.02);
        const dish = 0.020 * H * (1.0 - std.math.pow(f32, @abs((t0 + t1) - 0.62), 1.6));
        const col = switch (@mod(i, 3)) {
            0 => BOARD,
            1 => BOARD_LT,
            else => BOARD_DK,
        };
        b.addBox(
            v3(0, (y0 + y1) * 0.5, dish),
            v3(w, 0, 0),
            v3(0, (y0 - y1) * 0.5 + 0.002 * H, 0),
            v3(0, 0, SH_THICK * 0.5),
            col,
        );
    }
    b.setMat(.steel);
    i = 0;
    while (i < SH_ROWS) : (i += 1) {
        if (rng.float() < 0.12) continue;
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
    b.addCapsule(v3(-SH_HALF * 0.94, SH_TOP - 0.004 * H, 0.004 * H), v3(SH_HALF * 0.94, SH_TOP - 0.004 * H, 0.004 * H), 0.0078 * H, 0.0072 * H, 7, IRON);
    b.addCapsule(v3(0, 0.012 * H, 0.020 * H), v3(0, 0.012 * H, 0.034 * H), 0.030 * H, 0.020 * H, 9, IRON_LT);
    b.addBox(v3(0, 0.012 * H, 0.026 * H), v3(SH_HALF * 0.82, 0, 0), v3(0, 0.0105 * H, 0), v3(0, 0, 0.005 * H), IRON_DK);
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
    b.addCylinder(v3(-0.052 * H, 0.012 * H, -0.012 * H), v3(0.052 * H, 0.012 * H, -0.012 * H), 0.0085 * H, 0.0085 * H, 6, WRAP);
    return b.toMesh();
}

/// THE SHIELD IS NOT A BONE (hero.zig's rule): it rides the LEFT WRIST's matrix. The long axis of a strapped kite shield runs DOWN the forearm — the wrist frame's own −Y — so the boards need no turning, only standing off the fist and raked a few degrees off the arm.
const SH_HUB = v3(-0.028 * H, FIST_Y + 0.175 * H, FIST_Z + SH_STANDOFF);
const SH_RAKE_X = -9.0;
const SH_RAKE_Z = 4.0;

fn shieldXf(w: *const Warrior) rl.Matrix {
    const fs = w.rigScale();
    const hub = rl.math.vector3Transform(SH_HUB, w.xf[WRL]);
    return mul3(
        scaleM(fs, fs, fs),
        mul3(rx(SH_RAKE_X), rz(SH_RAKE_Z), ry(mathx.degrees(w.facing))),
        tr(hub.x, hub.y, hub.z),
    );
}

test "the role table, the enum and the map's foe kinds agree" {
    try std.testing.expectEqual(Role.shieldman, roleOf(.shieldman).?);
    try std.testing.expectEqual(Role.greatsword, roleOf(.greatsword).?);
    try std.testing.expect(roleOf(.archer) == null);
    try std.testing.expect(roleOf(.toad) == null);
    try std.testing.expect(roleOf(.berserker) == null);
    try std.testing.expect(roleOf(.brood_sac) == null);
    for (0..SPEC.len) |i| {
        const r: Role = @enumFromInt(i);
        try std.testing.expectEqual(r, roleOf(kindOf(r)).?);
    }
}

test "THE WINDOW IS AN INSTANT BEFORE THE HIT, on every stroke a warrior throws" {
    try std.testing.expect(PARRY_LEAD > 0);
    for ([_]Role{ .shieldman, .greatsword }) |role| {
        var w = Warrior.spawnAs(role, mathx.ground(0, 0), 0, 1.0, 0.0);
        for (spec(role).moves, 0..) |a, mv| {
            const impact = a.swingDur * a.impactK;
            // It is an INSTANT, not a slice of the tell — a 1.34 s haul must not be catchable for a fifth of it.
            try std.testing.expect(PARRY_LEAD < a.windDur * 0.4);
            // MEASURED off the state machine rather than asserted about the constants: walk the move frame by frame from the first of its windup and collect the span that is actually parryable.
            const step = 1.0 / 600.0;
            var open: f32 = -1;
            var shut: f32 = -1;
            var elapsed: f32 = 0;
            w.atk = mv;
            w.stroke = 0;
            while (elapsed <= a.windDur + impact) : (elapsed += step) {
                if (elapsed > a.windDur) {
                    w.state = .swing;
                    w.t = elapsed - a.windDur;
                } else {
                    w.state = .wind;
                    w.t = elapsed;
                }
                if (w.parryable() != null) {
                    if (open < 0) open = elapsed;
                    shut = elapsed;
                }
            }
            try std.testing.expect(open > 0);
            try std.testing.expectApproxEqAbs(a.windDur + impact, shut, 2.0 * step);
            try std.testing.expectApproxEqAbs(PARRY_LEAD, shut - open, 3.0 * step);
            try std.testing.expect(w.parryReach(a) <= triggerR(a, w.scale) + 1e-4);
        }
        if (spec(role).moves.len > 1) {
            const a = spec(role).moves[1];
            try std.testing.expect(a.strokes > 1 and a.chainWind > 0);
            w.atk = 1;
            w.state = .wind;
            w.t = 0;
            w.stroke = 0;
            const first = w.toImpact().?;
            w.stroke = 1;
            const chained = w.toImpact().?;
            // The follow-up's blow is nearer BY THE WHOLE DIFFERENCE between the two winds — 0.22 s of it — which is exactly what reading `windDur()` rather than `a.windDur` buys.
            try std.testing.expectApproxEqAbs(a.windDur - a.chainWind, first - chained, 1e-5);
            // …and it really is catchable. Both windows land inside the STROKE rather than the wind, because the point goes live 0.12 s in and the lead is shorter than that.
            w.state = .swing;
            w.t = a.swingDur * a.impactK - PARRY_LEAD * 0.5;
            try std.testing.expect(w.parryable() != null);
        }
        for ([_]State{ .idle, .approach, .circle, .recover, .stunlight, .stunheavy, .guardbreak, .dead }) |s| {
            w.state = s;
            w.t = 0;
            try std.testing.expect(w.parryable() == null);
        }
    }
    var g = Warrior.spawnAs(.greatsword, mathx.ground(0, 0), 0, 1.0, 0.0);
    try std.testing.expect(g.parryReach(LUNGE) < triggerR(LUNGE, g.scale));
}

test "A CAUGHT STROKE NEVER LANDS, and HYPER ARMOUR is no defence against the boards" {
    // The slam cannot be TRADED with (`hyperArmor` refuses its poise), which is why being able to refuse it outright is worth having.
    var w = Warrior.spawnAs(.greatsword, mathx.ground(0, 0), 0, 1.0, 0.0);
    const hero = mathx.v3(0, 0, 1.6);
    w.atk = 0;
    const a = w.move();
    try std.testing.expect(a.hyper);
    w.state = .swing;
    w.t = a.swingDur * a.impactK - PARRY_LEAD * 0.5;
    try std.testing.expect(w.hyperArmor());
    w.parry = .{ .live = true, .at = hero, .facing = 0 };
    w.takeParry();
    try std.testing.expect(!w.parried and w.state == .swing);
    w.parry = .{ .live = true, .at = hero, .facing = std.math.pi };
    w.takeParry();
    try std.testing.expect(w.parried);
    try std.testing.expectEqual(State.stunlight, w.state);
    try std.testing.expect(!w.live);
    try std.testing.expect(w.cds[0] > 0);
    try std.testing.expectEqual(@as(f32, 0), w.hop);
    w.state = .swing;
    w.t = a.swingDur * a.impactK - PARRY_LEAD * 0.5;
    w.parried = false;
    w.takeParry();
    try std.testing.expect(w.parried);
    try std.testing.expectEqual(State.stunheavy, w.state);
}

test "the two movesets differ in every column that matters" {
    try std.testing.expect(SLAM.reachOut > MACE.reachOut * 1.5);
    try std.testing.expect(SLAM.windDur > MACE.windDur * 1.5);
    try std.testing.expect(SLAM.hit.raw() > MACE.hit.raw() * 1.8);
    try std.testing.expect(SLAM.recoverDur > MACE.windDur + MACE.swingDur);
    try std.testing.expect(SLAM.hit.stance > 0 and MACE.hit.stance == 0);
    try std.testing.expect(spec(.greatsword).speed < spec(.shieldman).speed);
}

test "THE MACE IS NOT FAST ANY MORE, and its windup is most of why" {
    try std.testing.expect(MACE.windDur > 0.55);
    try std.testing.expect(MACE.windDur > MACE.swingDur * 2.0);
    try std.testing.expect(MACE.windDur + MACE.swingDur + MACE.recoverDur > 1.5);
}

test "a long tell is readable: the slam's windup outlasts a roll" {
    try std.testing.expect(SLAM.windDur > 0.7);
    try std.testing.expect(SLAM.windDur > SLAM.swingDur * 3.0);
}

test "THE LUNGE IS THE QUICK ONE, and it is the one you can stop" {
    try std.testing.expect(!LUNGE.hyper and SLAM.hyper);
    try std.testing.expect(LUNGE.windDur < SLAM.windDur * 0.4);
    try std.testing.expect(LUNGE.strokes > 1 and LUNGE.chainWind > 0);
    try std.testing.expect(LUNGE.chainWind < LUNGE.windDur * 0.7);
    try std.testing.expect(LUNGE.lunge > 1.4 and LUNGE.lunge < LUNGE.reachOut);
    try std.testing.expect(LUNGE.hop > 0.2 and LUNGE.hop < 0.7);
    try std.testing.expect(LUNGE.hit.raw() * @as(f32, @floatFromInt(LUNGE.strokes)) > SLAM.hit.raw());
    try std.testing.expect(LUNGE.hit.raw() < SLAM.hit.raw());
    try std.testing.expect(triggerR(LUNGE, 1.0) > LUNGE.reachOut + foe.HERO_REACH);
}

test "the greatsword answers at his own reach with the slam, and LEAPS the gap with the lunge" {
    const all = [_]bool{ true, true, true };
    try std.testing.expect(triggerR(SLAM, 1.0) < 3.2 and triggerR(LUNGE, 1.0) > 3.2);
    try std.testing.expect(triggerR(SWEEP, 1.0) < 3.2);
    try std.testing.expectEqual(@as(usize, 1), pick(.greatsword, 3.2, 1.0, &all).?);
    try std.testing.expect(pick(.greatsword, triggerR(LUNGE, 1.0) + 0.5, 1.0, &all) == null);
    try std.testing.expectEqual(@as(usize, 0), pick(.greatsword, 1.2, 1.0, &all).?);
    // WITH THE SLAM COOLING, THE HORIZONTAL IS THE CLOSE ANSWER and the lunge stays the stroke that covers ground. Only when both are spent does he throw the leap at his own feet.
    const slamSpent = [_]bool{ false, true, true };
    try std.testing.expectEqual(@as(usize, 2), pick(.greatsword, 1.2, 1.0, &slamSpent).?);
    const swordOnly = [_]bool{ false, true, false };
    try std.testing.expectEqual(@as(usize, 1), pick(.greatsword, 1.2, 1.0, &swordOnly).?);
    const none = [_]bool{ false, false, false };
    try std.testing.expect(pick(.greatsword, 1.2, 1.0, &none) == null);
}

/// THE SECTOR A STROKE ACTUALLY COVERS, in degrees off his facing, measured by standing a hero on a ring at `r` and asking every 5 deg whether the swept kit reaches him. The tip's own bearing is NOT this number — a vertical's tip passes over his skull, where a 2 cm radius spins the bearing through 159 deg of nothing.
fn covered(mv: usize, r: f32) struct { lo: f32, hi: f32, deg: f32 } {
    var lo: f32 = 999;
    var hi: f32 = -999;
    var b: f32 = -100;
    while (b <= 100) : (b += 5) {
        const rad = mathx.radians(b);
        if (!swungAt(.greatsword, mv, 0, v3(mathx.sinf(rad) * r, 0, mathx.cosf(rad) * r)).hit) continue;
        lo = @min(lo, b);
        hi = @max(hi, b);
    }
    return .{ .lo = lo, .hi = hi, .deg = hi - lo };
}

test "THE SWEEP IS THE STRAFE TAX: a wide LEVEL sector where the slam and the lunge are both a line" {
    const sw = swung(.greatsword, 2, 0, 2.0);
    const slam = swung(.greatsword, 0, 0, 2.0);
    // MEASURED: 2.79 m of tip, held level between 1.28 m and 2.01 m — never the turf, never over his skull.
    try std.testing.expect(sw.maxD > 2.7 and sw.lowY > 0.9 and sw.apex < slam.apex);
    try std.testing.expect(sw.apex - sw.lowY < 1.0);
    // THE TELL IS LATERAL, the one thing this stroke may have instead of a raised weapon: at the top of the wind the blade is out past a metre and a half on his sword side, and level. MEASURED 1.92 m.
    try std.testing.expect(sw.windLat > 1.4);
    try std.testing.expect(@abs(sw.windY - sw.lowY) < 0.9);
    // AND THE SECTOR IS THE POINT. MEASURED 95 deg at 1.4 m and 85 at 2.0 — where the vertical's own sector COLLAPSES with distance (65 -> 45), because a line only ever covers the line.
    const near = covered(2, 1.4);
    const far = covered(2, 2.0);
    std.debug.print("\n  sweep: tip {d:.2} m out, {d:.2}..{d:.2} m up, cocked {d:.2} m aside; covers {d:.0} deg at 1.4 m, {d:.0} at 2.0 (slam {d:.0}/{d:.0})\n", .{
        sw.maxD, sw.lowY, sw.apex, sw.windLat, near.deg, far.deg, covered(0, 1.4).deg, covered(0, 2.0).deg,
    });
    try std.testing.expect(near.deg >= 90 and far.deg >= 80);
    try std.testing.expect(far.deg > covered(0, 2.0).deg * 1.7);
    try std.testing.expect(far.deg > covered(1, 2.0).deg * 1.7);
    // …and it is CENTRED on him rather than trailing off one shoulder, so the tax is the same either way he steps.
    try std.testing.expect(@abs(far.lo + far.hi) < 20.0);
    // A hero stood the width of a roll off the line the slam comes down is inside this stroke, not that one.
    const off = v3(1.28, 0, 1.28);
    try std.testing.expect(swungAt(.greatsword, 2, 0, off).hit);
    try std.testing.expect(!swungAt(.greatsword, 0, 0, off).hit);
}

test "range decides the action, and only the shieldman circles" {
    const s: f32 = 1.0;
    const ready = [_]bool{ true, true, true };
    const spent = [_]bool{ false, false, false };
    try std.testing.expectEqual(Choice.hold, classify(.shieldman, AGGRO_R + 1, s, ready[0..1]));
    try std.testing.expectEqual(Choice.approach, classify(.shieldman, 8.0, s, ready[0..1]));
    try std.testing.expectEqual(Choice.strike, classify(.shieldman, 1.0, s, ready[0..1]));
    try std.testing.expectEqual(Choice.circle, classify(.shieldman, 1.0, s, spent[0..1]));
    try std.testing.expectEqual(Choice.wait, classify(.greatsword, 1.0, s, spent[0..3]));
    try std.testing.expectEqual(Choice.strike, classify(.greatsword, 3.0, s, ready[0..3]));
    try std.testing.expectEqual(Choice.approach, classify(.shieldman, 3.0, s, ready[0..1]));
}

test "A COOLDOWN IS NOT A RETREAT: in reach with nothing to throw he holds his ground" {
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    g.pos = v3(0, 0, foe.LEASH_HOME_R + 12.0);
    for (&g.cds) |*c| c.* = 1.0;
    g.decide(1.0);
    try std.testing.expect(!g.homing);
    try std.testing.expectEqual(State.idle, g.state);
    g.decide(AGGRO_R + 5.0);
    try std.testing.expect(g.homing);
    try std.testing.expectEqual(State.approach, g.state);
}

test "THE SHIELD IS A DIRECTION, not a bubble, and it is DOWN through the swing" {
    var w = Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    try std.testing.expect(w.guardUp());
    for ([_]State{ .idle, .approach, .circle, .wind }) |s| {
        w.state = s;
        try std.testing.expect(w.guardUp());
    }
    for ([_]State{ .swing, .recover, .stunlight, .stunheavy, .guardbreak, .dead }) |s| {
        w.state = s;
        try std.testing.expect(!w.guardUp());
    }
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
    try std.testing.expect(swings >= 3 and swings <= 5);
    try std.testing.expectEqual(State.guardbreak, w.state);
    try std.testing.expect(w.vit.stunned());
    w.t = KNEEL_IN;
    try std.testing.expect(w.kneelAmount() > 0.9);
    w.pose();
    try std.testing.expect(w.shieldGone);
    w.stam.cur = w.stam.max;
    w.stam.winded = false;
    for ([_]State{ .idle, .approach, .circle, .wind }) |s| {
        w.state = s;
        try std.testing.expect(!w.guardUp());
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), w.guardFrac(), 1e-6);
    w.state = .idle;
    w.covered = w.guardUp() and true;
    try std.testing.expect(!w.covered);
    try std.testing.expect(w.vit.hp < w.vit.hpMax and w.vit.hp > w.vit.hpMax * 0.85);
}

test "the kneel is a KNEEL: down fast, up slow, and gone by the end of the stagger" {
    var w = Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    w.debugBreak();
    try std.testing.expectApproxEqAbs(@as(f32, 0), w.kneelAmount(), 1e-4);
    w.t = KNEEL_IN;
    const down = w.kneelAmount();
    try std.testing.expect(down > 0.9);
    w.t = combat.FOE_HEAVY_STUN_DUR * 0.5;
    try std.testing.expect(w.kneelAmount() > 0.9);
    w.t = combat.FOE_HEAVY_STUN_DUR;
    try std.testing.expectApproxEqAbs(@as(f32, 0), w.kneelAmount(), 1e-4);
    try std.testing.expect(KNEEL_OUT > KNEEL_IN * 2.0);
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
        .hit = heromod.ATK_HEAVY_HIT,
    });
    try std.testing.expectEqual(@as(u32, 0), w.hits);
    try std.testing.expectEqual(State.idle, w.state);
    try std.testing.expectApproxEqAbs(before, w.vit.stance, 1e-5);
    try std.testing.expect(w.stam.cur < w.stam.max);
}

test "UNINTERRUPTIBLE: the diagonal takes the damage and keeps coming — the LUNGE does not" {
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    g.debugSwing(0);
    const hpBefore = g.vit.hp;
    const HEAVIES: u32 = 4;
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
        try std.testing.expectEqual(State.wind, g.state);
    }
    try std.testing.expectApproxEqAbs(hpBefore - @as(f32, HEAVIES) * heromod.ATK_HEAVY_HIT.dmg, g.vit.hp, 0.01);
    try std.testing.expectEqual(@as(u32, HEAVIES), g.hits);

    var q = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    q.debugSwing(1);
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

test "THERE IS NOTHING ON HIS BACK — the boards answer for the BLOW'S bearing, not for what he is squared up to" {
    var w = Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    w.covered = w.guardUp();
    try std.testing.expect(w.covered);
    const c = w.centerWorld();
    const swing = struct {
        fn at(from: rl.Vector3, to: rl.Vector3) foe.Blade {
            return .{ .active = true, .r = 0.5, .a = from, .b = to, .a0 = from, .b0 = to, .hit = heromod.ATK_HEAVY_HIT };
        }
    }.at;
    try std.testing.expect(w.shielded(swing(v3(0, c.y, 1.4), c)));
    const back = swing(v3(0, c.y, -1.4), c);
    try std.testing.expect(!w.shielded(back));
    w.tryHit(back);
    try std.testing.expectEqual(@as(u32, 1), w.hits);
    try std.testing.expect(w.staggered());
    try std.testing.expectApproxEqAbs(w.stam.max, w.stam.cur, 1e-5);
}

test "A SHAFT THE BOARDS ATE IS SPENT — it does not fly on into whatever stood behind him" {
    var w = [_]Warrior{Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3)};
    w[0].covered = w[0].guardUp();
    const c = w[0].centerWorld();
    const shaft = foe.Blade{
        .active = true,
        .pierce = true,
        .r = 0.16,
        .a = v3(0, c.y, 1.4),
        .b = c,
        .a0 = v3(0, c.y, 1.4),
        .b0 = c,
        .hit = .{ .dmg = 9 },
    };
    try std.testing.expect(foe.pierceGroup(&w, shaft));
    try std.testing.expectEqual(@as(u32, 0), w[0].hits);
    try std.testing.expectEqual(@as(u32, 1), w[0].blocksTaken());
    try std.testing.expect(w[0].stam.cur < w[0].stam.max);
}

test "a shieldman with his boards down takes a blow like anything else" {
    var w = Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    w.state = .recover;
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
    try std.testing.expectApproxEqAbs(w.stam.max, w.stam.cur, 1e-5);
}

/// Drive one whole stroke on the real clock and hand back what it did: whether it reached a hero standing `at`
/// metres dead ahead, the tip's furthest reach, the height at the top of the tell, the lowest the tip went, and
/// the SECTOR its tip swept (degrees off his facing, least to most). EVERY hurt-shape test below measures through here, which is the ogre's law (`clubLowWorld`).
const Swung = struct {
    hit: bool,
    maxD: f32,
    apex: f32,
    lowY: f32,
    /// Where the tip sits at the END of the tell, in his own frame: how far OUT TO THE SIDE, and how far up. A raised weapon is not the only readable tell — a horizontal's is entirely lateral.
    windLat: f32 = 0,
    windY: f32 = 0,
};
fn swung(role: Role, mv: usize, stroke: u8, at: f32) Swung {
    return swungAt(role, mv, stroke, v3(0, 0, at));
}
fn swungAt(role: Role, mv: usize, stroke: u8, hero: rl.Vector3) Swung {
    var w = Warrior.spawnAs(role, mathx.zero3, 0, 1.0, 0.3);
    w.atk = mv;
    const a = w.move();
    var apex: f32 = 0;
    w.state = .wind;
    var t: f32 = 0;
    while (t < a.windDur) : (t += 1.0 / 60.0) {
        w.t = t;
        w.setWind(mathx.smoothstep(0, a.windDur * 0.88, t));
        w.pose();
        apex = @max(apex, w.weaponSeg()[1].y);
    }
    const cocked = w.weaponSeg()[1];
    w.enter(.swing);
    w.stroke = stroke;
    var out = Swung{
        .hit = false,
        .maxD = 0,
        .apex = apex,
        .lowY = 99,
        .windLat = cocked.x,
        .windY = cocked.y,
    };
    t = 0;
    while (t < a.swingDur) : (t += 1.0 / 60.0) {
        w.t = t;
        w.setSwing(foe.swingCurve(t / a.swingDur));
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
    // THE BUG THIS FILE SHIPPED WITH: a mace whose head never left 0.6 m of his own chest, firing an annulus at 2.8 m. So the contract is now geometric — `reachOut` is a MEASUREMENT of the swing.
    for ([_]struct { r: Role, mv: usize }{
        .{ .r = .shieldman, .mv = 0 },
        .{ .r = .greatsword, .mv = 0 },
        .{ .r = .greatsword, .mv = 1 },
        .{ .r = .greatsword, .mv = 2 },
    }) |c| {
        var w = Warrior.spawnAs(c.r, mathx.zero3, 0, 1.0, 0.3);
        w.atk = c.mv;
        const a = w.move();
        const s = swung(c.r, c.mv, 0, 1.2);
        try std.testing.expectApproxEqAbs(a.reachOut * w.scale, s.maxD, 0.14);
        try std.testing.expect(s.hit);
        try std.testing.expect(swung(c.r, c.mv, 0, a.reachOut * w.scale).hit);
        try std.testing.expect(!swung(c.r, c.mv, 0, a.reachOut * w.scale + 1.1).hit);
        var q = Warrior.spawnAs(c.r, mathx.zero3, 0, 1.0, 0.3);
        q.debugSwing(c.mv);
        var t: f32 = 0;
        while (t < a.windDur - 1.0 / 60.0) : (t += 1.0 / 60.0) {
            try std.testing.expect(q.update(1.0 / 60.0, v3(0, 0, 1.0), 500.0, .{}) == null);
        }
    }
}

test "A TELL YOU CAN SEE: both kits are carried ABOVE THE SKULL at the top of the windup" {
    // Owner: "windup hard to see". It shipped with the mace head at 1.34 m — chest height on its own owner — so the cock did not break his silhouette at all. Judged against the SHOULDER line.
    const shoulder = REST[CHEST].y * SCALE;
    const mace = swung(.shieldman, 0, 0, 1.2);
    const slam = swung(.greatsword, 0, 0, 2.0);
    try std.testing.expect(mace.apex > shoulder * 1.30); // MEASURED 2.35 m: two thirds of a metre of daylight
    try std.testing.expect(slam.apex > shoulder * 1.60); // MEASURED 2.83 m — two metres of steel, stood on end
    try std.testing.expect(slam.apex > mace.apex);
}

test "NO STROKE PLOUGHS THE TURF BESIDE HIM, and the slam's point really does reach the earth" {
    // A weapon held radial to the arm through the bottom of an arc goes UNDER the ground — this measured
    // 0.44 m beneath it, next to his own boot, which is why `swingTilt` drives the attitude instead.
    try std.testing.expect(swung(.shieldman, 0, 0, 1.2).lowY > 0.35);
    try std.testing.expect(swung(.greatsword, 1, 0, 2.0).lowY > 0.35);
    // The horizontal is held LEVEL, so its floor is the highest of the three and its ceiling is low.
    try std.testing.expect(swung(.greatsword, 2, 0, 2.0).lowY > 0.60);
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.3);
    g.debugSwing(0);
    var t: f32 = 0;
    var crashed = false;
    while (t < SLAM.windDur + SLAM.swingDur and !crashed) : (t += 1.0 / 60.0) {
        _ = g.update(1.0 / 60.0, v3(0, 0, 2.2), 500.0, .{});
        crashed = g.crashed;
    }
    try std.testing.expect(crashed);
}

test "the stroke latches, so one swing lands once — and a COMBO gets one landing per stroke" {
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    g.debugSwing(0);
    const hero = v3(0, 0, 2.0);
    var lands: u32 = 0;
    var t: f32 = 0;
    while (t < SLAM.windDur + SLAM.swingDur + 0.1) : (t += 1.0 / 60.0) {
        if (g.update(1.0 / 60.0, hero, 500.0, .{}) != null) lands += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), lands);
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
    m.facing = 0;
    m.debugSwing(0);
    m.enter(.swing);
    var k: f32 = 0;
    while (k <= 1.0) : (k += 1.0 / 90.0) m.flyStroke(mathx.minF(k, 1.0), 500.0);
    m.flyStroke(1.0, 500.0);
    try std.testing.expectApproxEqAbs(MACE.step * m.scale, m.pos.z, 0.02);
    try std.testing.expectApproxEqAbs(@as(f32, 0), m.hop, 1e-4);
}

test "EVERY STROKE'S COMMITTED TRAVEL STARTS AT ZERO, whichever stroke of the combo it is" {
    // `flyStroke` moves him by `want - leapDone`, so a stroke that inherits its predecessor's total walks
    // BACKWARD out of the gate. Zeroed on entering `.wind` instead, only stroke 0 was ever safe.
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    g.debugSwing(1);
    g.enter(.swing);
    var k: f32 = 0;
    while (k <= 1.0) : (k += 1.0 / 90.0) g.flyStroke(mathx.minF(k, 1.0), 500.0);
    try std.testing.expect(g.leapDone > 0);
    g.stroke = 1;
    g.enter(.swing);
    try std.testing.expectApproxEqAbs(@as(f32, 0), g.leapDone, 1e-6);
    try std.testing.expectEqual(@as(u8, 1), g.stroke);
}

test "ROOTED, THE GREATSWORD SLAMS RATHER THAN LUNGING — and never off cooldown" {
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    g.root.grab();
    const at = v3(0, 0, triggerR(LUNGE, g.scale) - 0.2);
    var t: f32 = 0;
    while (t < combat.ROOT_HOLD * 0.9) : (t += 1.0 / 60.0) {
        _ = g.update(1.0 / 60.0, at, 500.0, .{});
        try std.testing.expect(!g.airborne());
        try std.testing.expect(g.hop <= 0.0001);
        if (g.state == .wind or g.state == .swing) try std.testing.expect(g.atk == 0 and g.cds[0] <= 0);
    }
    g.root.release();
    var left = false;
    t = 0;
    while (t < 4.0) : (t += 1.0 / 60.0) {
        _ = g.update(1.0 / 60.0, at, 500.0, .{});
        if (g.airborne()) left = true;
    }
    try std.testing.expect(left);
}

test "a rooted berserker never dashes, and a rooted hatchling never pounces" {
    const koboldmod = @import("kobold.zig");
    var z = koboldmod.Kobold.spawnAs(.berserker, mathx.zero3, 0, 1.0, 0.4);
    z.root.grab();
    var t: f32 = 0;
    while (t < combat.ROOT_HOLD * 0.9) : (t += 1.0 / 60.0) {
        _ = z.update(1.0 / 60.0, v3(0, 0, 5.0), 500.0, .{});
        try std.testing.expect(!z.airborne());
    }

    const broodmod = @import("brood.zig");
    var b = broodmod.Spider.spawnAs(.broodling, mathx.zero3, 0, 1.0, 0.4);
    b.root.grab();
    t = 0;
    while (t < combat.ROOT_HOLD * 0.9) : (t += 1.0 / 60.0) {
        _ = b.update(1.0 / 60.0, v3(0, 0, 3.0), 500.0, .{});
        try std.testing.expect(!b.airborne());
    }
}

test "THE LEAP TRAVELS EXACTLY ITS OWN DISTANCE, and comes back to earth" {
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    g.facing = 0;
    g.debugSwing(1);
    g.enter(.swing);
    var peak: f32 = 0;
    var k: f32 = 0;
    while (k <= 1.0) : (k += 1.0 / 90.0) {
        g.flyStroke(mathx.minF(k, 1.0), 500.0);
        peak = @max(peak, g.hop);
    }
    g.flyStroke(1.0, 500.0);
    try std.testing.expectApproxEqAbs(LUNGE.lunge * g.scale, g.pos.z, 0.02);
    try std.testing.expect(peak > LUNGE.hop * g.scale * 0.9);
    try std.testing.expectApproxEqAbs(@as(f32, 0), g.hop, 1e-4);
    g.hop = LUNGE.hop * g.scale;
    try std.testing.expect(g.airborne());
    g.hop = 0;
    try std.testing.expect(!g.airborne());
}

test "MELEE SKELETONS RUN THE GAP DOWN, and walk the last of it in" {
    for ([_]Role{ .shieldman, .greatsword }) |r| {
        var w = Warrior.spawnAs(r, mathx.zero3, 0, 1.0, 0.3);
        const walk = WALK_SPEED * spec(r).speed;
        try std.testing.expect(w.approachSpeed(AGGRO_R) > walk * 1.5);
        try std.testing.expectApproxEqAbs(walk, w.approachSpeed(w.walkInR() - 0.01), 1e-4);
        try std.testing.expectApproxEqAbs(walk, w.approachSpeed(0), 1e-4);
        try std.testing.expect(w.walkInR() > w.longestTrigger());
        try std.testing.expect(w.approachSpeed(AGGRO_R) < heromod.RUN_SPEED);
        w.homing = true;
        try std.testing.expectApproxEqAbs(walk, w.approachSpeed(AGGRO_R), 1e-4);
    }
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.3);
    g.speedS = WALK_SPEED * spec(.greatsword).speed;
    try std.testing.expectApproxEqAbs(@as(f32, 0), g.runBlend(), 1e-4);
    g.speedS = RUN_SPEED * spec(.greatsword).speed;
    try std.testing.expectApproxEqAbs(@as(f32, 1), g.runBlend(), 1e-4);
}

fn ribbonSamples(w: *const Warrior) usize {
    var n: usize = 0;
    for (w.trail.s) |s| {
        if (s.age < TRAIL_LIFE) n += 1;
    }
    return n;
}

test "THE LEAP IS FELT ONCE: one launch flag per lunge, and only the lunge raises it" {
    var g = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    g.debugSwing(1);
    var launches: u32 = 0;
    var t: f32 = 0;
    while (t < LUNGE.windDur + LUNGE.swingDur * 2 + LUNGE.chainWind + 0.2) : (t += 1.0 / 60.0) {
        _ = g.update(1.0 / 60.0, v3(0, 0, LUNGE.lunge * g.scale + 1.4), 500.0, .{});
        if (g.leapt) launches += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), launches);
    try std.testing.expect(ribbonSamples(&g) > 0);
    var m = Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.3);
    m.debugSwing(0);
    t = 0;
    while (t < MACE.windDur + MACE.swingDur + 0.1) : (t += 1.0 / 60.0) {
        _ = m.update(1.0 / 60.0, v3(0, 0, 1.0), 500.0, .{});
        try std.testing.expect(!m.leapt);
    }
    try std.testing.expectEqual(@as(usize, 0), ribbonSamples(&m));
    var s = Warrior.spawnAs(.greatsword, mathx.zero3, 0, 1.0, 0.4);
    s.debugSwing(0);
    t = 0;
    while (t < SLAM.windDur + SLAM.swingDur + 0.1) : (t += 1.0 / 60.0) {
        _ = s.update(1.0 / 60.0, v3(0, 0, 2.2), 500.0, .{});
    }
    try std.testing.expectEqual(@as(usize, 0), ribbonSamples(&s));
}

test "THE HURT SPHERE IS ON THE BODY, AND IT KNEELS WHEN HE DOES" {
    var w = Warrior.spawnAs(.shieldman, mathx.zero3, 0, 1.0, 0.4);
    // `rest` is the bare 1.8 m skeleton; the rig is drawn through `SCALE`, so the bar has to be scaled to meet it.
    const hip = w.rest[heromod.ROOT].y * w.scale;
    const skull = w.rest[SKULL].y * w.scale;
    const r = w.hurtRadius();

    // Standing: the sphere has to REACH the pelvis and not overshoot the skull by its own radius — a centre at
    // 0.95*H put its floor at 1.29 m, above the hips, and half of it in the air over his head.
    const up = w.centerWorld().y - w.pos.y;
    try std.testing.expect(up - r <= hip);
    try std.testing.expect(up + r >= skull);
    try std.testing.expect(up < skull);

    // …and kneeling it comes DOWN with him. `KNEEL_SINK` drops the pelvis 0.315*H; a sphere that stayed put left
    // a broken shieldman standing in a hitbox he was no longer inside.
    w.debugBreak();
    var f: i32 = 0;
    while (f < 40) : (f += 1) _ = w.update(1.0 / 60.0, mathx.ground(0, 40), 200, .{});
    const down = w.centerWorld().y - w.pos.y;
    std.debug.print("\n  shieldman hurt sphere: standing {d:.2} m, kneeling {d:.2} m (r {d:.2}, hips {d:.2}, skull {d:.2})\n", .{ up, down, r, hip, skull });
    try std.testing.expect(down < up - 0.25);
    try std.testing.expect(down > 0.2);
}

test "a skeleton burns and does not freeze, whatever is in its hands" {
    for ([_]Role{ .shieldman, .greatsword }) |r| {
        const w = Warrior.spawnAs(r, mathx.zero3, 0, 1.0, 0.2);
        try std.testing.expect(w.vit.res.at(.fire) < 0);
        try std.testing.expect(w.vit.res.at(.cold) > 0);
        try std.testing.expect(w.vit.res.at(.chaos) > 0);
    }
}

test "the kite profile is a kite: widest at the shoulders, a point at the bottom" {
    try std.testing.expect(kiteHalf(0.30) > kiteHalf(0.0));
    try std.testing.expectApproxEqAbs(SH_HALF, kiteHalf(0.30), 1e-4);
    var t: f32 = 0.30;
    var prev = kiteHalf(t);
    while (t <= 1.0) : (t += 0.02) {
        const w = kiteHalf(t);
        try std.testing.expect(w <= prev + 1e-5);
        prev = w;
    }
    try std.testing.expect(kiteHalf(1.0) < SH_HALF * 0.05);
    try std.testing.expect((SH_TOP + SH_BOT) > 0.55 * H);
}



test "NO ATTACK COMES OUT OF NOWHERE: every stroke of every moveset is visible first" {
    for (SPEC) |sp| {
        for (sp.moves) |a| {
            const first = a.windDur + a.swingDur * a.impactK;
            try std.testing.expect(first >= foe.TELL_MIN);
            if (a.strokes > 1) {
                const next = a.chainWind + a.swingDur * a.impactK;
                try std.testing.expect(next >= foe.TELL_MIN);
            }
        }
    }
}
