const std = @import("std");
const rl = @import("raylib");

const chestmod = @import("play/chest.zig");
const pickupmod = @import("play/pickup.zig");
const awardmod = @import("play/award.zig");
const mapart = @import("ui/mapart.zig");
const combat = @import("play/combat.zig");
const daynight = @import("world/daynight.zig");
const heromod = @import("play/hero.zig");
const item = @import("play/item.zig");
const mathx = @import("core/mathx.zig");
const ptree = @import("play/passivetree.zig");
const soulsmod = @import("play/souls.zig");
const trigmod = @import("world/trigger.zig");
const wf = @import("world/worldfmt.zig");

/// THIS FILE, for the tests that read their own SOURCE. A stale copy does not fail — `readForTest` turns a missing path into `error.SkipZigTest`.
const SRC = "src/save.zig";

pub const VERSION: u32 = 1;

pub const SLOTS: usize = 3;

fn slotNames(comptime stem: []const u8, comptime ext: []const u8) [SLOTS][:0]const u8 {
    var out: [SLOTS][:0]const u8 = undefined;
    for (&out, 0..) |*p, i| p.* = std.fmt.comptimePrint(stem ++ "{d}." ++ ext, .{i + 1});
    return out;
}

const PATHS = slotNames("save", "dat");
const SHOTS = slotNames("save", "png");
const DEV_PATHS = slotNames("devsave", "dat");
const DEV_SHOTS = slotNames("devsave", "png");

comptime {
    std.debug.assert(std.mem.eql(u8, PATHS[0], "save1.dat"));
    std.debug.assert(std.mem.eql(u8, SHOTS[SLOTS - 1], "save3.png"));
    std.debug.assert(std.mem.eql(u8, DEV_PATHS[0], "devsave1.dat"));
}

/// Positional rows: an APPEND passes both pins; an insert, a removal or a rename fails them.
const TIERS_SAVED = [_][]const u8{ "sword", "dagger", "club", "bow", "bell", "shield", "wand", "torch" };
const TREE_SAVED: usize = 81;
const TREE_SAVED_FNV: u64 = 0xead516985217e25f;

comptime {
    for (TIERS_SAVED, 0..) |n, i| {
        if (i >= heromod.NARM or !std.mem.eql(u8, @tagName(@as(heromod.Armament, @enumFromInt(i))), n))
            @compileError("save: `tiers:` is positional over `hero.Armament`, and `" ++ n ++ "` is no longer where the files put it");
    }
    @setEvalBranchQuota(200000);
    if (ptree.N < TREE_SAVED) @compileError("save: `tree:` is positional over the node table, and a node the files index has gone");
    var h = std.hash.Fnv1a_64.init();
    for (ptree.NODES_BANK[0..TREE_SAVED]) |n| {
        h.update(n.name);
        h.update("|");
    }
    if (h.final() != TREE_SAVED_FNV) @compileError(std.fmt.comptimePrint("save: `tree:` is positional over the node table and its first {d} nodes moved (fnv 0x{x}) - append, never insert", .{ TREE_SAVED, h.final() }));
}

var devShelf = false;

pub fn useDevShelf(on: bool) void {
    devShelf = on;
}

pub fn onDevShelf() bool {
    return devShelf;
}

pub fn path(i: usize) [:0]const u8 {
    return if (devShelf) DEV_PATHS[i] else PATHS[i];
}
pub fn shotPath(i: usize) [:0]const u8 {
    return if (devShelf) DEV_SHOTS[i] else SHOTS[i];
}

pub const Error = error{ BadVersion, BadKey, BadField };

pub const Slot = struct {
    hero: *heromod.Hero,
    bag: *item.Bag,
    tree: *ptree.Tree,
    souls: *soulsmod.Souls,
    day: *daynight.Clock,
    trig: *trigmod.Runtime,
    chests: *chestmod.Chests,
    pickups: *pickupmod.Pickups,
    bosses: *BossBits,
    award: *awardmod.Award,
    seenMap: *mapart.Seen,
    map: []const u8,
};

pub const MAP_CAP = wf.PATH_CAP;
comptime {
    if (wf.START_MAP.len > MAP_CAP) @compileError("save: MAP_CAP is shorter than the map path it has to hold");
}

pub const MapName = struct {
    buf: [MAP_CAP]u8 = [_]u8{0} ** MAP_CAP,
    len: usize = 0,

    pub fn of(p: []const u8) MapName {
        var m = MapName{ .len = @min(p.len, MAP_CAP) };
        @memcpy(m.buf[0..m.len], p[0..m.len]);
        return m;
    }

    pub fn name(self: *const MapName) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn is(self: *const MapName, p: []const u8) bool {
        return std.mem.eql(u8, self.name(), p);
    }
};

/// RAIL 0 IS THE FILE'S ORIGINAL `bosses:` ROW AND STAYS THAT WAY: a save written before the duo existed describes one rail, and a row nobody wrote reads back as nobody dead.
pub const BOSS_RAILS: usize = 4;
pub const BossBits = [BOSS_RAILS][wf.MAX_PER_KIND]bool;

pub const Drop = struct {
    at: rl.Vector3 = mathx.zero3,
    n: u8 = 0,
    loot: [pickupmod.DROP_MAX]item.Kind = undefined,
    gold: u32 = 0,
};

pub const Data = struct {
    map: [MAP_CAP]u8 = [_]u8{0} ** MAP_CAP,
    mapLen: usize = 0,

    at: rl.Vector3 = mathx.zero3,
    facing: f32 = 0,
    souls: u32 = 0,
    gold: u32 = 0,
    tiers: [heromod.NARM]u8 = [_]u8{0} ** heromod.NARM,

    arm: heromod.Armament = .sword,
    off: heromod.Armament = .shield,
    armAlt: heromod.Armament = .bow,
    offAlt: heromod.Armament = .wand,
    spell: combat.Spell = .bolt,
    memory: [combat.MEM_SLOTS]?combat.Spell = (combat.Memory{}).slots,
    arrow: combat.ArrowKind = .plain,
    arrows: u8 = combat.ARROWS_MAX,
    fireArrows: u8 = combat.FIRE_ARROWS_MAX,
    flask: combat.FlaskKind = .crimson,
    /// The ALLOTMENT, not what is left in them — a bonfire fills to it. Appended to `ready:`, so a file written before the split existed still loads and takes the default.
    crimsonMax: u8 = combat.FLASK_CRIMSON,
    /// The whole pool, grown by every empty flask found; also appended to `ready:`, so an older file keeps the default.
    flaskTotal: u8 = combat.FLASK_TOTAL,
    quick: [combat.QUICK_SLOTS]?item.Kind = [_]?item.Kind{null} ** combat.QUICK_SLOTS,
    quickSel: usize = 0,
    worn: heromod.Worn = .{},

    bag: [item.NK]u16 = [_]u16{0} ** item.NK,
    tree: [ptree.N]bool = [_]bool{false} ** ptree.N,

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
    running: [wf.MAX_TRIGGERS]bool = [_]bool{false} ** wf.MAX_TRIGGERS,
    actAt: [wf.MAX_TRIGGERS]u8 = [_]u8{0} ** wf.MAX_TRIGGERS,
    waitLeft: [wf.MAX_TRIGGERS]f32 = [_]f32{0} ** wf.MAX_TRIGGERS,
    deaths: [NFOE]u32 = [_]u32{0} ** NFOE,
    elapsed: f32 = 0,

    chestOpen: [chestmod.CAP]bool = [_]bool{false} ** chestmod.CAP,
    pickupTaken: [pickupmod.CAP]bool = [_]bool{false} ** pickupmod.CAP,
    ground: [pickupmod.CAP]Drop = [_]Drop{.{}} ** pickupmod.CAP,
    groundN: usize = 0,
    bossDead: BossBits = [_][wf.MAX_PER_KIND]bool{[_]bool{false} ** wf.MAX_PER_KIND} ** BOSS_RAILS,
    seen: [item.NK]bool = [_]bool{false} ** item.NK,
    /// One bit a chart cell (`mapart.Seen`) — the widest row the file carries.
    seenMap: [mapart.SEEN_CELLS]bool = [_]bool{false} ** mapart.SEEN_CELLS,

    pub fn mapName(self: *const Data) []const u8 {
        return self.map[0..self.mapLen];
    }
};

