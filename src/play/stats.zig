const std = @import("std");


pub const Attr = enum(u8) {
    vitality,
    mind,
    endurance,
    strength,
    dexterity,
    intelligence,
    luck,
};

pub const NA = @typeInfo(Attr).@"enum".fields.len;

pub const START: u8 = 15;
pub const MAX: u8 = 99;

pub fn displayName(a: Attr) [:0]const u8 {
    return switch (a) {
        .vitality => "Vitality",
        .mind => "Mind",
        .endurance => "Endurance",
        .strength => "Strength",
        .dexterity => "Dexterity",
        .intelligence => "Intelligence",
        .luck => "Luck",
    };
}

pub fn governs(a: Attr) [:0]const u8 {
    return switch (a) {
        .vitality => "Governs HP.",
        .mind => "Governs FP.",
        .endurance => "Governs stamina.",
        .strength => "Club damage, and half the sword's.",
        .dexterity => "Dirk and bow damage, and half the sword's.",
        .intelligence => "Sorcery damage.",
        .luck => "Rare drops.",
    };
}

pub fn inert(a: Attr) bool {
    _ = a;
    return false;
}

const Seg = struct { upTo: u8, per: f32 };

/// `base` at one point, then each leg's rate until its cap. The caps are ER's documented SOFT CAPS (`docs/ELDEN_RING.md` §2) — the shape is ER's, the scale is this game's.
fn yield(pts: u8, base: f32, segs: []const Seg) f32 {
    var out = base;
    var from: u8 = 1;
    for (segs) |s| {
        const to = @min(@max(pts, 1), s.upTo);
        if (to > from) out += @as(f32, @floatFromInt(to - from)) * s.per;
        from = s.upTo;
    }
    return out;
}

const HP_BASE: f32 = 28.0;
const HP_SEGS = [_]Seg{ .{ .upTo = 40, .per = 3.0 }, .{ .upTo = 60, .per = 1.6 }, .{ .upTo = MAX, .per = 0.6 } };

const FP_BASE: f32 = 32.0;
const FP_SEGS = [_]Seg{ .{ .upTo = 35, .per = 2.0 }, .{ .upTo = 60, .per = 1.0 }, .{ .upTo = MAX, .per = 0.4 } };

// The stamina pool IS ER's table (`docs/ELDEN_RING.md` §3): 1 → 80, 15 → 105, 30 → 130, 50 → 155, 99 → 170, softcapping at 15/30/50.
const STAM_BASE: f32 = 80.0;
const STAM_SEGS = [_]Seg{
    .{ .upTo = 15, .per = 25.0 / 14.0 },
    .{ .upTo = 30, .per = 25.0 / 15.0 },
    .{ .upTo = 50, .per = 25.0 / 20.0 },
    .{ .upTo = MAX, .per = 15.0 / 49.0 },
};

// ONE curve for strength, dexterity and intelligence — nothing about the three differs but which weapon asks. 1.0 at `START`: putting damage behind an attribute may not move the damage the game is tuned around. 0.72 at a single point, ~1.71x maxed. Caps are ER's weapon-scaling ones (§2), 20/55/80.
const SCALE_BASE: f32 = 0.72;
const SCALE_SEGS = [_]Seg{
    .{ .upTo = 20, .per = 0.020 },
    .{ .upTo = 55, .per = 0.012 },
    .{ .upTo = 80, .per = 0.006 },
    .{ .upTo = MAX, .per = 0.002 },
};

pub fn scaleFor(pts: u8) f32 {
    return yield(pts, SCALE_BASE, &SCALE_SEGS);
}

// It multiplies a RARE row's weight and NOTHING ELSE — scale every row and luck does nothing, the weights being relative. 1.0 at `START`. Under-invested takes nearly half the rare chance; maxed is about two and a half times.
const FIND_BASE: f32 = 0.60;
const FIND_SEGS = [_]Seg{
    // WRITTEN AS THE DIVISION IT IS (`STAM_SEGS`' idiom): the RATE is what carries 0.60 → 1.00 across the fourteen points from 1 to `START`, and a rounded decimal lands at 1.0004 — a curve that moved the drops it promised not to.
    .{ .upTo = 30, .per = 0.40 / 14.0 },
    .{ .upTo = 60, .per = 0.020 },
    .{ .upTo = MAX, .per = 0.0125 },
};

pub fn findFor(luck: u8) f32 {
    return yield(luck, FIND_BASE, &FIND_SEGS);
}

pub fn hpFor(vitality: u8) f32 {
    return yield(vitality, HP_BASE, &HP_SEGS);
}

pub fn fpFor(mind: u8) f32 {
    return yield(mind, FP_BASE, &FP_SEGS);
}

pub fn staminaFor(endurance: u8) f32 {
    return yield(endurance, STAM_BASE, &STAM_SEGS);
}

pub const Sheet = struct {
    pts: [NA]u8 = [_]u8{START} ** NA,

    pub fn at(self: *const Sheet, a: Attr) u8 {
        return self.pts[@intFromEnum(a)];
    }

    pub fn set(self: *Sheet, a: Attr, v: u8) void {
        self.pts[@intFromEnum(a)] = std.math.clamp(v, 1, MAX);
    }

    pub fn add(self: *Sheet, a: Attr, n: u8) void {
        self.set(a, self.at(a) +| n);
    }

    pub fn scale(self: *const Sheet, a: Attr) f32 {
        return scaleFor(self.at(a));
    }

    pub fn hp(self: *const Sheet) f32 {
        return hpFor(self.at(.vitality));
    }

    pub fn fp(self: *const Sheet) f32 {
        return fpFor(self.at(.mind));
    }

    pub fn stamina(self: *const Sheet) f32 {
        return staminaFor(self.at(.endurance));
    }

    pub fn finds(self: *const Sheet) f32 {
        return findFor(self.at(.luck));
    }

    pub fn level(self: *const Sheet) u32 {
        var n: u32 = 1;
        for (self.pts) |p| n += @as(u32, p) -| START;
        return n;
    }

    pub fn barFor(self: *const Sheet, a: Attr) ?f32 {
        return switch (a) {
            .vitality => self.hp(),
            .mind => self.fp(),
            .endurance => self.stamina(),
            .strength, .dexterity, .intelligence, .luck => null,
        };
    }
};

