const props = @import("../props/props.zig");
const mathx = @import("mathx.zig");
const wf = @import("../world/worldfmt.zig");

const Kind = props.Kind;
const Op = wf.Op;


const BASE_SEED: u64 = 20260728;

pub const Emit = struct {
    m: *wf.Map,
    rng: mathx.Rng,
    counter: u64 = 0,

    fn nextSeed(self: *Emit) u64 {
        self.counter += 1;
        return 1000 + self.counter;
    }

    fn push(self: *Emit, o: Op) void {
        _ = self.m.add(o) catch @panic("bake: worldfmt.MAX_OPS exceeded — raise the cap");
    }


    fn at(self: *Emit, kind: Kind, x: f32, z: f32, yaw: f32, scale: f32) void {
        self.atY(kind, x, 0, z, yaw, scale);
    }

    fn atY(self: *Emit, kind: Kind, x: f32, y: f32, z: f32, yaw: f32, scale: f32) void {
        var o = wf.defaults(.at);
        o.kind = kind;
        o.x = x;
        o.z = z;
        o.yaw = yaw;
        o.scale = scale;
        o.r1 = y;
        self.push(o);
    }

    fn jit(self: *Emit, kind: Kind, x: f32, z: f32, spread: f32, sLo: f32, sHi: f32) void {
        self.at(
            kind,
            x + self.rng.signed() * spread,
            z + self.rng.signed() * spread,
            self.rng.range(0, 360),
            self.rng.range(sLo, sHi),
        );
    }

    fn belt(self: *Emit, kind: Kind, x0: f32, z0: f32, x1: f32, z1: f32, n: i32, sLo: f32, sHi: f32) void {
        var o = wf.defaults(.belt);
        o.kind = kind;
        o.x = x0;
        o.z = z0;
        o.x1 = x1;
        o.z1 = z1;
        o.n = n;
        o.sLo = sLo;
        o.sHi = sHi;
        o.seed = self.nextSeed();
        self.push(o);
    }

    fn beltMix(self: *Emit, mix: []const Kind, x0: f32, z0: f32, x1: f32, z1: f32, n: i32, sLo: f32, sHi: f32) *Op {
        var o = wf.defaults(.belt);
        o.x = x0;
        o.z = z0;
        o.x1 = x1;
        o.z1 = z1;
        o.n = n;
        o.sLo = sLo;
        o.sHi = sHi;
        o.seed = self.nextSeed();
        setMix(&o.mix, &o.nmix, mix);
        o.kind = mix[0];
        self.push(o);
        return &self.m.ops[self.m.nops - 1];
    }

    fn disc(self: *Emit, mix: []const Kind, cx: f32, cz: f32, r0: f32, r1: f32, n: i32, sLo: f32, sHi: f32) *Op {
        var o = wf.defaults(.disc);
        o.kind = mix[0];
        o.x = cx;
        o.z = cz;
        o.r0 = r0;
        o.r1 = r1;
        o.n = n;
        o.sLo = sLo;
        o.sHi = sHi;
        o.seed = self.nextSeed();
        if (mix.len > 1) setMix(&o.mix, &o.nmix, mix);
        self.push(o);
        return &self.m.ops[self.m.nops - 1];
    }

    fn ring(self: *Emit, kind: Kind, cx: f32, cz: f32, radius: f32, n: i32, skip: i32, sLo: f32, sHi: f32) void {
        var o = wf.defaults(.ring);
        o.kind = kind;
        o.x = cx;
        o.z = cz;
        o.r0 = radius;
        o.n = n;
        o.skip = skip;
        o.sLo = sLo;
        o.sHi = sHi;
        o.seed = self.nextSeed();
        self.push(o);
    }

    fn line(self: *Emit, mix: []const Kind, ax: f32, az: f32, bx: f32, bz: f32, seg: f32, chance: f32, sLo: f32, sHi: f32) void {
        var o = wf.defaults(.line);
        o.kind = mix[0];
        o.x = ax;
        o.z = az;
        o.x1 = bx;
        o.z1 = bz;
        o.r0 = seg;
        o.chance = chance;
        o.sLo = sLo;
        o.sHi = sHi;
        o.seed = self.nextSeed();
        if (mix.len > 1) setMix(&o.mix, &o.nmix, mix);
        self.push(o);
    }

    fn ivyOn(self: *Emit, x0: f32, z0: f32, x1: f32, z1: f32) void {
        var o = wf.defaults(.ivy);
        o.kind = .ivy;
        o.x = x0;
        o.z = z0;
        o.x1 = x1;
        o.z1 = z1;
        o.sLo = 0.85;
        o.sHi = 1.5;
        o.seed = self.nextSeed();
        self.push(o);
    }

    fn clearing(self: *Emit, x: f32, z: f32, r: f32) void {
        if (self.m.nclearings >= wf.MAX_CLEARINGS) @panic("bake: clearing cap exceeded");
        self.m.clearings[self.m.nclearings] = .{ .x = x, .z = z, .r = r };
        self.m.nclearings += 1;
    }

    fn foe(self: *Emit, kind: wf.FoeKind, x: f32, z: f32, yawDeg: f32, scale: f32, seed: f32) void {
        if (self.m.nfoes >= wf.MAX_FOES) @panic("bake: foe cap exceeded");
        self.m.foes[self.m.nfoes] = .{ .kind = kind, .x = x, .z = z, .yaw = yawDeg, .scale = scale, .seed = seed };
        self.m.nfoes += 1;
    }

    fn zone(self: *Emit, name: []const u8, x0: f32, z0: f32, x1: f32, z1: f32, density: f32, mix: []const Kind) void {
        if (self.m.nzones >= wf.MAX_ZONES) @panic("bake: zone cap exceeded");
        var z = wf.Zone{ .x = x0, .z = z0, .x1 = x1, .z1 = z1, .density = density };
        const n = @min(name.len, wf.NAME_CAP - 1);
        @memcpy(z.name[0..n], name[0..n]);
        setMix(&z.mix, &z.nmix, mix);
        self.m.zones[self.m.nzones] = z;
        self.m.nzones += 1;
    }
};

