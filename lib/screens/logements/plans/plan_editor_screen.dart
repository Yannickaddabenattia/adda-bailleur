import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/photo_watermark.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/plan_logement.dart';
import '../../../services/logement_service.dart';
import '../../../services/plan_logement_service.dart';
import 'wall_photos_screen.dart';

/// Éditeur d'un plan : soit image importée (visualisation), soit dessin
/// vectoriel (palette de pièces glissables sur grille, redimensionnement).
class PlanEditorScreen extends StatefulWidget {
  final String planId;

  /// Quand vrai, le plan est consultable mais non modifiable :
  /// pas de palette, pas de drag, pas de poignées, pas de suppression
  /// de mur. Utilisé depuis l'EDL pour empêcher les modifications par
  /// inadvertance pendant la visite.
  final bool readOnly;

  /// Quand vrai, autorise la prise de photo de mur (appui long sur le
  /// numéro M1/M2…) même en lecture seule. Utilisé depuis l'EDL où le
  /// propriétaire peut documenter les murs sans toucher au dessin.
  final bool allowWallPhotoCapture;

  /// Identifiant de l'EDL en cours quand l'éditeur est ouvert depuis un EDL.
  /// Toute photo de mur prise sera taguée avec cet etatId pour qu'elle ne
  /// réapparaisse que dans cet EDL (et soit effacée avec lui).
  final String? etatId;

  const PlanEditorScreen({
    super.key,
    required this.planId,
    this.readOnly = false,
    this.allowWallPhotoCapture = false,
    this.etatId,
  });

  @override
  State<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends State<PlanEditorScreen> {
  String? _selectedRoomId;
  bool _saving = false;
  late String _activePlanId;

  /// Pile d'historique pour undo/redo. Chaque entrée est un snapshot JSON
  /// du plan (toMap) — fromMap reconstruit ensuite l'objet avec ses listes
  /// indépendantes.
  final List<String> _history = [];
  int _historyIndex = -1;
  static const int _historyMax = 60;
  bool _restoring = false;

  /// RepaintBoundary pour capturer le canvas en image lors de l'export.
  final GlobalKey _canvasKey = GlobalKey();

  /// Clé permettant à la sidebar externe d'invoquer les actions du moteur.
  final GlobalKey<_DrawerViewState> _drawerKey =
      GlobalKey<_DrawerViewState>();

  bool get _shouldForceLandscape =>
      !widget.readOnly &&
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _activePlanId = widget.planId;
    if (_shouldForceLandscape) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    // Snapshot initial pour ancrer l'undo/redo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final plan = context.read<PlanLogementService>().byId(_activePlanId);
      if (plan != null && mounted) {
        _seedHistory(plan);
      }
    });
  }

  @override
  void dispose() {
    if (_shouldForceLandscape) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    super.dispose();
  }

  PlanLogement? _plan(BuildContext context) =>
      context.watch<PlanLogementService>().byId(_activePlanId);

  void _seedHistory(PlanLogement plan) {
    _history
      ..clear()
      ..add(jsonEncode(plan.toMap()));
    _historyIndex = 0;
  }

  void _pushHistory(PlanLogement plan) {
    if (_restoring) return;
    final snap = jsonEncode(plan.toMap());
    if (_history.isNotEmpty &&
        _historyIndex >= 0 &&
        _historyIndex < _history.length &&
        _history[_historyIndex] == snap) {
      return;
    }
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(snap);
    if (_history.length > _historyMax) {
      _history.removeAt(0);
    } else {
      _historyIndex = _history.length - 1;
    }
    _historyIndex = _history.length - 1;
  }

  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex >= 0 && _historyIndex < _history.length - 1;

  Future<void> _undo() async {
    if (!_canUndo) return;
    _historyIndex--;
    await _restoreFromHistory();
  }

  Future<void> _redo() async {
    if (!_canRedo) return;
    _historyIndex++;
    await _restoreFromHistory();
  }

  Future<void> _restoreFromHistory() async {
    final plan = context.read<PlanLogementService>().byId(_activePlanId);
    if (plan == null) return;
    final snap = PlanLogement.fromMap(
        jsonDecode(_history[_historyIndex]) as Map<String, dynamic>);
    _restoring = true;
    plan.imagePath = snap.imagePath;
    plan.rooms = snap.rooms;
    plan.annotations = snap.annotations;
    plan.wallPhotos = snap.wallPhotos;
    await context.read<PlanLogementService>().save(plan);
    _restoring = false;
    if (mounted) setState(() {});
  }

  Future<void> _save(PlanLogement plan) async {
    if (_saving) return;
    _saving = true;
    try {
      await context.read<PlanLogementService>().save(plan);
      _pushHistory(plan);
    } finally {
      _saving = false;
    }
  }

  Future<void> _exportCurrent(PlanLogement plan) async {
    final boundary = _canvasKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    try {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();
      final pdf = pw.Document();
      final memImage = pw.MemoryImage(pngBytes);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${plan.kind.label} · ${plan.name}',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(memImage, fit: pw.BoxFit.contain),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'ADDA Bailleur · ${plan.rooms.length} pièce(s)',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),
      );
      final fname = '${plan.kind.label}_${plan.name}'
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      await Printing.sharePdf(
          bytes: await pdf.save(), filename: '$fname.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export impossible : $e')),
        );
      }
    }
  }

  void _switchToPlan(PlanLogement other) {
    if (other.id == _activePlanId) return;
    setState(() {
      _activePlanId = other.id;
      _selectedRoomId = null;
      _seedHistory(other);
    });
  }

  Future<void> _importImage(PlanLogement plan) async {
    final source = await _askImageSource();
    if (source == null) return;
    File? file;
    String? ext;
    if (source == _ImageSource.fichier) {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'pdf', 'heic'],
      );
      if (res == null || res.files.single.path == null) return;
      file = File(res.files.single.path!);
      ext = res.files.single.extension;
    } else {
      final picker = ImagePicker();
      final XFile? x;
      if (source == _ImageSource.camera) {
        x = await picker.pickImage(
            source: ImageSource.camera, imageQuality: 85);
      } else {
        x = await picker.pickImage(
            source: ImageSource.gallery, imageQuality: 90);
      }
      if (x == null) return;
      file = File(x.path);
    }
    if (!mounted) return;
    final svc = context.read<PlanLogementService>();
    final dest = await svc.persistImportedFile(
      source: file,
      planId: plan.id,
      extension: ext,
    );
    plan.imagePath = dest;
    plan.rooms = []; // L'image remplace le dessin.
    await _save(plan);
    if (mounted) setState(() {});
  }

  Future<_ImageSource?> _askImageSource() async {
    return showModalBottomSheet<_ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(ctx).pop(_ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.of(ctx).pop(_ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Importer un fichier'),
              onTap: () => Navigator.of(ctx).pop(_ImageSource.fichier),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeImage(PlanLogement plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer l\'image ?'),
        content: const Text(
            'L\'image sera supprimée. Vous pourrez créer un dessin à la place.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    if (plan.imagePath != null) {
      try {
        await File(plan.imagePath!).delete();
      } catch (_) {}
    }
    plan.imagePath = null;
    await _save(plan);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan(context);
    if (plan == null) {
      return const Scaffold(
        body: Center(child: Text('Plan introuvable.')),
      );
    }

    final media = MediaQuery.of(context);
    final isCompactPhone = media.size.shortestSide < 600;
    final isPortrait = media.orientation == Orientation.portrait;
    final mustRotate =
        !widget.readOnly && isCompactPhone && isPortrait;

    final siblings = context
        .watch<PlanLogementService>()
        .byLogement(plan.logementId);

    // Stats : surface et nb de pièces saisis manuellement sur le logement.
    final logement = context.watch<LogementService>().byId(plan.logementId);
    final logementSurface = logement?.surface ?? 0;
    final logementPieces = logement?.nbPieces ?? 0;
    final selectedRoom = _findSelectedRoom(plan);

    // Sidebar visible si écran large + landscape + pas image + pas readonly
    final wideEnough = media.size.width >= 700;
    final showExternalSidebar = !mustRotate &&
        !plan.hasImage &&
        !widget.readOnly &&
        wideEnough &&
        media.orientation == Orientation.landscape;

    final canvasWidget = mustRotate
        ? _RotatePrompt(planName: plan.name)
        : RepaintBoundary(
            key: _canvasKey,
            child: plan.hasImage
                ? _ImageView(path: plan.imagePath!)
                : _DrawerView(
                    key: _drawerKey,
                    plan: plan,
                    selectedRoomId: _selectedRoomId,
                    readOnly: widget.readOnly,
                    allowWallPhotoCapture: widget.allowWallPhotoCapture,
                    etatId: widget.etatId,
                    externalChrome: showExternalSidebar,
                    onSelect: (id) =>
                        setState(() => _selectedRoomId = id),
                    onChanged: () => _save(plan),
                  ),
          );

    final body = showExternalSidebar
        ? Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    canvasWidget,
                    Positioned(
                      bottom: 14,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _CanvasControls(
                          canZoomIn:
                              _drawerKey.currentState?.canZoomInExt ?? true,
                          canZoomOut:
                              _drawerKey.currentState?.canZoomOutExt ??
                                  false,
                          onZoomIn: () => setState(() =>
                              _drawerKey.currentState?.zoomInExt()),
                          onZoomOut: () => setState(() =>
                              _drawerKey.currentState?.zoomOutExt()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 320,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    left: BorderSide(color: AppColors.divider),
                  ),
                ),
                child: _PlanSidebar(
                  plan: plan,
                  selected: selectedRoom,
                  isTerrain: plan.kind == PlanKind.terrain,
                  etatId: widget.etatId,
                  onAddRoom: (label) => _drawerKey.currentState
                      ?.addRoomFromPalette(label),
                  onAddFormeLibre: () {
                    final state = _drawerKey.currentState;
                    if (state == null) return;
                    if (selectedRoom != null) {
                      state.toggleFormeLibre();
                    } else {
                      state.addRoomFromPalette('Pièce en L');
                    }
                  },
                  onPickColor: (idx) =>
                      _drawerKey.currentState?.setRoomColorIndex(idx),
                  onRename: () => _drawerKey.currentState?.renameSelected(),
                  onDelete: () => _drawerKey.currentState?.deleteSelected(),
                  onRotate: () => _drawerKey.currentState?.rotateSelected(),
                  onOpenWall: (photo) => _openWallFromSidebar(plan, photo),
                ),
              ),
            ],
          )
        : canvasWidget;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _PlanTopBar(
              plan: plan,
              siblings: siblings,
              readOnly: widget.readOnly,
              canUndo: _canUndo && !mustRotate,
              canRedo: _canRedo && !mustRotate,
              totalAreaM2: logementSurface,
              roomCount: logementPieces,
              photoCount: plan.wallPhotos
                  .where((p) =>
                      widget.etatId == null || p.etatId == widget.etatId)
                  .length,
              onBack: () => Navigator.of(context).maybePop(),
              onSwitchPlan: _switchToPlan,
              onUndo: _undo,
              onRedo: _redo,
              onExport: mustRotate ? null : () => _exportCurrent(plan),
              onImport: widget.readOnly
                  ? null
                  : (plan.hasImage
                      ? () => _removeImage(plan)
                      : () => _importImage(plan)),
              hasImage: plan.hasImage,
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  RoomShape? _findSelectedRoom(PlanLogement plan) {
    final id = _selectedRoomId;
    if (id == null) return null;
    for (final r in plan.rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> _openWallFromSidebar(
      PlanLogement plan, WallPhoto sample) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WallPhotosScreen(
          planId: plan.id,
          roomId: sample.roomId,
          side: sample.side,
          title: '${sample.roomName} · ${sample.label}',
          canDelete: !widget.readOnly,
          etatId: widget.etatId,
        ),
      ),
    );
  }
}

class _PlanTopBar extends StatelessWidget {
  final PlanLogement plan;
  final List<PlanLogement> siblings;
  final bool readOnly;
  final bool canUndo;
  final bool canRedo;
  final bool hasImage;
  final double totalAreaM2;
  final int roomCount;
  final int photoCount;
  final VoidCallback onBack;
  final ValueChanged<PlanLogement> onSwitchPlan;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback? onExport;
  final VoidCallback? onImport;

