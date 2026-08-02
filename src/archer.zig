const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const heromod = @import("hero.zig");
const foe = @import("foe.zig");
const collision = @import("collision.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// A bare-bones skeleton that KITES: it holds a range band, looses slowish lightly-homing arrows that stick and fade, and never melees — the opening is closing the gap.

const BONE = rgba(126, 116, 92, 255); // weathered ivory, yellowed with the centuries
const BONE_DK = rgba(78, 70, 55, 255); // shadowed recesses / old bone
const BONE_LT = rgba(154, 144, 120, 255); // caught-light ridges
const STAIN = rgba(96, 82, 60, 255); // grave-dirt staining (bones weather unevenly)
const SOCKET = rgba(12, 10, 9, 255); // eye sockets, nasal cavity, rib hollow — void
const TEETH = rgba(188, 178, 152, 255); // pale teeth, pop against the skull
const BOWWOOD = rgba(32, 22, 13, 255); // dark horn-and-wood bow
const BOWWOOD_LT = rgba(48, 35, 21, 255);
const GRIP_WRAP = rgba(50, 38, 27, 255); // cracked leather grip wrap
const STRINGCOL = rgba(170, 162, 140, 255); // pale sinew string
const QUIVER_HIDE = rgba(46, 34, 24, 255); // the back quiver's cracked leather
const QUIVER_LT = rgba(64, 49, 34, 255);
// The arrow reads as a THREAT first (owner: "arrows need to be easier to see") — pale shaft, big bone-white fletching + bright pile, both partly SELF-LIT (vertex alpha < 255 = emissive) so a shot pops in shade and against the ground.
const ARROW_SHAFT = rgba(118, 102, 76, 255); // pale ash shaft
const ARROW_HEAD = rgba(158, 166, 178, 170); // bright steel pile (glints, slightly self-lit)
const ARROW_FLETCH = rgba(176, 166, 140, 150); // bone-white feathers, self-lit — the tracer

// Bow rides the RIGHT wrist (a left-hand-draw archer) — the shared weapon-on-right convention, so the FK scaffold lines up.
const N = heromod.N;
const ROOT = heromod.ROOT;
const SPINE = heromod.SPINE;
const CHEST = heromod.CHEST;
const NECK = heromod.NECK;
const SKULL = heromod.HEAD; // …the archer's name for it: this one is a bare skull
const HIPL = heromod.HIPL;
const KNEEL = heromod.KNEEL;
const ANKL = heromod.ANKL;
const HIPR = heromod.HIPR;
const KNEER = heromod.KNEER;
const ANKR = heromod.ANKR;
const SHL = heromod.SHL; // shoulder L (the DRAW arm)
const ELL = heromod.ELL;
const WRL = heromod.WRL;
const SHR = heromod.SHR; // shoulder R (the BOW arm)
const ELR = heromod.ELR;
const WRR = heromod.WRR;
const BOW = heromod.HELD; // the drawn bow, in the shared weapon slot

const parent = heromod.PARENT;

// Stature + segment lengths: the hero's exact anthropometry (Drillis & Contini 1966 / Winter).
const H: f32 = heromod.H;
// The LEGS take the hero's fractions from the shared source — legChain's strafe geometry is measured off them, so a local copy that drifted would make this skeleton's planted feet skate.
const SEG_THIGH = heromod.SEG_THIGH;
const SEG_SHANK = heromod.SEG_SHANK;
// …and so do the ARMS, from the same source.
const SEG_UPARM = heromod.SEG_UPARM;
const SEG_FOREARM = heromod.SEG_FOREARM;

fn restPositions() [N]rl.Vector3 {
    // A skeleton has the Tarnished's own frame — same stature, same hips, same shoulders.
    return heromod.restHumanoid(heromod.HIP_HALF, heromod.SHOULDER_HALF, H);
}

const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleV = mathx.scaleV;
const scaleM = mathx.scaleM;

fn setLocal(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    heromod.setJoint(wx, &rest, i, @intCast(parent[i]), animRot);
}

const BOW_FY = -0.05 * H; // fist centre in the wrist frame (the hero's grip anchor)
const BOW_FZ = 0.02 * H; // held a touch out front of the palm
const TIP_UP = 0.40 * H; // upper limb reach above the fist…
const TIP_DN = 0.37 * H; // …lower limb a touch shorter (war bows are uneven — wabi-sabi)
const TIP_Z = 0.06 * H; // the recurved tips kick forward of the grip line
const FIST_L = v3(0, -0.05 * H, 0.02 * H); // the DRAW hand's fist centre (left-wrist frame)

// Orient +Z along `dir` (the arrowXform convention), rotation only.
fn orientZ(dir: rl.Vector3) rl.Matrix {
    const yaw = mathx.degrees(std.math.atan2(dir.x, dir.z));
    const pitch = mathx.degrees(std.math.asin(mathx.clampF(-dir.y, -1, 1)));
    return mul(rx(pitch), ry(yaw));
}

// Stretch the unit +Z string segment from `a` to `b` (world space).
fn stretchZ(a: rl.Vector3, b: rl.Vector3) rl.Matrix {
    const d = mathx.subV(b, a);
    const len = mathx.maxF(mathx.lenV(d), 1e-4);
    return mul(scaleM(1, 1, len), mul(orientZ(mathx.scaleV(d, 1.0 / len)), tr(a.x, a.y, a.z)));
}

pub const SCALE = 1.0; // archers stand at the hero's height — no global bump (unlike the toads)
const WALK_SPEED = heromod.WALK_SPEED * 0.95; // a wary, unhurried reposition
const AGGRO_R = 24.0; // notices + engages the hero within this (ranged, so wider than the toad)
const RANGE_MIN = 8.0; // too close → back off to re-open the shot
const RANGE_MAX = 20.0; // out past here → step in to close to band
const TURN_RATE = 6.0; // rad/s — tracks the hero (light aim tracking)
const BODY_R = 0.34; // ground footprint (matches the hero's HERO_R feel)
const HURT_R = 0.42; // hurt-sphere radius for the hero's blade
// Pelvis walk oscillation — the hero's amplitude, so the shared gait reads as one humanoid.
const A_BOB = heromod.A_BOB;
// Where a skeletal foot meets the earth, MEASURED off footMesh: the metatarsal plate + heel, with the toe bones fanning out to ~0.245·H ahead.
const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.04 * H, .toe = 0.245 * H, .halfW = 0.05 * H, .drop = 0.034 * H },
    .{ .bone = ANKR, .heel = 0.04 * H, .toe = 0.245 * H, .halfW = 0.05 * H, .drop = 0.034 * H },
};

const A_PROT = 4.0; // deg of pelvic TRANSVERSE rotation per stride (the hero walks on 3.5; bare

const DRAW_DUR = 0.85; // raise + pull to full draw (the tell)
const HOLD_DUR = 0.45; // settle at full draw, aiming
const LOOSE_DUR = 0.14; // the release snap
const RECOVER_DUR = 0.55; // lower the bow, reset
const RELOAD_CD = 1.1; // beat between shots (nock the next)
const REPOSITION_DUR = 1.6; // how long a kite step lasts before re-deciding

const BACKSTEP_R = 3.9; // hero this close and it bails (well inside RANGE_MIN's walking kite)
const BACKSTEP_CD = 7.0; // …but only this often
const BACKSTEP_GATHER = 0.13; // the coil. Short — it is a flinch, not a wind-up
const BACKSTEP_FLIGHT = 0.44; // the leap itself
const BACKSTEP_LAND = 0.30; // …and the landing, wide open (the price of using it)
const BACKSTEP_DIST = 4.7; // ground covered, straight away from the hero — back into the band
const BACKSTEP_RISE = 0.34; // peak hop height (world units)

const HP_MAX = 58.0;
const POISE_MAX = 14.0; // a clean light hit still flinches it out of a draw
const STANCE_MAX = 30.0;
pub const ARROW_HIT = combat.Hit{ .dmg = 16, .poise = 10 }; // eased down from 20 (owner: lower dmg a bit)
const DEATH_DUR = 1.15; // collapse-and-still before the corpse dissipates
/// RUNES a skeletal archer is worth — twice a toad.
pub const RUNES: u32 = 130;
const DISS_DUR = 0.9; // dissipation into bone-dust + grace motes
const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 7.0;

// Slowish flight with LIGHT homing toward the hero (a gentle curve, not a lock-on), then it STICKS where it lands (ground / near the hero) and fades.
const ARROW_SPEED = 15.0; // world units/s — slowish, dodgeable
const ARROW_HOMING = 0.85; // rad/s the heading may bend toward the hero — a NUDGE, not a lock
const ARROW_HOME_FADE = 0.45; // …and it decays to nothing over this much flight (see stepArrow):
const ARROW_GRAV: f32 = 3.0; // gentle drop so long shots arc
/// A STONE DROPS HARDER THAN A SHAFT — which this file has always claimed and never did, because one gravity served both.
const STONE_GRAV: f32 = 9.0;
const ARROW_LIFE = 3.5; // seconds airborne before it gives up (falls + sticks)
const ARROW_STICK_FADE = 1.4; // seconds a stuck arrow lingers, then fades
/// How fat the shaft is against the WORLD when it tests cover — a name because `game.arrowCover` sizes its grid query around "the fattest margin it tests with" and was pointing at a bare literal in another file.
pub const ARROW_COVER_MARGIN: f32 = 0.04;
const ARROW_HIT_R = 0.5; // hero footprint the arrow must reach to connect…
const ARROW_HIT_HALF_H = 0.85; // …and how far above/below his centre of mass still counts. It was a

