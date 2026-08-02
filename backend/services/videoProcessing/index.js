import VideoPipeline from './VideoPipeline.js';
import DownloadStep from './steps/DownloadStep.js';
import HlsTranscodeStep from './steps/HlsTranscodeStep.js';
import CleanupStep from './steps/CleanupStep.js';
// import GeminiSummarizationStep from './steps/GeminiSummarizationStep.js';

/**
 * Standard Video Processing Pipeline
 * 
 * Download → HLS Transcode → Cleanup
 * 
 * ⚠️ GeminiSummarizationStep DISABLED — saves CPU (ffmpeg audio extraction) + memory
 * (Groq Whisper, Gemini Flash, Gemini embedding API calls)
 */
const defaultPipeline = new VideoPipeline();

defaultPipeline
  .addStep(new DownloadStep())
  .addStep(new HlsTranscodeStep())
  .addStep(new CleanupStep());

// ⚠️ AI Analysis Pipeline DISABLED — was using GeminiSummarizationStep
// Uncomment below to re-enable Gemini summarization + embedding
/*
const aiAnalysisPipeline = new VideoPipeline();

aiAnalysisPipeline
  .addStep(new DownloadStep())
  .addStep(new GeminiSummarizationStep())
  .addStep(new CleanupStep());

export { aiAnalysisPipeline };
*/
export default defaultPipeline;

