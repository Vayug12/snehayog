// Application constants

export const APP_CONFIG = {
  NAME: 'Snehayog',
  VERSION: '1.0.0',
  DEFAULT_PORT: 5001,
  DEFAULT_HOST: '0.0.0.0',
  LOCAL_NETWORK_IP: '192.168.0.185'
};

export const DATABASE_CONFIG = {
  CONNECTION_TIMEOUT: 5000,
  SOCKET_TIMEOUT: 45000,
  MAX_POOL_SIZE: 10
};

export const UPLOAD_CONFIG = {
  AD_FILE_SIZE_LIMIT: 10 * 1024 * 1024, // 10MB
  VIDEO_FILE_SIZE_LIMIT: 700 * 1024 * 1024, // 700MB
  ALLOWED_AD_TYPES: [
    'image/jpeg', 'image/png', 'image/gif', 'image/webp',
    'video/mp4', 'video/webm', 'video/avi'
  ],
  ALLOWED_VIDEO_TYPES: [
    'video/mp4', 'video/webm', 'video/avi', 'video/mov'
  ]
};

export const AD_CONFIG = {
  // Match the smallest prepaid pack so every product can fund a campaign.
  MIN_DAILY_BUDGET: 1,
  MIN_TOTAL_BUDGET: 30,
  DEFAULT_CPM: 30, // ₹30 per 1000 impressions (for carousel and video feed ads)
  BANNER_CPM: 20, // ₹20 per 1000 impressions (for banner ads)
  DEFAULT_BID_TYPE: 'CPM',
  CREATOR_REVENUE_SHARE: 0.80, // 80%
  PLATFORM_REVENUE_SHARE: 0.20, // 20%
  MAX_FREQUENCY_CAP: 10,
  MIN_FREQUENCY_CAP: 1
};

export const PAYMENT_CONFIG = {
  INVOICE_DUE_HOURS: 24,
  MIN_PAYOUT_AMOUNT: 200, // ₹200
  PAYOUT_SCHEDULE: {
    DAY: 1, // 1st of month
    HOUR: 9, // 9 AM
    MINUTE: 0
  }
};

export const HTTP_STATUS = {
  OK: 200,
  CREATED: 201,
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  INTERNAL_SERVER_ERROR: 500
};

export const ERROR_MESSAGES = {
  MISSING_REQUIRED_FIELDS: 'Missing required fields',
  INVALID_DATE_FORMAT: 'Invalid date format',
  END_DATE_AFTER_START: 'End date must be after start date',
  BUDGET_TOO_LOW: 'Budget must be at least ₹100',
  TOTAL_BUDGET_TOO_LOW: 'Total budget must be at least ₹1000',
  FILE_TOO_LARGE: 'File size exceeds the allowed limit',
  INVALID_FILE_TYPE: 'Invalid file type',
  CAMPAIGN_NOT_FOUND: 'Campaign not found',
  AD_NOT_FOUND: 'Ad not found',
  INVOICE_NOT_FOUND: 'Invoice not found',
  USER_NOT_FOUND: 'User not found',
  ACCESS_DENIED: 'Access denied',
  PAYMENT_REQUIRED: 'Payment required before activation'
};

export const SUCCESS_MESSAGES = {
  CAMPAIGN_CREATED: 'Campaign created successfully',
  CAMPAIGN_SUBMITTED: 'Campaign submitted for review',
  CAMPAIGN_ACTIVATED: 'Campaign activated successfully',
  CREATIVE_UPLOADED: 'Ad creative uploaded successfully',
  AD_CREATED: 'Ad created successfully. Payment required to activate.',
  PAYMENT_PROCESSED: 'Payment processed successfully. Ad is now active!',
  CLICK_TRACKED: 'Click tracked successfully'
};
