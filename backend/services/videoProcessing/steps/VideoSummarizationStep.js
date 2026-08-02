// ⚠️ VideoSummarizationStep DISABLED — saves CPU (ffmpeg audio extraction) + memory
// (Groq Whisper transcription, DeepSeek semantic text, Gemini embedding API calls)
// To re-enable, uncomment the code below.

/*
import IBaseStep from '../IBaseStep.js';
import Video from '../../../models/Video.js';
import AIService from '../../aiService.js';
import aiSemanticService from '../../yugFeedServices/aiSemanticService.js';
import deepseekService from '../../deepseekService.js';
import path from 'path';
import fs from 'fs';
import ffmpegStatic from 'ffmpeg-static';
import { exec } from 'child_process';
import { promisify } from 'util';
import os from 'os';

const execPromise = promisify(exec);

class VideoSummarizationStep extends IBaseStep {
  constructor() {
    super('VideoSummarization');
  }

  async execute(context) {
    const { videoId, localRawPath } = context;

    if (!process.env.GROQ_API_KEY && !process.env.HF_TOKEN) {
      console.warn('⚠️ VideoSummarizationStep: Skipping because neither GROQ_API_KEY nor HF_TOKEN is set');
      return;
    }

    const video = await Video.findById(videoId);
    if (!video) return;

    const tempDir = os.tmpdir();
    const audioPath = path.join(tempDir, `audio_${videoId}_${Date.now()}.wav`);

    try {
      console.log(`📝 VideoSummarizationStep: Extracting audio for video ${videoId}...`);

      const ffmpegPath = ffmpegStatic || 'ffmpeg';
      await execPromise(`"${ffmpegPath}" -y -i "${localRawPath}" -vn -acodec pcm_s16le -ar 16000 -ac 1 "${audioPath}"`);

      if (!fs.existsSync(audioPath)) {
        throw new Error('Audio extraction failed: File not created');
      }

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

  async _transcribe(audioPath) {
    if (process.env.GROQ_API_KEY) {
      return this._transcribeWithGroq(audioPath);
    }
    console.log('ℹ️ VideoSummarizationStep: GROQ_API_KEY not found, falling back to HF Whisper');
    return AIService.transcribe(audioPath);
  }

  async _transcribeWithGroq(audioPath) {
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

  async _runSummarizationInBackground(videoId, audioPath) {
    try {
      console.log(`📝 VideoSummarizationStep: Transcribing audio for video ${videoId}...`);
      const transcript = await this._transcribe(audioPath);

      if (!transcript || transcript.trim().length < 10) {
        console.warn(`⚠️ VideoSummarizationStep: Empty or too short transcript for video ${videoId}, skipping.`);
        return;
      }

      const safeTranscript = transcript.substring(0, 1500);
      const fullVideo = await Video.findById(videoId);

      console.log(`🧠 VideoSummarizationStep: Generating rich semantic text via DeepSeek for video ${videoId}...`);
      const semanticText = await deepseekService.generateSemanticText(safeTranscript, {
        title: fullVideo.videoName,
        category: fullVideo.category,
        tags: fullVideo.tags
      });

      if (!semanticText) {
        console.warn(`⚠️ VideoSummarizationStep: DeepSeek returned empty semantic text for ${videoId}, using fallback`);
      }

      const embeddingSource = semanticText || `Title: ${fullVideo.videoName || ''}. Category: ${fullVideo.category || ''}. Tags: ${(fullVideo.tags || []).join(', ')}. Transcript: ${safeTranscript}`.trim();

      console.log(`🧠 VideoSummarizationStep: Generating vector embedding for semantic search...`);
      const vectorEmbedding = await aiSemanticService.getEmbedding(embeddingSource);

      const updateData = {
        aiContext: safeTranscript,
        aiContextGenerated: true
      };

      if (vectorEmbedding) {
        updateData.vectorEmbedding = vectorEmbedding;
        updateData.embeddingVersion = aiSemanticService.getActiveModelName();
      }

      await Video.findByIdAndUpdate(videoId, updateData);
      console.log(`✅ VideoSummarizationStep: Summarization and embedding completed for ${videoId}`);

    } catch (error) {
      console.error(`❌ VideoSummarizationStep: Background summarization failed:`, error);
    } finally {
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
*/
