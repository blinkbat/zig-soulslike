const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const glsl = @import("shaders.zig"); // the GLSL source text — see there for the contract between the two

const v3 = mathx.v3;


const alloc = std.heap.raw_c_allocator;

// Shadow sampler lives on a high texture slot raylib's default material never binds (it only uses slot 0 for albedo), so the per-frame bind survives drawModel/drawMesh.
const SLOT_SHADOW: i32 = 12;
const SLOT_SOIL: i32 = 13;
const SLOT_WATER: i32 = 14;
const SLOT_SOILCOV: i32 = 15;

pub const SOIL_N: i32 = 112;

/// THE WATER FIELD's resolution — finer than the soil's, because a coastline is a SHAPE you read and a patch of dirt is not. 224 over a 560 m map is 2.5 m a cell, and the field is BILINEAR (unlike the soil's ids, which must not interpolate), so the shoreline the shader draws is smooth well under a cell.
pub const WATER_N: i32 = 224;

pub const HEIGHT_N: i32 = 224;

pub const WATER_SHORE: u8 = 128;
/// Metres from the shore at which the water reads FULLY DEEP, and metres of soaked sand outside it.
pub const WATER_DEEP_AT: f32 = 11.0;
pub const WATER_WET_OUT: f32 = 3.4;

// THE SUN — one hard directional light.
pub const SUN_DIR = norm3(v3(-0.60, 0.50, -0.46));

pub const SHADOWMAP_RES = 8192;
pub const SHADOW_ORTHO = 108.0;
const SUN_DIST = 120.0; // shadow camera distance along SUN_DIR
// Depth slab around the casters, kept as TIGHT as the box allows.
const SHADOW_CLIP_NEAR = SUN_DIST - SHADOW_ORTHO * 0.78;
const SHADOW_CLIP_FAR = SUN_DIST + SHADOW_ORTHO * 0.78;

pub const HAZE = v3(0.078, 0.070, 0.056);
// Haze falloff: 1-exp(-density*dist).
const HAZE_DENSITY: f32 = 0.013;

pub const MAX_LIGHTS = 16;
comptime {
    // The scene FS declares `lightPos/lightCol/lightRad[16]` as literals
    @setEvalBranchQuota(200_000); // scanning a ~9 KB shader source three times at comptime
    std.debug.assert(MAX_LIGHTS == 16);
    std.debug.assert(std.mem.indexOf(u8, glsl.sceneFS, "lightPos[16]") != null);
    std.debug.assert(std.mem.indexOf(u8, glsl.sceneFS, "lightCol[16]") != null);
    std.debug.assert(std.mem.indexOf(u8, glsl.sceneFS, "lightRad[16]") != null);
}
pub const Light = struct {
    pos: rl.Vector3,
    col: rl.Vector3, // colour PRE-MULTIPLIED by intensity (pre-gamma, like every other colour here)
    radius: f32, // falloff reaches exactly zero here, so a light can never leak past its room
};

