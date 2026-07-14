import { HuggingFaceAIEngine } from './aiService/HuggingFaceAIEngine.js';
import { OpenAIAIEngine } from './aiService/OpenAIAIEngine.js';

let activeAIEngine = new HuggingFaceAIEngine();
const translationProvider =
  process.env.DUBBING_TRANSLATION_PROVIDER?.trim().toLowerCase() || 'openai';
let openAITranslationEngine;

if (!['openai', 'huggingface'].includes(translationProvider)) {
  throw new Error(
    `Unsupported DUBBING_TRANSLATION_PROVIDER: ${translationProvider}`,
  );
}

/**
 * Orchestrator acting as a proxy to the active IAIEngine implementation.
 * Provides hot-swappable AI capabilities and full backward compatibility.
 */
class AIServiceProxy {
  /**
   * Sets the active AI engine plugin.
   * @param {IAIEngine} engine 
   */
  setAIEngine(engine) {
    console.log(`🔌 [AIService] Swapping AI engine provider...`);
    activeAIEngine = engine;
  }

  /**
   * Gets the current active AI engine plugin.
   * @returns {IAIEngine}
   */
  getAIEngine() {
    return activeAIEngine;
  }

  /**
   * Gets the engine used exclusively for dubbing translations. Speech-to-text
   * and text-to-speech continue to use the active engine above.
   */
  getTranslationEngine() {
    if (translationProvider === 'openai') {
      openAITranslationEngine ??= new OpenAIAIEngine();
      return openAITranslationEngine;
    }

    return activeAIEngine;
  }

  /**
   * Translates text using the configured dubbing translation engine.
   */
  async translate(text, targetLang) {
    return this.getTranslationEngine().translate(text, targetLang);
  }

  /**
   * Transcribes audio file using the active engine.
   */
  async transcribe(audioPath) {
    return activeAIEngine.transcribe(audioPath);
  }

  /**
   * Synthesizes text to speech using the active engine.
   */
  async synthesize(text, language, outputPath) {
    return activeAIEngine.synthesize(text, language, outputPath);
  }

  /**
   * Summarizes text using the active engine.
   */
  async summarize(text) {
    return activeAIEngine.summarize(text);
  }
}

export default new AIServiceProxy();
