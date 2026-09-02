const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// **THE FORGE YARD** — the smith's four pieces (`npc.zig`'s `.smith`), the way `propmarket` is the caravaneer's.
// A yard, not a building: an anvil on a stump, a hooded hearth, a quench trough and a rack of tools, laid out
// by an author rather than welded into one mesh, so the same four dress a ruin, a camp or a village square.
//
// **IRON IS BOXED AND TIMBER IS ROUND** (the LAW). The anvil is planes and one horn; what is round here is the
// wood it stands on and the water it quenches in.
//
// **THESE ARE BIG SMOOTH MASSES AND THE FIRST CUT WAS AUTHORED FAR TOO LIGHT.** Shot alone, every one of them
// came back pale: a 0.6 m capsule of `art.TIMBER` reads at 180 on screen where the same albedo on a fence rail
// reads at 130, because a large sunward face takes the full key and the gamma lift does the rest. The family
// therefore carries its OWN timber and stone, a third under `propart`'s, and the values are solved down the
// chain rather than picked — screen = (albedo/255 x 1.72)^(1/2.2) x 255:
//     16 -> 93    26 -> 114    38 -> 136    58 -> 172    96 -> 210
const OAK = rgba(26, 20, 13, 255);
const OAK_LT = rgba(38, 29, 19, 255);
const OAK_DK = rgba(15, 12, 8, 255);
const MASON = rgba(26, 25, 22, 255);
const MASON_LT = rgba(38, 36, 32, 255);
const MASON_DK = rgba(15, 14, 13, 255);
const IRON = art.IRON;
const IRON_LT = rgba(38, 36, 34, 255);
/// The face of an anvil is POLISHED by its own work and nothing else on it is. It is the one bright band in the
/// yard and it is deliberately SMALL — a whole top plane at this value came back as a white tray.
const FACE = rgba(58, 62, 68, 255);
const FACE_DK = rgba(30, 32, 36, 255);
const SOOT = rgba(12, 11, 10, 255);
const LEATHER = rgba(30, 22, 15, 255);
const LEATHER_LT = rgba(44, 33, 22, 255);
const SLAG = rgba(18, 16, 14, 255);
/// The coal bed. **ALPHA IS THE EMISSIVE CHANNEL** and AGENTS.md reserves a low one for the things that ARE
/// light. This is the only fire in the yard and it is the whole point of the object.
const COAL = rgba(216, 88, 22, 52);
const COAL_HOT = rgba(250, 182, 84, 20);
const WATER = rgba(20, 27, 29, 255);

/// **`Builder.addCube` AND `addRoundBox` TAKE A FULL SIZE, NOT HALF-EXTENTS** (`gfx.zig`: `hx = size.x / 2`).
/// This file authored every mass as a HALF and handed it straight in — `HEARTH_HW` is *named* half-width — so
/// every box came out at half its span and the masses meant to meet stood apart instead. MEASURED in the
/// renders: the anvil's foot floated 25 mm over its own stump and its waist was a quarter of its authored
/// height, which is the "tray on a stem" it read as; the hearth block shrank inside its own courses and left
/// them hanging in a shell of grey lozenges around it and down onto the grass. The authored numbers stay
/// halves — they are what every dimension in this file is named for — and these two hand the API what it wants.
fn boxH(b: *Builder, c: rl.Vector3, half: rl.Vector3, col: rl.Color) void {
    b.addCube(c, v3(half.x * 2, half.y * 2, half.z * 2), col);
}
fn roundBoxH(b: *Builder, c: rl.Vector3, half: rl.Vector3, round: f32, segs: i32, sides: i32, col: rl.Color) void {
    b.addRoundBox(c, v3(half.x * 2, half.y * 2, half.z * 2), round, segs, sides, col);
}

// ── THE ANVIL ─────────────────────────────────────────────────────────────────────────────────────────────
// **HIS.** Everything else in the yard is furniture; this is the thing the character is defined by hitting.

