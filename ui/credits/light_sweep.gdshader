shader_type canvas_item;
// A soft diagonal band of light that crosses the illustration. It only adds
// light where the art is opaque, so it never glows over the empty background.
uniform float sweep = -1.0;
uniform float band_width : hint_range(0.01, 0.5) = 0.16;
uniform float strength : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = (UV.x * 0.6 + (1.0 - UV.y) * 0.4) - sweep;
	float band = smoothstep(band_width, 0.0, abs(d));
	COLOR = vec4(c.rgb + vec3(band * strength), c.a);
}