const NFOE = wf.NFOE;
const NWEAR = @typeInfo(item.Wear).@"enum".fields.len;

const CAP: usize =
    64 + MAP_CAP +
    20 +
    3 * 48 +
    5 * 32 +
    combat.QUICK_SLOTS * 28 + 16 +
    combat.MEM_SLOTS * 14 + 10 +
    NWEAR * 28 + 8 +

    item.NK * 36 + 8 +
    ptree.N + 8 +
    wf.MAX_FLAGS + 8 +
    wf.MAX_COUNTERS * 13 + 12 +
    wf.MAX_TIMERS * 12 + wf.MAX_TIMERS + 24 +
    wf.MAX_DIALOGS + 8 +
    wf.MAX_TRIGGERS * 3 + 3 * 12 +
    wf.MAX_TRIGGERS * 5 + 12 +
    wf.MAX_TRIGGERS * 12 + 12 +
    NFOE * 12 + 10 +
    chestmod.CAP + 10 +
    pickupmod.CAP + 10 +
    BOSS_RAILS * (wf.MAX_PER_KIND + 12) +
    pickupmod.CAP * (3 * 11 + 4 + pickupmod.DROP_MAX * (item.TAG_MAX + 1) + 12) + 10 +
    item.NK + 8 +
    mapart.SEEN_CELLS + 12;

pub const Head = struct {
    level: u32,
    souls: u32,
    playtime: f32,
    map: MapName = .{},
};

pub const Shelf = struct {
    head: [SLOTS]?Head = [_]?Head{null} ** SLOTS,
    /// A FILE THAT IS THERE AND WILL NOT PARSE IS NOT AN EMPTY SLOT: read as empty it is offered for a new game and overwritten.
    unreadable: [SLOTS]bool = [_]bool{false} ** SLOTS,

    pub fn any(self: *const Shelf) bool {
        for (self.head) |h| {
            if (h != null) return true;
        }
        return false;
    }

    pub fn full(self: *const Shelf) bool {
        return self.firstFree() == null;
    }

    /// Good or bad: what opens the picker, since DELETE is only there.
    pub fn anyHeld(self: *const Shelf) bool {
        for (0..SLOTS) |i| {
            if (self.holds(i)) return true;
        }
        return false;
    }

    pub fn firstFree(self: *const Shelf) ?usize {
        for (self.head, 0..) |h, i| {
            if (h == null and !self.unreadable[i]) return i;
        }
        return null;
    }

    /// Whether the slot holds a file at all — a good save or a bad one. What DELETE answers to.
    pub fn holds(self: *const Shelf, i: usize) bool {
        return self.head[i] != null or self.unreadable[i];
    }

    /// The file parses (so `peek` filled `head`) but the run behind it will not open. Clearing `head` alone offers the
    /// slot for a new game over the top of a live save.
    pub fn refused(self: *Shelf, i: usize) void {
        self.head[i] = null;
        self.unreadable[i] = onDisk(i);
    }
};

pub fn survey() Shelf {
    drain();
    const sh = surveyRaw();
    // A result not yet taken carries a shelf from before whatever this survey follows (a delete), and `pumpSave` would lay it back over this one.
    bg.mtx.lock();
    if (bg.ready) bg.shelf = sh;
    bg.mtx.unlock();
    return sh;
}

fn surveyRaw() Shelf {
    var sh = Shelf{};
    for (0..SLOTS) |i| {
        sh.head[i] = peek(i);
        sh.unreadable[i] = sh.head[i] == null and onDisk(i);
    }
    return sh;
}

fn onDisk(i: usize) bool {
    std.fs.cwd().access(path(i), .{}) catch return false;
    return true;
}

pub fn peek(i: usize) ?Head {
    var d = Data{};
    if (!parseFile(path(i), &d)) return null;
    var taken: u32 = 0;
    for (d.tree) |t| taken += @intFromBool(t);
    return .{ .level = taken + 1, .souls = d.souls, .playtime = d.elapsed, .map = MapName.of(d.mapName()) };
}

/// The world a slot was written in, read without loading the run: `game.loadGame` opens this map before it scatters
/// the file. It is the FIRST read of the slot and owes `drain`'s rule — unwaited, it is the read that crosses a
/// half-written file.
pub fn mapOf(i: usize) ?MapName {
    drain();
    return mapOfFile(path(i));
}

pub fn mapOfFile(file: []const u8) ?MapName {
    var d = Data{};
    if (!parseFile(file, &d)) return null;
    return MapName.of(d.mapName());
}

pub fn read(i: usize, s: Slot) bool {
    drain();
    return readFrom(path(i), s);
}

/// THE DISK IS OFF THE FRAME, AND `gather` IS NOT: the snapshot is taken on the MAIN thread — it reads live game state through the view — and only
/// the render, the rename and the survey behind them ride the worker.
const Bg = struct {
    mtx: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    thread: ?std.Thread = null,
    quit: bool = false,
    /// A snapshot waiting in `data`. A second save while one is in flight REPLACES it rather than queuing: every write is the whole file.
    pending: bool = false,
    working: bool = false,
    slot: usize = 0,
    data: Data = .{},
    ready: bool = false,
    ok: bool = false,
    doneSlot: usize = 0,
    shelf: Shelf = .{},
};
var bg: Bg = .{};

pub const Done = struct { ok: bool, slot: usize, shelf: Shelf };

/// Refused OUTRIGHT, never truncated: either fault writes a clean slot that reads back unloadable. TOO LONG —
/// `MapName.of` clamps it and a clamped name no longer matches. A SPACE — the row is read back with a whitespace
/// tokeniser, so `readFrom` compares the first word against the whole path. Every writer of a map name asks here.
pub fn refuses(map: []const u8) ?[]const u8 {
    if (map.len > MAP_CAP) return "is longer than a slot can hold";
    for (map) |c| {
        if (c == ' ' or c == '\t') return "holds a space, which the `map:` row is read past";
    }
    return null;
}

pub fn writeAsync(i: usize, s: Slot) void {
    if (refuses(s.map) != null) {
        bg.mtx.lock();
        defer bg.mtx.unlock();
        finish(i, false, bg.shelf);
        return;
    }
    const d = gather(s);
    bg.mtx.lock();
    bg.slot = i;
    bg.data = d;
    bg.pending = true;
    if (bg.thread == null) {
        bg.thread = std.Thread.spawn(.{}, bgLoop, .{}) catch null;
        if (bg.thread == null) {
            bg.pending = false;
            bg.mtx.unlock();
            const ok = writeData(path(i), &d);
            const sh = surveyRaw();
            bg.mtx.lock();
            finish(i, ok, sh);
            bg.mtx.unlock();
            return;
        }
    }
    bg.mtx.unlock();
    bg.cond.broadcast();
}

fn finish(i: usize, ok: bool, sh: Shelf) void {
    bg.ready = true;
    bg.ok = ok;
    bg.doneSlot = i;
    bg.shelf = sh;
}

fn bgLoop() void {
    while (true) {
        bg.mtx.lock();
        while (!bg.pending and !bg.quit) bg.cond.wait(&bg.mtx);
        if (!bg.pending) {
            bg.mtx.unlock();
            return;
        }
        const i = bg.slot;
        const d = bg.data;
        bg.pending = false;
        bg.working = true;
        bg.mtx.unlock();

        const ok = writeData(path(i), &d);
        const sh = surveyRaw();

        bg.mtx.lock();
        bg.working = false;
        finish(i, ok, sh);
        bg.mtx.unlock();
        bg.cond.broadcast();
    }
}

