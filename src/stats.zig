const std = @import("std");

// THE CHARACTER SHEET: seven attributes, and the curves that turn three of them into the bars.

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

/// Every attribute starts here, and 15 is not arbitrary: it is the level at which each curve below yields exactly the HP / FP / stamina the game was already tuned around (see the tests), so putting the bars behind attributes moved nothing.
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

/// WHAT IT DOES — and for the four nothing reads yet, that nothing reads it yet. An inert attribute the player cannot tell is inert is a lie on the character sheet, the same way inventing a sorcery for the HUD's empty slot would be.
pub fn governs(a: Attr) [:0]const u8 {
    return switch (a) {
        .vitality => "Governs HP.",
        .mind => "Governs FP.",
        .endurance => "Governs stamina.",
        .strength => "Skill with heavy weapons. None forged yet.",
        .dexterity => "Skill with light weapons. Nothing scales off it yet.",
        .intelligence => "Skill with magic. The wand's bolt is a flat number; nothing scales off this yet.",
        .luck => "Drops, and rare finds. Nothing reads it yet.",
    };
}

/// One leg of a curve: `per` a point, up to and including `upTo`.
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

// HP is deliberately shallow — 70 at the start, lowered from a flat 100 so a few solid blows kill (owner: raise the stakes). Vigor's caps are 40/60.
const HP_BASE: f32 = 28.0;
const HP_SEGS = [_]Seg{ .{ .upTo = 40, .per = 3.0 }, .{ .upTo = 60, .per = 1.6 }, .{ .upTo = MAX, .per = 0.6 } };

// FP buys CASTS now (`combat.SPELL_FP`, off the wand), so Mind is how many of them a grace is worth — the curve was written for the day sorcery landed and this is that day. Mind's caps are ~35/50/60.
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

    pub fn hp(self: *const Sheet) f32 {
        return hpFor(self.at(.vitality));
    }

    pub fn fp(self: *const Sheet) f32 {
        return fpFor(self.at(.mind));
    }

    pub fn stamina(self: *const Sheet) f32 {
        return staminaFor(self.at(.endurance));
    }

    /// LEVEL IS NOT STORED, IT IS COUNTED: every point spent past the starting sheet, plus one. ER works
    /// exactly this way, and storing it beside the points is how a sheet and its level drift apart.
    pub fn level(self: *const Sheet) u32 {
        var n: u32 = 1;
        for (self.pts) |p| n += @as(u32, p) -| START;
        return n;
    }

    /// WHAT THIS ATTRIBUTE IS BUYING RIGHT NOW, or null for the four nothing reads yet. THE one place the
    /// attribute→bar binding is written: the character sheet asked the same question with a switch of its
    /// own, so a fourth curve meant editing two files and forgetting the second showed a bare row. It is
    /// EXHAUSTIVE, so a new attribute is a compile error until it has said whether it feeds a bar.
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

test "every curve rises, and rises SLOWER past each softcap" {
    for ([_]*const fn (u8) f32{ &hpFor, &fpFor, &staminaFor }) |curve| {
        var prev = curve(1);
        var lastGain: f32 = std.math.floatMax(f32);
        var pts: u8 = 2;
        while (pts <= MAX) : (pts += 1) {
            const now = curve(pts);
            const gain = now - prev;
            try std.testing.expect(gain > 0);
            try std.testing.expect(gain <= lastGain + 1e-4); // never STEEPENS with investment
            prev = now;
            lastGain = gain;
        }
        try std.testing.expect(curve(MAX) > 1.5 * curve(1)); // …and a maxed attribute is still worth having
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
    try std.testing.expectEqual(START, s.at(.mind)); // …and moving one moves ONLY that one
}
