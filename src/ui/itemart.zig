const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const uiart = @import("uiart.zig");
const item = @import("../play/item.zig");
const combat = @import("../play/combat.zig");

// Every stroke scales off `k`: the set was tuned in a 34 px box (`TUNED_AT`) and multiplies up, so one picture serves a 33 px bag cell and a 240 px detail plate. Every wabi-sabi offset comes out of a FIXED-SEED `mathx.Rng` re-seeded per call — off a live stream the whole HUD crawls.

const rgba = mathx.rgba;

/// **THE DROP SHADOW UNDER A PICTURE, NAMED ONCE.** Nineteen `drawCircleV`s laid the same black wash and every
/// one of them spelled it out, in a file that names every other colour it uses — so the one value the whole set
/// shares was the one nothing could retune. The handful of pictures that ask for a heavier or lighter wash keep
/// their own literal on purpose.
const SHADOW = rgba(0, 0, 0, 110);

pub const STEEL = rgba(232, 234, 238, 255);
pub const STEEL_MID = rgba(178, 184, 192, 255);
pub const STEEL_DK = rgba(126, 132, 140, 255);
pub const BRASS = rgba(182, 146, 78, 255);
pub const GRIP = rgba(112, 82, 56, 255);
pub const BOARD_JOINT = rgba(78, 56, 38, 255);
pub const GRIP_LT = rgba(146, 110, 76, 255);
pub const WAX = rgba(126, 34, 30, 255);
pub const GLASS_LIT = rgba(238, 236, 230, 255);
pub const CORD = rgba(158, 142, 108, 255);
pub const FIRE = rgba(255, 158, 62, 255);
const FIRE_DIM = rgba(226, 108, 30, 150);
pub const CHAOS = rgba(178, 92, 224, 255);
/// **POISON'S VIOLET, UP HERE WITH THE REST OF THE PALETTE.** The dirk drew it inline off a `hud` constant that
/// nothing has read since the ten meters replaced the one poison bar (`hud.ailTint`), so the citation and the
/// figure had already parted company.
const VENOM = rgba(96, 62, 118, 255);
const VENOM_LT = rgba(158, 118, 186, 255);
const CHAOS_LT = rgba(226, 182, 252, 255);
const CHAOS_DK = rgba(96, 40, 132, 255);
const BOWWOOD = rgba(96, 68, 44, 255);
const BOWWOOD_LT = rgba(140, 102, 66, 255);
const BOWNOCK = rgba(196, 188, 168, 255);
const BOWSTRING = rgba(214, 206, 184, 255);
const CRIMSON = rgba(196, 46, 40, 255);
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
const SPARK = rgba(180, 214, 236, 255);
const RIME_ICE = rgba(150, 200, 226, 255);
const RIME_LT = rgba(212, 238, 250, 255);
const LEVIN_HOT = rgba(255, 255, 224, 255);
const LEVIN_EDGE = rgba(226, 230, 232, 255);
const WEED = rgba(126, 30, 34, 255);
const WEED_LT = rgba(178, 62, 52, 255);
const WEED_DK = rgba(74, 20, 24, 255);
const CAP_DK = rgba(96, 58, 42, 255);
const CAP_LT = rgba(158, 108, 72, 255);
const SALT = rgba(226, 208, 176, 255);
const ROOT_BARK = rgba(64, 46, 32, 255);
const ROOT_HEART = rgba(172, 148, 112, 255);
const ROOT_SOIL = rgba(52, 40, 30, 255);
const SHROOM_CAP = rgba(178, 84, 70, 255);
const RING_GOLD = rgba(214, 176, 84, 255);
const RING_GOLD_LT = rgba(248, 226, 160, 255);
const RING_SOUL = rgba(250, 214, 132, 255);
const SHROOM_CAP_DK = rgba(112, 48, 40, 255);
const SHROOM_CREAM = rgba(224, 206, 170, 255);
const EMBER_FAT = rgba(230, 196, 130, 255);
const EMBER_FAT_DK = rgba(178, 140, 84, 255);
const BRONZE = rgba(168, 126, 58, 255);
const BRONZE_LT = rgba(214, 176, 102, 255);
const BRONZE_DK = rgba(104, 76, 34, 255);
const BRONZE_BORE = rgba(38, 28, 14, 255);
const HIDE = rgba(198, 176, 134, 255);
const HIDE_LT = rgba(226, 208, 172, 255);
const HIDE_DK = rgba(132, 112, 80, 255);
const SPIRIT = rgba(146, 166, 190, 255);
const SPIRIT_LT = rgba(206, 222, 238, 255);

pub const TUNED_AT: f32 = 34.0;

fn strokeK(px: f32) f32 {
    return px / TUNED_AT;
}

fn quad(a: rl.Vector2, b: rl.Vector2, c: rl.Vector2, d: rl.Vector2, col: rl.Color) void {
    if ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) <= 0) {
        rl.drawTriangle(a, b, c, col);
        rl.drawTriangle(a, c, d, col);
    } else {
        rl.drawTriangle(a, d, c, col);
        rl.drawTriangle(a, c, b, col);
    }
}

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

const UNLIT_SHARE: f32 = 120.0 / 255.0;
fn dimmed(c: rl.Color, lit: bool) rl.Color {
    return if (lit) c else mathx.withAlpha(c, mathx.u8f(@as(f32, @floatFromInt(c.a)) * UNLIT_SHARE));
}

/// A filled ellipse at a FLOAT centre. raylib's own takes `i32` there, so every caller was doing the same `@intFromFloat` pair by hand — and quietly snapping the picture to a whole pixel, which at a 33 px bag cell is a tenth of the cell.
fn ellipseV(cx: f32, cy: f32, rx: f32, ry: f32, col: rl.Color) void {
    rl.drawEllipse(@intFromFloat(@round(cx)), @intFromFloat(@round(cy)), rx, ry, col);
}

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

pub fn draw(k: item.Kind, cx: f32, cy: f32, px: f32) void {
    drawHeld(k, cx, cy, px, true);
}

/// **A SHEAF, NOT ONE ARROW.** Three shafts fanned and tied — a single arrow at this size is a line, and a line is what every other stick in the tray already looks like. `hot` swaps the heads for tallow-wrapped rag, the only thing that separates the two kinds at 32 px.
fn arrowSheaf(cx: f32, cy: f32, px: f32, hot: bool) void {
    const s = px;
    const k = strokeK(px);
    const LEAN = [_]f32{ -0.16, 0.02, 0.19 };
    for (LEAN, 0..) |lean, i| {
        const t = @as(f32, @floatFromInt(i));
        const foot = v2(cx + lean * s * 1.4 - s * 0.02, cy + s * 0.36);
        const head = v2(cx + lean * s * 0.5, cy - s * 0.34);
        rl.drawLineEx(foot, head, 2.2 * k, if (i == 1) BOWWOOD_LT else BOWWOOD);
        // The head: a leaf point in steel, or a wrapped bundle if it is meant to burn.
        if (hot) {
            rl.drawCircleV(v2(head.x, head.y + s * 0.03), 3.4 * k, CORD);
            rl.drawCircleV(v2(head.x, head.y + s * 0.01), 2.4 * k, if (@mod(t, 2.0) == 0) FIRE else FIRE_DIM);
        } else {
            rl.drawTriangle(
                v2(head.x, head.y - s * 0.06),
                v2(head.x - s * 0.045, head.y + s * 0.05),
                v2(head.x + s * 0.045, head.y + s * 0.05),
                STEEL_MID,
            );
        }
        // Fletching, on the near side only — three sets of both is a hedge.
        const fl = v2(mathx.lerpF(foot.x, head.x, 0.16), mathx.lerpF(foot.y, head.y, 0.16));
        rl.drawLineEx(fl, v2(fl.x - s * 0.07, fl.y + s * 0.03), 1.6 * k, BONE_DK);
        rl.drawLineEx(v2(fl.x, fl.y + s * 0.05), v2(fl.x - s * 0.06, fl.y + s * 0.08), 1.5 * k, BONE_DK);
    }
    rl.drawLineEx(v2(cx - s * 0.16, cy + s * 0.08), v2(cx + s * 0.15, cy + s * 0.05), 2.6 * k, CORD);
}

pub fn drawHeld(k: item.Kind, cx: f32, cy: f32, px: f32, any: bool) void {
    switch (k) {
        .crimson_flask => flask(cx, cy, px, .crimson, any),
        .cerulean_flask => flask(cx, cy, px, .cerulean, any),
        .rune_arc => soulArc(cx, cy, px),
        .golden_seed => goldenSeed(cx, cy, px),
        .smithing_stone => smithingStone(cx, cy, px),
        .bloodgrass => bloodgrass(cx, cy, px),
        .kobold_fang => koboldFang(cx, cy, px),
        .plain_arrows => arrowSheaf(cx, cy, px, false),
        .fire_arrows => arrowSheaf(cx, cy, px, true),
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
        .purgeleaf => purgeleaf(cx, cy, px),
        .pilgrims_salt => pilgrimsSalt(cx, cy, px),
        .ironwort_tea => ironwortTea(cx, cy, px),
        .rimeward_mantle => rimewardMantle(cx, cy, px),
        .sporecrown => sporecrown(cx, cy, px),
        .gravebell_amulet => gravebellAmulet(cx, cy, px),
        .scroll_bolt => sorceryScroll(cx, cy, px, .bolt),
        .scroll_roots => sorceryScroll(cx, cy, px, .roots),
        .scroll_rime => sorceryScroll(cx, cy, px, .rime),
        .scroll_levin => sorceryScroll(cx, cy, px, .levin),
        .scroll_siphon => sorceryScroll(cx, cy, px, .siphon),
        .scroll_lance => sorceryScroll(cx, cy, px, .lance),
        .scroll_sunder => sorceryScroll(cx, cy, px, .sunder),
        .kiln_draught => kilnDraught(cx, cy, px),
        .rimewax => rimewax(cx, cy, px),
        .pilgrims_offering => pilgrimsOffering(cx, cy, px),
        .envenomed_dagger => envenomedDagger(cx, cy, px),
        .spidersilk_moccasins => spidersilkMoccasins(cx, cy, px),
        .bloodtinge_signet => bloodtingeSignet(cx, cy, px),
        .loop_of_chance => loopOfChance(cx, cy, px),
        .nightcap_grease => nightcapGrease(cx, cy, px),
        .wakers_nail => wakersNail(cx, cy, px),
        .madcap_powder => madcapPowder(cx, cy, px),
        .stolen_gravebell => stolenGravebell(cx, cy, px),
        .bloodwine => bloodwine(cx, cy, px),
        .wax_stopped_hood => waxStoppedHood(cx, cy, px),
        .scroll_babble => sorceryScroll(cx, cy, px, .babble),
        .scroll_bidding => sorceryScroll(cx, cy, px, .bidding),
    }
}

const SLEEP_WAX = rgba(150, 158, 206, 255);
const SLEEP_WAX_DK = rgba(96, 104, 152, 255);
const GILL_DUST = rgba(186, 208, 96, 255);
const GILL_DUST_DK = rgba(126, 144, 58, 255);
const CHARM_ROSE = rgba(228, 122, 172, 255);
const WINE_BLACK = rgba(46, 18, 26, 255);
const WINE_RED = rgba(140, 26, 40, 255);
const PAPER = rgba(206, 192, 156, 255);
const PAPER_DK = rgba(160, 144, 112, 255);

/// **ONE JAR, THREE FATS.** "Same cloth, same cord, only the fat swapped" is the law all three greases are
/// written under, and all three drew it out by hand. Split in two calls rather than one, because the tallow
/// threads its wick BETWEEN them — behind the lump, which is where a wick goes.
fn greaseRag(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.12 + 1.2 * k), s * 0.25, rgba(0, 0, 0, 115));
    quad(v2(cx - s * 0.23, cy + s * 0.02), v2(cx + s * 0.22, cy + s * 0.05), v2(cx + s * 0.15, cy + s * 0.30), v2(cx - s * 0.17, cy + s * 0.27), SALT);
    rl.drawLineEx(v2(cx - s * 0.23, cy + s * 0.04), v2(cx - s * 0.33, cy - s * 0.04), 3.4 * k, CORD);
}

fn greaseFat(cx: f32, cy: f32, px: f32, rng: *mathx.Rng, fat: rl.Color, dk: rl.Color, glint: rl.Color) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx - s * 0.02, cy - s * 0.03), s * 0.165, fat);
    rl.drawCircleV(v2(cx + s * 0.11 + rng.range(-1.2, 1.2) * k, cy + s * 0.01), s * 0.115, dk);
    rl.drawCircleV(v2(cx - s * 0.09, cy - s * 0.08), s * 0.05, glint);
}

/// **THE THIRD JAR ON THE TALLOW'S SHELF AND IT READS AS THE THIRD** (`rimewax`'s law) — same cloth, same cord,
/// only the fat swapped.
fn nightcapGrease(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x51EE);
    greaseRag(cx, cy, px);
    greaseFat(cx, cy, px, &rng, SLEEP_WAX, SLEEP_WAX_DK, rgba(216, 222, 250, 255));
    rl.drawLineEx(v2(cx + s * 0.04, cy + s * 0.09), v2(cx + s * 0.06, cy + s * 0.26), 2.0 * k, SLEEP_WAX_DK);
}

/// A NAIL BENT INTO A RING and not a cast band — the head still stands proud of the circle.
fn wakersNail(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.04 + 1.0 * k), s * 0.20, SHADOW);
    arc(cx, cy + s * 0.03, s * 0.175, std.math.pi * 0.10, std.math.tau * 0.97, 20, s * 0.052, s * 0.030, IRON_DK);
    arc(cx - s * 0.02, cy + s * 0.01, s * 0.150, std.math.pi * 1.00, std.math.pi * 1.55, 8, 1.6 * k, 0.9 * k, rgba(158, 150, 138, 220));
    quad(
        v2(cx + s * 0.14, cy - s * 0.19),
        v2(cx + s * 0.26, cy - s * 0.15),
        v2(cx + s * 0.23, cy - s * 0.05),
        v2(cx + s * 0.12, cy - s * 0.09),
        RUST,
    );
    rl.drawLineEx(v2(cx + s * 0.15, cy - s * 0.16), v2(cx + s * 0.24, cy - s * 0.13), 1.3 * k, rgba(176, 122, 82, 255));
    rl.drawLineEx(v2(cx - s * 0.15, cy + s * 0.16), v2(cx - s * 0.05, cy + s * 0.20), 1.4 * k, rgba(96, 88, 78, 255));
}

/// A PAPER TWIST WITH ITS SEAM ALREADY GOING — the dust leaking out is the only thing that says which powder.
fn madcapPowder(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x9A5D);
    rl.drawCircleV(v2(cx + 1.1 * k, cy + s * 0.10 + 1.3 * k), s * 0.23, rgba(0, 0, 0, 112));
    quad(v2(cx - s * 0.19, cy - s * 0.09), v2(cx + s * 0.20, cy - s * 0.13), v2(cx + s * 0.17, cy + s * 0.21), v2(cx - s * 0.21, cy + s * 0.17), PAPER);
    quad(v2(cx - s * 0.19, cy - s * 0.09), v2(cx - s * 0.02, cy - s * 0.11), v2(cx - s * 0.04, cy + s * 0.19), v2(cx - s * 0.21, cy + s * 0.17), PAPER_DK);
    // Neither on the axis and neither the same length.
    rl.drawLineEx(v2(cx - s * 0.03, cy - s * 0.11), v2(cx + s * 0.05, cy - s * 0.30), 3.2 * k, PAPER_DK);
    rl.drawLineEx(v2(cx - s * 0.06, cy + s * 0.18), v2(cx - s * 0.16, cy + s * 0.32), 2.8 * k, PAPER_DK);
    rl.drawLineEx(v2(cx - s * 0.10, cy - s * 0.05), v2(cx + s * 0.09, cy + s * 0.15), 1.2 * k, rgba(140, 126, 96, 200));
    var i: u32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const r = s * rng.range(0.20, 0.34);
        rl.drawCircleV(v2(cx + mathx.cosf(a) * r, cy + s * 0.04 + mathx.sinf(a) * r * 0.7), s * rng.range(0.018, 0.040), if (i % 2 == 0) GILL_DUST else GILL_DUST_DK);
    }
}

