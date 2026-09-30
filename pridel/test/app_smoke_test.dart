import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pridel/app.dart';
import 'package:pridel/controllers/app_controller.dart';
import 'package:pridel/data/app_database.dart';

class _SmokeDatabase extends AppDatabase {
  @override
  Future<bool> getOnboardingComplete() async => false;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('app starts and shows onboarding on a fresh profile',
      (tester) async {
    final controller = AppController(_SmokeDatabase());

    await tester.pumpWidget(PridelApp(controller: controller));
    await tester.pump();

    expect(find.text('PRÍDEL'), findsOneWidget);
    expect(find.text('Menej rozmýšľania, čo variť'), findsOneWidget);
    expect(find.text('Pokračovať'), findsOneWidget);
  });
}
