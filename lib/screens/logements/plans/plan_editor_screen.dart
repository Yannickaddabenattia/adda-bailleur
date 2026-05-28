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
  String? _selectedWallId;
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
                    selectedWallId: _selectedWallId,
                    readOnly: widget.readOnly,
                    allowWallPhotoCapture: widget.allowWallPhotoCapture,
                    etatId: widget.etatId,
                    externalChrome: showExternalSidebar,
                    onSelect: (id) =>
                        setState(() => _selectedRoomId = id),
                    onSelectWall: (id) =>
                        setState(() => _selectedWallId = id),
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
                    state.startFreeDraw();
                  },
                  onStartCalibrate: () {
                    final state = _drawerKey.currentState;
                    if (state == null) return;
                    state.startCalibration();
                  },
                  onClearCalibrate: () {
                    final state = _drawerKey.currentState;
                    if (state == null) return;
                    state.clearCalibration();
                  },
                  onStartDrawWall: () {
                    final state = _drawerKey.currentState;
                    if (state == null) return;
                    state.startDrawWall();
                  },
                  onStartDrawVirtualWall: () {
                    final state = _drawerKey.currentState;
                    if (state == null) return;
                    state.startDrawWall(virtual: true);
                  },
                  selectedWall: _findSelectedWall(plan),
                  onRenameWall: () {
                    final state = _drawerKey.currentState;
                    if (state == null) return;
                    state.renameSelectedWall();
                  },
                  onDeleteWall: () {
                    final state = _drawerKey.currentState;
                    if (state == null) return;
                    state.deleteSelectedWall();
                  },
                  onToggleWallVirtual: () {
                    final state = _drawerKey.currentState;
                    if (state == null) return;
                    state.toggleSelectedWallVirtual();
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

  FreeWall? _findSelectedWall(PlanLogement plan) {
    final id = _selectedWallId;
    if (id == null) return null;
    for (final w in plan.freeWalls) {
      if (w.id == id) return w;
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
  final FreeWall? selectedWall;
  final bool isTerrain;
  final String? etatId;
  final ValueChanged<String> onAddRoom;
  final VoidCallback onAddFormeLibre;
  final VoidCallback onStartCalibrate;
  final VoidCallback onClearCalibrate;
  final VoidCallback onStartDrawWall;
  final VoidCallback onStartDrawVirtualWall;
  final VoidCallback onRenameWall;
  final VoidCallback onDeleteWall;
  final VoidCallback onToggleWallVirtual;
  final ValueChanged<int> onPickColor;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onRotate;
  final ValueChanged<WallPhoto> onOpenWall;

  const _PlanSidebar({
    required this.plan,
    required this.selected,
    required this.selectedWall,
    required this.isTerrain,
    required this.onAddRoom,
    required this.onAddFormeLibre,
    required this.onStartCalibrate,
    required this.onClearCalibrate,
    required this.onStartDrawWall,
    required this.onStartDrawVirtualWall,
    required this.onRenameWall,
    required this.onDeleteWall,
    required this.onToggleWallVirtual,
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
              label: '✏️ Tracer une pièce',
              onTap: onAddFormeLibre,
            ),
            const SizedBox(height: 8),
            _DashedAddButton(
              label: '🧱 Tracer un mur',
              onTap: onStartDrawWall,
            ),
            const SizedBox(height: 8),
            _DashedAddButton(
              label: '┄ Tracer un mur virtuel',
              onTap: onStartDrawVirtualWall,
            ),
            const SizedBox(height: 22),
          ],
          const _SectionHeader('Échelle du plan'),
          const SizedBox(height: 10),
          _ScaleCard(
            plan: plan,
            onCalibrate: onStartCalibrate,
            onClear: onClearCalibrate,
          ),
          const SizedBox(height: 22),
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
              areaM2: _roomAreaForLabel(selected!, plan),
              perimM: _perimeterForLabel(selected!, plan),
            ),
          if (selectedWall != null) ...[
            const SizedBox(height: 16),
            const _SectionHeader('Mur sélectionné'),
            const SizedBox(height: 10),
            _SelectedWallCard(
              plan: plan,
              wall: selectedWall!,
              onRename: onRenameWall,
              onDelete: onDeleteWall,
              onToggleVirtual: onToggleWallVirtual,
            ),
          ],
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

  /// Échelle utilisée par défaut quand le plan n'est pas calibré (canvas
  /// virtuel de 12 m × 12 m). Sera remplacée par la valeur réelle dès que
  /// l'utilisateur a calibré son plan.
  static const double _defaultMetersPerUnit = 12.0;

  static double _metersPerUnit(PlanLogement plan) =>
      plan.scaleMetersPerUnit ?? _defaultMetersPerUnit;

  static double _roomAreaForLabel(RoomShape r, PlanLogement plan) {
    final m = _metersPerUnit(plan);
    final m2 = m * m;
    if (r.isPolygon && r.vertices != null) {
      final v = r.vertices!;
      double a = 0;
      final n = v.length ~/ 2;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        a += v[i * 2] * v[j * 2 + 1];
        a -= v[j * 2] * v[i * 2 + 1];
      }
      return (a / 2).abs() * m2;
    }
    return r.width * r.height * m2;
  }

  static double _perimeterForLabel(RoomShape r, PlanLogement plan) {
    final m = _metersPerUnit(plan);
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
      return p * m;
    }
    return (r.width + r.height) * 2.0 * m;
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
  final String? selectedWallId;
  final bool readOnly;
  final bool allowWallPhotoCapture;
  final String? etatId;
  final bool externalChrome;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String?> onSelectWall;
  final VoidCallback onChanged;

  const _DrawerView({
    super.key,
    required this.plan,
    required this.selectedRoomId,
    required this.selectedWallId,
    required this.readOnly,
    required this.allowWallPhotoCapture,
    required this.etatId,
    required this.onSelect,
    required this.onSelectWall,
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

  /// Mode « Tracer une pièce » : chaque tap sur le canvas pose un sommet.
  /// Quand l'utilisateur tape près du premier sommet (avec au moins 3 sommets
  /// posés), le polygone se ferme automatiquement.
  bool _freeDrawMode = false;
  final List<Offset> _freeDrawPoints = <Offset>[];

  /// Position courante du curseur (desktop) pour afficher une ligne d'aperçu
  /// entre le dernier sommet posé et le pointeur. Sur mobile, reste null.
  Offset? _freeDrawHover;

  /// Contraint le segment courant à un multiple de 45° par rapport au sommet
  /// précédent. Activable depuis la bannière du mode tracé.
  bool _freeDrawOrthoLock = false;

  /// Rayon (en proportion du canvas) autour du premier sommet où un tap
  /// déclenche la fermeture automatique du polygone.
  static const double _freeDrawCloseRadius = 0.035;

  /// Rayon (en proportion du canvas) autour des sommets / murs existants
  /// pour le magnétisme. Plus petit que la fermeture pour éviter la confusion.
  static const double _freeDrawSnapRadius = 0.02;

  /// Mode « Calibrer l'échelle » : 1ᵉʳ tap pose le sommet de départ, 2ᵉ tap
  /// pose l'arrivée puis un dialog demande la distance réelle en mètres.
  bool _calibrateMode = false;
  Offset? _calibratePoint1;
  Offset? _calibratePoint2;

  /// Mode « Tracer un mur » : tap pose le point A, 2ᵉ tap pose le point B
  /// et le mur libre est créé instantanément (nommé automatiquement selon
  /// la pièce la plus proche).
  bool _drawWallMode = false;
  Offset? _drawWallPoint1;

  /// Si true, le mur en cours de tracé sera créé en virtuel (pointillé,
  /// nommé "Séparation A / B"). Activable depuis le bandeau de tracé.
  bool _drawWallVirtual = false;

  /// Position courante du curseur (normalisée) pendant le mode tracé mur,
  /// pour afficher la ligne d'aperçu entre point1 et le curseur. Null si
  /// pas en mode wall draw ou pas encore de mouvement détecté.
  Offset? _drawWallHover;

  /// Etat du drag en cours sur un mur libre sélectionné.
  _WallDragMode? _wallDragMode;
  Offset? _wallDragStart;
  FreeWall? _wallDragSnapshot;

  /// Distance maximale (en proportion du canvas) pour qu'un tap soit
  /// considéré comme sur un mur libre.
  static const double _wallHitTolerance = 0.015;

  /// `true` quand l'utilisateur est dans un mode de dessin actif (tracer
  /// une pièce, tracer un mur, calibrer). Les pièces existantes doivent
  /// ignorer les taps/pans dans ces modes pour ne pas être sélectionnées
  /// ou bougées par erreur quand on clique près d'elles pour poser un
  /// sommet ou un point de calibration.
  bool get _isInDrawingMode =>
      _freeDrawMode || _calibrateMode || _drawWallMode;

  /// Test si une arête (paire d'Offset) correspond à une arête de la pièce
  /// donnée. Utilisé pour exclure les arêtes de la pièce en cours de drag
  /// dans la détection d'overlap (sinon elle s'auto-superpose).
  bool _edgeBelongsTo(List<Offset> edge, RoomShape r) {
    final roomEdges = _RoomDragOverlapPainter._edgesOf(r);
    for (final re in roomEdges) {
      if ((re[0] == edge[0] && re[1] == edge[1]) ||
          (re[0] == edge[1] && re[1] == edge[0])) {
        return true;
      }
    }
    return false;
  }

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
        // Aperçu du polygone en cours dans le mode tracé.
        final willClose = _freeDrawMode &&
            _freeDrawPoints.length >= 3 &&
            _freeDrawHover != null &&
            (_freeDrawHover! - _freeDrawPoints.first).distance <
                _freeDrawCloseRadius;
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
                    child: MouseRegion(
                      onHover: (_freeDrawMode || _drawWallMode)
                          ? (e) {
                              if (_freeDrawMode) {
                                _updateFreeDrawHover(e.localPosition, size);
                              } else if (_drawWallMode) {
                                _updateDrawWallHover(e.localPosition, size);
                              }
                            }
                          : null,
                      cursor: (_freeDrawMode || _drawWallMode)
                          ? SystemMouseCursors.precise
                          : MouseCursor.defer,
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
                            if (widget.plan.freeWalls.isNotEmpty)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _FreeWallsPainter(
                                      plan: widget.plan,
                                      selectedId: widget.selectedWallId,
                                    ),
                                  ),
                                ),
                              ),
                            // Cotes (dimensions) sur chaque arête de pièce.
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _DimensionsPainter(
                                      plan: widget.plan),
                                ),
                              ),
                            ),
                            // Zones de hit transparentes sur chaque mur libre :
                            // permettent de saisir le mur n'importe où sur sa
                            // longueur (tap = sélection, drag = translation).
                            ..._buildFreeWallHitZones(size),
                            // Poignées du mur sélectionné (drag).
                            if (_selectedWall() != null)
                              ..._buildSelectedWallHandles(
                                  _selectedWall()!, size),
                            if (_freeDrawMode)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _FreeDrawPreviewPainter(
                                      points: _freeDrawPoints,
                                      hover: _freeDrawHover,
                                      closeRadius: _freeDrawCloseRadius,
                                      willClose: willClose,
                                      existingEdges:
                                          _collectExistingEdges(widget.plan),
                                      metersPerUnit: widget
                                              .plan.scaleMetersPerUnit ??
                                          12.0,
                                      isCalibrated:
                                          widget.plan.isCalibrated,
                                    ),
                                  ),
                                ),
                              ),
                            if (_calibrateMode)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _CalibratePreviewPainter(
                                      p1: _calibratePoint1,
                                      p2: _calibratePoint2,
                                    ),
                                  ),
                                ),
                              ),
                            if (_drawWallMode && _drawWallPoint1 != null)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _DrawWallPreviewPainter(
                                      p1: _drawWallPoint1,
                                      hover: _drawWallHover,
                                      isVirtual: _drawWallVirtual,
                                      existingEdges:
                                          _collectExistingEdges(widget.plan),
                                    ),
                                  ),
                                ),
                              ),
                            // Surbrillance des chevauchements pendant qu'on
                            // déplace une pièce existante (drag).
                            if (_dragMode == _DragMode.move &&
                                _selectedRoom() != null)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _RoomDragOverlapPainter(
                                      draggedRoom: _selectedRoom()!,
                                      otherEdges: _collectExistingEdges(
                                              widget.plan)
                                          .where((e) =>
                                              !_edgeBelongsTo(e,
                                                  _selectedRoom()!))
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_drawWallMode)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: _DrawWallBanner(
                    point1Placed: _drawWallPoint1 != null,
                    isVirtual: _drawWallVirtual,
                    onToggleVirtual: toggleDrawWallVirtual,
                    onCancel: cancelDrawWall,
                  ),
                ),
              if (_freeDrawMode)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: _FreeDrawBanner(
                    pointCount: _freeDrawPoints.length,
                    orthoLock: _freeDrawOrthoLock,
                    onToggleOrtho: toggleFreeDrawOrthoLock,
                    onUndoPoint: undoLastFreeDrawPoint,
                    onCancel: cancelFreeDraw,
                    onFinish: _freeDrawPoints.length >= 3
                        ? _finalizeFreeDraw
                        : null,
                  ),
                ),
              if (_calibrateMode)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: _CalibrateBanner(
                    point1Placed: _calibratePoint1 != null,
                    onCancel: cancelCalibration,
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
        onTapUp: (ro || _isInDrawingMode)
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
            : (ro || _annotateMode || _isInDrawingMode)
                ? null
                : () => _showRoomContextMenu(r),
        onPanStart: (ro || _annotateMode || _isInDrawingMode)
            ? null
            : (d) {
                widget.onSelect(r.id);
                _dragMode = _DragMode.move;
                _dragStart = d.globalPosition;
                _dragSnapshot = _snap(r);
              },
        onPanUpdate: (ro || _annotateMode || _isInDrawingMode)
            ? null
            : (d) => _onPanUpdate(r, d.globalPosition, canvas),
        onPanEnd: (ro || _annotateMode || _isInDrawingMode) ? null : (_) => _onPanEnd(),
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
        onTapUp: (ro || _isInDrawingMode)
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
            : (ro || _annotateMode || _isInDrawingMode)
                ? null
                : () => _showRoomContextMenu(r),
        onPanStart: (ro || _annotateMode || _isInDrawingMode)
            ? null
            : (d) {
                widget.onSelect(r.id);
                _dragMode = _DragMode.move;
                _dragStart = d.globalPosition;
                _dragSnapshot = _snap(r);
              },
        onPanUpdate: (ro || _annotateMode || _isInDrawingMode)
            ? null
            : (d) => _onPanUpdate(r, d.globalPosition, canvas),
        onPanEnd: (ro || _annotateMode || _isInDrawingMode) ? null : (_) => _onPanEnd(),
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
      onLongPress: () => _showVertexMenu(r, index),
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

  /// Menu déclenché par long-press sur un sommet : choix entre supprimer
  /// le coin et définir l'angle exact en degrés.
  Future<void> _showVertexMenu(RoomShape r, int index) async {
    if (!r.isPolygon) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Coin'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'angle'),
            child: Row(children: const [
              Icon(Icons.architecture, size: 18),
              SizedBox(width: 10),
              Text("Définir l'angle…"),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: Row(children: [
              Icon(Icons.delete_outline,
                  size: 18, color: AppColors.error),
              const SizedBox(width: 10),
              Text('Supprimer ce coin',
                  style: TextStyle(color: AppColors.error)),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    if (action == 'delete') {
      await _confirmRemoveVertex(r, index);
    } else if (action == 'angle') {
      await _promptVertexAngle(r, index);
    }
  }

  Future<void> _promptVertexAngle(RoomShape r, int index) async {
    if (!r.isPolygon) return;
    final v = r.vertices!;
    final n = v.length ~/ 2;
    final prev = (index - 1 + n) % n;
    final next = (index + 1) % n;
    final ax = v[prev * 2], ay = v[prev * 2 + 1];
    final bx = v[index * 2], by = v[index * 2 + 1];
    final cx = v[next * 2], cy = v[next * 2 + 1];

    final baX = ax - bx, baY = ay - by;
    final bcX = cx - bx, bcY = cy - by;
    final lenBA = math.sqrt(baX * baX + baY * baY);
    final lenBC = math.sqrt(bcX * bcX + bcY * bcY);
    if (lenBA < 1e-6 || lenBC < 1e-6) return;
    final dot = baX * bcX + baY * bcY;
    final cosTheta = (dot / (lenBA * lenBC)).clamp(-1.0, 1.0);
    final currentDeg = math.acos(cosTheta) * 180 / math.pi;

    final controller =
        TextEditingController(text: currentDeg.toStringAsFixed(0));
    String? errorText;

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Angle du coin'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Angle actuel : ${currentDeg.toStringAsFixed(1)}°',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Nouvel angle',
                    hintText: 'ex. 90',
                    suffixText: '°',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final preset in [45, 60, 90, 120, 135])
                      OutlinedButton(
                        onPressed: () =>
                            controller.text = preset.toString(),
                        child: Text('$preset°'),
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
                  if (v == null || v <= 0 || v >= 180) {
                    setLocal(
                        () => errorText = 'Doit être entre 0° et 180° exclus.');
                    return;
                  }
                  Navigator.of(ctx).pop(v);
                },
                child: const Text('Appliquer'),
              ),
            ],
          );
        });
      },
    );
    controller.dispose();
    if (result == null) return;
    _setVertexAngle(r, index, result);
  }

  /// Repositionne le sommet `index` du polygone `r` de sorte que l'angle
  /// formé par les 2 arêtes adjacentes (prev-i et i-next) soit égal à
  /// [angleDegrees]. Les 2 sommets voisins ne bougent pas. Le nouveau
  /// sommet est placé sur la bissectrice perpendiculaire au segment
  /// prev-next, du côté correspondant à la position courante (pour
  /// préserver l'orientation du polygone).
  void _setVertexAngle(RoomShape r, int index, double angleDegrees) {
    if (!r.isPolygon) return;
    final v = List<double>.from(r.vertices!);
    final n = v.length ~/ 2;
    if (n < 3) return;
    final prev = (index - 1 + n) % n;
    final next = (index + 1) % n;
    final ax = v[prev * 2], ay = v[prev * 2 + 1];
    final cx = v[next * 2], cy = v[next * 2 + 1];
    final bxOld = v[index * 2], byOld = v[index * 2 + 1];

    final acLen = math.sqrt((cx - ax) * (cx - ax) + (cy - ay) * (cy - ay));
    if (acLen < 1e-6) return;

    final mx = (ax + cx) / 2;
    final my = (ay + cy) / 2;

    final halfAngle = (angleDegrees * math.pi / 180) / 2;
    final sinH = math.sin(halfAngle);
    final cosH = math.cos(halfAngle);
    if (sinH < 1e-6) return;
    // Distance du milieu de AC au sommet B' (sur la bissectrice ⊥ à AC).
    final d = (acLen / 2) * cosH / sinH;

    final perpX = -(cy - ay) / acLen;
    final perpY = (cx - ax) / acLen;

    final bxOpt1 = mx + d * perpX;
    final byOpt1 = my + d * perpY;
    final bxOpt2 = mx - d * perpX;
    final byOpt2 = my - d * perpY;
    final dist1 = (bxOpt1 - bxOld) * (bxOpt1 - bxOld) +
        (byOpt1 - byOld) * (byOpt1 - byOld);
    final dist2 = (bxOpt2 - bxOld) * (bxOpt2 - bxOld) +
        (byOpt2 - byOld) * (byOpt2 - byOld);
    final newBx = (dist1 < dist2 ? bxOpt1 : bxOpt2).clamp(0.0, 1.0);
    final newBy = (dist1 < dist2 ? byOpt1 : byOpt2).clamp(0.0, 1.0);

    v[index * 2] = newBx;
    v[index * 2 + 1] = newBy;

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < n; i++) {
      if (v[i * 2] < minX) minX = v[i * 2];
      if (v[i * 2] > maxX) maxX = v[i * 2];
      if (v[i * 2 + 1] < minY) minY = v[i * 2 + 1];
      if (v[i * 2 + 1] > maxY) maxY = v[i * 2 + 1];
    }

    setState(() {
      r.vertices = v;
      r.x = minX;
      r.y = minY;
      r.width = maxX - minX;
      r.height = maxY - minY;
    });
    widget.onChanged();
  }

  Future<void> _confirmRemoveVertex(RoomShape r, int index) async {
    if (!r.isPolygon) return;
    final n = (r.vertices?.length ?? 0) ~/ 2;
    if (n <= 3) {
      // Un polygone doit garder au moins 3 sommets.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Un polygone doit conserver au moins 3 sommets.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce sommet ?'),
        content: const Text(
            'La pièce sera recalée sans ce coin. Cette action peut être annulée via Annuler (↶).'),
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
    if (ok == true) _removeVertex(r, index);
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
    if (_freeDrawMode) {
      _handleFreeDrawTap(pos, canvas);
      return;
    }
    if (_calibrateMode) {
      _handleCalibrateTap(pos, canvas);
      return;
    }
    if (_drawWallMode) {
      _handleDrawWallTap(pos, canvas);
      return;
    }
    // Hit-test : tap sur un mur libre = sélectionne ce mur.
    final norm = Offset(
      (pos.dx / canvas.width).clamp(0.0, 1.0),
      (pos.dy / canvas.height).clamp(0.0, 1.0),
    );
    final hit = _wallAt(norm);
    if (hit != null) {
      widget.onSelectWall(hit.id);
      widget.onSelect(null); // priorité au mur sur la pièce
      return;
    }
    // Tap sur le canvas vide : déselectionne tout.
    widget.onSelectWall(null);
    widget.onSelect(null);
  }

  // ───────────────────────────────────────────────────────────────────────
  //   Mode « Tracer un mur » + sélection/drag de murs libres
  // ───────────────────────────────────────────────────────────────────────

  void startDrawWall({bool virtual = false}) {
    if (widget.readOnly) return;
    setState(() {
      _drawWallMode = true;
      _drawWallVirtual = virtual;
      _drawWallPoint1 = null;
      _drawWallHover = null;
      _freeDrawMode = false;
      _freeDrawPoints.clear();
      _calibrateMode = false;
      _calibratePoint1 = null;
      _calibratePoint2 = null;
      _annotateMode = false;
    });
    widget.onSelectWall(null);
    widget.onSelect(null);
  }

  void cancelDrawWall() {
    setState(() {
      _drawWallMode = false;
      _drawWallPoint1 = null;
      _drawWallHover = null;
    });
  }

  void toggleDrawWallVirtual() {
    setState(() => _drawWallVirtual = !_drawWallVirtual);
  }

  /// Bascule l'état "mur virtuel" du mur libre actuellement sélectionné.
  void toggleSelectedWallVirtual() {
    final w = _selectedWall();
    if (w == null) return;
    setState(() => w.isVirtual = !w.isVirtual);
    widget.onChanged();
  }

  void _handleDrawWallTap(Offset pos, Size canvas) {
    final norm = Offset(
      (pos.dx / canvas.width).clamp(0.0, 1.0),
      (pos.dy / canvas.height).clamp(0.0, 1.0),
    );
    final snapped = _snapToExistingGeometry(norm);
    if (_drawWallPoint1 == null) {
      setState(() => _drawWallPoint1 = snapped);
      return;
    }
    // 2ᵉ point : crée le mur si distance > minuscule.
    final p1 = _drawWallPoint1!;
    final p2 = snapped;
    if ((p2 - p1).distance < 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mur trop court — réessaie.')),
      );
      setState(() => _drawWallPoint1 = null);
      return;
    }
    final wall = FreeWall.create(
      x1: p1.dx,
      y1: p1.dy,
      x2: p2.dx,
      y2: p2.dy,
      isVirtual: _drawWallVirtual,
    );
    setState(() {
      widget.plan.freeWalls.add(wall);
      _drawWallMode = false;
      _drawWallPoint1 = null;
    });
    widget.onSelectWall(wall.id);
    widget.onChanged();
  }

  /// Cherche un mur libre dont la distance perpendiculaire à `p` est ≤ tolérance.
  /// Retourne le plus proche, ou null.
  FreeWall? _wallAt(Offset p) {
    FreeWall? best;
    double bestDist = _wallHitTolerance;
    for (final w in widget.plan.freeWalls) {
      final d = _distPointToSegment(
        p,
        Offset(w.x1, w.y1),
        Offset(w.x2, w.y2),
      );
      if (d < bestDist) {
        bestDist = d;
        best = w;
      }
    }
    return best;
  }

  double _distPointToSegment(Offset p, Offset a, Offset b) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final len2 = abx * abx + aby * aby;
    if (len2 < 1e-9) return (p - a).distance;
    var t = ((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / len2;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * abx, a.dy + t * aby);
    return (p - proj).distance;
  }

  FreeWall? _selectedWall() {
    final id = widget.selectedWallId;
    if (id == null) return null;
    for (final w in widget.plan.freeWalls) {
      if (w.id == id) return w;
    }
    return null;
  }

  /// Renomme un mur libre (custom label). Vide → retour à l'auto-nommage.
  Future<void> renameSelectedWall() async {
    final w = _selectedWall();
    if (w == null) return;
    final auto = widget.plan.autoLabelForWall(w);
    final controller = TextEditingController(text: w.customLabel ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le mur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nom auto suggéré : $auto',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom personnalisé (vide = auto)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('__cancel__'),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (result == null || result == '__cancel__') return;
    final clean = result.trim();
    setState(() => w.customLabel = clean.isEmpty ? null : clean);
    widget.onChanged();
  }

  Future<void> deleteSelectedWall() async {
    final w = _selectedWall();
    if (w == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce mur ?'),
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
    setState(() {
      widget.plan.freeWalls.removeWhere((x) => x.id == w.id);
    });
    widget.onSelectWall(null);
    widget.onChanged();
  }

  /// Démarre un drag sur le mur sélectionné. `mode` indique quelle partie
  /// du mur on tire (extrémité 1, extrémité 2, ou corps pour translation).
  void _startWallDrag(_WallDragMode mode, Offset globalPosition) {
    final w = _selectedWall();
    if (w == null) return;
    _wallDragMode = mode;
    _wallDragStart = globalPosition;
    _wallDragSnapshot = FreeWall(
      id: w.id,
      x1: w.x1,
      y1: w.y1,
      x2: w.x2,
      y2: w.y2,
      customLabel: w.customLabel,
    );
  }

  void _updateWallDrag(Offset globalPosition, Size canvas) {
    final w = _selectedWall();
    if (w == null || _wallDragSnapshot == null || _wallDragStart == null) {
      return;
    }
    final dx = (globalPosition.dx - _wallDragStart!.dx) / canvas.width;
    final dy = (globalPosition.dy - _wallDragStart!.dy) / canvas.height;
    final s = _wallDragSnapshot!;
    setState(() {
      switch (_wallDragMode) {
        case _WallDragMode.endpoint1:
          w.x1 = (s.x1 + dx).clamp(0.0, 1.0);
          w.y1 = (s.y1 + dy).clamp(0.0, 1.0);
          break;
        case _WallDragMode.endpoint2:
          w.x2 = (s.x2 + dx).clamp(0.0, 1.0);
          w.y2 = (s.y2 + dy).clamp(0.0, 1.0);
          break;
        case _WallDragMode.body:
          // Translation : on déplace les 2 extrémités du même delta, en
          // bornant pour ne pas sortir du canvas.
          final maxDxPos = 1.0 - math.max(s.x1, s.x2);
          final minDxNeg = -math.min(s.x1, s.x2);
          final maxDyPos = 1.0 - math.max(s.y1, s.y2);
          final minDyNeg = -math.min(s.y1, s.y2);
          final adx = dx.clamp(minDxNeg, maxDxPos);
          final ady = dy.clamp(minDyNeg, maxDyPos);
          w.x1 = s.x1 + adx;
          w.y1 = s.y1 + ady;
          w.x2 = s.x2 + adx;
          w.y2 = s.y2 + ady;
          break;
        case null:
          break;
      }
    });
  }

  void _endWallDrag() {
    if (_wallDragMode != null) {
      widget.onChanged();
    }
    _wallDragMode = null;
    _wallDragStart = null;
    _wallDragSnapshot = null;
  }

  /// Construit les widgets de poignées (drag handles) à afficher quand un
  /// mur libre est sélectionné : extrémité 1, extrémité 2, et "poignée corps"
  /// au milieu pour la translation. Chaque poignée est un GestureDetector
  /// avec pan handlers.
  /// Menu déclenché par long-press sur un mur libre : permet de prendre
  /// ou consulter les photos rattachées à ce mur (utile dans le contexte
  /// EDL pour documenter visuellement une cloison ajoutée).
  Future<void> _onFreeWallLongPress(FreeWall w) async {
    final photos = _photosForFreeWall(w.id);
    final ro = widget.readOnly;
    final canCapture = !ro || widget.allowWallPhotoCapture;
    if (!canCapture && photos.isEmpty) return;
    final label = widget.plan.labelForWall(w);
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
                label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16),
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
      await _captureFreeWallPhoto(w, ImageSource.camera);
    } else if (action == 'gallery') {
      await _captureFreeWallPhoto(w, ImageSource.gallery);
    } else if (action == 'view') {
      await _showFreeWallPhotos(w);
    }
  }

  List<WallPhoto> _photosForFreeWall(String wallId) {
    return widget.plan.wallPhotos
        .where((p) =>
            p.freeWallId == wallId &&
            (widget.etatId == null || p.etatId == widget.etatId))
        .toList();
  }

  Future<void> _captureFreeWallPhoto(FreeWall w, ImageSource src) async {
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
    final label = widget.plan.labelForWall(w);
    try {
      await PhotoWatermark.stampInPlace(
        File(destPath),
        at: takenAt,
        label: label,
      );
    } catch (_) {
      // Photo brute en cas d'échec watermark.
    }
    final photo = WallPhoto(
      id: photoId,
      roomId: '',
      side: 'free',
      wallNumber: 0,
      roomName: label,
      path: destPath,
      takenAt: takenAt,
      etatId: widget.etatId,
      freeWallId: w.id,
    );
    setState(() => widget.plan.wallPhotos.add(photo));
    widget.onChanged();
  }

  Future<void> _showFreeWallPhotos(FreeWall w) async {
    final label = widget.plan.labelForWall(w);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WallPhotosScreen(
          planId: widget.plan.id,
          roomId: '',
          side: 'free',
          title: label,
          canDelete: !widget.readOnly,
          etatId: widget.etatId,
          freeWallId: w.id,
        ),
      ),
    );
  }

  /// Zones de hit transparentes pour chaque mur libre, pour permettre
  /// la sélection au tap et la translation au drag depuis n'importe quel
  /// point du mur. Si la pièce est en mode dessin, on n'ajoute rien (les
  /// taps doivent aller au handler du mode).
  List<Widget> _buildFreeWallHitZones(Size canvas) {
    if (widget.readOnly || _isInDrawingMode) return const [];
    Offset toPx(double nx, double ny) =>
        Offset(nx * canvas.width, ny * canvas.height);
    final widgets = <Widget>[];
    for (final w in widget.plan.freeWalls) {
      final a = toPx(w.x1, w.y1);
      final b = toPx(w.x2, w.y2);
      const pad = 14.0;
      final left = math.min(a.dx, b.dx) - pad;
      final top = math.min(a.dy, b.dy) - pad;
      final width = (a.dx - b.dx).abs() + pad * 2;
      final height = (a.dy - b.dy).abs() + pad * 2;
      widgets.add(Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            widget.onSelectWall(w.id);
            widget.onSelect(null);
          },
          onLongPress: () => _onFreeWallLongPress(w),
          onPanStart: (d) {
            // Vérifie qu'on est bien sur la ligne du mur (et pas dans la
            // bbox loin de la ligne, possible pour un mur diagonal).
            final localNorm = Offset(
              (d.localPosition.dx + left) / canvas.width,
              (d.localPosition.dy + top) / canvas.height,
            );
            final dist = _pointToSegmentDistance(
                localNorm, Offset(w.x1, w.y1), Offset(w.x2, w.y2));
            if (dist > 0.025) return;
            widget.onSelectWall(w.id);
            widget.onSelect(null);
            _startWallDrag(_WallDragMode.body, d.globalPosition);
          },
          onPanUpdate: (d) {
            if (_wallDragMode == _WallDragMode.body) {
              _updateWallDrag(d.globalPosition, canvas);
            }
          },
          onPanEnd: (_) {
            if (_wallDragMode == _WallDragMode.body) _endWallDrag();
          },
        ),
      ));
    }
    return widgets;
  }

  List<Widget> _buildSelectedWallHandles(FreeWall w, Size size) {
    if (widget.readOnly) return const [];
    Offset toPx(double nx, double ny) =>
        Offset(nx * size.width, ny * size.height);
    final a = toPx(w.x1, w.y1);
    final b = toPx(w.x2, w.y2);
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    const handleSize = 20.0;
    Widget handle({
      required Offset center,
      required _WallDragMode mode,
      required Color color,
      required IconData icon,
    }) {
      return Positioned(
        left: center.dx - handleSize / 2,
        top: center.dy - handleSize / 2,
        width: handleSize,
        height: handleSize,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _startWallDrag(mode, d.globalPosition),
          onPanUpdate: (d) => _updateWallDrag(d.globalPosition, size),
          onPanEnd: (_) => _endWallDrag(),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 2),
              ],
            ),
            child: Icon(icon, size: 12, color: color),
          ),
        ),
      );
    }

    return [
      handle(
        center: a,
        mode: _WallDragMode.endpoint1,
        color: const Color(0xFF2563EB),
        icon: Icons.fiber_manual_record,
      ),
      handle(
        center: b,
        mode: _WallDragMode.endpoint2,
        color: const Color(0xFF2563EB),
        icon: Icons.fiber_manual_record,
      ),
      handle(
        center: mid,
        mode: _WallDragMode.body,
        color: const Color(0xFF7C3AED),
        icon: Icons.open_with,
      ),
    ];
  }

  // ───────────────────────────────────────────────────────────────────────
  //   Mode « Tracer une pièce » (dessin libre point par point)
  // ───────────────────────────────────────────────────────────────────────

  /// Entre dans le mode tracé : désélectionne, vide l'historique de sommets,
  /// affiche la bannière de contrôle et attend les taps sur le canvas.
  /// Appelé depuis le bouton « Tracer une pièce » de la sidebar/palette.
  void startFreeDraw() {
    if (widget.readOnly) return;
    setState(() {
      _freeDrawMode = true;
      _freeDrawPoints.clear();
      _freeDrawHover = null;
      _freeDrawOrthoLock = false;
      _annotateMode = false;
      widget.onSelect(null);
    });
  }

  /// Annule le tracé en cours et quitte le mode.
  void cancelFreeDraw() {
    setState(() {
      _freeDrawMode = false;
      _freeDrawPoints.clear();
      _freeDrawHover = null;
    });
  }

  /// Retire le dernier sommet posé. Si la liste est vide, sort du mode.
  void undoLastFreeDrawPoint() {
    setState(() {
      if (_freeDrawPoints.isNotEmpty) {
        _freeDrawPoints.removeLast();
      } else {
        _freeDrawMode = false;
      }
    });
  }

  /// Active/désactive la contrainte d'angle (multiples de 45°).
  void toggleFreeDrawOrthoLock() {
    setState(() => _freeDrawOrthoLock = !_freeDrawOrthoLock);
  }

  /// Met à jour la position d'aperçu (sur desktop, via MouseRegion).
  void _updateFreeDrawHover(Offset pos, Size canvas) {
    if (!_freeDrawMode) return;
    setState(() {
      _freeDrawHover = Offset(
        (pos.dx / canvas.width).clamp(0.0, 1.0),
        (pos.dy / canvas.height).clamp(0.0, 1.0),
      );
    });
  }

  void _updateDrawWallHover(Offset pos, Size canvas) {
    if (!_drawWallMode) return;
    setState(() {
      _drawWallHover = Offset(
        (pos.dx / canvas.width).clamp(0.0, 1.0),
        (pos.dy / canvas.height).clamp(0.0, 1.0),
      );
    });
  }

  /// Gestion d'un tap dans le mode tracé : ajoute un sommet, applique le snap
  /// aux sommets/murs existants, applique la contrainte d'angle si active,
  /// et ferme le polygone si on tape près du premier sommet (≥ 3 sommets).
  void _handleFreeDrawTap(Offset pos, Size canvas) {
    final raw = Offset(
      (pos.dx / canvas.width).clamp(0.0, 1.0),
      (pos.dy / canvas.height).clamp(0.0, 1.0),
    );

    // Fermeture automatique : tap près du premier sommet (≥ 3 sommets).
    if (_freeDrawPoints.length >= 3) {
      final start = _freeDrawPoints.first;
      if ((raw - start).distance < _freeDrawCloseRadius) {
        _finalizeFreeDraw();
        return;
      }
    }

    // 1) Snap aux sommets et murs existants.
    Offset point = _snapToExistingGeometry(raw);

    // 2) Contrainte d'angle (multiples de 45°) relative au sommet précédent.
    if (_freeDrawOrthoLock && _freeDrawPoints.isNotEmpty) {
      point = _applyOrthoLock(_freeDrawPoints.last, point);
    }

    setState(() {
      _freeDrawPoints.add(point);
      _freeDrawHover = point;
    });
  }

  /// Cherche un point d'accrochage parmi les sommets puis les arêtes des
  /// pièces existantes. Retourne le point d'accrochage si trouvé, sinon `p`.
  Offset _snapToExistingGeometry(Offset p) {
    Offset best = p;
    double bestDist = _freeDrawSnapRadius;

    for (final r in widget.plan.rooms) {
      // Sommets de la pièce (polygone ou rectangle).
      final corners = _roomCorners(r);
      for (final c in corners) {
        final d = (p - c).distance;
        if (d < bestDist) {
          bestDist = d;
          best = c;
        }
      }
    }
    if (best != p) return best;

    // Aucun sommet proche : on tente le snap sur les arêtes (projection).
    bestDist = _freeDrawSnapRadius;
    for (final r in widget.plan.rooms) {
      final edges = _roomEdges(r);
      for (final e in edges) {
        final proj = _projectOnSegment(p, e[0], e[1]);
        if (proj == null) continue;
        final d = (p - proj).distance;
        if (d < bestDist) {
          bestDist = d;
          best = proj;
        }
      }
    }
    return best;
  }

  /// Retourne les 4 coins du rectangle ou les sommets du polygone, en
  /// coordonnées normalisées.
  List<Offset> _roomCorners(RoomShape r) {
    if (r.isPolygon && r.vertices != null) {
      final v = r.vertices!;
      return [
        for (var i = 0; i < v.length; i += 2) Offset(v[i], v[i + 1]),
      ];
    }
    return [
      Offset(r.x, r.y),
      Offset(r.x + r.width, r.y),
      Offset(r.x + r.width, r.y + r.height),
      Offset(r.x, r.y + r.height),
    ];
  }

  /// Retourne les arêtes (paires de points) d'une pièce.
  List<List<Offset>> _roomEdges(RoomShape r) {
    final corners = _roomCorners(r);
    final edges = <List<Offset>>[];
    for (var i = 0; i < corners.length; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % corners.length];
      edges.add([a, b]);
    }
    return edges;
  }

  /// Projette `p` sur le segment [a,b]. Retourne le point projeté si la
  /// projection tombe sur le segment (paramètre t ∈ [0,1]), sinon null.
  Offset? _projectOnSegment(Offset p, Offset a, Offset b) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final len2 = abx * abx + aby * aby;
    if (len2 < 1e-9) return null;
    final t = ((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / len2;
    if (t < 0 || t > 1) return null;
    return Offset(a.dx + t * abx, a.dy + t * aby);
  }

  /// Contraint le vecteur `last → cur` à un multiple de 45°, en conservant
  /// la distance entre les deux points.
  Offset _applyOrthoLock(Offset last, Offset cur) {
    final dx = cur.dx - last.dx;
    final dy = cur.dy - last.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1e-6) return cur;
    final angle = math.atan2(dy, dx);
    const step = math.pi / 4; // 45°
    final snappedAngle = (angle / step).round() * step;
    return Offset(
      last.dx + dist * math.cos(snappedAngle),
      last.dy + dist * math.sin(snappedAngle),
    );
  }

  /// Termine le tracé : prompt pour nommer la pièce puis crée le RoomShape
  /// polygonal. Si moins de 3 sommets, refuse.
  Future<void> _finalizeFreeDraw() async {
    if (_freeDrawPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trace au moins 3 sommets.')),
      );
      return;
    }
    final pts = List<Offset>.from(_freeDrawPoints);
    setState(() {
      _freeDrawMode = false;
      _freeDrawPoints.clear();
      _freeDrawHover = null;
    });
    final name = await _promptFreeDrawRoomName();
    if (name == null) return; // annulé
    _createRoomFromFreeDrawPolygon(name, pts);
  }

  /// Affiche un dialog demandant le nom de la pièce. Retourne null si annulé.
  Future<String?> _promptFreeDrawRoomName() async {
    final controller = TextEditingController(text: 'Pièce');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nommer la pièce'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom',
            hintText: 'ex. Salon, Chambre 1…',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim().isEmpty ? 'Pièce' : v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.of(ctx).pop(v.isEmpty ? 'Pièce' : v);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  /// Crée une nouvelle pièce polygonale à partir de la liste de sommets.
  void _createRoomFromFreeDrawPolygon(String name, List<Offset> pts) {
    final flat = <double>[];
    for (final p in pts) {
      flat..add(p.dx)..add(p.dy);
    }
    double minX = pts.first.dx, maxX = pts.first.dx;
    double minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final idx = widget.plan.rooms.length % _colors.length;
    final room = RoomShape.create(
      name: name,
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
      colorIndex: idx,
    )..vertices = flat;
    setState(() {
      widget.plan.rooms.add(room);
      widget.onSelect(room.id);
    });
    widget.onChanged();
  }

  // ───────────────────────────────────────────────────────────────────────
  //   Mode « Calibrer l'échelle » (deux clics + saisie de la distance réelle)
  // ───────────────────────────────────────────────────────────────────────

  /// Entre dans le mode calibration. L'utilisateur clique 2 points sur le
  /// plan puis tape la distance réelle entre ces deux points.
  void startCalibration() {
    if (widget.readOnly) return;
    setState(() {
      _calibrateMode = true;
      _calibratePoint1 = null;
      _calibratePoint2 = null;
      _freeDrawMode = false;
      _freeDrawPoints.clear();
      _annotateMode = false;
      widget.onSelect(null);
    });
  }

  void cancelCalibration() {
    setState(() {
      _calibrateMode = false;
      _calibratePoint1 = null;
      _calibratePoint2 = null;
    });
  }

  /// Supprime l'échelle calibrée du plan (retour à un plan non métré).
  Future<void> clearCalibration() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la calibration ?'),
        content: const Text(
          'Le plan ne sera plus à l\'échelle. Les cotes en mètres et les '
          'surfaces calculées ne seront plus affichées.',
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
    if (ok != true) return;
    setState(() => widget.plan.scaleMetersPerUnit = null);
    widget.onChanged();
  }

  void _handleCalibrateTap(Offset pos, Size canvas) {
    final norm = Offset(
      (pos.dx / canvas.width).clamp(0.0, 1.0),
      (pos.dy / canvas.height).clamp(0.0, 1.0),
    );
    // Snap aux sommets/murs existants pour pointer précisément.
    final snapped = _snapToExistingGeometry(norm);
    if (_calibratePoint1 == null) {
      setState(() => _calibratePoint1 = snapped);
    } else {
      setState(() => _calibratePoint2 = snapped);
      _askCalibrationDistance();
    }
  }

  Future<void> _askCalibrationDistance() async {
    final p1 = _calibratePoint1!;
    final p2 = _calibratePoint2!;
    final unitsDist = (p2 - p1).distance;
    if (unitsDist < 1e-4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Les 2 points sont trop proches.')),
      );
      setState(() {
        _calibratePoint1 = null;
        _calibratePoint2 = null;
      });
      return;
    }
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Distance réelle ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Saisis la distance réelle entre les 2 points cliqués (en mètres). '
              'Le plan entier sera mis à l\'échelle.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Distance (m)',
                hintText: 'ex. 5,20',
                suffixText: 'm',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Calibrer'),
          ),
        ],
      ),
    );
    if (result == null) {
      setState(() {
        _calibrateMode = false;
        _calibratePoint1 = null;
        _calibratePoint2 = null;
      });
      return;
    }
    final parsed = double.tryParse(result.trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Distance invalide.')),
      );
      setState(() {
        _calibratePoint1 = null;
        _calibratePoint2 = null;
      });
      return;
    }
    final scale = parsed / unitsDist;
    setState(() {
      widget.plan.scaleMetersPerUnit = scale;
      _calibrateMode = false;
      _calibratePoint1 = null;
      _calibratePoint2 = null;
    });
    widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Échelle calibrée : ${parsed.toStringAsFixed(2)} m sur ${(unitsDist * 100).toStringAsFixed(1)} % du plan.'),
        ),
      );
    }
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
    final metersPerUnit =
        widget.plan.scaleMetersPerUnit ?? _wallScaleMeters;
    final currentMeters = currentRatio * metersPerUnit;
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
                    if (v > metersPerUnit) {
                      setLocal(() => errorText =
                          'Maximum ${metersPerUnit.toStringAsFixed(0)} m');
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
            (result.lengthMeters! / metersPerUnit).clamp(0.001, 1.0);
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
            _applyPolygonMoveSnap(r);
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

  /// Pour une pièce polygonale en cours de déplacement : si l'une de ses
  /// arêtes est presque parallèle et proche d'une arête d'une autre pièce
  /// (rect ou polygone) ou d'un mur libre, applique un offset perpendiculaire
  /// pour les faire coïncider exactement. Le snap le plus court (parmi tous
  /// les couples d'arêtes candidats) est appliqué à tout le polygone.
  void _applyPolygonMoveSnap(RoomShape r) {
    if (!r.isPolygon || r.vertices == null) return;
    final v = r.vertices!;
    final n = v.length ~/ 2;
    if (n < 3) return;

    final myEdges = <List<Offset>>[];
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      myEdges.add([
        Offset(v[i * 2], v[i * 2 + 1]),
        Offset(v[j * 2], v[j * 2 + 1]),
      ]);
    }

    final targets = <List<Offset>>[];
    for (final o in widget.plan.rooms) {
      if (o.id == r.id) continue;
      if (o.isPolygon && o.vertices != null) {
        final ov = o.vertices!;
        final on = ov.length ~/ 2;
        for (var i = 0; i < on; i++) {
          final j = (i + 1) % on;
          targets.add([
            Offset(ov[i * 2], ov[i * 2 + 1]),
            Offset(ov[j * 2], ov[j * 2 + 1]),
          ]);
        }
      } else {
        final l = o.x, rr = o.x + o.width, tt = o.y, bb = o.y + o.height;
        targets.add([Offset(l, tt), Offset(rr, tt)]);
        targets.add([Offset(rr, tt), Offset(rr, bb)]);
        targets.add([Offset(rr, bb), Offset(l, bb)]);
        targets.add([Offset(l, bb), Offset(l, tt)]);
      }
    }
    for (final w in widget.plan.freeWalls) {
      targets.add([Offset(w.x1, w.y1), Offset(w.x2, w.y2)]);
    }

    double bestDx = 0, bestDy = 0;
    double bestPerp = _snapThreshold;

    for (final me in myEdges) {
      for (final t in targets) {
        final snap = _edgePerpSnap(me[0], me[1], t[0], t[1]);
        if (snap != null && snap[2].abs() < bestPerp) {
          bestPerp = snap[2].abs();
          bestDx = snap[0];
          bestDy = snap[1];
        }
      }
    }
    if (bestPerp >= _snapThreshold) return;

    final out = <double>[];
    for (var i = 0; i < v.length; i += 2) {
      out.add((v[i] + bestDx).clamp(0.0, 1.0));
      out.add((v[i + 1] + bestDy).clamp(0.0, 1.0));
    }
    r.vertices = out;
    r.recomputeBounds();
  }

  /// Si AB et CD sont presque parallèles avec recouvrement de leurs
  /// projections, retourne [dx, dy, perpDistance] où (dx, dy) est l'offset
  /// à appliquer à AB pour le faire coïncider avec la ligne de CD.
  List<double>? _edgePerpSnap(Offset a, Offset b, Offset c, Offset d) {
    final abDx = b.dx - a.dx;
    final abDy = b.dy - a.dy;
    final lenAB = math.sqrt(abDx * abDx + abDy * abDy);
    if (lenAB < 1e-6) return null;
    final cdDx = d.dx - c.dx;
    final cdDy = d.dy - c.dy;
    final lenCD = math.sqrt(cdDx * cdDx + cdDy * cdDy);
    if (lenCD < 1e-6) return null;
    final ux = abDx / lenAB, uy = abDy / lenAB;
    final vx = cdDx / lenCD, vy = cdDy / lenCD;
    final cross = (ux * vy - uy * vx).abs();
    if (cross > 0.09) return null; // > ~5°, pas parallèle

    // Recouvrement minimal des projections (sinon les arêtes ne se voient
    // pas comme adjacentes, juste comme alignées au loin).
    final tC = ((c.dx - a.dx) * ux + (c.dy - a.dy) * uy) / lenAB;
    final tD = ((d.dx - a.dx) * ux + (d.dy - a.dy) * uy) / lenAB;
    final tMin = math.min(tC, tD);
    final tMax = math.max(tC, tD);
    if (tMax < -0.05 || tMin > 1.05) return null;

    // Distance perpendiculaire signée de A à la ligne de CD.
    final perp = (c.dx - a.dx) * (-uy) + (c.dy - a.dy) * ux;
    final dx = perp * (-uy);
    final dy = perp * ux;
    return [dx, dy, perp];
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

/// Mode de drag sur un mur libre sélectionné.
enum _WallDragMode { endpoint1, endpoint2, body }

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

/// Painter qui dessine le polygone en cours de tracé dans le mode
/// « Tracer une pièce » : segments déjà posés + ligne d'aperçu jusqu'au
/// pointeur + cercles aux sommets + zone de fermeture autour du 1er sommet.
/// Distance euclidienne d'un point au segment [a,b] (en coords normalisées).
double _pointToSegmentDistance(Offset p, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final len2 = dx * dx + dy * dy;
  if (len2 < 1e-9) return (p - a).distance;
  final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2).clamp(0.0, 1.0);
  final proj = Offset(a.dx + t * dx, a.dy + t * dy);
  return (p - proj).distance;
}

