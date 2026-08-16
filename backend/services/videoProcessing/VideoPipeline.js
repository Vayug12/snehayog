import Video from '../../models/Video.js';
import fs from 'fs';
import { beat } from '../../utils/progressHeartbeat.js';
import { markVideoUploadFailed } from '../uploadServices/videoUploadLifecycleService.js';

/**
 * FFmpeg-style Video Processing Engine (The Orchestrator)
 */
class VideoPipeline {
  constructor() {
    this.steps = [];
  }

  /**
   * Add a step to the pipeline
   * @param {IBaseStep} step 
   */
  addStep(step) {
    this.steps.push(step);
    return this;
  }

  /**
   * Run the full pipeline for a video
   * @param {Object} initialContext - Initial data (videoId, etc.)
   */
  async run(initialContext) {
    const { videoId } = initialContext;
    const context = { ...initialContext };
    
    console.log(`🎬 Pipeline: Starting for video ${videoId}`);
    const pipelineStart = Date.now();
    const timings = [];

    try {
      for (const step of this.steps) {
        console.log(`⏳ Pipeline: Executing [${step.getName()}]...`);
        const stepStart = Date.now();

        // Step boundaries mote-mote heartbeats hain. DownloadSource aur Cleanup
        // jaise steps andar se koi progress nahi dete, isliye watchdog ke liye
        // yehi unka ekmatra "zinda hoon" signal hai.
        beat();

        await step.execute(context);

        beat();

        const stepSec = (Date.now() - stepStart) / 1000;
        timings.push(`${step.getName()}=${stepSec.toFixed(1)}s`);
        console.log(`⏱️ Pipeline: [${step.getName()}] finished in ${stepSec.toFixed(1)}s`);

        // Optional: Update progress in DB if available
        if (context.progress) {
          await Video.findByIdAndUpdate(videoId, { processingProgress: context.progress });
        }
      }

      const totalSec = (Date.now() - pipelineStart) / 1000;
      console.log(`✅ Pipeline: Completed successfully for ${videoId} in ${totalSec.toFixed(1)}s | ${timings.join(' | ')}`);
      return context;
    } catch (error) {
      const totalSec = (Date.now() - pipelineStart) / 1000;
      console.error(`❌ Pipeline: Failed for ${videoId} after ${totalSec.toFixed(1)}s | completed steps: ${timings.join(' | ') || 'none'}`);
      console.error(`❌ Pipeline: Failed at step for ${videoId}:`, error);
      
      // Update DB with failure
      await markVideoUploadFailed(videoId, error);
      
      // Cleanup local temp file on ANY failure to save disk space
      if (context.localRawPath && fs.existsSync(context.localRawPath)) {
        try {
          fs.unlinkSync(context.localRawPath);
          console.log(`🧹 Pipeline: Cleaned up local file after failure: ${context.localRawPath}`);
        } catch (cleanupErr) {
          console.warn('⚠️ Pipeline: Failed to clean up local file on failure:', cleanupErr.message);
        }
      }
      
      throw error;
    }
  }
}

export default VideoPipeline;
