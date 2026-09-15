package pt.boraapp.bora

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    companion object {
        // Sessão 2026-05-24 (exec2 FIX A) — canal v3 com som EXPLÍCITO bora_alert.
        // O canal v2 nasceu sem setSound() → Android trancou-o com som default.
        // Para escapar à armadilha (channel sound é imutável após criação),
        // criamos um ID NOVO com setSound() correcto.
        const val CHANNEL_ORDERS_V3 = "bora_orders_urgent_v3"
        const val NATIVE_BRIDGE = "pt.boraapp.bora/native"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerReservationsChannel()
        deleteLegacyOrderChannels()
        createDriverOfferChannelV3()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Exec6.16 (2026-05-25) — MethodChannel limpa, sem isDeviceLocked
        // (gate já não usa) nem KeyguardManager bridge (substituído pelo
        // heartbeat bora_main_alive_ts no main isolate).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_BRIDGE)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveTaskToBack" -> {
                        // CAMADA 2 (Stuart pattern) — back button intercept.
                        // Manda app para background sem destruir MainActivity →
                        // main isolate + WebSocket sobrevivem → realtime continua.
                        try {
                            moveTaskToBack(true)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "bringToForeground" -> {
                        // Usado pelo overlay flow quando precisa de main isolate
                        // event loop activo (ex: rehydrate após fullScreenIntent).
                        try {
                            val intent = packageManager.getLaunchIntentForPackage(packageName)
                            intent?.addFlags(
                                android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                                android.content.Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP
                            )
                            if (intent != null) startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "getDeviceDiagnostics" -> {
                        // [F] 2026-06-30 — contexto para debug_crash_logs sem
                        // dependências novas (package_info_plus/device_info_plus
                        // arriscariam o build de release no CI). android.os.Build
                        // e getPackageInfo são core do SDK.
                        try {
                            val pInfo = packageManager.getPackageInfo(packageName, 0)
                            val versionName = pInfo.versionName ?: ""
                            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                pInfo.longVersionCode.toString()
                            } else {
                                @Suppress("DEPRECATION")
                                pInfo.versionCode.toString()
                            }
                            val map = hashMapOf(
                                "app_version" to "$versionName+$versionCode",
                                "device_model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                                "android_version" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
                            )
                            result.success(map)
                        } catch (e: Exception) {
                            result.error("DIAG", e.message, null)
                        }
                    }
                    "canUseFullScreenIntent" -> {
                        // Sessão 2026-06-11 — Android 14+ trata USE_FULL_SCREEN_INTENT
                        // como "special app access": a Play Store revoga-a na instalação
                        // para apps que não são de chamadas/alarmes. Sem ela, o
                        // fullScreenIntent é ignorado em silêncio (notif normal, ecrã
                        // não acorda com telemóvel bloqueado). Em Android <14 é
                        // concedida via manifest.
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                                result.success(nm.canUseFullScreenIntent())
                            } else {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.error("FSI_CHECK", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerReservationsChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            "bora_reservations",
            "Reservas",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Notificações de novas reservas para o parceiro."
            enableVibration(true)
            vibrationPattern = longArrayOf(0L, 500L, 200L, 500L)
            enableLights(true)
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
    }

    /// Apaga canais antigos (v1, v2) — limpa o ecrã Definições→App→Notif.
    /// Idempotente: deleteNotificationChannel é no-op se o canal não existe.
    private fun deleteLegacyOrderChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try { manager.deleteNotificationChannel("bora_orders_urgent") } catch (_: Exception) {}
        try { manager.deleteNotificationChannel("bora_orders_urgent_v2") } catch (_: Exception) {}
    }

    /// Canal v3 com som EXPLÍCITO bora_alert (raw resource) e
    /// AudioAttributes USAGE_NOTIFICATION_RINGTONE — tom de chamada estilo
    /// Uber/Glovo. CONTENT_TYPE_SONIFICATION + bypass DND reforça que toca
    /// alto, mesmo em perfis silenciosos. Edge Fn notify-driver usa este id.
    private fun createDriverOfferChannelV3() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val soundUri = Uri.parse("android.resource://$packageName/raw/bora_alert")
        val audioAttrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(
            CHANNEL_ORDERS_V3,
            "Bora — Novos pedidos",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Som contínuo + vibração para novos pedidos urgentes."
            setSound(soundUri, audioAttrs)
            enableVibration(true)
            vibrationPattern = longArrayOf(0L, 500L, 200L, 500L, 200L, 500L)
            enableLights(true)
            setShowBadge(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setBypassDnd(true)
        }
        manager.createNotificationChannel(channel)
    }
}
