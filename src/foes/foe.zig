const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const gfx = @import("../gfx/gfx.zig");
const wf = @import("../world/worldfmt.zig");
const props = @import("../props/props.zig");

const v3 = mathx.v3;


pub const FLASH_DUR: f32 = 0.20;
pub const FLASH_GAIN: f32 = 0.85;
pub const FROST_GAIN: f32 = 0.55;
pub const HERO_R: f32 = 0.36;
pub const HERO_REACH: f32 = 0.55;
/// **TOO CLOSE TO HAVE A FRONT.** Inside this every close blow lands whatever the bearing says. Six creatures
/// wrote this out by hand and one had drifted to 0.30.
pub const POINT_BLANK: f32 = 0.35;
pub const HERO_LOW: f32 = -0.10;
pub const HERO_HIGH: f32 = 1.71; // 0.95 of his 1.8 m stature
pub const HERO_EYE: f32 = 1.25;
/// What a thrown thing aims at and is tested against: 0.55 of his 1.8 m stature.
pub const HERO_CHEST: f32 = 0.99;
pub fn heroChest(at: rl.Vector3) rl.Vector3 {
    return v3(at.x, at.y + HERO_CHEST, at.z);
}

/// **WHAT COUNTS AS EARTH UNDER A THING IN FLIGHT**, since nothing in `foes/` can reach `env.groundAt` and the
/// world is a sculpted heightfield. A body's `pos.y` IS the ground under it (AGENTS.md), so a projectile
/// carries the floor it was thrown from and is spent on the LOWER of that and the quarry's own. Asked against
/// the QUARRY's alone, a caster standing below him lost every shot on the frame it left: the deer's throat
/// rides 2.33 m over its own feet and the magus's staff head 1.60 m, both under a man three metres up.
pub const LANDED_AT: f32 = 0.05;
pub fn landed(atY: f32, floor: f32, quarryY: f32) bool {
    return atY <= mathx.minF(floor, quarryY) + LANDED_AT;
}
pub fn closestApproach(bodyR: f32) f32 {
    return bodyR + HERO_R;
}

/// **THE WHOLE REACH OF A CLOSE BLOW** — the creature's metres scaled with the body, plus the hero's standing
/// footprint, which is HIS and does not grow with the thing swinging. Twenty-two sites wrote this out and FOUR
/// had drifted to `(own + HERO_REACH) * scale`: +0.55 m of reach on a scale-2 body, -0.28 m on a scale-0.5 one,
/// invisible at 1.0 where every test spawns. `closestApproach` is the same triangle for COLLISION (`HERO_R`).
pub fn hurtReach(own: f32, scale: f32) f32 {
    return own * scale + HERO_REACH;
}

pub const AIRBORNE_LIFT: f32 = 0.04;

pub const Nature = enum {
    beast,
    demon,
    undead,
    humanoid,
    plant,
    /// Nothing in this world is one yet; the row is named so nobody files one under `beast`.
    construct,

    pub fn label(n: Nature) [:0]const u8 {
        return switch (n) {
            .beast => "Beast",
            .demon => "Demon",
            .undead => "Undead",
            .humanoid => "Humanoid",
            .plant => "Plant",
            .construct => "Construct",
        };
    }
};

/// NOT `airborne()`, which is off-the-ground THIS FRAME: this is what the creature IS, on every frame.
pub const Gait = enum {
    /// On foot, and the water gate holds it (`game.gateTerrain`).
    walking,
    /// At home in it — the water gate does not apply at any depth.
    waterfaring,
    flying,
    /// Does not travel at all, so no gate has anything to say to it.
    rooted,

    pub fn label(g: Gait) [:0]const u8 {
        return switch (g) {
            .walking => "Walking",
            .waterfaring => "Waterfaring",
            .flying => "Flying",
            .rooted => "Rooted",
        };
    }
};

pub const Traits = struct { nature: Nature, gait: Gait = .walking };

pub fn traitsOf(k: wf.FoeKind) Traits {
    return switch (k) {
        .toad => .{ .nature = .beast, .gait = .waterfaring },
        .fen_lurker => .{ .nature = .demon, .gait = .waterfaring },
        .leechfly => .{ .nature = .beast, .gait = .flying },
        .shade, .mourner => .{ .nature = .undead, .gait = .flying },
        .blinkbat => .{ .nature = .demon, .gait = .flying },
        .rooted => .{ .nature = .plant, .gait = .rooted },
        .slumber_bloom => .{ .nature = .plant, .gait = .rooted },
        .brood_sac => .{ .nature = .beast, .gait = .rooted },
        .archer, .shieldman, .greatsword, .bone_knight, .necromancer, .bone_skitterer, .ancient_priest, .tolling_hollow, .cinder_wake, .salt_husk => .{ .nature = .undead },
        .berserker, .priest, .slinger, .ogre, .fish_spearman, .fish_netter, .fish_shaman => .{ .nature = .humanoid },
        .brood_mother, .broodling, .delver, .fungal_deer, .rotgorger => .{ .nature = .beast },
        .shroom, .mushroom_mage, .spore_golem, .birchwight => .{ .nature = .plant },
        .fungal_swordsman, .fungal_magus => .{ .nature = .plant },
    };
}

/// **WHICH KINGDOM A CREATURE READS AS STANDING IN** — the third axis beside `Nature` and `Gait`, and an
/// exhaustive switch for their reason: a creature cannot be added unfiled. It is `props.Biome`, the same axis
/// the props are filed on, so the editor's units palette and its prop palette split the world the same way.
///
/// **NOTHING SPAWNS BY IT** (`props.biome`'s own rule). What places a creature is an authored `foe:` line, and
/// nothing consults this but the editor's palette. `any` is not a dustbin — it is the set that reads right
/// ANYWHERE, and `atHome` is what puts those in every list rather than a list of their own.
pub fn homeOf(k: wf.FoeKind) props.Biome {
    return switch (k) {
        // Nothing about a bloodfly or a bat says where it is: both are authored across every test map there is.
        .leechfly, .blinkbat => .any,
        // `shade.zig` builds both, so both are filed together.
        .shade, .mourner => .ruins,
        // The warband camps (`kobold.zig`, one group because of the priest), which is the one settled thing here.
        .berserker, .priest, .slinger => .village,
        // The rooted wears a `snag`'s own palette and limb builder, the birchwight is a birch, and the bloom and
        // the brood are the things a wood hides.
        .rooted, .birchwight, .slumber_bloom => .forest,
        .brood_mother, .broodling, .brood_sac => .forest,
        // The cyclops for its scale and the delver because it comes up THROUGH the ground.
        .ogre, .delver => .rock,
        .toad, .fen_lurker, .fish_spearman, .fish_netter, .fish_shaman => .wetland,
        // A wake that leaves burnt ground, and a body the dried lake took the water out of.
        .cinder_wake, .salt_husk => .ash,
        .archer, .shieldman, .greatsword, .bone_knight, .bone_skitterer => .bone,
        .ancient_priest, .necromancer, .tolling_hollow, .rotgorger => .bone,
        .shroom, .mushroom_mage, .spore_golem, .fungal_deer => .fungal,
        .fungal_swordsman, .fungal_magus => .fungal,
    };
}

/// **WHICH CREATURES ARE A FIGHT OF THEIR OWN** — an exhaustive switch for `homeOf`'s reason: a creature
/// cannot be added unfiled, and the next boss arrives with a bar and no gate that will offer it. `game`'s
/// `BOSS_RAILS` is the other half of this — a boss owes that list a rail and this one a `true` — and a comptime
/// block there pins the two, so the set that gets a bar and the set a fog gate can be sealed on are one set.
///
/// **THE ONLY CONSUMER THAT NEEDS IT BY NAME IS THE EDITOR.** A gate's `boss=` names what the ward waits on
/// (`worldfmt.Op.boss`, `game.solveArenaSeals`), and offering all thirty-eight kinds there is a list nobody
/// scrolls and a seal nobody meant: a ward held on a broodling is a door that opens when a broodling dies.
pub fn isBoss(k: wf.FoeKind) bool {
    return switch (k) {
        .bone_knight => true,
        // A duo is TWO bosses and two bars, because they die separately (`game.BOSS_RAILS`).
        .fungal_swordsman, .fungal_magus => true,
        .toad, .archer, .ogre, .berserker, .priest, .slinger => false,
        .brood_mother, .broodling, .brood_sac => false,
        .shieldman, .greatsword, .shade, .mourner => false,
        .leechfly, .rooted, .shroom, .delver, .necromancer => false,
        .fungal_deer, .mushroom_mage, .fen_lurker, .spore_golem => false,
        .bone_skitterer, .ancient_priest, .tolling_hollow => false,
        .slumber_bloom, .cinder_wake, .rotgorger, .birchwight, .salt_husk => false,
        .fish_spearman, .fish_netter, .fish_shaman, .blinkbat => false,
    };
}

test "A BOSS IS FILED, AND THE SET IS SMALL ENOUGH TO BE A LIST" {
    var n: usize = 0;
    const total = @typeInfo(wf.FoeKind).@"enum".fields.len;
    std.debug.print("\n  bosses:", .{});
    for (0..total) |i| {
        const k: wf.FoeKind = @enumFromInt(i);
        if (!isBoss(k)) continue;
        n += 1;
        std.debug.print(" {s}", .{wf.foeName(k)});
    }
    std.debug.print("  ({d} of {d} kinds)\n", .{ n, total });
    // A gate offers this list unscrolled, which is what taking it off all thirty-eight bought.
    try std.testing.expect(n >= 1 and n <= 12);
    try std.testing.expect(isBoss(.bone_knight) and isBoss(.fungal_magus));
    try std.testing.expect(!isBoss(.broodling));
}

/// Everything that reads right in `b`, plus everything that reads right anywhere — `props.inBiome`'s rule, for
/// the creatures.
pub fn atHome(k: wf.FoeKind, b: props.Biome) bool {
    const own = homeOf(k);
    return own == b or own == .any;
}

test "EVERY KINGDOM THAT HOLDS A CREATURE HOLDS MORE THAN ONE, and the wanderers are in every list" {
    var n = [_]usize{0} ** props.Biome.N;
    for (0..@typeInfo(wf.FoeKind).@"enum".fields.len) |i| n[@intFromEnum(homeOf(@enumFromInt(i)))] += 1;
    std.debug.print("\n  foe homes:", .{});
    for (n, 0..) |c, i| {
        if (c == 0) continue;
        const b: props.Biome = @enumFromInt(i);
        std.debug.print(" {s} {d}", .{ b.label(), c });
        // A kingdom with ONE creature in it is a chip that opens onto a single row — file it or fold it.
        try std.testing.expect(c >= 2);
    }
    std.debug.print("\n", .{});
    // …and an `any` creature answers every kingdom, which is what keeps it off a chip of its own.
    for (0..props.Biome.N) |i| try std.testing.expect(atHome(.blinkbat, @enumFromInt(i)));
    try std.testing.expect(!atHome(.toad, .ash));
    try std.testing.expect(atHome(.toad, .wetland));
}

/// A share of its OWN STATURE — the hips. The hero's own limit is 0.76 of his (`env.WADE_MAX`).
pub const WADE_FRAC: f32 = 0.45;

pub fn wadeLimit(k: wf.FoeKind, stature: f32) f32 {
    return switch (traitsOf(k).gait) {
        .walking => WADE_FRAC * mathx.maxF(stature, 0.2),
        .waterfaring, .flying, .rooted => std.math.floatMax(f32),
    };
}

/// **NO ATTACK COMES OUT OF NOWHERE**: seconds the kit must be VISIBLY MOVING first. A chop at 0.14 and a bite at 0.20 read as INSTANT. A FLOOR under the winds, never the length of one.
pub const TELL_MIN: f32 = 0.30;

/// SECONDS back from the move's own impact frame, and it IS the parry's difficulty. Every creature with a window reads THIS one (`ogre.parryable`).
pub const PARRY_LEAD: f32 = 0.18;

pub fn inParryWindow(left: f32) bool {
    return left >= 0 and left <= PARRY_LEAD;
}

/// THE HERO'S SHIELD, STAMPED ON EVERY MEMBER (`game.markParry`) — a ONE-FRAME edge, read after `update`.
pub fn setParry(foes: anytype, p: Parry) void {
    for (foes) |*f| f.parry = p;
}
pub fn anyParried(foes: anytype) bool {
    for (foes) |*f| {
        if (f.parried) return true;
    }
    return false;
}

pub fn corporeal(f: anytype) bool {
    return f.alive() and !f.dying();
}


/// Past its own notice ring, before turning for home. Per-creature: one flat 30 m was 2.7x the toad's aggro and the spacing between camps in `worlds/`.
pub const LEASH_SLACK: f32 = 6.0;
/// …and it is home again only this close — the hysteresis, so a foe at the boundary cannot flap.
pub const LEASH_HOME_R: f32 = 3.0;
pub const LEASH_CALM: f32 = 4.5;
/// Walking back into a homing foe turns it round, and for this long it cannot try to leave again. MUST stay
/// above `LEASH_CALM` (else standing still sheds it) and below `PROVOKE_HOLD` (what three blows buy).
pub const REENGAGE_HOLD: f32 = 8.0;

pub const SIGHT_MEMORY: f32 = 6.0;

pub const PROVOKE_PER_HIT: f32 = 1.0;
pub const PROVOKE_ROUSE: f32 = 14.0;
pub const PROVOKE_BREAK: f32 = 2.5;
pub const PROVOKE_HOLD: f32 = 14.0;
pub const PROVOKE_DECAY: f32 = 0.35;

pub fn leashR(aggroR: f32) f32 {
    return aggroR + LEASH_SLACK;
}

pub const Leash = struct {
    sinceCombat: f32 = mathx.LONG_AGO,
    sinceSeen: f32 = 0,
    provoked: f32 = 0,
    rouseLeft: f32 = 0,
    breakLeft: f32 = 0,
    engagedLeft: f32 = 0,
    returning: bool = false,

    /// Per frame, BEFORE the state machine decides anything. **BOTH RANGES ARE MEASURED FROM THE POST** —
    /// `out` for the creature, `heroOut` for the hero. Tethers nominally 17–30 m long release at 34 m (ogre) to 176 m (leechfly).
    pub fn tick(self: *Leash, dt: f32, out: f32, heroOut: f32, aggroR: f32) void {
        self.sinceCombat += dt;
        self.sinceSeen += dt;
        self.provoked = mathx.maxF(0, self.provoked - PROVOKE_DECAY * dt);
        self.rouseLeft = mathx.maxF(0, self.rouseLeft - dt);
        self.breakLeft = mathx.maxF(0, self.breakLeft - dt);
        self.engagedLeft = mathx.maxF(0, self.engagedLeft - dt);
        if (self.breakLeft > 0) {
            self.returning = false;
            return;
        }
        if (self.returning) {
            if (out <= LEASH_HOME_R) {
                self.returning = false;
            } else if (heroOut <= aggroR) {
                self.reengage();
            }
            return;
        }
        if (self.engagedLeft > 0) return;
        if (out > leashR(aggroR) and heroOut > aggroR and self.sinceCombat >= LEASH_CALM) self.returning = true;
    }

    pub fn noteCombat(self: *Leash) void {
        self.sinceCombat = 0;
    }

    pub fn noteSeen(self: *Leash) void {
        self.sinceSeen = 0;
    }

    pub fn blindNow(self: *Leash) void {
        self.sinceSeen = mathx.LONG_AGO;
    }

    pub fn blind(self: *const Leash) bool {
        return self.sinceSeen > SIGHT_MEMORY and !self.roused();
    }

    /// **A SUMMONS, NOT A WOUND** (the tolling hollow's bell). Never touches `provoked`: the leash BREAK is what three blows buy, and a bell rung four times may not buy it for a whole camp.
    pub fn call(self: *Leash) void {
        self.noteCombat();
        self.rouseLeft = PROVOKE_ROUSE;
        self.reengage();
    }

    pub fn provoke(self: *Leash) void {
        self.call();
        self.provoked += PROVOKE_PER_HIT;
        if (self.provoked >= PROVOKE_BREAK) self.breakLeft = PROVOKE_HOLD;
    }

    fn reengage(self: *Leash) void {
        self.returning = false;
        self.engagedLeft = REENGAGE_HOLD;
    }

    pub fn goingHome(self: *const Leash) bool {
        return self.returning;
    }

    pub fn roused(self: *const Leash) bool {
        return self.breakLeft > 0 or self.rouseLeft > 0;
    }
};

pub fn sensedDist(l: *const Leash, real: f32, aggroR: f32) f32 {
    if (l.blind()) return mathx.LONG_AGO;
    if (l.goingHome()) return mathx.LONG_AGO;
    if (l.roused()) return mathx.minF(real, aggroR);
    return real;
}

/// A `call` and not a `provoke` (see `Leash.call`). The radius is the SOUND's, so it is measured from where the noise was made and not from the creature that made it.
pub fn rouseWithin(foes: anytype, at: rl.Vector3, r: f32) u32 {
    var n: u32 = 0;
    for (foes) |*f| {
        if (!corporeal(f)) continue;
        if (mathx.distXZ(f.pos, at) > r) continue;
        f.leash.call();
        n += 1;
    }
    return n;
}

