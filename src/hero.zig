const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;
const radians = mathx.radians;

// ── THE HERO ────────────────────────────────────────────────────────────────────────
// A fully articulated human, proportioned from real anthropometry and animated with a
// real gait cycle. Two things make him read as HUMAN rather than a mannequin:
//
//  1. ANATOMY. Every bone length is a fixed fraction of stature H, taken from the
//     Drillis & Contini (1966) body-segment table as tabulated in Winter, "Biomechanics
//     and Motor Control of Human Movement" — copied verbatim below. This is why the
//     half-way point of the body sits at the pubis, the elbow at the navel, etc.
//
//  2. GAIT. The legs are driven by normative sagittal-plane joint-angle curves (hip,
//     knee, ankle over one stride) after Perry, "Gait Analysis" / Winter's normative
//     kinematics — with contralateral arm swing, a twice-per-stride vertical pelvis bob,
//     once-per-stride lateral sway, and pelvic transverse rotation with torso counter-
//     rotation. These are the invariants of human walking, not eyeballed keyframes.
//
// Rendering: a forward-kinematics skeleton. Each bone is a small procedural mesh authored
// in its joint's local frame; per frame `pose()` chains matrices down the hierarchy to a
// world matrix per bone, and `draw()` replays them. Depth pass and lit pass call the same
// `draw()`, so the cast shadow always matches the lit silhouette.

pub const H: f32 = 1.8; // stature (world units ≈ metres)

// Body-segment lengths as a fraction of stature H (Drillis & Contini 1966; Winter).
// Reference joint HEIGHTS off the floor these imply, for sanity: ankle .039, knee .285,
// hip(trochanter) .530, wrist .485, elbow .630, shoulder(acromion) .818, chin .870,
// crown 1.0 — each below is the difference between two of these.
const SEG_THIGH = 0.245; // hip → knee   (femur)   .530-.285
const SEG_SHANK = 0.246; // knee → ankle (tibia)   .285-.039
const SEG_UPARM = 0.188; // shoulder → elbow        .818-.630
const SEG_FOREARM = 0.145; // elbow → wrist         .630-.485
const BREADTH_SHOULDER = 0.259; // biacromial breadth
const BREADTH_HIP = 0.191; // bi-iliac / bitrochanteric breadth

// Skeleton joints (indices). Every joint owns exactly one drawn bone mesh.
const N = 17;
const ROOT = 0; // pelvis
const SPINE = 1; // lumbar / mid-torso pivot
const CHEST = 2; // thorax / shoulder girdle
const NECK = 3;
const HEAD = 4;
const HIPL = 5;
const KNEEL = 6;
const ANKL = 7;
const HIPR = 8;
const KNEER = 9;
const ANKR = 10;
const SHL = 11; // shoulder L
const ELL = 12; // elbow L
const WRL = 13; // wrist L
const SHR = 14;
const ELR = 15;
const WRR = 16;

const parent = [N]i32{ -1, ROOT, SPINE, CHEST, NECK, ROOT, HIPL, KNEEL, ROOT, HIPR, KNEER, CHEST, SHL, ELL, CHEST, SHR, ELR };

// Rest positions in the hero's local standing frame (X = hero's left/+, Y up, Z forward),
// in world units. Limbs hang straight down so each bone mesh aligns with -Y; the small
// A-pose splay and stance width come from constant abduction in the pose, not the rest
// pose (so a bone mesh and its child joint never separate).
fn restPositions() [N]rl.Vector3 {
    const hx = 0.090; // hip half-separation (a touch under BREADTH_HIP/2 so the stance isn't splayed)
    const sx = 0.150; // shoulder half-separation (~BREADTH_SHOULDER/2, plus pauldron room)
    var r: [N]rl.Vector3 = undefined;
    r[ROOT] = v3(0, 0.530, 0);
    r[SPINE] = v3(0, 0.640, 0);
    r[CHEST] = v3(0, 0.760, 0);
    r[NECK] = v3(0, 0.815, 0); // neck base sits just at the shoulder line…
    r[HEAD] = v3(0, 0.885, 0); // …head raised a touch so a real neck shows (crown ≈ 1.02 H)
    r[HIPL] = v3(hx, 0.530, 0);
    r[KNEEL] = v3(hx, 0.285, 0);
    r[ANKL] = v3(hx, 0.039, 0);
    r[HIPR] = v3(-hx, 0.530, 0);
    r[KNEER] = v3(-hx, 0.285, 0);
    r[ANKR] = v3(-hx, 0.039, 0);
    r[SHL] = v3(sx, 0.818, 0);
    r[ELL] = v3(sx, 0.630, 0);
    r[WRL] = v3(sx, 0.485, 0);
    r[SHR] = v3(-sx, 0.818, 0);
    r[ELR] = v3(-sx, 0.630, 0);
    r[WRR] = v3(-sx, 0.485, 0);
    for (&r) |*p| p.* = v3(p.x * H, p.y * H, p.z * H);
    return r;
}

