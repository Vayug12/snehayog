import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/features/video/core/data/services/picture_in_picture_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Top-level function for handling background messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('📱 Background message received: ${message.messageId}');
  print('📱 Title: ${message.notification?.title}');
  print('📱 Body: ${message.notification?.body}');
  print('📱 Data: ${message.data}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static final StreamController<RemoteMessage> _messageStreamController =
      StreamController<RemoteMessage>.broadcast();
  static Stream<RemoteMessage> get onMessageStream =>
      _messageStreamController.stream;

  FirebaseMessaging? _messaging;
  String? _fcmToken;
  bool _initialized = false;
  Timer? _retryTimer;
  bool _isRetrying = false;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _localNotificationsInitialized = false;

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'default',
    'General Notifications',
    description: 'General app notifications',
    importance: Importance.high,
  );

  /// Dedicated channel for AI video generation progress.
  /// Importance.low keeps it silent so frequent progress updates don't spam
  /// the user with sound/heads-up popups.
  static const AndroidNotificationChannel _aiProgressChannel =
      AndroidNotificationChannel(
    'ai_video_progress',
    'AI Video Generation',
    description: 'Shows the progress of your AI video while it generates',
    importance: Importance.low,
  );

  /// Fixed id so progress updates replace the same notification instead of
  /// stacking new ones.
  static const int _aiProgressNotificationId = 71001;

  /// Initialize Firebase and FCM
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      // Initialize Firebase (idempotent if already initialized in main.dart)
      await Firebase.initializeApp();
      print('✅ Firebase initialized (NotificationService)');

      // Initialize local notifications (for foreground messages)
      await _initializeLocalNotifications();

      // Initialize Firebase Messaging
      print('🚀 Initializing FirebaseMessaging instance...');
      _messaging = FirebaseMessaging.instance;

      // Request permission (iOS)
      print('🚀 Requesting notification permission...');
      final NotificationSettings settings =
          await PictureInPictureService.instance.withAutoEnterSuppressed(
        () => _messaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        ),
      );
      print(
          '🚀 Permission request completed. Status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Notification permission granted');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        print('⚠️ Notification permission granted provisionally');
      } else {
        print('❌ Notification permission denied');
        return;
      }

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        print('📱 Foreground message received: ${message.messageId}');
        print('📱 Title: ${message.notification?.title}');
        print('📱 Body: ${message.notification?.body}');
        print('📱 Data: ${message.data}');

        // Show a local notification when app is in foreground
        await _showLocalNotification(message);

        // Add message to stream
        _messageStreamController.add(message);
      });

      // Handle notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('📱 Notification opened app: ${message.messageId}');
        print('📱 Data: ${message.data}');
        _handleNotificationTap(message);
      });

      // Check if app was opened from a terminated state via notification
      RemoteMessage? initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        print('📱 App opened from terminated state via notification');
        _handleNotificationTap(initialMessage);
      }

      // Get FCM token
      await _getFCMToken();

      // Start periodic retry mechanism
      _startPeriodicRetry();

      _initialized = true;
      print('✅ NotificationService initialized successfully');
    } catch (e) {
      print('❌ Error initializing NotificationService: $e');
    }
  }

  /// Start periodic retry mechanism to save FCM token when user logs in
  void _startPeriodicRetry() {
    // Stop any existing timer
    _retryTimer?.cancel();

    // Check every 30 seconds if user is logged in and token needs to be saved
    // Reduced frequency to avoid spamming backend
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (_isRetrying) return; // Prevent concurrent retries

      // Only retry if we have FCM token but haven't saved it yet
      if (_fcmToken != null) {
        final prefs = await SharedPreferences.getInstance();
        final authToken = prefs.getString('jwt_token');
        final lastSavedToken = prefs.getString('last_saved_fcm_token');

        // Retry if:
        // 1. User is now authenticated (has JWT token)
        // 2. Token hasn't been saved yet OR token changed
        if (authToken != null &&
            authToken.isNotEmpty &&
            (lastSavedToken != _fcmToken)) {
          print('🔄 Periodic retry: User authenticated, saving FCM token...');
          _isRetrying = true;
          await _saveTokenToBackend(_fcmToken!);
          _isRetrying = false;

          // If successfully saved, we can stop checking (token refresh will handle updates)
          final savedToken = prefs.getString('last_saved_fcm_token');
          if (savedToken == _fcmToken) {
            print(
                '✅ FCM token saved via periodic retry, stopping periodic checks');
            timer.cancel();
            _retryTimer = null;
          }
        }
      }
    });

    print('🔄 Started periodic retry mechanism (checks every 30 seconds)');
  }

  /// Initialize local notifications (used for foreground FCM messages)
  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) return;

    try {
      const androidInitSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const initSettings = InitializationSettings(
        android: androidInitSettings,
      );

      await _localNotificationsPlugin.initialize(
        initSettings,
      );

      // Create Android notification channel to match backend channelId "default"
      final androidPlatform =
          _localNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlatform?.createNotificationChannel(_androidChannel);
      await androidPlatform?.createNotificationChannel(_aiProgressChannel);

      _localNotificationsInitialized = true;
      print('✅ Local notifications initialized');
    } catch (e) {
      print('⚠️ Failed to initialize local notifications: $e');
    }
  }

  /// Stop periodic retry mechanism
  void _stopPeriodicRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Get FCM token and save it to backend
  Future<String?> _getFCMToken() async {
    try {
      if (_messaging == null) {
        print('⚠️ Firebase Messaging not initialized');
        return null;
      }

      // Get token
      _fcmToken = await _messaging!.getToken();

      if (_fcmToken == null) {
        print('⚠️ FCM token is null');
        return null;
      }

      print('🔥🔥 FCM TOKEN: $_fcmToken');

      // Save token to backend
      await _saveTokenToBackend(_fcmToken!);

      // Listen for token refresh
      _messaging!.onTokenRefresh.listen((newToken) {
        print('🔄 FCM token refreshed: ${newToken.substring(0, 20)}...');
        _fcmToken = newToken;
        _saveTokenToBackend(newToken);
      });

      return _fcmToken;
    } catch (e) {
      print('❌ Error getting FCM token: $e');
      return null;
    }
  }

  /// Save FCM token to backend
  Future<void> _saveTokenToBackend(String fcmToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('jwt_token');

      if (authToken == null || authToken.isEmpty) {
        print('⚠️ User not authenticated, skipping FCM token save');
        return;
      }

      final baseUrl = AppConfig.baseUrl;
      final response = await httpClientService.post(
        Uri.parse('$baseUrl/api/notifications/token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'fcmToken': fcmToken,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ FCM token saved to backend');
        // Store in SharedPreferences to avoid resending unnecessarily
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_saved_fcm_token', fcmToken);

        // Stop periodic retry since token is now saved
        _stopPeriodicRetry();
      } else {
        print('❌ Failed to save FCM token: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('❌ Error saving FCM token to backend: $e');
    }
  }

  /// Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;

    // Handle different notification types based on data
    if (data.containsKey('type')) {
      final navigator = AuthService.navigatorKey.currentState;
      if (navigator == null) {
        print('⚠️ Navigator state is null, cannot navigate');
        return;
      }

      switch (data['type']) {
        case 'video':
          // Navigate to video screen
          final videoId = data['videoId'];
          print('📱 Navigate to video: $videoId');
          if (videoId != null) {
            navigator.pushNamed('/video', arguments: {'videoId': videoId});
          }
          break;
        case 'user':
          // Navigate to user profile
          final userId = data['userId'];
          print('📱 Navigate to user: $userId');
          if (userId != null) {
            // Assuming there is a '/profile' route or similar.
            // If not, we might need to add it or use a specific screen widget.
            // For now, I'll assume we can push a profile screen if it exists,
            // OR finding that the user hasn't defined a named route for generic profile yet
            // based on main.dart routes.
            // checking main.dart again.. only /home and /video are defined.
            // I will leave a TODO or try to navigate to /home with arguments?
            // Actually, best to just log it for now if route doesn't exist,
            // or perform a best effort.
            // I will implement video navigation primarily as requested.
            print('⚠️ Profile route not defined in main.dart yet.');
          }
          break;
        default:
          print('📱 Unknown notification type: ${data['type']}');
      }
    }
  }

  /// Show a local notification for foreground messages
  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (!_localNotificationsInitialized) {
      return;
    }

    try {
      final notification = message.notification;
      final title = notification?.title ?? message.data['title'] ?? 'Vayu';
      final body = notification?.body ?? message.data['body'] ?? '';

      final androidDetails = AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
      );

      await _localNotificationsPlugin.show(
        message.hashCode,
        title,
        body,
        details,
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      print('⚠️ Failed to show local notification: $e');
    }
  }

  /// Show/update an ongoing progress notification for AI video generation.
  /// Uses a fixed id so each call replaces the previous progress bar.
  Future<void> showAiVideoProgress({
    required int progressPercent,
    required String statusText,
  }) async {
    try {
      await _initializeLocalNotifications();
      final pct = progressPercent.clamp(0, 100);
      final androidDetails = AndroidNotificationDetails(
        _aiProgressChannel.id,
        _aiProgressChannel.name,
        channelDescription: _aiProgressChannel.description,
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true, // don't buzz on every progress update
        showProgress: true,
        maxProgress: 100,
        progress: pct,
        ongoing: true, // can't be swiped away while generating
        autoCancel: false,
        icon: '@mipmap/ic_launcher',
      );
      await _localNotificationsPlugin.show(
        _aiProgressNotificationId,
        'Generating your AI video',
        '$statusText • $pct%',
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      print('⚠️ Failed to show AI video progress notification: $e');
    }
  }

  /// Replace the progress notification with a tappable "ready" notification.
  Future<void> showAiVideoComplete() async {
    try {
      await _initializeLocalNotifications();
      final androidDetails = AndroidNotificationDetails(
        _aiProgressChannel.id,
        _aiProgressChannel.name,
        channelDescription: _aiProgressChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        autoCancel: true,
        ongoing: false,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );
      await _localNotificationsPlugin.show(
        _aiProgressNotificationId,
        '✅ Video ready!',
        'Your AI video has been saved to your gallery.',
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      print('⚠️ Failed to show AI video complete notification: $e');
    }
  }

  /// Replace the progress notification with a failure notification.
  Future<void> showAiVideoFailed(String message) async {
    try {
      await _initializeLocalNotifications();
      final androidDetails = AndroidNotificationDetails(
        _aiProgressChannel.id,
        _aiProgressChannel.name,
        channelDescription: _aiProgressChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        autoCancel: true,
        ongoing: false,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );
      await _localNotificationsPlugin.show(
        _aiProgressNotificationId,
        '❌ Video generation failed',
        message,
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      print('⚠️ Failed to show AI video failed notification: $e');
    }
  }

  /// Dismiss the AI video generation notification entirely.
  Future<void> cancelAiVideoNotification() async {
    try {
      await _localNotificationsPlugin.cancel(_aiProgressNotificationId);
    } catch (e) {
      print('⚠️ Failed to cancel AI video notification: $e');
    }
  }

  /// Retry saving FCM token to backend (call this after user logs in)
  /// Note: Periodic retry mechanism will also handle this automatically
  Future<void> retrySaveToken() async {
    if (_fcmToken != null) {
      print('🔄 Manual retry: Saving FCM token after login...');
      await _saveTokenToBackend(_fcmToken!);
    } else {
      print('⚠️ No FCM token available to save');
      // Try to get token again
      await _getFCMToken();
    }
  }

  /// Cleanup when service is disposed
  void dispose() {
    _stopPeriodicRetry();
  }

  /// Get current FCM token
  String? get fcmToken => _fcmToken;

  /// Check if service is initialized
  bool get isInitialized => _initialized;
}
