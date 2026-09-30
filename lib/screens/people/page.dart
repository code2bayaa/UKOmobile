// Port of mobile/app/(tabs)/people/page.tsx (PEOPLE).
import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/graphql.dart';
import '../../services/keys.dart';
import '../../widgets/common.dart';
import '../../widgets/eden_image.dart';
import '../../widgets/picture.dart';
import '../../widgets/sweet_page.dart';

const _fetchPeopleCollectionQuery = r'''
        query PeopleCollection (
            $data:[COLLECTION_TRACK_PEOPLE_DATA_OUTPUT],
            $hashedKey:String!
        ){
            peopleCollection(
                data :$data,
                hashedKey:$hashedKey
            ) {
                data {
                    results {
                        adult
                        gender
                        profile_path
                        id
                        known_for_department
                        name
                        original_name
                        popularity
                    }
                    page
                    total_pages
                    total_results
                    index
                }
                success
                error
                message
            }
        }
''';

const _insertPeopleCollectionMutation = r'''
        mutation AddCollectionPeople(
            $data:[ADD_COLLECTION_PEOPLE],
            $hashedKey:String!,
            $date:String!,
        ) {
            addCollectionPeople(
                hashedKey:$hashedKey,
                date:$date,
                data:$data
            ) {
                success
                message
            }
        }
''';

const _fetchPersonQuery = r'''
        query People (
            $page: Int!,
            $genre : String!,
            $year : Int!,
            $region : String!,
            $language : String!,
            $index : String!,
            $date:String!,
            $hashedKey:String!
        ){
            people(
                page:$page,
                genre:$genre,
                year:$year,
                region:$region,
                language:$language,
                index:$index,
                date:$date,
                hashedKey:$hashedKey
            ) {
                results {
                    adult
                    gender
                    profile_path
                    id
                    known_for_department
                    name
                    original_name
                    popularity

                }
                page
                total_pages
                total_results
                success
                error
                message
                people_page
                people_next
            }
        }
''';

const _insertPersonMutation = r'''
      mutation AddPerson(
          $page:Int!,
          $results:[ADD_PERSON_RESULTS_INPUT],
          $total_pages:Int!,
          $total_results:Int!,
          $data :TRACK_PERSON_DATA_INPUT,
          $chunking:Boolean!
          $chunking_index:Int!
          $people_total_pages:Int!
          $type:String!,
          $hashedKey:String!
      ) {
          addPerson(
              page:$page,
              results:$results,
              total_pages:$total_pages,
              total_results:$total_results,
              data:$data,
              chunking:$chunking
              chunking_index:$chunking_index
              people_total_pages:$people_total_pages
              type:$type,
              hashedKey:$hashedKey
          ) {
              success
              message
              index
          }
      }
''';

/// `temp_people` in the RN file: index -> TMDB api path. Order = display order.
const _peopleApis = <String, String>{
  'trending': 'trending/person/day',
  'popular': 'person/popular',
};

/// Eden studios' own cast & crew, most followed first - served by the database
/// service (POST /database/people/eden), not TMDB. Shown above the TMDB rows.
const _edenIndex = 'eden_studios';
const _peopleOrder = [_edenIndex, 'trending', 'popular'];

class PeoplePageScreen extends StatefulWidget {
  const PeoplePageScreen({super.key});

  @override
  State<PeoplePageScreen> createState() => _PeoplePageScreenState();
}

class _PeoplePageScreenState extends State<PeoplePageScreen> {
  List<Map<String, dynamic>> _people = [];

  @override
  void initState() {
    super.initState();
    _loadEden(1);
    _initPeople(runContent: const ['trending', 'popular'], page: 1, adjustable: true);
  }

  /// One page (20) of Eden people ranked by followers.
  Future<void> _loadEden(int page) async {
    final res = await Http.postJson(Api.edenPeople, {'page': page});
    if (res is! Map || res['success'] != true) return;
    final results = asMapList(res['results']);
    // no Eden people yet - keep the row off the page
    if (results.isEmpty && page == 1) return;
    _upsert(_edenIndex, {
      'results': results,
      'page': res['page'] ?? page,
      'total_pages': res['total_pages'],
      'total_results': res['total_results'],
    });
  }