pub const TRAIL_N = 10;
const TRAIL_LIFE = 0.17; // seconds a sample lingers
const TRAIL_W = 0.055; // half-width at the head, tapering to nothing at the tail
const TRAIL_COL = rgba(214, 198, 158, 255); // pale, kin to the fletching — alpha set per segment

pub const Arrow = struct {
    pos: rl.Vector3 = mathx.zero3,
    vel: rl.Vector3 = mathx.zero3,
    live: bool = false,
    stuck: bool = false,
    age: f32 = 0, // in flight: seconds airborne; stuck: seconds since it stuck (fade timer)
    hit: bool = false, // it connected with the hero this frame (game.zig reads + clears)
    /// WHAT IT STUCK IN, set on the frame it plants. null = the bare earth (a miss), which is the commonest case by far and wants its own duller, fizzier impact. game.zig reads it to pick the sound; nothing else cares.
    struck: ?collision.Surface = null,
    /// A SLINGER'S STONE rather than an arrow.
    stone: bool = false,
    // The trail ring.
    trail: [TRAIL_N]rl.Vector3 = [_]rl.Vector3{mathx.zero3} ** TRAIL_N,
    trailAge: [TRAIL_N]f32 = [_]f32{mathx.LONG_AGO} ** TRAIL_N,
    trailHead: usize = 0,
};

/// The streak behind a shaft in flight — a tapering tube down the last few positions, fading with age.
pub fn drawArrowTrails(arrows: []const Arrow) void {
    for (arrows) |*a| drawArrowTrail(a);
}

fn drawArrowTrail(a: *const Arrow) void {
    if (!a.live) return;
    var i: usize = 0;
    while (i + 1 < TRAIL_N) : (i += 1) {
        // `ia`/`ib`, not `i0`/`i1` — those are real Zig integer TYPE names and shadowing a primitive is a compile error.
        const ia = (a.trailHead + TRAIL_N - i) % TRAIL_N;
        const ib = (a.trailHead + TRAIL_N - i - 1) % TRAIL_N;
        const g0 = a.trailAge[ia];
        const g1 = a.trailAge[ib];
        if (g0 >= TRAIL_LIFE or g1 >= TRAIL_LIFE) break; // the rest is older still
        const p0 = a.trail[ia];
        const p1 = a.trail[ib];
        const seg = mathx.subV(p1, p0);
        if (mathx.lenV(seg) < 1e-4) continue;
        // A TAPERED CYLINDER per segment, not a triangle-strip ribbon.
        const w0 = TRAIL_W * (0.35 + 0.65 * (1.0 - g0 / TRAIL_LIFE));
        const w1 = TRAIL_W * (0.35 + 0.65 * (1.0 - g1 / TRAIL_LIFE));
        const f = 1.0 - 0.5 * (g0 + g1) / TRAIL_LIFE;
        rl.drawCylinderEx(p0, p1, w0, w1, 4, mathx.withAlpha(TRAIL_COL, mathx.u8f(190.0 * f)));
    }
}

// Loose an arrow from `from` toward `target`, with a little loft so the shot ARCS toward a (usually lower) target over distance — the light homing in stepArrow refines the rest.
fn launchAt(from: rl.Vector3, target: rl.Vector3, speed: f32, grav: f32, stone: bool) Arrow {
    var d = mathx.subV(target, from);
    const dist = mathx.lenV(d);
    d = if (dist < 1e-3) v3(0, 0, 1) else mathx.scaleV(d, 1.0 / dist);
    var vel = mathx.scaleV(d, speed);
    vel.y += 0.5 * grav * (dist / speed);
    return .{ .pos = from, .vel = vel, .live = true, .stone = stone };
}

pub fn launchArrow(from: rl.Vector3, target: rl.Vector3) Arrow {
    return launchAt(from, target, ARROW_SPEED, ARROW_GRAV, false);
}

/// A SLINGER'S STONE, off the same launcher: slower, and it DROPS HARDER (`STONE_GRAV`), which is where the visible lob comes from now that the loft is solved rather than piled on.
pub fn launchStone(from: rl.Vector3, target: rl.Vector3, speed: f32) Arrow {
    return launchAt(from, target, speed, STONE_GRAV, true);
}

// Advance one arrow a frame: LIGHT homing (a gentle bend toward the hero, never a lock — a sidestep beats it), gravity arc, then STICK on cover / hero / ground / expiry; sets `hit` the frame it strikes, stuck arrows age out and clear `live`.
fn heroReached(p: rl.Vector3, hero: rl.Vector3, heroCenterY: f32) bool {
    return mathx.distXZ(p, hero) <= ARROW_HIT_R and @abs(p.y - heroCenterY) <= ARROW_HIT_HALF_H;
}

pub fn stepArrow(a: *Arrow, hero: rl.Vector3, heroCenterY: f32, groundY: f32, heroDodging: bool, solids: []const collision.Solid, dt: f32) void {
    if (!a.live) return;
    // THE STREAK AGES WHETHER THE SHAFT IS FLYING OR PLANTED. Behind the stuck branch's return it stopped ageing the moment the arrow hit, so `drawArrowTrail` — which only asks whether the arrow is `live` — kept redrawing a full-alpha tube hanging in the air behind every embedded shaft for the whole `ARROW_STICK_FADE`.
    for (&a.trailAge) |*ag| ag.* = @min(ag.* + dt, mathx.LONG_AGO);
    if (a.stuck) {
        a.age += dt;
        if (a.age >= ARROW_STICK_FADE) a.live = false;
        return;
    }
    a.age += dt;
    const target = v3(hero.x, heroCenterY, hero.z);
    // HOMING IS HORIZONTAL ONLY, and the vertical is left strictly to the launch and to gravity.
    const hs = mathx.lenXZ(a.vel);
    if (hs > 1e-3) {
        const assist = ARROW_HOMING * (1.0 - mathx.smoothstep(0, ARROW_HOME_FADE, a.age));
        const cur = v3(a.vel.x / hs, 0, a.vel.z / hs);
        const to = mathx.dirXZ(a.pos, target);
        // …and only while still CLOSING, so a shot that has been dodged flies PAST instead of U-turning.
        if (assist > 0 and cur.x * to.x + cur.z * to.z > 0.2) {
            const bent = mathx.normV(mathx.lerpV(cur, to, mathx.clampF(assist * dt, 0, 1)));
            a.vel.x = bent.x * hs;
            a.vel.z = bent.z * hs;
        }
    }
    // …and the drop, which is per-PROJECTILE: `launchAt` solved the loft against this exact number, so integrating a shaft's gravity under a stone would put the stone back off the aim line.
    a.vel.y -= (if (a.stone) STONE_GRAV else ARROW_GRAV) * dt;
    const prev = a.pos;
    a.pos = mathx.addV(a.pos, mathx.scaleV(a.vel, dt));
    // Push this frame's position onto the trail ring.
    a.trailHead = (a.trailHead + 1) % TRAIL_N;
    a.trail[a.trailHead] = a.pos;
    a.trailAge[a.trailHead] = 0;
    // COVER first (a wall between archer and hero beats a hero hugging its far side): sample the frame's travel at midpoint + endpoint so a fast shaft can't tunnel a thin trunk.
    const mid = mathx.lerpV(prev, a.pos, 0.5);
    const midSurf = collision.blockerAt(mid, ARROW_COVER_MARGIN, solids);
    const endSurf = collision.blockerAt(a.pos, ARROW_COVER_MARGIN, solids);
    const midBlocked = midSurf != null;
    if (midBlocked or endSurf != null) {
        a.struck = midSurf orelse endSurf; // …what it went into, for the impact sound
        // Normalize the CURRENT velocity: `spd` was sampled before homing + gravity touched it, so using it as the divisor left the embed offset a frame of gravity out of true.
        const dir = mathx.normV(a.vel);
        a.pos = mathx.subV(if (midBlocked) mid else a.pos, mathx.scaleV(dir, 0.26)); // head embedded, shaft + fletch proud
        a.stuck = true;
        a.age = 0;
        return;
    }
    // …and the HERO, sampled over the same two points for the same reason.
    if (!heroDodging and (heroReached(a.pos, hero, heroCenterY) or heroReached(mid, hero, heroCenterY))) {
        a.hit = true;
        a.stuck = true;
        a.age = 0;
    } else if (a.pos.y <= groundY + 0.02 or a.age >= ARROW_LIFE) {
        a.pos.y = mathx.maxF(a.pos.y, groundY + 0.02); // stuck in the earth where it landed
        a.stuck = true;
        a.age = 0;
    }
}

// The draw matrix for one arrow: orient the mesh's +Z (its flight axis) along the velocity (yaw + pitch), placed at pos, shrinking over the back half of a stuck arrow's fade.
pub fn arrowXform(a: *const Arrow) rl.Matrix {
    const spd = mathx.lenV(a.vel);
    const dir = if (spd > 1e-3) mathx.scaleV(a.vel, 1.0 / spd) else v3(0, -1, 0);
    const fade = if (a.stuck) 1.0 - mathx.smoothstep(ARROW_STICK_FADE * 0.5, ARROW_STICK_FADE, a.age) else 1.0;
    const s = mathx.clampF(fade, 0.06, 1.0);
    return mul(scaleM(s, s, s), mul(orientZ(dir), tr(a.pos.x, a.pos.y, a.pos.z)));
}

const State = enum { idle, draw, hold, loose, recover, reposition, backstep, stunlight, stunheavy, dead };

// Pure kite decision — a function of range + reload, so it's unit-testable without a world.
const Choice = enum { shoot, back_off, close_in, hold_ground };
fn classify(dist: f32, reloaded: bool) Choice {
    if (dist > AGGRO_R) return .hold_ground; // hasn't noticed / disengaged
    if (dist < RANGE_MIN) return .back_off; // too close — kite out
    if (dist > RANGE_MAX) return .close_in; // too far — step in
    return if (reloaded) .shoot else .hold_ground; // in band: fire when nocked
}

