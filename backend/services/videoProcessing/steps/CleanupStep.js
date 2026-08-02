import IBaseStep from '../IBaseStep.js';
import storageManager from '../../storageSystem/StorageManager.js';
import fs from 'fs';
import path from 'path';

/**
 * Pipeline Step: Final Cleanup
 */
class CleanupStep extends IBaseStep {
  constructor() {
    super('FinalCleanup');
  }

  async execute(context) {
    const { videoId, rawVideoKey, hlsResult, tempDir, localRawPath } = context;

    // 1. Delete original from R2 if encoded successfully
    if (rawVideoKey && hlsResult) {
      try {
        console.log(`🧹 CleanupStep: Deleting source from R2: ${rawVideoKey}`);
        await storageManager.active.delete(rawVideoKey);
      } catch (e) {
        console.warn('⚠️ CleanupStep: Failed to delete R2 source:', e.message);
      }
    }

    // 2. Delete entire per-job temp directory (covers raw file + any partial HLS output)
    if (tempDir && fs.existsSync(tempDir)) {
      try {
        fs.rmSync(tempDir, { recursive: true, force: true });
        console.log(`🧹 CleanupStep: Temp directory deleted: ${tempDir}`);
      } catch (e) {
        console.warn('⚠️ CleanupStep: Failed to delete temp directory:', e.message);
      }
    } else if (localRawPath && fs.existsSync(localRawPath)) {
      // Fallback: delete individual file if tempDir not set (backwards compat)
      try {
        fs.unlinkSync(localRawPath);
        console.log(`🧹 CleanupStep: Local file deleted: ${localRawPath}`);
      } catch (e) {
        console.warn('⚠️ CleanupStep: Failed to delete local file:', e.message);
      }
    }

    context.progress = 100;
  }
}

export default CleanupStep;
