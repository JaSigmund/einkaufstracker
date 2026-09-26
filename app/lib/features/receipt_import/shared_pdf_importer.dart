import 'dart:async';
import 'dart:typed_data';

import '../../data/share/shared_pdf_source.dart';
import 'receipt_import_service.dart';

/// Verbindet "PDF von einer anderen App geteilt" mit der Pruefansicht des Imports.
///
/// Ist noch niemand angemeldet (App-Start per Teilen vor dem Login), wird das PDF gemerkt und nach der
/// Anmeldung ueber [onSignedIn] verarbeitet.
class SharedPdfImporter {
  SharedPdfImporter({
    required this.source,
    required this.isSignedIn,
    required this.preview,
    required this.openReview,
  });

  final SharedPdfSource source;
  final bool Function() isSignedIn;
  final Future<ImportPreview> Function(Uint8List bytes) preview;
  final void Function(ImportPreview preview) openReview;

  StreamSubscription<Uint8List>? _sub;
  Uint8List? _pending;

  /// Beginnt zu lauschen und holt ein PDF ab, mit dem die App gestartet wurde.
  Future<void> start() async {
    _sub = source.incoming.listen(_handle);
    final initial = await source.takeInitial();
    if (initial != null) await _handle(initial);
  }

  /// Nach erfolgreicher Anmeldung aufrufen.
  Future<void> onSignedIn() async {
    final bytes = _pending;
    if (bytes == null) return;
    _pending = null;
    await _handle(bytes);
  }

  Future<void> _handle(Uint8List bytes) async {
    if (!isSignedIn()) {
      _pending = bytes;
      return;
    }
    openReview(await preview(bytes));
  }

  void dispose() => _sub?.cancel();
}