  /// Insert or update the collection for [index], keeping the RN display
  /// order (eden studios, trending, popular).
  void _upsert(String index, Map<String, dynamic> fields) {
    if (!mounted) return;
    setState(() {
      final list = [..._people];
      final i = list.indexWhere((p) => p['index'] == index);
      if (i > -1) {
        list[i] = {...list[i], ...fields};
      } else {
        list.add({'index': index, ...fields});
      }
      const order = _peopleOrder;
      int rank(Map<String, dynamic> p) {
        final r = order.indexOf('${p['index']}');
        return r < 0 ? order.length : r;
      }

      list.sort((a, b) => rank(a).compareTo(rank(b)));
      _people = list;
    });
  }

  /// RN `intitPeople`: first load of both rows through the collection cache.
  Future<void> _initPeople({required List<String> runContent, int? page, bool adjustable = false}) async {
    final currentDate = isoDateToday();
    var hashed = 'people$currentDate';
    final peopleWrap = <Map<String, dynamic>>[];
    for (final actualIndex in runContent) {
      final p = page ?? 1;
      hashed += '$p$actualIndex';
      peopleWrap.add({'page': p, 'index': actualIndex, 'date': currentDate});
    }
    final hashedKey = sha256Hex(hashed);
    if (!adjustable) return;

    Future<void> freshFetch() async {
      final k = KeyService.instance;
      await k.ready;
      final insertContent = (await Future.wait(runContent.map((actualIndex) async {
        final p = page ?? 1;
        final json = await Http.getJson(
            '${k.movieDb}${_peopleApis[actualIndex]}?api_key=${k.apiKey}&language=en-US&page=$p');
        final peopleArray = json is Map ? asMapList(json['results']) : <Map<String, dynamic>>[];
        if (peopleArray.isNotEmpty) {
          _upsert(actualIndex, {
            'results': peopleArray,
            'page': p,
            'total_pages': json['total_pages'],
            'total_results': json['total_results'],
          });
          return <String, dynamic>{
            'page': p,
            'results': json['results'],
            'total_pages': json['total_pages'],
            'total_results': json['total_results'],
            'index': actualIndex,
          };
        }
        return null;
      })))
          .whereType<Map<String, dynamic>>()
          .toList();

      Gql.mutate(_insertPeopleCollectionMutation, {
        'data': insertContent,
        'date': currentDate,
        'hashedKey': hashedKey,
      });
    }

    final data = await Gql.query(_fetchPeopleCollectionQuery, {'data': peopleWrap, 'hashedKey': hashedKey});
    final pc = data?['peopleCollection'];
    if (pc is Map && pc['message'] != 'not initialized' && !truthy(pc['error']) && pc['data'] is List) {
      // upsert rather than replace so the Eden row already loaded stays
      for (final row in asMapList(pc['data'])) {
        _upsert('${row['index'] ?? ''}', row);
      }
    } else {
      await freshFetch();
    }
  }

  /// RN `intitializePeople` (called by SWEETPAGE with adjustable:true and
  /// empty filters).
  Future<void> _initializePeople({
    required List<String> runContent,
    int? page,
    bool adjustable = false,
    String jobId = 'Actor',
    String genreId = '',
    String regionId = '',
    String languageId = '',
    int yearId = 0,
  }) async {
    for (final actualIndex in runContent.toSet()) {
      _fetchPersonFromApi(actualIndex,
          page: page,
          adjustable: adjustable,
          jobId: jobId,
          genreId: genreId,
          regionId: regionId,
          languageId: languageId,
          yearId: yearId);
    }
  }

  Future<void> _fetchPersonFromApi(
    String actualIndex, {
    int? page,
    required bool adjustable,
    required String jobId,
    required String genreId,
    required String regionId,
    required String languageId,
    required int yearId,
  }) async {
    final currentDate = isoDateToday();
    final p = page ?? 1;
    final hashedKey = sha256Hex('$p$genreId$regionId$languageId${js(yearId)}${actualIndex}person0');

    Future<void> freshFetch() async {
      final k = KeyService.instance;
      await k.ready;
      final json = await Http.getJson(
          '${k.movieDb}${_peopleApis[actualIndex]}?api_key=${k.apiKey}&language=en-US&page=$p&with_genres=$genreId&with_origin_country=$regionId&sort_by=popularity.desc&with_original_language=$languageId&primary_release_year=${js(yearId)}');
      final peopleArray = json is Map ? asMapList(json['results']) : <Map<String, dynamic>>[];
      if (peopleArray.isEmpty) return;
      _upsert(actualIndex, {
        'results': peopleArray,
        'page': p,
        'total_pages': json['total_pages'],
        'total_results': json['total_results'],
      });
      Gql.mutate(_insertPersonMutation, {
        'page': p,
        'results': json['results'],
        'total_pages': json['total_pages'],
        'total_results': json['total_results'],
        'chunking': false,
        'chunking_index': 0,
        'people_total_pages': 0,
        'data': {
          'genre': genreId,
          'region': regionId,
          'language': languageId,
          'year': yearId,
          'index': actualIndex,
          'date': currentDate,
        },
        'type': 'person',
        'hashedKey': hashedKey,
      });
    }

    if (!(adjustable || jobId != 'Actor' || genreId.isNotEmpty || regionId.isNotEmpty || languageId.isNotEmpty || yearId != 0)) {
      return;
    }
    final data = await Gql.query(_fetchPersonQuery, {
      'page': p,
      'genre': genreId,
      'region': regionId,
      'language': languageId,
      'year': yearId,
      'index': actualIndex,
      'date': currentDate,
      'hashedKey': hashedKey,
    });
    final people = data?['people'];
    if (people is Map && people['error'] != 'insert person' && people['error'] != 'no records found') {
      _upsert(actualIndex, {
        'results': asMapList(people['results']),
        'page': people['page'] ?? p,
        if (people['total_pages'] != null) 'total_pages': people['total_pages'],
        if (people['total_results'] != null) 'total_results': people['total_results'],
      });
    } else {
      await freshFetch();
    }
  }

