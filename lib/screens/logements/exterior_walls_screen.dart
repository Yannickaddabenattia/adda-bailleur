import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/storage/photo_watermark.dart';
import '../../core/theme/app_theme.dart';
import '../../models/logement.dart';
import '../../models/plan_logement.dart';
import '../../services/plan_logement_service.dart';

/// Écran dédié aux **photos de murs / façades extérieurs** du logement.
/// Stockées dans le même `PlanLogement.wallPhotos` que les murs intérieurs,
/// avec le flag `isExterior=true`. Si aucun plan n'existe, on en crée un
/// virtuel "Extérieur" à la première photo.
class ExteriorWallsScreen extends StatefulWidget {
  final Logement logement;
  const ExteriorWallsScreen({super.key, required this.logement});

  @override
  State<ExteriorWallsScreen> createState() => _ExteriorWallsScreenState();
}

class _ExteriorWallsScreenState extends State<ExteriorWallsScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<PlanLogementService>();
    final plans = svc.byLogement(widget.logement.id);
    final photos = <WallPhoto>[];
    for (final p in plans) {
      photos.addAll(p.wallPhotos.where((w) => w.isExterior));
    }
    photos.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    final df = DateFormat('dd MMM yyyy HH:mm', 'fr_FR');

    return Scaffold(
      appBar: AppBar(title: const Text('Murs / façades extérieurs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addPhoto,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Ajouter une photo'),
      ),
      body: photos.isEmpty
          ? const _Empty()
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: photos.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemBuilder: (ctx, i) {
                final p = photos[i];
                return _PhotoTile(
                  photo: p,
                  dateFmt: df,
                  onRename: () => _rename(p),
                  onDelete: () => _delete(p),
                );
              },
            ),
    );
  }

  Future<void> _addPhoto() async {
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
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: source,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (xfile == null) return;

    if (!mounted) return;
    final label = await _askLabel(initial: 'Façade');
    if (label == null) return;

    setState(() => _busy = true);
    try {
      final svc = context.read<PlanLogementService>();
      var plans = svc.byLogement(widget.logement.id);
      PlanLogement target;
      if (plans.isEmpty) {
        target = PlanLogement.create(
          logementId: widget.logement.id,
          kind: PlanKind.niveau,
          name: 'Extérieur',
        );
        await svc.save(target);
      } else {
        target = plans.first;
      }
      final photoId = const Uuid().v4();
      final stored = await svc.persistWallPhoto(
        source: File(xfile.path),
        planId: target.id,
        photoId: photoId,
        extension: 'jpg',
      );
      final takenAt = DateTime.now().toUtc();
      try {
        await PhotoWatermark.stampInPlace(
          File(stored),
          at: takenAt,
          label: label,
        );
      } catch (_) {}
      final photo = WallPhoto.create(
        roomId: '__exterior__',
        side: 'exterior',
        wallNumber: 0,
        roomName: label,
        path: stored,
        isExterior: true,
      );
      // takenAt n'est pas modifiable via create() — mais l'incrustation
      // utilise un horodatage cohérent (juste au-dessus).
      target.wallPhotos.add(photo);
      await svc.save(target);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askLabel({required String initial}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Étiquette de la photo'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Libellé',
            helperText: 'Ex : Façade nord, Pignon ouest, Toiture, Cour…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(WallPhoto p) async {
    final newLabel = await _askLabel(initial: p.roomName);
    if (newLabel == null || newLabel.isEmpty) return;
    final svc = context.read<PlanLogementService>();
    for (final plan in svc.byLogement(widget.logement.id)) {
      final idx = plan.wallPhotos.indexWhere((w) => w.id == p.id);
      if (idx >= 0) {
        plan.wallPhotos[idx].roomName = newLabel;
        await svc.save(plan);
        break;
      }
    }
  }

  Future<void> _delete(WallPhoto p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la photo ?'),
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
    final svc = context.read<PlanLogementService>();
    await svc.deleteWallPhoto(p);
    for (final plan in svc.byLogement(widget.logement.id)) {
      plan.wallPhotos.removeWhere((w) => w.id == p.id);
      await svc.save(plan);
    }
  }
}

class _PhotoTile extends StatelessWidget {
  final WallPhoto photo;
  final DateFormat dateFmt;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _PhotoTile({
    required this.photo,
    required this.dateFmt,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(photo.path);
    final exists = file.existsSync();
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dividerColor),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: exists
                ? Image.file(file, fit: BoxFit.cover)
                : Container(
                    color: context.dividerColor,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined,
                        color: AppColors.textSecondary),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  photo.roomName,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  dateFmt.format(photo.takenAt.toLocal()),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: onRename,
                      icon: const Icon(Icons.edit, size: 14),
                      label: const Text('Renommer',
                          style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 28),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.error, size: 18),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      tooltip: 'Supprimer',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
          children: const [
            Icon(Icons.house_outlined,
                size: 64, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text('Aucune photo extérieure',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
              'Photographie les façades, le toit, la cour, le jardin — '
              'chaque cliché est horodaté et nommé. Utile pour documenter '
              'l\'état général à l\'entrée et à la sortie.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

