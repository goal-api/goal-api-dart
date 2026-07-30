// Runs against the real API. Skipped unless GOAL_API_KEY is set.
//
//   GOAL_API_KEY=... dart test
//
// Endpoint-by-endpoint coverage lives in ../tools/sweep.py. This checks the
// parts that are the SDK's job: auth, param encoding, envelope handling, pagination
// across real pages, error mapping and the quota snapshot.

import 'dart:io';

import 'package:goal_api/goal_api.dart';
import 'package:test/test.dart';

void main() {
  final apiKey = Platform.environment['GOAL_API_KEY'];
  final skip =
      (apiKey == null || apiKey.isEmpty) ? 'GOAL_API_KEY is not set' : null;

  late GoalApi goal;

  setUpAll(() {
    goal = GoalApi(
      apiKey: apiKey ?? 'unset',
      timeout: const Duration(seconds: 30),
    );
  });

  tearDownAll(() => goal.close());

  test('status.get returns the bare body', () async {
    final status = await goal.status.get();
    expect(status['status'], isA<String>());
    expect(status['components'], isA<List<dynamic>>());
    expect(status.containsKey('data'), isFalse,
        reason: '/public/* must not be wrapped in an envelope');
  }, skip: skip);

  test('coverageLeagues paginates with page/limit', () async {
    final page = await goal.status.coverageLeagues({'page': 1, 'limit': 5});
    expect(page['leagues'], isA<List<dynamic>>());
    expect((page['leagues'] as List).length, lessThanOrEqualTo(5));
    expect(page['total'], isA<int>());
    expect(page['pages'], isA<int>());
  }, skip: skip);

  test('leagues.list returns the envelope and honours limit', () async {
    final page = await goal.leagues.list({'isActive': true, 'limit': 3});
    expect(page['success'], isTrue);
    expect((page['data'] as List).length, lessThanOrEqualTo(3));
    expect((page['pagination'] as Map)['total'], isA<int>());
    expect(page['source'], anyOf('cache', 'database'));
  }, skip: skip);

  test('the quota snapshot is populated after an authenticated call', () async {
    await goal.leagues.list({'limit': 1});
    expect(goal.rateLimit.limit, isA<int>());
    expect(goal.rateLimit.remaining, lessThanOrEqualTo(goal.rateLimit.limit!));
    expect(goal.rateLimit.type, anyOf('DAILY', 'MONTHLY'));
  }, skip: skip);

  test('fixtures.live returns matches in play', () async {
    final page = await goal.fixtures.live();
    expect(page['success'], isTrue);
    expect(page['data'], isA<List<dynamic>>());
  }, skip: skip);

  test('a real league resolves through the nested endpoints', () async {
    final leagues = (await goal.leagues
        .list({'isActive': true, 'limit': 1}))['data'] as List;
    expect(leagues, isNotEmpty, reason: 'expected at least one active league');
    final leagueId = (leagues.first as Map)['id'] as String;

    expect(
        (await goal.leagues.teams(leagueId, {'limit': 5}))['success'], isTrue);
    expect((await goal.leagues.fixtures(leagueId, {'limit': 5}))['success'],
        isTrue);
  }, skip: skip);

  test('paginate walks real pages without repeating', () async {
    final seen = <String>[];
    await for (final row in goal.paginate((p) => goal.countries.list(p),
        pageSize: 20, maxItems: 45)) {
      seen.add((row as Map)['id'] as String);
    }
    expect(seen.length, greaterThan(20),
        reason: 'expected pagination to cross a page boundary');
    expect(seen.toSet().length, seen.length,
        reason: 'pagination returned duplicates');
  }, skip: skip);

  test('players.search accepts a query', () async {
    final page = await goal.players.search('silva', {'limit': 3});
    expect(page['success'], isTrue);
    expect((page['data'] as List).length, lessThanOrEqualTo(3));
  }, skip: skip);

  test('an unknown id throws NotFoundException', () async {
    await expectLater(
      goal.fixtures.get('definitely-not-a-real-id'),
      throwsA(isA<NotFoundException>()
          .having((e) => e.status, 'status', 404)
          .having((e) => e.code, 'code', 'FIXTURE_NOT_FOUND')
          // The service puts the text in `error`; the SDK normalises it to `message`.
          .having((e) => e.message, 'message', isNotEmpty)),
    );
  }, skip: skip);

  test('a bad enum throws ValidationException with details', () async {
    await expectLater(
      goal.players.top('not-a-real-stat'),
      throwsA(isA<ValidationException>()
          .having((e) => e.status, 'status', 400)
          .having((e) => e.code, 'code', 'VALIDATION_ERROR')
          .having((e) => e.details, 'details', isA<List<dynamic>>())),
    );
  }, skip: skip);

  test('a bad key throws AuthenticationException', () async {
    final bad = GoalApi(apiKey: 'gapi_not_a_real_key', maxRetries: 0);
    await expectLater(
      bad.leagues.list({'limit': 1}),
      throwsA(isA<AuthenticationException>()),
    );
    bad.close();
  }, skip: skip);
}
