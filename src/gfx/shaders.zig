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
    \\// raylib's own per-draw tint (`drawModelEx`'s last argument). Everything in the scene passes WHITE and is
    \\// unaffected; the fog gate passes an ember tint to say it is SHUT. `a` must stay 255 on any tint — the FS
    \\// reads `1 - fragColor.a` as EMISSIVE, so a translucent tint would silently relight the model.
    \\uniform vec4 colDiffuse;
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
    \\        // Flora sway: bend grows with height^2 so bases stay planted while tips lean; phase keys off the clump's WORLD origin so neighbours move as one gust field.
    \\        vec3 baseW = vec3(matModel*vec4(0.0, 0.0, 0.0, 1.0));
    \\        float h = max(p.y, 0.0);
    \\        float bend = h*h*windAmt*0.10;
    \\        float phase = uTime*1.5 + baseW.x*0.6 + baseW.z*0.5;
    \\        float sway = sin(phase) + 0.3*sin(phase*2.7 + 1.3);
    \\        p.x += bend*sway;
    \\        p.z += bend*sway*0.4;
    \\    }
    \\    // EVERY BRANCH IS BOUNDED AT THE TOP, and that is load-bearing: an open-ended `> 11.5` claims every
    \\    // id ADDED AFTER. `bark` (14) went in and every trunk in the wood started climbing like an ember.
    \\    if (vertexTexCoord2.x > 11.5 && vertexTexCoord2.x < 13.5) {
    \\        vec3 baseW = vec3(matModel*vec4(0.0, 0.0, 0.0, 1.0));
    \\        float oy   = floor(vertexTexCoord2.y);   // the source height…
    \\        float seed = fract(vertexTexCoord2.y);   // …and this puff's own place in the cycle
    \\        // EMBERS (13) RIDE THE SAME CONTRACT AS SMOKE (12) and differ in all three of its terms.
    \\        bool mote = vertexTexCoord2.x > 12.5;
    \\        float life = fract(uTime*(mote ? 0.42 : 0.20) + seed + baseW.x*0.031 + baseW.z*0.027);
    \\        fragLife = life;
    \\        // BILLOW: the puff swells about its own source as it climbs.
    \\        vec3 c = vec3(0.0, oy, 0.0);
    \\        p = c + (p - c)*(mote ? (0.95 + 0.55*life) : (0.42 + 2.30*life));
    \\        // RISE, and LEAN once it has slowed: the lateral term is life-squared because smoke goes up first and sideways later — it is climbing fastest while it is still hottest.
    \\        p.y += life*(mote ? 5.60 : 3.30);
    \\        float sway = sin(uTime*0.63 + seed*23.0)*0.34*life;
    \\        p.x += life*life*1.45 + sway;
    \\        p.z += life*life*0.55 - sway*0.4;
    \\    } else if (vertexTexCoord2.x > 10.5 && vertexTexCoord2.x < 11.5) {
    \\        vec3 baseW = vec3(matModel*vec4(0.0, 0.0, 0.0, 1.0));
    \\        // CLAMPED: the drifting wisps are authored up to a whole unit above the fuel, and an h-squared term would fling those across the room.
    \\        float hh = clamp(p.y - vertexTexCoord2.y, 0.0, 0.6);
    \\        float w = hh*hh;
    \\        float tongue = p.x*9.3 + p.z*7.7;        // per-tongue — they sit at different offsets
    \\        float seed = baseW.x*1.7 + baseW.z*1.3;  // …and no two FIRES gutter together
    \\        // SLOWED AND SMOOTHED (owner: the flames read skinny and weird).
    \\        float ph = uTime*4.9 + seed + tongue - hh*9.0;
    \\        float lash  = sin(ph) + 0.42*sin(ph*2.31 + 1.7) + 0.12*sin(ph*4.70 + 0.4) + 0.05*sin(ph*9.10);
    \\        float twist = sin(ph*0.61 + 2.1) + 0.40*sin(ph*1.90 + 3.3);
    \\        // AMPLITUDE IS A FRACTION OF A TONGUE'S WIDTH, NOT OF ITS HEIGHT.
    \\        p.x += w*0.150*lash  + hh*0.034*twist;
    \\        p.z += w*0.125*twist - hh*0.028*lash;
    \\        // SHOOT: tongues leap and drop back, biased upward — fire climbs.
    \\        p.y += hh*(0.105*sin(ph*0.83 + 0.9) + 0.040*sin(ph*2.7)) + w*0.150*max(0.0, sin(ph*0.47));
    \\        // NECK, about the prop's own axis — which is where a torch's flame sits.
    \\        float pinch = 1.0 + 0.17*hh*sin(ph*1.37 + 0.7);
    \\        p.x *= pinch;
    \\        p.z *= pinch;
    \\    } else if (vertexTexCoord2.x > 14.5 && vertexTexCoord2.x < 15.5) {
    \\        // THE FOG GATE. `animY` is the sheet's own height fraction (0 at the threshold, 1 at the head),
    \\        // authored per row by propfx.fogGateMesh — it drives the billow HERE and the fade in the FS, so
    \\        // the two cannot disagree about which end is the top.
    \\        vec3 baseW = vec3(matModel*vec4(0.0, 0.0, 0.0, 1.0));
    \\        float h = clamp(vertexTexCoord2.y, 0.0, 1.0);
    \\        fragLife = h;
    \\        // No two gates in a world breathe together (owner: more undulating). It HEAVES rather than
    \\        // flutters: the biggest term is also the SLOWEST, and the two above it only break its edge.
    \\        float ph = uTime*0.58 + baseW.x*0.29 + baseW.z*0.23;
    \\        float swell = sin(ph*0.43 + p.x*0.55 + h*1.15);
    \\        float roll = sin(ph + p.x*1.30 + h*2.7) + 0.42*sin(ph*1.87 - p.x*2.10 + h*4.9) + 0.16*sin(ph*3.10 + h*8.0);
    \\        // OUT OF ITS OWN FACE, and further out the higher up it is: the foot of a fog wall is held by
    \\        // the doorway and the head of it is not held by anything.
    \\        p.z += (0.070 + 0.300*h)*roll + (0.050 + 0.190*h)*swell;
    \\        p.x += 0.130*h*sin(ph*0.71 + p.y*1.7) + 0.070*h*swell;
    \\        p.y += 0.150*h*sin(ph*1.23 + p.x*0.90);
    \\    } else if (vertexTexCoord2.x > 7.5 && vertexTexCoord2.x < 8.5 && vertexTexCoord2.y > 0.0) {
    \\        // DANGLE (plant, 8). `animY` is the MODEL-space height of the point this vertex hangs FROM, so the
    \\        // throw is LINEAR in the drop below it — a thread swinging by theta carries a point at distance L
    \\        // by L*sin(theta). The flora term above is h-squared because that is a stalk rooted at the GROUND;
    \\        // used here it would pin the bead and swing the thing it hangs off.
    \\        vec3 baseW = vec3(matModel*vec4(0.0, 0.0, 0.0, 1.0));
    \\        float drop = max(vertexTexCoord2.y - p.y, 0.0);
    \\        // 0.017 m per metre of drop and the two terms peak near 1.3, so 3 cm on the deepest authored hang
    \\        // (`propfungus.DANGLE_DROP_MAX`) — half a spore bead's own width, and 2 texels of mesh-to-shadow
    \\        // divorce at SHADOW_ORTHO 108 m over 8192, since the depth pass has no wind term.
    \\        // Off the flora's 1.5, or the fungus beats in time with the grass. `- drop` lags the far end.
    \\        float ph = uTime*1.15 + baseW.x*0.6 + baseW.z*0.5 + vertexTexCoord2.y*2.7 - drop*1.4;
    \\        float swing = sin(ph) + 0.3*sin(ph*2.31 + 1.1);
    \\        p.x += drop*0.017*swing;
    \\        p.z += drop*0.017*swing*0.55;
    \\    }
    \\    fragPosition = vec3(matModel*vec4(p, 1.0));
    \\    fragColor = vertexColor*colDiffuse;
    \\    fragNormal = normalize(mat3(matModel)*vertexNormal);
    \\    fragUV = vertexTexCoord;      // surface-anchored, ~world units (Builder authors these)
    \\    fragMatF = vertexTexCoord2.x; // material id (gfx.Mat), constant per face
    \\    gl_Position = mvp*vec4(p, 1.0);
    \\}
