const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const uiart = @import("uiart.zig");
const item = @import("item.zig");
const combat = @import("combat.zig"); // …and WHICH SORCERY a picture is of (`spellArt`), the one enum here beside `item.Kind`

// Every stroke scales off `k`: the set was tuned in a 34 px box (`TUNED_AT`) and multiplies up, so one picture
// serves a 33 px bag cell and a 240 px detail plate. Every wabi-sabi offset comes out of a FIXED-SEED
// `mathx.Rng` re-seeded per call — off a live stream the whole HUD crawls.

const rgba = mathx.rgba;

pub const STEEL = rgba(232, 234, 238, 255);
pub const STEEL_MID = rgba(178, 184, 192, 255); // a blade's BODY: polished steel in a black well reads light
pub const STEEL_DK = rgba(126, 132, 140, 255);
pub const BRASS = rgba(182, 146, 78, 255);
pub const GRIP = rgba(112, 82, 56, 255);
pub const BOARD_JOINT = rgba(78, 56, 38, 255); // the shield icon's plank seams — a shade under GRIP
pub const GRIP_LT = rgba(146, 110, 76, 255); // …and the lit lip below one, which is what makes a seam an EDGE
pub const WAX = rgba(126, 34, 30, 255); // the flask's seal over its stopper
pub const GLASS_LIT = rgba(238, 236, 230, 255);
pub const CORD = rgba(158, 142, 108, 255); // the tie round its neck, and the bow's own wrap
pub const FIRE = rgba(255, 158, 62, 255);
const FIRE_DIM = rgba(226, 108, 30, 150);
/// THE CHAOS VIOLET — the wand's stone and the bolt in the sorcery slot, and the same element the world
/// draws in `hero.CHAOS_MOTE`. Brighter here because these are LITERAL screen values (the HUD draws after
/// the retro blit, outside the scene shader), where the mesh's are albedo the shader's hot key lifts.
pub const CHAOS = rgba(178, 92, 224, 255);
const CHAOS_LT = rgba(226, 182, 252, 255);
const CHAOS_DK = rgba(96, 40, 132, 255);
const BOWWOOD = rgba(96, 68, 44, 255);
const BOWWOOD_LT = rgba(140, 102, 66, 255); // the lit BACK of a limb — a bow has a front and a back
const BOWNOCK = rgba(196, 188, 168, 255); // the horn nock the string sits in
const BOWSTRING = rgba(214, 206, 184, 255);
const CRIMSON = rgba(196, 46, 40, 255); // Flask of Crimson Tears
const CRIMSON_DK = rgba(104, 24, 22, 255);
const CERULEAN = rgba(64, 128, 200, 255);
const CERULEAN_DK = rgba(28, 62, 118, 255);
const CORK = rgba(150, 118, 74, 255);
const BONE = rgba(224, 212, 182, 255);
const BONE_DK = rgba(150, 136, 104, 255);
const IRON_DK = rgba(74, 68, 60, 255);
const RUST = rgba(122, 74, 44, 255);
const STONE = rgba(132, 130, 126, 255);
const STONE_LT = rgba(186, 184, 178, 255);
const STONE_DK = rgba(74, 73, 70, 255);
const SPARK = rgba(180, 214, 236, 255); // the cold blue-white a struck facet throws
const RIME_ICE = rgba(150, 200, 226, 255); // the rime breath's crystal — `elemfx`'s COLD hue, on a card
const RIME_LT = rgba(212, 238, 250, 255);
/// THE LEVIN'S PAIR — `elemfx`'s LIGHTNING, which is **the only colourless signature in that table**, and the
/// icon has to keep that: given any blue at all it becomes the rime's crystal at another brightness, which is
/// the exact confusion the element was authored achromatic to avoid.
const LEVIN_HOT = rgba(255, 255, 224, 255);
const LEVIN_EDGE = rgba(226, 230, 232, 255);
const WEED = rgba(126, 30, 34, 255); // bloodgrass: dried arterial red, not a leaf green
const WEED_LT = rgba(178, 62, 52, 255);
const WEED_DK = rgba(74, 20, 24, 255);
const CAP_DK = rgba(96, 58, 42, 255); // dried mushroom: the leathery outside…
const CAP_LT = rgba(158, 108, 72, 255); // …and the pale torn flesh
const SALT = rgba(226, 208, 176, 255);
/// THE ROOTS' own three: dead wood, the blunt snap of pale heartwood where a tendril broke, and the earth it
/// came up through. Darker than `BOWWOOD` — this is wood out of the ground, not a limb somebody oiled.
const ROOT_BARK = rgba(64, 46, 32, 255);
const ROOT_HEART = rgba(172, 148, 112, 255);
const ROOT_SOIL = rgba(52, 40, 30, 255);
/// The sporeling's brick over cream — brighter than the creature's albedo, HUD colours are literal.
const SHROOM_CAP = rgba(178, 84, 70, 255);
/// THE BINDING RING'S OWN GOLD, and the soul it is holding. Kept off `BRASS` on purpose: brass is fittings,
/// this is the one precious metal in the bag.
const RING_GOLD = rgba(214, 176, 84, 255);
const RING_GOLD_LT = rgba(248, 226, 160, 255);
const RING_SOUL = rgba(250, 214, 132, 255);
const SHROOM_CAP_DK = rgba(112, 48, 40, 255);
const SHROOM_CREAM = rgba(224, 206, 170, 255);
const EMBER_FAT = rgba(230, 196, 130, 255);
const EMBER_FAT_DK = rgba(178, 140, 84, 255);
/// THE BELL'S BRONZE. Warmer and darker than `BRASS` (the world's fittings) so the two do not read as one
/// metal, and the bore is near-black because it is a HOLE — the same free contrast the scroll's ink takes.
const BRONZE = rgba(168, 126, 58, 255);
const BRONZE_LT = rgba(214, 176, 102, 255);
const BRONZE_DK = rgba(104, 76, 34, 255);
const BRONZE_BORE = rgba(38, 28, 14, 255);
/// THE SCROLL — hide gone stiff as board, so it is browner and duller than `BONE`, which is clean bone.
const HIDE = rgba(198, 176, 134, 255);
const HIDE_LT = rgba(226, 208, 172, 255);
const HIDE_DK = rgba(132, 112, 80, 255);
/// …and the wolf inked on it, which is the one COLD thing in the picture. Separated from the hide on HUE and
/// not on value (the sheet is warm, the spirit is not): at icon size a darker brown line on brown hide reads
/// as a crease, where a grey one reads as a drawing. It is also what the creature itself will be.
const SPIRIT = rgba(146, 166, 190, 255);
const SPIRIT_LT = rgba(206, 222, 238, 255);

/// THE BOX EVERY STROKE WAS TUNED IN. A picture drawn at `px` multiplies each weight by `px / TUNED_AT`.
pub const TUNED_AT: f32 = 34.0;

fn strokeK(px: f32) f32 {
    return px / TUNED_AT;
}

/// Two triangles making one quad, WOUND WHICHEVER WAY RAYLIB WILL ACTUALLY RASTERISE. It culls a back-facing
/// 2D triangle, so a quad handed over the wrong way round is silently not drawn — which is how the sword
/// icon's blade body went missing and left a point triangle plus two hairlines. Callers give the four
/// corners in order and stop caring.
fn quad(a: rl.Vector2, b: rl.Vector2, c: rl.Vector2, d: rl.Vector2, col: rl.Color) void {
    // Signed area of a→b→c in SCREEN space, where y runs down: raylib draws the NEGATIVE one.
    if ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) <= 0) {
        rl.drawTriangle(a, b, c, col);
        rl.drawTriangle(a, c, d, col);
    } else {
        rl.drawTriangle(a, d, c, col);
        rl.drawTriangle(a, c, b, col);
    }
}

/// A point `along` the axis from `from` to `to`, pushed `off` sideways across it.
fn onAxis(from: rl.Vector2, to: rl.Vector2, along: f32, off: f32) rl.Vector2 {
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const len = @max(@sqrt(dx * dx + dy * dy), 1e-4);
    const nx = -dy / len;
    const ny = dx / len;
    return .{ .x = from.x + dx * along + nx * off, .y = from.y + dy * along + ny * off };
}

fn v2(x: f32, y: f32) rl.Vector2 {
    return .{ .x = x, .y = y };
}

/// An arc struck in segments, tapering from `w0` to `w1`. Raylib's ring primitive is a filled annulus with
/// square ends; every curved thing in this set wants a tapered one, so it is drawn as a run of strokes.
fn arc(cx: f32, cy: f32, r: f32, from: f32, to: f32, segs: u32, w0: f32, w1: f32, col: rl.Color) void {
    var i: u32 = 0;
    while (i < segs) : (i += 1) {
        const t0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segs));
        const t1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(segs));
        const a0 = mathx.lerpF(from, to, t0);
        const a1 = mathx.lerpF(from, to, t1);
        rl.drawLineEx(
            v2(cx + mathx.cosf(a0) * r, cy + mathx.sinf(a0) * r),
            v2(cx + mathx.cosf(a1) * r, cy + mathx.sinf(a1) * r),
            mathx.lerpF(w0, w1, (t0 + t1) * 0.5),
            col,
        );
    }
}

pub const FlaskTint = enum { crimson, cerulean };

/// WHAT AN ITEM LOOKS LIKE — the one place the binding is written, and EXHAUSTIVE, so a tenth kind is a
/// compile error here rather than a blank cell in the bag.
pub fn draw(k: item.Kind, cx: f32, cy: f32, px: f32) void {
    drawHeld(k, cx, cy, px, true);
}

/// …and the same picture knowing whether there is any of it LEFT, which only the quick slot and the flask
/// ever ask: an empty glass reads as empty, and everything else is drawn whole because a bag row you can
/// see at all is a row with one in it.
pub fn drawHeld(k: item.Kind, cx: f32, cy: f32, px: f32, any: bool) void {
    switch (k) {
        .crimson_flask => flask(cx, cy, px, .crimson, any),
        .cerulean_flask => flask(cx, cy, px, .cerulean, any),
        .rune_arc => soulArc(cx, cy, px),
        .golden_seed => goldenSeed(cx, cy, px),
        .smithing_stone => smithingStone(cx, cy, px),
        .bloodgrass => bloodgrass(cx, cy, px),
        .kobold_fang => koboldFang(cx, cy, px),
        .iron_key => ironKey(cx, cy, px),
        .mushroom_jerky => jerky(cx, cy, px),
        .ember_candle => emberCandle(cx, cy, px),
        .sporeling_cap => sporelingCap(cx, cy, px),
        .second_wind => secondWind(cx, cy, px),
        .tower_shield => towerShield(cx, cy, px),
        .greatclub => greatclub(cx, cy, px),
        .leech_signet => leechSignet(cx, cy, px),
        .soul_binding_ring => soulRing(cx, cy, px),
        .fire_tallow => fireTallow(cx, cy, px),
        .thundercrock => thundercrock(cx, cy, px),
        .nameless_soul => crackedSoul(cx, cy, px),
        .toadflesh_broth => toadfleshBroth(cx, cy, px),
        .fang_dirk => fangDirk(cx, cy, px),
        .grave_warbow => graveWarbow(cx, cy, px),
        .quilted_gambeson => quiltedGambeson(cx, cy, px),
        .spirit_scroll_wolf => spiritScroll(cx, cy, px, .wolf),
        .pitted_helm => pittedHelm(cx, cy, px),
        .ashen_amulet => ashenAmulet(cx, cy, px),
        .banded_warbelt => bandedWarbelt(cx, cy, px),
        .marchboots => marchboots(cx, cy, px),
        .deft_signet => deftSignet(cx, cy, px),
    }
}

/// **WHICH PICTURE A SORCERY IS, AND THE ONE PLACE IT IS DECIDED** — `drawHeld`'s own shape one enum along.
/// Written out at the HUD's cross AND at the character book's socket, it was one list of five in two files that
/// differed only in how each spelled "can he afford it": a sixth spell is now one row here instead of a picture
/// somebody has to remember twice. `lit` is that affordability — a thing you cannot cast has to LOOK it, the
/// ammo box's own rule.
pub fn spellArt(s: combat.Spell, cx: f32, cy: f32, px: f32, lit: bool) void {
    switch (s) {
        .bolt => spell(cx, cy, px, lit),
        .roots => roots(cx, cy, px, lit),
        // THE CONE is what this one's picture has to carry: it is the one spell that is a direction and a width
        // rather than a mark thrown at somebody.
        .rime => rime(cx, cy, px, lit),
        // …and the two that arrive without crossing the ground: a STROKE and a DRAIN, which is the one thing
        // each has to say, since neither is a thing sailing through the air like the bolt.
        .levin => levin(cx, cy, px, lit),
        .siphon => siphon(cx, cy, px, lit),
    }
}

/// **AN OPEN-FACED HELM, AND WHAT SAYS HELM IS THE DOME PLUS THE NASAL.** Drawn as a dark dome with a wide black
/// face gap split by a thick nose bar it read as a keyhole in a stone: the gap became a T and the iron sat at the
/// cell's own value, so there was no dome to see. So — the iron is LIT well clear of the background, the gap is
/// narrow and inset with cheek metal showing either side of it, and the nasal hangs only halfway down it.
/// The PITTING is eaten out of one cheek only (the wabi-sabi law: uneven, one side, off a seeded `Rng`).
fn pittedHelm(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x4E1);
    const iron = rgba(132, 124, 112, 255);
    const ironLo = rgba(88, 82, 74, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.02 + 1.4 * k), s * 0.26, rgba(0, 0, 0, 115));
    // THE DOME, and it is the biggest thing in the cell: shaded half first, lit crown over it.
    rl.drawCircleV(v2(cx, cy - s * 0.03), s * 0.245, ironLo);
    rl.drawCircleV(v2(cx - s * 0.03, cy - s * 0.06), s * 0.205, iron);
    arc(cx - s * 0.02, cy - s * 0.05, s * 0.20, std.math.pi * 1.06, std.math.pi * 1.62, 10, 2.0 * k, 1.0 * k, rgba(186, 178, 162, 255));
    // …AND THE CHEEKS BELOW IT, so the dark gap is INSET in metal rather than cutting the dome in half.
    quad(v2(cx - s * 0.235, cy + s * 0.02), v2(cx + s * 0.235, cy + s * 0.02), v2(cx + s * 0.185, cy + s * 0.24), v2(cx - s * 0.185, cy + s * 0.24), ironLo);
    // THE OPENING — narrow, low, and stopping well short of both cheek edges.
    quad(v2(cx - s * 0.125, cy + s * 0.05), v2(cx + s * 0.125, cy + s * 0.05), v2(cx + s * 0.10, cy + s * 0.20), v2(cx - s * 0.10, cy + s * 0.20), rgba(14, 12, 10, 240));
    // The nasal hangs HALFWAY only: full-length it splits the gap into two eyes and the whole thing reads as a T.
    rl.drawLineEx(v2(cx, cy + s * 0.04), v2(cx, cy + s * 0.13), 1.6 * k, iron);
    // The brow band across the join, brighter than the dome so it reads as a separate hoop, and riveted.
    quad(v2(cx - s * 0.24, cy - s * 0.03), v2(cx + s * 0.24, cy - s * 0.03), v2(cx + s * 0.235, cy + s * 0.04), v2(cx - s * 0.235, cy + s * 0.04), rgba(160, 152, 138, 255));
    rl.drawCircleV(v2(cx - s * 0.17, cy + s * 0.005), 1.5 * k, rgba(70, 64, 56, 255));
    rl.drawCircleV(v2(cx + s * 0.17, cy + s * 0.005), 1.5 * k, rgba(70, 64, 56, 255));
    // …AND THE RUST EATING ONE CHEEK THROUGH. Three bites, none the same size, all on the left.
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const fy = cy + s * 0.04 + @as(f32, @floatFromInt(i)) * s * 0.062;
        rl.drawCircleV(v2(cx - s * 0.155 + rng.range(-1.5, 1.5) * k, fy), s * rng.range(0.020, 0.040), RUST);
    }
}