/// A HAND-BELL, not the summoning bell (`bell`): a HANDLE where that one has a crown.
fn stolenGravebell(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x6BE1);
    const lean = rng.range(-0.7, 0.7) * k;
    const mouthY = cy + s * 0.22;
    const hw = s * 0.195;
    rl.drawCircleV(v2(cx + 1.2 * k, mouthY + 1.4 * k), s * 0.22, rgba(0, 0, 0, 112));
    quad(
        v2(cx - s * 0.085 + lean, cy - s * 0.14),
        v2(cx + s * 0.085 + lean, cy - s * 0.14),
        v2(cx + hw, mouthY),
        v2(cx - hw, mouthY),
        BRONZE,
    );
    quad(
        v2(cx - s * 0.085 + lean, cy - s * 0.14),
        v2(cx - s * 0.010 + lean, cy - s * 0.14),
        v2(cx - hw * 0.40, mouthY),
        v2(cx - hw, mouthY),
        BRONZE_DK,
    );
    ellipseV(cx, mouthY, hw, s * 0.036, BRONZE_BORE);
    arc(cx + lean * 0.5, cy - s * 0.22, s * 0.070, std.math.pi * 1.02, std.math.tau * 0.99, 10, 2.9 * k, 2.4 * k, BRONZE_LT);
    rl.drawLineEx(v2(cx + lean * 0.5, cy - s * 0.29), v2(cx + lean * 0.5 + s * 0.02, cy - s * 0.36), 3.0 * k, rgba(120, 92, 52, 255));
    // Off the middle: a bell hanging true is a bell nobody has rung.
    rl.drawCircleV(v2(cx + s * 0.045, mouthY - s * 0.045), s * 0.042, rgba(84, 62, 30, 255));
    arc(cx + s * 0.09, cy - s * 0.02, s * 0.10, std.math.pi * 1.30, std.math.pi * 1.94, 8, 1.5 * k, 0.6 * k, rgba(238, 220, 176, 130));
}

/// A BOTTLE WITH THE RED SETTLED OUT OF IT: the sediment in the bottom is the whole picture.
fn bloodwine(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx + 1.1 * k, cy + s * 0.20 + 1.3 * k), s * 0.22, rgba(0, 0, 0, 118));
    quad(v2(cx - s * 0.155, cy - s * 0.05), v2(cx + s * 0.155, cy - s * 0.05), v2(cx + s * 0.175, cy + s * 0.30), v2(cx - s * 0.175, cy + s * 0.30), WINE_BLACK);
    quad(v2(cx - s * 0.155, cy + s * 0.13), v2(cx + s * 0.165, cy + s * 0.13), v2(cx + s * 0.175, cy + s * 0.30), v2(cx - s * 0.175, cy + s * 0.30), WINE_RED);
    rl.drawLineEx(v2(cx - s * 0.09, cy + s * 0.00), v2(cx - s * 0.10, cy + s * 0.26), 2.0 * k, rgba(96, 34, 44, 200));
    quad(v2(cx - s * 0.055, cy - s * 0.28), v2(cx + s * 0.055, cy - s * 0.28), v2(cx + s * 0.075, cy - s * 0.05), v2(cx - s * 0.075, cy - s * 0.05), rgba(62, 26, 32, 255));
    rl.drawCircleV(v2(cx, cy - s * 0.30), s * 0.062, CORK);
    rl.drawLineEx(v2(cx - s * 0.05, cy - s * 0.31), v2(cx + s * 0.05, cy - s * 0.29), 1.2 * k, rgba(112, 86, 52, 255));
    rl.drawCircleV(v2(cx - s * 0.055, cy - s * 0.13), s * 0.030, rgba(196, 120, 118, 120));
}

/// **THE EARS ARE THE ITEM** — a hood is a hood at 34 px, so the two wax plugs and the stitching carry it.
fn waxStoppedHood(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    const cloth = rgba(118, 108, 92, 255);
    const clothLo = rgba(76, 70, 60, 255);
    const wax = rgba(232, 222, 186, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.08 + 1.4 * k), s * 0.25, rgba(0, 0, 0, 112));
    arc(cx, cy + s * 0.06, s * 0.235, std.math.pi * 0.98, std.math.tau * 1.02, 16, s * 0.24, s * 0.15, clothLo);
    arc(cx - s * 0.02, cy + s * 0.05, s * 0.195, std.math.pi * 1.06, std.math.pi * 1.90, 12, s * 0.17, s * 0.09, cloth);
    quad(v2(cx - s * 0.24, cy + s * 0.05), v2(cx - s * 0.11, cy + s * 0.05), v2(cx - s * 0.15, cy + s * 0.31), v2(cx - s * 0.29, cy + s * 0.26), clothLo);
    quad(v2(cx + s * 0.11, cy + s * 0.05), v2(cx + s * 0.24, cy + s * 0.05), v2(cx + s * 0.27, cy + s * 0.22), v2(cx + s * 0.14, cy + s * 0.26), cloth);
    var e: u32 = 0;
    while (e < 2) : (e += 1) {
        const sx: f32 = if (e == 0) -1.0 else 1.0;
        const x = cx + sx * s * 0.185;
        const y = cy + s * 0.015 + sx * s * 0.012;
        rl.drawCircleV(v2(x, y), s * 0.072, wax);
        rl.drawCircleV(v2(x - sx * s * 0.018, y - s * 0.018), s * 0.030, rgba(250, 244, 218, 255));
        var t: u32 = 0;
        while (t < 4) : (t += 1) {
            const ty = y - s * 0.055 + @as(f32, @floatFromInt(t)) * s * 0.037;
            rl.drawLineEx(v2(x - s * 0.075, ty), v2(x + s * 0.075, ty - s * 0.008), 1.2 * k, rgba(52, 46, 38, 210));
        }
    }
}

fn purgeleaf(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x9EAF);
    const leaf = rgba(96, 118, 84, 255);
    const leafLo = rgba(58, 74, 52, 255);
    const rib = rgba(178, 190, 150, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.04 + 1.4 * k), s * 0.25, rgba(0, 0, 0, 105));
    const tip = v2(cx + s * 0.20, cy - s * 0.26);
    const base = v2(cx - s * 0.14, cy + s * 0.25);
    quad(v2(base.x, base.y), v2(cx - s * 0.20, cy - s * 0.02), tip, v2(cx + s * 0.04, cy + s * 0.10), leafLo);
    quad(v2(base.x, base.y), v2(cx + s * 0.02, cy + s * 0.02), tip, v2(cx + s * 0.19, cy + s * 0.04), leaf);
    rl.drawLineEx(base, tip, 2.0 * k, rib);
    rl.drawCircleV(tip, 1.7 * k, rib);
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const t = 0.22 + @as(f32, @floatFromInt(i)) * 0.19;
        const on = v2(base.x + (tip.x - base.x) * t, base.y + (tip.y - base.y) * t);
        const side: f32 = if (i % 2 == 0) 1.0 else -1.0;
        rl.drawLineEx(on, v2(on.x + side * s * rng.range(0.08, 0.15), on.y - s * rng.range(0.02, 0.07)), 1.2 * k, rgba(140, 154, 118, 210));
    }
    rl.drawLineEx(base, v2(cx - s * 0.24, cy + s * 0.31), 2.4 * k, leafLo);
    rl.drawCircleV(v2(cx - s * 0.24, cy + s * 0.31), 1.6 * k, CAP_LT);
}

fn pilgrimsSalt(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x5A17);
    const grey = rgba(198, 194, 184, 255);
    const greyLo = rgba(142, 138, 130, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.06 + 1.4 * k), s * 0.26, SHADOW);
    quad(v2(cx - s * 0.26, cy - s * 0.02), v2(cx + s * 0.26, cy - s * 0.06), v2(cx + s * 0.24, cy + s * 0.24), v2(cx - s * 0.25, cy + s * 0.26), greyLo);
    quad(v2(cx - s * 0.26, cy - s * 0.02), v2(cx - s * 0.06, cy - s * 0.22), v2(cx + s * 0.28, cy - s * 0.25), v2(cx + s * 0.26, cy - s * 0.06), grey);
    rl.drawCircleV(v2(cx + s * 0.06, cy - s * 0.13), s * 0.075, rgba(172, 168, 158, 255));
    rl.drawCircleV(v2(cx + s * 0.05, cy - s * 0.145), s * 0.050, SALT);
    rl.drawLineEx(v2(cx - s * 0.01, cy - s * 0.05), v2(cx - s * 0.02, cy + s * 0.25), 1.3 * k, rgba(118, 114, 108, 200));
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        rl.drawCircleV(v2(cx - s * 0.24 + rng.range(-1.5, 1.5) * k, cy + s * 0.02 + @as(f32, @floatFromInt(i)) * s * 0.070), s * rng.range(0.018, 0.034), rgba(216, 212, 202, 255));
    }
}

fn ironwortTea(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    const clay = rgba(104, 78, 58, 255);
    const clayLo = rgba(68, 50, 38, 255);
    const brew = rgba(126, 66, 34, 255);
    const brewLt = rgba(172, 100, 52, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.14 + 1.4 * k), s * 0.26, SHADOW);
    quad(v2(cx - s * 0.27, cy - s * 0.02), v2(cx + s * 0.28, cy - s * 0.04), v2(cx + s * 0.18, cy + s * 0.26), v2(cx - s * 0.16, cy + s * 0.27), clay);
    arc(cx + s * 0.005, cy + s * 0.26, s * 0.17, std.math.pi * 0.06, std.math.pi * 0.94, 10, 2.6 * k, 2.2 * k, clayLo);
    ellipseV(cx + s * 0.005, cy - s * 0.03, s * 0.275, s * 0.075, brew);
    ellipseV(cx - s * 0.03, cy - s * 0.045, s * 0.185, s * 0.042, brewLt);
    rl.drawLineEx(v2(cx + s * 0.10, cy - s * 0.055), v2(cx + s * 0.20, cy - s * 0.19), 2.4 * k, ROOT_BARK);
    rl.drawLineEx(v2(cx + s * 0.20, cy - s * 0.19), v2(cx + s * 0.16, cy - s * 0.27), 2.0 * k, ROOT_BARK);
    rl.drawCircleV(v2(cx + s * 0.16, cy - s * 0.27), 1.8 * k, ROOT_HEART);
    arc(cx - s * 0.12, cy - s * 0.19, s * 0.10, std.math.pi * 1.2, std.math.pi * 1.9, 8, 1.7 * k, 0.7 * k, rgba(238, 232, 220, 130));
    arc(cx - s * 0.03, cy - s * 0.27, s * 0.08, std.math.pi * 1.25, std.math.pi * 1.95, 8, 1.4 * k, 0.6 * k, rgba(238, 232, 220, 95));
}

fn rimewardMantle(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x21CE);
    const hide = rgba(84, 74, 62, 255);
    const hideLo = rgba(54, 48, 40, 255);
    const fleece = rgba(196, 190, 176, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.06 + 1.4 * k), s * 0.27, SHADOW);
    quad(v2(cx - s * 0.15, cy - s * 0.14), v2(cx + s * 0.15, cy - s * 0.14), v2(cx + s * 0.29, cy + s * 0.28), v2(cx - s * 0.29, cy + s * 0.28), hide);
    quad(v2(cx - s * 0.15, cy - s * 0.14), v2(cx + s * 0.01, cy - s * 0.14), v2(cx + s * 0.06, cy + s * 0.28), v2(cx - s * 0.29, cy + s * 0.28), hideLo);
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / 5.0;
        const x = cx - s * 0.24 + t * s * 0.48;
        rl.drawCircleV(v2(x, cy - s * 0.19 + rng.range(-1.6, 1.6) * k), s * rng.range(0.055, 0.082), fleece);
    }
    i = 0;
    while (i < 5) : (i += 1) {
        const x = cx - s * 0.24 + @as(f32, @floatFromInt(i)) * s * 0.12;
        rl.drawLineEx(v2(x, cy + s * 0.24), v2(x + rng.range(-1.5, 1.5) * k, cy + s * 0.31), 1.8 * k, rgba(150, 144, 132, 235));
    }
    // THE COLD ON IT — frost along the shoulder, and nothing else in the cell is blue: what this coat is FOR has to be readable in a 33 px bag cell.
    arc(cx, cy - s * 0.12, s * 0.21, std.math.pi * 1.10, std.math.pi * 1.90, 10, 2.2 * k, 1.0 * k, RIME_ICE);
    rl.drawCircleV(v2(cx - s * 0.13, cy - s * 0.06), 1.7 * k, RIME_LT);
    rl.drawCircleV(v2(cx + s * 0.15, cy - s * 0.02), 1.4 * k, RIME_LT);
}

fn sporecrown(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x5C40);
    const fibre = rgba(146, 96, 66, 255);
    const fibreLo = rgba(96, 60, 42, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.06 + 1.4 * k), s * 0.25, SHADOW);
    arc(cx, cy + s * 0.10, s * 0.255, std.math.pi, std.math.tau, 14, s * 0.26, s * 0.14, fibreLo);
    arc(cx - s * 0.02, cy + s * 0.09, s * 0.215, std.math.pi * 1.06, std.math.pi * 1.88, 12, s * 0.18, s * 0.09, fibre);
    var c: u32 = 0;
    while (c < 3) : (c += 1) {
        const rr = s * (0.10 + @as(f32, @floatFromInt(c)) * 0.058);
        arc(cx, cy + s * 0.10, rr, std.math.pi * 1.04, std.math.pi * 1.96, 10, 1.5 * k, 1.0 * k, rgba(178, 126, 90, 200));
    }
    rl.drawLineEx(v2(cx - s * 0.27, cy + s * 0.11), v2(cx + s * 0.27, cy + s * 0.10), 4.2 * k, fibreLo);
    var i: u32 = 0;
    while (i < 7) : (i += 1) {
        const x = cx - s * 0.24 + @as(f32, @floatFromInt(i)) * s * 0.080;
        rl.drawLineEx(v2(x, cy + s * 0.075), v2(x + s * 0.045, cy + s * 0.145), 1.5 * k, rgba(186, 134, 96, 220));
    }
    i = 0;
    while (i < 5) : (i += 1) {
        const x = cx - s * 0.19 + @as(f32, @floatFromInt(i)) * s * 0.095;
        rl.drawCircleV(v2(x + rng.range(-1.2, 1.2) * k, cy + s * 0.165), s * rng.range(0.024, 0.042), SHROOM_CREAM);
    }
}

