const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;

// GFX — the render layer: one lit scene shader plus a small procedural-mesh Builder.
// Adapted from zig-rts (which itself reused zig-diablo's Builder + depth-pass shadow
// pipeline). Driven by a single hard directional SUN (crisp form shading + hemisphere
// ambient + cast shadows) with a distance haze fading to the sky.
//
// Difference from zig-rts: the RTS fog-of-war multiply is GONE. A soulslike world is
// fully lit and explored; the only visibility term left is atmospheric distance haze.

// c_allocator = malloc, matching raylib's libc free() in UnloadMesh/Model.
const alloc = std.heap.c_allocator;

// Shadow sampler lives on a high texture slot raylib's default material never binds (it
// only uses slot 0 for albedo), so the per-frame bind survives drawModel/drawMesh.
const SLOT_SHADOW: i32 = 12;

// THE SUN — one hard directional light. Single source for the shader uniform and the
// shadow camera so shading and cast shadows can never disagree. Low golden-hour
// elevation (~33 deg) from the front-left throws long raking amber shadows.
pub const SUN_DIR = norm3(v3(-0.60, 0.50, -0.46));

pub const SHADOWMAP_RES = 4096;
const SHADOW_ORTHO = 44.0; // world-unit square the sun's ortho box covers around the focus (tight = crisp)
const SUN_DIST = 120.0; // shadow camera distance along SUN_DIR
// Tight depth slab around the casters. Ortho depth is LINEAR over near..far, so the
// shader's NDC bias = bias*(far-near) world units — leaving raylib's default planes makes
// the bias huge and small casters' shadows detach or vanish.
const SHADOW_CLIP_NEAR = 70.0;
const SHADOW_CLIP_FAR = 190.0;

// The haze color the world fades into with distance (authored pre-gamma — the shader
// gammas output, so dark values lift). Warm grey-gold mist; the sky shader's horizon band
// is authored to the DISPLAYED value of this so the seam disappears. The shader also
// banks the haze golden toward the sun's quarter (see sceneFS) to match the sky's glow.
pub const HAZE = v3(0.078, 0.070, 0.056);
// Haze falloff: 1-exp(-density*dist) — at 0.021, ~63% hazed by ~48 world units, so the
// horizon giants (|z| ~ 50+) read as silhouettes while the avenue stays clear.
const HAZE_DENSITY: f32 = 0.021;

// Depth-only pass for the sun's shadow map (zig-diablo's depth shader verbatim).
const depthVS =
    \\#version 330
    \\in vec3 vertexPosition;
    \\uniform mat4 mvp;
    \\void main() { gl_Position = mvp*vec4(vertexPosition, 1.0); }
;
const depthFS =
    \\#version 330
    \\out vec4 c;
    \\void main() { c = vec4(1.0); }
;

const sceneVS =
    \\#version 330
    \\in vec3 vertexPosition;
    \\in vec2 vertexTexCoord;
    \\in vec3 vertexNormal;
    \\in vec4 vertexColor;
    \\uniform mat4 mvp;
    \\uniform mat4 matModel;
    \\uniform float windAmt;   // 0 = rigid (terrain / props / hero); 1 = flora opts into sway
    \\uniform float windTime;  // seconds, drives the sway phase
    \\out vec3 fragPosition;
    \\out vec4 fragColor;
    \\out vec3 fragNormal;
    \\void main() {
    \\    vec3 p = vertexPosition;
    \\    if (windAmt > 0.0) {
    \\        // Flora sway: bend grows with height^2 so bases stay planted while tips lean;
    \\        // phase keys off the clump's WORLD origin so neighbours move as one gust field.
    \\        vec3 baseW = vec3(matModel*vec4(0.0, 0.0, 0.0, 1.0));
    \\        float h = max(p.y, 0.0);
    \\        float bend = h*h*windAmt*0.10;
    \\        float phase = windTime*1.5 + baseW.x*0.6 + baseW.z*0.5;
    \\        float sway = sin(phase) + 0.3*sin(phase*2.7 + 1.3);
    \\        p.x += bend*sway;
    \\        p.z += bend*sway*0.4;
    \\    }
    \\    fragPosition = vec3(matModel*vec4(p, 1.0));
    \\    fragColor = vertexColor;
    \\    fragNormal = normalize(mat3(matModel)*vertexNormal);
    \\    gl_Position = mvp*vec4(p, 1.0);
    \\}
