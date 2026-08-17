const std = @import("std");
const rl = @import("raylib");

const chestmod = @import("chest.zig");
const pickupmod = @import("pickup.zig");
const awardmod = @import("award.zig");
const combat = @import("combat.zig");
const daynight = @import("daynight.zig");
const heromod = @import("hero.zig");
const item = @import("item.zig");
const mathx = @import("mathx.zig");
const ptree = @import("passivetree.zig");
const soulsmod = @import("souls.zig");
const trigmod = @import("trigger.zig");
const wf = @import("worldfmt.zig");

pub const VERSION: u32 = 1;

/// **THREE SLOTS, AND A FIRE WRITES OVER THE ONE YOU ARE PLAYING** (ER's own). There is no Save row anywhere:
/// which slot a bonfire lands in is decided once, when the character is started, and never asked again.
pub const SLOTS: usize = 3;

/// Both files a slot owns — the save, and the picture the picker shows it by. Written out rather than built
/// from an index at runtime: no formatting buffer to size, and no path that can come back empty.
const PATHS = [SLOTS][:0]const u8{ "save1.dat", "save2.dat", "save3.dat" };
const SHOTS = [SLOTS][:0]const u8{ "save1.png", "save2.png", "save3.png" };

pub fn path(i: usize) [:0]const u8 {
    return PATHS[i];
}
pub fn shotPath(i: usize) [:0]const u8 {
    return SHOTS[i];
}

/// A versioned text file in the map's own grammar (`key: value`), for the map's own reason: a save you can
/// read is a save you can see what is wrong with. A WRONG MAP is not in here — `readFrom` and `peek` answer
/// that in `bool`, because it is a fact about the SLOT rather than about the file being malformed.
pub const Error = error{ BadVersion, BadKey, BadField };

/// THE STATE THE GAME OWNS, gathered into one place so a load can be an ALL-OR-NOTHING swap. Parsing
/// straight into the live game leaves a half-read file as a half-built character — the same hazard
/// `audio.loadSettings` refuses a truncated rack for, one layer up.
pub const Slot = struct {
    hero: *heromod.Hero,
    bag: *item.Bag,
    tree: *ptree.Tree,
    souls: *soulsmod.Souls,
    day: *daynight.Clock,
    trig: *trigmod.Runtime,
    chests: *chestmod.Chests,
    pickups: *pickupmod.Pickups,
    /// **THE DISCOVERY SET LIVES IN THE FILE**, or every reload turns the game back into a slideshow of items
    /// it has already shown you. The pending cards and toasts deliberately do NOT: those are a moment, not a
    /// character (`award.clearPending`).
    award: *awardmod.Award,
    /// Which world this belongs to. A file naming another map is refused, not replayed against whatever
    /// happens to be loaded — the trigger indices, the chest indices and `near npc=` are all that map's.
    map: []const u8,
};

const MAP_CAP = 96;
comptime {
    // The one map anything is ever saved against. A longer one is a compile error rather than a save nobody
    // can load, which is what a silent clip in `gather` would have made it.
    if (wf.START_MAP.len > MAP_CAP) @compileError("save: MAP_CAP is shorter than the map path it has to hold");
}

/// **THE BARS ARE NOT IN HERE, AND THAT IS THE POINT.** The one place a save is taken is a bonfire, and
/// sitting down at one runs `hero.makeWhole` — HP, stamina, focus, both flasks, both quivers, poison, ward
/// and grease, all settled before the file is written. Storing them would be storing a constant, and a
/// constant stored beside the thing that derives it is two numbers that can disagree. The SHEET is out for
/// the same reason one layer along: it is `ptree.Bonus.sheet()` of the tree below, and `game.applyTree` is
/// what re-derives it on the way back in.
pub const Data = struct {
    map: [MAP_CAP]u8 = [_]u8{0} ** MAP_CAP,
    mapLen: usize = 0,

    at: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,
    spawnAt: rl.Vector3 = mathx.zero3,
    spawnFacing: f32 = 0,
    souls: u32 = 0,

    arm: heromod.Armament = .sword,
    off: heromod.Armament = .shield,
    /// …and the OTHER slot of each hand. A save that carried only the live one came back with a default
    /// alternate, so half of every loadout was silently reset at the fire it was written from.
    armAlt: heromod.Armament = .bow,
    offAlt: heromod.Armament = .wand,
    spell: combat.Spell = .bolt,
    arrow: combat.ArrowKind = .plain,
    flask: combat.FlaskKind = .crimson,
    quick: [combat.QUICK_SLOTS]?item.Kind = [_]?item.Kind{null} ** combat.QUICK_SLOTS,
    quickSel: usize = 0,

    bag: [item.NK]u16 = [_]u16{0} ** item.NK,
    tree: [ptree.N]bool = [_]bool{false} ** ptree.N,

    /// WHAT HE LEFT ON THE GROUND. `amount` 0 is a bare floor, which is `souls.spill`'s own reading of it.
    dropAt: rl.Vector3 = mathx.zero3,
    dropAmount: u32 = 0,

    hour: f32 = 0,

    flags: [wf.MAX_FLAGS]bool = [_]bool{false} ** wf.MAX_FLAGS,
    counters: [wf.MAX_COUNTERS]i32 = [_]i32{0} ** wf.MAX_COUNTERS,
    timers: [wf.MAX_TIMERS]f32 = [_]f32{0} ** wf.MAX_TIMERS,
    armed: [wf.MAX_TIMERS]bool = [_]bool{false} ** wf.MAX_TIMERS,
    talked: [wf.MAX_DIALOGS]bool = [_]bool{false} ** wf.MAX_DIALOGS,
    fired: [wf.MAX_TRIGGERS]bool = [_]bool{false} ** wf.MAX_TRIGGERS,
    preserved: [wf.MAX_TRIGGERS]bool = [_]bool{false} ** wf.MAX_TRIGGERS,
    /// A TRIGGER MID-EXECUTION — where its action cursor sits and what is left of its `wait`. `inDialog` is
    /// deliberately absent: neither menu opens at a fire, so no save can be taken with a conversation up.
    running: [wf.MAX_TRIGGERS]bool = [_]bool{false} ** wf.MAX_TRIGGERS,
    actAt: [wf.MAX_TRIGGERS]u8 = [_]u8{0} ** wf.MAX_TRIGGERS,
    waitLeft: [wf.MAX_TRIGGERS]f32 = [_]f32{0} ** wf.MAX_TRIGGERS,
    deaths: [NFOE]u32 = [_]u32{0} ** NFOE,
    elapsed: f32 = 0,

    chestOpen: [chestmod.CAP]bool = [_]bool{false} ** chestmod.CAP,
    pickupTaken: [pickupmod.CAP]bool = [_]bool{false} ** pickupmod.CAP,
    /// **AND WHAT HE HAS EVER SEEN** — one bit per item kind, through the same `bits` run the chests use, so it
    /// is legible in a save you can read; a MISSING row leaves it all false, which is what an older save
    /// honestly is (it will card each kind once more, and then never again).
    ///
    /// **IT IS POSITIONAL, WHICH MAKES `item.Kind`'S ORDER PART OF THE SAVE FORMAT.** `bits` writes one
    /// character per kind in enum order and `readBits` reads them straight back by index — no tag names
    /// anywhere. So a kind INSERTED or MOVED in that enum silently re-points every discovery bit in every
    /// existing file: the player is re-introduced to things he has carried for hours and never shown the one
    /// thing he has not. `item.Kind` is append-only for this reason and a test in `item.zig` pins its order.
    /// (This comment said "written by TAG" and claimed a reordered enum could not re-point it. Neither was
    /// ever true, and a false safety note is worse than none — it is the reason nobody added the guard.)
    seen: [item.NK]bool = [_]bool{false} ** item.NK,

    pub fn mapName(self: *const Data) []const u8 {
        return self.map[0..self.mapLen];
    }
};

