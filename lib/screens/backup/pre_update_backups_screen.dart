import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/storage/local_database.dart';
import '../../core/theme/app_theme.dart';

/// Liste les sauvegardes de sécurité créées automatiquement avant chaque
/// mise à jour de l'application, et permet de revenir à l'une d'elles.
class PreUpdateBackupsScreen extends StatefulWidget {
  const PreUpdateBackupsScreen({super.key});

  @override
  State<PreUpdateBackupsScreen> createState() => _PreUpdateBackupsScreenState();
}

class _PreUpdateBackupsScreenState extends State<PreUpdateBackupsScreen> {
  List<Directory> _snapshots = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await LocalDatabase.listPreUpdateSnapshots();
    if (!mounted) return;
    setState(() {
      _snapshots = s;
      _loading = false;
    });
  }

  /// Nom de dossier `<stamp>__v<version>` → libellé lisible.
  ({String date, String version}) _describe(Directory d) {
    final name = d.path.split(Platform.pathSeparator).last;
    final parts = name.split('__v');
    final stamp = parts.isNotEmpty ? parts.first : name;
    final version = parts.length > 1 ? parts[1] : '?';
    // stamp ISO « 2026-06-09T18-40-05-123 » → on garde date + heure lisibles.
    final clean = stamp.replaceAll('T', ' à ').replaceFirst(
          RegExp(r'(\d{2})-(\d{2})-(\d{2,})$'),
          '',
        );
    final dateOnly = clean.split(' à ').first;
    final timeRaw = stamp.contains('T') ? stamp.split('T')[1] : '';
    final time = timeRaw.length >= 5
        ? '${timeRaw.substring(0, 2)}:${timeRaw.substring(3, 5)}'
        : '';
    return (date: time.isEmpty ? dateOnly : '$dateOnly à $time', version: version);
  }

  Future<void> _restore(Directory d) async {
    final info = _describe(d);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurer cet état ?'),
        content: Text(
          'Les données reviendront à l\'état d\'avant la version '
          '${info.version} (${info.date}). La restauration s\'applique au '
          'prochain démarrage de l\'application.',
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
    await LocalDatabase.requestRestore(d.path);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restauration programmée'),
        content: const Text(
          'Fermez puis rouvrez l\'application pour appliquer la restauration.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegardes de sécurité')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _snapshots.isEmpty
              ? _empty(context)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'L\'application crée automatiquement une copie de vos '
                        'données avant chaque mise à jour. En cas de souci, '
                        'vous pouvez revenir à l\'un de ces états.',
                        style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondaryColor,
                            height: 1.4),
                      ),
                    ),
                    for (final d in _snapshots) _tile(context, d),
                  ],
                ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_toggle_off,
                  size: 48, color: context.textSecondaryColor),
              const SizedBox(height: 12),
              Text(
                'Aucune sauvegarde de sécurité pour l\'instant.\nUne copie sera '
                'créée automatiquement avant la prochaine mise à jour.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textSecondaryColor),
              ),
            ],
          ),
        ),
      );

  Widget _tile(BuildContext context, Directory d) {
    final info = _describe(d);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.restore, color: AppColors.primary),
        title: Text('Avant la version ${info.version}'),
        subtitle: Text(info.date),
        trailing: TextButton(
          onPressed: () => _restore(d),
          child: const Text('Restaurer'),
        ),
      ),
    );
  }
}
