const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const gfx = @import("gfx.zig");
const wf = @import("worldfmt.zig");

const v3 = mathx.v3;


pub const FLASH_DUR: f32 = 0.20; // seconds a struck foe pops on the shared gfx `hitFlash` uniform
pub const FLASH_GAIN: f32 = 0.85;
pub const HERO_R: f32 = 0.36;
pub const HERO_REACH: f32 = 0.55;
pub fn closestApproach(bodyR: f32) f32 {
    return bodyR + HERO_R;
}

pub const AIRBORNE_LIFT: f32 = 0.04;

/// STILL A BODY IN THE WAY. A CORPSE IS NOT ONE (owner's call, and the genre's rule): the frame a foe
/// dies you must be able to walk straight through it, and `alive()` stays true for the whole death
/// collapse plus its dissipation — seconds of a dead thing you were shouldering past. `pierceGroup`
/// already asked the question this way; this is the one place it is written.
pub fn corporeal(f: anytype) bool {
    return f.alive() and !f.dying();
}

// THE LEASH — and the provocation that overrides it.

/// Drawn THIS far from where it was posted and it starts thinking about going back…
pub const LEASH_R: f32 = 30.0;
/// …and it is home again only this close, which is the hysteresis: start far, stop near, so a foe hovering at the boundary cannot flap between chasing and returning every other frame.
pub const LEASH_HOME_R: f32 = 3.0;
/// …and only after this long with no blow given OR taken.
pub const LEASH_CALM: f32 = 4.5;

/// WHAT ONE BLOW IS WORTH as provocation…
pub const PROVOKE_PER_HIT: f32 = 1.0;
/// …how long one makes a foe ignore its own aggro range and come for you wherever you are.
pub const PROVOKE_ROUSE: f32 = 14.0;
/// …and how much BREAKS it outright.
pub const PROVOKE_BREAK: f32 = 2.5;
pub const PROVOKE_HOLD: f32 = 14.0;
pub const PROVOKE_DECAY: f32 = 0.35;

/// A foe's interest in you, and its tether to where it was posted.
pub const Leash = struct {
    sinceCombat: f32 = mathx.LONG_AGO,
    provoked: f32 = 0,
    rouseLeft: f32 = 0,
    breakLeft: f32 = 0,
    returning: bool = false,

    /// Per frame, BEFORE the state machine decides anything.
    pub fn tick(self: *Leash, dt: f32, out: f32) void {
        self.sinceCombat += dt;
        self.provoked = mathx.maxF(0, self.provoked - PROVOKE_DECAY * dt);
        self.rouseLeft = mathx.maxF(0, self.rouseLeft - dt);
        self.breakLeft = mathx.maxF(0, self.breakLeft - dt);
        if (self.breakLeft > 0) {
            self.returning = false; // committed to the fight; the tether does not exist for now
            return;
        }
        if (self.returning) {
            // …and it only stops when it is actually HOME, not the moment it is back inside LEASH_R.
            if (out <= LEASH_HOME_R) self.returning = false;
            return;
        }
        if (out > LEASH_R and self.sinceCombat >= LEASH_CALM) self.returning = true;
    }

    pub fn noteCombat(self: *Leash) void {
        self.sinceCombat = 0;
    }

    /// SOMETHING OF THE PLAYER'S LANDED ON IT.
    pub fn provoke(self: *Leash) void {
        self.noteCombat();
        self.rouseLeft = PROVOKE_ROUSE;
        self.provoked += PROVOKE_PER_HIT;
        if (self.provoked >= PROVOKE_BREAK) {
            self.breakLeft = PROVOKE_HOLD;
            self.returning = false;
        }
    }

    pub fn goingHome(self: *const Leash) bool {
        return self.returning;
    }

    pub fn roused(self: *const Leash) bool {
        return self.breakLeft > 0 or self.rouseLeft > 0;
    }
};

pub fn sensedDist(l: *const Leash, real: f32, aggroR: f32) f32 {
    if (l.goingHome()) return mathx.LONG_AGO;
    if (l.roused()) return mathx.minF(real, aggroR);
    return real;
}

pub fn faceToward(pos: rl.Vector3, facing: *f32, target: rl.Vector3, rate: f32, dt: f32) void {
    const d = mathx.dirXZ(pos, target);
    if (mathx.lenXZ(d) < 1e-3) return;
    facing.* = mathx.approachAngle(facing.*, mathx.headingXZ(d), rate * dt);
}

pub fn flashFrac(flash: f32) f32 {
    return mathx.clampF(flash / FLASH_DUR, 0, 1);
}

