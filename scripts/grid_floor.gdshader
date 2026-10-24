shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.04, 0.05, 0.08, 1.0);
uniform vec4 sub_grid_color : source_color = vec4(0.08, 0.14, 0.22, 1.0);
uniform vec4 main_grid_color : source_color = vec4(0.0, 0.65, 0.95, 1.0);
uniform vec4 accent_color : source_color = vec4(1.0, 0.45, 0.0, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 pos, float scale, float thickness) {
	vec2 coord = pos * scale;
	vec2 grid = abs(fract(coord - 0.5) - 0.5) / fwidth(coord);
	float line = min(grid.x, grid.y);
	return 1.0 - min(line / thickness, 1.0);
}

void fragment() {
	vec2 xz = world_pos.xz;
	float dist = length(xz);
	
	// 1m サブグリッドと 4m メイングリッド
	float g_sub = grid_line(xz, 1.0, 1.2);
	float g_main = grid_line(xz, 0.25, 1.8);
	
	// 中央のサークルリング演出
	float ring1 = smoothstep(0.08, 0.0, abs(dist - 4.0));
	float ring2 = smoothstep(0.12, 0.0, abs(dist - 10.0));
	float pulse = 0.5 + 0.5 * sin(TIME * 2.5 - dist * 0.5);
	
	// 遠距離フェード
	float fade = clamp(1.0 - smoothstep(12.0, 28.0, dist), 0.0, 1.0);
	
	// チェッカーボード風の微細な明暗差
	vec2 cell = floor(xz * 0.5);
	float checker = mod(cell.x + cell.y, 2.0) * 0.015;
	
	vec3 col = base_color.rgb + vec3(checker);
	col = mix(col, sub_grid_color.rgb, g_sub * fade * 0.7);
	col = mix(col, main_grid_color.rgb, g_main * fade * 0.9);
	col += accent_color.rgb * ring1 * 0.8;
	col += main_grid_color.rgb * ring2 * (0.4 + 0.4 * pulse);
	
	ALBEDO = col;
	ROUGHNESS = mix(0.6, 0.2, g_main);
	METALLIC = 0.4;
	EMISSION = (main_grid_color.rgb * g_main * 0.35 + accent_color.rgb * ring1 * 0.6) * fade;
}
