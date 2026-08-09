const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");
const heromod = @import("hero.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const scaleM = mathx.scaleM;
const mul = mathx.mul;
const mul3 = mathx.mul3;

const place = mathx.placeAt; // the shared joint placer — see mathx


const CHITIN = rgba(19, 20, 22, 255); // → ~(102,96,88): a cold near-black shell
const CHITIN_DK = rgba(11, 12, 14, 255);
const CHITIN_LT = rgba(30, 31, 33, 255);
const ABDO = rgba(22, 23, 24, 255);
const MARK = rgba(78, 58, 22, 255); // dull gold chevrons down the abdomen — lit, not luminous
const CLAW_H = rgba(74, 74, 66, 255); // → ~(195,176,143): HORN, and the first thing you should see
const CLAW_EDGE = rgba(110, 112, 104, 255);
const FANG = rgba(70, 70, 62, 255);
const EYE = rgba(226, 108, 40, 92); // the cluster, lit like an ember (low ALPHA drives the emissive, so
const EYE_HOT = rgba(255, 58, 30, 58);
const VENOM = rgba(42, 104, 18, 235); // → ~(150,205,80): sickly acid green
const VENOM_DK = rgba(26, 62, 12, 255);
const SAC_MEM = rgba(67, 93, 62, 220);
const SAC_EGG = rgba(48, 70, 38, 255);
const SAC_VEIN = rgba(26, 22, 16, 255);
const GORE = rgba(46, 9, 7, 235);

const B_CHITIN = rgba(42, 52, 54, 255);
const B_CHITIN_DK = rgba(24, 30, 32, 255);
const B_CHITIN_LT = rgba(58, 70, 70, 255);
const B_ABDO = rgba(50, 62, 52, 255);

const NP = 22;
const CEPHALO = 0; // fused head + thorax: the eight-eye cluster and the fangs.
const ABDOMEN = 1; // the egg-heavy bulb, hinged at the pedicel — it swells and pumps as she lays
const ARM_L = 2; // claw arm (shoulder pivot)
const ARM_R = 3;
const BLADE_L = 4;
const BLADE_R = 5;
const FEMUR_0 = 6; // 8 legs: L0..L3 then R0..R3, front to back
const TIBIA_0 = 14;
const NLEG = 4; // per side

// Rest joints in the cephalothorax frame (origin at the GROUND SEAT under her, +Y up, +Z forward).
const BODY_Y = 0.52;
const P_PEDICEL = v3(0, BODY_Y + 0.12, -0.28);
const P_SHOULDER = v3(0.23, BODY_Y + 0.15, 0.34);
const P_WRIST = v3(0.26, 0.00, 0.62); // in the ARM's frame, out along its length
const HIP_X = 0.32;
const HIP_Z0 = 0.30; // front hip…
const HIP_DZ = 0.23;

const FEMUR_OUT = 0.54;
const FEMUR_UP = 0.36;
const TIBIA_OUT = 0.40;
const TIBIA_DOWN = 0.94;

const HURT_R = 0.52; // hurt sphere (pre per-spider scale)
const BODY_R = 0.62; // ground footprint for collision
const BODY_CY = 0.56; // body centre height (camera focus + hurt sphere)
/// The reticle's seat in the CEPHALO part's own frame, whose origin sits on the ground under her — so the
/// body height, carried a little forward onto the eye cluster.
const LOCK_AT = v3(0, BODY_Y, 0.10);

const LEG_PHASE = [NLEG]f32{ 0.0, 0.5, 0.0, 0.5 };
const STEP_SWING = 26.0; // deg the femur sweeps fore/aft
const STEP_LIFT = 20.0;
const KNEE_REST = 96.0; // the standing knee angle (deg) — high and folded
// She ends on her BACK, so the femur drives the knee down THROUGH the body's frame (+, the step-lift's sign) and
// the tibia folds back the other way, arching the pair over the belly. Curling the femur the other way folds
// each leg flat to the trunk, which on an upturned body buries all eight feet. Retune against 112d, not a stand.
const CURL_FEMUR = 70.0;
const CURL_KNEE = -95.0;
const IDLE_BOB = 0.028; // a slow breathing rise/fall at rest

const TURN_RATE = 2.4; // rad/s — she is SLOW to come round, and that is a real opening
const TURN_RATE_B = 7.0;

const M_SCALE = 1.55;
const M_HP = 150.0;
const M_POISE = 34.0;
const M_STANCE = 58.0;
const M_SPEED = heromod.WALK_SPEED * 0.52; // SHE CANNOT MOVE QUICKLY (owner's rule)
const M_AGGRO = 22.0;
const M_SPIT_MIN = 4.6; // inside this she stops spitting and uses her mouth
const M_SPIT_MAX = 19.0;
const M_BITE_R = 2.3;
/// HOW FAR SHE WILL LEAVE HER EGGS.
const M_GUARD_R = 7.5;

/// SHE REARS, THE ABDOMEN PUMPS, THE EYES BURN — and she holds it (owner's call).
const SPIT_WINDUP = 1.05;
const SPIT_THROW = 0.16;
const SPIT_RECOVER = 0.52;
const SPIT_CD = 2.4;
const BITE_WINDUP = 0.40; // claws fly wide, fangs come up
const BITE_SNAP = 0.13;
const BITE_RECOVER = 0.50;
const BITE_CD = 1.1;
const LAY_DUR = 1.75; // squat, swell, drop — and she is wide open for all of it
const LAY_DROP = 0.72; // the fraction of the lay at which the sac actually leaves her
const LAY_CD = 6.5;
const LAY_BACK = 0.95; // how far behind the seat the sac lands (pre-scale)

/// HOW MANY UNHATCHED SACS SHE WILL KEEP STANDING.
pub const MAX_SACS: usize = 3;
/// …and what comes out of one: ONE (owner's call).
pub const PER_SAC: usize = 1;

/// BOTH AGES OF HER, because they are one creature at two ages (see the file header): chitin over a
/// body that makes and carries its own acid, hung about with silk that catches. See `frog.RESISTS` on
/// why fire is the only one of the four anything deals yet.
const RESISTS = combat.resists(.{ .fire = -25, .cold = 35, .chaos = 75 });
/// THE SPIT IS POISON, AND NOW IT MEANS IT (`combat.Status`): the glob deals almost nothing on arrival —
/// the poise is a caustic lump still rocking you — and what it really costs is `M_SPIT_BUILD` on the meter.
/// Her POOLS carry the same venom (`SPIT_BUILD_DPS`), because they are the same fluid.
pub const M_SPIT_HIT = combat.Hit{ .dmg = 2, .poise = 5 };
/// WHAT ONE GLOB PUTS ON THE METER — three of them proc, so a mother left to spit at range is a clock you
/// are running down whether or not you feel the hits.
pub const M_SPIT_BUILD: f32 = 36.0;
pub const M_BITE_HIT = combat.Hit{ .dmg = 19, .poise = 22, .stance = 7 };
/// HOW LONG BEFORE HER FANGS LAND THEY CAN STILL BE CAUGHT — the game's own number (`foe.PARRY_LEAD`), so a
/// player who learned the timing off a giant's club already knows this one. HER BITE AND NOTHING ELSE OF HERS
/// carries a window; see `Spider.toImpact` for why the spit, the lay and the whole broodling are out.
const PARRY_LEAD = foe.PARRY_LEAD;
/// The glob's flight, handed to the shared launcher (`archer.launchShaft`, kind `.venom`).
pub const SPIT_SPEED: f32 = 15.0;


/// A pool's full radius…
pub const ACID_R: f32 = 1.55;
/// …how fast it spreads to it (a splash, not a bloom)…
const ACID_SPREAD: f32 = 0.22;
/// …and how long it lies there before it has eaten itself out.
pub const ACID_LIFE: f32 = 7.5;
const ACID_THIN: f32 = 2.0;
/// THE FLOOR NO LONGER BURNS — IT POISONS. Buildup a second while he stands in it, continuous and scaled by
/// `dt` rather than pulsed: the meter is drawn every frame and a dose delivered in lumps reads as a stutter.
/// Sized so about two and a half seconds in a pool is a proc — a pool is a place you leave, not one you cross.
pub const ACID_BUILD: f32 = 40.0;
const POOL_CAP: usize = 12;

// THE BROODLING'S.
const B_SCALE = 0.72; // a shade bigger (owner's call) — still well under the mother's M_SCALE
const B_STAND = 1.22;
const B_HP = 18.0;
const B_POISE = 1.0;
const B_STANCE = 6.0;
const B_SPEED = heromod.RUN_SPEED * 0.95; // you can outrun it, but not while looking away
const B_AGGRO = 16.0;
/// How near where it HATCHED counts as back there — tighter than the tether's own `foe.LEASH_HOME_R` on
/// purpose (see `frog.HOME_R`), and named because a bare literal inside `decideBroodling` is where the
/// same question in four other files drifted to four different answers.
const B_HOME_R = 1.8;
const B_BITE_R = 1.05;
const B_LEAP_MIN = 2.4; // it pounces from this band and nowhere else
const B_LEAP_MAX = 5.4;
/// Its rear-and-claws-wide tell (`resolveBiteWind` already poses one) — it was 0.20 s, which with a 0.09 s
/// snap behind it is 17 frames from standing to bitten. Still the quickest thing in the game, but now over
/// `foe.TELL_MIN`, so the frame it opens up is a frame you can act on.
const B_BITE_WINDUP = 0.34;
const B_BITE_SNAP = 0.09;
const B_BITE_RECOVER = 0.26;
const B_BITE_CD = 0.75;
const B_LEAP_COIL = 0.30; // the crouch — short, but it IS there, and it is the counter
const B_LEAP_FLIGHT = 0.30;
const B_LEAP_LAND = 0.13;
const B_LEAP_APEX = 0.92;
const B_LEAP_CD = 1.9;
const B_LEAP_IMPACT_R = 1.25;
const B_LEAP_FRONT_DOT = 0.20;

pub const B_BITE_HIT = combat.Hit{ .dmg = 3, .poise = 4 };
pub const B_LEAP_HIT = combat.Hit{ .dmg = 5, .poise = 8 };

const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 7.5;
const DEATH_DUR = 1.05;
const DISS_DUR = 0.9;
/// …and the cloud. A spider dies FLAT — legs out, body low — so it comes off wider than it does tall.
const DISSOLVE = foe.Dissolve{ .rate = 34.0, .spread = 0.60, .rise = 0.40 };
const HERO_REACH = foe.HERO_REACH;

/// RUNES each is worth.
pub const M_RUNES: u32 = 240;
pub const B_RUNES: u32 = 25;

// THE SAC.
const SAC_HP = 18.0;
const SAC_R = 0.44; // the drawn radius…
/// …and a FATTER one to hit, deliberately.
const SAC_HURT_R = 0.62;
/// SECONDS OF VISIBLE SWELLING BEFORE IT SPLITS — long (owner's call), because the whole point of a sac is that it is a problem you can go and solve, and six seconds was not enough time to decide to.
pub const SAC_HATCH = 11.5;
const SAC_BURST_DUR = 0.55;
const SAC_PULSE_HZ = 1.6;
/// A SAC HAS NO POISE AND NO STANCE: it does not flinch, it bursts.
const SAC_UNFLINCHING: f32 = 1e9;
/// DRY SILK OVER A MEMBRANE — the one thing in her nest that really goes up, and the reason a scarce
/// fire arrow spent on a clutch is worth more than one spent on her.
const SAC_RESISTS = combat.resists(.{ .fire = -70, .chaos = 75 });

const FX_MAX = 26;
const Particle = foe.Particle;
const DUST = foe.DUST;
const MOTE = foe.MOTE;


/// The two ages of one animal.
pub const Role = enum { mother, broodling };

/// …and the run is written down once and pinned, because the shift is only sound while it holds.
const ROLE_KIND = [_]wf.FoeKind{ .brood_mother, .broodling };
comptime {
    if (ROLE_KIND.len != @typeInfo(Role).@"enum".fields.len) @compileError("brood: a Role with no foe kind");
    for (ROLE_KIND, 0..) |k, i| {
        if (@intFromEnum(k) != @intFromEnum(wf.FoeKind.brood_mother) + i) {
            @compileError("brood: wf.FoeKind." ++ @tagName(k) ++ " is not in the brood's contiguous run");
        }
    }
}

pub fn roleOf(k: wf.FoeKind) ?Role {
    const lo = @intFromEnum(wf.FoeKind.brood_mother);
    const i = @intFromEnum(k);
    if (i < lo or i >= lo + @typeInfo(Role).@"enum".fields.len) return null;
    return @enumFromInt(i - lo);
}
pub fn kindOf(r: Role) wf.FoeKind {
    return @enumFromInt(@intFromEnum(wf.FoeKind.brood_mother) + @intFromEnum(r));
}

const Spec = struct {
    scale: f32,
    hp: f32,
    poise: f32,
    stance: f32,
    speed: f32,
    aggro: f32,
    turn: f32,
    runes: u32,
};

/// THE WIDEST NOTICE RING IN THE BROOD, off the table itself — read by `game.markSight` to work out how
/// far out a look at the hero is worth taking at all.
pub const AGGRO_R = blk: {
    var w: f32 = 0;
    for (@typeInfo(Role).@"enum".fields) |f| w = @max(w, spec(@enumFromInt(f.value)).aggro);
    break :blk w;
};

fn spec(r: Role) Spec {
    return switch (r) {
        .mother => .{ .scale = M_SCALE, .hp = M_HP, .poise = M_POISE, .stance = M_STANCE, .speed = M_SPEED, .aggro = M_AGGRO, .turn = TURN_RATE, .runes = M_RUNES },
        .broodling => .{ .scale = B_SCALE, .hp = B_HP, .poise = B_POISE, .stance = B_STANCE, .speed = B_SPEED, .aggro = B_AGGRO, .turn = TURN_RATE_B, .runes = B_RUNES },
    };
}


const MChoice = enum { hold, close, spit, bite, lay };
fn classifyMother(dist: f32, tether: f32, spitReady: bool, biteReady: bool, layWanted: bool) MChoice {
    if (dist > M_AGGRO) return .hold;
    if (dist <= M_BITE_R) return if (biteReady) .bite else .hold;
    if (layWanted and dist > M_BITE_R * 1.6) return .lay;
    if (dist <= M_SPIT_MAX and dist >= M_SPIT_MIN) return if (spitReady) .spit else .hold;
    if (dist < M_SPIT_MIN) return .close; // between her spit and her teeth — walk in and use them
    if (tether >= M_GUARD_R) return .hold;
    return .close;
}

const BChoice = enum { idle, chase, leap, bite };
fn classifyBroodling(dist: f32, leapReady: bool, biteReady: bool) BChoice {
    if (dist > B_AGGRO) return .idle;
    if (dist <= B_BITE_R) return if (biteReady) .bite else .idle;
    if (leapReady and dist >= B_LEAP_MIN and dist <= B_LEAP_MAX) return .leap;
    return .chase;
}

const State = enum { idle, walk, windup, strike, recover, lay, leap, stunlight, stunheavy, dead };


/// One age's colours and proportions.
const Skin = struct {
    chitin: rl.Color,
    dark: rl.Color,
    light: rl.Color,
    abdo: rl.Color,
    mark: rl.Color,
    abdoR: f32, // she is EGG-HEAVY; a hatchling is not
    clawLen: f32,
    legR: f32,
    /// HOW LONG THE WALKING LEGS ARE, against the authored length.
    legScale: f32,
    /// …and how far the abdomen hangs BELOW the pedicel, so hers drags on the ground behind her.
    abdoDrop: f32,
    armLift: f32,
    /// Ground covered per full leg cycle.
    stride: f32,
    marks: bool,
    matron: bool,
    fur: bool,
    seed: u64,
};

const MOTHER_SKIN = Skin{ .chitin = CHITIN, .dark = CHITIN_DK, .light = CHITIN_LT, .abdo = ABDO, .mark = MARK, .abdoR = 0.60, .clawLen = 0.62, .legR = 0.070, .legScale = 0.68, .abdoDrop = 0.26, .armLift = 6.0, .stride = 0.72, .marks = true, .matron = true, .fur = true, .seed = 20719 };
const BROOD_SKIN = Skin{ .chitin = B_CHITIN, .dark = B_CHITIN_DK, .light = B_CHITIN_LT, .abdo = B_ABDO, .mark = B_CHITIN_LT, .abdoR = 0.34, .clawLen = 0.40, .legR = 0.095, .legScale = B_STAND, .abdoDrop = 0.0, .armLift = 24.0, .stride = 1.55, .marks = false, .matron = false, .fur = true, .seed = 51413 };

fn skinOf(r: Role) Skin {
    return switch (r) {
        .mother => MOTHER_SKIN,
        .broodling => BROOD_SKIN,
    };
}

/// The clearance a standing foot keeps under the hip, at the authored leg length.
const FOOT_CLEAR = 0.07;
const DRAG_CLEAR = 0.03;
fn hipHeight(sk: Skin) f32 {
    return (TIBIA_DOWN - FEMUR_UP) * sk.legScale + FOOT_CLEAR;
}
/// …and how far the whole animal therefore rides below where the meshes were authored.
fn rideDropSkin(sk: Skin) f32 {
    return (P_SHOULDER.y - 0.02) - hipHeight(sk);
}
fn rideDrop(r: Role) f32 {
    return rideDropSkin(skinOf(r));
}
/// Where a flipped corpse's back finds the ground (author units): the standing crown, mirrored about the BODY_Y roll hinge, less the ride the legs no longer provide.
fn deadRest(sk: Skin) f32 {
    const crown: f32 = if (sk.matron) 1.05 else 1.02; // a hatchling rests on its slung abdomen, higher than its carapace
    return rideDropSkin(sk) - (2.0 * BODY_Y - crown);
}

/// THE ABDOMEN'S HALF-HEIGHT and where its centre has to sit, both derived.
fn abdoHalfY(sk: Skin) f32 {
    return sk.abdoR * (if (sk.matron) @as(f32, 0.96) else 0.86);
}
fn abdoCentreY(sk: Skin) f32 {
    if (!sk.matron) return -0.02; // a hatchling's is slung under it, clear of the ground — unchanged
    return abdoHalfY(sk) + DRAG_CLEAR - (P_PEDICEL.y - rideDropSkin(sk));
}

const FLAIL_HZ = 2.3;
const FLAIL_SPREAD = 15.0; // deg of yaw…
const FLAIL_LIFT = 11.0;

pub const Model = struct {
    mesh: [2][NP]rl.Mesh, // [role][part]
    eyes: [2][2]rl.Mesh, // [role][burning]
    sac: rl.Mesh,
    wreck: rl.Mesh,
    pool: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("brood material");
        mat.shader = shader;
        var m = Model{
            .mesh = undefined,
            .eyes = undefined,
            .sac = sacMesh(false),
            .wreck = sacMesh(true),
            .pool = poolMesh(),
            .mat = mat,
        };
        for (0..2) |i| {
            const sk = skinOf(@enumFromInt(i));
            m.mesh[i] = buildMeshes(sk);
            m.eyes[i] = [2]rl.Mesh{ eyeMesh(sk, EYE), eyeMesh(sk, EYE_HOT) };
        }
        return m;
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, role: Role, xf: *const [NP]rl.Matrix, hot: bool) void {
        const ri = @intFromEnum(role);
        for (0..NP) |i| rl.drawMesh(self.mesh[ri][i], self.mat, xf[i]);
        rl.drawMesh(self.eyes[ri][@intFromBool(hot)], self.mat, xf[CEPHALO]);
    }
};

