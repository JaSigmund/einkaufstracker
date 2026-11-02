import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/local/database.dart';
import '../../data/products/off_client.dart';
import '../../data/repositories/product_repository.dart';
import '../../domain/inventory/shelf_life_rules.dart';
import '../../domain/products/off_quantity.dart';
import '../../domain/products/packaging.dart';
import '../../domain/receipt/unit_price.dart';
import '../../domain/shopping_list/list_quantity.dart';
import '../common/quantity_dialog.dart';

/// Argumente fuer /product-form: entweder ein unbekannter Barcode (mit optionalem OFF-Vorschlag) oder ein
/// bestehendes Produkt zum Bearbeiten.
class ProductFormArgs {
  const ProductFormArgs({this.ean, this.suggestion, this.existing, this.initialName});
  final String? ean;
  final OffProduct? suggestion;
  final Product? existing;

  /// Vorbelegter Name, wenn das Produkt ohne Barcode aus der Suche heraus angelegt wird.
  final String? initialName;
}

const _amountUnits = [QuantityOption.g, QuantityOption.kg, QuantityOption.ml, QuantityOption.l];
const _locations = [('pantry', 'Vorrat'), ('fridge', 'Kühlschrank'), ('freezer', 'Tiefkühl'), ('other', 'Sonstiges')];
const _dateKinds = [('best_before', 'Mindestens haltbar bis'), ('use_by', 'Zu verbrauchen bis')];

/// Anlegen oder Bearbeiten eines Produkts (Doku 06 §3.5, §4). Nach einem Barcode-Scan eines unbekannten
/// Produkts vorbelegt mit dem OFF-Vorschlag, sonst leer oder mit dem bestehenden Produkt.
class ProductFormPage extends ConsumerStatefulWidget {
  const ProductFormPage({super.key, this.ean, this.suggestion, this.existing, this.initialName});

  final String? initialName;

  /// EAN, mit dem das neue Produkt verknuepft wird (Barcode-Scan eines unbekannten Produkts).
  final String? ean;
  final OffProduct? suggestion;

  /// Bearbeiten eines bestehenden Produkts (dann kein EAN-Verweis).
  final Product? existing;

