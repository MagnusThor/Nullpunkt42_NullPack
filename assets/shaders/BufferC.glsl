// Transpiled from TinyShade 1001:0841
float getBoomTime(float t) {
    if (t < 20.0) return mod(t, 2.0); // Intro
    if (t > 84.0 && t < 126.0) return mod(t, 8.0); // Middle
    if (t >= 150.0 && t < 180.0) return mod(t, 2.0); // Outro escalation
    float mt = t - 20.0;
    if (mt >= 16.0 && mt < 24.0) return mod(mt, 8.0); // Percussion section
    return 999.0;
}

void mainImage(out vec4 fragColor, vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    
   
    float shockTime = getBoomTime(iTime);
    float isShock = (shockTime < 0.3) ? 1.0 : 0.0;
    
    vec2 sampleUV = uv;
    float shockwaveIntensity = 0.0;
    
    if (isShock > 0.0) {
        float progress = shockTime / 0.3; 
        vec2 p = uv - 0.5;
        float dist = length(p);
        
        float wave = sin(dist * 20.0 - progress * 15.0) * exp(-progress * 4.0);
        sampleUV += normalize(p) * wave * 0.05;
        shockwaveIntensity = exp(-progress * 6.0) * 0.4;
    }

    vec4 fractalFrame = texture(iChannel0, sampleUV);
    vec4 particleFrame = texture(iChannel1, sampleUV);
    
    vec3 finalCol = fractalFrame.rgb;
    finalCol += vec3(0.4, 0.7, 1.0) * shockwaveIntensity;
    finalCol += particleFrame.rgb;
    
    fragColor = vec4(finalCol, fractalFrame.a);
}