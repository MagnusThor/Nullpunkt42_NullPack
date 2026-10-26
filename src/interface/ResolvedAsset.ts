export interface ResolvedAsset {
  bytes: Uint8Array;
  blob: Blob;
  mime: string;
  url: string;
  text: () => string;
}