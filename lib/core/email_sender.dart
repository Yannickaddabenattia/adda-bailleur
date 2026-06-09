import 'dart:io';

import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:share_plus/share_plus.dart';

/// Envoi d'un fichier par e-mail.
///
/// Sur **Android / iOS**, ouvre directement le composeur d'e-mail du téléphone
/// avec la **pièce jointe**, le destinataire, l'objet et le corps pré-remplis.
/// Sur **desktop (macOS / Linux)** — ou si aucun client mail n'est configuré —
/// repli automatique sur la feuille de partage du système (où l'utilisateur
/// choisit Mail, le fichier restant attaché).
class EmailSender {
  static Future<void> sendWithAttachment({
    required String path,
    required String subject,
    required String body,
    List<String> recipients = const [],
    String? mimeType,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await FlutterEmailSender.send(
          Email(
            subject: subject,
            body: body,
            recipients: recipients,
            attachmentPaths: [path],
          ),
        );
        return;
      } catch (_) {
        // Pas de client mail configuré : repli sur le partage générique.
      }
    }
    await Share.shareXFiles(
      [XFile(path, mimeType: mimeType)],
      subject: subject,
      text: body,
    );
  }
}