// Pure backstep gate, same shape as `classify` so it is testable without a world.
fn wantsBackstep(dist: f32, cd: f32, s: State) bool {
    if (dist > BACKSTEP_R or cd > 0) return false;
    return switch (s) {
        .idle, .draw, .hold, .recover, .reposition => true,
        .loose, .backstep, .stunlight, .stunheavy, .dead => false,
    };
}

// How far through the leap: 0 at the coil, 1 the instant it lands.
fn leapU(t: f32) f32 {
    return mathx.clampF((t - BACKSTEP_GATHER) / BACKSTEP_FLIGHT, 0, 1);
}
// Distance covered by time t — front-loaded, so it explodes off the coil and coasts to a stop instead of ending on a hard stop.
fn leapTravel(t: f32) f32 {
    const u = leapU(t);
    const e = 1.0 - (1.0 - u) * (1.0 - u);
    return BACKSTEP_DIST * e;
}

pub const Model = struct {
    mesh: [N]rl.Mesh,
    string: rl.Mesh, // unit +Z segment; poseString stretches two of these tip→nock→tip
    nockArrow: rl.Mesh, // the nocked shaft riding the drawn string (tail at origin, +Z)
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("archer material");
        mat.shader = shader;
        return .{ .mesh = buildMeshes(), .string = stringMesh(), .nockArrow = nockArrowMesh(), .mat = mat };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, a: *const Archer) void {
        for (0..N) |i| rl.drawMesh(self.mesh[i], self.mat, a.xf[i]);
        for (a.stringXf) |sm| rl.drawMesh(self.string, self.mat, sm);
        if (a.nockVis) rl.drawMesh(self.nockArrow, self.mat, a.nockXf);
    }
};

