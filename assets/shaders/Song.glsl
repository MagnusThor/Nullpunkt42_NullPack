// ============================================================================
// ====== GLOBAL TIMING & MATH ======
// ============================================================================
#define TAU 6.28318530718
#define SR 44100
#define FREQ(nn) (440. * exp2(((nn) - 9.) / 12.))

// --- NaN / overflow safe helpers -------------------------------------------
// tanh() can return NaN (inf/inf) on some drivers for large inputs.
float th(float x) { x = clamp(x, -15., 15.); float e = exp(2. * x); return (e - 1.) / (e + 1.); }
vec2  th(vec2 x)  { return vec2(th(x.x), th(x.y)); }

// sin of a phase given in CYCLES. fract() first keeps the argument small, which
// keeps GPU sin() accurate (huge arguments produce hash/crackle).
float sn(float cycles) { return sin(TAU * fract(cycles)); }

// Core envelopes and shapers
float envAD(float t, float atk, float dec) {
    return smoothstep(0.0, atk, t) * exp(-max(0.0, t - atk) * dec);
}
float antiClick(float t, float dur) { return 1.0 - smoothstep(dur - 0.05, dur, t); }

// Noise & Oscillators
float rand(float p) { p = fract(p * .1031); p *= p + 33.33; return fract(p * p * 2.); }
float noise(float s) {
    float i = floor(s), f = fract(s);
    return mix(rand(i), rand(i + 1.), f * f * (3. - 2. * f)) * 2. - 1.;
}
float saw(float p, float fc) {
    p -= round(p);
    return mix(-1. - 2.*p, 1. - 2.*p, smoothstep(-.75/fc, .75/fc, p));
}

// ============================================================================
// ====== HARMONIC CHORD LIBRARY ======  (sm = samples since song start)
// ============================================================================
vec4 chord(int sm) {
    int i = (sm / (8 * SR)) % 8;
    return i==0||i==5 ? vec4(-22,-10,-7,-3) :
           i==1 ? vec4(-14,-2,2,5) :
           i==2 ? vec4(-19,-7,-3,0) :
           i==3 ? vec4(-24,-12,-8,-5) :
           i==4 ? vec4(-17,-5,-2,2) :
           i==6 ? vec4(-21,-9,-5,-2) :
                  vec4(-15,-3,0,4);
}

// ============================================================================
// ====== INSTRUMENTS ======
// t = LOCAL time (small, restarts with each note/bar), e = envelope time
// ============================================================================
vec2 strings(float f, float t, float e) {
    vec2 v = vec2(0);
    for(int i=-3; i<=4; i++) {
        float s = saw(f * (1. + float(i)*.0015) * t + float(i)*0.13, 2500./f);
        if ((i & 1) == 0) v.x += s; else v.y += s;
    }
    v += v * (sn(5.1 * t) * smoothstep(.3, 1., e) * .008);
    float n = sn(f * .5 * t) * envAD(e,.2,.3) * .15 +
              sn(f * 1.5 * e) * noise(t*3e3) * exp(-e*12.) * .08;
    return (v * .25 + n) * envAD(e, .35, .45);
}

vec2 brass(float f, float t, float e) {
    float buzz = th((sn(f*t) + .5*sn(f*2.*t) + .25*sn(f*3.*t)) * .5 * 1.4) / th(1.4);
    vec2 v = vec2(0);
    for(int i=-2; i<=3; i++) {
        float s = saw(f * (1. + float(i)*.002) * t, 3500./f) * (1. - abs(float(i))*.1);
        if ((i & 1) == 0) v.x += s; else v.y += s;
    }
    vec2 wave = vec2(th((buzz*.4 + (v.x+v.y)*.09) * (1.+exp(-e*8.)*.08) * 1.2));
    return (wave + v*.08) * smoothstep(0., .18, e) * exp(-e*.25) * envAD(e, .18, .8);
}

vec2 choir(float f, float t, float e) {
    float vib = sn(3.8*t) * smoothstep(.5,1.5,e) * .015;
    float fc8 = 8e3/f;
    float sL = saw(f*t+vib, fc8) + saw(f*1.004*t-vib, fc8) + saw(f*.996*t, fc8);
    float sR = saw(f*1.002*t+vib*.5, fc8) + saw(f*1.004*t-vib, fc8) + saw(f*.996*t, fc8);

    // Formants
    float fmts = 0.0;
    vec3 fc = vec3(700., 1100., 2500.), bw = vec3(80., 120., 250.), m = vec3(1., .7, .25);
    for(int i=0; i<3; i++) {
        float nr = max(1., round(fc[i]/f)) * f;
        float d = (fc[i]-nr)/fc[i];
        // was pow(d, 2.) -> NaN for negative d on many drivers. d*d is exact and safe.
        fmts += sn(nr*t) * exp(-d*d * bw[i] * 1e-4) * m[i];
    }
    return (vec2(sL, sR)*.1 + fmts*.7) * envAD(e, .8, .4);
}

