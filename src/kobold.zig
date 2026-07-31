const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const combat = @import("combat.zig");
const heromod = @import("hero.zig");
const foe = @import("foe.zig");
const wf = @import("worldfmt.zig");
const sfx = @import("audio.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// ── THE KOBOLDS ─────────────────────────────────────────────────────────────────────────
// A WARBAND, not a fourth monster: three ROLES of one creature, and the whole point of them is that
// they are only dangerous together. Doglike humanoids — muzzle, pricked ears, a fur ruff, a tail —
// somewhat shorter than a man (SCALE), so a knot of them reads as a pack of scavengers rather than as
// small people.
//
//   BERSERKER — two axes and no plan. A FLURRY of wild alternating chops, then a long heaving
//               RECOVERY that is the entire opening. Low poise: he is interruptible on purpose,
//               because a foe that swings this much has to be punishable.
//   PRIEST    — a staff, and no attack at all. It hangs at the BACK of the band and pours HP into
//               whoever is hurt worst, off a long cooldown, through a readable cast you can break.
//               It is the priority target, and the fight teaches you that by itself.
//   SLINGER   — a whirled sling at range, and TEETH if you close. It has no third answer, so
//               closing is correct and staying at range is not.
//
// ONE FILE AND ONE STRUCT, because they are one creature: the body, the gait, the fur, the death and
// the reactions are shared and only the KIT and the state machine differ. Three files would be three
// copies of a doglike skull. (AGENTS.md's file rule: minimise the tokens it takes to make a correct
// change, which favours cohesion — a change to "how a kobold looks" is one place.)
//
// FOUNDED ON THE SHARED HUMANOID SCAFFOLD (`hero.N` / `hero.PARENT` / `hero.restHumanoid`) and it
// walks on `hero.advanceGait` + `hero.legChain` like every other biped here — AGENTS.md's humanoid
// rule. Nothing about the locomotion is authored in this file; what is authored is the upper body.

// ── palette ── pre-gamma dark (the scene shader gammas output, so these lift a lot). A scavenger's
// colours: dust-brown fur going grey at the muzzle, cheap iron, filthy hide.
// AUTHORED NEARLY BLACK, and this is the law I broke on the first pass (AGENTS.md: "A BIG SMOOTH MASS
// NEEDS A NEARLY-BLACK ALBEDO"). The scene shader's hot key (*1.72) plus the gamma lift turns any
// mid-dark value PALE wherever a large face takes the sun square on — and a kobold is nothing but large
// smooth faces. At 84/62/40 the pelt rendered as pale pine and three of them read as wooden mannequins
// rather than as animals. Roughly halved, and the SPREAD between the three widened, because form only
// reads if the shadowed side is genuinely darker than the lit one.
// …and then back UP a third, because the law has a scope I over-applied a second time. "Nearly black"
// is for a BIG SMOOTH mass — a cliff face, a keep wall — where one huge face takes the sun square on. A
// kobold is small and its surface is already broken to pieces by the tufts, so it never gets that flat
// hot face; halved outright it went from pale pine to grey-brown ROCK and lost the dust-brown warmth
// that makes it fur. 60/43/26 is the landing point between the two renders.
const FUR = rgba(60, 43, 26, 255); // dust-brown pelt
const FUR_DK = rgba(30, 21, 13, 255); // …its shadowed underside and the tufts' roots
const FUR_LT = rgba(94, 71, 45, 255); // …sun-bleached along the back and shoulders
const MUZZLE = rgba(38, 28, 20, 255); // the darker mask over the snout
const NOSE = rgba(18, 15, 13, 255);
const EAR_IN = rgba(96, 60, 52, 255); // the pink-grey inside of a pricked ear
const EYE = rgba(168, 128, 44, 200); // amber, slightly self-lit so it catches in shade
const TOOTH = rgba(196, 188, 166, 255);
const HIDE = rgba(48, 36, 26, 255); // scraps of cured hide — belt, harness, wraps
const HIDE_LT = rgba(66, 50, 36, 255);
const IRON = rgba(72, 74, 78, 255); // cheap, unpolished iron
const IRON_LT = rgba(104, 108, 114, 255);
const HAFT = rgba(46, 33, 21, 255); // dark wood
const CLAW = rgba(150, 142, 122, 255);
/// The priest's fetish colours — bone, and the grace-adjacent gold its magic borrows.
const BONE_CHARM = rgba(140, 130, 106, 255);
const HEAL_GLOW = rgba(196, 156, 60, 150); // self-lit: the cast's tell has to read from across a plaza
const SLING_CORD = rgba(92, 78, 58, 255);
const STONE_COL = rgba(96, 92, 86, 255);

// ── rig ── the SHARED 18-bone humanoid scaffold; only the names of two slots are ours.
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
const KIT = heromod.HELD; // the right hand's weapon: an axe, a staff, or a sling

const parent = heromod.PARENT;

const H: f32 = heromod.H;
// The LEGS and ARMS take the hero's fractions from the shared source, like the archer's: `legChain`'s
// strafe geometry is measured off the leg pair, so a local copy that drifted would make a kobold's
// planted feet skate.
const SEG_THIGH = heromod.SEG_THIGH;
const SEG_SHANK = heromod.SEG_SHANK;
const SEG_UPARM = heromod.SEG_UPARM;
const SEG_FOREARM = heromod.SEG_FOREARM;

/// SOMEWHAT SHORTER THAN A MAN (owner's brief) — not a child's height, which would read as comic, and
/// not so close to the hero's that the difference stops being a silhouette. At 0.82 a kobold's crown
/// lands about at the Tarnished's collarbone, which is where "I can see over its head" happens.
pub const SCALE: f32 = 0.82;
/// …and NARROWER ACROSS THE SHOULDERS than a man, which is most of what makes it read as a different
/// animal rather than as a scaled-down person. The hips stay nearly the hero's — a scavenger is
/// hollow-chested, not narrow-hipped.
const HIP_HALF = 0.086;
const SHOULDER_HALF = 0.132;

fn restPositions() [N]rl.Vector3 {
    return heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);
}

// matrix shorthand (shared mathx TRS — mul(a,b) applies a FIRST then b)
const rx = mathx.rx;
const ry = mathx.ry;
const rz = mathx.rz;
const tr = mathx.tr;
const mul = mathx.mul;
const mul3 = mathx.mul3;
const scaleM = mathx.scaleM;

// world(child) = animRot ∘ translate(offset) ∘ world(parent) — through `hero.setJoint`, the ONE
// statement of the "MatrixMultiply(a, b) applies a FIRST" rule. All this adds is our parent table.
fn setLocal(wx: *[N]rl.Matrix, i: usize, rest: [N]rl.Vector3, animRot: rl.Matrix) void {
    heromod.setJoint(wx, &rest, i, @intCast(parent[i]), animRot);
}

/// The kobold's PAW footprint, measured off `footMesh` below: the pad spans z −0.035·H…+0.175·H and
/// x ±0.044·H, its underside on the ankle plane. A longer foot than the hero's boot for its height —
/// it is a dog's foot, and the toes are most of its length.
const solePatches = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.035 * H, .toe = 0.175 * H, .halfW = 0.044 * H, .drop = 0.036 * H },
    .{ .bone = ANKR, .heel = 0.035 * H, .toe = 0.175 * H, .halfW = 0.044 * H, .drop = 0.036 * H },
};

const A_BOB = heromod.A_BOB; // the hero's own pelvis amplitude — a shared walk owes a shared bob
const A_PROT = 4.6; // deg of pelvic transverse rotation: a scavenger's walk is loose in the hips

// ── ROLES ───────────────────────────────────────────────────────────────────────────────
/// Which kobold this is. The tags match `wf.FoeKind`'s three kobold entries so the editor's unit
/// brushes, the map's `foe:` records and this enum cannot drift apart.
pub const Role = enum { berserker, priest, slinger };

/// Per-role tuning, as ONE ROW each — the same "a kind is one row" rule `props.INFO` and the sound
/// BANK follow, and for the same reason: three roles' numbers spread across three switch statements
/// is three places to forget one.
const Spec = struct {
    hp: f32,
    poise: f32,
    stance: f32,
    /// Ground speed, as a fraction of the hero's walk. The berserker is the quick one.
    speed: f32,
    bodyR: f32,
    hurtR: f32,
    /// RUNES. The priest is worth the most: killing it first is the correct play, and the payout
    /// should agree with the lesson.
    runes: u32,
    /// How close it wants to be. The berserker closes to nothing, the slinger holds a band, the
    /// priest hangs at the back.
    wantMin: f32,
    wantMax: f32,
};

const SPEC = [_]Spec{
    // berserker — fast, TOUGH IN HP AND GLASS IN POISE, and that pairing is the whole creature: he
    // takes a lot of killing but the flurry can always be stopped. (This said 13 and the test caught
    // it: 13 is ABOVE the slinger's, i.e. the hardest of the three to interrupt, which is the exact
    // opposite of what he is for.)
    .{ .hp = 76, .poise = 11, .stance = 34, .speed = 1.22, .bodyR = 0.34, .hurtR = 0.52, .runes = 120, .wantMin = 0.0, .wantMax = 1.5 },
    // priest — frail, and the only one with no attack at all. Its whole defence is the band.
    .{ .hp = 54, .poise = 10, .stance = 24, .speed = 0.86, .bodyR = 0.32, .hurtR = 0.50, .runes = 210, .wantMin = 7.5, .wantMax = 12.0 },
    // slinger — middling everything, dangerous only at the range it chooses.
    .{ .hp = 62, .poise = 12, .stance = 28, .speed = 1.0, .bodyR = 0.32, .hurtR = 0.50, .runes = 140, .wantMin = 5.0, .wantMax = 10.5 },
};

fn spec(r: Role) *const Spec {
    return &SPEC[@intFromEnum(r)];
}

comptime {
    // The spec table IS the role enum, in order. A role added without a row would silently take the
    // last one's numbers.
    std.debug.assert(SPEC.len == @typeInfo(Role).@"enum".fields.len);
    // …and the roles ARE the map's kobold foe kinds, by name, so `wf.FoeKind` → `Role` is an ordinal
    // shift and not a hand-written switch that can disagree.
    for (@typeInfo(Role).@"enum".fields, 0..) |f, i| {
        const fk: wf.FoeKind = @enumFromInt(@intFromEnum(wf.FoeKind.berserker) + i);
        std.debug.assert(std.mem.eql(u8, f.name, @tagName(fk)));
    }
}

