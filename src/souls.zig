const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const foe = @import("foe.zig");
const sfx = @import("audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// WHAT YOU DROPPED WHEN YOU DIED — DS's bloodstain and ER's rune drop, which are the same mechanic under two
// names: everything you were carrying stands on the spot it left you, you walk back for it, and dying again
// on the way is what makes the walk mean something.
//
// **THERE IS EXACTLY ONE.** A second death overwrites the first, and the first is gone for good. That is not
// a storage decision — it is THE mechanic, and a list of drops would quietly delete the whole risk.
//
// **NOTHING ELSE CAN TAKE IT.** No timer, no decay, no despawn on distance: the only thing that spends a drop
// is picking it up or dying again. A bloodstain on a clock is a bloodstain you lose to the loading screen.

/// How close you have to stand for the prompt, in metres on XZ. Generous next to a chest's 2.1: you are
/// coming back for this under pressure, and fumbling the reach is not the tension the mechanic is for.
pub const REACH: f32 = 2.6;

/// The gold stands about chest height on the 1.8 m rig — tall enough to find across a clearing, short enough
/// that it never hides the thing that killed you standing behind it.
pub const H: f32 = 1.25;
/// …and the prompt hangs off the top of that.
const TOP_LIFT: f32 = 0.30;

/// Seconds the bloom takes to grow out of the ground where you fell — it does not pop into being.
const RISE: f32 = 0.55;
/// …and how far it OVERSHOOTS that height before settling onto it (the reactions law, on a prop).
const RISE_PUNCH: f32 = 0.16;
/// The slow turn and the breath, on two rates that never line up.
const SPIN: f32 = 0.35; // radians a second
const BOB: f32 = 0.035; // metres either way
const BOB_RATE: f32 = 1.3;

/// Motes coming off it a second, and how long one lives. Sized against the ring below by arithmetic.
const MOTE_RATE: f32 = 26.0;
const MOTE_LIFE_LO: f32 = 0.9;
const MOTE_LIFE_HI: f32 = 1.7;
/// A ring that overwrites its oldest does it silently, so its size is arithmetic over what feeds it.
const PARTS = blk: {
    const worst = MOTE_RATE * MOTE_LIFE_HI + TAKE_MOTES;
    break :blk @as(usize, @intFromFloat(@ceil(worst))) + 4;
};
comptime {
    // The ring overwrites its oldest SILENTLY, so the size is arithmetic over the emitters' worst frame:
    // a full standing cloud, and the whole take burst thrown on top of it on one frame.
    std.debug.assert(@as(f32, PARTS) >= MOTE_RATE * MOTE_LIFE_HI + TAKE_MOTES);
}
/// The burst it goes out on when you pick it up, and how long those motes take to reach him. THE PICKUP IS
/// INSTANT (owner's call): the runes are on the counter the frame he presses, and this is the effect
/// catching up with a thing that has already happened — no committed action, no animation on the man.
const TAKE_MOTES: f32 = 34.0;
const TAKE_PULL: f32 = 0.34; // seconds a mote takes to cross to him
/// …and how far up his body they land: the chest, so they arrive at the man and not at his boots.
const TAKE_INTO: f32 = 1.05;

/// THE HUM IS A RETRIGGER, NOT A LOOP (`leechfly.WHINE_EVERY`'s rule — raylib cannot loop a synthesized
/// take). Cut a hair SHORTER than the voice itself so consecutive takes overlap: gapped, a standing hum
/// pulses, and a pulse reads as something arming rather than something waiting.
const HUM_EVERY: f32 = 1.15;

/// THE GOLD ITSELF, and it must read as GOLD and not as BONE — which is the one thing a pale glowing tree in
/// a graveyard cannot afford to look like. Vertex alpha is the emissive channel (255 = lit by the sun, lower
/// = self-lit), so ONE alpha across all three tones: at a single emissive level the tones separate on hue and
/// value alone, and the shaft cannot band where a level changes.
///
/// MEASURED, NOT GUESSED (AGENTS.md). At alpha 58 the chain comes back as screen = 255·(albedo/255 · 1.236)^(1/2.2)
/// — sampled off the first pass, where albedo 150 rendered 221 and anything over ~205 clipped to 255. The
/// tips were authored at 246,220,150 and came back 255,255,221: a white knuckle, which is why it read as bone.
/// Solved back from the screen values actually wanted, the three come out deeply saturated and none of them clips.
const EMISSIVE: u8 = 58;
const GOLD = rgba(140, 70, 8, EMISSIVE); // → ~214,158,60 on screen
const GOLD_LT = rgba(168, 90, 13, EMISSIVE); // → ~232,176,74
/// …and the hot heart at the fork and the limb ends, which is the only part allowed to run pale.
const GOLD_HOT = rgba(201, 140, 39, EMISSIVE); // → ~252,214,120
const MOTE = rgba(250, 200, 96, 190);

/// The trunk's own dimensions, in metres.
const BOLE_R0: f32 = 0.085;
const BOLE_R1: f32 = 0.045;
/// Limbs the bloom forks into. NOTHING ENDS IN A POINT: each rises to an elbow, droops off the line, and
/// stops in a blunt swelling — a rosette of needles is a hub of spokes, whatever it is made of.
const LIMBS = 7;

pub const Drop = struct {
    at: rl.Vector3 = mathx.zero3,
    amount: u32 = 0,
    /// Seconds since it landed — the rise, the spin and the bob all read it.
    t: f32 = 0,
    live: bool = false,

    /// Where the prompt hangs.
    pub fn topWorld(self: *const Drop) rl.Vector3 {
        return v3(self.at.x, self.at.y + H + TOP_LIFT, self.at.z);
    }

    /// 0..1 of the way out of the ground, overshooting once before it settles.
    fn grown(self: *const Drop) f32 {
        const k = mathx.smoothstep(0, RISE, self.t);
        return k + RISE_PUNCH * mathx.pulse(self.t, RISE * 0.45, RISE * 0.8, RISE * 0.8, RISE * 2.0);
    }
};

pub const Souls = struct {
    mesh: rl.Mesh = undefined,
    mat: rl.Material = undefined,
    drop: Drop = .{},
    /// Is he standing in reach of it — the prompt's own question, asked once a frame like the bonfires'.
    near: bool = false,

    parts: [PARTS]foe.Particle = [_]foe.Particle{.{}} ** PARTS,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    humLeft: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0x50015),

    pub fn init(shader: rl.Shader) Souls {
        var mat = rl.loadMaterialDefault() catch @panic("souls material");
        mat.shader = shader;
        return .{ .mesh = boughMesh(), .mat = mat };
    }

    pub fn setShader(self: *Souls, sh: rl.Shader) void {
        self.mat.shader = sh;
    }

    /// HE DIED HERE, CARRYING THIS. Overwrites whatever was standing already — that drop is gone, which is
    /// the whole of the rule. `amount` 0 leaves the ground bare: a stain worth nothing is a walk for nothing.
    pub fn spill(self: *Souls, at: rl.Vector3, amount: u32) void {
        if (amount == 0) {
            self.drop = .{};
            self.near = false;
            return;
        }
        self.drop = .{ .at = at, .amount = amount, .t = 0, .live = true };
        self.near = false;
        self.humLeft = HUM_EVERY * 0.5; // …and it does not sound the instant it lands: the spill owns that beat
        self.fxRng = foe.fxStream(at.x + at.z * 1.7 + @as(f32, @floatFromInt(amount)), 613.0, 0x5011);
    }

    /// …and the same question the bonfires and the boxes ask, in the same shape.
    pub fn look(self: *Souls, heroPos: rl.Vector3) void {
        self.near = self.drop.live and mathx.distXZ(self.drop.at, heroPos) <= REACH;
    }

    /// PICKED UP — the amount, or null if there was nothing there. It goes out in a burst rather than
    /// blinking off: what you get back has to be seen arriving.
    pub fn take(self: *Souls, heroPos: rl.Vector3) ?u32 {
        if (!self.drop.live) return null;
        const got = self.drop.amount;
        self.burst(heroPos);
        sfx.world(.souls_take, self.drop.at);
        self.drop = .{};
        self.near = false;
        return got;
    }

    /// What is standing on the ground, for anything that wants to read it without taking it.
    pub fn standing(self: *const Souls) ?u32 {
        return if (self.drop.live) self.drop.amount else null;
    }

    /// A FRESH WORLD KEEPS IT. `game.resetFoes` re-homes the field on a death and the drop is the one thing
    /// on it that must survive that, so this is called only where the MAP itself changes.
    pub fn clear(self: *Souls) void {
        self.drop = .{};
        self.near = false;
        for (&self.parts) |*p| p.* = .{};
    }

    pub fn update(self: *Souls, dt: f32) void {
        foe.tickParticles(&self.parts, dt, self.drop.at.y);
        if (!self.drop.live) return;
        self.drop.t += dt;
        // …and it says so out loud on its own cadence, which is what lets you find one you walked past.
        self.humLeft -= dt;
        if (self.humLeft <= 0) {
            self.humLeft = HUM_EVERY;
            sfx.world(.souls_hum, self.drop.topWorld());
        }
        // The motes climb out of it the whole time it stands — the only thing that says it is still there
        // when the bloom itself is behind a rise.
        self.fxAccum += MOTE_RATE * self.drop.grown() * dt;
        while (self.fxAccum >= 1.0) {
            self.fxAccum -= 1.0;
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.05, 0.42);
            const from = v3(
                self.drop.at.x + mathx.cosf(a) * rr,
                self.drop.at.y + self.fxRng.range(0.05, 1.0) * H,
                self.drop.at.z + mathx.sinf(a) * rr,
            );
            foe.emitParticle(
                &self.parts,
                &self.fxHead,
                from,
                v3(self.fxRng.signed() * 0.18, self.fxRng.range(0.35, 0.9), self.fxRng.signed() * 0.18),
                self.fxRng.range(MOTE_LIFE_LO, MOTE_LIFE_HI),
                self.fxRng.range(0.022, 0.045),
                0.004,
                MOTE,
                -0.55, // negative grav: they FLOAT, the grace motes' own rule
            );
        }
    }

    /// IT GOES INTO HIM, it does not go out. Each mote is SOLVED to arrive at his chest inside its own life
    /// (the wand gather's construction, with the ends swapped), so the shower reads as a thing being taken
    /// up rather than a thing being scattered — which is the whole difference between a pickup and a death.
    fn burst(self: *Souls, heroPos: rl.Vector3) void {
        const into = v3(heroPos.x, heroPos.y + TAKE_INTO, heroPos.z);
        var i: f32 = 0;
        while (i < TAKE_MOTES) : (i += 1) {
            const a = self.fxRng.angle();
            const rr = self.fxRng.range(0.05, 0.5);
            const from = v3(
                self.drop.at.x + mathx.cosf(a) * rr,
                self.drop.at.y + self.fxRng.range(0.05, 1.05) * H,
                self.drop.at.z + mathx.sinf(a) * rr,
            );
            // A SPREAD of lives, not one: they arrive over a few frames, which is what makes it a rush and
            // not a single flash. The velocity is (where it has to be − where it is) over its own life.
            const life = self.fxRng.range(TAKE_PULL * 0.6, TAKE_PULL);
            const v = mathx.scaleV(mathx.subV(into, from), 1.0 / life);
            foe.emitParticle(
                &self.parts,
                &self.fxHead,
                from,
                v3(v.x, v.y + self.fxRng.range(-0.4, 0.8), v.z), // a little arc on the way up, no gravity
                life,
                self.fxRng.range(0.030, 0.060),
                0.010,
                MOTE,
                0,
            );
        }
    }

    /// LIT PASS ONLY, with the arrows — it is made of light and has no business laying a shadow on the grass
    /// it is standing in. `drawParticles` is its own call, so the motes go over the opaque pass like every
    /// creature's FX do.
    pub fn draw(self: *const Souls) void {
        if (!self.drop.live) return;
        const up = self.drop.grown();
        if (up <= 0.001) return;
        const bob = BOB * mathx.sinf(self.drop.t * BOB_RATE);
        const yaw = mathx.degrees(self.drop.t * SPIN);
        rl.drawMesh(self.mesh, self.mat, mathx.mul3(
            mathx.scaleM(1.0, up, 1.0),
            mathx.ry(yaw),
            mathx.tr(self.drop.at.x, self.drop.at.y + bob, self.drop.at.z),
        ));
    }

    pub fn drawFx(self: *const Souls) void {
        foe.drawParticles(&self.parts);
    }
};

