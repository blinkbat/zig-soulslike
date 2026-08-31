const std = @import("std");
const stats = @import("stats.zig");


/// **THE FOUR ELEMENTS BY NAME, FOR A FILE THAT CANNOT SEE `combat`.** This one is a leaf on purpose (`combat`
/// imports it), so a ward or a grease says which column it is in these terms and `combat.elemOf` crosses over —
/// pinned field for field against `combat.Elem` at comptime there.
pub const ElemName = enum(u8) { fire, cold, lightning, chaos };

/// **THE TEN BY NAME, FOR `ElemName`'S REASON** — this file is a leaf and cannot see `combat.Ail`. Pinned tag
/// for tag at comptime there (`combat.ailOfName`).
pub const AilName = enum(u8) { poison, burning, chill, stun, bleed, sleep, confusion, charm, berserk, stupefy };

/// What a source puts in ONE meter, out of that row's own `max`.
pub const AilDose = struct { ail: AilName, amt: f32 };

/// A MULTIPLIER on how fast one meter fills on the wearer. Named, so a helm cannot slow all ten at once by accident.
pub const AilRate = struct { ail: AilName, k: f32 };

/// **LOWER CASE, BECAUSE IT LANDS MID-SENTENCE** — `combat.ailName` is the capitalised bar label; a gear line
/// reads "sleep fills at 40%".
pub fn ailWord(a: AilName) [:0]const u8 {
    return switch (a) {
        .poison => "poison",
        .burning => "burning",
        .chill => "chill",
        .stun => "stun",
        .bleed => "bleed",
        .sleep => "sleep",
        .confusion => "confusion",
        .charm => "charm",
        .berserk => "berserk",
        .stupefy => "stupor",
    };
}

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
    scroll_bolt,
    scroll_roots,
    scroll_rime,
    scroll_levin,
    scroll_siphon,
    scroll_lance,
    scroll_sunder,
    kiln_draught,
    rimewax,
    pilgrims_offering,
    envenomed_dagger,
    spidersilk_moccasins,
    bloodtinge_signet,
    loop_of_chance,
    nightcap_grease,
    wakers_nail,
    madcap_powder,
    stolen_gravebell,
    bloodwine,
    wax_stopped_hood,
    scroll_babble,
    scroll_bidding,
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
    "fire_arrows",     "scroll_bolt",    "scroll_roots",   "scroll_rime",
    "scroll_levin",    "scroll_siphon",  "scroll_lance",   "scroll_sunder",
    "kiln_draught",    "rimewax",        "pilgrims_offering", "envenomed_dagger",
    "spidersilk_moccasins", "bloodtinge_signet", "loop_of_chance",
    "nightcap_grease", "wakers_nail",       "madcap_powder",  "stolen_gravebell",
    "bloodwine",       "wax_stopped_hood",  "scroll_babble",  "scroll_bidding",
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
        .scroll_bolt => "Sorcery Scroll: Chaos Bolt",
        .scroll_roots => "Sorcery Scroll: Roots",
        .scroll_rime => "Sorcery Scroll: Rime Breath",
        .scroll_levin => "Sorcery Scroll: Levin Strike",
        .scroll_siphon => "Sorcery Scroll: Siphon",
        .scroll_lance => "Sorcery Scroll: Ember Lance",
        .scroll_sunder => "Sorcery Scroll: Sunder",
        .kiln_draught => "Kiln Draught",
        .rimewax => "Rimewax",
        .pilgrims_offering => "Pilgrim's Offering",
        .envenomed_dagger => "Envenomed Dagger",
        .spidersilk_moccasins => "Spidersilk Moccasins",
        .bloodtinge_signet => "Bloodtinge Signet",
        .loop_of_chance => "Loop of Chance",
        .nightcap_grease => "Nightcap Grease",
        .wakers_nail => "Waker's Nail",
        .madcap_powder => "Madcap Powder",
        .stolen_gravebell => "Stolen Gravebell",
        .bloodwine => "Bloodwine",
        .wax_stopped_hood => "Wax-Stopped Hood",
        .scroll_babble => "Sorcery Scroll: Babble",
        .scroll_bidding => "Sorcery Scroll: Bidding",
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

/// **WHAT A THING IS WORTH IN COIN, AND 0 MEANS IT DOES NOT TRADE.** Derived from the SHELF it sits on rather
/// than authored sixty times: a tool is a tool, and the handful that are genuinely dearer or genuinely priceless
/// say so below. Guessed on the owner's say-so and meant to be retuned — the test beside it prints the whole
/// list so the spread can be read at once instead of hunted for.
///
/// **UNTRADEABLE IS A PRICE OF 0** and it is one rule, not a second flag: the two flasks are the ESTUS of this
/// game, a key is a key, and a boss's ring is the record of a fight. None of those has a number a shop could
/// name without breaking something.
pub fn price(k: Kind) u32 {
    return switch (k) {
        // The things no counter may touch.
        .crimson_flask, .cerulean_flask, .iron_key, .soul_binding_ring, .golden_seed => 0,

        // Dearer than their shelf: a made weapon, and the two scrolls a boss dies for.
        .envenomed_dagger => 900,
        .grave_warbow => 850,
        .tower_shield => 700,
        .greatclub => 480,
        .scroll_babble, .scroll_bidding => 620,
        // The one material the smith actually eats, so it has a price a player will feel.
        .smithing_stone => 150,
        .rune_arc => 520,

        else => switch (class(k)) {
            .tool => 60,
            .treasure => 400,
            .material => 40,
            .key => 0,
            .gear => 300,
        },
    };
}

