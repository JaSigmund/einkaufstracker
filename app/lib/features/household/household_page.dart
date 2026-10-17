import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/clock.dart';
import '../../data/household/household_invites.dart';
import '../../domain/household/invite_code.dart';

/// Haushalt: Mitglieder zaehlen, Personen einladen, offene Einladungen verwalten (Phase 6, ADR-017 Option A).
///
/// Einladungen gehen nicht per E-Mail raus: die App zeigt den Code, den man selbst per Nachrichten-App weitergibt. Die
/// eingeladene Person gibt Code, die eingeladene Adresse und ein Passwort ein (Seite "Einladung annehmen").
class HouseholdPage extends ConsumerWidget {
  const HouseholdPage({super.key, this.now});

  /// Aktueller Zeitpunkt (UTC), austauschbar fuer Tests.
  final DateTime? now;

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final email = await showDialog<String>(context: context, builder: (_) => const _InviteDialog());
    if (email == null || !context.mounted) return;
    try {
      final invite = await ref.read(householdInviteRepositoryProvider).create(email);
      ref.invalidate(householdInvitesProvider);
      if (context.mounted) await _showCode(context, ref, invite);
    } on InviteFailure catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showCode(BuildContext context, WidgetRef ref, HouseholdInvite invite) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Einladung bereit'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Gib diesen Code an ${invite.email} weiter:'),
            const SizedBox(height: 12),
            SelectableText(
              formatInviteCode(invite.token),
              key: const Key('invite-code'),
              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(letterSpacing: 2, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const SizedBox(height: 12),
            Text('Gültig bis ${_date(invite.expiresAt)}, einmal verwendbar. Die Person braucht außerdem genau diese E-Mail-Adresse.', style: Theme.of(ctx).textTheme.bodySmall),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
            TextButton(key: const Key('invite-copy'), onPressed: () => _copy(ctx, invite), child: const Text('Kopieren')),
            FilledButton(key: const Key('invite-share'), onPressed: () => _share(ref, invite), child: const Text('Teilen')),
          ],
        ),
      );

  Future<void> _copy(BuildContext context, HouseholdInvite invite) async {
    await Clipboard.setData(ClipboardData(text: inviteShareText(code: invite.token, validUntil: invite.expiresAt.toLocal())));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Einladungstext kopiert.')));
  }

  Future<void> _share(WidgetRef ref, HouseholdInvite invite) =>
      ref.read(shareTextProvider)(inviteShareText(code: invite.token, validUntil: invite.expiresAt.toLocal()));

  Future<void> _revoke(BuildContext context, WidgetRef ref, HouseholdInvite invite) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Einladung zurückziehen?'),
        content: Text('Der Code für ${invite.email} funktioniert danach nicht mehr.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(key: const Key('invite-revoke-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Zurückziehen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(householdInviteRepositoryProvider).revoke(invite.id);
      ref.invalidate(householdInvitesProvider);
    } on InviteFailure catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static String _date(DateTime utc) {
    final d = utc.toLocal();
    return '${d.day}.${d.month}.${d.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(householdInvitesProvider);
    final members = ref.watch(householdMemberCountProvider);
    final t = Theme.of(context);
    final current = now ?? appClock.now().toUtc();

    return Scaffold(
      appBar: AppBar(title: const Text('Haushalt')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.group_outlined),
          title: const Text('Mitglieder'),
          subtitle: Text(
            members.when(
              data: (n) => n == 1 ? 'Nur du' : '$n Personen',
              loading: () => '…',
              error: (_, _) => 'nicht verfügbar',
            ),
            key: const Key('household-members'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Alle Mitglieder sehen und bearbeiten dieselben Bons, dasselbe Inventar und dieselbe Einkaufsliste. '
          'Das Essenstagebuch gehört ebenfalls zum Haushalt.',
          style: t.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(key: const Key('household-invite'), onPressed: () => _invite(context, ref), icon: const Icon(Icons.person_add_alt_1), label: const Text('Person einladen')),
        const SizedBox(height: 24),
        Text('Offene Einladungen', style: t.textTheme.titleSmall),
        invites.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(e is InviteFailure ? e.message : 'Einladungen sind gerade nicht verfügbar.', key: const Key('household-invites-error')),
          ),
          data: (list) => list.isEmpty
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Keine offenen Einladungen.', key: Key('household-no-invites')))
              : Column(children: [
                  for (final i in list)
                    ListTile(
                      key: Key('invite-${i.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(i.isExpired(current) ? Icons.timer_off_outlined : Icons.mail_outline),
                      title: Text(i.email),
                      subtitle: Text(
                        i.isExpired(current)
                            ? 'Abgelaufen am ${_date(i.expiresAt)}'
                            : 'Code ${formatInviteCode(i.token)} · gültig bis ${_date(i.expiresAt)}',
                      ),
                      trailing: PopupMenuButton<String>(
                        key: Key('invite-menu-${i.id}'),
                        onSelected: (action) {
                          switch (action) {
                            case 'show':
                              _showCode(context, ref, i);
                            case 'revoke':
                              _revoke(context, ref, i);
                          }
                        },
                        itemBuilder: (_) => [
                          if (!i.isExpired(current)) const PopupMenuItem(value: 'show', child: Text('Code anzeigen und teilen')),
                          const PopupMenuItem(value: 'revoke', child: Text('Zurückziehen')),
                        ],
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog();

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _email = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final email = normalizeEmail(_email.text);
    if (email == null) return setState(() => _error = 'Bitte eine gültige E-Mail-Adresse eingeben.');
    Navigator.pop(context, email);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Person einladen'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Die Person bekommt von dir einen Code und legt damit ihr eigenes Konto an. Mit der E-Mail-Adresse meldet sie sich später an.'),
        const SizedBox(height: 12),
        TextField(
          key: const Key('invite-email'),
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: 'E-Mail-Adresse', errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(key: const Key('invite-create'), onPressed: _submit, child: const Text('Einladen')),
      ],
    );
  }
}