/// Height of the working face off the ground. **SOLVED, NOT PICKED** — `npc`'s stroke bottoms its hammer head
/// here and a test re-measures the pair every build. A giant bent over a low anvil is the whole read, so this
/// number MOVES whenever he does: it moved when `npc.SMITH_SIZE` did, and the rest of the
/// iron went with it rather than leaving a footstool under a 3.24 m body.
pub const ANVIL_FACE: f32 = 0.98;
pub const ANVIL_TOP: f32 = ANVIL_FACE + 0.02;
pub const ANVIL_R: f32 = 0.70;
const ANVIL_LEN: f32 = 0.98;
/// **THE WAIST IS THE SILHOUETTE.** First cut gave it 0.054 m of height between a foot and a body and the whole
/// thing read as a tray floating over a stump; a pinch has to be TALL to be a pinch.
const WAIST_H: f32 = 0.20;
/// **AND IT IS WIDE ENOUGH TO CARRY THE BODY.** At 0.098 the pinch was a dark stem against a lit stump and the
/// iron read as a tray hovering over a log — the same failure the height was raised to cure, from the other side.
const WAIST_HW: f32 = 0.130;
/// The block it is bedded on. Under half the iron's own height, or the anvil is a detail on a log — and WIDER
/// than the anvil's own foot, because a plate that overhangs its post reads as floating over it.
pub const STUMP_R: f32 = 0.370;
const STUMP_H: f32 = 0.52;

pub fn anvilMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5A17);
    stumpInto(&b, &rng, STUMP_H, STUMP_R);
    anvilBodyInto(&b, STUMP_H);
    // **NO SCATTER ON THE FLOOR.** Hammer scale was authored here as sixteen 6 mm discs and came back as a
    // carpet of WHITE LOZENGES: a disc that thin has every normal straight up into the key, so a near-black
    // albedo still lands at full brightness. Ground litter is a `decor` op the author places.
    return b.toModel(shader);
}

/// The oak block, and it is a ROUND thing under a square one — that contrast is most of why an anvil reads as
/// iron at all. Flat SAWN ends, because a butt of oak is cut and not grown to length.
fn stumpInto(b: *Builder, rng: *mathx.Rng, top: f32, r: f32) void {
    b.setMat(.wood);
    b.addCylinder(v3(0, 0, 0), v3(0, top, 0), r * 1.12, r, 11, OAK);
    // **A CYLINDER IS CAPLESS** (AGENTS.md) and the first cut left both ends open: from the shot harness's own
    // overhead you looked straight down INTO the stump, saw its far wall, and the anvil read as floating half a
    // metre over a barrel. An axis-flattened blob is the cap, at both ends.
    b.addBlob(v3(0, top - 0.012, 0), v3(r * 0.99, 0.016, r * 0.99), 3, 11, OAK);
    b.addBlob(v3(0, 0.012, 0), v3(r * 1.11, 0.016, r * 1.11), 3, 11, OAK_DK);
    // Bark still on it in strips — an oak butt, not a turned post, and the strips are what break the cylinder.
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const d = r * rng.range(0.86, 1.04);
        b.addCapsule(
            v3(mathx.cosf(a) * d, rng.range(0.0, 0.06), mathx.sinf(a) * d),
            v3(mathx.cosf(a) * d * 1.06, top * rng.range(0.55, 0.98), mathx.sinf(a) * d * 1.06),
            rng.range(0.024, 0.046),
            rng.range(0.018, 0.036),
            6,
            if (rng.float() < 0.5) OAK_DK else art.BARK_OLD,
        );
    }
    // THE END GRAIN, and the anvil covers most of it. It is the ONE lighter face and it is nearly all hidden.
    b.addBlob(v3(0, top - 0.004, 0), v3(r * 0.94, 0.010, r * 0.94), 3, 11, OAK_LT);
}