// ── palette (pre-gamma dark: the scene shader gammas output, so these lift a lot) ──────
// A worn Tarnished: dark iron-blue wool under oxblood leather, a faded crimson tabard and
// short cape, steel at the guard/pauldron, brass at buckle and pommel.
const SKIN = rgba(150, 112, 86, 255);
const SKIN_DK = rgba(120, 88, 66, 255);
const TUNIC = rgba(38, 40, 50, 255); // dark iron-blue wool
const TUNIC_DK = rgba(28, 30, 38, 255);
const LEATHER = rgba(58, 39, 26, 255); // oxblood-brown pauldron/bracer leather
const LEATHER_DK = rgba(38, 26, 18, 255);
const CLOTHDK = rgba(44, 39, 32, 255); // umber trousers
const BOOT = rgba(24, 22, 20, 255); // near-black boots/gloves
const BELT = rgba(34, 26, 18, 255);
const HAIR = rgba(40, 31, 24, 255); // warm dark brown
const CAPE = rgba(82, 20, 12, 255); // faded oxblood-crimson cloth
const STEEL = rgba(98, 104, 114, 255);
const STEEL_DK = rgba(58, 62, 70, 255);
const BRASS = rgba(122, 92, 40, 255);

// ══ ANIMATION ART DIRECTION — the DESIRED LOOK of each state (read before retuning) ══════
// These are the intent; the numeric knobs below are only tuned to hit them. If you change a
// knob, keep it serving the description — and update the description if the intent changes.
//
//  IDLE   : upright, still, but alive — only a slow breathing bob + faint weight settle.
//           No limb motion. Reads "at rest, ready."
//  WALK   : unhurried, grounded, calm. Near-upright torso (~3° lean). RESTRAINED arms — a
//           small swing, the rear arm nearly straight (never both forearms out front, the
//           "zombie arms" failure). LOW hip sway (no waddle). Clear heel→toe stride with a
//           readable knee bend. Feet toe-out slightly; head carries a gentle downward gaze.
//  RUN    : low and aggressive. DEEP forward lean over a LOW centre of gravity (pelvis
//           crouched), the WHOLE body pitched forward about the feet so the COG leads the
//           base — driving, coiled. The HEAD lifts so the gaze lands a few metres AHEAD
//           (~20° down) — off the floor, but NOT craned level/up (capped, natural neck).
//           NORMAL pumping arms bent ~90° (explicitly NOT
//           swept-back "naruto" arms — that was tried and rejected). A real flight phase
//           (both feet airborne) via an up-only bounce; big swing-knee flexion.
//  SPRINT : the run dialled up — even deeper forward tilt (near-diving), lower, longer
//           stride, faster turnover. "Falling forward and catching it."
//  ROLL   : a committed dodge — crouch into a tight tuck, ONE full forward somersault about
//           a low ball centre, ease back out to a stand. Fast ease-out lunge in the roll
//           direction. Snappy, no float/hang.
//  Blends : idle↔walk by a `moving` ease; walk↔run↔sprint by ground SPEED (runB/sprintB).
//           Stride LENGTH scales with speed so one leg-cycle reads at every pace.
//
// ── gait: normative sagittal joint angles over one stride, sampled every 12.5% (deg) ──
// phase 0 = heel strike of that leg; stance ≈ 0..0.60, swing ≈ 0.60..1.0.
// hip: +flexion (thigh forward). knee: +flexion (bend). ankle: +dorsiflexion (toe up).
const HIP_FLEX = [8]f32{ 25, 13, 3, -5, -10, -3, 12, 22 };
const KNEE_FLEX = [8]f32{ 5, 18, 10, 4, 10, 38, 62, 30 };
const ANK_DORSI = [8]f32{ -2, -6, 2, 9, 6, -14, -6, -1 };

// ── running gait (a distinct cycle, not a sped-up walk) ────────────────────────────
// Sagittal joint angles after Novacheck, "The biomechanics of running" (Gait & Posture
// 1998) and Physiopedia's running-biomechanics normatives: much larger ranges than
// walking, forefoot contact, stance ≈ 40% (toe-off near phase 0.4), a big swing-knee
// flexion (heel toward buttock), and a genuine flight phase (both feet airborne).
const RUN_HIP = [8]f32{ 42, 25, 8, -8, 5, 35, 60, 55 };
const RUN_KNEE = [8]f32{ 26, 48, 40, 28, 62, 98, 80, 44 }; // deeper bend throughout — coiled + low
const RUN_ANK = [8]f32{ -3, 10, 22, 2, -18, -6, 0, -2 };
// The run reads low + aggressive: a deep forward tilt over a low centre of gravity, with
// normal pumping arms (bent ~90°).
const RUN_LEAN = 24.0; // deep forward trunk lean when running (deg)
const RUN_ARM_SWING = 30.0; // shoulder swing amplitude when running (deg)
const RUN_ELBOW = 85.0; // elbows bent ~90° and pumping
const RUN_CROUCH = 0.06 * H; // pelvis drops — a low centre of gravity
const BODY_PITCH_RUN = 9.0; // whole-body forward pitch about the FEET at run — moves the centre of gravity ahead of the base
const BODY_PITCH_SPRINT = 18.0; // …more at sprint (falling-forward drive)
const HEAD_WALK = 7.0; // gentle downward head tilt at idle/walk — a natural "looking a few steps ahead" gaze
const GAZE_AHEAD = 15.0; // running: counter the lean down to ~this chain angle; final gaze ≈ GAZE_AHEAD+HEAD_WALK below horizontal (a few metres ahead), never craned up
const NECK_EXT_MAX = 34.0; // cap total head+neck extension so lifting the gaze can't hyperextend the neck
const A_RUN_BOUNCE = 0.05 * H; // vertical airtime lift during flight (up-only, so planted feet don't sink)
const RUN_SPEED_LO = 2.1; // blend walk→run across this ground-speed band
const RUN_SPEED_HI = 3.2;
const SPRINT_LEAN = 40.0; // near-horizontal forward tilt at full sprint (deg)
const SPRINT_REF_SPEED = 4.6; // speed the extra sprint lean/crouch saturate at (mirrors game.SPRINT_SPEED)

