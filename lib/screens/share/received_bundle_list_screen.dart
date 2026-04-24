import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/backup/backup_codec.dart';
import '../../core/theme/app_theme.dart';
import '../../models/received_bundle.dart';
import '../../services/tenant_share_service.dart';
import '../../widgets/primary_button.dart';
import 'received_bundle_detail_screen.dart';

class ReceivedBundleListScreen extends StatefulWidget {
  const ReceivedBundleListScreen({super.key});

  @override
  State<ReceivedBundleListScreen> createState() =>
      _ReceivedBundleListScreenState();
}

class _ReceivedBundleListScreenState extends State<ReceivedBundleListScreen> {
  bool _busy = false;

  Future<void> _receiveNew() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['adls', 'adlb'],
    );
    if (result == null || result.files.single.path == null) return;
    final bytes = await File(result.files.single.path!).readAsBytes();
    if (!mounted) return;

    final code = await _askCode();
    if (code == null) return;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      final bundle = await context
          .read<TenantShareService>()
          .saveReceivedShare(bytes: bytes, code: code);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReceivedBundleDetailScreen(bundleId: bundle.id),
        ),
      );
    } on BackupDecryptionException {
      if (!mounted) return;
      _showError('Code incorrect.');
    } on BackupFormatException catch (e) {
      if (!mounted) return;
      _showError('Fichier invalide : ${e.message}');
    } catch (e) {
      if (!mounted) return;
      _showError('Import impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askCode() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Code de partage'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Saisissez le code à 8 caractères communiqué par le propriétaire.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              maxLength: 8,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              decoration: const InputDecoration(hintText: 'CODE'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bundles = context.watch<TenantShareService>().receivedBundles;
    return Scaffold(
      appBar: AppBar(title: const Text('Documents reçus')),
      body: bundles.isEmpty
          ? _Empty(onAdd: _busy ? null : _receiveNew, busy: _busy)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: bundles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) => _BundleCard(bundle: bundles[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _receiveNew,
        icon: const Icon(Icons.download_outlined),
        label: const Text('Recevoir'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _BundleCard extends StatelessWidget {
  final ReceivedBundle bundle;
  const _BundleCard({required this.bundle});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR');
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReceivedBundleDetailScreen(bundleId: bundle.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.folder_open_outlined,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'De ${bundle.fromName}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Reçu ${df.format(bundle.receivedAt.toLocal())}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback? onAdd;
  final bool busy;
  const _Empty({required this.onAdd, required this.busy});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined,
                size: 72,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'Aucun document reçu',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Importez un fichier .adls partagé par votre propriétaire.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Recevoir un partage',
              icon: Icons.download_outlined,
              loading: busy,
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}
