/// Exception types mapped from the API's error envelope. Everything extends
/// [GoalApiException].
library;

class GoalApiException implements Exception {
  GoalApiException(
    this.message, {
    this.status,
    this.code,
    this.category,
    this.details,
    this.correlationId,
    this.headers,
    this.cause,
  });

  /// From the response body, or from the SDK on a transport failure.
  final String message;

  /// HTTP status, or null for a network/timeout failure.
  final int? status;

  /// The API's machine-readable code, e.g. `VALIDATION_ERROR`.
  final String? code;

  /// Groups the code, e.g. `validation`, `not_found`.
  final String? category;

  /// Per-field validation info: an object from the gateway, a list from the
  /// football service.
  final Object? details;

  /// Set on gateway errors only, not on football-service ones.
  final String? correlationId;

  final Map<String, String>? headers;

  /// The underlying error, for transport failures.
  final Object? cause;

  @override
  String toString() {
    final parts = <String>['$runtimeType: $message'];
    if (code != null) parts.add('code=$code');
    if (status != null) parts.add('status=$status');
    if (correlationId != null) parts.add('correlationId=$correlationId');
    return parts.join(' ');
  }
}

/// No HTTP response at all: DNS, TLS, socket.
class GoalApiConnectionException extends GoalApiException {
  GoalApiConnectionException(super.message, {super.cause});
}

/// Exceeded the configured timeout.
class GoalApiTimeoutException extends GoalApiConnectionException {
  GoalApiTimeoutException(super.message, {super.cause});
}

/// 400, 422.
class ValidationException extends GoalApiException {
  ValidationException(super.message,
      {super.status,
      super.code,
      super.category,
      super.details,
      super.correlationId,
      super.headers});
}

/// 401.
class AuthenticationException extends GoalApiException {
  AuthenticationException(super.message,
      {super.status,
      super.code,
      super.category,
      super.details,
      super.correlationId,
      super.headers});
}

/// 403.
class PermissionException extends GoalApiException {
  PermissionException(super.message,
      {super.status,
      super.code,
      super.category,
      super.details,
      super.correlationId,
      super.headers});
}

/// 402: endpoint not included in the current plan.
class PlanUpgradeRequiredException extends GoalApiException {
  PlanUpgradeRequiredException(super.message,
      {super.status,
      super.code,
      super.category,
      super.details,
      super.correlationId,
      super.headers});
}

/// 404.
class NotFoundException extends GoalApiException {
  NotFoundException(super.message,
      {super.status,
      super.code,
      super.category,
      super.details,
      super.correlationId,
      super.headers});
}

/// 409.
class ConflictException extends GoalApiException {
  ConflictException(super.message,
      {super.status,
      super.code,
      super.category,
      super.details,
      super.correlationId,
      super.headers});
}

/// 429.
class RateLimitException extends GoalApiException {
  RateLimitException(
    super.message, {
    super.status,
    super.code,
    super.category,
    super.details,
    super.correlationId,
    super.headers,
    this.retryAfter,
    this.limit,
    this.remaining,
    this.reset,
    this.rateLimitType,
  });

  /// Seconds to wait, from `Retry-After`.
  final int? retryAfter;
  final int? limit;
  final int? remaining;

  /// When the window rolls over, as unix seconds.
  final int? reset;

  /// `DAILY` or `MONTHLY`.
  final String? rateLimitType;
}

/// 503.
class ServiceUnavailableException extends GoalApiException {
  ServiceUnavailableException(super.message,
      {super.status,
      super.code,
      super.category,
      super.details,
      super.correlationId,
      super.headers});
}

/// 5xx.
class ServerException extends GoalApiException {
  ServerException(super.message,
      {super.status,
      super.code,
      super.category,
      super.details,
      super.correlationId,
      super.headers});
}

int? _intHeader(Map<String, String> headers, String name) {
  final raw = headers[name];
  if (raw == null || raw.isEmpty) return null;
  return int.tryParse(raw);
}

/// Maps a non-2xx response to an exception.
///
/// The API has two error shapes: the gateway sends `message`, the football service
/// sends `error`. [body] is null when the response was not JSON (nginx 502s are
/// HTML).
GoalApiException errorFromResponse(
  int status,
  Map<String, dynamic>? body,
  Map<String, String> headers,
) {
  final message =
      (body?['message'] ?? body?['error'] ?? 'HTTP $status').toString();
  final code = body?['code'] as String?;
  final category = body?['category'] as String?;
  final details = body?['details'];
  final correlationId = body?['correlationId'] as String?;

  switch (status) {
    case 400:
    case 422:
      return ValidationException(message,
          status: status,
          code: code,
          category: category,
          details: details,
          correlationId: correlationId,
          headers: headers);
    case 401:
      return AuthenticationException(message,
          status: status,
          code: code,
          category: category,
          details: details,
          correlationId: correlationId,
          headers: headers);
    case 402:
      return PlanUpgradeRequiredException(message,
          status: status,
          code: code,
          category: category,
          details: details,
          correlationId: correlationId,
          headers: headers);
    case 403:
      return PermissionException(message,
          status: status,
          code: code,
          category: category,
          details: details,
          correlationId: correlationId,
          headers: headers);
    case 404:
      return NotFoundException(message,
          status: status,
          code: code,
          category: category,
          details: details,
          correlationId: correlationId,
          headers: headers);
    case 409:
      return ConflictException(message,
          status: status,
          code: code,
          category: category,
          details: details,
          correlationId: correlationId,
          headers: headers);
    case 429:
      return RateLimitException(
        message,
        status: status,
        code: code,
        category: category,
        details: details,
        correlationId: correlationId,
        headers: headers,
        retryAfter: _intHeader(headers, 'retry-after'),
        limit: _intHeader(headers, 'x-ratelimit-limit'),
        remaining: _intHeader(headers, 'x-ratelimit-remaining'),
        reset: _intHeader(headers, 'x-ratelimit-reset'),
        rateLimitType: headers['x-ratelimit-type'],
      );
    case 503:
      return ServiceUnavailableException(message,
          status: status,
          code: code,
          category: category,
          details: details,
          correlationId: correlationId,
          headers: headers);
  }

  if (status >= 500) {
    return ServerException(message,
        status: status,
        code: code,
        category: category,
        details: details,
        correlationId: correlationId,
        headers: headers);
  }
  return GoalApiException(message,
      status: status,
      code: code,
      category: category,
      details: details,
      correlationId: correlationId,
      headers: headers);
}
