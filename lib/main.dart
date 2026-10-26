import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'download.dart';
import 'importer.dart';
import 'models.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.load();
  runApp(PickSlipApp(store: store));
}

// ---------------------------------------------------------------- motyw

const _navy = Color(0xFF1F3A5F);

/// Pastelowe kolory grup – jak kolorowanie bloków w arkuszu.
const _groupColors = [
  Color(0xFFDCEBFA), // niebieski
  Color(0xFFFCE5CD), // brzoskwiniowy
  Color(0xFFD9EAD3), // zielony
  Color(0xFFEADCF5), // fioletowy
  Color(0xFFFFF2CC), // żółty
  Color(0xFFD0ECEC), // morski
  Color(0xFFF8D7DA), // różowy
  Color(0xFFE6E6E6), // szary
];
const _groupColorsDark = [
  Color(0xFF203247),
  Color(0xFF3F2E1E),
  Color(0xFF223622),
  Color(0xFF34284A),
  Color(0xFF3D3618),
  Color(0xFF1C3838),
  Color(0xFF452428),
  Color(0xFF333333),
];

Color groupColor(BuildContext c, int i) =>
    Theme.of(c).brightness == Brightness.dark
        ? _groupColorsDark[i % _groupColorsDark.length]
        : _groupColors[i % _groupColors.length];

({Color bg, Color fg}) classColors(SizeClass c) => switch (c) {
      SizeClass.b => (bg: const Color(0xFF9A3412), fg: Colors.white),
      SizeClass.m => (bg: const Color(0xFFB45309), fg: Colors.white),
      SizeClass.s => (bg: const Color(0xFF166534), fg: Colors.white),
      SizeClass.unknown => (bg: const Color(0xFF6B7280), fg: Colors.white),
    };

class PickSlipApp extends StatelessWidget {
  const PickSlipApp({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: _navy, brightness: b),
          visualDensity: VisualDensity.standard,
        );
    return MaterialApp(
      title: 'Pick Slip',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomeShell(store: store),
    );
  }
}

// ---------------------------------------------------------------- powłoka

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});
  final AppStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_tab == 0
              ? (store.title.isEmpty ? 'Pick slip' : 'Pick slip ${store.title}')
              : 'Baza produktów'),
          actions: [
            IconButton(
              tooltip: 'Importuj plik (CSV, XLSX, JSON)',
              icon: const Icon(Icons.upload_file),
              onPressed: () => importFile(context, store),
            ),
            _MoreMenu(store: store, tab: _tab),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            PickSlipPage(store: store),
            ProductsPage(store: store),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.checklist_outlined),
              selectedIcon: Icon(Icons.checklist),
              label: 'Kompletacja',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: store.lines.isNotEmpty && store.missingProductData > 0,
                label: Text('${store.missingProductData}'),
                child: const Icon(Icons.inventory_2_outlined),
              ),
              selectedIcon: const Icon(Icons.inventory_2),
              label: 'Produkty',
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.store, required this.tab});
  final AppStore store;
  final int tab;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Więcej',
      onSelected: (v) async {
        switch (v) {
          case 'sample':
            await loadSample(context, store);
          case 'export_slip':
            if (context.mounted) {
              await exportText(context,
                  'pick_slip_${store.title.isEmpty ? 'postep' : store.title}.csv',
                  store.exportPickSlipCsv());
            }
          case 'export_products':
            await exportText(context, 'baza_produktow.csv', store.exportProductsCsv());
          case 'reset':
            if (await confirm(context, 'Wyczyścić wszystkie zaznaczenia „Zrobione”?')) {
              store.resetDone();
            }
          case 'clear':
            if (await confirm(context,
                'Usunąć bieżący pick slip? Baza produktów zostanie zachowana.')) {
              store.clearPickSlip();
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'sample', child: ListTile(
            leading: Icon(Icons.science_outlined), title: Text('Załaduj przykład'))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'export_slip', enabled: store.lines.isNotEmpty,
            child: const ListTile(leading: Icon(Icons.download),
                title: Text('Eksportuj postęp (CSV)'))),
        PopupMenuItem(value: 'export_products', enabled: store.products.isNotEmpty,
            child: const ListTile(leading: Icon(Icons.download_outlined),
                title: Text('Eksportuj bazę produktów (CSV)'))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'reset', enabled: store.lines.isNotEmpty,
            child: const ListTile(leading: Icon(Icons.restart_alt),
                title: Text('Wyczyść zaznaczenia'))),
        PopupMenuItem(value: 'clear', enabled: store.lines.isNotEmpty,
            child: const ListTile(leading: Icon(Icons.delete_outline),
                title: Text('Zamknij pick slip'))),
      ],
    );
  }
}

