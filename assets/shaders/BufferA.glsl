// Transpiled from TinyShade 1001:0841

const int RAY_STEPS = 180;

const int SHADOWS = 12;

float tri(in float x) { return abs(fract(x) - .5); }

vec3 tri3(in vec3 p) { 
    return vec3(tri(p.z + tri(p.y)), tri(p.z + tri(p.x)), tri(p.y + tri(p.x))); 
}

float Noise3d(in vec3 p) {
    float z = 1.4;
    float rz = 0.0;
    vec3 bp = p;
    for (float i = 0.0; i <= 2.0; i++) {
        vec3 dg = tri3(bp);
        p += dg;
        bp *= 2.0;
        z *= 1.5;
        p *= 1.3;
        rz += tri(p.z + tri(p.x + tri(p.y))) / z;
        bp += 0.14;
    }
    return rz;
}

float fogmap(in vec3 p, in float t) {
    p.xz -= t * 0.2 + sin(p.z * 0.5) * 1.0;
    p.y -= t * 0.1;
    return (max(Noise3d(p * 0.8 + 0.1) - 0.1, 0.0) * Noise3d(p * 1.2)) * 0.4;
}

float sdUFO(vec3 p) {
    float dish = length(p * vec3(1.0, 3.2, 1.0)) - 0.12;
    float dome = length((p - vec3(0.0, 0.025, 0.0)) * vec3(1.8, 2.6, 1.8)) - 0.065;
    float rim = length(vec2(length(p.xz) - 0.13, p.y * 4.0)) - 0.012;
    return min(min(dish, dome), rim) * 0.5;
}

float mapUFOSchool(vec3 p) {
    float d = 1e5;
    const float ufoScale = 3.0;
    float vTime = getVisualTime(iTime);
    
    for(int i = 0; i < 3; i++) {
        float fi = float(i);
        float speed = 0.35 + fi * 0.08;
        float angle = vTime * speed + fi * 2.094;
        float radius = 2.8 + 0.6 * sin(vTime * 0.4 + fi);
        float height = 0.4 + 0.8 * sin(vTime * 0.6 + fi * 1.5);
        
        vec3 ufoPos = vec3(sin(angle) * radius, height, cos(angle) * radius);
        vec3 q = (p - ufoPos) / ufoScale;
        
        q.yz *= rot(sin(angle * 2.0) * 0.15);
        float du = sdUFO(q) * ufoScale;
        d = min(d, du);
    }
    return d;
}

float de1(vec3 p) {
    float vTime = getVisualTime(iTime);
    vec3 cs = vec3(0.63248, 0.78632, 0.875) + sin(vTime * 0.2 + vec3(0.0, 2.0, 4.0)) * 0.02;
    float invLimit = 0.70968 + sin(vTime * 0.15) * 0.015;
    
    float s = 1.0;    
    for(int i = 0; i < 5; i++) {
        p = 2.0 * clamp(p, -cs, cs) - p;
        float k = max(invLimit / dot(p, p), 1.0);
        p *= k;
        s *= k;
        
        if(trap.r >= 0.0) trap.xyz += abs(p) * 0.2 / s; 
    }
    
    float rxy = length(p.xy);
    return max(rxy - 0.92784, abs(rxy * p.z) / length(p)) / s;
}

float de2(vec3 p0) {
    vec4 p = vec4(p0 / 10.0, 1.0);
    p.xyz = abs(p.xyz);
    float vTime = getVisualTime(iTime);
    
    if(p.x < p.z) p.xz = p.zx;
    if(p.z < p.y) p.zy = p.yz;
    if(p.y < p.x) p.yx = p.xy;
    
    for(int i = 0; i < 6; i++) {
        if(p.x < p.z) p.xz = p.zx;
        if(p.z < p.y) p.zy = p.yz;
        if(p.y < p.x) p.yx = p.xy;
        
        p.xyz = abs(p.xyz);
        p *= (1.9 / clamp(dot(p.xyz, p.xyz), 0.1, 1.0));
        
        vec3 offset = vec3(0.2, 1.9, 0.6) + sin(vTime * 0.3 + float(i)) * 0.035;
        p.xyz -= offset;
        
        if(trap.r >= 0.0) trap.xyz += abs(p.xyz) * 0.8;
    }
    
    float m = 1.2;
    p.xyz -= clamp(p.xyz, -m, m);
    float dFrac = (length(p.xyz) / p.w) * 10.0;
    
    float arena = length(vec2(length(p0.xz) - 3.0, p0.y - 0.4)) - 2.0;
    dFrac = max(dFrac, -arena);
    
    float dUFO = mapUFOSchool(p0);
    
    if(trap.r >= 0.0) {
        trap.w += smoothstep(0.15, 0.0, dUFO) * 2.0;
    }
    
    return min(dFrac, dUFO);
}

