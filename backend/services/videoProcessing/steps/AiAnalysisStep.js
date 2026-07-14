import IBaseStep from '../IBaseStep.js';
import geminiService from '../../geminiService.js';
import Video from '../../../models/Video.js';
import recommendationService from '../../yugFeedServices/recommendationService.js';
import path from 'path';
import fs from 'fs';
import { exec } from 'child_process';
import { promisify } from 'util';
import os from 'os';

const execPromise = promisify(exec);

/**
 * Pipeline Step: AI Content Analysis using Gemini
 */
class AiAnalysisStep extends IBaseStep {
  constructor() {
    super('AiAnalysis');
  }

  async execute(context) {
    const { videoId, localRawPath } = context;
    
    if (!process.env.GEMINI_API_KEY) {
      console.warn('⚠️ AiAnalysisStep: Skipping because GEMINI_API_KEY is not set');
      return;
    }

    const video = await Video.findById(videoId);
    if (!video) return;

    console.log(`🧠 AiAnalysisStep: Extracting frames for video ${videoId}...`);
    const tempFrames = [];
    
    try {
      const duration = video.duration || 10;
      const timestamps = [0.1, 0.3, 0.5, 0.7, 0.9].map(p => duration * p);
      const tempDir = os.tmpdir();

      // Extract frames (takes 1-2 seconds)
      for (let i = 0; i < timestamps.length; i++) {
        const framePath = path.join(tempDir, `frame_${videoId}_${i}.jpg`);
        try {
          await execPromise(`ffmpeg -ss ${timestamps[i]} -i "${localRawPath}" -frames:v 1 -q:v 2 "${framePath}" -y`);
          if (fs.existsSync(framePath)) tempFrames.push(framePath);
        } catch (e) {
          console.warn(`⚠️ AiAnalysisStep: Failed to extract frame at ${timestamps[i]}s`);
        }
      }

      // Start the Gemini analysis asynchronously in the background without awaiting it!
      this._runAiAnalysisInBackground(videoId, tempFrames, video).catch(err => {
        console.error(`❌ AiAnalysisStep: Background analysis failed for ${videoId}:`, err);
      });

    } catch (error) {
      console.error(`❌ AiAnalysisStep: Frame extraction failed for ${videoId}:`, error);
      // Clean up frames if extraction failed before background worker took over
      for (const frame of tempFrames) {
        if (fs.existsSync(frame)) fs.unlinkSync(frame);
      }
    }
  }

  /**
   * Helper to execute Gemini analysis in background
   */
  async _runAiAnalysisInBackground(videoId, tempFrames, video) {
    try {
      console.log(`🧠 AiAnalysisStep: Starting background Gemini analysis for ${videoId}...`);
      const analysisInput = tempFrames.length > 0 ? tempFrames : [video.thumbnailUrl];

      const metadata = await geminiService.getVideoContext(analysisInput, {
        title: video.videoName,
        category: video.category,
        description: video.description
      });
      
      if (metadata) {
        await Video.findByIdAndUpdate(videoId, { 
          aiSummary: metadata.summary,
          language: metadata.language,
          detectedRegion: metadata.region,
          tags: [...new Set([...(video.tags || []), ...(metadata.keywords || [])])],
          aiContextGenerated: true 
        });
        
        // Update recommendation score with new metadata
        await recommendationService.calculateAndUpdateVideoScore(videoId);
        console.log(`✅ AiAnalysisStep: Background metadata enriched for ${videoId}`);
      }
    } catch (error) {
      console.error(`❌ AiAnalysisStep: Background analysis failed:`, error);
    } finally {
      // Clean up temp frames
      for (const frame of tempFrames) {
        if (fs.existsSync(frame)) {
          try {
            fs.unlinkSync(frame);
          } catch (e) {
            console.warn(`⚠️ AiAnalysisStep: Failed to delete temp frame:`, e.message);
          }
        }
      }
    }
  }
}

export default AiAnalysisStep;
