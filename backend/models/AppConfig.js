import mongoose from 'mongoose';

/**
 * AppConfig Model - Backend-Driven Mobile Configuration
 * 
 * This model stores all configuration that controls the mobile app behavior:
 * - UI texts (titles, button labels, descriptions)
 * - Feature flags (enable/disable features remotely)
 * - Business rules (minimum ad budget, limits, pricing rules)
 * - Recommendation algorithm parameters
 * - Kill-switch for emergency shutdown
 * - Forced update settings
 * 
 * This allows updating the app without requiring Play Store updates.
 */
const appConfigSchema = new mongoose.Schema({
  // Platform identifier (android, ios, web)
  platform: {
    type: String,
    required: true,
    enum: ['android', 'ios', 'web', 'all'],
    default: 'all',
    index: true
  },
  
  // Version control for forced updates
  versionControl: {
    minSupportedAppVersion: {
      type: String,
      required: true,
      default: '1.0.0',
      description: 'Minimum app version that can use the API. Versions below this will be blocked.'
    },
    latestAppVersion: {
      type: String,
      required: true,
      default: '1.0.0',
      description: 'Latest available app version. Versions below this will see soft update banner.'
    },
    forceUpdateMessage: {
      type: String,
      default: 'A new version of the app is available. Please update to continue.',
      description: 'Message shown when app version is below minimum'
    },
    softUpdateMessage: {
      type: String,
      default: 'A new version is available with exciting features!',
      description: 'Message shown when app version is below latest but above minimum'
    },
    updateUrl: {
      android: {
        type: String,
        default: 'https://play.google.com/store/apps/details?id=com.snehayog.app'
      },
      ios: {
        type: String,
        default: 'https://apps.apple.com/app/snehayog'
      }
    }
  },
  
  // Feature flags - Enable/disable features remotely
  featureFlags: {
    yugTabCarouselAds: {
      type: Boolean,
      default: true,
      description: 'Show carousel ads in Yug tab'
    },
    imageUploadForCreators: {
      type: Boolean,
      default: true,
      description: 'Allow creators to upload product images'
    },
    adCreationV2: {
      type: Boolean,
      default: true,
      description: 'Enable new ad creation UI'
    },
    videoFeedAds: {
      type: Boolean,
      default: true,
      description: 'Show ads in video feed'
    },
    creatorPayouts: {
      type: Boolean,
      default: true,
      description: 'Enable creator payout system'
    },
    referralSystem: {
      type: Boolean,
      default: true,
      description: 'Enable referral system'
    },
    pushNotifications: {
      type: Boolean,
      default: true,
      description: 'Enable push notifications'
    },
    analytics: {
      type: Boolean,
      default: true,
      description: 'Enable analytics tracking'
    },
    professionTargeting: {
      type: Boolean,
      default: true,
      description: 'Enable profession profile and creator targeting UI'
    }
  },
  
  // Business rules - Pricing, limits, thresholds
  businessRules: {
    // Ad budget rules
    adBudget: {
      minDailyBudget: {
        type: Number,
        default: 100,
        description: 'Minimum daily ad budget in INR'
      },
      maxDailyBudget: {
        type: Number,
        default: 10000,
        description: 'Maximum daily ad budget in INR'
      },
      minTotalBudget: {
        type: Number,
        default: 1000,
        description: 'Minimum total campaign budget in INR'
      }
    },
    
    // CPM rates
    cpmRates: {
      banner: {
        type: Number,
        default: 10.0,
        description: 'CPM for banner ads in INR'
      },
      carousel: {
        type: Number,
        default: 30.0,
        description: 'CPM for carousel ads in INR'
      },
      videoFeedAd: {
        type: Number,
        default: 30.0,
        description: 'CPM for video feed ads in INR'
      }
    },
    
    // Revenue share
    revenueShare: {
      creatorShare: {
        type: Number,
        default: 0.80,
        min: 0,
        max: 1,
        description: 'Creator revenue share (80% = 0.80)'
      },
      platformShare: {
        type: Number,
        default: 0.20,
        min: 0,
        max: 1,
        description: 'Platform revenue share (20% = 0.20)'
      }
    },
    
    // Upload limits
    uploadLimits: {
      maxDailyUploads: {
        type: Number,
        default: 10,
        min: 1,
        description: 'Maximum successful user uploads per IST calendar day'
      },
      maxVideoSize: {
        type: Number,
        default: 700 * 1024 * 1024, // 700MB
        description: 'Maximum video file size in bytes'
      },
      maxImageSize: {
        type: Number,
        default: 5 * 1024 * 1024, // 5MB
        description: 'Maximum image file size in bytes'
      },
      maxVideoDuration: {
        type: Number,
        default: 600, // 10 minutes in seconds
        description: 'Maximum video duration in seconds'
      },
      allowedVideoFormats: {
        type: [String],
        default: ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'],
        description: 'Allowed video file formats'
      },
      allowedImageFormats: {
        type: [String],
        default: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'avif', 'bmp'],
        description: 'Allowed image file formats'
      }
    },
    
    // Payout rules
    payoutRules: {
      minPayoutAmount: {
        type: Number,
        default: 500,
        description: 'Minimum payout amount in INR'
      },
      payoutProcessingDays: {
        type: Number,
        default: 7,
        description: 'Days to process payout after request'
      }
    },
    
    // Ad serving rules
    adServing: {
      insertionFrequency: {
        type: Number,
        default: 2,
        description: 'Show ad every Nth video (2 = every 2nd video)'
      },
      maxAdsPerSession: {
        type: Number,
        default: 10,
        description: 'Maximum ads shown per user session'
      },
      impressionFrequencyCap: {
        type: Number,
        default: 3,
        description: 'Max impressions per user per day'
      }
    }
  },
  
  // Recommendation algorithm parameters
  recommendationParams: {
    // Weight factors for recommendation score
    weights: {
      views: {
        type: Number,
        default: 0.3,
        description: 'Weight for view count in recommendation'
      },
      likes: {
        type: Number,
        default: 0.25,
        description: 'Weight for like count in recommendation'
      },
      recency: {
        type: Number,
        default: 0.2,
        description: 'Weight for recency (time since upload)'
      },
      userEngagement: {
        type: Number,
        default: 0.15,
        description: 'Weight for user engagement history'
      },
      categoryMatch: {
        type: Number,
        default: 0.1,
        description: 'Weight for category matching'
      }
    },
    
    // Time decay factor
    timeDecayFactor: {
      type: Number,
      default: 0.95,
      min: 0,
      max: 1,
      description: 'Decay factor for recency (0.95 = 5% decay per day)'
    },
    
    // Trending threshold
    trendingThreshold: {
      type: Number,
      default: 1000,
      description: 'Minimum views to be considered trending'
    }
  },
  
  // UI Texts - All visible texts in the app (i18n keys)
  // Format: { key: 'text_value' }
  uiTexts: {
    type: Map,
    of: String,
    default: new Map([
      // Common texts
      ['app_name', 'Vayu'],
      ['app_tagline', 'Create • Video • Earn'],
      ['btn_done', 'Done'],
      ['upload_target_audience', 'Target audience'],
      ['upload_target_audience_hint', 'Only selected professions can receive this video'],
      ['upload_target_private_hint', 'Private videos already use subscriber access'],
      ['profession_single_count', '1 profession'],
      ['profession_multiple_count', '{count} professions'],
      ['profile_add_profession', '+ Add profession'],
      ['profile_profession_title', 'Your profession'],
      ['profile_remove_profession', 'Remove profession'],
      ['profile_profession_update_error', 'Could not update profession. Please try again.'],
      ['profession_picker_title', 'Choose profession'],
      ['profession_search_hint', 'Search profession'],
      ['profession_everyone', 'Everyone'],
      ['profession_target_private', 'Unavailable'],
      ['profession_load_error', 'Could not load professions. Please try again.'],
      
      // Navigation
      ['nav_yug', 'Yug'],
      ['nav_vayu', 'Vayu'],
      ['nav_profile', 'Profile'],
      ['nav_ads', 'Ads'],
      
      // Buttons
      ['btn_upload', 'Upload'],
      ['btn_create_ad', 'Create Advertisement'],
      ['btn_save', 'Save'],
      ['btn_cancel', 'Cancel'],
      ['btn_submit', 'Submit'],
      ['btn_visit_now', 'Visit Now'],
      ['btn_update_app', 'Update App'],
      
      // Upload screen
      ['upload_title', 'Upload & Create'],
      ['upload_select_media', 'Select Media'],
      ['upload_media_hint', 'Upload Video or Product Image'],
      ['upload_product_image_hint', 'Product image selected. Please add your product/website URL in the External Link field.'],
      
      // Ad creation
      ['ad_create_title', 'Create Advertisement'],
      ['ad_budget_label', 'Daily Budget'],
      ['ad_duration_label', 'Campaign Duration'],
      
      // Profile
      ['profile_my_videos', 'My Videos'],
      ['profile_earnings', 'Earnings'],
      ['profile_settings', 'Settings'],
      
      // Errors
      ['error_network', 'Network error. Please check your connection.'],
      ['error_upload_failed', 'Upload failed. Please try again.'],
      ['error_invalid_url', 'Please enter a valid URL starting with http:// or https://'],
      
      // Success messages
      ['success_upload', 'Upload successful!'],
      ['success_ad_created', 'Advertisement created successfully!']
    ])
  },
  
  // Kill switch - Emergency shutdown
  killSwitch: {
    enabled: {
      type: Boolean,
      default: false,
      description: 'If true, app will be blocked from making API calls'
    },
    message: {
      type: String,
      default: 'The app is temporarily unavailable. Please try again later.',
      description: 'Message shown when kill switch is enabled'
    },
    maintenanceMode: {
      type: Boolean,
      default: false,
      description: 'If true, app shows maintenance message but allows some features'
    },
    maintenanceMessage: {
      type: String,
      default: 'We are performing maintenance. Some features may be unavailable.',
      description: 'Message shown during maintenance mode'
    }
  },
  
  // Cache settings
  cacheSettings: {
    configCacheTTL: {
      type: Number,
      default: 300, // 5 minutes
      description: 'Time to live for config cache in seconds'
    },
    videoFeedCacheTTL: {
      type: Number,
      default: 180, // 3 minutes
      description: 'Time to live for video feed cache in seconds'
    }
  },
  
  // Metadata
  isActive: {
    type: Boolean,
    default: true,
    description: 'Whether this config is currently active'
  },
  
  // Environment (development, staging, production)
  environment: {
    type: String,
    enum: ['development', 'staging', 'production'],
    default: 'production',
    index: true
  }
}, {
  timestamps: true, // Adds createdAt and updatedAt
  collection: 'app_configs'
});