/// One implementation, `wf.setMix`. It TRUNCATES, though, and a bake that overran the cap would then emit a
/// mix quietly missing kinds — so the door refuses loudly first and copies through the one writer.
fn setMix(dst: *[wf.MAX_MIX]Kind, n: *u8, src: []const Kind) void {
    if (src.len > wf.MAX_MIX) @panic("bake: kind mix longer than worldfmt.MAX_MIX");
    wf.setMix(dst, n, src);
}

fn localToWorld(lx: f32, lz: f32, yaw: f32, scale: f32) [2]f32 {
    const th = mathx.radians(yaw);
    const c = mathx.cosf(th);
    const s = mathx.sinf(th);
    return .{ scale * (lx * c + lz * s), scale * (-lx * s + lz * c) };
}


pub fn build(m: *wf.Map) void {
    m.* = .{};
    m.setName("The Fallen Plain");
    m.half = wf.DEFAULT_HALF;
    m.runway = .{ .x = -3.4, .z = -44, .x1 = 3.4, .z1 = 30 };

    var p = Emit{ .m = m, .rng = mathx.Rng.init(BASE_SEED) };

    p.clearing(-98, -16, 18.0);
    p.clearing(-74, 30, 15.0);

    avenue(&p);
    fallenCity(&p);
    theTarn(&p);
    oldWood(&p);
    theDowns(&p);
    groundCover(&p);
    foes(&p);
}

fn foes(p: *Emit) void {
    p.foe(.toad, 13.5, -14.0, 215, 1.08, 0.0);
    p.foe(.toad, -13.0, -20.0, 70, 0.94, 0.37);
    p.foe(.toad, 14.5, -8.0, 250, 1.0, 0.61);
    p.foe(.toad, -12.5, -27.0, 120, 1.14, 0.83);
    p.foe(.archer, -16.0, -22.0, 60, 1.0, 0.2);
    p.foe(.archer, 17.5, -34.0, 210, 1.04, 0.7);
    p.foe(.ogre, 3.0, -50.0, 0, 1.0, 0.4);
}