test "the STARTING sheet reproduces the tuned bars exactly, so nothing moved" {
    const s = Sheet{};
    try std.testing.expectApproxEqAbs(@as(f32, 70), s.hp(), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 60), s.fp(), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 105), s.stamina(), 1e-3);
    for (0..NA) |i| try std.testing.expectEqual(START, s.at(@enumFromInt(i)));
}

test "level is COUNTED off the points, and a fresh sheet is level 1" {
    var s = Sheet{};
    try std.testing.expectEqual(@as(u32, 1), s.level());
    s.set(.vitality, START + 5);
    s.set(.luck, START + 2);
    try std.testing.expectEqual(@as(u32, 8), s.level());
    // A sheet driven BELOW the start (nothing does, but `set` allows it) may not push the level under 1.
    s.set(.vitality, 1);
    s.set(.luck, 1);
    try std.testing.expectEqual(@as(u32, 1), s.level());
}

test "the stamina curve IS ER's table, softcaps and all" {
    for ([_][2]f32{ .{ 1, 80 }, .{ 15, 105 }, .{ 30, 130 }, .{ 50, 155 }, .{ 99, 170 } }) |p| {
        try std.testing.expectApproxEqAbs(p[1], staminaFor(@intFromFloat(p[0])), 1e-3);
    }
}

test "THE SKILL CURVE IS 1.0 AT THE START, so wiring damage to an attribute moved no damage" {
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), scaleFor(START), 1e-4);
    const s = Sheet{};
    for ([_]Attr{ .strength, .dexterity, .intelligence }) |a| {
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), s.scale(a), 1e-4);
    }
    try std.testing.expect(scaleFor(1) > 0.6 and scaleFor(1) < 0.8);
    try std.testing.expect(scaleFor(MAX) > 1.5 and scaleFor(MAX) < 2.0);
}

test "NOTHING ON THE SHEET IS DEAD ANY MORE, and the page says so either way" {
    var dead: usize = 0;
    for (0..NA) |i| {
        const a: Attr = @enumFromInt(i);
        const pleads = std.mem.indexOf(u8, governs(a), " yet") != null;
        try std.testing.expectEqual(inert(a), pleads);
        if (inert(a)) dead += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), dead);
    try std.testing.expect(!inert(.luck));
    try std.testing.expect(findFor(MAX) > findFor(START) and findFor(START) > findFor(1));
}

test "the FIND curve is 1.0 at the starting sheet, so adding drops moved none of them" {
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), findFor(START), 1e-4);
    try std.testing.expect(findFor(1) > 0.55 and findFor(1) < 0.65);
    try std.testing.expect(findFor(MAX) > 2.3 and findFor(MAX) < 2.7);
    std.debug.print(
        "\n  find curve: 1 -> {d:.2}x, {d} -> {d:.2}x, 60 -> {d:.2}x, {d} -> {d:.2}x\n",
        .{ findFor(1), START, findFor(START), findFor(60), MAX, findFor(MAX) },
    );
}

test "every curve rises, and rises SLOWER past each softcap" {
    for ([_]*const fn (u8) f32{ &hpFor, &fpFor, &staminaFor, &scaleFor }) |curve| {
        var prev = curve(1);
        var lastGain: f32 = std.math.floatMax(f32);
        var pts: u8 = 2;
        while (pts <= MAX) : (pts += 1) {
            const now = curve(pts);
            const gain = now - prev;
            try std.testing.expect(gain > 0);
            try std.testing.expect(gain <= lastGain + 1e-4);
            prev = now;
            lastGain = gain;
        }
        try std.testing.expect(curve(MAX) > 1.5 * curve(1));
    }
}

test "every attribute has a name and says what it governs, and no two share a name" {
    for (0..NA) |i| {
        const a: Attr = @enumFromInt(i);
        try std.testing.expect(displayName(a).len > 0);
        try std.testing.expect(governs(a).len > 0);
        for (i + 1..NA) |j| {
            try std.testing.expect(!std.mem.eql(u8, displayName(a), displayName(@enumFromInt(j))));
        }
    }
}

test "the three that feed a bar are exactly the three with a curve" {
    const s = Sheet{};
    try std.testing.expectApproxEqAbs(s.hp(), s.barFor(.vitality).?, 1e-4);
    try std.testing.expectApproxEqAbs(s.fp(), s.barFor(.mind).?, 1e-4);
    try std.testing.expectApproxEqAbs(s.stamina(), s.barFor(.endurance).?, 1e-4);
    var bars: usize = 0;
    for (0..NA) |i| {
        if (s.barFor(@enumFromInt(i)) != null) bars += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), bars);
}

test "a sheet clamps rather than wrapping, at both ends" {
    var s = Sheet{};
    s.set(.vitality, 0);
    try std.testing.expectEqual(@as(u8, 1), s.at(.vitality));
    s.set(.vitality, 200);
    try std.testing.expectEqual(MAX, s.at(.vitality));
    try std.testing.expectApproxEqAbs(hpFor(MAX), s.hp(), 1e-3);
    try std.testing.expectEqual(START, s.at(.mind));
}
