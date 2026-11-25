#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 resTimeZoom;
    float4 motion;
    float4 tailScene;
    float4 groomRect;
    float4 plateRect;
};

struct VOut {
    float4 position [[position]];
};

vertex VOut purrVertex(uint id [[vertex_id]]) {
    float2 p[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VOut o;
    o.position = float4(p[id], 0.0, 1.0);
    return o;
}

static float hash21(float2 p) {
    int x = int(floor(p.x));
    int y = int(floor(p.y));
    uint n = uint(x) * 374761393u + uint(y) * 668265263u;
    n = (n ^ (n >> 13u)) * 1274126177u;
    return float(n & 0xFFFFFFu) / float(0xFFFFFFu);
}

static float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(1e-5, dot(ba, ba)));
    return length(pa - ba * h);
}

// Keep the tail spine in sync with CatAnatomy.tailPoints.
static float tailWeight(float2 p, float stretch, float sway, thread float &along) {
    float2 base = float2(0.48, 0.63);
    float2 mid = float2(0.40 - sway * 0.25, 0.72);
    float2 curl = float2(0.31 - sway * 0.40, 0.775);
    float2 tip = float2(0.255 - sway * 0.20 - stretch * 0.03, 0.71 - stretch * 0.025);
    float d0 = sdSegment(p, base, mid);
    float d1 = sdSegment(p, mid, curl);
    float d2 = sdSegment(p, curl, tip);
    float d = min(d0, min(d1, d2));
    along = d0 <= d1 && d0 <= d2 ? 0.25 : (d1 <= d2 ? 0.6 : 1.0);
    return 1.0 - smoothstep(0.01, 0.055, d);
}

static float earWeight(float2 p, float2 c) {
    float2 d = (p - c) / float2(0.05, 0.042);
    return 1.0 - smoothstep(0.2, 1.05, length(d));
}

static float3 nightGrade(float3 c) {
    return saturate(c * float3(0.457, 0.643, 0.917) + float3(-0.020, -0.018, 0.004));
}

static float2 warp(float2 uv, constant Uniforms &u, float2 flow, float part) {
    float breath = u.motion.x;
    float earL = u.motion.y;
    float earR = u.motion.z;
    float chub = u.motion.w;
    float stretch = u.tailScene.x;
    float sway = u.tailScene.y;
    float2 p = uv;
    float wide = 0.96 + chub * 0.08;
    p.x = 0.48 + (p.x - 0.48) / wide;

    float2 torso = float2(0.48, 0.46);
    float2 d = p - torso;
    float bw = 1.0 - smoothstep(0.2, 1.35, length(d / float2(0.20, 0.18)));
    p = torso + d * (1.0 - breath * 0.018 * bw);

    p.y += earL * earWeight(p, float2(0.385, 0.218)) * 0.012;
    p.y += earR * earWeight(p, float2(0.575, 0.216)) * 0.012;

    float along = 0.0;
    float tw = tailWeight(p, stretch, sway, along);
    p.x += sway * tw * along * 0.65;
    p.x += stretch * tw * along * 0.035;
    p.y += stretch * tw * along * 0.02;

    p -= flow * part * 0.014;
    return p;
}

fragment float4 purrFragment(VOut in [[stage_in]],
                             constant Uniforms &u [[buffer(0)]],
                             texture2d<float> groomTex [[texture(0)]],
                             texture2d<float> cushionTex [[texture(1)]],
                             texture2d<float> catTex [[texture(2)]],
                             texture2d<float> maskTex [[texture(3)]]) {
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    float2 frag = in.position.xy;
    float2 origin = u.plateRect.xy;
    float2 span = max(u.plateRect.zw, float2(1.0));
    float2 uv = (frag - origin) / span;

    bool night = u.tailScene.w > 0.5;
    float3 bg = cushionTex.sample(smp, uv).rgb;
    if (night) bg = nightGrade(bg);

    float2 gUV = (uv - u.groomRect.xy) / max(u.groomRect.zw, float2(1e-4));
    float4 g = groomTex.sample(smp, gUV);
    float2 flow = g.xy * 2.0 - 1.0;
    float part = g.z;
    float2 sampleUV = warp(uv, u, flow, part);

    float3 fur = catTex.sample(smp, sampleUV).rgb;
    float mask = maskTex.sample(smp, sampleUV).r;
    float detail = hash21(frag * 0.72);
    float strand = hash21(frag * float2(0.18, 1.25));
    fur *= 0.945 + 0.04 * detail + 0.035 * smoothstep(0.28, 0.75, strand);
    float press = saturate(part);
    fur *= 1.0 - 0.22 * press;
    float3 sheen = night ? float3(0.62, 0.70, 0.82) : float3(1.0, 0.96, 0.88);
    fur += sheen * press * press * 0.14;
    if (night) fur = nightGrade(fur);

    // The mask asset is already eroded and feathered. Hardening it redraws a jagged rim.
    float alpha = saturate(mask);
    float blur = 0.0;
    blur += maskTex.sample(smp, uv + float2( 0.014, 0.0)).r;
    blur += maskTex.sample(smp, uv + float2(-0.014, 0.0)).r;
    blur += maskTex.sample(smp, uv + float2(0.0,  0.014)).r;
    blur += maskTex.sample(smp, uv + float2(0.0, -0.014)).r;
    blur += maskTex.sample(smp, uv + float2( 0.010,  0.010)).r;
    blur += maskTex.sample(smp, uv + float2(-0.010,  0.010)).r;
    blur += maskTex.sample(smp, uv + float2( 0.010, -0.010)).r;
    blur += maskTex.sample(smp, uv + float2(-0.010, -0.010)).r;
    blur *= 0.125;
    float shade = saturate(blur - alpha);
    bg *= 1.0 - shade * 0.22;
    float3 col = mix(bg, fur, alpha);

    if (u.tailScene.z > 0.5) {
        float drop = fract(frag.y * 0.016 - u.resTimeZoom.z * 0.32 + frag.x * 0.008);
        float streak = smoothstep(0.0, 0.045, drop) * (1.0 - smoothstep(0.05, 0.16, drop));
        streak *= 1.0 - smoothstep(0.0, 0.42, abs(fract(frag.x * 0.028) - 0.5));
        col += streak * (night ? 0.09 : 0.06);
    }
    return float4(saturate(col), 1.0);
}
