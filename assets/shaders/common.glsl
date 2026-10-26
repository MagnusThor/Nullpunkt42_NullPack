//.1
const int NUM_OF_SEQ = 10;

const vec3 SEQ[10] = vec3[](
    vec3(20000.0, 0.0, 11.0),
    vec3(10000.0, 20000.0, 12.0),
    vec3(20000.0, 30000.0, 13.0),
    vec3(20000.0, 50000.0, 4.0),
    vec3(20000.0, 70000.0, 15.0),
    vec3(20000.0, 90000.0, 6.0),
    vec3(20000.0, 110000.0, 7.0),
    vec3(10000.0, 130000.0, 8.0),
    vec3(10000.0, 140000.0, 9.0),
    vec3(30000.0, 150000.0, 10.0)
);

struct SceneContext {
    int id;
    int flags;
    float prog;
    float localTime;
    bool state;
};

SceneContext evaluateConductor(float globalTime, int count) {
    SceneContext ctx;
    ctx.id = 0; ctx.flags = 0; ctx.prog = 0.0; ctx.localTime = 0.0; ctx.state = false;

    float totalDuration = 0.0;
    for (int i = 0; i < NUM_OF_SEQ; i++) {
        if (i >= count) break;
        totalDuration += SEQ[i].x;
    }

    float p = mod(globalTime * 1000.0, totalDuration);

    for (int i = 0; i < NUM_OF_SEQ; i++) {
        if (i >= count) break;
        vec3 v = SEQ[i];

        if (p >= v.y && p < v.y + v.x) {
            ctx.prog = (p - v.y) / v.x;
            ctx.localTime = (p - v.y) / 1000.0; 
            ctx.id = int(v.z) % 10;
            ctx.flags = int(v.z) / 10;
            ctx.state = true;
            break;
        }
    }
    return ctx;
}

float getVisualTime(float t) {
    if (t < 20.0) return t * 0.5; 
    return t - 10.0;              
}

vec4 trap = vec4(0.0);
float rngState;
mat2 rot(float a) { float sc = sin(a), cc = cos(a); return mat2(cc, -sc, sc, cc); }

void initRNG(vec2 seedCoord) { 
    rngState = fract(sin(dot(seedCoord, vec2(113.421, 17.329))) * 3134.1234); 
}

float nextRand() { 
    return fract(sin(rngState++) * 3143.45345); 
}

mat3 calcLookAtMatrix(in vec3 ro, in vec3 ta, in float roll) {
    vec3 ww = normalize(ta - ro);
    vec3 uu = normalize(cross(ww, vec3(sin(roll), cos(roll), 0.0)));
    vec3 vv = normalize(cross(uu, ww));
    return mat3(uu, vv, ww);
}

vec3 calcLightPath(float t) {
    float speed = t * 0.35; 
    float radius = 1.4 + sin(t * 1.3) * 0.4; 
    float x = cos(speed) * radius;
    float z = sin(speed) * radius;
    float y = 1.8 + sin(t * 0.8) * 0.6; 
    return vec3(x, y, z);
}

vec3 ufoPos(int i, float T, out float angle) {
    float fi = float(i); angle = T * (0.35 + fi * 0.08) + fi * 2.094;
    return vec3(sin(angle) * (2.8 + 0.6 * sin(T * 0.4 + fi)), 0.4 + 0.8 * sin(T * 0.6 + fi * 1.5), cos(angle) * (2.8 + 0.6 * sin(T * 0.4 + fi)));
}

void setMechCamera(float T, out vec3 ro, out vec3 ta, out float roll, out float fl) {
    if (T >= 90.0 && T < 110.0) {
        float localT = T - 90.0;
        float progress = localT * 0.22;
        
        ro = vec3(-4.2 + progress * 0.8, 0.25 + sin(localT * 0.2) * 0.15, -1.8 + progress * 0.6);
        
        vec3 lightPos = calcLightPath(T);
        ta = mix(vec3(0.8, 0.3, 1.2), lightPos * 0.5, 0.4);
        
        roll = -0.12 + sin(localT * 0.15) * 0.08;
        fl = 1.5;
        return;
    }

    float cut = floor((T - 3.0) / 4.0); float lt = T - (3.0 + cut * 4.0); float shotType = mod(cut, 3.0); 
    if (shotType < 1.0) {
        float camT = T * 0.35; float arm = mix(3.5, 5.0, 0.5 + 0.5 * sin(T * 0.25)); 
        ta = vec3(0.8 * sin(camT * 0.5), 0.3 + 0.5 * cos(camT * 0.7), 0.8 * cos(camT * 0.4));
        ro = ta + vec3(arm * cos((-10.0 + 15.0 * sin(camT * 0.6))*0.017) * sin((camT * 25.0 + 15.0 * sin(camT * 0.4))*0.017), -arm * sin((-10.0 + 15.0 * sin(camT * 0.6))*0.017), arm * cos((-10.0 + 15.0 * sin(camT * 0.6))*0.017) * cos((camT * 25.0 + 15.0 * sin(camT * 0.4))*0.017));
        roll = (camT * 1.5 + sin(camT)) * 0.0174533; fl = 1.4; 
    } else if (shotType < 2.0) {
        float ang; vec3 tp = ufoPos(int(mod(floor(cut * 0.5), 3.0)), T, ang);
        vec3 rad = vec3(sin(ang), 0.0, cos(ang)); vec3 tang = vec3(rad.z, 0.0, -rad.x);      
        ro = tp + (rad * 1.2 - tang * 0.9 + vec3(0.0, 0.3, 0.0)) * mix(1.0, 0.75, lt / 4.0);
        ta = tp + tang * 0.4; roll = sin(T * 0.7) * 0.06; fl = 1.4; 
    } else {
        float angM = T * 0.25 + cut * 1.5; float radC = 3.2 + 0.4 * sin(T * 0.5);
        ro = vec3(sin(angM) * radC, 0.8 + 0.6 * cos(T * 0.375), cos(angM) * radC);
        ta = vec3(0.5 * sin(T * 0.3), 0.2 * cos(T * 0.4), 0.5 * cos(T * 0.3)); 
        roll = sin(T * 0.4) * 0.08; fl = 1.5; 
    }
}

