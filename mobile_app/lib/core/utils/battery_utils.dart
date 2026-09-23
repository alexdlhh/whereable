/// Espejo del cálculo de firmware (`battery_utils.h`) para tests y HUD.
class BatteryUtils {
  static const double emptyVolts = 3.30;
  static const double fullVolts = 4.20;
  static const double spanVolts = fullVolts - emptyVolts;
  static const int adcMax = 4095;

  static int percentFromVoltage(double vBat) {
    final pct = ((vBat - emptyVolts) / spanVolts) * 100.0;
    if (pct < 0) return 0;
    if (pct > 100) return 100;
    return pct.round();
  }

  static double voltageFromAdc(int rawAdc, {double vRef = 3.3, double divider = 2.0}) {
    if (rawAdc < 0) return 0;
    return (rawAdc / adcMax) * vRef * divider;
  }

  static String healthLabel(int percent) {
    if (percent <= 15) return 'Crítica';
    if (percent <= 30) return 'Baja';
    if (percent <= 70) return 'Media';
    return 'OK';
  }
}