fn gravebellAmulet(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    const bronze = BRONZE;
    const bronzeLo = BRONZE_DK;
    const bronzeLt = BRONZE_LT;
    const cord = rgba(72, 60, 48, 255);
    const top = cy - s * 0.29;
    rl.drawLineEx(v2(cx - s * 0.16, top), v2(cx - s * 0.02, cy - s * 0.10), 1.8 * k, cord);
    rl.drawLineEx(v2(cx + s * 0.15, top - s * 0.01), v2(cx + s * 0.03, cy - s * 0.10), 1.8 * k, cord);
    arc(cx, top + s * 0.01, s * 0.15, std.math.pi * 1.08, std.math.pi * 1.92, 8, 1.6 * k, 1.6 * k, cord);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.10 + 1.4 * k), s * 0.24, rgba(0, 0, 0, 115));
    quad(v2(cx - s * 0.10, cy - s * 0.11), v2(cx + s * 0.10, cy - s * 0.11), v2(cx + s * 0.23, cy + s * 0.19), v2(cx - s * 0.23, cy + s * 0.19), bronzeLo);
    quad(v2(cx - s * 0.10, cy - s * 0.11), v2(cx + s * 0.01, cy - s * 0.11), v2(cx + s * 0.08, cy + s * 0.19), v2(cx - s * 0.23, cy + s * 0.19), bronze);
    arc(cx, cy - s * 0.10, s * 0.105, std.math.pi, std.math.tau, 8, s * 0.10, s * 0.05, bronze);
    ellipseV(cx, cy + s * 0.20, s * 0.235, s * 0.058, bronzeLo);
    ellipseV(cx, cy + s * 0.185, s * 0.215, s * 0.045, bronzeLt);
    ellipseV(cx, cy + s * 0.195, s * 0.155, s * 0.030, BRONZE_BORE);
    rl.drawLineEx(v2(cx + s * 0.12, cy + s * 0.18), v2(cx + s * 0.07, cy + s * 0.02), 1.6 * k, rgba(30, 24, 14, 235));
    rl.drawLineEx(v2(cx + s * 0.07, cy + s * 0.02), v2(cx + s * 0.10, cy - s * 0.09), 1.4 * k, rgba(30, 24, 14, 235));
    arc(cx + s * 0.22, cy + s * 0.02, s * 0.11, std.math.pi * 1.25, std.math.pi * 1.92, 8, 1.6 * k, 0.6 * k, rgba(238, 226, 190, 120));
}

/// **WHICH PICTURE A SORCERY IS, AND THE ONE PLACE IT IS DECIDED** — `drawHeld`'s own shape one enum along. One list of five lived at the HUD's cross AND the book's socket, differing only in how each spelled "can he afford it". `lit` is that affordability.
pub fn spellArt(s: combat.Spell, cx: f32, cy: f32, px: f32, lit: bool) void {
    switch (s) {
        .bolt => spell(cx, cy, px, lit),
        .roots => roots(cx, cy, px, lit),
        .rime => rime(cx, cy, px, lit),
        .levin => levin(cx, cy, px, lit),
        .siphon => siphon(cx, cy, px, lit),
        .lance => lance(cx, cy, px, lit),
        .sunder => sunder(cx, cy, px, lit),
        .babble => babble(cx, cy, px, lit),
        .bidding => bidding(cx, cy, px, lit),
    }
}

/// **THREE MOUTHS AND NO TWO SAYING THE SAME THING.** The confusion meter's colour, so the icon and the bar agree.
fn babble(cx: f32, cy: f32, px: f32, lit: bool) void {
    const s = px;
    const k = strokeK(px);
    const hot = dimmed(rgba(172, 202, 82, 255), lit);
    const cool = dimmed(rgba(112, 138, 46, 255), lit);
    const rows = [_][4]f32{ .{ -0.16, -0.14, 0.20, 0.20 }, .{ 0.10, 0.02, 0.27, -0.35 }, .{ -0.04, 0.22, 0.15, 0.70 } };
    for (rows, 0..) |r, i| {
        const ox = cx + s * r[0];
        const oy = cy + s * r[1];
        const rr = s * r[2];
        const tilt = r[3];
        arc(ox, oy, rr, std.math.pi * (0.20 + tilt), std.math.pi * (0.86 + tilt), 9, 2.6 * k, 1.5 * k, if (i == 1) hot else cool);
        arc(ox, oy, rr * 0.58, std.math.pi * (0.28 + tilt), std.math.pi * (0.80 + tilt), 7, 1.8 * k, 1.0 * k, if (i == 1) cool else hot);
    }
    rl.drawCircleV(v2(cx + s * 0.30, cy - s * 0.24), 1.9 * k, hot);
    rl.drawCircleV(v2(cx - s * 0.30, cy + s * 0.28), 1.6 * k, cool);
}

/// **A HAND HELD OUT WITH A COIN IN IT.** Not a crown and not a chain: this spell PAYS. Charm's rose, for the
/// babble's reason.
fn bidding(cx: f32, cy: f32, px: f32, lit: bool) void {
    const s = px;
    const k = strokeK(px);
    const rose = dimmed(CHARM_ROSE, lit);
    const roseLo = dimmed(rgba(158, 74, 112, 255), lit);
    const coin = dimmed(rgba(240, 216, 148, 255), lit);
    arc(cx - s * 0.02, cy + s * 0.10, s * 0.235, std.math.pi * 0.06, std.math.pi * 0.96, 12, 4.6 * k, 3.0 * k, roseLo);
    arc(cx - s * 0.02, cy + s * 0.08, s * 0.190, std.math.pi * 0.12, std.math.pi * 0.90, 10, 2.2 * k, 1.4 * k, rose);
    rl.drawLineEx(v2(cx - s * 0.25, cy + s * 0.07), v2(cx - s * 0.31, cy - s * 0.08), 3.4 * k, roseLo);
    var f: u32 = 0;
    while (f < 3) : (f += 1) {
        const x = cx - s * 0.06 + @as(f32, @floatFromInt(f)) * s * 0.115;
        rl.drawLineEx(v2(x, cy + s * 0.30), v2(x + s * 0.02, cy + s * 0.34), 1.6 * k, roseLo);
    }
    rl.drawCircleV(v2(cx + s * 0.03, cy - s * 0.12), s * 0.105, coin);
    rl.drawCircleV(v2(cx + s * 0.03, cy - s * 0.12), s * 0.042, dimmed(rgba(150, 116, 52, 255), lit));
    arc(cx + s * 0.03, cy - s * 0.12, s * 0.155, std.math.pi * 1.10, std.math.pi * 1.80, 8, 1.5 * k, 0.6 * k, dimmed(rgba(252, 240, 200, 150), lit));
}

fn lance(cx: f32, cy: f32, px: f32, lit: bool) void {
    const s = px;
    const k = strokeK(px);
    const hot = dimmed(FIRE, lit);
    const edge = dimmed(FIRE_DIM, lit);
    const from = v2(cx - s * 0.30, cy + s * 0.24);
    const to = v2(cx + s * 0.32, cy - s * 0.26);
    rl.drawLineEx(from, to, 5.4 * k, edge);
    rl.drawLineEx(from, to, 2.2 * k, hot);
    rl.drawCircleV(to, 3.0 * k, hot);
    rl.drawCircleV(v2(to.x - s * 0.05, to.y + s * 0.04), 2.0 * k, dimmed(rgba(255, 226, 170, 255), lit));
    rl.drawCircleV(onAxis(from, to, 0.42, 0), 3.4 * k, dimmed(rgba(58, 44, 36, 255), lit));
    rl.drawCircleV(onAxis(from, to, 0.68, 0), 3.0 * k, dimmed(rgba(58, 44, 36, 255), lit));
    rl.drawLineEx(onAxis(from, to, 0.42, -s * 0.055), onAxis(from, to, 0.42, s * 0.075), 1.5 * k, edge);
    rl.drawLineEx(onAxis(from, to, 0.68, -s * 0.065), onAxis(from, to, 0.68, s * 0.055), 1.4 * k, edge);
    rl.drawLineEx(from, onAxis(from, to, 0.14, 0), 2.6 * k, dimmed(rgba(196, 88, 30, 130), lit));
}

fn sunder(cx: f32, cy: f32, px: f32, lit: bool) void {
    const s = px;
    const k = strokeK(px);
    const board = dimmed(rgba(96, 72, 50, 255), lit);
    const boardLo = dimmed(rgba(62, 46, 32, 255), lit);
    const iron = dimmed(rgba(148, 142, 132, 255), lit);
    const split = dimmed(rgba(246, 240, 226, 255), lit);
    quad(v2(cx - s * 0.24, cy - s * 0.24), v2(cx + s * 0.24, cy - s * 0.24), v2(cx + s * 0.20, cy + s * 0.10), v2(cx - s * 0.20, cy + s * 0.10), boardLo);
    quad(v2(cx - s * 0.24, cy - s * 0.24), v2(cx + s * 0.02, cy - s * 0.24), v2(cx + s * 0.01, cy + s * 0.10), v2(cx - s * 0.20, cy + s * 0.10), board);
    quad(v2(cx - s * 0.20, cy + s * 0.10), v2(cx + s * 0.20, cy + s * 0.10), v2(cx, cy + s * 0.31), v2(cx, cy + s * 0.31), boardLo);
    rl.drawLineEx(v2(cx - s * 0.24, cy - s * 0.21), v2(cx + s * 0.24, cy - s * 0.21), 2.4 * k, iron);
    rl.drawLineEx(v2(cx - s * 0.16, cy - s * 0.26), v2(cx - s * 0.02, cy - s * 0.04), 2.6 * k, split);
    rl.drawLineEx(v2(cx - s * 0.02, cy - s * 0.04), v2(cx + s * 0.09, cy + s * 0.09), 2.2 * k, split);
    rl.drawLineEx(v2(cx + s * 0.09, cy + s * 0.09), v2(cx + s * 0.05, cy + s * 0.29), 1.8 * k, split);
    rl.drawCircleV(v2(cx + s * 0.17, cy - s * 0.14), 2.0 * k, boardLo);
    rl.drawCircleV(v2(cx + s * 0.25, cy - s * 0.02), 1.6 * k, boardLo);
    rl.drawCircleV(v2(cx + s * 0.21, cy + s * 0.15), 1.3 * k, boardLo);
}

fn pittedHelm(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x4E1);
    const iron = rgba(132, 124, 112, 255);
    const ironLo = rgba(88, 82, 74, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.02 + 1.4 * k), s * 0.26, rgba(0, 0, 0, 115));
    rl.drawCircleV(v2(cx, cy - s * 0.03), s * 0.245, ironLo);
    rl.drawCircleV(v2(cx - s * 0.03, cy - s * 0.06), s * 0.205, iron);
    arc(cx - s * 0.02, cy - s * 0.05, s * 0.20, std.math.pi * 1.06, std.math.pi * 1.62, 10, 2.0 * k, 1.0 * k, rgba(186, 178, 162, 255));
    quad(v2(cx - s * 0.235, cy + s * 0.02), v2(cx + s * 0.235, cy + s * 0.02), v2(cx + s * 0.185, cy + s * 0.24), v2(cx - s * 0.185, cy + s * 0.24), ironLo);
    quad(v2(cx - s * 0.125, cy + s * 0.05), v2(cx + s * 0.125, cy + s * 0.05), v2(cx + s * 0.10, cy + s * 0.20), v2(cx - s * 0.10, cy + s * 0.20), rgba(14, 12, 10, 240));
    rl.drawLineEx(v2(cx, cy + s * 0.04), v2(cx, cy + s * 0.13), 1.6 * k, iron);
    quad(v2(cx - s * 0.24, cy - s * 0.03), v2(cx + s * 0.24, cy - s * 0.03), v2(cx + s * 0.235, cy + s * 0.04), v2(cx - s * 0.235, cy + s * 0.04), rgba(160, 152, 138, 255));
    rl.drawCircleV(v2(cx - s * 0.17, cy + s * 0.005), 1.5 * k, rgba(70, 64, 56, 255));
    rl.drawCircleV(v2(cx + s * 0.17, cy + s * 0.005), 1.5 * k, rgba(70, 64, 56, 255));
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const fy = cy + s * 0.04 + @as(f32, @floatFromInt(i)) * s * 0.062;
        rl.drawCircleV(v2(cx - s * 0.155 + rng.range(-1.5, 1.5) * k, fy), s * rng.range(0.020, 0.040), RUST);
    }
}

fn ashenAmulet(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xA5BE);
    const cord = rgba(72, 60, 48, 255);
    const top = cy - s * 0.28;
    rl.drawLineEx(v2(cx - s * 0.16, top), v2(cx - s * 0.015, cy + s * 0.08), 1.8 * k, cord);
    rl.drawLineEx(v2(cx + s * 0.15 + rng.range(-1, 1) * k, top - s * 0.01), v2(cx + s * 0.02, cy + s * 0.08), 1.8 * k, cord);
    arc(cx, top + s * 0.01, s * 0.16, std.math.pi * 1.08, std.math.pi * 1.92, 8, 1.6 * k, 1.6 * k, cord);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.15 + 1.2 * k), s * 0.115, SHADOW);
    rl.drawCircleV(v2(cx, cy + s * 0.13), s * 0.105, rgba(122, 118, 112, 255));
    arc(cx, cy + s * 0.13, s * 0.075, std.math.pi * 0.85, std.math.pi * 1.55, 8, 1.5 * k, 0.8 * k, rgba(176, 170, 160, 255));
    rl.drawCircleV(v2(cx - s * 0.03, cy + s * 0.09), 1.6 * k, rgba(236, 214, 176, 210));
    rl.drawCircleV(v2(cx + s * 0.04, cy + s * 0.18), s * 0.022, rgba(74, 70, 66, 255));
}

fn bandedWarbelt(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xBE17);
    const hide = rgba(88, 62, 42, 255);
    const hideLt = rgba(126, 92, 62, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + 1.4 * k), s * 0.26, rgba(0, 0, 0, 105));
    quad(v2(cx - s * 0.34, cy - s * 0.09), v2(cx + s * 0.30, cy - s * 0.12), v2(cx + s * 0.30, cy + s * 0.05), v2(cx - s * 0.34, cy + s * 0.08), hide);
    quad(v2(cx - s * 0.34, cy - s * 0.09), v2(cx + s * 0.30, cy - s * 0.12), v2(cx + s * 0.30, cy - s * 0.07), v2(cx - s * 0.34, cy - s * 0.04), hideLt);
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const bx = cx - s * 0.20 + @as(f32, @floatFromInt(i)) * s * 0.155 + rng.range(-2, 2) * k;
        quad(v2(bx, cy - s * 0.11), v2(bx + s * 0.035, cy - s * 0.11), v2(bx + s * 0.035, cy + s * 0.07), v2(bx, cy + s * 0.07), rgba(96, 88, 78, 255));
    }
    quad(v2(cx - s * 0.36, cy - s * 0.15), v2(cx - s * 0.20, cy - s * 0.15), v2(cx - s * 0.20, cy + s * 0.13), v2(cx - s * 0.36, cy + s * 0.13), rgba(140, 130, 116, 255));
    quad(v2(cx - s * 0.32, cy - s * 0.09), v2(cx - s * 0.24, cy - s * 0.09), v2(cx - s * 0.24, cy + s * 0.07), v2(cx - s * 0.32, cy + s * 0.07), rgba(24, 20, 18, 225));
    rl.drawLineEx(v2(cx - s * 0.28, cy - s * 0.13), v2(cx - s * 0.28, cy + s * 0.11), 1.8 * k, rgba(170, 160, 144, 255));
    rl.drawCircleV(v2(cx + s * 0.13, cy - s * 0.03), 1.7 * k, rgba(30, 22, 16, 235));
    rl.drawCircleV(v2(cx + s * 0.22, cy - s * 0.04), 1.5 * k, rgba(30, 22, 16, 200));
}

