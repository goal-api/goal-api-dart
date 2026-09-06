// Reconnect behaviour against a local server that refuses the upgrade, which is
// what the production rate limiter does under load (429 on `GET /ws`).
//
// These need no API key and no network: they stand up an HttpServer on
// localhost and count the connection attempts it receives.
//
// The bug they cover: a refused upgrade fails inside connect()'s own try/catch,
// before the stream — and therefore before onDone/_handleDone — exists. The
// backoff hung entirely off _handleDone, so it was unreachable on exactly the
// path that retries hardest, and every caller-driven retry restarted from
// _attempt 0 with no delay. Against the old code the first test below sees a
// single attempt and fails.

import 'dart:async';
import 'dart:io';

import 'package:goal_api/goal_api.dart';
import 'package:test/test.dart';

/// A server that answers every request with [status] and records the arrivals.
Future<(HttpServer, List<DateTime>)> _refusingServer({int status = 429}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final hits = <DateTime>[];
  server.listen((request) async {
    hits.add(DateTime.now());
    request.response.statusCode = status;
    request.response.headers.set('Retry-After', '5');
    await request.response.close();
  });
  return (server, hits);
}

GoalApi _clientFor(HttpServer server) => GoalApi(
      apiKey: 'test-key',
      baseUrl: 'http://${server.address.address}:${server.port}',
    );

void main() {
  group('LiveClient reconnect after a refused upgrade', () {
    test('retries at all — the refusal path reaches the backoff', () async {
      final (server, hits) = await _refusingServer();
      final goal = _clientFor(server);
      final live =
          goal.live(url: 'ws://${server.address.address}:${server.port}/ws');

      await expectLater(
          live.connect(), throwsA(isA<GoalApiConnectionException>()));
      expect(hits, hasLength(1), reason: 'the initial attempt');

      // First backoff step is 1s jittered to 0.5-1.0s, second is 2s jittered to
      // 1.0-2.0s, so 3.5s is comfortably enough for at least one retry.
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      await live.close();

      expect(hits.length, greaterThan(1),
          reason: 'a 429 must schedule a retry, not give up silently');

      goal.close();
      await server.close(force: true);
    });

    test('retries are spaced by backoff, not fired in a loop', () async {
      final (server, hits) = await _refusingServer();
      final goal = _clientFor(server);
      final live =
          goal.live(url: 'ws://${server.address.address}:${server.port}/ws');

      await expectLater(
          live.connect(), throwsA(isA<GoalApiConnectionException>()));
      await Future<void>.delayed(const Duration(seconds: 5));
      await live.close();

      // 1s + 2s + 4s (each jittered down to as little as half) fits at most
      // about six attempts into five seconds. The bug produced thousands.
      expect(hits.length, lessThan(8),
          reason: 'attempts must back off; got ${hits.length} in 5s');

      // And each gap should be growing rather than flat.
      final gaps = <int>[];
      for (var i = 1; i < hits.length; i++) {
        gaps.add(hits[i].difference(hits[i - 1]).inMilliseconds);
      }
      if (gaps.length >= 2) {
        expect(gaps.last, greaterThan(gaps.first),
            reason: 'backoff should widen: $gaps');
      }

      goal.close();
      await server.close(force: true);
    });

    test('only one retry chain is ever pending', () async {
      final (server, hits) = await _refusingServer();
      final goal = _clientFor(server);
      final live =
          goal.live(url: 'ws://${server.address.address}:${server.port}/ws');

      // Three concurrent callers, as a rebuilding UI would produce. Each failure
      // schedules, but the guard must collapse them into a single chain.
      await Future.wait<void>([
        live.connect().then((_) {}, onError: (_) {}),
        live.connect().then((_) {}, onError: (_) {}),
        live.connect().then((_) {}, onError: (_) {}),
      ]);
      final immediate = hits.length;

      await Future<void>.delayed(const Duration(milliseconds: 2500));
      await live.close();

      expect(hits.length - immediate, lessThan(4),
          reason: 'three callers must not open three doubling retry chains');

      goal.close();
      await server.close(force: true);
    });

    test('close() cancels a pending retry', () async {
      final (server, hits) = await _refusingServer();
      final goal = _clientFor(server);
      final live =
          goal.live(url: 'ws://${server.address.address}:${server.port}/ws');

      await expectLater(
          live.connect(), throwsA(isA<GoalApiConnectionException>()));
      await live.close();
      final atClose = hits.length;

      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(hits.length, atClose,
          reason: 'a retry armed before close() must not outlive it');

      goal.close();
      await server.close(force: true);
    });

    test('autoReconnect: false still means no retry', () async {
      final (server, hits) = await _refusingServer();
      final goal = _clientFor(server);
      final live = goal.live(
        url: 'ws://${server.address.address}:${server.port}/ws',
        autoReconnect: false,
      );

      await expectLater(
          live.connect(), throwsA(isA<GoalApiConnectionException>()));
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      await live.close();

      expect(hits, hasLength(1),
          reason: 'opting out of reconnection must still opt out');

      goal.close();
      await server.close(force: true);
    });
  });
}