/// THE BLOOM: a short crooked bole out of the earth, forking into limbs that rise to an elbow, droop off
/// their own line and stop in a blunt swelling. It is a TREE and not a flame, so it obeys the dead-limb law
/// — nothing straight, nothing ending in a point — and the variation is seeded so a build stays deterministic.
fn boughMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x501D7EE);
    b.setMat(.plain);

    // The bole, in three leaning segments — one capsule to the fork is a stake.
    var at = v3(0, 0, 0);
    var r = BOLE_R0;
    var seg: u32 = 0;
    while (seg < 3) : (seg += 1) {
        const rise = H * 0.16 * rng.range(0.85, 1.2);
        const a = rng.angle();
        const lean = rng.range(0.01, 0.035);
        const next = v3(at.x + mathx.cosf(a) * lean, at.y + rise, at.z + mathx.sinf(a) * lean);
        const rn = mathx.lerpF(r, BOLE_R1, 0.4);
        b.addCapsule(at, next, r, rn, 7, if (seg % 2 == 0) GOLD else GOLD_LT);
        at = next;
        r = rn;
    }
    // The fork itself — the one part that reads white, and it is small.
    b.addBlob(at, v3(r * 1.9, r * 1.5, r * 1.9), 5, 9, GOLD_HOT);

    // The limbs. Each one: out and up to an elbow, then OFF the line and DOWN to a blunt snap, with a
    // swelling on the end. No two the same length, height or lean — nine of one size is a garden rake.
    const forkY = at.y;
    var i: u32 = 0;
    while (i < LIMBS) : (i += 1) {
        const yaw = std.math.tau * (@as(f32, @floatFromInt(i)) / LIMBS) + rng.range(-0.30, 0.30);
        const out = rng.range(0.16, 0.30);
        const up = rng.range(0.16, 0.34) * H;
        const c = mathx.cosf(yaw);
        const s = mathx.sinf(yaw);
        const elbow = v3(at.x + c * out, forkY + up, at.z + s * out);
        const lr = rng.range(0.45, 0.75) * r;
        b.addCapsule(at, elbow, r * 0.8, lr, 6, if (i % 2 == 0) GOLD_LT else GOLD);
        // …and off the line: it droops, and it stops BLUNT.
        const drop = rng.range(0.05, 0.16) * H;
        const reach = rng.range(0.09, 0.20);
        const tip = v3(
            elbow.x + c * reach + rng.signed() * 0.05,
            elbow.y + rng.range(-drop, drop * 0.35),
            elbow.z + s * reach + rng.signed() * 0.05,
        );
        b.addCapsule(elbow, tip, lr, lr * 0.75, 6, GOLD_LT);
        b.addBlob(tip, v3(lr * 1.15, lr * 1.05, lr * 1.15), 4, 8, GOLD_HOT); // the blunt swelling — a STOP, not a knuckle
    }
    return b.toMesh();
}


