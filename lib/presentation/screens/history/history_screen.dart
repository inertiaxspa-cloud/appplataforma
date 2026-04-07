import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../domain/entities/test_result.dart';
import '../../providers/language_provider.dart';
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
    // Watch language so the screen rebuilds when the language changes.
    ref.watch(languageProvider);

    final sessionsAsync = ref.watch(sessionHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('history')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.compare_arrows),
            tooltip: AppStrings.get('compare_sessions'),
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
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
              const SizedBox(height: 12),
              Text(AppStrings.get('cannot_load_history'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: Text(AppStrings.get('retry')),
                onPressed: () => ref.invalidate(sessionHistoryProvider),
              ),
            ],
          ),
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

class _SessionList extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> sessions;
  const _SessionList({required this.sessions});

  @override
  ConsumerState<_SessionList> createState() => _SessionListState();
}

class _SessionListState extends ConsumerState<_SessionList> {
  /// Local optimistic copy — items are removed immediately on dismiss so that
  /// there is no race between the Dismissible animation and provider rebuild.
  late List<Map<String, dynamic>> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = List<Map<String, dynamic>>.from(widget.sessions);
  }

  @override
  void didUpdateWidget(_SessionList old) {
    super.didUpdateWidget(old);
    // Sync local copy whenever the provider delivers a fresh list
    // (e.g. after a delete refresh or manual reload).
    if (widget.sessions != old.sessions) {
      setState(() => _sessions = List<Map<String, dynamic>>.from(widget.sessions));
    }
  }

  void _removeSession(Map<String, dynamic> session) {
    final id = session['id'] as int?;
    // 1. Remove from local list immediately — animation stays smooth.
    setState(() => _sessions.removeWhere((s) => s['id'] == id));
    // 2. Delete from DB asynchronously.
    if (id != null) {
      DatabaseHelper.instance.deleteSession(id).then((_) {
        // 3. Delay the provider invalidation so the Dismissible animation
        //    finishes before the widget tree is rebuilt. Without this delay,
        //    the rebuild races with the animation and causes a black screen.
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) ref.invalidate(sessionHistoryProvider);
        });
      }).catchError((e) {
        // Restore item on error and show a snackbar.
        if (mounted) {
          setState(() {
            if (!_sessions.any((s) => s['id'] == id)) _sessions.add(session);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppStrings.get('error_deleting')}: $e'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final s in _sessions) {
      final dt  = DateTime.tryParse(s['performed_at'] as String? ?? '') ?? DateTime.now();
      final key = DateFormat('EEEE, d MMM yyyy', AppStrings.currentLanguage).format(dt);
      (grouped[key] ??= []).add(s);
    }
    final dates = grouped.keys.toList();

    if (_sessions.isEmpty) return const _EmptyHistory();

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
            ...daySessions.map((s) => _SessionTile(
              session: s,
              onDelete: () => _removeSession(s),
            )),
          ],
        );
      },
    );
  }
}

class _SessionTile extends ConsumerWidget {
  final Map<String, dynamic> session;
  /// Called after the user confirms deletion. The parent handles actual DB
  /// deletion and provider refresh — keeping it out of the Dismissible callback.
  final VoidCallback onDelete;
  const _SessionTile({required this.session, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          case FreeTestResult r:
            heroValue = r.peakForceN.toStringAsFixed(0); heroUnit = 'N';
        }
      } catch (e) { debugPrint('[History] Result parse error: $e'); }
    }

    final athleteId = session['athlete_id'] as int?;

    final sessionId = session['id']?.toString() ?? testTypeName;
    return Dismissible(
      key: Key('session_$sessionId'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
      ),
      confirmDismiss: (_) async {
        final id = session['id'] as int?;
        if (id == null) return false;
        // IMPORTANT: use the dialog builder's own context (dlgCtx) for
        // Navigator.pop, NOT the tile's context.  showDialog() pushes the
        // dialog onto the *root* navigator; using the tile's context (shell
        // inner navigator) pops the history tab instead → black screen.
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dlgCtx) => AlertDialog(
            backgroundColor: col.surface,
            title: Text(AppStrings.get('delete_session')),
            content:
                Text(AppStrings.get('delete_confirmation')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dlgCtx, false),
                  child: Text(AppStrings.get('cancel'))),
              TextButton(
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () => Navigator.pop(dlgCtx, true),
                  child: Text(AppStrings.get('delete'))),
            ],
          ),
        );
        return confirmed == true;
      },
      onDismissed: (_) {
        // Delegate deletion to the parent stateful widget — this keeps the
        // Dismissible callback synchronous and avoids the widget-tree tear-down
        // race that caused the black screen / hang.
        onDelete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppStrings.get('session_deleted')),
              backgroundColor: AppColors.danger,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Container(
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
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${AppStrings.get('could_not_load_result')}: $e'),
                    backgroundColor: Colors.red.shade700,
                  ),
                );
              }
            }
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
                  tooltip: AppStrings.get('compare_sessions'),
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
      ), // Container
    ); // Dismissible
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
      case TestType.freeTest: return AppColors.forceTotal;
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
      case TestType.freeTest: return Icons.science;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: col.textDisabled.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history_rounded, size: 44, color: col.textDisabled),
            ),
            const SizedBox(height: 20),
            Text(
              AppStrings.get('no_history'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: col.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.get('no_history_sub'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: col.textDisabled),
            ),
          ],
        ),
      ),
    );
  }
}
