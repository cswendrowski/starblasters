// Planet Ground — a flat, vertically-scrolling, seamlessly-looping planet SURFACE seen
// from directly above, for a fly-over background. Unlike a plain noise field, each
// `surface_type` reproduces the ACTUAL generator the matching PixelPlanets world uses,
// so the surfaces are genuinely different (continents+rivers vs dunes vs ice vs lava vs
// craters), not one noise pattern recoloured:
//
//   0 TERRAN — domain-warped elevation classified through a NON-UNIFORM biome ladder
//              (deep sea → snow caps, thin sand/snow bands) + warped-fbm river networks.
//   1 DESERT — X-stretched dune ridges with slip-face shading over posterized undulation.
//   2 ICE    — posterized ice sheets + thin fracture cracks (thresholded high-freq fbm).
//   3 LAVA   — dark rock tiers + glowing emissive lava channels (LavaWorld Rivers).
//   4 MOON   — straight flat port of Asteroids.gdshader: 3-tone fbm differential relief +
//              crater interiors reset to mid + bare c2<c1 light crescents, two lattices.
//   5 MOONSTEROID — the kit asteroid EXACTLY: relief + ONE crater lattice, nothing added.
//
// The kit's `d_light = distance(uv, light_origin)` is SPHERE shading — meaningless on a
// flat top-down surface — so it's replaced by a flat directional hillshade() from the
// fbm height field (sun-facing slopes read brighter / one band up).
//
// SEAMLESS LOOP: rand() tiles the lattice at period round(size) along Y, so every fbm/
// circle_noise here is periodic — PROVIDED each sample's Y coord coefficient is a multiple
// of 0.125 (the driver wraps `scroll` at 8×round(size), a whole period for every such
// layer; keep `size` integer). X coefficients are unconstrained (X never wraps), which is
// what lets the desert stretch its dune noise anisotropically. Translations (constant
// offsets, domain-warp adds) never break tiling.
shader_type canvas_item;
render_mode blend_mix;

// Pixelation — square, native-pixel-aligned cells. `pixels` = cells across the WIDTH.
uniform float pixels : hint_range(0.0, 800.0) = 160.0;
uniform vec2 rect_size = vec2(480.0, 270.0);

// Feature density (noise cells across the screen), decoupled from `size` (the tiling period).
uniform float feature_scale : hint_range(2.0, 40.0) = 8.0;
uniform float size = 32.0;   // tiling period — MUST be integer for a seamless loop
uniform int OCTAVES : hint_range(1, 12) = 5;
uniform float seed : hint_range(1.0, 10.0) = 1.0;

// Vertical scroll offset (noise-cell units). Advanced + wrapped at round(size) in GD.
uniform float scroll = 0.0;

uniform int surface_type : hint_range(0, 5) = 0;
uniform vec4[8] colors : source_color;
// Sun direction — biases the coastline erosion (as light_origin did) AND the hillshade. This one IS
// the direction of the LIGHT (contrast building_shadow.gdshader's same-named uniform, which is the
// SHADOW direction). Always normalized before use, so only the direction matters. Default = the
// canonical 225° up-left scene light; flyover_backdrop.gd sets it from SceneLight.light_dir().
uniform vec2 sun_dir = vec2(-0.7071, -0.7071);
uniform float relief : hint_range(0.0, 1.0) = 0.35;
uniform float river_cutoff : hint_range(0.0, 1.0) = 0.5;
uniform float emissive : hint_range(0.0, 4.0) = 2.2;   // lava-channel HDR glow
uniform bool should_dither = true;


float rand(vec2 coord) {
	coord = mod(coord, vec2(2.0, 1.0) * round(size));
	return fract(sin(dot(coord.xy, vec2(12.9898, 78.233))) * 15.5453 * seed);
}

