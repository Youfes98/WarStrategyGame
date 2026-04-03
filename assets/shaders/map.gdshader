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
uniform sampler2D detail_tex : filter_linear, repeat_enable;
uniform bool has_detail = false;

uniform float terrain_blend = 0.42;
uniform float elevation_strength = 8.0;
uniform float coast_glow_str = 0.18;
uniform float noise_str = 0.025;
uniform float detail_strength = 0.08;
uniform float province_border_str = 0.20;
uniform float country_border_str = 0.55;

// Decode province index from RGB
int rgb_to_index(vec3 c) {
    return int(c.r * 255.0 + 0.5) * 65536 + int(c.g * 255.0 + 0.5) * 256 + int(c.b * 255.0 + 0.5);
}

void fragment() {
    vec2 px = tex_pixel_size;
    vec3 det = texture(province_tex, UV).rgb;
    int idx = rgb_to_index(det);

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

        if (has_detail) {
            float d1 = texture(detail_tex, UV * 200.0).r - 0.5;
            float d2 = texture(detail_tex, UV * 80.0).r - 0.5;
            float d3 = texture(detail_tex, UV * 30.0).r - 0.5;
            float detail = d1 * 0.5 + d2 * 0.3 + d3 * 0.2;
            col += vec3(detail) * detail_strength;
        }

        // ── Anti-aliased border detection ────────────────────────────────
        // 8 neighbors in a ring for smooth coverage of diagonals
        vec2 offsets[8] = vec2[](
            vec2(-1.0, -1.0), vec2( 0.0, -1.0), vec2( 1.0, -1.0),
            vec2(-1.0,  0.0),                     vec2( 1.0,  0.0),
            vec2(-1.0,  1.0), vec2( 0.0,  1.0), vec2( 1.0,  1.0)
        );

        float province_diff = 0.0;
        float country_diff = 0.0;
        float coast_count = 0.0;
        float my_c = texture(country_lut, vec2(u_idx, 0.5)).r;

        for (int i = 0; i < 8; i++) {
            vec3 nb = texture(province_tex, UV + offsets[i] * px).rgb;
            float is_diff = step(0.004, distance(det, nb));
            province_diff += is_diff;

            int nb_idx = rgb_to_index(nb);

            // Coast detection: neighbor is ocean
            if (nb_idx == 0) {
                coast_count += 1.0;
            }

            // Country border detection: neighbor belongs to a different country
            if (is_diff > 0.5 && nb_idx > 0) {
                float nb_c = texture(country_lut, vec2((float(nb_idx) + 0.5) / lut_size, 0.5)).r;
                country_diff += step(0.002, abs(nb_c - my_c));
            }
        }

        // Coast glow (soft blend based on how many neighbors are ocean)
        if (coast_count > 0.5) {
            col += vec3(0.35, 0.55, 0.85) * coast_glow_str * smoothstep(0.5, 3.0, coast_count);
        }

        // Soft color blend at province edges
        if (province_diff > 0.5) {
            float blend_weight = smoothstep(0.5, 4.0, province_diff) * 0.35;
            vec3 avg_neighbor = vec3(0.0);
            float neighbor_count = 0.0;
            for (int i = 0; i < 8; i++) {
                vec3 nb2 = texture(province_tex, UV + offsets[i] * px).rgb;
                int nb2_idx = rgb_to_index(nb2);
                if (nb2_idx > 0 && nb2_idx != idx) {
                    float nb2_u = (float(nb2_idx) + 0.5) / lut_size;
                    avg_neighbor += texture(color_lut, vec2(nb2_u, 0.5)).rgb;
                    neighbor_count += 1.0;
                }
            }
            if (neighbor_count > 0.5) {
                avg_neighbor /= neighbor_count;
                col = mix(col, avg_neighbor, blend_weight);
            }
        }

        // Border rendering with smooth falloff
        if (province_diff > 0.5) {
            float is_country_border = step(0.5, country_diff);
            float strength = mix(province_border_str, country_border_str, is_country_border);
            // smoothstep: 1-2 neighbors different = light edge, 3+ = full border
            float edge_alpha = smoothstep(0.5, 3.0, province_diff);
            col = mix(col, vec3(0.0), strength * edge_alpha);
        }
    }

    COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