// ── dodge roll (committed tuck-and-somersault) ────────────────────────────────────
const ROLL_DUR = 0.60; // seconds, start to finish
const ROLL_DIST = 2.8; // ground units travelled (ease-out velocity profile)
const ROLL_BALL_Y = 0.50; // pelvis/pivot height at mid-roll (the tucked "ball" centre)
const ROLL_HIP = 95.0; // tuck: thighs to chest (deg)
const ROLL_KNEE = 115.0; // tuck: heels toward glutes (deg)
const ROLL_SPINE = 30.0; // forward spine curl per segment (deg)
const ROLL_HEAD = 32.0; // chin to chest (deg)
const ROLL_SHOULDER = 45.0; // arms tuck forward (deg)
const ROLL_ELBOW = 100.0; // elbows tucked (deg)

const STRIDE = 0.85 * H; // ground distance per full (two-step) cycle at walk pace — ties phase to travel, no foot-skate
const WALK_REF_SPEED = 1.7; // reference walk speed the stride is tuned for (mirrors game.WALK_SPEED)
const ARM_SWING = 9.0; // shoulder flex amplitude (deg) at walk — restrained, contralateral to the legs
const A_BOB = 0.024 * H; // vertical pelvis travel (peak-to-peak ~ realistic 4-5 cm at H=1.8)
const A_SWAY = 0.009 * H; // lateral pelvis sway toward the stance foot (subtle — no waddle)
const A_PROT = 3.5; // pelvic transverse rotation (deg)
const A_LIST = 2.0; // pelvic frontal drop toward the swing leg (deg)
const TORSO_LEAN = 3.0; // forward torso lean while walking (deg) — walking is near-upright
const HIP_ADDUCT = 2.0; // constant leg-toward-midline angle so the stance narrows (deg)
const FOOT_TOEOUT = 6.0; // feet splay slightly outward (Fick angle) — a real standing/gait detail
const ARM_ABD = 9.0; // constant arm abduction so arms clear the torso (deg)
const IDLE_KNEE = 4.0;
const IDLE_ELBOW = 6.0;

fn sampleCurve(tbl: [8]f32, phase: f32) f32 {
    const ph = phase - @floor(phase); // 0..1
    const t = ph * 8.0;
    const base: usize = @intFromFloat(@floor(t));
    const a = base % 8;
    const b = (base + 1) % 8;
    const f = t - @floor(t);
    return tbl[a] + (tbl[b] - tbl[a]) * f;
}

// matrix shorthand — MatrixMultiply(a,b) applies a FIRST then b (raylib TRS convention).
fn rx(deg: f32) rl.Matrix {
    return rl.math.matrixRotateX(radians(deg));
}
fn ry(deg: f32) rl.Matrix {
    return rl.math.matrixRotateY(radians(deg));
}
fn rz(deg: f32) rl.Matrix {
    return rl.math.matrixRotateZ(radians(deg));
}
fn tr(x: f32, y: f32, z: f32) rl.Matrix {
    return rl.math.matrixTranslate(x, y, z);
}
fn mul(a: rl.Matrix, b: rl.Matrix) rl.Matrix {
    return rl.math.matrixMultiply(a, b);
}
fn mul3(a: rl.Matrix, b: rl.Matrix, c: rl.Matrix) rl.Matrix {
    return mul(mul(a, b), c);
}

