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
const SLOT_SOIL: i32 = 13;

/// THE SOIL GRID's resolution across the whole world. 112 cells over a 560 m map is 5 m a cell,
/// which is about the smallest patch of ground worth painting by hand — and the sample position
/// is noise-jittered in the shader, so a cell edge never reads as a 5 m step.
///
/// It is a count, not a pitch, so it has to GROW WITH THE WORLD or a bigger map paints in bigger
/// blocks: at 64 over 560 m a "cell" is 8.75 m, which is a brush you cannot draw a path with.
/// Costs one byte per cell everywhere it is stored — the texture, `wf.Map.soil`, and 24 of those
/// in the editor's undo ring, so ~300 KB of BSS for the increase.
pub const SOIL_N: i32 = 112;

// THE SUN — one hard directional light. Single source for the shader uniform and shadow
// camera so shading and cast shadows can't disagree; low golden-hour elevation (~33 deg)
// throws long raking amber shadows.
pub const SUN_DIR = norm3(v3(-0.60, 0.50, -0.46));

// ── THE SHADOW BOX ── the single trade in the whole renderer: DISTANCE against CRISPNESS
// against the depth pass's draw count. Texel size is SHADOW_ORTHO / SHADOWMAP_RES, and the
// depth pass has to draw every caster that can throw INTO the box, so widening it costs draws
// quadratically while resolution costs only fill.
//
// Owner's call: reach matters more than edge fidelity here, and 44 m (±22 around the hero) cut
// shadows off well inside the visible field — you could watch a great tree's shadow pop in. 108
// with the map doubled to 8192 is 2.5x the reach for a texel that only coarsens 0.011 → 0.013 m,
// and it lands the cut-off out where the haze is already eating detail.
pub const SHADOWMAP_RES = 8192;
// PUBLIC because env's depth-pass cull must know how big the box is to decide what can throw a
// shadow into it — one source, so changing the box can't leave the cull wrong in either
// direction (too small pops shadows, too large re-drops the perf you just bought).
pub const SHADOW_ORTHO = 108.0;
const SUN_DIST = 120.0; // shadow camera distance along SUN_DIR
// Depth slab around the casters, kept as TIGHT as the box allows. Ortho depth is LINEAR over
// near..far, so the shader's NDC bias costs bias*(far-near) WORLD units — widen the slab and
// small casters' shadows start to detach. The box's own half-diagonal sets the floor: a corner
// 76 m out along the view axis has to stay inside, so the slab tracks SHADOW_ORTHO.
const SHADOW_CLIP_NEAR = SUN_DIST - SHADOW_ORTHO * 0.78;
const SHADOW_CLIP_FAR = SUN_DIST + SHADOW_ORTHO * 0.78;

// The haze color the world fades into with distance (authored pre-gamma — the shader
// gammas output, so dark values lift). The sky shader's horizon band is authored to the
// DISPLAYED value of this so the seam disappears.
pub const HAZE = v3(0.078, 0.070, 0.056);
// Haze falloff: 1-exp(-density*dist). PULLED BACK from the old 0.021 (which was ~63% hazed by
// 48 units) when the world grew to env.HALF 160: at that density everything past ~100 units was
// flat haze, so seven eighths of the map was reachable but invisible. At 0.013 it's ~63% by 75
// units and ~88% by 160, so the far cliffs / horizon gate / great trees still dissolve into
// golden-hour SILHOUETTES — you just get to see the world's scale from the start point.
const HAZE_DENSITY: f32 = 0.013;

// ── POINT LIGHTS ── torches, braziers, campfires, the grace ember. The sun can't reach inside
// a roofed ruin, so an interior needs its own light or it's a black hole; these are what make
// the chapel/watchtower interiors readable. Small fixed set of uniforms, filled each frame with
// the lights NEAREST the camera (env.uploadLights) — the world holds far more than MAX_LIGHTS,
// but only the ones you can see are ever on the GPU.
pub const MAX_LIGHTS = 16;
comptime {
    // The scene FS declares `lightPos/lightCol/lightRad[16]` as literals — GLSL array sizes can't
    // read a Zig constant. Raising MAX_LIGHTS without editing all three declarations would overrun
    // the uniform arrays, so fail the BUILD instead (same guard style as `Mat`'s water/marble ids).
    @setEvalBranchQuota(200_000); // scanning a ~9 KB shader source three times at comptime
    std.debug.assert(MAX_LIGHTS == 16);
    std.debug.assert(std.mem.indexOf(u8, sceneFS, "lightPos[16]") != null);
    std.debug.assert(std.mem.indexOf(u8, sceneFS, "lightCol[16]") != null);
    std.debug.assert(std.mem.indexOf(u8, sceneFS, "lightRad[16]") != null);
}
pub const Light = struct {
    pos: rl.Vector3,
    col: rl.Vector3, // colour PRE-MULTIPLIED by intensity (pre-gamma, like every other colour here)
    radius: f32, // falloff reaches exactly zero here, so a light can never leak past its room
};

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
    \\in vec2 vertexTexCoord2;
    \\in vec3 vertexNormal;
    \\in vec4 vertexColor;
    \\uniform mat4 mvp;
    \\uniform mat4 matModel;
    \\uniform float windAmt;   // 0 = rigid (terrain / props / hero); 1 = flora opts into sway
    \\uniform float uTime;     // seconds — drives the flora sway phase AND the water ripples (FS)
    \\out vec3 fragPosition;
    \\out vec4 fragColor;
    \\out vec3 fragNormal;
    \\out vec2 fragUV;
    \\out float fragMatF;
    \\void main() {
    \\    vec3 p = vertexPosition;
    \\    if (windAmt > 0.0) {
    \\        // Flora sway: bend grows with height^2 so bases stay planted while tips lean;
    \\        // phase keys off the clump's WORLD origin so neighbours move as one gust field.
    \\        vec3 baseW = vec3(matModel*vec4(0.0, 0.0, 0.0, 1.0));
    \\        float h = max(p.y, 0.0);
    \\        float bend = h*h*windAmt*0.10;
    \\        float phase = uTime*1.5 + baseW.x*0.6 + baseW.z*0.5;
    \\        float sway = sin(phase) + 0.3*sin(phase*2.7 + 1.3);
    \\        p.x += bend*sway;
    \\        p.z += bend*sway*0.4;
    \\    }
    \\    // ---- FIRE MOVES ---- flame meshes are permanent geometry like every other prop, so the
    \\    // writhe has to happen HERE. Amplitude grows with height ABOVE THE FUEL (texcoords2.y
    \\    // carries the flame's own base, written by props.flameInto), so the coals stay welded to
    \\    // the hearth and only the tongues dance — keyed off p.y alone the whole fire would slide.
    \\    // THREE incommensurate motions, because a flame that only waves side to side reads as a
    \\    // flag: a fast lateral lash, a slower twist about the fire's own axis, and a vertical
    \\    // BREATHE that makes it gutter and flare. Phased off the prop's WORLD origin so no two
    \\    // fires in a room dance in lockstep — the same argument env.gutter makes for their light,
    \\    // and this is its visible half (the light has been guttering all along; the flame it was
    \\    // supposed to be coming off has been standing perfectly still).
    \\    // FOUR things have to be true or it reads as a rigid object being waved about, which is
    \\    // exactly how the first version came out — only (1) was:
    \\    //
    \\    //  1. AMPLITUDE GROWS WITH HEIGHT ABOVE THE FUEL, so the coals stay welded to the hearth.
    \\    //  2. EACH TONGUE HAS ITS OWN PHASE. Keyed off the prop origin alone, every vertex of a
    \\    //     fire shared one phase and the whole flame leaned left and right AS ONE PIECE — the
    \\    //     "moves in one piece" failure the rig rules call out for humanoids, on a fire. A
    \\    //     vertex's own offset from the fire's axis differs tongue to tongue, which de-syncs
    \\    //     them while keeping each tongue coherent (a blob is small beside the gap between
    \\    //     tongues).
    \\    //  3. THE WRINKLES TRAVEL UP. The -hh term advects the wave toward the tip. Without it a
    \\    //     tongue lashes in place, and a thing that lashes in place is a flag, not a flame.
    \\    //  4. IT PINCHES AND LEAPS. Motion that only translates reads as a solid being shaken,
    \\    //     however fast you shake it; fire necks, swells and shoots.
    \\    if (vertexTexCoord2.x > 10.5) {
    \\        vec3 baseW = vec3(matModel*vec4(0.0, 0.0, 0.0, 1.0));
    \\        // CLAMPED: the drifting wisps are authored up to a whole unit above the fuel, and an
    \\        // h-squared term would fling those across the room.
    \\        float hh = clamp(p.y - vertexTexCoord2.y, 0.0, 0.6);
    \\        float w = hh*hh;
    \\        float tongue = p.x*9.3 + p.z*7.7;        // per-tongue — they sit at different offsets
    \\        float seed = baseW.x*1.7 + baseW.z*1.3;  // …and no two FIRES gutter together
    \\        // SLOWED AND SMOOTHED (owner: the flames read skinny and weird). The base rate came
    \\        // down by a third and the two top octaves were more than halved: at 7.4 rad/s with a
    \\        // 9x octave on it, a narrow tongue was being shaken faster than the eye can integrate,
    \\        // which is what read as buzzing wire rather than as fire. The tongues are now FAT (see
    \\        // props.flameInto), and a fat lobe wants to roll and swell, not vibrate — so the slow
    \\        // terms carry the motion and the fast ones only stop it looking looped.
    \\        float ph = uTime*4.9 + seed + tongue - hh*9.0;
    \\        float lash  = sin(ph) + 0.42*sin(ph*2.31 + 1.7) + 0.12*sin(ph*4.70 + 0.4) + 0.05*sin(ph*9.10);
    \\        float twist = sin(ph*0.61 + 2.1) + 0.40*sin(ph*1.90 + 3.3);
    \\        // AMPLITUDE IS A FRACTION OF A TONGUE'S WIDTH, NOT OF ITS HEIGHT. This was 0.45, which
    \\        // displaced a tip by 0.22 — a tongue is 0.03..0.055 wide, so it was being sheared three
    \\        // times its own width and came out a bent noodle with the facet folds to prove it. A
    \\        // flame leans and shimmers; it does not swing across itself.
    \\        // …and eased down again (owner: all flames a bit more subtle). Fire SIMMERS more than it
    \\        // thrashes; the tell is the shape reorganising, not the distance travelled.
    \\        // …then RAISED, because the tongues got SHORTER. `w` here is hh SQUARED, so dropping the
    \\        // height band by a third cut the lateral swing to well under half without anyone asking
    \\        // for that — the flames went stiff at the same moment they went fat. These put the
    \\        // travel back where it was in world units, which against a wider lobe reads as the whole
    \\        // tongue ROLLING rather than a wire being flicked.
    \\        p.x += w*0.150*lash  + hh*0.034*twist;
    \\        p.z += w*0.125*twist - hh*0.028*lash;
    \\        // SHOOT: tongues leap and drop back, biased upward — fire climbs. The VERTICAL is where
    \\        // a flame's amplitude legitimately lives, so this carries most of the motion now.
    \\        p.y += hh*(0.105*sin(ph*0.83 + 0.9) + 0.040*sin(ph*2.7)) + w*0.150*max(0.0, sin(ph*0.47));
    \\        // NECK, about the prop's own axis — which is where a torch's flame sits. A brazier's
    \\        // or a bonfire's SECOND tongue is offset up to 0.2, so for that one this also nudges
    \\        // sideways; at this amplitude that reads as sway, so it stays the cheap approximation.
    \\        // Eased off with the widening: a fat lobe necking as hard as a thin one did reads as an
    \\        // hourglass, and the swelling is supposed to be the subtle half of the writhe.
    \\        float pinch = 1.0 + 0.17*hh*sin(ph*1.37 + 0.7);
    \\        p.x *= pinch;
    \\        p.z *= pinch;
    \\    }
    \\    fragPosition = vec3(matModel*vec4(p, 1.0));
    \\    fragColor = vertexColor;
    \\    fragNormal = normalize(mat3(matModel)*vertexNormal);
    \\    fragUV = vertexTexCoord;      // surface-anchored, ~world units (Builder authors these)
    \\    fragMatF = vertexTexCoord2.x; // material id (gfx.Mat), constant per face
    \\    gl_Position = mvp*vec4(p, 1.0);
    \\}
