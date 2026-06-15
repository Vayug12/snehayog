import mongoose from 'mongoose';
import dotenv from 'dotenv';
import path from 'path';
import fs from 'fs';
import os from 'os';
import ffmpegStatic from 'ffmpeg-static';
import { fileURLToPath } from 'url';
import { exec } from 'child_process';
import { promisify } from 'util';

const execPromise = promisify(exec);

// Setup __dirname for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load the .env file from the backend folder
dotenv.config({ path: path.join(__dirname, '..', '.env') });

// We dynamically import internal models/services below 
// so that dotenv.config() runs first!

async function backfill() {
  if (!process.env.MONGO_URI) {
    console.error('❌ MONGO_URI is undefined. Make sure it is set in backend/.env');
    process.exit(1);
  }

  // Parse command line arguments
  const args = process.argv.slice(2);
  let limit = 10;
  
  const limitIndex = args.indexOf('--limit');
  if (limitIndex !== -1 && args.length > limitIndex + 1) {
    limit = parseInt(args[limitIndex + 1], 10);
  }
  
  const targetVideoId = args.includes('--videoId') ? args[args.indexOf('--videoId') + 1] : null;

  // Dynamically import now that process.env is populated
  const Video = (await import('../models/Video.js')).default;
  const AIService = (await import('../services/aiService.js')).default;
  const aiSemanticService = (await import('../services/yugFeedServices/aiSemanticService.js')).default;

  await mongoose.connect(process.env.MONGO_URI);
  console.log('✅ Connected to DB:', process.env.MONGO_URI.split('@')[1] || process.env.MONGO_URI);

  // Initialize semantic service (loads Xenova transformers into memory)
  console.log('🤖 Initializing local semantic embedding model...');
  await aiSemanticService.initialize();

  const query = targetVideoId 
    ? { _id: targetVideoId }
    : { aiContextGenerated: { $ne: true }, aiContextError: { $ne: true } };

  const videos = await Video.find(query).limit(limit).lean();
  
  console.log(`📊 Found ${videos.length} videos requiring summaries and embeddings (limit: ${limit})...`);
  if (videos.length === 0) {
    console.log('✅ No videos left to process!');
    process.exit(0);
  }

  let successCount = 0;
  let failCount = 0;

  for (let i = 0; i < videos.length; i++) {
    const v = videos[i];
    console.log(`\n⏳ Processing ${i + 1}/${videos.length}: ${v.videoName} (${v._id})`);
    
    const videoUrl = v.lowQualityUrl || v.videoUrl;
    if (!videoUrl) {
      console.warn(`⚠️ Skipping video ${v._id}: No accessible URL found.`);
      failCount++;
      continue;
    }

    const tempDir = os.tmpdir();
    const audioPath = path.join(tempDir, `audio_backfill_${v._id}_${Date.now()}.wav`);

    try {
      console.log(`   🎵 Extracting audio stream from remote URL: ${videoUrl}`);
      const ffmpegPath = ffmpegStatic || 'ffmpeg';
      
      // Stream audio directly from remote URL using FFmpeg without downloading full video
      await execPromise(`"${ffmpegPath}" -y -i "${videoUrl}" -vn -acodec pcm_s16le -ar 16000 -ac 1 "${audioPath}"`);
      
      if (!fs.existsSync(audioPath)) {
        throw new Error('Audio extraction failed: File not created');
      }

      console.log(`   📝 Transcribing audio...`);
      const transcript = await AIService.transcribe(audioPath);
      
      if (!transcript || transcript.trim().length === 0) {
        throw new Error('Empty transcript returned');
      }

      const safeTranscript = transcript.substring(0, 800);

      console.log(`   🧠 Generating semantic vector embedding...`);
      const semanticText = `Title: ${v.videoName || ''}. Category: ${v.category || ''}. Tags: ${(v.tags || []).join(', ')}. Transcript: ${safeTranscript}`.trim();
      const vectorEmbedding = await aiSemanticService.getEmbedding(semanticText);

      if (!vectorEmbedding) throw new Error('Vector embedding generation failed');

      // Update Database
      await Video.findByIdAndUpdate(v._id, {
        aiContext: safeTranscript,
        aiContextGenerated: true,
        vectorEmbedding: vectorEmbedding,
        embeddingVersion: 'v1_minilm'
      });

      console.log(`   ✅ Success! Video ${v._id} successfully backfilled.`);
      successCount++;
    } catch (error) {
      console.log(`   ❌ Failed to process video ${v._id}: ${error.message}`);
      
      // Mark as error in DB so we don't keep trying it forever
      try {
        await Video.findByIdAndUpdate(v._id, { aiContextError: true });
      } catch (dbErr) {
        // Ignore DB update errors here
      }
      
      failCount++;
    } finally {
      if (fs.existsSync(audioPath)) {
        fs.unlinkSync(audioPath);
      }
    }
  }

  console.log(`\n🎉 Backfill Complete! Success: ${successCount}, Failed: ${failCount}`);
  process.exit(0);
}

backfill().catch(err => {
  console.error('Fatal Error:', err);
  process.exit(1);
});
