const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const glsl = @import("shaders.zig");
const daynight = @import("../world/daynight.zig");

const v3 = mathx.v3;


const alloc = std.heap.raw_c_allocator;

// Shadow sampler lives on a high texture slot raylib's default material never binds (it only uses slot 0 for albedo), so the per-frame bind survives drawModel/drawMesh.
const SLOT_SHADOW: i32 = 12;
const SLOT_SOIL: i32 = 13;
const SLOT_WATER: i32 = 14;
const SLOT_SOILCOV: i32 = 15;
const SLOT_SOILEDGE: i32 = 16;
/// The COAST SHAPE and the LIQUID, packed into one byte a cell (`env.packLiquid`).
const SLOT_WATEREDGE: i32 = 17;

pub const SOIL_N: i32 = 112;

/// THE WATER FIELD's resolution — finer than the soil's, because a coastline is a SHAPE you read. 224 over a 560 m map is 2.5 m a cell, and the field is BILINEAR (unlike the soil's ids, which must not interpolate), so the shoreline the shader draws is smooth well under a cell.
pub const WATER_N: i32 = 224;

pub const HEIGHT_N: i32 = 224;

/// Re-exported from the shader, which is where the GLSL that indexes `liquidTone` is generated from it.
/// `props.LIQUID_TONES` sizes off this and `wf.Liquid` asserts against it.
pub const LIQUID_N: usize = glsl.LIQUID_N;

/// Re-exported for `LIQUID_N`'s reason — the GLSL that discards on it is generated from it over there, so the
/// byte `env`'s bake writes, the one `env.paintedDepth` reads back and the one the sheet tests are one number.
pub const WATER_SHORE: u8 = glsl.WATER_SHORE;
pub const WATER_DEEP_AT: f32 = 11.0;
pub const WATER_WET_OUT: f32 = 3.4;

/// **THE RAW GL BLEND ENUMS, NAMED ONCE.** `rl.gl.rlSetBlendFactors` takes them as bare ints and two callers
/// want them (`env`'s occluder pass, the editor's opaque minimap blit); the editor was writing `1, 0, 0x8006`
/// with the names in a comment beside it.
pub const GL_ZERO: i32 = 0;
pub const GL_ONE: i32 = 1;
pub const GL_FUNC_ADD: i32 = 0x8006;

/// THE ANCHOR SUN — what the game was authored and photographed under, and the bearing every frame in `shots/` is framed off (`shots.LIT_YAW`). It is NOT what casts any more (`daynight.keyDir`); it stays because the cycle is SOLVED THROUGH it.
pub const SUN_DIR = daynight.ANCHOR_DIR;

/// WHAT IS CASTING THIS FRAME, and it is STILL ONE SOURCE (AGENTS.md): the shader's `sunDir`, the shadow camera's position and `env`'s shadow-reach cull all read this and nothing else. Written once a frame by `Scene.setHour` — never by hand.
pub var sun: rl.Vector3 = SUN_DIR;
pub var sunReach: f32 = daynight.reachOf(SUN_DIR);

/// **THE HOT KEY AND THE OUTPUT GAMMA, NAMED ONCE.** The whole chain every albedo in the game is SOLVED
/// through (AGENTS.md) lives in two places in the scene shader — `keyCol*diff*1.72` and the `pow(1.0/2.2)` on
/// the way out — and the GLSL is a raw string, so it cannot import a constant. The comptime pin below is what
/// keeps the two in step: move the key in the shader and the build stops here rather than letting the art
/// tests go on measuring the old chain and passing.
pub const KEY_HOT: f32 = 1.72;
pub const OUT_GAMMA: f32 = 2.2;

comptime {
    // The FS is ~30 KB of GLSL and a scan of it costs one branch a byte.
    @setEvalBranchQuota(200000);
    if (std.mem.indexOf(u8, glsl.sceneFS, "keyCol*diff*1.72*") == null)
        @compileError("gfx: the scene shader's key is no longer 1.72 — `KEY_HOT` and every solved albedo have parted company with it");
    if (std.mem.indexOf(u8, glsl.sceneFS, "vec3(1.0/2.2)") == null)
        @compileError("gfx: the scene shader no longer gammas at 1/2.2 — `OUT_GAMMA` has parted company with it");
}

/// What an authored albedo BYTE (0..255) comes up as ON SCREEN, in the same units. The one place the chain is
/// arithmetic rather than prose — `propgold` and `propmarket` each carried their own copy of it.
pub fn screenOf(albedo: f32) f32 {
    return 255.0 * std.math.pow(f32, mathx.clampF(albedo / 255.0 * KEY_HOT, 0, 1), 1.0 / OUT_GAMMA);
}

/// The same chain read backwards: the albedo byte that lands on a wanted SCREEN byte. This is the solve the
/// palettes are authored with, and guessing it instead is what the law exists to stop.
pub fn albedoFor(screen: f32) f32 {
    return std.math.pow(f32, mathx.clampF(screen, 0, 255) / 255.0, OUT_GAMMA) / KEY_HOT * 255.0;
}

/// A colour's screen value taken off its own MEAN channel — what a "is this paler than that" test compares.
pub fn screenOfColor(c: rl.Color) f32 {
    const mean = (@as(f32, @floatFromInt(c.r)) + @as(f32, @floatFromInt(c.g)) + @as(f32, @floatFromInt(c.b))) / 3.0;
    return screenOf(mean);
}

pub const SHADOWMAP_RES = 8192;
pub const SHADOW_ORTHO = 108.0;
/// The widest the box may open, for the editor zoomed out over a whole map (`worldfmt.MAX_DECLARED_HALF` is 312 a side). 8192 over 1024 m is 12.5 cm a texel: a pillar still lays a shadow, a fern's is gone.
pub const SHADOW_SPAN_MAX = 1024.0;
const SUN_DIST = 120.0;
const SHADOW_DEPTH = 0.78;
const SHADOW_NEAR = SUN_DIST - SHADOW_ORTHO * SHADOW_DEPTH;

/// HOW WIDE THE BOX IS THIS FRAME, read by `env`'s caster cull the way `sun` is. Written only by `beginShadowPass`.
pub var shadowSpan: f32 = SHADOW_ORTHO;

const HAZE_DENSITY: f32 = 0.013;
const HAZE_STORM: f32 = 3.10;

pub const MAX_LIGHTS = 16;
comptime {
    @setEvalBranchQuota(200_000); // scanning a ~9 KB shader source three times at comptime
    std.debug.assert(MAX_LIGHTS == 16);
    std.debug.assert(std.mem.indexOf(u8, glsl.sceneFS, "lightPos[16]") != null);
    std.debug.assert(std.mem.indexOf(u8, glsl.sceneFS, "lightCol[16]") != null);
    std.debug.assert(std.mem.indexOf(u8, glsl.sceneFS, "lightRad[16]") != null);
}
pub const Light = struct {
    pos: rl.Vector3,
    col: rl.Vector3,
    radius: f32,
};

pub const Sky = struct {
    shader: rl.Shader,
    loc_fwd: i32,
    loc_right: i32,
    loc_up: i32,
    loc_res: i32,
    loc_time: i32,
    /// The hour's own uniforms. Held as locations rather than looked up per push: `getShaderLocation` is a string compare against the program's uniform table, and eleven of those a frame for numbers that never move is eleven for nothing.
    loc_sun: i32,
    loc_moon: i32,
    loc_stars: i32,
    loc_pal: [PAL_FIELDS.len]i32,

    /// The palette fields the sky colours come off, IN UNIFORM ORDER — the one place the two lists are tied together, so a renamed palette field is a compile error instead of a colour that stops arriving. **AND THE COUNT IS THIS LIST'S**: written out as three literal `8`s, a ninth colour was three edits.
    const PAL_FIELDS = [_][:0]const u8{ "skyLow", "skyMid", "skyHigh", "skyBank", "skyGlow", "skyDisc", "cloudDark", "cloudLit" };
    comptime {
        for (PAL_FIELDS) |name| {
            if (!@hasField(daynight.Palette, name)) @compileError("gfx.Sky: daynight.Palette has no `" ++ name ++ "`");
        }
    }

    pub fn init() Sky {
        const sh = rl.loadShaderFromMemory(glsl.skyVS, glsl.skyFS) catch @panic("sky shader");
        var pal: [PAL_FIELDS.len]i32 = undefined;
        for (PAL_FIELDS, 0..) |name, i| pal[i] = rl.getShaderLocation(sh, name);
        var out = Sky{
            .shader = sh,
            .loc_fwd = rl.getShaderLocation(sh, "camFwd"),
            .loc_right = rl.getShaderLocation(sh, "camRightS"),
            .loc_up = rl.getShaderLocation(sh, "camUpS"),
            .loc_res = rl.getShaderLocation(sh, "resolution"),
            .loc_time = rl.getShaderLocation(sh, "uTime"),
            .loc_sun = rl.getShaderLocation(sh, "sunDir"),
            .loc_moon = rl.getShaderLocation(sh, "moonDir"),
            .loc_stars = rl.getShaderLocation(sh, "stars"),
            .loc_pal = pal,
        };
        // A SKY WITH NO HOUR IN IT IS BLACK, so it is armed at the anchor here rather than left to the first frame: the menu draws over a live sky before the loop has ticked anything.
        out.setHour(daynight.SHOT_HOUR, 0, 0);
        return out;
    }

    pub fn setHour(self: *Sky, hour: f32, wet: f32, spore: f32) void {
        const p = daynight.bloom(daynight.overcast(daynight.paletteAt(hour), wet), spore);
        var s = daynight.sunDir(hour);
        var m = daynight.moonDir(hour);
        rl.setShaderValue(self.shader, self.loc_sun, &s, .vec3);
        rl.setShaderValue(self.shader, self.loc_moon, &m, .vec3);
        var st = p.stars;
        rl.setShaderValue(self.shader, self.loc_stars, &st, .float);
        inline for (PAL_FIELDS, 0..) |name, i| {
            var c = @field(p, name);
            rl.setShaderValue(self.shader, self.loc_pal[i], &c, .vec3);
        }
    }

    pub fn draw(self: *Sky, cam: rl.Camera3D) void {
        const w = rl.getScreenWidth();
        const h = rl.getScreenHeight();
        var t: f32 = @floatCast(rl.getTime());
        rl.setShaderValue(self.shader, self.loc_time, &t, .float);
        const fwd = norm3(v3(cam.target.x - cam.position.x, cam.target.y - cam.position.y, cam.target.z - cam.position.z));
        const right = norm3(cross(fwd, cam.up));
        const up = cross(right, fwd);
        const tanF = @tan(mathx.radians(cam.fovy) * 0.5);
        const aspect = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
        var f = fwd;
        var r = v3(right.x * tanF * aspect, right.y * tanF * aspect, right.z * tanF * aspect);
        var u = v3(up.x * tanF, up.y * tanF, up.z * tanF);
        rl.setShaderValue(self.shader, self.loc_fwd, &f, .vec3);
        rl.setShaderValue(self.shader, self.loc_right, &r, .vec3);
        rl.setShaderValue(self.shader, self.loc_up, &u, .vec3);
        var res = rl.Vector2{ .x = @floatFromInt(w), .y = @floatFromInt(h) };
        rl.setShaderValue(self.shader, self.loc_res, &res, .vec2);
        rl.beginShaderMode(self.shader);
        rl.drawRectangle(0, 0, w, h, rl.Color.white);
        rl.endShaderMode();
    }
};

