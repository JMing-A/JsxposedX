package com.jsxposed.x.core.bridge.memory_tool_native

import android.content.Context
import android.os.Build
import android.os.Process
import com.jsxposed.x.core.utils.log.LogX
import com.jsxposed.x.core.utils.shell.Shell
import java.io.File
import java.util.zip.ZipFile

class MemoryToolHelperManager(private val context: Context) {
    companion object {
        private const val TAG = "MemoryToolHelperManager"
        private const val STARTUP_RETRY_COUNT = 30
        private const val STARTUP_RETRY_DELAY_MS = 150L
        private const val HELPER_LOG_FILE_NAME = "memory_tool_helper.log"
    }

    private val socketName = "jsxposed_memory_tool_${Process.myPid()}"
    private val helperLogFile by lazy {
        val logDirectory = context.externalCacheDir ?: context.cacheDir
        File(logDirectory, HELPER_LOG_FILE_NAME)
    }
    private val helperLibraryDirectory by lazy {
        File(context.codeCacheDir, "memory_tool/helper_libs")
    }

    fun socketName(): String = socketName

    fun ensureDaemon() {
        synchronized(this) {
            if (isDaemonAlive()) {
                return
            }

            if (!hasRootAccess()) {
                throw IllegalStateException("Root access is required for memory search.")
            }

            startDaemon()
            waitForDaemonReady()
        }
    }

    fun isDaemonAlive(): Boolean {
        return MemoryToolDaemonClient.ping(socketName)
    }

    private fun startDaemon() {
        val sourceDir = context.applicationInfo.sourceDir
        val memoryToolLibPath = extractHelperLibrary()
        val helperLogPath = helperLogFile.absolutePath
        val mainClass = "com.jsxposed.x.core.bridge.memory_tool_native.MemoryToolHelperMain"
        helperLogFile.parentFile?.mkdirs()
        helperLogFile.writeText("")
        val command =
            "CLASSPATH=${shellEscape(sourceDir)} " +
                "/system/bin/app_process /system/bin $mainClass " +
                "${shellEscape(memoryToolLibPath)} ${shellEscape(socketName)} " +
                ">${shellEscape(helperLogPath)} 2>&1 &"
        LogX.i(TAG, "start daemon", socketName)
        Runtime.getRuntime().exec(arrayOf("su", "-c", command))
    }

    private fun extractHelperLibrary(): String {
        val apkPath = context.applicationInfo.sourceDir
        val supportedAbis = Build.SUPPORTED_ABIS.toList()
        val helperLibraryFile = File(helperLibraryDirectory, "libmemory_tool.so")

        ZipFile(apkPath).use { zipFile ->
            val abiEntry = supportedAbis.firstNotNullOfOrNull { abi ->
                zipFile.getEntry("lib/$abi/libmemory_tool.so")
            } ?: throw IllegalStateException(
                "libmemory_tool.so not found in APK for supported ABIs: $supportedAbis"
            )

            helperLibraryDirectory.mkdirs()
            helperLibraryDirectory.setReadable(true, false)
            helperLibraryDirectory.setExecutable(true, false)

            zipFile.getInputStream(abiEntry).use { input ->
                helperLibraryFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
        }

        helperLibraryFile.setReadable(true, false)
        helperLibraryFile.setExecutable(true, false)
        return helperLibraryFile.absolutePath
    }

    private fun waitForDaemonReady() {
        repeat(STARTUP_RETRY_COUNT) {
            if (isDaemonAlive()) {
                return
            }
            Thread.sleep(STARTUP_RETRY_DELAY_MS)
        }

        throw IllegalStateException(buildDaemonStartFailureMessage())
    }

    private fun hasRootAccess(): Boolean {
        val output = Shell(su = true).execute("id")
        return output.contains("uid=0")
    }

    private fun shellEscape(value: String): String {
        return "'${value.replace("'", "'\"'\"'")}'"
    }

    private fun buildDaemonStartFailureMessage(): String {
        val helperLog = helperLogFile.takeIf { it.exists() }?.readText().orEmpty().trim()
        if (helperLog.isBlank()) {
            return "Memory tool helper daemon did not start."
        }

        val lines = helperLog.lines()
        val startIndex = (lines.size - 20).coerceAtLeast(0)
        val tail = lines
            .subList(startIndex, lines.size)
            .joinToString(separator = "\n")

        return "Memory tool helper daemon did not start.\n$tail"
    }
}
