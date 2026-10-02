shader_type canvas_item;

// Wall fill around the kitchen art. The fine texture (mottled paint and its
// halftone dots) comes from a plain wall patch of the art itself, high-passed
// (patch minus its own blur) and tiled with mirrored repeat. The slow tone comes
// from the art's own edge colors, so the fill continues the picture's color at
// the join. Near the join the fill fades out over the art's own edge.

uniform sampler2D patch : filter_linear_mipmap, repeat_disable;
uniform sampler2D patch_blur : filter_linear_mipmap, repeat_disable;
uniform sampler2D tone_left : filter_linear, repeat_disable;
uniform sampler2D tone_right : filter_linear, repeat_disable;
uniform sampler2D tone_top : filter_linear, repeat_disable;
uniform vec2 tile_size = vec2(300.0, 420.0);
// The art rectangle (x, y, width, height), in the node's local coordinates.
uniform vec4 inner = vec4(0.0, 0.0, 1176.0, 902.0);
uniform float feather = 20.0;
uniform float detail_gain = 1.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

vec2 mirrored(vec2 t) {
	return 1.0 - abs(1.0 - mod(t, 2.0));
}

void fragment() {
	vec2 rel = local_pos - inner.xy;
	vec2 uv = mirrored(rel / tile_size);
	vec3 detail = texture(patch, uv).rgb - texture(patch_blur, uv).rgb;
	float across = clamp(rel.x / inner.z, 0.0, 1.0);
	float down = clamp(rel.y / inner.w, 0.0, 1.0);
	vec3 tone_t = texture(tone_top, vec2(across, 0.5)).rgb;
	vec3 tone_l = texture(tone_left, vec2(0.5, down)).rgb;
	vec3 tone;
	if (rel.x >= inner.z) {
		tone = texture(tone_right, vec2(0.5, down)).rgb;
	} else if (rel.y < 0.0) {
		tone = tone_t;
	} else if (rel.x < 0.0) {
		tone = tone_l;
	} else {
		tone = rel.y < rel.x ? tone_t : tone_l;
	}
	// How far into the art (from its left or top edge) this pixel lies.
	float depth = (rel.x > 0.0 && rel.y > 0.0 && rel.x < inner.z) ? min(rel.x, rel.y) : -1.0;
	float alpha = depth > 0.0 ? 1.0 - smoothstep(0.0, feather, depth) : 1.0;
	// COLOR arrives as the node's modulate (the dimming of the backdrop).
	COLOR = vec4(clamp(tone + detail * detail_gain, 0.0, 1.0) * COLOR.rgb, alpha * COLOR.a);
}
