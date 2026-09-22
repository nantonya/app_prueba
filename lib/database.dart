import 'package:postgres/postgres.dart';

class BudgetDatabase {
  BudgetDatabase._(this._connection);

  final Connection _connection;

  static Future<BudgetDatabase> open() async {
    final connection = await Connection.open(
      Endpoint(
        host: '127.0.0.1',
        port: 5432,
        database: 'mydb',
        username: 'postgres',
        password: 'pass_postgres',
      ),
      settings: const ConnectionSettings(
        sslMode: SslMode.disable,
        connectTimeout: Duration(seconds: 5),
      ),
    );
    final database = BudgetDatabase._(connection);
    await database._createSchema();
    await database.seedMaterials();
    await database.seedDefaults();
    return database;
  }

  Future<void> _createSchema() async {
    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS materials (
        id SERIAL PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        unit TEXT NOT NULL,
        price DOUBLE PRECISION NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');
    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS templates (
        id SERIAL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');
    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS items (
        id SERIAL PRIMARY KEY,
        template_id INTEGER NOT NULL REFERENCES templates(id) ON DELETE CASCADE,
        material_id INTEGER REFERENCES materials(id) ON DELETE SET NULL,
        material_name TEXT,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        quantity DOUBLE PRECISION NOT NULL,
        material DOUBLE PRECISION NOT NULL,
        labor DOUBLE PRECISION NOT NULL
      )
    ''');
    await _connection.execute(
      'ALTER TABLE items ADD COLUMN IF NOT EXISTS material_id INTEGER REFERENCES materials(id) ON DELETE SET NULL',
    );
    await _connection.execute(
      'ALTER TABLE items ADD COLUMN IF NOT EXISTS material_name TEXT',
    );
  }

  Future<void> seedDefaults() async {
    final count = await _connection.execute('SELECT COUNT(*) FROM templates');
    if ((count.first.first as int) > 0) return;
    await insertTemplate(
      name: 'Techado de vivienda',
      description: 'Estructura, cubierta y remates para techo a dos aguas',
      items: const [
        {
          'name': 'Estructura de madera',
          'unit': 'squareMeter',
          'quantity': 86.0,
          'material': 18.50,
          'labor': 12.0,
        },
        {
          'name': 'Lamina galvanizada cal. 26',
          'unit': 'squareMeter',
          'quantity': 86.0,
          'material': 11.80,
          'labor': 4.75,
        },
        {
          'name': 'Aislante termico',
          'unit': 'squareMeter',
          'quantity': 86.0,
          'material': 6.25,
          'labor': 2.10,
        },
        {
          'name': 'Canal de aguas lluvias',
          'unit': 'linearMeter',
          'quantity': 18.0,
          'material': 9.40,
          'labor': 5.50,
        },
        {
          'name': 'Tornillos y fijaciones',
          'unit': 'unit',
          'quantity': 1.0,
          'material': 145.0,
          'labor': 0.0,
        },
      ],
    );
    await insertTemplate(
      name: 'Piso ceramico',
      description: 'Suministro e instalacion de piso interior',
      items: const [
        {
          'name': 'Ceramica nacional',
          'unit': 'squareMeter',
          'quantity': 42.0,
          'material': 14.90,
          'labor': 8.50,
        },
      ],
    );
    await insertTemplate(
      name: 'Muro de block',
      description: 'Levantado, mortero y acabado de muro',
      items: const [
        {
          'name': 'Muro de block de 15 cm',
          'unit': 'squareMeter',
          'quantity': 30.0,
          'material': 16.30,
          'labor': 10.25,
        },
      ],
    );
  }

  Future<void> seedMaterials() async {
    final count = await _connection.execute('SELECT COUNT(*) FROM materials');
    if ((count.first.first as int) > 0) return;
    for (final material in const [
      {'name': 'Clavo galvanizado', 'unit': 'kilogram', 'price': 38.00},
      {'name': 'Tornillo por unidad', 'unit': 'unit', 'price': 4.50},
      {'name': 'Canaleta galvanizada', 'unit': 'linearMeter', 'price': 9.40},
      {'name': 'Lamina galvanizada', 'unit': 'squareMeter', 'price': 11.80},
    ]) {
      await insertMaterial(
        name: material['name'] as String,
        unit: material['unit'] as String,
        price: material['price'] as double,
      );
    }
  }

  Future<List<Map<String, dynamic>>> templates() async {
    final result = await _connection.execute(
      'SELECT id, name, description FROM templates ORDER BY id',
    );
    return result.map((row) => row.toColumnMap()).toList();
  }

  Future<List<Map<String, dynamic>>> itemsFor(int templateId) async {
    final result = await _connection.execute(
      Sql.named(
        'SELECT id, material_id, material_name, name, unit, quantity, material, labor FROM items WHERE template_id = @id ORDER BY id',
      ),
      parameters: {'id': templateId},
    );
    return result.map((row) => row.toColumnMap()).toList();
  }

  Future<List<Map<String, dynamic>>> materials() async {
    final result = await _connection.execute(
      'SELECT id, name, unit, price FROM materials ORDER BY name',
    );
    return result.map((row) => row.toColumnMap()).toList();
  }

  Future<int> insertMaterial({
    required String name,
    required String unit,
    required double price,
  }) async {
    final result = await _connection.execute(
      Sql.named(
        'INSERT INTO materials (name, unit, price) VALUES (@name, @unit, @price) RETURNING id',
      ),
      parameters: {'name': name, 'unit': unit, 'price': price},
    );
    return result.first.first as int;
  }

  Future<int> insertTemplate({
    required String name,
    required String description,
    required List<Map<String, Object>> items,
  }) async {
    return _connection.run((session) async {
      final result = await session.execute(
        Sql.named(
          'INSERT INTO templates (name, description) VALUES (@name, @description) RETURNING id',
        ),
        parameters: {'name': name, 'description': description},
      );
      final id = result.first.first as int;
      for (final item in items) {
        await session.execute(
          Sql.named(
            'INSERT INTO items (template_id, material_id, material_name, name, unit, quantity, material, labor) VALUES (@template, @materialId, @materialName, @name, @unit, @quantity, @material, @labor)',
          ),
          parameters: {
            ...item,
            'template': id,
            'materialId': item['materialId'],
            'materialName': item['materialName'],
          },
        );
      }
      return id;
    });
  }

  Future<int> insertItem({
    required int templateId,
    required String name,
    required String unit,
    required double quantity,
    required double material,
    required double labor,
    int? materialId,
    String? materialName,
  }) async {
    final result = await _connection.execute(
      Sql.named(
        'INSERT INTO items (template_id, material_id, material_name, name, unit, quantity, material, labor) VALUES (@template, @materialId, @materialName, @name, @unit, @quantity, @material, @labor) RETURNING id',
      ),
      parameters: {
        'template': templateId,
        'name': name,
        'unit': unit,
        'quantity': quantity,
        'material': material,
        'labor': labor,
        'materialId': materialId,
        'materialName': materialName,
      },
    );
    return result.first.first as int;
  }

  Future<void> deleteTemplate(int id) => _connection.execute(
    Sql.named('DELETE FROM templates WHERE id = @id'),
    parameters: {'id': id},
  );

  Future<void> deleteItem(int id) => _connection.execute(
    Sql.named('DELETE FROM items WHERE id = @id'),
    parameters: {'id': id},
  );

  Future<void> close() => _connection.close();
}