pub const Hero = struct {
    mesh: [N]rl.Mesh,
    mat: rl.Material,
    rest: [N]rl.Vector3,
    xf: [N]rl.Matrix = undefined, // per-bone world matrix, recomputed each frame by pose()

    // gameplay/anim state
    pos: rl.Vector3 = mathx.zero3, // feet on Y=0
    facing: f32 = 0, // yaw radians, 0 = +Z
    phase: f32 = 0, // stride phase [0,1) (left-leg reference)
    moving: f32 = 0, // eased 0..1 walk blend
    speed: f32 = 0, // this frame's ground speed (world units/sec) — for HUD + stride scaling
    elapsed: f32 = 0,
    // dodge roll
    rolling: bool = false,
    rollT: f32 = 0, // seconds into the current roll
    rollDir: rl.Vector3 = mathx.zero3, // world XZ unit direction of the roll

    pub fn init(shader: rl.Shader) Hero {
        var mat = rl.loadMaterialDefault() catch @panic("hero material");
        mat.shader = shader;
        return .{
            .mesh = buildMeshes(),
            .mat = mat,
            .rest = restPositions(),
        };
    }

    pub fn setShader(self: *Hero, sh: rl.Shader) void {
        self.mat.shader = sh;
    }

    // Advance the walk. `movedDist` = ground distance travelled this frame; `speed` its
    // rate. Phase is driven by DISTANCE (not time) so the feet never skate.
    pub fn update(self: *Hero, dt: f32, movedDist: f32, speed: f32) void {
        self.elapsed += dt;
        self.speed = speed;
        const target: f32 = if (speed > 0.05) 1.0 else 0.0;
        self.moving = mathx.approach(self.moving, target, dt * 4.0);
        if (movedDist > 0) {
            // Longer strides at higher speed (as people do), so run/sprint reuse this walk
            // cycle at a believable cadence instead of a frantic shuffle.
            const strideLen = STRIDE * mathx.clampF(0.55 + 0.45 * speed / WALK_REF_SPEED, 0.8, 2.0);
            self.phase += movedDist / strideLen;
        }
        self.phase -= @floor(self.phase);
    }

    // Begin a dodge roll in world direction `dir` (falls back to current facing). Ignored
    // while already rolling — rolls are committed.
    pub fn startRoll(self: *Hero, dir: rl.Vector3) void {
        if (self.rolling) return;
        var d = v3(dir.x, 0, dir.z);
        if (mathx.lenXZ(d) < 0.1) d = v3(mathx.sinf(self.facing), 0, mathx.cosf(self.facing));
        d = mathx.normV(d);
        self.rolling = true;
        self.rollT = 0;
        self.rollDir = d;
        self.facing = std.math.atan2(d.x, d.z); // snap to the roll heading
    }

    // Advance an in-progress roll: committed ease-out travel + pose. Call in place of the
    // normal move/update while `rolling` is true; `bounds` clamps position like moveHero.
    pub fn updateRoll(self: *Hero, dt: f32, bounds: f32) void {
        self.elapsed += dt;
        const u = mathx.clampF(self.rollT / ROLL_DUR, 0, 1);
        const speed = ROLL_DIST * 2.0 * (1.0 - u) / ROLL_DUR; // ease-out: fast launch, glide to stop
        const moved = speed * dt;
        self.pos.x = mathx.clampF(self.pos.x + self.rollDir.x * moved, -bounds, bounds);
        self.pos.z = mathx.clampF(self.pos.z + self.rollDir.z * moved, -bounds, bounds);
        self.speed = speed;
        self.moving = 1;
        self.rollT += dt;
        if (self.rollT >= ROLL_DUR) self.rolling = false;
        self.pose();
    }

    // Compute every bone's world matrix for this frame's pose. Call once before drawing.
    pub fn pose(self: *Hero) void {
        if (self.rolling) return self.poseRoll();
        const m = self.moving;
        const ph = self.phase;
        const twoPi = std.math.tau;
        // Walk→run blend from ground speed; run curves/posture fade in across the band.
        // sprintB adds extra lean/crouch past full run.
        const runB = mathx.clampF((self.speed - RUN_SPEED_LO) / (RUN_SPEED_HI - RUN_SPEED_LO), 0, 1);
        const sprintB = mathx.clampF((self.speed - RUN_SPEED_HI) / (SPRINT_REF_SPEED - RUN_SPEED_HI), 0, 1);
        const crouch = (RUN_CROUCH * runB + 0.5 * RUN_CROUCH * sprintB) * m; // low centre of gravity

        // ── pelvis oscillations (walk bob ↔ run airtime bounce) ──
        const walkBob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * ph); // twice/stride, symmetric
        const runBounce = A_RUN_BOUNCE * (0.5 - 0.5 * mathx.cosf(2.0 * twoPi * (ph - 0.2))); // up-only, peaks at flight
        const bob = mathx.lerpF(walkBob, runBounce, runB) * m + 0.006 * H * mathx.sinf(self.elapsed * 2.2) * (1.0 - m);
        const sway = A_SWAY * mathx.sinf(twoPi * ph) * m * (1.0 - 0.6 * runB); // running tracks narrower
        const prot = A_PROT * mathx.sinf(twoPi * ph) * m; // pelvic transverse rotation
        const list = A_LIST * mathx.sinf(twoPi * ph) * m; // pelvic frontal drop

        // Root: place at world pos, at hip height (crouched when running), swayed/bobbed in
        // body frame, PITCHED FORWARD ABOUT THE FEET (so the centre of gravity leads the
        // base — the driving, falling-forward run), then faced.
        const facingDeg = self.facing * 180.0 / std.math.pi;
        const hipY = self.rest[ROOT].y;
        const bodyPitch = (BODY_PITCH_RUN * runB + (BODY_PITCH_SPRINT - BODY_PITCH_RUN) * sprintB) * m;
        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            mul(rz(list), ry(prot)), // tilt/rotate pelvis about its centre
            mul(tr(sway, hipY - crouch + bob, 0), mul(rx(bodyPitch), ry(facingDeg))), // crouch, pitch whole body forward about the feet, then face
            tr(self.pos.x, 0, self.pos.z), // place in the world
        );

        // Spine chain — lean deepens through run into sprint + counter-rotation vs pelvis.
        const lean = (mathx.lerpF(TORSO_LEAN, RUN_LEAN, runB) + sprintB * (SPRINT_LEAN - RUN_LEAN)) * m;
        setLocal(&wx, SPINE, self.rest, mul(rx(lean * 0.5), ry(-0.3 * prot)));
        setLocal(&wx, CHEST, self.rest, mul(rx(lean * 0.5), ry(-0.5 * prot)));
        // Idle/walk carries a gentle downward gaze (HEAD_WALK). When running, the body pitch
        // + spine lean would drive the face at the floor, so counter that accumulated tilt
        // down toward ~GAZE_AHEAD — a few metres ahead, NOT level/up — capped so the neck
        // never hyperextends. Split across neck + head so the lift curves naturally.
        const fwdTilt = bodyPitch + lean;
        const gazeCounter = mathx.clampF(fwdTilt - GAZE_AHEAD, 0, NECK_EXT_MAX);
        setLocal(&wx, NECK, self.rest, mul(rx(-0.45 * gazeCounter), ry(-0.2 * prot)));
        setLocal(&wx, HEAD, self.rest, rx(HEAD_WALK - 0.55 * gazeCounter)); // +rx = gaze down (walk); the counter lifts it toward ahead when running

        // Legs — left uses phase, right is half a stride out.
        legChain(&wx, self.rest, ph, m, runB, 1.0, HIPL, KNEEL, ANKL);
        legChain(&wx, self.rest, ph + 0.5, m, runB, -1.0, HIPR, KNEER, ANKR);

        // Arms — contralateral swing (cos: same-side arm is BACK when its leg is forward);
        // bigger swing + ~90° elbows when running.
        const armAmp = mathx.lerpF(ARM_SWING, RUN_ARM_SWING, runB);
        const armL = -armAmp * mathx.cosf(twoPi * ph) * m;
        const armR = armAmp * mathx.cosf(twoPi * ph) * m;
        armChain(&wx, self.rest, armL, m, runB, 1.0, SHL, ELL, WRL);
        armChain(&wx, self.rest, armR, m, runB, -1.0, SHR, ELR, WRR);

        self.xf = wx;
    }

    // Roll pose: the whole tucked body somersaults forward about a pivot at ball height,
    // easing into a crouch and back out to a stand. After facing, the body's +Z is rollDir,
    // so a +X-axis rotation is a forward roll along it.
    fn poseRoll(self: *Hero) void {
        const u = mathx.clampF(self.rollT / ROLL_DUR, 0, 1);
        const tuck = mathx.clampF(@min(u / 0.2, (1.0 - u) / 0.2), 0, 1); // ramp in, hold, ramp out
        const rollDeg = 360.0 * u; // exactly one forward revolution over the roll
        const ballY = mathx.lerpF(self.rest[ROOT].y, ROLL_BALL_Y, tuck);
        const facingDeg = self.facing * 180.0 / std.math.pi;

        var wx: [N]rl.Matrix = undefined;
        wx[ROOT] = mul3(
            rx(rollDeg), // somersault about body-right (forward)
            mul(ry(facingDeg), tr(0, ballY, 0)), // face roll dir, lift to the ball centre
            tr(self.pos.x, 0, self.pos.z), // place in the world
        );
        setLocal(&wx, SPINE, self.rest, rx(ROLL_SPINE * tuck)); // curl forward
        setLocal(&wx, CHEST, self.rest, rx(ROLL_SPINE * tuck));
        setLocal(&wx, NECK, self.rest, rx(ROLL_HEAD * 0.4 * tuck));
        setLocal(&wx, HEAD, self.rest, rx(ROLL_HEAD * tuck)); // chin to chest
        rollLeg(&wx, self.rest, tuck, 1.0, HIPL, KNEEL, ANKL);
        rollLeg(&wx, self.rest, tuck, -1.0, HIPR, KNEER, ANKR);
        rollArm(&wx, self.rest, tuck, 1.0, SHL, ELL, WRL);
        rollArm(&wx, self.rest, tuck, -1.0, SHR, ELR, WRR);
        self.xf = wx;
    }

    pub fn draw(self: *const Hero) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, self.xf[i]);
    }

    // Eye/target point for the camera: roughly the base of the neck, in world space.
    pub fn shoulderPoint(self: *const Hero) rl.Vector3 {
        return v3(self.pos.x, self.rest[CHEST].y, self.pos.z);
    }
};

