import { InterceptFetchOptions } from "./interface/InterceptFetchOptions.js";
import { AssetBundle } from "./interface/AssetBundle.js";
import { AssetMeta } from "./interface/AssetMeta.js";
import { BundleManifest } from "./interface/BundleManifest.js";
import { FileEntry } from "./interface/FileEntry.js";
import { ResolvedAsset } from "./interface/ResolvedAsset.js";
import { LoadBundleOptions } from "./interface/LoadBundleOptions.js";


export async function loadAssetBundle(
  bundleUrl: string,
  options: LoadBundleOptions = {}
): Promise<AssetBundle> {
  const response = await fetch(bundleUrl);
  if (!response.ok) {
    throw new Error(`Failed to download bundle: ${response.status} ${response.statusText}`);
  }

  const arrayBuffer = await response.arrayBuffer();
  const view = new DataView(arrayBuffer);

  const magic = String.fromCharCode(
    view.getUint8(0), view.getUint8(1), view.getUint8(2), view.getUint8(3)
  );
  if (magic !== 'DEMO') {
    throw new Error(`Invalid bundle format: expected 'DEMO', got '${magic}'`);
  }

  const manifestLen = view.getUint32(4, true);
  const payloadStart = 8 + manifestLen;
  const manifestBytes = new Uint8Array(arrayBuffer, 8, manifestLen);
  const manifest: BundleManifest = JSON.parse(new TextDecoder().decode(manifestBytes));

  const cache = new Map<string, ResolvedAsset>();
  const objectUrls = new Set<string>();
  let originalFetch: typeof window.fetch | null = null;

  async function decompressChunk(chunk: Uint8Array): Promise<Uint8Array> {
    const stream = new Response(chunk as unknown as BodyInit).body!.pipeThrough(
      new DecompressionStream('deflate-raw')
    );
    const resultBuffer = await new Response(stream).arrayBuffer();
    return new Uint8Array(resultBuffer);
  }

  async function resolveEntry(key: string): Promise<ResolvedAsset> {
    const cached = cache.get(key);
    if (cached) return cached;

    const meta: AssetMeta | undefined = manifest.files[key as string];
    if (!meta) {
      throw new Error(`Asset not found in bundle: "${key}"`);
    }

    const rawChunk = new Uint8Array(
      arrayBuffer.slice(payloadStart + meta.offset, payloadStart + meta.offset + meta.size)
    );

    const bytes = meta.compressed ? await decompressChunk(rawChunk) : rawChunk;
    const blob = new Blob([bytes as unknown as BlobPart], { type: meta.mime });
    const url = URL.createObjectURL(blob);
    objectUrls.add(url);

    const entry: ResolvedAsset = {
      bytes,
      blob,
      mime: meta.mime,
      url,
      text: () => new TextDecoder().decode(bytes)
    };

    cache.set(key, entry);
    return entry;
  }

  function normalizeKey(inputPath: string, prefix?: string): string | null {
    let clean = inputPath;
    try {
      clean = new URL(inputPath, window.location.href).pathname;
    } catch {
      clean = inputPath.split('?')[0].split('#')[0];
    }

    clean = clean.replace(/^(\.\/|\/)+/, '');

    if (clean in manifest.files) return clean;

    if (prefix) {
      const cleanPrefix = prefix.replace(/^\/+|\/+$/g, '') + '/';
      if (clean.startsWith(cleanPrefix)) {
        const stripped = clean.slice(cleanPrefix.length);
        if (stripped in manifest.files) return stripped;
      }
    }

    return null;
  }

  const bundle: AssetBundle = {
    meta: manifest.__meta__,

    has(key: string): boolean {
      return key in manifest.files;
    },

    listFiles(): FileEntry[] {
      return Object.entries(manifest.files).map(([filePath, meta]) => ({
        path: filePath,
        size: meta.size,
        origSize: meta.origSize,
        compressed: meta.compressed,
        mime: meta.mime
      }));
    },

    async get(key: string): Promise<ResolvedAsset> {
      return resolveEntry(key);
    },

    async text(key: string): Promise<string> {
      return (await resolveEntry(key)).text();
    },

    async blob(key: string): Promise<Blob> {
      return (await resolveEntry(key)).blob;
    },

    async url(key: string): Promise<string> {
      return (await resolveEntry(key)).url;
    },

    async buffer(key: string): Promise<ArrayBuffer> {
      return (await resolveEntry(key)).bytes.buffer as ArrayBuffer;
    },

    interceptFetch(fetchOpts: InterceptFetchOptions = {}): () => void {
      if (originalFetch !== null) return () => bundle.dispose();

      originalFetch = window.fetch;
      const nativeFetch = originalFetch;

      window.fetch = async function (
        input: RequestInfo | URL,
        init?: RequestInit
      ): Promise<Response> {
        let reqUrl = '';
        if (typeof input === 'string') reqUrl = input;
        else if (input instanceof URL) reqUrl = input.href;
        else if (input instanceof Request) reqUrl = input.url;

        const matchedKey = normalizeKey(reqUrl, fetchOpts.prefix);
        if (matchedKey !== null) {
          const asset = await resolveEntry(matchedKey);
          return new Response(asset.blob, {
            status: 200,
            statusText: 'OK',
            headers: {
              'Content-Type': asset.mime,
              'Content-Length': String(asset.bytes.byteLength),
              'X-Virtual-Asset': 'true'
            }
          });
        }

        return nativeFetch.call(window, input, init);
      };

      return function restore() {
        if (originalFetch) {
          window.fetch = originalFetch;
          originalFetch = null;
        }
      };
    },

    async run(entryFile?: string): Promise<unknown> {
      const target = entryFile || manifest.__meta__.runnerFile;
      if (!bundle.has(target)) {
        throw new Error(`Runner entry file "${target}" does not exist in the bundle.`);
      }

      const scriptAsset = await resolveEntry(target);
      // Dynamically import runner directly from in-memory Object URL
      const module = await import(/* @vite-ignore */ scriptAsset.url);

      if (typeof module.runDemo === 'function') {
        return module.runDemo(bundle);
      } else if (typeof module.default === 'function') {
        return module.default(bundle);
      }
      return module;
    },

    dispose(): void {
      if (originalFetch) {
        window.fetch = originalFetch;
        originalFetch = null;
      }
      for (const url of objectUrls) {
        URL.revokeObjectURL(url);
      }
      objectUrls.clear();
      cache.clear();
    }
  };

  if (options.interceptFetch) {
    bundle.interceptFetch({ prefix: options.fetchPrefix });
  }

  return bundle;
}