pub const Archer = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,

    state: State = .idle,
    t: f32 = 0,
    reloadCd: f32 = 0,
    elapsed: f32 = 0,
    drawAmt: f32 = 0, // 0 = string home, 1 = full draw — the STRING pull (kinks to the hand)
    armT: f32 = 0, // the draw arm's arc: 0 rest → reach over the shoulder (quiver) → 1 anchor
    kick: f32 = 0, // loose follow-through (hand flies back, bow bounces); decays after
    headScan: f32 = 0, // idle sentry sweep (deg yaw) — the skull scans the ruins
    kiteDir: rl.Vector3 = mathx.zero3, // world XZ direction of the current reposition AND the leap
    looseFired: bool = false, // one arrow per loose (latched)
    backstepCd: f32 = 0, // the panic leap's long cooldown
    leapDone: f32 = 0, // ground already covered by the current leap (so travel integrates once)
    hop: f32 = 0, // world-space height off the ground mid-leap (rides the ROOT translate)

    // Shared humanoid GAIT STATE — hero.advanceGait drives these, hero.legChain animates the legs (the player's walk + strafe/backpedal). fwdB/latB = travel direction vs facing.
    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(HP_MAX, POISE_MAX, STANCE_MAX),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,
    fade: f32 = 0,
    gone: bool = false,

    xf: [N]rl.Matrix = undefined,
    stringXf: [2]rl.Matrix = undefined, // tip→nock, nock→tip (live string segments)
    nockXf: rl.Matrix = undefined,
    nockVis: bool = false,
    lastNock: rl.Vector3 = mathx.zero3, // the true release point (game.zig looses from here)
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Archer {
        var a = Archer{ .pos = home, .home = home, .facing = faceYaw, .scale = scale * SCALE, .seed = seed };
        a.rest = restPositions();
        a.reloadCd = 0.4 + seed; // stagger the volley so a line doesn't fire in lockstep
        a.pose();
        return a;
    }

    // All three ride `hop`: the backstep lifts the whole rig off the earth (pose() adds it to the pelvis), so a hurt sphere / reticle / HP bar pinned to ground height DETACHES from the body for the whole 0.44 s leap — the reticle sits at its feet and the blade tests empty air below it.
    pub fn centerWorld(self: *const Archer) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + 0.95 * H * self.scale + self.hop, self.pos.z);
    }
    pub fn hurtRadius(self: *const Archer) f32 {
        return HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Archer) f32 {
        return BODY_R * self.scale;
    }
    pub fn lockPoint(self: *const Archer) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + 0.90 * H * self.scale + self.hop, self.pos.z);
    }
    pub fn topWorld(self: *const Archer) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + 1.15 * H * self.scale + self.hop, self.pos.z);
    }
    pub fn alive(self: *const Archer) bool {
        return !self.gone;
    }
    pub fn staggered(self: *const Archer) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    pub fn dying(self: *const Archer) bool {
        return self.state == .dead;
    }
    pub fn flashFrac(self: *const Archer) f32 {
        return foe.flashFrac(self.flash);
    }
    // Off the ground only during the backstep's flight — the one time it leaves the earth.
    pub fn airborne(self: *const Archer) bool {
        return self.state == .backstep and self.hop > 0.04;
    }

    fn faceToward(self: *Archer, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt); // shared — see foe.zig
    }

    // The true nock point — where the arrow actually sits on the live string this frame, so the loosed projectile leaves from exactly where the nocked shaft was drawn.
    pub fn nockWorld(self: *const Archer) rl.Vector3 {
        return self.lastNock;
    }

    // `blade` is applied at the END (via tryHit) so a kill sets justDied for THIS frame's beat
    pub fn update(self: *Archer, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) bool {
        if (self.gone) return false;
        self.justDied = false; // one-frame flag: re-set below only if a blade kills it this frame
        self.elapsed += dt;
        self.vit.tick(dt);
        self.reloadCd = mathx.maxF(0, self.reloadCd - dt);
        self.backstepCd = mathx.maxF(0, self.backstepCd - dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        self.t += dt;
        var loosed = false;
        var movedDist: f32 = 0; // this frame's walk distance + heading → the shared gait
        var moveYaw: ?f32 = null;

        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt); // the bone-clatter jolt off a blow

        const d = mathx.distXZ(self.pos, hero);
        // THE PANIC LEAP interrupts whatever it was doing — checked before the state machine so a hero who closes mid-draw gets leapt away from on the same frame he arrives.
        if (wantsBackstep(d, self.backstepCd, self.state)) self.enterBackstep();
        switch (self.state) {
            .idle => {
                self.armT = mathx.approach(self.armT, 0, dt * 4.0);
                self.drawAmt = mathx.approach(self.drawAmt, 0, dt * 6.0);
                if (d <= AGGRO_R) {
                    self.faceToward(hero, dt);
                    self.headScan = mathx.approach(self.headScan, 0, dt * 70.0);
                } else {
                    // a slow sentry sweep — the empty skull scans the ruins for trespass
                    self.headScan = mathx.approach(self.headScan, 32.0 * mathx.sinf(self.elapsed * 0.55 + self.seed * 9.0), dt * 45.0);
                }
                self.decide(d);
            },
            .draw => {
                self.faceToward(hero, dt); // track while pulling
                const u = mathx.clampF(self.t / DRAW_DUR, 0, 1);
                self.armT = mathx.smoothstep(0, 0.92, u); // reach the quiver, nock, settle in
                self.drawAmt = mathx.smoothstep(0.60, 1.0, u); // the string comes back only once hooked
                if (self.t >= DRAW_DUR) self.enter(.hold);
            },
            .hold => {
                self.faceToward(hero, dt);
                self.armT = 1.0;
                self.drawAmt = 1.0;
                if (self.t >= HOLD_DUR) self.enter(.loose);
            },
            .loose => {
                const first = !self.looseFired;
                if (first) {
                    self.looseFired = true;
                    loosed = true; // game.zig spawns the arrow at nockWorld toward the hero
                    sfx.world(.bow_loose, self.pos); // the twang: the one cue that says MOVE
                }
                // The string only starts snapping AFTER the release frame.
                if (!first) {
                    const u = mathx.clampF(self.t / LOOSE_DUR, 0, 1);
                    self.drawAmt = 1.0 - mathx.smoothstep(0, 0.38, u); // the string SNAPS home ahead of the arm…
                    self.kick = mathx.smoothstep(0, 0.5, u); // …while the hand flies back off the release
                }
                if (self.t >= LOOSE_DUR) {
                    self.reloadCd = RELOAD_CD;
                    self.enter(.recover);
                }
            },
            .recover => {
                self.faceToward(hero, dt);
                self.armT = mathx.approach(self.armT, 0, dt * 2.4); // lower the bow, unhurried
                self.drawAmt = mathx.approach(self.drawAmt, 0, dt * 8.0);
                if (self.t >= RECOVER_DUR) self.decide(d);
            },
            .reposition => {
                self.armT = mathx.approach(self.armT, 0.15, dt * 3.0); // a wary half-ready carry
                self.drawAmt = mathx.approach(self.drawAmt, 0, dt * 6.0);
                // Step along the committed kite direction while FACING the hero — so travel-vs- facing feeds the shared gait as a STRAFE (lateral) or BACKPEDAL (kiting out).
                self.faceToward(hero, dt);
                const moved = WALK_SPEED * dt;
                mathx.stepXZ(&self.pos, self.kiteDir, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(self.kiteDir);
                if (self.t >= REPOSITION_DUR) self.decide(d);
            },
            .backstep => {
                // Coil, leap, land — FACING the hero the whole way (retreating, not fleeing: the bow comes straight back up on landing).
                self.faceToward(hero, dt);
                self.armT = mathx.approach(self.armT, 0.15, dt * 5.0);
                self.drawAmt = mathx.approach(self.drawAmt, 0, dt * 12.0); // the half-drawn shot is abandoned
                const want = leapTravel(self.t);
                const step = want - self.leapDone;
                self.leapDone = want;
                mathx.stepXZ(&self.pos, self.kiteDir, step, bounds);
                self.hop = BACKSTEP_RISE * mathx.sinf(leapU(self.t) * std.math.pi);
                if (self.t >= BACKSTEP_GATHER + BACKSTEP_FLIGHT + BACKSTEP_LAND) {
                    self.hop = 0;
                    self.decide(mathx.distXZ(self.pos, hero));
                }
            },
            .stunlight => {
                self.armT = mathx.approach(self.armT, 0, dt * 8.0);
                if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enter(.idle);
            },
            .stunheavy => {
                self.armT = mathx.approach(self.armT, 0, dt * 8.0);
                if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enter(.idle);
            },
            .dead => {
                self.armT = mathx.approach(self.armT, 0, dt * 3.0);
                self.drawAmt = mathx.approach(self.drawAmt, 0, dt * 8.0);
                if (self.t >= DEATH_DUR) {
                    self.fade = mathx.smoothstep(DEATH_DUR, DEATH_DUR + DISS_DUR, self.t);
                    if (self.t >= DEATH_DUR + DISS_DUR) self.gone = true;
                }
            },
        }
        if (self.state != .loose) self.kick = mathx.approach(self.kick, 0, dt * 4.5);

        // Drive the SHARED humanoid gait (the walk/strafe legs come from hero.legChain in pose()). legChain's geometry is entirely RIG-LOCAL (it divides the measured hip height by the root matrix's own scale), so the stride phase must be fed a SCALE-CORRECTED distance or a scale≠1 archer's planted foot skates — the same correction ogre.zig applies.
        const gaitSpeed: f32 = if (movedDist > 0) WALK_SPEED else 0;
        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, gaitSpeed, moveYaw, self.facing);
        self.pose();
        self.tryHit(blade); // hero's blade AFTER the state machine (like the toad); a kill here
        // flags justDied for this frame's kill beat, cleared at the top of the next update.
        return loosed;
    }

    fn enter(self: *Archer, s: State) void {
        self.state = s;
        self.t = 0;
        self.looseFired = false;
        // The DRAW is the tell — a creak of loading limbs that starts DRAW_DUR before the shaft leaves.
        if (s == .draw) sfx.world(.bow_draw, self.pos);
    }

    // Pick the next action from range + reload (kite AI).
    fn decide(self: *Archer, dist: f32) void {
        switch (classify(dist, self.reloadCd <= 0)) {
            .shoot => self.enter(.draw),
            .back_off => {
                self.kiteDir = self.awayDir();
                self.enter(.reposition);
            },
            .close_in => {
                self.kiteDir = mathx.scaleV(self.awayDir(), -1); // toward the hero
                self.enter(.reposition);
            },
            .hold_ground => self.enter(.idle),
        }
    }
    // Unit direction pointing straight away from the hero, from the archer's facing (it faces the hero, so −facing is "away"); a little seeded skew so a line doesn't retreat as one.
    fn awayDir(self: *const Archer) rl.Vector3 {
        const skew = (self.seed - 0.5) * 0.7;
        const yaw = self.facing + std.math.pi + skew;
        return mathx.headingDir(yaw);
    }

    // Commit a direction away from the hero, spend the cooldown, zero the travel integrator.
    fn enterBackstep(self: *Archer) void {
        self.state = .backstep;
        self.t = 0;
        self.looseFired = false;
        self.kiteDir = self.awayDir();
        self.leapDone = 0;
        self.hop = 0;
        self.backstepCd = BACKSTEP_CD;
    }

    fn enterStun(self: *Archer, s: State) void {
        self.state = s;
        self.t = 0;
        self.drawAmt = 0; // interrupted mid-draw — no shot leaves the bow
        self.looseFired = false;
        self.hop = 0; // caught in the air: it comes straight down
    }
    fn enterDeath(self: *Archer) void {
        self.state = .dead;
        self.t = 0;
        self.hop = 0;
        self.justDied = true;
    }

    // The leap's PELVIS: it coils, extends as it flies, gathers again to meet the ground, and absorbs.
    fn leapCrouch(self: *const Archer) f32 {
        if (self.state != .backstep) return 0;
        if (self.t < BACKSTEP_GATHER) return 0.11 * H * mathx.smoothstep(0, BACKSTEP_GATHER, self.t);
        const land = (self.t - BACKSTEP_GATHER - BACKSTEP_FLIGHT) / BACKSTEP_LAND;
        if (land < 0) {
            const u = leapU(self.t);
            return 0.11 * H * (1.0 - u) + 0.14 * H * mathx.smoothstep(0.6, 1.0, u);
        }
        return 0.14 * H * (1.0 - mathx.smoothstep(0, 1, mathx.clampF(land, 0, 1)));
    }

    fn tryHit(self: *Archer, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), blade) orelse return;
        self.hits += 1;
        self.flash = FLASH_DUR;
        const heavyBlow = blade.hit.stance > 0;
        self.shove = mathx.scaleV(s.dir, if (heavyBlow) 1.8 else 1.15); // a bone-clatter jolt off the blow
        sfx.world(.bone_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                sfx.world(.bone_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    pub fn pose(self: *Archer) void {
        const fs = self.scale * (1.0 - 0.7 * self.fade);
        const sink = -0.55 * self.scale * self.fade; // corpse sinks as it dissipates
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        // Death crumple: fold + topple as it collapses (reaction pose lives entirely here).
        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.45, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        // Stagger: a big recoil back off the blow (light = a pulse, heavy = a sustained reel).
        const stunAmt = self.stunAmount();

        // Shared humanoid WALK: a bob + weight-sway ride the pelvis (quieting on collapse), and the legs animate via hero.legChain below — the player's walk + strafe/backpedal footing.
        const m = self.moving * (1.0 - dk);
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const latW = @abs(self.latB) * m;
        // Sway/prot/dip all come from hero.zig so the sidestep reads IDENTICALLY on every humanoid (AGENTS.md's rule covers the trunk, not just legChain).
        const sway = heromod.strafeSway(latW, 0) * mathx.sinf(twoPi * self.phase) * m;
        const prot = A_PROT * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB) +
            heromod.strafeProt(self.phase, self.latB, m);
        const dip = heromod.STRAFE_DIP * latW;

        var wx: [N]rl.Matrix = undefined;
        const collapse = mathx.lerpF(hipY, 0.22 * H, dk); // pelvis drops on death
        const pitchBody = 20.0 * dk - 26.0 * stunAmt; // topple forward dead / arch back stunned
        // scaleM FIRST → the whole skeleton scales about its pelvis (per-archer size + the shrink `fs`); the world placement `tr(pos)` stays unscaled.
        const pelvY = if (dead) collapse else hipY + bob - dip - self.leapCrouch();
        // `self.hop` is WORLD units and rides outside the ×fs terms: the leap lifts the whole rig off the earth, and rig-local legChain neither knows nor needs to — its feet come up with the body, which is what airborne looks like.
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(10.0 * dk), rx(pitchBody), ry(prot)),
            mul(tr(sway * fs, pelvY * fs + sink + self.hop, 0), ry(facingDeg)),
            heromod.rootAt(self.pos), // …on the sculpted ground under him, not on y = 0
        ));

        // Legs: the SHARED walk/strafe (runB = 0 — the archer only walks).
        if (!dead) {
            heromod.legChain(&wx, &self.rest, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        }
        self.poseUpper(&wx, dk, stunAmt, dead, prot);
        self.xf = wx;
        self.poseString();
    }

    // The LIVE string + nocked arrow.
    fn poseString(self: *Archer) void {
        const tipU = rl.math.vector3Transform(v3(0, BOW_FY + TIP_UP, BOW_FZ + TIP_Z), self.xf[BOW]);
        const tipD = rl.math.vector3Transform(v3(0, BOW_FY - TIP_DN, BOW_FZ + TIP_Z), self.xf[BOW]);
        const restLine = mathx.lerpV(tipU, tipD, 0.52); // hooked a touch below centre
        const hand = rl.math.vector3Transform(FIST_L, self.xf[WRL]);
        const nock = mathx.lerpV(restLine, hand, self.drawAmt);
        self.lastNock = nock;
        self.stringXf[0] = stretchZ(tipU, nock);
        self.stringXf[1] = stretchZ(nock, tipD);
        self.nockVis = (self.state == .draw or self.state == .hold) and self.drawAmt > 0.03;
        if (self.nockVis) {
            const grip = rl.math.vector3Transform(v3(0, BOW_FY + 0.01 * H, BOW_FZ), self.xf[BOW]);
            const dir = mathx.normV(mathx.subV(grip, nock));
            self.nockXf = mul(orientZ(dir), tr(nock.x, nock.y, nock.z));
        }
    }

    // How much the trunk is folded over the leap right now (0..1): it builds through the coil, holds through the flight, and unwinds over the landing.
    fn leapLean(self: *const Archer) f32 {
        if (self.state != .backstep) return 0;
        const inAir = BACKSTEP_GATHER + BACKSTEP_FLIGHT;
        if (self.t < inAir) return mathx.smoothstep(0, BACKSTEP_GATHER * 1.4, self.t);
        return 1.0 - mathx.smoothstep(0, 1, mathx.clampF((self.t - inAir) / BACKSTEP_LAND, 0, 1));
    }

    fn stunAmount(self: *const Archer) f32 {
        if (self.state == .stunlight) {
            const u = mathx.clampF(self.t / combat.FOE_LIGHT_STUN_DUR, 0, 1);
            return mathx.sinf(u * std.math.pi);
        } else if (self.state == .stunheavy) {
            const u = mathx.clampF(self.t / combat.FOE_HEAVY_STUN_DUR, 0, 1);
            return mathx.pulse(u, 0, 0.14, 0.7, 1.0);
        }
        return 0;
    }

    // Spine, head, the archery arms, and (only when DEAD) the buckling legs (`dk` = death collapse, `stun` = recoil).
    fn poseUpper(self: *Archer, wx: *[N]rl.Matrix, dk: f32, stun: f32, dead: bool, prot: f32) void {
        const rest = self.rest;
        const at = self.armT;
        const dr = self.drawAmt;
        // The draw-arm arc in two beats: REACH over the shoulder for a shaft from the quiver (at 0→0.45), then sweep down and PULL to the cheek anchor (at 0.45→1).
        const reach = mathx.smoothstep(0.0, 0.45, at);
        const pull = mathx.smoothstep(0.45, 1.0, at);
        // Seeded wonk — each archer stands a little crooked (cosmetic only; wabi-sabi).
        const wonk = (self.seed - 0.5) * 6.0;

        // Spine: a slight ready-stoop that blades side-on through the pull, leaning back a hair at full draw (the counterweight); curls on death, arches back when stunned.
        const spineX = 4.0 - 3.0 * dr + 22.0 * dk - 20.0 * stun + 26.0 * self.leapLean();
        setLocal(wx, SPINE, rest, mul3(rx(spineX * 0.5), ry(-0.35 * prot), rz(wonk * 0.5)));
        setLocal(wx, CHEST, rest, mul3(rx(spineX * 0.5), ry(-0.5 * prot - 5.0 * reach - 9.0 * pull), rz(-wonk * 0.3)));
        setLocal(wx, NECK, rest, rx(3.0 + 12.0 * dk - 8.0 * stun));
        // Head: sentry-scans at rest, sights down the shaft as the pull anchors — craned in and CANTED onto the arrow (the archer's cheek-weld); lolls aside as it dies.
        setLocal(wx, SKULL, rest, mul3(
            rx(6.0 + 4.0 * pull + 20.0 * dk - 30.0 * stun),
            ry(self.headScan + 8.0 * pull),
            rz(wonk + 9.0 * dr + 14.0 * dk),
        ));

        // Legs buckle under the crumple ONLY when dead; alive, hero.legChain (pose()) owns them.
        if (dead) {
            setLocal(wx, HIPL, rest, mul(rx(-60.0 * dk), rz(-3.0)));
            setLocal(wx, KNEEL, rest, rx(8.0 + 100.0 * dk));
            setLocal(wx, ANKL, rest, ry(7.0));
            setLocal(wx, HIPR, rest, mul(rx(-52.0 * dk), rz(3.0)));
            setLocal(wx, KNEER, rest, rx(8.0 + 92.0 * dk));
            setLocal(wx, ANKR, rest, ry(-7.0));
        }
        // …and the OTHER time legChain is wrong: mid-leap the ground is a third of a metre below the feet and legChain's job is putting them ON it.
        if (self.state == .backstep) {
            const u = leapU(self.t);
            const w = mathx.sinf(mathx.clampF(u, 0, 1) * std.math.pi);
            if (w > 0.02) {
                const catchUp = mathx.smoothstep(0.52, 1.0, u); // the legs come forward to land
                const hipA = -32.0 * w + 34.0 * catchUp;
                const kneeA = 10.0 + 84.0 * w - 46.0 * catchUp;
                setLocal(wx, HIPL, rest, mul(rx(hipA + 7.0), rz(-4.0)));
                setLocal(wx, KNEEL, rest, rx(kneeA + 9.0));
                setLocal(wx, ANKL, rest, rx(-14.0 * w));
                setLocal(wx, HIPR, rest, mul(rx(hipA - 6.0), rz(4.0)));
                setLocal(wx, KNEER, rest, rx(kneeA - 7.0));
                setLocal(wx, ANKR, rest, rx(-11.0 * w));
            }
        }

        const armStun = -70.0 * stun; // arms fly up when hit
        // Right arm = the BOW arm: rises early in the draw from a low carry, punching the bow out toward the target, elbow near-straight; a small forward BOUNCE off the release.
        const bowT = mathx.clampF(at * 1.7, 0, 1);
        const bowShFwd = mathx.lerpF(-26.0, -88.0, bowT) + 5.0 * self.kick + armStun;
        setLocal(wx, SHR, rest, mul(rx(bowShFwd - 30.0 * dk), rz(-9.0 + wonk * 0.4)));
        setLocal(wx, ELR, rest, rx(-(8.0 + 5.0 * bowT)));
        setLocal(wx, WRR, rest, rz(-6.0 - 4.0 * self.kick));
        // rx(100) stands the bow VERTICAL, ry(180) faces it — string toward the archer, limbs bowing out to the target; the whole bow rocks forward a touch off the loose.
        setLocal(wx, BOW, rest, mul(ry(180.0), rx(100.0 - 3.0 * self.kick)));

        // Left arm = the DRAW arm: beat one plucks a shaft from the back quiver (hand up-and-back over the shoulder), beat two hauls to the cheek with the elbow riding HIGH (the signature silhouette).
        const wob = (mathx.sinf(self.elapsed * 9.0 + self.seed * 7.0) + 0.5 * mathx.sinf(self.elapsed * 23.0)) * 1.1 * dr;
        const drawSh = -26.0 - 102.0 * reach + 44.0 * pull + armStun - 30.0 * dk + wob;
        const drawYaw = -26.0 * reach + 10.0 * pull; // out-and-back at the quiver, in at the anchor
        const drawRz = 9.0 + 24.0 * pull - wonk * 0.4; // the drawing elbow rides up
        const drawEl = 16.0 + 104.0 * reach + 32.0 * pull - 30.0 * self.kick;
        setLocal(wx, SHL, rest, mul3(rx(drawSh), ry(drawYaw), rz(drawRz)));
        setLocal(wx, ELL, rest, rx(-drawEl));
        setLocal(wx, WRL, rest, rx(-12.0 * self.kick));
    }

    pub fn draw(self: *const Archer, model: *const Model) void {
        model.draw(self);
    }
};

