package com.zapi.chat

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.AudioEncoderSettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

data class VideoMetadataInfo(
    val durationMs: Long,
    val width: Int,
    val height: Int,
)

@OptIn(UnstableApi::class)
object ZapiVideoTranscoder {

    private val mainHandler = Handler(Looper.getMainLooper())

    fun readMetadata(path: String): VideoMetadataInfo {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val dur = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val rawW = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            val rawH = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            val rot = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            val swapped = rot == 90 || rot == 270
            VideoMetadataInfo(
                durationMs = max(0L, dur),
                width = if (swapped) rawH else rawW,
                height = if (swapped) rawW else rawH,
            )
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    fun trimAndCompress(
        context: Context,
        inputPath: String,
        startMs: Long,
        endMs: Long,
        maxBytes: Long,
        removeAudio: Boolean = false,
        onComplete: (Map<String, Any?>) -> Unit,
        onFailure: (String) -> Unit,
    ) {
        val inputFile = File(inputPath)
        if (!inputFile.exists()) {
            onFailure("Arquivo de vídeo não encontrado.")
            return
        }

        val info = try {
            readMetadata(inputPath)
        } catch (_: Exception) {
            VideoMetadataInfo(durationMs = max(1000L, endMs - startMs), width = 720, height = 1280)
        }

        val safeStart = startMs.coerceIn(0L, max(0L, info.durationMs - 1000L))
        val effectiveEnd = if (endMs > safeStart + 500L) {
            min(endMs, if (info.durationMs > 0) info.durationMs else endMs)
        } else {
            min(safeStart + 60_000L, max(safeStart + 1000L, info.durationMs))
        }
        val clipDurationMs = max(1000L, effectiveEnd - safeStart)

        if (clipDurationMs > 60_500L) {
            onComplete(
                mapOf(
                    "tooLarge" to true,
                    "durationMs" to clipDurationMs,
                    "sizeBytes" to inputFile.length(),
                )
            )
            return
        }

        // Fast-path: if user kept full/nearly-full short clip, audio isn't being stripped, and file is under maxBytes
        val fullRangeSelected = safeStart <= 150L &&
            (info.durationMs <= 0L || effectiveEnd >= info.durationMs - 150L)
        if (!removeAudio && fullRangeSelected && inputFile.length() in 1..maxBytes) {
            onComplete(
                mapOf(
                    "tooLarge" to false,
                    "path" to inputFile.absolutePath,
                    "sizeBytes" to inputFile.length(),
                    "durationMs" to clipDurationMs,
                )
            )
            return
        }

        val outDir = File(context.cacheDir, "zapi_video_out").apply {
            if (!exists()) mkdirs()
        }

        val clipSec = max(1.0, clipDurationMs / 1000.0)
        val targetTotalBps = ((maxBytes * 8.0 * 0.84) / clipSec).toInt()
        val audioBps = if (removeAudio) {
            0
        } else {
            when {
                targetTotalBps >= 260_000 -> 48_000
                targetTotalBps >= 140_000 -> 32_000
                else -> 24_000
            }
        }
        val videoBps = (targetTotalBps - audioBps).coerceIn(48_000, 1_400_000)
        val shortSide = when {
            videoBps >= 480_000 -> 720
            videoBps >= 220_000 -> 480
            videoBps >= 105_000 -> 360
            else -> 240
        }

        val pass1File = File(outDir, "zapi_vid_${UUID.randomUUID()}.mp4")
        runPass(
            context = context,
            inputUri = Uri.fromFile(inputFile),
            outputFile = pass1File,
            sourceInfo = info,
            startMs = safeStart,
            endMs = effectiveEnd,
            shortSide = shortSide,
            videoBps = videoBps,
            audioBps = audioBps,
            removeAudio = removeAudio,
            onDone = { outFile ->
                val actualSize = outFile.length()
                if (actualSize <= maxBytes && actualSize > 0L) {
                    onComplete(
                        mapOf(
                            "tooLarge" to false,
                            "path" to outFile.absolutePath,
                            "sizeBytes" to actualSize,
                            "durationMs" to clipDurationMs,
                        )
                    )
                } else {
                    // Second tighter pass if hardware encoder overshot VBR cap
                    val ratio = if (actualSize > 0L) maxBytes.toDouble() / actualSize.toDouble() else 0.5
                    val retryVideoBps = (videoBps * ratio * 0.78).toInt().coerceIn(36_000, 600_000)
                    val pass2File = File(outDir, "zapi_vid_${UUID.randomUUID()}_p2.mp4")
                    outFile.delete()
                    runPass(
                        context = context,
                        inputUri = Uri.fromFile(inputFile),
                        outputFile = pass2File,
                        sourceInfo = info,
                        startMs = safeStart,
                        endMs = effectiveEnd,
                        shortSide = 240,
                        videoBps = retryVideoBps,
                        audioBps = if (removeAudio) 0 else 20_000,
                        removeAudio = removeAudio,
                        onDone = { secondFile ->
                            val secondSize = secondFile.length()
                            if (secondSize <= maxBytes && secondSize > 0L) {
                                onComplete(
                                    mapOf(
                                        "tooLarge" to false,
                                        "path" to secondFile.absolutePath,
                                        "sizeBytes" to secondSize,
                                        "durationMs" to clipDurationMs,
                                    )
                                )
                            } else {
                                secondFile.delete()
                                onComplete(
                                    mapOf(
                                        "tooLarge" to true,
                                        "sizeBytes" to secondSize,
                                        "durationMs" to clipDurationMs,
                                    )
                                )
                            }
                        },
                        onError = { err ->
                            pass2File.delete()
                            onFailure(err)
                        },
                    )
                }
            },
            onError = { err ->
                pass1File.delete()
                onFailure(err)
            },
        )
    }

    private fun runPass(
        context: Context,
        inputUri: Uri,
        outputFile: File,
        sourceInfo: VideoMetadataInfo,
        startMs: Long,
        endMs: Long,
        shortSide: Int,
        videoBps: Int,
        audioBps: Int,
        removeAudio: Boolean,
        onDone: (File) -> Unit,
        onError: (String) -> Unit,
    ) {
        mainHandler.post {
            try {
                val clippingConfig = MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .build()

                val mediaItem = MediaItem.Builder()
                    .setUri(inputUri)
                    .setClippingConfiguration(clippingConfig)
                    .build()

                val minSourceSide = min(sourceInfo.width, sourceInfo.height)
                val videoEffects = if (minSourceSide <= 0 || minSourceSide > shortSide) {
                    listOf(Presentation.createForShortSide(shortSide))
                } else {
                    emptyList()
                }

                val editedItem = EditedMediaItem.Builder(mediaItem)
                    .setRemoveAudio(removeAudio)
                    .setEffects(Effects(emptyList(), videoEffects))
                    .build()

                val videoSettings = VideoEncoderSettings.Builder()
                    .setBitrate(videoBps)
                    .build()

                val audioSettings = AudioEncoderSettings.Builder()
                    .setBitrate(if (removeAudio) 24_000 else audioBps)
                    .build()

                val encoderFactory = DefaultEncoderFactory.Builder(context)
                    .setRequestedVideoEncoderSettings(videoSettings)
                    .setRequestedAudioEncoderSettings(audioSettings)
                    .setEnableFallback(true)
                    .build()

                val transformer = Transformer.Builder(context)
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .setEncoderFactory(encoderFactory)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(
                            composition: Composition,
                            exportResult: ExportResult,
                        ) {
                            onDone(outputFile)
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException,
                        ) {
                            onError(
                                exportException.localizedMessage
                                    ?: "Não foi possível preparar este vídeo."
                            )
                        }
                    })
                    .build()

                transformer.start(editedItem, outputFile.absolutePath)
            } catch (e: Exception) {
                onError(e.localizedMessage ?: "Não foi possível preparar este vídeo.")
            }
        }
    }
}
