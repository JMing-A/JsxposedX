package com.jsxposed.x

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.jsxposed.x.core.bridge.lsposed_native.LSPosed
import com.jsxposed.x.core.utils.log.LogX
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingLsposedCheck: Runnable? = null

    companion object {
        private const val TAG = "FINDBUGS"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "========== MainActivity.configureFlutterEngine ==========")
        NativeProvider.registerAll(this, flutterEngine.dartExecutor.binaryMessenger)
        Log.d(TAG, "NativeProvider registered")
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "MainActivity.onCreate")
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "MainActivity.onResume")
        LSPosed.initService(applicationContext)
        scheduleOneTimeLsposedCheck()
    }

    override fun onPause() {
        super.onPause()
        Log.d(TAG, "MainActivity.onPause")
        pendingLsposedCheck?.let { mainHandler.removeCallbacks(it) }
    }

    override fun onDestroy() {
        pendingLsposedCheck?.let { mainHandler.removeCallbacks(it) }
        NativeProvider.dispose()
        super.onDestroy()
    }

    private fun scheduleOneTimeLsposedCheck() {
        pendingLsposedCheck?.let { mainHandler.removeCallbacks(it) }
        val task = Runnable {
            if (LSPosed.isServiceConnected()) {
                LogX.d("FixHookError", "LSPosed connected, skip auto restart")
                return@Runnable
            }

            LogX.w(
                "FixHookError",
                "LSPosed not connected after cold start, skip auto relaunch to avoid interrupting Frida/HookJsXposed"
            )
        }
        pendingLsposedCheck = task
        mainHandler.postDelayed(task, 3500L)
    }
}
