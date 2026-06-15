import VideoPipeline from './VideoPipeline.js';
import DownloadStep from './steps/DownloadStep.js';
import HlsTranscodeStep from './steps/HlsTranscodeStep.js';
import CleanupStep from './steps/CleanupStep.js';
import VideoSummarizationStep from './steps/VideoSummarizationStep.js';

/**
 * Standard Video Processing Pipeline
 */
const defaultPipeline = new VideoPipeline();

defaultPipeline
  .addStep(new DownloadStep())
  .addStep(new HlsTranscodeStep())
  .addStep(new VideoSummarizationStep())
  .addStep(new CleanupStep());

export default defaultPipeline;
