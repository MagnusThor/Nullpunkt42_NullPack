vec3 RGBtoYCoCg(vec3 c) { return mat3(.25, .5, -.25, .5, 0, .5, .25, -.5, -.25) * c; }
vec3 YCoCgToRGB(vec3 c) { return mat3(1, 1, 1, 1, 0, -1, -1, 1, -1) * c; }

vec4 SampleTextureCatmullRom(sampler2D tex, vec2 texSize, vec2 uv) {
    vec2 samplePos = uv * texSize;
    vec2 texPos1 = floor(samplePos - 0.5) + 0.5;
    vec2 f = samplePos - texPos1;
    vec2 w0 = f * ( -0.5 + f * (1.0 - 0.5*f));
    vec2 w1 = 1.0 + f * f * (-2.5 + 1.5*f);
    vec2 w2 = f * ( 0.5 + f * (2.0 - 1.5*f) );
    vec2 w3 = f * f * (-0.5 + 0.5 * f);
    vec2 w12 = w1 + w2;
    vec2 offset12 = w2 / w12;
    vec2 texPos0 = (texPos1 - vec2(1.0)) / texSize;
    vec2 texPos3 = (texPos1 + vec2(2.0)) / texSize;
    vec2 texPos12 = (texPos1 + offset12) / texSize;

    vec4 result = vec4(0.0);
    result += texture(tex, vec2(texPos0.x,  texPos0.y)) * w0.x * w0.y;
    result += texture(tex, vec2(texPos12.x, texPos0.y)) * w12.x * w0.y;
    result += texture(tex, vec2(texPos3.x,  texPos0.y)) * w3.x * w0.y;
    result += texture(tex, vec2(texPos0.x,  texPos12.y)) * w0.x * w12.y;
    result += texture(tex, vec2(texPos12.x, texPos12.y)) * w12.x * w12.y;
    result += texture(tex, vec2(texPos3.x,  texPos12.y)) * w3.x * w12.y;
    result += texture(tex, vec2(texPos0.x,  texPos3.y)) * w0.x * w3.y;
    result += texture(tex, vec2(texPos12.x, texPos3.y)) * w12.x * w3.y;
    result += texture(tex, vec2(texPos3.x,  texPos3.y)) * w3.x * w3.y;
    return result;
}

void mainImage(out vec4 fragColor, vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 o = getJitter(iFrame);
    
    vec4 curr = textureLod(iChannel0, (fragCoord - o) / res, 0.0);
    float depth = curr.a;
    
    if (depth >= 19.9) {
        fragColor = curr;
        return;
    }

    vec3 ro, ta; float roll, fl;
    getCamera(iTime, ro, ta, roll, fl);
    mat3 cmat = calcLookAtMatrix(ro, ta, roll);
    
    vec2 pv = (fragCoord - 0.5 * res) / res.y; 
    vec3 rd = normalize(cmat * vec3(pv, fl));
    vec3 p = ro + rd * depth; 

    vec3 pro, pta; float proll, pfl;
    getCamera(iTime - iTimeDelta, pro, pta, proll, pfl);
    mat3 pmat = calcLookAtMatrix(pro, pta, proll);

    vec3 cp = transpose(pmat) * (p - pro);
    vec2 np = cp.xy / (cp.z / pfl);
    vec2 puv = (np * res.y + 0.5 * res) / res;
    vec3 prd = normalize(pmat * vec3(np, pfl));

    vec4 hist = SampleTextureCatmullRom(iChannel1, res, puv);
    vec3 pp = pro + prd * hist.a; 

    float a = 0.1; 
    
    if (puv.x < 0.0 || puv.x > 1.0 || puv.y < 0.0 || puv.y > 1.0) {
        a = 1.0; 
    }
    
    if (distance(p, pp) > 0.1 * depth) {
        a = 1.0; 
    }

    if (distance(ro, pro) > 0.5) {
        a = 1.0;
    }

    vec3 newCol = RGBtoYCoCg(curr.rgb);
    vec3 oldCol = RGBtoYCoCg(hist.rgb);
    
    vec3 cMin = newCol;
    vec3 cMax = newCol;
    
    for(int y = -1; y <= 1; ++y) {
        for(int x = -1; x <= 1; ++x) {
            if(x == 0 && y == 0) continue;
            vec3 neighbor = RGBtoYCoCg(textureLod(iChannel0, (fragCoord - o + vec2(x, y)) / res, 0.0).rgb);
            cMin = min(cMin, neighbor);
            cMax = max(cMax, neighbor);
        }
    }
    
    oldCol = clamp(oldCol, cMin, cMax);

    vec3 finalCol = (iFrame != 0) ? mix(oldCol, newCol, a) : newCol;
    fragColor = vec4(YCoCgToRGB(finalCol), depth);
}