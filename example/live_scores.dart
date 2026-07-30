// GOAL_API_KEY=... dart run example/live_scores.dart
//
// Connects to the live socket, subscribes to whatever is in play, and prints every frame
// the server sends. Exits non-zero if nothing arrives, so it works as a smoke test.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:goal_api/goal_api.dart';

Future<void> main() async {
  final apiKey = Platform.environment['GOAL_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('GOAL_API_KEY is not set.');
    exitCode = 2;
    return;
  }
  final listenSeconds =
      int.tryParse(Platform.environment['LISTEN_SECONDS'] ?? '') ?? 30;

  final goal = GoalApi(apiKey: apiKey);
  final live = (await goal.fixtures.live())['data'] as List;
  print('${live.length} match(es) in play');
  for (final match in live.take(5)) {
    final row = match as Map<String, dynamic>;
    final home = (row['homeTeam'] as Map?)?['name'] ?? '?';
    final away = (row['awayTeam'] as Map?)?['name'] ?? '?';
    print('  ${row['id']}  $home v $away');
  }

  final seen = <String, int>{};
  final feed = goal.live();

  feed.messages.listen((message) {
    final type = message['type'] as String? ?? '?';
    seen[type] = (seen[type] ?? 0) + 1;

    switch (type) {
      case LiveMessageType.authSuccess:
        final data = message['data'] as Map<String, dynamic>? ?? {};
        print('\nauthenticated: plan=${data['plan']} '
            'maxSubscriptions=${data['maxSubscriptions']}');
        if (data['maxSubscriptions'] == 0) {
          print('  this plan allows 0 concurrent subscriptions, '
              'so no match_update can arrive');
        }
      case LiveMessageType.subscribeResponse:
        if (message['success'] == true) {
          print('  subscribed: ${message['data']}');
        } else {
          final error = message['error'] as Map<String, dynamic>? ?? {};
          print('  subscribe rejected: ${error['code']} ${error['message']}');
        }
      case LiveMessageType.matchUpdate:
        final data = message['data'] as Map<String, dynamic>? ?? {};
        final home = (data['homeTeam'] as Map?)?['name'] ?? '?';
        final away = (data['awayTeam'] as Map?)?['name'] ?? '?';
        print(
            '  UPDATE  $home ${data['homeScore']}-${data['awayScore']} $away  '
            "${data['minute']}'");
      case LiveMessageType.pong:
        print('  pong');
    }
  }, onError: (Object error) => print('  error: $error'));

  try {
    await feed.connect();
  } on GoalApiException catch (error) {
    stderr.writeln('\nconnect failed: ${error.message}');
    goal.close();
    exitCode = 1;
    return;
  }

  for (final match in live.take(5)) {
    feed.subscribe((match as Map<String, dynamic>)['id'] as String);
  }
  feed.listSubscriptions();
  feed.ping();

  print('\nlistening for ${listenSeconds}s ...');
  await Future<void>.delayed(Duration(seconds: listenSeconds));
  await feed.close();
  goal.close();

  print('\nreceived: $seen');
  if (!seen.containsKey(LiveMessageType.authSuccess)) {
    stderr.writeln('nothing was received from the socket');
    exitCode = 1;
  }
}