/// A map foe kind → the role it posts, or null if it is not a kobold at all. The ordinal shift the
/// comptime block above pins.
pub fn roleOf(k: wf.FoeKind) ?Role {
    const lo = @intFromEnum(wf.FoeKind.berserker);
    const i = @intFromEnum(k);
    if (i < lo or i >= lo + SPEC.len) return null;
    return @enumFromInt(i - lo);
}

const AGGRO_R = 16.0; // it notices you from here
const TURN_RATE = 5.2; // rad/s — quicker than the ogre, slower than the hero
const WALK_SPEED = heromod.WALK_SPEED;
const DEATH_DUR = 1.0; // yelp and fold
const DISS_DUR = 0.85; // …then dissipate into grace motes
const FLASH_DUR = foe.FLASH_DUR;
const SHOVE_DECAY = 8.0;

// ── the berserker's FLURRY ──────────────────────────────────────────────────────────────
// The shape is the whole character: a burst of chops far too fast to trade with, then a recovery far
// too long to get away with. Both halves have to be legible — the flurry so you back off, the heave
// so you come back in.
const ZERK_SWINGS_LO: u32 = 3;
const ZERK_SWINGS_HI: u32 = 5;
const ZERK_CHOP = 0.42; // one chop, start to finish
const ZERK_HIT_A = 0.34; // …and the fraction of it the axe is live for
const ZERK_HIT_B = 0.62;
const ZERK_STEP = 0.42; // ground he carries himself forward per chop
const ZERK_RECOVER = 1.75; // THE OPENING: doubled over, heaving, wide open
const ZERK_REACH = 1.9;
pub const ZERK_HIT = combat.Hit{ .dmg = 11, .poise = 9 };

// ── the priest's CAST ───────────────────────────────────────────────────────────────────
// Owner's call: an INTERRUPTIBLE cast with a tell. So the heal is a WINDOW, not a fact — the staff
// comes up, the light gathers, and a blade through it costs the priest the cooldown as well as the
// heal. That is what makes rushing the back line the answer instead of a suggestion.
const CAST_DUR = 1.25; // the tell, and it is deliberately long enough to cross a plaza for
const CAST_CD = 9.0; // …and it may not do it often
const HEAL_AMT = 30.0; // …but when it lands it is worth having stopped
const HEAL_SLACK = 4.0; // don't cast for a scratch
const HEAL_RANGE = 14.0; // how far its blessing reaches

// ── the slinger's SLING and its TEETH ───────────────────────────────────────────────────
const WHIRL_DUR = 0.70; // the sling goes round — the tell
const SLING_CD = 1.9;
const BITE_R = 1.45; // inside this it stops slinging and snaps at you
const BITE_DUR = 0.52;
const BITE_HIT_A = 0.30;
const BITE_HIT_B = 0.52;
const BITE_CD = 1.15;
pub const BITE_HIT = combat.Hit{ .dmg = 9, .poise = 7 };
/// The stone leaves slower and drops harder than an arrow — it is a lobbed pebble, not a shaft, and
/// the arc is what makes it dodgeable by walking rather than by rolling.
pub const STONE_SPEED = 11.0;
pub const STONE_HIT = combat.Hit{ .dmg = 10, .poise = 8 };

const REPOSITION_DUR = 1.3;

/// HOW MUCH OF A FOLD THE PELVIS IS ALLOWED TO TAKE (`ogre.PELVIS_SHARE`'s idea, same law): almost none.
/// A body doubling over hinges at the WAIST over feet that stay planted, so the fold belongs to
/// SPINE/CHEST and the pelvis stays nearly upright. Route it through the root instead and the legs
/// rotate with it — the whole figure tips like a felled post and nothing reads as folding at all, which
/// is exactly what the berserker's heave did on its first render.
const PELVIS_SHARE: f32 = 0.12;

// ── FX ──────────────────────────────────────────────────────────────────────────────────
const NPART = 22; // a modest per-kobold pool: a warband is up to 72 of these
const BLOOD = rgba(104, 26, 22, 200); // a kobold bleeds thin and dark

// ── STATE ───────────────────────────────────────────────────────────────────────────────
// One machine, and which arms of it are reachable is the ROLE's business (`decide`). A priest never
// enters `.chop`; a berserker never enters `.cast`.
const State = enum {
    idle,
    approach, // walking toward its wanted range
    reposition, // …or away from it
    chop, // berserker: one swing of the flurry
    heave, // berserker: the long recovery
    cast, // priest: the heal tell
    whirl, // slinger: the sling goes round
    bite, // slinger: teeth
    stunlight,
    stunheavy,
    dead,
};

/// What the band has to do about this kobold THIS FRAME. Returned by `update` rather than acted on
/// inside it, because both of these need something the creature deliberately cannot see: the arrow
/// pool belongs to game.zig, and choosing WHO to heal belongs to the Warband (see `Warband.update`).
pub const Act = union(enum) {
    none: void,
    /// A stone left the sling, from this point.
    sling: rl.Vector3,
    /// A cast completed. The band applies it — the priest owns the animation, not the targeting.
    healed: void,
};