/// What a counter pays for one. **A SHOP IS NOT A BANK** — buying back what you sold has to cost something, or
/// the stock list is a free storage chest with extra steps.
pub const SELL_SHARE: f32 = 0.40;

pub fn sellPrice(k: Kind) u32 {
    const p = price(k);
    if (p == 0) return 0;
    const paid: u32 = @intFromFloat(@as(f32, @floatFromInt(p)) * SELL_SHARE);
    return @max(paid, 1);
}

pub fn class(k: Kind) Class {
    return switch (k) {
        // **ONE PER LINE.** This is the table you read to find out where a thing shelves, and both of the long arms ran past 200 columns.
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
        .kiln_draught,
        .rimewax,
        .pilgrims_offering,
        .nightcap_grease,
        .madcap_powder,
        .stolen_gravebell,
        .bloodwine,
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
        .envenomed_dagger,
        .spidersilk_moccasins,
        .bloodtinge_signet,
        .loop_of_chance,
        .wakers_nail,
        .wax_stopped_hood,
        => .gear,
        .soul_binding_ring => .gear,
        .spirit_scroll_wolf => .treasure,
        .scroll_bolt,
        .scroll_roots,
        .scroll_rime,
        .scroll_levin,
        .scroll_siphon,
        .scroll_lance,
        .scroll_sunder,
        .scroll_babble,
        .scroll_bidding,
        => .treasure,
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
        .scroll_bolt => "A single sheet, thumbed soft at one corner by whoever learned off it first. The figure on it is a fist closed round a stone that is not there, and the stone is the first thing any rod throws.",
        .scroll_roots => "Bark-paper, and the ink has gone into it like sap. What is drawn is a hand pressed flat to the ground, and under the hand a tangle that goes down further than the sheet has room for.",
        .scroll_rime => "Vellum stiff with cold that does not come off it in the sun. The mouth drawn open across the middle of it is breathing out, and the breath is the only part of the drawing still white.",
        .scroll_levin => "A sheet burned through in one place, the hole the shape of a struck line. Whoever copied this out got it right once and never dared copy it again.",
        .scroll_siphon => "Skin, and thinner than it ought to be, as though something had already drunk out of it. The figure drawn on it is fuller than the figure drawn opposite, and the line between them runs the wrong way.",
        .scroll_lance => "Scorched down one edge and rolled tight against the draught. The mark on it is a straight run of fire held level, which is a thing to be aimed rather than thrown.",
        .kiln_draught => "Grit and kiln-ash steeped in oil, drunk warm and swallowed fast before it settles. For a minute fire goes into you slower than it means to.",
        .rimewax => "Wax gone cloudy with the cold still shut in it, in a waxed twist of cloth like the tallow. Wiped along an edge it clings and bites: for a minute the sword hangs cold on top of what it always did.",
        .pilgrims_offering => "What a shrine was owed and never got - coin, a tooth and a cut lock of hair, pressed into one cold lump. There is more of somebody in this than in a brick of salt, and it went the same way.",
        .envenomed_dagger => "A dirk with its groove packed and packed again with leechfly gut, black to the hilt and sticky in the hand. It takes less with it than a clean edge does, and what it leaves in the wound finishes the work.",
        .spidersilk_moccasins => "Shoes bound out of silk cut off a brood sac's shelf, light enough that you forget you have them on. What the spore beds put out does not stick to them, and they walk a little quicker than boots do.",
        .bloodtinge_signet => "A signet with a garnet gone almost black, set so deep the band has closed over the stone. Wearing it your blood runs thicker than it has any right to.",
        .loop_of_chance => "A loop of wire twisted through a holed coin, the kind pressed into a dead man's hand for the toll he owed. What it buys is nothing you can point at until something turns up that should not have.",
        .scroll_sunder => "Half a sheet, the tear old and clean. What is left shows a rod brought down close in, inside the length of a sword - which is the whole of what this one asks of you.",
        .nightcap_grease => "A jar of pale fat rendered off a dreaming cap, in the same waxed cloth the tallow comes in. Wiped along an edge it goes on thin and stays cold, and what it puts in a wound is not pain - it is the want of sleep, four strokes of it, and the body goes down where it stands.",
        .wakers_nail => "An iron nail bent round into a ring, filed flat where a thumb would rub it. The old orders wore them to keep a vigil honest: it sits against the bone and will not let you settle.",
        .madcap_powder => "Dried gill-dust off a ring of caps that grew too close together, ground fine and folded into a paper twist. Thrown, it hangs in the air about as long as a held breath, and everything inside it stops being sure which of the shapes around it it came in with.",
        .stolen_gravebell => "A hand-bell lifted off a hollow that was still swinging it, the bronze thin as a leaf and the clapper worn to a nub. It was cast to call the dead to their work. It never asked whose work, and it does not ask now - but ringing it takes the same thing out of you that a sorcery does.",
        .bloodwine => "Black wine gone to syrup in the neck of the bottle, cut with something that settles out red if you let it stand. Drink it and everything comes easier and faster for a while, and you pay for the while twice: once going, and once when it lets go of you.",
        .wax_stopped_hood => "A pilgrim's hood with the ears sewn shut and packed with candle-wax, done from the inside by somebody who wanted it that way. It came off a body a mile from the nearest bell, still walking a straight line.",
        .scroll_babble => "A sheet written over three times in three hands, none of them agreeing, and the last one going round the margin. Read aloud it does nothing to you. What it does is to whatever is listening.",
        .scroll_bidding => "One line, very large, very carefully drawn, and no words in it at all. Below it, small, in a different ink: WHAT IS OWED IS OWED TO WHOEVER HOLDS THE DEBT.",
    };
}