test "THERE IS EXACTLY ONE DROP, and a second death spends the first" {
    var s = Souls{};
    try std.testing.expect(s.standing() == null);
    s.spill(v3(4, 0, 4), 900);
    try std.testing.expectEqual(@as(u32, 900), s.standing().?);
    // Dying again elsewhere OVERWRITES it — the first 900 are gone, and that is the mechanic.
    s.spill(v3(-20, 0, 7), 120);
    try std.testing.expectEqual(@as(u32, 120), s.standing().?);
    try std.testing.expectApproxEqAbs(@as(f32, -20), s.drop.at.x, 1e-5);
    // …and picking it up hands back exactly what was standing, once.
    try std.testing.expectEqual(@as(u32, 120), s.take(mathx.zero3).?);
    try std.testing.expect(s.take(mathx.zero3) == null);
    try std.testing.expect(s.standing() == null);
}

test "a death carrying NOTHING leaves no stain to walk back to" {
    var s = Souls{};
    s.spill(v3(1, 0, 1), 500);
    s.spill(v3(2, 0, 2), 0);
    try std.testing.expect(s.standing() == null);
    try std.testing.expect(!s.drop.live);
}

test "the prompt is a RING round the drop, and it is only offered where there is one" {
    var s = Souls{};
    s.look(mathx.zero3);
    try std.testing.expect(!s.near);
    s.spill(mathx.zero3, 300);
    s.look(v3(REACH * 0.5, 0, 0));
    try std.testing.expect(s.near);
    s.look(v3(REACH + 1.0, 0, 0));
    try std.testing.expect(!s.near);
    // Exactly ON the ring is IN, which is what `<=` says — a chest's `Nearest` is the strict one.
    s.look(v3(REACH, 0, 0));
    try std.testing.expect(s.near);
    // …and taking it takes the prompt with it.
    s.look(mathx.zero3);
    _ = s.take(mathx.zero3);
    s.look(mathx.zero3);
    try std.testing.expect(!s.near);
}

