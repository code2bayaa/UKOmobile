import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/http.dart';
import '../../core/util.dart';
import '../../routes.dart';
import '../../services/prefs.dart';
import '../../widgets/common.dart';
import '../../widgets/eden_image.dart';
import '../../widgets/picture.dart';
import '../../widgets/sweet_page.dart';
import '../../core/theme.dart';

/// Port of app/(tabs)/following.tsx.
class FollowingScreen extends StatefulWidget {
  const FollowingScreen({super.key, this.params = const {}});
  final Map<String, dynamic> params;

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  dynamic _count = 0;
  List<Map<String, dynamic>> _results = [];
  int _page = 1;
  int _totalPages = 0;

  /// Eden studio people the viewer follows (person_followers) - their own row, opened at /eden/people/id.
  List<Map<String, dynamic>> _eden = [];

  @override
  void initState() {
    super.initState();
    _initializePeople(1);
  }

  Future<void> _initializePeople(int page) async {
    if (page > 1) setState(() => _page = page);

    final data = await Http.postJson(Api.following, {
      'page': page,
      'email': await Prefs.user,
    });
    if (!mounted || data is! Map) return;
    final results = data['results'];
    if (truthy(data['success'])) setState(() => _eden = asMapList(data['eden']));
    if (truthy(data['success']) && results is List && results.isNotEmpty) {
      setState(() {
        // NOTE: RN uses the follow *count* as the number of pages.
        _totalPages = toNum(data['count']).toInt();
        _count = data['count'];
        _results = asMapList(results);
        _page = page;
      });
    } else if (truthy(data['error'])) {
      showUkoAlert(context, 'Error', '${data['error']}');
    } else if (_eden.isEmpty && (results == 0 || (results is List && results.isEmpty))) {
      showUkoAlert(context, 'Empty', 'follow more people');
    }
  }

  void _navRoute(Map<String, dynamic> state) {
    // phone only - the TV app has no People pages to mirror
    Nav.replace(context, Routes.peopleId, state);
  }

  void _openEden(Map<String, dynamic> person) {
    final state = {'id': person['id'], 'person_id': person['person_id'], 'eden': true};
    Nav.push(context, Routes.edenPeopleId, state);
  }

  /// The user service reads the app token, so only the viewer's own follow can go.
  Future<void> _removeEden(Map<String, dynamic> person) async {
    final data = await Http.postJson(Api.edenUnfollow, {'person_id': person['person_id']});
    if (!mounted) return;
    if (data is Map && data['status'] == true) {
      setState(() => _eden = _eden.where((p) => p['person_id'] != person['person_id']).toList());
      showUkoAlert(context, 'success', 'Unfollowed');
    } else {
      showUkoAlert(context, 'Error', 'could not remove, try later');
    }
  }

  Widget _renderEden(Map<String, dynamic> person) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 180,
          width: double.infinity,
          child: InkWell(
            onTap: () => _openEden(person),
            child: EdenImage(path: truthy(person['profile_path']) ? '${person['profile_path']}' : null),
          ),
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
          child: LayoutBuilder(
            builder: (context, c) => Row(
              children: [
                _pill(c.maxWidth * 0.48, UkoColors.green, 'read', () => _openEden(person)),
                const SizedBox(width: 1),
                _pill(c.maxWidth * 0.48, UkoColors.red, 'unfollow', () => _removeEden(person)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _removeFollowing(dynamic id) async {
    final data = await Http.postJson(Api.removeFollowing, {
      'id': id,
      'email': await Prefs.user,
    });
    if (!mounted) return;
    if (data is Map && truthy(data['status'])) {
      // the server deleted the follow by this person's id - drop the card
      setState(() => _results = _results.where((p) => '${p['id']}' != '$id').toList());
      showUkoAlert(context, 'success', 'Unfollowed');
    } else if (data is Map && truthy(data['error'])) {
      showUkoAlert(context, 'Error', '${data['error']}');
    } else {
      showUkoAlert(context, 'Error', 'could not remove, try later');
    }
  }

  Widget _renderCredits(Map<String, dynamic> item) {
    final name = truthy(item['name']) ? item['name'] : (truthy(item['original_name']) ? item['original_name'] : item['name']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 180,
          width: double.infinity,
          child: Picture(picture: truthy(item['profile_path']) ? '${item['profile_path']}' : ''),
        ),
        SizedBox(
          height: 25,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${name ?? ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: UkoColors.divider, width: 2)),
          ),
          child: LayoutBuilder(
            builder: (context, c) => Row(
              children: [
                _pill(c.maxWidth * 0.48, UkoColors.green, 'read', () => _navRoute({'id': item.idInt})),
                const SizedBox(width: 1),
                _pill(c.maxWidth * 0.48, UkoColors.red, 'unfollow', () => _removeFollowing(item['id'])),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(double width, Color color, String label, VoidCallback onTap) => SizedBox(
        width: width,
        height: 30,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (_results.isEmpty && _eden.isEmpty) {
      return Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/images/followers.png', fit: BoxFit.contain)),
          const Align(
            alignment: Alignment.topCenter,
            child: Text('Not following anyone', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    }
    final itemWidth = w * 0.45;
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 128),
      children: [
        if (_eden.isNotEmpty) ...[
          Text('Eden Studios : ${_eden.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _eden.length,
              separatorBuilder: (context, i) => const SizedBox(width: 6),
              itemBuilder: (context, i) => SizedBox(width: itemWidth, child: _renderEden(_eden[i])),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_results.isNotEmpty) ...[
          Text('following : $_count', style: const TextStyle(color: Colors.white)),
          SweetPage(page: _page, totalPages: _totalPages, onPageChange: _initializePeople),
          const SizedBox(height: 8),
          Wrap(
            children: [
              for (final item in _results)
                SizedBox(width: itemWidth, height: 250, child: _renderCredits(item)),
            ],
          ),
        ],
      ],
    );
  }
}