pub const Use = union(enum) {
    none,
    /// Refills one bank of the quiver (`combat.Quiver`). `n` is arrows, and the quiver caps it.
    arrows: struct { fire: bool, n: u8 },
    regen: struct { frac: f32, secs: f32 },
    /// `r` and `dose` together are the POWDER: no damage, one meter filled in everything inside the ring where
    /// it lands. `r` of 0 is the candle and the crock — the blow is the shaft's own and nothing spreads.
    lob: struct { dmg: f32, fire: f32 = 0, lightning: f32 = 0, poise: f32, dose: ?AilDose = null, r: f32 = 0 },
    /// A timed ward: `amount` of resistance in ONE named column for `secs` seconds. Refreshes, never stacks (the status law). **ONE COLUMN, NOT A SPREAD** — two tonics that each ward two things is a resistance sheet nobody can read off the bag.
    ward: struct { elem: ElemName, amount: f32, secs: f32 },
    wind: struct { share: f32 },
    /// `frac` of the blow hung on the edge as `elem`, on TOP of what the sword already did.
    grease: struct { elem: ElemName, frac: f32, secs: f32 },
    souls: struct { n: u32 },
    brew: struct { mult: f32, secs: f32 },
    purge,
    steady: struct { mult: f32, secs: f32 },
    /// **THE ONE USE THAT DOSES THE DRINKER.** `combat.Bearer` refusing a foe-only row in one place
    /// (`Vitals.build`) is what keeps a bottle of charm off the shelf.
    dose: AilDose,
    /// A COATING, not a grease (`grease` hangs an element on the blow). Both may run at once.
    coat: struct { ail: AilName, amt: f32, secs: f32 },
    /// **THE BELL — THE ONE ITEM THAT IS NOT SPENT.** Bills FOCUS instead of a charge, so what limits it is the
    /// pool and the walk in, not the count in the bag.
    toll: struct { ail: AilName, amt: f32, fp: f32, r: f32 },
};

/// `book.SlotId`'s own subset, named HERE because which socket a thing belongs in is a fact about the THING.
/// This file imports nothing but std, so `hero.wearFor` is the one place the two are matched up.
/// **APPENDED, NEVER INSERTED** — a save's `worn:` line is one word per socket in THIS order and the parser
/// stops at the end of a short line, so an older save loads with the new sockets empty. Inserting a tag re-points every equipped item in every file on disk.
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
    hand_dagger,
    hand_club,

    /// Read by the comptime gear check below (an `.arm` equip must live in a held socket) and by the two tests that ask about the WORN sockets — extending it is what let `item.DAGGER`/`item.CLUB` exist at all.
    pub fn held(w: Wear) bool {
        return switch (w) {
            .hand_sword, .hand_dagger, .hand_club, .hand_bow, .hand_shield => true,
            else => false,
        };
    }
};

/// **PRICED AS MULTIPLIERS ON THE ONE IT REPLACES**, never a fresh set of absolutes: `hero.ATK_*_HIT`,
/// `combat.STAM_*` and `combat.GUARD_*` stay the single place a swing, a block and their bills are written, and a
/// weapon says only how it DIFFERS. Bare-handed every dial is 1.
/// **WHICH SKILL DRIVES A WEAPON** — ER's scaling letters, ONE per armament. `quality` is the MEAN of the two curves, so either build carries the starting sword and neither is best with it.
pub const Scaling = enum { strength, dexterity, quality };

/// **WHAT KIND OF WEAPON IT IS, ON THE TWO AXES A FIGHT ACTUALLY ASKS ABOUT.** `reach` is where the blow lands
/// from and is pinned to the socket below — a thing in the bow hand is the ranged one. `heft` is how much of the
/// body goes into it: the multipliers say a club is slower and hits harder, but only this says it is swung like a club. The STROKES are the armament's (`hero.MOVES`); what reads `heft` is the book's own wording.
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
    /// **WHAT A LANDED STROKE PUTS IN THE BODY'S POISON METER** (`combat.Hit.dose`'s poison column, out of `combat.POISON_MAX`), and 0 for every clean edge. An ABSOLUTE, not a multiplier: the dose is the coating's, so it does not ride the damage dial or the skill.
    venom: f32 = 0,
};