fn buildMeshes(sk: Skin) [NP]rl.Mesh {
    var mesh: [NP]rl.Mesh = undefined;
    mesh[CEPHALO] = cephaloMesh(sk);
    mesh[ABDOMEN] = abdomenMesh(sk);
    mesh[ARM_L] = armMesh(sk, 1.0);
    mesh[ARM_R] = armMesh(sk, -1.0);
    mesh[BLADE_L] = bladeMesh(sk, 1.0);
    mesh[BLADE_R] = bladeMesh(sk, -1.0);
    for (0..NLEG) |i| {
        mesh[FEMUR_0 + i] = femurMesh(sk, 1.0, i);
        mesh[FEMUR_0 + NLEG + i] = femurMesh(sk, -1.0, i);
        mesh[TIBIA_0 + i] = tibiaMesh(sk, 1.0, i);
        mesh[TIBIA_0 + NLEG + i] = tibiaMesh(sk, -1.0, i);
    }
    return mesh;
}

fn furOver(b: *Builder, rng: *mathx.Rng, c: rl.Vector3, r: rl.Vector3, n: u32, len: f32, col: rl.Color) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const a = rng.angle();
        const e = rng.range(-1.0, 1.0);
        const s = @sqrt(mathx.maxF(0, 1.0 - e * e));
        const d = v3(mathx.cosf(a) * s, e, mathx.sinf(a) * s);
        const p = v3(c.x + d.x * r.x, c.y + d.y * r.y, c.z + d.z * r.z);
        const l = len * rng.range(0.55, 1.45);
        b.addCapsule(
            v3(p.x - d.x * l * 0.3, p.y - d.y * l * 0.3, p.z - d.z * l * 0.3), // rooted UNDER the skin
            v3(p.x + d.x * l + rng.signed() * l * 0.4, p.y + d.y * l + rng.range(-0.1, 0.5) * l, p.z + d.z * l + rng.signed() * l * 0.4),
            rng.range(0.010, 0.019),
            0.002,
            4,
            col,
        );
    }
}

fn cephaloMesh(sk: Skin) rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    var rng = mathx.Rng.init(sk.seed);
    if (sk.matron) {
        const hz = 0.46;
        b.addBlob(v3(0, BODY_Y + 0.10, hz), v3(0.44, 0.42, 0.42), 11, 15, sk.chitin);
        b.addBlob(v3(0, BODY_Y - 0.02, hz - 0.30), v3(0.34, 0.28, 0.28), 8, 11, sk.dark); // the neck into the trunk
        b.addBlob(v3(0, BODY_Y - 0.06, 0.02), v3(0.34, 0.24, 0.34), 8, 11, sk.dark); // the low trunk the legs hang off
        for ([_]f32{ -1, 1 }) |sgn| {
            var p = v3(sgn * 0.20, BODY_Y - 0.16, hz + 0.16);
            var seg: u32 = 0;
            while (seg < 4) : (seg += 1) {
                const nx = v3(p.x + sgn * rng.range(0.01, 0.06), p.y - rng.range(0.10, 0.15), p.z + rng.range(-0.04, 0.03));
                const rr = 0.075 - @as(f32, @floatFromInt(seg)) * 0.012;
                b.addCapsule(p, nx, rr, rr * 0.86, 8, if (seg % 2 == 0) sk.chitin else sk.light);
                p = nx;
            }
            b.addCapsule(p, v3(p.x + sgn * 0.05, p.y - 0.12, p.z + 0.05), 0.036, 0.008, 6, FANG); // the fang on the end
        }
        if (sk.fur) {
            furOver(&b, &rng, v3(0, BODY_Y + 0.10, hz), v3(0.44, 0.42, 0.42), 22, 0.13, sk.dark);
            furOver(&b, &rng, v3(0, BODY_Y - 0.06, 0.02), v3(0.34, 0.24, 0.34), 14, 0.12, sk.dark);
        }
        return b.toMesh();
    }
    b.addBlob(v3(0, BODY_Y + 0.02, 0.02), v3(0.44, 0.26, 0.50), 9, 14, sk.chitin); // the carapace
    b.addBlob(v3(0, BODY_Y - 0.10, 0.06), v3(0.38, 0.16, 0.42), 7, 12, sk.dark);
    b.addBlob(v3(0, BODY_Y + 0.02, 0.40), v3(0.30, 0.20, 0.22), 7, 12, sk.chitin);
    b.addBlob(v3(0, BODY_Y - 0.12, 0.44), v3(0.24, 0.15, 0.20), 6, 10, sk.dark); // the chelicerae block
    b.addBlob(v3(0, BODY_Y + 0.20, 0.02), v3(0.09, 0.05, 0.40), 6, 8, sk.light);
    var i: u32 = 0;
    while (i < 9) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.16, 0.36);
        b.addBlob(
            v3(mathx.cosf(a) * rr, BODY_Y + rng.range(0.10, 0.20), 0.02 + mathx.sinf(a) * rr * 1.1),
            v3(rng.range(0.05, 0.09), rng.range(0.015, 0.03), rng.range(0.05, 0.09)),
            5,
            8,
            if (rng.float() < 0.5) sk.dark else sk.light,
        );
    }
    // THE FANGS, folded back under the head — bone-pale, so the bite reads even in shadow.
    for ([_]f32{ -1, 1 }) |sgn| {
        b.addCapsule(v3(sgn * 0.10, BODY_Y - 0.18, 0.50), v3(sgn * 0.13, BODY_Y - 0.36, 0.40), 0.048, 0.012, 7, FANG);
    }
    if (sk.fur) furOver(&b, &rng, v3(0, BODY_Y + 0.02, 0.02), v3(0.44, 0.26, 0.50), 12, 0.09, sk.dark);
    return b.toMesh();
}

fn eyeMesh(sk: Skin, col: rl.Color) rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    if (sk.matron) {
        var rng = mathx.Rng.init(sk.seed +% 313);
        var i: u32 = 0;
        while (i < 13) : (i += 1) {
            const a = rng.angle();
            const rr = rng.range(0.0, 0.9);
            // …on the forward face of a 0.44 ball centred at (0, BODY_Y+0.10, 0.46).
            const x = mathx.cosf(a) * rr * 0.40;
            const y = mathx.sinf(a) * rr * 0.36;
            const z = @sqrt(mathx.maxF(0.02, 1.0 - rr * rr)) * 0.41;
            const s = rng.range(0.026, 0.062);
            b.addBlob(v3(x, BODY_Y + 0.12 + y, 0.46 + z), v3(s, s, s * 0.8), 5, 8, col);
        }
        return b.toMesh();
    }
    const row = [_][3]f32{
        .{ 0.055, 0.055, 0.052 }, .{ 0.145, 0.030, 0.046 },
        .{ 0.055, -0.020, 0.040 }, .{ 0.160, -0.045, 0.034 },
    };
    for ([_]f32{ -1, 1 }) |sgn| {
        for (row) |e| {
            b.addBlob(v3(sgn * e[0], BODY_Y + 0.14 + e[1], 0.52), v3(e[2], e[2], e[2] * 0.7), 5, 8, col);
        }
    }
    return b.toMesh();
}

fn abdomenMesh(sk: Skin) rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    const r = sk.abdoR;
    const dy = abdoCentreY(sk);
    // A near-SPHERE on her (owner's drawing), where a hatchling keeps the longer teardrop.
    const ax: rl.Vector3 = if (sk.matron) v3(r * 0.98, abdoHalfY(sk), r * 0.98) else v3(r * 0.92, abdoHalfY(sk), r);
    b.addBlob(v3(0, dy, -r * 0.72), ax, 12, 16, sk.abdo);
    if (sk.fur) {
        var frng = mathx.Rng.init(sk.seed +% 5501);
        furOver(&b, &frng, v3(0, dy, -r * 0.72), ax, if (sk.matron) 46 else 16, r * 0.20, sk.dark);
    }
    b.addBlob(v3(0, dy * 0.5, -r * 0.18), v3(r * 0.42, r * 0.44, r * 0.40), 7, 10, sk.dark); // the waist into it
    if (sk.marks) {
        var rng = mathx.Rng.init(sk.seed +% 977);
        var i: u32 = 0;
        while (i < 5) : (i += 1) {
            const t = 0.18 + @as(f32, @floatFromInt(i)) * 0.17;
            const w = (0.30 - 0.04 * @as(f32, @floatFromInt(i))) * r + rng.range(-0.02, 0.02);
            const y = dy + 0.55 * abdoHalfY(sk) + rng.range(-0.03, 0.03) * r;
            b.addBlob(v3(rng.range(-0.03, 0.03), y, -r * 1.5 * t), v3(w, 0.035 * r, 0.07 * r), 5, 8, sk.mark);
        }
    }
    b.addBlob(v3(0, dy - 0.20 * abdoHalfY(sk), -r * 1.42), v3(0.10 * r, 0.09 * r, 0.10 * r), 5, 8, sk.dark);
    b.addBlob(v3(0, dy - 0.62 * abdoHalfY(sk), -r * 0.70), v3(r * 0.62, r * 0.24, r * 0.68), 7, 10, sk.light);
    return b.toMesh();
}