const NFOE = @typeInfo(wf.FoeKind).@"enum".fields.len;

/// SIZED OFF THE TABLES, never a round number that looked big enough (the ring-buffer rule). Every run is
/// its element count times the widest thing one element prints as, plus its key.
const CAP: usize =
    64 + MAP_CAP + // version, map
    4 * 48 + // at, spawn, drop, hour
    5 * 32 + // souls, hands, sels, quickSel, elapsed
    combat.QUICK_SLOTS * 28 + 16 +
    item.NK * 36 + 8 +
    ptree.N + 8 +
    wf.MAX_FLAGS + 8 +
    wf.MAX_COUNTERS * 13 + 12 +
    wf.MAX_TIMERS * 12 + wf.MAX_TIMERS + 24 +
    wf.MAX_DIALOGS + 8 +
    wf.MAX_TRIGGERS * 3 + 3 * 12 + // fired, preserved, running
    wf.MAX_TRIGGERS * 5 + 12 + // actAt
    wf.MAX_TRIGGERS * 12 + 12 + // waitLeft
    NFOE * 12 + 10 +
    chestmod.CAP + 10 +
    pickupmod.CAP + 10 + // the glows…
    item.NK + 8; // …and the discovery set, one character each plus its key

/// **WHAT A PICKER ROW SAYS** — read off the file itself, never kept in a second index beside it. Three
/// small files re-read when the shelf is surveyed is nothing, and a manifest is a thing that can disagree
/// with what it lists.
pub const Head = struct {
    /// The tree's own arithmetic (`ptree.Tree.level`): a level is not stored anywhere, it is counted.
    level: u32,
    souls: u32,
    /// Seconds lived in this world — the trigger machine's `elapsed`, which the save carries across.
    playtime: f32,
};

/// EVERY SLOT AT ONCE, which is what the boot screen needs to answer its two questions with: is Load live at
/// all (`any`), and what does each row say (`head`). BOTH boot rows now open the picker (`menu.openSlots`), so
/// nothing asks where a new character would go — the player says.
pub const Shelf = struct {
    head: [SLOTS]?Head = [_]?Head{null} ** SLOTS,

    pub fn any(self: *const Shelf) bool {
        for (self.head) |h| {
            if (h != null) return true;
        }
        return false;
    }

    /// NOWHERE LEFT TO PUT ONE. `any`'s opposite question, and the boot screen's New Game row hangs off it:
    /// a new character needs an EMPTY slot (owner's call), so with all three written there is no such thing
    /// as starting one until something is deleted.
    pub fn full(self: *const Shelf) bool {
        return self.firstFree() == null;
    }

    /// The first empty slot, or null when all three are full. It is no longer ER's "New Game takes the first
    /// free slot without asking" — both boot rows ask WHICH slot — but `full` is written on top of it, so it
    /// is what answers "is there anywhere left to start a character" for the boot screen's greyed New Game.
    pub fn firstFree(self: *const Shelf) ?usize {
        for (self.head, 0..) |h, i| {
            if (h == null) return i;
        }
        return null;
    }
};

/// **A SLOT ONLY LISTS IF IT WOULD ACTUALLY LOAD**, which is why the map is asked for here and not just at
/// `readFrom`. A file this build cannot honestly read is not a row with a level on it that dies when pressed
/// — that is precisely the "looks available and does nothing" the picker's own greying law refuses.
pub fn survey(map: []const u8) Shelf {
    var sh = Shelf{};
    for (0..SLOTS) |i| sh.head[i] = peek(map, i);
    return sh;
}

