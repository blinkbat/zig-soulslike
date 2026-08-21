const std = @import("std");
const stats = @import("stats.zig");


pub const Kind = enum(u8) {
    crimson_flask,
    cerulean_flask,
    rune_arc,
    golden_seed,
    smithing_stone,
    bloodgrass,
    kobold_fang,
    iron_key,
    mushroom_jerky,
    ember_candle,
    sporeling_cap,
    second_wind,
    tower_shield,
    greatclub,
    leech_signet,
    soul_binding_ring,
    fire_tallow,
    thundercrock,
    nameless_soul,
    toadflesh_broth,
    fang_dirk,
    grave_warbow,
    quilted_gambeson,
    spirit_scroll_wolf,
    pitted_helm,
    ashen_amulet,
    banded_warbelt,
    marchboots,
    deft_signet,
    purgeleaf,
    pilgrims_salt,
    ironwort_tea,
    rimeward_mantle,
    sporecrown,
    gravebell_amulet,
    plain_arrows,
    fire_arrows,
};

pub const NK = @typeInfo(Kind).@"enum".fields.len;

const ORDER = [_][]const u8{
    "crimson_flask",   "cerulean_flask", "rune_arc",     "golden_seed",
    "smithing_stone",  "bloodgrass",     "kobold_fang",  "iron_key",
    "mushroom_jerky",  "ember_candle",   "sporeling_cap", "second_wind",
    "tower_shield",    "greatclub",      "leech_signet", "soul_binding_ring",
    "fire_tallow",     "thundercrock",   "nameless_soul", "toadflesh_broth",
    "fang_dirk",       "grave_warbow",   "quilted_gambeson", "spirit_scroll_wolf",
    "pitted_helm",     "ashen_amulet",   "banded_warbelt", "marchboots",
    "deft_signet",     "purgeleaf",      "pilgrims_salt", "ironwort_tea",
    "rimeward_mantle", "sporecrown",     "gravebell_amulet", "plain_arrows",
    "fire_arrows",
};

comptime {
    if (ORDER.len != NK) @compileError("item: a kind was added or removed without updating ORDER — a save's " ++
        "`seen:` run is positional over this enum, so the new kind must go at the END of both");
    for (ORDER, 0..) |name, i| {
        const tagName = @tagName(@as(Kind, @enumFromInt(i)));
        if (!std.mem.eql(u8, name, tagName)) @compileError("item: kind " ++ tagName ++ " is at index " ++
            std.fmt.comptimePrint("{d}", .{i}) ++ " where ORDER says " ++ name ++ " — a MOVED or INSERTED " ++
            "kind silently re-points every discovery bit in every save on disk (`save.Data.seen`). Append instead.");
    }
}

pub fn displayName(k: Kind) [:0]const u8 {
    return switch (k) {
        .crimson_flask => "Flask of Crimson Tears",
        .cerulean_flask => "Flask of Cerulean Tears",
        .rune_arc => "Rune Arc",
        .golden_seed => "Golden Seed",
        .smithing_stone => "Smithing Stone",
        .bloodgrass => "Bloodgrass",
        .kobold_fang => "Kobold Fang",
        .iron_key => "Iron Key",
        .mushroom_jerky => "Mushroom Jerky",
        .ember_candle => "Emberfat Candle",
        .sporeling_cap => "Dried Sporeling Cap",
        .second_wind => "Second Wind",
        .tower_shield => "Cracked Tower Shield",
        .greatclub => "Bog-Oak Greatclub",
        .leech_signet => "Leech Signet",
        .soul_binding_ring => "Soul Binding Ring",
        .fire_tallow => "Fire Tallow",
        .thundercrock => "Thundercrock",
        .nameless_soul => "Nameless Soul",
        .toadflesh_broth => "Toadflesh Broth",
        .fang_dirk => "Fang Dirk",
        .grave_warbow => "Grave Warbow",
        .quilted_gambeson => "Quilted Gambeson",
        .spirit_scroll_wolf => "Spirit Scroll: Hildebrand",
        .pitted_helm => "Pitted Half-Helm",
        .ashen_amulet => "Ashen Amulet",
        .banded_warbelt => "Banded Warbelt",
        .marchboots => "Sodden Marchboots",
        .deft_signet => "Signet of the Deft",
        .purgeleaf => "Purgeleaf",
        .pilgrims_salt => "Pilgrim's Salt",
        .ironwort_tea => "Ironwort Tea",
        .rimeward_mantle => "Rimeward Mantle",
        .sporecrown => "Sporecrown",
        .gravebell_amulet => "Gravebell Amulet",
        .plain_arrows => "Sheaf of Arrows",
        .fire_arrows => "Sheaf of Fire Arrows",
    };
}

pub const Class = enum {
    tool,
    treasure,
    material,
    key,
    gear,

    pub fn label(c: Class) [:0]const u8 {
        return switch (c) {
            .tool => "Tool",
            .treasure => "Treasure",
            .material => "Material",
            .key => "Key Item",
            .gear => "Equipment",
        };
    }
};

pub fn class(k: Kind) Class {
    return switch (k) {
        // **ONE PER LINE.** This is the table you read to find out where a thing shelves, and both of the long
        // arms ran past 200 columns — a row you cannot find is a row you re-add by mistake.
        .crimson_flask,
        .cerulean_flask,
        .mushroom_jerky,
        .ember_candle,
        .sporeling_cap,
        .second_wind,
        .fire_tallow,
        .thundercrock,
        .nameless_soul,
        .toadflesh_broth,
        .purgeleaf,
        .pilgrims_salt,
        .ironwort_tea,
        => .tool,
        .rune_arc,
        .golden_seed,
        => .treasure,
        .tower_shield,
        .greatclub,
        .leech_signet,
        .fang_dirk,
        .grave_warbow,
        .quilted_gambeson,
        .pitted_helm,
        .ashen_amulet,
        .banded_warbelt,
        .marchboots,
        .deft_signet,
        .rimeward_mantle,
        .sporecrown,
        .gravebell_amulet,
        => .gear,
        .soul_binding_ring => .gear,
        .spirit_scroll_wolf => .treasure,
        .plain_arrows, .fire_arrows => .tool,
        .smithing_stone, .bloodgrass, .kobold_fang => .material,
        .iron_key => .key,
    };
}

