/// Konfiguration aus `--dart-define-from-file=dart_defines.local.json`.
/// Der Publishable Key ist fuer Clients gedacht (durch RLS geschuetzt), gehoert aber trotzdem
/// nicht hartkodiert ins Repo.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