/// **A WIDE FOOT, A TALL PINCHED WAIST, A FLARED BODY AND A FACE.** Four masses, in that order, or it is a box.
fn anvilBodyInto(b: *Builder, base: f32) void {
    b.setMat(.steel);
    const halfL = ANVIL_LEN * 0.5;
    const faceY = ANVIL_FACE;
    const footTop = base + 0.100;
    const waistTop = footTop + WAIST_H;
    // The foot, splayed, with the four feet the casting always has.
    boxH(b, v3(0, (base + footTop) * 0.5, 0), v3(halfL * 0.62, (footTop - base) * 0.5, 0.135), IRON);
    for ([_]f32{ -1, 1 }) |sx| {
        for ([_]f32{ -1, 1 }) |sz| {
            boxH(b, v3(sx * halfL * 0.56, base + 0.020, sz * 0.112), v3(0.062, 0.022, 0.036), IRON_LT);
        }
    }
    // THE WAIST — and it is the tallest single mass on the thing.
    boxH(b, v3(0, (footTop + waistTop) * 0.5, 0), v3(WAIST_HW, WAIST_H * 0.5, 0.082), IRON);
    // The body, flaring out of the waist to carry the face.
    b.addBox(
        v3(0, (waistTop + faceY - 0.048) * 0.5, 0),
        v3(halfL * 0.60, 0, 0),
        v3(0, (faceY - 0.048 - waistTop) * 0.5, 0),
        v3(0, 0, 0.112),
        IRON,
    );
    // **THE FACE, AND THE STEP UNDER IT IS WHAT YOUR EYE READS THE TOP PLANE OFF.**
    boxH(b, v3(0, faceY - 0.030, 0), v3(halfL * 0.72, 0.020, 0.122), FACE_DK);
    boxH(b, v3(0, faceY - 0.006, 0), v3(halfL * 0.70, 0.008, 0.116), FACE);
    // THE HARDIE AND PRITCHEL HOLES — sunk, so they hold shadow at every hour.
    b.setMat(.plain);
    boxH(b, v3(halfL * 0.40, faceY - 0.008, 0), v3(0.024, 0.014, 0.024), SOOT);
    b.addCylinder(v3(halfL * 0.56, faceY - 0.016, 0), v3(halfL * 0.56, faceY + 0.002, 0), 0.013, 0.013, 6, SOOT);
    b.setMat(.steel);
    // THE HORN: a long cone off one end and the step down to it, which is what says anvil at fifteen metres.
    boxH(b, v3(-halfL * 0.80, faceY - 0.058, 0), v3(0.070, 0.028, 0.096), IRON_LT);
    b.addCylinder(v3(-halfL * 0.70, faceY - 0.040, 0), v3(-halfL * 1.36, faceY - 0.026, 0), 0.086, 0.018, 9, IRON_LT);
    b.addDome(v3(-halfL * 1.36, faceY - 0.026, 0), v3(-1, 0, 0), 0.018, 8, IRON_LT);
    // THE HEEL, squared off, with the tail the tongs live on.
    boxH(b, v3(halfL * 0.84, faceY - 0.052, 0), v3(0.058, 0.032, 0.104), IRON);
}

// ── THE HEARTH ────────────────────────────────────────────────────────────────────────────────────────────
// **THE FIRE IS THE OBJECT.** The first cut hung a 1.5 m stone panel on two legs over it, which came back as a
// pale billboard with the coal bed sunk out of sight behind its own lip — a forge you could not see the fire
// in. The hood is now a low tapered cowl that sits ON the block, the lip is a rim rather than a wall, and the
// bed stands PROUD of the table.

pub const FORGE_TOP: f32 = 2.05;
pub const FORGE_R: f32 = 1.05;
const HEARTH_Y: f32 = 0.86;
const HEARTH_HW: f32 = 0.72;
const HEARTH_HD: f32 = 0.56;
/// Where the coal bed sits, which is what `props.INFO` hangs the light on. **A LIGHT'S RADIUS MATTERS MORE
/// THAN ITS BRIGHTNESS** (AGENTS.md) — a forge has to POOL, so the reach is short.
pub const FORGE_LIGHT_Y: f32 = HEARTH_Y + 0.16;
pub const FORGE_LIGHT_R: f32 = 7.2;

