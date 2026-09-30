import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pridel/data/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  Future<({AppDatabase db, Directory dir})> openTempDb() async {
    final dir = await Directory.systemTemp.createTemp('pridel_db_test_');
    final db = AppDatabase(
      factory: databaseFactoryFfi,
      databasePathProvider: () async => dir.path,
    );
    await db.initialize();
    return (db: db, dir: dir);
  }

  test('database initializes with healthy schema and seed data', () async {
    final env = await openTempDb();
    addTearDown(() async {
      await env.db.close();
      await env.dir.delete(recursive: true);
    });

    expect(await env.db.dataHealthIssues(), isEmpty);
    expect((await env.db.getRecipes()).length, greaterThanOrEqualTo(170));
    expect((await env.db.getIngredients()).length, greaterThanOrEqualTo(170));
  });

  test('backup export and import round-trip preserves user state', () async {
    final source = await openTempDb();
    final target = await openTempDb();
    addTearDown(() async {
      await source.db.close();
      await target.db.close();
      await source.dir.delete(recursive: true);
      await target.dir.delete(recursive: true);
    });

    await source.db.setUsePantry(false);
    await source.db.setPlanHorizonDays(14);
    await source.db.addPantryItem(
      name: 'Ryža',
      qty: 321,
      unit: 'g',
      location: 'pantry',
    );

    final backup = await source.db.exportBackupJson();
    await target.db.importBackupJson(backup);

    expect(await target.db.getUsePantry(), isFalse);
    expect(await target.db.getPlanHorizonDays(), 14);
    final pantry = await target.db.getPantry();
    final rice = pantry.where((item) => item.ingredientName == 'Ryža').toList();
    expect(rice, hasLength(1));
    expect(rice.single.qty, 321);
    expect(rice.single.location, 'pantry');
    expect(await target.db.dataHealthIssues(), isEmpty);
  });
}
