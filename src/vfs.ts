import { AssetBundle } from "./interface/AssetBundle.js";

export interface VirtualFetchOptions {
  prefix?: string;
}

export function installVirtualFetch(bundle: AssetBundle, options: VirtualFetchOptions = {}): () => void {
  const originalFetch = window.fetch;
  const prefix = options.prefix ? options.prefix.replace(/^\/+|\/+$/g, '') + '/' : '';

  window.fetch = async function (
    input: RequestInfo | URL,
    init?: RequestInit
  ): Promise<Response> {
    let urlString: string;
    if (typeof input === 'string') {
      urlString = input;
    } else if (input instanceof URL) {
      urlString = input.pathname;
    } else {
      urlString = input.url;
    }

    try {
      const parsed = new URL(urlString, window.location.origin);
      urlString = parsed.pathname;
    } catch {
    }

    let normalizedKey = urlString.replace(/^\/+/, '');
    if (prefix && normalizedKey.startsWith(prefix)) {
      normalizedKey = normalizedKey.slice(prefix.length);
    }

    if (bundle.has(normalizedKey)) {
      const asset = await bundle.get(normalizedKey);
      const body = new ArrayBuffer(asset.bytes.byteLength);
      new Uint8Array(body).set(asset.bytes);

      return new Response(body, {
        status: 200,
        statusText: 'OK',
        headers: {
          'Content-Type': asset.mime,
          'Content-Length': String(asset.bytes.byteLength),
          'X-Virtual-Asset': 'true'
        }
      });
    }

    return originalFetch.call(window, input, init);
  };

  return function uninstall() {
    window.fetch = originalFetch;
  };
}