  const _PlanTopBar({
    required this.plan,
    required this.siblings,
    required this.readOnly,
    required this.canUndo,
    required this.canRedo,
    required this.hasImage,
    required this.totalAreaM2,
    required this.roomCount,
    required this.photoCount,
    required this.onBack,
    required this.onSwitchPlan,
    required this.onUndo,
    required this.onRedo,
    required this.onExport,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final niveaux =
        siblings.where((p) => p.kind == PlanKind.niveau).toList();
    final showNiveau = plan.kind == PlanKind.niveau && niveaux.length > 1;
    final compact = MediaQuery.of(context).size.width < 720;
    final showStats =
        plan.kind != PlanKind.terrain && totalAreaM2 > 0 && !compact;
    final formattedArea = totalAreaM2 == totalAreaM2.roundToDouble()
        ? totalAreaM2.toStringAsFixed(0)
        : totalAreaM2.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          _LightIconButton(
            icon: Icons.arrow_back,
            tooltip: 'Retour',
            onTap: onBack,
          ),
          const SizedBox(width: 8),
          if (showNiveau)
            _NiveauDropdown(
              current: plan,
              niveaux: niveaux,
              onSwitch: onSwitchPlan,
            )
          else
            _PlanLabel(
              plan: plan,
              readOnly: readOnly,
            ),
          if (showStats) ...[
            const SizedBox(width: 16),
            _StatChips(
              areaText: '$formattedArea m²',
              roomCount: roomCount,
              photoCount: photoCount,
            ),
          ],
          const Spacer(),
          if (!readOnly) ...[
            _LightIconButton(
              icon: Icons.undo,
              tooltip: 'Annuler',
              onTap: canUndo ? onUndo : null,
            ),
            _LightIconButton(
              icon: Icons.redo,
              tooltip: 'Rétablir',
              onTap: canRedo ? onRedo : null,
            ),
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: AppColors.divider,
            ),
          ],
          if (onImport != null)
            _LightIconButton(
              icon: hasImage
                  ? Icons.image_not_supported_outlined
                  : Icons.upload_file_outlined,
              tooltip: hasImage ? 'Retirer l\'image' : 'Importer une image',
              onTap: onImport,
            ),
          const SizedBox(width: 6),
          _ExportButton(onTap: onExport),
        ],
      ),
    );
  }
}