  void _open(Map<String, dynamic> person, {bool eden = false}) {
    final id = person.idInt;
    // Eden people have their own page, read from the database by their `person` row id -
    // their `id` is Eden's own counter and would open a stranger's TMDB profile
    final params = <String, dynamic>{
      'id': id,
      if (eden) ...{'eden': true, 'person_id': person['person_id']},
    };
    // phone only - the TV app has no People pages to mirror
    Nav.push(context, eden ? Routes.edenPeopleId : Routes.peopleId, params);
  }

  @override
  Widget build(BuildContext context) {
    if (_people.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Align(
          alignment: Alignment.topCenter,
          child: Text('Loading...', style: TextStyle(color: Colors.white)),
        ),
      );
    }
    final itemWidth = MediaQuery.of(context).size.width * 0.45;
    return ListView.builder(
      padding: const EdgeInsets.only(top: 16, bottom: 32),
      itemCount: _people.length,
      itemBuilder: (context, i) {
        final item = _people[i];
        final index = '${item['index'] ?? ''}';
        final results = asMapList(item['results']);
        return Column(
          key: ValueKey('people-$index'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(index.replaceFirst('_', ' ')),
            SweetPage(
              key: ValueKey('people-page-$index'),
              page: toNum(item['page']).toInt() == 0 ? 1 : toNum(item['page']).toInt(),
              totalPages: toNum(item['total_pages']).toInt(),
              onPageChange: (newPage) => index == _edenIndex
                  ? _loadEden(newPage)
                  : _initializePeople(
                runContent: [index],
                adjustable: true,
                page: newPage,
                genreId: '',
                regionId: '',
                languageId: '',
                yearId: 0,
              ),
            ),
            SizedBox(
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: results.length,
                itemBuilder: (context, j) => Padding(
                  key: ValueKey('discover-people-${results[j]['id'] ?? j}'),
                  padding: EdgeInsets.only(right: itemWidth * 0.011 + 2),
                  child: _PersonCard(
                    person: results[j],
                    width: itemWidth,
                    eden: index == _edenIndex,
                    onTap: () => _open(results[j], eden: index == _edenIndex),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// `renderMovie` of people/page.tsx: profile picture, name, then
/// star + popularity | known_for_department. Eden people show their follower
/// count in place of the TMDB popularity.
class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.width, required this.onTap, this.eden = false});
  final Map<String, dynamic> person;
  final double width;
  final VoidCallback onTap;
  final bool eden;

  @override
  Widget build(BuildContext context) {
    final profile = person['profile_path'];
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 180,
              width: double.infinity,
              child: eden
                  ? EdenImage(path: profile is String ? profile : '')
                  : Picture(picture: profile is String ? profile : ''),
            ),
            SizedBox(
              height: 25,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${or([person['name'], person['original_name']]) ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: UkoColors.divider, width: 2)),
              ),
              child: Row(
                children: [
                  Icon(eden ? Icons.people_outline : Icons.star_border, size: 18, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(eden ? '${toNum(person['followers']).toInt()}' : person.ratingText,
                      style: const TextStyle(color: UkoColors.yellow, fontSize: 15)),
                  const SizedBox(width: 6),
                  const Text('|', style: TextStyle(color: Colors.white)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('${person['known_for_department'] ?? ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
