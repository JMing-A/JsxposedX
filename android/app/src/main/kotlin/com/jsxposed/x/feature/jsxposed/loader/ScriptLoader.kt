package com.jsxposed.x.feature.jsxposed.loader

import android.content.Context
import com.jsxposed.x.core.bridge.xposed_js_snapshot.XposedScriptSnapshotRepository
import com.jsxposed.x.core.utils.log.LogX
import com.whl.quickjs.wrapper.QuickJSContext
import org.json.JSONObject

/**
 * JS 脚本加载器 (客户端)
 * 负责通过 libxposed remote file 读取宿主生成的脚本快照并投递到 JS 引擎
 */
class ScriptLoader(
    private val context: Context,
    private val qjs: QuickJSContext,
    private val packageName: String
) {
    private val TAG = "FINDBUGS"

    fun loadAndExecute() {
        val loadStart = System.currentTimeMillis()
        val fileName = XposedScriptSnapshotRepository.snapshotFileName(packageName)

        try {
            LogX.d(TAG, "snapshot-open-start package=$packageName thread=${Thread.currentThread().name} file=$fileName")
            val snapshotText = XposedRemoteFileReader.readText(fileName)
            if (snapshotText.isNullOrEmpty()) {
                LogX.d(TAG, "snapshot-empty package=$packageName file=$fileName reason=file-missing-or-empty")
                return
            }
            LogX.d(TAG, "snapshot-open-finish package=$packageName file=$fileName size=${snapshotText.length} cost=${System.currentTimeMillis() - loadStart}ms")

            val snapshot = JSONObject(snapshotText)
            val scripts = snapshot.optJSONArray("scripts")
            val count = scripts?.length() ?: 0
            LogX.d(TAG, "snapshot-parse-finish package=$packageName file=$fileName count=$count")
            if (count == 0) {
                LogX.d(TAG, "snapshot-empty package=$packageName file=$fileName reason=no-enabled-scripts")
                return
            }

            for (index in 0 until count) {
                val item = scripts?.optJSONObject(index) ?: continue
                val scriptName = item.optString("name")
                val sourceCode = item.optString("code")
                if (scriptName.isBlank() || sourceCode.isEmpty()) {
                    LogX.e(TAG, "snapshot-entry-invalid package=$packageName file=$fileName index=$index")
                    continue
                }

                LogX.d(TAG, "ScriptLoader.execute-start package=$packageName script=$scriptName size=${sourceCode.length}")
                val executeStart = System.currentTimeMillis()
                executeScript(scriptName, sourceCode)
                LogX.d(TAG, "ScriptLoader.execute-finish package=$packageName script=$scriptName cost=${System.currentTimeMillis() - executeStart}ms")
            }

            LogX.d(TAG, "ScriptLoader.loadAndExecute finish package=$packageName cost=${System.currentTimeMillis() - loadStart}ms")
        } catch (e: UnsupportedOperationException) {
            LogX.e(TAG, "snapshot-open-unsupported package=$packageName file=$fileName error=${e.message}")
        } catch (e: Exception) {
            LogX.e(TAG, "snapshot-open-failed package=$packageName file=$fileName error=${e.message}")
        }
    }

    private fun executeScript(scriptName: String, sourceCode: String) {
        try {
            qjs.evaluate(sourceCode, scriptName)
            LogX.d(TAG, "[$packageName] 脚本执行成功: $scriptName")
        } catch (e: Exception) {
            LogX.e(TAG, "[$packageName] 脚本语法错误或者执行崩溃 ($scriptName): ${e.message}")
        }
    }
}
