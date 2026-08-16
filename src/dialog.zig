const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const wf = @import("worldfmt.zig");
const trigger = @import("trigger.zig");
const gfx = @import("gfx.zig");
const npcmod = @import("npc.zig"); // for the PORTRAIT FRAMING only — never for a body
const hud = @import("hud.zig");
const uiart = @import("uiart.zig");
const sfx = @import("audio.zig");

const rgba = mathx.rgba;
const v3 = mathx.v3;

// A CONVERSATION, and the panel it is read off.
//
// The tree is map data; this is the walk through it. One node is on screen at a time: what is said, and
// either the lines you may answer with or a Continue. A node's `act:` fires when it is SHOWN and a choice's
// `gets:` when it is PICKED, both straight through `trigger.Runtime.apply` — an action means the same thing
// whether a trigger or an answer fired it, and two copies of that switch would eventually disagree.
//
// **A GATE HIDES A LINE, IT DOES NOT GREY IT.** bg2's editor carries a `disabledMessage` for a refused
// choice; nothing here has one to show, and a greyed row with no reason is worse than a row that was never
// offered. When there is a reason to give, that is the day the gate grows a message.
//
// **YOU MAY NOT WALK OUT MID-SENTENCE.** There is no cancel: a conversation is left through one of its own
// endings, which is what lets `talked` mean "has heard this" rather than "has seen the first line of it".

/// How long the panel takes to come up…
const RAISE: f32 = 0.14;
/// …and how far it slides through on the way, in px.
const RAISE_LIFT: f32 = 40.0;
/// The plate's own opacity at full raise.
const PLATE_A: f32 = 235.0;

const SIDE_MARGIN: i32 = 54;
const BOTTOM_MARGIN: i32 = 44;
const PAD: i32 = 22;
/// Gap above and below a rule.
const RULE_GAP: i32 = 10;
const ROW_GAP: i32 = 8;
const MAX_LINES: usize = 7;
/// The panel never grows past this share of the screen, however long a node's prose runs — past it the words
/// have taken the world with them.
const MAX_FRAC: f32 = 0.62;
const WRAP_BUF: usize = 640;
const LABEL_CAP: usize = 128;

const TEXT = rgba(224, 214, 190, 246);
const TEXT_OFF = rgba(150, 142, 124, 230);
const NAME = uiart.GILT;
/// How black the world goes behind the panel. Dimmed, never hidden: you are still standing somewhere.
const VEIL: u8 = 132;

// THE PORTRAIT — the man you are talking to, photographed live.
//
// **IT IS THE ACTUAL 3D MODEL, ZOOMED TO THE HEAD, THREE-QUARTERS ON** (owner). Not drawn art: the rig is
// rendered off-screen into a target and blitted into the panel, which is `book.drawPortrait`'s trick one rig
// along and for its reason — it is the real model in the real pose, so it cannot go stale, and the head that
// cranes round to look at you cranes round in the panel.
//
// **THE TURNTABLE HANGS OFF HIS FACING, NEVER THE WORLD.** He is photographed three-quarters from the front
// wherever he happens to be standing, so the framing does not change because the conversation happened to
// start on the other side of a rock.
/// **SMALLER THAN A THIRD OF THE PLATE** (owner: the portraits are too big). At 320 the head was competing
/// with the prose it is supposed to be attributing — a portrait names the speaker, it is not the subject of
/// the panel.
const PORT_W: i32 = 176;
const PORT_H: i32 = 200;
/// Degrees off his own front. Three-quarters: enough to give the head a near side and a far side — a dead-on
/// face is a passport photo and reads flat on a low-poly head with no shading break in it.
/// …and none of the four is authored here, because the shot that proves this picture has to frame it the
/// same way or it is signing off a picture nobody sees. The ANGLE is the house's, the DISTANCE the speaker's.
const PORT_YAW = hud.PORTRAIT_YAW;
const PORT_PITCH = hud.PORTRAIT_PITCH;
const PORT_DIST = npcmod.PORTRAIT_DIST;
const PORT_FOV = hud.PORTRAIT_FOV;
/// The plate is sized to what it holds, and from here that includes the picture.
const PORT_GAP: i32 = 16;
/// …and the fewest pixels of PROSE worth wrapping into. Under this the portrait is dropped instead: the
/// words are the panel and the picture is an attribution on them.
const PROSE_MIN_W: i32 = 240;

