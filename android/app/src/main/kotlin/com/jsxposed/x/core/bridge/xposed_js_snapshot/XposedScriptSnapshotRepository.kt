package com.jsxposed.x.core.bridge.xposed_js_snapshot

import android.content.Context
import android.os.ParcelFileDescriptor
import com.jsxposed.x.core.bridge.lsposed_native.LSPosed
import com.jsxposed.x.core.bridge.pinia_native.Pinia
import com.jsxposed.x.core.bridge.project_native.Project
import com.jsxposed.x.core.utils.log.LogX
import org.json.JSONArray
import org.json.JSONObject

class XposedScriptSnapshotRepository(private val context: Context) {

    companion object {
        private const val TAG = "XposedScriptSnapshot"
        private const val SNAPSHOT_VERSION = 1
        private const val PINIA_SPACE = "pinia"
        private const val XPOSED_SWITCH_PREFIX = "xposed_check_status_"

        fun snapshotFileName(packageName: String): String {
            val sanitizedPackage = packageName.replace('.', '_')
            return "xposed_js_${sanitizedPackage}.json"
        }

        fun packageNameFromSwitchKey(key: String): String? {
            if (!key.startsWith(XPOSED_SWITCH_PREFIX)) return null
            val payload = key.removePrefix(XPOSED_SWITCH_PREFIX)
            val marker = "_/data/"
            val markerIndex = payload.indexOf(marker)
            if (markerIndex <= 0) return null
            return payload.substring(0, markerIndex)
        }
    }

    private val project = Project(context)
    private val pinia = Pinia(context)

    fun buildSnapshot(packageName: String): String {
        val scripts = JSONArray()
        val scriptPaths = project.getJsScripts(packageName)

        scriptPaths.forEach { path ->
            val scriptName = java.io.File(path).name
            val switchKey = "${XPOSED_SWITCH_PREFIX}${packageName}_${path}"
            val isEnabled = pinia.getValue(PINIA_SPACE, switchKey, false)
            if (!isEnabled) return@forEach

            val sourceCode = project.readJsScript(packageName, scriptName)
            if (sourceCode.isEmpty() || sourceCode.startsWith("cat: ")) {
                LogX.e(TAG, "buildSnapshot skip unreadable package=$packageName script=$scriptName")
                return@forEach
            }

            val item = JSONObject()
            item.put("name", scriptName)
            item.put("code", sourceCode)
            scripts.put(item)
        }

        return JSONObject().apply {
            put("version", SNAPSHOT_VERSION)
            put("packageName", packageName)
            put("updatedAt", System.currentTimeMillis())
            put("scripts", scripts)
        }.toString()
    }

    fun writeSnapshot(packageName: String) {
        val snapshot = buildSnapshot(packageName)
        val fileName = snapshotFileName(packageName)
        val descriptor = LSPosed.openRemoteFile(fileName)

        if (descriptor == null) {
            LogX.e(TAG, "writeSnapshot failed package=$packageName file=$fileName reason=remote-file-unavailable")
            return
        }

        try {
            ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { output ->
                output.channel.truncate(0)
                output.channel.position(0)
                output.bufferedWriter(Charsets.UTF_8).use {
                    it.write(snapshot)
                    it.flush()
                }
            }
            LogX.d(TAG, "writeSnapshot success package=$packageName file=$fileName size=${snapshot.length}")
        } catch (e: Exception) {
            LogX.e(TAG, "writeSnapshot failed package=$packageName file=$fileName error=${e.message}")
        }
    }

    fun rebuildAllSnapshots() {
        val packages = project.getProjects().map { it.packageName }.distinct().sorted()
        packages.forEach { writeSnapshot(it) }
        LogX.d(TAG, "rebuildAllSnapshots finished count=${packages.size}")
    }

    fun refreshForSwitchKey(space: String, key: String) {
        if (space != PINIA_SPACE) return
        val packageName = packageNameFromSwitchKey(key) ?: return
        writeSnapshot(packageName)
    }

    fun refreshAfterClear(space: String) {
        if (space != PINIA_SPACE) return
        rebuildAllSnapshots()
    }
}
