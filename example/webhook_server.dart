// GOAL_WEBHOOK_SECRET=... dart run example/webhook_server.dart
//
// A receiver built on dart:io, no framework. The important part is that verification runs
// on the raw request bytes: decoding and re-encoding the body first changes the byte order
// and breaks the HMAC.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:goal_api/goal_api.dart';

Future<void> main() async {
  final secret = Platform.environment['GOAL_WEBHOOK_SECRET'];
  if (secret == null || secret.isEmpty) {
    stderr.writeln('GOAL_WEBHOOK_SECRET is not set.');
    exitCode = 2;
    return;
  }
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 3100;

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  print('listening on http://localhost:$port/goal-webhooks');
  print('events: ${WebhookEvent.all.join(', ')}');

  await for (final request in server) {
    if (request.method != 'POST' || request.uri.path != '/goal-webhooks') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }

    // Collect the raw bytes. Do not decode before verifying.
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
    }

    Map<String, dynamic> event;
    try {
      event = verifyWebhook(
        bytes,
        request.headers.value(signatureHeader),
        secret,
      );
    } on WebhookSignatureException catch (error) {
      stderr.writeln('rejected: ${error.message}');
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      continue;
    }

    final type = request.headers.value(eventHeader);
    print('$type  delivery=${request.headers.value(deliveryHeader)}');

    switch (type) {
      case WebhookEvent.goalScored:
        final home = (event['homeTeam'] as Map?)?['name'] ?? '?';
        final away = (event['awayTeam'] as Map?)?['name'] ?? '?';
        print('  $home ${event['homeScore']}-${event['awayScore']} $away');
      case WebhookEvent.matchFinished:
        print('  full time');
      default:
        print(
            '  ${event.toString().substring(0, event.toString().length.clamp(0, 120))}');
    }

    // Ack fast. Retries are ~1m, 5m, 25m, 2h, 10h.
    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
  }
}
