# GOAL API — SDK surface specification

Single source of truth for all five SDKs. Derived from the live service, not from prose:

- Gateway mounts (`services/api-gateway/src/app.js:126-129`, `routes/football.js`)
- Route tables (`services/football-service/src/routes/*.js`)
- Parameter validators (`services/football-service/src/middleware/validators/*.js`)
- Error envelope (`services/api-gateway/src/errors/sendErrorResponse.js`)
- Rate-limit headers (`services/api-gateway/src/middleware/rateLimiter.js:350-379`)
- WebSocket protocol (`services/websocket-service/src/handlers/messageRouter.js`, `subscriptionHandler.js`)
- Webhook signing (`services/worker-service/src/services/webhookDeliveryService.js:22-67`)

## Transport

| | |
|---|---|
| Base URL | `https://api.goal-api.com/v1` |
| Auth | `Authorization: Bearer <API_KEY>` (the **only** accepted form — no `X-API-Key`) |
| Content type | `application/json` |
| Methods used by the data API | `GET` only |

## Success envelope

Collection endpoints:

```json
{
  "success": true,
  "data": [ ... ],
  "pagination": { "total": 1234, "limit": 50, "offset": 0, "hasMore": true },
  "source": "cache" | "database"
}
```

Single-resource endpoints return `{ "success": true, "data": { ... } }`. The betting
endpoints additionally return top-level `fixtureId`, `matchApiId` and `count`.

## Error envelope

There are **two** shapes, confirmed by `integration/sweep.py` against production. An SDK
has to read both.

Gateway errors (auth, routing, rate limits) — `services/api-gateway/src/errors/sendErrorResponse.js`:

```json
{
  "success": false,
  "message": "Route not found",
  "code": "ROUTE_NOT_FOUND",
  "category": "not_found",
  "details": { "path": "/api/v1/no/such/route" },
  "correlationId": "gw-1785382415462-0dne7w5",
  "timestamp": "2026-07-30T03:33:35.463Z"
}
```

Football-service errors — the great majority of what a client hits:

```json
{
  "success": false,
  "error": "Fixture not found",
  "code": "FIXTURE_NOT_FOUND"
}
```

Validation errors from that service carry express-validator's array in `details`:

```json
{
  "success": false,
  "error": "Validation failed",
  "code": "VALIDATION_ERROR",
  "details": [
    { "type": "field", "value": "not-a-stat", "msg": "Invalid stat parameter",
      "path": "stat", "location": "params" }
  ]
}
```

So, portably:

| Field | Always present | Notes |
|---|---|---|
| `success: false` | yes | |
| `code` | yes | |
| `message` | gateway only | Human text. Service errors put it in `error` instead. |
| `error` | service only | Read `message ?? error`. |
| `category` | gateway only | |
| `correlationId` | gateway only | Do **not** rely on it for service errors. |
| `timestamp` | gateway only | |
| `details` | sometimes | Object on gateway errors, array on service validation errors. |

Every SDK normalises this: one message field regardless of shape, and a nullable
`correlationId`.

Codes the SDKs map to typed errors:

| Status | Code | SDK error |
|---|---|---|
| 400 / 422 | `VALIDATION_ERROR` | `ValidationError` |
| 401 | `AUTH_FAILED`, `INVALID_API_KEY`, `INVALID_WS_TOKEN`, `WS_TOKEN_ALREADY_USED` | `AuthenticationError` |
| 402 | `PLAN_UPGRADE_REQUIRED` | `PlanUpgradeRequiredError` |
| 403 | `ACCESS_DENIED` | `PermissionError` |
| 404 | `ROUTE_NOT_FOUND`, plus per-resource codes: `FIXTURE_NOT_FOUND`, `STANDINGS_NOT_FOUND`, `H2H_NOT_FOUND`, `H2H_STATS_NOT_FOUND`, … | `NotFoundError` |
| 409 | `CONFLICT`, `DUPLICATE_RECORD` | `ConflictError` |
| 429 | `RATE_LIMIT_EXCEEDED`, `BURST_LIMIT_EXCEEDED` | `RateLimitError` |
| 503 | `SERVICE_UNAVAILABLE` | `ServiceUnavailableError` |
| 5xx | `INTERNAL_ERROR`, `DATABASE_ERROR` | `ServerError` |

## Rate-limit headers

