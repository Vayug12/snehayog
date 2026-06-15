import IBaseStep from '../IBaseStep.js';
import Video from '../../../models/Video.js';
import AIService from '../../aiService.js';
import aiSemanticService from '../../yugFeedServices/aiSemanticService.js';
import path from 'path';
import fs from 'fs';
import ffmpegStatic from 'ffmpeg-static';
import { exec } from 'child_process';
import { promisify } from 'util';
import os from 'os';

const execPromise = promisify(exec);

/**
 * Pipeline Step: AI Video Summarization
 * Extracts audio from the video, transcribes it, and generates a summary.
 */
class VideoSummarizationStep extends IBaseStep {
  constructor() {
    super('VideoSummarization');
  }

  async execute(context) {
    const { videoId, localRawPath } = context;
    
    // Quick check if HF_TOKEN is available, as we need it for transcription/summarization
    if (!process.env.HF_TOKEN) {
      console.warn('⚠️ VideoSummarizationStep: Skipping because HF_TOKEN is not set');
      return;
    }

    const video = await Video.findById(videoId);
    if (!video) return;

    const tempDir = os.tmpdir();
    const audioPath = path.join(tempDir, `audio_${videoId}_${Date.now()}.wav`);

    try {
      console.log(`📝 VideoSummarizationStep: Extracting audio for video ${videoId}...`);
      
      const ffmpegPath = ffmpegStatic || 'ffmpeg';
      
      // We MUST AWAIT the extraction here because CleanupStep runs immediately after this step 
      // and will delete the localRawPath.
      // Extract audio: 16kHz, mono, wav format (optimized for Whisper)
      await execPromise(`"${ffmpegPath}" -y -i "${localRawPath}" -vn -acodec pcm_s16le -ar 16000 -ac 1 "${audioPath}"`);
      
      if (!fs.existsSync(audioPath)) {
        throw new Error('Audio extraction failed: File not created');
      }

      // Start transcription and summarization in background to avoid blocking the pipeline
      this._runSummarizationInBackground(videoId, audioPath).catch(err => {
        console.error(`❌ VideoSummarizationStep: Background summarization failed for ${videoId}:`, err);
      });

    } catch (error) {
      console.error(`❌ VideoSummarizationStep: Audio extraction failed for ${videoId}:`, error);
      if (fs.existsSync(audioPath)) {
        fs.unlinkSync(audioPath);
      }
    }
  }

  /**
   * Helper to execute API calls for summarization in background
   */
  async _runSummarizationInBackground(videoId, audioPath) {
    try {
      console.log(`📝 VideoSummarizationStep: Transcribing audio for video ${videoId}...`);
      const transcript = await AIService.transcribe(audioPath);
      
      if (!transcript || transcript.trim().length === 0) {
        console.warn(`⚠️ VideoSummarizationStep: Empty transcript for video ${videoId}, skipping summarization.`);
        return;
      }

      // We truncate to 800 chars to fit safely within the MiniLM context window.
      const safeTranscript = transcript.substring(0, 800);
      
      let vectorEmbedding = null;
      if (safeTranscript) {
        // Fetch full video details to build a rich semantic string
        const fullVideo = await Video.findById(videoId);
        
        // Combine all relevant context for a powerful semantic embedding
        const semanticText = `Title: ${fullVideo.videoName || ''}. Category: ${fullVideo.category || ''}. Tags: ${(fullVideo.tags || []).join(', ')}. Transcript: ${safeTranscript}`.trim();
        
        console.log(`🧠 VideoSummarizationStep: Generating vector embedding for semantic search...`);
        vectorEmbedding = await aiSemanticService.getEmbedding(semanticText);
        
        const updateData = { 
          aiContext: safeTranscript,
          aiContextGenerated: true
        };
        
        if (vectorEmbedding) {
          updateData.vectorEmbedding = vectorEmbedding;
          updateData.embeddingVersion = 'v1_minilm';
        }

        await Video.findByIdAndUpdate(videoId, updateData);
        console.log(`✅ VideoSummarizationStep: Background summarization and embedding completed for ${videoId}`);
      }

    } catch (error) {
      console.error(`❌ VideoSummarizationStep: Background summarization failed:`, error);
    } finally {
      // Clean up temp audio file
      if (fs.existsSync(audioPath)) {
        try {
          fs.unlinkSync(audioPath);
        } catch (e) {
          console.warn(`⚠️ VideoSummarizationStep: Failed to delete temp audio:`, e.message);
        }
      }
    }
  }
}

export default VideoSummarizationStep;
