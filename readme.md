# Nullpunkt42_NullPack

**Nullpunkt42_NullPack** is a single-file virtual file system (VFS) and asset pipeline tailored for web-based demoscene productions.

It takes an entire folder of shaders, audio, textures, and scripts and packs them into a highly optimized `.bin` archive using selective Deflate compression. In the browser, a transparent in-memory `window.fetch` interceptor serves the assets back, so your existing WebGL/WebGPU engines (or ported C++ runners) can load files normally without knowing they are running from a single binary blob.

It also includes a fully featured **WebGL2 Shadertoy Executor**, allowing you to run multi-pass Shadertoy JSON exports natively with audio-reactive FFT textures.

---

## ⚡ Features

- **Single-File Output** – Compiles your entire production into one `.bin` payload and a sleek HTML launcher.
- **Smart Compression** – Automatically runs `zlib.deflateRaw` on text, shaders, and JSON, while passing pre-compressed media (PNG, MP3, MP4) through untouched.
- **Transparent VFS** – Overrides `window.fetch` at runtime. Standard calls like `fetch('assets/shader.glsl')` resolve instantly from memory via the native `DecompressionStream` API.
- **Shadertoy Compatible** – Drop a `shadertoy.json` into your assets folder, and the included WebGL2 executor will wire up ping-pong framebuffers, `iMouse`, `iDate`, and 512×2 audio FFT/waveform textures automatically.
- **TypeScript First** – Fully typed architecture, bundled at lightning speed with esbuild.

---

## 🚀 Quick Start

### 1. Install Dependencies

Ensure you have [Node.js](https://nodejs.org/) installed, then run:

```bash
npm install
```

### 2. Add Your Assets

Drop your shaders, `.mp3` tracks, and JSON configurations into the `/assets` folder. Subdirectories are fully supported.

### 3. Build & Pack

Compile the TypeScript runners, bundle the files, and generate the release folder:

```bash
npm run build
```

### 4. Run the Demo

Serve the generated `/output` directory (e.g. with `npx serve output` or Vite). Click the play button to unpack the VFS, compile the shaders, and launch the demo.

---

## 📁 Project Structure

```text
Nullpunkt42_NullPack/
├── assets/                  # Raw assets (audio, glsl, json) go here
├── output/                  # The final shippable artifact is generated here
│   ├── demo.bin             # The packed binary payload
│   ├── index.html           # Minimalist fullscreen launcher
│   └── loader.js            # Browser VFS and decompression engine
├── src/
│   ├── demo.ts              # Entry point for the active demo
│   ├── index.html           # Launcher template
│   ├── loader.ts            # VFS and DecompressionStream logic
│   ├── pack.ts              # Node.js asset compiler
│   ├── types.ts             # Shared TypeScript interfaces
│   └── executors/           # Pluggable rendering engines
│       ├── DemoExecutor.ts
│       └── ShadertoyExecutor.ts
├── settings.json            # Build configuration
├── package.json
└── tsconfig.json
```

---

## ⚙️ Configuration (`settings.json`)

You can control the packing process by editing `settings.json` in the project root. If omitted, the packer uses these defaults:

```json
{
  "assetsDir": "./assets",
  "output": "./output/demo.bin",
  "runnerFile": "demo.js",
  "fullscreenOnStart": true
}
```

| Option              | Description                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `assetsDir`         | The directory to scan and pack.                                                               |
| `output`            | Where the final `.bin` file should be written.                                                |
| `runnerFile`        | The JavaScript entry point the VFS dynamically imports and executes once unpacking completes. |
| `fullscreenOnStart` | Whether the demo requests fullscreen when started.                                            |

---

## 🛠️ The Shadertoy Engine

NullPack includes a modular execution system. By default, `demo.ts` invokes the `ShadertoyExecutor`.

### Running a Shadertoy Project

1. Export your project to JSON from Shadertoy.
2. Save it as `shadertoy.json` in your `/assets` folder.
3. Update the media file paths in the JSON `inputs` array to point to your local `/assets` paths (e.g. `"filepath": "audio/track.mp3"`).
4. Run `npm run build`.

### Supported Features

- **Multi-pass buffers** (Buffer A, Buffer B, etc.) using ping-pong framebuffers
- **Floating-point textures** (`EXT_color_buffer_float`)
- **Common tab injection**
- **Audio inputs** – automatically translates Web Audio API frequency and time-domain data into a 512×2 texture
- **Standard uniforms:** `iTime`, `iResolution`, `iMouse`, `iDate`, `iChannelResolution`
