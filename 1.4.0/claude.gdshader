shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always;

uniform sampler2D albedo_texture : source_color, filter_linear; // Changed to linear
uniform vec4 replace_color : source_color = vec4(0.0, 0.5, 1.0, 1.0);
uniform float threshold : hint_range(0.0, 1.0) = 0.1;
uniform vec3 uv1_scale = vec3(3.0, 2.0, 1.0);
uniform float edge_smoothness : hint_range(0.0, 0.1) = 0.02; // New parameter

void fragment() {
    vec2 scaled_uv = UV * uv1_scale.xy;
    vec4 tex = texture(albedo_texture, scaled_uv);
    
    float brightness = (tex.r + tex.g + tex.b) / 3.0;
    
    // Smooth transition instead of hard cutoff
    float edge = smoothstep(threshold - edge_smoothness, threshold + edge_smoothness, brightness);
    
    ALBEDO = mix(vec3(0.0, 0.0, 0.0), replace_color.rgb, edge);
    ALPHA = tex.a;
}