import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/supabase_service.dart';

/// Subscription plan tiers.
enum SubscriptionPlan { free, pro, team }

/// Subscription state.
class SubscriptionState {
  final SubscriptionPlan plan;
  final String status;   // 'active', 'trialing', 'canceled', 'past_due'
  final DateTime? periodEnd;
  final DateTime? trialEnd;
  final bool isLoading;

  const SubscriptionState({
    this.plan     = SubscriptionPlan.free,
    this.status   = 'active',
    this.periodEnd,
    this.trialEnd,
    this.isLoading = false,
  });

  bool get isPro  => plan == SubscriptionPlan.pro  || plan == SubscriptionPlan.team;
  bool get isTeam => plan == SubscriptionPlan.team;
  bool get isTrial => status == 'trialing';

  int get trialDaysLeft {
    if (trialEnd == null) return 0;
    final diff = trialEnd!.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }

  SubscriptionState copyWith({
    SubscriptionPlan? plan,
    String? status,
    DateTime? periodEnd,
    DateTime? trialEnd,
    bool? isLoading,
  }) => SubscriptionState(
    plan: plan ?? this.plan,
    status: status ?? this.status,
    periodEnd: periodEnd ?? this.periodEnd,
    trialEnd: trialEnd ?? this.trialEnd,
    isLoading: isLoading ?? this.isLoading,
  );
}

/// Manages subscription state — reads from Supabase, caches locally.
class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  SubscriptionNotifier() : super(const SubscriptionState()) {
    _init();
  }

  static const _kPlan       = 'sub_plan';
  static const _kStatus     = 'sub_status';
  static const _kPeriodEnd  = 'sub_period_end';
  static const _kTrialEnd   = 'sub_trial_end';
  static const _kLastCheck  = 'sub_last_check';

  /// Admin emails that always get Team access (for testing).
  static const _adminEmails = {'vicente.iturra@outlook.es'};

  Future<void> _init() async {
    // Load cached state first (fast, offline-capable)
    await _loadCache();
    // Then refresh from server
    await refreshStatus();
  }

  Future<void> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final planName = p.getString(_kPlan) ?? 'free';
      final plan = SubscriptionPlan.values.firstWhere(
          (e) => e.name == planName, orElse: () => SubscriptionPlan.free);
      final status = p.getString(_kStatus) ?? 'active';
      final periodEndMs = p.getInt(_kPeriodEnd);
      final trialEndMs  = p.getInt(_kTrialEnd);

      // Honor cache for up to 7 days without connectivity
      final lastCheck = p.getInt(_kLastCheck) ?? 0;
      final daysSinceCheck = DateTime.now().millisecondsSinceEpoch - lastCheck;
      final cacheExpired = daysSinceCheck > 7 * 24 * 3600 * 1000;

      if (cacheExpired) {
        state = const SubscriptionState(); // fallback to free
      } else {
        state = SubscriptionState(
          plan: plan,
          status: status,
          periodEnd: periodEndMs != null ? DateTime.fromMillisecondsSinceEpoch(periodEndMs) : null,
          trialEnd:  trialEndMs  != null ? DateTime.fromMillisecondsSinceEpoch(trialEndMs)  : null,
        );
      }
    } catch (e) {
      debugPrint('[Subscription] Cache load error: $e');
    }
  }

  Future<void> _saveCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPlan, state.plan.name);
      await p.setString(_kStatus, state.status);
      if (state.periodEnd != null) {
        await p.setInt(_kPeriodEnd, state.periodEnd!.millisecondsSinceEpoch);
      }
      if (state.trialEnd != null) {
        await p.setInt(_kTrialEnd, state.trialEnd!.millisecondsSinceEpoch);
      }
      await p.setInt(_kLastCheck, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[Subscription] Cache save error: $e');
    }
  }

  /// Refresh subscription status from Supabase.
  Future<void> refreshStatus() async {
    try {
      if (!SupabaseService.isConfigured) return;
      final client = SupabaseService.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      // Admin override
      if (_adminEmails.contains(user.email)) {
        state = SubscriptionState(
          plan: SubscriptionPlan.team,
          status: 'active',
          periodEnd: DateTime.now().add(const Duration(days: 3650)),
        );
        await _saveCache();
        return;
      }

      final row = await client
          .from('force_subscriptions')
          .select()
          .eq('user_id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (row == null) {
        // No subscription record — free tier
        state = const SubscriptionState();
        await _saveCache();
        return;
      }

      final planName = row['plan'] as String? ?? 'free';
      final plan = SubscriptionPlan.values.firstWhere(
          (e) => e.name == planName, orElse: () => SubscriptionPlan.free);
      final status = row['status'] as String? ?? 'active';
      final periodEndStr = row['current_period_end'] as String?;
      final trialEndStr  = row['trial_end'] as String?;

      // Check trial expiration
      final trialEnd = trialEndStr != null ? DateTime.tryParse(trialEndStr) : null;
      final trialExpired = trialEnd != null && DateTime.now().isAfter(trialEnd);

      state = SubscriptionState(
        plan: (status == 'trialing' && trialExpired) ? SubscriptionPlan.free : plan,
        status: (status == 'trialing' && trialExpired) ? 'active' : status,
        periodEnd: periodEndStr != null ? DateTime.tryParse(periodEndStr) : null,
        trialEnd: trialEnd,
      );
      await _saveCache();
    } catch (e) {
      debugPrint('[Subscription] Refresh error: $e');
      // Keep cached state on error
    }
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>(
        (_) => SubscriptionNotifier());