pub fn describe(k: Kind) [:0]const u8 {
    return switch (k) {
        .crimson_flask => "A flask of clouded red glass, refilled at any bonfire. The draught it holds closes wounds that ought to have killed you.",
        .cerulean_flask => "The blue twin of the crimson. It gives back half the focus a rod spends, which is two more casts of the wand before you have to walk back to a bonfire.",
        .rune_arc => "A shard of a shattered great rune, still lit from the inside. Whatever it once carried leaks out of the break; nothing here can catch it yet.",
        .golden_seed => "A sprout of gilded stalk, pulled up whole. In another age these bought another swallow from the flask. This one is only precious.",
        .smithing_stone => "A shard off a bigger stone, hard enough to bite steel. No smith has set up in these ruins to grind it against.",
        .bloodgrass => "A tuft of the red grass that grows thickest where something bled out. Common as dirt, and worth about as much.",
        .kobold_fang => "A tooth taken out of a jaw that was still using it. The crack across the root says how.",
        .iron_key => "Cold, heavy, and eaten with rust. It was cut for one lock, and that lock is somewhere in the ruins.",
        .mushroom_jerky => "Cap flesh, salted and dried until it is more leather than mushroom. Chewing it staunches you slowly, for a long while.",
        .ember_candle => "A dollop of rendered fire-fat around a wick, made to be thrown lit. It bursts on whatever it lands on; the fat still burns out too fast to pool.",
        .sporeling_cap => "A sporeling's cap, dried until the violet in it went quiet. Chewed, it steeps you in its element, and for a minute chaos slides off you.",
        .second_wind => "A curl of pale bark that smells of cold air after rain. One sharp breath of it and your legs remember themselves.",
        .tower_shield => "A door of a shield, cracked through and banded in old iron. Behind it almost nothing gets through and almost nothing gets round, and you walk at the pace a door walks.",
        .greatclub => "Bog-oak shod with iron, heavier than it looks, and it looks heavy. It hits half again as hard as the sword and takes half again as long to get there, and things that shrug a blade off do not shrug this off.",
        .leech_signet => "A signet cut from a leech's beak, warm against the skin. It gives back a little of every swing of yours that lands, and it takes a bite out of the bar it is filling to do it.",
        .soul_binding_ring => "A thin gold band with a hairline already run through it. Die with one on you and the RING gives instead: it snaps, and what you were carrying stays carried.",
        .fire_tallow => "Rendered fire-fat, unlit, in a waxed twist of cloth. Wiped along an edge it clings and burns: for a minute the sword hangs fire on top of what it always did.",
        .thundercrock => "A squat clay jar that hums against the palm, thrown like the candle. It cracks on what it lands on and the sky's own spark gets out - the only lightning anywhere in these ruins.",
        .nameless_soul => "Someone's whole worth, gone cold and hard enough to carry. Crushed in the fist it is worth a middling foe's souls, and nobody walks back for these.",
        .toadflesh_broth => "Toad shanks boiled pale, drunk cold from the skin they cooked in. It sits heavy and warm, and for a minute your wind comes back the faster for it.",
        .fang_dirk => "A dirk ground out of the longest fang in a kobold's jaw, hafted in cord. It goes in and comes back before a sword has finished the stroke, and it takes about three quarters as much with it.",
        .grave_warbow => "A warbow of grave-oak, its draw twice the skeletons' hunting bows. The shaft it looses is worth stopping for; getting it up and holding it there costs you.",
        .quilted_gambeson => "A coat of rag-stuffed linen, stitched in diamonds and stained by whoever wore it last. It turns the edge off a blow, and off a small one by more than a big one.",
        .spirit_scroll_wolf => "A hide scroll gone stiff as board, the wolf on it drawn in one unbroken line. A name is written under it - Hildebrand - and a bell that knows the name can call the shape; what answers is grey, half there, and already running.",
        .pitted_helm => "An open-faced helm eaten to lace along one cheek, the crown still sound. It turns the edge off what reaches your head, which is less of you than the coat covers and a worse place to be reached.",
        .ashen_amulet => "A grey bead on a thong, warm out of all proportion to the weather. Wearing it the rod answers quicker than your hand does, and what it throws lands harder.",
        .banded_warbelt => "A wide belt of banded leather, cut for a bigger man and punched with a new hole. Cinched hard it braces the back, and a heavy thing swung out of braced hips is a heavier thing.",
        .marchboots => "Boots that have not been dry in years, soles worn through to the second layer of hide. They stop what comes at your feet, which is less than you would think and more than nothing.",
        .deft_signet => "A plain band with the inside worn to a knife-edge by somebody's restless thumb. It steadies the wrist, and a steadied wrist puts a point where it was aimed.",
        .purgeleaf => "A grey-green leaf that grows only downwind of the spore beds, thick as felt and bitter enough to make your eyes run. Chewed, it takes whatever is in you back out the way it came in.",
        .pilgrims_salt => "A grey brick of salt, pressed in a mould and thumbed smooth by whoever carried it last. There is more of somebody in this than in a nameless soul, and it went just as cold.",
        .ironwort_tea => "Bitter root steeped until the water goes the colour of rust, drunk lukewarm. It settles the wind out of you: what a blow knocks loose comes back the quicker for a while.",
        .rimeward_mantle => "A mantle of layered fleece and oiled hide, cut for a winter these ruins do not have. The cold slides off it, and off you - which is worth knowing where anything at all deals cold.",
        .sporecrown => "A cap of woven stalk-fibre, still faintly warm, the inside furred with something that eats spores for a living. What gets past it gets past slowly.",
        .gravebell_amulet => "A finger of bell-bronze on a thong, cracked through and still ringing on if you hold it to the ear. A call made near it costs less to make; what it takes for the loan is depth out of the pool the call comes from.",
        .plain_arrows => "A dozen shafts bundled in oiled cord, fletched with whatever still had feathers. They go in the quiver and most of them come back out of whatever you hit.",
        .fire_arrows => "Five heads wrapped in tallow-soaked rag. They cost more than they are worth against anything that is not afraid of burning, and rather less against anything that is.",
    };
}