// Carry a landed blow's KNOCKBACK for one frame and bleed it off — a jolt off the blade, not a slide.
pub fn applyShove(pos: *rl.Vector3, shove: *rl.Vector3, decay: f32, bounds: f32, dt: f32) void {
    if (mathx.lenXZ(shove.*) <= 0.01) return;
    mathx.stepXZ(pos, shove.*, dt, bounds); // the shared bounded step — shove is a velocity, so dist = dt
    shove.* = mathx.scaleV(shove.*, mathx.maxF(0, 1.0 - decay * dt));
}


pub const DUST = mathx.rgba(150, 132, 96, 175);
pub const MOTE = mathx.rgba(252, 198, 92, 170);

pub fn fxStream(seed: f32, mul: f32, salt: u64) mathx.Rng {
    return mathx.Rng.init(@as(u64, @intFromFloat(@abs(seed) * mul)) +% salt);
}

pub const Particle = struct {
    p: rl.Vector3 = mathx.zero3,
    v: rl.Vector3 = mathx.zero3,
    life: f32 = 0, // seconds remaining (0 = dead slot)
    max: f32 = 1, // life at spawn (for the fade fraction)
    r0: f32 = 0.05, // radius at spawn
    r1: f32 = 0.05, // radius at death (r1>r0 = an expanding puff; r1<r0 = a shrinking spark)
    col: rl.Color = mathx.rgba(255, 255, 255, 255),
    grav: f32 = 0, // downward accel (world/s²); negative floats up
};

pub fn emitParticle(pool: []Particle, head: *usize, p: rl.Vector3, vel: rl.Vector3, life: f32, r0: f32, r1: f32, col: rl.Color, grav: f32) void {
    pool[head.*] = .{ .p = p, .v = vel, .life = life, .max = life, .r0 = r0, .r1 = r1, .col = col, .grav = grav };
    head.* = (head.* + 1) % pool.len;
}

pub fn tickParticles(pool: []Particle, dt: f32, floor: f32) void {
    for (pool) |*q| {
        if (q.life <= 0) continue;
        q.life -= dt;
        q.p.x += q.v.x * dt;
        q.p.y += q.v.y * dt;
        q.p.z += q.v.z * dt;
        q.v.y -= q.grav * dt;
        if (q.p.y < floor) q.p.y = floor;
    }
}

pub fn drawParticles(pool: []const Particle) void {
    for (pool) |*q| {
        if (q.life <= 0) continue;
        const frac = mathx.clampF(q.life / q.max, 0, 1);
        const rad = mathx.lerpF(q.r1, q.r0, frac); // r0 at spawn (frac 1) → r1 at death (frac 0)
        const a = mathx.u8f(@as(f32, @floatFromInt(q.col.a)) * frac);
        rl.drawSphereEx(q.p, rad, 6, 8, mathx.withAlpha(q.col, a));
    }
}


pub fn resetGroup(comptime T: type, out: []T, n: *usize, m: *const wf.Map, want: wf.FoeKind) void {
    n.* = 0;
    for (m.foes[0..m.nfoes]) |h| {
        if (h.kind != want or n.* >= out.len) continue;
        // ON THE GROUND, which the map's own height field decides — a spawn table stores x/z only, so posting a foe on a sculpted rise and dropping it at y = 0 would bury it to the waist.
        out[n.*] = T.spawn(v3(h.x, m.heightAt(h.x, h.z), h.z), mathx.radians(h.yaw), h.scale, h.seed);
        n.* += 1;
    }
}

pub fn drawGroup(foes: anytype, model: anytype, scene: ?*gfx.Scene) void {
    for (foes) |*f| {
        if (!f.alive()) continue;
        if (scene) |sc| sc.setFlash(FLASH_GAIN * f.flashFrac());
        f.draw(model);
    }
    if (scene) |sc| sc.setFlash(0);
}

pub fn anyDied(foes: anytype) bool {
    for (foes) |*f| {
        if (f.justDied) return true;
    }
    return false;
}

pub fn totalHits(foes: anytype) u32 {
    var n: u32 = 0;
    for (foes) |*f| n += f.hits;
    return n;
}

pub fn runesDropped(foes: anytype, per: u32) u32 {
    var n: u32 = 0;
    for (foes) |*f| {
        if (f.justDied) n += per;
    }
    return n;
}

pub fn aliveCount(foes: anytype) u32 {
    var n: u32 = 0;
    for (foes) |*f| {
        if (f.alive()) n += 1;
    }
    return n;
}

pub const Blade = struct {
    active: bool = false,
    r: f32 = 0,
    a: rl.Vector3 = mathx.zero3,
    b: rl.Vector3 = mathx.zero3,
    a0: rl.Vector3 = mathx.zero3,
    b0: rl.Vector3 = mathx.zero3,
    hit: combat.Hit = .{}, // HP/poise/stance the swing deals (light vs heavy, set by game.zig)
    /// A PROJECTILE, NOT A SWING: one of the player's own, presented as the segment it crossed this frame so it goes through the same `strike` and gets each creature's own reactions.
    pierce: bool = false,
};