// ---------------------------------------------------------------- akcje

Future<void> importFile(BuildContext context, AppStore store) async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv', 'txt', 'tsv', 'xlsx', 'json'],
    withData: true,
  );
  if (res == null || res.files.isEmpty) return;
  final f = res.files.first;
  final bytes = f.bytes;
  if (bytes == null) {
    if (context.mounted) snack(context, 'Nie udało się odczytać pliku.');
    return;
  }
  try {
    final r = Importer.parse(f.name, bytes);
    if (!context.mounted) return;
    if (r.lines.isNotEmpty && store.lines.isNotEmpty) {
      final ok = await confirm(context,
          'Plik zawiera nowy pick slip (${r.lines.length} lokacji). '
          'Zastąpić bieżący? Postęp obecnego zostanie utracony.');
      if (!ok) return;
    }
    final (nLines, nProducts) = store.applyImport(r, fileName: f.name);
    if (context.mounted) {
      snack(context, [
        if (nLines > 0) 'Pick slip: $nLines lokacji',
        if (nProducts > 0) 'produkty: $nProducts',
      ].join(' · '));
    }
  } on ImportException catch (e) {
    if (context.mounted) snack(context, e.message);
  }
}

Future<void> loadSample(BuildContext context, AppStore store) async {
  final products = await rootBundle.loadString('assets/sample_products.csv');
  final slip = await rootBundle.loadString('assets/sample_pick_slip.csv');
  store.applyImport(Importer.parseCsvText(products), fileName: 'produkty.csv');
  store.applyImport(Importer.parseCsvText(slip), fileName: 'pick_slip_6037474.csv');
  if (context.mounted) snack(context, 'Załadowano przykładowy pick slip.');
}

Future<void> exportText(BuildContext context, String name, String content) async {
  if (downloadText(name, content)) return;
  await Clipboard.setData(ClipboardData(text: content));
  if (context.mounted) snack(context, 'Skopiowano CSV do schowka.');
}

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) snack(context, 'Skopiowano: $text');
}

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirm(BuildContext context, String msg) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tak')),
      ],
    ),
  );
  return r ?? false;
}

// ---------------------------------------------------------------- kompletacja

