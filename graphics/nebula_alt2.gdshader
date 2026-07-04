shader_type canvas_item;
render_mode blend_mix, unshaded;

// ALT nebula B — from https://godotshaders.com/shader/nebula-stars-clouds/ (CC0). Already Godot-4
// native; added an `alpha` knob for backdrop use. Needs a SEAMLESS noise texture in `noise_texture`
// (Shader Lab supplies a seamless NoiseTexture2D). Wired into Shader Lab → Nebula as an A/B alternate
// to nebula2.gdshader. (Roman 2026-06-12)

uniform bool stars_on = true;
uniform float timeScaleFactor = 0.04;
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform vec4 colour_muiltiplier : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 colour_muiltiplier2 : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float brightness : hint_range(0.0, 3.0, 0.01) = 1.0;
uniform float clouds_resolution : hint_range(0.0, 10.0, 0.01) = 3.0;
uniform float clouds_intesity : hint_range(-0.06, 0.0, 0.001) = 0.0;
uniform float waveyness : hint_range(0.0, 10.0, 0.01) = 0.5;
uniform float fragmentation : hint_range(0.0, 100.0, 0.01) = 7.0;
uniform float distortion : hint_range(0.0, 10.0, 0.01) = 0.5;
uniform float clouds_alpha : hint_range(0.4, 0.6, 0.01) = 0.5;
uniform float movement : hint_range(0.7, 1.3, 0.01) = 1.0;
uniform float blur : hint_range(0.0, 10.0, 0.01) = 1.4;
uniform float blur2 : hint_range(0.0, 0.01, 0.00001) = 0.01;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
// External parallax scroll (Nebula Lab / backdrop): shifts the cloud + star sampling so this
// screen-space nebula can drift downward WITH the parallax stack. 0 = static (original look).
uniform vec2 scroll_offset = vec2(0.0);

float localTime() {
	return TIME * timeScaleFactor;
}

mat2 makem2(float theta) {
	float c = cos(theta);
	float s = sin(theta);
	return mat2(vec2(c, -s), vec2(s, c));
}

float noise_x(vec2 x) {
	return texture(noise_texture, x * blur2).x;
}

float noise_y(vec2 y) {
	return texture(noise_texture, y * blur2).y;
}

vec2 gradn(vec2 p) {
	float ep = 0.09;
	float gradx = noise_x(vec2(p.x + ep, p.y)) - noise_x(vec2(p.x - ep, p.y));
	float grady = noise_y(vec2(p.x, p.y + ep)) - noise_y(vec2(p.x, p.y - ep));
	return vec2(gradx, grady);
}

float flow(vec2 p) {
	float z = 2.0;
	float rz = clouds_intesity;
	vec2 bp = p;
	for (float i = 1.0; i < 7.0; i += 1.0) {
		p += localTime() * 0.6;
		bp += localTime() * 5.9;
		vec2 gr = gradn(i * p * 0.34 + localTime() * 1.0);
		gr *= makem2(localTime() * 6.0 - (0.05 * p.x + 0.03 * p.y) * 90.0);
		p += gr * waveyness;
		rz += (sin(noise_x(p) * fragmentation) * distortion + clouds_alpha) / z;
		p = mix(bp, p, movement);
		z *= blur;
		p *= 2.0;
		bp *= 1.9;
	}
	return rz;
}

float rand2(vec2 st) {
	return fract(sin(dot(st.xy, vec2(12.9898, 72.233))) * 53758.5453123);
}

void fragment() {
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 fragCoord = FRAGCOORD.xy;
	fragCoord = vec2(fragCoord.x, fragCoord.y - resolution.y);
	vec2 p = fragCoord / resolution - 0.5;
	p.x *= resolution.x / resolution.y;
	p *= clouds_resolution;
	p += scroll_offset;   // parallax drift (cloud sampling)

	float red = 0.2 * sin(TIME * 0.1);
	float blue = 0.1;
	float green = 0.1;

	float rz = flow(p);
	vec3 col = vec3(red, blue, green) / rz;
	col = pow(max(col, vec3(0.0)), vec3(brightness));

	float stars = 0.0;
	vec2 star_uv = SCREEN_UV.xy + scroll_offset * 0.1;   // parallax drift (star field)
	if (rand2(star_uv / 20.0) > 0.995) {
		float r = rand2(star_uv);
		stars = r * (0.5 * sin(TIME * (r * 2.0) + 1000.0 * r) + 0.5);
	}

	vec4 c;
	if (stars_on) {
		c = vec4((col + stars) * colour_muiltiplier.rgb, 1.0) * colour_muiltiplier2;
	} else {
		c = vec4(col * colour_muiltiplier.rgb, 1.0) * colour_muiltiplier2;
	}
	COLOR = vec4(c.rgb, c.a * alpha);
}
