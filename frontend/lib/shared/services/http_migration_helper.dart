/// HTTP Migration Helper
/// This file provides examples and patterns for migrating services to use the shared HTTP client
/// 
/// MIGRATION PATTERN:
/// 
/// BEFORE (creates new connections):
/// ```dart
/// import 'package:http/http.dart' as http;
/// 
/// final response = await http.get(Uri.parse('$baseUrl/api/endpoint'));
/// final response = await http.post(Uri.parse('$baseUrl/api/endpoint'), 
///   headers: headers, body: jsonEncode(data));
/// ```
/// 
/// AFTER (uses connection pooling):
/// ```dart
/// import 'package:http/http.dart' as http;
/// import 'package:vayug/shared/services/http_client_service.dart';
/// 
/// final response = await httpClientService.get(Uri.parse('$baseUrl/api/endpoint'));
/// final response = await httpClientService.post(Uri.parse('$baseUrl/api/endpoint'), 
///   headers: headers, body: jsonEncode(data));
/// ```
/// 
/// BENEFITS:
/// - Connection reuse (no new TLS handshakes)
/// - Reduced latency (3-5x faster subsequent requests)
/// - Better resource management
/// - Automatic retry logic
/// - Centralized timeout configuration
/// 
/// SERVICES TO UPDATE:
/// - authservices.dart ✅ (completed)
/// - video_service.dart ✅ (completed) 
/// - cloudflare_r2_service.dart ✅ (completed)
/// - ad_service.dart ✅ (completed)
/// - user_service.dart ✅ (completed)
/// - feedback_service.dart ✅ (completed)
/// - carousel_ad_service.dart ✅ (completed)
/// - active_ads_service.dart ✅ (completed)
/// - ad_targeting_service.dart ✅ (completed)
/// - location_onboarding_service.dart ✅ (completed)
/// - payment_setup_service.dart ✅ (completed)
/// - report_service.dart ✅ (completed)
/// - video_view_tracker.dart ✅ (completed)
/// - city_search_service.dart ✅ (completed)
/// - ad_impression_service.dart ✅ (completed)
/// - ad_comment_service.dart ✅ (completed)
/// - creator_payout_dashboard.dart ✅ (completed - uses http.Response type from httpClientService)
/// - debug_helper.dart ✅ (completed)
/// 
/// NOTE: Some files may still import 'package:http/http.dart' for type annotations (http.Response)
/// This is expected and necessary since httpClientService returns http.Response for compatibility
/// 
/// CONNECTION POOLING CONFIGURATION:
/// The shared HTTP client automatically handles:
/// - Keep-alive connections
/// - Connection reuse
/// - Proper connection cleanup
/// - Retry logic with exponential backoff
/// - Timeout management
/// 
/// PERFORMANCE IMPROVEMENTS:
/// - First request: Normal latency (establishes connection)
/// - Subsequent requests: 3-5x faster (reuses connection)
/// - Reduced server load (fewer connection establishments)
/// - Better battery life (fewer network operations)
/// 
/// USAGE EXAMPLES:
/// 
/// Simple GET request:
/// ```dart
/// final response = await httpClientService.get(
///   Uri.parse('$baseUrl/api/videos'),
///   headers: {'Authorization': 'Bearer $token'},
/// );
/// ```
/// 
/// POST request with retry:
/// ```dart
/// final response = await httpClientService.makeRequest(
///   () => httpClientService.post(
///     Uri.parse('$baseUrl/api/videos/upload'),
///     headers: headers,
///     body: jsonEncode(data),
///   ),
///   maxRetries: 3,
///   retryDelay: Duration(seconds: 1),
/// );
/// ```
/// 
/// Multipart request:
/// ```dart
/// final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'));
/// request.files.add(await http.MultipartFile.fromPath('file', filePath));
/// final response = await httpClientService.send(request);
/// ```
