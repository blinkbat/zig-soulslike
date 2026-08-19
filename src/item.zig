const std = @import("std");
/// **THE ONE IMPORT THIS FILE IS ALLOWED**, and the reason the others are not: `combat` and `hero` both import
/// THIS file, so naming one of their types here is a cycle — which is why `Use` is plain floats and `Wear` is its
/// own enum rather than `hero.Armament`. `stats` imports nothing but std, so there is no cycle to have, and WHICH
/// SKILL a thing is worth points of is a fact about the THING.
const stats = @import("stats.zig");


/// **APPEND-ONLY.** `save.Data.seen` is a POSITIONAL bit run over this enum — one character per kind, read
/// back by index and never by tag — so a kind inserted or moved anywhere above the end silently re-points
/// every discovery bit in every save on disk. `ORDER` below pins it; add new kinds at the BOTTOM and add the
/// tag to the end of that list.
pub const Kind = enum(u8) {
    crimson_flask, // the ones the HUD already draws
    cerulean_flask,
    rune_arc,
    golden_seed,
    smithing_stone,
    bloodgrass, // wayside pickings — the common, worthless drop
    kobold_fang,
    iron_key,
    mushroom_jerky, // THE FIRST ITEM THAT DOES ANYTHING — see `Use`
    ember_candle, // thrown fire — the quiver's answer without the quiver
    sporeling_cap, // chewed: chaos slides off you for a while
    second_wind, // one sharp breath — the winded latch let go at once
    tower_shield, // gear waiting on an equip system: registered, described honestly, inert
    greatclub,
    leech_signet,
    soul_binding_ring, // it breaks in place of you: a death spills no souls while one is on you
    fire_tallow, // wiped on the blade: the fire arrow's rule, moved to the swing
    thundercrock, // thrown lightning — the first of it anywhere in the world
    nameless_soul, // souls, straight onto the counter
    toadflesh_broth, // the stamina refill runs faster for a while
    fang_dirk, // more gear waiting on the equip system, the tower shield's shelf
    grave_warbow,
    quilted_gambeson,
    spirit_scroll_wolf, // THE FIRST SPIRIT — carried, not used: the bell reads the bag (`combat.spiritOf`)
    pitted_helm, // the four sockets that were drawn and dead: head, throat, waist, feet…
    ashen_amulet,
    banded_warbelt,
    marchboots,
    deft_signet, // …and the second finger, which needed a second ring to exist before it could open
    purgeleaf, // THE FIRST CURE: poison was the one status and nothing in the world answered it
    pilgrims_salt, // the nameless soul's own shelf, one tier up
    ironwort_tea, // the broth's shape pointed at the POISE bar instead of the stamina one
    rimeward_mantle, // …and the first COLD resistance anywhere on his side of the fight
    sporecrown, // …and the first thing that slows a status filling
    gravebell_amulet, // the bell's own bargain: a cheaper call, a shorter blue bar
};

pub const NK = @typeInfo(Kind).@"enum".fields.len;

/// **THE ORDER, WRITTEN DOWN, because a save file depends on it and nothing else could see that.** A reorder
/// or an insert is a legal-looking edit that corrupts every `seen:` run on disk (`save.Data.seen`), and it
/// fails SILENTLY — the file still parses, it just describes a different set of items. Pinning the tags is
/// the only guard that catches it, and it costs one line per kind at the one moment it matters.
const ORDER = [_][]const u8{
    "crimson_flask",   "cerulean_flask", "rune_arc",     "golden_seed",
    "smithing_stone",  "bloodgrass",     "kobold_fang",  "iron_key",
    "mushroom_jerky",  "ember_candle",   "sporeling_cap", "second_wind",
    "tower_shield",    "greatclub",      "leech_signet", "soul_binding_ring",
    "fire_tallow",     "thundercrock",   "nameless_soul", "toadflesh_broth",
    "fang_dirk",       "grave_warbow",   "quilted_gambeson", "spirit_scroll_wolf",
    "pitted_helm",     "ashen_amulet",   "banded_warbelt", "marchboots",
    "deft_signet",     "purgeleaf",      "pilgrims_salt", "ironwort_tea",
    "rimeward_mantle", "sporecrown",     "gravebell_amulet",
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
    };
}