/// A GREY BEAD ON A THONG — the read is the V of the cord, because a bead alone is the signet's own picture at a
/// different size. Cord first, bead over its knot.
fn ashenAmulet(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xA5BE);
    const cord = rgba(72, 60, 48, 255);
    const top = cy - s * 0.28;
    // The two runs of the thong, deliberately unequal — a knot nobody tied straight.
    rl.drawLineEx(v2(cx - s * 0.16, top), v2(cx - s * 0.015, cy + s * 0.08), 1.8 * k, cord);
    rl.drawLineEx(v2(cx + s * 0.15 + rng.range(-1, 1) * k, top - s * 0.01), v2(cx + s * 0.02, cy + s * 0.08), 1.8 * k, cord);
    arc(cx, top + s * 0.01, s * 0.16, std.math.pi * 1.08, std.math.pi * 1.92, 8, 1.6 * k, 1.6 * k, cord); // the loop over the neck
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.15 + 1.2 * k), s * 0.115, rgba(0, 0, 0, 110));
    // THE BEAD: ash grey, and the one warm note is the gloss, because the prose says it is warm.
    rl.drawCircleV(v2(cx, cy + s * 0.13), s * 0.105, rgba(122, 118, 112, 255));
    arc(cx, cy + s * 0.13, s * 0.075, std.math.pi * 0.85, std.math.pi * 1.55, 8, 1.5 * k, 0.8 * k, rgba(176, 170, 160, 255));
    rl.drawCircleV(v2(cx - s * 0.03, cy + s * 0.09), 1.6 * k, rgba(236, 214, 176, 210));
    rl.drawCircleV(v2(cx + s * 0.04, cy + s * 0.18), s * 0.022, rgba(74, 70, 66, 255)); // a chip out of it
}

/// **A BELT IS A BUCKLE AND A TONGUE, NOT A RING.** Drawn as a ring it is the signet again; drawn as the buckle
/// end with the strap running out of it and the SPARE punched holes showing, it reads as a belt cut for somebody
/// bigger — which is what the prose says it is.
fn bandedWarbelt(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xBE17);
    const hide = rgba(88, 62, 42, 255);
    const hideLt = rgba(126, 92, 62, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + 1.4 * k), s * 0.26, rgba(0, 0, 0, 105));
    // The strap: one band across, leaning a little, with the far end curling under.
    quad(v2(cx - s * 0.34, cy - s * 0.09), v2(cx + s * 0.30, cy - s * 0.12), v2(cx + s * 0.30, cy + s * 0.05), v2(cx - s * 0.34, cy + s * 0.08), hide);
    quad(v2(cx - s * 0.34, cy - s * 0.09), v2(cx + s * 0.30, cy - s * 0.12), v2(cx + s * 0.30, cy - s * 0.07), v2(cx - s * 0.34, cy - s * 0.04), hideLt); // the lit top edge
    // THE BANDING — iron straps across it, uneven spacing (between the instances, not along one).
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const bx = cx - s * 0.20 + @as(f32, @floatFromInt(i)) * s * 0.155 + rng.range(-2, 2) * k;
        quad(v2(bx, cy - s * 0.11), v2(bx + s * 0.035, cy - s * 0.11), v2(bx + s * 0.035, cy + s * 0.07), v2(bx, cy + s * 0.07), rgba(96, 88, 78, 255));
    }
    // The buckle at the near end: a frame, not a filled block, or it is a stone on a strap.
    quad(v2(cx - s * 0.36, cy - s * 0.15), v2(cx - s * 0.20, cy - s * 0.15), v2(cx - s * 0.20, cy + s * 0.13), v2(cx - s * 0.36, cy + s * 0.13), rgba(140, 130, 116, 255));
    quad(v2(cx - s * 0.32, cy - s * 0.09), v2(cx - s * 0.24, cy - s * 0.09), v2(cx - s * 0.24, cy + s * 0.07), v2(cx - s * 0.32, cy + s * 0.07), rgba(24, 20, 18, 225));
    rl.drawLineEx(v2(cx - s * 0.28, cy - s * 0.13), v2(cx - s * 0.28, cy + s * 0.11), 1.8 * k, rgba(170, 160, 144, 255)); // the pin
    // …AND THE PUNCHED HOLES, which are the whole story: the new one, and the old ones nobody uses.
    rl.drawCircleV(v2(cx + s * 0.13, cy - s * 0.03), 1.7 * k, rgba(30, 22, 16, 235));
    rl.drawCircleV(v2(cx + s * 0.22, cy - s * 0.04), 1.5 * k, rgba(30, 22, 16, 200));
}

/// BOOTS, AND THERE ARE TWO OF THEM — one alone reads as a sock. The near one over the far one, both leaning,
/// and the SOLE is a separate darker slab because a boot worn through to the second layer of hide is the prose.
fn marchboots(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    const hide = rgba(74, 56, 42, 255);
    const hideDk = rgba(46, 34, 26, 255);
    const sole = rgba(58, 50, 44, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.18 + 1.4 * k), s * 0.26, rgba(0, 0, 0, 110));
    // THE FAR BOOT, offset up and back, darker — it is behind and it is in the near one's shade.
    quad(v2(cx - s * 0.02, cy - s * 0.24), v2(cx + s * 0.15, cy - s * 0.24), v2(cx + s * 0.17, cy + s * 0.10), v2(cx - s * 0.01, cy + s * 0.10), hideDk);
    quad(v2(cx - s * 0.01, cy + s * 0.05), v2(cx + s * 0.30, cy + s * 0.09), v2(cx + s * 0.30, cy + s * 0.17), v2(cx - s * 0.01, cy + s * 0.15), hideDk);
    // …and the near one, the shaft slumped over on itself the way an unlaced boot stands.
    quad(v2(cx - s * 0.26, cy - s * 0.20), v2(cx - s * 0.07, cy - s * 0.22), v2(cx - s * 0.05, cy + s * 0.14), v2(cx - s * 0.24, cy + s * 0.14), hide);
    quad(v2(cx - s * 0.27, cy - s * 0.20), v2(cx - s * 0.17, cy - s * 0.21), v2(cx - s * 0.15, cy - s * 0.09), v2(cx - s * 0.26, cy - s * 0.08), rgba(104, 80, 58, 255)); // the flopped cuff
    quad(v2(cx - s * 0.25, cy + s * 0.09), v2(cx + s * 0.08, cy + s * 0.13), v2(cx + s * 0.08, cy + s * 0.21), v2(cx - s * 0.25, cy + s * 0.19), hide);
    // The soles, and the wear: the near one's toe is through.
    quad(v2(cx - s * 0.26, cy + s * 0.19), v2(cx + s * 0.09, cy + s * 0.21), v2(cx + s * 0.09, cy + s * 0.26), v2(cx - s * 0.26, cy + s * 0.24), sole);
    rl.drawCircleV(v2(cx + s * 0.03, cy + s * 0.17), s * 0.03, rgba(112, 92, 70, 220));
    rl.drawLineEx(v2(cx - s * 0.20, cy - s * 0.10), v2(cx - s * 0.11, cy - s * 0.08), 1.2 * k, hideDk); // one lace hole run
    rl.drawLineEx(v2(cx - s * 0.20, cy - s * 0.02), v2(cx - s * 0.10, cy), 1.2 * k, hideDk);
}

/// THE SECOND BAND, AND IT MUST NOT BE THE FIRST ONE. `leechSignet` is a horn ring with a red bead high on it;
/// this is bare metal with NO stone at all and a bright worn INNER edge — the one thing the prose gives it.
fn deftSignet(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.03 + 1.0 * k), s * 0.20, rgba(0, 0, 0, 110));
    arc(cx, cy + s * 0.02, s * 0.175, 0, std.math.tau, 20, s * 0.062, s * 0.062, rgba(118, 112, 102, 255));
    // THE WORN INSIDE — a bright arc drawn just inboard of the band, which is the knife-edge the thumb made.
    arc(cx, cy + s * 0.02, s * 0.145, std.math.pi * 0.15, std.math.pi * 1.05, 12, 1.3 * k, 1.3 * k, rgba(206, 200, 186, 255));
    arc(cx - s * 0.03, cy - s * 0.01, s * 0.17, std.math.pi * 0.95, std.math.pi * 1.5, 8, 1.7 * k, 0.9 * k, rgba(168, 160, 146, 255)); // the lit shoulder
    // A flat facet where a stone would have been on a richer ring: this one has none, and that IS the read.
    quad(v2(cx - s * 0.045, cy - s * 0.20), v2(cx + s * 0.045, cy - s * 0.20), v2(cx + s * 0.035, cy - s * 0.13), v2(cx - s * 0.035, cy - s * 0.13), rgba(142, 136, 124, 255));
}

/// THE SUMMONING BELL — a cross's picture, not a bag row: it is an ARMAMENT, drawn beside `sword` and `bow`
/// and taking no `item.Kind`. The flare and the OPEN MOUTH are the whole read — a quad whose foot is wider
/// than its head, an elliptical rim under it, and the bore as a darker ellipse INSIDE that rim, since at
/// 34 px a bell with a filled bottom is a thimble.
pub fn bell(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xBE11);
    const lean = rng.range(-0.6, 0.6) * k;
    const mouthY = cy + s * 0.24;
    const crownY = cy - s * 0.12;
    const hw = s * 0.215; // half the mouth
    const cw = s * 0.085; // …and half the shoulder
    rl.drawCircleV(v2(cx + 1.2 * k, mouthY + 1.0 * k), hw, rgba(0, 0, 0, 110));

    rl.drawLineEx(v2(cx + lean, cy - s * 0.36), v2(cx + lean, crownY), 3.6 * k, GRIP);
    rl.drawCircleV(v2(cx + lean, cy - s * 0.345), 2.6 * k, GRIP_LT);
    rl.drawCircleV(v2(cx + lean, cy - s * 0.245), 2.9 * k, GRIP); // the swell the fist closes on

    // THE SKIRT. The sides bow OUT rather than running straight — a cone is a funnel, a curve is a bell.
    quad(v2(cx - cw + lean, crownY), v2(cx + cw + lean, crownY), v2(cx + hw, mouthY), v2(cx - hw, mouthY), BRONZE);
    // The shoulder: a dome capping the skirt, which is what the crown actually is.
    arc(cx + lean, crownY + s * 0.015, cw, std.math.pi, std.math.tau, 10, s * 0.055, s * 0.055, BRONZE);
    // The lit edge down the near side, and the moulding round the waist — sunk, a few percent proud.
    rl.drawLineEx(v2(cx - cw * 0.8 + lean, crownY + s * 0.01), v2(cx - hw * 0.88, mouthY - s * 0.02), 1.6 * k, BRONZE_LT);
    const wy = mathx.lerpF(crownY, mouthY, 0.62);
    const ww = mathx.lerpF(cw, hw, 0.62);
    rl.drawLineEx(v2(cx - ww, wy), v2(cx + ww, wy), 1.8 * k, BRONZE_DK);

    // THE MOUTH — the rim ellipse, then the bore inside it. Raylib has no ellipse primitive with a stroke, so
    // the rim is the outer fill and the bore is a smaller one laid on top.
    rl.drawEllipse(@intFromFloat(cx), @intFromFloat(mouthY), hw, s * 0.075, BRONZE_LT);
    rl.drawEllipse(@intFromFloat(cx), @intFromFloat(mouthY), hw - 2.2 * k, s * 0.075 - 1.6 * k, BRONZE_BORE);
    rl.drawLineEx(v2(cx + s * 0.02, mouthY - s * 0.10), v2(cx + s * 0.055, mouthY + s * 0.005), 1.3 * k, BRONZE_DK);
    rl.drawCircleV(v2(cx + s * 0.055, mouthY + s * 0.02), 2.6 * k, BRONZE_LT);
}

/// A HIDE SCROLL, HALF UNROLLED, with the spirit it carries inked on the face — one sheet standing out of one
/// roll, and the drawing is the only thing that changes between scrolls (`SpiritGlyph`), so a second spirit is
/// a glyph and not a second picture.
fn spiritScroll(cx: f32, cy: f32, px: f32, glyph: SpiritGlyph) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x5C011);
    const lean = rng.range(-0.8, 0.8) * k; // no scroll was ever rolled square
    const hw = s * 0.21;
    const top = cy - s * 0.33;
    const rollY = cy + s * 0.26; // the roll it is still wound on, at the foot
    rl.drawCircleV(v2(cx + 1.2 * k, rollY + 1.2 * k), hw * 1.02, rgba(0, 0, 0, 110));

    const tl = v2(cx - hw * 1.06 + lean, top);
    const tr = v2(cx + hw * 1.02 + lean, top + s * 0.02);
    quad(tl, tr, v2(cx + hw * 0.94, rollY), v2(cx - hw * 0.96, rollY), HIDE);
    arc(cx + lean, top + s * 0.03, hw * 1.02, std.math.pi * 1.04, std.math.tau - 0.06, 10, s * 0.055, s * 0.035, HIDE_LT);
    rl.drawLineEx(v2(cx - hw * 0.96, rollY), v2(cx - hw * 1.06 + lean, top), 1.2 * k, HIDE_LT); // the lit near edge

    glyphOn(cx, cy - s * 0.03, s, k, glyph);

    rl.drawLineEx(v2(cx - hw, rollY), v2(cx + hw, rollY), s * 0.17, HIDE_DK);
    rl.drawLineEx(v2(cx - hw, rollY - s * 0.03), v2(cx + hw, rollY - s * 0.03), s * 0.05, HIDE);
    rl.drawCircleV(v2(cx - hw, rollY), s * 0.085, HIDE_DK); // the two ends of the roll…
    rl.drawCircleV(v2(cx + hw, rollY), s * 0.085, HIDE_DK);
    rl.drawCircleV(v2(cx + hw, rollY), s * 0.042, rgba(84, 68, 46, 255)); // …and the hole down the near one
    rl.drawLineEx(v2(cx - s * 0.05, rollY - s * 0.10), v2(cx - s * 0.02, rollY + s * 0.09), 1.8 * k, CORD);
    rl.drawLineEx(v2(cx - s * 0.02, rollY + s * 0.09), v2(cx + s * 0.07, rollY + s * 0.13), 1.5 * k, CORD);
}