// offset(child) in the parent's frame = restPos(child) - restPos(parent), since all rest
// orientations are identity. world(child) = local(child) ∘ world(parent), where
// local = animRot ∘ translate(offset) (animRot applied first, about the joint).
fn setLocal(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    const p: usize = @intCast(parent[i]);
    const off = mathx.subV(rest[i], rest[p]);
    const local = mul(animRot, tr(off.x, off.y, off.z));
    wx[i] = mul(local, wx[p]);
}

fn legChain(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, ph: f32, m: f32, runB: f32, side: f32, hip: usize, knee: usize, ank: usize) void {
    const hipFlex = mathx.lerpF(sampleCurve(HIP_FLEX, ph), sampleCurve(RUN_HIP, ph), runB) * m;
    const kneeWR = mathx.lerpF(sampleCurve(KNEE_FLEX, ph), sampleCurve(RUN_KNEE, ph), runB);
    const kneeFlex = mathx.lerpF(IDLE_KNEE, kneeWR, m);
    const ankDorsi = mathx.lerpF(sampleCurve(ANK_DORSI, ph), sampleCurve(RUN_ANK, ph), runB) * m;
    // hip: sagittal flexion (−rx = thigh forward) then a constant adduction toward midline.
    setLocal(wx, hip, rest, mul(rx(-hipFlex), rz(-side * HIP_ADDUCT)));
    setLocal(wx, knee, rest, rx(kneeFlex)); // +rx = knee bends (shank swings back/up)
    setLocal(wx, ank, rest, mul(rx(-ankDorsi), ry(side * FOOT_TOEOUT))); // dorsiflex + toe-out splay
}

