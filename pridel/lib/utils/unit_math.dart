class UnitValue {
  const UnitValue(this.value, this.unit);
  final double value;
  final String unit;
}

class UnitMath {
  static String normalizeUnit(String raw) {
    final value = raw.trim().toLowerCase().replaceAll('.', '');
    switch (value) {
      case 'kg':
        return 'kg';
      case 'g':
      case 'gr':
        return 'g';
      case 'l':
        return 'l';
      case 'ml':
        return 'ml';
      case 'ks':
      case 'kus':
      case 'kusy':
      case 'pc':
      case 'pcs':
        return 'ks';
      default:
        return raw.trim().isEmpty ? 'g' : raw.trim();
    }
  }

  static String dimension(String unit) {
    switch (normalizeUnit(unit)) {
      case 'g':
      case 'kg':
        return 'mass';
      case 'ml':
      case 'l':
        return 'volume';
      case 'ks':
        return 'count';
      default:
        return 'custom:${normalizeUnit(unit)}';
    }
  }

  static bool compatible(String a, String b) => dimension(a) == dimension(b);

  static UnitValue toBase(double value, String unit) {
    switch (normalizeUnit(unit)) {
      case 'kg':
        return UnitValue(value * 1000, 'g');
      case 'g':
        return UnitValue(value, 'g');
      case 'l':
        return UnitValue(value * 1000, 'ml');
      case 'ml':
        return UnitValue(value, 'ml');
      case 'ks':
        return UnitValue(value, 'ks');
      default:
        return UnitValue(value, normalizeUnit(unit));
    }
  }

  static double convert(double value, String from, String to) {
    if (!compatible(from, to)) {
      throw ArgumentError('Nekompatibilné jednotky: $from a $to');
    }
    final base = toBase(value, from);
    switch (normalizeUnit(to)) {
      case 'kg':
        return base.value / 1000;
      case 'g':
        return base.value;
      case 'l':
        return base.value / 1000;
      case 'ml':
        return base.value;
      case 'ks':
        return base.value;
      default:
        return base.value;
    }
  }

  static String format(double value, String unit) {
    final normalized = normalizeUnit(unit);
    if (normalized == 'g' && value >= 1000)
      return '${_number(value / 1000)} kg';
    if (normalized == 'ml' && value >= 1000)
      return '${_number(value / 1000)} l';
    return '${_number(value)} $normalized';
  }

  static String _number(double value) {
    if ((value - value.roundToDouble()).abs() < 0.001)
      return value.round().toString();
    if (value.abs() >= 100) return value.toStringAsFixed(0);
    if (value.abs() >= 10)
      return value.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
