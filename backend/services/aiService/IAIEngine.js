/**
 * Abstract interface defining the contract for AI translation and speech services (Dubbing engine).
 */
export class IAIEngine {
  /**
   * Translates English text to a target language.
   * @param {string} text 
   * @param {string} targetLang 
   * @returns {Promise<string>}
   */
  async translate(text, targetLang = 'hi_IN') {
    throw new Error('IAIEngine: translate(text, targetLang) not implemented');
  }

  /**
   * Transcribes an audio file into text.
   * @param {string} audioPath 
   * @returns {Promise<string>}
   */
  async transcribe(audioPath) {
    throw new Error('IAIEngine: transcribe(audioPath) not implemented');
  }

  /**
   * Synthesizes text into spoken audio saved to outputPath.
   * @param {string} text 
   * @param {string} language 
   * @param {string} outputPath 
   * @returns {Promise<string>} Path to output file
   */
  async synthesize(text, language = 'hindi', outputPath) {
    throw new Error('IAIEngine: synthesize(text, language, outputPath) not implemented');
  }

  /**
   * Summarizes a long text transcript into a short summary.
   * @param {string} text 
   * @returns {Promise<string>}
   */
  async summarize(text) {
    throw new Error('IAIEngine: summarize(text) not implemented');
  }
}
