import { GoogleGenerativeAI } from "@google/generative-ai";
import axios from 'axios';
import deepseekService from './deepseekService.js';

/**
 * Gemini Service
 * Handles Multimodal Video Analysis and Semantic Embeddings.
 * Provider priority: DeepSeek (cheapest) → OpenAI → Gemini
 */
class GeminiService {
    constructor() {
        this.apiKey = process.env.GEMINI_API_KEY;
        this.genAI = this.apiKey ? new GoogleGenerativeAI(this.apiKey) : null;
    }

    /**
     * Generates a detailed description using DeepSeek (Cheapest option).
     * Cost: ~$0.07/1M tokens vs Gemini $0.35/1M
     */
    async getDeepSeekContext(transcript, videoMetadata = {}) {
        return deepseekService.getVideoContext(transcript, videoMetadata);
    }

    /**
     * Generates a detailed description using OpenAI GPT-4o-mini (Multimodal).
     * Faster and higher rate limits for bulk migration.
     */
    async getOpenAIContext(imagePaths, videoMetadata = {}) {
        const openaiKey = process.env.OPENAI_API_KEY;
        if (!openaiKey) throw new Error("OPENAI_API_KEY is missing.");

        try {
            console.log(`🎬 [OpenAI] Analyzing sequence of ${imagePaths.length} frames...`);

            const content = [
                {
                    type: "text",
                    text: `Analyze this sequence of frames from a video to provide structured findings in JSON.
                    Video Info:
                    - Title: ${videoMetadata.title || 'Unknown'}
                    - Category: ${videoMetadata.category || 'General'}
                    - Description: ${videoMetadata.description || 'None'}

                    Return strictly valid JSON:
                    1. "summary": Detailed summary in Hinglish (mix of Hindi/English).
                    2. "oneLineAbout": Short catchy description.
                    3. "language": Primary language.
                    4. "region": Region (North India, South India, Global, etc.).
                    5. "keywords": Array of 8-10 tags.
                    6. "activity": What is happening?`
                }
            ];

            for (const imgPath of imagePaths) {
                let data;
                if (imgPath.startsWith('http')) {
                    const response = await axios.get(imgPath, { responseType: 'arraybuffer' });
                    data = Buffer.from(response.data).toString("base64");
                } else {
                    data = fs.readFileSync(imgPath).toString("base64");
                }
                
                content.push({
                    type: "image_url",
                    image_url: {
                        url: `data:image/jpeg;base64,${data}`
                    }
                });
            }

            const response = await axios.post('https://api.openai.com/v1/chat/completions', {
                model: "gpt-4o-mini",
                messages: [{ role: "user", content }],
                response_format: { type: "json_object" }
            }, {
                headers: { 'Authorization': `Bearer ${openaiKey}` }
            });

            const metadata = response.data.choices[0].message.content;
            const parsedData = typeof metadata === 'string' ? JSON.parse(metadata) : metadata;
            
            console.log(`✅ [OpenAI] Analysis complete for: ${videoMetadata.title || 'Video'}`);
            return parsedData;
        } catch (error) {
            console.error(`❌ [OpenAI] Failed:`, error.response?.data?.error?.message || error.message);
            return null;
        }
    }

