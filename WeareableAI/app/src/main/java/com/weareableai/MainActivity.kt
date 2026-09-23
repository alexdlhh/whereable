// BASE V57 MUY BIEN RECONNECT + WEB INTELIGENTE + REINTENTO WEB AFINADO ÚNICO. Sin cambios en audio, cámara, full-duplex, TTS ni conexión XIAO.
// BASE V57 MUY BIEN RECONNECT + ANTI-ALUCINACIÓN + WEB GENÉRICA + WEB INTELIGENTE: busca solo si se pide, si es información actual, o si la IA admite que no sabe.
// BASE V57 MUY BIEN RECONNECT + ANTI-ALUCINACIÓN + FIX SOLO ORDEN WEB GENÉRICA.
// BASE V57 MUY BIEN RECONNECT + SOLO ANTI-ALUCINACIÓN VISUAL. BÚSQUEDA WEB SIN CAMBIOS.
// BASE V57 MUY BIEN + BOTÓN REINICIAR CONEXIÓN XIAO. RESTO SIN CAMBIOS.
// V52 - base V51; cambios SOLO en MIC/ESCUCHA y COMPORTAMIENTO. Cámara/visión y web quedan precintados.
package com.weareableai

// V36: TODAS las conexiones HTTP al XIAO usan exclusivamente activeXiaoNetwork.
// Nunca se permite fallback a Wi-Fi/5G normal del móvil.
import java.io.FileOutputStream

import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Network
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.net.wifi.WifiManager
import android.net.wifi.WifiConfiguration

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.foundation.Image
import androidx.compose.ui.layout.ContentScale
import androidx.compose.foundation.background
import androidx.compose.ui.graphics.Color
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig
import com.k2fsa.sherpa.onnx.GenerationConfig
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import android.util.Base64
import java.net.InetAddress
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.speech.SpeechRecognizer
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.content.Intent
import android.media.AudioFormat
import android.media.MediaPlayer
import android.os.ParcelFileDescriptor
import java.io.File
import java.util.Locale
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout


// V53 QUIRÚRGICA: solo BLOQUE 1 (micrófono/escucha) y BLOQUE 4 (comportamiento/lógica).
// BLOQUE 2 (cámara/visión) y BLOQUE 3 (conexiones web externas) permanecen sin cambios.

// =====================================================
// UUID EXACTOS DEL FIRMWARE XIAO
// =====================================================

private val XIAO_SERVICE_UUID: UUID =
    UUID.fromString(
        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
    )

private val XIAO_WIFI_CHAR_UUID: UUID =
    UUID.fromString(
        "beb5483e-36e1-4688-b7f5-ea07361b26a8"
    )

private val XIAO_STATUS_CHAR_UUID: UUID =
    UUID.fromString(
        "8b1b22e1-4547-497b-83a3-6b746a5996b7"
    )


// Un único escaneo BLE activo por proceso.
private var activeBleScanner: android.bluetooth.le.BluetoothLeScanner? = null
private var activeBleScanCallback: ScanCallback? = null

// Mantener viva la red LocalOnlyHotspot mientras la app esté abierta.
private var activeHotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null

// Red Wi-Fi directa del XIAO. NO se enlaza al proceso completo:
// Gemini seguirá saliendo por la red normal del móvil (5G).
@Volatile
private var activeXiaoNetwork: Network? = null
private var activeXiaoNetworkCallback: ConnectivityManager.NetworkCallback? = null
private var xiaoNetworkRequestInProgress = false

private const val XIAO_AP_SSID = "XIAO-Glasses-AP"
private const val XIAO_AP_PASSWORD = "12345678"
private const val XIAO_AP_IP = "192.168.4.1"



// =====================================================
// DIAGNÓSTICO PERSISTENTE V22
// =====================================================
object WearableDiag {
    private const val FILE_NAME = "wearable_diagnostic.log"
    private const val MAX_BYTES = 3_000_000

    @Synchronized
    fun log(context: Context, event: String, detail: String = "") {
        try {
            val file = File(context.filesDir, FILE_NAME)

            if (file.exists() && file.length() > MAX_BYTES) {
                file.writeText(file.readText().takeLast(MAX_BYTES / 2))
            }

            val stamp = java.time.LocalDateTime.now().format(
                java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS")
            )

            val clean = detail
                .replace("\r", " ")
                .replace("\n", " ↩ ")
                .take(4_000)

            file.appendText("$stamp | $event | $clean\n")
        } catch (_: Exception) {
        }
    }

    @Synchronized
    fun read(context: Context): String {
        return try {
            val file = File(context.filesDir, FILE_NAME)
            if (!file.exists() || file.length() == 0L) {
                "Sin eventos registrados todavía."
            } else {
                file.readText()
            }
        } catch (e: Exception) {
            "ERROR LEYENDO INFORME: ${e.javaClass.simpleName}: ${e.message ?: "sin detalle"}"
        }
    }

    @Synchronized
    fun clear(context: Context) {
        try {
            File(context.filesDir, FILE_NAME).writeText("")
        } catch (_: Exception) {
        }
    }
}

fun diag(context: Context, event: String, detail: String = "") {
    // V37 DIAGNÓSTICO REDUCIDO: guardar SOLO fallos reales o degradaciones útiles.
    // Incluye fallos duros y también problemas funcionales de escucha/transcripción
    // que antes no aparecían por no contener literalmente ERROR/FAIL/TIMEOUT.
    // No cambia el funcionamiento de ningún subsistema; únicamente filtra el log.
    val e = event.uppercase(Locale.ROOT)

    val isProblemEvent =
        e.contains("ERROR") ||
                e.contains("FAIL") ||
                e.contains("FAILED") ||
                e.contains("DROPPED") ||
                e.contains("EXCEPTION") ||
                e.contains("TIMEOUT") ||
                e.contains("UNAVAILABLE") ||
                e.contains("NO_SPEECH") ||
                e.contains("REJECTED") ||
                e.contains("SLOW") ||
                // V50: trazas mínimas para saber si una frase válida llega a la IA
                // y si la petición de Internet se detecta, se lanza y termina bien.
                // Son pocos eventos por pregunta y mantienen el informe compacto.
                e == "PIPELINE_TEXT_ACCEPTED" ||
                e == "WEB_DECISION" ||
                e == "WEB_TRIGGERED" ||
                e == "WEB_OK" ||
                e == "WEB_FALLBACK_TRIGGERED" ||
                e == "WEB_FALLBACK_OK" ||
                e == "WEB_RETRY_REFINED_TRIGGERED" ||
                e == "WEB_RETRY_REFINED_OK" ||
                e == "WEB_RETRY_REFINED_ANSWER_OK" ||
                e == "VOSK_AUDIO_MEASURE"

    if (isProblemEvent) {
        WearableDiag.log(context.applicationContext, event, detail)
    }
}

// =====================================================
// DIAGNÓSTICO DE CONCURRENCIA / BLOQUEOS
// Registra qué subsistemas están usando el XIAO en cada momento.
// =====================================================
private object DiagRuntime {
    private val seq = java.util.concurrent.atomic.AtomicLong(0L)
    private val cameraActive = java.util.concurrent.atomic.AtomicInteger(0)
    private val micActive = java.util.concurrent.atomic.AtomicInteger(0)
    private val playbackActive = java.util.concurrent.atomic.AtomicInteger(0)

    fun nextId(): Long = seq.incrementAndGet()
    fun cameraStart() { cameraActive.incrementAndGet() }
    fun cameraEnd() { cameraActive.updateAndGet { if (it > 0) it - 1 else 0 } }
    fun micStart() { micActive.incrementAndGet() }
    fun micEnd() { micActive.updateAndGet { if (it > 0) it - 1 else 0 } }
    fun playbackStart() { playbackActive.incrementAndGet() }
    fun playbackEnd() { playbackActive.updateAndGet { if (it > 0) it - 1 else 0 } }

    fun snapshot(): String =
        "cam=${cameraActive.get()} mic=${micActive.get()} play=${playbackActive.get()} " +
                "xiaoNet=${activeXiaoNetwork != null} hotspot=${activeHotspotReservation != null} " +
                "bleScan=${activeBleScanCallback != null} thread=${Thread.currentThread().name} " +
                "uptimeMs=${android.os.SystemClock.elapsedRealtime()}"
}

private fun installDiagnosticCrashHandler(context: Context) {
    val previous = Thread.getDefaultUncaughtExceptionHandler()
    if (previous is DiagnosticCrashHandler) return
    Thread.setDefaultUncaughtExceptionHandler(
        DiagnosticCrashHandler(context.applicationContext, previous)
    )
}

private class DiagnosticCrashHandler(
    private val context: Context,
    private val previous: Thread.UncaughtExceptionHandler?
) : Thread.UncaughtExceptionHandler {
    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        try {
            val trace = android.util.Log.getStackTraceString(throwable).take(12_000)
            diag(
                context,
                "UNCAUGHT_EXCEPTION",
                "thread=${thread.name} type=${throwable.javaClass.name} msg=${throwable.message ?: "sin detalle"} " +
                        "state=${DiagRuntime.snapshot()} stack=$trace"
            )
        } catch (_: Exception) { }
        previous?.uncaughtException(thread, throwable)
    }
}


// =====================================================
// MAIN ACTIVITY
// =====================================================

class MainActivity : ComponentActivity() {

    private var permissionGrantedCallback:
            (() -> Unit)? = null

    private val bluetoothPermissionLauncher =
        registerForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions()
        ) { permissions ->

            val ok =
                permissions.values.all { it }

            if (ok) {
                permissionGrantedCallback?.invoke()
            }

            permissionGrantedCallback = null
        }


    private val audioPermissionLauncher =
        registerForActivityResult(
            ActivityResultContracts.RequestPermission()
        ) { granted ->
            // El Modo IA comprobará de nuevo el permiso antes de transcribir.
        }


    override fun onCreate(
        savedInstanceState: Bundle?
    ) {

        super.onCreate(savedInstanceState)

        installDiagnosticCrashHandler(this)

        // Cada ejecución nueva empieza con un informe limpio.
        // Una recreación de Activity (por ejemplo rotación) no borra la sesión en curso.
        if (savedInstanceState == null) {
            WearableDiag.clear(this)
            diag(
                this,
                "SESSION_START",
                "Nueva sesión automática · appStart=true " +
                        "sdk=${android.os.Build.VERSION.SDK_INT} " +
                        "device=${android.os.Build.MANUFACTURER}/${android.os.Build.MODEL} " +
                        "state=${DiagRuntime.snapshot()}"
            )
        } else {
            diag(this, "ACTIVITY_RECREATE", "savedState=true state=${DiagRuntime.snapshot()}")
        }

        diag(
            this,
            "APP_ONCREATE",
            "audioPermission=${ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED} " +
                    "state=${DiagRuntime.snapshot()}"
        )

        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            audioPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }

        setContent {

            MaterialTheme {

                WearableAIScreen(
                    context = this,
                    activity = this
                )
            }
        }

        diag(this, "UI_SETCONTENT_DONE", "Compose solicitado; TTS no bloquea arranque")
    }


    fun requestBluetoothPermissions(
        onGranted: () -> Unit
    ) {

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.S
        ) {

            val scanGranted =
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.BLUETOOTH_SCAN
                ) ==
                        PackageManager.PERMISSION_GRANTED

            val connectGranted =
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.BLUETOOTH_CONNECT
                ) ==
                        PackageManager.PERMISSION_GRANTED

            val nearbyWifiGranted =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.NEARBY_WIFI_DEVICES
                    ) == PackageManager.PERMISSION_GRANTED
                } else {
                    true
                }

            if (
                scanGranted &&
                connectGranted &&
                nearbyWifiGranted
            ) {

                onGranted()

            } else {

                permissionGrantedCallback =
                    onGranted

                val permissions = mutableListOf(
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    permissions += Manifest.permission.NEARBY_WIFI_DEVICES
                }
                bluetoothPermissionLauncher.launch(permissions.toTypedArray())
            }

        } else {

            val locationGranted =
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ) ==
                        PackageManager.PERMISSION_GRANTED


            if (locationGranted) {

                onGranted()

            } else {

                permissionGrantedCallback =
                    onGranted

                bluetoothPermissionLauncher.launch(
                    arrayOf(
                        Manifest.permission.ACCESS_FINE_LOCATION
                    )
                )
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun forceReconnectDirectlyToXiao(
        onStatus: (String) -> Unit,
        onReady: () -> Unit
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            onStatus("Android demasiado antiguo para reconexión directa")
            return
        }

        val connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        activeXiaoNetworkCallback?.let {
            try {
                connectivityManager.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }

        activeXiaoNetworkCallback = null
        activeXiaoNetwork = null
        xiaoNetworkRequestInProgress = false

        onStatus("Reiniciando conexión con XIAO...")

        connectDirectlyToXiao(
            onStatus = onStatus,
            onReady = onReady
        )
    }


    @SuppressLint("MissingPermission")
    fun connectDirectlyToXiao(
        onStatus: (String) -> Unit,
        onReady: () -> Unit
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            onStatus("Android demasiado antiguo para conexión directa")
            return
        }

        val connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        if (activeXiaoNetwork != null) {
            onStatus("Conectado directamente al XIAO · 192.168.4.1")
            onReady()
            return
        }

        if (xiaoNetworkRequestInProgress) {
            onStatus("Esperando selección de XIAO-Glasses-AP")
            return
        }

        activeXiaoNetworkCallback?.let {
            try {
                connectivityManager.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }

        activeXiaoNetwork = null
        xiaoNetworkRequestInProgress = true

        val specifier =
            WifiNetworkSpecifier.Builder()
                .setSsid(XIAO_AP_SSID)
                .setWpa2Passphrase(XIAO_AP_PASSWORD)
                .build()

        val request =
            NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .setNetworkSpecifier(specifier)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()

        val callback =
            object : ConnectivityManager.NetworkCallback() {

                override fun onAvailable(network: Network) {
                    xiaoNetworkRequestInProgress = false
                    activeXiaoNetwork = network
                    runOnUiThread {
                        onStatus("Conectado directamente al XIAO · 192.168.4.1")
                        onReady()
                    }
                }

                override fun onLost(network: Network) {
                    xiaoNetworkRequestInProgress = false
                    if (activeXiaoNetwork == network) {
                        activeXiaoNetwork = null
                    }
                    runOnUiThread {
                        onStatus("Conexión directa con XIAO perdida")
                    }
                }

                override fun onUnavailable() {
                    xiaoNetworkRequestInProgress = false
                    activeXiaoNetwork = null
                    runOnUiThread {
                        onStatus("No se pudo conectar a XIAO-Glasses-AP")
                    }
                }
            }

        activeXiaoNetworkCallback = callback
        onStatus("Selecciona XIAO-Glasses-AP cuando Android lo pida")
        connectivityManager.requestNetwork(request, callback)
    }

}


// =====================================================
// PANTALLA PRINCIPAL
// =====================================================