pub const Use = union(enum) {
    none,
    /// Refills one bank of the quiver (`combat.Quiver`). `n` is arrows, and the quiver caps it.
    arrows: struct { fire: bool, n: u8 },
    regen: struct { frac: f32, secs: f32 },
    lob: struct { dmg: f32, fire: f32 = 0, lightning: f32 = 0, poise: f32 },
    /// A timed ward: `chaos` resistance for `secs` seconds. Refreshes, never stacks (the status law).
    ward: struct { chaos: f32, secs: f32 },
    wind: struct { share: f32 },
    grease: struct { frac: f32, secs: f32 },
    souls: struct { n: u32 },
    brew: struct { mult: f32, secs: f32 },
    purge,
    steady: struct { mult: f32, secs: f32 },
};

/// `book.SlotId`'s own subset, named HERE because which socket a thing belongs in is a fact about the THING.
/// This file imports nothing but std, so `hero.wearFor` is the one place the two are matched up.
/// **APPEND-ONLY, for `save.Data.worn`'s sake** — the `worn:` line is one word per socket in THIS order and
/// the parser stops at the end of a short line, so an older save loads with the new sockets empty. Inserting
/// a tag re-points every word on every line on disk.
pub const Wear = enum {
    hand_sword,
    hand_bow,
    hand_shield,
    chest,
    ring,
    helm,
    neck,
    belt,
    feet,
    ring2,

    pub fn held(w: Wear) bool {
        return w == .hand_sword or w == .hand_bow or w == .hand_shield;
    }
};

/// **PRICED AS MULTIPLIERS ON THE ONE IT REPLACES**, never a fresh set of absolutes: `hero.ATK_*_HIT`,
/// `combat.STAM_*` and `combat.GUARD_*` stay the single place a swing, a block and their bills are written,
/// and a weapon says only how it DIFFERS. Bare-handed every dial is 1.
/// **WHICH SKILL DRIVES A WEAPON** — ER's scaling letters, ONE per armament rather than one per attribute.
/// `quality` is the MEAN of the two curves, so either build carries the starting sword and neither is best
/// with it. `hero.scaleOf` maps to a `stats.Attr`, `stats.scaleFor` is the curve.
pub const Scaling = enum { strength, dexterity, quality };

/// **WHAT KIND OF WEAPON IT IS, ON THE TWO AXES A FIGHT ACTUALLY ASKS ABOUT.** `reach` is where the blow
/// lands from and is pinned to the socket below — a thing in the bow hand is the ranged one, and there is no
/// third answer. `heft` is how much of the body goes into it: the multipliers say a club is slower and hits
/// harder, but only this says it is swung like a club, and `hero.swingOf` reads it for the pose.
pub const Heft = enum {
    light,
    heavy,

    pub fn label(h: Heft) [:0]const u8 {
        return switch (h) {
            .light => "Light",
            .heavy => "Heavy",
        };
    }
};

pub const Reach = enum {
    melee,
    ranged,

    pub fn label(r: Reach) [:0]const u8 {
        return switch (r) {
            .melee => "melee",
            .ranged => "ranged",
        };
    }
};

pub const Arm = struct {
    slot: Wear,
    heft: Heft = .light,
    reach: Reach = .melee,
    dmg: f32 = 1,
    poise: f32 = 1,
    scales: Scaling = .quality,
    dur: f32 = 1,
    stam: f32 = 1,
    negate: f32 = 1,
    arc: f32 = 1,
    walk: f32 = 1,
};

pub const Res = struct { fire: f32 = 0, cold: f32 = 0, lightning: f32 = 0, chaos: f32 = 0 };

/// `a` is the armour value in `A/(A + 5*dmg)` (`combat.armourTaken`), `res` the four elemental columns, and
/// `poison` a MULTIPLIER on how fast a status meter fills — one row, not three verbs each stacked separately.
pub const Plate = struct { slot: Wear, a: f32 = 0, res: Res = .{}, poison: f32 = 1 };

pub const Charm = struct { slot: Wear, leech: f32 = 0, hpFrac: f32 = 0, spiritFp: f32 = 1, fpFrac: f32 = 0 };

pub const Boon = struct { slot: Wear, attr: stats.Attr, n: u8 };

pub const Bind = struct { slot: Wear };

pub const Equip = union(enum) {
    none,
    arm: Arm,
    plate: Plate,
    charm: Charm,
    boon: Boon,
    bind: Bind,
};

/// **THE BARE ARMAMENT'S ROW** — every dial 1, and the skill that drives the thing he was born holding. An empty
/// socket may not inherit the sword's `quality` default and quietly pay a bowman for his strength.
pub fn bareArm(w: Wear) Arm {
    return .{
        .slot = w,
        .scales = if (w == .hand_bow) .dexterity else .quality,
        .reach = if (w == .hand_bow) .ranged else .melee,
    };
}

pub const Gear = struct {
    kind: Kind,
    equip: Equip = .none,
    use: Use = .none,
};

