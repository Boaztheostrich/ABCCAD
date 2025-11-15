shader_type spatial;

uniform vec4 face_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

uniform float edge_thickness = 0.02;

void fragment() {
    // Don't render backfaces at all
    if (!FRONT_FACING) {
        discard;
    }

    vec3 p = abs(VERTEX);

    float dx = min(p.x, 0.5 - p.x);
    float dy = min(p.y, 0.5 - p.y);
    float dz = min(p.z, 0.5 - p.z);

    bool edge =
        (dx < edge_thickness && dy < edge_thickness) ||
        (dx < edge_thickness && dz < edge_thickness) ||
        (dy < edge_thickness && dz < edge_thickness);

    ALBEDO = edge ? edge_color.rgb : face_color.rgb;
}