;
pub const sceneFS =
    \\#version 330
    \\in vec3 fragPosition;
    \\in vec4 fragColor;
    \\in vec3 fragNormal;
    \\in vec2 fragUV;
    \\in float fragMatF;
    \\in float fragLife;        // smoke only — see the vertex shader's rise block
    \\uniform vec3 sunDir;      // normalized, surface -> whatever is CASTING (sun by day, moon by night)
    \\uniform int groundMode;   // 1 = terrain (procedural grain), 0 = props/hero
    \\uniform vec3 camPos;      // for distance haze
    \\uniform vec3 hazeColor;   // sky/haze tint (pre-gamma)
    \\uniform float hazeDensity;
    \\// THE HOUR'S OWN COLOURS (`daynight.Palette`, pushed by `gfx.Scene.setHour`). The KEY carries its own
    \\// strength, so nightfall is this vector walking toward black; the hemisphere pair is the ambient it sits
    \\// in, and `hazeBank` the warm wash the distance takes on looking into the light.
    \\uniform vec3 keyCol;
    \\uniform vec3 ambGround;
    \\uniform vec3 ambSky;
    \\uniform vec3 hazeBank;
    \\// …and how bright the key is against the hour the SPECULARS were authored at (1 = that hour). Every
    \\// highlight here is a mirror of the key, so left at full a blade blazed like noon under a half moon.
    \\uniform float keyAmt;
    \\uniform float hitFlash;   // 0..1 blood-red combat flash on the CURRENT draw (per-actor)
    \\uniform float frost;      // 0..1 rime coating on the CURRENT draw (per-actor) — chilled bodies
    \\uniform float fade;       // 1 = solid, <1 = see THROUGH the current draw — see Scene.setFade
    \\uniform float uTime;      // seconds — water ripple phase (shared with the VS wind term)
    \\uniform mat4 lightVP;     // sun's ortho view-projection (captured in the depth pass)
    \\uniform sampler2D shadowMap;
    \\uniform int shadowMapResolution;
    \\uniform vec3 lightPos[16];  // MAX_LIGHTS point lights: the nearest world fires, plus any CARRIED one
    \\uniform vec3 lightCol[16];  // colour * intensity (pre-gamma)
    \\uniform float lightRad[16];
    \\uniform int nLights;
    \\out vec4 finalColor;
    \\// HOW SOLID A FLAME IS (owner's call: all flames somewhat transparent).
    \\const float FLAME_A_CORE = 0.86;
    \\const float FLAME_A_TIP = 0.42;
    \\const float SMOKE_A = 0.34;   // the ceiling on a puff — see the fade at the bottom of main()
    \\const float EMBER_A = 0.85;   // …and on a mote, which is nearly solid: it is a lit coal, not vapour
    \\const float FOG_A = 0.97;     // a fog gate at the THRESHOLD, where it is thickest — it is a door, not a haze
    \\float hash21(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
    \\float vnoise(vec2 p){ vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    \\  return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x), mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y); }
    \\float speck(vec2 p, float s){ return hash21(floor(p*s)); }
    \\// Every pattern below is procedural, sampled ONCE per fragment at a FIXED frequency in world/UV units.
    \\float uvFoot(vec2 q){ return length(fwidth(q)); }
    \\// How unresolvable a `freq`-cycles-per-unit term is at this footprint: 0 = fine, 1 = mush.
    \\float band(float freq, float px){ return smoothstep(0.35, 1.0, px*freq); }
    \\float fvn(vec2 q, float freq, vec2 off, float px){ return mix(vnoise(q*freq + off), 0.5, band(freq, px)); }
    \\float fvn2(vec2 q, vec2 freq, vec2 off, float px){ return mix(vnoise(q*freq + off), 0.5, band(max(freq.x, freq.y), px)); }
    \\// speck is a HARD hash (floor, no interpolation), so it is the worst offender of the lot.
    \\float fspk(vec2 q, float freq, float px){ return mix(speck(q, freq), 0.5, band(freq, px)); }
    \\// The albedo LOD above fixes patterns; this fixes HIGHLIGHTS, which alias for the same reason.
    \\float lobe(float px, float k){ return max(1.0/(1.0 + px*k), 0.05); }
    \\// dark): sun-bleached khaki grass drifting to damp green, a worn dirt path down the ruin avenue (x ~ 0, edges wobbled), stony patches, and dark scrub clumps.
    \\uniform sampler2D soilMap;
    \\uniform float soilHalf;    // world half-extent the grid spans
    \\uniform float soilCell;    // metres per grid cell — the scale the coverage ring samples at
    \\uniform int   soilOn;      // 0 = nothing painted anywhere; skip the fetch entirely
    \\vec3 soilColor(int id){
    \\  // Authored NEAR-BLACK like every other albedo here — the shader's hot key plus the gamma lift turns any mid-dark value pale where a big face takes the sun square on.
    \\  if (id==1) return vec3(0.130, 0.106, 0.074);  // trodden dirt / a path worn through
    \\  if (id==2) return vec3(0.072, 0.098, 0.042);  // green turf
    \\  if (id==3) return vec3(0.132, 0.134, 0.130);  // stone, flagged or scoured bare
    \\  if (id==4) return vec3(0.150, 0.132, 0.090);  // pale silt, the tarn's margin
    \\  if (id==5) return vec3(0.062, 0.058, 0.054);  // ash and burnt ground
    \\  if (id==6) return vec3(0.046, 0.062, 0.034);  // deep moss
    \\  // The three below separate from the six above on HUE, not value: neutral-cool, warm-black, violet.
    \\  if (id==7) return vec3(0.165, 0.156, 0.132);  // bone meal - the palest ground in the table
    \\  if (id==8) return vec3(0.058, 0.044, 0.038);  // cinder, a burnt crust warmer and darker than ash
    \\  if (id==9) return vec3(0.058, 0.048, 0.062);  // spore floor, the one COLD ground
    \\  if (id==10) return vec3(0.115, 0.055, 0.070);  // fungal bloom - the one PINK ground, mauve at 122/85/97 on screen
    \\  return vec3(0.046, 0.062, 0.034);
    \\}
    \\int soilAt(vec2 w){
    \\  vec2 uv = w/(2.0*soilHalf) + 0.5;
    \\  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0;
    \\  return int(texture(soilMap, uv).r*255.0 + 0.5);
    \\}
    \\// brush (wf.Map.soilCov).
    \\uniform sampler2D soilCovMap;
    \\// …AND HOW THE PATCH ENDS, one authored `wf.Edge` per cell (wf.Map.soilEdge), point-sampled and
    \\// DILATED one cell at upload so the bare side of a boundary answers with the same policy as the
    \\// painted side. Without that dilation a tiled courtyard is tiled looking out and soft looking in.
    \\uniform sampler2D soilEdgeMap;
    \\int soilEdgeAt(vec2 w){
    \\  vec2 uv = w/(2.0*soilHalf) + 0.5;
    \\  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 1;   // natural
    \\  return int(texture(soilEdgeMap, uv).r*255.0 + 0.5);
    \\}
    \\// **THE THREE KNOBS AN EDGE ACTUALLY HAS.** x = how far the lookup wanders off the authored line in
    \\// metres, y = the wavelength it wanders at in cycles/metre, z = how much the 4-tap neighbour feather
    \\// survives (1 = full soft ring, 0 = a clean cut). Ordinals are pinned to `wf.Edge` by a comptime
    \\// assert there — an inserted row would re-point every stroke in every map at the wrong shape.
    \\vec3 edgeShape(int e){
    \\  if (e==0) return vec3(0.0,  0.00, 1.60);  // blend    — no wander, the widest feather of the set
    \\  if (e==2) return vec3(1.1,  1.90, 1.00);  // frayed   — a light fast wander, still soft
    \\  if (e==3) return vec3(3.2,  2.60, 0.00);  // jagged   — deep, fast, and CUT: a torn line
    \\  if (e==4) return vec3(0.0,  0.00, 0.00);  // straight — exactly where it was painted
    \\  if (e==5) return vec3(0.0,  0.00, 0.00);  // tiled    — straight, and snapped to the grid below
    \\  if (e==6) return vec3(1.5,  0.00, 0.00);  // scallop  — a periodic wave, not noise (see below)
    \\  if (e==7) return vec3(0.9,  3.40, 0.55);  // speckle  — flecks off the end of it
    \\  return vec3(1.7, 0.62, 1.00);             // 1 = natural, the wander everything used to have
    \\}
    \\// WHERE THE LOOKUP ACTUALLY READS FROM. This is the whole fix: the displacement used to be one fixed
    \\// noise applied to EVERY material before anything else was asked, so the material BOUNDARY wandered
    \\// +/-1.7 m whatever its policy said — and `soilHard` only ever snapped the COVERAGE. Nothing could
    \\// produce a straight edge because the thing being straightened was not the thing being bent.
    \\vec2 edgeWarp(vec2 p, int e, vec3 k){
    \\  if (k.x <= 0.0001) return p;
    \\  if (e==6){
    \\    // The scallop is DELIBERATE, so it is a sine along both axes rather than noise — a laid border.
    \\    return p + vec2(sin(p.y*0.9), sin(p.x*0.9))*k.x;
    \\  }
    \\  vec2 j = vec2(vnoise(p*k.y), vnoise(p*k.y + 47.3)) - 0.5;
    \\  return p + j*2.0*k.x;
    \\}
    \\float soilCovAt(vec2 w, bool snap){
    \\  vec2 uv = w/(2.0*soilHalf) + 0.5;
    \\  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 0.0;
    \\  // SNAPPING THE UV TO THE TEXEL CENTRE point-samples out of the same bilinear texture, which is the
    \\  // trick that lets one texture serve both policies. Only `tiled` asks for it.
    \\  if (snap){ float n = 2.0*soilHalf/soilCell; uv = (floor(uv*n) + 0.5)/n; }
    \\  return texture(soilCovMap, uv).r;
    \\}
    \\// of it: 0.5 is the waterline, above it depth, below it the walk back to dry land.
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
    \\// WET SAND.
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
    \\  // **THE POLICY IS READ FIRST, AT THE UNWARPED POSITION.** It has to be: the warp is what the policy
    \\  // decides, so sampling the edge through it would ask the answer to choose the question. The map is
    \\  // dilated one cell at upload, so this reads the patch's own policy from either side of its boundary.
    \\  int e = soilEdgeAt(p);
    \\  vec3 k = edgeShape(e);
    \\  vec2 q = edgeWarp(p, e, k);
    \\  // …then SOFTEN IT BY COVERAGE.
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
    \\  // THE TWO COVERAGES MULTIPLY, and they answer different questions: the brush's own strength, and how
    \\  // much of this cell's NEIGHBOURHOOD is the same material. `k.z` is how much of the second one the
    \\  // shape wants — 0 cuts the ring out entirely and the edge lands wherever the coverage does.
    \\  float a = soilCovAt(q, e==5);
    \\  if (k.z > 0.0001) a *= clamp((cov/5.0)*k.z, 0.0, 1.0);
    \\  // AND THE SPECKLE BREAKS ITS LAST STRETCH INTO FLECKS rather than fading: a hard per-cell hash
    \\  // thresholded against the coverage, so full cover is solid and the tail scatters and stops.
    \\  if (e==7) a *= step(speck(p, 2.7), a*1.35);
    \\  return mix(c, s, a*0.92);
    \\}
    \\vec3 terrainAlbedo(vec2 p, float px){
    \\  float f1 = fvn(p, 0.055, vec2(0.0), px);
    \\  float f2 = fvn(p, 0.35, vec2(7.7), px);
    \\  float f3 = fvn(p, 1.6, vec2(3.1), px);
    \\  // `blades` is the ground's sizzle: a 7-cycle noise plus a 31-cell HARD hash.
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
    \\  // REGION DRIFT.
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
    \\  // LAST, over the paint as well: sand is soaked by the water standing on it, whatever material somebody painted there.
    \\  c = wetShore(c, p);
    \\  return c*(0.78 + 0.22*fvn(p, 0.03, vec2(9.7), px));
    \\}
    \\// vertexTexCoord2.x) plus surface-anchored UVs in ~world units, so patterns stick to bones and props instead of swimming through world space when they animate.
    \\float mottle(vec2 p){ return vnoise(p)*0.6 + vnoise(p*3.7 + 11.3)*0.4; }
    \\// mottle is TWO octaves (freq and 3.7*freq), and they must be banded SEPARATELY.
    \\float fmot(vec2 q, float freq, float px){
    \\  return mix(vnoise(q*freq), 0.5, band(freq, px))*0.6
    \\       + mix(vnoise(q*freq*3.7 + 11.3), 0.5, band(freq*3.7, px))*0.4;
    \\}
    \\// facing the sky, and lichen takes the faces that never see the sun.
    \\vec3 weather(vec3 c, vec2 q, vec3 n, float px){
    \\  float up = clamp(n.y, 0.0, 1.0);   // 1 = a ledge, a step tread, the top of a fallen drum
    \\  float vert = 1.0 - abs(n.y);       // 1 = a wall or a column shaft, 0 = a floor or a soffit
    \\  // RUNOFF: streaks stretched hard along the vertical, on the verticals only.
    \\  float streak = fvn2(q, vec2(7.0, 0.35), vec2(13.7), px)*0.65
    \\               + fvn2(q, vec2(19.0, 0.70), vec2(5.3), px)*0.35;
    \\  c *= 1.0 - 0.16*vert*smoothstep(0.45, 0.95, streak);
    \\  // SETTLED DIRT on whatever faces the sky, broken up so a ledge is grimy in patches and not uniformly dimmed (which would just read as the light being wrong).
    \\  c *= 1.0 - 0.13*up*smoothstep(0.30, 0.85, fvn(q, 1.7, vec2(41.3), px));
    \\  // LICHEN takes the COLD faces — biased away from the low western sun (gfx.SUN_DIR) — and it TINTS rather than darkens.
    \\  float cold = clamp(-(n.x*0.6 + n.z*0.8), 0.0, 1.0);
    \\  float lich = smoothstep(0.55, 0.92, fvn(q, 1.1, vec2(59.1), px))*cold*vert;
    \\  return mix(c, c*vec3(0.78, 0.94, 0.72), lich*0.55);
    \\}
    \\vec3 matAlbedo(int m, vec2 q, vec3 base, vec3 n, float px){
    \\  if (m == 1){        // STONE: blotch at TWO scales, two-octave grain, soft strata, ROUNDED pits.
    \\    // All smooth value noise — hard speck/step cells read as square pixels on a close column face, so weathering must stay soft-edged.
    \\    float mass = fvn(q, 0.30, vec2(17.3), px);
    \\    float blotch = fvn(q, 2.1, vec2(0.0), px);
    \\    float grain = fvn(q, 6.1, vec2(4.7), px)*0.6 + fvn(q, 12.3, vec2(9.2), px)*0.4;
    \\    float strata = fvn2(q, vec2(0.4, 3.4), vec2(23.1), px);
    \\    base *= (0.88 + 0.12*mass + 0.12*blotch)*(0.94 + 0.12*grain)*(0.94 + 0.12*strata);
    \\    // …and the pits read as EROSION rather than as pepper.
    \\    base *= 1.0 - 0.15*smoothstep(0.70, 0.97, fvn(q, 5.5, vec2(31.7), px));
    \\    base = weather(base, q, n, px);   // rubble masonry has stood out in the rain the longest
    \\  } else if (m == 2){ // WOOD: long grain streaks along v, slow wander, BOARD scale
    \\    float grain = fvn2(q, vec2(9.0, 0.8), vec2(0.0), px);
    \\    // Timber comes in PIECES.
    \\    float board = fvn2(q, vec2(0.35, 2.6), vec2(31.1), px);
    \\    base *= (0.82 + 0.30*grain)*(0.94 + 0.12*fvn(q, 2.9, vec2(5.1), px))*(0.95 + 0.10*board);
    \\    // KNOTS: sparse dark rounds where a branch was — the one thing bare grain cannot say.
    \\    base *= 1.0 - 0.24*smoothstep(0.80, 0.97, fvn(q, 3.6, vec2(47.9), px));
    \\  } else if (m == 14){ // BARK: FISSURES up the trunk, in PLATES, over the close grain.
    \\    // The furrows ARE the read, and a two-octave value field is too soft to be one on its own: the
    \\    // ridge function pow(1-|2f-1|, n) spends most of its range near 0 and dives to 1 in a narrow
    \\    // crack, which is the shape of a furrow rather than of a blotch.
    \\    // COARSE on purpose: at 13 cycles/unit the furrows came out as fine even pinstripes and the
    \\    // trunk read as brushed timber. Bark is a few centimetres of relief every hand's width.
    \\    float fis = fvn2(q, vec2(7.0, 0.90), vec2(0.0), px)*0.60 + fvn2(q, vec2(17.0, 2.00), vec2(7.3), px)*0.40;
    \\    // Banded on the COARSE octave: once even that is unresolvable `fis` sits at 0.5, and an unbanded
    \\    // ridge would read 1.0 there — every far trunk uniformly dark. 1/4 is this term's own mean.
    \\    float furrow = mix(pow(1.0 - abs(fis*2.0 - 1.0), 3.0), 0.25, band(7.0, px));
    \\    // MEAN-PRESERVING on purpose (1.22 - 0.88*0.25 = 1.0): the ridges come up as far as the cracks
    \\    // go down, so pushing the contrast does not quietly re-darken every trunk in the wood.
    \\    base *= 1.22 - 0.88*furrow;
    \\    // Bark comes off in PLATES, each weathered its own amount…
    \\    base *= 0.82 + 0.36*fvn2(q, vec2(1.3, 0.7), vec2(23.7), px);
    \\    // …and where one has dropped off, the sapwood under it is pale and smooth.
    \\    base *= 1.0 + 0.34*smoothstep(0.88, 0.99, fvn(q, 2.4, vec2(51.3), px));
    \\    base *= 0.93 + 0.14*fvn(q, 7.0, vec2(3.1), px);
    \\  } else if (m == 3){ // CLOTH: soft anisotropic weave + broad wrinkle shading + FOLDS
    \\    float weave = fvn2(q, vec2(30.0, 3.2), vec2(0.0), px)*0.5 + fvn2(q, vec2(3.2, 30.0), vec2(9.7), px)*0.5;
    \\    // Broad banding along the hang, anisotropic the OTHER way from the weave: a banner has to read as cloth carrying its own weight, not as a painted board.
    \\    float fold = fvn2(q, vec2(1.1, 0.22), vec2(17.9), px);
    \\    base *= (0.91 + 0.15*weave)*(0.92 + 0.15*fvn(q, 1.7, vec2(2.3), px))*(0.94 + 0.12*fold);
    \\  } else if (m == 4){ // STEEL: fine brush lines along the length + broad soft tarnish + PITTING
    \\    // 46 cycles/unit is the highest frequency in the whole shader — a blade or a helm seen across the avenue was sampling it once per pixel and strobing.
    \\    float brush = fvn2(q, vec2(46.0, 2.3), vec2(0.0), px);
    \\    base *= (0.94 + 0.11*brush)*(0.95 + 0.10*fvn(q, 0.9, vec2(7.7), px));
    \\    // Old iron is not evenly bright.
    \\    base *= 1.0 - 0.12*smoothstep(0.68, 0.95, fvn(q, 3.3, vec2(27.7), px));
    \\  } else if (m == 5){ // LEATHER: pore stipple + crease mottle + PANEL scale
    \\    base *= (0.90 + 0.17*fvn(q, 13.0, vec2(0.0), px))*(0.92 + 0.15*fvn(q, 3.1, vec2(6.3), px));
    \\    // A bracer, a pauldron and a scabbard are CUT PIECES; one pore field across the lot of them reads as moulded plastic however good the pores are.
    \\    base *= 0.95 + 0.10*fvn(q, 0.80, vec2(37.3), px);
    \\  } else if (m == 6){ // SKIN: faint soft mottle only
    \\    base *= 0.94 + 0.11*fmot(q, 4.6, px);
    \\  } else if (m == 7){ // HIDE: amphibian blotch patches + fine wart grain — DARKEN
    \\    // only (max ~1.0): the bog toad must stay a near-black night thing, its blotches reading as damp shadow, never pale camo.
    \\    float blotch = smoothstep(0.35, 0.75, fvn(q, 2.4, vec2(0.0), px));
    \\    base *= (0.72 + 0.26*blotch)*(0.88 + 0.12*fvn(q, 8.2, vec2(3.3), px));
    \\  } else if (m == 8){ // PLANT: broad value drift so clumps read as many blades
    \\    base *= 0.87 + 0.22*fmot(q, 2.2, px);
    \\    // …a LEAF-scale octave with real contrast, and a SINGLE-LEAF one over it (which bands itself
    \\    // out by ~20 m, so it costs nothing at the distance most of the wood is seen from)…
    \\    base *= 0.86 + 0.28*fvn(q, 9.0, vec2(13.1), px);
    \\    base *= 0.94 + 0.12*fvn(q, 22.0, vec2(63.7), px);
    \\    // …and sparse DARK POCKETS between leaf clusters at two scales, so a big lobe reads as
    \\    // foliage with holes in it — the metre-scale one is what breaks a flat facet seen from under the canopy.
    \\    base *= 1.0 - 0.24*smoothstep(0.62, 0.94, fvn(q, 4.6, vec2(41.3), px));
    \\    base *= 1.0 - 0.15*smoothstep(0.58, 0.90, fvn(q, 1.6, vec2(71.7), px));
    \\  } else if (m == 10){ // MARBLE: a cool body crossed by wandering VEINS, plus the crazing
    \\    // and dull weathered patches a thousand years outdoors puts on burnished stone.
    \\    float wob  = fvn(q, 0.9, vec2(0.0), px)*1.7 + fvn(q, 2.7, vec2(3.1), px)*0.55;
    \\    // The veins are the one pattern whose mean ISN'T 0.5: pow(1-|sin|, n) is a thin spike, so it averages to about 1/(n·pi/2) — 0.09 at n=7, 0.05 at n=13.
    \\    float vein = mix(pow(1.0 - abs(sin((q.x*0.8 + q.y*2.4 + wob)*3.1)), 7.0), 0.09, band(20.0, px));
    \\    float hair = mix(pow(1.0 - abs(sin((q.x*2.3 - q.y*1.1 + wob*1.7)*2.2)), 13.0), 0.05, band(26.0, px));
    \\    base *= 1.0 + 0.15*fvn(q, 1.4, vec2(7.7), px) - 0.30*vein - 0.17*hair;
    \\    base *= 0.95 + 0.12*fvn(q, 11.0, vec2(2.9), px);                         // crazing
    \\    base *= 1.0 - 0.17*smoothstep(0.60, 0.92, fvn(q, 0.35, vec2(19.0), px)); // where the polish is gone
    \\    // BLOCK DRIFT: dressed stone is quarried in pieces and no two blocks match.
    \\    base *= 0.94 + 0.12*fvn(q, 0.22, vec2(53.7), px);
    \\    base = weather(base, q, n, px);   // …and the kingdom's own stone has stood out here just as long
    \\  } else if (m == 12){ // SMOKE: no surface texture either, for the flame's reason — the generic
    \\    // grain mottles the one thing here that is supposed to have no surface at all.
    \\    base *= 0.90 + 0.16*fvn(q, 0.9, vec2(31.0), px) + 0.05*sin(uTime*1.7 + q.x*1.3 + q.y*0.9);
    \\  } else if (m == 15){ // FOG GATE: no surface either, and what it has instead is a slow CURDLE — two
    \\    // noise octaves crawling across the sheet at different speeds, which is what keeps a flat quad from
    \\    // reading as a flat quad once the vertex billow has moved it.
    \\    // The octaves DRIFT (an animated offset) rather than sitting still and breathing, so the churn goes
    \\    // somewhere; and the troughs are deliberately deep — an evenly-valued sheet is a sheet of paper, and
    \\    // dark holes moving through a bright body is what says the mass has something inside it.
    \\    base *= 0.58 + 0.44*fvn(q, 0.42, vec2(17.0 + uTime*0.055, -uTime*0.115), px)
    \\          + 0.26*fvn(q, 1.55, vec2(5.3 - uTime*0.090, uTime*0.048), px)
    \\          + 0.09*sin(uTime*0.83 + q.x*0.90 + q.y*0.60);
    \\  } else if (m == 11 || m == 13){ // FLAME and EMBER: no surface texture at all — but they GUTTER.
    \\    // A fire has no SURFACE to weather, and the generic grain the default branch applies was mottling the one thing in the scene that is pure emitted light (flameInto's own comment, "no surface mottle over a glow", asked for this and could not get it — `.plain` IS the grain).
    \\    float fl = sin(uTime*11.0 + q.x*2.1 + q.y*1.7)*0.5
    \\             + sin(uTime*19.0 + q.x*3.3)*0.3
    \\             + sin(uTime*31.0 + q.y*2.6)*0.2;
    \\    base *= 1.0 + 0.10*fl;   // 0.26 on top of an already-hot emissive blew the tongues to yellow
    \\  } else if (m == 9){ // WATER: silt drifting under the surface (the RIPPLES are geometry-
    \\    // free — see waterNormal — this is only what's suspended in the tarn) THE PAINTED SHEET reads its colour from the field instead of from the mesh: one quad over the whole world, present only where the field says water and shaded deep→shallow by how far inside the shore it is.
    \\    if (waterSheet == 1){
    \\      // `q` IS world xz for water (see the call site — water textures in world space, not surface UVs), which is the coordinate the field is indexed in.
    \\      float f = waterField(q);
    \\      if (f < 0.503) discard;                       // outside the waterline: no sheet here at all
    \\      float d = clamp((f - 0.5)*2.0, 0.0, 1.0);     // 0 at the shore, 1 in the deep
    \\      // The three tones come from the PALETTE (propart.WATER_SHALLOW/MID/DEEP), pushed in as uniforms by env.drawWater.
    \\      base = (d < 0.5) ? mix(waterTone[0], waterTone[1], smoothstep(0.0, 0.5, d))
    \\                       : mix(waterTone[1], waterTone[2], smoothstep(0.5, 1.0, d));
    \\      // …and the last half metre of it goes THIN, so the edge dies into the wet sand instead of ruling a line across it.
    \\      if (d < 0.06 && fract(q.x*0.9 + q.y*0.7 + vnoise(q*2.3)*3.0) > d*14.0) discard;
    \\    }
    \\    base *= 0.84 + 0.30*fmot(q, 0.7, px);
    \\  } else {            // PLAIN: the old generic grain, now surface-anchored. This is the DEFAULT
    \\    // material — every untagged shape (the skeleton's bones, eyes, glints) lands here, so its 13-cell hard hash was sizzling on more of the world than any other single term.
    \\    float g = fvn(q, 1.1, vec2(0.0), px)*0.45 + fvn(q, 4.3, vec2(0.0), px)*0.35 + fspk(q, 13.0, px)*0.20;
    \\    base *= 0.88 + 0.24*g;
    \\  }
    \\  return base;
    \\}
    \\// Two crossed swell trains plus a drifting noise octave, differenced to a slope — cheap, and because it keys off WORLD xz the wave field is continuous across the whole lake (per-mesh UVs would seam at the shore ring).
    \\float swell(vec2 q, float t){
    \\  return sin(q.x*0.85 + t*0.95)*0.60 + sin(q.y*0.66 - t*0.72)*0.48
    \\       + sin((q.x + q.y)*2.1 + t*1.9)*0.16 + sin((q.x - q.y*1.7)*4.3 - t*2.7)*0.07
    \\       + vnoise(q*0.7 + vec2(t*0.09, -t*0.07))*1.15 + vnoise(q*3.1 - vec2(t*0.21, t*0.16))*0.28;
    \\}
    \\vec3 waterNormal(vec2 q, float t, float px){
    \\  // The finite-difference baseline must be at least a PIXEL wide.
    \\  float E = max(0.14, px);  // slope sample step, in world units
    \\  // STEEPNESS matters more than it looks.
    \\  const float AMP = 0.24;
    \\  float h0 = swell(q, t);
    \\  return normalize(vec3(-(swell(q + vec2(E, 0.0), t) - h0)/E*AMP, 1.0,
    \\                        -(swell(q + vec2(0.0, E), t) - h0)/E*AMP));
    \\}
    \\// Torch/fire light: quadratic falloff reaching exactly 0 at the radius (so a light can never leak out of its room), lambert wrapped hard so one flame fills a chamber.
    \\vec3 pointLights(vec3 pos, vec3 n){
    \\  vec3 sum = vec3(0.0);
    \\  for (int i = 0; i < nLights; i++){
    \\    vec3 d = lightPos[i] - pos;
    \\    // Reject on the SQUARED distance so out-of-range lights cost no sqrt.
    \\    float r = lightRad[i];
    \\    float d2 = dot(d, d);
    \\    if (d2 >= r*r) continue;
    \\    float dist = sqrt(d2);
    \\    float att = 1.0 - dist/r;
    \\    att *= att;
    \\    // Wrapped, but not so hard that every surface in the room gets the same value — the wrap is there so a torch FILLS a chamber, not so it erases form.
    \\    float ndl = clamp((dot(n, d/max(dist, 1e-4)) + 0.22)/1.22, 0.0, 1.0);
    \\    sum += lightCol[i]*att*ndl;
    \\  }
    \\  return sum;
    \\}
    \\// Fraction of this fragment in sun shadow (0 lit, 1 shadowed): 3x3 PCF.
    \\float shadowFrac(vec3 pos, float ndl){
    \\  vec4 p = lightVP*vec4(pos, 1.0);
    \\  p.xyz /= p.w;
    \\  p.xyz = p.xyz*0.5 + 0.5;
    \\  if (p.z > 1.0 || p.z < 0.0 || p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) return 0.0;
    \\  // Bias is in NDC, so it costs bias*(far-near) WORLD units — the slab widened with the box, so these came DOWN to keep the real offset near 0.22 m.
    \\  float bias = max(0.0013*(1.0 - ndl), 0.00032);
    \\  float texel = 1.0/float(shadowMapResolution);
    \\  float sc = 0.0;
    \\  for (int x = -1; x <= 1; x++)
    \\    for (int y = -1; y <= 1; y++)
    \\      if (p.z - bias > texture(shadowMap, p.xy + vec2(x, y)*texel).r) sc += 1.0;
    \\  return sc/9.0;
    \\}
    \\void main(){
    \\  // Hoisted per-fragment invariants.
    \\  vec3 L = normalize(sunDir);
    \\  vec3 base = fragColor.rgb;
    \\  vec3 n = normalize(fragNormal);
    \\  vec2 p = fragPosition.xz;
    \\  vec3 toCam = camPos - fragPosition;
    \\  float dist = length(toCam);
    \\  vec3 V = toCam/max(dist, 1e-5);
    \\  float nv = clamp(dot(n, V), 0.0, 1.0);
    \\  // Detail-LOD footprints, both taken HERE: `fwidth` needs uniform control flow, and `mi == 9` (water) is NOT uniform — it rides a vertex attribute.
    \\  float pxP = uvFoot(p);
    \\  float pxQ = uvFoot(fragUV);
    \\  int mi = -1;
    \\  if (groundMode==1){
    \\    base *= terrainAlbedo(p, pxP);
    \\  } else {
    \\    mi = int(fragMatF + 0.5);
    \\    // WATER is textured in WORLD xz, not surface UVs: the tarn is a radial fan of quads and the Builder decorrelates UVs per shape, so surface-anchored silt would show the lake's triangulation as a patchwork of unrelated blotches.
    \\    // THE FOG GATE IS THE SAME PROBLEM STOOD UP: it is 224 quads with decorrelated UVs, so a UV-anchored
    \\    // curdle was 224 unrelated blotches averaging out to a flat sheet. It takes world (x+z, y) — the
    \\    // width and the HEIGHT, since a wall varies up as well as along — and world xz's own footprint,
    \\    // which is the right order of magnitude and costs no third `fwidth` over the whole scene.
    \\    vec2 mq = (mi == 9) ? p : (mi == 15) ? vec2(p.x + p.y, fragPosition.y) : fragUV;
    \\    base = matAlbedo(mi, mq, base, n, (mi == 9 || mi == 15) ? pxP : pxQ);
    \\    // …and its ripples live in the NORMAL, so they must land before any lighting term.
    \\    if (mi == 9) { n = waterNormal(p, uTime, pxP); nv = clamp(dot(n, V), 0.0, 1.0); } // ripples move the normal
    \\  }
    \\  float ndl = dot(n, L);
    \\  float diff = clamp((ndl + 0.12)/1.12, 0.0, 1.0); // tighter wrap = crisper terminator (more contrast)
    \\  float sh = shadowFrac(fragPosition, ndl);
    \\  // Golden-hour split: warm amber key vs cool slate sky ambient + warm dirt bounce.
    \\  vec3 hemi = mix(ambGround, ambSky, n.y*0.5 + 0.5); // darker floor — darks go DARKER
    \\  vec3 lit = base*(hemi*(1.0 - 0.62*sh) + keyCol*diff*1.72*(1.0 - sh)
    \\                   + pointLights(fragPosition, n));                                   // + torch/firelight
    \\  if (groundMode == 0){
    \\    // Cool sky rim on props/hero — lifts silhouettes off the dark ground (cheap atmospheric backlight; NOT on terrain, where grazing angles would sheen it all).
    \\    float rim = (mi == 9) ? 0.0 : pow(1.0 - nv, 2.6);
    \\    // The rim IS the sky, so it takes the sky's own ambient rather than a colour of its own — which is
    \\    // what carries it from slate at noon to near-nothing at midnight without a second dial.
    \\    lit += rim*ambSky*0.51*(0.6 + 0.4*n.y)*(1.0 - 0.5*sh);
    \\    // SHINY METAL (STEEL, id 4): a hot, tight Blinn-Phong sun glint + a cool sky sheen on grazing angles, so blades/armour/steel props read as polished metal (not matte).
    \\    if (mi == 4){
    \\      vec3 H = normalize(L + V);
    \\      float nh = max(dot(n, H), 0.0);
    \\      // The tight 96-exponent lobe is what made distant blades and helms strobe; the broad 22 one already spans several pixels, so it is left alone.
    \\      float w = lobe(pxQ, 8.0);
    \\      float sp = pow(nh, 96.0*w)*3.6*w + pow(nh, 22.0)*0.7;  // a BLINDING tight hotspot + a broader sheen
    \\      lit += sp*vec3(1.5, 1.3, 1.0)*keyAmt*(1.0 - sh);       // hot near-white glint — steel POPS
    \\      float fres = pow(1.0 - nv, 4.0);
    \\      lit += fres*vec3(0.34, 0.40, 0.52)*keyAmt*(1.0 - 0.4*sh); // bright cool reflective sky sheen at the edges
    \\    }
    \\    // POLISHED STONE.
    \\    float gloss = (mi == 10) ? 0.55 : (mi == 1) ? 0.09 : 0.0;
    \\    if (gloss > 0.001){
    \\      vec3 Hg = normalize(L + V);
    \\      float nhg = max(dot(n, Hg), 0.0);
    \\      float wg = lobe(pxQ, 8.0); // a burnished capital across the plaza was blinking, same cause
    \\      lit += (pow(nhg, 78.0*wg)*0.72*wg + pow(nhg, 20.0)*0.06)*gloss*vec3(1.18, 1.05, 0.86)*keyAmt*(1.0 - sh);
    \\      lit += pow(1.0 - nv, 6.0)*gloss*vec3(0.07, 0.09, 0.13)*keyAmt;
    \\    }
    \\    // WATER (id 9): a long tight sun streak shattered across the ripples + a broad sky reflection at grazing angles.
    \\    if (mi == 9){
    \\      vec3 H = normalize(L + V);
    \\      float nh = max(dot(n, H), 0.0);
    \\      // A TIGHT glitter path only.
    \\      float ww = lobe(pxP, 10.0);
    \\      lit += (pow(nh, 320.0*ww)*2.6*ww + pow(nh, 48.0)*0.07)*vec3(1.5, 1.26, 0.92)*keyAmt*(1.0 - sh);
    \\      float fres = pow(1.0 - nv, 4.0);
    \\      lit += fres*vec3(0.058, 0.072, 0.104)*keyAmt;          // the slate sky, only at grazing angles
    \\    }
    \\  }
    \\  float emis = 1.0 - fragColor.a;
    \\  lit = mix(lit, base*1.35, emis);
    \\  // Rime: a chilled body wears a pale blue coat while the hold lasts (per-draw, like the flash).
    \\  lit = mix(lit, vec3(0.60, 0.74, 0.88), frost);
    \\  // Combat flash: the struck actor pops for a beat (per-draw uniform). AFTER the frost, so a hit
    \\  // still reads on a frosted body. PALE ARTERIAL, not blood-red: at (0.55,0.07,0.05) the body came
    \\  // back off this chain at luma 111 and the blood flying off it at 48, so the spray was a dark red
    \\  // thing on a red thing. Screen luma here is 185 — the same hue, twice the gap.
    \\  lit = mix(lit, vec3(0.88, 0.38, 0.30), hitFlash);
    \\  float haze = 1.0 - exp(-hazeDensity*dist);
    \\  // Haze banks golden looking into the sun's quarter (matches the sky shader's bank).
    \\  float sunAmt = pow(clamp(dot(-V, L), 0.0, 1.0), 3.0);
    \\  vec3 hazeC = hazeColor + hazeBank*sunAmt;
    \\  lit = mix(lit, hazeC, clamp(haze, 0.0, 1.0));
    \\  // A TOUCH more saturation overall — push colours out from their luma (kept subtle).
    \\  float luma = dot(lit, vec3(0.299, 0.587, 0.114));
    \\  lit = max(mix(vec3(luma), lit, 1.15), 0.0);
    \\  vec3 outc = pow(max(lit, 0.0), vec3(1.0/2.2));
    \\  outc += (hash21(gl_FragCoord.xy) - 0.5)*(2.0/255.0);
    \\  // …and the flame's own body is the only thing here that is not opaque.
    \\  float outA = (mi == 11) ? mix(FLAME_A_TIP, FLAME_A_CORE, smoothstep(0.62, 0.90, emis)) : 1.0;
    \\  // SMOKE IS THIN, AND IT THINS OUT.
    \\  if (mi == 12) outA = SMOKE_A*smoothstep(0.0, 0.10, fragLife)*(1.0 - smoothstep(0.22, 0.90, fragLife));
    \\  // AN EMBER IS THE OPPOSITE OF SMOKE: nearly solid, and it does not dissolve — it WINKS OUT.
    \\  // A FOG GATE IS THICKEST AT THE THRESHOLD AND GONE BEFORE THE LINTEL — the fade is the whole read of
    \\  // it, and it goes to EXACTLY zero at the head so the sheet has no edge to see. `fragLife` is the
    \\  // height fraction the VS put there, so the fade and the billow are the same number.
    \\  if (mi == 15){
    \\    // THE TOP OF IT IS TORN AND IT MOVES. A fade that only ran on height reached zero at the head of the
    \\    // sheet and drew a ruled horizontal line on the way there — a few percent of alpha over something
    \\    // this bright is still a straight edge. So the height the fade DIES AT wanders, per world column and
    \\    // over time, and the sheet is gone well below its own last row.
    \\    float tear = 0.60 + 0.16*sin(uTime*0.37 + fragPosition.x*1.10 + fragPosition.z*0.70)
    \\                     + 0.10*sin(uTime*0.83 - fragPosition.x*2.30)
    \\                     + 0.08*vnoise(vec2(fragPosition.x*1.7 + uTime*0.11, fragPosition.z*1.3));
    \\    // AND IT IS SOLID FOR MOST OF ITS HEIGHT (owner: more opaque). Falling from 0.05 meant the sheet was
    \\    // already half gone at chest height, which is a haze; it now holds full alpha to 0.62 of wherever its
    \\    // own torn head happens to be that frame, and only then goes.
    \\    outA = FOG_A*(1.0 - smoothstep(tear*0.62, tear, fragLife))
    \\         *(0.96 + 0.04*sin(uTime*0.71 + fragPosition.x*0.8 + fragPosition.z*0.6));
    \\  }
    \\  if (mi == 13) outA = EMBER_A*smoothstep(0.0, 0.05, fragLife)*(1.0 - smoothstep(0.55, 1.0, fragLife))
    \\                     *(0.55 + 0.45*sin(uTime*17.0 + fragLife*29.0));
    \\  // …and the CURRENT DRAW may be asked to go see-through on top of all that (the hero under an aim
    \\  // who otherwise fills the frame at that boom length). Per-draw like `hitFlash`, and multiplied in
    \\  // LAST so it thins the flame and the smoke by the same fraction rather than replacing their own.
    \\  finalColor = vec4(outc, outA*fade);
    \\}
