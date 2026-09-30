// Port of web-app/src/components/eden/person.jsx - an Eden studio's cast or crew member at
// /eden/people/id. Read from the database only (POST /database/people/eden/id), never TMDB,
// whose ids collide with Eden's. Same layout as eden/movie.dart: backdrop, portrait, facts,
// actions (resume reel, follow), then credit rows and more people from the studio.
import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../widgets/common.dart';
import '../../widgets/eden_image.dart';
import '../../widgets/yt_player.dart';
import '../movies/detail_common.dart' show PillButton;
import 'eden_common.dart';

class EdenPersonScreen extends StatefulWidget {
  const EdenPersonScreen({super.key, this.params = const {}});

  /// {person_id} - the `person` row id - and/or {id} - Eden's public id.
  final Map<String, dynamic> params;

  @override
  State<EdenPersonScreen> createState() => _EdenPersonScreenState();
}

class _EdenPersonScreenState extends State<EdenPersonScreen> {
  static const _white = TextStyle(color: Colors.white);

  Map<String, dynamic>? _person;
  Map<String, dynamic> _movies = const {};
  Map<String, dynamic> _series = const {};
  List<Map<String, dynamic>> _resume = [];
  List<Map<String, dynamic>> _related = [];
  String? _playing;
  bool _following = false;
  bool _loading = true;

  int? get _id => P.intOf(widget.params, 'id');
  int? get _personId => P.intOf(widget.params, 'person_id');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_id == null && _personId == null) {
      setState(() => _loading = false);
      return;
    }
    final res = await Http.postJson(Api.edenPerson, {'person_id': _personId, 'id': _id});
    if (!mounted) return;
    final ok = res is Map && res['success'] == true;
    setState(() {
      _person = ok ? Map<String, dynamic>.from(res['person'] as Map) : null;
      _movies = ok && res['movies'] is Map ? Map<String, dynamic>.from(res['movies'] as Map) : const {};
      _series = ok && res['series'] is Map ? Map<String, dynamic>.from(res['series'] as Map) : const {};
      _resume = ok ? asMapList(res['resume']) : [];
      _related = ok ? asMapList(res['related']) : [];
      _loading = false;
    });
    final rowId = _person?['person_id'];
    if (rowId == null) return;
    // the user service answers from the app token - never a user id the app claims
    final following = await Http.postJson(Api.edenFollowing, {'person_id': rowId});
    if (mounted && following is Map && following['following'] == true) setState(() => _following = true);
  }

  Future<void> _follow() async {
    final person = _person;
    if (person == null) return;
    final res = await Http.postJson(Api.edenFollow, {'person_id': person['person_id']});
    if (!mounted) return;
    if (res is! Map || res['status'] == null && res['message'] == null) {
      showUkoSnack(context, 'Oops...', 'Sign in to follow ${person['name'] ?? ''}');
      return;
    }
    if (res['status'] == true) {
      showUkoSnack(context, 'success', 'Added to following');
      setState(() => person['followers'] = toNum(person['followers']).toInt() + 1);
    } else if (res['message'] == 'Already following') {
      showUkoSnack(context, 'Oops...', 'Already following');
    } else {
      showUkoSnack(context, 'Oops...', 'Sign in to follow ${person['name'] ?? ''}');
      return;
    }
    setState(() => _following = true);
  }

  void _play(String? key) => setState(() => _playing = key);

  void _openCredit(Map<String, dynamic> credit) {
    final id = credit.idInt;
    // a season or episode whose series could not be resolved has no page to open
    if (id <= 0) return;
    Nav.push(context, credit['media_type'] == 'tv' ? Routes.tvEden : Routes.moviesEden, {'id': id});
  }

  void _openPerson(Map<String, dynamic> other) =>
      Nav.push(context, Routes.edenPeopleId, {'id': other['id'], 'person_id': other['person_id'], 'eden': true});

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    final p = _person;
    if (p == null) {
      return const Center(child: Text('This Eden person could not be found.', style: TextStyle(color: UkoColors.divider)));
    }
    final width = MediaQuery.of(context).size.width;
    final btnW = (width - 24) / 2;
    final name = '${or([p['name'], p['original_name']]) ?? ''}';
    final followers = toNum(p['followers']).toInt();
    List<Map<String, dynamic>> list(Map<String, dynamic> m, String k) => asMapList(m[k]);
    final all = [...list(_movies, 'cast'), ...list(_movies, 'crew'), ...list(_series, 'cast'), ...list(_series, 'crew')];
    // the background is the newest credit's backdrop, as the title pages use their own
    final backdrop = all.map((c) => c['backdrop_path']).firstWhere(truthy, orElse: () => null);
    final facts = [p['birthday'], if (truthy(p['deathday'])) '– ${p['deathday']}', p['place_of_birth']]
        .where(truthy)
        .join(' · ');
    final aka = p['also_known_as'];

    return ListView(
      key: ValueKey(p['person_id']),
      padding: const EdgeInsets.only(bottom: 128),
      children: [
        Stack(
          children: [
            EdenBackdrop(path: backdrop?.toString(), height: 260),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  EdenImage(
                    path: p['profile_path']?.toString(),
                    width: width * 0.36,
                    height: width * 0.54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EdenTag(),
                        const SizedBox(height: 8),
                        Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        if (truthy(p['original_name']) && p['original_name'] != p['name'])
                          Text('${p['original_name']}', style: const TextStyle(color: UkoColors.gray400)),
                        const SizedBox(height: 4),
                        Text('${p['known_for_department'] ?? ''} · ${all.length} credit${all.length == 1 ? '' : 's'}',
                            style: _white),
                        Row(children: [
                          const Icon(Icons.people_outline, size: 16, color: UkoColors.yellow),
                          const SizedBox(width: 4),
                          Text('$followers follower${followers == 1 ? '' : 's'}',
                              style: const TextStyle(color: UkoColors.yellow)),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (aka is List && aka.isNotEmpty)
                Text(aka.join(' || '),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: UkoColors.yellow, fontStyle: FontStyle.italic)),
              if (facts.isNotEmpty) Text(facts, textAlign: TextAlign.center, style: const TextStyle(color: UkoColors.gray400)),
              if (truthy(p['skills']))
                Text(p['skills'] is List ? (p['skills'] as List).join(' || ') : '${p['skills']}',
                    textAlign: TextAlign.center, style: const TextStyle(color: UkoColors.yellow, fontSize: 12)),
              const SizedBox(height: 10),
              Text('${or([p['biography'], 'waiting for more content'])}', textAlign: TextAlign.justify, style: _white),
              // follow hangs right under the biography
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: Material(
                  color: _following ? Colors.black : UkoColors.yellow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: _following ? const BorderSide(color: UkoColors.yellow, width: 2) : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _follow,
                    child: Center(
                      child: Text(_following ? 'following' : 'follow',
                          style: TextStyle(
                              color: _following ? UkoColors.yellow : Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_resume.isNotEmpty)
                    SizedBox(
                      width: btnW,
                      child: PillButton(
                        label: _playing != null ? ' close resume' : ' resume reel',
                        icon: Icons.play_arrow,
                        onTap: () => _play(_playing != null ? null : '${_resume.first['key']}'),
                      ),
                    ),
                ],
              ),
              if (_playing != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(aspectRatio: 16 / 9, child: YtPlayer(videoId: _playing!)),
                ),
                if (_resume.length > 1)
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(top: 8),
                      itemCount: _resume.length,
                      separatorBuilder: (context, i) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final key = '${_resume[i]['key']}';
                        return OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: key == _playing ? UkoColors.yellow : UkoColors.border),
                          ),
                          onPressed: () => _play(key),
                          child: Text('${or([_resume[i]['name'], 'reel ${i + 1}'])}',
                              style: TextStyle(color: key == _playing ? UkoColors.yellow : UkoColors.divider)),
                        );
                      },
                    ),
                  ),
              ],
              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('No Eden credits yet.', style: TextStyle(color: UkoColors.divider)),
                ),
              _CreditRow(title: 'Movies · cast', items: list(_movies, 'cast'), onTap: _openCredit),
              _CreditRow(title: 'Movies · crew', items: list(_movies, 'crew'), onTap: _openCredit),
              _CreditRow(title: 'Series · cast', items: list(_series, 'cast'), onTap: _openCredit),
              _CreditRow(title: 'Series · crew', items: list(_series, 'crew'), onTap: _openCredit),
              if (_related.isNotEmpty) _RelatedRow(people: _related, onTap: _openPerson),
            ],
          ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(text,
            style: const TextStyle(color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white)),
      );
}