pub fn forgeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0B6);
    // THE BLOCK: one dark mass, with the courses cut INTO its faces rather than glued onto them.
    b.setMat(.stone);
    boxH(&b, v3(0, HEARTH_Y * 0.5, 0), v3(HEARTH_HW, HEARTH_Y * 0.5, HEARTH_HD), MASON_DK);
    // **FEWER AND BIGGER.** Seventy pebbles read as a lattice at any distance; four courses of four read as
    // masonry, which is what a hearth block is.
    var course: i32 = 0;
    while (course < 4) : (course += 1) {
        const y = 0.12 + @as(f32, @floatFromInt(course)) * 0.205;
        if (y > HEARTH_Y - 0.08) break;
        var s: i32 = 0;
        while (s < 4) : (s += 1) {
            const u = (@as(f32, @floatFromInt(s)) / 3.0 - 0.5) * 2.0;
            const w = rng.range(0.150, 0.205);
            for ([_]f32{ 1, -1 }) |sz| {
                roundBoxH(&b, 
                    v3(u * HEARTH_HW * 0.72, y + rng.signed() * 0.010, sz * (HEARTH_HD - 0.025)),
                    v3(w, 0.086, 0.030),
                    0.024,
                    2,
                    6,
                    if (rng.float() < 0.25) MASON else MASON_DK,
                );
            }
        }
    }
    // THE TABLE, and a RIM rather than a wall: 0.03 m proud, so the bed inside it is visible from a standing
    // eye AND from the overhead the editor and the shot harness both use.
    boxH(&b, v3(0, HEARTH_Y + 0.022, 0), v3(HEARTH_HW + 0.04, 0.022, HEARTH_HD + 0.04), MASON);
    for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |d| {
        boxH(&b, 
            v3(d[0] * (HEARTH_HW - 0.02), HEARTH_Y + 0.058, d[1] * (HEARTH_HD - 0.02)),
            v3(if (d[0] == 0) HEARTH_HW + 0.03 else 0.055, 0.030, if (d[1] == 0) HEARTH_HD + 0.03 else 0.055),
            MASON_LT,
        );
    }
    // **THE COAL BED, PROUD OF ITS OWN RIM** — slag at the edge, white-hot in the middle, and the whole heap
    // standing over the stone rather than sitting in a hole in it.
    //
    // **AND IT IS `Mat.flame`, NOT `Mat.ember`.** The ember id is one of the two VERTEX-ANIMATED branches
    // (`shaders`' `> 11.5 && < 13.5`): it is for the sparks that FLY UP off a fire, driven by `setAnimY`, and a
    // static bed authored under it drifted off the hearth and out of the hood. `flameInto` is the shared fire
    // every other hearth in the game is built from, so the forge reuses it rather than growing a second one.
    b.setMat(.plain);
    b.addBlob(v3(0, HEARTH_Y + 0.048, 0), v3(HEARTH_HW * 0.70, 0.030, HEARTH_HD * 0.68), 4, 10, SLAG);
    b.setMat(.flame);
    b.setAnimY(HEARTH_Y + 0.09);
    var c: i32 = 0;
    while (c < 22) : (c += 1) {
        const a = rng.angle();
        const d = @sqrt(rng.float());
        const rr = rng.range(0.050, 0.090);
        b.addBlob(
            v3(mathx.cosf(a) * d * HEARTH_HW * 0.58, HEARTH_Y + 0.078 + (1.0 - d) * 0.040, mathx.sinf(a) * d * HEARTH_HD * 0.56),
            v3(rr, rr * 0.58, rr),
            3,
            7,
            if (d < 0.50) COAL_HOT else COAL,
        );
    }
    b.setAnimY(0);
    // …and three tongues off the middle of it, so the fire MOVES. `flameInto` animates its own.
    art.flameInto(&b, &rng, 0, HEARTH_Y + 0.115, 0, 0.62);
    b.setMat(.stone);
    // **THE HOOD IS ONE TAPERED MASS AND IT IS A CONE.** Two goes at it in boxes failed the same way twice: a
    // back wall with a slanted top and two cheeks left daylight between four slabs, and a stack of narrowing
    // boxes came back as a wedding cake. A truncated cone is ONE call with no seams to leave open, and a round
    // cowl over a square hearth is what a plastered hood actually is.
    // **AND IT STANDS WELL CLEAR OF THE FIRE, LEANING BACK.** Sat on the hearth at full width it was a KILN —
    // one clean shape that swallowed the coal bed whole, which is the fire the object exists to show. A hood is
    // a canopy with its front open: it starts above head-height of the work, it is narrower than the table, and
    // it leans off the back so you look straight in at the bed from where the smith stands.
    b.setMat(.stone);
    const hz = -HEARTH_HD * 0.30;
    const hoodBase = HEARTH_Y + 0.52;
    b.addCylinder(v3(0, hoodBase, hz - 0.06), v3(0, HEARTH_Y + 1.02, hz - 0.26), HEARTH_HW * 0.82, 0.185, 10, MASON_DK);
    // A collar where it meets the flue, which is what keeps the taper from reading as a funnel.
    b.addCylinder(v3(0, HEARTH_Y + 0.98, hz - 0.25), v3(0, HEARTH_Y + 1.06, hz - 0.27), 0.215, 0.215, 10, MASON);
    // …and the FLUE out of the top of it, capped so it is a pipe and not an open tube.
    b.addCylinder(v3(0, HEARTH_Y + 1.02, hz - 0.26), v3(0, FORGE_TOP, hz - 0.30), 0.185, 0.155, 9, MASON);
    b.addBlob(v3(0, FORGE_TOP - 0.02, hz - 0.30), v3(0.170, 0.030, 0.170), 3, 9, MASON_DK);
    // The two posts it stands on, at the BACK corners only — the front is open by construction.
    for ([_]f32{ -1, 1 }) |sx| {
        b.addCylinder(
            v3(sx * HEARTH_HW * 0.74, HEARTH_Y + 0.09, -HEARTH_HD * 0.72),
            v3(sx * HEARTH_HW * 0.60, hoodBase + 0.04, hz - 0.20),
            0.052,
            0.046,
            7,
            MASON,
        );
    }
    // THE THROAT is SOOTED, and it is the one dark hole the fire sits under.
    b.setMat(.plain);
    boxH(&b, v3(0, HEARTH_Y + 0.14, hz), v3(HEARTH_HW * 0.86, 0.030, HEARTH_HD * 0.50), SOOT);

    // THE BELLOWS: a leather bag between two boards, hung off the side rather than the back so it is not
    // behind the hood. Ribbed, because a smooth bag at this size is a pillow.
    const bx = -HEARTH_HW - 0.30;
    b.setMat(.leather);
    b.addBlob(v3(bx, HEARTH_Y - 0.18, 0.02), v3(0.115, 0.155, 0.27), 4, 9, LEATHER);
    var rib: i32 = 0;
    while (rib < 4) : (rib += 1) {
        const t = -0.11 + 0.075 * @as(f32, @floatFromInt(rib));
        b.addCylinder(v3(bx - 0.10, HEARTH_Y - 0.18 + t, -0.25), v3(bx - 0.10, HEARTH_Y - 0.18 + t, 0.29), 0.014, 0.014, 6, LEATHER_LT);
    }
    b.setMat(.wood);
    b.addBox(v3(bx - 0.02, HEARTH_Y - 0.02, 0.02), v3(0.028, 0, 0), v3(0, 0.030, 0), v3(0, 0, 0.26), OAK);
    b.addBox(v3(bx - 0.02, HEARTH_Y - 0.34, 0.02), v3(0.028, 0, 0), v3(0, 0.030, 0), v3(0, 0, 0.24), OAK_DK);
    b.addCapsule(v3(bx - 0.04, HEARTH_Y + 0.02, 0.02), v3(bx - 0.30, HEARTH_Y + 0.34, 0.02), 0.030, 0.024, 7, OAK_LT);
    // The tuyere: the iron pipe out of the bellows into the fire.
    b.setMat(.steel);
    b.addCylinder(v3(bx + 0.10, HEARTH_Y - 0.10, 0.02), v3(-HEARTH_HW * 0.40, HEARTH_Y + 0.04, 0.0), 0.036, 0.028, 7, IRON);
    return b.toModel(shader);
}

