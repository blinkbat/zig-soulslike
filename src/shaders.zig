// ── THE SHADERS ── every line of GLSL in the game, and nothing else. The Zig that compiles these,
// feeds them uniforms and decides when to bind them is gfx.zig; this file is the source text.
//
// Split out because the two are read for different reasons: nothing you need in order to change the
// mesh Builder or the Scene's uniform plumbing is in here, and nothing you need in order to change
// the lighting is over there. What DOES cross the line is a short contract, and it is worth knowing
// before you touch either side:
//
//   UNIFORM NAMES are the interface. `Scene.init` looks each one up by string; a rename here that is
//   not made there silently yields location −1 and the uniform stops arriving (raylib does not warn).
//   MATERIAL IDS are numbers on both sides. `sceneFS` hard-codes 9 for water in three places and 11
//   for flame; `gfx.Mat`'s comptime block asserts those enum values so a reorder fails the build.
//   TEXTURE SLOTS: the shadow map, the soil grid and the water field ride SLOT_SHADOW/SOIL/WATER,
//   bound once a frame by `Scene.bind`, because raylib's default material only ever binds slot 0.
//   AUTHOR COLOURS NEAR-BLACK. The key is hot (*1.72) and the final gamma lift is 1/2.2, so any
//   mid-dark albedo comes back pale — that rule is the reason every palette in props is so dark.
pub const depthVS =
    \\#version 330
    \\in vec3 vertexPosition;
    \\uniform mat4 mvp;
    \\void main() { gl_Position = mvp*vec4(vertexPosition, 1.0); }
;
pub const depthFS =
    \\#version 330
    \\out vec4 c;
    \\void main() { c = vec4(1.0); }
;

