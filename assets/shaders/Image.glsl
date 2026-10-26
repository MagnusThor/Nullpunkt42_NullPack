vec2 getP(vec2 textUV, vec2 off, float scale, float fade) {
    float warp = sin(textUV.y * 12.0 - iTime * 2.5) * cos(textUV.x * 8.0 + iTime * 1.5);
    vec2 shift = vec2(pow(1.0 - fade, 3.0) * warp * 0.06, 0.0);
    return ((textUV - off) + shift) / scale;
}

float getChar(vec2 p, int c, float fade) {
    float wobble = smoothstep(1.5, 3.0, iTime) * (1.0 + iFreqs.w * 0.5);
    p.x += sin(p.y * 12.0 + iTime * 2.0) * 0.005 * wobble;
    p.y += cos(p.x * 12.0 - iTime * 1.5) * 0.003 * wobble;

    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) return 0.0;
    
    vec2 uv = p / 16.0 + vec2(float(c % 16), float(15 - c / 16)) / 16.0;
    float d = texture(iChannel3, uv).r;
    
    float particleNoise = fract(sin(dot(p * 43.7, vec2(12.9898, 78.233))) * 43758.5453);
    float assembleThreshold = 1.0 - fade; 
    
    float particleMask = smoothstep(assembleThreshold - 0.15, assembleThreshold + 0.05, d + (particleNoise - 0.5) * 0.4);
    
    float af = fwidth(d);
    float core = smoothstep(0.5 - af * 1.5, 0.5 + af * 1.5, d);
    float bloom = smoothstep(0.2, 0.8, d) * 0.7;
    
    return (core + bloom) * particleMask; 
}

vec4 renderBigBang(vec2 fragCoord, float time) {
    vec2 u = (fragCoord - iResolution.xy * 0.5) / iResolution.y;
    vec4 o = vec4(0.0);
    float d = 0.0, s = 0.0;
    
    for (float i = 0.0; i < 40.0; i++) {
        vec3 p = vec3(u * d, d);
        s = p.x + 2.0;
        
        for (float n = 0.6; n < 24.0; n *= 2.0) {
            s -= abs(dot(sin(p.z + time + p * n), vec3(0.7))) / n;
        }
        
        s = 0.03 + abs(s) * 0.13;
        d += s;
        o += 1.0 / s;
    }
    
    u.y += 0.5;
    return tanh(vec4(3.0, 1.0, 9.0, 1.0) * o / d / 2000.0 / max(0.0001, length(sin(time * 0.3) * u)));
}

vec3 DpthFld(sampler2D iCh, vec2 uv, vec2 caOffset) {
    float depth = texture(iCh, uv).a;
    const float focD = 3.5; 
    const float coc = 1.5;  
    
    float l = abs(depth - focD) - coc;
    float dof = clamp(l / coc, 0.0, 1.0); 
    dof = mix(dof * 2.0, smoothstep(0.2, 0.6, abs(uv.y - 0.5)) * 4.0, 0.5);
    
    vec3 acc = vec3(0.0);
    float totWeight = 0.0; 
    vec2 iRes = vec2(iResolution.x / iResolution.y, 1.0) * 450.0;
    
    for(int i = 0; i < 25; i++) {
        vec2 offset = (vec2(float(i / 5), float(i % 5)) - 2.0) / iRes * dof;
        vec2 sUV = clamp(uv + offset, 0.0, 1.0);
        
        vec3 smpl = vec3(
            texture(iCh, clamp(sUV - caOffset, 0.0, 1.0)).r,
            texture(iCh, sUV).g,
            texture(iCh, clamp(sUV + caOffset, 0.0, 1.0)).b
        );
        
        float luma = dot(smpl, vec3(0.299, 0.587, 0.114));
        float w = 1.0 / (1.0 + luma); 
        
        acc += smpl * w;
        totWeight += w;
    }
    
    return acc / totWeight;
}

