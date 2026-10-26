/// Modele danych: linia pick slipu, produkt (baza wymiarów) i grupa materiału.
library;

class PickLine {
  PickLine({
    required this.id,
    required this.location,
    required this.quantity,
    required this.uom,
    required this.materialId,
    this.done = false,
  });

  final String id;
  final String location;
  final int quantity;
  final String uom;
  final String materialId;
  bool done;

  Map<String, dynamic> toJson() => {
        'id': id,
        'location': location,
        'quantity': quantity,
        'uom': uom,
        'materialId': materialId,
        'done': done,
      };

  factory PickLine.fromJson(Map<String, dynamic> j) => PickLine(
        id: j['id'] as String,
        location: j['location'] as String? ?? '',
        quantity: (j['quantity'] as num?)?.toInt() ?? 0,
        uom: j['uom'] as String? ?? '',
        materialId: j['materialId'] as String? ?? '',
        done: j['done'] as bool? ?? false,
      );
}

/// Klasa wielkości kartonu: B (duży), M (średni), S (mały).
enum SizeClass { b, m, s, unknown }

SizeClass sizeClassOf(String raw) {
  switch (raw.trim().toUpperCase()) {
    case 'B':
      return SizeClass.b;
    case 'M':
      return SizeClass.m;
    case 'S':
      return SizeClass.s;
    default:
      return SizeClass.unknown;
  }
}

/// Kolejność sortowania „wg wielkości”: B → M → S → brak.
int sizeRank(SizeClass c) => switch (c) {
      SizeClass.b => 0,
      SizeClass.m => 1,
      SizeClass.s => 2,
      SizeClass.unknown => 3,
    };

class Product {
  Product({
    required this.materialId,
    this.klasa = '',
    this.wymiary = '',
    this.waga = '',
    this.nazwa = '',
  });

  final String materialId;
  String klasa;
  String wymiary;
  String waga;
  String nazwa;

  SizeClass get sizeClass => sizeClassOf(klasa);

  bool get isEmpty =>
      klasa.isEmpty && wymiary.isEmpty && waga.isEmpty && nazwa.isEmpty;

  /// Uzupełnia puste pola danymi z [other] (lub nadpisuje, gdy [overwrite]).
  void mergeFrom(Product other, {bool overwrite = true}) {
    String pick(String mine, String theirs) {
      if (theirs.isEmpty) return mine;
      if (mine.isEmpty || overwrite) return theirs;
      return mine;
    }

    klasa = pick(klasa, other.klasa);
    wymiary = pick(wymiary, other.wymiary);
    waga = pick(waga, other.waga);
    nazwa = pick(nazwa, other.nazwa);
  }

  Map<String, dynamic> toJson() => {
        'materialId': materialId,
        'klasa': klasa,
        'wymiary': wymiary,
        'waga': waga,
        'nazwa': nazwa,
      };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        materialId: j['materialId'] as String,
        klasa: j['klasa'] as String? ?? '',
        wymiary: j['wymiary'] as String? ?? '',
        waga: j['waga'] as String? ?? '',
        nazwa: j['nazwa'] as String? ?? '',
      );
}

/// Grupa lokacji z tym samym Material ID (odpowiednik bloku z wierszem SUMA).
class MaterialGroup {
  MaterialGroup({
    required this.materialId,
    required this.lines,
    required this.product,
    required this.colorIndex,
  });

  final String materialId;
  final List<PickLine> lines;
  final Product? product;
  final int colorIndex;

  int get total => lines.fold(0, (s, l) => s + l.quantity);
  int get remaining =>
      lines.where((l) => !l.done).fold(0, (s, l) => s + l.quantity);
  int get doneLines => lines.where((l) => l.done).length;
  bool get allDone => lines.every((l) => l.done);
  bool get noneDone => lines.every((l) => !l.done);
  SizeClass get sizeClass => product?.sizeClass ?? SizeClass.unknown;
}

enum SortMode { bySum, bySize, byLocation }

class ImportResult {
  ImportResult({required this.lines, required this.products});
  final List<PickLine> lines;
  final List<Product> products;
}
