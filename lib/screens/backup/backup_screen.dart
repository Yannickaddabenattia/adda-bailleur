import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import '../../core/backup/backup_codec.dart';
import '../../core/email_sender.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backup_service.dart';
import '../../widgets/primary_button.dart';
import '../account/delete_account_action.dart';
import 'auto_backup_settings_screen.dart';
import 'received_backups_screen.dart';

enum _ImportMode { merge, replace }

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

      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        const subject = 'Sauvegarde ADDA Bailleur';
        const body =
            'Sauvegarde chiffrée ADDA Bailleur en pièce jointe. '
            'Conservez ce fichier et votre passphrase en lieu sûr.';
        final opened = await _openMailClientWithAttachment(
          filePath: file.path,
          subject: subject,
          body: body,
        );
        if (!mounted) return;
        if (opened) {
          if (Platform.isLinux) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 8),
                content: Text(
                  'Mail ouvert. Glissez « ${file.path.split('/').last} » '
                  'depuis le dossier (déjà sélectionné) dans votre email.',
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Mail ouvert avec la sauvegarde en pièce jointe'),
              ),
            );
          }
        } else {
          final fileName = file.path.split(Platform.pathSeparator).last;
          final location = await fs.getSaveLocation(
            suggestedName: fileName,
            acceptedTypeGroups: const [
              fs.XTypeGroup(label: 'Sauvegarde Adda', extensions: ['zip']),
            ],
          );
          if (location != null) {
            await File(location.path)
                .writeAsBytes(await file.readAsBytes(), flush: true);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Sauvegarde enregistrée : ${location.path}'),
              ),
            );
          }
        }
      } else {
        // Mobile : composeur d'e-mail direct avec la sauvegarde en pièce
        // jointe (repli sur la feuille de partage si aucun client mail).
        await EmailSender.sendWithAttachment(
          path: file.path,
          subject: 'Sauvegarde ADDA Bailleur',
          body: 'Sauvegarde chiffrée ADDA Bailleur en pièce jointe. '
              'Conservez ce fichier et votre passphrase en lieu sûr.',
          mimeType: 'application/octet-stream',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Export impossible: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _openMailClientWithAttachment({
    required String filePath,
    required String subject,
    required String body,
  }) async {
    try {
      if (Platform.isLinux) {
        await Process.start(
          'xdg-email',
          ['--subject', subject, '--body', body, '--attach', filePath],
          mode: ProcessStartMode.detached,
        );
        final dir = File(filePath).parent.path;
        final hasNautilus = (await Process.run('which', ['nautilus']))
            .exitCode ==
            0;
        if (hasNautilus) {
          await Process.start(
            'nautilus',
            ['--select', filePath],
            mode: ProcessStartMode.detached,
          );
        } else {
          await Process.start(
            'xdg-open',
            [dir],
            mode: ProcessStartMode.detached,
          );
        }
        return true;
      }
      if (Platform.isMacOS) {
        String escaped(String s) =>
            s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
        final script = '''
tell application "Mail"
  set newMsg to make new outgoing message with properties {subject:"${escaped(subject)}", content:"${escaped(body)}", visible:true}
  tell newMsg
    make new attachment with properties {file name:(POSIX file "${escaped(filePath)}")} at after last paragraph
  end tell
  activate
end tell
''';
        final result = await Process.run('osascript', ['-e', script]);
        return result.exitCode == 0;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: Platform.isIOS ? FileType.any : FileType.custom,
      allowedExtensions:
          Platform.isIOS ? null : ['adlb', 'zip', 'bin'],
    );
    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    final bytes = await file.readAsBytes();

    if (!mounted) return;
    final passphrase = await _askPassphrase(confirm: false);
    if (passphrase == null) return;
    if (!mounted) return;

    final mode = await showDialog<_ImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Comment importer ?'),
        content: const Text(
          'Fusionner : vos données actuelles sont conservées et complétées. '
          'Pour chaque élément présent des deux côtés, la version la plus '
          'récente est gardée.\n\n'
          'Remplacer : toutes vos données actuelles (logements, locataires, '
          'états des lieux, quittances) sont supprimées et remplacées par '
          'celles du fichier. Les plans de logement locaux sont préservés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_ImportMode.merge),
            child: const Text('Fusionner'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(_ImportMode.replace),
            child: const Text('Remplacer'),
          ),
        ],
      ),
    );
    if (mode == null) return;

    setState(() => _busy = true);
    try {
      final report = mode == _ImportMode.replace
          ? await _service.importEncryptedReplace(
              bytes: bytes,
              passphrase: passphrase,
            )
          : await _service.importEncrypted(
              bytes: bytes,
              passphrase: passphrase,
            );
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(mode == _ImportMode.replace
              ? 'Restauration terminée'
              : 'Fusion terminée'),
          content: Text(
            'Profil : ${report.profileRestored ? 'installé' : 'conservé'}\n'
            'Logements : ${report.logements.describe()}\n'
            'Locataires : ${report.locataires.describe()}\n'
            'États des lieux : ${report.etatsDesLieux.describe()}\n'
            'Quittances : ${report.quittances.describe()}'
            '${report.duplicatesRemoved > 0 ? '\nDoublons fusionnés : ${report.duplicatesRemoved}' : ''}',
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
                final a = ctrl1.text.trim();
                final b = ctrl2.text.trim();
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
                icon: Icons.cloud_sync_outlined,
                title: 'Sauvegarde automatique',
                description:
                    'Pour ne plus jamais oublier d\'exporter, ADDA Bailleur '
                    'peut sauvegarder tout seul vers un dossier de votre '
                    'iCloud Drive, OneDrive, Google Drive ou pCloud.',
                button: 'Configurer',
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AutoBackupSettingsScreen(),
                          ),
                        ),
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
              _ActionCard(
                icon: Icons.archive_outlined,
                title: 'Sauvegardes reçues',
                description:
                    'Fichiers .adlb reçus depuis l\'extérieur (AirDrop, '
                    'Fichiers, partage Android…) et conservés dans '
                    'l\'application pour un import à tout moment.',
                button: 'Voir',
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ReceivedBackupsScreen(),
                          ),
                        ),
              ),
              const SizedBox(height: 16),
              // Accès direct à la suppression de compte (Apple 5.1.1(v)) : efface
              // aussi les sauvegardes cloud. Confirmation dans confirmDeleteAccount.
              _ActionCard(
                icon: Icons.delete_forever_outlined,
                title: 'Supprimer mon compte',
                description:
                    'Efface définitivement votre profil, toutes vos données et '
                    'les sauvegardes chiffrées de votre dossier cloud lié. '
                    'Action irréversible — une confirmation vous sera demandée.',
                button: 'Supprimer mon compte',
                onPressed: _busy ? null : () => confirmDeleteAccount(context),
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
