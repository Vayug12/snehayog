/**
 * AI SEMANTIC SERVICE — Zero-Cost Gemini Embedding Pipeline
 * 
 * Embedding provider: Gemini text-embedding-004 (free tier: 1000/day, 2 RPM)
 * Output: 384-dimensional vectors (matches existing v3_gemini data)
 * 
 * IMPORTANT: All embeddings MUST be generated from the same model for vector search to work.
 * Model version tag: 'v3_gemini'
 */
import axios from 'axios';
import apiRateLimiter from '../rateLimiting/apiRateLimiter.js';

const GEMINI_EMBED_URL = 'https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent';
const EMBEDDING_DIMENSION = 384;

class AISemanticService {
  constructor() {
    this.cache = new Map();
    this.apiKey = process.env.GEMINI_API_KEY;
  }

  /**
   * Get the active embedding model name for version tagging
   */
  getActiveModelName() {
    return 'v3_gemini';
  }

  /**
   * Get embedding for text (Gemini text-embedding-004, 384-dim)
   * Rate-limited via apiRateLimiter (2 RPM, 1000/day)
   */
  async getEmbedding(text) {
    if (!text) return null;
    if (!this.apiKey) {
      console.warn('⚠️ AISemanticService: GEMINI_API_KEY not set');
      return null;
    }

    // Check cache (1hr TTL)
    const cacheKey = `gemini_384:${text.toLowerCase().trim().substring(0, 500)}`;
    if (this.cache.has(cacheKey)) return this.cache.get(cacheKey);

    // Wait for rate limit
    const { allowed, dailyRemaining } = await apiRateLimiter.wait('gemini');
    if (!allowed) {
      console.warn('⚠️ AISemanticService: Gemini daily quota exhausted, skipping embedding');
      return null;
    }

    try {
      const embedding = await this._getGeminiEmbedding(text);
      if (embedding) {
        this.cache.set(cacheKey, embedding);
        setTimeout(() => this.cache.delete(cacheKey), 3600000); // 1hr TTL
        return embedding;
      }
    } catch (error) {
      const errMsg = error.response?.data?.error?.message || error.message;
      console.warn(`⚠️ AISemanticService: Gemini embedding failed: ${errMsg}`);
    }

    return null;
  }

  /**
   * Gemini text-embedding-004 with output_dimensionality=384
   * Free tier: 1000 requests/day, 2 RPM
   */
  async _getGeminiEmbedding(text) {
    const response = await axios.post(
      `${GEMINI_EMBED_URL}?key=${this.apiKey}`,
      {
        model: 'models/text-embedding-004',
        content: { parts: [{ text: text.substring(0, 8000) }] },
        output_dimensionality: EMBEDDING_DIMENSION
      },
      {
        headers: { 'Content-Type': 'application/json' },
        timeout: 15000
      }
    );

    if (response.data?.embedding?.values) {
      const values = response.data.embedding.values;
      if (values.length === EMBEDDING_DIMENSION) {
        return values;
      }
      console.warn(`⚠️ AISemanticService: Expected ${EMBEDDING_DIMENSION}d, got ${values.length}d`);
      return values;
    }

    return null;
  }

  /**
   * Calculate cosine similarity between two embeddings
   */
  cosineSimilarity(a, b) {
    if (!a || !b || a.length !== b.length) return 0;

    let dotProduct = 0;
    let normA = 0;
    let normB = 0;

    for (let i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA === 0 || normB === 0) return 0;
    return dotProduct / (Math.sqrt(normA) * Math.sqrt(normB));
  }

  /**
   * Match ads semantically to video content
   * Returns top matching ads based on semantic similarity
   */
  async matchSemantically(videoContent, ads) {
    try {
      const videoText = `${videoContent.videoName || videoContent.title || ''} ${videoContent.description || ''}`.trim();
      if (!videoText) return [];

      const videoEmbedding = await this.getEmbedding(videoText);
      if (!videoEmbedding) return [];

      const scoredAds = [];
      for (const ad of ads) {
        try {
          const adText = `${ad.title || ''} ${ad.description || ''}`.trim();
          if (!adText) continue;

          const adEmbedding = await this.getEmbedding(adText);
          if (!adEmbedding) continue;

          const score = this.cosineSimilarity(videoEmbedding, adEmbedding);
          scoredAds.push({ ad, score });
        } catch {
          continue;
        }
      }

      scoredAds.sort((a, b) => b.score - a.score);

      return scoredAds
        .filter(item => item.score > 0.15)
        .slice(0, 5)
        .map(item => item.ad);
    } catch (error) {
      console.error('❌ Error in semantic matching:', error);
      return [];
    }
  }

  /**
   * Clear cache (useful for testing or memory management)
   */
  clearCache() {
    this.cache.clear();
  }
}

export default new AISemanticService();
