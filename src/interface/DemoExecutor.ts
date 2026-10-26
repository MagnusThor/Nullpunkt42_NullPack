import { AssetBundle } from "./AssetBundle.js";



export interface DemoExecutor {
  execute(bundle: AssetBundle): Promise<void>;
  dispose?(): void;
}