const P = struct { x: f32, z: f32, yaw: f32, s: f32, kind: Kind };
const avenue_layout = [_]P{
    .{ .x = -6, .z = 14, .yaw = 8, .s = 0.9, .kind = .broken },
    .{ .x = 6, .z = 12, .yaw = 0, .s = 1.0, .kind = .pillar },
    .{ .x = -6, .z = -6, .yaw = 0, .s = 1.0, .kind = .pillar },
    .{ .x = 6, .z = -6, .yaw = 0, .s = 1.1, .kind = .pillar },
    .{ .x = -6, .z = -16, .yaw = 0, .s = 1.0, .kind = .broken },
    .{ .x = 6, .z = -16, .yaw = 12, .s = 1.0, .kind = .pillar },
    .{ .x = -6, .z = -26, .yaw = 0, .s = 0.95, .kind = .pillar },
    .{ .x = 6, .z = -26, .yaw = 0, .s = 1.05, .kind = .broken },
    .{ .x = -6, .z = -36, .yaw = -6, .s = 1.05, .kind = .pillar },
    .{ .x = 6, .z = -36, .yaw = 20, .s = 0.95, .kind = .broken },
    .{ .x = 0, .z = -31, .yaw = 0, .s = 1.0, .kind = .arch },
    .{ .x = 3.0, .z = 6.5, .yaw = 0, .s = 1.0, .kind = .bonfire },
    .{ .x = -14, .z = -14, .yaw = 78, .s = 1.1, .kind = .wall },
    .{ .x = 15, .z = -40, .yaw = -12, .s = 1.2, .kind = .wall },
    .{ .x = -24, .z = -28, .yaw = 100, .s = 0.9, .kind = .wall },
    .{ .x = -12, .z = -2, .yaw = 0, .s = 1.1, .kind = .tree },
    .{ .x = 16, .z = -31, .yaw = 140, .s = 1.3, .kind = .tree },
    .{ .x = -20, .z = -38, .yaw = 70, .s = 0.9, .kind = .tree },
    .{ .x = 24, .z = 6, .yaw = 200, .s = 1.0, .kind = .tree },
    .{ .x = -11, .z = -29, .yaw = 15, .s = 1.0, .kind = .graves },
    .{ .x = -14, .z = -33, .yaw = -40, .s = 0.9, .kind = .graves },
    .{ .x = 13, .z = -26, .yaw = 60, .s = 0.8, .kind = .graves },
    .{ .x = -2.8, .z = -21, .yaw = 30, .s = 1.0, .kind = .sword },
    .{ .x = 10, .z = -8, .yaw = -70, .s = 0.9, .kind = .sword },
    .{ .x = -12.5, .z = -31, .yaw = 120, .s = 1.1, .kind = .sword },
    .{ .x = 15, .z = -3, .yaw = -25, .s = 1.3, .kind = .block },
    .{ .x = 13, .z = -22, .yaw = 70, .s = 1.0, .kind = .block },
    .{ .x = -9, .z = -44, .yaw = 30, .s = 1.0, .kind = .block },
    .{ .x = 20, .z = -18, .yaw = 55, .s = 1.0, .kind = .block },
    .{ .x = -22, .z = -6, .yaw = -35, .s = 0.9, .kind = .block },
    .{ .x = 7.5, .z = -11, .yaw = -18, .s = 1.0, .kind = .banner },
    .{ .x = -7.5, .z = -33, .yaw = 155, .s = 1.1, .kind = .banner },
    .{ .x = -8.5, .z = 7, .yaw = 155, .s = 1.0, .kind = .statue },
    .{ .x = 2.5, .z = -13, .yaw = 45, .s = 1.0, .kind = .rubble },
    .{ .x = -4, .z = -34, .yaw = 10, .s = 1.0, .kind = .rubble },
    .{ .x = 8, .z = 2, .yaw = 70, .s = 0.8, .kind = .rubble },
    .{ .x = -8, .z = -20, .yaw = 0, .s = 1.0, .kind = .rubble },
    .{ .x = 2.1, .z = 5.5, .yaw = 40, .s = 1.0, .kind = .glow },
    .{ .x = 4.2, .z = 7.6, .yaw = 210, .s = 0.85, .kind = .glow },
    .{ .x = -11.8, .z = -30.6, .yaw = 75, .s = 1.0, .kind = .flowers },
    .{ .x = 12.4, .z = -27.2, .yaw = 150, .s = 0.9, .kind = .flowers },
    .{ .x = -13.2, .z = -15.7, .yaw = 25, .s = 1.15, .kind = .reeds },
    .{ .x = -9.6, .z = -28.2, .yaw = 20, .s = 0.95, .kind = .flowers },
    .{ .x = -13.5, .z = -27.8, .yaw = 130, .s = 1.05, .kind = .flowers },
    .{ .x = -15.4, .z = -31.4, .yaw = 250, .s = 0.9, .kind = .flowers },
    .{ .x = -12.2, .z = -34.4, .yaw = 300, .s = 1.0, .kind = .flowers },
    .{ .x = -9.4, .z = -32.6, .yaw = 60, .s = 0.85, .kind = .flowers },
    .{ .x = 11.0, .z = -24.2, .yaw = 200, .s = 0.9, .kind = .flowers },
    .{ .x = 14.6, .z = -24.8, .yaw = 20, .s = 0.95, .kind = .flowers },
    .{ .x = -3.5, .z = -30.2, .yaw = 0, .s = 1.0, .kind = .brazier },
    .{ .x = 0, .z = -4, .yaw = 0, .s = 1.2, .kind = .paving },
    .{ .x = 0.6, .z = -19, .yaw = 40, .s = 1.1, .kind = .paving },
    .{ .x = -0.8, .z = -38, .yaw = 15, .s = 1.0, .kind = .paving },
};

