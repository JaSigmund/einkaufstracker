import 'package:einkaufstracker/domain/shopping_list/list_archive.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Row = ({String id, DateTime at, String list});

void main() {
  List<ArchivedPurchase<_Row>> group(List<_Row> rows) => groupArchivedPurchases(rows, archivedAt: (_Row r) => r.at, listId: (_Row r) => r.list);

  test('Eintraege mit demselben Zeitstempel sind ein Einkauf, der neueste zuerst', () {
    final older = DateTime.utc(2026, 10, 30, 18);
    final newer = DateTime.utc(2026, 11, 2, 12);
    final result = group([
      (id: 'a', at: older, list: 'l1'),
      (id: 'b', at: newer, list: 'l1'),
      (id: 'c', at: older, list: 'l1'),
    ]);

    expect(result.map((p) => p.archivedAt), [newer, older]);
    expect(result.last.items.map((r) => r.id), ['a', 'c']);
  });

  test('ein Einkauf bleibt zusammen, auch wenn seine Liste geloescht wurde und ein Teil schon umgezogen ist', () {
    final at = DateTime.utc(2026, 11, 2);
    final result = group([(id: 'a', at: at, list: 'weg'), (id: 'b', at: at, list: 'standard')]);
    expect(result, hasLength(1));
    expect(result.single.items, hasLength(2));
  });

  test('Zeitstempel in Ortszeit und UTC zaehlen als derselbe Moment', () {
    final utc = DateTime.utc(2026, 11, 2, 12);
    final result = group([(id: 'a', at: utc, list: 'l'), (id: 'b', at: utc.toLocal(), list: 'l')]);
    expect(result, hasLength(1));
  });

  test('nichts archiviert: leere Liste', () => expect(group(const []), isEmpty));
}