// ── THE QUENCH TROUGH ─────────────────────────────────────────────────────────────────────────────────────
// **A HOLLOWED LOG WITH SAWN ENDS.** The first cut built the outside as a capsule and it came back as a pale
// gas cylinder: rounded ends, no cut, and a 0.13 m slot for a hollow you could not see the water in.

pub const QUENCH_TOP: f32 = 0.62;
pub const QUENCH_R: f32 = 0.92;
const QUENCH_HL: f32 = 0.72;
/// Half-width of the OPENING. Wide: the water sheet is the read and a slot is not one.
const QUENCH_HW: f32 = 0.185;
const LOG_R: f32 = 0.285;

pub fn quenchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x9CE7);
    const axis = QUENCH_TOP - LOG_R;
    b.setMat(.wood);
    // FLAT ENDS: a cylinder and not a capsule, and the end grain is its own tone.
    b.addCylinder(v3(-QUENCH_HL, axis, 0), v3(QUENCH_HL, axis, 0), LOG_R, LOG_R * 0.97, 11, OAK);
    for ([_]f32{ -1, 1 }) |sx| {
        b.addCylinder(v3(sx * QUENCH_HL, axis, 0), v3(sx * (QUENCH_HL + 0.012), axis, 0), LOG_R * 0.99, LOG_R * 0.94, 11, OAK_LT);
    }
    // Bark strips down the outside, which is what stops the log being a pipe.
    var i: i32 = 0;
    while (i < 8) : (i += 1) {
        const a = rng.range(0.4, 2.7);
        const t0 = rng.range(-0.95, 0.2);
        const t1 = t0 + rng.range(0.5, 1.4);
        b.addCapsule(
            v3(t0 * QUENCH_HL, axis - mathx.sinf(a) * LOG_R * 0.96, mathx.cosf(a) * LOG_R * 0.96),
            v3(@min(t1, 0.98) * QUENCH_HL, axis - mathx.sinf(a) * LOG_R * 0.96, mathx.cosf(a) * LOG_R * 0.96),
            rng.range(0.018, 0.034),
            rng.range(0.014, 0.028),
            5,
            if (rng.float() < 0.5) OAK_DK else art.BARK_OLD,
        );
    }
    // **THE HOLLOW IS ADZED OUT AND IT IS WIDE.** Dark inside, so the water sheet in it has something to be
    // bright against — the trough's whole job is to be a black rectangle with a gloss on it.
    b.setMat(.plain);
    boxH(&b, v3(0, QUENCH_TOP - 0.075, 0), v3(QUENCH_HL * 0.90, 0.085, QUENCH_HW), SOOT);
    b.setMat(.wood);
    // The rim either side of the opening, which is what says hollowed rather than sliced.
    for ([_]f32{ -1, 1 }) |sz| {
        b.addCapsule(
            v3(-QUENCH_HL * 0.94, QUENCH_TOP - 0.030, sz * (QUENCH_HW + 0.040)),
            v3(QUENCH_HL * 0.94, QUENCH_TOP - 0.030, sz * (QUENCH_HW + 0.040)),
            0.042,
            0.042,
            7,
            OAK_LT,
        );
    }
    // Two chocks under it, and two iron bands: a log that holds water has already split once.
    for ([_]f32{ -1, 1 }) |sx| {
        boxH(&b, v3(sx * QUENCH_HL * 0.60, 0.055, 0), v3(0.095, 0.055, 0.24), OAK_DK);
    }
    b.setMat(.steel);
    for ([_]f32{ -0.56, 0.56 }) |t| {
        b.addCylinder(v3(t * QUENCH_HL - 0.020, axis, 0), v3(t * QUENCH_HL + 0.020, axis, 0), LOG_R * 1.03, LOG_R * 1.03, 11, IRON);
    }
    // **THE WATER, AND IT IS THE ONE GLOSS IN THE YARD** (`Mat.water`, the only real specular besides steel).
    // It sits BELOW the rim, or the trough is a solid block with a shiny lid.
    b.setMat(.water);
    boxH(&b, v3(0, QUENCH_TOP - 0.062, 0), v3(QUENCH_HL * 0.88, 0.004, QUENCH_HW * 0.94), WATER);
    b.setMat(.plant);
    var g: i32 = 0;
    while (g < 6) : (g += 1) {
        const a = rng.angle();
        const rr = rng.range(0.040, 0.075);
        b.addBlob(v3(mathx.cosf(a) * QUENCH_HL * 0.9, rr * 0.5, mathx.sinf(a) * 0.30), v3(rr, rr * 0.6, rr), 3, 6, art.MOSS_DK);
    }
    return b.toModel(shader);
}

