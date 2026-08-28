const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const combat = @import("../play/combat.zig");
const heromod = @import("../play/hero.zig");
const foe = @import("foe.zig");
const anim = @import("../core/anim.zig");
const wf = @import("../world/worldfmt.zig");
const elemfx = @import("../gfx/elemfx.zig");
const sfx = @import("../core/audio.zig");
const shroommod = @import("shroom.zig");
const knightmod = @import("knight.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;
const lerpF = mathx.lerpF;
const setLocal = heromod.setHumanoid;

// THE FUNGAL DUO (owner's creature, owner's brief) — a SWORDSMAN and a MAGUS fought together. Two creatures in
// one file for the kobold warband's reason: they are one encounter, and the thing that makes either of them
// hard is the other one standing behind it. The swordsman holds you in place; the magus spends that time.
//
// **THEY DIVIDE THE GROUND BETWEEN THEM AND NEITHER CAN COVER THE OTHER'S** — the swordsman owns the ring you
// are standing in and the magus owns everywhere else, so backing off the sword walks into the sprouts and
// closing on the staff turns your back on the blade. Neither of them is answering that for you.
//
// **NEITHER KNOWS THE OTHER EXISTS.** No shared brain, no combo table, no "the mage casts while the swordsman
// commits" — that would be a script, and the LAW forbids reading anything of the hero's anyway. What makes them
// read as a pair is that their BANDS abut (`SW_SLASH_R` against `MG_FLEE_R`), and nothing else.

const H: f32 = heromod.H;

/// **BOTH ARE TALL AND STURDY** (owner, twice — "they can be a bit taller too"). Authored as METRES OVER THE
/// HERO rather than as a ratio, so the number here is the thing being judged: 0.86 puts a 2.66 m crown on the
/// swordsman, over the mushroom mage's 2.04 and under the bone knight — they loom without being a
/// boss-of-a-different-size.
pub const SCALE = (heromod.H + 0.86) / heromod.H;
/// **THE WIDTHS RIDE THE HEIGHT** — written out as their own 1.34 and 1.30 they were `SCALE` copied by hand,
/// and the first time the crown moved the body under it stayed the old build's width. The shoulder keeps its
/// 0.97 of the hip's share, which is what makes the silhouette a stalk and not a barrel.
const HIP_HALF = heromod.HIP_HALF * SCALE;
const SHOULDER_HALF = heromod.SHOULDER_HALF * SCALE * 0.97;
const REST = heromod.restHumanoid(HIP_HALF, SHOULDER_HALF, H);

const N = heromod.N;
const ROOT = heromod.ROOT;
const SPINE = heromod.SPINE;
const CHEST = heromod.CHEST;
const NECK = heromod.NECK;
const HEAD = heromod.HEAD;
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
const HELD = heromod.HELD;

const SOLES = [_]heromod.SolePatch{
    .{ .bone = ANKL, .heel = 0.048 * H, .toe = 0.192 * H, .halfW = 0.064 * H, .drop = 0.038 * H },
    .{ .bone = ANKR, .heel = 0.048 * H, .toe = 0.192 * H, .halfW = 0.064 * H, .drop = 0.038 * H },
};

// **THE PAIR READS AS ONE HOUSE AND THE TWO READ APART** — one palette, split on VALUE and not on hue. The
// swordsman is the paler one (a crusted rind) and the magus the dark one (wet gills and spore-dust), so at
// fighting range the thing coming at you and the thing standing off are told apart by brightness alone.
//
// **AUTHOR DARK AND SOLVE IT** (the law), and these were authored LIGHT. Screen goes as albedo^(1/2.2), and
// `.skin` only mottles (x0.94..1.05), so the albedo IS the read: `RIND` at (112,96,74) came back at 187 luma
// on the biggest, smoothest masses in the scene — brighter than the ground it stands on. Two naked mannequins.
// The reference is the mushroom mage's cloak at (10,13,9), which lands at 58. Solved to that bar rather than
// eyeballed: 26 puts the rind at 90 on screen and the magus's body at 63, so the pair still read APART on
// value (the whole point of the split) with neither of them a pale figure.
const RIND = rgba(26, 22, 17, 255);
const RIND_DK = rgba(16, 14, 11, 255);
const RIND_LT = rgba(42, 36, 28, 255);
const GILL = rgba(12, 8, 8, 255);
const MYC = rgba(15, 18, 13, 255);
const MYC_DK = rgba(9, 11, 8, 255);
const CAP_COL = shroommod.CAP_COL;
const CAP_DK = shroommod.CAP_DK;
const WART = shroommod.WART;
const FLESH = rgba(30, 26, 20, 255);
// **A BLADE MAY NOT BE THE BRIGHTEST THING IN THE FRAME.** At 104 it came off the chain at 170 luma against
// a body at 90 — two metres of near-white plank, and `.steel`'s specular is catastrophic on a flat face
// (`propart`'s own note), so the lit side blew out on top of that. 58 lands it at 128: still metal, no longer
// the read. The FULLER is what makes it a blade rather than a board, so the dark inlay got wider.
const STEEL = rgba(58, 61, 66, 255);
const STEEL_DK = rgba(30, 32, 36, 255);
const VENOM = rgba(150, 206, 120, 210);
const EYE = rgba(214, 232, 150, 44);

const CHAOS_CORE = elemfx.sig(.chaos).core;

/// **AND IT MUST REACH PAST WHERE THE PAIR THEMSELVES STAND** — at the 26 this was, the magus could blink
/// outside the ring its own boss bar wakes on. The comptime block by `MG_REAPPEAR_R` holds the two together.
pub const AGGRO_R: f32 = 30.0;

/// **THE MARK IS A POINT IN THE CHEST BONE'S OWN FRAME** (`foe.markOn`) — the house form, and the one both
/// bodies wear. Handed the WORLD centre instead, the transform put it a body-length past the far side of the
/// world: nothing could see it, so `game.canSee` refused the lock and `game.markSight` cast its sight ray at
/// open ground — which is how a fog gate stopped blocking their aggro.
const MARK_AT = v3(0, 0.03 * H, 0);

const SHOVE_DECAY: f32 = 6.5;
const A_PROT: f32 = 3.2;

const SPRING_STIFF: f32 = 1500.0;
const SPRING_ZETA: f32 = 0.72;
const SPRING_FALLOFF: f32 = 0.93;

const CHAN_N = 9;
const Chan = [CHAN_N]f32;
const CH_LEAN = 0;
const CH_TWIST = 1;
const CH_HEAD = 2;
const CH_RSH = 3;
const CH_RABD = 4;
const CH_REL = 5;
const CH_LSH = 6;
const CH_LEL = 7;
/// **WHERE THE KIT POINTS, AS A POSE CHANNEL** — degrees the weapon leads FORWARD of the forearm line (0 down,
/// 90 level, 180 on end), the warriors' own convention (`hero.staffFit`).
const CH_TILT = 8;

const P = struct {
    lean: f32 = 0,
    twist: f32 = 0,
    head: f32 = 0,
    rsh: f32 = 0,
    rabd: f32 = 0,
    rel: f32 = 0,
    lsh: f32 = 0,
    lel: f32 = 0,
    tilt: f32 = 0,

    pub fn chan(self: P) Chan {
        return .{ self.lean, self.twist, self.head, self.rsh, self.rabd, self.rel, self.lsh, self.lel, self.tilt };
    }
};

const PoseKey = anim.Pose(P).PoseKey;

/// **THE NINE CHANNELS IN AND OUT OF A BODY, ONCE FOR THE PAIR.** Spelled per struct they were byte-identical
/// bar the receiver, so a tenth channel meant four hand edits in lockstep. The two structs keep one-line
/// delegates (`foe.resetGroup`'s rule) because every state branch calls them by name.
fn chanOf(self: anytype) Chan {
    return .{ self.bodyLean, self.twist, self.headPitch, self.rsh, self.rabd, self.rel, self.lsh, self.lel, self.tilt };
}

fn setChan(self: anytype, c: Chan) void {
    self.bodyLean = c[CH_LEAN];
    self.twist = c[CH_TWIST];
    self.headPitch = c[CH_HEAD];
    self.rsh = c[CH_RSH];
    self.rabd = c[CH_RABD];
    self.rel = c[CH_REL];
    self.lsh = c[CH_LSH];
    self.lel = c[CH_LEL];
    self.tilt = c[CH_TILT];
}

fn settle(self: anytype, dt: f32) void {
    var want = chanOf(self);
    self.springs.chase(&want, SPRING_STIFF, SPRING_ZETA, SPRING_FALLOFF, dt);
    setChan(self, want);
}
const samplePose = anim.Pose(P).sample;

// **HE STAYS IN YOUR FACE** (owner). Fast on foot, a LUNGE that eats a gap you thought you had, and a jumpback
// that is a reposition and not a retreat — he comes straight back. The longsword is POISONED, so the fight has
// a clock on it even when you are blocking: the meter fills off chaos whether the blow lands on you or on your
// guard, and the answer is to end it rather than to out-last it.

const SW_HP: f32 = 620.0;
/// **STURDY** (owner). Sized off what a creature's flinch now means — the damage he shrugs off inside the
/// refill window — and pitched between the bone knight's 78 and a warrior's, so a light poke never stops him
/// and a committed trade does.
const SW_POISE: f32 = 62.0;
const SW_STANCE: f32 = 96.0;
const SW_RESISTS = combat.resists(.{ .chaos = 75, .fire = -45, .cold = -25, .lightning = 10 });
pub const SW_SOULS: u32 = 1500;

const SW_TURN_RATE: f32 = 3.05;
const SW_SPEED: f32 = heromod.RUN_SPEED * 0.92;
const SW_BODY_R: f32 = 0.56;
/// Metres pre-scale. **SOLVED OFF THE BODY, NOT PICKED**: the sphere sits at `SW_CENTER_F` and must take the
/// crown at `SW_TOP_F` without dropping below the knee — 1.05 m about a centre 1.45 m up on a 2.42 m body.
const SW_HURT_R: f32 = 0.78;
const SW_CENTER_F: f32 = 0.60;
const SW_TOP_F: f32 = 1.06;

const SW_DEATH_DUR: f32 = 2.05;
const SW_DISS_DUR: f32 = 1.15;
const SW_DISSOLVE = foe.Dissolve{ .rate = 62.0, .spread = 0.95, .rise = 1.05, .flake = WART };
const SW_SHOVE = foe.Push{ .light = 1.05, .heavy = 2.35 };

/// The blade, from the fist. A longsword on a 2.41 m body: 1.62 m of it past the hand.
const SW_BLADE_LEN: f32 = 0.90 * H;
const SW_KIT_R: f32 = 0.30;

/// **IT IS THE MEASURED REACH OF THE STROKE, NOT A NUMBER BESIDE ONE.** Thrown for real at a man stood
/// dead ahead, the slash lands out to 2.35 m (the judge below measures it), so a 3.3 m band handed the move
/// out at stands where the blade goes past him. A band wider than the kit is a whiff the pick called a plan.
const SW_SLASH_R: f32 = 2.2;

/// Half the arc the stroke sweeps on its own, in degrees — measured off the blade's own path, and what the
/// bearing gate adds to what the wind can turn.
const SW_SWEEP_HALF: f32 = 46.0;

/// **A BEARING THE BLADE CANNOT BE BROUGHT ROUND TO IS A HARD GATE AT THE CHOOSE, NEVER A LOWER SCORE** (the
/// ogre's law), and it is SOLVED off what the wind can actually turn, so retiming a stroke cannot leave a stale
/// number here. Thrown at a man 165 deg off, he came round to 72 and billed nothing.
///
/// **THE TWO STROKES DO NOT GET THE SAME ALLOWANCE, BECAUSE THEY ARE NOT THE SAME SHAPE.** The slash SWEEPS, so
/// a bearing it does not quite close is still crossed by the arc; the LUNGE is a thrust down one line and
/// closes nothing after the wind commits it. Given the slash's allowance it was handed out at 100 deg, came
/// round to 9 short, and drove past the man at every stand in its band.
fn swSlashArc() f32 {
    return SW_TURN_RATE * SW_SLASH_WIND + mathx.radians(SW_SWEEP_HALF);
}
fn swLungeArc() f32 {
    return SW_TURN_RATE * SW_LUNGE_WIND;
}

/// **THE STROKE IS PRICED BY ITS CLOCK, NOT BY ITS ROW** (owner: dps way too high). Measured through his own
/// update at his slash band, he billed 22.7 a second against the first boss's 22.0 — and he is one of TWO
/// bodies. A 0.44 s gather on a stroke worth as much as the knight's sweep is also barely a tell; the knight's
/// own note ("more windup now that they can hit — more predictable") is the precedent. Winds, tails and the
/// cooldown all up about 40%, which is what carries the chain down to ~13 a second.
const SW_SLASH_WIND: f32 = 0.62;
const SW_SLASH_DUR: f32 = 0.26;
const SW_SLASH_REC: f32 = 0.62;
const SW_SLASH2_CHANCE: f32 = 0.55;
const SW_SLASH_CD: f32 = 1.35;

const SW_LUNGE_MIN: f32 = 3.4;
const SW_LUNGE_MAX: f32 = 9.0;
const SW_LUNGE_WIND: f32 = 0.70;
const SW_LUNGE_DUR: f32 = 0.34;
const SW_LUNGE_REC: f32 = 0.72;
/// **THE COMMITMENT IS RARE OR IT IS NOT A COMMITMENT** (owner: lunges come too often, longer cooldowns on
/// lunges). At 3.6 it came round every 4.6 s measured, which is close enough to the slash's own cadence that
/// the whole 3.4–9.0 band read as one move on repeat; at 6.4 it is one throw in ~7.7 s.
const SW_LUNGE_CD: f32 = 6.4;
const SW_LUNGE_DIST: f32 = 7.4;
const SW_LUNGE_UP: f32 = 0.30;

const SW_BACK_DIST: f32 = 5.2;
const SW_BACK_DUR: f32 = 0.38;
const SW_BACK_UP: f32 = 0.52;
const SW_BACK_LAND: f32 = 0.20;
const SW_BACK_CD: f32 = 6.5;

/// **THE POISON IS THE CLOCK ON THE FIGHT.** Chaos builds poison (`combat.ailOf`), and a guard answers the
/// DAMAGE and not the buildup — so blocking every stroke still fills the meter, slower.
///
/// **AND THE BAR IS THE BONE KNIGHT, NOT A FEELING** (owner: they do a lot of damage). His heaviest commitment
/// is the OVERHEAD at 46 and his bread-and-butter sweep is 33. The slash was landing 56 raw — over the
/// knight's biggest single stroke, from a move that CHAINS — and the lunge 72, one and a half times it. Solved
/// back onto his scale: the slash sits under the sweep because it doubles, and the lunge sits under the
/// overhead because that is what a commitment is worth. A test below pins both against the knight's own rows.
/// …and the ROWS came down with the clock: 31 raw was the knight's own sweep out of a stroke that CHAINS, off a
/// body standing beside a second one. 23 puts it between his light swat (16) and that sweep (33). **THE CUT
/// CAME OFF THE STEEL AND NOT OFF THE VENOM** — the poison is the clock the fight runs on and its own meter
/// already rate-limits it, so taking the chaos down as well only made the fight longer at the same danger.
/// …and the STEEL came down a second time (owner: does too much damage), by the same rule: 23 raw to 18 on the
/// slash and 32 to 25 on the lunge, all of it off `dmg`, so the venom clock the fight is built on is untouched.
const SW_SLASH_HIT = combat.Hit{ .dmg = 7, .poise = 30, .stance = 26, .elem = combat.elems(.{ .chaos = 11 }) };
const SW_LUNGE_HIT = combat.Hit{ .dmg = 13, .poise = 44, .stance = 34, .launch = 3.4, .elem = combat.elems(.{ .chaos = 12 }) };

const SW_NPART = 40;

comptime {
    std.debug.assert(SW_SLASH_WIND >= foe.TELL_MIN);
    std.debug.assert(SW_LUNGE_WIND >= foe.TELL_MIN);
    std.debug.assert(SW_LUNGE_MIN > SW_SLASH_R);
    std.debug.assert(SW_SWEEP_HALF > 20.0 and SW_SWEEP_HALF < 90.0);
    std.debug.assert(SW_LUNGE_DIST + SW_SLASH_R >= SW_LUNGE_MAX);
    std.debug.assert(SW_BACK_DIST + SW_SLASH_R > SW_LUNGE_MIN);
    std.debug.assert(SW_BACK_DIST + SW_SLASH_R < SW_LUNGE_MAX);
    std.debug.assert(SW_SLASH_HIT.elem.at(.chaos) > 0 and SW_LUNGE_HIT.elem.at(.chaos) > 0);
}

/// **TOP-HEAVY AND HUNG FORWARD.** All the mass is in the shelves, so he carries it the way a thing with a
/// loaded back carries it: the trunk over its feet and the hood low and out in front. Upright at 6 deg he was
/// a soldier at attention.
const SW_CARRY = P{ .lean = 17.0, .head = -9.0, .rsh = 14.0, .rabd = 16.0, .rel = 58.0, .lsh = 10.0, .lel = 34.0, .tilt = 34.0 };

const SW_SLASH_WIND_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = SW_CARRY },
    .{ .t = 0.60, .p = .{ .lean = -8.0, .twist = -38.0, .head = 6.0, .rsh = -34.0, .rabd = 54.0, .rel = 96.0, .lsh = 22.0, .lel = 48.0, .tilt = 128.0 }, .ease = .accel },
    .{ .t = 1.00, .p = .{ .lean = -12.0, .twist = -46.0, .head = 8.0, .rsh = -44.0, .rabd = 62.0, .rel = 104.0, .lsh = 26.0, .lel = 52.0, .tilt = 148.0 } },
};