test "NOTHING BUT A DEATH OR A PICKUP SPENDS IT — no clock, no decay, no despawn" {
    var s = Souls{};
    s.spill(mathx.zero3, 4200);
    var t: f32 = 0;
    while (t < 600.0) : (t += 1.0 / 30.0) s.update(1.0 / 30.0);
    try std.testing.expectEqual(@as(u32, 4200), s.standing().?);
    // …and ten minutes on it is still fully grown and still asking to be picked up.
    try std.testing.expect(s.drop.grown() > 0.99);
    s.look(mathx.zero3);
    try std.testing.expect(s.near);
}

test "it GROWS out of the ground, overshoots, and settles onto its own height" {
    var s = Souls{};
    s.spill(mathx.zero3, 10);
    try std.testing.expect(s.drop.grown() < 0.05);
    var over: f32 = 0;
    var t: f32 = 0;
    while (t < RISE * 3.0) : (t += 1.0 / 120.0) {
        s.update(1.0 / 120.0);
        over = @max(over, s.drop.grown());
    }
    try std.testing.expect(over > 1.0); // A MASS IN MOTION OVERSHOOTS ITS REST…
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), s.drop.grown(), 0.01); // …and settles back onto it
}

test "the prompt anchor is over the bloom, not at its foot" {
    var s = Souls{};
    s.spill(v3(3, 1.5, -2), 60);
    const top = s.drop.topWorld();
    try std.testing.expectApproxEqAbs(@as(f32, 3), top.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, -2), top.z, 1e-5);
    try std.testing.expect(top.y > 1.5 + H); // measured from ITS OWN ground, like every world point here
}
