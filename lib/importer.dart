/// Import danych z CSV / TSV / TXT, XLSX (np. arkusz pick slipu) i JSON.
///
/// Rozpoznawane kolumny (nagłówki, bez względu na wielkość liter):
///   Location ID | Quantity | UOM | Material ID | Klasa | Wymiary | Waga |
///   Nazwa | Zrobione
/// Plik z lokacjami tworzy pick slip; plik bez kolumny lokacji (tylko
/// Material ID + dane) trafia wyłącznie do bazy produktów.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'models.dart';

class ImportException implements Exception {
  ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Importer {
  static ImportResult parse(String fileName, Uint8List bytes) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'xlsx':
        return _fromRows(_xlsxRows(bytes));
      case 'json':
        return _fromJson(_decodeText(bytes));
      default:
        return parseCsvText(_decodeText(bytes));
    }
  }

  static ImportResult parseCsvText(String text) {
    final firstLine = text
        .split(RegExp(r'\r?\n'))
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    return _fromRows(parseCsv(text, detectDelimiter(firstLine)));
  }

  // ---------------------------------------------------------------- tekst

  static String _decodeText(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    return text;
  }

  static String detectDelimiter(String headerLine) {
    final counts = {
      ';': ';'.allMatches(headerLine).length,
      '\t': '\t'.allMatches(headerLine).length,
      ',': ','.allMatches(headerLine).length,
    };
    var best = ';';
    var max = -1;
    counts.forEach((d, c) {
      if (c > max) {
        max = c;
        best = d;
      }
    });
    return best;
  }

  /// Prosty parser CSV z obsługą cudzysłowów.
  static List<List<String>> parseCsv(String text, String delimiter) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == delimiter) {
        endField();
      } else if (ch == '\n') {
        endRow();
      } else if (ch == '\r') {
        // pomijamy – \n zamknie wiersz
      } else {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }

  // ---------------------------------------------------------------- xlsx

  static List<List<String>> _xlsxRows(Uint8List bytes) {
    final Excel book;
    try {
      book = Excel.decodeBytes(bytes);
    } catch (e) {
      throw ImportException('Nie udało się odczytać pliku XLSX ($e).');
    }
    if (book.tables.isEmpty) throw ImportException('Plik XLSX jest pusty.');
    // Preferuj arkusz „Pick Slip”, w innym razie pierwszy.
    final name = book.tables.keys.firstWhere(
      (n) => n.toLowerCase().replaceAll(' ', '') == 'pickslip',
      orElse: () => book.tables.keys.first,
    );
    final sheet = book.tables[name]!;
    return [
      for (final r in sheet.rows)
        [for (final c in r) _cellText(c?.value)],
    ];
  }

  static String _cellText(CellValue? v) {
    if (v == null) return '';
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    if (v is BoolCellValue) return v.value ? 'true' : '';
    return v.toString();
  }

  // ---------------------------------------------------------------- json

  static ImportResult _fromJson(String text) {
    final dynamic data;
    try {
      data = jsonDecode(text);
    } catch (e) {
      throw ImportException('Niepoprawny JSON ($e).');
    }
    final lines = <Map<String, dynamic>>[];
    final products = <Map<String, dynamic>>[];
    if (data is List) {
      lines.addAll(data.whereType<Map<String, dynamic>>());
    } else if (data is Map<String, dynamic>) {
      for (final k in ['lines', 'pickSlip', 'pick_slip', 'items']) {
        if (data[k] is List) {
          lines.addAll((data[k] as List).whereType<Map<String, dynamic>>());
        }
      }
      for (final k in ['products', 'produkty']) {
        if (data[k] is List) {
          products.addAll((data[k] as List).whereType<Map<String, dynamic>>());
        }
      }
    }
    List<List<String>> toRows(List<Map<String, dynamic>> maps) {
      if (maps.isEmpty) return [];
      final keys = <String>{for (final m in maps) ...m.keys}.toList();
      return [
        keys,
        for (final m in maps) [for (final k in keys) '${m[k] ?? ''}'],
      ];
    }

    final a = _fromRows(toRows(lines), allowEmpty: true);
    final b = _fromRows(toRows(products), allowEmpty: true);
    final result = ImportResult(
      lines: a.lines,
      products: [...a.products, ...b.products],
    );
    if (result.lines.isEmpty && result.products.isEmpty) {
      throw ImportException('W pliku JSON nie znaleziono danych.');
    }
    return result;
  }

  // ---------------------------------------------------------- wspólne

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_\-.()]'), '')
      .replaceAll('ł', 'l')
      .replaceAll('ś', 's')
      .replaceAll('ą', 'a')
      .replaceAll('ę', 'e')
      .replaceAll('ó', 'o');

  static int? _col(List<String> header, List<String> keys) {
    for (var i = 0; i < header.length; i++) {
      final h = _norm(header[i]);
      if (h.isEmpty) continue;
      if (keys.any(h.contains)) return i;
    }
    return null;
  }

  static ImportResult _fromRows(List<List<String>> rows,
      {bool allowEmpty = false}) {
    // Szukamy wiersza nagłówka z kolumną Material ID (w pierwszych 30).
    var headerIdx = -1;
    for (var i = 0; i < rows.length && i < 30; i++) {
      if (_col(rows[i], ['material', 'sku']) != null) {
        headerIdx = i;
        break;
      }
    }
    if (headerIdx < 0) {
      if (allowEmpty) return ImportResult(lines: [], products: []);
      throw ImportException(
          'Nie znaleziono nagłówka z kolumną „Material ID”.');
    }
    final h = rows[headerIdx];
    final cMat = _col(h, ['material', 'sku'])!;
    final cLoc = _col(h, ['location', 'lokacja', 'lokalizacja']);
    final cQty = _col(h, ['quantity', 'qty', 'ilosc', 'sztuki']);
    final cUom = _col(h, ['uom', 'jm', 'jednostka']);
    final cKl = _col(h, ['klasa', 'class']);
    final cWym = _col(h, ['wymiary', 'dimension', 'dims']);
    final cWaga = _col(h, ['waga', 'weight']);
    final cNaz = _col(h, ['nazwa', 'name', 'opis', 'description']);
    final cDone = _col(h, ['zrobione', 'done']);

    String at(List<String> r, int? c) =>
        (c == null || c >= r.length) ? '' : r[c].trim();

    final lines = <PickLine>[];
    final products = <String, Product>{};
    var seq = 0;

    for (final r in rows.skip(headerIdx + 1)) {
      final mat = at(r, cMat);
      final loc = at(r, cLoc);
      final firstCell = r.isEmpty ? '' : r.first.trim().toUpperCase();
      if (firstCell.startsWith('SUMA') ||
          firstCell.startsWith('RAZEM') ||
          firstCell.startsWith('POSTĘP') ||
          firstCell.startsWith('POSTEP')) {
        // Wiersze podsumowań z arkusza – pomijamy, ale bierzemy dane produktu.
        if (mat.isNotEmpty) _addProduct(products, mat, r, at, cKl, cWym, cWaga, cNaz);
        if (firstCell.startsWith('RAZEM')) break;
        continue;
      }
      if (mat.isEmpty) continue;
      _addProduct(products, mat, r, at, cKl, cWym, cWaga, cNaz);

      if (cLoc != null && loc.isNotEmpty) {
        final qty = _parseInt(at(r, cQty));
        if (qty == null) continue;
        final doneRaw = at(r, cDone).toLowerCase();
        lines.add(PickLine(
          id: 'L${seq++}',
          location: loc,
          quantity: qty,
          uom: at(r, cUom).isEmpty ? 'CS' : at(r, cUom),
          materialId: mat,
          done: const ['true', '1', 'tak', 'x', '✓', 'yes', 'prawda']
              .contains(doneRaw),
        ));
      }
    }

    if (!allowEmpty && lines.isEmpty && products.isEmpty) {
      throw ImportException('Plik nie zawiera żadnych wierszy z danymi.');
    }
    return ImportResult(lines: lines, products: products.values.toList());
  }

  static void _addProduct(
    Map<String, Product> products,
    String mat,
    List<String> r,
    String Function(List<String>, int?) at,
    int? cKl,
    int? cWym,
    int? cWaga,
    int? cNaz,
  ) {
    final p = Product(
      materialId: mat,
      klasa: at(r, cKl).toUpperCase(),
      wymiary: at(r, cWym),
      waga: at(r, cWaga),
      nazwa: at(r, cNaz),
    );
    if (p.isEmpty) return;
    products.putIfAbsent(mat, () => Product(materialId: mat)).mergeFrom(p);
  }

  static int? _parseInt(String s) {
    final cleaned = s.replaceAll(' ', '').replaceAll(',', '.');
    final d = double.tryParse(cleaned);
    return d?.round();
  }
}

/// Eksport CSV (średnik + przecinek dziesiętny – dobrze otwiera się w Excelu PL).
String toCsv(List<List<String>> rows) {
  String esc(String v) => (v.contains(';') || v.contains('"') || v.contains('\n'))
      ? '"${v.replaceAll('"', '""')}"'
      : v;
  return rows.map((r) => r.map(esc).join(';')).join('\r\n');
}
