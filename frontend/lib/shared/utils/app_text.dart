import 'package:vayug/shared/services/app_remote_config_service.dart';

/// AppText - Text Management System
///
/// This utility provides centralized text management:
/// - All texts come from backend (via AppRemoteConfig)
/// - Fallback to default texts if backend unavailable
/// - Prepared for multi-language support
/// - No hard-coded strings in UI
///
/// Usage:
/// ```dart
/// Text(AppText.get('app_name'))
/// Text(AppText.get('btn_upload', fallback: 'Upload'))
/// ```
class AppText {
  // Default fallback texts (used when backend config is unavailable)
  static const Map<String, String> _defaultTexts = {
    // Common texts
    'app_name': 'Vayu',
    'app_tagline': 'Create • Video • Share',

    // Navigation
    'nav_yug': 'Yug',
    'nav_vayu': 'Vayu',
    'nav_profile': 'Account',
    'nav_ads': 'Ads',

    // Buttons
    'btn_upload': 'Upload',
    'btn_create_ad': 'Create Advertisement',
    'btn_save': 'Save',
    'btn_cancel': 'Cancel',
    'btn_submit': 'Submit',
    'btn_visit_now': 'Visit Now',
    'btn_update_app': 'Update App',
    'btn_loading': 'Loading...',
    'btn_retry': 'Retry',
    'btn_delete': 'Delete',
    'btn_delete_all': 'Delete All',
    'btn_sign_in': 'Sign In',
    'btn_take_photo': 'Take Photo',
    'btn_choose_gallery': 'Choose from Gallery',
    'btn_update_now': 'Update Now',
    'btn_retry_upload': 'Retry Upload',
    'btn_upload_another': 'Upload',
    'btn_view_in_feed': 'View in Feed',
    'btn_i_understand': 'I Understand',
    'btn_manage_ads': 'Manage Ads',
    'btn_select_media': 'Select Media',
    'btn_upload_media': 'Upload Media',
    'btn_creating_ad': 'Creating Ad...',
    'btn_view_all': 'View All',
    'btn_close': 'Close',
    'btn_confirm': 'Confirm',
    'btn_withdraw_funds': 'Redeem Rewards',
    'btn_add_upi_id': 'Setup Billing',
    'btn_refer_friends': '2 Share & Unlock Full Access',
    'btn_sign_in_google': 'Sign In with Google',

    // Video player
    'video_picture_in_picture': 'Picture in picture',
    'video_pip_short': 'PiP',
    'video_pip_unavailable': 'Picture in picture is unavailable on this device',

    // Upload screen
    'upload_title': 'Upload & Create',
    'upload_select_media': 'Select Media',
    'upload_media_hint': 'Upload Video or Product Image',
    'upload_product_image_hint':
        'Product image selected. Please add your product/website URL in the External Link field.',
    'upload_please_sign_in': 'Please sign in to upload videos and create ads',
    'upload_choose_what_create': 'Choose what you want to create',
    'upload_video': 'Upload Video',
    'upload_video_desc': 'Share your video content with the community',
    'upload_create_ad': 'Create Ad',
    'upload_create_ad_desc':
        'Promote your content with targeted advertisements',
    'upload_no_video_selected': 'No video selected',
    'upload_processing_video': 'Processing video...',
    'upload_what_to_upload': 'What to Upload?',
    'upload_uploading': 'Uploading...',
    'upload_preparing_video': 'Preparing Video',
    'upload_preparing_desc': 'Validating file and preparing for upload...',
    'upload_uploading_video': 'Uploading Video',
    'upload_uploading_desc': 'Transferring video to server...',
    'upload_validating_video': 'Validating Video',
    'upload_validating_desc': 'Checking video format and quality...',
    'upload_processing_video_name': 'Processing Video',
    'upload_processing_desc': 'Converting to optimized format...',
    'upload_complete': 'Upload Complete!',
    'upload_complete_desc': 'Video processing completed successfully!',
    'upload_finalizing': 'Finalizing',
    'upload_finalizing_desc': 'Generating thumbnails and completing...',
    'upload_video_ready': 'Video is ready!',
    'upload_progress': 'Progress',
    'upload_time': 'Time:',
    'upload_success_title': 'Upload Successful! 🎉',
    'upload_success_message':
        'Your video has been uploaded and processed successfully! It is now available in your feed.',
    'upload_processed_ready':
        'Video has been processed and is ready for streaming!',
    'upload_login_required': 'Login Required',
    'upload_terms_title':
        'What to Upload? \nVayug Terms & Conditions (Copyright Policy)',
    'upload_terms_user_responsibility': '1. User Responsibility',
    'upload_terms_user_responsibility_desc':
        'By uploading, you confirm you are the original creator or have legal rights/permission to use this content. Do not upload media that infringes on others\' copyright, trademark, or intellectual property.',
    'upload_terms_copyright': '2. Copyright Infringement',
    'upload_terms_copyright_desc':
        'If you upload content belonging to someone else without permission, you (the uploader) will be fully responsible for any legal consequences. Vayug acts only as a platform and does not own or endorse user-uploaded content.',
    'upload_terms_reporting': '3. Reporting Copyright Violation',
    'upload_terms_reporting_desc':
        'Copyright owners may submit a takedown request by emailing: support@snehayog.site with proof of ownership. Upon receiving a valid request, Vayug will remove the infringing content within 48 hours.',
    'upload_terms_payment_desc':
        'All creator payments are subject to a 30-day hold for copyright checks and disputes. If a video is found infringing during this period, the transfer will be cancelled and may be withheld.',
    'upload_terms_strike': '5. Strike Policy',
    'upload_terms_strike_desc':
        '1st Strike → Warning & content removal.  2nd Strike → Account on hold for 60 days.  3rd Strike → Permanent ban, with forfeiture of unpaid rewards.',
    'upload_terms_liability': '6. Limitation of Liability',
    'upload_terms_liability_desc':
        'Vayug, as an intermediary platform, is not liable for user-uploaded content under the IT Act 2000 (India) and DMCA (international). All responsibility for copyright compliance lies with the content uploader.',
    'upload_error_select_video': 'Please select a video first',
    'upload_error_enter_title': 'Please enter a title for your content',
    'upload_error_select_category': 'Please select a category',
    'upload_error_file_too_large':
        'Video file is too large. Maximum size is 700MB',
    'upload_error_invalid_format':
        'Invalid video format. Supported formats: {formats}',
    'upload_error_file_not_exist': 'Selected video file does not exist',
    'upload_error_timeout':
        'Upload timed out. Please check your internet connection and try again.',
    'upload_error_file_access':
        'Error accessing video file. Please try selecting the video again.',
    'upload_error_sign_in_again':
        'Please sign in again to upload videos. Your session may have expired.',
    'upload_error_server_not_responding':
        'Server is not responding. Please check your connection and try again.',
    'upload_error_service_unavailable':
        'Video upload service is temporarily unavailable. Please try again later.',
    'upload_error_file_too_large_short':
        'Video file is too large. Maximum size is 700MB.',
    'upload_error_invalid_file_type':
        'Invalid video format. Please upload a supported video file.',
    'upload_error_duplicate':
        'You have already uploaded this video: "{name}". Please select a different video.',
    'upload_error_video_too_short':
        'Video is too short. Minimum length is 8 seconds.',
    'upload_error_invalid_file':
        'Please select a valid video file (MP4, AVI, MOV, WMV, FLV, or WebM).',

    // Ad creation
    'ad_create_title': 'Create Advertisement',
    'ad_budget_label': 'Daily Budget',
    'ad_duration_label': 'Campaign Duration',
    'ad_sign_in_to_create': 'Sign in to create ads',
    'ad_banner_details': 'Banner Details',
    'ad_details': 'Ad Details',
    'ad_tip_banner':
        'Tip: Keep headline short (4-6 words) and use a clear, bright image',
    'ad_tip_general': 'Tip: Use engaging visuals and a clear call-to-action',
    'ad_budget_duration': 'Budget & Duration',
    'ad_budget_recommended':
        'Recommended: ₹300/day for 14 days gives you good reach',
    'ad_daily_budget': 'Daily Budget (₹)',
    'ad_budget_hint': '300',
    'ad_budget_minimum': 'Minimum ₹100',
    'ad_budget_recommended_badge': 'Recommended',
    'ad_campaign_duration': 'Campaign Duration',
    'ad_advanced_settings': 'Advanced Settings (Optional)',
    'ad_advanced_settings_desc':
        'Smart targeting is enabled by default. Customize if needed.',
    'ad_smart_targeting':
        'Smart Targeting is ON: Your ad will automatically reach the right audience based on your content.',
    'ad_required_fields': 'Required Fields Checklist',
    'ad_banner_title_max': 'Banner Title (max 30 words)',
    'ad_title': 'Ad Title',
    'ad_description': 'Description',
    'ad_destination_url': 'Destination URL',
    'ad_link_url': 'Link URL',
    'ad_budget_min': 'Budget (₹100+)',
    'ad_campaign_dates': 'Campaign Dates',
    'ad_media_file': 'Media File',
    'ad_created_success':
        '✅ Advertisement created. You can create another one.',
    'ad_error_uploading_media': '📤 Uploading media files...',
    'ad_error_creating': '💳 Creating advertisement...',
    'ad_error_media_failed':
        '❌ Media upload failed - no URLs returned. Please try selecting different media files.',
    'ad_error_network':
        '❌ Network error: Please check your internet connection and try again.',
    'ad_error_media_upload':
        '❌ Media upload failed: Please try with different image/video files.',
    'ad_error_payment':
        '❌ Payment error: Please check your payment details and try again.',
    'ad_error_validation':
        '❌ Validation error: Please check all required fields are filled correctly.',
    'ad_error_server': '❌ Server error: Please try again in a few moments.',
    'ad_error_auth': '❌ Authentication error: Please sign in again.',
    'ad_error_forbidden':
        '❌ Access denied: You do not have permission to create ads.',
    'ad_error_failed': '❌ Failed to create ad: {message}',
    'ad_title_required': 'Ad title is required',
    'ad_title_too_long': 'Banner ad title must be 30 words or less',
    'ad_description_required': 'Description is required',
    'ad_link_required': 'Link URL is required',
    'ad_budget_required': 'Budget amount is required',
    'ad_budget_invalid': 'Please enter a valid budget amount (e.g., 100.00)',
    'ad_budget_minimum_error': 'Minimum budget is ₹100',
    'ad_budget_positive': 'Budget must be greater than ₹0',
    'ad_dates_required': 'Please select campaign start and end dates',
    'ad_end_after_start': 'End date must be after start date',
    'ad_start_not_past': 'Start date cannot be in the past',
    'ad_banner_image_required':
        'Banner ads require an image. Please select an image.',
    'ad_carousel_media_required':
        'Carousel ads require either images or video. Please select media.',
    'ad_age_range_invalid': 'Minimum age cannot be greater than maximum age',
    'ad_banner_only_images':
        'Banner ads only support images. Video has been removed.',
    'ad_banner_single_image':
        'Banner ads only support single images. Multiple images have been removed.',
    'ad_carousel_exclusive':
        'Carousel ads require exclusive selection. Please choose either images OR video.',

    // Profile
    'profile_my_videos': 'My Videos',
    'profile_earnings': 'Rewards',
    'profile_settings': 'Settings',
    'profile_title': 'Account',
    'profile_sign_in_title': 'Sign in to view your profile',
    'profile_sign_in_desc':
        'You need to sign in with your Google account to access your profile and upload videos.',
    'profile_sign_in_button': 'Sign in with Google',
    'profile_updated_success': 'Profile updated successfully!',
    'profile_photo_uploading': 'Uploading profile photo...',
    'profile_photo_updated': 'Profile photo updated successfully',
    'profile_change_photo': 'Change Profile Photo',
    'profile_take_photo': 'Take Photo',
    'profile_choose_gallery': 'Choose from Gallery',
    'profile_delete_videos_title': 'Delete Videos?',
    'profile_delete_videos_desc':
        'You are about to delete {count} video(s). This action cannot be undone.',
    'profile_videos_deleted': '{count} videos deleted successfully!',
    'profile_refer_friends': 'Refer 2 friends and get full access',
    'profile_top_earners': 'Top Creators (Following)',
    'profile_upi_notice': 'Score ke liye apna billing setup karein',
    'profile_video_earnings': 'Video Rewards',
    'profile_no_videos': 'No videos found',
    'profile_stat_subscribers': 'Subscribers',
    'profile_stat_content': 'Content',
    'profile_stat_earnings': 'Rewards',
    'profile_stat_rank': 'Ranking',
    'profile_sign_in_success': 'Signed in successfully!',
    'profile_logout_success': 'Logged out successfully',

    // Subscribers sheet
    'subscribers_title': 'Subscribers',
    'subscribers_title_count': '{count} Subscribers',
    'subscribers_subscribed_at': 'Subscribed {time}',
    'subscribers_new_badge': 'NEW',
    'subscribers_empty_title': 'No subscribers yet',
    'subscribers_empty_hint':
        'Share your videos - everyone who subscribes shows up here.',
    'subscribers_load_error': 'Could not load subscribers',
    'subscribers_error_hint': 'Check your connection and try again.',
    'subscribers_retry': 'Retry',

    // Settings
    'settings_title': 'Settings',
    'settings_developer_header': 'Developer Settings',
    'settings_developer_token': 'Access Token',
    'settings_token_usage': 'Use this token to authenticate with the Arcade Creator Web Portal.',
    'settings_token_copied': 'Token copied to clipboard',
    'settings_account_header': 'Account',
    'settings_linked_accounts': 'Linked Accounts',

    // Linked Accounts
    'linked_accounts_title': 'Linked Accounts',
    'linked_accounts_subtitle': 'Manage social accounts',
    'linked_accounts_youtube': 'YouTube',
    'linked_accounts_connect': 'Connect',
    'linked_accounts_connected': 'Connected',
    'linked_accounts_disconnect': 'Disconnect',
    'linked_accounts_refresh_hint': 'Refresh your profile after connecting to see the updated status.',
    'linked_accounts_opening_browser': 'Opening browser to connect YouTube...',
    
    // Cross-Posting Hinglish
    'crosspost_youtube_connect_title': 'YouTube Channel Connect Karo!',
    'crosspost_youtube_connect_desc': 'Video upload karte hi auto-post ho jayega YouTube par bhi. Zyada views pao aur apna time bachao. Bas ek baar connect karna hai.',
    'crosspost_youtube_connect_button': 'YouTube Connect Karo',
    'crosspost_youtube_connect_later': 'Baad mein karenge',
    'crosspost_youtube_success': 'YouTube connect ho gaya! Ab ye video wahan bhi upload hoga.',

    // Errors
    'error_network': 'Network error. Please check your connection.',
    'error_upload_failed': 'Upload failed. Please try again.',
    'error_invalid_url':
        'Please enter a valid URL starting with http:// or https://',
    'error_load_profile': 'Failed to load profile data',
    'error_load_videos': 'Unable to load videos. Please refresh.',
    'error_update_profile': 'Error updating profile',
    'error_change_photo': 'Error changing profile photo',
    'error_sign_in': 'Error signing in',
    'error_sign_in_network':
        'No stable connection. Sign-in could not be completed — please retry.',
    'error_sign_in_server':
        'Sign-in service is unavailable right now. Please try again shortly.',
    'auth_sign_in_cancelled': 'Sign-in cancelled',
    'error_sign_in_in_progress': 'Sign-in is already in progress.',
    'error_sign_in_partial':
        'Signed in, but your profile could not be loaded. Pull to refresh.',
    'error_logout': 'Error logging out',
    'error_share': 'Unable to share right now. Please try again.',
    'error_whatsapp':
        'Unable to open WhatsApp right now. Please try again later.',
    'error_refresh_cache': 'Unable to refresh profile. Showing cached data.',
    'error_refresh': 'Failed to refresh',
    'error_videos_load': 'Videos failed to load',
    'error_delete_videos': 'Failed to delete videos',
    'error_load_profile_generic': 'Failed to load profile. Please try again.',
    'error_profile_not_found': 'Profile not found.',
    'error_server': 'Server error. Please try again later.',
    'error_sign_in_again': 'Please sign in again to view your profile.',
    'error_auth_failed':
        'You appear to be signed in, but we couldn\'t load your profile.',
    'error_load_revenue': 'Error loading revenue data: {error}',
    'error_revenue_sign_in':
        'Please sign in again to view your revenue. Your session may have expired.',
    'error_revenue_token':
        'Authentication token not found. Please sign in again to view your revenue.',
    'error_revenue_videos':
        'Unable to load your videos. Please check your connection and try again.',

    // Success messages
    'success_upload': 'Upload successful!',
    'success_ad_created': 'Advertisement created successfully!',
    'success_withdrawal': 'Redemption initiated successfully!',
    'success_ad_created_full': '✅ Advertisement created successfully!',

    // Update messages
    'update_required':
        'A new version of the app is available. Please update to continue.',
    'update_recommended': 'A new version is available with exciting features!',

    // Revenue screen
    'revenue_title': 'Creator Activity',
    'revenue_creator_earnings': 'Creator Rewards',
    'revenue_gross_revenue': 'Total Engagement Score',
    'revenue_platform_fee': 'Platform Fee ({percent}%)',
    'revenue_this_month': 'This Month',
    'revenue_last_month': 'Last Month',
    'revenue_view_cycle': 'View Cycle Summary',
    'revenue_current_cycle_views': 'Current Cycle Views',
    'revenue_all_time_views': 'All-time Views',
    'revenue_cycle_period': 'Cycle Period',
    'revenue_next_reset': 'Next Reset',
    'revenue_previous_month': 'Previous Month Rewards',
    'revenue_no_earnings': 'No rewards in {month}',
    'revenue_start_creating': 'Start creating content to grow!',
    'revenue_total_earnings': 'Total Rewards',
    'revenue_analytics': 'Growth Analytics',
    'revenue_analytics_this_month': 'This Month',
    'revenue_breakdown': 'Performance Breakdown',
    'revenue_payment_history': 'Reward History',
    'revenue_no_payments': 'No rewards yet',
    'revenue_withdraw_earnings': 'Redeem Rewards',
    'revenue_available_balance': 'Available Score: {amount}',
    'revenue_min_withdrawal': 'Minimum redeemable: {amount}',
    'revenue_withdraw_dialog_title': 'Initiate Transfer',
    'revenue_withdraw_dialog_content':
    'This will initiate a transfer to your registered bank account. Processing time: 3-5 business days.',
    'revenue_video_breakdown': 'Video Performance Breakdown',
    'revenue_no_videos': 'No videos available',
    'revenue_upload_to_earn': 'Upload videos to start growing',
    'revenue_and_more': '... and {count} more videos',
    'revenue_detailed_analytics': 'Detailed Video Analytics',
    'revenue_impressions': '{count} impressions',
    'revenue_views': 'Views',
    'revenue_likes': 'Likes',
    'revenue_comments': 'Comments',
    'revenue_ad_impressions': 'Ad Impressions',
  };