// ── THE TOOL RACK ─────────────────────────────────────────────────────────────────────────────────────────

pub const RACK_TOP: f32 = 1.72;
pub const RACK_HW: f32 = 0.62;

pub fn toolRackMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x700D);
    b.setMat(.wood);
    for ([_]f32{ -1, 1 }) |sx| {
        b.addCapsule(v3(sx * RACK_HW, 0, 0.02), v3(sx * RACK_HW + rng.signed() * 0.02, RACK_TOP, 0), 0.062, 0.052, 8, OAK);
    }
    b.addCylinder(v3(-RACK_HW, RACK_TOP - 0.16, 0), v3(RACK_HW, RACK_TOP - 0.16, 0), 0.046, 0.046, 7, OAK_DK);
    b.addCylinder(v3(-RACK_HW, RACK_TOP * 0.40, 0.02), v3(RACK_HW, RACK_TOP * 0.40, 0.02), 0.040, 0.040, 7, OAK_DK);
    // FIVE TOOLS, and no two the same length — a rack where every peg hangs to the same height reads as a shop
    // display. **THE HEADS ARE BIG**: at 18 m a hammer head under 0.10 m is four grey pixels and says nothing.
    const Tool = enum { hammer, tongs, sledge };
    const hang = [_]struct { x: f32, drop: f32, head: f32, kind: Tool }{
        .{ .x = -0.44, .drop = 0.46, .head = 0.115, .kind = .hammer },
        .{ .x = -0.16, .drop = 0.66, .head = 0.090, .kind = .hammer },
        .{ .x = 0.08, .drop = 0.84, .head = 0.070, .kind = .tongs },
        .{ .x = 0.33, .drop = 0.56, .head = 0.135, .kind = .sledge },
        .{ .x = 0.53, .drop = 0.74, .head = 0.062, .kind = .tongs },
    };
    for (hang) |t| {
        const topY = RACK_TOP - 0.16;
        const botY = topY - t.drop;
        b.setMat(.wood);
        b.addCapsule(v3(t.x, topY, 0.01), v3(t.x + rng.signed() * 0.03, botY + t.head, 0.01), 0.024, 0.020, 6, if (rng.float() < 0.4) OAK_LT else OAK);
        b.setMat(.steel);
        switch (t.kind) {
            // A HAMMER: a square head across the haft, with a lighter face on one end.
            .hammer => {
                boxH(&b, v3(t.x, botY + t.head * 0.5, 0.01), v3(t.head * 1.5, t.head * 0.60, t.head * 0.60), IRON);
                boxH(&b, v3(t.x + t.head * 1.5, botY + t.head * 0.5, 0.01), v3(t.head * 0.14, t.head * 0.52, t.head * 0.52), FACE_DK);
            },
            // TONGS: two legs off one pivot, hanging open.
            .tongs => {
                for ([_]f32{ -1, 1 }) |sx| {
                    b.addCapsule(
                        v3(t.x, botY + t.head, 0.01),
                        v3(t.x + sx * t.head * 1.4, botY - t.head * 2.4, 0.01),
                        0.017,
                        0.012,
                        5,
                        IRON,
                    );
                }
                b.addCylinder(v3(t.x, botY + t.head, -0.01), v3(t.x, botY + t.head, 0.03), 0.024, 0.024, 6, IRON_LT);
            },
            // A SLEDGE, the heaviest thing on the wall and hung where he can get two hands to it.
            .sledge => {
                boxH(&b, v3(t.x, botY + t.head * 0.5, 0.01), v3(t.head * 0.85, t.head * 0.95, t.head * 0.75), IRON);
                boxH(&b, v3(t.x, botY - t.head * 0.42, 0.01), v3(t.head * 0.50, t.head * 0.14, t.head * 0.50), FACE_DK);
            },
        }
    }
    // THE BARREL OF STOCK at its foot: bar ends standing on end, which is where a smith keeps them. **NO
    // BRIGHT BAR** — one `IRON_LT` cylinder in here came back pure white end-on to the key.
    b.setMat(.wood);
    b.addCylinder(v3(RACK_HW + 0.32, 0, -0.12), v3(RACK_HW + 0.32, 0.48, -0.12), 0.245, 0.225, 9, OAK);
    for ([_]f32{ 0.10, 0.36 }) |t| {
        b.setMat(.steel);
        b.addCylinder(v3(RACK_HW + 0.32, t, -0.12), v3(RACK_HW + 0.32, t + 0.035, -0.12), 0.252, 0.252, 9, IRON);
        b.setMat(.wood);
    }
    b.setMat(.steel);
    for ([_]f32{ 0, 1, 2, 3, 4, 5, 6 }) |k| {
        const a = k * 0.90 + 0.4;
        const d = rng.range(0.03, 0.16);
        const lean = rng.range(0.08, 0.26);
        const foot = v3(RACK_HW + 0.32 + mathx.cosf(a) * d, 0.42, -0.12 + mathx.sinf(a) * d);
        b.addCylinder(
            foot,
            v3(foot.x + mathx.cosf(a) * lean, 0.42 + rng.range(0.28, 0.62), foot.z + mathx.sinf(a) * lean),
            0.019,
            0.017,
            5,
            IRON,
        );
    }
    return b.toModel(shader);
}