@Composable
fun WearableAIScreen(
    context: Context,
    activity: MainActivity
) {

    val prefs =
        remember {

            context.getSharedPreferences(
                "wearable_ai",
                Context.MODE_PRIVATE
            )
        }


    var xiaoIp by remember {

        mutableStateOf(
            prefs.getString(
                "xiao_ip",
                "192.168.4.1"
            ) ?: "192.168.4.1"
        )
    }


    var apiKey by remember {

        mutableStateOf(
            prefs.getString(
                "cerebras_key",
                prefs.getString("gemini_key", "")
            ) ?: ""
        )
    }


    var tavilyApiKey by remember {
        mutableStateOf(
            prefs.getString(
                "tavily_key",
                ""
            ) ?: ""
        )
    }


    var wifiSsid by remember {

        mutableStateOf(
            prefs.getString(
                "wifi_ssid",
                ""
            ) ?: ""
        )
    }


    var wifiPassword by remember {
        mutableStateOf(
            loadWifiPasswordSecure(context, wifiSsid)
        )
    }


    var connectionStatus by remember {
        mutableStateOf("Sin comprobar")
    }


    var appStatus by remember {
        mutableStateOf("Preparado")
    }
    var geminiResult by remember { mutableStateOf("") }


    var micResult by remember {
        mutableStateOf("Sin probar")
    }


    var speakerResult by remember {
        mutableStateOf("Sin probar")
    }


    var cameraResult by remember {
        mutableStateOf("Sin probar")
    }


    var testResult by remember {
        mutableStateOf("")
    }


    var wifiStatus by remember {
        mutableStateOf("Sin configurar")
    }


    var aiMode by remember {
        mutableStateOf(false)
    }

    // V31: no arrancamos cámara y micro a ciegas.
    // Primero confirmamos que el servidor HTTP del XIAO responde en /status.
    var xiaoHttpReady by remember {
        mutableStateOf(false)
    }


    val scope =
        rememberCoroutineScope()


    // =====================================================
    // CONEXION DIRECTA MOVIL -> AP DEL XIAO
    // XIAO HTTP por 192.168.4.1; Gemini conserva 5G.
    // =====================================================
    LaunchedEffect(Unit) {
        xiaoIp = XIAO_AP_IP
        prefs.edit().putString("xiao_ip", XIAO_AP_IP).apply()

        activity.requestBluetoothPermissions {
            activity.connectDirectlyToXiao(
                onStatus = { wifiStatus = it },
                onReady = {
                    xiaoIp = XIAO_AP_IP
                    connectionStatus = "Conectado"
                }
            )
        }
    }


    // =====================================================
    // MODO IA - CÁMARA + CONTEXTO VISUAL
    // - La cámara refresca la "mirada" del XIAO cada ~2 segundos.
    // - NO se analiza cada captura.
    // - Cuando llega una pregunta válida, se analiza la última foto disponible.
    // - Esa descripción se incorpora al contexto antes de responder.
    // =====================================================
    var visualContext by remember {
        mutableStateOf(prefs.getString("visual_context", "") ?: "")
    }
    var visualMemoryCount by remember { mutableStateOf(0) }
    var latestCameraJpeg by remember { mutableStateOf<ByteArray?>(null) }

    // V39: serializa únicamente los análisis visuales para que el contexto
    // de fondo y una pregunta visual no pisen la misma petición.
    val visualAnalysisBusy = remember {
        java.util.concurrent.atomic.AtomicBoolean(false)
    }

    // Memoria temporal multimodal: guarda TEXTO, nunca las fotos.
    // Mezcla lo que la cámara ha descrito y lo que el usuario ha dicho.
    var multimodalMemory by remember {
        mutableStateOf(prefs.getString("multimodal_memory", "") ?: "")
    }

    // Memoria explícita de conversación y memoria visual cronológica.
    // Se mantienen separadas para que referencias como "continúa" y "eso de antes"
    // funcionen aunque la cámara cambie entre turnos.
    var conversationMemory by remember {
        mutableStateOf(prefs.getString("conversation_memory", "") ?: "")
    }
    var visualTimelineMemory by remember {
        mutableStateOf(prefs.getString("visual_timeline_memory", "") ?: "")
    }

    // La visión cede prioridad mientras Vosk o Cerebras/TTS están trabajando.
    // IMPORTANTE V13: esto SOLO afecta a la visión. NUNCA detiene la captura del micrófono.
    var transcriptionBusy by remember { mutableStateOf(false) }
    var cerebrasBusy by remember { mutableStateOf(false) }
    val voiceBusy by rememberUpdatedState(transcriptionBusy || cerebrasBusy)

    // Estados independientes de la tubería de voz.
    var captureState by remember { mutableStateOf("DETENIDA") }
    var transcriptionState by remember { mutableStateOf("EN ESPERA") }
    var thinkingState by remember { mutableStateOf("EN ESPERA") }
    var responseState by remember { mutableStateOf("EN ESPERA") }
    var queuedPhrases by remember { mutableStateOf(0) }
    var queuedTexts by remember { mutableStateOf(0) }
    var droppedPhrases by remember { mutableStateOf(0) }
    var droppedTexts by remember { mutableStateOf(0) }
    var lastTranscript by remember { mutableStateOf("") }
    var diagnosticUiStatus by remember { mutableStateOf("Sin copiar") }

    // BARGE-IN: permite interrumpir al asistente mientras habla.
    val assistantSpeakingFlag = remember {
        java.util.concurrent.atomic.AtomicBoolean(false)
    }
    val speechInterruptRequested = remember {
        java.util.concurrent.atomic.AtomicBoolean(false)
    }
    val currentAssistantSpeech = remember {
        java.util.concurrent.atomic.AtomicReference("")
    }

    var selectedTtsVoiceName by remember {
        mutableStateOf(prefs.getString("tts_voice_name", "sherpa-es_ES-miro-high") ?: "sherpa-es_ES-miro-high")
    }
    var availableSpanishVoices by remember {
        mutableStateOf<List<TtsVoiceOption>>(emptyList())
    }

    // V34: la lista Sherpa es local y ligera. NO cargamos el modelo aquí.
    // Así Compose, cámara y micrófono arrancan sin esperar al motor de voz.
    LaunchedEffect(Unit) {
        availableSpanishVoices = loadSpanishTtsVoices(context)
        if (availableSpanishVoices.none { it.name == selectedTtsVoiceName }) {
            selectedTtsVoiceName = "sherpa-es_ES-miro-high"
            prefs.edit().putString("tts_voice_name", selectedTtsVoiceName).apply()
        }
        diag(context, "TTS_VOICES_READY", "count=${availableSpanishVoices.size} selected=$selectedTtsVoiceName engine=sherpa-onnx-lazy")
    }

    // =====================================================
    // V36 - PRECHECK HTTP DEL XIAO SOBRE SU RED DIRECTA
    // Evita lanzar /capture y /mic_sample simultáneamente antes
    // de comprobar que 192.168.4.1 realmente responde.
    // =====================================================
    LaunchedEffect(aiMode, xiaoIp) {
        xiaoHttpReady = false
        if (!aiMode) return@LaunchedEffect

        var attempt = 0
        while (aiMode && !xiaoHttpReady) {
            // V36: no hacemos ni una petición HTTP hasta que Android haya
            // entregado la red concreta XIAO-Glasses-AP. Esto evita que
            // 192.168.4.1 salga por 192.168.1.x o por la red móvil.
            if (activeXiaoNetwork == null) {
                delay(250)
                continue
            }

            attempt++
            val started = android.os.SystemClock.elapsedRealtime()
            diag(context, "XIAO_STATUS_PROBE_START", "attempt=$attempt ip=$xiaoIp")

            val result = httpGetBytes(
                ip = xiaoIp,
                endpoint = "/status",
                connectTimeoutMs = 700,
                readTimeoutMs = 1_200
            )
            val elapsed = android.os.SystemClock.elapsedRealtime() - started

            if (result.success && result.data.isNotEmpty()) {
                xiaoHttpReady = true
                diag(
                    context,
                    "XIAO_STATUS_PROBE_OK",
                    "attempt=$attempt bytes=${result.data.size} elapsedMs=$elapsed"
                )
            } else {
                diag(
                    context,
                    "XIAO_STATUS_PROBE_FAIL",
                    "attempt=$attempt error=${result.error.ifBlank { "sin respuesta" }} elapsedMs=$elapsed"
                )
                delay(700)
            }
        }
    }

    // =====================================================
    // PREVISUALIZACIÓN RÁPIDA DE CÁMARA
    // Esta es la "mirada" del dispositivo: se muestran TODAS las capturas.
    // Objetivo: refrescar la pantalla aproximadamente cada 2 s.
    // El análisis IA se hace después, solo cuando llega una pregunta.
    // V23: la cámara intenta mantenerse activa siempre.
    // No se pausa por Vosk ni por /play_audio.
    // =====================================================
    LaunchedEffect(aiMode, xiaoIp, xiaoHttpReady) {
        diag(context, "CAMERA_LOOP_STATE", "aiMode=$aiMode ip=$xiaoIp state=${DiagRuntime.snapshot()}")
        if (!aiMode || !xiaoHttpReady) return@LaunchedEffect

        while (aiMode && xiaoHttpReady) {
            // V23: no pausamos artificialmente la cámara por Vosk ni por TTS.
            // Si el XIAO no puede atender /capture mientras reproduce audio,
            // el diagnóstico mostrará CAMERA_ERROR/TIMEOUT y lo sabremos.
            val cameraRequestId = DiagRuntime.nextId()
            val cameraStartedAt = android.os.SystemClock.elapsedRealtime()
            DiagRuntime.cameraStart()
            diag(
                context,
                "CAMERA_REQUEST_START",
                "id=$cameraRequestId ip=$xiaoIp connectTimeoutMs=700 readTimeoutMs=1500 state=${DiagRuntime.snapshot()}"
            )

            val preview = try {
                // V36: conexión obligatoria por activeXiaoNetwork + timeouts reales.
                // No dependemos de cancelar desde fuera una llamada bloqueada.
                httpGetBytes(
                    ip = xiaoIp,
                    endpoint = "/capture",
                    connectTimeoutMs = 700,
                    readTimeoutMs = 1_500
                )
            } finally {
                DiagRuntime.cameraEnd()
            }

            val cameraElapsed = android.os.SystemClock.elapsedRealtime() - cameraStartedAt

            if (preview != null && preview.success && preview.data.isNotEmpty()) {
                latestCameraJpeg = unmirrorJpeg(preview.data)
                diag(
                    context,
                    "CAMERA_FRAME",
                    "id=$cameraRequestId bytes=${preview.data.size} elapsedMs=$cameraElapsed state=${DiagRuntime.snapshot()}"
                )
                if (cameraElapsed > 1_000) {
                    diag(context, "CAMERA_SLOW", "id=$cameraRequestId elapsedMs=$cameraElapsed state=${DiagRuntime.snapshot()}")
                }
            } else {
                diag(
                    context,
                    "CAMERA_ERROR",
                    "id=$cameraRequestId error=${preview?.error ?: "timeout/null"} elapsedMs=$cameraElapsed state=${DiagRuntime.snapshot()}"
                )
            }

            delay(2_000)
        }
    }

    // =====================================================
    // V39 - RESTAURACIÓN DEL CONTEXTO VISUAL CONTINUO
    // Basado en la arquitectura anterior que sí creaba memoria visual:
    // - la vista de cámara sigue refrescando aproximadamente cada 2 s;
    // - se MUESTREAN capturas cada ~2 s, pero el contexto visual solo se actualiza con una muestra periódica;
    // - no se analiza cada foto ni se guardan fotografías: solo texto resumido;
    // - si voz/Cerebras están ocupados, la visión cede prioridad.
    // IMPORTANTE: se conserva el modelo de visión que ya tenía la V37.
    // =====================================================
    LaunchedEffect(aiMode, xiaoHttpReady, apiKey) {
        if (!aiMode || !xiaoHttpReady) return@LaunchedEffect

        while (aiMode && xiaoHttpReady) {
            if (voiceBusy || apiKey.isBlank()) {
                delay(250)
                continue
            }

            val frameForContext = latestCameraJpeg?.copyOf()
            if (frameForContext == null || frameForContext.isEmpty()) {
                delay(250)
                continue
            }

            if (!visualAnalysisBusy.compareAndSet(false, true)) {
                delay(150)
                continue
            }

            try {
                val update = updateCerebrasVisualContext(
                    context = context,
                    apiKey = apiKey,
                    jpeg = frameForContext,
                    previousContext = visualContext
                )

                if (update.success) {
                    val value = update.text.trim()
                    if (value.isNotBlank() && value != "NO_CHANGE") {
                        visualContext = compactVisualText(value)
                        visualMemoryCount++

                        val stamp = java.time.LocalTime.now()
                            .format(java.time.format.DateTimeFormatter.ofPattern("HH:mm:ss"))

                        val updatedVisualMemory = appendVisualObservation(
                            visualTimelineMemory,
                            value,
                            stamp
                        )
                        val memoryChanged = updatedVisualMemory != visualTimelineMemory
                        visualTimelineMemory = updatedVisualMemory

                        if (memoryChanged) {
                            multimodalMemory = (
                                    multimodalMemory + "\n[$stamp] VISTO: " + visualContext
                                    ).takeLast(16_000)
                        }

                        prefs.edit()
                            .putString("visual_context", visualContext)
                            .putString("multimodal_memory", multimodalMemory)
                            .putString("visual_timeline_memory", visualTimelineMemory)
                            .apply()
                    }
                } else {
                    diag(context, "VISION_CONTEXT_FAIL", update.error.take(1_200))
                }
            } finally {
                visualAnalysisBusy.set(false)
            }

            delay(6_000) // contexto continuo muestreado: la cámara sigue refrescando cada ~2 s
        }
    }


    // =====================================================
    // V13 - MOTOR DE ESCUCHA CONTINUA REAL
    // =====================================================
    // Arquitectura de tres etapas independientes:
    //   1) PRODUCTOR HTTP + VAD -> voicePhraseQueue
    //   2) VOSK -> recognizedTextQueue
    //   3) CEREBRAS -> TTS -> XIAO
    //
    // La captura no espera jamás por Vosk, Cerebras ni /play_audio.
    // Los bloques grandes de /mic_sample se trocean internamente en ventanas
    // PCM de 100 ms para que el VAD decida con precisión inicio y fin de frase.
    // =====================================================
    val voicePhraseQueue = remember {
        kotlinx.coroutines.channels.Channel<ByteArray>(capacity = 12)
    }
    val recognizedTextQueue = remember {
        kotlinx.coroutines.channels.Channel<String>(capacity = 12)
    }

    // Scope independiente de Compose/Main para la captura de audio.
    val continuousCaptureScope = remember {
        kotlinx.coroutines.CoroutineScope(
            kotlinx.coroutines.SupervisorJob() + Dispatchers.IO
        )
    }

    DisposableEffect(Unit) {
        onDispose {
            continuousCaptureScope.cancel()
        }
    }

    // -----------------------------------------------------
    // ETAPA 1: PRODUCTOR - SOLO CAPTURA + VAD + SEGMENTACIÓN
    // -----------------------------------------------------
    DisposableEffect(aiMode, xiaoIp, xiaoHttpReady) {
        diag(context, "MIC_LOOP_STATE", "aiMode=$aiMode ip=$xiaoIp state=${DiagRuntime.snapshot()}")
        if (!aiMode || !xiaoHttpReady) {
            captureState = if (aiMode) "ESPERANDO XIAO HTTP" else "DETENIDA"
            onDispose { }
        } else {
            while (voicePhraseQueue.tryReceive().isSuccess) { }
            while (recognizedTextQueue.tryReceive().isSuccess) { }
            queuedPhrases = 0
            queuedTexts = 0

            val captureJob = continuousCaptureScope.launch {
                // 16 kHz, mono, PCM16 => 3.200 bytes = 100 ms.
                val frameBytes = 3_200
                val preRoll = java.util.ArrayDeque<ByteArray>()
                val preRollMaxFrames = 7          // V51: 700 ms para conservar sílabas iniciales suaves (p. ej. "in-" de "información")
                val bargePreRoll = java.util.ArrayDeque<ByteArray>()
                val bargePreRollMaxFrames = 6     // 600 ms exclusivos para interrupción durante TTS
                val silenceFramesToClose = 10     // 1.000 ms: margen de continuación de solo 200 ms.
                val maxPhraseFrames = 120         // 12 s máximo

                var phrase: java.io.ByteArrayOutputStream? = null
                var phraseFrames = 0
                var silentFrames = 0
                // V27: exigimos 2 frames consecutivos (~200 ms) antes de abrir frase.
                // El pre-roll conserva el comienzo, así que no cortamos la primera sílaba.
                var candidateVoiceFrames = 0
                var candidateStrongFrames = 0

                // V25: detector rápido de cualquier intervención del usuario
                // mientras el asistente habla. No espera al cierre del VAD.
                var fastStopRecognizer: Recognizer? = null
                var fastStopTriggered = false
                var fastStopFrameCount = 0
                var lastFastCandidate = ""
                var stableFastCandidateFrames = 0
                var echoGuardUntilMs = 0L

                // V26C: barge-in acústico filtrado para reducir cortes falsos + limpieza de colas.
                // Aprende el nivel habitual que llega al micro mientras
                // habla el asistente y corta ante una subida clara.
                var acousticBaselineRms = 0.0
                var acousticBaselinePeak = 0.0
                var acousticWarmupFrames = 0
                var acousticHotFrames = 0
                var wasAssistantSpeaking = false
                var postPlaybackIgnoreFrames = 0

                fun closeFastStopRecognizer() {
                    try { fastStopRecognizer?.close() } catch (_: Exception) {}
                    fastStopRecognizer = null
                    fastStopFrameCount = 0
                    lastFastCandidate = ""
                    stableFastCandidateFrames = 0
                }

                // V34: el barge-in usa un pre-roll SEPARADO del VAD normal.
                // Así el audio del propio altavoz nunca contamina preRoll/phrase.
                fun forceOpenPhraseForBarge(reason: String) {
                    if (phrase != null) return

                    val started = java.io.ByteArrayOutputStream()
                    while (bargePreRoll.isNotEmpty()) {
                        started.write(bargePreRoll.removeFirst())
                    }

                    preRoll.clear()
                    phrase = started
                    phraseFrames = (started.size() / frameBytes).coerceAtLeast(1)
                    silentFrames = 0
                    candidateVoiceFrames = 0
                    candidateStrongFrames = 0

                    diag(
                        context,
                        "BARGE_PHRASE_FORCED_OPEN",
                        "reason=$reason bargePrerollBytes=${started.size()} phraseFrames=$phraseFrames"
                    )
                }

                suspend fun clearStaleQueuesForBarge(reason: String) {
                    var removedAudio = 0
                    var removedText = 0

                    while (voicePhraseQueue.tryReceive().isSuccess) {
                        removedAudio++
                    }
                    while (recognizedTextQueue.tryReceive().isSuccess) {
                        removedText++
                    }

                    if (removedAudio > 0 || removedText > 0) {
                        withContext(Dispatchers.Main.immediate) {
                            queuedPhrases = 0
                            queuedTexts = 0
                        }
                    }

                    diag(
                        context,
                        "BARGE_STALE_QUEUES_CLEARED",
                        "reason=$reason audio=$removedAudio text=$removedText"
                    )
                }

                suspend fun publishPhrase(reason: String) {
                    val bytes = phrase?.toByteArray() ?: ByteArray(0)
                    phrase = null
                    phraseFrames = 0
                    silentFrames = 0
                    candidateVoiceFrames = 0
                    candidateStrongFrames = 0

                    val rejection = phraseRejectionReason(bytes, frameBytes)
                    if (rejection != null) {
                        diag(context, "VAD_PHRASE_REJECTED", "reason=$rejection bytes=${bytes.size}")
                        return
                    }
                    diag(context, "VAD_PHRASE_CLOSED", "reason=$reason bytes=${bytes.size} silenceLimitMs=${silenceFramesToClose * 100}")
                    val sent = voicePhraseQueue.trySend(bytes)
                    withContext(Dispatchers.Main.immediate) {
                        if (sent.isSuccess) {
                            queuedPhrases = (queuedPhrases + 1).coerceAtMost(12)
                            diag(
                                context,
                                "AUDIO_PHRASE_ENQUEUED",
                                "bytes=${bytes.size} queue=$queuedPhrases"
                            )
                        } else {
                            droppedPhrases++
                            diag(
                                context,
                                "AUDIO_PHRASE_DROPPED",
                                "bytes=${bytes.size} dropped=$droppedPhrases"
                            )
                        }
                    }
                }

                withContext(Dispatchers.Main.immediate) {
                    captureState = "CAPTURANDO"
                }

                while (kotlinx.coroutines.currentCoroutineContext().isActive) {
                    val micRequestId = DiagRuntime.nextId()
                    val micStartedAt = android.os.SystemClock.elapsedRealtime()
                    DiagRuntime.micStart()
                    diag(
                        context,
                        "MIC_REQUEST_START",
                        "id=$micRequestId ip=$xiaoIp connectTimeoutMs=700 readTimeoutMs=2500 state=${DiagRuntime.snapshot()}"
                    )
                    val sample = try {
                        // V31: petición serializada con cámara y timeouts internos reales.
                        httpGetBytes(
                            ip = xiaoIp,
                            endpoint = "/mic_sample",
                            connectTimeoutMs = 700,
                            readTimeoutMs = 2_500
                        )
                    } finally {
                        DiagRuntime.micEnd()
                    }
                    val micElapsed = android.os.SystemClock.elapsedRealtime() - micStartedAt

                    if (sample == null || !sample.success || sample.data.isEmpty()) {
                        diag(
                            context,
                            "MIC_SAMPLE_ERROR",
                            "id=$micRequestId error=${sample?.error ?: "timeout/null"} elapsedMs=$micElapsed state=${DiagRuntime.snapshot()}"
                        )
                        withContext(Dispatchers.Main.immediate) {
                            captureState = "REINTENTANDO MICRÓFONO"
                        }
                        delay(100)
                        continue
                    }

                    diag(
                        context,
                        "MIC_SAMPLE_OK",
                        "id=$micRequestId bytes=${sample.data.size} elapsedMs=$micElapsed state=${DiagRuntime.snapshot()}"
                    )
                    if (micElapsed > 1_000) {
                        diag(context, "MIC_SAMPLE_SLOW", "id=$micRequestId elapsedMs=$micElapsed bytes=${sample.data.size} state=${DiagRuntime.snapshot()}")
                    }

                    withContext(Dispatchers.Main.immediate) {
                        captureState = "CAPTURANDO"
                    }

                    // Un /mic_sample puede traer varios segundos. Nunca lo tratamos
                    // como un único bloque de VAD: lo recorremos en ventanas de 100 ms.
                    var offset = 0
                    while (
                        offset < sample.data.size &&
                        kotlinx.coroutines.currentCoroutineContext().isActive
                    ) {
                        val count = minOf(frameBytes, sample.data.size - offset)
                        if (count < 320) break // resto menor de 10 ms: no decide VAD

                        val frame = sample.data.copyOfRange(offset, offset + count)
                        offset += count

                        // V34: detectar transición de playback para limpiar cualquier cola acústica
                        // residual SOLO cuando el asistente terminó de forma natural.
                        val assistantSpeakingNow = assistantSpeakingFlag.get()
                        if (wasAssistantSpeaking && !assistantSpeakingNow) {
                            if (!fastStopTriggered && !speechInterruptRequested.get()) {
                                phrase = null
                                phraseFrames = 0
                                silentFrames = 0
                                candidateVoiceFrames = 0
                                preRoll.clear()
                                bargePreRoll.clear()
                                postPlaybackIgnoreFrames = 4 // 400 ms para cola/eco mecánico del altavoz
                                diag(context, "POST_PLAYBACK_VAD_RESET", "reason=natural_tts_end ignoreMs=400")
                            } else {
                                // Si hubo interrupción real, conservamos la frase del usuario.
                                bargePreRoll.clear()
                                postPlaybackIgnoreFrames = 0
                            }
                        }
                        wasAssistantSpeaking = assistantSpeakingNow

                        if (!assistantSpeakingNow && postPlaybackIgnoreFrames > 0 && phrase == null) {
                            postPlaybackIgnoreFrames--
                            if (postPlaybackIgnoreFrames == 0) {
                                diag(context, "POST_PLAYBACK_VAD_READY", "normal_listening_resumed")
                            }
                            continue
                        }

                        // -------------------------------------------------
                        // V25 FAST BARGE-IN: mientras TTS habla, Vosk recibe cada
                        // frame de 100 ms inmediatamente. Cualquier parcial no-eco
                        // corta la reproducción sin esperar al cierre VAD.
                        // -------------------------------------------------
                        if (assistantSpeakingNow) {
                            // V34: durante TTS, este frame SOLO entra al buffer de barge-in.
                            // El VAD normal queda completamente aislado del altavoz.
                            bargePreRoll.addLast(frame)
                            while (bargePreRoll.size > bargePreRollMaxFrames) bargePreRoll.removeFirst()

                            // =============================================
                            // V26 - BARGE-IN ACÚSTICO INMEDIATO
                            // =============================================
                            // No espera a que Vosk reconozca palabras.
                            // Usa RMS/pico sin DC y una referencia adaptativa
                            // del sonido que normalmente recoge el micro
                            // mientras el propio asistente está hablando.
                            if (!fastStopTriggered) {
                                val stats = pcmAcStats(frame)

                                if (stats.rms > 0.0) {
                                    if (acousticWarmupFrames < 4) {
                                        // ~400 ms iniciales para aprender el nivel
                                        // normal de eco/ruido durante playback.
                                        acousticWarmupFrames++

                                        if (acousticBaselineRms <= 0.0) {
                                            acousticBaselineRms = stats.rms
                                            acousticBaselinePeak = stats.peak
                                        } else {
                                            acousticBaselineRms =
                                                acousticBaselineRms * 0.70 + stats.rms * 0.30
                                            acousticBaselinePeak =
                                                acousticBaselinePeak * 0.70 + stats.peak * 0.30
                                        }

                                        diag(
                                            context,
                                            "ACOUSTIC_BARGE_WARMUP",
                                            "frame=$acousticWarmupFrames rms=${"%.1f".format(stats.rms)} peak=${"%.1f".format(stats.peak)} baseRms=${"%.1f".format(acousticBaselineRms)}"
                                        )
                                    } else {
                                        // V26C: filtro más conservador para evitar que
                                        // cambios normales de volumen del propio TTS se
                                        // interpreten como una intervención del usuario.
                                        // El detector Vosk rápido y el Vosk normal siguen
                                        // funcionando como respaldo para voces más suaves.
                                        val rmsThreshold =
                                            maxOf(85.0, acousticBaselineRms * 2.30)

                                        val peakThreshold =
                                            maxOf(550.0, acousticBaselinePeak * 1.70)

                                        val strongVoice =
                                            stats.rms >= rmsThreshold &&
                                                    stats.peak >= peakThreshold

                                        if (strongVoice) {
                                            acousticHotFrames++
                                        } else {
                                            acousticHotFrames = 0

                                            // Adaptación lenta: el baseline sigue
                                            // al nivel del altavoz sin perseguir
                                            // una intervención humana repentina.
                                            acousticBaselineRms =
                                                acousticBaselineRms * 0.90 + stats.rms * 0.10
                                            acousticBaselinePeak =
                                                acousticBaselinePeak * 0.90 + stats.peak * 0.10
                                        }

                                        // V52: recuperado del comportamiento anterior que ya funcionaba
                                        // (V37): 3 frames fuertes consecutivos cortan el TTS de inmediato.
                                        if (acousticHotFrames >= 3) {
                                            fastStopTriggered = true
                                            speechInterruptRequested.set(true)
                                            clearStaleQueuesForBarge("acoustic")
                                            forceOpenPhraseForBarge("acoustic")

                                            diag(
                                                context,
                                                "ACOUSTIC_BARGE_DETECTED",
                                                "rms=${"%.1f".format(stats.rms)} peak=${"%.1f".format(stats.peak)} baseRms=${"%.1f".format(acousticBaselineRms)} rmsThr=${"%.1f".format(rmsThreshold)} peakThr=${"%.1f".format(peakThreshold)} hotFrames=$acousticHotFrames"
                                            )

                                            // Conserva la intervención del usuario para responder después.
                                            closeFastStopRecognizer()
                                        }
                                    }
                                }
                            }

                            if (!fastStopTriggered) {
                                try {
                                    if (fastStopRecognizer == null) {
                                        val model =
                                            VoskModelCache.get(context.applicationContext)

                                        fastStopRecognizer =
                                            Recognizer(model, 16_000.0f)

                                        fastStopFrameCount = 0

                                        diag(
                                            context,
                                            "FAST_BARGE_LISTENING",
                                            "Detector rápido activado"
                                        )
                                    }

                                    // V53 MIC/ESCUCHA: refuerzo de nivel SOLO para el
                                    // recognizer rápido de barge-in. No cambia VAD, cámara,
                                    // red ni el PCM original del XIAO.
                                    val correctedFrame =
                                        boostPcm16Volume(removeDcOffsetPcm16(frame), 3.0f)

                                    val r = fastStopRecognizer
                                    if (r != null) {
                                        val endpoint =
                                            r.acceptWaveForm(
                                                correctedFrame,
                                                correctedFrame.size
                                            )

                                        fastStopFrameCount++

                                        val partialText = try {
                                            JSONObject(r.partialResult)
                                                .optString("partial", "")
                                                .trim()
                                        } catch (_: Exception) {
                                            ""
                                        }

                                        var candidate = partialText

                                        if (endpoint) {
                                            val resultText = try {
                                                JSONObject(r.result)
                                                    .optString("text", "")
                                                    .trim()
                                            } catch (_: Exception) {
                                                ""
                                            }

                                            if (resultText.isNotBlank()) {
                                                candidate = resultText
                                            }
                                        }

                                        if (candidate.isBlank()) {
                                            lastFastCandidate = ""
                                            stableFastCandidateFrames = 0
                                        }
                                        if (candidate.isNotBlank()) {
                                            diag(
                                                context,
                                                "FAST_BARGE_PARTIAL",
                                                "text=$candidate frames=$fastStopFrameCount"
                                            )
                                        }

                                        if (candidate.isNotBlank()) {
                                            val assistantTextNow =
                                                currentAssistantSpeech.get()

                                            val looksLikeEcho =
                                                assistantTextNow.isNotBlank() &&
                                                        looksLikeAssistantEcho(
                                                            candidate,
                                                            assistantTextNow
                                                        )

                                            if (looksLikeEcho) {
                                                diag(
                                                    context,
                                                    "FAST_BARGE_ECHO_IGNORED",
                                                    "heard=$candidate frames=$fastStopFrameCount"
                                                )
                                            } else {
                                                // V52: recuperado del barge-in anterior (V37):
                                                // cualquier parcial inteligible que NO sea eco corta el TTS.
                                                fastStopTriggered = true
                                                speechInterruptRequested.set(true)
                                                clearStaleQueuesForBarge("fast_vosk")
                                                forceOpenPhraseForBarge("fast_vosk")

                                                diag(
                                                    context,
                                                    "FAST_BARGE_DETECTED",
                                                    "heard=$candidate frames=$fastStopFrameCount"
                                                )

                                                // La frase normal se conserva para responder después.
                                                closeFastStopRecognizer()
                                            }
                                        }
                                    }
                                } catch (e: Exception) {
                                    diag(
                                        context,
                                        "FAST_BARGE_ERROR",
                                        "${e.javaClass.simpleName}: ${e.message ?: "sin detalle"}"
                                    )
                                    closeFastStopRecognizer()
                                }
                            }

                            // CRÍTICO V34: si el usuario NO ha sido confirmado como barge-in,
                            // no dejamos que este frame de playback llegue al VAD normal.
                            if (!fastStopTriggered) {
                                continue
                            }
                        } else {
                            if (
                                fastStopRecognizer != null ||
                                fastStopTriggered
                            ) {
                                closeFastStopRecognizer()
                                fastStopTriggered = false
                                acousticBaselineRms = 0.0
                                acousticBaselinePeak = 0.0
                                acousticWarmupFrames = 0
                                acousticHotFrames = 0
                                echoGuardUntilMs = 0L
                                bargePreRoll.clear()

                                diag(
                                    context,
                                    "FAST_BARGE_IDLE",
                                    "Asistente dejó de hablar"
                                )
                            }
                        }

                        val hasVoice = pcmContainsVoice(frame)
                        val frameStats = pcmAcStats(frame)
                        val strongVoice = frameStats.rms > 95.0 && frameStats.peak > 480.0

                        if (phrase == null) {
                            // V34: no abrimos frase por un chasquido o un único frame de ruido.
                            // Voz baja real se conserva: 3 frames moderados seguidos (~300 ms),
                            // o 2 frames si al menos uno tiene energía claramente vocal.
                            preRoll.addLast(frame)
                            while (preRoll.size > preRollMaxFrames) preRoll.removeFirst()

                            if (hasVoice) {
                                candidateVoiceFrames++
                                if (strongVoice) candidateStrongFrames++

                                val continuousQuietVoice = candidateVoiceFrames >= 3
                                val confidentVoice = candidateVoiceFrames >= 2 && candidateStrongFrames >= 1

                                if (continuousQuietVoice || confidentVoice) {
                                    val started = java.io.ByteArrayOutputStream()
                                    while (preRoll.isNotEmpty()) started.write(preRoll.removeFirst())
                                    phrase = started
                                    phraseFrames = started.size() / frameBytes
                                    silentFrames = 0
                                    candidateVoiceFrames = 0
                                    candidateStrongFrames = 0
                                    diag(
                                        context,
                                        "VAD_PHRASE_OPENED",
                                        "mode=${if (confidentVoice) "confident" else "quiet_continuous"} rms=${"%.1f".format(frameStats.rms)} peak=${"%.1f".format(frameStats.peak)}"
                                    )
                                }
                            } else {
                                candidateVoiceFrames = 0
                                candidateStrongFrames = 0
                            }
                            continue
                        }

                        phrase?.write(frame)
                        phraseFrames++

                        if (hasVoice) {
                            if (silentFrames >= 8) diag(context, "VAD_CONTINUATION_JOINED", "reason=voice_returned_within_200ms_grace silenceFrames=$silentFrames")
                            silentFrames = 0
                        } else {
                            silentFrames++
                            if (silentFrames == 8) diag(context, "VAD_CLOSE_PENDING", "reason=allow_200ms_natural_continuation")
                        }

                        if (
                            silentFrames >= silenceFramesToClose ||
                            phraseFrames >= maxPhraseFrames
                        ) {
                            publishPhrase(if (phraseFrames >= maxPhraseFrames) "maximum_12s" else "silence_1000ms")
                            preRoll.clear()
                        }
                    }
                }

                // Si se cancela con una frase en curso no bloqueamos el cierre.
                phrase = null
                closeFastStopRecognizer()
            }

            onDispose {
                captureJob.cancel()
                captureState = "DETENIDA"
            }
        }
    }

    // -----------------------------------------------------
    // ETAPA 2: VOSK - consume audio y PRODUCE texto válido
    // -----------------------------------------------------
    LaunchedEffect(aiMode, xiaoIp) {
        if (!aiMode) {
            transcriptionState = "EN ESPERA"
            transcriptionBusy = false
            return@LaunchedEffect
        }

        while (aiMode) {
            val phraseBytes = voicePhraseQueue.receive()
            queuedPhrases = (queuedPhrases - 1).coerceAtLeast(0)

            transcriptionBusy = true
            transcriptionState = "TRANSCRIBIENDO"

            diag(
                context,
                "VOSK_START",
                "bytes=${phraseBytes.size} queueRemaining=$queuedPhrases"
            )

            val transcript = transcribeXiaoPcmWithVosk(
                context = context,
                pcmAudio = phraseBytes
            )

            if (!transcript.success || transcript.text.isBlank()) {
                val noSpeech = transcript.error.startsWith("VOSK V9 AUDIO VACÍO") ||
                        (transcript.success && transcript.text.isBlank())
                diag(
                    context,
                    if (noSpeech) "VOSK_NO_SPEECH" else "VOSK_FAIL",
                    "success=${transcript.success} error=${transcript.error.take(800)}"
                )
                transcriptionState = if (noSpeech) {
                    "SIN VOZ RECONOCIBLE · SIGO ESCUCHANDO"
                } else {
                    "ERROR: ${transcript.error.take(180)}"
                }
                transcriptionBusy = false
                continue
            }

            // IMPORTANTE: este texto pertenece a ESTE intento de Vosk.
            // Solo se muestra aquí después de éxito real.
            val acceptedText = transcript.text.trim()

            // V34: si Vosk inventa varias palabras sobre un bloque acústicamente
            // muy débil y discontinuo, no se manda a Cerebras. No afecta a voz baja
            // sostenida: esa sí supera la continuidad aunque su volumen sea pequeño.
            if (suspiciousWeakTranscript(acceptedText, phraseBytes)) {
                diag(context, "VOSK_TEXT_REJECTED", "reason=weak_discontinuous_audio text=$acceptedText bytes=${phraseBytes.size}")
                transcriptionState = "RUIDO / TEXTO DUDOSO · SIGO ESCUCHANDO"
                transcriptionBusy = false
                continue
            }

            lastTranscript = acceptedText
            diag(context, "VOSK_TEXT", "text=$acceptedText")
            // V50: una sola traza compacta confirma que el texto útil ha salido
            // de Vosk y va a seguir por la cadena de Cerebras/web.
            diag(context, "PIPELINE_TEXT_ACCEPTED", "text=${acceptedText.take(500)}")

            // V53 COMPORTAMIENTO/LÓGICA: una orden explícita de silencio
            // mientras el asistente habla corta el TTS y NO genera respuesta nueva.
            if (assistantSpeakingFlag.get() && isFastStopCommand(acceptedText)) {
                speechInterruptRequested.set(true)
                diag(
                    context,
                    "STOP_COMMAND_APPLIED",
                    "heard=$acceptedText action=interrupt_without_reply"
                )
                transcriptionState = "SILENCIO SOLICITADO · ESCUCHANDO"
                transcriptionBusy = false
                continue
            }

            // Si el asistente está hablando, una frase válida puede ser una interrupción.
            // Descartamos ecos evidentes comparando contra el texto que se está reproduciendo.
            if (assistantSpeakingFlag.get()) {
                val assistantTextNow = currentAssistantSpeech.get()

                if (!looksLikeAssistantEcho(acceptedText, assistantTextNow)) {
                    speechInterruptRequested.set(true)
                    diag(
                        context,
                        "BARGE_IN_DETECTED_SLOW",
                        "heard=$acceptedText"
                    )
                    transcriptionState = "INTERRUPCIÓN DETECTADA · ENCOLADA"
                } else {
                    diag(
                        context,
                        "BARGE_IN_ECHO_IGNORED",
                        "heard=$acceptedText assistant=${assistantTextNow.take(500)}"
                    )
                    transcriptionState = "ECO DEL ALTAVOZ IGNORADO"
                    transcriptionBusy = false
                    continue
                }
            } else {
                transcriptionState = "OK · ENCOLADO A CEREBRAS"
            }

            // La cola de texto desacopla completamente Vosk de Cerebras.
            val sent = recognizedTextQueue.trySend(acceptedText)
            if (sent.isSuccess) {
                queuedTexts = (queuedTexts + 1).coerceAtMost(12)
                diag(
                    context,
                    "TEXT_ENQUEUED",
                    "queue=$queuedTexts text=$acceptedText"
                )
            } else {
                droppedTexts++
                diag(
                    context,
                    "TEXT_DROPPED",
                    "dropped=$droppedTexts text=$acceptedText"
                )
                transcriptionState = "ERROR: COLA CEREBRAS LLENA"
            }

            transcriptionBusy = false
        }
    }

    // -----------------------------------------------------
    // ETAPA 3: CEREBRAS -> TTS -> XIAO
    // -----------------------------------------------------
    LaunchedEffect(aiMode, xiaoIp, apiKey) {
        if (!aiMode) {
            thinkingState = "EN ESPERA"
            responseState = "EN ESPERA"
            cerebrasBusy = false
            return@LaunchedEffect
        }

        appStatus = "Modo IA: escucha continua activa"

        while (aiMode) {
            val currentQuestion = recognizedTextQueue.receive()
            queuedTexts = (queuedTexts - 1).coerceAtLeast(0)

            diag(
                context,
                "QUESTION_DEQUEUED",
                "remaining=$queuedTexts text=$currentQuestion"
            )

            cerebrasBusy = true
            responseState = "EN ESPERA"

            // =====================================================
            // VISIÓN BAJO DEMANDA
            // Tomamos una COPIA de la última foto que está mostrando la app.
            // Mientras se analiza, la cámara puede seguir refrescando la pantalla.
            // =====================================================
            val visualReason = visualDecisionReason(currentQuestion, visualTimelineMemory)
            val useVisualMemory = visualReason.startsWith("memory:")
            val incompleteQuestion = isIncompleteVoiceQuestion(currentQuestion)
            val needsCurrentFrame = visualReason.startsWith("current:")
            val detailedVisualQuestion = needsCurrentFrame && isDetailedCurrentVisualQuestion(currentQuestion)
            val rememberedVisual = selectVisualMemory(currentQuestion, visualTimelineMemory)
            var currentFrameDescription = ""

            // V44: cuando el usuario pregunta directamente por lo que está viendo
            // ("¿qué es eso?", "¿qué estás viendo?", "¿qué pone?"...), pedimos
            // una captura NUEVA en ese instante. Si falla, usamos la última vista
            // disponible para no romper el flujo. No afecta al audio ni al contexto
            // visual silencioso de fondo.
            val imageAtQuestion = if (needsCurrentFrame) {
                if (detailedVisualQuestion) {
                    val fresh = httpGetBytes(
                        ip = xiaoIp,
                        endpoint = "/capture",
                        connectTimeoutMs = 900,
                        readTimeoutMs = 2_000
                    )
                    if (fresh.success && fresh.data.isNotEmpty()) {
                        val corrected = unmirrorJpeg(fresh.data)
                        latestCameraJpeg = corrected
                        diag(context, "VISION_FRESH_FRAME", "bytes=${fresh.data.size} reason=direct_visual_question")
                        corrected.copyOf()
                    } else {
                        diag(context, "VISION_FRESH_FRAME_FAIL", "error=${fresh.error.ifBlank { "sin respuesta" }} fallback=latest_frame")
                        latestCameraJpeg?.copyOf()
                    }
                } else {
                    latestCameraJpeg?.copyOf()
                }
            } else null
            if (!needsCurrentFrame || imageAtQuestion == null || imageAtQuestion.isEmpty()) {
                diag(context, "VISION_SKIPPED", "reason=${if (needsCurrentFrame) "current_frame_unavailable" else visualReason}")
            }
            if (useVisualMemory) {
                diag(context, "VISUAL_MEMORY_USED", "reason=$visualReason chars=${rememberedVisual.length} available=${rememberedVisual.isNotBlank()}")
            }

            if (imageAtQuestion != null && imageAtQuestion.isNotEmpty()) {
                thinkingState = "ANALIZANDO IMAGEN"
                diag(context, "VISION_USED_CURRENT_FRAME", "reason=$visualReason jpegBytes=${imageAtQuestion.size}")
                diag(
                    context,
                    "VISION_START",
                    "jpegBytes=${imageAtQuestion.size}"
                )

                while (!visualAnalysisBusy.compareAndSet(false, true)) {
                    delay(40)
                }
                val vision = try {
                    updateCerebrasVisualContext(
                        context = context,
                        apiKey = apiKey,
                        jpeg = imageAtQuestion,
                        previousContext = "", // La descripción actual no debe arrastrar objetos antiguos.
                        detailedRequest = detailedVisualQuestion,
                        userQuestion = currentQuestion
                    )
                } finally {
                    visualAnalysisBusy.set(false)
                }

                if (vision.success) {
                    diag(
                        context,
                        "VISION_OK",
                        vision.text.take(800)
                    )
                    val newVisual = vision.text.trim()

                    if (newVisual.isNotBlank() && newVisual != "NO_CHANGE") {
                        currentFrameDescription = compactVisualText(newVisual)
                        visualContext = currentFrameDescription
                        visualMemoryCount++

                        val visionStamp = java.time.LocalTime.now()
                            .format(java.time.format.DateTimeFormatter.ofPattern("HH:mm:ss"))

                        val updatedVisualMemory = appendVisualObservation(visualTimelineMemory, newVisual, visionStamp)
                        val memoryChanged = updatedVisualMemory != visualTimelineMemory
                        visualTimelineMemory = updatedVisualMemory
                        if (memoryChanged) {
                            multimodalMemory = (multimodalMemory +
                                    "\n[$visionStamp] VISTO: " + currentFrameDescription).takeLast(16_000)
                        }
                        diag(context, "VISUAL_MEMORY_UPDATED",
                            "changed=$memoryChanged reason=${if (memoryChanged) "useful_current_observation" else "irrelevant_or_unchanged_observation_preserve_memory"} chars=${visualTimelineMemory.length}")

                        prefs.edit()
                            .putString("visual_context", visualContext)
                            .putString("multimodal_memory", multimodalMemory)
                            .putString("visual_timeline_memory", visualTimelineMemory)
                            .apply()
                    }
                }
                // No presentar una descripción antigua como si fuera el frame actual.
                if (currentFrameDescription.isBlank()) {
                    diag(context, "VISION_CURRENT_UNAVAILABLE", "reason=analysis_failed_or_empty error=${vision.error.take(300)}")
                }
            }

            // La búsqueda web es una etapa auxiliar. La captura del micrófono
            // sigue funcionando en su scope independiente mientras buscamos.
            var webContext = ""
            val webReason = webDecisionReason(currentQuestion)
            val webRequested = webReason.startsWith("use:")
            val webQuery = wearableSearchQuery(currentQuestion,
                if (needsCurrentFrame) currentFrameDescription else rememberedVisual)
            diag(
                context,
                "WEB_DECISION",
                "requested=$webRequested reason=$webReason query=$webQuery"
            )

            if (webRequested) {
                diag(context, "WEB_TRIGGERED", "reason=$webReason query=$webQuery")
                if (tavilyApiKey.isBlank()) {
                    diag(context, "WEB_FAIL", "Falta API key de Tavily")
                    thinkingState = "WEB: FALTA API KEY"
                    webContext = "BÚSQUEDA WEB NO DISPONIBLE: falta configurar la API key de Tavily. No se han consultado fuentes."
                } else {
                    thinkingState = "BUSCANDO EN INTERNET"
                    val web = searchWebWithTavily(
                        context = context,
                        apiKey = tavilyApiKey,
                        query = webQuery
                    )
                    webContext =
                        if (web.success) {
                            diag(context, "WEB_OK", web.text.take(1_200))
                            web.text
                        } else {
                            diag(context, "WEB_FAIL", web.error.take(1_200))
                            "BÚSQUEDA WEB NO DISPONIBLE: ${web.error.take(300)}"
                        }
                }
            }

            thinkingState = "PENSANDO"

            // El contexto enviado a Cerebras es el ANTERIOR a la pregunta actual.
            // Así la pregunta actual no queda duplicada dentro de la memoria y mantiene
            // prioridad máxima en askCerebrasWithText().
            val memoryBeforeCurrentQuestion = buildString {
                if (conversationMemory.isNotBlank()) {
                    append("CONVERSACIÓN RECIENTE:\n")
                    append(conversationMemory.takeLast(12_000))
                }
                if (visualTimelineMemory.isNotBlank()) {
                    if (isNotEmpty()) append("\n\n")
                    append("MEMORIA VISUAL RECIENTE:\n")
                    append(selectVisualMemory(currentQuestion, visualTimelineMemory))
                }
                if (isEmpty() && multimodalMemory.isNotBlank()) {
                    append(multimodalMemory.takeLast(16_000))
                }
                append("\n\nDECISIÓN VISUAL PARA ESTA PREGUNTA: $visualReason. ")
                if (detailedVisualQuestion && currentFrameDescription.isNotBlank()) {
                    append("La descripción de cámara acaba de obtenerse con análisis visual detallado para esta pregunta. Usa nombres y texto legible del análisis para contestar de forma concreta, sin pedir aclaración sobre 'eso' o 'ahí' salvo que siga siendo realmente ambiguo. ")
                }
                if (useVisualMemory) append("Responde usando lo recordado, no la escena actual. ")
                if (needsCurrentFrame && currentFrameDescription.isBlank()) {
                    append("No se ha podido analizar la imagen actual. No presentes recuerdos como una observación actual. ")
                }
            }

            diag(
                context,
                "CEREBRAS_START",
                "question=$currentQuestion web=${webContext.isNotBlank()} visual=${currentFrameDescription.isNotBlank()} useVisualMemory=$useVisualMemory incomplete=$incompleteQuestion convChars=${conversationMemory.length} visualMemChars=${visualTimelineMemory.length}"
            )

            var answer = if (incompleteQuestion) {
                diag(context, "VOICE_CLARIFICATION", "text=$currentQuestion")
                TextResult(true, text = "No he entendido la pregunta completa. ¿Puedes repetirla?")
            } else askCerebrasWithText(
                context = context,
                apiKey = apiKey,
                userText = currentQuestion,
                visualContext = currentFrameDescription,
                multimodalMemory = memoryBeforeCurrentQuestion,
                webContext = webContext
            )

            if (!answer.success) {
                thinkingState = "REINTENTO CON CONTEXTO REDUCIDO"
                answer = askCerebrasWithText(
                    context = context,
                    apiKey = apiKey,
                    userText = currentQuestion,
                    visualContext = currentFrameDescription.take(1_000),
                    multimodalMemory = memoryBeforeCurrentQuestion,
                    webContext = webContext.take(4_000)
                )
            }

            if (!answer.success) {
                diag(context, "CEREBRAS_FAIL", answer.error.take(1_200))
                thinkingState = "ERROR: ${answer.error.take(180)}"
                responseState = "EN ESPERA"
                cerebrasBusy = false
                continue
            }

            // V35 INTERNET FALLBACK: si Cerebras reconoce que no sabe la respuesta,
            // no tiene datos suficientes o necesita información actual, buscamos
            // automáticamente en Internet y repetimos LA MISMA pregunta con Tavily.
            // Esto solo se ejecuta cuando no se hizo ya una búsqueda web y el usuario
            // no ha pedido expresamente evitar Internet.
            if (
                !incompleteQuestion &&
                !webRequested &&
                !declinesWebSearch(currentQuestion) &&
                answerRequestsWebFallback(answer.text)
            ) {
                diag(
                    context,
                    "WEB_FALLBACK_TRIGGERED",
                    "reason=assistant_uncertain query=$webQuery answer=${answer.text.take(500)}"
                )

                if (tavilyApiKey.isBlank()) {
                    diag(context, "WEB_FALLBACK_FAIL", "Falta API key de Tavily")
                } else {
                    thinkingState = "BUSCANDO EN INTERNET"
                    val fallbackWeb = searchWebWithTavily(
                        context = context,
                        apiKey = tavilyApiKey,
                        query = webQuery
                    )

                    if (fallbackWeb.success && fallbackWeb.text.isNotBlank()) {
                        webContext = fallbackWeb.text
                        diag(context, "WEB_FALLBACK_OK", webContext.take(1_200))
                        thinkingState = "PENSANDO CON INTERNET"

                        val webAnswer = askCerebrasWithText(
                            context = context,
                            apiKey = apiKey,
                            userText = currentQuestion,
                            visualContext = currentFrameDescription,
                            multimodalMemory = memoryBeforeCurrentQuestion,
                            webContext = webContext
                        )

                        if (webAnswer.success && webAnswer.text.isNotBlank()) {
                            answer = webAnswer
                            diag(context, "WEB_FALLBACK_ANSWER_OK", answer.text.take(1_200))

                            // Si incluso con Internet sigue sin saberlo,
                            // hacemos UNA segunda búsqueda afinada usando SOLO
                            // la descripción visual actual y sin memoria visual antigua.
                            if (answerStillUncertainAfterWeb(answer.text)) {
                                val refinedQuery = refinedVisualWebQuery(
                                    question = currentQuestion,
                                    currentVisual = currentFrameDescription
                                )

                                diag(
                                    context,
                                    "WEB_RETRY_REFINED_TRIGGERED",
                                    "query=${refinedQuery.take(1_200)}"
                                )

                                val refinedWeb = searchWebWithTavily(
                                    context = context,
                                    apiKey = tavilyApiKey,
                                    query = refinedQuery
                                )

                                if (refinedWeb.success && refinedWeb.text.isNotBlank()) {
                                    diag(
                                        context,
                                        "WEB_RETRY_REFINED_OK",
                                        refinedWeb.text.take(1_200)
                                    )

                                    val refinedAnswer = askCerebrasWithText(
                                        context = context,
                                        apiKey = apiKey,
                                        userText = currentQuestion,
                                        visualContext = currentFrameDescription,
                                        multimodalMemory = "",
                                        webContext = refinedWeb.text
                                    )

                                    if (refinedAnswer.success && refinedAnswer.text.isNotBlank()) {
                                        answer = refinedAnswer
                                        diag(
                                            context,
                                            "WEB_RETRY_REFINED_ANSWER_OK",
                                            answer.text.take(1_200)
                                        )
                                    } else {
                                        diag(
                                            context,
                                            "WEB_RETRY_REFINED_ANSWER_FAIL",
                                            refinedAnswer.error.take(1_200)
                                        )
                                    }
                                } else {
                                    diag(
                                        context,
                                        "WEB_RETRY_REFINED_FAIL",
                                        refinedWeb.error.take(1_200)
                                    )
                                }
                            }
                        } else {
                            diag(
                                context,
                                "WEB_FALLBACK_ANSWER_FAIL",
                                webAnswer.error.take(1_200)
                            )
                        }
                    } else {
                        diag(
                            context,
                            "WEB_FALLBACK_FAIL",
                            fallbackWeb.error.take(1_200)
                        )
                    }
                }
            }

            if (answer.text.isBlank()) {
                diag(context, "CEREBRAS_EMPTY", "success=true, text vacío")
                thinkingState = "ERROR: RESPUESTA VACÍA"
                responseState = "EN ESPERA"
                cerebrasBusy = false
                continue
            }

            diag(context, "CEREBRAS_OK", answer.text.take(1_200))
            thinkingState = "RESPUESTA RECIBIDA"

            // Solo después de obtener respuesta incorporamos el turno actual a memoria.
            val now = java.time.LocalTime.now()
                .format(java.time.format.DateTimeFormatter.ofPattern("HH:mm:ss"))
            conversationMemory = (
                    conversationMemory +
                            "\n[$now] USUARIO: " + currentQuestion.take(1_500) +
                            "\n[$now] ASISTENTE: " + answer.text.take(1_500)
                    ).takeLast(14_000)

            multimodalMemory = (
                    multimodalMemory +
                            "\n[$now] USUARIO: " + currentQuestion.take(1_500) +
                            "\n[$now] ASISTENTE: " + answer.text.take(1_500)
                    ).takeLast(18_000)

            prefs.edit()
                .putString("conversation_memory", conversationMemory)
                .putString("multimodal_memory", multimodalMemory)
                .apply()

            responseState = "GENERANDO VOZ"
            // TEMPORAL: limita la respuesta hablada para evitar saturar el XIAO
            // en respuestas largas. La respuesta completa sigue guardándose en memoria.
            val spokenText = limitSpeechText(
                cleanTextForSpeech(answer.text),
                maxChars = 320
            )

            diag(
                context,
                "TTS_START",
                "chars=${spokenText.length} engine=sherpa-onnx-embedded voice=$selectedTtsVoiceName"
            )

            val speech = synthesizeSpanishSpeechToPcm16(
                context = context,
                text = spokenText,
                targetRate = 16_000,
                preferredVoiceName = selectedTtsVoiceName
            )

            if (!speech.success || speech.data.isEmpty()) {
                diag(
                    context,
                    "TTS_FAIL",
                    "success=${speech.success} bytes=${speech.data.size} error=${speech.error.take(800)}"
                )
                responseState = "ERROR GENERANDO VOZ"
                cerebrasBusy = false
                continue
            }

            diag(context, "TTS_OK", "pcmBytes=${speech.data.size}")
            responseState = "RESPONDIENDO"

            speechInterruptRequested.set(false)
            assistantSpeakingFlag.set(true)
            currentAssistantSpeech.set(spokenText)

            val played = playPcmInterruptible(
                context = context,
                ip = xiaoIp,
                pcm = boostPcm16Volume(speech.data, ttsGainForVoice(selectedTtsVoiceName)),
                interruptRequested = speechInterruptRequested
            )

            assistantSpeakingFlag.set(false)
            currentAssistantSpeech.set("")

            when {
                played.success && played.text == "INTERRUPTED" ->
                    diag(context, "PLAYBACK_INTERRUPTED", "Interrupción solicitada")
                played.success ->
                    diag(context, "PLAYBACK_OK", played.text)
                else ->
                    diag(context, "PLAYBACK_FAIL", played.error.take(1_000))
            }

            responseState =
                when {
                    played.success && played.text == "INTERRUPTED" ->
                        "INTERRUMPIDO · ESCUCHANDO"
                    played.success ->
                        "EN ESPERA"
                    else ->
                        "ERROR: ${played.error.take(180)}"
                }

            thinkingState = "EN ESPERA"
            cerebrasBusy = false

            // La captura nunca se ha detenido. Si hubo interrupción,
            // la nueva frase ya está esperando en recognizedTextQueue.
        }
    }


    var selectedTab by remember { mutableStateOf(0) }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    icon = { Text("●") },
                    label = { Text("Control") }
                )
                NavigationBarItem(
                    selected = selectedTab == 1,
                    onClick = { selectedTab = 1 },
                    icon = { Text("AI") },
                    label = { Text("Asistente IA") }
                )
            }
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            when (selectedTab) {
                0 -> Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(
                            rememberScrollState()
                        )
                        .padding(20.dp),

                    horizontalAlignment =
                        Alignment.CenterHorizontally
                ) {


                    // =====================================================
                    // TITULO
                    // =====================================================

                    Text(
                        text = "Wearable AI",
                        fontSize = 30.sp,
                        fontWeight = FontWeight.Bold
                    )


                    Spacer(
                        Modifier.height(15.dp)
                    )


                    Text(
                        text =
                            "Estado: $connectionStatus",

                        fontWeight =
                            FontWeight.Bold
                    )


                    Spacer(
                        Modifier.height(12.dp)
                    )


                    // =====================================================
                    // IP XIAO
                    // =====================================================

                    OutlinedTextField(
                        value = xiaoIp,

                        onValueChange = {
                            xiaoIp = it.trim()
                        },

                        label = {
                            Text("IP del XIAO")
                        },

                        singleLine = true,

                        modifier =
                            Modifier.fillMaxWidth()
                    )


                    Spacer(
                        Modifier.height(20.dp)
                    )


                    // =====================================================
                    // MODO IA
                    // =====================================================

                    Card(
                        modifier =
                            Modifier.fillMaxWidth()
                    ) {

                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(18.dp),

                            verticalAlignment =
                                Alignment.CenterVertically,

                            horizontalArrangement =
                                Arrangement.SpaceBetween
                        ) {

                            Column {

                                Text(
                                    "MODO IA",
                                    fontSize = 22.sp,
                                    fontWeight =
                                        FontWeight.Bold
                                )

                                Text(
                                    if (aiMode)
                                        "Activado"
                                    else
                                        "Desactivado"
                                )
                            }


                            Switch(
                                checked = aiMode,

                                onCheckedChange = {

                                    if (
                                        it &&
                                        apiKey.isBlank()
                                    ) {

                                        appStatus =
                                            "Falta API key de Cerebras"

                                    } else {

                                        aiMode = it
                                        diag(
                                            context,
                                            if (it) "AI_MODE_ON" else "AI_MODE_OFF",
                                            "Usuario cambió Modo IA"
                                        )

                                        appStatus =
                                            if (it)
                                                "Modo IA activado"
                                            else
                                                "Modo IA desactivado"
                                    }
                                }
                            )
                        }
                    }


                    Spacer(
                        Modifier.height(15.dp)
                    )


                    Text(
                        appStatus,
                        fontWeight =
                            FontWeight.Bold
                    )

                    if (aiMode) {
                        Spacer(Modifier.height(6.dp))
                        Text(
                            text = "Contexto activo · $visualMemoryCount actualizaciones visuales",
                            fontSize = 13.sp
                        )
                    }

                    if (aiMode && geminiResult.isNotBlank()) {
                        Spacer(Modifier.height(8.dp))
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Text(
                                text = "IA: $geminiResult",
                                modifier = Modifier.padding(12.dp)
                            )
                        }
                    }


                    Spacer(
                        Modifier.height(30.dp)
                    )


                    // =====================================================
                    // PRUEBA MICROFONO
                    // =====================================================

                    Button(
                        onClick = {

                            scope.launch {

                                micResult =
                                    "Probando..."

                                val result =
                                    httpGetBytes(
                                        xiaoIp,
                                        "/mic_sample"
                                    )


                                if (
                                    result.success &&
                                    result.data.isNotEmpty()
                                ) {
                                    val recorded = ArrayList<Byte>()
                                    recorded.addAll(result.data.toList())
                                    repeat(5) {
                                        delay(40)
                                        val more = httpGetBytes(xiaoIp, "/mic_sample")
                                        if (more.success && more.data.isNotEmpty()) recorded.addAll(more.data.toList())
                                    }
                                    val pcm = recorded.toByteArray()
                                    micResult = "Grabados ${pcm.size} bytes · reproduciendo..."
                                    connectionStatus = "Conectado"
                                    playXiaoPcmOnPhone(context, pcm) { msg -> micResult = msg }

                                } else {

                                    micResult =
                                        "ERROR: ${result.error}"
                                }
                            }
                        },

                        modifier =
                            Modifier.fillMaxWidth()
                    ) {

                        Text(
                            "Probar micrófono"
                        )
                    }


                    Text(
                        "Micrófono: $micResult",

                        modifier =
                            Modifier.fillMaxWidth()
                    )


                    Spacer(
                        Modifier.height(10.dp)
                    )


                    // =====================================================
                    // PRUEBA ALTAVOZ
                    // =====================================================

                    Button(
                        onClick = {

                            scope.launch {

                                speakerResult =
                                    "Probando..."

                                val result =
                                    httpGetText(
                                        xiaoIp,
                                        "/beep"
                                    )


                                if (
                                    result.success
                                ) {

                                    speakerResult =
                                        "OK"

                                    connectionStatus =
                                        "Conectado"

                                } else {

                                    speakerResult =
                                        "ERROR: ${result.error}"
                                }
                            }
                        },

                        modifier =
                            Modifier.fillMaxWidth()
                    ) {

                        Text(
                            "Probar altavoz"
                        )
                    }


                    Text(
                        "Altavoz: $speakerResult",

                        modifier =
                            Modifier.fillMaxWidth()
                    )


                    Spacer(
                        Modifier.height(10.dp)
                    )


                    // =====================================================
                    // PRUEBA CAMARA
                    // =====================================================

                    Button(
                        onClick = {

                            scope.launch {

                                cameraResult =
                                    "Capturando..."

                                val result =
                                    httpGetBytes(
                                        xiaoIp,
                                        "/capture"
                                    )


                                if (
                                    result.success &&
                                    result.data.isNotEmpty()
                                ) {

                                    cameraResult =
                                        "OK (${result.data.size} bytes)"

                                    connectionStatus =
                                        "Conectado"

                                } else {

                                    cameraResult =
                                        "ERROR: ${result.error}"
                                }
                            }
                        },

                        modifier =
                            Modifier.fillMaxWidth()
                    ) {

                        Text(
                            "Capturar cámara"
                        )
                    }


                    Text(
                        "Cámara: $cameraResult",

                        modifier =
                            Modifier.fillMaxWidth()
                    )


                    Spacer(
                        Modifier.height(10.dp)
                    )


                    // =====================================================
                    // TEST INTEGRAL
                    // =====================================================

                    Button(
                        onClick = {

                            scope.launch {

                                appStatus =
                                    "Ejecutando test..."

                                val result =
                                    httpGetText(
                                        xiaoIp,
                                        "/selftest?beep=1"
                                    )


                                if (
                                    result.success
                                ) {

                                    connectionStatus =
                                        "Conectado"

                                    testResult =
                                        result.text

                                    appStatus =
                                        "Test terminado"

                                } else {

                                    connectionStatus =
                                        "Sin conexión"

                                    testResult =
                                        "ERROR: ${result.error}"

                                    appStatus =
                                        "Test fallido"
                                }
                            }
                        },

                        modifier =
                            Modifier.fillMaxWidth()
                    ) {

                        Text(
                            "Test integral"
                        )
                    }


                    if (
                        testResult.isNotBlank()
                    ) {

                        Spacer(
                            Modifier.height(10.dp)
                        )


                        Card(
                            modifier =
                                Modifier.fillMaxWidth()
                        ) {

                            Text(
                                testResult,

                                modifier =
                                    Modifier.padding(15.dp)
                            )
                        }
                    }


                    Spacer(
                        Modifier.height(30.dp)
                    )


                    HorizontalDivider()


                    Spacer(
                        Modifier.height(20.dp)
                    )


                    // =====================================================
                    // CONFIGURACION WIFI XIAO
                    // =====================================================

                    Text(
                        "Conexión automática XIAO",

                        fontWeight =
                            FontWeight.Bold,

                        fontSize =
                            22.sp
                    )


                    Spacer(
                        Modifier.height(12.dp)
                    )


                    OutlinedTextField(
                        value = wifiSsid,

                        onValueChange = {
                            wifiSsid = it
                            wifiPassword =
                                loadWifiPasswordSecure(
                                    context,
                                    it
                                )
                        },

                        label = {
                            Text(
                                "Nombre de red (SSID)"
                            )
                        },

                        singleLine = true,

                        modifier =
                            Modifier.fillMaxWidth()
                    )


                    Spacer(
                        Modifier.height(10.dp)
                    )


                    OutlinedTextField(
                        value = wifiPassword,

                        onValueChange = {
                            wifiPassword = it
                        },

                        label = {
                            Text(
                                "Contraseña Wi-Fi"
                            )
                        },

                        visualTransformation =
                            PasswordVisualTransformation(),

                        keyboardOptions =
                            KeyboardOptions(
                                keyboardType =
                                    KeyboardType.Password
                            ),

                        singleLine = true,

                        modifier =
                            Modifier.fillMaxWidth()
                    )


                    Spacer(
                        Modifier.height(10.dp)
                    )


                    Button(
                        onClick = {

                            if (
                                wifiSsid.isBlank()
                            ) {

                                wifiStatus =
                                    "Escribe el nombre del Wi-Fi"

                            } else {

                                wifiStatus =
                                    "Preparando Bluetooth..."


                                activity
                                    .requestBluetoothPermissions {

                                        configureXiaoWifiBle(
                                            context = context,

                                            ssid =
                                                wifiSsid,

                                            password =
                                                wifiPassword,

                                            onStatus = {
                                                wifiStatus = it
                                            },
                                            onWifiSent = {
                                                saveWifiPasswordSecure(
                                                    context,
                                                    wifiSsid,
                                                    wifiPassword
                                                )

                                                prefs.edit()
                                                    .putString("wifi_ssid", wifiSsid)
                                                    .apply()

                                                wifiStatus =
                                                    "Wi-Fi enviado. Esperando IP del XIAO por Bluetooth..."
                                            },

                                            onIpFound = { foundIp ->
                                                xiaoIp = foundIp
                                                prefs.edit()
                                                    .putString("xiao_ip", foundIp)
                                                    .apply()

                                                connectionStatus = "Conectado"
                                                wifiStatus =
                                                    "Conectado a $wifiSsid · IP $foundIp"
                                            }
                                        )
                                    }
                            }
                        },

                        modifier =
                            Modifier.fillMaxWidth()
                    ) {

                        Text(
                            "RECONECTAR XIAO AL HOTSPOT"
                        )
                    }


                    Spacer(
                        Modifier.height(8.dp)
                    )


                    Button(
                        onClick = {
                            wifiStatus = "Reiniciando conexión directa con XIAO..."
                            connectionStatus = "Reconectando"

                            activity.requestBluetoothPermissions {
                                activity.forceReconnectDirectlyToXiao(
                                    onStatus = { wifiStatus = it },
                                    onReady = {
                                        xiaoIp = XIAO_AP_IP
                                        prefs.edit()
                                            .putString("xiao_ip", XIAO_AP_IP)
                                            .apply()
                                        connectionStatus = "Conectado"
                                        wifiStatus = "Conectado directamente al XIAO · $XIAO_AP_IP"
                                    }
                                )
                            }
                        },

                        modifier =
                            Modifier.fillMaxWidth()
                    ) {
                        Text("REINICIAR CONEXIÓN XIAO")
                    }


                    Spacer(
                        Modifier.height(8.dp)
                    )


                    Text(
                        "Wi-Fi: $wifiStatus",

                        modifier =
                            Modifier.fillMaxWidth()
                    )


                    Spacer(
                        Modifier.height(30.dp)
                    )


                    HorizontalDivider()


                    Spacer(
                        Modifier.height(20.dp)
                    )


                    // =====================================================
                    // CONFIGURACION OPENAI
                    // =====================================================

                    Text(
                        "Configuración IA",

                        fontWeight =
                            FontWeight.Bold,

                        fontSize =
                            22.sp
                    )


                    Spacer(
                        Modifier.height(12.dp)
                    )


                    OutlinedTextField(
                        value = apiKey,

                        onValueChange = {
                            apiKey = it.trim()
                            prefs.edit()
                                .putString("cerebras_key", apiKey)
                                .apply()
                        },

                        label = {
                            Text(
                                "API key de Cerebras"
                            )
                        },

                        visualTransformation =
                            PasswordVisualTransformation(),

                        keyboardOptions =
                            KeyboardOptions(
                                keyboardType =
                                    KeyboardType.Password
                            ),

                        singleLine = true,

                        modifier =
                            Modifier.fillMaxWidth()
                    )


                    Spacer(Modifier.height(10.dp))

                    OutlinedTextField(
                        value = tavilyApiKey,

                        onValueChange = {
                            tavilyApiKey = it.trim()
                            prefs.edit()
                                .putString("tavily_key", tavilyApiKey)
                                .apply()
                        },

                        label = {
                            Text("API key de Tavily (búsqueda web)")
                        },

                        visualTransformation =
                            PasswordVisualTransformation(),

                        keyboardOptions =
                            KeyboardOptions(
                                keyboardType =
                                    KeyboardType.Password
                            ),

                        singleLine = true,

                        modifier =
                            Modifier.fillMaxWidth()
                    )

                    Spacer(Modifier.height(10.dp))

                    Button(
                        onClick = {
                            if (tavilyApiKey.isBlank()) {
                                geminiResult = "Introduce la API key de Tavily"
                            } else {
                                scope.launch {
                                    geminiResult = "Probando búsqueda web..."
                                    val result = searchWebWithTavily(
                                        context = context,
                                        apiKey = tavilyApiKey,
                                        query = "OpenAI noticias de hoy"
                                    )
                                    geminiResult =
                                        if (result.success)
                                            "Web OK: ${result.text.take(500)}"
                                        else
                                            "Web ERROR: ${result.error.take(500)}"
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Probar búsqueda web")
                    }

                    Spacer(Modifier.height(10.dp))

                    Button(
                        onClick = {
                            if (apiKey.isBlank()) {
                                geminiResult = "Introduce la API key de Cerebras"
                            } else {
                                scope.launch {
                                    geminiResult = "Probando Cerebras..."
                                    val result = testGeminiApi(apiKey)
                                    geminiResult = if (result.success)
                                        "Cerebras OK: ${result.text}"
                                    else
                                        "Cerebras ERROR: ${result.error}"
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("Probar Cerebras") }

                    if (geminiResult.isNotBlank()) {
                        Spacer(Modifier.height(8.dp))
                        Text(geminiResult, modifier = Modifier.fillMaxWidth())
                    }

                    Spacer(Modifier.height(10.dp))

                    Button(
                        onClick = {

                            prefs.edit()
                                .putString(
                                    "cerebras_key",
                                    apiKey
                                )
                                .putString(
                                    "xiao_ip",
                                    xiaoIp
                                )
                                .putString(
                                    "wifi_ssid",
                                    wifiSsid
                                )
                                .putString(
                                    "tavily_key",
                                    tavilyApiKey
                                )
                                .apply()


                            appStatus =
                                "Configuración guardada"
                        },

                        modifier =
                            Modifier.fillMaxWidth()
                    ) {

                        Text(
                            "Guardar configuración"
                        )
                    }


                    Spacer(
                        Modifier.height(20.dp)
                    )


                    Text(
                        "Firmware XIAO: 1.4.10-BASE-BUENA-MIC-ESP-I2S"
                    )
                    Text("App: V34-SHERPA-NO-BLOQUEANTE")


                    Spacer(
                        Modifier.height(40.dp)
                    )
                }

                1 -> Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text("Asistente IA", fontSize = 30.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(10.dp))
                    Text("Micrófono XIAO → transcripción → Cerebras → altavoz XIAO", modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(16.dp))

                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text("Estados reales", fontWeight = FontWeight.Bold)
                            Text("Captura: $captureState")
                            Text("Transcripción: $transcriptionState")
                            Text("Cerebras: $thinkingState")
                            Text("Respuesta: $responseState")
                            Text("Cola de voz: $queuedPhrases / 12")
                            Text("Cola Cerebras: $queuedTexts / 12")
                            if (droppedPhrases > 0) Text("Frases de audio descartadas: $droppedPhrases")
                            if (droppedTexts > 0) Text("Textos descartados antes de Cerebras: $droppedTexts")
                            if (lastTranscript.isNotBlank()) Text("Último texto válido: ${lastTranscript.take(220)}")
                            Spacer(Modifier.height(6.dp))
                            Text("XIAO: $connectionStatus · IP $xiaoIp")
                            if (visualMemoryCount > 0) Text("Contexto: $visualMemoryCount actualizaciones visuales")
                        }
                    }

                    Spacer(Modifier.height(16.dp))

                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text("Diagnóstico", fontWeight = FontWeight.Bold)
                            Text(
                                "Registra audio, Vosk, colas, visión, web, Cerebras, TTS, reproducción e interrupciones.",
                                fontSize = 12.sp
                            )

                            Spacer(Modifier.height(10.dp))

                            Button(
                                onClick = {
                                    val report = WearableDiag.read(context)
                                    val clipboard =
                                        context.getSystemService(Context.CLIPBOARD_SERVICE)
                                                as ClipboardManager
                                    clipboard.setPrimaryClip(
                                        ClipData.newPlainText(
                                            "Wearable AI diagnostic",
                                            report
                                        )
                                    )
                                    diagnosticUiStatus =
                                        "Copiado: ${report.length} caracteres"
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text("COPIAR INFORME")
                            }

                            Spacer(Modifier.height(8.dp))

                            Button(
                                onClick = {
                                    WearableDiag.clear(context)
                                    diag(
                                        context,
                                        "SESSION_START",
                                        "Nueva sesión de diagnóstico"
                                    )
                                    diagnosticUiStatus = "Informe borrado"
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text("BORRAR INFORME")
                            }

                            Spacer(Modifier.height(6.dp))
                            Text(diagnosticUiStatus, fontSize = 12.sp)
                        }
                    }

                    Spacer(Modifier.height(16.dp))

                    // Vista en directo de la última captura recibida de la cámara XIAO.
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            Text("Cámara XIAO", fontWeight = FontWeight.Bold)
                            Spacer(Modifier.height(8.dp))
                            val previewBytes = latestCameraJpeg
                            val previewBitmap = remember(previewBytes) {
                                previewBytes?.let {
                                    android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size)
                                }
                            }
                            if (previewBitmap != null) {
                                Image(
                                    bitmap = previewBitmap.asImageBitmap(),
                                    contentDescription = "Imagen actual de la cámara XIAO",
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(220.dp),
                                    contentScale = ContentScale.Fit
                                )
                            } else {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(160.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text("Esperando imagen de la cámara...")
                                }
                            }
                        }
                    }

                    Spacer(Modifier.height(16.dp))

                    Card(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text("MODO IA", fontWeight = FontWeight.Bold, fontSize = 20.sp)
                                Text(if (aiMode) "Escuchando por el XIAO" else "Desactivado")
                            }
                            Switch(
                                checked = aiMode,
                                onCheckedChange = { enabled ->
                                    if (enabled && apiKey.isBlank()) {
                                        appStatus = "Falta API key de Cerebras"
                                    } else {
                                        aiMode = enabled
                                        appStatus = if (enabled) "Modo IA activado" else "Modo IA desactivado"
                                    }
                                }
                            )
                        }
                    }

                    Spacer(Modifier.height(16.dp))

                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text("Voz del asistente", fontWeight = FontWeight.Bold)
                            Spacer(Modifier.height(6.dp))

                            val currentVoiceLabel =
                                availableSpanishVoices
                                    .firstOrNull { it.name == selectedTtsVoiceName }
                                    ?.label
                                    ?: "Android TTS · voz española del sistema"

                            Text(currentVoiceLabel, modifier = Modifier.fillMaxWidth())
                            Spacer(Modifier.height(10.dp))

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Button(
                                    onClick = {
                                        val names = availableSpanishVoices.map { it.name }
                                        if (names.isNotEmpty()) {
                                            val current = names.indexOf(selectedTtsVoiceName).let {
                                                if (it < 0) 0 else it
                                            }
                                            val next = if (current <= 0) names.lastIndex else current - 1
                                            selectedTtsVoiceName = names[next]
                                            prefs.edit()
                                                .putString("tts_voice_name", selectedTtsVoiceName)
                                                .apply()
                                        }
                                    },
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Text("ANTERIOR")
                                }

                                Button(
                                    onClick = {
                                        val names = availableSpanishVoices.map { it.name }
                                        if (names.isNotEmpty()) {
                                            val current = names.indexOf(selectedTtsVoiceName).let {
                                                if (it < 0) 0 else it
                                            }
                                            val next = if (current >= names.lastIndex) 0 else current + 1
                                            selectedTtsVoiceName = names[next]
                                            prefs.edit()
                                                .putString("tts_voice_name", selectedTtsVoiceName)
                                                .apply()
                                        }
                                    },
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Text("SIGUIENTE")
                                }
                            }

                            Spacer(Modifier.height(8.dp))

                            Button(
                                onClick = {
                                    scope.launch {
                                        appStatus = "Probando voz seleccionada..."
                                        val demo = synthesizeSpanishSpeechToPcm16(
                                            context = context,
                                            text = "Hola. Esta es la voz seleccionada para tu Wearable AI.",
                                            targetRate = 16_000,
                                            preferredVoiceName = selectedTtsVoiceName
                                        )

                                        if (!demo.success || demo.data.isEmpty()) {
                                            appStatus = "Error de voz: ${demo.error}"
                                        } else {
                                            val played = httpPostBytes(
                                                ip = xiaoIp,
                                                endpoint = "/play_audio",
                                                data = boostPcm16Volume(demo.data, ttsGainForVoice(selectedTtsVoiceName)),
                                                contentType = "application/octet-stream"
                                            )
                                            appStatus =
                                                if (played.success) "Voz probada correctamente"
                                                else "Error reproduciendo voz: ${played.error}"
                                        }
                                    }
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text("PROBAR VOZ")
                            }

                            if (availableSpanishVoices.isEmpty()) {
                                Spacer(Modifier.height(6.dp))
                                Text(
                                    "Android no ha listado voces españolas adicionales. Se usará la voz automática.",
                                    fontSize = 12.sp
                                )
                            }
                        }
                    }

                    Spacer(Modifier.height(16.dp))

                    Button(
                        onClick = {
                            scope.launch {
                                appStatus = "Habla ahora: grabando 3 segundos desde el XIAO..."
                                val recorded = ArrayList<Byte>()
                                repeat(6) {
                                    val r = httpGetBytes(xiaoIp, "/mic_sample")
                                    if (r.success && r.data.isNotEmpty()) recorded.addAll(r.data.toList())
                                    delay(40)
                                }
                                if (recorded.isNotEmpty()) {
                                    val pcm = recorded.toByteArray()
                                    micResult = "Grabados ${pcm.size} bytes · reproduciendo..."
                                    playXiaoPcmOnPhone(context, pcm) { msg ->
                                        micResult = msg
                                        appStatus = msg
                                    }
                                } else {
                                    micResult = "ERROR: no llegó audio"
                                    appStatus = "Micrófono XIAO no disponible"
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("PROBAR MICRÓFONO XIAO") }

                    Spacer(Modifier.height(10.dp))

                    Button(
                        onClick = {
                            playLastVoskInput(context) { msg ->
                                micResult = msg
                                appStatus = msg
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("ESCUCHAR ÚLTIMA FRASE VOSK") }

                    Spacer(Modifier.height(10.dp))

                    Button(
                        onClick = {
                            scope.launch {
                                appStatus = "Asistente: capturando imagen..."
                                val r = httpGetBytes(xiaoIp, "/capture")
                                if (r.success && r.data.isNotEmpty()) {
                                    val correctedJpeg = unmirrorJpeg(r.data)
                                    latestCameraJpeg = correctedJpeg
                                    cameraResult = "OK (${correctedJpeg.size} bytes)"
                                    appStatus = "VISIÓN: enviando una foto a Cerebras..."

                                    diag(context, "VISION_USED_CURRENT_FRAME", "reason=explicit_manual_vision_button jpegBytes=${correctedJpeg.size}")
                                    val vision = updateCerebrasVisualContext(
                                        context = context,
                                        apiKey = apiKey,
                                        jpeg = correctedJpeg,
                                        previousContext = ""
                                    )

                                    if (vision.success && vision.text.isNotBlank()) {
                                        visualContext = compactVisualText(vision.text)
                                        visualMemoryCount++
                                        val stamp = java.time.LocalTime.now().format(java.time.format.DateTimeFormatter.ofPattern("HH:mm:ss"))
                                        val updated = appendVisualObservation(visualTimelineMemory, vision.text, stamp)
                                        val changed = updated != visualTimelineMemory
                                        visualTimelineMemory = updated
                                        diag(context, "VISUAL_MEMORY_UPDATED", "reason=manual_vision_useful_observation changed=$changed chars=${updated.length}")
                                        prefs.edit().putString("visual_context", visualContext)
                                            .putString("visual_timeline_memory", visualTimelineMemory).apply()
                                        appStatus = "VISIÓN OK: ${vision.text.take(700)}"
                                    } else {
                                        appStatus = "VISIÓN ERROR: ${vision.error.take(700)}"
                                    }
                                } else {
                                    cameraResult = "ERROR: ${r.error}"
                                    appStatus = "Cámara XIAO no disponible"
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("PROBAR CÁMARA XIAO") }

                    Spacer(Modifier.height(10.dp))

                    Button(
                        onClick = {
                            scope.launch {
                                val r = httpGetText(xiaoIp, "/beep")
                                speakerResult = if (r.success) "OK" else "ERROR: ${r.error}"
                                appStatus = if (r.success) "Altavoz XIAO preparado" else "Altavoz XIAO no disponible"
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("PROBAR ALTAVOZ XIAO") }

                    Spacer(Modifier.height(16.dp))
                    Text("Micrófono: $micResult", modifier = Modifier.fillMaxWidth())
                    Text("Cámara: $cameraResult", modifier = Modifier.fillMaxWidth())
                    Text("Altavoz: $speakerResult", modifier = Modifier.fillMaxWidth())

                    if (geminiResult.isNotBlank()) {
                        Spacer(Modifier.height(16.dp))
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Text("IA: $geminiResult", modifier = Modifier.padding(14.dp))
                        }
                    }

                    Spacer(Modifier.height(40.dp))
                }
            }
        }
    }
}


// =====================================================
// HOTSPOT LOCAL AUTOMATICO DEL MOVIL
// =====================================================
@SuppressLint("MissingPermission")
fun startWearableHotspot(
    context: Context,
    onStatus: (String) -> Unit,
    onReady: (ssid: String, password: String) -> Unit
) {
    val mainHandler = Handler(Looper.getMainLooper())
    fun ui(message: String) = mainHandler.post { onStatus(message) }

    val wifiManager =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

    // Si ya existe uno creado por esta app, lo cerramos antes de crear el nuevo.
    try {
        activeHotspotReservation?.close()
    } catch (_: Exception) {
    }
    activeHotspotReservation = null

    ui("Creando hotspot automático del móvil...")

    try {
        wifiManager.startLocalOnlyHotspot(
            object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                    activeHotspotReservation = reservation

                    val ssid: String
                    val password: String

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        val config = reservation.softApConfiguration
                        ssid = config.ssid ?: ""
                        password = config.passphrase ?: ""
                    } else {
                        @Suppress("DEPRECATION")
                        val config: WifiConfiguration? = reservation.wifiConfiguration
                        @Suppress("DEPRECATION")
                        ssid = config?.SSID?.removeSurrounding("\"") ?: ""
                        @Suppress("DEPRECATION")
                        password = config?.preSharedKey?.removeSurrounding("\"") ?: ""
                    }

                    if (ssid.isBlank()) {
                        ui("Android creó el hotspot, pero no entregó el SSID")
                        return
                    }

                    ui("Hotspot creado. Buscando XIAO por Bluetooth...")
                    mainHandler.post { onReady(ssid, password) }
                }

                override fun onStopped() {
                    activeHotspotReservation = null
                    ui("Hotspot detenido")
                }

                override fun onFailed(reason: Int) {
                    activeHotspotReservation = null
                    val detail = when (reason) {
                        WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL -> "sin canal Wi-Fi disponible"
                        WifiManager.LocalOnlyHotspotCallback.ERROR_GENERIC -> "error interno de Android"
                        WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE -> "modo Wi-Fi incompatible"
                        WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED -> "hotspot no permitido por el sistema"
                        else -> "código $reason"
                    }
                    ui("No se pudo crear el hotspot: $detail")
                }
            },
            mainHandler
        )
    } catch (e: SecurityException) {
        ui("Falta permiso para crear el hotspot")
    } catch (e: Exception) {
        ui("Error creando hotspot: ${e.message ?: e.javaClass.simpleName}")
    }
}


// =====================================================
// BUSCAR XIAO POR BLUETOOTH
// =====================================================

@SuppressLint("MissingPermission")
fun configureXiaoWifiBle(
    context: Context,
    ssid: String,
    password: String,
    onStatus: (String) -> Unit,
    onWifiSent: () -> Unit,
    onIpFound: (String) -> Unit
) {
    val mainHandler = Handler(Looper.getMainLooper())

    fun status(message: String) {
        mainHandler.post { onStatus(message) }
    }

    val bluetoothManager =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager

    val adapter = bluetoothManager.adapter

    if (adapter == null) {
        status("Este móvil no tiene Bluetooth")
        return
    }

    if (!adapter.isEnabled) {
        status("Activa Bluetooth en el móvil")
        return
    }

    val scanner = adapter.bluetoothLeScanner

    if (scanner == null) {
        status("No se puede iniciar Bluetooth")
        return
    }

    // Cierra cualquier escaneo anterior que haya quedado registrado.
    try {
        val oldScanner = activeBleScanner
        val oldCallback = activeBleScanCallback
        if (oldScanner != null && oldCallback != null) {
            oldScanner.stopScan(oldCallback)
        }
    } catch (_: Exception) {
    }
    activeBleScanner = null
    activeBleScanCallback = null

    var finished = false

    // Diagnóstico acumulado: no perdemos los resultados al terminar.
    val bleDevices = linkedMapOf<String, String>()
    var bleResultCount = 0

    lateinit var callback: ScanCallback

    val timeout = Runnable {
        if (!finished) {
            finished = true
            try {
                scanner.stopScan(callback)
            } catch (_: Exception) {
            }
            val summary =
                if (bleDevices.isEmpty()) {
                    "Fin BLE: 0 dispositivos recibidos."
                } else {
                    "Fin BLE: ${bleDevices.size} dispositivos (${bleResultCount} anuncios). " +
                            bleDevices.values.joinToString(" | ")
                }
            status(summary)
        }
    }

    callback = object : ScanCallback() {

        override fun onScanResult(
            callbackType: Int,
            result: ScanResult
        ) {
            if (finished) return

            val device = result.device

            // Primero usamos el nombre incluido en el anuncio BLE.
            // Si no viene ahí, usamos device.name.
            val advertisedName = result.scanRecord?.deviceName ?: ""
            val deviceName = try {
                device.name ?: ""
            } catch (_: SecurityException) {
                ""
            }

            val name =
                if (advertisedName.isNotBlank()) advertisedName else deviceName

            // DIAGNÓSTICO: guardar TODOS los BLE recibidos durante el escaneo.
            val shownName = if (name.isBlank()) "(sin nombre)" else name
            val address = try { device.address } catch (_: SecurityException) { "?" }
            bleResultCount++
            bleDevices[address] = "$shownName ${result.rssi}dBm"

            // Durante el escaneo mostramos el contador; al final se muestra la lista completa.
            status("Escaneando BLE... ${bleDevices.size} dispositivos recibidos")

            val normalized =
                name.uppercase()
                    .replace("-", "")
                    .replace("_", "")
                    .replace("/", "")
                    .replace(" ", "")

            val isXiao =
                normalized.contains("XIAO") &&
                        normalized.contains("SMARTGLASSES")

            if (isXiao) {
                finished = true
                mainHandler.removeCallbacks(timeout)

                try {
                    scanner.stopScan(this)
                } catch (_: Exception) {
                }

                status("XIAO encontrado ($name). Conectando...")

                connectAndSendWifi(
                    context = context,
                    device = device,
                    ssid = ssid,
                    password = password,
                    onStatus = { status(it) },
                    onWifiSent = {
                        mainHandler.post {
                            onWifiSent()
                        }
                    },
                    onIpFound = { ip ->
                        mainHandler.post {
                            onIpFound(ip)
                        }
                    }
                )
            }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            for (result in results) {
                onScanResult(0, result)
                if (finished) break
            }
        }

        override fun onScanFailed(errorCode: Int) {
            if (finished) return
            finished = true
            mainHandler.removeCallbacks(timeout)

            val detail = when (errorCode) {
                ScanCallback.SCAN_FAILED_ALREADY_STARTED ->
                    "escaneo ya iniciado"
                ScanCallback.SCAN_FAILED_APPLICATION_REGISTRATION_FAILED ->
                    "Android no pudo registrar el escáner BLE"
                ScanCallback.SCAN_FAILED_INTERNAL_ERROR ->
                    "error interno Bluetooth"
                ScanCallback.SCAN_FAILED_FEATURE_UNSUPPORTED ->
                    "escaneo BLE no compatible"
                else ->
                    "código $errorCode"
            }

            activeBleScanner = null
            activeBleScanCallback = null
            status("Error Bluetooth: $detail")
        }
    }

    activeBleScanner = scanner
    activeBleScanCallback = callback

    status("Buscando XIAO-SmartGlasses...")

    // Asegura que este intento termina y libera el escáner.
    mainHandler.postDelayed(timeout, 15_000)

    try {
        scanner.startScan(callback)
    } catch (e: Exception) {
        finished = true
        mainHandler.removeCallbacks(timeout)
        status("No se pudo iniciar BLE: ${e.message ?: e.javaClass.simpleName}")
    }
}


// =====================================================
// CONECTAR BLE Y ENVIAR WIFI
// =====================================================

@SuppressLint("MissingPermission")
fun connectAndSendWifi(
    context: Context,
    device: BluetoothDevice,
    ssid: String,
    password: String,
    onStatus: (String) -> Unit,
    onWifiSent: () -> Unit,
    onIpFound: (String) -> Unit
) {
    val mainHandler = Handler(Looper.getMainLooper())
    fun ui(message: String) = mainHandler.post { onStatus(message) }

    val wifiJson = JSONObject()
        .put("ssid", ssid)
        .put("password", password)
        .toString()

    device.connectGatt(context, false, object : BluetoothGattCallback() {
        private var discoveryStarted = false
        private var statusChar: BluetoothGattCharacteristic? = null
        private var ipDelivered = false
        private var attempts = 0
        private val handler = Handler(Looper.getMainLooper())

        private fun parseIp(data: ByteArray): String? = try {
            val ip = JSONObject(data.toString(Charsets.UTF_8))
                .optString("sta_ip", "").trim()
            if (ip.isNotBlank() && ip != "0.0.0.0" && ip != "192.168.4.1") ip else null
        } catch (_: Exception) { null }

        private fun finish(gatt: BluetoothGatt, ip: String) {
            if (ipDelivered) return
            ipDelivered = true
            handler.removeCallbacksAndMessages(null)
            mainHandler.post { onIpFound(ip) }
            gatt.disconnect()
        }

        private fun readAgain(gatt: BluetoothGatt) {
            if (ipDelivered) return
            if (attempts >= 20) {
                ui("Wi-Fi enviado, pero el XIAO no devolvió IP por Bluetooth")
                gatt.disconnect()
                return
            }
            handler.postDelayed({
                val c = statusChar
                if (c == null) {
                    ui("No encuentro el canal de estado del XIAO")
                    gatt.disconnect()
                } else {
                    attempts++
                    if (!gatt.readCharacteristic(c)) readAgain(gatt)
                }
            }, 1500)
        }

        private fun sendWifi(gatt: BluetoothGatt, c: BluetoothGattCharacteristic) {
            val data = wifiJson.toByteArray(Charsets.UTF_8)
            ui("Enviando Wi-Fi al XIAO...")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val r = gatt.writeCharacteristic(
                    c, data, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                )
                if (r != BluetoothStatusCodes.SUCCESS) {
                    ui("No se pudo enviar: $r")
                    gatt.disconnect()
                }
            } else {
                @Suppress("DEPRECATION")
                c.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                @Suppress("DEPRECATION")
                c.value = data
                @Suppress("DEPRECATION")
                if (!gatt.writeCharacteristic(c)) {
                    ui("No se pudo iniciar el envío")
                    gatt.disconnect()
                }
            }
        }

        override fun onConnectionStateChange(
            gatt: BluetoothGatt, status: Int, newState: Int
        ) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                handler.removeCallbacksAndMessages(null)
                try { gatt.disconnect() } catch (_: Exception) {}
                gatt.close()

                // En algunos Samsung/Android el GATT puede caer justo cuando el
                // ESP32 cambia de estado Wi-Fi. No presentamos el código GATT
                // como si fuera un error de contraseña/red.
                if (!ipDelivered) {
                    ui("Bluetooth se desconectó. Reintentando conexión con el XIAO...")
                    mainHandler.postDelayed({
                        configureXiaoWifiBle(
                            context = context,
                            ssid = ssid,
                            password = password,
                            onStatus = onStatus,
                            onWifiSent = onWifiSent,
                            onIpFound = onIpFound
                        )
                    }, 1800)
                }
                return
            }
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                ui("Bluetooth conectado")
                if (!gatt.requestMtu(247)) {
                    discoveryStarted = true
                    gatt.discoverServices()
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                handler.removeCallbacksAndMessages(null)
                gatt.close()
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            if (!discoveryStarted) {
                discoveryStarted = true
                gatt.discoverServices()
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                ui("Error leyendo servicios: $status")
                gatt.disconnect()
                return
            }
            val service = gatt.getService(XIAO_SERVICE_UUID)
            val wifiChar = service?.getCharacteristic(XIAO_WIFI_CHAR_UUID)
            statusChar = service?.getCharacteristic(XIAO_STATUS_CHAR_UUID)

            if (wifiChar == null || statusChar == null) {
                ui("Falta un canal BLE del XIAO")
                gatt.disconnect()
                return
            }
            sendWifi(gatt, wifiChar)
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            if (characteristic.uuid == XIAO_WIFI_CHAR_UUID &&
                status == BluetoothGatt.GATT_SUCCESS) {
                ui("Wi-Fi enviado. Esperando IP por Bluetooth...")
                mainHandler.post { onWifiSent() }
                readAgain(gatt)
            } else {
                ui("Error enviando Wi-Fi: $status")
                gatt.disconnect()
            }
        }

        @Deprecated("Deprecated in Android")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            if (characteristic.uuid == XIAO_STATUS_CHAR_UUID &&
                status == BluetoothGatt.GATT_SUCCESS) {
                @Suppress("DEPRECATION")
                val ip = parseIp(characteristic.value ?: ByteArray(0))
                if (ip != null) finish(gatt, ip) else readAgain(gatt)
            } else readAgain(gatt)
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int
        ) {
            if (characteristic.uuid == XIAO_STATUS_CHAR_UUID &&
                status == BluetoothGatt.GATT_SUCCESS) {
                val ip = parseIp(value)
                if (ip != null) finish(gatt, ip) else readAgain(gatt)
            } else readAgain(gatt)
        }
    })
}


