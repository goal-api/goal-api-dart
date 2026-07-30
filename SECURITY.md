# Security policy

## Reporting a vulnerability

Email **support@goal-api.com** with "security" in the subject. Please do not open a public
issue for anything exploitable.

Include what you have: affected version, a reproduction, and what an attacker gets. We will
acknowledge within three working days and keep you updated until it is resolved. If you want
credit in the release notes, say so.

## Supported versions

The latest minor release gets security fixes. Older minors do not, so upgrade before
reporting against one.

## What is in scope

This is a client library. The interesting surface is small but real:

- **Webhook signature verification.** A bypass, a timing leak in the comparison, or a way
  to get a forged delivery accepted.
- **Path and query construction.** Anything that lets a caller-supplied id change which
  endpoint is hit, or inject into the query string.
- **Credential handling.** The API key appearing anywhere it should not: a log line, an
  error message, a URL, a stack trace.
- **The retry and backoff logic**, if it can be driven into amplifying requests against the
  API.
- **The WebSocket client**, including the native/web handshake split and the token flow.

Out of scope: vulnerabilities in the GOAL API service itself (still email us, it is just a
different fix), in your own application code, or in third-party dependencies where the fix
belongs upstream. See THIRD_PARTY_NOTICES.md for what those are.

## Notes for users

- **Keys belong on a server.** A key in a browser bundle or a mobile binary is a public key,
  whatever the file permissions say. Proxy through your own backend.
- **For browser live data, use the `/ws/token` flow.** Your backend mints a short-lived
  single-use token so the frontend never sees the key.
- **Verify webhooks against the raw request body.** A parsed-and-re-encoded body has
  different bytes, so the HMAC will not match, and working around that by skipping
  verification is the actual vulnerability.
