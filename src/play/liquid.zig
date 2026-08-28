const std = @import("std");
const combat = @import("combat.zig");
const foe = @import("../foes/foe.zig");
const wf = @import("../world/worldfmt.zig");

/// **WHAT STANDING IN ONE COSTS**, per `wf.Liquid`. `build` is meter per second on `ail`, billed the way a
/// cloud bills (`foe.Soak`: `ENTRY_BOLUS` seconds up front, then the clock), and `dpsFrac` is a drip on top of
/// it in the ail's own element. Water is `null` — it is the one liquid that is only water.
pub const Soak = struct {
    ail: combat.Ail,
    build: f32,
    /// Share of MAX HP a second, so a longer bar answers it the way every other clocked bill in the game is
    /// answered (`combat.AilRow.hpFrac`) rather than a flat number a levelled body outgrows.
    dpsFrac: f32 = 0,
};

/// **IT BUILDS SLOWLY OR IT IS JUST A WALL** (owner). Nothing here decays while you stand in it — a dose resets
/// `sinceDose` and the delay is 1.1 s (`combat.POISON_DECAY_DELAY`) — so `max/build` IS the seconds to break.
/// The bar it is set against is the burnt ground the cinder wake leaves, which fills BURNING in 1.7 s: a lake
/// is scenery you cross, not a creature's attack, so the fungal takes eight times that and the lava four.
pub const SOAK = [wf.Liquid.N]?Soak{
    null,
    null,
    .{ .ail = .poison, .build = 7.2 },
    .{ .ail = .burning, .build = 14.3, .dpsFrac = 0.045 },
};

pub fn soakOf(l: wf.Liquid) ?Soak {
    return SOAK[@intFromEnum(l)];
}

pub const Bill = struct { ail: combat.Ail, amt: f32, dmgFrac: f32 };

/// One frame's bill for a body standing in `l`, or nothing when it is out of the liquid or the liquid asks for
/// nothing. The `Soak` is the caller's, so a creature that grows one later pays the same entry bolus off the
/// same clock.
pub fn tick(soak: *foe.Soak, l: ?wf.Liquid, dt: f32) ?Bill {
    const row = if (l) |kind| soakOf(kind) else null;
    const r = row orelse {
        _ = soak.step(false, dt, 0);
        return null;
    };
    return .{ .ail = r.ail, .amt = soak.step(true, dt, r.build), .dmgFrac = r.dpsFrac * dt };
}

test "only the two that say so soak, and a crossing costs far less than a stand-in" {
    var lavaSecs: f32 = 0;
    for (SOAK, 0..) |row, i| {
        const l: wf.Liquid = @enumFromInt(i);
        const s = row orelse {
            try std.testing.expect(l == .water or l == .oil);
            continue;
        };
        const P = combat.ailRow(s.ail);
        // Nothing decays under a continuous dose, so the meter is filled at the bare rate.
        const secs = P.max / s.build;
        // …and the whole of a crossing that only clips the rim is the entry bolus.
        const clip = s.build * foe.ENTRY_BOLUS / P.max;
        std.debug.print("\n  {s}: {s} breaks after {d:.1} s of standing in it; clipping the rim is {d:.0}% of the bar", .{ l.label(), P.name, secs, clip * 100.0 });
        try std.testing.expect(secs > 6.0);
        try std.testing.expect(clip < 0.06);
        if (l == .lava) lavaSecs = secs;
    }
    // LAVA IS THE HARD ONE AND SAYS SO TWICE — it breaks first AND it is the only one that bites.
    try std.testing.expect(lavaSecs < combat.ailRow(.poison).max / SOAK[@intFromEnum(wf.Liquid.fungal)].?.build);
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
    // …and the bolus is owed again on the way back in, or clipping a rim twice costs less than clipping it once.
    try std.testing.expect(tick(&s, .lava, dt).?.amt > after.amt * 10.0);
}