/// One row of Eden titles the person is credited on; a card opens the Eden title page.
class _CreditRow extends StatelessWidget {
  const _CreditRow({required this.title, required this.items, required this.onTap});
  final String title;
  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final w = MediaQuery.of(context).size.width * 0.34;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(title),
        SizedBox(
          height: w * 1.5 + 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (context, i) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = items[i];
              final role = or([c['character'], c['job']]);
              return SizedBox(
                width: w,
                child: InkWell(
                  onTap: () => onTap(c),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EdenImage(
                        path: '${or([c['poster_path'], c['backdrop_path']]) ?? ''}',
                        width: w,
                        height: w * 1.5,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 4),
                      Text('${or([c['name'], c['title']]) ?? ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                      if (truthy(role))
                        Text('$role',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: UkoColors.divider, fontSize: 12)),
                      if (toNum(c['vote_average']) > 0)
                        Text('★ ${toNum(c['vote_average']).toStringAsFixed(1)}',
                            style: const TextStyle(color: UkoColors.yellow, fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "More from this studio" - the person page's answer to a title's similar row.
class _RelatedRow extends StatelessWidget {
  const _RelatedRow({required this.people, required this.onTap});
  final List<Map<String, dynamic>> people;
  final ValueChanged<Map<String, dynamic>> onTap;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width * 0.34;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('MORE FROM THIS STUDIO'),
        SizedBox(
          height: w * 1.5 + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: people.length,
            separatorBuilder: (context, i) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final o = people[i];
              return SizedBox(
                width: w,
                child: InkWell(
                  onTap: () => onTap(o),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EdenImage(
                        path: truthy(o['profile_path']) ? '${o['profile_path']}' : null,
                        width: w,
                        height: w * 1.5,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 4),
                      Text('${or([o['name'], o['original_name']]) ?? ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                      Text('${toNum(o['followers']).toInt()} followers · ${o['known_for_department'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: UkoColors.divider, fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