vec2 pulseBass(float f, float t, float e) {
    float g = (saw(f*t, 2e3/f) + saw(f*1.012*t, 2e3/f)) * .5;
    float clkE = exp(-e*50.);
    float w = sn(f*(1.+exp(-e*15.)*.3)*t)*.5 + sn(f*t)*.3 +
              (th(g*3.5)/th(3.5))*.2 + sn(f*3.*e)*clkE*.6 + noise(e*2e3)*clkE*.15;
    return vec2(th(w*1.8)/th(1.8)) * envAD(e, .005, 1.5);
}

vec2 timpani(float e) {
    float f0 = 55. * (1. + exp(-e*15.)*.1);
    float d = sn(f0*e)*envAD(e,.005,3.5) + sn(f0*1.5*e)*envAD(e,.005,2.5)*.45 +
              sn(f0*1.98*e)*envAD(e,.005,2.)*.25 + sn(f0*2.44*e)*envAD(e,.005,1.5)*.1;
    float m = sn(300.*e) * noise(e*1500.) * envAD(e,.008,30.)*.4;
    float r = sn(27.5*e) * envAD(e,.05,4.)*.5;
    return vec2(th((d*.7+m+r)*1.2)/th(1.2)) * envAD(e, .008, 4.);
}

// Deep, hollow, cinematic boom. len = how long this hit is allowed to ring.
vec2 boom(float e, float len) {
    float p = exp(-e * 30.0) * 4.0;
    float b = sn(35.0 * (1.0 + p) * e) * envAD(e, 0.001, 3.5);
    float sub = sn(28.0 * e) * envAD(e, 0.1, 1.8) * 0.85;
    // noise(0) == -1, so this term started with a hard -0.3 STEP (a click on every hit).
    // 2 ms attack ramp removes the step but keeps the crack.
    float c = (noise(e * 8e3) * exp(-e * 2e2) * 0.3 + sn(22.0 * e) * exp(-e * 5.0) * 0.4)
              * smoothstep(0., .002, e);
    // Short tail fade so the hit never gets chopped when the router stops it.
    float tail = 1. - smoothstep(len - .06, len, e);
    return vec2(th((b + sub + c) * 2.4)) * tail;
}

// t = local time for phase, tg = global time for the very slow LFOs only
vec2 pad(float f, float t, float tg, float e) {
    float w = sn(f*t        + sin(TAU*.07*tg)*(.8/TAU)) +
              sn(f*1.008*t  + sin(TAU*.11*tg)*(.6/TAU)) +
              sn(f*.992*t   + sin(TAU*.09*tg)*(.7/TAU)) +
              sn(f*2.001*t  + sin(TAU*.13*tg)*(.4/TAU))*.4 +
              sn(f*3.003*t  + sin(TAU*.17*tg)*(.3/TAU))*.15;
    // was sin(.. * fract(t*.5)): jumped every 2 s. Using e keeps it continuous.
    float n = sn(f*2.*e) * noise(t*5e2)*.08;
    float pan = sn(.05*tg)*.3, pls = .85+.15*sn(4.*tg);
    return vec2(w*.2*(.7+pan)+n, w*.2*(.7-pan)+n*.9) * pls * envAD(e, 5., 3.);
}

vec2 darkPluck(float f, float t, float tg, float e, float vel) {
    float d = sn(.8*tg)*.003, fc = 1.5+4.*exp(-e*15.);
    float s = (saw(f*t+d, fc) + saw(f*1.006*t-d, fc))*.4 + sn(f*.5*t)*.6;
    return vec2(th(s*1.8)/th(1.8)) * envAD(e, .002, 2.) * vel;
}