pub const Res = struct {
    fire: f32 = 0,
    cold: f32 = 0,
    lightning: f32 = 0,
    chaos: f32 = 0,

    /// **THE COLUMNS ADD** (the plate law), walked rather than written out four times — a fifth element added to
    /// this struct is summed by every caller for free instead of being silently dropped by whoever forgot a line.
    pub fn plus(self: Res, other: Res) Res {
        var out = self;
        inline for (@typeInfo(Res).@"struct".fields) |f| @field(out, f.name) += @field(other, f.name);
        return out;
    }
};

/// `a` is the armour value in `A/(A + 5*dmg)` (`combat.armourTaken`), `res` the four elemental columns, `rate`
/// the ONE meter this piece slows and by how much, and `move` a multiplier on how fast he walks — one row, not
/// four verbs each stacked separately.
/// **THE RATE NAMES ITS METER** — a bare `poison: f32` was fine while poison was the only meter; at ten, a piece
/// that slowed "the status meter" slows all ten for free.
pub const Plate = struct { slot: Wear, a: f32 = 0, res: Res = .{}, rate: ?AilRate = null, move: f32 = 1 };

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

/// **A MELEE CLASS'S OWN ROW, WRITTEN ONCE.** The straight sword is the reference and is 1 on every dial — `hero.ATK_LIGHT_HIT`/`ATK_HEAVY_HIT` are literally its blow — and the other two classes say only how they differ. The two weapons standing in those sockets ARE these rows.
pub const DAGGER = Arm{ .slot = .hand_dagger, .heft = .light, .dmg = 0.74, .poise = 0.72, .dur = 0.78, .stam = 0.76, .scales = .dexterity };
pub const CLUB = Arm{ .slot = .hand_club, .heft = .heavy, .dmg = 1.48, .poise = 1.60, .dur = 1.34, .stam = 1.48, .scales = .strength };

/// **DERIVED FROM THE DAGGER'S ROW, NOT WRITTEN BESIDE IT** — a dirk retuned above retunes this one, and the two
/// dials named here are the whole of what the coating costs and buys: a duller edge, and four landed strokes to
/// a full meter (`combat.POISON_MAX` is 100).
pub const ENVENOMED = blk: {
    var a = DAGGER;
    a.dmg = 0.66;
    a.venom = 26;
    break :blk a;
};

/// **THE BARE ARMAMENT'S ROW** — every dial 1, and the skill that drives the thing he was born holding. An empty socket may not inherit the sword's `quality` default and quietly pay a bowman for his strength.
pub fn bareArm(w: Wear) Arm {
    return switch (w) {
        .hand_dagger => DAGGER,
        .hand_club => CLUB,
        else => .{
            .slot = w,
            .scales = if (w == .hand_bow) .dexterity else .quality,
            .reach = if (w == .hand_bow) .ranged else .melee,
        },
    };
}

pub const Gear = struct {
    kind: Kind,
    equip: Equip = .none,
    use: Use = .none,
};