/// WHICH ANIMAL IS ON THE SHEET. Its own enum rather than `combat.SpiritKind` because `itemart` draws pictures
/// and must not import the rules — the binding is made once, at the `drawHeld` row.
const SpiritGlyph = enum { wolf };

/// THE DRAWING, IN ONE UNBROKEN LINE — which is the flavour and also the only thing legible at 34 px. A whole
/// body comes out as twelve pixels of mush, so what is inked is the HEAD IN PROFILE: muzzle, stop, pricked ear
/// and the nape running off the sheet. The ear is the read; without it this is a dog or a fox.
fn glyphOn(cx: f32, cy: f32, s: f32, k: f32, glyph: SpiritGlyph) void {
    switch (glyph) {
        .wolf => {
            const w = 2.0 * k;
            const nose = v2(cx - s * 0.115, cy + s * 0.045);
            const stop = v2(cx - s * 0.025, cy - s * 0.005); // where muzzle meets brow — a wolf's is shallow
            const brow = v2(cx + s * 0.025, cy - s * 0.055);
            const ear = v2(cx + s * 0.045, cy - s * 0.135); // pricked and set BACK, never on top of the skull
            const nape = v2(cx + s * 0.10, cy - s * 0.02);
            rl.drawLineEx(nose, stop, w, SPIRIT);
            rl.drawLineEx(stop, brow, w, SPIRIT);
            rl.drawLineEx(brow, ear, w, SPIRIT);
            rl.drawLineEx(ear, nape, w, SPIRIT);
            rl.drawLineEx(nose, v2(cx - s * 0.02, cy + s * 0.075), w * 0.85, SPIRIT);
            rl.drawLineEx(v2(cx - s * 0.02, cy + s * 0.075), v2(cx + s * 0.06, cy + s * 0.06), w * 0.85, SPIRIT);
            rl.drawCircleV(v2(cx - s * 0.115, cy + s * 0.045), w * 0.6, SPIRIT_LT); // the nose, blunt: nothing ends in a point
            rl.drawCircleV(v2(cx - s * 0.005, cy + s * 0.005), 1.3 * k, SPIRIT_LT); // and the eye it is looking at you with
        },
    }
}

/// A squat dollop of rendered fat round a wick, lit — the flame is the read, the drips are the wabi-sabi.
fn emberCandle(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xEB3A);
    const lean = rng.range(-1.2, 1.2) * k;
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.20 + 1.0 * k), s * 0.24, rgba(0, 0, 0, 120));
    rl.drawCircleV(v2(cx, cy + s * 0.20), s * 0.24, EMBER_FAT_DK); // the dollop, slumped
    rl.drawCircleV(v2(cx - s * 0.03, cy + s * 0.16), s * 0.20, EMBER_FAT);
    rl.drawLineEx(v2(cx + s * 0.14, cy + s * 0.12), v2(cx + s * 0.17 + lean, cy + s * 0.32), 2.6 * k, EMBER_FAT);
    rl.drawLineEx(v2(cx - s * 0.18, cy + s * 0.18), v2(cx - s * 0.19, cy + s * 0.33 + rng.range(0, 2) * k), 2.0 * k, EMBER_FAT_DK);
    rl.drawLineEx(v2(cx + lean, cy + s * 0.02), v2(cx + lean, cy - s * 0.10), 1.6 * k, IRON_DK); // the wick
    rl.drawCircleV(v2(cx + lean * 1.4, cy - s * 0.17), s * 0.085, FIRE_DIM);
    rl.drawCircleV(v2(cx + lean * 1.2, cy - s * 0.145), s * 0.05, FIRE);
    rl.drawCircleV(v2(cx + lean, cy - s * 0.12), s * 0.022, rgba(255, 236, 190, 255));
}

/// One dried cap, gills up-ended: the brick dome, the pale flecks, and the bite something regretted.
fn sporelingCap(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x5CA9);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + 1.2 * k), s * 0.30, rgba(0, 0, 0, 120));
    arc(cx, cy + s * 0.06, s * 0.28, std.math.pi, std.math.tau, 14, s * 0.34, s * 0.20, SHROOM_CAP);
    arc(cx, cy + s * 0.07, s * 0.29, std.math.pi * 1.06, std.math.pi * 1.94, 12, 2.4 * k, 2.0 * k, SHROOM_CAP_DK);
    rl.drawLineEx(v2(cx - s * 0.27, cy + s * 0.075), v2(cx + s * 0.27, cy + s * 0.065), 3.0 * k, SHROOM_CAP_DK);
    rl.drawLineEx(v2(cx - s * 0.20, cy + s * 0.13), v2(cx + s * 0.20, cy + s * 0.12), 2.2 * k, CAP_LT);
    var f: u32 = 0;
    while (f < 5) : (f += 1) { // the cream flecks, dealt
        const a = rng.range(std.math.pi * 1.15, std.math.pi * 1.85);
        const rr = rng.range(0.10, 0.24) * s;
        rl.drawCircleV(v2(cx + mathx.cosf(a) * rr, cy + s * 0.02 + mathx.sinf(a) * rr * 0.8), rng.range(1.2, 2.2) * k, SHROOM_CREAM);
    }
    rl.drawCircleV(v2(cx + s * 0.21, cy - s * 0.10), s * 0.06, rgba(30, 22, 20, 255));
    rl.drawCircleV(v2(cx + s * 0.17, cy - s * 0.075), 1.6 * k, CHAOS_DK);
}

/// A curl of pale bark and the breath it buys: two faint arcs of moving air off its lip.
fn secondWind(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.06 + 1.0 * k), s * 0.26, rgba(0, 0, 0, 110));
    arc(cx, cy + s * 0.04, s * 0.22, std.math.pi * 0.2, std.math.pi * 1.6, 14, s * 0.16, s * 0.10, BONE_DK);
    arc(cx, cy + s * 0.04, s * 0.22, std.math.pi * 0.25, std.math.pi * 1.5, 12, s * 0.10, s * 0.05, BONE);
    arc(cx + s * 0.06, cy + s * 0.02, s * 0.10, std.math.pi * 0.4, std.math.pi * 1.8, 10, s * 0.07, s * 0.03, BONE);
    rl.drawLineEx(v2(cx - s * 0.16, cy + s * 0.20), v2(cx - s * 0.02, cy + s * 0.24), 2.0 * k, CORD); // the tie
    // The wind itself, drawn the way the HUD draws nothing else: two pale streaks running OFF the curl.
    arc(cx + s * 0.16, cy - s * 0.14, s * 0.16, std.math.pi * 1.2, std.math.pi * 1.85, 8, 2.0 * k, 0.8 * k, rgba(238, 244, 248, 170));
    arc(cx + s * 0.20, cy - s * 0.02, s * 0.12, std.math.pi * 1.25, std.math.pi * 1.9, 8, 1.6 * k, 0.6 * k, rgba(238, 244, 248, 110));
}

/// A DOOR of a shield: planks, two iron bands, and the crack that names it.
fn towerShield(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    const hw = s * 0.20;
    const top = cy - s * 0.34;
    const bot = cy + s * 0.36;
    rl.drawCircleV(v2(cx + 1.2 * k, bot - s * 0.04), hw, rgba(0, 0, 0, 110));
    quad(v2(cx - hw, top + s * 0.06), v2(cx + hw, top + s * 0.06), v2(cx + hw * 0.86, bot), v2(cx - hw * 0.86, bot), GRIP);
    arc(cx, top + s * 0.07, hw, std.math.pi, std.math.tau, 10, s * 0.12, s * 0.12, GRIP); // the rounded head
    for ([_]f32{ -0.4, 0.2 }) |t| {
        rl.drawLineEx(v2(cx + hw * t, top + s * 0.02), v2(cx + hw * t * 0.86, bot - s * 0.01), 1.4 * k, BOARD_JOINT);
        rl.drawLineEx(v2(cx + hw * t + 1.2 * k, top + s * 0.02), v2(cx + hw * t * 0.86 + 1.2 * k, bot - s * 0.01), 0.8 * k, GRIP_LT);
    }
    for ([_]f32{ top + s * 0.16, bot - s * 0.14 }) |by| {
        rl.drawLineEx(v2(cx - hw, by), v2(cx + hw, by), 3.4 * k, IRON_DK);
        rl.drawCircleV(v2(cx - hw * 0.6, by), 1.3 * k, STEEL_DK);
        rl.drawCircleV(v2(cx + hw * 0.6, by), 1.3 * k, STEEL_DK);
    }
    // THE CRACK — through, corner to band, jagged where a straight line would be a scratch.
    rl.drawLineEx(v2(cx - hw * 0.2, top + s * 0.05), v2(cx + hw * 0.15, cy - s * 0.02), 1.8 * k, rgba(24, 16, 12, 255));
    rl.drawLineEx(v2(cx + hw * 0.15, cy - s * 0.02), v2(cx - hw * 0.1, cy + s * 0.16), 1.6 * k, rgba(24, 16, 12, 255));
    rl.drawLineEx(v2(cx - hw * 0.1, cy + s * 0.16), v2(cx + hw * 0.1, bot - s * 0.06), 1.2 * k, rgba(24, 16, 12, 255));
}

/// MOSTLY HEAD (the sword's own law, upside down): everything that says CLUB is the lumped end, so it is
/// drawn big and the haft runs off the bottom losing itself.
fn greatclub(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xC1B8);
    rl.drawCircleV(v2(cx + 1.4 * k, cy - s * 0.10 + 1.4 * k), s * 0.24, rgba(0, 0, 0, 120));
    rl.drawLineEx(v2(cx - s * 0.10, cy + s * 0.44), v2(cx + s * 0.02, cy - s * 0.02), s * 0.10, ROOT_BARK);
    rl.drawLineEx(v2(cx - s * 0.085, cy + s * 0.42), v2(cx + s * 0.005, cy + s * 0.06), 1.6 * k, rgba(30, 20, 14, 255)); // its grain
    rl.drawCircleV(v2(cx + s * 0.05, cy - s * 0.12), s * 0.20, ROOT_BARK);
    rl.drawCircleV(v2(cx + s * 0.14, cy - s * 0.20), s * 0.13, rgba(50, 36, 26, 255));
    rl.drawCircleV(v2(cx - s * 0.06, cy - s * 0.22), s * 0.11, rgba(46, 33, 24, 255));
    arc(cx + s * 0.05, cy - s * 0.13, s * 0.185, std.math.pi * 1.15, std.math.pi * 1.95, 10, 3.2 * k, 2.6 * k, IRON_DK);
    var st: u32 = 0;
    while (st < 4) : (st += 1) {
        const a = rng.range(std.math.pi * 1.2, std.math.pi * 1.9);
        rl.drawCircleV(v2(cx + s * 0.05 + mathx.cosf(a) * s * 0.185, cy - s * 0.13 + mathx.sinf(a) * s * 0.185), 1.4 * k, RUST);
    }
    rl.drawCircleV(v2(cx - s * 0.02, cy - s * 0.19), 2.0 * k, rgba(84, 64, 46, 255)); // one worn hight-light knot
}

/// A THIN GOLD BAND ALREADY CRACKED — the break is the picture, since breaking is the whole of what it does.
fn soulRing(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.03 + 1.0 * k), s * 0.21, rgba(0, 0, 0, 110));
    // The band, thin and even — a plain ring, so the CRACK is the only thing on it worth looking at.
    arc(cx, cy + s * 0.02, s * 0.175, 0, std.math.tau, 20, s * 0.048, s * 0.038, RING_GOLD);
    arc(cx - s * 0.05, cy - s * 0.02, s * 0.175, std.math.pi * 0.85, std.math.pi * 1.45, 8, 1.7 * k, 0.9 * k, RING_GOLD_LT);
    const bx = cx + s * 0.155;
    const by = cy - s * 0.06;
    rl.drawLineEx(v2(bx - s * 0.03, by + s * 0.04), v2(bx + s * 0.03, by - s * 0.04), 2.2 * k, rgba(26, 20, 12, 255));
    rl.drawLineEx(v2(bx - s * 0.035, by + s * 0.035), v2(bx - s * 0.008, by), 1.1 * k, RING_GOLD_LT);
    rl.drawCircleV(v2(cx, cy - s * 0.155), s * 0.062, RING_SOUL);
    rl.drawCircleV(v2(cx - s * 0.015, cy - s * 0.172), 1.3 * k, rgba(255, 246, 214, 235));
}

/// A ring of dark beak-horn with a bead of what it is for.
fn leechSignet(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.04 + 1.0 * k), s * 0.20, rgba(0, 0, 0, 110));
    arc(cx, cy + s * 0.04, s * 0.17, 0, std.math.tau, 18, s * 0.075, s * 0.05, rgba(44, 34, 30, 255)); // the band, thicker at the seat
    arc(cx - s * 0.04, cy, s * 0.16, std.math.pi * 0.9, std.math.pi * 1.5, 8, 1.6 * k, 0.8 * k, rgba(120, 104, 92, 255)); // horn sheen
    rl.drawCircleV(v2(cx, cy - s * 0.16), s * 0.075, CRIMSON); // the bead
    rl.drawCircleV(v2(cx - s * 0.02, cy - s * 0.18), 1.4 * k, rgba(255, 200, 190, 220)); // its gloss
    rl.drawCircleV(v2(cx, cy - s * 0.10), 1.6 * k, rgba(44, 34, 30, 255)); // the claw holding it
}

