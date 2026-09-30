import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uko_mobile/routes.dart';
import 'package:uko_mobile/services/prefs.dart';
import 'package:uko_mobile/services/region.dart';
import 'package:uko_mobile/shell/app_drawer.dart';
import 'package:uko_mobile/widgets/credit_gate.dart';

// earn / buy credits: only signed-in users whose saved location is in Kenya, Brazil or Oceania
Future<void> signIn({String? user, String? iso}) async {
  if (user == null) {
    await Prefs.removeItem(PrefKeys.user);
  } else {
    await Prefs.setItem(PrefKeys.user, user);
  }
  if (iso == null) {
    await Prefs.removeItem(PrefKeys.location);
  } else {
    await Prefs.setItem(PrefKeys.location, jsonEncode([
      {'country': 'x', 'isoCountryCode': iso}
    ]));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('creditsAllowedHere', () {
    for (final (iso, allowed) in [('KE', true), ('BR', true), ('AU', true), ('NZ', true), ('ug', false), ('US', false), ('ZA', false)]) {
      test('$iso -> $allowed', () async {
        await signIn(user: 'a@b.c', iso: iso);
        expect(await creditsAllowedHere(), allowed);
      });
    }
    test('no saved location -> false, never prompts', () async {
      await signIn(user: 'a@b.c');
      expect(await creditsAllowedHere(), false);
    });
  });

  group('drawer', () {
    Future<void> openDrawer(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(drawer: AppDrawer(), body: SizedBox())));
      final ScaffoldState scaffold = tester.firstState(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
    }

    final cases = [
      ('signed in, Kenya', 'a@b.c', 'KE', true),
      ('signed in, Brazil', 'a@b.c', 'BR', true),
      ('signed in, Australia', 'a@b.c', 'AU', true),
      ('signed in, US', 'a@b.c', 'US', false),
      ('signed in, no saved location', 'a@b.c', null, false),
      ('signed out, Kenya', null, 'KE', false),
    ];
    for (final (name, user, iso, shows) in cases) {
      testWidgets('$name -> credit items ${shows ? 'shown' : 'hidden'}', (tester) async {
        await tester.runAsync(() => signIn(user: user, iso: iso));
        await openDrawer(tester);
        expect(find.text('earn credit'), shows ? findsOneWidget : findsNothing);
        expect(find.text('subscribe'), shows ? findsOneWidget : findsNothing);
        expect(find.text('following'), findsOneWidget);
      });
    }
  });

  group('CreditGate', () {
    Future<void> pumpGate(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        initialRoute: Routes.creditsEarn,
        routes: {
          Routes.home: (_) => const Text('HOME'),
          Routes.creditsEarn: (_) => const CreditGate(child: Text('EARN SCREEN')),
        },
      ));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
    }

    testWidgets('signed in, Kenya -> screen', (tester) async {
      await tester.runAsync(() => signIn(user: 'a@b.c', iso: 'KE'));
      await pumpGate(tester);
      expect(find.text('EARN SCREEN'), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
    });

    testWidgets('signed in, US -> sent home', (tester) async {
      await tester.runAsync(() => signIn(user: 'a@b.c', iso: 'US'));
      await pumpGate(tester);
      expect(find.text('EARN SCREEN'), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('signed out, Kenya -> sent home', (tester) async {
      await tester.runAsync(() => signIn(iso: 'KE'));
      await pumpGate(tester);
      expect(find.text('EARN SCREEN'), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
    });
  });
}