// WHERE the archers are perched is the MAP's business now (`foe: archer …` records).
const CAP = wf.MAX_PER_KIND;

pub const Line = struct {
    model: Model,
    archers: [CAP]Archer = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Line {
        return .{ .model = Model.init(shader) };
    }
    /// The archers this map posted — never iterate the whole array, the tail is `undefined`.
    pub fn live(self: *Line) []Archer {
        return self.archers[0..self.n];
    }
    /// Read-only view, for the `*const Line` paths (draw, the roll-ups).
    pub fn liveConst(self: *const Line) []const Archer {
        return self.archers[0..self.n];
    }
    // Re-perch every archer, alive and fresh (a hero death reloads the world, ER-style).
    pub fn reset(self: *Line, m: *const wf.Map) void {
        foe.resetGroup(Archer, &self.archers, &self.n, m, .archer);
    }
    pub fn setShader(self: *Line, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Line, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    // The shared Group roll-ups (foe.zig).
    pub fn anyDied(self: *const Line) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn runesDropped(self: *const Line) u32 {
        return foe.runesDropped(self.liveConst(), RUNES);
    }
    pub fn totalHits(self: *const Line) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Line) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

// Every bone carries its own seeded wonk — kinks, waists, stains, uneven knobs — so no two
fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = ribcageMesh();
    mesh[NECK] = neckMesh();
    mesh[SKULL] = skullMesh();
    mesh[HIPL] = femurMesh(101);
    mesh[KNEEL] = tibiaMesh(102);
    mesh[ANKL] = footMesh(1.0, 103);
    mesh[HIPR] = femurMesh(104);
    mesh[KNEER] = tibiaMesh(105);
    mesh[ANKR] = footMesh(-1.0, 106);
    mesh[SHL] = humerusMesh(107);
    mesh[ELL] = forearmMesh(108);
    mesh[WRL] = handMesh(109);
    mesh[SHR] = humerusMesh(110);
    mesh[ELR] = forearmMesh(111);
    mesh[WRR] = handMesh(112);
    mesh[BOW] = bowMesh();
    return mesh;
}

