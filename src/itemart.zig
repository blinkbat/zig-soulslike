const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const uiart = @import("uiart.zig");
const item = @import("item.zig");

// PICTURES OF THINGS — the armaments in the HUD's cross and every kind in the bag, shared by the HUD and
// the character book the way uiart.zig's chrome is. They are drawn as OBJECTS rather than as glyphs: a
// blade has a taper, a fuller and an edge that catches the light; a shield has boards, a binding and
// rivets; a flask has glass, a liquid line and a wax seal. Three rules hold the set together:
//
// - **EVERY STROKE SCALES OFF `k`.** The set was tuned in a 34 px box (`TUNED_AT`) and multiplies up, so
//   one picture serves a 33 px bag cell and a 240 px detail plate.
// - **WABI-SABI, BUT DETERMINISTIC.** Nothing here is machined: unequal guard arms, planks of different
//   widths, a nicked edge, a stopper off plumb. Every offset comes out of a FIXED-SEED `mathx.Rng`
//   re-seeded on each call, so the icon is imperfect and *the same imperfection every frame*. Drawing off
//   a live stream would make the whole HUD crawl.
// - **ONE PICTURE PER KIND, RESOLVED IN `draw`.** Nothing else asks what an item looks like.

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
const WEED = rgba(126, 30, 34, 255); // bloodgrass: dried arterial red, not a leaf green
const WEED_LT = rgba(178, 62, 52, 255);
const WEED_DK = rgba(74, 20, 24, 255);
const CAP_DK = rgba(96, 58, 42, 255); // dried mushroom: the leathery outside…
const CAP_LT = rgba(158, 108, 72, 255); // …and the pale torn flesh
const SALT = rgba(226, 208, 176, 255);

/// THE BOX EVERY STROKE WAS TUNED IN. A picture drawn at `px` multiplies each weight by `px / TUNED_AT`.
pub const TUNED_AT: f32 = 34.0;

fn strokeK(px: f32) f32 {
    return px / TUNED_AT;
}

/// Two triangles making one quad, WOUND WHICHEVER WAY RAYLIB WILL ACTUALLY RASTERISE. It culls a
/// back-facing 2D triangle (see `arrow`, which is the one that proved it), so a quad handed over the
/// wrong way round is silently not drawn — and that is exactly how the sword icon's blade body went
/// missing: the picture was its point triangle plus two hairlines, which is to say a dagger. Callers give
/// the four corners in order and stop caring.
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
    switch (k) {
        .crimson_flask => flask(cx, cy, px, .crimson, true),
        .cerulean_flask => flask(cx, cy, px, .cerulean, true),
        .rune_arc => runeArc(cx, cy, px),
        .golden_seed => goldenSeed(cx, cy, px),
        .smithing_stone => smithingStone(cx, cy, px),
        .bloodgrass => bloodgrass(cx, cy, px),
        .kobold_fang => koboldFang(cx, cy, px),
        .iron_key => ironKey(cx, cy, px),
        .mushroom_jerky => jerky(cx, cy, px),
    }
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
    // THE BULB, SHADED FROM THE DARK SIDE OUT: the deep tone is the whole ball and the lit fill is a
    // slightly smaller one set up and left inside it, so what shows of the deep is a crescent along the
    // bottom-right rim. THERE IS NO CLIPPING HERE, which is what killed the three attempts before it —
    // a concentric dark circle is a bubble, a sector cuts the flask in half, and a big offset circle
    // (the obvious way round) spills its far side across the HUD and the world behind it.
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

/// ELDEN RING'S OWN PATTERN, and the owner's call: MOSTLY HILT, AND THE BLADE FADES OUT. A whole sword
/// scaled to fit a 44×60 socket is a dagger — that is what it read as — because everything that says
/// LONG about a longsword is the part there is no room for. So the hilt is drawn big and jewelled down
/// in the frame and the steel runs off the top losing itself, which reads as a blade that continues.
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
fn runeArc(cx: f32, cy: f32, px: f32) void {
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
    const lit = rng.range(0, N - 1);
    const li: usize = @intFromFloat(lit);
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

/// A STRIP OF DRIED CAP, curling as it dries, torn at both ends and dusted with the salt it was kept in.
/// The read is LEATHERY: a wavy band, dark outside and pale where the flesh was torn open.
fn jerky(cx: f32, cy: f32, px: f32) void {
    const s = px;
    const k = strokeK(px);
    var rng = mathx.Rng.init(0x1E12C4);
    const len = s * 0.72;
    const x0 = cx - len * 0.5;
    const wobble = s * 0.10;
    const SEGS = 12;
    // The strip: a run of quads following a sine, each a hair thinner than the last towards the ends —
    // a rectangle here reads as a plank and a smooth taper as a leaf.
    var prevT = v2(0, 0);
    var prevB = v2(0, 0);
    for (0..SEGS + 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / SEGS;
        const x = x0 + len * t;
        const y = cy + mathx.sinf(t * 4.1 + 0.6) * wobble;
        const half = s * (0.13 - 0.06 * @abs(t - 0.5) * 2.0) * rng.range(0.88, 1.12);
        const top = v2(x, y - half);
        const bot = v2(x, y + half);
        if (i > 0) {
            const shade = mathx.lerpColor(CAP_DK, CAP_LT, 0.25 + 0.5 * (1.0 - @abs(t - 0.42) * 2.0));
            quad(prevT, top, bot, prevB, shade);
        }
        prevT = top;
        prevB = bot;
    }
    // THE TORN ENDS: pale fibres, not a clean cut.
    for ([_]f32{ 0.0, 1.0 }) |end| {
        const x = x0 + len * end;
        const y = cy + mathx.sinf(end * 4.1 + 0.6) * wobble;
        var f: u32 = 0;
        while (f < 3) : (f += 1) {
            const off = (@as(f32, @floatFromInt(f)) - 1.0) * s * 0.055;
            const out = (if (end > 0.5) @as(f32, 1) else @as(f32, -1)) * rng.range(1.4, 3.2) * k;
            rl.drawLineEx(v2(x, y + off), v2(x + out, y + off + rng.range(-1.0, 1.0) * k), 1.1 * k, CAP_LT);
        }
    }
    // The curl along the top edge, the gills as dark ticks underneath, and the salt.
    rl.drawLineEx(v2(x0 + len * 0.06, cy - s * 0.10), v2(x0 + len * 0.94, cy - s * 0.06), 1.1 * k, rgba(196, 156, 112, 150));
    var g: u32 = 0;
    while (g < 6) : (g += 1) {
        const t = 0.16 + @as(f32, @floatFromInt(g)) * 0.13;
        const x = x0 + len * t;
        const y = cy + mathx.sinf(t * 4.1 + 0.6) * wobble;
        rl.drawLineEx(v2(x, y + s * 0.01), v2(x + rng.range(-0.8, 0.8) * k, y + s * 0.075), 0.9 * k, rgba(70, 44, 32, 190));
    }
    var sa: u32 = 0;
    while (sa < 5) : (sa += 1) {
        const t = rng.range(0.12, 0.88);
        const x = x0 + len * t;
        const y = cy + mathx.sinf(t * 4.1 + 0.6) * wobble + rng.range(-0.7, 0.7) * s * 0.09;
        rl.drawCircleV(v2(x, y), rng.range(0.4, 0.9) * k, rgba(SALT.r, SALT.g, SALT.b, 190));
    }
}