const SW_SLASH_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = -12.0, .twist = -46.0, .head = 8.0, .rsh = -44.0, .rabd = 62.0, .rel = 104.0, .lsh = 26.0, .lel = 52.0, .tilt = 148.0 } },
    .{ .t = 0.46, .p = .{ .lean = 14.0, .twist = 40.0, .head = -8.0, .rsh = 74.0, .rabd = 10.0, .rel = 16.0, .lsh = -14.0, .lel = 22.0, .tilt = 96.0 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = 11.0, .twist = 48.0, .head = -6.0, .rsh = 82.0, .rabd = 6.0, .rel = 10.0, .lsh = -20.0, .lel = 18.0, .tilt = 74.0 } },
};

const SW_SLASH2_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = 11.0, .twist = 48.0, .head = -6.0, .rsh = 82.0, .rabd = 6.0, .rel = 10.0, .lsh = -20.0, .lel = 18.0, .tilt = 74.0 } },
    .{ .t = 0.44, .p = .{ .lean = 8.0, .twist = -34.0, .head = -4.0, .rsh = 30.0, .rabd = 58.0, .rel = 30.0, .lsh = 30.0, .lel = 26.0, .tilt = 100.0 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = 4.0, .twist = -40.0, .head = -2.0, .rsh = 20.0, .rabd = 64.0, .rel = 38.0, .lsh = 34.0, .lel = 30.0, .tilt = 88.0 } },
};

const SW_LUNGE_WIND_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = SW_CARRY },
    .{ .t = 0.55, .p = .{ .lean = -18.0, .twist = -22.0, .head = 10.0, .rsh = -20.0, .rabd = 22.0, .rel = 118.0, .lsh = 16.0, .lel = 62.0, .tilt = 112.0 }, .ease = .accel },
    .{ .t = 1.00, .p = .{ .lean = -24.0, .twist = -28.0, .head = 13.0, .rsh = -26.0, .rabd = 26.0, .rel = 128.0, .lsh = 20.0, .lel = 68.0, .tilt = 120.0 } },
};

const SW_LUNGE_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = -24.0, .twist = -28.0, .head = 13.0, .rsh = -26.0, .rabd = 26.0, .rel = 128.0, .lsh = 20.0, .lel = 68.0, .tilt = 120.0 } },
    .{ .t = 0.30, .p = .{ .lean = 26.0, .twist = 16.0, .head = -10.0, .rsh = 84.0, .rabd = 4.0, .rel = 6.0, .lsh = -26.0, .lel = 14.0, .tilt = 92.0 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = 22.0, .twist = 12.0, .head = -8.0, .rsh = 78.0, .rabd = 6.0, .rel = 10.0, .lsh = -22.0, .lel = 18.0, .tilt = 88.0 } },
};

const SW_BACK_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = 22.0, .twist = 12.0, .head = -8.0, .rsh = 78.0, .rabd = 6.0, .rel = 10.0, .lsh = -22.0, .lel = 18.0, .tilt = 88.0 } },
    .{ .t = 0.40, .p = .{ .lean = -30.0, .head = 16.0, .rsh = 6.0, .rabd = 40.0, .rel = 84.0, .lsh = 34.0, .lel = 56.0, .tilt = 60.0 }, .ease = .decel },
    .{ .t = 1.00, .p = SW_CARRY, .ease = .decel },
};

const SW_REC_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = 11.0, .twist = 48.0, .head = -6.0, .rsh = 82.0, .rabd = 6.0, .rel = 10.0, .lsh = -20.0, .lel = 18.0, .tilt = 74.0 } },
    .{ .t = 1.00, .p = SW_CARRY, .ease = .decel },
};

const SwState = enum { idle, stride, slash_wind, slash, slash2, lunge_wind, lunge, back, recover, stunlight, stunheavy, dead };

const SwChoice = enum { hold, close, slash, lunge, back };

/// The pick, with no world near it, so a test can walk every band. `off` is radians the quarry stands off his
/// own bearing — a fact about where two bodies are, which is what the LAW allows a decision to read.
fn swClassify(dist: f32, off: f32, slashReady: bool, lungeReady: bool, backReady: bool, crowded: bool) SwChoice {
    if (dist > AGGRO_R) return .hold;
    // **THE JUMPBACK IS FIRST AND IT IS THE ONLY ONE THAT LOOKS INWARD.** `crowded` is his OWN clock saying he
    // has been stood on top of for long enough — never a read of what the hero did (the LAW).
    if (crowded and backReady) return .back;
    const a = @abs(off);
    if (dist <= SW_SLASH_R and slashReady and a <= swSlashArc()) return .slash;
    if (lungeReady and dist >= SW_LUNGE_MIN and dist <= SW_LUNGE_MAX and a <= swLungeArc()) return .lunge;
    // **OFF THE GATE HE LOOMS, AND LOOMING IS THE TURN.** `.close` walks at him and idle faces him at the full
    // rate, so a gate is never a hole: the bearing it refused is the bearing he spends the next beat fixing.
    return .close;
}

// **DEFENSIVE AND STRATEGIC** (owner). It never closes. It holds a band, throws quick chaos orbs to wear you
// down, and SPROUTS a bunch of caps where you are standing — which grow, glow and then go off, so the ground
// itself starts asking you to move. Threatened, it DISSOLVES: a slow fade that leaves slumber mist behind it,
// and it comes back up somewhere else.

const MG_HP: f32 = 520.0;
const MG_POISE: f32 = 34.0;
const MG_STANCE: f32 = 62.0;
const MG_RESISTS = combat.resists(.{ .chaos = 75, .fire = -55, .cold = -15, .lightning = -20 });
pub const MG_SOULS: u32 = 1500;

const MG_TURN_RATE: f32 = 2.5;
const MG_SPEED: f32 = heromod.WALK_SPEED * 0.72;
const MG_BODY_R: f32 = 0.52;
const MG_HURT_R: f32 = 0.74;
const MG_CENTER_F: f32 = 0.62;
const MG_TOP_F: f32 = 1.08;

const MG_DEATH_DUR: f32 = 1.85;
const MG_DISS_DUR: f32 = 1.10;
const MG_DISSOLVE = foe.Dissolve{ .rate = 58.0, .spread = 0.9, .rise = 1.0, .flake = CAP_DK };
const MG_SHOVE = foe.Push{ .light = 1.20, .heavy = 2.70 };

const MG_FLEE_R: f32 = 7.0;
const MG_KEEP_R: f32 = 16.0;
const MG_DRIFT_DUR: f32 = 0.85;

pub const ORB_SPEED: f32 = 15.0;
pub const ORB_R: f32 = 0.20;
pub const ORB_LIFE: f32 = 2.6;
/// ATTRITION, and the knight's gas is the tier: 14 raw, thrown often, and never the thing that kills you.
pub const ORB_HIT = combat.Hit{ .poise = 14, .elem = combat.elems(.{ .chaos = 14 }) };
const MG_ORB_WIND: f32 = 0.36;
const MG_ORB_DUR: f32 = 0.16;
const MG_ORB_REC: f32 = 0.26;
/// **THE ATTRITION IS A DRIP, NOT A STREAM** (owner: chaos orbs could come out a bit slower) — the cadence and
/// not the flight, which stays at `ORB_SPEED`.
const MG_ORB_CD: f32 = 2.3;
const MG_ORB_RELEASE_K: f32 = 0.34;
/// **DERIVED OFF THE RING IT WALKS OUT OF, NOT PICKED.** `.back` is answered before either cast, so any part
/// of a spell's band inside `MG_FLEE_R` is a band it can never be asked for — a dead number that reads as tuning.
const MG_ORB_MIN: f32 = MG_FLEE_R;

pub const CAP_GROW: f32 = 1.9;
pub const CAP_GLOW: f32 = 0.85;
pub const CAP_BURST_R: f32 = 3.1;
/// **A BUNCH IS FOUR OF THESE AND THEY POP IN A RUN**, so the cap is priced as one of four and not as one
/// blow: at 40 apiece, standing in the middle of a bunch was 160 raw — more than three of the knight's overheads.
pub const CAP_HIT = combat.Hit{ .poise = 34, .stance = 22, .launch = 2.2, .elem = combat.elems(.{ .chaos = 20 }) };
const MG_SPROUT_WIND: f32 = 0.78;
const MG_SPROUT_DUR: f32 = 0.30;
const MG_SPROUT_CD: f32 = 6.2;
const MG_SPROUT_MIN: f32 = MG_FLEE_R;
const MG_SPROUT_MAX: f32 = 18.0;
const MG_BUNCH: usize = 4;
const MG_BUNCH_R: f32 = 1.8;
/// **THEY DO NOT ALL GO OFF ON ONE FRAME.** A group hands back ONE blow a frame (`foe.worseBlow`), so a bunch
/// sown on one clock detonated as a single blow and standing in the middle of four cost exactly what standing
/// beside one did. Spread over their own clocks they pop as a run, which is both the cost and the picture.
const CAP_STAGGER: f32 = 0.45;

/// **IT DISSOLVES SLOWLY WHEN THREATENED** (owner) — slow enough to be interrupted, which is what makes closing
/// on it worth doing. `threatened` is its OWN clock and its own health, never a read of him.
const MG_FADE_OUT: f32 = 1.15;
const MG_GONE_DUR: f32 = 0.55;
const MG_FADE_IN: f32 = 0.60;
const MG_FADE_CD: f32 = 9.0;
const MG_REAPPEAR_R: f32 = 13.0;
pub const MIST_R: f32 = 3.4;
pub const MIST_LIFE: f32 = 5.5;
pub const MIST_BUILD: f32 = 16.0;

const MG_NPART = 72;

comptime {
    std.debug.assert(MG_ORB_WIND >= foe.TELL_MIN);
    std.debug.assert(MG_SPROUT_WIND >= foe.TELL_MIN);
    std.debug.assert(MG_FLEE_R < MG_KEEP_R);
    std.debug.assert(MG_SPROUT_MIN < MG_KEEP_R and MG_SPROUT_MAX > MG_KEEP_R);
    std.debug.assert(MG_SPROUT_MIN >= MG_FLEE_R and MG_ORB_MIN >= MG_FLEE_R);
    std.debug.assert(MG_FADE_OUT > MG_ORB_WIND * 2.0);
    std.debug.assert(MG_REAPPEAR_R > MG_FLEE_R);
    std.debug.assert(CAP_GROW > CAP_GLOW * 2.0);
    // **A CREATURE MAY NOT STAND FURTHER OFF THAN THE RING ITS OWN BAR WAKES ON.** Keeping to 16 and blinking
    // 13 put the magus 29 m out against an `AGGRO_R` of 26, so the bar dropped mid-fight whenever `roused` had
    // lapsed (owner). The room answers it now (`game.sealedInWith`), and this stops the NEXT blink re-authoring it.
    std.debug.assert(MG_KEEP_R + MG_REAPPEAR_R <= AGGRO_R);
}

const MG_CARRY = P{ .lean = 4.0, .head = 3.0, .rsh = 16.0, .rabd = 12.0, .rel = 26.0, .lsh = 8.0, .lel = 20.0, .tilt = 166.0 };

const MG_ORB_WIND_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = MG_CARRY },
    .{ .t = 0.60, .p = .{ .lean = -6.0, .twist = -14.0, .head = 5.0, .rsh = 18.0, .rabd = 14.0, .rel = 30.0, .lsh = 40.0, .lel = 92.0, .tilt = 150.0 }, .ease = .accel },
    .{ .t = 1.00, .p = .{ .lean = -9.0, .twist = -18.0, .head = 6.0, .rsh = 18.0, .rabd = 14.0, .rel = 30.0, .lsh = 46.0, .lel = 100.0, .tilt = 142.0 } },
};

const MG_ORB_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = -9.0, .twist = -18.0, .head = 6.0, .rsh = 18.0, .rabd = 14.0, .rel = 30.0, .lsh = 46.0, .lel = 100.0, .tilt = 142.0 } },
    .{ .t = 0.34, .p = .{ .lean = 12.0, .twist = 12.0, .head = -6.0, .rsh = 18.0, .rabd = 14.0, .rel = 30.0, .lsh = 116.0, .lel = 16.0, .tilt = 118.0 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = 9.0, .twist = 8.0, .head = -4.0, .rsh = 18.0, .rabd = 14.0, .rel = 30.0, .lsh = 124.0, .lel = 10.0, .tilt = 112.0 } },
};

const MG_SPROUT_WIND_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = MG_CARRY },
    .{ .t = 0.58, .p = .{ .lean = -14.0, .head = 14.0, .rsh = -52.0, .rabd = 28.0, .rel = 44.0, .lsh = -44.0, .lel = 50.0, .tilt = 176.0 }, .ease = .accel },
    .{ .t = 1.00, .p = .{ .lean = -19.0, .head = 18.0, .rsh = -66.0, .rabd = 32.0, .rel = 38.0, .lsh = -56.0, .lel = 44.0, .tilt = 180.0 } },
};

const MG_SPROUT_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = -19.0, .head = 18.0, .rsh = -66.0, .rabd = 32.0, .rel = 38.0, .lsh = -56.0, .lel = 44.0, .tilt = 180.0 } },
    .{ .t = 0.38, .p = .{ .lean = 24.0, .head = -14.0, .rsh = 54.0, .rabd = 10.0, .rel = 14.0, .lsh = 44.0, .lel = 18.0, .tilt = 14.0 }, .ease = .snap },
    .{ .t = 1.00, .p = .{ .lean = 20.0, .head = -11.0, .rsh = 48.0, .rabd = 8.0, .rel = 16.0, .lsh = 40.0, .lel = 20.0, .tilt = 22.0 } },
};

const MG_REC_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = .{ .lean = 20.0, .head = -11.0, .rsh = 48.0, .rabd = 8.0, .rel = 16.0, .lsh = 40.0, .lel = 20.0, .tilt = 22.0 } },
    .{ .t = 1.00, .p = MG_CARRY, .ease = .decel },
};

const MG_FADE_KEYS = [_]PoseKey{
    .{ .t = 0.00, .p = MG_CARRY },
    .{ .t = 1.00, .p = .{ .lean = 26.0, .head = -22.0, .rsh = 4.0, .rabd = 4.0, .rel = 118.0, .lsh = 4.0, .lel = 112.0, .tilt = 150.0 }, .ease = .accel },
};

const MgState = enum { idle, drift, orb_wind, orb_throw, sprout_wind, sprout, recover, fade_out, gone, fade_in, stunlight, stunheavy, dead };

const MgChoice = enum { hold, back, keep, orb, sprout, vanish };

fn mgClassify(dist: f32, orbReady: bool, sproutReady: bool, fadeReady: bool, pressed: bool) MgChoice {
    if (dist > AGGRO_R) return .hold;
    // **PRESSED IS ITS OWN CLOCK AND ITS OWN BAR** — how long something has been inside its skirt and how much
    // of it is left, never what the hero is holding or pressing.
    if (pressed and fadeReady) return .vanish;
    if (dist < MG_FLEE_R) return .back;
    if (sproutReady and dist >= MG_SPROUT_MIN and dist <= MG_SPROUT_MAX) return .sprout;
    if (orbReady and dist >= MG_ORB_MIN) return .orb;
    return .keep;
}

pub const CAP_N: usize = 24;

/// One cap of a bunch. It has no bar and cannot be killed — it is GROUND, and the answer to it is your feet.
pub const Cap = struct {
    live: bool = false,
    at: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    r: f32 = 0.5,
    seed: f32 = 0,
    burst: bool = false,

    /// 0 while it grows, climbing to 1 over the glow — the picture and the clock are one number.
    pub fn heat(self: *const Cap) f32 {
        if (self.t <= CAP_GROW) return 0;
        return mathx.clampF((self.t - CAP_GROW) / CAP_GLOW, 0, 1);
    }
    pub fn grown(self: *const Cap) f32 {
        return mathx.clampF(self.t / CAP_GROW, 0, 1);
    }
    /// Sown a beat apart, so `t` starts NEGATIVE and a cap is nothing at all until its own clock opens.
    pub fn showing(self: *const Cap) bool {
        return self.live and self.t > 0;
    }
};

pub const MIST_N: usize = 8;

pub const Mist = struct {
    live: bool = false,
    at: rl.Vector3 = mathx.zero3,
    t: f32 = 0,

    pub fn amt(self: *const Mist) f32 {
        if (!self.live) return 0;
        const u = mathx.clampF(self.t / MIST_LIFE, 0, 1);
        return mathx.smoothstep(0, 0.14, u) * (1.0 - mathx.smoothstep(0.55, 1.0, u));
    }
    pub fn covers(self: *const Mist, at: rl.Vector3) bool {
        return self.live and self.amt() > 0.10 and mathx.distXZ(self.at, at) <= MIST_R;
    }
};

pub const ORB_N: usize = 12;

pub const Orb = struct {
    live: bool = false,
    at: rl.Vector3 = mathx.zero3,
    vel: rl.Vector3 = mathx.zero3,
    t: f32 = 0,
    spin: f32 = 0,
};

/// **HOW LONG SOMETHING HAS TO STAND ON HIM BEFORE HE TAKES THE GROUND BACK.** Over two of his own strokes, so
/// the jumpback is what a sustained press buys and never a reflex.
const SW_CROWD_HOLD: f32 = 3.2;

pub const SwModel = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) SwModel {
        return .{ .bone = swBones(), .mat = gfx.material(shader, "fungal swordsman") };
    }
    pub fn setShader(self: *SwModel, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const SwModel, k: *const Swordsman) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, k.xf[i]);
    }
};

