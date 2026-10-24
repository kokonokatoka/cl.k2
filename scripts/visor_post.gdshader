shader_type canvas_item;

uniform float blind_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 player_screen_pos = vec2(0.5, 0.5);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV;
	vec2 aspect = vec2(16.0 / 9.0, 1.0);
	vec2 diff = (uv - player_screen_pos) * aspect;
	float dist = length(diff);
	
	// 微細なスキャンライン
	float scanline = sin(uv.y * 450.0 + TIME * 8.0) * 0.5 + 0.5;
	
	// 通常時の軽いタクティカルビネット
	float normal_vignette = smoothstep(0.65, 1.25, dist) * 0.42;
	vec3 normal_col = vec3(0.0, 0.05, 0.1);
	
	// 目パーツなし時（ブラインド・緊急センサーモード）
	// 中心のごく狭い範囲（dist < 0.22）だけうっすら見え、周囲は完全な暗闇＋デジタルノイズ
	float sonar_radius = mix(1.5, 0.24, blind_amount);
	float blind_mask = smoothstep(sonar_radius * 0.45, sonar_radius, dist);
	
	// 緊急ソナーの赤いパルスリング
	float sonar_wave = fract(dist * 2.5 - TIME * 1.2);
	float ring = smoothstep(0.92, 0.98, sonar_wave) * (1.0 - smoothstep(0.98, 1.0, sonar_wave));
	
	// デジタル砂嵐ノイズ
	float noise = hash(floor(uv * vec2(320.0, 180.0)) + vec2(floor(TIME * 24.0)));
	float glitch_line = step(0.985, hash(vec2(floor(uv.y * 60.0), floor(TIME * 15.0))));
	
	vec3 blind_col = vec3(0.02, 0.005, 0.01);
	blind_col += vec3(0.8, 0.1, 0.15) * ring * 0.28 * blind_mask;
	blind_col += vec3(0.35, 0.08, 0.1) * noise * 0.15 * blind_mask;
	blind_col += vec3(0.9, 0.15, 0.2) * glitch_line * 0.25;
	
	float final_alpha = mix(normal_vignette + scanline * 0.02, clamp(blind_mask * 0.97 + 0.15, 0.0, 0.985), blind_amount);
	vec3 final_rgb = mix(normal_col, blind_col, blind_amount);
	
	COLOR = vec4(final_rgb, final_alpha);
}