pub const Vignette = struct {
    tex: rl.Texture2D,

    pub fn init() Vignette {
        const W = 256;
        const H = 256;
        const START = 0.62; // radius (0=centre, 1=edge-midpoint, ~1.41=corner) where the fade BEGINS — big clean centre
        const ENDR = 1.34;
        const MAX_A: f32 = 120.0;
        var img = rl.genImageColor(W, H, rl.Color.init(0, 0, 0, 0));
        var y: i32 = 0;
        while (y < H) : (y += 1) {
            var x: i32 = 0;
            while (x < W) : (x += 1) {
                const nx = (@as(f32, @floatFromInt(x)) / (W - 1)) * 2.0 - 1.0;
                const ny = (@as(f32, @floatFromInt(y)) / (H - 1)) * 2.0 - 1.0;
                const r = @sqrt(nx * nx + ny * ny);
                const t = mathx.smoothstep(START, ENDR, r);
                const a = mathx.u8f(t * MAX_A);
                rl.imageDrawPixel(&img, x, y, rl.Color.init(10, 16, 28, a));
            }
        }
        const tex = rl.loadTextureFromImage(img) catch @panic("vignette");
        rl.unloadImage(img);
        rl.setTextureFilter(tex, .bilinear);
        return .{ .tex = tex };
    }

    pub fn draw(self: *const Vignette) void {
        const src = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(self.tex.width), .height = @floatFromInt(self.tex.height) };
        const dst = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(rl.getScreenWidth()), .height = @floatFromInt(rl.getScreenHeight()) };
        rl.drawTexturePro(self.tex, src, dst, rl.Vector2{ .x = 0, .y = 0 }, 0, rl.Color.white);
    }
};

pub const RETRO_COUNT = RETRO_FILTERS.len;
pub const RETRO_EPS: f32 = 0.001;
pub const RF_PIXELATE = 0;
pub const RF_CHROMA = 1;
pub const RF_POSTERIZE = 2;
pub const RF_DITHER = 3;
pub const RF_GAMEBOY = 4;
pub const RF_CGA = 5;
pub const RF_PALETTE = 6;
pub const RF_SEPIA = 7;
pub const RF_MONO = 8;
pub const RF_AMBER = 9;
pub const RF_EDGES = 10;
pub const RF_SCANLINES = 11;
pub const RF_CURVE = 12;
pub const RF_VHS = 13;
pub const RF_GRAIN = 14;

// SINGLE SOURCE OF TRUTH — one row per filter in RF_* index order; the menu labels, uniform names, and owner-tuned launch defaults are DERIVED at comptime so they can't drift out of positional lockstep.
const RetroFilter = struct { name: [:0]const u8, uniform: [:0]const u8, default: f32 };
const RETRO_FILTERS = [_]RetroFilter{
    .{ .name = "Pixelate", .uniform = "fPixelate", .default = 0.05 },
    .{ .name = "Chroma Fringe", .uniform = "fChroma", .default = 0.09 },
    .{ .name = "Posterize", .uniform = "fPosterize", .default = 0.24 },
    .{ .name = "Dither", .uniform = "fDither", .default = 0.40 },
    .{ .name = "Game Boy", .uniform = "fGameBoy", .default = 0.0 },
    .{ .name = "CGA", .uniform = "fCGA", .default = 0.07 },
    .{ .name = "Palette 16", .uniform = "fPalette", .default = 0.07 },
    .{ .name = "Sepia", .uniform = "fSepia", .default = 0.05 },
    .{ .name = "Mono", .uniform = "fMono", .default = 0.0 },
    .{ .name = "Amber CRT", .uniform = "fAmber", .default = 0.0 },
    .{ .name = "Ink Edges", .uniform = "fEdges", .default = 0.0 },
    .{ .name = "Scanlines", .uniform = "fScanlines", .default = 0.0 },
    .{ .name = "CRT Curve", .uniform = "fCurve", .default = 0.0 },
    .{ .name = "VHS", .uniform = "fVHS", .default = 0.0 },
    .{ .name = "Film Grain", .uniform = "fGrain", .default = 0.0 },
};
pub const RETRO_NAMES = blk: {
    var out: [RETRO_COUNT][:0]const u8 = undefined;
    for (&out, RETRO_FILTERS) |*o, f| o.* = f.name;
    break :blk out;
};
const RETRO_UNIFORMS = blk: {
    var out: [RETRO_COUNT][:0]const u8 = undefined;
    for (&out, RETRO_FILTERS) |*o, f| o.* = f.uniform;
    break :blk out;
};
pub const RETRO_DEFAULTS = blk: {
    var out: [RETRO_COUNT]f32 = undefined;
    for (&out, RETRO_FILTERS) |*o, f| o.* = f.default;
    break :blk out;
};

comptime {
    const PINS = [_]struct { i: usize, u: [:0]const u8 }{
        .{ .i = RF_PIXELATE, .u = "fPixelate" },
        .{ .i = RF_CHROMA, .u = "fChroma" },
        .{ .i = RF_POSTERIZE, .u = "fPosterize" },
        .{ .i = RF_DITHER, .u = "fDither" },
        .{ .i = RF_GAMEBOY, .u = "fGameBoy" },
        .{ .i = RF_CGA, .u = "fCGA" },
        .{ .i = RF_PALETTE, .u = "fPalette" },
        .{ .i = RF_SEPIA, .u = "fSepia" },
        .{ .i = RF_MONO, .u = "fMono" },
        .{ .i = RF_AMBER, .u = "fAmber" },
        .{ .i = RF_EDGES, .u = "fEdges" },
        .{ .i = RF_SCANLINES, .u = "fScanlines" },
        .{ .i = RF_CURVE, .u = "fCurve" },
        .{ .i = RF_VHS, .u = "fVHS" },
        .{ .i = RF_GRAIN, .u = "fGrain" },
    };
    std.debug.assert(PINS.len == RETRO_COUNT);
    for (PINS, 0..) |row, k| {
        std.debug.assert(row.i == k);
        std.debug.assert(std.mem.eql(u8, RETRO_UNIFORMS[row.i], row.u));
    }
}

pub const Preset = struct { idx: usize, val: f32 };
pub const PRESET_PS1 = [_]Preset{ .{ .idx = RF_PIXELATE, .val = 0.35 }, .{ .idx = RF_DITHER, .val = 0.55 }, .{ .idx = RF_POSTERIZE, .val = 0.25 } };
pub const PRESET_CRT = [_]Preset{ .{ .idx = RF_SCANLINES, .val = 0.6 }, .{ .idx = RF_CHROMA, .val = 0.45 }, .{ .idx = RF_CURVE, .val = 0.55 }, .{ .idx = RF_GRAIN, .val = 0.25 } };
pub const PRESET_VHS = [_]Preset{ .{ .idx = RF_VHS, .val = 0.65 }, .{ .idx = RF_CHROMA, .val = 0.55 }, .{ .idx = RF_GRAIN, .val = 0.35 }, .{ .idx = RF_SEPIA, .val = 0.15 } };
pub const PRESET_GB = [_]Preset{ .{ .idx = RF_GAMEBOY, .val = 1.0 }, .{ .idx = RF_PIXELATE, .val = 0.45 }, .{ .idx = RF_DITHER, .val = 0.4 } };