pub fn peek(map: []const u8, i: usize) ?Head {
    var d = Data{};
    if (!parseFile(PATHS[i], &d)) return null;
    if (!std.mem.eql(u8, d.mapName(), map)) return null;
    var taken: u32 = 0;
    for (d.tree) |t| taken += @intFromBool(t);
    return .{ .level = taken + 1, .souls = d.souls, .playtime = d.elapsed };
}

/// SIT DOWN AT A FIRE AND THIS IS WHAT HAPPENS. Silent: the fire's own screen is already saying where you
/// are, and a modal over it would be a second thing to dismiss at the one place the game lets you stop.
pub fn write(i: usize, s: Slot) bool {
    return writeTo(PATHS[i], s);
}

pub fn read(i: usize, s: Slot) bool {
    return readFrom(PATHS[i], s);
}

/// **A SLOT IS TWO FILES AND BOTH GO.** A picture left standing beside a save that is gone is precisely what
/// the picker's own rule forbids — a row reading "Empty" over a photograph of somebody's game — and it is why
/// the shot is deleted here rather than left for `writeShot` to overwrite one day.
///
/// A file that was never there is not a failure: what the caller asked for is that the slot END UP empty, and
/// it is. Only a delete that was REFUSED (a read-only file, a handle still open) comes back false, so the one
/// thing the menu can say — "that did not happen" — is the one thing this reports.
pub fn erase(i: usize) bool {
    var ok = true;
    std.fs.cwd().deleteFile(PATHS[i]) catch |e| {
        if (e != error.FileNotFound) ok = false;
    };
    // The picture is chrome. Losing the save but keeping the thumbnail is a broken slot; the other way round
    // is a slot that simply draws an empty plate, which the picker already handles.
    std.fs.cwd().deleteFile(SHOTS[i]) catch {};
    return ok;
}

/// THE PICTURE THE PICKER SHOWS A SLOT BY — the frame as it stands, scaled down. Taken at the fire and NOT
/// on the frame the file is written: `justEntered` fires at the bottom of the fade-in, where the screen is
/// black, so the game asks for this once the fade is back up (`game.SHOT_CLEAR`) and before any chrome goes
/// down over it. A slot with no picture still lists — the row just draws an empty plate.
const THUMB_W: i32 = 320;

/// **IT COSTS A FRAME, AND THAT IS WHERE IT IS SPENT.** `loadImageFromScreen` is a full-framebuffer
/// `glReadPixels` — a pipeline stall of several milliseconds — plus a resize and a PNG encode. It happens
/// ONCE, on one frame, at a bonfire: the one place in the game nothing is moving and nothing is being aimed
/// at you. Cheaper is not worth having; a thumbnail is what a readback buys.
pub fn writeShot(i: usize) bool {
    rl.gl.rlDrawRenderBatchActive(); // the batch has to be flushed or the grab is the PREVIOUS frame
    var img = rl.loadImageFromScreen() catch return false;
    defer rl.unloadImage(img);
    const w = rl.getScreenWidth();
    const h = rl.getScreenHeight();
    if (w <= 0 or h <= 0) return false;
    // THE SCREEN'S OWN ASPECT, not a 16:9 assumption: the window is resizable and a fixed pair of numbers
    // squashes the picture by whatever the player has dragged it to.
    rl.imageResize(&img, THUMB_W, @max(1, @divTrunc(THUMB_W * h, w)));
    return rl.exportImage(img, SHOTS[i]);
}

/// The path is an argument ONLY so the round trip through a real file can be tested without a test writing
/// over somebody's save. In the game a slot is an INDEX and `write`/`read` are the doors to it.
pub fn writeTo(file: []const u8, s: Slot) bool {
    // A NAME THAT DOES NOT FIT IS A REFUSED SAVE, NEVER A TRUNCATED ONE. `gather` clips to `MAP_CAP`, and a
    // clipped name is one `readFrom` can never match again — every save silently unloadable, which is the
    // worst failure this file has. The comptime assert below is what says it cannot happen today.
    if (s.map.len > MAP_CAP) return false;
    const d = gather(s);
    const f = std.fs.cwd().createFile(file, .{}) catch return false;
    defer f.close();
    // **A WRITE THAT DIED HALFWAY TAKES ITS FILE WITH IT.** A refused save is a false out of here and nothing
    // else; a TRUNCATED one is worse than either, because a short run is LEGAL in this grammar (`readBits`'s
    // own rule) — so the tail that never reached the disk parses as all-defaults and the slot lists and loads
    // as a character whose triggers, boxes, tree and bag have quietly gone back to nothing.
    render(f.writer(), &d) catch {
        std.fs.cwd().deleteFile(file) catch {};
        return false;
    };
    return true;
}

pub fn readFrom(file: []const u8, s: Slot) bool {
    var d = Data{};
    if (!parseFile(file, &d)) return false;
    // ANOTHER MAP'S SAVE IS NOT THIS MAP'S. Every index in here — the triggers, the boxes, `near npc=` —
    // belongs to the file it was written against, so replaying it elsewhere is not a partial load, it is a
    // different game wearing these numbers.
    if (!std.mem.eql(u8, d.mapName(), s.map)) return false;
    scatter(&d, s);
    return true;
}

fn parseFile(file: []const u8, d: *Data) bool {
    var buf: [CAP]u8 = undefined;
    const f = std.fs.cwd().openFile(file, .{}) catch return false;
    defer f.close();
    const n = f.readAll(&buf) catch return false;
    // IT FILLED THE BUFFER, so the tail was cut MID-LINE (`worldfmt.load`'s guard, and `audio`'s). A run
    // that lost its end parses as a SHORT one, which is a legal thing here — so the cut is invisible unless
    // the length is checked, and the file is refused whole rather than loaded with a truncated character.
    if (n == buf.len) return false;
    parse(buf[0..n], d) catch return false;
    return true;
}