class _PlanLabel extends StatelessWidget {
  final PlanLogement plan;
  final bool readOnly;
  const _PlanLabel({required this.plan, required this.readOnly});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            plan.kind.label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            plan.name + (readOnly ? ' (lecture seule)' : ''),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChips extends StatelessWidget {
  final String areaText;
  final int roomCount;
  final int photoCount;
  const _StatChips({
    required this.areaText,
    required this.roomCount,
    required this.photoCount,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(
        fontSize: 14,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 18,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              children: [
                TextSpan(
                  text: areaText.split(' ').first,
                ),
                const TextSpan(
                  text: '  m²',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Text('·', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(width: 10),
          Text(
            '$roomCount pièce${roomCount > 1 ? 's' : ''}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          const Text('·', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(width: 10),
          Text(
            '$photoCount photo${photoCount > 1 ? 's' : ''}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LightIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _LightIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 22,
            color: disabled ? AppColors.divider : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _ExportButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: disabled
          ? AppColors.primary.withValues(alpha: 0.4)
          : AppColors.primary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.file_download_outlined,
                  size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Exporter',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NiveauDropdown extends StatelessWidget {
  final PlanLogement current;
  final List<PlanLogement> niveaux;
  final ValueChanged<PlanLogement> onSwitch;
  const _NiveauDropdown({
    required this.current,
    required this.niveaux,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Changer de niveau',
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (id) {
        final p = niveaux.firstWhere((n) => n.id == id);
        onSwitch(p);
      },
      itemBuilder: (_) => niveaux
          .map(
            (n) => PopupMenuItem<String>(
              value: n.id,
              child: Row(
                children: [
                  Icon(
                    n.id == current.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: n.id == current.id
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(n.name),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'NIVEAU',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              current.name,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more,
                color: AppColors.textPrimary, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Sidebar externe (nouveau design — landscape large screen)
// ─────────────────────────────────────────────────────────────────────────

class _PlanSidebar extends StatelessWidget {
  final PlanLogement plan;
  final RoomShape? selected;
  final bool isTerrain;
  final String? etatId;
  final ValueChanged<String> onAddRoom;
  final VoidCallback onAddFormeLibre;
  final ValueChanged<int> onPickColor;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onRotate;
  final ValueChanged<WallPhoto> onOpenWall;

  const _PlanSidebar({
    required this.plan,
    required this.selected,
    required this.isTerrain,
    required this.onAddRoom,
    required this.onAddFormeLibre,
    required this.onPickColor,
    required this.onRename,
    required this.onDelete,
    required this.onRotate,
    required this.onOpenWall,
    this.etatId,
  });

  static const _quickRooms = <_QuickRoom>[
    _QuickRoom('Cuisine', Icons.countertops_outlined),
    _QuickRoom('Salon', Icons.weekend_outlined),
    _QuickRoom('Chambre', Icons.bed_outlined),
    _QuickRoom('Suite parentale', Icons.king_bed_outlined),
    _QuickRoom('SDB', Icons.bathtub_outlined),
    _QuickRoom('WC', Icons.wc_outlined),
    _QuickRoom('Couloir', Icons.swap_horiz),
    _QuickRoom('Entrée', Icons.login),
    _QuickRoom('Bureau', Icons.desk_outlined),
    _QuickRoom('Garage', Icons.garage_outlined),
    _QuickRoom('Pièce en L', Icons.dashboard_outlined),
    _QuickRoom('Pièce en T', Icons.shape_line_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final wallPhotos = plan.wallPhotos
        .where((p) => etatId == null || p.etatId == etatId)
        .toList()
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final byWall = <String, List<WallPhoto>>{};
    for (final p in wallPhotos) {
      final key = '${p.roomId}|${p.side}|${p.wallNumber}';
      byWall.putIfAbsent(key, () => []).add(p);
    }
    final wallEntries = byWall.entries.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isTerrain) ...[
            const _SectionHeader('Ajouter une pièce'),
            const SizedBox(height: 10),
            _RoomsGrid(
              rooms: _quickRooms,
              onPick: onAddRoom,
            ),
            const SizedBox(height: 12),
            _DashedAddButton(
              label: '+ Forme libre',
              onTap: onAddFormeLibre,
            ),
            const SizedBox(height: 22),
          ],
          const _SectionHeader('Pièce sélectionnée'),
          const SizedBox(height: 10),
          if (selected == null)
            const _SelectionEmpty()
          else
            _SelectedRoomCard(
              room: selected!,
              onRename: onRename,
              onDelete: onDelete,
              onRotate: onRotate,
              onPickColor: onPickColor,
              areaM2: _roomAreaForLabel(selected!),
              perimM: _perimeterForLabel(selected!),
            ),
          const SizedBox(height: 22),
          const _SectionHeader('Photos par mur'),
          const SizedBox(height: 10),
          if (wallEntries.isEmpty)
            const _PhotosEmpty()
          else
            ...wallEntries.map((e) {
              final photos = e.value;
              final sample = photos.first;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _WallPhotoTile(
                  label: sample.label,
                  title: sample.roomName,
                  count: photos.length,
                  onTap: () => onOpenWall(sample),
                ),
              );
            }),
        ],
      ),
    );
  }

  static double _roomAreaForLabel(RoomShape r) {
    if (r.isPolygon && r.vertices != null) {
      final v = r.vertices!;
      double a = 0;
      final n = v.length ~/ 2;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        a += v[i * 2] * v[j * 2 + 1];
        a -= v[j * 2] * v[i * 2 + 1];
      }
      return (a / 2).abs() * 144.0;
    }
    return r.width * r.height * 144.0;
  }

  static double _perimeterForLabel(RoomShape r) {
    if (r.isPolygon && r.vertices != null) {
      final v = r.vertices!;
      double p = 0;
      final n = v.length ~/ 2;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final dx = v[j * 2] - v[i * 2];
        final dy = v[j * 2 + 1] - v[i * 2 + 1];
        p += math.sqrt(dx * dx + dy * dy);
      }
      return p * 12.0;
    }
    return (r.width + r.height) * 2.0 * 12.0;
  }
}

class _QuickRoom {
  final String label;
  final IconData icon;
  const _QuickRoom(this.label, this.icon);
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.4,
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _RoomsGrid extends StatelessWidget {
  final List<_QuickRoom> rooms;
  final ValueChanged<String> onPick;
  const _RoomsGrid({required this.rooms, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rooms.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < rooms.length ? 8 : 0),
            child: Row(
              children: [
                Expanded(
                  child: _RoomChipButton(
                    icon: rooms[i].icon,
                    label: rooms[i].label,
                    onTap: () => onPick(_realLabel(rooms[i].label)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < rooms.length
                      ? _RoomChipButton(
                          icon: rooms[i + 1].icon,
                          label: rooms[i + 1].label,
                          onTap: () =>
                              onPick(_realLabel(rooms[i + 1].label)),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _realLabel(String shortLabel) {
    if (shortLabel == 'SDB') return 'Salle de bain';
    return shortLabel;
  }
}

class _RoomChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RoomChipButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedAddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DashedAddButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: AppColors.primary.withValues(alpha: 0.6),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    const dash = 5.0;
    const gap = 4.0;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double dist = 0;
      while (dist < metric.length) {
        final segment = metric.extractPath(
          dist,
          (dist + dash).clamp(0, metric.length).toDouble(),
        );
        canvas.drawPath(segment, paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SelectionEmpty extends StatelessWidget {
  const _SelectionEmpty();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Text(
        'Touchez une pièce dans le plan pour la sélectionner.',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _SelectedRoomCard extends StatelessWidget {
  final RoomShape room;
  final double areaM2;
  final double perimM;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onRotate;
  final ValueChanged<int> onPickColor;
  const _SelectedRoomCard({
    required this.room,
    required this.areaM2,
    required this.perimM,
    required this.onRename,
    required this.onDelete,
    required this.onRotate,
    required this.onPickColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = _DrawerViewState.paletteColors[
        room.colorIndex % _DrawerViewState.paletteColors.length];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.crop_square,
                    size: 18, color: Colors.black54),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${areaM2.toStringAsFixed(1)} m² · périm. ${perimM.toStringAsFixed(0)} m',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Renommer',
                onPressed: onRename,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0;
                  i < _DrawerViewState.paletteColors.length;
                  i++)
                _ColorDot(
                  color: _DrawerViewState.paletteColors[i],
                  selected: i == room.colorIndex,
                  onTap: () => onPickColor(i),
                ),
              _ActionDot(
                icon: Icons.rotate_right,
                tooltip: 'Pivoter de 45°',
                onTap: onRotate,
              ),
              _ActionDot(
                icon: Icons.delete_outline,
                tooltip: 'Supprimer',
                color: AppColors.error,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

class _ActionDot extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;
  const _ActionDot({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.divider),
          ),
          child: Icon(icon, size: 14, color: color ?? AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _PhotosEmpty extends StatelessWidget {
  const _PhotosEmpty();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Text(
        'Appui long sur un mur (M1, M2…) pour prendre une photo.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    );
  }
}

class _WallPhotoTile extends StatelessWidget {
  final String label;
  final String title;
  final int count;
  final VoidCallback onTap;
  const _WallPhotoTile({
    required this.label,
    required this.title,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  count == 1 ? '1 photo' : '$count photos',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanvasControls extends StatelessWidget {
  final bool canZoomIn;
  final bool canZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  const _CanvasControls({
    required this.canZoomIn,
    required this.canZoomOut,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(28),
      elevation: 4,
      shadowColor: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CanvasButton(
              icon: Icons.zoom_out,
              tooltip: 'Dézoomer',
              onTap: canZoomOut ? onZoomOut : null,
            ),
            _CanvasButton(
              icon: Icons.zoom_in,
              tooltip: 'Zoomer',
              onTap: canZoomIn ? onZoomIn : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CanvasButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _CanvasButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 22,
            color: disabled ? AppColors.divider : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _RotatePrompt extends StatelessWidget {
  final String planName;
  const _RotatePrompt({required this.planName});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.screen_rotation,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Tournez votre téléphone',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'L\'éditeur de plan « $planName » nécessite le mode '
              'paysage pour vous offrir l\'espace de travail nécessaire.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ImageSource { camera, gallery, fichier }

class _ImageView extends StatelessWidget {
  final String path;
  const _ImageView({required this.path});

  @override
  Widget build(BuildContext context) {
    final f = File(path);
    final isPdf = path.toLowerCase().endsWith('.pdf');
    if (isPdf) {
      // Pas de rendu PDF embarqué en phase 1 : on affiche un aperçu textuel.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined,
                  size: 80, color: AppColors.primary),
              const SizedBox(height: 12),
              const Text(
                'PDF importé',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                path.split('/').last,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5,
      child: Center(
        child: Image.file(
          f,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Text('Image illisible.'),
        ),
      ),
    );
  }
}

/// Vue dessin : grille + rooms + palette en bas.
class _DrawerView extends StatefulWidget {
  final PlanLogement plan;
  final String? selectedRoomId;
  final bool readOnly;
  final bool allowWallPhotoCapture;
  final String? etatId;
  final bool externalChrome;
  final ValueChanged<String?> onSelect;
  final VoidCallback onChanged;

  const _DrawerView({
    super.key,
    required this.plan,
    required this.selectedRoomId,
    required this.readOnly,
    required this.allowWallPhotoCapture,
    required this.etatId,
    required this.onSelect,
    required this.onChanged,
    this.externalChrome = false,
  });

  @override
  State<_DrawerView> createState() => _DrawerViewState();
}

class _DrawerViewState extends State<_DrawerView> {
  /// Pour suivre le mode de drag en cours sur une pièce sélectionnée :
  /// `move` = déplacer la pièce, `resize*` = poignée de mur,
  /// `resizeVertex` = poignée de sommet polygone.
  _DragMode? _dragMode;
  Offset? _dragStart;
  RoomShape? _dragSnapshot;
  int? _dragVertexIndex;

  /// Quand actif, un tap sur une pièce pose un repère au lieu de la sélectionner.
  bool _annotateMode = false;

  /// En mode prise de photos depuis l'EDL (readOnly + allowWallPhotoCapture),
  /// pièce verrouillée par appui long. Tant qu'une pièce est verrouillée,
  /// seuls ses badges de murs restent visibles et capturables — afin que
  /// l'utilisateur ne photographie pas le mur d'une pièce voisine par
  /// erreur. Hors de ce mode, ce champ reste null.
  String? _captureRoomId;

  bool get _isWallPhotoMode =>
      widget.readOnly && widget.allowWallPhotoCapture;

  /// Niveau de zoom appliqué au canvas (1.0 → 4.0). Le zoom est centré sur la
  /// pièce sélectionnée si présente, sinon au centre du canvas.
  double _zoom = 1.0;
  static const double _zoomMin = 1.0;
  static const double _zoomMax = 4.0;
  static const double _zoomStep = 0.5;

  /// Décalage de panoramique appliqué après le zoom (en pixels écran).
  /// Mis à jour par les flèches directionnelles.
  Offset _panOffset = Offset.zero;

  /// Pas de déplacement à chaque appui sur une flèche (en pixels écran).
  static const double _panStep = 60.0;

  /// État capturé au début d'un geste de pinch (2 doigts) pour calculer
  /// le delta de zoom et de pan relativement au début du geste.
  double _zoomAtPinchStart = 1.0;
  Offset _panAtPinchStart = Offset.zero;
  Offset _focalAtPinchStart = Offset.zero;

  void _zoomIn() {
    setState(() => _zoom = (_zoom + _zoomStep).clamp(_zoomMin, _zoomMax));
  }

  void _zoomOut() {
    setState(() {
      _zoom = (_zoom - _zoomStep).clamp(_zoomMin, _zoomMax);
      if (_zoom == 1.0) _panOffset = Offset.zero;
    });
  }

  void _pan(double dx, double dy) {
    setState(() {
      _panOffset = Offset(_panOffset.dx + dx, _panOffset.dy + dy);
    });
  }

  void _onPinchStart(ScaleStartDetails d) {
    _zoomAtPinchStart = _zoom;
    _panAtPinchStart = _panOffset;
    _focalAtPinchStart = d.focalPoint;
  }

  void _onPinchUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount < 2) return;
    final newZoom =
        (_zoomAtPinchStart * d.scale).clamp(_zoomMin, _zoomMax);
    final focalDelta = d.focalPoint - _focalAtPinchStart;
    setState(() {
      _zoom = newZoom;
      _panOffset = _panAtPinchStart + focalDelta;
      if (_zoom == 1.0) _panOffset = Offset.zero;
    });
  }

  static const _palette = [
    'Cuisine',
    'Salon',
    'Salle à manger',
    'Chambre',
    'Suite parentale',
    'Salle de bain',
    'WC',
    'Couloir',
    'Entrée',
    'Bureau',
    'Garage',
    'Pièce en L',
    'Pièce en T',
    'Cellier',
    'Placard',
    'Buanderie',
    'Pièce en L',
    'Pièce en T',
  ];

  static const _colors = [
    Color(0xFFBFDBFE),
    Color(0xFFFECACA),
    Color(0xFFFEF3C7),
    Color(0xFFD9F99D),
    Color(0xFFC7D2FE),
    Color(0xFFFBCFE8),
    Color(0xFFA7F3D0),
    Color(0xFFE2E8F0),
  ];

  static const _terrainItems = <_TerrainItem>[
    _TerrainItem('Maison', Icons.home_outlined, Color(0xFFFEF3C7), 0.30, 0.25),
    _TerrainItem('Garage', Icons.garage_outlined, Color(0xFFE2E8F0), 0.18, 0.14),
    _TerrainItem('Piscine', Icons.pool_outlined, Color(0xFF93C5FD), 0.20, 0.14),
    _TerrainItem('Terrasse', Icons.deck_outlined, Color(0xFFFED7AA), 0.20, 0.14),
    _TerrainItem('Cabanon', Icons.cabin_outlined, Color(0xFFD6BFA0), 0.10, 0.10),
    _TerrainItem('Allée', Icons.route_outlined, Color(0xFFE5E7EB), 0.30, 0.05),
    _TerrainItem('Parking', Icons.local_parking_outlined, Color(0xFFCBD5E1), 0.18, 0.10),
    _TerrainItem('Clôture', Icons.fence_outlined, Color(0xFF94A3B8), 0.30, 0.02),
    _TerrainItem('Portail', Icons.door_sliding_outlined, Color(0xFFFCD34D), 0.10, 0.02),
    _TerrainItem('Arbre', Icons.park_outlined, Color(0xFFA7F3D0), 0.07, 0.07),
    _TerrainItem('Végétation', Icons.local_florist_outlined, Color(0xFFD9F99D), 0.14, 0.10),
    _TerrainItem('Potager', Icons.eco_outlined, Color(0xFFBBF7D0), 0.15, 0.10),
    _TerrainItem('Puits', Icons.water_drop_outlined, Color(0xFFBAE6FD), 0.05, 0.05),
    _TerrainItem('BBQ', Icons.outdoor_grill_outlined, Color(0xFFCBD5E1), 0.06, 0.06),
  ];

  bool get _isTerrain => widget.plan.kind == PlanKind.terrain;

  _TerrainItem? _terrainItemByName(String name) {
    for (final t in _terrainItems) {
      if (t.name == name) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final wallNumbers = _computeWallNumbers();
    final annotationOrder = [...widget.plan.annotations]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final canvas = LayoutBuilder(
      builder: (ctx, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        final sel = _selectedRoom();
        final cx = sel == null ? 0.5 : sel.x + sel.width / 2;
        final cy = sel == null ? 0.5 : sel.y + sel.height / 2;
        return ClipRect(
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onScaleStart: _onPinchStart,
                onScaleUpdate: _onPinchUpdate,
                child: Transform.translate(
                  offset: _panOffset,
                  child: Transform.scale(
                    scale: _zoom,
                    alignment: Alignment(
                      (2 * cx - 1).clamp(-1.0, 1.0),
                      (2 * cy - 1).clamp(-1.0, 1.0),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _onTap(d.localPosition, size),
                      child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: _GridPainter()),
                        ),
                        // Si une pièce est verrouillée pour la capture
                        // photo, on la dessine en dernier afin que ses
                        // badges restent au-dessus de toute pièce voisine
                        // qui dépasse.
                        ..._roomsForRender()
                            .map((r) => _buildRoom(r, size, wallNumbers)),
                        ...annotationOrder.asMap().entries.map(
                              (e) => _buildPin(e.value, e.key + 1, size),
                            ),
                      ],
                    ),
                  ),
                ),
                ),
              ),
              if (_zoom > 1.0)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _PanPad(
                    onUp: () => _pan(0, _panStep),
                    onDown: () => _pan(0, -_panStep),
                    onLeft: () => _pan(_panStep, 0),
                    onRight: () => _pan(-_panStep, 0),
                  ),
                ),
            ],
          ),
        );
      },
    );

    final toolbar = _Toolbar(
      selected: _selectedRoom(),
      readOnly: widget.readOnly,
      annotateMode: _annotateMode,
      zoom: _zoom,
      canZoomIn: _zoom < _zoomMax,
      canZoomOut: _zoom > _zoomMin,
      onZoomIn: _zoomIn,
      onZoomOut: _zoomOut,
      onToggleAnnotate: () =>
          setState(() => _annotateMode = !_annotateMode),
      onRename: _renameSelected,
      onDelete: _deleteSelected,
      onColor: _colorSelected,
      onToggleShape: _toggleShapeMode,
      onRotate: _rotateSelected,
    );
    final paletteItems =
        _isTerrain ? _terrainItems.map((t) => t.name).toList() : _palette;
    final paletteIcons = _isTerrain
        ? {for (final t in _terrainItems) t.name: t.icon}
        : const <String, IconData>{};
    final palette = widget.readOnly
        ? null
        : _Palette(
            items: paletteItems,
            icons: paletteIcons,
            onPick: (label) => _addRoom(label),
          );

    final captureHint = _isWallPhotoMode
        ? _CaptureHint(
            captureRoomName: _captureRoomId == null
                ? null
                : widget.plan.rooms
                    .firstWhere(
                      (r) => r.id == _captureRoomId,
                      orElse: () => widget.plan.rooms.first,
                    )
                    .name,
            onClear: _captureRoomId == null
                ? null
                : () => setState(() => _captureRoomId = null),
          )
        : null;

    if (widget.externalChrome) {
      // La sidebar/toolbar/palette sont gérées par le parent (nouveau design).
      return Column(
        children: [
          if (captureHint != null) captureHint,
          Expanded(child: canvas),
        ],
      );
    }
    return OrientationBuilder(
      builder: (ctx, orientation) {
        if (orientation == Orientation.landscape) {
          return Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    if (captureHint != null) captureHint,
                    Expanded(child: canvas),
                  ],
                ),
              ),
              SizedBox(
                width: 220,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border:
                        Border(left: BorderSide(color: AppColors.divider)),
                  ),
                  child: Column(
                    children: [
                      toolbar,
                      const Divider(height: 1),
                      if (!widget.readOnly)
                        Expanded(
                          child: _Palette(
                            items: paletteItems,
                            icons: paletteIcons,
                            onPick: (label) => _addRoom(label),
                            vertical: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            if (captureHint != null) captureHint,
            Expanded(child: canvas),
            toolbar,
            if (palette != null) palette,
          ],
        );
      },
    );
  }

  RoomShape? _selectedRoom() {
    final id = widget.selectedRoomId;
    if (id == null) return null;
    for (final r in widget.plan.rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Normalise un nom de pièce pour comparaison (trim + lower-case).
  /// Évite que « Salon » et « salon » soient traités comme différents.
  static String _normName(String s) => s.trim().toLowerCase();

  /// Toutes les pièces qui partagent le même nom et sont reliées (par
  /// transitivité d'arêtes communes) à [r]. Inclut [r] elle-même.
  /// Les pièces polygonales restent isolées (groupe = elles-mêmes).
  List<RoomShape> _groupOf(RoomShape r) {
    if (r.isPolygon) return [r];
    final visited = <String>{r.id};
    final queue = <RoomShape>[r];
    final result = <RoomShape>[];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      result.add(cur);
      for (final other in widget.plan.rooms) {
        if (visited.contains(other.id)) continue;
        if (other.isPolygon) continue;
        if (_normName(other.name) != _normName(cur.name)) continue;
        if (_touches(cur, other)) {
          visited.add(other.id);
          queue.add(other);
        }
      }
    }
    return result;
  }

  /// Vrai si [a] et [b] partagent une arête (overlap > 0).
  /// Les polygones ne sont jamais considérés "touchant" pour l'instant.
  bool _touches(RoomShape a, RoomShape b) {
    if (a.isPolygon || b.isPolygon) return false;
    const eps = 0.003;
    final aR = a.x + a.width;
    final aB = a.y + a.height;
    final bR = b.x + b.width;
    final bB = b.y + b.height;
    final hOverlap =
        math.max(0.0, math.min(aB, bB) - math.max(a.y, b.y));
    final vOverlap =
        math.max(0.0, math.min(aR, bR) - math.max(a.x, b.x));
    if ((aR - b.x).abs() < eps && hOverlap > eps) return true;
    if ((bR - a.x).abs() < eps && hOverlap > eps) return true;
    if ((aB - b.y).abs() < eps && vOverlap > eps) return true;
    if ((bB - a.y).abs() < eps && vOverlap > eps) return true;
    return false;
  }

  /// Côtés de [r] qui partagent une arête avec une voisine du même nom.
  /// Toujours faux pour les polygones (chaque arête reste numérotée).
  ({bool top, bool right, bool bottom, bool left}) _sharedSides(RoomShape r) {
    if (r.isPolygon) {
      return (top: false, right: false, bottom: false, left: false);
    }
    const eps = 0.003;
    bool top = false, right = false, bottom = false, left = false;
    final rR = r.x + r.width;
    final rB = r.y + r.height;
    for (final o in widget.plan.rooms) {
      if (o.id == r.id) continue;
      if (o.isPolygon) continue;
      if (_normName(o.name) != _normName(r.name)) continue;
      final oR = o.x + o.width;
      final oB = o.y + o.height;
      final hOverlap =
          math.max(0.0, math.min(rB, oB) - math.max(r.y, o.y));
      final vOverlap =
          math.max(0.0, math.min(rR, oR) - math.max(r.x, o.x));
      if ((rR - o.x).abs() < eps && hOverlap > eps) right = true;
      if ((oR - r.x).abs() < eps && hOverlap > eps) left = true;
      if ((rB - o.y).abs() < eps && vOverlap > eps) bottom = true;
      if ((oB - r.y).abs() < eps && vOverlap > eps) top = true;
    }
    return (top: top, right: right, bottom: bottom, left: left);
  }

  /// L'ancre du groupe = pièce avec l'id le plus petit (ordre stable).
  /// Sert à n'afficher qu'un seul label par groupe fusionné.
  bool _isAnchor(RoomShape r) {
    final group = _groupOf(r);
    if (group.length <= 1) return true;
    group.sort((a, b) => a.id.compareTo(b.id));
    return group.first.id == r.id;
  }

  /// Numéro de chaque mur visible (non partagé avec une voisine de même nom
  /// et non explicitement supprimé). La numérotation redémarre à 1 pour
  /// chaque pièce, dans l'ordre haut → droite → bas → gauche.
  /// Désactivée pour les plans de terrain (les éléments extérieurs n'ont
  /// pas de notion de mur partagé).
  Map<String, _WallNumbers> _computeWallNumbers() {
    if (_isTerrain) return const {};
    final result = <String, _WallNumbers>{};
    final processed = <String>{};
    for (final r in widget.plan.rooms) {
      if (r.isPolygon) {
        final perEdge = <int, int>{};
        var counter = 1;
        final n = r.vertexCount;
        for (var i = 0; i < n; i++) {
          final removed = r.hiddenWalls.contains('edge:$i');
          if (!removed) perEdge[i] = counter++;
        }
        if (perEdge.isNotEmpty) {
          result[r.id] = _WallNumbers(byEdgeIndex: perEdge);
        }
        continue;
      }
      if (processed.contains(r.id)) continue;
      final group = _groupOf(r)..sort((a, b) => a.id.compareTo(b.id));
      var counter = 1;
      for (final g in group) {
        processed.add(g.id);
        final s = _sharedSides(g);
        final perRoom = <_WallSide, int>{};
        for (final side in _WallSide.values) {
          final shared = switch (side) {
            _WallSide.top => s.top,
            _WallSide.right => s.right,
            _WallSide.bottom => s.bottom,
            _WallSide.left => s.left,
          };
          final removed = g.hiddenWalls.contains(side.name);
          if (!shared && !removed) perRoom[side] = counter++;
        }
        if (perRoom.isNotEmpty) {
          result[g.id] = _WallNumbers(bySide: perRoom);
        }
      }
    }
    return result;
  }

  /// Renvoie le rectangle voisin qui touche [r] sur [side], ou null. Ne
  /// considère pas les polygones ni [r] lui-même.
  RoomShape? _adjacentRectangleOn(RoomShape r, _WallSide side) {
    if (r.isPolygon) return null;
    const eps = 0.003;
    final rR = r.x + r.width;
    final rB = r.y + r.height;
    for (final o in widget.plan.rooms) {
      if (o.id == r.id) continue;
      if (o.isPolygon) continue;
      final oR = o.x + o.width;
      final oB = o.y + o.height;
      final hOverlap =
          math.max(0.0, math.min(rB, oB) - math.max(r.y, o.y));
      final vOverlap =
          math.max(0.0, math.min(rR, oR) - math.max(r.x, o.x));
      switch (side) {
        case _WallSide.right:
          if ((rR - o.x).abs() < eps && hOverlap > eps) return o;
        case _WallSide.left:
          if ((oR - r.x).abs() < eps && hOverlap > eps) return o;
        case _WallSide.bottom:
          if ((rB - o.y).abs() < eps && vOverlap > eps) return o;
        case _WallSide.top:
          if ((oB - r.y).abs() < eps && vOverlap > eps) return o;
      }
    }
    return null;
  }

  // ── Photos de mur ──────────────────────────────────────────────────────

  List<WallPhoto> _photosFor(String roomId, _WallSide side) {
    return widget.plan.wallPhotos
        .where((p) =>
            p.roomId == roomId &&
            p.side == side.name &&
            (widget.etatId == null || p.etatId == widget.etatId))
        .toList()
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  }

  Widget _wallBadgeFor(RoomShape r, _WallSide side, int wallNumber) {
    final count = _photosFor(r.id, side).length;
    final captureLocked = _isWallPhotoMode && _captureRoomId == r.id;
    final useShortTap = captureLocked;
    final badge = _WallBadge(
      label: 'M$wallNumber',
      photoCount: count,
      large: captureLocked,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: useShortTap
          ? () => _onWallBadgeLongPress(r, side, wallNumber)
          : null,
      onLongPress: useShortTap
          ? null
          : () => _onWallBadgeLongPress(r, side, wallNumber),
      child: captureLocked
          ? Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              child: badge,
            )
          : badge,
    );
  }

  /// Verrouille (ou déverrouille) une pièce pour la capture photo. Quand
  /// verrouillée, seuls ses badges de murs sont visibles + capturables.
  void _toggleCaptureRoom(String roomId) {
    setState(() {
      _captureRoomId = (_captureRoomId == roomId) ? null : roomId;
    });
  }

  /// Ordre de rendu des pièces : la pièce verrouillée pour la capture
  /// photo est repoussée en dernière position, afin que ses badges (qui
  /// peuvent dépasser sur les pièces voisines) restent cliquables.
  List<RoomShape> _roomsForRender() {
    final lockId = _captureRoomId;
    if (lockId == null) return widget.plan.rooms;
    final rest = <RoomShape>[];
    RoomShape? locked;
    for (final r in widget.plan.rooms) {
      if (r.id == lockId) {
        locked = r;
      } else {
        rest.add(r);
      }
    }
    if (locked == null) return widget.plan.rooms;
    return [...rest, locked];
  }

  Future<void> _onWallBadgeLongPress(
      RoomShape r, _WallSide side, int wallNumber) async {
    final photos = _photosFor(r.id, side);
    final ro = widget.readOnly;
    final canCapture = !ro || widget.allowWallPhotoCapture;
    if (!canCapture && photos.isEmpty) return;
    final isHidden = r.hiddenWalls.contains(side.name);
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                '${r.name} · M$wallNumber',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const Divider(height: 1),
            if (canCapture)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Prendre une photo'),
                onTap: () => Navigator.of(ctx).pop('camera'),
              ),
            if (canCapture)
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choisir dans la galerie'),
                onTap: () => Navigator.of(ctx).pop('gallery'),
              ),
            if (photos.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.collections_outlined),
                title: Text('Voir les photos (${photos.length})'),
                onTap: () => Navigator.of(ctx).pop('view'),
              ),
            if (canCapture) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: const Text('Changer de pièce / de mur…'),
                onTap: () => Navigator.of(ctx).pop('switch'),
              ),
            ],
            if (!ro)
              ListTile(
                leading: Icon(isHidden
                    ? Icons.add_box_outlined
                    : Icons.delete_outline),
                title: Text(
                    isHidden ? 'Restaurer ce mur' : 'Supprimer ce mur'),
                onTap: () => Navigator.of(ctx).pop('toggleHidden'),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Annuler'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'camera') {
      await _captureWallPhoto(r, side, wallNumber, ImageSource.camera);
    } else if (action == 'gallery') {
      await _captureWallPhoto(r, side, wallNumber, ImageSource.gallery);
    } else if (action == 'view') {
      await _showWallPhotos(r, side, wallNumber);
    } else if (action == 'switch') {
      final picked = await _pickAnotherWall();
      if (!mounted || picked == null) return;
      await _onWallBadgeLongPress(picked.$1, picked.$2, picked.$3);
    } else if (action == 'toggleHidden') {
      _toggleWallHidden(r, side);
    }
  }

  Future<(RoomShape, _WallSide, int)?> _pickAnotherWall() async {
    final wallNumbers = _computeWallNumbers();
    final rooms = widget.plan.rooms
        .where((r) => !r.isPolygon && wallNumbers[r.id] != null)
        .toList();
    if (rooms.isEmpty) return null;
    return showModalBottomSheet<(RoomShape, _WallSide, int)>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Choisir la pièce et le mur',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: rooms.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = rooms[i];
                    final entries = wallNumbers[r.id]!.bySide.entries.toList()
                      ..sort((a, b) => a.value.compareTo(b.value));
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final e in entries)
                                ActionChip(
                                  label: Text('M${e.value}'),
                                  onPressed: () => Navigator.of(ctx)
                                      .pop((r, e.key, e.value)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Annuler'),
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _captureWallPhoto(
    RoomShape r,
    _WallSide side,
    int wallNumber,
    ImageSource src,
  ) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: src, imageQuality: 85);
    if (x == null) return;
    if (!mounted) return;
    final svc = context.read<PlanLogementService>();
    final photoId = const Uuid().v4();
    final ext = x.path.contains('.')
        ? x.path.substring(x.path.lastIndexOf('.') + 1).toLowerCase()
        : 'jpg';
    final destPath = await svc.persistWallPhoto(
      source: File(x.path),
      planId: widget.plan.id,
      photoId: photoId,
      extension: ext,
    );
    final takenAt = DateTime.now().toUtc();
    try {
      await PhotoWatermark.stampInPlace(
        File(destPath),
        at: takenAt,
        label: '${r.name} · M$wallNumber',
      );
    } catch (_) {
      // En cas d'échec, on garde la photo brute plutôt que de bloquer
      // l'utilisateur ; la date+heure reste enregistrée dans le modèle.
    }
    final photo = WallPhoto(
      id: photoId,
      roomId: r.id,
      side: side.name,
      wallNumber: wallNumber,
      roomName: r.name,
      path: destPath,
      takenAt: takenAt,
      etatId: widget.etatId,
    );
    setState(() => widget.plan.wallPhotos.add(photo));
    widget.onChanged();
  }

  Future<void> _showWallPhotos(
      RoomShape r, _WallSide side, int wallNumber) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WallPhotosScreen(
          planId: widget.plan.id,
          roomId: r.id,
          side: side.name,
          title: '${r.name} · M$wallNumber',
          canDelete: !widget.readOnly,
          etatId: widget.etatId,
        ),
      ),
    );
  }

  /// Long-press sur une poignée de mur : marque le mur comme supprimé,
  /// ou le restaure si déjà supprimé. Si le mur sépare deux pièces
  /// distinctes, fusionne les pièces (renommage de la voisine pour matcher)
  /// afin de ne former qu'une seule pièce avec numérotation continue.
  void _toggleWallHidden(RoomShape r, _WallSide side) {
    if (widget.readOnly) return;
    final key = side.name;
    final isHidden = r.hiddenWalls.contains(key);
    if (!isHidden) {
      final neighbor = _adjacentRectangleOn(r, side);
      if (neighbor != null && neighbor.name != r.name) {
        setState(() {
          neighbor.name = r.name;
        });
        widget.onChanged();
        return;
      }
    }
    setState(() {
      if (isHidden) {
        r.hiddenWalls.remove(key);
      } else {
        r.hiddenWalls.add(key);
      }
    });
    widget.onChanged();
  }

  Widget _buildRoom(
    RoomShape r,
    Size canvas,
    Map<String, _WallNumbers> wallNumbers,
  ) {
    if (r.isPolygon) {
      return _buildPolygonRoom(r, canvas, wallNumbers);
    }
    final left = r.x * canvas.width;
    final top = r.y * canvas.height;
    final width = r.width * canvas.width;
    final height = r.height * canvas.height;
    final selectedId = widget.selectedRoomId;
    final terrainItem = _isTerrain ? _terrainItemByName(r.name) : null;
    final group = _isTerrain ? <RoomShape>[r] : _groupOf(r);
    final selectedInGroup =
        selectedId != null && group.any((g) => g.id == selectedId);
    final color = terrainItem?.color ??
        _colors[r.colorIndex.clamp(0, _colors.length - 1)];
    final shared = _isTerrain
        ? (top: false, right: false, bottom: false, left: false)
        : _sharedSides(r);
    bool wallHidden(_WallSide s) => r.hiddenWalls.contains(s.name);
    final hide = (
      top: shared.top || wallHidden(_WallSide.top),
      right: shared.right || wallHidden(_WallSide.right),
      bottom: shared.bottom || wallHidden(_WallSide.bottom),
      left: shared.left || wallHidden(_WallSide.left),
    );
    final isAnchor = _isTerrain ? true : _isAnchor(r);
    final nums = wallNumbers[r.id]?.bySide ?? const <_WallSide, int>{};

    final isCaptureLocked = _isWallPhotoMode && _captureRoomId == r.id;
    final hasCaptureLock = _isWallPhotoMode && _captureRoomId != null;
    final borderColor = (selectedInGroup || isCaptureLocked)
        ? AppColors.primary
        : Colors.black54;
    final borderWidth = (selectedInGroup || isCaptureLocked) ? 2.5 : 1.5;
    BorderSide side(bool hide) => hide
        ? BorderSide.none
        : BorderSide(color: borderColor, width: borderWidth);

    final ro = widget.readOnly;
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        onTapUp: ro
            ? null
            : (d) {
                if (_annotateMode) {
                  _createAnnotation(r, d.localPosition, canvas);
                } else {
                  widget.onSelect(r.id);
                }
              },
        onLongPress: _isWallPhotoMode
            ? () => _toggleCaptureRoom(r.id)
            : (ro || _annotateMode)
                ? null
                : () => _showRoomContextMenu(r),
        onPanStart: (ro || _annotateMode)
            ? null
            : (d) {
                widget.onSelect(r.id);
                _dragMode = _DragMode.move;
                _dragStart = d.globalPosition;
                _dragSnapshot = _snap(r);
              },
        onPanUpdate: (ro || _annotateMode)
            ? null
            : (d) => _onPanUpdate(r, d.globalPosition, canvas),
        onPanEnd: (ro || _annotateMode) ? null : (_) => _onPanEnd(),
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.7),
                border: Border(
                  top: side(hide.top),
                  right: side(hide.right),
                  bottom: side(hide.bottom),
                  left: side(hide.left),
                ),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(4),
              child: isAnchor
                  ? (terrainItem != null
                      ? _TerrainContent(
                          icon: terrainItem.icon, label: r.name)
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            r.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: Colors.black,
                            ),
                          ),
                        ))
                  : const SizedBox.shrink(),
            ),
            // Badges de numérotation des murs visibles.
            // En mode capture verrouillé sur une autre pièce → masqués
            // pour éviter toute confusion entre pièces.
            if (!hasCaptureLock || isCaptureLocked) ...[
              if (nums[_WallSide.top] != null)
                Positioned(
                  top: 4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child:
                        _wallBadgeFor(r, _WallSide.top, nums[_WallSide.top]!),
                  ),
                ),
              if (nums[_WallSide.bottom] != null)
                Positioned(
                  bottom: 4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _wallBadgeFor(
                        r, _WallSide.bottom, nums[_WallSide.bottom]!),
                  ),
                ),
              if (nums[_WallSide.left] != null)
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _wallBadgeFor(
                        r, _WallSide.left, nums[_WallSide.left]!),
                  ),
                ),
              if (nums[_WallSide.right] != null)
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _wallBadgeFor(
                        r, _WallSide.right, nums[_WallSide.right]!),
                  ),
                ),
            ],
            // Porte de garage : bande visible sur le mur désigné. La poignée
            // de redimensionnement n'apparaît que quand la pièce est
            // sélectionnée et qu'on n'est pas en mode lecture seule.
            if (r.hasGarageDoor)
              _GarageDoorOverlay(
                room: r,
                showHandle: selectedInGroup && !ro && !_annotateMode,
                onResize: (ratio) {
                  setState(() {
                    r.garageDoorRatio = ratio.clamp(0.1, 1.0);
                  });
                  widget.onChanged();
                },
              ),
            // Poignées de murs (visibles uniquement quand sélectionné,
            // hors mode annotation et hors lecture seule).
            if (selectedInGroup && !_annotateMode && !ro) ...[
              _wallHandle(r, _WallSide.top, canvas, hide.top),
              _wallHandle(r, _WallSide.right, canvas, hide.right),
              _wallHandle(r, _WallSide.bottom, canvas, hide.bottom),
              _wallHandle(r, _WallSide.left, canvas, hide.left),
            ],
          ],
        ),
      ),
    );
  }

  /// Rendu d'une pièce en mode polygone (forme libre).
  Widget _buildPolygonRoom(
    RoomShape r,
    Size canvas,
    Map<String, _WallNumbers> wallNumbers,
  ) {
    final left = r.x * canvas.width;
    final top = r.y * canvas.height;
    final width = r.width * canvas.width;
    final height = r.height * canvas.height;
    final isSelected = widget.selectedRoomId == r.id;
    final color = _colors[r.colorIndex.clamp(0, _colors.length - 1)];
    final n = r.vertexCount;
    final w = r.width.clamp(0.001, 1.0);
    final h = r.height.clamp(0.001, 1.0);
    final verts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final v = r.vertexAt(i);
      verts.add(Offset(
        ((v.vx - r.x) / w) * width,
        ((v.vy - r.y) / h) * height,
      ));
    }
    bool wallHidden(int i) => r.hiddenWalls.contains('edge:$i');
    final isCaptureLocked = _isWallPhotoMode && _captureRoomId == r.id;
    final hasCaptureLock = _isWallPhotoMode && _captureRoomId != null;
    final borderColor = (isSelected || isCaptureLocked)
        ? AppColors.primary
        : Colors.black54;
    final borderWidth = (isSelected || isCaptureLocked) ? 2.5 : 1.5;
    final nums = wallNumbers[r.id]?.byEdgeIndex ?? const <int, int>{};

    double cxSum = 0, cySum = 0;
    for (final p in verts) {
      cxSum += p.dx;
      cySum += p.dy;
    }
    final cx = cxSum / verts.length;
    final cy = cySum / verts.length;

    final ro = widget.readOnly;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        onTapUp: ro
            ? null
            : (d) {
                if (_annotateMode) {
                  _createPolygonAnnotation(r, d.localPosition, canvas, verts);
                } else {
                  widget.onSelect(r.id);
                }
              },
        onLongPress: _isWallPhotoMode
            ? () => _toggleCaptureRoom(r.id)
            : (ro || _annotateMode)
                ? null
                : () => _showRoomContextMenu(r),
        onPanStart: (ro || _annotateMode)
            ? null
            : (d) {
                widget.onSelect(r.id);
                _dragMode = _DragMode.move;
                _dragStart = d.globalPosition;
                _dragSnapshot = _snap(r);
              },
        onPanUpdate: (ro || _annotateMode)
            ? null
            : (d) => _onPanUpdate(r, d.globalPosition, canvas),
        onPanEnd: (ro || _annotateMode) ? null : (_) => _onPanEnd(),
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _PolygonPainter(
                vertices: verts,
                fill: color.withValues(alpha: 0.7),
                borderColor: borderColor,
                borderWidth: borderWidth,
                hiddenEdges: {
                  for (var i = 0; i < n; i++)
                    if (wallHidden(i)) i,
                },
              ),
            ),
            // Label au centroïde
            Positioned(
              left: cx - 60,
              top: cy - 10,
              width: 120,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  r.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            // Badges des arêtes (milieu d'arête). En mode capture
            // verrouillé sur une autre pièce, on les masque.
            if (!hasCaptureLock || isCaptureLocked)
              for (var i = 0; i < n; i++)
                if (nums[i] != null)
                  Builder(builder: (_) {
                    final mx = (verts[i].dx + verts[(i + 1) % n].dx) / 2;
                    final my = (verts[i].dy + verts[(i + 1) % n].dy) / 2;
                    final ddx = cx - mx;
                    final ddy = cy - my;
                    final len = math.sqrt(ddx * ddx + ddy * ddy);
                    const shift = 20.0;
                    final ox = len > 0.001 ? ddx / len * shift : 0.0;
                    final oy = len > 0.001 ? ddy / len * shift : 0.0;
                    return Positioned(
                    left: mx + ox - (isCaptureLocked ? 28 : 16),
                    top: my + oy - (isCaptureLocked ? 28 : 12),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: isCaptureLocked
                          ? () => _onPolygonWallBadgeLongPress(
                              r, i, nums[i]!)
                          : null,
                      onLongPress: isCaptureLocked
                          ? null
                          : () =>
                              _onPolygonWallBadgeLongPress(r, i, nums[i]!),
                      child: isCaptureLocked
                          ? Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              child: _WallBadge(
                                label: 'M${nums[i]}',
                                photoCount: _photosForEdge(r.id, i).length,
                                large: true,
                              ),
                            )
                          : _WallBadge(
                              label: 'M${nums[i]}',
                              photoCount: _photosForEdge(r.id, i).length,
                            ),
                    ),
                  );
                  }),
            // Poignées de sommets + boutons d'insertion (si sélectionné)
            if (isSelected && !_annotateMode && !ro) ...[
              for (var i = 0; i < n; i++)
                Positioned(
                  left: verts[i].dx - 11,
                  top: verts[i].dy - 11,
                  child: _vertexHandle(r, i, canvas),
                ),
              for (var i = 0; i < n; i++)
                Positioned(
                  left: (verts[i].dx + verts[(i + 1) % n].dx) / 2 - 9,
                  top: (verts[i].dy + verts[(i + 1) % n].dy) / 2 - 9,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _insertVertex(r, i),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.primary, width: 1.5),
                      ),
                      child: const Icon(Icons.add,
                          size: 12, color: AppColors.primary),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vertexHandle(RoomShape r, int index, Size canvas) {
    return GestureDetector(
      onPanStart: (d) {
        widget.onSelect(r.id);
        _dragMode = _DragMode.resizeVertex;
        _dragVertexIndex = index;
        _dragStart = d.globalPosition;
        _dragSnapshot = _snap(r);
      },
      onPanUpdate: (d) => _onPanUpdate(r, d.globalPosition, canvas),
      onPanEnd: (_) => _onPanEnd(),
      onLongPress: () => _removeVertex(r, index),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  void _insertVertex(RoomShape r, int edgeIndex) {
    if (!r.isPolygon) return;
    final v = List<double>.from(r.vertices!);
    final n = v.length ~/ 2;
    final i = ((edgeIndex % n) + n) % n;
    final j = (i + 1) % n;
    final mx = (v[i * 2] + v[j * 2]) / 2;
    final my = (v[i * 2 + 1] + v[j * 2 + 1]) / 2;
    // Insère un nouveau sommet juste après i.
    v.insert(i * 2 + 2, my);
    v.insert(i * 2 + 2, mx);
    // Décale les hiddenWalls 'edge:k' avec k > i.
    final newHidden = <String>[];
    for (final hk in r.hiddenWalls) {
      if (hk.startsWith('edge:')) {
        final k = int.tryParse(hk.substring(5));
        if (k == null) {
          newHidden.add(hk);
        } else if (k <= i) {
          newHidden.add(hk);
        } else {
          newHidden.add('edge:${k + 1}');
        }
      } else {
        newHidden.add(hk);
      }
    }
    setState(() {
      r.vertices = v;
      r.hiddenWalls = newHidden;
      r.recomputeBounds();
    });
    widget.onChanged();
  }

  void _removeVertex(RoomShape r, int index) {
    if (!r.isPolygon) return;
    final v = List<double>.from(r.vertices!);
    final n = v.length ~/ 2;
    if (n <= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Un polygone doit garder au moins 3 sommets'),
        ),
      );
      return;
    }
    final i = ((index % n) + n) % n;
    v.removeAt(i * 2);
    v.removeAt(i * 2);
    final newHidden = <String>[];
    for (final hk in r.hiddenWalls) {
      if (hk.startsWith('edge:')) {
        final k = int.tryParse(hk.substring(5));
        if (k == null) {
          newHidden.add(hk);
        } else if (k < i) {
          newHidden.add(hk);
        } else if (k > i) {
          newHidden.add('edge:${k - 1}');
        }
        // k == i : l'arête disparaît avec la suppression.
      } else {
        newHidden.add(hk);
      }
    }
    setState(() {
      r.vertices = v;
      r.hiddenWalls = newHidden;
      r.recomputeBounds();
    });
    widget.onChanged();
  }