pub const Kobold = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,
    scale: f32 = 1.0,
    seed: f32 = 0,
    role: Role = .berserker,

    state: State = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    /// The flurry's remaining chops, and which hand the next one comes from. Alternating is what
    /// makes it read as WILD rather than as a repeated animation.
    chopsLeft: u32 = 0,
    chopLeftHand: bool = false,
    castCd: f32 = 0,
    slingCd: f32 = 0,
    biteCd: f32 = 0,
    /// Set by the Warband before `update`: is there anybody worth healing in reach? The priest may
    /// not go looking itself — it has no way to see its friends and should not grow one.
    healWanted: bool = false,
    /// 0..1 how hot the cast's glow is (the tell). Read by the draw for the staff light.
    castGlow: f32 = 0,
    /// Sling whirl phase, in turns — the pouch really does go round the head.
    whirlPh: f32 = 0,
    moveDir: rl.Vector3 = mathx.zero3,

    vit: combat.Vitals = combat.Vitals.initFoe(76, 13, 34),
    hits: u32 = 0,
    justDied: bool = false,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    fade: f32 = 0,
    gone: bool = false,
    /// A live hurt window's own latch, so one chop or one bite lands once however many frames it is
    /// open for. Mirrors `foe.strike`'s latch on the other side of the exchange.
    dealt: bool = false,

    // the shared humanoid gait state (hero.advanceGait drives all five)
    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    parts: [NPART]foe.Particle = [_]foe.Particle{.{}} ** NPART,
    head: usize = 0,
    fxRng: mathx.Rng = mathx.Rng.init(1),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Kobold {
        return spawnAs(.berserker, home, faceYaw, scale, seed);
    }

    /// The real constructor. `resetGroup`'s `T.spawn` signature has no room for a role, and the
    /// Warband holds all three mixed, so the band calls this directly and `spawn` above exists only
    /// to satisfy the shared contract.
    pub fn spawnAs(role: Role, home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Kobold {
        const s = spec(role);
        var k = Kobold{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .role = role,
            .vit = combat.Vitals.initFoe(s.hp, s.poise, s.stance),
        };
        k.rest = restPositions();
        // @abs first — @intFromFloat into an unsigned type traps on a negative seed (see frog.zig).
        k.fxRng = mathx.Rng.init(@as(u64, @intFromFloat(@abs(seed) * 96337.0)) +% 11);
        k.slingCd = 0.3 + seed; // stagger the volley so a pack doesn't loose in lockstep
        k.castCd = seed * 2.0;
        k.whirlPh = seed;
        k.pose();
        return k;
    }

    // ── the foe contract ────────────────────────────────────────────────────────────────
    // Every height is measured from `pos.y` — THE GROUND UNDER IT, never y = 0 — or on a hillside a
    // reticle, an HP bar and a hurt sphere all hang in the air beside the body (AGENTS.md).
    pub fn alive(self: *const Kobold) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Kobold) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Kobold) bool {
        return self.state == .stunlight or self.state == .stunheavy or self.state == .dead;
    }
    /// Nothing a kobold does leaves the ground — it has no leap. Answered honestly rather than left
    /// out, because collision and the terrain gate both ask.
    pub fn airborne(self: *const Kobold) bool {
        _ = self;
        return false;
    }
    pub fn bodyR(self: *const Kobold) f32 {
        return spec(self.role).bodyR * self.scale;
    }
    pub fn hurtRadius(self: *const Kobold) f32 {
        return spec(self.role).hurtR * self.scale;
    }
    pub fn centerWorld(self: *const Kobold) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + 0.80 * H * self.scale, self.pos.z);
    }
    pub fn lockPoint(self: *const Kobold) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + 0.78 * H * self.scale, self.pos.z);
    }
    pub fn topWorld(self: *const Kobold) rl.Vector3 {
        return v3(self.pos.x, self.pos.y + 1.06 * H * self.scale, self.pos.z);
    }
    pub fn flashFrac(self: *const Kobold) f32 {
        return foe.flashFrac(self.flash);
    }
    pub fn runeValue(self: *const Kobold) u32 {
        return spec(self.role).runes;
    }

    fn faceToward(self: *Kobold, target: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, target, TURN_RATE, dt);
    }

    /// Where a stone leaves the sling: the pouch, out at arm's length past the head.
    pub fn slingPoint(self: *const Kobold) rl.Vector3 {
        return rl.math.vector3Transform(v3(0, 0, SLING_LEN * H), self.xf[KIT]);
    }

    /// Is a hurt window open right now, and has it not already landed? The attacker's side of the
    /// one-hit latch — `game.zig` asks this and applies the blow.
    pub fn hurtOpen(self: *const Kobold) bool {
        if (self.dealt) return false;
        const u = switch (self.state) {
            .chop => self.t / ZERK_CHOP,
            .bite => self.t / BITE_DUR,
            else => return false,
        };
        return switch (self.state) {
            .chop => u >= ZERK_HIT_A and u < ZERK_HIT_B,
            .bite => u >= BITE_HIT_A and u < BITE_HIT_B,
            else => false,
        };
    }

    /// …and the blow it deals, plus how far it reaches. One place, so the shape the player learns and
    /// the damage they take cannot disagree.
    pub fn hurtReach(self: *const Kobold) f32 {
        return switch (self.state) {
            .chop => ZERK_REACH * self.scale + foe.HERO_REACH,
            .bite => BITE_R * self.scale + foe.HERO_REACH,
            else => 0,
        };
    }
    pub fn hurtBlow(self: *const Kobold) combat.Hit {
        return switch (self.state) {
            .chop => ZERK_HIT,
            else => BITE_HIT,
        };
    }
    /// Mark this window spent (the caller landed it) — the latch that stops one swing hitting twice.
    pub fn markDealt(self: *Kobold) void {
        self.dealt = true;
    }

    // ── per-frame ───────────────────────────────────────────────────────────────────────
    /// Returns what the BAND must do about this frame (a stone loosed, a heal completed). The hero's
    /// blade is applied at the END via `tryHit`, so a kill sets `justDied` for this frame's beat only
    /// — the top-of-update reset is what makes it a true one-frame flag.
    pub fn update(self: *Kobold, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) Act {
        if (self.gone) return .none;
        self.justDied = false;
        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.flash = mathx.maxF(0, self.flash - dt);
        self.castCd = mathx.maxF(0, self.castCd - dt);
        self.slingCd = mathx.maxF(0, self.slingCd - dt);
        self.biteCd = mathx.maxF(0, self.biteCd - dt);
        var act: Act = .none;
        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;

        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);
        foe.tickParticles(&self.parts, dt, self.pos.y);

        const d = mathx.distXZ(self.pos, hero);
        switch (self.state) {
            .idle => {
                self.faceToward(hero, dt);
                if (self.t >= 0.25) self.decide(d);
            },
            .approach, .reposition => {
                self.faceToward(hero, dt);
                const moved = WALK_SPEED * spec(self.role).speed * dt;
                mathx.stepXZ(&self.pos, self.moveDir, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(self.moveDir);
                if (self.t >= REPOSITION_DUR) self.decide(d);
            },
            // ── BERSERKER ──
            .chop => {
                // He carries himself into it — a wild chop is a lunge with an axe on the end, and a
                // stationary flurry reads as a windmill you can stand next to.
                self.faceToward(hero, dt * 0.35); // barely tracking: committed, and that is the counter
                const u = self.t / ZERK_CHOP;
                if (u >= ZERK_HIT_A and u < ZERK_HIT_B) {
                    mathx.stepXZ(&self.pos, mathx.headingDir(self.facing), ZERK_STEP / ((ZERK_HIT_B - ZERK_HIT_A) * ZERK_CHOP) * dt, bounds);
                }
                if (self.t >= ZERK_CHOP) {
                    if (self.chopsLeft > 0) {
                        self.chopsLeft -= 1;
                        self.chopLeftHand = !self.chopLeftHand;
                        self.enter(.chop);
                        sfx.world(.kobold_chop, self.pos);
                    } else self.enter(.heave);
                }
            },
            .heave => {
                // THE OPENING. Doubled over, gasping, not tracking you at all.
                if (self.t >= ZERK_RECOVER) self.decide(d);
            },
            // ── PRIEST ──
            .cast => {
                self.faceToward(hero, dt * 0.2);
                self.castGlow = mathx.smoothstep(0, 0.85, self.t / CAST_DUR);
                self.emitCastMotes(dt);
                if (self.t >= CAST_DUR) {
                    act = .healed; // the band applies it — see Warband.update
                    self.castCd = CAST_CD;
                    self.castGlow = 0;
                    self.decide(d);
                }
            },
            // ── SLINGER ──
            .whirl => {
                self.faceToward(hero, dt);
                self.whirlPh += dt * 3.4; // the pouch really goes round: the tell is the motion
                if (self.t >= WHIRL_DUR) {
                    act = .{ .sling = self.slingPoint() };
                    self.slingCd = SLING_CD;
                    sfx.world(.kobold_sling, self.pos);
                    self.decide(d);
                }
            },
            .bite => {
                self.faceToward(hero, dt * 0.8);
                if (self.t >= BITE_DUR) {
                    self.biteCd = BITE_CD;
                    self.decide(d);
                }
            },
            .stunlight => if (self.t >= combat.FOE_LIGHT_STUN_DUR) self.enter(.idle),
            .stunheavy => if (self.t >= combat.FOE_HEAVY_STUN_DUR) self.enter(.idle),
            .dead => {
                if (self.t >= DEATH_DUR) {
                    self.fade = mathx.smoothstep(DEATH_DUR, DEATH_DUR + DISS_DUR, self.t);
                    self.emitMotes(dt);
                    if (self.t >= DEATH_DUR + DISS_DUR) self.gone = true;
                }
            },
        }

        // The SHARED humanoid gait. `movedDist / self.scale` because `legChain`'s geometry is
        // RIG-LOCAL (it divides the measured hip height by the root matrix's own scale), so a
        // scale≠1 kobold fed world distance would skate — the same correction archer and ogre make.
        const gaitSpeed: f32 = if (movedDist > 0) WALK_SPEED * spec(self.role).speed else 0;
        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, gaitSpeed, moveYaw, self.facing);
        self.pose();
        self.tryHit(blade);
        return act;
    }

    fn enter(self: *Kobold, s: State) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
        if (s != .cast) self.castGlow = 0;
        switch (s) {
            .cast => sfx.world(.kobold_cast, self.pos),
            .whirl => sfx.world(.kobold_whirl, self.pos),
            .bite => sfx.world(.kobold_bite, self.pos),
            .heave => sfx.world(.kobold_heave, self.pos),
            else => {},
        }
    }

    /// PICK THE NEXT ACTION — and this is where the three roles actually part company. Everything
    /// above is one creature; the differences live in these three arms.
    fn decide(self: *Kobold, d: f32) void {
        if (d > AGGRO_R) {
            // Out of range: drift home rather than freeze mid-field.
            const back = mathx.distXZ(self.pos, self.home);
            if (back > 1.5) {
                self.moveDir = mathx.dirXZ(self.pos, self.home);
                return self.enter(.reposition);
            }
            return self.enter(.idle);
        }
        const s = spec(self.role);
        switch (self.role) {
            .berserker => {
                if (d <= ZERK_REACH * self.scale + foe.HERO_REACH) {
                    // Commit to a whole flurry up front, so its LENGTH is decided before the first
                    // swing and the player can read the burst rather than guessing each time.
                    self.chopsLeft = ZERK_SWINGS_LO + @as(u32, @intCast(self.fxRng.intn(@intCast(ZERK_SWINGS_HI - ZERK_SWINGS_LO + 1))));
                    self.chopLeftHand = false;
                    self.enter(.chop);
                    sfx.world(.kobold_chop, self.pos);
                    return;
                }
                self.moveDir = mathx.dirXZ(self.pos, heroAt(self));
                return self.enter(.approach);
            },
            .priest => {
                // THE BACK LINE. It heals when it can and otherwise only manages its distance — it
                // has no attack at all, which is what makes reaching it the whole point.
                if (self.healWanted and self.castCd <= 0) return self.enter(.cast);
                if (d < s.wantMin) {
                    self.moveDir = self.awayDir();
                    return self.enter(.reposition);
                }
                if (d > s.wantMax) {
                    self.moveDir = mathx.scaleV(self.awayDir(), -1);
                    return self.enter(.approach);
                }
                return self.enter(.idle);
            },
            .slinger => {
                if (d <= BITE_R * self.scale + foe.HERO_REACH and self.biteCd <= 0) return self.enter(.bite);
                if (d < s.wantMin) {
                    self.moveDir = self.awayDir();
                    return self.enter(.reposition);
                }
                if (d > s.wantMax) {
                    self.moveDir = mathx.scaleV(self.awayDir(), -1);
                    return self.enter(.approach);
                }
                if (self.slingCd <= 0) return self.enter(.whirl);
                return self.enter(.idle);
            },
        }
    }

    /// The hero's position, recovered from the facing this creature has just been turning toward. The
    /// state machine gets `d` but not the point, and `decide` needs a direction — rather than thread
    /// the hero through, use the facing, which IS pointed at him by every arm that calls this.
    fn heroAt(self: *const Kobold) rl.Vector3 {
        const f = mathx.headingDir(self.facing);
        return v3(self.pos.x + f.x * 4.0, self.pos.y, self.pos.z + f.z * 4.0);
    }

    /// Straight away from the hero, with a little seeded skew so a pack does not retreat as one body.
    fn awayDir(self: *const Kobold) rl.Vector3 {
        return mathx.headingDir(self.facing + std.math.pi + (self.seed - 0.5) * 0.8);
    }

    // ── FX ──────────────────────────────────────────────────────────────────────────────
    fn emitCastMotes(self: *Kobold, dt: f32) void {
        // Gold specks gathering INTO the staff head — drawn upward and inward, so the tell reads as
        // something being summoned rather than as something leaking.
        if (self.fxRng.float() > dt * 34.0) return;
        const head = rl.math.vector3Transform(v3(0, STAFF_TOP * H, 0), self.xf[KIT]);
        const a = self.fxRng.angle();
        const r = self.fxRng.range(0.16, 0.42);
        foe.emitParticle(
            &self.parts,
            &self.head,
            v3(head.x + mathx.cosf(a) * r, head.y + self.fxRng.range(-0.2, 0.2), head.z + mathx.sinf(a) * r),
            mathx.scaleV(mathx.dirXZ(v3(head.x + mathx.cosf(a) * r, 0, head.z + mathx.sinf(a) * r), head), 0.9),
            0.42,
            0.028,
            0.006,
            HEAL_GLOW,
            -0.4, // negative gravity: they float UP into the staff
        );
    }

    fn emitMotes(self: *Kobold, dt: f32) void {
        if (self.fxRng.float() > dt * 26.0) return;
        const c = self.centerWorld();
        foe.emitParticle(&self.parts, &self.head, v3(c.x + self.fxRng.signed() * 0.3, c.y + self.fxRng.signed() * 0.3, c.z + self.fxRng.signed() * 0.3), v3(self.fxRng.signed() * 0.2, self.fxRng.range(0.4, 0.9), self.fxRng.signed() * 0.2), 0.9, 0.035, 0.008, foe.MOTE, -0.25);
    }

    fn emitBlood(self: *Kobold, at: rl.Vector3, dir: rl.Vector3) void {
        var i: u32 = 0;
        while (i < 7) : (i += 1) {
            foe.emitParticle(&self.parts, &self.head, at, v3(dir.x * self.fxRng.range(1.0, 2.6) + self.fxRng.signed() * 0.7, self.fxRng.range(0.7, 2.1), dir.z * self.fxRng.range(1.0, 2.6) + self.fxRng.signed() * 0.7), self.fxRng.range(0.28, 0.5), 0.036, 0.012, BLOOD, 7.0);
        }
    }

    pub fn drawFx(self: *const Kobold) void {
        foe.drawParticles(&self.parts);
    }

    // ── the hero's blade lands (the SHARED foe.strike behaviour) ────────────────────────
    fn tryHit(self: *Kobold, blade: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.strike(&self.vit, &self.hitLatch, self.centerWorld(), self.hurtRadius(), blade) orelse return;
        self.hits += 1;
        self.flash = FLASH_DUR;
        const heavyBlow = blade.hit.stance > 0;
        self.shove = mathx.scaleV(s.dir, if (heavyBlow) 2.1 else 1.35);
        self.emitBlood(s.contact, s.dir);
        sfx.world(.kobold_hurt, self.pos);
        switch (s.reaction) {
            .death => {
                sfx.world(.kobold_die, self.pos);
                self.enterDeath();
            },
            .heavy => self.enterStun(.stunheavy),
            .light => self.enterStun(.stunlight),
            .none => {},
        }
    }

    fn enterStun(self: *Kobold, s: State) void {
        // A BROKEN CAST COSTS THE COOLDOWN TOO, and this has to be read BEFORE `state` is overwritten.
        // That is what makes the owner's "interruptible with a tell" a real window rather than a
        // formality: shutting it buys you the whole nine seconds, where merely delaying the priest a
        // frame would mean it simply starts again as you turn away.
        if (self.state == .cast) self.castCd = CAST_CD;
        self.state = s;
        self.t = 0;
        self.dealt = true; // an interrupted swing lands nothing
        self.chopsLeft = 0; // …and the flurry is over, not paused
        self.castGlow = 0;
    }

    fn enterDeath(self: *Kobold) void {
        self.state = .dead;
        self.t = 0;
        self.dealt = true;
        self.chopsLeft = 0;
        self.castGlow = 0;
        self.justDied = true;
    }

    // ── pose ────────────────────────────────────────────────────────────────────────────
    pub fn pose(self: *Kobold) void {
        const fs = self.scale * (1.0 - 0.55 * self.fade);
        const sink = -0.4 * self.scale * self.fade;
        const facingDeg = mathx.degrees(self.facing);
        const hipY = self.rest[ROOT].y;

        const dead = self.state == .dead;
        const dk = if (dead) mathx.smoothstep(0, 0.5, mathx.clampF(self.t / DEATH_DUR, 0, 1)) else 0;
        const stunAmt = self.stunAmount();

        const m = self.moving * (1.0 - dk);
        const twoPi = std.math.tau;
        const bob = -0.5 * A_BOB * mathx.cosf(2.0 * twoPi * self.phase) * m;
        const latW = @abs(self.latB) * m;
        // Sway / prot / dip all come from hero.zig, so the sidestep reads IDENTICALLY on every
        // humanoid here. The DIP is not optional: a leg swung out to sidestep no longer reaches the
        // ground without it (the bug that left the archer hovering on straight legs).
        const sway = heromod.strafeSway(latW, 0) * mathx.sinf(twoPi * self.phase) * m;
        const prot = A_PROT * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB) +
            heromod.strafeProt(self.phase, self.latB, m);
        const dip = heromod.STRAFE_DIP * latW;

        var wx: [N]rl.Matrix = undefined;
        const collapse = mathx.lerpF(hipY, 0.20 * H, dk);
        // A kobold walks with its trunk already tipped forward — a scavenger's slouch, and the thing
        // that most separates its silhouette from a short man's.
        //
        // THE HEAVE IS NOT HERE, and that is AGENTS.md's law: "BIG BODIES HINGE AT THE WAIST, LEGS STAY
        // PLANTED. Route lean through SPINE/CHEST and leave the pelvis nearly upright; lean at the ROOT
        // rotates the legs and reads as lurching." The first version put 34 deg of doubling-over on the
        // pelvis and it read as a slight tip of the whole body — the legs came with it, so nothing
        // FOLDED. `poseUpper` owns the fold now (`PELVIS_SHARE` below is the ogre's idea, same reason).
        const slouch = 7.0 + 4.0 * m + PELVIS_SHARE * 34.0 * self.heaveAmt() + 16.0 * dk - 22.0 * stunAmt;
        const pelvY = if (dead) collapse else hipY + bob - dip - 0.05 * H * self.heaveAmt();
        // scaleM FIRST → the whole rig scales about its pelvis; the world placement stays unscaled.
        // EVERY rig-local term in the translate is × fs (hip height, bob, dip, sway, the collapse) or
        // at SCALE≠1 the legs hang and the feet sink — AGENTS.md's documented humanoid gotcha.
        wx[ROOT] = mul(scaleM(fs, fs, fs), mul3(
            mul3(rz(8.0 * dk), rx(slouch), ry(prot)),
            mul(tr(sway * fs, pelvY * fs + sink, 0), ry(facingDeg)),
            heromod.rootAt(self.pos), // …on the sculpted ground under it, never y = 0
        ));

        if (!dead) {
            heromod.legChain(&wx, &self.rest, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, solePatches[0]);
            heromod.legChain(&wx, &self.rest, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, solePatches[1]);
        }
        self.poseUpper(&wx, dk, stunAmt, prot);
        self.xf = wx;
    }

    fn stunAmount(self: *const Kobold) f32 {
        return switch (self.state) {
            .stunlight => 1.0 - mathx.smoothstep(0, combat.FOE_LIGHT_STUN_DUR, self.t),
            .stunheavy => 1.0 - 0.45 * mathx.smoothstep(0, combat.FOE_HEAVY_STUN_DUR, self.t),
            else => 0,
        };
    }

    /// How doubled-over the berserker's recovery is right now (0..1). Rises fast, holds, and lets go
    /// late — the hold IS the punish window, so it must not look like it is already leaving.
    fn heaveAmt(self: *const Kobold) f32 {
        if (self.state != .heave) return 0;
        const u = mathx.clampF(self.t / ZERK_RECOVER, 0, 1);
        return mathx.smoothstep(0, 0.16, u) * (1.0 - mathx.smoothstep(0.78, 1.0, u));
    }

    // ── THE UPPER BODY ──────────────────────────────────────────────────────────────────
    // AGENTS.md: legs alone are NOT a gait. Shared legs under a rigid trunk read as moving in one
    // piece, so every walking humanoid here owes a contralateral arm swing at full amplitude, elbows
    // flexing through the FORWARD half only, a shoulder girdle COUNTER-ROTATING against the pelvis, a
    // trunk NOD twice a stride, and a head that counter-rolls all of it — with the LAGS STAGGERED, or
    // joints peaking on the same frame read as one welded block however big the amplitudes.
    fn poseUpper(self: *Kobold, wx: *[N]rl.Matrix, dk: f32, stunAmt: f32, prot: f32) void {
        const twoPi = std.math.tau;
        const ph = self.phase;
        const m = self.moving * (1.0 - dk);
        const heave = self.heaveAmt();

        // TRUNK. The nod is twice a stride (once per foot-fall); the girdle counter-rotates the
        // pelvis, and it LAGS it by an eighth of a cycle because a torso answers hips, it does not
        // anticipate them.
        const nod = 2.2 * mathx.sinf(2.0 * twoPi * ph) * m;
        const counter = -0.62 * prot;
        // THE WAIST TAKES THE FOLD. The heave's whole job is to read as an opening from across a field,
        // and AGENTS.md's other law applies too — REACTIONS ARE HUGE, never a subtle lean — so this is a
        // deliberate 46 deg through the lumbar and 30 more through the chest, over planted feet. It was
        // 6 deg here with 34 on the pelvis, which is the same total angle arranged so that none of it
        // showed. The spine leads and the chest follows it, which is what makes it a fold and not a hinge.
        const fold = 46.0 * heave;
        const spineExtra = 14.0 * dk - 16.0 * stunAmt;
        setLocal(wx, SPINE, self.rest, mul3(rx(nod + fold + spineExtra * 0.5), ry(counter * 0.45), rz(1.4 * mathx.sinf(twoPi * ph) * m)));
        setLocal(wx, CHEST, self.rest, mul3(rx(nod * 0.6 + 0.65 * fold + spineExtra * 0.5), ry(counter * 0.55), rz(-1.0 * mathx.sinf(twoPi * ph) * m)));

        // NECK + SKULL. A dog leads with its nose: the head hangs a touch forward of vertical and
        // counter-rolls the trunk. On the heave it drops to the floor, on a stagger it snaps back.
        const headYaw = -counter * 0.5 + 6.0 * mathx.sinf(self.elapsed * 0.7 + self.seed * 6.0) * (1.0 - m);
        const headPitch = 8.0 - nod * 0.8 + 30.0 * heave - 34.0 * stunAmt + 22.0 * dk;
        setLocal(wx, NECK, self.rest, mul(rx(headPitch * 0.45), ry(headYaw * 0.4)));
        setLocal(wx, SKULL, self.rest, mul3(rx(headPitch * 0.55), ry(headYaw * 0.6), rz(-1.8 * mathx.sinf(twoPi * ph) * m)));

        // ARMS. The contralateral swing is the shared humanoid one; each role then overrides the arm
        // that carries its kit. LAG: the shoulder leads, the elbow arrives an eighth of a cycle later.
        const swing = 13.0 * m;
        const lag = 0.125;
        const shL = -swing * mathx.cosf(twoPi * ph);
        const shR = -swing * mathx.cosf(twoPi * (ph + 0.5));
        const elL = 22.0 + 16.0 * mathx.maxF(0, -mathx.cosf(twoPi * (ph - lag))) * m;
        const elR = 22.0 + 16.0 * mathx.maxF(0, -mathx.cosf(twoPi * (ph + 0.5 - lag))) * m;
        // A kobold's arms hang wide of a narrow chest — the abduction is what stops the forearms
        // clipping the ruff.
        const abd = 11.0;

        switch (self.role) {
            .berserker => self.poseZerk(wx, shL, shR, elL, elR, abd, heave, dk, stunAmt),
            .priest => self.posePriest(wx, shL, shR, elL, elR, abd, dk, stunAmt),
            .slinger => self.poseSlinger(wx, shL, shR, elL, elR, abd, dk, stunAmt),
        }
    }

    /// TWO AXES, ALTERNATING. The live hand chops down and across; the other one is already winding
    /// back, which is what makes the flurry look like it has no plan.
    fn poseZerk(self: *Kobold, wx: *[N]rl.Matrix, shL: f32, shR: f32, elL: f32, elR: f32, abd: f32, heave: f32, dk: f32, stunAmt: f32) void {
        var aL = shL;
        var aR = shR;
        var eL = elL;
        var eR = elR;
        if (self.state == .chop) {
            const u = mathx.clampF(self.t / ZERK_CHOP, 0, 1);
            // Up over the shoulder, then DOWN across the body. The strike span is fast and the
            // recovery is what is left, so the arc arrests rather than parking.
            const raise = 1.0 - mathx.smoothstep(0, ZERK_HIT_A, u);
            const fall = mathx.smoothstep(ZERK_HIT_A, ZERK_HIT_B, u);
            const live = -150.0 * raise + 55.0 * fall;
            const idleArm = 34.0 * mathx.smoothstep(ZERK_HIT_B, 1.0, u); // the other one re-chambers
            if (self.chopLeftHand) {
                aL = live;
                eL = 96.0 * raise + 12.0 * fall;
                aR = -70.0 - idleArm;
                eR = 74.0;
            } else {
                aR = live;
                eR = 96.0 * raise + 12.0 * fall;
                aL = -70.0 - idleArm;
                eL = 74.0;
            }
        } else if (heave > 0.01) {
            // Hanging off his own arms, axes dragging in the dirt.
            aL = 26.0 * heave;
            aR = 26.0 * heave;
            eL = 18.0 + 10.0 * heave;
            eR = 18.0 + 10.0 * heave;
        }
        const flail = 30.0 * stunAmt + 24.0 * dk; // arms fly up on a hit
        setLocal(wx, SHL, self.rest, mul3(rx(aL - flail), ry(-8.0), rz(abd)));
        setLocal(wx, ELL, self.rest, rx(-eL));
        setLocal(wx, WRL, self.rest, rx(-8.0));
        setLocal(wx, SHR, self.rest, mul3(rx(aR - flail), ry(8.0), rz(-abd)));
        setLocal(wx, ELR, self.rest, rx(-eR));
        setLocal(wx, WRR, self.rest, rx(-8.0));
        setLocal(wx, KIT, self.rest, rl.math.matrixIdentity());
    }

    /// THE STAFF, two-handed on the cast: it comes up over the head and the off hand steadies it.
    /// The rest of the time it is a walking stick.
    fn posePriest(self: *Kobold, wx: *[N]rl.Matrix, shL: f32, shR: f32, elL: f32, elR: f32, abd: f32, dk: f32, stunAmt: f32) void {
        const c = if (self.state == .cast) mathx.smoothstep(0, 0.55, self.t / CAST_DUR) else 0;
        const flail = 28.0 * stunAmt + 20.0 * dk;
        // The staff arm: down at rest, swung up and forward through the cast.
        const aR = mathx.lerpF(shR - 14.0, -112.0, c);
        const eR = mathx.lerpF(elR, 34.0, c);
        // The off hand comes ACROSS to the haft as the cast builds — two hands on it is what says
        // this is the thing it is doing, not a thing it is holding.
        const aL = mathx.lerpF(shL, -74.0, c);
        const eL = mathx.lerpF(elL, 82.0, c);
        setLocal(wx, SHL, self.rest, mul3(rx(aL - flail), ry(mathx.lerpF(-6.0, -34.0, c)), rz(abd * (1.0 - 0.5 * c))));
        setLocal(wx, ELL, self.rest, rx(-eL));
        setLocal(wx, WRL, self.rest, rx(-6.0));
        setLocal(wx, SHR, self.rest, mul3(rx(aR - flail), ry(mathx.lerpF(6.0, 16.0, c)), rz(-abd * (1.0 - 0.4 * c))));
        setLocal(wx, ELR, self.rest, rx(-eR));
        setLocal(wx, WRR, self.rest, rx(-10.0 - 16.0 * c));
        // The staff itself tips from a carried angle toward vertical as the light gathers.
        setLocal(wx, KIT, self.rest, rx(mathx.lerpF(24.0, -8.0, c)));
    }

    /// THE SLING WHIRLS OVER THE HEAD, and the arm really goes round with it — the tell is motion,
    /// not a pose. The bite is the whole body snapping forward behind the jaw.
    fn poseSlinger(self: *Kobold, wx: *[N]rl.Matrix, shL: f32, shR: f32, elL: f32, elR: f32, abd: f32, dk: f32, stunAmt: f32) void {
        var aR = shR;
        var eR = elR;
        var yR: f32 = 8.0;
        if (self.state == .whirl) {
            const w = self.whirlPh * std.math.tau;
            // Arm up and over, describing a cone about the shoulder: the pitch lifts it, the yaw
            // carries it round.
            aR = -118.0 + 22.0 * mathx.sinf(w);
            yR = 34.0 * mathx.cosf(w);
            eR = 26.0;
        } else if (self.state == .bite) {
            const u = mathx.clampF(self.t / BITE_DUR, 0, 1);
            const snap = mathx.smoothstep(BITE_HIT_A * 0.5, BITE_HIT_B, u) * (1.0 - mathx.smoothstep(BITE_HIT_B, 1.0, u));
            aR = shR - 34.0 * snap; // arms sweep back as it lunges with the head
            eR = elR + 20.0 * snap;
        }
        const flail = 26.0 * stunAmt + 20.0 * dk;
        setLocal(wx, SHL, self.rest, mul3(rx(shL - flail), ry(-6.0), rz(abd)));
        setLocal(wx, ELL, self.rest, rx(-elL));
        setLocal(wx, WRL, self.rest, rx(-6.0));
        setLocal(wx, SHR, self.rest, mul3(rx(aR - flail), ry(yR), rz(-abd)));
        setLocal(wx, ELR, self.rest, rx(-eR));
        setLocal(wx, WRR, self.rest, rx(-8.0));
        setLocal(wx, KIT, self.rest, rx(if (self.state == .whirl) -40.0 else 10.0));
    }

    /// THE JAW OPENS on the bite, and the SNOUT drives the whole reaction. Returned as a number the
    /// draw uses on the muzzle mesh rather than posed as a bone: a hinged jaw would be a nineteenth
    /// bone on a shared eighteen-bone scaffold, and one creature is not worth breaking that for.
    pub fn gape(self: *const Kobold) f32 {
        if (self.state == .bite) {
            const u = mathx.clampF(self.t / BITE_DUR, 0, 1);
            return mathx.smoothstep(0, BITE_HIT_A, u) * (1.0 - mathx.smoothstep(BITE_HIT_B, 1.0, u));
        }
        if (self.state == .dead) return 0.45 * mathx.smoothstep(0, 0.3, self.t / DEATH_DUR);
        return 0;
    }

    pub fn draw(self: *const Kobold, model: *const Model) void {
        model.draw(self);
    }
};