fn marchboots(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    const hide = rgba(74, 56, 42, 255);
    const hideDk = rgba(46, 34, 26, 255);
    const sole = rgba(58, 50, 44, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.18 + 1.4 * k), s * 0.26, SHADOW);
    quad(v2(cx - s * 0.02, cy - s * 0.24), v2(cx + s * 0.15, cy - s * 0.24), v2(cx + s * 0.17, cy + s * 0.10), v2(cx - s * 0.01, cy + s * 0.10), hideDk);
    quad(v2(cx - s * 0.01, cy + s * 0.05), v2(cx + s * 0.30, cy + s * 0.09), v2(cx + s * 0.30, cy + s * 0.17), v2(cx - s * 0.01, cy + s * 0.15), hideDk);
    quad(v2(cx - s * 0.26, cy - s * 0.20), v2(cx - s * 0.07, cy - s * 0.22), v2(cx - s * 0.05, cy + s * 0.14), v2(cx - s * 0.24, cy + s * 0.14), hide);
    quad(v2(cx - s * 0.27, cy - s * 0.20), v2(cx - s * 0.17, cy - s * 0.21), v2(cx - s * 0.15, cy - s * 0.09), v2(cx - s * 0.26, cy - s * 0.08), rgba(104, 80, 58, 255));
    quad(v2(cx - s * 0.25, cy + s * 0.09), v2(cx + s * 0.08, cy + s * 0.13), v2(cx + s * 0.08, cy + s * 0.21), v2(cx - s * 0.25, cy + s * 0.19), hide);
    quad(v2(cx - s * 0.26, cy + s * 0.19), v2(cx + s * 0.09, cy + s * 0.21), v2(cx + s * 0.09, cy + s * 0.26), v2(cx - s * 0.26, cy + s * 0.24), sole);
    rl.drawCircleV(v2(cx + s * 0.03, cy + s * 0.17), s * 0.03, rgba(112, 92, 70, 220));
    rl.drawLineEx(v2(cx - s * 0.20, cy - s * 0.10), v2(cx - s * 0.11, cy - s * 0.08), 1.2 * k, hideDk);
    rl.drawLineEx(v2(cx - s * 0.20, cy - s * 0.02), v2(cx - s * 0.10, cy), 1.2 * k, hideDk);
}

fn deftSignet(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.03 + 1.0 * k), s * 0.20, SHADOW);
    arc(cx, cy + s * 0.02, s * 0.175, 0, std.math.tau, 20, s * 0.062, s * 0.062, rgba(118, 112, 102, 255));
    arc(cx, cy + s * 0.02, s * 0.145, std.math.pi * 0.15, std.math.pi * 1.05, 12, 1.3 * k, 1.3 * k, rgba(206, 200, 186, 255));
    arc(cx - s * 0.03, cy - s * 0.01, s * 0.17, std.math.pi * 0.95, std.math.pi * 1.5, 8, 1.7 * k, 0.9 * k, rgba(168, 160, 146, 255));
    quad(v2(cx - s * 0.045, cy - s * 0.20), v2(cx + s * 0.045, cy - s * 0.20), v2(cx + s * 0.035, cy - s * 0.13), v2(cx - s * 0.035, cy - s * 0.13), rgba(142, 136, 124, 255));
}

/// THE SUMMONING BELL — a cross's picture, not a bag row: it is an ARMAMENT, drawn beside `sword` and `bow` and taking no `item.Kind`. The flare and the OPEN MOUTH are the whole read, since at 34 px a bell with a filled bottom is a thimble.
pub fn bell(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xBE11);
    const lean = rng.range(-0.6, 0.6) * k;
    const mouthY = cy + s * 0.24;
    const crownY = cy - s * 0.12;
    const hw = s * 0.215;
    const cw = s * 0.085;
    rl.drawCircleV(v2(cx + 1.2 * k, mouthY + 1.0 * k), hw, SHADOW);

    rl.drawLineEx(v2(cx + lean, cy - s * 0.36), v2(cx + lean, crownY), 3.6 * k, GRIP);
    rl.drawCircleV(v2(cx + lean, cy - s * 0.345), 2.6 * k, GRIP_LT);
    rl.drawCircleV(v2(cx + lean, cy - s * 0.245), 2.9 * k, GRIP);

    quad(v2(cx - cw + lean, crownY), v2(cx + cw + lean, crownY), v2(cx + hw, mouthY), v2(cx - hw, mouthY), BRONZE);
    arc(cx + lean, crownY + s * 0.015, cw, std.math.pi, std.math.tau, 10, s * 0.055, s * 0.055, BRONZE);
    rl.drawLineEx(v2(cx - cw * 0.8 + lean, crownY + s * 0.01), v2(cx - hw * 0.88, mouthY - s * 0.02), 1.6 * k, BRONZE_LT);
    const wy = mathx.lerpF(crownY, mouthY, 0.62);
    const ww = mathx.lerpF(cw, hw, 0.62);
    rl.drawLineEx(v2(cx - ww, wy), v2(cx + ww, wy), 1.8 * k, BRONZE_DK);

    rl.drawEllipse(@intFromFloat(cx), @intFromFloat(mouthY), hw, s * 0.075, BRONZE_LT);
    rl.drawEllipse(@intFromFloat(cx), @intFromFloat(mouthY), hw - 2.2 * k, s * 0.075 - 1.6 * k, BRONZE_BORE);
    rl.drawLineEx(v2(cx + s * 0.02, mouthY - s * 0.10), v2(cx + s * 0.055, mouthY + s * 0.005), 1.3 * k, BRONZE_DK);
    rl.drawCircleV(v2(cx + s * 0.055, mouthY + s * 0.02), 2.6 * k, BRONZE_LT);
}

fn spiritScroll(cx: f32, cy: f32, px: f32, glyph: SpiritGlyph) void {
    const s = px;
    const k = strokeK(px);
    scrollSheet(cx, cy, px);
    glyphOn(cx, cy - s * 0.03, s, k, glyph);
    scrollRoll(cx, cy, px);
}

/// One scroll picture in the game; the sigil inked on it is what says which scroll it is.
fn sorceryScroll(cx: f32, cy: f32, px: f32, sp: combat.Spell) void {
    const s = px;
    scrollSheet(cx, cy, px);
    spellArt(sp, cx, cy - s * 0.03, s * 0.34, true);
    scrollRoll(cx, cy, px);
}

fn scrollSheet(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x5C011);
    const lean = rng.range(-0.8, 0.8) * k;
    const hw = s * 0.21;
    const top = cy - s * 0.33;
    const rollY = cy + s * 0.26;
    rl.drawCircleV(v2(cx + 1.2 * k, rollY + 1.2 * k), hw * 1.02, SHADOW);

    const tl = v2(cx - hw * 1.06 + lean, top);
    const tr = v2(cx + hw * 1.02 + lean, top + s * 0.02);
    quad(tl, tr, v2(cx + hw * 0.94, rollY), v2(cx - hw * 0.96, rollY), HIDE);
    arc(cx + lean, top + s * 0.03, hw * 1.02, std.math.pi * 1.04, std.math.tau - 0.06, 10, s * 0.055, s * 0.035, HIDE_LT);
    rl.drawLineEx(v2(cx - hw * 0.96, rollY), v2(cx - hw * 1.06 + lean, top), 1.2 * k, HIDE_LT);
}

fn scrollRoll(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    const hw = s * 0.21;
    const rollY = cy + s * 0.26;
    rl.drawLineEx(v2(cx - hw, rollY), v2(cx + hw, rollY), s * 0.17, HIDE_DK);
    rl.drawLineEx(v2(cx - hw, rollY - s * 0.03), v2(cx + hw, rollY - s * 0.03), s * 0.05, HIDE);
    rl.drawCircleV(v2(cx - hw, rollY), s * 0.085, HIDE_DK);
    rl.drawCircleV(v2(cx + hw, rollY), s * 0.085, HIDE_DK);
    rl.drawCircleV(v2(cx + hw, rollY), s * 0.042, rgba(84, 68, 46, 255));
    rl.drawLineEx(v2(cx - s * 0.05, rollY - s * 0.10), v2(cx - s * 0.02, rollY + s * 0.09), 1.8 * k, CORD);
    rl.drawLineEx(v2(cx - s * 0.02, rollY + s * 0.09), v2(cx + s * 0.07, rollY + s * 0.13), 1.5 * k, CORD);
}

const SpiritGlyph = enum { wolf };

/// THE DRAWING, IN ONE UNBROKEN LINE — the flavour, and the only thing legible at 34 px. A whole body comes out as twelve pixels of mush, so what is inked is the HEAD IN PROFILE. The ear is the read; without it this is a dog or a fox.
fn glyphOn(cx: f32, cy: f32, s: f32, k: f32, glyph: SpiritGlyph) void {
    switch (glyph) {
        .wolf => {
            const w = 2.0 * k;
            const nose = v2(cx - s * 0.115, cy + s * 0.045);
            const stop = v2(cx - s * 0.025, cy - s * 0.005);
            const brow = v2(cx + s * 0.025, cy - s * 0.055);
            const ear = v2(cx + s * 0.045, cy - s * 0.135);
            const nape = v2(cx + s * 0.10, cy - s * 0.02);
            rl.drawLineEx(nose, stop, w, SPIRIT);
            rl.drawLineEx(stop, brow, w, SPIRIT);
            rl.drawLineEx(brow, ear, w, SPIRIT);
            rl.drawLineEx(ear, nape, w, SPIRIT);
            rl.drawLineEx(nose, v2(cx - s * 0.02, cy + s * 0.075), w * 0.85, SPIRIT);
            rl.drawLineEx(v2(cx - s * 0.02, cy + s * 0.075), v2(cx + s * 0.06, cy + s * 0.06), w * 0.85, SPIRIT);
            rl.drawCircleV(v2(cx - s * 0.115, cy + s * 0.045), w * 0.6, SPIRIT_LT);
            rl.drawCircleV(v2(cx - s * 0.005, cy + s * 0.005), 1.3 * k, SPIRIT_LT);
        },
    }
}

fn emberCandle(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xEB3A);
    const lean = rng.range(-1.2, 1.2) * k;
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.20 + 1.0 * k), s * 0.24, rgba(0, 0, 0, 120));
    rl.drawCircleV(v2(cx, cy + s * 0.20), s * 0.24, EMBER_FAT_DK);
    rl.drawCircleV(v2(cx - s * 0.03, cy + s * 0.16), s * 0.20, EMBER_FAT);
    rl.drawLineEx(v2(cx + s * 0.14, cy + s * 0.12), v2(cx + s * 0.17 + lean, cy + s * 0.32), 2.6 * k, EMBER_FAT);
    rl.drawLineEx(v2(cx - s * 0.18, cy + s * 0.18), v2(cx - s * 0.19, cy + s * 0.33 + rng.range(0, 2) * k), 2.0 * k, EMBER_FAT_DK);
    rl.drawLineEx(v2(cx + lean, cy + s * 0.02), v2(cx + lean, cy - s * 0.10), 1.6 * k, IRON_DK);
    rl.drawCircleV(v2(cx + lean * 1.4, cy - s * 0.17), s * 0.085, FIRE_DIM);
    rl.drawCircleV(v2(cx + lean * 1.2, cy - s * 0.145), s * 0.05, FIRE);
    rl.drawCircleV(v2(cx + lean, cy - s * 0.12), s * 0.022, rgba(255, 236, 190, 255));
}

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
    while (f < 5) : (f += 1) {
        const a = rng.range(std.math.pi * 1.15, std.math.pi * 1.85);
        const rr = rng.range(0.10, 0.24) * s;
        rl.drawCircleV(v2(cx + mathx.cosf(a) * rr, cy + s * 0.02 + mathx.sinf(a) * rr * 0.8), rng.range(1.2, 2.2) * k, SHROOM_CREAM);
    }
    rl.drawCircleV(v2(cx + s * 0.21, cy - s * 0.10), s * 0.06, rgba(30, 22, 20, 255));
    rl.drawCircleV(v2(cx + s * 0.17, cy - s * 0.075), 1.6 * k, CHAOS_DK);
}

fn secondWind(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.06 + 1.0 * k), s * 0.26, SHADOW);
    arc(cx, cy + s * 0.04, s * 0.22, std.math.pi * 0.2, std.math.pi * 1.6, 14, s * 0.16, s * 0.10, BONE_DK);
    arc(cx, cy + s * 0.04, s * 0.22, std.math.pi * 0.25, std.math.pi * 1.5, 12, s * 0.10, s * 0.05, BONE);
    arc(cx + s * 0.06, cy + s * 0.02, s * 0.10, std.math.pi * 0.4, std.math.pi * 1.8, 10, s * 0.07, s * 0.03, BONE);
    rl.drawLineEx(v2(cx - s * 0.16, cy + s * 0.20), v2(cx - s * 0.02, cy + s * 0.24), 2.0 * k, CORD);
    arc(cx + s * 0.16, cy - s * 0.14, s * 0.16, std.math.pi * 1.2, std.math.pi * 1.85, 8, 2.0 * k, 0.8 * k, rgba(238, 244, 248, 170));
    arc(cx + s * 0.20, cy - s * 0.02, s * 0.12, std.math.pi * 1.25, std.math.pi * 1.9, 8, 1.6 * k, 0.6 * k, rgba(238, 244, 248, 110));
}

fn towerShield(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    const hw = s * 0.20;
    const top = cy - s * 0.34;
    const bot = cy + s * 0.36;
    rl.drawCircleV(v2(cx + 1.2 * k, bot - s * 0.04), hw, SHADOW);
    quad(v2(cx - hw, top + s * 0.06), v2(cx + hw, top + s * 0.06), v2(cx + hw * 0.86, bot), v2(cx - hw * 0.86, bot), GRIP);
    arc(cx, top + s * 0.07, hw, std.math.pi, std.math.tau, 10, s * 0.12, s * 0.12, GRIP);
    for ([_]f32{ -0.4, 0.2 }) |t| {
        rl.drawLineEx(v2(cx + hw * t, top + s * 0.02), v2(cx + hw * t * 0.86, bot - s * 0.01), 1.4 * k, BOARD_JOINT);
        rl.drawLineEx(v2(cx + hw * t + 1.2 * k, top + s * 0.02), v2(cx + hw * t * 0.86 + 1.2 * k, bot - s * 0.01), 0.8 * k, GRIP_LT);
    }
    for ([_]f32{ top + s * 0.16, bot - s * 0.14 }) |by| {
        rl.drawLineEx(v2(cx - hw, by), v2(cx + hw, by), 3.4 * k, IRON_DK);
        rl.drawCircleV(v2(cx - hw * 0.6, by), 1.3 * k, STEEL_DK);
        rl.drawCircleV(v2(cx + hw * 0.6, by), 1.3 * k, STEEL_DK);
    }
    rl.drawLineEx(v2(cx - hw * 0.2, top + s * 0.05), v2(cx + hw * 0.15, cy - s * 0.02), 1.8 * k, rgba(24, 16, 12, 255));
    rl.drawLineEx(v2(cx + hw * 0.15, cy - s * 0.02), v2(cx - hw * 0.1, cy + s * 0.16), 1.6 * k, rgba(24, 16, 12, 255));
    rl.drawLineEx(v2(cx - hw * 0.1, cy + s * 0.16), v2(cx + hw * 0.1, bot - s * 0.06), 1.2 * k, rgba(24, 16, 12, 255));
}

