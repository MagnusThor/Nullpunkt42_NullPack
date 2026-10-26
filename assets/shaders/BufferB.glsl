// Transpiled from TinyShade 1001:0841
const int NUM_PARTICLES = 150;

vec3 getParticlePos(float id, float time, float morph) {
    float seed1 = fract(id * 0.1337);
    float r1 = 0.3 + seed1 * 1.5;
    float a1 = time * (0.4 + seed1 * 0.4) + id;
    vec3 orgPath = vec3(
        cos(a1) * r1, 
        sin(a1) * r1, 
        mod(id * 5.0 - time * 2.5, 40.0) - 20.0
    );
    
    float seed2 = fract(id * 0.8123);
    float r2 = 2.5 + seed2 * 1.2; 
    /*
    float a2 = time * (0.15 + seed2 * 0.1) + id;
    vec3 mechPath = vec3(
        cos(a2) * r2, 
        0.2 + sin(time * 0.5 + id) * 0.5, 
        sin(a2) * r2
    );
    */

    float a2 = time * (0.15 + seed2 * 0.1) + id * 2.39996; 

    vec3 mechPath = vec3(
        cos(a2) * r2, 
        0.2 + sin(time * 0.5 + seed2 * 6.28) * 0.5, 
        sin(a2) * r2
    );

    return mix(orgPath, mechPath, morph);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    vec2 pUV = (fragCoord - 0.5 * res) / iResolution.y;
    
    vec4 fractalData = texture(iChannel1, uv);
    float sceneDepth = fractalData.a;
    if (sceneDepth <= 0.01) sceneDepth = 9999.0;
    
    float vTime = getVisualTime(iTime);
    float camTime = vTime > 110.0 ? 16.0 + (vTime - 125.0) : vTime;
    
    vec3 ro1, ta1; float roll1; setCamera(ro1, ta1, roll1, camTime);
    vec3 ro2, ta2; float roll2, fl2; setMechCamera(vTime, ro2, ta2, roll2, fl2);

    float blend = getMorphBlend(vTime); 
    vec3 ro = mix(ro1, ro2, blend);
    vec3 ta = mix(ta1, ta2, blend);
    float roll = mix(roll1, roll2, blend);
    float focalLength = mix(1.8, fl2, blend);

    mat3 camMat = calcLookAtMatrix(ro, ta, roll);
    vec3 rd = normalize(camMat * vec3(pUV, focalLength));

    vec3 currentParticles = vec3(0.0);
    
    for (int i = 0; i < NUM_PARTICLES; i++) {
        vec3 pPos = getParticlePos(float(i), vTime, blend);
        
        vec3 L = pPos - ro;
        float t = dot(L, rd);
        
        if (t > 0.1) {
            
            float occlusion = smoothstep(-0.2, 0.2, sceneDepth - t);
            
            if (occlusion > 0.0) {
                float distToRay = length(pPos - (ro + rd * t));
                
                float core = smoothstep(0.01, 0.0, distToRay);
                float glow = 0.00005 / (distToRay * distToRay + 0.00005);
                
                vec3 pCol = mix(vec3(0.05, 0.8, 1.0), vec3(1.0, 0.1, 0.6), fract(float(i) * 0.618));
                float beatPulse = exp(-fract(vTime * 2.0) * 4.0); 
                pCol *= 1.0 + (beatPulse * 2.5);
                
                float atten = exp(-t * 0.15);
                
                currentParticles += pCol * (core + glow) * atten * occlusion;
            }
        }
    }

    vec2 center = uv - 0.5;
    vec2 trailUV = 0.5 + center * 1.003; 
    
    vec3 history = texture(iChannel0, trailUV).rgb;
    float decay = .25; 
    
    vec3 finalColor = currentParticles + (history * decay);
    fragColor = vec4(finalColor, 1.0);
}