/// WHAT SHELF IT BELONGS ON. The bag is one grid and always will be — this is what the detail panel calls
/// the thing, and what a sort would go on the day the bag is big enough to need one.
pub const Class = enum {
    tool, // spent for an effect: the flasks, the jerky
    treasure, // spent for a permanent gain, or for something the game has not built yet
    material, // it is worth what a smith or a merchant will give for it
    key, // it opens exactly one thing
    /// PUT ON, not spent — a hand's armament, a coat, a ring. Its own shelf from the day an arm learned to take
    /// one up: before that these sat under `treasure`, whose definition is "something the game has not built".
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
        // …AND THE GEAR HAS ITS OWN SHELF NOW (`equip`). Every one of these is worn or held; none of them is
        // spent, so none of them was ever a tool, and `treasure` was only ever where they waited.
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
        // …and the band that breaks for you shelves with the gear it competes with, because that is where the
        // decision is now taken. NOT a tool either way: a tool is spent by pressing Confirm, this by dying.
        .soul_binding_ring => .gear,
        // …and the scroll for the ring's reason, read the other way: finding it is a PERMANENT gain (the bell
        // knows the wolf from here on), which is what this shelf means. Nothing is spent by pressing Confirm.
        .spirit_scroll_wolf => .treasure,
        .smithing_stone, .bloodgrass, .kobold_fang => .material,
        .iron_key => .key,
    };
}

/// WHAT IT IS, IN THE PLAYER'S HANDS — the description the character book prints beside the picture.
/// Two sentences at most, and the SECOND one is always what it is honestly worth right now: half of
/// these do nothing yet, and a description that hides that is the same lie as an inert attribute with no
/// note under it (`stats.governs`). The day one of them gains an effect, its line is edited here.
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
    };
}

/// WHAT USING IT DOES — named here, done elsewhere. Plain numbers only: this file imports nothing but
/// std, so an effect that needs a `combat` type is described here in floats and assembled at the apply
/// site (`game.useItem`).
pub const Use = union(enum) {
    /// Nothing yet.
    none,
    /// HP back slowly over time (`combat.Regen` is the mechanism): `frac` of MAX HP spread over `secs` seconds.
    regen: struct { frac: f32, secs: f32 },
    /// LOBBED at the reticle through the shafts' own pool — one victim, like everything thrown here.
    lob: struct { dmg: f32, fire: f32 = 0, lightning: f32 = 0, poise: f32 },
    /// A timed ward: `chaos` resistance for `secs` seconds. Refreshes, never stacks (the status law).
    ward: struct { chaos: f32, secs: f32 },
    /// `share` of the stamina pool back at once, through the winded latch's own gate.
    wind: struct { share: f32 },
    /// WIPED ON THE BLADE: the sword hangs `frac` of its own physical as fire for `secs` — the fire
    /// arrow's rule (`hero.FIRE_ARROW_FRAC`), moved to the swing. Refreshes, never stacks.
    grease: struct { frac: f32, secs: f32 },
    /// Souls, straight onto the counter.
    souls: struct { n: u32 },
    /// The stamina refill runs `mult` times its rate for `secs` seconds. Refreshes, never stacks.
    brew: struct { mult: f32, secs: f32 },
    /// **THE FIRST CURE.** The status meter wiped outright, filling or running — poison was the only status
    /// in the world and nothing anywhere answered it, so the one thing you could do about a spore cloud was
    /// spend a crimson on the damage after the fact. NO PAYLOAD: it does not half-clear, and a leaf that took
    /// a fraction would be a second dial nobody could size the first one against.
    purge,
    /// The POISE refill runs `mult` times its rate for `secs` seconds — the broth's shape (`brew`) pointed at
    /// the bar that decides whether a blow flinches him. Refreshes, never stacks.
    steady: struct { mult: f32, secs: f32 },
};

/// **WHICH SOCKET A PIECE OF GEAR GOES IN.** `book.SlotId`'s own subset — the sockets gear can actually fill —
/// named HERE because which socket a thing belongs in is a fact about the THING. This file imports nothing but
/// std, so it cannot say `hero.Armament`; `hero.wearFor` is the one place the two are matched up, exactly as
/// `combat.flaskOf` is the one place a kind becomes a `FlaskKind`.
/// **APPEND-ONLY, for `save.Data.worn`'s sake** — the `worn:` line is one word per socket in THIS order, and the
/// parser stops at the end of a short line so an older save loads with the new sockets empty (which is honestly
/// what that character had in them). Inserting a tag instead re-points every word on every line on disk.
pub const Wear = enum {
    hand_sword, // the right hand's blade — the straight sword's socket
    hand_bow,
    hand_shield,
    chest,
    ring,
    helm,
    neck,
    belt,
    feet,
    /// THE SECOND FINGER. A kind names ONE socket (`wearSlot`), so two ring sockets need two kinds of ring —
    /// which is exactly why this one stayed shut until there was a second band in the world to put in it.
    ring2,

    /// Is this one of the two hands? The book asks, because a hand's socket is filled by SWAPPING and the worn
    /// ones by putting something on, and the page has to say which.
    pub fn held(w: Wear) bool {
        return w == .hand_sword or w == .hand_bow or w == .hand_shield;
    }
};