pub fn gather(s: Slot) Data {
    var d = Data{};
    d.mapLen = @min(s.map.len, MAP_CAP);
    @memcpy(d.map[0..d.mapLen], s.map[0..d.mapLen]);

    const h = s.hero;
    d.at = h.pos;
    d.facing = h.facing;
    d.spawnAt = h.spawnPos;
    d.spawnFacing = h.spawnFacing;
    d.souls = h.souls.total;
    d.arm = h.arm;
    d.off = h.off;
    d.armAlt = h.armAlt;
    d.offAlt = h.offAlt;
    d.spell = h.spell;
    d.arrow = h.quiver.sel;
    d.flask = h.flasks.sel;
    d.quick = h.quick.slots;
    d.quickSel = h.quick.sel;

    d.bag = s.bag.counts;
    d.tree = s.tree.taken;
    d.dropAt = s.souls.drop.at;
    d.dropAmount = if (s.souls.drop.live) s.souls.drop.amount else 0;
    d.hour = s.day.hour;

    const t = s.trig;
    d.flags = t.flags;
    d.counters = t.counters;
    d.timers = t.timers;
    d.armed = t.armed;
    d.talked = t.talked;
    d.fired = t.fired;
    d.preserved = t.preserved;
    d.running = t.running;
    d.actAt = t.actAt;
    d.waitLeft = t.waitLeft;
    d.deaths = t.deaths;
    d.elapsed = t.elapsed;

    for (s.chests.liveConst(), 0..) |c, i| d.chestOpen[i] = c.opened;
    for (s.pickups.liveConst(), 0..) |p, i| d.pickupTaken[i] = p.taken;
    d.seen = s.award.seen;
    return d;
}

pub fn scatter(d: *const Data, s: Slot) void {
    const h = s.hero;
    h.pos = d.at;
    h.facing = d.facing;
    h.setSpawn(d.spawnAt, d.spawnFacing);
    h.souls.total = d.souls;
    h.souls.shown = @floatFromInt(d.souls);
    h.arm = d.arm;
    h.off = d.off;
    h.armAlt = d.armAlt;
    h.offAlt = d.offAlt;
    h.spell = d.spell;
    h.quiver.sel = d.arrow;
    h.flasks.sel = d.flask;
    h.quick.slots = d.quick;
    h.quick.sel = @min(d.quickSel, combat.QUICK_SLOTS - 1);

    s.bag.counts = d.bag;
    s.tree.taken = d.tree;
    // THROUGH THE MODULE'S OWN DOOR — `spill` arms the mote stream and the hum off the amount, where
    // writing the three fields by hand leaves a pile of gold standing there in silence.
    s.souls.spill(d.dropAt, d.dropAmount);
    s.day.set(d.hour);

    const t = s.trig;
    t.flags = d.flags;
    t.counters = d.counters;
    t.timers = d.timers;
    t.armed = d.armed;
    t.talked = d.talked;
    t.fired = d.fired;
    t.preserved = d.preserved;
    t.running = d.running;
    t.actAt = d.actAt;
    t.waitLeft = d.waitLeft;
    t.deaths = d.deaths;
    t.elapsed = d.elapsed;

    for (s.chests.live(), 0..) |*c, i| {
        c.opened = d.chestOpen[i];
        c.swing = if (c.opened) 1 else 0; // a lid you opened last session is not one caught mid-swing
    }
    for (s.pickups.live(), 0..) |*p, i| {
        p.taken = d.pickupTaken[i];
        p.fade = if (p.taken) 1 else 0; // …and a glow you took is gone, not one caught mid-shrink
    }
    s.award.seen = d.seen;
    // The pending notices are NOT restored — a card is a moment. Cleared, or a load lands you staring at the
    // item you were reading about when you last sat down.
    s.award.clearPending();
}

pub fn render(w: anytype, d: *const Data) !void {
    try w.print("version: {d}\n", .{VERSION});
    try w.print("map: {s}\n", .{d.mapName()});
    try w.print("at: {d:.3} {d:.3} {d:.3} {d:.4}\n", .{ d.at.x, d.at.y, d.at.z, d.facing });
    try w.print("spawn: {d:.3} {d:.3} {d:.3} {d:.4}\n", .{ d.spawnAt.x, d.spawnAt.y, d.spawnAt.z, d.spawnFacing });
    try w.print("souls: {d}\n", .{d.souls});
    try w.print("hands: {s} {s} {s} {s} {s}\n", .{ @tagName(d.arm), @tagName(d.off), @tagName(d.spell), @tagName(d.armAlt), @tagName(d.offAlt) });
    try w.print("ready: {s} {s}\n", .{ @tagName(d.arrow), @tagName(d.flask) });
    try w.writeAll("quick:");
    for (d.quick) |q| try w.print(" {s}", .{if (q) |k| item.tag(k) else "-"});
    try w.print("\nquicksel: {d}\n", .{d.quickSel});

    try w.writeAll("bag:");
    for (d.bag, 0..) |c, i| {
        if (c == 0) continue;
        try w.print(" {s} {d}", .{ item.tag(@enumFromInt(i)), c });
    }
    try w.writeByte('\n');

    try bits(w, "tree", &d.tree);
    try w.print("drop: {d:.3} {d:.3} {d:.3} {d}\n", .{ d.dropAt.x, d.dropAt.y, d.dropAt.z, d.dropAmount });
    try w.print("hour: {d:.4}\n", .{d.hour});

    try bits(w, "flags", &d.flags);
    try nums(w, "counters", &d.counters);
    try nums(w, "timers", &d.timers);
    try bits(w, "armed", &d.armed);
    try bits(w, "talked", &d.talked);
    try bits(w, "fired", &d.fired);
    try bits(w, "preserved", &d.preserved);
    try bits(w, "running", &d.running);
    try nums(w, "actat", &d.actAt);
    try nums(w, "waitleft", &d.waitLeft);
    try nums(w, "deaths", &d.deaths);
    try w.print("elapsed: {d:.3}\n", .{d.elapsed});
    try bits(w, "chests", &d.chestOpen);
    try bits(w, "pickups", &d.pickupTaken);
    try bits(w, "seen", &d.seen);
}

