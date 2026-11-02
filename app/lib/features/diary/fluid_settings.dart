import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../domain/nutrition/fluid_intake.dart';

/// Ziel und Erinnerung fuer die Trinkmenge (ADR-049), erreichbar von "Schnell eintragen" und den Richtwerten.
Future<void> showFluidSettings(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _FluidSettingsSheet(),
    );

class _FluidSettingsSheet extends ConsumerStatefulWidget {
  const _FluidSettingsSheet();

  @override
  ConsumerState<_FluidSettingsSheet> createState() => _FluidSettingsSheetState();
}

class _FluidSettingsSheetState extends ConsumerState<_FluidSettingsSheet> {
  final _target = TextEditingController();
  var _settings = const FluidSettings();
  var _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(householdPrefsRepositoryProvider).load().then((prefs) {
      if (!mounted) return;
      setState(() {
        _settings = FluidSettings.fromPrefs(prefs);
        _target.text = formatQuantity(_settings.targetMl / 1000);
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _settings.hour, minute: _settings.minute));
    if (time == null || !mounted) return;
    setState(() => _settings = FluidSettings(targetMl: _settings.targetMl, reminderOn: _settings.reminderOn, hour: time.hour, minute: time.minute));
  }

  Future<void> _save() async {
    final liters = double.tryParse(_target.text.replaceAll(',', '.').trim());
    if (liters == null || liters <= 0 || liters > 10) {
      setState(() => _error = 'Bitte eine Menge zwischen 0 und 10 Litern eingeben.');
      return;
    }
    final repo = ref.read(householdPrefsRepositoryProvider);
    await repo.set(fluidTargetPref, liters * 1000);
    await repo.set(fluidReminderOnPref, _settings.reminderOn);
    await repo.set(fluidReminderTimePref, _settings.timeText);
    await rescheduleFluidReminders(ref);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: !_loaded
              ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Trinkmenge', style: t.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('fluid-target'),
                    controller: _target,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Ziel pro Tag',
                      suffixText: 'l',
                      helperText: 'Vorbelegt sind rund 1,5 l, der Richtwert der DGE für Erwachsene. Dein Bedarf kann davon abweichen.',
                      helperMaxLines: 2,
                      errorText: _error,
                    ),
                  ),
                  if (kIsWeb)
                    Padding(padding: const EdgeInsets.only(top: 12), child: Text('Im Browser gibt es keine Erinnerung.', style: t.textTheme.bodySmall))
                  else ...[
                    SwitchListTile(
                      key: const Key('fluid-reminder-on'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Erinnerung'),
                      subtitle: const Text('Entfällt für den Tag, sobald du die Hälfte des Ziels erreicht hast'),
                      value: _settings.reminderOn,
                      onChanged: (v) => setState(() => _settings = FluidSettings(targetMl: _settings.targetMl, reminderOn: v, hour: _settings.hour, minute: _settings.minute)),
                    ),
                    if (_settings.reminderOn)
                      ListTile(
                        key: const Key('fluid-reminder-time'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule),
                        title: Text('Um ${_settings.timeText}'),
                        trailing: const Icon(Icons.edit_outlined, size: 18),
                        onTap: _pickTime,
                      ),
                  ],
                  const SizedBox(height: 8),
                  FilledButton(key: const Key('fluid-save'), onPressed: _save, child: const Text('Speichern')),
                ]),
        ),
      ),
    );
  }
}