/// Collecte toutes les arêtes existantes du plan (pièces rectangles &
/// polygones + murs libres) en coordonnées normalisées 0..1. Utilisé par
/// les painters d'aperçu pour détecter et surligner les zones de
/// chevauchement avec le tracé en cours.
List<List<Offset>> _collectExistingEdges(PlanLogement plan) {
  final edges = <List<Offset>>[];
  for (final r in plan.rooms) {
    if (r.isPolygon && r.vertices != null) {
      final v = r.vertices!;
      final n = v.length ~/ 2;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        edges.add([
          Offset(v[i * 2], v[i * 2 + 1]),
          Offset(v[j * 2], v[j * 2 + 1]),
        ]);
      }
    } else {
      final x1 = r.x, y1 = r.y;
      final x2 = r.x + r.width, y2 = r.y + r.height;
      edges.add([Offset(x1, y1), Offset(x2, y1)]);
      edges.add([Offset(x2, y1), Offset(x2, y2)]);
      edges.add([Offset(x2, y2), Offset(x1, y2)]);
      edges.add([Offset(x1, y2), Offset(x1, y1)]);
    }
  }
  for (final w in plan.freeWalls) {
    edges.add([Offset(w.x1, w.y1), Offset(w.x2, w.y2)]);
  }
  return edges;
}

