import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import 'etat_element.dart';

/// Un élément à inspecter dans une pièce (ex: évier, sol, robinetterie).
class ElementPiece {
  final String id;
  String nom;
  EtatElement etat;
  String description;
  List<String> photoPaths;

  ElementPiece({
    required this.id,
    required this.nom,
    required this.etat,
    required this.description,
    required this.photoPaths,
  });

  factory ElementPiece.create({
    required String nom,
    EtatElement etat = EtatElement.bon,
    String description = '',
    List<String> photoPaths = const [],
  }) {
    return ElementPiece(
      id: const Uuid().v4(),
      nom: nom.trim(),
      etat: etat,
      description: description.trim(),
      photoPaths: List<String>.from(photoPaths),
    );
  }

  /// Empreinte utilisée dans le calcul du hash d'intégrité de l'EDL.
  String get canonicalForHash {
    return [
      id,
      nom.trim(),
      etat.name,
      description.trim(),
      photoPaths.join(','),
    ].join('::');
  }
}

class ElementPieceAdapter extends TypeAdapter<ElementPiece> {
  @override
  final int typeId = 7;

  @override
  ElementPiece read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return ElementPiece(
      id: fields[0] as String,
      nom: fields[1] as String,
      etat: EtatElement.fromString(fields[2] as String),
      description: fields[3] as String,
      photoPaths: (fields[4] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, ElementPiece obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.nom)
      ..writeByte(2)
      ..write(obj.etat.name)
      ..writeByte(3)
      ..write(obj.description)
      ..writeByte(4)
      ..write(obj.photoPaths);
  }
}