/// THE CLAW ARM — a thick horn limb held out and forward, authored from the shoulder along +X·sgn.
fn armMesh(sk: Skin, sgn: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide);
    if (sk.matron) {
        const el = v3(sgn * 0.62, 0.74, 0.10);
        b.addCapsule(v3(0, 0, 0), el, 0.075, 0.055, 8, sk.chitin);
        b.addCapsule(el, v3(sgn * P_WRIST.x, P_WRIST.y, P_WRIST.z), 0.055, 0.044, 8, sk.chitin);
        b.addBlob(el, v3(0.085, 0.085, 0.085), 6, 9, sk.light); // the angular knuckle at the top of the arch
        if (sk.fur) {
            var rng = mathx.Rng.init(sk.seed +% 811 +% (if (sgn > 0) @as(u64, 3) else 9));
            var i: u32 = 0;
            while (i < 7) : (i += 1) {
                const u = rng.range(0.1, 0.9);
                const p = mathx.lerpV(mathx.zero3, el, u);
                b.addCapsule(p, v3(p.x + rng.signed() * 0.10, p.y + rng.range(0.03, 0.13), p.z + rng.signed() * 0.10), 0.014, 0.002, 4, sk.dark);
            }
        }
        return b.toMesh();
    }
    b.addCapsule(v3(0, 0, 0), v3(sgn * 0.26, 0.02, 0.24), 0.115, 0.092, 9, sk.chitin);
    b.addCapsule(v3(sgn * 0.26, 0.02, 0.24), v3(sgn * P_WRIST.x, P_WRIST.y, P_WRIST.z), 0.092, 0.074, 9, sk.chitin);
    b.addBlob(v3(sgn * 0.26, 0.02, 0.24), v3(0.10, 0.085, 0.10), 6, 9, sk.light); // the elbow knuckle
    return b.toMesh();
}

fn bladeSeg(b: *Builder, p0: rl.Vector3, p1: rl.Vector3, h: f32, t: f32, col: rl.Color) void {
    const d = mathx.subV(p1, p0);
    const len = mathx.lenV(d);
    if (len < 1e-4) return;
    const dir = mathx.scaleV(d, 1.0 / len);
    var side = v3(-dir.z, 0, dir.x);
    const sl = mathx.lenV(side);
    side = if (sl < 1e-4) v3(1, 0, 0) else mathx.scaleV(side, 1.0 / sl);
    b.addBox(
        mathx.lerpV(p0, p1, 0.5),
        mathx.scaleV(side, t * 0.5), // thin ACROSS…
        v3(0, h * 0.5, 0),
        mathx.scaleV(dir, len * 0.5),
        col,
    );
}

fn bladeMesh(sk: Skin, sgn: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.hide); // horn is not steel: the flat stays matt, and only the honed edge below catches light
    const L = sk.clawLen;
    const p = [_]rl.Vector3{
        v3(0, 0, 0),
        v3(sgn * -0.02 * L, 0.02 * L, 0.26 * L),
        v3(sgn * -0.10 * L, 0.03 * L, 0.50 * L),
        v3(sgn * -0.24 * L, 0.00 * L, 0.68 * L),
        v3(sgn * -0.40 * L, -0.05 * L, 0.78 * L),
    };
    const depth = [_]f32{ 0.17, 0.16, 0.12, 0.07 };
    for (0..4) |i| {
        bladeSeg(&b, p[i], p[i + 1], depth[i] * L, 0.055 * L, CLAW_H);
    }
    b.addBlob(v3(0, 0, 0), v3(0.09 * L, 0.085 * L, 0.09 * L), 6, 9, sk.light);
    b.setMat(.steel);
    for (0..4) |i| {
        const e0 = v3(p[i].x, p[i].y - depth[i] * 0.42 * L, p[i].z);
        const e1 = v3(p[i + 1].x, p[i + 1].y - depth[i] * 0.42 * L, p[i + 1].z);
        b.addCapsule(e0, e1, 0.022 * L, 0.016 * L, 5, CLAW_EDGE);
    }
    b.setMat(.hide);
    var rng = mathx.Rng.init(sk.seed +% 4441);
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        const u = 0.16 + @as(f32, @floatFromInt(i)) * 0.13 + rng.range(-0.02, 0.02);
        const at = mathx.lerpV(p[0], p[4], u);
        const len = rng.range(0.04, 0.075) * L * (if (rng.float() < 0.18) @as(f32, 0.4) else @as(f32, 1.0));
        b.addCapsule(
            v3(at.x, at.y - 0.055 * L, at.z),
            v3(at.x + sgn * -0.2 * len, at.y - (0.055 * L + len), at.z + 0.35 * len),
            0.018 * L,
            0.005,
            5,
            CLAW_EDGE,
        );
    }
    return b.toMesh();
}

/// A leg's upper segment, authored from the hip going OUT and UP to the knee.
fn femurMesh(sk: Skin, sgn: f32, i: usize) rl.Mesh {
    var rng = mathx.Rng.init(sk.seed +% @as(u64, @intCast(i)) *% 131 +% (if (sgn > 0) @as(u64, 7) else 19));
    var b = Builder.init();
    b.setMat(.hide);
    const out = FEMUR_OUT * sk.legScale * rng.range(0.93, 1.08);
    const up = FEMUR_UP * sk.legScale * rng.range(0.90, 1.12);
    b.addCapsule(v3(0, 0, 0), v3(sgn * out, up, rng.range(-0.05, 0.05)), sk.legR * 1.15, sk.legR * 0.82, 8, sk.chitin);
    b.addBlob(v3(0, 0, 0), v3(sk.legR * 1.5, sk.legR * 1.4, sk.legR * 1.5), 5, 8, sk.dark); // the hip knuckle
    b.addBlob(v3(sgn * out, up, 0), v3(sk.legR * 1.3, sk.legR * 1.3, sk.legR * 1.3), 5, 8, sk.light); // the knee
    return b.toMesh();
}

/// …and the lower segment, from that knee down and out to a point.
fn tibiaMesh(sk: Skin, sgn: f32, i: usize) rl.Mesh {
    var rng = mathx.Rng.init(sk.seed +% @as(u64, @intCast(i)) *% 271 +% (if (sgn > 0) @as(u64, 23) else 41));
    var b = Builder.init();
    b.setMat(.hide);
    const out = TIBIA_OUT * sk.legScale * rng.range(0.90, 1.10);
    const down = TIBIA_DOWN * sk.legScale * rng.range(0.94, 1.06);
    const knee = v3(0, 0, 0);
    const mid = v3(sgn * out * 0.5, -down * 0.45, rng.range(-0.04, 0.04));
    const foot = v3(sgn * out, -down, rng.range(-0.05, 0.05));
    b.addCapsule(knee, mid, sk.legR * 0.82, sk.legR * 0.60, 8, sk.chitin);
    b.addCapsule(mid, foot, sk.legR * 0.60, 0.008, 8, sk.dark);
    var k: u32 = 0;
    while (k < 3) : (k += 1) {
        const u = rng.range(0.2, 0.8);
        const p = mathx.lerpV(knee, mid, u);
        b.addCapsule(p, v3(p.x + rng.signed() * 0.05, p.y + rng.range(0.02, 0.07), p.z + rng.signed() * 0.05), sk.legR * 0.22, 0.004, 4, sk.dark);
    }
    return b.toMesh();
}

fn sacMesh(wrecked: bool) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    var rng = mathx.Rng.init(if (wrecked) 8831 else 3307);
    if (wrecked) {
        b.addBlob(v3(0, SAC_R * 0.30, 0), v3(SAC_R * 1.15, SAC_R * 0.34, SAC_R * 1.05), 8, 12, SAC_MEM);
        var i: u32 = 0;
        while (i < 7) : (i += 1) {
            const a = rng.angle();
            const rr = rng.range(0.2, 1.0) * SAC_R;
            b.addBlob(v3(mathx.cosf(a) * rr, SAC_R * rng.range(0.10, 0.30), mathx.sinf(a) * rr), v3(rng.range(0.06, 0.12), rng.range(0.05, 0.09), rng.range(0.06, 0.12)), 5, 8, GORE);
        }
        return b.toMesh();
    }
    b.addBlob(v3(0, SAC_R * 0.86, 0), v3(SAC_R, SAC_R * 0.92, SAC_R * 0.94), 10, 14, SAC_MEM);
    // The eggs inside, showing through as lumps in the membrane — sunk most of the way in.
    var i: u32 = 0;
    while (i < 9) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.45, 0.80) * SAC_R;
        const y = SAC_R * rng.range(0.42, 1.28);
        b.addBlob(v3(mathx.cosf(a) * rr, y, mathx.sinf(a) * rr), v3(rng.range(0.09, 0.15), rng.range(0.09, 0.14), rng.range(0.09, 0.15)), 6, 9, SAC_EGG);
    }
    var k: u32 = 0;
    while (k < 5) : (k += 1) {
        const a = rng.angle();
        b.addCapsule(v3(mathx.cosf(a) * SAC_R * 0.7, SAC_R * 1.1, mathx.sinf(a) * SAC_R * 0.7), v3(mathx.cosf(a) * SAC_R * 1.7, 0.01, mathx.sinf(a) * SAC_R * 1.7), 0.012, 0.005, 4, SAC_MEM);
        b.addCapsule(v3(mathx.cosf(a) * SAC_R * 0.5, SAC_R * 1.6, mathx.sinf(a) * SAC_R * 0.5), v3(mathx.cosf(a) * SAC_R * 0.95, SAC_R * 0.3, mathx.sinf(a) * SAC_R * 0.95), 0.018, 0.008, 5, SAC_VEIN);
    }
    return b.toMesh();
}

pub fn venomMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.plain);
    b.addBlob(mathx.zero3, v3(0.11, 0.10, 0.13), 7, 10, VENOM);
    b.addBlob(v3(0, 0, -0.04), v3(0.07, 0.06, 0.09), 6, 8, VENOM_DK);
    return b.toModel(shader);
}

fn poolMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    var rng = mathx.Rng.init(2683);
    b.addBlob(v3(0, 0.012, 0), v3(0.82, 0.030, 0.86), 9, 14, VENOM_DK);
    var i: u32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.30, 0.72);
        const s = rng.range(0.22, 0.46);
        b.addBlob(v3(mathx.cosf(a) * rr, 0.014, mathx.sinf(a) * rr), v3(s, rng.range(0.022, 0.040), s * rng.range(0.8, 1.3)), 7, 10, if (rng.float() < 0.5) VENOM else VENOM_DK);
    }
    while (i < 13) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.85, 1.05);
        b.addBlob(v3(mathx.cosf(a) * rr, 0.010, mathx.sinf(a) * rr), v3(rng.range(0.06, 0.13), 0.018, rng.range(0.06, 0.13)), 5, 8, VENOM);
    }
    return b.toMesh();
}

pub const Pool = struct {
    pos: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    seed: f32 = 0,
    live: bool = false,
    parts: [FX_MAX]Particle = [_]Particle{.{}} ** FX_MAX,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    pub fn splash(at: rl.Vector3, seed: f32) Pool {
        return .{ .pos = at, .seed = seed, .live = true, .fxRng = foe.fxStream(seed, 58067.0, 11) };
    }
    pub fn radius(self: *const Pool) f32 {
        return ACID_R * mathx.smoothstep(0, ACID_SPREAD, self.t);
    }
    pub fn strength(self: *const Pool) f32 {
        return 1.0 - mathx.smoothstep(ACID_LIFE - ACID_THIN, ACID_LIFE, self.t);
    }
    pub fn burning(self: *const Pool) bool {
        return self.live and self.t < ACID_LIFE;
    }
    pub fn covers(self: *const Pool, p: rl.Vector3) bool {
        return self.burning() and mathx.distXZ(self.pos, p) <= self.radius();
    }

    pub fn update(self: *Pool, dt: f32) void {
        if (!self.live) return;
        self.t += dt;
        foe.tickParticles(&self.parts, dt, self.pos.y);
        if (self.t >= ACID_LIFE) {
            self.live = false;
            return;
        }
        self.fxAccum += (26.0 * self.strength() + 4.0) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.float() * self.radius();
            foe.emitParticle(
                &self.parts,
                &self.fxHead,
                v3(self.pos.x + mathx.cosf(a) * rr, self.pos.y + 0.02, self.pos.z + mathx.sinf(a) * rr),
                v3(self.fxRng.signed() * 0.14, self.fxRng.range(0.25, 0.85), self.fxRng.signed() * 0.14),
                self.fxRng.range(0.35, 0.75),
                self.fxRng.range(0.03, 0.07),
                0.004,
                VENOM,
                -0.35, // the fume RISES
            );
        }
    }

    pub fn drawFx(self: *const Pool) void {
        foe.drawParticles(&self.parts);
    }
    pub fn xform(self: *const Pool) rl.Matrix {
        const r = self.radius();
        const s = self.strength();
        return mul(scaleM(r, 0.4 + 0.6 * s, r), tr(self.pos.x, self.pos.y, self.pos.z));
    }
};


