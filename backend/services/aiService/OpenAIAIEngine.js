import { IAIEngine } from './IAIEngine.js';
import axios from 'axios';
import fs from 'fs';
import FormData from 'form-data';

/**
 * OpenAI AI Engine Implementation.
 * Swappable provider demonstrating plug-and-play capability using OpenAI APIs.
 */
export class OpenAIAIEngine extends IAIEngine {
  constructor() {
    super();
    this.apiKey = process.env.OPENAI_API_KEY ? process.env.OPENAI_API_KEY.trim() : null;
  }

  /**
   * Translates English text to a target language using GPT-4o-mini
   */
  async translate(text, targetLang = 'hi_IN') {
    if (!this.apiKey) {
      console.warn('⚠️ [OpenAI AI Engine] API Key missing, falling back to original text');
      return text;
    }

    try {
      const languageMap = {
        'hi_IN': 'Hindi',
        'hindi': 'Hindi',
        'en_XX': 'English',
        'english': 'English'
      };
      
      const targetLanguageName = languageMap[targetLang] || 'Hindi';

      const response = await axios.post(
        'https://api.openai.com/v1/chat/completions',
        {
          model: 'gpt-4o-mini',
          messages: [
            {
              role: 'system',
              content: `You are an expert translator. Translate the user text into natural, spoken-style ${targetLanguageName}. Only return the translation, no extra commentary.`
            },
            {
              role: 'user',
              content: text
            }
          ],
          temperature: 0.3
        },
        {
          headers: {
            'Authorization': `Bearer ${this.apiKey}`,
            'Content-Type': 'application/json'
          }
        }
      );

      return response.data?.choices?.[0]?.message?.content?.trim() || text;
    } catch (error) {
      console.error('❌ [OpenAI AI Engine] Translation error:', error.message);
      return text;
    }
  }

  /**
   * Transcribes audio using OpenAI Whisper API
   */
  async transcribe(audioPath) {
    if (!this.apiKey) throw new Error('OPENAI_API_KEY is missing');

    try {
      const form = new FormData();
      form.append('file', fs.createReadStream(audioPath));
      form.append('model', 'whisper-1');

      console.log(`🎙️ [OpenAI AI Engine] Sending audio to OpenAI Whisper API...`);

      const response = await axios.post(
        'https://api.openai.com/v1/audio/transcriptions',
        form,
        {
          headers: {
            'Authorization': `Bearer ${this.apiKey}`,
            ...form.getHeaders()
          },
          maxContentLength: Infinity,
          maxBodyLength: Infinity
        }
      );

      if (response.data && response.data.text) {
        console.log(`✅ [OpenAI AI Engine] Transcription success: "${response.data.text.substring(0, 50)}..."`);
        return response.data.text;
      }
      
      throw new Error('OpenAI transcription response invalid');
    } catch (error) {
      console.error('❌ [OpenAI AI Engine] Transcription error:', error.message);
      throw error;
    }
  }

  /**
   * Synthesizes speech using OpenAI TTS API
   */
  async synthesize(text, language = 'hindi', outputPath) {
    if (!this.apiKey) throw new Error('OPENAI_API_KEY is missing');

    try {
      console.log(`🔊 [OpenAI AI Engine] Synthesizing speech using OpenAI TTS...`);

      const response = await axios.post(
        'https://api.openai.com/v1/audio/speech',
        {
          model: 'tts-1',
          input: text,
          voice: language.toLowerCase() === 'hindi' ? 'alloy' : 'nova',
          response_format: 'wav'
        },
        {
          headers: {
            'Authorization': `Bearer ${this.apiKey}`,
            'Content-Type': 'application/json'
          },
          responseType: 'arraybuffer'
        }
      );

      fs.writeFileSync(outputPath, response.data);
      console.log(`✅ [OpenAI AI Engine] Synthesis complete: ${outputPath}`);
      return outputPath;
    } catch (error) {
      console.error('❌ [OpenAI AI Engine] Synthesis error:', error.message);
      throw error;
    }
  }

  /**
   * Summarizes a long text transcript using GPT-4o-mini
   */
  async summarize(text) {
    if (!this.apiKey) {
      console.warn('⚠️ [OpenAI AI Engine] API Key missing, failing summarization');
      throw new Error('OPENAI_API_KEY is missing');
    }

    try {
      console.log(`📝 [OpenAI AI Engine] Sending text to GPT-4o-mini for summarization (${text.length} chars)...`);

      const response = await axios.post(
        'https://api.openai.com/v1/chat/completions',
        {
          model: 'gpt-4o-mini',
          messages: [
            {
              role: 'system',
              content: 'You are an expert at summarizing long video transcripts. Provide a concise, clear summary of the main points in a short paragraph.'
            },
            {
              role: 'user',
              content: text
            }
          ],
          temperature: 0.3
        },
        {
          headers: {
            'Authorization': `Bearer ${this.apiKey}`,
            'Content-Type': 'application/json'
          }
        }
      );

      return response.data?.choices?.[0]?.message?.content?.trim() || '';
    } catch (error) {
      console.error('❌ [OpenAI AI Engine] Summarization error:', error.message);
      throw error;
    }
  }
}
