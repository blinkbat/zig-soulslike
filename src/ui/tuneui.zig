const std = @import("std");
const rl = @import("raylib");

const hud = @import("hud.zig");
const mathx = @import("../core/mathx.zig");
const tune = @import("../play/tune.zig");
const ui = @import("ui.zig");

/// **THE STATS BENCH'S FACE** (owner: easy viewing and editing of stats, filed with the object viewer so you can
/// see the thing and its numbers side by side). One file, because the same field column is drawn in two places:
/// the editor's own sheet, and beside the model in `ui/objview.zig`.
///
/// Every number here is `play/tune.zig`'s. Nothing in this file knows what a spell or a shield IS.
pub const State = struct {
    tab: usize = 0,
    row: usize = 0,
    scroll: i32 = 0,
};

pub const ROW_H: i32 = 22;
const GAP: i32 = 2;

const MAX_ROWS = blk: {
    var m: usize = 0;
    for (tune.TABLES) |t| m = @max(m, t.n);
    break :blk m;
};

var nameBuf: [MAX_ROWS][:0]const u8 = undefined;

fn rowNames(t: usize) []const [:0]const u8 {
    const tb = tune.TABLES[t];
    for (0..tb.n) |i| nameBuf[i] = tb.rowName(i);
    return nameBuf[0..tb.n];
}

/// Decimals from the STEP, so a 0.01 dial does not read as 0.1 and a whole number does not trail a point. The
/// stock stepper prints one place for everything, which turned a 0.06 drop rate into 0.1 on the screen.
fn places(step: f32, int: bool) u8 {
    if (int) return 0;
    if (step >= 1.0) return 1;
    if (step >= 0.05) return 2;
    return 3;
}

fn print(buf: []u8, v: f32, dp: u8) [:0]const u8 {
    return switch (dp) {
        0 => std.fmt.bufPrintZ(buf, "{d:.0}", .{v}) catch "?",
        1 => std.fmt.bufPrintZ(buf, "{d:.1}", .{v}) catch "?",
        2 => std.fmt.bufPrintZ(buf, "{d:.2}", .{v}) catch "?",
        else => std.fmt.bufPrintZ(buf, "{d:.3}", .{v}) catch "?",
    };
}

/// Named once: the row Revert is drawn on the bench's own header AND beside the model in the object viewer.
const REVERT: [:0]const u8 = "Revert";
const REVERT_TIP: [:0]const u8 = "This row back to the numbers in the code";

const NUDGE_W: i32 = 18;
const VAL_W: i32 = 66;
/// Pixels of drag that step the value once — a scrub, so a long ladder is one gesture and not forty clicks.
const SCRUB_PX: f32 = 6.0;

var scrubFrom: f32 = 0;
var scrubAt: f32 = 0;

/// ONE DIAL. Returns true if it moved.
fn dial(ctx: *ui.Ctx, x: i32, y: i32, w: i32, t: usize, r: usize, c: usize) bool {
    const col = tune.colSpec(t, r, c);
    const v = tune.value(t, r, c);
    const was = tune.baseValue(t, r, c);
    const dp = places(col.step, col.int);
    const hit = tune.edited(t, r, c);

    const whole = ui.rect(x, y, w, ROW_H);
    ui.tipFor(ctx, whole, col.tip);
    hud.mono(col.name, x, y + 4, hud.MONO, if (hit) ui.HOT else ui.LABEL);

    const bx = x + w - NUDGE_W * 2 - VAL_W;
    var moved = false;
    if (ui.button(ctx, ui.rect(bx, y, NUDGE_W, ROW_H - 2), "-", hud.MONO, false, col.tip)) {
        tune.setValue(t, r, c, v - col.step);
        moved = true;
    }
    if (ui.button(ctx, ui.rect(bx + NUDGE_W + VAL_W, y, NUDGE_W, ROW_H - 2), "+", hud.MONO, false, col.tip)) {
        tune.setValue(t, r, c, v + col.step);
        moved = true;
    }

    // The readout is also the grab handle.
    const valR = ui.rect(bx + NUDGE_W, y, VAL_W, ROW_H - 2);
    if (ctx.owns(valR)) {
        if (ctx.pressed) {
            scrubFrom = v;
            scrubAt = ctx.mouse.x;
        } else if (ctx.down) {
            const steps = @round((ctx.mouse.x - scrubAt) / SCRUB_PX);
            const want = scrubFrom + steps * col.step;
            if (want != v) {
                tune.setValue(t, r, c, want);
                moved = true;
            }
        }
    }
    var buf: [24]u8 = undefined;
    const s = print(&buf, tune.value(t, r, c), dp);
    if (ctx.hot(valR)) rl.drawRectangleRec(valR, ui.HOVER_FILL);
    hud.mono(s, @as(i32, @intFromFloat(valR.x)) + @divTrunc(VAL_W - hud.monoW(s, hud.MONO), 2), y + 4, hud.MONO, if (hit) ui.HOT else ui.VALUE);
    // **WHAT THE CODE SAYS, BESIDE WHAT YOU MADE IT SAY.** An edited dial with no original next to it is a
    // number you cannot judge and cannot put back by hand.
    if (hit) {
        var ob: [24]u8 = undefined;
        const os = print(&ob, was, dp);
        hud.mono(os, x + @divTrunc(w, 2) - hud.monoW(os, hud.MONO) - 8, y + 4, hud.MONO, ui.alpha(ui.LABEL, 150));
    }
    return moved;
}