  @override
  ConsumerState<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends ConsumerState<ProductFormPage> {
  /// Vorbelegung fuer ein neues Produkt aus dem OFF-Namen (Doku 06 §3.2, Roadmap Phase 3), damit
  /// Haltbarkeit-nach-Oeffnen, Lagerort und Datumsart nicht bei jedem Produkt neu eingetippt werden muessen.
  late final _shelfLifeSuggestion = widget.existing == null ? suggestShelfLife(widget.suggestion?.name ?? '') : null;
  late final _name = TextEditingController(text: widget.existing?.name ?? widget.suggestion?.name ?? widget.initialName ?? '');
  late final _brand = TextEditingController(text: widget.existing?.brand ?? widget.suggestion?.brand ?? '');
  /// Was ueber die Packung schon bekannt ist: das Produkt selbst, sonst die Angabe von Open Food Facts ("6 x 65 ml").
  late final Packaging _knownPackaging = _initialPackaging();
  late PackagingKind _kind = widget.existing == null && _offPackaging == null ? PackagingKind.single : PackagingKind.of(_knownPackaging);
  late final _pieceCount = TextEditingController(text: _knownPackaging.piecesPerPack?.toString() ?? '');
  late final _pieceLabel = TextEditingController(text: widget.existing?.pieceLabel ?? '');
  late QuantityOption _amountUnit = _initialAmountUnit();
  late final _packSize = TextEditingController(text: _initialAmount());
  late final _openedDays =
      TextEditingController(text: (widget.existing?.openedShelfLifeDays ?? _shelfLifeSuggestion?.openedShelfLifeDays)?.toString() ?? '');
  String? _categoryId;
  var _categoryInitialized = false;
  late String _looseUnit = widget.existing?.baseUnit == 'l' ? 'l' : 'kg';
  late String _location = widget.existing?.defaultLocation ?? _shelfLifeSuggestion?.location ?? 'pantry';
  late String _dateKind = widget.existing?.defaultDateKind ?? _shelfLifeSuggestion?.dateKind ?? 'best_before';
  late bool _restock = widget.existing?.restock ?? false;
  var _saving = false;
  String? _error;
  late final _search = TextEditingController();
  List<Product> _matches = const [];

  /// Produkte ohne Barcode, als Vorauswahl solange noch nicht gesucht wurde (Fehlerbericht "Automatische
  /// Bonzuordnung": die App soll nicht erst tippen lassen, wenn sie schon Kandidaten kennt).
  List<Product> _unlinked = const [];
  var _linking = false;

  late final _offPackaging = widget.suggestion?.quantityText == null ? null : parsePackagingFromText(widget.suggestion!.quantityText!);

  Packaging _initialPackaging() {
    final existing = widget.existing;
    if (existing != null) return packagingOf(existing, existing.baseUnit);
    final off = _offPackaging;
    return off == null ? const Packaging(baseUnit: 'piece') : Packaging(baseUnit: off.unit, rawPackSize: off.amount, rawPiecesPerPack: off.pieces);
  }

  /// Der Inhalt, den das Formular zeigt: je Stueck bei einer Mehrfachpackung, sonst je Packung.
  double? get _initialContent => _knownPackaging.isMultipack ? _knownPackaging.contentPerPiece : (_knownPackaging.baseUnit == 'piece' ? null : _knownPackaging.contentPerPack);

  QuantityOption _initialAmountUnit() {
    final best = ListAmountUnit.bestFor(_initialContent ?? 0, _knownPackaging.baseUnit == 'piece' ? 'kg' : _knownPackaging.baseUnit);
    return _amountUnits.firstWhere((o) => o.label == best.label);
  }

  String _initialAmount() {
    final content = _initialContent;
    return content == null ? '' : formatListNumberExact(content / _amountUnit.toBase);
  }

  /// In Worten, was eingegeben ist. So faellt auf, wenn "65" als Kilo gemeint waere.
  String? get _packagingPreview {
    final r = resolvePackaging(kind: _kind, looseUnit: _looseUnit, count: _pieceCount.text, amount: _packSize.text, amountUnit: _amountUnit, label: _pieceLabel.text);
    if (r.error != null) return null;
    final p = Packaging(baseUnit: r.baseUnit, rawPackSize: r.packSize, rawPiecesPerPack: r.piecesPerPack, pieceLabel: r.pieceLabel);
    return switch (_kind) {
      PackagingKind.multipack => 'Eine Packung: ${p.piecesPerPack} ${p.pieceName} zu je ${formatListAmount(p.contentPerPiece!, p.baseUnit)}, zusammen ${formatListAmount(p.contentPerPack!, p.baseUnit)}',
      PackagingKind.countPack => 'Eine Packung: ${p.packDescription}',
      PackagingKind.contentPack => 'Eine Packung: ${p.packDescription}',
      PackagingKind.loose => 'Gezählt wird in ${r.baseUnit == 'l' ? 'Litern' : 'Kilogramm'}',
      PackagingKind.single => 'Gezählt wird in Stück',
    };
  }

  @override
  void initState() {
    super.initState();
    if (widget.ean != null && widget.existing == null) {
      // Bei einem OFF-Vorschlag gleich danach suchen, statt den Nutzer tippen zu lassen (Fehlerbericht
      // "Automatische Bonzuordnung", 2026-09-28).
      final suggestedName = widget.suggestion?.name;
      if (suggestedName != null) {
        _search.text = suggestedName;
        WidgetsBinding.instance.addPostFrameCallback((_) => _searchExisting(suggestedName));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final recent = await ref.read(productRepositoryProvider).recentUnlinked();
        if (mounted) setState(() => _unlinked = recent);
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _packSize.dispose();
    _pieceCount.dispose();
    _pieceLabel.dispose();
    _openedDays.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _removeAlias(ProductAlias alias) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zuordnung lösen?'),
        content: Text('„${alias.aliasText}“ wird beim nächsten Bon nicht mehr automatisch diesem Produkt zugeordnet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lösen')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(productRepositoryProvider).removeAlias(alias.id);
    }
  }

  Future<void> _searchExisting(String query) async {
    final results = query.trim().isEmpty ? const <Product>[] : await ref.read(productRepositoryProvider).search(query);
    if (mounted) setState(() => _matches = results);
  }

  /// Verknuepft den gescannten Barcode mit einem bereits vorhandenen Produkt, statt ein zweites anzulegen.
  /// Wichtig, wenn ein Bon-Vorschlag (Doku 06 §2) schon ein Produkt mit diesem Namen erzeugt hat, das OFF
  /// aber unter einem anderen Namen fuehrt: die Bon-Suche findet das Produkt, die OFF-Suche nicht.
  Future<void> _linkExisting(Product product) async {
    setState(() => _linking = true);
    try {
      await ref.read(productRepositoryProvider).linkBarcode(widget.ean!, product.id);
      if (mounted) context.pop(product);
    } catch (e) {
      if (mounted) {
        setState(() {
          _linking = false;
          _error = 'Verknüpfen nicht möglich: $e';
        });
      }
    }
  }

  void _initCategory(List<Category> categories) {
    if (_categoryInitialized) return;
    _categoryInitialized = true;
    if (widget.existing != null) {
      _categoryId = widget.existing!.categoryId;
      return;
    }
    final suggestion = widget.suggestion;
    if (suggestion != null) {
      _categoryId = suggestCategoryId(suggestion, {for (final c in categories) c.name: c.id});
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Bitte einen Namen eingeben.');
      return;
    }
    final packaging = resolvePackaging(kind: _kind, looseUnit: _looseUnit, count: _pieceCount.text, amount: _packSize.text, amountUnit: _amountUnit, label: _pieceLabel.text);
    if (packaging.error != null) {
      setState(() => _error = packaging.error);
      return;
    }
    final openedDays = int.tryParse(_openedDays.text.trim());
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(productRepositoryProvider);
      final Product product;
      if (widget.existing != null) {
        final updated = widget.existing!.copyWith(
          name: name,
          brand: Value(_brand.text.trim().isEmpty ? null : _brand.text.trim()),
          categoryId: Value(_categoryId),
          baseUnit: packaging.baseUnit,
          packSize: Value(packaging.packSize),
          piecesPerPack: Value(packaging.piecesPerPack),
          pieceLabel: Value(packaging.pieceLabel),
          unitWeightG: Value(packaging.pieceWeightG ?? widget.existing!.unitWeightG),
          defaultLocation: _location,
          defaultDateKind: _dateKind,
          openedShelfLifeDays: Value(openedDays),
          restock: _restock,
        );
        await repo.update(updated);
        // Der Bestand folgt, wenn sich die Einheit geaendert hat oder der Inhalt jetzt erst bekannt ist
        await ref.read(inventoryRepositoryProvider).normalizeStock(updated);
        product = updated;
      } else {
        product = await repo.create(
          name: name,
          brand: _brand.text.trim(),
          categoryId: _categoryId,
          baseUnit: packaging.baseUnit,
          packSize: packaging.packSize,
          piecesPerPack: packaging.piecesPerPack,
          pieceLabel: packaging.pieceLabel,
          defaultLocation: _location,
          defaultDateKind: _dateKind,
          openedShelfLifeDays: openedDays,
          restock: _restock,
          offCode: null,
          nutrientsPer100: widget.suggestion?.nutrientsPer100,
          nutrientsBasis: widget.suggestion?.nutrientsBasis,
          nutrientsSource: widget.suggestion?.nutrientsPer100 == null ? null : 'off',
          unitWeightG: packaging.pieceWeightG ?? (widget.suggestion?.quantityText == null ? null : parseUnitWeightGrams(widget.suggestion!.quantityText!)),
          ean: widget.ean,
        );
      }
      if (mounted) context.pop(product);
    } catch (e) {
      if (mounted) setState(() => _error = 'Speichern nicht möglich: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(categoriesStreamProvider).value ?? const <Category>[]).where((c) => c.deletedAt == null).toList();
    _initCategory(categories);
    final editing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Produkt bearbeiten' : 'Neues Produkt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.suggestion != null)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Vorschlag von Open Food Facts. Bitte prüfen und bei Bedarf anpassen.')),
                ]),
              ),
            ),
          if (widget.ean != null && widget.existing == null) ...[
            Text('Gibt es diesen Artikel schon in deinem Inventar?', key: const Key('existing-product-hint'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Ein Bon kann ein Produkt schon angelegt haben, bevor du es gescannt hast. Dann hier verknüpfen, statt neu anzulegen.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('product-search'),
              controller: _search,
              decoration: const InputDecoration(labelText: 'Vorhandenes Produkt suchen', prefixIcon: Icon(Icons.search)),
              onChanged: _searchExisting,
            ),
            for (final m in _matches)
              Card(
                child: ListTile(
                  key: Key('match-${m.id}'),
                  title: Text(m.name),
                  subtitle: m.brand == null ? null : Text(m.brand!),
                  trailing: _linking ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link),
                  onTap: _linking ? null : () => _linkExisting(m),
                ),
              ),
            if (_search.text.trim().isEmpty && _unlinked.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Zuletzt aus Bons, noch ohne Barcode', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              for (final m in _unlinked)
                Card(
                  child: ListTile(
                    key: Key('unlinked-${m.id}'),
                    title: Text(m.name),
                    subtitle: m.brand == null ? null : Text(m.brand!),
                    trailing: _linking ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link),
                    onTap: _linking ? null : () => _linkExisting(m),
                  ),
                ),
            ],
            const Divider(height: 32),
            Text('Oder neu anlegen', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
          ],
          if (editing) ...[
            _AliasSection(productId: widget.existing!.id, onRemove: _removeAlias),
            const SizedBox(height: 16),
          ],
          TextField(key: const Key('product-name'), controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(key: const Key('product-brand'), controller: _brand, decoration: const InputDecoration(labelText: 'Marke (optional)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: const Key('product-category'),
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Kategorie'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Keine')),
              for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PackagingKind>(
            key: const Key('product-kind'),
            isExpanded: true,
            initialValue: _kind,
            decoration: InputDecoration(labelText: 'Wie wird es gekauft?', helperText: _kind.example),
            items: [for (final k in PackagingKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: 12),
          if (_kind == PackagingKind.loose) ...[
            SegmentedButton<String>(
              key: const Key('product-unit'),
              segments: const [ButtonSegment(value: 'kg', label: Text('Gewicht (kg)')), ButtonSegment(value: 'l', label: Text('Volumen (l)'))],
              selected: {_looseUnit},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _looseUnit = s.first),
            ),
            const SizedBox(height: 12),
          ],
          if (_kind == PackagingKind.countPack || _kind == PackagingKind.multipack) ...[
            TextField(
              key: const Key('product-piece-count'),
              controller: _pieceCount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stück je Packung'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
          ],
          if (_kind == PackagingKind.contentPack || _kind == PackagingKind.multipack) ...[
            Row(children: [
              Expanded(
                flex: 2,
                child: TextField(
                  key: const Key('product-pack-size'),
                  controller: _packSize,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: _kind == PackagingKind.multipack ? 'Inhalt je Stück' : 'Inhalt der Packung'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<QuantityOption>(
                  key: const Key('product-amount-unit'),
                  initialValue: _amountUnit,
                  decoration: const InputDecoration(labelText: 'Einheit'),
                  items: [for (final o in _amountUnits) DropdownMenuItem(value: o, child: Text(o.label))],
                  onChanged: (v) => setState(() => _amountUnit = v ?? _amountUnit),
                ),
              ),
            ]),
            const SizedBox(height: 12),
          ],
          if (_kind == PackagingKind.countPack || _kind == PackagingKind.multipack) ...[
            TextField(
              key: const Key('product-piece-label'),
              controller: _pieceLabel,
              maxLength: 30,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name der Stücke (optional)', hintText: 'z. B. Fläschchen, Becher, Riegel', counterText: ''),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
          ],
          if (_packagingPreview case final text?) ...[
            Text(text, key: const Key('product-packaging-preview'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            key: const Key('product-location'),
            initialValue: _location,
            decoration: const InputDecoration(labelText: 'Üblicher Lagerort'),
            items: [for (final l in _locations) DropdownMenuItem(value: l.$1, child: Text(l.$2))],
            onChanged: (v) => setState(() => _location = v ?? _location),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('product-date-kind'),
            initialValue: _dateKind,
            decoration: const InputDecoration(labelText: 'Art des Datums'),
            items: [for (final d in _dateKinds) DropdownMenuItem(value: d.$1, child: Text(d.$2))],
            onChanged: (v) => setState(() => _dateKind = v ?? _dateKind),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('product-opened-days'),
            controller: _openedDays,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Haltbarkeit nach dem Öffnen (Tage, optional)'),
          ),
          SwitchListTile(
            key: const Key('product-restock'),
            title: const Text('Nachkaufprodukt'),
            subtitle: const Text('Vorschlag auf der Einkaufsliste, wenn der Bestand ausgeht'),
            value: _restock,
            onChanged: (v) => setState(() => _restock = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('product-save'),
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Speichern'),
          ),
        ],
      ),
    );
  }
}

/// Gelernte Bon-Text-Zuordnungen (ADR-010) dieses Produkts, mit der Moeglichkeit, eine falsch gelernte
/// wieder zu loesen (Fehlerbericht "Alias ändern", 2026-09-27).
class _AliasSection extends ConsumerWidget {
  const _AliasSection({required this.productId, required this.onRemove});
  final String productId;
  final Future<void> Function(ProductAlias alias) onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aliases = ref.watch(productAliasesStreamProvider(productId)).value ?? const <ProductAlias>[];
    if (aliases.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Gelernte Bon-Zuordnungen', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Diese Bon-Texte werden automatisch diesem Produkt zugeordnet.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          for (final a in aliases)
            ListTile(
              key: Key('alias-${a.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(a.aliasText),
              trailing: IconButton(
                key: Key('alias-remove-${a.id}'),
                icon: const Icon(Icons.link_off),
                tooltip: 'Zuordnung lösen',
                onPressed: () => onRemove(a),
              ),
            ),
        ]),
      ),
    );
  }
}
