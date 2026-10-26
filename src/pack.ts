import * as fs from 'node:fs';
import * as path from 'node:path';
import * as zlib from 'node:zlib';
import type { BundleManifest } from './interface/BundleManifest.js';

interface Settings {
  assetsDir?: string;
  output?: string;
  runnerFile?: string;
}

function loadSettings(): Required<Settings> {
  const defaults: Required<Settings> = {
    assetsDir: './assets',
    output: './output/demo.bin',
    runnerFile: 'runner.js'
  };

  const settingsPath = path.resolve(process.cwd(), 'settings.json');
  if (fs.existsSync(settingsPath)) {
    try {
      const raw = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
      return {
        assetsDir: raw.assetsDir?.trim() || defaults.assetsDir,
        output: raw.output?.trim() || defaults.output,
        runnerFile: raw.runnerFile?.trim() || defaults.runnerFile
      };
    } catch (e) {
      console.warn('Warning: Could not parse settings.json, using defaults.', e);
    }
  }

  return defaults;
}

const settings = loadSettings();
const ASSETS_DIR = path.resolve(process.argv[2] ?? settings.assetsDir);
const OUTPUT_FILE = path.resolve(process.argv[3] ?? settings.output);
const RUNNER_FILE = settings.runnerFile;

const NO_COMPRESS = new Set<string>([
  '.png', '.jpg', '.jpeg', '.webp', '.gif',
  '.mp3', '.ogg', '.aac', '.flac',
  '.mp4', '.webm', '.wasm', '.woff2'
]);

const MIME_MAP: Record<string, string> = {
  '.js':   'application/javascript',
  '.mjs':  'application/javascript',
  '.glsl': 'text/plain',
  '.vert': 'text/plain',
  '.frag': 'text/plain',
  '.wgsl': 'text/plain',
  '.json': 'application/json',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.mp3':  'audio/mpeg',
  '.ogg':  'audio/ogg',
  '.wav':  'audio/wav'
};

function getAllFiles(dir: string, fileList: string[] = []): string[] {
  if (!fs.existsSync(dir)) {
    throw new Error(`Assets directory does not exist: "${dir}"`);
  }
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      getAllFiles(fullPath, fileList);
    } else {
      fileList.push(fullPath);
    }
  }
  return fileList;
}

function pack(): void {
  const files = getAllFiles(ASSETS_DIR);
  const manifest: BundleManifest = {
    __meta__: {
      runnerFile: RUNNER_FILE,
      created: Date.now()
    },
    files: {}
  };

  const chunks: Buffer[] = [];
  let currentOffset = 0;

  for (const filePath of files) {
    const relKey = path.relative(ASSETS_DIR, filePath).replace(/\\/g, '/');
    const ext = path.extname(filePath).toLowerCase();
    const rawData = fs.readFileSync(filePath);
    const origSize = rawData.length;

    let finalData = rawData;
    let isCompressed = false;

    if (!NO_COMPRESS.has(ext)) {
      const deflated = zlib.deflateRawSync(rawData, { level: 9 });
      if (deflated.length < origSize) {
        finalData = deflated;
        isCompressed = true;
      }
    }

    manifest.files[relKey] = {
      offset: currentOffset,
      size: finalData.length,
      origSize,
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

  const finalPackage = Buffer.concat([header, manifestBuffer, ...chunks]);

  fs.mkdirSync(path.dirname(OUTPUT_FILE), { recursive: true });
  fs.writeFileSync(OUTPUT_FILE, finalPackage);

  const origTotal = Object.values(manifest.files).reduce((s, m) => s + m.origSize, 0);
  console.log(`\n========================================`);
  console.log(`Source folder : ${ASSETS_DIR}`);
  console.log(`Packed files  : ${files.length}`);
  console.log(`Runner Entry  : ${RUNNER_FILE}`);
  console.log(`Output        : ${OUTPUT_FILE}`);
  console.log(`Raw Size      : ${(origTotal / 1024).toFixed(1)} KB`);
  console.log(`Bundle Size   : ${(finalPackage.length / 1024).toFixed(1)} KB`);
  console.log(`========================================\n`);

  const outDir = path.dirname(OUTPUT_FILE);
  const htmlSrc = path.resolve('./src/index.html');
  
  if (fs.existsSync(htmlSrc)) {
    const htmlDest = path.join(outDir, 'index.html');
    fs.copyFileSync(htmlSrc, htmlDest);
    console.log(`Copied launcher to: ${htmlDest}\n`);
  } else {
    console.warn(`Warning: Could not find launcher at ${htmlSrc} to copy.\n`);
  }
}

pack();