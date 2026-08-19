const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const wf = @import("worldfmt.zig");
const trigger = @import("trigger.zig");
const gfx = @import("../gfx/gfx.zig");
const npcmod = @import("../foes/npc.zig");
const hud = @import("../ui/hud.zig");
const uiart = @import("../ui/uiart.zig");
const sfx = @import("../core/audio.zig");

const rgba = mathx.rgba;
const v3 = mathx.v3;


const RAISE: f32 = 0.14;
const RAISE_LIFT: f32 = 40.0;
const PLATE_A: f32 = 235.0;

const SIDE_MARGIN: i32 = 54;
const BOTTOM_MARGIN: i32 = 44;
const PAD: i32 = 22;
const RULE_GAP: i32 = 10;
const ROW_GAP: i32 = 8;
const MAX_LINES: usize = 7;
const MAX_FRAC: f32 = 0.62;
const WRAP_BUF: usize = 640;
const LABEL_CAP: usize = 128;

const TEXT = rgba(224, 214, 190, 246);
const TEXT_OFF = rgba(150, 142, 124, 230);
const NAME = uiart.GILT;
const VEIL: u8 = 132;

const PORT_W: i32 = 176;
const PORT_H: i32 = 200;
const PORT_YAW = hud.PORTRAIT_YAW;
const PORT_PITCH = hud.PORTRAIT_PITCH;
const PORT_DIST = npcmod.PORTRAIT_DIST;
const PORT_FOV = hud.PORTRAIT_FOV;
const PORT_GAP: i32 = 16;
const PROSE_MIN_W: i32 = 240;

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
    pick: ?usize = null,
};

pub const Session = struct {
    dlg: u16 = wf.NO_DIALOG,
    node: u16 = wf.NO_NODE,
    cursor: usize = 0,
    t: f32 = 0,
    npc: ?usize = null,
    speaker: [wf.ID_CAP * 2]u8 = undefined,
    speakerLen: usize = 0,
    justClosed: bool = false,
    closed: u16 = wf.NO_DIALOG,

    pub fn active(self: *const Session) bool {
        return self.dlg != wf.NO_DIALOG;
    }

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

    pub fn open(self: *Session, m: *const wf.Map, rt: *trigger.Runtime, dlg: u16, who: []const u8, npc: ?usize) bool {
        const d = m.dialogAt(dlg) orelse return false;
        if (d.nnodes == 0) return false;
        self.* = .{ .dlg = dlg, .node = d.node0, .npc = npc };
        self.setSpeaker(who);
        self.enter(m, rt);
        return true;
    }

    fn enter(self: *Session, m: *const wf.Map, rt: *trigger.Runtime) void {
        self.cursor = 0;
        const nd = self.nodeOf(m) orelse return;
        rt.applyAll(m, m.dactRun(nd.act0, nd.nact));
    }

    pub fn nodeOf(self: *const Session, m: *const wf.Map) ?*const wf.Node {
        if (self.node >= m.nnodes) return null;
        return &m.nodes[self.node];
    }

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
        if (in.confirm or in.pick != null) {
            const nd = self.nodeOf(m) orelse return self.close(rt);
            sfx.play(.menu_pick);
            self.go(m, rt, nd.next);
        }
    }

    fn go(self: *Session, m: *const wf.Map, rt: *trigger.Runtime, next: u16) void {
        if (next == wf.NO_NODE or next >= m.nnodes) return self.close(rt);
        self.node = next;
        self.enter(m, rt);
    }

    fn close(self: *Session, rt: *trigger.Runtime) void {
        const was = self.dlg;
        const who = self.npc;
        rt.finished(was);
        rt.dialogClosed();
        self.* = .{ .justClosed = true, .closed = was, .npc = who };
        sfx.play(.menu_back);
    }

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
        if (showPort) need = @max(need, PAD * 2 + PORT_H);

        const capH = @as(i32, @intFromFloat(@as(f32, @floatFromInt(sh)) * MAX_FRAC));
        const hpx = @min(need, capH);
        const lift = @as(i32, @intFromFloat((1.0 - k) * RAISE_LIFT));
        const y = sh - BOTTOM_MARGIN - hpx + lift;
        const a: u8 = @intFromFloat(PLATE_A * k);
        uiart.plate(x, y, wpx, hpx, a);
        uiart.frame(x, y, wpx, hpx, a);
        if (showPort) {
            const ph = @min(PORT_H, @max(0, hpx - PAD * 2));
            const pw = @divTrunc(PORT_W * ph, PORT_H);
            if (ph > 0) drawPortrait(port.?, x + PAD + @divTrunc(PORT_W - pw, 2), y + PAD, pw, ph);
        }

        var cy = y + PAD;
        const midX = x + @divTrunc(wpx, 2);
        const halfW = @divTrunc(innerW, 2);

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
                if (cy + rowStep > footer) break;
                const c = &nd.choices[ci];
                const on = row == self.cursor;
                if (on) uiart.rowHilite(innerX - 8, cy - 4, innerW + 16, rowStep - 2);
                var lb: [LABEL_CAP]u8 = undefined;
                var out: [LABEL_CAP]u8 = undefined;
                const label = m.spanText(c.label);
                const numbered = std.fmt.bufPrint(&out, "{d}. {s}", .{ row + 1, label }) catch label;
                hud.text(zterm(&lb, numbered), innerX + (if (on) @as(i32, 10) else 0), cy, hud.BODY, if (on) uiart.HOT else TEXT_OFF);
                cy += rowStep;
            }
        }
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

fn drawPortrait(p: Portrait, dx: i32, dy: i32, dw: i32, dh: i32) void {
    const dst = rl.Rectangle{
        .x = @floatFromInt(dx),
        .y = @floatFromInt(dy),
        .width = @floatFromInt(dw),
        .height = @floatFromInt(dh),
    };
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
    const band = @divTrunc(dh, 5);
    rl.drawRectangleGradientV(dx, dy, dw, band, rgba(0, 0, 0, 175), rgba(0, 0, 0, 0));
    rl.drawRectangleGradientV(dx, dy + dh - band, dw, band, rgba(0, 0, 0, 0), rgba(0, 0, 0, 195));
    const side = @divTrunc(dw, 6);
    rl.drawRectangleGradientH(dx, dy, side, dh, rgba(0, 0, 0, 160), rgba(0, 0, 0, 0));
    rl.drawRectangleGradientH(dx + dw - side, dy, side, dh, rgba(0, 0, 0, 0), rgba(0, 0, 0, 160));
    rl.drawRectangleLinesEx(dst, 1, mathx.withAlpha(uiart.GILT_DIM, 95));
}

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

    pick(&s, m, &rt, 1);
    try std.testing.expectEqualStrings("north", wf.idText(&s.nodeOf(m).?.id));
    try std.testing.expect(rt.flags[m.findFlag("told").?]);
    s.update(m, &rt, .{}, 1.0 / 60.0, .{ .confirm = true });
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
    pick(&s, m, &rt, 2);
    try std.testing.expect(!s.active());
    try std.testing.expect(rt.talked[0]);

    rt.flags[m.findFlag("gate_open").?] = true;
    _ = s.open(m, &rt, 0, "Someone", null);
    const shown = s.offered(m, &rt, .{}, &buf);
    try std.testing.expectEqual(@as(usize, 3), shown.len);
    try std.testing.expectEqual(@as(usize, 1), shown[1]);
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
    try std.testing.expectEqual(@as(usize, 1), s.cursor);
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
