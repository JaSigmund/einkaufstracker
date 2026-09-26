import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Zusaetzlich zum Sync nach jeder Aenderung: regelmaessig und beim Zurueckkehren in die App
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _sync());
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
  }

  void _sync() => ref.read(syncControllerProvider.notifier).sync();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _connectivity?.cancel();
    _shared.dispose();
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
      }
    });
    return MaterialApp.router(
      title: 'Einkaufstracker',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
