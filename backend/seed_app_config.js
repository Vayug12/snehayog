import mongoose from 'mongoose';
import './config/config.js';
import AppConfig from './models/AppConfig.js';
import redisService from './services/caching/redisService.js';

const seedConfig = async () => {
  try {
    console.log('🔌 Connecting to MongoDB...');
    // Ensure you have MONGO_URI in your .env file
    if (!process.env.MONGO_URI) {
      console.error('❌ Missing MONGO_URI in .env file!');
      process.exit(1);
    }
    await mongoose.connect(process.env.MONGO_URI);
    console.log('✅ Connected.');

    const configData = {
      platform: 'android', 
      environment: 'production',
      isActive: true,
      versionControl: {
        minSupportedAppVersion: '3.6.2',
        latestAppVersion: '3.6.2',
        forceUpdateMessage: 'Please update Vayug to the latest version to continue.',
        softUpdateMessage: 'A new update is available with better performance!',
        updateUrl: {
          android: 'https://play.google.com/store/apps/details?id=com.snehayog.app',
          ios: 'https://apps.apple.com/app/snehayog'
        }
      },
      featureFlags: {
        yugTabCarouselAds: true,
        imageUploadForCreators: true,
        adCreationV2: true,
        videoFeedAds: true,
        creatorPayouts: true,
        referralSystem: true,
        pushNotifications: true,
        analytics: true
      },
      businessRules: {
        adBudget: { minDailyBudget: 100, maxDailyBudget: 10000, minTotalBudget: 1000 },
        cpmRates: { banner: 10, carousel: 30, videoFeedAd: 30 },
        revenueShare: { creatorShare: 0.80, platformShare: 0.20 },
        uploadLimits: {
          maxDailyUploads: 10,
          maxVideoSize: 734003200, // 700MB
          maxImageSize: 5242880,   // 5MB
          maxVideoDuration: 600,
          allowedVideoFormats: ['mp4', 'avi', 'mov'],
          allowedImageFormats: ['jpg', 'png', 'webp']
        },
        payoutRules: { minPayoutAmount: 500, payoutProcessingDays: 7 },
        adServing: { insertionFrequency: 2, maxAdsPerSession: 10, impressionFrequencyCap: 3 }
      },
      recommendationParams: {
        weights: { views: 0.3, likes: 0.25, recency: 0.2, userEngagement: 0.15, categoryMatch: 0.1 },
        timeDecayFactor: 0.95,
        trendingThreshold: 1000
      }
    };

    console.log('💾 Updating AppConfig version control...');
    const filter = { platform: configData.platform, environment: configData.environment };
    const existingConfig = await AppConfig.findOne(filter).sort({ createdAt: -1 });

    if (existingConfig) {
      existingConfig.set({
        isActive: true,
        'versionControl.minSupportedAppVersion': configData.versionControl.minSupportedAppVersion,
        'versionControl.latestAppVersion': configData.versionControl.latestAppVersion,
        'versionControl.forceUpdateMessage': configData.versionControl.forceUpdateMessage,
        'versionControl.softUpdateMessage': configData.versionControl.softUpdateMessage,
        'versionControl.updateUrl.android': configData.versionControl.updateUrl.android,
        'versionControl.updateUrl.ios': configData.versionControl.updateUrl.ios,
      });
      await existingConfig.save();
      console.log('✨ Updated version control without overwriting other AppConfig settings.');
    } else {
      const newConfig = new AppConfig(configData);
      await newConfig.save();
      console.log('✨ Created the initial AppConfig for Android/Production.');
    }

    if (await redisService.connect()) {
      await redisService.del(`app_config:${configData.platform}:${configData.environment}`);
      await redisService.disconnect();
      console.log('🧹 Cleared the AppConfig cache.');
    }
    process.exit(0);
  } catch (error) {
    console.error('❌ Error seeding database:', error);
    process.exit(1);
  }
};

seedConfig();
