import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/providers.dart';
import '../../data/local/database.dart';

/// Zeigt den abgelegten Originalbeleg eines Bons: Foto (zoombar) oder PDF.
class ReceiptFilePage extends ConsumerStatefulWidget {
  const ReceiptFilePage({super.key, required this.file});

  final ReceiptFile file;

  @override
  ConsumerState<ReceiptFilePage> createState() => _ReceiptFilePageState();
}

class _ReceiptFilePageState extends ConsumerState<ReceiptFilePage> {
  late final Future<Uint8List?> _bytes = ref.read(receiptFileServiceProvider).bytes(widget.file);

  @override
  Widget build(BuildContext context) {
    final isPdf = widget.file.kind == 'pdf';
    return Scaffold(
      appBar: AppBar(title: Text(isPdf ? 'Originalbeleg (PDF)' : 'Originalbeleg (Foto, Seite ${widget.file.pageNo})')),
      body: FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final data = snap.data;
          if (data == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Die Datei ist auf diesem Gerät nicht vorhanden und konnte nicht geladen werden. '
                  'Sie wird angezeigt, sobald das Gerät online ist und die Datei hochgeladen wurde.',
                  key: Key('file-unavailable'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (isPdf) return PdfViewer.data(data, sourceName: 'beleg-${widget.file.id}.pdf');
          return InteractiveViewer(
            key: const Key('file-image'),
            maxScale: 6,
            child: Center(child: Image.memory(data, fit: BoxFit.contain)),
          );
        },
      ),
    );
  }
}
