import 'billa_text_parser.dart';
import 'hofer_text_parser.dart';
import 'parsed_receipt.dart';

/// Haendler-Vermutung aus den Kopfzeilen (Fehlerbericht "Featurevorschlag Hofer-Erkennung", 2026-09-28):
/// unbekannte oder nicht erkannte Haendler gelten als Billa, da das bei Weitem der haeufigste Fall ist.
/// Auch als Hinweis fuer die Cloud-Vision-Erkennung nutzbar (Codereview-Fund 2026-10-01), wenn die lokale
/// Erkennung insgesamt scheitert und der volle Parser deshalb nicht durchlaeuft.
String detectChainHint(String text) {
  final header = text.split('\n').take(6).join('\n');
  return RegExp(r'\bHOFER\b', caseSensitive: false).hasMatch(header) ? 'Hofer' : 'Billa';
}

/// Waehlt anhand der Kopfzeilen den passenden Parser: bislang gab es nur [BillaTextParser], jetzt
/// zusaetzlich [HoferTextParser].
ParsedReceipt parseReceiptText(String text, {bool lenient = true}) {
  if (detectChainHint(text) == 'Hofer') return HoferTextParser(lenient: lenient).parse(text);
  return BillaTextParser(lenient: lenient).parse(text);
}
