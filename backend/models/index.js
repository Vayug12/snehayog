// Models index file - Import all models to ensure they are registered with Mongoose
// This prevents "MissingSchemaError: Schema hasn't been registered for model" errors

import './User.js';
import './Video.js';

import './Invoice.js';
import './AdCampaign.js';
import './AdCreative.js';
import './RemovedVideoRecord.js';
import './AdImpression.js';
import './CreatorPayout.js';
import './Feedback.js';
import './WatchHistory.js';
import './FeedHistory.js';
import './AppConfig.js';
import './DailyUploadQuota.js';
import './Notice.js';
import './CreatorDailyStats.js';

console.log('✅ All models imported and registered successfully');