// ══ MESHES ═══════════════════════════════════════════════════════════════════════════════
// FLESH IS ROUND (AGENTS.md): every organic mass here is `addBlob`/`addCapsule`, and `addCube`/`addBox`
// is reserved for the iron, the hide straps and the hafts. A bare `addCylinder` leaves an open cut
// pipe and a hard rim, and those rims are what read as BLOCKY however good the animation on top.
//
// WABI-SABI: every bone carries its own seeded wonk, so no two limbs are the same machined part. The
// FUR is the same idea taken further — tufts at irregular angles and sizes, and RELIEF IS SUBTLE, so
// each one stands off its mass by a few percent of that mass's radius rather than a tenth.

/// How far a fur tuft stands off the mass it grows from, as a fraction of that mass's radius.
///
/// RELIEF IS SUBTLE cuts the other way for FUR, and 0.16 was me applying the masonry rule to a pelt.
/// That law is about detail whose job is to BREAK UP a big smooth mass — flutes, coursing, bark ridges
/// — where a tenth of the radius reads as strips glued on. Fur is not that: it is the SILHOUETTE, and a
/// pelt that only breaks its own outline by a few percent is a shaved animal. Rendered, the first pass
/// read as bare sticks with the tufts invisible.
const FUR_OUT: f32 = 0.42;

