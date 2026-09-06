# Changelog

All notable changes to this package. Versions follow [semver](https://semver.org);
all five GOAL API SDKs are released together under one version number.

## 1.1.0 - 2026-09-06

### Fixed

- **Reconnection no longer bypasses backoff when the server refuses the upgrade.**
  A rejected handshake (a `429` from the rate limiter, a `503`, a dead network)
  fails inside `connect()`'s own try/catch, before the stream — and therefore
  before `onDone`/`_handleDone` — exists. Reconnection hung entirely off
  `_handleDone`, so the exponential backoff was unreachable on exactly the path
  that retries hardest: every caller-driven retry restarted from attempt 0 with
  no delay. Refused handshakes now schedule a retry like any other disconnect,
  and `connect()` still throws so an awaiting caller learns it failed.
- **The backoff counter no longer resets on `auth_success` alone.** A server that
  accepts the socket and then drops it (plan limit reached) made every cycle look
  like a success, pinning retries at the first backoff step forever. A connection
  must now hold for `stableAfter` (default 60s) before the counter resets.
- **Concurrent `connect()` calls no longer open competing retry chains.** A
  rebuilding UI could start several, each doubling the request rate on every
  subsequent failure. Only one retry is pending at a time.
- **`close()` no longer hangs after a failed connect.** Awaiting `sink.close()`
  on a channel whose upgrade was refused never completes; that channel is now
  dropped, and the close handshake is bounded at 2s.

### Added

- `stableAfter` on `GoalApi.live()` and `LiveClient`, controlling how long a
  connection must survive before the backoff counter resets.

## 1.0.0

First release. Covers the full public API surface (13 resource groups, ~70 endpoints).

- Grouped resources: `status`, `countries`, `leagues`, `teams`, `fixtures`, `standings`,
  `players`, `coaches`, `h2h`, `results`, `videos`, `odds`, `predictions`.
- Typed errors carrying `code`, `category`, `details` and `correlationId`, normalised
  across the API's two error shapes (`message` from the gateway, `error` from the
  football service).
- Retries on 429 and 5xx with exponential backoff and jitter, honouring `Retry-After`.
  Never on 4xx, never on a cancelled request.
- Rate-limit snapshot from the `X-RateLimit-*` headers.
- Pagination helpers that terminate on `hasMore: false` or a short page.
- Webhook signature verification with constant-time comparison and a replay window.
- Percent-encoded path segments.
