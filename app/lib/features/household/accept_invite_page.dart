import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/household/household_invites.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/household/invite_code.dart';

/// Einladung annehmen (Phase 6, ADR-017 Option A): ohne Anmeldung erreichbar, denn wer eingeladen wurde, hat noch kein
/// Konto. Code, die eingeladene E-Mail-Adresse und ein neues Passwort; danach wird gleich angemeldet.
class AcceptInvitePage extends ConsumerStatefulWidget {
  const AcceptInvitePage({super.key});

  @override
  ConsumerState<AcceptInvitePage> createState() => _AcceptInvitePageState();
}

class _AcceptInvitePageState extends ConsumerState<AcceptInvitePage> {
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _email, _password, _repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final code = normalizeInviteCode(_code.text);
    final email = normalizeEmail(_email.text);
    if (code == null) return setState(() => _error = 'Der Code hat 12 Zeichen, z.B. ABCD-EFGH-JKMN.');
    if (email == null) return setState(() => _error = 'Bitte die E-Mail-Adresse eingeben, an die die Einladung ging.');
    final problem = passwordProblem(_password.text);
    if (problem != null) return setState(() => _error = problem);
    if (_password.text != _repeat.text) return setState(() => _error = 'Die beiden Passwörter sind nicht gleich.');

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(acceptInviteApiProvider).accept(code: code, email: email, password: _password.text);
      // Konto existiert jetzt: gleich anmelden, die Weiterleitung erledigt der Router, sobald die Sitzung da ist.
      await ref.read(authRepositoryProvider).signIn(email, _password.text);
    } on InviteFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on SignInFailure {
      // Das Konto ist angelegt, nur die Anmeldung hat nicht geklappt (z.B. Netz weg): zur normalen Anmeldung schicken.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Du bist dem Haushalt beigetreten. Bitte melde dich jetzt an.')));
        context.go('/login');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Einladung annehmen')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  'Du wurdest in einen Haushalt eingeladen? Gib den Code ein, den du bekommen hast, und lege dein Passwort fest.',
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('accept-code'),
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Einladungscode', hintText: 'ABCD-EFGH-JKMN'),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('accept-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'E-Mail-Adresse', helperText: 'genau die, an die die Einladung ging'),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('accept-password'),
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Passwort',
                    helperText: 'mindestens $minPasswordChars Zeichen',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Passwort anzeigen' : 'Passwort verbergen',
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('accept-repeat'),
                  controller: _repeat,
                  obscureText: _obscure,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Passwort wiederholen'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, key: const Key('accept-error'), style: TextStyle(color: t.colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('accept-submit'),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Beitreten'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
