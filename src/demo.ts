import { ShadertoyExecutor } from "./executors/ShadertoyExecutor.js";
import { AssetBundle } from "./interface/AssetBundle.js";

/**
 * Main entry point called by the HTML launcher after the VFS is unpacked.
 */
export async function runDemo(bundle: AssetBundle): Promise<void> {
  console.log('[Runner] Initializing Shadertoy Executor...');
  
  // Instantiate the isolated Shadertoy runtime
  const executor = new ShadertoyExecutor();
  
  try {
    // Hand over control and the virtual filesystem to the executor
    await executor.execute(bundle);
  } catch (error) {
    console.error('[Runner] Execution failed:', error);
    
    // Clean up resources if it crashes during initialization
    if (typeof executor.dispose === 'function') {
      executor.dispose();
    }
    
    throw error;
  }
}