// A bone: a kinked, waisted shaft with a fatter articular knob at each joint end — never machine-straight.
fn bone(b: *Builder, rng: *mathx.Rng, a: rl.Vector3, e: rl.Vector3, r: f32, col: rl.Color) void {
    const mid = v3(
        (a.x + e.x) * 0.5 + rng.range(-0.007, 0.007) * H,
        (a.y + e.y) * 0.5,
        (a.z + e.z) * 0.5 + rng.range(-0.007, 0.007) * H,
    );
    const rm = r * rng.range(0.78, 0.9); // old bone waists at mid-shaft
    b.addCylinder(a, mid, r, rm, 7, col);
    b.addCylinder(mid, e, rm, r * 0.92, 7, col);
    b.addCylinder(v3(a.x, a.y + r * 0.6, a.z), v3(a.x, a.y - r * 0.6, a.z), r * rng.range(1.5, 1.75), r * 1.55, 7, BONE_LT);
    b.addCylinder(v3(e.x, e.y + r * 0.6, e.z), v3(e.x, e.y - r * 0.6, e.z), r * rng.range(1.4, 1.65), r * 1.5, 7, BONE_LT);
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    // An OPEN bony girdle, not a solid block: sacrum wedge, two flared iliac blades (the left runs bigger — wabi-sabi), a thin pubic bar, hip-socket knobs — and dark void within.
    b.addCube(v3(0, 0.0, -0.02 * H), v3(0.085 * H, 0.10 * H, 0.075 * H), BONE_DK); // sacrum wedge
    b.addCube(v3(0, -0.045 * H, -0.005 * H), v3(0.11 * H, 0.055 * H, 0.055 * H), SOCKET); // the hollow within
    b.addBox(v3(0.082 * H, 0.022 * H, 0.0), v3(0.05 * H, 0.024 * H, 0.0), v3(0.014 * H, 0.062 * H, 0.0), v3(0, 0, 0.055 * H), BONE); // L ilium blade
    b.addBox(v3(-0.080 * H, 0.018 * H, 0.0), v3(0.046 * H, 0.02 * H, 0.0), v3(-0.012 * H, 0.056 * H, 0.0), v3(0, 0, 0.050 * H), STAIN); // R ilium — smaller, dirt-stained
    b.addCylinder(v3(0.07 * H, -0.055 * H, 0.045 * H), v3(-0.07 * H, -0.055 * H, 0.045 * H), 0.016 * H, 0.016 * H, 6, BONE_DK); // pubic bar
    b.addCylinder(v3(0.090 * H, -0.002 * H, 0.01 * H), v3(0.090 * H, -0.032 * H, 0.01 * H), 0.030 * H, 0.026 * H, 7, BONE_LT); // L hip socket
    b.addCylinder(v3(-0.090 * H, -0.002 * H, 0.01 * H), v3(-0.090 * H, -0.032 * H, 0.01 * H), 0.030 * H, 0.026 * H, 7, BONE_LT); // R hip socket
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    // A short CROOKED stack of lumbar vertebrae — each drifts a hair off plumb (old spines settle; nothing machined) — spinous processes poking back.
    var rng = mathx.Rng.init(2203);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const y = 0.01 * H + @as(f32, @floatFromInt(i)) * 0.032 * H;
        const ox = rng.range(-0.006, 0.006) * H;
        b.addCube(v3(ox, y, -0.02 * H), v3(0.055 * H, 0.021 * H, 0.05 * H), if (@mod(i, 2) == 0) BONE else STAIN); // vertebral body
        b.addCube(v3(ox, y, -0.052 * H), v3(0.028 * H, 0.014 * H, 0.032 * H), BONE_DK); // spinous process
    }
    return b.toMesh();
}

fn ribcageMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    // Thorax joint ~0.76 H; a near-black CORE fills the chest so the rib gaps read as hollow void, not daylight.
    b.addCube(v3(0, 0.015 * H, -0.005 * H), v3(0.13 * H, 0.185 * H, 0.10 * H), SOCKET); // the hollow core
    b.addCube(v3(0, 0.02 * H, -0.07 * H), v3(0.05 * H, 0.17 * H, 0.05 * H), BONE_DK); // thoracic spine
    b.addCube(v3(0, 0.032 * H, 0.078 * H), v3(0.036 * H, 0.125 * H, 0.016 * H), BONE_LT); // sternum
    // shoulder girdle: clavicles (uneven pair) so the arms hang off real bone
    b.addBox(v3(0.07 * H, 0.10 * H, 0.02 * H), v3(0.075 * H, 0.012 * H, 0.0), v3(0, 0.012 * H, 0), v3(0, 0, 0.02 * H), BONE); // L clavicle
    b.addBox(v3(-0.07 * H, 0.10 * H, 0.02 * H), v3(0.075 * H, 0.015 * H, 0.0), v3(0, 0.010 * H, 0), v3(0, 0, 0.02 * H), STAIN); // R clavicle — thicker, stained
    var rng = mathx.Rng.init(911);
    const levels = [_]f32{ 0.088, 0.052, 0.014, -0.024, -0.060 }; // rib heights (H) off the joint
    const halfw = [_]f32{ 0.104, 0.122, 0.120, 0.105, 0.082 }; // cage half-width at each level
    const fwd = [_]f32{ 0.080, 0.094, 0.090, 0.076, 0.056 }; // sternum reach at each level
    for (0..levels.len) |li| {
        const y = levels[li] * H;
        const w = halfw[li] * H;
        const fz = fwd[li] * H;
        const rr = 0.0095 * H * rng.range(0.9, 1.12); // rib gauge drifts rib to rib
        const col = if (@mod(li, 2) == 0) BONE else BONE_LT;
        for ([_]f32{ 1, -1 }) |sgn| {
            const droop = rng.range(-0.004, 0.010) * H; // each rib settles its own way
            const spinePt = v3(0, y, -0.06 * H);
            const sidePt = v3(sgn * w, y - 0.006 * H - droop, 0.01 * H);
            const frontPt = v3(sgn * 0.02 * H, y - 0.014 * H - droop, fz);
            b.addCylinder(spinePt, sidePt, rr, rr, 5, col);
            if (li == 3 and sgn > 0) {
                // the snapped rib: its front run dies at a jagged stub short of the sternum
                const stub = mathx.lerpV(sidePt, frontPt, 0.38);
                b.addCylinder(sidePt, stub, rr, rr * 0.25, 5, STAIN);
            } else {
                b.addCylinder(sidePt, frontPt, rr, rr * 0.85, 5, col);
            }
        }
    }
    // fan of spare shafts at odd heights.
    b.setMat(.leather);
    const qBase = v3(0.010 * H, -0.095 * H, -0.105 * H);
    const qMouth = v3(0.125 * H, 0.115 * H, -0.120 * H);
    b.addCylinder(qBase, qMouth, 0.026 * H, 0.033 * H, 7, QUIVER_HIDE);
    b.addCylinder(mathx.lerpV(qBase, qMouth, 0.94), qMouth, 0.036 * H, 0.035 * H, 7, QUIVER_LT); // rolled rim
    b.addCylinder(mathx.lerpV(qBase, qMouth, 0.30), mathx.lerpV(qBase, qMouth, 0.44), 0.0345 * H, 0.0345 * H, 7, QUIVER_LT); // patch band
    b.addBox(v3(0.0, 0.02 * H, 0.088 * H), v3(0.075 * H, 0.085 * H, 0.0), v3(-0.012 * H, 0.010 * H, 0.0), v3(0, 0, 0.007 * H), QUIVER_HIDE); // the worn strap, shoulder→hip across the ribs
    b.setMat(.wood);
    var qi: i32 = 0;
    while (qi < 3) : (qi += 1) {
        const fi = @as(f32, @floatFromInt(qi));
        const off = v3(rng.range(-0.012, 0.012) * H, 0, rng.range(-0.012, 0.012) * H);
        const foot = mathx.addV(mathx.lerpV(qBase, qMouth, 0.5), off);
        const tip = mathx.addV(mathx.addV(qMouth, off), v3(rng.range(0.0, 0.03) * H + fi * 0.008 * H, rng.range(0.08, 0.15) * H, rng.range(-0.02, 0.01) * H));
        b.addCylinder(foot, tip, 0.006 * H, 0.005 * H, 4, ARROW_SHAFT);
        if (qi != 1) { // fletched — except the one bare shaft (wabi-sabi)
            b.setMat(.cloth);
            const fb = mathx.lerpV(foot, tip, 0.82);
            b.addBox(fb, v3(0.002 * H, 0, 0), v3(0, 0.022 * H, 0.004 * H), v3(0, 0.004 * H, 0.020 * H), ARROW_FLETCH);
            b.setMat(.wood);
        }
    }
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    b.addCylinder(v3(0, 0, 0), v3(0, 0.070 * H, 0), 0.026 * H, 0.024 * H, 7, BONE_DK); // cervical column
    b.addCube(v3(0, 0.020 * H, 0), v3(0.032 * H, 0.018 * H, 0.032 * H), BONE); // a vertebra ring
    b.addCube(v3(0, 0.048 * H, -0.004 * H), v3(0.028 * H, 0.014 * H, 0.028 * H), STAIN); // and another, askew
    return b.toMesh();
}

fn skullMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    // Head joint ~0.885 H (chin line); cranium lands ~1.0 H.
    b.addCylinder(v3(0, 0.06 * H, -0.008 * H), v3(0, 0.114 * H, -0.010 * H), 0.066 * H, 0.048 * H, 9, BONE); // crown (inside the box line — no hat-brim ledge)
    b.addCube(v3(0, 0.058 * H, -0.004 * H), v3(0.140 * H, 0.082 * H, 0.138 * H), BONE); // cranium box
    b.addCube(v3(0.020 * H, 0.098 * H, 0.010 * H), v3(0.014 * H, 0.030 * H, 0.11 * H), STAIN); // the old cleft, stained dark
    b.addCube(v3(0, 0.075 * H, 0.062 * H), v3(0.126 * H, 0.026 * H, 0.030 * H), BONE_LT); // brow ridge
    // eye sockets — DEEP black wells under the brow (the read at any distance), uneven
    b.addCube(v3(0.043 * H, 0.048 * H, 0.064 * H), v3(0.054 * H, 0.048 * H, 0.028 * H), SOCKET);
    b.addCube(v3(-0.041 * H, 0.046 * H, 0.064 * H), v3(0.048 * H, 0.044 * H, 0.028 * H), SOCKET);
    b.addCube(v3(0, 0.028 * H, 0.070 * H), v3(0.022 * H, 0.042 * H, 0.026 * H), SOCKET); // nasal cavity
    b.addCube(v3(0.058 * H, 0.026 * H, 0.048 * H), v3(0.030 * H, 0.028 * H, 0.042 * H), BONE_DK); // L cheekbone
    b.addCube(v3(-0.056 * H, 0.024 * H, 0.046 * H), v3(0.024 * H, 0.022 * H, 0.038 * H), STAIN); // R cheekbone — chipped smaller
    // upper jaw over a dark GAPE, the mandible slung low (an undead skull hangs open a little)
    b.addCube(v3(0, 0.008 * H, 0.052 * H), v3(0.082 * H, 0.028 * H, 0.058 * H), BONE); // maxilla
    b.addCube(v3(0, -0.020 * H, 0.048 * H), v3(0.070 * H, 0.026 * H, 0.052 * H), SOCKET); // the gape
    b.addCube(v3(0, -0.038 * H, 0.046 * H), v3(0.078 * H, 0.020 * H, 0.056 * H), BONE_DK); // mandible
    var trng = mathx.Rng.init(4801);
    var i: i32 = -3;
    while (i <= 3) : (i += 1) {
        const tx = @as(f32, @floatFromInt(i)) * 0.019 * H;
        if (trng.float() >= 0.14) // upper row (the odd tooth missing)
            b.addCube(v3(tx, -0.006 * H, 0.082 * H), v3(0.010 * H, 0.020 * H * trng.range(0.7, 1.25), 0.009 * H), TEETH);
        if (trng.float() >= 0.25) // lower row — more gaps, shorter pegs
            b.addCube(v3(tx + 0.004 * H, -0.030 * H, 0.078 * H), v3(0.009 * H, 0.013 * H * trng.range(0.6, 1.1), 0.008 * H), TEETH);
    }
    return b.toMesh();
}

