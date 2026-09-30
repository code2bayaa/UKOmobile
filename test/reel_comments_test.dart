// Movies PRD #26 on the phone: the reel like / comment bar and the comments sheet.
// Tests run without --dart-define, so the reels API is "not configured" - which is exactly the failure path.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uko_mobile/widgets/reel_comments.dart';

void main() {
  test('counts are short like the web', () {
    expect(reelCount(0), '0');
    expect(reelCount(999), '999');
    expect(reelCount(1234), '1.2k');
    expect(reelCount(12345), '12k');
    expect(reelCount(null), '0');
  });

  testWidgets('a like shows at once and goes back when it cannot be saved', (tester) async {
    Map<String, dynamic> stat = {'likes': 4, 'comments': 2, 'liked': false};
    final changes = <Map<String, dynamic>>[];
    var commentsOpened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ReelActions(
            reelKey: 'abc',
            stat: stat,
            onChange: (c) => setState(() {
              changes.add(c);
              stat = {...stat, ...c};
            }),
            onComments: () => commentsOpened++,
          ),
        ),
      ),
    ));
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();
    // optimistic +1, then the real state back (the API is not configured in tests)
    expect(changes.first, {'liked': true, 'likes': 5});
    expect(changes.last, {'liked': false, 'likes': 4});
    expect(find.text('4'), findsOneWidget);
    expect(find.textContaining('not configured', findRichText: true), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mode_comment_outlined));
    expect(commentsOpened, 1);
  });

  testWidgets('the comments sheet opens and says when comments cannot load', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReelComments(context, reelKey: 'abc', name: 'Reel', onCount: (_) {}),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Comments'), findsOneWidget);
    expect(find.textContaining('not configured'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Comments'), findsNothing);
  });
}
