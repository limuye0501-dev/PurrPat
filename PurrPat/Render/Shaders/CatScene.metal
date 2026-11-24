#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 resCenter;
    float4 scaleTimeChubRain;
    float4 breathEarStretch;
    float4 swayDelightHappyScene;
    float4 groomRect;
    float4 cushion;
    float4 extras;
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

static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    float2 shift = float2(0.0);
    for (int i = 0; i < 3; ++i) {
        v += a * vnoise(p + shift);
        p *= 2.02;
        a *= 0.5;
        shift += float2(1.7, 9.2);
    }
    return v;
}

static float sdEllipse(float2 p, float2 c, float2 r) {
    float2 q = (p - c) / r;
    return (length(q) - 1.0) * min(r.x, r.y);
}

static float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(1e-5, dot(ba, ba)));
    return length(pa - ba * h);
}

static float smin(float a, float b, float k) {
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

static float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

static float band(float x) {
    float s = sin(x) * 0.5 + 0.5;
    return smoothstep(0.42, 0.62, s);
}

static float3 coatColor(int coat, float2 p, int region, float along) {
    float n = fbm(p * 2.2 + 3.0);
    float n2 = fbm(p * 2.6 + 30.0);
    float3 color = float3(0.5);
    if (coat == 0) {
        color = float3(0.055, 0.050, 0.060) * (0.88 + 0.22 * n);
    } else if (coat == 1) {
        float stripe = band(p.x * 15.0 + n * 4.0);
        color = mix(float3(0.80, 0.44, 0.16), float3(0.36, 0.16, 0.06), stripe);
    } else if (coat == 2) {
        float3 white = float3(0.90, 0.88, 0.84);
        float3 orange = float3(0.82, 0.44, 0.16);
        float3 black = float3(0.10, 0.08, 0.07);
        float o = smoothstep(0.46, 0.58, n);
        float b = smoothstep(0.50, 0.62, n2);
        color = mix(mix(white, orange, o), black, b);
    } else if (coat == 3) {
        color = float3(0.94, 0.92, 0.89) * (0.96 + 0.08 * n);
    } else if (coat == 4) {
        float stripe = smoothstep(0.72, 0.9, abs(sin(p.x * 26.0 + n * 2.5)));
        color = mix(float3(0.72, 0.60, 0.46), float3(0.28, 0.20, 0.14), stripe);
    } else if (coat == 5) {
        bool chest = sdEllipse(p, float2(-0.18, 0.04), float2(0.12, 0.08)) < 0.0;
        bool blaze = region == 2 && abs(p.y) < 0.035 && p.x < -0.5;
        color = (chest || blaze || region == 6) ? float3(0.93, 0.91, 0.88) : float3(0.08, 0.075, 0.08);
    } else if (coat == 6) {
        float m = smoothstep(0.42, 0.58, fbm(p * 4.5 + n2));
        color = mix(float3(0.09, 0.07, 0.065), float3(0.78, 0.40, 0.14), m);
    } else if (coat == 7) {
        color = float3(0.46, 0.48, 0.52) * (0.92 + 0.08 * sin(along * 70.0));
    } else if (coat == 8) {
        float swirl = band(p.x * 8.0 + sin(p.y * 6.0) * 2.2 + n * 2.0);
        color = mix(float3(0.62, 0.40, 0.22), float3(0.28, 0.16, 0.08), swirl);
    } else if (coat == 9 || coat == 10) {
        float3 pale = coat == 9 ? float3(0.90, 0.82, 0.70) : float3(0.90, 0.91, 0.93);
        float3 point = coat == 9 ? float3(0.28, 0.18, 0.12) : float3(0.45, 0.50, 0.60);
        float m = (region == 3 || region == 4 || region == 5 || region == 6) ? 1.0 : 0.0;
        if (region == 2 && p.x < -0.60) m = max(m, smoothstep(0.0, 0.08, -0.60 - p.x));
        color = mix(pale, point, m * (coat == 10 ? 0.85 : 1.0));
    } else if (coat == 11) {
        float tick = 0.75 + 0.25 * (0.5 + 0.5 * sin(along * 55.0));
        color = float3(0.62, 0.61, 0.58) * tick;
    } else {
        float yy = p.y / 0.08;
        float dorsal = exp(-(yy * yy));
        color = mix(float3(0.48, 0.40, 0.30), float3(0.22, 0.16, 0.12), dorsal * 0.7);
    }
    if (region == 4) color = mix(color, float3(0.74, 0.48, 0.46), 0.7);
    return color;
}

// region: 1 body, 2 head, 3 ear, 4 inner ear, 5 tail, 6 paw
static void catSDF(float2 p, constant Uniforms &u, thread float &sdf, thread int &region, thread float2 &grain) {
    float ch = u.scaleTimeChubRain.z;
    float breath = 1.0 + u.breathEarStretch.x * 0.025;
    float stretch = u.extras.y > 0.5 && u.extras.y < 1.5 ? 1.0 + u.swayDelightHappyScene.y * 0.07 : 1.0;
    float headShift = u.extras.y > 0.5 && u.extras.y < 1.5 ? u.swayDelightHappyScene.y * 0.035 : 0.0;
    float body = sdEllipse(p, float2(0.05, 0.02), float2(0.48 * stretch, 0.195 * ch * breath));
    float belly = sdEllipse(p, float2(0.06, 0.075), float2(0.32 * stretch, 0.145 * ch));
    float chest = sdEllipse(p, float2(-0.24 - headShift, 0.02), float2(0.20, 0.155 * ch));
    float rump = sdEllipse(p, float2(0.30, 0.015), float2(0.20, 0.17 * ch));
    float neck = sdEllipse(p, float2(-0.40 - headShift * 0.5, 0.02), float2(0.12, 0.10 * ch));
    float torso = smin(body, belly, 0.12);
    torso = smin(torso, chest, 0.11);
    torso = smin(torso, rump, 0.11);
    torso = smin(torso, neck, 0.09);
    float head = sdEllipse(p, float2(-0.56 - headShift, 0.015), float2(0.168, 0.140));
    float earL = sdEllipse(p, float2(-0.64 - headShift, -0.155 + u.breathEarStretch.y * 0.05), float2(0.055, 0.105));
    float earR = sdEllipse(p, float2(-0.50 - headShift, 0.160 + u.breathEarStretch.z * 0.05), float2(0.050, 0.098));
    float earLI = sdEllipse(p, float2(-0.63 - headShift, -0.125), float2(0.022, 0.042));
    float earRI = sdEllipse(p, float2(-0.505 - headShift, 0.130), float2(0.020, 0.038));
    float s = u.breathEarStretch.w;
    float w = u.swayDelightHappyScene.x;
    float2 t0 = float2(0.36, 0.01);
    float2 t1 = float2(0.52, 0.13 + w);
    float2 t2 = float2(0.68 + s * 0.18, 0.10 + w * 0.6);
    float2 t3 = float2(0.84 + s * 0.42, -0.05 + w * 0.2);
    float tail = sdSegment(p, t0, t1) - 0.05 * ch;
    tail = min(tail, sdSegment(p, t1, t2) - 0.036 * ch);
    tail = min(tail, sdSegment(p, t2, t3) - 0.02 * ch);
    float pawA = sdEllipse(p, float2(-0.30 - headShift, 0.145), float2(0.07, 0.038 * ch));
    float pawB = sdEllipse(p, float2(-0.34 - headShift, -0.085), float2(0.055, 0.030));
    float cat = smin(torso, head, 0.055);
    cat = smin(cat, tail, 0.04);
    cat = smin(cat, pawA, 0.03);
    cat = smin(cat, pawB, 0.03);
    cat = min(cat, min(earL, earR));
    sdf = cat;
    float best = torso; region = 1;
    if (head < best) { best = head; region = 2; }
    if (min(earL, earR) < best) { best = min(earL, earR); region = 3; }
    if (tail < best) { best = tail; region = 5; }
    if (min(pawA, pawB) < best) { region = 6; }
    if (min(earLI, earRI) < 0.0) region = 4;
    grain = float2(1.0, p.y * 0.28);
    if (region == 5) {
        float d0 = sdSegment(p, t0, t1);
        float d1 = sdSegment(p, t1, t2);
        float d2 = sdSegment(p, t2, t3);
        grain = d0 < d1 && d0 < d2 ? (t1 - t0) : (d1 < d2 ? (t2 - t1) : (t3 - t2));
    } else if (region == 3 || region == 4) {
        grain = p.y < 0.0 ? float2(-0.2, -1.0) : float2(-0.15, 1.0);
    }
    grain = normalize(grain + 1e-4);
}

fragment float4 purrFragment(VOut in [[stage_in]],
                             constant Uniforms &u [[buffer(0)]],
                             texture2d<float> groomTex [[texture(0)]]) {
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    float2 frag = in.position.xy;
    float2 res = u.resCenter.xy;
    float2 center = u.resCenter.zw;
    float scale = max(u.scaleTimeChubRain.x, 1.0);
    float2 local = (frag - center) / scale;
    bool day = u.swayDelightHappyScene.w < 0.5;
    float3 floorA = day ? float3(0.91, 0.84, 0.75) : float3(0.12, 0.15, 0.24);
    float3 floorB = day ? float3(0.84, 0.75, 0.64) : float3(0.07, 0.09, 0.15);
    float3 col = mix(floorA, floorB, saturate(frag.y / res.y));

    float2 winMax = float2(res.x * 0.52, res.y * 0.21);
    if (frag.x < winMax.x && frag.y < winMax.y) {
        float t = frag.y / max(winMax.y, 1.0);
        col = day ? mix(float3(1.0, 0.96, 0.90), float3(1.0, 0.86, 0.70), t)
                  : mix(float3(0.10, 0.14, 0.28), float3(0.05, 0.07, 0.14), t);
        if (frag.x < 70.0 * (res.x / 390.0)) {
            float fold = 0.85 + 0.15 * sin(frag.x * 0.25);
            col = mix(col, day ? float3(0.98) * fold : float3(0.62, 0.68, 0.78) * fold, 0.55);
        }
        if (!day) {
            float moon = length(frag - float2(winMax.x - 64.0, 54.0));
            col = mix(col, float3(0.93, 0.94, 0.88), 1.0 - smoothstep(24.0, 28.0, moon));
        }
        if (u.scaleTimeChubRain.w > 0.5) {
            float drop = fract(frag.y * 0.02 - u.scaleTimeChubRain.y * 0.35 + frag.x * 0.01);
            float streak = smoothstep(0.0, 0.08, drop) * smoothstep(0.2, 0.08, drop);
            streak *= smoothstep(1.5, 0.0, abs(fract(frag.x * 0.04) - 0.5) * 8.0);
            col += streak * (day ? 0.15 : 0.25);
        }
    }

    float2 cushCenter = u.cushion.xy + u.cushion.zw * 0.5;
    float2 cushHalf = u.cushion.zw * 0.5;
    float cush = sdRoundBox(frag - cushCenter, cushHalf, 36.0 * (res.x / 390.0));
    float cushA = saturate(1.0 - smoothstep(-1.0, 1.5, cush));
    float3 linen = day ? float3(0.84, 0.77, 0.67) : float3(0.24, 0.27, 0.36);
    float weave = 0.5 + 0.5 * sin(frag.x * 1.3) * sin(frag.y * 1.25);
    linen *= 0.94 + 0.08 * weave;
    float ang = atan2(frag.y - winMax.y * 0.5, frag.x - 40.0);
    float d0 = (ang - 1.0) / 0.12;
    float d1 = (ang - 1.18) / 0.07;
    float beams = exp(-(d0 * d0)) * 0.28 + exp(-(d1 * d1)) * 0.16;
    beams *= saturate((frag.y - winMax.y * 0.4) / 200.0) * cushA;
    float3 ray = day ? float3(1.0, 0.95, 0.82) : float3(0.70, 0.78, 0.95);
    float3 room = mix(col, linen, cushA) + ray * beams * (day ? 1.0 : 0.45);
    col = room;

    float sdf = 1.0; int region = 0; float2 grain = float2(1.0, 0.0);
    catSDF(local, u, sdf, region, grain);
    float furLength = max(u.extras.w, 0.5);
    float fringe = 0.012 * furLength;
    if (sdf < fringe) {
        float2 uv = (local - u.groomRect.xy) / max(u.groomRect.zw, 1e-3);
        float4 g = groomTex.sample(smp, uv);
        float2 flow = g.xy * 2.0 - 1.0;
        float part = g.z;
        float2 fur = normalize(grain + flow * 1.2 + 1e-4);
        float along = dot(local, fur);
        float across = dot(local, float2(-fur.y, fur.x));
        float fiber = 0.93 + 0.09 * (fbm(local * 6.2) - 0.5) + 0.05 * (vnoise(float2(along * 16.0, across * 42.0)) - 0.5);
        int coat = int(u.extras.x + 0.5);
        float3 alb = coatColor(coat, local, region, along);
        float3 amb = day ? float3(0.58, 0.50, 0.44) : float3(0.32, 0.36, 0.50);
        float3 key = day ? float3(1.02, 0.95, 0.84) : float3(0.58, 0.66, 0.92);
        float inside = smoothstep(0.0, 0.05, -sdf);
        float yy = local.y / (0.16 * u.scaleTimeChubRain.z);
        float xx = (local.x - 0.02) / 0.46;
        float spine = exp(-(yy * yy)) * exp(-(xx * xx));
        float3 furCol = alb * (amb + key * (0.42 + 0.45 * inside)) * fiber;
        float3 sheen = day ? float3(1.0, 0.96, 0.86) : float3(0.78, 0.84, 1.0);
        furCol += sheen * spine * (day ? 0.20 : 0.12);
        furCol *= 1.0 - 0.34 * part;
        float lip = (part - 0.48) / 0.18;
        furCol += exp(-(lip * lip)) * 0.06;
        furCol = 1.0 - exp(-furCol * 1.08);
        // Closed eyes, nose.
        float headShift = u.extras.y > 0.5 && u.extras.y < 1.5 ? u.swayDelightHappyScene.y * 0.035 : 0.0;
        float eye = min(
            sdEllipse(local, float2(-0.655 - headShift, -0.04), float2(0.05, 0.012)),
            sdEllipse(local, float2(-0.655 - headShift, 0.038), float2(0.05, 0.012))
        );
        furCol = mix(furCol, float3(0.15, 0.10, 0.09), smoothstep(0.006, -0.002, eye) * (region == 2 ? 1.0 : 0.0));
        float nose = sdEllipse(local, float2(-0.71 - headShift, 0.012), float2(0.018, 0.012));
        furCol = mix(furCol, float3(0.55, 0.32, 0.30), smoothstep(0.004, -0.004, nose));
        float alpha = saturate(1.0 - sdf / fringe);
        col = mix(col, furCol, alpha);
        float shadow = pow(saturate(1.0 - (sdf - 0.02) / 0.12), 1.5) * (1.0 - alpha) * cushA;
        col *= 1.0 - shadow * (day ? 0.22 : 0.35);
    }
    return float4(saturate(col), 1.0);
}
