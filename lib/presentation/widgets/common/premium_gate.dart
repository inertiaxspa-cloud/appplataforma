import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../providers/subscription_provider.dart';

/// Premium features that require a paid subscription.
enum PremiumFeature {
  normatives,       // Pro+
  autoReports,      // Pro+
  teamDashboard,    // Team
  apiAccess,        // Team
  multiUser,        // Team
}

extension PremiumFeatureExt on PremiumFeature {
  bool get requiresTeam => [
    PremiumFeature.teamDashboard,
    PremiumFeature.apiAccess,
    PremiumFeature.multiUser,
  ].contains(this);

  bool isUnlocked(SubscriptionState sub) {
    if (requiresTeam) return sub.isTeam;
    return sub.isPro;
  }
}

/// Wraps a child widget and shows a lock overlay if the user doesn't
/// have the required subscription plan.
class PremiumGate extends ConsumerWidget {
  final PremiumFeature feature;
  final Widget child;
  /// If true, shows a compact lock icon instead of the full overlay.
  final bool compact;

  const PremiumGate({
    super.key,
    required this.feature,
    required this.child,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider);
    if (feature.isUnlocked(sub)) return child;

    if (compact) {
      return Stack(
        children: [
          Opacity(opacity: 0.4, child: child),
          Positioned(
            right: 4, top: 4,
            child: Icon(Icons.lock, size: 14, color: AppColors.warning),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Opacity(opacity: 0.3, child: IgnorePointer(child: child)),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 32, color: AppColors.warning),
                const SizedBox(height: 8),
                Text(AppStrings.get('premium_feature'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppColors.warning)),
                const SizedBox(height: 4),
                Text(
                  feature.requiresTeam
                      ? AppStrings.get('unlock_with_team')
                      : AppStrings.get('unlock_with_pro'),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.star, size: 16),
                  label: Text(AppStrings.get('upgrade'), style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onPressed: () => context.push('/subscription'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