/// Sow `n` tufts of fur around a limb segment a→b of radius `r`. The tufts are BLOBS sunk most of the
/// way into the mass with only their ends breaking the surface, which is what makes a pelt out of a
/// smooth capsule instead of a hedgehog.
fn furInto(b: *Builder, a: rl.Vector3, bb: rl.Vector3, r: f32, n: i32, rng: *mathx.Rng, col: rl.Color) void {
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const t = rng.range(0.12, 0.92);
        const p = mathx.lerpV(a, bb, t);
        const ang = rng.angle();
        // A tuft lies mostly ALONG the limb (fur has a lie), so it is a long thin blob, not a spike.
        const out = r * (1.0 + FUR_OUT * rng.range(0.5, 1.0));
        const cx = p.x + mathx.cosf(ang) * out * 0.72;
        const cz = p.z + mathx.sinf(ang) * out * 0.72;
        const len = r * rng.range(1.1, 2.1);
        // FAT tufts, not needles. A clump of fur is a lump the width of a finger; at 0.26-0.42 of the
        // limb's radius these were slivers that vanished into the capsule they grew from.
        //
        // …and ROUNDER: at 3 segments x 5 sides a blob this size is a visible polyhedron, and rendered,
        // the pelt came back reading as angular ARMOUR PLATE rather than fur. 4x7 is still cheap (a
        // warband is up to 72 of these) and it is the difference between a lump and a facet.
        b.addBlob(v3(cx, p.y, cz), v3(r * rng.range(0.48, 0.78), len, r * rng.range(0.48, 0.78)), 4, 7, col);
    }
}

// ── the head ────────────────────────────────────────────────────────────────────────────
// A DOG'S HEAD ON A HUMANOID: the skull is a rounded box of bone, the SNOUT is the whole character —
// long, tapering, with the nose leather at the end — and the EARS are pricked triangles standing off
// the crown. Get the muzzle length wrong and it is a man in a mask.
const SNOUT_LEN = 0.088; // fractions of H, the head being the one place they are worth naming
const SNOUT_DROP = 0.018;