/// WHAT THE PANEL NEEDS TO TAKE THE PICTURE, handed in by the game rather than reached for: the scene it
/// draws through, where the face is, which way he is pointing, and how to draw him. `who` is an index into
/// the folk, and `drawFn` is passed so this file never has to import the creature.
pub const Portrait = struct {
    scene: *gfx.Scene,
    face: rl.Vector3,
    facing: f32,
    ctx: *const anyopaque,
    drawFn: *const fn (*const anyopaque) void,
};

pub const Input = struct {
    up: bool = false,
    down: bool = false,
    confirm: bool = false,
    /// A number key, 1-based, or null.
    pick: ?usize = null,
};

pub const Session = struct {
    dlg: u16 = wf.NO_DIALOG,
    node: u16 = wf.NO_NODE,
    cursor: usize = 0,
    t: f32 = 0,
    /// Which of the map's folk is speaking, when a prompt rather than a trigger opened this.
    npc: ?usize = null,
    /// Who the panel names when a node does not say (`who:`).
    speaker: [wf.ID_CAP * 2]u8 = undefined,
    speakerLen: usize = 0,
    /// An EDGE, true for exactly the frame the conversation ends on (`rest.justLeft`'s pattern).
    justClosed: bool = false,
    /// …and WHICH conversation closed, since `dlg` is already back to nothing by then.
    closed: u16 = wf.NO_DIALOG,

    pub fn active(self: *const Session) bool {
        return self.dlg != wf.NO_DIALOG;
    }

    /// How far up the panel is, 0..1.
    pub fn raise(self: *const Session) f32 {
        return mathx.smoothstep(0, RAISE, self.t);
    }

    pub fn speakerName(self: *const Session) []const u8 {
        return self.speaker[0..self.speakerLen];
    }

    fn setSpeaker(self: *Session, s: []const u8) void {
        self.speakerLen = @min(s.len, self.speaker.len);
        @memcpy(self.speaker[0..self.speakerLen], s[0..self.speakerLen]);
    }

    /// OPEN one, at its first node. Refuses a dialog that is not there or has no nodes, so a bad map record
    /// costs a silent no-op rather than a panel with nothing in it.
    pub fn open(self: *Session, m: *const wf.Map, rt: *trigger.Runtime, dlg: u16, who: []const u8, npc: ?usize) bool {
        const d = m.dialogAt(dlg) orelse return false;
        if (d.nnodes == 0) return false;
        self.* = .{ .dlg = dlg, .node = d.node0, .npc = npc };
        self.setSpeaker(who);
        self.enter(m, rt);
        return true;
    }

    /// The node's own actions fire on ARRIVAL, so a line that opens a gate has opened it by the time the
    /// player reads it.
    fn enter(self: *Session, m: *const wf.Map, rt: *trigger.Runtime) void {
        self.cursor = 0;
        const nd = self.nodeOf(m) orelse return;
        rt.applyAll(m, m.dactRun(nd.act0, nd.nact));
    }

    pub fn nodeOf(self: *const Session, m: *const wf.Map) ?*const wf.Node {
        if (self.node >= m.nnodes) return null;
        return &m.nodes[self.node];
    }

    /// The lines actually on offer, gates applied — written into `out` as indices into the node's choices.
    pub fn offered(self: *const Session, m: *const wf.Map, rt: *const trigger.Runtime, w: trigger.World, out: []usize) []usize {
        const nd = self.nodeOf(m) orelse return out[0..0];
        var n: usize = 0;
        for (nd.choiceSlice(), 0..) |*c, i| {
            if (n >= out.len) break;
            if (c.gate >= 0 and !rt.holds(&m.gates[@intCast(c.gate)], w)) continue;
            out[n] = i;
            n += 1;
        }
        return out[0..n];
    }

    pub fn update(self: *Session, m: *const wf.Map, rt: *trigger.Runtime, w: trigger.World, dt: f32, in: Input) void {
        self.justClosed = false;
        if (!self.active()) return;
        self.t += dt;

        var buf: [wf.MAX_CHOICES]usize = undefined;
        const shown = self.offered(m, rt, w, &buf);
        if (shown.len > 0) {
            self.cursor = @min(self.cursor, shown.len - 1);
            if (in.up and self.cursor > 0) {
                self.cursor -= 1;
                sfx.play(.menu_move);
            }
            if (in.down and self.cursor + 1 < shown.len) {
                self.cursor += 1;
                sfx.play(.menu_move);
            }
            // A number key jumps AND picks, the way BG2's own list does.
            var take: ?usize = null;
            if (in.pick) |p| {
                if (p >= 1 and p <= shown.len) take = p - 1;
            }
            if (in.confirm) take = self.cursor;
            if (take) |k| {
                const nd = self.nodeOf(m).?;
                const c = &nd.choices[shown[k]];
                sfx.play(.menu_pick);
                rt.applyAll(m, m.dactRun(c.act0, c.nact));
                self.go(m, rt, c.next);
            }
            return;
        }
        // No lines to answer with: Continue, and where `then:` said.
        if (in.confirm or in.pick != null) {
            const nd = self.nodeOf(m) orelse return self.close(rt);
            sfx.play(.menu_pick);
            self.go(m, rt, nd.next);
        }
    }

    fn go(self: *Session, m: *const wf.Map, rt: *trigger.Runtime, next: u16) void {
        if (next == wf.NO_NODE or next >= m.nnodes) return self.close(rt);
        self.node = next;
        // The panel is already up, so the reveal does not replay between nodes.
        self.enter(m, rt);
    }

    fn close(self: *Session, rt: *trigger.Runtime) void {
        const was = self.dlg;
        // WHO WAS SPEAKING SURVIVES THE EDGE. The whole point of `justClosed` is that the caller acts on it —
        // it is what fires the wanderer's parting nod — and a wipe that took `npc` with it left that read as
        // `null` on the one frame anybody looks.
        const who = self.npc;
        rt.finished(was);
        rt.dialogClosed();
        self.* = .{ .justClosed = true, .closed = was, .npc = who };
        sfx.play(.menu_back);
    }

    /// THE PANEL. Drawn after the retro blit like the rest of the HUD, so these colours are literal screen
    /// values and the author-dark rule does not apply.
    ///
    /// **IT IS SIZED TO WHAT IT HOLDS, and it grows UPWARD off a fixed bottom edge.** A panel pinned to a
    /// fraction of the screen is half empty on a two-line exchange and cramped on a long one.
    pub fn draw(self: *const Session, m: *const wf.Map, rt: *const trigger.Runtime, w: trigger.World, port: ?Portrait) void {
        if (!self.active()) return;
        const nd = self.nodeOf(m) orelse return;
        const k = self.raise();
        const sw = rl.getScreenWidth();
        const sh = rl.getScreenHeight();
        rl.drawRectangle(0, 0, sw, sh, rgba(0, 0, 0, @intFromFloat(@as(f32, VEIL) * k)));

        const x = SIDE_MARGIN;
        const wpx = sw - SIDE_MARGIN * 2;
        // THE PICTURE TAKES ITS COLUMN OUT OF THE PROSE'S, never off the end of the plate: the wrap below is
        // measured against what is LEFT, so a portrait can never push a line out past the frame.
        //
        // …AND IT IS DROPPED ENTIRELY RATHER THAN STARVING THE WORDS. On a window too narrow to hold both,
        // the portrait is the half that goes: it says who is speaking, and the panel already says that in
        // text. Without this the wrap is handed a negative width and the plate a negative-sided rectangle.
        const room = wpx - PAD * 2 - (PORT_W + PORT_GAP) >= PROSE_MIN_W;
        const showPort = port != null and room;
        const portCol: i32 = if (showPort) PORT_W + PORT_GAP else 0;
        const innerX = x + PAD + portCol;
        const innerW = wpx - PAD * 2 - portCol;
        const bodyH = hud.lineH(hud.BODY);
        const rowStep = bodyH + ROW_GAP;

        var nameBuf: [LABEL_CAP]u8 = undefined;
        const who = if (nd.who.len > 0) m.spanText(nd.who) else self.speakerName();
        var wrapBuf: [WRAP_BUF]u8 = undefined;
        var rows: [MAX_LINES][:0]const u8 = undefined;
        const lines = hud.wrap(m.spanText(nd.text), hud.BODY, innerW, &wrapBuf, &rows);
        var buf: [wf.MAX_CHOICES]usize = undefined;
        const shown = self.offered(m, rt, w, &buf);

        // THE MEASURE, in the same order the draw walks it — one pass ahead of the other, so a row added below
        // cannot silently overflow a box laid out for the row count before it.
        var need: i32 = PAD * 2;
        if (who.len > 0) need += bodyH + RULE_GAP * 2;
        need += @as(i32, @intCast(lines.len)) * bodyH;
        if (shown.len > 0) need += RULE_GAP * 2 + @as(i32, @intCast(shown.len)) * rowStep;
        need += RULE_GAP + hud.lineH(hud.HINT);
        // …and the picture is content too: a two-line exchange must still leave a plate tall enough to hold
        // a face, or the portrait spills out of the frame it is supposed to be mounted in.
        if (showPort) need = @max(need, PAD * 2 + PORT_H);

        const capH = @as(i32, @intFromFloat(@as(f32, @floatFromInt(sh)) * MAX_FRAC));
        const hpx = @min(need, capH);
        // It RISES: the panel slides up into place rather than appearing, which is what says a conversation
        // began rather than the frame changing.
        const lift = @as(i32, @intFromFloat((1.0 - k) * RAISE_LIFT));
        const y = sh - BOTTOM_MARGIN - hpx + lift;
        const a: u8 = @intFromFloat(PLATE_A * k);
        uiart.plate(x, y, wpx, hpx, a);
        uiart.frame(x, y, wpx, hpx, a);
        if (showPort) {
            // Fitted to whatever the plate ended up being, and KEEPING ITS ASPECT: `MAX_FRAC` may have
            // refused the height `need` asked for, and a picture squashed to fill the hole is a different
            // face. It shrinks in both axes and centres in the column instead.
            const ph = @min(PORT_H, @max(0, hpx - PAD * 2));
            const pw = @divTrunc(PORT_W * ph, PORT_H);
            if (ph > 0) drawPortrait(port.?, x + PAD + @divTrunc(PORT_W - pw, 2), y + PAD, pw, ph);
        }

        var cy = y + PAD;
        const midX = x + @divTrunc(wpx, 2);
        const halfW = @divTrunc(innerW, 2);

        // WHO IS TALKING — the node's own `who:` first, then whoever the prompt named.
        if (who.len > 0) {
            hud.engraved(zterm(&nameBuf, who), innerX, cy, hud.BODY, NAME);
            cy += bodyH + RULE_GAP;
            uiart.divider(midX, cy, halfW, a);
            cy += RULE_GAP;
        }

        // THE FOOTER IS THE FLOOR EVERYTHING INSIDE THE PLATE IS MEASURED AGAINST — the prose as much as the
        // rows. `need` asked for the height it wanted and `MAX_FRAC` may have refused it on a short window, and
        // a line that will not fit is not drawn OUTSIDE the plate.
        const footer = y + hpx - PAD - hud.lineH(hud.HINT);
        for (lines) |ln| {
            if (cy + bodyH > footer) break;
            hud.text(ln, innerX, cy, hud.BODY, TEXT);
            cy += bodyH;
        }

        if (shown.len > 0) {
            cy += RULE_GAP;
            uiart.divider(midX, cy, halfW, a);
            cy += RULE_GAP;
            for (shown, 0..) |ci, row| {
                // The measure above wanted `need`, and `MAX_FRAC` may have refused it on a short window. A row
                // that will not fit inside the plate is not drawn OUTSIDE it.
                if (cy + rowStep > footer) break;
                const c = &nd.choices[ci];
                const on = row == self.cursor;
                if (on) uiart.rowHilite(innerX - 8, cy - 4, innerW + 16, rowStep - 2);
                var lb: [LABEL_CAP]u8 = undefined;
                var out: [LABEL_CAP]u8 = undefined;
                const label = m.spanText(c.label);
                const numbered = std.fmt.bufPrint(&out, "{d}. {s}", .{ row + 1, label }) catch label;
                // The bar `rowHilite` lays down IS the cursor here as it is in every menu (`uiart.caret`);
                // this row used to carry a gilt diamond on top of it, which is one cursor drawn twice.
                hud.text(zterm(&lb, numbered), innerX + (if (on) @as(i32, 10) else 0), cy, hud.BODY, if (on) uiart.HOT else TEXT_OFF);
                cy += rowStep;
            }
        }
        // THE FOOTER NAMES THE BUTTONS AND NOTHING ELSE — the same interact glyph the world's own prompt
        // showed to open this conversation, so the button that got you in is the button that walks you out.
        var hints: [2]hud.Hint = undefined;
        var n: usize = 0;
        if (shown.len > 0) {
            hints[n] = .{ .glyph = .{ .dpad = .updown }, .label = "Choose" };
            n += 1;
        }
        hints[n] = .{ .glyph = .{ .face = hud.BTN_INTERACT }, .label = if (shown.len > 0) "Speak" else "Continue" };
        n += 1;
        hud.hintRowAt(hints[0..n], innerX, footer + @divTrunc(hud.lineH(hud.HINT), 2), hud.HINT, uiart.TEXT_HINT);
    }
};