pub const GEAR = [_]Gear{
    .{ .kind = .fang_dirk, .equip = .{ .arm = .{ .slot = .hand_sword, .heft = .light, .dmg = 0.74, .poise = 0.72, .dur = 0.78, .stam = 0.76, .scales = .dexterity } } },
    .{ .kind = .greatclub, .equip = .{ .arm = .{ .slot = .hand_sword, .heft = .heavy, .dmg = 1.48, .poise = 1.60, .dur = 1.34, .stam = 1.48, .scales = .strength } } },
    .{ .kind = .grave_warbow, .equip = .{ .arm = .{ .slot = .hand_bow, .heft = .heavy, .reach = .ranged, .dmg = 1.62, .poise = 1.45, .dur = 1.28, .stam = 1.34, .scales = .dexterity } } },
    // A DOOR — half again the compass of the small shield, at four fifths of the speed and more per blow.
    // **THE NEGATION DIAL STOPS UNDER THE CAP ON PURPOSE**: `combat.GUARD_NEGATE_CAP` is 0.95 on a 0.85 base,
    // so anything past ~1.118 is silently clamped — and `effect` PRINTS this figure, so a clamped dial is a
    // number the fight does not honour. The cap is for stopping a shield PLUS a tree node being free.
    .{ .kind = .tower_shield, .equip = .{ .arm = .{ .slot = .hand_shield, .heft = .heavy, .negate = 1.10, .arc = 1.45, .walk = 0.80, .stam = 1.30 } } },
    .{ .kind = .quilted_gambeson, .equip = .{ .plate = .{ .slot = .chest, .a = 22.0 } } },
    .{ .kind = .leech_signet, .equip = .{ .charm = .{ .slot = .ring, .leech = 2.0, .hpFrac = 0.06 } } },
    .{ .kind = .pitted_helm, .equip = .{ .plate = .{ .slot = .helm, .a = 14.0 } } },
    .{ .kind = .marchboots, .equip = .{ .plate = .{ .slot = .feet, .a = 9.0 } } },
    .{ .kind = .banded_warbelt, .equip = .{ .boon = .{ .slot = .belt, .attr = .strength, .n = 3 } } },
    .{ .kind = .deft_signet, .equip = .{ .boon = .{ .slot = .ring2, .attr = .dexterity, .n = 3 } } },
    .{ .kind = .ashen_amulet, .equip = .{ .boon = .{ .slot = .neck, .attr = .intelligence, .n = 3 } } },
    // **THE FIRST COLD RESISTANCE ANYWHERE ON HIS SIDE** — the necromancer's rune ring is the game's one
    // source of cold and the sheet showed 0%. PHYSICAL under the gambeson's on purpose: a chest socket
    // strictly better than the coat already in it retires that coat instead of competing with it.
    .{ .kind = .rimeward_mantle, .equip = .{ .plate = .{ .slot = .chest, .a = 13.0, .res = .{ .cold = 35 } } } },
    .{ .kind = .sporecrown, .equip = .{ .plate = .{ .slot = .helm, .a = 8.0, .poison = 0.55 } } },
    .{ .kind = .gravebell_amulet, .equip = .{ .charm = .{ .slot = .neck, .spiritFp = 0.60, .fpFrac = 0.10 } } },
    .{ .kind = .soul_binding_ring, .equip = .{ .bind = .{ .slot = .ring } } },
    .{ .kind = .mushroom_jerky, .use = .{ .regen = .{ .frac = 0.60, .secs = 20.0 } } },
    .{ .kind = .ember_candle, .use = .{ .lob = .{ .dmg = 8, .fire = 22, .poise = 12 } } },
    .{ .kind = .sporeling_cap, .use = .{ .ward = .{ .chaos = 40, .secs = 60 } } },
    .{ .kind = .second_wind, .use = .{ .wind = .{ .share = 0.5 } } },
    .{ .kind = .fire_tallow, .use = .{ .grease = .{ .frac = 0.5, .secs = 60 } } },
    .{ .kind = .thundercrock, .use = .{ .lob = .{ .dmg = 8, .lightning = 22, .poise = 12 } } },
    .{ .kind = .nameless_soul, .use = .{ .souls = .{ .n = 150 } } },
    .{ .kind = .toadflesh_broth, .use = .{ .brew = .{ .mult = 1.5, .secs = 60 } } },
    .{ .kind = .purgeleaf, .use = .purge },
    .{ .kind = .pilgrims_salt, .use = .{ .souls = .{ .n = 600 } } },
    .{ .kind = .ironwort_tea, .use = .{ .steady = .{ .mult = 2.2, .secs = 40 } } },
    // **AMMUNITION IS AN ITEM NOW** (owner: arrows need to be droppable, placeable, all kinds) — both banks.
    // **SIZED TO THE BANK, NOT GUESSED**: 12 into a quiver of 10 wasted two shafts on every pickup. This file
    // imports nothing but std, so it cannot read `combat.ARROWS_MAX` and a test holds the two together.
    .{ .kind = .plain_arrows, .use = .{ .arrows = .{ .fire = false, .n = 10 } } },
    .{ .kind = .fire_arrows, .use = .{ .arrows = .{ .fire = true, .n = 5 } } },
};

pub const INERT = [_]Kind{
    .crimson_flask,  .cerulean_flask, .rune_arc,    .golden_seed,
    .smithing_stone, .bloodgrass,     .kobold_fang, .iron_key,
    .spirit_scroll_wolf,
};

comptime {
    if (GEAR.len + INERT.len != NK) @compileError("item: every Kind must be in GEAR or named in INERT, exactly once");
    var seen = [_]bool{false} ** NK;
    for (GEAR) |g| {
        if (seen[@intFromEnum(g.kind)]) @compileError("item: " ++ @tagName(g.kind) ++ " has two rows in GEAR");
        seen[@intFromEnum(g.kind)] = true;
    }
    for (INERT) |k| {
        if (seen[@intFromEnum(k)]) @compileError("item: " ++ @tagName(k) ++ " is both in GEAR and named INERT");
        seen[@intFromEnum(k)] = true;
    }
}