/// **A HAND'S ARMAMENT, PRICED AS MULTIPLIERS ON THE ONE IT REPLACES** — never as a fresh set of absolutes.
/// `hero.ATK_*_HIT`, `combat.STAM_*` and `combat.GUARD_*` stay the single place a swing, a block and their bills
/// are written down, and a weapon says only how it DIFFERS. Bare-handed every dial here is 1, which is why this
/// whole system lands without retuning one existing number: the starting kit is the game exactly as it was.
/// **WHICH SKILL DRIVES A WEAPON** — ER's scaling letters, at ONE letter per armament rather than a letter per
/// attribute, because a weapon carrying two rates would need a table and there are three weapons in the world.
/// `quality` is the straight sword everybody starts with: the MEAN of the two curves, so either build carries it
/// and neither build is best with it. The mapping to a `stats.Attr` is `hero.scaleOf`, and the curve is
/// `stats.scaleFor` — one place each.
pub const Scaling = enum { strength, dexterity, quality };

pub const Arm = struct {
    slot: Wear,
    dmg: f32 = 1,
    poise: f32 = 1,
    /// The skill whose curve multiplies `dmg`. Defaulted for the SWORD's socket; `bareArm` is what an EMPTY
    /// socket gets, because a bow is a dexterity weapon whether or not a warbow is sitting in it.
    scales: Scaling = .quality,
    /// The swing's own DURATION. Under 1 is quicker — the dirk — and over 1 is the club: a heavier thing is not
    /// a stronger thing that also arrives at the same speed.
    dur: f32 = 1,
    stam: f32 = 1,
    /// SHIELDS ONLY: what it stops, how much of the compass it covers, and what it costs him to walk behind.
    negate: f32 = 1,
    arc: f32 = 1,
    walk: f32 = 1,
};

/// **WHAT PUTTING IT ON DOES** — named here, applied elsewhere (`hero.armOf`, `hero.armourA`, `hero.charm`), which
/// is `Use`'s own split: plain numbers only, assembled where the types live.
/// **THE FOUR ELEMENTS AS PLAIN FLOATS** — `combat.Spread`'s own fields, spelled out again here because this
/// file may import nothing but `std` and `stats` (naming `combat.Elem` is the cycle the header refuses). The
/// two are matched up at the ONE place they meet, `hero.resistOf`, exactly as `Wear` is matched to
/// `hero.Armament` by `hero.wearFor` and a `Kind` is made a flask by `combat.flaskOf`.
pub const Res = struct { fire: f32 = 0, cold: f32 = 0, lightning: f32 = 0, chaos: f32 = 0 };

/// **WORN, AND IT IS THE DEFENSIVE ROW — all of it.** `a` is the armour value in `A/(A + 5*dmg)`
/// (`combat.armourTaken`), so physical is a diminishing return by construction and a coat cannot become
/// immunity however many are stacked. `res` is the four elemental columns beside it, and `poison` is a
/// MULTIPLIER on how fast a status meter fills — the three things a piece of armour can honestly turn aside,
/// on one row rather than three verbs that would each have to be stacked and printed separately.
pub const Plate = struct { slot: Wear, a: f32 = 0, res: Res = .{}, poison: f32 = 1 };

/// WORN, and a BARGAIN — what it gives and what it costs, because a ring in this genre is always both. `leech`
/// is HP back on every blow of his that lands; `hpFrac` is the share of his max HP it eats to do it.
/// **AND THE SAME TRADE ON THE BLUE BAR**: `spiritFp` is a multiplier on what a call costs (`combat.spiritFp`)
/// and `fpFrac` the share of his max focus that buys it — the red pair's exact shape one bar along, so the two
/// charms in the world are the same kind of decision rather than two unrelated mechanics.
pub const Charm = struct { slot: Wear, leech: f32 = 0, hpFrac: f32 = 0, spiritFp: f32 = 1, fpFrac: f32 = 0 };

/// **WORN, AND WHAT IT BUYS IS A SKILL** — `n` points of `attr`, laid onto the live sheet exactly the way a tree
/// node's are (`stats.Sheet.add`), so gear and the wheel are the same kind of gain and neither knows the other
/// exists. It is a PLAIN grant with no cost on purpose, where `Charm` is a bargain: a charm is priced against the
/// other rings you might have worn instead, and with one piece per socket a downside is not a trade — it is a
/// reason to leave the socket empty, which is the one thing a piece of gear may never be.
pub const Boon = struct { slot: Wear, attr: stats.Attr, n: u8 };

/// **WORN, AND IT DOES NOTHING UNTIL THE ONE MOMENT IT DOES EVERYTHING** — a band that breaks in place of you.
/// It carries no numbers because there is nothing to tune: it is spent or it is not. A socket is the whole
/// price, and that is the point of putting it here rather than leaving it a thing in the bag — insurance you
/// pay for in the finger a leech signet wanted, decided BEFORE the fight instead of by having packed it.
pub const Bind = struct { slot: Wear };

pub const Equip = union(enum) {
    /// Not a thing you can put on.
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
    return .{ .slot = w, .scales = if (w == .hand_bow) .dexterity else .quality };
}

