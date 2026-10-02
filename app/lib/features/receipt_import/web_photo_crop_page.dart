import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Web-Pendant zum automatischen Zahlungsblock-Zuschnitt (Codereview-Fund 2026-10-01, Go/No-Go B4
/// "Zahlungsdaten verlassen nie das Geraet"). Nativ findet ML Kit die "Summe"-Zeile und schneidet dort
/// automatisch ab (`ImagePreparer`/`image_prep.dart`); ML Kit gibt es im Browser nicht, deshalb markiert
/// hier ein Mensch von Hand, wo der Bon endet und der Zahlungsteil (Kartennummer, Terminal-ID) beginnt.
/// Liefert `cutY` in Bildpixeln (nach EXIF-Rotation, siehe `prepareForCloudBytes`) zurueck, oder `null`
/// bei Abbruch.
class WebPhotoCropPage extends StatefulWidget {
  const WebPhotoCropPage({super.key, required this.jpeg});

  final Uint8List jpeg;

  @override
  State<WebPhotoCropPage> createState() => _WebPhotoCropPageState();
}

class _WebPhotoCropPageState extends State<WebPhotoCropPage> {
  int _imageWidth = 1;
  int _imageHeight = 1;
  bool _decodeFailed = false;

  /// Anteil der Bildhoehe, konservativ ueber der Mitte als Startwert -- bei den meisten Bons steht die
  /// Summe im oberen Drittel bis zur Haelfte, der Zahlungsblock (Terminal, Kartennummer) danach.
  double _lineFraction = 0.6;

  @override
  void initState() {
    super.initState();
    try {
      // Dieselbe Reihenfolge wie prepareForCloudBytes (decode + bakeOrientation), damit `cutY` spaeter
      // zu denselben, nach EXIF korrigierten Bildmassen passt, die hier auch angezeigt werden.
      final decoded = img.bakeOrientation(img.decodeJpg(widget.jpeg)!);
      _imageWidth = decoded.width;
      _imageHeight = decoded.height;
    } catch (_) {
      _decodeFailed = true;
    }
  }

  void _updateFraction(double localY, double displayHeight) {
    if (displayHeight <= 0) return;
    setState(() => _lineFraction = (localY / displayHeight).clamp(0.05, 0.95));
  }

  @override
  Widget build(BuildContext context) {
    if (_decodeFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Zahlungsblock markieren')),
        body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Das Foto konnte nicht gelesen werden.'))),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Zahlungsblock markieren')),
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Ziehe die Linie direkt über die Summen-Zeile. Alles darunter (Zahlungsart, Kartennummer, '
            'Terminal) wird abgeschnitten und verlässt dieses Gerät nie.',
          ),
        ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _imageWidth / _imageHeight,
              child: LayoutBuilder(builder: (context, constraints) {
                final displayHeight = constraints.maxHeight;
                return GestureDetector(
                  key: const Key('web-crop-area'),
                  onVerticalDragUpdate: (d) => _updateFraction(d.localPosition.dy, displayHeight),
                  onTapDown: (d) => _updateFraction(d.localPosition.dy, displayHeight),
                  child: Stack(fit: StackFit.expand, children: [
                    Image.memory(widget.jpeg, fit: BoxFit.fill),
                    Positioned(
                      top: displayHeight * _lineFraction,
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(color: Colors.black.withValues(alpha: 0.55)),
                    ),
                    Positioned(
                      top: displayHeight * _lineFraction - 1,
                      left: 0,
                      right: 0,
                      child: Container(height: 3, color: Colors.redAccent),
                    ),
                  ]),
                );
              }),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              key: const Key('web-crop-confirm'),
              onPressed: () => Navigator.of(context).pop(_lineFraction * _imageHeight),
              child: const Text('Bestätigen und hochladen'),
            ),
          ),
        ),
      ]),
    );
  }
}
