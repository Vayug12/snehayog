import mongoose from 'mongoose';
import '../config/config.js';
import Video from '../models/Video.js';
import User from '../models/User.js';
import EncryptedVideoKey from '../models/EncryptedVideoKey.js';

async function run() {
  try {
    console.log('🔌 Connecting to MongoDB...');
    await mongoose.connect(process.env.MONGO_URI);
    console.log('✅ Connected.');

    const videoId = '6a18a598755f654b785c5b68';
    console.log(`\n🔍 Looking up video: ${videoId}`);
    const video = await Video.findById(videoId).lean();
    if (!video) {
      console.log('❌ Video not found in database.');
      // Find all subscriber-only videos
      const subVideos = await Video.find({ isSubscriberOnly: true }).limit(5).lean();
      console.log(`Found ${subVideos.length} subscriber-only videos:`);
      for (const v of subVideos) {
        console.log(` - ID: ${v._id}, Name: ${v.videoName}, URL: ${v.videoUrl}`);
      }
      process.exit(1);
    }
    
    console.log('Video Details:', {
      _id: video._id,
      videoName: video.videoName,
      uploader: video.uploader,
      isSubscriberOnly: video.isSubscriberOnly,
      allowedSubscribers: video.allowedSubscribers,
      videoUrl: video.videoUrl,
      hlsPlaylistUrl: video.hlsPlaylistUrl,
      hlsMasterPlaylistUrl: video.hlsMasterPlaylistUrl,
      isHLSEncoded: video.isHLSEncoded,
    });

    const keys = await EncryptedVideoKey.find({ videoId }).lean();
    console.log(`Found ${keys.length} key entries:`);
    for (const key of keys) {
      const subUser = await User.findById(key.subscriberId).select('name googleId').lean();
      console.log(` - Subscriber ID: ${key.subscriberId} (${subUser ? subUser.name : 'Unknown'}), Key Snippet: ${key.encryptedSymmetricKey ? key.encryptedSymmetricKey.substring(0, 30) + '...' : 'null'}`);
    }

  } catch (error) {
    console.error('❌ Error during lookup:', error);
  } finally {
    await mongoose.disconnect();
    process.exit(0);
  }
}

run();