// =====================================================
// CONTRASEÑAS WI-FI CIFRADAS (ANDROID KEYSTORE)
// =====================================================

private const val WIFI_KEY_ALIAS = "wearable_ai_wifi_key"
private const val WIFI_SECURE_PREFS = "wearable_ai_wifi_secure"

private fun getOrCreateWifiSecretKey(): SecretKey {
    val keyStore = KeyStore.getInstance("AndroidKeyStore").apply {
        load(null)
    }

    val existing = keyStore.getKey(WIFI_KEY_ALIAS, null)
    if (existing is SecretKey) return existing

    val generator = KeyGenerator.getInstance(
        KeyProperties.KEY_ALGORITHM_AES,
        "AndroidKeyStore"
    )

    generator.init(
        KeyGenParameterSpec.Builder(
            WIFI_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or
                    KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(
                KeyProperties.ENCRYPTION_PADDING_NONE
            )
            .build()
    )

    return generator.generateKey()
}

private fun wifiPreferenceKey(ssid: String): String =
    Base64.encodeToString(
        ssid.trim().toByteArray(Charsets.UTF_8),
        Base64.NO_WRAP or Base64.URL_SAFE
    )

fun saveWifiPasswordSecure(
    context: Context,
    ssid: String,
    password: String
) {
    if (ssid.isBlank()) return

    try {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            getOrCreateWifiSecretKey()
        )

        val encrypted =
            cipher.doFinal(
                password.toByteArray(Charsets.UTF_8)
            )

        val iv =
            Base64.encodeToString(
                cipher.iv,
                Base64.NO_WRAP
            )

        val data =
            Base64.encodeToString(
                encrypted,
                Base64.NO_WRAP
            )

        context.getSharedPreferences(
            WIFI_SECURE_PREFS,
            Context.MODE_PRIVATE
        ).edit()
            .putString(
                wifiPreferenceKey(ssid),
                "$iv:$data"
            )
            .apply()

    } catch (_: Exception) {
        // Si Android Keystore falla, no guardamos la contraseña
        // en texto plano.
    }
}