fn avenue(p: *Emit) void {
    for (avenue_layout) |q| p.at(q.kind, q.x, q.z, q.yaw, q.s);
    p.ivyOn(-30, -46, 30, 26);
    p.at(.lantern, 4.6, 1.5, 0, 1.0);
    p.at(.lantern, -4.6, -22.0, 0, 1.0);
    p.at(.well, -13.5, 3.0, 0, 1.0);
    p.at(.shrine, 6.8, -3.5, 200, 1.0);
    p.at(.cairn, -5.2, 18.0, 0, 1.1);
    p.at(.barrels, 9.5, -16.0, 50, 0.95);
    p.belt(.wildflowers, -18, -6, 18, 24, 60, 0.85, 1.35);
    p.belt(.grasstall, -20, -8, 20, 26, 80, 0.85, 1.4);
    p.belt(.clover, -20, -8, 20, 26, 60, 0.9, 1.5);
    p.belt(.foxglove, -18, -6, 18, 22, 26, 0.85, 1.2);
    p.belt(.sapling, -24, -42, 24, 26, 30, 0.8, 1.2);
    p.belt(.thicket, -26, -44, 26, 26, 20, 0.85, 1.25);
    p.belt(.bush, -26, -44, 26, 26, 34, 0.85, 1.3);
    p.belt(.mushrooms, -22, -40, 22, 24, 24, 0.9, 1.3);
    p.belt(.rocks, -26, -44, 26, 26, 22, 0.8, 1.2);
    p.belt(.outcrop, -28, -44, 28, 26, 10, 0.85, 1.2);
}

