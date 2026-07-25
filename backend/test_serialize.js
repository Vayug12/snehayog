import mongoose from 'mongoose';
import './config/config.js';
import User from './models/User.js';
import Video from './models/Video.js';
import { serializeVideos } from './utils/serializers/videoSerializer.js';

async function run() {
  try {
    await mongoose.connect(process.env.MONGO_URI, { useNewUrlParser: true, useUnifiedTopology: true });
    
    // Find the test user
    const user = await User.findOne({ name: 'Sanjeev Snehayog' });
    if (!user) {
      console.log('User not found');
      return;
    }

    console.log('User Google ID:', user.googleId);

    // Fetch their videos like getUserVideos does
    const query = {
      uploader: user._id,
      videoUrl: { $exists: true, $ne: null, $ne: '' },
      processingStatus: { $nin: ['failed', 'error'] }
    };

    const videos = await Video.find(query)
      .populate('uploader', 'name profilePic googleId')
      .sort({ createdAt: -1 })
      .limit(5)
      .select('-description -shares')
      .lean();

    console.log('Found', videos.length, 'videos');

    const videosWithMetadata = videos.map(v => {
      if (v.uploader) {
        v.uploader.earnings = 0;
      }
      return v;
    });

    const serialized = serializeVideos(videosWithMetadata, '2026-04-02', user._id.toString());
    
    for (let i = 0; i < Math.min(2, serialized.length); i++) {
      console.log(`Video ${i+1}:`);
      console.log(`  Name: ${serialized[i].videoName}`);
      console.log(`  isSubscriberOnly: ${serialized[i].isSubscriberOnly}`);
      console.log(`  _id: ${serialized[i]._id}`);
    }

  } catch (err) {
    console.error(err);
  } finally {
    await mongoose.disconnect();
  }
}

run();
