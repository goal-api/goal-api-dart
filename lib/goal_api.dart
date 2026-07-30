/// Dart SDK for the GOAL API: football fixtures, live scores, standings, player
/// stats, odds and live WebSocket updates.
///
/// https://goal-api.com/documentation
///
/// ```dart
/// import 'package:goal_api/goal_api.dart';
///
/// final goal = GoalApi(apiKey: 'your-key');
/// final page = await goal.fixtures.live();
/// print(page['data']);
/// goal.close();
/// ```
library;

export 'src/client.dart' show GoalApi;
export 'src/errors.dart';
export 'src/live.dart' show LiveClient, LiveMessageType;
export 'src/resources.dart';
export 'src/transport.dart' show RateLimitInfo, defaultBaseUrl, sdkVersion;
export 'src/webhooks.dart'
    show
        WebhookEvent,
        WebhookSignatureException,
        deliveryHeader,
        eventHeader,
        signatureHeader,
        verifyWebhook;
