// src/executors/ShadertoyExecutor.ts
var ShadertoyExecutor = class {
  canvas;
  gl;
  bundle;
  audioCtx = null;
  analyser = null;
  audioTex = null;
  audioDataFFT = null;
  audioDataWave = null;
  loadedTextures = /* @__PURE__ */ new Map();
  texResolutions = /* @__PURE__ */ new Map();
  passMap = /* @__PURE__ */ new Map();
  quadBuffer;
  mouse = { x: 0, y: 0, z: 0, w: 0, isDown: false };
  startTime = 0;
  lastTime = 0;
  frame = 0;
  isRunning = false;
  async execute(bundle) {
    this.bundle = bundle;
    this.isRunning = true;
    this.initCanvas();
    this.initWebGL();
    this.bindMouseEvents();
    if (!bundle.has("shadertoy.json")) {
      throw new Error("shadertoy.json not found in VFS.");
    }
    const manifest = JSON.parse(await bundle.text("shadertoy.json"));
    const commonPass = manifest.renderpass.find((p) => p.type === "common")?.code || "";
    const renderPasses = manifest.renderpass.filter((p) => p.type !== "common").sort((a, b) => (a.type === "image" ? 1 : 0) - (b.type === "image" ? 1 : 0));
    await this.setupPasses(renderPasses, commonPass);
    this.startTime = performance.now();
    this.lastTime = this.startTime;
    requestAnimationFrame((now) => this.render(now));
  }
  dispose() {
    this.isRunning = false;
    if (this.audioCtx) this.audioCtx.close();
    if (this.canvas) this.canvas.remove();
    this.passMap.clear();
    this.loadedTextures.clear();
  }
  initCanvas() {
    this.canvas = document.createElement("canvas");
    document.body.appendChild(this.canvas);
    this.canvas.style.cssText = "position:fixed; top:0; left:0; width:100vw; height:100vh; display:block;";
    const resize = () => {
      this.canvas.width = window.innerWidth;
      this.canvas.height = window.innerHeight;
    };
    window.addEventListener("resize", resize);
    resize();
  }
  initWebGL() {
    const gl = this.canvas.getContext("webgl2", { antialias: false, alpha: false });
    if (!gl) throw new Error("WebGL2 required");
    this.gl = gl;
    this.gl.getExtension("EXT_color_buffer_float");
    this.gl.getExtension("OES_texture_float_linear");
    const vsSource = `#version 300 es
in vec2 position; void main() { gl_Position = vec4(position, 0.0, 1.0); }`;
    const vShader = this.compileShader(this.gl.VERTEX_SHADER, vsSource);
    this.quadBuffer = this.gl.createBuffer();
    this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.quadBuffer);
    this.gl.bufferData(this.gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), this.gl.STATIC_DRAW);
  }
  bindMouseEvents() {
    window.addEventListener("mousedown", (e) => {
      this.mouse.isDown = true;
      this.mouse.x = e.clientX;
      this.mouse.y = this.canvas.height - e.clientY;
      this.mouse.z = this.mouse.x;
      this.mouse.w = this.mouse.y;
    });
    window.addEventListener("mousemove", (e) => {
      if (this.mouse.isDown) {
        this.mouse.x = e.clientX;
        this.mouse.y = this.canvas.height - e.clientY;
      }
    });
    window.addEventListener("mouseup", () => {
      this.mouse.isDown = false;
      this.mouse.z = -Math.abs(this.mouse.z);
      this.mouse.w = -Math.abs(this.mouse.w);
    });
  }
  compileShader(type, source) {
    const shader = this.gl.createShader(type);
    this.gl.shaderSource(shader, source);
    this.gl.compileShader(shader);
    if (!this.gl.getShaderParameter(shader, this.gl.COMPILE_STATUS)) {
      throw new Error("Shader compile error:\n" + this.gl.getShaderInfoLog(shader));
    }
    return shader;
  }
  async initAudio(filepath) {
    if (this.audioTex) return;
    const cleanPath = filepath.replace(/^\/+/, "");
    this.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    this.analyser = this.audioCtx.createAnalyser();
    this.analyser.fftSize = 1024;
    this.audioDataFFT = new Uint8Array(this.analyser.frequencyBinCount);
    this.audioDataWave = new Uint8Array(this.analyser.frequencyBinCount);
    const assetUrl = await this.bundle.url(cleanPath);
    const audio = new Audio(assetUrl);
    audio.crossOrigin = "anonymous";
    audio.loop = true;
    const source = this.audioCtx.createMediaElementSource(audio);
    source.connect(this.analyser);
    this.analyser.connect(this.audioCtx.destination);
    this.audioTex = this.gl.createTexture();
    this.gl.bindTexture(this.gl.TEXTURE_2D, this.audioTex);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.LINEAR);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MAG_FILTER, this.gl.LINEAR);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
    await audio.play();
  }
  updateAudioTexture() {
    if (!this.analyser || !this.audioTex || !this.audioDataFFT || !this.audioDataWave) return;
    this.analyser.getByteFrequencyData(this.audioDataFFT);
    this.analyser.getByteTimeDomainData(this.audioDataWave);
    const data = new Uint8Array(1024);
    data.set(this.audioDataFFT, 0);
    data.set(this.audioDataWave, 512);
    this.gl.bindTexture(this.gl.TEXTURE_2D, this.audioTex);
    this.gl.texImage2D(this.gl.TEXTURE_2D, 0, this.gl.LUMINANCE, 512, 2, 0, this.gl.LUMINANCE, this.gl.UNSIGNED_BYTE, data);
  }
  async loadTexture(filepath, sampler) {
    const cleanPath = filepath.replace(/^\/+/, "");
    if (this.loadedTextures.has(cleanPath)) return;
    const blob = await this.bundle.blob(cleanPath);
    const bitmap = await createImageBitmap(blob, { imageOrientation: sampler?.vflip === "true" ? "flipY" : "none" });
    const tex = this.gl.createTexture();
    this.gl.bindTexture(this.gl.TEXTURE_2D, tex);
    this.gl.texImage2D(this.gl.TEXTURE_2D, 0, this.gl.RGBA, this.gl.RGBA, this.gl.UNSIGNED_BYTE, bitmap);
    const filter = sampler?.filter === "nearest" ? this.gl.NEAREST : this.gl.LINEAR;
    const wrap = sampler?.wrap === "repeat" ? this.gl.REPEAT : this.gl.CLAMP_TO_EDGE;
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, filter);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MAG_FILTER, filter);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, wrap);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, wrap);
    this.loadedTextures.set(cleanPath, tex);
    this.texResolutions.set(cleanPath, [bitmap.width, bitmap.height, 1]);
  }
  async setupPasses(renderPasses, commonPass) {
    for (const pass of renderPasses) {
      const fsSource = `#version 300 es
        precision highp float;
        uniform vec3 iResolution; uniform float iTime; uniform float iTimeDelta;
        uniform int iFrame; uniform float iFrameRate; uniform vec4 iMouse;
        uniform vec4 iDate; uniform float iSampleRate; uniform vec3 iChannelResolution[4];
        uniform float iChannelTime[4];
        uniform sampler2D iChannel0; uniform sampler2D iChannel1;
        uniform sampler2D iChannel2; uniform sampler2D iChannel3;
        out vec4 fragColor;
        ${commonPass}
        ${pass.code}
        void main() { mainImage(fragColor, gl_FragCoord.xy); }`;
      const fShader = this.compileShader(this.gl.FRAGMENT_SHADER, fsSource);
      const prog = this.gl.createProgram();
      const vShader = this.compileShader(this.gl.VERTEX_SHADER, `#version 300 es
in vec2 position; void main() { gl_Position = vec4(position, 0.0, 1.0); }`);
      this.gl.attachShader(prog, vShader);
      this.gl.attachShader(prog, fShader);
      this.gl.linkProgram(prog);
      const uniforms = {
        iResolution: this.gl.getUniformLocation(prog, "iResolution"),
        iTime: this.gl.getUniformLocation(prog, "iTime"),
        iTimeDelta: this.gl.getUniformLocation(prog, "iTimeDelta"),
        iFrame: this.gl.getUniformLocation(prog, "iFrame"),
        iMouse: this.gl.getUniformLocation(prog, "iMouse"),
        iDate: this.gl.getUniformLocation(prog, "iDate"),
        iSampleRate: this.gl.getUniformLocation(prog, "iSampleRate"),
        iChannelResolution: this.gl.getUniformLocation(prog, "iChannelResolution"),
        channels: [
          this.gl.getUniformLocation(prog, "iChannel0"),
          this.gl.getUniformLocation(prog, "iChannel1"),
          this.gl.getUniformLocation(prog, "iChannel2"),
          this.gl.getUniformLocation(prog, "iChannel3")
        ]
      };
      let fbos = null;
      let textures = null;
      if (pass.type === "buffer") {
        fbos = [this.gl.createFramebuffer(), this.gl.createFramebuffer()];
        textures = [this.gl.createTexture(), this.gl.createTexture()];
        for (let i = 0; i < 2; i++) {
          this.gl.bindTexture(this.gl.TEXTURE_2D, textures[i]);
          this.gl.texImage2D(this.gl.TEXTURE_2D, 0, this.gl.RGBA32F, this.canvas.width, this.canvas.height, 0, this.gl.RGBA, this.gl.FLOAT, null);
          const filter = pass.outputs[0]?.id ? this.gl.LINEAR : this.gl.NEAREST;
          this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, filter);
          this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MAG_FILTER, filter);
          this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
          this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
          this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, fbos[i]);
          this.gl.framebufferTexture2D(this.gl.FRAMEBUFFER, this.gl.COLOR_ATTACHMENT0, this.gl.TEXTURE_2D, textures[i], 0);
        }
      }
      this.passMap.set(pass.outputs[0]?.id || "image", {
        prog,
        posLoc: this.gl.getAttribLocation(prog, "position"),
        uniforms,
        pass,
        fbos,
        textures,
        current: 0
      });
      for (const input of pass.inputs) {
        if (input.type === "music") await this.initAudio(input.filepath);
        else if (input.type === "texture" || input.type === "image") await this.loadTexture(input.filepath, input.sampler);
      }
    }
  }
  render(now) {
    if (!this.isRunning) return;
    const time = (now - this.startTime) * 1e-3;
    const delta = (now - this.lastTime) * 1e-3;
    this.lastTime = now;
    this.updateAudioTexture();
    const date = /* @__PURE__ */ new Date();
    const iDate = [date.getFullYear(), date.getMonth(), date.getDate(), date.getHours() * 3600 + date.getMinutes() * 60 + date.getSeconds() + date.getMilliseconds() * 1e-3];
    for (const pData of this.passMap.values()) {
      this.gl.useProgram(pData.prog);
      this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.quadBuffer);
      this.gl.enableVertexAttribArray(pData.posLoc);
      this.gl.vertexAttribPointer(pData.posLoc, 2, this.gl.FLOAT, false, 0, 0);
      this.gl.uniform3f(pData.uniforms.iResolution, this.canvas.width, this.canvas.height, 1);
      this.gl.uniform1f(pData.uniforms.iTime, time);
      this.gl.uniform1f(pData.uniforms.iTimeDelta, delta);
      this.gl.uniform1i(pData.uniforms.iFrame, this.frame);
      this.gl.uniform4f(pData.uniforms.iMouse, this.mouse.x, this.mouse.y, this.mouse.z, this.mouse.w);
      this.gl.uniform4f(pData.uniforms.iDate, iDate[0], iDate[1], iDate[2], iDate[3]);
      this.gl.uniform1f(pData.uniforms.iSampleRate, this.audioCtx ? this.audioCtx.sampleRate : 44100);
      const resArray = new Float32Array(12);
      for (let i = 0; i < pData.pass.inputs.length; i++) {
        const input = pData.pass.inputs[i];
        this.gl.activeTexture(this.gl.TEXTURE0 + input.channel);
        let res = [0, 0, 0];
        if (input.type === "music" && this.audioTex) {
          this.gl.bindTexture(this.gl.TEXTURE_2D, this.audioTex);
          res = [512, 2, 1];
        } else if ((input.type === "texture" || input.type === "image") && this.loadedTextures.has(input.filepath.replace(/^\/+/, ""))) {
          this.gl.bindTexture(this.gl.TEXTURE_2D, this.loadedTextures.get(input.filepath.replace(/^\/+/, "")));
          res = this.texResolutions.get(input.filepath.replace(/^\/+/, "")) || [0, 0, 0];
        } else if (input.type === "buffer") {
          const dep = this.passMap.get(input.id);
          if (dep && dep.textures) {
            this.gl.bindTexture(this.gl.TEXTURE_2D, dep.textures[(dep.current + 1) % 2]);
            res = [this.canvas.width, this.canvas.height, 1];
          }
        }
        resArray[input.channel * 3] = res[0];
        resArray[input.channel * 3 + 1] = res[1];
        resArray[input.channel * 3 + 2] = res[2];
        this.gl.uniform1i(pData.uniforms.channels[input.channel], input.channel);
      }
      this.gl.uniform3fv(pData.uniforms.iChannelResolution, resArray);
      if (pData.fbos) {
        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, pData.fbos[pData.current]);
        this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      } else {
        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
        this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      }
      this.gl.drawArrays(this.gl.TRIANGLES, 0, 6);
      if (pData.fbos) pData.current = (pData.current + 1) % 2;
    }
    this.frame++;
    requestAnimationFrame((now2) => this.render(now2));
  }
};

// src/demo.ts
async function runDemo(bundle) {
  console.log("[Runner] Initializing Shadertoy Executor...");
  const executor = new ShadertoyExecutor();
  try {
    await executor.execute(bundle);
  } catch (error) {
    console.error("[Runner] Execution failed:", error);
    if (typeof executor.dispose === "function") {
      executor.dispose();
    }
    throw error;
  }
}
export {
  runDemo
};