fn greatclub(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xC1B8);
    rl.drawCircleV(v2(cx + 1.4 * k, cy - s * 0.10 + 1.4 * k), s * 0.24, rgba(0, 0, 0, 120));
    rl.drawLineEx(v2(cx - s * 0.10, cy + s * 0.44), v2(cx + s * 0.02, cy - s * 0.02), s * 0.10, ROOT_BARK);
    rl.drawLineEx(v2(cx - s * 0.085, cy + s * 0.42), v2(cx + s * 0.005, cy + s * 0.06), 1.6 * k, rgba(30, 20, 14, 255));
    rl.drawCircleV(v2(cx + s * 0.05, cy - s * 0.12), s * 0.20, ROOT_BARK);
    rl.drawCircleV(v2(cx + s * 0.14, cy - s * 0.20), s * 0.13, rgba(50, 36, 26, 255));
    rl.drawCircleV(v2(cx - s * 0.06, cy - s * 0.22), s * 0.11, rgba(46, 33, 24, 255));
    arc(cx + s * 0.05, cy - s * 0.13, s * 0.185, std.math.pi * 1.15, std.math.pi * 1.95, 10, 3.2 * k, 2.6 * k, IRON_DK);
    var st: u32 = 0;
    while (st < 4) : (st += 1) {
        const a = rng.range(std.math.pi * 1.2, std.math.pi * 1.9);
        rl.drawCircleV(v2(cx + s * 0.05 + mathx.cosf(a) * s * 0.185, cy - s * 0.13 + mathx.sinf(a) * s * 0.185), 1.4 * k, RUST);
    }
    rl.drawCircleV(v2(cx - s * 0.02, cy - s * 0.19), 2.0 * k, rgba(84, 64, 46, 255));
}

fn soulRing(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.03 + 1.0 * k), s * 0.21, SHADOW);
    arc(cx, cy + s * 0.02, s * 0.175, 0, std.math.tau, 20, s * 0.048, s * 0.038, RING_GOLD);
    arc(cx - s * 0.05, cy - s * 0.02, s * 0.175, std.math.pi * 0.85, std.math.pi * 1.45, 8, 1.7 * k, 0.9 * k, RING_GOLD_LT);
    const bx = cx + s * 0.155;
    const by = cy - s * 0.06;
    rl.drawLineEx(v2(bx - s * 0.03, by + s * 0.04), v2(bx + s * 0.03, by - s * 0.04), 2.2 * k, rgba(26, 20, 12, 255));
    rl.drawLineEx(v2(bx - s * 0.035, by + s * 0.035), v2(bx - s * 0.008, by), 1.1 * k, RING_GOLD_LT);
    rl.drawCircleV(v2(cx, cy - s * 0.155), s * 0.062, RING_SOUL);
    rl.drawCircleV(v2(cx - s * 0.015, cy - s * 0.172), 1.3 * k, rgba(255, 246, 214, 235));
}

fn leechSignet(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.04 + 1.0 * k), s * 0.20, SHADOW);
    arc(cx, cy + s * 0.04, s * 0.17, 0, std.math.tau, 18, s * 0.075, s * 0.05, rgba(44, 34, 30, 255));
    arc(cx - s * 0.04, cy, s * 0.16, std.math.pi * 0.9, std.math.pi * 1.5, 8, 1.6 * k, 0.8 * k, rgba(120, 104, 92, 255));
    rl.drawCircleV(v2(cx, cy - s * 0.16), s * 0.075, CRIMSON);
    rl.drawCircleV(v2(cx - s * 0.02, cy - s * 0.18), 1.4 * k, rgba(255, 200, 190, 220));
    rl.drawCircleV(v2(cx, cy - s * 0.10), 1.6 * k, rgba(44, 34, 30, 255));
}

fn fireTallow(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xFA77);
    greaseRag(cx, cy, px);
    rl.drawLineEx(v2(cx - s * 0.05, cy + s * 0.10), v2(cx - s * 0.10, cy + s * 0.24), 1.0 * k, rgba(190, 172, 138, 255));
    greaseFat(cx, cy, px, &rng, EMBER_FAT, EMBER_FAT_DK, rgba(246, 222, 164, 255));
    rl.drawLineEx(v2(cx + s * 0.05, cy + s * 0.08), v2(cx + s * 0.07 + rng.range(0, 2) * k, cy + s * 0.25), 2.2 * k, EMBER_FAT_DK);
}

/// **THE TALLOW'S COLD TWIN, AND IT HAS TO READ AS THE TWIN** — same twist of waxed cloth, same cord, and the
/// only thing swapped is the fat for rime-clouded wax. Two greases that look nothing alike is two pictures to
/// learn where one would have done.
fn rimewax(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x21CE);
    greaseRag(cx, cy, px);
    greaseFat(cx, cy, px, &rng, RIME_ICE, rgba(104, 152, 184, 255), RIME_LT);
    // Three frost needles off the lump — the only part of the picture the tallow does not have.
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const a = std.math.pi * (1.15 + 0.28 * @as(f32, @floatFromInt(i)));
        const from = v2(cx - s * 0.02 + mathx.cosf(a) * s * 0.10, cy - s * 0.03 + mathx.sinf(a) * s * 0.10);
        rl.drawLineEx(from, v2(from.x + mathx.cosf(a) * s * 0.12, from.y + mathx.sinf(a) * s * 0.12), 1.3 * k, RIME_LT);
    }
    rl.drawLineEx(v2(cx + s * 0.05, cy + s * 0.08), v2(cx + s * 0.07 + rng.range(0, 2) * k, cy + s * 0.25), 2.2 * k, rgba(104, 152, 184, 255));
}

/// A horn cup of kiln-grit in oil, the ash settled in a band and one ember still live in it. The BAND is the
/// read: a cup of plain dark liquid is the toad broth already in the tray.
fn kilnDraught(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x4C17);
    const horn = rgba(96, 82, 66, 255);
    const hornLo = rgba(62, 52, 42, 255);
    const ash = rgba(148, 142, 134, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.14 + 1.4 * k), s * 0.26, SHADOW);
    quad(v2(cx - s * 0.24, cy - s * 0.06), v2(cx + s * 0.25, cy - s * 0.08), v2(cx + s * 0.13, cy + s * 0.30), v2(cx - s * 0.11, cy + s * 0.29), horn);
    quad(v2(cx + s * 0.06, cy - s * 0.07), v2(cx + s * 0.25, cy - s * 0.08), v2(cx + s * 0.13, cy + s * 0.30), v2(cx + s * 0.02, cy + s * 0.30), hornLo);
    ellipseV(cx + s * 0.005, cy - s * 0.07, s * 0.245, s * 0.070, rgba(52, 44, 38, 255));
    ellipseV(cx - s * 0.01, cy - s * 0.08, s * 0.185, s * 0.048, ash);
    // The ember: the one warm mark, and it sits IN the ash rather than over the rim.
    rl.drawCircleV(v2(cx + s * 0.05 + rng.range(-1.0, 1.0) * k, cy - s * 0.085), s * 0.052, FIRE);
    rl.drawCircleV(v2(cx + s * 0.045, cy - s * 0.095), s * 0.026, rgba(255, 226, 168, 255));
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        rl.drawCircleV(v2(cx - s * 0.10 + @as(f32, @floatFromInt(i)) * s * 0.075, cy - s * 0.075 + rng.range(-1.2, 1.2) * k), s * rng.range(0.016, 0.030), rgba(196, 190, 180, 235));
    }
    rl.drawLineEx(v2(cx - s * 0.22, cy - s * 0.03), v2(cx - s * 0.10, cy + s * 0.27), 1.4 * k, hornLo);
}

/// **THE THIRD RUNG OF THE SOUL LADDER, AND THE PICTURE SAYS SO** — the nameless soul is a cracked lump and the
/// salt is a brick; this is a TIED PURSE with the lump inside and a coin at the knot, so the tray reads a tier
/// off the shape and never off the number.
fn pilgrimsOffering(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x0FFE);
    const cloth = rgba(126, 106, 84, 255);
    const clothLo = rgba(86, 70, 54, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.14 + 1.4 * k), s * 0.27, rgba(0, 0, 0, 115));
    rl.drawCircleV(v2(cx, cy + s * 0.10), s * 0.255, cloth);
    rl.drawCircleV(v2(cx + s * 0.09, cy + s * 0.15), s * 0.175, clothLo);
    // The glow through the weave: what is inside is somebody, and it is the only lit part.
    rl.drawCircleV(v2(cx - s * 0.05, cy + s * 0.05), s * 0.105, rgba(206, 178, 118, 200));
    rl.drawCircleV(v2(cx - s * 0.05, cy + s * 0.04), s * 0.055, RING_SOUL);
    // The neck, gathered and tied.
    quad(v2(cx - s * 0.10, cy - s * 0.20), v2(cx + s * 0.10, cy - s * 0.20), v2(cx + s * 0.14, cy - s * 0.04), v2(cx - s * 0.14, cy - s * 0.04), cloth);
    rl.drawLineEx(v2(cx - s * 0.13, cy - s * 0.11), v2(cx + s * 0.13, cy - s * 0.13), 2.8 * k, CORD);
    rl.drawLineEx(v2(cx + s * 0.11, cy - s * 0.13), v2(cx + s * 0.24, cy - s * 0.22 + rng.range(-1.4, 1.4) * k), 1.6 * k, CORD);
    // The coin on the tie, edge-on so it is a coin and not a bead.
    ellipseV(cx - s * 0.20, cy - s * 0.16, s * 0.075, s * 0.095, BRONZE);
    ellipseV(cx - s * 0.205, cy - s * 0.165, s * 0.045, s * 0.060, BRONZE_LT);
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const a = std.math.pi * (0.15 + 0.30 * @as(f32, @floatFromInt(i)));
        rl.drawLineEx(v2(cx + mathx.cosf(a) * s * 0.06, cy + s * 0.06 + mathx.sinf(a) * s * 0.06), v2(cx + mathx.cosf(a) * s * 0.20, cy + s * 0.10 + mathx.sinf(a) * s * 0.20), 1.2 * k, clothLo);
    }
}

/// **THE DIRK IS DRAWN ONCE.** The fang, the corded haft and the iron collar are one picture; a variant owns
/// only its SEED (which is the bend and the cord's jitter), the edge's tone and the glint laid down it. Returns
/// the POINT, because that is the one place a coating has anything of its own to hang.
fn dirkInto(cx: f32, cy: f32, px: f32, seed: u64, edge: rl.Color, glint: rl.Color) rl.Vector2 {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(seed);
    const rootP = v2(cx - s * 0.10, cy + s * 0.14);
    const tipP = v2(cx + s * 0.24, cy - s * 0.34);
    const bend = rng.range(0.12, 0.18);
    const SEGS = 12;
    var prev = rootP;
    for (0..SEGS + 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / SEGS;
        const p = onAxis(rootP, tipP, t, -bend * s * (4.0 * t * (1.0 - t)));
        const w = mathx.lerpF(5.2, 0.5, t * t * 0.85 + t * 0.15) * k;
        if (i > 0) rl.drawLineEx(prev, p, w, mathx.lerpColor(BONE_DK, edge, mathx.clampF(t * 1.25, 0, 1)));
        prev = p;
    }
    rl.drawLineEx(onAxis(rootP, tipP, 0.15, 1.2 * k), onAxis(rootP, tipP, 0.88, 0.3 * k), 1.1 * k, glint);
    const buttP = v2(cx - s * 0.24, cy + s * 0.30);
    rl.drawLineEx(rootP, buttP, 5.0 * k, GRIP);
    rl.drawCircleV(v2(rootP.x, rootP.y), 3.2 * k, IRON_DK);
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const t = 0.25 + 0.25 * @as(f32, @floatFromInt(i)) + rng.range(-0.03, 0.03);
        rl.drawLineEx(onAxis(rootP, buttP, t, -3.0 * k), onAxis(rootP, buttP, t + 0.07, 3.0 * k), 1.5 * k, CORD);
    }
    rl.drawCircleV(buttP, 2.4 * k, GRIP_LT);
    return tipP;
}

/// **THE DIRK'S SILHOUETTE, THE COATING'S COLOUR** — same fang, same corded haft, and the blade carried in
/// poison's own violet, with the bead at the point that says it is WET.
fn envenomedDagger(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const tipP = dirkInto(cx, cy, px, 0x0E2D, VENOM, VENOM_LT);
    // The drop hanging off the point: two circles, because one is a dot on a line.
    rl.drawCircleV(v2(tipP.x + s * 0.03, tipP.y + s * 0.05), s * 0.048, VENOM);
    rl.drawCircleV(v2(tipP.x + s * 0.025, tipP.y + s * 0.040), s * 0.024, VENOM_LT);
}

/// **THE BOOTS' SILHOUETTE IN SILK** — the pair reads as the pair (same two uppers, same sole line) and what is
/// swapped is hide for pale spider-silk, plus the strand still off the heel. The moccasin has NO hard sole:
/// that is the whole difference a player can see at 32 px.
fn spidersilkMoccasins(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x5117);
    const silk = rgba(206, 202, 212, 255);
    const silkDk = rgba(150, 146, 162, 255);
    const bind = rgba(176, 168, 150, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.18 + 1.4 * k), s * 0.26, rgba(0, 0, 0, 100));
    quad(v2(cx - s * 0.02, cy - s * 0.22), v2(cx + s * 0.15, cy - s * 0.22), v2(cx + s * 0.17, cy + s * 0.10), v2(cx - s * 0.01, cy + s * 0.10), silkDk);
    quad(v2(cx - s * 0.01, cy + s * 0.05), v2(cx + s * 0.29, cy + s * 0.09), v2(cx + s * 0.29, cy + s * 0.16), v2(cx - s * 0.01, cy + s * 0.15), silkDk);
    quad(v2(cx - s * 0.26, cy - s * 0.19), v2(cx - s * 0.07, cy - s * 0.21), v2(cx - s * 0.05, cy + s * 0.14), v2(cx - s * 0.24, cy + s * 0.14), silk);
    quad(v2(cx - s * 0.25, cy + s * 0.09), v2(cx + s * 0.08, cy + s * 0.13), v2(cx + s * 0.08, cy + s * 0.21), v2(cx - s * 0.25, cy + s * 0.19), silk);
    rl.drawLineEx(v2(cx - s * 0.26, cy + s * 0.21), v2(cx + s * 0.09, cy + s * 0.23), 1.6 * k, silkDk);
    // The binding round the ankle, and one loose strand: silk, not leather.
    rl.drawLineEx(v2(cx - s * 0.27, cy - s * 0.10), v2(cx - s * 0.04, cy - s * 0.12), 1.7 * k, bind);
    rl.drawLineEx(v2(cx - s * 0.27, cy - s * 0.02), v2(cx - s * 0.04, cy - s * 0.04), 1.5 * k, bind);
    var prev = v2(cx - s * 0.25, cy + s * 0.20);
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const p = v2(prev.x - s * 0.05, prev.y + s * 0.035 + rng.range(-1.0, 1.0) * k);
        rl.drawLineEx(prev, p, 1.1 * k, rgba(226, 224, 232, 210));
        prev = p;
    }
}

/// The deft signet's band with the stone SET INTO it rather than perched on top, and the stone dark enough that
/// the two rings are never the same picture. A garnet gone black reads as a hole, so it keeps one red highlight.
fn bloodtingeSignet(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.03 + 1.0 * k), s * 0.20, SHADOW);
    arc(cx, cy + s * 0.02, s * 0.175, 0, std.math.tau, 20, s * 0.066, s * 0.066, rgba(96, 74, 66, 255));
    arc(cx, cy + s * 0.02, s * 0.145, std.math.pi * 0.15, std.math.pi * 1.05, 12, 1.3 * k, 1.3 * k, rgba(168, 140, 128, 255));
    rl.drawCircleV(v2(cx, cy - s * 0.17), s * 0.105, rgba(74, 56, 52, 255));
    rl.drawCircleV(v2(cx, cy - s * 0.175), s * 0.072, WEED_DK);
    rl.drawCircleV(v2(cx - s * 0.02, cy - s * 0.195), s * 0.030, WEED_LT);
}

