package com.githubnexus.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class DeployForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "github_nexus_deploy_channel"
        const val NOTIF_ID_ACTIVE = 4001
        const val NOTIF_ID_RESULT = 4002

        const val ACTION_START = "com.githubnexus.app.action.DEPLOY_START"
        const val ACTION_UPDATE = "com.githubnexus.app.action.DEPLOY_UPDATE"
        const val ACTION_FINISH = "com.githubnexus.app.action.DEPLOY_FINISH"
        const val ACTION_STOP = "com.githubnexus.app.action.DEPLOY_STOP"
        const val ACTION_CANCEL_FROM_NOTIF = "com.githubnexus.app.action.DEPLOY_CANCEL_CLICKED"

        const val EXTRA_TITLE = "title"
        const val EXTRA_SUBTITLE = "subtitle"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_SUCCESS = "success"

        @Volatile
        var onCancelRequested: (() -> Unit)? = null
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "GitHub Nexus Deploy"
                val subtitle = intent.getStringExtra(EXTRA_SUBTITLE) ?: "Initializing..."
                acquireWakeLock()
                val notification = buildProgressNotification(
                    title = title,
                    subtitle = subtitle,
                    progress = 0,
                    indeterminate = true
                )
                startForegroundCompat(notification)
            }

            ACTION_UPDATE -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "GitHub Nexus Deploy"
                val subtitle = intent.getStringExtra(EXTRA_SUBTITLE) ?: "Deploying..."
                val progress = intent.getIntExtra(EXTRA_PROGRESS, 0).coerceIn(0, 100)
                val notification = buildProgressNotification(
                    title = title,
                    subtitle = subtitle,
                    progress = progress,
                    indeterminate = false
                )
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(NOTIF_ID_ACTIVE, notification)
            }

            ACTION_FINISH -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Deployment Finished"
                val subtitle = intent.getStringExtra(EXTRA_SUBTITLE) ?: ""
                val success = intent.getBooleanExtra(EXTRA_SUCCESS, true)
                releaseWakeLock()
                stopForegroundCompat()
                showFinalResultNotification(title, subtitle, success)
                stopSelf()
            }

            ACTION_CANCEL_FROM_NOTIF -> {
                onCancelRequested?.invoke()
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(
                    NOTIF_ID_ACTIVE,
                    buildProgressNotification(
                        title = "GitHub Nexus",
                        subtitle = "جارٍ إلغاء عملية النشر...",
                        progress = 0,
                        indeterminate = true,
                        includeCancelAction = false
                    )
                )
            }

            ACTION_STOP -> {
                releaseWakeLock()
                stopForegroundCompat()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID_ACTIVE,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIF_ID_ACTIVE, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "GitHub Deployments",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Live upload progress and completion alerts for GitHub Nexus deployments"
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildProgressNotification(
        title: String,
        subtitle: String,
        progress: Int,
        indeterminate: Boolean,
        includeCancelAction: Boolean = true
    ): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPending = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            pendingIntentFlags()
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentPending)
            .setProgress(100, progress, indeterminate)

        if (includeCancelAction) {
            val cancelIntent = Intent(this, DeployForegroundService::class.java).apply {
                action = ACTION_CANCEL_FROM_NOTIF
            }
            val cancelPending = PendingIntent.getService(
                this,
                1,
                cancelIntent,
                pendingIntentFlags()
            )
            val cancelAction = Notification.Action.Builder(
                android.R.drawable.ic_menu_close_clear_cancel,
                "إلغاء",
                cancelPending
            ).build()
            builder.addAction(cancelAction)
        }

        return builder.build()
    }

    private fun showFinalResultNotification(
        title: String,
        subtitle: String,
        success: Boolean
    ) {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPending = PendingIntent.getActivity(
            this,
            2,
            launchIntent,
            pendingIntentFlags()
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setAutoCancel(true)
            .setOngoing(false)
            .setContentIntent(contentPending)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setColor(if (success) 0xFF10B981.toInt() else 0xFFF43F5E.toInt())
        }

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID_RESULT, builder.build())
    }

    private fun pendingIntentFlags(): Int {
        return PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock?.isHeld == true) return
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "GitHubNexus::AtomicDeployWakeLock"
            ).apply {
                acquire(20 * 60 * 1000L) // 20-minute ceiling safety timeout
            }
        } catch (_: Exception) {
            // Proceed even if WakeLock acquisition is restricted by OEM policy.
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            wakeLock = null
        } catch (_: Exception) {
        }
    }
}
