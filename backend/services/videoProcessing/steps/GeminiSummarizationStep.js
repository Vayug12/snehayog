import IBaseStep from '../IBaseStep.js';
import Video from '../../../models/Video.js';
import aiSemanticService from '../../yugFeedServices/aiSemanticService.js';
import deepseekService from '../../deepseekService.js';
import apiRateLimiter from '../../rateLimiting/apiRateLimiter.js';
import path from 'path';
import fs from 'fs';
import ffmpegStatic from 'ffmpeg-static';
import { exec } from 'child_process';
import { promisify } from 'util';
import os from 'os';

const execPromise = promisify(exec);

/**
 * Pipeline Step: Zero-Cost AI Video Summarization (Gemini)
 * 
 * Flow:
 * 1. Extract audio (ffmpeg)
 * 2. Transcribe via Groq Whisper (free: 7K/day, rate-limited)
 * 3. Generate semantic text via Gemini Flash (free: 1K/day, rate-limited)
 * 4. Generate 384-dim embedding via Gemini text-embedding-004 (free: 1K/day, rate-limited)
 * 
 * On quota exhaustion: marks video as pending, retries next day via autoResume cron.
 */
class GeminiSummarizationStep extends IBaseStep {
  constructor() {
    super('GeminiSummarization');
  }

  async execute(context) {
    const { videoId, localRawPath } = context;

    if (!process.env.GROQ_API_KEY && !process.env.HF_TOKEN) {
      console.warn('⚠️ GeminiSummarizationStep: Skipping — no GROQ_API_KEY or HF_TOKEN');
      return;
    }

    const video = await Video.findById(videoId);
    if (!video) return;

    const tempDir = os.tmpdir();
    const audioPath = path.join(tempDir, `audio_${videoId}_${Date.now()}.wav`);

    try {
      console.log(`📝 GeminiSummarizationStep: Extracting audio for ${videoId}...`);

      const ffmpegPath = ffmpegStatic || 'ffmpeg';
      await execPromise(`"${ffmpegPath}" -y -i "${localRawPath}" -vn -acodec pcm_s16le -ar 16000 -ac 1 "${audioPath}"`);

      if (!fs.existsSync(audioPath)) {
        throw new Error('Audio extraction failed: File not created');
      }

      // Await summarization synchronously since it now runs in a dedicated background queue job
      await this._runSummarizationInBackground(videoId, audioPath);

    } catch (error) {
      console.error(`❌ GeminiSummarizationStep: Audio extraction failed for ${videoId}:`, error);
      if (fs.existsSync(audioPath)) {
        fs.unlinkSync(audioPath);
      }
    }
  }

  /**
   * Transcribe using Groq Whisper API (free tier: 7000 requests/day, 180 RPM)
   */
  async _transcribe(audioPath) {
    if (process.env.GROQ_API_KEY) {
      return this._transcribeWithGroq(audioPath);
    }

    // Fallback to HuggingFace Whisper
    console.log('ℹ️ GeminiSummarizationStep: GROQ_API_KEY not found, falling back to HF Whisper');
    const AIService = (await import('../../aiService.js')).default;
    return AIService.transcribe(audioPath);
  }

  async _transcribeWithGroq(audioPath) {
    // Rate limit: Groq allows 180 RPM, we use 350ms delay
    await apiRateLimiter.wait('groq');

    const FormData = (await import('form-data')).default;
    const formData = new FormData();
    formData.append('file', fs.createReadStream(audioPath));
    formData.append('model', 'whisper-large-v3');
    formData.append('language', 'hi');
    formData.append('response_format', 'verbose_json');

    const response = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.GROQ_API_KEY}`,
        ...formData.getHeaders()
      },
      body: formData
    });

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`Groq API error ${response.status}: ${errText.substring(0, 200)}`);
    }

    const result = await response.json();
    return result.text;
  }

  /**
   * Full summarization pipeline with rate limiting
   */
  async _runSummarizationInBackground(videoId, audioPath) {
    try {
      // STEP 1: Transcribe (Groq — rate-limited)
      console.log(`📝 GeminiSummarizationStep: Transcribing audio for ${videoId}...`);
      const transcript = await this._transcribe(audioPath);

      if (!transcript || transcript.trim().length < 10) {
        console.warn(`⚠️ GeminiSummarizationStep: Empty/short transcript for ${videoId}, skipping.`);
        return;
      }

      const safeTranscript = transcript.substring(0, 1500);

      // STEP 2: Generate semantic text via Gemini Flash (rate-limited)
      const fullVideo = await Video.findById(videoId);

      console.log(`🧠 GeminiSummarizationStep: Generating semantic text via Gemini Flash for ${videoId}...`);
      const semanticText = await deepseekService.generateSemanticText(safeTranscript, {
        title: fullVideo.videoName,
        category: fullVideo.category,
        tags: fullVideo.tags
      });

      if (!semanticText) {
        console.warn(`⚠️ GeminiSummarizationStep: Gemini Flash returned empty semantic text for ${videoId}`);
      }

      // Use Gemini output if available, otherwise fallback to basic concat
      const embeddingSource = semanticText || `Title: ${fullVideo.videoName || ''}. Category: ${fullVideo.category || ''}. Tags: ${(fullVideo.tags || []).join(', ')}. Transcript: ${safeTranscript}`.trim();

      // STEP 3: Generate 384-dim embedding via Gemini (rate-limited)
      console.log(`🧠 GeminiSummarizationStep: Generating 384-dim embedding for ${videoId}...`);
      const vectorEmbedding = await aiSemanticService.getEmbedding(embeddingSource);

      const updateData = {
        aiContext: safeTranscript,
        aiContextGenerated: true
      };

      if (vectorEmbedding) {
        updateData.vectorEmbedding = vectorEmbedding;
        updateData.embeddingVersion = aiSemanticService.getActiveModelName(); // 'v3_gemini'
      }

      await Video.findByIdAndUpdate(videoId, updateData);
      console.log(`✅ GeminiSummarizationStep: Completed for ${videoId} (model: ${updateData.embeddingVersion || 'none'}, dims: ${vectorEmbedding?.length || 0})`);

    } catch (error) {
      console.error(`❌ GeminiSummarizationStep: Background summarization failed:`, error);

      // If Gemini quota exhausted, mark as pending for retry
      if (error.message?.includes('quota') || error.message?.includes('429') || error.message?.includes('Resource exhausted')) {
        await Video.findByIdAndUpdate(videoId, {
          embeddingVersion: 'pending',
          aiContextGenerated: false
        });
        console.log(`⏳ GeminiSummarizationStep: Marked ${videoId} as pending (will retry at midnight UTC)`);
      }
    } finally {
      // Clean up temp audio file
      if (fs.existsSync(audioPath)) {
        try {
          fs.unlinkSync(audioPath);
        } catch (e) {
          console.warn(`⚠️ GeminiSummarizationStep: Failed to delete temp audio:`, e.message);
        }
      }
    }
  }
}

export default GeminiSummarizationStep;
