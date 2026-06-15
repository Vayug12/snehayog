import 'dart:convert';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/core/interfaces/i_notification_service.dart';

class NotificationService implements INotificationService {
  final AuthService _authService = AuthService();

  /// Send a direct alert to subscribers (Creator Only)
  @override
  Future<Map<String, dynamic>> sendCreatorAlert({
    required String message,
    String? title,
    String? targetUrl,
    List<String>? recipientIds,
  }) async {
    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) throw Exception('Not authenticated');

      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.apiBaseUrl}/notifications/creator-alert'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'message': message,
          if (title != null) 'title': title,
          if (targetUrl != null) 'targetUrl': targetUrl,
          if (recipientIds != null && recipientIds.isNotEmpty) 'recipientIds': recipientIds,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to send alert');
      }
    } catch (e) {
      AppLogger.log('❌ NotificationService: Error sending alert: $e');
      rethrow;
    }
  }

  /// Update notification preferences (Global or Creator-specific)
  @override
  Future<Map<String, dynamic>> updatePreferences({
    bool? globalEnabled,
    String? disabledCreatorId,
    String? enabledCreatorId,
  }) async {
    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) throw Exception('Not authenticated');

      final response = await httpClientService.patch(
        Uri.parse('${NetworkHelper.apiBaseUrl}/notifications/preferences'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          if (globalEnabled != null) 'globalEnabled': globalEnabled,
          if (disabledCreatorId != null) 'disabledCreatorId': disabledCreatorId,
          if (enabledCreatorId != null) 'enabledCreatorId': enabledCreatorId,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update preferences');
      }
    } catch (e) {
      AppLogger.log('❌ NotificationService: Error updating preferences: $e');
      rethrow;
    }
  }

  /// Get analytics for creator alerts
  @override
  Future<Map<String, dynamic>> getCreatorAlertStats() async {
    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) throw Exception('Not authenticated');

      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.apiBaseUrl}/notifications/creator-alert/stats'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch stats');
      }
    } catch (e) {
      AppLogger.log('❌ NotificationService: Error fetching stats: $e');
      rethrow;
    }
  }
}