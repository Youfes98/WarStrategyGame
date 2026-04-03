shader_type canvas_item;

uniform sampler2D province_tex : filter_nearest;
uniform sampler2D color_lut : filter_nearest;
uniform sampler2D country_lut : filter_nearest;
uniform float lut_size;
uniform vec2 tex_pixel_size;

uniform sampler2D terrain_tex : filter_linear;
uniform sampler2D heightmap_tex : filter_linear;
uniform sampler2D noise_tex : filter_linear;
uniform bool has_terrain = false;
uniform bool has_heightmap = false;
uniform bool has_noise = false;

uniform float terrain_blend = 0.42;
uniform float elevation_strength = 8.0;
uniform float coast_glow_str = 0.18;
uniform float noise_str = 0.025;
uniform float province_border_str = 0.20;
uniform float country_border_str = 0.55;

void fragment() {
	vec2 px = tex_pixel_size;
	vec3 det = texture(province_tex, UV).rgb;
	int idx = int(det.r * 255.0 + 0.5) * 65536 + int(det.g * 255.0 + 0.5) * 256 + int(det.b * 255.0 + 0.5);

	vec3 col = vec3(0.08, 0.18, 0.38);

	if (idx == 0) {
		if (has_terrain) {
			col = mix(texture(terrain_tex, UV).rgb, col, 0.25);
		}
	} else {
		float u_idx = (float(idx) + 0.5) / lut_size;
		vec3 country_col = texture(color_lut, vec2(u_idx, 0.5)).rgb;
		col = country_col;

		if (has_terrain) {
			vec3 t = texture(terrain_tex, UV).rgb;
			float g = dot(t, vec3(0.3, 0.5, 0.2));
			t = mix(vec3(g), t, 0.6);
			col = mix(t, country_col, terrain_blend);
		}

		if (has_heightmap) {
			float h = texture(heightmap_tex, UV).r;
			float hr = texture(heightmap_tex, UV + vec2(px.x * 3.0, 0.0)).r;
			float hd = texture(heightmap_tex, UV + vec2(0.0, px.y * 3.0)).r;
			col *= clamp(1.0 + ((h - hr) + (h - hd)) * 0.5 * elevation_strength, 0.72, 1.28);
		}

		if (has_noise) {
			col += (texture(noise_tex, UV * 50.0).rgb - vec3(0.5)) * noise_str;
		}

		vec3 dr = texture(province_tex, UV + vec2(px.x, 0.0)).rgb;
		vec3 dl = texture(province_tex, UV - vec2(px.x, 0.0)).rgb;
		vec3 du = texture(province_tex, UV - vec2(0.0, px.y)).rgb;
		vec3 dd = texture(province_tex, UV + vec2(0.0, px.y)).rgb;

		float er = step(0.004, distance(det, dr));
		float el = step(0.004, distance(det, dl));
		float eu = step(0.004, distance(det, du));
		float ed = step(0.004, distance(det, dd));
		float edge = er + el + eu + ed;

		int ir = int(dr.r * 255.0 + 0.5) * 65536 + int(dr.g * 255.0 + 0.5) * 256 + int(dr.b * 255.0 + 0.5);
		int il = int(dl.r * 255.0 + 0.5) * 65536 + int(dl.g * 255.0 + 0.5) * 256 + int(dl.b * 255.0 + 0.5);
		int iu = int(du.r * 255.0 + 0.5) * 65536 + int(du.g * 255.0 + 0.5) * 256 + int(du.b * 255.0 + 0.5);
		int id2 = int(dd.r * 255.0 + 0.5) * 65536 + int(dd.g * 255.0 + 0.5) * 256 + int(dd.b * 255.0 + 0.5);

		if (ir == 0 || il == 0 || iu == 0 || id2 == 0) {
			col += vec3(0.35, 0.55, 0.85) * coast_glow_str;
		}

		if (edge > 0.5) {
			float my_c = texture(country_lut, vec2(u_idx, 0.5)).r;
			float cd = 0.0;
			if (er > 0.5 && ir > 0) { cd += step(0.002, abs(texture(country_lut, vec2((float(ir) + 0.5) / lut_size, 0.5)).r - my_c)); }
			if (el > 0.5 && il > 0) { cd += step(0.002, abs(texture(country_lut, vec2((float(il) + 0.5) / lut_size, 0.5)).r - my_c)); }
			if (eu > 0.5 && iu > 0) { cd += step(0.002, abs(texture(country_lut, vec2((float(iu) + 0.5) / lut_size, 0.5)).r - my_c)); }
			if (ed > 0.5 && id2 > 0) { cd += step(0.002, abs(texture(country_lut, vec2((float(id2) + 0.5) / lut_size, 0.5)).r - my_c)); }

			float s = cd > 0.5 ? country_border_str : province_border_str;
			col = mix(col, vec3(0.0), s * smoothstep(0.5, 2.0, edge));
		}
	}

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
