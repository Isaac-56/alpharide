package com.alpharideapp.passengerapp

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.media.AudioAttributes
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            for ((id, name, importance) in listOf(
                Triple("alpha_ride_alerts_v1", "Ride requests and updates", NotificationManager.IMPORTANCE_HIGH),
                Triple("alpha_updates_v1", "News and discounts", NotificationManager.IMPORTANCE_DEFAULT)
            )) {
                val channel = NotificationChannel(id, name, importance)
                channel.setSound(Settings.System.DEFAULT_NOTIFICATION_URI,
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build())
                channel.enableVibration(true)
                manager.createNotificationChannel(channel)
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alpha/notifications")
            .setMethodCallHandler { call, result ->
                if (call.method != "show") {
                    result.notImplemented()
                } else {
                    try {
                        val urgent = call.argument<Boolean>("urgent") == true
                        val channelId = if (urgent) "alpha_ride_alerts_v1" else "alpha_updates_v1"
                        val eventId = call.argument<String>("eventId") ?: "alpha-update"
                        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: intent
                        val pending = PendingIntent.getActivity(this, 0, launch,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                            android.app.Notification.Builder(this, channelId)
                        else android.app.Notification.Builder(this)
                        builder.setSmallIcon(R.drawable.ic_notification)
                            .setContentTitle(call.argument<String>("title") ?: "Alpha update")
                            .setContentText(call.argument<String>("body") ?: "")
                            .setAutoCancel(true)
                            .setContentIntent(pending)
                            .setVisibility(android.app.Notification.VISIBILITY_PRIVATE)
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                            builder.setDefaults(android.app.Notification.DEFAULT_ALL)
                            builder.setPriority(if (urgent) android.app.Notification.PRIORITY_HIGH
                                else android.app.Notification.PRIORITY_DEFAULT)
                        }
                        manager.notify(eventId.hashCode(), builder.build())
                        result.success(null)
                    } catch (error: SecurityException) {
                        result.error("permission-denied", "Enable notifications in phone settings.", null)
                    }
                }
            }
    }
}
