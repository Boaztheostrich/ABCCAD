shader_type spatial;
render_mode unshaded;

// Color you want the outline/mask to render as
uniform vec4 mask_color : source_color = vec4(0.0, 0.4, 1.0, 1.0); // blue

// Drag-and-drop your edge.png here
uniform sampler2D edge_mask : source_color, repeat_enable;

// UV1 scale — NO RANGE HINT (because it's a vec2/vec3)
uniform vec3 uv1_scale = vec3(3.0, 2.0, 1.0);

void fragment() {
	// Apply mask texture using UV1, scaled
	vec2 uv = UV * uv1_scale.xy;

	vec4 mask = texture(edge_mask, uv);

	// Only show the mask (multiply by incoming alpha)
	ALBEDO = mask_color.rgb;
	ALPHA = mask.r; // or mask.a depending on your texture
}