/// Calcule la portion de chevauchement entre les segments AB et CD si :
///   - ils sont quasi parallèles (angle < ~5°)
///   - leur distance perpendiculaire est < perpTolerance (en unités
///     normalisées du canvas)
///   - leurs projections se recouvrent d'au moins minOverlap
///
/// Retourne [start, end] en coords normalisées, sinon null.
List<Offset>? _segmentOverlapZone(
  Offset a,
  Offset b,
  Offset c,
  Offset d, {
  double perpTolerance = 0.025,
  double minOverlap = 0.005,
}) {
  final abDx = b.dx - a.dx;
  final abDy = b.dy - a.dy;
  final lenAB = math.sqrt(abDx * abDx + abDy * abDy);
  if (lenAB < 1e-6) return null;
  final cdDx = d.dx - c.dx;
  final cdDy = d.dy - c.dy;
  final lenCD = math.sqrt(cdDx * cdDx + cdDy * cdDy);
  if (lenCD < 1e-6) return null;

  // Vecteurs unitaires
  final ux = abDx / lenAB;
  final uy = abDy / lenAB;
  final vx = cdDx / lenCD;
  final vy = cdDy / lenCD;

  // Parallélisme : produit vectoriel des unitaires (sin de l'angle).
  final cross = (ux * vy - uy * vx).abs();
  if (cross > 0.18) return null; // ~10°

  // Distance perpendiculaire entre les 2 lignes : projeter (c - a) sur
  // la normale unitaire à AB (-uy, ux).
  final perpA = ((c.dx - a.dx) * (-uy) + (c.dy - a.dy) * ux).abs();
  if (perpA > perpTolerance) return null;

  // Projection de C et D sur AB en paramètre t (0 = a, 1 = b).
  final tC = ((c.dx - a.dx) * ux + (c.dy - a.dy) * uy) / lenAB;
  final tD = ((d.dx - a.dx) * ux + (d.dy - a.dy) * uy) / lenAB;
  final tMin = math.max(0.0, math.min(tC, tD));
  final tMax = math.min(1.0, math.max(tC, tD));
  if (tMax - tMin < minOverlap / lenAB) return null;

  final start = Offset(a.dx + abDx * tMin, a.dy + abDy * tMin);
  final end = Offset(a.dx + abDx * tMax, a.dy + abDy * tMax);
  return [start, end];
}