;
// Lighting model (softness tricks ported from zig-diablo/zig-rts):
//  - BARELY-WRAPPED LAMBERT: (N.L + 0.12)/1.12 clamped — shaded faces roll off gently.
//  - HEMISPHERE AMBIENT: cool sky from above, warm dirt bounce from below.
//  - CAST SHADOW (3x3 PCF): the shadow term kills the sun AND eats the ambient, so
//    shadow pools run deep and cool without collapsing to black.
//  - EMISSIVE CHANNEL: vertex alpha < 255 marks self-lit material (embers, glints).
//  - POINT LIGHTS: up to MAX_LIGHTS warm torch/fire lights, quadratic falloff to zero at
//    their radius, HEAVILY wrapped (+0.35) so a torch fills a room instead of spotlighting
//    the one wall it faces. They stack on top of the sun key, and they are NOT shadowed
//    (there is one shadow map and it belongs to the sun).
//  - DISTANCE HAZE: mix toward HAZE by 1-exp(-density*dist-from-camera) — atmosphere.
//  - GAMMA + DITHER: pow(1/2.2) then +-1 LSB screen noise so near-dark gradients don't
//    band on an 8-bit target. Gamma lifts dark albedos hard — author colors near-black.
const sceneFS =
    \\#version 330
    \\in vec3 fragPosition;
    \\in vec4 fragColor;
    \\in vec3 fragNormal;
    \\in vec2 fragUV;
    \\in float fragMatF;
    \\uniform vec3 sunDir;      // normalized, surface -> sun
    \\uniform int groundMode;   // 1 = terrain (procedural grain), 0 = props/hero
    \\uniform vec3 camPos;      // for distance haze
    \\uniform vec3 hazeColor;   // sky/haze tint (pre-gamma)
    \\uniform float hazeDensity;
    \\uniform float hitFlash;   // 0..1 blood-red combat flash on the CURRENT draw (per-actor)
    \\uniform float uTime;      // seconds — water ripple phase (shared with the VS wind term)
    \\uniform mat4 lightVP;     // sun's ortho view-projection (captured in the depth pass)
    \\uniform sampler2D shadowMap;
    \\uniform int shadowMapResolution;
    \\uniform vec3 lightPos[16];  // MAX_LIGHTS torch/fire lights, nearest-first
    \\uniform vec3 lightCol[16];  // colour * intensity (pre-gamma)
    \\uniform float lightRad[16];
    \\uniform int nLights;
    \\out vec4 finalColor;
    \\float hash21(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
    \\float vnoise(vec2 p){ vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    \\  return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x), mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y); }
    \\float speck(vec2 p, float s){ return hash21(floor(p*s)); }
    \\// ---- DETAIL LOD: the fix for distant SIZZLE ----------------------------------------------
    \\// Every pattern below is procedural, sampled ONCE per fragment at a FIXED frequency in world/UV
    \\// units. Near the camera a pixel covers a fraction of a cycle and it resolves; far away a pixel
    \\// spans many cycles, so the single sample it takes is essentially random — and it re-randomises
    \\// as the camera moves a sub-pixel amount. That is the flicker on small distant objects, and MSAA
    \\// cannot touch it (MSAA supersamples COVERAGE; shading still runs once per pixel).
    \\//
    \\// A texture solves this with mipmaps. Procedural noise has no mip chain, so build one by hand:
    \\// measure the fragment's footprint in the pattern's own coordinate space with screen-space
    \\// derivatives, and where a term's cycle is smaller than that footprint, fade it to its MEAN
    \\// (0.5 for vnoise/speck/mottle) — which is exactly what a correctly-filtered texel would be.
    \\// Below Nyquist nothing changes, so the near-field look is untouched to the bit.
    \\//
    \\// `fwidth` must be evaluated in UNIFORM control flow, so main() computes the footprints up front
    \\// and passes them down rather than each helper taking its own derivative inside a branch.
    \\float uvFoot(vec2 q){ return length(fwidth(q)); }
    \\// How unresolvable a `freq`-cycles-per-unit term is at this footprint: 0 = fine, 1 = mush.
    \\float band(float freq, float px){ return smoothstep(0.35, 1.0, px*freq); }
    \\float fvn(vec2 q, float freq, vec2 off, float px){ return mix(vnoise(q*freq + off), 0.5, band(freq, px)); }
    \\float fvn2(vec2 q, vec2 freq, vec2 off, float px){ return mix(vnoise(q*freq + off), 0.5, band(max(freq.x, freq.y), px)); }
    \\// speck is a HARD hash (floor, no interpolation), so it is the worst offender of the lot.
    \\float fspk(vec2 q, float freq, float px){ return mix(speck(q, freq), 0.5, band(freq, px)); }
    \\// ---- SPECULAR ANTI-ALIASING ---------------------------------------------------------------
    \\// The albedo LOD above fixes patterns; this fixes HIGHLIGHTS, which alias for the same reason.
    \\// A pow(nh, 320) lobe is far narrower than a pixel on anything distant, so whether it lands on
    \\// this fragment is luck — and it stops being the same luck the instant the camera moves, which
    \\// is the blink. Returns a 0..1 sharpness: widen the lobe by it AND dim the peak by it, so the
    \\// pixel keeps roughly the energy it ought to average to instead of gambling on a direct hit
    \\// (the cheap end of Toksvig). 1 = full sharpness up close, nothing changes.
    \\// FLOORED at 0.05 for two reasons: it keeps a hint of sheen on the furthest surfaces instead of
    \\// mathematically deleting the highlight, and it keeps the exponent strictly positive — an
    \\// exponent that reached 0 would hit pow(0.0, 0.0), which GLSL leaves undefined and which can
    \\// hand a NaN straight into the haze mix.
    \\float lobe(float px, float k){ return max(1.0/(1.0 + px*k), 0.05); }
    \\// ---- TERRAIN ALBEDO ---- dry golden grassland (pre-gamma, so everything starts
    \\// dark): sun-bleached khaki grass drifting to damp green, a worn dirt path down the
    \\// ruin avenue (x ~ 0, edges wobbled), stony patches, and dark scrub clumps. All
    \\// smooth field noise — no coarse per-tile specks, which read as a checkerboard.
    \\// ---- PAINTED SOIL ---- an OVERRIDE laid over the procedural floor above, never a
    \\// replacement for it: id 0 means "nobody painted here" and the field below returns the
    \\// ground untouched, so the whole authored look survives by construction and painting is
    \\// purely additive. The grain (blades / f3) is carried THROUGH the override, or a painted
    \\// patch reads as flat plastic against the ground it sits in.
    \\uniform sampler2D soilMap;
    \\uniform float soilHalf;    // world half-extent the grid spans
    \\uniform float soilCell;    // metres per grid cell — the scale the coverage ring samples at
    \\uniform int   soilOn;      // 0 = nothing painted anywhere; skip the fetch entirely
    \\vec3 soilColor(int id){
    \\  // Authored NEAR-BLACK like every other albedo here — the shader's hot key plus the
    \\  // gamma lift turns any mid-dark value pale where a big face takes the sun square on.
    \\  if (id==1) return vec3(0.130, 0.106, 0.074);  // trodden dirt / a path worn through
    \\  if (id==2) return vec3(0.072, 0.098, 0.042);  // green turf
    \\  if (id==3) return vec3(0.132, 0.134, 0.130);  // stone, flagged or scoured bare
    \\  if (id==4) return vec3(0.150, 0.132, 0.090);  // pale silt, the tarn's margin
    \\  if (id==5) return vec3(0.062, 0.058, 0.054);  // ash and burnt ground
    \\  return vec3(0.046, 0.062, 0.034);             // 6 = deep moss
    \\}
    \\int soilAt(vec2 w){
    \\  vec2 uv = w/(2.0*soilHalf) + 0.5;
    \\  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0;
    \\  return int(texture(soilMap, uv).r*255.0 + 0.5);
    \\}
    \\vec3 paintedSoil(vec3 c, vec2 p, float blades, float f3, float px){
    \\  if (soilOn == 0) return c;
    \\  // JITTER THE LOOKUP, don't filter the id. Ids do not interpolate — blending 2 and 4
    \\  // gives 3, a material nobody painted — so the cell edge is broken up by pushing the
    \\  // SAMPLE POSITION around instead, which turns a 5 m staircase into a ragged margin.
    \\  vec2 j = vec2(vnoise(p*0.62), vnoise(p*0.62 + 47.3)) - 0.5;
    \\  vec2 q = p + j*3.4;
    \\  // …then SOFTEN IT BY COVERAGE. The jitter alone still gives a hard in/out at every
    \\  // texel — the boundary is ragged but it is still a cliff, and against a procedural
    \\  // floor that cross-fades over metres it reads as a decal laid on the world. So sample a
    \\  // ring around the point and blend by HOW MANY taps agree: deep inside a patch every tap
    \\  // agrees and the paint is full strength, at the margin only some do and it fades out.
    \\  // Cheap, and it cannot invent a material — coverage weights an id, it never mixes two.
    \\  vec2 o[4] = vec2[4](vec2(1.0,0.0), vec2(-1.0,0.0), vec2(0.0,1.0), vec2(0.0,-1.0));
    \\  int id = soilAt(q);
    \\  float cov = (id != 0) ? 1.0 : 0.0;
    \\  for (int i = 0; i < 4; i++){
    \\    int t = soilAt(q + o[i]*soilCell*0.85);
    \\    if (t == 0) continue;
    \\    if (id == 0) id = t;          // the centre is bare but a neighbour is painted: fade IN
    \\    if (t == id) cov += 1.0;
    \\  }
    \\  if (id == 0) return c;
    \\  vec3 s = soilColor(id)*(0.80 + 0.50*blades + 0.20*f3);
    \\  return mix(c, s, (cov/5.0)*0.92);
    \\}
    \\vec3 terrainAlbedo(vec2 p, float px){
    \\  float f1 = fvn(p, 0.055, vec2(0.0), px);
    \\  float f2 = fvn(p, 0.35, vec2(7.7), px);
    \\  float f3 = fvn(p, 1.6, vec2(3.1), px);
    \\  // `blades` is the ground's sizzle: a 7-cycle noise plus a 31-cell HARD hash. Past a few tens
    \\  // of metres both are far under a pixel, and they were what made the whole plain crawl.
    \\  float blades = fvn(p, 7.0, vec2(0.0), px)*0.65 + fspk(p, 31.0, px)*0.35;
    \\  vec3 dry = vec3(0.140, 0.114, 0.058);
    \\  vec3 grn = vec3(0.080, 0.100, 0.048);
    \\  vec3 c = mix(grn, dry, smoothstep(0.22, 0.78, f1 + 0.30*(f2 - 0.5)));
    \\  c *= 0.80 + 0.50*blades + 0.20*f3;
    \\  float wob = (vnoise(vec2(p.y*0.13, 3.7)) - 0.5)*3.2; // 0.13 cycles/unit — resolves to the horizon
    \\  float path = smoothstep(2.8, 1.2, abs(p.x + wob));
    \\  vec3 dirt = vec3(0.130, 0.110, 0.082)*(0.80 + 0.40*f3)*(0.88 + 0.24*fspk(p, 21.0, px));
    \\  c = mix(c, dirt, path*0.85);
    \\  float rocky = smoothstep(0.64, 0.86, fvn(p, 0.09, vec2(47.1), px));
    \\  vec3 rock = vec3(0.140, 0.142, 0.140)*(0.78 + 0.40*fvn(p, 2.7, vec2(0.0), px))*(0.88 + 0.24*fspk(p, 11.0, px));
    \\  c = mix(c, rock, rocky*(1.0 - path)*0.9);
    \\  float scrub = smoothstep(0.68, 0.90, fvn(p, 0.22, vec2(8.9), px))*(1.0 - rocky)*(1.0 - path);
    \\  c = mix(c, vec3(0.042, 0.055, 0.026)*(0.7 + 0.6*blades), scrub*0.8);
    \\  // REGION DRIFT. The five regions each grow their own flora, but the SOIL underneath them was
    \\  // one field, so the wood's floor read as the same dry gold meadow with trees standing on it.
    \\  // West goes damp and green (shaded, leaf-littered); east goes silty and pale toward the tarn.
    \\  // The wood gets a floor of its OWN, not a tint over the meadow's: leaf mould drifting into
    \\  // damp shaded turf, mottled at a few metres' scale. Tinting the grassland green only made a
    \\  // brighter, more saturated LAWN — the floor of a closed wood is darker AND browner AND
    \\  // patchier than open ground, and all three of those have to change together.
    \\  float wood = smoothstep(-46.0, -104.0, p.x);
    \\  if (wood > 0.001){
    \\    vec3 litter = vec3(0.058, 0.050, 0.030);   // last year's leaves
    \\    vec3 shade  = vec3(0.040, 0.056, 0.032);   // moss and damp turf
    \\    float m = fvn(p, 0.13, vec2(21.3), px)*0.7 + fvn(p, 0.44, vec2(5.1), px)*0.3;
    \\    vec3 floorC = mix(shade, litter, smoothstep(0.34, 0.72, m))*(0.78 + 0.55*blades);
    \\    c = mix(c, floorC, wood*0.86);
    \\  }
    \\  float marsh = smoothstep(44.0, 108.0, p.x);
    \\  c = mix(c, c*vec3(1.06, 0.97, 0.74), marsh*0.42);
    \\  c = paintedSoil(c, p, blades, f3, px);
    \\  return c*(0.78 + 0.22*fvn(p, 0.03, vec2(9.7), px));
    \\}
    \\// ---- SURFACE MATERIALS ---- every Builder mesh carries a material id (gfx.Mat, in
    \\// vertexTexCoord2.x) plus surface-anchored UVs in ~world units, so patterns stick to
    \\// bones and props instead of swimming through world space when they animate. Patterns
    \\// are VALUE-only multiplies around 1.0 (the authored hue survives) held inside ~+-20%
    \\// — weathered surface read, never wallpaper. Keep them QUIET.
    \\float mottle(vec2 p){ return vnoise(p)*0.6 + vnoise(p*3.7 + 11.3)*0.4; }
    \\// mottle is TWO octaves (freq and 3.7*freq), and they must be banded SEPARATELY. Filtering the
    \\// pair against one frequency throws the coarse octave away as soon as the fine one goes — which
    \\// flattened toad hide and plant clumps at middle distance, where the broad blotches still had
    \\// several pixels each and should have survived. Per-octave is what a real mip chain does.
    \\float fmot(vec2 q, float freq, float px){
    \\  return mix(vnoise(q*freq), 0.5, band(freq, px))*0.6
    \\       + mix(vnoise(q*freq*3.7 + 11.3), 0.5, band(freq*3.7, px))*0.4;
    \\}
    \\// ---- WEATHERING ---- dirt does not fall evenly. It RUNS DOWN verticals, SETTLES on anything
    \\// facing the sky, and lichen takes the faces that never see the sun. All three key off the
    \\// world NORMAL, so they land where the GEOMETRY says they should instead of being one more
    \\// octave of noise — which is the whole difference between a surface that reads as aged and one
    \\// that reads as merely busy. A thousand years outdoors is the point of every ruin out here, and
    \\// none of it was being said.
    \\vec3 weather(vec3 c, vec2 q, vec3 n, float px){
    \\  float up = clamp(n.y, 0.0, 1.0);   // 1 = a ledge, a step tread, the top of a fallen drum
    \\  float vert = 1.0 - abs(n.y);       // 1 = a wall or a column shaft, 0 = a floor or a soffit
    \\  // RUNOFF: streaks stretched hard along the vertical, on the verticals only. Rain gathers as
    \\  // it falls, so this is what puts the dark tails under every ledge and cornice.
    \\  float streak = fvn2(q, vec2(7.0, 0.35), vec2(13.7), px)*0.65
    \\               + fvn2(q, vec2(19.0, 0.70), vec2(5.3), px)*0.35;
    \\  c *= 1.0 - 0.16*vert*smoothstep(0.45, 0.95, streak);
    \\  // SETTLED DIRT on whatever faces the sky, broken up so a ledge is grimy in patches and not
    \\  // uniformly dimmed (which would just read as the light being wrong).
    \\  c *= 1.0 - 0.13*up*smoothstep(0.30, 0.85, fvn(q, 1.7, vec2(41.3), px));
    \\  // LICHEN takes the COLD faces — biased away from the low western sun (gfx.SUN_DIR) — and it
    \\  // TINTS rather than darkens. This is the one place these patterns touch HUE, deliberately:
    \\  // the house rule is value-only because value keeps the authored palette, but a grey-green
    \\  // bloom on old stone is a colour event and no amount of darkening can say it. Kept low and
    \\  // desaturated for exactly the reason the rule exists.
    \\  float cold = clamp(-(n.x*0.6 + n.z*0.8), 0.0, 1.0);
    \\  float lich = smoothstep(0.55, 0.92, fvn(q, 1.1, vec2(59.1), px))*cold*vert;
    \\  return mix(c, c*vec3(0.78, 0.94, 0.72), lich*0.55);
    \\}
    \\vec3 matAlbedo(int m, vec2 q, vec3 base, vec3 n, float px){
    \\  if (m == 1){        // STONE: blotch at TWO scales, two-octave grain, soft strata, ROUNDED pits.
    \\    // All smooth value noise — hard speck/step cells read as square pixels on a
    \\    // close column face, so weathering must stay soft-edged.
    \\    // TWO SCALES OF BLOTCH, not one. A single 2.1-cycle term is a ~0.5 m patch: right for a
    \\    // wall block, and it leaves a 15 m cliff face or the colossal gate with NO variation at
    \\    // the scale of the MASS — so the biggest surfaces in the world came back as flat tan
    \\    // planes, which is the same failure the near-black albedos and the form breaks exist to
    \\    // fight. The old 0.24 is SPLIT between the two, so the range and the mean are unchanged
    \\    // to the bit: this is more scale coverage at exactly the old loudness, not more noise.
    \\    float mass = fvn(q, 0.30, vec2(17.3), px);
    \\    float blotch = fvn(q, 2.1, vec2(0.0), px);
    \\    float grain = fvn(q, 6.1, vec2(4.7), px)*0.6 + fvn(q, 12.3, vec2(9.2), px)*0.4;
    \\    float strata = fvn2(q, vec2(0.4, 3.4), vec2(23.1), px);
    \\    base *= (0.88 + 0.12*mass + 0.12*blotch)*(0.94 + 0.12*grain)*(0.94 + 0.12*strata);
    \\    // …and the pits read as EROSION rather than as pepper. At 9 cycles/unit they were 11 cm
    \\    // dots, all the same size and all the same value — dirt sprinkled on the rock. Bigger,
    \\    // fewer and softer-edged (a wider smoothstep takes fewer of them) is a weathered hollow.
    \\    base *= 1.0 - 0.15*smoothstep(0.70, 0.97, fvn(q, 5.5, vec2(31.7), px));
    \\    base = weather(base, q, n, px);   // rubble masonry has stood out in the rain the longest
    \\  } else if (m == 2){ // WOOD: long grain streaks along v, slow wander, BOARD scale
    \\    float grain = fvn2(q, vec2(9.0, 0.8), vec2(0.0), px);
    \\    // Timber comes in PIECES. Without a board scale a cart bed, a palisade or a woodpile is
    \\    // one continuous streak field running straight through every plank in it.
    \\    float board = fvn2(q, vec2(0.35, 2.6), vec2(31.1), px);
    \\    base *= (0.82 + 0.30*grain)*(0.94 + 0.12*fvn(q, 2.9, vec2(5.1), px))*(0.95 + 0.10*board);
    \\  } else if (m == 3){ // CLOTH: soft anisotropic weave + broad wrinkle shading + FOLDS
    \\    float weave = fvn2(q, vec2(30.0, 3.2), vec2(0.0), px)*0.5 + fvn2(q, vec2(3.2, 30.0), vec2(9.7), px)*0.5;
    \\    // Broad banding along the hang, anisotropic the OTHER way from the weave: a banner has to
    \\    // read as cloth carrying its own weight, not as a painted board.
    \\    float fold = fvn2(q, vec2(1.1, 0.22), vec2(17.9), px);
    \\    base *= (0.91 + 0.15*weave)*(0.92 + 0.15*fvn(q, 1.7, vec2(2.3), px))*(0.94 + 0.12*fold);
    \\  } else if (m == 4){ // STEEL: fine brush lines along the length + broad soft tarnish + PITTING
    \\    // 46 cycles/unit is the highest frequency in the whole shader — a blade or a helm seen
    \\    // across the avenue was sampling it once per pixel and strobing.
    \\    float brush = fvn2(q, vec2(46.0, 2.3), vec2(0.0), px);
    \\    base *= (0.94 + 0.11*brush)*(0.95 + 0.10*fvn(q, 0.9, vec2(7.7), px));
    \\    // Old iron is not evenly bright. A few soft dark freckles where the rust took, low enough
    \\    // in frequency to read as damage to the metal rather than as dirt lying on it.
    \\    base *= 1.0 - 0.12*smoothstep(0.68, 0.95, fvn(q, 3.3, vec2(27.7), px));
    \\  } else if (m == 5){ // LEATHER: pore stipple + crease mottle + PANEL scale
    \\    base *= (0.90 + 0.17*fvn(q, 13.0, vec2(0.0), px))*(0.92 + 0.15*fvn(q, 3.1, vec2(6.3), px));
    \\    // A bracer, a pauldron and a scabbard are CUT PIECES; one pore field across the lot of
    \\    // them reads as moulded plastic however good the pores are.
    \\    base *= 0.95 + 0.10*fvn(q, 0.80, vec2(37.3), px);
    \\  } else if (m == 6){ // SKIN: faint soft mottle only
    \\    base *= 0.94 + 0.11*fmot(q, 4.6, px);
    \\  } else if (m == 7){ // HIDE: amphibian blotch patches + fine wart grain — DARKEN
    \\    // only (max ~1.0): the bog toad must stay a near-black night thing, its blotches
    \\    // reading as damp shadow, never pale camo.
    \\    float patch = smoothstep(0.35, 0.75, fvn(q, 2.4, vec2(0.0), px));
    \\    base *= (0.72 + 0.26*patch)*(0.88 + 0.12*fvn(q, 8.2, vec2(3.3), px));
    \\  } else if (m == 8){ // PLANT: broad value drift so clumps read as many blades
    \\    base *= 0.87 + 0.22*fmot(q, 2.2, px);
    \\    // …and a LEAF-scale octave on top. The broad drift says "this is a clump"; this says the
    \\    // clump is made of separate leaves. The new cliff ivy needed it more than anything —
    \\    // without it a creeper cluster is one flat green lump stuck to the rock.
    \\    base *= 0.93 + 0.14*fvn(q, 9.0, vec2(13.1), px);
    \\  } else if (m == 10){ // MARBLE: a cool body crossed by wandering VEINS, plus the crazing
    \\    // and dull weathered patches a thousand years outdoors puts on burnished stone. This
    \\    // is the one material allowed past the +-20% house limit: a vein that stays inside it
    \\    // is a smudge, and marble without veins is just pale stone. The wobble term is what
    \\    // keeps them WANDERING — a clean sin() gives you barber-shop stripes.
    \\    float wob  = fvn(q, 0.9, vec2(0.0), px)*1.7 + fvn(q, 2.7, vec2(3.1), px)*0.55;
    \\    // The veins are the one pattern whose mean ISN'T 0.5: pow(1-|sin|, n) is a thin spike, so it
    \\    // averages to about 1/(n·pi/2) — 0.09 at n=7, 0.05 at n=13. Fading them to 0.5 would turn a
    \\    // distant column into a dark smear and fading them to 0 would brighten it; fade to the true
    \\    // mean and the column keeps its overall value while the stripes stop strobing. Their thinness
    \\    // makes them alias far above their nominal ~7 cycles/unit, hence the 20/26 bands.
    \\    float vein = mix(pow(1.0 - abs(sin((q.x*0.8 + q.y*2.4 + wob)*3.1)), 7.0), 0.09, band(20.0, px));
    \\    float hair = mix(pow(1.0 - abs(sin((q.x*2.3 - q.y*1.1 + wob*1.7)*2.2)), 13.0), 0.05, band(26.0, px));
    \\    base *= 1.0 + 0.15*fvn(q, 1.4, vec2(7.7), px) - 0.30*vein - 0.17*hair;
    \\    base *= 0.95 + 0.12*fvn(q, 11.0, vec2(2.9), px);                         // crazing
    \\    base *= 1.0 - 0.17*smoothstep(0.60, 0.92, fvn(q, 0.35, vec2(19.0), px)); // where the polish is gone
    \\    // BLOCK DRIFT: dressed stone is quarried in pieces and no two blocks match. Frequency low
    \\    // enough that it varies drum to drum down a colonnade rather than within any one drum,
    \\    // which is what stops twelve columns reading as twelve copies of one column.
    \\    base *= 0.94 + 0.12*fvn(q, 0.22, vec2(53.7), px);
    \\    base = weather(base, q, n, px);   // …and the kingdom's own stone has stood out here just as long
    \\  } else if (m == 11){ // FLAME: no surface texture at all — but it GUTTERS.
    \\    // A fire has no SURFACE to weather, and the generic grain the default branch applies was
    \\    // mottling the one thing in the scene that is pure emitted light (flameInto's own comment,
    \\    // "no surface mottle over a glow", asked for this and could not get it — `.plain` IS the
    \\    // grain).
    \\    // What it gets instead is BRIGHTNESS FLICKER, which is the other half of reading as fire:
    \\    // the vertex writhe moves the shape, this makes it surge and dim. Deliberately near-uniform
    \\    // in SPACE and fast in TIME — a fine spatial pattern here would sizzle on a distant torch,
    \\    // and temporal flicker cannot alias spatially at all.
    \\    float fl = sin(uTime*11.0 + q.x*2.1 + q.y*1.7)*0.5
    \\             + sin(uTime*19.0 + q.x*3.3)*0.3
    \\             + sin(uTime*31.0 + q.y*2.6)*0.2;
    \\    base *= 1.0 + 0.10*fl;   // 0.26 on top of an already-hot emissive blew the tongues to yellow
    \\  } else if (m == 9){ // WATER: silt drifting under the surface (the RIPPLES are geometry-
    \\    // free — see waterNormal — this is only what's suspended in the tarn)
    \\    base *= 0.84 + 0.30*fmot(q, 0.7, px);
    \\  } else {            // PLAIN: the old generic grain, now surface-anchored. This is the DEFAULT
    \\    // material — every untagged shape (the skeleton's bones, eyes, glints) lands here, so its
    \\    // 13-cell hard hash was sizzling on more of the world than any other single term.
    \\    float g = fvn(q, 1.1, vec2(0.0), px)*0.45 + fvn(q, 4.3, vec2(0.0), px)*0.35 + fspk(q, 13.0, px)*0.20;
    \\    base *= 0.88 + 0.24*g;
    \\  }
    \\  return base;
    \\}
    \\// ---- WATER SURFACE ---- the tarn is a FLAT mesh; every ripple you see is this normal.
    \\// Two crossed swell trains plus a drifting noise octave, differenced to a slope — cheap,
    \\// and because it keys off WORLD xz the wave field is continuous across the whole lake
    \\// (per-mesh UVs would seam at the shore ring).
    \\// Wavelengths are LONG (~7 m on the primary train): the first pass was ~3 m and the lake
    \\// read as hammered metal from any height. A sheltered tarn has slow swells with a fine
    \\// chop riding them, which is what the third term is for.
    \\float swell(vec2 q, float t){
    \\  return sin(q.x*0.85 + t*0.95)*0.60 + sin(q.y*0.66 - t*0.72)*0.48
    \\       + sin((q.x + q.y)*2.1 + t*1.9)*0.16 + sin((q.x - q.y*1.7)*4.3 - t*2.7)*0.07
    \\       + vnoise(q*0.7 + vec2(t*0.09, -t*0.07))*1.15 + vnoise(q*3.1 - vec2(t*0.21, t*0.16))*0.28;
    \\}
    \\vec3 waterNormal(vec2 q, float t, float px){
    \\  // The finite-difference baseline must be at least a PIXEL wide. Fixed at 0.14, a distant
    \\  // fragment measured the slope over a step far SMALLER than its own footprint, so it sampled
    \\  // ripple detail it had no hope of resolving and the normal thrashed frame to frame — which
    \\  // the razor-tight specular below then turned into sparkle. Widening the step with the
    \\  // footprint makes this a FILTERED slope across the pixel rather than a point slope, so the
    \\  // sheet flattens toward mirror as it recedes (which is what real water does) and the glitter
    \\  // settles into a moving streak instead of a field of blinking dots.
    \\  float E = max(0.14, px);  // slope sample step, in world units
    \\  // STEEPNESS matters more than it looks. At 0.10 the normals barely left vertical, so the
    \\  // fresnel and the sun glint were near-constant across the whole sheet: a flat milky pane
    \\  // with one blown-out white splodge in it. 0.24 breaks both into moving streaks and
    \\  // scatters the glitter into sparkle, which is what actually reads as water.
    \\  const float AMP = 0.24;
    \\  float h0 = swell(q, t);
    \\  return normalize(vec3(-(swell(q + vec2(E, 0.0), t) - h0)/E*AMP, 1.0,
    \\                        -(swell(q + vec2(0.0, E), t) - h0)/E*AMP));
    \\}
    \\// Torch/fire light: quadratic falloff reaching exactly 0 at the radius (so a light can
    \\// never leak out of its room), lambert wrapped hard so one flame fills a chamber.
    \\vec3 pointLights(vec3 pos, vec3 n){
    \\  vec3 sum = vec3(0.0);
    \\  for (int i = 0; i < nLights; i++){
    \\    vec3 d = lightPos[i] - pos;
    \\    // Reject on the SQUARED distance so out-of-range lights cost no sqrt. Most fragments are
    \\    // outside most of the 16 uploaded radii, so this is the common path through the loop.
    \\    float r = lightRad[i];
    \\    float d2 = dot(d, d);
    \\    if (d2 >= r*r) continue;
    \\    float dist = sqrt(d2);
    \\    float att = 1.0 - dist/r;
    \\    att *= att;
    \\    // Wrapped, but not so hard that every surface in the room gets the same value — the
    \\    // wrap is there so a torch FILLS a chamber, not so it erases form.
    \\    float ndl = clamp((dot(n, d/max(dist, 1e-4)) + 0.22)/1.22, 0.0, 1.0);
    \\    sum += lightCol[i]*att*ndl;
    \\  }
    \\  return sum;
    \\}
    \\// Fraction of this fragment in sun shadow (0 lit, 1 shadowed): 3x3 PCF. Outside the
    \\// ortho box counts as lit.
    \\float shadowFrac(vec3 pos, float ndl){
    \\  vec4 p = lightVP*vec4(pos, 1.0);
    \\  p.xyz /= p.w;
    \\  p.xyz = p.xyz*0.5 + 0.5;
    \\  if (p.z > 1.0 || p.z < 0.0 || p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) return 0.0;
    \\  // Bias is in NDC, so it costs bias*(far-near) WORLD units — the slab widened with the
    \\  // box, so these came DOWN to keep the real offset near 0.22 m. Too much and small
    \\  // casters peter-pan off their own feet.
    \\  float bias = max(0.0013*(1.0 - ndl), 0.00032);
    \\  float texel = 1.0/float(shadowMapResolution);
    \\  float sc = 0.0;
    \\  for (int x = -1; x <= 1; x++)
    \\    for (int y = -1; y <= 1; y++)
    \\      if (p.z - bias > texture(shadowMap, p.xy + vec2(x, y)*texel).r) sc += 1.0;
    \\  return sc/9.0;
    \\}
    \\void main(){
    \\  // Hoisted per-fragment invariants. These were each recomputed several times below, and this
    \\  // is a FILL-BOUND shader (a full-screen terrain pass at 1280x800 is ~1M fragments), so the
    \\  // duplicates were real work: `sunDir` arrives ALREADY normalized from gfx.SUN_DIR, yet
    \\  // normalize(sunDir) appeared five times; `length(camPos - fragPosition)` was computed once
    \\  // for V and again for the haze distance; and clamp(dot(n,V)) was recomputed by the rim term
    \\  // and by all three fresnels. Same output, one evaluation each.
    \\  vec3 L = normalize(sunDir);
    \\  vec3 base = fragColor.rgb;
    \\  vec3 n = normalize(fragNormal);
    \\  vec2 p = fragPosition.xz;
    \\  vec3 toCam = camPos - fragPosition;
    \\  float dist = length(toCam);
    \\  vec3 V = toCam/max(dist, 1e-5);
    \\  float nv = clamp(dot(n, V), 0.0, 1.0);
    \\  // Detail-LOD footprints, both taken HERE: `fwidth` needs uniform control flow, and `mi == 9`
    \\  // (water) is NOT uniform — it rides a vertex attribute. `pxP` measures the world-xz patterns
    \\  // (terrain albedo, water silt, the ripple normal's difference step); `pxQ` the surface-anchored
    \\  // material UVs (every prop pattern, and the specular lobe widths further down). Terrain pays
    \\  // for a `pxQ` it never reads — one quad-difference, and the alternative is two different LOD
    \\  // proxies for the albedo and the highlight of the same surface.
    \\  float pxP = uvFoot(p);
    \\  float pxQ = uvFoot(fragUV);
    \\  int mi = -1;
    \\  if (groundMode==1){
    \\    base *= terrainAlbedo(p, pxP);
    \\  } else {
    \\    mi = int(fragMatF + 0.5);
    \\    // WATER is textured in WORLD xz, not surface UVs: the tarn is a radial fan of quads
    \\    // and the Builder decorrelates UVs per shape, so surface-anchored silt would show the
    \\    // lake's triangulation as a patchwork of unrelated blotches.
    \\    // The footprint must be taken in the SAME space as the coordinate, or the LOD is measured
    \\    // against the wrong scale — water textures in world xz, everything else in surface UVs.
    \\    base = matAlbedo(mi, (mi == 9) ? p : fragUV, base, n, (mi == 9) ? pxP : pxQ);
    \\    // …and its ripples live in the NORMAL, so they must land before any lighting term.
    \\    if (mi == 9) { n = waterNormal(p, uTime, pxP); nv = clamp(dot(n, V), 0.0, 1.0); } // ripples move the normal
    \\  }
    \\  float ndl = dot(n, L);
    \\  float diff = clamp((ndl + 0.12)/1.12, 0.0, 1.0); // tighter wrap = crisper terminator (more contrast)
    \\  float sh = shadowFrac(fragPosition, ndl);
    \\  // Golden-hour split: warm amber key vs cool slate sky ambient + warm dirt bounce.
    \\  // CONTRAST lives here: a low ambient floor + shadows eating deep vs a hot key.
    \\  vec3 hemi = mix(vec3(0.090, 0.076, 0.054), vec3(0.168, 0.188, 0.244), n.y*0.5 + 0.5); // darker floor — darks go DARKER
    \\  vec3 lit = base*(hemi*(1.0 - 0.62*sh) + vec3(1.32, 1.10, 0.80)*diff*1.72*(1.0 - sh) // hotter warm sun key
    \\                   + pointLights(fragPosition, n));                                   // + torch/firelight
    \\  if (groundMode == 0){
    \\    // Cool sky rim on props/hero — lifts silhouettes off the dark ground (cheap
    \\    // atmospheric backlight; NOT on terrain, where grazing angles would sheen it all).
    \\    // NOT on water either: a rim on a flat sheet frosts the whole lake.
    \\    float rim = (mi == 9) ? 0.0 : pow(1.0 - nv, 2.6);
    \\    lit += rim*vec3(0.082, 0.096, 0.128)*(0.6 + 0.4*n.y)*(1.0 - 0.5*sh);
    \\    // SHINY METAL (STEEL, id 4): a hot, tight Blinn-Phong sun glint + a cool sky sheen on
    \\    // grazing angles, so blades/armour/steel props read as polished metal (not matte). The
    \\    // spec is unclamped so the hotspot blows to white — the "super shiny" catch of light.
    \\    if (mi == 4){
    \\      vec3 H = normalize(L + V);
    \\      float nh = max(dot(n, H), 0.0);
    \\      // The tight 96-exponent lobe is what made distant blades and helms strobe; the broad
    \\      // 22 one already spans several pixels, so it is left alone.
    \\      float w = lobe(pxQ, 8.0);
    \\      float sp = pow(nh, 96.0*w)*3.6*w + pow(nh, 22.0)*0.7;  // a BLINDING tight hotspot + a broader sheen
    \\      lit += sp*vec3(1.5, 1.3, 1.0)*(1.0 - sh);              // hot near-white glint — steel POPS
    \\      float fres = pow(1.0 - nv, 4.0);
    \\      lit += fres*vec3(0.34, 0.40, 0.52)*(1.0 - 0.4*sh);     // bright cool reflective sky sheen at the edges
    \\    }
    \\    // POLISHED STONE. Marble was cut and burnished; the rubble masonry beside it never
    \\    // was, and what sells that difference is not colour, it is a HIGHLIGHT — a dressed
    \\    // capital catching the low sun next to a matte wall is the whole read. ONE gloss dial
    \\    // per material drives one Blinn lobe, so "shinier than the thing beside it" stays a
    \\    // number instead of another shader path. Kept LOW — a gloss that reads as "shiny" on
    \\    // a swatch is a gloss that lays a broad wash over every sunward face, and a ruin washed
    \\    // pale is the exact failure the dark-albedo rule exists to stop. This wants to be a
    \\    // tight glance off a burnished edge, not a coat of varnish.
    \\    float gloss = (mi == 10) ? 0.55 : (mi == 1) ? 0.09 : 0.0;
    \\    if (gloss > 0.001){
    \\      vec3 Hg = normalize(L + V);
    \\      float nhg = max(dot(n, Hg), 0.0);
    \\      float wg = lobe(pxQ, 8.0); // a burnished capital across the plaza was blinking, same cause
    \\      lit += (pow(nhg, 78.0*wg)*0.72*wg + pow(nhg, 20.0)*0.06)*gloss*vec3(1.18, 1.05, 0.86)*(1.0 - sh);
    \\      lit += pow(1.0 - nv, 6.0)*gloss*vec3(0.07, 0.09, 0.13);
    \\    }
    \\    // WATER (id 9): a long tight sun streak shattered across the ripples + a broad sky
    \\    // reflection at grazing angles. This — not the albedo — is what makes it read WET.
    \\    if (mi == 9){
    \\      vec3 H = normalize(L + V);
    \\      float nh = max(dot(n, H), 0.0);
    \\      // A TIGHT glitter path only. The broad term used to sit at 0.30, which is a sheen
    \\      // across the whole sheet from any angle — that plus a pale albedo is what made the
    \\      // tarn read as milk. Water's read comes from a hot narrow highlight on a dark body.
    \\      // 320 is the sharpest lobe in the renderer and the tarn is the widest thing wearing one,
    \\      // so this is where sparkle was worst. Widened HARDER than steel (k 10) because the ripple
    \\      // normal it rides is itself high-frequency.
    \\      float ww = lobe(pxP, 10.0);
    \\      lit += (pow(nh, 320.0*ww)*2.6*ww + pow(nh, 48.0)*0.07)*vec3(1.5, 1.26, 0.92)*(1.0 - sh);
    \\      float fres = pow(1.0 - nv, 4.0);
    \\      lit += fres*vec3(0.058, 0.072, 0.104);                 // the slate sky, only at grazing angles
    \\    }
    \\  }
    \\  float emis = 1.0 - fragColor.a;
    \\  lit = mix(lit, base*1.35, emis);
    \\  // Combat flash: the struck actor pops blood-red for a beat (per-draw uniform).
    \\  lit = mix(lit, vec3(0.55, 0.07, 0.05), hitFlash);
    \\  float haze = 1.0 - exp(-hazeDensity*dist);
    \\  // Haze banks golden looking into the sun's quarter (matches the sky shader's bank).
    \\  float sunAmt = pow(clamp(dot(-V, L), 0.0, 1.0), 3.0);
    \\  vec3 hazeC = hazeColor + vec3(0.34, 0.19, 0.05)*sunAmt;
    \\  lit = mix(lit, hazeC, clamp(haze, 0.0, 1.0));
    \\  // A TOUCH more saturation overall — push colours out from their luma (kept subtle).
    \\  float luma = dot(lit, vec3(0.299, 0.587, 0.114));
    \\  lit = max(mix(vec3(luma), lit, 1.15), 0.0);
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

    // Authored PER-PIXEL in normalized screen space (not genImageGradientRadial, whose radius
    // is the short dimension — on 16:9 that saturates to full dark and reads as a contracted
    // ring). Falloff measured to the CORNERS and stretched to screen, so it tracks the real
    // aspect; tune with the three consts below.
    pub fn init() Vignette {
        const W = 256;
        const H = 256;
        const START = 0.62; // radius (0=centre, 1=edge-midpoint, ~1.41=corner) where the fade BEGINS — big clean centre
        const ENDR = 1.34; // …and reaches full strength by here (the corners)
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

// SINGLE SOURCE OF TRUTH — one row per filter in RF_* index order; the menu labels,
// uniform names, and owner-tuned launch defaults are DERIVED at comptime so they can't
// drift out of positional lockstep. Defaults = the launch look (owner-tuned): a light retro
// grunge; "Reset to Default" restores it, "All Off" gives the clean render.
const RetroFilter = struct { name: [:0]const u8, uniform: [:0]const u8, default: f32 };
const RETRO_FILTERS = [RETRO_COUNT]RetroFilter{
    // Blocks snap to whole pixels (see retroFS), so what matters is where the rounding lands:
    // 0.03 rounds to 1 px and is a no-op, 0.05 is the first intensity that buys a real, steady
    // 2x2 block. That 2x2 is the owner's launch look.
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

// The RF_* index constants must still line up with RETRO_FILTERS' rows; anchor a few at
// comptime so moving a filter without updating its RF_* index fails the build.
comptime {
    std.debug.assert(std.mem.eql(u8, RETRO_UNIFORMS[RF_PIXELATE], "fPixelate"));
    std.debug.assert(std.mem.eql(u8, RETRO_UNIFORMS[RF_GRAIN], "fGrain"));
    std.debug.assert(std.mem.eql(u8, RETRO_NAMES[RF_CGA], "CGA"));
}

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
    \\// EVERY read of the captured scene goes through this. Snapping the UV to a block centre
    \\// POINT-samples it — the RT is GL_NEAREST — so a 2x2 block kept one pixel and threw three
    \\// away, and a reed or a distant column edge landing in a discarded pixel on some frames and
    \\// a kept one on others is what twinkled. Pixelate sets pixQ to a QUARTER of a block, which
    \\// turns this into a 4-sample BOX FILTER over that block: the detail is averaged in rather
    \\// than gambled on, at every distance and with no boundary to see. pixQ zero (pixelate off,
    \\// or a block rounded to 1 px) collapses it back to the single tap it always was.
    \\//
    \\// PIX_BOX is how much of that average to take, and it is a STRAIGHT TRADE, not a free win:
    \\// point-sampling is exactly what makes a block edge hard, so filtering the twinkle out
    \\// softens the crunch by the same stroke — the twinkle IS a hard edge crossing a pixel
    \\// boundary. 0 = the old hard blocks and the old flicker; 1 = a true 2x2 downsample, calm and
    \\// noticeably soft; between = flicker amplitude scaled down by that much for that much less
    \\// bite. One dial, so it can be judged by playing rather than argued about.
    \\const float PIX_BOX = 0.5;
    \\vec2 pixQ = vec2(0.0);
    \\float pixStep = 0.0; // one block's WIDTH in UV, zero when pixelate is off (chroma snaps to it)
    \\vec4 sceneTap(vec2 p){
    \\  vec4 pt = texture(texture0, p);
    \\  if (pixQ.x <= 0.0) return pt;
    \\  vec4 box = 0.25*(texture(texture0, p - pixQ)
    \\                 + texture(texture0, p + vec2( pixQ.x, -pixQ.y))
    \\                 + texture(texture0, p + vec2(-pixQ.x,  pixQ.y))
    \\                 + texture(texture0, p + pixQ));
    \\  return mix(pt, box, PIX_BOX);
    \\}
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
    \\  // Pixelate: quantize the UV onto a coarse grid (1px = off ... 14px = full chunk).
    \\  // THE BLOCK MUST BE A WHOLE NUMBER OF PIXELS. mix(1,14,f) yields fractional sizes, and at the
    \\  // old default 0.03 that was 1.39 — a 1280-wide frame resampled onto a 921-cell grid. A
    \\  // non-integer ratio makes some cells cover two source pixels and some one, and WHICH cells do
    \\  // changes as the scene moves: that beat is a shimmer, not a crunch, and it landed on exactly
    \\  // the fine distant detail everything else here is trying to calm down. Snapped, a block maps to
    \\  // exactly n x n pixels and the grid is rock steady. n == 1 is then a true no-op.
    \\  if (fPixelate > 0.0){
    \\    float blk = max(floor(mix(1.0, 14.0, fPixelate) + 0.5), 1.0);
    \\    vec2 grid = max(resolution/blk, vec2(1.0));
    \\    uv = (floor(uv*grid) + 0.5)/grid;
    \\    // …and arm the box filter (see sceneTap). A quarter-block from the centre puts the four
    \\    // taps on the quadrant centres, which at the 2 px default is EXACTLY the block's four
    \\    // pixels. Above 2 px it is a 4x supersample of the block rather than a full box — the
    \\    // taps would have to grow with blk^2 for that, and 14 px would cost 196 of them.
    \\    if (blk > 1.0) pixQ = blk/(4.0*resolution);
    \\    pixStep = blk/resolution.x;
    \\  }
    \\  // Chroma fringe: fetch R and B slightly off-axis (worn composite cable).
    \\  vec4 baseTex = sceneTap(uv);
    \\  vec3 col;
    \\  if (fChroma > 0.0){
    \\    // THE OFFSET SNAPS TO WHOLE BLOCKS. Unsnapped it is half a pixel at the default 9%, which
    \\    // GL_NEAREST used to round straight back onto the base texel — the fringe was a near
    \\    // no-op with pixelate on, and that is the look this was tuned to. Filtered, that same
    \\    // half pixel instead straddles the block boundary and R/B smear a pixel apart: a colour
    \\    // blur, not the flicker fix, and most of what read as "blurry". Snapped, R and B come
    \\    // from the same averaged blocks G does, so the channels can't disagree about where a
    \\    // block edge is — and a fringe on a pixelated image belongs in block units anyway.
    \\    float off = fChroma*0.0045;
    \\    vec2 o = vec2(off, 0.0);
    \\    if (pixStep > 0.0) o.x = floor(off/pixStep + 0.5)*pixStep;
    \\    col.r = sceneTap(uv + o).r;
    \\    col.g = baseTex.g;
    \\    col.b = sceneTap(uv - o).b;
    \\  } else { col = baseTex.rgb; }
    \\  // Ink edges: Sobel on luminance, applied as a darkening AFTER the color crush. Deliberately
    \\  // NOT routed through sceneTap: eight taps become thirty-two, and its own 1.5 px kernel is
    \\  // already a filter. Off by default, so it is not what flickers in the launch look.
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
    \\  // Film grain: animated per-pixel flicker, HELD on a 24 Hz beat. Real emulsion grain changes
    \\  // once per photographed frame; this re-rolled every rendered frame, so on a 144 Hz panel it
    \\  // ran six times the intended rate and read as electronic sparkle rather than film. Quantising
    \\  // the seed also decouples the look from the player's refresh rate, which it had no business
    \\  // depending on.
    \\  if (fGrain > 0.0){
    \\    float gt = floor(time*24.0);
    \\    float gnoise = hash21(gl_FragCoord.xy + vec2(mod(gt, 97.0)*137.0, mod(gt, 89.0)*291.0));
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

    // Rebuild the capture RT + resolution uniform for a new window size — the filtered path
    // renders into this RT and blits at its own size, so it must track the backbuffer or it
    // fills only a corner. w/h ≤ 0 (a minimized window) is ignored.
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
// A blank SOIL_N x SOIL_N single-byte texture, updated in place by setSoil. NEAREST filtering
// is load-bearing: the bytes are enum ids, and a bilinear fetch between 2 and 4 returns 3 — a
// material nobody painted, showing as a seam of the wrong ground along every boundary.
fn loadSoilTexture() rl.Texture2D {
    const n: usize = @intCast(SOIL_N);
    const blank = std.heap.c_allocator.alloc(u8, n * n) catch @panic("soil texture");
    defer std.heap.c_allocator.free(blank);
    @memset(blank, 0);
    const img = rl.Image{
        .data = blank.ptr,
        .width = SOIL_N,
        .height = SOIL_N,
        .mipmaps = 1,
        .format = .uncompressed_grayscale,
    };
    const tex = rl.loadTextureFromImage(img) catch @panic("soil texture");
    rl.setTextureFilter(tex, .point);
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
    loc_lightPos: i32,
    loc_lightCol: i32,
    loc_lightRad: i32,
    loc_nLights: i32,
    soilTex: rl.Texture2D,
    loc_soilOn: i32,
    loc_soilHalf: i32,
    loc_soilCell: i32,
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
        var slotSoil = SLOT_SOIL;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "soilMap"), &slotSoil, .int);
        var haze = HAZE;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "hazeColor"), &haze, .vec3);
        var density: f32 = HAZE_DENSITY;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "hazeDensity"), &density, .float);
        var windOff: f32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "windAmt"), &windOff, .float);
        var flashOff: f32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "hitFlash"), &flashOff, .float);
        var noLights: i32 = 0;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "nLights"), &noLights, .int);
        return .{
            .shader = shader,
            .depthShader = depthShader,
            .shadowMap = loadShadowmap(SHADOWMAP_RES),
            .soilTex = loadSoilTexture(),
            .loc_soilOn = rl.getShaderLocation(shader, "soilOn"),
            .loc_soilHalf = rl.getShaderLocation(shader, "soilHalf"),
            .loc_soilCell = rl.getShaderLocation(shader, "soilCell"),
            .lightVP = rl.math.matrixIdentity(),
            .loc_ground = rl.getShaderLocation(shader, "groundMode"),
            .loc_lightVP = rl.getShaderLocation(shader, "lightVP"),
            .loc_camPos = rl.getShaderLocation(shader, "camPos"),
            .loc_windAmt = rl.getShaderLocation(shader, "windAmt"),
            .loc_time = rl.getShaderLocation(shader, "uTime"),
            .loc_flash = rl.getShaderLocation(shader, "hitFlash"),
            .loc_lightPos = rl.getShaderLocation(shader, "lightPos"),
            .loc_lightCol = rl.getShaderLocation(shader, "lightCol"),
            .loc_lightRad = rl.getShaderLocation(shader, "lightRad"),
            .loc_nLights = rl.getShaderLocation(shader, "nLights"),
        };
    }

    // Sun depth pass: call, draw casters (materials swapped to depthShader — drawMesh uses
    // the MATERIAL's shader, beginShaderMode won't reach it), then endShadowPass; must run
    // BEFORE beginDrawing. The ortho box tracks `focus`, snapped to shadow texels so walking
    // doesn't make shadow edges crawl.
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
        self.bindSoil();
        rl.setShaderValueMatrix(self.shader, self.loc_lightVP, self.lightVP);
        var cp = camPos;
        rl.setShaderValue(self.shader, self.loc_camPos, &cp, .vec3);
        var t: f32 = @floatCast(rl.getTime());
        rl.setShaderValue(self.shader, self.loc_time, &t, .float);
    }

    // Upload this frame's point lights (torches/fires). Caller passes the ones NEAREST the
    // camera — env.uploadLights does the picking — and anything past MAX_LIGHTS is dropped,
    // which is invisible in practice because the dropped ones are the furthest away.
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

    /// Push the painted soil grid: SOIL_N x SOIL_N material ids, one byte each, 0 = unpainted.
    /// `half` is the world half-extent the grid spans. Re-uploads the WHOLE texture — SOIL_N² bytes,
    /// ~12 KB at 112 a side — which is still nothing, so a brush stroke can call this every frame it
    /// moves. (It said 4 KB, from when the grid was 64 a side.)
    ///
    /// NEAREST filtering on purpose: the ids are enum values, and a bilinear fetch between 2
    /// and 4 returns 3 — a material nobody painted, appearing as a seam of the wrong ground
    /// along every boundary. The shader jitters its sample position instead.
    pub fn setSoil(self: *Scene, ids: []const u8, half: f32) void {
        const n: usize = @intCast(SOIL_N);
        std.debug.assert(ids.len == n * n);
        rl.updateTexture(self.soilTex, ids.ptr);
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

    // The soil texture rides its own slot alongside the shadow map, bound once per frame.
    fn bindSoil(self: *Scene) void {
        rl.gl.rlActiveTextureSlot(SLOT_SOIL);
        rl.gl.rlEnableTexture(self.soilTex.id);
        rl.gl.rlActiveTextureSlot(0);
    }

    // Flora opt into vertex-shader sway; everything else (terrain, props, hero) draws rigid.
    // Toggle ON only around the flora draw, OFF immediately after.
    pub fn setWind(self: *Scene, on: bool) void {
        var a: f32 = if (on) 1.0 else 0.0;
        rl.setShaderValue(self.shader, self.loc_windAmt, &a, .float);
    }

    // The blood-red combat flash on whatever draws NEXT (0 = none). Set per actor around
    // its draw, reset to 0 after — the struck one pops, the rest of the scene doesn't.
    pub fn setFlash(self: *Scene, amt: f32) void {
        var a = mathx.clampF(amt, 0, 1);
        rl.setShaderValue(self.shader, self.loc_flash, &a, .float);
    }
};