pub const Blow = struct {
    hit: combat.Hit,
    from: rl.Vector3, // the attacker's own `pos`, in world space
};

pub fn worseBlow(worst: *?Blow, h: combat.Hit, from: rl.Vector3) void {
    if (worst.* == null or h.dmg > worst.*.?.hit.dmg) worst.* = .{ .hit = h, .from = from };
}

pub fn groupBlow(foes: anytype, dt: f32, hero: rl.Vector3, bounds: f32, blade: Blade) ?Blow {
    var worst: ?Blow = null;
    for (foes) |*f| {
        if (f.update(dt, hero, bounds, blade)) |h| worseBlow(&worst, h, f.pos);
    }
    return worst;
}

pub fn pierceGroup(foes: anytype, blade: Blade) bool {
    for (foes) |*f| {
        if (!f.alive() or f.dying()) continue;
        const before = f.hits;
        f.tryHit(blade);
        if (f.hits != before) return true;
    }
    return false;
}

pub const Strike = struct {
    contact: rl.Vector3,
    dir: rl.Vector3,
    reaction: combat.HitResult,
};

pub fn strike(vit: *combat.Vitals, hitLatch: *bool, center: rl.Vector3, hurtR: f32, blade: Blade) ?Strike {
    if (blade.pierce) {
        if (!blade.active) return null;
    } else {
        if (!blade.active) {
            hitLatch.* = false; // window closed → the next swing may land again
            return null;
        }
        if (hitLatch.*) return null;
    }
    const reach = hurtR + blade.r;
    // Swept: test THIS frame's blade segment AND last frame's, so a fast arc can't skip the foe.
    const q1 = mathx.closestOnSegV(center, blade.a, blade.b);
    const hit1 = mathx.lenV(mathx.subV(center, q1)) <= reach;
    const q0 = mathx.closestOnSegV(center, blade.a0, blade.b0);
    if (!(hit1 or mathx.lenV(mathx.subV(center, q0)) <= reach)) return null;
    if (!blade.pierce) hitLatch.* = true;
    // The blow reads at the wound: blood/knockback fly along the blade's sweep at the contact.
    const contact = if (hit1) q1 else q0;
    // A SHAFT'S OWN LENGTH *IS* ITS TRAVEL (`a`→`b` is this frame's segment), where a swing's sweep is the difference between two FRAMES of blade — which for a shaft subtracts to zero and used to fall through to "contact toward centre", i.e. square across the shaft.
    var sweep = if (blade.pierce)
        mathx.subV(blade.b, blade.a)
    else
        mathx.subV(mathx.lerpV(blade.a, blade.b, 0.7), mathx.lerpV(blade.a0, blade.b0, 0.7));
    sweep.y = 0;
    const dir = if (mathx.lenXZ(sweep) > 0.03) mathx.normV(sweep) else mathx.dirXZ(contact, center);
    return .{ .contact = contact, .dir = dir, .reaction = vit.hit(blade.hit) };
}

test "a CORPSE is not a body in the way, from the frame it starts to fall" {
    const Dummy = struct {
        gone: bool = false,
        down: bool = false,
        fn alive(self: *const @This()) bool {
            return !self.gone;
        }
        fn dying(self: *const @This()) bool {
            return self.down;
        }
    };
    var d = Dummy{};
    try std.testing.expect(corporeal(&d));
    d.down = true; // the collapse has begun, and `alive()` stays true for seconds yet
    try std.testing.expect(!corporeal(&d));
    d.gone = true;
    try std.testing.expect(!corporeal(&d));
}

test "THE LEASH: a foe drawn far from home walks back once the fight has gone quiet" {
    var l = Leash{};
    const far = LEASH_R + 8.0;
    l.noteCombat();
    l.tick(1.0 / 60.0, far);
    try std.testing.expect(!l.goingHome());
    var t: f32 = 0;
    while (t < LEASH_CALM + 0.1) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, far);
    try std.testing.expect(l.goingHome());
    // THE HYSTERESIS: back inside LEASH_R is NOT "home" — it keeps walking until it is actually there, so a foe hovering at the boundary cannot flap between chasing and returning every other frame.
    l.tick(1.0 / 60.0, LEASH_R - 1.0);
    try std.testing.expect(l.goingHome());
    l.tick(1.0 / 60.0, LEASH_HOME_R - 0.5);
    try std.testing.expect(!l.goingHome());
    var near = Leash{};
    t = 0;
    while (t < 30.0) : (t += 1.0 / 60.0) near.tick(1.0 / 60.0, 2.0);
    try std.testing.expect(!near.goingHome());
}

