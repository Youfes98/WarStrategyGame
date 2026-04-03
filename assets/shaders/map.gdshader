shader_type canvas_item;

uniform sampler2D province_tex : filter_nearest;
uniform sampler2D color_lut : filter_nearest;
uniform sampler2D country_lut : filter_nearest;
uniform float lut_size;
uniform vec2 tex_pixel_size;

uniform sampler2D terrain_tex : filter_linear;
uniform sampler2D heightmap_tex : filter_linear;
uniform sampler2D noise_tex : filter_linear;
uniform sampler2D detail_tex : filter_linear, repeat_enable;
uniform bool has_terrain = false;
uniform bool has_heightmap = false;
uniform bool has_noise = false;
uniform bool has_detail = false;

// Biome system: terrain_type_tex classifies pixels, biome_atlas has 6 tiles in a 3x2 grid
uniform sampler2D terrain_type_tex : filter_nearest;
uniform sampler2D biome_atlas : filter_linear;
uniform bool has_terrain_types = false;

uniform float terrain_blend = 0.68;
uniform float terrain_desat = 0.55;
uniform float elevation_strength = 6.0;
uniform float noise_str = 0.02;
uniform float detail_strength = 0.06;
uniform float biome_detail_strength = 0.25;
uniform float province_border_str = 0.14;
uniform float country_border_str = 0.52;
uniform float inner_darken = 0.06;
uniform vec3 ocean_deep = vec3(0.06, 0.12, 0.22);
uniform vec3 ocean_shallow = vec3(0.14, 0.26, 0.42);
uniform float coast_glow_str = 0.12;
uniform vec3 paper_tint = vec3(0.95, 0.92, 0.86);
uniform float paper_strength = 0.08;

int rgb_to_index(vec3 c) {
    return int(c.r * 255.0 + 0.5) * 65536 + int(c.g * 255.0 + 0.5) * 256 + int(c.b * 255.0 + 0.5);
}

void fragment() {
    vec2 px = tex_pixel_size;
    vec3 det = texture(province_tex, UV).rgb;
    int idx = rgb_to_index(det);
    vec3 col = vec3(0.0);

    vec2 offsets[8] = vec2[](
        vec2(-1.0,-1.0), vec2(0.0,-1.0), vec2(1.0,-1.0), vec2(-1.0,0.0),
        vec2(1.0,0.0), vec2(-1.0,1.0), vec2(0.0,1.0), vec2(1.0,1.0)
    );

    if (idx == 0) {
        // ── OCEAN ────────────────────────────────────────────────────────
        col = ocean_deep;
        if (has_terrain) {
            float lum = dot(texture(terrain_tex, UV).rgb, vec3(0.3, 0.5, 0.2));
            col = mix(ocean_deep, ocean_shallow, lum * 0.6);
        }
        if (has_heightmap) {
            col = mix(col, ocean_shallow, texture(heightmap_tex, UV).r * 0.2);
        }
        float land = 0.0;
        for (int i = 0; i < 8; i++) {
            if (rgb_to_index(texture(province_tex, UV + offsets[i] * px * 2.0).rgb) > 0) land += 1.0;
        }
        if (land > 0.0) {
            col = mix(col, ocean_shallow, land / 8.0 * 0.5);
            col += vec3(0.03, 0.05, 0.07) * (land / 8.0);
        }
        if (has_noise) col += (texture(noise_tex, UV * 40.0).rgb - vec3(0.5)) * 0.012;
        if (has_detail) col += vec3(texture(detail_tex, UV * 60.0).r - 0.5) * 0.018;
    } else {
        // ── LAND ─────────────────────────────────────────────────────────
        float u_idx = (float(idx) + 0.5) / lut_size;
        vec3 country_col = texture(color_lut, vec2(u_idx, 0.5)).rgb;
        col = country_col;

        // Terrain underlay
        if (has_terrain) {
            vec3 t = texture(terrain_tex, UV).rgb;
            float gray = dot(t, vec3(0.3, 0.5, 0.2));
            t = mix(vec3(gray), t, 1.0 - terrain_desat);
            col = mix(t, country_col, terrain_blend);
        }

        // Biome detail from atlas (3x2 grid: plains/forest/desert / mountain/tundra/jungle)
        if (has_terrain_types) {
            float ttype = texture(terrain_type_tex, UV).r * 255.0;
            int biome_idx = 0;
            if (ttype < 45.0)       biome_idx = 0;  // plains
            else if (ttype < 75.0)  biome_idx = 1;  // forest
            else if (ttype < 105.0) biome_idx = 2;  // desert
            else if (ttype < 135.0) biome_idx = 3;  // mountain
            else if (ttype < 165.0) biome_idx = 4;  // tundra
            else                    biome_idx = 5;  // jungle

            float tile_col = float(biome_idx % 3);
            float tile_row = float(biome_idx / 3);
            vec2 tiled_uv = fract(UV * 150.0);
            vec2 atlas_uv = vec2(
                (tile_col + tiled_uv.x) / 3.0,
                (tile_row + tiled_uv.y) / 2.0
            );
            vec3 biome_col = texture(biome_atlas, atlas_uv).rgb;
            float zoom_factor = clamp(1.0 - px.x * 4096.0, 0.0, 1.0);
            col = mix(col, mix(col, biome_col, biome_detail_strength), zoom_factor);
        }

        // Elevation shading
        if (has_heightmap) {
            float h = texture(heightmap_tex, UV).r;
            float hr = texture(heightmap_tex, UV + vec2(px.x * 3.0, 0.0)).r;
            float hd = texture(heightmap_tex, UV + vec2(0.0, px.y * 3.0)).r;
            col *= clamp(1.0 + ((h - hr) + (h - hd)) * 0.5 * elevation_strength, 0.75, 1.25);
        }

        if (has_noise) col += (texture(noise_tex, UV * 50.0).rgb - vec3(0.5)) * noise_str;

        if (has_detail) {
            float d1 = texture(detail_tex, UV * 200.0).r - 0.5;
            float d2 = texture(detail_tex, UV * 70.0).r - 0.5;
            float d3 = texture(detail_tex, UV * 25.0).r - 0.5;
            col += vec3(d1 * 0.5 + d2 * 0.3 + d3 * 0.2) * detail_strength;
        }

        // Paper tint
        float col_gray = dot(col, vec3(0.3, 0.5, 0.2));
        col = mix(col, mix(vec3(col_gray), col, 0.85) * paper_tint, paper_strength);

        // Coast darkening (keep in shader — vector borders don't handle coastlines)
        float coast = 0.0;
        for (int i = 0; i < 8; i++) {
            if (rgb_to_index(texture(province_tex, UV + offsets[i] * px).rgb) == 0) coast += 1.0;
        }
        if (coast > 0.5) {
            col = mix(col, col * 0.7, smoothstep(0.5, 4.0, coast) * coast_glow_str);
        }
        // Province/country borders rendered by vector BorderLayer (not shader)
    }

    COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