pub const Sac = struct {
    pos: rl.Vector3 = mathx.zero3,
    seed: f32 = 0,
    scale: f32 = 1,
    vit: combat.Vitals = combat.Vitals.initFoe(SAC_HP, SAC_UNFLINCHING, SAC_UNFLINCHING).withRes(SAC_RESISTS),
    t: f32 = 0, // seconds since it was laid
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    killed: bool = false,
    hatched: bool = false,
    gone: bool = false,
    parts: [FX_MAX]Particle = [_]Particle{.{}} ** FX_MAX,
    fxHead: usize = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    pub fn lay(at: rl.Vector3, seed: f32, scale: f32) Sac {
        return .{
            .pos = at,
            .seed = seed,
            .scale = scale,
            .vit = combat.Vitals.initFoe(SAC_HP, SAC_UNFLINCHING, SAC_UNFLINCHING).withRes(SAC_RESISTS),
            .fxRng = foe.fxStream(seed, 74209.0, 5),
        };
    }

    pub fn alive(self: *const Sac) bool {
        return !self.gone;
    }
    /// Still standing and still going to hatch — what the mother counts against her cap.
    pub fn standing(self: *const Sac) bool {
        return !self.gone and !self.killed and !self.hatched;
    }
    pub fn centerWorld(self: *const Sac) rl.Vector3 {
        return foe.bodyPoint(self.pos, SAC_R * 0.9, self.scale, 0);
    }
    pub fn hurtRadius(self: *const Sac) f32 {
        return SAC_HURT_R * self.scale;
    }
    /// THE TARGET CONTRACT.
    pub fn dying(self: *const Sac) bool {
        return self.killed or self.hatched;
    }
    pub fn staggered(_: *const Sac) bool {
        return false; // it has no reaction to be in — it either holds or it bursts
    }
    /// THE ONE TARGET WHOSE MARK IS STILL A HEIGHT, and it is not an oversight: a sac is one membrane on
    /// the ground with no parts to ride. There is nothing on it that moves independently of the whole,
    /// so its centre IS the part the reticle would have ridden.
    pub fn lockPoint(self: *const Sac) rl.Vector3 {
        return self.centerWorld();
    }
    pub fn topWorld(self: *const Sac) rl.Vector3 {
        return foe.bodyPoint(self.pos, SAC_R * 1.9, self.scale, 0);
    }
    pub fn bodyR(self: *const Sac) f32 {
        return SAC_R * self.scale;
    }
    pub fn kind(self: *const Sac) wf.FoeKind {
        _ = self;
        return .brood_sac;
    }
    pub fn flashFrac(self: *const Sac) f32 {
        return foe.flashFrac(self.flash);
    }
    /// SWELLING, 0..1 — the tell.
    pub fn swell(self: *const Sac) f32 {
        return mathx.clampF(self.t / SAC_HATCH, 0, 1);
    }

    pub fn update(self: *Sac, dt: f32, blade: foe.Blade) bool {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return false;
        }
        self.flash = mathx.maxF(0, self.flash - dt);
        // A SAC IS A TARGET, so its vitals run like every other target's — `sinceHurt` is what the floating HP bar is gated on, and left frozen at 0 the bar never goes away again.
        self.vit.tick(dt);
        self.t += dt;
        foe.tickParticles(&self.parts, dt, self.pos.y);
        if (self.killed or self.hatched) {
            if (self.t >= SAC_BURST_DUR) self.gone = true;
            return false;
        }
        self.tryHit(blade);
        if (self.killed or self.gone) return false;
        if (self.t >= SAC_HATCH) {
            self.hatched = true;
            self.t = 0;
            self.burstFx(MOTE, 16, 2.1);
            sfx.world(.sac_hatch, self.pos);
            return true;
        }
        return false;
    }

    pub fn tryHit(self: *Sac, blade: foe.Blade) void {
        if (self.killed or self.hatched or self.gone) return;
        const s = foe.strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), blade) orelse return;
        self.hits += 1;
        self.flash = FLASH_DUR;
        self.burstFx(VENOM, 7, 1.5);
        if (s.reaction == .death) {
            self.killed = true;
            self.t = 0;
            self.burstFx(GORE, 14, 2.4);
            self.burstFx(VENOM, 10, 2.0);
            sfx.world(.sac_burst, self.pos);
        } else {
            sfx.world(.sac_hit, self.pos);
        }
    }

    fn burstFx(self: *Sac, col: rl.Color, n: i32, spd: f32) void {
        const c = self.centerWorld();
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const s = self.fxRng.range(0.4, 1.0) * spd;
            foe.emitParticle(
                &self.parts,
                &self.fxHead,
                c,
                v3(mathx.cosf(a) * s, self.fxRng.range(0.4, 2.1), mathx.sinf(a) * s),
                self.fxRng.range(0.32, 0.62),
                self.fxRng.range(0.03, 0.07) * self.scale,
                0.01,
                col,
                6.0,
            );
        }
    }

    pub fn drawFx(self: *const Sac) void {
        foe.drawParticles(&self.parts);
    }

    pub fn xform(self: *const Sac) rl.Matrix {
        const k = self.swell();
        if (self.killed or self.hatched) {
            const u = mathx.clampF(self.t / SAC_BURST_DUR, 0, 1);
            const s = self.scale * (1.0 - 0.55 * u);
            return mul(scaleM(s, s * (1.0 - 0.3 * u), s), tr(self.pos.x, self.pos.y, self.pos.z));
        }
        const pulse = 0.055 * k * mathx.sinf(self.t * SAC_PULSE_HZ * std.math.tau);
        const grow = self.scale * (0.72 + 0.28 * k);
        return mul(
            scaleM(grow * (1.0 - pulse * 0.5), grow * (1.0 + pulse), grow * (1.0 - pulse * 0.5)),
            tr(self.pos.x, self.pos.y, self.pos.z),
        );
    }
};