fn armChain(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, swing: f32, m: f32, runB: f32, side: f32, sh: usize, el: usize, wr: usize) void {
    // Contralateral fore/aft swing; the walking elbow tracks the FORWARD swing only (back
    // arm stays nearly straight — no "zombie arms"), and running bends both to ~90° pumping.
    const walkElbow = mathx.maxF(6.0, 4.0 + 0.8 * swing);
    const elbow = mathx.lerpF(IDLE_ELBOW, mathx.lerpF(walkElbow, RUN_ELBOW, runB), m);
    setLocal(wx, sh, rest, mul(rx(-swing), rz(side * ARM_ABD))); // −rx forward, ±side rz outward
    setLocal(wx, el, rest, rx(-elbow)); // −rx = forearm forward (elbow flexes)
    setLocal(wx, wr, rest, rl.math.matrixIdentity());
}

// Roll tuck: thighs to chest, heels toward glutes, arms hugged in front — all scaled by
// `tuck` so the crouch eases in and the stand eases out.
fn rollLeg(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, tuck: f32, side: f32, hip: usize, knee: usize, ank: usize) void {
    setLocal(wx, hip, rest, mul(rx(-ROLL_HIP * tuck), rz(-side * HIP_ADDUCT)));
    setLocal(wx, knee, rest, rx(ROLL_KNEE * tuck));
    setLocal(wx, ank, rest, ry(side * FOOT_TOEOUT));
}
fn rollArm(wx: *[N]rl.Matrix, rest: [N]rl.Vector3, tuck: f32, side: f32, sh: usize, el: usize, wr: usize) void {
    setLocal(wx, sh, rest, mul(rx(-ROLL_SHOULDER * tuck), rz(side * ARM_ABD)));
    setLocal(wx, el, rest, rx(-ROLL_ELBOW * tuck));
    setLocal(wx, wr, rest, rl.math.matrixIdentity());
}