pub const Swordsman = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// **THE FIELD A UNIT OWES ITS ORDERS** (`foe.Post`), stamped at spawn off the map's `ai=` and `wp=`.
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: SwState = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    slashCd: f32 = 0,
    lungeCd: f32 = 0,
    backCd: f32 = 0,
    /// **HOW LONG HE HAS BEEN STOOD ON TOP OF**, in seconds, and the only thing that asks for the jumpback. A
    /// distance and a clock — the world as any body standing in it could see it — never a read of the man.
    crowd: f32 = 0,
    /// The follow-through is rolled at the FIRST stroke, so the second is a fact by the time the first lands.
    doubling: bool = false,

    hop: f32 = 0,
    hopDone: f32 = 0,
    hopDir: rl.Vector3 = mathx.zero3,

    heroHit: ?combat.Hit = null,
    dealt: bool = false,
    /// **WHICH RECOVER HE OWES.** `enter` clears `hopDone` on the way into `.recover`, so reading the leap off
    /// that gave the lunge the SLASH's recover every time — a 9.9 m commitment with a 0.40 s tail on it.
    fromLeap: bool = false,

    moveDir: rl.Vector3 = mathx.zero3,
    homing: bool = false,

    bodyLean: f32 = 0,
    twist: f32 = 0,
    headPitch: f32 = 0,
    rsh: f32 = 0,
    rabd: f32 = 0,
    rel: f32 = 0,
    lsh: f32 = 0,
    lel: f32 = 0,
    tilt: f32 = 0,
    springs: anim.SpringBank(CHAN_N) = .{},

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(SW_HP, SW_POISE, SW_STANCE).withRes(SW_RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,

    fade: f32 = 0,
    gone: bool = false,

    parts: [SW_NPART]foe.Particle = [_]foe.Particle{.{}} ** SW_NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(3),
    rng: mathx.Rng = mathx.Rng.init(5),

    /// Where the blade's two ends were LAST frame. The hurt shape is what it swept, never a yaw-guessed sector.
    wpnWas: [2]rl.Vector3 = .{ mathx.zero3, mathx.zero3 },

    parry: foe.Parry = .{},
    parried: bool = false,

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Swordsman {
        var k = Swordsman{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .vit = combat.Vitals.initFoe(SW_HP, SW_POISE, SW_STANCE).withRes(SW_RESISTS),
        };
        k.rest = REST;
        k.fxRng = foe.fxStream(seed, 51103.0, 0x5A1);
        k.rng = foe.fxStream(seed, 22679.0, 0x5A2);
        k.springs.seat(SW_CARRY.chan());
        k.chanSet(SW_CARRY.chan());
        k.pose();
        k.wpnWas = k.bladeSeg();
        return k;
    }

    pub fn kind(_: *const Swordsman) wf.FoeKind {
        return .fungal_swordsman;
    }
    pub fn centerWorld(self: *const Swordsman) rl.Vector3 {
        return foe.bodyPoint(self.pos, SW_CENTER_F * H, self.scale, self.hop);
    }
    pub fn topWorld(self: *const Swordsman) rl.Vector3 {
        return foe.bodyPoint(self.pos, SW_TOP_F * H, self.scale, self.hop);
    }
    pub fn lockPoint(self: *const Swordsman) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], MARK_AT);
    }
    pub fn hurtRadius(self: *const Swordsman) f32 {
        return SW_HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Swordsman) f32 {
        return SW_BODY_R * self.scale;
    }
    pub fn alive(self: *const Swordsman) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Swordsman) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Swordsman) bool {
        return self.state == .stunlight or self.state == .stunheavy;
    }
    pub fn airborne(self: *const Swordsman) bool {
        return self.hop > foe.AIRBORNE_LIFT;
    }
    fn hopOf(self: *const Swordsman) f32 {
        return self.hop / self.scale;
    }
    pub fn flashFrac(self: *const Swordsman) f32 {
        return self.flash / foe.FLASH_DUR;
    }

    fn fdir(self: *const Swordsman) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Swordsman, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, SW_TURN_RATE, dt);
    }

    pub fn navWant(self: *const Swordsman, hero: rl.Vector3) ?rl.Vector3 {
        _ = hero;
        if (self.state != .stride) return null;
        if (self.homing) return self.home;
        return mathx.addV(self.pos, self.moveDir);
    }

    pub fn bladeSeg(self: *const Swordsman) [2]rl.Vector3 {
        const grip = rl.math.vector3Transform(mathx.zero3, self.xf[HELD]);
        const tip = rl.math.vector3Transform(v3(0, SW_BLADE_LEN, 0), self.xf[HELD]);
        return .{ grip, tip };
    }

    fn chanGet(self: *const Swordsman) Chan {
        return chanOf(self);
    }
    fn chanSet(self: *Swordsman, c: Chan) void {
        setChan(self, c);
    }
    fn settlePose(self: *Swordsman, dt: f32) void {
        settle(self, dt);
    }

    fn enter(self: *Swordsman, s: SwState) void {
        self.state = s;
        self.t = 0;
        self.dealt = false;
        if (s != .recover) self.fromLeap = false;
        if (s != .lunge and s != .back) {
            self.hop = 0;
            self.hopDone = 0;
        }
    }

    pub fn update(self: *Swordsman, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.justDied = false;
        self.parried = false;
        self.heroHit = null;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.stateStep(dt, hero, bounds);
        self.takeParry();
        self.tryHit(blade);
        return self.heroHit;
    }

    fn stateStep(self: *Swordsman, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer if (!self.airborne()) grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);

        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.slashCd = mathx.maxF(0, self.slashCd - dt);
        self.lungeCd = mathx.maxF(0, self.lungeCd - dt);
        self.backCd = mathx.maxF(0, self.backCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        if (d <= SW_SLASH_R) self.crowd += dt else self.crowd = mathx.maxF(0, self.crowd - dt * 1.6);

        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.chanSet(SW_CARRY.chan());
                // **ORDERS ARE WHAT IT DOES BEFORE IT HAS SEEN ANYBODY** (`foe.postDrive`), refused inside the ring.
                _ = foe.postDrive(self, dt, bounds, SW_SPEED, d, AGGRO_R, SW_TURN_RATE, &movedDist, &moveSpeed, &moveYaw);
                if (self.t >= 0.12) self.decide(d, hero);
            },
            .stride => {
                self.faceToward(hero, dt);
                const way = self.nav.along(self.moveDir);
                moveSpeed = SW_SPEED;
                const moved = moveSpeed * dt * self.chill.travel();
                mathx.stepXZ(&self.pos, way, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(way);
                self.chanSet(SW_CARRY.chan());
                if (self.homing and mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) {
                    self.homing = false;
                    self.enter(.idle);
                } else if (self.t >= 0.22) self.decide(d, hero);
            },
            .slash_wind => {
                self.faceToward(hero, dt);
                self.chanSet(samplePose(&SW_SLASH_WIND_KEYS, mathx.clampF(self.t / SW_SLASH_WIND, 0, 1)));
                if (self.t >= SW_SLASH_WIND) {
                    sfx.world(.swing_heavy, self.pos);
                    self.enter(.slash);
                }
            },
            .slash => {
                // A third of a turn inside the stroke: the cut tracks a walking man and not a rolling one.
                self.faceToward(hero, dt * 0.33);
                self.chanSet(samplePose(&SW_SLASH_KEYS, mathx.clampF(self.t / SW_SLASH_DUR, 0, 1)));
                self.tryReach(hero);
                if (self.t >= SW_SLASH_DUR) {
                    if (self.doubling) {
                        sfx.world(.swing_light, self.pos);
                        self.enter(.slash2);
                    } else {
                        self.slashCd = SW_SLASH_CD;
                        self.enter(.recover);
                    }
                }
            },
            .slash2 => {
                // **THE RETURN CUT CANNOT BE AIMED.** It is the follow-through of the first, so where the first
                // was going is where this one goes — which is what makes stepping out of the first one work.
                self.chanSet(samplePose(&SW_SLASH2_KEYS, mathx.clampF(self.t / SW_SLASH_DUR, 0, 1)));
                self.tryReach(hero);
                if (self.t >= SW_SLASH_DUR) {
                    self.doubling = false;
                    self.slashCd = SW_SLASH_CD;
                    self.enter(.recover);
                }
            },
            .lunge_wind => {
                self.faceToward(hero, dt);
                self.chanSet(samplePose(&SW_LUNGE_WIND_KEYS, mathx.clampF(self.t / SW_LUNGE_WIND, 0, 1)));
                if (self.t >= SW_LUNGE_WIND) {
                    self.hopDir = self.fdir();
                    sfx.world(.swing_heavy, self.pos);
                    self.enter(.lunge);
                    self.fromLeap = true;
                }
            },
            .lunge => {
                self.chanSet(samplePose(&SW_LUNGE_KEYS, mathx.clampF(self.t / SW_LUNGE_DUR, 0, 1)));
                const u = mathx.clampF(self.t / SW_LUNGE_DUR, 0, 1);
                const want = SW_LUNGE_DIST * (1.0 - (1.0 - u) * (1.0 - u)) * self.scale;
                mathx.stepXZ(&self.pos, self.hopDir, want - self.hopDone, bounds);
                self.hopDone = want;
                self.hop = SW_LUNGE_UP * mathx.sinf(u * std.math.pi) * self.scale;
                self.tryReach(hero);
                if (self.t >= SW_LUNGE_DUR) {
                    self.hop = 0;
                    self.lungeCd = SW_LUNGE_CD;
                    self.enter(.recover);
                }
            },
            .back => {
                self.faceToward(hero, dt * 0.5);
                self.chanSet(samplePose(&SW_BACK_KEYS, mathx.clampF(self.t / (SW_BACK_DUR + SW_BACK_LAND), 0, 1)));
                const u = mathx.clampF(self.t / SW_BACK_DUR, 0, 1);
                const want = SW_BACK_DIST * (1.0 - (1.0 - u) * (1.0 - u)) * self.scale;
                mathx.stepXZ(&self.pos, self.hopDir, want - self.hopDone, bounds);
                self.hopDone = want;
                self.hop = SW_BACK_UP * mathx.sinf(u * std.math.pi) * self.scale;
                if (self.t >= SW_BACK_DUR + SW_BACK_LAND) {
                    self.hop = 0;
                    self.crowd = 0;
                    self.backCd = SW_BACK_CD;
                    // Re-measured after the leap, through the leash: he came back to a different fight.
                    self.decide(foe.senseHero(&self.leash, self.pos, hero, AGGRO_R), hero);
                }
            },
            .recover => {
                if (d <= AGGRO_R) self.faceToward(hero, dt * 0.55);
                const dur = if (self.fromLeap) SW_LUNGE_REC else SW_SLASH_REC;
                self.chanSet(samplePose(&SW_REC_KEYS, mathx.clampF(self.t / dur, 0, 1)));
                if (self.t >= dur) self.enter(.idle);
            },
            .stunlight, .stunheavy => {
                self.chanSet(SW_CARRY.chan());
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .dead => {
                foe.dissipate(self, dt, SW_DEATH_DUR, SW_DISS_DUR, SW_DISSOLVE);
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.settlePose(dt);
        self.wpnWas = self.bladeSeg();
        self.pose();
    }

    fn decide(self: *Swordsman, dist: f32, toward: rl.Vector3) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            self.moveDir = mathx.dirXZ(self.pos, self.home);
            return self.enter(.stride);
        }
        self.homing = false;
        // **THE BEARING IS TO THE QUARRY AND NOT TO HIS OWN NOSE.** Every branch above has spent the frame
        // facing him, so the two are close — but a gate measured off the thing it gates on is the whole point.
        const f = mathx.dirXZ(self.pos, toward);
        const off = mathx.wrapPi(mathx.headingXZ(f) - self.facing);
        switch (swClassify(dist, off, self.slashCd <= 0, self.lungeCd <= 0, self.backCd <= 0, self.crowd >= SW_CROWD_HOLD)) {
            .slash => {
                self.doubling = self.rng.float() < SW_SLASH2_CHANCE;
                self.enter(.slash_wind);
            },
            .lunge => self.enter(.lunge_wind),
            .back => {
                if (foe.canLeap(&self.root)) {
                    self.hopDir = mathx.scaleV(f, -1.0);
                    self.enter(.back);
                } else {
                    // Held feet cannot spring (`foe.canLeap`). He stays and swings, which is his answer anyway.
                    self.crowd = 0;
                    self.enter(.idle);
                }
            },
            .close => {
                // A small seeded drift off the bearing, so two of him do not walk one groove and a straight
                // backpedal does not hold him at range.
                const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
                const lat = mathx.scaleV(mathx.perpXZ(f), side * 0.22);
                self.moveDir = mathx.normV(mathx.addV(f, lat));
                self.enter(.stride);
            },
            .hold => {
                if (mathx.distXZ(self.pos, foe.homeFor(self)) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.moveDir = mathx.dirXZ(self.pos, self.home);
                    self.enter(.stride);
                } else self.enter(.idle);
            },
        }
    }

    /// **SECONDS UNTIL THE POINT ARRIVES**, or null if nothing is coming. Off the pose track's own snap key, so
    /// retiming a stroke retimes its parry window and cannot leave one behind.
    fn toImpact(self: *const Swordsman) ?f32 {
        return switch (self.state) {
            .slash_wind => SW_SLASH_WIND - self.t + SW_SLASH_DUR * 0.46,
            .slash => SW_SLASH_DUR * 0.46 - self.t,
            .lunge_wind => SW_LUNGE_WIND - self.t + SW_LUNGE_DUR * 0.30,
            .lunge => SW_LUNGE_DUR * 0.30 - self.t,
            else => null,
        };
    }

    /// **THE RETURN CUT IS NOT PARRYABLE AND THAT IS THE POINT OF IT** — `.slash2` is off the follow-through
    /// with no wind of its own, so there is nothing to read and nothing to catch. Read the FIRST one.
    fn parryable(self: *const Swordsman) ?f32 {
        const left = self.toImpact() orelse return null;
        if (!foe.inParryWindow(left)) return null;
        return foe.hurtReach(SW_KIT_R, self.scale) + SW_BLADE_LEN * self.scale * 0.5;
    }

    pub fn takeParry(self: *Swordsman) void {
        const reach = self.parryable() orelse return;
        if (!foe.caught(self, reach)) return;
        self.slashCd = SW_SLASH_CD;
        self.lungeCd = SW_LUNGE_CD;
        self.doubling = false;
        self.venom(self.bladeSeg()[1], 14);
        sfx.world(.duo_sword_hurt, self.pos);
        switch (self.vit.hit(combat.PARRY_HIT)) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light, .none => self.enterStun(false),
        }
    }

    /// One blow per stroke, off what the blade actually swept — the warrior's rule.
    fn tryReach(self: *Swordsman, hero: rl.Vector3) void {
        if (self.dealt) return;
        const r = foe.hurtReach(SW_KIT_R, self.scale);
        if (!foe.weaponReaches(self.wpnWas, self.bladeSeg(), hero, r)) return;
        self.heroHit = if (self.state == .lunge) SW_LUNGE_HIT else SW_SLASH_HIT;
        self.dealt = true;
        self.leash.noteCombat();
        self.venom(self.bladeSeg()[1], 7);
    }

    pub fn tryHit(self: *Swordsman, blade_: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade_) orelse return;
        const heavy = foe.wounded(self, s, blade_, SW_SHOVE);
        self.venom(s.contact, if (heavy) 10 else 5);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    fn enterStun(self: *Swordsman, heavy: bool) void {
        if (self.state == .dead) return;
        sfx.world(.duo_sword_hurt, self.pos);
        self.enter(if (heavy) .stunheavy else .stunlight);
    }

    fn enterDeath(self: *Swordsman) void {
        if (self.state == .dead) return;
        sfx.world(.duo_sword_die, self.pos);
        self.justDied = true;
        self.enter(.dead);
    }

    pub fn stagger(self: *Swordsman, heavy: bool) void {
        if (self.state == .dead) return;
        self.enterStun(heavy);
    }

    /// **A BOSS STAYS DEAD ACROSS A LOAD** (`save.Slot.bosses`) — put down with no death to play, because the
    /// one it earned was played in the run that killed it.
    pub fn markSlain(self: *Swordsman) void {
        self.vit.hp = 0;
        self.vit.dead = true;
        self.state = .dead;
        self.t = SW_DEATH_DUR + SW_DISS_DUR;
        self.fade = 1;
        self.gone = true;
    }

    fn venom(self: *Swordsman, at: rl.Vector3, n: usize) void {
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, v3(0, 1, 0), .chaos, n, self.scale);
    }

    fn stunAmount(self: *const Swordsman) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t / combat.foeStunDur(false), false),
            .stunheavy => foe.stunCurve(self.t / combat.foeStunDur(true), true),
            else => 0,
        };
    }

    pub fn pose(self: *Swordsman) void {
        poseBody(self, SW_DEATH_DUR);
    }

    pub fn draw(self: *const Swordsman, model: *const SwModel) void {
        if (self.gone) return;
        model.draw(self);
    }
    pub fn drawFx(self: *const Swordsman) void {
        foe.drawParticles(&self.parts);
    }
};

/// **HOW LONG SOMETHING HAS TO BE INSIDE ITS SKIRT BEFORE IT LEAVES**, and how thin it has to be for that clock
/// to start at all. Both are its own: a clock and a bar, never a read of what he is doing.
const MG_PRESS_HOLD: f32 = 2.4;
const MG_PRESS_HP: f32 = 0.86;

pub const MgModel = struct {
    bone: [N]rl.Mesh,
    mat: rl.Material,

    pub fn init(shader: rl.Shader) MgModel {
        return .{ .bone = mgBones(), .mat = gfx.material(shader, "fungal magus") };
    }
    pub fn setShader(self: *MgModel, sh: rl.Shader) void {
        self.mat.shader = sh;
    }
    pub fn draw(self: *const MgModel, k: *const Magus) void {
        for (0..N) |i| rl.drawMesh(self.bone[i], self.mat, k.xf[i]);
    }
};

