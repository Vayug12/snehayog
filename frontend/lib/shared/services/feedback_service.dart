import 'dart:convert';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/models/feedback_model.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/install_attribution_service.dart';

class FeedbackService {
  final AuthService _authService = AuthService();
  static String get baseUrl => NetworkHelper.getBaseUrl();

  /// Submit feedback to the server
  Future<bool> submitFeedback({
    required int rating,
    required String comments,
    String type = 'general',
  }) async {
    try {
      // Get user data to extract email and ID
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final attribution =
          await InstallAttributionService.instance.getAttributionPayload();
      final payload = <String, dynamic>{
        'rating': rating,
        'comments': comments,
        'type': type,
        'userEmail': userData['email'] ?? 'anonymous@user.com',
        'userId': userData['googleId'] ?? userData['id'],
      };

      if (attribution.isNotEmpty) {
        payload['attribution'] = attribution;
      }

      final response = await httpClientService.post(
        Uri.parse('$baseUrl/api/feedback/submit'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        return responseData['success'] == true;
      } else {
        print(
            'Error submitting feedback: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error in submitFeedback: $e');
      return false;
    }
  }

  /// Get user's feedback history
  Future<List<FeedbackModel>> getFeedbackHistory() async {
    try {
      final token = await _authService.refreshTokenIfNeeded();
      if (token == null) {
        throw Exception('User not authenticated');
      }

      final response = await httpClientService.get(
        Uri.parse('$baseUrl/api/feedback/history'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((json) => FeedbackModel.fromJson(json)).toList();
      } else {
        print('Error fetching feedback history: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error in getFeedbackHistory: $e');
      return [];
    }
  }
}
