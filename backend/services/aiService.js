import { HuggingFaceAIEngine } from './aiService/HuggingFaceAIEngine.js';

let activeAIEngine = new HuggingFaceAIEngine();

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
   * Translates text using the active engine.
   */
  async translate(text, targetLang) {
    return activeAIEngine.translate(text, targetLang);
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