/// `out` and `heroOut` transposed is a tether that releases at the wrong range.
pub fn tickLeash(l: *Leash, dt: f32, at: rl.Vector3, home: rl.Vector3, hero: rl.Vector3, aggroR: f32) void {
    l.tick(dt, mathx.distXZ(at, home), mathx.distXZ(home, hero), aggroR);
}

/// …AND A FIXTURE'S: it is always at its post, so `out` is 0 and the tether only asks whether HE left.
pub fn tickFixedLeash(l: *Leash, dt: f32, home: rl.Vector3, hero: rl.Vector3, aggroR: f32) void {
    l.tick(dt, 0, mathx.distXZ(home, hero), aggroR);
}

pub fn senseHero(l: *const Leash, at: rl.Vector3, hero: rl.Vector3, aggroR: f32) f32 {
    return sensedDist(l, mathx.distXZ(at, hero), aggroR);
}

/// **THE FRONTAL CONE EVERY CLOSE BLOW ANSWERS FOR**: inside `reach`, inside `dot` of the way the body looks,
/// with `POINT_BLANK` exempt. Six creatures had this written out with the dot product by hand and one had
/// already drifted on the exemption. `reach` is the whole reach, the hero's own footprint included.
pub fn inFront(pos: rl.Vector3, facing: f32, at: rl.Vector3, reach: f32, dot: f32) bool {
    const d = mathx.distXZ(pos, at);
    if (d > reach) return false;
    if (d <= POINT_BLANK) return true;
    const to = mathx.dirXZ(pos, at);
    const fwd = mathx.headingDir(facing);
    return to.x * fwd.x + to.z * fwd.z >= dot;
}

/// **THE SAME QUESTION IN DEGREES** — for callers whose sector is authored as an ARC (`combat.withinArc`'s
/// unit) rather than a dot. The exemption is DIFFERENT on purpose and is the degenerate one — a bearing off a
/// zero-length vector is not a bearing — where `inFront`'s is the metre of `POINT_BLANK`.
pub fn inArc(pos: rl.Vector3, facing: f32, at: rl.Vector3, reach: f32, arcDeg: f32) bool {
    if (mathx.distXZ(pos, at) > reach) return false;
    const to = mathx.dirXZ(pos, at);
    if (mathx.lenXZ(to) < 1e-4) return true;
    return combat.withinArc(mathx.headingXZ(to), facing, arcDeg);
}

pub fn faceToward(pos: rl.Vector3, facing: *f32, target: rl.Vector3, rate: f32, dt: f32) void {
    const d = mathx.dirXZ(pos, target);
    if (mathx.lenXZ(d) < 1e-3) return;
    facing.* = mathx.approachAngle(facing.*, mathx.headingXZ(d), rate * dt);
}

/// **WHAT A UNIT DOES BEFORE IT HAS SEEN ANYBODY** (owner: a few basic idle enemy AIs, assigned per unit in the
/// editor).
///
/// **PRE-AGGRO ONLY** (owner). Nothing here touches a fight: the moment a creature is engaged its own state
/// machine owns it, and this hands back nothing until it is idle again.
/// **ONE ENUM, NOT TWO KEPT IN LOCKSTEP.** The FORMAT owns the authored shapes (`wf.FoeAi`, `wf.Wp`) because the
/// editor and the save both spell them; the runtime only reads them. Two parallel enums is the brittleness the
/// repo's own audit rules name.
pub const Ai = wf.FoeAi;
pub const MAX_WP: usize = wf.MAX_WP;
pub const Wp = wf.Wp;

/// How far a LEASHED roamer strays from its post, and how long it stands at each place it picks.
pub const ROAM_R: f32 = 9.0;
const ROAM_STEP_LO: f32 = 3.0;
const DWELL_LO: f32 = 1.4;
const DWELL_HI: f32 = 5.0;
/// An unleashed roamer picks its next place the same way; it just measures from where it IS rather than a post.
///
/// **PUBLIC, BECAUSE IT IS A CONTRACT WITH WHOEVER WALKS THE MARK.** A creature that stops SHORT of this never
/// arrives, so `want` hands back the same place for ever and the body stands there: the scrapped ravager's own
/// `HOME_R` was 1.2 against this 1.1 and it stalled a tenth of a metre out.
pub const ARRIVE: f32 = 1.1;

/// **THE CREATURE OWES A FIELD AND ONE CALL** (`foe.Nav`'s rule). It embeds this, the game stamps the authored
/// mode and route onto it at spawn, and the creature asks `want` from its own IDLE — never reaches out for it.
pub const Post = struct {
    ai: Ai = .hold,
    home: rl.Vector3 = mathx.zero3,
    wp: [MAX_WP]Wp = [_]Wp{.{}} ** MAX_WP,
    nwp: u8 = 0,
    /// Which leg of the route, and which way along it — a patrol turns round rather than teleporting to the start.
    leg: u8 = 0,
    back: bool = false,
    mark: rl.Vector3 = mathx.zero3,
    marked: bool = false,
    dwell: f32 = 0,
    rng: mathx.Rng = mathx.Rng.init(0x9051_11AA),

    pub fn arm(self: *Post, ai: Ai, home: rl.Vector3, pts: []const Wp, seed: f32) void {
        self.* = .{ .ai = ai, .home = home, .rng = fxStream(seed, 26417.0, 11) };
        for (pts, 0..) |p, i| {
            if (i >= MAX_WP) break;
            self.wp[i] = p;
            self.nwp = @intCast(i + 1);
        }
    }

    pub fn idles(self: *const Post) bool {
        return self.ai != .hold;
    }

    /// **WHERE TO WALK, OR NULL TO STAND.** Called every frame a creature is NOT engaged; `at` is where it is.
    /// A creature that is fighting, going home on its leash, or otherwise busy simply does not call this.
    pub fn want(self: *Post, dt: f32, at: rl.Vector3) ?rl.Vector3 {
        switch (self.ai) {
            .hold => return null,
            .patrol => return self.walkRoute(at),
            .roam, .roam_free => {
                if (self.dwell > 0) {
                    self.dwell -= dt;
                    return null;
                }
                if (self.marked and mathx.distXZ(at, self.mark) > ARRIVE) return self.mark;
                if (self.marked) {
                    // Arrived: stand a while, so a roamer reads as an animal and not a patrolling guard.
                    self.marked = false;
                    self.dwell = self.rng.range(DWELL_LO, DWELL_HI);
                    return null;
                }
                self.pick(at);
                return self.mark;
            },
        }
    }

    /// **THE LEASH IS ON THE POST, NOT ON THE STEP** — a leashed roamer picks anywhere inside `ROAM_R` of home,
    /// so it cannot walk itself out one short step at a time the way a per-step limit lets it.
    fn pick(self: *Post, at: rl.Vector3) void {
        const a = self.rng.angle();
        const d = self.rng.range(ROAM_STEP_LO, ROAM_R);
        // The leash is the POST, so a leashed roamer's `d` is already inside `ROAM_R` of it and there is nothing
        // left to clamp — the clamp that stood here could not fire. An unleashed one measures from where it IS.
        const from = if (self.ai == .roam) self.home else at;
        self.mark = v3(from.x + mathx.cosf(a) * d, from.y, from.z + mathx.sinf(a) * d);
        self.marked = true;
    }

    /// The leg this patrol is walking toward, for the tether to measure from. `fallback` covers a route with
    /// no legs on it at all, which is an authored patrol that never got one.
    pub fn legHere(self: *const Post, fallback: rl.Vector3) rl.Vector3 {
        if (self.nwp == 0) return fallback;
        return self.legAt(self.leg);
    }

    fn legAt(self: *const Post, i: u8) rl.Vector3 {
        if (i == 0) return self.home;
        const w = self.wp[@min(i - 1, MAX_WP - 1)];
        return v3(w.x, self.home.y, w.z);
    }

    /// The route is the POST and then every painted point, walked out and back. A unit with no points painted
    /// has nothing to patrol and stands, so a half-finished route in the editor is never a creature spinning.
    fn walkRoute(self: *Post, at: rl.Vector3) ?rl.Vector3 {
        if (self.nwp == 0) return null;
        const last: u8 = self.nwp;
        const target = self.legAt(self.leg);
        if (mathx.distXZ(at, target) > ARRIVE) return target;
        if (self.back) {
            if (self.leg == 0) {
                self.back = false;
                self.leg = 1;
            } else self.leg -= 1;
        } else {
            if (self.leg >= last) {
                self.back = true;
                self.leg = last - 1;
            } else self.leg += 1;
        }
        return self.legAt(self.leg);
    }
};

pub const Nav = struct {
    dir: ?rl.Vector3 = null,
    /// WHICH WAY ROUND IT WENT LAST TIME, and this is why it does not dither: with both sides equally open, the
    /// side it already committed to wins. Re-set to whichever side actually worked, so it cannot commit to a wrong one for good.
    side: f32 = 1,

    pub fn aim(self: *const Nav, from: rl.Vector3, want: rl.Vector3) rl.Vector3 {
        const d = self.dir orelse return want;
        return mathx.addV(from, d);
    }

    pub fn along(self: *const Nav, want: rl.Vector3) rl.Vector3 {
        return self.dir orelse want;
    }
};

test "AN UNSTAMPED WAY CHANGES NOTHING — steering is a bend on a refused heading, never a layer on top of one" {
    const at = mathx.ground(0, 0);
    const want = mathx.ground(0, 10);
    var n = Nav{};
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(want, n.aim(at, want)), 1e-6);
    const straight = mathx.dirXZ(at, want);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(straight, n.along(straight)), 1e-6);
    n.dir = v3(1, 0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(mathx.ground(1, 0), n.aim(at, want)), 1e-6);
    try std.testing.expectApproxEqAbs(mathx.headingXZ(n.dir.?), mathx.headingXZ(mathx.dirXZ(at, n.aim(at, want))), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), n.along(straight).x, 1e-6);
}

pub const SENSE_SMOOTH: f32 = 6.0;
pub const PRESSURE_HALFLIFE: f32 = 3.2;

/// ALL WORLD STATE — a measured bearing rate and damage taken since it last stood somewhere else, so NO INPUT
/// READING holds by construction. **PRESSURE IS PER SPOT, NOT PER FIGHT** (`stood`): travelling past `spanR` wipes the meter.
pub const Sense = struct {
    bearingWas: f32 = 0,
    circleRate: f32 = 0,
    hurtHere: f32 = 0,
    stood: rl.Vector3 = mathx.zero3,

    /// ONE FRAME, before the state machine decides anything (`Leash.tick`'s slot). `bearing` is the quarry's
    /// bearing off the creature's own facing, in RADIANS. `settled` is false while the creature's OWN movement is what sweeps it.
    pub fn tick(self: *Sense, dt: f32, at: rl.Vector3, bearing: f32, spanR: f32, settled: bool) void {
        const rate = @abs(mathx.wrapPi(bearing - self.bearingWas)) / mathx.maxF(dt, 1e-4);
        self.bearingWas = bearing;
        if (settled) self.circleRate = mathx.approach(self.circleRate, rate, dt * SENSE_SMOOTH);
        if (mathx.distXZ(at, self.stood) > spanR) {
            self.stood = at;
            self.hurtHere = 0;
            return;
        }
        self.hurtHere *= std.math.pow(f32, 0.5, dt / PRESSURE_HALFLIFE);
    }

    pub fn hurt(self: *Sense, dmg: f32) void {
        self.hurtHere += mathx.maxF(dmg, 0);
    }

    pub fn circling(self: *const Sense, rate: f32) bool {
        return self.circleRate > rate;
    }

    pub fn pressed(self: *const Sense, maxHp: f32, share: f32) bool {
        return self.hurtHere >= mathx.maxF(maxHp, 1) * share;
    }
};

test "PRESSURE IS PER SPOT: damage banked where it USED to stand is not a reason to leave where it is now" {
    var s = Sense{};
    const dt = 1.0 / 60.0;
    const here = mathx.ground(0, 0);
    s.tick(dt, here, 0, 0.5, true);
    s.hurt(40);
    try std.testing.expect(s.pressed(100, 0.3));
    var k: i32 = 0;
    while (k < 30) : (k += 1) s.tick(dt, here, 0, 0.5, true);
    try std.testing.expect(s.hurtHere > 0);
    s.tick(dt, mathx.ground(0, 3.0), 0, 0.5, true);
    try std.testing.expect(!s.pressed(100, 0.3));
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.hurtHere, 1e-6);
}

test "IT DOES NOT READ ITS OWN TRAVEL AS AN ORBIT" {
    var s = Sense{};
    const dt = 1.0 / 60.0;
    const at = mathx.ground(0, 0);
    var k: i32 = 0;
    var b: f32 = 0;
    while (k < 40) : (k += 1) {
        b += 0.05;
        s.tick(dt, at, b, 0.5, false);
    }
    try std.testing.expect(!s.circling(0.45));
    k = 0;
    while (k < 60) : (k += 1) {
        b += 0.05;
        s.tick(dt, at, b, 0.5, true);
    }
    try std.testing.expect(s.circling(0.45));
}

/// ONE DIAL FOR THE WHOLE FIELD. What each creature sheds and in what proportion stays in its own file.
pub const HIT_PARTS: f32 = 1.5;

pub fn hitParts(n: i32) i32 {
    return @intFromFloat(@round(@as(f32, @floatFromInt(n)) * HIT_PARTS));
}

pub fn flashFrac(flash: f32) f32 {
    return mathx.clampF(flash / FLASH_DUR, 0, 1);
}

/// …AND THE DRAIN THAT GOES WITH IT: `FLASH_DUR` is a DURATION, so only a decay of 1.0/s makes it one.
pub fn fadeFlash(flash: *f32, dt: f32) void {
    flash.* = mathx.maxF(0, flash.* - dt);
}

/// `h` metres of ITS OWN SCALE above the ground under it, plus this frame's `lift`. **EVERY WORLD POINT ON AN ACTOR IS MEASURED FROM `pos.y`** — off the datum, a foe on a bank keeps its bar down in the field.
pub fn bodyPoint(pos: rl.Vector3, h: f32, scale: f32, lift: f32) rl.Vector3 {
    return v3(pos.x, pos.y + h * scale + lift, pos.z);
}

/// `at` is in the BONE's own frame, which already carries the rig's scale, the facing and `pos`; every `spawn` poses before it returns, so the matrix is never undefined.
pub fn markOn(bone: rl.Matrix, at: rl.Vector3) rl.Vector3 {
    return rl.math.vector3Transform(at, bone);
}

pub fn swingCurve(u: f32) f32 {
    return std.math.pow(f32, mathx.smoothstep(0, 1, u), 1.35);
}

pub fn stunCurve(t: f32, heavy: bool) f32 {
    const u = mathx.clampF(t / combat.foeStunDur(heavy), 0, 1);
    if (!heavy) return mathx.sinf(u * std.math.pi);
    return mathx.pulse(u, 0, 0.14, 0.74, 1.0);
}

pub const Push = struct { light: f32, heavy: f32 };

pub const Clock = struct { wind: f32, strike: f32, recover: f32 };

pub fn moveClock(row: anytype) Clock {
    return .{ .wind = row.windDur, .strike = row.strikeDur, .recover = row.recoverDur };
}

pub fn reached(self: anytype, blade: Blade) ?Strike {
    const s = strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), blade) orelse return null;
    self.leash.provoke();
    // **AND WHOEVER SWUNG IT JUST BOUGHT ITS ATTENTION.** The ONE place damage-threat is written; the blade says who it belongs to (`Blade.by`).
    self.threat.hurtBy(blade.by, blade.hit.raw());
    if (blade.pierce) self.facing = mathx.headingXZ(mathx.scaleV(s.dir, -1));
    return s;
}

pub fn wounded(self: anytype, s: Strike, blade: Blade, push: Push) bool {
    self.hits += 1;
    self.flash = FLASH_DUR;
    const heavy = blade.hit.heavy();
    self.shove = mathx.scaleV(s.dir, if (heavy) push.heavy else push.light);
    woundImpact(self, s, heavy);
    return heavy;
}

pub const HIT_FLASH = mathx.rgba(255, 244, 214, 235);
const HIT_HAZE = mathx.rgba(64, 52, 42, 92);

const WOUND_HAZE_HEAVY = 3;
const WOUND_HAZE_LIGHT = 2;
/// Worst case — the flash plus the heavy blow's haze. Every pool asserted over its worst frame carries a landed blow in that frame.
pub const WOUND_PARTS = 1 + WOUND_HAZE_HEAVY;

/// The FLASH (gone in four frames) and the HAZE that hangs after; blood, bone and gore stay the creature's own. FIELDS ONLY: `parts`/`fxHead`/`fxRng`/`scale`.
fn woundImpact(self: anytype, s: Strike, heavy: bool) void {
    if (comptime !@hasField(std.meta.Child(@TypeOf(self)), "parts")) return;
    const fr: f32 = if (heavy) 0.15 else 0.10;
    emitPart(&self.parts, &self.fxHead, .{
        .p = s.contact,
        .v = mathx.scaleV(s.dir, 0.6),
        .life = 0.07,
        .r0 = fr * self.scale,
        .r1 = fr * self.scale * 0.3,
        .col = HIT_FLASH,
        .add = true,
    });
    var i: usize = 0;
    const n: usize = if (heavy) WOUND_HAZE_HEAVY else WOUND_HAZE_LIGHT;
    while (i < n) : (i += 1) {
        emitPart(&self.parts, &self.fxHead, .{
            .p = mathx.addV(s.contact, mathx.scaleV(randomUnit(&self.fxRng), 0.06 * self.scale)),
            .v = v3(s.dir.x * self.fxRng.range(0.4, 0.9), self.fxRng.range(0.2, 0.6), s.dir.z * self.fxRng.range(0.4, 0.9)),
            .life = self.fxRng.range(0.45, 0.75),
            .r0 = 0.05 * self.scale,
            .r1 = 0.16 * self.scale,
            .col = HIT_HAZE,
            .grav = -0.25,
            .drag = 2.5,
        });
    }
}

