import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pridel/utils/unit_math.dart';

void main() {
  test('seed data has unique recipes and complete ingredient references',
      () async {
    final recipes =
        jsonDecode(await File('assets/data/recipes.json').readAsString())
            as List<dynamic>;
    final ingredients =
        jsonDecode(await File('assets/data/ingredients.json').readAsString())
            as Map<String, dynamic>;
    expect(recipes.length, greaterThanOrEqualTo(170));
    expect(ingredients.length, greaterThanOrEqualTo(170));

    final ids = <String>{};
    final missing = <String>{};
    final unitMismatch = <String>[];
    for (final raw in recipes) {
      final recipe = Map<String, dynamic>.from(raw as Map);
      final id = recipe['id'] as String;
      expect(ids.add(id), isTrue, reason: 'Duplicitné ID $id');
      expect((recipe['name'] as String).trim(), isNotEmpty);
      expect((recipe['source_url'] ?? '').toString().trim(), isEmpty,
          reason: '$id obsahuje source_url');
      expect((recipe['adult_kcal'] as num?)?.toDouble() ?? 0, greaterThan(0),
          reason: '$id nemá energiu pre dospelého');
      expect((recipe['child_kcal'] as num?)?.toDouble() ?? 0, greaterThan(0),
          reason: '$id nemá energiu pre dieťa');
      for (final riRaw
          in (recipe['ingredients'] as List<dynamic>? ?? const [])) {
        final ri = Map<String, dynamic>.from(riRaw as Map);
        final name = ri['ingredient'] as String;
        if (!ingredients.containsKey(name)) {
          missing.add(name);
          continue;
        }
        final def = Map<String, dynamic>.from(ingredients[name] as Map);
        if (!UnitMath.compatible(
            (ri['unit'] ?? 'g').toString(), (def['unit'] ?? 'g').toString())) {
          unitMismatch.add('$id/$name');
        }
        expect((ri['adult_qty'] as num?)?.toDouble() ?? 0,
            greaterThanOrEqualTo(0));
        expect((ri['child_qty'] as num?)?.toDouble() ?? 0,
            greaterThanOrEqualTo(0));
      }
    }
    expect(missing, isEmpty);
    expect(unitMismatch, isEmpty);
    for (final entry in ingredients.entries) {
      final def = Map<String, dynamic>.from(entry.value as Map);
      final buy = def['buy'] != false;
      if (!buy) continue;
      expect((def['pack'] as num?)?.toDouble() ?? 0, greaterThan(0),
          reason: '${entry.key} nemá veľkosť balenia');
      expect((def['pack_price'] as num?)?.toDouble() ?? 0, greaterThan(0),
          reason: '${entry.key} nemá orientačnú cenu');
    }

    bool compatible(Map<String, dynamic> recipe, String meal) {
      final category = (recipe['category'] ?? '').toString().toLowerCase();
      final use = (recipe['meal_use'] ?? '').toString().toLowerCase();
      switch (meal) {
        case 'breakfast':
          return category.contains('raňaj') || use.contains('raňaj');
        case 'snack':
          return category.contains('desiata') || use.contains('desiata');
        case 'soup':
          return category.contains('poliev') || use.contains('poliev');
        case 'lunch':
          return (category == 'obed' ||
                  category.contains('rozpočt') ||
                  use == 'obed') &&
              !category.contains('poliev');
        case 'afternoon':
          return category.contains('olovrant') || use.contains('olovrant');
        case 'dinner':
          return category.contains('večera') ||
              category.contains('jednoduché jedlo') ||
              use.contains('večera');
        default:
          return false;
      }
    }

    for (final meal in [
      'breakfast',
      'snack',
      'soup',
      'lunch',
      'afternoon',
      'dinner'
    ]) {
      final count = recipes
          .where(
              (raw) => compatible(Map<String, dynamic>.from(raw as Map), meal))
          .length;
      expect(count, greaterThanOrEqualTo(15),
          reason: 'Príliš málo kandidátov pre $meal: $count');
    }
  });
}
