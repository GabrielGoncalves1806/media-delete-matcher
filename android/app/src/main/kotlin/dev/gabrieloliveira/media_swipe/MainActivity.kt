package dev.gabrieloliveira.media_swipe

import android.app.usage.StorageStatsManager
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.Settings
import android.util.Size
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * O que o Dart não faz sozinho: permissão de "acesso a todos os arquivos",
 * miniaturas, espaço livre e avisar a galeria quando um arquivo sai do lugar.
 */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newFixedThreadPool(3)
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "media_swipe/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAllFilesAccess" -> result.success(Environment.isExternalStorageManager())

                    "requestAllFilesAccess" -> {
                        openAllFilesSettings()
                        result.success(null)
                    }

                    "storageStats" -> result.success(storageStats())

                    "thumbnail" -> {
                        val path = call.argument<String>("path")!!
                        val size = call.argument<Int>("size") ?: 400
                        val video = call.argument<Boolean>("video") ?: false
                        worker.execute {
                            val bytes = try {
                                thumbnail(File(path), size, video)
                            } catch (e: Exception) {
                                null // arquivo corrompido ou formato sem suporte
                            }
                            main.post { result.success(bytes) }
                        }
                    }

                    "scanFiles" -> {
                        val paths = call.argument<List<String>>("paths")!!
                        if (paths.isNotEmpty()) {
                            MediaScannerConnection.scanFile(this, paths.toTypedArray(), null, null)
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * total: capacidade de fábrica (os "128 GB" da caixa), igual a tela de
     * armazenamento do Android. system: o que não é partição de dados
     * (sistema operacional e partições reservadas). Não precisa de permissão.
     */
    private fun storageStats(): Map<String, Long> {
        val data = StatFs(Environment.getDataDirectory().path)
        val (total, free) = try {
            val stats = getSystemService(StorageStatsManager::class.java)
            stats.getTotalBytes(StorageManager.UUID_DEFAULT) to stats.getFreeBytes(StorageManager.UUID_DEFAULT)
        } catch (e: Exception) {
            data.totalBytes to data.availableBytes
        }
        return mapOf(
            "total" to total,
            "free" to free,
            "system" to (total - data.totalBytes).coerceAtLeast(0),
        )
    }

    private fun thumbnail(file: File, size: Int, video: Boolean): ByteArray {
        val target = Size(size, size)
        val bitmap = if (video) {
            ThumbnailUtils.createVideoThumbnail(file, target, null)
        } else {
            ThumbnailUtils.createImageThumbnail(file, target, null)
        }
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    private fun openAllFilesSettings() {
        try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName"),
                ),
            )
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
    }
}