const BY_KIND: [NK]Gear = blk: {
    var out: [NK]Gear = undefined;
    for (0..NK) |i| out[i] = .{ .kind = @enumFromInt(i) };
    for (GEAR) |g| out[@intFromEnum(g.kind)] = g;
    break :blk out;
};

pub fn equip(k: Kind) Equip {
    return BY_KIND[@intFromEnum(k)].equip;
}

pub fn use(k: Kind) Use {
    return BY_KIND[@intFromEnum(k)].use;
}


pub fn wearable(k: Kind) bool {
    return std.meta.activeTag(equip(k)) != .none;
}

pub fn wearSlot(k: Kind) ?Wear {
    return switch (equip(k)) {
        .none => null,
        .arm => |a| a.slot,
        .plate => |p| p.slot,
        .charm => |c| c.slot,
        .boon => |b| b.slot,
        .bind => |b| b.slot,
    };
}

comptime {
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        switch (equip(k)) {
            .arm => |a| {
                const guardDials = a.negate != 1 or a.arc != 1 or a.walk != 1;
                const bladeDials = a.dmg != 1 or a.poise != 1;
                if (a.slot == .hand_shield and bladeDials) @compileError("item: " ++ @tagName(k) ++
                    " is a shield with damage or poise on it — a board does not swing, and those dials are dead here");
                if (a.slot != .hand_shield and guardDials) @compileError("item: " ++ @tagName(k) ++
                    " sets shield dials but is not a shield — `negate`/`arc`/`walk` are only read of the guard");
                if (!a.slot.held()) @compileError("item: " ++ @tagName(k) ++ " is an armament in a worn socket");
                if ((a.slot == .hand_bow) != (a.reach == .ranged)) @compileError("item: " ++ @tagName(k) ++
                    " disagrees with its own socket about reach — the bow hand IS the ranged one, and a melee " ++
                    "row in it (or a ranged row out of it) is a weapon the fight would swing and shoot both");
            },
            .plate => |p| if (p.slot.held()) @compileError("item: " ++ @tagName(k) ++ " is armour in a hand"),
            .charm => |c| if (c.slot.held()) @compileError("item: " ++ @tagName(k) ++ " is a charm in a hand"),
            .bind => |b| if (b.slot != .ring and b.slot != .ring2) @compileError("item: " ++ @tagName(k) ++
                " binds souls from a socket that is not a finger — the ring is the mechanic's whole tell"),
            .boon => |b| {
                if (b.slot.held()) @compileError("item: " ++ @tagName(k) ++ " is a boon in a hand");
                if (b.n == 0) @compileError("item: " ++ @tagName(k) ++ " grants zero points — a boon of nothing");
                if (stats.inert(b.attr)) @compileError("item: " ++ @tagName(k) ++ " grants " ++
                    @tagName(b.attr) ++ ", which nothing reads — the gear would be honestly inert");
            },
            .none => {},
        }
    }
    for (@typeInfo(Wear).@"enum".fields) |wf| {
        const w: Wear = @enumFromInt(wf.value);
        if (w.held()) continue;
        var any = false;
        for (0..NK) |i| {
            if (wearSlot(@enumFromInt(i)) == w) any = true;
        }
        if (!any) @compileError("item: nothing in the world goes in the " ++ wf.name ++
            " socket — the book would draw a hole that can never be filled");
    }
}

fn plateElem(r: Res) ?struct { name: []const u8, amount: f32 } {
    if (r.fire != 0) return .{ .name = "fire", .amount = r.fire };
    if (r.cold != 0) return .{ .name = "cold", .amount = r.cold };
    if (r.lightning != 0) return .{ .name = "lightning", .amount = r.lightning };
    if (r.chaos != 0) return .{ .name = "chaos", .amount = r.chaos };
    return null;
}


pub fn usable(k: Kind) bool {
    return std.meta.activeTag(use(k)) != .none;
}

pub fn dosed(k: Kind) bool {
    return switch (use(k)) {
        inline else => |payload| @TypeOf(payload) != void,
    };
}