  /// Get text by key
  ///
  /// [key] - Text key (e.g., 'app_name', 'btn_upload')
  /// [fallback] - Optional fallback text if key not found
  ///
  /// Returns text from backend config, or fallback, or key itself
  static String get(String key, {String? fallback}) {
    // Try to get from remote config first
    final configService = AppRemoteConfigService.instance;
    if (configService.isConfigAvailable) {
      final text = configService.getText(key, fallback: fallback);
      if (text != key) {
        // Text found in remote config
        return text;
      }
    }

    // Try default texts
    if (_defaultTexts.containsKey(key)) {
      return _defaultTexts[key]!;
    }

    // Use provided fallback or return key
    return fallback ?? key;
  }

  /// Get multiple texts at once
  ///
  /// Returns a map of key-value pairs
  static Map<String, String> getMultiple(List<String> keys) {
    final result = <String, String>{};
    for (final key in keys) {
      result[key] = get(key);
    }
    return result;
  }

  /// Check if a text key exists
  static bool hasKey(String key) {
    final configService = AppRemoteConfigService.instance;
    if (configService.isConfigAvailable) {
      final text = configService.getText(key);
      if (text != key) {
        return true;
      }
    }
    return _defaultTexts.containsKey(key);
  }

  /// Get all available text keys
  static List<String> getAllKeys() {
    final keys = <String>{};

    // Add keys from remote config
    final configService = AppRemoteConfigService.instance;
    if (configService.isConfigAvailable && configService.config != null) {
      keys.addAll(configService.config!.uiTexts.keys);
    }

    // Add default keys
    keys.addAll(_defaultTexts.keys);

    return keys.toList()..sort();
  }
}

/// Extension for easier text access in widgets
extension AppTextExtension on String {
  /// Get text using this string as key
  ///
  /// Usage:
  /// ```dart
  /// Text('app_name'.t)
  /// Text('btn_upload'.t(fallback: 'Upload'))
  /// ```
  String t({String? fallback}) => AppText.get(this, fallback: fallback);
}