pub const Retro = struct {
    shader: rl.Shader,
    rt: rl.RenderTexture2D,
    locs: [RETRO_COUNT]i32,
    loc_time: i32,
    values: [RETRO_COUNT]f32 = RETRO_DEFAULTS,

    pub fn init(w: i32, h: i32) Retro {
        const sh = rl.loadShaderFromMemory(glsl.skyVS, glsl.retroFS) catch @panic("retro shader");
        var res = rl.Vector2{ .x = @floatFromInt(w), .y = @floatFromInt(h) };
        rl.setShaderValue(sh, rl.getShaderLocation(sh, "resolution"), &res, .vec2);
        var locs: [RETRO_COUNT]i32 = undefined;
        for (RETRO_UNIFORMS, 0..) |name, i| locs[i] = rl.getShaderLocation(sh, name);
        return .{
            .shader = sh,
            .rt = rl.loadRenderTexture(w, h) catch @panic("retro rt"),
            .locs = locs,
            .loc_time = rl.getShaderLocation(sh, "time"),
        };
    }

    pub fn resize(self: *Retro, w: i32, h: i32) void {
        if (w <= 0 or h <= 0) return;
        if (self.rt.texture.width == w and self.rt.texture.height == h) return;
        rl.unloadRenderTexture(self.rt);
        self.rt = rl.loadRenderTexture(w, h) catch @panic("retro rt");
        var res = rl.Vector2{ .x = @floatFromInt(w), .y = @floatFromInt(h) };
        rl.setShaderValue(self.shader, rl.getShaderLocation(self.shader, "resolution"), &res, .vec2);
    }

    pub fn anyActive(self: *const Retro) bool {
        for (self.values) |v| if (v > RETRO_EPS) return true;
        return false;
    }

    pub fn allOff(self: *Retro) void {
        self.values = [_]f32{0} ** RETRO_COUNT;
    }

    pub fn applyPreset(self: *Retro, preset: []const Preset) void {
        self.allOff();
        for (preset) |p| self.values[p.idx] = p.val;
    }

    pub fn begin(self: *Retro) bool {
        if (!self.anyActive()) return false;
        rl.beginTextureMode(self.rt);
        return true;
    }

    pub fn end(self: *Retro) void {
        rl.endTextureMode();
        var t: f32 = @floatCast(rl.getTime());
        rl.setShaderValue(self.shader, self.loc_time, &t, .float);
        for (self.locs, 0..) |loc, i| {
            var v = self.values[i];
            rl.setShaderValue(self.shader, loc, &v, .float);
        }
        const w: f32 = @floatFromInt(self.rt.texture.width);
        const h: f32 = @floatFromInt(self.rt.texture.height);
        rl.beginShaderMode(self.shader);
        rl.drawTexturePro(
            self.rt.texture,
            .{ .x = 0, .y = 0, .width = w, .height = -h },
            .{ .x = 0, .y = 0, .width = w, .height = h },
            .{ .x = 0, .y = 0 },
            0,
            rl.Color.white,
        );
        rl.endShaderMode();
    }
};

fn loadFieldTexture(n: i32, filter: rl.TextureFilter) rl.Texture2D {
    const cells: usize = @intCast(n * n);
    const blank = std.heap.c_allocator.alloc(u8, cells) catch @panic("field texture");
    defer std.heap.c_allocator.free(blank);
    @memset(blank, 0);
    const img = rl.Image{
        .data = blank.ptr,
        .width = n,
        .height = n,
        .mipmaps = 1,
        .format = .uncompressed_grayscale,
    };
    const tex = rl.loadTextureFromImage(img) catch @panic("field texture");
    rl.setTextureFilter(tex, filter);
    rl.setTextureWrap(tex, .clamp);
    return tex;
}

fn loadShadowmap(res: i32) rl.RenderTexture2D {
    const fbo = rl.gl.rlLoadFramebuffer();
    const depthTex = rl.gl.rlLoadTextureDepth(res, res, false);
    rl.gl.rlFramebufferAttach(fbo, depthTex, 100, 100, 0);
    const fmt = rl.PixelFormat.uncompressed_grayscale;
    return .{
        .id = @intCast(fbo),
        .texture = .{ .id = 0, .width = res, .height = res, .mipmaps = 1, .format = fmt },
        .depth = .{ .id = @intCast(depthTex), .width = res, .height = res, .mipmaps = 1, .format = fmt },
    };
}