/// **WHAT IT DOES, IN ONE LINE OF MECHANIC** — the answer to "which of these two flasks did I just put in the
/// box", which the flavour prose (`describe`) deliberately does not give. Read off `use` wherever there is a
/// `Use` to read, so a dose retuned there reads here and the two cannot drift.
pub fn effect(k: Kind, buf: []u8) [:0]const u8 {
    if (isFlask(k)) return switch (k) {
        .crimson_flask => "Heals. Charges refill at a bonfire, not from the bag.",
        else => "Restores Focus. Charges refill at a bonfire, not from the bag.",
    };
    if (k == .spirit_scroll_wolf) return "Carried: the bell can call Hildebrand.";
    if (k == .iron_key) return "Opens the one lock it was cut for.";
    // GEAR SAYS WHAT IT DOES IN THE SAME PLACE A TOOL DOES, off `equip` for the same reason the tools read
    // `use`: a dial retuned in the table reads here, and the two cannot drift.
    switch (equip(k)) {
        .none => {},
        .arm => |a| return switch (a.slot) {
            .hand_shield => std.fmt.bufPrintZ(buf, "{s} {s}: blocks {d:.0}% more, covers {d:.0}% wider, walks at {d:.0}%.", .{
                a.heft.label(),
                a.reach.label(),
                (a.negate - 1) * 100,
                (a.arc - 1) * 100,
                a.walk * 100,
            }) catch "Held: a bigger shield.",
            else => std.fmt.bufPrintZ(buf, "{s} {s}: {d:.0}% damage, {d:.0}% poise, {d:.0}% {s} time.", .{
                a.heft.label(),
                a.reach.label(),
                a.dmg * 100,
                a.poise * 100,
                a.dur * 100,
                if (a.reach == .ranged) @as([]const u8, "draw") else "swing",
            }) catch "Held: its own weight and speed.",
        },
        // **THE ROW PRINTS WHAT IT ACTUALLY CARRIES, NOT ALL FOUR COLUMNS.** A coat that turns no cold has no
        // business saying "0% cold" on the one panel a player compares two coats on, and a helm whose whole
        // point is the spore meter cannot have that hidden behind an armour figure it barely has.
        .plate => |p| {
            const el = plateElem(p.res);
            if (el != null and p.poison != 1) return std.fmt.bufPrintZ(buf, "Worn: {d:.0} armour, {d:.0}% {s}, poison fills at {d:.0}%.", .{
                p.a, el.?.amount, el.?.name, p.poison * 100,
            }) catch "Worn: armour and a ward.";
            if (el) |e| return std.fmt.bufPrintZ(buf, "Worn: {d:.0} armour, {d:.0}% {s} resistance.", .{ p.a, e.amount, e.name }) catch "Worn: armour and a ward.";
            if (p.poison != 1) return std.fmt.bufPrintZ(buf, "Worn: {d:.0} armour, poison fills at {d:.0}%.", .{ p.a, p.poison * 100 }) catch "Worn: armour.";
            return std.fmt.bufPrintZ(buf, "Worn: {d:.0} armour against physical damage.", .{p.a}) catch "Worn: armour.";
        },
        // …AND THE CHARM SAYS WHICHEVER BARGAIN IT IS. Both halves on one line would price the gravebell's
        // leech at zero and the signet's call at 100%, which is two numbers that mean "this row does nothing".
        .charm => |c| {
            if (c.spiritFp != 1 or c.fpFrac > 0) return std.fmt.bufPrintZ(buf, "Worn: a spirit costs {d:.0}% focus, -{d:.0}% max focus.", .{
                c.spiritFp * 100,
                c.fpFrac * 100,
            }) catch "Worn: a bargain.";
            return std.fmt.bufPrintZ(buf, "Worn: {d:.0} HP back per swing landed, -{d:.0}% max HP.", .{
                c.leech,
                c.hpFrac * 100,
            }) catch "Worn: a bargain.";
        },
        .boon => |b| return std.fmt.bufPrintZ(buf, "Worn: +{d} {s}.", .{
            b.n,
            stats.displayName(b.attr),
        }) catch "Worn: a point of skill.",
        .bind => return "Worn: a death spills no souls. The ring breaks instead.",
    }
    return switch (use(k)) {
        .none => "No effect yet.",
        .regen => |r| std.fmt.bufPrintZ(buf, "Heals {d:.0}% of max HP over {d:.0}s.", .{ r.frac * 100, r.secs }) catch "Heals over time.",
        .lob => |l| std.fmt.bufPrintZ(buf, "Thrown at the reticle: {d:.0} physical + {d:.0} {s}, {d:.0} poise.", .{
            l.dmg,
            l.fire + l.lightning,
            if (l.lightning > 0) @as([]const u8, "lightning") else "fire",
            l.poise,
        }) catch "Thrown for damage.",
        .ward => |w| std.fmt.bufPrintZ(buf, "+{d:.0} Chaos resistance for {d:.0}s. Refreshes, never stacks.", .{ w.chaos, w.secs }) catch "Wards off Chaos.",
        .wind => |w| std.fmt.bufPrintZ(buf, "Gives back {d:.0}% of stamina at once, and lets the winded lockout go.", .{w.share * 100}) catch "Gives stamina back.",
        .grease => |gr| std.fmt.bufPrintZ(buf, "Sword hangs +{d:.0}% of its blow as fire for {d:.0}s. Refreshes, never stacks.", .{ gr.frac * 100, gr.secs }) catch "Sets the blade alight.",
        .souls => |s| std.fmt.bufPrintZ(buf, "Crushed for {d} souls, on the spot.", .{s.n}) catch "Worth souls.",
        .arrows => |a| std.fmt.bufPrintZ(buf, "Puts {d} {s} arrows back in the quiver.", .{ a.n, if (a.fire) @as([]const u8, "fire") else "plain" }) catch "Refills the quiver.",
        .brew => |b| std.fmt.bufPrintZ(buf, "Stamina comes back {d:.1}x as fast for {d:.0}s. Refreshes, never stacks.", .{ b.mult, b.secs }) catch "Stamina returns faster.",
        .purge => "Clears poison outright, filling or already running.",
        .steady => |s| std.fmt.bufPrintZ(buf, "Poise comes back {d:.1}x as fast for {d:.0}s. Refreshes, never stacks.", .{ s.mult, s.secs }) catch "Poise returns faster.",
    };
}

pub const EFFECT_BUF: usize = 128;

/// THE TWO THE FLASK SYSTEM OWNS. They sit on the quick bar like anything else, but their charges live in
/// `combat.Flasks` and come back at a bonfire, so spending one never touches the bag. Named here rather than
/// in `combat` because it is a fact about the ITEM; `combat.flaskOf` is the same question answered as a
/// `FlaskKind`, and it cannot live here — `combat` imports this file and not the other way about.
pub fn isFlask(k: Kind) bool {
    return k == .crimson_flask or k == .cerulean_flask;
}

pub fn bindsSouls(k: Kind) bool {
    return std.meta.activeTag(equip(k)) == .bind;
}

pub fn quickable(k: Kind) bool {
    return isFlask(k) or usable(k);
}

pub const TAG_MAX: usize = @tagName(LONGEST_TAG).len;

/// The kind whose tag IS `TAG_MAX`. `save.CAP`'s worst case is sized off the longest tag, so the test that
/// proves the buffer holds it has to WRITE that tag — hand-picking a plausible one understated the row by two
/// characters a slot, silently, and every new item is a chance to understate it again.
pub const LONGEST_TAG: Kind = blk: {
    var worst: Kind = @enumFromInt(0);
    for (@typeInfo(Kind).@"enum".fields) |f| {
        if (f.name.len > @tagName(worst).len) worst = @enumFromInt(f.value);
    }
    break :blk worst;
};