/// Peint en surbrillance toutes les zones de chevauchement entre le
/// segment AB (préview) et les arêtes existantes.
void _paintOverlapHighlights({
  required Canvas canvas,
  required Size size,
  required Offset a,
  required Offset b,
  required List<List<Offset>> existingEdges,
}) {
  // Halo doré derrière (glow) pour visibilité maximale, puis ligne épaisse
  // orange par-dessus. Le résultat est très visible même sur fond clair.
  final glow = Paint()
    ..color = const Color(0xFFFDE68A).withValues(alpha: 0.85)
    ..strokeWidth = 14
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final paint = Paint()
    ..color = const Color(0xFFEA580C)
    ..strokeWidth = 7
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  Offset toPx(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
  for (final e in existingEdges) {
    final overlap = _segmentOverlapZone(a, b, e[0], e[1]);
    if (overlap != null) {
      final s = toPx(overlap[0]);
      final t = toPx(overlap[1]);
      canvas.drawLine(s, t, glow);
      canvas.drawLine(s, t, paint);
    }
  }
}

/// Painter qui affiche les dimensions (longueur en mètres si calibré, ou
/// fraction de canvas sinon) de chaque arête visible des pièces. Le texte
/// est positionné juste à l'extérieur de chaque arête, perpendiculairement.
class _DimensionsPainter extends CustomPainter {
  final PlanLogement plan;

  _DimensionsPainter({required this.plan});

  @override
  void paint(Canvas canvas, Size size) {
    Offset toPx(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    final scale = plan.scaleMetersPerUnit;
    // Quand calibré, 1 unité = N mètres. Sinon on n'a pas de réalité, mais
    // on garde le canvas par défaut à 12 m (cohérent avec _wallScaleMeters).
    final metersPerUnit = scale ?? 12.0;

    for (final r in plan.rooms) {
      final edges = _edgesOf(r);
      final hidden = _hiddenEdgeSet(r);
      // Centroïde de la pièce (en coords normalisées).
      final centroid = _centroidOf(r);
      for (var i = 0; i < edges.length; i++) {
        if (hidden.contains(i)) continue;
        final e = edges[i];
        final a = e[0];
        final b = e[1];
        final dx = b.dx - a.dx;
        final dy = b.dy - a.dy;
        final lenNorm = math.sqrt(dx * dx + dy * dy);
        if (lenNorm < 0.01) continue; // trop court pour méritter une cote
        final lenM = lenNorm * metersPerUnit;
        // Format : N,NN m si > 1 m, sinon NN cm.
        final label = lenM >= 1.0
            ? '${lenM.toStringAsFixed(2).replaceAll('.', ',')} m'
            : '${(lenM * 100).round()} cm';

        // Position du midpoint en pixels.
        final midN = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        final midPx = toPx(midN);

        // Outward perpendiculaire : on prend la perpendiculaire (-dy, dx)
        // normalisée, puis on choisit le signe qui s'éloigne du centroïde.
        var perpX = -dy / lenNorm;
        var perpY = dx / lenNorm;
        final toCentroidX = centroid.dx - midN.dx;
        final toCentroidY = centroid.dy - midN.dy;
        if (perpX * toCentroidX + perpY * toCentroidY > 0) {
          // perp pointe vers le centroïde → inverse pour aller dehors
          perpX = -perpX;
          perpY = -perpY;
        }

        const offsetPx = 14.0;
        final labelCenter = Offset(
          midPx.dx + perpX * offsetPx,
          midPx.dy + perpY * offsetPx,
        );

        // Texte avec fond blanc semi-transparent pour la lisibilité.
        final textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: scale != null
                  ? const Color(0xFF065F46)
                  : const Color(0xFF334155),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final w = textPainter.width;
        final h = textPainter.height;
        // Petit fond arrondi.
        final bgRect = Rect.fromCenter(
          center: labelCenter,
          width: w + 8,
          height: h + 4,
        );
        final bgPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.92);
        final borderPaint = Paint()
          ..color = scale != null
              ? const Color(0xFF10B981).withValues(alpha: 0.45)
              : const Color(0xFFCBD5E1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
        final rrect = RRect.fromRectAndRadius(
            bgRect, const Radius.circular(4));
        canvas.drawRRect(rrect, bgPaint);
        canvas.drawRRect(rrect, borderPaint);
        textPainter.paint(
          canvas,
          Offset(labelCenter.dx - w / 2, labelCenter.dy - h / 2),
        );
      }
    }
  }

  Offset _centroidOf(RoomShape r) {
    if (r.isPolygon && r.vertices != null) {
      final v = r.vertices!;
      final n = v.length ~/ 2;
      double sx = 0, sy = 0;
      for (var i = 0; i < n; i++) {
        sx += v[i * 2];
        sy += v[i * 2 + 1];
      }
      return Offset(sx / n, sy / n);
    }
    return Offset(r.x + r.width / 2, r.y + r.height / 2);
  }

  List<List<Offset>> _edgesOf(RoomShape r) {
    if (r.isPolygon && r.vertices != null) {
      final v = r.vertices!;
      final n = v.length ~/ 2;
      final out = <List<Offset>>[];
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        out.add([
          Offset(v[i * 2], v[i * 2 + 1]),
          Offset(v[j * 2], v[j * 2 + 1]),
        ]);
      }
      return out;
    }
    // Rectangle : ordre top, right, bottom, left pour matcher hiddenWalls.
    return [
      [Offset(r.x, r.y), Offset(r.x + r.width, r.y)],
      [Offset(r.x + r.width, r.y), Offset(r.x + r.width, r.y + r.height)],
      [Offset(r.x + r.width, r.y + r.height), Offset(r.x, r.y + r.height)],
      [Offset(r.x, r.y + r.height), Offset(r.x, r.y)],
    ];
  }

  Set<int> _hiddenEdgeSet(RoomShape r) {
    final s = <int>{};
    if (r.isPolygon) {
      for (final h in r.hiddenWalls) {
        if (h.startsWith('edge:')) {
          final n = int.tryParse(h.substring(5));
          if (n != null) s.add(n);
        }
      }
    } else {
      const mapping = {'top': 0, 'right': 1, 'bottom': 2, 'left': 3};
      for (final h in r.hiddenWalls) {
        final idx = mapping[h];
        if (idx != null) s.add(idx);
      }
    }
    return s;
  }

  @override
  bool shouldRepaint(covariant _DimensionsPainter old) =>
      old.plan.rooms.length != plan.rooms.length ||
      old.plan.scaleMetersPerUnit != plan.scaleMetersPerUnit ||
      !_sameGeometry(old.plan.rooms, plan.rooms);

  static bool _sameGeometry(List<RoomShape> a, List<RoomShape> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].x != b[i].x ||
          a[i].y != b[i].y ||
          a[i].width != b[i].width ||
          a[i].height != b[i].height) return false;
      final va = a[i].vertices;
      final vb = b[i].vertices;
      if ((va == null) != (vb == null)) return false;
      if (va != null && vb != null) {
        if (va.length != vb.length) return false;
        for (var k = 0; k < va.length; k++) {
          if (va[k] != vb[k]) return false;
        }
      }
    }
    return true;
  }
}

