import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../domain/entities/test_result.dart';
import '../../theme/app_theme.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final sessionHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return DatabaseHelper.instance.getAllSessionsWithAthlete();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.compare_arrows),
            tooltip: 'Comparar sesiones',
            onPressed: () => context.push('/compare'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(sessionHistoryProvider),
          ),
        ],
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: AppColors.danger)),
        ),
        data: (sessions) {
          if (sessions.isEmpty) return const _EmptyHistory();
          return _SessionList(sessions: sessions);
        },
      ),
    );
  }
}

// ── Session list ──────────────────────────────────────────────────────────────

class _SessionList extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  const _SessionList({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final s in sessions) {
      final dt  = DateTime.tryParse(s['performed_at'] as String? ?? '') ?? DateTime.now();
      final key = DateFormat('EEEE, d MMM yyyy', 'es').format(dt);
      (grouped[key] ??= []).add(s);
    }
    final dates = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: dates.length,
      itemBuilder: (ctx, i) {
        final date        = dates[i];
        final daySessions = grouped[date]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(date, style: IXTextStyles.sectionHeader()),
            ),
            ...daySessions.map((s) => _SessionTile(session: s)),
          ],
        );
      },
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Map<String, dynamic> session;
  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final col          = context.col;
    final testTypeName = session['test_type'] as String? ?? 'cmj';
    final testType     = TestType.values.firstWhere(
      (t) => t.name == testTypeName, orElse: () => TestType.cmj);
    final athleteName = session['athlete_name'] as String? ?? 'Atleta';
    final dt          = DateTime.tryParse(session['performed_at'] as String? ?? '') ?? DateTime.now();
    final timeStr     = DateFormat('HH:mm').format(dt);
    final resultJson  = session['result_json'] as String?;

    String heroValue = '--';
    String heroUnit  = '';
    if (resultJson != null) {
      try {
        final result = TestResult.fromJson(resultJson);
        switch (result) {
          case DropJumpResult r:
            heroValue = r.jumpHeightCm.toStringAsFixed(1); heroUnit = 'cm';
          case JumpResult r:
            heroValue = r.jumpHeightCm.toStringAsFixed(1); heroUnit = 'cm';
          case MultiJumpResult r:
            heroValue = r.meanHeightCm.toStringAsFixed(1); heroUnit = 'cm';
          case ImtpResult r:
            heroValue = r.peakForceN.toStringAsFixed(0); heroUnit = 'N';
          case CoPResult r:
            heroValue = r.areaEllipseMm2.toStringAsFixed(0); heroUnit = 'mm²';
        }
      } catch (_) {}
    }

    final athleteId = session['athlete_id'] as int?;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: col.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (resultJson != null) {
            try {
              final result = TestResult.fromJson(resultJson);
              context.push('/results/${session['id']}', extra: result);
            } catch (_) {}
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              _TestTypeIcon(testType: testType),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(testType.displayName,
                        style: TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 14, color: col.textPrimary)),
                    const SizedBox(height: 2),
                    Text('$athleteName · $timeStr',
                        style: TextStyle(fontSize: 12, color: col.textSecondary)),
                  ],
                ),
              ),
              if (heroValue != '--')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(heroValue,
                        style: IXTextStyles.metricValue(color: AppColors.primary)
                            .copyWith(fontSize: 20)),
                    Text(heroUnit,
                        style: IXTextStyles.metricLabel.copyWith(fontSize: 10)),
                  ],
                ),
              if (athleteId != null)
                IconButton(
                  icon: Icon(Icons.compare_arrows,
                      size: 18, color: col.textSecondary),
                  tooltip: 'Comparar sesiones',
                  splashRadius: 20,
                  onPressed: () => context.push('/compare', extra: {
                    'athleteId': athleteId,
                    'testType': testType,
                  }),
                )
              else
                const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: col.textSecondary, size: 18),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Test type icon badge ──────────────────────────────────────────────────────

class _TestTypeIcon extends StatelessWidget {
  final TestType testType;
  const _TestTypeIcon({required this.testType});

  Color get _color {
    switch (testType) {
      case TestType.cmj:
      case TestType.cmjArms:
      case TestType.sj:      return AppColors.primary;
      case TestType.dropJump: return AppColors.warning;
      case TestType.multiJump:return AppColors.forceTotal;
      case TestType.cop:      return AppColors.secondary;
      case TestType.imtp:     return AppColors.danger;
    }
  }

  IconData get _icon {
    switch (testType) {
      case TestType.cmj:
      case TestType.cmjArms:
      case TestType.sj:       return Icons.arrow_upward;
      case TestType.dropJump: return Icons.arrow_downward;
      case TestType.multiJump:return Icons.repeat;
      case TestType.cop:      return Icons.balance;
      case TestType.imtp:     return Icons.fitness_center;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(_icon, color: _color, size: 20),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: col.textSecondary.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text('No hay sesiones guardadas',
              style: TextStyle(fontSize: 16, color: col.textSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('Realiza tu primer test para ver el historial aquí.',
              style: TextStyle(fontSize: 13, color: col.textSecondary)),
        ],
      ),
    );
  }
}
