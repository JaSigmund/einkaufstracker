import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sobald eine Sitzung besteht (Start oder Login), sofort synchronisieren
    ref.listen(sessionProvider, (prev, next) {
      if (next.value != null) _sync();
    });
    return MaterialApp.router(
      title: 'Einkaufstracker',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
