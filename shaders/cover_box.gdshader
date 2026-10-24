shader_type spatial;

// 遮蔽物・壁の表面。側面の上端が光って、暗闇の中でも形が読み取れる。天面は控えめに色づく。
uniform vec3 base_color : source_color = vec3(0.16, 0.18, 0.23);
uniform vec3 rim_color : source_color = vec3(0.3, 0.8, 1.0);
// 箱の高さ（この付近が光る）
uniform float top = 1.8;
uniform float rim_width = 0.16;
uniform float rim_strength = 1.3;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float side = 1.0 - smoothstep(0.3, 0.7, world_normal.y);
	float top_face = smoothstep(0.7, 0.95, world_normal.y);
	float rim = smoothstep(top - rim_width, top - 0.005, world_pos.y) * side;
	// 床際は少し暗くして立体感を出す
	float base_shade = mix(0.6, 1.0, smoothstep(0.0, 1.4, world_pos.y));
	ALBEDO = base_color * base_shade + rim_color * top_face * 0.06;
	ROUGHNESS = 0.8;
	METALLIC = 0.1;
	EMISSION = rim_color * (rim * rim_strength + top_face * 0.1);
}
