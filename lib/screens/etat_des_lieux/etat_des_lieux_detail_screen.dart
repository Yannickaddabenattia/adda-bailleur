import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/pdf/etat_des_lieux_pdf.dart';
import '../../core/theme/app_theme.dart';
import '../../models/element_piece.dart';
import '../../models/etat_des_lieux.dart';
import '../../models/etat_element.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/user_profile.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/user_service.dart';
import 'etat_des_lieux_edit_screen.dart';
import 'locataire_code_screen.dart';

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
              icon: const Icon(Icons.key_outlined),
              tooltip: 'Afficher le code',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LocataireCodeScreen(
                    edlId: edlId,
                    code: edl.locataireCode!,
                  ),
                ),
              ),
            ),
          if (canExport)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Partager le PDF',
              onPressed: () => _sharePdf(
                context,
                edl: edl,
                bailleur: bailleur,
                logement: logement,
                locataire: locataire,
              ),
            ),
          if (canExport)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Imprimer',
              onPressed: () => _printPdf(
                edl: edl,
                bailleur: bailleur,
                logement: logement,
                locataire: locataire,
              ),
            ),
          if (!edl.isFinalized)
            IconButton(
              icon: const Icon(Icons.delete_outline),
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

  Future<void> _sharePdf(
    BuildContext context, {
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Logement logement,
    required Locataire locataire,
  }) async {
    final doc = await EtatDesLieuxPdfBuilder.build(
      edl: edl,
      bailleur: bailleur,
      logement: logement,
      locataire: locataire,
    );
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: _pdfFilename(edl, locataire),
    );
  }

  Future<void> _printPdf({
    required EtatDesLieux edl,
    required UserProfile bailleur,
    required Logement logement,
    required Locataire locataire,
  }) async {
    await Printing.layoutPdf(
      name: _pdfFilename(edl, locataire),
      onLayout: (format) async {
        final doc = await EtatDesLieuxPdfBuilder.build(
          edl: edl,
          bailleur: bailleur,
          logement: logement,
          locataire: locataire,
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
        content: const Text(
          'Cet état des lieux et toutes ses photos seront supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () async {
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
