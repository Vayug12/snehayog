import axios from 'axios';
import apiRateLimiter from './rateLimiting/apiRateLimiter.js';

/**
 * LLM Service — Multi-provider with free-first fallback chain.
 * Priority: Gemini Flash (free) → OpenRouter (free) → SiliconFlow (free) → DeepSeek (paid) → concat fallback
 * 
 * Gemini Flash free tier: 1000 requests/day, 2 RPM
 */
class DeepSeekService {
  constructor() {
    this.apiKey = process.env.DEEPSEEK_API_KEY;
    this.baseUrl = process.env.DEEPSEEK_BASE_URL || 'https://api.deepseek.com';
    this.model = process.env.DEEPSEEK_MODEL || 'deepseek-chat';
  }

  async _callLLM(url, apiKey, model, prompt, options = {}) {
    const maxRetries = options.retries ?? 1;
    let lastError;

    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        const response = await axios.post(`${url}/chat/completions`, {
          model,
          messages: [{ role: 'user', content: prompt }],
          max_tokens: options.maxTokens || 200,
          temperature: options.temperature ?? 0.2,
          ...(options.responseFormat ? { response_format: options.responseFormat } : {})
        }, {
          headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json'
          },
          timeout: options.timeout || 15000
        });
        const content = response.data.choices[0]?.message?.content;
        if (!content) {
          lastError = new Error('Empty response from LLM');
          if (attempt < maxRetries) {
            console.warn(`⚠️ [${model}] Empty response, retrying...`);
            await new Promise(r => setTimeout(r, 1000));
            continue;
          }
          throw lastError;
        }
        return content.trim();
      } catch (error) {
        lastError = error;
        if (attempt < maxRetries && !error.response) {
          await new Promise(r => setTimeout(r, 1000));
          continue;
        }
        throw error;
      }
    }
    throw lastError;
  }

  /**
   * Gemini 2.0 Flash via Google AI Studio REST API (free: 1000/day, 2 RPM)
   */
  async _callGeminiFlash(prompt, options = {}) {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) return null;

    // Rate limit
    const { allowed } = await apiRateLimiter.wait('gemini');
    if (!allowed) {
      console.warn('⚠️ [Gemini Flash] Daily quota exhausted, skipping');
      return null;
    }

    try {
      const model = process.env.GEMINI_MODEL || 'gemini-2.0-flash';
      const genConfig = {
        maxOutputTokens: options.maxTokens || 200,
        temperature: options.temperature ?? 0.3
      };

      // Force JSON output when caller expects JSON
      if (options.responseFormat?.type === 'json_object') {
        genConfig.responseMimeType = 'application/json';
      }

      const response = await axios.post(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
        {
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: genConfig
        },
        { timeout: options.timeout || 30000 }
      );

      const content = response.data?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (content) {
        console.log('✅ [Gemini Flash] Response received');
        return content.trim();
      }
      return null;
    } catch (error) {
      const errMsg = error.response?.data?.error?.message || error.message;
      console.warn(`⚠️ [Gemini Flash] Failed: ${errMsg}`);
      return null;
    }
  }

  _getProviders() {
    return [
      {
        name: 'Gemini Flash',
        customCall: (prompt, opts) => this._callGeminiFlash(prompt, opts)
      },
      {
        name: 'OpenRouter',
        url: 'https://openrouter.ai/api/v1',
        apiKey: process.env.OPENROUTER_API_KEY,
        model: process.env.OPENROUTER_CHAT_MODEL || 'openai/gpt-oss-20b:free'
      },
      {
        name: 'SiliconFlow',
        url: process.env.SILICONFLOW_BASE_URL || 'https://api.siliconflow.com/v1',
        apiKey: process.env.SILICONFLOW_API_KEY,
        model: process.env.SILICONFLOW_CHAT_MODEL || 'deepseek-ai/DeepSeek-V4-Flash'
      },
      {
        name: 'DeepSeek',
        url: `${this.baseUrl}/v1`,
        apiKey: this.apiKey,
        model: this.model
      }
    ];
  }

  async _callWithFallback(prompt, options = {}) {
    for (const provider of this._getProviders()) {
      if (!provider.apiKey && !provider.customCall) continue;
      try {
        let result;
        if (provider.customCall) {
          result = await provider.customCall(prompt, options);
        } else {
          result = await this._callLLM(provider.url, provider.apiKey, provider.model, prompt, { ...options, retries: 1 });
        }
        if (result) {
          console.log(`✅ [${provider.name}] Response received`);
          return result;
        }
      } catch (error) {
        const errMsg = error.response?.data?.error?.message || error.message;
        console.warn(`⚠️ [${provider.name}] Failed: ${errMsg}`);
      }
    }
    return null;
  }

  async getVideoContext(transcript, videoMetadata = {}) {
    const prompt = `Analyze this video transcript and provide structured findings in JSON.

Video Info:
- Title: ${videoMetadata.title || 'Unknown'}
- Category: ${videoMetadata.category || 'General'}
- Description: ${videoMetadata.description || 'None'}

Transcript:
${transcript.substring(0, 3000)}

Return strictly valid JSON with these fields:
1. "summary": Detailed summary in Hinglish (mix of Hindi/English). 2-3 sentences.
2. "oneLineAbout": Short catchy one-line description.
3. "language": Primary language spoken.
4. "region": Region (North India, South India, Global, etc.).
5. "keywords": Array of 8-10 relevant tags/keywords.
6. "activity": What is happening in this video? Be specific.
7. "topics": Array of main topics covered.
8. "difficulty": beginner, intermediate, or advanced.`;

    const content = await this._callWithFallback(prompt, {
      maxTokens: 1000,
      temperature: 0.3,
      responseFormat: { type: 'json_object' },
      timeout: 30000
    });

    if (!content) return null;

    try {
      return typeof content === 'string' ? JSON.parse(content) : content;
    } catch {
      console.error('❌ Failed to parse LLM JSON response');
      return null;
    }
  }

  async generateSemanticText(transcript, videoMetadata = {}) {
    const prompt = `Given this video transcript and metadata, generate a concise semantic text (max 500 chars) that captures the core content for search indexing.

Title: ${videoMetadata.title || 'Unknown'}
Category: ${videoMetadata.category || 'General'}
Tags: ${(videoMetadata.tags || []).join(', ')}

Transcript:
${transcript.substring(0, 2000)}

Return ONLY the semantic text, no quotes or explanation. Focus on:
- What the video teaches/demonstrates
- Key technologies/concepts mentioned
- The practical outcome for the viewer`;

    const result = await this._callWithFallback(prompt);
    if (result) return result;

    console.warn(`⚠️ All LLM providers failed, using concat fallback`);
    return `Title: ${videoMetadata.title || ''}. Category: ${videoMetadata.category || ''}. Tags: ${(videoMetadata.tags || []).join(', ')}. Transcript: ${transcript.substring(0, 800)}`;
  }
}

export default new DeepSeekService();