fn fallenCity(p: *Emit) void {
    const COLONNADE = [_]Kind{ .pillar, .broken, .broken };
    p.line(&COLONNADE, -6.5, -48, -6.5, -112, 11.0, 1.0, 0.85, 1.15);
    p.line(&COLONNADE, 6.5, -48, 6.5, -112, 11.0, 1.0, 0.85, 1.15);
    p.belt(.paving, -3.2, -112, 3.2, -48, 6, 0.9, 1.4);
    p.belt(.rubble, -5, -112, 5, -48, 5, 0.8, 1.3);

    _ = p.disc(&.{.paving}, 0, -80, 0, 13.0, 14, 1.0, 1.5);
    p.at(.statue, -9.5, -74, 150, 1.25);
    p.at(.statue, 9.0, -86, 20, 1.15);
    p.at(.brazier, -5.0, -79.0, 0, 1.1);
    p.at(.brazier, 5.4, -81.5, 0, 1.0);
    p.ring(.broken, 0, -80, 15.5, 12, 5, 0.8, 1.2);
    p.at(.monolith, 0, -80, p.rng.range(0, 360), 1.35);
    p.belt(.rubble, -18, -94, 18, -66, 16, 0.8, 1.4);

    const cx: f32 = -30.0;
    const cz: f32 = -66.0;
    p.at(.chapel, cx, cz, 270, 1.0);
    const torches = [_][2]f32{ .{ -1.9, 2.4 }, .{ 1.9, 2.4 }, .{ 1.9, -1.4 } };
    for (torches) |t| {
        const w = localToWorld(t[0], t[1], 270, 1.0);
        p.at(.torch, cx + w[0], cz + w[1], p.rng.range(0, 360), 0.95);
    }
    p.at(.brazier, cx + 5.2, cz + 0.6, 0, 0.95);
    p.belt(.graves, cx - 9, cz - 8, cx - 3, cz + 8, 5, 0.85, 1.15);
    p.belt(.rubble, cx - 7, cz - 9, cx + 7, cz + 9, 7, 0.8, 1.2);
    p.belt(.flowers, cx - 9, cz - 9, cx - 2, cz + 9, 8, 0.8, 1.1);

    towerSite(p, 36.0, -88.0, 20);
    towerSite(p, -52.0, -104.0, 200);

    p.line(&.{.wall}, -46, -120, 46, -120, 7.4, 0.78, 0.9, 1.25);
    p.line(&.{.wall}, -46, -120, -46, -58, 7.4, 0.78, 0.9, 1.25);
    p.line(&.{.wall}, 46, -120, 46, -62, 7.4, 0.78, 0.9, 1.25);

    const quarter = [_][3]f32{
        .{ 20, -58, 84 },   .{ 27, -64, 12 },   .{ 19, -70, 96 },  .{ 28, -76, 4 },
        .{ -18, -92, 270 }, .{ -25, -99, 186 }, .{ -16, -105, 8 }, .{ 24, -100, 200 },
        .{ 31, -107, 92 },  .{ -30, -86, 96 },
    };
    for (quarter) |h| {
        p.at(.cottage, h[0], h[1], h[2] + p.rng.signed() * 8, p.rng.range(0.95, 1.35));
        p.belt(.rubble, h[0] - 5, h[1] - 5, h[0] + 5, h[1] + 5, 3, 0.8, 1.3);
        if (p.rng.float() < 0.45) p.jit(.paving, h[0], h[1] - 5.5, 2.0, 1.0, 1.4);
    }
    p.at(.cart, 4.6, -55.0, 28, 1.0);
    p.at(.cart, -5.8, -97.0, 200, 0.95);
    p.belt(.sword, -20, -110, 20, -50, 9, 0.85, 1.15);
    p.belt(.banner, -24, -112, 24, -52, 6, 0.9, 1.2);
    p.belt(.block, -40, -118, 40, -50, 26, 0.85, 1.35);
    p.belt(.tree, -42, -118, 42, -48, 16, 0.8, 1.25);
    p.at(.well, -12.0, -62.0, 0, 1.05);
    p.at(.well, 16.5, -95.0, 0, 1.0);
    p.at(.shrine, 5.5, -50.0, 186, 1.0);
    p.at(.gibbet, -8.5, -54.0, 200, 1.05);
    p.at(.gibbet, 11.0, -110.0, 20, 0.95);
    var ln: i32 = 0;
    while (ln < 8) : (ln += 1) {
        const lz = -52.0 - @as(f32, @floatFromInt(ln)) * 8.5;
        p.at(.lantern, if (@mod(ln, 2) == 0) @as(f32, 4.2) else -4.2, lz, 0, p.rng.range(0.9, 1.1));
    }
    p.belt(.stairs, -42, -116, 42, -50, 14, 0.85, 1.3);
    p.belt(.sarcophagus, -40, -114, 40, -52, 12, 0.9, 1.25);
    p.belt(.barrels, -38, -112, 38, -50, 18, 0.85, 1.2);
    p.belt(.woodpile, -36, -110, 36, -52, 10, 0.85, 1.15);
    p.belt(.bones, -40, -116, 40, -48, 22, 0.85, 1.3);
    p.belt(.cart, -34, -112, 34, -50, 8, 0.85, 1.1);
    p.belt(.fence, -38, -112, 38, -52, 14, 0.9, 1.2);
    p.ivyOn(-46, -122, 46, -46);
    p.belt(.nettles, -44, -120, 44, -48, 120, 0.85, 1.35);
    p.belt(.sapling, -44, -120, 44, -48, 70, 0.8, 1.2);
    p.belt(.thicket, -44, -120, 44, -48, 40, 0.85, 1.3);
    p.at(.gate, 2, -124, 4, 1.35);
    p.at(.tower, -34, -132, 10, 1.4);
    p.at(.tower, 44, -126, -25, 1.15);
    p.at(.tower, -96, -128, 40, 1.2);
    p.at(.tower, 104, -120, 15, 1.3);
    p.at(.tower, -128, -66, 55, 1.1);
    p.at(.tower, 132, -78, -30, 1.0);
}