/// Painter qui matérialise les chevauchements entre une pièce en cours de
/// déplacement (par drag) et les autres pièces/murs du plan. Permet à
/// l'utilisateur d'aligner précisément ses pièces lors de l'accolage.
class _RoomDragOverlapPainter extends CustomPainter {
  final RoomShape draggedRoom;
  final List<List<Offset>> otherEdges;

  _RoomDragOverlapPainter({
    required this.draggedRoom,
    required this.otherEdges,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final draggedEdges = _edgesOf(draggedRoom);
    for (final dEdge in draggedEdges) {
      _paintOverlapHighlights(
        canvas: canvas,
        size: size,
        a: dEdge[0],
        b: dEdge[1],
        existingEdges: otherEdges,
      );
    }
  }

  static List<List<Offset>> _edgesOf(RoomShape r) {
    if (r.isPolygon && r.vertices != null) {
      final v = r.vertices!;
      final n = v.length ~/ 2;
      final out = <List<Offset>>[];
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        out.add([
          Offset(v[i * 2], v[i * 2 + 1]),
          Offset(v[j * 2], v[j * 2 + 1]),
        ]);
      }
      return out;
    }
    return [
      [Offset(r.x, r.y), Offset(r.x + r.width, r.y)],
      [Offset(r.x + r.width, r.y), Offset(r.x + r.width, r.y + r.height)],
      [Offset(r.x + r.width, r.y + r.height), Offset(r.x, r.y + r.height)],
      [Offset(r.x, r.y + r.height), Offset(r.x, r.y)],
    ];
  }