fn femurMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    var rng = mathx.Rng.init(seed);
    bone(&b, &rng, v3(0, 0, 0), v3(0, -SEG_THIGH * H, 0), 0.024 * H, if (rng.float() < 0.4) STAIN else BONE);
    return b.toMesh();
}

fn tibiaMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    var rng = mathx.Rng.init(seed);
    bone(&b, &rng, v3(0, 0, 0), v3(0, -SEG_SHANK * H, 0), 0.020 * H, BONE);
    b.addCylinder(v3(0.014 * H, -0.01 * H, 0.006 * H), v3(0.007 * H, -SEG_SHANK * H * 0.82, 0.004 * H), 0.008 * H, 0.005 * H, 5, STAIN); // fibula alongside
    return b.toMesh();
}

fn footMesh(side: f32, seed: u64) rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    var rng = mathx.Rng.init(seed);
    const ay = 0.039 * H;
    b.addCube(v3(0, -ay + 0.018 * H, 0.045 * H), v3(0.046 * H, 0.026 * H, 0.115 * H), BONE_DK); // metatarsal plate
    for ([_]f32{ -1, 0, 1 }) |t| { // toe bones fan forward, each its own length
        const tl = rng.range(0.125, 0.155);
        b.addCylinder(v3(t * 0.017 * H * side, -ay + 0.014 * H, 0.09 * H), v3(t * 0.027 * H * side, -ay + 0.010 * H, tl * H), 0.0075 * H, 0.0045 * H, 4, BONE);
    }
    b.addCube(v3(0, -ay + 0.028 * H, -0.02 * H), v3(0.034 * H, 0.038 * H, 0.038 * H), STAIN); // heel / calcaneus
    return b.toMesh();
}

fn humerusMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    var rng = mathx.Rng.init(seed);
    bone(&b, &rng, v3(0, 0, 0), v3(0, -SEG_UPARM * H, 0), 0.020 * H, if (rng.float() < 0.3) STAIN else BONE);
    return b.toMesh();
}

fn forearmMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    var rng = mathx.Rng.init(seed);
    // Radius + ulna: two thin parallel bones for the skeletal read.
    bone(&b, &rng, v3(0.008 * H, 0, 0), v3(0.008 * H, -SEG_FOREARM * H, 0), 0.013 * H, BONE);
    b.addCylinder(v3(-0.012 * H, -0.004 * H, 0.004 * H), v3(-0.006 * H, -SEG_FOREARM * H, 0.002 * H), 0.011 * H, 0.008 * H, 6, STAIN);
    return b.toMesh();
}

fn handMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    var rng = mathx.Rng.init(seed);
    b.addCube(v3(0, -0.03 * H, 0.005 * H), v3(0.034 * H, 0.048 * H, 0.028 * H), BONE_DK); // metacarpals / palm
    for ([_]f32{ -1.5, -0.5, 0.5, 1.5 }) |fgr| { // a bony claw — finger lengths drift
        const fl = rng.range(0.068, 0.082);
        b.addCylinder(v3(fgr * 0.012 * H, -0.055 * H, 0.01 * H), v3(fgr * 0.014 * H, -fl * H, 0.030 * H), 0.0065 * H, 0.0035 * H, 4, BONE);
    }
    return b.toMesh();
}

// The bow, authored in the RIGHT-WRIST frame about the fist — a TALL recurve, wrapped grip, horn nocks, limbs UNEVEN (lower a touch shorter).
fn bowMesh() rl.Mesh {
    var b = Builder.init();
    const fy = BOW_FY;
    const fz = BOW_FZ;
    b.setMat(.leather);
    b.addCylinder(v3(0, fy + 0.055 * H, fz), v3(0, fy - 0.055 * H, fz), 0.019 * H, 0.019 * H, 7, GRIP_WRAP); // wrapped grip
    b.addCylinder(v3(0, fy + 0.012 * H, fz), v3(0, fy - 0.012 * H, fz), 0.021 * H, 0.021 * H, 7, BOWWOOD_LT); // binding band
    b.setMat(.wood);
    const uy = [_]f32{ 0.055, 0.22, 0.40 }; // upper limb (reach = TIP_UP)
    const ly = [_]f32{ 0.055, 0.21, 0.37 }; // lower limb, shorter (TIP_DN)
    const zz = [_]f32{ 0.0, -0.028, 0.06 }; // sweeps back, recurves forward at the tip (TIP_Z)
    const rr = [_]f32{ 0.016, 0.011, 0.005 };
    for (0..2) |seg| {
        b.addCylinder(v3(0, fy + uy[seg] * H, fz + zz[seg] * H), v3(0, fy + uy[seg + 1] * H, fz + zz[seg + 1] * H), rr[seg] * H, rr[seg + 1] * H, 6, BOWWOOD);
        b.addCylinder(v3(0, fy - ly[seg] * H, fz + zz[seg] * H), v3(0, fy - ly[seg + 1] * H, fz + zz[seg + 1] * H), rr[seg] * H, rr[seg + 1] * H, 6, BOWWOOD);
    }
    b.setMat(.plain);
    // horn nocks capping the tips (where the live string ties on)
    b.addCylinder(v3(0, fy + 0.385 * H, fz + 0.054 * H), v3(0, fy + 0.406 * H, fz + 0.062 * H), 0.008 * H, 0.004 * H, 5, TEETH);
    b.addCylinder(v3(0, fy - 0.352 * H, fz + 0.054 * H), v3(0, fy - 0.376 * H, fz + 0.062 * H), 0.008 * H, 0.004 * H, 5, TEETH);
    return b.toMesh();
}

// A unit string segment: hair-thin, 0→+Z, length 1 — poseString stretches two of these tip→nock→tip every frame, so the string really hauls back, kinks, and snaps home.
fn stringMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.plain);
    b.addCylinder(v3(0, 0, 0), v3(0, 0, 1), 0.0032 * H, 0.0032 * H, 4, STRINGCOL);
    return b.toMesh();
}

// The nocked arrow — tail AT the origin (it rides the string nock), head out +Z, ~0.72 long (matches the loosed projectile's gauge so the hand-off is seamless).
fn nockArrowMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.wood);
    b.addCylinder(v3(0, 0, 0.01), v3(0, 0, 0.63), 0.00825, 0.00825, 5, ARROW_SHAFT);
    b.setMat(.steel);
    b.addCylinder(v3(0, 0, 0.63), v3(0, 0, 0.73), 0.01875, 0.001, 5, ARROW_HEAD);
    b.setMat(.cloth);
    b.addBox(v3(0, 0.021, 0.07), v3(0.0009, 0, 0), v3(0, 0.033, 0), v3(0, 0, 0.075), ARROW_FLETCH);
    b.addBox(v3(0.01875, -0.0128, 0.07), v3(0.0009, 0, 0), v3(0.0285, -0.01875, 0), v3(0, 0, 0.075), ARROW_FLETCH);
    b.addBox(v3(-0.01875, -0.0128, 0.07), v3(0.0009, 0, 0), v3(-0.0285, -0.01875, 0), v3(0, 0, 0.075), ARROW_FLETCH);
    return b.toMesh();
}

// Gauge + fletching run FAT for visibility — a projectile you're meant to dodge must read at
pub fn arrowMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    // Authored along +Z (the flight axis); game.zig orients it to the velocity. ~0.74 m long.
    b.setMat(.wood);
    b.addCylinder(v3(0, 0, -0.3525), v3(0, 0, 0.285), 0.0128, 0.0113, 5, ARROW_SHAFT); // shaft
    b.setMat(.steel);
    b.addCylinder(v3(0, 0, 0.285), v3(0, 0, 0.39), 0.0255, 0.001, 5, ARROW_HEAD); // pile / head
    b.setMat(.cloth);
    // fletching: three big pale vanes at the tail (the tracer the eye tracks)
    b.addBox(v3(0, 0.0285, -0.2925), v3(0.0012, 0, 0), v3(0, 0.045, 0), v3(0, 0, 0.075), ARROW_FLETCH);
    b.addBox(v3(0.0255, -0.0173, -0.2925), v3(0.0012, 0, 0), v3(0.039, -0.0255, 0), v3(0, 0, 0.075), ARROW_FLETCH);
    b.addBox(v3(-0.0255, -0.0173, -0.2925), v3(0.0012, 0, 0), v3(-0.039, -0.0255, 0), v3(0, 0, 0.075), ARROW_FLETCH);
    return b.toModel(shader);
}

