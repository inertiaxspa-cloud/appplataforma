import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../domain/entities/athlete.dart';
import '../../providers/athlete_provider.dart';
import '../../providers/language_provider.dart';
import '../../theme/app_theme.dart';

class AthleteListScreen extends ConsumerWidget {
  const AthleteListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch language so the screen rebuilds when the language changes.
    ref.watch(languageProvider);

    final athletes = ref.watch(athleteNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('athletes')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: AppStrings.get('new_athlete'),
            onPressed: () => _showFormDialog(context, ref, null),
          ),
        ],
      ),
      body: athletes.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
              const SizedBox(height: 12),
              Text(AppStrings.get('could_not_load_athletes'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(AppStrings.get('restart_app'),
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: Text(AppStrings.get('retry')),
                onPressed: () => ref.invalidate(athleteNotifierProvider),
              ),
            ],
          ),
        ),
        data: (list) => list.isEmpty
            ? _EmptyState(onAdd: () => _showFormDialog(context, ref, null))
            : _AthleteList(
                athletes: list,
                onEdit:   (a) => _showFormDialog(context, ref, a),
              ),
      ),
    );
  }

  void _showFormDialog(BuildContext context, WidgetRef ref, Athlete? existing) {
    showDialog(
      context: context,
      builder: (_) => _AthleteFormDialog(ref: ref, existing: existing),
    );
  }
}

// ── List ──────────────────────────────────────────────────────────────────────

class _AthleteList extends ConsumerWidget {
  final List<Athlete> athletes;
  final void Function(Athlete) onEdit;
  const _AthleteList({required this.athletes, required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: athletes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) => _AthleteCard(
        athlete: athletes[i],
        onEdit:  onEdit,
      ),
    );
  }
}

// ── Card with swipe-to-delete ─────────────────────────────────────────────────

class _AthleteCard extends ConsumerWidget {
  final Athlete athlete;
  final void Function(Athlete) onEdit;
  const _AthleteCard({required this.athlete, required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final col = context.col;
    return Dismissible(
      key: ValueKey(athlete.id),
      direction: DismissDirection.endToStart,
      background: _DeleteBackground(),
      confirmDismiss: (_) => _confirmDelete(context, col),
      onDismissed: (_) async {
        final id = athlete.id;
        if (id == null) return;
        if (ref.read(selectedAthleteProvider)?.id == id) {
          ref.read(selectedAthleteProvider.notifier).select(null);
        }
        await ref.read(athleteNotifierProvider.notifier).deleteAthlete(id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${athlete.name} ${AppStrings.get('athlete_deleted')}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: InkWell(
        onTap: () {
          ref.read(selectedAthleteProvider.notifier).select(athlete);
          context.pop();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(
            color: col.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: col.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withAlpha(38),
                child: Text(
                  athlete.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(athlete.name,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                            color: col.textPrimary)),
                    if (athlete.sport != null && athlete.sport!.isNotEmpty)
                      Text(athlete.sport!,
                          style: TextStyle(fontSize: 12, color: col.textSecondary)),
                  ],
                ),
              ),
              if (athlete.bodyWeightKg != null)
                Text(
                  '${athlete.bodyWeightKg!.toStringAsFixed(1)} kg',
                  style: TextStyle(fontSize: 13, color: col.textSecondary),
                ),
              IconButton(
                icon: const Icon(Icons.show_chart_rounded,
                    size: 18, color: AppColors.primary),
                tooltip: AppStrings.get('progress'),
                onPressed: () =>
                    context.push('/athletes/progress', extra: athlete),
              ),
              IconButton(
                icon: Icon(Icons.edit_outlined, size: 18, color: col.textSecondary),
                tooltip: AppStrings.get('edit'),
                onPressed: () => onEdit(athlete),
              ),
              Icon(Icons.chevron_right, color: col.textDisabled, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, ThemeColors col) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.col.surface,
        title: Text(AppStrings.get('delete_athlete'),
            style: TextStyle(color: ctx.col.textPrimary)),
        content: Text(
          '${AppStrings.get('delete_athlete_confirm')} ${athlete.name}?\n'
          '${AppStrings.get('delete_athlete_confirmation')}',
          style: TextStyle(color: ctx.col.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.get('cancel'),
                style: TextStyle(color: ctx.col.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppStrings.get('delete'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: AppColors.danger.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.delete_outline, color: AppColors.danger, size: 24),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

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
              child: Icon(Icons.people_outline, size: 44, color: col.textDisabled),
            ),
            const SizedBox(height: 20),
            Text(
              AppStrings.get('no_athletes'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: col.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.get('no_athletes_sub'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: col.textDisabled),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add_outlined),
              label: Text(AppStrings.get('add_athlete')),
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared create/edit dialog ─────────────────────────────────────────────────

class _AthleteFormDialog extends StatefulWidget {
  final WidgetRef ref;
  final Athlete? existing;
  const _AthleteFormDialog({required this.ref, this.existing});

  @override
  State<_AthleteFormDialog> createState() => _AthleteFormDialogState();
}

class _AthleteFormDialogState extends State<_AthleteFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _sportCtrl;
  late final TextEditingController _weightCtrl;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _nameCtrl   = TextEditingController(text: a?.name ?? '');
    _sportCtrl  = TextEditingController(text: a?.sport ?? '');
    _weightCtrl = TextEditingController(
        text: a?.bodyWeightKg?.toStringAsFixed(1) ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _sportCtrl.dispose(); _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.get('name_required_error'))),
      );
      return;
    }

    // Validar peso antes de guardar
    final bwKg = _weightCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_weightCtrl.text.trim());
    if (_weightCtrl.text.trim().isNotEmpty && (bwKg == null || bwKg <= 0 || bwKg > 500)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.get('invalid_weight'))),
      );
      return;
    }

    setState(() => _saving = true);

    final notifier = widget.ref.read(athleteNotifierProvider.notifier);
    final name  = _nameCtrl.text.trim();
    final sport = _sportCtrl.text.trim().isEmpty ? null : _sportCtrl.text.trim();

    if (_isEdit) {
      final updated = widget.existing!.copyWith(
          name: name, sport: sport, bodyWeightKg: bwKg);
      await notifier.updateAthlete(updated);
      final sel = widget.ref.read(selectedAthleteProvider);
      if (sel?.id == updated.id) {
        widget.ref.read(selectedAthleteProvider.notifier).select(updated);
      }
    } else {
      await notifier.createAthlete(name: name, sport: sport, bodyWeightKg: bwKg);
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return AlertDialog(
      backgroundColor: col.surface,
      title: Text(_isEdit ? AppStrings.get('edit_athlete') : AppStrings.get('new_athlete'),
          style: TextStyle(color: col.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(labelText: AppStrings.get('name_required')),
            autofocus: !_isEdit,
            maxLength: 100,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sportCtrl,
            decoration: InputDecoration(labelText: AppStrings.get('sport_label')),
            maxLength: 50,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: AppStrings.get('body_weight_label_kg'), suffixText: 'kg'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.get('cancel'),
              style: TextStyle(color: col.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEdit ? AppStrings.get('save_changes') : AppStrings.get('create_label')),
        ),
      ],
    );
  }
}
