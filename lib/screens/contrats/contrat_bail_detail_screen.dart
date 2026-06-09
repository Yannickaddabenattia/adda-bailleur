import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';

import '../../core/constants.dart';
import '../../core/pdf/contrat_bail_annexes_pdf.dart';
import '../../core/pdf/contrat_bail_pdf.dart';
import '../../core/storage/local_database.dart';
import '../../core/theme/app_theme.dart';
import '../../models/contrat_bail.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../services/contrat_bail_service.dart';
import '../../services/contrat_bail_validation_service.dart';
import '../../services/diagnostic_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../widgets/primary_button.dart';
import 'avenant_list_screen.dart';
import 'contrat_bail_form_screen.dart';

class ContratBailDetailScreen extends StatelessWidget {
  final String bailId;
  const ContratBailDetailScreen({super.key, required this.bailId});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ContratBailService>();
    final bail = svc.byId(bailId);
    if (bail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bail')),
        body: const Center(child: Text('Contrat introuvable.')),
      );
    }
    final logement = context.watch<LogementService>().byId(bail.logementId);
    final locataires = context
        .watch<LocataireService>()
        .all
        .where((l) => bail.locataireIds.contains(l.id))
        .toList();
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final dateFmt = DateFormat('dd MMM yyyy', 'fr_FR');

    return Scaffold(
      appBar: AppBar(
        title: Text(bail.reference),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Modifier',
            onPressed: logement == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ContratBailFormScreen(
                          logement: logement,
                          existing: bail,
                        ),
                      ),
                    ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                final ok = await _confirmDelete(context);
                if (ok && context.mounted) {
                  await svc.delete(bail.id);
                  if (context.mounted) Navigator.of(context).pop();
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Header(bail: bail),
          const SizedBox(height: 16),
          _Section('Récapitulatif', [
            _kv('Type', bail.type.label),
            _kv('Logement', logement?.libelle ?? '(inconnu)'),
            _kv('Adresse', bail.adresseLogement),
            _kv('Surface', '${bail.surfaceM2.toStringAsFixed(1)} m²'),
            _kv('Durée', '${bail.dureeMois} mois'),
            _kv('Du', dateFmt.format(bail.dateDebut)),
            _kv('Au', dateFmt.format(bail.dateFin)),
          ]),
          _Section('Financier', [
            _kv('Loyer HC', money.format(bail.loyerHC)),
            _kv('Charges', money.format(bail.charges)),
            _kv('Total mensuel', money.format(bail.totalMensuel)),
            _kv('Dépôt de garantie', money.format(bail.depotGarantie)),
            _kv('Échéance', 'Le ${bail.jourEcheance} du mois'),
            _kv('Mode', bail.modePaiement.label),
            if (bail.rib != null && bail.rib!.isNotEmpty)
              _kv('RIB', bail.rib!),
          ]),
          _Section('Locataires (${locataires.length})', [
            for (final l in locataires)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(l.fullName),
                subtitle: Text(l.email),
                trailing: bail.signaturesLocatairesPng[l.id] != null &&
                        bail.signaturesLocatairesPng[l.id]!.isNotEmpty
                    ? const Icon(Icons.check_circle, color: AppColors.success)
                    : const Icon(Icons.pending_outlined,
                        color: AppColors.textSecondary),
                onTap: () => _signLocataire(context, bail, l),
              ),
          ]),
          const SizedBox(height: 8),
          _SignatureRow(
            label: 'Signature bailleur',
            signed: bail.signatureBailleurPng != null &&
                bail.signatureBailleurPng!.isNotEmpty,
            onSign: () => _signBailleur(context, bail),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Générer / régénérer le PDF',
            icon: Icons.picture_as_pdf_outlined,
            onPressed: logement == null
                ? null
                : () => _generatePdf(context, bail, logement, locataires),
          ),
          if (bail.pdfPath != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _openPdf(context, bail.pdfPath!),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Ouvrir le PDF'),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: logement == null
                ? null
                : () => _generateAnnexesPdf(
                      context,
                      bail,
                      logement,
                      locataires,
                    ),
            icon: const Icon(Icons.library_books_outlined),
            label: const Text('Générer les annexes obligatoires'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AvenantListScreen(bail: bail),
              ),
            ),
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Avenants'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce bail ?'),
        content: const Text(
          'Action irréversible. Le PDF généré reste sur le disque.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _signBailleur(BuildContext context, ContratBail bail) async {
    final png = await _showSignaturePad(context, 'Signature bailleur');
    if (png == null) return;
    bail.signatureBailleurPng = png;
    bail.signatureBailleurAt = DateTime.now().toUtc();
    bail.statut = BailStatus.signe;
    await context.read<ContratBailService>().save(bail);
  }

  Future<void> _signLocataire(
      BuildContext context, ContratBail bail, Locataire l) async {
    final png =
        await _showSignaturePad(context, 'Signature de ${l.fullName}');
    if (png == null) return;
    bail.signaturesLocatairesPng[l.id] = png;
    bail.signaturesLocatairesAt[l.id] =
        DateTime.now().toUtc().toIso8601String();
    await context.read<ContratBailService>().save(bail);
  }

  Future<String?> _showSignaturePad(
      BuildContext context, String title) async {
    final ctrl = SignatureController(
      penStrokeWidth: 2,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          height: 220,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Signature(
              controller: ctrl,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.clear();
            },
            child: const Text('Effacer'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              if (ctrl.isEmpty) return;
              final bytes = await ctrl.toPngBytes();
              if (bytes == null) return;
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop(base64Encode(bytes));
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  /// Affiche la liste des problèmes bloquants empêchant la génération du PDF.
  Future<void> _showBailIncompletDialog(
      BuildContext context, List<String> problemes) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bail incomplet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La génération du PDF est bloquée tant que ces points ne sont '
              'pas corrigés :',
            ),
            const SizedBox(height: 12),
            for (final p in problemes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(p)),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePdf(
    BuildContext context,
    ContratBail bail,
    dynamic logement,
    List<Locataire> locataires,
  ) async {
    // Verrou dur : un bail incomplet ne doit jamais générer de PDF.
    final problemes = ContratBailValidation.validateFull(
      bail,
      logement: logement is Logement ? logement : null,
      diagnostics:
          context.read<DiagnosticService>().forLogement(bail.logementId),
    );
    if (problemes.isNotEmpty) {
      await _showBailIncompletDialog(context, problemes);
      return;
    }
    final bailleur =
        LocalDatabase.userBox.get(AppConstants.userProfileKey);
    if (bailleur == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil bailleur manquant.')),
      );
      return;
    }

    final diagnostics = context
        .read<DiagnosticService>()
        .forLogement(bail.logementId)
        .where((d) => bail.diagnosticIds.contains(d.id) || true)
        .toList();

    // Hash d'intégrité calculé sur les champs clés AVANT génération.
    final canonical = [
      bail.id,
      bail.reference,
      bail.type.name,
      bail.dateDebut.toIso8601String(),
      bail.dateFin.toIso8601String(),
      bail.loyerHC.toString(),
      bail.charges.toString(),
      bail.depotGarantie.toString(),
      bail.locataireIds.join(','),
      bail.signatureBailleurPng ?? '',
      bail.signaturesLocatairesPng.entries
          .map((e) => '${e.key}=${e.value}')
          .join('|'),
    ].join('::');
    bail.integrityHash = sha256.convert(utf8.encode(canonical)).toString();

    Uint8List bytes;
    try {
      bytes = await _withLoading<Uint8List>(
        context,
        'Génération du contrat PDF…',
        () async {
          // Pré-charge les fonts sur l'isolate principal (rootBundle).
          final fonts = await ContratBailPdfBuilder.loadFontBytes();
          // Construit + encode le PDF dans un isolate séparé pour ne pas
          // bloquer l'UI pendant 5-30 secondes.
          final pdfBytes = await Isolate.run<Uint8List>(() async {
            final doc = await ContratBailPdfBuilder.build(
              bail: bail,
              bailleur: bailleur,
              logement: logement,
              locataires: locataires,
              diagnostics: diagnostics,
              preloadedFonts: fonts,
            );
            return doc.save();
          });

          final docs = await getApplicationDocumentsDirectory();
          final dir = Directory('${docs.path}/contrats_bail');
          if (!await dir.exists()) await dir.create(recursive: true);
          final safeRef =
              bail.reference.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_');
          final pdfFile = File('${dir.path}/$safeRef.pdf');
          await pdfFile.writeAsBytes(pdfBytes, flush: true);

          bail.pdfPath = pdfFile.path;
          if (bail.statut == BailStatus.brouillon &&
              bail.signatureBailleurPng != null) {
            bail.statut = BailStatus.signe;
          }
          return pdfBytes;
        },
      );
    } catch (e, st) {
      debugPrint('ContratBail PDF generation failed: $e\n$st');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur génération PDF : $e')),
      );
      return;
    }
    if (!context.mounted) return;
    await context.read<ContratBailService>().save(bail);
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BailPdfPreviewScreen(
          bytes: bytes,
          filename: '${bail.reference}.pdf',
          title: bail.reference,
        ),
      ),
    );
  }

  Future<void> _openPdf(BuildContext context, String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fichier PDF introuvable.')),
      );
      return;
    }
    final bytes = await _withLoading<Uint8List>(
      context,
      'Ouverture du PDF…',
      () => file.readAsBytes(),
    );
    if (!context.mounted) return;
    final filename = path.split(Platform.pathSeparator).last;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BailPdfPreviewScreen(
          bytes: bytes,
          filename: filename,
          title: filename.replaceAll('.pdf', ''),
        ),
      ),
    );
  }

  Future<void> _generateAnnexesPdf(
    BuildContext context,
    ContratBail bail,
    dynamic logement,
    List<Locataire> locataires,
  ) async {
    // Verrou dur : un bail incomplet ne doit jamais générer d'annexes.
    final problemes = ContratBailValidation.validateFull(
      bail,
      logement: logement is Logement ? logement : null,
      diagnostics:
          context.read<DiagnosticService>().forLogement(bail.logementId),
    );
    if (problemes.isNotEmpty) {
      await _showBailIncompletDialog(context, problemes);
      return;
    }
    final bailleur =
        LocalDatabase.userBox.get(AppConstants.userProfileKey);
    if (bailleur == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil bailleur manquant.')),
      );
      return;
    }
    final diagnostics = context
        .read<DiagnosticService>()
        .forLogement(bail.logementId)
        .toList();

    Uint8List bytes;
    try {
      bytes = await _withLoading<Uint8List>(
        context,
        'Génération des annexes PDF…',
        () async {
          final fonts = await ContratBailAnnexesPdfBuilder.loadFontBytes();
          final pdfBytes = await Isolate.run<Uint8List>(() async {
            final doc = await ContratBailAnnexesPdfBuilder.build(
              bail: bail,
              bailleur: bailleur,
              logement: logement,
              locataires: locataires,
              diagnostics: diagnostics,
              preloadedFonts: fonts,
            );
            return doc.save();
          });
          final docs = await getApplicationDocumentsDirectory();
          final dir = Directory('${docs.path}/contrats_bail');
          if (!await dir.exists()) await dir.create(recursive: true);
          final safeRef =
              bail.reference.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_');
          final file = File('${dir.path}/${safeRef}_ANNEXES.pdf');
          await file.writeAsBytes(pdfBytes, flush: true);
          return pdfBytes;
        },
      );
    } catch (e, st) {
      debugPrint('Annexes PDF generation failed: $e\n$st');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur génération annexes : $e')),
      );
      return;
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BailPdfPreviewScreen(
          bytes: bytes,
          filename: '${bail.reference}_ANNEXES.pdf',
          title: 'Annexes - ${bail.reference}',
        ),
      ),
    );
  }
}

