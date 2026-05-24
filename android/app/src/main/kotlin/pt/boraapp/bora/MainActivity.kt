package pt.boraapp.bora

import android.app.KeyguardManager
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
        // Sessão 2026-05-24 (exec2 FIX C-prep) — bridge nativo para Flutter.
        // Permite ao bg/main isolate consultar estado do dispositivo sem
        // depender de plugins externos. Por agora expõe isDeviceLocked().
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_BRIDGE)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDeviceLocked" -> {
                        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                        result.success(km?.isDeviceLocked ?: false)
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
            // BUG B — vibração dupla (500ms ON, 200ms OFF, 500ms ON).
            vibrationPattern = longArrayOf(0L, 500L, 200L, 500L)
            enableLights(true)
            // Heads-up garantido (IMPORTANCE_HIGH já cobre); notificação
            // permanece até parceiro descartar (sem timeout automático).
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

    /// FIX A: canal v3 com som EXPLÍCITO bora_alert (raw resource) e
    /// AudioAttributes USAGE_NOTIFICATION_RINGTONE — tom de chamada estilo
    /// Uber/Glovo. CONTENT_TYPE_SONIFICATION + FLAG_AUDIBILITY_ENFORCED
    /// reforça que toca alto, mesmo em perfis silenciosos.
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