pub fn randomUnit(rng: *mathx.Rng) rl.Vector3 {
    const z = rng.signed();
    const a = rng.range(0, std.math.tau);
    const r = @sqrt(mathx.maxF(0, 1.0 - z * z));
    return v3(r * mathx.cosf(a), z, r * mathx.sinf(a));
}

/// THE FEET ARE HELD AND NOTHING ELSE IS. A GATE at the end of `update`, never a guard at each `stepXZ` —
/// a creature grows movements and a per-site list forgets one.
pub const Grip = struct {
    was: rl.Vector3,
    on: bool,
    killed: bool,
    /// **A METER PUT IT ON THE FLOOR THIS FRAME** — the lightning's stun, full. A ONE-FRAME EDGE, so the
    /// creature's own stagger (and its voice) fires once and then runs its clock like any other.
    downed: bool = false,

    pub fn hold(self: Grip, pos: *rl.Vector3) void {
        if (!self.on) return;
        pos.x = self.was.x;
        pos.z = self.was.z;
    }
};

pub fn canLeap(root: *const combat.Root) bool {
    return !root.held();
}

/// ONE FRAME OF WHAT IS ALREADY IN THE BODY — the wand's grip, the cold, and the poison off an envenomed edge.
/// Taken at the TOP of `update` and held through a `defer` there, so the pin covers whatever the state machine
/// goes on to do. Every bite is billed as a DRIP, never as a blow. **EVERY CREATURE IN THE GAME CALLS THIS**,
/// which is why a poison meter on `combat.Vitals` needed no field on any of them.
pub fn grip(root: *combat.Root, chill: *combat.Chill, vit: *combat.Vitals, dt: f32, at: rl.Vector3) Grip {
    const on = root.held();
    const bitten = if (root.tick(dt)) |bite| vit.drip(bite) == .death else false;
    const frozen = if (chill.tick(dt)) |bite| vit.drip(bite) == .death else false;
    const rotted = vit.tickAils(dt);
    // **THE COLD METER IS THE GATE IN FRONT OF THE HOLD IT ALREADY HAD.** Cold damage fills the meter and a
    // full meter takes the feet — so the buildup law reaches the chill without the chill growing a second clock.
    if (vit.ailProcced(.chill)) chill.touch();
    // **A SLEEP PROC GOES DOWN THE SAME DOOR THE LIGHTNING'S STUN DOES.** Only `sporegolem` reads
    // `vit.stunned()`; every other creature enters its stagger from `tryHit`'s reaction or from `grip.downed`,
    // and twenty of them handle this field. Pinning `vit.stunLeft` from `Vitals.tick` alone left sleep doing
    // NOTHING to nineteen groups — the coating and the bloom both landed a meter that no body answered.
    // One heavy stagger, which is exactly what the hero's own sleep proc buys (`hero.tickPoison`).
    // **AND A DEAD BODY IS NEVER DOWNED.** `tickAils` walks all ten meters in one pass, so a poison billing the
    // last of the bar and a stun filling on the same frame both come back true — and every creature answers
    // them in order (`if (grip.killed) enterDeath(); if (grip.downed) stagger(true);`), so the stagger put the
    // corpse back on its feet with its souls already paid and no state that can ever reach `.dead` again.
    // `hero.tickPoison` has always read `if (!self.dead)` here; this is that rule for the other twenty.
    return .{ .was = at, .on = on, .killed = bitten or frozen or rotted, .downed = !vit.dead and (vit.ailProcced(.stun) or vit.ailProcced(.sleep)) };
}

/// Stamped from outside every frame (`game.markParry`): the ARC belongs to the shield, not to what is caught.
pub const Parry = struct {
    live: bool = false,
    at: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,
    arc: f32 = combat.GUARD_ARC,

    pub fn catches(self: *const Parry, at: rl.Vector3, reach: f32) bool {
        if (!self.live) return false;
        return inArc(self.at, self.facing, at, reach, self.arc);
    }
};

/// FIELDS ONLY (`parry`, `pos`, `parried`, `flash`, `leash`): the cooldown, the sparks, the voice and the stun stay in the creature's own file.
pub fn caught(self: anytype, reach: f32) bool {
    if (!self.parry.catches(self.pos, reach)) return false;
    self.parried = true;
    self.flash = FLASH_DUR;
    self.leash.noteCombat();
    return true;
}

/// Stamped every frame (`game.markWade`) — only `game.zig` sees the creature and `env`'s water at once. `quarry` is the depth where the HERO IS STANDING: a fact about the ground, so NO INPUT READING holds.
pub const Wade = struct {
    here: f32 = 0,
    quarry: f32 = 0,
};

pub fn setWade(foes: anytype, at: anytype, quarry: f32, comptime depthAt: anytype) void {
    for (foes) |*f| f.wade = .{ .here = depthAt(at, f.pos), .quarry = quarry };
}

/// **A STAIN NEEDS DRY GROUND** — a splat lands at TERRAIN height, so a drop shed over water is blood on the riverbed. Opt-in on the `wade` field.
pub const SPLAT_DRY_MAX: f32 = 0.05;
pub fn onDryGround(self: anytype) bool {
    if (comptime !@hasField(std.meta.Child(@TypeOf(self)), "wade")) return true;
    return self.wade.here <= SPLAT_DRY_MAX;
}

test "A CREATURE THAT NEVER SEES WATER IS DRY BY CONSTRUCTION, and a wading one sheds no stain" {
    var landlocked = struct { pos: rl.Vector3 = mathx.zero3 }{};
    try std.testing.expect(onDryGround(&landlocked));
    var w = struct { wade: Wade = .{} }{};
    try std.testing.expect(onDryGround(&w));
    w.wade.here = SPLAT_DRY_MAX;
    try std.testing.expect(onDryGround(&w));
    w.wade.here = SPLAT_DRY_MAX + 0.01;
    try std.testing.expect(!onDryGround(&w));
}

/// The landing spot is solved ONCE at the launch and clamped THERE: clamped per frame, a hop into the rim shortens under you. FIELDS ONLY: `launched`/`hopFrom`/`hopTo`/`hopReach`.
pub fn hopStep(self: anytype, dt: f32, bounds: f32, dir: rl.Vector3, coil: f32, flight: f32) f32 {
    if (!self.launched) {
        self.launched = true;
        self.hopFrom = self.pos;
        self.hopTo = mathx.clampXZ(v3(self.pos.x + dir.x * self.hopReach, 0, self.pos.z + dir.z * self.hopReach), bounds);
    }
    const inv = 1.0 / flight;
    self.pos.x += (self.hopTo.x - self.hopFrom.x) * inv * dt;
    self.pos.z += (self.hopTo.z - self.hopFrom.z) * inv * dt;
    return (self.t - coil) / flight;
}

pub fn applyShove(pos: *rl.Vector3, shove: *rl.Vector3, decay: f32, bounds: f32, dt: f32) void {
    if (mathx.lenXZ(shove.*) <= 0.01) return;
    mathx.stepXZ(pos, shove.*, dt, bounds);
    shove.* = mathx.scaleV(shove.*, mathx.maxF(0, 1.0 - decay * dt));
}


pub const DUST = mathx.rgba(150, 132, 96, 175);
/// What a cloud THINS TO — paler and cooler as it disperses and takes the sky's light instead of the ground's.
pub const DUST_THIN = mathx.rgba(176, 168, 150, 96);
/// **DUST IS FINE PARTICULATE, NOT FLUNG GRAVEL.** High drag is what makes it dust, low gravity is what lets it hang.
pub const DUST_DRAG: f32 = 4.5;
pub const DUST_GRAV: f32 = 1.6;

/// **BLOOD IS DROPLETS, AND THE PHYSICS OF A DROPLET IS NOT THE CREATURE'S TO PICK.** The COLOUR stays each creature's own (a toad's is not a spider's), and so does how far it is thrown.
pub const BLOOD_DRAG: f32 = 3.6;
pub const BLOOD_GRAV: f32 = 14.0;
pub const BLOOD_STRETCH: f32 = 0.045;
pub const MOTE = mathx.rgba(252, 198, 92, 170);
pub const WAKE = mathx.rgba(224, 230, 244, 255);

/// **DRAG COSTS REACH, SO THE SPEED HAS TO BUY IT BACK.** Under drag `k` a mote covers v0/k·(1−e^(−k·t)) where
/// a free one covers v0·t; a burst moved onto drag without this arrives at a third of where it was aimed.
pub fn dragBoost(k: f32, life: f32) f32 {
    if (k <= 0 or life <= 0) return 1.0;
    return k * life / (1.0 - @exp(-k * life));
}

/// **THE LIFE, THE DRAG AND THE BOOST ARE ONE NUMBER IN THREE PARTS, SO THEY TRAVEL TOGETHER** — split up, a retuned range leaves the speed solved for the old one, silently. Built at comptime.
pub const Blast = struct {
    lo: f32,
    hi: f32,
    k: f32,
    boost: f32,

    pub fn of(k: f32, lo: f32, hi: f32) Blast {
        return .{ .lo = lo, .hi = hi, .k = k, .boost = dragBoost(k, (lo + hi) * 0.5) };
    }
    pub fn life(self: Blast, rng: *mathx.Rng) f32 {
        return rng.range(self.lo, self.hi);
    }
};

test "A BLAST SOLVES ITS OWN BOOST FROM ITS OWN LIFE — the two cannot be retuned apart" {
    const b = Blast.of(DUST_DRAG, 0.4, 0.7);
    try std.testing.expectEqual(dragBoost(DUST_DRAG, 0.55), b.boost);
    try std.testing.expectEqual(DUST_DRAG, b.k);
    // The same reach a free mote covered over the same mean life.
    const free: f32 = 3.0 * 0.55;
    const dragged = 3.0 * b.boost / b.k * (1.0 - @exp(-b.k * 0.55));
    try std.testing.expectApproxEqRel(free, dragged, 1e-4);
    var rng = mathx.Rng.init(0xB1A5);
    for (0..64) |_| {
        const t = b.life(&rng);
        try std.testing.expect(t >= b.lo and t <= b.hi);
    }
}

test "DRAG COSTS REACH AND THE BOOST BUYS IT BACK — same metres, front-loaded" {
    for ([_]f32{ 2.0, 3.6, 4.5 }) |k| {
        for ([_]f32{ 0.35, 0.55, 0.9 }) |life| {
            const boost = dragBoost(k, life);
            const free: f32 = 3.0 * life;
            const dragged = 3.0 * boost / k * (1.0 - @exp(-k * life));
            try std.testing.expectApproxEqRel(free, dragged, 1e-4);
        }
    }
    std.debug.print("\n  dust drag {d:.1}/s over a {d:.2} s life costs {d:.2}x the speed to reach the same metres\n", .{ DUST_DRAG, @as(f32, 0.55), dragBoost(DUST_DRAG, 0.55) });
    try std.testing.expectEqual(@as(f32, 1.0), dragBoost(0, 0.5));
}

pub fn fxStream(seed: f32, mul: f32, salt: u64) mathx.Rng {
    return mathx.Rng.init(@as(u64, @intFromFloat(@abs(seed) * mul)) +% salt);
}

pub const Particle = struct {
    p: rl.Vector3 = mathx.zero3,
    v: rl.Vector3 = mathx.zero3,
    life: f32 = 0,
    max: f32 = 1,
    r0: f32 = 0.05,
    r1: f32 = 0.05,
    col: rl.Color = mathx.rgba(255, 255, 255, 255),
    /// Colour at the END of life — hot things cool (white → amber → ember), wet things dry. Null keeps one colour.
    col1: ?rl.Color = null,
    grav: f32 = 0,
    /// 1/s exponential velocity decay — a burst that starts fast and DIES DOWN reads as a blast; linear flight reads as drift.
    drag: f32 = 0,
    /// Seconds of velocity the draw trails behind the head: a fast mote becomes a tapered streak, and collapses back to a dot as it slows.
    stretch: f32 = 0,
    /// Floor restitution — hard debris (bone chips, sparks) skitters instead of sticking.
    bounce: f32 = 0,
    /// >0: a drop that reaches the floor stops and lies as a stain this many times its radius. ONE-OFF BURSTS
    /// ONLY — a landed mote holds `SPLAT_HOLD`, so brood drool at 8-34/s was 40+ resident stains eating the blood behind them.
    splat: f32 = 0,
    /// LIGHT, not matter — drawn additive, so overlapping motes brighten into a glow. Matter (blood, dust, gas,
    /// chips) stays alpha-blended: additive can only brighten, and a dark thing drawn additive disappears.
    add: bool = false,
    landed: bool = false,
    floor: ?f32 = null,
};

pub fn emitTicks(acc: *f32, dt: f32, rate: f32, cap: usize) usize {
    acc.* += dt * rate;
    var n: usize = 0;
    while (acc.* >= 1.0 and n < cap) : (n += 1) acc.* -= 1.0;
    // **A HITCH IS A WHOLE MOTE STILL OWED AFTER THE CAP — NOT MERELY REACHING IT.** `emitCap` FLOORS AT ONE,
    // so at any rate under ~24/s the cap *is* one and every ordinary mote tripped it: the fenlurker's 16/s wake ran at 15.
    if (acc.* >= 1.0) acc.* = 0;
    return n;
}

/// **THE RATE AND ITS CEILING TRAVEL TOGETHER** — a cap that does not match its rate is an emitter quietly running slow. Pass a cap yourself only to mean something OTHER than this rate's own ceiling.
pub fn emitDue(acc: *f32, dt: f32, rate: f32) usize {
    return emitTicks(acc, dt, rate, emitCap(rate));
}

/// …AND THE CEILING ITSELF, off the rate. Floored at ONE, or an emitter could never pay a single mote — **and a cap of one is the NORMAL case**, every rate under ~24/s.
const EMIT_CAP_FRAMES: f32 = 2.5;
pub fn emitCap(rate: f32) usize {
    return @max(1, @as(usize, @intFromFloat(@ceil(mathx.maxF(rate, 0) / 60.0 * EMIT_CAP_FRAMES))));
}

test "THE CAP CLEARS A REAL FRAME AND NEVER LANDS ON ZERO" {
    for ([_]f32{ 5, 26, 54, 82, 240, 560 }) |rate| {
        try std.testing.expect(@as(f32, @floatFromInt(emitCap(rate))) > rate / 60.0);
    }
    try std.testing.expectEqual(@as(usize, 1), emitCap(0));
    var acc: f32 = 0;
    try std.testing.expectEqual(@as(usize, 1), emitTicks(&acc, 1.0, 1.0, emitCap(1.0)));
}

test "the accumulator carries a fraction across frames and DROPS a hitch's arrears" {
    var acc: f32 = 0;
    try std.testing.expectEqual(@as(usize, 10), emitTicks(&acc, 0.1, 100.0, 64));
    try std.testing.expectEqual(@as(usize, 0), emitTicks(&acc, 0.005, 100.0, 64));
    try std.testing.expectEqual(@as(usize, 1), emitTicks(&acc, 0.005, 100.0, 64));
    acc = 0;
    try std.testing.expectEqual(@as(usize, 24), emitTicks(&acc, 2.0, 560.0, 24));
    try std.testing.expectEqual(@as(f32, 0), acc);
    try std.testing.expectEqual(@as(usize, 0), emitTicks(&acc, 0, 560.0, 24));
}

test "A SLOW EMITTER RUNS AT ITS OWN RATE — a cap of one is not a hitch every time" {
    for ([_]f32{ 5.0, 9.0, 16.0, 22.0 }) |rate| {
        try std.testing.expectEqual(@as(usize, 1), emitCap(rate));
        var acc: f32 = 0;
        var n: usize = 0;
        var t: f32 = 0;
        const dt = 1.0 / 60.0;
        while (t < 10.0) : (t += dt) n += emitTicks(&acc, dt, rate, emitCap(rate));
        const got = @as(f32, @floatFromInt(n)) / 10.0;
        std.debug.print("  emitter at {d:.0}/s actually emits {d:.1}/s\n", .{ rate, got });
        try std.testing.expectApproxEqAbs(rate, got, 0.2);
    }
    var slow: f32 = 0;
    try std.testing.expectEqual(@as(usize, 1), emitTicks(&slow, 3.0, 16.0, emitCap(16.0)));
    try std.testing.expectEqual(@as(f32, 0), slow);
}

pub fn emitPart(pool: []Particle, head: *usize, q: Particle) void {
    pool[head.*] = q;
    pool[head.*].max = q.life;
    head.* = (head.* + 1) % pool.len;
}

pub const Spray = struct {
    fanLo: f32,
    fanHi: f32,
    upLo: f32,
    upHi: f32,
    lifeLo: f32,
    lifeHi: f32,
    rLo: f32,
    rHi: f32,
    r1: f32,
    col: rl.Color,
    grav: f32,
    col1: ?rl.Color = null,
    stretch: f32 = 0,
    bounce: f32 = 0,
    splat: f32 = 0,
    drag: f32 = 0,
};

