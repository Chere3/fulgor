#include <metal_stdlib>
using namespace metal;
#include "frame.metal"
#include "atmosphere.metal"

struct SkyOut {
    float4 position [[position]];
    float2 uv;
};

vertex SkyOut sky_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    return {float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0), p};
}

fragment float4 sky_fragment(SkyOut in [[stage_in]], constant FrameData &frame [[buffer(0)]]) {
    float4 eye = frame.invViewProj * float4(0,0,1,0);
    float4 nearPoint = frame.invViewProj * float4(in.uv * 2.0 - 1.0, 1.0, 1.0);
    float3 direction = normalize(nearPoint.xyz / nearPoint.w - eye.xyz / eye.w);
    // A lightning flash lights the clouded sky from within.
    // The open sky sits a little under the light it gives the haze, as in the reference.
    float3 sky = atmosphere_sky(frame, direction) * 0.78 + float3(0.20, 0.23, 0.32) * frame.lightning.w;
#ifdef MC_SOFT_CLOUDS
    // The sun: a round disc bright enough to glow (the bloom spreads it), in place of the game's square one
    // (SkyRendererMixin), and behind the clouds.
    float towardsSun = dot(direction, frame.solarDir.xyz);
    float disc = smoothstep(0.99880, 0.99935, towardsSun) * (1.0 - saturate(frame.params.y)) * smoothstep(-0.05, 0.02, frame.solarDir.y);
    // Far brighter than the sky around it, and nearly white: the haze in front of a low sun dims it a good deal.
    float halo = pow(saturate(towardsSun), 900.0) * (1.0 - saturate(frame.params.y)) * smoothstep(-0.05, 0.02, frame.solarDir.y);
    sky += mix(frame.surfaceSun.rgb, float3(1.3), 0.6) * (48.0 * disc + 3.0 * halo);
    // The alpha tells the composite pass how much cloud is here (1: clear sky, 0.5: all cloud), so the haze it lays
    // over the sky spares the clouds; nothing else reads the sky's alpha.
    float covered;
    float2 grain = in.position.xy + 5.588238 * fmod(frame.temporal.x, 64.0);
    sky = cloud_layer(frame, direction, sky, covered, fract(52.9829189 * fract(dot(grain, float2(0.06711056, 0.00583715)))));
    return float4(sky, 1.0 - 0.5 * covered);
#endif
    return float4(sky, 1.0);
}