/// Affiche un loader plein écran pendant l'exécution de [task] et le ferme
/// quand la future se termine — évite que l'UI ait l'air figée pendant la
/// génération du PDF (qui peut prendre plusieurs secondes).
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

/// Aperçu plein écran du PDF d'un bail, avec boutons Partager / Imprimer.
class _BailPdfPreviewScreen extends StatelessWidget {
  final List<int> bytes;
  final String filename;
  final String title;
  const _BailPdfPreviewScreen({
    required this.bytes,
    required this.filename,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final data = Uint8List.fromList(bytes);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Partager',
            onPressed: () => Printing.sharePdf(bytes: data, filename: filename),
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimer',
            onPressed: () => Printing.layoutPdf(
              name: filename,
              onLayout: (_) async => data,
            ),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => data,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowSharing: false,
        allowPrinting: false,
        pdfFileName: filename,
        previewPageMargin: const EdgeInsets.all(8),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ContratBail bail;
  const _Header({required this.bail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_outlined,
              color: AppColors.primary, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bail.type.label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'Réf. ${bail.reference}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    bail.statut.label,
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

Widget _kv(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

class _SignatureRow extends StatelessWidget {
  final String label;
  final bool signed;
  final VoidCallback onSign;
  const _SignatureRow({
    required this.label,
    required this.signed,
    required this.onSign,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.dividerColor),
      ),
      child: Row(
        children: [
          Icon(
            signed ? Icons.check_circle : Icons.draw_outlined,
            color: signed ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              signed ? '$label : signée' : label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: onSign,
            child: Text(signed ? 'Re-signer' : 'Signer'),
          ),
        ],
      ),
    );
  }
}
