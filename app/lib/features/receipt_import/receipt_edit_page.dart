import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../domain/receipt/parsed_receipt.dart';
import '../../core/vienna_time.dart';
import 'receipt_import_service.dart';

enum EditKind { article, discount, deposit, billDiscount }

extension on EditKind {
  String get label => switch (this) {
        EditKind.article => 'Artikel',
        EditKind.discount => 'Rabatt auf einen Artikel',
        EditKind.deposit => 'Pfand',
        EditKind.billDiscount => 'Rabatt auf den ganzen Bon',
      };
}

/// Eine Zeile im Editor. Artikel, Rabatte, Pfand und Bon-Rabatte stehen in einer Liste.
class EditLine {
  EditLine({required this.name, required this.cents, required this.kind, this.quantity = 1, this.quantityUnit = 'piece', this.taxCode});

  String name;
  int cents;
  EditKind kind;
  double quantity;
  String quantityUnit;
  String? taxCode;
}

List<EditLine> editLinesOf(ParsedReceipt r) => [
      for (final i in r.items)
        EditLine(
          name: i.rawText,
          cents: i.lineTotalCents,
          kind: switch (i.kind) {
            ReceiptItemKind.article => EditKind.article,
            ReceiptItemKind.discount => EditKind.discount,
            ReceiptItemKind.deposit => EditKind.deposit,
          },
          quantity: i.quantity,
          quantityUnit: i.quantityUnit,
          taxCode: i.taxCode,
        ),
      for (final d in r.bonDiscounts)
        EditLine(name: d.percent == null ? d.name : '${d.name} ${d.percent}%', cents: d.cents, kind: EditKind.billDiscount),
    ];

/// Baut aus den Editor-Zeilen wieder einen Bon.
ParsedReceipt receiptFromEditLines(
  ParsedReceipt? base,
  List<EditLine> lines, {
  required int totalCents,
  required DateTime purchasedAtUtc,
  String? chain,
}) {
  return ParsedReceipt.edited(
    base: base,
    chain: chain,
    totalCents: totalCents,
    purchasedAtUtc: purchasedAtUtc,
    items: [
      for (final l in lines.where((l) => l.kind != EditKind.billDiscount))
        ParsedItem(
          rawText: l.name,
          kind: switch (l.kind) {
            EditKind.discount => ReceiptItemKind.discount,
            EditKind.deposit => ReceiptItemKind.deposit,
            _ => ReceiptItemKind.article,
          },
          lineTotalCents: l.cents,
          taxCode: l.taxCode,
          quantity: l.quantity,
          quantityUnit: l.quantityUnit,
        ),
    ],
    bonDiscounts: [for (final l in lines.where((l) => l.kind == EditKind.billDiscount)) BonDiscount(name: l.name, cents: l.cents)],
  );
}

/// Bearbeitung vor dem Speichern, unabhaengig davon, wie der Bon gelesen wurde (PDF, lokal, Cloud). Gibt die
/// bearbeitete Vorschau per `context.pop` zurueck.
class ReceiptEditPage extends StatefulWidget {
  const ReceiptEditPage({super.key, required this.preview});

  final ImportPreview preview;

  @override
  State<ReceiptEditPage> createState() => _ReceiptEditPageState();
}

class _ReceiptEditPageState extends State<ReceiptEditPage> {
  late List<EditLine> _lines;
  late int _totalCents;
  late DateTime _purchasedAtUtc;
  String? _chain;
  late final TextEditingController _totalCtrl;

  @override
  void initState() {
    super.initState();
    final r = widget.preview.receipt;
    _lines = r.isParsed ? editLinesOf(r) : [];
    _totalCents = r.totalCents ?? 0;
    _purchasedAtUtc = r.purchasedAtUtc ?? DateTime.now().toUtc();
    _chain = r.chain;
    _totalCtrl = TextEditingController(text: _plain(_totalCents));
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    super.dispose();
  }

  String _plain(int cents) => formatEuro(cents).replaceAll(' €', '').replaceAll('.', '');

  int get _linesSum => _lines.fold<int>(0, (s, l) => s + l.cents);

