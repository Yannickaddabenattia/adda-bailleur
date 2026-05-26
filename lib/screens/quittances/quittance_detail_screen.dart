import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/pdf/quittance_pdf.dart';
import '../../core/theme/app_theme.dart';
import '../../models/quittance.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/quittance_service.dart';
import '../../services/user_service.dart';
import 'quittance_edit_screen.dart';

class QuittanceDetailScreen extends StatelessWidget {
  final String quittanceId;
  const QuittanceDetailScreen({super.key, required this.quittanceId});

  @override
  Widget build(BuildContext context) {
    final q = context.watch<QuittanceService>().byId(quittanceId);
    if (q == null) {
      return const Scaffold(
        body: Center(child: Text('Quittance introuvable.')),
      );
    }
    final bailleur = context.watch<UserService>().current;
    final logement = context.watch<LogementService>().byId(q.logementId);
    final locataireService = context.watch<LocataireService>();
    final locataire = locataireService.byId(q.locataireId);
    final colocataires = locataire == null
        ? const []
        : locataireService
            .byLogement(q.logementId)
            .where((l) => l.id != locataire.id && !l.isArchived && !l.isFutur)
            .toList();

    if (bailleur == null || logement == null || locataire == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Quittance ${q.periodLabel}')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Données incomplètes : logement ou locataire supprimé.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final filename = _filename(q, locataire.fullName);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          q.periodLabel[0].toUpperCase() + q.periodLabel.substring(1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Partager',
            onPressed: () async {
              final doc = await QuittancePdfBuilder.build(
                quittance: q,
                bailleur: bailleur,
                logement: logement,
                locataire: locataire,
                colocataires: colocataires.cast(),
                bailleurNameOverride: q.bailleurName,
                bailleurEmailOverride: q.bailleurEmail,
              );
              await Printing.sharePdf(
                bytes: await doc.save(),
                filename: filename,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimer',
            onPressed: () async {
              await Printing.layoutPdf(
                name: filename,
                onLayout: (format) async {
                  final doc = await QuittancePdfBuilder.build(
                    quittance: q,
                    bailleur: bailleur,
                    logement: logement,
                    locataire: locataire,
                    colocataires: colocataires.cast(),
                    bailleurNameOverride: q.bailleurName,
                    bailleurEmailOverride: q.bailleurEmail,
                  );
                  return doc.save();
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Modifier',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => QuittanceEditScreen(quittanceId: q.id),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer',
            onPressed: () => _confirmDelete(context, q),
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) async {
          final doc = await QuittancePdfBuilder.build(
            quittance: q,
            bailleur: bailleur,
            logement: logement,
            locataire: locataire,
            colocataires: colocataires.cast(),
            bailleurNameOverride: q.bailleurName,
            bailleurEmailOverride: q.bailleurEmail,
          );
          return doc.save();
        },
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: filename,
        previewPageMargin: const EdgeInsets.all(8),
      ),
      bottomNavigationBar: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${NumberFormat.currency(locale: 'fr_FR', symbol: '€').format(q.total)} · ${locataire.fullName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(
                q.verifyIntegrity()
                    ? Icons.verified_outlined
                    : Icons.warning_amber_outlined,
                color: q.verifyIntegrity()
                    ? AppColors.success
                    : AppColors.error,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                q.verifyIntegrity() ? 'Intégrité OK' : 'Hash altéré',
                style: TextStyle(
                  fontSize: 11,
                  color: q.verifyIntegrity()
                      ? AppColors.success
                      : AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _filename(Quittance q, String locataireName) {
    final safe = locataireName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final period = '${q.periodYear}-${q.periodMonth.toString().padLeft(2, '0')}';
    return 'quittance_${period}_$safe.pdf';
  }

  void _confirmDelete(BuildContext context, Quittance q) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette quittance ?'),
        content: const Text(
          'Cette quittance sera définitivement supprimée de vos documents.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () async {
              await context.read<QuittanceService>().delete(q.id);
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
