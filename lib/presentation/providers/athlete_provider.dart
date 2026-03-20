import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../domain/entities/athlete.dart';

const _kSelectedAthleteId = 'selected_athlete_id';

// ── Athlete list ───────────────────────────────────────────────────────────

final athleteListProvider = FutureProvider<List<Athlete>>((ref) async {
  final rows = await DatabaseHelper.instance.getAthletes();
  return rows.map(Athlete.fromMap).toList();
});

// ── Selected athlete (persisted across restarts) ───────────────────────────

class SelectedAthleteNotifier extends StateNotifier<Athlete?> {
  SelectedAthleteNotifier() : super(null) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_kSelectedAthleteId);
    if (id == null) return;
    try {
      final rows = await DatabaseHelper.instance.getAthletes();
      final list = rows.map(Athlete.fromMap).toList();
      final match = list.where((a) => a.id == id).firstOrNull;
      if (match != null) state = match;
    } catch (_) {}
  }

  /// Select or deselect an athlete and persist the choice.
  Future<void> select(Athlete? athlete) async {
    state = athlete;
    final prefs = await SharedPreferences.getInstance();
    if (athlete?.id != null) {
      await prefs.setInt(_kSelectedAthleteId, athlete!.id!);
    } else {
      await prefs.remove(_kSelectedAthleteId);
    }
  }
}

final selectedAthleteProvider =
    StateNotifierProvider<SelectedAthleteNotifier, Athlete?>(
        (ref) => SelectedAthleteNotifier());

// ── Athlete CRUD notifier ──────────────────────────────────────────────────

class AthleteNotifier extends StateNotifier<AsyncValue<List<Athlete>>> {
  AthleteNotifier() : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final rows = await DatabaseHelper.instance.getAthletes();
      state = AsyncValue.data(rows.map(Athlete.fromMap).toList());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Athlete> createAthlete({
    required String name,
    double? bodyWeightKg,
    String? sport,
    String? notes,
  }) async {
    final map = Athlete(
      name: name,
      bodyWeightKg: bodyWeightKg,
      sport: sport,
      notes: notes,
      createdAt: DateTime.now(),
    ).toMap();
    final id = await DatabaseHelper.instance.insertAthlete(map);
    await load();
    return Athlete.fromMap({...map, 'id': id});
  }

  Future<void> updateAthlete(Athlete athlete) async {
    await DatabaseHelper.instance.updateAthlete(athlete.toMap());
    await load();
  }

  Future<void> deleteAthlete(int id) async {
    await DatabaseHelper.instance.deleteAthlete(id);
    await load();
  }
}

final athleteNotifierProvider =
    StateNotifierProvider<AthleteNotifier, AsyncValue<List<Athlete>>>((ref) {
  return AthleteNotifier();
});
