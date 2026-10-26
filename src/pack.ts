import * as fs from 'node:fs';
import * as path from 'node:path';
import * as zlib from 'node:zlib';

interface Settings {
  assetsDir?: string;
  output?: string;
  runnerFile?: string;
  png?: boolean;
  cover?: string;
}

function loadSettings(): Required<Settings> {
  const defaults: Required<Settings> = {
    assetsDir: './assets',
    output: './output/demo.bin',
    runnerFile: 'demo.js',
    png: false,
    cover: ''
  };

  const settingsPath = path.resolve(process.cwd(), 'settings.json');
  if (fs.existsSync(settingsPath)) {
    try {
      const raw = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
      return {
        assetsDir: raw.assetsDir?.trim() || defaults.assetsDir,
        output: raw.output?.trim() || defaults.output,
        runnerFile: raw.runnerFile?.trim() || defaults.runnerFile,
        png: !!raw.png,
        cover: raw.cover?.trim() || defaults.cover
      };
    } catch (e) {}
  }
  return defaults;
}

const settings = loadSettings();
const ASSETS_DIR = path.resolve(process.argv[2] ?? settings.assetsDir);
let OUTPUT_FILE = path.resolve(process.argv[3] ?? settings.output);

if (settings.png && !OUTPUT_FILE.endsWith('.png.html')) {
  OUTPUT_FILE = OUTPUT_FILE.replace(/\.bin$/, '') + '.png.html';
}

const NO_COMPRESS = new Set<string>([
  '.png', '.jpg', '.jpeg', '.webp', '.gif',
  '.mp3', '.ogg', '.aac', '.flac',
  '.mp4', '.webm', '.wasm', '.woff2'
]);

const MIME_MAP: Record<string, string> = {
  '.js':   'application/javascript',
  '.glsl': 'text/plain',
  '.json': 'application/json',
  '.png':  'image/png',
  '.mp3':  'audio/mpeg'
};

// --- CRC32 for PNG Chunks ---
const crcTable = new Uint32Array(256);
for (let i = 0; i < 256; i++) {
  let c = i;
  for (let j = 0; j < 8; j++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
  crcTable[i] = c;
}

function crc32(data: Uint8Array): number {
  let crc = 0xffffffff;
  for (let i = 0; i < data.length; i++) crc = (crc >>> 8) ^ crcTable[(crc ^ data[i]) & 0xff];
  return (crc ^ 0xffffffff) >>> 0;
}

function makePngChunk(type: string, data: Buffer): Buffer {
  const out = Buffer.alloc(8 + data.length + 4);
  out.writeUInt32BE(data.length, 0);
  Buffer.from(type, 'ascii').copy(out, 4);
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 4 + 4 + data.length)), 8 + data.length);
  return out;
}

function parsePngChunks(buffer: Buffer) {
  const chunks = [];
  let offset = 8;
  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    chunks.push({ type, raw: buffer.subarray(offset, offset + 12 + length) });
    offset += 12 + length;
  }
  return chunks;
}

function getAllFiles(dir: string, fileList: string[] = []): string[] {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) getAllFiles(fullPath, fileList);
    else fileList.push(fullPath);
  }
  return fileList;
}

function buildPayload(files: string[], salt: number = 0): Buffer {
  const manifest: any = {
    __meta__: { runnerFile: settings.runnerFile, created: Date.now() },
    files: {}
  };
  if (salt > 0) manifest.__meta__.salt = salt;

  const chunks: Buffer[] = [];
  let currentOffset = 0;

  for (const filePath of files) {
    const relKey = path.relative(ASSETS_DIR, filePath).replace(/\\/g, '/');
    const ext = path.extname(filePath).toLowerCase();
    const rawData = fs.readFileSync(filePath);
    
    let finalData = rawData;
    let isCompressed = false;

    if (!NO_COMPRESS.has(ext)) {
      const deflated = zlib.deflateRawSync(rawData, { level: 9 });
      if (deflated.length < rawData.length) {
        finalData = deflated;
        isCompressed = true;
      }
    }

    manifest.files[relKey] = {
      offset: currentOffset,
      size: finalData.length,
      origSize: rawData.length,
      compressed: isCompressed,
      mime: MIME_MAP[ext] ?? 'application/octet-stream'
    };

    chunks.push(finalData);
    currentOffset += finalData.length;
  }

  const manifestBuffer = Buffer.from(JSON.stringify(manifest), 'utf8');
  const header = Buffer.alloc(8);
  header.write('DEMO', 0, 4, 'ascii');
  header.writeUInt32LE(manifestBuffer.length, 4);

  return Buffer.concat([header, manifestBuffer, ...chunks]);
}