void setCamera(out vec3 camPos, out vec3 camTar, out float camRoll, in float time) {
   
   /*
   if (time >= 90.0 && time < 110.0) {
        float localT = time - 90.0;
        float progress = localT * 0.22;
        
        camPos = vec3(-4.2 + progress * 0.8, 0.25 + sin(localT * 0.2) * 0.15, -1.8 + progress * 0.6);
        
        vec3 lightPos = calcLightPath(time);
        camTar = mix(vec3(0.8, 0.3, 1.2), lightPos * 0.5, 0.4);
        
        camRoll = -0.12 + sin(localT * 0.15) * 0.08;
        return; 
    }
    */

    float cutDuration = 8.0; 
    float localTime = mod(time, cutDuration);
    
    int totalIdx = int(time / cutDuration); 
    int camIdx = totalIdx % 18; 
    
    float t = time * 0.25;
    camRoll = sin(time * 0.2) * 0.05;
    
    vec3 lightPos = calcLightPath(time); 
    
    if (camIdx == 0) {
        float an = 0.3 * t + 10.0;
        camPos = vec3(3.2 * sin(an), 0.5, 3.2 * cos(an));
        camTar = vec3(0.0, 0.2, 0.0);
    } 
    else if (camIdx == 1) {
        float progress = localTime * 0.25; 
        camPos = vec3(-4.5 + progress, 0.2, 4.0 - progress * 0.8);
        camTar = vec3(0.0, 0.2, 0.5); 
    } 
    else if (camIdx == 2) {
        float progress = localTime * 0.3;
        float sway = sin(localTime * 0.8) * 0.6;
        camPos = vec3(-3.2 + progress, 0.2 + 0.15 * cos(localTime * 1.2), 2.5 + sway);
        camTar = lightPos * 0.3;
    } 
    else if (camIdx == 3) {
        camPos = vec3(-2.8, 0.3, -2.5 + (localTime * 0.5));
        camTar = vec3(0.5, 0.1, 1.5);
    }
    else if (camIdx == 4) {
        float slowForward = localTime * 0.09;
        camPos = vec3(-2.5 + slowForward * 0.6, 0.4, 3.5 - slowForward * 0.8);
        camTar = vec3(0.2, 0.0, 0.1);
    }
    else if (camIdx == 5) {
        float height = 4.5 - (localTime * 0.35); 
        camPos = vec3(1.5 * sin(t * 1.5), height, 1.5 * cos(t * 1.5));
        camTar = vec3(0.0, -0.5, 0.0);
    }
    else if (camIdx == 6) {
        camPos = vec3(1.5 + (localTime * 0.3), 0.4, 1.5 - (localTime * 0.2));
        camTar = lightPos * 0.4;
    }
    else if (camIdx == 7) {
        float an = 1.5 * t;
        camPos = vec3(2.8 * sin(an), 0.15, 2.8 * cos(an));
        camTar = vec3(0.2, 0.9, 0.0);
    }
    else if (camIdx == 8) {
        camPos = vec3(2.5, 0.3, -3.0 + (localTime * 0.5));
        camTar = lightPos * 0.5;
    }
    else if (camIdx == 9) {
        float an = -0.3 * t - 10.0;
        camPos = vec3(3.2 * sin(an), 0.5, 3.2 * cos(an));
        camTar = vec3(0.0, 0.2, 0.0);
    }
    else if (camIdx == 10) {
       float progress = localTime * 0.25;
        
  
        camPos = vec3(1.5 - progress, 0.2, 2.5 + progress * 1.5);
        
         camTar = vec3(-1.0, 0.2 + progress * 0.35, 1.5);
    }
    else if (camIdx == 11) {
    float progress = localTime * 0.22;
        
        camPos = vec3(-4.5 + progress * 0.8, 0.25 + sin(localTime * 0.2) * 0.15, -2.2 + progress * 0.6);
        
        vec3 lightPos = calcLightPath(time);
        
        camTar = mix(vec3(1.0, 0.2, 0.0), lightPos * 0.85, 0.85);
        
        camRoll = -0.12 + sin(localTime * 0.15) * 0.08;
      
    }
    else if (camIdx == 12) {
        float an = 0.5 * t;
        camPos = vec3(3.5 * sin(an), 3.0, 3.5 * cos(an));
        camTar = vec3(0.0, -0.5, 0.0);
    }
    else if (camIdx == 13) {
        float an = 1.2 * t;
        camPos = vec3(1.6 * sin(an), 0.3 + 0.2 * cos(an * 0.5), 1.6 * cos(an));
        camTar = lightPos * 0.5;
    }
    else if (camIdx == 14) {
        float up = localTime * 0.15;
        camPos = vec3(1.8, -0.2 + up, 1.8);
        camTar = vec3(0.0, 1.0, 0.0);
    }
    else if (camIdx == 15) {
        float travel = localTime * 0.3;
        camPos = vec3(1.5 + travel, 0.8 + travel, 1.5 + travel);
        camTar = vec3(0.0, -0.5, 0.0);
    }
    else if (camIdx == 16) {
        float pan = localTime * 0.1;
        camPos = vec3(3.5, 0.4, 3.5);
        camTar = vec3(3.5 + sin(pan), 0.4 - (localTime * 0.02), 3.5 + cos(pan));
    }
    else {
        float pull = localTime * 0.15;
        camPos = vec3(0.0, 0.8 + pull * 0.5, 2.8 + pull * 1.5);
        camTar = lightPos * 0.5;
    }
}

