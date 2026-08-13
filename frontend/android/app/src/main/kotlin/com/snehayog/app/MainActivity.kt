package com.snehayog.app

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.annotation.Keep
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

@Keep
class MainActivity : FlutterActivity() {
    private val installReferrerChannel = "vayug/install_referrer"

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