comptime {
    // `TAG_MAX` is now DERIVED from `LONGEST_TAG`, so the two cannot disagree — which also means a wrong
    // argmax would go unnoticed. This is the independent pass the derivation replaced.
    for (@typeInfo(Kind).@"enum".fields) |f| std.debug.assert(f.name.len <= TAG_MAX);
}

pub fn tag(k: Kind) []const u8 {
    return @tagName(k);
}

pub fn fromTag(s: []const u8) ?Kind {
    return std.meta.stringToEnum(Kind, s);
}

pub const CAP: u16 = 999;

pub const Bag = struct {
    counts: [NK]u16 = [_]u16{0} ** NK,

    pub fn add(self: *Bag, k: Kind, n: u16) void {
        const i = @intFromEnum(k);
        self.counts[i] = @min(CAP, self.counts[i] +| n);
    }

    pub fn take(self: *Bag, k: Kind, n: u16) u16 {
        const i = @intFromEnum(k);
        const got = @min(self.counts[i], n);
        self.counts[i] -= got;
        return got;
    }

    pub fn count(self: *const Bag, k: Kind) u16 {
        return self.counts[@intFromEnum(k)];
    }

    pub fn distinct(self: *const Bag) usize {
        var n: usize = 0;
        for (self.counts) |c| {
            if (c > 0) n += 1;
        }
        return n;
    }

    pub fn total(self: *const Bag) u32 {
        var n: u32 = 0;
        for (self.counts) |c| n += c;
        return n;
    }

    pub fn nth(self: *const Bag, i: usize) ?Kind {
        var seen: usize = 0;
        for (self.counts, 0..) |c, ki| {
            if (c == 0) continue;
            if (seen == i) return @enumFromInt(ki);
            seen += 1;
        }
        return null;
    }

    pub fn clear(self: *Bag) void {
        self.counts = [_]u16{0} ** NK;
    }
};


test "every kind has a name, and no two share one" {
    for (0..NK) |i| {
        const a: Kind = @enumFromInt(i);
        try std.testing.expect(displayName(a).len > 0);
        for (i + 1..NK) |j| {
            try std.testing.expect(!std.mem.eql(u8, displayName(a), displayName(@enumFromInt(j))));
        }
    }
}

test "every kind is described and shelved, and no two share a description" {
    for (0..NK) |i| {
        const a: Kind = @enumFromInt(i);
        try std.testing.expect(describe(a).len > 20);
        try std.testing.expect(class(a).label().len > 0);
        for (i + 1..NK) |j| {
            try std.testing.expect(!std.mem.eql(u8, describe(a), describe(@enumFromInt(j))));
        }
    }
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        if (usable(k)) try std.testing.expectEqual(Class.tool, class(k));
    }
}

test "EVERY KIND SAYS WHAT IT DOES, and a kind with a dose says it in NUMBERS" {
    var buf: [EFFECT_BUF]u8 = undefined;
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        const s = effect(k, &buf);
        try std.testing.expect(s.len > 10);
        if (dosed(k)) {
            var digit = false;
            for (s) |c| digit = digit or std.ascii.isDigit(c);
            try std.testing.expect(digit);
        }
        if (isFlask(k) or bindsSouls(k) or k == .spirit_scroll_wolf or k == .iron_key) {
            try std.testing.expect(!std.mem.eql(u8, s, "No effect yet."));
        }
    }
}

test "a tag round-trips, and a bad one is rejected rather than guessed" {
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        try std.testing.expectEqual(k, fromTag(tag(k)).?);
    }
    try std.testing.expect(fromTag("no_such_item") == null);
    try std.testing.expect(fromTag("") == null);
}

test "every usable kind carries its OWN dose, and the rest do nothing" {
    var found: usize = 0;
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        switch (use(k)) {
            .none => try std.testing.expect(!usable(k)),
            .regen => |r| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(r.frac > 0 and r.frac <= 1.0);
                try std.testing.expect(r.secs > 0);
            },
            .lob => |l| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(l.dmg + l.fire + l.lightning > 0);
            },
            .arrows => |a| {
                found += 1;
                try std.testing.expect(usable(k));
                // A sheaf worth nothing is a sheaf that shelves as clutter. The upper bound is checked
                // against `combat.Quiver.cap` where the two can see each other — this file imports nothing
                // but std on purpose, so all it can say here is that the number is a number.
                try std.testing.expect(a.n > 0 and a.n < 100);
            },
            .ward => |w| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(w.chaos > 0 and w.secs > 0);
            },
            .wind => |w| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(w.share > 0 and w.share <= 1.0);
            },
            .grease => |gr| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(gr.frac > 0 and gr.frac <= 1.0);
                try std.testing.expect(gr.secs > 0);
            },
            .souls => |s| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(s.n > 0);
            },
            .brew => |b| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(b.mult > 1.0);
                try std.testing.expect(b.secs > 0);
            },
            .purge => {
                found += 1;
                try std.testing.expect(usable(k));
            },
            .steady => |s| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(s.mult > 1.0);
                try std.testing.expect(s.secs > 0);
            },
        }
    }
    try std.testing.expect(found >= 1);
}

test "THE BINDING RING IS NOT A TOOL — it is spent by DYING, and it has to be ON A FINGER to be" {
    var n: usize = 0;
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        if (!bindsSouls(k)) continue;
        n += 1;
        try std.testing.expect(!usable(k));
        try std.testing.expect(!quickable(k));
        try std.testing.expectEqual(Use.none, use(k));
        try std.testing.expect(wearable(k));
        const w = wearSlot(k).?;
        try std.testing.expect(w == .ring or w == .ring2);
        try std.testing.expect(!w.held());
    }
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expect(bindsSouls(.soul_binding_ring));
    try std.testing.expect(!bindsSouls(.leech_signet));
    try std.testing.expectEqual(wearSlot(.soul_binding_ring), wearSlot(.leech_signet));
}

