import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

class ErrorScreen extends StatefulWidget {
  final String? errorMessage;
  final FlutterErrorDetails? details;

  const ErrorScreen({
    super.key,
    this.errorMessage,
    this.details,
  });

  @override
  State<ErrorScreen> createState() => _ErrorScreenState();
}

class _ErrorScreenState extends State<ErrorScreen> {
  bool _showDetails = false;

  String get _displayMessage =>
      widget.errorMessage ??
      widget.details?.exceptionAsString() ??
      'Error desconocido.';

  String get _stackTrace =>
      widget.details?.stack?.toString() ?? 'Sin stack trace disponible.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              // Error icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.danger.withOpacity(0.12),
                  border: Border.all(
                    color: AppColors.danger.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.danger,
                  size: 38,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Algo salió mal',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'La app encontró un error inesperado. Puedes intentar reiniciarla.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              // Collapsible technical detail
              GestureDetector(
                onTap: () => setState(() => _showDetails = !_showDetails),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF2D3748), width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.code_rounded,
                                size: 16,
                                color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Detalles técnicos',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              _showDetails
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: AppColors.textDisabled,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                      if (_showDetails) ...[
                        Container(
                          height: 1,
                          color: const Color(0xFF2D3748),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayMessage,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.danger,
                                  fontFamily: 'monospace',
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Stack trace:',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textDisabled,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                height: 160,
                                child: SingleChildScrollView(
                                  child: Text(
                                    _stackTrace,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textDisabled,
                                      fontFamily: 'monospace',
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 3),
              // Restart button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text(
                    'Reiniciar app',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () {
                    // Navigate to home, which triggers a full widget rebuild
                    // via go_router's shell route.
                    try {
                      context.go('/');
                    } catch (_) {
                      // If context is invalid (during a render error),
                      // we cannot navigate. The user must restart manually.
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    minimumSize: const Size(double.infinity, 56),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