pub const Magus = struct {
    pos: rl.Vector3 = mathx.zero3,
    home: rl.Vector3 = mathx.zero3,
    leash: foe.Leash = .{},
    /// **THE FIELD A UNIT OWES ITS ORDERS** (`foe.Post`), stamped at spawn off the map's `ai=` and `wp=`.
    post: foe.Post = .{},
    root: combat.Root = .{},
    chill: combat.Chill = .{},
    threat: foe.Threat = .{},
    nav: foe.Nav = .{},

    facing: f32 = 0,
    scale: f32 = SCALE,
    seed: f32 = 0,

    state: MgState = .idle,
    t: f32 = 0,
    elapsed: f32 = 0,
    orbCd: f32 = 0,
    sproutCd: f32 = 0,
    fadeCd: f32 = 0,
    press: f32 = 0,

    /// Where it will come back up. Chosen at the START of the fade, so the mist it leaves is on the way out.
    returnTo: rl.Vector3 = mathx.zero3,

    heroHit: ?combat.Hit = null,
    /// A one-frame edge: an orb left the staff, or a bunch was sown. The pools belong to the group.
    threw: bool = false,
    threwFrom: rl.Vector3 = mathx.zero3,
    sowed: bool = false,
    sowAt: rl.Vector3 = mathx.zero3,
    misted: bool = false,
    mistAt: rl.Vector3 = mathx.zero3,

    moveDir: rl.Vector3 = mathx.zero3,
    homing: bool = false,

    bodyLean: f32 = 0,
    twist: f32 = 0,
    headPitch: f32 = 0,
    rsh: f32 = 0,
    rabd: f32 = 0,
    rel: f32 = 0,
    lsh: f32 = 0,
    lel: f32 = 0,
    tilt: f32 = 0,
    springs: anim.SpringBank(CHAN_N) = .{},

    phase: f32 = 0,
    moving: f32 = 0,
    fwdB: f32 = 1,
    latB: f32 = 0,
    speedS: f32 = 0,

    vit: combat.Vitals = combat.Vitals.initFoe(MG_HP, MG_POISE, MG_STANCE).withRes(MG_RESISTS),
    hits: u32 = 0,
    hitLatch: bool = false,
    flash: f32 = 0,
    shove: rl.Vector3 = mathx.zero3,
    justDied: bool = false,

    fade: f32 = 0,
    gone: bool = false,

    parts: [MG_NPART]foe.Particle = [_]foe.Particle{.{}} ** MG_NPART,
    fxHead: usize = 0,
    fxAccum: f32 = 0,
    fxRng: mathx.Rng = mathx.Rng.init(7),
    rng: mathx.Rng = mathx.Rng.init(11),

    xf: [N]rl.Matrix = undefined,
    rest: [N]rl.Vector3 = undefined,

    pub fn spawn(home: rl.Vector3, faceYaw: f32, scale: f32, seed: f32) Magus {
        var k = Magus{
            .pos = home,
            .home = home,
            .facing = faceYaw,
            .scale = scale * SCALE,
            .seed = seed,
            .vit = combat.Vitals.initFoe(MG_HP, MG_POISE, MG_STANCE).withRes(MG_RESISTS),
        };
        k.rest = REST;
        k.fxRng = foe.fxStream(seed, 63127.0, 0x7B1);
        k.rng = foe.fxStream(seed, 30011.0, 0x7B2);
        k.orbCd = 0.6 + seed * 1.2;
        k.springs.seat(MG_CARRY.chan());
        k.chanSet(MG_CARRY.chan());
        k.pose();
        return k;
    }

    pub fn kind(_: *const Magus) wf.FoeKind {
        return .fungal_magus;
    }
    pub fn centerWorld(self: *const Magus) rl.Vector3 {
        return foe.bodyPoint(self.pos, MG_CENTER_F * H, self.scale, 0);
    }
    pub fn topWorld(self: *const Magus) rl.Vector3 {
        return foe.bodyPoint(self.pos, MG_TOP_F * H, self.scale, 0);
    }
    pub fn lockPoint(self: *const Magus) rl.Vector3 {
        return foe.markOn(self.xf[CHEST], MARK_AT);
    }
    pub fn hurtRadius(self: *const Magus) f32 {
        return MG_HURT_R * self.scale;
    }
    pub fn bodyR(self: *const Magus) f32 {
        return MG_BODY_R * self.scale;
    }
    pub fn alive(self: *const Magus) bool {
        return !self.gone;
    }
    pub fn dying(self: *const Magus) bool {
        return self.state == .dead;
    }
    pub fn staggered(self: *const Magus) bool {
        return self.state == .stunlight or self.state == .stunheavy;
    }
    pub fn airborne(_: *const Magus) bool {
        return false;
    }
    fn hopOf(_: *const Magus) f32 {
        return 0;
    }
    pub fn flashFrac(self: *const Magus) f32 {
        return self.flash / foe.FLASH_DUR;
    }

    /// **GONE IS GONE — A BLADE FINDS NOTHING.** The fen lurker's rule for a body that is not there. It is not
    /// invulnerable: the part you interrupt is the FADE that got it here, which is long on purpose.
    pub fn absent(self: *const Magus) bool {
        return self.state == .gone;
    }

    /// **AND GONE IS GONE FOR THE OTHER TWO QUESTIONS TOO** (`game.disguised`, `game.phased`). `tryHit` was the
    /// only one being answered, so a dissolved magus was still a body you shouldered into and still a thing the
    /// lock-on picked: an invisible wall you could target. Both hooks already exist and both are opt-in.
    pub fn hidden(self: *const Magus) bool {
        return self.absent();
    }
    pub fn phased(self: *const Magus) bool {
        return self.absent();
    }

    fn fdir(self: *const Magus) rl.Vector3 {
        return mathx.headingDir(self.facing);
    }
    fn faceToward(self: *Magus, at: rl.Vector3, dt: f32) void {
        foe.faceToward(self.pos, &self.facing, at, MG_TURN_RATE, dt);
    }

    pub fn navWant(self: *const Magus, hero: rl.Vector3) ?rl.Vector3 {
        _ = hero;
        if (self.state != .drift) return null;
        if (self.homing) return self.home;
        return mathx.addV(self.pos, self.moveDir);
    }

    pub fn staffHead(self: *const Magus) rl.Vector3 {
        return rl.math.vector3Transform(v3(0, STAFF_LEN, 0), self.xf[HELD]);
    }

    fn chanGet(self: *const Magus) Chan {
        return chanOf(self);
    }
    fn chanSet(self: *Magus, c: Chan) void {
        setChan(self, c);
    }
    fn settlePose(self: *Magus, dt: f32) void {
        settle(self, dt);
    }

    fn enter(self: *Magus, s: MgState) void {
        self.state = s;
        self.t = 0;
    }

    pub fn update(self: *Magus, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?combat.Hit {
        self.justDied = false;
        self.threw = false;
        self.sowed = false;
        self.misted = false;
        self.heroHit = null;
        if (self.gone) {
            foe.tickParticles(&self.parts, dt, self.pos.y);
            return null;
        }
        self.stateStep(dt, hero, bounds);
        if (!self.absent()) self.tryHit(blade);
        return self.heroHit;
    }

    fn stateStep(self: *Magus, dt: f32, hero: rl.Vector3, bounds: f32) void {
        const grip = foe.grip(&self.root, &self.chill, &self.vit, dt, self.pos);
        defer grip.hold(&self.pos);
        if (grip.killed) self.enterDeath();
        if (grip.downed) self.stagger(true);

        self.elapsed += dt;
        self.t += dt;
        self.vit.tick(dt);
        self.orbCd = mathx.maxF(0, self.orbCd - dt);
        self.sproutCd = mathx.maxF(0, self.sproutCd - dt);
        self.fadeCd = mathx.maxF(0, self.fadeCd - dt);
        foe.fadeFlash(&self.flash, dt);
        foe.tickLeash(&self.leash, dt, self.pos, foe.tetherFor(self), hero, AGGRO_R);
        foe.tickParticles(&self.parts, dt, self.pos.y);
        foe.applyShove(&self.pos, &self.shove, SHOVE_DECAY, bounds, dt);

        const d = foe.senseHero(&self.leash, self.pos, hero, AGGRO_R);
        if (d <= MG_FLEE_R and self.vit.hpFrac() < MG_PRESS_HP) {
            self.press += dt;
        } else self.press = mathx.maxF(0, self.press - dt * 1.2);

        var movedDist: f32 = 0;
        var moveYaw: ?f32 = null;
        var moveSpeed: f32 = 0;

        switch (self.state) {
            .idle => {
                if (d <= AGGRO_R) self.faceToward(hero, dt);
                self.chanSet(MG_CARRY.chan());
                // **ORDERS ARE WHAT IT DOES BEFORE IT HAS SEEN ANYBODY** (`foe.postDrive`), refused inside the ring.
                _ = foe.postDrive(self, dt, bounds, MG_SPEED, d, AGGRO_R, MG_TURN_RATE, &movedDist, &moveSpeed, &moveYaw);
                if (self.t >= 0.16) self.decide(d, hero);
            },
            .drift => {
                self.faceToward(hero, dt);
                const way = self.nav.along(self.moveDir);
                moveSpeed = MG_SPEED;
                const moved = moveSpeed * dt * self.chill.travel();
                mathx.stepXZ(&self.pos, way, moved, bounds);
                movedDist = moved;
                moveYaw = mathx.headingXZ(way);
                self.chanSet(MG_CARRY.chan());
                if (self.homing and mathx.distXZ(self.pos, self.home) <= foe.LEASH_HOME_R) {
                    self.homing = false;
                    self.enter(.idle);
                } else if (self.t >= MG_DRIFT_DUR) self.decide(d, hero);
            },
            .orb_wind => {
                self.faceToward(hero, dt);
                const u = mathx.clampF(self.t / MG_ORB_WIND, 0, 1);
                self.chanSet(samplePose(&MG_ORB_WIND_KEYS, u));
                self.kindle(dt, u);
                if (self.t >= MG_ORB_WIND) self.enter(.orb_throw);
            },
            .orb_throw => {
                if (self.t < MG_ORB_DUR * MG_ORB_RELEASE_K) self.faceToward(hero, dt * 0.4);
                self.chanSet(samplePose(&MG_ORB_KEYS, mathx.clampF(self.t / MG_ORB_DUR, 0, 1)));
                // The release is an EDGE, caught by the clock crossing it: a long frame cannot fire two.
                const at = MG_ORB_DUR * MG_ORB_RELEASE_K;
                if (self.t - dt < at and self.t >= at) {
                    self.threw = true;
                    self.threwFrom = self.staffHead();
                    sfx.world(.duo_orb, self.pos);
                }
                if (self.t >= MG_ORB_DUR) {
                    self.orbCd = MG_ORB_CD;
                    self.enter(.recover);
                }
            },
            .sprout_wind => {
                self.faceToward(hero, dt);
                const u = mathx.clampF(self.t / MG_SPROUT_WIND, 0, 1);
                self.chanSet(samplePose(&MG_SPROUT_WIND_KEYS, u));
                self.kindle(dt, u * 1.4);
                if (self.t >= MG_SPROUT_WIND) self.enter(.sprout);
            },
            .sprout => {
                self.chanSet(samplePose(&MG_SPROUT_KEYS, mathx.clampF(self.t / MG_SPROUT_DUR, 0, 1)));
                const at = MG_SPROUT_DUR * 0.42;
                if (self.t - dt < at and self.t >= at) {
                    self.sowed = true;
                    // **SOWN WHERE HE IS, WHICH IS A POSITION** — the one thing the LAW allows a creature to read.
                    self.sowAt = mathx.ground(hero.x, hero.z);
                    self.sowAt.y = hero.y;
                    sfx.world(.duo_sprout, self.pos);
                }
                if (self.t >= MG_SPROUT_DUR) {
                    self.sproutCd = MG_SPROUT_CD;
                    self.enter(.recover);
                }
            },
            .recover => {
                if (d <= AGGRO_R) self.faceToward(hero, dt * 0.6);
                self.chanSet(samplePose(&MG_REC_KEYS, mathx.clampF(self.t / MG_ORB_REC, 0, 1)));
                if (self.t >= MG_ORB_REC) self.enter(.idle);
            },
            .fade_out => {
                const u = mathx.clampF(self.t / MG_FADE_OUT, 0, 1);
                self.chanSet(samplePose(&MG_FADE_KEYS, u));
                self.fade = u;
                self.shed(dt, u);
                if (self.t >= MG_FADE_OUT) {
                    self.misted = true;
                    self.mistAt = self.pos;
                    self.fade = 1;
                    self.enter(.gone);
                }
            },
            .gone => {
                self.fade = 1;
                if (self.t >= MG_GONE_DUR) {
                    // **IT COMES BACK UP INSIDE THE WORLD.** A bearing off its own seed put it through the
                    // cliff ring on a small map; `bounds` is the same clamp every step it takes already pays.
                    self.pos = self.returnTo;
                    self.pos.x = mathx.clampF(self.pos.x, -bounds, bounds);
                    self.pos.z = mathx.clampF(self.pos.z, -bounds, bounds);
                    self.facing = mathx.headingXZ(mathx.dirXZ(self.pos, hero));
                    self.enter(.fade_in);
                    sfx.world(.duo_bloom, self.pos);
                }
            },
            .fade_in => {
                const u = mathx.clampF(self.t / MG_FADE_IN, 0, 1);
                self.chanSet(samplePose(&MG_FADE_KEYS, 1.0 - u));
                self.fade = 1.0 - u;
                self.shed(dt, 1.0 - u);
                if (self.t >= MG_FADE_IN) {
                    self.fade = 0;
                    self.press = 0;
                    self.fadeCd = MG_FADE_CD;
                    self.enter(.idle);
                }
            },
            .stunlight, .stunheavy => {
                self.chanSet(MG_CARRY.chan());
                if (self.t >= combat.foeStunDur(self.state == .stunheavy)) self.enter(.idle);
            },
            .dead => {
                foe.dissipate(self, dt, MG_DEATH_DUR, MG_DISS_DUR, MG_DISSOLVE);
            },
        }

        heromod.advanceGait(&self.phase, &self.moving, &self.fwdB, &self.latB, &self.speedS, dt, movedDist / self.scale, moveSpeed, moveYaw, self.facing);
        self.settlePose(dt);
        self.pose();
    }

    fn decide(self: *Magus, dist: f32, toward: rl.Vector3) void {
        if (self.leash.goingHome()) {
            self.homing = true;
            self.moveDir = mathx.dirXZ(self.pos, self.home);
            return self.enter(.drift);
        }
        self.homing = false;
        // **THE BEARING IS TO THE QUARRY AND NOT TO ITS OWN NOSE** — the swordsman's rule, and this one needed
        // it more: off `fdir` a caster shoved or stunned out of line backed away along a bearing it was no
        // longer standing on, so a retreat walked across his front instead of off it.
        const f = mathx.dirXZ(self.pos, toward);
        const side: f32 = if (self.seed < 0.5) 1.0 else -1.0;
        const lat = mathx.scaleV(mathx.perpXZ(f), side);
        switch (mgClassify(dist, self.orbCd <= 0, self.sproutCd <= 0, self.fadeCd <= 0, self.press >= MG_PRESS_HOLD)) {
            .orb => self.enter(.orb_wind),
            .sprout => self.enter(.sprout_wind),
            .vanish => {
                // The bearing home is its OWN, off the seed and its own clock — it does not choose a spot
                // relative to him, it chooses one relative to where it was standing.
                const a = self.rng.angle();
                const away = v3(mathx.cosf(a), 0, mathx.sinf(a));
                self.returnTo = mathx.addV(self.pos, mathx.scaleV(away, MG_REAPPEAR_R));
                self.returnTo.y = self.pos.y;
                self.enter(.fade_out);
                sfx.world(.duo_fade, self.pos);
            },
            .back => {
                self.moveDir = mathx.normV(mathx.addV(mathx.scaleV(f, -1.0), mathx.scaleV(lat, 0.5)));
                self.enter(.drift);
            },
            .keep => {
                self.moveDir = if (dist > MG_KEEP_R)
                    mathx.normV(mathx.addV(f, mathx.scaleV(lat, 0.35)))
                else
                    lat;
                self.enter(.drift);
            },
            .hold => {
                if (mathx.distXZ(self.pos, foe.homeFor(self)) > foe.LEASH_HOME_R) {
                    self.homing = true;
                    self.moveDir = mathx.dirXZ(self.pos, self.home);
                    self.enter(.drift);
                } else self.enter(.idle);
            },
        }
    }

    fn kindle(self: *Magus, dt: f32, u: f32) void {
        const n = foe.emitTicks(&self.fxAccum, dt, lerpF(6.0, 34.0, u * u), 6);
        if (n == 0) return;
        elemfx.gather(&self.parts, &self.fxHead, &self.fxRng, self.staffHead(), .chaos, n, 0.22 * (0.4 + 0.6 * u) * self.scale, self.scale);
    }

    fn shed(self: *Magus, dt: f32, u: f32) void {
        const n = foe.emitTicks(&self.fxAccum, dt, lerpF(4.0, 26.0, u), 6);
        if (n == 0) return;
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, self.centerWorld(), v3(0, -1, 0), .chaos, n, self.scale);
    }

    pub fn tryHit(self: *Magus, blade_: foe.Blade) void {
        if (self.state == .dead) return;
        const s = foe.reached(self, blade_) orelse return;
        const heavy = foe.wounded(self, s, blade_, MG_SHOVE);
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, s.contact, v3(0, 1, 0), .chaos, if (heavy) 10 else 5, self.scale);
        switch (s.reaction) {
            .death => self.enterDeath(),
            .heavy => self.enterStun(true),
            .light => self.enterStun(false),
            .none => {},
        }
    }

    fn enterStun(self: *Magus, heavy: bool) void {
        if (self.state == .dead) return;
        // **A STAGGER SPENDS THE FADE.** Caught halfway out it comes back solid and owes the whole cooldown,
        // which is what makes closing on it during the dissolve the answer rather than a race.
        if (self.state == .fade_out or self.state == .fade_in) {
            self.fade = 0;
            self.press = 0;
            self.fadeCd = MG_FADE_CD;
        }
        sfx.world(.duo_magus_hurt, self.pos);
        self.enter(if (heavy) .stunheavy else .stunlight);
    }

    fn enterDeath(self: *Magus) void {
        if (self.state == .dead) return;
        self.fade = 0;
        sfx.world(.duo_magus_die, self.pos);
        self.justDied = true;
        self.enter(.dead);
    }

    pub fn markSlain(self: *Magus) void {
        self.vit.hp = 0;
        self.vit.dead = true;
        self.state = .dead;
        self.t = MG_DEATH_DUR + MG_DISS_DUR;
        self.fade = 1;
        self.gone = true;
    }

    pub fn stagger(self: *Magus, heavy: bool) void {
        if (self.state == .dead) return;
        self.enterStun(heavy);
    }

    fn stunAmount(self: *const Magus) f32 {
        return switch (self.state) {
            .stunlight => foe.stunCurve(self.t / combat.foeStunDur(false), false),
            .stunheavy => foe.stunCurve(self.t / combat.foeStunDur(true), true),
            else => 0,
        };
    }

    pub fn pose(self: *Magus) void {
        poseBody(self, MG_DEATH_DUR);
    }

    pub fn draw(self: *const Magus, model: *const MgModel) void {
        if (self.gone or self.fade >= 0.98) return;
        model.draw(self);
    }
    pub fn drawFx(self: *const Magus) void {
        foe.drawParticles(&self.parts);
    }
};