;
// Lighting model (softness tricks ported from zig-diablo/zig-rts):
//  - BARELY-WRAPPED LAMBERT: (N.L + 0.18)/1.18 clamped — shaded faces roll off gently.
//  - HEMISPHERE AMBIENT: cool sky from above, warm dirt bounce from below.
//  - CAST SHADOW (3x3 PCF): the shadow term kills the sun AND eats the ambient, so
//    shadow pools run deep and cool without collapsing to black.
//  - EMISSIVE CHANNEL: vertex alpha < 255 marks self-lit material (embers, glints).
//  - DISTANCE HAZE: mix toward HAZE by 1-exp(-density*dist-from-camera) — atmosphere.
//  - GAMMA + DITHER: pow(1/2.2) then +-1 LSB screen noise so near-dark gradients don't
//    band on an 8-bit target. Gamma lifts dark albedos hard — author colors near-black.
const sceneFS =
    \\#version 330
    \\in vec3 fragPosition;
    \\in vec4 fragColor;
    \\in vec3 fragNormal;
    \\uniform vec3 sunDir;      // normalized, surface -> sun
    \\uniform int groundMode;   // 1 = terrain (procedural grain), 0 = props/hero
    \\uniform vec3 camPos;      // for distance haze
    \\uniform vec3 hazeColor;   // sky/haze tint (pre-gamma)
    \\uniform float hazeDensity;
    \\uniform mat4 lightVP;     // sun's ortho view-projection (captured in the depth pass)
    \\uniform sampler2D shadowMap;
    \\uniform int shadowMapResolution;
    \\out vec4 finalColor;
    \\float hash21(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
    \\float vnoise(vec2 p){ vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    \\  return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x), mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y); }
    \\float speck(vec2 p, float s){ return hash21(floor(p*s)); }
    \\// ---- TERRAIN ALBEDO ---- dry golden grassland (pre-gamma, so everything starts
    \\// dark): sun-bleached khaki grass drifting to damp green, a worn dirt path down the
    \\// ruin avenue (x ~ 0, edges wobbled), stony patches, and dark scrub clumps. All
    \\// smooth field noise — no coarse per-tile specks, which read as a checkerboard.
    \\vec3 terrainAlbedo(vec2 p){
    \\  float f1 = vnoise(p*0.055);
    \\  float f2 = vnoise(p*0.35 + 7.7);
    \\  float f3 = vnoise(p*1.6 + 3.1);
    \\  float blades = vnoise(p*7.0)*0.65 + speck(p, 31.0)*0.35;
    \\  vec3 dry = vec3(0.140, 0.114, 0.058);
    \\  vec3 grn = vec3(0.080, 0.100, 0.048);
    \\  vec3 c = mix(grn, dry, smoothstep(0.22, 0.78, f1 + 0.30*(f2 - 0.5)));
    \\  c *= 0.80 + 0.50*blades + 0.20*f3;
    \\  float wob = (vnoise(vec2(p.y*0.13, 3.7)) - 0.5)*3.2;
    \\  float path = smoothstep(2.8, 1.2, abs(p.x + wob));
    \\  vec3 dirt = vec3(0.130, 0.110, 0.082)*(0.80 + 0.40*f3)*(0.88 + 0.24*speck(p, 21.0));
    \\  c = mix(c, dirt, path*0.85);
    \\  float rocky = smoothstep(0.64, 0.86, vnoise(p*0.09 + 47.1));
    \\  vec3 rock = vec3(0.140, 0.142, 0.140)*(0.78 + 0.40*vnoise(p*2.7))*(0.88 + 0.24*speck(p, 11.0));
    \\  c = mix(c, rock, rocky*(1.0 - path)*0.9);
    \\  float scrub = smoothstep(0.68, 0.90, vnoise(p*0.22 + 8.9))*(1.0 - rocky)*(1.0 - path);
    \\  c = mix(c, vec3(0.042, 0.055, 0.026)*(0.7 + 0.6*blades), scrub*0.8);
    \\  return c*(0.78 + 0.22*vnoise(p*0.03 + 9.7));
    \\}
    \\// Fraction of this fragment in sun shadow (0 lit, 1 shadowed): 3x3 PCF. Outside the
    \\// ortho box counts as lit.
    \\float shadowFrac(vec3 pos, float ndl){
    \\  vec4 p = lightVP*vec4(pos, 1.0);
    \\  p.xyz /= p.w;
    \\  p.xyz = p.xyz*0.5 + 0.5;
    \\  if (p.z > 1.0 || p.z < 0.0 || p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) return 0.0;
    \\  float bias = max(0.0016*(1.0 - ndl), 0.0004);
    \\  float texel = 1.0/float(shadowMapResolution);
    \\  float sc = 0.0;
    \\  for (int x = -1; x <= 1; x++)
    \\    for (int y = -1; y <= 1; y++)
    \\      if (p.z - bias > texture(shadowMap, p.xy + vec2(x, y)*texel).r) sc += 1.0;
    \\  return sc/9.0;
    \\}
    \\void main(){
    \\  vec3 base = fragColor.rgb;
    \\  vec3 n = normalize(fragNormal);
    \\  float upMask = smoothstep(0.25, 0.95, n.y);
    \\  vec2 p = fragPosition.xz;
    \\  if (groundMode==1){
    \\    base *= terrainAlbedo(p);
    \\  } else {
    \\    float grain = vnoise(p*1.1)*0.45 + vnoise(p*4.3)*0.35 + speck(p, 13.0)*0.20;
    \\    float gstr = mix(0.08, 0.18, upMask);
    \\    base *= 1.0 - gstr + 2.0*gstr*grain;
    \\  }
    \\  float ndl = dot(n, normalize(sunDir));
    \\  float diff = clamp((ndl + 0.18)/1.18, 0.0, 1.0);
    \\  float sh = shadowFrac(fragPosition, ndl);
    \\  // Golden-hour split: warm amber key vs cool slate sky ambient + warm dirt bounce.
    \\  vec3 hemi = mix(vec3(0.100, 0.084, 0.060), vec3(0.165, 0.185, 0.240), n.y*0.5 + 0.5);
    \\  vec3 lit = base*(hemi*(1.0 - 0.50*sh) + vec3(1.22, 1.02, 0.74)*diff*1.22*(1.0 - sh));
    \\  vec3 V = normalize(camPos - fragPosition);
    \\  if (groundMode == 0){
    \\    // Cool sky rim on props/hero — lifts silhouettes off the dark ground (cheap
    \\    // atmospheric backlight; NOT on terrain, where grazing angles would sheen it all).
    \\    float rim = pow(1.0 - clamp(dot(n, V), 0.0, 1.0), 3.0);
    \\    lit += rim*vec3(0.040, 0.048, 0.066)*(0.6 + 0.4*n.y)*(1.0 - 0.5*sh);
    \\  }
    \\  float emis = 1.0 - fragColor.a;
    \\  lit = mix(lit, base*1.35, emis);
    \\  float dist = length(fragPosition - camPos);
    \\  float haze = 1.0 - exp(-hazeDensity*dist);
    \\  // Haze banks golden looking into the sun's quarter (matches the sky shader's bank).
    \\  float sunAmt = pow(clamp(dot(-V, normalize(sunDir)), 0.0, 1.0), 3.0);
    \\  vec3 hazeC = hazeColor + vec3(0.34, 0.19, 0.05)*sunAmt;
    \\  lit = mix(lit, hazeC, clamp(haze, 0.0, 1.0));
    \\  vec3 outc = pow(max(lit, 0.0), vec3(1.0/2.2));
    \\  outc += (hash21(gl_FragCoord.xy) - 0.5)*(2.0/255.0);
    \\  finalColor = vec4(outc, 1.0);
    \\}