float noise(vec2 coord) {
	vec2 i = floor(coord);
	vec2 f = fract(coord);
	float a = rand(i);
	float b = rand(i + vec2(1.0, 0.0));
	float c = rand(i + vec2(0.0, 1.0));
	float d = rand(i + vec2(1.0, 1.0));
	vec2 cubic = f * f * (3.0 - 2.0 * f);
	return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

float fbm(vec2 coord) {
	float value = 0.0;
	float scl = 0.5;
	for (int i = 0; i < OCTAVES; i++) {
		value += noise(coord) * scl;
		coord *= 2.0;
		scl *= 0.5;
	}
	return value;
}

// Tileable circle-packing noise (Leukbaars, via the kit's Craters/Clouds), reworked after
// the "swiss cheese" pass. Three fixes over the naive port:
//  * CONTAINMENT — centre is jittered within [r, 1-r] so a circle can NEVER cross its cell
//    edge (the kit gets this by correlating centre+radius on one hash; a naive min-radius
//    broke it → circles clipped square at cell borders).
//  * SPARSITY — an existence hash skips ~40% of cells entirely (in the kit tiny-h cells get
//    radius ≈ 0, which is where its natural sparseness comes from).
//  * DECORRELATION — `salt` translates the hash lattice per layer. Two union layers offset
//    by +1 cell (the kit's `+(i+1)` trick) are the SAME field translated one cell diagonally
//    on a tiled lattice → every crater showed up twice as a diagonal pair.
float circle_noise(vec2 uv, vec2 salt) {
	vec2 c = floor(uv);
	vec2 f = fract(uv);
	float h = rand(c + salt);
	if (h < 0.4) { return 1.0; }              // sparse: this cell has no circle
	float r = (h - 0.4) * 0.4 + 0.08;         // radius 0.08..0.32
	vec2 jit = vec2(rand(c + salt + vec2(53.0, 11.0)), rand(c + salt + vec2(31.0, 43.0)));
	// Containment pads for the edge wobble below (max +0.3r) — still can't clip the cell.
	float pad = r * 1.35;
	vec2 center = vec2(pad) + (1.0 - 2.0 * pad) * jit;
	float m = length(f - center);
	// Edge roughening, two frequencies: low (uv*3) varies the overall shape a little,
	// high (uv*8) breaks the rim line into ragged rock. Proportional to r (small craters
	// keep their shape) and positional, so the light-shifted resample wobbles coherently.
	// Low-freq amplitude kept SMALL — at ±0.35r it ovalized big craters into oblongs.
	m += (noise(uv * 3.0 + salt) - 0.5) * r * 0.2;
	m += (noise(uv * 8.0 + salt + vec2(41.0, 13.0)) - 0.5) * r * 0.25;
	// Wider edge ramp than the kit's 0.10r — the continuous gradient is what the
	// differential shading (crater_shade) turns into varying-width crescents and depth.
	return smoothstep(r - 0.25 * r, r, m);
}

// Crater depressions = union of two decorrelated circle-noise layers (different salts, so
// no translated-twin craters). ~0 outside craters, ~1 inside. Overlaps FUSE into compound
// shapes — good for clustered pocks, but at big scales the fused peanuts read as weird
// oblong blobs, so the large generations use the single-layer field below instead.
float crater_field(vec2 uv, vec2 salt) {
	float c = circle_noise(uv, salt) * circle_noise(uv, salt + vec2(23.0, 17.0));
	return 1.0 - c;
}

// ── Asteroid-surface craters (kit-faithful) ────────────────────────────────
// The kit asteroid has NO existence gate: EVERY cell rolls a circle with r = h*0.25 —
// most come out tiny (near-invisible), a few big. That radius spread IS its density and
// size-variety model. Kept from our tiled-lattice fixes: per-layer salts (no translated
// twins), containment (no square clipping), positional edge wobble (rough rims).
// size_mult scales the whole roll (the Water slider: crater size/coverage).
float circle_noise_ast(vec2 uv, vec2 salt, float size_mult) {
	vec2 c = floor(uv);
	vec2 f = fract(uv);
	float h = rand(c + salt);
	float r = min(h * 0.3 * size_mult, 0.36);
	if (r < 0.02) { return 1.0; }
	vec2 jit = vec2(rand(c + salt + vec2(53.0, 11.0)), rand(c + salt + vec2(31.0, 43.0)));
	float pad = r * 1.3;
	vec2 center = vec2(pad) + (1.0 - 2.0 * pad) * jit;
	float m = length(f - center);
	m += (noise(uv * 6.0 + salt) - 0.5) * r * 0.4;
	return smoothstep(r - 0.15 * r, r, m);
}

// The kit's crater(): union of two circle layers (decorrelated by salt, not by the +1-cell
// translate that twins on a tiled lattice). ~0 outside, →1 inside.
float crater_field_ast(vec2 uv, vec2 salt, float size_mult) {
	float c = circle_noise_ast(uv, salt, size_mult)
			* circle_noise_ast(uv, salt + vec2(23.0, 17.0), size_mult);
	return 1.0 - c;
}

// Flat directional hillshade from the fbm height field. Positive = slope faces the sun.
// Replaces the sphere's radial d_light so the flat surface still reads as lit terrain.
float hillshade(vec2 coord) {
	float e = 0.7;
	float hx = fbm(coord + vec2(e, 0.0)) - fbm(coord - vec2(e, 0.0));
	float hy = fbm(coord + vec2(0.0, e)) - fbm(coord - vec2(0.0, e));
	vec2 sd = normalize(sun_dir + vec2(0.0001));
	return clamp(-(hx * sd.x + hy * sd.y) * 6.0, -1.0, 1.0);
}

// Posterize v (0..1+) into 0..n-1.
int band(float v, int n) {
	return clamp(int(floor(clamp(v, 0.0, 0.999) * float(n))), 0, n - 1);
}

// Expand the fbm height (values cluster near 0.5) to the full 0..1 range so posterized
// bands cover roughly equal area. The kit got this spread for free from d_light; on a flat
// surface we remap explicitly, else the whole surface collapses into one band.
float elev01(float f) {
	return clamp((f - 0.30) / 0.40, 0.0, 1.0);
}

// S-curve contrast on a 0..1 height — pushes values off fbm's mushy mid-range so peaks and
// basins commit to their bands (the Planet Coffee shader shapes its height the same way,
// via 0.4v³+v²+0.5v; smoothstep is the cheap equivalent).
float shape(float v) {
	return v * v * (3.0 - 2.0 * v);
}

// Elevation field = base fbm + an INDEPENDENTLY-OFFSET detail fbm at 3× frequency (the
// animated-pixel-art-planet shader combines primary/secondary/tertiary noise layers this
// way — separate layers break the self-similar mush plain fbm octaves settle into),
// spread + shaped. 3 is an integer coeff → loop-safe.
float elevation(vec2 coord) {
	float e = fbm(coord) * 0.72 + fbm(coord * 3.0 + vec2(9.0, 4.0)) * 0.28;
	return shape(elev01(e));
}

// 3-level QUANTISED directional lighting, dithered at the transitions — the pixel-art
// planet shader's "Quantised" light mode. Applied AFTER the palette pick so every surface
// shades consistently: lit slopes step brighter, lee slopes darker, ±15% keeps the result
// reading as the same palette entry.
vec3 apply_light(vec3 col, float sun, bool dith) {
	// relief * 2.7: slider 0 = genuinely flat (mix(0.6,...) kept phantom shading at zero),
	// default 0.35 ≈ the old strength.
	float l = sun * relief * 2.7;
	float lit = 0.0;
	// NARROW dither band (0.26..0.30): a wide band put huge smoothly-shaded regions into
	// the checkerboard zone and carpeted whole surfaces in speckle (Roman's ice feedback).
	if (l > 0.30 || (l > 0.26 && should_dither && dith)) { lit = 1.0; }
	else if (l < -0.30 || (l < -0.26 && should_dither && dith)) { lit = -1.0; }
	return col * (1.0 + lit * 0.15);
}


// 0 — continents as a proper BIOME LADDER (the 2d-procedural-terrain shader's recipe):
// one warped elevation field classified through NON-UNIFORM thresholds — the thin sand
// band is what makes coastlines read, the thin snow band caps only the highest peaks.
// Coastline character comes from domain-warping the elevation input (the Planet Coffee /
// IQ trick: warp by a vector built from two offset fbm samples) — fjords and peninsulas
// instead of round noise blobs. Rivers carve land in the water colours.
// Colours: [0] deep sea, [1] sea, [2] shallows, [3] sand, [4] grass, [5] forest,
// [6] mountain, [7] snow.
vec3 surf_terran(vec2 coord, float sun, bool dith, out float emis) {
	emis = 0.0;
	vec2 w = vec2(fbm(coord + vec2(5.0, 1.0)), fbm(coord + vec2(1.0, 7.0)));
	vec2 wc = coord + (w - 0.5) * 1.3;            // warped coords (bounded offset → tiles)
	float e = elevation(wc);
	if (should_dither && dith) { e += 0.02; }     // dithered band edges (kit coastline dither)
	// The Water slider IS the sea level. Water bands scale with the water span and land
	// bands with the land span, so lowering the slider makes the ocean RECEDE and turn
	// shallow-dominated (deep water shrinks fastest), raising it drowns the lowlands.
	float sl = river_cutoff;
	float land = max(1.0 - sl, 0.001);
	vec3 col = colors[0].rgb;                     // deep sea
	if (e > sl * 0.58) col = colors[1].rgb;       // sea
	if (e > sl * 0.85) col = colors[2].rgb;       // shallows
	if (e > sl)        col = colors[3].rgb;       // sand — THIN: the coastline ring
	if (e > sl + land * 0.08) col = colors[4].rgb;  // grass
	if (e > sl + land * 0.37) col = colors[5].rgb;  // forest
	if (e > sl + land * 0.62) col = colors[6].rgb;  // mountain
	if (e > sl + land * 0.83) col = colors[7].rgb;  // snow caps
	// Rivers: the kit's warped-fbm channels, drawn in the water colours, land only.
	if (e > sl + land * 0.08 && fbm(wc + e * 6.0) < sl * 0.5) col = colors[2].rgb;
	return apply_light(col, sun, dith);
}

// 1 — dune sea. DryTerran's posterize relied on the sphere's radial light for structure;
// flat needs actual DUNES: an X-stretched fbm (ridges elongated across the screen) shaded
// by its own vertical offset difference (slip faces — bright windward, dark lee), riding
// on the large posterized undulation. X coeff is free (no horizontal wrap); only the Y
// coefficient must stay on the half-integer lattice for the loop.
// Sahara-satellite recipe (Roman's reference photos): the sand sea is LINEAR dunes — long
// parallel wavy ridge LINES that branch and merge like a fingerprint — made by folding a
// horizontal ramp into rows (fract) after warping it with fbm: where the warp gradient
// fights the ramp, rows split into Y-junctions exactly like real longitudinal dunes.
// A low-freq mask fades the ridges out entirely in places → smooth featureless sand
// corridors (photo 3). High ground = near-black rocky MASSIFS veined by pale sand-filled
// wadis (dendritic channels, photo 1); lowest basins = pale playa/salt flats.
// Colours: [0] deep shadow sand, [1] lee shadow, [2] base sand, [3] bright flank,
// [4] sunlit crest, [5] massif rock (near-black), [6] wadi vein (pale), [7] playa.
vec3 surf_desert(vec2 coord, float sun, bool dith, out float emis) {
	emis = 0.0;
	vec2 w = vec2(fbm(coord + vec2(3.0, 9.0)), fbm(coord + vec2(8.0, 2.0)));
	vec2 wc = coord + (w - 0.5) * 1.1;
	float e = elevation(wc);
	if (should_dither && dith) { e += 0.02; }
	// Sand↔rock balance rides the Water/lava slider: up = more exposed massif.
	float rock_th = 1.02 - river_cutoff * 0.55;
	vec3 col;
	if (e > rock_th) {
		// Massif: TWO rock tones banded by their own noise (internal structure, not a
		// flat blob) + dendritic pale veins (sand-filled wadis).
		float rt = fbm(wc * 3.0 + vec2(14.0, 5.0));
		col = (rt > 0.52) ? colors[5].rgb : colors[0].rgb;
		float vz = fbm(wc * 3.0 + vec2(6.0, 15.0));
		float vein = smoothstep(0.465, 0.5, vz) - smoothstep(0.5, 0.535, vz);
		if (vein > 0.25) col = colors[6].rgb;
	} else if (e < 0.20) {
		col = colors[7].rgb;                          // playa / salt flat — smooth and pale
	} else {
		// The dune sea. Ripples FADE IN with the mask (rs): smooth sand → faint sparse
		// rows → full ripple field — a gradient, not an on/off border. The rs-scaled
		// thresholds also soften the field overall (fewer crest/shadow pixels).
		float rs = smoothstep(0.30, 0.62, fbm(wc + vec2(21.0, 4.0)));
		col = (e > 0.55) ? colors[3].rgb : colors[2].rgb;
		if (rs > 0.03) {
			float t = coord.y * 2.0 + (fbm(wc * 2.0 + vec2(12.0, 8.0)) - 0.5) * 1.7;
			float tri = abs(fract(t) - 0.5) * 2.0;
			if (tri < 0.16 * rs) col = colors[4].rgb;          // sunlit crest line
			else if (tri < 0.42 * rs) col = colors[3].rgb;     // bright windward flank
			if (tri > 1.0 - 0.14 * rs) col = colors[1].rgb;    // slip-face shadow line
		}
	}
	return apply_light(col, sun, dith);
}

// 2 — ice sheets + frozen lakes + pressure cracks. The kit's IceWorld stacks a Lakes layer
// over the pale land: a SECOND thresholded fbm (`step(lake_cutoff, lake)`) in darker blue
// tones — that irregular dark-lake patchwork is the world's signature, not the bands alone.
// Colours: [1..3] ice dark→bright, [4] lake shelf, [5] lake deep, [0] crack.
// Macro structure (the terran lesson): ONE warped elevation drives everything — frozen
// leads/lakes are the LOW basins of the same field (not an unrelated overlay blob field),
// so lakes sit naturally between floe-shaped ice sheets with warped shorelines. Pressure
// ridges crack the land at two scales (Europa linae). river_cutoff shifts the waterline.
// Colours: [0] crack, [1..3] ice dark→bright, [4] lake shelf, [5] lake deep.
vec3 surf_ice(vec2 coord, float sun, bool dith, out float emis) {
	emis = 0.0;
	vec2 w = vec2(fbm(coord + vec2(7.0, 3.0)), fbm(coord + vec2(2.0, 11.0)));
	vec2 wc = coord + (w - 0.5) * 1.2;
	float e = elevation(wc);
	if (should_dither && dith) { e += 0.02; }
	// The river_cutoff slider IS the water amount: waterline sweeps ~0.18 (scattered
	// ponds) → ~0.72 (mostly ocean). Land bands are PROPORTIONAL to the remaining land
	// span, so dark ice / bright ice / snow keep their ratio at any water level.
	float wl = river_cutoff * 0.9;
	float land = max(1.0 - wl, 0.001);
	vec3 col = colors[1].rgb;                      // deep ice sheet
	if (e > wl + land * 0.35) col = colors[2].rgb; // mid sheet
	if (e > wl + land * 0.62) col = colors[3].rgb; // bright highland ice / snow
	if (e < wl) col = colors[4].rgb;               // frozen lake shelf
	if (e < wl - 0.08) col = colors[5].rgb;        // deep lead
	// Pressure-ridge cracks, land only, ONE scale, cluster-gated. The old second scale
	// (wc*6, razor band) fragmented into isolated dark-blue pixels that flickered as the
	// ground scrolled — the same speckle failure as the lava fissures. One lower-frequency
	// scale with a wider band reads as connected linae; the mask groups them in families.
	if (e >= wl) {
		float pm = fbm(wc + vec2(17.0, 23.0));
		if (pm > 0.48) {
			float cr1 = fbm(wc * 3.0 + e * 2.0);
			float crack = smoothstep(0.465, 0.5, cr1) - smoothstep(0.5, 0.535, cr1);
			if (crack > 0.2) col = colors[0].rgb;
		}
	}
	return apply_light(col, sun, dith);
}

// 3 — the kit's LavaWorld is THREE stacked generators: NoAtmosphere rock (3 dark tiers) +
// a sparse Craters layer at ~1/3 the land frequency + Rivers with a 3-TONE lava gradient
// (dark-red edge → red → orange core). Colours: [0..2] rock dark→light, [3] lava edge,
// [4] lava mid, [5] lava core (emissive).
// Macro structure (the terran lesson): warped rock tiers with the lava CONCENTRATED in
// the low basins, plus two new heat features — a thin glowing FISSURE network cracking
// the high rock (ember veins), and heat-glow on rock adjacent to a channel (the bank
// catches the light of the lava beside it). Colours: [0..2] rock dark→light, [3] lava
// edge, [4] lava mid, [5] lava core.
vec3 surf_lava(vec2 coord, float sun, bool dith, out float emis) {
	emis = 0.0;
	vec2 w = vec2(fbm(coord + vec2(4.0, 6.0)), fbm(coord + vec2(10.0, 1.0)));
	vec2 wc = coord + (w - 0.5) * 1.1;
	float e = elevation(wc);
	if (should_dither && dith) { e += 0.02; }
	vec3 col = colors[0].rgb;                      // low basalt plains
	if (e > 0.35) col = colors[1].rgb;             // mid rock
	if (e > 0.70) col = colors[2].rgb;             // high ridges
	// Sparse dark craters (LavaWorld stacks Craters size 3.5 under its rivers).
	float c1 = crater_field(coord * 0.5, vec2(47.0, 3.0));
	if (c1 > 0.4) col = colors[0].rgb;
	// Sun-shade the ROCK only — everything molten below is self-luminous.
	col = apply_light(col, sun, dith);
	// Molten rivers pool in the basins: channel strength grows as elevation drops, so
	// lava concentrates low with warped shorelines instead of cutting ridges uniformly.
	float rn = fbm(wc + e * 2.5) + e * 0.35;
	float channel = river_cutoff - rn + 0.18;
	if (channel > 0.0) {
		float heat = channel / max(river_cutoff, 0.001);
		col = colors[3].rgb;                       // cooling edge
		if (heat > 0.14) col = colors[4].rgb;      // flowing
		if (heat > 0.34) col = colors[5].rgb;      // molten core
		emis = emissive * (0.3 + 1.2 * min(heat, 1.0));
	} else if (channel > -0.05) {
		col = mix(col, colors[3].rgb, 0.5);        // bank glow — rock lit by the lava beside it
		emis = emissive * 0.15;
	} else {
		// Ember fissures: patch-gated, LOWER frequency + wider band so they read as
		// connected glowing cracks — at wc*4 with a razor band they degenerated into
		// scattered single orange pixels (Roman's screenshot).
		float pm = fbm(wc + vec2(23.0, 7.0));
		if (pm > 0.55) {
			float fz = fbm(wc * 2.0 + vec2(17.0, 9.0));
			float vein = smoothstep(0.47, 0.5, fz) - smoothstep(0.5, 0.53, fz);
			if (vein > 0.3) {
				col = colors[4].rgb;
				emis = emissive * 0.4;
			}
		}
	}
	return col;
}

// 4 — barren cratered surface: a STRAIGHT flat port of the kit's Asteroids.gdshader.
// (Two structured-crater rebuilds were scrubbed — this is the kit's recipe verbatim.)
// Its entire look is three ingredients, nothing else:
//   1. 3-tone relief: two fbm samples, one shifted toward the sun; their difference picks
//      dark/mid/light through the kit's dithered double-thresholds (±0.05 / ±0.03).
//   2. Crater interiors RESET to the mid tone — punching clean holes through the relief
//      mottling is what makes craters read on the busy surface.
//   3. A bare `c2 < c1` light crescent from a slightly sun-shifted crater resample.
// Two lattices of the same treatment: the kit's own scale + a 0.25-freq one for big
// craters (small overprint big). Relief slider scales the sun offset (0 = flat; default
// 0.35 ≈ the kit's 0.5). Water slider scales the crater size roll (coverage).
// Colours (kit's 3-tone): [0] dark, [1] mid/base, [2] light.
vec3 surf_moon(vec2 coord, float sun, bool dith, out float emis) {
	emis = 0.0;
	vec2 sdir = normalize(sun_dir + vec2(0.0001));
	float n = fbm(coord);
	float n2 = fbm(coord + sdir * relief * 1.4);
	float noise_rel = n2 - n;
	vec3 col = colors[1].rgb;
	if (noise_rel < -0.06 || (noise_rel < -0.04 && should_dither && dith)) { col = colors[0].rgb; }
	if (noise_rel > 0.05 || (noise_rel > 0.03 && should_dither && dith)) { col = colors[2].rgb; }
	float size_mult = 0.5 + river_cutoff;
	// Big craters first, kit-scale second — the small ones overprint the big floors.
	float b1 = crater_field_ast(coord * 0.25, vec2(61.0, 7.0), size_mult);
	float b2 = crater_field_ast(coord * 0.25 + sdir * 0.04, vec2(61.0, 7.0), size_mult);
	if (b1 > 0.4) { col = colors[1].rgb; }
	if (b2 < b1) { col = colors[2].rgb; }
	float c1 = crater_field_ast(coord, vec2(0.0), size_mult);
	float c2 = crater_field_ast(coord + sdir * 0.05, vec2(0.0), size_mult);
	if (c1 > 0.4) { col = colors[1].rgb; }
	if (c2 < c1) { col = colors[2].rgb; }
	return col;
}

// 5 — MOONSTEROID: the kit asteroid EXACTLY — relief + ONE crater lattice at the noise
// frequency, nothing added (no second big-crater lattice; that's the surf_moon delta).
vec3 surf_moonsteroid(vec2 coord, float sun, bool dith, out float emis) {
	emis = 0.0;
	vec2 sdir = normalize(sun_dir + vec2(0.0001));
	float n = fbm(coord);
	float n2 = fbm(coord + sdir * relief * 1.4);
	float noise_rel = n2 - n;
	vec3 col = colors[1].rgb;
	if (noise_rel < -0.06 || (noise_rel < -0.04 && should_dither && dith)) { col = colors[0].rgb; }
	if (noise_rel > 0.05 || (noise_rel > 0.03 && should_dither && dith)) { col = colors[2].rgb; }
	float size_mult = 0.5 + river_cutoff;
	float c1 = crater_field_ast(coord, vec2(0.0), size_mult);
	float c2 = crater_field_ast(coord + sdir * 0.05, vec2(0.0), size_mult);
	if (c1 > 0.4) { col = colors[1].rgb; }
	if (c2 < c1) { col = colors[2].rgb; }
	return col;
}



void fragment() {
	// Square, native-pixel-aligned pixelation + the screen-space dither cell parity.
	vec2 uv = UV;
	vec2 cell = floor(UV * rect_size);
	if (pixels > 1.0) {
		float chunk = max(1.0, round(rect_size.x / pixels));
		cell = floor(floor(UV * rect_size) / chunk);
		uv = (cell * chunk) / rect_size;
	}
	bool dith = mod(cell.x + cell.y, 2.0) < 1.0;

	// Aspect-correct X so features stay round on the 16:9 rect; X never wraps.
	float aspect = rect_size.x / rect_size.y;
	vec2 coord = vec2(uv.x * aspect, uv.y) * feature_scale;
	coord.y -= scroll;   // fly the surface toward the viewer (down-screen)

	float sun = hillshade(coord);
	float emis = 0.0;
	vec3 col;
	if (surface_type == 1) col = surf_desert(coord, sun, dith, emis);
	else if (surface_type == 2) col = surf_ice(coord, sun, dith, emis);
	else if (surface_type == 3) col = surf_lava(coord, sun, dith, emis);
	else if (surface_type == 4) col = surf_moon(coord, sun, dith, emis);
	else if (surface_type == 5) col = surf_moonsteroid(coord, sun, dith, emis);
	else col = surf_terran(coord, sun, dith, emis);

	COLOR = vec4(col * (1.0 + emis), 1.0);
}
