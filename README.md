# goal_api

Dart SDK for the [GOAL API](https://goal-api.com): football fixtures, live scores,
standings, player stats, odds and live WebSocket updates.

Works in Dart VM, server-side Dart and Flutter (iOS, Android, web, desktop).

```yaml
dependencies:
  goal_api: ^1.0.0
```

## Quick start

```dart
import 'package:goal_api/goal_api.dart';

final goal = GoalApi(apiKey: 'your-key');

final page = await goal.fixtures.live();
for (final match in page['data'] as List) {
  final row = match as Map<String, dynamic>;
  print('${row['homeTeam']['name']} ${row['homeScore']}-${row['awayScore']}');
}

goal.close();
```

Get a key at [goal-api.com/signup](https://goal-api.com/signup).

> **Flutter apps:** an API key shipped inside an app binary is a public key. Proxy
> through your own backend for anything user-facing.

Share one `GoalApi`: the underlying `http.Client` pools connections and the rate-limit
snapshot is per-instance. Call `close()` when done.

## Client options

```dart
final goal = GoalApi(
  apiKey: apiKey,
  baseUrl: 'https://api.goal-api.com/v1',      // default
  timeout: const Duration(seconds: 30),        // per attempt
  maxRetries: 2,                               // 429 + 5xx + network errors
  headers: {'X-My-App': 'scoreboard'},
  httpClient: myInstrumentedClient,            // optional
);
```

Retries use exponential backoff with full jitter and always honour a server-sent
`Retry-After`.

## Endpoints

Grouped by resource. Params are a plain `Map<String, dynamic>`; nulls are dropped, so you
can build one unconditionally. Full reference in [`ENDPOINTS.md`](ENDPOINTS.md).

```dart
await goal.status.get();                                  // no API key needed
await goal.countries.list({'search': 'spa'});
await goal.leagues.list({'isActive': true, 'limit': 100});
await goal.leagues.standings(leagueId);
await goal.leagues.topScorers(leagueId, {'limit': 10});
await goal.teams.get(teamId, {'includePlayers': true});
await goal.teams.statistics(teamId, {'season': '2025-2026'});
await goal.fixtures.list({'from': '2026-08-01', 'to': '2026-08-07', 'status': 'SCHEDULED'});
await goal.fixtures.byDate('2026-08-15', {'leagueId': leagueId});
await goal.fixtures.lineups(fixtureId);
await goal.fixtures.statistics(fixtureId, {'half': '1half'});
await goal.standings.form(leagueId);
await goal.players.search('haaland', {'limit': 5});
await goal.players.compare([playerA, playerB]);
await goal.players.top('goals', {'limit': 20});
await goal.coaches.byTeam(teamId);
await goal.h2h.stats(teamA, teamB);
await goal.results.today();
await goal.videos.recent({'leagueId': leagueId, 'limit': 10});
await goal.odds.list({'bookmaker': 'bet365'});
await goal.predictions.list({'matchId': matchId});
```

Enum values are available as `matchStatuses`, `playerTypes`, `playerStats`, `halves`.

Every method returns the raw decoded envelope, so `pagination` and `source` stay reachable:

```dart
final page = await goal.teams.list({'leagueId': leagueId, 'limit': 50});
page['data'];                   // List
page['pagination']['hasMore'];  // bool
page['source'];                 // 'cache' | 'database'
```

### One exception: `goal.status.*`

The five `/public/*` endpoints don't use the `{success, data}` envelope. They return bare
objects, so read them directly with no `['data']`:

```dart
final status = await goal.status.get();
status['status'];      // 'operational'
status['components'];  // List of {name, status, uptime}
```

They also paginate with `page`/`limit` instead of `limit`/`offset`, so `paginate()` does
not apply to `coverageLeagues`.

## Pagination

`paginate` returns a `Stream`; `collect` gives you a list:

```dart
await for (final team in goal.paginate((p) => goal.leagues.teams(leagueId, p))) {
  print((team as Map)['name']);
}

// /results accepts limit up to 500:
final recent = await goal.collect(
  (p) => goal.results.list({'leagueId': leagueId, ...p}),
  pageSize: 500,
  maxItems: 500,
);
```

Default `pageSize` is 100, the limit ceiling on most endpoints.

## Errors

Everything thrown is a `GoalApiException`. Branch only where you'd actually behave
differently:

```dart
try {
  final fixture = await goal.fixtures.get(fixtureId);
} on NotFoundException {
  return null;
} on RateLimitException catch (error) {
  print('Quota exhausted (${error.rateLimitType}), retry in ${error.retryAfter}s');
  rethrow;
} on ValidationException catch (error) {
  print(error.details);   // which field the server rejected
  rethrow;
} on GoalApiException catch (error) {
  print('${error.code} ${error.correlationId}');
  rethrow;
}
```

Types: `ValidationException`, `AuthenticationException`, `PermissionException`,
`PlanUpgradeRequiredException`, `NotFoundException`, `ConflictException`,
`RateLimitException`, `ServiceUnavailableException`, `ServerException`,
`GoalApiConnectionException`, `GoalApiTimeoutException`.

### Two error shapes

The API answers with one of two bodies, and the SDK normalises both:

| | Gateway (auth, routing, rate limits) | Football service (most endpoints) |
|---|---|---|
| text | `message` | `error` |
| `code` | yes | yes |
| `category` | yes | no |
| `correlationId` | yes | **no** |
| `details` | object | array, on validation errors |

So `error.message` and `error.code` are always populated, and `error.correlationId` is
only set on gateway errors. Quote it in a support ticket when you have it.

### Rate limits

```dart
await goal.fixtures.live();
goal.rateLimit.remaining;   // int?
goal.rateLimit.reset;       // unix seconds
goal.rateLimit.type;        // 'DAILY' | 'MONTHLY'
```

## Live WebSocket updates

```dart
final live = goal.live();

live.on(LiveMessageType.matchUpdate).listen((message) => print(message['data']));
live.messages.handleError((Object error) => print('live error: $error'));

await live.connect();
live.subscribe(fixtureId);

// later
await live.close();
```

- **Native / server Dart**: authenticates the handshake with the `Authorization` header,
  so no token round trip.
- **Flutter Web**: browsers cannot set headers on a WebSocket, so pass
  `goal.live(useConnectToken: true)`; the client mints a single-use token via
  `POST /ws/token` first.
- Reconnects with backoff and replays your subscriptions. `close()` opts out.
- `subscribe()` before `connect()` is fine; it's replayed on open.
- Server caps client messages at 60/minute and concurrent subscriptions by plan.

Message types: `LiveMessageType.matchUpdate`, `.authSuccess`, `.status`, `.pong`,
`.serverShutdown`, `.error`. Use the `messages` stream for everything.

Flutter widget sketch:

```dart
StreamBuilder<Map<String, dynamic>>(
  stream: live.on(LiveMessageType.matchUpdate),
  builder: (context, snapshot) {
    final update = snapshot.data?['data'] as Map<String, dynamic>?;
    return Text('${update?['homeScore'] ?? '-'} : ${update?['awayScore'] ?? '-'}');
  },
)
```

## Webhooks

Verify against the **raw** body. A decoded-and-re-encoded map has different bytes and will
never match.

```dart
import 'package:goal_api/goal_api.dart';
import 'package:shelf/shelf.dart';

Future<Response> handler(Request request) async {
  final body = await request.read().expand((chunk) => chunk).toList();

  try {
    final event = verifyWebhook(
      body,
      request.headers[signatureHeader],
      Platform.environment['GOAL_WEBHOOK_SECRET']!,
    );

    if (request.headers[eventHeader] == WebhookEvent.goalScored) {
      // ...
    }
  } on WebhookSignatureException {
    return Response.badRequest();
  }

  return Response.ok('');   // ack fast; retries are ~1m, 5m, 25m, 2h, 10h
}
```

Timestamps outside 5 minutes are rejected as replays. Override with `tolerance:`.

## Escape hatch

For an endpoint this SDK doesn't wrap yet:

```dart
final data = await goal.request('/some/new/endpoint', {'limit': 10});
```

## Testing

```bash
dart pub get
dart test                       # unit tests, no network
GOAL_API_KEY=... dart test      # also runs the live tests
dart analyze --fatal-infos
dart run example/goal_api_example.dart
```

The live tests skip themselves without a key. Endpoint-by-endpoint coverage of the API
lives in `tools/sweep.py` in the SDK workspace.

## License

MIT