pub const sceneVS =
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
    \\out float fragLife;   // smoke only: 0 = the puff has just been born, 1 = it is gone
    \\void main() {
    \\    vec3 p = vertexPosition;
    \\    fragLife = 0.0;
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
    \\    // ---- SMOKE RISES ---- and this is where a static mesh becomes a particle system. Each
    \\    // `.smoke` shape is ONE PUFF authored down at the fire (see gfx.smokeAnim for the packing);
    \\    // every cycle the shader grows it, lifts it, leans it downwind and hands the fragment stage a
    \\    // life value to fade it out on. Nothing models the column — the column is a dozen puffs
    \\    // caught at different points of the same loop, which is why they never march in step.
    \\    //
    \\    // TESTED BEFORE THE FLAME BRANCH and with its own range, because the flame's test is a bare
    \\    // `> 10.5` and smoke is 12: left as it was, every puff would have been fed through the
    \\    // tongue writhe as well.
    \\    if (vertexTexCoord2.x > 11.5) {
    \\        vec3 baseW = vec3(matModel*vec4(0.0, 0.0, 0.0, 1.0));
    \\        float oy   = floor(vertexTexCoord2.y);   // the source height…
    \\        float seed = fract(vertexTexCoord2.y);   // …and this puff's own place in the cycle
    \\        // No two FIRES smoke in lockstep either — same argument the flame's `seed` makes.
    \\        float life = fract(uTime*0.20 + seed + baseW.x*0.031 + baseW.z*0.027);
    \\        fragLife = life;
    \\        // BILLOW: the puff swells about its own source as it climbs. A plume that rises without
    \\        // growing is a smoke signal going up a pipe — the widening IS the thing that reads as
    \\        // air getting into it.
    \\        vec3 c = vec3(0.0, oy, 0.0);
    \\        p = c + (p - c)*(0.42 + 2.30*life);
    \\        // RISE, and LEAN once it has slowed: the lateral term is life-squared because smoke goes
    \\        // up first and sideways later — it is climbing fastest while it is still hottest.
    \\        p.y += life*3.30;
    \\        float sway = sin(uTime*0.63 + seed*23.0)*0.34*life;
    \\        p.x += life*life*1.45 + sway;
    \\        p.z += life*life*0.55 - sway*0.4;
    \\    } else if (vertexTexCoord2.x > 10.5) {
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
pub const sceneFS =
    \\#version 330
    \\in vec3 fragPosition;
    \\in vec4 fragColor;
    \\in vec3 fragNormal;
    \\in vec2 fragUV;
    \\in float fragMatF;
    \\in float fragLife;        // smoke only — see the vertex shader's rise block
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
    \\// HOW SOLID A FLAME IS (owner's call: all flames somewhat transparent). The one material in the
    \\// scene that is emitted light rather than a lit surface, so what is behind it should come through
    \\// it — and the COOLER the tongue the more of it does, because a tip is the thin edge of the fire
    \\// where a core is deep enough to hide what it stands in front of.
    \\const float FLAME_A_CORE = 0.86;
    \\const float FLAME_A_TIP = 0.42;
    \\const float SMOKE_A = 0.26;   // the ceiling on a puff — see the fade at the bottom of main()
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
    \\// ---- COVERAGE ---- how strongly the painted material holds its cell, authored per cell by the
    \\// brush (wf.Map.soilCov). This is the whole blending system: an edge is not a special case, it is
    \\// simply where the author left the number low.
    \\uniform sampler2D soilCovMap;
    \\// DOES THIS MATERIAL CUT OR BLEND? Pinned to wf.Soil by a comptime assert on the Zig side, which
    \\// is what stops a reordered enum handing the crisp edge to whichever material inherits the number.
    \\bool soilHard(int id){ return id==3; }   // stone: masons stop where they stopped
    \\float soilCovAt(vec2 w, bool hard){
    \\  vec2 uv = w/(2.0*soilHalf) + 0.5;
    \\  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
    \\  // A HARD MATERIAL SNAPS THE UV TO THE TEXEL CENTRE — point sampling out of the same bilinear
    \\  // texture, which is the trick that lets one texture serve both policies. Sampled normally the
    \\  // coverage ramps over a whole 5 m cell, and there is no such thing as a flagstone floor with a
    \\  // five-metre fade on it. Snapped, the transition is exactly one cell wide, and the jitter the
    \\  // caller already applied to `w` is what keeps that from reading as a grid.
    \\  // It also leaves the authored LEVEL untouched, so hard-edged does not mean always-opaque.
    \\  if (hard){ float n = 2.0*soilHalf/soilCell; uv = (floor(uv*n) + 0.5)/n; }
    \\  return texture(soilCovMap, uv).r;
    \\}
    \\// ---- PAINTED WATER ---- one SIGNED field, bilinear, and everything about the coast comes out
    \\// of it: 0.5 is the waterline, above it depth, below it the walk back to dry land. The mask the
    \\// author paints is only the outline (see wf.Map.water); this is what turns an outline into a
    \\// shore that fades, shallows that pale, and sand that is wet where the water has been.
    \\uniform sampler2D waterMap;
    \\uniform float waterHalf;   // world half-extent the field spans
    \\uniform int   waterOn;     // 0 = nothing painted; every read below is skipped
    \\uniform int   waterSheet;  // 1 while the PAINTED sheet draws — authored water props keep their own colours
    \\uniform vec3  waterTone[3]; // shallow / mid / deep, straight off the prop palette (env.drawWater)
    \\float waterField(vec2 w){
    \\  vec2 uv = w/(2.0*waterHalf) + 0.5;
    \\  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
    \\  return texture(waterMap, uv).r;
    \\}
    \\// WET SAND. The band just OUTSIDE the waterline, darkened and saturated the way soaked ground is.
    \\// Done in the terrain's albedo rather than as another sheet, because it IS the ground — a
    \\// separate mud mesh is what the old hand-placed lakes needed and what gave them their hard rim.
    \\vec3 wetShore(vec3 c, vec2 p){
    \\  if (waterOn == 0) return c;
    \\  float f = waterField(p);
    \\  if (f <= 0.002) return c;                       // dry land, well away from any water
    \\  float wet = clamp(f/0.5, 0.0, 1.0);             // 0 at the ramp's edge, 1 at the waterline
    \\  wet = wet*wet;                                  // the last metre or so does most of the work
    \\  return mix(c, c*0.42 + vec3(0.020, 0.019, 0.014), wet*0.85);
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
    \\  // THE TWO COVERAGES MULTIPLY, and they answer different questions. The ring above is STRUCTURAL
    \\  // — how much of the neighbourhood is this same material — and it exists to stop a cell boundary
    \\  // reading as a cliff. The authored one is the AUTHOR's, and it is what a low number in the
    \\  // coverage grid actually means on screen.
    \\  //
    \\  // A HARD MATERIAL SKIPS THE RING ENTIRELY. The ring's whole job is to soften a boundary, which
    \\  // is exactly what stone must not do — with it applied a flagged floor still dissolved over a
    \\  // cell however crisply it was painted. Its edge is then whatever the author painted, no softer.
    \\  bool hard = soilHard(id);
    \\  float a = soilCovAt(q, hard);
    \\  if (!hard) a *= cov/5.0;
    \\  return mix(c, s, a*0.92);
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
    \\  // LAST, over the paint as well: sand is soaked by the water standing on it, whatever material
    \\  // somebody painted there.
    \\  c = wetShore(c, p);
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
    \\    // `blotch`, NOT `patch`: `patch` is a RESERVED WORD in GLSL (the tessellation qualifier), and
    \\    // a driver that enforces it — Intel's does — fails the whole scene shader to compile, which
    \\    // is a hard panic at startup with nothing but "syntax error" and a line number to go on. Any
    \\    // local named for a tessellation, layout or subroutine keyword is the same trap.
    \\    float blotch = smoothstep(0.35, 0.75, fvn(q, 2.4, vec2(0.0), px));
    \\    base *= (0.72 + 0.26*blotch)*(0.88 + 0.12*fvn(q, 8.2, vec2(3.3), px));
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
    \\  } else if (m == 12){ // SMOKE: no surface texture either, for the flame's reason — the generic
    \\    // grain mottles the one thing here that is supposed to have no surface at all. What it gets
    \\    // instead is a slow roil, an order of magnitude below the flame's flicker: smoke churns, it
    \\    // does not gutter, and anything faster reads as static on a distant plume.
    \\    base *= 0.90 + 0.16*fvn(q, 0.9, vec2(31.0), px) + 0.05*sin(uTime*1.7 + q.x*1.3 + q.y*0.9);
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
    \\    // THE PAINTED SHEET reads its colour from the field instead of from the mesh: one quad over
    \\    // the whole world, present only where the field says water and shaded deep→shallow by how far
    \\    // inside the shore it is. Dry fragments are DISCARDED, which is what lets one sheet serve any
    \\    // shape of lake without a mesh per coastline. Authored water props (waterSheet == 0) keep the
    \\    // deep→shallow ramp baked into their own vertices.
    \\    if (waterSheet == 1){
    \\      // `q` IS world xz for water (see the call site — water textures in world space, not surface
    \\      // UVs), which is the coordinate the field is indexed in.
    \\      float f = waterField(q);
    \\      if (f < 0.503) discard;                       // outside the waterline: no sheet here at all
    \\      float d = clamp((f - 0.5)*2.0, 0.0, 1.0);     // 0 at the shore, 1 in the deep
    \\      // The three tones come from the PALETTE (propart.WATER_SHALLOW/MID/DEEP), pushed in as
    \\      // uniforms by env.drawWater. They were literals here, hand-converted to linear — a second
    \\      // copy of an authored colour, which meant retuning the tarn silently left the painted water
    \\      // a different colour from the placed water beside it.
    \\      base = (d < 0.5) ? mix(waterTone[0], waterTone[1], smoothstep(0.0, 0.5, d))
    \\                       : mix(waterTone[1], waterTone[2], smoothstep(0.5, 1.0, d));
    \\      // …and the last half metre of it goes THIN, so the edge dies into the wet sand instead of
    \\      // ruling a line across it. (No blending: the ground shows through where we discard.)
    \\      if (d < 0.06 && fract(q.x*0.9 + q.y*0.7 + vnoise(q*2.3)*3.0) > d*14.0) discard;
    \\    }
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
    \\  // …and the flame's own body is the only thing here that is not opaque. Graded off the VERTEX
    \\  // emissive rather than a second channel: `emis` runs ~0.90 at FLAME_CORE down to ~0.65 at
    \\  // FLAME_TIP, which is already the hot-to-cool ramp the tongues are authored with.
    \\  // The depth WRITE stays on, so a flame blends over what was drawn BEFORE it — the ground, the
    \\  // water, its own ironwork — and its overlapping tongues do not stack into a brighter core. A
    \\  // prop drawn after it and standing behind it is still occluded, which at a torch's size reads
    \\  // as nothing; sorting the whole prop pass to fix that would cost far more than it buys.
    \\  float outA = (mi == 11) ? mix(FLAME_A_TIP, FLAME_A_CORE, smoothstep(0.62, 0.90, emis)) : 1.0;
    \\  // SMOKE IS THIN, AND IT THINS OUT. Two curves on the puff's own life: a quick fade IN so it
    \\  // does not pop into existence at the fire, and a long fade OUT over most of the climb, which is
    \\  // both what makes it dissipate and what recycles the puff invisibly.
    \\  //
    \\  // SMOKE_A is the ceiling and it is deliberately LOW (owner: the first version was far too
    \\  // opaque). Woodsmoke is something you see the world THROUGH; at anything near solid it stops
    \\  // being smoke and becomes a shape, and the shape it most resembles is a bone.
    \\  if (mi == 12) outA = SMOKE_A*smoothstep(0.0, 0.10, fragLife)*(1.0 - smoothstep(0.30, 1.0, fragLife));
    \\  finalColor = vec4(outc, outA);
    \\}
;

// ── SKY ── a fullscreen shader quad drawn before the 3D pass (in place of the old flat
// 2D gradient): vertical slate gradient, a golden bank + aureole + disc around the sun,
// and a streaky fbm cloud deck with warm sunward rims. Output is DISPLAY-space (the 2D
// pass has no gamma); the horizon band is authored to the displayed value of HAZE so the
// 3D distance haze dissolves into it seamlessly.
pub const skyVS =
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
pub const skyFS =
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


pub const retroFS =
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