/// What the write COST, taken on the main thread. The shelf the worker surveyed is the one the picker reads.
pub fn takeDone() ?Done {
    bg.mtx.lock();
    defer bg.mtx.unlock();
    if (!bg.ready) return null;
    bg.ready = false;
    return .{ .ok = bg.ok, .slot = bg.doneSlot, .shelf = bg.shelf };
}

/// ONE WRITER OF THESE FILES AT A TIME — every main-thread path that reads, surveys or deletes a slot waits here, so a load can never cross a half-written file.
pub fn drain() void {
    bg.mtx.lock();
    while (bg.pending or bg.working) bg.cond.wait(&bg.mtx);
    bg.mtx.unlock();
}

pub fn shutdown() void {
    drain();
    bg.mtx.lock();
    bg.quit = true;
    bg.mtx.unlock();
    bg.cond.broadcast();
    if (bg.thread) |t| {
        t.join();
        bg.thread = null;
    }
    // The latch goes with the thread: left set, every save after this one queues behind a thread that is gone.
    bg.quit = false;
}

pub fn erase(i: usize) bool {
    drain();
    std.fs.cwd().deleteFile(path(i)) catch |e| {
        // The save survived, so its picture stays with it rather than the row going blank over a live file.
        if (e != error.FileNotFound) return false;
    };
    std.fs.cwd().deleteFile(shotPath(i)) catch {};
    return true;
}

const THUMB_W: i32 = 320;

pub fn writeShot(i: usize) bool {
    rl.gl.rlDrawRenderBatchActive();
    var img = rl.loadImageFromScreen() catch return false;
    defer rl.unloadImage(img);
    const w = rl.getScreenWidth();
    const h = rl.getScreenHeight();
    if (w <= 0 or h <= 0) return false;
    rl.imageResize(&img, THUMB_W, @max(1, @divTrunc(THUMB_W * h, w)));
    return rl.exportImage(img, shotPath(i));
}

/// WRITE BESIDE IT AND RENAME OVER IT (`worldfmt.save`'s rule, and this is the other file the game writes):
/// `createFile` truncates first, so a render that failed part-way took the save it was replacing with it.
pub fn writeTo(file: []const u8, s: Slot) bool {
    if (refuses(s.map) != null) return false;
    const d = gather(s);
    return writeData(file, &d);
}

fn writeData(file: []const u8, d: *const Data) bool {
    var tmpBuf: [MAP_CAP + 16]u8 = undefined;
    const tmp = std.fmt.bufPrint(&tmpBuf, "{s}.tmp", .{file}) catch return false;
    {
        const f = std.fs.cwd().createFile(tmp, .{}) catch return false;
        defer f.close();
        render(f.writer(), d) catch {
            std.fs.cwd().deleteFile(tmp) catch {};
            return false;
        };
    }
    std.fs.cwd().rename(tmp, file) catch {
        std.fs.cwd().deleteFile(tmp) catch {};
        return false;
    };
    return true;
}

pub fn readFrom(file: []const u8, s: Slot) bool {
    var d = Data{};
    if (!parseFile(file, &d)) return false;
    if (!std.mem.eql(u8, d.mapName(), s.map)) return false;
    scatter(&d, s);
    return true;
}

fn parseFile(file: []const u8, d: *Data) bool {
    var buf: [CAP]u8 = undefined;
    const f = std.fs.cwd().openFile(file, .{}) catch return false;
    defer f.close();
    const n = f.readAll(&buf) catch return false;
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
    d.souls = h.souls.total;
    d.gold = h.gold.total;
    d.tiers = h.tiers;
    d.arm = h.arm;
    d.off = h.off;
    d.armAlt = h.armAlt;
    d.offAlt = h.offAlt;
    d.spell = h.spell;
    d.memory = h.mem.slots;
    d.arrow = h.quiver.sel;
    d.arrows = h.quiver.arrows;
    d.fireArrows = h.quiver.fire;
    d.flask = h.flasks.sel;
    d.crimsonMax = h.flasks.crimsonMax;
    d.flaskTotal = h.flasks.total();
    d.quick = h.quick.slots;
    d.quickSel = h.quick.sel;
    d.worn = h.worn;

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
    for (s.pickups.mappedConst(), 0..) |p, i| d.pickupTaken[i] = p.taken;
    d.groundN = 0;
    for (s.pickups.droppedConst()) |p| {
        if (p.taken or !p.dropped()) continue;
        if (d.groundN >= d.ground.len) break;
        d.ground[d.groundN] = .{ .at = p.pos, .n = p.nloot, .loot = p.loot, .gold = p.gold };
        d.groundN += 1;
    }
    d.bossDead = s.bosses.*;
    d.seen = s.award.seen;
    d.seenMap = s.seenMap.cell;
    return d;
}

pub fn scatter(d: *const Data, s: Slot) void {
    const h = s.hero;
    h.pos = d.at;
    h.facing = d.facing;
    h.setSpawn(d.at, d.facing);
    h.souls.total = d.souls;
    h.souls.shown = @floatFromInt(d.souls);
    h.gold.total = d.gold;
    h.gold.shown = @floatFromInt(d.gold);
    for (&h.tiers, d.tiers) |*t, v| t.* = @min(v, heromod.TIER_MAX);
    h.arm = d.arm;
    h.off = d.off;
    h.armAlt = d.armAlt;
    h.offAlt = d.offAlt;
    h.tidyHands();
    h.spell = d.spell;
    h.mem.slots = d.memory;
    h.tidySpells();
    h.quiver.sel = d.arrow;
    h.quiver.arrows = @min(d.arrows, combat.Quiver.cap(.plain));
    h.quiver.fire = @min(d.fireArrows, combat.Quiver.cap(.fire));
    h.flasks.sel = d.flask;
    h.flasks.pool(@min(d.flaskTotal, combat.FLASK_CAP), d.crimsonMax);
    h.quick.slots = d.quick;
    h.quick.sel = @min(d.quickSel, combat.QUICK_SLOTS - 1);

    for (&s.bag.counts, d.bag) |*c, v| c.* = @min(v, item.CAP);
    s.tree.taken = d.tree;
    h.applyPerks(s.tree.bonus());
    inline for (@typeInfo(item.Wear).@"enum".fields) |f| {
        const w: item.Wear = @enumFromInt(f.value);
        _ = h.wear(w, d.worn.at(w));
    }

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
        c.swing = if (c.opened) 1 else 0;
    }
    for (s.pickups.mappedOnes(), 0..) |*p, i| {
        p.taken = d.pickupTaken[i];
        p.fade = if (p.taken) 1 else 0;
    }
    s.pickups.clearDropped();
    for (d.ground[0..d.groundN]) |g| s.pickups.spawn(g.at, g.at, g.loot[0..g.n], g.gold);
    s.bosses.* = d.bossDead;
    s.award.seen = d.seen;
    s.award.clearPending();
    s.seenMap.cell = d.seenMap;
    s.seenMap.gen +%= 1;
    s.seenMap.at = -1;
}

