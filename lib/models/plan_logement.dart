import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

enum PlanKind {
  niveau,
  dependance,
  terrain;

  String get label {
    switch (this) {
      case PlanKind.niveau:
        return 'Niveau';
      case PlanKind.dependance:
        return 'Dépendance';
      case PlanKind.terrain:
        return 'Terrain';
    }
  }

  static PlanKind fromString(String value) {
    return PlanKind.values.firstWhere(
      (k) => k.name == value,
      orElse: () => PlanKind.niveau,
    );
  }
}

/// Une pièce posée sur le canvas — coordonnées normalisées 0..1
/// pour rester indépendant de la taille d'écran.
///
/// Mode rectangle (par défaut) : x, y, width, height définissent le rect.
/// Mode polygone (forme libre) : [vertices] non null → liste plate
/// `[x0, y0, x1, y1, ...]` ; x/y/width/height sont alors la bbox calculée.
class RoomShape {
  final String id;
  String name;
  double x;
  double y;
  double width;
  double height;
  int colorIndex;

  /// Murs explicitement supprimés par le propriétaire (long-press).
  /// - Pour un rectangle : 'top', 'right', 'bottom', 'left'.
  /// - Pour un polygone : 'edge:0', 'edge:1', ... (index d'arête).
  List<String> hiddenWalls;

  /// Sommets en coordonnées normalisées, stockés à plat
  /// `[x0, y0, x1, y1, ...]`. Null = pièce rectangulaire classique.
  List<double>? vertices;

  /// Mur portant une porte de garage. Valeurs possibles :
  /// 'top' / 'right' / 'bottom' / 'left' (sur rectangle), ou 'edge:N' (sur
  /// polygone). `null` = pas de porte de garage. Activée automatiquement
  /// pour les pièces nommées « Garage » à la création.
  String? garageDoorSide;

  /// Largeur de la porte de garage, en ratio (0..1) de la longueur du mur
  /// désigné. 0.5 = porte qui occupe la moitié du mur, centrée.
  /// `null` = pas de porte. Modifiable par l'utilisateur (poignées de
  /// redimensionnement dans l'éditeur).
  double? garageDoorRatio;

  RoomShape({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.colorIndex = 0,
    List<String>? hiddenWalls,
    this.vertices,
    this.garageDoorSide,
    this.garageDoorRatio,
  }) : hiddenWalls = hiddenWalls ?? <String>[];

  factory RoomShape.create({
    required String name,
    required double x,
    required double y,
    double width = 0.25,
    double height = 0.18,
    int colorIndex = 0,
  }) {
    return RoomShape(
      id: const Uuid().v4(),
      name: name,
      x: x,
      y: y,
      width: width,
      height: height,
      colorIndex: colorIndex,
    );
  }

  /// `true` si la pièce a une porte de garage configurée.
  bool get hasGarageDoor =>
      garageDoorSide != null &&
      garageDoorRatio != null &&
      garageDoorRatio! > 0;

  bool get isPolygon => vertices != null && vertices!.length >= 6;

  /// Nombre de sommets (≥ 3 si polygone, sinon 4 implicites).
  int get vertexCount => isPolygon ? vertices!.length ~/ 2 : 4;

  /// Renvoie la i-ème paire (vx, vy) en coordonnées normalisées.
  /// Pour un rectangle : 0=TL, 1=TR, 2=BR, 3=BL.
  ({double vx, double vy}) vertexAt(int i) {
    if (isPolygon) {
      final v = vertices!;
      final n = v.length ~/ 2;
      final k = ((i % n) + n) % n;
      return (vx: v[k * 2], vy: v[k * 2 + 1]);
    }
    switch (((i % 4) + 4) % 4) {
      case 0:
        return (vx: x, vy: y);
      case 1:
        return (vx: x + width, vy: y);
      case 2:
        return (vx: x + width, vy: y + height);
      default:
        return (vx: x, vy: y + height);
    }
  }

  /// Recalcule la bounding-box d'un polygone et met à jour x/y/width/height.
  void recomputeBounds() {
    if (!isPolygon) return;
    final v = vertices!;
    double minX = v[0], maxX = v[0], minY = v[1], maxY = v[1];
    for (var i = 0; i < v.length; i += 2) {
      if (v[i] < minX) minX = v[i];
      if (v[i] > maxX) maxX = v[i];
      if (v[i + 1] < minY) minY = v[i + 1];
      if (v[i + 1] > maxY) maxY = v[i + 1];
    }
    x = minX;
    y = minY;
    width = (maxX - minX).clamp(0.001, 1.0);
    height = (maxY - minY).clamp(0.001, 1.0);
  }

