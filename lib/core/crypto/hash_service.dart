import 'dart:convert';
import 'package:crypto/crypto.dart';

class HashService {
  /// Retourne le hash SHA-256 hexadécimal d'une chaîne.
  static String sha256Hex(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  /// Calcule le hash d'intégrité d'un profil utilisateur à partir
  /// de ses champs immuables. Utilisé pour détecter toute altération.
  static String userIntegrityHash({
    required String role,
    required String firstName,
    required String lastName,
    required String email,
    required DateTime createdAt,
  }) {
    final payload = [
      role.trim().toLowerCase(),
      firstName.trim(),
      lastName.trim(),
      email.trim().toLowerCase(),
      createdAt.toUtc().toIso8601String(),
    ].join('|');
    return sha256Hex(payload);
  }
}
