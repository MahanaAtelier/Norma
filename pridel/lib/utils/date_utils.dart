class PridelDates {
  static const weekdayShort = ['Po', 'Ut', 'St', 'Št', 'Pi', 'So', 'Ne'];
  static const weekdayLong = [
    'Pondelok',
    'Utorok',
    'Streda',
    'Štvrtok',
    'Piatok',
    'Sobota',
    'Nedeľa'
  ];
  static const monthNames = [
    'januára',
    'februára',
    'marca',
    'apríla',
    'mája',
    'júna',
    'júla',
    'augusta',
    'septembra',
    'októbra',
    'novembra',
    'decembra'
  ];

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime startOfWeek(DateTime value) {
    final d = dateOnly(value);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  static String iso(DateTime value) {
    final d = dateOnly(value);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static DateTime? tryParse(String? value) =>
      value == null ? null : DateTime.tryParse(value);

  static String dayLabel(DateTime value) =>
      '${weekdayLong[value.weekday - 1]} ${value.day}. ${monthNames[value.month - 1]}';

  static String compactDay(DateTime value) => '${value.day}.${value.month}.';

  static String weekRange(DateTime weekStart) {
    final start = startOfWeek(weekStart);
    final end = start.add(const Duration(days: 6));
    if (start.year == end.year && start.month == end.month) {
      return '${start.day}. – ${end.day}. ${monthNames[start.month - 1]} ${start.year}';
    }
    if (start.year == end.year) {
      return '${start.day}. ${monthNames[start.month - 1]} – ${end.day}. ${monthNames[end.month - 1]} ${start.year}';
    }
    return '${start.day}.${start.month}.${start.year} – ${end.day}.${end.month}.${end.year}';
  }

  static String weekKey(DateTime value) => iso(startOfWeek(value));

  static int daysBetween(DateTime a, DateTime b) =>
      dateOnly(b).difference(dateOnly(a)).inDays;
}
