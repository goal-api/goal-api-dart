# Third-party notices

This package is MIT licensed. It depends on the packages below at runtime, each under its
own licence. Nothing is vendored: `dart pub get` fetches them, and each ships its own
licence text.

## Direct

| Package | Licence | Why |
|---|---|---|
| [http](https://pub.dev/packages/http) | BSD-3-Clause | The HTTP client. Works unchanged on native and web, which the conditional-import layout relies on. |
| [web_socket_channel](https://pub.dev/packages/web_socket_channel) | BSD-3-Clause | The live match feed, with the platform split this SDK needs (headers on native, `?wsToken=` on web). |
| [crypto](https://pub.dev/packages/crypto) | BSD-3-Clause | HMAC-SHA256 for webhook signature verification. Dart has no HMAC in its core libraries. |

All three are published by the Dart team under the standard Dart project BSD-3-Clause
licence, and all are permissive: no copyleft obligations on your code.

## Development only

Not part of the published package: `test` (BSD-3-Clause), `lints` (BSD-3-Clause).

## Checking this yourself

```bash
dart pub deps --style=list
```

Versions move, so treat the table above as the shape rather than the current truth.