fn dot3(a: rl.Vector3, b: rl.Vector3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

fn lightBasis() struct { fwd: rl.Vector3, right: rl.Vector3, up: rl.Vector3 } {
    const fwd = mathx.normV(mathx.scaleV(sun, -1));
    var right = mathx.crossV(v3(0, 0, -1), fwd);
    if (mathx.lenV(right) < 1e-4) right = mathx.crossV(v3(1, 0, 0), fwd);
    right = mathx.normV(right);
    return .{ .fwd = fwd, .right = right, .up = mathx.normV(mathx.crossV(fwd, right)) };
}

pub const Scene = struct {
    shader: rl.Shader,
    depthShader: rl.Shader,
    shadowMap: rl.RenderTexture2D,
    lightVP: rl.Matrix,
    loc_ground: i32,
    loc_lightVP: i32,
    loc_camPos: i32,
    loc_windAmt: i32,
    loc_time: i32,
    loc_flash: i32,
    loc_frost: i32,
    loc_fade: i32,
    loc_lightPos: i32,
    loc_lightCol: i32,
    loc_lightRad: i32,
    loc_nLights: i32,
    loc_sun: i32,
    loc_key: i32,
    loc_ambGround: i32,
    loc_ambSky: i32,
    loc_haze: i32,
    loc_hazeBank: i32,
    loc_keyAmt: i32,
    loc_hazeD: i32,
    loc_hazeScale: i32,
    soilTex: rl.Texture2D,
    soilCovTex: rl.Texture2D,
    soilEdgeTex: rl.Texture2D,
    loc_soilOn: i32,
    loc_soilHalf: i32,
    loc_soilCell: i32,
    waterTex: rl.Texture2D,
    waterEdgeTex: rl.Texture2D,
    loc_waterOn: i32,
    loc_waterHalf: i32,
    loc_waterCell: i32,
    loc_waterSheet: i32,
    loc_liquidTone: i32,
    saved_near: @TypeOf(rl.gl.rlGetCullDistanceNear()) = 0,
    saved_far: @TypeOf(rl.gl.rlGetCullDistanceFar()) = 0,

    pub fn init() Scene {
        const shader = rl.loadShaderFromMemory(glsl.sceneVS, glsl.sceneFS) catch @panic("scene shader");
        const depthShader = rl.loadShaderFromMemory(glsl.depthVS, glsl.depthFS) catch @panic("depth shader");
        var slotShadow = SLOT_SHADOW;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "shadowMap"), &slotShadow, .int);
        var res: i32 = SHADOWMAP_RES;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "shadowMapResolution"), &res, .int);
        var slotSoil = SLOT_SOIL;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "soilMap"), &slotSoil, .int);
        var slotWater = SLOT_WATER;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "waterMap"), &slotWater, .int);
        var slotSoilCov = SLOT_SOILCOV;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "soilCovMap"), &slotSoilCov, .int);
        var slotSoilEdge = SLOT_SOILEDGE;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "soilEdgeMap"), &slotSoilEdge, .int);
        var slotWaterEdge = SLOT_WATEREDGE;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "waterEdgeMap"), &slotWaterEdge, .int);
        var waterOff: i32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "waterOn"), &waterOff, .int);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "waterSheet"), &waterOff, .int);
        var windOff: f32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "windAmt"), &windOff, .float);
        var flashOff: f32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "hitFlash"), &flashOff, .float);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "frost"), &flashOff, .float);
        var fadeOff: f32 = 1;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "fade"), &fadeOff, .float);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "hazeScale"), &fadeOff, .float);
        var noLights: i32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "nLights"), &noLights, .int);
        var out = Scene{
            .shader = shader,
            .depthShader = depthShader,
            .shadowMap = loadShadowmap(SHADOWMAP_RES),
            .soilTex = loadFieldTexture(SOIL_N, .point),
            .soilCovTex = loadFieldTexture(SOIL_N, .bilinear),
            .soilEdgeTex = loadFieldTexture(SOIL_N, .point),
            .loc_soilOn = rl.getShaderLocation(shader, "soilOn"),
            .loc_soilHalf = rl.getShaderLocation(shader, "soilHalf"),
            .loc_soilCell = rl.getShaderLocation(shader, "soilCell"),
            .waterTex = loadFieldTexture(WATER_N, .bilinear),
            // POINT, like the soil edge map: both ordinals it packs are ordinals, and blending two of them
            // names a third shape and a fifth liquid.
            .waterEdgeTex = loadFieldTexture(WATER_N, .point),
            .loc_waterOn = rl.getShaderLocation(shader, "waterOn"),
            .loc_waterHalf = rl.getShaderLocation(shader, "waterHalf"),
            .loc_waterCell = rl.getShaderLocation(shader, "waterCell"),
            .loc_waterSheet = rl.getShaderLocation(shader, "waterSheet"),
            .loc_liquidTone = rl.getShaderLocation(shader, "liquidTone"),
            .lightVP = rl.math.matrixIdentity(),
            .loc_ground = rl.getShaderLocation(shader, "groundMode"),
            .loc_lightVP = rl.getShaderLocation(shader, "lightVP"),
            .loc_camPos = rl.getShaderLocation(shader, "camPos"),
            .loc_windAmt = rl.getShaderLocation(shader, "windAmt"),
            .loc_time = rl.getShaderLocation(shader, "uTime"),
            .loc_flash = rl.getShaderLocation(shader, "hitFlash"),
            .loc_frost = rl.getShaderLocation(shader, "frost"),
            .loc_fade = rl.getShaderLocation(shader, "fade"),
            .loc_lightPos = rl.getShaderLocation(shader, "lightPos"),
            .loc_lightCol = rl.getShaderLocation(shader, "lightCol"),
            .loc_lightRad = rl.getShaderLocation(shader, "lightRad"),
            .loc_nLights = rl.getShaderLocation(shader, "nLights"),
            .loc_sun = rl.getShaderLocation(shader, "sunDir"),
            .loc_key = rl.getShaderLocation(shader, "keyCol"),
            .loc_ambGround = rl.getShaderLocation(shader, "ambGround"),
            .loc_ambSky = rl.getShaderLocation(shader, "ambSky"),
            .loc_haze = rl.getShaderLocation(shader, "hazeColor"),
            .loc_hazeBank = rl.getShaderLocation(shader, "hazeBank"),
            .loc_keyAmt = rl.getShaderLocation(shader, "keyAmt"),
            .loc_hazeD = rl.getShaderLocation(shader, "hazeDensity"),
            .loc_hazeScale = rl.getShaderLocation(shader, "hazeScale"),
        };
        out.setHour(daynight.SHOT_HOUR, 0, 1.0, 0);
        return out;
    }

    /// The ONE writer of `gfx.sun`/`gfx.sunReach`, keeping the shader key, the shadow camera and `env`'s depth
    /// cull one source. Called once a frame, before either pass.
    ///
    /// **THE STORM IS A LAYER ON TOP** (`daynight.overcast`, owner: affect lighting depending on weather). `wet` is `weather.Weather.rain()`, 0 leaving the hour's palette untouched; `fogK` is the DEBUG haze override, 1 in the game; `spore` turns the distance PEACH and shortens it.
    pub fn setHour(self: *Scene, hour: f32, wet: f32, fogK: f32, spore: f32) void {
        const p = daynight.bloom(daynight.overcast(daynight.paletteAt(hour), wet), spore);
        sun = daynight.keyDir(hour);
        sunReach = daynight.shadowReach(hour);
        var d = sun;
        rl.setShaderValue(self.shader, self.loc_sun, &d, .vec3);
        var key = p.key;
        rl.setShaderValue(self.shader, self.loc_key, &key, .vec3);
        var ag = p.ambGround;
        rl.setShaderValue(self.shader, self.loc_ambGround, &ag, .vec3);
        var as_ = p.ambSky;
        rl.setShaderValue(self.shader, self.loc_ambSky, &as_, .vec3);
        var hz = p.haze;
        rl.setShaderValue(self.shader, self.loc_haze, &hz, .vec3);
        var hb = p.hazeBank;
        rl.setShaderValue(self.shader, self.loc_hazeBank, &hb, .vec3);
        var ka = daynight.keyAmt(p);
        rl.setShaderValue(self.shader, self.loc_keyAmt, &ka, .float);
        var density: f32 = HAZE_DENSITY * (1.0 + (HAZE_STORM - 1.0) * mathx.clampF(wet, 0, 1)) *
            (1.0 + (daynight.HAZE_SPORE_D - 1.0) * mathx.clampF(spore, 0, 1)) * mathx.maxF(fogK, 0);
        rl.setShaderValue(self.shader, self.loc_hazeD, &density, .float);
    }

    /// `span` is the width of the ortho box in metres — `SHADOW_ORTHO` in play, wider as the editor pulls
    /// back. The camera's distance and both clip planes ride it, so the depth slab stays the same +-0.78 span
    /// around the focus at every width and the shader's NDC bias keeps costing the same 16.6 texels.
    pub fn beginShadowPass(self: *Scene, focus: rl.Vector3, span: f32) void {
        shadowSpan = mathx.clampF(span, SHADOW_ORTHO, SHADOW_SPAN_MAX);
        const dist = SHADOW_NEAR + shadowSpan * SHADOW_DEPTH;
        const t = shadowSpan / @as(f32, SHADOWMAP_RES);
        const b = lightBasis();
        const a0 = @round(dot3(focus, b.right) / t) * t;
        const a1 = @round(dot3(focus, b.up) / t) * t;
        const a2 = dot3(focus, b.fwd);
        const f = mathx.addV(mathx.addV(mathx.scaleV(b.right, a0), mathx.scaleV(b.up, a1)), mathx.scaleV(b.fwd, a2));
        const cam = rl.Camera3D{
            .position = v3(f.x + sun.x * dist, f.y + sun.y * dist, f.z + sun.z * dist),
            .target = f,
            .up = b.up,
            .fovy = shadowSpan,
            .projection = .orthographic,
        };
        self.saved_near = rl.gl.rlGetCullDistanceNear();
        self.saved_far = rl.gl.rlGetCullDistanceFar();
        rl.gl.rlSetClipPlanes(SHADOW_NEAR, dist + shadowSpan * SHADOW_DEPTH);
        rl.beginTextureMode(self.shadowMap);
        rl.clearBackground(rl.Color.white);
        rl.beginMode3D(cam);
        self.lightVP = rl.math.matrixMultiply(rl.gl.rlGetMatrixModelview(), rl.gl.rlGetMatrixProjection());
    }

    pub fn endShadowPass(self: *Scene) void {
        rl.endMode3D();
        rl.endTextureMode();
        rl.gl.rlSetClipPlanes(self.saved_near, self.saved_far);
    }

    pub fn bind(self: *Scene, camPos: rl.Vector3) void {
        rl.gl.rlActiveTextureSlot(SLOT_SHADOW);
        rl.gl.rlEnableTexture(self.shadowMap.depth.id);
        rl.gl.rlActiveTextureSlot(0);
        self.bindSoil();
        rl.setShaderValueMatrix(self.shader, self.loc_lightVP, self.lightVP);
        var cp = camPos;
        rl.setShaderValue(self.shader, self.loc_camPos, &cp, .vec3);
        var t: f32 = @floatCast(rl.getTime());
        rl.setShaderValue(self.shader, self.loc_time, &t, .float);
    }

    /// TAKE CAST SHADOWS OFF the draws that follow, until the next `bind`. The translate ALONE left a live 2 m box at the origin whose fragments still passed the shader's in-range test and sampled a stale depth map; the zero scale collapses every world point out of range.
    pub fn shadowsOff(self: *Scene) void {
        const kill = rl.math.matrixMultiply(rl.math.matrixScale(0, 0, 0), rl.math.matrixTranslate(0, 0, 5));
        rl.setShaderValueMatrix(self.shader, self.loc_lightVP, kill);
    }

    pub fn setLights(self: *Scene, lights: []const Light) void {
        var pos: [MAX_LIGHTS * 3]f32 = undefined;
        var col: [MAX_LIGHTS * 3]f32 = undefined;
        var rad: [MAX_LIGHTS]f32 = undefined;
        const n = @min(lights.len, MAX_LIGHTS);
        for (lights[0..n], 0..) |l, i| {
            pos[i * 3 + 0] = l.pos.x;
            pos[i * 3 + 1] = l.pos.y;
            pos[i * 3 + 2] = l.pos.z;
            col[i * 3 + 0] = l.col.x;
            col[i * 3 + 1] = l.col.y;
            col[i * 3 + 2] = l.col.z;
            rad[i] = l.radius;
        }
        var ni: i32 = @intCast(n);
        rl.setShaderValue(self.shader, self.loc_nLights, &ni, .int);
        if (n == 0) return;
        rl.setShaderValueV(self.shader, self.loc_lightPos, &pos, .vec3, ni);
        rl.setShaderValueV(self.shader, self.loc_lightCol, &col, .vec3, ni);
        rl.setShaderValueV(self.shader, self.loc_lightRad, &rad, .float, ni);
    }

    pub fn setGround(self: *Scene, on: bool) void {
        var m: i32 = if (on) 1 else 0;
        rl.setShaderValue(self.shader, self.loc_ground, &m, .int);
    }

    /// `field` is the plain signed distance and `edge` the PACKED coast-shape-plus-liquid byte, already dilated
    /// (`env.dilateWaterEdge`). **THE SHAPE IS APPLIED PER FRAGMENT NOW** and is no longer baked into `field`,
    /// which survives being sampled.
    pub fn setWater(self: *Scene, field: []const u8, edge: []const u8, half: f32, any: bool) void {
        const n: usize = @intCast(WATER_N);
        std.debug.assert(field.len == n * n);
        std.debug.assert(edge.len == field.len);
        rl.updateTexture(self.waterTex, field.ptr);
        rl.updateTexture(self.waterEdgeTex, edge.ptr);
        var on: i32 = if (any) 1 else 0;
        rl.setShaderValue(self.shader, self.loc_waterOn, &on, .int);
        var h = half;
        rl.setShaderValue(self.shader, self.loc_waterHalf, &h, .float);
        var cell = 2.0 * half / @as(f32, @floatFromInt(WATER_N));
        rl.setShaderValue(self.shader, self.loc_waterCell, &cell, .float);
    }

    /// `tones` is shallow/mid/deep for every `wf.Liquid`, flat and in its order (`props.LIQUID_TONES`) — the
    /// sheet picks per fragment off the packed edge byte, so one draw covers a tarn and a lava run at once.
    pub fn setWaterSheet(self: *Scene, on: bool, tones: [LIQUID_N * 3]rl.Vector3) void {
        var v: i32 = if (on) 1 else 0;
        rl.setShaderValue(self.shader, self.loc_waterSheet, &v, .int);
        if (!on) return;
        var t = tones;
        rl.setShaderValueV(self.shader, self.loc_liquidTone, &t, .vec3, LIQUID_N * 3);
    }