class PickSlipPage extends StatelessWidget {
  const PickSlipPage({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    if (store.lines.isEmpty) return _EmptyState(store: store);
    final groups = store.visibleGroups;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              sliver: SliverList.list(children: [
                _StatsCard(store: store),
                const SizedBox(height: 12),
                _Controls(store: store),
                const SizedBox(height: 8),
              ]),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverList.separated(
                itemCount: groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (c, i) => GroupCard(store: store, group: groups[i]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
              sliver: SliverToBoxAdapter(
                child: groups.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Brak pozycji do pokazania.',
                            textAlign: TextAlign.center),
                      )
                    : Text(
                        'RAZEM: ${store.quantityProgress.total} szt. '
                        'w ${store.locationsProgress.total} lokacjach',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assignment_outlined, size: 64,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('Brak pick slipu', style: t.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Zaimportuj plik CSV, XLSX lub JSON z kolumnami '
                'Location ID, Quantity, UOM, Material ID. '
                'Dane produktów (Klasa, Wymiary, Waga) mogą być w tym samym '
                'pliku albo w osobnej bazie produktów.',
                textAlign: TextAlign.center,
                style: t.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => importFile(context, store),
                icon: const Icon(Icons.upload_file),
                label: const Text('Importuj plik'),
                style: FilledButton.styleFrom(minimumSize: const Size(220, 48)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => loadSample(context, store),
                child: const Text('Załaduj przykład (6037474)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Lokacje', store.locationsProgress),
      ('Sztuki', store.quantityProgress),
      ('Materiały', store.materialsProgress),
    ];
    final t = Theme.of(context).textTheme;
    final allDone = store.locationsProgress.left == 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Postęp', style: t.titleMedium),
              const Spacer(),
              if (allDone)
                Chip(
                  avatar: const Icon(Icons.check_circle, size: 18),
                  label: const Text('Gotowe'),
                  visualDensity: VisualDensity.compact,
                ),
            ]),
            const SizedBox(height: 8),
            for (final (label, p) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 84, child: Text(label, style: t.bodyMedium)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: p.ratio, minHeight: 10),
                    ),
                  ),
                  SizedBox(
                    width: 112,
                    child: Text(
                      'zostało ${p.left}/${p.total}',
                      textAlign: TextAlign.right,
                      style: t.bodyMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<SortMode>(
          segments: const [
            ButtonSegment(value: SortMode.bySum, label: Text('Wg sumy'),
                icon: Icon(Icons.functions)),
            ButtonSegment(value: SortMode.bySize, label: Text('Wg wielkości'),
                icon: Icon(Icons.straighten)),
            ButtonSegment(value: SortMode.byLocation, label: Text('Wg lokacji'),
                icon: Icon(Icons.place_outlined)),
          ],
          selected: {store.sort},
          showSelectedIcon: false,
          onSelectionChanged: (s) => store.setSort(s.first),
        ),
        FilterChip(
          label: const Text('Ukryj zrobione'),
          selected: store.hideDone,
          onSelected: store.setHideDone,
        ),
        SizedBox(
          width: 260,
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Szukaj lokacji lub materiału',
              border: OutlineInputBorder(),
            ),
            onChanged: store.setQuery,
          ),
        ),
      ],
    );
  }
}

class ClassBadge extends StatelessWidget {
  const ClassBadge(this.klasa, {super.key});
  final String klasa;

  @override
  Widget build(BuildContext context) {
    final c = classColors(sizeClassOf(klasa));
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(6)),
      child: Text(klasa.isEmpty ? '?' : klasa,
          style: TextStyle(color: c.fg, fontWeight: FontWeight.w700, fontSize: 15)),
    );
  }
}

