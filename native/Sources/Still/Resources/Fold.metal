#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float angle;
    float workingAngle;
    float perspective;
    float frost;
    float shade;
    float fadeAngle;
    float aspect;
    float padding;
};
struct VertexOut { float4 position [[position]]; float2 uv; };

vertex VertexOut foldVertex(uint id [[vertex_id]]) {
    float2 vertices[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
    VertexOut out;
    out.position = float4(vertices[id], 0, 1);
    out.uv = float2((vertices[id].x + 1) * .5, (1 - vertices[id].y) * .5);
    return out;
}

fragment float4 foldFragment(VertexOut in [[stage_in]],
                             texture2d<float> picture [[texture(0)]],
                             constant Uniforms& t [[buffer(0)]]) {
    constexpr sampler samplePicture(coord::normalized, address::clamp_to_edge,
                                     filter::linear, mip_filter::linear);
    float2 uv = in.uv;
    float angle = clamp(t.angle, 0.0, t.workingAngle);
    float progress = clamp((t.workingAngle-angle)/(t.workingAngle-t.fadeAngle), 0.0, 1.0);
    float a = radians(angle);
    float w = radians(t.workingAngle);
    float3 eye = float3(0, 2.3, 2.6);
    float3 point = float3((uv.x-.5)*t.aspect, (1-uv.y)*sin(a), (1-uv.y)*cos(a));
    float3 normal = float3(0, cos(w), -sin(w));
    float denominator = dot(normal, point-eye);
    float distance = abs(denominator) > .00001 ? -dot(normal, eye)/denominator : -1.0;
    float3 reference = eye + distance * (point-eye);
    float2 projected = float2(reference.x/t.aspect+.5, 1-dot(reference, float3(0,sin(w),cos(w))));
    float easing = smoothstep(0.0, 7.0, t.workingAngle-angle);
    float2 source = mix(uv, projected, t.perspective*easing);
    float inside = step(0.0, source.x)*step(source.x,1.0)*step(0.0, source.y)*step(source.y,1.0)*step(0.0,distance);
    float edgeDistance = min(min(source.x, 1-source.x), min(source.y, 1-source.y));
    float feather = mix(1.0, smoothstep(0.0, .009, edgeDistance), easing);
    float blur = t.frost * smoothstep(.05, .9, progress) * (1.5 + 4.8 * (1-uv.y));
    float3 color = picture.sample(samplePicture, source, level(blur)).rgb;
    float dim = 1-t.shade*progress*(.25+.60*pow(1-uv.y,2.0));
    color *= dim;
    float glass = t.frost*progress*.035;
    color = mix(color, float3(.64,.76,.94), glass);
    float fade = smoothstep(t.fadeAngle, t.fadeAngle+12, angle);
    color *= inside*feather*fade;
    return float4(color, 1);
}
