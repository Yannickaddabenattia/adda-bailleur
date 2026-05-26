import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/backup/backup_codec.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backup_service.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../services/received_backups_service.dart';
import '../../widgets/primary_button.dart';

/// Écran ouvert quand l'utilisateur tape un fichier `.adlr` (retour signé
/// envoyé par le locataire) ou `.adlb` (sauvegarde complète) reçu depuis
/// l'extérieur. Demande le code/passphrase et route vers l'import.
class IncomingFileScreen extends StatefulWidget {
  final String filePath;
  const IncomingFileScreen({super.key, required this.filePath});

  @override
  State<IncomingFileScreen> createState() => _IncomingFileScreenState();
}

class _IncomingFileScreenState extends State<IncomingFileScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Chemin effectif du fichier après copie dans le dossier "ADDA Bailleur
  /// document". Tous les fichiers `.adlb` (sauvegardes) et `.adlr` (retours
  /// de signature) reçus sont systématiquement archivés là, afin de les
  /// conserver même si le fichier original est supprimé de la boîte de
  /// réception OS.
  late String _activePath = widget.filePath;
  bool _archived = false;

  String get _filename => _activePath.split(Platform.pathSeparator).last;
  bool get _isSignatureReturn => _filename.toLowerCase().endsWith('.adlr');
  bool get _isBackup => _filename.toLowerCase().endsWith('.adlb');

  @override
  void initState() {
    super.initState();
    final lower = widget.filePath.toLowerCase();
    if (lower.endsWith('.adlb') || lower.endsWith('.adlr')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _archiveBackup());
    }
  }

  Future<void> _archiveBackup() async {
    if (!mounted) return;
    final service = context.read<ReceivedBackupsService>();
    try {
      final saved = await service.save(File(widget.filePath));
      if (!mounted) return;
      setState(() {
        _activePath = saved.path;
        _archived = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Archivage impossible : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _process() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Saisissez le code ou la passphrase.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final bytes = await File(_activePath).readAsBytes();

      // .adlr → retour signé locataire (code 8 chars, majuscules).
      // .adlb → sauvegarde complète (passphrase utilisateur).
      try {
        final jsonText = await BackupCodec.decryptAsync(
          bytes: bytes,
          passphrase: _isSignatureReturn ? code.toUpperCase() : code,
        );
        final decoded = jsonDecode(jsonText);
        final kind = decoded is Map<String, dynamic> ? decoded['kind'] : null;

        if (kind == 'tenant_signature') {
          await _importAsSignature(decoded as Map<String, dynamic>);
        } else {
          await _importAsBackup(bytes, code);
        }
      } on BackupDecryptionException {
        if (_isBackup) {
          await _importAsBackup(bytes, code);
        } else {
          rethrow;
        }
      }
    } on BackupDecryptionException {
      if (!mounted) return;
      setState(() {
        _error = _isSignatureReturn
            ? 'Code incorrect.'
            : 'Passphrase incorrecte.';
        _busy = false;
      });
    } on BackupFormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Fichier invalide : ${e.message}';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible d\'ouvrir le fichier : $e';
        _busy = false;
      });
    }
  }

  Future<void> _importAsSignature(Map<String, dynamic> payload) async {
    final edlId = payload['edlId'] as String?;
    final preHash = payload['preSignatureHash'] as String?;
    final signaturePng = payload['locataireSignaturePng'] as String?;
    final signedAtIso = payload['locataireSignatureAt'] as String?;
    if (edlId == null ||
        preHash == null ||
        signaturePng == null ||
        signedAtIso == null) {
      throw const BackupFormatException('Fichier signature incomplet.');
    }
    final signedAt = DateTime.parse(signedAtIso);
    final service = context.read<EtatDesLieuxService>();
    final edl = await service.applyLocataireSignatureFromShare(
      edlId: edlId,
      preSignatureHash: preHash,
      signaturePngBase64: signaturePng,
      signedAt: signedAt,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Signature reçue'),
        content: Text(
          'L\'état des lieux du ${_formatDate(edl.date)} est désormais '
          'finalisé avec la signature du locataire.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _formatDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year}';
  }

  Future<void> _importAsBackup(List<int> bytes, String passphrase) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fusionner cette sauvegarde ?'),
        content: const Text(
          'Vos données actuelles sont conservées. Pour chaque élément '
          'présent des deux côtés, la version la plus récente est gardée. '
          'Les quittances déjà présentes ne sont pas écrasées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Fusionner'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final report = await BackupService().importEncrypted(
      bytes: Uint8List.fromList(bytes),
      passphrase: passphrase,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fusion terminée'),
        content: Text(
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
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final share = _isSignatureReturn;
    final title = share ? 'Signature reçue' : 'Sauvegarde reçue';
    final subtitle = share
        ? 'Saisissez le code à 8 caractères communiqué par le locataire.'
        : 'Saisissez la passphrase utilisée lors de l\'export.';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _filename,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (_archived) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.folder_open_outlined,
                        size: 18, color: AppColors.success),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Archivé dans « ADDA Bailleur document ».',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(subtitle,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              obscureText: !share,
              textCapitalization:
                  share ? TextCapitalization.characters : TextCapitalization.none,
              textAlign: share ? TextAlign.center : TextAlign.start,
              maxLength: share ? 8 : null,
              style: share
                  ? const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    )
                  : null,
              inputFormatters: share
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))]
                  : null,
              decoration: InputDecoration(
                labelText: share ? 'Code' : 'Passphrase',
                prefixIcon: Icon(share
                    ? Icons.password_outlined
                    : Icons.lock_outline),
                errorText: _error,
              ),
              onSubmitted: (_) => _busy ? null : _process(),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: share ? 'Recevoir' : 'Restaurer',
              icon: share ? Icons.download_outlined : Icons.restore_outlined,
              loading: _busy,
              onPressed: _busy ? null : _process,
            ),
          ],
        ),
      ),
    );
  }
}