    /**
     * Generates a detailed description of the video content.
     * Provider priority: OpenRouter (free) → SiliconFlow (free) → DeepSeek (paid) → OpenAI → Gemini
     */
    async getVideoContext(imagePaths, videoMetadata = {}) {
        // **Free/cheap LLM providers first (via deepseekService fallback chain)**
        console.log(`🎬 Using OpenRouter/SiliconFlow/DeepSeek for video analysis...`);
        const result = await this.getDeepSeekContext(
            videoMetadata.transcript || videoMetadata.description || '',
            videoMetadata
        );
        if (result) return result;
        console.warn('⚠️ All cheap/free LLM providers failed, trying OpenAI...');

        // **OpenAI: Multimodal fallback (if provider explicitly set)**
        const provider = process.env.AI_PROVIDER || 'openrouter';
        if (provider === 'openai') {
            return this.getOpenAIContext(imagePaths, videoMetadata);
        }

        // **Gemini: Final fallback (multimodal, more expensive)**
        if (!this.apiKey) {
            console.warn('⚠️ No providers available for video analysis');
            return null;
        }

        try {
            console.log(`🎬 [Gemini] Analyzing sequence of ${imagePaths.length} frames...`);
            
            const modelName = process.env.GEMINI_MODEL || "gemini-2.0-flash";
            const model = this.genAI.getGenerativeModel({ model: modelName });

            const parts = [];

            for (const imgPath of imagePaths) {
                let data;
                if (imgPath.startsWith('http')) {
                    const response = await axios.get(imgPath, { responseType: 'arraybuffer' });
                    data = Buffer.from(response.data).toString("base64");
                } else {
                    data = fs.readFileSync(imgPath).toString("base64");
                }
                
                parts.push({
                    inlineData: {
                        data,
                        mimeType: "image/jpeg"
                    }
                });
            }

            const prompt = `
                Analyze this sequence of frames from a video to provide structured findings in JSON.
                The video might be a compilation or edit of multiple clips.
                
                Video Info:
                - Title: ${videoMetadata.title || 'Unknown'}
                - Category: ${videoMetadata.category || 'General'}
                - Description: ${videoMetadata.description || 'None'}

                Return strictly valid JSON:
                1. "summary": Detailed summary in Hinglish (mix of Hindi/English).
                2. "oneLineAbout": Short catchy description.
                3. "language": Primary language.
                4. "region": Region.
                5. "keywords": Array of 8-10 tags.
                6. "activity": What is happening?
            `;

            let resultGemini;
            let retryCount = 0;
            const maxRetries = 3;

            while (retryCount <= maxRetries) {
                try {
                    resultGemini = await model.generateContent([prompt, ...parts]);
                    break; 
                } catch (err) {
                    if ((err.message.includes('429') || err.message.includes('Quota')) && retryCount < maxRetries) {
                        retryCount++;
                        const waitTime = retryCount * 15000;
                        console.warn(`⏳ [Gemini] Rate limit hit. Retry ${retryCount}/${maxRetries}...`);
                        await new Promise(resolve => setTimeout(resolve, waitTime));
                        continue;
                    }
                    throw err; 
                }
            }

            const responseText = resultGemini.response.text();
            const jsonMatch = responseText.match(/\{[\s\S]*\}/);
            if (!jsonMatch) throw new Error("Could not parse JSON from Gemini response");
            
            console.log(`✅ [Gemini] Analysis complete for: ${videoMetadata.title || 'Video'}`);
            return JSON.parse(jsonMatch[0]);
        } catch (error) {
            console.error(`❌ [Gemini] Failed:`, error.message);
            return null; 
        }
    }

    /**
     * Generates semantic embeddings for a given text.
     * Uses text-embedding-004 which is optimized for Hinglish/Multilingual.
     * @param {string} text - The text to embed (Title + Desc + Tags)
     * @returns {Promise<number[]>} - 768-dimensional vector
     */
    async getEmbedding(text) {
        if (!this.apiKey) throw new Error("GEMINI_API_KEY is missing.");

        const attempts = [
            { 
                url: `https://generativelanguage.googleapis.com/v1/models/gemini-embedding-2:embedContent?key=${this.apiKey}`,
                model: "gemini-embedding-2"
            },
            { 
                url: `https://generativelanguage.googleapis.com/v1/models/gemini-embedding-001:embedContent?key=${this.apiKey}`,
                model: "gemini-embedding-001"
            }
        ];

        for (const attempt of attempts) {
            try {
                const response = await axios.post(attempt.url, {
                    content: { parts: [{ text }] }
                });

                if (response.data && response.data.embedding) {
                    return response.data.embedding.values;
                }
            } catch (error) {
                const errMsg = error.response?.data?.error?.message || error.message;
                
                if (errMsg.includes('Resource exhausted') || error.response?.status === 429) {
                    console.warn(`⏳ [Gemini] Rate limit hit. Sleeping for 2s...`);
                    await new Promise(resolve => setTimeout(resolve, 2000)); // Wait 2s
                    // Recursive retry once after sleep
                    return this.getEmbedding(text); 
                }

                console.warn(`⚠️ [Gemini REST] Attempt with ${attempt.model} failed: ${errMsg}`);
                
                if (errMsg.includes('API key') || errMsg.includes('expired')) {
                    throw new Error(`Critical Auth Error: ${errMsg}`);
                }
            }
        }

        console.error(`❌ [Gemini REST] All attempts failed.`);
        return null;
    }
}

export default new GeminiService();
