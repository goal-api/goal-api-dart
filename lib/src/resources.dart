import 'transport.dart';

/// One class per endpoint group.
///
/// Methods return the decoded envelope (`{success, data, pagination}`). Rows stay
/// as maps rather than models -- they follow the API's response shapes and change. Accepted
/// params and limit ceilings: ENDPOINTS.md
typedef Json = Map<String, dynamic>;
typedef Params = Map<String, dynamic>;

abstract class _Resource {
  const _Resource(this._t);
  final Transport _t;
}

/// Unauthenticated status and coverage. No API key needed.
///
/// These five don't use the `{success, data}` envelope -- they return bare
/// objects, so read `(await status.get())['status']`, not `['data']['status']`.
class StatusResource extends _Resource {
  const StatusResource(super.t);

  /// `{status, updatedAt, measurement, components[]}`
  Future<Json> get() => _t.get('/public/status');

  /// `{leagues, countries, teams, players, fixtures, ...}`
  Future<Json> coverage() => _t.get('/public/coverage');

  /// `{leagues[], total, page, limit, pages}`
  ///
  /// Paginates with `page`/`limit`, not `offset`, so `paginate` won't work here.
  /// Also accepts `q` and `country`.
  Future<Json> coverageLeagues([Params? params]) =>
      _t.get('/public/coverage/leagues', params);

  /// `{countries[], total}`
  Future<Json> coverageCountries() => _t.get('/public/coverage/countries');

  /// A bare league object. The 404 body is `{error, code}`.
  Future<Json> coverageLeague(Object id) =>
      _t.get('/public/coverage/leagues/${segment(id)}');
}

class CountriesResource extends _Resource {
  const CountriesResource(super.t);

  Future<Json> list([Params? params]) => _t.get('/countries', params);
  Future<Json> get(Object id) => _t.get('/countries/${segment(id)}');
  Future<Json> leagues(Object id, [Params? params]) =>
      _t.get('/countries/${segment(id)}/leagues', params);
}

class LeaguesResource extends _Resource {
  const LeaguesResource(super.t);

  Future<Json> list([Params? params]) => _t.get('/leagues', params);
  Future<Json> get(Object id) => _t.get('/leagues/${segment(id)}');
  Future<Json> teams(Object id, [Params? params]) =>
      _t.get('/leagues/${segment(id)}/teams', params);
  Future<Json> standings(Object id, [Params? params]) =>
      _t.get('/leagues/${segment(id)}/standings', params);
  Future<Json> fixtures(Object id, [Params? params]) =>
      _t.get('/leagues/${segment(id)}/fixtures', params);
  Future<Json> topScorers(Object id, [Params? params]) =>
      _t.get('/leagues/${segment(id)}/top-scorers', params);
  Future<Json> results(Object id, [Params? params]) =>
      _t.get('/leagues/${segment(id)}/results', params);
}

class TeamsResource extends _Resource {
  const TeamsResource(super.t);

  Future<Json> list([Params? params]) => _t.get('/teams', params);
  Future<Json> get(Object id, [Params? params]) =>
      _t.get('/teams/${segment(id)}', params);
  Future<Json> players(Object id, [Params? params]) =>
      _t.get('/teams/${segment(id)}/players', params);
  Future<Json> fixtures(Object id, [Params? params]) =>
      _t.get('/teams/${segment(id)}/fixtures', params);
  Future<Json> results(Object id, [Params? params]) =>
      _t.get('/teams/${segment(id)}/results', params);
  Future<Json> statistics(Object id, [Params? params]) =>
      _t.get('/teams/${segment(id)}/statistics', params);
  Future<Json> upcoming(Object id, [Params? params]) =>
      _t.get('/teams/${segment(id)}/upcoming', params);
}

class FixturesResource extends _Resource {
  const FixturesResource(super.t);

  Future<Json> list([Params? params]) => _t.get('/fixtures', params);

  /// Matches in play. Takes an optional `leagueId`.
  Future<Json> live([Params? params]) => _t.get('/fixtures/live', params);

  /// [date] is `YYYY-MM-DD`.
  Future<Json> byDate(String date, [Params? params]) =>
      _t.get('/fixtures/date/${segment(date)}', params);

