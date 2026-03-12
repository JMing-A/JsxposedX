package com.jsxposed.x.core.bridge.project_native

import android.content.Context
import android.os.Build
import androidx.annotation.RequiresApi
import com.jsxposed.x.core.bridge.xposed_js_snapshot.XposedScriptSnapshotRepository
import com.jsxposed.x.core.models.Encrypt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class ProjectNativeImpl(val context: Context) : ProjectNative {
    companion object {
        // Avoid blocking UI thread
        private val fridaExecutor = Executors.newSingleThreadExecutor()
    }

    private val snapshotRepository by lazy { XposedScriptSnapshotRepository(context) }
    override fun initProject() = runBlocking(Dispatchers.IO) {
        Project(context).initProject()
    }

    override fun projectExists(packageName: String): Boolean = runBlocking(Dispatchers.IO) {
        Project(context).projectExists(packageName)
    }

    override fun createProject(packageName: String) = runBlocking(Dispatchers.IO) {
        Project(context).createProject(packageName)
    }

    override fun deleteProject(packageName: String) = runBlocking(Dispatchers.IO) {
        Project(context).deleteProject(packageName)
    }

    override fun getProjects(): List<AppInfo> = runBlocking(Dispatchers.IO) {
        Project(context).getProjects()
    }

    override fun getFridaScripts(packageName: String): List<String> = runBlocking(Dispatchers.IO) {
        Project(context).getFridaScripts(packageName)
    }

    override fun createFridaScript(
        packageName: String, content: String, localPath: String, append: Boolean
    ) = runBlocking(Dispatchers.IO) {
        Project(context).createFridaScript(
            packageName = packageName, content = content, localPath = localPath, append = append
        )
    }

    override fun readFridaScript(
        packageName: String, localPath: String
    ): String = runBlocking(Dispatchers.IO) {
        Project(context).readFridaScript(
            packageName = packageName,
            localPath = localPath,
        )
    }

    override fun deleteFridaScript(packageName: String, scriptName: String) =
        runBlocking(Dispatchers.IO) {
            Project(context).deleteFridaScript(packageName, scriptName)
        }

    override fun importFridaScripts(
        packageName: String, localPaths: List<String>, callback: (Result<Unit>) -> Unit
    ) {
        runBlocking(Dispatchers.IO) {
            try {
                Project(context).importFridaScripts(packageName, localPaths)
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }


    override fun bundleFridaHookJs(packageName: String, callback: (Result<Unit>) -> Unit) {
        Thread {
            try {
                runBlocking(Dispatchers.IO) {
                    Project(context).bundleFridaHookJs(packageName)
                }
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }.start()
    }

    override fun getJsScripts(packageName: String): List<String> = runBlocking(Dispatchers.IO) {
        Project(context).getJsScripts(packageName)
    }

    override fun createJsScript(
        packageName: String, content: String, localPath: String, append: Boolean
    ) = runBlocking(Dispatchers.IO) {
        Project(context).createJsScript(
            packageName = packageName, content = content, localPath = localPath, append = append
        )
        snapshotRepository.writeSnapshot(packageName)
    }

    override fun readJsScript(packageName: String, localPath: String): String =
        runBlocking(Dispatchers.IO) {
            Project(context).readJsScript(
                packageName = packageName,
                localPath = localPath,
            )
        }

    override fun deleteJsScript(packageName: String, localPath: String) =
        runBlocking(Dispatchers.IO) {
            Project(context).deleteJsScript(packageName, localPath)
            snapshotRepository.writeSnapshot(packageName)
        }

    override fun importJsScripts(
        packageName: String, localPaths: List<String>, callback: (Result<Unit>) -> Unit
    ) {
        runBlocking(Dispatchers.IO) {
            try {
                Project(context).importJsScripts(packageName, localPaths)
                snapshotRepository.writeSnapshot(packageName)
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.FROYO)
    override fun getAuditLogs(
        packageName: String,
        limit: Long,
        offset: Long,
        keyword: String?,
        callback: (Result<List<AuditLog?>>) -> Unit
    ) {
        val project = Project(context)
        runBlocking(Dispatchers.IO) {
            try {
                val logs = project.getAuditLogs(packageName, limit, offset, keyword)
                val pigeonLogs = logs.map { encrypt ->
                    AuditLog(
                        algorithm = encrypt.algorithm,
                        operation = encrypt.operation.toLong(),
                        key = encrypt.key,
                        keyBase64 = Project.hexToBase64(encrypt.key),
                        keyPlaintext = Project.hexToPlaintext(encrypt.key),
                        iv = encrypt.iv,
                        ivBase64 = Project.hexToBase64(encrypt.iv),
                        ivPlaintext = Project.hexToPlaintext(encrypt.iv),
                        input = encrypt.input,
                        inputBase64 = Project.hexToBase64(encrypt.inputHex),
                        output = encrypt.output,
                        outputBase64 = Project.hexToBase64(encrypt.outputHex),
                        inputHex = encrypt.inputHex,
                        outputHex = encrypt.outputHex,
                        stackTrace = encrypt.stackTrace,
                        fingerprint = encrypt.fingerprint,
                        timestamp = encrypt.timestamp
                    )
                }
                callback(Result.success(pigeonLogs))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun deleteAuditLog(
        packageName: String, timestamp: Long, callback: (Result<Unit>) -> Unit
    ) {
        val project = Project(context)
        runBlocking(Dispatchers.IO) {
            try {
                project.deleteAuditLog(packageName, timestamp)
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun updateAuditLog(
        packageName: String, updatedLog: AuditLog, callback: (Result<Unit>) -> Unit
    ) {
        val project = Project(context)
        runBlocking(Dispatchers.IO) {
            try {
                val encrypt = Encrypt(
                    algorithm = updatedLog.algorithm,
                    operation = updatedLog.operation.toInt(),
                    key = updatedLog.key,
                    iv = updatedLog.iv,
                    input = updatedLog.input,
                    output = updatedLog.output,
                    inputHex = updatedLog.inputHex,
                    outputHex = updatedLog.outputHex,
                    stackTrace = updatedLog.stackTrace.filterNotNull(),
                    fingerprint = updatedLog.fingerprint,
                    timestamp = updatedLog.timestamp
                )
                project.updateAuditLog(packageName, encrypt)
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun clearAuditLogs(packageName: String, callback: (Result<Unit>) -> Unit) {
        val project = Project(context)
        runBlocking(Dispatchers.IO) {
            try {
                project.clearAuditLogs(packageName)
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }
}
