import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/plan_logement.dart';
import '../../../services/plan_logement_service.dart';

/// Affiche les photos d'un mur d'une pièce, avec en surimpression le nom de la
/// pièce, le numéro du mur (M1, M2…) au moment de la prise et la date+heure.
class WallPhotosScreen extends StatelessWidget {
  final String planId;
  final String roomId;

  /// 'top' | 'right' | 'bottom' | 'left' (rectangle) ou 'edge' (polygone).
  final String side;
  final String title;

  /// Index d'arête pour les pièces polygonales. Null pour rectangles.
  final int? edgeIndex;

  /// Quand vrai, l'utilisateur peut supprimer une photo. Désactivé en
  /// lecture seule (depuis l'EDL).
  final bool canDelete;

  /// Si fourni, n'affiche que les photos rattachées à cet EDL.
  final String? etatId;

  /// Si fourni, ne montre que les photos d'un mur libre spécifique.
  /// Prend la priorité sur le filtrage `roomId/side`.
  final String? freeWallId;

  const WallPhotosScreen({
    super.key,
    required this.planId,
    required this.roomId,
    required this.side,
    required this.title,
    this.edgeIndex,
    this.canDelete = true,
    this.etatId,
    this.freeWallId,
  });

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<PlanLogementService>();
    final plan = svc.byId(planId);
    final photos = (plan?.wallPhotos ?? <WallPhoto>[])
        .where((p) {
          if (etatId != null && p.etatId != etatId) return false;
          if (freeWallId != null) return p.freeWallId == freeWallId;
          return p.roomId == roomId &&
              (edgeIndex != null
                  ? p.edgeIndex == edgeIndex
                  : p.side == side);
        })
        .toList()
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: photos.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (ctx, i) => _PhotoCard(
                photo: photos[i],
                canDelete: canDelete,
                onDelete: canDelete
                    ? () => _confirmDelete(context, plan!, photos[i])
                    : null,
                onTap: () => _openFullscreen(context, photos[i]),
              ),
            ),
    );
  }

  void _openFullscreen(BuildContext context, WallPhoto photo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WallPhotoFullscreenScreen(photo: photo),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, PlanLogement plan, WallPhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la photo ?'),
        content: const Text('Cette action est définitive.'),
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
    if (!context.mounted) return;
    final svc = context.read<PlanLogementService>();
    await svc.deleteWallPhoto(photo);
    plan.wallPhotos.removeWhere((p) => p.id == photo.id);
    await svc.save(plan);
  }
}

class _PhotoCard extends StatelessWidget {
  final WallPhoto photo;
  final bool canDelete;
  final VoidCallback? onDelete;
  final VoidCallback onTap;
  const _PhotoCard({
    required this.photo,
    required this.canDelete,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy HH:mm', 'fr_FR');
    final localDate = photo.takenAt.toLocal();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(photo.path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFFEEF2F7),
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined,
                          color: AppColors.textSecondary),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${photo.roomName} · ${photo.label}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        df.format(localDate),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (canDelete && onDelete != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Supprimer'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                  onPressed: onDelete,
                ),
              ),
          ],
        ),
      ),
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
              Icons.photo_camera_outlined,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Aucune photo pour ce mur',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 4),
            const Text(
              'Faites un appui long sur le numéro du mur pour ajouter une photo.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class WallPhotoFullscreenScreen extends StatelessWidget {
  final WallPhoto photo;
  const WallPhotoFullscreenScreen({super.key, required this.photo});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy HH:mm', 'fr_FR');
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${photo.roomName} · ${photo.label}'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image.file(
                  File(photo.path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text(
                      'Image illisible.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                df.format(photo.takenAt.toLocal()),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
