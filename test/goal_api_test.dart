// Client tests against a MockClient. No network.
//
// Covers request shape (URL, headers, param encoding), error mapping, retries,
// pagination and webhook signing.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:goal_api/goal_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Records requests and replays a queue of responses.
class Recorder {
  Recorder(this._responses);

  final List<http.Response> _responses;
  final List<http.Request> seen = [];

  MockClient get client => MockClient((request) async {
        seen.add(request);
        final index = seen.length - 1;
        return _responses[
            index < _responses.length ? index : _responses.length - 1];
      });
}

http.Response jsonResponse(
  Object body, {
  int status = 200,
  Map<String, String> headers = const {},
}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...headers},
    );

GoalApi clientFor(
  http.Client httpClient, {
  int maxRetries = 0,
}) =>
    GoalApi(apiKey: 'test-key', httpClient: httpClient, maxRetries: maxRetries);

void main() {
  group('request shape', () {
    test('rejects an empty API key', () {
      expect(() => GoalApi(apiKey: ''), throwsA(isA<ArgumentError>()));
    });

    test('sends the bearer header to the right URL', () async {
      final recorder = Recorder([
        jsonResponse({
          'success': true,
          'data': [
            {'id': 'x'}
          ]
        })
      ]);
      final goal = clientFor(recorder.client);

      final page = await goal.fixtures.live();
      expect((page['data'] as List).length, 1);

      final request = recorder.seen.first;
      expect(
          request.url.toString(), 'https://api.goal-api.com/v1/fixtures/live');
      expect(request.headers['Authorization'], 'Bearer test-key');
      expect(request.headers['User-Agent'], startsWith('goal-api-dart/'));
      goal.close();
    });

    test('news.list hits /news and forwards its filters', () async {
      final recorder = Recorder([
        jsonResponse({'success': true, 'data': <Object>[]})
      ]);
      final goal = clientFor(recorder.client);

      // The ids are the news source's, not ours, so they reach the wire untouched.
      await goal.news.list({
        'leagueId': '3',
        'teamId': '150',
        'from': '2026-09-01',
        'limit': 5,
      });

      final url = recorder.seen.first.url;
      expect(url.path, '/v1/news');
      expect(url.queryParameters['leagueId'], '3');
      expect(url.queryParameters['teamId'], '150');
      expect(url.queryParameters['from'], '2026-09-01');
      expect(url.queryParameters['limit'], '5');
      goal.close();
    });

    test('drops nulls and lowercases booleans', () async {
      final recorder = Recorder([
        jsonResponse({'success': true, 'data': <Object>[]})
      ]);
      final goal = clientFor(recorder.client);

      await goal.fixtures.list({
        'leagueId': 'L1',
        'status': null,
        'teamId': null,
        'offset': 0,
        'live': false,
      });

      final query = recorder.seen.first.url.queryParameters;
      expect(query['leagueId'], 'L1');
      expect(query['offset'], '0');
      expect(query['live'], 'false'); // the API validates the literal strings
      expect(query.containsKey('status'), isFalse);
      expect(query.containsKey('teamId'), isFalse);
      goal.close();
    });

    test('encodes path segments', () async {
      final recorder = Recorder([
        jsonResponse({'success': true, 'data': <Object>[]})
      ]);
      final goal = clientFor(recorder.client);

      await goal.coaches.byCountry('Trinidad And Tobago');
      expect(recorder.seen.first.url.path,
          '/v1/coaches/country/Trinidad%20And%20Tobago');
      goal.close();
    });

    test('a slash in an id cannot escape its segment', () async {
      final recorder = Recorder([
        jsonResponse({'success': true, 'data': null})
      ]);
      final goal = clientFor(recorder.client);

      await goal.fixtures.get('../../admin');
      expect(recorder.seen.first.url.path, '/v1/fixtures/..%2F..%2Fadmin');
      goal.close();
    });

    test('an empty path segment is rejected before the request', () {
      final recorder = Recorder([jsonResponse({})]);
      final goal = clientFor(recorder.client);

      expect(() => goal.fixtures.get(''), throwsA(isA<ArgumentError>()));
      expect(recorder.seen, isEmpty);
      goal.close();
    });

    test('compare joins ids with commas', () async {
      final recorder = Recorder([
        jsonResponse({'success': true, 'data': <Object>[]})
      ]);
      final goal = clientFor(recorder.client);

      await goal.players.compare(['p1', 'p2', 'p3']);
      expect(recorder.seen.first.url.queryParameters['ids'], 'p1,p2,p3');
      goal.close();
    });

    test('search puts q in the query', () async {
      final recorder = Recorder([
        jsonResponse({'success': true, 'data': <Object>[]})
      ]);
      final goal = clientFor(recorder.client);

      await goal.players.search('haaland', {'limit': 5});
      final query = recorder.seen.first.url.queryParameters;
      expect(query['q'], 'haaland');
      expect(query['limit'], '5');
      goal.close();
    });
  });

  group('public endpoints', () {
    test('return the bare body, not an envelope', () async {
      final recorder = Recorder([
        jsonResponse({
          'status': 'operational',
          'components': [
            {'name': 'API', 'status': 'operational'}
          ]
        })
      ]);
      final goal = clientFor(recorder.client);

      final status = await goal.status.get();
      expect(status['status'], 'operational');
      expect((status['components'] as List).length, 1);
      expect(status.containsKey('data'), isFalse);
      goal.close();
    });

    test('coverageLeagues paginates with page, not offset', () async {
      final recorder = Recorder([
        jsonResponse({
          'leagues': <Object>[],
          'total': 0,
          'page': 2,
          'limit': 50,
          'pages': 1
        })
      ]);
      final goal = clientFor(recorder.client);

      await goal.status
          .coverageLeagues({'page': 2, 'limit': 50, 'country': 'England'});
      final query = recorder.seen.first.url.queryParameters;
      expect(query['page'], '2');
      expect(query['country'], 'England');
      expect(query.containsKey('offset'), isFalse);
      goal.close();
    });
  });

  group('errors', () {
    test('maps 400 to ValidationException and keeps the envelope fields',
        () async {
      final recorder = Recorder([
        jsonResponse({
          'success': false,
          'message': 'League ID is required',
          'code': 'VALIDATION_ERROR',
          'category': 'validation',
          'details': {'field': 'id'},
          'correlationId': 'abc-123',
        }, status: 400)
      ]);
      final goal = clientFor(recorder.client);

      await expectLater(
        goal.leagues.get('bad'),
        throwsA(
          isA<ValidationException>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.code, 'code', 'VALIDATION_ERROR')
              .having((e) => e.correlationId, 'correlationId', 'abc-123')
              .having((e) => e.details, 'details', {'field': 'id'}),
        ),
      );
      goal.close();
    });

    test('maps status codes to the right exception types', () async {
      final expected = <int, Matcher>{
        401: isA<AuthenticationException>(),
        402: isA<PlanUpgradeRequiredException>(),
        403: isA<PermissionException>(),
        404: isA<NotFoundException>(),
        409: isA<ConflictException>(),
        422: isA<ValidationException>(),
        429: isA<RateLimitException>(),
        500: isA<ServerException>(),
        503: isA<ServiceUnavailableException>(),
      };

      for (final entry in expected.entries) {
        final recorder = Recorder([
          jsonResponse({'success': false, 'message': 'nope'}, status: entry.key)
        ]);
        final goal = clientFor(recorder.client);
        await expectLater(goal.fixtures.live(), throwsA(entry.value),
            reason: 'status ${entry.key}');
        goal.close();
      }
    });

    test('429 carries retryAfter and the quota headers', () async {
      final recorder = Recorder([
        jsonResponse(
          {
            'success': false,
            'message': 'Too many requests',
            'code': 'RATE_LIMIT_EXCEEDED'
          },
          status: 429,
          headers: {
            'retry-after': '42',
            'x-ratelimit-limit': '1000',
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset': '1800000000',
            'x-ratelimit-type': 'DAILY',
          },
        )
      ]);
      final goal = clientFor(recorder.client);

      await expectLater(
        goal.fixtures.live(),
        throwsA(isA<RateLimitException>()
            .having((e) => e.retryAfter, 'retryAfter', 42)
            .having((e) => e.limit, 'limit', 1000)
            .having((e) => e.rateLimitType, 'rateLimitType', 'DAILY')),
      );
      goal.close();
    });

    test('an HTML error body still produces a useful message', () async {
      final goal = clientFor(MockClient((_) async => http.Response(
            '<html><body>502 Bad Gateway</body></html>',
            502,
            headers: {'content-type': 'text/html'},
          )));

      await expectLater(
        goal.fixtures.live(),
        throwsA(isA<ServerException>()
            .having((e) => e.message, 'message', contains('502 Bad Gateway'))),
      );
      goal.close();
    });

    test('records the rate-limit snapshot from a success', () async {
      final recorder = Recorder([
        jsonResponse({
          'success': true,
          'data': <Object>[]
        }, headers: {
          'x-ratelimit-limit': '10000',
          'x-ratelimit-remaining': '9997',
          'x-ratelimit-reset': '1800000000',
          'x-ratelimit-type': 'MONTHLY',
        })
      ]);
      final goal = clientFor(recorder.client);

      await goal.results.today();
      expect(goal.rateLimit.limit, 10000);
      expect(goal.rateLimit.remaining, 9997);
      expect(goal.rateLimit.type, 'MONTHLY');
      goal.close();
    });

    test('a public response without quota headers leaves the snapshot alone',
        () async {
      final recorder = Recorder([
        jsonResponse({'status': 'operational'})
      ]);
      final goal = clientFor(recorder.client);

      await goal.status.get();
      expect(goal.rateLimit.limit, isNull);
      goal.close();
    });
  });

  group('retries', () {
    test('retries a 503 then succeeds', () async {
      var calls = 0;
      final goal = clientFor(
        MockClient((_) async {
          calls++;
          return calls == 1
              ? jsonResponse({'success': false, 'message': 'down'}, status: 503)
              : jsonResponse({
                  'success': true,
                  'data': <Object>[1]
                });
        }),
        maxRetries: 2,
      );

      final page = await goal.fixtures.live();
      expect(calls, 2);
      expect(page['data'], [1]);
      goal.close();
    });

    test('does not retry a 400', () async {
      var calls = 0;
      final goal = clientFor(
        MockClient((_) async {
          calls++;
          return jsonResponse({'success': false, 'message': 'bad'},
              status: 400);
        }),
        maxRetries: 3,
      );

      await expectLater(
          goal.fixtures.live(), throwsA(isA<ValidationException>()));
      expect(calls, 1);
      goal.close();
    });
  });

  group('pagination', () {
    test('walks pages and stops on hasMore=false', () async {
      final recorder = Recorder([
        jsonResponse({
          'success': true,
          'data': [
            {'id': 1},
            {'id': 2}
          ],
          'pagination': {'total': 3, 'limit': 2, 'offset': 0, 'hasMore': true},
        }),
        jsonResponse({
          'success': true,
          'data': [
            {'id': 3}
          ],
          'pagination': {'total': 3, 'limit': 2, 'offset': 2, 'hasMore': false},
        }),
      ]);
      final goal = clientFor(recorder.client);

      final items =
          await goal.collect((page) => goal.teams.list(page), pageSize: 2);
      expect(items.map((t) => (t as Map)['id']).toList(), [1, 2, 3]);
      expect(recorder.seen[1].url.queryParameters['offset'], '2');
      goal.close();
    });

    test('honours maxItems without fetching further pages', () async {
      final recorder = Recorder([
        jsonResponse({
          'success': true,
          'data': [
            {'id': 1},
            {'id': 2}
          ],
          'pagination': {'total': 99, 'limit': 2, 'offset': 0, 'hasMore': true},
        })
      ]);
      final goal = clientFor(recorder.client);

      final items = await goal.collect((page) => goal.teams.list(page),
          pageSize: 2, maxItems: 2);
      expect(items.length, 2);
      expect(recorder.seen.length, 1);
      goal.close();
    });

    test('stops on a short page when pagination is absent', () async {
      final recorder = Recorder([
        jsonResponse({
          'success': true,
          'data': [
            {'id': 1}
          ]
        })
      ]);
      final goal = clientFor(recorder.client);

      final items =
          await goal.collect((page) => goal.videos.list(page), pageSize: 10);
      expect(items.length, 1);
      expect(recorder.seen.length, 1);
      goal.close();
    });
  });

  group('webhooks', () {
    const secret = 'whsec_test';

    String sign(String body, int timestamp) {
      final digest = Hmac(sha256, utf8.encode(secret))
          .convert(utf8.encode('$timestamp.$body'));
      return 't=$timestamp,v1=$digest';
    }

    int now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

    test('accepts a correctly signed payload', () {
      const body = '{"event":"goal.scored","matchId":"m1"}';
      final event = verifyWebhook(body, sign(body, now()), secret);
      expect(event['event'], 'goal.scored');
      expect(event['matchId'], 'm1');
    });

    test('accepts raw bytes', () {
      const body = '{"event":"match.started"}';
      final event = verifyWebhook(utf8.encode(body), sign(body, now()), secret);
      expect(event['event'], 'match.started');
    });

    test('rejects a tampered body', () {
      final signature = sign('{"homeScore":1}', now());
      expect(
        () => verifyWebhook('{"homeScore":9}', signature, secret),
        throwsA(isA<WebhookSignatureException>()),
      );
    });

    test('rejects a replayed timestamp, and allows opting out', () {
      const body = '{"event":"goal.scored"}';
      final old = now() - 4000;
      expect(
        () => verifyWebhook(body, sign(body, old), secret),
        throwsA(isA<WebhookSignatureException>()),
      );
      expect(
        verifyWebhook(body, sign(body, old), secret,
            tolerance: Duration.zero)['event'],
        'goal.scored',
      );
    });

    test('rejects malformed and missing headers', () {
      expect(() => verifyWebhook('{}', 'garbage', secret),
          throwsA(isA<WebhookSignatureException>()));
      expect(() => verifyWebhook('{}', null, secret),
          throwsA(isA<WebhookSignatureException>()));
    });

    test('rejects a wrong secret', () {
      const body = '{"a":1}';
      expect(
        () => verifyWebhook(body, sign(body, now()), 'whsec_other'),
        throwsA(isA<WebhookSignatureException>()),
      );
    });
  });
}