pub const Sky = struct {
    shader: rl.Shader,
    loc_fwd: i32,
    loc_right: i32,
    loc_up: i32,
    loc_res: i32,
    loc_dim: i32,

    pub fn init() Sky {
        const sh = rl.loadShaderFromMemory(glsl.skyVS, glsl.skyFS) catch @panic("sky shader");
        var sun = SUN_DIR;
        rl.setShaderValue(sh, rl.getShaderLocation(sh, "sunDir"), &sun, .vec3);
        var dimOff: f32 = 0;
        rl.setShaderValue(sh, rl.getShaderLocation(sh, "dim"), &dimOff, .float);
        return .{
            .shader = sh,
            .loc_fwd = rl.getShaderLocation(sh, "camFwd"),
            .loc_right = rl.getShaderLocation(sh, "camRightS"),
            .loc_up = rl.getShaderLocation(sh, "camUpS"),
            .loc_res = rl.getShaderLocation(sh, "resolution"),
            .loc_dim = rl.getShaderLocation(sh, "dim"),
        };
    }

    /// The scene shader's dusk dial, on the sky.
    pub fn setDim(self: *Sky, amt: f32) void {
        var a = mathx.clampF(amt, 0, 1);
        rl.setShaderValue(self.shader, self.loc_dim, &a, .float);
    }

    // Fullscreen quad through the sky shader.
    pub fn draw(self: *Sky, cam: rl.Camera3D) void {
        const w = rl.getScreenWidth();
        const h = rl.getScreenHeight();
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
        const MAX_A: f32 = 120.0; // corner darkness (0..255)
        var img = rl.genImageColor(W, H, rl.Color.init(0, 0, 0, 0));
        var y: i32 = 0;
        while (y < H) : (y += 1) {
            var x: i32 = 0;
            while (x < W) : (x += 1) {
                const nx = (@as(f32, @floatFromInt(x)) / (W - 1)) * 2.0 - 1.0;
                const ny = (@as(f32, @floatFromInt(y)) / (H - 1)) * 2.0 - 1.0;
                const r = @sqrt(nx * nx + ny * ny);
                const t = mathx.smoothstep(START, ENDR, r); // 0 in the clean centre → 1 at the corners
                const a = mathx.u8f(t * MAX_A);
                // A dark, faintly cool slate — darkens AND cools the rim in one wash.
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

pub const RETRO_COUNT = 15;
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
const RETRO_FILTERS = [RETRO_COUNT]RetroFilter{
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
    .{ .name = "Film Grain", .uniform = "fGrain", .default = 0.04 },
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

// The RF_* index constants must line up with RETRO_FILTERS' rows
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

    // Clear all filters, then enable the given preset's filters.
    pub fn applyPreset(self: *Retro, preset: []const Preset) void {
        self.allOff();
        for (preset) |p| self.values[p.idx] = p.val;
    }

    // Redirect the frame into the capture RT when any filter is on. true => the caller MUST call end() after its 3D pass; false => draw straight to the backbuffer.
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

/// A blank n x n single-byte texture, updated in place by the setters above.
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
    loc_fade: i32,
    loc_dim: i32,
    loc_lightPos: i32,
    loc_lightCol: i32,
    loc_lightRad: i32,
    loc_nLights: i32,
    soilTex: rl.Texture2D,
    soilCovTex: rl.Texture2D,
    loc_soilOn: i32,
    loc_soilHalf: i32,
    loc_soilCell: i32,
    waterTex: rl.Texture2D,
    loc_waterOn: i32,
    loc_waterHalf: i32,
    loc_waterSheet: i32,
    loc_waterTone: i32,
    saved_near: @TypeOf(rl.gl.rlGetCullDistanceNear()) = 0,
    saved_far: @TypeOf(rl.gl.rlGetCullDistanceFar()) = 0,

    pub fn init() Scene {
        const shader = rl.loadShaderFromMemory(glsl.sceneVS, glsl.sceneFS) catch @panic("scene shader");
        const depthShader = rl.loadShaderFromMemory(glsl.depthVS, glsl.depthFS) catch @panic("depth shader");
        var sun = SUN_DIR;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "sunDir"), &sun, .vec3);
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
        var waterOff: i32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "waterOn"), &waterOff, .int);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "waterSheet"), &waterOff, .int);
        var haze = HAZE;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "hazeColor"), &haze, .vec3);
        var density: f32 = HAZE_DENSITY;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "hazeDensity"), &density, .float);
        var windOff: f32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "windAmt"), &windOff, .float);
        var flashOff: f32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "hitFlash"), &flashOff, .float);
        var fadeOff: f32 = 1;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "fade"), &fadeOff, .float);
        var noLights: i32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "nLights"), &noLights, .int);
        var dimOff: f32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "dim"), &dimOff, .float);
        return .{
            .shader = shader,
            .depthShader = depthShader,
            .shadowMap = loadShadowmap(SHADOWMAP_RES),
            .soilTex = loadFieldTexture(SOIL_N, .point),
            .soilCovTex = loadFieldTexture(SOIL_N, .bilinear),
            .loc_soilOn = rl.getShaderLocation(shader, "soilOn"),
            .loc_soilHalf = rl.getShaderLocation(shader, "soilHalf"),
            .loc_soilCell = rl.getShaderLocation(shader, "soilCell"),
            .waterTex = loadFieldTexture(WATER_N, .bilinear),
            .loc_waterOn = rl.getShaderLocation(shader, "waterOn"),
            .loc_waterHalf = rl.getShaderLocation(shader, "waterHalf"),
            .loc_waterSheet = rl.getShaderLocation(shader, "waterSheet"),
            .loc_waterTone = rl.getShaderLocation(shader, "waterTone"),
            .lightVP = rl.math.matrixIdentity(),
            .loc_ground = rl.getShaderLocation(shader, "groundMode"),
            .loc_lightVP = rl.getShaderLocation(shader, "lightVP"),
            .loc_camPos = rl.getShaderLocation(shader, "camPos"),
            .loc_windAmt = rl.getShaderLocation(shader, "windAmt"),
            .loc_time = rl.getShaderLocation(shader, "uTime"),
            .loc_flash = rl.getShaderLocation(shader, "hitFlash"),
            .loc_fade = rl.getShaderLocation(shader, "fade"),
            .loc_dim = rl.getShaderLocation(shader, "dim"),
            .loc_lightPos = rl.getShaderLocation(shader, "lightPos"),
            .loc_lightCol = rl.getShaderLocation(shader, "lightCol"),
            .loc_lightRad = rl.getShaderLocation(shader, "lightRad"),
            .loc_nLights = rl.getShaderLocation(shader, "nLights"),
        };
    }

    // Sun depth pass: call, draw casters (materials swapped to depthShader — drawMesh uses the MATERIAL's shader, beginShaderMode won't reach it), then endShadowPass; must run BEFORE beginDrawing.
    pub fn beginShadowPass(self: *Scene, focus: rl.Vector3) void {
        const t = SHADOW_ORTHO / @as(f32, SHADOWMAP_RES);
        const fx = @round(focus.x / t) * t;
        const fz = @round(focus.z / t) * t;
        // …AND THE FOCUS HEIGHT, snapped the same way.
        const fy = @round(focus.y / t) * t;
        const cam = rl.Camera3D{
            .position = v3(fx + SUN_DIR.x * SUN_DIST, fy + SUN_DIR.y * SUN_DIST, fz + SUN_DIR.z * SUN_DIST),
            .target = v3(fx, fy, fz),
            .up = v3(0, 0, -1),
            .fovy = SHADOW_ORTHO, // orthographic: fovy is the box height in world units
            .projection = .orthographic,
        };
        self.saved_near = rl.gl.rlGetCullDistanceNear();
        self.saved_far = rl.gl.rlGetCullDistanceFar();
        rl.gl.rlSetClipPlanes(SHADOW_CLIP_NEAR, SHADOW_CLIP_FAR);
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

    // Bind the shadow texture on its slot and push this frame's sun VP + camera position.
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

    /// TAKE CAST SHADOWS OFF the draws that follow, until the next `bind`.
    pub fn shadowsOff(self: *Scene) void {
        rl.setShaderValueMatrix(self.shader, self.loc_lightVP, rl.math.matrixTranslate(0, 0, 5));
    }

    /// Upload this frame's point lights (torches/fires).
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
        if (n == 0) return; // nothing to push; the count alone switches the loop off
        rl.setShaderValueV(self.shader, self.loc_lightPos, &pos, .vec3, ni);
        rl.setShaderValueV(self.shader, self.loc_lightCol, &col, .vec3, ni);
        rl.setShaderValueV(self.shader, self.loc_lightRad, &rad, .float, ni);
    }

    pub fn setGround(self: *Scene, on: bool) void {
        var m: i32 = if (on) 1 else 0;
        rl.setShaderValue(self.shader, self.loc_ground, &m, .int);
    }

    /// Push the WATER FIELD: WATER_N² bytes of signed distance around the shore (see WATER_SHORE).
    pub fn setWater(self: *Scene, field: []const u8, half: f32, any: bool) void {
        const n: usize = @intCast(WATER_N);
        std.debug.assert(field.len == n * n);
        rl.updateTexture(self.waterTex, field.ptr);
        var on: i32 = if (any) 1 else 0;
        rl.setShaderValue(self.shader, self.loc_waterOn, &on, .int);
        var h = half;
        rl.setShaderValue(self.shader, self.loc_waterHalf, &h, .float);
    }

    pub fn setWaterSheet(self: *Scene, on: bool, tones: [3]rl.Vector3) void {
        var v: i32 = if (on) 1 else 0;
        rl.setShaderValue(self.shader, self.loc_waterSheet, &v, .int);
        if (!on) return;
        var t = tones;
        rl.setShaderValueV(self.shader, self.loc_waterTone, &t, .vec3, 3);
    }

    /// Push the painted soil grid: SOIL_N x SOIL_N material ids, one byte each, 0 = unpainted.
    pub fn setSoil(self: *Scene, ids: []const u8, cov: []const u8, half: f32) void {
        const n: usize = @intCast(SOIL_N);
        std.debug.assert(ids.len == n * n);
        std.debug.assert(cov.len == ids.len);
        rl.updateTexture(self.soilTex, ids.ptr);
        rl.updateTexture(self.soilCovTex, cov.ptr);
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

    // The soil and water fields ride their own slots alongside the shadow map, bound once per frame.
    fn bindSoil(self: *Scene) void {
        rl.gl.rlActiveTextureSlot(SLOT_SOIL);
        rl.gl.rlEnableTexture(self.soilTex.id);
        rl.gl.rlActiveTextureSlot(SLOT_WATER);
        rl.gl.rlEnableTexture(self.waterTex.id);
        rl.gl.rlActiveTextureSlot(SLOT_SOILCOV);
        rl.gl.rlEnableTexture(self.soilCovTex.id);
        rl.gl.rlActiveTextureSlot(0);
    }

    // Flora opt into vertex-shader sway; everything else (terrain, props, hero) draws rigid.
    pub fn setWind(self: *Scene, on: bool) void {
        var a: f32 = if (on) 1.0 else 0.0;
        rl.setShaderValue(self.shader, self.loc_windAmt, &a, .float);
    }

    // The blood-red combat flash on whatever draws NEXT (0 = none).
    pub fn setFlash(self: *Scene, amt: f32) void {
        var a = mathx.clampF(amt, 0, 1);
        rl.setShaderValue(self.shader, self.loc_flash, &a, .float);
    }

    /// HOW SOLID WHATEVER DRAWS NEXT IS — 1 opaque, 0 gone.
    pub fn setFade(self: *Scene, amt: f32) void {
        var a = mathx.clampF(amt, 0, 1);
        rl.setShaderValue(self.shader, self.loc_fade, &a, .float);
    }

    pub fn setDim(self: *Scene, amt: f32) void {
        var a = mathx.clampF(amt, 0, 1);
        rl.setShaderValue(self.shader, self.loc_dim, &a, .float);
    }
};

