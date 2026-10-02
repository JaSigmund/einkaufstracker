import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/local/database.dart';

/// Foto einer Mahlzeit als Bild: lokale Kopie, sonst vom Server (siehe `MealPhotoService.bytes`). Solange das Foto
/// laedt oder nicht erreichbar ist (andere Geraete, kein Netz), steht [placeholder] da.
class MealPhoto extends ConsumerStatefulWidget {
  const MealPhoto({super.key, required this.meal, required this.placeholder, this.size, this.fit = BoxFit.cover});

  final Meal meal;
  final Widget placeholder;

  /// Kantenlaenge in logischen Pixeln (quadratisch), `null` = Platz des Elternelements.
  final double? size;
  final BoxFit fit;

  @override
  ConsumerState<MealPhoto> createState() => _MealPhotoState();
}

class _MealPhotoState extends ConsumerState<MealPhoto> {
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _load();
  }

  @override
  void didUpdateWidget(MealPhoto old) {
    super.didUpdateWidget(old);
    if (old.meal.id != widget.meal.id || old.meal.photoPath != widget.meal.photoPath) _bytes = _load();
  }

  Future<Uint8List?> _load() => ref.read(mealPhotoServiceProvider).bytes(widget.meal);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return SizedBox(width: widget.size, height: widget.size, child: Center(child: widget.placeholder));
        // cacheWidth: grosse Fotos nicht in voller Aufloesung dekodieren, wenn nur eine Vorschau gezeigt wird
        return Image.memory(
          data,
          key: const Key('meal-photo-image'),
          width: widget.size,
          height: widget.size,
          fit: widget.fit,
          cacheWidth: widget.size == null ? null : (widget.size! * 2).round(),
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => widget.placeholder,
        );
      },
    );
  }
}