pub fn render(w: anytype, d: *const Data) !void {
    try w.print("version: {d}\n", .{VERSION});
    try w.print("map: {s}\n", .{d.mapName()});
    try w.print("at: {d:.3} {d:.3} {d:.3} {d:.4}\n", .{ d.at.x, d.at.y, d.at.z, d.facing });
    try w.print("souls: {d}\n", .{d.souls});
    if (d.gold > 0) try w.print("gold: {d}\n", .{d.gold});
    var anyTier = false;
    for (d.tiers) |t| anyTier = anyTier or t > 0;
    if (anyTier) {
        try w.writeAll("tiers:");
        for (d.tiers) |t| try w.print(" {d}", .{t});
        try w.writeAll("\n");
    }
    try w.print("hands: {s} {s} {s} {s} {s}\n", .{ @tagName(d.arm), @tagName(d.off), @tagName(d.spell), @tagName(d.armAlt), @tagName(d.offAlt) });
    try w.print("ready: {s} {s} {d} {d}\n", .{ @tagName(d.arrow), @tagName(d.flask), d.crimsonMax, d.flaskTotal });
    try w.print("quiver: {d} {d}\n", .{ d.arrows, d.fireArrows });
    try w.writeAll("memory:");
    for (d.memory) |m| try w.print(" {s}", .{if (m) |sp| @tagName(sp) else "-"});
    try w.writeByte('\n');
    try w.writeAll("quick:");
    for (d.quick) |q| try w.print(" {s}", .{if (q) |k| item.tag(k) else "-"});
    try w.print("\nquicksel: {d}\n", .{d.quickSel});
    try w.writeAll("worn:");
    inline for (@typeInfo(item.Wear).@"enum".fields) |f| {
        const k = d.worn.at(@enumFromInt(f.value));
        try w.print(" {s}", .{if (k) |kind| item.tag(kind) else "-"});
    }
    try w.writeAll("\n");

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
    try w.writeAll("ground:");
    for (d.ground[0..d.groundN]) |g| {
        try w.print(" {d:.3} {d:.3} {d:.3} {d}", .{ g.at.x, g.at.y, g.at.z, g.n });
        for (g.loot[0..g.n]) |k| try w.print(" {s}", .{item.tag(k)});
        if (g.gold > 0) try w.print(" g{d}", .{g.gold});
    }
    try w.writeByte('\n');
    // **A ROW IS WRITTEN ONLY WHEN IT SAYS SOMETHING** past rail 0, so a knight-only save is the same bytes it always was.
    try bits(w, "bosses", &d.bossDead[0]);
    for (d.bossDead[1..], 1..) |row, i| {
        var any = false;
        for (row) |x| any = any or x;
        if (!any) continue;
        var kb: [16]u8 = undefined;
        try bits(w, try std.fmt.bufPrint(&kb, "bosses{d}", .{i}), &row);
    }
    try bits(w, "seen", &d.seen);
    try bits(w, "seenmap", &d.seenMap);
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
            _ = try vec(&it);
            _ = try float(&it);
        } else if (std.mem.eql(u8, key, "souls:")) {
            d.souls = try int(u32, &it);
        } else if (std.mem.eql(u8, key, "gold:")) {
            d.gold = try int(u32, &it);
        } else if (std.mem.eql(u8, key, "tiers:")) {
            d.tiers = [_]u8{0} ** heromod.NARM;
            var ti: usize = 0;
            while (it.next()) |tok| : (ti += 1) {
                const v = std.fmt.parseInt(u8, tok, 10) catch return Error.BadField;
                if (ti < d.tiers.len) d.tiers[ti] = v;
            }
        } else if (std.mem.eql(u8, key, "hands:")) {
            d.arm = try tagged(heromod.Armament, &it);
            d.off = try tagged(heromod.Armament, &it);
            d.spell = try tagged(combat.Spell, &it);
            if (it.next()) |tok| d.armAlt = std.meta.stringToEnum(heromod.Armament, tok) orelse return Error.BadField;
            if (it.next()) |tok| d.offAlt = std.meta.stringToEnum(heromod.Armament, tok) orelse return Error.BadField;
        } else if (std.mem.eql(u8, key, "ready:")) {
            d.arrow = try tagged(combat.ArrowKind, &it);
            d.flask = try tagged(combat.FlaskKind, &it);
            if (it.next()) |tok| d.crimsonMax = std.fmt.parseInt(u8, tok, 10) catch return Error.BadField;
            if (it.next()) |tok| d.flaskTotal = std.fmt.parseInt(u8, tok, 10) catch return Error.BadField;
        } else if (std.mem.eql(u8, key, "quiver:")) {
            d.arrows = try int(u8, &it);
            d.fireArrows = try int(u8, &it);
        } else if (std.mem.eql(u8, key, "quick:")) {
            // A positional rack (`quick:`, `memory:`, `worn:`, `tiers:`) is read WHOLE and stored SHORT: a wider row is
            // a newer build's and its tail is dropped, a shorter one keeps the defaults, and a malformed token anywhere
            // in it is a bad file wherever it falls — including in the tail.
            d.quick = [_]?item.Kind{null} ** combat.QUICK_SLOTS;
            var i: usize = 0;
            while (it.next()) |tok| : (i += 1) {
                if (std.mem.eql(u8, tok, "-")) continue;
                const k = item.fromTag(tok) orelse {
                    if (!item.retired(tok)) return Error.BadField;
                    continue;
                };
                if (i < d.quick.len) d.quick[i] = k;
            }
        } else if (std.mem.eql(u8, key, "memory:")) {
            d.memory = [_]?combat.Spell{null} ** combat.MEM_SLOTS;
            var i: usize = 0;
            while (it.next()) |tok| : (i += 1) {
                if (std.mem.eql(u8, tok, "-")) continue;
                const sp = std.meta.stringToEnum(combat.Spell, tok) orelse return Error.BadField;
                // One of each (`Memory.put` MOVES): a doubled spell stalls `Memory.next` between its two slots.
                for (d.memory) |held| {
                    if (held == sp) return Error.BadField;
                }
                if (i < d.memory.len) d.memory[i] = sp;
            }
        } else if (std.mem.eql(u8, key, "quicksel:")) {
            d.quickSel = try int(usize, &it);
        } else if (std.mem.eql(u8, key, "worn:")) {
            d.worn = .{};
            var wi: usize = 0;
            while (it.next()) |tok| : (wi += 1) {
                if (std.mem.eql(u8, tok, "-")) continue;
                const k = item.fromTag(tok) orelse {
                    if (!item.retired(tok)) return Error.BadField;
                    continue;
                };
                const slot = item.wearSlot(k) orelse return Error.BadField;
                if (wi < NWEAR) d.worn.put(slot, k);
            }
        } else if (std.mem.eql(u8, key, "bag:")) {
            d.bag = [_]u16{0} ** item.NK;
            while (it.next()) |tok| {
                const k = item.fromTag(tok) orelse {
                    if (!item.retired(tok)) return Error.BadField;
                    _ = try int(u16, &it);
                    continue;
                };
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
        } else if (std.mem.eql(u8, key, "ground:")) {
            d.groundN = 0;
            while (it.peek() != null) {
                if (d.groundN >= d.ground.len) return Error.BadField;
                var g = Drop{ .at = try vec(&it) };
                g.n = try int(u8, &it);
                if (g.n > pickupmod.DROP_MAX) return Error.BadField;
                var j: usize = 0;
                var kept: u8 = 0;
                while (j < g.n) : (j += 1) {
                    const tok = it.next() orelse return Error.BadField;
                    const k = item.fromTag(tok) orelse {
                        if (!item.retired(tok)) return Error.BadField;
                        continue;
                    };
                    g.loot[kept] = k;
                    kept += 1;
                }
                g.n = kept;
                if (it.peek()) |tok| {
                    if (tok.len > 1 and tok[0] == 'g') {
                        g.gold = std.fmt.parseInt(u32, tok[1..], 10) catch return Error.BadField;
                        _ = it.next();
                    }
                }
                if (g.n == 0 and g.gold == 0) continue;
                d.ground[d.groundN] = g;
                d.groundN += 1;
            }
        } else if (std.mem.eql(u8, key, "bosses:")) {
            try readBits(&it, &d.bossDead[0]);
        } else if (std.mem.startsWith(u8, key, "bosses") and std.mem.endsWith(u8, key, ":")) {
            const n = std.fmt.parseInt(usize, key["bosses".len .. key.len - 1], 10) catch return Error.BadKey;
            if (n == 0 or n >= BOSS_RAILS) return Error.BadKey;
            try readBits(&it, &d.bossDead[n]);
        } else if (std.mem.eql(u8, key, "seen:")) {
            try readBits(&it, &d.seen);
        } else if (std.mem.eql(u8, key, "seenmap:")) {
            try readBits(&it, &d.seenMap);
        } else {
            return Error.BadKey;
        }
    }
    if (!sawVersion) return Error.BadVersion;
}