/// TAKE THE PICTURE AND MOUNT IT. The render target is lazy and lives as long as the process (`book`'s
/// `portRT`), because a conversation opens and closes constantly and reallocating a target per panel is a
/// stall you can feel.
fn drawPortrait(p: Portrait, dx: i32, dy: i32, dw: i32, dh: i32) void {
    const dst = rl.Rectangle{
        .x = @floatFromInt(dx),
        .y = @floatFromInt(dy),
        .width = @floatFromInt(dw),
        .height = @floatFromInt(dh),
    };
    // THE CAMERA AND THE TARGET ARE `hud.livePortrait`'s — three callers photograph a body now (the book's
    // doll, this, the spirit toast) and three copies of one camera is three things to retune apart.
    // THREE-QUARTERS OFF HIS OWN FRONT: the camera sits out along his facing and looks back, so this is his
    // face however the world happens to be oriented.
    hud.livePortrait(.{
        .scene = p.scene,
        .focus = p.face,
        .yaw = p.facing + mathx.radians(PORT_YAW),
        .pitch = PORT_PITCH,
        .dist = PORT_DIST,
        .fov = PORT_FOV,
        .ctx = p.ctx,
        .drawFn = p.drawFn,
    }, dst, rl.Color.white);
    // Dusk at the edges so he sits IN the plate rather than on top of it, and a gilt rebate to mount it.
    const band = @divTrunc(dh, 5);
    rl.drawRectangleGradientV(dx, dy, dw, band, rgba(0, 0, 0, 175), rgba(0, 0, 0, 0));
    rl.drawRectangleGradientV(dx, dy + dh - band, dw, band, rgba(0, 0, 0, 0), rgba(0, 0, 0, 195));
    const side = @divTrunc(dw, 6);
    rl.drawRectangleGradientH(dx, dy, side, dh, rgba(0, 0, 0, 160), rgba(0, 0, 0, 0));
    rl.drawRectangleGradientH(dx + dw - side, dy, side, dh, rgba(0, 0, 0, 0), rgba(0, 0, 0, 160));
    rl.drawRectangleLinesEx(dst, 1, mathx.withAlpha(uiart.GILT_DIM, 95));
}

