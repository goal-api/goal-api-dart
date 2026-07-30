# Changelog

All notable changes to this package. Versions follow [semver](https://semver.org);
all five GOAL API SDKs are released together under one version number.

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
