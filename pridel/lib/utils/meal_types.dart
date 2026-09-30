class MealTypes {
  static const breakfast = 'breakfast';
  static const snack = 'snack';
  static const soup = 'soup';
  static const lunch = 'lunch';
  static const afternoon = 'afternoon';
  static const dinner = 'dinner';

  static const ordered = [breakfast, snack, soup, lunch, afternoon, dinner];

  static String label(String type) {
    switch (type) {
      case breakfast:
        return 'Raňajky';
      case snack:
        return 'Desiata';
      case soup:
        return 'Polievka';
      case lunch:
        return 'Hlavné jedlo';
      case afternoon:
        return 'Olovrant';
      case dinner:
        return 'Večera';
      default:
        return type;
    }
  }

  static bool isMain(String type) => type == lunch || type == dinner;
}