  // ── Photos murs polygone ───────────────────────────────────────────────

  List<WallPhoto> _photosForEdge(String roomId, int edgeIndex) {
    return widget.plan.wallPhotos
        .where((p) =>
            p.roomId == roomId &&
            p.edgeIndex == edgeIndex &&
            (widget.etatId == null || p.etatId == widget.etatId))
        .toList()
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  }

  Future<void> _onPolygonWallBadgeLongPress(
      RoomShape r, int edgeIndex, int wallNumber) async {
    final photos = _photosForEdge(r.id, edgeIndex);
    final ro = widget.readOnly;
    final canCapture = !ro || widget.allowWallPhotoCapture;
    if (!canCapture && photos.isEmpty) return;
    final hiddenKey = 'edge:$edgeIndex';
    final isHidden = r.hiddenWalls.contains(hiddenKey);
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                '${r.name} · M$wallNumber',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const Divider(height: 1),
            if (canCapture)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Prendre une photo'),
                onTap: () => Navigator.of(ctx).pop('camera'),
              ),
            if (canCapture)
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choisir dans la galerie'),
                onTap: () => Navigator.of(ctx).pop('gallery'),
              ),
            if (photos.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.collections_outlined),
                title: Text('Voir les photos (${photos.length})'),
                onTap: () => Navigator.of(ctx).pop('view'),
              ),
            if (!ro)
              ListTile(
                leading: Icon(isHidden
                    ? Icons.add_box_outlined
                    : Icons.delete_outline),
                title: Text(
                    isHidden ? 'Restaurer ce mur' : 'Supprimer ce mur'),
                onTap: () => Navigator.of(ctx).pop('toggleHidden'),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Annuler'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'camera') {
      await _captureWallPhotoEdge(
          r, edgeIndex, wallNumber, ImageSource.camera);
    } else if (action == 'gallery') {
      await _captureWallPhotoEdge(
          r, edgeIndex, wallNumber, ImageSource.gallery);
    } else if (action == 'view') {
      await _showWallPhotosEdge(r, edgeIndex, wallNumber);
    } else if (action == 'toggleHidden') {
      setState(() {
        if (isHidden) {
          r.hiddenWalls.remove(hiddenKey);
        } else {
          r.hiddenWalls.add(hiddenKey);
        }
      });
      widget.onChanged();
    }
  }

  Future<void> _captureWallPhotoEdge(
    RoomShape r,
    int edgeIndex,
    int wallNumber,
    ImageSource src,
  ) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: src, imageQuality: 85);
    if (x == null) return;
    if (!mounted) return;
    final svc = context.read<PlanLogementService>();
    final photoId = const Uuid().v4();
    final ext = x.path.contains('.')
        ? x.path.substring(x.path.lastIndexOf('.') + 1).toLowerCase()
        : 'jpg';
    final destPath = await svc.persistWallPhoto(
      source: File(x.path),
      planId: widget.plan.id,
      photoId: photoId,
      extension: ext,
    );
    final takenAt = DateTime.now().toUtc();
    try {
      await PhotoWatermark.stampInPlace(
        File(destPath),
        at: takenAt,
        label: '${r.name} · M$wallNumber',
      );
    } catch (_) {}
    final photo = WallPhoto(
      id: photoId,
      roomId: r.id,
      side: 'edge',
      wallNumber: wallNumber,
      roomName: r.name,
      path: destPath,
      takenAt: takenAt,
      etatId: widget.etatId,
      edgeIndex: edgeIndex,
    );
    setState(() => widget.plan.wallPhotos.add(photo));
    widget.onChanged();
  }

  Future<void> _showWallPhotosEdge(
      RoomShape r, int edgeIndex, int wallNumber) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WallPhotosScreen(
          planId: widget.plan.id,
          roomId: r.id,
          side: 'edge',
          edgeIndex: edgeIndex,
          title: '${r.name} · M$wallNumber',
          canDelete: !widget.readOnly,
          etatId: widget.etatId,
        ),
      ),
    );
  }

  // ── Annotations polygone ──────────────────────────────────────────────

  Future<void> _createPolygonAnnotation(
      RoomShape r, Offset localPos, Size canvas, List<Offset> verts) async {
    // Conversion local → normalisé global
    final w = r.width.clamp(0.001, 1.0);
    final h = r.height.clamp(0.001, 1.0);
    final widthPx = r.width * canvas.width;
    final heightPx = r.height * canvas.height;
    final nx = (r.x + (localPos.dx / widthPx) * w).clamp(0.0, 1.0);
    final ny = (r.y + (localPos.dy / heightPx) * h).clamp(0.0, 1.0);

    // Trouve l'arête la plus proche en local si distance < seuil.
    int? edgeIndex;
    double bestDist = double.infinity;
    final n = verts.length;
    for (var i = 0; i < n; i++) {
      final a = verts[i];
      final b = verts[(i + 1) % n];
      final d = _distancePointToSegment(localPos, a, b);
      if (d < bestDist) {
        bestDist = d;
        edgeIndex = i;
      }
    }
    final shortest = math.min(widthPx, heightPx);
    if (bestDist > shortest * 0.20) edgeIndex = null;

    final result = await _annotationDialog(
      title: 'Nouveau repère',
      contextLabel:
          _annotationContextLabel(r, null, wallEdgeIndex: edgeIndex),
      initialTitle: '',
      initialDescription: '',
    );
    if (result == null || result.delete) return;
    if (result.title.isEmpty && result.description.isEmpty) return;
    setState(() {
      widget.plan.annotations.add(PlanAnnotation.create(
        roomId: r.id,
        wallSide: null,
        x: nx,
        y: ny,
        title: result.title,
        description: result.description,
        wallEdgeIndex: edgeIndex,
      ));
    });
    widget.onChanged();
  }

  static double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return (p - a).distance;
    final t =
        (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2).clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - proj).distance;
  }

  RoomShape _snap(RoomShape r) => RoomShape(
        id: r.id,
        name: r.name,
        x: r.x,
        y: r.y,
        width: r.width,
        height: r.height,
        colorIndex: r.colorIndex,
        hiddenWalls: List<String>.from(r.hiddenWalls),
        vertices:
            r.vertices == null ? null : List<double>.from(r.vertices!),
      );

  Widget _wallHandle(RoomShape r, _WallSide side, Size canvas, bool wallHidden) {
    const handleColor = AppColors.primary;
    Widget handle;
    final mode = switch (side) {
      _WallSide.top => _DragMode.resizeTop,
      _WallSide.right => _DragMode.resizeRight,
      _WallSide.bottom => _DragMode.resizeBottom,
      _WallSide.left => _DragMode.resizeLeft,
    };
    final isHorizontal = side == _WallSide.top || side == _WallSide.bottom;
    handle = Container(
      width: isHorizontal ? 48 : 18,
      height: isHorizontal ? 18 : 48,
      decoration: BoxDecoration(
        color: wallHidden ? Colors.white : handleColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: wallHidden ? handleColor : Colors.white,
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: wallHidden
          ? const Icon(Icons.add, size: 12, color: handleColor)
          : null,
    );
    final detector = GestureDetector(
      onPanStart: (d) {
        widget.onSelect(r.id);
        _dragMode = mode;
        _dragStart = d.globalPosition;
        _dragSnapshot = _snap(r);
      },
      onPanUpdate: (d) => _onPanUpdate(r, d.globalPosition, canvas),
      onPanEnd: (_) => _onPanEnd(),
      onTap: widget.readOnly ? null : () => _showWallEditDialog(r, side),
      onLongPress: () => _toggleWallHidden(r, side),
      child: handle,
    );
    return switch (side) {
      _WallSide.top => Positioned(
          top: -9,
          left: 0,
          right: 0,
          child: Center(child: detector),
        ),
      _WallSide.bottom => Positioned(
          bottom: -9,
          left: 0,
          right: 0,
          child: Center(child: detector),
        ),
      _WallSide.left => Positioned(
          left: -9,
          top: 0,
          bottom: 0,
          child: Center(child: detector),
        ),
      _WallSide.right => Positioned(
          right: -9,
          top: 0,
          bottom: 0,
          child: Center(child: detector),
        ),
    };
  }

  void _onTap(Offset pos, Size canvas) {
    // Tap sur le canvas vide : déselectionne.
    widget.onSelect(null);
  }

  /// Échelle réelle du canvas (12 m × 12 m).
  static const double _wallScaleMeters = 12.0;

  /// Distance (en proportion du canevas) en deçà de laquelle un mur
  /// s'aligne automatiquement sur le mur d'une pièce voisine.
  static const double _snapThreshold = 0.02;

  /// Affiche un dialog permettant de voir/modifier la longueur d'un mur
  /// et de basculer l'orientation de la pièce (horizontale ↔ verticale).
  Future<void> _showWallEditDialog(RoomShape r, _WallSide side) async {
    final isHorizontalWall =
        side == _WallSide.top || side == _WallSide.bottom;
    final currentRatio = isHorizontalWall ? r.width : r.height;
    final currentMeters = currentRatio * _wallScaleMeters;
    final controller = TextEditingController(
      text: currentMeters.toStringAsFixed(2).replaceAll('.', ','),
    );
    String? errorText;

    final result = await showDialog<_WallEditResult>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(
                isHorizontalWall
                    ? 'Mur horizontal (${side == _WallSide.top ? "haut" : "bas"})'
                    : 'Mur vertical (${side == _WallSide.left ? "gauche" : "droit"})',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Longueur actuelle : ${currentMeters.toStringAsFixed(2)} m',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Nouvelle longueur (m)',
                      hintText: 'ex. 3,25',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                      suffixText: 'm',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Orientation de la pièce',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Horizontale'),
                          onPressed: () {
                            Navigator.of(ctx).pop(
                              const _WallEditResult(orientation: 'h'),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.swap_vert),
                          label: const Text('Verticale'),
                          onPressed: () {
                            Navigator.of(ctx).pop(
                              const _WallEditResult(orientation: 'v'),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () {
                    final raw = controller.text.trim().replaceAll(',', '.');
                    final v = double.tryParse(raw);
                    if (v == null || v <= 0) {
                      setLocal(() => errorText = 'Valeur invalide');
                      return;
                    }
                    if (v > _wallScaleMeters) {
                      setLocal(() => errorText =
                          'Maximum ${_wallScaleMeters.toStringAsFixed(0)} m');
                      return;
                    }
                    Navigator.of(ctx)
                        .pop(_WallEditResult(lengthMeters: v));
                  },
                  child: const Text('Appliquer'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    if (result == null) return;

    setState(() {
      if (result.lengthMeters != null) {
        final newRatio =
            (result.lengthMeters! / _wallScaleMeters).clamp(0.001, 1.0);
        if (r.isPolygon) {
          // Pour un polygone, on redimensionne sa bounding-box autour de
          // l'extrémité opposée du mur tapé, en préservant les proportions
          // sur l'axe perpendiculaire.
          final v = r.vertices!;
          if (isHorizontalWall) {
            // anchor x = r.x (gauche), on rescale la largeur.
            final scale = newRatio / r.width;
            for (var i = 0; i < v.length; i += 2) {
              v[i] = (r.x + (v[i] - r.x) * scale).clamp(0.0, 1.0);
            }
          } else {
            final scale = newRatio / r.height;
            for (var i = 0; i < v.length; i += 2) {
              v[i + 1] =
                  (r.y + (v[i + 1] - r.y) * scale).clamp(0.0, 1.0);
            }
          }
          r.recomputeBounds();
        } else {
          if (isHorizontalWall) {
            r.width = newRatio;
            if (r.x + r.width > 1.0) r.x = (1.0 - r.width).clamp(0.0, 1.0);
          } else {
            r.height = newRatio;
            if (r.y + r.height > 1.0) r.y = (1.0 - r.height).clamp(0.0, 1.0);
          }
        }
      }
      if (result.orientation != null && !r.isPolygon) {
        // 'h' : largeur > hauteur ; 'v' : hauteur > largeur.
        final wantH = result.orientation == 'h';
        final isCurrentlyH = r.width >= r.height;
        if (wantH != isCurrentlyH) {
          final cx = r.x + r.width / 2;
          final cy = r.y + r.height / 2;
          final newW = r.height;
          final newH = r.width;
          r.width = newW;
          r.height = newH;
          r.x = (cx - newW / 2).clamp(0.0, 1.0 - newW);
          r.y = (cy - newH / 2).clamp(0.0, 1.0 - newH);
        }
      }
    });
    widget.onChanged();
  }

  void _onPanUpdate(RoomShape r, Offset globalPos, Size canvas) {
    final start = _dragStart;
    final snap = _dragSnapshot;
    if (start == null || snap == null) return;
    final dx = (globalPos.dx - start.dx) / canvas.width / _zoom;
    final dy = (globalPos.dy - start.dy) / canvas.height / _zoom;
    const minSize = 0.001;
    setState(() {
      switch (_dragMode) {
        case _DragMode.move:
          if (r.isPolygon && snap.vertices != null) {
            final v = snap.vertices!;
            // Calcule un dx/dy borné pour que le polygone reste dans [0,1].
            double minX = v[0], maxX = v[0], minY = v[1], maxY = v[1];
            for (var i = 0; i < v.length; i += 2) {
              if (v[i] < minX) minX = v[i];
              if (v[i] > maxX) maxX = v[i];
              if (v[i + 1] < minY) minY = v[i + 1];
              if (v[i + 1] > maxY) maxY = v[i + 1];
            }
            final cdx = dx.clamp(-minX, 1.0 - maxX);
            final cdy = dy.clamp(-minY, 1.0 - maxY);
            final out = <double>[];
            for (var i = 0; i < v.length; i += 2) {
              out.add(v[i] + cdx);
              out.add(v[i + 1] + cdy);
            }
            r.vertices = out;
            r.recomputeBounds();
          } else {
            r.x = (snap.x + dx).clamp(0.0, 1.0 - snap.width);
            r.y = (snap.y + dy).clamp(0.0, 1.0 - snap.height);
            _applyMoveSnap(r);
          }
          break;
        case _DragMode.resizeVertex:
          final idx = _dragVertexIndex;
          if (idx == null || !r.isPolygon || snap.vertices == null) break;
          final v = snap.vertices!;
          final n = v.length ~/ 2;
          final i = ((idx % n) + n) % n;
          final newX = (v[i * 2] + dx).clamp(0.0, 1.0);
          final newY = (v[i * 2 + 1] + dy).clamp(0.0, 1.0);
          final cur = List<double>.from(r.vertices!);
          cur[i * 2] = newX;
          cur[i * 2 + 1] = newY;
          r.vertices = cur;
          r.recomputeBounds();
          break;
        case _DragMode.resizeRight:
          final raw = (snap.width + dx).clamp(minSize, 1.0 - snap.x);
          r.width = _snapEdge(snap.x + raw, r.id) - snap.x;
          r.width = r.width.clamp(minSize, 1.0 - snap.x);
          break;
        case _DragMode.resizeBottom:
          final raw = (snap.height + dy).clamp(minSize, 1.0 - snap.y);
          r.height =
              _snapEdge(snap.y + raw, r.id, vertical: true) - snap.y;
          r.height = r.height.clamp(minSize, 1.0 - snap.y);
          break;
        case _DragMode.resizeLeft:
          final maxDx = snap.width - minSize;
          final clampedDx = dx.clamp(-snap.x, maxDx);
          final rawX = snap.x + clampedDx;
          final snappedX = _snapEdge(rawX, r.id);
          r.x = snappedX.clamp(0.0, snap.x + snap.width - minSize);
          r.width = snap.width - (r.x - snap.x);
          break;
        case _DragMode.resizeTop:
          final maxDy = snap.height - minSize;
          final clampedDy = dy.clamp(-snap.y, maxDy);
          final rawY = snap.y + clampedDy;
          final snappedY = _snapEdge(rawY, r.id, vertical: true);
          r.y = snappedY.clamp(0.0, snap.y + snap.height - minSize);
          r.height = snap.height - (r.y - snap.y);
          break;
        case null:
          break;
      }
    });
  }

  /// Pour un déplacement : décale la pièce de quelques pourcents pour que
  /// l'un de ses 4 bords s'aligne sur un bord d'une autre pièce.
  void _applyMoveSnap(RoomShape r) {
    final t = _snapThreshold;
    double bestDx = 0, bestDxAbs = t;
    double bestDy = 0, bestDyAbs = t;
    final l = r.x, rr = r.x + r.width;
    final tt = r.y, bb = r.y + r.height;
    for (final o in widget.plan.rooms) {
      if (o.id == r.id) continue;
      final oL = o.x, oR = o.x + o.width;
      final oT = o.y, oB = o.y + o.height;
      for (final cand in [oL - l, oR - l, oL - rr, oR - rr]) {
        if (cand.abs() < bestDxAbs) {
          bestDxAbs = cand.abs();
          bestDx = cand;
        }
      }
      for (final cand in [oT - tt, oB - tt, oT - bb, oB - bb]) {
        if (cand.abs() < bestDyAbs) {
          bestDyAbs = cand.abs();
          bestDy = cand;
        }
      }
    }
    r.x = (r.x + bestDx).clamp(0.0, 1.0 - r.width);
    r.y = (r.y + bestDy).clamp(0.0, 1.0 - r.height);
  }

  /// Pour un redimensionnement : retourne la position alignée la plus
  /// proche (mur d'une autre pièce) du bord [edge], sinon [edge].
  double _snapEdge(double edge, String excludeId,
      {bool vertical = false}) {
    final t = _snapThreshold;
    double best = edge;
    double bestDist = t;
    for (final o in widget.plan.rooms) {
      if (o.id == excludeId) continue;
      final candidates = vertical
          ? [o.y, o.y + o.height]
          : [o.x, o.x + o.width];
      for (final c in candidates) {
        if ((c - edge).abs() < bestDist) {
          bestDist = (c - edge).abs();
          best = c;
        }
      }
    }
    return best;
  }

  void _onPanEnd() {
    _dragMode = null;
    _dragStart = null;
    _dragSnapshot = null;
    _dragVertexIndex = null;
    widget.onChanged();
  }

  void _addRoom(String label) {
    final idx = widget.plan.rooms.length % _colors.length;
    final offset = 0.02 * (widget.plan.rooms.length % 5);
    final terrainItem = _isTerrain ? _terrainItemByName(label) : null;
    final isL = label == 'Pièce en L';
    final isT = label == 'Pièce en T';
    final isGarage =
        label.toLowerCase().contains('garage') && !isL && !isT;
    final defW = (isL || isT) ? 0.20 : (isGarage ? 0.22 : 0.15);
    final defH = (isL || isT) ? 0.20 : (isGarage ? 0.18 : 0.12);
    final w = terrainItem?.width ?? defW;
    final h = terrainItem?.height ?? defH;
    final x = (0.5 - w / 2 + offset).clamp(0.0, 1.0 - w);
    final y = (0.5 - h / 2 + offset).clamp(0.0, 1.0 - h);
    final room = RoomShape.create(
      name: label,
      x: x,
      y: y,
      width: w,
      height: h,
      colorIndex: idx,
    );
    if (isGarage) {
      // Porte de garage par défaut : mur du bas, occupe 60 % de sa longueur,
      // centrée. L'utilisateur peut ensuite la déplacer/redimensionner via
      // la sidebar.
      room.garageDoorSide = 'bottom';
      room.garageDoorRatio = 0.6;
    }
    if (isL) {
      room.vertices = <double>[
        x, y,
        x + w / 2, y,
        x + w / 2, y + h / 2,
        x + w, y + h / 2,
        x + w, y + h,
        x, y + h,
      ];
    } else if (isT) {
      room.vertices = <double>[
        x, y,
        x + w, y,
        x + w, y + h * 0.4,
        x + w * 0.7, y + h * 0.4,
        x + w * 0.7, y + h,
        x + w * 0.3, y + h,
        x + w * 0.3, y + h * 0.4,
        x, y + h * 0.4,
      ];
    }
    setState(() {
      widget.plan.rooms.add(room);
      widget.onSelect(room.id);
    });
    widget.onChanged();
  }

  void _rotateSelected() {
    final r = _selectedRoom();
    if (r == null) return;
    if (!r.isPolygon) r.convertToPolygon();
    final v = List<double>.from(r.vertices!);
    final n = v.length ~/ 2;
    double cx = 0, cy = 0;
    for (var i = 0; i < n; i++) {
      cx += v[i * 2];
      cy += v[i * 2 + 1];
    }
    cx /= n;
    cy /= n;
    const angle = math.pi / 4;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final out = <double>[];
    for (var i = 0; i < n; i++) {
      final dx = v[i * 2] - cx;
      final dy = v[i * 2 + 1] - cy;
      out.add(cx + dx * cosA - dy * sinA);
      out.add(cy + dx * sinA + dy * cosA);
    }
    double minX = out[0], maxX = out[0], minY = out[1], maxY = out[1];
    for (var i = 0; i < out.length; i += 2) {
      if (out[i] < minX) minX = out[i];
      if (out[i] > maxX) maxX = out[i];
      if (out[i + 1] < minY) minY = out[i + 1];
      if (out[i + 1] > maxY) maxY = out[i + 1];
    }
    double sx = 0, sy = 0;
    if (minX < 0) sx = -minX;
    if (maxX + sx > 1) sx = 1 - maxX;
    if (minY < 0) sy = -minY;
    if (maxY + sy > 1) sy = 1 - maxY;
    for (var i = 0; i < out.length; i += 2) {
      out[i] += sx;
      out[i + 1] += sy;
    }
    setState(() {
      r.vertices = out;
      r.recomputeBounds();
    });
    widget.onChanged();
  }

  Future<void> _renameSelected() async {
    final r = _selectedRoom();
    if (r == null) return;
    final ctrl = TextEditingController(text: r.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer la pièce'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (newName == null) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final group = _groupOf(r);
    setState(() {
      for (final g in group) {
        g.name = trimmed;
      }
    });
    widget.onChanged();
  }

  void _deleteSelected() {
    final r = _selectedRoom();
    if (r == null) return;
    final groupIds = _groupOf(r).map((g) => g.id).toSet();
    setState(() {
      widget.plan.rooms.removeWhere((x) => groupIds.contains(x.id));
      widget.plan.annotations
          .removeWhere((a) => groupIds.contains(a.roomId));
      widget.onSelect(null);
    });
    widget.onChanged();
  }

  void _colorSelected() {
    final r = _selectedRoom();
    if (r == null) return;
    final group = _groupOf(r);
    final next = (r.colorIndex + 1) % _colors.length;
    setState(() {
      for (final g in group) {
        g.colorIndex = next;
      }
    });
    widget.onChanged();
  }

  void _setColorIndex(int idx) {
    final r = _selectedRoom();
    if (r == null) return;
    final group = _groupOf(r);
    setState(() {
      for (final g in group) {
        g.colorIndex = idx % _colors.length;
      }
    });
    widget.onChanged();
  }

  // ── API publique exposée à la sidebar externe ────────────────────────────
  void addRoomFromPalette(String label) => _addRoom(label);
  void setRoomColorIndex(int idx) => _setColorIndex(idx);
  Future<void> renameSelected() => _renameSelected();
  void deleteSelected() => _deleteSelected();
  void rotateSelected() => _rotateSelected();
  void toggleFormeLibre() => _toggleShapeMode();
  void zoomInExt() => _zoomIn();
  void zoomOutExt() => _zoomOut();
  bool get canZoomInExt => _zoom < _zoomMax;
  bool get canZoomOutExt => _zoom > _zoomMin;
  static List<Color> get paletteColors => _colors;

  /// Bascule la pièce sélectionnée entre rectangle et polygone (forme libre).
  void _toggleShapeMode() {
    final r = _selectedRoom();
    if (r == null) return;
    setState(() {
      if (r.isPolygon) {
        r.convertToRectangle();
      } else {
        r.convertToPolygon();
      }
    });
    widget.onChanged();
  }

  /// Menu contextuel ouvert au long-press sur une pièce : raccourcis vers
  /// les actions courantes (renommer, couleur, forme, supprimer).
  Future<void> _showRoomContextMenu(RoomShape r) async {
    if (widget.readOnly) return;
    widget.onSelect(r.id);
    final isPoly = r.isPolygon;
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                r.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Renommer'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            if (!_isTerrain)
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Changer la couleur'),
                onTap: () => Navigator.of(ctx).pop('color'),
              ),
            if (!_isTerrain)
              ListTile(
                leading: Icon(isPoly
                    ? Icons.crop_square
                    : Icons.format_shapes_outlined),
                title: Text(isPoly
                    ? 'Repasser en rectangle'
                    : 'Modifier la forme (libre)'),
                subtitle: Text(isPoly
                    ? 'Conservera la bounding-box'
                    : 'Permet de déplacer chaque coin'),
                onTap: () => Navigator.of(ctx).pop('shape'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: AppColors.error),
              title: const Text('Supprimer cette pièce',
                  style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Annuler'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        await _renameSelected();
        break;
      case 'color':
        _colorSelected();
        break;
      case 'shape':
        _toggleShapeMode();
        break;
      case 'delete':
        _deleteSelected();
        break;
    }
  }

  // ── Annotations ────────────────────────────────────────────────────────

  Widget _buildPin(PlanAnnotation a, int number, Size canvas) {
    final px = a.x * canvas.width;
    final py = a.y * canvas.height;
    return Positioned(
      left: px - 14,
      top: py - 14,
      child: GestureDetector(
        onTap: () => _editAnnotation(a),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.error,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            'A$number',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createAnnotation(
      RoomShape r, Offset localPos, Size canvas) async {
    final pixelLeft = r.x * canvas.width;
    final pixelTop = r.y * canvas.height;
    final nx = ((pixelLeft + localPos.dx) / canvas.width).clamp(0.0, 1.0);
    final ny = ((pixelTop + localPos.dy) / canvas.height).clamp(0.0, 1.0);

    final fracX = (localPos.dx / (r.width * canvas.width)).clamp(0.0, 1.0);
    final fracY = (localPos.dy / (r.height * canvas.height)).clamp(0.0, 1.0);
    String? wallSide;
    final dists = {
      'left': fracX,
      'right': 1 - fracX,
      'top': fracY,
      'bottom': 1 - fracY,
    };
    final closest =
        dists.entries.reduce((a, b) => a.value < b.value ? a : b);
    if (closest.value < 0.25) wallSide = closest.key;

    final result = await _annotationDialog(
      title: 'Nouveau repère',
      contextLabel: _annotationContextLabel(r, wallSide),
      initialTitle: '',
      initialDescription: '',
    );
    if (result == null || result.delete) return;
    if (result.title.isEmpty && result.description.isEmpty) return;
    setState(() {
      widget.plan.annotations.add(PlanAnnotation.create(
        roomId: r.id,
        wallSide: wallSide,
        x: nx,
        y: ny,
        title: result.title,
        description: result.description,
      ));
    });
    widget.onChanged();
  }

  Future<void> _editAnnotation(PlanAnnotation a) async {
    final r = widget.plan.rooms.cast<RoomShape?>().firstWhere(
          (x) => x?.id == a.roomId,
          orElse: () => null,
        );
    final result = await _annotationDialog(
      title: 'Repère',
      contextLabel: r == null
          ? '—'
          : _annotationContextLabel(
              r,
              a.wallSide,
              wallEdgeIndex: a.wallEdgeIndex,
            ),
      initialTitle: a.title,
      initialDescription: a.description,
      canDelete: true,
    );
    if (result == null) return;
    setState(() {
      if (result.delete) {
        widget.plan.annotations.removeWhere((x) => x.id == a.id);
      } else {
        a.title = result.title;
        a.description = result.description;
      }
    });
    widget.onChanged();
  }

  String _annotationContextLabel(
    RoomShape r,
    String? wallSide, {
    int? wallEdgeIndex,
  }) {
    final wallNumbers = _computeWallNumbers();
    if (r.isPolygon) {
      if (wallEdgeIndex == null) return 'Pièce : ${r.name} (intérieur)';
      final n = wallNumbers[r.id]?.byEdgeIndex[wallEdgeIndex];
      final mLabel = n == null ? 'mur masqué' : 'M$n';
      return 'Pièce : ${r.name} · $mLabel';
    }
    if (wallSide == null) return 'Pièce : ${r.name} (intérieur)';
    final side = _WallSide.values.firstWhere(
      (s) => s.name == wallSide,
      orElse: () => _WallSide.top,
    );
    final n = wallNumbers[r.id]?.bySide[side];
    final mLabel = n == null ? 'mur partagé' : 'M$n';
    return 'Pièce : ${r.name} · $mLabel';
  }

  Future<_AnnotationResult?> _annotationDialog({
    required String title,
    required String contextLabel,
    required String initialTitle,
    required String initialDescription,
    bool canDelete = false,
  }) async {
    final titleCtrl = TextEditingController(text: initialTitle);
    final descCtrl = TextEditingController(text: initialDescription);
    return showDialog<_AnnotationResult>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              contextLabel,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Titre court'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Détails'),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          if (canDelete)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(
                _AnnotationResult(
                    title: '', description: '', delete: true),
              ),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Supprimer'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_AnnotationResult(
              title: titleCtrl.text.trim(),
              description: descCtrl.text.trim(),
            )),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _AnnotationResult {
  final String title;
  final String description;
  final bool delete;
  _AnnotationResult({
    required this.title,
    required this.description,
    this.delete = false,
  });
}

enum _DragMode {
  move,
  resizeTop,
  resizeRight,
  resizeBottom,
  resizeLeft,
  resizeVertex,
}

enum _WallSide { top, right, bottom, left }

/// Résultat du dialog d'édition de mur : nouvelle longueur (en mètres) et/ou
/// orientation cible ('h' = horizontale, 'v' = verticale).
class _WallEditResult {
  final double? lengthMeters;
  final String? orientation;
  const _WallEditResult({this.lengthMeters, this.orientation});
}

/// Numérotation des murs : un rectangle utilise [bySide], un polygone
/// utilise [byEdgeIndex]. Une seule des deux maps est non vide par pièce.
class _WallNumbers {
  final Map<_WallSide, int> bySide;
  final Map<int, int> byEdgeIndex;
  const _WallNumbers({
    this.bySide = const {},
    this.byEdgeIndex = const {},
  });
  bool get isEmpty => bySide.isEmpty && byEdgeIndex.isEmpty;
}

class _TerrainItem {
  final String name;
  final IconData icon;
  final Color color;
  final double width;
  final double height;
  const _TerrainItem(
      this.name, this.icon, this.color, this.width, this.height);
}

class _TerrainContent extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TerrainContent({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final compact = c.maxHeight < 56 || c.maxWidth < 64;
        final iconSize = compact ? 18.0 : 28.0;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: Colors.black87),
            if (!compact) const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFFAFBFC);
    canvas.drawRect(Offset.zero & size, bg);
    final paint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 0.5;
    const step = 20.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Peint un polygone (vertices en coords locales) avec :
/// - un remplissage [fill]
/// - des arêtes en [borderColor] de [borderWidth] (sauf indices dans
///   [hiddenEdges] qui ne sont pas tracées).
class _PolygonPainter extends CustomPainter {
  final List<Offset> vertices;
  final Color fill;
  final Color borderColor;
  final double borderWidth;
  final Set<int> hiddenEdges;

  _PolygonPainter({
    required this.vertices,
    required this.fill,
    required this.borderColor,
    required this.borderWidth,
    required this.hiddenEdges,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (vertices.length < 3) return;
    final path = Path()..moveTo(vertices[0].dx, vertices[0].dy);
    for (var i = 1; i < vertices.length; i++) {
      path.lineTo(vertices[i].dx, vertices[i].dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    final stroke = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final n = vertices.length;
    for (var i = 0; i < n; i++) {
      if (hiddenEdges.contains(i)) continue;
      final a = vertices[i];
      final b = vertices[(i + 1) % n];
      canvas.drawLine(a, b, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _PolygonPainter old) {
    if (old.fill != fill ||
        old.borderColor != borderColor ||
        old.borderWidth != borderWidth ||
        old.vertices.length != vertices.length ||
        old.hiddenEdges.length != hiddenEdges.length) {
      return true;
    }
    for (var i = 0; i < vertices.length; i++) {
      if (old.vertices[i] != vertices[i]) return true;
    }
    return !old.hiddenEdges.containsAll(hiddenEdges);
  }
}

class _Toolbar extends StatelessWidget {
  final RoomShape? selected;
  final bool readOnly;
  final bool annotateMode;
  final double zoom;
  final bool canZoomIn;
  final bool canZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onToggleAnnotate;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onColor;
  final VoidCallback onToggleShape;
  final VoidCallback onRotate;
  const _Toolbar({
    required this.selected,
    required this.readOnly,
    required this.annotateMode,
    required this.zoom,
    required this.canZoomIn,
    required this.canZoomOut,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onToggleAnnotate,
    required this.onRename,
    required this.onDelete,
    required this.onColor,
    required this.onToggleShape,
    required this.onRotate,
  });

  @override
  Widget build(BuildContext context) {
    final s = selected;
    final zoomLabel = zoom == 1.0 ? '' : ' · ×${zoom.toStringAsFixed(1)}';
    final hint = readOnly
        ? 'Lecture seule — édition réservée au propriétaire$zoomLabel'
        : annotateMode
            ? 'Mode repère : touchez une pièce ou un mur'
            : (s == null
                ? 'Sélectionnez une pièce$zoomLabel'
                : 'Sélection : ${s.name}$zoomLabel');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: annotateMode
            ? AppColors.error.withValues(alpha: 0.06)
            : AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              hint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: annotateMode
                    ? AppColors.error
                    : (s == null
                        ? AppColors.textSecondary
                        : AppColors.textPrimary),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.zoom_out),
                  tooltip: 'Dézoomer',
                  visualDensity: VisualDensity.compact,
                  onPressed: canZoomOut ? onZoomOut : null,
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_in),
                  tooltip: 'Zoomer (centré sur la sélection)',
                  visualDensity: VisualDensity.compact,
                  onPressed: canZoomIn ? onZoomIn : null,
                ),
                if (!readOnly) ...[
                  IconButton(
                    icon: Icon(
                      annotateMode ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                    tooltip: annotateMode
                        ? 'Quitter le mode repère'
                        : 'Poser des repères',
                    color: annotateMode ? AppColors.error : null,
                    visualDensity: VisualDensity.compact,
                    onPressed: onToggleAnnotate,
                  ),
                  IconButton(
                    icon: const Icon(Icons.palette_outlined),
                    tooltip: 'Couleur',
                    visualDensity: VisualDensity.compact,
                    onPressed: (annotateMode || s == null) ? null : onColor,
                  ),
                  IconButton(
                    icon: const Icon(Icons.rotate_right),
                    tooltip: 'Pivoter de 45°',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        (annotateMode || s == null) ? null : onRotate,
                  ),
                  IconButton(
                    icon: Icon(s != null && s.isPolygon
                        ? Icons.crop_square
                        : Icons.format_shapes_outlined),
                    tooltip: s != null && s.isPolygon
                        ? 'Repasser en rectangle'
                        : 'Forme libre (polygone)',
                    visualDensity: VisualDensity.compact,
                    onPressed: (annotateMode || s == null)
                        ? null
                        : onToggleShape,
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Renommer',
                    visualDensity: VisualDensity.compact,
                    onPressed: (annotateMode || s == null) ? null : onRename,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Supprimer',
                    visualDensity: VisualDensity.compact,
                    onPressed: (annotateMode || s == null) ? null : onDelete,
                    color:
                        (annotateMode || s == null) ? null : AppColors.error,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanPad extends StatelessWidget {
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  const _PanPad({
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    required this.onRight,
  });

  Widget _btn(IconData icon, VoidCallback onTap, String tooltip) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.keyboard_arrow_up, onUp, 'Déplacer vers le haut'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _btn(Icons.keyboard_arrow_left, onLeft, 'Déplacer à gauche'),
              const SizedBox(width: 36, height: 36),
              _btn(Icons.keyboard_arrow_right, onRight, 'Déplacer à droite'),
            ],
          ),
          _btn(Icons.keyboard_arrow_down, onDown, 'Déplacer vers le bas'),
        ],
      ),
    );
  }
}

class _CaptureHint extends StatelessWidget {
  final String? captureRoomName;
  final VoidCallback? onClear;

  const _CaptureHint({required this.captureRoomName, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final locked = captureRoomName != null;
    return Container(
      width: double.infinity,
      color: locked
          ? AppColors.primary.withValues(alpha: 0.12)
          : AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Icon(
            locked ? Icons.lock_outline : Icons.touch_app_outlined,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              locked
                  ? 'Pièce sélectionnée : $captureRoomName · touchez un mur '
                      'pour photographier.'
                  : 'Maintenez la pièce pour la verrouiller, puis touchez '
                      'un mur pour la photo.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (locked)
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Changer'),
            ),
        ],
      ),
    );
  }
}

class _WallBadge extends StatelessWidget {
  final String label;
  final int photoCount;
  final bool large;
  const _WallBadge({
    required this.label,
    this.photoCount = 0,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: large
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
              : const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(large ? 6 : 4),
            border: Border.all(
              color: AppColors.primary,
              width: large ? 1.6 : 1,
            ),
            boxShadow: large
                ? const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: large ? 14 : 9,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        if (photoCount > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.white, width: 1),
              ),
              alignment: Alignment.center,
              child: Text(
                '$photoCount',
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Palette extends StatelessWidget {
  final List<String> items;
  final Map<String, IconData> icons;
  final ValueChanged<String> onPick;
  final bool vertical;
  const _Palette({
    required this.items,
    required this.onPick,
    this.icons = const {},
    this.vertical = false,
  });

  Widget _chip(String label) {
    final iconData = icons[label] ?? Icons.add;
    return InkWell(
      onTap: () => onPick(label),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconData, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return Container(
        color: AppColors.surface,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) => _chip(items[i]),
        ),
      );
    }
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) => _chip(items[i]),
      ),
    );
  }
}

/// Overlay visuel pour la porte de garage : bande épaisse contrastée sur le
/// mur désigné. Quand `showHandle` est `true` (pièce sélectionnée hors mode
/// lecture), affiche une poignée à chaque extrémité pour la redimensionner.
class _GarageDoorOverlay extends StatefulWidget {
  final RoomShape room;
  final bool showHandle;
  final ValueChanged<double> onResize;

  const _GarageDoorOverlay({
    required this.room,
    required this.showHandle,
    required this.onResize,
  });

  @override
  State<_GarageDoorOverlay> createState() => _GarageDoorOverlayState();
}

class _GarageDoorOverlayState extends State<_GarageDoorOverlay> {
  double? _dragStartRatio;
  double? _dragStartPx;
  double? _dragWallLength;
  bool _dragFromLeft = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.room;
    final side = r.garageDoorSide ?? 'bottom';
    final ratio = (r.garageDoorRatio ?? 0.5).clamp(0.1, 1.0);

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      // Détermine la position de la porte sur le mur désigné. Elle est
      // centrée sur le mur. Épaisseur visuelle : un peu plus épaisse que le
      // mur normal pour bien voir l'ouverture.
      const thickness = 6.0;
      double left, top, doorWidth, doorHeight;
      switch (side) {
        case 'top':
          doorWidth = w * ratio;
          doorHeight = thickness;
          left = (w - doorWidth) / 2;
          top = -thickness / 2;
        case 'right':
          doorWidth = thickness;
          doorHeight = h * ratio;
          left = w - thickness / 2;
          top = (h - doorHeight) / 2;
        case 'left':
          doorWidth = thickness;
          doorHeight = h * ratio;
          left = -thickness / 2;
          top = (h - doorHeight) / 2;
        case 'bottom':
        default:
          doorWidth = w * ratio;
          doorHeight = thickness;
          left = (w - doorWidth) / 2;
          top = h - thickness / 2;
      }

      final isHorizontal = side == 'top' || side == 'bottom';
      final wallLength = isHorizontal ? w : h;

      void startDrag(DragStartDetails d, {required bool fromLeft}) {
        _dragStartRatio = ratio;
        _dragWallLength = wallLength;
        _dragFromLeft = fromLeft;
        _dragStartPx = isHorizontal ? d.globalPosition.dx : d.globalPosition.dy;
      }

      void updateDrag(DragUpdateDetails d) {
        if (_dragStartRatio == null ||
            _dragStartPx == null ||
            _dragWallLength == null) return;
        final px = isHorizontal ? d.globalPosition.dx : d.globalPosition.dy;
        final deltaPx = px - _dragStartPx!;
        final deltaRatio = (deltaPx / _dragWallLength!) * 2;
        // Les deux poignées sont symétriques (la porte reste centrée), donc
        // un drag depuis n'importe quelle extrémité agrandit/réduit. Le sens
        // dépend du côté tiré.
        final signedDelta = _dragFromLeft ? -deltaRatio : deltaRatio;
        final next =
            (_dragStartRatio! + signedDelta).clamp(0.1, 1.0).toDouble();
        widget.onResize(next);
      }

      return Stack(
        children: [
          // Bande porte (couleur contrastée pour bien la voir).
          Positioned(
            left: left,
            top: top,
            width: doorWidth,
            height: doorHeight,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Poignées de redimensionnement aux deux extrémités. Visibles
          // uniquement quand la pièce est sélectionnée et qu'on n'est pas
          // en lecture seule.
          if (widget.showHandle) ...[
            Positioned(
              left: isHorizontal ? left - 6 : left - 4,
              top: isHorizontal ? top - 4 : top - 6,
              width: 14,
              height: 14,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => startDrag(d, fromLeft: true),
                onPanUpdate: updateDrag,
                child: const _DoorHandle(),
              ),
            ),
            Positioned(
              left: isHorizontal ? left + doorWidth - 8 : left - 4,
              top: isHorizontal ? top - 4 : top + doorHeight - 8,
              width: 14,
              height: 14,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => startDrag(d, fromLeft: false),
                onPanUpdate: updateDrag,
                child: const _DoorHandle(),
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _DoorHandle extends StatelessWidget {
  const _DoorHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.accent, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 2),
        ],
      ),
    );
  }
}
