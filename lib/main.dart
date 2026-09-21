import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';

import 'database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BudgetApp());
}

class BudgetApp extends StatelessWidget {
  const BudgetApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Obra Clara',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E8A72)),
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
        cardTheme: const CardThemeData(color: Colors.white, elevation: 0),
        useMaterial3: true,
      ),
      home: const BudgetHome(),
    );
  }
}

enum Unit { squareMeter, linearMeter, unit }

extension UnitText on Unit {
  String get label => ['m²', 'm lineal', 'unidad'][index];
}

class BudgetItem {
  BudgetItem({
    this.id,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.material,
    required this.labor,
  });
  final int? id;
  final String name;
  final Unit unit;
  final double quantity;
  final double material;
  final double labor;
  double get total => quantity * (material + labor);
}

class BudgetTemplate {
  BudgetTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.items,
  });
  final int id;
  final String name;
  final String description;
  final List<BudgetItem> items;
  double get total => items.fold(0, (sum, item) => sum + item.total);
  double get materials =>
      items.fold(0, (sum, item) => sum + item.quantity * item.material);
  double get labor =>
      items.fold(0, (sum, item) => sum + item.quantity * item.labor);
}

class BudgetHome extends StatefulWidget {
  const BudgetHome({super.key});
  @override
  State<BudgetHome> createState() => _BudgetHomeState();
}

class _BudgetHomeState extends State<BudgetHome> {
  BudgetDatabase? database;
  Object? loadError;
  int selected = 0;
  var templates = <BudgetTemplate>[];

  @override
  void initState() {
    super.initState();
    _loadDatabase();
  }

  Future<void> _loadDatabase() async {
    try {
      final db = await BudgetDatabase.open();
      final rows = await db.templates();
      final loaded = <BudgetTemplate>[];
      for (final row in rows) {
        final itemRows = await db.itemsFor(row['id'] as int);
        loaded.add(
          BudgetTemplate(
            id: row['id'] as int,
            name: row['name'] as String,
            description: row['description'] as String,
            items: itemRows.map(_itemFromRow).toList(),
          ),
        );
      }
      if (!mounted) {
        await db.close();
        return;
      }
      setState(() {
        database = db;
        templates = loaded;
        selected =
            loaded.isEmpty ? 0 : selected.clamp(0, loaded.length - 1).toInt();
      });
    } catch (error) {
      if (mounted) setState(() => loadError = error);
    }
  }

  @override
  void dispose() {
    database?.close();
    super.dispose();
  }

  BudgetItem _itemFromRow(Map<String, Object?> row) => BudgetItem(
    id: row['id'] as int,
    name: row['name'] as String,
    unit: Unit.values.firstWhere((unit) => unit.name == row['unit']),
    quantity: (row['quantity'] as num).toDouble(),
    material: (row['material'] as num).toDouble(),
    labor: (row['labor'] as num).toDouble(),
  );