  /// Convertit en polygone à 4 sommets si pas déjà polygonal.
  /// hiddenWalls 'top'/'right'/'bottom'/'left' deviennent 'edge:0/1/2/3'.
  void convertToPolygon() {
    if (isPolygon) return;
    vertices = <double>[
      x, y,
      x + width, y,
      x + width, y + height,
      x, y + height,
    ];
    const sideToEdge = {
      'top': 'edge:0',
      'right': 'edge:1',
      'bottom': 'edge:2',
      'left': 'edge:3',
    };
    hiddenWalls = hiddenWalls
        .map((s) => sideToEdge[s] ?? s)
        .toList();
  }

  /// Repasse en rectangle pur : recalcule la bbox, supprime les vertices.
  /// hiddenWalls 'edge:N' sont remappés vers top/right/bottom/left si N<4,
  /// sinon ignorés.
  void convertToRectangle() {
    if (!isPolygon) return;
    recomputeBounds();
    vertices = null;
    const edgeToSide = {
      'edge:0': 'top',
      'edge:1': 'right',
      'edge:2': 'bottom',
      'edge:3': 'left',
    };
    hiddenWalls = hiddenWalls
        .map((s) => edgeToSide[s] ?? s)
        .where((s) =>
            s == 'top' || s == 'right' || s == 'bottom' || s == 'left')
        .toList();
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'colorIndex': colorIndex,
        'hiddenWalls': hiddenWalls,
        if (vertices != null) 'vertices': vertices,
        if (garageDoorSide != null) 'garageDoorSide': garageDoorSide,
        if (garageDoorRatio != null) 'garageDoorRatio': garageDoorRatio,
      };