Set on every authenticated response: `X-RateLimit-Limit`, `X-RateLimit-Remaining`,
`X-RateLimit-Reset` (unix seconds), `X-RateLimit-Type` (`DAILY` / `MONTHLY`), plus
`Retry-After` (seconds) on 429.

## Shared parameter vocabulary

| Param | Type | Notes |
|---|---|---|
| `limit` | int | Per-endpoint max — 50/100/200/500, see table below |
| `offset` | int | `>= 0` |
| `from`, `to` | `YYYY-MM-DD` | `to` must be `>= from` |
| `season` | `YYYY-YYYY` or `YYYY/YY` | Must be consecutive years, e.g. `2025-2026` |
| `isActive` | bool | `true` / `false` |
| `live` | bool | `true` / `false` |
| `search` | string | 2–100 chars, `[a-zA-Z0-9 \-'.]` only |
| `q` | string | Required on `/search` endpoints, same charset |
| `status` | enum | `SCHEDULED` `LIVE` `FINISHED` `HALF_TIME` `AFTER_ET` `AFTER_PEN` `POSTPONED` `CANCELLED` `AWARDED` `ABANDONED` `SUSPENDED` |
| `type` | enum | `Goalkeepers` `Defenders` `Midfielders` `Forwards` |
| `half` | enum | `full` `1half` `2half` |
| `stage` | string | 1–100 chars |
| `country` | string | 2–100 chars, letters/spaces/hyphens |
| `stat` | enum | `goals` `assists` `yellowCards` `redCards` `rating` `matchPlayed` `minutes` `saves` `tackles` `shotsTotal` `keyPasses` `passes` `interceptions` `duelsWon` `dribbleSucc` |
| `ids` | csv | 2–5 player ids, `/players/compare` only |
| `includePlayers` | bool | `/teams/{id}` only |

## Endpoint map → SDK method

`client.<group>.<method>()` in every language (naming adapted per language convention:
`camelCase` for JS/Dart/PHP, `snake_case` for Python, `PascalCase` for Go).

### status (no API key required)

> **These five endpoints do not use the `{success, data}` envelope.** They return bare
> objects, they paginate with `page`/`limit` rather than `limit`/`offset`, and their 404
> body is `{error, code}` with no `message`. Verified against the live API and
> `services/football-service/src/routes/public.js`. The SDKs return their bodies as-is
> rather than pretending they are wrapped — do not reach for `.data` on these.

| Method | Endpoint | Params | Response |
|---|---|---|---|
| `status.get()` | `GET /public/status` | — | `{status, updatedAt, measurement, components[]}` |
| `status.coverage()` | `GET /public/coverage` | — | `{leagues, countries, teams, players, fixtures, …}` |
| `status.coverageLeagues(p)` | `GET /public/coverage/leagues` | `q` `country` `page` `limit` | `{leagues[], total, page, limit, pages}` |
| `status.coverageCountries()` | `GET /public/coverage/countries` | — | `{countries[], total}` |
| `status.coverageLeague(id)` | `GET /public/coverage/leagues/{id}` | — bare league object | 404 → `{error, code}` |

Rate limited by IP at 60/min, with the draft-standard `RateLimit-*` headers rather than
`X-RateLimit-*` — so these calls leave the SDKs' rate-limit snapshot untouched.

### countries

| Method | Endpoint | Params |
|---|---|---|
| `countries.list(p)` | `GET /countries` | `isActive` `search` `limit`≤500 `offset` |
| `countries.get(id)` | `GET /countries/{id}` | — |
| `countries.leagues(id, p)` | `GET /countries/{id}/leagues` | `season` `isActive` `limit`≤100 `offset` |

### leagues

| Method | Endpoint | Params |
|---|---|---|
| `leagues.list(p)` | `GET /leagues` | `countryId` `season` `search` `isActive` `limit`≤100 `offset` |
| `leagues.get(id)` | `GET /leagues/{id}` | — |
| `leagues.teams(id, p)` | `GET /leagues/{id}/teams` | `season` `limit`≤100 `offset` |
| `leagues.standings(id, p)` | `GET /leagues/{id}/standings` | `stage` |
| `leagues.fixtures(id, p)` | `GET /leagues/{id}/fixtures` | `from` `to` `status` `limit`≤100 `offset` |
| `leagues.topScorers(id, p)` | `GET /leagues/{id}/top-scorers` | `limit`≤100 |
| `leagues.results(id, p)` | `GET /leagues/{id}/results` | `from` `to` `limit`≤100 `offset` |