/// THE GEAR TABLE — one row per thing, and the numbers are all any of them is.
/// ONE ITEM'S WHOLE BEHAVIOUR. What it does WORN and what it does USED were two switches in two halves of
/// this file, so what a thing is worth took two lookups and adding one took two edits — with the second one
/// a 24-line `=> .none` tail nobody could read.
pub const Gear = struct {
    kind: Kind,
    equip: Equip = .none,
    use: Use = .none,
};

/// **WHAT EVERYTHING DOES, AS ONE TABLE YOU CAN READ DOWN.** Sparse on purpose: a kind absent from here does
/// nothing at all, and `INERT` below names every one of those so an absence is a DECISION and not an
/// omission — a new `Kind` is a compile error until it has appeared in one list or the other.
pub const GEAR = [_]Gear{
    // ── WORN ────────────────────────────────────────────────────────────────────────────────────────────
    // A LONG KNIFE. Quicker than the sword by a fifth and cheaper to swing, at three quarters of the damage
    // and less poise than a hero light already carries: it is the weapon for a fight you win on openings.
    .{ .kind = .fang_dirk, .equip = .{ .arm = .{ .slot = .hand_sword, .dmg = 0.74, .poise = 0.72, .dur = 0.78, .stam = 0.76, .scales = .dexterity } } },
        // …AND THE OTHER END OF THE SAME DIAL. Half again the damage and the poise — enough that a light swing
    // of it flinches what a sword's light bounces off — bought with a third more commitment on every stroke
    // and half again the stamina. This is the thing that staggers the ogre without a spell.
    .{ .kind = .greatclub, .equip = .{ .arm = .{ .slot = .hand_sword, .dmg = 1.48, .poise = 1.60, .dur = 1.34, .stam = 1.48, .scales = .strength } } },
    // A DRAW TWICE THE SKELETONS' (its own description) — but a bow CHIPS, it does not win, so the multiple
    // is on the shaft and not on the archer: slower to bring up and dearer to hold.
    .{ .kind = .grave_warbow, .equip = .{ .arm = .{ .slot = .hand_bow, .dmg = 1.62, .poise = 1.45, .dur = 1.28, .stam = 1.34, .scales = .dexterity } } },
    // A DOOR. It stops nearly everything and covers half again the compass the small shield does — and the
    // three metres of it are why he walks behind it at four fifths of the speed and pays more per blow eaten.
    // **THE NEGATION DIAL STOPS UNDER THE CAP ON PURPOSE.** `combat.GUARD_NEGATE_CAP` is 0.95 and the base is
    // 0.85, so anything past ~1.118 here is silently clamped — and `effect` below PRINTS this figure, so a
    // clamped dial is a number on the panel that the fight does not honour. At 1.10 the door is worth every
    // point of it, and the cap goes back to being what it is for: stopping a shield PLUS a tree node from
    // making a block free.
    .{ .kind = .tower_shield, .equip = .{ .arm = .{ .slot = .hand_shield, .negate = 1.10, .arc = 1.45, .walk = 0.80, .stam = 1.30 } } },
    // THE FIRST ARMOUR IN THE WORLD. `a` is sized to take about a fifth off a middling blow and less off a
    // big one — `A/(A + 5*dmg)` is the curve, so it is worth most against the pokes and least against the
    // thing that was going to kill you, which is what a rag coat should be.
    .{ .kind = .quilted_gambeson, .equip = .{ .plate = .{ .slot = .chest, .a = 22.0 } } },
    // THE BARGAIN. Two HP back on every blow of his that lands, paid for with a permanent bite out of the
    // bar it fills — so it is a trade for somebody who lands a lot of blows and a straight loss otherwise.
    .{ .kind = .leech_signet, .equip = .{ .charm = .{ .slot = .ring, .leech = 2.0, .hpFrac = 0.06 } } },
    // THE REST OF THE SUIT. Head and feet answer PHYSICAL like the coat does, and they are sized by how much
    // of him each actually covers — the coat is the body, a helm is one head, boots are two feet. All three
    // on, `A/(A+5*dmg)` turns aside about a third of a middling blow and a fifth of the one that would have
    // killed him, which is the curve doing exactly what it is for.
    .{ .kind = .pitted_helm, .equip = .{ .plate = .{ .slot = .helm, .a = 14.0 } } },
    .{ .kind = .marchboots, .equip = .{ .plate = .{ .slot = .feet, .a = 9.0 } } },
    // …AND THE THREE THAT BUY A SKILL, one per socket and one per weapon that reads it: the belt braces the
    // hips a club is swung out of, the signet steadies the wrist a point goes out on, the bead answers the
    // rod. Three points each — a fifth of the way to the first softcap, so it is a real gain and not a level.
    .{ .kind = .banded_warbelt, .equip = .{ .boon = .{ .slot = .belt, .attr = .strength, .n = 3 } } },
    .{ .kind = .deft_signet, .equip = .{ .boon = .{ .slot = .ring2, .attr = .dexterity, .n = 3 } } },
    .{ .kind = .ashen_amulet, .equip = .{ .boon = .{ .slot = .neck, .attr = .intelligence, .n = 3 } } },
    // **THE FIRST COLD RESISTANCE ANYWHERE ON HIS SIDE.** The necromancer's rune ring is the game's one
    // source of cold and the sheet showed 0% with nothing in the world able to move it, so this coat is a
    // real answer to a real creature rather than a number. Its PHYSICAL is under the gambeson's on purpose:
    // fleece and hide turn a chill, not an edge, and a chest socket that was strictly better than the coat
    // already in it would retire that coat instead of competing with it.
    .{ .kind = .rimeward_mantle, .equip = .{ .plate = .{ .slot = .chest, .a = 13.0, .res = .{ .cold = 35 } } } },
    // …AND THE FIRST THING THAT SLOWS A METER FILLING. Poison is the only status, it is his alone, and
    // nothing resisted it: the sporeling's cloud filled the bar at one rate whatever he had on. Just over
    // half, so a cloud is still something you walk out of and not something you stand in.
    .{ .kind = .sporecrown, .equip = .{ .plate = .{ .slot = .helm, .a = 8.0, .poison = 0.55 } } },
    // THE BELL'S OWN BARGAIN, and the leech signet's shape on the blue bar: a call is the single biggest
    // bill in the game (30 of a 60 pool), so two fifths off it is most of a second ringing — bought with a
    // tenth of the pool the ringing comes out of, which is what stops it being free depth.
    .{ .kind = .gravebell_amulet, .equip = .{ .charm = .{ .slot = .neck, .spiritFp = 0.60, .fpFrac = 0.10 } } },
    // **IT HAS TO BE ON YOUR HAND TO BREAK FOR YOU** (owner's call). Carried, it was insurance already bought
    // by having picked it up, and nothing was ever decided; in the leech signet's own finger it is a choice
    // taken before the fight — HP back on every blow that lands, against keeping what you carry the once.
    .{ .kind = .soul_binding_ring, .equip = .{ .bind = .{ .slot = .ring } } },
    // ── USED ────────────────────────────────────────────────────────────────────────────────────────────
    .{ .kind = .mushroom_jerky, .use = .{ .regen = .{ .frac = 0.60, .secs = 20.0 } } },
    // Under both melee swings in damage (the bow's own restraint), but it is fire, and fire is the answer to
    // half the wood.
    .{ .kind = .ember_candle, .use = .{ .lob = .{ .dmg = 8, .fire = 22, .poise = 12 } } },
    .{ .kind = .sporeling_cap, .use = .{ .ward = .{ .chaos = 40, .secs = 60 } } },
    .{ .kind = .second_wind, .use = .{ .wind = .{ .share = 0.5 } } },
    // The fire arrow's own fraction: the tallow makes a sword of the burning shaft, not a bigger one.
    .{ .kind = .fire_tallow, .use = .{ .grease = .{ .frac = 0.5, .secs = 60 } } },
    // The candle's weights with the element swapped — the pair teach one throw.
    .{ .kind = .thundercrock, .use = .{ .lob = .{ .dmg = 8, .lightning = 22, .poise = 12 } } },
    // A middling foe's worth (the Rooted's own figure) — found money, not a farm.
    .{ .kind = .nameless_soul, .use = .{ .souls = .{ .n = 150 } } },
    .{ .kind = .toadflesh_broth, .use = .{ .brew = .{ .mult = 1.5, .secs = 60 } } },
    .{ .kind = .purgeleaf, .use = .purge },
    // FOUR TIMES the nameless soul's 150 — that one is "found money" off a middling body, and this is the
    // thing at the bottom of a chest. Still nowhere near a level (`passivetree.costAt(0)` is 280).
    .{ .kind = .pilgrims_salt, .use = .{ .souls = .{ .n = 600 } } },
    // The broth's own multiple and a shorter clock: poise is what decides whether the next blow flinches him,
    // so a minute of it would be a minute of not being staggered.
    .{ .kind = .ironwort_tea, .use = .{ .steady = .{ .mult = 2.2, .secs = 40 } } },
};