float map(vec3 p) {
    float vTime = getVisualTime(iTime);
    float blend = getMorphBlend(vTime); 
    
    if (blend <= 0.0) return de1(p);
    if (blend >= 1.0) return de2(p);
    
    vec4 backupTrap = trap;
    trap = vec4(-1.0); 
    float d1 = de1(p);
    float d2 = de2(p);
    
    trap = backupTrap;
    if (trap.r >= 0.0) {
        trap = vec4(0.0); de1(p); vec4 t1 = trap;
        trap = vec4(0.0); de2(p); vec4 t2 = trap;
        trap = mix(t1, t2, blend);
    }
    
    return mix(d1, d2, blend);
}

vec3 calcNormal(in vec3 p) {
    vec2 e = vec2(1.0, -1.0) * 0.5773 * 0.003; 
    return normalize(e.xyy * map(p + e.xyy) + 
                     e.yyx * map(p + e.yyx) + 
                     e.yxy * map(p + e.yxy) + 
                     e.xxx * map(p + e.xxx));
}

/*

float cheapShadow(vec3 ro, vec3 rd) {
    float res = 1.0;
    float t = 0.02;
    for(int i = 0; i < SHADOWS; i++) {
        float h = map(ro + rd * t);
        res = min(res, 8.0 * h / t);
        t += clamp(h, 0.04, 0.2);
        if(res < 0.01 || t > 5.0) break;
    }
    return clamp(res, 0.0, 1.0);
}

*/

float softShadow(vec3 ro, vec3 rd, float k) {
    float res = 1.0;
    float ph = 1e20;
    float t = 0.02; 
    
    for(int i = 0; i < SHADOWS; i++) {
        float h = map(ro + rd * t);
        if(h < 0.001) return 0.0;
        
       
        float y = h * h / (2.0 * ph);
        float d = sqrt(max(0.0, h * h - y * y));
        res = min(res, k * d / max(0.0, t - y));
        
        ph = h;
        t += clamp(h, 0.04, 0.2); 
        if(res < 0.01 || t > 5.0) break;
    }
    return clamp(res, 0.0, 1.0);
}

float calcAO(in vec3 pos, in vec3 nor) {
    vec4 backupTrap = trap; 
    float occ = 0.0;
    float sca = 1.0;
    
 
    for(int i = 0; i < 10; i++) {
        float hr = 0.01 + 0.15 * float(i) / 4.0;
        vec3 aopos = pos + nor * hr;
        float dd = map(aopos);
        
        occ += (hr - dd) * sca;
        sca *= 0.95;
    }
    
    trap = backupTrap; 
    
   
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}
float calcSss(vec3 pos, vec3 lDir) {
    float sss = 0.0;
    float sca = 1.0;
    // Step *into* the object towards the light
    for(int i = 0; i < 4; i++) {
        float hr = 0.02 + 0.12 * float(i);
        float dd = map(pos + lDir * hr);
        sss += max(0.0, hr - dd) * sca;
        sca *= 0.6;
    }
    return clamp(sss, 0.0, 1.0);
}