/// **THE DRAW ORDER IS LOAD-BEARING** — angle, speed, the fan on X, the lift, the fan on Z, the life, the radius. The same numbers in another order give every caller a different wound off the same seed.
pub fn spray(pool: []Particle, head: *usize, rng: *mathx.Rng, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32, scale: f32, s: Spray) void {
    const parts = hitParts(n);
    var i: i32 = 0;
    while (i < parts) : (i += 1) {
        const a = rng.angle();
        const sp = rng.range(0.4, 1.0) * spd;
        const vel = v3(
            dir.x * sp + mathx.cosf(a) * rng.range(s.fanLo, s.fanHi),
            rng.range(s.upLo, s.upHi),
            dir.z * sp + mathx.sinf(a) * rng.range(s.fanLo, s.fanHi),
        );
        emitPart(pool, head, .{
            .p = at,
            .v = vel,
            .life = rng.range(s.lifeLo, s.lifeHi),
            .r0 = rng.range(s.rLo, s.rHi) * scale,
            .r1 = s.r1,
            .col = s.col,
            .col1 = s.col1,
            .grav = s.grav,
            .stretch = s.stretch,
            .bounce = s.bounce,
            .splat = s.splat,
            .drag = s.drag,
        });
    }
}

test "THE SPRAY IS THE FIVE HAND-WRITTEN LOOPS, MOTE FOR MOTE — the draw order is the thing being pinned" {
    const S = Spray{
        .fanLo = 0.15, .fanHi = 0.8,
        .upLo = 0.7,   .upHi = 2.4,
        .lifeLo = 0.28, .lifeHi = 0.5,
        .rLo = 0.028,  .rHi = 0.055,
        .r1 = 0.008,   .col = DUST, .grav = 7.5,
    };
    const at = v3(1, 2, 3);
    const dir = v3(0.6, 0, -0.8);
    const scale: f32 = 1.3;

    var wantPool = [_]Particle{.{}} ** 64;
    var wantHead: usize = 0;
    var r = mathx.Rng.init(0xB10D);
    var i: i32 = 0;
    while (i < hitParts(9)) : (i += 1) {
        const a = r.angle();
        const sp = r.range(0.4, 1.0) * 2.5;
        const vel = v3(
            dir.x * sp + mathx.cosf(a) * r.range(S.fanLo, S.fanHi),
            r.range(S.upLo, S.upHi),
            dir.z * sp + mathx.sinf(a) * r.range(S.fanLo, S.fanHi),
        );
        emitPart(&wantPool, &wantHead, .{ .p = at, .v = vel, .life = r.range(S.lifeLo, S.lifeHi), .r0 = r.range(S.rLo, S.rHi) * scale, .r1 = S.r1, .col = S.col, .grav = S.grav });
    }

    var gotPool = [_]Particle{.{}} ** 64;
    var gotHead: usize = 0;
    var r2 = mathx.Rng.init(0xB10D);
    spray(&gotPool, &gotHead, &r2, at, dir, 9, 2.5, scale, S);

    try std.testing.expectEqual(wantHead, gotHead);
    try std.testing.expect(gotHead > 0);
    for (wantPool, gotPool) |w, g| {
        try std.testing.expectEqual(w.v.x, g.v.x);
        try std.testing.expectEqual(w.v.y, g.v.y);
        try std.testing.expectEqual(w.v.z, g.v.z);
        try std.testing.expectEqual(w.life, g.life);
        try std.testing.expectEqual(w.r0, g.r0);
    }
    std.debug.print("\n  spray: {d} motes, identical to the hand-written loop mote for mote\n", .{gotHead});
}

/// **A FOOTFALL'S DUST IS A RING, NOT A FAN**, so `Spray`'s `dir` cannot say it — and the count is the
/// caller's own, never through `hitParts`: that dial is how heavy a WOUND reads, and a landing rescaled by it
/// is the bug `shroom.emitPuff` records. Six creatures each wrote this loop out. **THE DRAW ORDER IS
/// LOAD-BEARING** exactly as `spray`'s is — angle, speed, lift, life, radius, then the flare only if the
/// caller asked for one, so `bigJit` is part of the stream and not a cosmetic switch.
pub const Puff = struct {
    blast: Blast,
    spdLo: f32,
    upLo: f32,
    upHi: f32,
    rLo: f32,
    rHi: f32,
    /// Null is a flat `big` and ONE DRAW FEWER per mote, so it moves the stream and is not cosmetic.
    bigJit: ?[2]f32 = .{ 0.8, 1.3 },
    col: rl.Color = DUST,
    col1: rl.Color = DUST_THIN,
};

/// `at` is the mote's origin ALREADY LIFTED off the ground: whose Y the lift is measured from is the
/// creature's business (the brood's is the burst point, everyone else's is their own feet).
pub fn puff(pool: []Particle, head: *usize, rng: *mathx.Rng, at: rl.Vector3, n: i32, spd: f32, big: f32, scale: f32, p: Puff) void {
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const a = rng.angle();
        const sp = rng.range(p.spdLo, 1.0) * spd * scale * p.blast.boost;
        emitPart(pool, head, .{
            .p = at,
            .v = v3(mathx.cosf(a) * sp, rng.range(p.upLo, p.upHi) * p.blast.boost, mathx.sinf(a) * sp),
            .life = p.blast.life(rng),
            .r0 = rng.range(p.rLo, p.rHi) * scale,
            .r1 = if (p.bigJit) |j| big * rng.range(j[0], j[1]) * scale else big,
            .col = p.col,
            .col1 = p.col1,
            .grav = DUST_GRAV,
            .drag = DUST_DRAG,
        });
    }
}

test "THE PUFF IS THE SIX HAND-WRITTEN LOOPS, MOTE FOR MOTE — and the flat flare draws one number fewer" {
    const P = Puff{
        .blast = Blast.of(DUST_DRAG, 0.4, 0.7),
        .spdLo = 0.5,
        .upLo = 0.8,
        .upHi = 3.0,
        .rLo = 0.08,
        .rHi = 0.16,
    };
    const at = v3(2, 0.06, -1);
    const scale: f32 = 1.3;
    const big: f32 = 0.20;

    var wantPool = [_]Particle{.{}} ** 64;
    var wantHead: usize = 0;
    var r = mathx.Rng.init(0xD057);
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        const a = r.angle();
        const s = r.range(0.5, 1.0) * 2.0 * scale * P.blast.boost;
        emitPart(&wantPool, &wantHead, .{
            .p = at,
            .v = v3(mathx.cosf(a) * s, r.range(0.8, 3.0) * P.blast.boost, mathx.sinf(a) * s),
            .life = P.blast.life(&r),
            .r0 = r.range(0.08, 0.16) * scale,
            .r1 = big * r.range(0.8, 1.3) * scale,
            .col = DUST,
            .col1 = DUST_THIN,
            .grav = DUST_GRAV,
            .drag = DUST_DRAG,
        });
    }

    var gotPool = [_]Particle{.{}} ** 64;
    var gotHead: usize = 0;
    var r2 = mathx.Rng.init(0xD057);
    puff(&gotPool, &gotHead, &r2, at, 9, 2.0, big, scale, P);

    try std.testing.expectEqual(wantHead, gotHead);
    try std.testing.expect(gotHead > 0);
    for (wantPool, gotPool) |w, g| {
        try std.testing.expectEqual(w.v.x, g.v.x);
        try std.testing.expectEqual(w.v.y, g.v.y);
        try std.testing.expectEqual(w.v.z, g.v.z);
        try std.testing.expectEqual(w.life, g.life);
        try std.testing.expectEqual(w.r0, g.r0);
        try std.testing.expectEqual(w.r1, g.r1);
    }

    // A flat flare is one number fewer, which moves every mote after it — so it is pinned, not assumed.
    var flat = P;
    flat.bigJit = null;
    var a1 = [_]Particle{.{}} ** 64;
    var h1: usize = 0;
    var ra = mathx.Rng.init(0x51AB);
    puff(&a1, &h1, &ra, at, 3, 2.0, big, scale, flat);
    var a2 = [_]Particle{.{}} ** 64;
    var h2: usize = 0;
    var rb = mathx.Rng.init(0x51AB);
    puff(&a2, &h2, &rb, at, 3, 2.0, big, scale, P);
    try std.testing.expectEqual(big, a1[0].r1);
    try std.testing.expect(a1[1].life != a2[1].life);
    std.debug.print("\n  puff: {d} motes identical to the hand-written loop; a flat flare shifts the stream\n", .{gotHead});
}

/// **A BURST IS JUDGED BY ITS CROSS-SECTION, NOT BY ITS SPEED.** `open` is the widest separation perpendicular to `dir`, `reach` the furthest any mote got, both at `sampleAt`; `splats` is counted once the flight is over.
pub const SprayShape = struct { open: f32, reach: f32, splats: usize, motes: usize, sink: f32 };

pub fn measureSpray(pool: []Particle, s: Spray, at: rl.Vector3, dir: rl.Vector3, n: i32, spd: f32, scale: f32, seed: u64, sampleAt: f32, floor: f32) SprayShape {
    // The caller hands a pool that holds the whole burst, or the measurement reads motes it overwrote.
    const motes = @as(usize, @intCast(@max(0, hitParts(n))));
    std.debug.assert(motes <= pool.len);
    var head: usize = 0;
    var rng = mathx.Rng.init(seed);
    spray(pool, &head, &rng, at, dir, n, spd, scale, s);
    var out = SprayShape{ .open = 0, .reach = 0, .splats = 0, .motes = motes, .sink = 0 };
    const dt = 1.0 / 60.0;

    var t: f32 = 0;
    var sampled = false;
    while (t < 3.0) : (t += dt) {
        tickParticles(pool, dt, floor);
        if (!sampled and t + dt >= sampleAt) {
            sampled = true;
            for (pool[0..motes], 0..) |*a, i| {
                out.reach = mathx.maxF(out.reach, mathx.lenV(mathx.subV(a.p, at)));
                for (pool[i + 1 .. motes]) |*b| {
                    const d = mathx.subV(a.p, b.p);
                    const along = d.x * dir.x + d.y * dir.y + d.z * dir.z;
                    out.open = mathx.maxF(out.open, mathx.lenV(mathx.subV(d, mathx.scaleV(dir, along))));
                }
            }
        }
    }
    for (pool[0..motes]) |*q| {
        if (q.landed) out.splats += 1;
    }

    // …and the same flight given all the life it wants: `sink` is what `lifeHi` must cover for a stain.
    head = 0;
    var rng2 = mathx.Rng.init(seed);
    spray(pool, &head, &rng2, at, dir, n, spd, scale, s);
    for (pool[0..motes]) |*q| q.life = 9.0;
    t = 0;
    while (t < 3.0) : (t += dt) {
        tickParticles(pool, dt, floor);
        var flying: usize = 0;
        for (pool[0..motes]) |*q| {
            if (!q.landed) flying += 1;
        }
        if (flying == 0) break;
        out.sink = t + dt;
    }
    return out;
}

pub fn floorBurst(pool: []Particle, from: usize, to: usize, floor: f32) void {
    var i = from;
    while (i != to) : (i = (i + 1) % pool.len) pool[i].floor = floor;
}

/// **A BODY GOES BY GOING TRANSPARENT, NOT BY GETTING SMALL** — at the 55-85% shrink it had, a corpse walks off into the ground. What is left is a SETTLE, a tenth.
pub const DEATH_SHRINK: f32 = 0.10;
pub fn rigScale(scale: f32, fade: f32) f32 {
    return scale * (1.0 - DEATH_SHRINK * fade);
}

/// **…AND IT SETTLES INTO THE GROUND WHILE IT GOES** — `rigScale`'s other half, written out by TWELVE creatures
/// as `-depth * self.scale * self.fade`. The SHAPE is the shared thing (metres of the body's OWN scale, run off
/// the same `fade`); the DEPTH is per-creature the way `DEATH_DUR` is, so it is an argument and not a constant.
/// The shade passes its `thin` here, which is the only name that rig has for the same clock.
pub fn rigSink(depth: f32, scale: f32, fade: f32) f32 {
    return -depth * scale * fade;
}

/// What a walking humanoid settles by. FIVE rigs wrote this figure out — the archer, the warrior, the
/// necromancer, the ancient priest and the tolling hollow are one body in five coats.
pub const SINK_HUMANOID: f32 = 0.55;

pub const Dissolve = struct {
    rate: f32 = 54.0,
    spread: f32 = 0.85,
    rise: f32 = 0.70,
    flake: rl.Color = DUST,
};
const DISS_MOTE_SHARE: f32 = 0.76;
const DISS_MOTE_R: f32 = 0.094;
const DISS_FLAKE_R: f32 = 0.129;

pub fn dissolveMotes(self: anytype, dt: f32, d: Dissolve) void {
    const thinning = 1.0 - 0.6 * self.fade;
    var n = emitTicks(&self.fxAccum, dt, d.rate * thinning, emitCap(d.rate));
    while (n > 0) : (n -= 1) {
        const a = self.fxRng.angle();
        const rr = self.fxRng.range(0.1, 1.0) * d.spread * self.scale * thinning;
        const p = mathx.v3(
            self.pos.x + mathx.cosf(a) * rr,
            self.pos.y + self.fxRng.range(0.08, 1.0) * d.rise * self.scale,
            self.pos.z + mathx.sinf(a) * rr,
        );
        if (self.fxRng.float() < DISS_MOTE_SHARE) {
            emitPart(&self.parts, &self.fxHead, .{
                .p = p,
                .v = mathx.v3(self.fxRng.signed() * 0.3, self.fxRng.range(0.5, 1.4), self.fxRng.signed() * 0.3),
                .life = self.fxRng.range(0.55, 1.05),
                .r0 = self.fxRng.range(0.42, 1.0) * DISS_MOTE_R * d.spread * self.scale,
                .r1 = 0.004,
                .col = MOTE,
                .grav = -0.7,
                .add = true,
            });
        } else {
            // The ASH half — alpha, and it goes out by thinning where the mote above goes out by cooling. Its drag is what stops the two halves drifting apart.
            emitPart(&self.parts, &self.fxHead, .{
                .p = p,
                .v = mathx.v3(self.fxRng.signed() * 0.35, self.fxRng.range(0.1, 0.45), self.fxRng.signed() * 0.35),
                .life = self.fxRng.range(0.32, 0.65),
                .r0 = self.fxRng.range(0.55, 1.0) * DISS_FLAKE_R * d.spread * self.scale,
                .r1 = 0.011,
                .col = d.flake,
                .col1 = mathx.withAlpha(d.flake, d.flake.a / 3),
                .grav = 2.0,
                .drag = 1.8,
            });
        }
    }
}

/// **A CORPSE SOMETHING IS STANDING OVER DOES NOT GO** — `heldOpen`, read as an OPT-IN (`@hasField`): gaining a behaviour is a FIELD on the creature, never an edit to a shared pass.
fn stayed(self: anytype) bool {
    if (comptime @hasField(std.meta.Child(@TypeOf(self)), "heldOpen")) return self.heldOpen;
    return false;
}

pub fn dissipate(self: anytype, dt: f32, still: f32, diss: f32, d: Dissolve) void {
    if (self.t < still) return;
    if (stayed(self)) return;
    self.fade = mathx.smoothstep(still, still + diss, self.t);
    dissolveMotes(self, dt, d);
    if (self.t >= still + diss) self.gone = true;
}

/// **THE BODY COMING BACK UP** — `dissipate` run backwards. FIELDS ONLY: `vit`, `fade`, `gone`, `hitLatch`,
/// `flash`, `shove`, `justDied`, `heldOpen`, `t`. `hits` is deliberately NOT among them: `game.allHits` diffs it across a frame.
pub fn rekindle(self: anytype, frac: f32) void {
    self.vit.revive(frac);
    self.fade = 0;
    self.gone = false;
    self.hitLatch = false;
    self.flash = FLASH_DUR;
    self.shove = mathx.zero3;
    self.justDied = false;
    self.heldOpen = false;
    self.t = 0;
}

const SPLAT_HOLD: f32 = 0.7;

pub fn tickParticles(pool: []Particle, dt: f32, floor: f32) void {
    for (pool) |*q| {
        if (q.life <= 0) continue;
        q.life -= dt;
        if (q.landed) continue;
        q.p.x += q.v.x * dt;
        q.p.y += q.v.y * dt;
        q.p.z += q.v.z * dt;
        q.v.y -= q.grav * dt;
        if (q.drag > 0) {
            const k = 1.0 / (1.0 + q.drag * dt);
            q.v.x *= k;
            q.v.y *= k;
            q.v.z *= k;
        }
        const at = q.floor orelse floor;
        if (q.p.y < at) {
            q.p.y = at;
            if (q.splat > 0) {
                q.landed = true;
                q.v = mathx.zero3;
                // A stain fades on its own clock — on the flight's leftovers it was gone before anyone saw it.
                q.life = SPLAT_HOLD;
                q.max = SPLAT_HOLD;
            } else if (q.bounce > 0 and q.v.y < 0) {
                q.v.y = -q.v.y * q.bounce;
                q.v.x *= 0.6;
                q.v.z *= 0.6;
            }
        }
    }
}