  factory RoomShape.fromMap(Map<String, dynamic> m) => RoomShape(
        id: m['id'] as String,
        name: m['name'] as String,
        x: (m['x'] as num).toDouble(),
        y: (m['y'] as num).toDouble(),
        width: (m['width'] as num).toDouble(),
        height: (m['height'] as num).toDouble(),
        colorIndex: (m['colorIndex'] as num?)?.toInt() ?? 0,
        hiddenWalls:
            (m['hiddenWalls'] as List?)?.cast<String>() ?? <String>[],
        vertices: (m['vertices'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList(),
        garageDoorSide: m['garageDoorSide'] as String?,
        garageDoorRatio: (m['garageDoorRatio'] as num?)?.toDouble(),
      );
}

/// Photo d'un mur d'une pièce, prise via appui long sur le numéro de mur.
/// Stockée à part des annotations pour rester accessible depuis l'EDL.
class WallPhoto {
  final String id;
  String roomId;
  /// 'top' | 'right' | 'bottom' | 'left' (rect) ou 'edge' (polygone).
  /// Pour les photos extérieures (`isExterior` = true), la valeur n'a pas
  /// de sens géométrique : on stocke arbitrairement 'exterior'.
  String side;
  /// Numéro du mur (M1, M2…) au moment de la prise. Utilisé pour l'affichage
  /// si la numérotation change ensuite (par exemple après suppression d'un
  /// mur), on garde la trace du numéro affiché lors de la prise.
  int wallNumber;
  /// Nom de la pièce au moment de la prise (pour l'affichage stable).
  /// Pour les photos extérieures, on stocke une étiquette libre
  /// (« Façade nord », « Pignon ouest », « Toiture », etc.).
  String roomName;
  /// Chemin local du fichier image.
  String path;
  final DateTime takenAt;
  /// EDL auquel cette photo est rattachée. Null = photo de plan « générique »
  /// (héritage avant v3.3) ; sinon visible uniquement dans cet EDL.
  String? etatId;
  /// Index d'arête pour les pièces polygonales. Null pour rectangles.
  int? edgeIndex;

  /// `true` si cette photo représente un mur extérieur / une façade
  /// (et non un mur intérieur d'une pièce). Permet de les afficher
  /// dans une section dédiée du plan et du PDF.
  bool isExterior;

  /// Identifiant du mur libre (FreeWall) auquel cette photo est rattachée.
  /// `null` = photo classique attachée à un mur de pièce. Quand non null,
  /// `roomId` peut être vide et `side`/`wallNumber` sont indicatifs.
  String? freeWallId;

  WallPhoto({
    required this.id,
    required this.roomId,
    required this.side,
    required this.wallNumber,
    required this.roomName,
    required this.path,
    required this.takenAt,
    this.etatId,
    this.edgeIndex,
    this.isExterior = false,
    this.freeWallId,
  });

  factory WallPhoto.create({
    required String roomId,
    required String side,
    required int wallNumber,
    required String roomName,
    required String path,
    String? etatId,
    int? edgeIndex,
    bool isExterior = false,
    String? freeWallId,
  }) {
    return WallPhoto(
      id: const Uuid().v4(),
      roomId: roomId,
      side: side,
      wallNumber: wallNumber,
      roomName: roomName,
      path: path,
      takenAt: DateTime.now().toUtc(),
      etatId: etatId,
      edgeIndex: edgeIndex,
      isExterior: isExterior,
      freeWallId: freeWallId,
    );
  }

  String get label => isExterior ? roomName : 'M$wallNumber';
  bool get isOnFreeWall =>
      freeWallId != null && freeWallId!.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'id': id,
        'roomId': roomId,
        'side': side,
        'wallNumber': wallNumber,
        'roomName': roomName,
        'path': path,
        'takenAt': takenAt.toUtc().toIso8601String(),
        if (etatId != null) 'etatId': etatId,
        if (edgeIndex != null) 'edgeIndex': edgeIndex,
        if (isExterior) 'isExterior': true,
        if (freeWallId != null) 'freeWallId': freeWallId,
      };

  factory WallPhoto.fromMap(Map<String, dynamic> m) => WallPhoto(
        id: m['id'] as String,
        roomId: m['roomId'] as String,
        side: m['side'] as String,
        wallNumber: (m['wallNumber'] as num).toInt(),
        roomName: m['roomName'] as String,
        path: m['path'] as String,
        isExterior: (m['isExterior'] as bool?) ?? false,
        takenAt: DateTime.parse(m['takenAt'] as String),
        etatId: m['etatId'] as String?,
        edgeIndex: (m['edgeIndex'] as num?)?.toInt(),
        freeWallId: m['freeWallId'] as String?,
      );
}

/// Repère posé sur un plan : ancré à une pièce (et optionnellement à un côté
/// de mur), positionné en coordonnées normalisées 0..1 sur le canevas.
class PlanAnnotation {
  final String id;
  String roomId;
  String? wallSide; // 'top' | 'right' | 'bottom' | 'left' | null (rect)
  double x;
  double y;
  String title;
  String description;
  final DateTime createdAt;
  /// Index d'arête pour les pièces polygonales. Null pour rectangles.
  int? wallEdgeIndex;

  PlanAnnotation({
    required this.id,
    required this.roomId,
    required this.wallSide,
    required this.x,
    required this.y,
    required this.title,
    required this.description,
    required this.createdAt,
    this.wallEdgeIndex,
  });

