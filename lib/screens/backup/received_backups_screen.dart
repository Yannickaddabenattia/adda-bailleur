import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/backup/backup_codec.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backup_service.dart';
import '../../services/received_backups_service.dart';

/// Liste les fichiers `.adlb` reçus depuis l'extérieur (AirDrop, Fichiers,
/// partage Android…) et conservés dans `Documents/sauvegardes_recues/` du
/// sandbox de l'application. Permet de relancer l'import, de partager le
/// fichier ou de le supprimer.
class ReceivedBackupsScreen extends StatefulWidget {
  const ReceivedBackupsScreen({super.key});

  @override
  State<ReceivedBackupsScreen> createState() => _ReceivedBackupsScreenState();
}

class _ReceivedBackupsScreenState extends State<ReceivedBackupsScreen> {
  late Future<List<ReceivedBackup>> _future;
  ReceivedBackupsService? _service;

  @override
  void initState() {
    super.initState();
    _service = context.read<ReceivedBackupsService>();
    _future = _service!.list();
    _service!.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service?.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {
      _future = _service!.list();
    });
  }

  void _refresh() {
    setState(() {
      _future = _service!.list();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegardes reçues')),
      body: FutureBuilder<List<ReceivedBackup>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erreur : ${snap.error}'),
              ),
            );
          }
          final items = snap.data ?? const <ReceivedBackup>[];
          if (items.isEmpty) return const _Empty();
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) => _BackupTile(
                backup: items[i],
                onChanged: _refresh,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BackupTile extends StatefulWidget {
  final ReceivedBackup backup;
  final VoidCallback onChanged;
  const _BackupTile({required this.backup, required this.onChanged});

  @override
  State<_BackupTile> createState() => _BackupTileState();
}

class _BackupTileState extends State<_BackupTile> {
  bool _busy = false;

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} Ko';
    return '${(kb / 1024).toStringAsFixed(2)} Mo';
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR');
    final b = widget.backup;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.archive_outlined,
                    size: 22, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    b.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${df.format(b.receivedAt.toLocal())} · ${_humanSize(b.size)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.restore_outlined, size: 18),
                    label: const Text('Importer'),
                    onPressed: _busy ? null : _import,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.ios_share_outlined),
                  tooltip: 'Partager',
                  onPressed: _busy ? null : _share,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.error),
                  tooltip: 'Supprimer',
                  onPressed: _busy ? null : _delete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _import() async {
    final passphrase = await _askPassphrase();
    if (passphrase == null || passphrase.isEmpty) return;
    setState(() => _busy = true);
    try {
      final bytes = await widget.backup.file.readAsBytes();
      final report = await BackupService().importEncrypted(
        bytes: bytes,
        passphrase: passphrase,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fusion terminée'),
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
      _snack('Passphrase incorrecte.');
    } on BackupFormatException catch (e) {
      if (!mounted) return;
      _snack('Fichier invalide : ${e.message}');
    } catch (e) {
      if (!mounted) return;
      _snack('Import impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(widget.backup.file.path, mimeType: 'application/octet-stream')],
      subject: 'Sauvegarde ADDA Bailleur',
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce fichier ?'),
        content: Text(
          'Le fichier « ${widget.backup.name} » sera supprimé de l\'application. '
          'Vos données restent intactes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    final svc = context.read<ReceivedBackupsService>();
    await svc.delete(widget.backup.file);
    widget.onChanged();
  }

  Future<String?> _askPassphrase() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saisir la passphrase'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Passphrase',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Importer'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.archive_outlined,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Aucune sauvegarde reçue',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 4),
            const Text(
              'Les fichiers .adlb que vous recevez (AirDrop, Fichiers…) '
              'sont automatiquement enregistrés ici.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
