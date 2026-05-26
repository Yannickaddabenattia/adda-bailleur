import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/storage/photo_storage.dart';
import '../../core/storage/photo_watermark.dart';
import '../../core/theme/app_theme.dart';
import '../../models/element_piece.dart';
import '../../models/etat_element.dart';
import '../../models/plan_logement.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../services/plan_logement_service.dart';
import '../logements/plans/wall_photos_screen.dart';

class PieceEditScreen extends StatelessWidget {
  final String edlId;
  final String pieceId;
  const PieceEditScreen({
    super.key,
    required this.edlId,
    required this.pieceId,
  });

  @override
  Widget build(BuildContext context) {
    final edl = context.watch<EtatDesLieuxService>().byId(edlId);
    final piece = edl?.pieces.where((p) => p.id == pieceId).firstOrNull;
    if (edl == null || piece == null) {
      return const Scaffold(body: Center(child: Text('Pièce introuvable.')));
    }

    final wallPhotos = _wallPhotosForPiece(
      context.watch<PlanLogementService>(),
      logementId: edl.logementId,
      pieceName: piece.nom,
      etatId: edl.id,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(piece.nom),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Ajouter un élément',
            onPressed: () => _addElement(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (wallPhotos.isNotEmpty) ...[
            _WallPhotosStrip(
              photos: wallPhotos,
              onDelete: (photo) => _confirmDeleteWallPhoto(context, photo),
            ),
            const SizedBox(height: 16),
          ],
          if (piece.elements.isEmpty)
            _empty(context)
          else
            ...List.generate(piece.elements.length, (i) {
              return Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                child: _ElementCard(
                  element: piece.elements[i],
                  onEtatChange: (etat) async {
                    piece.elements[i].etat = etat;
                    await context.read<EtatDesLieuxService>().save(edl);
                  },
                  onDescriptionChange: (desc) async {
                    piece.elements[i].description = desc;
                    await context.read<EtatDesLieuxService>().save(edl);
                  },
                  onAddPhoto: () async {
                    await _addPhoto(context, i);
                  },
                  onRemovePhoto: (path) async {
                    final el = piece.elements[i];
                    final idx = el.photoPaths.indexOf(path);
                    if (idx >= 0) {
                      el.photoPaths.removeAt(idx);
                      if (idx < el.photoCapturedAt.length) {
                        el.photoCapturedAt.removeAt(idx);
                      }
                    }
                    await PhotoStorage.deleteImage(path);
                    if (!context.mounted) return;
                    await context.read<EtatDesLieuxService>().save(edl);
                  },
                  onRename: () => _renameElement(context, i),
                  onDelete: () => _confirmDeleteElement(context, i),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteWallPhoto(
      BuildContext context, WallPhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la photo ?'),
        content: const Text(
          'La photo sera retirée du plan et de l\'état des lieux. Cette action est définitive.',
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
    if (ok != true || !context.mounted) return;
    final svc = context.read<PlanLogementService>();
    final plan = svc
        .all()
        .firstWhere((p) => p.wallPhotos.any((w) => w.id == photo.id));
    await svc.deleteWallPhoto(photo);
    plan.wallPhotos.removeWhere((p) => p.id == photo.id);
    await svc.save(plan);
  }

  List<WallPhoto> _wallPhotosForPiece(
    PlanLogementService planService, {
    required String logementId,
    required String pieceName,
    required String etatId,
  }) {
    final norm = pieceName.trim().toLowerCase();
    final plans = planService.byLogement(logementId);
    final out = <WallPhoto>[];
    for (final plan in plans) {
      for (final p in plan.wallPhotos) {
        if (p.roomName.trim().toLowerCase() == norm && p.etatId == etatId) {
          out.add(p);
        }
      }
    }
    out.sort((a, b) {
      final c = a.wallNumber.compareTo(b.wallNumber);
      if (c != 0) return c;
      return a.takenAt.compareTo(b.takenAt);
    });
    return out;
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.checklist_rtl_outlined,
                size: 64,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'Aucun élément',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ajoutez des éléments à inspecter (sols, évier, prises…).',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addElement(BuildContext context) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvel élément'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex: Interrupteur'),
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
    if (name == null || name.isEmpty) return;
    if (!context.mounted) return;
    final service = context.read<EtatDesLieuxService>();
    final edl = service.byId(edlId)!;
    final piece = edl.pieces.firstWhere((p) => p.id == pieceId);
    piece.elements.add(ElementPiece.create(nom: name));
    await service.save(edl);
  }

  Future<void> _renameElement(BuildContext context, int index) async {
    final service = context.read<EtatDesLieuxService>();
    final edl = service.byId(edlId)!;
    final piece = edl.pieces.firstWhere((p) => p.id == pieceId);
    final ctrl = TextEditingController(text: piece.elements[index].nom);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer l\'élément'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    piece.elements[index].nom = name;
    await service.save(edl);
  }

  void _confirmDeleteElement(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer l\'élément ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () async {
              final service = context.read<EtatDesLieuxService>();
              final edl = service.byId(edlId)!;
              final piece = edl.pieces.firstWhere((p) => p.id == pieceId);
              final removed = piece.elements.removeAt(index);
              for (final p in removed.photoPaths) {
                await PhotoStorage.deleteImage(p);
              }
              await service.save(edl);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  Future<void> _addPhoto(BuildContext context, int elementIndex) async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir depuis la galerie'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final xfile = await picker.pickImage(
      source: source,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (xfile == null) return;
    if (!context.mounted) return;
    final service = context.read<EtatDesLieuxService>();
    final edl = service.byId(edlId)!;
    final piece = edl.pieces.firstWhere((p) => p.id == pieceId);
    final element = piece.elements[elementIndex];
    final storedPath = await PhotoStorage.saveImage(
      etatId: edl.id,
      sourcePath: xfile.path,
    );
    final capturedAt = DateTime.now().toUtc();
    try {
      await PhotoWatermark.stampInPlace(
        File(storedPath),
        at: capturedAt,
        label: '${piece.nom} · ${element.nom}',
      );
    } catch (_) {
      // En cas d'échec de l'incrustation, on garde la photo brute plutôt que
      // de bloquer l'utilisateur ; la date+heure reste enregistrée dans le
      // modèle via photoCapturedAt.
    }
    element.photoPaths.add(storedPath);
    element.photoCapturedAt.add(capturedAt.toIso8601String());
    await service.save(edl);
  }
}

class _ElementCard extends StatelessWidget {
  final ElementPiece element;
  final ValueChanged<EtatElement> onEtatChange;
  final ValueChanged<String> onDescriptionChange;
  final VoidCallback onAddPhoto;
  final ValueChanged<String> onRemovePhoto;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ElementCard({
    required this.element,
    required this.onEtatChange,
    required this.onDescriptionChange,
    required this.onAddPhoto,
    required this.onRemovePhoto,
    required this.onRename,
    required this.onDelete,
  });

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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  element.nom,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: onRename,
                tooltip: 'Renommer',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete,
                tooltip: 'Supprimer',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: EtatElement.values.map((e) {
              final selected = element.etat == e;
              final color = _colorFor(e);
              return ChoiceChip(
                label: Text(e.label),
                selected: selected,
                onSelected: (_) => onEtatChange(e),
                selectedColor: color.withValues(alpha: 0.18),
                labelStyle: TextStyle(
                  color: selected ? color : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected ? color : AppColors.divider,
                ),
                backgroundColor: AppColors.surface,
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: element.description,
            onChanged: onDescriptionChange,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Détails (facultatif)',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...element.photoPaths.map(
                  (path) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(path),
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 90,
                              height: 90,
                              color: AppColors.divider,
                              child: const Icon(Icons.broken_image,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: InkWell(
                            onTap: () => onRemovePhoto(path),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  onTap: onAddPhoto,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.divider,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: const Icon(
                      Icons.add_a_photo_outlined,
                      color: AppColors.primary,
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

class _WallPhotosStrip extends StatelessWidget {
  final List<WallPhoto> photos;
  final ValueChanged<WallPhoto> onDelete;
  const _WallPhotosStrip({required this.photos, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.architecture_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'Photos des murs (depuis le plan) · ${photos.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) => _WallPhotoThumb(
                photo: photos[i],
                onDelete: () => onDelete(photos[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WallPhotoThumb extends StatelessWidget {
  final WallPhoto photo;
  final VoidCallback onDelete;
  const _WallPhotoThumb({required this.photo, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WallPhotoFullscreenScreen(photo: photo),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Image.file(
                      File(photo.path),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 96,
                        height: 96,
                        color: AppColors.divider,
                        child: const Icon(Icons.broken_image,
                            color: AppColors.textSecondary),
                      ),
                    ),
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          photo.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