/// **ONE POSE FOR BOTH BODIES, AND NOT ONE BRANCH IN IT.** They are the same rig, the same channels and the
/// same stagger; what differs is the numbers in the keys and the MESH on the held bone. Written twice they
/// drifted, which is the thing this file is two creatures in one for. **THE RIG HAS ONE HELD BONE** (`hero.HELD`
/// hangs off `WRR`), so a sword and a staff come off the same wrist and every world point either creature takes
/// off its kit — `Swordsman.bladeSeg`, `Magus.staffHead` — reads that one matrix.
fn poseBody(self: anytype, deathDur: f32) void {
    const fs = foe.rigScale(self.scale, self.fade);
    const sink = foe.rigSink(0.46, self.scale, self.fade);
    const facingDeg = mathx.degrees(self.facing);
    const hipY = self.rest[ROOT].y;

    const dead = self.state == .dead;
    const dk = if (dead) mathx.smoothstep(0, 0.5, mathx.clampF(self.t / deathDur, 0, 1)) else 0;
    const stun = self.stunAmount();
    const m = self.moving * (1.0 - dk);
    const pel = heromod.pelvisChannels(self.phase, m, self.fwdB, self.latB, A_PROT);

    var wx: [N]rl.Matrix = undefined;
    const collapse = lerpF(hipY, 0.18 * H, dk);
    const pelvY = if (dead) collapse else hipY + pel.bob - pel.dip + self.hopOf();
    wx[ROOT] = mathx.mul(mathx.scaleM(fs, fs, fs), mathx.mul3(
        mathx.mul3(mathx.rz(9.0 * dk), mathx.rx(22.0 * dk), mathx.ry(pel.prot)),
        mathx.mul(mathx.tr(pel.sway * fs, pelvY * fs + sink, 0), mathx.ry(facingDeg)),
        heromod.rootAt(self.pos),
    ));

    if (!dead) {
        heromod.legChain(&wx, &self.rest, self.pos.y, self.phase, m, 0, self.fwdB, self.latB, 1.0, HIPL, KNEEL, SOLES[0]);
        heromod.legChain(&wx, &self.rest, self.pos.y, self.phase + 0.5, m, 0, self.fwdB, self.latB, -1.0, HIPR, KNEER, SOLES[1]);
    }

    const rest = self.rest;
    const twoPi = std.math.tau;
    const wonk = (self.seed - 0.5) * 5.5;
    const idleAmt = (1.0 - mathx.clampF(self.moving * 2.0, 0, 1)) * (1.0 - dk);
    const swayArg = self.elapsed * (0.5 + 0.2 * (0.5 + 0.5 * mathx.sinf(self.seed * 29.3))) + self.seed * 6.28;
    const swy = mathx.sinf(swayArg) * idleAmt;
    const swyLag = mathx.sinf(swayArg - 0.9) * idleAmt;

    const nod = 1.7 * mathx.cosf(2.0 * twoPi * self.phase) * m;
    const lean = self.bodyLean - 24.0 * stun + 28.0 * dk;
    setLocal(&wx, SPINE, rest, mathx.mul3(
        mathx.rx(lean * 0.40 + nod + 0.7 * swy),
        mathx.ry(-0.35 * pel.prot + self.twist * 0.40),
        mathx.rz(wonk * 0.5 + 1.0 * swy),
    ));
    setLocal(&wx, CHEST, rest, mathx.mul3(
        mathx.rx(lean * 0.60 + nod * 0.6 + 0.6 * swyLag),
        mathx.ry(-0.5 * pel.prot + self.twist * 0.60),
        mathx.rz(-wonk * 0.3 - 0.7 * swyLag),
    ));
    setLocal(&wx, NECK, rest, mathx.rx(self.headPitch * 0.30 + 8.0 * dk - 6.0 * stun));
    setLocal(&wx, HEAD, rest, mathx.mul3(
        mathx.rx(self.headPitch * 0.70 + 16.0 * dk - 30.0 * stun),
        mathx.ry(-0.5 * pel.prot),
        mathx.rz(wonk * 1.2 - 1.1 * swyLag - 0.8 * nod),
    ));

    if (dead) heromod.deadLegs(&wx, rest, dk);

    // **THE TWO ARMS ARE TWO CHANNELS, NOT ONE MIRRORED.** A sword arm and a guard arm never do the same thing,
    // and the staff is held at two different heights on the same shaft.
    const armStun = -56.0 * stun;
    const busy = mathx.clampF(mathx.smoothstep(10.0, 46.0, @abs(self.rsh)), 0, 1);
    const swing = 12.0 * mathx.sinf(twoPi * self.phase) * m * @abs(self.fwdB) * (1.0 - busy);
    setLocal(&wx, SHR, rest, mathx.mul(mathx.rx(-(self.rsh - swing + armStun - 24.0 * dk)), mathx.rz(-(self.rabd + wonk * 0.4))));
    setLocal(&wx, ELR, rest, mathx.rx(-(self.rel + wonk * 0.6)));
    setLocal(&wx, WRR, rest, mathx.rz(-8.0));
    setLocal(&wx, SHL, rest, mathx.mul(mathx.rx(-(self.lsh + swing + armStun - 24.0 * dk)), mathx.rz(self.rabd * 0.35 + wonk * 0.4)));
    setLocal(&wx, ELL, rest, mathx.rx(-(self.lel - wonk * 0.6)));
    setLocal(&wx, WRL, rest, mathx.rz(8.0));

    // **BOTH KITS ARE AUTHORED POINTING UP OFF THE GRIP** (the warriors' convention) and `hero.staffFit` is
    // what turns one into the world: after it, `tilt` is degrees the kit leads FORWARD of the forearm — 0 down,
    // 90 level, 180 on end. Fitted by hand instead, the blade left the wrist at a right angle and the whole
    // stroke reached 1.85 m on a body carrying 2.17 m of sword.
    // **AND THE TILT IS WORLD-RELATIVE, SO THE ARM'S OWN FLEX COMES OUT OF IT** (`warrior.swingTilt`). Fitted
    // in the forearm's frame the number means nothing: measured, a `tilt` of 94 — level, by the convention —
    // put the point 3.73 m up, two metres over a hero column that ends at 1.71, and the whole stroke reached
    // 1.85 m because the blade never once crossed him.
    setLocal(&wx, HELD, rest, heromod.staffFit(self.tilt - self.rsh));
    self.xf = wx;
}

/// **A STAFF IS SHOULDER-TALL ON THE BODY CARRYING IT, NOT TALLER THAN IT.** Measured off the posed grip at
/// 1.27 m: at 1.05·H the head stood 3.67 m up over a 2.42 m creature, which is a pole with a body hanging off
/// it. At 0.86 it clears the cap and stops.
pub const STAFF_LEN: f32 = 0.86 * H;

comptime {
    std.debug.assert(STAFF_LEN > 0.60 * H and STAFF_LEN < 1.0 * H);
}

fn swBones() [N]rl.Mesh {
    var b: [N]rl.Mesh = undefined;
    b[ROOT] = swPelvis();
    b[SPINE] = swLumbar();
    b[CHEST] = swChest();
    b[NECK] = neckMesh();
    b[HEAD] = swHead();
    b[HIPL] = thighMesh(0x11);
    b[KNEEL] = shinMesh(0x12);
    b[ANKL] = footMesh(1.0);
    b[HIPR] = thighMesh(0x13);
    b[KNEER] = shinMesh(0x14);
    b[ANKR] = footMesh(-1.0);
    b[SHL] = upperArmMesh(1.0);
    b[ELL] = forearmMesh(1.0);
    b[WRL] = handMesh(1.0);
    b[SHR] = upperArmMesh(-1.0);
    b[ELR] = forearmMesh(-1.0);
    b[WRR] = handMesh(-1.0);
    b[HELD] = swordMesh();
    return b;
}

fn mgBones() [N]rl.Mesh {
    var b: [N]rl.Mesh = undefined;
    b[ROOT] = mgPelvis();
    b[SPINE] = mgLumbar();
    b[CHEST] = mgChest();
    b[NECK] = neckMesh();
    b[HEAD] = mgHead();
    b[HIPL] = thighMesh(0x21);
    b[KNEEL] = shinMesh(0x22);
    b[ANKL] = footMesh(1.0);
    b[HIPR] = thighMesh(0x23);
    b[KNEER] = shinMesh(0x24);
    b[ANKR] = footMesh(-1.0);
    b[SHL] = upperArmMesh(1.0);
    b[ELL] = forearmMesh(1.0);
    b[WRL] = handMesh(1.0);
    b[SHR] = upperArmMesh(-1.0);
    b[ELR] = forearmMesh(-1.0);
    b[WRR] = handMesh(-1.0);
    b[HELD] = staffMesh();
    return b;
}

/// **A LIMB IS THREE FORMS, NOT ONE CAPSULE** — the mass, a swell where the muscle is, and a BALL at the joint
/// (the hero rig's own law: a bare cylinder is capless and shows its cut mouth the moment the limb swings).
/// Straight capsules with nothing on them is what made these two read as shop dummies.
fn limb(b: *Builder, len: f32, r0: f32, r1: f32, belly: f32, col: rl.Color, dk: rl.Color) void {
    b.addCapsule(v3(0, 0, 0), v3(0, -len, 0), r0, r1, 8, col);
    b.addBlob(v3(0, -len * 0.38, r0 * 0.18), v3(r0 * belly, len * 0.30, r0 * belly * 0.92), 7, 6, col);
    // **THE JOINT SEALS THE MOUTH; IT IS NOT A BEARING.** A ball proud of the limb at every hinge, repeated six
    // times, is what made these two read as mechs. Barely wider than the capsule it caps, and SQUASHED, so it
    // is a knuckle under skin rather than a sphere with a limb hanging off it.
    b.addBlob(v3(0, -r0 * 0.10, 0), v3(r0 * 1.02, r0 * 0.78, r0 * 1.02), 7, 6, dk);
}

/// **A SHELF IS A HALF-DISC ON EDGE WITH A GILL UNDER IT** — `propfungus.bracketMesh`'s idiom, and the one
/// shape this creature is made of. Thick where it meets the body, thin at the lip, and the dark disc beneath
/// is what says fungus rather than armour plate: a pauldron has no underside worth seeing.
fn shelf(b: *Builder, at: rl.Vector3, ang: f32, out: f32, thick: f32, col: rl.Color) void {
    const c = mathx.cosf(ang);
    const sn = mathx.sinf(ang);
    const mid = v3(at.x + c * out * 0.55, at.y, at.z + sn * out * 0.55);
    const wide = out * (0.58 + 0.42 * @abs(c));
    const deep = out * (0.58 + 0.42 * @abs(sn));
    b.addBlob(mid, v3(wide, thick, deep), 3, 9, col);
    b.addBlob(v3(mid.x, mid.y - thick * 0.85, mid.z), v3(wide * 0.86, thick * 0.42, deep * 0.86), 3, 8, GILL);
}

/// The crust: a scatter of hard plates over a soft mass, thickest where the light lands. **RELIEF IS SUBTLE** —
/// a few percent of the mass's radius, sunk most of the way in, and it is the IRREGULARITY that reads.
fn crust(b: *Builder, rng: *mathx.Rng, at: rl.Vector3, r: rl.Vector3, n: u32, col: rl.Color) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const a = rng.angle();
        const t = rng.range(-0.8, 0.9);
        const sz = rng.range(0.13, 0.30);
        b.addBlob(
            v3(at.x + mathx.cosf(a) * r.x * 0.94, at.y + t * r.y * 0.72, at.z + mathx.sinf(a) * r.z * 0.94),
            v3(r.x * sz, r.y * sz * rng.range(0.35, 0.75), r.z * sz * 0.55),
            5,
            4,
            col,
        );
    }
}

fn swPelvis() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x1188);
    b.setMat(.skin);
    b.addBlob(v3(0, -0.004 * H, 0), v3(0.122 * H, 0.082 * H, 0.098 * H), 9, 7, RIND);
    b.addBlob(v3(0, 0.030 * H, 0.006 * H), v3(0.114 * H, 0.020 * H, 0.094 * H), 8, 6, RIND_DK);
    // A HANGING RIND OVER THE HIPS, ragged and uneven: the thing that stops him reading as a naked figure.
    b.setMat(.cloth);
    b.addSkirt(v3(0, 0.010 * H, 0), 0.118 * H, 0.180 * H, 0.150 * H, 0.012 * H, 11, RIND_DK, &rng);
    b.setMat(.skin);
    crust(&b, &rng, v3(0, 0, 0), v3(0.122 * H, 0.082 * H, 0.098 * H), 5, WART);
    return b.toMesh();
}

fn swLumbar() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.092 * H, 0), 0.104 * H, 0.118 * H, 9, RIND);
    return b.toMesh();
}

fn swChest() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x51A7);
    b.setMat(.skin);
    b.addBlob(v3(0, 0.050 * H, 0.004 * H), v3(0.156 * H, 0.112 * H, 0.120 * H), 10, 8, RIND);
    b.addBlob(v3(0, -0.008 * H, 0.014 * H), v3(0.134 * H, 0.070 * H, 0.108 * H), 9, 7, RIND_LT);
    // **HE IS A BRACKET FUNGUS AND SHE IS A CAP** — the pair's whole silhouette split. Hers is one shape
    // standing UP; his is a stack of shelves growing OUT, heaviest over the back and shoulders, so a low wide
    // mass reads against a tall narrow one at any range and from behind.
    var i: u32 = 0;
    while (i < 11) : (i += 1) {
        const a = rng.angle();
        // Toward the BACK (-z) they run out furthest; across the chest they are barely lips.
        const back = 0.5 - 0.5 * mathx.sinf(a);
        const tier = rng.range(0.02, 0.13) * H;
        shelf(
            &b,
            v3(0, 0.030 * H + tier, 0),
            a,
            (0.10 + 0.13 * back) * H * rng.range(0.82, 1.15),
            rng.range(0.012, 0.026) * H,
            if (rng.float() < 0.35) RIND_DK else RIND,
        );
    }
    // The sword side carries one heavy course lower than the rest — nothing here is symmetric.
    shelf(&b, v3(0, 0.006 * H, 0), mathx.radians(196.0), 0.20 * H, 0.030 * H, RIND_DK);
    crust(&b, &rng, v3(0, 0.040 * H, 0), v3(0.150 * H, 0.106 * H, 0.116 * H), 7, WART);
    return b.toMesh();
}

/// **HE HAS NO HEAD.** The bone is still there because the rig is shared, but what sits on it is the top
/// SHELF of the stack — pulled forward over a dark cleft with two points burning back in it. A featureless lump
/// on a neck was the last thing making him read as a man in armour; a growth has no head to give him.
fn swHead() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x6C21);
    b.setMat(.skin);
    // The hood shelf: wide, thin, jutting FORWARD past where a face would be, so the cleft is in shadow.
    b.addBlob(v3(0, 0.052 * H, 0.020 * H), v3(0.132 * H, 0.030 * H, 0.118 * H), 4, 10, RIND);
    b.addBlob(v3(0, 0.074 * H, -0.008 * H), v3(0.096 * H, 0.026 * H, 0.086 * H), 4, 9, RIND_DK);
    // …and the CLEFT under it, which is the whole face: a dark wedge and nothing else in it.
    b.addBlob(v3(0, 0.026 * H, 0.026 * H), v3(0.086 * H, 0.030 * H, 0.078 * H), 6, 8, GILL);
    b.addBlob(v3(0, 0.010 * H, 0.006 * H), v3(0.062 * H, 0.028 * H, 0.058 * H), 6, 7, GILL);
    b.setMat(.plain);
    // Set BACK in the cleft, not on the front of a face — the overhang is what makes two points read as eyes.
    b.addBlob(v3(0.026 * H, 0.028 * H, 0.048 * H), v3(0.011 * H, 0.009 * H, 0.009 * H), 5, 5, EYE);
    b.addBlob(v3(-0.024 * H, 0.026 * H, 0.048 * H), v3(0.010 * H, 0.009 * H, 0.009 * H), 5, 5, EYE);
    b.setMat(.skin);
    var w: u32 = 0;
    while (w < 6) : (w += 1) {
        const a = rng.range(-2.2, 2.2);
        b.addBlob(
            v3(mathx.sinf(a) * 0.104 * H, 0.062 * H, -0.030 * H + mathx.cosf(a) * 0.030 * H),
            v3(0.020 * H, rng.range(0.010, 0.024) * H, 0.016 * H),
            5,
            4,
            CAP_DK,
        );
    }
    return b.toMesh();
}

