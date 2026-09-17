const std = @import("std");
const combat = @import("combat.zig");
const foe = @import("../foes/foe.zig");
const wf = @import("../world/worldfmt.zig");

pub const Soak = struct {
    /// WHOSE ROW THIS IS, written out so the table can be read (and reordered) without counting — the comptime walk below pins it against `wf.Liquid`'s own order, `drops.Row`'s rule.
    liquid: wf.Liquid,
    ail: ?combat.Ail = null,
    build: f32 = 0,
    dpsFrac: f32 = 0,
};

/// `sinceDose` and the delay is 1.1 s (`combat.POISON_DECAY_DELAY`), so `max/build` IS the seconds to break. Set against the cinder wake's burnt ground, which fills BURNING in 1.7 s: the fungal takes eight times that and the lava four.
pub const SOAK_BANK = [wf.Liquid.N]Soak{
    .{ .liquid = .water },
    .{ .liquid = .oil },
    .{ .liquid = .fungal, .ail = .poison, .build = 7.2 },
    .{ .liquid = .lava, .ail = .burning, .build = 14.3, .dpsFrac = 0.045 },
};

comptime {
    for (SOAK_BANK, 0..) |row, i| {
        const l: wf.Liquid = @enumFromInt(i);
        if (row.liquid != l) @compileError("liquid: the " ++ @tagName(row.liquid) ++ " row sits where " ++ @tagName(l) ++ " should be");
        if ((row.ail == null) != (row.build == 0)) @compileError("liquid: " ++ @tagName(l) ++ " names a status and a rate that disagree");
        if (row.ail == null and row.dpsFrac > 0) @compileError("liquid: " ++ @tagName(l) ++ " drips health and soaks nothing");
    }
}

/// The live four. `SOAK_BANK` above is the revert (`play/tune.zig`).
pub var SOAK: [wf.Liquid.N]Soak = SOAK_BANK;

/// Null for the two that are a look and a sound and nothing else.
pub fn soakOf(l: wf.Liquid) ?Soak {
    const row = SOAK[@intFromEnum(l)];
    return if (row.ail == null) null else row;
}

pub const Bill = struct { ail: combat.Ail, amt: f32, dmgFrac: f32 };

pub fn tick(soak: *foe.Soak, l: ?wf.Liquid, dt: f32) ?Bill {
    const row = if (l) |kind| soakOf(kind) else null;
    const r = row orelse {
        _ = soak.step(false, dt, 0);
        return null;
    };
    return .{ .ail = r.ail.?, .amt = soak.step(true, dt, r.build), .dmgFrac = r.dpsFrac * dt };
}

test "only the two that say so soak, and a crossing costs far less than a stand-in" {
    var lavaSecs: f32 = 0;
    for (SOAK, 0..) |row, i| {
        const l: wf.Liquid = @enumFromInt(i);
        const s = soakOf(l) orelse {
            try std.testing.expect(l == .water or l == .oil);
            try std.testing.expectEqual(l, row.liquid);
            continue;
        };
        const P = combat.ailRow(s.ail.?);
        const secs = P.max / s.build;
        const clip = s.build * foe.ENTRY_BOLUS / P.max;
        std.debug.print("\n  {s}: {s} breaks after {d:.1} s of standing in it; clipping the rim is {d:.0}% of the bar", .{ l.label(), P.name, secs, clip * 100.0 });
        try std.testing.expect(secs > 6.0);
        try std.testing.expect(clip < 0.06);
        if (l == .lava) lavaSecs = secs;
    }
    try std.testing.expect(lavaSecs < combat.ailRow(.poison).max / soakOf(.fungal).?.build);
    try std.testing.expect(soakOf(.lava).?.dpsFrac > 0);
    try std.testing.expect(soakOf(.fungal).?.dpsFrac == 0);
    std.debug.print("\n", .{});
}

test "stepping into lava bills the bolus, then the clock, and it stops at the bank" {
    var s = foe.Soak{};
    const dt: f32 = 1.0 / 60.0;
    const first = tick(&s, .lava, dt).?;
    const after = tick(&s, .lava, dt).?;
    try std.testing.expectApproxEqAbs(soakOf(.lava).?.build * foe.ENTRY_BOLUS, first.amt, 1e-4);
    try std.testing.expect(first.amt > after.amt * 10.0);
    try std.testing.expectEqual(combat.Ail.burning, after.ail);
    try std.testing.expect(after.dmgFrac > 0);
    try std.testing.expectEqual(@as(?Bill, null), tick(&s, .water, dt));
    try std.testing.expectEqual(@as(?Bill, null), tick(&s, null, dt));
    try std.testing.expect(tick(&s, .lava, dt).?.amt > after.amt * 10.0);
}