### teams

| Method | Endpoint | Params |
|---|---|---|
| `teams.list(p)` | `GET /teams` | `leagueId` `country` `search` `isActive` `limit`≤100 `offset` |
| `teams.get(id, p)` | `GET /teams/{id}` | `includePlayers` |
| `teams.players(id, p)` | `GET /teams/{id}/players` | `type` `limit`≤100 `offset` |
| `teams.fixtures(id, p)` | `GET /teams/{id}/fixtures` | `status` `from` `to` `limit`≤100 `offset` |
| `teams.results(id, p)` | `GET /teams/{id}/results` | `from` `to` `limit`≤100 `offset` |
| `teams.statistics(id, p)` | `GET /teams/{id}/statistics` | `season` |
| `teams.upcoming(id, p)` | `GET /teams/{id}/upcoming` | `limit`≤50 |

### fixtures

| Method | Endpoint | Params |
|---|---|---|
| `fixtures.list(p)` | `GET /fixtures` | `from` `to` `leagueId` `teamId` `status` `live` `limit`≤100 `offset` |
| `fixtures.live(p)` | `GET /fixtures/live` | `leagueId` |
| `fixtures.byDate(date, p)` | `GET /fixtures/date/{date}` | `leagueId` `teamId` `limit`≤100 `offset` |
| `fixtures.get(id)` | `GET /fixtures/{id}` | — |
| `fixtures.events(id)` | `GET /fixtures/{id}/events` | — |
| `fixtures.lineups(id)` | `GET /fixtures/{id}/lineups` | — |
| `fixtures.statistics(id, p)` | `GET /fixtures/{id}/statistics` | `half` |
| `fixtures.cards(id)` | `GET /fixtures/{id}/cards` | — |
| `fixtures.substitutions(id)` | `GET /fixtures/{id}/substitutions` | — |
| `fixtures.odds(id)` | `GET /fixtures/{id}/odds` | — |
| `fixtures.predictions(id)` | `GET /fixtures/{id}/predictions` | — |
| `fixtures.liveOdds(id)` | `GET /fixtures/{id}/live-odds` | — |
| `fixtures.commentary(id)` | `GET /fixtures/{id}/commentary` | — |

The four betting sub-resources accept either a GOAL fixture id or the provider's
`matchApiId`.

### standings

| Method | Endpoint | Params |
|---|---|---|
| `standings.get(leagueId, p)` | `GET /standings/{leagueId}` | `stage` |
| `standings.team(leagueId, teamId)` | `GET /standings/{leagueId}/team/{teamId}` | — |
| `standings.home(leagueId, p)` | `GET /standings/{leagueId}/home` | `stage` |
| `standings.away(leagueId, p)` | `GET /standings/{leagueId}/away` | `stage` |
| `standings.form(leagueId, p)` | `GET /standings/{leagueId}/form` | `stage` |
| `standings.zones(leagueId, p)` | `GET /standings/{leagueId}/zones` | `stage` |

`/home` and `/away` filter on the provider's `homeLeaguePosition`, which is empty for many
leagues. Those return `404 STANDINGS_NOT_FOUND` even when the base table has rows — handle
404 here as "no split available", not as a bad league id.

### players

| Method | Endpoint | Params |
|---|---|---|
| `players.list(p)` | `GET /players` | `teamId` `type` `search` `limit`≤100 `offset` |
| `players.search(q, p)` | `GET /players/search` | `q` (required) `limit`≤100 |
| `players.compare(ids)` | `GET /players/compare` | `ids` (2–5, csv) |
| `players.top(stat, p)` | `GET /players/top/{stat}` | `teamId` `type` `limit`≤100 |
| `players.get(id)` | `GET /players/{id}` | — |
| `players.statistics(id, p)` | `GET /players/{id}/statistics` | `season` |

### coaches

| Method | Endpoint | Params |
|---|---|---|
| `coaches.list(p)` | `GET /coaches` | `search` `country` `limit`≤100 `offset` |
| `coaches.search(q, p)` | `GET /coaches/search` | `q` (required) `limit`≤100 |
| `coaches.byCountry(country, p)` | `GET /coaches/country/{country}` | `limit`≤100 `offset` |
| `coaches.byTeam(teamId)` | `GET /coaches/team/{teamId}` | — |
| `coaches.get(id)` | `GET /coaches/{id}` | — |

