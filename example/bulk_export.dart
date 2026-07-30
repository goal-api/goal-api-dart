// GOAL_API_KEY=... dart run example/bulk_export.dart > countries.csv
//
// Walks every page of a collection and streams it out as CSV. Shows paginate() doing the
// page walking, and that limit ceilings differ per endpoint.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:goal_api/goal_api.dart';

String csv(Object? value) {
  final text = value?.toString() ?? '';
  return RegExp('[",\n]').hasMatch(text)
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}

Future<void> main() async {
  final apiKey = Platform.environment['GOAL_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('GOAL_API_KEY is not set.');
    exitCode = 2;
    return;
  }

  final goal = GoalApi(apiKey: apiKey);
  stdout.writeln('id,name,code,isActive');

  var rows = 0;
  // /countries accepts limit up to 500; most endpoints cap at 100.
  await for (final row
      in goal.paginate((p) => goal.countries.list(p), pageSize: 500)) {
    final country = row as Map<String, dynamic>;
    stdout.writeln([
      csv(country['id']),
      csv(country['name']),
      csv(country['code']),
      csv(country['isActive']),
    ].join(','));
    rows++;
  }

  stderr.writeln('\n$rows countries exported');
  stderr.writeln(
      'quota: ${goal.rateLimit.remaining}/${goal.rateLimit.limit} left');
  goal.close();
}