/// The candle's fat WITHOUT wick or flame — unlit on purpose: what it promises burns on the sword, not in
/// the bag. An open twist of cloth with the fat slumped proud of it.
fn fireTallow(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xFA77);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.12 + 1.2 * k), s * 0.25, rgba(0, 0, 0, 115));
    quad(v2(cx - s * 0.23, cy + s * 0.02), v2(cx + s * 0.22, cy + s * 0.05), v2(cx + s * 0.15, cy + s * 0.30), v2(cx - s * 0.17, cy + s * 0.27), SALT);
    rl.drawLineEx(v2(cx - s * 0.23, cy + s * 0.04), v2(cx - s * 0.33, cy - s * 0.04), 3.4 * k, CORD);
    rl.drawLineEx(v2(cx - s * 0.05, cy + s * 0.10), v2(cx - s * 0.10, cy + s * 0.24), 1.0 * k, rgba(190, 172, 138, 255)); // one fold
    rl.drawCircleV(v2(cx - s * 0.02, cy - s * 0.03), s * 0.165, EMBER_FAT);
    rl.drawCircleV(v2(cx + s * 0.11 + rng.range(-1.2, 1.2) * k, cy + s * 0.01), s * 0.115, EMBER_FAT_DK);
    rl.drawCircleV(v2(cx - s * 0.09, cy - s * 0.08), s * 0.05, rgba(246, 222, 164, 255));
    // …and one run of it down the cloth: it is going to end up on an edge anyway.
    rl.drawLineEx(v2(cx + s * 0.05, cy + s * 0.08), v2(cx + s * 0.07 + rng.range(0, 2) * k, cy + s * 0.25), 2.2 * k, EMBER_FAT_DK);
}

/// A squat clay jar, corked, the spark already showing at a crack in the belly — the same LIGHTNING pale
/// its trail flies (`archer.TRAIL_CROCK`'s read), which nothing else in the bag or the sky is.
fn thundercrock(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x7C0C);
    const clay = rgba(118, 76, 50, 255);
    const clayDk = rgba(80, 52, 34, 255);
    const lean = rng.range(-1.4, 1.4) * k;
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.09 + 1.2 * k), s * 0.25, rgba(0, 0, 0, 120));
    rl.drawCircleV(v2(cx, cy + s * 0.08), s * 0.245, clay); // the belly
    rl.drawCircleV(v2(cx - s * 0.07, cy + s * 0.02), s * 0.15, rgba(142, 96, 64, 255)); // thrown-pot sheen
    quad(v2(cx - s * 0.09 + lean, cy - s * 0.21), v2(cx + s * 0.09 + lean, cy - s * 0.21), v2(cx + s * 0.07, cy - s * 0.07), v2(cx - s * 0.07, cy - s * 0.07), clayDk); // the neck, off plumb
    rl.drawCircleV(v2(cx + lean, cy - s * 0.22), s * 0.07, CORK);
    // THE CRACK, AND THE SKY'S OWN SPARK IN IT — the read of the whole item, so it is drawn HOT (a pale blue
    // jag on brown clay is a hairline) and it BREAKS THE RIM at both ends, which says a thing is escaping
    // rather than a pot is chipped. SIZED BETWEEN TWO FAILURES: wide enough to read, but inside the belly,
    // or it hides the jar it exists to point at.
    const jag = [_]rl.Vector2{
        v2(cx - s * 0.27, cy + s * 0.01),
        v2(cx - s * 0.11, cy + s * 0.09),
        v2(cx - s * 0.01, cy + s * 0.03),
        v2(cx + s * 0.07, cy + s * 0.15),
        v2(cx + s * 0.26, cy + s * 0.09),
    };
    for (0..jag.len - 1) |i| {
        const w = mathx.lerpF(3.0, 1.8, @as(f32, @floatFromInt(i)) / 3.0) * k;
        rl.drawLineEx(jag[i], jag[i + 1], w, SPARK); // the cool outer body of the bolt…
        rl.drawLineEx(jag[i], jag[i + 1], w * 0.40, rgba(252, 254, 255, 255)); // …and the white heart in it
    }
    // The glare where it is coming through the shell, kept under the neck so the jar keeps its silhouette.
    rl.drawCircleV(jag[2], s * 0.038, rgba(232, 246, 255, 120));
    rl.drawCircleV(jag[2], s * 0.018, rgba(255, 255, 255, 235));
}

/// TWO HALVES OF ONE RUNE PARTED A HAIR, the light getting out of the split. Kin to the Rune Arc's gilt —
/// this is the currency itself, so the split carries the pale core the arc wears as a band.
fn crackedSoul(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xC4AC);
    // ONE STONE WITH A BREAK THROUGH IT, not two halves side by side: as a pair of upright slabs with a
    // lit gutter between them it read as an open BOOK, which is the shape any two equal panels make.
    const hw = s * 0.19;
    const shy = s * 0.17; // where the sides turn — the tablet's shoulders
    const top = cy - s * 0.32;
    const bot = cy + s * 0.30;
    const slip = s * 0.028; // how far the right half has slid down its own crack
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.04 + 1.2 * k), s * 0.26, rgba(0, 0, 0, 120));
    // Each half is a quad down the seam — apex, shoulder, shoulder, apex — so neither is a rectangle.
    quad(v2(cx, top), v2(cx, bot), v2(cx - hw, cy + shy), v2(cx - hw, cy - shy), rgba(0, 0, 0, 170));
    quad(v2(cx, top + slip), v2(cx, bot + slip), v2(cx + hw, cy + shy + slip), v2(cx + hw, cy - shy + slip), rgba(0, 0, 0, 170));
    quad(v2(cx - 0.8 * k, top), v2(cx - 0.8 * k, bot), v2(cx - hw + 1.4 * k, cy + shy), v2(cx - hw + 1.4 * k, cy - shy), uiart.GILT_DIM);
    quad(v2(cx + 0.8 * k, top + slip), v2(cx + 0.8 * k, bot + slip), v2(cx + hw - 1.4 * k, cy + shy + slip), v2(cx + hw - 1.4 * k, cy - shy + slip), uiart.GILT);
    // The lit bevels off the two upper edges — struck metal, not parchment.
    rl.drawLineEx(v2(cx - 0.8 * k, top), v2(cx - hw + 1.4 * k, cy - shy), 1.3 * k, uiart.GILT_BRIGHT);
    rl.drawLineEx(v2(cx + 0.8 * k, top + slip), v2(cx + hw - 1.4 * k, cy - shy + slip), 1.3 * k, uiart.GILT_BRIGHT);
    // THE RUNE CUT INTO THE FACE — half the mark on each half, which is what says a soul broke and not a
    // coin. Dark, because a groove is a shadow.
    const groove = rgba(92, 66, 20, 235);
    rl.drawLineEx(v2(cx - hw * 0.72, cy - s * 0.10), v2(cx - 1.5 * k, cy - s * 0.17), 1.7 * k, groove);
    rl.drawLineEx(v2(cx - hw * 0.62, cy + s * 0.15), v2(cx - hw * 0.62, cy - s * 0.06), 1.7 * k, groove);
    rl.drawLineEx(v2(cx + 1.5 * k, cy - s * 0.16 + slip), v2(cx + hw * 0.74, cy - s * 0.01 + slip), 1.7 * k, groove);
    rl.drawLineEx(v2(cx + hw * 0.74, cy - s * 0.01 + slip), v2(cx + hw * 0.40, cy + s * 0.16 + slip), 1.7 * k, groove);
    // THE LIGHT GETTING OUT OF THE BREAK, and it is a JAG rather than a gutter — a straight bright band
    // between two panels is a spine, and a spine is a book.
    const seam = [_]rl.Vector2{
        v2(cx + 1.0 * k, top + s * 0.03),
        v2(cx - 1.6 * k, cy - s * 0.11),
        v2(cx + 2.0 * k, cy + s * 0.02),
        v2(cx - 1.0 * k, bot - s * 0.03),
    };
    for (0..seam.len - 1) |i| {
        rl.drawLineEx(seam[i], seam[i + 1], 2.6 * k, rgba(255, 240, 196, 210));
        rl.drawLineEx(seam[i], seam[i + 1], 1.1 * k, rgba(255, 254, 240, 250));
    }
    rl.drawCircleV(seam[2], 2.6 * k, rgba(255, 254, 244, 255)); // the hot point at the widest of it
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        rl.drawCircleV(v2(cx + rng.range(-0.08, 0.08) * s, cy + rng.range(-0.36, -0.12) * s), rng.range(0.6, 1.2) * k, rgba(255, 232, 176, 200));
    }
}

/// The skin it cooked in: a sagging waterskin tied at the neck over a bone toggle. Leather and bone say
/// FOOD OFF A CAMPFIRE, and nothing about it glows — it is soup.
fn toadfleshBroth(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x70AD);
    const sag = rng.range(0, 1.6) * k;
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.12 + 1.2 * k), s * 0.24, rgba(0, 0, 0, 115));
    // The body: two lobes, fuller on one side — a skin sags where the weight went.
    rl.drawCircleV(v2(cx - s * 0.04, cy + s * 0.12 + sag), s * 0.21, GRIP);
    rl.drawCircleV(v2(cx + s * 0.10, cy + s * 0.08), s * 0.16, GRIP);
    rl.drawCircleV(v2(cx - s * 0.09, cy + s * 0.05), s * 0.11, GRIP_LT); // the swell catching light
    quad(v2(cx - s * 0.045, cy - s * 0.18), v2(cx + s * 0.045, cy - s * 0.18), v2(cx + s * 0.06, cy - s * 0.02), v2(cx - s * 0.06, cy - s * 0.02), BOARD_JOINT);
    rl.drawLineEx(v2(cx - s * 0.08, cy - s * 0.10), v2(cx + s * 0.08, cy - s * 0.12), 2.6 * k, CORD);
    rl.drawLineEx(v2(cx - s * 0.11, cy - s * 0.20), v2(cx + s * 0.11, cy - s * 0.22), 3.0 * k, BONE); // the toggle
    rl.drawCircleV(v2(cx + s * 0.11, cy - s * 0.22), 1.5 * k, BONE_DK); // its cut end
    rl.drawCircleV(v2(cx + s * 0.02, cy - s * 0.155), 1.4 * k, SALT);
}

/// THE KOBOLD FANG AS A BLADE — the tooth's own quadratic curve (`koboldFang`'s construction), ground to a
/// lit edge and hafted in cord. Bone, not steel: what it is made of is the whole item.
fn fangDirk(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xD1FA);
    const rootP = v2(cx - s * 0.10, cy + s * 0.14); // where blade meets haft
    const tipP = v2(cx + s * 0.24, cy - s * 0.34);
    const bend = rng.range(0.12, 0.18);
    const SEGS = 12;
    var prev = rootP;
    for (0..SEGS + 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / SEGS;
        const p = onAxis(rootP, tipP, t, -bend * s * (4.0 * t * (1.0 - t)));
        const w = mathx.lerpF(5.2, 0.5, t * t * 0.85 + t * 0.15) * k;
        if (i > 0) rl.drawLineEx(prev, p, w, mathx.lerpColor(BONE_DK, BONE, mathx.clampF(t * 1.25, 0, 1)));
        prev = p;
    }
    // The GROUND EDGE along the hollow of the curve — brighter than any tooth, which is what says dirk.
    rl.drawLineEx(onAxis(rootP, tipP, 0.15, 1.2 * k), onAxis(rootP, tipP, 0.88, 0.3 * k), 1.1 * k, rgba(255, 252, 240, 220));
    const buttP = v2(cx - s * 0.24, cy + s * 0.30);
    rl.drawLineEx(rootP, buttP, 5.0 * k, GRIP);
    rl.drawCircleV(v2(rootP.x, rootP.y), 3.2 * k, IRON_DK);
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const t = 0.25 + 0.25 * @as(f32, @floatFromInt(i)) + rng.range(-0.03, 0.03);
        rl.drawLineEx(onAxis(rootP, buttP, t, -3.0 * k), onAxis(rootP, buttP, t + 0.07, 3.0 * k), 1.5 * k, CORD);
    }
    rl.drawCircleV(buttP, 2.4 * k, GRIP_LT); // the pommel-less butt, just leather over bone
}

/// TWICE THE SKELETONS' TIMBER: a stave of grave-oak, iron-shod, strung. Darker and thicker than any bow
/// this HUD has drawn, and the string runs the chord to say it is a bow and not a stick.
fn graveWarbow(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x6B0B);
    const top = v2(cx + s * 0.16, cy - s * 0.36);
    const bot = v2(cx - s * 0.14 + rng.range(-1.2, 1.2) * k, cy + s * 0.37);
    const belly = rng.range(0.16, 0.20);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.06 + 1.4 * k), s * 0.22, rgba(0, 0, 0, 100));
    const SEGS = 14;
    var prev = top;
    for (0..SEGS + 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / SEGS;
        const p = onAxis(top, bot, t, -belly * s * (4.0 * t * (1.0 - t)));
        const w = mathx.lerpF(2.6, 6.0, 4.0 * t * (1.0 - t)) * k;
        if (i > 0) rl.drawLineEx(prev, p, w, ROOT_BARK);
        prev = p;
    }
    rl.drawLineEx(onAxis(top, bot, 0.22, -belly * s * 0.75), onAxis(top, bot, 0.78, -belly * s * 0.72), 1.2 * k, rgba(110, 82, 54, 255));
    rl.drawLineEx(onAxis(top, bot, 0.44, -belly * s * 1.02), onAxis(top, bot, 0.56, -belly * s * 1.00), 6.8 * k, GRIP);
    // Iron shoes on both tips — the fittings of a weapon, not a hunting stick.
    for ([_]rl.Vector2{ top, bot }) |p| rl.drawCircleV(p, 2.2 * k, IRON_DK);
    rl.drawLineEx(top, bot, 1.0 * k, BOWSTRING); // the string, dead straight down the chord
}

