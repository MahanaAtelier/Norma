class HouseholdMember {
  const HouseholdMember({
    required this.id,
    required this.name,
    required this.role,
    required this.portion,
    required this.active,
    this.allergens = '',
    this.dislikes = '',
  });

  final int id;
  final String name;
  final String role;
  final double portion;
  final bool active;
  final String allergens;
  final String dislikes;

  bool get isChild => role == 'child';

  factory HouseholdMember.fromMap(Map<String, Object?> map) => HouseholdMember(
        id: map['id'] as int,
        name: map['name'] as String,
        role: (map['role'] as String?) ?? 'adult',
        portion: (map['portion'] as num?)?.toDouble() ?? 1,
        active: ((map['active'] as int?) ?? 1) == 1,
        allergens: (map['allergens'] as String?) ?? '',
        dislikes: (map['dislikes'] as String?) ?? '',
      );
}