/// A NUL-terminated copy, because `hud.text` takes a sentinel slice and the arena's prose has none.
fn zterm(buf: []u8, s: []const u8) [:0]const u8 {
    const n = @min(s.len, buf.len - 1);
    @memcpy(buf[0..n], s[0..n]);
    buf[n] = 0;
    return buf[0..n :0];
}


const testMap = wf.testMap;
const HEAD = wf.TEST_HEAD;

const TREE = HEAD ++
    \\dlg: hunter
    \\  node: root
    \\  who: The Hunter
    \\  say: You have the look of one who walks a long road alone.
    \\  ask: The way north? -> north
    \\  ask: Through the gate. -> gate
    \\  need: flag gate_open=1
    \\  ask: Nothing. -> end
    \\  node: north
    \\  say: North the great gate stands shut.
    \\  act: flag told=1
    \\  then: root
    \\  node: gate
    \\  say: Then go, and do not look back.
    \\  then: end
;

fn pick(s: *Session, m: *const wf.Map, rt: *trigger.Runtime, row: usize) void {
    s.update(m, rt, .{}, 1.0 / 60.0, .{ .pick = row });
}

test "a conversation walks its nodes and a then: brings it back" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, TREE);
    defer alloc.destroy(m);
    var rt = trigger.Runtime{};
    rt.arm(m);
    var s = Session{};
    try std.testing.expect(s.open(m, &rt, 0, "Someone", null));
    try std.testing.expect(s.active());
    try std.testing.expectEqualStrings("root", wf.idText(&s.nodeOf(m).?.id));

    pick(&s, m, &rt, 1); // "The way north?"
    try std.testing.expectEqualStrings("north", wf.idText(&s.nodeOf(m).?.id));
    try std.testing.expect(rt.flags[m.findFlag("told").?]); // the node's act fired on arrival
    s.update(m, &rt, .{}, 1.0 / 60.0, .{ .confirm = true }); // Continue
    try std.testing.expectEqualStrings("root", wf.idText(&s.nodeOf(m).?.id));
}