fn mgPelvis() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x4411);
    b.setMat(.cloth);
    b.addBlob(v3(0, -0.004 * H, 0), v3(0.116 * H, 0.080 * H, 0.096 * H), 9, 7, MYC);
    b.addBlob(v3(0, 0.028 * H, 0.004 * H), v3(0.110 * H, 0.018 * H, 0.092 * H), 8, 6, MYC_DK);
    // Longer and more ragged than the swordsman's: it stands still, so its hem is what moves.
    b.addSkirt(v3(0, 0.014 * H, 0), 0.112 * H, 0.260 * H, 0.164 * H, 0.010 * H, 13, MYC_DK, &rng);
    b.addSkirt(v3(0, -0.030 * H, 0), 0.104 * H, 0.150 * H, 0.132 * H, 0.009 * H, 9, GILL, &rng);
    return b.toMesh();
}

fn mgLumbar() rl.Mesh {
    var b = Builder.init();
    b.setMat(.cloth);
    b.addCapsule(v3(0, 0, 0), v3(0, 0.090 * H, 0), 0.100 * H, 0.112 * H, 9, MYC);
    return b.toMesh();
}

fn mgChest() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x77C3);
    b.setMat(.cloth);
    b.addBlob(v3(0, 0.048 * H, 0.004 * H), v3(0.144 * H, 0.106 * H, 0.116 * H), 10, 8, MYC);
    b.addBlob(v3(0, -0.006 * H, 0.012 * H), v3(0.126 * H, 0.066 * H, 0.104 * H), 9, 7, MYC_DK);
    var i: u32 = 0;
    while (i < 9) : (i += 1) {
        const a = rng.angle();
        const rr = 0.118 * H;
        b.addBlob(
            v3(mathx.cosf(a) * rr, 0.092 * H + rng.range(-0.008, 0.020) * H, mathx.sinf(a) * rr * 0.9),
            v3(rng.range(0.020, 0.040) * H, rng.range(0.024, 0.048) * H, 0.014 * H),
            5,
            4,
            if (rng.float() < 0.4) GILL else MYC_DK,
        );
    }
    return b.toMesh();
}

/// **A CAP IS A BRIM, AND A BRIM IS WIDER THAN THE SHOULDERS.** At 0.132 of H it was a smooth ball sitting on
/// his head — a helmet, not a mushroom — with the gills tucked underneath where nothing can see them. The
/// mushroom mage's own rim is 0.200 and its note says why: the read is the OVERHANG and the dark ring under it.
const MG_RIM: f32 = 0.196 * H;

comptime {
    // The brim has to clear the shoulders or there is no overhang to read, and stop before it is an umbrella.
    std.debug.assert(MG_RIM > SHOULDER_HALF * 1.35 and MG_RIM < SHOULDER_HALF * 2.4);
}

fn mgHead() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x3B90);
    b.setMat(.skin);
    // THE CAP IS THE HOOD (the mushroom mage's law) — one silhouette, and it sits DOWN over the head rather
    // than on top of it, so there is no neck and no face under a hat: there is only the cap.
    b.addBlob(v3(0, 0.062 * H, 0), v3(MG_RIM, 0.070 * H, MG_RIM * 0.94), 12, 9, CAP_COL);
    b.addBlob(v3(0.012 * H, 0.098 * H, -0.010 * H), v3(MG_RIM * 0.58, 0.044 * H, MG_RIM * 0.55), 9, 7, CAP_COL);
    // **THE GILLS ARE THE WHOLE THING** (the fungus law) — the one surface permanently in its own shade, and
    // the ring of dark under the brim is what says mushroom from any angle.
    b.addBlob(v3(0, 0.030 * H, 0.002 * H), v3(MG_RIM * 0.92, 0.020 * H, MG_RIM * 0.87), 11, 7, GILL);
    b.addBlob(v3(0, 0.006 * H, 0.030 * H), v3(MG_RIM * 0.44, 0.030 * H, MG_RIM * 0.32), 7, 6, GILL);
    b.setMat(.plain);
    b.addBlob(v3(0.028 * H, 0.008 * H, MG_RIM * 0.52), v3(0.013 * H, 0.011 * H, 0.010 * H), 5, 5, EYE);
    b.addBlob(v3(-0.028 * H, 0.006 * H, MG_RIM * 0.52), v3(0.012 * H, 0.010 * H, 0.010 * H), 5, 5, EYE);
    b.setMat(.skin);
    // A cap is not a smooth dome: warts on the crown, thinning toward the rim, and one torn edge.
    var w: u32 = 0;
    while (w < 13) : (w += 1) {
        const a = rng.angle();
        const rr = rng.range(0.18, 0.86) * MG_RIM;
        const sz = rng.range(0.09, 0.19) * MG_RIM;
        b.addBlob(
            v3(mathx.cosf(a) * rr, 0.078 * H + 0.034 * H * (1.0 - rr / MG_RIM), mathx.sinf(a) * rr * 0.94),
            v3(sz, sz * 0.44, sz),
            5,
            4,
            CAP_DK,
        );
    }
    b.addBlob(v3(-MG_RIM * 0.74, 0.046 * H, -MG_RIM * 0.52), v3(MG_RIM * 0.26, 0.020 * H, MG_RIM * 0.22), 5, 4, CAP_DK);
    return b.toMesh();
}

/// Short and swallowed: the hood shelf sits down on the chest, so any neck showing between them is a man's.
fn neckMesh() rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addCapsule(v3(0, -0.010 * H, 0), v3(0, 0.026 * H, 0), 0.062 * H, 0.070 * H, 8, GILL);
    return b.toMesh();
}

fn thighMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    limb(&b, 0.196 * H, 0.062 * H, 0.050 * H, 1.18, RIND_DK, RIND);
    crust(&b, &rng, v3(0, -0.098 * H, 0), v3(0.062 * H, 0.098 * H, 0.062 * H), 3, MYC_DK);
    return b.toMesh();
}

fn shinMesh(seed: u64) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    b.setMat(.skin);
    limb(&b, 0.186 * H, 0.048 * H, 0.036 * H, 1.22, RIND_DK, RIND);
    crust(&b, &rng, v3(0, -0.080 * H, 0), v3(0.048 * H, 0.086 * H, 0.048 * H), 3, MYC_DK);
    return b.toMesh();
}

fn footMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(side * 0.004 * H, -0.014 * H, 0.036 * H), v3(0.050 * H, 0.026 * H, 0.088 * H), 7, 6, RIND_DK);
    return b.toMesh();
}

fn upperArmMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0x2A11 else 0x2A22);
    b.setMat(.skin);
    limb(&b, 0.152 * H, 0.048 * H, 0.040 * H, 1.20, RIND, RIND_DK);
    crust(&b, &rng, v3(0, -0.076 * H, 0), v3(0.048 * H, 0.076 * H, 0.048 * H), 2, WART);
    return b.toMesh();
}

fn forearmMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(if (side > 0) 0x3B11 else 0x3B22);
    b.setMat(.skin);
    limb(&b, 0.140 * H, 0.040 * H, 0.032 * H, 1.16, RIND, RIND_DK);
    crust(&b, &rng, v3(0, -0.070 * H, 0), v3(0.040 * H, 0.070 * H, 0.040 * H), 2, WART);
    return b.toMesh();
}

fn handMesh(side: f32) rl.Mesh {
    var b = Builder.init();
    b.setMat(.skin);
    b.addBlob(v3(side * 0.004 * H, -0.028 * H, 0), v3(0.032 * H, 0.040 * H, 0.026 * H), 6, 5, FLESH);
    return b.toMesh();
}

/// **IRON IS BOXES** (the law) — and the venom is a bead running the fuller, not a coat over the whole blade.
fn swordMesh() rl.Mesh {
    var b = Builder.init();
    // **THE BLADE IS `.plain`, AND ONLY THE FITTINGS ARE `.steel`** — the knight's rule (`PLATE` = `.plain`,
    // `BRIGHT` = `.steel`), because `Mat.steel`'s specular is catastrophic on a FACE: a blinding `pow(nh,96)`
    // hotspot added on top of whatever the albedo is. Two metres of flat blade in steel came back near-white
    // however dark it was authored — dropping the albedo from 104 to 58 changed nothing on screen at all.
    b.setMat(.plain);
    const half = 0.030 * H;
    // **IT TAPERS.** A constant-width bar is a plank; the blade narrows to the point over three courses, which
    // is what a longsword does and what stops two metres of it reading as scaffolding.
    inline for (.{ .{ 0.00, 0.42, 1.00 }, .{ 0.42, 0.78, 0.84 }, .{ 0.78, 1.00, 0.62 } }) |seg| {
        const y0 = SW_BLADE_LEN * seg[0];
        const y1 = SW_BLADE_LEN * seg[1];
        b.addCube(v3(0, (y0 + y1) * 0.5, 0), v3(half * 2.0 * seg[2], y1 - y0, half * 0.50), STEEL);
    }
    // The fuller: a deep dark channel down the middle, and the thing that reads as edge-and-spine at range.
    b.addCube(v3(0, SW_BLADE_LEN * 0.48, 0), v3(half * 0.78, SW_BLADE_LEN * 0.90, half * 0.62), STEEL_DK);
    b.addCube(v3(0, SW_BLADE_LEN + 0.026 * H, 0), v3(half * 0.62, 0.058 * H, half * 0.40), STEEL);
    // The cross and the pommel are the small BRIGHT things, which is where a steel highlight belongs.
    b.setMat(.steel);
    b.addCube(v3(0, 0, 0), v3(0.150 * H, 0.022 * H, 0.030 * H), STEEL_DK);
    b.addBlob(v3(0, -0.116 * H, 0), v3(0.026 * H, 0.024 * H, 0.026 * H), 6, 5, STEEL_DK);
    b.setMat(.plain);
    b.setMat(.leather);
    b.addCapsule(v3(0, -0.014 * H, 0), v3(0, -0.104 * H, 0), 0.022 * H, 0.026 * H, 7, RIND_DK);
    // …and the venom is a BEAD RUNNING THE FULLER, not seven dots stuck on the flat.
    b.setMat(.plain);
    var i: u32 = 0;
    while (i < 11) : (i += 1) {
        const t = 0.08 + 0.082 * @as(f32, @floatFromInt(i));
        b.addBlob(v3(0, SW_BLADE_LEN * t, half * 0.30), v3(half * 0.16, half * 0.50, half * 0.12), 4, 4, VENOM);
    }
    return b.toMesh();
}

fn staffMesh() rl.Mesh {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x2E6D);
    b.setMat(.bark);
    b.addCapsule(v3(0, -0.10 * H, 0), v3(0, STAFF_LEN * 0.86, 0.012 * H), 0.020 * H, 0.026 * H, 7, RIND_DK);
    b.addCapsule(v3(0, STAFF_LEN * 0.86, 0.012 * H), v3(0, STAFF_LEN, -0.006 * H), 0.026 * H, 0.020 * H, 7, RIND_DK);
    b.setMat(.skin);
    b.addBlob(v3(0, STAFF_LEN + 0.028 * H, -0.006 * H), v3(0.070 * H, 0.052 * H, 0.066 * H), 8, 7, CAP_COL);
    b.addBlob(v3(0, STAFF_LEN + 0.004 * H, -0.006 * H), v3(0.058 * H, 0.016 * H, 0.054 * H), 7, 6, GILL);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const t = rng.range(0.25, 0.80);
        const a = rng.angle();
        b.addBlob(
            v3(mathx.cosf(a) * 0.020 * H, STAFF_LEN * t, mathx.sinf(a) * 0.020 * H),
            v3(0.020 * H, 0.012 * H, 0.020 * H),
            5,
            4,
            CAP_DK,
        );
    }
    return b.toMesh();
}

pub fn orbMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.setMat(.flame);
    b.addBlob(mathx.zero3, v3(ORB_R, ORB_R, ORB_R), 8, 7, mathx.withAlpha(CHAOS_CORE, 90));
    return b.toModel(shader);
}


// **ONE ENCOUNTER, TWO GROUPS, AND THAT IS NOT A CONTRADICTION.** A group in `game.FOE_GROUPS` answers for ONE
// kind or hands back one slice of one type (`liveConst`), and these two bodies are not one type: the swordsman
// is a set of strokes and the magus is a set of spells, and a role field over both would be a union with two
// state machines in it. They stay in ONE FILE because they are one fight — the rig, the palette, the pose and
// the bands are shared, and the bands only mean anything against each other.

const SW_CAP: usize = wf.MAX_PER_KIND;
const MG_CAP: usize = wf.MAX_PER_KIND;

pub const Vanguard = struct {
    model: SwModel,
    men: [SW_CAP]Swordsman = undefined,
    n: usize = 0,

    pub fn init(shader: rl.Shader) Vanguard {
        return .{ .model = SwModel.init(shader) };
    }
    pub fn setShader(self: *Vanguard, sh: rl.Shader) void {
        self.model.setShader(sh);
    }
    pub fn live(self: *Vanguard) []Swordsman {
        return self.men[0..self.n];
    }
    pub fn liveConst(self: *const Vanguard) []const Swordsman {
        return self.men[0..self.n];
    }
    pub fn reset(self: *Vanguard, m: *const wf.Map) void {
        foe.resetGroup(Swordsman, &self.men, &self.n, m, .fungal_swordsman);
    }
    pub fn update(self: *Vanguard, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        return foe.groupBlow(self.live(), dt, hero, bounds, blade);
    }
    pub fn draw(self: *const Vanguard, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
    }
    pub fn drawFx(self: *const Vanguard) void {
        for (self.liveConst()) |*k| k.drawFx();
    }
    pub fn pierce(self: *Vanguard, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn setParry(self: *Vanguard, p: foe.Parry) void {
        foe.setParry(self.live(), p);
    }
    pub fn anyParried(self: *const Vanguard) bool {
        return foe.anyParried(self.liveConst());
    }
    pub fn anyDied(self: *const Vanguard) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Vanguard) u32 {
        return foe.soulsDropped(self.liveConst(), SW_SOULS);
    }
    pub fn totalHits(self: *const Vanguard) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Vanguard) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