fn towerSite(p: *Emit, x: f32, z: f32, yaw: f32) void {
    p.at(.watchtower, x, z, yaw, 1.0);
    p.at(.torch, x + p.rng.signed() * 0.9, z + p.rng.signed() * 0.9, p.rng.range(0, 360), 0.9);
    const door = localToWorld(0, -3.6, yaw, 1.0);
    p.at(.brazier, x + door[0], z + door[1], 0, 1.0);
    p.belt(.rubble, x - 6, z - 6, x + 6, z + 6, 5, 0.8, 1.3);
    p.belt(.block, x - 8, z - 8, x + 8, z + 8, 3, 0.8, 1.1);
}

fn theTarn(p: *Emit) void {
    const lx: f32 = 104.0;
    const lz: f32 = 6.0;
    p.atY(.water, lx, 0, lz, 0, 3.1); // ~40 m across
    p.atY(.water, 62.0, 0.004, -52.0, 40, 1.05);

    p.at(.causeway, 74.0, 8.0, 6, 1.35);
    p.at(.causeway, 86.5, 9.4, 10, 1.35);
    p.belt(.rocks, 66, 0, 82, 16, 8, 0.8, 1.3);

    _ = p.disc(&.{ .broken, .broken, .broken, .block, .block }, lx, lz, 6.0, 34.0, 9, 0.8, 1.2);
    _ = p.disc(&.{.willow}, lx, lz, 36.0, 46.0, 11, 0.85, 1.3);
    _ = p.disc(&.{ .reeds, .reeds, .cattails, .cattails }, lx, lz, 26.0, 54.0, 420, 0.9, 1.55);

    var raft: i32 = 0;
    while (raft < 14) : (raft += 1) {
        const ra = p.rng.angle();
        const rd = p.rng.range(16.0, 33.0);
        const o = p.disc(&.{.lilypads}, lx + mathx.cosf(ra) * rd, lz + mathx.sinf(ra) * rd, 0, 4.5, 7, 0.85, 1.6);
        o.bias = 1.0;
    }
    _ = p.disc(&.{.lilypads}, 62.0, -52.0, 1.0, 9.0, 14, 0.8, 1.3);

    p.belt(.boulder, 62, -40, 150, 55, 26, 0.8, 1.5);
    p.belt(.rocks, 58, -50, 152, 60, 44, 0.8, 1.4);
    p.belt(.bush, 60, -55, 152, 62, 60, 0.8, 1.3);
    p.belt(.thicket, 58, -58, 152, 62, 40, 0.85, 1.4);
    p.belt(.nettles, 56, -60, 152, 62, 70, 0.85, 1.3);
    p.belt(.reeds, 52, -66, 78, -34, 90, 0.9, 1.4);
    p.belt(.cattails, 52, -66, 78, -34, 60, 0.9, 1.4);
    p.belt(.willow, 52, -62, 74, -40, 8, 0.8, 1.1);
    p.belt(.log, 62, -30, 148, 50, 14, 0.8, 1.2);
    p.belt(.outcrop, 60, -50, 150, 58, 16, 0.85, 1.3);
    p.belt(.sapling, 58, -55, 152, 60, 45, 0.8, 1.2);
    p.belt(.birch, 56, -56, 152, 60, 16, 0.8, 1.15);
    p.at(.campfire, 88.0, 34.0, 0, 1.0);
    p.at(.log, 90.6, 35.4, 20, 1.0);
    p.at(.cart, 85.0, 37.5, 130, 0.9);
    p.at(.barrels, 86.6, 31.6, 70, 0.95);
    p.at(.fence, 91.0, 30.0, 24, 0.95);
    p.at(.shrine, 72.0, 14.0, 100, 1.0);
    p.at(.lantern, 68.5, 8.5, 0, 1.0);
    p.at(.tower, 146, 30, -40, 1.1);
    p.at(.monolith, 70, 42, p.rng.range(0, 360), 1.1);
}