pub fn parse(text: []const u8, d: *Data) !void {
    var sawVersion = false;
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        if (line.len == 0 or line[0] == '#') continue;
        var it = std.mem.tokenizeAny(u8, line, " \t");
        const key = it.next() orelse continue;
        if (!sawVersion) {
            // FIRST LINE OR NOTHING. A file that opens with anything else is not one of ours, and reading
            // its body to find out would be reading an unversioned format.
            if (!std.mem.eql(u8, key, "version:")) return Error.BadVersion;
            if (try int(u32, &it) != VERSION) return Error.BadVersion;
            sawVersion = true;
        } else if (std.mem.eql(u8, key, "map:")) {
            const name = it.next() orelse return Error.BadField;
            if (name.len > MAP_CAP) return Error.BadField;
            d.mapLen = name.len;
            @memcpy(d.map[0..name.len], name);
        } else if (std.mem.eql(u8, key, "at:")) {
            d.at = try vec(&it);
            d.facing = try float(&it);
        } else if (std.mem.eql(u8, key, "spawn:")) {
            d.spawnAt = try vec(&it);
            d.spawnFacing = try float(&it);
        } else if (std.mem.eql(u8, key, "souls:")) {
            d.souls = try int(u32, &it);
        } else if (std.mem.eql(u8, key, "hands:")) {
            d.arm = try tagged(heromod.Armament, &it);
            d.off = try tagged(heromod.Armament, &it);
            d.spell = try tagged(combat.Spell, &it);
            // THE TWO ALTERNATES ARE OPTIONAL ON THE LINE, which is what lets a file written before a hand
            // was a pair still load: it keeps the live pair it named, and the alternates come up at their
            // defaults — honestly what that character was carrying.
            d.armAlt = tagged(heromod.Armament, &it) catch d.armAlt;
            d.offAlt = tagged(heromod.Armament, &it) catch d.offAlt;
        } else if (std.mem.eql(u8, key, "ready:")) {
            d.arrow = try tagged(combat.ArrowKind, &it);
            d.flask = try tagged(combat.FlaskKind, &it);
        } else if (std.mem.eql(u8, key, "quick:")) {
            d.quick = [_]?item.Kind{null} ** combat.QUICK_SLOTS;
            var i: usize = 0;
            while (it.next()) |tok| : (i += 1) {
                if (i >= d.quick.len) return Error.BadField;
                if (std.mem.eql(u8, tok, "-")) continue;
                d.quick[i] = item.fromTag(tok) orelse return Error.BadField;
            }
        } else if (std.mem.eql(u8, key, "quicksel:")) {
            d.quickSel = try int(usize, &it);
        } else if (std.mem.eql(u8, key, "bag:")) {
            d.bag = [_]u16{0} ** item.NK;
            while (it.next()) |tok| {
                const k = item.fromTag(tok) orelse return Error.BadField;
                d.bag[@intFromEnum(k)] = try int(u16, &it);
            }
        } else if (std.mem.eql(u8, key, "tree:")) {
            try readBits(&it, &d.tree);
        } else if (std.mem.eql(u8, key, "drop:")) {
            d.dropAt = try vec(&it);
            d.dropAmount = try int(u32, &it);
        } else if (std.mem.eql(u8, key, "hour:")) {
            d.hour = try float(&it);
        } else if (std.mem.eql(u8, key, "flags:")) {
            try readBits(&it, &d.flags);
        } else if (std.mem.eql(u8, key, "counters:")) {
            try readNums(i32, &it, &d.counters);
        } else if (std.mem.eql(u8, key, "timers:")) {
            try readNums(f32, &it, &d.timers);
        } else if (std.mem.eql(u8, key, "armed:")) {
            try readBits(&it, &d.armed);
        } else if (std.mem.eql(u8, key, "talked:")) {
            try readBits(&it, &d.talked);
        } else if (std.mem.eql(u8, key, "fired:")) {
            try readBits(&it, &d.fired);
        } else if (std.mem.eql(u8, key, "preserved:")) {
            try readBits(&it, &d.preserved);
        } else if (std.mem.eql(u8, key, "running:")) {
            try readBits(&it, &d.running);
        } else if (std.mem.eql(u8, key, "actat:")) {
            try readNums(u8, &it, &d.actAt);
        } else if (std.mem.eql(u8, key, "waitleft:")) {
            try readNums(f32, &it, &d.waitLeft);
        } else if (std.mem.eql(u8, key, "deaths:")) {
            try readNums(u32, &it, &d.deaths);
        } else if (std.mem.eql(u8, key, "elapsed:")) {
            d.elapsed = try float(&it);
        } else if (std.mem.eql(u8, key, "chests:")) {
            try readBits(&it, &d.chestOpen);
        } else if (std.mem.eql(u8, key, "pickups:")) {
            try readBits(&it, &d.pickupTaken);
        } else if (std.mem.eql(u8, key, "seen:")) {
            try readBits(&it, &d.seen);
        } else {
            return Error.BadKey;
        }
    }
    if (!sawVersion) return Error.BadVersion;
}

const Tok = std.mem.TokenIterator(u8, .any);

fn float(it: *Tok) !f32 {
    return std.fmt.parseFloat(f32, it.next() orelse return Error.BadField) catch Error.BadField;
}

