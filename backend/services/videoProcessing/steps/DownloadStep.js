import IBaseStep from '../IBaseStep.js';
import storageManager from '../../storageSystem/StorageManager.js';
import path from 'path';
import fs from 'fs';

/**
 * Pipeline Step: Download Source from Storage
 */
class DownloadStep extends IBaseStep {
  constructor() {
    super('DownloadSource');
  }

  async execute(context) {
    const { videoId, rawVideoKey } = context;
    const tempDir = path.join(process.cwd(), 'temp_raw_downloads', videoId);
    
    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
    
    const localRawPath = path.join(tempDir, `raw${path.extname(rawVideoKey) || '.mp4'}`);
    
    await storageManager.active.download(rawVideoKey, localRawPath);
    
    context.localRawPath = localRawPath;
    context.tempDir = tempDir;
    context.progress = 15;
  }
}

export default DownloadStep;
