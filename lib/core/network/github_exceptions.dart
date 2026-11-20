/// Typed exception hierarchy for GitHub REST / Git Data API failures.
sealed class GitHubException implements Exception {
  final String message;
  final int? statusCode;

  const GitHubException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

final class InvalidTokenException extends GitHubException {
  const InvalidTokenException([
    super.message = 'التوكن غير صالح أو منتهي الصلاحية. تحقق من الـ PAT وحاول مجدداً.',
  ]) : super(statusCode: 401);
}

final class InsufficientScopeException extends GitHubException {
  final List<String> grantedScopes;

  const InsufficientScopeException({
    required this.grantedScopes,
    String message = 'التوكن يفتقر إلى صلاحية (repo) المطلوبة لقراءة المستودعات والنشر.',
  }) : super(message, statusCode: 403);
}

final class RateLimitException extends GitHubException {
  final DateTime? resetAt;

  const RateLimitException({
    this.resetAt,
    String message = 'تم تجاوز حد طلبات GitHub API مؤقتاً. انتظر قليلاً ثم أعد المحاولة.',
  }) : super(message, statusCode: 403);
}

final class NetworkConnectionException extends GitHubException {
  const NetworkConnectionException([
    super.message = 'تعذر الاتصال بخوادم GitHub. تحقق من اتصال الإنترنت.',
  ]);
}

final class GitHubApiException extends GitHubException {
  const GitHubApiException(super.message, {super.statusCode});
}