vec3 calculateSurfaceColor(vec4 tm, vec4 am, vec3 ro, vec3 rd, vec3 lightPos, float t) {
    vec3 surfaceCol = vec3(0.0);
    vec3 p;
    float vTime = getVisualTime(iTime);
    
    for(int i = 0; i < 4; i++) {
        if(tm.x < 0.0) continue;

        trap = vec4(-1.0);
        p = ro + rd * tm.x;
        vec3 N = calcNormal(p);
        
        trap = vec4(0.0);
        map(p); 
        
        float morphState = getMorphBlend(vTime);
        vec4 tMap = mix(trap * 0.15, trap, morphState);
        
        vec3 L = lightPos - p;
        float distToLight = length(L);
        L /= distToLight;
        
        float detailFreq = mix(12.0, 45.0, morphState);
        float microDetail = sin(p.x * detailFreq) * sin(p.y * detailFreq) * sin(p.z * detailFreq);
        
        float shellMask = smoothstep(0.3, 0.7, sin(tMap.x * 3.0 + tMap.z * 2.0) * 0.5 + 0.5);
        
        float microGreeble = smoothstep(0.2, 0.8, sin(tMap.y * 12.0 + microDetail * 3.0) * 0.5 + 0.5);
        microGreeble *= (1.0 - shellMask);
        
        vec3 orgShell  = vec3(0.25, 0.04, 0.12);
        vec3 orgCavity = mix(vec3(0.08, 0.01, 0.03), vec3(0.35, 0.08, 0.15), microGreeble);
        
        vec3 mechShell  = vec3(0.12, 0.14, 0.18);
        vec3 mechCavity = mix(vec3(0.05, 0.06, 0.08), vec3(0.35, 0.4, 0.5), microGreeble);
        
        vec3 shellColor  = mix(orgShell, mechShell, morphState);
        vec3 cavityColor = mix(orgCavity, mechCavity, morphState);
        
        vec3 matColor = mix(cavityColor, shellColor, shellMask);
        
        float steelMask = mix(0.4 + microGreeble * 0.5, 1.8, shellMask); 
        
        float wave = sin(dot(p, vec3(1.1, -0.8, 1.5)) * 1.8 - vTime * 0.8 + tMap.y * 2.0);
        float energyPulse = pow(max(0.0, wave), 4.0) * (1.0 - shellMask * 0.75);
        matColor += mix(vec3(0.4, 0.05, 0.15), vec3(0.05, 0.4, 0.8), morphState) * energyPulse * 0.6;
        
        float ufoMask = clamp(trap.w, 0.0, 1.0);
        vec3 ufoGlow = vec3(0.0);
        
          if (ufoMask > 0.01) {
            vec3 ufoDarkMetal = vec3(0.12, 0.14, 0.18);
            vec3 ufoMagenta = vec3(0.85, 0.15, 0.65);
            
            float seamRing = pow(max(0.0, 1.0 - abs(N.y - 0.25) * 8.0), 6.0);
            vec3 ufoBase = mix(vec3(0.05, 0.06, 0.08), ufoDarkMetal, smoothstep(-0.2, 0.5, N.y));
            ufoBase = mix(ufoBase, ufoMagenta, seamRing * 0.6);
            
            matColor = mix(matColor, ufoBase, ufoMask);
            
            steelMask = mix(steelMask, 3.5, ufoMask); 
            
            vec3 ufoCyan  = vec3(0.05, 0.75, 0.95);
            
            float domeRingMask = pow(max(0.0, 1.0 - abs(N.y - 0.75) * 5.0), 8.0);
            float gentlePulse = 1.0 + 0.12 * sin(vTime * 2.5 - length(p.xz) * 4.0);
            
            ufoGlow = ufoCyan * domeRingMask * 2.0 * gentlePulse * ufoMask;
        }

        
        float trueAO = calcAO(p, N);

        float fakeAO = trueAO * clamp(0.5 + 0.5 * N.y, 0.2, 1.0);

        //float fakeAO = clamp(0.35 + 0.65 * N.y, 0.2, 1.0);
        //float shadow = cheapShadow(p + N * 0.005, L); 
        float shadow = softShadow(p + N * 0.005, L, 16.0);
        
        float lightAtten = exp(-distToLight * 0.15);
        
        float v = max(0.0, dot(N, -rd));
        vec3 ref = reflect(rd, N);
        float fre = pow(clamp(1.0 - v, 0.0, 1.0), 4.0);
        
        float diff = max(0.0, dot(N, L));
        vec3 scol = lightAtten * matColor * diff * shadow * fakeAO;
        scol += matColor * 0.05 * fakeAO;

        float sss = calcSss(p, L);
      
        vec3 sssColor = mix(vec3(0.8, 0.1, 0.2), vec3(0.1, 0.5, 0.9), morphState); 
 
        scol += sssColor * sss * 0.8 * lightAtten * (1.0 - shellMask * 0.5);

        vec3 headLightDir = -rd;
        float headDiff = max(0.0, dot(N, headLightDir));
     
        float headSpec = pow(max(0.0, dot(ref, headLightDir)), 24.0);
        
        float headAtten = 1.0 / (1.0 + tm.x * tm.x * 0.25); 
        vec3 headLightColor = vec3(0.85, 0.92, 1.0) * 1.25;
        
        scol += (matColor * headDiff * 0.5 + headLightColor * headSpec * 1.0 * steelMask) * headAtten;
        
        vec3 refSky = mix(vec3(0.02, 0.04, 0.08), vec3(0.12, 0.25, 0.45), smoothstep(-0.5, 0.8, ref.y));
        refSky += vec3(0.8, 0.85, 1.0) * pow(max(0.0, dot(ref, L)), 16.0) * shadow;
        
        scol += refSky * (0.2 + 0.8 * fre) * steelMask * fakeAO * 1.1;
        /*
        vec3 halfVec = normalize(L - rd);
        float specPower = mix(12.0, 32.0, morphState);
        float spec = pow(max(0.0, dot(N, halfVec)), specPower);
        
        float specIntensity = mix(0.4, 1.4, morphState);
        scol += vec3(0.9, 0.95, 1.0) * spec * shadow * steelMask * (specIntensity + microGreeble * 1.2);
        
        */

        vec3 halfVec = normalize(L - rd);
        
        float specPower = mix(16.0, 32.0, morphState);
        float spec = pow(max(0.0, dot(N, halfVec)), specPower);
        
        float specIntensity = mix(0.15, 1.4, morphState);
        
        scol += vec3(0.9, 0.95, 1.0) * spec * shadow * fakeAO * steelMask * (specIntensity + microGreeble * 1.2);
            
        scol += ufoGlow * fakeAO;
        
        float camAtten = 1.0 / (1.0 + tm.x * tm.x * 0.15);
        scol *= camAtten;
        
        surfaceCol = mix(scol, surfaceCol, am.x);
        am = am.yzwx;
        tm = tm.yzwx;
    }
    
    return surfaceCol;
}