fun loadWifiPasswordSecure(
    context: Context,
    ssid: String
): String {
    if (ssid.isBlank()) return ""

    return try {
        val saved =
            context.getSharedPreferences(
                WIFI_SECURE_PREFS,
                Context.MODE_PRIVATE
            ).getString(
                wifiPreferenceKey(ssid),
                null
            ) ?: return ""

        val parts = saved.split(":", limit = 2)
        if (parts.size != 2) return ""

        val iv =
            Base64.decode(
                parts[0],
                Base64.NO_WRAP
            )

        val encrypted =
            Base64.decode(
                parts[1],
                Base64.NO_WRAP
            )

        val cipher =
            Cipher.getInstance("AES/GCM/NoPadding")

        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateWifiSecretKey(),
            GCMParameterSpec(128, iv)
        )

        String(
            cipher.doFinal(encrypted),
            Charsets.UTF_8
        )

    } catch (_: Exception) {
        ""
    }
}


// =====================================================
// DESCUBRIR AUTOMÁTICAMENTE LA IP DEL XIAO EN LA RED LOCAL
// =====================================================

private fun getPhoneWifiLanIp(context: Context): String? {
    return try {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        // IMPORTANTE: buscamos expresamente la interfaz Wi-Fi.
        // No usamos la primera IP privada del teléfono porque puede ser 5G, VPN, etc.
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) continue

            val props = cm.getLinkProperties(network) ?: continue
            for (linkAddress in props.linkAddresses) {
                val address = linkAddress.address
                if (address is Inet4Address &&
                    !address.isLoopbackAddress &&
                    address.isSiteLocalAddress
                ) {
                    return address.hostAddress
                }
            }
        }

        null
    } catch (_: Exception) {
        null
    }
}


