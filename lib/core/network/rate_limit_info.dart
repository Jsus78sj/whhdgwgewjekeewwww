/// Tracks GitHub REST API rate-limit quota parsed from response headers.
class RateLimitInfo {
  final int limit;
  final int remaining;
  final DateTime? resetAt;
  final DateTime updatedAt;

  const RateLimitInfo({
    required this.limit,
    required this.remaining,
    required this.resetAt,
    required this.updatedAt,
  });

  double get usedFraction {
    if (limit <= 0) return 0;
    return ((limit - remaining) / limit).clamp(0.0, 1.0);
  }

  bool get isLow => limit > 0 && remaining <= (limit * 0.1).ceil();

  bool get isExhausted => limit > 0 && remaining == 0;

  Duration? get timeUntilReset {
    if (resetAt == null) return null;
    final diff = resetAt!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  static RateLimitInfo? fromHeaders(Map<String, List<String>> headers) {
    final normalized = <String, String>{};
    headers.forEach((key, values) {
      if (values.isNotEmpty) {
        normalized[key.toLowerCase()] = values.first;
      }
    });

    final limit = int.tryParse(normalized['x-ratelimit-limit'] ?? '');
    final remaining = int.tryParse(normalized['x-ratelimit-remaining'] ?? '');
    if (limit == null || remaining == null) return null;

    final resetSeconds = int.tryParse(normalized['x-ratelimit-reset'] ?? '');
    final resetAt = resetSeconds != null
        ? DateTime.fromMillisecondsSinceEpoch(
            resetSeconds * 1000,
            isUtc: true,
          ).toLocal()
        : null;

    return RateLimitInfo(
      limit: limit,
      remaining: remaining,
      resetAt: resetAt,
      updatedAt: DateTime.now(),
    );
  }
}