test "a gated line is not offered until its flag is up, and numbering follows what is shown" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, TREE);
    defer alloc.destroy(m);
    var rt = trigger.Runtime{};
    rt.arm(m);
    var s = Session{};
    _ = s.open(m, &rt, 0, "Someone", null);

    var buf: [wf.MAX_CHOICES]usize = undefined;
    try std.testing.expectEqual(@as(usize, 2), s.offered(m, &rt, .{}, &buf).len);
    // …so line 2 is "Nothing." while the gate is shut, and picking it ENDS the conversation.
    pick(&s, m, &rt, 2);
    try std.testing.expect(!s.active());
    try std.testing.expect(rt.talked[0]);

    rt.flags[m.findFlag("gate_open").?] = true;
    _ = s.open(m, &rt, 0, "Someone", null);
    const shown = s.offered(m, &rt, .{}, &buf);
    try std.testing.expectEqual(@as(usize, 3), shown.len);
    try std.testing.expectEqual(@as(usize, 1), shown[1]); // the gated one is back in the middle
}

test "the cursor cannot leave the offered lines" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, TREE);
    defer alloc.destroy(m);
    var rt = trigger.Runtime{};
    rt.arm(m);
    var s = Session{};
    _ = s.open(m, &rt, 0, "Someone", null);
    var i: usize = 0;
    while (i < 8) : (i += 1) s.update(m, &rt, .{}, 1.0 / 60.0, .{ .up = true });
    try std.testing.expectEqual(@as(usize, 0), s.cursor);
    i = 0;
    while (i < 8) : (i += 1) s.update(m, &rt, .{}, 1.0 / 60.0, .{ .down = true });
    try std.testing.expectEqual(@as(usize, 1), s.cursor); // two lines offered, so the last is 1
}