private fun looksLikeXiaoStatus(text: String): Boolean {
    val value = text.lowercase()

    return (
            value.contains("\"fw\"") &&
                    (
                            value.contains("pdm-fix") ||
                                    value.contains("wifi-fix") ||
                                    value.contains("\"camera\"") ||
                                    value.contains("\"microphone\"") ||
                                    value.contains("\"speaker\"") ||
                                    value.contains("\"sta_ip\"")
                            )
            )
}


suspend fun discoverXiaoIpByLan(
    context: Context,
    preferredIp: String? = null
): String? =
    withContext(Dispatchers.IO) {

        // 1) Primero probamos SIEMPRE la última IP guardada.
        // Si sigue siendo válida, la conexión es prácticamente inmediata.
        if (!preferredIp.isNullOrBlank() && preferredIp != "192.168.4.1") {
            val saved = httpGetTextFastSync(preferredIp, "/status")
            if (saved.success && looksLikeXiaoStatus(saved.text)) {
                return@withContext preferredIp
            }
        }

        val phoneIp = getPhoneWifiLanIp(context) ?: return@withContext null
        val parts = phoneIp.split(".")
        if (parts.size != 4) return@withContext null

        val prefix = "${parts[0]}.${parts[1]}.${parts[2]}"
        val phoneHost = parts[3].toIntOrNull() ?: return@withContext null

        fun probe(ip: String): Boolean {
            if (ip == phoneIp) return false
            val status = httpGetTextFastSync(ip, "/status")
            return status.success && looksLikeXiaoStatus(status.text)
        }

        // 2) Si cambió la IP, probamos primero los vecinos del móvil.
        // Evitamos IPs fijas antiguas como .141.
        for (distance in 1..35) {
            val up = phoneHost + distance
            val down = phoneHost - distance

            if (up in 1..254) {
                val ip = "$prefix.$up"
                if (probe(ip)) return@withContext ip
            }

            if (down in 1..254) {
                val ip = "$prefix.$down"
                if (probe(ip)) return@withContext ip
            }
        }

        // 3) Último recurso: recorremos una sola vez el resto de la LAN.
        for (host in 1..254) {
            val ip = "$prefix.$host"
            if (ip == phoneIp || ip == preferredIp) continue
            if (probe(ip)) return@withContext ip
        }

        null
    }


// =====================================================
// HTTP RÁPIDO PARA DESCUBRIMIENTO DE IP
// =====================================================

private fun httpGetTextFastSync(
    ip: String,
    endpoint: String
): TextResult {
    var connection: HttpURLConnection? = null

    return try {
        val url = URL("http://${ip.trim()}$endpoint")
        connection = url.openConnection() as HttpURLConnection
        connection.requestMethod = "GET"
        connection.connectTimeout = 450
        connection.readTimeout = 700
        connection.useCaches = false
        connection.connect()

        val code = connection.responseCode
        if (code in 200..299) {
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            TextResult(success = true, text = body)
        } else {
            TextResult(success = false, error = "HTTP $code")
        }
    } catch (e: Exception) {
        TextResult(
            success = false,
            error = e.message ?: e.javaClass.simpleName
        )
    } finally {
        connection?.disconnect()
    }
}


// =====================================================
// MODO IA - DETECCION DE VOZ EN PCM 16-BIT / 16 KHZ
// =====================================================
private fun pcmRms(pcm: ByteArray): Double {
    if (pcm.size < 4) return 0.0

    var sum = 0.0
    var count = 0
    var i = 0

    while (i + 1 < pcm.size) {
        val lo = pcm[i].toInt() and 0xFF
        val hi = pcm[i + 1].toInt()
        val sample = ((hi shl 8) or lo).toShort().toInt()
        sum += sample.toDouble() * sample.toDouble()
        count++
        i += 2
    }

    return if (count == 0) 0.0 else kotlin.math.sqrt(sum / count)
}

private data class PcmAcStats(
    val rms: Double,
    val peak: Double
)

private fun pcmAcStats(pcm: ByteArray): PcmAcStats {
    if (pcm.size < 4) return PcmAcStats(0.0, 0.0)

    var sum = 0.0
    var count = 0
    var i = 0

    while (i + 1 < pcm.size) {
        val lo = pcm[i].toInt() and 0xFF
        val hi = pcm[i + 1].toInt()
        val sample = ((hi shl 8) or lo).toShort().toInt()
        sum += sample
        count++
        i += 2
    }

    if (count == 0) return PcmAcStats(0.0, 0.0)

    val dc = sum / count
    var sumSq = 0.0
    var peak = 0.0
    i = 0

    while (i + 1 < pcm.size) {
        val lo = pcm[i].toInt() and 0xFF
        val hi = pcm[i + 1].toInt()
        val sample = ((hi shl 8) or lo).toShort().toInt()
        val ac = kotlin.math.abs(sample - dc)

        sumSq += ac * ac
        if (ac > peak) peak = ac
        i += 2
    }

    val rms = kotlin.math.sqrt(sumSq / count)
    return PcmAcStats(rms, peak)
}


private fun pcmContainsVoice(pcm: ByteArray): Boolean {
    // El micrófono del XIAO tiene un offset DC cercano a +1470.
    // Medimos la componente AC para que el offset no se confunda con voz.
    val stats = pcmAcStats(pcm)

    // V34: mantenemos sensibilidad para voz baja y trasladamos el filtro de ruido
    // a la CONTINUIDAD temporal. Un frame moderado puede ser voz, pero no abre
    // una frase por sí solo.
    return stats.rms > 48.0 && stats.peak > 230.0
}



// =====================================================
// GEMINI - ACTUALIZAR MEMORIA VISUAL EN SILENCIO
// =====================================================
suspend fun updateCerebrasVisualContext(
    context: Context,
    apiKey: String,
    jpeg: ByteArray,
    previousContext: String,
    detailedRequest: Boolean = false,
    userQuestion: String = ""
): TextResult = withContext(Dispatchers.IO) {
    var connection: HttpURLConnection? = null
    try {
        if (apiKey.isBlank()) {
            return@withContext TextResult(false, error = "Falta API key de Cerebras")
        }
        if (jpeg.isEmpty()) {
            return@withContext TextResult(false, error = "Imagen vacía")
        }

        val url = URL("https://api.cerebras.ai/v1/chat/completions")

        // La visión debe salir por una red con Internet, nunca por el AP del XIAO.
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val internetNetwork = cm.allNetworks.firstOrNull { network ->
            if (network == activeXiaoNetwork) return@firstOrNull false
            val caps = cm.getNetworkCapabilities(network) ?: return@firstOrNull false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } ?: return@withContext TextResult(
            false,
            error = "Sin Internet disponible para visión Cerebras"
        )

        connection = internetNetwork.openConnection(url) as HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = 10_000
        connection.readTimeout = 30_000
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json")
        connection.setRequestProperty("Authorization", "Bearer ${apiKey.trim()}")

        val image64 = Base64.encodeToString(jpeg, Base64.NO_WRAP)
        val old = previousContext.takeLast(8_000)

        val instruction = if (detailedRequest) {
            """
                Estás analizando la imagen ACTUAL de la cámara de un wearable para contestar esta pregunta concreta:
                "$userQuestion"

                Haz una inspección visual más cuidadosa que la usada para el contexto de fondo.
                Prioriza exactamente aquello a lo que parece referirse la pregunta.
                Lee únicamente el texto que sea REALMENTE legible en la imagen: nombres, títulos, carteles, etiquetas, portadas, matrículas o inscripciones.

                REGLA ESTRICTA ANTI-ALUCINACIÓN:
                - No completes letras, títulos, marcas, nombres, artistas, discos, edificios, estatuas ni modelos a partir de una impresión parcial.
                - No conviertas una semejanza visual en una identificación.
                - No inventes texto que no pueda leerse con claridad.
                - Si el texto está borroso, cortado o ambiguo, indica "texto no legible" y no deduzcas el resto.
                - Solo da un nombre concreto cuando haya evidencia visual clara y suficiente.
                - Si no puedes estar razonablemente seguro, responde que no puedes identificarlo con seguridad y describe únicamente los rasgos que sí ves.
                - Es preferible no identificar algo antes que dar un nombre incorrecto.

                Usa texto legible y rasgos visuales únicamente cuando sean claros.
                Si puedes identificarlo con seguridad, devuelve su nombre específico y los detalles visuales que sustentan esa identificación.
                Si parece un monumento o lugar turístico, solo identifícalo si los rasgos distintivos son inequívocos.
                No te quedes en categorías genéricas si el título o nombre se puede leer claramente, pero nunca lo inventes.
                No describas toda la escena salvo que la pregunta pida una descripción general.
                Si algo no se distingue bien, dilo de forma concreta.
                Máximo 1600 caracteres.
            """.trimIndent()
        } else {
            """
                Eres la memoria visual silenciosa de un wearable.
                Tu tarea principal es describir QUÉ ESTÁ VIENDO AHORA MISMO la cámara del XIAO.
                Usa la imagen actual como fuente principal y no dependas de una captura manual.
                Describe de forma breve los objetos, aparatos, pantallas, personas sin identificar y el entorno que sean visibles.
                Si la escena ha cambiado, reemplaza los detalles antiguos por los actuales.
                Conserva del contexto anterior únicamente información que siga siendo claramente válida en la imagen actual.

                REGLA ANTI-ALUCINACIÓN:
                - Describe solo lo que realmente sea visible.
                - No inventes ni completes texto, títulos, marcas, nombres, artistas, discos, edificios, estatuas o modelos.
                - Si una identificación no es clara, usa una descripción genérica y marca la incertidumbre.
                - Si el texto está borroso o parcial, di que no es legible.
                - No arrastres una identificación antigua si la imagen actual no la confirma.
                - Nunca afirmes un nombre concreto basándote solo en parecido.

                Devuelve siempre un contexto actualizado de la escena actual, máximo 1200 caracteres.

                CONTEXTO ANTERIOR:
                ${if (old.isBlank()) "(vacío)" else old}
            """.trimIndent()
        }

        // Formato OpenAI-compatible: imagen primero y después texto.
        val userContent = org.json.JSONArray()
            .put(
                JSONObject()
                    .put("type", "image_url")
                    .put(
                        "image_url",
                        JSONObject().put(
                            "url",
                            "data:image/jpeg;base64,$image64"
                        )
                    )
            )
            .put(
                JSONObject()
                    .put("type", "text")
                    .put("text", instruction)
            )

        val messages = org.json.JSONArray()
            .put(
                JSONObject()
                    .put("role", "user")
                    .put("content", userContent)
            )

        // BLOQUE 2 - VISIÓN: evitamos que Qwen consuma toda la salida en
        // razonamiento interno y termine con content vacío. No cambia ninguna
        // regla de comportamiento: solo estabiliza la respuesta visual.
        val body = JSONObject()
            .put("model", "qwen-3.8-27b")
            .put("messages", messages)
            .put("reasoning_effort", "none")
            .put("max_completion_tokens", if (detailedRequest) 900 else 500)
            .toString()

        connection.outputStream.use {
            it.write(body.toByteArray(Charsets.UTF_8))
        }

        val code = connection.responseCode
        val raw = if (code in 200..299) {
            connection.inputStream.bufferedReader().use { it.readText() }
        } else {
            connection.errorStream?.bufferedReader()?.use { it.readText() } ?: "HTTP $code"
        }

        if (code !in 200..299) {
            return@withContext TextResult(false, error = "Visión Cerebras HTTP $code: $raw")
        }

        val json = JSONObject(raw)
        val choices = json.optJSONArray("choices")
            ?: return@withContext TextResult(false, error = "Visión Cerebras sin choices")
        if (choices.length() == 0) {
            return@withContext TextResult(false, error = "Visión Cerebras sin respuesta")
        }

        val choice = choices.getJSONObject(0)
        val finishReason = choice.optString("finish_reason", "")
        val message = choice.optJSONObject("message")
            ?: return@withContext TextResult(
                false,
                error = "Visión Cerebras sin message · HTTP $code · rawChars=${raw.length}"
            )

        // BLOQUE 2 - VISIÓN: el endpoint puede devolver content como String
        // o como una lista de bloques. Leemos ambos formatos. El reasoning no
        // se usa como respuesta; solo se mide para que el diagnóstico sea útil.
        val text = when (val content = message.opt("content")) {
            is String -> content.trim()
            is org.json.JSONArray -> {
                buildString {
                    for (i in 0 until content.length()) {
                        val part = content.optJSONObject(i) ?: continue
                        when (part.optString("type")) {
                            "text", "output_text" -> append(part.optString("text", ""))
                        }
                    }
                }.trim()
            }
            else -> choice.optString("text", "").trim()
        }

        if (text.isBlank()) {
            val reasoningChars = message.optString("reasoning", "").length
            TextResult(
                false,
                error = "Visión Cerebras devolvió texto vacío · HTTP $code · finish=$finishReason · reasoningChars=$reasoningChars · rawChars=${raw.length}"
            )
        } else {
            TextResult(true, text = text)
        }
    } catch (e: Exception) {
        TextResult(
            false,
            error = "Visión: ${e.javaClass.simpleName}: ${e.message ?: "sin detalle"}"
        )
    } finally {
        connection?.disconnect()
    }
}


// =====================================================
// MODO IA - ENVIAR AUDIO PCM DIRECTAMENTE A GEMINI
// =====================================================
suspend fun askGeminiWithPcmAudio(
    apiKey: String,
    pcmAudio: ByteArray
): TextResult =
    withContext(Dispatchers.IO) {
        var connection: HttpURLConnection? = null

        try {
            if (apiKey.isBlank()) {
                return@withContext TextResult(false, error = "Falta API key de Cerebras")
            }

            val url = URL(
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent"
            )

            connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.connectTimeout = 10000
            connection.readTimeout = 30000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("x-goog-api-key", apiKey.trim())

            val audio64 = Base64.encodeToString(pcmAudio, Base64.NO_WRAP)

            val parts = org.json.JSONArray()
                .put(
                    JSONObject().put(
                        "text",
                        "Escucha este audio del wearable. Si no hay una frase inteligible, responde exactamente NO_SPEECH. " +
                                "Si hay una frase, responde de forma breve y natural en español a lo que dice la persona."
                    )
                )
                .put(
                    JSONObject().put(
                        "inlineData",
                        JSONObject()
                            .put("mimeType", "audio/pcm;rate=16000")
                            .put("data", audio64)
                    )
                )

            val body = JSONObject()
                .put(
                    "contents",
                    org.json.JSONArray().put(
                        JSONObject().put("parts", parts)
                    )
                )
                .toString()

            connection.outputStream.use {
                it.write(body.toByteArray(Charsets.UTF_8))
            }

            val code = connection.responseCode
            val raw = if (code in 200..299) {
                connection.inputStream.bufferedReader().use { it.readText() }
            } else {
                connection.errorStream?.bufferedReader()?.use { it.readText() }
                    ?: "HTTP $code"
            }

            if (code !in 200..299) {
                return@withContext TextResult(false, error = "HTTP $code: $raw")
            }

            val json = JSONObject(raw)
            val candidates = json.optJSONArray("candidates")
                ?: return@withContext TextResult(false, error = "Gemini sin candidates")

            if (candidates.length() == 0) {
                return@withContext TextResult(false, error = "Gemini sin respuesta")
            }

            val answer = candidates.getJSONObject(0)
                .getJSONObject("content")
                .getJSONArray("parts")
                .getJSONObject(0)
                .optString("text", "")
                .trim()

            if (answer.equals("NO_SPEECH", ignoreCase = true) || answer.isBlank()) {
                TextResult(true, text = "")
            } else {
                TextResult(true, text = answer)
            }

        } catch (e: Exception) {
            TextResult(false, error = e.message ?: e.javaClass.simpleName)
        } finally {
            connection?.disconnect()
        }
    }


// =====================================================
// STT - PCM DEL XIAO -> TEXTO CON SPEECHRECOGNIZER ANDROID
// Android 13+ permite inyectar un ParcelFileDescriptor como fuente de audio.
// =====================================================

private fun savePcm16MonoWav(file: File, pcm: ByteArray, sampleRate: Int = 16_000) {
    FileOutputStream(file).use { out ->
        fun le16(v: Int) { out.write(v and 255); out.write((v shr 8) and 255) }
        fun le32(v: Int) {
            out.write(v and 255); out.write((v shr 8) and 255)
            out.write((v shr 16) and 255); out.write((v shr 24) and 255)
        }
        out.write("RIFF".toByteArray(Charsets.US_ASCII)); le32(36 + pcm.size)
        out.write("WAVEfmt ".toByteArray(Charsets.US_ASCII)); le32(16)
        le16(1); le16(1); le32(sampleRate); le32(sampleRate * 2); le16(2); le16(16)
        out.write("data".toByteArray(Charsets.US_ASCII)); le32(pcm.size)
        out.write(pcm)
    }
}

private fun playLastVoskInput(context: Context, onStatus: (String) -> Unit) {
    try {
        val wav = File(context.cacheDir, "last_vosk_input.wav")
        if (!wav.exists() || wav.length() <= 44L) {
            onStatus("Aún no hay frase Vosk guardada")
            return
        }
        val mp = MediaPlayer()
        mp.setDataSource(wav.absolutePath)
        mp.setOnPreparedListener {
            onStatus("REPRODUCIENDO la frase EXACTA enviada a Vosk")
            it.start()
        }
        mp.setOnCompletionListener {
            it.release()
            onStatus("ESCUCHA VOSK TERMINADA")
        }
        mp.setOnErrorListener { player, _, _ ->
            player.release()
            onStatus("ERROR reproduciendo la frase Vosk")
            true
        }
        mp.prepareAsync()
    } catch (e: Exception) {
        onStatus("ERROR Vosk WAV: ${e.message ?: e.javaClass.simpleName}")
    }
}

private fun playXiaoPcmOnPhone(context: Context, pcm: ByteArray, onStatus: (String) -> Unit) {
    try {
        val wav = File(context.cacheDir, "xiao_mic_test.wav")
        FileOutputStream(wav).use { out ->
            fun le16(v: Int) { out.write(v and 255); out.write((v shr 8) and 255) }
            fun le32(v: Int) {
                out.write(v and 255); out.write((v shr 8) and 255)
                out.write((v shr 16) and 255); out.write((v shr 24) and 255)
            }
            out.write("RIFF".toByteArray(Charsets.US_ASCII)); le32(36 + pcm.size)
            out.write("WAVEfmt ".toByteArray(Charsets.US_ASCII)); le32(16)
            le16(1); le16(1); le32(16000); le32(32000); le16(2); le16(16)
            out.write("data".toByteArray(Charsets.US_ASCII)); le32(pcm.size)
            out.write(pcm)
        }
        val mp = MediaPlayer()
        mp.setDataSource(wav.absolutePath)
        mp.setOnPreparedListener {
            onStatus("REPRODUCIENDO audio REAL del XIAO en el teléfono")
            it.start()
        }
        mp.setOnCompletionListener {
            it.release()
            onStatus("ESCUCHA TERMINADA")
        }
        mp.setOnErrorListener { player, _, _ ->
            player.release()
            onStatus("ERROR reproduciendo audio")
            true
        }
        mp.prepareAsync()
    } catch (e: Exception) {
        onStatus("ERROR: ${e.message ?: e.javaClass.simpleName}")
    }
}


private const val VOSK_ES_ASSET_DIR = "vosk-model-small-es-0.42"

