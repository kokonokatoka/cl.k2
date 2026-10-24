shader_type spatial;

// 動いていることが分かるように、ワールド座標に 1m 間隔のグリッド線を描く
uniform vec3 base_color : source_color = vec3(0.30, 0.32, 0.36);
uniform vec3 line_color : source_color = vec3(0.45, 0.48, 0.54);
uniform float cell_size = 1.0;
uniform float line_width = 0.04;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 to_line = abs(fract(world_pos.xz / cell_size + 0.5) - 0.5) * cell_size;
	float line = 1.0 - step(line_width * 0.5, min(to_line.x, to_line.y));
	ALBEDO = mix(base_color, line_color, line);
	ROUGHNESS = 0.9;
}
