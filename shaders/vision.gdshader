shader_type canvas_item;

// 視界の中心（ColorRect の UV 座標）
uniform vec2 center = vec2(0.5, 0.5);
// 視界の半径（画面の高さ = 1.0 とした長さ）。x が横、y が縦。見下ろしカメラでは地面の円が楕円に見えるので別々に持つ。
// 0 で真っ暗
uniform vec2 radii = vec2(0.5, 0.4);
// 縁のぼかし幅（半径に対する割合）
uniform float softness = 0.22;
// 画面の横幅 / 高さ
uniform float aspect = 1.7778;
// 視界の内側に重ねる色（アルファ = 強さ）
uniform vec4 tint : source_color = vec4(0.0);
// 暗闇の濃さ（1 で真っ暗）
uniform float darkness_amount = 1.0;

void fragment() {
	vec2 offset = UV - center;
	offset.x *= aspect;
	float d = length(offset / max(radii, vec2(0.0001)));
	float darkness = smoothstep(1.0 - softness, 1.0, d) * darkness_amount;
	COLOR = mix(tint, vec4(0.0, 0.0, 0.0, 1.0), darkness);
}