// ── bone meshes (authored at the joint origin, hero-local axes; lengths in units of H) ──
fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = abdomenMesh();
    mesh[CHEST] = chestMesh();
    mesh[NECK] = neckMesh();
    mesh[HEAD] = headMesh();
    mesh[HIPL] = thighMesh();
    mesh[KNEEL] = shankMesh();
    mesh[ANKL] = footMesh();
    mesh[HIPR] = thighMesh();
    mesh[KNEER] = shankMesh();
    mesh[ANKR] = footMesh();
    mesh[SHL] = upperArmMesh(true);
    mesh[ELL] = forearmMesh();
    mesh[WRL] = handMesh();
    mesh[SHR] = upperArmMesh(false);
    mesh[ELR] = forearmMesh();
    mesh[WRR] = handMesh();
    return mesh;
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.addCube(v3(0, -0.01 * H, 0), v3(0.235 * H, 0.16 * H, 0.175 * H), BELT);
    b.addCube(v3(0, 0.055 * H, 0), v3(0.215 * H, 0.07 * H, 0.16 * H), TUNIC_DK); // hip skirt of the tunic
    b.addCube(v3(0, -0.005 * H, 0.0925 * H), v3(0.035 * H, 0.035 * H, 0.012 * H), BRASS); // buckle
    // leather tassets over the hips + a supply pouch on the right
    b.addCube(v3(0.095 * H, -0.055 * H, 0.05 * H), v3(0.07 * H, 0.085 * H, 0.016 * H), LEATHER);
    b.addCube(v3(-0.095 * H, -0.055 * H, 0.05 * H), v3(0.07 * H, 0.085 * H, 0.016 * H), LEATHER);
    b.addCube(v3(-0.115 * H, -0.045 * H, -0.03 * H), v3(0.05 * H, 0.06 * H, 0.045 * H), LEATHER_DK); // pouch
    b.addCube(v3(-0.115 * H, -0.028 * H, -0.03 * H), v3(0.054 * H, 0.02 * H, 0.05 * H), LEATHER); // pouch flap
    // Sword at the left hip, riding the pelvis bone: scabbard raked down-and-back, hilt
    // above the belt. d = unit lean of the scabbard; p1/p2 its cross-section axes.
    const d = v3(0.10, -0.90, -0.42);
    const p1 = v3(0.995, 0.090, 0.042);
    const p2 = v3(0, -0.422, 0.9045);
    const s0 = v3(0.115 * H, -0.045 * H, -0.015 * H); // scabbard throat (at the belt line)
    const hl = 0.185 * H; // scabbard half-length
    b.addBox(v3(s0.x + d.x * hl, s0.y + d.y * hl, s0.z + d.z * hl), v3(p1.x * 0.020 * H, p1.y * 0.020 * H, p1.z * 0.020 * H), v3(d.x * hl, d.y * hl, d.z * hl), v3(p2.x * 0.010 * H, p2.y * 0.010 * H, p2.z * 0.010 * H), LEATHER_DK);
    b.addBox(v3(s0.x + d.x * 2 * hl, s0.y + d.y * 2 * hl, s0.z + d.z * 2 * hl), v3(p1.x * 0.023 * H, p1.y * 0.023 * H, p1.z * 0.023 * H), v3(d.x * 0.014 * H, d.y * 0.014 * H, d.z * 0.014 * H), v3(p2.x * 0.012 * H, p2.y * 0.012 * H, p2.z * 0.012 * H), STEEL_DK); // chape
    b.addBox(s0, v3(p1.x * 0.055 * H, p1.y * 0.055 * H, p1.z * 0.055 * H), v3(d.x * 0.009 * H, d.y * 0.009 * H, d.z * 0.009 * H), v3(p2.x * 0.011 * H, p2.y * 0.011 * H, p2.z * 0.011 * H), STEEL); // crossguard
    b.addCylinder(v3(s0.x - d.x * 0.005 * H, s0.y - d.y * 0.005 * H, s0.z - d.z * 0.005 * H), v3(s0.x - d.x * 0.075 * H, s0.y - d.y * 0.075 * H, s0.z - d.z * 0.075 * H), 0.013 * H, 0.011 * H, 6, BELT); // grip
    b.addCube(v3(s0.x - d.x * 0.09 * H, s0.y - d.y * 0.09 * H, s0.z - d.z * 0.09 * H), v3(0.028 * H, 0.028 * H, 0.028 * H), BRASS); // pommel
    return b.toMesh();
}

fn abdomenMesh() rl.Mesh {
    var b = Builder.init();
    // Slight waist taper: a lower belly block under a broader ribcage base.
    b.addCube(v3(0, -0.01 * H, 0), v3(0.205 * H, 0.13 * H, 0.145 * H), TUNIC);
    b.addCube(v3(0, 0.075 * H, 0), v3(0.235 * H, 0.09 * H, 0.16 * H), TUNIC);
    // tabard front — hangs over the belly, bends with the spine
    b.addCube(v3(0, -0.012 * H, 0.079 * H), v3(0.135 * H, 0.155 * H, 0.014 * H), CAPE);
    return b.toMesh();
}

fn chestMesh() rl.Mesh {
    var b = Builder.init();
    // Thorax topping out AT the shoulder line (~0.815 H) so the neck stays clear — the
    // broad-shouldered read comes from the pauldrons on the arms, not a tall chest block.
    b.addCube(v3(0, -0.005 * H, 0), v3(0.285 * H, 0.12 * H, 0.165 * H), TUNIC); // 0.695–0.815 H
    b.addCube(v3(0, 0.035 * H, -0.005 * H), v3(0.305 * H, 0.06 * H, 0.18 * H), LEATHER_DK); // collar/mantle at the shoulders
    b.addCube(v3(0, -0.01 * H, 0.086 * H), v3(0.135 * H, 0.11 * H, 0.012 * H), CAPE); // tabard chest panel
    b.addCube(v3(0, -0.035 * H, -0.098 * H), v3(0.24 * H, 0.115 * H, 0.016 * H), CAPE); // short cape at the back
    b.addCube(v3(0, 0.042 * H, -0.10 * H), v3(0.25 * H, 0.035 * H, 0.02 * H), LEATHER); // cape yoke
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.addCylinder(v3(0, 0, 0), v3(0, 0.070 * H, 0), 0.040 * H, 0.036 * H, 8, SKIN_DK);
    return b.toMesh();
}