/// A COAT OFF ITS WEARER: box body, stub sleeves, the diamond stitching that names it — and the stain
/// nobody asked about, because "stained by whoever wore it last" is the description's own second sentence.
fn quiltedGambeson(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x6A3B);
    const linen = rgba(184, 168, 136, 255);
    const linenDk = rgba(140, 126, 100, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.08 + 1.4 * k), s * 0.26, rgba(0, 0, 0, 110));
    // Sleeves first so the body sits OVER their roots.
    quad(v2(cx - s * 0.20, cy - s * 0.18), v2(cx - s * 0.34, cy - s * 0.02), v2(cx - s * 0.26, cy + s * 0.06), v2(cx - s * 0.14, cy - s * 0.06), linenDk);
    quad(v2(cx + s * 0.20, cy - s * 0.18), v2(cx + s * 0.34, cy - s * 0.04), v2(cx + s * 0.27, cy + s * 0.05), v2(cx + s * 0.14, cy - s * 0.06), linenDk);
    quad(v2(cx - s * 0.19, cy - s * 0.22), v2(cx + s * 0.19, cy - s * 0.22), v2(cx + s * 0.17, cy + s * 0.32), v2(cx - s * 0.16, cy + s * 0.30 + rng.range(0, 2) * k), linen);
    quad(v2(cx - s * 0.06, cy - s * 0.22), v2(cx + s * 0.06, cy - s * 0.22), v2(cx + s * 0.01, cy - s * 0.10), v2(cx - s * 0.01, cy - s * 0.10), rgba(56, 44, 34, 255));
    // THE QUILTING: a diamond lattice, and every endpoint is solved INSIDE the body — run off a stepped
    // key it walked out of the coat and out of the bag cell with it.
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const yc = cy - s * 0.10 + @as(f32, @floatFromInt(i)) * s * 0.10 + rng.range(-0.012, 0.012) * s;
        rl.drawLineEx(v2(cx - s * 0.17, yc - s * 0.07), v2(cx + s * 0.17, yc + s * 0.07), 0.9 * k, linenDk);
        rl.drawLineEx(v2(cx - s * 0.17, yc + s * 0.07), v2(cx + s * 0.17, yc - s * 0.07), 0.9 * k, linenDk);
    }
    rl.drawCircleV(v2(cx + s * 0.08, cy + s * 0.20), s * 0.075, rgba(96, 62, 48, 170)); // the stain, low and old
    rl.drawCircleV(v2(cx + s * 0.12, cy + s * 0.24), s * 0.045, rgba(96, 62, 48, 140));
}

pub fn flask(cx: f32, cy: f32, px: f32, tint: FlaskTint, full: bool) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xF1A5C);
    const lit = switch (tint) {
        .crimson => CRIMSON,
        .cerulean => CERULEAN,
    };
    const dk = switch (tint) {
        .crimson => CRIMSON_DK,
        .cerulean => CERULEAN_DK,
    };
    const fill = if (full) lit else rgba(dk.r, dk.g, dk.b, 150);
    const deep = if (full) rgba(dk.r, dk.g, dk.b, 255) else rgba(dk.r, dk.g, dk.b, 120);
    const body = s * 0.265; // half-width of the bulb — narrowed, so the silhouette is a FLASK not a ball
    const bodyY = cy + s * 0.13;
    // The whole flask leans: hand-blown glass does not stand plumb, and nor does the way it is carried.
    const lean = rng.range(-0.9, 0.9) * k;

    rl.drawCircleV(v2(cx + 1.0 * k, bodyY + 1.1 * k), body, rgba(0, 0, 0, 120)); // off the plate
    // THE BULB, SHADED FROM THE DARK SIDE OUT: the deep tone is the whole ball and the lit fill is a slightly
    // smaller one set up and left inside it, so what shows of the deep is a crescent along the bottom-right
    // rim. THERE IS NO CLIPPING HERE — a concentric dark circle is a bubble, a sector cuts the flask in half,
    // and a big offset circle spills its far side across the HUD and the world behind it.
    rl.drawCircleV(v2(cx, bodyY), body, deep);
    rl.drawCircleV(v2(cx - body * 0.11, bodyY - body * 0.13), body * 0.90, fill);
    // THE SHOULDERS as a taper up to the neck. A rounded BOX here (the first pass) pokes its corners out
    // past the bulb's arc and reads as a flange bolted to the glass; a shoulder is a cone.
    const neckHalf = s * 0.062;
    const shoulderY = bodyY - body * 0.42;
    quad(
        v2(cx + lean * 0.5 - neckHalf, cy + s * 0.015),
        v2(cx + lean * 0.5 + neckHalf, cy + s * 0.015),
        v2(cx + body * 0.88, shoulderY),
        v2(cx - body * 0.88, shoulderY),
        fill,
    );
    rl.drawLineEx(v2(cx + lean * 0.4, cy + s * 0.02), v2(cx + lean, cy - s * 0.31), neckHalf * 2.0, fill);
    rl.drawLineEx(v2(cx + lean - s * 0.070, cy - s * 0.295), v2(cx + lean + s * 0.070, cy - s * 0.295), 2.0 * k, deep);
    // THE LIQUID LINE sits DOWN IN THE BULB and stops short of the left, because the specular runs there:
    // laid across the shoulder and full width, the two of them crossed and read as a label on the glass.
    if (full) {
        rl.drawLineEx(
            v2(cx - body * 0.20, bodyY - body * 0.60),
            v2(cx + body * 0.72, bodyY - body * 0.68),
            1.4 * k,
            rgba(255, 255, 255, 80),
        );
    }
    // THE SPECULAR: one long streak down the left shoulder of the bulb, and nothing on the neck (a second
    // highlight there made a cross with the liquid line).
    rl.drawLineEx(
        v2(cx - body * 0.52, bodyY - body * 0.62),
        v2(cx - body * 0.66, bodyY + body * 0.28),
        2.0 * k,
        rgba(GLASS_LIT.r, GLASS_LIT.g, GLASS_LIT.b, if (full) 200 else 90),
    );

    const sx = cx + lean * 1.15;
    rl.drawRectangleV(v2(sx - s * 0.062, cy - s * 0.395), v2(s * 0.124, s * 0.105), CORK);
    rl.drawCircleV(v2(sx, cy - s * 0.335), s * 0.075, WAX);
    rl.drawCircleV(v2(sx + rng.range(-0.6, 0.6) * s * 0.05, cy - s * 0.30), s * 0.048, WAX); // the run
    rl.drawCircleV(v2(sx - 1.2 * k, cy - s * 0.355), 1.0 * k, rgba(255, 210, 190, 120)); // its gloss
    const ty = cy - s * 0.245;
    rl.drawLineEx(v2(sx - s * 0.075, ty), v2(sx + s * 0.075, ty - 0.6 * k), 1.4 * k, CORD);
    rl.drawLineEx(
        v2(sx + s * 0.055, ty),
        v2(sx + s * 0.055 + rng.range(1.4, 3.0) * k, ty + rng.range(1.6, 3.4) * k),
        1.0 * k,
        CORD,
    );
}

/// ELDEN RING'S OWN PATTERN, and the owner's call: MOSTLY HILT, AND THE BLADE FADES OUT. A whole sword scaled
/// to fit a 44×60 socket is a dagger, because everything that says LONG about a longsword is the part there
/// is no room for. So the hilt is drawn big and the steel runs off the top, which reads as a blade continuing.
pub fn sword(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x5B1AD3);
    const d = s * 0.72; // …and the blade's end is the FRAME, which is what says it carries on past it
    const u = 0.70711; // the diagonal axis, pommel-ward…
    // The whole sword leans a degree or so off the true diagonal: nothing forged is square to a grid.
    const lean = rng.range(-0.035, 0.035);
    // NOT a tip: where the steel has faded to nothing. The blade has no point in this picture.
    const gone = v2(cx - u * d * (1.0 + lean), cy - u * d * (1.0 - lean));
    // THE POMMEL HAS TO FIT ITS OWN SOCKET, and off the diagonal that is not free: at the shipped 150%
    // equipment scale the obvious 0.92 of the axis put its far side 3 px out over the rim. Held in off
    // the wheel's own radius, so it cannot spill again at whatever scale the picture is next drawn at.
    const pomR = 2.7 * k;
    const pomOut = @min(u * d * 0.92, s * 0.5 - pomR - 1.5 * k);
    const pom = v2(cx + pomOut, cy + pomOut);
    const guard = onAxis(gone, pom, 0.60, 0); // the hilt: the bottom 40%, drawn big and jewelled
    const shoulder = onAxis(gone, pom, 0.565, 0); // where the blade meets the guard

    // THE BLADE: a stack of segments losing alpha as it climbs, because raylib's 2D triangles are flat and
    // a gradient is the only thing that says "this goes on past the frame". Widest at the shoulder, and it
    // does NOT taper to a point — a taper plus a fade reads as a blade that broke.
    const wBase = 2.7 * k; // a LONGSWORD: any wider over this length and it reads as a cleaver
    const wFar = 2.1 * k;
    const SEGS = 18;
    const runTo = 0.565; // the blade's whole run, as a fraction of the frame's diagonal…
    const FADE_FROM = 0.28; // …SOLID for this much of it, then losing itself into the corner. Faded from
    // the GUARD outward instead — which is how the first pass went in — a longsword reads as a lit stub.
    for (0..SEGS) |i| {
        const t0 = @as(f32, @floatFromInt(i)) / SEGS; // 0 AT THE GUARD, 1 where the steel has gone
        const t1 = @as(f32, @floatFromInt(i + 1)) / SEGS;
        const w0 = mathx.lerpF(wBase, wFar, t0);
        const w1 = mathx.lerpF(wBase, wFar, t1);
        const col = mathx.withAlpha(STEEL_MID, mathx.u8f(255.0 * (1.0 - mathx.smoothstep(FADE_FROM, 1.0, (t0 + t1) * 0.5))));
        quad(
            onAxis(gone, pom, runTo * (1.0 - t1), w1),
            onAxis(gone, pom, runTo * (1.0 - t0), w0),
            onAxis(gone, pom, runTo * (1.0 - t0), -w0),
            onAxis(gone, pom, runTo * (1.0 - t1), -w1),
            col,
        );
    }
    const solid = runTo * (1.0 - FADE_FROM); // the near end of the fade: no detail survives past it
    rl.drawLineEx(onAxis(gone, pom, solid + 0.01, 0), onAxis(shoulder, pom, -0.02, 0), 1.1 * k, rgba(64, 68, 74, 170));
    rl.drawLineEx(onAxis(gone, pom, solid, -wBase * 0.84), onAxis(shoulder, pom, 0, -wBase * 0.88), 1.1 * k, mathx.withAlpha(STEEL, 215));
    rl.drawLineEx(onAxis(gone, pom, solid, wBase * 0.84), onAxis(shoulder, pom, 0, wBase * 0.88), 0.9 * k, rgba(88, 92, 98, 180));
    // A NICK, low on the edge where the steel is still opaque — up in the fade it is invisible anyway.
    const nickAt = rng.range(0.33, 0.43);
    rl.drawTriangle(
        onAxis(gone, pom, nickAt, -wBase * 0.72),
        onAxis(gone, pom, nickAt + 0.022, -wBase * 0.26),
        onAxis(gone, pom, nickAt - 0.016, -wBase * 0.26),
        rgba(20, 18, 16, 190),
    );

    // THE GRIP: a leather core with unevenly spaced wrap turns over it — hairline, or they read as segments
    // of a rod rather than as cord over leather. It is the LONG grip of a weapon held in two hands.
    rl.drawLineEx(guard, pom, 3.2 * k, GRIP);
    var band: f32 = 0.14;
    while (band < 0.88) : (band += rng.range(0.16, 0.24)) {
        const c = onAxis(guard, pom, band, 0);
        rl.drawLineEx(
            v2(c.x + u * 1.55 * k, c.y - u * 1.55 * k),
            v2(c.x - u * 1.55 * k, c.y + u * 1.55 * k),
            0.7 * k,
            rgba(66, 48, 33, 230),
        );
    }

    // THE CROSSGUARD — two arms of different length, and WIDE now that it is the read: the hilt is what
    // this picture is of. The first pass ran it at 0.215·s and 2.9 px, which is a warhammer's head.
    const q = s * 0.17;
    for ([_]f32{ -1, 1 }) |side| {
        const armLen = q * rng.range(0.84, 1.08);
        const droop = -side * 0.9 * k; // both arms sweep the same way about the axis
        const outer = v2(guard.x + side * u * armLen + u * droop, guard.y - side * u * armLen + u * droop);
        rl.drawLineEx(guard, outer, 2.1 * k, BRASS);
        rl.drawCircleV(outer, 1.15 * k, uiart.GILT);
    }
    rl.drawCircleV(guard, 1.35 * k, uiart.GILT); // the block the arms leave from

    rl.drawCircleV(v2(pom.x + 0.6 * k, pom.y + 0.7 * k), pomR, rgba(0, 0, 0, 150));
    rl.drawCircleV(pom, pomR, BRASS);
    rl.drawCircleV(v2(pom.x - 0.8 * k, pom.y - 0.9 * k), 1.1 * k, uiart.GILT_BRIGHT);
}

pub fn bow(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xB0FF12);
    const d = s * 0.55;
    const u = 0.70711;
    // THE UPPER LIMB IS THE LONGER ONE. That is true of every real bow (the grip sits above centre so the
    // arrow can pass through it) and it is the cheapest honest asymmetry in the whole set.
    const upper = d * 1.06;
    const lower = d * 0.90;
    const tx = cx - u * upper;
    const ty = cy - u * upper;
    const bx = cx + u * lower;
    const by = cy + u * lower;
    const belly = s * 0.17; // how far the grip stands off the string line, across the axis
    const mx = cx - u * belly;
    const my = cy + u * belly;

    for ([_][3]f32{ .{ tx, ty, 1 }, .{ bx, by, -1 } }) |limb| {
        const tip = v2(limb[0], limb[1]);
        const grip = v2(mx, my);
        const bend = rng.range(0.28, 0.40);
        const knee = onAxis(grip, tip, 0.52, -belly * bend);
        const outer = onAxis(grip, tip, 0.84, -belly * bend * 0.55);
        rl.drawLineEx(grip, knee, 3.5 * k, BOWWOOD);
        rl.drawLineEx(knee, outer, 2.7 * k, BOWWOOD);
        rl.drawLineEx(outer, tip, 2.0 * k, BOWWOOD); // the recurve, thinnest at the tip…
        rl.drawLineEx(onAxis(grip, knee, 0.25, -1.1 * k), onAxis(knee, outer, 0.7, -0.9 * k), 0.9 * k, BOWWOOD_LT);
        rl.drawCircleV(tip, 1.7 * k, BOWNOCK);
        rl.drawCircleV(v2(tip.x - 0.4 * k, tip.y - 0.5 * k), 0.7 * k, uiart.CATCH);
    }

    rl.drawLineEx(v2(mx - u * s * 0.075, my - u * s * 0.075), v2(mx + u * s * 0.085, my + u * s * 0.085), 4.4 * k, GRIP);
    for ([_]f32{ rng.range(0.22, 0.38), rng.range(0.62, 0.80) }) |f| {
        const p = onAxis(v2(mx - u * s * 0.075, my - u * s * 0.075), v2(mx + u * s * 0.085, my + u * s * 0.085), f, 0);
        rl.drawLineEx(v2(p.x - u * 2.2 * k, p.y + u * 2.2 * k), v2(p.x + u * 2.2 * k, p.y - u * 2.2 * k), 1.0 * k, CORD);
    }

    rl.drawLineEx(v2(tx, ty), v2(bx, by), 1.2 * k, BOWSTRING);
    const serveA = onAxis(v2(tx, ty), v2(bx, by), 0.44, 0);
    const serveB = onAxis(v2(tx, ty), v2(bx, by), 0.58, 0);
    rl.drawLineEx(serveA, serveB, 2.0 * k, CORD);
}