/// The magi, AND everything they put on the ground: the orbs in the air, the bunches growing and the mist a
/// vanish leaves. **THE GROUND BELONGS TO THE GROUP AND NOT TO THE BODY** — a bunch outlives the caster that
/// sowed it, which is most of what makes killing the caster first not the whole answer.
pub const Conclave = struct {
    model: MgModel,
    orbModel: rl.Model,
    magi: [MG_CAP]Magus = undefined,
    n: usize = 0,

    /// **SIZED FOR THE PAIR, AND A FULL POOL DROPS RATHER THAN WRAPS** (`foe.pushTurned`'s rule): wrapping
    /// would put a bunch under somebody nothing was cast at. The group is `wf.MAX_PER_KIND` deep because the
    /// game demands it, so a map that posts a hundred magi gets a hundred casters sharing twelve orbs — that
    /// is a map doing something this creature is not for, and it degrades quietly instead of growing `Game`
    /// by a megabyte for a case nobody authors.
    orbs: [ORB_N]Orb = [_]Orb{.{}} ** ORB_N,
    caps: [CAP_N]Cap = [_]Cap{.{}} ** CAP_N,
    mists: [MIST_N]Mist = [_]Mist{.{}} ** MIST_N,
    /// One pool and one meter for every wisp of it (the sporeling cloud's rule), so two vanishes overlapping
    /// is one mist and not two accumulators filling one bar.
    soak: foe.Soak = .{},

    parts: [DUO_PARTS]foe.Particle = [_]foe.Particle{.{}} ** DUO_PARTS,
    fxHead: usize = 0,
    fxRng: mathx.Rng = mathx.Rng.init(0xD00),

    pub fn init(shader: rl.Shader) Conclave {
        return .{ .model = MgModel.init(shader), .orbModel = orbMesh(shader) };
    }
    pub fn setShader(self: *Conclave, sh: rl.Shader) void {
        self.model.setShader(sh);
        self.orbModel.materials[0].shader = sh;
    }
    pub fn live(self: *Conclave) []Magus {
        return self.magi[0..self.n];
    }
    pub fn liveConst(self: *const Conclave) []const Magus {
        return self.magi[0..self.n];
    }
    pub fn reset(self: *Conclave, m: *const wf.Map) void {
        self.clearGround();
        foe.resetGroup(Magus, &self.magi, &self.n, m, .fungal_magus);
    }

    /// **`clear` EMPTIES THE FIELD** — the house contract every other group's has (`knight.Vigil`,
    /// `cinderwake.Scorch`): the BODIES and whatever they left behind. Written as the ground alone it was the
    /// one row of `game.clearFoes` that left its creatures standing.
    pub fn clear(self: *Conclave) void {
        self.n = 0;
        self.clearGround();
    }

    /// Everything on the field that is not a body. Cleared with the casters, or a reload comes up standing in
    /// a bunch that was sown before it.
    fn clearGround(self: *Conclave) void {
        self.orbs = [_]Orb{.{}} ** ORB_N;
        self.caps = [_]Cap{.{}} ** CAP_N;
        self.mists = [_]Mist{.{}} ** MIST_N;
        self.soak = .{};
    }

    pub fn update(self: *Conclave, dt: f32, hero: rl.Vector3, bounds: f32, blade: foe.Blade) ?foe.Blow {
        var worst: ?foe.Blow = null;
        for (self.live()) |*k| {
            if (k.update(dt, k.threat.aim(hero), bounds, blade)) |h| foe.worseBlow(&worst, h, k.pos, &k.threat);
            if (k.threw) self.launchOrb(k.threwFrom, k.threat.aim(hero));
            if (k.sowed) self.sow(k.sowAt);
            if (k.misted) self.mist(k.mistAt);
        }
        self.tickOrbs(dt, hero, &worst);
        self.tickCaps(dt, hero, &worst);
        for (&self.mists) |*g| {
            if (!g.live) continue;
            g.t += dt;
            if (g.t >= MIST_LIFE) g.live = false;
        }
        foe.tickParticles(&self.parts, dt, hero.y);
        return worst;
    }

    /// **THE MIST BILLS SLEEP AS A SOAK** — the bloom's meter through the cloud's channel, so nothing blocks it
    /// and nothing parries it. Handed back rather than applied: dosing the hero is the game's to do.
    pub fn breath(self: *Conclave, at: rl.Vector3, dt: f32) f32 {
        var inside = false;
        for (&self.mists) |*g| {
            if (g.covers(at)) inside = true;
        }
        return self.soak.step(inside, dt, MIST_BUILD);
    }

    fn launchOrb(self: *Conclave, from: rl.Vector3, at: rl.Vector3) void {
        for (&self.orbs) |*o| {
            if (o.live) continue;
            const to = v3(at.x, at.y + heromod.H * 0.55, at.z);
            o.* = .{ .live = true, .at = from, .vel = mathx.scaleV(mathx.normV(mathx.subV(to, from)), ORB_SPEED), .spin = self.fxRng.angle() };
            return;
        }
    }

    fn tickOrbs(self: *Conclave, dt: f32, hero: rl.Vector3, worst: *?foe.Blow) void {
        for (&self.orbs) |*o| {
            if (!o.live) continue;
            o.t += dt;
            o.at = mathx.addV(o.at, mathx.scaleV(o.vel, dt));
            o.spin += dt * 9.0;
            const chest = v3(hero.x, hero.y + heromod.H * 0.55, hero.z);
            if (mathx.lenV(mathx.subV(o.at, chest)) <= ORB_R + foe.HERO_R) {
                o.live = false;
                self.splashAt(o.at, 9);
                foe.worseBlow(worst, ORB_HIT, o.at, &GROUND_THREAT);
                continue;
            }
            if (o.t >= ORB_LIFE or o.at.y <= hero.y + 0.05) {
                o.live = false;
                self.splashAt(o.at, 9);
            }
        }
    }

    /// A BUNCH, sown AROUND the point and not on it — standing still is what the move punishes.
    fn sow(self: *Conclave, at: rl.Vector3) void {
        var placed: usize = 0;
        var tries: usize = 0;
        while (placed < MG_BUNCH and tries < MG_BUNCH * 4) : (tries += 1) {
            const a = self.fxRng.angle();
            const r = self.fxRng.range(MG_BUNCH_R * 0.25, MG_BUNCH_R);
            const spot = v3(at.x + mathx.cosf(a) * r, at.y, at.z + mathx.sinf(a) * r);
            for (&self.caps) |*c| {
                if (c.live) continue;
                c.* = .{ .live = true, .at = spot, .r = self.fxRng.range(0.42, 0.72), .t = -self.fxRng.range(0, CAP_STAGGER) };
                placed += 1;
                break;
            }
        }
    }

    fn tickCaps(self: *Conclave, dt: f32, hero: rl.Vector3, worst: *?foe.Blow) void {
        for (&self.caps) |*c| {
            if (!c.live) continue;
            c.t += dt;
            if (c.t < CAP_GROW + CAP_GLOW) continue;
            if (!c.burst) {
                c.burst = true;
                self.splashAt(c.at, 18);
                sfx.world(.duo_burst, c.at);
                // ONE BLOW PER CAP, on the frame it goes: a bunch overlapping you is a bunch of blows, which is
                // exactly the cost of standing in the middle of one.
                if (mathx.distXZ(c.at, hero) <= CAP_BURST_R) foe.worseBlow(worst, CAP_HIT, c.at, &GROUND_THREAT);
            }
            // One frame of burst and it is gone: the mark on the ground was the warning.
            if (c.t >= CAP_GROW + CAP_GLOW + 0.10) c.live = false;
        }
    }

    fn mist(self: *Conclave, at: rl.Vector3) void {
        for (&self.mists) |*g| {
            if (g.live) continue;
            g.* = .{ .live = true, .at = at };
            return;
        }
    }

    fn splashAt(self: *Conclave, at: rl.Vector3, n: usize) void {
        const from = self.fxHead;
        elemfx.burst(&self.parts, &self.fxHead, &self.fxRng, at, v3(0, 1, 0), .chaos, n, 1.0);
        foe.floorBurst(&self.parts, from, self.fxHead, at.y);
    }

    pub fn draw(self: *const Conclave, scene: ?*gfx.Scene) void {
        foe.drawGroup(self.liveConst(), &self.model, scene);
        for (&self.caps) |*c| {
            if (!c.showing() or c.burst) continue;
            drawCap(c);
        }
    }

    pub fn drawFx(self: *const Conclave) void {
        for (self.liveConst()) |*k| k.drawFx();
        for (&self.orbs) |*o| {
            if (!o.live) continue;
            rl.drawModelEx(self.orbModel, o.at, v3(0, 1, 0), mathx.degrees(o.spin), v3(1, 1, 1), rl.Color.white);
        }
        for (&self.mists) |*g| {
            const a = g.amt();
            if (a <= 0.02) continue;
            rl.drawSphereEx(v3(g.at.x, g.at.y + MIST_R * 0.16, g.at.z), MIST_R * (0.55 + 0.45 * a), 10, 6, mathx.withAlpha(MIST_COL, mathx.u8f(46.0 * a)));
        }
        foe.drawParticles(&self.parts);
    }

    pub fn pierce(self: *Conclave, blade: foe.Blade) bool {
        return foe.pierceGroup(self.live(), blade);
    }
    pub fn anyDied(self: *const Conclave) bool {
        return foe.anyDied(self.liveConst());
    }
    pub fn soulsDropped(self: *const Conclave) u32 {
        return foe.soulsDropped(self.liveConst(), MG_SOULS);
    }
    pub fn totalHits(self: *const Conclave) u32 {
        return foe.totalHits(self.liveConst());
    }
    pub fn aliveCount(self: *const Conclave) u32 {
        return foe.aliveCount(self.liveConst());
    }
};

const DUO_PARTS: usize = 96;

fn drawCap(c: *const Cap) void {
    const g = c.grown();
    const up = c.r * g;
    const stem = v3(c.at.x, c.at.y + up * 0.42, c.at.z);
    rl.drawCylinderEx(c.at, stem, c.r * 0.16, c.r * 0.22, 6, RIND_LT);
    // **IT GLOWS BEFORE IT GOES.** The cap's colour IS its clock: nothing else says the thing is about to
    // happen, and a warning you have to remember is not a warning.
    const heat = c.heat();
    const col = mathx.lerpColor(CAP_COL, mathx.withAlpha(CHAOS_CORE, 255), heat);
    rl.drawSphereEx(v3(stem.x, stem.y + up * 0.22, stem.z), up * 0.46, 7, 6, col);
    if (heat > 0.02) {
        const puff = up * (0.55 + 0.55 * heat) * (1.0 + 0.10 * mathx.sinf(c.t * 20.0));
        rl.drawSphereEx(v3(stem.x, stem.y + up * 0.22, stem.z), puff, 7, 6, mathx.withAlpha(CHAOS_CORE, mathx.u8f(70.0 * heat)));
    }
}

/// An orb in flight and a cap in the ground belong to nobody standing there — they ARE the ground, so they
/// answer for the hero and for nothing else. A `Threat` with no spirit and no owner is what says that.
const GROUND_THREAT = foe.Threat{};

const MIST_COL = rgba(178, 196, 150, 255);

test "THE TWO BANDS ABUT, so there is no ring where neither of them is answering" {
    try std.testing.expect(MG_FLEE_R > SW_SLASH_R);
    try std.testing.expect(SW_LUNGE_MAX > MG_FLEE_R);
    std.debug.print("\n  duo: sword swings to {d:.1} m and lunges to {d:.1}; the magus flees inside {d:.1} and keeps to {d:.1}\n", .{ SW_SLASH_R, SW_LUNGE_MAX, MG_FLEE_R, MG_KEEP_R });
    try std.testing.expect(MG_KEEP_R < AGGRO_R);
}

test "EVERY BAND OF THE SWORDSMAN PICKS A MOVE, and a bearing he cannot reach is a hard gate" {
    var d: f32 = 0;
    while (d <= AGGRO_R) : (d += 0.25) {
        try std.testing.expect(swClassify(d, 0, true, true, true, false) != .hold);
    }
    try std.testing.expectEqual(SwChoice.hold, swClassify(AGGRO_R + 1.0, 0, true, true, true, false));
    try std.testing.expectEqual(SwChoice.back, swClassify(1.0, 0, true, true, true, true));
    try std.testing.expectEqual(SwChoice.slash, swClassify(1.0, 0, true, true, false, true));
    try std.testing.expectEqual(SwChoice.slash, swClassify(SW_SLASH_R - 0.1, 0, true, true, false, false));
    try std.testing.expectEqual(SwChoice.lunge, swClassify(SW_LUNGE_MIN + 0.1, 0, false, true, false, false));
    try std.testing.expectEqual(SwChoice.close, swClassify(6.0, 0, false, false, false, false));
    inline for (.{ @as(f32, 1.0), @as(f32, -1.0) }) |sgn| {
        const wide = sgn * (swSlashArc() + 0.05);
        try std.testing.expectEqual(SwChoice.close, swClassify(SW_SLASH_R - 0.1, wide, true, false, false, false));
        const wideL = sgn * (swLungeArc() + 0.05);
        try std.testing.expectEqual(SwChoice.close, swClassify(SW_LUNGE_MIN + 0.1, wideL, false, true, false, false));
    }
    std.debug.print("  sword: swings to {d:.1} m inside {d:.0} deg, lunges {d:.1}..{d:.1} inside {d:.0} deg\n", .{
        SW_SLASH_R, mathx.degrees(swSlashArc()), SW_LUNGE_MIN, SW_LUNGE_MAX, mathx.degrees(swLungeArc()),
    });
}

test "THE MAGUS NEVER CLOSES, and being pressed outranks casting" {
    try std.testing.expectEqual(MgChoice.back, mgClassify(MG_FLEE_R - 0.1, true, true, false, false));
    try std.testing.expectEqual(MgChoice.vanish, mgClassify(MG_FLEE_R - 0.1, true, true, true, true));
    try std.testing.expectEqual(MgChoice.back, mgClassify(MG_FLEE_R - 0.1, true, true, false, true));
    try std.testing.expectEqual(MgChoice.sprout, mgClassify(MG_SPROUT_MIN + 0.1, true, true, false, false));
    try std.testing.expectEqual(MgChoice.orb, mgClassify(MG_SPROUT_MIN + 0.1, true, false, false, false));
    try std.testing.expectEqual(MgChoice.hold, mgClassify(AGGRO_R + 1.0, true, true, true, true));
    var d: f32 = 0;
    while (d <= AGGRO_R) : (d += 0.25) {
        const c = mgClassify(d, false, false, false, false);
        try std.testing.expect(c == .back or c == .keep);
    }
}

test "A BUNCH GROWS LONGER THAN IT GLOWS, and the glow is the last warning" {
    var duo = Conclave{ .model = undefined, .orbModel = undefined };
    duo.sow(mathx.ground(0, 0));
    var n: usize = 0;
    for (&duo.caps) |*c| n += @intFromBool(c.live);
    try std.testing.expectEqual(MG_BUNCH, n);
    for (&duo.caps) |*c| {
        if (!c.live) continue;
        try std.testing.expect(mathx.distXZ(c.at, mathx.ground(0, 0)) >= MG_BUNCH_R * 0.2);
        try std.testing.expect(mathx.distXZ(c.at, mathx.ground(0, 0)) <= MG_BUNCH_R + 1e-3);
    }
    var c0 = Cap{ .live = true };
    c0.t = CAP_GROW * 0.5;
    try std.testing.expectApproxEqAbs(@as(f32, 0), c0.heat(), 1e-6);
    c0.t = CAP_GROW + CAP_GLOW;
    try std.testing.expectApproxEqAbs(@as(f32, 1), c0.heat(), 1e-6);
    std.debug.print("  a bunch of {d}: {d:.1} s of growing, {d:.2} s of glowing, then {d:.1} m of burst\n", .{ MG_BUNCH, CAP_GROW, CAP_GLOW, CAP_BURST_R });
}

test "CLEARING THE FIELD CLEARS THE BODIES TOO, not just what they left on it" {
    // `game.clearFoes` calls this on every group and reads nothing back — a `clear` that only swept the ground
    // emptied the pools and left the casters standing in the shot it was called to empty.
    var duo = Conclave{ .model = undefined, .orbModel = undefined };
    duo.magi[0] = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.3);
    duo.n = 1;
    duo.caps[0] = .{ .live = true };
    duo.mists[0] = .{ .live = true };
    duo.clear();
    try std.testing.expectEqual(@as(usize, 0), duo.liveConst().len);
    try std.testing.expect(!duo.caps[0].live and !duo.mists[0].live);
}

test "THE MIST THICKENS BEFORE IT BILLS, then bills on entry and on the clock" {
    var duo = Conclave{ .model = undefined, .orbModel = undefined };
    duo.mist(mathx.ground(0, 0));
    const dt: f32 = 1.0 / 60.0;
    try std.testing.expectEqual(@as(f32, 0), duo.breath(mathx.ground(0.5, 0), dt));
    var t: f32 = 0;
    while (t < MIST_LIFE * 0.25) : (t += dt) {
        for (&duo.mists) |*g| {
            if (g.live) g.t += dt;
        }
    }
    const first = duo.breath(mathx.ground(0.5, 0), dt);
    const after = duo.breath(mathx.ground(0.5, 0), dt);
    try std.testing.expect(first > after * 10.0);
    try std.testing.expectApproxEqAbs(MIST_BUILD * foe.ENTRY_BOLUS, first, 1e-4);
    try std.testing.expectEqual(@as(f32, 0), duo.breath(mathx.ground(MIST_R + 2.0, 0), dt));
    while (t < MIST_LIFE) : (t += dt) {
        for (&duo.mists) |*g| {
            if (g.live) g.t += dt;
        }
    }
    try std.testing.expectEqual(@as(f32, 0), duo.breath(mathx.ground(0.5, 0), dt));
    std.debug.print("  mist: {d:.1} m across for {d:.1} s, {d:.0} sleep a second inside it" ++ "\n", .{ MIST_R, MIST_LIFE, MIST_BUILD });
}

test "BOTH ARE TALL AND STURDY, and the swordsman is the one that hits" {
    const crown = SCALE * H;
    std.debug.print("  duo: {d:.2} m to the crown; sword {d:.0} HP / {d:.0} poise, magus {d:.0} / {d:.0}\n", .{ crown, SW_HP, SW_POISE, MG_HP, MG_POISE });
    try std.testing.expect(crown > heromod.H * 1.25);
    try std.testing.expect(SW_POISE > MG_POISE);
    try std.testing.expect(SW_HP > MG_HP);
    // **THE MARGIN OVER THE ORB IS THE COMMITMENT'S, NOT THE BREAD-AND-BUTTER STROKE'S.** The owner's second
    // cut to the steel put one slash (18) inside 1.5x of the orb (14) and the bar failed; the orb was left
    // where it is because it is pure chaos, and cutting it would come off the VENOM the fight is clocked on.
    try std.testing.expect(SW_SLASH_HIT.raw() > ORB_HIT.raw());
    try std.testing.expect(SW_LUNGE_HIT.raw() > ORB_HIT.raw() * 1.5);
}

test "THE SEAMS HOLD — every pose track starts where the one before it ended" {
    const pairs = .{
        .{ &SW_SLASH_WIND_KEYS, &SW_SLASH_KEYS },
        .{ &SW_SLASH_KEYS, &SW_SLASH2_KEYS },
        .{ &SW_SLASH_KEYS, &SW_REC_KEYS },
        .{ &SW_LUNGE_WIND_KEYS, &SW_LUNGE_KEYS },
        .{ &SW_LUNGE_KEYS, &SW_BACK_KEYS },
        .{ &MG_ORB_WIND_KEYS, &MG_ORB_KEYS },
        .{ &MG_SPROUT_WIND_KEYS, &MG_SPROUT_KEYS },
        .{ &MG_SPROUT_KEYS, &MG_REC_KEYS },
    };
    inline for (pairs) |p| {
        const endA = samplePose(p[0], 1.0);
        const startB = samplePose(p[1], 0.0);
        for (endA, startB) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
    }
    for (samplePose(&SW_SLASH_WIND_KEYS, 0.0), SW_CARRY.chan()) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
    for (samplePose(&MG_ORB_WIND_KEYS, 0.0), MG_CARRY.chan()) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-5);
}

