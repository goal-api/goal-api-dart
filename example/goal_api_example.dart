// GOAL_API_KEY=... dart run example/goal_api_example.dart
//
// The status section works without a key.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:goal_api/goal_api.dart';

Future<void> main() async {
  final apiKey = Platform.environment['GOAL_API_KEY'];
  final goal = GoalApi(apiKey: apiKey ?? 'unset');

  try {
    // --- public status: no API key required ---------------------------------
    // Note: /public/* returns a bare object, not the {success, data} envelope.
    final status = await goal.status.get();
    print('Platform: ${status['status']}');
    for (final component in (status['components'] as List? ?? [])) {
      final row = component as Map<String, dynamic>;
      final uptime = (row['uptime'] as Map?)?['24h'];
      print('  ${row['name'].toString().padRight(28)} '
          '${row['status'].toString().padRight(14)} 24h $uptime%');
    }

    if (apiKey == null) {
      print('\nSet GOAL_API_KEY to run the authenticated examples.');
      return;
    }

    // --- live matches -------------------------------------------------------
    final live = (await goal.fixtures.live())['data'] as List;
    print('\n${live.length} match(es) in play');
    for (final match in live.take(5)) {
      final row = match as Map<String, dynamic>;
      final home = (row['homeTeam'] as Map?)?['name'] ?? '?';
      final away = (row['awayTeam'] as Map?)?['name'] ?? '?';
      print('  $home ${row['homeScore'] ?? 0}-${row['awayScore'] ?? 0} $away '
          '(${row['minute'] ?? '?'}\')');
    }

    // --- pick a league and read its table -----------------------------------
    final leagues = (await goal.leagues
        .list({'isActive': true, 'limit': 1}))['data'] as List;
    if (leagues.isEmpty) return;
    final league = leagues.first as Map<String, dynamic>;

    print('\nStandings: ${league['name']}');
    final table =
        (await goal.leagues.standings(league['id'] as Object))['data'];
    if (table is List) {
      for (final entry in table.take(5)) {
        final row = entry as Map<String, dynamic>;
        final name = (row['team'] as Map?)?['name'] ?? row['teamName'] ?? '?';
        print('  ${row['position'].toString().padLeft(2)}. '
            '${name.toString().padRight(24)} ${row['points']} pts');
      }
    }

    print('\nTop scorers: ${league['name']}');
    final scorers = (await goal.leagues
        .topScorers(league['id'] as Object, {'limit': 5}))['data'];
    if (scorers is List) {
      for (final entry in scorers) {
        final row = entry as Map<String, dynamic>;
        final name = (row['player'] as Map?)?['name'] ?? row['name'] ?? '?';
        print('  ${name.toString().padRight(24)} ${row['goals'] ?? 0}');
      }
    }

    // --- pagination across every team in the league --------------------------
    final teams = await goal
        .collect((page) => goal.leagues.teams(league['id'] as Object, page));
    print('\n${teams.length} teams in ${league['name']}');

    print('\nQuota: ${goal.rateLimit}');
  } on RateLimitException catch (error) {
    stderr.writeln(
        'Rate limited (${error.rateLimitType}). Retry in ${error.retryAfter}s.');
    exitCode = 1;
  } on GoalApiException catch (error) {
    stderr.writeln(
        '${error.code ?? 'ERROR'}: ${error.message} [${error.correlationId}]');
    exitCode = 1;
  } finally {
    goal.close();
  }
}