;

// ── SKY ── a fullscreen shader quad drawn before the 3D pass (in place of the old flat
// 2D gradient): vertical slate gradient, a golden bank + aureole + disc around the sun,
// and a streaky fbm cloud deck with warm sunward rims. Output is DISPLAY-space (the 2D
// pass has no gamma); the horizon band is authored to the displayed value of HAZE so the
// 3D distance haze dissolves into it seamlessly.
const skyVS =
    \\#version 330
    \\in vec3 vertexPosition;
    \\in vec2 vertexTexCoord;
    \\in vec4 vertexColor;
    \\uniform mat4 mvp;
    \\out vec2 fragTexCoord;
    \\out vec4 fragColor;
    \\void main(){ fragTexCoord = vertexTexCoord; fragColor = vertexColor;
    \\  gl_Position = mvp*vec4(vertexPosition, 1.0); }
;
const skyFS =
    \\#version 330
    \\uniform vec3 camFwd;    // camera forward (unit)
    \\uniform vec3 camRightS; // camera right, pre-scaled by tan(fov/2)*aspect
    \\uniform vec3 camUpS;    // camera up, pre-scaled by tan(fov/2)
    \\uniform vec3 sunDir;
    \\uniform vec2 resolution;
    \\out vec4 finalColor;
    \\float hash21(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
    \\float vnoise(vec2 p){ vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    \\  return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x), mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y); }
    \\float fbm(vec2 p){ float a=0.5, s=0.0;
    \\  for (int i=0;i<4;i++){ s+=a*vnoise(p); p=p*2.13+vec2(19.7,7.3); a*=0.5; } return s; }
    \\void main(){
    \\  // Screen ray from gl_FragCoord — NOT fragTexCoord: drawRectangle maps texcoords to
    \\  // raylib's tiny shapes-texture rect, which is constant across the quad.
    \\  float sx = (gl_FragCoord.x/resolution.x)*2.0 - 1.0;
    \\  float sy = (gl_FragCoord.y/resolution.y)*2.0 - 1.0; // gl_FragCoord.y is bottom-up: +1 = screen top
    \\  vec3 ray = normalize(camFwd + sx*camRightS + sy*camUpS);
    \\  float e = max(ray.y, 0.0);
    \\  vec3 sun = normalize(sunDir);
    \\  float sunAmt = clamp(dot(ray, sun), 0.0, 1.0);
    \\  float az = pow(sunAmt, 3.0);
    \\  vec3 col = mix(vec3(0.325,0.310,0.278), vec3(0.235,0.250,0.300), smoothstep(0.0,0.22,e));
    \\  col = mix(col, vec3(0.150,0.170,0.230), smoothstep(0.18,0.75,e));
    \\  col += vec3(0.40,0.26,0.10)*az*exp(-e*7.0);                    // golden horizon bank
    \\  col += vec3(0.90,0.62,0.28)*pow(sunAmt, 24.0)*0.50;            // aureole
    \\  col += vec3(1.00,0.85,0.55)*smoothstep(0.9993, 0.9998, sunAmt); // disc
    \\  if (ray.y > 0.0){
    \\    vec2 cp = ray.xz/(ray.y + 0.32);          // low deck: streaks reach the horizon
    \\    float cl = fbm(cp*vec2(1.1,2.2) + vec2(3.1,-6.7));
    \\    float cover = smoothstep(0.34, 0.62, cl)*smoothstep(0.0, 0.06, ray.y);
    \\    vec3 cloudCol = mix(vec3(0.165,0.172,0.205), vec3(0.40,0.31,0.20), az*0.85);
    \\    col = mix(col, cloudCol, cover*0.85);
    \\    float rim = smoothstep(0.26,0.40,cl) - smoothstep(0.40,0.66,cl);
    \\    col += vec3(0.16,0.13,0.08)*rim*(0.45 + 0.55*az);
    \\  }
    \\  col += (hash21(gl_FragCoord.xy) - 0.5)*(2.0/255.0);
    \\  finalColor = vec4(col, 1.0);
    \\}