var soilEdgeDilated: [@as(usize, @intCast(SOIL_N)) * @as(usize, @intCast(SOIL_N))]u8 = undefined;

/// **THE BARE SIDE OF A BOUNDARY ANSWERS WITH THE PAINTED SIDE'S POLICY.** Without it a tiled courtyard is
/// tiled looking out and soft looking in - and a coast is read from OUTSIDE the water as often as from in it.
/// One walk for both grids; `ids` is whatever counts as painted on that grid. The soil's runs at upload and is
/// the GPU's alone; the water's is `env.dilateWaterEdge`, which HOLDS its result because the footing reads it
/// too — so this is public, and there is not a second copy of the walk over there.
pub fn dilateEdges(out: []u8, n: usize, ids: []const u8, edge: []const u8) []const u8 {
    @memcpy(out, edge);
    for (0..n) |z| {
        for (0..n) |x| {
            const i = z * n + x;
            if (ids[i] != 0) continue;
            const nb = [4]?usize{
                if (x > 0) i - 1 else null,
                if (x + 1 < n) i + 1 else null,
                if (z > 0) i - n else null,
                if (z + 1 < n) i + n else null,
            };
            for (nb) |maybe| {
                const j = maybe orelse continue;
                if (ids[j] == 0) continue;
                out[i] = edge[j];
                break;
            }
        }
    }
    return out;
}

    pub fn setSoil(self: *Scene, ids: []const u8, cov: []const u8, edge: []const u8, half: f32) void {
        const n: usize = @intCast(SOIL_N);
        std.debug.assert(ids.len == n * n);
        std.debug.assert(cov.len == ids.len);
        std.debug.assert(edge.len == ids.len);
        rl.updateTexture(self.soilTex, ids.ptr);
        rl.updateTexture(self.soilCovTex, cov.ptr);
        rl.updateTexture(self.soilEdgeTex, dilateEdges(&soilEdgeDilated, n, ids, edge).ptr);
        var painted: i32 = 0;
        for (ids) |v| {
            if (v != 0) {
                painted = 1;
                break;
            }
        }
        rl.setShaderValue(self.shader, self.loc_soilOn, &painted, .int);
        var h = half;
        rl.setShaderValue(self.shader, self.loc_soilHalf, &h, .float);
        var cell = 2.0 * half / @as(f32, @floatFromInt(SOIL_N));
        rl.setShaderValue(self.shader, self.loc_soilCell, &cell, .float);
    }

    fn bindSoil(self: *Scene) void {
        rl.gl.rlActiveTextureSlot(SLOT_SOIL);
        rl.gl.rlEnableTexture(self.soilTex.id);
        rl.gl.rlActiveTextureSlot(SLOT_WATER);
        rl.gl.rlEnableTexture(self.waterTex.id);
        rl.gl.rlActiveTextureSlot(SLOT_SOILCOV);
        rl.gl.rlEnableTexture(self.soilCovTex.id);
        rl.gl.rlActiveTextureSlot(SLOT_SOILEDGE);
        rl.gl.rlEnableTexture(self.soilEdgeTex.id);
        rl.gl.rlActiveTextureSlot(SLOT_WATEREDGE);
        rl.gl.rlEnableTexture(self.waterEdgeTex.id);
        rl.gl.rlActiveTextureSlot(0);
    }

    pub fn setWind(self: *Scene, on: bool) void {
        var a: f32 = if (on) 1.0 else 0.0;
        rl.setShaderValue(self.shader, self.loc_windAmt, &a, .float);
    }

    pub fn setFlash(self: *Scene, amt: f32) void {
        var a = mathx.clampF(amt, 0, 1);
        rl.setShaderValue(self.shader, self.loc_flash, &a, .float);
    }

    pub fn setFrost(self: *Scene, amt: f32) void {
        var a = mathx.clampF(amt, 0, 1);
        rl.setShaderValue(self.shader, self.loc_frost, &a, .float);
    }

    /// A PER-DRAW share of the world's haze, 1 for everything but the birds. Paired like `beginFade`: whatever
    /// turns it down puts it back, or the next thing drawn comes out of the distance too clean.
    pub fn setHaze(self: *Scene, amt: f32) void {
        var a = mathx.clampF(amt, 0, 1);
        rl.setShaderValue(self.shader, self.loc_hazeScale, &a, .float);
    }

    pub fn setFade(self: *Scene, amt: f32) void {
        var a = mathx.clampF(amt, 0, 1);
        rl.setShaderValue(self.shader, self.loc_fade, &a, .float);
    }

    pub fn beginFade(self: *Scene, amt: f32) void {
        self.setFade(amt);
        rl.gl.rlDisableDepthMask();
    }
    pub fn endFade(self: *Scene) void {
        rl.gl.rlEnableDepthMask();
        self.setFade(1);
    }
};

pub const Mat = enum(u8) { plain, stone, wood, cloth, steel, leather, skin, hide, plant, water, marble, flame, smoke, ember, bark, fog, gilt };
comptime {
    // **THE HEAD IS PINNED AS WELL AS THE TAIL.** `water == 9` catches an INSERT below it, but the shader
    // branches on 1 through 8 too (`matAlbedo`), and a reorder inside that run leaves water where it is —
    // stone would silently come out as wood.
    std.debug.assert(@intFromEnum(Mat.stone) == 1);
    std.debug.assert(@intFromEnum(Mat.wood) == 2);
    std.debug.assert(@intFromEnum(Mat.cloth) == 3);
    std.debug.assert(@intFromEnum(Mat.steel) == 4);
    std.debug.assert(@intFromEnum(Mat.leather) == 5);
    std.debug.assert(@intFromEnum(Mat.skin) == 6);
    std.debug.assert(@intFromEnum(Mat.hide) == 7);
    std.debug.assert(@intFromEnum(Mat.plant) == 8);
    std.debug.assert(@intFromEnum(Mat.water) == 9);
    std.debug.assert(@intFromEnum(Mat.marble) == 10);
    std.debug.assert(@intFromEnum(Mat.flame) == 11);
    std.debug.assert(@intFromEnum(Mat.smoke) == 12);
    std.debug.assert(@intFromEnum(Mat.ember) == 13);
    std.debug.assert(@intFromEnum(Mat.bark) == 14);
    std.debug.assert(@intFromEnum(Mat.fog) == 15);
    // GOLD IS NOT STEEL WITH A YELLOW ALBEDO: the steel branch answers with a near-white glint and a COOL sky fresnel, and gold under it reads as blued silver at every edge.
    std.debug.assert(@intFromEnum(Mat.gilt) == 16);
}

pub fn smokeAnim(originY: f32, phase01: f32) f32 {
    return @floor(originY) + mathx.clampF(phase01, 0, 0.999);
}

pub fn material(shader: rl.Shader, comptime what: []const u8) rl.Material {
    var mat = rl.loadMaterialDefault() catch @panic(what ++ " material");
    mat.shader = shader;
    return mat;
}