test "closing is a one-frame edge that names what closed AND who was speaking" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, TREE);
    defer alloc.destroy(m);
    var rt = trigger.Runtime{};
    rt.arm(m);
    var s = Session{};
    _ = s.open(m, &rt, 0, "Someone", 3);
    pick(&s, m, &rt, 2);
    try std.testing.expect(s.justClosed);
    try std.testing.expectEqual(@as(u16, 0), s.closed);
    // …and WHICH of the folk it was, or the parting gesture has nobody to play on.
    try std.testing.expectEqual(@as(?usize, 3), s.npc);
    s.update(m, &rt, .{}, 1.0 / 60.0, .{});
    try std.testing.expect(!s.justClosed);
}

test "a hidden gate cannot be reached by its own number" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, TREE);
    defer alloc.destroy(m);
    var rt = trigger.Runtime{};
    rt.arm(m);
    var s = Session{};
    _ = s.open(m, &rt, 0, "Someone", null);
    // Three lines are authored and two are offered, so a 3 must do nothing at all.
    pick(&s, m, &rt, 3);
    try std.testing.expect(s.active());
    try std.testing.expectEqualStrings("root", wf.idText(&s.nodeOf(m).?.id));
}

test "an empty or missing dialog is refused rather than opened blank" {
    const alloc = std.testing.allocator;
    const m = try testMap(alloc, TREE);
    defer alloc.destroy(m);
    var rt = trigger.Runtime{};
    rt.arm(m);
    var s = Session{};
    try std.testing.expect(!s.open(m, &rt, wf.NO_DIALOG, "x", null));
    try std.testing.expect(!s.open(m, &rt, 9, "x", null));
    try std.testing.expect(!s.active());
}
