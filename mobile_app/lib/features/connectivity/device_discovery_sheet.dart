import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'ble_service.dart';
import '../diagnostics/device_test_dialog.dart';

class DeviceDiscoverySheet extends ConsumerStatefulWidget {
  const DeviceDiscoverySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const DeviceDiscoverySheet(),
    );
  }

  @override
  ConsumerState<DeviceDiscoverySheet> createState() => _DeviceDiscoverySheetState();
}

class _DeviceDiscoverySheetState extends ConsumerState<DeviceDiscoverySheet>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _ssidCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _manualIpCtrl;
  late final AnimationController _pulseAnim;
  bool _obscurePassword = true;
  DiscoveredGlassesDevice? _selectedDevice;

  @override
  void initState() {
    super.initState();
    final bleState = ref.read(bleServiceProvider);
    _ssidCtrl = TextEditingController(
      text: bleState.detectedPhoneWifiSsid ?? bleState.savedProfile.savedSsid ?? "",
    );
    _passCtrl = TextEditingController();
    _manualIpCtrl = TextEditingController(
      text: bleState.glassesIp ?? bleState.savedProfile.lastKnownIp ?? "",
    );

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // Iniciar auto-descubrimiento al abrir SOLO SI NO están ya conectadas
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!bleState.isWifiConnected && !bleState.isBleConnected) {
        ref.read(bleServiceProvider.notifier).startAutoDiscovery();
      }
    });
  }

  @override
  void dispose() {
    _pulseAnim.dispose();
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    _manualIpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleServiceProvider);
    final bleCtrl = ref.read(bleServiceProvider.notifier);

    // Auto-fill SSID sin pisar el cursor: solo si el campo sigue vacío y
    // colocando el caret al final (evita el anti-patrón de mutar en build).
    if (_ssidCtrl.text.isEmpty && (bleState.detectedPhoneWifiSsid?.isNotEmpty ?? false)) {
      final v = bleState.detectedPhoneWifiSsid!;
      _ssidCtrl.value = TextEditingValue(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
      );
    }

    return Padding(
      // El teclado ya no tapa SSID/pass: empuja el sheet con viewInsets.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDragHandle(),
          _buildHeader(bleState, bleCtrl),
          const Divider(height: 1, color: AppColors.border),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                _buildRadarStatus(bleState, bleCtrl),
                const SizedBox(height: 14),
                _buildDiscoveredDevicesList(bleState, bleCtrl),
                const SizedBox(height: 16),
                _buildWifiProvisioningSection(bleState, bleCtrl),
                const SizedBox(height: 16),
                _buildSavedDeviceSection(bleState, bleCtrl),
                const SizedBox(height: 12),
                _buildManualIpTile(bleCtrl),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.muted.withOpacity(0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(BleState bleState, BleService bleCtrl) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.radar, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Buscador de Gafas",
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  "Auto-descubrimiento Bluetooth LE y Red Local",
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: bleState.isSearching ? "Detener escaneo" : "Buscar de nuevo",
            icon: Icon(
              bleState.isSearching ? Icons.stop_circle_outlined : Icons.refresh,
              color: AppColors.accent,
            ),
            onPressed: () {
              if (bleState.isSearching) {
                bleCtrl.stopDiscovery();
              } else {
                bleCtrl.startAutoDiscovery(force: true);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRadarStatus(BleState bleState, BleService bleCtrl) {
    final isLinked = bleState.isWifiConnected || bleState.isBleConnected;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLinked ? const Color(0xFF10241A) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLinked ? AppColors.success.withOpacity(0.6) : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (bleState.isSearching)
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 0.9 + (_pulseAnim.value * 0.2),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent.withOpacity(0.2),
                        ),
                        child: const Icon(Icons.sensors, color: AppColors.accent, size: 20),
                      ),
                    );
                  },
                )
              else
                Icon(
                  isLinked ? Icons.check_circle : Icons.bluetooth_searching,
                  color: isLinked ? AppColors.success : AppColors.muted,
                  size: 24,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLinked
                          ? "Gafas sincronizadas (${bleState.glassesIp ?? 'Enlace activo'})"
                          : (bleState.isSearching
                              ? "Buscando gafas cercanas..."
                              : "Escaneo completado"),
                      style: TextStyle(
                        color: isLinked ? AppColors.success : AppColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bleState.lastMessage ??
                          "Enciende las gafas para que sean detectadas automáticamente.",
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (bleState.isSearching)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                ),
            ],
          ),
          if (isLinked) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentDim,
                  foregroundColor: AppColors.accent,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => DeviceTestDialog.show(
                  context,
                  ipAddress: bleState.glassesIp,
                  deviceName: bleState.connectedDevice?.platformName ?? "XIAO Gafas",
                ),
                icon: const Icon(Icons.health_and_safety_rounded, size: 16),
                label: const Text(
                  "🧪 Probar Todo (Foto, Mic, Altavoz y WhatsApp)",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiscoveredDevicesList(BleState bleState, BleService bleCtrl) {
    final devices = bleState.discoveredDevices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              "DISPOSITIVOS ENCONTRADOS",
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "${devices.length}",
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            if (devices.isNotEmpty)
              TextButton(
                onPressed: () => bleCtrl.startAutoDiscovery(force: true),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text("Re-escanear", style: TextStyle(fontSize: 11, color: AppColors.accent)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (devices.isEmpty && !bleState.isWifiConnected && !bleState.isBleConnected)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.wifi_tethering_error_rounded, color: AppColors.muted, size: 32),
                const SizedBox(height: 8),
                Text(
                  bleState.isSearching
                      ? "Escaneando señales Bluetooth y Wi-Fi..."
                      : "No se detectaron gafas en este escaneo.",
                  style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Comprueba que las gafas tengan batería y el LED esté encendido.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: () => bleCtrl.startAutoDiscovery(force: true),
                  icon: const Icon(Icons.radar, size: 16),
                  label: const Text("Buscar de nuevo"),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: devices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final d = devices[index];
              final isConnected = (d.ip != null && d.ip == bleState.glassesIp) ||
                  (d.bluetoothDevice != null &&
                      bleState.connectedDevice?.remoteId.str == d.id);
              final isSelected = _selectedDevice?.id == d.id;

              return InkWell(
                onTap: () {
                  setState(() => _selectedDevice = d);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? const Color(0xFF10241A)
                        : (isSelected ? AppColors.accentDim : AppColors.surfaceAlt),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isConnected
                          ? AppColors.success
                          : (isSelected ? AppColors.accent : AppColors.border),
                      width: isSelected || isConnected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          d.medium == DeviceMedium.ble
                              ? Icons.bluetooth
                              : (d.medium == DeviceMedium.softAp
                                  ? Icons.wifi_tethering
                                  : Icons.wifi),
                          color: isConnected ? AppColors.success : AppColors.accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    d.name,
                                    style: const TextStyle(
                                      color: AppColors.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                _buildMediumBadge(d.medium),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (d.ip != null)
                                  Text(
                                    "IP: ${d.ip!}  ·  ",
                                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                                  ),
                                Text(
                                  "Señal: ${d.signalLabel} (${d.rssi} dBm)",
                                  style: TextStyle(
                                    color: d.rssi >= -70 ? AppColors.success : AppColors.warning,
                                    fontSize: 11,
                                  ),
                                ),
                                if (d.batteryPct != null) ...[
                                  Text(
                                    "  ·  Bat: ${d.batteryPct}%",
                                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isConnected)
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF193826),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: () => DeviceTestDialog.show(
                            context,
                            ipAddress: d.ip,
                            deviceName: d.name,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 12, color: AppColors.success),
                              SizedBox(width: 4),
                              Text("Test", style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        )
                      else
                        FilledButton(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: () async {
                            setState(() => _selectedDevice = d);
                            final ok = await bleCtrl.connectToDiscoveredDevice(d);
                            if (ok && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Conectado con éxito a ${d.name}")),
                              );
                            }
                          },
                          child: const Text("Conectar", style: TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildMediumBadge(DeviceMedium medium) {
    final color = medium == DeviceMedium.ble
        ? Colors.blueAccent
        : (medium == DeviceMedium.softAp ? Colors.orangeAccent : AppColors.success);
    final label = medium == DeviceMedium.ble
        ? "Bluetooth"
        : (medium == DeviceMedium.softAp ? "Punto Acceso" : "Wi-Fi");

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildWifiProvisioningSection(BleState bleState, BleService bleCtrl) {
    final targetDevice = _selectedDevice ??
        (bleState.discoveredDevices.where((d) => d.medium == DeviceMedium.ble).firstOrNull);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wifi_protected_setup, color: AppColors.accent, size: 16),
              const SizedBox(width: 6),
              const Text(
                "APROVISIONAMIENTO WI-FI ASISTIDO",
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (bleState.detectedPhoneWifiSsid != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check, size: 10, color: AppColors.success),
                      const SizedBox(width: 3),
                      Text(
                        bleState.detectedPhoneWifiSsid!,
                        style: const TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "Detecta automáticamente la red de tu móvil y la transfiere a las gafas por Bluetooth en un solo paso:",
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withOpacity(0.35)),
            ),
            child: Row(
              children: const [
                Icon(Icons.wifi_tethering, color: Colors.amber, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Si usas Zona Wi-Fi (Hotspot móvil), verifica activar la banda 2.4 GHz ('Maximizar compatibilidad'). Las gafas se auto-enlazarán por UDP.",
                    style: TextStyle(color: Colors.amber, fontSize: 11, height: 1.25),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ssidCtrl,
            style: const TextStyle(color: AppColors.text, fontSize: 13),
            decoration: InputDecoration(
              labelText: "Nombre de Red Wi-Fi (SSID)",
              hintText: "Tu Wi-Fi",
              isDense: true,
              prefixIcon: const Icon(Icons.wifi, size: 18),
              suffixIcon: IconButton(
                icon: const Icon(Icons.sync, size: 16),
                tooltip: "Re-detectar Wi-Fi del teléfono",
                onPressed: () async {
                  await bleCtrl.detectPhoneNetworkInfo();
                  final ssid = ref.read(bleServiceProvider).detectedPhoneWifiSsid;
                  if (ssid != null) _ssidCtrl.text = ssid;
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passCtrl,
            obscureText: _obscurePassword,
            style: const TextStyle(color: AppColors.text, fontSize: 13),
            decoration: InputDecoration(
              labelText: "Contraseña Wi-Fi",
              hintText: "Introduce la contraseña",
              isDense: true,
              prefixIcon: const Icon(Icons.lock_outline, size: 18),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                if (_ssidCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Introduce el nombre de la red Wi-Fi")),
                  );
                  return;
                }

                if (targetDevice != null && targetDevice.medium == DeviceMedium.ble) {
                  final ok = await bleCtrl.pairAndProvisionWifi(
                    device: targetDevice,
                    ssid: _ssidCtrl.text.trim(),
                    password: _passCtrl.text.trim(),
                  );
                  if (ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Credenciales Wi-Fi enviadas a ${targetDevice.name}")),
                    );
                  }
                } else {
                  final ok = await bleCtrl.sendWifiCredentials(
                    _ssidCtrl.text.trim(),
                    _passCtrl.text.trim(),
                  );
                  if (ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Credenciales Wi-Fi enviadas")),
                    );
                  }
                }
              },
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text(
                targetDevice != null
                    ? "Vincular y Enviar Wi-Fi a ${targetDevice.name}"
                    : "Enviar Wi-Fi a Gafas",
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedDeviceSection(BleState bleState, BleService bleCtrl) {
    final profile = bleState.savedProfile;
    if (profile.deviceId == null && profile.lastKnownIp == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "DISPOSITIVO VINCULADO PREVIAMENTE",
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.deviceName ?? "XIAO-SmartGlasses",
                      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    Text(
                      "IP: ${profile.lastKnownIp ?? '—'}  ·  BLE: ${profile.deviceId ?? '—'}",
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
                onPressed: () async {
                  await bleCtrl.forgetDevice();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Gafas olvidadas")),
                    );
                  }
                },
                child: const Text("Olvidar", style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 6),
              FilledButton.tonal(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () async {
                  await bleCtrl.autoConnectGlasses();
                },
                child: const Text("Reconectar", style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManualIpTile(BleService bleCtrl) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text(
        "Conexión manual por IP directa",
        style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _manualIpCtrl,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: "Ej: 192.168.1.50",
                  labelText: "Dirección IP",
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                final ip = _manualIpCtrl.text.trim();
                if (ip.isNotEmpty) {
                  final ok = await bleCtrl.connectDirectIp(ip);
                  if (ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Conectado a $ip")),
                    );
                  }
                }
              },
              child: const Text("Conectar"),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