test "kite AI: too close backs off, too far closes, in-band shoots when reloaded" {
    try std.testing.expectEqual(Choice.hold_ground, classify(AGGRO_R + 1, true)); // disengaged
    try std.testing.expectEqual(Choice.back_off, classify(RANGE_MIN - 1, true)); // crowded
    try std.testing.expectEqual(Choice.close_in, classify(RANGE_MAX + 1, true)); // too far
    try std.testing.expectEqual(Choice.shoot, classify((RANGE_MIN + RANGE_MAX) * 0.5, true)); // in band, nocked
    try std.testing.expectEqual(Choice.hold_ground, classify((RANGE_MIN + RANGE_MAX) * 0.5, false)); // in band, reloading
}

test "range band is ordered and sits inside aggro" {
    try std.testing.expect(RANGE_MIN < RANGE_MAX and RANGE_MAX < AGGRO_R);
}

test "the backstep fires only when crowded, off cooldown, and interruptible" {
    try std.testing.expect(wantsBackstep(BACKSTEP_R - 0.5, 0, .draw)); // crowded mid-draw: bail
    try std.testing.expect(wantsBackstep(BACKSTEP_R - 0.5, 0, .reposition)); // …even while kiting
    try std.testing.expect(!wantsBackstep(BACKSTEP_R + 0.5, 0, .draw)); // not crowded yet
    try std.testing.expect(!wantsBackstep(BACKSTEP_R - 0.5, 3.0, .draw)); // still on cooldown
    try std.testing.expect(!wantsBackstep(0.5, 0, .loose)); // the arrow is already leaving
    try std.testing.expect(!wantsBackstep(0.5, 0, .stunheavy)); // staggered: it cannot
    try std.testing.expect(!wantsBackstep(0.5, 0, .dead));
    try std.testing.expect(!wantsBackstep(0.5, 0, .backstep)); // no chaining into itself
}

test "the leap clears sword reach, lands where its curve says, and never overshoots" {
    // It must actually ESCAPE: starting at the trigger radius, the landing has to put the archer back inside its shooting band, or the evade buys nothing and the hero just walks after it.
    try std.testing.expect(BACKSTEP_R + BACKSTEP_DIST > RANGE_MIN);
    // The travel curve is monotonic, starts at nothing, and finishes at exactly BACKSTEP_DIST — the position is integrated from it frame by frame, so a curve that overshot would teleport.
    try std.testing.expectApproxEqAbs(@as(f32, 0), leapTravel(0), 1e-5);
    try std.testing.expectApproxEqAbs(BACKSTEP_DIST, leapTravel(BACKSTEP_GATHER + BACKSTEP_FLIGHT), 1e-4);
    var prev: f32 = -1;
    var t: f32 = 0;
    while (t <= BACKSTEP_GATHER + BACKSTEP_FLIGHT + BACKSTEP_LAND) : (t += 0.01) {
        const d = leapTravel(t);
        try std.testing.expect(d >= prev - 1e-5 and d <= BACKSTEP_DIST + 1e-4);
        prev = d;
    }
    // And the cooldown has to outlast the move several times over, or it is a kite, not a panic.
    try std.testing.expect(BACKSTEP_CD > 4.0 * (BACKSTEP_GATHER + BACKSTEP_FLIGHT + BACKSTEP_LAND));
}

test "an arrow in flight lays a trail, and a pooled one never inherits the last shot's" {
    const dt: f32 = 1.0 / 60.0;
    var a = launchArrow(v3(0, 1.4, 0), v3(0, 1.0, 14.0));
    // A FRESH arrow has no trail at all: every age starts saturated, so the ribbon cannot draw a streak from wherever this pool slot was last used — which would flash a band across the map on the shot's first frame.
    for (a.trailAge) |g| try std.testing.expect(g >= TRAIL_LIFE);
    var i: u32 = 0;
    while (i < 6) : (i += 1) stepArrow(&a, v3(0, 0, 14.0), 1.0, 0, false, &.{}, dt);
    // Six frames of flight → six live samples, the newest at `trailHead` with age 0.
    try std.testing.expectApproxEqAbs(@as(f32, 0), a.trailAge[a.trailHead], 1e-6);
    var live: u32 = 0;
    for (a.trailAge) |g| {
        if (g < TRAIL_LIFE) live += 1;
    }
    try std.testing.expectEqual(@as(u32, 6), live);
    // …and they are DISTINCT positions marching along the flight, or the ribbon has no length and every segment collapses to a degenerate quad.
    const newest = a.trail[a.trailHead];
    const prev = a.trail[(a.trailHead + TRAIL_N - 1) % TRAIL_N];
    try std.testing.expect(mathx.lenV(mathx.subV(newest, prev)) > 0.05);
    try std.testing.expect(newest.z > prev.z); // marching the way it is flying

    // A STUCK arrow stops laying trail — its streak ages out behind it instead of hanging in the air.
    a.stuck = true;
    const headAtStick = a.trailHead;
    stepArrow(&a, v3(0, 0, 14.0), 1.0, 0, false, &.{}, dt);
    try std.testing.expectEqual(headAtStick, a.trailHead);
}

test "arrows thunk into cover instead of piercing it; tall shots clear a LOW blocker" {
    // A chest-high wall dead on the flight line: the flat shot must stick in it, short of the target — cover answers the archers.
    var low = collision.circle(0, 5.0, 0.8);
    low.h = 0.9;
    var tall = low;
    tall.h = 5.0;
    const dt: f32 = 1.0 / 60.0;

    var blocked = launchArrow(v3(0, 1.3, 0), v3(0, 1.0, 12.0));
    var i: u32 = 0;
    while (i < 120 and !blocked.stuck) : (i += 1)
        stepArrow(&blocked, v3(0, 0, 12.0), 1.0, 0, false, &.{tall}, dt);
    try std.testing.expect(blocked.stuck and !blocked.hit);
    try std.testing.expect(blocked.pos.z < 5.5); // it died AT the wall, not at the target

    // The same shot over a knee-high grave sails past it (arrows arc honestly over low cover).
    var over = launchArrow(v3(0, 1.3, 0), v3(0, 1.0, 12.0));
    i = 0;
    while (i < 240 and !over.stuck) : (i += 1)
        stepArrow(&over, v3(0, 0, 12.0), 1.0, 0, false, &.{low}, dt);
    try std.testing.expect(over.stuck and over.pos.z > 5.5); // cleared the grave, landed well beyond
}

test "a shot that is aimed at a standing hero HITS him, at every range and either weight" {
    // The solved loft is an EQUALITY, so this is not a tolerance check on a feel dial: a target that does not move must be struck whatever the distance, and it was the slinger sailing over the hero's head at every range that said the loft was being guessed.
    const dt: f32 = 1.0 / 60.0;
    const heroY: f32 = 1.0;
    for ([_]f32{ 3, 8, 14, 20 }) |range| {
        const hero = v3(0, 0, range);
        const aim = v3(0, heroY, range);
        // From a launch point ABOVE the target (a bow at the chest, a sling pouch over the head) and from BELOW it, since the aim line's own slope is what the old loft was fighting.
        for ([_]f32{ 1.4, 2.1, 0.4 }) |fromY| {
            var shaft = launchArrow(v3(0, fromY, 0), aim);
            var stone = launchStone(v3(0, fromY, 0), aim, 11.0);
            var i: u32 = 0;
            while (i < 600 and !shaft.stuck) : (i += 1) stepArrow(&shaft, hero, heroY, 0, false, &.{}, dt);
            i = 0;
            while (i < 600 and !stone.stuck) : (i += 1) stepArrow(&stone, hero, heroY, 0, false, &.{}, dt);
            try std.testing.expect(shaft.hit);
            try std.testing.expect(stone.hit);
        }
    }
}

test "the stone LOBS and the shaft does not — the arc is the slinger's tell" {
    // Same launcher, same aim, and the stone must still be the one that goes over a wall.
    const dt: f32 = 1.0 / 60.0;
    const aim = v3(0, 1.0, 14.0);
    var shaft = launchArrow(v3(0, 1.4, 0), aim);
    var stone = launchStone(v3(0, 1.4, 0), aim, 11.0);
    var peakShaft: f32 = 0;
    var peakStone: f32 = 0;
    var i: u32 = 0;
    while (i < 600 and !shaft.stuck) : (i += 1) {
        stepArrow(&shaft, v3(0, 0, 14.0), 1.0, 0, false, &.{}, dt);
        peakShaft = @max(peakShaft, shaft.pos.y - 1.4);
    }
    i = 0;
    while (i < 600 and !stone.stuck) : (i += 1) {
        stepArrow(&stone, v3(0, 0, 14.0), 1.0, 0, false, &.{}, dt);
        peakStone = @max(peakStone, stone.pos.y - 1.4);
    }
    try std.testing.expect(peakStone > peakShaft * 2.0);
}

test "a SIDESTEP beats an arrow: the homing is a launch nudge, not a lock" {
    const dt: f32 = 1.0 / 60.0;
    // Loosed at a hero 12 out; he then steps three body-widths off the flight line and holds.
    var shot = launchArrow(v3(0, 1.3, 0), v3(0, 1.0, 12.0));
    const dodged = v3(2.6, 0, 12.0);
    var i: u32 = 0;
    while (i < 300 and !shot.stuck) : (i += 1) stepArrow(&shot, dodged, 1.0, 0, false, &.{}, dt);
    try std.testing.expect(shot.stuck and !shot.hit);
    try std.testing.expect(shot.pos.x < 1.6); // it bent a little, then committed — never reached him

    // …but it still trims the LEAD ERROR: a hero who only drifts a step gets hit.
    var lead = launchArrow(v3(0, 1.3, 0), v3(0, 1.0, 12.0));
    i = 0;
    while (i < 300 and !lead.stuck) : (i += 1) stepArrow(&lead, v3(0.5, 0, 12.0), 1.0, 0, false, &.{}, dt);
    try std.testing.expect(lead.hit);
}