  Future<Json> get(Object id) => _t.get('/fixtures/${segment(id)}');
  Future<Json> events(Object id) => _t.get('/fixtures/${segment(id)}/events');
  Future<Json> lineups(Object id) => _t.get('/fixtures/${segment(id)}/lineups');

  /// Takes an optional `half`: `full`, `1half` or `2half`.
  Future<Json> statistics(Object id, [Params? params]) =>
      _t.get('/fixtures/${segment(id)}/statistics', params);

  Future<Json> cards(Object id) => _t.get('/fixtures/${segment(id)}/cards');
  Future<Json> substitutions(Object id) =>
      _t.get('/fixtures/${segment(id)}/substitutions');

  // These four accept a matchApiId as well as a fixture id.
  Future<Json> odds(Object id) => _t.get('/fixtures/${segment(id)}/odds');
  Future<Json> predictions(Object id) =>
      _t.get('/fixtures/${segment(id)}/predictions');
  Future<Json> liveOdds(Object id) =>
      _t.get('/fixtures/${segment(id)}/live-odds');
  Future<Json> commentary(Object id) =>
      _t.get('/fixtures/${segment(id)}/commentary');
}

/// Every method takes an optional `stage`.
///
/// [home] and [away] 404 for leagues with no home/away split,
/// even when the base table has rows.
class StandingsResource extends _Resource {
  const StandingsResource(super.t);

  Future<Json> get(Object leagueId, [Params? params]) =>
      _t.get('/standings/${segment(leagueId)}', params);
  Future<Json> team(Object leagueId, Object teamId) =>
      _t.get('/standings/${segment(leagueId)}/team/${segment(teamId)}');
  Future<Json> home(Object leagueId, [Params? params]) =>
      _t.get('/standings/${segment(leagueId)}/home', params);
  Future<Json> away(Object leagueId, [Params? params]) =>
      _t.get('/standings/${segment(leagueId)}/away', params);
  Future<Json> form(Object leagueId, [Params? params]) =>
      _t.get('/standings/${segment(leagueId)}/form', params);
  Future<Json> zones(Object leagueId, [Params? params]) =>
      _t.get('/standings/${segment(leagueId)}/zones', params);
}

class PlayersResource extends _Resource {
  const PlayersResource(super.t);

  Future<Json> list([Params? params]) => _t.get('/players', params);

  /// [query] must be 2-100 characters.
  Future<Json> search(String query, [Params? params]) =>
      _t.get('/players/search', {...?params, 'q': query});

  /// 2-5 players.
  Future<Json> compare(List<Object> ids) =>
      _t.get('/players/compare', {'ids': ids});

  /// Ranks players by a stat. See [playerStats].
  Future<Json> top(String stat, [Params? params]) =>
      _t.get('/players/top/${segment(stat)}', params);

  Future<Json> get(Object id) => _t.get('/players/${segment(id)}');
  Future<Json> statistics(Object id, [Params? params]) =>
      _t.get('/players/${segment(id)}/statistics', params);
}

class CoachesResource extends _Resource {
  const CoachesResource(super.t);

  Future<Json> list([Params? params]) => _t.get('/coaches', params);
  Future<Json> search(String query, [Params? params]) =>
      _t.get('/coaches/search', {...?params, 'q': query});
  Future<Json> byCountry(String country, [Params? params]) =>
      _t.get('/coaches/country/${segment(country)}', params);
  Future<Json> byTeam(Object teamId) =>
      _t.get('/coaches/team/${segment(teamId)}');
  Future<Json> get(Object id) => _t.get('/coaches/${segment(id)}');
}

/// The two ids must differ, and 404 means the teams have never met.
class H2HResource extends _Resource {
  const H2HResource(super.t);

  Future<Json> get(Object team1Id, Object team2Id) =>
      _t.get('/h2h/${segment(team1Id)}/${segment(team2Id)}');
  Future<Json> direct(Object team1Id, Object team2Id, [Params? params]) =>
      _t.get('/h2h/${segment(team1Id)}/${segment(team2Id)}/direct', params);
  Future<Json> stats(Object team1Id, Object team2Id) =>
      _t.get('/h2h/${segment(team1Id)}/${segment(team2Id)}/stats');
}

