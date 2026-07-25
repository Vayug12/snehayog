import 'package:flutter/material.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

class DebugHelper {
  static void showDebugInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔍 Debug Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Backend URL: ${AppConfig.baseUrl}'),
              const SizedBox(height: 8),
              const Text('Environment: Development'), // Hardcoded for now
              const SizedBox(height: 16),
              const Text('Common Issues:'),
              const Text('• Backend server not running'),
              const Text('• Wrong IP address in config'),
              const Text('• Network permissions not granted'),
              const Text('• Google Sign-In not configured'),
              const SizedBox(height: 16),
              const Text('To fix:'),
              const Text('1. Start your backend server'),
              const Text('2. Check the IP address in app_config.dart'),
              const Text('3. Ensure network permissions are granted'),
              const Text('4. Configure Google Sign-In in Google Cloud Console'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () => _testBackendConnection(context),
            child: const Text('Test Connection'),
          ),
        ],
      ),
    );
  }

  static Future<void> _testBackendConnection(BuildContext context) async {
    try {
      final response = await httpClientService.get(
        Uri.parse('${AppConfig.baseUrl}/api/health'),
        timeout: const Duration(seconds: 5),
      );

      if (response.statusCode == 200) {
        _showResult(context, 'Backend is accessible!', VayuSnackBarType.success);
      } else {
        _showResult(
            context,
            'Backend responded with status: ${response.statusCode}',
            VayuSnackBarType.warning);
      }
    } catch (e) {
      _showResult(context, 'Backend connection failed: $e', VayuSnackBarType.error);
    }
  }

  static void _showResult(
      BuildContext context, String message, VayuSnackBarType type) {
    VayuSnackBar.show(context, message, type: type);
  }

  static void logSignInAttempt(String step, {String? details}) {
    final timestamp = DateTime.now().toIso8601String();
    AppLogger.log(
        '🔐 [$timestamp] $step${details != null ? ': $details' : ''}');
  }

  static void logError(String step, String error) {
    final timestamp = DateTime.now().toIso8601String();
    AppLogger.log('❌ [$timestamp] $step - Error: $error');
  }

  static void logSuccess(String step, {String? details}) {
    final timestamp = DateTime.now().toIso8601String();
    AppLogger.log('✅ [$timestamp] $step${details != null ? ': $details' : ''}');
  }
}
