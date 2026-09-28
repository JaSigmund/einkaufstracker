import 'package:supabase_flutter/supabase_flutter.dart';

/// Einstellungen des Haushalts (Tabelle household_settings). In Phase 1 nur online verfuegbar.
class HouseholdSettings {
  const HouseholdSettings({
    required this.notifyTime,
    required this.notifyLeadDays,
    required this.allowCloudOcr,
    required this.keepReceiptImages,
    this.monthlyBudgetCents,
  });

  /// Format HH:mm
  final String notifyTime;
  final int notifyLeadDays;
  final bool allowCloudOcr;
  final bool keepReceiptImages;

  /// Monatsbudget in Cent (Doku 07 §2 "Budget"), `null` = kein Budget gesetzt.
  final int? monthlyBudgetCents;

  factory HouseholdSettings.fromJson(Map<String, dynamic> j) => HouseholdSettings(
        notifyTime: (j['notify_time'] as String).substring(0, 5),
        notifyLeadDays: (j['notify_lead_days'] as num).toInt(),
        allowCloudOcr: j['allow_cloud_ocr'] as bool,
        keepReceiptImages: j['keep_receipt_images'] as bool,
        monthlyBudgetCents: (j['monthly_budget_cents'] as num?)?.toInt(),
      );
}

abstract class SettingsRepository {
  Future<HouseholdSettings> load(String householdId);
  Future<void> update(String householdId, Map<String, dynamic> changes);
}

class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseSettingsRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<HouseholdSettings> load(String householdId) async {
    final row = await _client
        .from('household_settings')
        .select('notify_time, notify_lead_days, allow_cloud_ocr, keep_receipt_images, monthly_budget_cents')
        .eq('household_id', householdId)
        .single();
    return HouseholdSettings.fromJson(row);
  }

  @override
  Future<void> update(String householdId, Map<String, dynamic> changes) async {
    await _client.from('household_settings').update(changes).eq('household_id', householdId);
  }
}
