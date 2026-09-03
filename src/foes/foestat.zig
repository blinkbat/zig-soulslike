const std = @import("std");
const wf = @import("../world/worldfmt.zig");

/// **WHAT A BODY IS GIVEN WHEN IT IS MADE** (`play/tune.zig`'s Foes sheet). Every creature's pools are authored
/// in its own file and half of them are folded into a struct's field default at comptime — `initFoe(HP_MAX, …)`
pub const N = @typeInfo(wf.FoeKind).@"enum".fields.len;

pub const Mult = struct {
    hp: f32 = 1,
    poise: f32 = 1,
    stance: f32 = 1,
    brk: f32 = 1,
};

/// `brk` is `combat.Vitals.breakShare` — the share of stance one flinch bills. Learned like the pools, so a
/// creature re-authored in code flows through a `tuning.cfg` that never named it.
pub const Pools = struct {
    hp: f32 = 0,
    poise: f32 = 0,
    stance: f32 = 0,
    brk: f32 = 0,
};

pub var mult: [N]Mult = [_]Mult{.{}} ** N;

var authored: [N]Pools = [_]Pools{.{}} ** N;

pub fn known(k: wf.FoeKind) bool {
    return authored[@intFromEnum(k)].hp > 0;
}

pub fn pools(k: wf.FoeKind) Pools {
    return authored[@intFromEnum(k)];
}

pub fn live(k: wf.FoeKind) Pools {
    const a = authored[@intFromEnum(k)];
    const m = mult[@intFromEnum(k)];
    return .{ .hp = a.hp * m.hp, .poise = a.poise * m.poise, .stance = a.stance * m.stance, .brk = a.brk * m.brk };
}

pub fn edited(k: wf.FoeKind) bool {
    const m = mult[@intFromEnum(k)];
    return m.hp != 1 or m.poise != 1 or m.stance != 1 or m.brk != 1;
}

pub fn arm(vit: anytype, k: wf.FoeKind) void {
    const i = @intFromEnum(k);
    if (vit.hpMax <= 0) return;
    authored[i] = .{ .hp = vit.hpMax, .poise = vit.poiseMax, .stance = vit.stanceMax, .brk = vit.breakShare };
    const m = mult[i];
    if (m.hp == 1 and m.poise == 1 and m.stance == 1 and m.brk == 1) return;
    vit.hpMax = authored[i].hp * m.hp;
    vit.hp = vit.hpMax;
    vit.poiseMax = authored[i].poise * m.poise;
    vit.poise = vit.poiseMax;
    vit.stanceMax = authored[i].stance * m.stance;
    vit.stance = vit.stanceMax;
    vit.breakShare = authored[i].brk * m.brk;
}

test "a multiplier of one leaves a body exactly as the code made it" {
    const combat = @import("../play/combat.zig");
    var v = combat.Vitals.initFoe(96, 14, 44);
    arm(&v, .fungal_deer);
    try std.testing.expectEqual(@as(f32, 96), v.hpMax);
    try std.testing.expect(known(.fungal_deer));
    try std.testing.expectEqual(@as(f32, 96), live(.fungal_deer).hp);
    try std.testing.expect(!edited(.fungal_deer));

    mult[@intFromEnum(wf.FoeKind.fungal_deer)].hp = 2.0;
    defer mult[@intFromEnum(wf.FoeKind.fungal_deer)] = .{};
    var w = combat.Vitals.initFoe(96, 14, 44);
    arm(&w, .fungal_deer);
    try std.testing.expectEqual(@as(f32, 192), w.hpMax);
    try std.testing.expectEqual(w.hpMax, w.hp);
    try std.testing.expectEqual(@as(f32, 14), w.poiseMax);
    try std.testing.expect(edited(.fungal_deer));
}