// Per-fragment surface material for the scene shader's texturing pass (see matAlbedo).
// Rides vertexTexCoord2.x; .plain is the generic grain every untagged shape gets. The ORDER is
// the shader's `m ==` ladder — append only, never reorder.
pub const Mat = enum(u8) { plain, stone, wood, cloth, steel, leather, skin, hide, plant, water, marble, flame };
comptime {
    // The shader hard-codes 9 for water in three places (albedo, ripple normal, spec/fresnel),
    // 10 for marble in two (albedo, gloss) and 11 for flame in two (the VERTEX shader's writhe and
    // the albedo's leave-it-alone branch); fail the build rather than silently texture the tarn as
    // marble if the enum ever shifts. APPEND-ONLY past this point.
    std.debug.assert(@intFromEnum(Mat.water) == 9);
    std.debug.assert(@intFromEnum(Mat.marble) == 10);
    std.debug.assert(@intFromEnum(Mat.flame) == 11);
}

// Procedural-mesh Builder (from zig-rts, plus toMesh for the FK-rigged hero which needs bare
// Meshes, not Models). Every shape gets SURFACE-ANCHORED UVs in ~world units + the current
// material id in texcoords2 so patterns stay glued to animated bones; setMat() switches
// material and a per-shape UV offset decorrelates identical shapes so nothing tiles in sync.
pub const Builder = struct {
    pos: std.ArrayList(f32),
    nrm: std.ArrayList(f32),
    uv: std.ArrayList(f32),
    uv2: std.ArrayList(f32),
    col: std.ArrayList(u8),
    matf: f32 = 0, // current Mat id, written per vertex into texcoords2.x
    /// The local Y a shape's VERTEX ANIMATION measures from, written per vertex into texcoords2.y.
    /// Only fire uses it so far: a flame is authored at the top of its torch, so the vertex shader
    /// cannot tell "height above the fuel" from `p.y` alone — and without that distinction the
    /// coals writhe as hard as the tongues. `uv2.y` was a hardcoded 0, so this channel was free.
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

    /// Datum for the vertex animation of every shape added after this call — see `animY`. STICKY
    /// like `setMat`, so a shape that animates must set it back to 0 when it is done.
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

    // Planar-mapped quad: UVs are in-plane world-unit coordinates (u along a->b, v across),
    // shifted by the shape offset — any face textures itself with zero caller effort.
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

    // Axis-aligned box centered at `c` with full `size`. Faces wind CCW seen from OUTSIDE —
    // raylib culls back faces, so inward winding renders boxes hollow.
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
    // addCube. Winding matches addCube (CCW from outside); a LEFT-handed axis triple is
    // normalized first so callers can pass axes in any order without turning the box inside-out.
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

    // Tapered cylinder (no caps) a(radius ra) -> b(radius rb); rb≈0 for spikes. UVs: u = arc
    // length around the barrel (continuous across facets), v = distance along the axis, so
    // grain runs ALONG the limb and banding wraps it.
    pub fn addCylinder(self: *Builder, a: rl.Vector3, b: rl.Vector3, ra: f32, rb: f32, sides: i32, col: rl.Color) void {
        const f = axisFrame(a, b);
        const o = self.shapeOff();
        const rmid = @max(0.5 * (ra + rb), 0.02); // arc-length radius (floor keeps spike UVs sane)
        self.ringBand(a, b, f.u, f.w, ra, rb, sides, col, o, rmid, o.y, o.y + f.len);
    }

    // ONE band of a revolved surface: the quad ring between circle (a, ra) and circle (b, rb) in
    // the (u, w) frame, with the UV offset / arc radius / v-range supplied by the caller — so a
    // multi-band surface (a capsule's cap, a blob) keeps ONE continuous texture instead of a fresh
    // decorrelated patch per band (which reads as rings of noise on a big smooth mass).
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
    // The organic default for any limb/haft — a bare addCylinder leaves open flat-looking ends
    // that read as cut pipe, and stacking two of them shows the seam. Use this wherever flesh is.
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

    // A hemispherical cap of radius r on `c`, bulging along `dir`. `vAt`/`vSign` continue the
    // barrel's v coordinate over the dome so the grain doesn't restart at the seam.
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

    // A rounded ELLIPSOID mass centred on `c` with half-extents `r` — the anti-blockiness
    // primitive. Anything organic (a cranium, a pec, a gut, a wart, a knuckle, a club's stone
    // head) is one of these; addCube is for stone, iron and cloth, not for FLESH.
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
                // Vertex order matches addCylinder's proven CCW-from-outside winding (lower ring
                // first, sweeping +angle, then the upper ring back).
                const p0 = onBlob(c, r, t0, a0);
                const p1 = onBlob(c, r, t0, a1);
                const p2 = onBlob(c, r, t1, a1);
                const p3 = onBlob(c, r, t1, a0);
                const g = v3((0.25 * (p0.x + p1.x + p2.x + p3.x) - c.x) * inv.x * inv.x, (0.25 * (p0.y + p1.y + p2.y + p3.y) - c.y) * inv.y * inv.y, (0.25 * (p0.z + p1.z + p2.z + p3.z) - c.z) * inv.z * inv.z);
                self.quadUV(p0, p1, p2, p3, norm3(g), col, .{ .x = a0 * rmid + o.x, .y = o.y + t0 * r.y }, .{ .x = a1 * rmid + o.x, .y = o.y + t0 * r.y }, .{ .x = a1 * rmid + o.x, .y = o.y + t1 * r.y }, .{ .x = a0 * rmid + o.x, .y = o.y + t1 * r.y });
            }
        }
    }

    // Upload to the GPU as a bare Mesh (CPU arrays stay attached; the mesh lives the whole
    // program). The FK hero draws these directly with per-bone matrices via drawMesh.
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
// Pulled out of addCylinder so the capsule/dome/blob builders all revolve about the SAME frame
// (the winding and the UV grain then match across primitives).
const AxisFrame = struct { axis: rl.Vector3, u: rl.Vector3, w: rl.Vector3, len: f32 };
fn axisFrame(a: rl.Vector3, b: rl.Vector3) AxisFrame {
    const d = v3(b.x - a.x, b.y - a.y, b.z - a.z);
    const axis = norm3(d);
    const seed = if (@abs(axis.y) < 0.99) v3(0, 1, 0) else v3(1, 0, 0);
    const u = norm3(cross(axis, seed));
    return .{ .axis = axis, .u = u, .w = norm3(cross(axis, u)), .len = @sqrt(d.x * d.x + d.y * d.y + d.z * d.z) };
}
// A point on the ellipsoid (c, r): `t` = polar angle (0 = bottom pole), `ang` = angle around.
// Signs match dirOn's (u, w) = (0,0,-1), (-1,0,0) frame for a +Y axis, so windings agree.
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
