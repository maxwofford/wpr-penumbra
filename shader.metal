// penumbra: raymarched twisted torus through a crt, ported from the hack club
// penumbra landing page by ascpixi (https://github.com/hackclub/penumbra)
// crt pass after Xor (https://www.shadertoy.com/view/DtscRf)
// bloom after Xor's 1-pass blur (https://github.com/XorDev/1PassBlur)
//
// three-pass glsl -> two-pass metal: bloom reads the raw scene instead of
// the crt'd intermediate, so the glow is slightly smoother than the original

// crt intensity: 0 = clean, 1 = full retro
#ifndef WP_PARAM_crt
#define WP_PARAM_crt 1.0
#endif
// crt subpixel cell size in screen pixels
#ifndef WP_PARAM_mask
#define WP_PARAM_mask 12.0
#endif

constant float PN_PI  = 3.14159265358979;
constant float PN_D2R = PN_PI / 180.0;
constant float PN_FOV = 0.3;
constant float PN_FAR = 50.0;
constant float PN_EPS = 0.001;
constant int   PN_STEPS = 32;
constant float PN_BLOOM_R = 16.0;
constant float PN_BLOOM_N = 16.0;
constant float PN_BLOOM_BASE = 0.5;
constant float PN_BLOOM_GLOW = 3.0;

// ---- geometry ----------------------------------------------------------------

float3 pnRotX(float3 p, float a) {
    float c = cos(a), s = sin(a);
    return float3(p.x, c*p.y - s*p.z, s*p.y + c*p.z);
}

float3 pnRotZ(float3 p, float a) {
    float c = cos(a), s = sin(a);
    return float3(c*p.x - s*p.y, s*p.x + c*p.y, p.z);
}

float3 pnTwist(float3 p, float k) {
    float c = cos(k * p.y), s = sin(k * p.y);
    return float3(c*p.x + s*p.z, -s*p.x + c*p.z, p.y);
}

float pnTorus(float3 p, float2 t) {
    return length(float2(length(p.xz) - t.x, p.y)) - t.y;
}

float pnDisp(float3 p) {
    return sin(2.0*p.x) * sin(2.4*p.y) * sin(2.0*p.z);
}

float pnScene(float3 p, float angle) {
    p = pnRotX(p, 20.0 * PN_D2R);
    p = pnRotZ(p, angle);
    p = pnTwist(p, 1.0 + 87.0 / 15.0);
    return pnTorus(p, float2(2.5, 1.0)) - pnDisp(p) / 5.0;
}

float3 pnPalette(float t) {
    return float3(0.35) + float3(0.5) *
        cos(2.0*PN_PI * (float3(0.3, 0.5, 0.7) * t + float3(0.0, 0.2, 0.4)));
}

// ---- main: raymarched torus --------------------------------------------------

float4 wp_main(float2 uv, constant Uniforms& u) {
    float angle = hash11(u.seed + 40.0) * 360.0 * PN_D2R;
    float aspect = u.res.x / u.res.y;
    float2 cuv = uv * 2.0 - float2(aspect, 1.0);

    float3 ro = float3(0.0, 0.0, -3.0);
    float3 rd = normalize(float3(cuv * PN_FOV, 1.0));

    float t = 0.3, minD = 1e9;
    for (int i = 0; i < PN_STEPS; i++) {
        float d = pnScene(ro + rd * t, angle);
        t += d;
        minD = min(d, minD);
        if (d < PN_EPS || t > PN_FAR) break;
    }

    float3 color;
    if (t > PN_FAR) {
        float glow = 1.0 - clamp(minD, 0.0, 1.0);
        color = pnPalette(minD) * glow;
    } else {
        color = pnPalette(t / 16.0);
    }
    return float4(color, 1.0);
}

// ---- post: crt + bloom -------------------------------------------------------

float4 wp_post(float2 uv, texture2d<float> scene, constant Uniforms& u) {
    float crt = clamp(float(WP_PARAM_crt), 0.0, 1.0);
    float maskSz = max(float(WP_PARAM_mask), 1.0);
    float rY = u.res.y;

    // screen curvature
    float aspect = u.res.x / u.res.y;
    float2 ndc = uv / float2(aspect, 1.0) * 2.0 - 1.0;
    float curvature = 0.08 * crt;
    float2 warped = ndc * (1.0 + (dot(ndc, ndc) - 1.0) * curvature);
    float2 wUv = (warped + 1.0) * 0.5 * float2(aspect, 1.0);
    float2 px = (warped * 0.5 + 0.5) * u.res;

    // crt grid with chromatic aberration
    float maskEff = mix(1.0, maskSz, crt);
    float2 coord = px / maskEff;
    float2 cellOff = float2(0.0, fract(floor(coord.x) * 0.5));
    float2 cellPx = floor(coord + cellOff) * maskEff;
    float2 aberr = float2(2.0, 0.0) * crt;

    float3 crtCol;
    crtCol.r = wp_scene(scene, (cellPx - aberr) / rY, 0.0).r;
    crtCol.g = wp_scene(scene, (cellPx + aberr) / rY, 0.0).g;
    crtCol.b = wp_scene(scene, cellPx / rY, 0.0).b;

    // rgb subpixel mask
    float2 sub = coord * float2(3.0, 1.0);
    float ch = fmod(floor(sub.x), 3.0);
    ch = ch < 0.0 ? ch + 3.0 : ch;
    float3 mask = float3(ch < 0.5 ? 1.0 : 0.0,
                          (ch > 0.5 && ch < 1.5) ? 1.0 : 0.0,
                          ch > 1.5 ? 1.0 : 0.0) * 3.0;
    float2 cellUv = fract(sub + cellOff) * 2.0 - 1.0;
    float maskBorder = 0.8 * crt;
    float2 brd = 1.0 - cellUv * cellUv * maskBorder;
    mask *= brd.x * brd.y;
    crtCol *= 1.0 + (mask - 1.0) * crt;

    // vignette
    float2 edge = max(1.0 - ndc * ndc, float2(0.0));
    float vignette = pow(edge.x * edge.y, 0.4 * crt + 0.001);
    crtCol *= vignette;

    // crt scan pulse (frozen with seed phase)
    float pulse = cos(px.x / 60.0 + hash11(u.seed + 41.0) * 100.0) * 0.03 * crt;
    crtCol *= 1.0 + pulse;

    // bloom (golden angle spiral, reads raw scene since we have two passes not three)
    float4 bloom = float4(0.0);
    float2 bpt = float2(PN_BLOOM_R, 0.0) * rsqrt(PN_BLOOM_N);
    float bloomBase = mix(1.0, PN_BLOOM_BASE, crt);
    float bloomGlow = mix(0.0, PN_BLOOM_GLOW, crt);

    for (float i = 0.0; i < PN_BLOOM_N; i += 1.0) {
        float bx = bpt.x, by = bpt.y;
        bpt = float2(-0.7374*bx + 0.6755*by, -0.6755*bx - 0.7374*by);
        float2 sc = (px + bpt * sqrt(i)) / rY;
        bloom += wp_scene(scene, sc, 0.0) * (1.0 - i / PN_BLOOM_N);
    }
    bloom *= bloomGlow / PN_BLOOM_N;

    float3 color = crtCol * bloomBase + bloom.rgb;

    return float4(max(color, float3(0.0)), 1.0);
}