void mainImage(out vec4 fragColor, vec2 fragCoord) {
    vec2 ts = 1.0 / iResolution.xy;
    vec2 originalUV = fragCoord * ts;
    vec2 uv = originalUV;
    float screenAspect = iResolution.x / iResolution.y;

    float barHeight = max(0.0, (1.0 - (screenAspect / 2.35)) / 2.0);
    if (uv.y < barHeight || uv.y > 1.0 - barHeight) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return; 
    }
    
    if (iTime > 180.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
    
    vec2 vUV = uv - 0.5;
    float r2 = dot(vUV, vUV);
    uv += vUV * r2 * 0.08; 
    
    float vTime = getVisualTime(iTime);
    float cutDuration = 8.0; 
    float cutTime = mod(vTime, cutDuration);
    
    float cutImpact = exp(-cutTime * 20.0);
    uv -= vUV * cutImpact * 0.015;

    float gTime = floor(vTime * 8.0); 
    float gTrigger = fract(sin(gTime * 13.13) * 43758.5);
    
    float isGlitch = step(0.98, gTrigger);
    
    vec2 caOffset = vUV * r2 * 0.01; 
    
    if (isGlitch > 0.0) {
        vec2 grid = vec2(floor(uv.x * mix(10.0, 40.0, gTrigger)), floor(uv.y * mix(8.0, 60.0, fract(gTrigger * 2.1))));
        float blockNoise = fract(sin(dot(grid, vec2(12.9898, 78.233)) + gTime) * 43758.5453);
        
        if (blockNoise > 0.6) {
            uv.x += (blockNoise - 0.8) * 0.08 * (1.0 + iFreqs.y * 0.5);
            caOffset += vec2((blockNoise - 0.5) * 0.03, 0.0) * (1.0 + iFreqs.y * 1.5); 
        }
        
        float tearNoise = fract(sin(uv.y * 250.0 + iTime * 5.0) * 43758.5);
        if (tearNoise > 0.85) {
            uv.x += (tearNoise - 0.92) * 0.04 * (1.0 + iFreqs.z);
            caOffset.x -= 0.01 * (1.0 + iFreqs.z * 2.0); 
        }
    }

    float beatPulse = iTime > 20.0 ? (exp(-fract(iSync.y) * 4.0) * 0.5 + iFreqs.x * 0.8) : 0.0; 
    caOffset += vUV * (cutImpact * 0.01 + beatPulse * 0.004); 

    float gravPhase = smoothstep(17.5, 20.0, iTime) * (1.0 - step(20.0, iTime));
    if (gravPhase > 0.0) {
        vec2 gravCenter = vUV;
        gravCenter.x *= screenAspect;
        float distToCenter = length(gravCenter);
        
        float suction = exp(-distToCenter * 4.0) * 0.3 * pow(gravPhase, 4.0);
        float ripples = sin(distToCenter * 60.0 - iTime * 80.0) * 0.04 * gravPhase;
        
        vec2 pullDir = normalize(vUV + 0.0001); 
        uv -= pullDir * (suction + ripples);
    }

    vec3 sceneCol = DpthFld(iChannel1, uv, caOffset);

    vec3 finalColor = sceneCol * 0.8; 
    
    float luminance = dot(finalColor, vec3(0.299, 0.587, 0.114));
    finalColor = max(vec3(0.0), mix(vec3(luminance), finalColor, 1.3) * vec3(1.02, 0.98, 0.96));
    
    float vignette = smoothstep(1.4, 0.3, length(vUV * 2.0));
    finalColor *= mix(0.3, 1.0, vignette);

    float sceneVisibility = 0.0;
    if (iTime < 20.0) {
        float flash500ms = smoothstep(0.5, 0.0, mod(iTime, 2.0));
        float preFade = smoothstep(18.0, 20.0, iTime);
        sceneVisibility = max(flash500ms * 0.6, preFade);
    } else {
        sceneVisibility = 1.0;
        float strobe = step(0.5, fract(iSync.y * 2.0)) * 0.15 * (1.0 + iFreqs.w);
        
        sceneVisibility *= (1.0 + strobe + cutImpact * 0.2); 
    }
    
    if (iTime >= 165.0 && iTime <= 175.0) { 
        sceneVisibility *= 1.0 - smoothstep(165.0, 175.0, iTime); 
    } else if (iTime > 175.0) { 
        sceneVisibility = 0.0; 
    }

    finalColor *= sceneVisibility;

    float bangWeight = 1.0 - sceneVisibility;
    if (bangWeight > 0.001) {
        vec3 bangCol = renderBigBang(uv * iResolution.y + iResolution.xy * 0.5, iTime).rgb;
        finalColor += bangCol * bangWeight;
    }

    float topEdge = 1.0 - barHeight;
    float textIntensity = 0.0;
    vec2 p; float m;

    float textZoomTime = vTime > 40.0 ? max(0.0, mod(vTime, 20.0) - 5.0) : vTime;

    vec2 textUV = originalUV;
    vec2 zoomAnchor = vec2(0.1, 0.5); 
    textUV -= zoomAnchor;
    textUV *= 1.0 - (textZoomTime * 0.005); 
    textUV += zoomAnchor;
    textUV.x *= screenAspect; 
    
    if (iTime < 20.0) {
        float f0 = smoothstep(16.0, 16.5, iTime) * (1.0 - smoothstep(17.5, 18.0, iTime));
        if (f0 > 0.0) {
            m = 0.0; 
            p = getP(textUV, vec2(0.5 * screenAspect - 0.525, 0.5), 0.05, f0); 
            int t[42] = int[](73,78,32,77,69,77,79,82,89,32,79,70,32,83,153,82,69,78,32,49,57,54,53,45,48,49,45,48,53,32,45,32,50,48,50,54,45,48,57,45,50,55);
            for(int i=0; i<42; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], f0)); p.x-=0.5; } }
            textIntensity += m * f0 * 2.0; 
        }

        float f1 = smoothstep(1.5, 2.5, iTime) * (1.0 - smoothstep(5.0, 6.0, iTime));
        if (f1 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.15), 0.08, f1);
            int t[16] = int[](66,101,121,111,110,100,32,116,104,101,32,77,111,100,101,108);
            for(int i=0; i<16; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], f1)); p.x-=0.5; } }
            textIntensity += m * f1;
        }

        float f2 = smoothstep(3.5, 4.5, iTime) * (1.0 - smoothstep(7.0, 8.0, iTime));
        if (f2 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.28), 0.04, f2);
            int t[25] = int[](97,32,78,117,108,108,112,117,110,107,116,32,52,50,32,112,114,111,100,117,99,116,105,111,110);
            for(int i=0; i<25; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], f2)); p.x-=0.5; } }
            textIntensity += m * f2;
        }

        float f3 = smoothstep(5.5, 6.5, iTime) * (1.0 - smoothstep(9.0, 10.0, iTime));
        if (f3 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.38), 0.03, f3);
            int t[19] = int[](114,101,108,101,97,115,101,100,32,84,82,83,65,67,32,50,48,50,54);
            for(int i=0; i<19; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], f3)); p.x-=0.5; } }
            textIntensity += m * f3;
        }

        float f4 = smoothstep(10.0, 11.0, iTime) * (1.0 - smoothstep(13.0, 14.0, iTime));
        if (f4 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.48), 0.03, f4);
            int t[11] = int[](97, 32, 49, 54, 107, 32, 105, 110, 116, 114, 111);
            for(int i=0; i<11; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], f4)); p.x-=0.5; } }
            textIntensity += m * f4;
        }
    }
    
    if (vTime >= 10.0) {
        float qNew1 = smoothstep(15.0, 17.0, vTime) * (1.0 - smoothstep(23.0, 25.0, vTime));
        if (qNew1 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.25), 0.06, qNew1);
            int t[36] = int[](65,32,115,101,97,32,111,102,32,115,112,97,99,101,32,119,101,32,99,97,110,110,111,116,32,99,111,109,112,114,101,104,101,110,100,46);
            for(int i=0; i<36; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], qNew1)); p.x-=0.5; } }
            textIntensity += m * qNew1;
        }

        float q1 = smoothstep(30.0, 32.0, vTime) * (1.0 - smoothstep(38.0, 40.0, vTime));
        if (q1 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.25), 0.06, q1);
            int t[29] = int[](82,101,97,108,105,116,121,32,116,114,97,110,115,99,101,110,100,115,32,116,104,101,32,109,111,100,101,108,46);
            for(int i=0; i<29; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], q1)); p.x-=0.5; } }
            textIntensity += m * q1;
        }

        float q2 = smoothstep(50.0, 52.0, vTime) * (1.0 - smoothstep(58.0, 60.0, vTime));
        if (q2 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.25), 0.06, q2);
            int t[42] = int[](67,111,110,115,99,105,111,117,115,110,101,115,115,32,105,115,32,110,97,116,117,114,101,44,32,111,98,115,101,114,118,105,110,103,32,105,116,115,101,108,102,46);
            for(int i=0; i<42; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], q2)); p.x-=0.5; } }
            textIntensity += m * q2;
        }

        float qNew2 = smoothstep(62.0, 64.0, vTime) * (1.0 - smoothstep(70.0, 72.0, vTime));
        if (qNew2 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.25), 0.06, qNew2);
            int t[29] = int[](84,104,101,32,119,111,114,108,100,32,105,115,32,110,111,116,32,97,110,32,105,108,108,117,115,105,111,110,46);
            for(int i=0; i<29; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], qNew2)); p.x-=0.5; } }
            textIntensity += m * qNew2;
        }

        float q3 = smoothstep(75.0, 77.0, vTime) * (1.0 - smoothstep(83.0, 85.0, vTime));
        if (q3 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.25), 0.06, q3);
            int t[28] = int[](82,101,97,108,105,116,121,32,110,101,101,100,115,32,110,111,32,115,105,109,117,108,97,116,105,111,110,46);
            for(int i=0; i<28; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], q3)); p.x-=0.5; } }
            textIntensity += m * q3;
        }

        float q4 = smoothstep(105.0, 107.0, vTime) * (1.0 - smoothstep(113.0, 115.0, vTime));
        if (q4 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.25), 0.06, q4);
            int t[31] = int[](77,97,116,104,32,100,101,115,99,114,105,98,101,115,46,32,82,101,97,108,105,116,121,32,101,120,105,115,116,115,46);
            for(int i=0; i<31; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], q4)); p.x-=0.5; } }
            textIntensity += m * q4;
        }

        float q5 = smoothstep(118.0, 119.0, vTime) * (1.0 - smoothstep(124.0, 125.0, vTime));
        if (q5 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.25), 0.06, q5);
            int t[27] = int[](78,97,116,117,114,101,32,105,115,32,110,111,116,32,97,110,32,97,108,103,111,114,105,116,104,109,46);
            for(int i=0; i<27; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], q5)); p.x-=0.5; } }
            textIntensity += m * q5;
        }

        float q6 = smoothstep(128.0, 129.0, vTime) * (1.0 - smoothstep(134.0, 135.0, vTime));
        if (q6 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.25), 0.06, q6);
            int t[26] = int[](77,97,116,116,101,114,32,105,115,32,116,104,101,32,111,110,108,121,32,109,101,100,105,117,109,46);
            for(int i=0; i<26; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], q6)); p.x-=0.5; } }
            textIntensity += m * q6;
        }

        float q7 = smoothstep(138.0, 139.0, vTime) * (1.0 - smoothstep(143.0, 144.0, vTime));
        if (q7 > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.25), 0.06, q7);
            int t[32] = int[](66,101,121,111,110,100,32,116,104,101,32,109,111,100,101,108,32,108,105,101,115,32,116,104,101,32,119,111,114,108,100,46);
            for(int i=0; i<32; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], q7)); p.x-=0.5; } }
            textIntensity += m * q7;
        }

        float qCred = smoothstep(146.5, 147.2, vTime) * (1.0 - smoothstep(152.0, 154.0, vTime));
        if (qCred > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.22), 0.04, qCred);
            int c1[26] = int[](99,111,100,101,58,32,100,97,116,104,111,114,32,38,32,97,114,116,104,117,114,32,116,101,110,116);
            for(int i=0; i<26; i++) { if(c1[i]==32) p.x-=0.5; else { m=max(m,getChar(p,c1[i], qCred)); p.x-=0.5; } }
            textIntensity += m * qCred;

            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.32), 0.04, qCred);
            int c2[24] = int[](109,117,115,105,99,58,32,80,67,114,117,115,104,32,38,32,77,114,32,76,97,105,110,101);
            for(int i=0; i<24; i++) { if(c2[i]==32) p.x-=0.5; else { m=max(m,getChar(p,c2[i], qCred)); p.x-=0.5; } }
            textIntensity += m * qCred;

            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.42), 0.04, qCred);
            int c3[17] = int[](100,105,114,101,99,116,105,111,110,58,32,100,97,116,104,111,114);
            for(int i=0; i<17; i++) { if(c3[i]==32) p.x-=0.5; else { m=max(m,getChar(p,c3[i], qCred)); p.x-=0.5; } }
            textIntensity += m * qCred;
        }

        float qGreet = smoothstep(156.0, 157.0, vTime) * (1.0 - smoothstep(163.0, 164.0, vTime));
        if (qGreet > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.5 * screenAspect - 0.19, topEdge - 0.15), 0.04, qGreet);
            int g1[19] = int[](71,82,69,69,84,73,78,71,83,32,38,32,83,65,76,85,84,69,83); 
            for(int i=0; i<19; i++) { if(g1[i]==32) p.x-=0.5; else { m=max(m,getChar(p,g1[i], qGreet)); p.x-=0.5; } }
            textIntensity += m * qGreet;

            m = 0.0; p = getP(textUV, vec2(0.5 * screenAspect - 0.20, topEdge - 0.25), 0.03, qGreet);
            int g2[26] = int[](80,97,114,116,110,101,114,115,44,32,70,97,109,105,108,121,44,32,102,114,105,101,110,100,115,44); 
            for(int i=0; i<26; i++) { if(g2[i]==32) p.x-=0.5; else { m=max(m,getChar(p,g2[i], qGreet)); p.x-=0.5; } }
            textIntensity += m * qGreet;

            m = 0.0; p = getP(textUV, vec2(0.5 * screenAspect - 0.17, topEdge - 0.35), 0.03, qGreet);
            int g3[22] = int[](115,99,101,110,101,114,115,32,97,110,100,32,97,108,108,32,112,101,111,112,108,101); 
            for(int i=0; i<22; i++) { if(g3[i]==32) p.x-=0.5; else { m=max(m,getChar(p,g3[i], qGreet)); p.x-=0.5; } }
            textIntensity += m * qGreet;

            m = 0.0; p = getP(textUV, vec2(0.5 * screenAspect - 0.18, topEdge - 0.45), 0.03, qGreet);
            int g4[26] = int[](111,110,32,111,117,114,32,112,108,97,99,101,32,99,97,108,108,101,100,32,69,97,114,116,104,46); 
            for(int i=0; i<26; i++) { if(g4[i]==32) p.x-=0.5; else { m=max(m,getChar(p,g4[i], qGreet)); p.x-=0.5; } }
            textIntensity += m * qGreet;
        }

        float qEnd = smoothstep(165.5, 166.5, vTime) * (1.0 - smoothstep(168.5, 169.5, vTime));
        if (qEnd > 0.0) {
            m = 0.0; p = getP(textUV, vec2(0.07 * screenAspect, topEdge - 0.25), 0.06, qEnd);
            int t[8] = int[](84,104,101,32,101,110,100,46);
            for(int i=0; i<8; i++) { if(t[i]==32) p.x-=0.5; else { m=max(m,getChar(p,t[i], qEnd)); p.x-=0.5; } }
            textIntensity += m * qEnd;
        }
    }

    float textCore = min(textIntensity, 1.0);
    finalColor = mix(finalColor, vec3(0.95, 0.98, 1.0), textCore * 0.95);
    finalColor += vec3(0.1, 0.6, 1.0) * textIntensity * 0.35; 

    float noise = fract(sin(dot(uv + iTime, vec2(12.9898, 78.233))) * 43758.5453);
    finalColor += (noise - 0.5) * 0.05;
    
    finalColor *= smoothstep(0.0, 1.0, iTime);

    finalColor = max(vec3(0.0), finalColor);
    finalColor = clamp((finalColor * (2.51 * finalColor + 0.03)) / (finalColor * (2.43 * finalColor + 0.59) + 0.14), 0.0, 1.0);
    
   
    fragColor = vec4(finalColor, 1.0);
}