test "THE BLADE LANDS ON THE MAN WHERE HE STANDS - every stroke thrown for real, anywhere its own band picks it" {
    // The knight's judge and the ogre's, asked of the third (AGENTS.md). A strip or a shot is not the test: the
    // stroke goes through the REAL `update` at a hero stood across its OWN band, with the man shoved out to
    // `closestApproach` as `env.resolveActor` would, and it has to bill a hit at every stand the pick allows.
    const dt = 1.0 / 120.0;
    const probe = Swordsman.spawn(mathx.zero3, 0, 1.0, 0.0);
    const apart = foe.closestApproach(probe.bodyR());
    const rows = [_]struct { name: []const u8, wind: SwState, strike: SwState, pick: SwChoice, near: f32, far: f32 }{
        .{ .name = "slash", .wind = .slash_wind, .strike = .slash, .pick = .slash, .near = apart, .far = SW_SLASH_R },
        .{ .name = "lunge", .wind = .lunge_wind, .strike = .lunge, .pick = .lunge, .near = SW_LUNGE_MIN, .far = SW_LUNGE_MAX },
    };
    var misses: usize = 0;
    var thrown: usize = 0;
    var refused: usize = 0;
    for (rows) |row| {
        for ([_]f32{ 0, 45, 100, 165 }) |deg| {
            for ([_]f32{ 0.0, 0.34, 0.67, 1.0 }) |u| {
                const stand = lerpF(mathx.maxF(row.near, apart) + 0.05, row.far * 0.97, u);
                const off = mathx.radians(deg);
                // A GATE IS A STAND HE NEVER THROWS IT FROM, not a stand he throws it from and misses.
                if (swClassify(stand, off, row.pick == .slash, row.pick == .lunge, false, false) != row.pick) {
                    refused += 1;
                    continue;
                }
                thrown += 1;
                var k = Swordsman.spawn(mathx.zero3, 0, 1.0, 0.0);
                var hero = v3(@sin(off) * stand, 0, @cos(off) * stand);
                k.enter(row.wind);
                var hit = false;
                var best: f32 = 1e9;
                var relAt: f32 = 0;
                var guard: usize = 0;
                while (guard < 2000) : (guard += 1) {
                    if (k.update(dt, hero, 400.0, .{}) != null) {
                        hit = true;
                        break;
                    }
                    // The lunge SHOVES a man it runs into, as `env.resolveActor` does in the game.
                    if (mathx.distXZ(k.pos, hero) < apart) {
                        const out = mathx.dirXZ(k.pos, hero);
                        hero = v3(k.pos.x + out.x * apart, 0, k.pos.z + out.z * apart);
                    }
                    const a = @abs(mathx.wrapPi(mathx.headingXZ(mathx.dirXZ(k.pos, hero)) - k.facing));
                    if (a < best) {
                        best = a;
                        relAt = mathx.distXZ(k.pos, hero);
                    }
                    if (k.state != row.wind and k.state != row.strike and k.state != .slash2) break;
                }
                if (!hit) {
                    misses += 1;
                    std.debug.print("\n  {s} at {d:.2} m, {d:.0} deg off: MISSED - came round to {d:.0} deg at best, man {d:.2} m off him then\n", .{ row.name, stand, deg, mathx.degrees(best), relAt });
                }
            }
        }
    }
    std.debug.print("  blade: {d} stands thrown for real and landed, {d} refused by a gate\n", .{ thrown, refused });
    try std.testing.expectEqual(@as(usize, 0), misses);
    // NO SILENT CAP: a gate that swallowed the whole sweep would pass this with nothing thrown.
    try std.testing.expect(thrown >= 16);
}

test "AND THE BAND IS INSIDE THE REACH - the pick never hands out a stroke that goes past him" {
    // `SW_SLASH_R` is the measured reach and not a number beside one. Measured here, dead ahead, through the
    // real `update`: the band has to sit INSIDE it or the judge above is testing a promise nothing keeps.
    const dt = 1.0 / 120.0;
    var far: f32 = 0;
    var d: f32 = 0.6;
    while (d < 6.0) : (d += 0.05) {
        var k = Swordsman.spawn(mathx.zero3, 0, 1.0, 0.0);
        k.enter(.slash_wind);
        var guard: usize = 0;
        while (guard < 900) : (guard += 1) {
            if (k.update(dt, v3(0, 0, d), 900.0, .{}) != null) {
                far = d;
                break;
            }
            if (k.state != .slash_wind and k.state != .slash and k.state != .slash2) break;
        }
    }
    std.debug.print("  blade: the slash lands out to {d:.2} m, and its band stops at {d:.2}\n", .{ far, SW_SLASH_R });
    try std.testing.expect(SW_SLASH_R <= far);
    // …and the band is worth having: a ring thinner than a step is a creature flickering in and out of range.
    try std.testing.expect(SW_SLASH_R - foe.closestApproach(SW_BODY_R * SCALE) > 0.8);
}

test "THE MAGUS COMES BACK UP OUT OF REACH, and a stagger through the fade spends it" {
    const dt = 1.0 / 120.0;
    var k = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    const hero = mathx.ground(0, 2.0);
    k.enter(.fade_out);
    k.returnTo = mathx.addV(k.pos, v3(MG_REAPPEAR_R, 0, 0));
    var guard: usize = 0;
    while (guard < 4000 and k.state != .idle) : (guard += 1) _ = k.update(dt, hero, 400.0, .{});
    try std.testing.expect(mathx.distXZ(k.pos, hero) > MG_FLEE_R);
    try std.testing.expectApproxEqAbs(@as(f32, 0), k.fade, 1e-4);
    try std.testing.expect(k.fadeCd > 0);

    var caught = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    caught.enter(.fade_out);
    var n: usize = 0;
    while (n < 30) : (n += 1) _ = caught.update(dt, hero, 400.0, .{});
    try std.testing.expect(caught.fade > 0);
    caught.stagger(true);
    try std.testing.expectApproxEqAbs(@as(f32, 0), caught.fade, 1e-6);
    try std.testing.expectApproxEqAbs(MG_FADE_CD, caught.fadeCd, 1e-4);
    try std.testing.expect(caught.state == .stunheavy);
}

test "THE VENOM IS ON EVERY STROKE, and it is the clock the fight runs on" {
    const row = combat.ailRow(.poison);
    var v = combat.Vitals.initFoe(99999, 99999, 99999);
    var strokes: usize = 0;
    while (!v.ailOn(.poison) and strokes < 60) : (strokes += 1) {
        _ = v.hit(SW_SLASH_HIT);
        // The meter only TURNS OVER on a tick, and the tick is also what decays it: struck on the clock rather
        // than all in one frame, this is the honest count.
        _ = v.tickAils(1.0 / 60.0);
    }
    std.debug.print("  venom: {d} slashes break a bare {s} bar of {d:.0}, at {d:.0} chaos a stroke" ++ "\n", .{ strokes, row.name, row.max, SW_SLASH_HIT.elem.at(.chaos) });
    try std.testing.expect(strokes >= 3 and strokes <= 12);
    try std.testing.expect(SW_LUNGE_HIT.elem.at(.chaos) > 0);
}

test "AN ORB FLIES, LANDS ON HIM AND IS SPENT - and the pool never leaks" {
    // **THE WHOLE ORB PATH WAS NEVER COMPILED.** Zig only analyses what is reached, `run` never called the
    // pair's `update`, and so a call to a `mathx.distV` that does not exist sat in the file through a green
    // suite and four clean builds. Anything the group does on its own owes a test that reaches it.
    var c = Conclave{ .model = undefined, .orbModel = undefined };
    const hero = mathx.ground(0, 9);
    c.launchOrb(v3(0, 1.6, 0), hero);
    var lit: usize = 0;
    for (&c.orbs) |*o| lit += @intFromBool(o.live);
    try std.testing.expectEqual(@as(usize, 1), lit);

    const dt = 1.0 / 120.0;
    var worst: ?foe.Blow = null;
    var t: f32 = 0;
    while (t < ORB_LIFE and worst == null) : (t += dt) c.tickOrbs(dt, hero, &worst);
    const b = worst orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(ORB_HIT.elem.at(.chaos), b.hit.elem.at(.chaos));
    // …and it is SPENT: the pool is empty again, or a caster that throws for a minute stops being able to.
    for (&c.orbs) |*o| try std.testing.expect(!o.live);
    std.debug.print("  orb: {d:.0} m/s across {d:.1} m, landed in {d:.2} s\n", .{ ORB_SPEED, mathx.distXZ(mathx.zero3, hero), t });

    // A miss expires rather than flying forever.
    c.launchOrb(v3(0, 1.6, 0), mathx.ground(0, 200));
    var u: f32 = 0;
    var junk: ?foe.Blow = null;
    while (u < ORB_LIFE + 0.5) : (u += dt) c.tickOrbs(dt, mathx.ground(300, 300), &junk);
    for (&c.orbs) |*o| try std.testing.expect(!o.live);
    try std.testing.expect(junk == null);
}

test "A BUNCH GOES OFF ONCE, on the frame it bursts, and only on what is standing in it" {
    var c = Conclave{ .model = undefined, .orbModel = undefined };
    c.sow(mathx.ground(0, 0));
    const dt = 1.0 / 120.0;
    var hits: usize = 0;
    var t: f32 = 0;
    while (t < CAP_GROW + CAP_GLOW + 1.0) : (t += dt) {
        var worst: ?foe.Blow = null;
        c.tickCaps(dt, mathx.ground(0, 0), &worst);
        if (worst != null) hits += 1;
    }
    // **ONE BLOW PER CAP AND NOT ONE PER FRAME.** A bunch overlapping you is a bunch of blows, which is the
    // cost of standing in the middle of one; a cap billing every frame of its burst is a grinder.
    try std.testing.expectEqual(MG_BUNCH, hits);
    for (&c.caps) |*cp| try std.testing.expect(!cp.live);

    // …and nothing lands on a man stood outside the ring.
    var away = Conclave{ .model = undefined, .orbModel = undefined };
    away.sow(mathx.ground(0, 0));
    var miss: usize = 0;
    var u: f32 = 0;
    while (u < CAP_GROW + CAP_GLOW + 1.0) : (u += dt) {
        var worst: ?foe.Blow = null;
        away.tickCaps(dt, mathx.ground(0, CAP_BURST_R + MG_BUNCH_R + 2.0), &worst);
        if (worst != null) miss += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), miss);
}

test "THEY WAKE ON A DISTANCE AND NOTHING ELSE - no gate, no ward, no line of sight" {
    const dt = 1.0 / 60.0;
    var sw = Swordsman.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    var mg = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.70);
    const hero = mathx.ground(0, AGGRO_R * 0.4);
    const swHome = sw.pos;
    var t: f32 = 0;
    while (t < 2.0) : (t += dt) {
        _ = sw.update(dt, hero, 400.0, .{});
        _ = mg.update(dt, hero, 400.0, .{});
    }
    std.debug.print("\n  woke: sword {d:.1} m from him (was {d:.1}), state {s}; magus {d:.1} m, state {s}\n", .{
        mathx.distXZ(sw.pos, hero), mathx.distXZ(swHome, hero), @tagName(sw.state),
        mathx.distXZ(mg.pos, hero),                             @tagName(mg.state),
    });
    // **AGGRO IS TWO DISTANCES** (`foe.Leash.tick`: how far the body is from its post, how far HE is from that
    // post, against `AGGRO_R`). It reads no ward, no fog gate and no sight. What kept this pair asleep was that
    // `run` never called their `update` at all, so the leash never ticked once — a gate would have changed
    // nothing. On bare ground with nothing else in the world, both come off their post and act.
    try std.testing.expect(sw.state != .idle or mathx.distXZ(sw.pos, swHome) > 0.1);
    try std.testing.expect(mg.state != .idle or mathx.distXZ(mg.pos, mathx.ground(0, 0)) > 0.1);
    try std.testing.expect(mathx.distXZ(sw.pos, hero) < mathx.distXZ(swHome, hero));

    // …and past the ring they stay on their post, which is the other half of the same two distances.
    var far = Swordsman.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    const away = mathx.ground(0, AGGRO_R + 12.0);
    var u: f32 = 0;
    while (u < 2.0) : (u += dt) _ = far.update(dt, away, 400.0, .{});
    try std.testing.expectApproxEqAbs(@as(f32, 0), mathx.distXZ(far.pos, mathx.ground(0, 0)), 0.01);
}

/// **WHAT A BODY ACTUALLY BILLS PER SECOND OF CONTACT**, off the real state machine and not off a row of the
/// hit table: raw damage summed over `secs` of a foe fighting a hero who stands his ground at `stand` metres.
/// The clocks, the recovers and the cooldowns are all in it, which is the only way a chain of two cheap strokes
/// can be told from one expensive one.
/// How much harder the PAIR may be than the one body the knight is. Two abreast is more than one, and the
/// ground the magus lays is a third thing on the field — but a fight that bills three times the first boss is
/// not "harder", it is a different game.
const PAIR_OVER_KNIGHT: f32 = 1.60;

/// Everything the caster's side puts on a man who will not move: the orbs in the air and the bunches under him.
fn conclaveDps(stand: f32, secs: f32) f32 {
    const dt = 1.0 / 60.0;
    const hero = mathx.ground(0, stand);
    var c = Conclave{ .model = undefined, .orbModel = undefined };
    c.magi[0] = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.70);
    c.n = 1;
    var total: f32 = 0;
    var t: f32 = 0;
    while (t < secs) : (t += dt) {
        c.magi[0].leash.noteSeen();
        if (c.update(dt, hero, 400.0, .{})) |b| total += b.hit.raw();
        c.magi[0].pos = mathx.ground(0, 0);
    }
    return total / secs;
}

fn dpsAgainst(f: anytype, stand: f32, secs: f32) f32 {
    const dt = 1.0 / 60.0;
    const hero = mathx.ground(0, stand);
    var total: f32 = 0;
    var t: f32 = 0;
    while (t < secs) : (t += dt) {
        f.leash.noteSeen();
        if (f.update(dt, hero, 400.0, .{})) |h| total += h.raw();
        // He holds the ground: a stand-in is what a DPS bar is measured over, so the body is put back on its post.
        f.pos = mathx.ground(0, 0);
    }
    return total / secs;
}

test "AND NOTHING HERE OUT-EARNS THE FIRST BOSS PER SECOND EITHER" {
    // **THE HIT TABLE IS NOT THE BAR — THE CLOCK IS** (owner: DPS way too high). A stroke worth less than the
    // knight's that comes round twice as often is worth more than his, and the single-blow test below cannot
    // see that. Measured through the creature's own update at the stand each is built to fight from.
    var swWorst: f32 = 0;
    var knWorst: f32 = 0;
    var mgWorst: f32 = 0;
    for ([_]f32{ 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.5, 8.0, 10.0, 14.0 }) |stand| {
        var blade = Swordsman.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
        var plate = knightmod.Knight.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
        const sw = dpsAgainst(&blade, stand, 60.0);
        const kn = dpsAgainst(&plate, stand, 60.0);
        const mg = conclaveDps(stand, 60.0);
        swWorst = @max(swWorst, sw);
        knWorst = @max(knWorst, kn);
        mgWorst = @max(mgWorst, mg);
        std.debug.print("\n  at {d:>5.1} m: sword {d:>5.1}, magus {d:>5.1}, pair {d:>5.1} | knight {d:>5.1}", .{ stand, sw, mg, sw + mg, kn });
    }
    std.debug.print("\n  worst band: sword {d:.1}, magus {d:.1}, pair {d:.1} | knight {d:.1}\n", .{ swWorst, mgWorst, swWorst + mgWorst, knWorst });
    try std.testing.expect(swWorst > 4.0 and mgWorst > 2.0);
    // **THE SWORDSMAN ALONE MAY NOT OUT-EARN THE FIRST BOSS ALONE**, because he is one of two bodies.
    try std.testing.expect(swWorst <= knWorst);
    // …and the PAIR is a harder fight than the knight, but not a different order of one.
    try std.testing.expect(swWorst + mgWorst <= knWorst * PAIR_OVER_KNIGHT);
}

test "NOTHING HERE HITS HARDER THAN THE FIRST BOSS DOES" {
    // **THE BAR IS THE BONE KNIGHT** (owner: they do a lot of damage). Solved against his own rows rather than
    // eyeballed, so retuning either creature cannot quietly walk back over him.
    const sweep = knightmod.SWEEP_HIT.raw();
    const overhead = knightmod.OVERHEAD_HIT.raw();
    const slash = SW_SLASH_HIT.raw();
    const lunge = SW_LUNGE_HIT.raw();
    const bunch = CAP_HIT.raw() * @as(f32, @floatFromInt(MG_BUNCH));
    std.debug.print("\n  damage: slash {d:.0}, x2 chain {d:.0}, lunge {d:.0}, orb {d:.0}, a whole bunch {d:.0}" ++
        " | knight sweep {d:.0}, overhead {d:.0}\n", .{ slash, slash * 2, lunge, ORB_HIT.raw(), bunch, sweep, overhead });
    // The bread-and-butter stroke sits UNDER his bread-and-butter one, because it can be thrown twice.
    try std.testing.expect(slash < sweep);
    // The commitment sits under his commitment.
    try std.testing.expect(lunge <= overhead);
    // …and the chain is worth more than either single, or doubling means nothing.
    try std.testing.expect(slash * 2 > lunge);
    // The orb is attrition: under the cheapest thing the knight owns that is not his gas.
    try std.testing.expect(ORB_HIT.raw() < knightmod.SWAT_HIT.raw());
    // A whole bunch on your head is the worst thing in the fight, and still not two overheads.
    try std.testing.expect(bunch > overhead and bunch < overhead * 2.0);
}

test "A DISSOLVED MAGUS IS NOT THERE FOR ANY OF THE THREE QUESTIONS" {
    // `tryHit` (a blade), `game.disguised` (the lock-on) and `game.phased` (shouldering) are three separate
    // asks, and answering only the first left an invisible wall standing where it went that you could target.
    var k = Magus.spawn(mathx.ground(0, 0), 0, 1.0, 0.30);
    try std.testing.expect(!k.hidden() and !k.phased() and !k.absent());
    k.enter(.gone);
    try std.testing.expect(k.absent() and k.hidden() and k.phased());
    // …and a blade swung through it finds nothing, while the body is still ALIVE (it is coming back).
    const before = k.hits;
    _ = k.update(1.0 / 60.0, mathx.ground(0, 1), 400.0, .{
        .active = true,
        .r = 4.0,
        .a = mathx.ground(0, -1),
        .b = mathx.ground(0, 1),
        .hit = .{ .dmg = 50 },
    });
    try std.testing.expectEqual(before, k.hits);
    try std.testing.expect(k.alive());
}
