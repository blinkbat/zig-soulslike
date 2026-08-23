const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");


pub const Icon = enum {
    ground,
    locations,
    decor,
    props,
    interact,
    units,
    select,
    erase,
    zone,
    location,
    clearing,
    scatter,
    patch,
    single,
    stamp,
    row,
    ring,
    cluster,
    ivy,
    toad,
    archer,
    ogre,
    berserker,
    priest,
    slinger,
    brood_mother,
    broodling,
    brood_sac,
    shieldman,
    greatsword,
    shade,
    leechfly,
    rooted,
    shroom,
    bone_knight,
    delver,
    necromancer,
    florid_ravager,
    mushroom_mage,
    fen_lurker,
    spore_golem,
    bone_skitterer,
    ancient_priest,
    tolling_hollow,
    mourner,
    slumber_bloom,
    new,
    open,
    save,
    saveas,
    reload,
    undo,
    redo,
    eye,
    eyeOff,
};

pub fn draw(ic: Icon, cx: f32, cy: f32, size: f32, col: rl.Color) void {
    const s = size;
    const w = @max(1.4, s / 11.0);
    const d = dim(col);
    switch (ic) {
        .ground => {
            hline(cx, cy - s * 0.22, s * 0.72, w, col);
            hline(cx - s * 0.12, cy, s * 0.48, w, col);
            hline(cx + s * 0.22, cy, s * 0.20, w, d);
            hline(cx, cy + s * 0.22, s * 0.72, w, col);
        },
        .locations => {
            box(cx, cy, s * 0.78, s * 0.62, w, d);
            var i: i32 = -1;
            while (i <= 1) : (i += 1) {
                const x = cx + @as(f32, @floatFromInt(i)) * s * 0.24;
                vline(x, cy + s * 0.10, s * 0.26, w, col);
                dot(x, cy - s * 0.06, w * 1.1, col);
            }
        },
        .decor => {
            line(cx + s * 0.10, cy + s * 0.40, cx - s * 0.04, cy - s * 0.34, w, col);
            var i: i32 = 0;
            while (i < 2) : (i += 1) {
                const t = 0.30 + @as(f32, @floatFromInt(i)) * 0.36;
                const x = cx + s * (0.10 - 0.14 * t);
                const y = cy + s * (0.40 - 0.74 * t);
                const l = s * (0.34 - @as(f32, @floatFromInt(i)) * 0.09);
                line(x, y, x - l, y - l * 0.62, w, col);
                line(x, y, x + l, y - l * 0.62, w, col);
            }
            dot(cx - s * 0.04, cy - s * 0.34, w * 0.9, col);
        },
        .props => {
            hline(cx, cy - s * 0.34, s * 0.74, w * 1.3, col);
            hline(cx, cy - s * 0.25, s * 0.52, w, col);
            vline(cx - s * 0.10, cy + s * 0.02, s * 0.52, w, col);
            vline(cx + s * 0.10, cy + s * 0.02, s * 0.52, w, col);
            hline(cx, cy + s * 0.28, s * 0.52, w, col);
            hline(cx, cy + s * 0.38, s * 0.74, w * 1.3, col);
        },
        .interact => {
            box(cx, cy + s * 0.15, s * 0.72, s * 0.42, w, col);
            arc(cx, cy - s * 0.06, s * 0.36, 180, 360, w, col);
            hline(cx, cy - s * 0.06, s * 0.72, w, col);
            dot(cx, cy + s * 0.06, w * 1.2, col);
        },
        .units => {
            ring2(cx, cy - s * 0.20, s * 0.16, w, col);
            arc(cx, cy + s * 0.36, s * 0.30, 180, 360, w, col);
            vline(cx, cy + s * 0.14, s * 0.20, w, col);
        },

        .select => {
            const p = [_]rl.Vector2{
                .{ .x = cx - s * 0.20, .y = cy - s * 0.36 },
                .{ .x = cx - s * 0.20, .y = cy + s * 0.30 },
                .{ .x = cx - s * 0.03, .y = cy + s * 0.12 },
                .{ .x = cx + s * 0.10, .y = cy + s * 0.40 },
                .{ .x = cx + s * 0.24, .y = cy + s * 0.33 },
                .{ .x = cx + s * 0.11, .y = cy + s * 0.06 },
                .{ .x = cx + s * 0.30, .y = cy + s * 0.02 },
            };
            var i: usize = 0;
            while (i + 1 < p.len) : (i += 1) rl.drawLineEx(p[i], p[i + 1], w, col);
            rl.drawLineEx(p[p.len - 1], p[0], w, col);
        },
        .erase => {
            const a = rl.Vector2{ .x = cx - s * 0.30, .y = cy + s * 0.26 };
            const b = rl.Vector2{ .x = cx + s * 0.18, .y = cy - s * 0.30 };
            rl.drawLineEx(a, b, w * 3.4, d);
            rl.drawLineEx(.{ .x = a.x, .y = a.y }, .{ .x = cx - s * 0.06, .y = cy - s * 0.02 }, w * 3.4, col);
            hline(cx + s * 0.06, cy + s * 0.40, s * 0.62, w, d);
        },

        .zone => {
            box(cx, cy, s * 0.68, s * 0.56, w, col);
            dot(cx - s * 0.34, cy - s * 0.28, w * 1.5, col);
            dot(cx + s * 0.34, cy + s * 0.28, w * 1.5, col);
        },
        .location => {
            // A rectangle with its corner handles — StarEdit's own, and it is not the zone's dotted pair.
            box(cx, cy, s * 0.70, s * 0.54, w, col);
            dot(cx - s * 0.35, cy - s * 0.27, w * 1.6, col);
            dot(cx + s * 0.35, cy - s * 0.27, w * 1.6, col);
            dot(cx - s * 0.35, cy + s * 0.27, w * 1.6, col);
            dot(cx + s * 0.35, cy + s * 0.27, w * 1.6, col);
        },
        .clearing => {
            ring2(cx, cy, s * 0.34, w, col);
            dot(cx, cy, w * 1.2, col);
        },

        .scatter => {
            box(cx, cy, s * 0.74, s * 0.60, w, d);
            scatterDots(cx, cy, s * 0.28, s * 0.20, w, col, 5);
        },
        .patch => {
            ring2(cx, cy, s * 0.36, w, d);
            scatterDots(cx, cy, s * 0.19, s * 0.19, w, col, 5);
        },
        .single => {
            dot(cx, cy, w * 1.9, col);
            hline(cx, cy, s * 0.66, w * 0.8, d);
            vline(cx, cy, s * 0.66, w * 0.8, d);
        },
        .stamp => {
            vline(cx, cy - s * 0.16, s * 0.34, w, col);
            const tip = rl.Vector2{ .x = cx, .y = cy + s * 0.16 };
            rl.drawTriangle(
                .{ .x = tip.x - s * 0.14, .y = tip.y - s * 0.12 },
                .{ .x = tip.x, .y = tip.y + s * 0.10 },
                .{ .x = tip.x + s * 0.14, .y = tip.y - s * 0.12 },
                col,
            );
            hline(cx, cy + s * 0.36, s * 0.66, w, d);
        },
        .row => {
            hline(cx, cy, s * 0.80, w * 0.8, d);
            var i: i32 = -1;
            while (i <= 1) : (i += 1) dot(cx + @as(f32, @floatFromInt(i)) * s * 0.28, cy, w * 1.7, col);
        },
        .ring => {
            ring2(cx, cy, s * 0.34, w * 0.8, d);
            var i: i32 = 0;
            while (i < 7) : (i += 1) {
                if (i == 5) continue;
                const a = std.math.tau * @as(f32, @floatFromInt(i)) / 7.0;
                dot(cx + mathx.cosf(a) * s * 0.34, cy + mathx.sinf(a) * s * 0.34, w * 1.5, col);
            }
        },
        .cluster => {
            ring2(cx, cy, s * 0.40, w * 0.8, d);
            ring2(cx, cy, s * 0.16, w * 0.8, d);
            var i: i32 = 0;
            while (i < 6) : (i += 1) {
                const a = std.math.tau * @as(f32, @floatFromInt(i)) / 6.0 + 0.5;
                dot(cx + mathx.cosf(a) * s * 0.28, cy + mathx.sinf(a) * s * 0.28, w * 1.5, col);
            }
        },
        .ivy => {
            vline(cx - s * 0.26, cy, s * 0.84, w * 2.6, d);
            var i: i32 = 0;
            while (i < 3) : (i += 1) {
                const t = @as(f32, @floatFromInt(i)) / 2.0;
                const y = cy + s * 0.30 - t * s * 0.62;
                const side: f32 = if (@mod(i, 2) == 0) 1.0 else 0.45;
                const x = cx - s * 0.10 + s * 0.22 * side;
                line(cx - s * 0.14, y + s * 0.06, x, y, w, col);
                dot(x, y, w * 2.0, col);
            }
            vline(cx - s * 0.14, cy, s * 0.66, w * 0.9, col);
        },

        .toad => {
            arc(cx, cy + s * 0.22, s * 0.38, 180, 360, w, col);
            hline(cx, cy + s * 0.22, s * 0.72, w, col);
            dot(cx - s * 0.15, cy - s * 0.02, w * 1.3, col);
            dot(cx + s * 0.15, cy - s * 0.02, w * 1.3, col);
        },
        .archer => {
            arc(cx - s * 0.04, cy, s * 0.34, 300, 420, w, col);
            line(cx + s * 0.12, cy - s * 0.29, cx + s * 0.12, cy + s * 0.29, w * 0.7, col);
            line(cx - s * 0.26, cy, cx + s * 0.30, cy, w * 0.9, col);
        },
        .ogre => {
            arc(cx, cy + s * 0.28, s * 0.42, 180, 360, w, col);
            hline(cx, cy + s * 0.28, s * 0.80, w, col);
            dot(cx, cy - s * 0.04, w * 2.0, col);
        },
        .berserker => {
            // TWO axes, crossed — the whole character, and it cannot be mistaken for one weapon.
            for ([_]f32{ -1, 1 }) |side| {
                line(cx + side * s * 0.26, cy + s * 0.34, cx - side * s * 0.20, cy - s * 0.30, w, col);
                arc(cx - side * s * 0.20, cy - s * 0.30, s * 0.15, if (side < 0) 200 else 340, if (side < 0) 340 else 480, w, col);
            }
        },
        .priest => {
            line(cx - s * 0.06, cy + s * 0.40, cx - s * 0.06, cy - s * 0.20, w, col);
            arc(cx - s * 0.06, cy - s * 0.26, s * 0.13, 180, 360, w, col);
            dot(cx - s * 0.06, cy - s * 0.28, w * 1.9, col);
            line(cx + s * 0.14, cy + s * 0.06, cx + s * 0.14, cy + s * 0.26, w * 0.7, col);
        },
        .slinger => {
            line(cx - s * 0.24, cy - s * 0.32, cx - s * 0.05, cy + s * 0.26, w * 0.8, col);
            line(cx + s * 0.24, cy - s * 0.32, cx + s * 0.05, cy + s * 0.26, w * 0.8, col);
            arc(cx, cy + s * 0.26, s * 0.10, 0, 180, w, col);
            dot(cx, cy + s * 0.24, w * 1.7, col);
        },

        .brood_mother => {
            arc(cx, cy + s * 0.10, s * 0.26, 180, 360, w, col);
            hline(cx, cy + s * 0.10, s * 0.48, w, col);
            for ([_]f32{ -1, 1 }) |side| {
                for ([_]f32{ -0.16, 0.02, 0.20 }) |dy| {
                    line(cx + side * s * 0.20, cy + s * (0.06 + dy * 0.5), cx + side * s * 0.40, cy - s * 0.16 + s * dy, w * 0.7, col);
                    line(cx + side * s * 0.40, cy - s * 0.16 + s * dy, cx + side * s * 0.46, cy + s * 0.30, w * 0.7, col);
                }
                line(cx + side * s * 0.14, cy - s * 0.06, cx + side * s * 0.26, cy - s * 0.34, w, col);
            }
        },
        .broodling => {
            arc(cx, cy - s * 0.04, s * 0.17, 180, 360, w, col);
            hline(cx, cy - s * 0.04, s * 0.32, w, col);
            for ([_]f32{ -1, 1 }) |side| {
                for ([_]f32{ -0.06, 0.10 }) |dy| {
                    line(cx + side * s * 0.13, cy - s * 0.08 + s * dy, cx + side * s * 0.30, cy - s * 0.24 + s * dy, w * 0.7, col);
                }
            }
            hline(cx, cy + s * 0.32, s * 0.36, w * 0.6, d);
        },

        .brood_sac => {
            arc(cx, cy + s * 0.26, s * 0.34, 180, 360, w, col);
            hline(cx, cy + s * 0.26, s * 0.66, w, col);
            dot(cx - s * 0.12, cy + s * 0.10, w * 1.5, col);
            dot(cx + s * 0.11, cy + s * 0.04, w * 1.5, col);
            dot(cx - s * 0.01, cy + s * 0.16, w * 1.3, col);
            line(cx - s * 0.30, cy + s * 0.26, cx - s * 0.42, cy - s * 0.06, w * 0.6, d);
            line(cx + s * 0.30, cy + s * 0.26, cx + s * 0.42, cy - s * 0.06, w * 0.6, d);
        },

        .shieldman => {
            line(cx + s * 0.12, cy - s * 0.36, cx + s * 0.36, cy + s * 0.10, w * 0.8, d);
            dot(cx + s * 0.12, cy - s * 0.36, w * 2.1, d);
            arc(cx - s * 0.06, cy - s * 0.12, s * 0.24, 180, 360, w, col);
            line(cx - s * 0.30, cy - s * 0.12, cx - s * 0.06, cy + s * 0.42, w, col);
            line(cx + s * 0.18, cy - s * 0.12, cx - s * 0.06, cy + s * 0.42, w, col);
            dot(cx - s * 0.06, cy - s * 0.02, w * 1.6, col);
        },
        .greatsword => {
            vline(cx, cy - s * 0.06, s * 0.62, w, col);
            line(cx, cy - s * 0.44, cx - s * 0.09, cy - s * 0.26, w * 0.8, col);
            line(cx, cy - s * 0.44, cx + s * 0.09, cy - s * 0.26, w * 0.8, col);
            hline(cx, cy + s * 0.20, s * 0.56, w, col);
            vline(cx, cy + s * 0.32, s * 0.20, w * 1.6, d);
            dot(cx, cy + s * 0.43, w * 1.5, col);
        },

        .shade => {
            arc(cx, cy - s * 0.18, s * 0.20, 180, 360, w, col);
            line(cx - s * 0.20, cy - s * 0.18, cx - s * 0.30, cy + s * 0.18, w, col);
            line(cx + s * 0.20, cy - s * 0.18, cx + s * 0.30, cy + s * 0.18, w, col);
            dot(cx, cy - s * 0.17, w * 1.5, d);
            line(cx - s * 0.30, cy + s * 0.18, cx - s * 0.22, cy + s * 0.42, w * 0.8, d);
            line(cx - s * 0.10, cy + s * 0.22, cx - s * 0.04, cy + s * 0.36, w * 0.8, d);
            line(cx + s * 0.10, cy + s * 0.22, cx + s * 0.16, cy + s * 0.44, w * 0.8, d);
            line(cx + s * 0.30, cy + s * 0.18, cx + s * 0.24, cy + s * 0.34, w * 0.8, d);
        },

        // The shade's cowl BOWED and a great deal wider, with the head sunk into it: a mourner is a posture.
        .mourner => {
            arc(cx - s * 0.04, cy - s * 0.10, s * 0.26, 170, 350, w * 1.5, col);
            line(cx - s * 0.30, cy - s * 0.10, cx - s * 0.42, cy + s * 0.30, w * 1.2, col);
            line(cx + s * 0.22, cy - s * 0.10, cx + s * 0.36, cy + s * 0.30, w * 1.2, col);
            dot(cx - s * 0.10, cy - s * 0.02, w * 1.4, d);
            dot(cx + s * 0.06, cy - s * 0.04, w * 1.4, d);
            hline(cx - s * 0.04, cy + s * 0.30, s * 0.78, w, d);
            line(cx - s * 0.34, cy + s * 0.30, cx - s * 0.28, cy + s * 0.48, w * 0.8, d);
            line(cx - s * 0.08, cy + s * 0.32, cx - s * 0.02, cy + s * 0.46, w * 0.8, d);
            line(cx + s * 0.20, cy + s * 0.32, cx + s * 0.26, cy + s * 0.44, w * 0.8, d);
        },

        .rooted => {
            vline(cx, cy + s * 0.10, s * 0.74, w * 2.4, col);
            dot(cx - s * 0.09, cy - s * 0.06, w * 1.5, col);
            dot(cx + s * 0.09, cy - s * 0.06, w * 1.5, col);
            hline(cx, cy + s * 0.44, s * 0.44, w, d); // the roots it cannot leave
            line(cx - s * 0.02, cy - s * 0.18, cx - s * 0.26, cy - s * 0.30, w, col);
            line(cx - s * 0.26, cy - s * 0.30, cx - s * 0.38, cy - s * 0.14, w * 0.8, col);
            line(cx + s * 0.02, cy - s * 0.10, cx + s * 0.28, cy - s * 0.22, w, col);
            line(cx + s * 0.28, cy - s * 0.22, cx + s * 0.40, cy - s * 0.04, w * 0.8, col);
            line(cx, cy - s * 0.26, cx + s * 0.06, cy - s * 0.44, w * 0.8, d);
        },

        // The shroom's cap turned into a BAG: the whole difference between the two fungal creatures at a glance.
        .slumber_bloom => {
            arc(cx, cy - s * 0.16, s * 0.30, 180, 360, w * 2.2, col);
            hline(cx, cy - s * 0.16, s * 0.56, w * 1.4, col);
            vline(cx, cy + s * 0.16, s * 0.44, w * 1.8, col);
            line(cx - s * 0.26, cy - s * 0.14, cx - s * 0.34, cy + s * 0.12, w, d);
            line(cx + s * 0.26, cy - s * 0.14, cx + s * 0.34, cy + s * 0.10, w, d);
            line(cx - s * 0.10, cy - s * 0.12, cx - s * 0.14, cy + s * 0.16, w * 0.8, d);
            line(cx + s * 0.10, cy - s * 0.12, cx + s * 0.16, cy + s * 0.14, w * 0.8, d);
            dot(cx, cy - s * 0.42, w * 1.3, d);
            hline(cx, cy + s * 0.42, s * 0.34, w * 0.8, d);
        },

        .shroom => {
            arc(cx, cy - s * 0.06, s * 0.34, 180, 360, w * 1.6, col);
            hline(cx, cy - s * 0.06, s * 0.62, w * 1.2, col);
            vline(cx - s * 0.10, cy + s * 0.14, s * 0.30, w * 1.6, col);
            vline(cx + s * 0.10, cy + s * 0.14, s * 0.30, w * 1.6, col);
            hline(cx, cy + s * 0.12, s * 0.12, w * 1.3, d);
            dot(cx + s * 0.36, cy - s * 0.34, w * 1.2, d);
            dot(cx + s * 0.44, cy - s * 0.24, w * 0.9, d);
        },

        .leechfly => {
            arc(cx - s * 0.24, cy - s * 0.14, s * 0.22, 200, 340, w * 0.8, d);
            arc(cx + s * 0.24, cy - s * 0.14, s * 0.22, 200, 340, w * 0.8, d);
            dot(cx, cy - s * 0.02, w * 2.6, col);
            line(cx, cy + s * 0.04, cx - s * 0.06, cy + s * 0.30, w * 1.4, col);
            dot(cx - s * 0.07, cy + s * 0.33, w * 1.1, d);
            dot(cx + s * 0.02, cy - s * 0.20, w * 1.8, col);
            dot(cx - s * 0.06, cy - s * 0.24, w * 1.2, col);
            dot(cx + s * 0.09, cy - s * 0.24, w * 1.2, col);
            line(cx + s * 0.02, cy - s * 0.16, cx + s * 0.12, cy + s * 0.16, w * 0.8, col);
        },

        .bone_knight => {
            box(cx - s * 0.06, cy + s * 0.06, s * 0.50, s * 0.66, w * 1.6, col);
            hline(cx - s * 0.06, cy + s * 0.06, s * 0.44, w, d);
            dot(cx - s * 0.06, cy - s * 0.10, w * 1.8, d);
            arc(cx + s * 0.10, cy - s * 0.28, s * 0.16, 180, 360, w * 1.4, col);
            hline(cx + s * 0.10, cy - s * 0.26, s * 0.24, w * 1.1, d);
            line(cx + s * 0.34, cy - s * 0.12, cx + s * 0.34, cy + s * 0.40, w, col);
            hline(cx + s * 0.34, cy + s * 0.02, s * 0.16, w * 0.8, d);
        },

        .delver => {
            hline(cx, cy - s * 0.06, s * 0.80, w * 1.1, d);
            arc(cx, cy - s * 0.06, s * 0.32, 180, 360, w * 1.6, col);
            line(cx - s * 0.16, cy - s * 0.14, cx - s * 0.30, cy - s * 0.42, w * 1.2, col);
            line(cx + s * 0.04, cy - s * 0.20, cx + s * 0.06, cy - s * 0.50, w * 1.2, col);
            line(cx + s * 0.22, cy - s * 0.14, cx + s * 0.34, cy - s * 0.38, w * 1.2, col);
            dot(cx - s * 0.20, cy + s * 0.18, w * 1.3, d);
            dot(cx + s * 0.24, cy + s * 0.24, w * 1.1, d);
            dot(cx + s * 0.02, cy + s * 0.32, w * 1.2, d);
        },

        .necromancer => {
            arc(cx - s * 0.08, cy - s * 0.34, s * 0.15, 180, 360, w * 1.4, col);
            hline(cx - s * 0.08, cy - s * 0.32, s * 0.20, w, d);
            line(cx - s * 0.20, cy - s * 0.20, cx - s * 0.28, cy + s * 0.30, w * 1.3, col);
            line(cx + s * 0.04, cy - s * 0.20, cx + s * 0.12, cy + s * 0.30, w * 1.3, col);
            hline(cx - s * 0.08, cy + s * 0.30, s * 0.44, w * 1.1, col);
            line(cx + s * 0.28, cy - s * 0.44, cx + s * 0.22, cy - s * 0.04, w * 1.2, col);
            line(cx + s * 0.22, cy - s * 0.04, cx + s * 0.30, cy + s * 0.34, w * 1.2, col);
            dot(cx + s * 0.28, cy - s * 0.46, w * 1.6, col);
            dot(cx - s * 0.30, cy + s * 0.42, w * 1.1, d);
            dot(cx + s * 0.02, cy + s * 0.44, w * 1.1, d);
        },

        .florid_ravager => {
            hline(cx - s * 0.30, cy + s * 0.04, s * 0.40, w * 1.4, col);
            line(cx - s * 0.28, cy + s * 0.04, cx - s * 0.34, cy + s * 0.36, w * 1.1, col);
            line(cx - s * 0.14, cy + s * 0.04, cx - s * 0.10, cy + s * 0.36, w * 1.1, col);
            line(cx + s * 0.06, cy + s * 0.06, cx + s * 0.02, cy + s * 0.36, w * 1.1, col);
            line(cx - s * 0.32, cy + s * 0.02, cx - s * 0.44, cy - s * 0.14, w * 1.0, d);
            line(cx + s * 0.08, cy + s * 0.02, cx + s * 0.16, cy - s * 0.18, w * 1.2, col);
            dot(cx + s * 0.19, cy - s * 0.24, w * 1.8, d);
            var k: u32 = 0;
            while (k < 6) : (k += 1) {
                const a = @as(f32, @floatFromInt(k)) / 6.0 * std.math.tau;
                const bx = cx + s * 0.19 + @cos(a) * s * 0.10;
                const by = cy - s * 0.24 + @sin(a) * s * 0.10;
                line(cx + s * 0.19, cy - s * 0.24, bx, by, w * 1.1, col);
                dot(bx, by, w * 1.1, col);
            }
        },

        .spore_golem => {
            // A brim wider than the whole glyph over a block of a body: the silhouette IS the read.
            hline(cx - s * 0.46, cy - s * 0.16, s * 0.92, w * 2.2, col);
            line(cx - s * 0.40, cy - s * 0.16, cx - s * 0.14, cy - s * 0.44, w * 1.2, col);
            line(cx + s * 0.40, cy - s * 0.16, cx + s * 0.14, cy - s * 0.44, w * 1.2, col);
            hline(cx - s * 0.16, cy - s * 0.44, s * 0.32, w * 1.2, col);
            hline(cx - s * 0.26, cy - s * 0.02, s * 0.52, w * 1.4, d);
            line(cx - s * 0.26, cy - s * 0.02, cx - s * 0.30, cy + s * 0.34, w * 1.8, col);
            line(cx + s * 0.26, cy - s * 0.02, cx + s * 0.30, cy + s * 0.34, w * 1.8, col);
            hline(cx - s * 0.30, cy + s * 0.34, s * 0.60, w * 1.6, col);
            hline(cx - s * 0.22, cy + s * 0.46, s * 0.44, w * 1.4, col);
        },
        .mushroom_mage => {
            hline(cx - s * 0.34, cy - s * 0.14, s * 0.68, w * 1.6, col);
            line(cx - s * 0.30, cy - s * 0.14, cx - s * 0.06, cy - s * 0.40, w * 1.1, col);
            line(cx + s * 0.30, cy - s * 0.14, cx + s * 0.06, cy - s * 0.40, w * 1.1, col);
            hline(cx - s * 0.10, cy - s * 0.40, s * 0.20, w * 1.1, col);
            dot(cx, cy - s * 0.04, w * 1.3, d);
            line(cx - s * 0.13, cy - s * 0.10, cx - s * 0.21, cy + s * 0.40, w * 1.2, col);
            line(cx + s * 0.13, cy - s * 0.10, cx + s * 0.21, cy + s * 0.40, w * 1.2, col);
            hline(cx - s * 0.21, cy + s * 0.40, s * 0.42, w * 1.2, col);
            dot(cx + s * 0.26, cy + s * 0.02, w * 1.1, col);
            dot(cx + s * 0.38, cy - s * 0.16, w * 1.3, col);
            dot(cx + s * 0.46, cy + s * 0.06, w * 1.6, col);
        },

        .fen_lurker => {
            hline(cx - s * 0.40, cy + s * 0.10, s * 0.80, w * 1.5, col);
            hline(cx - s * 0.36, cy + s * 0.22, s * 0.18, w * 1.0, d);
            hline(cx + s * 0.14, cy + s * 0.22, s * 0.22, w * 1.0, d);
            line(cx - s * 0.10, cy + s * 0.10, cx + s * 0.04, cy - s * 0.10, w * 1.4, col);
            line(cx + s * 0.04, cy - s * 0.10, cx - s * 0.04, cy - s * 0.26, w * 1.3, col);
            line(cx - s * 0.04, cy - s * 0.26, cx + s * 0.10, cy - s * 0.36, w * 1.2, col);
            hline(cx + s * 0.04, cy - s * 0.38, s * 0.30, w * 1.8, col);
            dot(cx + s * 0.30, cy - s * 0.34, w * 1.2, col);
            dot(cx + s * 0.12, cy - s * 0.42, w * 1.0, d);
        },

        // A CAGE ON LEGS WITH A BLADE OVER IT — three legs a side now, and the goofy eye on the stalk.
        .bone_skitterer => {
            hline(cx - s * 0.30, cy + s * 0.06, s * 0.60, w * 1.5, col);
            var r: u32 = 0;
            while (r < 3) : (r += 1) {
                const x = cx - s * 0.24 + s * 0.24 * @as(f32, @floatFromInt(r));
                line(x, cy + s * 0.06, x - s * 0.14, cy + s * 0.32, w * 1.1, col);
                line(x, cy + s * 0.06, x + s * 0.14, cy + s * 0.32, w * 1.1, d);
                dot(x - s * 0.14, cy + s * 0.32, w * 0.9, col);
            }
            line(cx - s * 0.28, cy + s * 0.04, cx - s * 0.34, cy - s * 0.20, w * 1.4, col);
            line(cx - s * 0.34, cy - s * 0.20, cx - s * 0.10, cy - s * 0.40, w * 1.4, col);
            line(cx - s * 0.10, cy - s * 0.40, cx + s * 0.24, cy - s * 0.34, w * 1.4, col);
            dot(cx + s * 0.28, cy - s * 0.34, w * 2.4, col);
            dot(cx + s * 0.30, cy - s * 0.34, w * 1.1, d);
        },
        // A LONG MUZZLE AND TWO TALL EARS over a staff — the jackal head is the whole read.
        .ancient_priest => {
            line(cx - s * 0.16, cy - s * 0.14, cx - s * 0.24, cy - s * 0.44, w * 1.2, col);
            line(cx + s * 0.04, cy - s * 0.14, cx + s * 0.10, cy - s * 0.46, w * 1.2, col);
            box(cx - s * 0.06, cy - s * 0.10, s * 0.28, s * 0.18, w * 1.2, col);
            hline(cx + s * 0.06, cy - s * 0.06, s * 0.30, w * 1.3, col);
            dot(cx + s * 0.22, cy - s * 0.06, w * 1.0, d);
            vline(cx - s * 0.02, cy + s * 0.24, s * 0.40, w * 1.4, col);
            vline(cx + s * 0.34, cy + s * 0.02, s * 0.86, w * 1.2, col);
            arc(cx + s * 0.34, cy - s * 0.40, s * 0.13, 200.0, 340.0, w * 1.3, col);
        },
        // A BELL ON A HUNCHED BACK, and the bell is bigger than the head.
        .tolling_hollow => {
            arc(cx - s * 0.10, cy - s * 0.30, s * 0.10, 200.0, 340.0, w * 1.2, col);
            line(cx - s * 0.20, cy - s * 0.26, cx - s * 0.26, cy + s * 0.10, w * 1.6, col);
            line(cx - s * 0.02, cy - s * 0.24, cx - s * 0.06, cy + s * 0.10, w * 1.6, col);
            vline(cx - s * 0.26, cy + s * 0.30, s * 0.38, w * 1.5, col);
            vline(cx - s * 0.06, cy + s * 0.30, s * 0.38, w * 1.5, col);
            arc(cx + s * 0.22, cy + s * 0.02, s * 0.22, 180.0, 360.0, w * 1.5, col);
            vline(cx + s * 0.00, cy + s * 0.10, s * 0.16, w * 1.4, col);
            vline(cx + s * 0.44, cy + s * 0.10, s * 0.16, w * 1.4, col);
            hline(cx + s * 0.22, cy + s * 0.18, s * 0.48, w * 1.8, col);
            dot(cx + s * 0.22, cy + s * 0.10, w * 1.4, d);
        },

        .new => {
            page(cx, cy, s, w, col);
        },
        .open => {
            box(cx, cy - s * 0.02, s * 0.66, s * 0.44, w, d);
            hline(cx - s * 0.16, cy - s * 0.30, s * 0.32, w, col);
            rl.drawLineEx(.{ .x = cx - s * 0.33, .y = cy + s * 0.20 }, .{ .x = cx - s * 0.20, .y = cy + s * 0.36 }, w, col);
            rl.drawLineEx(.{ .x = cx - s * 0.20, .y = cy + s * 0.36 }, .{ .x = cx + s * 0.40, .y = cy + s * 0.36 }, w, col);
            rl.drawLineEx(.{ .x = cx + s * 0.40, .y = cy + s * 0.36 }, .{ .x = cx + s * 0.33, .y = cy + s * 0.20 }, w, col);
        },
        .save => {
            disk(cx, cy, s, w, col, d);
        },
        .saveas => {
            disk(cx - s * 0.06, cy + s * 0.04, s * 0.86, w, col, d);
            rl.drawLineEx(.{ .x = cx + s * 0.10, .y = cy - s * 0.12 }, .{ .x = cx + s * 0.40, .y = cy - s * 0.42 }, w * 1.4, col);
            dot(cx + s * 0.42, cy - s * 0.44, w * 1.1, col);
        },
        .reload => {
            arc(cx, cy, s * 0.32, 40, 330, w, col);
            arrowHead(cx + mathx.cosf(mathx.radians(40)) * s * 0.32, cy + mathx.sinf(mathx.radians(40)) * s * 0.32, s * 0.17, -60, col);
        },
        .undo => {
            arc(cx, cy + s * 0.06, s * 0.30, 180, 360, w, col);
            vline(cx - s * 0.30, cy + s * 0.18, s * 0.24, w, col);
            arrowHead(cx - s * 0.30, cy + s * 0.30, s * 0.17, 90, col);
        },
        .redo => {
            arc(cx, cy + s * 0.06, s * 0.30, 180, 360, w, col);
            vline(cx + s * 0.30, cy + s * 0.18, s * 0.24, w, col);
            arrowHead(cx + s * 0.30, cy + s * 0.30, s * 0.17, 90, col);
        },
        // TWO ARCS AND A PUPIL, and the lid is the SAME shape mirrored — an eye drawn as a circle in a box reads as a target at this size. `eyeOff` keeps the whole open eye and strikes it, rather than drawing a closed lid.
        .eye => eyeInto(cx, cy, s, w, col, false),
        .eyeOff => eyeInto(cx, cy, s, w, col, true),
    }
}