fn skullMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4B0B01D);
    const s = H;
    // The braincase — a blob wider than it is tall, with the occiput swelling out at the back.
    b.addBlob(v3(0, 0.030 * s, 0.004 * s), v3(0.049 * s, 0.044 * s, 0.055 * s), 5, 9, FUR);
    b.addBlob(v3(0, 0.020 * s, -0.032 * s), v3(0.040 * s, 0.036 * s, 0.030 * s), 4, 8, FUR_DK);
    // The BROW ridge — a low band over the eyes. It is what gives a dog a expression at all.
    b.addCapsule(v3(-0.040 * s, 0.036 * s, 0.036 * s), v3(0.040 * s, 0.036 * s, 0.036 * s), 0.013 * s, 0.013 * s, 6, FUR_LT);
    // The SNOUT: two tapering capsules, the second the nose bridge, dropping as it runs forward.
    const noseZ = (0.030 + SNOUT_LEN) * s;
    b.addCapsule(v3(0, 0.024 * s, 0.040 * s), v3(0, 0.024 * s - SNOUT_DROP * s, noseZ), 0.030 * s, 0.018 * s, 9, MUZZLE);
    b.addCapsule(v3(0, 0.036 * s, 0.046 * s), v3(0, 0.030 * s - SNOUT_DROP * s, noseZ - 0.004 * s), 0.016 * s, 0.010 * s, 7, FUR_DK);
    // The nose leather, and it is BLACK — the one hard dark note on the whole face, which is what the
    // eye finds first and reads as "dog".
    b.addBlob(v3(0, 0.026 * s - SNOUT_DROP * s, noseZ + 0.004 * s), v3(0.014 * s, 0.011 * s, 0.010 * s), 3, 7, NOSE);
    // The lower jaw, shorter than the upper — an underslung muzzle reads as a snarl.
    b.addCapsule(v3(0, 0.008 * s, 0.040 * s), v3(0, 0.006 * s - SNOUT_DROP * s * 0.7, noseZ - 0.016 * s), 0.020 * s, 0.012 * s, 7, MUZZLE);
    // TEETH, just proud of the lip line. Small, uneven, and only the canines really show.
    for ([_]f32{ -1, 1 }) |side| {
        b.addBlob(v3(side * 0.014 * s, 0.014 * s - SNOUT_DROP * s * 0.5, noseZ - 0.026 * s), v3(0.0042 * s, 0.010 * s, 0.0042 * s), 2, 5, TOOTH);
        b.addBlob(v3(side * 0.010 * s, 0.018 * s - SNOUT_DROP * s * 0.5, noseZ - 0.014 * s), v3(0.0030 * s, 0.006 * s, 0.0030 * s), 2, 4, TOOTH);
    }
    // EYES — amber, self-lit (vertex alpha < 255 is the emissive channel), set FORWARD and close: a
    // predator's placement, and the difference between a wolf and a sheep.
    for ([_]f32{ -1, 1 }) |side| {
        b.addBlob(v3(side * 0.026 * s, 0.032 * s, 0.043 * s), v3(0.0085 * s, 0.0085 * s, 0.0060 * s), 3, 6, EYE);
    }
    // EARS: pricked, tall, ASYMMETRIC (one a touch lower and cocked out — a scavenger has been in
    // fights). Built as flattened blobs so they have an inner face to catch light.
    for ([_]f32{ -1, 1 }) |side| {
        const lean: f32 = if (side < 0) 12.0 else -19.0;
        const hgt: f32 = if (side < 0) 0.052 else 0.046;
        const baseX = side * 0.036 * s;
        const tipX = baseX + side * 0.016 * s + mathx.sinf(mathx.radians(lean)) * 0.01 * s;
        b.addBlob(v3((baseX + tipX) * 0.5, (0.058 + hgt * 0.5) * s, -0.010 * s), v3(0.016 * s, hgt * 0.5 * s, 0.008 * s), 3, 6, FUR);
        b.addBlob(v3((baseX + tipX) * 0.5, (0.056 + hgt * 0.45) * s, -0.006 * s), v3(0.009 * s, hgt * 0.38 * s, 0.004 * s), 3, 5, EAR_IN);
    }
    // A fur ruff round the base of the skull, so the head does not meet the neck on a clean seam.
    furInto(&b, v3(-0.03 * s, 0.006 * s, -0.020 * s), v3(0.03 * s, 0.006 * s, -0.020 * s), 0.030 * s, 9, &rng, FUR_LT);
    return b.toMesh();
}

fn neckMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4EC0);
    const s = H;
    b.addCapsule(v3(0, 0, 0), v3(0, 0.062 * s, 0.006 * s), 0.038 * s, 0.032 * s, 8, FUR);
    // THE RUFF — a thick mane round the neck and over the shoulders. This is the single biggest
    // silhouette cue after the snout: it is what makes the shoulders look like an animal's. It did not
    // read AT ALL in the first render, which is what sent every radius on this creature up.
    furInto(&b, v3(0, 0.006 * s, -0.004 * s), v3(0, 0.052 * s, -0.004 * s), 0.046 * s, 26, &rng, FUR_LT);
    furInto(&b, v3(0, 0.012 * s, -0.012 * s), v3(0, 0.046 * s, -0.012 * s), 0.050 * s, 18, &rng, FUR_DK);
    return b.toMesh();
}

fn pelvisMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xBE17);
    const s = H;
    b.addBlob(v3(0, 0.014 * s, 0), v3(0.070 * s, 0.052 * s, 0.058 * s), 5, 9, FUR);
    // A filthy hide belt — cloth and leather are the one place a BOX is right.
    b.addCube(v3(0, 0.030 * s, 0), v3(0.126 * s, 0.020 * s, 0.100 * s), HIDE);
    b.addCube(v3(0, 0.030 * s, 0.052 * s), v3(0.034 * s, 0.028 * s, 0.010 * s), HIDE_LT); // the buckle plate
    // THE TAIL — low-set, heavy at the root, hanging and curling. A kobold without one is a goblin.
    var t: f32 = 0;
    var prev = v3(0, 0.010 * s, -0.044 * s);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        t += 1.0;
        const k = t / 5.0;
        const nxt = v3(
            mathx.sinf(k * 2.2 + 0.4) * 0.026 * s,
            (0.010 - 0.052 * k) * s,
            (-0.044 - 0.058 * k) * s,
        );
        b.addCapsule(prev, nxt, (0.020 - 0.011 * k) * s, (0.019 - 0.011 * k) * s, 7, if (@rem(i, 2) == 0) FUR else FUR_DK);
        furInto(&b, prev, nxt, (0.020 - 0.011 * k) * s, 4, &rng, FUR_LT);
        prev = nxt;
    }
    furInto(&b, v3(-0.05 * s, 0.006 * s, -0.02 * s), v3(0.05 * s, 0.006 * s, -0.02 * s), 0.040 * s, 8, &rng, FUR_DK);
    return b.toMesh();
}

fn lumbarMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x10BA);
    const s = H;
    b.addBlob(v3(0, 0.058 * s, -0.004 * s), v3(0.058 * s, 0.062 * s, 0.056 * s), 5, 9, FUR);
    furInto(&b, v3(0, 0.020 * s, -0.030 * s), v3(0, 0.096 * s, -0.030 * s), 0.048 * s, 14, &rng, FUR_DK);
    return b.toMesh();
}

fn ribcageMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x21BC);
    const s = H;
    // HOLLOW-CHESTED and narrow — a scavenger, not an athlete. Deeper front-to-back than it is wide,
    // which is a dog's ribcage and reads instantly as not-human.
    // DEEP front-to-back and narrow across — a dog's ribcage, and it has to have real MASS or the
    // shoulders read as a coat hanger (they did: the first render had no chest at all).
    b.addBlob(v3(0, 0.040 * s, 0.002 * s), v3(0.064 * s, 0.062 * s, 0.070 * s), 5, 9, FUR);
    b.addBlob(v3(0, 0.006 * s, 0.004 * s), v3(0.056 * s, 0.034 * s, 0.058 * s), 4, 8, FUR_DK);
    // A hide harness over one shoulder — asymmetric on purpose (wabi-sabi; nothing here is a matched
    // pair) and it breaks up the chest mass.
    b.addBox(v3(0.020 * s, 0.040 * s, 0.030 * s), v3(0.020 * s, 0.062 * s, 0.006 * s), v3(-0.052 * s, 0.020 * s, 0), v3(0, 0, 0.030 * s), HIDE);
    furInto(&b, v3(-0.04 * s, 0.072 * s, -0.026 * s), v3(0.04 * s, 0.072 * s, -0.026 * s), 0.040 * s, 12, &rng, FUR_LT);
    furInto(&b, v3(0, 0.010 * s, -0.034 * s), v3(0, 0.070 * s, -0.034 * s), 0.038 * s, 8, &rng, FUR_DK);
    return b.toMesh();
}

fn limbMesh(seed: u64, len: f32, r0: f32, r1: f32, col: rl.Color, tufts: i32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const s = H;
    // A limb hangs down its own -Y, and it is bent a hair off plumb — a machined-straight limb is the
    // thing that reads as a mannequin.
    const kink = rng.signed() * 0.006 * s;
    const a = v3(0, 0, 0);
    const bb = v3(kink, -len * s, rng.signed() * 0.005 * s);
    b.addCapsule(a, bb, r0 * s, r1 * s, 8, col);
    furInto(&b, a, bb, r0 * s, tufts, &rng, if (rng.float() < 0.5) FUR_LT else FUR_DK);
    return b.toMesh();
}

fn handMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const s = H;
    // A PAW-HAND: a padded palm and four short digits with claws. Short enough to read as an animal's,
    // articulate enough to hold a haft.
    b.addBlob(v3(0, -0.018 * s, 0.004 * s), v3(0.019 * s, 0.022 * s, 0.014 * s), 3, 7, FUR);
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const fx = (@as(f32, @floatFromInt(i)) - 1.5) * 0.0095 * s;
        const fl = 0.020 * s * rng.range(0.85, 1.15);
        const tip = v3(fx, -0.038 * s - fl, 0.010 * s);
        b.addCapsule(v3(fx, -0.032 * s, 0.008 * s), tip, 0.0046 * s, 0.0036 * s, 5, MUZZLE);
        b.addBlob(v3(tip.x, tip.y - 0.003 * s, tip.z + 0.003 * s), v3(0.0028 * s, 0.005 * s, 0.0028 * s), 2, 4, CLAW);
    }
    return b.toMesh();
}

fn footMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const s = H;
    // The PAW. Measured against `solePatches` above: the pad's underside sits on the ankle plane at
    // −0.036·H, spans z −0.035·H…+0.175·H and x ±0.044·H. Change it and re-measure that table, or the
    // foot planting solves against a sole that is not where the mesh is.
    b.addBlob(v3(0, -0.026 * s, 0.062 * s), v3(0.040 * s, 0.014 * s, 0.098 * s), 4, 8, FUR_DK);
    b.addCapsule(v3(0, -0.014 * s, -0.028 * s), v3(0, -0.014 * s, 0.030 * s), 0.026 * s, 0.030 * s, 7, FUR);
    // Three forward toes with claws, and a heel pad behind.
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const fx = (@as(f32, @floatFromInt(i)) - 1.0) * 0.024 * s;
        const tipZ = (0.150 + rng.range(0.0, 0.022)) * s;
        b.addCapsule(v3(fx, -0.030 * s, 0.100 * s), v3(fx, -0.032 * s, tipZ), 0.012 * s, 0.009 * s, 6, FUR_DK);
        b.addBlob(v3(fx, -0.032 * s, tipZ + 0.008 * s), v3(0.005 * s, 0.005 * s, 0.010 * s), 2, 5, CLAW);
    }
    b.addBlob(v3(0, -0.028 * s, -0.026 * s), v3(0.030 * s, 0.012 * s, 0.020 * s), 3, 6, MUZZLE);
    // Hide wraps round the ankle — every one of these has been scavenged off something.
    b.addCube(v3(0, 0.006 * s, 0.006 * s), v3(0.056 * s, 0.016 * s, 0.050 * s), HIDE);
    return b.toMesh();
}

