import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/rate_limit_info.dart';

void main() {
  group('RateLimitInfo', () {
    test('parses standard GitHub rate limit headers', () {
      final info = RateLimitInfo.fromHeaders({
        'X-RateLimit-Limit': ['5000'],
        'X-RateLimit-Remaining': ['4950'],
        'X-RateLimit-Reset': ['1795123200'],
      });

      expect(info, isNotNull);
      expect(info!.limit, 5000);
      expect(info.remaining, 4950);
      expect(info.isLow, isFalse);
      expect(info.isExhausted, isFalse);
      expect(info.resetAt, isNotNull);
    });

    test('flags low and exhausted quotas accurately', () {
      final low = RateLimitInfo.fromHeaders({
        'x-ratelimit-limit': ['5000'],
        'x-ratelimit-remaining': ['100'],
      });
      expect(low!.isLow, isTrue);
      expect(low.isExhausted, isFalse);

      final empty = RateLimitInfo.fromHeaders({
        'x-ratelimit-limit': ['5000'],
        'x-ratelimit-remaining': ['0'],
      });
      expect(empty!.isExhausted, isTrue);
    });
  });
}
