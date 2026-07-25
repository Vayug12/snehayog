import mongoose from 'mongoose';
import '../config/config.js';
import path from 'path';
import fs from 'fs';
import os from 'os';
import ffmpegStatic from 'ffmpeg-static';
import { exec } from 'child_process';
import { promisify } from 'util';

const execPromise = promisify(exec);

/**
 * BATCH BACKFILL: Content-Aware Search
 * Transcribes videos + generates SiliconFlow embeddings for all existing videos.
 * 
 * Usage:
 *   node scripts/backfill-content-search.js                    # Process all unprocessed
 *   node scripts/backfill-content-search.js --limit 50         # Process 50 videos
 *   node scripts/backfill-content-search.js --concurrency 3    # 3 parallel workers
 *   node scripts/backfill-content-search.js --reembed          # Re-embed all (even already processed)
 *   node scripts/backfill-content-search.js --test             # Test mode: process 5 + search test
 */

async function backfill() {
  if (!process.env.MONGO_URI) {
    console.error('❌ MONGO_URI is undefined');
    process.exit(1);
  }

  const args = process.argv.slice(2);
  const limit = parseInt(args[args.indexOf('--limit') + 1]) || 500;
  const concurrency = parseInt(args[args.indexOf('--concurrency') + 1]) || 2;
  const reembed = args.includes('--reembed');
  const testMode = args.includes('--test');

  const Video = (await import('../models/Video.js')).default;
  const aiSemanticService = (await import('../services/yugFeedServices/aiSemanticService.js')).default;
  const deepseekService = (await import('../services/deepseekService.js')).default;

  await mongoose.connect(process.env.MONGO_URI);
  console.log('✅ Connected to MongoDB');

  // Build query
  const query = reembed
    ? { videoUrl: { $exists: true, $ne: null }, processingStatus: 'completed' }
    : {
        $and: [
          { videoUrl: { $exists: true, $ne: null } },
          { processingStatus: 'completed' },
          { $or: [
            { aiContextGenerated: { $ne: true } },
            { embeddingVersion: { $ne: 'bge-m3' } },
            { embeddingVersion: { $exists: false } }
          ]}
        ]
      };

  const totalVideos = await Video.countDocuments(query);
  console.log(`📊 Found ${totalVideos} videos to process (limit: ${limit})`);

  if (totalVideos === 0) {
    console.log('✅ All videos already processed!');
    process.exit(0);
  }

  const videos = await Video.find(query).limit(limit).lean();
  
  let successCount = 0;
  let failCount = 0;
  const startTime = Date.now();

  // Process in batches with concurrency
  for (let i = 0; i < videos.length; i += concurrency) {
    const batch = videos.slice(i, i + concurrency);
    
    const results = await Promise.allSettled(
      batch.map(v => processVideo(v, Video, aiSemanticService, deepseekService))
    );

    results.forEach((result, idx) => {
      if (result.status === 'fulfilled' && result.value) {
        successCount++;
      } else {
        failCount++;
        console.error(`❌ Failed: ${batch[idx].videoName || batch[idx]._id}`);
      }
    });

    // Progress update
    const processed = Math.min(i + concurrency, videos.length);
    const percent = ((processed / videos.length) * 100).toFixed(1);
    const elapsed = ((Date.now() - startTime) / 1000 / 60).toFixed(1);
    const eta = ((elapsed / processed) * (videos.length - processed)).toFixed(1);
    
    console.log(`\n📈 Progress: ${processed}/${videos.length} (${percent}%) | ✅ ${successCount} | ❌ ${failCount} | ⏱️ ${elapsed}m | ETA: ${eta}m`);

    // Small delay between batches to avoid rate limits
    if (i + concurrency < videos.length) {
      await new Promise(r => setTimeout(r, 1000));
    }
  }

  console.log(`\n🎉 Backfill Complete!`);
  console.log(`   ✅ Success: ${successCount}`);
  console.log(`   ❌ Failed: ${failCount}`);
  console.log(`   ⏱️ Total time: ${((Date.now() - startTime) / 1000 / 60).toFixed(1)} minutes`);

  process.exit(0);
}

async function processVideo(video, Video, aiSemanticService, deepseekService) {
  const videoUrl = video.lowQualityUrl || video.videoUrl;
  if (!videoUrl) return false;

  const tempDir = os.tmpdir();
  const audioPath = path.join(tempDir, `audio_${video._id}_${Date.now()}.wav`);

  try {
    // 1. Extract audio
    const ffmpegPath = ffmpegStatic || 'ffmpeg';
    await execPromise(
      `"${ffmpegPath}" -y -i "${videoUrl}" -vn -acodec pcm_s16le -ar 16000 -ac 1 "${audioPath}"`,
      { timeout: 120000 }
    );

    if (!fs.existsSync(audioPath)) throw new Error('Audio extraction failed');

    // 2. Transcribe using Groq Whisper API
    const transcript = await transcribeWithGroq(audioPath);
    
    if (!transcript || transcript.trim().length < 10) {
      throw new Error('Empty or too short transcript');
    }

    const safeTranscript = transcript.substring(0, 1500);

    // 3. Generate rich semantic text using DeepSeek
    const semanticText = await deepseekService.generateSemanticText(safeTranscript, {
      title: video.videoName,
      category: video.category,
      tags: video.tags
    });

    // 4. Generate embedding using SiliconFlow
    const vectorEmbedding = await aiSemanticService.getEmbedding(semanticText);

    if (!vectorEmbedding) throw new Error('Embedding generation failed');

    // 5. Update database
    await Video.findByIdAndUpdate(video._id, {
      aiContext: safeTranscript,
      aiContextGenerated: true,
      vectorEmbedding: vectorEmbedding,
      embeddingVersion: 'bge-m3'
    });

    console.log(`✅ ${video.videoName?.substring(0, 40) || video._id}`);
    return true;
  } catch (error) {
    console.error(`   ❌ ${video.videoName?.substring(0, 30) || video._id}: ${error.message}`);
    return false;
  } finally {
    if (fs.existsSync(audioPath)) {
      try { fs.unlinkSync(audioPath); } catch (e) {}
    }
  }
}

/**
 * Transcribe using Groq Whisper API (Free tier: 3600s/day)
 */
async function transcribeWithGroq(audioPath) {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) {
    // Fallback to HF Whisper
    const AIService = (await import('../services/aiService.js')).default;
    return AIService.transcribe(audioPath);
  }

  const FormData = (await import('form-data')).default;
  const formData = new FormData();
  formData.append('file', fs.createReadStream(audioPath));
  formData.append('model', 'whisper-large-v3');
  formData.append('language', 'hi');
  formData.append('response_format', 'verbose_json');

  const response = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      ...formData.getHeaders()
    },
    body: formData
  });

  if (!response.ok) {
    throw new Error(`Groq API error: ${response.status}`);
  }

  const result = await response.json();
  return result.text;
}

backfill().catch(err => {
  console.error('Fatal Error:', err);
  process.exit(1);
});