class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.store, required this.group});
  final AppStore store;
  final MaterialGroup group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final p = g.product;
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final details = [
      if (p != null && p.wymiary.isNotEmpty) p.wymiary,
      if (p != null && p.waga.isNotEmpty) p.waga,
    ];
    return Opacity(
      opacity: g.allDone ? 0.6 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            Material(
              color: groupColor(context, g.colorIndex),
              child: InkWell(
                onTap: () => showProduct(context, store, g.materialId),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
                  child: Row(children: [
                    Checkbox(
                      tristate: true,
                      value: g.allDone ? true : (g.noneDone ? false : null),
                      onChanged: (_) => store.setGroupDone(g, !g.allDone),
                    ),
                    ClassBadge(p?.klasa ?? ''),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.materialId,
                              style: t.titleSmall?.copyWith(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700)),
                          if (p != null && p.nazwa.isNotEmpty)
                            Text(p.nazwa, style: t.bodySmall),
                          Text(
                            details.isEmpty
                                ? 'Brak wymiarów w bazie'
                                : details.join(' · '),
                            style: t.bodySmall?.copyWith(color: muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kopiuj Material ID',
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () => copyText(context, g.materialId),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${g.total}',
                            style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text(g.allDone ? 'zrobione' : 'zostało ${g.remaining}',
                            style: t.labelSmall?.copyWith(color: muted)),
                      ],
                    ),
                  ]),
                ),
              ),
            ),
            for (final l in g.lines) _LineTile(store: store, line: l),
          ],
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.store, required this.line});
  final AppStore store;
  final PickLine line;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final deco = line.done ? TextDecoration.lineThrough : null;
    return InkWell(
      onTap: () => store.toggleLine(line, !line.done),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(children: [
          Checkbox(
            value: line.done,
            onChanged: (v) => store.toggleLine(line, v ?? false),
          ),
          Expanded(
            child: Text(line.location,
                style: t.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    decoration: deco)),
          ),
          Text('${line.quantity} ${line.uom}',
              style: t.titleMedium?.copyWith(decoration: deco)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- produkty

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key, required this.store});
  final AppStore store;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final inSlip = {for (final l in store.lines) l.materialId};
    // Materiały z pick slipu bez danych – na górze.
    final missing = inSlip
        .where((m) => store.products[m] == null || store.products[m]!.isEmpty)
        .toList()
      ..sort();
    final list = store.products.values
        .where((p) => _q.isEmpty ||
            p.materialId.toUpperCase().contains(_q.toUpperCase()) ||
            p.nazwa.toUpperCase().contains(_q.toUpperCase()))
        .toList()
      ..sort((a, b) => a.materialId.compareTo(b.materialId));

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Szukaj Material ID',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 12),
              if (missing.isNotEmpty) ...[
                Text('Brak danych dla materiałów z pick slipu',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final m in missing)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber),
                      title: Text(m, style: const TextStyle(fontFamily: 'monospace')),
                      subtitle: const Text('Brak w bazie – zaimportuj dane produktu'),
                      trailing: IconButton(
                        tooltip: 'Kopiuj Material ID',
                        icon: const Icon(Icons.copy),
                        onPressed: () => copyText(context, m),
                      ),
                      onTap: () => showProduct(context, store, m),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              Text('Baza produktów (${store.products.length})',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Baza jest pusta. Zaimportuj CSV z kolumnami '
                    'Material ID; Klasa; Wymiary; Waga (opcjonalnie Nazwa).',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final p in list)
                Card(
                  child: ListTile(
                    leading: ClassBadge(p.klasa),
                    title: Text(p.materialId,
                        style: const TextStyle(fontFamily: 'monospace')),
                    subtitle: Text([
                      if (p.nazwa.isNotEmpty) p.nazwa,
                      if (p.wymiary.isNotEmpty) p.wymiary,
                      if (p.waga.isNotEmpty) p.waga,
                    ].join(' · ')),
                    trailing: inSlip.contains(p.materialId)
                        ? const Tooltip(message: 'W bieżącym pick slipie',
                            child: Icon(Icons.assignment_turned_in_outlined))
                        : null,
                    onTap: () => showProduct(context, store, p.materialId),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Podgląd danych produktu – tylko do odczytu (bez edycji i usuwania).
Future<void> showProduct(BuildContext context, AppStore store, String materialId) async {
  final p = store.products[materialId];
  final t = Theme.of(context).textTheme;
  final muted = Theme.of(context).colorScheme.onSurfaceVariant;

  Widget row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 80, child: Text(label, style: t.bodyMedium?.copyWith(color: muted))),
            Expanded(child: SelectableText(value.isEmpty ? '—' : value, style: t.bodyLarge)),
          ],
        ),
      );

  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Dane produktu'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Material ID', style: t.bodyMedium?.copyWith(color: muted)),
            Row(children: [
              Expanded(
                child: SelectableText(materialId,
                    style: t.titleMedium?.copyWith(
                        fontFamily: 'monospace', fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Kopiuj Material ID',
                icon: const Icon(Icons.copy),
                onPressed: () => copyText(c, materialId),
              ),
            ]),
            const Divider(),
            Row(children: [
              SizedBox(width: 80, child: Text('Klasa', style: t.bodyMedium?.copyWith(color: muted))),
              ClassBadge(p?.klasa ?? ''),
            ]),
            if (p != null && p.nazwa.isNotEmpty) row('Nazwa', p.nazwa),
            row('Wymiary', p?.wymiary ?? ''),
            row('Waga', p?.waga ?? ''),
            if (p == null || p.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Brak danych w bazie – zaimportuj plik produktów.',
                    style: t.bodySmall?.copyWith(color: muted)),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            Navigator.pop(c);
            copyText(context, materialId);
          },
          child: const Text('Kopiuj i zamknij'),
        ),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Zamknij')),
      ],
    ),
  );
}
