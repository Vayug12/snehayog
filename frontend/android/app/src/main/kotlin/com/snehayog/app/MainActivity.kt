package com.snehayog.app

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.util.Rational
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.annotation.Keep
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

@Keep
class MainActivity : FlutterActivity() {
    private val installReferrerChannel = "vayug/install_referrer"
    private val pictureInPictureChannel = "vayug/picture_in_picture"
    private val pictureInPictureAction = "com.snehayog.app.PICTURE_IN_PICTURE_ACTION"
    private lateinit var pipMethodChannel: MethodChannel
    private var pipActionReceiverRegistered = false
    private var pipAutoEnterEnabled = false
    private var pipIsPlaying = false
    private var pipAspectRatio = Rational(16, 9)
    private var pipSourceRect: Rect? = null
    private var pipEntryPending = false

    private val pipActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != pictureInPictureAction) return
            val shouldPlay = intent.getBooleanExtra("shouldPlay", false)
            pipIsPlaying = shouldPlay
            applyPictureInPictureParams()
            pipMethodChannel.invokeMethod(
                "playbackRequested",
                mapOf("shouldPlay" to shouldPlay)
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Edge-to-edge is enabled manually because enableEdgeToEdge() is not
        // supported on FlutterActivity. Bar colours are declared in the theme
        // (values/styles.xml) for API < 35; from API 35 the bars are always
        // transparent and Window.setStatusBarColor/setNavigationBarColor are
        // deprecated no-ops, so they must not be called here.
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        // Keep the bar transparent on Android versions where the colour APIs
        // still control the navigation surface. Android 15+ is edge-to-edge
        // by default and ignores these setters, but the same visual result is
        // provided there by the transparent edge-to-edge surface below.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                window.navigationBarDividerColor = Color.TRANSPARENT
            }
        }
        // Navigation bar contrast is enforced by default and paints an 80%
        // opaque scrim behind 3-button navigation, which reads as black over
        // the app's dark-navy background. The theme already disables it, but
        // Dart's SystemUiOverlayStyle only lands after the first Flutter frame,
        // so clear it here too to cover activity recreation and mode switches.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        WindowCompat.getInsetsController(window, window.decorView)?.let { controller ->
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            pictureInPictureChannel
        )
        pipMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(isPictureInPictureSupported())
                "enter" -> {
                    if (!isPictureInPictureSupported()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    updatePictureInPictureState(call.arguments as? Map<*, *>)
                    result.success(enterPictureInPictureMode(buildPictureInPictureParams()))
                }
                "update" -> {
                    updatePictureInPictureState(call.arguments as? Map<*, *>)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        ContextCompat.registerReceiver(
            this,
            pipActionReceiver,
            IntentFilter(pictureInPictureAction),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        pipActionReceiverRegistered = true

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            installReferrerChannel
        ).setMethodCallHandler { call, result ->
            if (call.method == "getInstallReferrer") {
                getInstallReferrer(result)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            pipAutoEnterEnabled &&
            !pipEntryPending &&
            !isInPictureInPictureMode &&
            isPictureInPictureSupported()
        ) {
            prepareFlutterSurfaceAndEnterPictureInPicture()
        }
    }

    private fun prepareFlutterSurfaceAndEnterPictureInPicture() {
        pipEntryPending = true
        pipMethodChannel.invokeMethod(
            "prepareToEnter",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    pipEntryPending = false
                    val isPrepared = result as? Boolean ?: false
                    val canEnter = isPrepared &&
                        !isFinishing &&
                        !isDestroyed &&
                        !isInPictureInPictureMode &&
                        isPictureInPictureSupported()
                    if (!canEnter || !enterPictureInPictureMode(buildPictureInPictureParams())) {
                        notifyPictureInPictureMode(false)
                    }
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?
                ) {
                    pipEntryPending = false
                    notifyPictureInPictureMode(false)
                }

                override fun notImplemented() {
                    pipEntryPending = false
                    notifyPictureInPictureMode(false)
                }
            }
        )
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        notifyPictureInPictureMode(isInPictureInPictureMode)
    }

    private fun notifyPictureInPictureMode(isActive: Boolean) {
        if (!::pipMethodChannel.isInitialized) return
        pipMethodChannel.invokeMethod(
            "modeChanged",
            mapOf("isActive" to isActive)
        )
    }

    override fun onDestroy() {
        if (pipActionReceiverRegistered) {
            unregisterReceiver(pipActionReceiver)
            pipActionReceiverRegistered = false
        }
        super.onDestroy()
    }

    private fun isPictureInPictureSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun updatePictureInPictureState(arguments: Map<*, *>?) {
        if (!isPictureInPictureSupported()) return
        pipIsPlaying = arguments?.get("isPlaying") as? Boolean ?: pipIsPlaying
        pipAutoEnterEnabled =
            arguments?.get("autoEnterEnabled") as? Boolean ?: pipAutoEnterEnabled

        val requestedRatio = (arguments?.get("aspectRatio") as? Number)?.toDouble()
        if (requestedRatio != null && requestedRatio.isFinite()) {
            val safeRatio = requestedRatio.coerceIn(1.0 / 2.39, 2.39)
            pipAspectRatio = Rational((safeRatio * 1000).toInt(), 1000)
        }

        val sourceRectValues = arguments?.get("sourceRect") as? List<*>
        pipSourceRect = if (sourceRectValues != null && sourceRectValues.size == 4) {
            val values = sourceRectValues.mapNotNull { (it as? Number)?.toInt() }
            if (values.size == 4 && values[2] > values[0] && values[3] > values[1]) {
                Rect(values[0], values[1], values[2], values[3])
            } else {
                null
            }
        } else {
            null
        }
        applyPictureInPictureParams()
    }

    private fun applyPictureInPictureParams() {
        if (!isPictureInPictureSupported()) return
        setPictureInPictureParams(buildPictureInPictureParams())
    }

    private fun buildPictureInPictureParams(): PictureInPictureParams {
        val actionIntent = Intent(pictureInPictureAction)
            .setPackage(packageName)
            .putExtra("shouldPlay", !pipIsPlaying)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            if (pipIsPlaying) 1 else 2,
            actionIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val action = RemoteAction(
            Icon.createWithResource(
                this,
                if (pipIsPlaying) android.R.drawable.ic_media_pause
                else android.R.drawable.ic_media_play
            ),
            if (pipIsPlaying) "Pause" else "Play",
            if (pipIsPlaying) "Pause video" else "Play video",
            pendingIntent
        )
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(pipAspectRatio)
            .setActions(listOf(action))
        pipSourceRect?.let(builder::setSourceRectHint)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Framework auto-enter can also react to system permission
            // surfaces. That is how a notification dialog can end up inside
            // PiP. We enter explicitly from onUserLeaveHint only after Flutter
            // has rendered its video-only frame.
            builder.setAutoEnterEnabled(false)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun getInstallReferrer(result: MethodChannel.Result) {
        val referrerClient = InstallReferrerClient.newBuilder(this).build()
        var completed = false

        referrerClient.startConnection(object : InstallReferrerStateListener {
            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                if (completed) return
                completed = true
                try {
                    if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                        val response = referrerClient.installReferrer
                        result.success(
                            mapOf(
                                "installReferrer" to response.installReferrer,
                                "referrerClickTimestampSeconds" to response.referrerClickTimestampSeconds,
                                "installBeginTimestampSeconds" to response.installBeginTimestampSeconds
                            )
                        )
                    } else {
                        result.success(null)
                    }
                } catch (error: Exception) {
                    result.error("INSTALL_REFERRER_ERROR", error.message, null)
                } finally {
                    referrerClient.endConnection()
                }
            }

            override fun onInstallReferrerServiceDisconnected() {
                if (!completed) {
                    completed = true
                    result.success(null)
                }
                referrerClient.endConnection()
            }
        })
    }
}
