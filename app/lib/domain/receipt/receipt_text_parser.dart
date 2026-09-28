import 'billa_text_parser.dart';
import 'hofer_text_parser.dart';
import 'parsed_receipt.dart';

/// Waehlt anhand der Kopfzeilen den passenden Parser (Fehlerbericht "Featurevorschlag Hofer-Erkennung",
/// 2026-09-28): bislang gab es nur [BillaTextParser], jetzt zusaetzlich [HoferTextParser]. Unbekannte oder
/// nicht erkannte Haendler fallen auf Billa zurueck (bisheriges Verhalten), da das bei Weitem der haeufigste
/// Fall ist.
ParsedReceipt parseReceiptText(String text, {bool lenient = true}) {
  final header = text.split('\n').take(6).join('\n');
  if (RegExp(r'\bHOFER\b', caseSensitive: false).hasMatch(header)) {
    return HoferTextParser(lenient: lenient).parse(text);
  }
  return BillaTextParser(lenient: lenient).parse(text);
}