const Tok = std.mem.TokenIterator(u8, .any);

/// **NON-FINITE IS A BAD FIELD** (`worldfmt.finiteFloat`'s rule, and this parser is the other door into the same runtime). `parseFloat` accepts `nan` and `inf`, and a NaN through here is a number nothing downstream can refuse: a NaN `at:` clamps to the corner of the world and a NaN facing poses the whole rig off-screen.
fn float(it: *Tok) !f32 {
    return wf.finiteFloat(f32, it.next() orelse return Error.BadField) catch Error.BadField;
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

fn bits(w: anytype, key: []const u8, run: []const bool) !void {
    try w.print("{s}: ", .{key});
    for (run) |b| try w.writeByte(if (b) '1' else '0');
    try w.writeByte('\n');
}

fn readBits(it: *Tok, out: []bool) !void {
    @memset(out, false);
    const txt = it.next() orelse return;
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
            .float => wf.finiteFloat(T, tok) catch return Error.BadField,
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
    d.souls = 12345;
    d.gold = 6789;
    d.tiers[@intFromEnum(heromod.Armament.sword)] = 7;
    d.tiers[@intFromEnum(heromod.Armament.bow)] = 3;
    d.arm = .bow;
    d.off = .wand;
    d.armAlt = .sword;
    d.offAlt = .shield;
    d.spell = .roots;
    d.memory = .{ null, .roots, .levin };
    d.arrow = .fire;
    d.arrows = 3;
    d.fireArrows = 1;
    d.flask = .cerulean;
    d.crimsonMax = combat.FLASK_CRIMSON + 2;
    d.flaskTotal = combat.FLASK_TOTAL + 3;
    d.quick[0] = .crimson_flask;
    d.quick[3] = .mushroom_jerky;
    d.quickSel = 3;
    d.worn.put(.hand_club, .greatclub);
    d.worn.put(.hand_dagger, .fang_dirk);
    d.worn.put(.chest, .quilted_gambeson);
    d.worn.put(.ring2, .deft_signet);
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
    d.ground[0] = .{ .at = .{ .x = -12.5, .y = 0.75, .z = 4.25 }, .n = 1, .loot = .{ .kobold_fang, .kobold_fang }, .gold = 41 };
    d.ground[1] = .{ .at = .{ .x = 3.0, .y = 0.0, .z = -8.5 }, .n = 2, .loot = .{ .mushroom_jerky, .quilted_gambeson } };
    d.ground[2] = .{ .at = .{ .x = -30.25, .y = 1.5, .z = 19.0 }, .n = 0, .gold = 7 };
    d.groundN = 3;
    d.bossDead[0][0] = true;
    d.bossDead[2][1] = true;
    d.seen[@intFromEnum(item.Kind.mushroom_jerky)] = true;
    d.seen[item.NK - 1] = true;
    d.seenMap[0] = true;
    d.seenMap[mapart.SEEN_N + 5] = true;
    d.seenMap[mapart.SEEN_CELLS - 1] = true;
    return d;
}

test "THE ROUND TRIP IS ONLY WORTH WHAT `sample` FILLS — a field left at its default proves nothing" {
    // Three had already fallen off it (`crimsonMax`, `flaskTotal`, the explored chart), so the writer could have dropped any of them and the round-trip test would still come back green.
    const src = try wf.readForTest(testing.allocator, SRC, wf.SRC_CAP);
    defer testing.allocator.free(src);
    const head = std.mem.indexOf(u8, src, "fn sample() Data {").?;
    const tail = std.mem.indexOfPos(u8, src, head, "\n}\n").?;
    const body = src[head..tail];
    var missing: usize = 0;
    inline for (@typeInfo(Data).@"struct".fields) |f| {
        // `wf.assignsField`'s rule plus the two more this sample uses: a SLICE handed to `@memcpy`, and a METHOD that writes the field (`worn.put`).
        const filled = wf.assignsField(body, "d", f.name) or
            std.mem.indexOf(u8, body, "d." ++ f.name ++ "[0..") != null or
            std.mem.indexOf(u8, body, "d." ++ f.name ++ ".put(") != null;
        if (!filled) {
            std.debug.print("\n  `sample` never fills `Data.{s}` — the round trip cannot see it\n", .{f.name});
            missing += 1;
        }
    }
    try testing.expectEqual(@as(usize, 0), missing);
    std.debug.print("\n  save: all {d} of `Data`'s fields carried by the round-trip sample\n", .{@typeInfo(Data).@"struct".fields.len});
}

test "A FILE WITH NO RACK IN IT LOADS AS THE STARTING RACK, and a bad sorcery is refused rather than guessed" {
    var old = Data{};
    try parse("version: 1\nsouls: 44\nhands: sword wand rime bow shield\n", &old);
    try testing.expectEqual((combat.Memory{}).slots, old.memory);
    try testing.expectEqual(combat.Spell.rime, old.spell);

    var wrote = Data{};
    try parse("version: 1\nmemory: - levin bolt\n", &wrote);
    try testing.expectEqual(@as(?combat.Spell, null), wrote.memory[0]);
    try testing.expectEqual(combat.Spell.levin, wrote.memory[1].?);
    try testing.expectEqual(combat.Spell.bolt, wrote.memory[2].?);

    var bad = Data{};
    try testing.expectError(Error.BadField, parse("version: 1\nmemory: - fireball -\n", &bad));

    var wide = Data{};
    try parse("version: 1\nmemory: bolt levin rime siphon lance sunder roots\n", &wide);
    try testing.expectEqual(combat.Spell.bolt, wide.memory[0].?);

    // The tail past the rack is dropped, not skipped: a bad tag in it is still a bad file, the `tiers:` rule.
    var tail = Data{};
    try testing.expectError(Error.BadField, parse("version: 1\nmemory: bolt levin rime fireball\n", &tail));

    var buf: [NWEAR * 2 + 64]u8 = undefined;
    var w = std.io.fixedBufferStream(&buf);
    try w.writer().writeAll("version: 1\nworn:");
    for (0..NWEAR) |_| try w.writer().writeAll(" -");
    try w.writer().writeAll(" fireball\n");
    try testing.expectError(Error.BadField, parse(w.getWritten(), &tail));

    // A REAL KIND THAT GOES IN NO SOCKET IS THE SAME BAD FILE, inside the rack or past it.
    var sock = std.io.fixedBufferStream(&buf);
    try sock.writer().writeAll("version: 1\nworn:");
    for (0..NWEAR) |_| try sock.writer().writeAll(" -");
    try sock.writer().writeAll(" crimson_flask\n");
    try testing.expect(item.wearSlot(.crimson_flask) == null);
    try testing.expectError(Error.BadField, parse(sock.getWritten(), &tail));
    try testing.expectError(Error.BadField, parse("version: 1\nworn: crimson_flask\n", &tail));
}

fn expectSame(comptime T: type, comptime where: []const u8, a: T, b: T) !void {
    switch (@typeInfo(T)) {
        .float => testing.expectApproxEqAbs(a, b, 1e-3) catch |e| {
            std.debug.print("\n  {s}: {d} -> {d}\n", .{ where, a, b });
            return e;
        },
        .array => |arr| for (a, b) |x, y| try expectSame(arr.child, where, x, y),
        .@"struct" => |st| inline for (st.fields) |f| {
            try expectSame(f.type, where ++ "." ++ f.name, @field(a, f.name), @field(b, f.name));
        },
        else => testing.expectEqual(a, b) catch |e| {
            std.debug.print("\n  {s} did not survive the file\n", .{where});
            return e;
        },
    }
}

test "a save round-trips through its own text" {
    const d = sample();
    const back = try roundTrip(&d);
    inline for (@typeInfo(Data).@"struct".fields) |f| {
        if (comptime std.mem.eql(u8, f.name, "ground")) continue;
        try expectSame(f.type, f.name, @field(d, f.name), @field(back, f.name));
    }
    for (d.ground[0..d.groundN], back.ground[0..back.groundN]) |a, b| {
        try expectSame(rl.Vector3, "ground.at", a.at, b.at);
        try testing.expectEqual(a.n, b.n);
        try testing.expectEqual(a.gold, b.gold);
        try testing.expectEqualSlices(item.Kind, a.loot[0..a.n], b.loot[0..b.n]);
    }
}

test "the buffer holds the biggest save this build can write" {
    var d = sample();
    for (&d.bag) |*c| c.* = item.CAP;
    for (&d.quick) |*q| q.* = item.LONGEST_TAG;
    for (&d.counters) |*c| c.* = std.math.minInt(i32);
    for (&d.waitLeft) |*v| v.* = -99999.5;
    for (&d.actAt) |*v| v.* = 255;
    for (&d.deaths) |*v| v.* = std.math.maxInt(u32);
    for (&d.timers) |*v| v.* = -99999.5;
    for (&d.bossDead) |*row| @memset(row, true);
    d.groundN = d.ground.len;
    for (&d.ground) |*g| g.* = .{
        .at = .{ .x = -99999.5, .y = -99999.5, .z = -99999.5 },
        .n = pickupmod.DROP_MAX,
        .loot = [_]item.Kind{item.LONGEST_TAG} ** pickupmod.DROP_MAX,
        .gold = std.math.maxInt(u32),
    };
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

test "A RACK HOLDING ONE SPELL TWICE IS A BAD FILE — the ring walk would stall between the two" {
    var d = Data{};
    try testing.expectError(Error.BadField, parse("version: 1\nmemory: bolt bolt -\n", &d));
    try parse("version: 1\nmemory: bolt - levin\n", &d);
    try testing.expectEqual(@as(?combat.Spell, .levin), d.memory[2]);
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

test "A SHORT `tiers:` IS AN OLDER ARMAMENT LIST, A BAD ONE IS A BAD FILE" {
    var d = Data{};
    try parse("version: 1\ntiers: 3\n", &d);
    try testing.expectEqual(@as(u8, 3), d.tiers[0]);
    try testing.expectEqual(@as(u8, 0), d.tiers[heromod.NARM - 1]);
    try testing.expectError(Error.BadField, parse("version: 1\ntiers: 3 x 1\n", &d));

    // A LONGER ROW IS A NEWER `Armament`: the tail is dropped, and a bad token IN the tail is still a bad file.
    var buf: [heromod.NARM * 4 + 64]u8 = undefined;
    var w = std.io.fixedBufferStream(&buf);
    try w.writer().writeAll("version: 1\ntiers:");
    for (0..heromod.NARM) |_| try w.writer().writeAll(" 2");
    const rack = w.pos;
    try w.writer().writeAll(" 5\n");
    try parse(w.getWritten(), &d);
    try testing.expectEqual(@as(u8, 2), d.tiers[heromod.NARM - 1]);
    w.pos = rack;
    try w.writer().writeAll(" x\n");
    try testing.expectError(Error.BadField, parse(w.getWritten(), &d));
}

test "A NON-FINITE NUMBER IS REFUSED IN EVERY RUN, not just the scalar rows" {
    var d = Data{};
    try testing.expectError(Error.BadField, parse("version: 1\nat: nan 0 0 0\n", &d));
    try testing.expectError(Error.BadField, parse("version: 1\nhour: inf\n", &d));
    try testing.expectError(Error.BadField, parse("version: 1\ntimers: nan 0 0\n", &d));
    try testing.expectError(Error.BadField, parse("version: 1\nwaitleft: 1.0 -inf\n", &d));
    try parse("version: 1\ntimers: 1.5 0 0\n", &d);
    try testing.expectApproxEqAbs(@as(f32, 1.5), d.timers[0], 1e-6);
}

test "a bag tag this build does not know is a load error" {
    var d = Data{};
    try testing.expectError(Error.BadField, parse("version: 1\nbag: dragon_hoard 3\n", &d));
}

test "A RETIRED TAG IS SKIPPED, NOT REFUSED — the golden seeds in an older bag load as nothing and the rest of the row survives" {
    var d = Data{};
    try parse("version: 1\nbag: golden_seed 2 rune_arc 1\n", &d);
    try testing.expectEqual(@as(u16, 1), d.bag[@intFromEnum(item.Kind.rune_arc)]);
    try testing.expectEqual(@as(u16, 0), d.bag[@intFromEnum(item.Kind.empty_flask)]);
}

test "EVERY ROW THAT NAMES AN ITEM SKIPS A RETIRED TAG — the bar, the doll and a pile on the ground, not just the bag" {
    var d = Data{};
    try parse("version: 1\nquick: golden_seed rune_arc\n", &d);
    try testing.expect(d.quick[0] == null);
    try testing.expectEqual(item.Kind.rune_arc, d.quick[1].?);

    d = Data{};
    try parse("version: 1\nworn: golden_seed\n", &d);
    try testing.expect(d.worn.at(.helm) == null);

    d = Data{};
    try parse("version: 1\nground: 0 0 0 2 golden_seed rune_arc\n", &d);
    try testing.expectEqual(@as(usize, 1), d.groundN);
    try testing.expectEqual(@as(u8, 1), d.ground[0].n);
    try testing.expectEqual(item.Kind.rune_arc, d.ground[0].loot[0]);

    // A pile that was nothing but retired tags is not a pile at all.
    d = Data{};
    try parse("version: 1\nground: 0 0 0 1 golden_seed\n", &d);
    try testing.expectEqual(@as(usize, 0), d.groundN);
}

test "THE FLASK POOL SURVIVES THE FILE — a found flask is still his after a load, and a file from before the pool grew keeps the default" {
    var d = sample();
    d.flaskTotal = 5;
    d.crimsonMax = 4;
    const back = try roundTrip(&d);
    try testing.expectEqual(@as(u8, 5), back.flaskTotal);
    try testing.expectEqual(@as(u8, 4), back.crimsonMax);
    var old = Data{};
    try parse("version: 1\nready: plain crimson 2\n", &old);
    try testing.expectEqual(combat.FLASK_TOTAL, old.flaskTotal);
    try testing.expectEqual(@as(u8, 2), old.crimsonMax);
}

test "WHAT HE WAS WEARING SURVIVES THE FILE, a short line loads bare, and a MOVED socket still loads" {
    const back = try roundTrip(&sample());
    inline for (@typeInfo(item.Wear).@"enum".fields) |f| {
        const w: item.Wear = @enumFromInt(f.value);
        try testing.expectEqual(sample().worn.at(w), back.worn.at(w));
    }

    var short = Data{};
    short.worn.put(.ring2, .deft_signet);
    try parse("version: 1\nworn: - grave_warbow\n", &short);
    try testing.expectEqual(item.Kind.grave_warbow, short.worn.at(.hand_bow).?);
    try testing.expect(short.worn.at(.ring2) == null);
    try testing.expect(short.worn.at(.hand_club) == null);

    var moved = Data{};
    try parse("version: 1\nworn: fang_dirk - - quilted_gambeson\nsouls: 3558\n", &moved);
    try testing.expectEqual(item.Kind.fang_dirk, moved.worn.at(.hand_dagger).?);
    try testing.expect(moved.worn.at(.hand_sword) == null);
    try testing.expectEqual(item.Kind.quilted_gambeson, moved.worn.at(.chest).?);
    try testing.expectEqual(@as(u32, 3558), moved.souls);

    var wrong = Data{};
    try parse("version: 1\nworn: quilted_gambeson\n", &wrong);
    try testing.expectEqual(item.Kind.quilted_gambeson, wrong.worn.at(.chest).?);
    try testing.expectError(Error.BadField, parse("version: 1\nworn: dragon_plate\n", &wrong));
    try testing.expectError(Error.BadField, parse("version: 1\nworn: crimson_flask\n", &wrong));
}

const Live = struct {
    hero: heromod.Hero = undefined,
    bag: item.Bag = .{},
    tree: ptree.Tree = .{},
    souls: soulsmod.Souls = undefined,
    day: daynight.Clock = .{},
    trig: trigmod.Runtime = .{},
    chests: chestmod.Chests = undefined,
    pickups: pickupmod.Pickups = .{},
    bosses: BossBits = [_][wf.MAX_PER_KIND]bool{[_]bool{false} ** wf.MAX_PER_KIND} ** BOSS_RAILS,
    award: awardmod.Award = .{},
    seenMap: mapart.Seen = .{},

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
            .bosses = &self.bosses,
            .award = &self.award,
            .seenMap = &self.seenMap,
            .map = wf.START_MAP,
        };
    }
};

test "THE SLOT CARRIES EVERY FIELD IT NAMES — live game out, text, live game back in" {
    const N_CHESTS = 4;
    var a = Live.blank(N_CHESTS);
    a.hero.pos = .{ .x = -4.5, .y = 0.25, .z = 7.125 };
    a.hero.facing = 1.5;
    a.hero.souls.total = 4321;
    a.hero.gold.total = 987;
    a.hero.tiers[@intFromEnum(heromod.Armament.club)] = 10;
    a.hero.arm = .bell;
    a.hero.off = .wand;
    a.hero.offAlt = .shield; // the rack is four DISTINCT armaments (`hero.equip`), and `scatter` tidies one that is not
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
    a.bosses[0][1] = true; // …one of the knight's two is down
    a.bosses[2][0] = true; // …and one HALF of the duo behind the second gate, which rail 0 could never say
    a.seenMap.walked(.{ .x = 40, .y = 0, .z = -60 }, 280, {});

    const out = gather(a.slot());
    const back = try roundTrip(&out);

    var b = Live.blank(N_CHESTS);
    scatter(&back, b.slot());
    try testing.expectEqual(out, gather(b.slot()));

    try testing.expectEqual(@as(f32, 4321), b.hero.souls.shown);
    try testing.expectApproxEqAbs(b.hero.pos.x, b.hero.spawnPos.x, 1e-4);
    try testing.expectApproxEqAbs(b.hero.pos.z, b.hero.spawnPos.z, 1e-4);
    try testing.expectApproxEqAbs(b.hero.facing, b.hero.spawnFacing, 1e-4);
    try testing.expect(b.chests.list[2].swing == 1 and b.chests.list[0].swing == 0);
    try testing.expect(b.bosses[0][1] and !b.bosses[0][0]);
    try testing.expect(b.bosses[2][0]);
    try testing.expectEqual(a.seenMap.count(), b.seenMap.count());
    try testing.expect(b.seenMap.count() > 0);
    try testing.expectEqual(a.seenMap.cell, b.seenMap.cell);
    try testing.expectEqual(@as(i32, -1), b.seenMap.at);
}

test "A PURSE ON THE GROUND IS SAVED — `pickup.spawn` makes a glow with coin and no item, and the filter was `nloot`" {
    var a = Live.blank(0);
    a.pickups.reset(&.{});
    a.pickups.spawn(.{ .x = 5.5, .y = 0.25, .z = -2.0 }, .{ .x = 5.5, .y = 0.25, .z = -2.0 }, &.{}, 63);
    a.pickups.spawn(.{ .x = -9.0, .y = 0, .z = 3.5 }, .{ .x = -9.0, .y = 0, .z = 3.5 }, &.{.kobold_fang}, 18);

    const out = gather(a.slot());
    try testing.expectEqual(@as(usize, 2), out.groundN);
    try testing.expectEqual(@as(u32, 63), out.ground[0].gold);
    try testing.expectEqual(@as(u8, 0), out.ground[0].n);
    try testing.expectEqual(@as(u32, 18), out.ground[1].gold);

    const back = try roundTrip(&out);
    var b = Live.blank(0);
    b.pickups.reset(&.{});
    scatter(&back, b.slot());
    try testing.expectEqual(@as(usize, 2), b.pickups.droppedOnes().len);
    try testing.expectEqual(@as(u32, 63), b.pickups.droppedOnes()[0].gold);
    try testing.expectEqual(@as(u8, 0), b.pickups.droppedOnes()[0].nloot);
    try testing.expectEqual(@as(u32, 18), b.pickups.droppedOnes()[1].gold);
    try testing.expectEqual(item.Kind.kobold_fang, b.pickups.droppedOnes()[1].loot[0]);
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

    var c = Live.blank(2);
    var wrong = c.slot();
    wrong.map = wf.DIR ++ "/02_brood_arena" ++ wf.EXT;
    try testing.expect(!readFrom(tmp, wrong));
    try testing.expectEqual(@as(u32, 0), c.hero.souls.total);

    try testing.expect(!readFrom("save.no_such_file.dat", b.slot()));
}

test "A SAVE CARRIES ITS OWN WORLD — the map is readable without loading the run, and one written elsewhere is still a save" {
    const tmp = "save.test.map.dat";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    const ELSEWHERE = wf.DIR ++ "/test_elsewhere" ++ wf.EXT;

    var a = Live.blank(1);
    var s = a.slot();
    s.map = ELSEWHERE;
    try testing.expect(writeTo(tmp, s));

    const got = mapOfFile(tmp) orelse return error.TestUnexpectedResult;
    try testing.expect(got.is(ELSEWHERE));
    try testing.expect(!got.is(wf.START_MAP));
    try testing.expect(wf.namesAMap(got.name()));
    std.debug.print("\n  a slot names its own world: {s}\n", .{got.name()});

    try testing.expectEqual(@as(?MapName, null), mapOfFile("save.no_such_file.dat"));
}

test "AN UNREADABLE SLOT IS NOT A FREE ONE — offered for a new game it is overwritten, and nothing ever said it was there" {
    var sh = Shelf{};
    try testing.expectEqual(@as(?usize, 0), sh.firstFree());
    sh.unreadable[0] = true;
    try testing.expect(sh.holds(0));
    try testing.expect(!sh.any());
    try testing.expectEqual(@as(?usize, 1), sh.firstFree());
    sh.head[1] = .{ .level = 2, .souls = 1, .playtime = 1 };
    try testing.expect(sh.holds(1));
    sh.unreadable[2] = true;
    try testing.expect(sh.full());

    const tmp = "save.test.bad.dat";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = "version: 1\nhelmet: iron\n" });
    var d = Data{};
    try testing.expect(!parseFile(tmp, &d));
    try std.fs.cwd().access(tmp, .{});
}

