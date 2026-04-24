import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/backup/backup_codec.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backup_service.dart';
import '../../widgets/primary_button.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _service = BackupService();
  bool _busy = false;

  Future<void> _export() async {
    final passphrase = await _askPassphrase(confirm: true);
    if (passphrase == null) return;
    setState(() => _busy = true);
    try {
      final file = await _service.exportEncrypted(passphrase: passphrase);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: 'Sauvegarde Adda Location',
        text:
            'Sauvegarde chiffrée Adda Location. Conservez ce fichier et '
            'votre passphrase en lieu sûr.',
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Export impossible: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['adlb'],
    );
    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    final bytes = await file.readAsBytes();

    if (!mounted) return;
    final passphrase = await _askPassphrase(confirm: false);
    if (passphrase == null) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer la restauration'),
        content: const Text(
          'Toutes les données actuelles (logements, locataires, EDL, '
          'quittances) seront remplacées par celles de la sauvegarde. '
          'Continuer ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final report = await _service.importEncrypted(
        bytes: bytes,
        passphrase: passphrase,
      );
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restauration réussie'),
          content: Text(
            'Profil restauré : ${report.profileRestored ? 'oui' : 'non (conservé)'}\n'
            'Logements : ${report.logements}\n'
            'Locataires : ${report.locataires}\n'
            'États des lieux : ${report.etatsDesLieux}\n'
            'Quittances : ${report.quittances}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on BackupDecryptionException {
      if (!mounted) return;
      _showError('Passphrase incorrecte.');
    } on BackupFormatException catch (e) {
      if (!mounted) return;
      _showError('Fichier invalide : ${e.message}');
    } catch (e) {
      if (!mounted) return;
      _showError('Restauration impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassphrase({required bool confirm}) async {
    final ctrl1 = TextEditingController();
    final ctrl2 = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(confirm ? 'Choisir une passphrase' : 'Saisir la passphrase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (confirm)
                const Text(
                  'Cette passphrase chiffre votre sauvegarde. Notez-la en '
                  'lieu sûr : elle ne peut pas être récupérée.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              if (confirm) const SizedBox(height: 12),
              TextField(
                controller: ctrl1,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Passphrase',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              if (confirm) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl2,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirmer',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                final a = ctrl1.text;
                final b = ctrl2.text;
                if (a.length < 8) {
                  setS(() =>
                      error = 'Minimum 8 caractères.');
                  return;
                }
                if (confirm && a != b) {
                  setS(() => error = 'Les deux saisies diffèrent.');
                  return;
                }
                Navigator.of(ctx).pop(a);
              },
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde & restauration')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              _InfoBox(),
              const SizedBox(height: 20),
              _ActionCard(
                icon: Icons.backup_outlined,
                title: 'Exporter mes données',
                description:
                    'Génère un fichier chiffré .adlb contenant toutes vos '
                    'données (logements, locataires, EDL, quittances). '
                    'Protégé par votre passphrase.',
                button: 'Exporter',
                onPressed: _busy ? null : _export,
                loading: _busy,
              ),
              const SizedBox(height: 16),
              _ActionCard(
                icon: Icons.settings_backup_restore_outlined,
                title: 'Restaurer une sauvegarde',
                description:
                    'Remplace toutes vos données actuelles par celles du '
                    'fichier .adlb. La passphrase est obligatoire.',
                button: 'Restaurer',
                onPressed: _busy ? null : _import,
                loading: _busy,
                destructive: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Vos sauvegardes sont chiffrées localement avec AES-256-GCM '
              '(clé dérivée par PBKDF2-SHA256, 200 000 itérations). '
              'Sans votre passphrase, aucune donnée ne peut être récupérée.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String button;
  final VoidCallback? onPressed;
  final bool loading;
  final bool destructive;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.button,
    required this.onPressed,
    this.loading = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (destructive ? AppColors.error : AppColors.primary)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: destructive ? AppColors.error : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: button,
            icon: icon,
            loading: loading,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}