private fun copyAssetDirectory(
    context: Context,
    assetPath: String,
    destination: File
) {
    val children = context.assets.list(assetPath) ?: emptyArray()

    if (children.isEmpty()) {
        destination.parentFile?.mkdirs()
        context.assets.open(assetPath).use { input ->
            destination.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        return
    }

    destination.mkdirs()
    for (child in children) {
        val childAsset = "$assetPath/$child"
        val childDest = File(destination, child)
        copyAssetDirectory(context, childAsset, childDest)
    }
}

private fun ensureSpanishVoskModel(context: Context): File {
    val destination = File(context.filesDir, VOSK_ES_ASSET_DIR)

    // final.mdl es una comprobación sencilla de que el modelo ya fue copiado.
    val finalModel = File(destination, "am/final.mdl")
    if (finalModel.exists()) return destination

    val rootAssets = context.assets.list("")?.toSet().orEmpty()
    if (!rootAssets.contains(VOSK_ES_ASSET_DIR)) {
        throw IllegalStateException(
            "Falta $VOSK_ES_ASSET_DIR en app/src/main/assets/"
        )
    }

    if (destination.exists()) destination.deleteRecursively()
    copyAssetDirectory(context, VOSK_ES_ASSET_DIR, destination)

    if (!finalModel.exists()) {
        throw IllegalStateException("El modelo Vosk español está incompleto")
    }

    return destination
}

// =====================================================
// STT LOCAL REAL: PCM XIAO -> VOSK -> TEXTO
// No usa SpeechRecognizer, Whisper ni una API de transcripción.
// Entrada esperada: PCM S16LE, mono, 16 kHz.
// =====================================================

// =====================================================
// VOSK CACHE V4
// El modelo acústico es pesado. Antes se abría/cerraba en cada frase,
// provocando recargas repetidas y pausas. Ahora se carga una sola vez
// por proceso y se reutiliza. Cada frase sigue usando su propio Recognizer.
// =====================================================
private object VoskModelCache {
    @Volatile private var cachedModel: Model? = null
    @Volatile private var loading: Boolean = false

    fun isReady(): Boolean = cachedModel != null

    fun get(context: Context): Model {
        cachedModel?.let { return it }
        synchronized(this) {
            cachedModel?.let { return it }
            loading = true
            try {
                val modelDir = ensureSpanishVoskModel(context.applicationContext)
                val loaded = Model(modelDir.absolutePath)
                cachedModel = loaded
                return loaded
            } finally {
                loading = false
            }
        }
    }

    suspend fun warmUp(context: Context): Boolean = withContext(Dispatchers.IO) {
        try {
            get(context)
            true
        } catch (_: Exception) {
            false
        }
    }
}

suspend fun transcribeXiaoPcmWithVosk(
    context: Context,
    pcmAudio: ByteArray
): TextResult = withContext(Dispatchers.IO) {

    if (pcmAudio.size < 3_200) {
        return@withContext TextResult(
            false,
            error = "VOSK V9: audio demasiado corto (${pcmAudio.size} bytes)"
        )
    }

    // XIAO: PCM S16LE, mono, 16 kHz.
    // V51 MIC/ESCUCHA: quitar offset DC + ganancia digital SUAVE solo para Vosk.
    // No toca VAD, cámara, web ni comportamiento. No usamos filtro pasa-altos ni AGC agresivo.
    val sampleCount = pcmAudio.size / 2
    val samples = IntArray(sampleCount)
    var sum = 0L
    var rawMin = Int.MAX_VALUE
    var rawMax = Int.MIN_VALUE

    for (i in 0 until sampleCount) {
        val lo = pcmAudio[i * 2].toInt() and 0xFF
        val hi = pcmAudio[i * 2 + 1].toInt()
        val s = ((hi shl 8) or lo).toShort().toInt()
        samples[i] = s
        sum += s.toLong()
        if (s < rawMin) rawMin = s
        if (s > rawMax) rawMax = s
    }

    val dc = sum.toDouble() / sampleCount.toDouble()

    val correctedPcm = ByteArray(sampleCount * 2)
    val centeredSamples = DoubleArray(sampleCount)
    var energy = 0.0
    var peak = 0.0
    var zeroCrossings = 0
    var nearZeroSamples = 0
    var previousCentered = 0.0

    // Primera pasada: medir la señal REAL ya sin DC.
    for (i in 0 until sampleCount) {
        val centeredDouble = samples[i].toDouble() - dc
        centeredSamples[i] = centeredDouble
        energy += centeredDouble * centeredDouble
        peak = maxOf(peak, kotlin.math.abs(centeredDouble))
        if (kotlin.math.abs(centeredDouble) < 32.0) nearZeroSamples++
        if (i > 0 && ((previousCentered < 0.0 && centeredDouble >= 0.0) ||
                    (previousCentered >= 0.0 && centeredDouble < 0.0))) {
            zeroCrossings++
        }
        previousCentered = centeredDouble
    }

    val rms = kotlin.math.sqrt(energy / sampleCount.toDouble())

    // V51: la voz de la XIAO llega a Vosk con RMS muy bajo en bastantes frases.
    // Aplicamos una ganancia conservadora SOLO al PCM entregado a Vosk.
    // Objetivo 650 RMS y máximo x3: suficiente para reforzar consonantes/sílabas
    // iniciales sin convertir el ruido de fondo en una señal enorme.
    val voskGain = if (rms > 1.0) {
        (650.0 / rms).coerceIn(1.0, 3.0)
    } else {
        1.0
    }

    for (i in 0 until sampleCount) {
        val amplified = (centeredSamples[i] * voskGain)
            .toInt()
            .coerceIn(-32768, 32767)

        correctedPcm[i * 2] = (amplified and 0xFF).toByte()
        correctedPcm[i * 2 + 1] = ((amplified shr 8) and 0xFF).toByte()
    }
    val durationSec = sampleCount / 16000.0
    val zeroCrossRate = if (sampleCount > 1) zeroCrossings.toDouble() / (sampleCount - 1).toDouble() else 0.0
    val nearZeroPct = if (sampleCount > 0) nearZeroSamples * 100.0 / sampleCount.toDouble() else 0.0

    // V9 DIAGNÓSTICO: guardamos EXACTAMENTE el PCM corregido que se entrega a Vosk.
    // Así podemos escucharlo después sin cambiar el firmware del XIAO.
    try {
        savePcm16MonoWav(
            File(context.cacheDir, "last_vosk_input.wav"),
            correctedPcm,
            16_000
        )
    } catch (_: Exception) {}

    var recognizer: Recognizer? = null
    try {
        val model = VoskModelCache.get(context.applicationContext)
        recognizer = Recognizer(model, 16_000.0f)

        var offset = 0
        val chunkBytes = 3_200 // 100 ms
        var endpointText = ""
        var bestPartial = ""

        while (offset < correctedPcm.size) {
            val count = minOf(chunkBytes, correctedPcm.size - offset)
            val chunk = correctedPcm.copyOfRange(offset, offset + count)

            val endpoint = recognizer.acceptWaveForm(chunk, chunk.size)

            val partial = try {
                JSONObject(recognizer.partialResult)
                    .optString("partial", "")
                    .trim()
            } catch (_: Exception) { "" }

            if (partial.length > bestPartial.length) {
                bestPartial = partial
            }

            if (endpoint) {
                val resultText = try {
                    JSONObject(recognizer.result)
                        .optString("text", "")
                        .trim()
                } catch (_: Exception) { "" }

                if (resultText.isNotBlank()) {
                    endpointText = listOf(endpointText, resultText)
                        .filter { it.isNotBlank() }
                        .joinToString(" ")
                }
            }

            offset += count
        }

        // 400 ms de silencio para cerrar la última palabra.
        val closingSilence = ByteArray(12_800)
        if (recognizer.acceptWaveForm(closingSilence, closingSilence.size)) {
            val resultText = try {
                JSONObject(recognizer.result)
                    .optString("text", "")
                    .trim()
            } catch (_: Exception) { "" }

            if (resultText.isNotBlank()) {
                endpointText = listOf(endpointText, resultText)
                    .filter { it.isNotBlank() }
                    .joinToString(" ")
            }
        }

        val finalJson = recognizer.finalResult
        val finalText = try {
            JSONObject(finalJson).optString("text", "").trim()
        } catch (_: Exception) { "" }

        // Los resultados de endpoint y el final son segmentos sucesivos.
        // Conservar ambos evita perder el final de la pregunta.
        val rawRecognized = joinVoskResults(endpointText, finalText, bestPartial)

        // V51 MIC/ESCUCHA: corrección MUY acotada de una confusión repetitiva del ASR.
        // Se hace aquí, dentro de transcripción, antes de salir del bloque de micrófono.
        val recognized = repairVoskSpanishListeningConfusions(rawRecognized)
        if (recognized != rawRecognized) {
            diag(
                context,
                "VOSK_LISTENING_REPAIR",
                "from='${rawRecognized.take(160)}' to='${recognized.take(160)}'"
            )
        }

        diag(
            context,
            "VOSK_AUDIO_MEASURE",
            "result=${if (recognized.isNotBlank()) "OK" else "EMPTY"} " +
                    "bytes=${pcmAudio.size} samples=$sampleCount dur=${"%.2f".format(durationSec)}s " +
                    "format=S16LE/16000Hz/mono dc=${"%.1f".format(dc)} rawMin=$rawMin rawMax=$rawMax " +
                    "rms=${"%.1f".format(rms)} peak=${"%.1f".format(peak)} voskGain=${"%.2f".format(voskGain)} " +
                    "zcr=${"%.4f".format(zeroCrossRate)} nearZero=${"%.1f".format(nearZeroPct)}% " +
                    "endpoint='${endpointText.take(120)}' partial='${bestPartial.take(120)}' " +
                    "final='${finalText.take(120)}' chosen='${recognized.take(160)}'"
        )

        if (recognized.isNotBlank()) {
            TextResult(true, text = recognized)
        } else {
            TextResult(
                false,
                error = "VOSK V9 AUDIO VACÍO · bytes=${pcmAudio.size} · dur=${"%.2f".format(sampleCount / 16000.0)}s · DCquitado=${"%.1f".format(dc)} · RMS=${"%.1f".format(rms)} · pico=${"%.1f".format(peak)} · parcial='$bestPartial' · final=$finalJson"
            )
        }

    } catch (e: Exception) {
        TextResult(
            false,
            error = "VOSK V9 AUDIO: ${e.javaClass.simpleName}: ${e.message ?: "sin detalle"}"
        )
    } finally {
        try { recognizer?.close() } catch (_: Exception) {}
    }
}

suspend fun transcribeXiaoPcmWithAndroid(
    context: Context,
    pcmAudio: ByteArray
): TextResult = withContext(Dispatchers.Main) {

    // NUEVO: normalizamos el PCM del XIAO antes de entregarlo a Android.
    // El endpoint puede devolver 16000 bytes correctamente y, aun así,
    // la voz llegar demasiado baja para que SpeechRecognizer encuentre palabras.
    fun normalizeXiaoPcm(input: ByteArray): ByteArray {
        if (input.size < 2) return input

        val sampleCount = input.size / 2
        val samples = IntArray(sampleCount)
        var sum = 0L

        for (i in 0 until sampleCount) {
            val lo = input[i * 2].toInt() and 0xFF
            val hi = input[i * 2 + 1].toInt()
            val v = ((hi shl 8) or lo).toShort().toInt()
            samples[i] = v
            sum += v
        }

        // Quitar componente continua del micrófono.
        val dc = (sum / sampleCount).toInt()

        var peak = 1
        for (v in samples) {
            val a = kotlin.math.abs(v - dc)
            if (a > peak) peak = a
        }

        // Llevar el pico aproximadamente a 80 % de escala.
        // Limitamos la ganancia para no amplificar ruido extremo.
        val gain = (26_000.0 / peak.toDouble()).coerceIn(1.0, 8.0)

        val out = ByteArray(sampleCount * 2)
        for (i in 0 until sampleCount) {
            val adjusted = ((samples[i] - dc) * gain)
                .toInt()
                .coerceIn(-32768, 32767)

            out[i * 2] = (adjusted and 0xFF).toByte()
            out[i * 2 + 1] = ((adjusted shr 8) and 0xFF).toByte()
        }
        return out
    }

    val speechPcm = normalizeXiaoPcm(pcmAudio)
    if (ContextCompat.checkSelfPermission(
            context, Manifest.permission.RECORD_AUDIO
        ) != PackageManager.PERMISSION_GRANTED
    ) {
        return@withContext TextResult(false, error = "Permiso RECORD_AUDIO no concedido")
    }

    if (pcmAudio.isEmpty()) {
        return@withContext TextResult(false, error = "Audio vacío")
    }

    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
        return@withContext TextResult(false, error = "Android 13 o superior requerido")
    }

    if (!SpeechRecognizer.isRecognitionAvailable(context)) {
        return@withContext TextResult(false, error = "Reconocimiento de voz no disponible")
    }

    suspendCancellableCoroutine { cont ->
        var recognizer: SpeechRecognizer? = null
        var readSide: ParcelFileDescriptor? = null
        var writeSide: ParcelFileDescriptor? = null
        var done = false
        var writerStarted = false

        fun finish(result: TextResult) {
            if (done) return
            done = true
            try { writeSide?.close() } catch (_: Exception) {}
            try { readSide?.close() } catch (_: Exception) {}
            try { recognizer?.destroy() } catch (_: Exception) {}
            writeSide = null
            readSide = null
            recognizer = null
            if (cont.isActive) cont.resume(result)
        }

        fun feedPcmInRealTime() {
            if (writerStarted || done) return
            writerStarted = true
            val fd = writeSide ?: return

            Thread {
                try {
                    ParcelFileDescriptor.AutoCloseOutputStream(fd).use { out ->
                        // PCM S16LE, mono, 16 kHz = 32 000 bytes/seg.
                        // 20 ms = 640 bytes. Se envía al ritmo real del audio;
                        // antes se volcaban ~3 s de PCM casi instantáneamente.
                        val frameBytes = 640

                        // Pequeño silencio de entrada.
                        repeat(10) {
                            out.write(ByteArray(frameBytes))
                            out.flush()
                            Thread.sleep(20)
                        }

                        var offset = 0
                        while (offset < speechPcm.size && !done) {
                            val count = minOf(frameBytes, speechPcm.size - offset)
                            out.write(speechPcm, offset, count)
                            out.flush()
                            offset += count
                            Thread.sleep(20)
                        }

                        // Silencio final para que Android cierre la frase.
                        repeat(30) {
                            if (done) return@repeat
                            out.write(ByteArray(frameBytes))
                            out.flush()
                            Thread.sleep(20)
                        }
                    }
                    writeSide = null
                } catch (e: Exception) {
                    Handler(Looper.getMainLooper()).post {
                        if (!done) {
                            finish(
                                TextResult(
                                    false,
                                    error = "Error enviando PCM: ${e.message ?: e.javaClass.simpleName}"
                                )
                            )
                        }
                    }
                }
            }.start()
        }

        try {
            val pipe = ParcelFileDescriptor.createPipe()
            readSide = pipe[0]
            writeSide = pipe[1]

            recognizer = SpeechRecognizer.createSpeechRecognizer(context)
            recognizer!!.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    feedPcmInRealTime()
                }

                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}

                override fun onError(error: Int) {
                    val detail = when (error) {
                        SpeechRecognizer.ERROR_NO_MATCH ->
                            "No se entendió la frase del XIAO"
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                            "No se detectó voz en el audio del XIAO"
                        SpeechRecognizer.ERROR_AUDIO ->
                            "Android no pudo procesar el audio del XIAO"
                        SpeechRecognizer.ERROR_NETWORK,
                        SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                            "El reconocimiento de Android no tiene conexión"
                        else -> "SpeechRecognizer error $error"
                    }
                    finish(TextResult(false, error = detail))
                }

                override fun onResults(results: Bundle?) {
                    val text = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        .orEmpty()
                        .trim()

                    if (text.isBlank()) {
                        finish(TextResult(false, error = "No se entendió la frase del XIAO"))
                    } else {
                        finish(TextResult(true, text = text))
                    }
                }

                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "es-ES")
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)

                // Fuente: PCM del XIAO, no el micrófono del teléfono.
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readSide)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                putExtra(
                    RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, 16_000)
            }

            recognizer!!.startListening(intent)

            // Algunos motores no llaman a onReadyForSpeech con audio externo.
            Handler(Looper.getMainLooper()).postDelayed({
                if (!done) feedPcmInRealTime()
            }, 500)

            // Segundo cortafuegos además del withTimeout exterior.
            Handler(Looper.getMainLooper()).postDelayed({
                if (!done) {
                    try { recognizer?.cancel() } catch (_: Exception) {}
                    finish(TextResult(false, error = "El reconocedor no devolvió resultado"))
                }
            }, 9_000)

            cont.invokeOnCancellation {
                Handler(Looper.getMainLooper()).post {
                    if (!done) {
                        done = true
                        try { recognizer?.cancel() } catch (_: Exception) {}
                        try { writeSide?.close() } catch (_: Exception) {}
                        try { readSide?.close() } catch (_: Exception) {}
                        try { recognizer?.destroy() } catch (_: Exception) {}
                    }
                }
            }
        } catch (e: Exception) {
            finish(TextResult(false, error = e.message ?: e.javaClass.simpleName))
        }
    }
}


// =====================================================
// RED MÓVIL EXPLÍCITA PARA BÚSQUEDA WEB
// =====================================================
suspend fun getCellularInternetNetwork(
    context: Context,
    timeoutMs: Long = 6_000
): Network? = kotlinx.coroutines.suspendCancellableCoroutine { cont ->

    val cm =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    val request =
        NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

    var finished = false

    lateinit var callback: ConnectivityManager.NetworkCallback

    fun finish(network: Network?) {
        if (finished) return
        finished = true
        try {
            cm.unregisterNetworkCallback(callback)
        } catch (_: Exception) {
        }
        if (cont.isActive) cont.resume(network)
    }

    callback =
        object : ConnectivityManager.NetworkCallback() {

            override fun onAvailable(network: Network) {
                val caps = cm.getNetworkCapabilities(network)

                val valid =
                    caps?.hasCapability(
                        NetworkCapabilities.NET_CAPABILITY_INTERNET
                    ) == true

                if (valid) {
                    finish(network)
                }
            }

            override fun onUnavailable() {
                finish(null)
            }
        }

    try {
        cm.requestNetwork(request, callback)

        Handler(Looper.getMainLooper()).postDelayed(
            {
                if (!finished) {
                    finish(null)
                }
            },
            timeoutMs
        )

    } catch (_: Exception) {
        finish(null)
    }

    cont.invokeOnCancellation {
        if (!finished) {
            finished = true
            try {
                cm.unregisterNetworkCallback(callback)
            } catch (_: Exception) {
            }
        }
    }
}


// =====================================================
// BÚSQUEDA WEB - TAVILY
// =====================================================
// Decisiones locales sobre el texto reconocido; no alteran audio ni conexiones.
// Reglas locales: capturar una imagen no implica analizarla ni almacenarla.
fun visualDecisionReason(question: String, memory: String): String {
    val q = normalizeWearableIntent(question)
    if (isIncompleteVoiceQuestion(question)) return "skip:incomplete_question"
    if (shouldUseVisualMemory(question)) return "memory:explicit_past_reference"
    val explicitNow = Regex("""\b(?:ahora|delante|aqui|en esta imagen|en esta foto)\b""").containsMatchIn(q)
    val rememberedObject = Regex("""\b(?:ese|esa|aquel|aquella)\s+\w+|\b(?:disco|poster|objeto) que te ensene\b""").containsMatchIn(q)
    if (rememberedObject && !explicitNow && memory.isNotBlank()) return "memory:previous_object_reference"
    val visualQuestion = Regex("""\b(?:que (?:ves|estas viendo|pone|dice aqui|color|objeto|tengo delante)|que (?:es|son) (?:esto|eso|este|esta|ese|esa)|de que color|lee (?:esto|eso|aqui)|describe (?:esto|lo que ves)|mira (?:esto|aqui|ahora)|identifica (?:esto|este|esta)|(?:que|cual) (?:album|disco) es)\b""").containsMatchIn(q)
    if (visualQuestion) return "current:question_depends_on_visible_scene"
    return "skip:conversation_does_not_require_current_image"
}

// V44: preguntas que deben provocar una inspección visual fina de la imagen actual.
// Solo afecta a visión bajo demanda; no cambia el análisis silencioso de fondo.
fun isDetailedCurrentVisualQuestion(question: String): Boolean {
    val q = normalizeWearableIntent(question)
    return Regex(
        """\b(?:que (?:ves|estas viendo|hay ahi|hay aqui|pone|dice ahi|dice aqui)|que (?:es|son) (?:esto|eso|este|esta|ese|esa|aquello)|cual es (?:esto|eso|este|esta)|lee (?:esto|eso|aqui|ahi)|identifica (?:esto|eso|este|esta)|mira (?:esto|eso|aqui|ahi)|(?:que|cual) (?:album|disco|monumento|estatua|edificio|cuadro|objeto) (?:es|ves))\b"""
    ).containsMatchIn(q)
}

fun visualMemoryEntries(memory: String): List<String> =
    memory.split(Regex("""\n(?=\[\d{2}:\d{2}:\d{2}\] VISTO:)"""))
        .map { it.trim() }.filter { it.isNotBlank() }

fun compactVisualText(text: String): String {
    val clean = text.replace(Regex("""\s+"""), " ").trim()
    if (clean.length <= 1_200) return clean
    return clean.take(1_200).substringBeforeLast(" ", clean.take(1_200)) + "…"
}

fun visualObservationWorthKeeping(text: String): Boolean {
    val q = normalizeWearableIntent(text)
    if (q.isBlank() || q == "no change") return false
    // Oclusión explícita: responder sobre ella si se pregunta ahora, sin desplazar recuerdos.
    if (Regex("""(?:camara|objetivo|vision).{0,35}(?:bloquead|tapad)|(?:hombro|espalda).{0,45}(?:bloquea|ocupa casi)|vista.{0,35}dominada.{0,60}(?:silueta|hombro|espalda)""").containsMatchIn(q.take(250))) return false
    return !Regex("""^(?:solo (?:se ve|veo|hay) |(?:se ve|veo|hay) )?(?:una )?pared(?: blanca| lisa| vacia)?$""").matches(q)
}

fun appendVisualObservation(memory: String, observation: String, stamp: String): String {
    if (!visualObservationWorthKeeping(observation)) return memory
    val compact = compactVisualText(observation)
    val key = normalizeWearableIntent(compact)
    val entries = visualMemoryEntries(memory).filter {
        normalizeWearableIntent(it.substringAfter("VISTO: ", it)) != key
    }.toMutableList()
    entries.add("[$stamp] VISTO: $compact")
    // Solo texto, sin imágenes; eliminar entradas completas al alcanzar el límite.
    while (entries.size > 1 && entries.sumOf { it.length + 1 } > 16_000) entries.removeAt(0)
    return entries.joinToString("\n")
}

fun selectVisualMemory(question: String, memory: String): String {
    val ignored = setOf("antes", "viste", "hablame", "sobre", "quiero", "puedes", "ensene", "posterior", "ahora", "aquel", "aquella", "otra", "hace", "falta", "mires")
    val words = normalizeWearableIntent(question).split(" ").filter { it.length >= 4 && it !in ignored }
    val entries = visualMemoryEntries(memory)
    val ranked = entries.mapIndexed { index, entry ->
        val text = normalizeWearableIntent(entry)
        Triple(index, entry, words.count { word -> text.contains(word) })
    }.sortedWith(compareByDescending<Triple<Int, String, Int>> { it.third }.thenByDescending { it.first })
    val selected = mutableListOf<String>()
    var chars = 0
    for ((_, entry, _) in ranked) {
        if (chars + entry.length + 1 > 9_000) continue
        selected.add(entry)
        chars += entry.length + 1
    }
    return selected.joinToString("\n")
}


fun answerRequestsWebFallback(answer: String): Boolean {
    val a = normalizeWearableIntent(answer)
    if (a.isBlank()) return false

    val uncertaintySignals = listOf(
        "no se",
        "no lo se",
        "no puedo saber",
        "no puedo confirmar",
        "no puedo determinar",
        "no puedo identificar",
        "no puedo identificarlo",
        "no puedo reconocer",
        "no estoy seguro",
        "no estoy segura",
        "no queda claro",
        "no se distingue",
        "no se ve con claridad",
        "no es posible identificar",
        "no tengo informacion",
        "no tengo datos",
        "no dispongo de informacion",
        "no dispongo de datos",
        "no tengo acceso a informacion en tiempo real",
        "no tengo acceso a internet",
        "no puedo consultar internet",
        "no puedo consultar la web",
        "no puedo verificar",
        "no puedo comprobar",
        "necesitaria informacion actual",
        "necesitaria datos actuales",
        "necesito informacion actual",
        "necesito datos actuales",
        "para saberlo tendria que consultar",
        "te recomiendo consultar",
        "consulta la prensa",
        "consulta internet",
        "consulta la web"
    )

    return uncertaintySignals.any { a.contains(it) }
}

fun answerStillUncertainAfterWeb(answer: String): Boolean {
    val a = normalizeWearableIntent(answer)
    if (a.isBlank()) return true

    val signals = listOf(
        "no se",
        "no lo se",
        "no puedo identificar",
        "no puedo determinar",
        "no puedo confirmar",
        "no estoy seguro",
        "no estoy segura",
        "no hay suficiente informacion",
        "no tengo suficiente informacion",
        "no hay datos suficientes",
        "no tengo datos suficientes",
        "no se puede identificar",
        "no es posible identificar",
        "no queda claro",
        "no se distingue",
        "no puedo reconocer"
    )

    return signals.any { a.contains(it) }
}

fun refinedVisualWebQuery(question: String, currentVisual: String): String {
    val visual = currentVisual.trim().take(1200)
    if (visual.isBlank()) return question

    return buildString {
        append("Identifica el objeto de la imagen actual. ")
        append("No uses contexto de imágenes anteriores. ")
        append("Usa únicamente estos rasgos visuales actuales y busca coincidencias concretas en internet. ")
        append("Si hay varias posibilidades, compáralas por postura, forma, material, texto visible, fondo y rasgos distintivos. ")
        append("Pregunta del usuario: ")
        append(question)
        append("\nRasgos visuales actuales: ")
        append(visual)
    }
}


fun webDecisionReason(question: String): String = when {
    isIncompleteVoiceQuestion(question) -> "skip:incomplete_question"
    declinesWebSearch(question) -> "skip:explicit_web_opt_out"
    else -> webSearchTrigger(question)?.let { "use:$it" } ?: "skip:no_web_request_or_live_topic"
}

fun wearableSearchQuery(question: String, visualText: String): String {
    val q = normalizeWearableIntent(question)

    // FIX QUIRÚRGICO WEB:
    // Vosk puede oír "buscando" cuando el usuario dice "búscalo".
    // Tratamos todas estas variantes como la MISMA orden genérica y nunca
    // enviamos literalmente "busca/buscando por internet" al buscador.
    val genericWebCommand =
        Regex(
            """^(?:busca|buscalo|buscar|buscarlo|buscando|miralo|mira|consulta|consultalo|comprueba|verifica)(?:\s+(?:por|en)\s+(?:internet|web|la web|google))?$"""
        ).matches(q)

    val needsObject =
        Regex("""\b(?:buscalo|buscarlo|ese|esa|esto|eso)\b|\b(?:que|cual) (?:album|disco) es\b""")
            .containsMatchIn(q)

    if (visualText.isBlank()) return question

    val visualObject =
        visualText.substringAfter("VISTO: ", visualText).take(600)

    if (genericWebCommand) {
        return "Identifica en internet este objeto usando SOLO esta descripción visual: $visualObject"
    }

    if (!needsObject) return question

    return question + "\nObjeto descrito por la cámara (sin identificar con certeza): " +
            visualObject
}

fun phraseRejectionReason(pcm: ByteArray, frameBytes: Int = 3_200): String? {
    if (pcm.size < frameBytes) return "less_than_100ms"
    val levels = mutableListOf<Double>()
    val peaks = mutableListOf<Double>()
    var voiced = 0
    var strong = 0
    var offset = 0
    while (offset + frameBytes <= pcm.size) {
        val frame = pcm.copyOfRange(offset, offset + frameBytes)
        val stats = pcmAcStats(frame)
        levels.add(stats.rms)
        peaks.add(stats.peak)
        if (pcmContainsVoice(frame)) voiced++
        if (stats.rms > 95.0 && stats.peak > 480.0) strong++
        offset += frameBytes
    }

    if (voiced < 2) return "less_than_200ms_voice_evidence"

    val mean = levels.average()
    val maxRms = levels.maxOrNull() ?: 0.0
    val maxPeak = peaks.maxOrNull() ?: 0.0
    val voicedRatio = voiced.toDouble() / levels.size.coerceAtLeast(1).toDouble()

    // V34: ruido bajo/aislado. Para no perder voz baja, solo se rechaza cuando
    // coinciden TRES señales: energía media baja, poca continuidad y ausencia
    // de picos claramente vocales.
    if (levels.size >= 8 && mean < 165.0 && voicedRatio < 0.38 && strong == 0 && maxRms < 320.0 && maxPeak < 1_100.0) {
        return "weak_discontinuous_low_energy_noise"
    }

    // Rechazar bloques largos, débiles y casi constantes.
    if (levels.size >= 30) {
        val variation = kotlin.math.sqrt(levels.map { (it - mean) * (it - mean) }.average())
        if (mean < 300.0 && variation / mean.coerceAtLeast(1.0) < 0.08) return "long_stationary_low_energy_noise"
    }
    return null
}

fun fastBargeTextReady(candidate: String, stableFrames: Int, endpoint: Boolean): Boolean {
    val words = normalizeWearableIntent(candidate).split(" ").filter { it.isNotBlank() }

    // V43: durante TTS solo aceptamos una interrupción clara.
    // Los comandos de parada siguen siendo inmediatos. Para cualquier otra frase
    // exigimos más contenido y estabilidad para evitar que el propio altavoz
    // se interprete como voz nueva del usuario.
    val command = isFastStopCommand(candidate) ||
            words.joinToString(" ") in setOf("para", "basta", "calla", "silencio", "espera", "stop", "no no")

    val content = words.count {
        it !in setOf("el", "la", "los", "las", "un", "una", "de", "del", "en", "entre", "a", "y", "que", "por", "con")
    }

    if (command) return endpoint || stableFrames >= 1

    val clearSentence = words.size >= 3 && content >= 2
    return clearSentence && (endpoint || stableFrames >= 3)
}


fun normalizeWearableIntent(text: String): String =
    java.text.Normalizer.normalize(text.lowercase(Locale("es", "ES")), java.text.Normalizer.Form.NFD)
        .replace(Regex("""\p{M}+"""), "")
        .replace(Regex("""[^\p{L}\p{N}\s]"""), " ")
        .replace(Regex("""\s+"""), " ")
        .trim()

fun declinesWebSearch(question: String): Boolean {
    val q = normalizeWearableIntent(question)
    return Regex("""\b(?:no\s+(?:(?:quiero|necesito|hace falta)\s+(?:que\s+)?)?(?:busques|buscar|buscarlo|busca|consultes|consultar|uses|usar)|sin\s+(?:buscar|buscarlo|consultar|usar))\s+(?:(?:en|por)\s+)?(?:internet|la web|la red|google)\b""").containsMatchIn(q)
}