// Per-fragment surface material for the scene shader's texturing pass (see matAlbedo).
pub const Mat = enum(u8) { plain, stone, wood, cloth, steel, leather, skin, hide, plant, water, marble, flame, smoke, ember };
comptime {
    std.debug.assert(@intFromEnum(Mat.water) == 9);
    std.debug.assert(@intFromEnum(Mat.marble) == 10);
    std.debug.assert(@intFromEnum(Mat.flame) == 11);
    std.debug.assert(@intFromEnum(Mat.smoke) == 12);
    std.debug.assert(@intFromEnum(Mat.ember) == 13);
}

pub fn smokeAnim(originY: f32, phase01: f32) f32 {
    return @floor(originY) + std.math.clamp(phase01, 0, 0.999);
}

pub const Builder = struct {
    pos: std.ArrayList(f32),
    nrm: std.ArrayList(f32),
    uv: std.ArrayList(f32),
    uv2: std.ArrayList(f32),
    col: std.ArrayList(u8),
    matf: f32 = 0, // current Mat id, written per vertex into texcoords2.x
    /// The local Y a shape's VERTEX ANIMATION measures from, written per vertex into texcoords2.y.
    animY: f32 = 0,
    shapeN: f32 = 0, // per-shape counter driving the UV decorrelation offset

    pub fn init() Builder {
        return .{
            .pos = std.ArrayList(f32).init(alloc),
            .nrm = std.ArrayList(f32).init(alloc),
            .uv = std.ArrayList(f32).init(alloc),
            .uv2 = std.ArrayList(f32).init(alloc),
            .col = std.ArrayList(u8).init(alloc),
        };
    }

    // Material for every shape added AFTER this call (until the next one).
    pub fn setMat(self: *Builder, m: Mat) void {
        self.matf = @floatFromInt(@intFromEnum(m));
    }

    /// Datum for the vertex animation of every shape added after this call — see `animY`.
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

    /// A quad with a normal PER CORNER, and world-XZ UVs.
    pub fn quadSmooth(self: *Builder, a: rl.Vector3, b: rl.Vector3, c: rl.Vector3, d: rl.Vector3, na: rl.Vector3, nb: rl.Vector3, nc: rl.Vector3, nd: rl.Vector3, col: rl.Color) void {
        self.vert(a, na, col, a.x, a.z);
        self.vert(b, nb, col, b.x, b.z);
        self.vert(c, nc, col, c.x, c.z);
        self.vert(a, na, col, a.x, a.z);
        self.vert(c, nc, col, c.x, c.z);
        self.vert(d, nd, col, d.x, d.z);
    }

    // Planar-mapped quad: UVs are in-plane world-unit coordinates (u along a->b, v across), shifted by the shape offset — any face textures itself with zero caller effort.
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

    // Axis-aligned box centered at `c` with full `size`.
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

    // Parallelepiped from a center and three half-axis vectors — the oriented cousin of addCube.
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

    // Tapered cylinder (no caps) a(radius ra) -> b(radius rb); rb≈0 for spikes.
    pub fn addCylinder(self: *Builder, a: rl.Vector3, b: rl.Vector3, ra: f32, rb: f32, sides: i32, col: rl.Color) void {
        const f = axisFrame(a, b);
        const o = self.shapeOff();
        const rmid = @max(0.5 * (ra + rb), 0.02); // arc-length radius (floor keeps spike UVs sane)
        self.ringBand(a, b, f.u, f.w, ra, rb, sides, col, o, rmid, o.y, o.y + f.len);
    }

    // ONE band of a revolved surface: the quad ring between circle (a, ra) and circle (b, rb) in the (u, w) frame, with the UV offset / arc radius / v-range supplied by the caller — so a multi-band surface (a capsule's cap, a blob) keeps ONE continuous texture instead of a fresh decorrelated patch per band (which reads as rings of noise on a big smooth mass).
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

    // A CAPSULE: the tapered barrel a→b plus real DOMED ends (radius ra behind a, rb past b).
    pub fn addCapsule(self: *Builder, a: rl.Vector3, b: rl.Vector3, ra: f32, rb: f32, sides: i32, col: rl.Color) void {
        const f = axisFrame(a, b);
        const o = self.shapeOff();
        const rmid = @max(0.5 * (ra + rb), 0.02);
        self.ringBand(a, b, f.u, f.w, ra, rb, sides, col, o, rmid, o.y, o.y + f.len);
        self.dome(a, neg(f.axis), f.u, f.w, ra, sides, col, o, rmid, o.y, -1);
        self.dome(b, f.axis, f.u, f.w, rb, sides, col, o, rmid, o.y + f.len, 1);
    }

    // A standalone domed cap — a rounded stump wherever a bare cylinder would show its open end.
    pub fn addDome(self: *Builder, c: rl.Vector3, dir: rl.Vector3, r: f32, sides: i32, col: rl.Color) void {
        const f = axisFrame(c, scaleAdd(c, norm3(dir), @max(r, 1e-3)));
        const o = self.shapeOff();
        self.dome(c, f.axis, f.u, f.w, r, sides, col, o, @max(r, 0.02), o.y, 1);
    }

    // A hemispherical cap of radius r on `c`, bulging along `dir`.
    fn dome(self: *Builder, c: rl.Vector3, dir: rl.Vector3, u: rl.Vector3, w: rl.Vector3, r: f32, sides: i32, col: rl.Color, o: rl.Vector2, rmid: f32, vAt: f32, vSign: f32) void {
        if (r < 1e-4) return;
        const BANDS = 3;
        var k: i32 = BANDS;
        while (k > 0) : (k -= 1) {
            const t0 = std.math.pi * 0.5 * @as(f32, @floatFromInt(k)) / @as(f32, BANDS); // far pole side
            const t1 = std.math.pi * 0.5 * @as(f32, @floatFromInt(k - 1)) / @as(f32, BANDS); // toward the seam
            const c0 = scaleAdd(c, dir, r * mathx.sinf(t0));
            const c1 = scaleAdd(c, dir, r * mathx.sinf(t1));
            const v0 = vAt + vSign * r * t0;
            const v1 = vAt + vSign * r * t1;
            // vSign flips which ring is "first" so the winding stays CCW-from-outside on both ends.
            if (vSign > 0) {
                self.ringBand(c1, c0, u, w, r * mathx.cosf(t1), r * mathx.cosf(t0), sides, col, o, rmid, v1, v0);
            } else {
                self.ringBand(c0, c1, u, w, r * mathx.cosf(t0), r * mathx.cosf(t1), sides, col, o, rmid, v0, v1);
            }
        }
    }

    // A rounded ELLIPSOID mass centred on `c` with half-extents `r` — the anti-blockiness primitive.
    pub fn addBlob(self: *Builder, c: rl.Vector3, r: rl.Vector3, segs: i32, sides: i32, col: rl.Color) void {
        const o = self.shapeOff();
        const sf: f32 = @floatFromInt(sides);
        const gf: f32 = @floatFromInt(segs);
        const rmid = @max((r.x + r.z) * 0.5, 0.02);
        const inv = v3(1.0 / @max(r.x, 1e-4), 1.0 / @max(r.y, 1e-4), 1.0 / @max(r.z, 1e-4));
        var j: i32 = 0;
        while (j < segs) : (j += 1) {
            const t0 = std.math.pi * @as(f32, @floatFromInt(j)) / gf; // 0 = bottom pole, pi = top
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

    // Upload to the GPU as a bare Mesh (CPU arrays stay attached; the mesh lives the whole program).
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
        mesh.texcoords2 = uv2.ptr; // material channel (gfx.Mat per vertex)
        mesh.colors = col.ptr;
        rl.uploadMesh(&mesh, false);
        return mesh;
    }

    // Upload and wrap in a Model bound to `shader` (props/terrain drawn with drawModel).
    pub fn toModel(self: *Builder, shader: rl.Shader) rl.Model {
        const mesh = self.toMesh();
        var model = rl.loadModelFromMesh(mesh) catch @panic("model");
        model.materials[0].shader = shader;
        return model;
    }
};

fn scaleAdd(base: rl.Vector3, dir: rl.Vector3, s: f32) rl.Vector3 {
    return v3(base.x + dir.x * s, base.y + dir.y * s, base.z + dir.z * s);
}
// The revolution frame for the segment a→b: unit axis, its two perpendiculars, and the length.
const AxisFrame = struct { axis: rl.Vector3, u: rl.Vector3, w: rl.Vector3, len: f32 };
fn axisFrame(a: rl.Vector3, b: rl.Vector3) AxisFrame {
    const d = v3(b.x - a.x, b.y - a.y, b.z - a.z);
    const axis = norm3(d);
    const seed = if (@abs(axis.y) < 0.99) v3(0, 1, 0) else v3(1, 0, 0);
    const u = norm3(cross(axis, seed));
    return .{ .axis = axis, .u = u, .w = norm3(cross(axis, u)), .len = @sqrt(d.x * d.x + d.y * d.y + d.z * d.z) };
}
// A point on the ellipsoid (c, r): `t` = polar angle (0 = bottom pole), `ang` = angle around.
fn onBlob(c: rl.Vector3, r: rl.Vector3, t: f32, ang: f32) rl.Vector3 {
    const st = mathx.sinf(t);
    return v3(c.x - r.x * mathx.sinf(ang) * st, c.y - r.y * mathx.cosf(t), c.z - r.z * mathx.cosf(ang) * st);
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
fn cross(a: rl.Vector3, b: rl.Vector3) rl.Vector3 {
    return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}
