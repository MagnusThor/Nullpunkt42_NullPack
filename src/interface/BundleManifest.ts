import { AssetMeta } from "./AssetMeta.js";
import { BundleHeaderMeta } from "./FileEntry.js";


export interface BundleManifest {
  __meta__: BundleHeaderMeta;
  files: Record<string, AssetMeta>;
}
