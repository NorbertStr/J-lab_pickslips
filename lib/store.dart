/// Stan aplikacji: bieżący pick slip, baza produktów, postęp. Zapis lokalny.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'importer.dart';
import 'models.dart';

class Progress {
  const Progress(this.done, this.total);
  final int done;
  final int total;
  int get left => total - done;
  double get ratio => total == 0 ? 0 : done / total;
}

class AppStore extends ChangeNotifier {
  static const _kState = 'pick_slip_state_v1';
  static const _kProducts = 'products_db_v1';

  String title = '';
  List<PickLine> lines = [];
  final Map<String, Product> products = {};
  SortMode sort = SortMode.bySum;
  bool hideDone = false;
  String query = '';

  SharedPreferences? _prefs;

  // ------------------------------------------------------------ trwałość

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final s = _prefs!.getString(_kState);
    if (s != null) {
      try {
        final j = jsonDecode(s) as Map<String, dynamic>;
        title = j['title'] as String? ?? '';
        sort = SortMode.values[(j['sort'] as int?) ?? 0];
        hideDone = j['hideDone'] as bool? ?? false;
        lines = [
          for (final l in (j['lines'] as List? ?? []))
            PickLine.fromJson(l as Map<String, dynamic>),
        ];
      } catch (_) {/* uszkodzony zapis – start od zera */}
    }
    final p = _prefs!.getString(_kProducts);
    if (p != null) {
      try {
        for (final e in (jsonDecode(p) as List)) {
          final prod = Product.fromJson(e as Map<String, dynamic>);
          products[prod.materialId] = prod;
        }
      } catch (_) {}
    }
  }

  void _save() {
    _prefs?.setString(
      _kState,
      jsonEncode({
        'title': title,
        'sort': sort.index,
        'hideDone': hideDone,
        'lines': [for (final l in lines) l.toJson()],
      }),
    );
    _prefs?.setString(
      _kProducts,
      jsonEncode([for (final p in products.values) p.toJson()]),
    );
  }

  void _changed() {
    _save();
    notifyListeners();
  }

  // ------------------------------------------------------------ import

  /// Zwraca (liczba lokacji, liczba produktów).
  (int, int) applyImport(ImportResult r, {required String fileName}) {
    for (final p in r.products) {
      products.putIfAbsent(p.materialId, () => Product(materialId: p.materialId))
          .mergeFrom(p);
    }
    if (r.lines.isNotEmpty) {
      lines = r.lines;
      final m = RegExp(r'(\d{5,})').firstMatch(fileName);
      title = m?.group(1) ?? fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    }
    _changed();
    return (r.lines.length, r.products.length);
  }

  void clearPickSlip() {
    lines = [];
    title = '';
    _changed();
  }

  // ------------------------------------------------------------ edycja

  void toggleLine(PickLine l, bool value) {
    l.done = value;
    _changed();
  }

  void setGroupDone(MaterialGroup g, bool value) {
    for (final l in g.lines) {
      l.done = value;
    }
    _changed();
  }

  void resetDone() {
    for (final l in lines) {
      l.done = false;
    }
    _changed();
  }

  void upsertProduct(Product p) {
    products[p.materialId] = p;
    _changed();
  }

  void deleteProduct(String materialId) {
    products.remove(materialId);
    _changed();
  }

  void setSort(SortMode m) {
    sort = m;
    _changed();
  }

  void setHideDone(bool v) {
    hideDone = v;
    _changed();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  // ------------------------------------------------------------ widoki

  /// Grupy wg Material ID – kolor przypisany wg kolejności z pliku.
  List<MaterialGroup> get allGroups {
    final order = <String>[];
    final byMat = <String, List<PickLine>>{};
    for (final l in lines) {
      byMat.putIfAbsent(l.materialId, () {
        order.add(l.materialId);
        return [];
      }).add(l);
    }
    return [
      for (var i = 0; i < order.length; i++)
        MaterialGroup(
          materialId: order[i],
          lines: byMat[order[i]]!,
          product: products[order[i]],
          colorIndex: i,
        ),
    ];
  }

  List<MaterialGroup> get visibleGroups {
    final q = query.trim().toUpperCase();
    var groups = allGroups.where((g) {
      if (hideDone && g.allDone) return false;
      if (q.isEmpty) return true;
      return g.materialId.toUpperCase().contains(q) ||
          (g.product?.nazwa.toUpperCase().contains(q) ?? false) ||
          g.lines.any((l) => l.location.toUpperCase().contains(q));
    }).toList();

    int bySum(MaterialGroup a, MaterialGroup b) => b.total.compareTo(a.total);
    switch (sort) {
      case SortMode.bySum:
        groups.sort(bySum);
      case SortMode.bySize:
        groups.sort((a, b) {
          final c = sizeRank(a.sizeClass).compareTo(sizeRank(b.sizeClass));
          return c != 0 ? c : bySum(a, b);
        });
      case SortMode.byLocation:
        for (final g in groups) {
          g.lines.sort((a, b) => a.location.compareTo(b.location));
        }
        groups.sort((a, b) => a.lines.first.location.compareTo(b.lines.first.location));
    }
    // Zakończone grupy na koniec listy.
    final open = groups.where((g) => !g.allDone).toList();
    final closed = groups.where((g) => g.allDone).toList();
    return [...open, ...closed];
  }

  Progress get locationsProgress =>
      Progress(lines.where((l) => l.done).length, lines.length);

  Progress get quantityProgress => Progress(
        lines.where((l) => l.done).fold(0, (s, l) => s + l.quantity),
        lines.fold(0, (s, l) => s + l.quantity),
      );

  Progress get materialsProgress {
    final g = allGroups;
    return Progress(g.where((x) => x.allDone).length, g.length);
  }

  int get missingProductData =>
      allGroups.where((g) => g.product == null || g.product!.isEmpty).length;

  // ------------------------------------------------------------ eksport

  String exportPickSlipCsv() {
    final rows = <List<String>>[
      ['Location ID', 'Quantity', 'UOM', 'Zrobione', 'Klasa', 'Wymiary', 'Waga', 'Material ID'],
    ];
    for (final g in visibleGroups) {
      final p = g.product;
      for (final l in g.lines) {
        rows.add([
          l.location, '${l.quantity}', l.uom, l.done ? 'TAK' : '',
          p?.klasa ?? '', p?.wymiary ?? '', p?.waga ?? '', l.materialId,
        ]);
      }
      rows.add(['SUMA', '${g.total}', '', g.allDone ? 'TAK' : '',
        p?.klasa ?? '', p?.wymiary ?? '', p?.waga ?? '', g.materialId]);
    }
    rows.add(['RAZEM (Total PickSlip Quantity)', '${quantityProgress.total}']);
    return toCsv(rows);
  }

  String exportProductsCsv() {
    final list = products.values.toList()
      ..sort((a, b) => a.materialId.compareTo(b.materialId));
    return toCsv([
      ['Material ID', 'Klasa', 'Wymiary', 'Waga', 'Nazwa'],
      for (final p in list) [p.materialId, p.klasa, p.wymiary, p.waga, p.nazwa],
    ]);
  }
}
