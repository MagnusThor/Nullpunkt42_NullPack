import { InterceptFetchOptions } from "./InterceptFetchOptions.js";
import { BundleHeaderMeta, FileEntry } from "./FileEntry.js";
import { ResolvedAsset } from "./ResolvedAsset.js";

export interface AssetBundle {
  meta: BundleHeaderMeta;
  has(key: string): boolean;
  listFiles(): FileEntry[];
  get(key: string): Promise<ResolvedAsset>;
  text(key: string): Promise<string>;
  blob(key: string): Promise<Blob>;
  url(key: string): Promise<string>;
  buffer(key: string): Promise<ArrayBuffer>;
  interceptFetch(options?: InterceptFetchOptions): () => void;
  run(entryFile?: string): Promise<unknown>;
  dispose(): void;
}