pub fn shield(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x5C1E1D);
    const c = v2(cx, cy);
    const r = s * 0.40; // ~80% of the box's width, matching the sword's own fill
    const boards = r - 2.6 * k;

    // THE BINDING is a 17-GON, not a circle: this thing was hammered round a wooden disc by hand, and a
    // perfect circle is the one shape that says machine. 17 sides at a lazy rotation is round at a glance
    // and hand-cut when you look.
    rl.drawCircleV(v2(cx + 0.8 * k, cy + 1.0 * k), r, rgba(0, 0, 0, 130)); // it sits off the plate
    rl.drawPoly(c, 17, r, rng.range(0, 20), STEEL_DK);
    rl.drawPoly(c, 17, boards, rng.range(0, 20), GRIP);

    // THE BOARDS: three planks of UNEQUAL width, so the joints are not a symmetric pair.
    const j1 = rng.range(-0.50, -0.30);
    const j2 = rng.range(0.24, 0.46);
    for ([_]f32{ j1, j2 }) |f| {
        const dy = boards * f;
        const half = @sqrt(@max(boards * boards - dy * dy, 1.0));
        rl.drawLineEx(v2(cx - half, cy + dy), v2(cx + half, cy + dy), 1.7 * k, BOARD_JOINT);
        // …and a lit lip under each joint, which is what makes them read as EDGES rather than as lines.
        rl.drawLineEx(
            v2(cx - half * 0.94, cy + dy + 1.2 * k),
            v2(cx + half * 0.94, cy + dy + 1.2 * k),
            0.8 * k,
            rgba(GRIP_LT.r, GRIP_LT.g, GRIP_LT.b, 150),
        );
    }
    var gi: u32 = 0;
    while (gi < 5) : (gi += 1) {
        const gy = boards * rng.range(-0.78, 0.78);
        const half = @sqrt(@max(boards * boards - gy * gy, 1.0)) * rng.range(0.35, 0.8);
        const x0 = cx + rng.range(-0.4, 0.4) * half;
        rl.drawLineEx(
            v2(x0 - half * 0.5, cy + gy),
            v2(x0 + half * 0.5, cy + gy),
            0.7 * k,
            rgba(BOARD_JOINT.r, BOARD_JOINT.g, BOARD_JOINT.b, 110),
        );
    }

    // RIVETS round the binding — FIVE, unevenly spaced, and one of them has been lost.
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        if (i == 3) continue; // the missing one
        const a = std.math.tau * (@as(f32, @floatFromInt(i)) / 5.0) + rng.range(-0.22, 0.22);
        const rr = r - 1.4 * k;
        const p = v2(cx + mathx.cosf(a) * rr, cy + mathx.sinf(a) * rr);
        rl.drawCircleV(p, 1.35 * k, STEEL);
        rl.drawCircleV(v2(p.x - 0.4 * k, p.y - 0.5 * k), 0.6 * k, uiart.CATCH);
    }

    const bx = cx + rng.range(-1.2, 1.2) * k;
    const by = cy + rng.range(-1.2, 1.2) * k;
    const br = s * 0.125;
    rl.drawCircleV(v2(bx + 0.7 * k, by + 0.9 * k), br, rgba(0, 0, 0, 160));
    rl.drawCircleV(v2(bx, by), br, STEEL_DK);
    rl.drawCircleV(v2(bx - 0.6 * k, by - 0.7 * k), br - 2.0 * k, STEEL);
    rl.drawCircleV(v2(bx - 1.5 * k, by - 1.7 * k), br * 0.30, uiart.CATCH);
}

/// THE WAND — the rod on the diagonal every other armament here uses, with the stone at its high end. The
/// stone is a LIT CORE inside a cooler shell, the flask's trick for the flask's reason: there is no clipping
/// in this set, so anything that glows is built out of stacked shapes rather than a gradient.
pub fn wand(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x7A4D91);
    const u = 0.70711;
    const d = s * 0.36;
    // NOTHING DEAD IS STRAIGHT — the rod is three lengths with a knee in each, not one line.
    const butt = v2(cx + u * d, cy + u * d);
    const head = v2(cx - u * d * 1.02, cy - u * d * 1.02);
    const kneeA = onAxis(butt, head, 0.36, s * rng.range(0.014, 0.026));
    const kneeB = onAxis(butt, head, 0.70, s * rng.range(-0.024, -0.012));
    rl.drawLineEx(v2(butt.x + 0.9 * k, butt.y + 1.1 * k), v2(head.x + 0.9 * k, head.y + 1.1 * k), 3.4 * k, rgba(0, 0, 0, 120));
    rl.drawLineEx(butt, kneeA, 3.6 * k, GRIP);
    rl.drawLineEx(kneeA, kneeB, 3.0 * k, BOWWOOD);
    rl.drawLineEx(kneeB, head, 2.4 * k, BOWWOOD);
    // the lit BACK of the rod, the bow limb's own read
    rl.drawLineEx(onAxis(butt, kneeA, 0.2, -1.1 * k), onAxis(kneeB, head, 0.7, -0.9 * k), 0.8 * k, BOWWOOD_LT);
    // THE BOUND GRIP: uneven turns of cord over the butt end.
    for ([_]f32{ rng.range(0.06, 0.14), rng.range(0.19, 0.27), rng.range(0.30, 0.36) }) |f| {
        const p = onAxis(butt, head, f, 0);
        rl.drawLineEx(v2(p.x - u * 2.4 * k, p.y + u * 2.4 * k), v2(p.x + u * 2.4 * k, p.y - u * 2.4 * k), 1.1 * k, CORD);
    }
    // The ferrule, then the claws, then the stone standing in them.
    const neck = onAxis(butt, head, 0.80, 0);
    rl.drawLineEx(onAxis(butt, head, 0.74, 0), neck, 3.8 * k, STEEL_DK);
    const sr = s * 0.115;
    for ([_]f32{ -1, 1 }) |side| {
        rl.drawLineEx(neck, v2(head.x + side * u * sr * 0.95, head.y + side * u * sr * -0.95), 1.5 * k, STEEL_DK);
    }
    rl.drawCircleV(v2(head.x + 0.7 * k, head.y + 0.9 * k), sr, rgba(0, 0, 0, 140));
    rl.drawCircleV(head, sr, CHAOS_DK); // the DARK tone at full size…
    rl.drawCircleV(v2(head.x - 0.9 * k, head.y - 1.0 * k), sr - 1.8 * k, CHAOS); // …with the lit fill inset up-left inside it
    rl.drawCircleV(v2(head.x - 1.5 * k, head.y - 1.7 * k), sr * 0.34, CHAOS_LT);
    rl.drawCircleV(v2(head.x - 1.9 * k, head.y - 2.1 * k), sr * 0.15, uiart.CATCH);
}

/// THE SPELL in the cross's sorcery slot — the BOLT itself, because what that slot holds is a thing you
/// throw and not a book you own. A hot core, a violet halo and three tongues streaming back off it, the
/// fire arrow's own construction: the streak is what says which way it is going.
pub fn spell(cx: f32, cy: f32, px: f32, on: bool) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x3C0BA1);
    const a: u8 = if (on) 255 else 120;
    const halo = rgba(CHAOS.r, CHAOS.g, CHAOS.b, if (on) 90 else 45);
    const shell = rgba(CHAOS_DK.r, CHAOS_DK.g, CHAOS_DK.b, a);
    const core = rgba(CHAOS_LT.r, CHAOS_LT.g, CHAOS_LT.b, a);
    const head = v2(cx + s * 0.13, cy - s * 0.04);
    const r = s * 0.135;
    // The tongues first, so the head sits on top of them rather than being cut by them.
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const off = (@as(f32, @floatFromInt(i)) - 1.0);
        const lead: f32 = if (off == 0) 1.25 else 0.85; // the middle tongue is the long one
        const reach = r * rng.range(2.1, 3.4) * lead;
        rl.drawTriangle(
            v2(head.x - reach, head.y + off * r * 0.95 + rng.range(-1.0, 1.0) * k),
            v2(head.x, head.y - r * 0.52),
            v2(head.x, head.y + r * 0.52),
            if (off == 0) rgba(CHAOS.r, CHAOS.g, CHAOS.b, a) else halo,
        );
    }
    rl.drawCircleV(head, r * 1.42, halo);
    rl.drawCircleV(head, r, shell);
    rl.drawCircleV(v2(head.x - 0.7 * k, head.y - 0.9 * k), r * 0.58, core);
    rl.drawCircleV(v2(head.x - 1.2 * k, head.y - 1.5 * k), r * 0.22, if (on) uiart.CATCH else rgba(255, 255, 255, 110));
}

/// THE ROOTS, the rod's other sorcery: dead wood coming up out of a broken ground line, lit at the tips with
/// the spell's own violet. NOTHING ENDS IN A POINT — every tendril snaps off blunt — and nothing is straight
/// or evenly spaced, or a rosette of spikes is what it reads as.
pub fn roots(cx: f32, cy: f32, px: f32, on: bool) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x600751);
    const a: u8 = if (on) 255 else 120;
    const bark = rgba(ROOT_BARK.r, ROOT_BARK.g, ROOT_BARK.b, a);
    const heart = rgba(ROOT_HEART.r, ROOT_HEART.g, ROOT_HEART.b, a);
    const lit = rgba(CHAOS.r, CHAOS.g, CHAOS.b, if (on) 210 else 90);
    const halo = rgba(CHAOS.r, CHAOS.g, CHAOS.b, if (on) 70 else 30);
    const soil = cy + s * 0.22; // the ground the things are coming through
    // FIVE, at uneven spacings and uneven heights: a fan of equal tendrils is a garden rake.
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) + rng.range(-0.22, 0.22)) / 4.0 - 0.5;
        const foot = v2(cx + t * s * 0.62, soil + rng.range(-0.02, 0.02) * s);
        const rise = s * rng.range(0.20, 0.40);
        const lean = rng.range(-0.34, 0.34) * s * 0.5;
        // Two segments with a KNEE, so it leaves the earth on one line and carries on off it — a single
        // straight run to the tip is the spear this law exists to forbid.
        const knee = v2(foot.x + lean * 0.35, foot.y - rise * 0.55);
        const tip = v2(knee.x + lean, knee.y - rise * 0.45);
        const w = rng.range(2.2, 3.1) * k;
        rl.drawLineEx(foot, knee, w, bark);
        rl.drawLineEx(knee, tip, w * 0.72, bark);
        rl.drawCircleV(tip, w * 0.44, heart); // the blunt snap of pale heartwood
        rl.drawCircleV(tip, w * 1.15, halo);
        rl.drawCircleV(tip, w * 0.30, lit);
    }
    // The broken ground itself, drawn OVER the feet so the tendrils read as coming through it.
    const soilCol = rgba(ROOT_SOIL.r, ROOT_SOIL.g, ROOT_SOIL.b, a);
    rl.drawLineEx(v2(cx - s * 0.36, soil), v2(cx + s * 0.36, soil), 2.4 * k, soilCol);
    var j: u32 = 0;
    while (j < 4) : (j += 1) {
        const x = cx + rng.range(-0.32, 0.32) * s;
        rl.drawCircleV(v2(x, soil + rng.range(-0.4, 1.2) * k), rng.range(0.8, 1.7) * k, soilCol);
    }
}

/// THE RIME BREATH, the rod's third sorcery: a CONE, because the cone is the whole mechanic — the one spell
/// in the game that is a direction and a width rather than a mark. Crystals stream out of a narrow throat
/// and open away from it, blunt-ended (NOTHING ENDS IN A POINT) and unevenly spaced, since an even fan of
/// equal spikes is a garden rake — the roots' own lesson, in the other element.
pub fn rime(cx: f32, cy: f32, px: f32, on: bool) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x21C3);
    const a: u8 = if (on) 255 else 120;
    const ice = rgba(RIME_ICE.r, RIME_ICE.g, RIME_ICE.b, a);
    const lit = rgba(RIME_LT.r, RIME_LT.g, RIME_LT.b, a);
    const halo = rgba(RIME_ICE.r, RIME_ICE.g, RIME_ICE.b, if (on) 60 else 26);
    // The throat, off-centre to the left: the cone has to be seen to come FROM somewhere.
    const throat = v2(cx - s * 0.34, cy + s * 0.04);
    // The breath's own body — three overlapping washes opening away from the throat, widest at the far end.
    var w: u32 = 0;
    while (w < 3) : (w += 1) {
        const t = (@as(f32, @floatFromInt(w)) + 1.0) / 3.0;
        rl.drawCircleV(v2(throat.x + s * 0.62 * t, throat.y + rng.range(-0.03, 0.03) * s), s * (0.10 + 0.20 * t), halo);
    }
    // SEVEN crystals, at uneven bearings inside the cone and uneven lengths along it.
    var i: u32 = 0;
    while (i < 7) : (i += 1) {
        const spread = ((@as(f32, @floatFromInt(i)) + rng.range(-0.3, 0.3)) / 6.0 - 0.5) * 0.86; // radians off the axis
        const run = s * rng.range(0.30, 0.68);
        const from = v2(throat.x + s * 0.06, throat.y + spread * s * 0.10);
        const to = v2(from.x + run, from.y + spread * run);
        const wid = rng.range(1.8, 3.0) * k;
        rl.drawLineEx(from, to, wid, ice);
        rl.drawCircleV(to, wid * 0.52, lit); // the blunt end
        rl.drawCircleV(to, wid * 1.25, halo);
    }
    // …and the frost that has already fallen out of it, settling: COLD IS THE ONE THAT LIES ABOUT.
    var j: u32 = 0;
    while (j < 5) : (j += 1) {
        const x = cx + rng.range(-0.10, 0.40) * s;
        rl.drawCircleV(v2(x, cy + s * rng.range(0.24, 0.40)), rng.range(0.9, 1.8) * k, lit);
    }
}

