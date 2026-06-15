import { IAIEngine } from './IAIEngine.js';
import axios from 'axios';
import fs from 'fs';
import mime from 'mime-types';
import { exec } from 'child_process';
import util from 'util';

const execPromise = util.promisify(exec);

export class HuggingFaceAIEngine extends IAIEngine {
  constructor() {
    super();
    this.hfToken = process.env.HF_TOKEN ? process.env.HF_TOKEN.trim() : null;
    
    // Model URLs
    const base = 'https://router.huggingface.co/hf-inference/models';
    this.transcriptionModel = `${base}/openai/whisper-large-v3-turbo`;
    this.ttsHindiModel = `${base}/facebook/mms-tts-hin`;
    this.ttsEnglishModel = `${base}/facebook/mms-tts-eng`;
    this.translationModel = `${base}/facebook/mbart-large-50-many-to-many-mmt`;
    this.summarizationModel = `${base}/facebook/bart-large-cnn`;
  }

  /**
   * Translates text between languages using Hugging Face translation models
   */
  async translate(text, targetLang = 'hi_IN') {
    if (!this.hfToken) throw new Error('HF_TOKEN is missing');
    
    try {
      const response = await axios.post(this.translationModel, 
        { 
          inputs: text,
          parameters: { src_lang: "en_XX", tgt_lang: targetLang === 'hindi' ? "hi_IN" : "en_XX" }
        }, 
        {
          headers: { 'Authorization': `Bearer ${this.hfToken}` }
        }
      );
      return response.data[0]?.translation_text || text;
    } catch (error) {
      this._handleError(error, 'Translation');
      return text; // Fallback to original
    }
  }

  /**
   * Transcribes audio file using Whisper via Hugging Face
   */
  async transcribe(audioPath) {
    if (!this.hfToken) throw new Error('HF_TOKEN is missing');

    try {
      const audioData = fs.readFileSync(audioPath);
      const mimeType = mime.lookup(audioPath) || 'audio/wav';
      
      console.log(`🎙️ [HF AI Engine] Sending audio to Whisper (${audioData.length} bytes, type: ${mimeType})...`);
      
      const response = await axios.post(this.transcriptionModel, audioData, {
        headers: {
          'Authorization': `Bearer ${this.hfToken}`,
          'Content-Type': mimeType,
          'Accept': 'application/json'
        },
        timeout: 300000 // Increased to 5 minutes to allow free tier API enough time
      });

      if (response.data && response.data.text) {
        console.log(`✅ [HF AI Engine] Transcription success: "${response.data.text.substring(0, 50)}..."`);
        return response.data.text;
      }
      
      throw new Error('Transcription response format invalid');
    } catch (error) {
      this._handleError(error, 'Transcription');
      throw error;
    }
  }

  /**
   * Generates high-quality speech from text using Microsoft Edge TTS
   */
  async synthesize(text, language = 'hindi', outputPath) {
    const voice = language.toLowerCase() === 'hindi' ? 'hi-IN-SwaraNeural' : 'en-US-AriaNeural';

    try {
      console.log(`🔊 [HF AI Engine] Synthesizing ${language} voice with Edge TTS (${voice}) for: "${text.substring(0, 30)}..."`);
      
      const safeText = text.replace(/"/g, '\\"');
      const command = `edge-tts --text "${safeText}" --voice ${voice} --write-media "${outputPath}"`;
      
      await execPromise(command);
      
      console.log(`✅ [HF AI Engine] Synthesis complete: ${outputPath}`);
      return outputPath;
    } catch (error) {
      console.error(`❌ [HF AI Engine] Synthesis error:`, error.message);
      throw error;
    }
  }

  /**
   * Summarizes a long text transcript using BART Large CNN
   */
  async summarize(text) {
    if (!this.hfToken) throw new Error('HF_TOKEN is missing');

    try {
      console.log(`📝 [HF AI Engine] Sending text to BART for summarization (${text.length} chars)...`);
      
      const response = await axios.post(this.summarizationModel, 
        { inputs: text },
        {
          headers: { 'Authorization': `Bearer ${this.hfToken}` },
          timeout: 60000
        }
      );

      if (response.data && response.data.length > 0 && response.data[0].summary_text) {
        console.log(`✅ [HF AI Engine] Summarization success: "${response.data[0].summary_text.substring(0, 50)}..."`);
        return response.data[0].summary_text;
      }
      
      throw new Error('Summarization response format invalid');
    } catch (error) {
      this._handleError(error, 'Summarization');
      throw error;
    }
  }

  _handleError(error, context) {
    if (error.response?.status === 503) {
      console.warn(`⏳ [HF AI Engine] ${context} model is loading on Hugging Face...`);
      throw new Error('MODEL_LOADING');
    }
    
    let errorMessage = error.message;
    if (error.response?.data) {
       if (typeof error.response.data === 'string') {
          errorMessage = error.response.data.substring(0, 200).replace(/hf_[a-zA-Z0-9]+/g, 'hf_****');
       } else {
          errorMessage = JSON.stringify(error.response.data).replace(/hf_[a-zA-Z0-9]+/g, 'hf_****');
       }
    }
    
    console.error(`❌ [HF AI Engine] ${context} error:`, errorMessage);
  }
}
