import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/templates/edl_templates.dart';
import '../../core/theme/app_theme.dart';
import '../../models/etat_des_lieux.dart';
import '../../models/piece.dart';
import '../../models/plan_logement.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../services/plan_logement_service.dart';
import '../../widgets/primary_button.dart';
import '../logements/plans/logement_plans_screen.dart';
import '../logements/plans/plan_editor_screen.dart';
import '../logements/plans/wall_photos_screen.dart';
import 'edl_metadata_screen.dart';
import 'piece_edit_screen.dart';
import 'signature_screen.dart';

class EtatDesLieuxEditScreen extends StatelessWidget {
  final String edlId;
  const EtatDesLieuxEditScreen({super.key, required this.edlId});

  @override
  Widget build(BuildContext context) {
    final edl = context.watch<EtatDesLieuxService>().byId(edlId);
    if (edl == null) {
      return const Scaffold(body: Center(child: Text('EDL introuvable.')));
    }
    final plans =
        context.watch<PlanLogementService>().byLogement(edl.logementId);

    return Scaffold(
      appBar: AppBar(
        title: Text(edl.titre),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_home_outlined),
            tooltip: 'Ajouter une pièce',
            onPressed: () => _addPiece(context, edl),
          ),
        ],
      ),
      body: Column(
        children: [
          _PlansBanner(
            logementId: edl.logementId,
            etatId: edl.id,
            plans: plans,
          ),
          if (plans
              .any((p) => p.wallPhotos.any((w) => w.etatId == edl.id)))
            _WallPhotosBanner(plans: plans, etatId: edl.id),
          _MetadataBanner(edl: edl),
          Expanded(
            child: edl.pieces.isEmpty
                ? _empty(context)
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    buildDefaultDragHandles: false,
                    itemCount: edl.pieces.length,
                    onReorder: (oldIndex, newIndex) async {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final piece = edl.pieces.removeAt(oldIndex);
                      edl.pieces.insert(newIndex, piece);
                      await context.read<EtatDesLieuxService>().save(edl);
                    },
                    itemBuilder: (ctx, i) {
                      final p = edl.pieces[i];
                      return _PieceTile(
                        key: ValueKey(p.id),
                        index: i,
                        piece: p,
                        onTap: () => Navigator.of(ctx).push(
                          MaterialPageRoute(
                            builder: (_) => PieceEditScreen(
                              edlId: edl.id,
                              pieceId: p.id,
                            ),
                          ),
                        ),
                        onDelete: () => _confirmDeletePiece(context, edl, p),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: AppColors.divider),
              ),
            ),
            child: PrimaryButton(
              label: 'Signer et générer le code',
              icon: Icons.edit_note,
              onPressed: edl.pieces.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SignatureScreen(edlId: edl.id),
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_outlined,
                size: 64,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'Aucune pièce',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ajoutez des pièces à l\'aide du bouton en haut à droite.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPiece(BuildContext context, EtatDesLieux edl) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Nom de la pièce',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: 360,
                child: ListView(
                  children: [
                    ...EdlTemplates.suggestedPieceNames.map(
                      (name) => ListTile(
                        title: Text(name),
                        onTap: () => Navigator.of(ctx).pop(name),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Autre (saisir)'),
                      onTap: () async {
                        final custom = await _askCustomName(ctx);
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop(custom);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || selected.trim().isEmpty) return;
    edl.pieces.add(Piece.create(nom: selected));
    if (!context.mounted) return;
    await context.read<EtatDesLieuxService>().save(edl);
  }

  Future<String?> _askCustomName(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nom personnalisé'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex: Véranda'),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePiece(
      BuildContext context, EtatDesLieux edl, Piece piece) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer « ${piece.nom} » ?'),
        content: const Text(
          'La pièce et tous ses éléments seront supprimés de cet état des lieux.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () async {
              edl.pieces.removeWhere((p) => p.id == piece.id);
              await context.read<EtatDesLieuxService>().save(edl);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _PlansBanner extends StatelessWidget {
  final String logementId;
  final String etatId;
  final List<PlanLogement> plans;
  const _PlansBanner({
    required this.logementId,
    required this.etatId,
    required this.plans,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const Icon(Icons.architecture_outlined,
              size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: plans.isEmpty
                ? const Text(
                    'Aucun plan associé à ce logement.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  )
                : SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: plans.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (ctx, i) {
                        final p = plans[i];
                        final n = p.annotations.length;
                        return ActionChip(
                          avatar: Icon(
                            switch (p.kind) {
                              PlanKind.niveau => Icons.layers_outlined,
                              PlanKind.dependance =>
                                Icons.house_siding_outlined,
                              PlanKind.terrain => Icons.grass_outlined,
                            },
                            size: 16,
                            color: AppColors.primary,
                          ),
                          label:
                              Text(n == 0 ? p.name : '${p.name} · $n repère${n > 1 ? 's' : ''}'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlanEditorScreen(
                                planId: p.id,
                                readOnly: true,
                                allowWallPhotoCapture: true,
                                etatId: etatId,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.tune, size: 18),
            label: Text(plans.isEmpty ? 'Ajouter' : 'Gérer'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    LogementPlansScreen(logementId: logementId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PieceTile extends StatelessWidget {
  final int index;
  final Piece piece;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _PieceTile({
    super.key,
    required this.index,
    required this.piece,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey(piece.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                child: Icon(Icons.drag_handle,
                    color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        piece.nom,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${piece.elements.length} élément(s)',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.textSecondary),
              onPressed: onDelete,
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pellicule horizontale des photos de murs collectées sur les plans du
/// logement. Tap → ouverture en lecture seule de la liste détaillée pour
/// le mur correspondant.
class _WallPhotosBanner extends StatelessWidget {
  final List<PlanLogement> plans;
  final String etatId;
  const _WallPhotosBanner({required this.plans, required this.etatId});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy HH:mm', 'fr_FR');
    final entries = <_WallPhotoEntry>[];
    for (final plan in plans) {
      for (final photo in plan.wallPhotos) {
        if (photo.etatId != etatId) continue;
        entries.add(_WallPhotoEntry(plan: plan, photo: photo));
      }
    }
    entries.sort((a, b) => a.photo.takenAt.compareTo(b.photo.takenAt));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Row(
              children: [
                const Icon(Icons.photo_library_outlined,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'Photos des murs (${entries.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final e = entries[i];
                return _WallPhotoThumb(
                  entry: e,
                  formattedDate: df.format(e.photo.takenAt.toLocal()),
                  onTap: () => Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => WallPhotosScreen(
                        planId: e.plan.id,
                        roomId: e.photo.roomId,
                        side: e.photo.side,
                        edgeIndex: e.photo.edgeIndex,
                        title:
                            '${e.photo.roomName} · ${e.photo.label}',
                        canDelete: false,
                        etatId: etatId,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WallPhotoEntry {
  final PlanLogement plan;
  final WallPhoto photo;
  _WallPhotoEntry({required this.plan, required this.photo});
}

class _WallPhotoThumb extends StatelessWidget {
  final _WallPhotoEntry entry;
  final String formattedDate;
  final VoidCallback onTap;
  const _WallPhotoThumb({
    required this.entry,
    required this.formattedDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(entry.photo.path),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFFEEF2F7),
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined,
                    color: AppColors.textSecondary),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${entry.photo.roomName} · ${entry.photo.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      formattedDate,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau récapitulatif des métadonnées ALUR (adresse bailleur, clés,
/// relevés compteurs). Tap → écran d'édition dédié.
class _MetadataBanner extends StatelessWidget {
  final EtatDesLieux edl;
  const _MetadataBanner({required this.edl});

  @override
  Widget build(BuildContext context) {
    final missing = <String>[];
    if (edl.bailleurAdresse == null || edl.bailleurAdresse!.trim().isEmpty) {
      missing.add('adresse bailleur');
    }
    if (edl.nombreCles == null) missing.add('clés');
    final releves = [
      edl.releveCompteurGaz,
      edl.releveCompteurEauChaude,
      edl.releveCompteurEauFroide,
      edl.releveCompteurElecJour,
      edl.releveCompteurElecNuit,
    ].where((v) => v != null && v.trim().isNotEmpty).length;
    if (releves == 0) missing.add('relevés');

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EdlMetadataScreen(edlId: edl.id),
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: missing.isEmpty
              ? AppColors.success.withValues(alpha: 0.06)
              : AppColors.accent.withValues(alpha: 0.08),
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Icon(
              missing.isEmpty
                  ? Icons.task_alt_outlined
                  : Icons.assignment_outlined,
              size: 20,
              color: missing.isEmpty ? AppColors.success : AppColors.accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Détails et compteurs',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    missing.isEmpty
                        ? 'Adresse bailleur, clés et $releves relevé(s) renseignés.'
                        : 'À renseigner : ${missing.join(', ')}.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
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