pub const GEAR = [_]Gear{
    .{ .kind = .fang_dirk, .equip = .{ .arm = DAGGER } },
    // **THE FIRST EDGE IN THE GAME THAT LEAVES SOMETHING BEHIND.** Poison was the HERO's alone until this row.
    .{ .kind = .envenomed_dagger, .equip = .{ .arm = ENVENOMED } },
    .{ .kind = .greatclub, .equip = .{ .arm = CLUB } },
    .{ .kind = .grave_warbow, .equip = .{ .arm = .{ .slot = .hand_bow, .heft = .heavy, .reach = .ranged, .dmg = 1.62, .poise = 1.45, .dur = 1.28, .stam = 1.34, .scales = .dexterity } } },
    // A DOOR — half again the compass of the small shield, at four fifths of the speed and more per blow. **THE
    // NEGATION DIAL STOPS UNDER THE CAP ON PURPOSE**: `combat.GUARD_NEGATE_CAP` is 0.95 on a 0.85 base, so anything past ~1.118 is silently clamped — and `effect` PRINTS this figure.
    .{ .kind = .tower_shield, .equip = .{ .arm = .{ .slot = .hand_shield, .heft = .heavy, .negate = 1.10, .arc = 1.45, .walk = 0.80, .stam = 1.30 } } },
    // **A WHOLE SUIT IS WORTH 25, NOT 45** (owner: too much armour). The curve is `a/(a + 5*dmg)`, so at 45 a
    // best-in-slot kit turned aside HALF of every rank-and-file blow before the tree's own 32 went on top.
    .{ .kind = .quilted_gambeson, .equip = .{ .plate = .{ .slot = .chest, .a = 12.0 } } },
    .{ .kind = .leech_signet, .equip = .{ .charm = .{ .slot = .ring, .leech = 2.0, .hpFrac = 0.06 } } },
    .{ .kind = .pitted_helm, .equip = .{ .plate = .{ .slot = .helm, .a = 8.0 } } },
    .{ .kind = .marchboots, .equip = .{ .plate = .{ .slot = .feet, .a = 5.0 } } },
    // **CHAOS IS WHAT HE MEETS MOST AND NOTHING ON HIS SIDE ANSWERED IT** — the wand's bolt and roots, the knight's lit blow and gas, and what poison itself is billed as. LESS armour than the boots beside them on purpose: the trade is the column and the pace, not a strictly better shoe.
    .{ .kind = .spidersilk_moccasins, .equip = .{ .plate = .{ .slot = .feet, .a = 4.0, .res = .{ .chaos = 25 }, .move = 1.06 } } },
    .{ .kind = .banded_warbelt, .equip = .{ .boon = .{ .slot = .belt, .attr = .strength, .n = 3 } } },
    .{ .kind = .deft_signet, .equip = .{ .boon = .{ .slot = .ring2, .attr = .dexterity, .n = 3 } } },
    // THE TWO FINGERS TAKE ONE EACH so both can be on at once, and neither shares a socket with the other's attribute.
    .{ .kind = .bloodtinge_signet, .equip = .{ .boon = .{ .slot = .ring, .attr = .vitality, .n = 5 } } },
    .{ .kind = .loop_of_chance, .equip = .{ .boon = .{ .slot = .ring2, .attr = .luck, .n = 4 } } },
    .{ .kind = .ashen_amulet, .equip = .{ .boon = .{ .slot = .neck, .attr = .intelligence, .n = 3 } } },
    // **THE FIRST COLD RESISTANCE ANYWHERE ON HIS SIDE** — the necromancer's rune ring is the game's one source of cold and the sheet showed 0%. PHYSICAL under the gambeson's on purpose: a chest socket strictly better than the coat already in it retires that coat instead of competing with it.
    .{ .kind = .rimeward_mantle, .equip = .{ .plate = .{ .slot = .chest, .a = 7.0, .res = .{ .cold = 35 } } } },
    .{ .kind = .sporecrown, .equip = .{ .plate = .{ .slot = .helm, .a = 5.0, .rate = .{ .ail = .poison, .k = 0.55 } } } },
    .{ .kind = .gravebell_amulet, .equip = .{ .charm = .{ .slot = .neck, .spiritFp = 0.60, .fpFrac = 0.10 } } },
    .{ .kind = .soul_binding_ring, .equip = .{ .bind = .{ .slot = .ring } } },
    .{ .kind = .mushroom_jerky, .use = .{ .regen = .{ .frac = 0.60, .secs = 20.0 } } },
    .{ .kind = .ember_candle, .use = .{ .lob = .{ .dmg = 8, .fire = 22, .poise = 12 } } },
    .{ .kind = .sporeling_cap, .use = .{ .ward = .{ .elem = .chaos, .amount = 40, .secs = 60 } } },
    .{ .kind = .second_wind, .use = .{ .wind = .{ .share = 0.5 } } },
    .{ .kind = .fire_tallow, .use = .{ .grease = .{ .elem = .fire, .frac = 0.5, .secs = 60 } } },
    .{ .kind = .thundercrock, .use = .{ .lob = .{ .dmg = 8, .lightning = 22, .poise = 12 } } },
    .{ .kind = .nameless_soul, .use = .{ .souls = .{ .n = 150 } } },
    .{ .kind = .toadflesh_broth, .use = .{ .brew = .{ .mult = 1.5, .secs = 60 } } },
    .{ .kind = .purgeleaf, .use = .purge },
    .{ .kind = .pilgrims_salt, .use = .{ .souls = .{ .n = 600 } } },
    .{ .kind = .ironwort_tea, .use = .{ .steady = .{ .mult = 2.2, .secs = 40 } } },
    // THE SPORELING CAP'S TWO SIBLINGS, one column over each: the same 40 for the same minute, so which element
    // a fight is made of is the only question the bag asks.
    .{ .kind = .kiln_draught, .use = .{ .ward = .{ .elem = .fire, .amount = 40, .secs = 60 } } },
    .{ .kind = .rimewax, .use = .{ .grease = .{ .elem = .cold, .frac = 0.5, .secs = 60 } } },
    .{ .kind = .pilgrims_offering, .use = .{ .souls = .{ .n = 2000 } } },
    // **AMMUNITION IS AN ITEM NOW** (owner: arrows need to be droppable, placeable, all kinds) — both banks. **SIZED TO THE BANK, NOT GUESSED**: 12 into a quiver of 10 wasted two shafts on every pickup. This file imports nothing but std, so a test holds the two together.
    .{ .kind = .plain_arrows, .use = .{ .arrows = .{ .fire = false, .n = 10 } } },
    .{ .kind = .fire_arrows, .use = .{ .arrows = .{ .fire = true, .n = 5 } } },
    // FOUR STROKES TO A FULL METER — the dirk's own arithmetic (`ENVENOMED`), pinned in `combat`. A minute is
    // the tallow's clock.
    .{ .kind = .nightcap_grease, .use = .{ .coat = .{ .ail = .sleep, .amt = 26, .secs = 60 } } },
    .{ .kind = .wakers_nail, .equip = .{ .plate = .{ .slot = .ring, .rate = .{ .ail = .sleep, .k = 0.40 } } } },
    // **THE WHOLE METER IN ONE THROW.** Half-filling one nothing else can build never procs (`combat.AILS`).
    .{ .kind = .madcap_powder, .use = .{ .lob = .{ .dmg = 0, .poise = 0, .dose = .{ .ail = .confusion, .amt = 100 }, .r = 3.4 } } },
    .{ .kind = .stolen_gravebell, .use = .{ .toll = .{ .ail = .charm, .amt = 100, .fp = 24, .r = 5.0 } } },
    .{ .kind = .bloodwine, .use = .{ .dose = .{ .ail = .berserk, .amt = 100 } } },
    .{ .kind = .wax_stopped_hood, .equip = .{ .plate = .{ .slot = .helm, .a = 6.0, .rate = .{ .ail = .stupefy, .k = 0.40 } } } },
};

