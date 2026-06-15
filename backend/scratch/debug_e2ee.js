import mongoose from 'mongoose';
import dotenv from 'dotenv';
import Video from '../models/Video.js';
import User from '../models/User.js';
import EncryptedVideoKey from '../models/EncryptedVideoKey.js';

dotenv.config();

async function run() {
  try {
    console.log('🔌 Connecting to MongoDB...');
    await mongoose.connect(process.env.MONGO_URI);
    console.log('✅ Connected.');

    const videoId = '6a169edadedd10b9816f24e0';
    console.log(`\n🔍 Looking up video: ${videoId}`);
    const video = await Video.findById(videoId).lean();
    if (!video) {
      console.log('❌ Video not found in database.');
      process.exit(1);
    }
    console.log('Video Details:', {
      _id: video._id,
      videoName: video.videoName,
      uploader: video.uploader,
      isSubscriberOnly: video.isSubscriberOnly,
      allowedSubscribers: video.allowedSubscribers,
    });

    const uploaderId = video.uploader;
    console.log(`\n🔍 Looking up uploader user: ${uploaderId}`);
    const uploader = await User.findById(uploaderId).lean();
    if (!uploader) {
      console.log('❌ Uploader user not found in database.');
    } else {
      console.log('Uploader Details:', {
        _id: uploader._id,
        name: uploader.name,
        googleId: uploader.googleId,
        publicKeyExists: !!uploader.publicKey,
        publicKeySnippet: uploader.publicKey ? uploader.publicKey.substring(0, 50) + '...' : null,
      });
    }

    console.log(`\n🔍 Looking up all EncryptedVideoKeys for video: ${videoId}`);
    const keys = await EncryptedVideoKey.find({ videoId }).lean();
    console.log(`Found ${keys.length} key entries:`);
    for (const key of keys) {
      // Find the subscriber user
      const subUser = await User.findById(key.subscriberId).select('name googleId publicKey').lean();
      console.log(` - Subscriber ID: ${key.subscriberId} (${subUser ? subUser.name : 'Unknown'}), Key snippet: ${key.encryptedSymmetricKey ? key.encryptedSymmetricKey.substring(0, 30) + '...' : 'null'}`);
    }

  } catch (error) {
    console.error('❌ Error during lookup:', error);
  } finally {
    await mongoose.disconnect();
    process.exit(0);
  }
}

run();
