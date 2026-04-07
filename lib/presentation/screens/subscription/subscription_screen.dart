import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../providers/subscription_provider.dart';
import '../../theme/app_theme.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  /// Base URL for the payment page (hosted on Render).
  /// Updated by the user's partner with the real URL.
  static const _payBaseUrl = 'https://appencoderverticalandroid.onrender.com/force-pay.html';

  void _openCheckout(BuildContext context, WidgetRef ref, String plan, String provider) async {
    final client = ref.read(subscriptionProvider.notifier);
    // Build checkout URL with auth params
    final user = ref.read(subscriptionProvider);
    // For now, just open the pay page — backend handles the rest
    final uri = Uri.parse('$_payBaseUrl?plan=$plan&provider=$provider');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider);
    final col = context.col;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('subscription')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Trial banner ──────────────────────────────────────────────
            if (sub.isTrial)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${AppStrings.get('trial_active')} — ${sub.trialDaysLeft} ${AppStrings.get('trial_days_left')}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Current plan badge ────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: col.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: col.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user, size: 20,
                      color: sub.isPro ? AppColors.success : col.textSecondary),
                  const SizedBox(width: 10),
                  Text('${AppStrings.get('current_plan')}: ',
                      style: TextStyle(fontSize: 13, color: col.textSecondary)),
                  Text(
                    sub.plan == SubscriptionPlan.team ? 'TEAM'
                        : sub.plan == SubscriptionPlan.pro ? 'PRO' : 'FREE',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        color: sub.isPro ? AppColors.success : col.textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Plan cards ────────────────────────────────────────────────
            _PlanCard(
              name: AppStrings.get('plan_free'),
              price: '\$0',
              period: '',
              description: AppStrings.get('plan_free_desc'),
              features: const [
                '8 tests (CMJ, SJ, DJ, IMTP, CoP, Multi, Libre)',
                'Dual platform + orientación',
                'PDF reports + CSV export',
                'Cloud sync (Supabase)',
                'Historial ilimitado',
                'Calibración per-cell',
              ],
              isActive: sub.plan == SubscriptionPlan.free,
              color: col.textSecondary,
            ),
            const SizedBox(height: 12),

            _PlanCard(
              name: AppStrings.get('plan_pro'),
              price: '\$19',
              period: AppStrings.get('per_month'),
              annualPrice: '\$169${AppStrings.get('per_year')}',
              description: AppStrings.get('plan_pro_desc'),
              features: const [
                'Todo del plan Free +',
                'Normativas internacionales (NSCA, Kistler)',
                'Bandas de referencia por edad/sexo/nivel',
                'Reportes automáticos (semanal/mensual)',
                'Alertas de asimetría y tendencias',
              ],
              isActive: sub.plan == SubscriptionPlan.pro,
              color: AppColors.primary,
              onPayPal: () => _openCheckout(context, ref, 'pro', 'paypal'),
              onMercadoPago: () => _openCheckout(context, ref, 'pro', 'mercadopago'),
            ),
            const SizedBox(height: 12),

            _PlanCard(
              name: AppStrings.get('plan_team'),
              price: '\$59',
              period: AppStrings.get('per_month'),
              annualPrice: '\$529${AppStrings.get('per_year')}',
              description: AppStrings.get('plan_team_desc'),
              features: const [
                'Todo del plan Pro +',
                'Dashboard de equipo',
                'Hasta 10 usuarios',
                'API REST para integraciones',
                'Ranking y comparativa grupal',
                'Soporte prioritario',
              ],
              isActive: sub.plan == SubscriptionPlan.team,
              color: AppColors.warning,
              onPayPal: () => _openCheckout(context, ref, 'team', 'paypal'),
              onMercadoPago: () => _openCheckout(context, ref, 'team', 'mercadopago'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Plan Card Widget ────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final String name;
  final String price;
  final String period;
  final String? annualPrice;
  final String description;
  final List<String> features;
  final bool isActive;
  final Color color;
  final VoidCallback? onPayPal;
  final VoidCallback? onMercadoPago;

  const _PlanCard({
    required this.name,
    required this.price,
    required this.period,
    this.annualPrice,
    required this.description,
    required this.features,
    required this.isActive,
    required this.color,
    this.onPayPal,
    this.onMercadoPago,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? color : col.border,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
              if (isActive) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(AppStrings.get('current_plan'),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                ),
              ],
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$price$period',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: col.textPrimary)),
                  if (annualPrice != null)
                    Text(annualPrice!,
                        style: TextStyle(fontSize: 11, color: col.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(description, style: TextStyle(fontSize: 12, color: col.textSecondary)),
          const SizedBox(height: 12),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(child: Text(f, style: TextStyle(fontSize: 12, color: col.textPrimary))),
              ],
            ),
          )),

          // Payment buttons (only for paid plans, not active)
          if (onPayPal != null && !isActive) ...[
            const SizedBox(height: 14),
            Text('${AppStrings.get('pay_with')}:',
                style: TextStyle(fontSize: 11, color: col.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.payment, size: 16),
                    label: const Text('PayPal', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF003087),
                      side: const BorderSide(color: Color(0xFF003087)),
                    ),
                    onPressed: onPayPal,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.account_balance_wallet, size: 16),
                    label: const Text('MercadoPago', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF009EE3),
                      side: const BorderSide(color: Color(0xFF009EE3)),
                    ),
                    onPressed: onMercadoPago,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