// ============================================================================
// ====== MASTER TIMELINE & MIXER ======
// ============================================================================
// All note/bar timing is derived from the INTEGER sample index. A float time
// like idx/44100 at t=150 s only has ~0.7-sample resolution, which turns into
// timing jitter / crackle on everything. Integer modulo is exact.
vec2 mainSound(int samp, float t_in) {
    // Song is 180 s. Anything past that (texture holds ~190 s) is silence.
    if (samp < 0 || samp >= 180 * SR) return vec2(0);

    float t = float(samp) / float(SR);   // coarse time: only for slow envelopes
    vec2 outA = vec2(0);

    // --- SMART BOOM ROUTER ---
    float bEnv = 999.0, bVol = 0.3, bLen = 5.0;
    if (samp < 20 * SR) {
        bEnv = float(samp % (2 * SR)) / float(SR);
        bVol = 0.2 + 0.02 * float(samp / (2 * SR));
        bLen = 2.0;
    } else if (samp > 84 * SR && samp < 126 * SR) {
        bEnv = float(samp % (8 * SR)) / float(SR);
        bVol = 0.35 * smoothstep(84., 84.05, t);   // enters at e=4: fade in, no step
        bLen = 5.0;
    } else if (samp >= 150 * SR) {
        bEnv = float(samp % (2 * SR)) / float(SR);
        bVol = 0.35 + 0.025 * float((samp - 150 * SR) / (2 * SR));
        bLen = 2.0;
    }
    if (bEnv < 5.0) outA += boom(bEnv, bLen) * bVol;

    // --- TRACK TIMELINE ---
    int sm = samp - 20 * SR;   // samples since the main track started
    if (sm >= 0) {
        float mt = float(sm) / float(SR);
        float oF = 1.0 - smoothstep(138., 158., mt);
        float pB = smoothstep(130., 140., mt);

        vec4 c = chord(sm);
        float mtBar  = float(sm % (4 * SR)) / float(SR);        // 4 s bar
        float mt2Bar = float(sm % (8 * SR)) / float(SR);        // 8 s bar
        float mt16   = float(sm % (SR / 4)) / float(SR);        // 0.25 s
        float mt32   = float((2 * sm) % (SR / 4)) / float(2 * SR); // 0.125 s

        // Jarre Pluck
        float eJ = smoothstep(0., 4., mt) * oF;
        if (eJ > 0.) {
            int st = (sm / (SR / 4)) % 16;
            float n = c.y+12.;
            if(st==2||st==8||st==12) n = c.w+12.; else if(st==4) n = c.y+24.;
            else if(st==6) n = c.z+12.; else if(st==10) n = c.z+24.;
            outA += darkPluck(FREQ(n), mt16, mt, mt16*.5, .7) * eJ * antiClick(mt16, .25);
        }

        // Pads
        if (oF > 0.) {
            outA += pad(FREQ(c.y), mtBar, mt, mtBar*.5) * oF * .25 * antiClick(mtBar, 4.0);
            float fHP = smoothstep(60., 90., mt) * (1.-pB) * oF;
            if(fHP > 0.) outA += pad(FREQ(c.y+24.), mtBar, mt, mtBar*.5) * fHP * antiClick(mtBar, 4.0);
        }

        // Strings
        float eS = smoothstep(0., 8., mt) * (1.-.6*pB) * oF;
        if (eS > 0.) {
            vec2 str = strings(FREQ(c.y+12.), mtBar, mtBar*.5) +
                       strings(FREQ(c.z+12.), mtBar, mtBar*.5)*.8 +
                       strings(FREQ(c.w+12.), mtBar, mtBar*.5)*.8;
            outA += str * eS * .85 * antiClick(mtBar, 4.0);
        }

        // Choir
        float eC = smoothstep(8., 16., mt) * (1.-pB) * oF;
        if (eC > 0.) {
            vec2 chr = choir(FREQ(c.y+12.), mtBar, mtBar*.5) + choir(FREQ(c.w+12.), mtBar, mtBar*.5)*.6;
            outA += th(chr*.8) * eC * .15 * antiClick(mtBar, 4.0);
        }

        // Pulse & Percussion
        float eP = smoothstep(16., 24., mt) * (1.-pB) * oF;
        if (eP > 0.) {
            outA += pulseBass(FREQ(c.x), mt16, mt16*.5) * eP * .15 * antiClick(mt16, .25);

            outA += boom(mt2Bar*.5, 99.) * eP * .4 * antiClick(mt2Bar, 8.0);

            float tRoll = smoothstep(6., 8., mt2Bar);
            if (tRoll > 0.) {
                outA += timpani(mt32*.5) * tRoll * eP * .3 * antiClick(mt32, .125);
            }
        }

        // Brass
        float eB = smoothstep(24., 32., mt) * (1.-pB) * oF;
        if (eB > 0.) {
            vec2 brs = brass(FREQ(c.x-12.), mt2Bar, mt2Bar*.5) + brass(FREQ(c.y), mt2Bar, mt2Bar*.5)*.8;
            outA += brs * eB * .4 * antiClick(mt2Bar, 8.0);
        }
    }

    // Master Limiter (fade in 0-2 s, fade out 178-180 s).
    // Original smoothstep(180.,178.,t) had edge0 > edge1 = undefined in GLSL.
    outA *= 0.85;
    return th(outA * 1.4) * smoothstep(0., 2., t) * (1.0 - smoothstep(178., 180., t));
}