;

pub const Sky = struct {
    shader: rl.Shader,
    loc_fwd: i32,
    loc_right: i32,
    loc_up: i32,
    loc_res: i32,

    pub fn init() Sky {
        const sh = rl.loadShaderFromMemory(skyVS, skyFS) catch @panic("sky shader");
        var sun = SUN_DIR;
        rl.setShaderValue(sh, rl.getShaderLocation(sh, "sunDir"), &sun, .vec3);
        return .{
            .shader = sh,
            .loc_fwd = rl.getShaderLocation(sh, "camFwd"),
            .loc_right = rl.getShaderLocation(sh, "camRightS"),
            .loc_up = rl.getShaderLocation(sh, "camUpS"),
            .loc_res = rl.getShaderLocation(sh, "resolution"),
        };
    }

    // Fullscreen quad through the sky shader. Call between beginDrawing and beginMode3D;
    // the per-pixel view ray is rebuilt from the 3D camera's basis so the sky tracks look.
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

// ── VIGNETTE ── one pre-generated radial-gradient texture stretched over the frame after
// the 3D pass (before the HUD): darkened corners pull the eye to the hero, souls-style.
pub const Vignette = struct {
    tex: rl.Texture2D,

    pub fn init() Vignette {
        const img = rl.genImageGradientRadial(320, 200, 0.42, rl.Color.init(0, 0, 0, 0), rl.Color.init(0, 0, 0, 54));
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

// ── RETRO FILTERS ── one combined post-process pass, inspired by ../crawler's
// retrofilter.go: the 3D scene (sky included) renders into an off-screen RT, then blits
// to the backbuffer through ONE shader where each filter is a 0..1 intensity uniform in
// a fixed pipeline order, so any subset layers in a single pass. The HUD/menu draw
// after, crisp. Order: UV warps (CRT curve, VHS jitter, pixelate) → sampling (chroma
// fringe, edge detect) → color crush (posterize, dither, Game Boy, CGA, palette, sepia,
// mono, amber) → overlays (edges, scanlines, VHS noise, grain, CRT mask).
pub const RETRO_COUNT = 15;
// A filter at or below this intensity is treated as OFF everywhere: anyActive() bypasses
// the whole pass, and the menu shows "Off" — one threshold so the label can't claim a live
// percentage for a value that renders nothing.
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

pub const RETRO_NAMES = [RETRO_COUNT][:0]const u8{
    "Pixelate",  "Chroma Fringe", "Posterize", "Dither", "Game Boy",
    "CGA",       "Palette 16",    "Sepia",     "Mono",   "Amber CRT",
    "Ink Edges", "Scanlines",     "CRT Curve", "VHS",    "Film Grain",
};
const RETRO_UNIFORMS = [RETRO_COUNT][:0]const u8{
    "fPixelate", "fChroma",    "fPosterize", "fDither", "fGameBoy",
    "fCGA",      "fPalette",   "fSepia",     "fMono",   "fAmber",
    "fEdges",    "fScanlines", "fCurve",     "fVHS",    "fGrain",
};

// The launch look (owner-tuned): a light retro grunge — a whisper of pixelate/chroma/
// grain over a posterize+dither color crush. "Reset to Default" restores this;
// "All Off" gives the clean render.
pub const RETRO_DEFAULTS = [RETRO_COUNT]f32{
    0.07, 0.09, 0.24, 0.40, 0.0,
    0.07, 0.07, 0.05, 0.0,  0.0,
    0.0,  0.0,  0.0,  0.0,  0.04,
};

// Retro filter PRESETS — the SINGLE source for the menu's Preset rows AND the --shot
// verification stacks (which previously re-hardcoded these values). Each is a set of
// {filter, intensity}; Retro.applyPreset clears everything else first.
pub const Preset = struct { idx: usize, val: f32 };
pub const PRESET_PS1 = [_]Preset{ .{ .idx = RF_PIXELATE, .val = 0.35 }, .{ .idx = RF_DITHER, .val = 0.55 }, .{ .idx = RF_POSTERIZE, .val = 0.25 } };
pub const PRESET_CRT = [_]Preset{ .{ .idx = RF_SCANLINES, .val = 0.6 }, .{ .idx = RF_CHROMA, .val = 0.45 }, .{ .idx = RF_CURVE, .val = 0.55 }, .{ .idx = RF_GRAIN, .val = 0.25 } };
pub const PRESET_VHS = [_]Preset{ .{ .idx = RF_VHS, .val = 0.65 }, .{ .idx = RF_CHROMA, .val = 0.55 }, .{ .idx = RF_GRAIN, .val = 0.35 }, .{ .idx = RF_SEPIA, .val = 0.15 } };
pub const PRESET_GB = [_]Preset{ .{ .idx = RF_GAMEBOY, .val = 1.0 }, .{ .idx = RF_PIXELATE, .val = 0.45 }, .{ .idx = RF_DITHER, .val = 0.4 } };

const retroFS =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\uniform sampler2D texture0;
    \\uniform vec2 resolution;
    \\uniform float time;
    \\uniform float fPixelate, fChroma, fPosterize, fDither, fGameBoy;
    \\uniform float fCGA, fPalette, fSepia, fMono, fAmber;
    \\uniform float fEdges, fScanlines, fCurve, fVHS, fGrain;
    \\out vec4 finalColor;
    \\float hash21(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
    \\float luma(vec3 c){ return dot(c, vec3(0.299, 0.587, 0.114)); }
    \\// 4x4 Bayer matrix, thresholds at +0.5/16 centers.
    \\const float bayer[16] = float[16](
    \\     0.0,  8.0,  2.0, 10.0,
    \\    12.0,  4.0, 14.0,  6.0,
    \\     3.0, 11.0,  1.0,  9.0,
    \\    15.0,  7.0, 13.0,  5.0);
    \\// Classic 4-shade green LCD ramp, dark to light.
    \\const vec3 gbRamp[4] = vec3[4](
    \\    vec3(0.055, 0.149, 0.055),
    \\    vec3(0.188, 0.384, 0.188),
    \\    vec3(0.545, 0.675, 0.059),
    \\    vec3(0.741, 0.890, 0.420));
    \\// CGA mode-4 high intensity: black / cyan / magenta / white.
    \\const vec3 cga4[4] = vec3[4](
    \\    vec3(0.0), vec3(0.333, 1.0, 1.0), vec3(1.0, 0.333, 1.0), vec3(1.0));
    \\// DawnBringer 16 — balanced general-purpose 16-color pixel-art palette.
    \\const vec3 db16[16] = vec3[16](
    \\    vec3(0.078, 0.047, 0.110), vec3(0.267, 0.141, 0.204),
    \\    vec3(0.188, 0.204, 0.427), vec3(0.306, 0.290, 0.306),
    \\    vec3(0.522, 0.298, 0.188), vec3(0.204, 0.396, 0.141),
    \\    vec3(0.816, 0.275, 0.282), vec3(0.459, 0.443, 0.380),
    \\    vec3(0.349, 0.490, 0.808), vec3(0.824, 0.490, 0.173),
    \\    vec3(0.522, 0.584, 0.631), vec3(0.427, 0.667, 0.173),
    \\    vec3(0.824, 0.667, 0.600), vec3(0.427, 0.761, 0.792),
    \\    vec3(0.855, 0.831, 0.369), vec3(0.871, 0.933, 0.839));
    \\void main(){
    \\  vec2 uv = fragTexCoord;
    \\  float crtMask = 1.0;
    \\  // CRT Curve: barrel-warp the UV; blacken past the tube edge, shade the corners.
    \\  if (fCurve > 0.0){
    \\    vec2 cc = uv*2.0 - 1.0;
    \\    cc *= 1.0 + fCurve*0.18*dot(cc, cc);
    \\    uv = cc*0.5 + 0.5;
    \\    vec2 edge = smoothstep(vec2(0.0), vec2(0.02), uv)*(1.0 - smoothstep(vec2(0.98), vec2(1.0), uv));
    \\    crtMask = edge.x*edge.y*(1.0 - fCurve*0.35*pow(dot(cc, cc)*0.5, 1.5));
    \\  }
    \\  // VHS: per-scanline horizontal jitter + a slow roaming tracking tear.
    \\  if (fVHS > 0.0){
    \\    float row = floor(uv.y*resolution.y);
    \\    uv.x += (hash21(vec2(row, floor(time*24.0))) - 0.5)*fVHS*0.006;
    \\    float band = smoothstep(0.986, 1.0, sin(uv.y*7.0 + time*1.6)*0.5 + 0.5);
    \\    uv.x += band*fVHS*0.05*(hash21(vec2(floor(time*13.0), 7.0)) - 0.5)*2.0;
    \\  }
    \\  // Pixelate: quantize the UV onto a coarse grid (1px = off ... ~14px = full chunk).
    \\  if (fPixelate > 0.0){
    \\    float px = mix(1.0, 14.0, fPixelate);
    \\    vec2 grid = max(resolution/px, vec2(1.0));
    \\    uv = (floor(uv*grid) + 0.5)/grid;
    \\  }
    \\  // Chroma fringe: fetch R and B slightly off-axis (worn composite cable).
    \\  vec4 baseTex = texture(texture0, uv);
    \\  vec3 col;
    \\  if (fChroma > 0.0){
    \\    float off = fChroma*0.0045;
    \\    col.r = texture(texture0, uv + vec2(off, 0.0)).r;
    \\    col.g = baseTex.g;
    \\    col.b = texture(texture0, uv - vec2(off, 0.0)).b;
    \\  } else { col = baseTex.rgb; }
    \\  // Ink edges: Sobel on luminance, applied as a darkening AFTER the color crush.
    \\  float edgeF = 0.0;
    \\  if (fEdges > 0.0){
    \\    vec2 t = 1.5/resolution;
    \\    float tl = luma(texture(texture0, uv + vec2(-t.x, -t.y)).rgb);
    \\    float tc = luma(texture(texture0, uv + vec2( 0.0, -t.y)).rgb);
    \\    float tr = luma(texture(texture0, uv + vec2( t.x, -t.y)).rgb);
    \\    float ml = luma(texture(texture0, uv + vec2(-t.x,  0.0)).rgb);
    \\    float mr = luma(texture(texture0, uv + vec2( t.x,  0.0)).rgb);
    \\    float bl = luma(texture(texture0, uv + vec2(-t.x,  t.y)).rgb);
    \\    float bc = luma(texture(texture0, uv + vec2( 0.0,  t.y)).rgb);
    \\    float br = luma(texture(texture0, uv + vec2( t.x,  t.y)).rgb);
    \\    float gx = (tr + 2.0*mr + br) - (tl + 2.0*ml + bl);
    \\    float gy = (bl + 2.0*bc + br) - (tl + 2.0*tc + tr);
    \\    edgeF = clamp(length(vec2(gx, gy))*2.2, 0.0, 1.0)*fEdges;
    \\  }
    \\  // Posterize: crush the color depth (48 = subtle banding ... 4 = poster).
    \\  if (fPosterize > 0.0){
    \\    float levels = mix(48.0, 4.0, fPosterize);
    \\    col = floor(col*levels + 0.5)/levels;
    \\  }
    \\  // Ordered dither: Bayer-threshold toward a 6-level quantize.
    \\  if (fDither > 0.0){
    \\    int bx = int(mod(gl_FragCoord.x, 4.0));
    \\    int by = int(mod(gl_FragCoord.y, 4.0));
    \\    float th = (bayer[by*4 + bx] + 0.5)/16.0 - 0.5;
    \\    float levels = 6.0;
    \\    vec3 q = floor((col + th*(1.5/levels))*levels + 0.5)/levels;
    \\    col = mix(col, q, fDither);
    \\  }
    \\  // Game Boy: luminance onto the 4-shade green LCD ramp.
    \\  if (fGameBoy > 0.0){
    \\    int gstep = int(clamp(floor(luma(col)*4.0), 0.0, 3.0));
    \\    col = mix(col, gbRamp[gstep], fGameBoy);
    \\  }
    \\  // CGA: nearest of the 4-color mode-4 palette.
    \\  if (fCGA > 0.0){
    \\    vec3 best = cga4[0];
    \\    float bestD = dot(col - cga4[0], col - cga4[0]);
    \\    for (int i = 1; i < 4; i++){
    \\      vec3 d = col - cga4[i];
    \\      float dist = dot(d, d);
    \\      if (dist < bestD){ bestD = dist; best = cga4[i]; }
    \\    }
    \\    col = mix(col, best, fCGA);
    \\  }
    \\  // Palette: snap to the nearest DawnBringer-16 color (hard pixel-art palette).
    \\  if (fPalette > 0.0){
    \\    vec3 best = db16[0];
    \\    float bestD = dot(col - db16[0], col - db16[0]);
    \\    for (int i = 1; i < 16; i++){
    \\      vec3 d = col - db16[i];
    \\      float dist = dot(d, d);
    \\      if (dist < bestD){ bestD = dist; best = db16[i]; }
    \\    }
    \\    col = mix(col, best, fPalette);
    \\  }
    \\  if (fSepia > 0.0){
    \\    float l = luma(col);
    \\    col = mix(col, vec3(l*1.07 + 0.04, l*0.87, l*0.55), fSepia);
    \\  }
    \\  if (fMono > 0.0) col = mix(col, vec3(luma(col)), fMono);
    \\  if (fAmber > 0.0) col = mix(col, vec3(1.0, 0.62, 0.14)*pow(luma(col), 0.85), fAmber);
    \\  col *= 1.0 - edgeF*0.85;
    \\  // Scanlines: soft CRT line darkening on alternating rows.
    \\  if (fScanlines > 0.0){
    \\    float s = 0.5 + 0.5*sin(gl_FragCoord.y*3.14159265);
    \\    col *= 1.0 - fScanlines*0.45*s;
    \\  }
    \\  // VHS finish: signal noise + a washed-out desaturation.
    \\  if (fVHS > 0.0){
    \\    float n = hash21(vec2(uv.x*731.0, uv.y*913.0 + time*61.0));
    \\    col += (n - 0.5)*fVHS*0.12;
    \\    col = mix(col, vec3(luma(col)), fVHS*0.25);
    \\  }
    \\  // Film grain: animated per-pixel flicker.
    \\  if (fGrain > 0.0){
    \\    float gnoise = hash21(gl_FragCoord.xy + vec2(mod(time, 97.0)*137.0, mod(time, 89.0)*291.0));
    \\    col += (gnoise - 0.5)*fGrain*0.18;
    \\  }
    \\  col *= crtMask;
    \\  finalColor = vec4(col, baseTex.a);
    \\}
;

pub const Retro = struct {
    shader: rl.Shader,
    rt: rl.RenderTexture2D,
    locs: [RETRO_COUNT]i32,
    loc_time: i32,
    values: [RETRO_COUNT]f32 = RETRO_DEFAULTS,

    pub fn init(w: i32, h: i32) Retro {
        const sh = rl.loadShaderFromMemory(skyVS, retroFS) catch @panic("retro shader");
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

    pub fn anyActive(self: *const Retro) bool {
        for (self.values) |v| if (v > RETRO_EPS) return true;
        return false;
    }

    pub fn allOff(self: *Retro) void {
        self.values = [_]f32{0} ** RETRO_COUNT;
    }

    // Clear all filters, then enable the given preset's filters. Used by the menu's Preset
    // rows and the --shot harness so both draw from the same PRESET_* tables.
    pub fn applyPreset(self: *Retro, preset: []const Preset) void {
        self.allOff();
        for (preset) |p| self.values[p.idx] = p.val;
    }

    // Redirect the frame into the capture RT when any filter is on. true => the caller
    // MUST call end() after its 3D pass; false => draw straight to the backbuffer.
    pub fn begin(self: *Retro) bool {
        if (!self.anyActive()) return false;
        rl.beginTextureMode(self.rt);
        return true;
    }

    // Blit the captured scene to the backbuffer through the filter shader (flipping the
    // RT upright via the negative source height). Pair with a true begin().
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

// Depth-only FBO for the shadow map (zig-diablo's loadShadowmap; the 100s are rlgl's
// depth-attachment enums, unchanged in this binding).
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
    loc_windTime: i32,
    saved_near: @TypeOf(rl.gl.rlGetCullDistanceNear()) = 0,
    saved_far: @TypeOf(rl.gl.rlGetCullDistanceFar()) = 0,

    pub fn init() Scene {
        const shader = rl.loadShaderFromMemory(sceneVS, sceneFS) catch @panic("scene shader");
        const depthShader = rl.loadShaderFromMemory(depthVS, depthFS) catch @panic("depth shader");
        var sun = SUN_DIR;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "sunDir"), &sun, .vec3);
        var slotShadow = SLOT_SHADOW;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "shadowMap"), &slotShadow, .int);
        var res: i32 = SHADOWMAP_RES;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "shadowMapResolution"), &res, .int);
        var haze = HAZE;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "hazeColor"), &haze, .vec3);
        var density: f32 = HAZE_DENSITY;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "hazeDensity"), &density, .float);
        var windOff: f32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "windAmt"), &windOff, .float);
        return .{
            .shader = shader,
            .depthShader = depthShader,
            .shadowMap = loadShadowmap(SHADOWMAP_RES),
            .lightVP = rl.math.matrixIdentity(),
            .loc_ground = rl.getShaderLocation(shader, "groundMode"),
            .loc_lightVP = rl.getShaderLocation(shader, "lightVP"),
            .loc_camPos = rl.getShaderLocation(shader, "camPos"),
            .loc_windAmt = rl.getShaderLocation(shader, "windAmt"),
            .loc_windTime = rl.getShaderLocation(shader, "windTime"),
        };
    }

    // Sun depth pass: call, draw casters (materials swapped to depthShader — drawMesh uses
    // the MATERIAL's shader, beginShaderMode won't reach it), then endShadowPass. Must run
    // BEFORE beginDrawing. The ortho box tracks `focus` (the hero), snapped to shadow
    // texels so walking doesn't make shadow edges crawl.
    pub fn beginShadowPass(self: *Scene, focus: rl.Vector3) void {
        const t = SHADOW_ORTHO / @as(f32, SHADOWMAP_RES);
        const fx = @round(focus.x / t) * t;
        const fz = @round(focus.z / t) * t;
        const cam = rl.Camera3D{
            .position = v3(fx + SUN_DIR.x * SUN_DIST, SUN_DIR.y * SUN_DIST, fz + SUN_DIR.z * SUN_DIST),
            .target = v3(fx, 0, fz),
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
    // Call once per frame after the depth pass, before drawing anything with this shader.
    pub fn bind(self: *Scene, camPos: rl.Vector3) void {
        rl.gl.rlActiveTextureSlot(SLOT_SHADOW);
        rl.gl.rlEnableTexture(self.shadowMap.depth.id);
        rl.gl.rlActiveTextureSlot(0);
        rl.setShaderValueMatrix(self.shader, self.loc_lightVP, self.lightVP);
        var cp = camPos;
        rl.setShaderValue(self.shader, self.loc_camPos, &cp, .vec3);
        var t: f32 = @floatCast(rl.getTime());
        rl.setShaderValue(self.shader, self.loc_windTime, &t, .float);
    }

    pub fn setGround(self: *Scene, on: bool) void {
        var m: i32 = if (on) 1 else 0;
        rl.setShaderValue(self.shader, self.loc_ground, &m, .int);
    }

    // Flora opt into vertex-shader sway; everything else (terrain, props, hero) draws rigid.
    // Toggle ON only around the flora draw, OFF immediately after.
    pub fn setWind(self: *Scene, on: bool) void {
        var a: f32 = if (on) 1.0 else 0.0;
        rl.setShaderValue(self.shader, self.loc_windAmt, &a, .float);
    }
};

// Procedural-mesh Builder — trimmed from zig-diablo's scenemesh.Builder (verbatim from
// zig-rts, plus toMesh for the FK-rigged hero which needs bare Meshes, not Models).
pub const Builder = struct {
    pos: std.ArrayList(f32),
    nrm: std.ArrayList(f32),
    uv: std.ArrayList(f32),
    col: std.ArrayList(u8),

    pub fn init() Builder {
        return .{
            .pos = std.ArrayList(f32).init(alloc),
            .nrm = std.ArrayList(f32).init(alloc),
            .uv = std.ArrayList(f32).init(alloc),
            .col = std.ArrayList(u8).init(alloc),
        };
    }

    fn vert(self: *Builder, p: rl.Vector3, n: rl.Vector3, c: rl.Color) void {
        self.pos.appendSlice(&.{ p.x, p.y, p.z }) catch @panic("oom");
        self.nrm.appendSlice(&.{ n.x, n.y, n.z }) catch @panic("oom");
        self.uv.appendSlice(&.{ 0, 0 }) catch @panic("oom");
        self.col.appendSlice(&.{ c.r, c.g, c.b, c.a }) catch @panic("oom");
    }

    pub fn quad(self: *Builder, a: rl.Vector3, b: rl.Vector3, c: rl.Vector3, d: rl.Vector3, n: rl.Vector3, col: rl.Color) void {
        self.vert(a, n, col);
        self.vert(b, n, col);
        self.vert(c, n, col);
        self.vert(a, n, col);
        self.vert(c, n, col);
        self.vert(d, n, col);
    }

    // Axis-aligned box centered at `c` with full `size`. Faces wind CCW seen from
    // OUTSIDE — raylib culls back faces, so inward winding renders boxes hollow (you
    // see through the near wall into the far interior; the cylinders always wound
    // correctly, which is why limbs looked solid while heads/torsos looked see-through).
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

    // Parallelepiped from a center and three half-axis vectors — the oriented cousin of
    // addCube. Face normals are the normalized axes. Winding matches addCube (CCW from
    // outside); a LEFT-handed axis triple is normalized first so callers can pass axes
    // in any order without turning the box inside-out.
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

    // Tapered cylinder (no caps) a(radius ra) -> b(radius rb). Limbs use this for a
    // rounded, organic read; rb≈0 for spikes.
    pub fn addCylinder(self: *Builder, a: rl.Vector3, b: rl.Vector3, ra: f32, rb: f32, sides: i32, col: rl.Color) void {
        const axis = norm3(v3(b.x - a.x, b.y - a.y, b.z - a.z));
        const seed = if (@abs(axis.y) < 0.99) v3(0, 1, 0) else v3(1, 0, 0);
        const u = norm3(cross(axis, seed));
        const w = norm3(cross(axis, u));
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
            self.quad(p0, p1, p2, p3, nmid, col);
        }
    }

    // Upload to the GPU as a bare Mesh (CPU arrays stay attached; the mesh lives the whole
    // program). The FK hero draws these directly with per-bone matrices via drawMesh.
    pub fn toMesh(self: *Builder) rl.Mesh {
        const pos = self.pos.toOwnedSlice() catch @panic("oom");
        const nrm = self.nrm.toOwnedSlice() catch @panic("oom");
        const uv = self.uv.toOwnedSlice() catch @panic("oom");
        const col = self.col.toOwnedSlice() catch @panic("oom");
        var mesh = std.mem.zeroes(rl.Mesh);
        mesh.vertexCount = @intCast(pos.len / 3);
        mesh.triangleCount = @intCast(pos.len / 9);
        mesh.vertices = pos.ptr;
        mesh.normals = nrm.ptr;
        mesh.texcoords = uv.ptr;
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
