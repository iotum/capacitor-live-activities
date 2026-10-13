package com.ciabosoftwaresolutions.liveactivities

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.getcapacitor.JSObject

class LiveActivitiesManager(private val context: Context) {

    companion object {
        private const val CHANNEL_ID = "live_activities"
        private const val CHANNEL_NAME = "Live Activities"
    }

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val preferences = context.getSharedPreferences("live_activity_lifecycle_v1", Context.MODE_PRIVATE)
    private val lifecycle = ActivityLifecycle(
        load = { preferences.getString("entries", null) },
        save = { stored ->
            check(preferences.edit().putString("entries", stored).commit()) { "Failed to persist Live Activity lifecycle" }
        },
        show = { info, state, ongoing ->
            notificationManager.notify(info.activityId, info.notificationId, buildNotification(JSObject(state.toString()), ongoing))
        },
        cancel = { info -> notificationManager.cancel(info.activityId, info.notificationId) },
    )

    init {
        ensureChannel()
        lifecycle.reconcile(notificationManager.activeNotifications.mapNotNull { it.tag }.toSet())
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    fun start(attributes: JSObject, state: JSObject): String {
        val activityType = attributes.optString("activityType", "activity")
        val result = applyEvent("start", activityType, state, System.currentTimeMillis() / 1000, true)
        return result.activityId ?: throw IllegalArgumentException("Live Activity key is already finished: $activityType")
    }

    fun update(activityId: String, state: JSObject) {
        val info = lifecycle.activeActivities().find { it.activityId == activityId }
            ?: throw IllegalArgumentException("No active Live Activity with id: $activityId")
        applyEvent("update", info.activityType, state, System.currentTimeMillis() / 1000, true)
    }

    fun end(activityId: String, finalState: JSObject?) {
        val info = lifecycle.activeActivities().find { it.activityId == activityId }
            ?: throw IllegalArgumentException("No active Live Activity with id: $activityId")
        applyEvent("end", info.activityType, finalState, System.currentTimeMillis() / 1000, false)
    }

    fun applyEvent(event: String, key: String, state: JSObject?, timestamp: Long, canStart: Boolean): ActivityEventResult =
        lifecycle.apply(event, key, state, timestamp, canStart)

    fun getActiveActivities(): List<ActivityInfo> = lifecycle.activeActivities()

    /**
     * Returns the FCM registration token if Firebase Messaging is present in
     * the host app, otherwise returns null.
     *
     * Firebase is NOT a hard dependency of this plugin. The token is obtained
     * via reflection so the plugin compiles and runs without firebase-messaging
     * on the classpath. When Firebase is absent this method returns null cleanly.
     *
     * To enable FCM token retrieval, add to your app's build.gradle:
     *   implementation 'com.google.firebase:firebase-messaging:24.x.x'
     *
     * Then call getPushToken() and send the token to your server to deliver
     * FCM data messages that drive Live Update notification changes.
     */
    fun getFcmToken(callback: (token: String?) -> Unit) {
        try {
            val firebaseMessagingClass = Class.forName("com.google.firebase.messaging.FirebaseMessaging")
            val getInstance = firebaseMessagingClass.getMethod("getInstance")
            val instance = getInstance.invoke(null)
            val getToken = firebaseMessagingClass.getMethod("getToken")
            // getToken() returns a Task<String> — resolve it via reflection
            val task = getToken.invoke(instance)
            val taskClass = Class.forName("com.google.android.gms.tasks.Task")
            val addOnSuccessListener = taskClass.getMethod(
                "addOnSuccessListener",
                Class.forName("com.google.android.gms.tasks.OnSuccessListener")
            )
            val addOnFailureListener = taskClass.getMethod(
                "addOnFailureListener",
                Class.forName("com.google.android.gms.tasks.OnFailureListener")
            )

            val successProxy = java.lang.reflect.Proxy.newProxyInstance(
                javaClass.classLoader,
                arrayOf(Class.forName("com.google.android.gms.tasks.OnSuccessListener"))
            ) { _, _, args ->
                callback(args[0] as? String)
                null
            }
            val failureProxy = java.lang.reflect.Proxy.newProxyInstance(
                javaClass.classLoader,
                arrayOf(Class.forName("com.google.android.gms.tasks.OnFailureListener"))
            ) { _, _, _ ->
                callback(null)
                null
            }

            addOnSuccessListener.invoke(task, successProxy)
            addOnFailureListener.invoke(task, failureProxy)
        } catch (_: ClassNotFoundException) {
            // Firebase not in project — expected when app-driven mode only
            callback(null)
        } catch (_: Exception) {
            callback(null)
        }
    }

    // -------------------------------------------------------------------------
    // Notification builder
    // Targets Android 16+ Live Updates chip when available, falls back to a
    // standard ongoing notification on Android 13–15.
    // -------------------------------------------------------------------------

    private fun buildNotification(state: JSObject, ongoing: Boolean): Notification {
        val title    = state.optString("title", "")
        val subtitle = state.optString("subtitle", "")
        val progress = if (state.has("progress")) state.getDouble("progress") else null

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(getAppIcon())
            .setContentTitle(title)
            .setOngoing(ongoing)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setSilent(true)

        if (subtitle.isNotBlank()) {
            builder.setContentText(subtitle)
        }

        if (progress != null) {
            val progressInt = (progress.coerceIn(0.0, 1.0) * 100).toInt()
            builder.setProgress(100, progressInt, false)
        }

        val display = DisplayContract.project(state.optJSONObject("display"))
        if (display != null) {
            val icons = mapOf(
                "call" to android.R.drawable.sym_action_call,
                "info" to android.R.drawable.ic_dialog_info,
                "delivery" to android.R.drawable.ic_menu_send,
                "check" to android.R.drawable.checkbox_on_background,
            )
            builder.setSmallIcon(icons[display.icon] ?: android.R.drawable.ic_dialog_info)
            val accent = when (display.phase) {
                "ringing" -> "#F4C95D"
                "connected" -> "#65D69A"
                "ended" -> "#B8C0CC"
                else -> null
            }
            accent?.let { builder.setColor(android.graphics.Color.parseColor(it)) }
            if (display.header.isNotBlank()) builder.setSubText(display.header)
            val timer = display.timer
            val summary = when (display.indicator) {
                "status" -> display.status
                "progress" -> progress?.let { "${(it.coerceIn(0.0, 1.0) * 100).toInt()}%" } ?: ""
                "timer" -> if (timer?.optString("mode") == "frozen") {
                    val seconds = timer.optLong("seconds").coerceAtLeast(0)
                    "%d:%02d".format(seconds / 60, seconds % 60)
                } else display.status
                else -> ""
            }
            builder.setContentText(summary)
            if (display.indicator == "timer" && timer != null) {
                when (timer.optString("mode")) {
                    "elapsed" -> builder.setWhen((timer.optDouble("start") * 1000).toLong()).setUsesChronometer(true)
                    "countdown" -> if (Build.VERSION.SDK_INT >= 24) {
                        builder.setWhen((timer.optDouble("end") * 1000).toLong())
                            .setUsesChronometer(true).setChronometerCountDown(true)
                    }
                }
            }
            val lines = listOfNotNull(
                subtitle.takeIf { display.showSubtitle && it.isNotBlank() },
                display.status.takeIf { it.isNotBlank() },
            ) + display.lines
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(lines.joinToString("\n")))
            linkIntent(display.url)?.let { builder.setContentIntent(it) }
            display.actions.forEach { action ->
                linkIntent(action.url)?.let { intent ->
                    val actionIcon = when (action.icon) {
                        "record" -> android.R.drawable.ic_menu_myplaces
                        "ticket" -> android.R.drawable.ic_menu_agenda
                        "note" -> android.R.drawable.ic_menu_edit
                        else -> android.R.drawable.ic_menu_view
                    }
                    val notificationAction = NotificationCompat.Action.Builder(actionIcon, action.label, intent)
                        .setSemanticAction(if (action.emphasis == "destructive") NotificationCompat.Action.SEMANTIC_ACTION_DELETE else NotificationCompat.Action.SEMANTIC_ACTION_NONE)
                    builder.addAction(notificationAction.build())
                }
            }
            if (display.template != "progress") builder.setProgress(0, 0, false)
            builder.setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
        }

        // Android 16+ Live Updates — shown as a persistent chip in the status bar.
        // The system promotes this notification to a Live Update when the app sets
        // FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or similar; here we use the
        // live-update flag available from API 36.
        if (Build.VERSION.SDK_INT >= 36) {
            applyLiveUpdateExtras(builder, state)
        }

        return builder.build()
    }