/// **THE KINDS THAT DELIBERATELY DO NOTHING**, named so that an absence from `GEAR` is a decision. Some are
/// carried rather than used (the scroll the bell reads), some are the HUD's own two flasks, and some are
/// treasure the game has not built a door for yet.
pub const INERT = [_]Kind{
    .crimson_flask,  .cerulean_flask, .rune_arc,    .golden_seed,
    .smithing_stone, .bloodgrass,     .kobold_fang, .iron_key,
    .spirit_scroll_wolf,
};

comptime {
    // EVERY KIND SAYS SOMETHING, ONCE. This is what the two exhaustive switches used to buy: a new `Kind` is a
    // compile error until it has appeared in `GEAR` or admitted it does nothing.
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

/// The table scattered by kind, so a lookup is an index rather than a walk — `GEAR` stays the hand-edited
/// thing and this is what the fight reads.
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


/// Can this be put on at all? `usable`'s twin one shelf along.
pub fn wearable(k: Kind) bool {
    return std.meta.activeTag(equip(k)) != .none;
}

/// …and WHICH SOCKET, or null for everything that is not gear — the book asks this of a bag row to know whether
/// it may be offered to the socket the cursor is standing on.
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
    // A ROW MAY NOT SIT IN A SOCKET IT WAS NOT WRITTEN FOR: the shield dials do nothing in a sword's hand and
    // the blade dials do nothing on a shield, so a row that sets the wrong ones is a row whose numbers silently
    // never apply. Caught here rather than by somebody wondering why their tower shield swings slowly.
    // Over the ENUM's own count, not over `ORDER` — that list exists to pin save ordinals and borrowing its
    // length to walk the kinds ties this check to a thing it has nothing to do with.
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
            },
            .plate => |p| if (p.slot.held()) @compileError("item: " ++ @tagName(k) ++ " is armour in a hand"),
            .charm => |c| if (c.slot.held()) @compileError("item: " ++ @tagName(k) ++ " is a charm in a hand"),
            // A BAND IS NOT SOMETHING YOU HOLD, and it may not sit where the armour and the boons do either:
            // `bindsSouls` reads the payload, so a bind row in a plate's socket would be a coat that quietly
            // eats a death — and the one thing the mechanic must be is legible from the socket it is in.
            .bind => |b| if (b.slot != .ring and b.slot != .ring2) @compileError("item: " ++ @tagName(k) ++
                " binds souls from a socket that is not a finger — the ring is the mechanic's whole tell"),
            .boon => |b| {
                if (b.slot.held()) @compileError("item: " ++ @tagName(k) ++ " is a boon in a hand");
                if (b.n == 0) @compileError("item: " ++ @tagName(k) ++ " grants zero points — a boon of nothing");
                // A BOON OF THE ONE DEAD ATTRIBUTE would be a piece of gear whose whole line is a number that
                // buys nothing, which is precisely the inert-row lie `stats.governs` exists to refuse.
                if (stats.inert(b.attr)) @compileError("item: " ++ @tagName(k) ++ " grants " ++
                    @tagName(b.attr) ++ ", which nothing reads — the gear would be honestly inert");
            },
            .none => {},
        }
    }
    // **ONE KIND PER SOCKET IS NOT REQUIRED, BUT AN EMPTY SOCKET IS A DEAD SOCKET.** Every `Wear` the book draws
    // has to have something in the world that goes in it, or the doll grows a hole nothing can ever fill — which
    // is the state five of these sockets were in before this table had rows for them.
    for (@typeInfo(Wear).@"enum".fields) |wf| {
        const w: Wear = @enumFromInt(wf.value);
        if (w.held()) continue; // a hand is filled by an ARMAMENT, with or without a variant to put in it
        var any = false;
        for (0..NK) |i| {
            if (wearSlot(@enumFromInt(i)) == w) any = true;
        }
        if (!any) @compileError("item: nothing in the world goes in the " ++ wf.name ++
            " socket — the book would draw a hole that can never be filled");
    }
}