test "a SPLAT drop stops where it lands and a BOUNCE chip skitters" {
    var pool = [_]Particle{.{}} ** 4;
    var head: usize = 0;
    emitPart(&pool, &head, .{ .p = v3(0, 0.5, 0), .v = v3(1.0, -2.0, 0), .life = 1.0, .splat = 3.0 });
    emitPart(&pool, &head, .{ .p = v3(0, 0.5, 0), .v = v3(1.0, -2.0, 0), .life = 1.0, .bounce = 0.5 });
    var t: f32 = 0;
    while (t < 0.5) : (t += 1.0 / 60.0) tickParticles(&pool, 1.0 / 60.0, 0);
    try std.testing.expect(pool[0].landed);
    try std.testing.expectEqual(@as(f32, 0), pool[0].p.y);
    try std.testing.expectEqual(@as(f32, 0), mathx.lenV(pool[0].v));
    try std.testing.expect(!pool[1].landed);
    try std.testing.expect(pool[1].v.x > 0);
    var burst = [_]Particle{.{}} ** 1;
    var bh: usize = 0;
    emitPart(&burst, &bh, .{ .p = mathx.zero3, .v = v3(4.0, 0, 0), .life = 2.0, .drag = 2.6 });
    t = 0;
    while (t < 1.0) : (t += 1.0 / 60.0) tickParticles(&burst, 1.0 / 60.0, -10);
    try std.testing.expect(burst[0].v.x < 4.0 * 0.15);
}

test "EVERY LANDED BLOW IS THREE LAYERS — the flash on the impact frame, the haze hanging after" {
    const Dummy = struct {
        hits: u32 = 0,
        flash: f32 = 0,
        shove: rl.Vector3 = mathx.zero3,
        scale: f32 = 1.0,
        parts: [16]Particle = [_]Particle{.{}} ** 16,
        fxHead: usize = 0,
        fxRng: mathx.Rng = mathx.Rng.init(0xF1A5),
    };
    var d = Dummy{};
    const s = Strike{ .contact = v3(1, 1, 1), .dir = v3(1, 0, 0), .reaction = .light };
    _ = wounded(&d, s, .{ .hit = .{ .dmg = 5 } }, .{ .light = 1, .heavy = 2 });
    try std.testing.expectEqual(@as(usize, 3), d.fxHead);
    try std.testing.expect(d.parts[0].life < 0.1);
    for (d.parts[1..3]) |q| {
        try std.testing.expect(q.life > 4.0 * d.parts[0].life);
        try std.testing.expect(q.r1 > q.r0);
        try std.testing.expect(q.col.a < d.parts[0].col.a);
    }
}

const TrailSample = struct { a: rl.Vector3 = mathx.zero3, b: rl.Vector3 = mathx.zero3, age: f32 = mathx.LONG_AGO };

/// Metres per frame worth a sample. A DEGENERACY GUARD, not a per-weapon dial — 0.05 m at 60 fps is 3 m/s of tip and nothing slower is a swing.
pub const TRAIL_SWEEP_MIN: f32 = 0.05;

pub fn Trail(comptime N: usize) type {
    return struct {
        const Self = @This();
        s: [N]TrailSample = [_]TrailSample{.{}} ** N,
        head: usize = 0,

        /// The segment `root`..1 of `base`→`tip`, kept only if the tip actually MOVED — a stationary blade fills the ring with identical quads and the ribbon never fades.
        pub fn push(self: *Self, base: rl.Vector3, tip: rl.Vector3, prevTip: rl.Vector3, root: f32) void {
            if (mathx.lenV(mathx.subV(tip, prevTip)) <= TRAIL_SWEEP_MIN) return;
            self.head = (self.head + 1) % N;
            self.s[self.head] = .{ .a = mathx.lerpV(base, tip, root), .b = tip, .age = 0 };
        }
        pub fn age(self: *Self, dt: f32) void {
            for (&self.s) |*q| q.age = mathx.minF(q.age + dt, mathx.LONG_AGO);
        }
        pub fn reset(self: *Self) void {
            for (&self.s) |*q| q.age = mathx.LONG_AGO;
        }
        pub fn draw(self: *const Self, life: f32, col: rl.Color, peak: f32) void {
            if (self.s[self.head].age >= life) return;
            rl.gl.rlDisableBackfaceCulling();
            defer rl.gl.rlEnableBackfaceCulling();
            var i: usize = 0;
            while (i + 1 < N) : (i += 1) {
                const s0 = &self.s[(self.head + N - i) % N];
                const s1 = &self.s[(self.head + N - i - 1) % N];
                if (s0.age >= life or s1.age >= life) break;
                const f = 1.0 - 0.5 * (s0.age + s1.age) / life;
                const strip = [4]rl.Vector3{ s0.a, s0.b, s1.a, s1.b };
                rl.drawTriangleStrip3D(&strip, mathx.withAlpha(col, mathx.u8f(peak * f * f)));
            }
        }
    };
}

/// A tail shorter than this many radii collapses back to a dot, so a drag-slowed spark dies as a glowing point rather than a smear standing still.
const STREAK_MIN_RADII: f32 = 1.6;

// **A MOTE IS A TEXTURED BILLBOARD, NEVER A SOLID SPHERE** — a hard-edged Lambert ball reads as a flat circle
// however it moves, and a quad costs a tenth of it. SOFT is the glow (light, smoke, stains); GRAIN keeps a
// near-solid core for matter in flight (blood, chips, clods), which drawn fully soft reads as vapour.
var moteSoft: ?rl.Texture2D = null;
var moteGrain: ?rl.Texture2D = null;

fn moteTexture(density: f32) rl.Texture2D {
    const img = rl.genImageGradientRadial(64, 64, density, mathx.rgba(255, 255, 255, 255), mathx.rgba(255, 255, 255, 0));
    defer rl.unloadImage(img);
    const tex = rl.loadTextureFromImage(img) catch @panic("mote sprite");
    rl.setTextureFilter(tex, .bilinear);
    return tex;
}

pub fn drawParticles(pool: []const Particle) void {
    if (moteSoft == null) {
        moteSoft = moteTexture(0.12);
        moteGrain = moteTexture(0.55);
    }
    // **AN EMPTY POOL COSTS TWO BATCH FLUSHES**: changing the blend mode drains rlgl's pending batch, and
    // this is called once per BODY every frame from 42 sites. The textures stay bound above, so the one-time
    // upload still lands on the first frame rather than mid-fight.
    var any = false;
    for (pool) |*q| {
        if (q.life > 0) {
            any = true;
            break;
        }
    }
    if (!any) return;
    // Depth is TESTED, never WRITTEN: soft quads that wrote depth would punch square holes in each other.
    rl.gl.rlDisableBackfaceCulling();
    rl.gl.rlDisableDepthMask();
    drawPass(pool, false);
    rl.beginBlendMode(.additive);
    drawPass(pool, true);
    rl.endBlendMode();
    rl.gl.rlEnableDepthMask();
    rl.gl.rlEnableBackfaceCulling();
}

/// ONE predicate, so the draw and anything measuring its batching cannot disagree. Light and anything that DIFFUSES (smoke, a stain) is soft; matter in flight keeps a core.
fn wantsSoft(q: *const Particle) bool {
    return q.add or q.landed or q.r1 > q.r0;
}

fn drawPass(pool: []const Particle, add: bool) void {
    var open: u32 = 0;
    for (pool) |*q| {
        if (q.life <= 0 or q.add != add) continue;
        const frac = mathx.clampF(q.life / q.max, 0, 1);
        const rad = mathx.lerpF(q.r1, q.r0, frac);
        if (rad <= 0.0004) continue;
        const col = if (q.col1) |c1| mathx.lerpColor(q.col, c1, 1.0 - frac) else q.col;
        const a = mathx.u8f(@as(f32, @floatFromInt(col.a)) * frac);
        const soft = wantsSoft(q);
        const want = (if (soft) moteSoft else moteGrain).?.id;
        if (want != open) {
            if (open != 0) rl.gl.rlEnd();
            rl.gl.rlSetTexture(want);
            rl.gl.rlBegin(rl.gl.rl_quads);
            open = want;
        }
        rl.gl.rlColor4ub(col.r, col.g, col.b, a);
        if (q.landed) {
            const s = rad * q.splat;
            quad(
                v3(q.p.x - s, q.p.y + 0.005, q.p.z - s),
                v3(q.p.x + s, q.p.y + 0.005, q.p.z - s),
                v3(q.p.x + s, q.p.y + 0.005, q.p.z + s),
                v3(q.p.x - s, q.p.y + 0.005, q.p.z + s),
            );
            continue;
        }
        if (q.stretch > 0) {
            const sp2 = q.v.x * q.v.x + q.v.y * q.v.y + q.v.z * q.v.z;
            const min = rad * STREAK_MIN_RADII;
            if (sp2 * q.stretch * q.stretch > min * min) {
                const sp = @sqrt(sp2);
                const axis = mathx.scaleV(q.v, 1.0 / sp);
                const toCam = mathx.subV(lensAt, q.p);
                var side = mathx.crossV(axis, toCam);
                const sl = mathx.lenV(side);
                if (sl > 1e-4) {
                    side = mathx.scaleV(side, rad / sl);
                    const tail = mathx.scaleV(axis, sp * q.stretch);
                    quad(
                        v3(q.p.x - tail.x - side.x, q.p.y - tail.y - side.y, q.p.z - tail.z - side.z),
                        v3(q.p.x - side.x, q.p.y - side.y, q.p.z - side.z),
                        v3(q.p.x + side.x, q.p.y + side.y, q.p.z + side.z),
                        v3(q.p.x - tail.x + side.x, q.p.y - tail.y + side.y, q.p.z - tail.z + side.z),
                    );
                    continue;
                }
            }
        }
        quad(
            v3(q.p.x - (lensRight.x + lensUp.x) * rad, q.p.y - (lensRight.y + lensUp.y) * rad, q.p.z - (lensRight.z + lensUp.z) * rad),
            v3(q.p.x + (lensRight.x - lensUp.x) * rad, q.p.y + (lensRight.y - lensUp.y) * rad, q.p.z + (lensRight.z - lensUp.z) * rad),
            v3(q.p.x + (lensRight.x + lensUp.x) * rad, q.p.y + (lensRight.y + lensUp.y) * rad, q.p.z + (lensRight.z + lensUp.z) * rad),
            v3(q.p.x - (lensRight.x - lensUp.x) * rad, q.p.y - (lensRight.y - lensUp.y) * rad, q.p.z - (lensRight.z - lensUp.z) * rad),
        );
    }
    if (open != 0) {
        rl.gl.rlEnd();
        rl.gl.rlSetTexture(0);
    }
}

fn quad(c0: rl.Vector3, c1: rl.Vector3, c2: rl.Vector3, c3: rl.Vector3) void {
    rl.gl.rlTexCoord2f(0, 0);
    rl.gl.rlVertex3f(c0.x, c0.y, c0.z);
    rl.gl.rlTexCoord2f(1, 0);
    rl.gl.rlVertex3f(c1.x, c1.y, c1.z);
    rl.gl.rlTexCoord2f(1, 1);
    rl.gl.rlVertex3f(c2.x, c2.y, c2.z);
    rl.gl.rlTexCoord2f(0, 1);
    rl.gl.rlVertex3f(c3.x, c3.y, c3.z);
}


/// What one idle frame of a unit's ORDERS comes to, in the three locals every creature's update already
/// carries to the single `advanceGait` at its foot.
pub const PostStep = struct { moved: f32 = 0, speed: f32 = 0, yaw: ?f32 = null };

/// **THE ONE CALL A CREATURE OWES ITS POST** (`Post`'s own note), made from its IDLE branch and nowhere else.
///
/// MEASURED at the map's own foe limit: **512 bodies asked every frame is 7.3 us, 0.044% of a 16.7 ms frame**,
/// in Debug. It refuses on a distance test before it touches the RNG or the marks, and the `post` field is a
/// comptime `@hasField`, so a creature without orders pays nothing at all. There is nothing here to buy.
///
/// It fills the same `movedDist`/`moveSpeed`/`moveYaw` a chase branch fills, so the gait is advanced ONCE a
/// frame by the call already at the foot of the update — a helper that advanced the phase itself would run the
/// walk cycle at double speed on exactly the frames the creature is walking.
///
/// **AND IT REFUSES WHILE ANYBODY IS SENSED.** `sensed` is the creature's own `senseHero`, which already
/// answers `LONG_AGO` when the body is blind or going home; orders are what a unit does BEFORE it has seen
/// anybody, so a dog that keeps padding its round with the hero inside its ring is a dog that has not noticed him.
pub fn postStep(self: anytype, dt: f32, bounds: f32, speed: f32, sensed: f32, aggroR: f32) PostStep {
    const T = @TypeOf(self.*);
    if (comptime !@hasField(T, "post")) return .{};
    if (sensed <= aggroR or speed <= 0) return .{};
    const go = self.post.want(dt, self.pos) orelse return .{};
    const dir = mathx.dirXZ(self.pos, go);
    if (mathx.lenXZ(dir) < 1e-4) return .{};
    const moved = speed * dt;
    mathx.stepXZ(&self.pos, mathx.normV(dir), moved, bounds);
    return .{ .moved = moved, .speed = speed, .yaw = mathx.headingXZ(dir) };
}

/// **WHERE "BACK TO YOUR POST" MEANS, FOR A UNIT THAT HAS ORDERS.** A held body is measured back to the spot
/// it was placed on; a body under orders is ALREADY at its post, because walking is what its orders are.
///
/// Without this every roamer got three metres out and turned round: the `.hold` arm of a creature's own
/// `decide` compares against its spawn point and `LEASH_HOME_R` is 3 m, so the orders and the go-home rule
/// pulled against each other and the orders lost. The same anchor feeds `tickLeash`, or `roam_free` — the one
/// that is unleashed BY DEFINITION — trips the tether at `leashR` and is dragged back anyway.
pub fn homeFor(self: anytype) rl.Vector3 {
    const T = @TypeOf(self.*);
    if (comptime !@hasField(T, "post")) return self.home;
    return if (self.post.ai == .hold) self.home else self.pos;
}

/// **WHAT THE TETHER MEASURES FROM, WHICH IS NOT WHERE "BACK TO YOUR POST" MEANS.** `homeFor` answers "am I at
/// my post" and a body under orders always is — feeding that to `tickLeash` made `out` zero for ever, so an
/// ordered unit had NO leash at all and a patrolling guard would follow you across the whole map.
///
/// The leash asks a different question: how far have I been DRAGGED from base. A roamer's base is its post, a
/// patrol's is the leg it is walking, and `roam_free` is unleashed by definition — for that one the anchor is
/// the body itself, which is the only honest way to say "no tether".
pub fn tetherFor(self: anytype) rl.Vector3 {
    const T = @TypeOf(self.*);
    if (comptime !@hasField(T, "post")) return self.home;
    return switch (self.post.ai) {
        .hold => self.home,
        .roam => self.post.home,
        .patrol => self.post.legHere(self.home),
        .roam_free => self.pos,
    };
}

/// **WHERE THE ORDERS POINT, ASKED WITHOUT ADVANCING THEM.** `navWant` is the way a creature tells the way-
/// finder where it is going and it is `*const`, so it cannot call `Post.want`; every body under orders answered
/// with its SPAWN PIN instead. `Nav.dir` is an ABSOLUTE heading, so `markWay`'s detour round whatever stood
/// between the body and its post was then steered by while it walked to a mark somewhere else entirely.
///
/// Null while a roamer stands out its dwell, and null for a route with no legs painted on it: a body with
/// nothing to walk to has nothing to walk round.
pub fn postAim(self: anytype) ?rl.Vector3 {
    const T = @TypeOf(self.*);
    if (comptime !@hasField(T, "post")) return null;
    return switch (self.post.ai) {
        .hold => null,
        .patrol => if (self.post.nwp == 0) null else self.post.legHere(self.home),
        .roam, .roam_free => if (self.post.marked) self.post.mark else null,
    };
}

/// **THE WHOLE IDLE-FRAME CONTRACT IN ONE LINE**, for the creatures that walk on legs and feed one
/// `advanceGait` at the foot of their update. Eight of them spelled out the same five: take the step, copy the
/// three locals, turn the facing toward it. `moveSpeed` is optional because a few derive their gait speed from
/// `movedDist` alone and have no such local.
///
/// Returns whether it walked, so a caller with its own `.idle`/`.walk` states can say which one it is in.
pub fn postDrive(
    self: anytype,
    dt: f32,
    bounds: f32,
    speed: f32,
    sensed: f32,
    aggroR: f32,
    turn: f32,
    movedDist: *f32,
    moveSpeed: ?*f32,
    moveYaw: *?f32,
) bool {
    const ps = postStep(self, dt, bounds, speed, sensed, aggroR);
    const w = ps.yaw orelse return false;
    movedDist.* = ps.moved;
    if (moveSpeed) |ms| ms.* = ps.speed;
    moveYaw.* = w;
    self.facing = mathx.approachAngle(self.facing, w, turn * dt);
    return true;
}