fn oldWood(p: *Emit) void {
    const CANOPY = [_]Kind{
        .bigtree,  .bigtree,  .bigtree2, .bigtree2, .bigtree3, .bigtree3,
        .bigtree3, .bigtree3, .conifer,  .conifer,  .conifer,  .conifer,
        .birch,    .birch,    .birch,    .snag,     .snag,     .tree,
    };
    const canopy = p.beltMix(&CANOPY, -152, -120, -54, 130, 260, 0.68, 1.24);
    canopy.gAxis = .x;
    canopy.gA = -54;
    canopy.gB = -84;
    canopy.gFloor = 0.18;
    canopy.avoid = .{ .runway = true, .water = true, .clear = true };
    canopy.field = false;

    p.belt(.sapling, -152, -125, -54, 132, 150, 0.8, 1.35);
    p.belt(.thicket, -152, -125, -54, 132, 110, 0.85, 1.45);
    p.belt(.stump, -150, -120, -56, 130, 60, 0.8, 1.3);
    p.belt(.log, -150, -120, -56, 130, 55, 0.8, 1.3);
    p.belt(.boulder, -152, -125, -56, 132, 46, 0.8, 1.6);
    p.belt(.rocks, -152, -125, -56, 132, 60, 0.8, 1.4);
    p.belt(.outcrop, -152, -125, -58, 132, 24, 0.85, 1.4);
    p.belt(.fern, -152, -125, -54, 132, 220, 0.8, 1.35);
    p.belt(.bramble, -152, -125, -54, 132, 150, 0.8, 1.4);
    p.belt(.bush, -152, -125, -52, 132, 130, 0.8, 1.4);
    p.belt(.mushrooms, -152, -125, -54, 132, 130, 0.85, 1.5);
    p.belt(.bracken, -152, -125, -54, 132, 120, 0.85, 1.4);
    p.belt(.moss, -152, -125, -54, 132, 140, 0.9, 1.6);
    p.belt(.nettles, -150, -120, -56, 130, 70, 0.85, 1.3);
    p.ring(.mushrooms, -120, 52, 3.2, 9, 4, 0.9, 1.4);
    p.belt(.cairn, -145, -110, -60, 120, 7, 0.9, 1.2);
    p.belt(.bones, -148, -118, -58, 128, 9, 0.85, 1.2);

    p.ring(.monolith, -98, -16, 8.5, 9, 6, 0.9, 1.25);
    p.at(.monolith, -98, -16, 30, 0.7);
    p.belt(.flowers, -106, -24, -90, -8, 12, 0.8, 1.2);
    p.belt(.glow, -104, -22, -92, -10, 5, 0.9, 1.2);
    p.at(.brazier, -93.0, -11.0, 0, 1.0);

    const hx: f32 = -74.0;
    const hz: f32 = 30.0;
    p.at(.cottage, hx, hz, 270, 1.05);
    const door = localToWorld(0, -4.6, 270, 1.05);
    p.at(.campfire, hx + door[0], hz + door[1], 0, 1.1);
    p.at(.log, hx + 4.4, hz + 3.0, 70, 1.0);
    p.at(.stump, hx + 3.2, hz - 3.4, 0, 1.15);
    p.at(.cart, hx + 6.5, hz - 1.0, 190, 0.95);
    p.at(.torch, hx + 1.6, hz + 0.4, 0, 0.9);
    p.at(.woodpile, hx - 3.6, hz + 2.6, 12, 1.05);
    p.at(.well, hx + 7.5, hz + 4.5, 0, 1.0);
    p.at(.fence, hx + 2.0, hz + 8.0, 6, 1.1);
    p.at(.fence, hx + 9.5, hz + 8.6, -8, 1.0);
    p.at(.barrels, hx - 5.0, hz - 2.2, 40, 1.0);
    p.at(.lantern, hx + 4.2, hz - 4.6, 0, 1.0);
    p.belt(.log, hx - 6, hz - 6, hx + 8, hz + 8, 10, 0.85, 1.2);
    p.belt(.bramble, hx - 10, hz - 10, hx + 10, hz + 10, 14, 0.8, 1.2);
    p.belt(.wildflowers, hx - 9, hz - 9, hx + 9, hz + 9, 18, 0.85, 1.25);
    p.belt(.mushrooms, hx - 8, hz - 8, hx + 8, hz + 8, 10, 0.9, 1.3);
}

