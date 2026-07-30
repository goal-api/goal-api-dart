import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'errors.dart';

/// Webhook event names.
abstract final class WebhookEvent {
  static const String matchStarted = 'match.started';
  static const String matchFinished = 'match.finished';
  static const String goalScored = 'goal.scored';
  static const String scoreChanged = 'score.changed';
  static const String matchStatusChanged = 'match.status_changed';

  static const List<String> all = [
    matchStarted,
    matchFinished,
    goalScored,
    scoreChanged,
    matchStatusChanged,
  ];
}

/// Headers on an inbound webhook delivery.
const String signatureHeader = 'x-goal-signature';
const String eventHeader = 'x-goal-event';
const String deliveryHeader = 'x-goal-delivery';

/// Missing, malformed, wrong, or too old.
class WebhookSignatureException extends GoalApiException {
  WebhookSignatureException(super.message);
}

/// Verifies an inbound webhook and returns the parsed event.
///
/// [payload] must be the raw body. Re-encoding a decoded map reorders keys and
/// changes whitespace, which breaks the HMAC.
///
/// ```dart
/// final event = verifyWebhook(
///   request.bodyBytes,
///   request.headers['x-goal-signature'],
///   Platform.environment['GOAL_WEBHOOK_SECRET']!,
/// );
/// ```
///
/// Throws [WebhookSignatureException] on a bad signature, or a timestamp older
/// than [tolerance] (replay protection). [Duration.zero] disables that check --
/// only sensible if you dedupe on `X-Goal-Delivery` yourself.
Map<String, dynamic> verifyWebhook(
  Object payload,
  String? signatureHeaderValue,
  String secret, {
  Duration tolerance = const Duration(minutes: 5),
}) {
  if (secret.isEmpty) {
    throw WebhookSignatureException('Webhook secret is required');
  }
  if (signatureHeaderValue == null || signatureHeaderValue.isEmpty) {
    throw WebhookSignatureException('Missing X-Goal-Signature header');
  }

  final List<int> bytes;
  if (payload is String) {
    bytes = utf8.encode(payload);
  } else if (payload is List<int>) {
    bytes = payload;
  } else {
    throw ArgumentError.value(
        payload, 'payload', 'must be a String or List<int>');
  }

  final (timestamp, signature) = _parseSignatureHeader(signatureHeaderValue);

  final hmac = Hmac(sha256, utf8.encode(secret));
  final expected =
      hmac.convert([...utf8.encode('$timestamp.'), ...bytes]).toString();

  if (!_constantTimeEquals(expected, signature)) {
    throw WebhookSignatureException('Webhook signature does not match');
  }

  if (tolerance > Duration.zero) {
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(timestamp * 1000))
        .abs();
    if (age > tolerance) {
      throw WebhookSignatureException(
          'Webhook timestamp is ${age.inSeconds}s old, outside the ${tolerance.inSeconds}s tolerance');
    }
  }

  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw WebhookSignatureException('Webhook body is not a JSON object');
    }
    return decoded;
  } on FormatException {
    throw WebhookSignatureException('Webhook body is not valid JSON');
  }
}

(int, String) _parseSignatureHeader(String header) {
  int? timestamp;
  String? signature;

  for (final part in header.split(',')) {
    final index = part.indexOf('=');
    if (index < 0) continue;
    final key = part.substring(0, index).trim();
    final value = part.substring(index + 1).trim();
    if (key == 't') {
      timestamp = int.tryParse(value);
    } else if (key == 'v1') {
      signature = value;
    }
  }

  if (timestamp == null || signature == null || signature.isEmpty) {
    throw WebhookSignatureException(
        'Malformed X-Goal-Signature header: $header');
  }
  return (timestamp, signature);
}

/// Constant-time hex digest comparison.
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