pub const Spider = struct {
    role: Role = .mother,
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    /// WHERE THE EGGS ARE, pushed in by the group each frame — her tether is the clutch, not her post (see M_GUARD_R).
    guard: ?rl.Vector3 = null,
    /// …and whether she may lay another, likewise the group's answer (it owns the sacs).
    layWanted: bool = false,
    leash: foe.Leash = .{},
    /// THE WAND'S ROOTS, when they have hold of it (combat.Root) — stamped from outside, like the leash's eyes.
    root: combat.Root = .{},
    /// …and THE HERO'S SHIELD, stamped the same way (`game.markParry`). Read only inside her own bite window.
    parry: foe.Parry = .{},
    /// THE SHIELD CAUGHT HER FANGS THIS FRAME — a ONE-FRAME flag, `justDied`'s exactly: reset at the top of
    /// `update`, set where the catch happens, read by the group (`Brood.anyParried`) after.
    parried: bool = false,
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    idleWait: f32 = 0,
    spitCd: f32 = 0,
    biteCd: f32 = 0,
    layCd: f32 = 0,
    elapsed: f32 = 0,
    fired: bool = false, // this action's one-shot (the glob leaving, the sac dropping) has happened
    throwing: bool = false,
    moveDir: rl.Vector3 = mathx.zero3,

    leapFrom: rl.Vector3 = mathx.zero3,
    leapTo: rl.Vector3 = mathx.zero3,

    gait: f32 = 0, // leg cycle phase, advanced by ground covered
    lift: f32 = 0, // world-Y above its own ground (the leap)
    crouch: f32 = 0, // body drop toward the legs (coil, lay)
    rear: f32 = 0,
    pitch: f32 = 0,
    armSpread: f32 = 0, // claws thrown wide (deg)
    armDrive: f32 = 0,
    bladeOpen: f32 = 0,
    abdoPump: f32 = 0, // the abdomen swelling/pumping through a lay or a spit
    fangs: f32 = 0,
    roll: f32 = 0, // the death KEEL — degrees about the body's long axis, hinged at BODY_Y
    settle: f32 = 0, // death-only world-Y shift: the flipped back finding the ground the legs no longer hold it off
    legCurl: f32 = 0, // death-only: femurs drawn in + knees clamped — the dead spider's leg basket

    vit: combat.Vitals = combat.Vitals.initFoe(M_HP, M_POISE, M_STANCE).withRes(RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    heroHit: ?combat.Hit = null,
    heroLatch: bool = false,
    justDied: bool = false,
    fade: f32 = 0,
    gone: bool = false,

    parts: [FX_MAX]Particle = [_]Particle{.{}} ** FX_MAX,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [NP]rl.Matrix = undefined,

    pub fn spawnAs(role: Role, home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Spider {
        const sp = spec(role);
        var s = Spider{
            .role = role,
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * sp.scale,
            .seed = seed,
            .vit = combat.Vitals.initFoe(sp.hp, sp.poise, sp.stance).withRes(RESISTS),
        };
        s.fxRng = foe.fxStream(seed, 92821.0, @as(u64, @intFromEnum(role)) + 3);
        s.idleWait = 0.4 + seed * 1.4;
        s.layCd = 1.2; // she does not lay the instant she sees him
        s.resolveIdle(1.0 / 60.0); // a one-shot settle for the spawn pose; the loop passes real time
        s.pose();
        return s;
    }

    pub fn kind(self: *const Spider) wf.FoeKind {
        return kindOf(self.role);
    }
    pub fn runeValue(self: *const Spider) u32 {
        return spec(self.role).runes;
    }
    pub fn centerWorld(self: *const Spider) rl.Vector3 {
        return foe.bodyPoint(self.pos, BODY_CY, self.scale, self.lift);
    }
    pub fn hurtRadius(self: *const Spider) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Spider) f32 {
        return BODY_R * self.scale;
    }
    /// THE MARK RIDES THE CEPHALOTHORAX — the fused head she REARS on and drops through a bite. A height
    /// off the ground ignored the whole of that: she has no upright posture to measure one against.
    pub fn lockPoint(self: *const Spider) rl.Vector3 {
        return foe.markOn(self.xf[CEPHALO], LOCK_AT);
    }
    pub fn topWorld(self: *const Spider) rl.Vector3 {
        return foe.bodyPoint(self.pos, BODY_Y + 0.42, self.scale, self.lift);
    }
    pub fn airborne(self: *const Spider) bool {
        return self.lift > foe.AIRBORNE_LIFT;
    }
    pub fn alive(self: *const Spider) bool {
        return !self.gone;
    }
    pub fn staggered(self: *const Spider) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn dying(self: *const Spider) bool {
        return self.state == .dead;
    }
    pub fn flashFrac(self: *const Spider) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn eyesHot(self: *const Spider) bool {
        return self.state == .windup or self.state == .strike or self.state == .leap;
    }

    fn fdir(self: *const Spider) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Spider, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, spec(self.role).turn, dt);
    }
    /// Where the fangs are — the glob leaves from here, and so does the drool.
    pub fn mouthWorld(self: *const Spider) rl.Vector3 {
        const d = self.fdir();
        return v3(
            self.pos.x + d.x * 0.52 * self.scale,
            self.pos.y + (BODY_Y - 0.10) * self.scale + self.lift + self.rear * 0.30 * self.scale,
            self.pos.z + d.z * 0.52 * self.scale,
        );
    }
    /// …and where a sac goes down: behind her, clear of her own feet.
    fn layWorld(self: *const Spider) rl.Vector3 {
        const d = self.fdir();
        return v3(self.pos.x - d.x * LAY_BACK * self.scale, self.pos.y, self.pos.z - d.z * LAY_BACK * self.scale);
    }
    /// How far she has strayed from what she is guarding (her clutch, else her post).
    fn tetherOut(self: *const Spider) f32 {
        return mathx.distXZ(self.pos, self.guard orelse self.home);
    }

    fn enter(self: *Spider, s: State) void {
        self.state = s;
        self.t = 0;
        self.fired = false;
        self.heroLatch = false;
    }
    fn enterIdle(self: *Spider, wait: f32) void {
        self.enter(.idle);
        self.idleWait = wait;
    }
    fn enterDeath(self: *Spider) void {
        self.enter(.dead);
        self.justDied = true;
        sfx.world(if (self.role == .mother) .spider_die else .brood_die, self.pos);
    }
    pub fn debugStagger(self: *Spider, heavy: bool) void {
        self.enter(if (heavy) .stunheavy else .stunlight);
    }
    pub fn debugKill(self: *Spider) void {
        self.enterDeath();
    }

    /// WHAT SHE ASKED THE WORLD FOR THIS FRAME — the two things a spider cannot do to itself.
    pub const Act = union(enum) {
        none,
        spit: rl.Vector3,
        lay: rl.Vector3,
    };

    pub fn update(self: *Spider, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) Act {
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return .none;
        }
        self.heroHit = null;
        self.justDied = false;
        self.parried = false;
        // THE ROOTS HAVE THE FEET AND NOTHING ELSE (foe.grip) — she still spits, still lays, still bites what is in
        // reach, and chitin shrugs most of the grip off.
        const grip = foe.grip(&self.root, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        self.vit.tick(dt);
        self.elapsed += dt;
        self.t += dt;
        self.flash = mathx.maxF(0, self.flash - dt);
        self.spitCd = mathx.maxF(0, self.spitCd - dt);
        self.biteCd = mathx.maxF(0, self.biteCd - dt);
        self.layCd = mathx.maxF(0, self.layCd - dt);
        self.leash.tick(dt, mathx.distXZ(self.pos, self.home), mathx.distXZ(self.pos, hero), spec(self.role).aggro);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.sensedDist(&self.leash, mathx.distXZ(self.pos, hero), spec(self.role).aggro);
        // THE SHIELD, asked BEFORE the state machine runs this frame's snap — a catch has to kill the bite it
        // caught, and by the time `tryReach` has run the fangs are already in him.
        self.takeParry();
        var act: Act = .none;
        switch (self.role) {
            .mother => act = self.updateMother(dt, hero, bounds, d),
            .broodling => self.updateBroodling(dt, hero, bounds, d),
        }
        self.pose();
        self.tryHit(blade);
        return act;
    }


    fn updateMother(self: *Spider, dt: f32, hero: rl.Vector3, bounds: f32, d: f32) Act {
        var act: Act = .none;
        switch (self.state) {
            .idle => {
                if (d <= M_AGGRO) self.faceToward(hero, dt);
                self.resolveIdle(dt);
                const wait = if (d <= M_AGGRO) mathx.minF(self.idleWait, 0.14) else self.idleWait;
                if (self.t >= wait) self.decideMother(d, bounds);
            },
            .walk => {
                self.faceToward(hero, dt);
                const moved = M_SPEED * dt;
                mathx.stepXZ(&self.pos, self.moveDir, moved, bounds);
                self.gait += moved / (skinOf(self.role).stride * self.scale);
                self.emitDrag(dt);
                self.resolveWalk();
                if (self.t >= 0.28) self.decideMother(d, bounds);
            },
            .windup => {
                self.faceToward(hero, dt * (if (self.spitting()) @as(f32, 1.0) else 0.5));
                if (self.throwing) self.resolveSpitWind(dt) else self.resolveBiteWind(dt);
                if (self.t >= self.windupDur()) self.enter(.strike);
            },
            .strike => {
                if (self.spitting()) {
                    self.resolveSpitThrow();
                    if (!self.fired) {
                        self.fired = true;
                        act = .{ .spit = self.mouthWorld() };
                        self.spitBurst();
                        sfx.world(.spider_spit, self.pos);
                    }
                    if (self.t >= SPIT_THROW) self.enter(.recover);
                } else {
                    self.resolveBiteSnap();
                    if (!self.fired) {
                        self.fired = true;
                        sfx.world(.spider_bite, self.pos);
                    }
                    self.tryReach(hero, M_BITE_R, M_BITE_HIT);
                    if (self.t >= BITE_SNAP) self.enter(.recover);
                }
            },
            .recover => {
                self.faceToward(hero, dt * 0.6);
                self.resolveRecover();
                if (self.t >= self.recoverDur()) self.enterIdle(0.05);
            },
            .lay => {
                self.resolveLay();
                if (!self.fired and self.t >= LAY_DUR * LAY_DROP) {
                    self.fired = true;
                    act = .{ .lay = self.layWorld() };
                    sfx.world(.sac_lay, self.pos);
                }
                if (self.t >= LAY_DUR) {
                    self.layCd = LAY_CD;
                    self.enterIdle(0.08);
                }
            },
            .stunlight => {
                self.resolveStun(false);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enterIdle(0.02);
            },
            .stunheavy => {
                self.resolveStun(true);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enterIdle(0.05);
            },
            .leap => self.enterIdle(0.05),
            .dead => self.resolveDeath(dt),
        }
        return act;
    }

    fn spitting(self: *const Spider) bool {
        return self.throwing;
    }
    fn windupDur(self: *const Spider) f32 {
        return if (self.throwing) SPIT_WINDUP else BITE_WINDUP;
    }
    /// PER ROLE, like every other duration here: `resolveRecover` scales its pose to this, so a broodling given the mother's window plays half a recovery and then snaps to idle.
    fn recoverDur(self: *const Spider) f32 {
        if (self.role == .broodling) return B_BITE_RECOVER;
        return if (self.throwing) SPIT_RECOVER else BITE_RECOVER;
    }

    fn decideMother(self: *Spider, d: f32, bounds: f32) void {
        _ = bounds;
        switch (classifyMother(d, self.tetherOut(), self.spitCd <= 0, self.biteCd <= 0, self.layWanted and self.layCd <= 0)) {
            .hold => self.enterIdle(0.16 + self.seed * 0.5),
            .close => {
                self.moveDir = self.fdir();
                self.enter(.walk);
            },
            .spit => {
                self.spitCd = SPIT_CD;
                self.throwing = true;
                self.enter(.windup);
                sfx.world(.spider_hiss, self.pos);
            },
            .bite => {
                self.biteCd = BITE_CD;
                self.throwing = false;
                self.enter(.windup);
            },
            // NO HISS ON THE LAY. The hiss is kept for the SPIT, where it is the windup you read the glob
            // off; laying a sac is a thing you watch her do, and it already has the sac's own voice under it.
            .lay => self.enter(.lay),
        }
    }


    fn updateBroodling(self: *Spider, dt: f32, hero: rl.Vector3, bounds: f32, d: f32) void {
        switch (self.state) {
            .idle => {
                if (d <= B_AGGRO) self.faceToward(hero, dt);
                self.resolveIdle(dt);
                const wait = if (d <= B_AGGRO) mathx.minF(self.idleWait, 0.08) else self.idleWait;
                if (self.t >= wait) self.decideBroodling(d, hero);
            },
            .walk => {
                self.faceToward(hero, dt);
                const moved = B_SPEED * dt;
                mathx.stepXZ(&self.pos, self.fdir(), moved, bounds);
                self.gait += moved / (skinOf(self.role).stride * self.scale);
                self.resolveWalk();
                if (self.t >= 0.18) self.decideBroodling(d, hero);
            },
            .windup => {
                self.faceToward(hero, dt * 0.7);
                self.resolveBiteWind(dt);
                if (self.t >= B_BITE_WINDUP) self.enter(.strike);
            },
            .strike => {
                self.resolveBiteSnap();
                if (!self.fired) {
                    self.fired = true;
                    sfx.world(.brood_bite, self.pos);
                }
                self.tryReach(hero, B_BITE_R, B_BITE_HIT);
                if (self.t >= B_BITE_SNAP) self.enter(.recover);
            },
            .recover => {
                self.faceToward(hero, dt);
                self.resolveRecover();
                if (self.t >= self.recoverDur()) self.enterIdle(0.02);
            },
            .leap => self.updateLeap(dt, hero, bounds),
            .stunlight => {
                self.resolveStun(false);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enterIdle(0.02);
            },
            .stunheavy => {
                self.resolveStun(true);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enterIdle(0.02);
            },
            .lay => self.enterIdle(0.05),
            .dead => self.resolveDeath(dt),
        }
    }

    fn decideBroodling(self: *Spider, d: f32, hero: rl.Vector3) void {
        // The pounce is a JUMP, so the grip refuses it outright rather than playing it out on the spot
        // (`foe.canLeap`); with it off the table a held hatchling falls through to `.chase` and skitters
        // nowhere, which is the post-step gate doing its ordinary job.
        switch (classifyBroodling(d, self.leapCdReady() and foe.canLeap(&self.root), self.biteCd <= 0)) {
            .idle => {
                // Out of its senses: skitter back toward where it hatched rather than freeze mid-field.
                if (mathx.distXZ(self.pos, self.home) > B_HOME_R) {
                    self.facing = mathx.headingXZ(mathx.dirXZ(self.pos, self.home));
                    self.enter(.walk);
                } else self.enterIdle(0.7 + self.seed * 1.1);
            },
            .chase => self.enter(.walk),
            .bite => {
                self.biteCd = B_BITE_CD;
                self.enter(.windup);
            },
            .leap => self.startLeap(hero),
        }
    }
    fn leapCdReady(self: *const Spider) bool {
        return self.spitCd <= 0; // a hatchling has no spit: the same clock times its pounce
    }

    fn startLeap(self: *Spider, hero: rl.Vector3) void {
        self.spitCd = B_LEAP_CD;
        self.enter(.leap);
        self.dustBurst(self.pos, 9, 1.9, 0.17);
        self.leapFrom = self.pos;
        const dir = mathx.dirXZ(self.pos, hero);
        const reach = mathx.minF(mathx.distXZ(self.pos, hero) - B_BITE_R * 0.5, B_LEAP_MAX);
        self.leapTo = v3(self.pos.x + dir.x * reach, self.pos.y, self.pos.z + dir.z * reach);
        self.facing = mathx.headingXZ(dir);
        sfx.world(.brood_leap, self.pos);
    }

    fn updateLeap(self: *Spider, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const total = B_LEAP_COIL + B_LEAP_FLIGHT + B_LEAP_LAND;
        if (self.t < B_LEAP_COIL) {
            // THE COIL — it gathers on the spot, and this is the whole of your warning.
            const u = self.t / B_LEAP_COIL;
            self.faceToward(hero, dt * 0.6);
            self.crouch = mathx.smoothstep(0, 1, u);
            self.rear = 0;
            self.lift = 0;
            self.armSpread = 34.0 * self.crouch;
            self.bladeOpen = 0.5 * self.crouch;
            self.fangs = self.crouch;
            self.resolvePlanted();
            return;
        }
        if (self.t < B_LEAP_COIL + B_LEAP_FLIGHT) {
            const u = (self.t - B_LEAP_COIL) / B_LEAP_FLIGHT;
            const p = mathx.clampXZ(mathx.lerpV(self.leapFrom, self.leapTo, u), bounds);
            self.pos.x = p.x;
            self.pos.z = p.z;
            self.lift = B_LEAP_APEX * self.scale * 4.0 * u * (1.0 - u);
            self.crouch = -0.35; // legs thrown out, body stretched forward
            self.armSpread = 46.0;
            self.bladeOpen = 1.0;
            self.fangs = 1.0;
            self.pitch = -14.0;
            self.resolveFlung(u);
            self.tryImpact(hero, B_LEAP_HIT);
            return;
        }
        const u = mathx.clampF((self.t - B_LEAP_COIL - B_LEAP_FLIGHT) / B_LEAP_LAND, 0, 1);
        self.lift = 0;
        self.crouch = 0.5 * (1.0 - u);
        self.pitch = -14.0 * (1.0 - u);
        self.armSpread = 46.0 * (1.0 - u);
        self.bladeOpen = 1.0 - u;
        self.resolvePlanted();
        if (self.t >= total) {
            if (!self.fired) {
                self.fired = true;
                self.dustBurst(self.pos, 12, 2.4, 0.20);
            }
            self.biteCd = mathx.minF(self.biteCd, 0.12);
            self.enterIdle(0.02);
        }
    }


    /// SECONDS UNTIL HER FANGS LAND, counted back from the frame `tryReach` fires — the FIRST frame of
    /// `.strike`, so the whole window lives in the windup and shuts at the snap by construction.
    ///
    /// Null for everything that is not her bite, and none of those is an oversight:
    /// - THE SPIT IS NOT PARRYABLE. The boards refuse a BLOW; a glob of acid is a projectile and goes through
    ///   the quiver like an arrow (`archer.launchShaft`), so there is no swing to catch.
    /// - NOR IS THE LAY, which is not an attack at all — she is wide open for it already.
    /// - AND NOR IS A BROODLING. A shield window on something that arrives out of a sac, four at a time, and
    ///   dies to one slash is a mechanic nobody could read; its 0.34 s tell is the counter it was given.
    ///
    /// EXHAUSTIVE over the states, so one added later has to say whether it carries a blow.
    fn toImpact(self: *const Spider) ?f32 {
        if (self.role != .mother or self.throwing) return null;
        return switch (self.state) {
            .windup => BITE_WINDUP - self.t,
            // Already snapping: `t` has been advanced by the time this is asked, so `left` is negative from the
            // first frame of it and the window is shut. The blow and the catch can never both happen.
            .strike => -self.t,
            .idle, .walk, .recover, .lay, .leap, .stunlight, .stunheavy, .dead => null,
        };
    }

    /// THE INSTANT THE FANGS CAN BE CAUGHT IN, and how far out they reach then — `tryReach`'s OWN extent, and
    /// UNSCALED exactly as that test is, so a bite the boards could not possibly have met is never offered as
    /// one (the ogre's `slamReach` law: the parry's reach is the blow's reach and not a second number).
    fn parryable(self: *const Spider) ?f32 {
        const left = self.toImpact() orelse return null;
        if (left < 0 or left > PARRY_LEAD) return null;
        return M_BITE_R + HERO_REACH;
    }

    /// THE BOARDS TAKE HER FANGS. `enter` is what kills the bite — it re-arms `heroLatch` and leaves `.strike`
    /// unreached, so nothing lands. NO BLOOD AND NO CHIPS: nothing was wounded. What says it happened is the
    /// whole-body flash, her stumble, and the amber off the shield itself — sized against the CREATURE.
    fn takeParry(self: *Spider) void {
        const reach = self.parryable() orelse return;
        if (!self.parry.catches(self.pos, reach)) return;
        self.parried = true;
        self.flash = FLASH_DUR;
        self.leash.noteCombat();
        // Back on its own cooldown though it never finished, or she walks out of the recoil into the snap she
        // was just denied.
        self.biteCd = BITE_CD;
        sfx.world(.spider_hurt, self.pos);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(), // a parry takes no HP today; the day one does, it kills like anything
            .heavy => self.enter(.stunheavy),
            // A stance that HELD is still fangs knocked off their line: the bite dies either way, into the
            // short recoil rather than the wide-open punish window.
            .light, .none => self.enter(.stunlight),
        }
    }

    fn tryReach(self: *Spider, hero: rl.Vector3, range: f32, h: combat.Hit) void {
        if (self.heroLatch) return;
        if (mathx.distXZ(self.pos, hero) <= range + HERO_REACH) {
            self.heroHit = h;
            self.heroLatch = true;
            self.leash.noteCombat();
        }
    }

    /// The pounce's landing: frontal only, like the toad's slam — one beside it is clear.
    fn tryImpact(self: *Spider, hero: rl.Vector3, h: combat.Hit) void {
        if (self.heroLatch) return;
        const d = mathx.distXZ(self.pos, hero);
        if (d > B_LEAP_IMPACT_R + HERO_REACH) return;
        const to = mathx.dirXZ(self.pos, hero);
        const fwd = self.fdir();
        if (d > 0.3 and to.x * fwd.x + to.z * fwd.z < B_LEAP_FRONT_DOT) return;
        self.heroHit = h;
        self.heroLatch = true;
        self.leash.noteCombat();
    }

    /// THE DAMAGE ENTRY, public because a shaft comes through it too (`foe.pierceGroup`).
    pub fn tryHit(self: *Spider, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade) orelse return;
        // THE SHOVE IS BILLED AGAINST HER MASS: a mother is four times a broodling and must not be swatted
        // about like one. Divided into the pair at the call site rather than carried as a third dial —
        // `Push` is two numbers chosen against each other, and this is the same choice made per body.
        const d = mathx.maxF(0.5, self.scale);
        const heavy = foe.wounded(self, s, blade, .{ .light = 1.35 / d, .heavy = 2.1 / d });
        self.bloodBurst(s.contact, s.dir, if (heavy) 13 else 8, if (heavy) 2.5 else 1.8);
        sfx.world(if (self.role == .mother) .spider_hurt else .brood_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                self.bloodBurst(s.contact, s.dir, 10, 2.2);
                self.enterDeath();
            },
            .heavy => self.enter(.stunheavy),
            .light => self.enter(.stunlight),
            .none => {},
        }
    }


    fn emit(self: *Spider, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
        foe.emitParticle(&self.parts, &self.fxHead, p, vel, life, r0, r1, col, grav);
    }
    fn bloodBurst(self: *Spider, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.4, 1.0) * spd;
            self.emit(
                at,
                v3(dir.x * sp + mathx.cosf(a) * self.fxRng.range(0.15, 0.7), self.fxRng.range(0.6, 2.2), dir.z * sp + mathx.sinf(a) * self.fxRng.range(0.15, 0.7)),
                self.fxRng.range(0.26, 0.48),
                self.fxRng.range(0.025, 0.05) * self.scale,
                0.008,
                GORE,
                7.5,
            );
        }
    }
    fn emitDrag(self: *Spider, dt: f32) void {
        if (self.role != .mother) return;
        const back = mathx.scaleV(self.fdir(), -1);
        const at = v3(self.pos.x + back.x * 0.9 * self.scale, self.pos.y + 0.03, self.pos.z + back.z * 0.9 * self.scale);
        self.fxAccum += 26.0 * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            self.emit(
                v3(at.x + mathx.cosf(a) * 0.3 * self.scale, at.y, at.z + mathx.sinf(a) * 0.3 * self.scale),
                v3(back.x * self.fxRng.range(0.2, 0.9) + self.fxRng.signed() * 0.3, self.fxRng.range(0.15, 0.7), back.z * self.fxRng.range(0.2, 0.9) + self.fxRng.signed() * 0.3),
                self.fxRng.range(0.4, 0.8),
                self.fxRng.range(0.05, 0.11) * self.scale,
                self.fxRng.range(0.16, 0.30) * self.scale,
                DUST,
                2.2,
            );
        }
    }

    fn dustBurst(self: *Spider, c: rl.Vector3, n: i32, spd: f32, big: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const a = self.fxRng.angle();
            const sp = self.fxRng.range(0.5, 1.0) * spd * self.scale;
            self.emit(
                v3(c.x, c.y + 0.04, c.z),
                v3(mathx.cosf(a) * sp, self.fxRng.range(0.5, 2.0), mathx.sinf(a) * sp),
                self.fxRng.range(0.32, 0.6),
                self.fxRng.range(0.05, 0.11) * self.scale,
                big * self.fxRng.range(0.8, 1.3) * self.scale,
                DUST,
                4.2,
            );
        }
    }

    /// Venom gathering at the fangs through the wind-up — the tell you can see from outside her range.
    fn emitDrool(self: *Spider, dt: f32, k: f32) void {
        self.fxAccum += (8.0 + 26.0 * k) * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const m = self.mouthWorld();
            self.emit(
                v3(m.x + self.fxRng.signed() * 0.14 * self.scale, m.y + self.fxRng.range(-0.06, 0.16) * self.scale, m.z + self.fxRng.signed() * 0.14 * self.scale),
                v3(self.fxRng.signed() * 0.2, self.fxRng.range(-0.4, 0.3), self.fxRng.signed() * 0.2),
                self.fxRng.range(0.28, 0.5),
                self.fxRng.range(0.025, 0.05) * self.scale,
                0.006,
                VENOM,
                5.0,
            );
        }
    }
    fn spitBurst(self: *Spider) void {
        const m = self.mouthWorld();
        const d = self.fdir();
        var i: i32 = 0;
        while (i < 10) : (i += 1) {
            const sp = self.fxRng.range(1.4, 3.2);
            self.emit(
                m,
                v3(d.x * sp + self.fxRng.signed() * 0.6, self.fxRng.range(0.2, 1.0), d.z * sp + self.fxRng.signed() * 0.6),
                self.fxRng.range(0.24, 0.44),
                self.fxRng.range(0.025, 0.045) * self.scale,
                0.01,
                VENOM,
                6.5,
            );
        }
    }
    pub fn drawFx(self: *const Spider) void {
        foe.drawParticles(&self.parts);
    }


    /// `dt`, NOT a baked 1/60: every `approach` here is a rate per SECOND, so a fixed step makes the settle twice as fast on a 120 Hz machine as on a 60 Hz one — the same class of bug the FEEL RULES ban for input, and it is just as visible on a creature easing back to rest.
    fn resolveIdle(self: *Spider, dt: f32) void {
        const breathe = mathx.sinf(self.elapsed * 1.3 + self.seed * 6.0);
        self.crouch = -IDLE_BOB * breathe;
        self.rear = 0;
        self.pitch = 0;
        self.lift = 0;
        self.armSpread = mathx.approach(self.armSpread, 20.0 + 4.0 * breathe, 60.0 * dt);
        self.armDrive = mathx.approach(self.armDrive, 0, 3.0 * dt);
        self.bladeOpen = mathx.approach(self.bladeOpen, 0.12, 2.0 * dt);
        self.abdoPump = mathx.approach(self.abdoPump, 0.04 * breathe, 2.0 * dt);
        self.fangs = mathx.approach(self.fangs, 0, 3.0 * dt);
    }
    fn resolveWalk(self: *Spider) void {
        self.crouch = 0.03 * mathx.sinf(self.gait * std.math.tau * 2.0);
        self.rear = 0;
        self.pitch = 0;
        self.lift = 0;
        self.armSpread = 14.0;
        self.armDrive = 0;
        self.bladeOpen = 0.2;
        self.abdoPump = 0.05 * mathx.sinf(self.gait * std.math.tau);
        self.fangs = 0;
    }
    fn resolveSpitWind(self: *Spider, dt: f32) void {
        const u = mathx.smoothstep(0, 1, mathx.clampF(self.t / SPIT_WINDUP, 0, 1));
        self.rear = u;
        self.crouch = -0.10 * u;
        self.pitch = -16.0 * u;
        self.armSpread = 12.0 + 52.0 * u;
        self.armDrive = 0;
        self.bladeOpen = 0.2 + 0.7 * u;
        self.abdoPump = 0.13 * u + 0.07 * u * mathx.sinf(self.t * 22.0);
        self.fangs = u;
        self.emitDrool(dt, u);
        // …and the front legs DIG as she rears: dust under her, ramping with the load.
        if (self.fxRng.float() < dt * 34.0 * u) self.dustBurst(self.pos, 2, 1.0, 0.12);
    }
    fn resolveSpitThrow(self: *Spider) void {
        const u = mathx.clampF(self.t / SPIT_THROW, 0, 1);
        self.rear = 1.0 - 0.75 * u; // the whole front end SLAMS down behind the glob
        self.crouch = -0.10 + 0.22 * u;
        self.pitch = -16.0 + 34.0 * u;
        self.armSpread = 64.0 - 18.0 * u;
        self.bladeOpen = 0.9;
        self.abdoPump = 0.13 * (1.0 - u);
        self.fangs = 1.0;
    }
    fn resolveBiteWind(self: *Spider, dt: f32) void {
        const dur: f32 = if (self.role == .mother) BITE_WINDUP else B_BITE_WINDUP;
        const u = mathx.smoothstep(0, 1, mathx.clampF(self.t / dur, 0, 1));
        self.rear = 0.45 * u;
        self.crouch = -0.06 * u;
        self.pitch = -8.0 * u;
        self.armSpread = 12.0 + 62.0 * u; // the claws go WIDE — the frame opens up before it shuts
        self.armDrive = -0.35 * u;
        self.bladeOpen = 0.2 + 0.8 * u;
        self.abdoPump = 0.10 * u;
        self.fangs = u;
        if (self.role == .mother) self.emitDrool(dt, u * 0.6);
    }
    fn resolveBiteSnap(self: *Spider) void {
        const dur: f32 = if (self.role == .mother) BITE_SNAP else B_BITE_SNAP;
        const u = mathx.clampF(self.t / dur, 0, 1);
        self.rear = 0.45 * (1.0 - u);
        self.crouch = 0.14 * u;
        self.pitch = -8.0 + 22.0 * u;
        self.armSpread = 74.0 - 66.0 * u;
        self.armDrive = -0.35 + 1.35 * u;
        self.bladeOpen = 1.0 - 0.95 * u;
        self.fangs = 1.0;
        self.abdoPump = 0;
    }
    fn resolveRecover(self: *Spider) void {
        const dur = self.recoverDur();
        const u = mathx.clampF(self.t / dur, 0, 1);
        self.rear = 0;
        self.crouch = 0.14 * (1.0 - u);
        self.pitch = 14.0 * (1.0 - u);
        self.armSpread = 8.0 + 10.0 * (1.0 - u);
        self.armDrive = 1.0 * (1.0 - u);
        self.bladeOpen = 0.05 + 0.2 * u;
        self.fangs = 1.0 - u;
        self.abdoPump = 0;
    }
    fn resolveLay(self: *Spider) void {
        const u = mathx.clampF(self.t / LAY_DUR, 0, 1);
        const swell = mathx.smoothstep(0, LAY_DROP, u);
        const after = mathx.smoothstep(LAY_DROP, 1.0, u);
        self.crouch = 0.42 * swell * (1.0 - 0.7 * after);
        self.rear = 0;
        self.pitch = 6.0 * swell;
        self.armSpread = 10.0 + 22.0 * swell;
        self.armDrive = 0;
        self.bladeOpen = 0.15;
        self.fangs = 0.2 * swell;
        self.abdoPump = 0.14 * swell + 0.09 * swell * mathx.sinf(self.t * 13.0) - 0.14 * after;
    }
    fn resolveStun(self: *Spider, heavy: bool) void {
        const dur: f32 = if (heavy) combat.FOE_HEAVY_STUN_DUR else combat.FOE_LIGHT_STUN_DUR;
        const u = mathx.clampF(self.t / dur, 0, 1);
        const k = (1.0 - u) * (1.0 - u);
        const shake = mathx.sinf(self.t * (if (heavy) @as(f32, 26.0) else 34.0));
        self.crouch = (if (heavy) @as(f32, 0.62) else 0.34) * k;
        self.rear = 0;
        self.pitch = (if (heavy) @as(f32, 26.0) else 13.0) * k * (0.6 + 0.4 * shake);
        self.armSpread = (if (heavy) @as(f32, 78.0) else 52.0) * k;
        self.armDrive = -0.5 * k;
        self.bladeOpen = 0.9 * k;
        self.abdoPump = -0.25 * k;
        self.fangs = k;
        self.lift = 0;
    }
    fn resolveDeath(self: *Spider, dt: f32) void {
        // A dead spider ends on its BACK, and the CAUSE reads in the order: the legs CRAMP first,
        // the stance fails, it FALLS sideways — accelerating, past flat — rocks back once, and clenches.
        const u = mathx.clampF(self.t / DEATH_DUR, 0, 1);
        const rearK = mathx.smoothstep(0, 0.10, u) * (1.0 - mathx.smoothstep(0.10, 0.30, u)); // one fast convulsion
        const cramp = mathx.smoothstep(0.03, 0.30, u);
        const clench = mathx.smoothstep(0.55, 0.85, u);
        const f = mathx.clampF((u - 0.20) / 0.35, 0, 1);
        const fall = f * f; // gravity's ease-in: slow past the balance point, arriving HOT
        const sk = skinOf(self.role);
        const dir: f32 = if (self.seed > 0.5) 1.0 else -1.0; // which shoulder it keels over — per spider, cosmetic
        const rollMax = 186.0 + 10.0 * self.seed; // the crash carries PAST flat…
        const rollRest = 168.0 + 14.0 * self.seed; // …and the rock-back settles short of it
        self.roll = dir * (rollMax * fall - (rollMax - rollRest) * mathx.smoothstep(0.55, 0.74, u));
        self.pitch = 26.0 * rearK + 5.0 * clench; // the head end stays out of the dirt
        self.rear = 0;
        self.crouch = 0.35 * cramp;
        self.legCurl = 0.55 * cramp + 0.45 * clench; // the cramp is what tips it; the clench is the corpse
        // The ground arrives WITH the fall, not eased under it — and bodyDrop inverts with the frame,
        // so the cramp's -0.30·crouch lifts the flipped body; the settle pays it back.
        self.settle = (deadRest(sk) * mathx.smoothstep(0.30, 0.54, u) - 0.30 * 0.35 * cramp * fall) * self.scale;
        self.armSpread = 46.0 * rearK - 30.0 * clench;
        self.armDrive = -0.4 * cramp - 0.5 * clench;
        self.bladeOpen = 0.9 * rearK - 0.6 * clench;
        self.abdoPump = 0.25 * rearK - 0.3 * clench;
        self.fangs = rearK;
        self.lift = 0;
        foe.dissipate(self, dt, DEATH_DUR, DISS_DUR, DISSOLVE);
    }
    /// Legs hold their standing stance (the coil, the landing) — the body moves, the feet do not.
    fn resolvePlanted(self: *Spider) void {
        self.armDrive = 0;
    }
    fn resolveFlung(self: *Spider, u: f32) void {
        _ = u;
        self.armDrive = 0.6;
    }


    pub fn pose(self: *Spider) void {
        const fs = self.scale * (1.0 - 0.8 * self.fade);
        const sink = -0.24 * self.scale * self.fade;
        // The BODY rides up and down on its legs (`crouch`) and tips its front up (`rear`) — the legs are placed off the same frame, so the whole animal squats over feet that stay where they were put.
        const bodyDrop = -self.crouch * 0.30;
        // …and the whole animal rides at whatever its own leg length can hold it at (see `rideDrop`), in WORLD units because the frame's translate happens after the scale.
        const ride = self.pos.y + self.lift + sink + self.settle - rideDrop(self.role) * fs;
        // The death KEEL: a barrel roll about the body's own long axis, hinged at BODY_Y, so the trunk spins in place and the legs sweep overhead. rz(0) makes it the exact identity — no living pose moves.
        const keel = mul3(tr(0, -BODY_Y, 0), rz(self.roll), tr(0, BODY_Y, 0));
        const frame = mul(
            mul(keel, scaleM(fs, fs, fs)),
            mul3(
                rx(self.pitch - self.rear * 22.0),
                ry(mathx.degrees(self.facing)),
                tr(self.pos.x, ride, self.pos.z),
            ),
        );
        const legFrame = mul(
            mul(keel, scaleM(fs, fs, fs)),
            mul3(ry(mathx.degrees(self.facing)), tr(0, 0, 0), tr(self.pos.x, ride, self.pos.z)),
        );

        const sk = skinOf(self.role);
        var wx: [NP]rl.Matrix = undefined;
        wx[CEPHALO] = mul(tr(0, bodyDrop, 0), frame);
        const pump = 1.0 + self.abdoPump;
        wx[ABDOMEN] = place(v3(P_PEDICEL.x, P_PEDICEL.y + bodyDrop, P_PEDICEL.z), mul(scaleM(pump, pump, pump), rx(-10.0 - 14.0 * self.abdoPump)), frame);

        for ([_]f32{ 1, -1 }, [_]usize{ ARM_L, ARM_R }, [_]usize{ BLADE_L, BLADE_R }) |sgn, ai, bi| {
            const sh = v3(sgn * P_SHOULDER.x, P_SHOULDER.y + bodyDrop, P_SHOULDER.z);
            const ph = self.elapsed * FLAIL_HZ + (if (sgn > 0) @as(f32, 0.0) else 1.9) + self.seed * 5.0;
            const wave = mathx.sinf(ph);
            const wave2 = mathx.sinf(ph * 1.37 + 0.7);
            // THE CLAWS ARE HELD UP, not out flat.
            const spread = self.armSpread + FLAIL_SPREAD * wave;
            const lift = sk.armLift + 0.55 * spread - 34.0 * self.armDrive + FLAIL_LIFT * wave2;
            wx[ai] = place(sh, mul3(rz(sgn * lift), ry(-sgn * spread * 0.7), rx(-14.0 * self.armDrive)), frame);
            // OPEN IS OPEN: 0 crosses the tips in front of her head, 1 throws them wide.
            wx[bi] = place(v3(sgn * P_WRIST.x, P_WRIST.y, P_WRIST.z), ry(sgn * (-8.0 + 46.0 * self.bladeOpen)), wx[ai]);
        }

        // EIGHT LEGS, two alternating tetrapods (see LEG_PHASE).
        for ([_]f32{ 1, -1 }, [_]usize{ 0, NLEG }) |sgn, base| {
            for (0..NLEG) |i| {
                const ph = self.gait + LEG_PHASE[i] + (if (sgn < 0) @as(f32, 0.5) else 0.0);
                const c = mathx.cosf(ph * std.math.tau);
                const s = mathx.sinf(ph * std.math.tau);
                const lift = mathx.maxF(0, s);
                const hip = v3(sgn * HIP_X, P_SHOULDER.y - 0.02 + bodyDrop, HIP_Z0 - @as(f32, @floatFromInt(i)) * HIP_DZ);
                const fan = 34.0 - @as(f32, @floatFromInt(i)) * 22.0;
                const swing = fan + c * STEP_SWING;
                const knee = KNEE_REST - 26.0 * lift - 16.0 * self.crouch;
                wx[FEMUR_0 + base + i] = place(hip, mul(ry(-sgn * swing), rz(-sgn * (STEP_LIFT * lift - 26.0 * self.crouch + CURL_FEMUR * self.legCurl))), legFrame);
                const kneeOff = v3(sgn * FEMUR_OUT * sk.legScale, FEMUR_UP * sk.legScale, 0);
                wx[TIBIA_0 + base + i] = place(kneeOff, rz(sgn * (knee * 0.42 + CURL_KNEE * self.legCurl)), wx[FEMUR_0 + base + i]);
            }
        }
        self.xf = wx;
    }

    pub fn draw(self: *const Spider, model: *const Model) void {
        model.draw(self.role, &self.xf, self.eyesHot());
    }
};


