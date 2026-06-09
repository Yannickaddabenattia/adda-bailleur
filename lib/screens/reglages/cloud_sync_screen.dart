import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/cloud/cloud_sync_service.dart';
import '../../services/master_key_service.dart';

/// Écran de configuration de la synchronisation cloud : mot de passe maître,
/// choix du service, sauvegarde et restauration.
class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _changing = false;
  bool _busy = false;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _savePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    await context.read<MasterKeyService>().setupPassword(_pwCtrl.text);
    if (!mounted) return;
    _pwCtrl.clear();
    _confirmCtrl.clear();
    setState(() {
      _busy = false;
      _changing = false;
    });
    _snack('Mot de passe maître enregistré.');
  }

  Future<void> _selectProvider(CloudProvider p) async {
    setState(() => _busy = true);
    final r = await context.read<CloudSyncService>().selectProvider(p);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(r.ok ? '${p.displayName} connecté.' : (r.message ?? 'Échec'));
  }

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    final r = await context.read<CloudSyncService>().backupNow();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(r.ok ? 'Sauvegarde envoyée au cloud.' : (r.message ?? 'Échec'));
  }

  Future<void> _restore() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurer depuis le cloud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Récupère la dernière sauvegarde et fusionne les données. '
              'Saisissez votre mot de passe maître.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restaurer')),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final r = await context.read<CloudSyncService>().restoreLatest(ctrl.text);
    ctrl.dispose();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(r.ok ? 'Données restaurées et fusionnées.' : (r.message ?? 'Échec'));
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    await context.read<CloudSyncService>().disconnect();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack('Service cloud déconnecté.');
  }

  @override
  Widget build(BuildContext context) {
    final masterKey = context.watch<MasterKeyService>();
    final cloud = context.watch<CloudSyncService>();
    final hasPassword = masterKey.isConfigured;

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation cloud')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _intro(context),
            const SizedBox(height: 24),

            // ─── 1. Mot de passe maître ───
            const _SectionTitle('1. Mot de passe maître'),
            const SizedBox(height: 8),
            if (hasPassword && !_changing)
              _configuredPasswordCard(context)
            else
              _passwordForm(),

            const SizedBox(height: 28),

            // ─── 2. Service cloud ───
            const _SectionTitle('2. Service cloud'),
            const SizedBox(height: 8),
            for (final p in CloudProvider.values) _providerTile(context, cloud, p),

            // ─── 3. Actions ───
            if (cloud.hasProvider && hasPassword) ...[
              const SizedBox(height: 28),
              const _SectionTitle('3. Sauvegarde & restauration'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _backupNow,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Sauvegarder maintenant'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restore,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Restaurer'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _disconnect,
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.link_off),
                    label: const Text('Déconnecter'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _intro(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, color: AppColors.primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Vos données sont chiffrées en AES-256 sur l\'appareil avant '
                'tout envoi. Seul votre mot de passe les déchiffre — aucun '
                'serveur ADDA n\'y a accès.',
                style: TextStyle(
                    fontSize: 13, color: context.textSecondaryColor, height: 1.4),
              ),
            ),
          ],
        ),
      );

  Widget _passwordForm() => Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _pwCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Mot de passe maître',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) =>
                  (v == null || v.length < 8) ? 'Minimum 8 caractères' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirmation',
                prefixIcon: Icon(Icons.key_outlined),
              ),
              validator: (v) => v != _pwCtrl.text ? 'Ne correspond pas' : null,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Notez-le précieusement : sans lui, vos sauvegardes sont '
                      'DÉFINITIVEMENT illisibles — personne ne peut les récupérer.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.red.shade900, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _savePassword,
              child: Text(_busy ? '…' : 'Enregistrer le mot de passe'),
            ),
          ],
        ),
      );

  Widget _configuredPasswordCard(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Mot de passe maître défini.',
                  style: TextStyle(fontSize: 13)),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _changing = true),
              child: const Text('Changer'),
            ),
          ],
        ),
      );

  Widget _providerTile(
      BuildContext context, CloudSyncService cloud, CloudProvider p) {
    final selected = cloud.activeProvider == p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: _busy ? null : () => _selectProvider(p),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.primary : context.dividerColor,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : context.textSecondaryColor,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.displayName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(
                      p.isAvailable
                          ? 'Dossier synchronisé par le service (recommandé)'
                          : 'Connexion directe à configurer (OAuth)',
                      style: TextStyle(
                          fontSize: 11.5, color: context.textSecondaryColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  const _SectionTitle(this.label);

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textSecondary,
        ),
      );
}