/// **THE SAME THING FOR A BODY THAT EASES ITS SPEED** rather than stepping at it flat — four creatures share
/// an `.idle`/`.walk` pair driven off a `self.speed` that accelerates, and spelled out they were four copies of
/// twelve lines. Returns whether it is walking, so the caller picks its own state name.
pub fn postAmble(
    self: anytype,
    dt: f32,
    bounds: f32,
    speed: f32,
    accel: f32,
    sensed: f32,
    aggroR: f32,
    turn: f32,
    movedDist: *f32,
    moveSpeed: *f32,
    moveYaw: *?f32,
) bool {
    const ps = postStep(self, dt, bounds, speed, sensed, aggroR);
    const w = ps.yaw orelse {
        self.speed = mathx.approach(self.speed, 0, accel * dt);
        return false;
    };
    self.speed = mathx.approach(self.speed, ps.speed, accel * dt);
    movedDist.* = ps.moved;
    moveSpeed.* = self.speed;
    moveYaw.* = w;
    self.facing = mathx.approachAngle(self.facing, w, turn * dt);
    return true;
}

/// **THE SAME ORDERS FOR A BODY THAT DOES NOT WALK.** `postStep` takes a step for you, which is right for
/// anything on legs; a HOPPER leaps, a flyer cruises and a burrower dives, and each of those wants the PLACE
/// its orders are pointing at so it can get there in its own idiom. Same refusal: nothing while anybody is sensed.
pub fn postWant(self: anytype, dt: f32, sensed: f32, aggroR: f32) ?rl.Vector3 {
    const T = @TypeOf(self.*);
    if (comptime !@hasField(T, "post")) return null;
    if (sensed <= aggroR) return null;
    return self.post.want(dt, self.pos);
}

/// Stamps the authored orders onto a body the moment it is spawned. Duck-typed, so a creature that has not
/// grown a `post` yet costs nothing and a creature that has needs no line here.
pub fn armPost(f: anytype, h: wf.Foe, home: rl.Vector3) void {
    const T = @TypeOf(f.*);
    if (comptime !@hasField(T, "post")) return;
    f.post.arm(h.ai, home, h.route(), h.seed);
}

pub fn resetGroup(comptime T: type, out: []T, n: *usize, m: *const wf.Map, want: wf.FoeKind) void {
    n.* = 0;
    for (m.foes[0..m.nfoes]) |h| {
        if (h.kind != want or n.* >= out.len) continue;
        // ON THE GROUND: a spawn table stores x/z only, so a foe on a sculpted rise dropped at y = 0 is buried to the waist.
        const home = v3(h.x, m.heightAt(h.x, h.z), h.z);
        out[n.*] = T.spawn(home, mathx.radians(h.yaw), h.scale, h.seed);
        armPost(&out[n.*], h, home);
        n.* += 1;
    }
}

pub fn resetRoles(
    comptime T: type,
    comptime R: type,
    out: []T,
    n: *usize,
    m: *const wf.Map,
    comptime roleOf: fn (wf.FoeKind) ?R,
) void {
    n.* = 0;
    for (m.foes[0..m.nfoes]) |h| {
        const role = roleOf(h.kind) orelse continue;
        if (n.* >= out.len) continue;
        const home = v3(h.x, m.heightAt(h.x, h.z), h.z);
        out[n.*] = T.spawnAs(role, home, mathx.radians(h.yaw), h.scale, h.seed);
        armPost(&out[n.*], h, home);
        n.* += 1;
    }
}

pub fn drawGroup(foes: anytype, model: anytype, scene: ?*gfx.Scene) void {
    var lit: f32 = -1;
    var iced: f32 = -1;
    for (foes) |*f| {
        if (!f.alive()) continue;
        var thin: f32 = 1;
        if (scene) |sc| {
            const want = FLASH_GAIN * f.flashFrac();
            if (want != lit) {
                sc.setFlash(want);
                lit = want;
            }
            if (comptime @hasField(@TypeOf(f.*), "chill")) {
                const cold = FROST_GAIN * f.chill.frac();
                if (cold != iced) {
                    sc.setFrost(cold);
                    iced = cold;
                }
            }
            // …AND THE DISSOLVE IS AN ALPHA (`DEATH_SHRINK`). VIEW PASS ONLY: the depth pass has no fade uniform, and a body keeps its shadow while any of it is left.
            if (comptime @hasField(@TypeOf(f.*), "fade")) thin = 1.0 - f.fade;
            if (thin < 0.999) sc.beginFade(thin);
        }
        f.draw(model);
        if (thin < 0.999) scene.?.endFade();
    }
    if (scene) |sc| {
        if (lit > 0) sc.setFlash(0);
        if (iced > 0) sc.setFrost(0);
    }
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

pub fn soulsDropped(foes: anytype, per: u32) u32 {
    var n: u32 = 0;
    for (foes) |*f| {
        if (f.justDied) n += per;
    }
    return n;
}

pub fn soulsEach(foes: anytype) u32 {
    var n: u32 = 0;
    for (foes) |*f| {
        if (f.justDied) n += f.soulValue();
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

pub fn weaponReaches(was: [2]rl.Vector3, now: [2]rl.Vector3, hero: rl.Vector3, r: f32) bool {
    const lo = v3(hero.x, hero.y + HERO_LOW, hero.z);
    const hi = v3(hero.x, hero.y + HERO_HIGH, hero.z);
    const SWEEP = 3;
    const ALONG = 4;
    for (0..SWEEP + 1) |si| {
        const sk = @as(f32, @floatFromInt(si)) / SWEEP;
        const a0 = mathx.lerpV(was[0], now[0], sk);
        const a1 = mathx.lerpV(was[1], now[1], sk);
        for (0..ALONG + 1) |pi| {
            const p = mathx.lerpV(a0, a1, @as(f32, @floatFromInt(pi)) / ALONG);
            if (mathx.lenV(mathx.subV(p, mathx.closestOnSegV(p, lo, hi))) <= r) return true;
        }
    }
    return false;
}

pub const Blade = struct {
    active: bool = false,
    r: f32 = 0,
    a: rl.Vector3 = mathx.zero3,
    b: rl.Vector3 = mathx.zero3,
    a0: rl.Vector3 = mathx.zero3,
    b0: rl.Vector3 = mathx.zero3,
    hit: combat.Hit = .{},
    pierce: bool = false,
    cullAt: f32 = 0,
    through: bool = false,
    by: Victim = .hero,
};


/// **WHO A CREATURE IS SWINGING AT**, and `foe` is what confusion and charm ARE: nothing in the state machine
/// changes, only the point it was handed (`Threat.aim`) and where the blow is billed.
pub const Victim = enum { hero, spirit, foe };

pub const THREAT_HALFLIFE: f32 = 5.0;
/// Only the RATIO to `THREAT_PROX` matters; 1.0 so damage numbers read directly as threat.
pub const THREAT_PER_DMG: f32 = 1.0;
pub const THREAT_PROX: f32 = 26.0;
pub const THREAT_PROX_R: f32 = 9.0;
pub const SPIRIT_TAUNT: f32 = 1.55;
pub const THREAT_SWITCH: f32 = 1.30;
pub const THREAT_DWELL: f32 = 0.65;

pub const Threat = struct {
    dmgHero: f32 = 0,
    dmgSpirit: f32 = 0,
    on: Victim = .hero,
    since: f32 = mathx.LONG_AGO,
    /// Stamped each frame (`game.markThreat`) — the creature never asks what a spirit is.
    at: rl.Vector3 = mathx.zero3,
    hasSpirit: bool = false,
    /// The nearest other body, stamped like the spirit's point (`game.markThreat`).
    atFoe: rl.Vector3 = mathx.zero3,
    hasFoe: bool = false,
    /// Stored, because `tick` makes the CONFUSED choice between them and re-measuring is a second answer.
    distHero: f32 = mathx.LONG_AGO,
    distFoe: f32 = mathx.LONG_AGO,
    /// STAMPED, not looked up: `Threat` cannot see a body's `Vitals` and must not.
    charmed: bool = false,
    confused: bool = false,

    pub fn aim(self: *const Threat, heroPos: rl.Vector3) rl.Vector3 {
        if (self.on == .foe) return self.atFoe;
        if (!self.hasSpirit or self.on == .hero) return heroPos;
        return self.at;
    }

    pub fn hurtBy(self: *Threat, who: Victim, dmg: f32) void {
        const t = mathx.maxF(dmg, 0) * THREAT_PER_DMG;
        switch (who) {
            .hero => self.dmgHero += t,
            .spirit => self.dmgSpirit += t,
            // **A CHARMED BODY'S BLOWS BUY IT NOTHING.** Credited, the two lock onto each other and fight to a
            // finish while the player watches, and the clock running out leaves one aggroed onto a friend.
            .foe => {},
        }
    }

    pub fn score(dmg: f32, dist: f32, taunt: f32) f32 {
        const prox = mathx.clampF((THREAT_PROX_R - dist) / THREAT_PROX_R, 0, 1);
        return (dmg + THREAT_PROX * prox * prox) * taunt;
    }

    pub fn tick(self: *Threat, dt: f32, distHero: f32, distSpirit: f32, spirit: bool) void {
        self.hasSpirit = spirit;
        self.since += dt;
        self.distHero = distHero;
        const k = std.math.pow(f32, 0.5, dt / THREAT_HALFLIFE);
        self.dmgHero *= k;
        self.dmgSpirit *= k;
        // **THE TWO METERS OUTRANK EVERY SCORE BELOW.** Charm and confusion are not a heavier taunt that damage
        // could out-argue. CHARM PICKS THE OTHER BODY and STANDS when there is none: falling back to the hero
        // would make a charm in an empty room a free aggro.
        if (self.charmed) {
            // **AND IT NEVER FALLS BACK TO THE HERO.** It did, which made a 24 FP Bidding on a lone body buy
            // exactly nothing — the creature carried on attacking him with a charm meter running. With no
            // neighbour, `game.markThreat` stamps `atFoe` at its OWN feet: it disengages, mills about, and any
            // swing it makes is dropped by `game.spendTurnedBlows` for being aimed at itself.
            self.on = .foe;
            return;
        }
        // …AND CONFUSION SWINGS AT WHATEVER IS NEAREST (`combat.AILS`' own line). No dwell and no switch margin:
        // it is not making a decision.
        if (self.confused) {
            self.on = if (self.hasFoe and self.distFoe < distHero) .foe else .hero;
            return;
        }
        if (self.on == .foe) self.on = .hero;
        if (!spirit) {
            self.on = .hero;
            self.dmgSpirit = 0;
            return;
        }
        if (self.since < THREAT_DWELL) return;
        // …and the scores are solved BELOW the dwell, not above it: they are pure, so every creature on the field was computing a pair it threw away for the whole 0.65 s after any change of mind.
        const h = score(self.dmgHero, distHero, 1.0);
        const s = score(self.dmgSpirit, distSpirit, SPIRIT_TAUNT);
        const want: Victim = switch (self.on) {
            .hero => if (s > h * THREAT_SWITCH) .spirit else .hero,
            .spirit => if (h > s * THREAT_SWITCH) .hero else .spirit,
            // Unreachable: the two meters return above. The score below never picks `.foe`.
            .foe => .hero,
        };
        if (want != self.on) {
            self.on = want;
            self.since = 0;
        }
    }
};

pub const Blow = struct {
    hit: combat.Hit,
    from: rl.Vector3,
    on: Victim = .hero,
    /// **WHERE IT WAS AIMED, NOT WHERE IT CAME FROM.** Only a `.foe` blow reads it: `from` is the swinger.
    at: rl.Vector3 = mathx.zero3,
};

/// **A GROUP HANDS BACK ONE BLOW A FRAME AND `worseBlow` PUTS THE HERO FIRST**, so a charmed body's swing ranked
/// against his would be the one thrown away. `.foe` blows skip the ranking entirely: pushed here, drained by
/// `game.spendTurnedBlows` once every group has stepped — which is also what lets one reach another group.
/// Module scratch, drained to empty every frame.
pub const TURNED_CAP: usize = 32;
pub var turned: [TURNED_CAP]Blow = undefined;
pub var turnedN: usize = 0;

fn pushTurned(b: Blow) void {
    // DROPPED, never wrapped: wrapping bills the newest blow onto a body nobody swung at.
    if (turnedN >= TURNED_CAP) return;
    turned[turnedN] = b;
    turnedN += 1;
}

/// **THE COUNT IS NOT RESET HERE.** It was, and the returned slice aliased a buffer that `pushTurned` was then
/// free to overwrite from under the caller mid-drain. Nothing pushes during a drain today (`tryHit` does not
/// reach `worseBlow`), which is exactly the kind of "safe until somebody adds a line" this could not stay.
/// The caller drains and then calls `clearTurned`.
pub fn takeTurned() []const Blow {
    return turned[0..turnedN];
}

pub fn clearTurned() void {
    turnedN = 0;
}

/// Takes the THREAT and not just its victim: a turned blow has to say where it was aimed, and the aim point
/// lives on the same struct that chose the victim.
pub fn worseBlow(worst: *?Blow, h: combat.Hit, from: rl.Vector3, th: *const Threat) void {
    const on = th.on;
    if (on == .foe) {
        pushTurned(.{ .hit = h, .from = from, .on = on, .at = th.atFoe });
        return;
    }
    const cand = Blow{ .hit = h, .from = from, .on = on };
    const had = worst.* orelse {
        worst.* = cand;
        return;
    };
    // **THE HERO'S BLOW OUTRANKS A SPIRIT'S, AND NOT BY DAMAGE.** A group hands back ONE blow a frame, so
    // ranking two victims' blows on `raw()` weighed two different bars against each other and threw the
    // smaller number away — including the one the player was standing in front of.
    if (had.on != on) {
        if (on == .hero) worst.* = cand;
        return;
    }
    if (h.raw() > had.hit.raw()) worst.* = cand;
}

pub fn groupBlow(foes: anytype, dt: f32, hero: rl.Vector3, bounds: f32, blade: Blade) ?Blow {
    var worst: ?Blow = null;
    for (foes) |*f| {
        if (f.update(dt, f.threat.aim(hero), bounds, blade)) |h| worseBlow(&worst, h, f.pos, &f.threat);
    }
    return worst;
}

test "THREAT: hitting something takes its attention, and letting up hands it back" {
    var t = Threat{ .hasSpirit = true, .on = .spirit };
    t.since = 100;
    t.tick(1.0 / 60.0, 3.0, 3.0, true);
    try std.testing.expectEqual(Victim.spirit, t.on);
    t.hurtBy(.hero, 60);
    t.tick(1.0 / 60.0, 3.0, 3.0, true);
    try std.testing.expectEqual(Victim.hero, t.on);
    var s: f32 = 0;
    while (s < 14.0) : (s += 1.0 / 60.0) t.tick(1.0 / 60.0, 14.0, 2.0, true);
    try std.testing.expectEqual(Victim.spirit, t.on);
}

test "THREAT: standing close is its own claim, with nobody hitting anything" {
    var t = Threat{ .hasSpirit = true, .on = .spirit };
    t.since = 100;
    t.tick(1.0 / 60.0, 0.6, 12.0, true);
    try std.testing.expectEqual(Victim.hero, t.on);
}

test "THREAT DOES NOT DITHER — a near-tie holds whoever has it, whichever way round" {
    const D: f32 = 5.0;
    const inside = THREAT_SWITCH - 0.05;
    const h = Threat.score(100, D, 1.0);
    const prox = Threat.score(0, D, 1.0);
    const dS = h * inside / SPIRIT_TAUNT - prox;

    var t = Threat{ .hasSpirit = true, .on = .spirit, .dmgHero = 100, .dmgSpirit = dS };
    t.since = 100;
    t.tick(1.0 / 60.0, D, D, true);
    try std.testing.expectEqual(Victim.spirit, t.on);

    var u = Threat{ .hasSpirit = true, .on = .hero, .dmgHero = 100, .dmgSpirit = dS };
    u.since = 100;
    u.tick(1.0 / 60.0, D, D, true);
    try std.testing.expectEqual(Victim.hero, u.on);
}

test "THREAT: it will not change its mind twice in a heartbeat" {
    var t = Threat{ .hasSpirit = true, .on = .hero };
    t.since = 100;
    t.hurtBy(.spirit, 400);
    t.tick(1.0 / 60.0, 5.0, 5.0, true);
    try std.testing.expectEqual(Victim.spirit, t.on);
    t.hurtBy(.hero, 4000);
    t.tick(1.0 / 60.0, 5.0, 5.0, true);
    try std.testing.expectEqual(Victim.spirit, t.on);
    var s: f32 = 0;
    while (s < THREAT_DWELL + 0.1) : (s += 1.0 / 60.0) t.tick(1.0 / 60.0, 5.0, 5.0, true);
    try std.testing.expectEqual(Victim.hero, t.on);
}

test "WITH NO SPIRIT ON THE FIELD it is the hero, exactly as it always was" {
    var t = Threat{};
    t.hurtBy(.spirit, 500);
    t.tick(1.0 / 60.0, 30.0, 0.0, false);
    try std.testing.expectEqual(Victim.hero, t.on);
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.dmgSpirit, 1e-6);
    const hero = v3(1, 0, 2);
    try std.testing.expectEqual(hero.x, t.aim(hero).x);
}

test "ONE BLOW A FRAME, AND A SPIRIT'S MAY NOT EAT THE HERO'S" {
    const small = combat.Hit{ .dmg = 5 };
    const big = combat.Hit{ .dmg = 90 };
    var a: ?Blow = null;
    const SP = Threat{ .on = .spirit };
    const HE = Threat{ .on = .hero };
    worseBlow(&a, big, mathx.zero3, &SP);
    worseBlow(&a, small, mathx.zero3, &HE);
    try std.testing.expectEqual(Victim.hero, a.?.on);
    try std.testing.expectApproxEqAbs(small.dmg, a.?.hit.dmg, 1e-6);

    var b: ?Blow = null;
    worseBlow(&b, small, mathx.zero3, &HE);
    worseBlow(&b, big, mathx.zero3, &SP);
    try std.testing.expectEqual(Victim.hero, b.?.on);

    var c: ?Blow = null;
    worseBlow(&c, small, mathx.zero3, &HE);
    worseBlow(&c, big, mathx.zero3, &HE);
    try std.testing.expectApproxEqAbs(big.dmg, c.?.hit.dmg, 1e-6);
    var d: ?Blow = null;
    worseBlow(&d, big, mathx.zero3, &SP);
    worseBlow(&d, small, mathx.zero3, &SP);
    try std.testing.expectEqual(Victim.spirit, d.?.on);
    try std.testing.expectApproxEqAbs(big.dmg, d.?.hit.dmg, 1e-6);
}

fn blocksOf(f: anytype) u32 {
    if (comptime @hasDecl(std.meta.Child(@TypeOf(f)), "blocksTaken")) return f.blocksTaken();
    return 0;
}

pub fn pierceGroup(foes: anytype, blade: Blade) bool {
    var hit = false;
    for (foes) |*f| {
        if (!corporeal(f)) continue;
        const before = f.hits;
        const blocksBefore = blocksOf(f);
        f.tryHit(blade);
        if (f.hits == before and blocksOf(f) == blocksBefore) continue;
        hit = true;
        if (!blade.through) return true;
    }
    return hit;
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
            hitLatch.* = false;
            return null;
        }
        if (hitLatch.*) return null;
    }
    const reach = hurtR + blade.r;
    const q1 = mathx.closestOnSegV(center, blade.a, blade.b);
    const hit1 = mathx.lenV(mathx.subV(center, q1)) <= reach;
    const q0 = mathx.closestOnSegV(center, blade.a0, blade.b0);
    if (!(hit1 or mathx.lenV(mathx.subV(center, q0)) <= reach)) return null;
    if (!blade.pierce) hitLatch.* = true;
    const contact = if (hit1) q1 else q0;
    var sweep = if (blade.pierce)
        mathx.subV(blade.b, blade.a)
    else
        mathx.subV(mathx.lerpV(blade.a, blade.b, 0.7), mathx.lerpV(blade.a0, blade.b0, 0.7));
    sweep.y = 0;
    const dir = if (mathx.lenXZ(sweep) > 0.03) mathx.normV(sweep) else mathx.dirXZ(contact, center);
    // **THE CULL IS READ BEFORE THE BLOW, NEVER AFTER IT.** Asked of the HP the body walked into the swing
    // with, so it is a threshold a player can see on the bar and aim for. It kills through the ordinary path
    // (`Vitals.hit`), so the death, the reaction, the souls and the drop are the blow's own.
    if (blade.cullAt > 0 and !vit.dead and vit.hpFrac() <= blade.cullAt) {
        var out = blade.hit;
        out.dmg += vit.hp;
        return .{ .contact = contact, .dir = dir, .reaction = vit.hit(out) };
    }
    return .{ .contact = contact, .dir = dir, .reaction = vit.hit(blade.hit) };
}

