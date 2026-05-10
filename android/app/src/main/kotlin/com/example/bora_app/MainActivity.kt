package com.example.bora_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerReservationsChannel()
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
}