/// The list endpoints here take `limit` up to 500.
class ResultsResource extends _Resource {
  const ResultsResource(super.t);

  Future<Json> list([Params? params]) => _t.get('/results', params);
  Future<Json> today() => _t.get('/results/today');
  Future<Json> yesterday() => _t.get('/results/yesterday');
  Future<Json> stats([Params? params]) => _t.get('/results/stats', params);
  Future<Json> highScoring([Params? params]) =>
      _t.get('/results/high-scoring', params);
  Future<Json> byDate(String date) => _t.get('/results/date/${segment(date)}');
  Future<Json> byLeague(Object leagueId, [Params? params]) =>
      _t.get('/results/league/${segment(leagueId)}', params);
  Future<Json> byTeam(Object teamId, [Params? params]) =>
      _t.get('/results/team/${segment(teamId)}', params);
}

class VideosResource extends _Resource {
  const VideosResource(super.t);

  Future<Json> list([Params? params]) => _t.get('/videos', params);
  Future<Json> recent([Params? params]) => _t.get('/videos/recent', params);
  Future<Json> byMatch(Object matchId) =>
      _t.get('/videos/match/${segment(matchId)}');
  Future<Json> byLeague(Object leagueId, [Params? params]) =>
      _t.get('/videos/league/${segment(leagueId)}', params);
  Future<Json> byDate(String date, [Params? params]) =>
      _t.get('/videos/date/${segment(date)}', params);
}

/// News articles, newest first.
///
/// Takes `leagueId`, `teamId`, `matchId`, `from`, `to`, `limit` (max 100,
/// default 20) and `offset`. The ids are the news source's and are not
/// guaranteed to resolve against `/teams` or `/leagues`, so every article also
/// carries `teamName` and `leagueName`; any of them may be null.
class NewsResource extends _Resource {
  const NewsResource(super.t);

  Future<Json> list([Params? params]) => _t.get('/news', params);
  Future<Json> byMatch(Object matchId, [Params? params]) =>
      _t.get('/news/match/${segment(matchId)}', params);
  Future<Json> byTeam(Object teamId, [Params? params]) =>
      _t.get('/news/team/${segment(teamId)}', params);
  Future<Json> byLeague(Object leagueId, [Params? params]) =>
      _t.get('/news/league/${segment(leagueId)}', params);

  /// One article, by our id or the article's apiId. 404s when absent.
  Future<Json> get(Object id) => _t.get('/news/${segment(id)}');
}

/// Takes `bookmaker`, `matchId`, `limit` (max 200, default 50) and `offset`.
class OddsResource extends _Resource {
  const OddsResource(super.t);

  Future<Json> list([Params? params]) => _t.get('/odds', params);
}

/// Takes `matchId`, `leagueName`, `limit` (max 200, default 50) and `offset`.
class PredictionsResource extends _Resource {
  const PredictionsResource(super.t);

  Future<Json> list([Params? params]) => _t.get('/predictions', params);
}

/// Values accepted by the `status` query param.
const List<String> matchStatuses = [
  'SCHEDULED',
  'LIVE',
  'FINISHED',
  'HALF_TIME',
  'AFTER_ET',
  'AFTER_PEN',
  'POSTPONED',
  'CANCELLED',
  'AWARDED',
  'ABANDONED',
  'SUSPENDED',
];

/// Values accepted by the `type` query param on player endpoints.
const List<String> playerTypes = [
  'Goalkeepers',
  'Defenders',
  'Midfielders',
  'Forwards'
];

/// Values accepted as the stat path segment of `/players/top/{stat}`.
const List<String> playerStats = [
  'goals',
  'assists',
  'yellowCards',
  'redCards',
  'rating',
  'matchPlayed',
  'minutes',
  'saves',
  'tackles',
  'shotsTotal',
  'keyPasses',
  'passes',
  'interceptions',
  'duelsWon',
  'dribbleSucc',
];

/// Values accepted by the `half` query param on fixture statistics.
const List<String> halves = ['full', '1half', '2half'];