/// Room for a full posting of every role (`wf.MAX_PER_KIND` each), off the pinned run rather than a
/// hand-written 2 — a third age widens the array with it.
pub const CAP = ROLE_KIND.len * wf.MAX_PER_KIND;
/// How many times over a fight her clutch may be re-laid: `MAX_SACS` stand at once, and a finished slot
/// is reused, so the array only has to outlast the reuse (`addSac`) — not the whole fight.
const SAC_REUSE: usize = 8;
pub const SAC_CAP = MAX_SACS * SAC_REUSE;

pub const Brood = struct {
    model: Model,
    band: [CAP]Spider = undefined,
    n: usize = 0,
    sacs: [SAC_CAP]Sac = undefined,
    nsacs: usize = 0,
    pools: [POOL_CAP]Pool = [_]Pool{.{}} ** POOL_CAP,
    /// TWO EVENTS THE FRAME SHOULD FEEL, counted rather than flagged so game.zig edge-detects them the way it already does hits and kills — a bool would need somebody to remember to clear it.
    hatches: u32 = 0,
    bursts: u32 = 0,
    hatchRng: mathx.Rng = mathx.Rng.init(6113),

    pub fn init(shader: rl.Shader) Brood {
        return .{ .model = Model.init(shader) };
    }
    pub fn live(self: *Brood) []Spider {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Brood) []const Spider {
        return self.band[0..self.n];
    }
    pub fn liveSacs(self: *Brood) []Sac {
        return self.sacs[0..self.nsacs];
    }
    pub fn liveSacsConst(self: *const Brood) []const Sac {
        return self.sacs[0..self.nsacs];
    }
    /// THE SECOND LIST, under the foe standard's own name: everything this group keeps on the field BESIDES its members, and which is still a target. `game.eachTarget` asks for this decl and nothing else, so the lock-on, the melee mark, the aim ray and the HP bars all see the clutch without any of them naming the brood.
    pub fn liveExtraConst(self: *const Brood) []const Sac {
        return self.liveSacsConst();
    }

    pub fn reset(self: *Brood, m: *const wf.Map) void {
        self.clearSacs();
        // A CLUTCH THE MAP AUTHORED, standing before anything has laid it — a nest you walk into. Its own
        // pass, because `.brood_sac` is not one of the two ROLES and only the spiders go through the
        // shared reset.
        for (m.foes[0..m.nfoes]) |h| {
            if (h.kind != .brood_sac or self.nsacs >= SAC_CAP) continue;
            self.sacs[self.nsacs] = Sac.lay(v3(h.x, m.heightAt(h.x, h.z), h.z), h.seed, h.scale);
            self.nsacs += 1;
        }
        foe.resetRoles(Spider, Role, &self.band, &self.n, m, roleOf);
    }
    fn clearSacs(self: *Brood) void {
        self.nsacs = 0;
        self.hatches = 0;
        self.bursts = 0;
        self.pools = [_]Pool{.{}} ** POOL_CAP;
        self.hatchRng = mathx.Rng.init(6113);
    }
    pub fn clear(self: *Brood) void {
        self.n = 0;
        self.clearSacs();
    }

    /// A GLOB LANDED HERE — game.zig calls this the frame one of her shots stops, wherever it stopped.
    pub fn splash(self: *Brood, at: rl.Vector3) void {
        var oldest: usize = 0;
        for (&self.pools, 0..) |*p, i| {
            if (!p.live) {
                p.* = Pool.splash(at, @as(f32, @floatFromInt(i)) * 0.37 + at.x * 0.11);
                sfx.world(.acid_splash, at);
                return;
            }
            if (p.t > self.pools[oldest].t) oldest = i;
        }
        self.pools[oldest] = Pool.splash(at, at.x * 0.11 + at.z * 0.07);
        sfx.world(.acid_splash, at);
    }

    /// THE VENOM DOSE: how much POISON BUILDUP standing in her floor is worth this frame, 0 out of it.
    /// `combat.Status` owns the decay, so stepping out is answered one layer up and this side keeps no
    /// clock of its own to fall out of step with it (the sporeling cloud's rule, and the same reason).
    pub fn burn(self: *const Brood, dt: f32, hero: rl.Vector3) f32 {
        return if (self.burning(hero)) ACID_BUILD * dt else 0;
    }
    /// Is he in it at all? (The HUD tint and the hiss ride this, not the pulse.)
    pub fn burning(self: *const Brood, hero: rl.Vector3) bool {
        for (&self.pools) |*p| {
            if (p.covers(hero)) return true;
        }
        return false;
    }

    pub fn setShader(self: *Brood, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    /// THE HERO'S SHIELD, STAMPED ON EVERY MEMBER (`game.markParry`) — the leash's own pattern, and set before
    /// `update` so a window is read on the frame it is open rather than the one after. The SACS are not stamped:
    /// a membrane on the ground swings nothing.
    pub fn setParry(self: *Brood, p: foe.Parry) void {
        for (self.live()) |*s| s.parry = p;
    }
    /// …and whether any of them was caught on it this frame. A ONE-FRAME edge, `anyDied`'s, read after `update`.
    pub fn anyParried(self: *const Brood) bool {
        for (self.liveConst()) |*s| {
            if (s.parried) return true;
        }
        return false;
    }
    pub fn draw(self: *const Brood, scene: ?*gfx.Scene) void {
        // THE FLOOR FIRST — it is under everything else by definition.
        for (&self.pools) |*p| {
            if (p.live) rl.drawMesh(self.model.pool, self.model.mat, p.xform());
        }
        for (self.liveSacsConst()) |*s| {
            if (!s.alive()) continue;
            if (scene) |sc| sc.setFlash(foe.FLASH_GAIN * s.flashFrac());
            rl.drawMesh(if (s.killed or s.hatched) self.model.wreck else self.model.sac, self.model.mat, s.xform());
        }
        if (scene) |sc| sc.setFlash(0);
        for (self.liveConst()) |*s| {
            if (!s.alive()) continue;
            if (scene) |sc| sc.setFlash(foe.FLASH_GAIN * s.flashFrac());
            s.draw(&self.model);
        }
        if (scene) |sc| sc.setFlash(0);
    }
    pub fn drawFx(self: *const Brood) void {
        for (self.liveConst()) |*s| s.drawFx();
        for (self.liveSacsConst()) |*s| s.drawFx();
        for (&self.pools) |*p| p.drawFx();
    }

    pub fn pierce(self: *Brood, blade: foe.Blade) bool {
        for (self.liveSacs()) |*s| {
            if (!s.standing()) continue;
            const before = s.hits;
            s.tryHit(blade);
            if (s.hits != before) return true;
        }
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Brood) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn totalHits(self: *const Brood) u32 {
        var n: u32 = 0;
        for (self.liveConst()) |*s| n += s.hits;
        for (self.liveSacsConst()) |*s| n += s.hits;
        return n;
    }
    pub fn aliveCount(self: *const Brood) u32 {
        return foe.aliveCount(self.liveConst());
    }
    pub fn runesDropped(self: *const Brood) u32 {
        return foe.runesEach(self.liveConst());
    }

    /// How many of `m`'s sacs are still going to hatch — what her cap counts.
    fn standingFor(self: *const Brood, at: rl.Vector3) usize {
        var n: usize = 0;
        for (self.liveSacsConst()) |*s| {
            if (s.standing() and mathx.distXZ(s.pos, at) <= M_GUARD_R * 2.0) n += 1;
        }
        return n;
    }
    /// …and where they are, averaged — the thing she actually guards.
    fn clutchOf(self: *const Brood, at: rl.Vector3) ?rl.Vector3 {
        var sum = mathx.zero3;
        var n: f32 = 0;
        for (self.liveSacsConst()) |*s| {
            if (!s.standing() or mathx.distXZ(s.pos, at) > M_GUARD_R * 2.0) continue;
            sum = mathx.addV(sum, s.pos);
            n += 1;
        }
        if (n == 0) return null;
        return mathx.scaleV(sum, 1.0 / n);
    }

    fn addSac(self: *Brood, at: rl.Vector3, seed: f32, scale: f32) void {
        // Reuse a slot whose sac is finished before growing the list — a long fight lays a lot of eggs.
        for (self.liveSacs()) |*s| {
            if (s.gone) {
                s.* = Sac.lay(at, seed, scale);
                return;
            }
        }
        if (self.nsacs >= SAC_CAP) return;
        self.sacs[self.nsacs] = Sac.lay(at, seed, scale);
        self.nsacs += 1;
    }

    fn addBroodling(self: *Brood, at: rl.Vector3, faceYaw: f32, seed: f32) void {
        for (self.live()) |*s| {
            if (s.gone) {
                s.* = Spider.spawnAs(.broodling, at, faceYaw, 1.0, seed);
                return;
            }
        }
        if (self.n >= CAP) return;
        self.band[self.n] = Spider.spawnAs(.broodling, at, faceYaw, 1.0, seed);
        self.n += 1;
    }

    pub fn update(
        self: *Brood,
        dt: f32,
        hero: rl.Vector3,
        bounds: f32,
        blade: foe.Blade,
        ctx: anytype,
        comptime spit: fn (@TypeOf(ctx), rl.Vector3) void,
    ) ?foe.Blow {
        for (&self.pools) |*p| p.update(dt);
        // THE SACS next, so a clutch that split this frame is already on the field when she decides whether to lay another.
        var s: usize = 0;
        while (s < self.nsacs) : (s += 1) {
            const sac = &self.sacs[s];
            const at = sac.pos;
            const seed = sac.seed;
            const wasKilled = sac.killed;
            const split = sac.update(dt, blade);
            if (sac.killed and !wasKilled) self.bursts += 1;
            if (!split) continue;
            self.hatches += 1;
            var k: usize = 0;
            while (k < PER_SAC) : (k += 1) {
                const a = self.hatchRng.angle();
                const rr = self.hatchRng.range(0.35, 0.8);
                const born = v3(at.x + mathx.cosf(a) * rr, at.y, at.z + mathx.sinf(a) * rr);
                self.addBroodling(born, a, seed + @as(f32, @floatFromInt(k)) * 0.137);
                sfx.world(.brood_screech, born);
            }
        }

        for (self.live()) |*m| {
            if (m.role != .mother) continue;
            m.guard = self.clutchOf(m.pos);
            m.layWanted = self.standingFor(m.pos) < MAX_SACS;
        }

        var blow: ?foe.Blow = null;
        var i: usize = 0;
        while (i < self.n) : (i += 1) {
            const sp = &self.band[i];
            switch (sp.update(dt, hero, bounds, blade)) {
                .none => {},
                .spit => |from| spit(ctx, from),
                .lay => |at| self.addSac(at, sp.seed + sp.elapsed, sp.scale / M_SCALE),
            }
            if (sp.heroHit) |h| foe.worseBlow(&blow, h, sp.pos);
        }
        return blow;
    }
};


test "the roles ARE the map's foe kinds, by name" {
    try std.testing.expectEqual(Role.mother, roleOf(.brood_mother).?);
    try std.testing.expectEqual(Role.broodling, roleOf(.broodling).?);
    try std.testing.expectEqual(wf.FoeKind.brood_mother, kindOf(.mother));
    try std.testing.expect(roleOf(.toad) == null);
    try std.testing.expect(roleOf(.slinger) == null);
}

test "HER BITE IS AN INSTANT FROM BEING CAUGHT, and nothing else of hers is catchable at all" {
    try std.testing.expect(PARRY_LEAD > 0);
    // It is an INSTANT, not a slice of the tell: her 0.40 s gape must not be catchable for a third of itself.
    try std.testing.expect(PARRY_LEAD < BITE_WINDUP * 0.4);

    var m = Spider.spawnAs(.mother, mathx.ground(0, 0), 0, 1.0, 0.0);
    // MEASURED off the state machine: walk the bite from the first frame of its windup and collect the span
    // that is actually parryable, plus where the fangs actually arrive.
    const step = 1.0 / 600.0;
    var open: f32 = -1;
    var shut: f32 = -1;
    var elapsed: f32 = 0;
    m.throwing = false;
    while (elapsed <= BITE_WINDUP + BITE_SNAP) : (elapsed += step) {
        if (elapsed > BITE_WINDUP) { // the snap takes over, and its clock restarts
            m.state = .strike;
            m.t = elapsed - BITE_WINDUP;
        } else {
            m.state = .windup;
            m.t = elapsed;
        }
        if (m.parryable() != null) {
            if (open < 0) open = elapsed;
            shut = elapsed;
        }
    }
    try std.testing.expect(open > 0);
    // It ENDS at the snap — the frame `tryReach` fires — and it is exactly the lead long.
    try std.testing.expectApproxEqAbs(BITE_WINDUP, shut, 2.0 * step);
    try std.testing.expectApproxEqAbs(PARRY_LEAD, shut - open, 3.0 * step);

    // THE SPIT IS NOT A BLOW: it goes through the quiver like an arrow, so there is nothing to catch.
    m.throwing = true;
    m.state = .windup;
    m.t = SPIT_WINDUP - PARRY_LEAD * 0.5;
    try std.testing.expect(m.parryable() == null);
    // …nor is the lay, nor anything that is not a swing.
    m.throwing = false;
    for ([_]State{ .idle, .walk, .recover, .lay, .leap, .stunlight, .stunheavy, .dead }) |s| {
        m.state = s;
        m.t = 0;
        try std.testing.expect(m.parryable() == null);
    }
    // AND NOR IS A BROODLING, whatever it is doing: a window on something that arrives out of a sac and dies
    // to one slash is a mechanic nobody could read.
    var b = Spider.spawnAs(.broodling, mathx.ground(0, 0), 0, 1.0, 0.0);
    for ([_]State{ .windup, .strike, .leap }) |s| {
        b.state = s;
        b.t = B_BITE_WINDUP - PARRY_LEAD * 0.5;
        try std.testing.expect(b.parryable() == null);
    }
}

test "A CAUGHT BITE NEVER REACHES HIM, and the second catch is the punish window" {
    var m = Spider.spawnAs(.mother, mathx.ground(0, 0), 0, 1.0, 0.0); // faces +Z
    const hero = v3(0, 0, 1.4); // dead ahead, inside her fangs
    m.throwing = false;
    m.state = .windup;
    m.t = BITE_WINDUP - PARRY_LEAD * 0.5;
    // The boards up but pointed the WRONG WAY: nothing is caught (`foe.Parry` uses the block's own arc).
    m.parry = .{ .live = true, .at = hero, .facing = 0 };
    m.takeParry();
    try std.testing.expect(!m.parried and m.state == .windup); // the fangs keep coming
    // …and squared onto her it is caught. Her stance is 46, so one catch is exactly enough to break it.
    m.parry = .{ .live = true, .at = hero, .facing = std.math.pi }; // hero faces -Z, i.e. at her
    m.takeParry();
    try std.testing.expect(m.parried);
    try std.testing.expect(m.state == .stunlight or m.state == .stunheavy);
    try std.testing.expect(!m.heroLatch); // …and the snap it never got to is re-armed, not spent
    try std.testing.expect(m.biteCd > 0); // the bite has to be gathered again before she throws it twice
}

test "SHE HOLDS THE CLUTCH: past her guard radius she stops closing and spits" {
    try std.testing.expect(M_SPIT_MAX + 2 < M_AGGRO);
    try std.testing.expectEqual(MChoice.hold, classifyMother(M_SPIT_MAX + 2,M_GUARD_R + 1, true, true, false));
    try std.testing.expectEqual(MChoice.spit, classifyMother(M_SPIT_MAX - 1, M_GUARD_R + 1, true, true, false));
    try std.testing.expectEqual(MChoice.close, classifyMother(M_SPIT_MAX + 2,1.0, true, true, false));
}

test "her order of business: teeth first, then eggs, then the spit" {
    try std.testing.expectEqual(MChoice.bite, classifyMother(M_BITE_R - 0.2, 0, true, true, true));
    try std.testing.expectEqual(MChoice.close, classifyMother(M_BITE_R * 1.2, 0, false, false, true));
    try std.testing.expectEqual(MChoice.lay, classifyMother(8.0, 0, true, true, true));
    try std.testing.expectEqual(MChoice.spit, classifyMother(8.0, 0, true, true, false));
    try std.testing.expectEqual(MChoice.close, classifyMother(M_SPIT_MIN - 0.5, 0, true, true, false));
    try std.testing.expectEqual(MChoice.hold, classifyMother(M_AGGRO + 1, 0, true, true, true));
}

test "range bands are ordered and sit inside her senses" {
    try std.testing.expect(M_BITE_R < M_SPIT_MIN);
    try std.testing.expect(M_SPIT_MIN < M_SPIT_MAX);
    try std.testing.expect(M_SPIT_MAX < M_AGGRO);
    try std.testing.expect(B_BITE_R < B_LEAP_MIN);
    try std.testing.expect(B_LEAP_MIN < B_LEAP_MAX);
    try std.testing.expect(B_LEAP_MAX < B_AGGRO);
}

test "A HATCHLING IS WIMPY AND FAST, and she is neither" {
    const light = heromod.ATK_LIGHT_HIT;
    try std.testing.expect(B_HP > light.dmg and B_HP <= light.dmg * 2);
    try std.testing.expect(B_HP < heromod.ATK_HEAVY_HIT.dmg);
    try std.testing.expect(B_POISE < light.poise);
    try std.testing.expect(M_POISE > light.poise);
    // A HATCHLING BARELY HURTS (owner's call): it is a thing that takes your attention, not your bar.
    try std.testing.expect(B_LEAP_HIT.dmg > B_BITE_HIT.dmg);
    try std.testing.expect(B_LEAP_HIT.dmg < heromod.HP_MAX * 0.1);
    // SHE CANNOT MOVE QUICKLY (owner's rule): slower than the hero's WALK, where they outrun it.
    try std.testing.expect(M_SPEED < heromod.WALK_SPEED);
    try std.testing.expect(B_SPEED > heromod.WALK_SPEED);
    try std.testing.expect(B_SPEED > M_SPEED * 2.0);
}

test "the broodling pounces only from its band, and bites what is on top of it" {
    try std.testing.expectEqual(BChoice.leap, classifyBroodling((B_LEAP_MIN + B_LEAP_MAX) * 0.5, true, true));
    try std.testing.expectEqual(BChoice.chase, classifyBroodling((B_LEAP_MIN + B_LEAP_MAX) * 0.5, false, true));
    try std.testing.expectEqual(BChoice.chase, classifyBroodling(B_LEAP_MAX + 2, true, true));
    try std.testing.expectEqual(BChoice.bite, classifyBroodling(B_BITE_R - 0.1, true, true));
    try std.testing.expectEqual(BChoice.idle, classifyBroodling(B_AGGRO + 1, true, true));
}

test "A SAC RIPENS, THEN SPLITS — and a cut one never does" {
    var s = Sac.lay(mathx.ground(0, 0), 0.5, 1.0);
    try std.testing.expect(s.standing());
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.swell(), 1e-5);
    var t: f32 = 0;
    var split = false;
    while (t < SAC_HATCH - 0.1) : (t += 1.0 / 60.0) {
        if (s.update(1.0 / 60.0, .{})) split = true;
    }
    try std.testing.expect(!split);
    try std.testing.expect(s.swell() > 0.95);
    while (t < SAC_HATCH + 0.2) : (t += 1.0 / 60.0) {
        if (s.update(1.0 / 60.0, .{})) split = true;
    }
    try std.testing.expect(split);
    try std.testing.expect(!s.standing());

    // THE POINT OF SHOOTING ONE: killed, it hatches nothing, ever.
    var k = Sac.lay(mathx.ground(0, 0), 0.5, 1.0);
    const shaft = foe.Blade{
        .active = true,
        .pierce = true,
        .r = 0.3,
        .a = mathx.addV(k.centerWorld(), v3(0, 0, 1)),
        .b = mathx.addV(k.centerWorld(), v3(0, 0, -0.1)),
        .hit = .{ .dmg = SAC_HP + 1 },
    };
    k.tryHit(shaft);
    try std.testing.expect(k.killed);
    try std.testing.expect(!k.standing());
    t = 0;
    while (t < SAC_HATCH * 2) : (t += 1.0 / 60.0) {
        try std.testing.expect(!k.update(1.0 / 60.0, .{}));
    }
    try std.testing.expect(!k.hatched);
}