### h2h

| Method | Endpoint | Params |
|---|---|---|
| `h2h.get(t1, t2)` | `GET /h2h/{team1Id}/{team2Id}` | — |
| `h2h.direct(t1, t2, p)` | `GET /h2h/{team1Id}/{team2Id}/direct` | `limit`≤100 |
| `h2h.stats(t1, t2)` | `GET /h2h/{team1Id}/{team2Id}/stats` | — |

`team1Id` and `team2Id` must differ (server-enforced).

### results

| Method | Endpoint | Params |
|---|---|---|
| `results.list(p)` | `GET /results` | `leagueId` `teamId` `from` `to` `limit`≤500 `offset` |
| `results.today()` | `GET /results/today` | — |
| `results.yesterday()` | `GET /results/yesterday` | — |
| `results.stats(p)` | `GET /results/stats` | `leagueId` `from` `to` |
| `results.highScoring(p)` | `GET /results/high-scoring` | `leagueId` `from` `to` `limit`≤100 |
| `results.byDate(date)` | `GET /results/date/{date}` | — |
| `results.byLeague(leagueId, p)` | `GET /results/league/{leagueId}` | `from` `to` `limit`≤500 `offset` |
| `results.byTeam(teamId, p)` | `GET /results/team/{teamId}` | `from` `to` `limit`≤500 `offset` |

### videos

| Method | Endpoint | Params |
|---|---|---|
| `videos.list(p)` | `GET /videos` | `leagueId` `from` `to` `limit`≤100 `offset` |
| `videos.recent(p)` | `GET /videos/recent` | `leagueId` `limit`≤100 |
| `videos.byMatch(matchId)` | `GET /videos/match/{matchId}` | — |
| `videos.byLeague(leagueId, p)` | `GET /videos/league/{leagueId}` | `from` `to` `limit`≤100 `offset` |
| `videos.byDate(date, p)` | `GET /videos/date/{date}` | `leagueId` `limit`≤100 `offset` |

### odds / predictions

| Method | Endpoint | Params |
|---|---|---|
| `odds.list(p)` | `GET /odds` | `bookmaker` `matchId` `limit`≤200 (default 50) `offset` |
| `predictions.list(p)` | `GET /predictions` | `matchId` `leagueName` `limit`≤200 (default 50) `offset` |

## WebSocket (live matches)

- URL: `wss://api.goal-api.com/v1/ws`
- Server-side auth: `Authorization: Bearer <API_KEY>` on the handshake.
- Browser auth: `POST /v1/ws/token` with the API key → `{ data: { token, expiresIn } }`,
  then connect to `wss://api.goal-api.com/v1/ws?wsToken=<token>`. Single-use, short TTL.

Client → server:

```json
{"type": "ping"}
{"type": "subscribe",   "resource": "match", "matchId": "..."}
{"type": "unsubscribe", "resource": "match", "matchId": "..."}
{"type": "get_subscriptions"}
{"type": "status"}
```

`resource` only accepts `"match"`. Client messages are capped at 60/minute
(`MESSAGE_RATE_LIMIT_EXCEEDED`); concurrent subscriptions are capped by plan.

Server → client: `auth_success`, `match_update`, `pong`, `status`, `server_shutdown`,
`error`.

## Webhooks

Delivered as `POST` with headers `X-Goal-Signature`, `X-Goal-Event`, `X-Goal-Delivery`.

Signature is the Stripe scheme — `t=<unix>,v1=<hex>` where the HMAC-SHA256 is computed
over `"<timestamp>.<raw body>"` using the endpoint secret. Verify against the **raw**
bytes, and reject timestamps outside a tolerance window (default 300s) to stop replays.

Events: `match.started`, `match.finished`, `goal.scored`, `score.changed`,
`match.status_changed`.

Retry schedule on the server: 5 attempts at ~1m, 5m, 25m, 2h, 10h.

Webhook *management* (`/auth/webhook-endpoints`) is authenticated with a dashboard JWT,
not an API key, so it is intentionally out of scope for these SDKs. Signature
verification is included.