test "A SLOT THE GAME REFUSED IS NOT A FREE ONE — the file reads fine and the RUN behind it is what would not open" {
    defer useDevShelf(false);
    useDevShelf(true);
    const i = SLOTS - 1;
    defer std.fs.cwd().deleteFile(path(i)) catch {};
    try std.fs.cwd().writeFile(.{ .sub_path = path(i), .data = "version: 1\nmap: " ++ wf.DIR ++ "/test_gone" ++ wf.EXT ++ "\n" });

    var sh = Shelf{};
    for (sh.head[0..i]) |*h| h.* = .{ .level = 1, .souls = 0, .playtime = 1 };
    sh.head[i] = peek(i);
    try testing.expect(sh.head[i] != null and sh.full());

    // `game.loadGame` refuses this one: the file parses, its `map:` names no world that will load.
    sh.refused(i);
    try testing.expectEqual(@as(?Head, null), sh.head[i]);
    try testing.expect(sh.unreadable[i] and sh.holds(i));
    try testing.expectEqual(@as(?usize, null), sh.firstFree());

    // …and once the file really is gone the same call hands the slot back.
    try std.fs.cwd().deleteFile(path(i));
    sh.refused(i);
    try testing.expect(!sh.holds(i));
    try testing.expectEqual(@as(?usize, i), sh.firstFree());
}