fn int(comptime T: type, it: *Tok) !T {
    return std.fmt.parseInt(T, it.next() orelse return Error.BadField, 10) catch Error.BadField;
}

fn vec(it: *Tok) !rl.Vector3 {
    return .{ .x = try float(it), .y = try float(it), .z = try float(it) };
}

fn tagged(comptime T: type, it: *Tok) !T {
    return std.meta.stringToEnum(T, it.next() orelse return Error.BadField) orelse Error.BadField;
}

/// One character per element, so a run is one token and a diff shows which switch moved.
fn bits(w: anytype, key: []const u8, run: []const bool) !void {
    try w.print("{s}: ", .{key});
    for (run) |b| try w.writeByte(if (b) '1' else '0');
    try w.writeByte('\n');
}

/// A SHORT RUN IS LEGAL AND A LONG ONE IS NOT. Every run here defaults to zero, so a file written before a
/// cap grew loads its tail at exactly what a fresh runtime has; one written after it grew is from a build
/// this one cannot honestly read, and guessing which end to cut is how a save loads as a different game.
fn readBits(it: *Tok, out: []bool) !void {
    @memset(out, false);
    const txt = it.next() orelse return; // an empty run is all-false, which is the default
    if (txt.len > out.len) return Error.BadField;
    for (txt, 0..) |c, i| {
        if (c != '0' and c != '1') return Error.BadField;
        out[i] = c == '1';
    }
}

fn nums(w: anytype, key: []const u8, run: anytype) !void {
    try w.print("{s}:", .{key});
    for (run) |v| switch (@typeInfo(@TypeOf(v))) {
        .float => try w.print(" {d:.3}", .{v}),
        else => try w.print(" {d}", .{v}),
    };
    try w.writeByte('\n');
}

fn readNums(comptime T: type, it: *Tok, out: []T) !void {
    @memset(out, 0);
    var i: usize = 0;
    while (it.next()) |tok| : (i += 1) {
        if (i >= out.len) return Error.BadField;
        out[i] = switch (@typeInfo(T)) {
            .float => std.fmt.parseFloat(T, tok) catch return Error.BadField,
            else => std.fmt.parseInt(T, tok, 10) catch return Error.BadField,
        };
    }
}


const testing = std.testing;

fn roundTrip(d: *const Data) !Data {
    var buf: [CAP]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), d);
    var back = Data{};
    try parse(fbs.getWritten(), &back);
    return back;
}

fn sample() Data {
    var d = Data{};
    const name = wf.START_MAP;
    d.mapLen = name.len;
    @memcpy(d.map[0..name.len], name);
    d.at = .{ .x = -4.5, .y = 0.31, .z = 7.25 };
    d.facing = 3.1416;
    d.spawnAt = .{ .x = 1.5, .y = 0.01, .z = -2.0 };
    d.spawnFacing = -1.25;
    d.souls = 12345;
    d.arm = .bow;
    d.off = .wand;
    d.spell = .roots;
    d.arrow = .fire;
    d.flask = .cerulean;
    d.quick[0] = .crimson_flask;
    d.quick[3] = .mushroom_jerky;
    d.quickSel = 3;
    d.bag[@intFromEnum(item.Kind.kobold_fang)] = 7;
    d.bag[@intFromEnum(item.Kind.iron_key)] = 1;
    d.tree[2] = true;
    d.tree[ptree.N - 1] = true;
    d.dropAt = .{ .x = 30, .y = 2, .z = -11 };
    d.dropAmount = 980;
    d.hour = 17.75;
    d.flags[5] = true;
    d.counters[1] = -3;
    d.timers[2] = 4.5;
    d.armed[2] = true;
    d.talked[1] = true;
    d.fired[0] = true;
    d.preserved[3] = true;
    d.running[4] = true;
    d.actAt[4] = 2;
    d.waitLeft[4] = 1.25;
    d.deaths[0] = 6;
    d.elapsed = 421.5;
    d.chestOpen[1] = true;
    d.pickupTaken[3] = true;
    d.seen[@intFromEnum(item.Kind.mushroom_jerky)] = true;
    d.seen[item.NK - 1] = true; // the LAST bit too: a run written one short round-trips as all-false at the end
    return d;
}

test "a save round-trips through its own text" {
    const d = sample();
    const back = try roundTrip(&d);
    try testing.expectEqualStrings(d.mapName(), back.mapName());
    try testing.expectApproxEqAbs(d.at.x, back.at.x, 1e-3);
    try testing.expectApproxEqAbs(d.at.z, back.at.z, 1e-3);
    try testing.expectApproxEqAbs(d.facing, back.facing, 1e-4);
    try testing.expectApproxEqAbs(d.spawnFacing, back.spawnFacing, 1e-4);
    try testing.expectEqual(d.souls, back.souls);
    try testing.expectEqual(d.arm, back.arm);
    try testing.expectEqual(d.off, back.off);
    try testing.expectEqual(d.spell, back.spell);
    try testing.expectEqual(d.arrow, back.arrow);
    try testing.expectEqual(d.flask, back.flask);
    try testing.expectEqual(d.quick, back.quick);
    try testing.expectEqual(d.quickSel, back.quickSel);
    try testing.expectEqual(d.bag, back.bag);
    try testing.expectEqual(d.tree, back.tree);
    try testing.expectEqual(d.dropAmount, back.dropAmount);
    try testing.expectApproxEqAbs(d.hour, back.hour, 1e-3);
    try testing.expectEqual(d.flags, back.flags);
    try testing.expectEqual(d.counters, back.counters);
    try testing.expectEqual(d.armed, back.armed);
    try testing.expectEqual(d.talked, back.talked);
    try testing.expectEqual(d.fired, back.fired);
    try testing.expectEqual(d.preserved, back.preserved);
    try testing.expectEqual(d.running, back.running);
    try testing.expectEqual(d.actAt, back.actAt);
    try testing.expectEqual(d.deaths, back.deaths);
    try testing.expectApproxEqAbs(d.elapsed, back.elapsed, 1e-3);
    try testing.expectEqual(d.chestOpen, back.chestOpen);
    try testing.expectEqual(d.pickupTaken, back.pickupTaken);
    // **THE DISCOVERY SET SURVIVES THE FILE**, which is the whole reason it is in it: without this a reload
    // shows you the first-time card for everything you already own.
    try testing.expectEqual(d.seen, back.seen);
}