pub const Builder = struct {
    pos: std.ArrayList(f32),
    nrm: std.ArrayList(f32),
    uv: std.ArrayList(f32),
    uv2: std.ArrayList(f32),
    col: std.ArrayList(u8),
    matf: f32 = 0,
    animY: f32 = 0,
    shapeN: f32 = 0,

    pub fn init() Builder {
        return .{
            .pos = std.ArrayList(f32).init(alloc),
            .nrm = std.ArrayList(f32).init(alloc),
            .uv = std.ArrayList(f32).init(alloc),
            .uv2 = std.ArrayList(f32).init(alloc),
            .col = std.ArrayList(u8).init(alloc),
        };
    }

    pub fn setMat(self: *Builder, m: Mat) void {
        self.matf = @floatFromInt(@intFromEnum(m));
    }

    pub fn setAnimY(self: *Builder, y: f32) void {
        self.animY = y;
    }

    fn shapeOff(self: *Builder) rl.Vector2 {
        self.shapeN += 1;
        return .{ .x = self.shapeN * 3.71, .y = self.shapeN * 7.13 };
    }

    fn vert(self: *Builder, p: rl.Vector3, n: rl.Vector3, c: rl.Color, u: f32, v: f32) void {
        self.pos.appendSlice(&.{ p.x, p.y, p.z }) catch @panic("oom");
        self.nrm.appendSlice(&.{ n.x, n.y, n.z }) catch @panic("oom");
        self.uv.appendSlice(&.{ u, v }) catch @panic("oom");
        self.uv2.appendSlice(&.{ self.matf, self.animY }) catch @panic("oom");
        self.col.appendSlice(&.{ c.r, c.g, c.b, c.a }) catch @panic("oom");
    }

    fn quadUV(self: *Builder, a: rl.Vector3, b: rl.Vector3, c: rl.Vector3, d: rl.Vector3, n: rl.Vector3, col: rl.Color, ta: rl.Vector2, tb: rl.Vector2, tc: rl.Vector2, td: rl.Vector2) void {
        self.vert(a, n, col, ta.x, ta.y);
        self.vert(b, n, col, tb.x, tb.y);
        self.vert(c, n, col, tc.x, tc.y);
        self.vert(a, n, col, ta.x, ta.y);
        self.vert(c, n, col, tc.x, tc.y);
        self.vert(d, n, col, td.x, td.y);
    }

    pub fn quadSmooth(self: *Builder, a: rl.Vector3, b: rl.Vector3, c: rl.Vector3, d: rl.Vector3, na: rl.Vector3, nb: rl.Vector3, nc: rl.Vector3, nd: rl.Vector3, col: rl.Color) void {
        self.vert(a, na, col, a.x, a.z);
        self.vert(b, nb, col, b.x, b.z);
        self.vert(c, nc, col, c.x, c.z);
        self.vert(a, na, col, a.x, a.z);
        self.vert(c, nc, col, c.x, c.z);
        self.vert(d, nd, col, d.x, d.z);
    }

    pub fn quadFade(self: *Builder, a: rl.Vector3, b: rl.Vector3, c: rl.Vector3, d: rl.Vector3, n: rl.Vector3, ab: rl.Color, cd: rl.Color) void {
        self.vert(a, n, ab, a.x, a.z);
        self.vert(b, n, ab, b.x, b.z);
        self.vert(c, n, cd, c.x, c.z);
        self.vert(a, n, ab, a.x, a.z);
        self.vert(c, n, cd, c.x, c.z);
        self.vert(d, n, cd, d.x, d.z);
    }

    /// `quadFade` with the ANIM channel graded across the cell as well. The fog gate's height fraction rides `animY` and is read by both the vertex billow and the fade — constant per cell it steps, and a sheet that fades in stripes is a sheet with nine edges in it.
    pub fn quadFadeAnim(self: *Builder, a: rl.Vector3, b: rl.Vector3, c: rl.Vector3, d: rl.Vector3, n: rl.Vector3, ab: rl.Color, cd: rl.Color, animAB: f32, animCD: f32) void {
        const keep = self.animY;
        self.animY = animAB;
        self.vert(a, n, ab, a.x, a.z);
        self.vert(b, n, ab, b.x, b.z);
        self.animY = animCD;
        self.vert(c, n, cd, c.x, c.z);
        self.animY = animAB;
        self.vert(a, n, ab, a.x, a.z);
        self.animY = animCD;
        self.vert(c, n, cd, c.x, c.z);
        self.vert(d, n, cd, d.x, d.z);
        self.animY = keep;
    }

    pub fn quad(self: *Builder, a: rl.Vector3, b: rl.Vector3, c: rl.Vector3, d: rl.Vector3, n: rl.Vector3, col: rl.Color) void {
        const ue = norm3(v3(b.x - a.x, b.y - a.y, b.z - a.z));
        const ve = cross(n, ue);
        const o = self.shapeOff();
        const t = struct {
            fn uv(p: rl.Vector3, aa: rl.Vector3, u: rl.Vector3, v: rl.Vector3, off: rl.Vector2) rl.Vector2 {
                const dx = p.x - aa.x;
                const dy = p.y - aa.y;
                const dz = p.z - aa.z;
                return .{ .x = dx * u.x + dy * u.y + dz * u.z + off.x, .y = dx * v.x + dy * v.y + dz * v.z + off.y };
            }
        }.uv;
        self.quadUV(a, b, c, d, n, col, t(a, a, ue, ve, o), t(b, a, ue, ve, o), t(c, a, ue, ve, o), t(d, a, ue, ve, o));
    }

    pub fn addCube(self: *Builder, c: rl.Vector3, size: rl.Vector3, col: rl.Color) void {
        const hx = size.x / 2;
        const hy = size.y / 2;
        const hz = size.z / 2;
        const x = c.x;
        const y = c.y;
        const z = c.z;
        self.quad(v3(x + hx, y - hy, z - hz), v3(x + hx, y + hy, z - hz), v3(x + hx, y + hy, z + hz), v3(x + hx, y - hy, z + hz), v3(1, 0, 0), col);
        self.quad(v3(x - hx, y - hy, z + hz), v3(x - hx, y + hy, z + hz), v3(x - hx, y + hy, z - hz), v3(x - hx, y - hy, z - hz), v3(-1, 0, 0), col);
        self.quad(v3(x - hx, y + hy, z - hz), v3(x - hx, y + hy, z + hz), v3(x + hx, y + hy, z + hz), v3(x + hx, y + hy, z - hz), v3(0, 1, 0), col);
        self.quad(v3(x - hx, y - hy, z + hz), v3(x - hx, y - hy, z - hz), v3(x + hx, y - hy, z - hz), v3(x + hx, y - hy, z + hz), v3(0, -1, 0), col);
        self.quad(v3(x - hx, y - hy, z + hz), v3(x + hx, y - hy, z + hz), v3(x + hx, y + hy, z + hz), v3(x - hx, y + hy, z + hz), v3(0, 0, 1), col);
        self.quad(v3(x + hx, y - hy, z - hz), v3(x - hx, y - hy, z - hz), v3(x - hx, y + hy, z - hz), v3(x + hx, y + hy, z - hz), v3(0, 0, -1), col);
    }

    pub fn addBox(self: *Builder, c: rl.Vector3, ax: rl.Vector3, ay: rl.Vector3, azIn: rl.Vector3, col: rl.Color) void {
        const x = cross(ax, ay);
        const az = if (x.x * azIn.x + x.y * azIn.y + x.z * azIn.z < 0) neg(azIn) else azIn;
        const corner = struct {
            fn at(cc: rl.Vector3, xx: rl.Vector3, y: rl.Vector3, z: rl.Vector3, sx: f32, sy: f32, sz: f32) rl.Vector3 {
                return v3(cc.x + xx.x * sx + y.x * sy + z.x * sz, cc.y + xx.y * sx + y.y * sy + z.y * sz, cc.z + xx.z * sx + y.z * sy + z.z * sz);
            }
        }.at;
        self.quad(corner(c, ax, ay, az, 1, -1, -1), corner(c, ax, ay, az, 1, 1, -1), corner(c, ax, ay, az, 1, 1, 1), corner(c, ax, ay, az, 1, -1, 1), norm3(ax), col);
        self.quad(corner(c, ax, ay, az, -1, -1, 1), corner(c, ax, ay, az, -1, 1, 1), corner(c, ax, ay, az, -1, 1, -1), corner(c, ax, ay, az, -1, -1, -1), norm3(neg(ax)), col);
        self.quad(corner(c, ax, ay, az, -1, 1, -1), corner(c, ax, ay, az, -1, 1, 1), corner(c, ax, ay, az, 1, 1, 1), corner(c, ax, ay, az, 1, 1, -1), norm3(ay), col);
        self.quad(corner(c, ax, ay, az, -1, -1, 1), corner(c, ax, ay, az, -1, -1, -1), corner(c, ax, ay, az, 1, -1, -1), corner(c, ax, ay, az, 1, -1, 1), norm3(neg(ay)), col);
        self.quad(corner(c, ax, ay, az, -1, -1, 1), corner(c, ax, ay, az, 1, -1, 1), corner(c, ax, ay, az, 1, 1, 1), corner(c, ax, ay, az, -1, 1, 1), norm3(az), col);
        self.quad(corner(c, ax, ay, az, 1, -1, -1), corner(c, ax, ay, az, -1, -1, -1), corner(c, ax, ay, az, -1, 1, -1), corner(c, ax, ay, az, 1, 1, -1), norm3(neg(az)), col);
    }

    pub fn addCylinder(self: *Builder, a: rl.Vector3, b: rl.Vector3, ra: f32, rb: f32, sides: i32, col: rl.Color) void {
        const f = axisFrame(a, b);
        const o = self.shapeOff();
        const rmid = @max(0.5 * (ra + rb), 0.02);
        self.ringBand(a, b, f.u, f.w, ra, rb, sides, col, o, rmid, o.y, o.y + f.len);
    }

    fn ringBand(self: *Builder, a: rl.Vector3, b: rl.Vector3, u: rl.Vector3, w: rl.Vector3, ra: f32, rb: f32, sides: i32, col: rl.Color, o: rl.Vector2, rmid: f32, va: f32, vb: f32) void {
        const sf: f32 = @floatFromInt(sides);
        var s: i32 = 0;
        while (s < sides) : (s += 1) {
            const a0 = std.math.tau * @as(f32, @floatFromInt(s)) / sf;
            const a1 = std.math.tau * @as(f32, @floatFromInt(s + 1)) / sf;
            const d0 = dirOn(u, w, a0);
            const d1 = dirOn(u, w, a1);
            const p0 = scaleAdd(a, d0, ra);
            const p1 = scaleAdd(a, d1, ra);
            const p2 = scaleAdd(b, d1, rb);
            const p3 = scaleAdd(b, d0, rb);
            const nmid = norm3(v3(d0.x + d1.x, d0.y + d1.y, d0.z + d1.z));
            const arc0 = a0 * rmid + o.x;
            const arc1 = a1 * rmid + o.x;
            self.quadUV(p0, p1, p2, p3, nmid, col, .{ .x = arc0, .y = va }, .{ .x = arc1, .y = va }, .{ .x = arc1, .y = vb }, .{ .x = arc0, .y = vb });
        }
    }

    pub fn addCapsule(self: *Builder, a: rl.Vector3, b: rl.Vector3, ra: f32, rb: f32, sides: i32, col: rl.Color) void {
        const f = axisFrame(a, b);
        const o = self.shapeOff();
        const rmid = @max(0.5 * (ra + rb), 0.02);
        self.ringBand(a, b, f.u, f.w, ra, rb, sides, col, o, rmid, o.y, o.y + f.len);
        self.dome(a, neg(f.axis), f.u, f.w, ra, sides, col, o, rmid, o.y, -1);
        self.dome(b, f.axis, f.u, f.w, rb, sides, col, o, rmid, o.y + f.len, 1);
    }

    pub fn addDome(self: *Builder, c: rl.Vector3, dir: rl.Vector3, r: f32, sides: i32, col: rl.Color) void {
        const f = axisFrame(c, scaleAdd(c, norm3(dir), @max(r, 1e-3)));
        const o = self.shapeOff();
        self.dome(c, f.axis, f.u, f.w, r, sides, col, o, @max(r, 0.02), o.y, 1);
    }

    fn dome(self: *Builder, c: rl.Vector3, dir: rl.Vector3, u: rl.Vector3, w: rl.Vector3, r: f32, sides: i32, col: rl.Color, o: rl.Vector2, rmid: f32, vAt: f32, vSign: f32) void {
        if (r < 1e-4) return;
        const BANDS = 3;
        var k: i32 = BANDS;
        while (k > 0) : (k -= 1) {
            const t0 = std.math.pi * 0.5 * @as(f32, @floatFromInt(k)) / @as(f32, BANDS);
            const t1 = std.math.pi * 0.5 * @as(f32, @floatFromInt(k - 1)) / @as(f32, BANDS);
            const c0 = scaleAdd(c, dir, r * mathx.sinf(t0));
            const c1 = scaleAdd(c, dir, r * mathx.sinf(t1));
            const v0 = vAt + vSign * r * t0;
            const v1 = vAt + vSign * r * t1;
            if (vSign > 0) {
                self.ringBand(c1, c0, u, w, r * mathx.cosf(t1), r * mathx.cosf(t0), sides, col, o, rmid, v1, v0);
            } else {
                self.ringBand(c0, c1, u, w, r * mathx.cosf(t0), r * mathx.cosf(t1), sides, col, o, rmid, v0, v1);
            }
        }
    }

    /// **A GARMENT THAT HANGS OFF A BODY** — a ring of thin panels from `rTop` out to `rBot` over `drop`, each
    /// wobbled and sagged on the caller's own seeded stream so the hem is uneven (WABI-SABI). Panels are thin
    /// WALLS AT THE RIM: `addBox` takes HALF-axes, so a radial extent of `(rTop - rBot)/2` centred on the mean
    /// radius spans one to the other, and writing the extents instead gives every panel a solid pie slice.
    pub fn addSkirt(self: *Builder, c: rl.Vector3, rTop: f32, drop: f32, rBot: f32, thick: f32, sides: i32, col: rl.Color, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < sides) : (i += 1) {
            const a0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sides)) * std.math.tau;
            const a1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(sides)) * std.math.tau;
            const am = (a0 + a1) * 0.5;
            const rb = rBot * rng.range(0.88, 1.12);
            const fall = drop * rng.range(0.90, 1.10);
            const mid = (rTop + rb) * 0.5;
            const half = (a1 - a0) * 0.5;
            self.addBox(
                v3(c.x + mathx.cosf(am) * mid, c.y - fall * 0.5, c.z + mathx.sinf(am) * mid),
                v3(mathx.cosf(am) * thick, 0, mathx.sinf(am) * thick),
                v3(mathx.cosf(am) * (rTop - rb) * 0.5, fall * 0.5, mathx.sinf(am) * (rTop - rb) * 0.5),
                v3(-mathx.sinf(am) * mid * half * 1.25, 0, mathx.cosf(am) * mid * half * 1.25),
                col,
            );
        }
    }

    pub fn addBlob(self: *Builder, c: rl.Vector3, r: rl.Vector3, segs: i32, sides: i32, col: rl.Color) void {
        const o = self.shapeOff();
        const sf: f32 = @floatFromInt(sides);
        const gf: f32 = @floatFromInt(segs);
        const rmid = @max((r.x + r.z) * 0.5, 0.02);
        const inv = v3(1.0 / @max(r.x, 1e-4), 1.0 / @max(r.y, 1e-4), 1.0 / @max(r.z, 1e-4));
        var j: i32 = 0;
        while (j < segs) : (j += 1) {
            const t0 = std.math.pi * @as(f32, @floatFromInt(j)) / gf;
            const t1 = std.math.pi * @as(f32, @floatFromInt(j + 1)) / gf;
            var s: i32 = 0;
            while (s < sides) : (s += 1) {
                const a0 = std.math.tau * @as(f32, @floatFromInt(s)) / sf;
                const a1 = std.math.tau * @as(f32, @floatFromInt(s + 1)) / sf;
                const p0 = onBlob(c, r, t0, a0);
                const p1 = onBlob(c, r, t0, a1);
                const p2 = onBlob(c, r, t1, a1);
                const p3 = onBlob(c, r, t1, a0);
                const g = v3((0.25 * (p0.x + p1.x + p2.x + p3.x) - c.x) * inv.x * inv.x, (0.25 * (p0.y + p1.y + p2.y + p3.y) - c.y) * inv.y * inv.y, (0.25 * (p0.z + p1.z + p2.z + p3.z) - c.z) * inv.z * inv.z);
                self.quadUV(p0, p1, p2, p3, norm3(g), col, .{ .x = a0 * rmid + o.x, .y = o.y + t0 * r.y }, .{ .x = a1 * rmid + o.x, .y = o.y + t0 * r.y }, .{ .x = a1 * rmid + o.x, .y = o.y + t1 * r.y }, .{ .x = a0 * rmid + o.x, .y = o.y + t1 * r.y });
            }
        }
    }

    /// A superquadric box. The point is what it does NOT move: the six faces stay in exactly `addCube`'s planes, so measured extents are unchanged while the edges round off. `round` 0..1 — 1 is a plain ellipsoid, ~0.3 a block taken to with a file. Takes a FULL `size` like `addCube` and unlike `addBlob`.
    pub fn addRoundBox(self: *Builder, c: rl.Vector3, size: rl.Vector3, round: f32, segs: i32, sides: i32, col: rl.Color) void {
        const h = v3(@abs(size.x) * 0.5, @abs(size.y) * 0.5, @abs(size.z) * 0.5);
        if (h.x < 1e-5 or h.y < 1e-5 or h.z < 1e-5) return;
        const e = mathx.clampF(round, 0.02, 1.0);
        const o = self.shapeOff();
        const sf: f32 = @floatFromInt(@max(sides, 4));
        const gf: f32 = @floatFromInt(@max(segs, 2));
        const nseg = @max(segs, 2);
        const nside = @max(sides, 4);
        var j: i32 = 0;
        while (j < nseg) : (j += 1) {
            const t0 = std.math.pi * @as(f32, @floatFromInt(j)) / gf;
            const t1 = std.math.pi * @as(f32, @floatFromInt(j + 1)) / gf;
            var s: i32 = 0;
            while (s < nside) : (s += 1) {
                const a0 = std.math.tau * @as(f32, @floatFromInt(s)) / sf;
                const a1 = std.math.tau * @as(f32, @floatFromInt(s + 1)) / sf;
                const p0 = onSquircle(c, h, e, t0, a0);
                const p1 = onSquircle(c, h, e, t0, a1);
                const p2 = onSquircle(c, h, e, t1, a1);
                const p3 = onSquircle(c, h, e, t1, a0);
                const mid = v3(
                    0.25 * (p0.x + p1.x + p2.x + p3.x) - c.x,
                    0.25 * (p0.y + p1.y + p2.y + p3.y) - c.y,
                    0.25 * (p0.z + p1.z + p2.z + p3.z) - c.z,
                );
                const n = squircleNormal(h, e, mid);
                self.quadUV(p0, p1, p2, p3, n, col, boxUV(p0, c, n, o), boxUV(p1, c, n, o), boxUV(p2, c, n, o), boxUV(p3, c, n, o));
            }
        }
    }

    pub fn toMesh(self: *Builder) rl.Mesh {
        const pos = self.pos.toOwnedSlice() catch @panic("oom");
        const nrm = self.nrm.toOwnedSlice() catch @panic("oom");
        const uv = self.uv.toOwnedSlice() catch @panic("oom");
        const uv2 = self.uv2.toOwnedSlice() catch @panic("oom");
        const col = self.col.toOwnedSlice() catch @panic("oom");
        var mesh = std.mem.zeroes(rl.Mesh);
        mesh.vertexCount = @intCast(pos.len / 3);
        mesh.triangleCount = @intCast(pos.len / 9);
        mesh.vertices = pos.ptr;
        mesh.normals = nrm.ptr;
        mesh.texcoords = uv.ptr;
        mesh.texcoords2 = uv2.ptr;
        mesh.colors = col.ptr;
        rl.uploadMesh(&mesh, false);
        return mesh;
    }

    pub fn toModel(self: *Builder, shader: rl.Shader) rl.Model {
        const mesh = self.toMesh();
        var model = rl.loadModelFromMesh(mesh) catch @panic("model");
        model.materials[0].shader = shader;
        return model;
    }

    /// For a builder that never reaches `toMesh`, which is otherwise the only release: it hands the five
    /// arrays to raylib.
    pub fn deinit(self: *Builder) void {
        self.pos.deinit();
        self.nrm.deinit();
        self.uv.deinit();
        self.uv2.deinit();
        self.col.deinit();
    }
};

