import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/athlete.dart';
import '../../providers/athlete_provider.dart';
import '../../theme/app_theme.dart';

class AthleteListScreen extends ConsumerWidget {
  const AthleteListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final athletes = ref.watch(athleteNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Atletas'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Nuevo atleta',
            onPressed: () => _showFormDialog(context, ref, null),
          ),
        ],
      ),
      body: athletes.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.danger))),
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
              content: Text('${athlete.name} eliminado'),
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
                icon: Icon(Icons.edit_outlined, size: 18, color: col.textSecondary),
                tooltip: 'Editar',
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
        title: Text('Eliminar atleta',
            style: TextStyle(color: ctx.col.textPrimary)),
        content: Text(
          '¿Eliminar a ${athlete.name}?\n'
          'Se eliminarán también todos sus tests guardados.',
          style: TextStyle(color: ctx.col.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar',
                style: TextStyle(color: ctx.col.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 64, color: col.textDisabled),
          const SizedBox(height: 16),
          Text('Sin atletas registrados',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(color: col.textSecondary)),
          const SizedBox(height: 8),
          Text('Agrega tu primer atleta para comenzar.',
              style: TextStyle(color: col.textDisabled)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Agregar atleta'),
            onPressed: onAdd,
          ),
        ],
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
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final notifier = widget.ref.read(athleteNotifierProvider.notifier);
    final name  = _nameCtrl.text.trim();
    final sport = _sportCtrl.text.trim().isEmpty ? null : _sportCtrl.text.trim();
    final bwKg  = double.tryParse(_weightCtrl.text);

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
      title: Text(_isEdit ? 'Editar atleta' : 'Nuevo atleta',
          style: TextStyle(color: col.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Nombre *'),
            autofocus: !_isEdit,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sportCtrl,
            decoration: const InputDecoration(labelText: 'Deporte'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Peso corporal (kg)', suffixText: 'kg'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancelar',
              style: TextStyle(color: col.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEdit ? 'Guardar cambios' : 'Crear'),
        ),
      ],
    );
  }
}
