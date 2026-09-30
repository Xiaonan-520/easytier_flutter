package io.github.xiaonan520.easytier_flutter

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.easytier.jni.EasyTierVpnService

/**
 * Single source of truth for the EasyTier notification. Flutter pushes the
 * current state (CoreState + current profile + status snapshot) through the
 * method channel; this helper renders it as a native notification.
 *
 * It always posts under the VPN service's notification id, so the foreground
 * notification and the app-level state updates are one and the same
 * notification — the UI and the shade can never disagree. The Disconnect
 * action routes back into the Dart state machine via the method channel;
 * only when the engine is gone (app swiped away) does it fall back to the
 * service's synchronous stopNow() teardown.
 */
object NotificationHelper {
    private const val TITLE = "EasyTier"

    /**
     * Initial notification for startForeground(). State updates arrive from
     * Flutter via [update]; this just renders a neutral "starting" placeholder
     * so the service is promoted without delay.
     */
    fun buildForeground(context: Context) = baseBuilder(context, "EasyTier · Starting…", null)
        .setOngoing(true)
        .build()

    private fun baseBuilder(
        context: Context,
        text: String,
        bigText: String?,
    ): NotificationCompat.Builder =
        NotificationCompat.Builder(context, EasyTierVpnService.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(TITLE)
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .apply {
                bigText?.let { setStyle(NotificationCompat.BigTextStyle().bigText(it)) }
                launchIntent(context)?.let(::setContentIntent)
            }

    fun update(
        context: Context,
        state: String,
        profileName: String,
        peers: Int,
        virtualIp: String,
        error: String?,
    ) {
        val networkLabel = profileName.ifEmpty { "EasyTier" }
        val (text, bigText) = when (state) {
            "starting" -> "$networkLabel · Connecting…" to null
            "stopping" -> "$networkLabel · Disconnecting…" to null
            "running" -> {
                val traffic = "↓  —        ↑  —"
                val summary = buildString {
                    append(peers)
                    append(if (peers == 1) " peer" else " peers")
                    if (virtualIp.isNotEmpty()) {
                        append(" · ")
                        append(virtualIp.substringBefore('/'))
                    }
                }
                "$networkLabel · Connected" to "$traffic\n$summary"
            }
            "error" -> "Connection failed" to error?.takeIf { it.isNotEmpty() }
            else -> "$networkLabel · Disconnected" to null
        }

        val running = state == "running" || state == "starting" || state == "stopping"
        val builder = baseBuilder(context, text, bigText).setOngoing(running)

        if (state == "running" || state == "starting") {
            builder.addAction(0, "Open App", openAppPendingIntent(context))
            builder.addAction(0, "Disconnect", disconnectPendingIntent(context))
        }

        context.getSystemService(NotificationManager::class.java)
            .notify(EasyTierVpnService.NOTIFICATION_ID, builder.build())
    }

    fun cancel(context: Context) {
        context.getSystemService(NotificationManager::class.java)
            .cancel(EasyTierVpnService.NOTIFICATION_ID)
    }

    private fun launchIntent(context: Context): PendingIntent? =
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(
                context, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

    private fun openAppPendingIntent(context: Context): PendingIntent? =
        launchIntent(context)

    private fun disconnectPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, EasyTierVpnService::class.java).apply {
            action = EasyTierVpnService.ACTION_NOTIFICATION_DISCONNECT
        }
        return PendingIntent.getService(
            context, 1, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
