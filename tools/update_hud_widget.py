from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
hud = ROOT / "mobile_app" / "lib" / "features" / "developer_mode" / "dev_hud_widget.dart"

content = hud.read_text(encoding="utf-8")
old_hard = '''  Widget _hardware(DevModeState dev, BleState ble, DevController ctrl) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilledButton.tonal(onPressed: ctrl.testSpeakerBeep, child: const Text("Beep")),
            FilledButton.tonal(onPressed: ctrl.runSelfTest, child: const Text("Self-test")),
            FilledButton.tonal(onPressed: ctrl.triggerReboot, child: const Text("Reboot")),
            FilledButton.tonal(onPressed: ctrl.uploadOtaFirmware, child: const Text("OTA .bin")),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => _confirmReset(ctrl),
              child: const Text("Reset NVS"),
            ),
          ],
        ),'''

new_hard = '''  Widget _hardware(DevModeState dev, BleState ble, DevController ctrl) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text("Modo Pantalla Bloqueada (Bolsillo)", style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: const Text("Mantiene enlace y acciones rápidas en la notificación del lockscreen", style: TextStyle(color: AppColors.muted, fontSize: 11)),
          value: dev.isBackgroundModeActive,
          activeColor: AppColors.accent,
          onChanged: (_) => ctrl.toggleBackgroundMode(),
        ),
        const Divider(color: AppColors.border),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilledButton.tonal(onPressed: ctrl.testSpeakerBeep, child: const Text("Beep")),
            FilledButton.tonal(onPressed: ctrl.runSelfTest, child: const Text("Self-test")),
            FilledButton.tonal(onPressed: ctrl.triggerReboot, child: const Text("Reboot")),
            FilledButton.tonal(onPressed: ctrl.uploadOtaFirmware, child: const Text("OTA .bin")),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => _confirmReset(ctrl),
              child: const Text("Reset NVS"),
            ),
          ],
        ),'''

if old_hard in content:
    content = content.replace(old_hard, new_hard)
    hud.write_text(content, encoding="utf-8")
    print("dev_hud_widget hardware updated")
else:
    print("old_hard not found")
