import { jest } from '@jest/globals';
import os from 'os';
import path from 'path';
import fs from 'fs';

// 1. Setup Mocks before importing the module
jest.unstable_mockModule('child_process', () => ({
  exec: jest.fn((cmd, cb) => cb(null, { stdout: '', stderr: '' }))
}));

jest.unstable_mockModule('../models/Video.js', () => {
  return {
    default: {
      findById: jest.fn(),
      findByIdAndUpdate: jest.fn()
    }
  };
});

jest.unstable_mockModule('../services/aiService.js', () => {
  return {
    default: {
      transcribe: jest.fn()
    }
  };
});

jest.unstable_mockModule('../services/yugFeedServices/aiSemanticService.js', () => {
  return {
    default: {
      getEmbedding: jest.fn()
    }
  };
});

describe('🤖 AI Video Summarization Pipeline', () => {
  let VideoSummarizationStep;
  let Video;
  let AIService;
  let aiSemanticService;
  let child_process;

  beforeAll(async () => {
    // Import dynamically after mocks are registered
    const module = await import('../services/videoProcessing/steps/VideoSummarizationStep.js');
    VideoSummarizationStep = module.default;
    
    Video = (await import('../models/Video.js')).default;
    AIService = (await import('../services/aiService.js')).default;
    aiSemanticService = (await import('../services/yugFeedServices/aiSemanticService.js')).default;
    child_process = await import('child_process');
  });

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.HF_TOKEN = 'mock-hf-token';
  });

  test('should successfully extract audio, summarize, generate vector, and update DB', async () => {
    const step = new VideoSummarizationStep();
    const context = {
      videoId: 'test-video-id',
      localRawPath: '/tmp/fake-video.mp4'
    };

    const mockVideo = {
      _id: 'test-video-id',
      videoName: 'Flutter Tutorial',
      description: 'Learn flutter',
      category: 'education',
      tags: ['flutter', 'code']
    };

    Video.findById.mockResolvedValue(mockVideo);
    
    // Fake the file creation so fs.existsSync passes
    const fakeAudioPath = path.join(os.tmpdir(), expect.any(String));
    
    // We override fs.existsSync just for this test
    const originalExistsSync = fs.existsSync;
    const originalUnlinkSync = fs.unlinkSync;
    jest.spyOn(fs, 'existsSync').mockReturnValue(true);
    jest.spyOn(fs, 'unlinkSync').mockReturnValue(true);

    AIService.transcribe.mockResolvedValue('Welcome to flutter tutorial.');
    aiSemanticService.getEmbedding.mockResolvedValue([0.1, 0.2, 0.3]);
    
    // Need to override the background method to run synchronously for the test
    const originalBackground = step._runSummarizationInBackground;
    let backgroundPromise;
    step._runSummarizationInBackground = function(vid, pth) {
      backgroundPromise = originalBackground.call(this, vid, pth);
      return backgroundPromise;
    };

    // Execute step
    await step.execute(context);
    
    // Wait for the background task to finish
    await backgroundPromise;

    // Verify FFmpeg was called
    expect(child_process.exec).toHaveBeenCalledWith(
      expect.stringContaining('ffmpeg -y -i "/tmp/fake-video.mp4" -vn'),
      expect.any(Function)
    );

    // Verify AI Services were called
    expect(AIService.transcribe).toHaveBeenCalled();
    
    // Verify vector was generated using combined semantic text
    expect(aiSemanticService.getEmbedding).toHaveBeenCalledWith(
      'Title: Flutter Tutorial. Category: education. Tags: flutter, code. Transcript: Welcome to flutter tutorial.'
    );

    // Verify DB update
    expect(Video.findByIdAndUpdate).toHaveBeenCalledWith(
      'test-video-id',
      expect.objectContaining({
        aiContext: 'Welcome to flutter tutorial.',
        aiContextGenerated: true,
        vectorEmbedding: [0.1, 0.2, 0.3],
        embeddingVersion: 'v1_minilm'
      })
    );

    // Restore fs mocks
    jest.restoreAllMocks();
  });
  
  test('should skip summarization if HF_TOKEN is missing', async () => {
    delete process.env.HF_TOKEN;
    const step = new VideoSummarizationStep();
    await step.execute({ videoId: '123' });
    expect(Video.findById).not.toHaveBeenCalled();
  });
});
