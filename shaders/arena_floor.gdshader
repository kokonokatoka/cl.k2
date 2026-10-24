shader_type spatial;

// アリーナの床。暗い地面に、細いグリッドと 5m ごとの太い線。線はわずかに光る。
uniform vec3 base_color : source_color = vec3(0.065, 0.075, 0.1);
uniform vec3 line_color : source_color = vec3(0.14, 0.18, 0.26);
uniform vec3 major_color : source_color = vec3(0.22, 0.38, 0.52);
uniform float cell_size = 1.0;
uniform float major_every = 5.0;
uniform float line_width = 0.035;
uniform float major_width = 0.07;

varying vec3 world_pos;

float grid_line(vec2 p, float spacing, float width) {
	vec2 to_line = abs(fract(p / spacing + 0.5) - 0.5) * spacing;
	return 1.0 - smoothstep(width * 0.5, width * 0.5 + 0.02, min(to_line.x, to_line.y));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float minor = grid_line(world_pos.xz, cell_size, line_width);
	float major = grid_line(world_pos.xz, cell_size * major_every, major_width);
	vec3 color = mix(base_color, line_color, minor);
	color = mix(color, major_color, major);
	ALBEDO = color;
	ROUGHNESS = 0.9;
	EMISSION = line_color * minor * 0.25 + major_color * major * 0.45;
}
