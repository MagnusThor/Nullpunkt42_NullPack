// src/loader.ts
function extractPngPayload(buf) {
  const u8 = new Uint8Array(buf);
  const isPng = u8.length > 8 && u8[0] === 137 && u8[1] === 80 && u8[2] === 78 && u8[3] === 71;
  if (!isPng) return buf;
  const dv = new DataView(buf);
  let p = 8;
  while (p + 12 <= u8.length) {
    const len = dv.getUint32(p);
    const type = String.fromCharCode(u8[p + 4], u8[p + 5], u8[p + 6], u8[p + 7]);
    if (type === "nuPK") {
      const key = u8[p + 8];
      const data = u8.slice(p + 9, p + 8 + len);
      if (key) for (let i = 0; i < data.length; i++) data[i] ^= key;
      return data.buffer;
    }
    p += 12 + len;
  }
  throw new Error("PNG container has no 'nuPK' payload chunk");
}
async function loadAssetBundle(bundleUrl, options = {}) {
  const response = await fetch(bundleUrl);
  if (!response.ok) {
    throw new Error(`Failed to download bundle: ${response.status} ${response.statusText}`);
  }
  const arrayBuffer = extractPngPayload(await response.arrayBuffer());
  const view = new DataView(arrayBuffer);
  const magic = String.fromCharCode(
    view.getUint8(0),
    view.getUint8(1),
    view.getUint8(2),
    view.getUint8(3)
  );
  if (magic !== "DEMO") {
    throw new Error(`Invalid bundle format: expected 'DEMO', got '${magic}'`);
  }
  const manifestLen = view.getUint32(4, true);
  const payloadStart = 8 + manifestLen;
  const manifestBytes = new Uint8Array(arrayBuffer, 8, manifestLen);
  const manifest = JSON.parse(new TextDecoder().decode(manifestBytes));
  const cache = /* @__PURE__ */ new Map();
  const objectUrls = /* @__PURE__ */ new Set();
  let originalFetch = null;
  async function decompressChunk(chunk) {
    const stream = new Response(chunk).body.pipeThrough(
      new DecompressionStream("deflate-raw")
    );
    const resultBuffer = await new Response(stream).arrayBuffer();
    return new Uint8Array(resultBuffer);
  }
  async function resolveEntry(key) {
    const cached = cache.get(key);
    if (cached) return cached;
    const meta = manifest.files[key];
    if (!meta) {
      throw new Error(`Asset not found in bundle: "${key}"`);
    }
    const rawChunk = new Uint8Array(
      arrayBuffer.slice(payloadStart + meta.offset, payloadStart + meta.offset + meta.size)
    );
    const bytes = meta.compressed ? await decompressChunk(rawChunk) : rawChunk;
    const blob = new Blob([bytes], { type: meta.mime });
    const url = URL.createObjectURL(blob);
    objectUrls.add(url);
    const entry = {
      bytes,
      blob,
      mime: meta.mime,
      url,
      text: () => new TextDecoder().decode(bytes)
    };
    cache.set(key, entry);
    return entry;
  }
  function normalizeKey(inputPath, prefix) {
    let clean = inputPath;
    try {
      clean = new URL(inputPath, window.location.href).pathname;
    } catch {
      clean = inputPath.split("?")[0].split("#")[0];
    }
    clean = clean.replace(/^(\.\/|\/)+/, "");
    if (clean in manifest.files) return clean;
    if (prefix) {
      const cleanPrefix = prefix.replace(/^\/+|\/+$/g, "") + "/";
      if (clean.startsWith(cleanPrefix)) {
        const stripped = clean.slice(cleanPrefix.length);
        if (stripped in manifest.files) return stripped;
      }
    }
    return null;
  }
  const bundle = {
    meta: manifest.__meta__,
    has(key) {
      return key in manifest.files;
    },
    listFiles() {
      return Object.entries(manifest.files).map(([filePath, meta]) => ({
        path: filePath,
        size: meta.size,
        origSize: meta.origSize,
        compressed: meta.compressed,
        mime: meta.mime
      }));
    },
    async get(key) {
      return resolveEntry(key);
    },
    async text(key) {
      return (await resolveEntry(key)).text();
    },
    async blob(key) {
      return (await resolveEntry(key)).blob;
    },
    async url(key) {
      return (await resolveEntry(key)).url;
    },
    async buffer(key) {
      return (await resolveEntry(key)).bytes.buffer;
    },
    interceptFetch(fetchOpts = {}) {
      if (originalFetch !== null) return () => bundle.dispose();
      originalFetch = window.fetch;
      const nativeFetch = originalFetch;
      window.fetch = async function(input, init) {
        let reqUrl = "";
        if (typeof input === "string") reqUrl = input;
        else if (input instanceof URL) reqUrl = input.href;
        else if (input instanceof Request) reqUrl = input.url;
        const matchedKey = normalizeKey(reqUrl, fetchOpts.prefix);
        if (matchedKey !== null) {
          const asset = await resolveEntry(matchedKey);
          return new Response(asset.blob, {
            status: 200,
            statusText: "OK",
            headers: {
              "Content-Type": asset.mime,
              "Content-Length": String(asset.bytes.byteLength),
              "X-Virtual-Asset": "true"
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
    async run(entryFile) {
      const target = entryFile || manifest.__meta__.runnerFile;
      if (!bundle.has(target)) {
        throw new Error(`Runner entry file "${target}" does not exist in the bundle.`);
      }
      const scriptAsset = await resolveEntry(target);
      const module = await import(
        /* @vite-ignore */
        scriptAsset.url
      );
      if (typeof module.runDemo === "function") {
        return module.runDemo(bundle);
      } else if (typeof module.default === "function") {
        return module.default(bundle);
      }
      return module;
    },
    dispose() {
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
export {
  loadAssetBundle
};
