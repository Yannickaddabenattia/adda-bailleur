import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto/hash_service.dart';
import 'user_role.dart';

/// Profil utilisateur figé après configuration initiale.
///
/// Les 4 champs **immuables** (role, firstName, lastName, email) ne peuvent
/// PAS être modifiés après la création. Le champ [integrityHash] permet
/// de détecter toute tentative d'altération du stockage.
class UserProfile {
  final String id;
  final UserRole role;
  final String firstName;
  final String lastName;
  final String email;
  final DateTime createdAt;
  final String integrityHash;

  UserProfile._({
    required this.id,
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.createdAt,
    required this.integrityHash,
  });

  /// Crée un nouveau profil et calcule son hash d'intégrité.
  factory UserProfile.create({
    required UserRole role,
    required String firstName,
    required String lastName,
    required String email,
  }) {
    final now = DateTime.now().toUtc();
    final id = const Uuid().v4();
    final normFirst = firstName.trim();
    final normLast = lastName.trim().toUpperCase();
    final normEmail = email.trim().toLowerCase();
    final hash = HashService.userIntegrityHash(
      role: role.name,
      firstName: normFirst,
      lastName: normLast,
      email: normEmail,
      createdAt: now,
    );
    return UserProfile._(
      id: id,
      role: role,
      firstName: normFirst,
      lastName: normLast,
      email: normEmail,
      createdAt: now,
      integrityHash: hash,
    );
  }

  /// Recalcule le hash et le compare à celui stocké.
  /// Retourne `true` si le profil n'a pas été altéré.
  bool verifyIntegrity() {
    final expected = HashService.userIntegrityHash(
      role: role.name,
      firstName: firstName,
      lastName: lastName,
      email: email,
      createdAt: createdAt,
    );
    return expected == integrityHash;
  }

  String get fullName => '$firstName $lastName';
}

class UserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final int typeId = 1;

  @override
  UserProfile read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfile._(
      id: fields[0] as String,
      role: UserRole.fromString(fields[1] as String),
      firstName: fields[2] as String,
      lastName: fields[3] as String,
      email: fields[4] as String,
      createdAt: DateTime.parse(fields[5] as String),
      integrityHash: fields[6] as String,
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.role.name)
      ..writeByte(2)
      ..write(obj.firstName)
      ..writeByte(3)
      ..write(obj.lastName)
      ..writeByte(4)
      ..write(obj.email)
      ..writeByte(5)
      ..write(obj.createdAt.toIso8601String())
      ..writeByte(6)
      ..write(obj.integrityHash);
  }
}
