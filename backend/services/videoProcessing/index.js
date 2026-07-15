import VideoPipeline from './VideoPipeline.js';
import DownloadStep from './steps/DownloadStep.js';
import HlsTranscodeStep from './steps/HlsTranscodeStep.js';
import CleanupStep from './steps/CleanupStep.js';
import GeminiSummarizationStep from './steps/GeminiSummarizationStep.js';

/**
 * Standard Video Processing Pipeline (Zero-Cost Gemini)
 * 
 * Download → HLS Transcode → Gemini AI Summarization → Cleanup
 * 
 * GeminiSummarizationStep handles:
 * - Groq Whisper transcription (free: 7K/day)
 * - Gemini Flash semantic text (free: 1K/day, rate-limited)
 * - Gemini embedding-004 384-dim (free: 1K/day, rate-limited)
 */
const defaultPipeline = new VideoPipeline();

defaultPipeline
  .addStep(new DownloadStep())
  .addStep(new HlsTranscodeStep())
  .addStep(new CleanupStep());

const aiAnalysisPipeline = new VideoPipeline();

aiAnalysisPipeline
  .addStep(new DownloadStep())
  .addStep(new GeminiSummarizationStep())
  .addStep(new CleanupStep());

export { aiAnalysisPipeline };
export default defaultPipeline;