fun hasExplicitWebRequest(question: String): Boolean {
    val q = normalizeWearableIntent(question)
    val online = Regex("""\b(?:internet|web|google)\b""").containsMatchIn(q)
    val action = Regex("""\b(?:busca\w*|busque\w*|consulta\w*|consulte\w*|mira\w*|mire\w*|comprueba\w*|verifica\w*)\b""").containsMatchIn(q)
    val identifyAlbum = Regex("""\b(?:mira|busca|averigua|consulta)\s+(?:que|cual)\s+(?:album|disco)\s+es\b""").containsMatchIn(q)
    val information = Regex("""\b(?:busca|buscar|buscame|consulta)\s+informacion\b""").containsMatchIn(q)
    return !declinesWebSearch(question) && ((online && action) || identifyAlbum || information)
}

fun shouldUseVisualMemory(question: String): Boolean {
    val q = normalizeWearableIntent(question)
    // Una petición explícita de mirar ahora tiene prioridad sobre el pasado.
    val currentView = Regex("""\b(?:mira(?:lo)?|enfoca(?:lo)?|observa(?:lo)?|ves|viendo)\s+(?:ahora|de nuevo|otra vez)\b""").containsMatchIn(q)
    val noNewLook = Regex("""\b(?:no hace falta que (?:lo |la )?mires|sin (?:volver a )?mirar|no (?:lo |la )?mires)\b""").containsMatchIn(q)
    if (currentView && !noNewLook) return false
    return noNewLook || Regex("""\b(?:viste|vimos|vimos antes|habias visto|has visto antes|te ensene|te mostre|recuerdas|recuerda|lo anterior|de antes|que viste antes)\b""").containsMatchIn(q)
}

fun isIncompleteVoiceQuestion(question: String): Boolean =
    normalizeWearableIntent(question) in setOf("", "que", "el", "la", "los", "las", "de", "y", "pero", "porque", "es que")

// V34: filtro MUY conservador de transcripciones probablemente espurias.
// Nunca descarta una frase solo por sonar rara: exige además audio débil/discontinuo.
fun suspiciousWeakTranscript(text: String, pcm: ByteArray, frameBytes: Int = 3_200): Boolean {
    val words = normalizeWearableIntent(text).split(" ").filter { it.isNotBlank() }
    if (words.size < 3) return false

    var offset = 0
    var voiced = 0
    var strong = 0
    var frames = 0
    var rmsSum = 0.0
    while (offset + frameBytes <= pcm.size) {
        val frame = pcm.copyOfRange(offset, offset + frameBytes)
        val st = pcmAcStats(frame)
        frames++
        rmsSum += st.rms
        if (pcmContainsVoice(frame)) voiced++
        if (st.rms > 95.0 && st.peak > 480.0) strong++
        offset += frameBytes
    }
    if (frames == 0) return false

    val meanRms = rmsSum / frames
    val voicedRatio = voiced.toDouble() / frames.toDouble()

    // Solo marcamos como sospechosa una transcripción de varias palabras cuando
    // casi no hay evidencia acústica sostenida. La voz baja continua NO cae aquí.
    return meanRms < 150.0 && voicedRatio < 0.30 && strong == 0
}

/**
 * V51 - Reparaciones léxicas del BLOQUE MICRÓFONO/ESCUCHA.
 *
 * Vosk está confundiendo de forma repetida "información" con "formación"
 * en este micrófono. No modificamos Cerebras ni la lógica de comportamiento:
 * únicamente limpiamos la hipótesis de ASR antes de entregarla al resto.
 *
 * Para no impedir pedir formación real, NO corregimos cuando aparecen pistas
 * explícitas de aprendizaje/curso.
 */
fun repairVoskSpanishListeningConfusions(text: String): String {
    if (text.isBlank()) return text

    val normalized = normalizeWearableIntent(text)
    val trainingClues = listOf(
        "curso", "cursos", "aprender", "aprendizaje", "enseñanza",
        "capacitación", "capacitacion", "clase", "clases", "estudiar",
        "estudio", "estudios", "formativo", "formativa"
    )

    if (trainingClues.any { clue ->
            normalized == clue ||
                    normalized.startsWith("$clue ") ||
                    normalized.endsWith(" $clue") ||
                    normalized.contains(" $clue ")
        }) {
        return text
    }

    var repaired = text

    // Confusión observada muchas veces: información -> formación.
    repaired = repaired.replace(
        Regex("(?i)(?<![\\p{L}])formación(?![\\p{L}])"),
        "información"
    )

    // Otra salida ocasional del mismo corte silábico: "en forma me" -> "infórmame".
    repaired = repaired.replace(
        Regex("(?i)(?<![\\p{L}])en\\s+forma\\s+me(?![\\p{L}])"),
        "infórmame"
    )

    // V52: en conversación, Vosk también ha devuelto "me formas de/sobre..."
    // cuando el usuario dice "me informas de/sobre...". Solo corregimos delante
    // de una preposición informativa para no convertir usos reales de "formas".
    repaired = repaired.replace(
        Regex("(?i)(?<![\\p{L}])me\\s+formas\\s+(de|sobre|acerca\\s+de)(?![\\p{L}])"),
        "me informas $1"
    )

    // V53: caso exacto observado: "quería que me formas de...".
    // Tras la reparación anterior queda "quería que me informas de...";
    // solo en ese contexto ajustamos el tiempo verbal.
    repaired = repaired.replace(
        Regex("(?i)(?<![\\p{L}])quer[ií]a\\s+que\\s+me\\s+informas\\s+(de|sobre|acerca\\s+de)(?![\\p{L}])"),
        "quería que me informaras $1"
    )

    return repaired
}


fun joinVoskResults(endpointText: String, finalText: String, bestPartial: String): String {
    val complete = listOf(endpointText.trim(), finalText.trim())
        .filter { it.isNotBlank() }
        .joinToString(" ")
        .trim()
    val partial = bestPartial.trim()

    if (complete.isBlank()) return partial
    if (partial.isBlank()) return complete

    val completeWords = normalizeWearableIntent(complete)
        .split(" ")
        .filter { it.isNotBlank() }
    val partialWords = normalizeWearableIntent(partial)
        .split(" ")
        .filter { it.isNotBlank() }

    // V50: Vosk puede cerrar un endpoint muy corto (p. ej. una palabra) y después
    // dejar en partial la frase realmente útil. Antes, cualquier endpoint no vacío
    // hacía que ese partial se perdiera. Conservamos el resultado estable salvo en
    // dos casos muy claros donde el partial aporta más información.
    val partialHasWebCommand = hasExplicitWebRequest(partial)
    val completeHasWebCommand = hasExplicitWebRequest(complete)

    if (partialHasWebCommand && !completeHasWebCommand) {
        return partial
    }

    // V52: caso observado: endpoint="de un poco de" y partial="hablar de un poco de".
    // Si el partial es la misma frase con palabras útiles delante, conservamos el inicio.
    val completeNorm = completeWords.joinToString(" ")
    val partialNorm = partialWords.joinToString(" ")
    if (
        partialWords.size > completeWords.size &&
        completeNorm.isNotBlank() &&
        partialNorm.endsWith(completeNorm)
    ) {
        return partial
    }

    if (completeWords.size <= 2 && partialWords.size >= completeWords.size + 2) {
        return partial
    }

    return complete
}


fun shouldUseWebSearch(question: String): Boolean = webSearchTrigger(question) != null

fun webSearchTrigger(question: String): String? {
    if (declinesWebSearch(question)) return null
    if (hasExplicitWebRequest(question)) return "explicit_search_or_identification_request"
    val q = question.lowercase(Locale("es", "ES"))

    // Peticiones explícitas de usar Internet.
    val explicit = listOf(
        "busca en internet",
        "busca por internet",
        "búscalo en internet",
        "buscalo en internet",
        "búscalo por internet",
        "buscalo por internet",
        "busca información",
        "busca informacion",
        "busca información en internet",
        "busca informacion en internet",
        "mira en internet",
        "mira por internet",
        "míralo en internet",
        "miralo en internet",
        "consulta internet",
        "consulta en internet",
        "consulta por internet",
        "comprueba en internet",
        "comprueba por internet",
        "verifica en internet",
        "verifica por internet",
        "búscame",
        "buscame"
    )

    explicit.firstOrNull { q.contains(it) }?.let { return "explicit_phrase=$it" }

    // Temas que por definición necesitan información actual.
    val liveTopics = listOf(
        "noticias",
        "última hora",
        "ultima hora",
        "últimas noticias",
        "ultimas noticias",
        "actualidad",
        "qué está pasando",
        "que esta pasando",
        "qué pasa en",
        "que pasa en",
        "meteorología",
        "meteorologia",
        "pronóstico",
        "pronostico",
        "previsión del tiempo",
        "prevision del tiempo",
        "el tiempo en",
        "tiempo en",
        "temperatura actual",
        "tráfico",
        "trafico"
    )

    liveTopics.firstOrNull { q.contains(it) }?.let { return "live_topic=$it" }

    // Palabras de frescura combinadas con una consulta informativa.
    val freshness = listOf(
        "hoy",
        "ahora",
        "actualmente",
        "actual",
        "último",
        "ultimo",
        "última",
        "ultima",
        "reciente",
        "recientes",
        "esta semana",
        "este mes",
        "precio actual",
        "cotización",
        "cotizacion"
    )

    // V53 COMPORTAMIENTO/LÓGICA: "que" es demasiado genérico.
    // Evita disparos como "quiero que me digas ahora mismo...".
    // No se toca Tavily ni ninguna conexión web externa: solo la decisión previa.
    val informational = listOf(
        "cuál",
        "cual",
        "cómo",
        "como",
        "dónde",
        "donde",
        "precio",
        "noticia",
        "tiempo",
        "meteorología",
        "meteorologia",
        "tráfico",
        "trafico"
    )

    val freshWord = freshness.firstOrNull { q.contains(it) }
    val informationWord = informational.firstOrNull { q.contains(it) }
    return if (freshWord != null && informationWord != null) "freshness=$freshWord information=$informationWord" else null
}

suspend fun searchWebWithTavily(
    context: Context,
    apiKey: String,
    query: String
): TextResult = withContext(Dispatchers.IO) {
    var connection: HttpURLConnection? = null

    try {
        if (apiKey.isBlank()) {
            return@withContext TextResult(false, error = "Falta API key de Tavily")
        }

        if (query.isBlank()) {
            return@withContext TextResult(false, error = "Consulta web vacía")
        }

        val url = URL("https://api.tavily.com/search")

        // La búsqueda web debe salir por datos móviles, no por el AP del XIAO.
        val cm =
            context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        val cellularNetwork =
            getCellularInternetNetwork(context)

        // Fallback: cualquier red validada con Internet que NO sea la del XIAO.
        val fallbackInternetNetwork =
            cm.allNetworks.firstOrNull { network ->
                if (network == activeXiaoNetwork) return@firstOrNull false

                val caps =
                    cm.getNetworkCapabilities(network)
                        ?: return@firstOrNull false

                caps.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_INTERNET
                ) &&
                        caps.hasCapability(
                            NetworkCapabilities.NET_CAPABILITY_VALIDATED
                        )
            }

        val internetNetwork =
            cellularNetwork ?: fallbackInternetNetwork

        if (internetNetwork == null) {
            return@withContext TextResult(
                false,
                error =
                    "No encuentro una red móvil/Internet válida para Tavily. " +
                            "El XIAO sigue conectado por su Wi-Fi local."
            )
        }

        connection =
            internetNetwork.openConnection(url) as HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = 10_000
        connection.readTimeout = 20_000
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json")
        connection.setRequestProperty("Authorization", "Bearer ${apiKey.trim()}")

        val body = JSONObject()
            .put("query", query)
            .put("search_depth", "basic")
            .put("topic", "general")
            .put("max_results", 5)
            .put("include_answer", true)
            .put("include_raw_content", false)
            .put("include_images", false)
            .put("include_published_date", true)
            .put("language", "es")
            .toString()

        connection.outputStream.use { out ->
            out.write(body.toByteArray(Charsets.UTF_8))
            out.flush()
        }

        val code = connection.responseCode
        val raw =
            if (code in 200..299) {
                connection.inputStream.bufferedReader().use { it.readText() }
            } else {
                connection.errorStream?.bufferedReader()?.use { it.readText() }
                    ?: "HTTP $code"
            }

        if (code !in 200..299) {
            return@withContext TextResult(
                false,
                error = "Tavily HTTP $code: ${raw.take(800)}"
            )
        }

        val json = JSONObject(raw)
        val answer = json.optString("answer", "").trim()
        val results = json.optJSONArray("results")

        val formatted = buildString {
            if (answer.isNotBlank()) {
                append("RESUMEN DE BÚSQUEDA:\n")
                append(answer.take(3_500))
                append("\n\n")
            }

            if (results != null) {
                append("FUENTES:\n")
                for (i in 0 until minOf(results.length(), 5)) {
                    val item = results.optJSONObject(i) ?: continue
                    val title = item.optString("title", "").trim()
                    val content = item.optString("content", "").trim()
                    val sourceUrl = item.optString("url", "").trim()
                    val published = item.optString("published_date", "").trim()

                    append("${i + 1}. ")
                    if (title.isNotBlank()) append(title)
                    if (published.isNotBlank()) append(" · ").append(published)
                    append("\n")
                    if (content.isNotBlank()) append(content.take(1_200)).append("\n")
                    if (sourceUrl.isNotBlank()) append("URL: ").append(sourceUrl).append("\n")
                    append("\n")
                }
            }
        }.trim()

        if (formatted.isBlank()) {
            TextResult(false, error = "Tavily no devolvió resultados útiles")
        } else {
            val usedCaps = cm.getNetworkCapabilities(internetNetwork)
            val transport =
                when {
                    usedCaps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true ->
                        "DATOS MÓVILES"
                    usedCaps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true ->
                        "WI-FI"
                    else ->
                        "OTRA RED"
                }

            TextResult(
                true,
                text = "RED WEB: $transport\n\n$formatted"
            )
        }

    } catch (e: Exception) {
        TextResult(
            false,
            error = "${e.javaClass.simpleName}: ${e.message ?: "sin detalle"}"
        )
    } finally {
        connection?.disconnect()
    }
}


// =====================================================
// CEREBRAS - PREGUNTA DE TEXTO
// V15: Qwen 3.8 27B con reasoning desactivado para evitar respuestas vacías.
// =====================================================
suspend fun askCerebrasWithText(
    context: Context,
    apiKey: String,
    userText: String,
    visualContext: String = "",
    multimodalMemory: String = "",
    webContext: String = ""
): TextResult = withContext(Dispatchers.IO) {
    var connection: HttpURLConnection? = null

    try {
        if (apiKey.isBlank()) {
            return@withContext TextResult(false, error = "Falta API key de Cerebras")
        }

        if (userText.isBlank()) {
            return@withContext TextResult(false, error = "Pregunta vacía")
        }

        val url = URL("https://api.cerebras.ai/v1/chat/completions")

        // Cerebras NO debe salir por el Wi-Fi/AP del XIAO.
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val internetNetwork = cm.allNetworks.firstOrNull { network ->
            if (network == activeXiaoNetwork) return@firstOrNull false
            val caps = cm.getNetworkCapabilities(network) ?: return@firstOrNull false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        }

        if (internetNetwork == null) {
            return@withContext TextResult(
                false,
                error = "Sin Internet disponible para Cerebras. El XIAO sigue conectado por su Wi-Fi."
            )
        }

        connection = internetNetwork.openConnection(url) as HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = 10_000
        connection.readTimeout = 30_000
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json")
        connection.setRequestProperty("Authorization", "Bearer ${apiKey.trim()}")

        val messages = org.json.JSONArray()
            .put(
                JSONObject()
                    .put("role", "system")
                    .put(
                        "content",
                        "Eres el asistente de voz de un wearable con cámara. " +
                                "Responde en español de forma breve, natural y útil. " +
                                "REGLA PRINCIPAL: responde primero a la PREGUNTA ACTUAL del usuario. " +
                                "El contexto visual es memoria INTERNA: úsalo para entender y responder, pero NO lo narres ni lo enumeres por iniciativa propia. " +
                                "Responde únicamente a lo que se ha preguntado, con una cantidad de detalle natural y proporcional a lo interesante o importante del objeto. " +
                                "Si pregunta '¿qué es esto?', '¿qué es eso?' o equivalente y puedes identificarlo, di primero qué es. Si es algo cotidiano, basta una respuesta breve; si es un monumento, obra, disco, producto, aparato o elemento notable, añade de forma natural 1 a 3 datos realmente útiles o interesantes (por ejemplo autor, fecha, por qué es conocido, función o rasgo distintivo), sin convertir la respuesta en una descripción de toda la escena. " +
                                "Ejemplo: si pregunta '¿me estás viendo?', responde solo si lo ves o no; no describas el fondo, objetos, ropa ni otros detalles salvo que el usuario los pida. " +
                                "Solo describe la escena completa cuando el usuario pida explícitamente una descripción o pregunte qué hay/qué ves en general. " +
                                "Mantén toda la respuesta en español, salvo nombres propios y títulos. " +
                                "Si el usuario dice 'que viste', 'que vimos', 'antes' o 'no hace falta que lo mires otra vez', resuelve el objeto con la MEMORIA VISUAL y la conversación. No exijas volver a enfocarlo por estar ahora fuera de cámara. Si no consta en la memoria, dilo sin inventar. " +
                                "No interpretes 'no hace falta que lo mires otra vez' como una orden de abandonar el tema: sigue respondiendo sobre el objeto recordado. " +
                                "La voz puede contener errores de transcripción: interpreta referencias como 'poste', 'post' o 'puesto' según el contexto, sin sustituirlas automáticamente. Si encajan varios objetos o una negación es ambigua, pide una aclaración breve. " +
                                "Si se informa de BÚSQUEDA WEB NO DISPONIBLE, explica brevemente la limitación y no afirmes haber consultado fuentes. " +
                                "Si el usuario dice 'continúa', 'sigue', 'eso', 'esto', 'lo anterior' o una referencia parecida, usa de forma explícita el último turno relevante de la memoria de conversación. " +
                                "El contexto de conversación y el contexto de cámara son apoyo para entender referencias, continuidad y objetos visibles; nunca sustituyen la pregunta actual. " +
                                "Si la pregunta es conceptual, explica el concepto; no te limites a repetir texto visible. " +
                                "Si el usuario pregunta específicamente qué ves, qué pone, qué estás viendo, qué tienes delante o por un objeto visible, usa el contexto de cámara. " +
                                "Cuando haya resultados de búsqueda web, puedes utilizarlos para información actual. No digas que no tienes Internet si se te han proporcionado resultados web. " +
                                "No inventes detalles que no estén en la pregunta o en el contexto disponible."
                    )
            )
            .put(
                JSONObject()
                    .put("role", "user")
                    .put(
                        "content",
                        """PREGUNTA ACTUAL DEL USUARIO — PRIORIDAD MÁXIMA:
$userText

CONTEXTO RECIENTE DE CONVERSACIÓN Y ENTORNO — SOLO COMO APOYO:
Memoria cronológica de lo visto y lo hablado:
${if (multimodalMemory.isBlank()) "(vacía)" else multimodalMemory.takeLast(24_000)}

Última descripción disponible de la cámara del XIAO:
${if (visualContext.isBlank()) "(sin descripción reciente)" else visualContext.takeLast(6_000)}

RESULTADOS DE BÚSQUEDA WEB RECIENTE — ÚSALOS SOLO SI SON RELEVANTES:
${if (webContext.isBlank()) "(no se realizó búsqueda web para esta pregunta)" else webContext.takeLast(10_000)}

Fecha y hora del teléfono: ${java.time.ZonedDateTime.now().format(java.time.format.DateTimeFormatter.ofPattern("EEEE d 'de' MMMM 'de' yyyy, HH:mm:ss z", java.util.Locale("es", "ES")))}
Zona horaria: ${java.time.ZoneId.systemDefault().id}

INSTRUCCIÓN: contesta exactamente a la pregunta actual. Usa el contexto solo cuando ayude a contestarla o a resolver referencias como 'eso', 'esto', 'ahí' o 'lo que pone'. No repitas el contexto si no responde a lo preguntado.
El contexto visual es silencioso e interno: no lo vuelques en la respuesta. Ajusta la extensión con naturalidad: identifica primero y, si lo identificado es relevante o notable, añade unos pocos datos útiles sin describir toda la escena.
No afirmes una ubicación exacta solo por una imagen; si el usuario la dice explícitamente, puedes conservarla como contexto aportado por él.""".trimIndent()
                    )
            )

        // Qwen 3.8 27B: para el asistente de voz pedimos respuesta directa
        // y evitamos consumir el límite de salida en razonamiento.
        val body = JSONObject()
            .put("model", "qwen-3.8-27b")
            .put("messages", messages)
            .put("reasoning_effort", "none")
            .put("max_completion_tokens", 500)
            .toString()

        connection.outputStream.use {
            it.write(body.toByteArray(Charsets.UTF_8))
            it.flush()
        }

        val code = connection.responseCode
        val raw = if (code in 200..299) {
            connection.inputStream.bufferedReader().use { it.readText() }
        } else {
            connection.errorStream?.bufferedReader()?.use { it.readText() }
                ?: "HTTP $code"
        }

        if (code !in 200..299) {
            return@withContext TextResult(false, error = "HTTP $code: ${raw.take(1000)}")
        }

        val json = JSONObject(raw)
        val choices = json.optJSONArray("choices")
            ?: return@withContext TextResult(false, error = "Cerebras sin choices: ${raw.take(700)}")

        if (choices.length() == 0) {
            return@withContext TextResult(false, error = "Cerebras sin respuesta: ${raw.take(700)}")
        }

        val choice = choices.getJSONObject(0)
        val finishReason = choice.optString("finish_reason", "")
        val message = choice.optJSONObject("message")
            ?: return@withContext TextResult(false, error = "Cerebras sin message: ${raw.take(700)}")

        val answer = when (val content = message.opt("content")) {
            is String -> content.trim()
            is org.json.JSONArray -> {
                buildString {
                    for (i in 0 until content.length()) {
                        val part = content.optJSONObject(i) ?: continue
                        if (part.optString("type") == "text") {
                            append(part.optString("text"))
                        }
                    }
                }.trim()
            }
            else -> ""
        }

        if (answer.isBlank()) {
            val reasoningChars = message.optString("reasoning", "").length
            return@withContext TextResult(
                false,
                error = "Cerebras devolvió contenido vacío · finish=$finishReason · reasoning=$reasoningChars chars"
            )
        }

        TextResult(true, text = answer)

    } catch (e: Exception) {
        TextResult(false, error = "${e.javaClass.simpleName}: ${e.message ?: "sin detalle"}")
    } finally {
        connection?.disconnect()
    }
}


// =====================================================
// CEREBRAS - PRUEBA REAL DE API
// =====================================================
suspend fun testGeminiApi(apiKey: String): TextResult =
    withContext(Dispatchers.IO) {
        var connection: HttpURLConnection? = null
        try {
            val url = URL("https://api.cerebras.ai/v1/chat/completions")
            connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.connectTimeout = 10_000
            connection.readTimeout = 30_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Authorization", "Bearer ${apiKey.trim()}")

            val body = JSONObject()
                .put("model", "qwen-3.8-27b")
                .put(
                    "messages",
                    org.json.JSONArray().put(
                        JSONObject()
                            .put("role", "user")
                            .put("content", "Responde solamente: Wearable AI conectado.")
                    )
                )
                .put("reasoning_effort", "none")
                .put("max_completion_tokens", 100)
                .toString()

            connection.outputStream.use {
                it.write(body.toByteArray(Charsets.UTF_8))
                it.flush()
            }

            val code = connection.responseCode
            val raw = if (code in 200..299) {
                connection.inputStream.bufferedReader().use { it.readText() }
            } else {
                connection.errorStream?.bufferedReader()?.use { it.readText() }
                    ?: "HTTP $code"
            }

            if (code !in 200..299) {
                return@withContext TextResult(false, error = "HTTP $code: ${raw.take(1000)}")
            }

            val json = JSONObject(raw)
            val choices = json.optJSONArray("choices")
                ?: return@withContext TextResult(false, error = "Cerebras sin choices: ${raw.take(700)}")
            if (choices.length() == 0) {
                return@withContext TextResult(false, error = "Cerebras sin respuesta: ${raw.take(700)}")
            }

            val choice = choices.getJSONObject(0)
            val message = choice.optJSONObject("message")
                ?: return@withContext TextResult(false, error = "Cerebras sin message: ${raw.take(700)}")
            val answer = message.optString("content", "").trim()

            if (answer.isBlank()) {
                val finishReason = choice.optString("finish_reason", "")
                val reasoningChars = message.optString("reasoning", "").length
                TextResult(
                    false,
                    error = "Respuesta vacía · finish=$finishReason · reasoning=$reasoningChars chars"
                )
            } else {
                TextResult(true, text = answer)
            }

        } catch (e: Exception) {
            TextResult(false, error = "${e.javaClass.simpleName}: ${e.message ?: "sin detalle"}")
        } finally {
            connection?.disconnect()
        }
    }


// =====================================================
// RESULTADOS HTTP
// =====================================================

data class TextResult(
    val success: Boolean,
    val text: String = "",
    val error: String = ""
)


data class BytesResult(
    val success: Boolean,
    val data: ByteArray =
        byteArrayOf(),
    val error: String = ""
)



// =====================================================
// BARGE-IN RÁPIDO DURANTE TTS
// =====================================================
fun removeDcOffsetPcm16(input: ByteArray): ByteArray {
    if (input.size < 4) return input

    val sampleCount = input.size / 2
    var sum = 0L

    for (i in 0 until sampleCount) {
        val lo = input[i * 2].toInt() and 0xFF
        val hi = input[i * 2 + 1].toInt()
        val s = ((hi shl 8) or lo).toShort().toInt()
        sum += s.toLong()
    }

    val dc = sum.toDouble() / sampleCount.toDouble()
    val out = ByteArray(sampleCount * 2)

    for (i in 0 until sampleCount) {
        val lo = input[i * 2].toInt() and 0xFF
        val hi = input[i * 2 + 1].toInt()
        val s = ((hi shl 8) or lo).toShort().toInt()

        val centered = (s.toDouble() - dc)
            .toInt()
            .coerceIn(-32768, 32767)

        out[i * 2] = (centered and 0xFF).toByte()
        out[i * 2 + 1] = ((centered shr 8) and 0xFF).toByte()
    }

    return out
}

fun isFastStopCommand(text: String): Boolean {
    val q = normalizeSpeechForComparison(text)

    if (q.isBlank()) return false

    val strongCommands = listOf(
        "callate",
        "cállate",
        "calla",
        "silencio",
        "detente",
        "parate",
        "párate",
        "stop",
        "para ya",
        "para para",
        "basta",
        "deja de hablar",
        "no sigas",
        "no hables"
    )

    if (strongCommands.any { cmd ->
            val normalizedCmd = normalizeSpeechForComparison(cmd)
            q == normalizedCmd ||
                    q.startsWith("$normalizedCmd ") ||
                    q.endsWith(" $normalizedCmd") ||
                    q.contains(" $normalizedCmd ")
        }) {
        return true
    }

    // "para" y "espera" solos sí son órdenes, pero no queremos que
    // "para qué..." o "espera que te diga..." corten por accidente.
    return q == "para" ||
            q == "para por favor" ||
            q == "para un momento" ||
            q == "espera" ||
            q == "espera un momento"
}


// =====================================================
// BARGE-IN / INTERRUPCIÓN DE VOZ
// =====================================================
fun normalizeSpeechForComparison(text: String): String {
    return text
        .lowercase(Locale("es", "ES"))
        .replace(Regex("""[^\p{L}\p{N}\s]"""), " ")
        .replace(Regex("""\s+"""), " ")
        .trim()
}

