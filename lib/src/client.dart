import 'package:http/http.dart' as http;

import 'live.dart';
import 'resources.dart';
import 'transport.dart';

/// The GOAL API client.
///
/// ```dart
/// final goal = GoalApi(apiKey: Platform.environment['GOAL_API_KEY']!);
/// final page = await goal.fixtures.live();
/// for (final match in page['data'] as List) {
///   print('${match['homeTeam']['name']} ${match['homeScore']}');
/// }
/// goal.close();
/// ```
///
/// Share one instance: the [http.Client] pools connections and the rate-limit
/// snapshot is per-instance. Call [close] when done.
class GoalApi {
  GoalApi({
    required String apiKey,
    String baseUrl = defaultBaseUrl,
    Duration timeout = const Duration(seconds: 30),
    int maxRetries = 2,
    http.Client? httpClient,
    String? userAgent,
    Map<String, String> headers = const {},
  }) : this._(Transport(
          apiKey: apiKey,
          baseUrl: baseUrl,
          timeout: timeout,
          maxRetries: maxRetries,
          httpClient: httpClient,
          userAgent: userAgent,
          headers: headers,
        ));

  GoalApi._(this._t)
      : status = StatusResource(_t),
        countries = CountriesResource(_t),
        leagues = LeaguesResource(_t),
        teams = TeamsResource(_t),
        fixtures = FixturesResource(_t),
        standings = StandingsResource(_t),
        players = PlayersResource(_t),
        coaches = CoachesResource(_t),
        h2h = H2HResource(_t),
        results = ResultsResource(_t),
        videos = VideosResource(_t),
        news = NewsResource(_t),
        odds = OddsResource(_t),
        predictions = PredictionsResource(_t);

  final Transport _t;

  /// Unauthenticated status and coverage. Returns bare objects, not the
  /// `{success, data}` envelope. See [StatusResource].
  final StatusResource status;
  final CountriesResource countries;
  final LeaguesResource leagues;
  final TeamsResource teams;
  final FixturesResource fixtures;
  final StandingsResource standings;
  final PlayersResource players;
  final CoachesResource coaches;
  final H2HResource h2h;
  final ResultsResource results;
  final VideosResource videos;
  final NewsResource news;
  final OddsResource odds;
  final PredictionsResource predictions;

  /// Quota from the last response. All null until the first authenticated call.
  RateLimitInfo get rateLimit => _t.rateLimit;

  String get baseUrl => _t.baseUrl;

  /// For endpoints not wrapped here yet.
  Future<Json> request(String path, [Params? params]) => _t.get(path, params);

  /// Walks pages, yielding items.
  ///
  /// ```dart
  /// await for (final team in goal.paginate((p) => goal.leagues.teams(leagueId, p))) {
  ///   print(team['name']);
  /// }
  /// ```
  ///
  /// 100 is the limit ceiling on most endpoints; `/results` and `/countries` take
  /// 500.
  Stream<dynamic> paginate(
    Future<Json> Function(Params page) fetchPage, {
    int pageSize = 100,
    int? maxItems,
    int startOffset = 0,
  }) async* {
    var offset = startOffset;
    var yielded = 0;

    while (maxItems == null || yielded < maxItems) {
      final page = await fetchPage({'limit': pageSize, 'offset': offset});
      final items = page['data'];
      if (items is! List || items.isEmpty) return;

      for (final item in items) {
        yield item;
        yielded++;
        if (maxItems != null && yielded >= maxItems) return;
      }

      // Some endpoints omit pagination; a short page is the only other signal.
      final pagination = page['pagination'];
      if (pagination is Map && pagination.containsKey('hasMore')) {
        if (pagination['hasMore'] != true) return;
      } else if (items.length < pageSize) {
        return;
      }
      offset += items.length;
    }
  }

  /// [paginate] collected into a list.
  Future<List<dynamic>> collect(
    Future<Json> Function(Params page) fetchPage, {
    int pageSize = 100,
    int? maxItems,
    int startOffset = 0,
  }) =>
      paginate(fetchPage,
              pageSize: pageSize, maxItems: maxItems, startOffset: startOffset)
          .toList();

  /// Live match updates. Nothing opens until you await [LiveClient.connect].
  ///
  /// ```dart
  /// final live = goal.live();
  /// live.on('match_update').listen((m) => print(m['data']));
  /// await live.connect();
  /// live.subscribe(fixtureId);
  /// ```
  LiveClient live({
    String? url,
    bool autoReconnect = true,
    int? maxReconnectAttempts,
    Duration pingInterval = const Duration(seconds: 30),
    bool useConnectToken = false,
    Duration stableAfter = const Duration(seconds: 60),
  }) =>
      LiveClient(
        _t,
        url: url,
        autoReconnect: autoReconnect,
        maxReconnectAttempts: maxReconnectAttempts,
        pingInterval: pingInterval,
        useConnectToken: useConnectToken,
        stableAfter: stableAfter,
      );

  /// Releases the HTTP client.
  void close() => _t.close();
}