/// **WHICH ELEMENT A DEFENSIVE ROW ACTUALLY ANSWERS**, for the one line the panel prints — null when it
/// answers none. One column at a time is not a limitation of the type (`Res` carries all four): it is what a
/// single line of prose can honestly say, and no piece in the world wards two.
fn plateElem(r: Res) ?struct { name: []const u8, amount: f32 } {
    if (r.fire != 0) return .{ .name = "fire", .amount = r.fire };
    if (r.cold != 0) return .{ .name = "cold", .amount = r.cold };
    if (r.lightning != 0) return .{ .name = "lightning", .amount = r.lightning };
    if (r.chaos != 0) return .{ .name = "chaos", .amount = r.chaos };
    return null;
}


/// Is this row worth pressing Confirm on?
pub fn usable(k: Kind) bool {
    return std.meta.activeTag(use(k)) != .none;
}

/// **DOES ITS EFFECT CARRY NUMBERS AT ALL** — which is NOT the same question as `usable`. Asked off the
/// union's own payload rather than by listing the verbs that have one, so a second payload-free effect is
/// covered here the day it is written instead of the day somebody notices the test.
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
            .hand_shield => std.fmt.bufPrintZ(buf, "Held: blocks {d:.0}% more, covers {d:.0}% wider, walks at {d:.0}%.", .{
                (a.negate - 1) * 100,
                (a.arc - 1) * 100,
                a.walk * 100,
            }) catch "Held: a bigger shield.",
            else => std.fmt.bufPrintZ(buf, "Held: {d:.0}% damage, {d:.0}% poise, {d:.0}% swing time.", .{
                a.dmg * 100,
                a.poise * 100,
                a.dur * 100,
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
        // No numbers, and no buffer: the whole row is the one thing it does. It reads WORN because that is now
        // the condition — the same line said "Carried" while a ring in the bag was enough.
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
        .brew => |b| std.fmt.bufPrintZ(buf, "Stamina comes back {d:.1}x as fast for {d:.0}s. Refreshes, never stacks.", .{ b.mult, b.secs }) catch "Stamina returns faster.",
        .purge => "Clears poison outright, filling or already running.",
        .steady => |s| std.fmt.bufPrintZ(buf, "Poise comes back {d:.1}x as fast for {d:.0}s. Refreshes, never stacks.", .{ s.mult, s.secs }) catch "Poise returns faster.",
    };
}