pub const INERT = [_]Kind{
    .crimson_flask,  .cerulean_flask, .rune_arc,    .golden_seed,
    .smithing_stone, .bloodgrass,     .kobold_fang, .iron_key,
    .spirit_scroll_wolf,
    // Inert on purpose: a scroll is neither worn nor used — it is CARRIED to a bonfire and racked there.
    .scroll_bolt,    .scroll_roots,   .scroll_rime, .scroll_levin,
    .scroll_siphon,  .scroll_lance,   .scroll_sunder,
    .scroll_babble,  .scroll_bidding,
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
                const bladeDials = a.dmg != 1 or a.poise != 1 or a.venom != 0;
                if (a.slot == .hand_shield and bladeDials) @compileError("item: " ++ @tagName(k) ++
                    " is a shield with damage, poise or venom on it — a board does not swing, and those dials are dead here");
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
    @setEvalBranchQuota(NK * @typeInfo(Wear).@"enum".fields.len * 8);
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

/// Closes a line built up clause by clause: the full stop and the NUL, in ONE place, or null if the buffer is out.
fn sentence(buf: []u8, n: usize) ?[:0]const u8 {
    if (n + 2 > buf.len) return null;
    buf[n] = '.';
    buf[n + 1] = 0;
    return buf[0 .. n + 1 :0];
}

fn plateElem(r: Res) ?struct { name: []const u8, amount: f32 } {
    if (r.fire != 0) return .{ .name = "fire", .amount = r.fire };
    if (r.cold != 0) return .{ .name = "cold", .amount = r.cold };
    if (r.lightning != 0) return .{ .name = "lightning", .amount = r.lightning };
    if (r.chaos != 0) return .{ .name = "chaos", .amount = r.chaos };
    return null;
}


pub fn isSpellScroll(k: Kind) bool {
    return switch (k) {
        .scroll_bolt,
        .scroll_roots,
        .scroll_rime,
        .scroll_levin,
        .scroll_siphon,
        .scroll_lance,
        .scroll_sunder,
        .scroll_babble,
        .scroll_bidding,
        => true,
        else => false,
    };
}

comptime {
    // **THE NINE SCROLL TAGS ARE WRITTEN TWICE** — once here and once in `class`'s `.treasure` arm — and
    // nothing but this held them together. A tenth sheet added to one list and not the other shelves as a
    // TOOL and lands on the quick bar, which is the one place the bag's own categories cannot say it is wrong.
    for (0..NK) |i| {
        const k: Kind = @enumFromInt(i);
        if (isSpellScroll(k) and class(k) != .treasure)
            @compileError("item: " ++ @tagName(k) ++ " is a sorcery scroll that `class` does not shelve as treasure");
    }
}

pub fn usable(k: Kind) bool {
    return std.meta.activeTag(use(k)) != .none;
}

pub fn dosed(k: Kind) bool {
    return switch (use(k)) {
        inline else => |payload| @TypeOf(payload) != void,
    };
}

/// **WHAT IT DOES, IN ONE LINE OF MECHANIC** — the answer to "which of these two flasks did I just put in the box", which the flavour prose (`describe`) deliberately does not give. Read off `use` wherever there is a `Use` to read, so a dose retuned there reads here.
pub fn effect(k: Kind, buf: []u8) [:0]const u8 {
    if (isFlask(k)) return switch (k) {
        .crimson_flask => "Heals. Charges refill at a bonfire, not from the bag.",
        else => "Restores Focus. Charges refill at a bonfire, not from the bag.",
    };
    if (k == .spirit_scroll_wolf) return "Carried: the bell can call Hildebrand.";
    // This file cannot import `combat`, so it will not write a second copy of the spell's name to say which.
    if (isSpellScroll(k)) return "Carried: memorize it at a bonfire to cast it.";
    if (k == .iron_key) return "Opens the one lock it was cut for.";
    // GEAR SAYS WHAT IT DOES IN THE SAME PLACE A TOOL DOES, off `equip` for the same reason the tools read `use`: a dial retuned in the table reads here.
    switch (equip(k)) {
        .none => {},
        .arm => |a| {
            if (a.slot == .hand_shield) return std.fmt.bufPrintZ(buf, "{s} {s}: blocks {d:.0}% more, covers {d:.0}% wider, walks at {d:.0}%.", .{
                a.heft.label(),
                a.reach.label(),
                (a.negate - 1) * 100,
                (a.arc - 1) * 100,
                a.walk * 100,
            }) catch "Held: a bigger shield.";
            var n = (std.fmt.bufPrint(buf, "{s} {s}: {d:.0}% damage, {d:.0}% poise, {d:.0}% {s} time", .{
                a.heft.label(),
                a.reach.label(),
                a.dmg * 100,
                a.poise * 100,
                a.dur * 100,
                if (a.reach == .ranged) @as([]const u8, "draw") else "swing",
            }) catch return "Held: its own weight and speed.").len;
            if (a.venom > 0) n += (std.fmt.bufPrint(buf[n..], ", +{d:.0} poison a hit", .{a.venom}) catch return "Held: a coated edge.").len;
            return sentence(buf, n) orelse "Held: its own weight and speed.";
        },
        // **THE ROW PRINTS WHAT IT ACTUALLY CARRIES, NOT ALL FOUR COLUMNS.** A coat that turns no cold has no business saying "0% cold" on the one panel a player compares two coats on. A CLAUSE PER DIAL rather than a branch per combination — four dials is sixteen sentences to write out.
        .plate => |p| {
            // **A PIECE THAT TURNS NO DAMAGE DOES NOT OPEN WITH "0 ARMOUR."**
            const head = if (p.a > 0)
                std.fmt.bufPrint(buf, "Worn: {d:.0} armour", .{p.a}) catch return "Worn: armour."
            else
                std.fmt.bufPrint(buf, "Worn:", .{}) catch return "Worn: a ward.";
            var n = head.len;
            if (plateElem(p.res)) |e| n += (std.fmt.bufPrint(buf[n..], "{s}{d:.0}% {s} resistance", .{ if (p.a > 0) @as([]const u8, ", ") else " ", e.amount, e.name }) catch return "Worn: armour and a ward.").len;
            if (p.rate) |r| n += (std.fmt.bufPrint(buf[n..], "{s}{s} fills at {d:.0}%", .{ if (n > head.len or p.a > 0) @as([]const u8, ", ") else " ", ailWord(r.ail), r.k * 100 }) catch return "Worn: armour and a ward.").len;
            if (p.move != 1) n += (std.fmt.bufPrint(buf[n..], ", walks at {d:.0}%", .{p.move * 100}) catch return "Worn: armour and a ward.").len;
            if (n == head.len) n += (std.fmt.bufPrint(buf[n..], " against physical damage", .{}) catch return "Worn: armour.").len;
            return sentence(buf, n) orelse "Worn: armour.";
        },
        // …AND THE CHARM SAYS WHICHEVER BARGAIN IT IS. Both halves on one line would price the gravebell's leech at zero and the signet's call at 100%.
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
        .lob => |l| if (l.dose) |d| std.fmt.bufPrintZ(buf, "Thrown at the reticle: bursts for {d:.0} {s} on everything inside {d:.1}m. No damage.", .{
            d.amt,
            ailWord(d.ail),
            l.r,
        }) catch "Thrown to fill a meter." else std.fmt.bufPrintZ(buf, "Thrown at the reticle: {d:.0} physical + {d:.0} {s}, {d:.0} poise.", .{
            l.dmg,
            l.fire + l.lightning,
            if (l.lightning > 0) @as([]const u8, "lightning") else "fire",
            l.poise,
        }) catch "Thrown for damage.",
        .ward => |w| std.fmt.bufPrintZ(buf, "+{d:.0}% {s} resistance for {d:.0}s. Refreshes, never stacks.", .{ w.amount, @tagName(w.elem), w.secs }) catch "Wards off an element.",
        .wind => |w| std.fmt.bufPrintZ(buf, "Gives back {d:.0}% of stamina at once, and lets the winded lockout go.", .{w.share * 100}) catch "Gives stamina back.",
        .grease => |gr| std.fmt.bufPrintZ(buf, "Sword hangs +{d:.0}% of its blow as {s} for {d:.0}s. Refreshes, never stacks.", .{ gr.frac * 100, @tagName(gr.elem), gr.secs }) catch "Coats the blade.",
        .souls => |s| std.fmt.bufPrintZ(buf, "Crushed for {d} souls, on the spot.", .{s.n}) catch "Worth souls.",
        .arrows => |a| std.fmt.bufPrintZ(buf, "Puts {d} {s} arrows back in the quiver.", .{ a.n, if (a.fire) @as([]const u8, "fire") else "plain" }) catch "Refills the quiver.",
        .brew => |b| std.fmt.bufPrintZ(buf, "Stamina comes back {d:.1}x as fast for {d:.0}s. Refreshes, never stacks.", .{ b.mult, b.secs }) catch "Stamina returns faster.",
        .purge => "Clears every meter outright, filling or already running.",
        .steady => |s| std.fmt.bufPrintZ(buf, "Poise comes back {d:.1}x as fast for {d:.0}s. Refreshes, never stacks.", .{ s.mult, s.secs }) catch "Poise returns faster.",
        .dose => |d| std.fmt.bufPrintZ(buf, "Puts {d:.0} {s} in YOUR OWN meter, at once.", .{ d.amt, ailWord(d.ail) }) catch "Fills one of your own meters.",
        .coat => |c| std.fmt.bufPrintZ(buf, "Edge carries +{d:.0} {s} a hit for {d:.0}s. Refreshes, never stacks.", .{ c.amt, ailWord(c.ail), c.secs }) catch "Coats the blade.",
        .toll => |t| std.fmt.bufPrintZ(buf, "Rung for {d:.0} focus: {d:.0} {s} into everything inside {d:.1}m. Not spent.", .{ t.fp, t.amt, ailWord(t.ail), t.r }) catch "Rung for focus.",
    };
}

pub const EFFECT_BUF: usize = 128;

/// THE TWO THE FLASK SYSTEM OWNS. They sit on the quick bar like anything else, but their charges live in `combat.Flasks` and come back at a bonfire, so spending one never touches the bag. Named here rather than in `combat` because it is a fact about the ITEM.
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

/// The kind whose tag IS `TAG_MAX`. `save.CAP`'s worst case is sized off the longest tag, so the test that proves the buffer holds it has to WRITE that tag — hand-picking a plausible one understated the row by two characters a slot, silently.
pub const LONGEST_TAG: Kind = blk: {
    var worst: Kind = @enumFromInt(0);
    for (@typeInfo(Kind).@"enum".fields) |f| {
        if (f.name.len > @tagName(worst).len) worst = @enumFromInt(f.value);
    }
    break :blk worst;
};

comptime {
    // `TAG_MAX` is now DERIVED from `LONGEST_TAG`, so the two cannot disagree — which also means a wrong argmax would go unnoticed. This is the independent pass the derivation replaced.
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
            // **DAMAGE OR A DOSE, AND EXACTLY ONE OF THE TWO.** A lob that does neither is the real mistake, and
            // one that doses without a ring puts its whole worth on a direct hit with a lobbed projectile.
            .lob => |l| {
                found += 1;
                try std.testing.expect(usable(k));
                if (l.dose) |d| {
                    try std.testing.expectApproxEqAbs(@as(f32, 0), l.dmg + l.fire + l.lightning, 1e-6);
                    try std.testing.expect(d.amt > 0);
                    try std.testing.expect(l.r > 0);
                } else {
                    try std.testing.expect(l.dmg + l.fire + l.lightning > 0);
                    try std.testing.expectApproxEqAbs(@as(f32, 0), l.r, 1e-6);
                }
            },
            .arrows => |a| {
                found += 1;
                try std.testing.expect(usable(k));
                // A sheaf worth nothing is a sheaf that shelves as clutter. The upper bound is checked against `combat.Quiver.cap` where the two can see each other.
                try std.testing.expect(a.n > 0 and a.n < 100);
            },
            .ward => |w| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(w.amount > 0 and w.secs > 0);
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
            .dose => |d| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(d.amt > 0);
            },
            .coat => |c| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(c.amt > 0 and c.secs > 0);
            },
            // **THE BELL IS THE ONE USE WITH A PRICE ON IT** — free, there is no reason not to stand ringing it.
            .toll => |t| {
                found += 1;
                try std.testing.expect(usable(k));
                try std.testing.expect(t.amt > 0 and t.r > 0);
                try std.testing.expect(t.fp > 0);
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
    try std.testing.expectEqual(@as(usize, 21), worn);
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
    try std.testing.expectEqual(@as(usize, 5), boons);
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
                // Every dial is a multiple of what the bare armament already does, so a row of all 1s is a piece of gear that exists and changes nothing.
                try std.testing.expect(a.dmg > 0 and a.poise > 0 and a.dur > 0 and a.stam > 0);
                try std.testing.expect(a.negate > 0 and a.arc > 0 and a.walk > 0);
                const gains = (a.dmg > 1) or (a.poise > 1) or (a.negate > 1) or (a.arc > 1) or (a.dur < 1) or (a.stam < 1) or (a.walk > 1);
                const costs = (a.dmg < 1) or (a.poise < 1) or (a.negate < 1) or (a.arc < 1) or (a.dur > 1) or (a.stam > 1) or (a.walk < 1);
                try std.testing.expect(gains and costs);
            },
            // **A PIECE MUST CARRY SOMETHING, AND ARMOUR IS ONE OF FOUR THINGS IT CAN BE.** Asking `a > 0` means
            // writing 0 armour on a ring whose whole worth is a rate, just to get it past this.
            .plate => |p| {
                const res = p.res.fire != 0 or p.res.cold != 0 or p.res.lightning != 0 or p.res.chaos != 0;
                try std.testing.expect(p.a > 0 or res or p.rate != null or p.move != 1);
                if (p.rate) |r| try std.testing.expect(r.k > 0 and r.k != 1);
            },
            .charm => |c| {
                const gives = c.leech > 0 or c.spiritFp < 1;
                const takes = c.hpFrac > 0 or c.fpFrac > 0;
                try std.testing.expect(gives and takes);
            },
            .boon => |b| try std.testing.expect(b.n > 0),
            // A BIND HAS NO DIALS TO TRADE — the socket is the price, and it is spent by dying. What it owes instead is a finger, which the comptime block over `GEAR` already refuses to let it skip.
            .bind => {},
            .none => {},
        }
    }
}