fn scaleAdd(base: rl.Vector3, dir: rl.Vector3, s: f32) rl.Vector3 {
    return v3(base.x + dir.x * s, base.y + dir.y * s, base.z + dir.z * s);
}
const AxisFrame = struct { axis: rl.Vector3, u: rl.Vector3, w: rl.Vector3, len: f32 };
fn axisFrame(a: rl.Vector3, b: rl.Vector3) AxisFrame {
    const d = v3(b.x - a.x, b.y - a.y, b.z - a.z);
    const axis = norm3(d);
    const seed = if (@abs(axis.y) < 0.99) v3(0, 1, 0) else v3(1, 0, 0);
    const u = norm3(cross(axis, seed));
    return .{ .axis = axis, .u = u, .w = norm3(cross(axis, u)), .len = @sqrt(d.x * d.x + d.y * d.y + d.z * d.z) };
}
fn onBlob(c: rl.Vector3, r: rl.Vector3, t: f32, ang: f32) rl.Vector3 {
    const st = mathx.sinf(t);
    return v3(c.x - r.x * mathx.sinf(ang) * st, c.y - r.y * mathx.cosf(t), c.z - r.z * mathx.cosf(ang) * st);
}

fn sgnPow(t: f32, p: f32) f32 {
    const a = @abs(t);
    if (a < 1e-6) return 0;
    const m = std.math.pow(f32, a, p);
    return if (t < 0) -m else m;
}

