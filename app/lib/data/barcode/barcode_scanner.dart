import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;

/// Kamera-Barcode-Scan (EAN-13/EAN-8/UPC-A). Gibt den erkannten Code zurueck, oder null bei Abbruch.
abstract class BarcodeScanner {
  Future<String?> scan(BuildContext context);
}

class MobileBarcodeScanner implements BarcodeScanner {
  @override
  Future<String?> scan(BuildContext context) => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _CameraPage()));
}

class _CameraPage extends StatefulWidget {
  const _CameraPage();
  @override
  State<_CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<_CameraPage> {
  final _controller = ms.MobileScannerController(formats: const [ms.BarcodeFormat.ean13, ms.BarcodeFormat.ean8, ms.BarcodeFormat.upcA]);
  var _handled = false;

  void _onDetect(ms.BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(code);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Barcode scannen'), backgroundColor: Colors.black, foregroundColor: Colors.white),
        backgroundColor: Colors.black,
        body: ms.MobileScanner(controller: _controller, onDetect: _onDetect),
      );
}