test "A SAC IS A TARGET, and answers everything a target has to answer" {
    var s = Sac.lay(mathx.ground(0, 0), 0.5, 1.0);
    try std.testing.expectEqual(wf.FoeKind.brood_sac, s.kind());
    try std.testing.expect(s.alive() and !s.dying() and !s.staggered());
    try std.testing.expect(s.lockPoint().y > s.pos.y);
    try std.testing.expect(s.topWorld().y > s.lockPoint().y);
    try std.testing.expect(s.bodyR() > 0);
    try std.testing.expect(s.hurtRadius() > SAC_R);
    s.killed = true;
    try std.testing.expect(s.dying());
}

test "A STRUCK SAC'S BAR GOES AWAY AGAIN — its vitals actually run" {
    // THE bug: `Sac.update` was the one `combat.Vitals` owner in the game that never ticked, so its clocks stayed pinned at 0 after the first blow and `game.drawFoeBars`' recent-hit window — which is a `sinceHurt` test — never closed again.
    var s = Sac.lay(mathx.ground(0, 0), 0.5, 1.0);
    try std.testing.expect(s.vit.sinceHurt > 100.0); // never hit: no bar
    s.tryHit(.{
        .active = true,
        .pierce = true,
        .r = 0.3,
        .a = mathx.addV(s.centerWorld(), v3(0, 0, 1)),
        .b = mathx.addV(s.centerWorld(), v3(0, 0, -0.1)),
        .hit = heromod.ATK_LIGHT_HIT,
    });
    try std.testing.expect(s.standing() and s.vit.sinceHurt == 0);
    var t: f32 = 0;
    while (t < 1.0) : (t += 1.0 / 60.0) _ = s.update(1.0 / 60.0, .{});
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), s.vit.sinceHurt, 0.05);
}

