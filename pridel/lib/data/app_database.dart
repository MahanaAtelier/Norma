import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/app_alert.dart';
import '../models/household_member.dart';
import '../models/ingredient.dart';
import '../models/leftover.dart';
import '../models/meal_entry.dart';
import '../models/pantry_item.dart';
import '../models/planning.dart';
import '../models/recipe.dart';
import '../services/meal_math.dart';
import '../utils/date_utils.dart';
import '../utils/unit_math.dart';

class AppDatabase {
  AppDatabase(
      {DatabaseFactory? factory,
      Future<String> Function()? databasePathProvider})
      : _factory = factory ?? databaseFactory,
        _databasePathProvider = databasePathProvider ?? getDatabasesPath;

  static const schemaVersion = 5;
  static const seedVersion = 4;
  final DatabaseFactory _factory;
  final Future<String> Function() _databasePathProvider;
  Database? _db;

  Database get db {
    final value = _db;
    if (value == null) throw StateError('Databáza ešte nie je inicializovaná.');
    return value;
  }

  Future<void> initialize() async {
    final base = await _databasePathProvider();
    _db = await _factory.openDatabase(
      p.join(base, 'pridel.db'),
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) async {
          // Sqflite treats PRAGMA statements as queries. Using execute() here
          // crashes on Android with 'Queries can be performed using query or rawQuery'.
          await database.rawQuery('PRAGMA foreign_keys = ON');
          await database.rawQuery('PRAGMA journal_mode = WAL');
          await database.rawQuery('PRAGMA synchronous = NORMAL');
          await database.rawQuery('PRAGMA busy_timeout = 2500');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    await _createIndices(db);
    await _syncSeedDataIfNeeded();
    await _ensureDefaultHousehold();
    await _repairRecoverableState();
  }

  Future<void> close() async {
    final value = _db;
    _db = null;
    await value?.close();
  }

  Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE ingredients(
        name TEXT PRIMARY KEY,
        unit TEXT NOT NULL,
        category TEXT NOT NULL,
        pack REAL,
        pack_price REAL,
        kcal REAL,
        allergens TEXT NOT NULL DEFAULT '',
        buy INTEGER NOT NULL DEFAULT 1,
        tags_json TEXT NOT NULL DEFAULT '[]'
      )
    ''');
    await database.execute('''
      CREATE TABLE recipes(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        meal_use TEXT NOT NULL DEFAULT '',
        adult_kcal REAL,
        child_kcal REAL,
        allergens TEXT NOT NULL DEFAULT '',
        step TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        prep_min INTEGER,
        is_custom INTEGER NOT NULL DEFAULT 0,
        source_basis TEXT NOT NULL DEFAULT '',
        source_url TEXT NOT NULL DEFAULT '',
        tags_json TEXT NOT NULL DEFAULT '[]'
      )
    ''');
    await database.execute('''
      CREATE TABLE recipe_ingredients(
        recipe_id TEXT NOT NULL,
        ingredient_name TEXT NOT NULL,
        unit TEXT NOT NULL,
        adult_qty REAL NOT NULL DEFAULT 0,
        child_qty REAL NOT NULL DEFAULT 0,
        PRIMARY KEY(recipe_id, ingredient_name),
        FOREIGN KEY(recipe_id) REFERENCES recipes(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE pantry(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ingredient_name TEXT NOT NULL,
        qty REAL NOT NULL CHECK(qty >= 0),
        unit TEXT NOT NULL,
        expiry TEXT,
        added_at TEXT NOT NULL,
        location TEXT NOT NULL DEFAULT 'pantry'
      )
    ''');
    await database.execute('''
      CREATE TABLE household_members(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'adult',
        portion REAL NOT NULL DEFAULT 1.0 CHECK(portion > 0),
        active INTEGER NOT NULL DEFAULT 1,
        allergens TEXT NOT NULL DEFAULT '',
        dislikes TEXT NOT NULL DEFAULT ''
      )
    ''');
    await database.execute('''
      CREATE TABLE meal_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        meal_type TEXT NOT NULL,
        recipe_id TEXT,
        status TEXT NOT NULL DEFAULT 'planned',
        snapshot_json TEXT,
        servings_json TEXT NOT NULL DEFAULT '[]',
        consumption_json TEXT NOT NULL DEFAULT '[]',
        leftover_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(date, meal_type)
      )
    ''');
    await database.execute('''
      CREATE TABLE leftovers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_meal_id INTEGER,
        recipe_id TEXT,
        recipe_name TEXT NOT NULL,
        portions REAL NOT NULL CHECK(portions >= 0),
        created_at TEXT NOT NULL,
        use_by TEXT,
        status TEXT NOT NULL DEFAULT 'available',
        snapshot_json TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE shopping_checks(
        week_key TEXT NOT NULL,
        ingredient_name TEXT NOT NULL,
        checked INTEGER NOT NULL DEFAULT 0,
        qty REAL NOT NULL DEFAULT 0,
        unit TEXT NOT NULL DEFAULT '',
        PRIMARY KEY(week_key, ingredient_name)
      )
    ''');
    await database.execute('''
      CREATE TABLE shopping_manual(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        week_key TEXT NOT NULL,
        name TEXT NOT NULL,
        qty REAL NOT NULL DEFAULT 1,
        unit TEXT NOT NULL DEFAULT 'ks',
        checked INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await database.execute('''
      CREATE TABLE recipe_preferences(
        recipe_id TEXT PRIMARY KEY,
        favorite INTEGER NOT NULL DEFAULT 0,
        blocked INTEGER NOT NULL DEFAULT 0,
        cooldown_until TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE alert_dismissals(
        alert_key TEXT PRIMARY KEY,
        dismissed_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE error_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message TEXT NOT NULL,
        stack TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await database.insert('settings', {'key': 'use_pantry', 'value': 'true'});
    await database
        .insert('settings', {'key': 'onboarding_complete', 'value': 'false'});
    await database
        .insert('settings', {'key': 'in_app_alerts', 'value': 'true'});
    await database
        .insert('settings', {'key': 'plan_horizon_days', 'value': '7'});
  }

  Future<void> _upgradeSchema(
      Database database, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(
          database, 'ingredients', "tags_json TEXT NOT NULL DEFAULT '[]'");
      await _addColumnIfMissing(
          database, 'recipes', "source_basis TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(
          database, 'recipes', "source_url TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(
          database, 'recipes', "tags_json TEXT NOT NULL DEFAULT '[]'");
      await _addColumnIfMissing(database, 'pantry', "added_at TEXT");
      await _addColumnIfMissing(
          database, 'household_members', "allergens TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(
          database, 'household_members', "dislikes TEXT NOT NULL DEFAULT ''");
      await _addColumnIfMissing(
          database, 'meal_entries', "servings_json TEXT NOT NULL DEFAULT '[]'");
      await _addColumnIfMissing(database, 'meal_entries',
          "consumption_json TEXT NOT NULL DEFAULT '[]'");
      await _addColumnIfMissing(
          database, 'meal_entries', 'leftover_id INTEGER');
      await _addColumnIfMissing(database, 'meal_entries', "created_at TEXT");
      await _addColumnIfMissing(database, 'meal_entries', "updated_at TEXT");
      await _addColumnIfMissing(
          database, 'leftovers', 'source_meal_id INTEGER');
      await _addColumnIfMissing(database, 'leftovers', 'snapshot_json TEXT');
      await database.execute('''
        CREATE TABLE IF NOT EXISTS recipe_preferences(
          recipe_id TEXT PRIMARY KEY,
          favorite INTEGER NOT NULL DEFAULT 0,
          blocked INTEGER NOT NULL DEFAULT 0,
          cooldown_until TEXT
        )
      ''');
      await database.execute('''
        CREATE TABLE IF NOT EXISTS shopping_manual(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          week_key TEXT NOT NULL,
          name TEXT NOT NULL,
          qty REAL NOT NULL DEFAULT 1,
          unit TEXT NOT NULL DEFAULT 'ks',
          checked INTEGER NOT NULL DEFAULT 0
        )
      ''');
      final now = DateTime.now().toIso8601String();
      await database.rawUpdate(
          "UPDATE pantry SET added_at = ? WHERE added_at IS NULL OR added_at = ''",
          [now]);
      await database.rawUpdate(
          "UPDATE meal_entries SET created_at = ? WHERE created_at IS NULL OR created_at = ''",
          [now]);
      await database.rawUpdate(
          "UPDATE meal_entries SET updated_at = ? WHERE updated_at IS NULL OR updated_at = ''",
          [now]);
    }
    if (oldVersion < 3) {
      await database.execute(
          'DELETE FROM meal_entries WHERE id NOT IN (SELECT MAX(id) FROM meal_entries GROUP BY date, meal_type)');
      await database.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_meal_date_type ON meal_entries(date, meal_type)');
    }
    if (oldVersion < 4) {
      await _addColumnIfMissing(
          database, 'shopping_checks', 'qty REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          database, 'shopping_checks', "unit TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 5) {
      await _addColumnIfMissing(
          database, 'pantry', "location TEXT NOT NULL DEFAULT 'pantry'");
      await database.execute('''
        CREATE TABLE IF NOT EXISTS alert_dismissals(
          alert_key TEXT PRIMARY KEY,
          dismissed_at TEXT NOT NULL
        )
      ''');
      await database.execute('''
        CREATE TABLE IF NOT EXISTS error_log(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          message TEXT NOT NULL,
          stack TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL
        )
      ''');
      await database.insert(
          'settings', {'key': 'onboarding_complete', 'value': 'true'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await database.insert(
          'settings', {'key': 'in_app_alerts', 'value': 'true'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await database.insert(
          'settings', {'key': 'plan_horizon_days', 'value': '7'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await database.rawUpdate('''
        UPDATE pantry
        SET location = CASE
          WHEN lower(ingredient_name) LIKE '%mrazen%' THEN 'freezer'
          WHEN ingredient_name IN (
            SELECT name FROM ingredients
            WHERE lower(category) LIKE '%mäso%'
               OR lower(category) LIKE '%ryb%'
               OR lower(category) LIKE '%mlieč%'
               OR lower(category) LIKE '%vajc%'
               OR lower(category) LIKE '%chladen%'
               OR lower(category) LIKE '%zelenina%'
          ) THEN 'fridge'
          ELSE 'pantry'
        END
      ''');
    }
  }

  Future<void> _addColumnIfMissing(
      Database database, String table, String definition) async {
    final column = definition.trim().split(RegExp(r'\s+')).first;
    final info = await database.rawQuery('PRAGMA table_info($table)');
    if (info.any((row) => row['name'] == column)) return;
    await database.execute('ALTER TABLE $table ADD COLUMN $definition');
  }

  Future<void> _createIndices(Database database) async {
    await database.execute(
        'CREATE INDEX IF NOT EXISTS idx_recipe_ingredient_name ON recipe_ingredients(ingredient_name)');
    await database.execute(
        'CREATE INDEX IF NOT EXISTS idx_pantry_name ON pantry(ingredient_name)');
    await database.execute(
        'CREATE INDEX IF NOT EXISTS idx_pantry_expiry ON pantry(expiry)');
    await database.execute(
        'CREATE INDEX IF NOT EXISTS idx_meal_date ON meal_entries(date)');
    await database.execute(
        'DELETE FROM meal_entries WHERE id NOT IN (SELECT MAX(id) FROM meal_entries GROUP BY date, meal_type)');
    await database.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_meal_date_type ON meal_entries(date, meal_type)');
    await database.execute(
        'CREATE INDEX IF NOT EXISTS idx_leftover_status_useby ON leftovers(status, use_by)');
  }

  Future<void> _repairRecoverableState() async {
    await db.transaction((txn) async {
      await txn.rawUpdate('''
        UPDATE leftovers
        SET status = 'available'
        WHERE status = 'reserved'
          AND id NOT IN (
            SELECT leftover_id
            FROM meal_entries
            WHERE leftover_id IS NOT NULL AND status = 'planned'
          )
      ''');
      await txn.rawUpdate("UPDATE pantry SET qty = 0 WHERE qty < 0");
    });
  }

  Future<void> _syncSeedDataIfNeeded() async {
    final rows = await db.query('settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['seed_version'],
        limit: 1);
    final current = rows.isEmpty
        ? null
        : int.tryParse((rows.first['value'] as String?) ?? '');
    if (current == seedVersion) return;
    await _syncSeedData();
    await db.insert(
      'settings',
      {'key': 'seed_version', 'value': seedVersion.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _syncSeedData() async {
    final ingredientJson =
        jsonDecode(await rootBundle.loadString('assets/data/ingredients.json'))
            as Map<String, dynamic>;
    final recipeJson =
        jsonDecode(await rootBundle.loadString('assets/data/recipes.json'))
            as List<dynamic>;

    await db.transaction((txn) async {
      for (final entry in ingredientJson.entries) {
        final name = entry.key;
        final value = Map<String, dynamic>.from(entry.value as Map);
        final existing = await txn.query('ingredients',
            columns: ['name'], where: 'name = ?', whereArgs: [name], limit: 1);
        if (existing.isEmpty) {
          await txn.insert('ingredients', {
            'name': name,
            'unit': value['unit'] ?? 'g',
            'category': value['category'] ?? 'Ostatné',
            'pack': value['pack'],
            'pack_price': value['pack_price'],
            'kcal': value['kcal'],
            'allergens': value['allergens'] ?? '',
            'buy': value['buy'] == false ? 0 : 1,
            'tags_json': jsonEncode(value['tags'] ?? const []),
          });
        } else {
          await txn.update(
              'ingredients',
              {
                'unit': value['unit'] ?? 'g',
                'category': value['category'] ?? 'Ostatné',
                'kcal': value['kcal'],
                'allergens': value['allergens'] ?? '',
                'buy': value['buy'] == false ? 0 : 1,
                'tags_json': jsonEncode(value['tags'] ?? const []),
              },
              where: 'name = ?',
              whereArgs: [name]);
          await txn.rawUpdate(
            'UPDATE ingredients SET pack = COALESCE(pack, ?), pack_price = COALESCE(pack_price, ?) WHERE name = ?',
            [value['pack'], value['pack_price'], name],
          );
        }
      }

      for (final raw in recipeJson) {
        final value = Map<String, dynamic>.from(raw as Map);
        final id = value['id'].toString();
        final custom = await txn.query('recipes',
            columns: ['is_custom'], where: 'id = ?', whereArgs: [id], limit: 1);
        if (custom.isNotEmpty && custom.first['is_custom'] == 1) continue;
        await txn.delete('recipe_ingredients',
            where: 'recipe_id = ?', whereArgs: [id]);
        await txn.insert(
            'recipes',
            {
              'id': id,
              'name': value['name'],
              'category': value['category'] ?? 'Ostatné',
              'meal_use': value['meal_use'] ?? '',
              'adult_kcal': value['adult_kcal'],
              'child_kcal': value['child_kcal'],
              'allergens': value['allergens'] ?? '',
              'step': value['step'] ?? '',
              'note': value['note'] ?? '',
              'prep_min': value['prep_min'],
              'is_custom': 0,
              'source_basis': value['source_basis'] ?? '',
              'source_url': value['source_url'] ?? '',
              'tags_json': jsonEncode(value['tags'] ?? const []),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        for (final ingredientRaw
            in (value['ingredients'] as List<dynamic>? ?? const [])) {
          final ri = Map<String, dynamic>.from(ingredientRaw as Map);
          await txn.insert(
              'recipe_ingredients',
              {
                'recipe_id': id,
                'ingredient_name': ri['ingredient'],
                'unit': ri['unit'] ?? 'g',
                'adult_qty': (ri['adult_qty'] as num?)?.toDouble() ?? 0,
                'child_qty': (ri['child_qty'] as num?)?.toDouble() ?? 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  Future<void> _ensureDefaultHousehold() async {
    final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM household_members')) ??
        0;
    if (count == 0) {
      await db.insert('household_members', {
        'name': 'Dospelý 1',
        'role': 'adult',
        'portion': 1.0,
        'active': 1,
        'allergens': '',
        'dislikes': '',
      });
    }
  }

  // Settings
  Future<String?> getSetting(String key) async {
    final rows = await db.query('settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> getUsePantry() async =>
      (await getSetting('use_pantry')) != 'false';
  Future<void> setUsePantry(bool value) =>
      setSetting('use_pantry', value ? 'true' : 'false');
  Future<bool> getOnboardingComplete() async =>
      (await getSetting('onboarding_complete')) == 'true';
  Future<void> setOnboardingComplete(bool value) =>
      setSetting('onboarding_complete', value ? 'true' : 'false');
  Future<bool> getInAppAlertsEnabled() async =>
      (await getSetting('in_app_alerts')) != 'false';
  Future<void> setInAppAlertsEnabled(bool value) =>
      setSetting('in_app_alerts', value ? 'true' : 'false');
  Future<int> getPlanHorizonDays() async {
    final value =
        int.tryParse(await getSetting('plan_horizon_days') ?? '') ?? 7;
    return value.clamp(7, 28).toInt();
  }

  Future<void> setPlanHorizonDays(int value) =>
      setSetting('plan_horizon_days', value.clamp(7, 28).toString());

  Future<PlanningPreferences> getPlanningPreferences() async =>
      PlanningPreferences(
        fishPerWeek: int.tryParse(await getSetting('fish_per_week') ?? '') ?? 1,
        vegetarianMainsPerWeek:
            int.tryParse(await getSetting('vegetarian_mains') ?? '') ?? 2,
        legumeMainsPerWeek:
            int.tryParse(await getSetting('legume_mains') ?? '') ?? 1,
        maxSweetMainsPerWeek:
            int.tryParse(await getSetting('max_sweet_mains') ?? '') ?? 1,
        minFruitDaysPerWeek:
            int.tryParse(await getSetting('min_fruit_days') ?? '') ?? 5,
        minVegetableMainDaysPerWeek:
            int.tryParse(await getSetting('min_vegetable_main_days') ?? '') ??
                5,
        maxSameProteinStreak:
            int.tryParse(await getSetting('max_same_protein_streak') ?? '') ??
                2,
        avoidRepeatDays:
            int.tryParse(await getSetting('avoid_repeat_days') ?? '') ?? 21,
        preferQuickWeekdays:
            (await getSetting('prefer_quick_weekdays')) != 'false',
      );

  Future<void> setPlanningPreferences(PlanningPreferences value) async {
    await db.transaction((txn) async {
      Future<void> put(String key, String value) =>
          txn.insert('settings', {'key': key, 'value': value},
              conflictAlgorithm: ConflictAlgorithm.replace);
      await put('fish_per_week', value.fishPerWeek.toString());
      await put('vegetarian_mains', value.vegetarianMainsPerWeek.toString());
      await put('legume_mains', value.legumeMainsPerWeek.toString());
      await put('max_sweet_mains', value.maxSweetMainsPerWeek.toString());
      await put('min_fruit_days', value.minFruitDaysPerWeek.toString());
      await put('min_vegetable_main_days',
          value.minVegetableMainDaysPerWeek.toString());
      await put(
          'max_same_protein_streak', value.maxSameProteinStreak.toString());
      await put('avoid_repeat_days', value.avoidRepeatDays.toString());
      await put('prefer_quick_weekdays',
          value.preferQuickWeekdays ? 'true' : 'false');
    });
  }

  // Ingredients and recipes
  Future<List<IngredientDefinition>> getIngredients() async {
    final rows = await db.query('ingredients',
        orderBy: 'category COLLATE NOCASE, name COLLATE NOCASE');
    return rows.map(IngredientDefinition.fromMap).toList(growable: false);
  }

  Future<IngredientDefinition?> getIngredient(String name) async {
    final rows = await db.query('ingredients',
        where: 'name = ?', whereArgs: [name], limit: 1);
    return rows.isEmpty ? null : IngredientDefinition.fromMap(rows.first);
  }

  Future<void> setIngredientPrice(String name,
      {double? pack, double? packPrice}) async {
    await db.update('ingredients', {'pack': pack, 'pack_price': packPrice},
        where: 'name = ?', whereArgs: [name]);
  }

  Future<List<Recipe>> getRecipes() async {
    final recipeRows =
        await db.query('recipes', orderBy: 'name COLLATE NOCASE');
    return _hydrateRecipes(recipeRows);
  }

  Future<Recipe?> getRecipe(String id) async {
    final rows =
        await db.query('recipes', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final hydrated = await _hydrateRecipes(rows);
    return hydrated.firstOrNull;
  }

  Future<List<Recipe>> getRecipesContainingIngredient(String ingredient) async {
    final ids = await db.query('recipe_ingredients',
        columns: ['recipe_id'],
        where: 'ingredient_name = ?',
        whereArgs: [ingredient]);
    if (ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final values = ids.map((e) => e['recipe_id']).toList(growable: false);
    final rows = await db.rawQuery(
        'SELECT * FROM recipes WHERE id IN ($placeholders) ORDER BY name COLLATE NOCASE',
        values);
    return _hydrateRecipes(rows);
  }

  Future<List<Recipe>> _hydrateRecipes(
      List<Map<String, Object?>> recipeRows) async {
    if (recipeRows.isEmpty) return const [];
    final ids = recipeRows.map((e) => e['id']).toList(growable: false);
    final placeholders = List.filled(ids.length, '?').join(',');
    final ingredientRows = await db.rawQuery(
        'SELECT * FROM recipe_ingredients WHERE recipe_id IN ($placeholders)',
        ids);
    final grouped = <String, List<RecipeIngredient>>{};
    for (final row in ingredientRows) {
      grouped.putIfAbsent(row['recipe_id'] as String, () => []).add(
            RecipeIngredient(
              ingredient: row['ingredient_name'] as String,
              unit: row['unit'] as String,
              adultQty: (row['adult_qty'] as num).toDouble(),
              childQty: (row['child_qty'] as num).toDouble(),
            ),
          );
    }
    return recipeRows.map((row) {
      List<String> tags = const [];
      try {
        tags = ((jsonDecode((row['tags_json'] as String?) ?? '[]')
                as List<dynamic>))
            .map((e) => e.toString())
            .toList(growable: false);
      } catch (_) {}
      return Recipe(
        id: row['id'] as String,
        name: row['name'] as String,
        category: row['category'] as String,
        mealUse: (row['meal_use'] as String?) ?? '',
        adultKcal: (row['adult_kcal'] as num?)?.toDouble(),
        childKcal: (row['child_kcal'] as num?)?.toDouble(),
        allergens: (row['allergens'] as String?) ?? '',
        step: (row['step'] as String?) ?? '',
        note: (row['note'] as String?) ?? '',
        prepMin: (row['prep_min'] as num?)?.toInt(),
        isCustom: (row['is_custom'] as int? ?? 0) == 1,
        ingredients: grouped[row['id'] as String] ?? const [],
        tags: tags,
        sourceBasis: (row['source_basis'] as String?) ?? '',
        sourceUrl: (row['source_url'] as String?) ?? '',
      );
    }).toList(growable: false);
  }

  Future<void> saveCustomRecipe(Recipe recipe) async {
    if (recipe.name.trim().length < 2 || recipe.ingredients.isEmpty)
      throw ArgumentError('Recept nemá platný názov alebo suroviny.');
    await db.transaction((txn) async {
      await txn.insert(
          'recipes',
          {
            'id': recipe.id,
            'name': recipe.name.trim(),
            'category': recipe.category,
            'meal_use': recipe.mealUse,
            'adult_kcal': recipe.adultKcal,
            'child_kcal': recipe.childKcal,
            'allergens': recipe.allergens,
            'step': recipe.step,
            'note': recipe.note,
            'prep_min': recipe.prepMin,
            'is_custom': 1,
            'source_basis': recipe.sourceBasis,
            'source_url': recipe.sourceUrl,
            'tags_json': jsonEncode(recipe.tags),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('recipe_ingredients',
          where: 'recipe_id = ?', whereArgs: [recipe.id]);
      for (final item in recipe.ingredients) {
        if (item.adultQty < 0 || item.childQty < 0)
          throw ArgumentError('Množstvo suroviny nemôže byť záporné.');
        final existing = await txn.query('ingredients',
            where: 'name = ?', whereArgs: [item.ingredient], limit: 1);
        String unit = UnitMath.normalizeUnit(item.unit);
        if (existing.isNotEmpty) {
          final knownUnit = existing.first['unit'] as String;
          if (!UnitMath.compatible(unit, knownUnit))
            throw ArgumentError(
                'Surovina ${item.ingredient} používa jednotku $knownUnit.');
          unit = knownUnit;
        } else {
          await txn.insert('ingredients', {
            'name': item.ingredient,
            'unit': unit,
            'category': 'Ostatné',
            'allergens': '',
            'buy': 1,
            'tags_json': '[]',
          });
        }
        await txn.insert('recipe_ingredients', {
          'recipe_id': recipe.id,
          'ingredient_name': item.ingredient,
          'unit': unit,
          'adult_qty': item.adultQty,
          'child_qty': item.childQty,
        });
      }
    });
  }

  Future<void> deleteCustomRecipe(String id) async {
    await db
        .delete('recipes', where: 'id = ? AND is_custom = 1', whereArgs: [id]);
  }

  Future<Recipe> duplicateAsCustom(Recipe source) async {
    final copy = source.copyWith(
      id: 'U${DateTime.now().microsecondsSinceEpoch}',
      name: '${source.name} – moja verzia',
      isCustom: true,
      sourceBasis: '',
      sourceUrl: '',
    );
    await saveCustomRecipe(copy);
    return copy;
  }

  // Recipe preferences
  Future<Map<String, RecipePreference>> getRecipePreferences() async {
    final rows = await db.query('recipe_preferences');
    return {
      for (final row in rows)
        row['recipe_id'] as String: RecipePreference(
          favorite: (row['favorite'] as int? ?? 0) == 1,
          blocked: (row['blocked'] as int? ?? 0) == 1,
          cooldownUntil: row['cooldown_until'] == null
              ? null
              : DateTime.tryParse(row['cooldown_until'] as String),
        )
    };
  }

  Future<RecipePreference> getRecipePreference(String recipeId) async {
    final rows = await db.query('recipe_preferences',
        where: 'recipe_id = ?', whereArgs: [recipeId], limit: 1);
    if (rows.isEmpty)
      return const RecipePreference(favorite: false, blocked: false);
    final row = rows.first;
    return RecipePreference(
      favorite: (row['favorite'] as int? ?? 0) == 1,
      blocked: (row['blocked'] as int? ?? 0) == 1,
      cooldownUntil: row['cooldown_until'] == null
          ? null
          : DateTime.tryParse(row['cooldown_until'] as String),
    );
  }

  Future<void> setRecipeFavorite(String recipeId, bool value) async {
    final current = await getRecipePreference(recipeId);
    await _putRecipePreference(recipeId, current: current, favorite: value);
  }

  Future<void> setRecipeBlocked(String recipeId, bool value) async {
    final current = await getRecipePreference(recipeId);
    await _putRecipePreference(recipeId, current: current, blocked: value);
  }

  Future<void> setRecipeCooldown(String recipeId, DateTime? until) async {
    final current = await getRecipePreference(recipeId);
    await db.insert(
        'recipe_preferences',
        {
          'recipe_id': recipeId,
          'favorite': current.favorite ? 1 : 0,
          'blocked': current.blocked ? 1 : 0,
          'cooldown_until': until?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _putRecipePreference(String recipeId,
      {required RecipePreference current,
      bool? favorite,
      bool? blocked}) async {
    await db.insert(
        'recipe_preferences',
        {
          'recipe_id': recipeId,
          'favorite': (favorite ?? current.favorite) ? 1 : 0,
          'blocked': (blocked ?? current.blocked) ? 1 : 0,
          'cooldown_until': current.cooldownUntil?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Household
  Future<List<HouseholdMember>> getHousehold({bool activeOnly = false}) async {
    final rows = await db.query('household_members',
        where: activeOnly ? 'active = 1' : null, orderBy: 'id');
    return rows.map(HouseholdMember.fromMap).toList(growable: false);
  }

  Future<int> saveHouseholdMember(
      {int? id,
      required String name,
      required String role,
      required double portion,
      bool active = true,
      String allergens = '',
      String dislikes = ''}) async {
    if (name.trim().isEmpty || portion <= 0 || portion > 3)
      throw ArgumentError('Neplatné údaje člena domácnosti.');
    if (id != null && !active) {
      final current = await db.query('household_members',
          where: 'id = ?', whereArgs: [id], limit: 1);
      if (current.isNotEmpty && current.first['active'] == 1) {
        final activeCount = Sqflite.firstIntValue(await db.rawQuery(
                'SELECT COUNT(*) FROM household_members WHERE active = 1')) ??
            0;
        if (activeCount <= 1)
          throw StateError(
              'V plánovaní musí zostať aspoň jeden aktívny člen domácnosti.');
      }
    }
    final data = {
      'name': name.trim(),
      'role': role == 'child' ? 'child' : 'adult',
      'portion': portion,
      'active': active ? 1 : 0,
      'allergens': allergens.trim(),
      'dislikes': dislikes.trim(),
    };
    if (id == null) return db.insert('household_members', data);
    await db
        .update('household_members', data, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<void> deleteHouseholdMember(int id) async {
    final count = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM household_members WHERE active = 1')) ??
        0;
    final rows = await db.query('household_members',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty && rows.first['active'] == 1 && count <= 1)
      throw StateError('V domácnosti musí zostať aspoň jeden aktívny člen.');
    await db.delete('household_members', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<MealServing>> defaultServings() async {
    var members = await getHousehold(activeOnly: true);
    if (members.isEmpty) {
      final all = await getHousehold();
      if (all.isNotEmpty) members = [all.first];
    }
    return members
        .map((m) => MealServing(
            memberId: m.id,
            name: m.name,
            role: m.role,
            portion: m.portion,
            eating: true))
        .toList(growable: false);
  }

  // Pantry
  Future<List<PantryItem>> getPantry({String? location}) async {
    final rows = await db.query(
      'pantry',
      where: location == null ? null : 'location = ?',
      whereArgs: location == null ? null : [location],
      orderBy:
          "CASE WHEN expiry IS NULL THEN 1 ELSE 0 END, expiry, ingredient_name COLLATE NOCASE",
    );
    return rows.map(PantryItem.fromMap).toList(growable: false);
  }

  String defaultStorageLocation(IngredientDefinition? def, String name) {
    final category = (def?.category ?? '').toLowerCase();
    final text =
        '${def?.name ?? name} $category ${(def?.tags ?? const <String>[]).join(' ')}'
            .toLowerCase();
    if (text.contains('mrazen') || text.contains('frozen')) return 'freezer';
    if (category.contains('mäso') ||
        category.contains('ryb') ||
        category.contains('mlieč') ||
        category.contains('vajc') ||
        category.contains('chladen') ||
        category.contains('zelenina')) {
      return 'fridge';
    }
    return 'pantry';
  }

  Future<int> addPantryItem({
    required String name,
    required double qty,
    required String unit,
    DateTime? expiry,
    String? location,
  }) async {
    if (qty <= 0 || qty.isNaN || qty.isInfinite)
      throw ArgumentError('Množstvo musí byť väčšie ako nula.');
    final def = await getIngredient(name);
    final targetUnit = def?.unit ?? UnitMath.normalizeUnit(unit);
    double targetQty = qty;
    if (def != null) {
      if (!UnitMath.compatible(unit, def.unit))
        throw ArgumentError('Surovina $name používa jednotku ${def.unit}.');
      targetQty = UnitMath.convert(qty, unit, def.unit);
    }
    return db.insert('pantry', {
      'ingredient_name': name.trim(),
      'qty': targetQty,
      'unit': targetUnit,
      'expiry': expiry == null ? null : PridelDates.iso(expiry),
      'added_at': DateTime.now().toIso8601String(),
      'location': location ?? defaultStorageLocation(def, name),
    });
  }

  Future<void> updatePantryItem(PantryItem item,
      {required double qty, DateTime? expiry, String? location}) async {
    if (qty < 0 || qty.isNaN || qty.isInfinite)
      throw ArgumentError('Neplatné množstvo.');
    if (qty == 0) {
      await deletePantryItem(item.id);
      return;
    }
    await db.update(
        'pantry',
        {
          'qty': qty,
          'expiry': expiry == null ? null : PridelDates.iso(expiry),
          'location': location ?? item.location,
        },
        where: 'id = ?',
        whereArgs: [item.id]);
  }

  Future<void> deletePantryItem(int id) async =>
      db.delete('pantry', where: 'id = ?', whereArgs: [id]);

  Future<Map<String, double>> pantryTotalsBase({DateTime? usableOn}) async {
    final items = await getPantry();
    final result = <String, double>{};
    final date = usableOn == null ? null : PridelDates.dateOnly(usableOn);
    for (final item in items) {
      if (item.qty <= 0) continue;
      if (date != null &&
          item.expiry != null &&
          PridelDates.dateOnly(item.expiry!).isBefore(date)) continue;
      final base = UnitMath.toBase(item.qty, item.unit);
      result[item.ingredientName] =
          (result[item.ingredientName] ?? 0) + base.value;
    }
    return result;
  }

  // Meals and plan
  Future<List<MealEntry>> getMealEntries(DateTime from, DateTime to) async {
    final rows = await db.query('meal_entries',
        where: 'date >= ? AND date <= ?',
        whereArgs: [PridelDates.iso(from), PridelDates.iso(to)],
        orderBy: 'date, id');
    return rows.map(MealEntry.fromMap).toList(growable: false);
  }

  Future<List<MealEntry>> getMealsForDay(DateTime date) =>
      getMealEntries(date, date);

  Future<MealEntry?> getMeal(DateTime date, String mealType) async {
    final rows = await db.query('meal_entries',
        where: 'date = ? AND meal_type = ?',
        whereArgs: [PridelDates.iso(date), mealType],
        limit: 1);
    return rows.isEmpty ? null : MealEntry.fromMap(rows.first);
  }

  Future<int> savePlannedMeal(
      {required DateTime date,
      required String mealType,
      required Recipe recipe,
      required List<MealServing> servings}) async {
    if (!servings.any((s) => s.eating && s.portion > 0))
      throw StateError('Pri jedle musí byť označený aspoň jeden stravník.');
    return db.transaction((txn) async {
      final rows = await txn.query(
        'meal_entries',
        where: 'date = ? AND meal_type = ?',
        whereArgs: [PridelDates.iso(date), mealType],
        limit: 1,
      );
      final existing = rows.isEmpty ? null : MealEntry.fromMap(rows.first);
      if (existing?.isDone == true)
        throw StateError('Hotové jedlo najprv vráť späť do plánovaného stavu.');
      if (existing?.leftoverId != null) {
        await txn.update(
          'leftovers',
          {'status': 'available'},
          where: 'id = ? AND status = ?',
          whereArgs: [existing!.leftoverId, 'reserved'],
        );
      }
      final now = DateTime.now().toIso8601String();
      final data = <String, Object?>{
        'date': PridelDates.iso(date),
        'meal_type': mealType,
        'recipe_id': recipe.id,
        'status': 'planned',
        'snapshot_json': recipe.toSnapshotJson(),
        'servings_json':
            jsonEncode(servings.map((e) => e.toJson()).toList(growable: false)),
        'consumption_json': '[]',
        'leftover_id': null,
        'updated_at': now,
      };
      if (existing == null) {
        data['created_at'] = now;
        return txn.insert('meal_entries', data);
      }
      await txn.update('meal_entries', data,
          where: 'id = ?', whereArgs: [existing.id]);
      return existing.id;
    });
  }

  Future<int> assignLeftover(
      {required DateTime date,
      required String mealType,
      required Leftover leftover,
      required List<MealServing> servings}) async {
    final requestedPortions = servings
        .where((s) => s.eating && s.portion > 0)
        .fold<double>(0, (sum, s) => sum + s.portion);
    if (requestedPortions <= 0)
      throw StateError('Pri jedle nie je označený žiadny stravník.');
    return db.transaction((txn) async {
      final leftoverRows = await txn.query('leftovers',
          where: 'id = ? AND status = ?',
          whereArgs: [leftover.id, 'available'],
          limit: 1);
      if (leftoverRows.isEmpty)
        throw StateError('Tento zvyšok už nie je dostupný.');
      final currentLeftover = Leftover.fromMap(leftoverRows.first);
      final day = PridelDates.dateOnly(date);
      if (PridelDates.dateOnly(currentLeftover.createdAt).isAfter(day))
        throw StateError('Zvyšok ešte v tento deň neexistoval.');
      if (currentLeftover.useBy != null &&
          PridelDates.dateOnly(currentLeftover.useBy!).isBefore(day)) {
        throw StateError('Tento zvyšok je už po odporúčanom dátume spotreby.');
      }
      if (currentLeftover.portions + 0.001 < requestedPortions) {
        throw StateError(
            'Zvyšok nemá dosť porcií. Dostupné: ${currentLeftover.portions.toStringAsFixed(1)}.');
      }
      final recipe = currentLeftover.snapshot;
      if (recipe == null) throw StateError('Zvyšok nemá uložený recept.');

      final existingRows = await txn.query(
        'meal_entries',
        where: 'date = ? AND meal_type = ?',
        whereArgs: [PridelDates.iso(date), mealType],
        limit: 1,
      );
      final existing =
          existingRows.isEmpty ? null : MealEntry.fromMap(existingRows.first);
      if (existing?.isDone == true)
        throw StateError('Hotové jedlo najprv vráť späť do plánovaného stavu.');
      if (existing?.leftoverId != null &&
          existing!.leftoverId != currentLeftover.id) {
        await txn.update('leftovers', {'status': 'available'},
            where: 'id = ? AND status = ?',
            whereArgs: [existing.leftoverId, 'reserved']);
      }

      final now = DateTime.now().toIso8601String();
      final data = <String, Object?>{
        'date': PridelDates.iso(date),
        'meal_type': mealType,
        'recipe_id': recipe.id,
        'status': 'planned',
        'snapshot_json': recipe.toSnapshotJson(),
        'servings_json':
            jsonEncode(servings.map((e) => e.toJson()).toList(growable: false)),
        'consumption_json': '[]',
        'leftover_id': currentLeftover.id,
        'updated_at': now,
      };
      int id;
      if (existing == null) {
        data['created_at'] = now;
        id = await txn.insert('meal_entries', data);
      } else {
        id = existing.id;
        await txn
            .update('meal_entries', data, where: 'id = ?', whereArgs: [id]);
      }
      final reserved = await txn.update(
        'leftovers',
        {'status': 'reserved'},
        where: 'id = ? AND status = ?',
        whereArgs: [currentLeftover.id, 'available'],
      );
      if (reserved != 1)
        throw StateError(
            'Zvyšok sa medzitým použil inde. Skús výber zopakovať.');
      return id;
    });
  }

  Future<void> updateMealServings(
      int entryId, List<MealServing> servings) async {
    final row = await db.query('meal_entries',
        where: 'id = ?', whereArgs: [entryId], limit: 1);
    if (row.isEmpty) return;
    if (row.first['status'] == 'done')
      throw StateError('Pri hotovom jedle najprv zruš označenie Hotovo.');
    final requested = servings
        .where((s) => s.eating && s.portion > 0)
        .fold<double>(0, (sum, s) => sum + s.portion);
    if (requested <= 0)
      throw StateError('Pri jedle musí byť označený aspoň jeden stravník.');
    final leftoverId = (row.first['leftover_id'] as num?)?.toInt();
    if (leftoverId != null) {
      final leftovers = await db.query('leftovers',
          where: 'id = ?', whereArgs: [leftoverId], limit: 1);
      if (leftovers.isEmpty) throw StateError('Pôvodný zvyšok už neexistuje.');
      final available = (leftovers.first['portions'] as num).toDouble();
      if (requested > available + 0.001)
        throw StateError(
            'Zvyšok má iba ${available.toStringAsFixed(1)} porcie.');
    }
    await db.update(
        'meal_entries',
        {
          'servings_json': jsonEncode(
              servings.map((e) => e.toJson()).toList(growable: false)),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [entryId]);
  }

  Future<void> clearMeal(int entryId) async {
    await db.transaction((txn) async {
      final rows = await txn.query('meal_entries',
          where: 'id = ?', whereArgs: [entryId], limit: 1);
      if (rows.isEmpty) return;
      final entry = MealEntry.fromMap(rows.first);
      if (entry.isDone) throw StateError('Hotové jedlo najprv vráť späť.');
      if (entry.leftoverId != null) {
        await txn.update(
          'leftovers',
          {'status': 'available'},
          where: 'id = ? AND status = ?',
          whereArgs: [entry.leftoverId, 'reserved'],
        );
      }
      await txn.delete('meal_entries', where: 'id = ?', whereArgs: [entryId]);
    });
  }

  Future<CompletionPreview> previewCompletion(int entryId) async {
    final rows = await db.query('meal_entries',
        where: 'id = ?', whereArgs: [entryId], limit: 1);
    if (rows.isEmpty) throw StateError('Jedlo neexistuje.');
    final entry = MealEntry.fromMap(rows.first);
    if (entry.isDone ||
        entry.isLeftover ||
        entry.snapshot == null ||
        !await getUsePantry()) return const CompletionPreview(shortages: {});
    final totals = await pantryTotalsBase(usableOn: entry.date);
    final shortages = <String, double>{};
    for (final need in MealMath.requirements(entry.snapshot!, entry.servings)) {
      final missing = math.max(0.0, need.qty - (totals[need.name] ?? 0));
      if (missing > 0.0001) shortages[need.name] = missing;
    }
    return CompletionPreview(shortages: shortages);
  }

  Future<void> completeMeal(int entryId,
      {double leftoverPortions = 0, bool allowShortage = false}) async {
    if (leftoverPortions < 0)
      throw ArgumentError('Zvyšné porcie nemôžu byť záporné.');
    final usePantry = await getUsePantry();
    await db.transaction((txn) async {
      final rows = await txn.query('meal_entries',
          where: 'id = ?', whereArgs: [entryId], limit: 1);
      if (rows.isEmpty) throw StateError('Jedlo neexistuje.');
      final entry = MealEntry.fromMap(rows.first);
      if (entry.isDone) return;
      final recipe = entry.snapshot;
      if (recipe == null) throw StateError('Jedlo nemá uložený recept.');

      final deductions = <PantryDeduction>[];
      if (entry.leftoverId != null) {
        final leftoverRows = await txn.query('leftovers',
            where: 'id = ? AND status = ?',
            whereArgs: [entry.leftoverId, 'reserved'],
            limit: 1);
        if (leftoverRows.isEmpty)
          throw StateError('Zvyšok už nie je rezervovaný pre toto jedlo.');
        final row = leftoverRows.first;
        final originalPortions = (row['portions'] as num).toDouble();
        final requestedPortions = entry.servings
            .where((s) => s.eating)
            .fold<double>(0, (sum, s) => sum + s.portion);
        final consumedPortions = math.min(originalPortions, requestedPortions);
        final remainingPortions =
            math.max(0.0, originalPortions - consumedPortions);
        await txn.update(
            'leftovers',
            {
              'portions': remainingPortions,
              'status': remainingPortions > 0.0001 ? 'available' : 'consumed',
            },
            where: 'id = ?',
            whereArgs: [entry.leftoverId]);
        deductions.add(PantryDeduction(
          pantryId: -entry.leftoverId!,
          ingredient: '__leftover__',
          qty: consumedPortions,
          unit: 'porcia',
        ));
      } else if (usePantry) {
        final needs = MealMath.requirements(recipe, entry.servings);
        final shortageNames = <String>[];
        for (final need in needs) {
          final mealDate = PridelDates.iso(entry.date);
          final lots = await txn.query(
            'pantry',
            where:
                'ingredient_name = ? AND qty > 0 AND (expiry IS NULL OR expiry >= ?)',
            whereArgs: [need.name, mealDate],
            orderBy:
                "CASE WHEN expiry IS NULL THEN 1 ELSE 0 END, expiry, added_at, id",
          );
          double availableBase = 0;
          for (final lot in lots) {
            final base = UnitMath.toBase(
                (lot['qty'] as num).toDouble(), lot['unit'] as String);
            if (UnitMath.compatible(base.unit, need.unit))
              availableBase += base.value;
          }
          if (availableBase + 0.0001 < need.qty) shortageNames.add(need.name);
        }
        if (shortageNames.isNotEmpty && !allowShortage) {
          throw StateError('Chýbajú zásoby: ${shortageNames.join(', ')}');
        }

        for (final need in needs) {
          double remaining = need.qty;
          final mealDate = PridelDates.iso(entry.date);
          final lots = await txn.query(
            'pantry',
            where:
                'ingredient_name = ? AND qty > 0 AND (expiry IS NULL OR expiry >= ?)',
            whereArgs: [need.name, mealDate],
            orderBy:
                "CASE WHEN expiry IS NULL THEN 1 ELSE 0 END, expiry, added_at, id",
          );
          for (final lot in lots) {
            if (remaining <= 0.0001) break;
            final lotId = lot['id'] as int;
            final lotUnit = lot['unit'] as String;
            if (!UnitMath.compatible(lotUnit, need.unit)) continue;
            final lotBase =
                UnitMath.toBase((lot['qty'] as num).toDouble(), lotUnit);
            final takeBase = math.min(remaining, lotBase.value);
            final takeInLotUnit =
                UnitMath.convert(takeBase, lotBase.unit, lotUnit);
            final nextQty =
                math.max(0.0, (lot['qty'] as num).toDouble() - takeInLotUnit);
            if (nextQty <= 0.0001) {
              await txn.delete('pantry', where: 'id = ?', whereArgs: [lotId]);
            } else {
              await txn.update('pantry', {'qty': nextQty},
                  where: 'id = ?', whereArgs: [lotId]);
            }
            deductions.add(PantryDeduction(
              pantryId: lotId,
              ingredient: need.name,
              qty: takeInLotUnit,
              unit: lotUnit,
              expiry: lot['expiry'] as String?,
              addedAt: lot['added_at'] as String?,
            ));
            remaining -= takeBase;
          }
        }
      }

      await txn.update(
          'meal_entries',
          {
            'status': 'done',
            'consumption_json': jsonEncode(
                deductions.map((e) => e.toJson()).toList(growable: false)),
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [entryId]);

      if (leftoverPortions > 0.0001 && entry.leftoverId == null) {
        final today = PridelDates.dateOnly(DateTime.now());
        final mealDay = PridelDates.dateOnly(entry.date);
        final created = mealDay.isAfter(today) ? today : mealDay;
        final useBy = created.add(Duration(days: _leftoverDays(recipe)));
        await txn.insert('leftovers', {
          'source_meal_id': entryId,
          'recipe_id': recipe.id,
          'recipe_name': recipe.name,
          'portions': leftoverPortions,
          'created_at': PridelDates.iso(created),
          'use_by': PridelDates.iso(useBy),
          'status': 'available',
          'snapshot_json': recipe.toSnapshotJson(),
        });
      }
    });
  }

  int _leftoverDays(Recipe recipe) {
    final text = '${recipe.name} ${recipe.tags.join(' ')}'.toLowerCase();
    if (text.contains('ryb') || text.contains('fish')) return 1;
    if (text.contains('šalát') || text.contains('salad')) return 1;
    if (text.contains('poliev') || text.contains('soup')) return 2;
    return 2;
  }

  Future<void> undoMealCompletion(int entryId) async {
    await db.transaction((txn) async {
      final rows = await txn.query('meal_entries',
          where: 'id = ?', whereArgs: [entryId], limit: 1);
      if (rows.isEmpty) return;
      final entry = MealEntry.fromMap(rows.first);
      if (!entry.isDone) return;
      final children = await txn.query('leftovers',
          where: 'source_meal_id = ?', whereArgs: [entryId]);
      if (children.any((row) => row['status'] != 'available')) {
        throw StateError(
            'Zvyšok z tohto jedla už bol použitý alebo vyhodený. Hotovo už nemožno bezpečne vrátiť.');
      }
      await txn.delete('leftovers',
          where: 'source_meal_id = ?', whereArgs: [entryId]);

      if (entry.leftoverId != null) {
        final otherUses = Sqflite.firstIntValue(await txn.rawQuery(
              "SELECT COUNT(*) FROM meal_entries WHERE leftover_id = ? AND id <> ? AND status IN ('planned','done')",
              [entry.leftoverId, entryId],
            )) ??
            0;
        if (otherUses > 0)
          throw StateError(
              'Zvyšok už bol použitý v inom jedle. Hotovo nemožno bezpečne vrátiť.');
        final rows = await txn.query('leftovers',
            where: 'id = ?', whereArgs: [entry.leftoverId], limit: 1);
        if (rows.isEmpty) throw StateError('Pôvodný zvyšok už neexistuje.');
        final leftoverStatus = (rows.first['status'] as String?) ?? 'available';
        if (leftoverStatus == 'discarded' || leftoverStatus == 'consumed') {
          throw StateError(
              'Zostávajúca časť zvyšku už bola zjedená alebo vyhodená. Hotovo nemožno bezpečne vrátiť.');
        }
        final consumed = entry.consumption
            .where((d) => d.ingredient == '__leftover__')
            .fold<double>(0, (sum, d) => sum + d.qty);
        final currentPortions = (rows.first['portions'] as num).toDouble();
        await txn.update(
            'leftovers',
            {
              'portions': currentPortions + consumed,
              'status': 'reserved',
            },
            where: 'id = ?',
            whereArgs: [entry.leftoverId]);
      } else {
        for (final deduction in entry.consumption) {
          final existing = await txn.query('pantry',
              where: 'id = ?', whereArgs: [deduction.pantryId], limit: 1);
          if (existing.isEmpty) {
            await txn.insert('pantry', {
              'id': deduction.pantryId,
              'ingredient_name': deduction.ingredient,
              'qty': deduction.qty,
              'unit': deduction.unit,
              'expiry': deduction.expiry,
              'added_at': deduction.addedAt ?? DateTime.now().toIso8601String(),
            });
          } else {
            final row = existing.first;
            await txn.update('pantry',
                {'qty': (row['qty'] as num).toDouble() + deduction.qty},
                where: 'id = ?', whereArgs: [deduction.pantryId]);
          }
        }
      }
      await txn.update(
          'meal_entries',
          {
            'status': 'planned',
            'consumption_json': '[]',
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [entryId]);
    });
  }

  // Leftovers
  Future<List<Leftover>> getLeftovers({String? status}) async {
    final rows = await db.query(
      'leftovers',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status],
      orderBy: "CASE WHEN use_by IS NULL THEN 1 ELSE 0 END, use_by, created_at",
    );
    return rows.map(Leftover.fromMap).toList(growable: false);
  }

  Future<void> discardLeftover(int id) async {
    final rows =
        await db.query('leftovers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    if (rows.first['status'] == 'reserved')
      throw StateError(
          'Zvyšok je naplánovaný v jedálničku. Najprv ho z plánu odstráň.');
    await db.update('leftovers', {'status': 'discarded'},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> consumeLeftoverOutsidePlan(int id) async {
    final rows =
        await db.query('leftovers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    if (rows.first['status'] == 'reserved')
      throw StateError('Zvyšok je rezervovaný v jedálničku.');
    await db.update('leftovers', {'status': 'consumed'},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> restoreLeftover(int id) async {
    await db.update('leftovers', {'status': 'available'},
        where: "id = ? AND status IN ('discarded','consumed')",
        whereArgs: [id]);
  }

  // Shopping persistence
  Future<List<Map<String, Object?>>> getShoppingCheckRows(String weekKey) =>
      db.query('shopping_checks', where: 'week_key = ?', whereArgs: [weekKey]);

  Future<void> setShoppingChecked(
    String weekKey,
    String ingredient,
    bool checked, {
    double qty = 0,
    String unit = '',
  }) async {
    await db.insert(
        'shopping_checks',
        {
          'week_key': weekKey,
          'ingredient_name': ingredient,
          'checked': checked ? 1 : 0,
          'qty': checked ? qty : 0,
          'unit': checked ? unit : '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> getManualShopping(String weekKey) =>
      db.query('shopping_manual',
          where: 'week_key = ?', whereArgs: [weekKey], orderBy: 'id');

  Future<int> addManualShopping(String weekKey,
      {required String name, required double qty, required String unit}) {
    if (name.trim().isEmpty || qty <= 0)
      throw ArgumentError('Neplatná nákupná položka.');
    return db.insert('shopping_manual', {
      'week_key': weekKey,
      'name': name.trim(),
      'qty': qty,
      'unit': UnitMath.normalizeUnit(unit),
      'checked': 0
    });
  }

  Future<void> setManualShoppingChecked(int id, bool checked) =>
      db.update('shopping_manual', {'checked': checked ? 1 : 0},
          where: 'id = ?', whereArgs: [id]);
  Future<void> deleteManualShopping(int id) async =>
      db.delete('shopping_manual', where: 'id = ?', whereArgs: [id]);

  Future<void> addPurchasedItemsToPantry(
      List<({String name, double qty, String unit})> items) async {
    await db.transaction((txn) async {
      for (final item in items) {
        if (item.qty <= 0) continue;
        final defs = await txn.query('ingredients',
            where: 'name = ?', whereArgs: [item.name], limit: 1);
        if (defs.isEmpty) throw StateError('Neznáma surovina: ${item.name}.');
        final canonicalUnit = defs.first['unit'] as String;
        if (!UnitMath.compatible(item.unit, canonicalUnit)) {
          throw StateError(
              'Surovina ${item.name} používa jednotku $canonicalUnit.');
        }
        final qty = UnitMath.convert(item.qty, item.unit, canonicalUnit);
        await txn.insert('pantry', {
          'ingredient_name': item.name,
          'qty': qty,
          'unit': canonicalUnit,
          'expiry': null,
          'added_at': DateTime.now().toIso8601String(),
          'location': defaultStorageLocation(
              IngredientDefinition.fromMap(defs.first), item.name),
        });
      }
    });
  }

  // Home, alerts, history, storage and backup
  Future<Set<String>> getDismissedAlertKeys() async {
    final rows = await db.query('alert_dismissals', columns: ['alert_key']);
    return rows.map((row) => row['alert_key'].toString()).toSet();
  }

  Future<void> dismissAlert(String key) => db.insert(
        'alert_dismissals',
        {'alert_key': key, 'dismissed_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> clearDismissedAlerts() async => db.delete('alert_dismissals');

  Future<List<PantryItem>> getExpiringPantry({int withinDays = 3}) async {
    final end =
        PridelDates.dateOnly(DateTime.now()).add(Duration(days: withinDays));
    final rows = await db.query('pantry',
        where: 'qty > 0 AND expiry IS NOT NULL AND expiry <= ?',
        whereArgs: [PridelDates.iso(end)],
        orderBy: 'expiry');
    return rows.map(PantryItem.fromMap).toList(growable: false);
  }

  Future<Set<String>> getRecentRecipeIds({int limit = 30}) async {
    final rows = await db.rawQuery(
        "SELECT recipe_id FROM meal_entries WHERE status = 'done' AND recipe_id IS NOT NULL AND recipe_id <> '' ORDER BY date DESC, updated_at DESC LIMIT ?",
        [limit]);
    return rows.map((row) => row['recipe_id'].toString()).toSet();
  }

  Future<DashboardStats> getDashboardStats() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = now.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);
    final done = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM meal_entries WHERE status = 'done' AND date >= ? AND date < ?",
            [PridelDates.iso(start), PridelDates.iso(end)])) ??
        0;
    final available = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM leftovers WHERE status = 'available' AND portions > 0")) ??
        0;
    final discarded = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM leftovers WHERE status = 'discarded' AND created_at >= ? AND created_at < ?",
            [PridelDates.iso(start), PridelDates.iso(end)])) ??
        0;
    final pantryCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM pantry WHERE qty > 0')) ??
        0;
    final expiring = (await getExpiringPantry(withinDays: 3)).length;
    return DashboardStats(
        doneMealsThisMonth: done,
        availableLeftovers: available,
        discardedLeftoversThisMonth: discarded,
        pantryItems: pantryCount,
        expiringItems: expiring);
  }

  Future<StorageSummary> getStorageSummary() async {
    int bytes = 0;
    try {
      bytes = await File(db.path).length();
    } catch (_) {}
    final recipes = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM recipes')) ??
        0;
    final pantry = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM pantry WHERE qty > 0')) ??
        0;
    final history = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM meal_entries WHERE status = 'done'")) ??
        0;
    return StorageSummary(
        databaseBytes: bytes,
        recipeCount: recipes,
        pantryCount: pantry,
        historyCount: history);
  }

  Future<void> logError(Object error, StackTrace? stack) async {
    try {
      await db.insert('error_log', {
        'message': error.toString(),
        'stack': stack?.toString() ?? '',
        'created_at': DateTime.now().toIso8601String()
      });
      await db.rawDelete(
          'DELETE FROM error_log WHERE id NOT IN (SELECT id FROM error_log ORDER BY id DESC LIMIT 100)');
    } catch (_) {}
  }

  Future<List<Map<String, Object?>>> getErrorLog({int limit = 20}) =>
      db.query('error_log', orderBy: 'id DESC', limit: limit);
  Future<void> clearErrorLog() async => db.delete('error_log');

  Future<String> exportBackupJson() async {
    final customRecipes = await db.query('recipes', where: 'is_custom = 1');
    final customIngredients = <Map<String, Object?>>[];
    for (final row in customRecipes) {
      customIngredients.addAll(await db.query('recipe_ingredients',
          where: 'recipe_id = ?', whereArgs: [row['id']]));
    }
    final payload = {
      'app': 'PRIDEL',
      'format_version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'settings': await db.query('settings'),
      'household_members': await db.query('household_members'),
      'pantry': await db.query('pantry'),
      'meal_entries': await db.query('meal_entries'),
      'leftovers': await db.query('leftovers'),
      'shopping_checks': await db.query('shopping_checks'),
      'shopping_manual': await db.query('shopping_manual'),
      'recipe_preferences': await db.query('recipe_preferences'),
      'custom_recipes': customRecipes,
      'custom_recipe_ingredients': customIngredients,
      'ingredient_prices': await db
          .query('ingredients', columns: ['name', 'pack', 'pack_price']),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> importBackupJson(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map)
      throw const FormatException('Záloha nemá správny formát.');
    final root = Map<String, dynamic>.from(decoded);
    if (root['app'] != 'PRIDEL' || root['format_version'] != 1)
      throw const FormatException('Toto nie je podporovaná záloha PRÍDEL.');
    List<Map<String, Object?>> rows(String key) {
      final value = root[key];
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((e) => Map<String, Object?>.from(e))
          .toList(growable: false);
    }

    await db.transaction((txn) async {
      for (final table in [
        'shopping_checks',
        'shopping_manual',
        'recipe_preferences',
        'leftovers',
        'meal_entries',
        'pantry',
        'household_members',
        'alert_dismissals'
      ]) {
        await txn.delete(table);
      }
      await txn.delete('recipe_ingredients',
          where: 'recipe_id IN (SELECT id FROM recipes WHERE is_custom = 1)');
      await txn.delete('recipes', where: 'is_custom = 1');
      for (final row in rows('settings')) {
        if (row['key'] == 'seed_version' ||
            row['key'] == null ||
            row['value'] == null) continue;
        await txn.insert('settings', {'key': row['key'], 'value': row['value']},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final key in [
        'household_members',
        'pantry',
        'custom_recipes',
        'custom_recipe_ingredients',
        'meal_entries',
        'leftovers',
        'shopping_checks',
        'shopping_manual',
        'recipe_preferences'
      ]) {
        final table = key == 'custom_recipes'
            ? 'recipes'
            : key == 'custom_recipe_ingredients'
                ? 'recipe_ingredients'
                : key;
        for (final row in rows(key)) {
          final copy = Map<String, Object?>.from(row);
          if (table == 'pantry') copy['location'] ??= 'pantry';
          await txn.insert(table, copy,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      for (final row in rows('ingredient_prices')) {
        if (row['name'] != null)
          await txn.update('ingredients',
              {'pack': row['pack'], 'pack_price': row['pack_price']},
              where: 'name = ?', whereArgs: [row['name']]);
      }
      await txn.insert(
          'settings', {'key': 'onboarding_complete', 'value': 'true'},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await _repairRecoverableState();
  }

  // Diagnostics
  Future<List<String>> dataHealthIssues() async {
    final issues = <String>[];
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty ||
        integrity.first.values.first.toString().toLowerCase() != 'ok') {
      issues.add('SQLite databáza neprešla internou kontrolou integrity.');
    }
    final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
    if (foreignKeys.isNotEmpty)
      issues.add('${foreignKeys.length} databázových väzieb je poškodených.');
    final missing = await db.rawQuery('''
      SELECT DISTINCT ri.ingredient_name
      FROM recipe_ingredients ri
      LEFT JOIN ingredients i ON i.name = ri.ingredient_name
      WHERE i.name IS NULL
    ''');
    if (missing.isNotEmpty)
      issues.add('${missing.length} surovín v receptoch nemá definíciu.');
    final invalidRecipeQty = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM recipe_ingredients WHERE adult_qty < 0 OR child_qty < 0')) ??
        0;
    if (invalidRecipeQty > 0)
      issues.add('$invalidRecipeQty množstiev v receptoch je záporných.');
    final missingEnergy = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM recipes WHERE adult_kcal IS NULL OR adult_kcal <= 0 OR child_kcal IS NULL OR child_kcal <= 0')) ??
        0;
    if (missingEnergy > 0)
      issues.add('$missingEnergy receptov nemá použiteľný energetický odhad.');
    final invalidPantry = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM pantry WHERE qty < 0')) ??
        0;
    if (invalidPantry > 0)
      issues.add('$invalidPantry skladových položiek má záporné množstvo.');
    final invalidLocation = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM pantry WHERE location NOT IN ('fridge','pantry','freezer')")) ??
        0;
    if (invalidLocation > 0)
      issues.add('$invalidLocation zásob má neplatné umiestnenie.');
    final unitRows = await db.rawQuery('''
      SELECT ri.ingredient_name, ri.unit recipe_unit, i.unit ingredient_unit
      FROM recipe_ingredients ri JOIN ingredients i ON i.name = ri.ingredient_name
    ''');
    int mismatch = 0;
    for (final row in unitRows) {
      if (!UnitMath.compatible(
          row['recipe_unit'] as String, row['ingredient_unit'] as String))
        mismatch++;
    }
    if (mismatch > 0)
      issues.add(
          '$mismatch receptových surovín používa nekompatibilnú jednotku.');
    return issues;
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