  factory PlanAnnotation.create({
    required String roomId,
    String? wallSide,
    required double x,
    required double y,
    String title = '',
    String description = '',
    int? wallEdgeIndex,
  }) {
    return PlanAnnotation(
      id: const Uuid().v4(),
      roomId: roomId,
      wallSide: wallSide,
      x: x,
      y: y,
      title: title.trim(),
      description: description.trim(),
      createdAt: DateTime.now().toUtc(),
      wallEdgeIndex: wallEdgeIndex,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'roomId': roomId,
        'wallSide': wallSide,
        'x': x,
        'y': y,
        'title': title,
        'description': description,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (wallEdgeIndex != null) 'wallEdgeIndex': wallEdgeIndex,
      };

  factory PlanAnnotation.fromMap(Map<String, dynamic> m) => PlanAnnotation(
        id: m['id'] as String,
        roomId: m['roomId'] as String,
        wallSide: m['wallSide'] as String?,
        x: (m['x'] as num).toDouble(),
        y: (m['y'] as num).toDouble(),
        title: m['title'] as String,
        description: m['description'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        wallEdgeIndex: (m['wallEdgeIndex'] as num?)?.toInt(),
      );
}

/// Un mur libre tracé hors d'une pièce, déplaçable indépendamment. Numéroté
/// automatiquement selon sa pièce de référence (la plus proche du milieu du
/// mur) sous la forme « Mur Salon M12 » sauf si l'utilisateur le renomme.
class FreeWall {
  final String id;
  double x1;
  double y1;
  double x2;
  double y2;

  /// Nom personnalisé saisi par l'utilisateur. Null = utiliser le label
  /// calculé automatiquement par PlanLogement.autoLabelForWall.
  String? customLabel;

  /// `true` = mur virtuel (ouverture / séparation visuelle entre 2 espaces
  /// ouverts) : rendu en pointillé, nommé "Séparation A / B". `false` = mur
  /// réel classique (trait plein, nommé "Mur {pièce} M{N}").
  bool isVirtual;

  FreeWall({
    required this.id,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.customLabel,
    this.isVirtual = false,
  });

  factory FreeWall.create({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    bool isVirtual = false,
  }) =>
      FreeWall(
        id: const Uuid().v4(),
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        isVirtual: isVirtual,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'customLabel': customLabel,
        'isVirtual': isVirtual,
      };

  factory FreeWall.fromMap(Map<String, dynamic> m) => FreeWall(
        id: m['id'] as String,
        x1: (m['x1'] as num).toDouble(),
        y1: (m['y1'] as num).toDouble(),
        x2: (m['x2'] as num).toDouble(),
        y2: (m['y2'] as num).toDouble(),
        customLabel: m['customLabel'] as String?,
        isVirtual: (m['isVirtual'] as bool?) ?? false,
      );
}

/// Un plan attaché à un logement, soit une image importée, soit un dessin
/// vectoriel composé de [RoomShape]s.
class PlanLogement {
  final String id;
  final String logementId;
  PlanKind kind;
  String name;
  String? imagePath;
  List<RoomShape> rooms;
  List<PlanAnnotation> annotations;
  List<WallPhoto> wallPhotos;
  List<FreeWall> freeWalls;
  int sortOrder;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Échelle réelle du plan : combien de mètres représente une unité du
  /// repère normalisé (canvas = 1.0 × 1.0). `null` = plan non calibré
  /// (aucune cote affichée). Calibré via l'outil « Calibrer l'échelle ».
  double? scaleMetersPerUnit;

  PlanLogement({
    required this.id,
    required this.logementId,
    required this.kind,
    required this.name,
    required this.imagePath,
    required this.rooms,
    required this.annotations,
    required this.wallPhotos,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    List<FreeWall>? freeWalls,
    this.scaleMetersPerUnit,
  }) : freeWalls = freeWalls ?? <FreeWall>[];

  factory PlanLogement.create({
    required String logementId,
    required PlanKind kind,
    required String name,
    String? imagePath,
    List<RoomShape>? rooms,
    List<PlanAnnotation>? annotations,
    List<WallPhoto>? wallPhotos,
    int sortOrder = 0,
  }) {
    final now = DateTime.now().toUtc();
    return PlanLogement(
      id: const Uuid().v4(),
      logementId: logementId,
      kind: kind,
      name: name.trim(),
      imagePath: imagePath,
      rooms: rooms ?? [],
      annotations: annotations ?? [],
      wallPhotos: wallPhotos ?? [],
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
  }

  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;
  bool get hasDrawing => rooms.isNotEmpty || freeWalls.isNotEmpty;
  bool get isCalibrated => scaleMetersPerUnit != null && scaleMetersPerUnit! > 0;

  /// Convertit une distance en unités normalisées (0..1) en mètres si le
  /// plan est calibré, sinon retourne null.
  double? unitsToMeters(double units) =>
      isCalibrated ? units * scaleMetersPerUnit! : null;

  /// Libellé automatique pour un mur libre. Comportement :
  ///
  /// - **Mur réel** : « Mur ${pieceProche} M${N} » où N est l'index 1-based
  ///   du mur dans freeWalls. Cherche la pièce dont le centroïde est le
  ///   plus proche du milieu du mur.
  /// - **Mur virtuel** : tente d'identifier les 2 pièces de part et d'autre
  ///   du mur (en regardant les pièces qui contiennent chacune des extrémités
  ///   ou sont les plus proches). Si 2 pièces distinctes trouvées →
  ///   « Séparation A / B ». Si 1 seule → « Séparation interne A ». Sinon →
  ///   « Mur virtuel M{N} ».
  String autoLabelForWall(FreeWall wall) {
    final idx = freeWalls.indexOf(wall);
    final n = idx >= 0 ? idx + 1 : freeWalls.length + 1;
    if (wall.isVirtual) {
      return _virtualWallLabel(wall, n);
    }
    return _solidWallLabel(wall, n);
  }

  String _solidWallLabel(FreeWall wall, int n) {
    final mx = (wall.x1 + wall.x2) / 2;
    final my = (wall.y1 + wall.y2) / 2;
    String? nearestRoom;
    double bestDist = 0.18;
    for (final r in rooms) {
      final cx = r.x + r.width / 2;
      final cy = r.y + r.height / 2;
      final dx = mx - cx;
      final dy = my - cy;
      final d = (dx * dx + dy * dy);
      if (d < bestDist * bestDist) {
        bestDist = d == 0 ? 1e-6 : d;
        nearestRoom = r.name;
      }
    }
    final base = nearestRoom == null ? 'Mur' : 'Mur $nearestRoom';
    return '$base M$n';
  }

  String _virtualWallLabel(FreeWall wall, int n) {
    // Trouve les pièces "à proximité" de chaque extrémité (qui contiennent
    // le point dans leur bbox, ou dont le centroïde est très proche).
    final p1 = (wall.x1, wall.y1);
    final p2 = (wall.x2, wall.y2);
    final roomA = _bestMatchingRoom(p1.$1, p1.$2);
    final roomB = _bestMatchingRoom(p2.$1, p2.$2);
    if (roomA != null && roomB != null) {
      if (roomA.id == roomB.id) {
        return 'Séparation interne ${roomA.name}';
      }
      // Trie alphabétique pour stabilité du libellé quelle que soit l'ordre
      // dans lequel on a posé les points.
      final names = [roomA.name, roomB.name]..sort();
      return 'Séparation ${names[0]} / ${names[1]}';
    }
    if (roomA != null || roomB != null) {
      final r = roomA ?? roomB!;
      return 'Séparation ${r.name}';
    }
    return 'Mur virtuel M$n';
  }

  /// Trouve la pièce la plus pertinente pour un point donné : prend la
  /// pièce dont la bbox contient le point ; à défaut la plus proche dans
  /// un rayon de 8% du canvas.
  RoomShape? _bestMatchingRoom(double x, double y) {
    // Priorité : bbox contenant le point.
    for (final r in rooms) {
      if (x >= r.x &&
          x <= r.x + r.width &&
          y >= r.y &&
          y <= r.y + r.height) {
        return r;
      }
    }
    // Sinon : la plus proche dans un rayon raisonnable.
    RoomShape? best;
    double bestDist = 0.08;
    for (final r in rooms) {
      final cx = r.x + r.width / 2;
      final cy = r.y + r.height / 2;
      final dx = x - cx;
      final dy = y - cy;
      final d2 = dx * dx + dy * dy;
      if (d2 < bestDist * bestDist) {
        bestDist = d2 == 0 ? 1e-6 : d2;
        best = r;
      }
    }
    return best;
  }

  /// Libellé effectif d'un mur (custom si défini, sinon auto).
  String labelForWall(FreeWall wall) =>
      (wall.customLabel != null && wall.customLabel!.trim().isNotEmpty)
          ? wall.customLabel!
          : autoLabelForWall(wall);

  Map<String, dynamic> toMap() => {
        'id': id,
        'logementId': logementId,
        'kind': kind.name,
        'name': name,
        'imagePath': imagePath,
        'rooms': rooms.map((r) => r.toMap()).toList(),
        'annotations': annotations.map((a) => a.toMap()).toList(),
        'wallPhotos': wallPhotos.map((w) => w.toMap()).toList(),
        'freeWalls': freeWalls.map((w) => w.toMap()).toList(),
        'sortOrder': sortOrder,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'scaleMetersPerUnit': scaleMetersPerUnit,
      };

  factory PlanLogement.fromMap(Map<String, dynamic> m) => PlanLogement(
        id: m['id'] as String,
        logementId: m['logementId'] as String,
        kind: PlanKind.fromString(m['kind'] as String),
        name: m['name'] as String,
        imagePath: m['imagePath'] as String?,
        rooms: ((m['rooms'] as List?) ?? const [])
            .map((e) => RoomShape.fromMap(e as Map<String, dynamic>))
            .toList(),
        annotations: ((m['annotations'] as List?) ?? const [])
            .map((e) => PlanAnnotation.fromMap(e as Map<String, dynamic>))
            .toList(),
        wallPhotos: ((m['wallPhotos'] as List?) ?? const [])
            .map((e) => WallPhoto.fromMap(e as Map<String, dynamic>))
            .toList(),
        freeWalls: ((m['freeWalls'] as List?) ?? const [])
            .map((e) => FreeWall.fromMap(e as Map<String, dynamic>))
            .toList(),
        sortOrder: (m['sortOrder'] as num).toInt(),
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
        scaleMetersPerUnit: (m['scaleMetersPerUnit'] as num?)?.toDouble(),
      );
}

class RoomShapeAdapter extends TypeAdapter<RoomShape> {
  @override
  final int typeId = 11;

  @override
  RoomShape read(BinaryReader reader) {
    final n = reader.readByte();
    final f = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return RoomShape(
      id: f[0] as String,
      name: f[1] as String,
      x: f[2] as double,
      y: f[3] as double,
      width: f[4] as double,
      height: f[5] as double,
      colorIndex: f[6] as int,
      hiddenWalls: f.containsKey(7)
          ? (f[7] as List).cast<String>()
          : <String>[],
      vertices: f.containsKey(8)
          ? (f[8] as List).map((e) => (e as num).toDouble()).toList()
          : null,
      garageDoorSide: f[9] as String?,
      garageDoorRatio: (f[10] as num?)?.toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, RoomShape obj) {
    final hasPoly = obj.vertices != null;
    final hasDoor = obj.garageDoorSide != null;
    final fieldCount = 8 + (hasPoly ? 1 : 0) + (hasDoor ? 2 : 0);
    writer
      ..writeByte(fieldCount)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.x)
      ..writeByte(3)
      ..write(obj.y)
      ..writeByte(4)
      ..write(obj.width)
      ..writeByte(5)
      ..write(obj.height)
      ..writeByte(6)
      ..write(obj.colorIndex)
      ..writeByte(7)
      ..write(obj.hiddenWalls);
    if (hasPoly) {
      writer
        ..writeByte(8)
        ..write(obj.vertices);
    }
    if (hasDoor) {
      writer
        ..writeByte(9)
        ..write(obj.garageDoorSide)
        ..writeByte(10)
        ..write(obj.garageDoorRatio);
    }
  }
}

class PlanLogementAdapter extends TypeAdapter<PlanLogement> {
  @override
  final int typeId = 10;

  @override
  PlanLogement read(BinaryReader reader) {
    final n = reader.readByte();
    final f = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return PlanLogement(
      id: f[0] as String,
      logementId: f[1] as String,
      kind: PlanKind.fromString(f[2] as String),
      name: f[3] as String,
      imagePath: f[4] as String?,
      rooms: (f[5] as List).cast<RoomShape>(),
      sortOrder: f[6] as int,
      createdAt: DateTime.parse(f[7] as String),
      updatedAt: DateTime.parse(f[8] as String),
      annotations: f.containsKey(9)
          ? (f[9] as List).cast<PlanAnnotation>()
          : <PlanAnnotation>[],
      wallPhotos: f.containsKey(10)
          ? (f[10] as List).cast<WallPhoto>()
          : <WallPhoto>[],
      scaleMetersPerUnit: (f[11] as num?)?.toDouble(),
      freeWalls: f.containsKey(12)
          ? (f[12] as List).cast<FreeWall>()
          : <FreeWall>[],
    );
  }

  @override
  void write(BinaryWriter writer, PlanLogement obj) {
    final hasScale = obj.scaleMetersPerUnit != null;
    final hasFreeWalls = obj.freeWalls.isNotEmpty;
    final count = 11 + (hasScale ? 1 : 0) + (hasFreeWalls ? 1 : 0);
    writer
      ..writeByte(count)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.logementId)
      ..writeByte(2)
      ..write(obj.kind.name)
      ..writeByte(3)
      ..write(obj.name)
      ..writeByte(4)
      ..write(obj.imagePath)
      ..writeByte(5)
      ..write(obj.rooms)
      ..writeByte(6)
      ..write(obj.sortOrder)
      ..writeByte(7)
      ..write(obj.createdAt.toIso8601String())
      ..writeByte(8)
      ..write(obj.updatedAt.toIso8601String())
      ..writeByte(9)
      ..write(obj.annotations)
      ..writeByte(10)
      ..write(obj.wallPhotos);
    if (hasScale) {
      writer
        ..writeByte(11)
        ..write(obj.scaleMetersPerUnit);
    }
    if (hasFreeWalls) {
      writer
        ..writeByte(12)
        ..write(obj.freeWalls);
    }
  }
}

class FreeWallAdapter extends TypeAdapter<FreeWall> {
  @override
  final int typeId = 21;

  @override
  FreeWall read(BinaryReader reader) {
    final n = reader.readByte();
    final f = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return FreeWall(
      id: f[0] as String,
      x1: (f[1] as num).toDouble(),
      y1: (f[2] as num).toDouble(),
      x2: (f[3] as num).toDouble(),
      y2: (f[4] as num).toDouble(),
      customLabel: f[5] as String?,
      isVirtual: (f[6] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, FreeWall obj) {
    final hasLabel = obj.customLabel != null;
    final hasVirtual = obj.isVirtual;
    final count = 5 + (hasLabel ? 1 : 0) + (hasVirtual ? 1 : 0);
    writer
      ..writeByte(count)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.x1)
      ..writeByte(2)
      ..write(obj.y1)
      ..writeByte(3)
      ..write(obj.x2)
      ..writeByte(4)
      ..write(obj.y2);
    if (hasLabel) {
      writer
        ..writeByte(5)
        ..write(obj.customLabel);
    }
    if (hasVirtual) {
      writer
        ..writeByte(6)
        ..write(true);
    }
  }
}

class WallPhotoAdapter extends TypeAdapter<WallPhoto> {
  @override
  final int typeId = 13;

  @override
  WallPhoto read(BinaryReader reader) {
    final n = reader.readByte();
    final f = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return WallPhoto(
      id: f[0] as String,
      roomId: f[1] as String,
      side: f[2] as String,
      wallNumber: f[3] as int,
      roomName: f[4] as String,
      path: f[5] as String,
      takenAt: DateTime.parse(f[6] as String),
      etatId: f.containsKey(7) ? f[7] as String? : null,
      edgeIndex: f.containsKey(8) ? f[8] as int? : null,
      isExterior: f.containsKey(9) ? (f[9] as bool? ?? false) : false,
      freeWallId: f.containsKey(10) ? f[10] as String? : null,
    );
  }

  @override
  void write(BinaryWriter writer, WallPhoto obj) {
    final hasFreeWall = obj.freeWallId != null;
    writer
      ..writeByte(hasFreeWall ? 11 : 10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.roomId)
      ..writeByte(2)
      ..write(obj.side)
      ..writeByte(3)
      ..write(obj.wallNumber)
      ..writeByte(4)
      ..write(obj.roomName)
      ..writeByte(5)
      ..write(obj.path)
      ..writeByte(6)
      ..write(obj.takenAt.toIso8601String())
      ..writeByte(7)
      ..write(obj.etatId)
      ..writeByte(8)
      ..write(obj.edgeIndex)
      ..writeByte(9)
      ..write(obj.isExterior);
    if (hasFreeWall) {
      writer
        ..writeByte(10)
        ..write(obj.freeWallId);
    }
  }
}

class PlanAnnotationAdapter extends TypeAdapter<PlanAnnotation> {
  @override
  final int typeId = 12;

  @override
  PlanAnnotation read(BinaryReader reader) {
    final n = reader.readByte();
    final f = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return PlanAnnotation(
      id: f[0] as String,
      roomId: f[1] as String,
      wallSide: f[2] as String?,
      x: f[3] as double,
      y: f[4] as double,
      title: f[5] as String,
      description: f[6] as String,
      createdAt: DateTime.parse(f[7] as String),
      wallEdgeIndex: f.containsKey(8) ? f[8] as int? : null,
    );
  }

  @override
  void write(BinaryWriter writer, PlanAnnotation obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.roomId)
      ..writeByte(2)
      ..write(obj.wallSide)
      ..writeByte(3)
      ..write(obj.x)
      ..writeByte(4)
      ..write(obj.y)
      ..writeByte(5)
      ..write(obj.title)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.createdAt.toIso8601String())
      ..writeByte(8)
      ..write(obj.wallEdgeIndex);
  }
}