;

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
    \\uniform vec3 sunDir;    // the TRUE sun — below the horizon at night, which is the point of it
    \\uniform vec3 moonDir;   // …and the anti-sun, so exactly one of the two is always up
    \\uniform vec2 resolution;
    \\uniform float uTime;    // seconds — the stars' twinkle, and nothing else here
    \\// THE HOUR'S SKY (`daynight.Palette`, pushed by `gfx.Sky.setHour`). Horizon → middle → zenith, then the
    \\// bank laid along the horizon under the light, the aureole round it, the disc itself, and the cloud deck's
    \\// two sides. The SHAPE of the sky is this shader's; every colour in it belongs to the clock.
    \\uniform vec3 skyLow;
    \\uniform vec3 skyMid;
    \\uniform vec3 skyHigh;
    \\uniform vec3 skyBank;
    \\uniform vec3 skyGlow;
    \\uniform vec3 skyDisc;
    \\uniform vec3 cloudDark;
    \\uniform vec3 cloudLit;
    \\uniform float stars;    // 0..1 of the star field, and its own dial — see the note at Palette.stars
    \\out vec4 finalColor;
    \\float hash21(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
    \\float vnoise(vec2 p){ vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    \\  return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x), mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y); }
    \\float fbm(vec2 p){ float a=0.5, s=0.0;
    \\  for (int i=0;i<4;i++){ s+=a*vnoise(p); p=p*2.13+vec2(19.7,7.3); a*=0.5; } return s; }
    \\void main(){
    \\  // Screen ray from gl_FragCoord — NOT fragTexCoord: drawRectangle maps texcoords to raylib's tiny shapes-texture rect, which is constant across the quad.
    \\  float sx = (gl_FragCoord.x/resolution.x)*2.0 - 1.0;
    \\  float sy = (gl_FragCoord.y/resolution.y)*2.0 - 1.0; // gl_FragCoord.y is bottom-up: +1 = screen top
    \\  vec3 ray = normalize(camFwd + sx*camRightS + sy*camUpS);
    \\  float e = max(ray.y, 0.0);
    \\  // WHICHEVER OF THE TWO IS UP is what lights the sky and carries the disc — ONE code path for both,
    \\  // because a moonrise is a sunrise with a different palette and nothing else. The colours do the rest:
    \\  // `skyDisc` is warm at the golden hour and pale at midnight, so the same three lines draw either.
    \\  vec3 sun = normalize(sunDir);
    \\  vec3 moon = normalize(moonDir);
    \\  vec3 lumDir = (sun.y >= moon.y) ? sun : moon;
    \\  float sunAmt = clamp(dot(ray, lumDir), 0.0, 1.0);
    \\  float az = pow(sunAmt, 3.0);
    \\  vec3 col = mix(skyLow, skyMid, smoothstep(0.0,0.22,e));
    \\  col = mix(col, skyHigh, smoothstep(0.18,0.75,e));
    \\  // THE STARS GO UNDER EVERYTHING ELSE IN THE SKY: laid down before the bank, the aureole and the deck,
    \\  // they are washed out near the moon and hidden by cloud, which is the whole of why they read as far off.
    \\  if (stars > 0.002 && ray.y > 0.0){
    \\    // A GNOMONIC-ISH PROJECTION of the ray, so the field is anchored to the SKY and not to the screen —
    \\    // dense overhead, thinning toward the horizon the way a real one does under haze.
    \\    vec2 sp = (ray.xz/(ray.y + 0.42))*7.0;
    \\    vec2 ci = floor(sp*18.0);
    \\    float h = hash21(ci);
    \\    if (h > 0.978){
    \\      // Off-centre inside its own cell, or the field is a lattice however sparse it is.
    \\      vec2 fp = fract(sp*18.0) - 0.5 - (vec2(hash21(ci + 7.13), hash21(ci + 3.71)) - 0.5)*0.62;
    \\      float mag = (h - 0.978)/0.022;                       // how bright THIS one is
    \\      float tw = 0.62 + 0.38*sin(uTime*(1.3 + 3.4*hash21(ci + 11.3)) + h*57.0);
    \\      float pt = smoothstep(0.17, 0.0, length(fp))*(0.30 + 0.70*mag);
    \\      col += vec3(0.80,0.86,1.00)*pt*tw*stars*smoothstep(0.0, 0.20, ray.y)*(1.0 - 0.85*az);
    \\    }
    \\  }
    \\  col += skyBank*az*exp(-e*7.0);                                 // the bank along the horizon
    \\  col += skyGlow*pow(sunAmt, 24.0)*0.50;                         // aureole
    \\  // THE DISC, and the MOON'S IS WIDER AND SOFTER than the sun's — a sun you can look at is a sun that is
    \\  // wrong, and a moon the same angular size as one reads as a hole punched in the sky. `stars` is the
    \\  // night proxy the widening rides, since it is already 0 by day and 1 in the small hours.
    \\  float d0 = mix(0.9993, 0.99855, stars);
    \\  float d1 = mix(0.9998, 0.99925, stars);
    \\  col += skyDisc*smoothstep(d0, d1, sunAmt);
    \\  col += skyDisc*pow(sunAmt, 900.0)*0.22*stars;                  // …and the lunar corona around it
    \\  if (ray.y > 0.0){
    \\    vec2 cp = ray.xz/(ray.y + 0.32);          // low deck: streaks reach the horizon
    \\    float cl = fbm(cp*vec2(1.1,2.2) + vec2(3.1,-6.7));
    \\    float cover = smoothstep(0.34, 0.62, cl)*smoothstep(0.0, 0.06, ray.y);
    \\    vec3 cloudCol = mix(cloudDark, cloudLit, az*0.85);
    \\    col = mix(col, cloudCol, cover*0.85);
    \\    float rim = smoothstep(0.26,0.40,cl) - smoothstep(0.40,0.66,cl);
    \\    col += cloudLit*0.40*rim*(0.45 + 0.55*az);
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
    \\// EVERY read of the captured scene goes through this.
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
    \\  if (fPixelate > 0.0){
    \\    float blk = max(floor(mix(1.0, 14.0, fPixelate) + 0.5), 1.0);
    \\    vec2 grid = max(resolution/blk, vec2(1.0));
    \\    uv = (floor(uv*grid) + 0.5)/grid;
    \\    // …and arm the box filter (see sceneTap).
    \\    if (blk > 1.0) pixQ = blk/(4.0*resolution);
    \\    pixStep = blk/resolution.x;
    \\  }
    \\  // Chroma fringe: fetch R and B slightly off-axis (worn composite cable).
    \\  vec4 baseTex = sceneTap(uv);
    \\  vec3 col;
    \\  if (fChroma > 0.0){
    \\    // THE OFFSET SNAPS TO WHOLE BLOCKS.
    \\    float off = fChroma*0.0045;
    \\    vec2 o = vec2(off, 0.0);
    \\    if (pixStep > 0.0) o.x = floor(off/pixStep + 0.5)*pixStep;
    \\    col.r = sceneTap(uv + o).r;
    \\    col.g = baseTex.g;
    \\    col.b = sceneTap(uv - o).b;
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
    \\  // Film grain: animated per-pixel flicker, HELD on a 24 Hz beat.
    \\  if (fGrain > 0.0){
    \\    float gt = floor(time*24.0);
    \\    float gnoise = hash21(gl_FragCoord.xy + vec2(mod(gt, 97.0)*137.0, mod(gt, 89.0)*291.0));
    \\    col += (gnoise - 0.5)*fGrain*0.18;
    \\  }
    \\  col *= crtMask;
    \\  finalColor = vec4(col, baseTex.a);
    \\}
;