/// How big a buffer `effect` needs. The longest line is the `lob`'s, and a `bufPrintZ` that does not fit falls
/// back to a bare phrase — legible, but it drops the numbers, which are the whole point of the line.
pub const EFFECT_BUF: usize = 128;

/// THE TWO THE FLASK SYSTEM OWNS. They sit on the quick bar like anything else, but their charges live in
/// `combat.Flasks` and come back at a bonfire, so spending one never touches the bag. Named here rather than
/// in `combat` because it is a fact about the ITEM; `combat.flaskOf` is the same question answered as a
/// `FlaskKind`, and it cannot live here — `combat` imports this file and not the other way about.
pub fn isFlask(k: Kind) bool {
    return k == .crimson_flask or k == .cerulean_flask;
}

/// THE ONE THING THAT SPENDS ITSELF WITHOUT BEING USED — DS's Ring of Sacrifice. A death takes the RING
/// instead of the souls, so what you were carrying stays carried and nothing is left on the ground to walk
/// back for. **IT MUST BE WORN**, which is `Bind`'s whole reason for being an `Equip` variant: the question is
/// asked of the SOCKET at the death site (`game.bindingWorn`) and a ring in the bag protects nothing.
/// Read off the payload rather than by kind, so a second binding band is one row in `GEAR` and no edit here.
pub fn bindsSouls(k: Kind) bool {
    return std.meta.activeTag(equip(k)) == .bind;
}

/// …and WHAT MAY GO ON THE QUICK BAR: a flask, or anything with an effect. There is no point carrying a
/// kobold fang into a fight on the one bar you are allowed to reach during it.
pub fn quickable(k: Kind) bool {
    return isFlask(k) or usable(k);
}

/// The SHORT tag the map file writes, and the only name a hand-edited world has to get right.
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

    /// How many DIFFERENT things are in here — the number of rows a menu has to draw.
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

    /// The `i`th non-empty kind, in Kind order.
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
        try std.testing.expect(describe(a).len > 20); // a stub is worse than no panel at all
        try std.testing.expect(class(a).label().len > 0);
        for (i + 1..NK) |j| {
            try std.testing.expect(!std.mem.eql(u8, describe(a), describe(@enumFromInt(j))));
        }
    }
    // …and the one kind that DOES something is shelved as a tool, which is the promise that row makes.
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
        // A dose that fell back to the bare phrase has lost its numbers, which is the whole line — asked of
        // the kinds that HAVE numbers, which is not the same as the kinds you can press Confirm on: `purge`
        // carries no payload on purpose, and there is nothing there for a digit to come out of.
        if (dosed(k)) {
            var digit = false;
            for (s) |c| digit = digit or std.ascii.isDigit(c);
            try std.testing.expect(digit);
        }
        // …and the three that work without a `Use` may not read as inert.
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
            // NO PAYLOAD TO CHECK, and that IS the check: a cure that carried a fraction would be a second
            // dial nobody could size the first one against (`Use.purge`'s own note).
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
        // It must not offer a Confirm: pressing Use on it would promise something the mechanic never does.
        try std.testing.expect(!usable(k));
        try std.testing.expect(!quickable(k)); // …nor a socket on the bar it can never be spent from
        try std.testing.expectEqual(Use.none, use(k));
        // …AND IT IS WORN, which is the whole of the rule: carrying one protects nothing now.
        try std.testing.expect(wearable(k));
        const w = wearSlot(k).?;
        try std.testing.expect(w == .ring or w == .ring2);
        try std.testing.expect(!w.held());
    }
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expect(bindsSouls(.soul_binding_ring));
    try std.testing.expect(!bindsSouls(.leech_signet)); // the other ring binds nothing
    // …and it competes for a finger with something, or the choice it exists to be is not one.
    try std.testing.expectEqual(wearSlot(.soul_binding_ring), wearSlot(.leech_signet));
}