test "the bag counts, caps, and never wraps" {
    var b = Bag{};
    try std.testing.expectEqual(@as(usize, 0), b.distinct());
    b.add(.rune_arc, 2);
    b.add(.rune_arc, 3);
    try std.testing.expectEqual(@as(u16, 5), b.count(.rune_arc));
    try std.testing.expectEqual(@as(usize, 1), b.distinct());
    b.add(.rune_arc, CAP);
    try std.testing.expectEqual(CAP, b.count(.rune_arc));
    try std.testing.expectEqual(@as(u16, 0), b.take(.golden_seed, 1));
    try std.testing.expectEqual(@as(u16, 4), b.take(.rune_arc, 4));
}

test "nth walks only the rows that have something in them" {
    var b = Bag{};
    b.add(.golden_seed, 1);
    const last: Kind = @enumFromInt(NK - 1);
    b.add(last, 1);
    try std.testing.expectEqual(Kind.golden_seed, b.nth(0).?);
    try std.testing.expectEqual(last, b.nth(1).?);
    try std.testing.expect(b.nth(2) == null);
    _ = b.take(.golden_seed, 1);
    try std.testing.expectEqual(last, b.nth(0).?);
    try std.testing.expectEqual(@as(usize, 1), b.distinct());
}

test "EVERY PIECE OF GEAR GOES IN A SOCKET, SAYS WHAT IT DOES IN NUMBERS, AND SHELVES AS GEAR" {
    var buf: [EFFECT_BUF]u8 = undefined;
    var worn: usize = 0;
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        if (!wearable(k)) {
            try std.testing.expect(wearSlot(k) == null);
            continue;
        }
        worn += 1;
        try std.testing.expect(!usable(k));
        try std.testing.expectEqual(Class.gear, class(k));
        try std.testing.expect(wearSlot(k) != null);
        const said = effect(k, &buf);
        try std.testing.expect(said.len > 0);
        if (equip(k) != .bind) {
            var digits = false;
            for (said) |c| {
                if (c >= '0' and c <= '9') digits = true;
            }
            try std.testing.expect(digits);
        }
        try std.testing.expect(std.mem.indexOf(u8, describe(k), " yet.") == null);
    }
    try std.testing.expectEqual(@as(usize, 15), worn);
}

test "EVERY SOCKET HAS SOMETHING THAT GOES IN IT, and no worn socket is a hand" {
    inline for (@typeInfo(Wear).@"enum".fields) |wf| {
        const w: Wear = @enumFromInt(wf.value);
        var n: usize = 0;
        for (0..NK) |i| {
            if (wearSlot(@enumFromInt(i)) == w) n += 1;
        }
        if (!w.held()) try std.testing.expect(n >= 1);
    }
    try std.testing.expectEqual(Wear.ring, wearSlot(.leech_signet).?);
    try std.testing.expectEqual(Wear.ring2, wearSlot(.deft_signet).?);
}

test "A BOON GRANTS A SKILL SOMETHING ACTUALLY READS, and says so in points" {
    var buf: [EFFECT_BUF]u8 = undefined;
    var boons: usize = 0;
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        switch (equip(k)) {
            .boon => |b| {
                boons += 1;
                try std.testing.expect(b.n > 0);
                try std.testing.expect(!stats.inert(b.attr));
                try std.testing.expect(std.mem.indexOf(u8, effect(k, &buf), stats.displayName(b.attr)) != null);
            },
            else => {},
        }
    }
    try std.testing.expectEqual(@as(usize, 3), boons);
}

test "A WEAPON'S SCALING MATCHES WHAT IT IS — and an EMPTY bow socket is still a bow" {
    try std.testing.expectEqual(Scaling.strength, equip(.greatclub).arm.scales);
    try std.testing.expectEqual(Scaling.dexterity, equip(.fang_dirk).arm.scales);
    try std.testing.expectEqual(Scaling.dexterity, equip(.grave_warbow).arm.scales);
    try std.testing.expectEqual(Scaling.quality, bareArm(.hand_sword).scales);
    try std.testing.expectEqual(Scaling.dexterity, bareArm(.hand_bow).scales);
    const bare = bareArm(.hand_sword);
    try std.testing.expectEqual(@as(f32, 1), bare.dmg);
    try std.testing.expectEqual(@as(f32, 1), bare.dur);
}

test "A WEAPON ROW TRADES: nothing is better than the plain thing on every dial at once" {
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        switch (equip(k)) {
            .arm => |a| {
                // Every dial is a multiple of what the bare armament already does, so a row of all 1s is a piece
                // of gear that exists and changes nothing — the one thing a weapon list may not contain.
                try std.testing.expect(a.dmg > 0 and a.poise > 0 and a.dur > 0 and a.stam > 0);
                try std.testing.expect(a.negate > 0 and a.arc > 0 and a.walk > 0);
                const gains = (a.dmg > 1) or (a.poise > 1) or (a.negate > 1) or (a.arc > 1) or (a.dur < 1) or (a.stam < 1) or (a.walk > 1);
                const costs = (a.dmg < 1) or (a.poise < 1) or (a.negate < 1) or (a.arc < 1) or (a.dur > 1) or (a.stam > 1) or (a.walk < 1);
                try std.testing.expect(gains and costs);
            },
            .plate => |p| try std.testing.expect(p.a > 0),
            .charm => |c| {
                const gives = c.leech > 0 or c.spiritFp < 1;
                const takes = c.hpFrac > 0 or c.fpFrac > 0;
                try std.testing.expect(gives and takes);
            },
            .boon => |b| try std.testing.expect(b.n > 0),
            // A BIND HAS NO DIALS TO TRADE — the socket is the price, and it is spent by dying. What it owes
            // instead is a finger, which the comptime block over `GEAR` already refuses to let it skip.
            .bind => {},
            .none => {},
        }
    }
}
