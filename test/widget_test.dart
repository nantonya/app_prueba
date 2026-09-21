import 'package:flutter_test/flutter_test.dart';
import 'package:mi_primera_app/main.dart';

void main() {
  test('calcula materiales, mano de obra y total por partida', () {
    final item = BudgetItem(
      name: 'Cubierta',
      unit: Unit.squareMeter,
      quantity: 10,
      material: 12.5,
      labor: 7.5,
    );

    expect(item.total, 200);
  });
}