function pack(): void {
  const files = getAllFiles(ASSETS_DIR);
  let payload = buildPayload(files, 0);
  
  let salt = 0;
  while (payload.includes(Buffer.from('-->')) || payload.includes(Buffer.from('--!>'))) {
    salt++;
    payload = buildPayload(files, salt);
  }

  fs.mkdirSync(path.dirname(OUTPUT_FILE), { recursive: true });

  if (settings.png) {
    const loaderPath = path.resolve('output/loader.js');
    if (!fs.existsSync(loaderPath)) throw new Error("loader.js not found. Run 'npm run build:loader' first.");
    const loaderCode = fs.readFileSync(loaderPath, 'utf8');

    let coverBuffer = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000b49444154785e636000020000050001e9fa25c10000000049454e44ae426082', 'hex');
    if (settings.cover && fs.existsSync(settings.cover)) {
      coverBuffer = fs.readFileSync(settings.cover);
    }

    const sourceChunks = parsePngChunks(coverBuffer);
    const ihdr = sourceChunks.find(c => c.type === 'IHDR')!.raw;
    const iend = sourceChunks.find(c => c.type === 'IEND')!.raw;
    const idats = sourceChunks.filter(c => c.type === 'IDAT').map(c => c.raw);

    // Bootstrap isolates the offset logic using a signature scanner that HIDES its own signature
    const bootHtml = `<meta charset=latin1><title>Demoscene Web Runner</title>
<style>
  body { margin:0; overflow:hidden; background:#0c0d12; display:flex; align-items:center; justify-content:center; }
  .play-btn { width:96px; height:96px; border:2px solid rgba(255,255,255,0.2); border-radius:50%; background:rgba(255,255,255,0.03); cursor:pointer; display:flex; align-items:center; justify-content:center; transition:all 0.25s; }
  .play-btn:hover { border-color:#38bdf8; transform:scale(1.06); }
  .play-btn svg { width:32px; height:32px; fill:#fff; margin-left:6px; }
</style>
<div id="launcher-ui"><button id="start-btn" class="play-btn"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg></button></div>
<script type="module">
${loaderCode};
document.getElementById('start-btn').onclick = async () => {
  document.getElementById('launcher-ui').style.display = 'none';
  try { if (!document.fullscreenElement) await document.documentElement.requestFullscreen().catch(()=>{}); } catch(e) {}
  
  const buf = await (await fetch(location.href)).arrayBuffer();
  const bytes = new Uint8Array(buf);
  let offset = 0;
  
  for(let i=0; i<bytes.length-8; i++) {
    // Looks for chunk type followed by magic bytes (ASCII: 110=n, 80=P, 65=A, 75=K, 68=D, 69=E, 77=M, 79=O)
    // Using raw integers guarantees this scanner can never accidentally match its own source code.
    if(
      bytes[i]===110 && bytes[i+1]===80 && bytes[i+2]===65 && bytes[i+3]===75 &&
      bytes[i+4]===68 && bytes[i+5]===69 && bytes[i+6]===77 && bytes[i+7]===79
    ) { 
      offset = i + 4; // Point exactly to byte 68 (start of payload)
      break; 
    }
  }
  
  const payloadUrl = URL.createObjectURL(new Blob([buf.slice(offset)]));
  
  // Pass isolated payload to standard unmodified loader
  const bundle = await loadAssetBundle(payloadUrl, { interceptFetch: true, fetchPrefix: 'assets/' });
  await bundle.run();
};
</script><!--`;

    const finalPolyglot = Buffer.concat([
      Buffer.from('89504e470d0a1a0a', 'hex'),
      ihdr,
      makePngChunk('bOOt', Buffer.from(bootHtml, 'latin1')),
      makePngChunk('nPAK', payload),
      ...idats,
      iend
    ]);

    fs.writeFileSync(OUTPUT_FILE, finalPolyglot);
    console.log(`[Packer] Created Polyglot PNG: ${OUTPUT_FILE}`);
  } else {
    fs.writeFileSync(OUTPUT_FILE, payload);
    console.log(`[Packer] Created Standard Binary: ${OUTPUT_FILE}`);
    
    if (fs.existsSync('./src/index.html')) {
      fs.copyFileSync('./src/index.html', path.join(path.dirname(OUTPUT_FILE), 'index.html'));
    }
  }
}

pack();