#include <metal_stdlib>
using namespace metal;

// Keep in step with site/dist/demo.mjs — the web demo and the Mac app share this look.

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

// Poisson disc, unit radius. Rotated per pixel so twelve taps read as smooth glass.
constant float2 kTaps[12] = {
    float2(-0.326,-0.406), float2(-0.840,-0.074), float2(-0.696, 0.457), float2(-0.203, 0.621),
    float2( 0.962,-0.195), float2( 0.473,-0.480), float2( 0.519, 0.767), float2( 0.185,-0.893),
    float2( 0.507, 0.064), float2( 0.896, 0.412), float2(-0.322,-0.933), float2(-0.792,-0.598)
};

static float hash21(float2 q) { return fract(sin(dot(q, float2(12.9898, 78.233))) * 43758.5453); }

static float3 frosted(texture2d<float> picture, sampler s, float2 uv, float radius, float lod, float aspect, float seed) {
    float a = seed * 6.2831853;
    float2x2 rot = float2x2(float2(cos(a), sin(a)), float2(-sin(a), cos(a)));
    float2 scale = float2(radius / aspect, radius);
    float3 sum = 0;
    for (int i = 0; i < 12; i++) sum += picture.sample(s, uv + (rot * kTaps[i]) * scale, level(lod)).rgb;
    return sum / 12.0;
}

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
    float ray = abs(denominator) > .00001 ? -dot(normal, eye)/denominator : -1.0;
    float3 reference = eye + ray * (point-eye);
    float2 projected = float2(reference.x/t.aspect+.5, 1-dot(reference, float3(0,sin(w),cos(w))));
    float easing = smoothstep(0.0, 7.0, t.workingAngle-angle);
    float2 source = mix(uv, projected, t.perspective*easing);

    // How far the projected point falls outside the picture (0 inside).
    float outside = max(max(-source.x, source.x-1.0), max(-source.y, source.y-1.0));
    outside = max(outside, step(ray, 0.0));

    // Frost: blur radius grows with progress and toward the top of the panel.
    // Comes in early: clearly soft by 90°, heavy by 70°.
    float soft = smoothstep(0.0, .5, progress);
    float radius = t.frost * soft * (.016 + .05 * (1-uv.y));
    float lod = clamp(log2(max(radius * float(picture.get_height()), 1.0)) - .35, 0.0, 5.5);
    float3 color = frosted(picture, samplePicture, source, radius, lod, t.aspect, hash21(in.position.xy));

    // Glow: bright content bleeds into a soft halo, like light through frosted glass.
    float3 haze = picture.sample(samplePicture, source, level(6.0)).rgb;
    color += haze * haze * (.6 * t.frost * soft);
    color = mix(color, float3(.64,.76,.94), t.frost * progress * .06);

    // Shade toward the top as the lid comes down; past the picture's edge the panel
    // reads as dark glass, not a stretched top row.
    color *= 1 - t.shade * progress * (.25 + .60 * pow(1-uv.y, 2.0));
    float3 glass = float3(.075,.085,.11) * (1.0 - .55 * progress);
    color = mix(color, glass, smoothstep(0.0, .06 + .08 * progress, outside));

    float fade = smoothstep(t.fadeAngle, t.fadeAngle+12, angle);
    color *= fade;
    return float4(color, 1);
}
