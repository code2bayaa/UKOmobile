// Port of mobile/components/home/controllers.jsx (CONTROLLERS): the
// Genre / Region / Language / Year (/ Actor Jobs for type "people") filter
// buttons, their expandable pick lists, and the "selected filter" chips with
// "remove" links. Used by the discover screens (lib/screens/shared/discover.dart).
import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart' show FetchPolicy;

import '../../core/http.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';

/// Argument object of RN `intitializeMovies({manualMode, page, genreId,
/// regionId, languageId, yearId, jobId})` as called by the controllers.
class DiscoverQuery {
  const DiscoverQuery({
    this.page = 1,
    this.genreId = '',
    this.regionId = '',
    this.languageId = '',
    this.yearId = 0,
    this.jobId,
    this.manualMode,
  });

  final int page;
  final String genreId;
  final String regionId;
  final String languageId;
  final int yearId;

  /// Only sent for type "people" (RN passed it only there).
  final String? jobId;

  /// RN passed `manualMode: type` (a truthy string).
  final String? manualMode;
}

// ---------------------------------------------------------------------------
// GraphQL documents (verbatim from controllers.jsx)
// ---------------------------------------------------------------------------

const String _genreQuery = r'''
        query Genre {
            genre {
                data {
                    id
                    name
                    mode
                }
                date
                success
                error
            }
        }
    ''';

const String _addGenreMutation = r'''
        mutation AddGenre(
            $date: String!
            $data: [GENRE_LIST_INPUT]!
        ) {
            addGenre(
             date: $date
             data: $data
            ){
                date
                data {
                    id
                    name
                    mode
                }
                success
                error
            }
        }
    ''';

const String _updateGenreMutation = r'''
        mutation UpdateGenre(
            $date: String!
            $data: [GENRE_LIST_INPUT]!
        ) {
            updateGenre(
                date: $date
                data: $data
            ){
                date
                data {
                    id
                    name
                    mode
                }
                success
                error
            }
        }
    ''';

const String _regionQuery = r'''
        query Region {
            region {
                data {
                    iso_3166_1
                    english_name
                    native_name
                }
                date
                success
                error
            }
        }
    ''';

const String _addRegionMutation = r'''
        mutation AddRegion(
            $date: String!
            $data: [REGION_DATA_INPUT]!
        ) {
            addRegion(
             date: $date
             data: $data
            ){
                date
                data {
                    iso_3166_1
                    english_name
                    native_name
                }
                success
                error
            }
        }
    ''';

const String _languageQuery = r'''
        query Language {
            language {
                data {
                    iso_639_1
                    english_name
                    name
                }
                date
                success
                error
            }
        }
    ''';

const String _addLanguageMutation = r'''
        mutation AddLanguage(
            $date: String!
            $data: [LANGUAGE_DATA_INPUT]!
        ) {
            addLanguage(
             date: $date
             data: $data
            ){
                date
                data {
                    iso_639_1
                    english_name
                    name
                }
                success
                error
            }
        }
    ''';

/// JSON form of a JS `new Date()` (what Apollo serialises the `date`
/// variable to): `2026-09-24T10:11:12.345Z` (millisecond precision).
String _jsDateNow() {
  final d = DateTime.now().toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}'
      'T${two(d.hour)}:${two(d.minute)}:${two(d.second)}.${d.millisecond.toString().padLeft(3, '0')}Z';
}

class Controllers extends StatefulWidget {
  const Controllers({
    super.key,
    required this.intitializeMovies,
    required this.type,
    this.extra,
    this.selectedFilters,
    this.onSelectedFiltersChanged,
  });

  /// Parent loader (RN prop `intitializeMovies`).
  final void Function(DiscoverQuery query) intitializeMovies;

  /// "movie" | "tv" | "people"
  final String type;

  /// "movie" | "tv" (people: which credits list)
  final String? extra;

  /// Parent-controlled filters (RN `selectedFilters`): keys genreId, genreName,
  /// regionId, regionName, languageId, languageName, yearId, yearName, jobId, jobName.
  final Map<String, dynamic>? selectedFilters;

  /// RN `setSelectedFilters(prev => ({...prev, ...}))` — receives the merged map.
  final ValueChanged<Map<String, dynamic>>? onSelectedFiltersChanged;

  @override
  State<Controllers> createState() => _ControllersState();
}

class _ControllersState extends State<Controllers> {
  List<Map<String, dynamic>>? _genre;
  List<Map<String, dynamic>>? _region;
  List<Map<String, dynamic>>? _language;
  List<int>? _years;
  List<Map<String, dynamic>>? _jobs;
  bool _selectedGenre = false;
  bool _selectedRegion = false;
  bool _selectedLanguage = false;
  bool _selectedYear = false;
  bool _selectedJob = false;

