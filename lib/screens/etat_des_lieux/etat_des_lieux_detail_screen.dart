import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/pdf/etat_des_lieux_pdf.dart';
import '../../core/theme/app_theme.dart';
import '../../models/element_piece.dart';
import '../../models/etat_des_lieux.dart';
import '../../models/etat_element.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/plan_logement.dart';
import '../../models/user_profile.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/local_share_service.dart';
import '../../services/plan_logement_service.dart';
import '../../services/user_service.dart';
import '../../widgets/disclaimer_dialog.dart';
import '../sharing/local_share_screen.dart';
import 'etat_des_lieux_edit_screen.dart';
import 'locataire_signature_screen.dart';

enum _ShareMode { pdfOnly, pdfWithPhotos, localQr, email }

/// Affiche un loader plein écran pendant l'exécution de [task] et le ferme
/// quand la future se termine — évite que l'UI ait l'air figée pendant la
/// génération du PDF (qui peut être longue avec beaucoup de photos).
Future<T> _withLoading<T>(
  BuildContext context,
  String message,
  Future<T> Function() task,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  // Laisse au moins une frame s'afficher pour que le dialog soit visible
  // avant que le travail lourd ne démarre et ne bloque éventuellement
  // l'isolate principal.
  await Future.delayed(const Duration(milliseconds: 50));
  try {
    return await task();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

class EtatDesLieuxDetailScreen extends StatelessWidget {
  final String edlId;
  const EtatDesLieuxDetailScreen({super.key, required this.edlId});

  @override
  Widget build(BuildContext context) {
    final edl = context.watch<EtatDesLieuxService>().byId(edlId);
    if (edl == null) {
      return const Scaffold(body: Center(child: Text('EDL introuvable.')));
    }
    final logement = context.watch<LogementService>().byId(edl.logementId);
    final locataire = context.watch<LocataireService>().byId(edl.locataireId);
    final bailleur = context.watch<UserService>().current;
    final plans = context
        .watch<PlanLogementService>()
        .byLogement(edl.logementId);
    final wallPhotos = plans
        .expand((plan) => plan.wallPhotos)
        .where((w) => w.etatId == edl.id)
        .toList();

    final df = DateFormat('dd/MM/yyyy', 'fr_FR');
    final dfDt = DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR');

    final canExport =
        bailleur != null && logement != null && locataire != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(edl.titre),
        actions: [
          if (edl.isDraft)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EtatDesLieuxEditScreen(edlId: edlId),
                ),
              ),
            ),
          if (edl.isPendingTenantSignature)
            IconButton(
              icon: const Icon(Icons.draw_outlined),
              tooltip: 'Faire signer le locataire',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LocataireSignatureScreen(edlId: edlId),
                ),
              ),
            ),
          if (canExport)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Partager le PDF',
              onPressed: () => _showShareSheet(
                context,
                edl: edl,
                bailleur: bailleur,
                logement: logement,
                locataire: locataire,
                wallPhotos: wallPhotos,
                plans: plans,
              ),
            ),
          if (canExport)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Imprimer',
              onPressed: () async {
                // Avertissement juridique avant toute génération.
                if (!await DisclaimerDialog.show(context)) return;
                if (!context.mounted) return;
                await _printPdf(
                  edl: edl,
                  bailleur: bailleur,
                  logement: logement,
                  locataire: locataire,
                  wallPhotos: wallPhotos,
                  plans: plans,
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer',
            onPressed: () => _confirmDelete(context, edl),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Header(edl: edl),
          const SizedBox(height: 16),
          _Card(
            title: 'Informations',
            children: [
              _Row(label: 'Logement', value: logement?.libelle ?? '—'),
              _Row(label: 'Adresse', value: logement?.adresseComplete ?? '—'),
              _Row(label: 'Locataire', value: locataire?.fullName ?? '—'),
              _Row(label: 'Date', value: df.format(edl.date)),
              _Row(label: 'Statut', value: edl.status.label, bold: true),
            ],
          ),
          const SizedBox(height: 16),
          ...edl.pieces.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _Card(
                  title: p.nom.toUpperCase(),
                  children: p.elements.isEmpty
                      ? [
                          const Text(
                            'Aucun élément.',
                            style:
                                TextStyle(color: AppColors.textSecondary),
                          ),
                        ]
                      : p.elements
                          .map((e) => _ElementView(element: e))
                          .toList(),
                ),
              )),
          if (edl.proprietaireSignaturePng != null) ...[
            const SizedBox(height: 16),
            _Card(
              title: 'Signature propriétaire',
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.memory(
                    base64Decode(edl.proprietaireSignaturePng!),
                    height: 140,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Signé le ${dfDt.format(edl.proprietaireSignatureAt!.toLocal())}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (edl.isFinalized) ...[
            const SizedBox(height: 16),
            _Card(
              title: 'Certification',
              children: [
                _Row(
                  label: 'Locataire',
                  value:
                      'Co-signé le ${dfDt.format(edl.locataireSignatureAt!.toLocal())}',
                ),
                _Row(label: 'Hash SHA-256', value: edl.integrityHash ?? '—'),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_outlined,
                          color: AppColors.success, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          edl.verifyIntegrity()
                              ? 'Intégrité vérifiée — document authentique.'
                              : 'Hash altéré — document potentiellement compromis.',
                          style: TextStyle(
                            color: edl.verifyIntegrity()
                                ? AppColors.success
                                : AppColors.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _pdfFilename(EtatDesLieux edl, Locataire locataire) {
    final safe = locataire.fullName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final date =
        '${edl.date.year}-${edl.date.month.toString().padLeft(2, '0')}-${edl.date.day.toString().padLeft(2, '0')}';
    return 'edl_${edl.type.name}_${date}_$safe.pdf';
  }

  Future<void> _showShareSheet(
    BuildContext context, {
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Logement logement,
    required Locataire locataire,
    required List<WallPhoto> wallPhotos,
    required List<PlanLogement> plans,
  }) async {
    // Avertissement juridique à lire et accepter avant toute génération.
    if (!await DisclaimerDialog.show(context)) return;
    if (!context.mounted) return;
    final hasPhotos = _collectPhotoPaths(edl, wallPhotos).isNotEmpty;
    final mode = await showModalBottomSheet<_ShareMode>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF seul'),
              subtitle: const Text(
                'Photos intégrées au PDF (annexe).',
              ),
              onTap: () => Navigator.of(ctx).pop(_ShareMode.pdfOnly),
            ),
            if (hasPhotos)
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('PDF + photos en pièces jointes'),
                subtitle: const Text(
                  'Le PDF et chaque photo en fichiers séparés.',
                ),
                onTap: () =>
                    Navigator.of(ctx).pop(_ShareMode.pdfWithPhotos),
              ),
            ListTile(
              leading: const Icon(Icons.qr_code_2_outlined),
              title: const Text('QR code Wi-Fi local'),
              subtitle: const Text(
                'Le locataire scanne et télécharge — sans cloud, sans internet.',
              ),
              onTap: () => Navigator.of(ctx).pop(_ShareMode.localQr),
            ),
            if (locataire.email.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Envoyer par email au locataire'),
                subtitle: Text(
                  'Ouvre votre messagerie · destinataire : ${locataire.email}',
                ),
                onTap: () => Navigator.of(ctx).pop(_ShareMode.email),
              )
            else
              const ListTile(
                leading: Icon(Icons.email_outlined,
                    color: Colors.grey),
                title: Text(
                  'Envoyer par email au locataire',
                  style: TextStyle(color: Colors.grey),
                ),
                subtitle: Text(
                  'Aucune adresse email enregistrée pour ce locataire.',
                  style: TextStyle(color: Colors.grey),
                ),
                enabled: false,
              ),
          ],
        ),
      ),
    );
    if (mode == null || !context.mounted) return;
    if (mode == _ShareMode.pdfOnly) {
      if (!context.mounted) return;
      await _sharePdfOnly(
        context,
        edl: edl,
        bailleur: bailleur,
        logement: logement,
        locataire: locataire,
        wallPhotos: wallPhotos,
        plans: plans,
      );
    } else if (mode == _ShareMode.pdfWithPhotos) {
      if (!context.mounted) return;
      await _sharePdfWithPhotos(
        context,
        edl: edl,
        bailleur: bailleur,
        logement: logement,
        locataire: locataire,
        wallPhotos: wallPhotos,
        plans: plans,
      );
    } else if (mode == _ShareMode.localQr) {
      if (!context.mounted) return;
      await _shareViaLocalQr(
        context,
        edl: edl,
        bailleur: bailleur,
        logement: logement,
        locataire: locataire,
        wallPhotos: wallPhotos,
        plans: plans,
      );
    } else if (mode == _ShareMode.email) {
      if (!context.mounted) return;
      await _shareViaEmail(
        context,
        edl: edl,
        bailleur: bailleur,
        logement: logement,
        locataire: locataire,
        wallPhotos: wallPhotos,
        plans: plans,
      );
    }
  }

  Future<void> _shareViaEmail(
    BuildContext context, {
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Logement logement,
    required Locataire locataire,
    required List<WallPhoto> wallPhotos,
    required List<PlanLogement> plans,
  }) async {
    final pdfFilename = _pdfFilename(edl, locataire);
    final pdfFile = await _withLoading<File>(
      context,
      'Génération du PDF…',
      () async {
        final doc = await EtatDesLieuxPdfBuilder.build(
          edl: edl,
          bailleur: bailleur,
          logement: logement,
          locataire: locataire,
          wallPhotos: wallPhotos,
          plans: plans,
        );
        final docsDir = await getApplicationDocumentsDirectory();
        final exportDir = Directory('${docsDir.path}/edl_exports');
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }
        final f = File('${exportDir.path}/$pdfFilename');
        await f.writeAsBytes(await doc.save(), flush: true);
        return f;
      },
    );
    if (!context.mounted) return;

    final subject = 'État des lieux ${edl.titre} — ${logement.libelle}';
    final body =
        'Bonjour ${locataire.fullName},\n\n'
        'Veuillez trouver ci-joint l\'état des lieux concernant le logement '
        '« ${logement.libelle} ».\n\n'
        'Cordialement,\n'
        '${bailleur.fullName}';

    if (Platform.isMacOS) {
      // Stratégie macOS :
      // 1) `open -a Mail <pdf>` ouvre une nouvelle fenêtre de composition
      //    Mail.app avec le PDF déjà attaché (sandbox-safe).
      // 2) On copie l'adresse du locataire dans le presse-papiers et on
      //    affiche un SnackBar pour qu'il suffise de coller dans le champ À.
      // L'AppleScript pour préremplir destinataire/sujet est instable depuis
      // un binaire sandboxé, donc on ne s'appuie pas dessus.
      try {
        final result = await Process.run('open', ['-a', 'Mail', pdfFile.path]);
        if (result.exitCode != 0) {
          throw Exception(result.stderr);
        }
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Mail.app indisponible. PDF enregistré ici :\n${pdfFile.path}'),
          ),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: locataire.email));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Mail.app ouvert avec le PDF attaché.\n'
            'Adresse copiée : ${locataire.email} — collez-la dans À.',
          ),
          action: SnackBarAction(
            label: 'Copier sujet',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: subject));
            },
          ),
        ),
      );
      return;
    }

    // Android et autres : on partage directement le PDF via la share sheet
    // système, qui ouvre la messagerie choisie avec le fichier déjà attaché.
    // mailto: ne supporte pas les pièces jointes, on copie donc l'adresse
    // du locataire dans le presse-papiers pour qu'un simple paste suffise.
    await Clipboard.setData(ClipboardData(text: locataire.email));
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    await Share.shareXFiles(
      [XFile(pdfFile.path, mimeType: 'application/pdf')],
      subject: subject,
      text: body,
      sharePositionOrigin: origin,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
          'Adresse copiée : ${locataire.email}\n'
          'Collez-la dans le champ destinataire de votre messagerie.',
        ),
      ),
    );
  }

  Future<void> _shareViaLocalQr(
    BuildContext context, {
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Logement logement,
    required Locataire locataire,
    required List<WallPhoto> wallPhotos,
    required List<PlanLogement> plans,
  }) async {
    final pdfFilename = _pdfFilename(edl, locataire);
    final pdfFile = await _withLoading<File>(
      context,
      'Génération du PDF…',
      () async {
        final doc = await EtatDesLieuxPdfBuilder.build(
          edl: edl,
          bailleur: bailleur,
          logement: logement,
          locataire: locataire,
          wallPhotos: wallPhotos,
          plans: plans,
          includePhotosAnnex: false,
        );
        final tempDir = await getTemporaryDirectory();
        if (!await tempDir.exists()) {
          await tempDir.create(recursive: true);
        }
        final f = File('${tempDir.path}/$pdfFilename');
        await f.writeAsBytes(await doc.save(), flush: true);
        return f;
      },
    );
    if (!context.mounted) return;

    final files = <ShareableFile>[
      ShareableFile(
        path: pdfFile.path,
        filename: pdfFilename,
        mimeType: 'application/pdf',
      ),
    ];
    final photoPaths = _collectPhotoPaths(edl, wallPhotos);
    var i = 1;
    for (final p in photoPaths) {
      if (!File(p).existsSync()) continue;
      final ext = p.toLowerCase().endsWith('.png')
          ? 'png'
          : p.toLowerCase().endsWith('.heic')
              ? 'heic'
              : 'jpg';
      files.add(ShareableFile(
        path: p,
        filename: 'photo_${i.toString().padLeft(3, '0')}.$ext',
        mimeType: _mimeFor(p),
      ));
      i++;
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocalShareScreen(
          title: 'EDL ${edl.titre}',
          files: files,
        ),
      ),
    );
  }

  Future<void> _sharePdfOnly(
    BuildContext context, {
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Logement logement,
    required Locataire locataire,
    required List<WallPhoto> wallPhotos,
    required List<PlanLogement> plans,
  }) async {
    final bytes = await _withLoading<Uint8List>(
      context,
      'Génération du PDF…',
      () async {
        final doc = await EtatDesLieuxPdfBuilder.build(
          edl: edl,
          bailleur: bailleur,
          logement: logement,
          locataire: locataire,
          wallPhotos: wallPhotos,
          plans: plans,
        );
        return doc.save();
      },
    );
    if (!context.mounted) return;
    await Printing.sharePdf(
      bytes: bytes,
      filename: _pdfFilename(edl, locataire),
    );
  }

  Future<void> _sharePdfWithPhotos(
    BuildContext context, {
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Logement logement,
    required Locataire locataire,
    required List<WallPhoto> wallPhotos,
    required List<PlanLogement> plans,
  }) async {
    final pdfFile = await _withLoading<File>(
      context,
      'Génération du PDF et préparation des photos…',
      () async {
        final doc = await EtatDesLieuxPdfBuilder.build(
          edl: edl,
          bailleur: bailleur,
          logement: logement,
          locataire: locataire,
          wallPhotos: wallPhotos,
          plans: plans,
          includePhotosAnnex: false,
        );
        final tempDir = await getTemporaryDirectory();
        if (!await tempDir.exists()) {
          await tempDir.create(recursive: true);
        }
        final f = File('${tempDir.path}/${_pdfFilename(edl, locataire)}');
        await f.writeAsBytes(await doc.save(), flush: true);
        return f;
      },
    );
    if (!context.mounted) return;

    final photoPaths = _collectPhotoPaths(edl, wallPhotos);
    final files = <XFile>[
      XFile(pdfFile.path, mimeType: 'application/pdf'),
      ...photoPaths
          .where((p) => File(p).existsSync())
          .map((p) => XFile(p, mimeType: _mimeFor(p))),
    ];
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    await Share.shareXFiles(
      files,
      subject: 'EDL ${edl.titre}',
      sharePositionOrigin: origin,
    );
  }

  List<String> _collectPhotoPaths(
    EtatDesLieux edl,
    List<WallPhoto> wallPhotos,
  ) {
    final out = <String>[];
    for (final piece in edl.pieces) {
      for (final element in piece.elements) {
        out.addAll(element.photoPaths);
      }
    }
    out.addAll(wallPhotos.map((w) => w.path));
    return out;
  }

  String _mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> _printPdf({
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Logement logement,
    required Locataire locataire,
    required List<WallPhoto> wallPhotos,
    required List<PlanLogement> plans,
  }) async {
    await Printing.layoutPdf(
      name: _pdfFilename(edl, locataire),
      onLayout: (format) async {
        final doc = await EtatDesLieuxPdfBuilder.build(
          edl: edl,
          bailleur: bailleur,
          logement: logement,
          locataire: locataire,
          wallPhotos: wallPhotos,
          plans: plans,
        );
        return doc.save();
      },
    );
  }

  void _confirmDelete(BuildContext context, EtatDesLieux edl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet EDL ?'),
        content: Text(
          edl.isFinalized
              ? 'Attention : cet EDL est finalisé et co-signé. '
                  'Sa suppression est définitive et toutes ses photos seront effacées.'
              : 'Cet état des lieux et toutes ses photos seront supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () async {
              await context
                  .read<PlanLogementService>()
                  .deleteWallPhotosForEtat(
                    logementId: edl.logementId,
                    etatId: edl.id,
                  );
              if (!ctx.mounted) return;
              await context.read<EtatDesLieuxService>().delete(edl.id);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final EtatDesLieux edl;
  const _Header({required this.edl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            edl.type == EtatDesLieuxType.entree
                ? Icons.login_rounded
                : Icons.logout_rounded,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  edl.titre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    edl.status.label.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Card({required this.title, required this.children});

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
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _Row({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color:
                  bold ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ElementView extends StatelessWidget {
  final ElementPiece element;
  const _ElementView({required this.element});

  Color _colorFor(EtatElement e) {
    switch (e) {
      case EtatElement.bon:
        return AppColors.success;
      case EtatElement.moyen:
        return AppColors.accent;
      case EtatElement.mauvais:
        return Colors.orange;
      case EtatElement.aRemplacer:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(element.etat);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  element.nom,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  element.etat.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (element.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              element.description,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          if (element.photoPaths.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: element.photoPaths.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(element.photoPaths[i]),
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 70,
                      height: 70,
                      color: AppColors.divider,
                      child: const Icon(Icons.broken_image,
                          size: 22, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