vec4 renderScene(vec3 ro, vec3 rd, float slider, float time, float pxl, vec2 fragCoord) {
    initRNG(fragCoord);    
    vec3 lightPos = calcLightPath(time + 1.0), p;
    lightPos.z += slider;
    ro.z -= slider;
    float vTime = getVisualTime(iTime);
    
    float d = map(ro) * 0.8, t = d * nextRand(), nt = d, od = 1.0, ft = 0.0;
    
    vec4 col = vec4(0.0, 0.0, 0.0, 1.0);
    vec4 am = vec4(-1.0), tm = vec4(-1.0);
    
    for(int i = 0; i < RAY_STEPS; i++) {
        if(nt > t + ft) {
            p = ro + rd * (t + ft);
            p += (lightPos - p) * (-p.z) / (lightPos.z - p.z);        
        } else {
            p = ro + rd * t;
        }
        
        d = map(p);
        
        if(nt > t + ft) {
            float dL = 0.05 * length(ro + rd * (t + ft) - lightPos);
            
            vec3 scatterCol = 0.5 + 0.5 * cos((t + ft) * 1.0 + vec3(0.5, 2.25, 4.25));
            float beatPulse = exp(-fract(vTime * 2.0) * 4.0);
            scatterCol *= 1.0 + (beatPulse * 2.5); 
            
            float fogDensity = fogmap(p, time);
            scatterCol += scatterCol * fogDensity * 12.0;
            
            col.rgb += col.a * scatterCol * exp(-dL * 40.0) * smoothstep(0.0, 0.01, d) * 0.5;
            
            //col.rgb += col.a * scatterCol * exp(-dL * 40.0) * smoothstep(0.0, 0.01, d) * 0.15;
    
    
            if(t + ft + dL > nt) {
                ft = 0.0;
                t = nt;
                if(t > 20.0) break;
            } else {
                ft += dL;
            }
        } else {
            if(d < od && tm.w < 0.0) {
                float alpha = clamp(d / (pxl * t), 0.0, 1.0);
                if(alpha < 0.95) {
                    am = vec4(alpha, am.xyz);
                    tm = vec4(t, tm.xyz);
                    col.a *= alpha;
                }
            }
            od = d;
            nt = t + d * (0.6 + 0.2 * nextRand());
        }
    }
    
    vec3 surfaceCol = calculateSurfaceColor(tm, am, ro, rd, lightPos, t);
    col.rgb += surfaceCol;
    
    return vec4(col.rgb, t);
}


void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 jitter = getJitter(iFrame);
    vec2 p = (fragCoord - 0.5 * iResolution.xy + jitter) / iResolution.y;
    
    vec3 ro, ta; float roll, focalLength;
    getCamera(iTime, ro, ta, roll, focalLength);
    
    mat3 camMat = calcLookAtMatrix(ro, ta, roll);
    vec3 rd = normalize(camMat * vec3(p.xy, focalLength));

    float vTime = getVisualTime(iTime);
    float tm = mod(vTime, 18.85);

    vec4 scene = renderScene(ro, rd, 0.3, tm * 0.12, 3.0 / iResolution.y, fragCoord);
    float depth = (scene.a > 0.0 && scene.a < 20.0) ? scene.a : 20.0;
    
    vec3 finalColor = max(vec3(0.0), scene.rgb);
    if (isnan(finalColor.x) || isnan(finalColor.y) || isnan(finalColor.z)) {
        finalColor = vec3(0.0);
    }
    
    float fadeOut = 1.0 - smoothstep(165.0, 180.0, iTime);
    finalColor *= fadeOut;
    
    fragColor = vec4(finalColor, depth);
}