/// A holed coin on a twist of wire — the hole is the whole read, and it is drawn as a RING of coin rather than
/// a disc with a dot so it survives the tray at 32 px.
fn loopOfChance(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xC0FF);
    rl.drawCircleV(v2(cx + 1.0 * k, cy + s * 0.06 + 1.2 * k), s * 0.23, SHADOW);
    arc(cx, cy + s * 0.05, s * 0.19, 0, std.math.tau, 22, s * 0.105, s * 0.105, BRONZE);
    arc(cx - s * 0.02, cy + s * 0.03, s * 0.19, std.math.pi * 0.55, std.math.pi * 1.35, 12, s * 0.055, s * 0.045, BRONZE_LT);
    arc(cx, cy + s * 0.05, s * 0.135, 0, std.math.tau, 18, 1.4 * k, 1.4 * k, BRONZE_BORE);
    // The wire through the hole, closed at the top with a twist rather than a bead.
    const top = v2(cx + s * 0.02, cy - s * 0.28);
    arc(cx + s * 0.01, cy - s * 0.20, s * 0.095, std.math.pi * 0.20, std.math.pi * 1.80, 12, 1.5 * k, 1.5 * k, STEEL_MID);
    rl.drawLineEx(v2(top.x - s * 0.03, top.y + s * 0.02 + rng.range(-1.0, 1.0) * k), v2(top.x + s * 0.04, top.y - s * 0.02), 1.4 * k, STONE_LT);
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const a = std.math.pi * (1.55 + 0.16 * @as(f32, @floatFromInt(i)));
        rl.drawCircleV(v2(cx + mathx.cosf(a) * s * 0.165, cy + s * 0.05 + mathx.sinf(a) * s * 0.165), 1.2 * k, BRONZE_DK);
    }
}

fn thundercrock(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x7C0C);
    const clay = rgba(118, 76, 50, 255);
    const clayDk = rgba(80, 52, 34, 255);
    const lean = rng.range(-1.4, 1.4) * k;
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.09 + 1.2 * k), s * 0.25, rgba(0, 0, 0, 120));
    rl.drawCircleV(v2(cx, cy + s * 0.08), s * 0.245, clay);
    rl.drawCircleV(v2(cx - s * 0.07, cy + s * 0.02), s * 0.15, rgba(142, 96, 64, 255));
    quad(v2(cx - s * 0.09 + lean, cy - s * 0.21), v2(cx + s * 0.09 + lean, cy - s * 0.21), v2(cx + s * 0.07, cy - s * 0.07), v2(cx - s * 0.07, cy - s * 0.07), clayDk);
    rl.drawCircleV(v2(cx + lean, cy - s * 0.22), s * 0.07, CORK);
    const jag = [_]rl.Vector2{
        v2(cx - s * 0.27, cy + s * 0.01),
        v2(cx - s * 0.11, cy + s * 0.09),
        v2(cx - s * 0.01, cy + s * 0.03),
        v2(cx + s * 0.07, cy + s * 0.15),
        v2(cx + s * 0.26, cy + s * 0.09),
    };
    for (0..jag.len - 1) |i| {
        const w = mathx.lerpF(3.0, 1.8, @as(f32, @floatFromInt(i)) / 3.0) * k;
        rl.drawLineEx(jag[i], jag[i + 1], w, SPARK);
        rl.drawLineEx(jag[i], jag[i + 1], w * 0.40, rgba(252, 254, 255, 255));
    }
    rl.drawCircleV(jag[2], s * 0.038, rgba(232, 246, 255, 120));
    rl.drawCircleV(jag[2], s * 0.018, rgba(255, 255, 255, 235));
}

fn crackedSoul(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xC4AC);
    const hw = s * 0.19;
    const shy = s * 0.17;
    const top = cy - s * 0.32;
    const bot = cy + s * 0.30;
    const slip = s * 0.028;
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.04 + 1.2 * k), s * 0.26, rgba(0, 0, 0, 120));
    quad(v2(cx, top), v2(cx, bot), v2(cx - hw, cy + shy), v2(cx - hw, cy - shy), rgba(0, 0, 0, 170));
    quad(v2(cx, top + slip), v2(cx, bot + slip), v2(cx + hw, cy + shy + slip), v2(cx + hw, cy - shy + slip), rgba(0, 0, 0, 170));
    quad(v2(cx - 0.8 * k, top), v2(cx - 0.8 * k, bot), v2(cx - hw + 1.4 * k, cy + shy), v2(cx - hw + 1.4 * k, cy - shy), uiart.GILT_DIM);
    quad(v2(cx + 0.8 * k, top + slip), v2(cx + 0.8 * k, bot + slip), v2(cx + hw - 1.4 * k, cy + shy + slip), v2(cx + hw - 1.4 * k, cy - shy + slip), uiart.GILT);
    rl.drawLineEx(v2(cx - 0.8 * k, top), v2(cx - hw + 1.4 * k, cy - shy), 1.3 * k, uiart.GILT_BRIGHT);
    rl.drawLineEx(v2(cx + 0.8 * k, top + slip), v2(cx + hw - 1.4 * k, cy - shy + slip), 1.3 * k, uiart.GILT_BRIGHT);
    const groove = rgba(92, 66, 20, 235);
    rl.drawLineEx(v2(cx - hw * 0.72, cy - s * 0.10), v2(cx - 1.5 * k, cy - s * 0.17), 1.7 * k, groove);
    rl.drawLineEx(v2(cx - hw * 0.62, cy + s * 0.15), v2(cx - hw * 0.62, cy - s * 0.06), 1.7 * k, groove);
    rl.drawLineEx(v2(cx + 1.5 * k, cy - s * 0.16 + slip), v2(cx + hw * 0.74, cy - s * 0.01 + slip), 1.7 * k, groove);
    rl.drawLineEx(v2(cx + hw * 0.74, cy - s * 0.01 + slip), v2(cx + hw * 0.40, cy + s * 0.16 + slip), 1.7 * k, groove);
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
    rl.drawCircleV(seam[2], 2.6 * k, rgba(255, 254, 244, 255));
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        rl.drawCircleV(v2(cx + rng.range(-0.08, 0.08) * s, cy + rng.range(-0.36, -0.12) * s), rng.range(0.6, 1.2) * k, rgba(255, 232, 176, 200));
    }
}

fn toadfleshBroth(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x70AD);
    const sag = rng.range(0, 1.6) * k;
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.12 + 1.2 * k), s * 0.24, rgba(0, 0, 0, 115));
    rl.drawCircleV(v2(cx - s * 0.04, cy + s * 0.12 + sag), s * 0.21, GRIP);
    rl.drawCircleV(v2(cx + s * 0.10, cy + s * 0.08), s * 0.16, GRIP);
    rl.drawCircleV(v2(cx - s * 0.09, cy + s * 0.05), s * 0.11, GRIP_LT);
    quad(v2(cx - s * 0.045, cy - s * 0.18), v2(cx + s * 0.045, cy - s * 0.18), v2(cx + s * 0.06, cy - s * 0.02), v2(cx - s * 0.06, cy - s * 0.02), BOARD_JOINT);
    rl.drawLineEx(v2(cx - s * 0.08, cy - s * 0.10), v2(cx + s * 0.08, cy - s * 0.12), 2.6 * k, CORD);
    rl.drawLineEx(v2(cx - s * 0.11, cy - s * 0.20), v2(cx + s * 0.11, cy - s * 0.22), 3.0 * k, BONE);
    rl.drawCircleV(v2(cx + s * 0.11, cy - s * 0.22), 1.5 * k, BONE_DK);
    rl.drawCircleV(v2(cx + s * 0.02, cy - s * 0.155), 1.4 * k, SALT);
}

fn fangDirk(cx: f32, cy: f32, px: f32) void {
    _ = dirkInto(cx, cy, px, 0xD1FA, BONE, rgba(255, 252, 240, 220));
}

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
    for ([_]rl.Vector2{ top, bot }) |p| rl.drawCircleV(p, 2.2 * k, IRON_DK);
    rl.drawLineEx(top, bot, 1.0 * k, BOWSTRING);
}

fn quiltedGambeson(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x6A3B);
    const linen = rgba(184, 168, 136, 255);
    const linenDk = rgba(140, 126, 100, 255);
    rl.drawCircleV(v2(cx + 1.2 * k, cy + s * 0.08 + 1.4 * k), s * 0.26, SHADOW);
    quad(v2(cx - s * 0.20, cy - s * 0.18), v2(cx - s * 0.34, cy - s * 0.02), v2(cx - s * 0.26, cy + s * 0.06), v2(cx - s * 0.14, cy - s * 0.06), linenDk);
    quad(v2(cx + s * 0.20, cy - s * 0.18), v2(cx + s * 0.34, cy - s * 0.04), v2(cx + s * 0.27, cy + s * 0.05), v2(cx + s * 0.14, cy - s * 0.06), linenDk);
    quad(v2(cx - s * 0.19, cy - s * 0.22), v2(cx + s * 0.19, cy - s * 0.22), v2(cx + s * 0.17, cy + s * 0.32), v2(cx - s * 0.16, cy + s * 0.30 + rng.range(0, 2) * k), linen);
    quad(v2(cx - s * 0.06, cy - s * 0.22), v2(cx + s * 0.06, cy - s * 0.22), v2(cx + s * 0.01, cy - s * 0.10), v2(cx - s * 0.01, cy - s * 0.10), rgba(56, 44, 34, 255));
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const yc = cy - s * 0.10 + @as(f32, @floatFromInt(i)) * s * 0.10 + rng.range(-0.012, 0.012) * s;
        rl.drawLineEx(v2(cx - s * 0.17, yc - s * 0.07), v2(cx + s * 0.17, yc + s * 0.07), 0.9 * k, linenDk);
        rl.drawLineEx(v2(cx - s * 0.17, yc + s * 0.07), v2(cx + s * 0.17, yc - s * 0.07), 0.9 * k, linenDk);
    }
    rl.drawCircleV(v2(cx + s * 0.08, cy + s * 0.20), s * 0.075, rgba(96, 62, 48, 170));
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
    const body = s * 0.265;
    const bodyY = cy + s * 0.13;
    const lean = rng.range(-0.9, 0.9) * k;

    rl.drawCircleV(v2(cx + 1.0 * k, bodyY + 1.1 * k), body, rgba(0, 0, 0, 120));
    rl.drawCircleV(v2(cx, bodyY), body, deep);
    rl.drawCircleV(v2(cx - body * 0.11, bodyY - body * 0.13), body * 0.90, fill);
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
    if (full) {
        rl.drawLineEx(
            v2(cx - body * 0.20, bodyY - body * 0.60),
            v2(cx + body * 0.72, bodyY - body * 0.68),
            1.4 * k,
            rgba(255, 255, 255, 80),
        );
    }
    rl.drawLineEx(
        v2(cx - body * 0.52, bodyY - body * 0.62),
        v2(cx - body * 0.66, bodyY + body * 0.28),
        2.0 * k,
        rgba(GLASS_LIT.r, GLASS_LIT.g, GLASS_LIT.b, if (full) 200 else 90),
    );

    const sx = cx + lean * 1.15;
    rl.drawRectangleV(v2(sx - s * 0.062, cy - s * 0.395), v2(s * 0.124, s * 0.105), CORK);
    rl.drawCircleV(v2(sx, cy - s * 0.335), s * 0.075, WAX);
    rl.drawCircleV(v2(sx + rng.range(-0.6, 0.6) * s * 0.05, cy - s * 0.30), s * 0.048, WAX);
    rl.drawCircleV(v2(sx - 1.2 * k, cy - s * 0.355), 1.0 * k, rgba(255, 210, 190, 120));
    const ty = cy - s * 0.245;
    rl.drawLineEx(v2(sx - s * 0.075, ty), v2(sx + s * 0.075, ty - 0.6 * k), 1.4 * k, CORD);
    rl.drawLineEx(
        v2(sx + s * 0.055, ty),
        v2(sx + s * 0.055 + rng.range(1.4, 3.0) * k, ty + rng.range(1.6, 3.4) * k),
        1.0 * k,
        CORD,
    );
}