/// **THE FIELD COLUMN FOR ONE ROW.** Draws only the dials that row actually has and returns the y it ended at,
/// so the caller can stack something under it. Used by the bench and by the object viewer both.
pub fn fields(ctx: *ui.Ctx, x: i32, y: i32, w: i32, t: usize, r: usize) i32 {
    var cy = y;
    for (0..tune.TABLES[t].cols.len) |c| {
        if (!tune.shows(t, r, c)) continue;
        _ = dial(ctx, x, cy, w, t, r, c);
        cy += ROW_H + GAP;
    }
    return cy;
}

pub fn rowHeight(t: usize, r: usize) i32 {
    var n: i32 = 0;
    for (0..tune.TABLES[t].cols.len) |c| {
        if (tune.shows(t, r, c)) n += 1;
    }
    return n * (ROW_H + GAP);
}

/// A title line with the row's name and whether it has been moved off the code, plus its Revert.
pub fn header(ctx: *ui.Ctx, x: i32, y: i32, w: i32, t: usize, r: usize) void {
    const tb = tune.TABLES[t];
    hud.mono(tb.rowName(r), x, y, hud.MONO, ui.TITLE);
    if (tune.rowEdited(t, r)) {
        hud.mono("EDITED", x + w - hud.monoW("EDITED", hud.MONO) - 76, y, hud.MONO, ui.HOT);
        if (ui.button(ctx, ui.rect(x + w - 72, y - 4, 72, 20), REVERT, hud.MONO, false, REVERT_TIP)) tune.revertRow(t, r);
    }
}

/// Where a thing's numbers live — what lets the object viewer stand the sheet beside the model. EVERY row that
/// names it, not the first: a creature has its pools, its drop and one row per stroke it swings.
pub const FACE_MAX = 20;

pub const Hit = struct { t: usize, r: usize };

pub fn forFace(face: tune.Face, ordinal: u32, out: *[FACE_MAX]Hit) []const Hit {
    var n: usize = 0;
    for (tune.TABLES, 0..) |tb, ti| {
        if (tb.face != face) continue;
        const of = tb.faceOf orelse continue;
        for (0..tb.n) |r| {
            if (n >= FACE_MAX) break;
            if (of(r) != ordinal) continue;
            out[n] = .{ .t = ti, .r = r };
            n += 1;
        }
    }
    return out[0..n];
}

/// **THE WHOLE SHEET, BESIDE ITS THING.** The object viewer's own panel: the tables that know this face,
/// stacked, each under its own name. Returns the y it ended at.
pub fn faceSheet(ctx: *ui.Ctx, x: i32, y: i32, w: i32, face: tune.Face, ordinal: u32, bottom: i32) i32 {
    var hits: [FACE_MAX]Hit = undefined;
    const found = forFace(face, ordinal, &hits);
    const line = hud.monoLineH(hud.MONO);
    var cy = y;
    var lastTable: ?usize = null;
    var left: usize = 0;
    for (found, 0..) |h, i| {
        // **WHAT FITS, AND AN HONEST COUNT OF WHAT DOES NOT.** A knight has six strokes at nine dials apiece and
        // the column beside his portrait is not eleven hundred pixels tall.
        if (cy + rowHeight(h.t, h.r) + line * 2 > bottom) {
            left = found.len - i;
            break;
        }
        if (lastTable == null or lastTable.? != h.t) {
            hud.mono(tune.TABLES[h.t].name, x, cy, hud.MONO, ui.alpha(ui.TRIM, 230));
            cy += line + 3;
            lastTable = h.t;
        }
        // A table that puts SEVERAL rows on one body says which is which; one that puts a single row does not
        // need to repeat its own name.
        if (multiRow(found, h.t)) {
            hud.mono(tune.TABLES[h.t].rowName(h.r), x + 8, cy, hud.MONO, ui.alpha(ui.LABEL, 210));
            cy += line + 1;
        }
        if (tune.rowEdited(h.t, h.r)) {
            if (ui.button(ctx, ui.rect(x + w - 66, cy - line, 66, 18), REVERT, hud.MONO, false, REVERT_TIP)) tune.revertRow(h.t, h.r);
        }
        cy = fields(ctx, x, cy, w, h.t, h.r) + 5;
    }
    if (left > 0) {
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrintZ(&buf, "+{d} more on the Stats bench", .{left}) catch "";
        hud.mono(s, x, cy, hud.MONO, ui.alpha(ui.LABEL, 150));
        cy += line;
    }
    return cy;
}