test "the buffer holds the biggest save this build can write" {
    // CAP is arithmetic over the tables, so the check is that the arithmetic is not SHORT — a file that
    // overruns it is refused on load (`read`'s filled-buffer guard) and the save silently stops working.
    var d = sample();
    for (&d.bag) |*c| c.* = item.CAP;
    for (&d.quick) |*q| q.* = .quilted_gambeson; // the longest tag, in every slot
    for (&d.counters) |*c| c.* = std.math.minInt(i32);
    for (&d.waitLeft) |*v| v.* = -99999.5;
    for (&d.actAt) |*v| v.* = 255;
    for (&d.deaths) |*v| v.* = std.math.maxInt(u32);
    for (&d.timers) |*v| v.* = -99999.5;
    var buf: [CAP]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), &d);
    try testing.expect(fbs.getWritten().len < CAP);
}

test "a file that does not open with its version is refused" {
    var d = Data{};
    try testing.expectError(Error.BadVersion, parse("souls: 10\nversion: 1\n", &d));
    try testing.expectError(Error.BadVersion, parse("version: 99\n", &d));
    try testing.expectError(Error.BadVersion, parse("# nothing but a comment\n", &d));
}

test "an unknown key is a load error, never a shrug" {
    var d = Data{};
    try testing.expectError(Error.BadKey, parse("version: 1\nhelmet: iron\n", &d));
}

test "a short run pads with the default and a long one is refused" {
    var d = Data{};
    d.flags[0] = true;
    try parse("version: 1\nflags: 01\n", &d);
    try testing.expect(!d.flags[0]);
    try testing.expect(d.flags[1]);
    try testing.expect(!d.flags[wf.MAX_FLAGS - 1]);

    const long = [_]u8{'1'} ** (wf.MAX_FLAGS + 2);
    var buf: [wf.MAX_FLAGS + 32]u8 = undefined;
    const text = try std.fmt.bufPrint(&buf, "version: 1\nflags: {s}\n", .{&long});
    try testing.expectError(Error.BadField, parse(text, &d));
}

test "a bag tag this build does not know is a load error" {
    var d = Data{};
    try testing.expectError(Error.BadField, parse("version: 1\nbag: dragon_hoard 3\n", &d));
}

/// The live objects a `Slot` points at, with only the fields `gather`/`scatter` touch made real. The three
/// mesh-bearing ones cannot be `init`ed without a GL context, and none of their meshes is read here.
const Live = struct {
    hero: heromod.Hero = undefined,
    bag: item.Bag = .{},
    tree: ptree.Tree = .{},
    souls: soulsmod.Souls = undefined,
    day: daynight.Clock = .{},
    trig: trigmod.Runtime = .{},
    chests: chestmod.Chests = undefined,
    pickups: pickupmod.Pickups = .{},
    award: awardmod.Award = .{},

    fn blank(nChests: usize) Live {
        var l = Live{};
        l.hero.pos = mathx.zero3;
        l.hero.facing = 0;
        l.hero.spawnPos = mathx.zero3;
        l.hero.spawnFacing = 0;
        l.hero.souls = .{};
        l.hero.arm = .sword;
        l.hero.off = .shield;
        l.hero.spell = .bolt;
        l.hero.quiver = .{};
        l.hero.flasks = .{};
        l.hero.quick = .{};
        l.souls.drop = .{};
        l.chests.n = nChests;
        for (0..nChests) |i| l.chests.list[i] = .{};
        return l;
    }

    fn slot(self: *Live) Slot {
        return .{
            .hero = &self.hero,
            .bag = &self.bag,
            .tree = &self.tree,
            .souls = &self.souls,
            .day = &self.day,
            .trig = &self.trig,
            .chests = &self.chests,
            .pickups = &self.pickups,
            .award = &self.award,
            .map = wf.START_MAP,
        };
    }
};

test "THE SLOT CARRIES EVERY FIELD IT NAMES — live game out, text, live game back in" {
    // The one test that can catch a field DROPPED from `gather`/`scatter` or written into the wrong one.
    // Values are chosen to survive `{d:.3}` exactly, so the comparison can be equality rather than a
    // tolerance per field — a tolerance is what would let a swapped pair through.
    const N_CHESTS = 4;
    var a = Live.blank(N_CHESTS);
    a.hero.pos = .{ .x = -4.5, .y = 0.25, .z = 7.125 };
    a.hero.facing = 1.5;
    a.hero.spawnPos = .{ .x = 12.5, .y = 1.5, .z = -30.25 };
    a.hero.spawnFacing = -0.75;
    a.hero.souls.total = 4321;
    a.hero.arm = .bell;
    a.hero.off = .wand;
    a.hero.spell = .roots;
    a.hero.quiver.sel = .fire;
    a.hero.flasks.sel = .cerulean;
    a.hero.quick.slots[4] = .ember_candle;
    a.hero.quick.sel = 4;
    a.bag.add(.kobold_fang, 9);
    a.bag.add(.iron_key, 1);
    a.tree.taken[3] = true;
    a.souls.drop = .{ .at = .{ .x = 8.5, .y = 0.5, .z = -2.25 }, .amount = 777, .live = true };
    a.day.set(19.5);
    a.trig.flags[7] = true;
    a.trig.counters[2] = 5;
    a.trig.timers[1] = 2.5;
    a.trig.armed[1] = true;
    a.trig.talked[0] = true;
    a.trig.fired[6] = true;
    a.trig.preserved[6] = true;
    a.trig.running[9] = true;
    a.trig.actAt[9] = 3;
    a.trig.waitLeft[9] = 0.5;
    a.trig.deaths[1] = 11;
    a.trig.elapsed = 300.5;
    a.chests.list[2].opened = true;

    const out = gather(a.slot());
    const back = try roundTrip(&out);

    var b = Live.blank(N_CHESTS);
    scatter(&back, b.slot());
    try testing.expectEqual(out, gather(b.slot()));

    // …and the two things `scatter` derives rather than copies, which a re-gather cannot see.
    // The counter arrives SNAPPED, never rolling: a load is not a number you just earned.
    try testing.expectEqual(@as(f32, 4321), b.hero.souls.shown);
    try testing.expect(b.chests.list[2].swing == 1 and b.chests.list[0].swing == 0);
}