pub fn sword(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x5B1AD3);
    const d = s * 0.72;
    const u = 0.70711;
    const lean = rng.range(-0.035, 0.035);
    const gone = v2(cx - u * d * (1.0 + lean), cy - u * d * (1.0 - lean));
    // THE POMMEL HAS TO FIT ITS OWN SOCKET, and off the diagonal that is not free: at the shipped 150% equipment scale the obvious 0.92 of the axis put its far side 3 px out over the rim. Held in off the wheel's own radius.
    const pomR = 2.7 * k;
    const pomOut = @min(u * d * 0.92, s * 0.5 - pomR - 1.5 * k);
    const pom = v2(cx + pomOut, cy + pomOut);
    const guard = onAxis(gone, pom, 0.60, 0); // the hilt: the bottom 40%, drawn big and jewelled
    const shoulder = onAxis(gone, pom, 0.565, 0);

    const wBase = 2.7 * k;
    const wFar = 2.1 * k;
    const SEGS = 18;
    const runTo = 0.565;
    const FADE_FROM = 0.28;
    for (0..SEGS) |i| {
        const t0 = @as(f32, @floatFromInt(i)) / SEGS;
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
    const solid = runTo * (1.0 - FADE_FROM);
    rl.drawLineEx(onAxis(gone, pom, solid + 0.01, 0), onAxis(shoulder, pom, -0.02, 0), 1.1 * k, rgba(64, 68, 74, 170));
    rl.drawLineEx(onAxis(gone, pom, solid, -wBase * 0.84), onAxis(shoulder, pom, 0, -wBase * 0.88), 1.1 * k, mathx.withAlpha(STEEL, 215));
    rl.drawLineEx(onAxis(gone, pom, solid, wBase * 0.84), onAxis(shoulder, pom, 0, wBase * 0.88), 0.9 * k, rgba(88, 92, 98, 180));
    const nickAt = rng.range(0.33, 0.43);
    rl.drawTriangle(
        onAxis(gone, pom, nickAt, -wBase * 0.72),
        onAxis(gone, pom, nickAt + 0.022, -wBase * 0.26),
        onAxis(gone, pom, nickAt - 0.016, -wBase * 0.26),
        rgba(20, 18, 16, 190),
    );

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

    // THE CROSSGUARD — two arms of different length, and WIDE now that it is the read: the hilt is what this picture is of. The first pass ran it at 0.215·s and 2.9 px, which is a warhammer's head.
    const q = s * 0.17;
    for ([_]f32{ -1, 1 }) |side| {
        const armLen = q * rng.range(0.84, 1.08);
        const droop = -side * 0.9 * k;
        const outer = v2(guard.x + side * u * armLen + u * droop, guard.y - side * u * armLen + u * droop);
        rl.drawLineEx(guard, outer, 2.1 * k, BRASS);
        rl.drawCircleV(outer, 1.15 * k, uiart.GILT);
    }
    rl.drawCircleV(guard, 1.35 * k, uiart.GILT);

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
    const upper = d * 1.06;
    const lower = d * 0.90;
    const tx = cx - u * upper;
    const ty = cy - u * upper;
    const bx = cx + u * lower;
    const by = cy + u * lower;
    const belly = s * 0.17;
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
        rl.drawLineEx(outer, tip, 2.0 * k, BOWWOOD);
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

    rl.drawCircleV(v2(cx + 0.8 * k, cy + 1.0 * k), r, rgba(0, 0, 0, 130));
    rl.drawPoly(c, 17, r, rng.range(0, 20), STEEL_DK);
    rl.drawPoly(c, 17, boards, rng.range(0, 20), GRIP);

    const j1 = rng.range(-0.50, -0.30);
    const j2 = rng.range(0.24, 0.46);
    for ([_]f32{ j1, j2 }) |f| {
        const dy = boards * f;
        const half = @sqrt(@max(boards * boards - dy * dy, 1.0));
        rl.drawLineEx(v2(cx - half, cy + dy), v2(cx + half, cy + dy), 1.7 * k, BOARD_JOINT);
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

    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        if (i == 3) continue;
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

pub fn wand(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x7A4D91);
    const u = 0.70711;
    const d = s * 0.36;
    const butt = v2(cx + u * d, cy + u * d);
    const head = v2(cx - u * d * 1.02, cy - u * d * 1.02);
    const kneeA = onAxis(butt, head, 0.36, s * rng.range(0.014, 0.026));
    const kneeB = onAxis(butt, head, 0.70, s * rng.range(-0.024, -0.012));
    rl.drawLineEx(v2(butt.x + 0.9 * k, butt.y + 1.1 * k), v2(head.x + 0.9 * k, head.y + 1.1 * k), 3.4 * k, rgba(0, 0, 0, 120));
    rl.drawLineEx(butt, kneeA, 3.6 * k, GRIP);
    rl.drawLineEx(kneeA, kneeB, 3.0 * k, BOWWOOD);
    rl.drawLineEx(kneeB, head, 2.4 * k, BOWWOOD);
    rl.drawLineEx(onAxis(butt, kneeA, 0.2, -1.1 * k), onAxis(kneeB, head, 0.7, -0.9 * k), 0.8 * k, BOWWOOD_LT);
    for ([_]f32{ rng.range(0.06, 0.14), rng.range(0.19, 0.27), rng.range(0.30, 0.36) }) |f| {
        const p = onAxis(butt, head, f, 0);
        rl.drawLineEx(v2(p.x - u * 2.4 * k, p.y + u * 2.4 * k), v2(p.x + u * 2.4 * k, p.y - u * 2.4 * k), 1.1 * k, CORD);
    }
    const neck = onAxis(butt, head, 0.80, 0);
    rl.drawLineEx(onAxis(butt, head, 0.74, 0), neck, 3.8 * k, STEEL_DK);
    const sr = s * 0.115;
    for ([_]f32{ -1, 1 }) |side| {
        rl.drawLineEx(neck, v2(head.x + side * u * sr * 0.95, head.y + side * u * sr * -0.95), 1.5 * k, STEEL_DK);
    }
    rl.drawCircleV(v2(head.x + 0.7 * k, head.y + 0.9 * k), sr, rgba(0, 0, 0, 140));
    rl.drawCircleV(head, sr, CHAOS_DK);
    rl.drawCircleV(v2(head.x - 0.9 * k, head.y - 1.0 * k), sr - 1.8 * k, CHAOS);
    rl.drawCircleV(v2(head.x - 1.5 * k, head.y - 1.7 * k), sr * 0.34, CHAOS_LT);
    rl.drawCircleV(v2(head.x - 1.9 * k, head.y - 2.1 * k), sr * 0.15, uiart.CATCH);
}

/// **WHAT A HAND HAS A PICTURE OF, ASKED ONCE** — the HUD cell, the book's four hand sockets and the doll all come through here, the way `spellArt` is already the one answer for the sorcery cell. Named apart from `hero.Armament` because `hud` and this file may not import `hero`.
pub const Arm = enum { sword, dagger, club, bow, bell, shield, wand, torch };

pub fn heldArt(a: Arm, gear: ?item.Kind, cx: f32, cy: f32, px: f32) void {
    if (gear) |k| return drawHeld(k, cx, cy, px, true);
    switch (a) {
        .sword => sword(cx, cy, px),
        // THE CLASS PICTURE IS ITS ONE WEAPON'S, because in this world it IS the class — and the hand cell never offers either of these two bare (`book.candidates`), so this is the fallback and not the view.
        .dagger => fangDirk(cx, cy, px),
        .club => greatclub(cx, cy, px),
        .bow => bow(cx, cy, px),
        .bell => bell(cx, cy, px),
        .shield => shield(cx, cy, px),
        .wand => wand(cx, cy, px),
        .torch => torch(cx, cy, px),
    }
}

/// On the ROD'S OWN DIAGONAL, so the two left-hand pictures read as one set — and shorter, because the flame is what has to fit in the box above it.
pub fn torch(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x70C48);
    const u = 0.70711;
    const d = s * 0.30;
    const butt = v2(cx + u * d, cy + u * d);
    const head = v2(cx - u * d * 0.86, cy - u * d * 0.86);
    rl.drawLineEx(v2(butt.x + 0.9 * k, butt.y + 1.1 * k), v2(head.x + 0.9 * k, head.y + 1.1 * k), 4.0 * k, rgba(0, 0, 0, 120));
    rl.drawLineEx(butt, head, 3.6 * k, GRIP);
    rl.drawLineEx(onAxis(butt, head, 0.30, -1.0 * k), onAxis(butt, head, 0.86, -0.9 * k), 1.0 * k, GRIP_LT);
    for ([_]f32{ rng.range(0.05, 0.12), rng.range(0.20, 0.28), rng.range(0.34, 0.42) }) |f| {
        const p = onAxis(butt, head, f, 0);
        rl.drawLineEx(v2(p.x - u * 2.6 * k, p.y + u * 2.6 * k), v2(p.x + u * 2.6 * k, p.y - u * 2.6 * k), 1.2 * k, CORD);
    }
    const neck = onAxis(butt, head, 0.80, 0);
    rl.drawLineEx(onAxis(butt, head, 0.72, 0), neck, 4.4 * k, IRON_DK);
    // The pitch wad, then the flame off ITS far face — a torch is read by the fire, not by the stick.
    const wad = onAxis(butt, head, 1.0, 0);
    rl.drawCircleV(v2(wad.x, wad.y), s * 0.085, rgba(24, 20, 18, 255));
    rl.drawLineEx(v2(wad.x - u * 3.0 * k, wad.y + u * 3.0 * k), v2(wad.x + u * 3.0 * k, wad.y - u * 3.0 * k), 1.2 * k, CORD);
    const tip = v2(wad.x - s * 0.03, wad.y - s * 0.20);
    quad(
        v2(wad.x - s * 0.105, wad.y - s * 0.01),
        v2(wad.x + s * 0.095, wad.y - s * 0.02),
        v2(tip.x + s * 0.035 + rng.range(-1.0, 1.0) * k, tip.y + s * 0.06),
        v2(tip.x - s * 0.045 + rng.range(-1.0, 1.0) * k, tip.y + s * 0.05),
        FIRE_DIM,
    );
    rl.drawCircleV(v2(wad.x - s * 0.005, wad.y - s * 0.055), s * 0.075, FIRE_DIM);
    rl.drawCircleV(v2(wad.x - s * 0.015, wad.y - s * 0.075), s * 0.048, FIRE);
    rl.drawCircleV(v2(tip.x, tip.y + s * 0.055), s * 0.020, rgba(255, 238, 196, 255));
    rl.drawCircleV(v2(wad.x + s * 0.075, wad.y - s * 0.20 + rng.range(0, 2) * k), 1.3 * k, FIRE_DIM);
}

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
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const off = (@as(f32, @floatFromInt(i)) - 1.0);
        const lead: f32 = if (off == 0) 1.25 else 0.85;
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

pub fn roots(cx: f32, cy: f32, px: f32, on: bool) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x600751);
    const a: u8 = if (on) 255 else 120;
    const bark = rgba(ROOT_BARK.r, ROOT_BARK.g, ROOT_BARK.b, a);
    const heart = rgba(ROOT_HEART.r, ROOT_HEART.g, ROOT_HEART.b, a);
    const lit = rgba(CHAOS.r, CHAOS.g, CHAOS.b, if (on) 210 else 90);
    const halo = rgba(CHAOS.r, CHAOS.g, CHAOS.b, if (on) 70 else 30);
    const soil = cy + s * 0.22;
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) + rng.range(-0.22, 0.22)) / 4.0 - 0.5;
        const foot = v2(cx + t * s * 0.62, soil + rng.range(-0.02, 0.02) * s);
        const rise = s * rng.range(0.20, 0.40);
        const lean = rng.range(-0.34, 0.34) * s * 0.5;
        const knee = v2(foot.x + lean * 0.35, foot.y - rise * 0.55);
        const tip = v2(knee.x + lean, knee.y - rise * 0.45);
        const w = rng.range(2.2, 3.1) * k;
        rl.drawLineEx(foot, knee, w, bark);
        rl.drawLineEx(knee, tip, w * 0.72, bark);
        rl.drawCircleV(tip, w * 0.44, heart);
        rl.drawCircleV(tip, w * 1.15, halo);
        rl.drawCircleV(tip, w * 0.30, lit);
    }
    const soilCol = rgba(ROOT_SOIL.r, ROOT_SOIL.g, ROOT_SOIL.b, a);
    rl.drawLineEx(v2(cx - s * 0.36, soil), v2(cx + s * 0.36, soil), 2.4 * k, soilCol);
    var j: u32 = 0;
    while (j < 4) : (j += 1) {
        const x = cx + rng.range(-0.32, 0.32) * s;
        rl.drawCircleV(v2(x, soil + rng.range(-0.4, 1.2) * k), rng.range(0.8, 1.7) * k, soilCol);
    }
}

pub fn rime(cx: f32, cy: f32, px: f32, on: bool) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x21C3);
    const a: u8 = if (on) 255 else 120;
    const ice = rgba(RIME_ICE.r, RIME_ICE.g, RIME_ICE.b, a);
    const lit = rgba(RIME_LT.r, RIME_LT.g, RIME_LT.b, a);
    const halo = rgba(RIME_ICE.r, RIME_ICE.g, RIME_ICE.b, if (on) 60 else 26);
    const throat = v2(cx - s * 0.34, cy + s * 0.04);
    var w: u32 = 0;
    while (w < 3) : (w += 1) {
        const t = (@as(f32, @floatFromInt(w)) + 1.0) / 3.0;
        rl.drawCircleV(v2(throat.x + s * 0.62 * t, throat.y + rng.range(-0.03, 0.03) * s), s * (0.10 + 0.20 * t), halo);
    }
    var i: u32 = 0;
    while (i < 7) : (i += 1) {
        const spread = ((@as(f32, @floatFromInt(i)) + rng.range(-0.3, 0.3)) / 6.0 - 0.5) * 0.86; // radians off the axis
        const run = s * rng.range(0.30, 0.68);
        const from = v2(throat.x + s * 0.06, throat.y + spread * s * 0.10);
        const to = v2(from.x + run, from.y + spread * run);
        const wid = rng.range(1.8, 3.0) * k;
        rl.drawLineEx(from, to, wid, ice);
        rl.drawCircleV(to, wid * 0.52, lit);
        rl.drawCircleV(to, wid * 1.25, halo);
    }
    var j: u32 = 0;
    while (j < 5) : (j += 1) {
        const x = cx + rng.range(-0.10, 0.40) * s;
        rl.drawCircleV(v2(x, cy + s * rng.range(0.24, 0.40)), rng.range(0.9, 1.8) * k, lit);
    }
}

pub fn levin(cx: f32, cy: f32, px: f32, on: bool) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x1E7A1);
    const a: u8 = if (on) 255 else 120;
    const hot = rgba(LEVIN_HOT.r, LEVIN_HOT.g, LEVIN_HOT.b, a);
    const edge = rgba(LEVIN_EDGE.r, LEVIN_EDGE.g, LEVIN_EDGE.b, a);
    const halo = rgba(LEVIN_EDGE.r, LEVIN_EDGE.g, LEVIN_EDGE.b, if (on) 66 else 28);
    const foot = v2(cx + s * 0.06, cy + s * 0.30);
    const head = v2(cx - s * 0.20, cy - s * 0.34);
    var prev = head;
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const u = (@as(f32, @floatFromInt(i)) + 1.0) / 4.0;
        const on_line = v2(head.x + (foot.x - head.x) * u, head.y + (foot.y - head.y) * u);
        const kink = if (i == 3) 0.0 else rng.range(-0.16, 0.16) * s;
        const p = v2(on_line.x + kink, on_line.y + rng.range(-0.03, 0.03) * s);
        const w = mathx.lerpF(3.4, 1.9, u) * k * rng.range(0.85, 1.15);
        rl.drawLineEx(prev, p, w + 1.6 * k, halo);
        rl.drawLineEx(prev, p, w, edge);
        rl.drawLineEx(prev, p, w * 0.42, hot);
        prev = p;
    }
    rl.drawCircleV(foot, s * 0.15, halo);
    rl.drawCircleV(foot, s * 0.070, edge);
    rl.drawCircleV(foot, s * 0.034, hot);
    var j: u32 = 0;
    while (j < 5) : (j += 1) {
        const ang = rng.range(3.4, 6.0);
        const run = s * rng.range(0.10, 0.22);
        const from = v2(foot.x + mathx.cosf(ang) * s * 0.04, foot.y + mathx.sinf(ang) * s * 0.04);
        rl.drawLineEx(from, v2(from.x + mathx.cosf(ang) * run, from.y + mathx.sinf(ang) * run), rng.range(1.0, 1.8) * k, edge);
    }
}

pub fn siphon(cx: f32, cy: f32, px: f32, on: bool) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x51F0);
    const a: u8 = if (on) 255 else 120;
    const shell = rgba(CHAOS_DK.r, CHAOS_DK.g, CHAOS_DK.b, a);
    const body = rgba(CHAOS.r, CHAOS.g, CHAOS.b, a);
    const core = rgba(CHAOS_LT.r, CHAOS_LT.g, CHAOS_LT.b, a);
    const halo = rgba(CHAOS.r, CHAOS.g, CHAOS.b, if (on) 80 else 34);
    const at = v2(cx - s * 0.04, cy + s * 0.02);
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        const ang = (@as(f32, @floatFromInt(i)) + rng.range(-0.34, 0.34)) / 6.0 * std.math.tau;
        // WIDELY uneven runs: six of a length is a rosette however the bearings are jittered. **AND THE HEADS STOP WELL SHORT OF THE CORE** — brought in to 0.13 they overlapped it and the card read as one fuzzy lump with whiskers; the DARK GAP is what says they are still travelling.
        const far = s * rng.range(0.34, 0.52);
        const nearR = s * rng.range(0.190, 0.250);
        const mid = mathx.lerpF(far, nearR, 0.55);
        const cs = mathx.cosf(ang);
        const sn = mathx.sinf(ang);
        const tail = v2(at.x + cs * far, at.y + sn * far);
        const waist = v2(at.x + cs * mid, at.y + sn * mid);
        const head = v2(at.x + cs * nearR, at.y + sn * nearR);
        const w = rng.range(1.5, 2.2) * k;
        rl.drawLineEx(tail, waist, w * 0.55, halo);
        rl.drawLineEx(waist, head, w, body);
        rl.drawCircleV(head, w * 1.05, if (i % 3 == 0) core else body);
    }
    rl.drawCircleV(at, s * 0.118, halo);
    rl.drawCircleV(at, s * 0.076, shell);
    rl.drawCircleV(v2(at.x - 0.7 * k, at.y - 0.9 * k), s * 0.046, body);
    rl.drawCircleV(v2(at.x - 1.1 * k, at.y - 1.4 * k), s * 0.020, core);
}