  // Local fallbacks (used only when no parent `selectedFilters` is given).
  String _languageId = '';
  int _yearId = 0;
  String _regionId = '';
  String _genreId = '';
  String _jobId = 'Actor';
  String _languageName = '';
  String _yearName = '';
  String _regionName = '';
  String _genreName = '';
  String _jobName = '';

  bool get _parentControlled => widget.onSelectedFiltersChanged != null;

  dynamic _sel(String key, dynamic local) {
    final m = widget.selectedFilters;
    if (m != null && m.containsKey(key) && m[key] != null) return m[key];
    return local;
  }

  // Effective current values. RN read only its (never updated when
  // parent-controlled) local ids here, so combined filters did not stack.
  String get genreId => '${_sel('genreId', _genreId)}';
  String get regionId => '${_sel('regionId', _regionId)}';
  String get languageId => '${_sel('languageId', _languageId)}';
  int get yearId => toNum(_sel('yearId', _yearId)).toInt();
  String get jobId => '${_sel('jobId', _jobId)}';

  bool get _people => widget.type == 'people';

  void _setFilters(Map<String, dynamic> patch, VoidCallback local) {
    if (_parentControlled) {
      widget.onSelectedFiltersChanged!({...?widget.selectedFilters, ...patch});
    } else {
      setState(local);
    }
  }

  void _init({String? genre, String? region, String? language, int? year, String? job, bool withJob = false}) {
    widget.intitializeMovies(DiscoverQuery(
      manualMode: widget.type,
      page: 1,
      genreId: genre ?? genreId,
      regionId: region ?? regionId,
      languageId: language ?? languageId,
      yearId: year ?? yearId,
      jobId: (_people || withJob) ? (job ?? jobId) : null,
    ));
  }

  // ---------------------------------------------------------------- remove
  void _removeGenre() {
    _init(genre: '');
    _setFilters({'genreId': '', 'genreName': ''}, () {
      _genreId = '';
      _genreName = '';
    });
  }

  void _removeJob() {
    _setFilters({'jobId': '', 'jobName': ''}, () {
      _jobId = '';
      _jobName = '';
    });
    _init(job: 'Actor', withJob: true);
  }

  void _removeLanguage() {
    _setFilters({'languageId': '', 'languageName': ''}, () {
      _languageId = '';
      _languageName = '';
    });
    _init(language: '');
  }

  void _removeRegion() {
    _setFilters({'regionId': '', 'regionName': ''}, () {
      _regionId = '';
      _regionName = '';
    });
    _init(region: '');
  }

  void _removeYear() {
    // RN stored the current year here but queried with 0; keep them consistent (0 = no year).
    _setFilters({'yearId': 0, 'yearName': ''}, () {
      _yearId = 0;
      _yearName = '';
    });
    _init(year: 0);
  }

  // ---------------------------------------------------------------- filter
  void _filterGenre(dynamic id, String name) {
    _init(genre: '$id');
    _setFilters({'genreId': '$id', 'genreName': name}, () {
      _genreId = '$id';
      _genreName = name;
    });
    setState(() {
      _genre = null;
      _selectedGenre = false;
    });
  }

  void _filterRegion(String id, String name) {
    _setFilters({'regionId': id, 'regionName': name}, () {
      _regionId = id;
      _regionName = name;
    });
    _init(region: id);
    setState(() {
      _region = null;
      _selectedRegion = false;
    });
  }

  void _filterLanguage(String id, String name) {
    _setFilters({'languageId': id, 'languageName': name}, () {
      _languageId = id;
      _languageName = name;
    });
    _init(language: id);
    setState(() {
      _language = null;
      _selectedLanguage = false;
    });
  }

  void _filterYear(int id) {
    _setFilters({'yearId': id, 'yearName': '$id'}, () {
      _yearId = id;
      _yearName = '$id';
    });
    _init(year: id);
    setState(() {
      _years = null;
      _selectedYear = false;
    });
  }

  void _filterJob(String id) {
    _setFilters({'jobId': id, 'jobName': id}, () {
      _jobId = id;
      _jobName = id;
    });
    _init(job: id, withJob: true);
    setState(() {
      _jobs = null;
      _selectedJob = false;
    });
  }

  // ---------------------------------------------------------------- TMDB
  Future<dynamic> _tmdb(String path) async {
    final k = KeyService.instance;
    await k.ready;
    return Http.getJson('${k.movieDb}$path?api_key=${k.apiKey}&language=en-US');
  }