test "ONE PLAYER HIT ROUSES IT FROM ANY RANGE, and KEEPING AT IT breaks the leash" {
    var l = Leash{};
    try std.testing.expect(!l.roused());
    l.provoke();
    try std.testing.expect(l.roused());
    // …AND IT STAYS ROUSED LONG ENOUGH TO WALK THE GROUND.
    var t: f32 = 0;
    while (t < PROVOKE_ROUSE - 0.5) : (t += 1.0 / 60.0) {
        l.tick(1.0 / 60.0, 0);
        try std.testing.expect(l.roused());
    }
    while (t < PROVOKE_ROUSE + 0.5) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, 0);
    try std.testing.expect(!l.roused());

    var c = Leash{};
    const far = LEASH_R + 8.0;
    t = 0;
    while (t < LEASH_CALM + 0.1) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far);
    try std.testing.expect(c.goingHome());
    c.provoke();
    c.tick(1.0 / 60.0, far);
    try std.testing.expect(c.goingHome());
    c.provoke();
    c.provoke();
    c.tick(1.0 / 60.0, far);
    try std.testing.expect(!c.goingHome());
    try std.testing.expect(c.roused());
    t = 0;
    while (t < LEASH_CALM + 2.0) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far);
    try std.testing.expect(!c.goingHome());
    t = 0;
    while (t < PROVOKE_HOLD + LEASH_CALM + 1.0) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far);
    try std.testing.expect(c.goingHome());
    try std.testing.expect(!c.roused());
}

test "the leash constants say what the rule is" {
    // Start FAR, stop NEAR — the gap between them IS the debounce, and a zero gap is the flapping.
    try std.testing.expect(LEASH_HOME_R < LEASH_R * 0.5);
    // It takes more than one hit to break a tether in progress.
    try std.testing.expect(PROVOKE_BREAK > PROVOKE_PER_HIT);
    try std.testing.expect(PROVOKE_ROUSE > LEASH_CALM * 2.0);
    try std.testing.expect(PROVOKE_HOLD > LEASH_CALM * 2.0);
}

test "A SHAFT'S blood and shove run ALONG its flight, and it never touches the swing latch" {
    // THE bug: a pierce passes one segment as BOTH `a`/`b` and `a0`/`b0`, so the swing's two-frame sweep subtracted to zero and `dir` came out square across the shaft — which is where blood and shove go.
    var vit = combat.Vitals.init(100, 999, 999); // huge poise/stance: no reaction to muddy this
    var latch = false;
    const shaft = mathx.v3(-1, 1, 0.3);
    const tip = mathx.v3(1, 1, 0.3);
    const s = strike(&vit, &latch, mathx.v3(0, 1, 0), 0.5, .{
        .active = true,
        .pierce = true,
        .r = 0.16,
        .a = shaft,
        .b = tip,
        .a0 = shaft,
        .b0 = tip,
        .hit = .{ .dmg = 5 },
    }).?;
    try std.testing.expect(s.dir.x > 0.95); // down the TRAVEL (+X)…
    try std.testing.expect(@abs(s.dir.z) < 0.2);
    try std.testing.expect(!latch);
    const again = strike(&vit, &latch, mathx.v3(0, 1, 0), 0.5, .{
        .active = true,
        .pierce = true,
        .r = 0.16,
        .a = shaft,
        .b = tip,
        .a0 = shaft,
        .b0 = tip,
        .hit = .{ .dmg = 5 },
    });
    try std.testing.expect(again != null);
}

test "strike: latches one hit per swing, re-arms when the window closes, applies the reaction" {
    var vit = combat.Vitals.init(100, 8, 100); // low poise → a hit flinches
    var latch = false;
    const c = mathx.v3(0, 1, 0);
    const active = Blade{ .active = true, .r = 0.4, .a = mathx.v3(0, 1, -1), .b = mathx.v3(0, 1, 1), .a0 = mathx.v3(0, 1, -1), .b0 = mathx.v3(0, 1, 1), .hit = .{ .dmg = 10, .poise = 20 } };
    const s = strike(&vit, &latch, c, 0.5, active);
    try std.testing.expect(s != null);
    try std.testing.expectEqual(combat.HitResult.light, s.?.reaction);
    try std.testing.expect(latch);
    try std.testing.expect(strike(&vit, &latch, c, 0.5, active) == null);
    _ = strike(&vit, &latch, c, 0.5, .{ .active = false });
    try std.testing.expect(!latch);
    try std.testing.expect(strike(&vit, &latch, mathx.v3(9, 1, 0), 0.5, active) == null);
}
