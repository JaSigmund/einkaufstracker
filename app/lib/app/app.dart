import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../core/clock.dart';
import '../domain/sync/sync_schedule.dart';
import '../features/diary/quick_action_handler.dart';
import '../features/receipt_import/shared_pdf_importer.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class EinkaufstrackerApp extends ConsumerStatefulWidget {
  const EinkaufstrackerApp({super.key});

  @override
  ConsumerState<EinkaufstrackerApp> createState() => _EinkaufstrackerAppState();
}

class _EinkaufstrackerAppState extends ConsumerState<EinkaufstrackerApp> with WidgetsBindingObserver {
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  late final SharedPdfImporter _shared;
  late final QuickActionHandler _quick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Zusaetzlich zum Sync nach jeder Aenderung: regelmaessig und beim Zurueckkehren in die App. Der Takt ist kurz, ob
    // wirklich synchronisiert wird, entscheidet die Haushaltsgroesse (ADR-018: allein alle 2 Minuten, zu mehreren alle 30 s).
    _timer = Timer.periodic(syncTickPeriod, (_) => _syncIfDue());
    // Sobald das Netz zurueckkommt (z.B. Flugmodus aus), sofort synchronisieren
    _connectivity = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) _sync();
    });
    // PDFs aus anderen Apps (Teilen / Oeffnen mit): direkt in die Pruefansicht des Imports
    _shared = SharedPdfImporter(
      source: ref.read(sharedPdfSourceProvider),
      isSignedIn: () => ref.read(sessionProvider).value != null,
      preview: (bytes) => ref.read(receiptImportServiceProvider).preview(bytes),
      openReview: (preview) => ref.read(routerProvider).push('/import-review', extra: preview),
    );
    _shared.start();
    // Widget auf dem Startbildschirm und langes Druecken auf das App-Symbol (ADR-041)
    _quick = QuickActionHandler(
      source: ref.read(quickActionSourceProvider),
      isSignedIn: () => Supabase.instance.client.auth.currentSession != null,
      takeWater: () => ref.read(supplementRepositoryProvider).takeWater(),
      open: () => ref.read(routerProvider).push('/quick-intake'),
    );
    _quick.start();
    // Hintergrund-Auffrischung beim App-Start (Doku 06 §5, Schritt 5): haelt die geplanten
    // Ablauf-Erinnerungen konsistent, auch nach einem Geraete-Neustart (der die Alarme loescht).
    _rescheduleReminders();
  }

  void _sync() => ref.read(syncControllerProvider.notifier).sync();

  void _syncIfDue() {
    final last = ref.read(syncControllerProvider).lastSync;
    final since = last == null ? null : appClock.now().difference(last);
    if (isSyncDue(members: ref.read(householdSizeProvider), sinceLastSync: since)) _sync();
  }

  // Codereview-Fund 2026-10-01 (Fehlerbericht "Ablauf-Erinnerung kommt nicht an, auch nicht nach
  // Neustart"): dieser Aufruf lief bisher komplett unbeobachtet ("fire and forget") -- ein Fehler darin
  // (z.B. keine Benachrichtigungs-Berechtigung, Plugin-Ausnahme) wurde nirgends sichtbar, auch nicht in
  // einer Debug-Session. `debugPrint` erscheint in `flutter logs`/`adb logcat`, ohne die Oberflaeche mit
  // einer Fehlermeldung zu stoeren (das laeuft im Hintergrund, der Nutzer hat nichts angefordert).
  void _rescheduleReminders() {
    rescheduleExpiryReminders(ref).catchError((Object e, StackTrace st) {
      debugPrint('[expiry-reminders] Neuplanen fehlgeschlagen: $e\n$st');
    });
    rescheduleFluidReminders(ref);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _connectivity?.cancel();
    _shared.dispose();
    _quick.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sobald eine Sitzung besteht (Start oder Login), sofort synchronisieren
    ref.listen(sessionProvider, (prev, next) {
      if (next.value != null) {
        _sync();
        _shared.onSignedIn();
        _quick.onSignedIn();
      }
    });
    // Nach jeder Inventaraenderung (Doku 06 §5, Schritt 1): der aktive Bestand aendert sich bei jedem
    // Kauf, Oeffnen, Aufbrauchen etc., der Live-Stream feuert also genau dann neu.
    ref.listen(activeInventoryStreamProvider, (prev, next) {
      if (next.hasValue) _rescheduleReminders();
    });
    // Auch ein neuer, noch unbestaetigter Bon-Vorschlag hat schon ein geschaetztes Ablaufdatum (Fehlerbericht
    // "keine Push-Benachrichtigung", 2026-09-28) und muss die Erinnerungen deshalb ebenfalls neu planen.
    ref.listen(inventorySuggestionsStreamProvider, (prev, next) {
      if (next.hasValue) _rescheduleReminders();
    });
    return MaterialApp.router(
      title: 'Einkaufstracker',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