  /// Mirrors Apollo's `fetchX.refetch()` after a successful insert: refresh
  /// the cached query result so the next open reads the new rows.
  void _refetch(String doc) {
    Gql.query(doc, const {}, fetchPolicy: FetchPolicy.networkOnly);
  }

  // ---------------------------------------------------------------- getters
  Future<void> _getLanguage() async {
    if (_selectedLanguage) {
      setState(() {
        _selectedLanguage = false;
        _language = null;
      });
      return;
    }
    setState(() => _selectedLanguage = true);
    List<Map<String, dynamic>> list;
    final data = await Gql.query(_languageQuery, const {});
    final lang = data?['language'];
    if (lang is Map) {
      if (lang['error'] == 'no records found') {
        final fresh = await _tmdb('configuration/languages');
        list = asMapList(fresh);
        if (list.isNotEmpty) {
          Gql.mutate(_addLanguageMutation, {'date': _jsDateNow(), 'data': list}).then((r) {
            final res = r?['addLanguage'];
            if (res is Map && res['success'] == true) _refetch(_languageQuery);
          });
        }
      } else {
        list = asMapList(lang['data']);
      }
    } else {
      list = asMapList(await _tmdb('configuration/languages'));
    }
    if (!mounted || !_selectedLanguage) return;
    setState(() => _language = list);
  }

  Future<void> _getRegion() async {
    if (_selectedRegion) {
      setState(() {
        _selectedRegion = false;
        _region = null;
      });
      return;
    }
    setState(() => _selectedRegion = true);
    List<Map<String, dynamic>> list;
    final data = await Gql.query(_regionQuery, const {});
    final region = data?['region'];
    if (region is Map) {
      if (region['error'] == 'no records found') {
        list = asMapList(await _tmdb('configuration/countries'));
        if (list.isNotEmpty) {
          Gql.mutate(_addRegionMutation, {'date': _jsDateNow(), 'data': list}).then((r) {
            final res = r?['addRegion'];
            if (res is Map && res['success'] == true) _refetch(_regionQuery);
          });
        }
      } else {
        list = asMapList(region['data']);
      }
    } else {
      list = asMapList(await _tmdb('configuration/countries'));
    }
    if (!mounted || !_selectedRegion) return;
    setState(() => _region = list);
  }

  Future<List<Map<String, dynamic>>> _freshGenres() async {
    final t = widget.type == 'movie' ? 'movie' : widget.extra == 'movie' ? 'movie' : 'tv';
    final data = await _tmdb('genre/$t/list');
    return data is Map ? asMapList(data['genres']) : <Map<String, dynamic>>[];
  }

  Future<void> _getGenre() async {
    if (_selectedGenre) {
      setState(() {
        _genre = null;
        _selectedGenre = false;
      });
      return;
    }
    setState(() => _selectedGenre = true);
    final type = widget.type;
    final mode = truthy(widget.extra) ? widget.extra : type;
    List<Map<String, dynamic>> list;
    final data = await Gql.query(_genreQuery, const {});
    final genre = data?['genre'];
    if (genre is Map) {
      final stored = asMapList(genre['data']);
      if (genre['error'] == 'no records found') {
        final fresh = await _freshGenres();
        list = [for (final g in fresh) {...g, 'mode': mode}];
        if (list.isNotEmpty) {
          Gql.mutate(_addGenreMutation, {'date': _jsDateNow(), 'data': list}).then((r) {
            final res = r?['addGenre'];
            if (res is Map && res['success'] == true) _refetch(_genreQuery);
          });
        }
      } else if (!stored.any((g) => g['mode'] == type)) {
        // switching from movie to tv
        final fresh = await _freshGenres();
        final typed = [for (final g in fresh) {...g, 'mode': mode}];
        list = [...stored.map((g) => Map<String, dynamic>.from(stripTypename(g) as Map)), ...typed];
        if (typed.isNotEmpty) {
          Gql.mutate(_updateGenreMutation, {'date': _jsDateNow(), 'data': list}).then((r) {
            final res = r?['updateGenre'];
            if (res is Map && res['success'] == true) _refetch(_genreQuery);
          });
        }
      } else {
        list = stored.where((g) => g['mode'] == widget.extra || g['mode'] == type).toList();
      }
    } else {
      list = await _freshGenres();
    }
    if (!mounted || !_selectedGenre) return;
    setState(() => _genre = list);
  }

  void _getYears() {
    if (_selectedYear) {
      setState(() {
        _selectedYear = false;
        _years = null;
      });
    } else {
      final now = DateTime.now().year;
      setState(() {
        _years = [for (var y = 1993; y <= now; y++) y];
        _selectedYear = true;
      });
    }
  }

