const std = @import("std");
const wf = @import("../world/worldfmt.zig");

/// **WHAT A BODY IS GIVEN WHEN IT IS MADE** (`play/tune.zig`'s Foes sheet). Every creature's pools are authored
/// in its own file and half of them are folded into a struct's field default at comptime — `initFoe(HP_MAX, …)`
/// — so there is no address the bench could write to. This is the other end of that: one multiplier per kind,
/// laid over the pools at SPAWN by `foe.armStats`, which is the one door every group's reset goes through.
///
/// **THE AUTHORED NUMBER IS LEARNED, NOT COPIED.** The first body of a kind arrives carrying what the code
/// says; `armStats` takes the reading before it applies anything, so the bench can print a real HP beside the
/// dial without this file holding a second copy of thirty-seven creatures' stats to drift against.
pub const N = @typeInfo(wf.FoeKind).@"enum".fields.len;

pub const Mult = struct {
    hp: f32 = 1,
    poise: f32 = 1,
    stance: f32 = 1,
};

pub const Pools = struct {
    hp: f32 = 0,
    poise: f32 = 0,
    stance: f32 = 0,
};

pub var mult: [N]Mult = [_]Mult{.{}} ** N;

/// What the code gave the last fresh body of each kind, before the multipliers went on. Zero until one has
/// been made — a kind nowhere in the open map has never been asked for.
var authored: [N]Pools = [_]Pools{.{}} ** N;

pub fn known(k: wf.FoeKind) bool {
    return authored[@intFromEnum(k)].hp > 0;
}

pub fn pools(k: wf.FoeKind) Pools {
    return authored[@intFromEnum(k)];
}

/// The pools a body of this kind is actually made with — what the bench prints.
pub fn live(k: wf.FoeKind) Pools {
    const a = authored[@intFromEnum(k)];
    const m = mult[@intFromEnum(k)];
    return .{ .hp = a.hp * m.hp, .poise = a.poise * m.poise, .stance = a.stance * m.stance };
}

pub fn edited(k: wf.FoeKind) bool {
    const m = mult[@intFromEnum(k)];
    return m.hp != 1 or m.poise != 1 or m.stance != 1;
}

/// **ON A FRESH BODY ONLY.** Called out of the group resets, where the pools are still full — scaling a body
/// mid-fight would either heal it or kill it depending on which way the dial went.
pub fn arm(vit: anytype, k: wf.FoeKind) void {
    const i = @intFromEnum(k);
    if (vit.hpMax <= 0) return;
    authored[i] = .{ .hp = vit.hpMax, .poise = vit.poiseMax, .stance = vit.stanceMax };
    const m = mult[i];
    if (m.hp == 1 and m.poise == 1 and m.stance == 1) return;
    vit.hpMax = authored[i].hp * m.hp;
    vit.hp = vit.hpMax;
    vit.poiseMax = authored[i].poise * m.poise;
    vit.poise = vit.poiseMax;
    vit.stanceMax = authored[i].stance * m.stance;
    vit.stance = vit.stanceMax;
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
    // …and it arrives FULL, or a dial that doubles a pool leaves the body at half health.
    try std.testing.expectEqual(w.hpMax, w.hp);
    try std.testing.expectEqual(@as(f32, 14), w.poiseMax);
    try std.testing.expect(edited(.fungal_deer));
}