/// THE LEVIN STRIKE, the rod's fourth: a STROKE, because that is the whole mechanic — the one spell that does
/// not cross the ground, so what the picture may not show is a thing sailing along like the bolt. It comes down
/// the card and ENDS ON SOMETHING, and the flash at the foot is what says it landed on a body rather than
/// carrying on. Uneven segments and uneven widths: a regular zigzag is a logo.
pub fn levin(cx: f32, cy: f32, px: f32, on: bool) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x1E7A1);
    const a: u8 = if (on) 255 else 120;
    const hot = rgba(LEVIN_HOT.r, LEVIN_HOT.g, LEVIN_HOT.b, a);
    const edge = rgba(LEVIN_EDGE.r, LEVIN_EDGE.g, LEVIN_EDGE.b, a);
    const halo = rgba(LEVIN_EDGE.r, LEVIN_EDGE.g, LEVIN_EDGE.b, if (on) 66 else 28);
    const foot = v2(cx + s * 0.06, cy + s * 0.30); // where it lands, low and a shade right of centre
    const head = v2(cx - s * 0.20, cy - s * 0.34); // …and where it comes out of, high and left
    // FOUR segments walked down between the two, each thrown off the straight line by its own amount, so the
    // stroke reads as torn rather than drawn. The width falls as it goes: the ground end is the thin end.
    var prev = head;
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const u = (@as(f32, @floatFromInt(i)) + 1.0) / 4.0;
        const on_line = v2(head.x + (foot.x - head.x) * u, head.y + (foot.y - head.y) * u);
        const kink = if (i == 3) 0.0 else rng.range(-0.16, 0.16) * s; // the last one MEETS the foot
        const p = v2(on_line.x + kink, on_line.y + rng.range(-0.03, 0.03) * s);
        const w = mathx.lerpF(3.4, 1.9, u) * k * rng.range(0.85, 1.15);
        rl.drawLineEx(prev, p, w + 1.6 * k, halo);
        rl.drawLineEx(prev, p, w, edge);
        rl.drawLineEx(prev, p, w * 0.42, hot); // the white-hot filament inside the stroke
        prev = p;
    }
    // THE FLASH IT ENDS IN, and a few sparks off it — the burst that says it hit something.
    rl.drawCircleV(foot, s * 0.15, halo);
    rl.drawCircleV(foot, s * 0.070, edge);
    rl.drawCircleV(foot, s * 0.034, hot);
    var j: u32 = 0;
    while (j < 5) : (j += 1) {
        const ang = rng.range(3.4, 6.0); // thrown up and out of the strike, never back down into the card
        const run = s * rng.range(0.10, 0.22);
        const from = v2(foot.x + mathx.cosf(ang) * s * 0.04, foot.y + mathx.sinf(ang) * s * 0.04);
        rl.drawLineEx(from, v2(from.x + mathx.cosf(ang) * run, from.y + mathx.sinf(ang) * run), rng.range(1.0, 1.8) * k, edge);
    }
}

/// THE SIPHON, the fifth: motes CONVERGING on a core, which is chaos's own `inward` signature (`elemfx`) and the
/// one thing this card has to say — the bolt's tongues stream BACK off a head that is leaving, and these run the
/// other way, into something that is taking. Uneven bearings and uneven runs, or it is a compass rose.
pub fn siphon(cx: f32, cy: f32, px: f32, on: bool) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x51F0);
    const a: u8 = if (on) 255 else 120;
    const shell = rgba(CHAOS_DK.r, CHAOS_DK.g, CHAOS_DK.b, a);
    const body = rgba(CHAOS.r, CHAOS.g, CHAOS.b, a);
    const core = rgba(CHAOS_LT.r, CHAOS_LT.g, CHAOS_LT.b, a);
    const halo = rgba(CHAOS.r, CHAOS.g, CHAOS.b, if (on) 80 else 34);
    const at = v2(cx - s * 0.04, cy + s * 0.02); // the throat, off dead centre
    // **SIX COMETS, HEAD INWARD** — and which end the head is on IS the whole picture. Drawn first with the ball
    // at the OUTER end this read as a burr: a still frame takes its direction from the comet's shape, so balls on
    // the outside are things that have just been thrown OUT, which is the exact opposite of a drain. The head
    // therefore sits at the INNER end with the tail streaming back out behind it, and the tail is two segments
    // because `drawLineEx` has one width and a taper is what says which end is leading.
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        const ang = (@as(f32, @floatFromInt(i)) + rng.range(-0.34, 0.34)) / 6.0 * std.math.tau;
        // WIDELY uneven runs: six of a length is a rosette however the bearings are jittered.
        // **AND THE HEADS STOP WELL SHORT OF THE CORE.** Brought in to 0.13 they overlapped it and each other and
        // the whole card read as one fuzzy lump with whiskers: the DARK GAP between the ring of heads and the
        // throat is what says they are still travelling, so it is as load-bearing as the taper.
        const far = s * rng.range(0.34, 0.52);
        const nearR = s * rng.range(0.190, 0.250);
        const mid = mathx.lerpF(far, nearR, 0.55);
        const cs = mathx.cosf(ang);
        const sn = mathx.sinf(ang);
        const tail = v2(at.x + cs * far, at.y + sn * far);
        const waist = v2(at.x + cs * mid, at.y + sn * mid);
        const head = v2(at.x + cs * nearR, at.y + sn * nearR);
        const w = rng.range(1.5, 2.2) * k;
        rl.drawLineEx(tail, waist, w * 0.55, halo); // the thin, faint end it came from…
        rl.drawLineEx(waist, head, w, body); // …thickening into the head
        rl.drawCircleV(head, w * 1.05, if (i % 3 == 0) core else body);
    }
    rl.drawCircleV(at, s * 0.118, halo);
    rl.drawCircleV(at, s * 0.076, shell);
    rl.drawCircleV(v2(at.x - 0.7 * k, at.y - 0.9 * k), s * 0.046, body);
    rl.drawCircleV(v2(at.x - 1.1 * k, at.y - 1.4 * k), s * 0.020, core);
}

/// `on` is a quiver that has something in it — a spent one draws the same shaft, greyed.
pub fn arrow(cx: f32, cy: f32, px: f32, on: bool, fire: bool) void {
    const s = px;
    const k = strokeK(px);
    const half = s * 0.16;
    const shaft = if (on) BOWWOOD else rgba(BOWWOOD.r, BOWWOOD.g, BOWWOOD.b, 120);
    const plainHead = if (on) STEEL else rgba(STEEL_DK.r, STEEL_DK.g, STEEL_DK.b, 140);
    const head = if (fire) (if (on) FIRE else rgba(FIRE.r, FIRE.g, FIRE.b, 140)) else plainHead;
    // THE PITCHED HEAD IS TONGUES STREAMING BACK OFF THE PILE, as the mesh is — a disc behind the head
    // swallowed it and read as a ball on a stick.
    if (fire) {
        const hot = if (on) FIRE else rgba(FIRE.r, FIRE.g, FIRE.b, 90);
        const dim = if (on) FIRE_DIM else rgba(FIRE_DIM.r, FIRE_DIM.g, FIRE_DIM.b, 70);
        const root = cx + half - 0.8 * k;
        for ([_]f32{ -1, 0, 1 }) |sy| {
            const reach = if (sy == 0) 5.6 * k else 4.0 * k;
            rl.drawTriangle(
                v2(root - reach, cy + sy * 2.5 * k),
                v2(root, cy - 1.5 * k),
                v2(root, cy + 1.5 * k),
                if (sy == 0) hot else dim,
            );
        }
    }
    rl.drawLineEx(v2(cx - half, cy), v2(cx + half, cy), 2.0 * k, shaft);
    rl.drawLineEx(v2(cx - half, cy - 0.7 * k), v2(cx + half * 0.7, cy - 0.7 * k), 0.7 * k, rgba(GRIP_LT.r, GRIP_LT.g, GRIP_LT.b, if (on) 160 else 70)); // the lit top of the shaft
    rl.drawTriangle(
        v2(cx + half + 3.0 * k, cy),
        v2(cx + half - 1.6 * k, cy - 2.3 * k),
        v2(cx + half - 1.6 * k, cy + 2.3 * k),
        head,
    );
    rl.drawLineEx(v2(cx + half - 2.2 * k, cy), v2(cx + half - 1.0 * k, cy), 3.0 * k, rgba(head.r / 2, head.g / 2, head.b / 2, head.a));
    for ([_]f32{ -1, 1 }) |sy| {
        rl.drawLineEx(v2(cx - half + 3.4 * k, cy), v2(cx - half - 0.6 * k, cy + sy * (2.4 + 0.5 * sy) * k), 1.5 * k, shaft);
    }
    // …and the NOCK: the notch the string sits in, which is what makes the tail an end and not a stub.
    rl.drawLineEx(v2(cx - half - 1.0 * k, cy - 1.5 * k), v2(cx - half - 1.0 * k, cy + 1.5 * k), 1.2 * k, rgba(CORD.r, CORD.g, CORD.b, if (on) 235 else 110));
}

/// A RING THAT HAS BEEN BROKEN, which is the whole of what a Rune Arc is: an arc of gilt with a lit core
/// running through it and two snapped ends. The break is what stops it reading as a coin.
fn soulArc(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xA12C);
    const r = s * 0.30;
    const gapAt = rng.range(-0.5, 0.5); // where the break sits on the wheel
    const gapHalf = 0.42; // radians
    const from = gapAt + gapHalf;
    const to = gapAt + std.math.tau - gapHalf;
    rl.drawCircleV(v2(cx + 1.0 * k, cy + 1.2 * k), r * 0.35, rgba(0, 0, 0, 90));
    arc(cx, cy, r, from, to, 26, 4.2 * k, 2.2 * k, rgba(0, 0, 0, 150)); // the seat under the band
    arc(cx, cy, r, from, to, 26, 3.2 * k, 1.5 * k, uiart.GILT_DIM);
    arc(cx, cy, r - 0.8 * k, from, to, 26, 1.4 * k, 0.8 * k, uiart.GILT_BRIGHT); // the lit inner edge
    // THE LIGHT INSIDE IT: a pale core following the band, and it is why this thing is worth picking up.
    arc(cx, cy, r, from + 0.10, to - 0.10, 22, 1.1 * k, 0.6 * k, rgba(255, 246, 214, 170));
    for ([_]f32{ from, to }) |a| {
        const p = v2(cx + mathx.cosf(a) * r, cy + mathx.sinf(a) * r);
        rl.drawCircleV(p, 2.1 * k, uiart.GILT); // a snapped end is a blunt swelling, not a taper
        rl.drawCircleV(v2(p.x - 0.5 * k, p.y - 0.6 * k), 0.9 * k, uiart.CATCH);
    }
    // Motes coming off the break — the arc is spending itself.
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const a = gapAt + rng.range(-0.5, 0.5);
        const rr = r * rng.range(0.55, 1.35);
        rl.drawCircleV(v2(cx + mathx.cosf(a) * rr, cy + mathx.sinf(a) * rr), rng.range(0.5, 1.1) * k, rgba(255, 232, 176, 190));
    }
}

/// A SPROUT, not a nut: a golden pod split at the top with two leaves off a leaning stem. The gold is the
/// thing that says it matters, so the pod carries the light and the leaves stay dull.
fn goldenSeed(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x60D5EE);
    const rootY = cy + s * 0.34;
    const tipY = cy - s * 0.30;
    const lean = rng.range(-0.06, 0.06) * s;
    const stem = v2(cx + lean * 0.35, rootY);
    const crown = v2(cx + lean, tipY);

    rl.drawLineEx(stem, crown, 2.0 * k, rgba(96, 84, 44, 255)); // the stalk, leaning
    // TWO LEAVES OF DIFFERENT LENGTH off different heights of the stalk — a matched pair is a logo.
    for ([_]f32{ -1, 1 }) |side| {
        const at = 0.34 + side * rng.range(0.04, 0.13);
        const root = onAxis(stem, crown, at, 0);
        const len = s * rng.range(0.22, 0.30);
        const tip = v2(root.x + side * len, root.y - len * rng.range(0.35, 0.62));
        const mid = v2((root.x + tip.x) * 0.5, (root.y + tip.y) * 0.5 - len * 0.22);
        quad(root, mid, tip, v2(mid.x, mid.y + len * 0.30), rgba(104, 96, 52, 255));
        rl.drawLineEx(root, tip, 0.8 * k, rgba(140, 130, 74, 220)); // the midrib
    }
    // THE POD: a teardrop of gold, drawn as a stack of shrinking discs so it comes to a soft point.
    const podR = s * 0.155;
    const podY = tipY + podR * 0.55;
    rl.drawCircleV(v2(cx + lean + 0.9 * k, podY + 1.0 * k), podR, rgba(0, 0, 0, 110));
    var i: u32 = 0;
    while (i < 7) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / 6.0;
        const rr = podR * (1.0 - 0.78 * t * t);
        const yy = podY - podR * 1.15 * t;
        rl.drawCircleV(v2(cx + lean * (1.0 + t * 0.4), yy), rr, mathx.lerpColor(uiart.GILT, uiart.GILT_BRIGHT, t * 0.7));
    }
    rl.drawCircleV(v2(cx + lean - podR * 0.34, podY - podR * 0.22), podR * 0.34, rgba(255, 246, 210, 190)); // its gloss
    // THE SPLIT down the pod's face, and a bead of light out of it.
    rl.drawLineEx(
        v2(cx + lean + podR * 0.10, podY + podR * 0.55),
        v2(cx + lean + podR * 0.22, podY - podR * 0.95),
        1.1 * k,
        rgba(126, 96, 30, 200),
    );
    rl.drawCircleV(v2(cx + lean + podR * 0.24, podY - podR * 1.05), 1.2 * k, uiart.CATCH);
}

