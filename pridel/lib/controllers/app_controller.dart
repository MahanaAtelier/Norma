import 'package:flutter/foundation.dart';

import '../data/app_database.dart';

enum AppArea {
  home,
  plan,
  recipes,
  pantry,
  shopping,
  settings,
  household,
  leftovers,
  all,
}

class AppController extends ChangeNotifier {
  AppController(this.database);

  final AppDatabase database;
  int _revision = 0;
  Set<AppArea> _lastAreas = const {AppArea.all};

  int get revision => _revision;
  Set<AppArea> get lastAreas => _lastAreas;

  bool affects(AppArea area) =>
      area == AppArea.home ||
      _lastAreas.contains(AppArea.all) ||
      _lastAreas.contains(area);

  bool _pantryRecipeFilterRequested = false;
  void requestPantryRecipeFilter() {
    _pantryRecipeFilterRequested = true;
    dataChanged({AppArea.recipes});
  }

  bool consumePantryRecipeFilterRequest() {
    final value = _pantryRecipeFilterRequested;
    _pantryRecipeFilterRequested = false;
    return value;
  }

  void dataChanged([Set<AppArea> areas = const {AppArea.all}]) {
    _revision++;
    _lastAreas =
        areas.isEmpty ? const {AppArea.all} : Set<AppArea>.unmodifiable(areas);
    notifyListeners();
  }
}