fn multiRow(found: []const Hit, t: usize) bool {
    var n: usize = 0;
    for (found) |h| n += @intFromBool(h.t == t);
    return n > 1;
}

/// **THIRTEEN TABS WIDE.** The row divides evenly, so the frame is sized off the LONGEST sheet name rather
/// than the content under it: at 940 the ninth character of "Armaments" sat on top of its neighbour.
pub const W: i32 = 1180;
pub const H: i32 = 660;
const LIST_W: i32 = 310;
const PAD: i32 = 20;

/// **THE BENCH.** Tables across the top, their rows down the left, that row's dials on the right. False when it
/// has been closed.
pub fn panel(st: *State, ctx: *ui.Ctx) bool {
    const box = ui.beginModal(ctx, W, H, "Stats");
    st.tab = @min(st.tab, tune.NT - 1);

    var labels: [tune.NT][:0]const u8 = undefined;
    var tips: [tune.NT][:0]const u8 = undefined;
    inline for (tune.TABLES, 0..) |tb, i| {
        labels[i] = tb.name;
        tips[i] = tb.tip;
    }
    if (ui.tabs(ctx, box.x + PAD, box.y + 44, W - 2 * PAD, &labels, st.tab, &tips)) |i| {
        if (i != st.tab) {
            st.tab = i;
            st.row = 0;
            st.scroll = 0;
        }
    }

    const tb = tune.TABLES[st.tab];
    st.row = @min(st.row, tb.n - 1);
    const listY = box.y + 44 + ui.TAB_H + 10;
    const listH = H - (listY - box.y) - 66;
    if (ui.list(ctx, ui.rect(box.x + PAD, listY, LIST_W, listH), rowNames(st.tab), st.row, &st.scroll, tb.tip)) |i| st.row = i;

    const cx = box.x + PAD + LIST_W + 24;
    const cw = W - (cx - box.x) - PAD;
    // **THE DIALS SIT UNDER THE NAME, NOT OUT AT THE FRAME.** Given the whole column the readout ends up a
    // hand's width from its own label and the pair stops reading as one row.
    const fieldW = @min(cw, 340);
    var cy = listY + 2;
    header(ctx, cx, cy, fieldW, st.tab, st.row);
    cy += hud.monoLineH(hud.MONO) + 10;
    cy = fields(ctx, cx, cy, fieldW, st.tab, st.row);

    var buf: [96]u8 = undefined;
    const count = std.fmt.bufPrintZ(&buf, "{d}/{d} in {s}", .{ st.row + 1, tb.n, tb.name }) catch "";
    hud.mono(count, cx, box.y + H - 88, hud.MONO, ui.alpha(ui.LABEL, 190));
    hud.mono("drag a number to scrub it", cx, box.y + H - 88 + hud.monoLineH(hud.MONO), hud.MONO, ui.alpha(ui.LABEL, 150));

    const by = box.y + H - 40;
    var bx = box.x + PAD;
    if (ui.button(ctx, ui.rect(bx, by, 120, 24), "Revert table", hud.MONO, tune.tableEdited(st.tab), "Every row in this table back to the code")) tune.revertTable(st.tab);
    bx += 128;
    if (ui.button(ctx, ui.rect(bx, by, 100, 24), "Revert all", hud.MONO, tune.anyEdited(), "Every number in the game back to the code")) tune.revertAll();
    bx += 108;
    if (ui.button(ctx, ui.rect(bx, by, 100, 24), "Save", hud.MONO, false, "Write the edited numbers over tuning.cfg")) tune.save();
    if (ui.button(ctx, ui.rect(box.x + W - PAD - 90, by, 90, 24), "Done", hud.MONO, false, "Close the bench. Edited numbers stay edited until you revert them")) {
        tune.save();
        return false;
    }
    return true;
}