test "A SHAFT IS SPENT ON THE FIRST BODY AND A LANCE GOES THROUGH THE LINE" {
    const Dummy = struct {
        pos: rl.Vector3,
        hits: u32 = 0,
        vit: combat.Vitals = combat.Vitals.initFoe(100, 999, 999),
        fn alive(_: *const @This()) bool {
            return true;
        }
        fn dying(_: *const @This()) bool {
            return false;
        }
        fn tryHit(self: *@This(), b: Blade) void {
            if (!b.active or mathx.lenV(mathx.subV(self.pos, mathx.closestOnSegV(self.pos, b.a, b.b))) > b.r) return;
            self.hits += 1;
            _ = self.vit.hit(b.hit);
        }
    };
    const line = [3]rl.Vector3{ v3(1, 1, 0), v3(2, 1, 0), v3(3, 1, 0) };
    const shaft = Blade{ .active = true, .pierce = true, .r = 0.5, .a = v3(0, 1, 0), .b = v3(9, 1, 0), .a0 = v3(0, 1, 0), .b0 = v3(9, 1, 0), .hit = .{ .dmg = 5 } };

    var spent = [3]Dummy{ .{ .pos = line[0] }, .{ .pos = line[1] }, .{ .pos = line[2] } };
    try std.testing.expect(pierceGroup(&spent, shaft));
    try std.testing.expectEqual(@as(u32, 1), spent[0].hits);
    try std.testing.expectEqual(@as(u32, 0), spent[1].hits);
    try std.testing.expectEqual(@as(u32, 0), spent[2].hits);

    var run = [3]Dummy{ .{ .pos = line[0] }, .{ .pos = line[1] }, .{ .pos = line[2] } };
    var lance = shaft;
    lance.through = true;
    try std.testing.expect(pierceGroup(&run, lance));
    for (&run) |*d| {
        try std.testing.expectEqual(@as(u32, 1), d.hits);
        try std.testing.expect(d.vit.hp < d.vit.hpMax);
    }
    var wide = [1]Dummy{.{ .pos = v3(0, 1, 40) }};
    try std.testing.expect(!pierceGroup(&wide, lance));
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
    d.down = true;
    try std.testing.expect(!corporeal(&d));
    d.gone = true;
    try std.testing.expect(!corporeal(&d));
}

test "THE SHIELD IS A DIRECTION AND EACH MOVE ITS OWN REACH" {
    const hero = v3(0, 0, 0);
    var p = Parry{ .live = false, .at = hero, .facing = 0 };
    const ahead = v3(0, 0, 3);
    try std.testing.expect(!p.catches(ahead, 4.0));
    p.live = true;
    try std.testing.expect(p.catches(ahead, 4.0));
    try std.testing.expect(!p.catches(ahead, 2.0));
    const flank = v3(3, 0, 0);
    try std.testing.expect(!p.catches(flank, 4.0));
    const edge = mathx.radians(combat.GUARD_ARC - 2.0);
    try std.testing.expect(p.catches(v3(3.0 * mathx.sinf(edge), 0, 3.0 * mathx.cosf(edge)), 4.0));
    const past = mathx.radians(combat.GUARD_ARC + 2.0);
    try std.testing.expect(!p.catches(v3(3.0 * mathx.sinf(past), 0, 3.0 * mathx.cosf(past)), 4.0));
    p.facing = std.math.pi;
    try std.testing.expect(!p.catches(ahead, 4.0));
    try std.testing.expect(p.catches(v3(0, 0, -3), 4.0));
}

test "THE LEASH: a foe drawn far from home walks back once the fight has gone quiet" {
    var l = Leash{};
    const aggro: f32 = 20.0;
    const far = leashR(aggro) + 8.0;
    const gone = aggro + 1.0; // every range here is measured from the POST
    l.noteCombat();
    l.tick(1.0 / 60.0, far, gone, aggro);
    try std.testing.expect(!l.goingHome());
    var t: f32 = 0;
    while (t < LEASH_CALM + 0.1) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, far, gone, aggro);
    try std.testing.expect(l.goingHome());
    l.tick(1.0 / 60.0, leashR(aggro) - 1.0, gone, aggro);
    try std.testing.expect(l.goingHome());
    l.tick(1.0 / 60.0, LEASH_HOME_R - 0.5, gone, aggro);
    try std.testing.expect(!l.goingHome());
    var near = Leash{};
    t = 0;
    while (t < 30.0) : (t += 1.0 / 60.0) near.tick(1.0 / 60.0, 2.0, gone, aggro);
    try std.testing.expect(!near.goingHome());
}

test "IT NEVER TURNS ROUND WHILE HE IS STILL IN ITS PATCH, and walking back in ends the walk home" {
    const aggro: f32 = 20.0;
    const far = leashR(aggro) + 8.0;
    var toe = Leash{};
    var t: f32 = 0;
    while (t < LEASH_CALM * 3.0) : (t += 1.0 / 60.0) toe.tick(1.0 / 60.0, far, 1.2, aggro);
    try std.testing.expect(!toe.goingHome());

    var l = Leash{};
    t = 0;
    while (t < LEASH_CALM + 0.1) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, far, aggro + 1.0, aggro);
    try std.testing.expect(l.goingHome());
    l.tick(1.0 / 60.0, far, aggro - 0.5, aggro);
    try std.testing.expect(!l.goingHome());
    t = 0;
    while (t < REENGAGE_HOLD - 1.0) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, far, aggro + 1.0, aggro);
    try std.testing.expect(!l.goingHome());
    while (t < REENGAGE_HOLD + 0.2) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, far, aggro + 1.0, aggro);
    try std.testing.expect(l.goingHome());
}

test "ONE PLAYER HIT ROUSES IT FROM ANY RANGE, and KEEPING AT IT breaks the leash" {
    var l = Leash{};
    try std.testing.expect(!l.roused());
    l.provoke();
    try std.testing.expect(l.roused());
    const aggro: f32 = 20.0;
    var t: f32 = 0;
    while (t < PROVOKE_ROUSE - 0.5) : (t += 1.0 / 60.0) {
        l.tick(1.0 / 60.0, 0, aggro + 1.0, aggro);
        try std.testing.expect(l.roused());
    }
    while (t < PROVOKE_ROUSE + 0.5) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, 0, aggro + 1.0, aggro);
    try std.testing.expect(!l.roused());

    var c = Leash{};
    const far = leashR(aggro) + 8.0;
    const sniped = aggro * 2.0;
    t = 0;
    while (t < LEASH_CALM + 0.1) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(c.goingHome());
    c.provoke();
    c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(!c.goingHome());
    try std.testing.expect(c.roused());
    t = 0;
    while (t < REENGAGE_HOLD + LEASH_CALM + 0.2) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(c.goingHome());
    c.provoke();
    c.provoke();
    c.provoke();
    c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(!c.goingHome());
    t = 0;
    while (t < REENGAGE_HOLD + LEASH_CALM + 1.0) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(!c.goingHome());
    t = 0;
    while (t < PROVOKE_HOLD + LEASH_CALM + 1.0) : (t += 1.0 / 60.0) c.tick(1.0 / 60.0, far, sniped, aggro);
    try std.testing.expect(c.goingHome());
    try std.testing.expect(!c.roused());
}

test "NOTHING NOTICES WHAT IT CANNOT SEE, and it keeps at him a while after it loses him" {
    const aggro: f32 = 20.0;
    var l = Leash{};
    l.blindNow();
    try std.testing.expect(l.blind());
    try std.testing.expect(sensedDist(&l, 1.0, aggro) > aggro);
    l.noteSeen();
    try std.testing.expect(!l.blind());
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), sensedDist(&l, 1.0, aggro), 1e-4);
    var t: f32 = 0;
    while (t < SIGHT_MEMORY - 0.5) : (t += 1.0 / 60.0) {
        l.tick(1.0 / 60.0, 0, 1.0, aggro);
        try std.testing.expect(!l.blind());
    }
    while (t < SIGHT_MEMORY + 0.5) : (t += 1.0 / 60.0) l.tick(1.0 / 60.0, 0, 1.0, aggro);
    try std.testing.expect(l.blind());

    // A BLOW STILL FINDS IT THROUGH COVER: being shot from somewhere it cannot see is exactly when a foe must come looking, so the rouse outranks blindness.
    var shot = Leash{};
    shot.blindNow();
    shot.provoke();
    try std.testing.expect(!shot.blind());
    try std.testing.expect(sensedDist(&shot, 40.0, aggro) <= aggro);
}

test "the leash constants say what the rule is" {
    try std.testing.expect(LEASH_HOME_R < LEASH_SLACK);
    try std.testing.expect(LEASH_SLACK > 0 and leashR(11.0) > 11.0);
    try std.testing.expect(PROVOKE_BREAK > PROVOKE_PER_HIT);
    try std.testing.expect(PROVOKE_ROUSE > LEASH_CALM * 2.0);
    try std.testing.expect(PROVOKE_HOLD > LEASH_CALM * 2.0);
    try std.testing.expect(REENGAGE_HOLD > LEASH_CALM and REENGAGE_HOLD < PROVOKE_HOLD);
    try std.testing.expect(SIGHT_MEMORY > LEASH_CALM);
}

test "A SHAFT'S blood and shove run ALONG its flight, and it never touches the swing latch" {
    var vit = combat.Vitals.init(100, 999, 999);
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
    try std.testing.expect(s.dir.x > 0.95);
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
    var vit = combat.Vitals.init(100, 8, 100);
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

test "A SWUNG WEAPON REACHES WHAT IT CROSSED, and nothing it went over" {
    const hero = v3(0, 0, 2.0);
    const level = [2]rl.Vector3{ v3(0, 1.1, 0.4), v3(0, 1.1, 2.1) };
    try std.testing.expect(weaponReaches(level, level, hero, 0.6));
    const over = [2]rl.Vector3{ v3(0, 2.9, 0.4), v3(0, 2.9, 2.1) };
    try std.testing.expect(!weaponReaches(over, over, hero, 0.6));
    const short = [2]rl.Vector3{ v3(0, 1.1, -0.6), v3(0, 1.1, 0.8) };
    try std.testing.expect(!weaponReaches(short, short, hero, 0.6));
    const a = [2]rl.Vector3{ v3(-1.4, 1.1, 2.0), v3(-0.2, 1.1, 2.0) };
    const b = [2]rl.Vector3{ v3(0.2, 1.1, 2.0), v3(1.4, 1.1, 2.0) };
    try std.testing.expect(!weaponReaches(a, a, hero, 0.15));
    try std.testing.expect(!weaponReaches(b, b, hero, 0.15));
    try std.testing.expect(weaponReaches(a, b, hero, 0.15));
}

test "THE SWING RIBBON ONLY RECORDS A BLADE THAT MOVED, and it expires" {
    var t = Trail(4){};
    const base = v3(0, 1.1, 0.2);
    t.push(base, v3(0, 1.1, 1.4), v3(0, 1.1, 1.4 + TRAIL_SWEEP_MIN * 0.5), 0.3);
    try std.testing.expect(t.s[t.head].age >= mathx.LONG_AGO);
    t.push(base, v3(0, 1.1, 1.4), v3(0.9, 1.1, 1.4), 0.3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.s[t.head].age, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2 + 0.3 * 1.2), t.s[t.head].a.z, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.4), t.s[t.head].b.z, 1e-6);
    t.age(0.4);
    try std.testing.expect(t.s[t.head].age > 0.39);
    t.reset();
    for (t.s) |s| try std.testing.expect(s.age >= mathx.LONG_AGO);
}

test "A SWING STARTS SLOW ENOUGH TO BE SEEN, then whips" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), swingCurve(0), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), swingCurve(1), 1e-5);
    // The first quarter of the window moves the limb a TWELFTH of its arc. Front-loaded it moved 58% of it, which is why a parry could only ever be timed off the sound and the clock.
    try std.testing.expect(swingCurve(0.25) < 0.10);
    try std.testing.expect(1.0 - swingCurve(0.75) > 2.0 * swingCurve(0.25));
    var prev: f32 = -1;
    var u: f32 = 0;
    while (u <= 1.0001) : (u += 1.0 / 64.0) {
        const now = swingCurve(u);
        try std.testing.expect(now >= prev);
        prev = now;
    }
    try std.testing.expect(swingCurve(0.5) < 0.5);
}

// **THIS GATE IS ABOUT COUNT, NOT COST PER MOTE** — a boss in phase two stands in a lane of twelve `GAS_PARTS`
// pools (132 each), and every one walks its whole array and appends quads for motes nobody sees.
//
// **IT IS NOT THE FRUSTUM AND MUST NEVER BECOME ONE.** `env.View` is the frustum, there is exactly one, and a
// second culler is the bug AGENTS.md names outright. This is a reach and a HEMISPHERE — nothing inside any
// field of view this game uses can fail either test, which is what makes it safe to be approximate.

var lensAt: rl.Vector3 = mathx.zero3;
var lensFwd: rl.Vector3 = v3(0, 0, 1);
var lensRight: rl.Vector3 = v3(1, 0, 0);
var lensUp: rl.Vector3 = v3(0, 1, 0);

/// Set ONCE a frame, before anything draws its motes (`game.drawScene`). The basis every billboard faces — solved here rather than per mote.
pub fn setLens(at: rl.Vector3, fwd: rl.Vector3) void {
    lensAt = at;
    lensFwd = fwd;
    var r = mathx.crossV(fwd, v3(0, 1, 0));
    const rl2 = mathx.lenV(r);
    if (rl2 > 1e-4) {
        r = mathx.scaleV(r, 1.0 / rl2);
        lensRight = r;
        lensUp = mathx.crossV(r, fwd);
    }
}

/// Past this a mote of any size is under a pixel and the haze has most of it (`gfx.HAZE_DENSITY` at 60 m is over half, and more in a storm).
pub const MOTE_REACH: f32 = 60.0;
/// …and how far off the view axis a pool has to be before it is dropped, as a COSINE. -0.45 is 117 degrees off the lens: past the corner of any frustum this game can produce.
const MOTE_BEHIND: f32 = -0.45;

