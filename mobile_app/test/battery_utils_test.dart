import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses_app/core/utils/battery_utils.dart';

void main() {
  group('BatteryUtils', () {
    test('mapea 3.30V a 0% y 4.20V a 100%', () {
      expect(BatteryUtils.percentFromVoltage(3.30), 0);
      expect(BatteryUtils.percentFromVoltage(4.20), 100);
    });

    test('satura fuera de rango LiPo 1S', () {
      expect(BatteryUtils.percentFromVoltage(2.90), 0);
      expect(BatteryUtils.percentFromVoltage(4.50), 100);
    });

    test('punto medio 3.75V es 50%', () {
      expect(BatteryUtils.percentFromVoltage(3.75), 50);
    });

    test('ADC 0 y 4095 con divisor 1:2', () {
      expect(BatteryUtils.voltageFromAdc(0), 0);
      expect(BatteryUtils.voltageFromAdc(4095), closeTo(6.6, 0.01));
    });

    test('etiquetas de salud para campo', () {
      expect(BatteryUtils.healthLabel(10), 'Crítica');
      expect(BatteryUtils.healthLabel(25), 'Baja');
      expect(BatteryUtils.healthLabel(55), 'Media');
      expect(BatteryUtils.healthLabel(90), 'OK');
    });
  });
}