test "THE ANVIL'S FACE IS THE NUMBER THE SMITH IS BUILT AGAINST, and its waist is a real pinch" {
    // `npc.SMITH_ANVIL_Z` and this face height are one solve; the test beside the stroke re-measures the pair.
    try std.testing.expect(ANVIL_TOP >= ANVIL_FACE);
    try std.testing.expect(ANVIL_FACE > STUMP_H);
    // The horn runs past the body, so the bounding radius has to hold it.
    try std.testing.expect(ANVIL_R >= ANVIL_LEN * 0.5 * 1.36 + 0.02);
    // **THE PINCH HAS TO BE TALL TO BE A PINCH.** At 0.054 m of height between a foot and a body the first cut
    // read as a tray floating over a log; the waist is now the tallest single mass on the iron.
    try std.testing.expect(WAIST_H > (ANVIL_FACE - STUMP_H) * 0.4);
    try std.testing.expect(WAIST_HW < ANVIL_LEN * 0.5 * 0.60);
    std.debug.print("\n  anvil: face {d:.2} m, stump {d:.2} m x r{d:.2}, waist {d:.2} m tall and {d:.2} m wide, horn out to {d:.2} m\n", .{
        ANVIL_FACE, STUMP_H, STUMP_R, WAIST_H, WAIST_HW * 2.0, ANVIL_LEN * 0.5 * 1.36,
    });
}

