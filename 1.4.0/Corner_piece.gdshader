shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always;

void fragment() {
    ALBEDO = vec3(UV, 0.0); // R = U, G = V
}