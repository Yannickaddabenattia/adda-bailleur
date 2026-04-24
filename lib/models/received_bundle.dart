import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

/// Archive reçue depuis un propriétaire.
///
/// Contient un snapshot JSON des EDL / quittances partagés au moment du
/// transfert. Les données sont consultées en lecture seule — le locataire
/// ne peut pas les modifier.
class ReceivedBundle {
  final String id;
  final String fromName; // prénom + nom du propriétaire (snapshot)
  final String fromEmail;
  final DateTime receivedAt;
  final String payloadJson; // JSON sérialisé du partage

  ReceivedBundle({
    required this.id,
    required this.fromName,
    required this.fromEmail,
    required this.receivedAt,
    required this.payloadJson,
  });

  factory ReceivedBundle.create({
    required String fromName,
    required String fromEmail,
    required String payloadJson,
  }) {
    return ReceivedBundle(
      id: const Uuid().v4(),
      fromName: fromName,
      fromEmail: fromEmail,
      receivedAt: DateTime.now().toUtc(),
      payloadJson: payloadJson,
    );
  }
}

class ReceivedBundleAdapter extends TypeAdapter<ReceivedBundle> {
  @override
  final int typeId = 9;

  @override
  ReceivedBundle read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return ReceivedBundle(
      id: fields[0] as String,
      fromName: fields[1] as String,
      fromEmail: fields[2] as String,
      receivedAt: DateTime.parse(fields[3] as String),
      payloadJson: fields[4] as String,
    );
  }

  @override
  void write(BinaryWriter writer, ReceivedBundle obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.fromName)
      ..writeByte(2)
      ..write(obj.fromEmail)
      ..writeByte(3)
      ..write(obj.receivedAt.toUtc().toIso8601String())
      ..writeByte(4)
      ..write(obj.payloadJson);
  }
}