  @override
  bool shouldRepaint(covariant _RoomDragOverlapPainter old) =>
      old.draggedRoom != draggedRoom || old.otherEdges != otherEdges;
}

class _FreeDrawPreviewPainter extends CustomPainter {
  /// Sommets posés en coordonnées normalisées 0..1.
  final List<Offset> points;

  /// Position courante du curseur (normalisée). Null = pas d'aperçu.
  final Offset? hover;

  /// Rayon de fermeture (normalisé) autour du premier sommet.
  final double closeRadius;

  /// Indique si l'aperçu fermerait le polygone (utilisé pour colorer la
  /// ligne d'aperçu en vert et grossir le 1er sommet).
  final bool willClose;

  /// Arêtes existantes (pièces + murs libres) pour détecter chevauchements.
  final List<List<Offset>> existingEdges;

  /// Échelle en mètres par unité normalisée — utilisée pour afficher la
  /// longueur de chaque segment du tracé.
  final double metersPerUnit;

  /// Indique si l'échelle vient d'un calibrage (true) ou de la valeur par
  /// défaut 12 m (false). Influe sur la couleur du libellé de cote.
  final bool isCalibrated;

  _FreeDrawPreviewPainter({
    required this.points,
    required this.hover,
    required this.closeRadius,
    required this.willClose,
    this.existingEdges = const [],
    this.metersPerUnit = 12.0,
    this.isCalibrated = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Offset toPx(Offset p) => Offset(p.dx * size.width, p.dy * size.height);

    // 0) Diagnostic : trace toutes les arêtes détectées en cyan translucide.
    //    Permet de visualiser ce que le système connaît comme arêtes
    //    existantes (pièces + murs libres). Si elles ne s'affichent pas,
    //    c'est que le painter ne tourne pas.
    final debugPaint = Paint()
      ..color = const Color(0xFF06B6D4).withValues(alpha: 0.55)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final e in existingEdges) {
      canvas.drawLine(toPx(e[0]), toPx(e[1]), debugPaint);
    }

    if (points.isEmpty) return;

    // 1) Surbrillance des chevauchements (dessinée en premier, sous les
    //    segments d'aperçu) : pour chaque segment posé + le segment courant
    //    de prévisualisation.
    for (var i = 0; i < points.length - 1; i++) {
      _paintOverlapHighlights(
        canvas: canvas,
        size: size,
        a: points[i],
        b: points[i + 1],
        existingEdges: existingEdges,
      );
    }
    if (hover != null && points.isNotEmpty) {
      _paintOverlapHighlights(
        canvas: canvas,
        size: size,
        a: points.last,
        b: hover!,
        existingEdges: existingEdges,
      );
    }

    final segPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Segments posés.
    for (var i = 0; i < points.length - 1; i++) {
      canvas.drawLine(toPx(points[i]), toPx(points[i + 1]), segPaint);
    }

    // Ligne d'aperçu (dernier sommet → curseur).
    if (hover != null && points.isNotEmpty) {
      final previewPaint = Paint()
        ..color = willClose
            ? const Color(0xFF16A34A)
            : const Color(0xFF2563EB).withValues(alpha: 0.55)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      _drawDashedLine(canvas, toPx(points.last), toPx(hover!), previewPaint);

      // Si la fermeture est imminente, on relie aussi visuellement le curseur
      // au premier sommet en pointillé vert clair.
      if (willClose && points.length >= 3) {
        final closePaint = Paint()
          ..color = const Color(0xFF16A34A).withValues(alpha: 0.5)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        _drawDashedLine(canvas, toPx(hover!), toPx(points.first), closePaint);
      }
    }

    // Zone de fermeture autour du premier sommet (≥ 3 sommets posés).
    if (points.length >= 3) {
      final radiusPx = closeRadius * math.min(size.width, size.height);
      final zonePaint = Paint()
        ..color = const Color(0xFF16A34A).withValues(alpha: 0.10)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(toPx(points.first), radiusPx, zonePaint);
      final ringPaint = Paint()
        ..color = const Color(0xFF16A34A).withValues(alpha: 0.55)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(toPx(points.first), radiusPx, ringPaint);
    }

    // Sommets : disque blanc bordé bleu, 1er sommet plus gros.
    final fillPaint = Paint()..color = Colors.white;
    final borderPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length; i++) {
      final p = toPx(points[i]);
      final r = i == 0 ? 7.0 : 5.0;
      canvas.drawCircle(p, r, fillPaint);
      canvas.drawCircle(p, r, borderPaint);
    }

    // Cote de chaque segment posé : longueur en m (ou cm si < 1m), placée
    // au milieu, légèrement décalée perpendiculairement.
    for (var i = 0; i < points.length - 1; i++) {
      _paintSegmentLength(canvas, points[i], points[i + 1], toPx);
    }
    // Cote de la ligne d'aperçu (dernier sommet → curseur).
    if (hover != null && points.isNotEmpty) {
      _paintSegmentLength(canvas, points.last, hover!, toPx,
          accent: willClose);
    }
  }

  void _paintSegmentLength(
    Canvas canvas,
    Offset a,
    Offset b,
    Offset Function(Offset) toPx, {
    bool accent = false,
  }) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenNorm = math.sqrt(dx * dx + dy * dy);
    if (lenNorm < 0.008) return;
    final meters = lenNorm * metersPerUnit;
    final label = meters >= 1.0
        ? '${meters.toStringAsFixed(2).replaceAll('.', ',')} m'
        : '${(meters * 100).round()} cm';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: accent
              ? const Color(0xFF14532D)
              : (isCalibrated
                  ? const Color(0xFF065F46)
                  : const Color(0xFF1E3A8A)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Position : milieu, décalé perpendiculairement de offsetPx pixels.
    final midPx = toPx(Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2));
    final perpX = -dy / lenNorm;
    final perpY = dx / lenNorm;
    const offsetPx = 14.0;
    final center = Offset(
      midPx.dx + perpX * offsetPx,
      midPx.dy + perpY * offsetPx,
    );
    final rect = Rect.fromCenter(
      center: center,
      width: tp.width + 8,
      height: tp.height + 4,
    );
    final bg = Paint()
      ..color = (accent ? const Color(0xFFD1FAE5) : Colors.white)
          .withValues(alpha: 0.95);
    final border = Paint()
      ..color = accent
          ? const Color(0xFF10B981)
          : (isCalibrated
              ? const Color(0xFF10B981).withValues(alpha: 0.45)
              : const Color(0xFF2563EB).withValues(alpha: 0.4))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final rrect =
        RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, bg);
    canvas.drawRRect(rrect, border);
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total < 1) {
      canvas.drawLine(a, b, paint);
      return;
    }
    final dx = (b.dx - a.dx) / total;
    final dy = (b.dy - a.dy) / total;
    double pos = 0;
    while (pos < total) {
      final start = Offset(a.dx + dx * pos, a.dy + dy * pos);
      final end = Offset(
        a.dx + dx * math.min(pos + dash, total),
        a.dy + dy * math.min(pos + dash, total),
      );
      canvas.drawLine(start, end, paint);
      pos += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _FreeDrawPreviewPainter old) =>
      old.points != points ||
      old.hover != hover ||
      old.willClose != willClose ||
      old.existingEdges != existingEdges;
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

