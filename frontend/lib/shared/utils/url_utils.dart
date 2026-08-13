import 'package:vayug/shared/utils/app_logger.dart';

class UrlUtils {
  static const int _maxVideoSlugLength = 80;

  static String slugifyVideoTitle(String title) {
    var slug = title
        .trim()
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    if (slug.length > _maxVideoSlugLength) {
      slug = slug.substring(0, _maxVideoSlugLength).replaceAll(
            RegExp(r'-+$'),
            '',
          );
    }

    return slug.isEmpty ? 'video' : slug;
  }

  static String buildVideoShareUrl(
    String videoId,
    String title, {
    Map<String, String>? queryParameters,
  }) {
    return Uri.https(
      'snehayog.site',
      '/video/$videoId/${slugifyVideoTitle(title)}',
      queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    ).toString();
  }

  /// Enriches a URL with UTM parameters for attribution tracking.
  /// 
  /// [source] defaults to 'vayug'
  /// [medium] e.g., 'app_ad', 'profile', 'internal_link'
  /// [campaign] e.g., 'vayug_ads', 'creator_visit'
  /// [content] optional specific identifier (e.g., ad ID)
  static String enrichUrl(
    String url, {
    String source = 'vayug',
    String? medium,
    String? campaign,
    String? content,
  }) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) return trimmedUrl;

    try {
      // Ensure the URL has a scheme before parsing
      final effectiveUrl = trimmedUrl.startsWith('http') 
          ? trimmedUrl 
          : 'https://$trimmedUrl';
          
      final uri = Uri.parse(effectiveUrl);
      final queryParams = Map<String, String>.from(uri.queryParameters);

      // Add UTM parameters if they aren't already present
      if (!queryParams.containsKey('utm_source')) {
        queryParams['utm_source'] = source;
      }
      if (medium != null && !queryParams.containsKey('utm_medium')) {
        queryParams['utm_medium'] = medium;
      }
      if (campaign != null && !queryParams.containsKey('utm_campaign')) {
        queryParams['utm_campaign'] = campaign;
      }
      if (content != null && !queryParams.containsKey('utm_content')) {
        queryParams['utm_content'] = content;
      }

      final enrichedUri = uri.replace(queryParameters: queryParams);
      final finalUrl = enrichedUri.toString();
      
      AppLogger.log('🔗 UrlUtils: Enriched URL: $finalUrl');
      return finalUrl;
    } catch (e) {
      AppLogger.log('⚠️ UrlUtils: Error enriching URL ($url): $e');
      return trimmedUrl; // Return original if parsing fails
    }
  }
}