test "THE FORGE'S FIRE IS VISIBLE FROM ABOVE — the bed stands proud of its own rim" {
    // The rim tops out at `HEARTH_Y + 0.088` and the coal heap at `HEARTH_Y + 0.12`+. A bed sunk behind its lip
    // is a forge with no fire in it, which is what the first cut was.
    const rimTop = HEARTH_Y + 0.058 + 0.030;
    const bedTop = HEARTH_Y + 0.075 + 0.045 + 0.082 * 0.62;
    try std.testing.expect(bedTop > rimTop);
    try std.testing.expect(FORGE_LIGHT_Y > HEARTH_Y and FORGE_LIGHT_Y < bedTop + 0.2);
    // **A LIGHT'S RADIUS MATTERS MORE THAN ITS BRIGHTNESS** — a forge that reached like a bonfire would flatten
    // the yard it is meant to be the one bright thing in.
    try std.testing.expect(FORGE_LIGHT_R < 9.0);
    try std.testing.expect(FORGE_TOP > HEARTH_Y + 1.0);
    std.debug.print("  forge: table {d:.2} m, rim tops {d:.2} m, coal tops {d:.2} m ({d:.0} mm proud), flue to {d:.2} m, light {d:.1} m\n", .{
        HEARTH_Y, rimTop, bedTop, (bedTop - rimTop) * 1000.0, FORGE_TOP, FORGE_LIGHT_R,
    });
}

test "THE TROUGH IS A HOLLOW YOU CAN SEE THE WATER IN, and the water is under the rim" {
    // The opening is WIDE — a slot reads as a saw cut, not as a trough.
    try std.testing.expect(QUENCH_HW > LOG_R * 0.55);
    // …and the sheet sits below the rim, or the thing is a solid block with a gloss on top.
    const rim = QUENCH_TOP - 0.030 + 0.042;
    try std.testing.expect(QUENCH_TOP - 0.062 < rim);
    try std.testing.expect(QUENCH_R > QUENCH_HL + LOG_R * 0.5);
    std.debug.print("  trough: {d:.2} m long, opening {d:.2} m across of a {d:.2} m log, water {d:.0} mm under the rim\n", .{
        QUENCH_HL * 2.0, QUENCH_HW * 2.0, LOG_R * 2.0, (rim - (QUENCH_TOP - 0.062)) * 1000.0,
    });
}