test "a hatchling's recovery is its OWN length, not its mother's" {
    // `resolveRecover` scales the pose to `recoverDur`, and the state exits on the same number — given the mother's 0.50 s a broodling played half a recovery and then snapped to idle.
    var b = Spider.spawnAs(.broodling, mathx.ground(0, 0), 0, 1.0, 0.4);
    try std.testing.expectApproxEqAbs(B_BITE_RECOVER, b.recoverDur(), 1e-6);
    var m = Spider.spawnAs(.mother, mathx.ground(0, 0), 0, 1.0, 0.4);
    try std.testing.expectApproxEqAbs(BITE_RECOVER, m.recoverDur(), 1e-6);
    m.throwing = true; // …and hers still splits by which attack she is coming out of
    try std.testing.expectApproxEqAbs(SPIT_RECOVER, m.recoverDur(), 1e-6);
}

test "a sac takes a few blows, not one — it is a target, not a balloon" {
    var s = Sac.lay(mathx.ground(0, 0), 0.5, 1.0);
    const light = foe.Blade{
        .active = true,
        .pierce = true,
        .r = 0.3,
        .a = mathx.addV(s.centerWorld(), v3(0, 0, 1)),
        .b = mathx.addV(s.centerWorld(), v3(0, 0, -0.1)),
        .hit = heromod.ATK_LIGHT_HIT,
    };
    s.tryHit(light);
    try std.testing.expect(!s.killed);
    try std.testing.expect(s.standing());
    s.tryHit(light);
    try std.testing.expect(s.killed);
}

test "THE GLOB IS NOT THE WEAPON, THE METER IS: a hit is cheap, standing in it is not" {
    try std.testing.expect(M_SPIT_HIT.raw() < M_BITE_HIT.raw() * 0.15); // it barely scratches…
    try std.testing.expect(M_SPIT_HIT.stance == 0);
    // …and what it really does is fill the bar: three globs go off, so a mother left to spit is a clock.
    try std.testing.expect(M_SPIT_BUILD * 3.0 >= combat.POISON_MAX);
    try std.testing.expect(M_SPIT_BUILD * 2.0 < combat.POISON_MAX);
    // THE FLOOR IS FASTER THAN THE GLOB: a pool is a place you leave, not one you trade hits from.
    try std.testing.expect(ACID_BUILD > M_SPIT_BUILD * 0.8);
    try std.testing.expect(combat.POISON_MAX / ACID_BUILD < 3.0); // under three seconds of standing in it
}

test "HER VENOM IS ONE FLUID: the spit and the puddle fill the SAME meter" {
    var psn = combat.Status{};
    psn.add(M_SPIT_BUILD);
    const oneGlob = psn.frac();
    try std.testing.expect(oneGlob > 0.3 and !psn.active());
    // Two more of them and it goes off, the floor having done nothing at all.
    psn.add(M_SPIT_BUILD);
    psn.add(M_SPIT_BUILD);
    _ = psn.tick(1.0 / 60.0, 70);
    try std.testing.expect(psn.active());

    // …and the pool alone gets there too, in its own two and a half seconds.
    var b = Brood{ .model = undefined };
    b.clear();
    const at = mathx.ground(0, 0);
    b.pools[0] = Pool.splash(at, 0.5);
    var t: f32 = 0;
    while (t < ACID_SPREAD * 2) : (t += 1.0 / 60.0) b.pools[0].update(1.0 / 60.0);
    var floor = combat.Status{};
    t = 0;
    while (t < 3.0 and !floor.active()) : (t += 1.0 / 60.0) {
        floor.add(b.burn(1.0 / 60.0, at));
        _ = floor.tick(1.0 / 60.0, 70);
    }
    try std.testing.expect(floor.active());
    try std.testing.expect(t < 3.0);
}

test "A FIRE ARROW IS FOR THE CLUTCH: silk burns where the mother mostly shrugs it off" {
    const tipped = heromod.fireTipped(heromod.BOW_AIMED_HIT);
    var sac = Sac.lay(mathx.ground(0, 0), 0.5, 1.0);
    var mother = Spider.spawnAs(.mother, mathx.ground(0, 0), 0, 1.0, 0.5);
    try std.testing.expect(sac.vit.damageFrom(tipped) > mother.vit.damageFrom(tipped));
    try std.testing.expectApproxEqAbs(sac.vit.damageFrom(heromod.BOW_AIMED_HIT), mother.vit.damageFrom(heromod.BOW_AIMED_HIT), 1e-5);
    // She is proof against her OWN weapon, at the cap — a pool she laid cannot take her with it.
    try std.testing.expectApproxEqAbs(combat.RES_CAP, mother.vit.res.at(.chaos), 1e-5);
}

test "a pool spreads, DOSES while he stands in it, thins out and stops" {
    var b = Brood{ .model = undefined };
    b.clear();
    const at = mathx.ground(0, 0);
    b.pools[0] = Pool.splash(at, 0.5);
    try std.testing.expect(b.pools[0].radius() < ACID_R);
    var t: f32 = 0;
    while (t < ACID_SPREAD * 2) : (t += 1.0 / 60.0) b.pools[0].update(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(ACID_R, b.pools[0].radius(), 1e-4);
    try std.testing.expect(b.burning(at));
    try std.testing.expect(!b.burning(mathx.ground(ACID_R + 1, 0)));

    // A CONTINUOUS DOSE, not a metronome: every frame in it is worth its own slice of a second.
    var dosed: f32 = 0;
    t = 0;
    while (t < 1.0) : (t += 1.0 / 60.0) dosed += b.burn(1.0 / 60.0, at);
    try std.testing.expectApproxEqAbs(ACID_BUILD, dosed, 0.7);
    // …and out of it, nothing.
    try std.testing.expectEqual(@as(f32, 0), b.burn(1.0 / 60.0, mathx.ground(50, 50)));

    t = 0;
    while (t < ACID_LIFE + 0.2) : (t += 1.0 / 60.0) b.pools[0].update(1.0 / 60.0);
    try std.testing.expect(!b.pools[0].burning());
    try std.testing.expectEqual(@as(f32, 0), b.burn(1.0, at));
}

test "she cannot outstay her own leash, and one shaft still rouses her" {
    var m = Spider.spawnAs(.mother, mathx.ground(0, 0), 0, 1.0, 0.3);
    try std.testing.expect(!m.leash.roused());
    const shaft = foe.Blade{
        .active = true,
        .pierce = true,
        .r = 0.3,
        .a = mathx.addV(m.centerWorld(), v3(0, 0, 2)),
        .b = mathx.addV(m.centerWorld(), v3(0, 0, -0.2)),
        .hit = .{ .dmg = 5 },
    };
    m.tryHit(shaft);
    try std.testing.expect(m.hits == 1);
    try std.testing.expect(m.leash.roused());
}

test "NO ATTACK COMES OUT OF NOWHERE: both ages telegraph before they can hurt" {
    // Her spit and her bite are long, obvious tells.
    try std.testing.expect(SPIT_WINDUP >= foe.TELL_MIN);
    try std.testing.expect(BITE_WINDUP >= foe.TELL_MIN);
    // THE HATCHLING IS THE FAST ONE and it is the one this law is really about: it reared and bit inside
    // 0.29 s, which is under what an eye resolves.
    try std.testing.expect(B_BITE_WINDUP >= foe.TELL_MIN);
    // …and the pounce coils on the spot first, which is what makes it answerable.
    try std.testing.expect(B_LEAP_COIL >= foe.TELL_MIN);
    // The mother still telegraphs HARDER than her young, or the two read as one creature.
    try std.testing.expect(BITE_WINDUP > B_BITE_WINDUP);
}
