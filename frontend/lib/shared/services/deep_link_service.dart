import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:flutter/material.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/features/video/vayu/presentation/screens/vayu_long_form_player_screen.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  void initialize() {
    _appLinks = AppLinks();
    _checkInitialLink();
    _listenToLinks();
  }

  Future<void> _checkInitialLink() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (e) {
      AppLogger.log('❌ DeepLinkService: Error getting initial link: $e');
    }
  }

  void _listenToLinks() {
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    }, onError: (err) {
      AppLogger.log('❌ DeepLinkService: Stream error: $err');
    });
  }

  void _handleUri(Uri uri) {
    AppLogger.log('🔗 DeepLinkService: Handling URI: $uri');
    
    // **FIX: Ignore legal links to prevent circular interception when launching externally**
    final path = uri.path.toLowerCase();
    if (path.contains('/privacy.html') || 
        path.contains('/terms.html') || 
        path.contains('/refund.html') || 
        path.contains('/contact.html') || 
        path.contains('/about.html')) {
      AppLogger.log('🔗 DeepLinkService: Ignoring legal link (should open in browser)');
      return;
    }

    // Check for social success (vayu://auth/social-success?platform=youtube)
    if (path.contains('social-success')) {
      final platform = uri.queryParameters['platform'];
      AppLogger.log('🔗 DeepLinkService: Social connection success for $platform');
      return;
    }

    // **NEW: Handle Video Links (vayu://video/ID or snehayog://video/ID)**
    if (path.startsWith('/video/')) {
      final segments = uri.pathSegments;
      if (segments.length >= 2) {
        final videoId = segments[1];
        AppLogger.log('🔗 DeepLinkService: Handling deep link for video: $videoId');
        
        // Smart Routing: Fetch metadata first to decide between Yug and Vayu.
        // `t` and `end` are seconds in a section-share link.
        final startAt = _parseTimestampSeconds(uri.queryParameters['t']);
        final sectionEnd = _parseTimestampSeconds(uri.queryParameters['end']);
        _routeToVideoSmartly(
          videoId,
          initialPosition: startAt == null ? null : Duration(seconds: startAt),
          sectionEnd: sectionEnd != null && (startAt == null || sectionEnd > startAt)
              ? Duration(seconds: sectionEnd)
              : null,
        );
        return;
      }
    }

    // Check for referral code (?ref=CODE)
    if (uri.queryParameters.containsKey('ref') || uri.path.contains('ref=')) {
      String? refCode = uri.queryParameters['ref'];
      
      // Fallback for weird URL formats
      if (refCode == null || refCode.isEmpty) {
        final pathStr = uri.path;
        if (pathStr.contains('ref=')) {
          final parts = pathStr.split('ref=');
          if (parts.length > 1) {
            final afterRef = parts.last;
            final subParts = afterRef.split('&');
            if (subParts.isNotEmpty) {
              refCode = subParts.first;
            }
          }
        }
      }

      if (refCode != null && refCode.isNotEmpty) {
        _saveReferralCode(refCode);
      }
    }
  }

  int? _parseTimestampSeconds(String? value) {
    final seconds = int.tryParse(value ?? '');
    return seconds != null && seconds >= 0 ? seconds : null;
  }

  void _routeToVideoSmartly(
    String videoId, {
    Duration? initialPosition,
    Duration? sectionEnd,
  }) async {
    try {
      AppLogger.log('🔗 DeepLinkService: Fetching metadata for smart routing: $videoId');
      
      // We use a short timeout to prevent hanging the app if network is bad
      final videoService = VideoService();
      final video = await videoService.getVideoById(videoId).timeout(
        const Duration(seconds: 4),
        onTimeout: () => throw TimeoutException('Metadata fetch timed out'),
      );

      AppLogger.log('🔗 DeepLinkService: Metadata found. Type=${video.videoType}, AR=${video.aspectRatio}');

      final context = AuthService.navigatorKey.currentContext;
      if (context == null) return;

      if (video.videoType == 'vayu' || video.aspectRatio > 1.2) {
        AppLogger.log('🔗 DeepLinkService: Routing to VAYU (Landscape) Player');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VayuLongFormPlayerScreen(
              video: video,
              initialPosition: initialPosition,
              sectionEnd: sectionEnd,
            ),
            settings: const RouteSettings(name: '/vayu_video'),
          ),
        );
      } else {
        AppLogger.log('🔗 DeepLinkService: Routing to YUG (Vertical) Feed');
        Navigator.pushNamed(
          context,
          '/video',
          arguments: {
            'videoId': videoId,
            if (initialPosition != null) 'startAtSeconds': initialPosition.inSeconds,
            if (sectionEnd != null) 'endAtSeconds': sectionEnd.inSeconds,
          },
        );
      }
    } catch (e) {
      AppLogger.log('🔗 DeepLinkService: Routing fallback due to error: $e');
      // Fallback: Just push the standard /video route if fetch fails
      AuthService.navigatorKey.currentState?.pushNamed(
        '/video',
        arguments: {
          'videoId': videoId,
          if (initialPosition != null) 'startAtSeconds': initialPosition.inSeconds,
          if (sectionEnd != null) 'endAtSeconds': sectionEnd.inSeconds,
        },
      );
    }
  }

  Future<void> _saveReferralCode(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Only save if not already signed in (don't overwrite or track for existing users here)
      // Actually, saved referral code is tracked during sign-up in AuthService.
      await prefs.setString('pending_referral_code', code);
      AppLogger.log('🎁 DeepLinkService: Saved referral code: $code');
    } catch (e) {
      AppLogger.log('❌ DeepLinkService: Error saving referral code: $e');
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