fun looksLikeAssistantEcho(
    heardText: String,
    assistantText: String
): Boolean {
    val heard = normalizeWearableIntent(heardText)
    val assistant = normalizeWearableIntent(assistantText)
    if (heard.isBlank() || assistant.isBlank()) return false
    if (" $assistant ".contains(" $heard ")) return true
    val heardWords = heard.split(" ")
    if (heardWords.size < 2) return false
    val assistantWords = assistant.split(" ").toSet()
    val matched = heardWords.count { it in assistantWords }
    return matched >= 2 && matched.toDouble() / heardWords.size >= 0.80
}


suspend fun playPcmInterruptible(
    context: Context,
    ip: String,
    pcm: ByteArray,
    interruptRequested: java.util.concurrent.atomic.AtomicBoolean
): TextResult = withContext(Dispatchers.IO) {

    if (pcm.isEmpty()) {
        return@withContext TextResult(false, error = "PCM vacío")
    }

    // PCM16 mono 16 kHz = 32.000 bytes/seg.
    // V43: 0,40 s por trozo (12.800 bytes).
    // Reducimos a la mitad el número de POST /play_audio para evitar los
    // microcortes entre trozos, manteniendo una latencia de interrupción baja.
    val chunkBytes = 12_800

    var offset = 0
    var chunkIndex = 0
    val playbackId = DiagRuntime.nextId()
    val playbackStartedAt = android.os.SystemClock.elapsedRealtime()
    DiagRuntime.playbackStart()
    diag(
        context,
        "PLAYBACK_START",
        "id=$playbackId totalBytes=${pcm.size} chunkBytes=$chunkBytes ip=$ip state=${DiagRuntime.snapshot()}"
    )
    diag(
        context,
        "FULL_DUPLEX_TEST",
        "mode=separate_input_playback_gates expected=mic_and_play_can_overlap"
    )

    try {
        while (offset < pcm.size) {
            if (interruptRequested.get()) {
                diag(
                    context,
                    "PLAYBACK_INTERRUPT_FLAG",
                    "beforeChunk=$chunkIndex offset=$offset"
                )
                return@withContext TextResult(true, text = "INTERRUPTED")
            }

            val end = minOf(offset + chunkBytes, pcm.size)
            val chunk = pcm.copyOfRange(offset, end)
            val startedAt = android.os.SystemClock.elapsedRealtime()

            val sent = httpPostBytes(
                ip = ip,
                endpoint = "/play_audio",
                data = chunk,
                contentType = "application/octet-stream"
            )

            val elapsed =
                android.os.SystemClock.elapsedRealtime() - startedAt

            diag(
                context,
                "PLAYBACK_CHUNK",
                "id=$playbackId index=$chunkIndex bytes=${chunk.size} offset=$offset elapsedMs=$elapsed success=${sent.success} error=${sent.error.take(300)} state=${DiagRuntime.snapshot()}"
            )

            if (!sent.success) {
                return@withContext sent
            }

            offset = end
            chunkIndex++

            // V55: mantenemos el turno del micrófono SIN introducir silencio fijo.
            // El Mutex ya deja a /mic_sample esperando mientras se envía este chunk;
            // al liberar el gate cedemos cooperativamente el hilo para que ese waiter
            // pueda entrar antes del siguiente /play_audio. Así conservamos el barge-in
            // pero eliminamos la pausa artificial de 25 ms que podía oírse como entrecorte.
            if (offset < pcm.size && !interruptRequested.get()) {
                kotlinx.coroutines.yield()
            }
        }

        if (interruptRequested.get()) {
            TextResult(true, text = "INTERRUPTED")
        } else {
            TextResult(true, text = "PLAYED")
        }
    } finally {
        DiagRuntime.playbackEnd()
        val totalElapsed = android.os.SystemClock.elapsedRealtime() - playbackStartedAt
        diag(
            context,
            "PLAYBACK_END",
            "id=$playbackId chunks=$chunkIndex sentBytes=$offset totalBytes=${pcm.size} elapsedMs=$totalElapsed interrupted=${interruptRequested.get()} state=${DiagRuntime.snapshot()}"
        )
    }
}


// =====================================================
// HTTP POST BYTES AL XIAO
// =====================================================

// =====================================================
// AJUSTES DE VOZ
// DaveFX tiene mucha más salida que Miro.
// =====================================================

fun ttsGainForVoice(voiceName: String): Float {
    return when {
        voiceName.contains("davefx", ignoreCase = true) -> 0.60f
        voiceName.contains("miro", ignoreCase = true) -> 2.80f
        voiceName.contains("sharvard", ignoreCase = true) -> 1.00f
        else -> 1.00f
    }
}

fun limitSpeechText(input: String, maxChars: Int = 320): String {
    val clean = input.trim()
    if (clean.length <= maxChars) return clean

    val candidate = clean.take(maxChars)
    val lastSentenceEnd = maxOf(
        candidate.lastIndexOf(". "),
        candidate.lastIndexOf("! "),
        candidate.lastIndexOf("? ")
    )

    return if (lastSentenceEnd >= 120) {
        candidate.take(lastSentenceEnd + 1).trim()
    } else {
        candidate.trimEnd().trimEnd(',', ';', ':', '-') + "."
    }
}

fun boostPcm16Volume(data: ByteArray, gain: Float = 1.0f): ByteArray {
    if (data.size < 2 || gain <= 0.0f || gain == 1.0f) return data
    val out = data.copyOf()
    var i = 0
    while (i + 1 < out.size) {
        val lo = out[i].toInt() and 0xFF
        val hi = out[i + 1].toInt()
        val sample = ((hi shl 8) or lo).toShort().toInt()
        val amplified = (sample * gain).toInt().coerceIn(-32768, 32767)
        out[i] = (amplified and 0xFF).toByte()
        out[i + 1] = ((amplified shr 8) and 0xFF).toByte()
        i += 2
    }
    return out
}

suspend fun httpPostBytes(
    ip: String,
    endpoint: String,
    data: ByteArray,
    contentType: String = "application/octet-stream"
): TextResult = withContext(Dispatchers.IO) {
    // V57 FULL-DUPLEX TEST:
    // /play_audio usa su propio gate. Esto permite que /mic_sample pueda entrar
    // al mismo tiempo y nos dice si el firmware/servidor HTTP del XIAO soporta
    // entrada y salida concurrentes de verdad. Cámara y demás GET siguen serializados.
    xiaoPlaybackGate.lock()
    var connection: HttpURLConnection? = null

    try {
        val url = URL("http://${ip.trim()}$endpoint")
        val boundary = "----WearableAI${System.currentTimeMillis()}"

        val prefix = (
                "--$boundary\r\n" +
                        "Content-Disposition: form-data; name=\"file\"; filename=\"audio.pcm\"\r\n" +
                        "Content-Type: $contentType\r\n\r\n"
                ).toByteArray(Charsets.UTF_8)

        val suffix = "\r\n--$boundary--\r\n".toByteArray(Charsets.UTF_8)
        val totalLength = prefix.size + data.size + suffix.size

        connection = openXiaoConnectionStrict(url)

        connection.requestMethod = "POST"
        connection.connectTimeout = 5_000
        connection.readTimeout = 30_000
        connection.doOutput = true
        connection.setRequestProperty(
            "Content-Type",
            "multipart/form-data; boundary=$boundary"
        )
        connection.setFixedLengthStreamingMode(totalLength)

        connection.outputStream.use { out ->
            out.write(prefix)
            out.write(data)
            out.write(suffix)
            out.flush()
        }

        val code = connection.responseCode
        val text = if (code in 200..299) {
            connection.inputStream?.bufferedReader()?.use { it.readText() }.orEmpty()
        } else {
            connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
        }

        if (code in 200..299) {
            TextResult(
                success = true,
                text = "HTTP $code · audio=${data.size} bytes · $text"
            )
        } else {
            TextResult(
                success = false,
                error = "HTTP $code · audio=${data.size} bytes · $text"
            )
        }
    } catch (e: Exception) {
        TextResult(
            success = false,
            error = "${e.javaClass.simpleName}: ${e.message ?: "sin detalle"} · audio=${data.size} bytes"
        )
    } finally {
        connection?.disconnect()
        xiaoPlaybackGate.unlock()
    }
}

// =====================================================
data class TtsVoiceOption(
    val name: String,
    val label: String
)

suspend fun loadSpanishTtsVoices(
    context: Context
): List<TtsVoiceOption> = withContext(Dispatchers.IO) {
    listOf(
        TtsVoiceOption(
            name = "sherpa-es_ES-miro-high",
            label = "Sherpa · Miro High · español · local"
        ),
        TtsVoiceOption(
            name = "sherpa-es_ES-davefx-medium",
            label = "Sherpa · DaveFX Medium · español · local"
        ),
        TtsVoiceOption(
            name = "sherpa-es_ES-sharvard-medium-m",
            label = "Sherpa · Sharvard M · español · local"
        ),
        TtsVoiceOption(
            name = "sherpa-es_ES-sharvard-medium-f",
            label = "Sherpa · Sharvard F · español · local"
        )
    )
}


// =====================================================
// LIMPIEZA DE TEXTO PARA HABLAR
// Evita que Android TTS lea símbolos de Markdown.
// NO modifica la respuesta guardada en memoria.
// =====================================================
fun cleanTextForSpeech(input: String): String {
    return input
        // Enlaces Markdown: [texto](url) -> texto
        .replace(Regex("""\[([^\]]+)]\(([^)]+)\)"""), "$1")
        // Negrita/cursiva/encabezados/código Markdown.
        .replace("**", "")
        .replace("__", "")
        .replace("*", "")
        .replace("_", " ")
        .replace("`", "")
        .replace("#", "")
        // Viñetas comunes al principio de línea.
        .replace(Regex("""(?m)^\s*[-•]+\s*"""), "")
        // Evita espacios raros después de quitar formato.
        .replace(Regex("""[ \t]{2,}"""), " ")
        .replace(Regex("""\n{3,}"""), "\n\n")
        .trim()
}


// =====================================================
// SHERPA-ONNX LOCAL EMBEBIDO -> PCM16 MONO
// Los modelos viven dentro de app/src/main/assets/sherpa_tts/.
// =====================================================
private object SherpaEmbeddedTts {
    private const val ASSET_MODEL_DIR = "sherpa_tts"

    private data class VoiceProfile(
        val modelCandidates: List<String>,
        val jsonCandidates: List<String>,
        val tokensCandidates: List<String>,
        val sid: Int,
        val expectedSha256: String? = null
    )

    private val engines = mutableMapOf<String, OfflineTts>()
    private val verifiedHashes = mutableMapOf<String, String>()

    private fun profileFor(voiceName: String): VoiceProfile = when (voiceName) {
        "sherpa-es_ES-davefx-medium" -> VoiceProfile(
            modelCandidates = listOf(
                "davefx/es_ES-davefx-medium.onnx",
                "davefx/es_ES-davefx-medium.onnx.txt"
            ),
            jsonCandidates = listOf("davefx/es_ES-davefx-medium.onnx.json"),
            tokensCandidates = listOf("davefx/tokens.txt"),
            sid = 0,
            expectedSha256 = "329fc723ef304f8688df9ef819eea169a4181f60a77f53e087b19dbca07b09f8"
        )
        "sherpa-es_ES-sharvard-medium-m" -> VoiceProfile(
            modelCandidates = listOf(
                "sharvard/es_ES-sharvard-medium.onnx",
                "es_ES-sharvard-medium.onnx"
            ),
            jsonCandidates = listOf(
                "sharvard/es_ES-sharvard-medium.onnx.json",
                "es_ES-sharvard-medium.onnx.json"
            ),
            tokensCandidates = listOf("sharvard/tokens.txt", "tokens-sharvard.txt"),
            sid = 0,
            expectedSha256 = "f26006cd03e2d558966fa3c49cfa9361dfa22d72197d74b6b50437cb02b8faaf"
        )
        "sherpa-es_ES-sharvard-medium-f" -> VoiceProfile(
            modelCandidates = listOf(
                "sharvard/es_ES-sharvard-medium.onnx",
                "es_ES-sharvard-medium.onnx"
            ),
            jsonCandidates = listOf(
                "sharvard/es_ES-sharvard-medium.onnx.json",
                "es_ES-sharvard-medium.onnx.json"
            ),
            tokensCandidates = listOf("sharvard/tokens.txt", "tokens-sharvard.txt"),
            sid = 1,
            expectedSha256 = "f26006cd03e2d558966fa3c49cfa9361dfa22d72197d74b6b50437cb02b8faaf"
        )
        else -> VoiceProfile(
            modelCandidates = listOf("es_ES-miro-high.onnx"),
            jsonCandidates = listOf("es_ES-miro-high.onnx.json"),
            tokensCandidates = listOf("tokens.txt"),
            sid = 0,
            expectedSha256 = null
        )
    }

    private fun ensureAssetTreeCopied(context: Context, modelDir: File) {
        copyAssetDirectory(
            context = context.applicationContext,
            assetPath = ASSET_MODEL_DIR,
            destination = modelDir
        )
    }

    private fun firstExisting(base: File, candidates: List<String>): File? {
        return candidates
            .map { File(base, it) }
            .firstOrNull { it.exists() && it.isFile }
    }

    private fun sha256(file: File): String {
        verifiedHashes[file.absolutePath]?.let { return it }
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(256 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                md.update(buffer, 0, read)
            }
        }
        val result = md.digest().joinToString("") { "%02x".format(it) }
        verifiedHashes[file.absolutePath] = result
        return result
    }

    private fun generateTokensFromPiperJson(jsonFile: File, outputFile: File) {
        val root = JSONObject(jsonFile.readText(Charsets.UTF_8))
        val map = root.getJSONObject("phoneme_id_map")
        val lines = mutableListOf<Pair<Int, String>>()
        val keys = map.keys()
        while (keys.hasNext()) {
            val token = keys.next()
            val id = map.getJSONArray(token).getInt(0)
            lines += id to token
        }
        outputFile.parentFile?.mkdirs()
        outputFile.bufferedWriter(Charsets.UTF_8).use { out ->
            for ((id, token) in lines.sortedBy { it.first }) {
                out.write(token)
                out.write(" ")
                out.write(id.toString())
                out.newLine()
            }
        }
    }

    @Synchronized
    private fun getOrCreate(context: Context, voiceName: String): Pair<OfflineTts, Int> {
        val normalizedVoice = voiceName.ifBlank { "sherpa-es_ES-miro-high" }
        val profile = profileFor(normalizedVoice)
        engines[normalizedVoice]?.let { return it to profile.sid }

        val appContext = context.applicationContext
        val modelDir = File(appContext.filesDir, ASSET_MODEL_DIR)
        ensureAssetTreeCopied(appContext, modelDir)

        val modelFile = firstExisting(modelDir, profile.modelCandidates)
            ?: throw IllegalStateException(
                "No encuentro el modelo para $normalizedVoice. Esperaba: ${profile.modelCandidates.joinToString()}"
            )

        if (modelFile.length() < 1_000_000L) {
            throw IllegalStateException(
                "El modelo ${modelFile.name} está incompleto (${modelFile.length()} bytes). No se carga para evitar que la app se cierre."
            )
        }

        // DaveFX y Sharvard tienen una variante preparada específicamente para sherpa-onnx.
        // Verificamos el hash antes de entrar en código nativo; un Piper original distinto
        // puede provocar un cierre nativo que Kotlin no puede capturar.
        profile.expectedSha256?.let { expected ->
            val actual = sha256(modelFile)
            if (!actual.equals(expected, ignoreCase = true)) {
                throw IllegalStateException(
                    "El archivo ${modelFile.name} no es la versión preparada para Sherpa. " +
                            "SHA256=$actual. Sustituye el modelo por el de csukuangfj/k2-fsa."
                )
            }
        }

        val espeakDir = File(modelDir, "espeak-ng-data")
        if (!espeakDir.exists() || !espeakDir.isDirectory) {
            throw IllegalStateException("Falta ${espeakDir.absolutePath}")
        }

        var tokensFile = firstExisting(modelDir, profile.tokensCandidates)
        if (tokensFile == null || tokensFile.length() == 0L) {
            val jsonFile = firstExisting(modelDir, profile.jsonCandidates)
                ?: throw IllegalStateException(
                    "Faltan tokens y JSON para $normalizedVoice"
                )
            val generated = File(modelDir, when {
                normalizedVoice.contains("davefx") -> "davefx/tokens-generated.txt"
                normalizedVoice.contains("sharvard") -> "tokens-sharvard.txt"
                else -> "tokens-generated.txt"
            })
            generateTokensFromPiperJson(jsonFile, generated)
            tokensFile = generated
        }

        diag(
            appContext,
            "SHERPA_FILES_READY",
            "voice=$normalizedVoice model=${modelFile.length()} tokens=${tokensFile.length()} sid=${profile.sid}"
        )

        val config = OfflineTtsConfig(
            model = OfflineTtsModelConfig(
                vits = OfflineTtsVitsModelConfig(
                    model = modelFile.absolutePath,
                    tokens = tokensFile.absolutePath,
                    dataDir = espeakDir.absolutePath,
                    noiseScale = 0.667f,
                    noiseScaleW = 0.8f,
                    lengthScale = 1.0f
                ),
                numThreads = 2,
                debug = false,
                provider = "cpu"
            ),
            maxNumSentences = 1,
            silenceScale = 0.2f
        )

        val created = OfflineTts(
            assetManager = null,
            config = config
        )
        engines[normalizedVoice] = created
        diag(appContext, "SHERPA_ENGINE_READY", "voice=$normalizedVoice sid=${profile.sid}")
        return created to profile.sid
    }

    fun generate(
        context: Context,
        text: String,
        voiceName: String
    ): Pair<Int, ByteArray> {
        val (tts, sid) = getOrCreate(context, voiceName)
        val audio = tts.generateWithConfig(
            text = text,
            config = GenerationConfig(
                sid = sid,
                speed = 1.0f,
                silenceScale = 0.2f
            )
        )

        val pcm = ByteArray(audio.samples.size * 2)
        var p = 0
        for (sample in audio.samples) {
            val v = (sample.coerceIn(-1.0f, 1.0f) * 32767.0f).toInt()
            pcm[p++] = (v and 0xFF).toByte()
            pcm[p++] = ((v shr 8) and 0xFF).toByte()
        }
        return audio.sampleRate to pcm
    }
}

suspend fun synthesizeSpanishSpeechToPcm16(
    context: Context,
    text: String,
    targetRate: Int,
    preferredVoiceName: String = "sherpa-es_ES-miro-high"
): BytesResult = withContext(Dispatchers.IO) {
    try {
        val clean = text.trim().take(500)
        if (clean.isBlank()) {
            return@withContext BytesResult(false, error = "Texto TTS vacío")
        }

        val selectedVoice = preferredVoiceName.ifBlank { "sherpa-es_ES-miro-high" }
        val (sourceRate, sourcePcm) = SherpaEmbeddedTts.generate(
            context = context,
            text = clean,
            voiceName = selectedVoice
        )

        if (sourcePcm.isEmpty()) {
            return@withContext BytesResult(false, error = "Sherpa no generó audio")
        }

        val pcm = if (sourceRate == targetRate) {
            sourcePcm
        } else {
            resamplePcm16Mono(sourcePcm, sourceRate, targetRate)
        }

        BytesResult(true, data = pcm)
    } catch (e: UnsatisfiedLinkError) {
        BytesResult(
            false,
            error = "Sherpa JNI no está incluido dentro de la APK: ${e.message ?: e.javaClass.simpleName}"
        )
    } catch (e: Exception) {
        BytesResult(
            false,
            error = "Sherpa local: ${e.javaClass.simpleName}: ${e.message ?: "sin detalle"}"
        )
    }
}


private fun extractPcm16MonoFromWav(wav: ByteArray): Pair<Int, ByteArray>? {
    if (wav.size < 44 ||
        String(wav, 0, 4, Charsets.US_ASCII) != "RIFF" ||
        String(wav, 8, 4, Charsets.US_ASCII) != "WAVE"
    ) return null

    fun u16(i: Int): Int =
        (wav[i].toInt() and 0xFF) or ((wav[i + 1].toInt() and 0xFF) shl 8)

    fun u32(i: Int): Int =
        (wav[i].toInt() and 0xFF) or
                ((wav[i + 1].toInt() and 0xFF) shl 8) or
                ((wav[i + 2].toInt() and 0xFF) shl 16) or
                ((wav[i + 3].toInt() and 0xFF) shl 24)

    var pos = 12
    var sampleRate = 0
    var channels = 0
    var bits = 0
    var audioFormat = 0
    var dataStart = -1
    var dataSize = 0

    while (pos + 8 <= wav.size) {
        val id = String(wav, pos, 4, Charsets.US_ASCII)
        val size = u32(pos + 4)
        val start = pos + 8
        if (size < 0 || start + size > wav.size) break

        if (id == "fmt " && size >= 16) {
            audioFormat = u16(start)
            channels = u16(start + 2)
            sampleRate = u32(start + 4)
            bits = u16(start + 14)
        } else if (id == "data") {
            dataStart = start
            dataSize = size
            break
        }
        pos = start + size + (size and 1)
    }

    if (audioFormat != 1 || bits != 16 || sampleRate <= 0 || dataStart < 0) return null

    val raw = wav.copyOfRange(dataStart, (dataStart + dataSize).coerceAtMost(wav.size))
    if (channels == 1) return sampleRate to raw
    if (channels != 2) return null

    // Stereo -> mono.
    val mono = ByteArray((raw.size / 4) * 2)
    var si = 0
    var di = 0
    while (si + 3 < raw.size) {
        val l = (((raw[si + 1].toInt()) shl 8) or (raw[si].toInt() and 0xFF)).toShort().toInt()
        val r = (((raw[si + 3].toInt()) shl 8) or (raw[si + 2].toInt() and 0xFF)).toShort().toInt()
        val m = ((l + r) / 2).toShort().toInt()
        mono[di] = (m and 0xFF).toByte()
        mono[di + 1] = ((m shr 8) and 0xFF).toByte()
        si += 4
        di += 2
    }
    return sampleRate to mono
}


private fun resamplePcm16Mono(
    pcm: ByteArray,
    sourceRate: Int,
    targetRate: Int
): ByteArray {
    if (sourceRate <= 0 || targetRate <= 0 || pcm.size < 2 || sourceRate == targetRate) return pcm

    val sourceSamples = pcm.size / 2
    val targetSamples = ((sourceSamples.toLong() * targetRate) / sourceRate).toInt().coerceAtLeast(1)
    val out = ByteArray(targetSamples * 2)

    fun sampleAt(index: Int): Int {
        val i = index.coerceIn(0, sourceSamples - 1) * 2
        return (((pcm[i + 1].toInt()) shl 8) or (pcm[i].toInt() and 0xFF)).toShort().toInt()
    }

    for (n in 0 until targetSamples) {
        val sourcePos = n.toDouble() * sourceRate / targetRate
        val i0 = sourcePos.toInt().coerceIn(0, sourceSamples - 1)
        val i1 = (i0 + 1).coerceAtMost(sourceSamples - 1)
        val frac = sourcePos - i0
        val value = (sampleAt(i0) * (1.0 - frac) + sampleAt(i1) * frac)
            .toInt().coerceIn(-32768, 32767)

        out[n * 2] = (value and 0xFF).toByte()
        out[n * 2 + 1] = ((value shr 8) and 0xFF).toByte()
    }

    return out
}

// =====================================================
// HTTP GET TEXTO
// =====================================================

suspend fun httpGetText(
    ip: String,
    endpoint: String
): TextResult =
    withContext(
        Dispatchers.IO
    ) {

        var connection:
                HttpURLConnection? = null


        try {

            val url =
                URL(
                    "http://${ip.trim()}$endpoint"
                )


            connection = openXiaoConnectionStrict(url)


            connection.requestMethod =
                "GET"


            connection.connectTimeout =
                5000


            connection.readTimeout =
                15000


            connection.connect()


            val code =
                connection.responseCode


            if (
                code in 200..299
            ) {

                val text =
                    connection
                        .inputStream
                        .bufferedReader()
                        .use {
                            it.readText()
                        }


                TextResult(
                    success = true,
                    text = text
                )

            } else {

                TextResult(
                    success = false,
                    error = "HTTP $code"
                )
            }

        } catch (
            e: Exception
        ) {

            TextResult(
                success = false,

                error =
                    e.message
                        ?: e.javaClass
                            .simpleName
            )

        } finally {

            connection
                ?.disconnect()
        }
    }


// =====================================================
// HTTP GET BYTES
// =====================================================

/**
 * Corrige el efecto espejo de la cámara XIAO en Android.
 * La misma imagen corregida se usa tanto para la vista previa como para la IA,
 * de modo que el texto y la orientación izquierda/derecha se interpreten reales.
 */
fun unmirrorJpeg(jpeg: ByteArray): ByteArray {
    if (jpeg.isEmpty()) return jpeg

    return try {
        val src = android.graphics.BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
            ?: return jpeg.copyOf()

        val matrix = android.graphics.Matrix().apply {
            postScale(-1f, 1f)
        }

        val flipped = android.graphics.Bitmap.createBitmap(
            src,
            0,
            0,
            src.width,
            src.height,
            matrix,
            true
        )

        val out = java.io.ByteArrayOutputStream()
        flipped.compress(android.graphics.Bitmap.CompressFormat.JPEG, 92, out)
        val result = out.toByteArray()

        if (flipped !== src) flipped.recycle()
        src.recycle()
        out.close()

        if (result.isNotEmpty()) result else jpeg.copyOf()
    } catch (_: Throwable) {
        jpeg.copyOf()
    }
}

private fun openXiaoConnectionStrict(url: URL): HttpURLConnection {
    // V36: PROHIBIDO caer en url.openConnection(), porque Android podría
    // intentar llegar a 192.168.4.1 por Wi-Fi doméstica o datos móviles.
    val network = activeXiaoNetwork
        ?: throw IllegalStateException("XIAO_NETWORK_NOT_READY")
    return network.openConnection(url) as HttpURLConnection
}

// V57: prueba controlada de full-duplex.
// GET de cámara/micrófono siguen compartiendo un gate para no pisarse entre sí.
// Playback tiene un gate independiente, de modo que SOLO micrófono y salida de audio
// pueden coexistir. Si el firmware no lo soporta, el log mostrará timeouts con mic=1/play=1.
private val xiaoInputGate = kotlinx.coroutines.sync.Mutex()
private val xiaoPlaybackGate = kotlinx.coroutines.sync.Mutex()

suspend fun httpGetBytes(
    ip: String,
    endpoint: String,
    connectTimeoutMs: Int = 900,
    readTimeoutMs: Int = 2_500
): BytesResult = withContext(Dispatchers.IO) {
    // V57: /capture y /mic_sample continúan serializados entre sí.
    // La única concurrencia permitida en esta prueba es con /play_audio.
    xiaoInputGate.lock()
    try {
        var connection: HttpURLConnection? = null
        try {
            val url = URL("http://${ip.trim()}$endpoint")
            connection = openXiaoConnectionStrict(url)

            connection.requestMethod = "GET"
            connection.connectTimeout = connectTimeoutMs.coerceAtLeast(250)
            connection.readTimeout = readTimeoutMs.coerceAtLeast(500)
            connection.useCaches = false
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("Connection", "close")
            connection.connect()

            val code = connection.responseCode
            if (code in 200..299) {
                val bytes = connection.inputStream.use { it.readBytes() }
                BytesResult(success = true, data = bytes)
            } else {
                BytesResult(success = false, error = "HTTP $code")
            }
        } catch (e: Exception) {
            BytesResult(
                success = false,
                error = "${e.javaClass.simpleName}: ${e.message ?: "sin detalle"}"
            )
        } finally {
            connection?.disconnect()
        }
    } finally {
        xiaoInputGate.unlock()
    }
}