fn theDowns(p: *Emit) void {
    p.belt(.bigtree, -120, 52, 40, 150, 18, 0.7, 1.05);
    p.belt(.tree, -130, 48, 60, 152, 32, 0.8, 1.25);
    p.belt(.snag, -130, 50, 70, 150, 12, 0.8, 1.1);
    p.belt(.boulder, -140, 46, 140, 152, 40, 0.8, 1.7);
    p.belt(.rocks, -140, 46, 145, 154, 60, 0.8, 1.4);
    p.belt(.outcrop, -140, 46, 145, 152, 34, 0.85, 1.45);
    p.belt(.scree, -140, 48, 145, 152, 26, 0.85, 1.4);
    p.belt(.cairn, -120, 52, 120, 150, 16, 0.9, 1.25);
    p.belt(.graves, -60, 60, 60, 140, 20, 0.8, 1.2);
    p.belt(.sarcophagus, -50, 66, 50, 130, 7, 0.9, 1.2);
    p.belt(.monolith, -110, 60, 110, 148, 11, 0.9, 1.3);
    p.belt(.wall, -100, 58, 100, 145, 12, 0.9, 1.2);
    p.belt(.shrub, -145, 44, 145, 155, 90, 0.8, 1.4);
    p.belt(.gorse, -145, 44, 145, 155, 110, 0.85, 1.5);
    p.belt(.heather, -148, 44, 148, 156, 200, 0.9, 1.6);
    p.belt(.thistle, -140, 46, 140, 152, 90, 0.85, 1.3);
    p.belt(.sword, -40, 55, 40, 120, 9, 0.9, 1.1);
    p.belt(.bones, -80, 58, 80, 140, 12, 0.85, 1.25);
    towerSite(p, 22.0, 98.0, 350);
    p.at(.tower, -74, 138, 25, 1.0);
    p.at(.tower, 96, 132, -15, 1.15);
    p.at(.campfire, -34.0, 74.0, 0, 1.0);
    p.at(.log, -32.0, 76.2, 30, 1.0);
    p.at(.cairn, -30.5, 71.0, 0, 1.15);
    p.at(.gibbet, 6.0, 62.0, 30, 1.0);
    p.at(.shrine, -4.5, 88.0, 186, 1.0);
    p.at(.lantern, 3.0, 104.0, 0, 1.0);
}

fn groundCover(p: *Emit) void {
    const F: f32 = 400;
    p.zone("wood", -F, -F, -52, F, 0.98, &.{
        .fern,    .fern,    .fern,   .bramble, .bramble,   .thicket,
        .bush,    .moss,    .moss,   .moss,    .mushrooms, .mushrooms,
        .bracken, .bracken, .clover, .nettles, .grasstall, .patch,
    });
    p.zone("marsh", 50, -F, F, F, 0.86, &.{
        .reeds, .reeds,   .cattails, .cattails, .cattails,  .patch,
        .bush,  .nettles, .moss,     .moss,     .grasstall, .wildflowers,
    });
    p.zone("city", -F, -F, F, -46, 0.44, &.{
        .tuft,   .tuft, .patch, .nettles, .nettles,     .thistle,
        .clover, .moss, .shrub, .shrub,   .wildflowers, .grasstall,
    });
    p.zone("downs", -F, 46, F, F, 0.58, &.{
        .heather, .heather, .heather, .gorse, .gorse,   .patch,
        .patch,   .tuft,    .tuft,    .moss,  .thistle, .bracken,
    });
    p.zone("plain", -F, -F, F, F, 0.80, &.{
        .grasstall, .grasstall, .grasstall, .patch,  .patch,       .tuft,
        .clover,    .clover,    .moss,      .shrub,  .wildflowers, .wildflowers,
        .flowers,   .thistle,   .foxglove,  .bracken,
    });

}