// ── the three kits ──────────────────────────────────────────────────────────────────────
// Each is authored in the RIGHT WRIST's frame, like the hero's sword and the archer's bow, and hangs
// off `hero.HELD`. IRON AND WOOD, so these are the one place boxes belong.

const AXE_HAFT = 0.150; // fractions of H
const STAFF_TOP = 0.300;
const SLING_LEN = 0.140;

fn axeMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    const s = H;
    const grip = v3(0, -0.05 * s, 0.006 * s); // the fist centre, matching the other rigs' convention
    // A crude hand-axe: a short haft with a wedge of iron lashed to the head, canted forward so it
    // leads the wrist (the same grip cant the hero's sword has).
    const headY = grip.y + AXE_HAFT * s;
    b.addCylinder(v3(grip.x, grip.y - 0.030 * s, grip.z), v3(grip.x, headY, grip.z + 0.014 * s), 0.0090 * s, 0.0075 * s, 7, HAFT);
    // …capped, because a cylinder is CAPLESS and an open end shows its culled interior.
    b.addDome(v3(grip.x, grip.y - 0.030 * s, grip.z), v3(0, -1, 0), 0.0090 * s, 7, HAFT);
    b.addCube(v3(grip.x, grip.y - 0.006 * s, grip.z), v3(0.020 * s, 0.026 * s, 0.020 * s), HIDE); // grip wrap
    // The blade: a wedge, chipped, and NOT symmetric.
    const bx = 0.030 * s * rng.range(0.9, 1.1);
    b.addBox(v3(grip.x + bx * 0.5, headY - 0.004 * s, grip.z + 0.016 * s), v3(bx, 0.006 * s, 0), v3(0, 0.044 * s, 0.004 * s), v3(0, 0, 0.013 * s), IRON);
    b.addBox(v3(grip.x + bx * 1.0, headY - 0.004 * s, grip.z + 0.016 * s), v3(0.010 * s, 0.004 * s, 0), v3(0, 0.036 * s, 0), v3(0, 0, 0.009 * s), IRON_LT); // the ground edge
    // A lashing where the head meets the haft.
    b.addCapsule(v3(grip.x - 0.004 * s, headY - 0.014 * s, grip.z + 0.010 * s), v3(grip.x + 0.006 * s, headY + 0.020 * s, grip.z + 0.018 * s), 0.0072 * s, 0.0072 * s, 6, HIDE_LT);
    return b.toMesh();
}

fn staffMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x57AFF);
    const s = H;
    const grip = v3(0, -0.05 * s, 0.006 * s);
    // A crooked branch, taller than its owner — the one thing about a kobold that has any dignity.
    var prev = v3(grip.x, grip.y - 0.115 * s, grip.z);
    var i: i32 = 0;
    while (i < 6) : (i += 1) {
        const k = (@as(f32, @floatFromInt(i)) + 1.0) / 6.0;
        const nxt = v3(
            grip.x + mathx.sinf(k * 2.6) * 0.012 * s,
            grip.y - 0.115 * s + (STAFF_TOP + 0.115) * s * k,
            grip.z + mathx.sinf(k * 1.7 + 1.0) * 0.008 * s,
        );
        b.addCapsule(prev, nxt, (0.0088 - 0.0016 * k) * s, (0.0086 - 0.0016 * k) * s, 7, HAFT);
        prev = nxt;
    }
    b.addDome(v3(grip.x, grip.y - 0.115 * s, grip.z), v3(0, -1, 0), 0.0088 * s, 7, HAFT);
    // The head: a fork of the branch holding a bound bone charm, and a self-lit stone in the crook.
    // Self-lit because the CAST has to be legible from across a plaza and a lit mesh in shade is not.
    for ([_]f32{ -1, 1 }) |side| {
        b.addCapsule(prev, v3(prev.x + side * 0.020 * s, prev.y + 0.026 * s, prev.z + 0.006 * s), 0.0060 * s, 0.0040 * s, 6, HAFT);
    }
    b.addBlob(v3(prev.x, prev.y + 0.020 * s, prev.z + 0.004 * s), v3(0.011 * s, 0.013 * s, 0.011 * s), 4, 7, HEAL_GLOW);
    // Charms and feathers on thongs — a wayside priest's whole authority.
    var k: i32 = 0;
    while (k < 4) : (k += 1) {
        const hy = prev.y - rng.range(0.03, 0.10) * s;
        const hx = prev.x + rng.signed() * 0.012 * s;
        b.addCapsule(v3(hx, hy, prev.z), v3(hx + rng.signed() * 0.006 * s, hy - 0.022 * s, prev.z + rng.signed() * 0.005 * s), 0.0016 * s, 0.0014 * s, 4, HIDE_LT);
        b.addBlob(v3(hx, hy - 0.026 * s, prev.z), v3(0.0050 * s, 0.0090 * s, 0.0038 * s), 2, 5, BONE_CHARM);
    }
    b.addCube(v3(grip.x, grip.y, grip.z), v3(0.020 * s, 0.030 * s, 0.020 * s), HIDE); // the grip wrap
    return b.toMesh();
}

fn slingMesh() rl.Mesh {
    var b = Builder.init();
    const s = H;
    const grip = v3(0, -0.05 * s, 0.006 * s);
    // Two cords off the fist to a leather pouch. Authored along +Z so `slingPoint` can find the pouch
    // by transforming (0, 0, SLING_LEN·H) — one definition of where a stone leaves from.
    const pouch = v3(grip.x, grip.y, grip.z + SLING_LEN * s);
    for ([_]f32{ -1, 1 }) |side| {
        b.addCapsule(
            v3(grip.x + side * 0.006 * s, grip.y, grip.z),
            v3(pouch.x + side * 0.010 * s, pouch.y, pouch.z - 0.016 * s),
            0.0018 * s,
            0.0016 * s,
            4,
            SLING_CORD,
        );
    }
    // The pouch, and a stone sitting in it — the loaded sling is the readable one.
    b.addBlob(pouch, v3(0.016 * s, 0.010 * s, 0.014 * s), 3, 7, HIDE);
    b.addBlob(v3(pouch.x, pouch.y + 0.005 * s, pouch.z), v3(0.009 * s, 0.008 * s, 0.009 * s), 3, 6, STONE_COL);
    b.addCube(grip, v3(0.020 * s, 0.026 * s, 0.020 * s), HIDE_LT);
    return b.toMesh();
}

/// The sling STONE, as a projectile mesh — game.zig draws it where an arrow would go.
pub fn stoneMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x570E);
    // Irregular, because a slung stone is a stone off the ground and not a ball bearing.
    b.addBlob(mathx.zero3, v3(0.040 * rng.range(0.9, 1.2), 0.036 * rng.range(0.9, 1.2), 0.042), 3, 6, STONE_COL);
    return b.toModel(shader);
}

fn buildMeshes() [N]rl.Mesh {
    var mesh: [N]rl.Mesh = undefined;
    mesh[ROOT] = pelvisMesh();
    mesh[SPINE] = lumbarMesh();
    mesh[CHEST] = ribcageMesh();
    mesh[NECK] = neckMesh();
    mesh[SKULL] = skullMesh();
    // LIMB RADII: a FURRY ANIMAL, not a skeleton. These were the archer's numbers (0.030/0.023 leg,
    // 0.022/0.018 arm) because that is the file I built the rig from — and rendered, three kobolds came
    // back as spindly stick-figures with skin-coloured bones. A dog's leg under fur is nearly twice
    // that, and the fur is on TOP of it. Every one is up ~55-60%, and the tuft counts with them.
    mesh[HIPL] = limbMesh(0x7401, SEG_THIGH, 0.049, 0.038, FUR, 12);
    mesh[KNEEL] = limbMesh(0x7402, SEG_SHANK, 0.036, 0.025, FUR, 10);
    mesh[ANKL] = footMesh(0x7403);
    mesh[HIPR] = limbMesh(0x7404, SEG_THIGH, 0.049, 0.038, FUR, 12);
    mesh[KNEER] = limbMesh(0x7405, SEG_SHANK, 0.036, 0.025, FUR, 10);
    mesh[ANKR] = footMesh(0x7406);
    mesh[SHL] = limbMesh(0x7407, SEG_UPARM, 0.035, 0.028, FUR, 10);
    mesh[ELL] = limbMesh(0x7408, SEG_FOREARM, 0.028, 0.021, FUR, 11);
    mesh[WRL] = handMesh(0x7409);
    mesh[SHR] = limbMesh(0x740A, SEG_UPARM, 0.035, 0.028, FUR, 10);
    mesh[ELR] = limbMesh(0x740B, SEG_FOREARM, 0.028, 0.021, FUR, 11);
    mesh[WRR] = handMesh(0x740C);
    // Bone 17 draws nothing shared — the KIT is per role (see Model.kit).
    var empty = Builder.init();
    empty.addBlob(mathx.zero3, v3(0.0001, 0.0001, 0.0001), 2, 3, FUR);
    mesh[KIT] = empty.toMesh();
    return mesh;
}

/// One shared Model for the whole warband: the body once, and the three kits beside it. The BERSERKER
/// carries two axes, so there is a second, deliberately different one for the off hand — the same
/// mesh in both fists is the kind of mirrored pair the house style exists to avoid.
pub const Model = struct {
    mesh: [N]rl.Mesh,
    kit: [3]rl.Mesh, // indexed by Role
    offAxe: rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) Model {
        var mat = rl.loadMaterialDefault() catch @panic("kobold material");
        mat.shader = shader;
        return .{
            .mesh = buildMeshes(),
            .kit = [3]rl.Mesh{ axeMesh(0xA7E1), staffMesh(), slingMesh() },
            .offAxe = axeMesh(0xA7E2),
            .mat = mat,
        };
    }
    pub fn setShader(self: *Model, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const Model, k: *const Kobold) void {
        for (0..N) |i| {
            if (i == KIT) continue;
            rl.drawMesh(self.mesh[i], self.mat, k.xf[i]);
        }
        rl.drawMesh(self.kit[@intFromEnum(k.role)], self.mat, k.xf[KIT]);
        // The off-hand axe rides the LEFT wrist, mirrored across X so its blade faces outward.
        if (k.role == .berserker) {
            rl.drawMesh(self.offAxe, self.mat, mul(mathx.scaleM(-1, 1, 1), k.xf[WRL]));
        }
    }
};