/// **A LENS AND A SOLID PUPIL, AND THAT IS ALL IT CAN AFFORD** — the smallest glyph in the set, about a dozen pixels, where arcs round a ring round a dot came out as one grey blob.
fn eyeInto(cx: f32, cy: f32, s: f32, w: f32, col: rl.Color, struck: bool) void {
    const body = if (struck) dim(col) else col;
    arc(cx, cy + s * 0.30, s * 0.46, 214, 326, w, body);
    arc(cx, cy - s * 0.30, s * 0.46, 34, 146, w, body);
    if (struck) {
        // The whole open eye stays under the stroke: shut and open have to be one glance apart on a strip of six, and a closed lid drawn as a single line is indistinguishable from a dash.
        line(cx - s * 0.40, cy + s * 0.34, cx + s * 0.40, cy - s * 0.34, w * 1.3, col);
    } else {
        dot(cx, cy, @max(w * 1.05, s * 0.15), col);
    }
}


fn dim(c: rl.Color) rl.Color {
    return rl.Color.init(c.r, c.g, c.b, @intCast(@as(u16, c.a) * 42 / 100));
}

fn line(x0: f32, y0: f32, x1: f32, y1: f32, w: f32, c: rl.Color) void {
    rl.drawLineEx(.{ .x = x0, .y = y0 }, .{ .x = x1, .y = y1 }, w, c);
}
fn hline(cx: f32, cy: f32, len: f32, w: f32, c: rl.Color) void {
    line(cx - len * 0.5, cy, cx + len * 0.5, cy, w, c);
}
fn vline(cx: f32, cy: f32, len: f32, w: f32, c: rl.Color) void {
    line(cx, cy - len * 0.5, cx, cy + len * 0.5, w, c);
}
fn dot(cx: f32, cy: f32, r: f32, c: rl.Color) void {
    rl.drawCircleV(.{ .x = cx, .y = cy }, r, c);
}
fn box(cx: f32, cy: f32, bw: f32, bh: f32, w: f32, c: rl.Color) void {
    rl.drawRectangleLinesEx(.{ .x = cx - bw * 0.5, .y = cy - bh * 0.5, .width = bw, .height = bh }, w, c);
}
fn ring2(cx: f32, cy: f32, r: f32, w: f32, c: rl.Color) void {
    arc(cx, cy, r, 0, 360, w, c);
}
fn arc(cx: f32, cy: f32, r: f32, a0: f32, a1: f32, w: f32, c: rl.Color) void {
    const segs: i32 = @intFromFloat(@max(6.0, @abs(a1 - a0) / 18.0));
    var i: i32 = 0;
    while (i < segs) : (i += 1) {
        const t0 = mathx.radians(a0 + (a1 - a0) * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segs)));
        const t1 = mathx.radians(a0 + (a1 - a0) * @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(segs)));
        line(cx + mathx.cosf(t0) * r, cy + mathx.sinf(t0) * r, cx + mathx.cosf(t1) * r, cy + mathx.sinf(t1) * r, w, c);
    }
}
fn arrowHead(cx: f32, cy: f32, r: f32, dirDeg: f32, c: rl.Color) void {
    const a = mathx.radians(dirDeg);
    const tip = rl.Vector2{ .x = cx + mathx.cosf(a) * r, .y = cy + mathx.sinf(a) * r };
    const l = rl.Vector2{ .x = cx + mathx.cosf(a + 2.5) * r, .y = cy + mathx.sinf(a + 2.5) * r };
    const rr = rl.Vector2{ .x = cx + mathx.cosf(a - 2.5) * r, .y = cy + mathx.sinf(a - 2.5) * r };
    rl.drawTriangle(tip, l, rr, c);
}
fn scatterDots(cx: f32, cy: f32, rx: f32, ry: f32, w: f32, c: rl.Color, n: u32) void {
    var rng = mathx.Rng.init(0xC0FFEE);
    var i: u32 = 0;
    while (i < n) : (i += 1) dot(cx + rng.signed() * rx, cy + rng.signed() * ry, w * 1.25, c);
}
fn page(cx: f32, cy: f32, s: f32, w: f32, c: rl.Color) void {
    const x0 = cx - s * 0.26;
    const x1 = cx + s * 0.26;
    const y0 = cy - s * 0.38;
    const y1 = cy + s * 0.38;
    const fold = s * 0.20;
    line(x0, y0, x1 - fold, y0, w, c);
    line(x1 - fold, y0, x1, y0 + fold, w, c);
    line(x1, y0 + fold, x1, y1, w, c);
    line(x1, y1, x0, y1, w, c);
    line(x0, y1, x0, y0, w, c);
    line(x1 - fold, y0, x1 - fold, y0 + fold, w, c);
    line(x1 - fold, y0 + fold, x1, y0 + fold, w, c);
}
fn disk(cx: f32, cy: f32, s: f32, w: f32, c: rl.Color, d: rl.Color) void {
    box(cx, cy, s * 0.62, s * 0.62, w, c);
    rl.drawRectangleRec(.{ .x = cx - s * 0.16, .y = cy - s * 0.31, .width = s * 0.32, .height = s * 0.20 }, d);
    box(cx, cy + s * 0.18, s * 0.40, s * 0.22, w * 0.8, c);
}
