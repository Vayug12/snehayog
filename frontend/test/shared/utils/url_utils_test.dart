import 'package:flutter_test/flutter_test.dart';
import 'package:vayug/shared/utils/url_utils.dart';

void main() {
  group('UrlUtils.enrichUrl Tests', () {
    test('Should add https if scheme is missing', () {
      final result = UrlUtils.enrichUrl('snehayog.site');
      expect(result, contains('https://snehayog.site'));
    });

    test('Should add UTM parameters correctly', () {
      const url = 'https://google.com';
      final result = UrlUtils.enrichUrl(
        url,
        source: 'test_source',
        medium: 'test_medium',
        campaign: 'test_campaign',
      );

      expect(result, contains('utm_source=test_source'));
      expect(result, contains('utm_medium=test_medium'));
      expect(result, contains('utm_campaign=test_campaign'));
    });

    test('Should handle whitespace and trim URL', () {
      final result = UrlUtils.enrichUrl('  https://vayu.app  ');
      expect(result, startsWith('https://vayu.app'));
    });
  });

  group('video share URLs', () {
    test('builds an ID-first URL with a title slug', () {
      final result = UrlUtils.buildVideoShareUrl(
        '507f1f77bcf86cd799439011',
        "Creator's Tips & Tricks!",
      );

      expect(
        result,
        'https://snehayog.site/video/507f1f77bcf86cd799439011/creators-tips-and-tricks',
      );
    });

    test('preserves section timestamps', () {
      final result = UrlUtils.buildVideoShareUrl(
        '507f1f77bcf86cd799439011',
        'Morning Yoga',
        queryParameters: {'t': '30', 'end': '75'},
      );

      expect(result, contains('/507f1f77bcf86cd799439011/morning-yoga?'));
      expect(result, contains('t=30'));
      expect(result, contains('end=75'));
    });

    test('uses a stable fallback for titles without ASCII words', () {
      expect(UrlUtils.slugifyVideoTitle('!!!'), 'video');
    });
  });
}
