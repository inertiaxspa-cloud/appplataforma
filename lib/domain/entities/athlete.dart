class Athlete {
  final int? id;
  final String name;
  final double? bodyWeightKg;
  final String? sport;
  final String? notes;
  final DateTime createdAt;
  final String? supabaseUuid;

  const Athlete({
    this.id,
    required this.name,
    this.bodyWeightKg,
    this.sport,
    this.notes,
    required this.createdAt,
    this.supabaseUuid,
  });

  Athlete copyWith({
    int? id,
    String? name,
    double? bodyWeightKg,
    String? sport,
    String? notes,
    DateTime? createdAt,
    String? supabaseUuid,
  }) {
    return Athlete(
      id: id ?? this.id,
      name: name ?? this.name,
      bodyWeightKg: bodyWeightKg ?? this.bodyWeightKg,
      sport: sport ?? this.sport,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      supabaseUuid: supabaseUuid ?? this.supabaseUuid,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'body_weight_kg': bodyWeightKg,
    'sport': sport,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'supabase_uuid': supabaseUuid,
  };

  factory Athlete.fromMap(Map<String, dynamic> map) => Athlete(
    id: map['id'] as int?,
    name: map['name'] as String,
    bodyWeightKg: map['body_weight_kg'] as double?,
    sport: map['sport'] as String?,
    notes: map['notes'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
    supabaseUuid: map['supabase_uuid'] as String?,
  );
}
