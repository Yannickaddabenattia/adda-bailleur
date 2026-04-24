import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import 'element_piece.dart';

/// Une pièce d'un logement (cuisine, salon, chambre...).
class Piece {
  final String id;
  String nom;
  List<ElementPiece> elements;

  Piece({
    required this.id,
    required this.nom,
    required this.elements,
  });

  factory Piece.create({required String nom, List<ElementPiece>? elements}) {
    return Piece(
      id: const Uuid().v4(),
      nom: nom.trim(),
      elements: elements ?? <ElementPiece>[],
    );
  }

  String get canonicalForHash {
    final elementsHash = elements.map((e) => e.canonicalForHash).join('|');
    return '$id::${nom.trim()}::$elementsHash';
  }
}

class PieceAdapter extends TypeAdapter<Piece> {
  @override
  final int typeId = 6;

  @override
  Piece read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return Piece(
      id: fields[0] as String,
      nom: fields[1] as String,
      elements: (fields[2] as List).cast<ElementPiece>(),
    );
  }

  @override
  void write(BinaryWriter writer, Piece obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.nom)
      ..writeByte(2)
      ..write(obj.elements);
  }
}
