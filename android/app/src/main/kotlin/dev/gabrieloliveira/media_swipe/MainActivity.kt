package dev.gabrieloliveira.media_swipe

import android.app.usage.StorageStatsManager
import android.content.ClipData
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaMetadataRetriever
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
import androidx.core.content.FileProvider
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
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
/** Quadro chapado ou que não abriu (o Dart ignora na comparação). */
private const val FLAT_FRAME = Long.MIN_VALUE

private val VIDEO_EXTENSIONS = setOf("mp4", "mkv", "mov", "3gp", "webm", "avi", "m4v")

class MainActivity : FlutterActivity() {
    private val worker = Executors.newFixedThreadPool(3)
    private val main = Handler(Looper.getMainLooper())
    private lateinit var channel: MethodChannel

    // Compressão em andamento (uma por vez).
    private var transformer: Transformer? = null
    private var pendingCompress: MethodChannel.Result? = null
    private val progressHolder = ProgressHolder()
    private val progressTick = object : Runnable {
        override fun run() {
            val current = transformer ?: return
            if (current.getProgress(progressHolder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                channel.invokeMethod("compressProgress", progressHolder.progress)
            }
            main.postDelayed(this, 300)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "media_swipe/native")
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAllFilesAccess" -> result.success(Environment.isExternalStorageManager())

                    "requestAllFilesAccess" -> {
                        openAllFilesSettings()
                        result.success(null)
                    }

                    "storageStats" -> result.success(storageStats())

                    "storageVolumes" -> result.success(storageVolumes())

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

                    "videoInfo" -> {
                        val path = call.argument<String>("path")!!
                        worker.execute {
                            val info = try {
                                videoInfo(path)
                            } catch (e: Exception) {
                                null
                            }
                            main.post { result.success(info) }
                        }
                    }

                    "compressVideo" -> {
                        if (transformer != null) {
                            result.error("busy", "Já tem uma compressão rodando", null)
                        } else {
                            startCompression(
                                input = call.argument<String>("input")!!,
                                output = call.argument<String>("output")!!,
                                shortSide = call.argument<Int>("shortSide")!!,
                                bitrate = call.argument<Int>("bitrate")!!,
                                result = result,
                            )
                        }
                    }

                    "cancelCompress" -> {
                        transformer?.cancel()
                        // cancel() não chama o listener: responde a chamada pendente aqui.
                        pendingCompress?.error("cancelled", "Cancelado", null)
                        finishCompression()
                        result.success(null)
                    }

                    "share" -> {
                        share(call.argument<List<String>>("paths")!!)
                        result.success(null)
                    }

                    "fingerprints" -> {
                        val paths = call.argument<List<String>>("paths")!!
                        val videos = call.argument<List<Boolean>>("videos")!!
                        worker.execute {
                            val out = paths.indices.map { i ->
                                try {
                                    fingerprint(paths[i], videos[i])
                                } catch (e: Exception) {
                                    null // arquivo que não abre: fica de fora
                                }
                            }
                            main.post { result.success(out) }
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

    /**
     * Volumes montados (armazenamento interno e cartão SD), com caminho e
     * espaço. O interno usa a capacidade de fábrica, igual ao [storageStats].
     */
    private fun storageVolumes(): List<Map<String, Any>> {
        val manager = getSystemService(StorageManager::class.java)
        return manager.storageVolumes
            .filter { it.state == Environment.MEDIA_MOUNTED && it.directory != null }
            .map { volume ->
                val path = volume.directory!!.path
                val stat = StatFs(path)
                val (total, free) = if (volume.isPrimary) {
                    val stats = storageStats()
                    stats.getValue("total") to stats.getValue("free")
                } else {
                    stat.totalBytes to stat.availableBytes
                }
                mapOf(
                    "path" to path,
                    "label" to volume.getDescription(this),
                    "removable" to volume.isRemovable,
                    "primary" to volume.isPrimary,
                    "total" to total,
                    "free" to free,
                )
            }
    }

    /**
     * Abre o "compartilhar" do Android com os arquivos. Não copia nada: o
     * FileProvider dá ao app escolhido acesso de leitura ao arquivo original.
     */
    private fun share(paths: List<String>) {
        val uris = ArrayList(paths.map { FileProvider.getUriForFile(this, "$packageName.files", File(it)) })
        val videos = paths.count { it.substringAfterLast('.').lowercase() in VIDEO_EXTENSIONS }
        val mime = when (videos) {
            0 -> "image/*"
            paths.size -> "video/*"
            else -> "*/*"
        }
        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris.first())
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        }
        intent.type = mime
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        // ClipData faz a permissão de leitura valer pra todos os arquivos.
        intent.clipData = ClipData.newRawUri("arquivos", uris.first()).apply {
            uris.drop(1).forEach { addItem(ClipData.Item(it)) }
        }
        startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
    }

    /**
     * "Impressão digital" pra achar mídia parecida (não idêntica): vídeo vira
     * 3 quadros (a 10%, 50% e 90%), foto vira 1. Cada quadro é reduzido a
     * 9×8 em cinza e vira 64 bits (dHash: cada bit diz se o pixel é mais
     * claro que o vizinho). Quadros parecidos têm poucos bits diferentes,
     * mesmo depois de recomprimir ou mudar a resolução.
     */
    private fun fingerprint(path: String, video: Boolean): Map<String, Any> {
        if (!video) {
            val thumb = ThumbnailUtils.createImageThumbnail(File(path), Size(64, 64), null)
            val hash = dHash(thumb)
            thumb.recycle()
            return mapOf("duration" to 0L, "hashes" to longArrayOf(hash))
        }
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val hashes = LongArray(3)
            listOf(0.1, 0.5, 0.9).forEachIndexed { i, at ->
                val frame = retriever.getScaledFrameAtTime(
                    (duration * 1000 * at).toLong(),
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    64,
                    64,
                )
                hashes[i] = if (frame == null) FLAT_FRAME else dHash(frame).also { frame.recycle() }
            }
            return mapOf("duration" to duration, "hashes" to hashes)
        } finally {
            retriever.release()
        }
    }

    private fun dHash(source: Bitmap): Long {
        val small = Bitmap.createScaledBitmap(source, 9, 8, true)
        val gray = IntArray(72)
        var min = 255
        var max = 0
        for (y in 0 until 8) {
            for (x in 0 until 9) {
                val c = small.getPixel(x, y)
                val g = (Color.red(c) * 299 + Color.green(c) * 587 + Color.blue(c) * 114) / 1000
                gray[y * 9 + x] = g
                if (g < min) min = g
                if (g > max) max = g
            }
        }
        if (small != source) small.recycle()
        // Quadro chapado (tela preta, branca...): qualquer um "parece" com
        // qualquer outro. Marca pra comparação ignorar.
        if (max - min < 12) return FLAT_FRAME
        var hash = 0L
        var bit = 0
        for (y in 0 until 8) {
            for (x in 0 until 8) {
                if (gray[y * 9 + x] > gray[y * 9 + x + 1]) hash = hash or (1L shl bit)
                bit++
            }
        }
        return hash
    }

    /** Largura e altura já como aparecem na tela (rotação aplicada). */
    private fun videoInfo(path: String): Map<String, Long> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            fun long(key: Int) = retriever.extractMetadata(key)?.toLongOrNull() ?: 0L
            var width = long(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            var height = long(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val rotation = long(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            if (rotation == 90L || rotation == 270L) width = height.also { height = width }
            return mapOf(
                "width" to width,
                "height" to height,
                "bitrate" to long(MediaMetadataRetriever.METADATA_KEY_BITRATE),
                "durationMs" to long(MediaMetadataRetriever.METADATA_KEY_DURATION),
            )
        } finally {
            retriever.release()
        }
    }

    /**
     * Recodifica em H.264 com o lado menor em [shortSide] e o [bitrate] pedido.
     * O áudio passa direto quando dá. Responde quando termina; o progresso vai
     * pelo método "compressProgress" do canal.
     */
    private fun startCompression(
        input: String,
        output: String,
        shortSide: Int,
        bitrate: Int,
        result: MethodChannel.Result,
    ) {
        val encoder = DefaultEncoderFactory.Builder(this)
            .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build())
            .build()
        val job = Transformer.Builder(this)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setEncoderFactory(encoder)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    val pending = pendingCompress
                    finishCompression()
                    pending?.success(null)
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    val pending = pendingCompress
                    finishCompression()
                    pending?.error("compress", exportException.message, null)
                }
            })
            .build()
        val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(input))))
            .setEffects(Effects(emptyList(), listOf(Presentation.createForShortSide(shortSide))))
            .build()
        transformer = job
        pendingCompress = result
        job.start(item, output)
        main.post(progressTick)
    }

    private fun finishCompression() {
        transformer = null
        pendingCompress = null
        main.removeCallbacks(progressTick)
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