/// Bannière de contrôle affichée en haut du canvas pendant le mode
/// « Tracer une pièce » : compteur de sommets, raccourci angles droits,
/// retour arrière, annulation, et bouton « Terminer » qui clôt le polygone.
class _FreeDrawBanner extends StatelessWidget {
  final int pointCount;
  final bool orthoLock;
  final VoidCallback onToggleOrtho;
  final VoidCallback onUndoPoint;
  final VoidCallback onCancel;
  final VoidCallback? onFinish;

  const _FreeDrawBanner({
    required this.pointCount,
    required this.orthoLock,
    required this.onToggleOrtho,
    required this.onUndoPoint,
    required this.onCancel,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final canFinish = onFinish != null;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: const Color(0xFF1E293B),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pointCount == 0
                    ? 'Tape sur le plan pour poser le premier sommet.'
                    : pointCount < 3
                        ? 'Sommet $pointCount · pose au moins 3 sommets.'
                        : 'Sommets : $pointCount · tape près du 1ᵉʳ pour fermer.',
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, height: 1.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            _BannerIconButton(
              icon: Icons.square_foot,
              tooltip: orthoLock
                  ? 'Angles libres'
                  : 'Forcer angles à 45°',
              active: orthoLock,
              onTap: onToggleOrtho,
            ),
            const SizedBox(width: 4),
            _BannerIconButton(
              icon: Icons.undo,
              tooltip: 'Retirer dernier sommet',
              onTap: pointCount > 0 ? onUndoPoint : null,
            ),
            const SizedBox(width: 4),
            _BannerIconButton(
              icon: Icons.close,
              tooltip: 'Annuler',
              onTap: onCancel,
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: canFinish ? onFinish : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                disabledBackgroundColor: Colors.white24,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Terminer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback? onTap;

  const _BannerIconButton({
    required this.icon,
    required this.tooltip,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: disabled
                ? Colors.white38
                : (active ? Colors.amberAccent : Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Carte « Échelle du plan » de la sidebar. Affiche l'état de calibration
/// (non calibré / calibré avec valeur) et propose les actions Calibrer /
/// Recalibrer / Supprimer.
class _ScaleCard extends StatelessWidget {
  final PlanLogement plan;
  final VoidCallback onCalibrate;
  final VoidCallback onClear;

  const _ScaleCard({
    required this.plan,
    required this.onCalibrate,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final calibrated = plan.isCalibrated;
    final scale = plan.scaleMetersPerUnit;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: calibrated
            ? const Color(0xFFECFDF5)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: calibrated
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                calibrated ? Icons.straighten : Icons.straighten_outlined,
                size: 18,
                color: calibrated
                    ? const Color(0xFF059669)
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  calibrated
                      ? 'Plan calibré'
                      : 'Plan non calibré',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: calibrated
                        ? const Color(0xFF065F46)
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            calibrated
                ? '1 unité = ${scale!.toStringAsFixed(2)} m · les cotes et surfaces s\'affichent en mètres.'
                : 'Clique « Calibrer » puis trace une distance connue (ex. la longueur d\'un mur) pour obtenir les cotes en mètres et la surface auto.',
            style: const TextStyle(fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onCalibrate,
                  icon: const Icon(Icons.straighten, size: 16),
                  label: Text(calibrated ? 'Recalibrer' : 'Calibrer'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              if (calibrated) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.error,
                  tooltip: 'Supprimer la calibration',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Card de la sidebar affichée quand un mur libre est sélectionné :
/// montre son label (auto ou personnalisé), sa longueur (en mètres si
/// calibré, sinon en %), et propose Renommer / Supprimer.
class _SelectedWallCard extends StatelessWidget {
  final PlanLogement plan;
  final FreeWall wall;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onToggleVirtual;

  const _SelectedWallCard({
    required this.plan,
    required this.wall,
    required this.onRename,
    required this.onDelete,
    required this.onToggleVirtual,
  });

  @override
  Widget build(BuildContext context) {
    final label = plan.labelForWall(wall);
    final autoLabel = plan.autoLabelForWall(wall);
    final isAuto = wall.customLabel == null ||
        wall.customLabel!.trim().isEmpty;
    final lenNorm = math.sqrt(
      math.pow(wall.x2 - wall.x1, 2) + math.pow(wall.y2 - wall.y1, 2),
    ).toDouble();
    final meters = plan.unitsToMeters(lenNorm);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: wall.isVirtual
            ? const Color(0xFFFEF3C7)
            : const Color(0xFFFAF5FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: wall.isVirtual
              ? const Color(0xFFD97706).withValues(alpha: 0.45)
              : const Color(0xFF7C3AED).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                wall.isVirtual ? Icons.more_horiz : Icons.linear_scale,
                size: 18,
                color: wall.isVirtual
                    ? const Color(0xFF92400E)
                    : const Color(0xFF5B21B6),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: wall.isVirtual
                        ? const Color(0xFF78350F)
                        : const Color(0xFF4C1D95),
                  ),
                ),
              ),
            ],
          ),
          if (!isAuto) ...[
            const SizedBox(height: 4),
            Text(
              'Auto : $autoLabel',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            meters != null
                ? 'Longueur : ${meters.toStringAsFixed(2)} m'
                : 'Longueur : ${(lenNorm * 100).toStringAsFixed(1)} % du plan',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: wall.isVirtual,
            onChanged: (_) => onToggleVirtual(),
            title: const Text(
              'Mur virtuel (pointillé)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              wall.isVirtual
                  ? 'Représente une ouverture entre 2 espaces.'
                  : 'Représente une cloison réelle.',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            dense: true,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRename,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Renommer'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                color: AppColors.error,
                tooltip: 'Supprimer',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Painter de tous les murs libres du plan. Affiche un trait épais + le
/// libellé centré au-dessus. Le mur sélectionné est mis en évidence.
class _FreeWallsPainter extends CustomPainter {
  final PlanLogement plan;
  final String? selectedId;

  _FreeWallsPainter({required this.plan, required this.selectedId});

  @override
  void paint(Canvas canvas, Size size) {
    Offset toPx(double nx, double ny) =>
        Offset(nx * size.width, ny * size.height);

    // Précalcule les arêtes des pièces (en normalisé) pour la détection
    // de jointure des extrémités.
    final roomEdges = <List<Offset>>[];
    for (final r in plan.rooms) {
      if (r.isPolygon && r.vertices != null) {
        final v = r.vertices!;
        final n = v.length ~/ 2;
        for (var i = 0; i < n; i++) {
          final j = (i + 1) % n;
          roomEdges.add([
            Offset(v[i * 2], v[i * 2 + 1]),
            Offset(v[j * 2], v[j * 2 + 1]),
          ]);
        }
      } else {
        roomEdges.add([Offset(r.x, r.y), Offset(r.x + r.width, r.y)]);
        roomEdges.add(
            [Offset(r.x + r.width, r.y), Offset(r.x + r.width, r.y + r.height)]);
        roomEdges.add([
          Offset(r.x + r.width, r.y + r.height),
          Offset(r.x, r.y + r.height)
        ]);
        roomEdges.add([Offset(r.x, r.y + r.height), Offset(r.x, r.y)]);
      }
    }

    bool isJoined(double x, double y) {
      const tolerance = 0.012; // 1.2% du canvas
      for (final e in roomEdges) {
        final dist = _pointToSegmentDistance(
            Offset(x, y), e[0], e[1]);
        if (dist < tolerance) return true;
      }
      return false;
    }

    for (final w in plan.freeWalls) {
      final isSelected = w.id == selectedId;
      final isVirtual = w.isVirtual;
      final a = toPx(w.x1, w.y1);
      final b = toPx(w.x2, w.y2);
      final joinedA = isJoined(w.x1, w.y1);
      final joinedB = isJoined(w.x2, w.y2);

      // Épaisseur alignée sur celle des murs des pièces (Border 1.5 / 2.5).
      if (isVirtual) {
        final paint = Paint()
          ..color = isSelected
              ? const Color(0xFF0EA5E9)
              : const Color(0xFF64748B)
          ..strokeWidth = isSelected ? 2.5 : 1.5
          ..strokeCap = StrokeCap.butt
          ..style = PaintingStyle.stroke;
        _drawDashedSegment(canvas, a, b, paint, dash: 8, gap: 5);
      } else {
        final paint = Paint()
          ..color = isSelected
              ? const Color(0xFF7C3AED)
              : Colors.black54
          ..strokeWidth = isSelected ? 2.5 : 1.5
          ..strokeCap = StrokeCap.butt
          ..style = PaintingStyle.stroke;
        canvas.drawLine(a, b, paint);
      }

      // Halo vert sur chaque extrémité qui touche un mur de pièce.
      // Indique visuellement que la jonction est faite.
      for (final entry
          in <(Offset, bool)>{(a, joinedA), (b, joinedB)}) {
        if (!entry.$2) continue;
        final glow = Paint()
          ..color = const Color(0xFF22C55E).withValues(alpha: 0.35)
          ..style = PaintingStyle.fill;
        final ring = Paint()
          ..color = const Color(0xFF16A34A)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(entry.$1, 9, glow);
        canvas.drawCircle(entry.$1, 6, ring);
      }

      // Cotes de position : distance perpendiculaire entre chaque extrémité
      // du mur et les murs de la pièce qui le contient. Affichées pour
      // toutes les murs libres (toujours visibles), en pointillé fin.
      _drawWallPositionDimensions(
        canvas: canvas,
        size: size,
        wall: w,
        joinedA: joinedA,
        joinedB: joinedB,
        plan: plan,
      );

      // Libellé au-dessus du milieu du mur, perpendiculaire à celui-ci.
      final label = plan.labelForWall(w);
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 30) continue; // mur trop court, skip
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: isSelected
                ? const Color(0xFF5B21B6)
                : const Color(0xFF1E293B),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: const [
              Shadow(color: Colors.white, blurRadius: 3),
              Shadow(color: Colors.white, blurRadius: 3),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final angle = math.atan2(dy, dx);
      // Décalage perpendiculaire pour poser le texte au-dessus du mur.
      final nx = -math.sin(angle);
      final ny = math.cos(angle);
      const offsetFromWall = 12.0;
      final tx = mid.dx + nx * offsetFromWall - tp.width / 2;
      final ty = mid.dy + ny * offsetFromWall - tp.height / 2;

      canvas.save();
      // Garde le texte droit si le mur est presque vertical (angle proche
      // de ±π/2), sinon le tourne pour suivre le mur.
      double rotAngle = angle;
      // Garde le texte lisible (jamais à l'envers).
      if (rotAngle > math.pi / 2) rotAngle -= math.pi;
      if (rotAngle < -math.pi / 2) rotAngle += math.pi;
      canvas.translate(tx + tp.width / 2, ty + tp.height / 2);
      canvas.rotate(rotAngle);
      canvas.translate(-tp.width / 2, -tp.height / 2);
      tp.paint(canvas, Offset.zero);
      canvas.restore();

      // Si calibré, affichage discret de la longueur en mètres.
      if (plan.isCalibrated) {
        final lenNorm = math.sqrt(
          math.pow(w.x2 - w.x1, 2) + math.pow(w.y2 - w.y1, 2),
        );
        final meters = plan.unitsToMeters(lenNorm.toDouble()) ?? 0;
        final lp = TextPainter(
          text: TextSpan(
            text: '${meters.toStringAsFixed(2)} m',
            style: const TextStyle(
              color: Color(0xFF065F46),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.white, blurRadius: 2)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final lx = mid.dx - nx * offsetFromWall - lp.width / 2;
        final ly = mid.dy - ny * offsetFromWall - lp.height / 2;
        canvas.save();
        canvas.translate(lx + lp.width / 2, ly + lp.height / 2);
        canvas.rotate(rotAngle);
        canvas.translate(-lp.width / 2, -lp.height / 2);
        lp.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FreeWallsPainter old) =>
      old.selectedId != selectedId ||
      old.plan.freeWalls.length != plan.freeWalls.length ||
      old.plan.scaleMetersPerUnit != plan.scaleMetersPerUnit ||
      !_wallsEqual(old.plan.freeWalls, plan.freeWalls);

  static bool _wallsEqual(List<FreeWall> a, List<FreeWall> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final wa = a[i];
      final wb = b[i];
      if (wa.id != wb.id ||
          wa.x1 != wb.x1 ||
          wa.y1 != wb.y1 ||
          wa.x2 != wb.x2 ||
          wa.y2 != wb.y2 ||
          wa.customLabel != wb.customLabel ||
          wa.isVirtual != wb.isVirtual) {
        return false;
      }
    }
    return true;
  }

  /// Trace les cotes de position d'un mur libre par rapport à la pièce qui
  /// le contient : pour chaque extrémité non-jointe à un mur, on cherche
  /// le mur de pièce le plus proche dans la direction perpendiculaire au
  /// mur, et on dessine un trait pointillé + un label avec la distance.
  void _drawWallPositionDimensions({
    required Canvas canvas,
    required Size size,
    required FreeWall wall,
    required bool joinedA,
    required bool joinedB,
    required PlanLogement plan,
  }) {
    // Trouve la pièce qui contient le milieu du mur (sinon : la plus
    // proche du milieu dans une marge raisonnable).
    final mx = (wall.x1 + wall.x2) / 2;
    final my = (wall.y1 + wall.y2) / 2;
    RoomShape? containingRoom;
    for (final r in plan.rooms) {
      if (mx >= r.x &&
          mx <= r.x + r.width &&
          my >= r.y &&
          my <= r.y + r.height) {
        containingRoom = r;
        break;
      }
    }
    if (containingRoom == null) return;
    final r = containingRoom;

    // Direction du mur + perpendiculaire (en normalisé).
    final dx = wall.x2 - wall.x1;
    final dy = wall.y2 - wall.y1;
    final lenWall = math.sqrt(dx * dx + dy * dy);
    if (lenWall < 1e-4) return;
    // Perpendiculaire unitaire au mur.
    final perpX = -dy / lenWall;
    final perpY = dx / lenWall;

    final metersPerUnit = plan.scaleMetersPerUnit ?? 12.0;
    Offset toPx(double nx, double ny) =>
        Offset(nx * size.width, ny * size.height);

    void drawDimAt({
      required double px,
      required double py,
      required bool joined,
    }) {
      if (joined) return; // déjà connecté → pas de cote utile
      // Cherche la pièce sur l'axe perpendiculaire : ray-cast depuis (px,py)
      // dans la direction (perpX, perpY) puis dans la direction inverse,
      // en s'arrêtant aux 4 bords de r. Le plus proche gagne.
      double bestDist = double.infinity;
      Offset? hitPoint;
      for (final sign in [1.0, -1.0]) {
        final dirX = perpX * sign;
        final dirY = perpY * sign;
        // Intersections avec les 4 bords de la pièce.
        for (final edge in <List<double>>[
          [r.x, r.y, r.x + r.width, r.y], // top
          [r.x + r.width, r.y, r.x + r.width, r.y + r.height], // right
          [r.x, r.y + r.height, r.x + r.width, r.y + r.height], // bottom
          [r.x, r.y, r.x, r.y + r.height], // left
        ]) {
          final ex1 = edge[0], ey1 = edge[1];
          final ex2 = edge[2], ey2 = edge[3];
          final t = _rayIntersect(px, py, dirX, dirY, ex1, ey1, ex2, ey2);
          if (t != null && t > 1e-4 && t < bestDist) {
            bestDist = t;
            hitPoint = Offset(px + dirX * t, py + dirY * t);
          }
        }
      }
      if (hitPoint == null || bestDist == double.infinity) return;

      final startPx = toPx(px, py);
      final endPx = toPx(hitPoint.dx, hitPoint.dy);
      final dimPaint = Paint()
        ..color = const Color(0xFF7C3AED).withValues(alpha: 0.55)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      _drawDashedSegment(canvas, startPx, endPx, dimPaint, dash: 4, gap: 3);

      // Label de distance au milieu du segment de cote.
      final meters = bestDist * metersPerUnit;
      final label = meters >= 1.0
          ? '${meters.toStringAsFixed(2).replaceAll('.', ',')} m'
          : '${(meters * 100).round()} cm';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFF5B21B6),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.white, blurRadius: 2)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final mid = Offset(
        (startPx.dx + endPx.dx) / 2,
        (startPx.dy + endPx.dy) / 2,
      );
      // Petit fond blanc semi-translucide pour la lisibilité.
      final bgRect = Rect.fromCenter(
        center: mid,
        width: tp.width + 6,
        height: tp.height + 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
      tp.paint(
          canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height / 2));
    }

    drawDimAt(px: wall.x1, py: wall.y1, joined: joinedA);
    drawDimAt(px: wall.x2, py: wall.y2, joined: joinedB);
  }

  /// Cherche l'intersection entre la demi-droite partant de (px,py) dans
  /// la direction (dirX,dirY) et le segment [(ex1,ey1), (ex2,ey2)].
  /// Retourne le paramètre t ≥ 0 où l'intersection a lieu, ou null sinon.
  double? _rayIntersect(double px, double py, double dirX, double dirY,
      double ex1, double ey1, double ex2, double ey2) {
    final segDx = ex2 - ex1;
    final segDy = ey2 - ey1;
    final denom = dirX * (-segDy) + dirY * segDx;
    if (denom.abs() < 1e-9) return null;
    final t = ((ex1 - px) * (-segDy) + (ey1 - py) * segDx) / denom;
    final s = ((ex1 - px) * dirY - (ey1 - py) * dirX) / -denom;
    if (t < 0 || s < -1e-4 || s > 1 + 1e-4) return null;
    return t;
  }

  void _drawDashedSegment(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final total = (b - a).distance;
    if (total < 1) {
      canvas.drawLine(a, b, paint);
      return;
    }
    final dx = (b.dx - a.dx) / total;
    final dy = (b.dy - a.dy) / total;
    double pos = 0;
    while (pos < total) {
      final start = Offset(a.dx + dx * pos, a.dy + dy * pos);
      final end = Offset(
        a.dx + dx * math.min(pos + dash, total),
        a.dy + dy * math.min(pos + dash, total),
      );
      canvas.drawLine(start, end, paint);
      pos += dash + gap;
    }
  }
}

/// Painter affichant le 1ᵉʳ point posé pendant le mode "Tracer un mur"
/// (avant le 2ᵉ point, qui finalise et crée le mur).
class _DrawWallPreviewPainter extends CustomPainter {
  final Offset? p1;
  final Offset? hover;
  final bool isVirtual;
  final List<List<Offset>> existingEdges;

  _DrawWallPreviewPainter({
    required this.p1,
    this.hover,
    this.isVirtual = false,
    this.existingEdges = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (p1 == null) return;
    Offset toPx(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    final a = toPx(p1!);

    // 1) Aperçu de la future ligne (p1 → curseur) + surbrillance overlap.
    if (hover != null) {
      _paintOverlapHighlights(
        canvas: canvas,
        size: size,
        a: p1!,
        b: hover!,
        existingEdges: existingEdges,
      );
      final b = toPx(hover!);
      final paint = Paint()
        ..color = isVirtual
            ? const Color(0xFF64748B)
            : const Color(0xFF7C3AED).withValues(alpha: 0.7)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      if (isVirtual) {
        const dash = 8.0;
        const gap = 5.0;
        final total = (b - a).distance;
        if (total >= 1) {
          final dx = (b.dx - a.dx) / total;
          final dy = (b.dy - a.dy) / total;
          double pos = 0;
          while (pos < total) {
            final s = Offset(a.dx + dx * pos, a.dy + dy * pos);
            final e = Offset(
              a.dx + dx * math.min(pos + dash, total),
              a.dy + dy * math.min(pos + dash, total),
            );
            canvas.drawLine(s, e, paint);
            pos += dash + gap;
          }
        } else {
          canvas.drawLine(a, b, paint);
        }
      } else {
        canvas.drawLine(a, b, paint);
      }
    }

    // 2) Marqueur du 1er point posé.
    final fill = Paint()..color = Colors.white;
    final border = Paint()
      ..color = const Color(0xFF7C3AED)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(a, 7, fill);
    canvas.drawCircle(a, 7, border);
  }

  @override
  bool shouldRepaint(covariant _DrawWallPreviewPainter old) =>
      old.p1 != p1 ||
      old.hover != hover ||
      old.isVirtual != isVirtual ||
      old.existingEdges != existingEdges;
}

/// Bannière affichée pendant le mode "Tracer un mur". Inclut un toggle
/// pour basculer entre mur réel (trait plein) et mur virtuel (pointillé,
/// pour matérialiser une ouverture / séparation entre 2 espaces ouverts).
class _DrawWallBanner extends StatelessWidget {
  final bool point1Placed;
  final bool isVirtual;
  final VoidCallback onToggleVirtual;
  final VoidCallback onCancel;

  const _DrawWallBanner({
    required this.point1Placed,
    required this.isVirtual,
    required this.onToggleVirtual,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: const Color(0xFF5B21B6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              isVirtual ? Icons.more_horiz : Icons.linear_scale,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                point1Placed
                    ? '${isVirtual ? "Mur virtuel" : "Mur réel"} — clique le 2ᵉ point.'
                    : '${isVirtual ? "Mur virtuel" : "Mur réel"} — clique le 1ᵉʳ point.',
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, height: 1.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: onToggleVirtual,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isVirtual
                      ? Colors.amber.withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isVirtual ? Icons.check : Icons.more_horiz,
                      size: 14,
                      color: isVirtual
                          ? const Color(0xFF7A4F00)
                          : Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Virtuel',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isVirtual
                            ? const Color(0xFF7A4F00)
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Annuler'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bannière de contrôle affichée pendant le mode calibration.
class _CalibrateBanner extends StatelessWidget {
  final bool point1Placed;
  final VoidCallback onCancel;

  const _CalibrateBanner({
    required this.point1Placed,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: const Color(0xFF065F46),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.straighten, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                point1Placed
                    ? 'Clique le 2ᵉ point pour fermer la distance à calibrer.'
                    : 'Clique le 1ᵉʳ point d\'une distance connue (ex. extrémité d\'un mur).',
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, height: 1.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Annuler'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter affichant les 2 points de calibration et la ligne entre eux.
class _CalibratePreviewPainter extends CustomPainter {
  final Offset? p1;
  final Offset? p2;

  _CalibratePreviewPainter({required this.p1, required this.p2});

  @override
  void paint(Canvas canvas, Size size) {
    if (p1 == null) return;
    Offset toPx(Offset p) => Offset(p.dx * size.width, p.dy * size.height);

    final dotFill = Paint()..color = Colors.white;
    final dotBorder = Paint()
      ..color = const Color(0xFF059669)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final linePaint = Paint()
      ..color = const Color(0xFF059669)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final a = toPx(p1!);
    canvas.drawCircle(a, 7, dotFill);
    canvas.drawCircle(a, 7, dotBorder);

    if (p2 != null) {
      final b = toPx(p2!);
      canvas.drawLine(a, b, linePaint);
      canvas.drawCircle(b, 7, dotFill);
      canvas.drawCircle(b, 7, dotBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _CalibratePreviewPainter old) =>
      old.p1 != p1 || old.p2 != p2;
}
