import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/storage/secure_folder.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auto_backup_service.dart';

/// Écran de configuration / suivi de la sauvegarde automatique cloud.
class AutoBackupSettingsScreen extends StatefulWidget {
  const AutoBackupSettingsScreen({super.key});

  @override
  State<AutoBackupSettingsScreen> createState() =>
      _AutoBackupSettingsScreenState();
}

class _AutoBackupSettingsScreenState extends State<AutoBackupSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passphraseCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _pickedFolder;
  String? _pickedBookmark;
  bool _obscure = true;
  bool _busy = false;
  String? _testMessage;
  // L'app peut se croire « activée » (drapeau Hive) mais avoir perdu la
  // passphrase du trousseau : on réaffiche alors le champ pour la ressaisir.
  bool _passphraseMissing = false;

  @override
  void initState() {
    super.initState();
    final svc = context.read<AutoBackupService>();
    _pickedFolder = svc.folderPath;
    _pickedBookmark = svc.folderBookmark;
    if (svc.isEnabled) {
      svc.hasPassphrase().then((has) {
        if (mounted) setState(() => _passphraseMissing = !has);
      });
    }
  }

  @override
  void dispose() {
    _passphraseCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    // Sur iOS/macOS, on passe par le sélecteur natif qui crée un bookmark
    // security-scoped (accès persistant au dossier après relance). Ailleurs,
    // sélection classique par chemin.
    if (SecureFolder.isSupported) {
      final picked = await SecureFolder.pickDirectory();
      if (picked == null) return;
      setState(() {
        _pickedFolder = picked.path;
        _pickedBookmark = picked.bookmark;
      });
    } else {
      final result = await getDirectoryPath();
      if (result == null) return;
      setState(() {
        _pickedFolder = result;
        _pickedBookmark = null;
      });
    }
  }

  Future<void> _saveConfig() async {
    if (_pickedFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez d\'abord un dossier.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AutoBackupService>().configure(
            folderPath: _pickedFolder!,
            passphrase: _passphraseCtrl.text,
            bookmark: _pickedBookmark,
          );
      if (!mounted) return;
      _passphraseCtrl.clear();
      _confirmCtrl.clear();
      _passphraseMissing = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sauvegarde automatique activée.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupNow() async {
    setState(() {
      _busy = true;
      _testMessage = null;
    });
    final r = await context.read<AutoBackupService>().runIfNeeded(
          trigger: AutoBackupTrigger.manual,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.didBackup) {
        _testMessage = 'Sauvegarde écrite : ${r.filePath?.split(Platform.pathSeparator).last}';
      } else if (r.errorMessage != null) {
        _testMessage = 'Erreur : ${r.errorMessage}';
      } else {
        _testMessage = r.reason ?? 'Rien à faire.';
      }
    });
  }

  Future<void> _disable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Désactiver l\'auto-backup ?'),
        content: const Text(
          'L\'app cessera de sauvegarder automatiquement. Les fichiers '
          'déjà écrits dans le dossier ne seront pas supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Désactiver'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    await context.read<AutoBackupService>().disable();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openFolder() async {
    final p = _pickedFolder;
    if (p == null) return;
    final uri = Uri.file(p);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<AutoBackupService>();
    final isConfigured = svc.isEnabled;
    final last = svc.lastBackupAt;
    final fmt = DateFormat('dd MMM yyyy à HH:mm', 'fr_FR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sauvegarde automatique'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_sync_outlined,
                      color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'L\'application sauvegarde automatiquement vos données '
                      'dans un dossier que vous choisissez (idéalement dans '
                      'votre iCloud Drive, OneDrive, Google Drive ou pCloud).\n'
                      'Le fichier est chiffré : seul votre mot de passe '
                      'permet de le relire.',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondaryColor,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── 1. Dossier ────────────────────────────────────────────
            const _SectionTitle('1. Dossier de destination'),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickFolder,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: context.dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_open,
                        color: AppColors.primary, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _pickedFolder ?? 'Choisir un dossier…',
                        style: TextStyle(
                          fontSize: 13,
                          color: _pickedFolder == null
                              ? context.textSecondaryColor
                              : null,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: context.textSecondaryColor),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Astuce : créez un dossier "ADDA Bailleur" dans votre iCloud Drive '
              'ou votre OneDrive depuis le Finder, puis sélectionnez-le ici. '
              'L\'application y écrira automatiquement les fichiers .adls — '
              'la synchronisation cloud est gérée par votre OS.',
              style: TextStyle(
                fontSize: 11.5,
                color: context.textSecondaryColor,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 28),

            // ─── 2. Passphrase ─────────────────────────────────────────
            const _SectionTitle('2. Mot de passe de chiffrement'),
            const SizedBox(height: 8),
            if (!isConfigured || _passphraseMissing) ...[
              if (_passphraseMissing) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.orange.shade800, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Le mot de passe n\'a pas pu être retrouvé dans le '
                          'trousseau. Ressaisissez-le (le même qu\'à l\'origine) '
                          'pour réactiver la sauvegarde.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _passphraseCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.key_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 8) {
                          return 'Minimum 8 caractères';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: _obscure,
                      decoration: const InputDecoration(
                        labelText: 'Confirmation',
                        prefixIcon: Icon(Icons.key_outlined),
                      ),
                      validator: (v) {
                        if (v != _passphraseCtrl.text) {
                          return 'Ne correspond pas';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
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
                        'Notez votre mot de passe dans un lieu sûr. '
                        'Si vous l\'oubliez, vos sauvegardes seront '
                        'DÉFINITIVEMENT illisibles — personne ne peut les '
                        'récupérer, pas même nous.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade900,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _saveConfig,
                icon: const Icon(Icons.cloud_done_outlined),
                label: Text(_busy
                    ? 'Activation…'
                    : (_passphraseMissing
                        ? 'Enregistrer le mot de passe'
                        : 'Activer la sauvegarde automatique')),
              ),
            ] else ...[
              Container(
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
                      child: Text(
                        'Mot de passe enregistré dans le trousseau de votre appareil.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ─── 3. État et actions ────────────────────────────────────
            if (isConfigured) ...[
              const SizedBox(height: 28),
              const _SectionTitle('3. État et actions'),
              const SizedBox(height: 8),
              _StatusBadge(state: svc.state, lastError: svc.lastError),
              const SizedBox(height: 10),
              if (last != null)
                Text(
                  'Dernière sauvegarde : ${fmt.format(last.toLocal())}',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondaryColor,
                  ),
                )
              else
                Text(
                  'Aucune sauvegarde encore réalisée.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondaryColor,
                  ),
                ),
              if (svc.lastBackupFilePath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Fichier : ${svc.lastBackupFilePath!.split(Platform.pathSeparator).last}',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ),
              if (_testMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.dividerColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _testMessage!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _backupNow,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Sauvegarder maintenant'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _openFolder,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Ouvrir le dossier'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _disable,
                    icon: const Icon(Icons.power_settings_new),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    label: const Text('Désactiver'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  const _SectionTitle(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final AutoBackupState state;
  final String? lastError;
  const _StatusBadge({required this.state, this.lastError});

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    IconData icon;
    switch (state) {
      case AutoBackupState.disabled:
        label = 'Désactivée';
        color = Colors.grey;
        icon = Icons.cloud_off_outlined;
        break;
      case AutoBackupState.upToDate:
        label = 'À jour';
        color = Colors.green;
        icon = Icons.cloud_done_outlined;
        break;
      case AutoBackupState.dirty:
        label = 'Modifications en attente';
        color = Colors.amber.shade700;
        icon = Icons.cloud_queue_outlined;
        break;
      case AutoBackupState.inProgress:
        label = 'Sauvegarde en cours…';
        color = AppColors.primary;
        icon = Icons.cloud_upload_outlined;
        break;
      case AutoBackupState.error:
        label = lastError ?? 'Erreur';
        color = Colors.red;
        icon = Icons.cloud_off;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