  Future<void> _getJobs() async {
    if (_selectedJob) {
      setState(() {
        _selectedJob = false;
        _jobs = null;
      });
      return;
    }
    setState(() => _selectedJob = true);
    final data = await _tmdb('configuration/jobs');
    if (!mounted || !_selectedJob) return;
    setState(() => _jobs = asMapList(data));
  }

  // ---------------------------------------------------------------- UI
  Widget _toggle(String label, bool selected, VoidCallback onTap, double w) {
    return Padding(
      padding: EdgeInsets.all(w * 0.01),
      child: Material(
        color: selected ? UkoColors.yellow : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? Colors.black : UkoColors.yellow, width: 2)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: w * 0.23, minHeight: 70, maxHeight: 70),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: TextStyle(color: selected ? Colors.black : UkoColors.yellow)),
                  const SizedBox(width: 8),
                  Icon(selected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One cell of the 3-column pick lists: name (75%) + small slate bar.
  Widget _pickCell(String text, VoidCallback onTap, double cellW, {double height = 100}) {
    return SizedBox(
      width: cellW,
      height: height,
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: cellW * 0.75,
              child: Text(text, style: const TextStyle(color: Colors.white)),
            ),
            Container(
              width: cellW * 0.15,
              height: 10,
              decoration: const BoxDecoration(
                color: UkoColors.slate,
                border: Border(right: BorderSide(color: Colors.white, width: 4)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<Widget> cells) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 5),
        child: Wrap(spacing: 10, runSpacing: 10, children: cells),
      );

  Widget _chip(String label, String name, VoidCallback onRemove, double w) {
    return Container(
      constraints: BoxConstraints(maxWidth: w * 0.23),
      margin: EdgeInsets.all(w * 0.01),
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: UkoColors.yellow, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: UkoColors.yellow)),
          Text(name, style: const TextStyle(color: Colors.white)),
          InkWell(
            onTap: onRemove,
            child: const SizedBox(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text('remove',
                    style: TextStyle(color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _name(String key, String local) {
    final v = widget.selectedFilters?[key] ?? local;
    return v == null ? '' : '$v';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.of(context).size.width;
      final cellW = (w - 2 - 20) * 0.30;

      final genreName = _name('genreName', _genreName);
      final languageName = _name('languageName', _languageName);
      final regionName = _name('regionName', _regionName);
      final yearName = _name('yearName', _yearName);
      final jobName = _name('jobName', _jobName);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _toggle('Genre', _selectedGenre, _getGenre, w),
              _toggle('Region', _selectedRegion, _getRegion, w),
              _toggle('Language', _selectedLanguage, _getLanguage, w),
              _toggle('Year', _selectedYear, _getYears, w),
              if (_people) _toggle('Actor Jobs', _selectedJob, _getJobs, w),
            ],
          ),
          if (_genre != null)
            _grid([
              for (final g in _genre!)
                _pickCell('${g['name'] ?? ''}', () => _filterGenre(g['id'], '${g['name'] ?? ''}'), cellW),
            ]),
          if (_region != null)
            _grid([
              for (final r in _region!)
                _pickCell('${r['english_name'] ?? ''}',
                    () => _filterRegion('${r['iso_3166_1'] ?? ''}', '${r['english_name'] ?? ''}'), cellW),
            ]),
          if (_language != null)
            _grid([
              for (final l in _language!)
                _pickCell('${l['english_name'] ?? ''}',
                    () => _filterLanguage('${l['iso_639_1'] ?? ''}', '${l['english_name'] ?? ''}'), cellW),
            ]),
          if (_years != null)
            _grid([
              for (final y in _years!) _pickCell('$y', () => _filterYear(y), cellW),
            ]),
          if (_jobs != null)
            for (final d in _jobs!)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${d['department'] ?? ''}', style: const TextStyle(color: Colors.white)),
                    _grid([
                      for (final j in (d['jobs'] is List ? d['jobs'] as List : const []))
                        _pickCell('$j', () => _filterJob('$j'), cellW, height: 60),
                    ]),
                  ],
                ),
              ),
          Wrap(
            children: [
              if (genreName.isNotEmpty) _chip('genre', genreName, _removeGenre, w),
              if (languageName.isNotEmpty) _chip('language', languageName, _removeLanguage, w),
              if (regionName.isNotEmpty) _chip('region', regionName, _removeRegion, w),
              if (yearName.isNotEmpty) _chip('year', yearName, _removeYear, w),
              if (jobName.isNotEmpty) _chip('job', jobName, _removeJob, w),
            ],
          ),
        ],
      );
    });
  }
}