fn onSquircle(c: rl.Vector3, h: rl.Vector3, e: f32, t: f32, ang: f32) rl.Vector3 {
    const ring = sgnPow(mathx.sinf(t), e);
    return v3(
        c.x - h.x * sgnPow(mathx.sinf(ang), e) * ring,
        c.y - h.y * sgnPow(mathx.cosf(t), e),
        c.z - h.z * sgnPow(mathx.cosf(ang), e) * ring,
    );
}

fn boxUV(p: rl.Vector3, c: rl.Vector3, n: rl.Vector3, o: rl.Vector2) rl.Vector2 {
    const d = v3(p.x - c.x, p.y - c.y, p.z - c.z);
    const ax = @abs(n.x);
    const ay = @abs(n.y);
    const az = @abs(n.z);
    if (ax >= ay and ax >= az) return .{ .x = d.z + o.x, .y = d.y + o.y };
    if (ay >= az) return .{ .x = d.x + o.x, .y = d.z + o.y };
    return .{ .x = d.x + o.x, .y = d.y + o.y };
}

fn squircleNormal(h: rl.Vector3, e: f32, d: rl.Vector3) rl.Vector3 {
    const k = 2.0 / e - 1.0;
    return norm3(v3(
        sgnPow(d.x / h.x, k) / h.x,
        sgnPow(d.y / h.y, k) / h.y,
        sgnPow(d.z / h.z, k) / h.z,
    ));
}
fn dirOn(u: rl.Vector3, w: rl.Vector3, ang: f32) rl.Vector3 {
    const c = mathx.cosf(ang);
    const s = mathx.sinf(ang);
    return v3(u.x * c + w.x * s, u.y * c + w.y * s, u.z * c + w.z * s);
}
fn neg(a: rl.Vector3) rl.Vector3 {
    return v3(-a.x, -a.y, -a.z);
}
fn norm3(a: rl.Vector3) rl.Vector3 {
    const l = @sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
    if (l < 1e-6) return v3(0, 1, 0);
    return v3(a.x / l, a.y / l, a.z / l);
}
const cross = mathx.crossV;

test "THE CHAIN AND ITS INVERSE ARE ONE SOLVE — an albedo run through both comes back where it started" {
    // `albedoFor` is what a palette is authored with and `screenOf` is what an art test measures; drifting apart
    // they would each pass on their own while the two halves of the law disagreed.
    for ([_]f32{ 8, 22, 45, 76, 95, 109, 148 }) |albedo| {
        try std.testing.expectApproxEqAbs(albedo, albedoFor(screenOf(albedo)), 0.01);
    }
    // …and past the clip the chain is one-way: the key saturates at 255/1.72, so anything over that is white.
    const ceiling = 255.0 / KEY_HOT;
    try std.testing.expectApproxEqAbs(@as(f32, 255), screenOf(ceiling), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 255), screenOf(ceiling + 40), 0.01);
    std.debug.print(
        "\n  albedo chain: 76 -> screen {d:.0}, 109 -> {d:.0}; anything over albedo {d:.0} clips white\n",
        .{ screenOf(76), screenOf(109), ceiling },
    );
}

test "a FILLETED BOX stays inside the cube it replaces, and its normals point out" {
    const size = v3(0.4, 0.9, 0.3);
    const c = v3(1, 2, -3);
    var b = Builder.init();
    defer b.deinit();
    b.addRoundBox(c, size, 0.30, 6, 12, mathx.rgba(255, 255, 255, 255));
    try std.testing.expect(b.pos.items.len > 0);
    try std.testing.expectEqual(b.pos.items.len, b.nrm.items.len);
    var i: usize = 0;
    var reachX: f32 = 0;
    while (i < b.pos.items.len) : (i += 3) {
        const d = v3(b.pos.items[i] - c.x, b.pos.items[i + 1] - c.y, b.pos.items[i + 2] - c.z);
        try std.testing.expect(@abs(d.x) <= size.x * 0.5 + 1e-4);
        try std.testing.expect(@abs(d.y) <= size.y * 0.5 + 1e-4);
        try std.testing.expect(@abs(d.z) <= size.z * 0.5 + 1e-4);
        reachX = @max(reachX, @abs(d.x));
        const n = v3(b.nrm.items[i], b.nrm.items[i + 1], b.nrm.items[i + 2]);
        try std.testing.expectApproxEqAbs(@as(f32, 1), @sqrt(n.x * n.x + n.y * n.y + n.z * n.z), 1e-3);
        try std.testing.expect(n.x * d.x + n.y * d.y + n.z * d.z > -1e-3);
    }
    try std.testing.expect(reachX > size.x * 0.5 * 0.93);
}

test "the fillet dial spans ellipsoid to hard box" {
    const h = v3(1, 1, 1);
    const t = std.math.pi * 0.25;
    const soft = onSquircle(mathx.zero3, h, 1.0, t, std.math.pi * 0.25);
    const hard = onSquircle(mathx.zero3, h, 0.08, t, std.math.pi * 0.25);
    try std.testing.expectApproxEqAbs(@as(f32, 1), mathx.lenV(soft), 1e-3);
    try std.testing.expect(mathx.lenV(hard) > 1.5);
    try std.testing.expect(mathx.lenV(hard) < @sqrt(3.0) + 1e-3);
}

test "EVERY PROGRAM THAT USES THE NOISE BASIS DECLARES IT ONCE — spliced, not copied" {
    const count = struct {
        fn of(hay: []const u8, needle: []const u8) usize {
            var n: usize = 0;
            var at: usize = 0;
            while (std.mem.indexOfPos(u8, hay, at, needle)) |i| : (at = i + needle.len) n += 1;
            return n;
        }
    }.of;
    const DECL = "float hash21(vec2 p){";
    for ([_][]const u8{ glsl.sceneFS, glsl.skyFS, glsl.retroFS }) |src| {
        try std.testing.expectEqual(@as(usize, 1), count(src, DECL));
        // The splice has to leave the declaration on a line of its own, or it lands inside the `//` comment above it.
        const at = std.mem.indexOf(u8, src, DECL).?;
        try std.testing.expectEqual(@as(u8, '\n'), src[at - 1]);
    }
    // …and the two that call `vnoise` carry its definition, which only the shared source can give them.
    for ([_][]const u8{ glsl.sceneFS, glsl.skyFS }) |src| {
        try std.testing.expectEqual(@as(usize, 1), count(src, "float vnoise(vec2 p){"));
    }
    try std.testing.expectEqual(@as(usize, 0), count(glsl.retroFS, "float vnoise(vec2 p){"));
}