test "A SLOT IS WRITTEN BESIDE ITSELF AND RENAMED OVER — a refused save never takes the one it was replacing" {
    const tmp = "save.atomic.dat";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp ++ ".tmp") catch {};

    var a = Live.blank(0);
    a.hero.souls.total = 12;
    try testing.expect(writeTo(tmp, a.slot()));
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(tmp ++ ".tmp", .{}));

    var s = a.slot();
    s.map = "w/" ++ "x" ** MAP_CAP;
    try testing.expect(!writeTo(tmp, s));
    var b = Live.blank(0);
    try testing.expect(readFrom(tmp, b.slot()));
    try testing.expectEqual(@as(u32, 12), b.hero.souls.total);
}

test "the shelf answers what the boot screen asks it" {
    var sh = Shelf{};
    try testing.expect(!sh.any());
    try testing.expectEqual(@as(?usize, 0), sh.firstFree());

    sh.head[0] = .{ .level = 4, .souls = 90, .playtime = 12 };
    try testing.expect(sh.any());
    try testing.expectEqual(@as(?usize, 1), sh.firstFree());

    sh.head[2] = .{ .level = 1, .souls = 0, .playtime = 0 };
    try testing.expectEqual(@as(?usize, 1), sh.firstFree());

    sh.head[1] = .{ .level = 9, .souls = 5, .playtime = 3 };
    try testing.expectEqual(@as(?usize, null), sh.firstFree());
    try testing.expect(sh.full());

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
    try testing.expectEqual(@as(u32, 4), taken + 1);
    try testing.expectEqual(@as(u32, 2500), d.souls);
    try testing.expectApproxEqAbs(@as(f32, 3661), d.elapsed, 0.01);
}