  Future<void> _editLine(int? index) async {
    final result = await showDialog<EditLine>(
      context: context,
      builder: (ctx) => _LineDialog(initial: index == null ? null : _lines[index]),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _lines.add(result);
      } else {
        _lines[index] = result;
      }
    });
  }

  Future<void> _pickDateTime() async {
    final local = utcToViennaLocal(_purchasedAtUtc);
    final date = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay(hour: local.hour, minute: local.minute));
    if (time == null) return;
    setState(() => _purchasedAtUtc = viennaLocalToUtc(date.year, date.month, date.day, time.hour, time.minute));
  }

  void _apply() {
    final r = receiptFromEditLines(widget.preview.receipt.isParsed ? widget.preview.receipt : null, _lines,
        totalCents: _totalCents, purchasedAtUtc: _purchasedAtUtc, chain: _chain);
    context.pop(widget.preview.copyWith(receipt: r, edited: true, clearError: true));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final diff = _totalCents - _linesSum;
    final ok = diff == 0 && _lines.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Bon bearbeiten')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-line'),
        onPressed: () => _editLine(null),
        icon: const Icon(Icons.add),
        label: const Text('Position'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('edit-chain'),
                  initialValue: const ['Billa', 'Hofer'].contains(_chain) ? _chain : 'Sonstiger Händler',
                  decoration: const InputDecoration(labelText: 'Händler'),
                  items: [
                    for (final c in const ['Billa', 'Hofer', 'Sonstiger Händler']) DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() => _chain = v == 'Sonstiger Händler' ? null : v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const Key('edit-total'),
                  controller: _totalCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Summe laut Bon (€)'),
                  onChanged: (v) => setState(() => _totalCents = parseEuroCents(v) ?? _totalCents),
                ),
              ),
            ]),
          ),
          ListTile(
            key: const Key('edit-date'),
            leading: const Icon(Icons.event_outlined),
            title: Text(formatViennaDateTime(_purchasedAtUtc)),
            subtitle: const Text('Einkaufszeitpunkt, antippen zum Ändern'),
            onTap: _pickDateTime,
          ),
          Container(
            key: const Key('edit-check'),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ok ? t.colorScheme.primaryContainer : t.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                  color: ok ? t.colorScheme.onPrimaryContainer : t.colorScheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ok
                      ? 'Die Positionen ergeben ${formatEuro(_linesSum)}, das entspricht der Summe.'
                      : _lines.isEmpty
                          ? 'Noch keine Positionen. Mit „Position" hinzufügen.'
                          : 'Die Positionen ergeben ${formatEuro(_linesSum)}, die Summe ist ${formatEuro(_totalCents)} (Differenz ${formatEuro(diff)}).',
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          for (var i = 0; i < _lines.length; i++)
            Dismissible(
              key: ObjectKey(_lines[i]),
              direction: DismissDirection.endToStart,
              background: Container(
                color: t.colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: Icon(Icons.delete_outline, color: t.colorScheme.onErrorContainer),
              ),
              onDismissed: (_) => setState(() => _lines.removeAt(i)),
              child: ListTile(
                key: Key('line-$i'),
                dense: true,
                title: Text(_lines[i].name),
                subtitle: Text([
                  if (_lines[i].kind != EditKind.article) _lines[i].kind.label,
                  if (_lines[i].quantity != 1) '${formatQuantity(_lines[i].quantity)}${_lines[i].quantityUnit == 'piece' ? ' ×' : ' ${_lines[i].quantityUnit}'}',
                ].join(' · ')),
                trailing: Text(formatEuro(_lines[i].cents), style: TextStyle(color: _lines[i].cents < 0 ? t.colorScheme.primary : null)),
                onTap: () => _editLine(i),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => context.pop(), child: const Text('Abbrechen'))),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('edit-apply'),
                onPressed: _lines.isEmpty ? null : _apply,
                child: const Text('Übernehmen'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LineDialog extends StatefulWidget {
  const _LineDialog({this.initial});
  final EditLine? initial;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _qty;
  late EditKind _kind;
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.name ?? '');
    _amount = TextEditingController(text: i == null ? '' : formatEuro(i.cents).replaceAll(' €', '').replaceAll('.', ''));
    _qty = TextEditingController(text: i == null ? '1' : formatQuantity(i.quantity));
    _kind = i?.kind ?? EditKind.article;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _ok() {
    final name = _name.text.trim();
    var cents = parseEuroCents(_amount.text);
    final qty = double.tryParse(_qty.text.replaceAll(',', '.').trim());
    if (name.isEmpty) return setState(() => _error = 'Bitte einen Namen eingeben.');
    if (cents == null) return setState(() => _error = 'Bitte einen Betrag wie 2,49 eingeben.');
    if (qty == null || qty == 0) return setState(() => _error = 'Bitte eine Menge eingeben.');
    // Rabatte sind immer negativ, egal wie eingegeben
    if ((_kind == EditKind.discount || _kind == EditKind.billDiscount) && cents > 0) cents = -cents;
    final i = widget.initial;
    Navigator.pop(
      context,
      EditLine(
        name: name,
        cents: cents,
        kind: _kind,
        quantity: qty,
        quantityUnit: i?.quantityUnit ?? 'piece',
        taxCode: i?.taxCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.initial == null ? 'Position hinzufügen' : 'Position bearbeiten'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8), // Platz fuer das schwebende Label des ersten Feldes
            TextField(key: const Key('line-name'), controller: _name, decoration: const InputDecoration(labelText: 'Name'), textCapitalization: TextCapitalization.sentences),
            const SizedBox(height: 16),
            TextField(
              key: const Key('line-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Betrag der Zeile (€)'),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('line-qty'),
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Menge'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<EditKind>(
              key: const Key('line-kind'),
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Art'),
              items: [for (final k in EditKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(key: const Key('line-ok'), onPressed: _ok, child: const Text('OK')),
        ],
      );
}