fn headMesh() rl.Mesh {
    var b = Builder.init();
    // Cranium, jaw, nose (facing cue), swept-back hair with a nape knot, and a thin
    // leather headband. Head joint sits at the chin line (~0.875 H); crown lands ~1.0 H.
    b.addCube(v3(0, 0.075 * H, -0.005 * H), v3(0.135 * H, 0.115 * H, 0.15 * H), SKIN); // cranium
    b.addCube(v3(0, 0.018 * H, 0.012 * H), v3(0.10 * H, 0.055 * H, 0.125 * H), SKIN); // jaw
    b.addCube(v3(0, 0.05 * H, 0.082 * H), v3(0.028 * H, 0.03 * H, 0.03 * H), SKIN_DK); // nose
    b.addCube(v3(0, 0.118 * H, -0.025 * H), v3(0.145 * H, 0.05 * H, 0.15 * H), HAIR); // hair cap
    b.addCube(v3(0, 0.055 * H, -0.078 * H), v3(0.135 * H, 0.125 * H, 0.035 * H), HAIR); // back of hair
    b.addCube(v3(0, 0.012 * H, -0.092 * H), v3(0.05 * H, 0.05 * H, 0.035 * H), HAIR); // nape knot
    b.addCube(v3(0, 0.092 * H, 0.0 * H), v3(0.142 * H, 0.018 * H, 0.152 * H), LEATHER_DK); // headband
    return b.toMesh();
}

fn thighMesh() rl.Mesh {
    var b = Builder.init();
    b.addCylinder(v3(0, 0, 0), v3(0, -SEG_THIGH * H, 0), 0.078 * H, 0.058 * H, 10, CLOTHDK);
    b.addCylinder(v3(0, -0.002 * H, 0), v3(0, -0.075 * H, 0), 0.088 * H, 0.072 * H, 10, LEATHER_DK); // skirt ring
    return b.toMesh();
}

fn shankMesh() rl.Mesh {
    var b = Builder.init();
    // Calf bulge, then a leather boot shaft tapering to the ankle.
    b.addCylinder(v3(0, 0, 0), v3(0, -0.09 * H, 0), 0.058 * H, 0.062 * H, 10, CLOTHDK);
    b.addCylinder(v3(0, -0.09 * H, 0), v3(0, -SEG_SHANK * H, 0), 0.064 * H, 0.036 * H, 10, BOOT);
    b.addCube(v3(0, -0.02 * H, 0.052 * H), v3(0.062 * H, 0.06 * H, 0.026 * H), LEATHER); // kneecap
    return b.toMesh();
}

fn footMesh() rl.Mesh {
    var b = Builder.init();
    // Boot: sole rests on the ground (ankle joint is ANKLE_Y=0.039 H up), toes forward +Z.
    const ay = 0.039 * H;
    b.addCube(v3(0, -ay + 0.028 * H, 0.045 * H), v3(0.085 * H, 0.056 * H, 0.19 * H), BOOT);
    b.addCube(v3(0, -ay + 0.075 * H, -0.02 * H), v3(0.075 * H, 0.05 * H, 0.09 * H), BOOT); // ankle cuff
    return b.toMesh();
}

// Asymmetric pauldrons, souls-style: the sword-side (left) shoulder carries the big
// layered leather + steel-rim pauldron; the right makes do with a plain cap.
fn upperArmMesh(big: bool) rl.Mesh {
    var b = Builder.init();
    if (big) {
        b.addCube(v3(0, -0.005 * H, 0), v3(0.125 * H, 0.10 * H, 0.13 * H), LEATHER);
        b.addCube(v3(0, 0.048 * H, 0), v3(0.105 * H, 0.045 * H, 0.115 * H), STEEL_DK); // steel rim cap
    } else {
        b.addCube(v3(0, 0.005 * H, 0), v3(0.105 * H, 0.085 * H, 0.115 * H), LEATHER);
    }
    b.addCylinder(v3(0, 0, 0), v3(0, -SEG_UPARM * H, 0), 0.052 * H, 0.044 * H, 9, TUNIC);
    return b.toMesh();
}

fn forearmMesh() rl.Mesh {
    var b = Builder.init();
    b.addCylinder(v3(0, 0, 0), v3(0, -0.065 * H, 0), 0.044 * H, 0.040 * H, 9, TUNIC);
    b.addCylinder(v3(0, -0.065 * H, 0), v3(0, -SEG_FOREARM * H, 0), 0.047 * H, 0.034 * H, 9, LEATHER); // bracer
    return b.toMesh();
}

fn handMesh() rl.Mesh {
    var b = Builder.init();
    b.addCube(v3(0, -0.05 * H, 0.005 * H), v3(0.05 * H, 0.10 * H, 0.045 * H), BOOT); // glove
    return b.toMesh();
}