/// A SHARD OFF A BIGGER STONE — flat facets at odd angles, one of them catching the light, and the
/// fracture edges pale where the crystal is fresh. Nothing here is symmetric: a smithing stone is rubble.
fn smithingStone(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x57012E);
    const r = s * 0.34;
    // The outline: seven corners at wobbled radii, so the silhouette is a chunk rather than a gem.
    const N = 7;
    var pts: [N]rl.Vector2 = undefined;
    for (0..N) |i| {
        const a = std.math.tau * (@as(f32, @floatFromInt(i)) / N) + rng.range(-0.22, 0.22) - 0.4;
        const rr = r * rng.range(0.70, 1.10);
        pts[i] = v2(cx + mathx.cosf(a) * rr, cy + mathx.sinf(a) * rr * 0.92);
    }
    // Seated, then filled as a fan off a point pushed off-centre — which is what tilts every facet.
    const core = v2(cx + rng.range(-0.12, 0.12) * s, cy + rng.range(-0.10, 0.10) * s);
    for (0..N) |i| {
        const a = pts[i];
        const b = pts[(i + 1) % N];
        rl.drawTriangle(v2(a.x + 1.4 * k, a.y + 1.8 * k), v2(b.x + 1.4 * k, b.y + 1.8 * k), v2(core.x + 1.4 * k, core.y + 1.8 * k), rgba(0, 0, 0, 120));
    }
    for (0..N) |i| {
        const a = pts[i];
        const b = pts[(i + 1) % N];
        // A facet's tone is how far it faces UP: the top of the stone takes the light, the underside does not.
        const up = 1.0 - (((a.y + b.y) * 0.5 - cy) / r + 1.0) * 0.5;
        const col = mathx.lerpColor(STONE_DK, STONE_LT, mathx.clampF(up * rng.range(0.75, 1.25), 0, 1));
        quad(a, b, core, core, col);
        rl.drawLineEx(a, b, 0.9 * k, rgba(STONE.r, STONE.g, STONE.b, 200)); // the fracture edge
    }
    // ONE facet struck bright, and the cold spark off it — the reason a smith wants the thing.
    const li: usize = @intCast(rng.intn(N));
    quad(pts[li], pts[(li + 1) % N], core, core, rgba(STONE_LT.r, STONE_LT.g, STONE_LT.b, 235));
    const sp = v2((pts[li].x + core.x) * 0.5, (pts[li].y + core.y) * 0.5);
    rl.drawCircleV(sp, 1.6 * k, rgba(SPARK.r, SPARK.g, SPARK.b, 200));
    rl.drawLineEx(v2(sp.x - 2.6 * k, sp.y), v2(sp.x + 2.6 * k, sp.y), 0.8 * k, rgba(SPARK.r, SPARK.g, SPARK.b, 130));
    rl.drawLineEx(v2(sp.x, sp.y - 2.6 * k), v2(sp.x, sp.y + 2.6 * k), 0.8 * k, rgba(SPARK.r, SPARK.g, SPARK.b, 130));
}

/// A TUFT PULLED UP WITH ITS ROOT ON — blades of unequal length fanning off one crown, dried to the
/// colour that named it. A neat fan is a wheat sheaf; these lean and cross.
fn bloodgrass(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xB100D6);
    const crown = v2(cx + rng.range(-0.03, 0.03) * s, cy + s * 0.26);
    // The root ball first, so the blades land on top of it.
    rl.drawCircleV(v2(crown.x, crown.y + s * 0.03), s * 0.10, rgba(58, 44, 34, 255));
    var i: u32 = 0;
    while (i < 7) : (i += 1) {
        const spread = (@as(f32, @floatFromInt(i)) / 6.0 - 0.5) * 2.0; // -1 … 1
        const len = s * rng.range(0.34, 0.60);
        const sway = spread * rng.range(0.30, 0.62);
        const tip = v2(crown.x + sway * len, crown.y - len);
        const knee = v2(crown.x + sway * len * 0.35, crown.y - len * 0.62);
        const col = if (@mod(@as(f32, @floatFromInt(i)), 3.0) == 0) WEED_DK else if (@mod(@as(f32, @floatFromInt(i)), 2.0) == 0) WEED else WEED_LT;
        rl.drawLineEx(crown, knee, 1.9 * k, col);
        rl.drawLineEx(knee, tip, 1.1 * k, col); // thinner past the knee: a blade tapers
        // The seed head: a few dark beads at the top of the taller blades.
        if (len > s * 0.46) {
            var b: u32 = 0;
            while (b < 3) : (b += 1) {
                const t = 0.72 + @as(f32, @floatFromInt(b)) * 0.11;
                rl.drawCircleV(v2(mathx.lerpF(crown.x, tip.x, t), mathx.lerpF(crown.y, tip.y, t)), 0.9 * k, WEED_DK);
            }
        }
    }
    // A little soil still hanging off the root, which is what says PULLED rather than picked.
    var d: u32 = 0;
    while (d < 4) : (d += 1) {
        rl.drawCircleV(
            v2(crown.x + rng.range(-0.13, 0.13) * s, crown.y + rng.range(0.02, 0.10) * s),
            rng.range(0.7, 1.5) * k,
            rgba(52, 40, 30, 220),
        );
    }
}

/// A TOOTH OUT OF A JAW: curved, root and all, yellowed at the root and pale at the point, with the crack
/// that let it come loose. Drawn as a stack of shrinking discs down a bent spine so it has real thickness.
fn koboldFang(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xFA46);
    const rootP = v2(cx - s * 0.16 + rng.range(-0.02, 0.02) * s, cy + s * 0.32);
    const tipP = v2(cx + s * 0.20, cy - s * 0.34);
    const bend = rng.range(0.14, 0.24); // how far the curve bellies out across the chord
    const SEGS = 14;
    var prev = rootP;
    for (0..SEGS + 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / SEGS;
        // A quadratic belly off the chord — one control point is all a tooth's curve needs.
        const p = onAxis(rootP, tipP, t, -bend * s * (4.0 * t * (1.0 - t)));
        const w = mathx.lerpF(4.6, 0.5, t * t * 0.85 + t * 0.15) * k;
        const col = mathx.lerpColor(BONE_DK, BONE, mathx.clampF(t * 1.25, 0, 1));
        if (i > 0) rl.drawLineEx(prev, p, w, col);
        prev = p;
    }
    // The lit ridge along the outer face, and the stain in the hollow of the curve.
    const midOut = onAxis(rootP, tipP, 0.45, -bend * s * 1.16);
    rl.drawLineEx(onAxis(rootP, tipP, 0.18, -bend * s * 0.72), midOut, 1.0 * k, rgba(255, 250, 236, 190));
    rl.drawLineEx(onAxis(rootP, tipP, 0.30, -bend * s * 0.30), onAxis(rootP, tipP, 0.70, -bend * s * 0.34), 1.4 * k, rgba(150, 128, 86, 150));
    // THE CRACK across the root — it did not fall out, something took it out.
    const cA = onAxis(rootP, tipP, 0.14, -1.8 * k);
    const cB = onAxis(rootP, tipP, 0.22, 2.4 * k);
    rl.drawLineEx(cA, v2((cA.x + cB.x) * 0.5 + 1.2 * k, (cA.y + cB.y) * 0.5), 0.9 * k, rgba(96, 82, 58, 220));
    rl.drawLineEx(v2((cA.x + cB.x) * 0.5 + 1.2 * k, (cA.y + cB.y) * 0.5), cB, 0.9 * k, rgba(96, 82, 58, 220));
    rl.drawCircleV(rootP, 2.2 * k, rgba(BONE_DK.r, BONE_DK.g, BONE_DK.b, 255)); // the blunt, open root
    rl.drawCircleV(v2(rootP.x + 0.4 * k, rootP.y - 0.3 * k), 1.1 * k, rgba(88, 62, 52, 235)); // the pulp cavity
}

/// A BOW, A SHANK AND A BIT — the three parts of a key, in iron that has been in the ground. The wards
/// are two teeth of different depth off the end, because a key nobody can read is a key nobody drew.
fn ironKey(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x1204E7);
    const u = 0.70711;
    const lean = rng.range(-0.05, 0.05);
    const headP = v2(cx - u * s * 0.28 * (1 + lean), cy - u * s * 0.28);
    const tipP = v2(cx + u * s * 0.34, cy + u * s * 0.34 * (1 - lean));

    rl.drawLineEx(v2(headP.x + 1.2 * k, headP.y + 1.4 * k), v2(tipP.x + 1.2 * k, tipP.y + 1.4 * k), 3.0 * k, rgba(0, 0, 0, 120));
    rl.drawLineEx(headP, tipP, 2.4 * k, IRON_DK); // the shank
    rl.drawLineEx(onAxis(headP, tipP, 0.18, -0.9 * k), onAxis(headP, tipP, 0.86, -0.9 * k), 0.8 * k, rgba(STEEL_DK.r, STEEL_DK.g, STEEL_DK.b, 170));

    // THE BOW: a ring you can put a finger through, struck as a band so the hole stays a hole — a filled
    // poly with a smaller one over it would need the plate's own colour, which this does not know.
    const ringR = s * 0.145;
    const ringC = onAxis(headP, tipP, -0.12, 0);
    arc(ringC.x, ringC.y, ringR + 0.6 * k, 0, std.math.tau, 18, 3.4 * k, 3.4 * k, rgba(0, 0, 0, 130));
    arc(ringC.x, ringC.y, ringR, 0, std.math.tau, 18, 2.6 * k, 2.6 * k, IRON_DK);
    arc(ringC.x, ringC.y, ringR, 3.5, 5.4, 9, 1.0 * k, 0.6 * k, rgba(STEEL_DK.r, STEEL_DK.g, STEEL_DK.b, 200));
    arc(ringC.x, ringC.y, ringR, 0.6, 2.1, 9, 1.4 * k, 1.0 * k, rgba(RUST.r, RUST.g, RUST.b, 220));
    // A COLLAR where the shank leaves the bow, or the two read as a lollipop.
    rl.drawCircleV(onAxis(headP, tipP, 0.10, 0), 2.0 * k, IRON_DK);

    // THE BIT: two wards of unequal depth off the end of the shank.
    const across = v2(-(tipP.y - headP.y), tipP.x - headP.x);
    const alen = @max(@sqrt(across.x * across.x + across.y * across.y), 1e-4);
    const nx = across.x / alen;
    const ny = across.y / alen;
    for ([_][2]f32{ .{ 0.80, 5.2 }, .{ 0.96, 3.4 } }) |ward| {
        const base = onAxis(headP, tipP, ward[0], 0);
        const outT = ward[1] * k * rng.range(0.9, 1.1);
        rl.drawLineEx(base, v2(base.x + nx * outT, base.y + ny * outT), 2.2 * k, IRON_DK);
    }
    rl.drawCircleV(tipP, 1.3 * k, rgba(RUST.r, RUST.g, RUST.b, 200)); // rust gathers at the end
}

/// A DRIED MUSHROOM, and the silhouette is what says so: a domed CAP over a STEM with the gills showing under
/// the rim. As a wavy horizontal strip it read as neither jerky nor forage — a lump. Dried, not fresh: the
/// cap is shrunken onto a stem too thin for it and the rim has curled UP off the gills.
fn jerky(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x1E12C4);
    const capR = s * 0.32; // the cap's half-width…
    const capH = s * 0.30; // …and how far the dome stands above its own rim
    const rimY = cy - s * 0.02; // the underside, a touch above centre so the stem has its room
    const SEGS = 14;

    // THE STEM first, so the cap sits over its top: a shrivelled taper, wider at the foot, leaning off plumb.
    const footX = cx + s * 0.035;
    const stemTop = s * 0.085;
    const stemFoot = s * 0.115;
    quad(
        v2(cx - stemTop, rimY),
        v2(cx + stemTop, rimY),
        v2(footX + stemFoot, cy + s * 0.36),
        v2(footX - stemFoot, cy + s * 0.36),
        CAP_DK,
    );
    // …lit down one side of it, or the stem is a flat plank under a shaded cap.
    quad(
        v2(cx, rimY),
        v2(cx + stemTop, rimY),
        v2(footX + stemFoot, cy + s * 0.36),
        v2(footX + stemFoot * 0.25, cy + s * 0.36),
        mathx.lerpColor(CAP_DK, CAP_LT, 0.30),
    );
    // The torn foot: pale fibres where it was pulled up, never a clean cut. SHORT and inside the stem's own
    // width — run past it and they read as legs, which is a different animal entirely.
    var f: u32 = 0;
    while (f < 4) : (f += 1) {
        const x = footX + (@as(f32, @floatFromInt(f)) - 1.5) * s * 0.05;
        rl.drawLineEx(v2(x, cy + s * 0.345), v2(x + rng.range(-0.5, 0.5) * k, cy + s * 0.36 + rng.range(0.6, 1.4) * k), 1.0 * k, CAP_LT);
    }

    // THE GILLS, drawn before the cap so the dome's rim laps over their tops: dark radial ticks fanned out
    // under the rim, and the one part of a mushroom nothing else in the bag looks like.
    var gi: u32 = 0;
    while (gi < 9) : (gi += 1) {
        const t = (@as(f32, @floatFromInt(gi)) + 0.5) / 9.0;
        const x = cx - capR * 0.86 + capR * 1.72 * t;
        const drop = s * 0.075 * (1.0 - @abs(t - 0.5) * 1.5) * rng.range(0.8, 1.2);
        rl.drawLineEx(v2(x, rimY - s * 0.01), v2(x * 0.985 + cx * 0.015, rimY + drop), 1.0 * k, rgba(62, 40, 30, 205));
    }

    // THE CAP: a dome laid down as a fan of quads off its own rim line, each rib a hair uneven so the
    // outline is a dried cap and not a compass arc.
    var prev = v2(cx - capR, rimY);
    for (1..SEGS + 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / SEGS;
        const a = std.math.pi * (1.0 - t); // pi → 0, left rim over the top to the right rim
        const shrink = rng.range(0.94, 1.05);
        const p = v2(cx + mathx.cosf(a) * capR * shrink, rimY - mathx.sinf(a) * capH * shrink);
        // Lit from the upper left, like every other picture in this file.
        const shade = mathx.lerpColor(CAP_DK, CAP_LT, mathx.clampF(0.86 - t * 0.86, 0, 1));
        rl.drawTriangle(v2(cx, rimY), prev, p, shade);
        rl.drawTriangle(v2(cx, rimY), p, prev, shade);
        prev = p;
    }
    // …and the rim CURLED UP off the gills, which is the whole tell that it is dried.
    rl.drawLineEx(v2(cx - capR, rimY), v2(cx - capR * 0.82, rimY - s * 0.055), 1.2 * k, CAP_LT);
    rl.drawLineEx(v2(cx + capR, rimY), v2(cx + capR * 0.84, rimY - s * 0.045), 1.2 * k, CAP_LT);
    // A shrivel crease or two over the dome — dried cap flesh puckers.
    var c: u32 = 0;
    while (c < 3) : (c += 1) {
        const a0 = 2.5 - @as(f32, @floatFromInt(c)) * 0.65;
        rl.drawLineEx(
            v2(cx + mathx.cosf(a0) * capR * 0.86, rimY - mathx.sinf(a0) * capH * 0.86),
            v2(cx + mathx.cosf(a0) * capR * 0.30, rimY - mathx.sinf(a0) * capH * 0.34),
            0.9 * k,
            rgba(74, 46, 34, 150),
        );
    }
    // The salt it was cured in, over the cap only — it does not settle on the underside.
    var sa: u32 = 0;
    while (sa < 6) : (sa += 1) {
        const a0 = rng.range(0.35, std.math.pi - 0.35);
        const r0 = rng.range(0.25, 0.88);
        rl.drawCircleV(
            v2(cx + mathx.cosf(a0) * capR * r0, rimY - mathx.sinf(a0) * capH * r0),
            rng.range(0.4, 0.9) * k,
            rgba(SALT.r, SALT.g, SALT.b, 190),
        );
    }
}
