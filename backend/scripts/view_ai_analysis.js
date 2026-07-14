import mongoose from 'mongoose';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '../.env') });

import Video from '../models/Video.js';

/**
 * View AI Analysis of Videos
 *
 * Usage:
 *   node scripts/view_ai_analysis.js                    # Latest 5 videos
 *   node scripts/view_ai_analysis.js --limit 20         # Latest 20 videos
 *   node scripts/view_ai_analysis.js --videoId <id>     # Specific video
 */

async function viewAnalysis() {
    try {
        const args = process.argv.slice(2);
        const limitIndex = args.indexOf('--limit');
        const limit = limitIndex !== -1 ? parseInt(args[limitIndex + 1], 10) : 5;
        const videoIdIndex = args.indexOf('--videoId');
        const videoId = videoIdIndex !== -1 ? args[videoIdIndex + 1] : null;

        console.log('🔌 Connecting to MongoDB...');
        await mongoose.connect(process.env.MONGO_URI);
        console.log('✅ Connected.\n');

        const query = videoId
            ? { _id: videoId, aiContextGenerated: true }
            : { aiContextGenerated: true };

        const videos = await Video.find(query)
            .sort({ updatedAt: -1 })
            .limit(videoId ? 1 : limit)
            .lean();

        if (videos.length === 0) {
            console.log('❌ No AI analyzed videos found.');
            process.exit(0);
        }

        // Stats
        const totalWithAI = await Video.countDocuments({ aiContextGenerated: true });
        const totalWithEmbedding = await Video.countDocuments({ vectorEmbedding: { $exists: true, $ne: null } });
        console.log(`📊 Stats: ${totalWithAI} videos with AI context | ${totalWithEmbedding} videos with embeddings\n`);

        videos.forEach((video, index) => {
            console.log(`🎬 --- [Video ${index + 1}] ---`);
            console.log(`📌 Title: ${video.videoName || 'Untitled'}`);
            console.log(`🌐 Language: ${video.language || 'Unknown'}`);
            console.log(`📍 Region: ${video.detectedRegion || 'Unknown'}`);
            console.log(`🏷️ Tags: ${video.tags ? video.tags.join(', ') : 'None'}`);
            console.log(`🤖 Embedding Version: ${video.embeddingVersion || 'Not set'}`);
            console.log(`📏 Embedding Dimensions: ${video.vectorEmbedding ? video.vectorEmbedding.length : 'None'}`);
            console.log(`📝 AI Summary: ${video.aiSummary || 'No summary'}`);
            console.log(`📄 Transcript (aiContext): ${video.aiContext ? video.aiContext.substring(0, 300) + (video.aiContext.length > 300 ? '...' : '') : 'No transcript'}`);
            console.log(`-----------------------------------\n`);
        });

        process.exit(0);
    } catch (error) {
        console.error('💥 Error:', error.message);
        process.exit(1);
    }
}

viewAnalysis();