test "a name too long to store is a refused save, not a truncated one" {
    const tmp = "save.long.dat";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    var a = Live.blank(0);
    var s = a.slot();
    s.map = "w/" ++ "x" ** MAP_CAP;
    try testing.expect(!writeTo(tmp, s));
    try testing.expectError(error.FileNotFound, std.fs.cwd().access(tmp, .{}));

    const fits = "w/" ++ "x" ** (MAP_CAP - 2);
    s.map = fits;
    try testing.expect(writeTo(tmp, s));
    var b = Live.blank(0);
    var back = b.slot();
    back.map = fits;
    try testing.expect(readFrom(tmp, back));
}

test "every slot owns a distinct pair of files" {
    for (0..SLOTS) |i| {
        for (0..SLOTS) |j| {
            if (i == j) continue;
            try testing.expect(!std.mem.eql(u8, path(i), path(j)));
            try testing.expect(!std.mem.eql(u8, shotPath(i), shotPath(j)));
        }
        try testing.expect(!std.mem.eql(u8, path(i), shotPath(i)));
    }
}

test "A DEV RUN CANNOT NAME A PLAYED FILE" {
    defer useDevShelf(false);
    useDevShelf(false);
    try testing.expectEqualStrings("save1.dat", path(0));
    try testing.expectEqualStrings("save1.png", shotPath(0));
    useDevShelf(true);
    try testing.expectEqualStrings("devsave1.dat", path(0));
    try testing.expectEqualStrings("devsave3.png", shotPath(SLOTS - 1));
    for (0..SLOTS) |i| {
        useDevShelf(true);
        const devDat = path(i);
        const devPng = shotPath(i);
        for (0..SLOTS) |j| {
            useDevShelf(false);
            try testing.expect(!std.mem.eql(u8, devDat, path(j)));
            try testing.expect(!std.mem.eql(u8, devPng, shotPath(j)));
        }
    }
}

test "an empty bag line clears the bag rather than leaving the last one" {
    var d = Data{};
    d.bag[0] = 9;
    try parse("version: 1\nbag:\n", &d);
    try testing.expectEqual(@as(u16, 0), d.bag[0]);
}

test "AN OLDER FILE'S `spawn:` ROW IS READ AND DROPPED, and the checkpoint is where the save was taken" {
    const older =
        "version: 1\n" ++
        "map: " ++ wf.START_MAP ++ "\n" ++
        "at: 4.250 0.305 4.550 -0.3700\n" ++
        "spawn: 0.000 4.000 4.000 3.1416\n" ++
        "souls: 1020\n";
    var d = Data{};
    try parse(older, &d);

    var l = Live.blank(1);
    scatter(&d, l.slot());
    try testing.expectApproxEqAbs(@as(f32, 4.250), l.hero.pos.x, 1e-3);
    try testing.expectApproxEqAbs(@as(f32, 4.250), l.hero.spawnPos.x, 1e-3);
    try testing.expectApproxEqAbs(@as(f32, 4.550), l.hero.spawnPos.z, 1e-3);
    try testing.expectApproxEqAbs(@as(f32, -0.37), l.hero.spawnFacing, 1e-4);
}

test "ARROWS ARE FOUND OR BOUGHT, NEVER GRANTED — a spent quiver survives the round trip" {
    var l = Live.blank(1);
    l.hero.quiver.arrows = 3;
    l.hero.quiver.fire = 1;
    l.hero.quiver.sel = .fire;
    var d = gather(l.slot());

    var buf: [CAP]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), &d);
    try testing.expect(fbs.getWritten().len < CAP);

    var back = Data{};
    try parse(fbs.getWritten(), &back);
    try testing.expectEqual(@as(u8, 3), back.arrows);
    try testing.expectEqual(@as(u8, 1), back.fireArrows);

    var b = Live.blank(1);
    scatter(&back, b.slot());
    std.debug.print("\n  quiver: saved 3/1, loaded {d}/{d}\n", .{ b.hero.quiver.arrows, b.hero.quiver.fire });
    try testing.expectEqual(@as(u8, 3), b.hero.quiver.arrows);
    try testing.expectEqual(@as(u8, 1), b.hero.quiver.fire);
    try testing.expectEqual(combat.ArrowKind.fire, b.hero.quiver.sel);
}

test "A SAVE WRITTEN BEFORE ARROWS WERE FINITE LOADS FULL, which is what it described" {
    var d = Data{};
    try parse("version: 1\nmap: " ++ wf.START_MAP ++ "\n", &d);
    try testing.expectEqual(combat.ARROWS_MAX, d.arrows);
    try testing.expectEqual(combat.FIRE_ARROWS_MAX, d.fireArrows);
}

test "THE WHEEL ONLY PAYS FOR THE SNAPSHOT — what a bonfire pick still costs the frame, against what rode the worker" {
    var l = Live.blank(4);
    var t = try std.time.Timer.start();
    const REPS = 200;
    var sink: u64 = 0;

    var i: usize = 0;
    t.reset();
    while (i < REPS) : (i += 1) {
        const d = gather(l.slot());
        sink +%= d.souls;
    }
    const gatherNs = t.read() / REPS;

    const d = gather(l.slot());
    var buf: [CAP]u8 = undefined;
    var written: usize = 0;
    i = 0;
    t.reset();
    while (i < REPS) : (i += 1) {
        var fbs = std.io.fixedBufferStream(&buf);
        try render(fbs.writer(), &d);
        written = fbs.getWritten().len;
        sink +%= written;
    }
    const renderNs = t.read() / REPS;

    var back = Data{};
    i = 0;
    t.reset();
    while (i < REPS) : (i += 1) {
        try parse(buf[0..written], &back);
    }
    const parseNs = t.read() / REPS;

    std.debug.print(
        "\n  save: gather {d:.1} us on the frame; render {d:.1} us + survey {d:.1} us ({d} slots) rode the worker, over {d} bytes\n",
        .{
            @as(f64, @floatFromInt(gatherNs)) / 1000.0,
            @as(f64, @floatFromInt(renderNs)) / 1000.0,
            @as(f64, @floatFromInt(parseNs * SLOTS)) / 1000.0,
            SLOTS,
            written,
        },
    );
    try testing.expect(sink != 0);
}
