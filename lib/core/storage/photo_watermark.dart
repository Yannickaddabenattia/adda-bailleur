import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

/// Résultat d'un tatouage : date+heure réellement gravée et hash SHA-256 du
/// fichier final (post-watermark) pour vérification ultérieure.
class PhotoStampResult {
  final DateTime capturedAt;
  final String sha256;
  const PhotoStampResult({required this.capturedAt, required this.sha256});

  String get sha256Short =>
      sha256.length >= 8 ? sha256.substring(0, 8) : sha256;
}

/// Grave un horodatage dans le coin inférieur droit de l'image (filigrane
/// JPEG). Utilisé pour les photos prises dans le cadre d'un état des lieux,
/// afin que la date+heure soit attestée visuellement sur l'image elle-même.
class PhotoWatermark {
  static final _df = DateFormat('dd/MM/yyyy HH:mm', 'fr_FR');

  /// Lit [file], décode l'image, dessine la date+heure (locale) en bas à
  /// droite avec fond semi-transparent, ré-encode en JPEG et écrase le
  /// fichier. Si [label] est fourni (p.ex. "Salon · M2"), il est gravé sur
  /// une ligne au-dessus de la date.
  ///
  /// Le hash SHA-256 des octets sources (pré-tatouage) est calculé ; ses 8
  /// premiers caractères sont gravés en `#XXXXXXXX` sous la date pour
  /// faciliter la vérification croisée avec la métadonnée stockée.
  ///
  /// Si l'image ne peut pas être décodée, le fichier est laissé tel quel et
  /// `null` est retourné.
  static Future<PhotoStampResult?> stampInPlace(
    File file, {
    DateTime? at,
    String? label,
  }) async {
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final capturedAt = (at ?? DateTime.now()).toUtc();
    final sourceHash = sha256.convert(bytes).toString();
    final hashShort = sourceHash.substring(0, 8);

    final stamp = _df.format(capturedAt.toLocal());
    final lines = <String>[
      if (label != null && label.trim().isNotEmpty) label.trim(),
      stamp,
      '#$hashShort',
    ];

    final width = decoded.width;
    final font = width >= 2000
        ? img.arial48
        : width >= 1000
            ? img.arial24
            : img.arial14;
    final fontHeight = font.lineHeight;
    final fontCharW = (fontHeight * 0.55).round();

    final longest =
        lines.fold<int>(0, (m, s) => math.max(m, s.length));
    final textWidth = longest * fontCharW;
    final padX = (fontHeight * 0.5).round();
    final padY = (fontHeight * 0.3).round();
    final lineGap = lines.length > 1 ? (fontHeight * 0.2).round() : 0;
    final boxW = textWidth + padX * 2;
    final boxH =
        fontHeight * lines.length + lineGap * (lines.length - 1) + padY * 2;
    final margin = (fontHeight * 0.5).round();
    final boxLeft = (decoded.width - boxW - margin).clamp(0, decoded.width);
    final boxTop = (decoded.height - boxH - margin).clamp(0, decoded.height);

    img.fillRect(
      decoded,
      x1: boxLeft,
      y1: boxTop,
      x2: boxLeft + boxW,
      y2: boxTop + boxH,
      color: img.ColorRgba8(0, 0, 0, 160),
    );

    var y = boxTop + padY;
    for (final line in lines) {
      img.drawString(
        decoded,
        line,
        font: font,
        x: boxLeft + padX,
        y: y,
        color: img.ColorRgb8(255, 255, 255),
      );
      y += fontHeight + lineGap;
    }

    final encoded = img.encodeJpg(decoded, quality: 88);
    await file.writeAsBytes(encoded, flush: true);

    final finalHash = sha256.convert(encoded).toString();
    return PhotoStampResult(capturedAt: capturedAt, sha256: finalHash);
  }
}