test "the bag counts, caps, and never wraps" {
    var b = Bag{};
    try std.testing.expectEqual(@as(usize, 0), b.distinct());
    b.add(.rune_arc, 2);
    b.add(.rune_arc, 3);
    try std.testing.expectEqual(@as(u16, 5), b.count(.rune_arc));
    try std.testing.expectEqual(@as(usize, 1), b.distinct());
    // Saturating, both ways: a count may not wrap to zero at the top nor underflow at the bottom.
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
    // Emptying a row closes the gap rather than leaving a hole a cursor can land in.
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
        // A thing you put on is never a thing you spend: the two shelves are exclusive by construction.
        try std.testing.expect(!usable(k));
        try std.testing.expectEqual(Class.gear, class(k));
        try std.testing.expect(wearSlot(k) != null);
        // …and its line carries a NUMBER, which is what makes it a piece of gear rather than a promise.
        // **EXCEPT A BIND, WHICH HAS NOTHING TO PUT A DIGIT IN**: `Bind` is a socket and nothing else, so the
        // rule is asked of the payload the way `dosed` asks it of a `Use` — not of a list of tags.
        const said = effect(k, &buf);
        try std.testing.expect(said.len > 0);
        if (equip(k) != .bind) {
            var digits = false;
            for (said) |c| {
                if (c >= '0' and c <= '9') digits = true;
            }
            try std.testing.expect(digits);
        }
        // AND ITS DESCRIPTION MAY NO LONGER PLEAD THE FIFTH. Every one of these used to end in some version of
        // "no hand here knows it yet", which was honest then and is a lie now.
        try std.testing.expect(std.mem.indexOf(u8, describe(k), " yet.") == null);
    }
    // A CENSUS, NOT A RULE — it says "somebody added a piece of gear" loudly enough to be noticed in review.
    try std.testing.expectEqual(@as(usize, 15), worn);
}

test "EVERY SOCKET HAS SOMETHING THAT GOES IN IT, and no worn socket is a hand" {
    inline for (@typeInfo(Wear).@"enum".fields) |wf| {
        const w: Wear = @enumFromInt(wf.value);
        var n: usize = 0;
        for (0..NK) |i| {
            if (wearSlot(@enumFromInt(i)) == w) n += 1;
        }
        // A hand is filled by an ARMAMENT and a variant is optional there; a WORN socket with nothing for it is
        // a hole in the paper doll, and five of them were exactly that.
        if (!w.held()) try std.testing.expect(n >= 1);
    }
    // …and the two rings are two sockets with two DIFFERENT bands, because a kind names one socket.
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
                try std.testing.expect(!stats.inert(b.attr)); // never a point of the one dead attribute
                // The line names the attribute, so a player can tell two boons apart without the flavour text.
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
    // The bare sword splits the difference; the bare BOW does not inherit that (`bareArm`'s whole reason).
    try std.testing.expectEqual(Scaling.quality, bareArm(.hand_sword).scales);
    try std.testing.expectEqual(Scaling.dexterity, bareArm(.hand_bow).scales);
    // A bare row is otherwise all ones, or an empty socket would be a weapon in its own right.
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
                // THE DIALS ARE NOT ALL THE SAME WAY UP: `dur` and `stam` are BILLS, so under 1 is the gain
                // there — which is the whole of what a dirk is, and reading them as damage dials made the one
                // weapon in the list that buys speed look like a weapon that buys nothing.
                const gains = (a.dmg > 1) or (a.poise > 1) or (a.negate > 1) or (a.arc > 1) or (a.dur < 1) or (a.stam < 1) or (a.walk > 1);
                const costs = (a.dmg < 1) or (a.poise < 1) or (a.negate < 1) or (a.arc < 1) or (a.dur > 1) or (a.stam > 1) or (a.walk < 1);
                try std.testing.expect(gains and costs); // it buys something AND it costs something
            },
            .plate => |p| try std.testing.expect(p.a > 0),
            // A charm that gave without taking would be a straight upgrade for carrying it, which is not a
            // bargain. **ASKED AS "GIVES SOMETHING AND TAKES SOMETHING", NOT AS TWO NAMED FIELDS** — the
            // gravebell's bargain is on the BLUE bar, and pinned to `leech`/`hpFrac` this test said a charm is
            // only a charm if it is the leech signet.
            .charm => |c| {
                const gives = c.leech > 0 or c.spiritFp < 1;
                const takes = c.hpFrac > 0 or c.fpFrac > 0;
                try std.testing.expect(gives and takes);
            },
            // A BOON IS DELIBERATELY NOT A BARGAIN (`Boon`'s own note): with one piece per socket a cost would
            // only make the socket worse than empty. What it owes instead is a grant worth having.
            .boon => |b| try std.testing.expect(b.n > 0),
            // A BIND HAS NO DIALS TO TRADE — the socket is the price, and it is spent by dying. What it owes
            // instead is a finger, which the comptime block over `GEAR` already refuses to let it skip.
            .bind => {},
            .none => {},
        }
    }
}