  Future<void> _newTemplate() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const TemplateDialog(),
    );
    if (result == null || database == null) return;
    final id = await database!.insertTemplate(
      name: result['name']!,
      description: result['description']!,
      items: const [],
    );
    setState(
      () => templates.add(
        BudgetTemplate(
          id: id,
          name: result['name']!,
          description: result['description']!,
          items: [],
        ),
      ),
    );
    setState(() => selected = templates.length - 1);
  }

  Future<void> _newItem() async {
    if (database == null || templates.isEmpty) return;
    final item = await showDialog<BudgetItem>(
      context: context,
      builder: (_) => const ItemDialog(),
    );
    if (item == null) return;
    final id = await database!.insertItem(
      templateId: current.id,
      name: item.name,
      unit: item.unit.name,
      quantity: item.quantity,
      material: item.material,
      labor: item.labor,
    );
    setState(
      () => current.items.add(
        BudgetItem(
          id: id,
          name: item.name,
          unit: item.unit,
          quantity: item.quantity,
          material: item.material,
          labor: item.labor,
        ),
      ),
    );
  }

  Future<void> _exportCurrent() async {
    final workbook = Excel.createExcel();
    final sheetName = _excelSheetName(current.name);
    workbook.rename('Sheet1', sheetName);
    final sheet = workbook[sheetName];
    sheet.appendRow([TextCellValue('PRESUPUESTO DE OBRA')]);
    sheet.appendRow([TextCellValue(current.name)]);
    sheet.appendRow([TextCellValue(current.description)]);
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('Partida'),
      TextCellValue('Unidad'),
      TextCellValue('Cantidad'),
      TextCellValue('Material / unidad'),
      TextCellValue('Mano de obra / unidad'),
      TextCellValue('Total'),
    ]);
    for (final item in current.items) {
      sheet.appendRow([
        TextCellValue(item.name),
        TextCellValue(item.unit.label),
        DoubleCellValue(item.quantity),
        DoubleCellValue(item.material),
        DoubleCellValue(item.labor),
        DoubleCellValue(item.total),
      ]);
    }
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('Materiales'),
      DoubleCellValue(current.materials),
    ]);
    sheet.appendRow([
      TextCellValue('Mano de obra'),
      DoubleCellValue(current.labor),
    ]);
    sheet.appendRow([
      TextCellValue('TOTAL ESTIMADO'),
      DoubleCellValue(current.total),
    ]);

    final home = Platform.environment['HOME'] ?? Directory.current.path;
    final downloads =
        Directory('$home/Descargas').existsSync()
            ? Directory('$home/Descargas')
            : Directory('$home/Downloads');
    if (!downloads.existsSync()) await downloads.create(recursive: true);
    final file = File('${downloads.path}/${_safeFileName(current.name)}.xlsx');
    final bytes = workbook.save();
    if (bytes == null) throw StateError('No se pudo crear el archivo Excel');
    await file.writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Excel exportado en ${file.path}')));
  }

  String _safeFileName(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  String _excelSheetName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/*?:\[\]]'), '').trim();
    return cleaned.isEmpty
        ? 'Presupuesto'
        : cleaned.length > 31
        ? cleaned.substring(0, 31)
        : cleaned;
  }

  BudgetTemplate get current => templates[selected];
  String money(double value) => '\$${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 920;
    if (loadError != null) {
      return Scaffold(
        body: Center(
          child: Text('No se pudo abrir la base de datos: $loadError'),
        ),
      );
    }
    if (database == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: !compact,
            backgroundColor: const Color(0xFF172B4D),
            selectedIndex: 0,
            selectedIconTheme: const IconThemeData(color: Color(0xFF172B4D)),
            unselectedIconTheme: const IconThemeData(color: Color(0xFFB7C4D2)),
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(0, 24, 0, 30),
              child:
                  compact
                      ? const Icon(
                        Icons.home_work_rounded,
                        color: Color(0xFF67D1AE),
                      )
                      : const Text(
                        'OBRA CLARA',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: Text('Resumen'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description_rounded),
                label: Text('Presupuestos'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2_rounded),
                label: Text('Catalogo'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: Text('Configuracion'),
              ),
            ],
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                const SliverAppBar(
                  pinned: true,
                  automaticallyImplyLeading: false,
                  toolbarHeight: 76,
                  title: Text(
                    'Presupuesto de obra',
                    style: TextStyle(
                      color: Color(0xFF172B4D),
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  backgroundColor: Colors.white,
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 20 : 42,
                    28,
                    compact ? 20 : 42,
                    40,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hola, Juan',
                                  style: TextStyle(
                                    color: Color(0xFF6B7A78),
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Tus plantillas de obra',
                                  style: TextStyle(
                                    color: Color(0xFF172B4D),
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _newTemplate,
                            icon: const Icon(Icons.add),
                            label: const Text('Nueva plantilla'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          MetricCard(
                            'Plantillas activas',
                            '${templates.length}',
                            Icons.dashboard_customize_outlined,
                          ),
                          MetricCard(
                            'Partidas creadas',
                            '${templates.fold<int>(0, (sum, item) => sum + item.items.length)}',
                            Icons.view_list_rounded,
                          ),
                          MetricCard(
                            'Valor de referencia',
                            money(
                              templates.fold(
                                0.0,
                                (sum, item) => sum + item.total,
                              ),
                            ),
                            Icons.analytics_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Mis plantillas',
                        style: TextStyle(
                          color: Color(0xFF172B4D),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (compact) ...[
                        templateList(),
                        const SizedBox(height: 18),
                        detailCard(),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 300, child: templateList()),
                            const SizedBox(width: 22),
                            Expanded(child: detailCard()),
                          ],
                        ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget templateList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            for (var i = 0; i < templates.length; i++)
              ListTile(
                selected: selected == i,
                selectedTileColor: const Color(0xFFE7F3EF),
                leading: const Icon(Icons.roofing_rounded),
                title: Text(
                  templates[i].name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  '${templates[i].items.length} partidas',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => setState(() => selected = i),
              ),
            TextButton.icon(
              onPressed: _newTemplate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Crear desde cero'),
            ),
          ],
        ),
      ),
    );
  }

  Widget detailCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current.name,
              style: const TextStyle(
                color: Color(0xFF172B4D),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              current.description,
              style: const TextStyle(color: Color(0xFF6B7A78), fontSize: 13),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Text(
                  'Partidas de costo',
                  style: TextStyle(
                    color: Color(0xFF172B4D),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _exportCurrent,
                  icon: const Icon(Icons.file_download_outlined, size: 17),
                  label: const Text('Exportar Excel'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _newItem,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('Agregar partida'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF5F7F6),
                ),
                columns: const [
                  DataColumn(label: Text('PARTIDA')),
                  DataColumn(label: Text('UNIDAD')),
                  DataColumn(label: Text('CANTIDAD')),
                  DataColumn(label: Text('MATERIAL / U.')),
                  DataColumn(label: Text('MANO DE OBRA / U.')),
                  DataColumn(label: Text('TOTAL')),
                ],
                rows: [
                  for (final item in current.items)
                    DataRow(
                      cells: [
                        DataCell(Text(item.name)),
                        DataCell(Text(item.unit.label)),
                        DataCell(Text('${item.quantity}')),
                        DataCell(Text(money(item.material))),
                        DataCell(Text(money(item.labor))),
                        DataCell(
                          Text(
                            money(item.total),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF176651),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const Divider(height: 30),
            Wrap(
              spacing: 30,
              runSpacing: 12,
              children: [
                TotalLine('Materiales', money(current.materials)),
                TotalLine('Mano de obra', money(current.labor)),
                TotalLine('Total estimado', money(current.total), strong: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard(this.label, this.value, this.icon, {super.key});
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 226,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF176651), size: 30),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF6B7A78),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF172B4D),
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class TotalLine extends StatelessWidget {
  const TotalLine(this.label, this.value, {this.strong = false, super.key});
  final String label;
  final String value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFF6B7A78), fontSize: 13),
      ),
      const SizedBox(width: 10),
      Text(
        value,
        style: TextStyle(
          color: strong ? const Color(0xFF176651) : const Color(0xFF172B4D),
          fontSize: strong ? 19 : 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class TemplateDialog extends StatefulWidget {
  const TemplateDialog({super.key});

  @override
  State<TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<TemplateDialog> {
  final name = TextEditingController();
  final description = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nueva plantilla'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              hintText: 'Ej. Instalacion electrica',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: description,
            decoration: const InputDecoration(labelText: 'Descripcion'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (name.text.trim().isEmpty) return;
          Navigator.pop(context, {
            'name': name.text.trim(),
            'description': description.text.trim(),
          });
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}

class ItemDialog extends StatefulWidget {
  const ItemDialog({super.key});

  @override
  State<ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<ItemDialog> {
  final name = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final material = TextEditingController(text: '0');
  final labor = TextEditingController(text: '0');
  Unit unit = Unit.squareMeter;

  double number(TextEditingController controller) =>
      double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;

  @override
  void dispose() {
    name.dispose();
    quantity.dispose();
    material.dispose();
    labor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nueva partida'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre de la partida',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<Unit>(
                    value: unit,
                    decoration: const InputDecoration(labelText: 'Unidad'),
                    items:
                        Unit.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.label),
                              ),
                            )
                            .toList(),
                    onChanged: (value) => setState(() => unit = value!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: material,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Material / unidad',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: labor,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Mano de obra / unidad',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (name.text.trim().isEmpty) return;
          Navigator.pop(
            context,
            BudgetItem(
              name: name.text.trim(),
              unit: unit,
              quantity: number(quantity),
              material: number(material),
              labor: number(labor),
            ),
          );
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}
