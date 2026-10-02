/// Serialisiert asynchrone Aktionen, die sich sonst beim Lesen-Aendern-Schreiben eines gemeinsamen Werts
/// ueberholen koennten (Codereview-Fund 2026-10-01, siehe `ReceiptFileService._pendingLock`). Eine fehlgeschlagene
/// Aktion blockiert die Warteschlange nicht fuer die naechste.
class AsyncLock {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