vec3 getScatteringColor(float depth, float time) {   
    return 0.5 + 0.5 * cos(depth * 1.0 - time * 3.14159 + vec3(0.5, 2.25, 4.25));
}

float getMorphBlend(float t) {
    return smoothstep(25.0, 27.0, t)
         - smoothstep(41.0, 43.0, t)
         + smoothstep(49.0, 51.0, t)
         - smoothstep(69.0, 71.0, t)
         
 
         + smoothstep(78.0, 80.0, t) 
         - smoothstep(85.0, 87.0, t)  
         
        
         + smoothstep(90.0, 95.0, t)
         - smoothstep(100.0, 103.0, t)
         
         + smoothstep(105.0, 107.0, t)
         - smoothstep(125.0, 127.0, t)
         + smoothstep(135.0, 139.0, t)   
         - smoothstep(147.0, 152.0, t)   
         + smoothstep(160.0, 166.0, t);  
}

// Standard 16-step Halton sequence for sub-pixel jittering
vec2 getJitter(int frame) {
    const vec2[16] halton = vec2[](
        vec2(0.5, 0.333333), vec2(0.25, 0.666667), vec2(0.75, 0.111111), vec2(0.125, 0.444444),
        vec2(0.625, 0.777778), vec2(0.375, 0.222222), vec2(0.875, 0.555556), vec2(0.0625, 0.888889),
        vec2(0.5625, 0.037037), vec2(0.3125, 0.370370), vec2(0.8125, 0.703704), vec2(0.1875, 0.148148),
        vec2(0.6875, 0.481481), vec2(0.4375, 0.814815), vec2(0.9375, 0.259259), vec2(0.03125, 0.592593)
    );
    return halton[frame % 16] - 0.5;
}

// Unified camera state fetcher so BufferD can look back in time
void getCamera(float time, out vec3 ro, out vec3 ta, out float roll, out float fl) {
    float vTime = getVisualTime(time);
    float camTime = vTime > 110.0 ? 16.0 + (vTime - 125.0) : vTime;
    
    vec3 ro1, ta1; float roll1; setCamera(ro1, ta1, roll1, camTime);
    vec3 ro2, ta2; float roll2, fl2; setMechCamera(vTime, ro2, ta2, roll2, fl2);

    float blend = getMorphBlend(vTime); 
    ro = mix(ro1, ro2, blend);
    ta = mix(ta1, ta2, blend);
    roll = mix(roll1, roll2, blend);
    fl = mix(1.8, fl2, blend);

    float driftTime = time * 0.8;
    vec3 drift = vec3(
        sin(driftTime * 1.1) * cos(driftTime * 0.8),
        cos(driftTime * 1.3) * sin(driftTime * 0.9),
        sin(driftTime * 0.7)
    );
    ta += drift * (0.05 / fl);
    roll += (drift.x * 0.02);
}