/// **IS THIS WHOLE CLOUD OF MOTES WORTH DRAWING** — `at` its centre, `r` how far its motes reach from it.
pub fn motesVisible(at: rl.Vector3, r: f32) bool {
    const d = mathx.subV(at, lensAt);
    const dist2 = d.x * d.x + d.y * d.y + d.z * d.z;
    const reach = MOTE_REACH + r;
    if (dist2 > reach * reach) return false;
    // THE LENS IS IN IT, or close enough that the angle test is meaningless there. This branch keeps the gate honest.
    if (dist2 <= r * r * 2.25) return true;
    const dist = @sqrt(@max(dist2, 1e-6));
    return (d.x * lensFwd.x + d.y * lensFwd.y + d.z * lensFwd.z) / dist > MOTE_BEHIND;
}

test "THE MOTE GATE NEVER DROPS SOMETHING YOU COULD SEE" {
    setLens(mathx.zero3, v3(0, 0, 1));
    var d: f32 = 1.0;
    while (d < MOTE_REACH) : (d += 1.0) try std.testing.expect(motesVisible(v3(0, 0, d), 1.5));
    // …and off to the side as far as any frustum corner reaches — 60 degrees off axis is well past the widest half-angle this game renders at.
    var deg: f32 = 0;
    while (deg <= 90.0) : (deg += 5.0) {
        const a = mathx.radians(deg);
        try std.testing.expect(motesVisible(v3(mathx.sinf(a) * 20.0, 0, mathx.cosf(a) * 20.0), 1.5));
    }
    try std.testing.expect(!motesVisible(v3(0, 0, -20.0), 1.5));
    try std.testing.expect(!motesVisible(v3(0, 0, MOTE_REACH + 10.0), 1.5));
    try std.testing.expect(motesVisible(v3(0, 0, -1.0), 6.0));
    try std.testing.expect(motesVisible(mathx.zero3, 6.0));
}

test "EVERY CREATURE IS CLASSIFIED, and the water is only home to the two it belongs to" {
        // The hero's own waterline, read where it is written rather than copied: this file sits below `env` in the import graph.
    const envWadePin = @import("../world/env.zig").WADE_MAX;
    var waterfaring: usize = 0;
    var still: usize = 0;
    for (std.enums.values(wf.FoeKind)) |k| {
        const t = traitsOf(k);
        const lim = wadeLimit(k, 1.8);
        switch (t.gait) {
            .walking => {
                try std.testing.expect(lim > 0.2 and lim < 1.8);
                try std.testing.expect(lim < envWadePin);
            },
            .waterfaring => {
                waterfaring += 1;
                try std.testing.expect(lim > 100.0);
            },
            .flying, .rooted => {
                still += 1;
                try std.testing.expect(lim > 100.0);
            },
        }
    }
    try std.testing.expectEqual(@as(usize, 2), waterfaring);
    try std.testing.expectEqual(Gait.waterfaring, traitsOf(.toad).gait);
    try std.testing.expectEqual(Gait.waterfaring, traitsOf(.fen_lurker).gait);
    try std.testing.expectEqual(Nature.demon, traitsOf(.fen_lurker).nature);
    try std.testing.expect(still >= 4);
    std.debug.print("\n  wade: a 1.8 m walker turns back at {d:.2} m, where the hero goes to {d:.2} m\n", .{ wadeLimit(.archer, 1.8), envWadePin });
}

// **A GAS BILLS YOU THE MOMENT YOU STEP IN, AND THE CLOCK STARTS AFTER**, or clipping the edge of one costs
// nothing. A DOSE on an interval (`knight.Vigil.gasDose`) seeds the accumulator AT the interval; a BUILD per
// second (poison, acid) has no interval to seed, so entering pays `ENTRY_BOLUS` seconds of the rate up front.

/// Seconds of the rate handed over the instant you cross into a cloud. A third: enough that clipping the rim is a real cost, not so much that the entry frame is worse than a second in there.
pub const ENTRY_BOLUS: f32 = 0.34;

pub const Soak = struct {
    inside: bool = false,

    pub fn step(self: *Soak, now: bool, dt: f32, rate: f32) f32 {
        if (!now) {
            self.inside = false;
            return 0;
        }
        if (!self.inside) {
            self.inside = true;
            return rate * ENTRY_BOLUS;
        }
        return rate * dt;
    }
};

test "A CLOUD BILLS YOU ON ENTRY AND THEN ON THE CLOCK" {
    var s = Soak{};
    const dt: f32 = 1.0 / 60.0;
    const first = s.step(true, dt, 24.0);
    const after = s.step(true, dt, 24.0);
    std.debug.print("\n  soak: stepping in costs {d:.2}, each frame after costs {d:.3}\n", .{ first, after });
    try std.testing.expect(first > after * 10.0);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0 * ENTRY_BOLUS), first, 1e-4);
    try std.testing.expectEqual(@as(f32, 0), s.step(false, dt, 24.0));
    try std.testing.expect(s.step(true, dt, 24.0) > after * 10.0);
}


test "THE RING KEEPS A BURST CONTIGUOUS, so the draw does not flip sprite per mote" {
    // Emitted as RUNS, which is how every emitter here works: each `rlEnd`/`rlSetTexture`/`rlBegin` flush costs far more than the walk.
    var pool = [_]Particle{.{}} ** 84;
    var head: usize = 0;
    var rng = mathx.Rng.init(0xFEED);
    for (0..14) |_| emitPart(&pool, &head, .{ .p = v3(0, 0.1, 0), .life = 0.5, .r0 = 0.08, .r1 = 0.22, .col = DUST });
    emitPart(&pool, &head, .{ .p = v3(0, 0.6, 0), .life = 0.07, .r0 = 0.10, .r1 = 0.03, .col = HIT_FLASH, .add = true });
    for (0..2) |_| emitPart(&pool, &head, .{ .p = v3(0, 0.6, 0), .life = 0.6, .r0 = 0.05, .r1 = 0.16, .col = HIT_HAZE });
    var blood = Spray{
        .fanLo = 0.6, .fanHi = 3.8, .upLo = 0.8, .upHi = 3.6,
        .lifeLo = 0.45, .lifeHi = 0.85, .rLo = 0.028, .rHi = 0.055,
        .r1 = 0.008, .col = mathx.rgba(112, 22, 16, 235), .grav = BLOOD_GRAV, .drag = BLOOD_DRAG,
    };
    blood.stretch = BLOOD_STRETCH;
    spray(&pool, &head, &rng, v3(0, 0.6, 0), v3(1, 0, 0), 18, 6.4, 1.0, blood);
    for (0..14) |_| emitPart(&pool, &head, .{ .p = v3(0, 0.1, 0), .life = 0.5, .r0 = 0.08, .r1 = 0.22, .col = DUST });

    var flips: usize = 0;
    var live: usize = 0;
    for ([_]bool{ false, true }) |add| {
        var open: ?bool = null;
        for (&pool) |*q| {
            if (q.life <= 0 or q.add != add) continue;
            live += 1;
            const soft = wantsSoft(q);
            if (open == null or open.? != soft) flips += 1;
            open = soft;
        }
    }
    std.debug.print("\n  draw batching: {d} live motes in {d} sprite runs\n", .{ live, flips });
    // Runs, not motes: one per burst plus the pass boundary, nowhere near one per mote.
    try std.testing.expect(flips <= 6);
    try std.testing.expect(live > 55);
}

test "A SLEEP PROC PUTS A CREATURE DOWN — through `grip.downed`, which is the door twenty of them handle" {
    // The bug this pins: the hold lived in `combat.Vitals.tick` alone, and almost nothing reads `vit.stunned()`,
    // so a full sleep meter on a creature did absolutely nothing. Nineteen groups ignored it.
    var vit = combat.Vitals.initFoe(400, 999, 999);
    var root = combat.Root{};
    var chill = combat.Chill{};
    const dt: f32 = 1.0 / 60.0;

    // Half a meter is not a proc, and nothing goes down for it.
    vit.build(.sleep, combat.ailRow(.sleep).max * 0.5);
    var g = grip(&root, &chill, &vit, dt, mathx.zero3);
    try std.testing.expect(!g.downed);
    try std.testing.expect(!vit.asleep());

    // …and the frame it fills, it does.
    vit.build(.sleep, combat.ailRow(.sleep).max);
    g = grip(&root, &chill, &vit, dt, mathx.zero3);
    try std.testing.expect(g.downed);
    try std.testing.expect(vit.asleep());
    // ONE proc, not one a frame: `justProcced` is the edge, so the stagger is not re-entered every frame of it.
    g = grip(&root, &chill, &vit, dt, mathx.zero3);
    try std.testing.expect(!g.downed);
    try std.testing.expect(vit.asleep());

    // …and the clock lets go on its own.
    var t: f32 = 0;
    while (t < combat.ailRow(.sleep).dur + 0.2) : (t += dt) _ = grip(&root, &chill, &vit, dt, mathx.zero3);
    std.debug.print("\n  sleep: down on the proc, {d:.1} s of clock, then awake\n", .{combat.ailRow(.sleep).dur});
    try std.testing.expect(!vit.asleep());
}

test "DEATH WINS THE FRAME — a corpse is never also DOWNED, or the stagger stands it back up" {
    // The bug this pins: `tickAils` walks all ten meters in ONE pass, so the poison that bills the last of the
    // bar and the sleep that fills on the same frame both came back true. Every creature reads them in order,
    // so `stagger(true)` overwrote `.dead` — a body with its souls already paid, standing in `.stunheavy`,
    // never able to reach `.dead` again because `Vitals.strike` refuses a dead body.
    var vit = combat.Vitals.initFoe(400, 999, 999);
    var root = combat.Root{};
    var chill = combat.Chill{};
    const dt: f32 = 1.0 / 60.0;

    vit.build(.poison, combat.ailRow(.poison).max);
    _ = vit.tickAils(dt);
    try std.testing.expect(vit.ailOn(.poison));
    // One frame's poison from a bar this thin is the whole of it.
    vit.hp = 0.05;
    vit.build(.sleep, combat.ailRow(.sleep).max);

    const g = grip(&root, &chill, &vit, dt, mathx.zero3);
    std.debug.print("\n  one frame: killed={}, downed={} (both would resurrect it)\n", .{ g.killed, g.downed });
    try std.testing.expect(g.killed);
    try std.testing.expect(!g.downed);
    try std.testing.expect(vit.dead);

    // …and it stays undownable for as long as it is a corpse, whatever its meters go on to do.
    var t: f32 = 0;
    while (t < combat.ailRow(.sleep).dur) : (t += dt) {
        try std.testing.expect(!grip(&root, &chill, &vit, dt, mathx.zero3).downed);
    }
}

test "A CHARMED BODY WITH NOTHING TO TURN ON DOES NOT TURN BACK ON HIM" {
    // The bug this pins: `.hero` on the no-neighbour branch, which made a 24 FP Bidding on a lone foe buy
    // nothing at all — it kept attacking the player with a charm meter running.
    var t = Threat{ .charmed = true, .hasFoe = false };
    t.tick(1.0 / 60.0, 4.0, mathx.LONG_AGO, false);
    try std.testing.expectEqual(Victim.foe, t.on);

    // With a neighbour it turns on that instead, and confusion picks whichever is NEARER.
    var c = Threat{ .confused = true, .hasFoe = true, .distFoe = 2.0 };
    c.tick(1.0 / 60.0, 9.0, mathx.LONG_AGO, false);
    try std.testing.expectEqual(Victim.foe, c.on);
    c.distFoe = 12.0;
    c.tick(1.0 / 60.0, 3.0, mathx.LONG_AGO, false);
    try std.testing.expectEqual(Victim.hero, c.on);
}

test "AN IDLE AI IS OFF UNTIL A MAP SAYS OTHERWISE — every unit holds its post as it always did" {
    var p = Post{};
    try std.testing.expectEqual(Ai.hold, p.ai);
    try std.testing.expect(!p.idles());
    var t: f32 = 0;
    while (t < 30.0) : (t += 1.0 / 60.0) try std.testing.expect(p.want(1.0 / 60.0, mathx.zero3) == null);
}

test "THE JUNKYARD DOG IS LEASHED OR IT IS NOT — one never leaves its post, the other never comes back" {
    const dt = 1.0 / 60.0;
    const home = mathx.ground(10, -4);
    for ([_]Ai{ .roam, .roam_free }) |ai| {
        var p = Post{};
        p.arm(ai, home, &.{}, 0.31);
        var at = home;
        var far: f32 = 0;
        var stood: f32 = 0;
        var walked: f32 = 0;
        var t: f32 = 0;
        while (t < 600.0) : (t += dt) {
            if (p.want(dt, at)) |go| {
                const d = mathx.dirXZ(at, go);
                at = v3(at.x + d.x * 1.6 * dt, at.y, at.z + d.z * 1.6 * dt);
                walked += dt;
            } else stood += dt;
            far = mathx.maxF(far, mathx.distXZ(at, home));
        }
        std.debug.print("\n  {s}: strayed {d:.1} m from its post over 10 min, walking {d:.0}% of it\n", .{ @tagName(ai), far, walked / (walked + stood) * 100.0 });
        // BOTH actually wander — a dog that stands still is `hold` under another name.
        try std.testing.expect(far > ROAM_R * 0.5);
        // …and it STANDS between places, or it is a patrol.
        try std.testing.expect(stood > 30.0);
        if (ai == .roam) {
            // LEASHED: the post is the limit, and it cannot walk itself out one step at a time.
            try std.testing.expect(far <= ROAM_R + 1.5);
        } else {
            // UNLEASHED: ten minutes of it should have taken the thing a long way off.
            try std.testing.expect(far > ROAM_R * 3.0);
        }
    }
}

test "A PATROL WALKS ITS ROUTE AND TURNS ROUND — post out to the last point and back, never teleporting" {
    const dt = 1.0 / 60.0;
    const home = mathx.ground(0, 0);
    var p = Post{};
    p.arm(.patrol, home, &.{ .{ .x = 8, .z = 0 }, .{ .x = 8, .z = 9 } }, 0.4);
    var at = home;
    var hitHome: usize = 0;
    var hitEnd: usize = 0;
    var far: f32 = 0;
    var t: f32 = 0;
    while (t < 200.0) : (t += dt) {
        const go = p.want(dt, at) orelse continue;
        const d = mathx.dirXZ(at, go);
        at = v3(at.x + d.x * 2.0 * dt, at.y, at.z + d.z * 2.0 * dt);
        far = mathx.maxF(far, mathx.distXZ(at, home));
        if (mathx.distXZ(at, home) < 1.2) hitHome += 1;
        if (mathx.distXZ(at, mathx.ground(8, 9)) < 1.2) hitEnd += 1;
    }
    std.debug.print("  patrol: reached its far point and its post again, {d} and {d} frames of it; furthest {d:.1} m\n", .{ hitEnd, hitHome, far });
    // IT WALKS THE WHOLE ROUTE, both ways, more than once.
    try std.testing.expect(hitEnd > 0 and hitHome > 0);
    // …and never further than the route itself: a patrol that overshoots is a roamer.
    try std.testing.expect(far < mathx.distXZ(home, mathx.ground(8, 9)) + 1.5);

    // A ROUTE WITH NOTHING PAINTED ON IT IS NOT A CREATURE SPINNING — a half-finished edit just stands.
    var empty = Post{};
    empty.arm(.patrol, home, &.{}, 0.4);
    try std.testing.expect(empty.want(dt, home) == null);

    // AND THE ROUTE IS CAPPED WHERE THE FORMAT CAPS IT: a longer one is truncated, never overrun.
    var many: [MAX_WP + 4]Wp = undefined;
    for (&many, 0..) |*w, i| w.* = .{ .x = @floatFromInt(i), .z = 0 };
    var big = Post{};
    big.arm(.patrol, home, &many, 0.4);
    try std.testing.expectEqual(@as(u8, MAX_WP), big.nwp);
}

test "WHAT ORDERS COST A FRAME — the idle-frame walk, at the map's own foe limit" {
    // **THE ROUND RUNS ON EVERY IDLE FRAME OF EVERY BODY**, so its cost is the one thing about this feature
    // that scales with the map. `postStep` refuses on a distance test before it touches the RNG or the marks.
    var posts: [512]Post = undefined;
    const home = mathx.ground(0, 0);
    for (&posts, 0..) |*p, i| p.arm(if (i % 2 == 0) .roam else .patrol, home, &.{ .{ .x = 9, .z = 0 }, .{ .x = 9, .z = 9 } }, @as(f32, @floatFromInt(i % 97)) / 97.0);
    const dt: f32 = 1.0 / 60.0;
    var timer = try std.time.Timer.start();
    const FRAMES = 600;
    var walked: usize = 0;
    for (0..FRAMES) |_| {
        for (&posts) |*p| {
            if (p.want(dt, home) != null) walked += 1;
        }
    }
    const us = @as(f64, @floatFromInt(timer.read())) / 1000.0 / @as(f64, @floatFromInt(FRAMES));
    std.debug.print("\n  orders: {d} bodies asked every frame costs {d:.1} us — {d:.3}% of a 16.7 ms frame\n", .{ posts.len, us, 100.0 * us / 16700.0 });
    // The shape is what matters: LINEAR in the bodies, no allocation, and one distance test on the frame a
    // body is standing still. `MAX_FOES` of them is the worst a map can ask for.
    try std.testing.expect(walked > 0);
}