// Indexes for fast queries
appConfigSchema.index({ platform: 1, environment: 1, isActive: 1 });
appConfigSchema.index({ createdAt: -1 });

// Static method to get active config for platform
appConfigSchema.statics.getActiveConfig = async function(platform = 'android', environment = 'production') {
  return await this.findOne({
    platform: { $in: [platform, 'all'] },
    environment: environment,
    isActive: true
  }).sort({ createdAt: -1 });
};

// Static method to get latest config (regardless of platform)
appConfigSchema.statics.getLatestConfig = async function(environment = 'production') {
  return await this.findOne({
    environment: environment,
    isActive: true
  }).sort({ createdAt: -1 });
};

// Instance method to check if app version is supported
appConfigSchema.methods.isAppVersionSupported = function(appVersion) {
  const minVersion = this.versionControl.minSupportedAppVersion;
  return this.compareVersions(appVersion, minVersion) >= 0;
};

// Instance method to check if app version is latest
appConfigSchema.methods.isAppVersionLatest = function(appVersion) {
  const latestVersion = this.versionControl.latestAppVersion;
  return this.compareVersions(appVersion, latestVersion) >= 0;
};

// Helper method to compare semantic versions (e.g., "1.2.3")
appConfigSchema.methods.compareVersions = function(version1, version2) {
  const v1Parts = version1.split('.').map(Number);
  const v2Parts = version2.split('.').map(Number);
  
  for (let i = 0; i < Math.max(v1Parts.length, v2Parts.length); i++) {
    const v1Part = v1Parts[i] || 0;
    const v2Part = v2Parts[i] || 0;
    
    if (v1Part > v2Part) return 1;
    if (v1Part < v2Part) return -1;
  }
  
  return 0;
};

// Instance method to get UI text with fallback
appConfigSchema.methods.getText = function(key, fallback = null) {
  const texts = this.uiTexts || new Map();
  return texts.get(key) || fallback || key;
};

export default mongoose.models.AppConfig || mongoose.model('AppConfig', appConfigSchema);