pub fn arrow(cx: f32, cy: f32, px: f32, on: bool, fire: bool) void {
    const s = px;
    const k = strokeK(px);
    const half = s * 0.16;
    const shaft = if (on) BOWWOOD else rgba(BOWWOOD.r, BOWWOOD.g, BOWWOOD.b, 120);
    const plainHead = if (on) STEEL else rgba(STEEL_DK.r, STEEL_DK.g, STEEL_DK.b, 140);
    const head = if (fire) (if (on) FIRE else rgba(FIRE.r, FIRE.g, FIRE.b, 140)) else plainHead;
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
    rl.drawLineEx(v2(cx - half, cy - 0.7 * k), v2(cx + half * 0.7, cy - 0.7 * k), 0.7 * k, rgba(GRIP_LT.r, GRIP_LT.g, GRIP_LT.b, if (on) 160 else 70));
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
    rl.drawLineEx(v2(cx - half - 1.0 * k, cy - 1.5 * k), v2(cx - half - 1.0 * k, cy + 1.5 * k), 1.2 * k, rgba(CORD.r, CORD.g, CORD.b, if (on) 235 else 110));
}

fn soulArc(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xA12C);
    const r = s * 0.30;
    const gapAt = rng.range(-0.5, 0.5);
    const gapHalf = 0.42; // radians
    const from = gapAt + gapHalf;
    const to = gapAt + std.math.tau - gapHalf;
    rl.drawCircleV(v2(cx + 1.0 * k, cy + 1.2 * k), r * 0.35, rgba(0, 0, 0, 90));
    arc(cx, cy, r, from, to, 26, 4.2 * k, 2.2 * k, rgba(0, 0, 0, 150));
    arc(cx, cy, r, from, to, 26, 3.2 * k, 1.5 * k, uiart.GILT_DIM);
    arc(cx, cy, r - 0.8 * k, from, to, 26, 1.4 * k, 0.8 * k, uiart.GILT_BRIGHT);
    arc(cx, cy, r, from + 0.10, to - 0.10, 22, 1.1 * k, 0.6 * k, rgba(255, 246, 214, 170));
    for ([_]f32{ from, to }) |a| {
        const p = v2(cx + mathx.cosf(a) * r, cy + mathx.sinf(a) * r);
        rl.drawCircleV(p, 2.1 * k, uiart.GILT);
        rl.drawCircleV(v2(p.x - 0.5 * k, p.y - 0.6 * k), 0.9 * k, uiart.CATCH);
    }
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        const a = gapAt + rng.range(-0.5, 0.5);
        const rr = r * rng.range(0.55, 1.35);
        rl.drawCircleV(v2(cx + mathx.cosf(a) * rr, cy + mathx.sinf(a) * rr), rng.range(0.5, 1.1) * k, rgba(255, 232, 176, 190));
    }
}

fn goldenSeed(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x60D5EE);
    const rootY = cy + s * 0.34;
    const tipY = cy - s * 0.30;
    const lean = rng.range(-0.06, 0.06) * s;
    const stem = v2(cx + lean * 0.35, rootY);
    const crown = v2(cx + lean, tipY);

    rl.drawLineEx(stem, crown, 2.0 * k, rgba(96, 84, 44, 255));
    for ([_]f32{ -1, 1 }) |side| {
        const at = 0.34 + side * rng.range(0.04, 0.13);
        const root = onAxis(stem, crown, at, 0);
        const len = s * rng.range(0.22, 0.30);
        const tip = v2(root.x + side * len, root.y - len * rng.range(0.35, 0.62));
        const mid = v2((root.x + tip.x) * 0.5, (root.y + tip.y) * 0.5 - len * 0.22);
        quad(root, mid, tip, v2(mid.x, mid.y + len * 0.30), rgba(104, 96, 52, 255));
        rl.drawLineEx(root, tip, 0.8 * k, rgba(140, 130, 74, 220));
    }
    const podR = s * 0.155;
    const podY = tipY + podR * 0.55;
    rl.drawCircleV(v2(cx + lean + 0.9 * k, podY + 1.0 * k), podR, SHADOW);
    var i: u32 = 0;
    while (i < 7) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / 6.0;
        const rr = podR * (1.0 - 0.78 * t * t);
        const yy = podY - podR * 1.15 * t;
        rl.drawCircleV(v2(cx + lean * (1.0 + t * 0.4), yy), rr, mathx.lerpColor(uiart.GILT, uiart.GILT_BRIGHT, t * 0.7));
    }
    rl.drawCircleV(v2(cx + lean - podR * 0.34, podY - podR * 0.22), podR * 0.34, rgba(255, 246, 210, 190));
    rl.drawLineEx(
        v2(cx + lean + podR * 0.10, podY + podR * 0.55),
        v2(cx + lean + podR * 0.22, podY - podR * 0.95),
        1.1 * k,
        rgba(126, 96, 30, 200),
    );
    rl.drawCircleV(v2(cx + lean + podR * 0.24, podY - podR * 1.05), 1.2 * k, uiart.CATCH);
}

fn smithingStone(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x57012E);
    const r = s * 0.34;
    const N = 7;
    var pts: [N]rl.Vector2 = undefined;
    for (0..N) |i| {
        const a = std.math.tau * (@as(f32, @floatFromInt(i)) / N) + rng.range(-0.22, 0.22) - 0.4;
        const rr = r * rng.range(0.70, 1.10);
        pts[i] = v2(cx + mathx.cosf(a) * rr, cy + mathx.sinf(a) * rr * 0.92);
    }
    const core = v2(cx + rng.range(-0.12, 0.12) * s, cy + rng.range(-0.10, 0.10) * s);
    for (0..N) |i| {
        const a = pts[i];
        const b = pts[(i + 1) % N];
        rl.drawTriangle(v2(a.x + 1.4 * k, a.y + 1.8 * k), v2(b.x + 1.4 * k, b.y + 1.8 * k), v2(core.x + 1.4 * k, core.y + 1.8 * k), rgba(0, 0, 0, 120));
    }
    for (0..N) |i| {
        const a = pts[i];
        const b = pts[(i + 1) % N];
        const up = 1.0 - (((a.y + b.y) * 0.5 - cy) / r + 1.0) * 0.5;
        const col = mathx.lerpColor(STONE_DK, STONE_LT, mathx.clampF(up * rng.range(0.75, 1.25), 0, 1));
        quad(a, b, core, core, col);
        rl.drawLineEx(a, b, 0.9 * k, rgba(STONE.r, STONE.g, STONE.b, 200));
    }
    const li: usize = @intCast(rng.intn(N));
    quad(pts[li], pts[(li + 1) % N], core, core, rgba(STONE_LT.r, STONE_LT.g, STONE_LT.b, 235));
    const sp = v2((pts[li].x + core.x) * 0.5, (pts[li].y + core.y) * 0.5);
    rl.drawCircleV(sp, 1.6 * k, rgba(SPARK.r, SPARK.g, SPARK.b, 200));
    rl.drawLineEx(v2(sp.x - 2.6 * k, sp.y), v2(sp.x + 2.6 * k, sp.y), 0.8 * k, rgba(SPARK.r, SPARK.g, SPARK.b, 130));
    rl.drawLineEx(v2(sp.x, sp.y - 2.6 * k), v2(sp.x, sp.y + 2.6 * k), 0.8 * k, rgba(SPARK.r, SPARK.g, SPARK.b, 130));
}

fn bloodgrass(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xB100D6);
    const crown = v2(cx + rng.range(-0.03, 0.03) * s, cy + s * 0.26);
    rl.drawCircleV(v2(crown.x, crown.y + s * 0.03), s * 0.10, rgba(58, 44, 34, 255));
    var i: u32 = 0;
    while (i < 7) : (i += 1) {
        const spread = (@as(f32, @floatFromInt(i)) / 6.0 - 0.5) * 2.0;
        const len = s * rng.range(0.34, 0.60);
        const sway = spread * rng.range(0.30, 0.62);
        const tip = v2(crown.x + sway * len, crown.y - len);
        const knee = v2(crown.x + sway * len * 0.35, crown.y - len * 0.62);
        const col = if (@mod(@as(f32, @floatFromInt(i)), 3.0) == 0) WEED_DK else if (@mod(@as(f32, @floatFromInt(i)), 2.0) == 0) WEED else WEED_LT;
        rl.drawLineEx(crown, knee, 1.9 * k, col);
        rl.drawLineEx(knee, tip, 1.1 * k, col);
        if (len > s * 0.46) {
            var b: u32 = 0;
            while (b < 3) : (b += 1) {
                const t = 0.72 + @as(f32, @floatFromInt(b)) * 0.11;
                rl.drawCircleV(v2(mathx.lerpF(crown.x, tip.x, t), mathx.lerpF(crown.y, tip.y, t)), 0.9 * k, WEED_DK);
            }
        }
    }
    var d: u32 = 0;
    while (d < 4) : (d += 1) {
        rl.drawCircleV(
            v2(crown.x + rng.range(-0.13, 0.13) * s, crown.y + rng.range(0.02, 0.10) * s),
            rng.range(0.7, 1.5) * k,
            rgba(52, 40, 30, 220),
        );
    }
}

fn koboldFang(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0xFA46);
    const rootP = v2(cx - s * 0.16 + rng.range(-0.02, 0.02) * s, cy + s * 0.32);
    const tipP = v2(cx + s * 0.20, cy - s * 0.34);
    const bend = rng.range(0.14, 0.24);
    const SEGS = 14;
    var prev = rootP;
    for (0..SEGS + 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / SEGS;
        const p = onAxis(rootP, tipP, t, -bend * s * (4.0 * t * (1.0 - t)));
        const w = mathx.lerpF(4.6, 0.5, t * t * 0.85 + t * 0.15) * k;
        const col = mathx.lerpColor(BONE_DK, BONE, mathx.clampF(t * 1.25, 0, 1));
        if (i > 0) rl.drawLineEx(prev, p, w, col);
        prev = p;
    }
    const midOut = onAxis(rootP, tipP, 0.45, -bend * s * 1.16);
    rl.drawLineEx(onAxis(rootP, tipP, 0.18, -bend * s * 0.72), midOut, 1.0 * k, rgba(255, 250, 236, 190));
    rl.drawLineEx(onAxis(rootP, tipP, 0.30, -bend * s * 0.30), onAxis(rootP, tipP, 0.70, -bend * s * 0.34), 1.4 * k, rgba(150, 128, 86, 150));
    const cA = onAxis(rootP, tipP, 0.14, -1.8 * k);
    const cB = onAxis(rootP, tipP, 0.22, 2.4 * k);
    rl.drawLineEx(cA, v2((cA.x + cB.x) * 0.5 + 1.2 * k, (cA.y + cB.y) * 0.5), 0.9 * k, rgba(96, 82, 58, 220));
    rl.drawLineEx(v2((cA.x + cB.x) * 0.5 + 1.2 * k, (cA.y + cB.y) * 0.5), cB, 0.9 * k, rgba(96, 82, 58, 220));
    rl.drawCircleV(rootP, 2.2 * k, rgba(BONE_DK.r, BONE_DK.g, BONE_DK.b, 255));
    rl.drawCircleV(v2(rootP.x + 0.4 * k, rootP.y - 0.3 * k), 1.1 * k, rgba(88, 62, 52, 235));
}

fn ironKey(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x1204E7);
    const u = 0.70711;
    const lean = rng.range(-0.05, 0.05);
    const headP = v2(cx - u * s * 0.28 * (1 + lean), cy - u * s * 0.28);
    const tipP = v2(cx + u * s * 0.34, cy + u * s * 0.34 * (1 - lean));

    rl.drawLineEx(v2(headP.x + 1.2 * k, headP.y + 1.4 * k), v2(tipP.x + 1.2 * k, tipP.y + 1.4 * k), 3.0 * k, rgba(0, 0, 0, 120));
    rl.drawLineEx(headP, tipP, 2.4 * k, IRON_DK);
    rl.drawLineEx(onAxis(headP, tipP, 0.18, -0.9 * k), onAxis(headP, tipP, 0.86, -0.9 * k), 0.8 * k, rgba(STEEL_DK.r, STEEL_DK.g, STEEL_DK.b, 170));

    const ringR = s * 0.145;
    const ringC = onAxis(headP, tipP, -0.12, 0);
    arc(ringC.x, ringC.y, ringR + 0.6 * k, 0, std.math.tau, 18, 3.4 * k, 3.4 * k, rgba(0, 0, 0, 130));
    arc(ringC.x, ringC.y, ringR, 0, std.math.tau, 18, 2.6 * k, 2.6 * k, IRON_DK);
    arc(ringC.x, ringC.y, ringR, 3.5, 5.4, 9, 1.0 * k, 0.6 * k, rgba(STEEL_DK.r, STEEL_DK.g, STEEL_DK.b, 200));
    arc(ringC.x, ringC.y, ringR, 0.6, 2.1, 9, 1.4 * k, 1.0 * k, rgba(RUST.r, RUST.g, RUST.b, 220));
    rl.drawCircleV(onAxis(headP, tipP, 0.10, 0), 2.0 * k, IRON_DK);

    const across = v2(-(tipP.y - headP.y), tipP.x - headP.x);
    const alen = @max(@sqrt(across.x * across.x + across.y * across.y), 1e-4);
    const nx = across.x / alen;
    const ny = across.y / alen;
    for ([_][2]f32{ .{ 0.80, 5.2 }, .{ 0.96, 3.4 } }) |ward| {
        const base = onAxis(headP, tipP, ward[0], 0);
        const outT = ward[1] * k * rng.range(0.9, 1.1);
        rl.drawLineEx(base, v2(base.x + nx * outT, base.y + ny * outT), 2.2 * k, IRON_DK);
    }
    rl.drawCircleV(tipP, 1.3 * k, rgba(RUST.r, RUST.g, RUST.b, 200));
}

fn jerky(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x1E12C4);
    const capR = s * 0.32;
    const capH = s * 0.30;
    const rimY = cy - s * 0.02;
    const SEGS = 14;

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
    quad(
        v2(cx, rimY),
        v2(cx + stemTop, rimY),
        v2(footX + stemFoot, cy + s * 0.36),
        v2(footX + stemFoot * 0.25, cy + s * 0.36),
        mathx.lerpColor(CAP_DK, CAP_LT, 0.30),
    );
    var f: u32 = 0;
    while (f < 4) : (f += 1) {
        const x = footX + (@as(f32, @floatFromInt(f)) - 1.5) * s * 0.05;
        rl.drawLineEx(v2(x, cy + s * 0.345), v2(x + rng.range(-0.5, 0.5) * k, cy + s * 0.36 + rng.range(0.6, 1.4) * k), 1.0 * k, CAP_LT);
    }

    var gi: u32 = 0;
    while (gi < 9) : (gi += 1) {
        const t = (@as(f32, @floatFromInt(gi)) + 0.5) / 9.0;
        const x = cx - capR * 0.86 + capR * 1.72 * t;
        const drop = s * 0.075 * (1.0 - @abs(t - 0.5) * 1.5) * rng.range(0.8, 1.2);
        rl.drawLineEx(v2(x, rimY - s * 0.01), v2(x * 0.985 + cx * 0.015, rimY + drop), 1.0 * k, rgba(62, 40, 30, 205));
    }

    var prev = v2(cx - capR, rimY);
    for (1..SEGS + 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / SEGS;
        const a = std.math.pi * (1.0 - t);
        const shrink = rng.range(0.94, 1.05);
        const p = v2(cx + mathx.cosf(a) * capR * shrink, rimY - mathx.sinf(a) * capH * shrink);
        const shade = mathx.lerpColor(CAP_DK, CAP_LT, mathx.clampF(0.86 - t * 0.86, 0, 1));
        rl.drawTriangle(v2(cx, rimY), prev, p, shade);
        rl.drawTriangle(v2(cx, rimY), p, prev, shade);
        prev = p;
    }
    rl.drawLineEx(v2(cx - capR, rimY), v2(cx - capR * 0.82, rimY - s * 0.055), 1.2 * k, CAP_LT);
    rl.drawLineEx(v2(cx + capR, rimY), v2(cx + capR * 0.84, rimY - s * 0.045), 1.2 * k, CAP_LT);
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