// ── THE WARBAND ─────────────────────────────────────────────────────────────────────────
// ONE group holding ALL THREE ROLES mixed, and that is a design decision with a reason: the PRIEST
// heals a friend, so somebody has to be able to see the whole band at once. Split across three Groups
// (one per FoeKind, like the toads and the archers) that "somebody" would have to be game.zig,
// threading two foreign groups into a third's update. Mixed in one array it is a loop over `self`.
//
// It is also why `reset` is not `foe.resetGroup`: that filters ONE kind, and three filtered passes
// would bucket the band by role and lose the map's own ordering.

/// Room for a full posting of every role (`wf.MAX_PER_KIND` each). Deliberately not smaller: the cap
/// is what a map may legally ask for, and `resetGroup`'s contract is to SKIP the overflow — a band
/// that silently dropped its priest would look like a bug in the healing.
pub const CAP = 3 * wf.MAX_PER_KIND;

pub const Warband = struct {
    model: Model,
    band: [CAP]Kobold = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Warband {
        return .{ .model = Model.init(shader) };
    }
    /// The posted kobolds — never iterate the whole array, the tail is `undefined`.
    pub fn live(self: *Warband) []Kobold {
        return self.band[0..self.n];
    }
    pub fn liveConst(self: *const Warband) []const Kobold {
        return self.band[0..self.n];
    }

    /// RE-HOME from the map: every kobold spawn of any role, in FILE ORDER, built fresh. One pass
    /// rather than three filtered ones (see the note above), so a band keeps the order it was
    /// authored in and a priest posted between two berserkers stays between them.
    pub fn reset(self: *Warband, m: *const wf.Map) void {
        self.n = 0;
        for (m.foes[0..m.nfoes]) |h| {
            const role = roleOf(h.kind) orelse continue;
            if (self.n >= CAP) continue;
            // ON THE GROUND the map's own height field decides — a spawn table stores x/z only, so
            // posting one on a sculpted rise and dropping it at y = 0 buries it to the waist.
            self.band[self.n] = Kobold.spawnAs(role, v3(h.x, m.heightAt(h.x, h.z), h.z), mathx.radians(h.yaw), h.scale, h.seed);
            self.n += 1;
        }
    }

    pub fn setShader(self: *Warband, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn draw(self: *const Warband, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Warband) void {
        for (self.liveConst()) |*k| k.drawFx();
    }

    // The shared Group roll-ups (foe.zig).
    pub fn anyDied(self: *const Warband) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn totalHits(self: *const Warband) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Warband) u32 {
        return foe.aliveCount(self.liveConst());
    }
    /// RUNES paid out this frame. Not `foe.runesDropped`, which pays a flat `per` for the whole group:
    /// a kobold's worth is its ROLE's (the priest is worth the most, because killing it first is the
    /// correct play and the payout should agree with the lesson).
    pub fn runesDropped(self: *const Warband) u32 {
        var n: u32 = 0;
        for (self.liveConst()) |*k| {
            if (k.justDied) n += k.runeValue();
        }
        return n;
    }

    /// Drive the whole band a frame. Returns the hero blow to apply, if any of them landed one.
    ///
    /// THE HEAL IS RESOLVED HERE, and this is the reason the band is one array: the priest's cast
    /// completes inside its own update and hands back `.healed`, and the CHOICE of who receives it is
    /// made from the band as a whole — the neediest living member in range. The priest owns the
    /// animation and the timing; it never learns who its friends are.
    /// `loose` is passed as a comptime function over a context (the `env.pickIf` / `camera.followClear`
    /// idiom) so this file stays independent of the projectile pool: a slinger's stone shares the
    /// ARROW pool, which game.zig owns, and the band needs to know where a stone leaves from — not
    /// what a pool is.
    pub fn update(
        self: *Warband,
        dt: f32,
        hero: rl.Vector3,
        bounds: f32,
        blade: foe.Blade,
        ctx: anytype,
        comptime loose: fn (@TypeOf(ctx), rl.Vector3) void,
    ) ?combat.Hit {
        // Tell each priest whether there is anything worth casting for, BEFORE any of them decides.
        // Read off the pre-update state on purpose: every priest in a band then answers the same
        // picture, instead of the second one seeing the first one's heal already applied.
        for (self.live()) |*k| {
            if (k.role != .priest) continue;
            k.healWanted = self.neediest(k.pos) != null;
        }
        var blow: ?combat.Hit = null;
        for (self.live()) |*k| {
            switch (k.update(dt, hero, bounds, blade)) {
                .none => {},
                .sling => |from| loose(ctx, from),
                .healed => {
                    // Chosen AT THE MOMENT IT LANDS, not at the cast's start: a heal that committed to
                    // a target a second and a quarter ago pours into whoever was worst off then, which
                    // on a live front line is regularly somebody already dead.
                    if (self.neediestIdx(k.pos)) |ti| {
                        if (self.band[ti].vit.heal(HEAL_AMT) > 0) sfx.world(.kobold_heal, self.band[ti].pos);
                    }
                },
            }
            // A live hurt window that reaches the hero: one blow per swing, latched.
            if (k.hurtOpen() and mathx.distXZ(k.pos, hero) <= k.hurtReach()) {
                k.markDealt();
                blow = k.hurtBlow();
                sfx.world(if (k.state == .bite) .kobold_bite else .kobold_chop, k.pos);
            }
        }
        return blow;
    }

    /// The living member most in need of a heal within `HEAL_RANGE` of `from`, or null. A priest will
    /// heal ITSELF if it is the worst off — a healer that would rather die than break formation is a
    /// bug, not a characterisation.
    fn neediestIdx(self: *const Warband, from: rl.Vector3) ?usize {
        var best: ?usize = null;
        var worst: f32 = 1.0;
        for (self.liveConst(), 0..) |*k, i| {
            if (!k.alive() or k.dying()) continue;
            if (!k.vit.needsHeal(HEAL_SLACK)) continue;
            if (mathx.distXZ(from, k.pos) > HEAL_RANGE) continue;
            const f = k.vit.hpFrac();
            if (f < worst) {
                worst = f;
                best = i;
            }
        }
        return best;
    }
    fn neediest(self: *const Warband, from: rl.Vector3) ?*const Kobold {
        const i = self.neediestIdx(from) orelse return null;
        return &self.band[i];
    }
};

// ── tests ───────────────────────────────────────────────────────────────────────────────

test "the role table, the enum and the map's foe kinds agree" {
    // The comptime block above pins the ordinal shift; this pins the accessor built on it, and that
    // non-kobold kinds are rejected rather than folded into a role.
    try std.testing.expectEqual(Role.berserker, roleOf(.berserker).?);
    try std.testing.expectEqual(Role.priest, roleOf(.priest).?);
    try std.testing.expectEqual(Role.slinger, roleOf(.slinger).?);
    try std.testing.expect(roleOf(.toad) == null);
    try std.testing.expect(roleOf(.archer) == null);
    try std.testing.expect(roleOf(.ogre) == null);
}

test "a kobold is shorter than the hero but not a child" {
    // The owner's brief is "somewhat shorter than a man", and both halves matter: too close and the
    // silhouette stops reading, too small and it is comic.
    try std.testing.expect(SCALE < 0.9 and SCALE > 0.72);
    // …and NARROWER across the shoulders than the hips are wide relative to a man's — the thing that
    // makes it a different animal rather than a scaled-down person.
    try std.testing.expect(SHOULDER_HALF < heromod.SHOULDER_HALF);
    try std.testing.expect(HIP_HALF < heromod.HIP_HALF);
}

test "the berserker's recovery is a REAL opening, and his poise is glass" {
    // The whole shape of him: a flurry too fast to trade with, then a window long enough to punish.
    // If the recovery ever gets shorter than the flurry it costs, he stops being answerable.
    const flurry = @as(f32, @floatFromInt(ZERK_SWINGS_LO)) * ZERK_CHOP;
    try std.testing.expect(ZERK_RECOVER > flurry * 0.8);
    try std.testing.expect(ZERK_RECOVER > combat.FOE_HEAVY_STUN_DUR * 0.5);
    // Low poise is the other half — a foe that swings this much must be interruptible.
    try std.testing.expect(spec(.berserker).poise < spec(.slinger).poise);
}

test "the priest is the priority target, and the numbers say so" {
    // No attack, the frailest body, the longest reach, and the biggest payout: every one of those is
    // the same lesson said a different way.
    try std.testing.expect(spec(.priest).hp < spec(.berserker).hp);
    try std.testing.expect(spec(.priest).runes > spec(.berserker).runes);
    try std.testing.expect(spec(.priest).runes > spec(.slinger).runes);
    // It stands FURTHER out than the slinger does — the back line is behind the skirmish line.
    try std.testing.expect(spec(.priest).wantMin > spec(.slinger).wantMin);
    // The cast has to be worth crossing the field to stop: long enough to reach, and rare enough
    // that stopping it matters.
    try std.testing.expect(CAST_DUR > 1.0 and CAST_CD > 6.0);
    try std.testing.expect(HEAL_AMT > spec(.priest).hp * 0.4); // a real save, not a top-up
}

test "the slinger has exactly two answers, and they do not overlap" {
    // Bite range must sit INSIDE the band it wants to hold, or there is a ring where it does nothing.
    try std.testing.expect(BITE_R < spec(.slinger).wantMin);
    // …and its stone is slower than an arrow: a lobbed pebble you walk out of, not a shaft you roll.
    try std.testing.expect(STONE_SPEED < 15.0);
}

test "a hurt window latches, so one swing lands once" {
    var k = Kobold.spawnAs(.berserker, mathx.zero3, 0, 1.0, 0.5);
    k.state = .chop;
    k.t = ZERK_CHOP * (ZERK_HIT_A + ZERK_HIT_B) * 0.5; // mid-window
    k.dealt = false;
    try std.testing.expect(k.hurtOpen());
    k.markDealt();
    try std.testing.expect(!k.hurtOpen()); // …and not again on the next frame
    // A stagger mid-swing lands nothing at all — souls commitment cuts both ways.
    k.dealt = false;
    k.enterStun(.stunlight);
    try std.testing.expect(!k.hurtOpen());
    // …and the flurry is over, not paused.
    try std.testing.expectEqual(@as(u32, 0), k.chopsLeft);
}

test "the priest never reaches for an attack window" {
    // It has no attack, and `hurtOpen` is what would give it one by accident.
    var p = Kobold.spawnAs(.priest, mathx.zero3, 0, 1.0, 0.2);
    for ([_]State{ .idle, .approach, .cast, .heave, .whirl, .bite }) |s| {
        p.state = s;
        p.dealt = false;
        p.t = 0.4;
        if (s == .bite or s == .heave or s == .whirl) continue; // states it cannot enter
        try std.testing.expect(!p.hurtOpen());
    }
}
