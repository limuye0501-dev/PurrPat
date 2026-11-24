#include <math.h>
#include <stdint.h>
#include <stdlib.h>

static float clampf(float x, float a, float b) {
    if (x < a) return a;
    if (x > b) return b;
    return x;
}

static float smoothf2(float x, float a, float b) {
    float t = (x - a) / (b - a + 1e-5f);
    t = clampf(t, 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

static float fractf(float x) { return x - floorf(x); }

static float sd_segment(float px, float py, float ax, float ay, float bx, float by) {
    float pax = px - ax;
    float pay = py - ay;
    float bax = bx - ax;
    float bay = by - ay;
    float h = clampf((pax * bax + pay * bay) / (bax * bax + bay * bay + 1e-5f), 0.0f, 1.0f);
    float dx = pax - bax * h;
    float dy = pay - bay * h;
    return sqrtf(dx * dx + dy * dy);
}

static void sample_rgb(const uint8_t *px, int w, int h, float u, float v, float *r, float *g, float *b) {
    float x, y, tx, ty;
    int x0, y0, x1, y1;
    const uint8_t *p00, *p10, *p01, *p11;
    float r0, g0, b0, r1, g1, b1;
    if (px == NULL || w < 2 || h < 2) {
        *r = 0.84f; *g = 0.77f; *b = 0.68f;
        return;
    }
    u = clampf(u, 0.0f, 1.0f);
    v = clampf(v, 0.0f, 1.0f);
    x = u * (float)(w - 1);
    y = v * (float)(h - 1);
    x0 = (int)x;
    y0 = (int)y;
    x1 = x0 + 1; if (x1 >= w) x1 = w - 1;
    y1 = y0 + 1; if (y1 >= h) y1 = h - 1;
    tx = x - (float)x0;
    ty = y - (float)y0;
    p00 = px + ((y0 * w + x0) * 4);
    p10 = px + ((y0 * w + x1) * 4);
    p01 = px + ((y1 * w + x0) * 4);
    p11 = px + ((y1 * w + x1) * 4);
    r0 = ((float)p00[0] * (1.0f - tx) + (float)p10[0] * tx) / 255.0f;
    g0 = ((float)p00[1] * (1.0f - tx) + (float)p10[1] * tx) / 255.0f;
    b0 = ((float)p00[2] * (1.0f - tx) + (float)p10[2] * tx) / 255.0f;
    r1 = ((float)p01[0] * (1.0f - tx) + (float)p11[0] * tx) / 255.0f;
    g1 = ((float)p01[1] * (1.0f - tx) + (float)p11[1] * tx) / 255.0f;
    b1 = ((float)p01[2] * (1.0f - tx) + (float)p11[2] * tx) / 255.0f;
    *r = r0 * (1.0f - ty) + r1 * ty;
    *g = g0 * (1.0f - ty) + g1 * ty;
    *b = b0 * (1.0f - ty) + b1 * ty;
}

static float sample_r(const uint8_t *px, int w, int h, float u, float v) {
    float x, y, tx, ty, top, bot;
    int x0, y0, x1, y1;
    if (px == NULL || w < 2 || h < 2) return 0.0f;
    u = clampf(u, 0.0f, 1.0f);
    v = clampf(v, 0.0f, 1.0f);
    x = u * (float)(w - 1);
    y = v * (float)(h - 1);
    x0 = (int)x;
    y0 = (int)y;
    x1 = x0 + 1; if (x1 >= w) x1 = w - 1;
    y1 = y0 + 1; if (y1 >= h) y1 = h - 1;
    tx = x - (float)x0;
    ty = y - (float)y0;
    top = ((float)px[(y0 * w + x0) * 4] * (1.0f - tx) + (float)px[(y0 * w + x1) * 4] * tx) / 255.0f;
    bot = ((float)px[(y1 * w + x0) * 4] * (1.0f - tx) + (float)px[(y1 * w + x1) * 4] * tx) / 255.0f;
    return top * (1.0f - ty) + bot * ty;
}

static void sample_groom(const float *fx, const float *fy, const float *part, int w, int h, float u, float v,
                          float *ox, float *oy, float *op) {
    float x, y, tx, ty;
    int x0, y0, x1, y1, i00, i10, i01, i11;
    float ax, ay, ap, bx, by, bp, cx, cy, cp;
    if (fx == NULL || fy == NULL || part == NULL || w < 2 || h < 2) {
        *ox = 0; *oy = 0; *op = 0;
        return;
    }
    u = clampf(u, 0.0f, 1.0f);
    v = clampf(v, 0.0f, 1.0f);
    x = u * (float)(w - 1);
    y = v * (float)(h - 1);
    x0 = (int)x;
    y0 = (int)y;
    x1 = x0 + 1; if (x1 >= w) x1 = w - 1;
    y1 = y0 + 1; if (y1 >= h) y1 = h - 1;
    tx = x - (float)x0;
    ty = y - (float)y0;
    i00 = y0 * w + x0; i10 = y0 * w + x1; i01 = y1 * w + x0; i11 = y1 * w + x1;
    ax = fx[i00] * (1.0f - tx) + fx[i10] * tx;
    ay = fy[i00] * (1.0f - tx) + fy[i10] * tx;
    ap = part[i00] * (1.0f - tx) + part[i10] * tx;
    bx = fx[i01] * (1.0f - tx) + fx[i11] * tx;
    by = fy[i01] * (1.0f - tx) + fy[i11] * tx;
    bp = part[i01] * (1.0f - tx) + part[i11] * tx;
    cx = ax * (1.0f - ty) + bx * ty;
    cy = ay * (1.0f - ty) + by * ty;
    cp = ap * (1.0f - ty) + bp * ty;
    *ox = cx; *oy = cy; *op = cp;
}

static float ear_falloff(float x, float y, float cx, float cy) {
    float dx = (x - cx) / 0.05f;
    float dy = (y - cy) / 0.042f;
    return smoothf2(sqrtf(dx * dx + dy * dy), 1.05f, 0.2f);
}

static void tail_shift(float x, float y, float stretch, float sway, float *ox, float *oy) {
    float mx = 0.40f - sway * 0.25f;
    float cx = 0.31f - sway * 0.40f;
    float tx = 0.255f - sway * 0.20f - stretch * 0.03f;
    float ty = 0.71f - stretch * 0.025f;
    float d0 = sd_segment(x, y, 0.48f, 0.63f, mx, 0.72f);
    float d1 = sd_segment(x, y, mx, 0.72f, cx, 0.775f);
    float d2 = sd_segment(x, y, cx, 0.775f, tx, ty);
    float d = d0 < d1 ? d0 : d1;
    float along;
    if (d2 < d) d = d2;
    along = (d0 <= d1 && d0 <= d2) ? 0.25f : ((d1 <= d2) ? 0.6f : 1.0f);
    float tw = smoothf2(d, 0.055f, 0.01f);
    *ox = sway * tw * along * 0.65f + stretch * tw * along * 0.035f;
    *oy = stretch * tw * along * 0.02f;
}

static void grade(float *r, float *g, float *b) {
    *r = clampf(*r * 0.457f - 0.020f, 0.0f, 1.0f);
    *g = clampf(*g * 0.643f - 0.018f, 0.0f, 1.0f);
    *b = clampf(*b * 0.917f + 0.004f, 0.0f, 1.0f);
}

static float hash2(int x, int y) {
    uint32_t n = (uint32_t)x * 374761393u;
    n += (uint32_t)y * 668265263u;
    n = (n ^ (n >> 13)) * 1274126177u;
    return (float)(n & 0xFFFFFFu) / (float)0xFFFFFFu;
}

void plate_raster(
    uint8_t *dst, int width, int height,
    const uint8_t *cushion, int cushion_w, int cushion_h,
    const uint8_t *cat, int cat_w, int cat_h,
    const uint8_t *mask, int mask_w, int mask_h,
    const float *flow_x, const float *flow_y, const float *part,
    int groom_w, int groom_h,
    float ox, float oy, float dw, float dh,
    float breath, float ear_l, float ear_r, float chub_scale,
    float stretch, float sway,
    int night, int rain, float time, int draw_cat
) {
    int y, x;
    if (dst == NULL || width < 1 || height < 1 || dw < 1.0f || dh < 1.0f) return;
    for (y = 0; y < height; y++) {
        float fy = (float)y + 0.5f;
        for (x = 0; x < width; x++) {
            float fx = (float)x + 0.5f;
            float u = (fx - ox) / dw;
            float v = (fy - oy) / dh;
            float r, g, b;
            sample_rgb(cushion, cushion_w, cushion_h, u, v, &r, &g, &b);
            if (night) grade(&r, &g, &b);
            if (draw_cat) {
                float gx, gy, gp, wx, wy, fur_r, fur_g, fur_b, mask_v, alpha, occ, shade;
                float dx, dy, bw, breath_scale, tsx, tsy, press, detail, strand, grain;
                sample_groom(flow_x, flow_y, part, groom_w, groom_h, u, v, &gx, &gy, &gp);
                wx = 0.48f + (u - 0.48f) / chub_scale;
                wy = v;
                dx = wx - 0.48f;
                dy = wy - 0.46f;
                bw = smoothf2(sqrtf((dx / 0.20f) * (dx / 0.20f) + (dy / 0.18f) * (dy / 0.18f)), 1.35f, 0.2f);
                breath_scale = 1.0f - breath * 0.018f * bw;
                wx = 0.48f + dx * breath_scale;
                wy = 0.46f + dy * breath_scale;
                wy += ear_l * ear_falloff(wx, wy, 0.385f, 0.218f) * 0.012f;
                wy += ear_r * ear_falloff(wx, wy, 0.575f, 0.216f) * 0.012f;
                tail_shift(wx, wy, stretch, sway, &tsx, &tsy);
                wx += tsx;
                wy += tsy;
                wx -= gx * gp * 0.014f;
                wy -= gy * gp * 0.014f;
                sample_rgb(cat, cat_w, cat_h, wx, wy, &fur_r, &fur_g, &fur_b);
                mask_v = sample_r(mask, mask_w, mask_h, wx, wy);
                detail = hash2(x * 3, y * 5);
                strand = hash2(x, y * 3 + 7);
                grain = 0.945f + 0.04f * detail + 0.035f * smoothf2(strand, 0.28f, 0.75f);
                fur_r *= grain; fur_g *= grain; fur_b *= grain;
                press = clampf(gp, 0.0f, 1.0f);
                fur_r *= 1.0f - 0.22f * press;
                fur_g *= 1.0f - 0.22f * press;
                fur_b *= 1.0f - 0.22f * press;
                if (night) {
                    fur_r += 0.62f * press * press * 0.14f;
                    fur_g += 0.70f * press * press * 0.14f;
                    fur_b += 0.82f * press * press * 0.14f;
                    grade(&fur_r, &fur_g, &fur_b);
                } else {
                    fur_r += 1.00f * press * press * 0.14f;
                    fur_g += 0.96f * press * press * 0.14f;
                    fur_b += 0.88f * press * press * 0.14f;
                }
                alpha = smoothf2(mask_v, 0.12f, 0.62f);
                occ = (sample_r(mask, mask_w, mask_h, u, v + 0.007f)
                    + sample_r(mask, mask_w, mask_h, u + 0.004f, v + 0.009f)
                    + sample_r(mask, mask_w, mask_h, u - 0.004f, v + 0.008f)) * 0.34f;
                shade = clampf(occ - alpha, 0.0f, 1.0f);
                r *= 1.0f - shade * (night ? 0.42f : 0.26f);
                g *= 1.0f - shade * (night ? 0.42f : 0.26f);
                b *= 1.0f - shade * (night ? 0.42f : 0.26f);
                r = r * (1.0f - alpha) + fur_r * alpha;
                g = g * (1.0f - alpha) + fur_g * alpha;
                b = b * (1.0f - alpha) + fur_b * alpha;
            }
            if (rain) {
                float drop = fractf(fy * 0.016f - time * 0.32f + fx * 0.008f);
                float streak = smoothf2(drop, 0.0f, 0.045f) * (1.0f - smoothf2(drop, 0.045f, 0.15f));
                float column = fabsf(fractf(fx * 0.028f) - 0.5f);
                streak *= 1.0f - smoothf2(column, 0.0f, 0.42f);
                r += streak * (night ? 0.09f : 0.06f);
                g += streak * (night ? 0.09f : 0.06f);
                b += streak * (night ? 0.09f : 0.06f);
            }
            r = clampf(r, 0.0f, 1.0f);
            g = clampf(g, 0.0f, 1.0f);
            b = clampf(b, 0.0f, 1.0f);
            dst[(y * width + x) * 4 + 0] = (uint8_t)(r * 255.0f);
            dst[(y * width + x) * 4 + 1] = (uint8_t)(g * 255.0f);
            dst[(y * width + x) * 4 + 2] = (uint8_t)(b * 255.0f);
            dst[(y * width + x) * 4 + 3] = 255;
        }
    }
}
