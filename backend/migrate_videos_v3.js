import './config/env.js';
import mongoose from 'mongoose';
import Video from './models/Video.js';
import geminiService from './services/geminiService.js';
import recommendationService from './services/yugFeedServices/recommendationService.js';

async function migrateVideos() {
    try {
        console.log('🚀 Starting V3 Gemini Migration...');
        
        if (mongoose.connection.readyState !== 1) {
            await mongoose.connect(process.env.MONGO_URI);
            console.log('✅ Connected to MongoDB');
        }

        // Find videos that need AI context
        const videosToMigrate = await Video.find({ 
            $or: [
                { aiContextGenerated: { $ne: true } },
                { language: { $exists: false } }
            ]
        }).limit(500); // Process in chunks of 500 to avoid long hangs

        console.log(`📊 Found ${videosToMigrate.length} videos that need AI analysis.`);

        let successCount = 0;
        let failCount = 0;

        for (let i = 0; i < videosToMigrate.length; i++) {
            const video = videosToMigrate[i];
            console.log(`\n🔄 [${i+1}/${videosToMigrate.length}] Processing: ${video.videoName || video._id}`);

            try {
                // We use the thumbnail for visual context (Multimodal)
                const thumbnailUrl = video.thumbnailUrl;
                
                if (!thumbnailUrl || !thumbnailUrl.startsWith('http')) {
                    console.warn(`⚠️ Skipping: No valid thumbnail found for ${video._id}`);
                    failCount++;
                    continue;
                }

                const metadata = await geminiService.getVideoContext([thumbnailUrl], {
                    title: video.videoName,
                    category: video.category,
                    description: video.description
                });

                if (metadata) {
                    video.aiSummary = metadata.summary;
                    video.language = metadata.language;
                    video.detectedRegion = metadata.region;
                    video.aiContextGenerated = true;
                    
                    // Merge AI keywords with existing tags
                    const newTags = [...new Set([...(video.tags || []), ...(metadata.keywords || [])])];
                    video.tags = newTags;

                    // Update recommendation score and embeddings
                    await video.save();
                    
                    // Trigger embedding update
                    await recommendationService.calculateAndUpdateVideoScore(video._id);
                    
                    console.log(`✅ Success: ${video.language} | ${video.detectedRegion}`);
                    successCount++;
                } else {
                    console.error(`❌ Gemini returned no metadata for ${video._id}`);
                    failCount++;
                }

                // Mandatory sleep to stay within Gemini Free Tier limits (5-15 RPM)
                console.log('⏳ Throttling: Waiting 13s for next request...');
                await new Promise(r => setTimeout(r, 13000));

            } catch (err) {
                console.error(`❌ Failed to process video ${video._id}:`, err.message);
                failCount++;
                
                // If it's a rate limit error, wait a bit
                if (err.message.includes('429') || err.message.includes('Resource exhausted')) {
                    console.log('⏳ Rate limit hit in migration. Sleeping for 5s...');
                    await new Promise(r => setTimeout(r, 5000));
                }
            }
        }

        console.log('\n✨ Migration Summary:');
        console.log(`✅ Successfully processed: ${successCount}`);
        console.log(`❌ Failed: ${failCount}`);
        
        process.exit(0);

    } catch (error) {
        console.error('💥 Critical Migration Error:', error);
        process.exit(1);
    }
}

migrateVideos();