    private fun linkIntent(url: String): PendingIntent? {
        val uri = Uri.parse(url)
        if (uri.scheme?.lowercase() != "https" || uri.host.isNullOrBlank() || uri.userInfo != null) return null
        val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    @Suppress("DEPRECATION")
    private fun applyLiveUpdateExtras(builder: NotificationCompat.Builder, state: JSObject) {
        // Android 16 (API 36) Live Updates API
        // Sets FLAG_LIVE_UPDATE so the system renders the notification as a
        // persistent status-bar chip rather than a standard shade entry.
        try {
            val flagField = Notification::class.java.getField("FLAG_LIVE_UPDATE")
            val flagValue = flagField.getInt(null)
            val notification = builder.build()
            notification.flags = notification.flags or flagValue

            // If a progress value exists, also attach it to the extras bundle so
            // the system can render the compact chip progress ring.
            val progress = if (state.has("progress")) state.getDouble("progress") else null
            if (progress != null) {
                notification.extras.putDouble("android.liveUpdate.progress", progress)
            }
        } catch (_: NoSuchFieldException) {
            // API not yet available on this build; graceful no-op
        } catch (_: Exception) {
            // Ignore any other reflection failures
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Persistent activity updates"
                setSound(null, null)
                enableVibration(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun getAppIcon(): Int {
        val res = context.packageManager
            .getApplicationInfo(context.packageName, 0)
            .icon
        return if (res != 0) res else android.R.drawable.ic_dialog_info
    }
}