test "the file itself round-trips, and one written for another map is refused" {
    const tmp = "save.test.dat";
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var a = Live.blank(2);
    a.hero.souls.total = 606;
    a.tree.taken[5] = true;
    try testing.expect(writeTo(tmp, a.slot()));

    var b = Live.blank(2);
    try testing.expect(readFrom(tmp, b.slot()));
    try testing.expectEqual(@as(u32, 606), b.hero.souls.total);
    try testing.expect(b.tree.taken[5]);

    // The same file, asked for by a slot that belongs to a different world.
    var c = Live.blank(2);
    var wrong = c.slot();
    wrong.map = "worlds/02_brood_arena.world";
    try testing.expect(!readFrom(tmp, wrong));
    try testing.expectEqual(@as(u32, 0), c.hero.souls.total); // …and nothing of it landed

    try testing.expect(!readFrom("save.no_such_file.dat", b.slot()));
}

test "the shelf answers what the boot screen asks it" {
    var sh = Shelf{};
    try testing.expect(!sh.any());
    try testing.expectEqual(@as(?usize, 0), sh.firstFree());

    sh.head[0] = .{ .level = 4, .souls = 90, .playtime = 12 };
    try testing.expect(sh.any());
    try testing.expectEqual(@as(?usize, 1), sh.firstFree()); // …the first EMPTY one, not the first one

    sh.head[2] = .{ .level = 1, .souls = 0, .playtime = 0 };
    try testing.expectEqual(@as(?usize, 1), sh.firstFree()); // …and it fills the hole rather than appending

    sh.head[1] = .{ .level = 9, .souls = 5, .playtime = 3 };
    try testing.expectEqual(@as(?usize, null), sh.firstFree()); // full: there is nowhere to put a new one
    try testing.expect(sh.full());

    // `full` and `any` are the two the boot screen hangs its rows off, and they are NOT opposites: a shelf
    // with one save on it answers true to both, which is the ordinary case and the one a naive `!any()`
    // would have got wrong.
    var one = Shelf{};
    one.head[1] = .{ .level = 2, .souls = 1, .playtime = 1 };
    try testing.expect(one.any() and !one.full());
    const none = Shelf{};
    try testing.expect(!none.any() and !none.full());
}

test "a slot's head is counted off the file, level included" {
    const tmp = "save.head.dat";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    var a = Live.blank(0);
    a.hero.souls.total = 2500;
    a.trig.elapsed = 3661;
    a.tree.taken[1] = true;
    a.tree.taken[4] = true;
    a.tree.taken[9] = true;
    try testing.expect(writeTo(tmp, a.slot()));

    var d = Data{};
    try testing.expect(parseFile(tmp, &d));
    var taken: u32 = 0;
    for (d.tree) |t| taken += @intFromBool(t);
    try testing.expectEqual(@as(u32, 4), taken + 1); // LEVEL IS COUNTED — three nodes is level four
    try testing.expectEqual(@as(u32, 2500), d.souls);
    try testing.expectApproxEqAbs(@as(f32, 3661), d.elapsed, 0.01);
}

test "a name too long to store is a refused save, not a truncated one" {
    // A clipped name is one `readFrom` can never match again — the save would write, list, and refuse to
    // load for the rest of its life.
    const tmp = "save.long.dat";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    var a = Live.blank(0);
    var s = a.slot();
    s.map = "w/" ++ "x" ** MAP_CAP;
    try testing.expect(!writeTo(tmp, s));
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(tmp, .{})); // …and nothing was written

    // The longest name that DOES fit still round-trips whole, which is what makes the guard a boundary
    // rather than a cliff somewhere near one.
    const fits = "w/" ++ "x" ** (MAP_CAP - 2);
    s.map = fits;
    try testing.expect(writeTo(tmp, s));
    var b = Live.blank(0);
    var back = b.slot();
    back.map = fits;
    try testing.expect(readFrom(tmp, back));
}

test "every slot owns a distinct pair of files" {
    // A shared path is a shelf where three characters are one character, and it fails SILENTLY.
    for (0..SLOTS) |i| {
        for (0..SLOTS) |j| {
            if (i == j) continue;
            try testing.expect(!std.mem.eql(u8, path(i), path(j)));
            try testing.expect(!std.mem.eql(u8, shotPath(i), shotPath(j)));
        }
        try testing.expect(!std.mem.eql(u8, path(i), shotPath(i)));
    }
}

test "an empty bag line clears the bag rather than leaving the last one" {
    var d = Data{};
    d.bag[0] = 9;
    try parse("version: 1\nbag:\n", &d);
    try testing.expectEqual(@as(u16, 0), d.bag[0]);
}
