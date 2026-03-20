import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/datasources/connection/connection_datasource.dart';
import '../../providers/connection_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/status_badge.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  bool _scanning = false;
  bool _showDiagnostic = false;
  Timer? _diagnosticTimer;

  @override
  void initState() {
    super.initState();
    _scan();
    // Show diagnostic checklist after 5 seconds without a connection
    _diagnosticTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !ref.read(connectionProvider).isConnected) {
        setState(() => _showDiagnostic = true);
      }
    });
  }

  @override
  void dispose() {
    _diagnosticTimer?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    await ref.read(connectionProvider.notifier).refreshTargets();
    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);
    // Also show diagnostic immediately when there is an error
    final shouldShowDiagnostic =
        _showDiagnostic || (conn.error != null && !conn.isConnected);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conectar Plataforma'),
        actions: [
          IconButton(
            icon: _scanning
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _scanning ? null : _scan,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (conn.isConnected)
            _ConnectedBanner(
              name: conn.connectedName ?? 'Conectado',
              onDisconnect: () =>
                  ref.read(connectionProvider.notifier).disconnect(),
            ),
          if (conn.error != null)
            _ErrorBanner(message: conn.error!),
          if (shouldShowDiagnostic && !conn.isConnected)
            _DiagnosticChecklist(),
          Expanded(
            child: conn.availableTargets.isEmpty
                ? _EmptyPorts(onScan: _scan, isScanning: _scanning)
                : _PortList(targets: conn.availableTargets),
          ),
          const _HelpFooter(),
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _ConnectedBanner extends StatelessWidget {
  final String name;
  final VoidCallback onDisconnect;
  const _ConnectedBanner({required this.name, required this.onDisconnect});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.successDim,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: AppColors.success, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                style: const TextStyle(color: AppColors.success, fontSize: 13)),
          ),
          TextButton(
            onPressed: onDisconnect,
            style: TextButton.styleFrom(
                foregroundColor: AppColors.danger, padding: EdgeInsets.zero),
            child: const Text('Desconectar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.dangerDim,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.danger.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12))),
        ],
      ),
    );
  }
}

class _PortList extends ConsumerWidget {
  final List<ConnectionTarget> targets;
  const _PortList({required this.targets});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: targets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final t           = targets[i];
        final isConnected = conn.isConnected && conn.connectedName == t.displayName;
        return _PortTile(
          target: t,
          isConnected: isConnected,
          onTap: () async {
            if (isConnected) {
              await ref.read(connectionProvider.notifier).disconnect();
            } else {
              await ref.read(connectionProvider.notifier).connect(t);
              if (ref.read(connectionProvider).isConnected && context.mounted) {
                context.pop();
              }
            }
          },
        );
      },
    );
  }
}

class _PortTile extends StatelessWidget {
  final ConnectionTarget target;
  final bool isConnected;
  final VoidCallback onTap;
  const _PortTile({
    required this.target,
    required this.isConnected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isConnected ? AppColors.successDim : col.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isConnected
                ? AppColors.success.withOpacity(0.4)
                : col.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              target.type == ConnectionType.ble
                  ? Icons.bluetooth : Icons.usb,
              color: isConnected ? AppColors.success : col.textSecondary,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                target.displayName,
                style: TextStyle(
                  fontSize: 14,
                  color: isConnected ? AppColors.success : col.textPrimary,
                  fontWeight: isConnected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            StatusBadge(
              label: isConnected ? 'Conectado' : 'Conectar',
              isOk: isConnected,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPorts extends StatelessWidget {
  final VoidCallback onScan;
  final bool isScanning;
  const _EmptyPorts({required this.onScan, required this.isScanning});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.usb_off, size: 56, color: col.textDisabled),
          const SizedBox(height: 16),
          Text('No se encontraron puertos',
              style: TextStyle(color: col.textSecondary,
                  fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('Conecta el RECEPTOR por cable USB y presiona Buscar.',
              style: TextStyle(color: col.textDisabled, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.search, size: 18),
            label: Text(isScanning ? 'Buscando...' : 'Buscar dispositivos'),
            onPressed: isScanning ? null : onScan,
          ),
        ],
      ),
    );
  }
}

// ── Diagnostic checklist ───────────────────────────────────────────────────

class _DiagnosticChecklist extends StatefulWidget {
  @override
  State<_DiagnosticChecklist> createState() => _DiagnosticChecklistState();
}

class _DiagnosticChecklistState extends State<_DiagnosticChecklist> {
  final List<bool> _checked = [false, false, false, false];

  static const _items = [
    '¿La plataforma está encendida?',
    '¿El cable USB está bien conectado?',
    '¿Seleccionaste el puerto correcto?',
    '¿Está configurado como 921600 baud?',
  ];

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.checklist_rounded,
                    color: AppColors.warning, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Lista de verificacion',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: col.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          ..._items.asMap().entries.map(
            (entry) => CheckboxListTile(
              dense: true,
              value: _checked[entry.key],
              onChanged: (v) =>
                  setState(() => _checked[entry.key] = v ?? false),
              activeColor: AppColors.success,
              checkColor: Colors.black,
              title: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 13,
                  color: _checked[entry.key]
                      ? col.textDisabled
                      : col.textPrimary,
                  decoration: _checked[entry.key]
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ── Help footer ─────────────────────────────────────────────────────────────

class _HelpFooter extends StatelessWidget {
  const _HelpFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'En Android el RECEPTOR se conecta por USB OTG. En iOS por Bluetooth LE.',
        style: TextStyle(fontSize: 11, color: context.col.textDisabled),
        textAlign: TextAlign.center,
      ),
    );
  }
}
