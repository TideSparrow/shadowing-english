package com.shadowing.english

import android.app.Activity
import android.media.AudioFormat
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.DocumentsContract
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ceil

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler {
    private lateinit var importPickerChannel: MethodChannel
    private lateinit var nativeTtsChannel: MethodChannel
    private lateinit var audioToolsChannel: MethodChannel
    private var pendingResult: MethodChannel.Result? = null
    private var pendingExtensions: Set<String> = emptySet()
    private var pendingTitle: String = ""
    private var pendingCopyFiles: Boolean = true
    private val mainHandler = Handler(Looper.getMainLooper())
    private var nativeTts: TextToSpeech? = null
    private var nativeTtsEngine: String = ""
    private var nativeTtsInitializing: Boolean = false
    private var nativeTtsReady: Boolean = false
    private val pendingTtsRequests = ArrayDeque<NativeTtsRequest>()
    private var activeTtsResult: MethodChannel.Result? = null
    private var activeTtsUtteranceId: String? = null
    private val pronunciationExtractionRequests =
        ConcurrentHashMap<String, AtomicBoolean>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        importPickerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.shadowing.english/import_picker",
        )
        importPickerChannel.setMethodCallHandler(this)
        nativeTtsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.shadowing.english/native_tts",
        )
        nativeTtsChannel.setMethodCallHandler(this)
        audioToolsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.shadowing.english/audio_tools",
        )
        audioToolsChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectoryFiles" -> handlePickDirectoryFiles(call, result)
            "copyPickedFile" -> handleCopyPickedFile(call, result)
            "speak" -> handleNativeTtsSpeak(call, result)
            "stop" -> handleNativeTtsStop(result)
            "getEngines" -> handleNativeTtsGetEngines(result)
            "getVoices" -> handleNativeTtsGetVoices(call, result)
            "splitAudio" -> handleSplitAudio(call, result)
            "extractPronunciationAudio" -> handlePronunciationAudioExtraction(call, result)
            "cancelPronunciationAudioExtraction" -> handleCancelPronunciationAudioExtraction(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handlePickDirectoryFiles(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "Another import picker request is running.", null)
            return
        }

        @Suppress("UNCHECKED_CAST")
        val extensions = (call.argument<List<String>>("extensions") ?: emptyList())
            .map { it.lowercase(Locale.US) }
            .toSet()
        pendingExtensions = extensions
        pendingTitle = call.argument<String>("title") ?: "导入目录"
        pendingCopyFiles = call.argument<Boolean>("copyFiles") ?: true
        pendingResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        startActivityForResult(intent, REQUEST_PICK_DIRECTORY)
    }

    private fun handleCopyPickedFile(call: MethodCall, result: MethodChannel.Result) {
        val sourceUri = call.argument<String>("sourceUri")
        val destinationName = call.argument<String>("destinationName")
        if (sourceUri.isNullOrEmpty() || destinationName.isNullOrEmpty()) {
            result.error("bad_args", "sourceUri and destinationName are required.", null)
            return
        }

        Thread {
            try {
                val copied = copyPickedFileToManagedStorage(
                    Uri.parse(sourceUri),
                    destinationName,
                )
                postResult(result, copied)
            } catch (exception: Exception) {
                postError(result, exception)
            }
        }.start()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_DIRECTORY) {
          return
        }

        val result = pendingResult
        pendingResult = null
        if (result == null) {
            return
        }
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        val uri = data.data!!
        val takeFlags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        contentResolver.takePersistableUriPermission(uri, takeFlags)

        Thread {
            try {
                val tree = DocumentFile.fromTreeUri(this, uri)
                if (tree == null || !tree.isDirectory) {
                    postResult(result, null)
                    return@Thread
                }

                val importId = UUID.randomUUID().toString()
                val targetRoot = File(managedImportBaseDir(), importId)
                ensureDirectoryExists(targetRoot, "imported sources root")

                val copiedFiles = mutableListOf<String>()
                val sourceUris = mutableMapOf<String, String>()
                collectAndCopyFiles(
                    node = tree,
                    root = tree,
                    allowedExtensions = pendingExtensions,
                    targetRoot = targetRoot,
                    copyFiles = pendingCopyFiles,
                    out = copiedFiles,
                    sourceUris = sourceUris,
                )

                val folderName = tree.name ?: pendingTitle
                val label = "$folderName（${copiedFiles.size} 个文件）"
                postResult(
                    result,
                    mapOf(
                        "folderName" to folderName,
                        "label" to label,
                        "files" to copiedFiles,
                        "sourceUris" to sourceUris,
                    ),
                )
            } catch (exception: Exception) {
                postError(result, exception)
            }
        }.start()
    }

    private fun collectAndCopyFiles(
        node: DocumentFile,
        root: DocumentFile,
        allowedExtensions: Set<String>,
        targetRoot: File,
        copyFiles: Boolean,
        out: MutableList<String>,
        sourceUris: MutableMap<String, String>,
    ) {
        if (node.isDirectory) {
            node.listFiles().forEach { child ->
                collectAndCopyFiles(
                    child,
                    root,
                    allowedExtensions,
                    targetRoot,
                    copyFiles,
                    out,
                    sourceUris,
                )
            }
            return
        }
        if (!node.isFile) {
            return
        }

        val name = node.name ?: return
        val extension = name.substringAfterLast('.', "").lowercase(Locale.US)
        if (extension.isEmpty() || !allowedExtensions.contains(extension)) {
            return
        }

        val relativePath = relativePath(root.uri, node.uri)
        val destination = File(targetRoot, sanitizeRelativePath(relativePath))
        destination.parentFile?.let { parent ->
            ensureDirectoryExists(parent, "picked directory copy parent")
        }
        if (copyFiles) {
            copyUriToFile(node.uri, destination)
        } else if (!destination.exists()) {
            destination.createNewFile()
            sourceUris[destination.absolutePath] = node.uri.toString()
        }
        out.add(destination.absolutePath)
    }

    private fun copyPickedFileToManagedStorage(sourceUri: Uri, destinationName: String): String {
        val targetRoot = File(
            managedImportBaseDir(),
            "confirmed_imports/${UUID.randomUUID()}",
        )
        ensureDirectoryExists(targetRoot, "confirmed import root")
        val destination = File(targetRoot, sanitizeFileName(destinationName))
        destination.parentFile?.let { parent ->
            ensureDirectoryExists(parent, "confirmed import parent")
        }
        copyUriToFile(sourceUri, destination)
        return destination.absolutePath
    }

    private fun managedImportBaseDir(): File {
        val externalFilesDir = getExternalFilesDir(null)
        val root = externalFilesDir ?: filesDir
        return File(root, "imported_sources")
    }

    private fun relativePath(rootUri: Uri, fileUri: Uri): String {
        val rootId = DocumentsContract.getDocumentId(rootUri)
        val fileId = DocumentsContract.getDocumentId(fileUri)
        return fileId.removePrefix("$rootId/")
    }

    private fun sanitizeRelativePath(value: String): String {
        return value
            .replace("..", "_")
            .replace("\\", "/")
            .trimStart('/')
    }

    private fun sanitizeFileName(value: String): String {
        return value
            .replace("/", "_")
            .replace("\\", "_")
            .replace("..", "_")
    }

    private fun copyUriToFile(uri: Uri, destination: File) {
        destination.parentFile?.let { parent ->
            ensureDirectoryExists(parent, "copy destination parent")
        }
        contentResolver.openInputStream(uri).use { inputStream ->
            FileOutputStream(destination).use { outputStream ->
                copyStream(inputStream, outputStream)
            }
        }
    }

    private fun ensureDirectoryExists(directory: File, label: String) {
        if (directory.exists()) {
            require(directory.isDirectory) {
                "$label exists but is not a directory: ${directory.absolutePath}"
            }
            return
        }
        check(directory.mkdirs()) {
            "failed to create $label: ${directory.absolutePath}"
        }
    }

    private fun copyStream(inputStream: InputStream?, outputStream: OutputStream) {
        requireNotNull(inputStream)
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val count = inputStream.read(buffer)
            if (count < 0) {
                break
            }
            outputStream.write(buffer, 0, count)
        }
        outputStream.flush()
    }

    private fun postResult(result: MethodChannel.Result, value: Any?) {
        Handler(Looper.getMainLooper()).post {
            result.success(value)
        }
    }

    private fun postError(result: MethodChannel.Result, throwable: Throwable) {
        Handler(Looper.getMainLooper()).post {
            result.error("import_picker_failed", throwable.message, null)
        }
    }

    private fun handleNativeTtsSpeak(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")?.trim()
        if (text.isNullOrEmpty()) {
            result.success(true)
            return
        }

        mainHandler.post {
            pendingTtsRequests.addLast(
                NativeTtsRequest(
                    text = text,
                    language = call.argument<String>("language") ?: "en-US",
                    engine = call.argument<String>("engine")?.trim().orEmpty(),
                    voice = call.argument<String>("voice")?.trim().orEmpty(),
                    rate = call.argument<Double>("rate")?.toFloat() ?: 0.75f,
                    result = result,
                ),
            )
            drainNativeTtsRequests()
        }
    }

    private fun handleNativeTtsStop(result: MethodChannel.Result) {
        mainHandler.post {
            activeTtsResult?.success(true)
            activeTtsResult = null
            activeTtsUtteranceId = null
            while (pendingTtsRequests.isNotEmpty()) {
                pendingTtsRequests.removeFirst().result.success(true)
            }
            nativeTts?.stop()
            result.success(true)
        }
    }

    private fun handleNativeTtsGetEngines(result: MethodChannel.Result) {
        val defaultEngine = systemDefaultTtsEngine().orEmpty()
        val engines = installedTtsEngines().map { engine ->
            mapOf(
                "id" to engine.serviceInfo.packageName,
                "label" to engine.loadLabel(packageManager).toString(),
                "isDefault" to (engine.serviceInfo.packageName == defaultEngine),
            )
        }
        result.success(
            mapOf(
                "defaultEngine" to defaultEngine,
                "engines" to engines,
            ),
        )
    }

    private fun handleNativeTtsGetVoices(call: MethodCall, result: MethodChannel.Result) {
        val engine = resolveTtsEngine(call.argument<String>("engine")?.trim().orEmpty())
        if (engine == null) {
            result.success(mapOf("voices" to emptyList<Map<String, String>>()))
            return
        }
        var tts: TextToSpeech? = null
        tts = TextToSpeech(this, { status ->
            val voices = if (status == TextToSpeech.SUCCESS) {
                tts?.voices
                    ?.asSequence()
                    ?.filter { it.locale.language == "en" }
                    ?.filter { !it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) }
                    ?.sortedWith(
                        compareByDescending<android.speech.tts.Voice> { it.quality }
                            .thenBy { it.latency },
                    )
                    ?.map { voice ->
                        mapOf(
                            "id" to voice.name,
                            "label" to "${voice.locale.getDisplayName(Locale.SIMPLIFIED_CHINESE)} · ${voiceQualityLabel(voice.quality)} · ${voice.name}",
                        )
                    }
                    ?.toList()
                    ?: emptyList()
            } else {
                emptyList()
            }
            tts?.shutdown()
            result.success(mapOf("voices" to voices))
        }, engine)
    }

    private fun handleSplitAudio(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val chunkMs = call.argument<Int>("chunkMs") ?: 58000
        if (sourcePath.isNullOrEmpty()) {
            result.error("bad_args", "sourcePath is required.", null)
            return
        }
        Thread {
            try {
                postResult(result, splitAudio(sourcePath, chunkMs))
            } catch (exception: Exception) {
                postError(result, exception)
            }
        }.start()
    }

    private fun handlePronunciationAudioExtraction(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val requestId = call.argument<String>("requestId")
        val sourcePath = call.argument<String>("sourcePath")
        val startMs = call.argument<Int>("startMs")
        val endMs = call.argument<Int>("endMs")
        if (requestId.isNullOrBlank() || sourcePath.isNullOrBlank() ||
            startMs == null || endMs == null || startMs < 0 || endMs <= startMs ||
            endMs - startMs > MAX_PRONUNCIATION_SEGMENT_MS
        ) {
            result.error("bad_args", "Invalid pronunciation audio range.", null)
            return
        }
        val cancelled = AtomicBoolean(false)
        pronunciationExtractionRequests[requestId] = cancelled
        Thread {
            val outputDir = File(cacheDir, "pronunciation_$requestId")
            try {
                val path = extractPronunciationAudio(
                    sourcePath = sourcePath,
                    startMs = startMs,
                    endMs = endMs,
                    outputDir = outputDir,
                    cancelled = cancelled,
                )
                if (cancelled.get()) {
                    outputDir.deleteRecursively()
                    postResult(result, null)
                } else {
                    postResult(result, path)
                }
            } catch (exception: Exception) {
                outputDir.deleteRecursively()
                if (cancelled.get()) {
                    postResult(result, null)
                } else {
                    Handler(Looper.getMainLooper()).post {
                        result.error(
                            "pronunciation_extract_failed",
                            "Unable to extract this video segment.",
                            null,
                        )
                    }
                }
            } finally {
                pronunciationExtractionRequests.remove(requestId, cancelled)
            }
        }.start()
    }

    private fun handleCancelPronunciationAudioExtraction(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val requestId = call.argument<String>("requestId")
        val cancelled = requestId?.let(pronunciationExtractionRequests::get)
        cancelled?.set(true)
        postResult(result, cancelled != null)
    }

    private fun extractPronunciationAudio(
        sourcePath: String,
        startMs: Int,
        endMs: Int,
        outputDir: File,
        cancelled: AtomicBoolean,
    ): String {
        val source = File(sourcePath)
        require(source.exists())
        ensureDirectoryExists(outputDir, "pronunciation audio output directory")
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        val output = File(outputDir, "reference.wav")
        var writer: WavChunkWriter? = null
        try {
            extractor.setDataSource(source.absolutePath)
            val audioTrackIndex = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: error("no audio track found")
            val sourceFormat = extractor.getTrackFormat(audioTrackIndex)
            val mime = sourceFormat.getString(MediaFormat.KEY_MIME)
                ?: error("missing audio mime")
            extractor.selectTrack(audioTrackIndex)
            val startUs = startMs.toLong() * 1000L
            val endUs = endMs.toLong() * 1000L
            extractor.seekTo(maxOf(0L, startUs - MAX_PRONUNCIATION_PREROLL_US), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            if (extractor.sampleTime >= 0L && startUs - extractor.sampleTime > MAX_PRONUNCIATION_PREROLL_US) {
                error("no nearby key frame")
            }
            val decoder = MediaCodec.createDecoderByType(mime)
            codec = decoder
            decoder.configure(sourceFormat, null, null, 0)
            decoder.start()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var pcm16OutputVerified = Build.VERSION.SDK_INT < Build.VERSION_CODES.N
            val extractionDeadlineMs =
                SystemClock.elapsedRealtime() + MAX_PRONUNCIATION_EXTRACTION_TIMEOUT_MS
            var sampleRate = sourceFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channelCount = if (sourceFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                sourceFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            } else {
                1
            }.coerceAtLeast(1)
            writer = WavChunkWriter(output)

            while (!outputDone && !cancelled.get()) {
                check(SystemClock.elapsedRealtime() < extractionDeadlineMs) {
                    "pronunciation extraction timed out"
                }
                if (!inputDone) {
                    val inputIndex = decoder.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val inputBuffer = decoder.getInputBuffer(inputIndex)!!
                        inputBuffer.clear()
                        val sampleTimeUs = extractor.sampleTime
                        val sampleSize = if (sampleTimeUs >= 0L && sampleTimeUs <= endUs) {
                            extractor.readSampleData(inputBuffer, 0)
                        } else {
                            -1
                        }
                        if (sampleSize < 0) {
                            decoder.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                endUs,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inputIndex, 0, sampleSize, sampleTimeUs, 0)
                            extractor.advance()
                        }
                    }
                }

                val outputIndex = decoder.dequeueOutputBuffer(info, 10_000)
                when {
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val format = decoder.outputFormat
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            val encoding = format.getInteger(MediaFormat.KEY_PCM_ENCODING)
                            require(encoding == AudioFormat.ENCODING_PCM_16BIT) {
                                "unsupported decoder PCM encoding"
                            }
                            pcm16OutputVerified = true
                        }
                        sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channelCount = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                            format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        } else {
                            channelCount
                        }.coerceAtLeast(1)
                    }
                    outputIndex >= 0 -> {
                        check(pcm16OutputVerified) {
                            "decoder PCM encoding was not verified"
                        }
                        val outputBuffer = decoder.getOutputBuffer(outputIndex)!!
                        if (info.size > 0 && info.presentationTimeUs < endUs) {
                            outputBuffer.position(info.offset)
                            outputBuffer.limit(info.offset + info.size)
                            val bytesPerFrame = 2 * channelCount
                            val pcm = outputBuffer.slice().order(ByteOrder.LITTLE_ENDIAN)
                            val frames = pcm.remaining() / bytesPerFrame
                            val startFrame = ceil(
                                ((startUs - info.presentationTimeUs).toDouble() * sampleRate) / 1_000_000.0,
                            ).toInt().coerceIn(0, frames)
                            val endFrame = ceil(
                                ((endUs - info.presentationTimeUs).toDouble() * sampleRate) / 1_000_000.0,
                            ).toInt().coerceIn(0, frames)
                            if (endFrame > startFrame) {
                                val bounded = pcm.duplicate().order(ByteOrder.LITTLE_ENDIAN)
                                bounded.position(startFrame * bytesPerFrame)
                                bounded.limit(endFrame * bytesPerFrame)
                                writer.writePcm(
                                    pcm = bounded.slice().order(ByteOrder.LITTLE_ENDIAN),
                                    inputSampleRate = sampleRate,
                                    inputChannelCount = channelCount,
                                )
                            }
                        }
                        if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0 ||
                            info.presentationTimeUs >= endUs
                        ) {
                            outputDone = true
                        }
                        decoder.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }
            if (cancelled.get()) {
                outputDir.deleteRecursively()
                error("cancelled")
            }
            writer.close()
            writer = null
            require(output.exists() && output.length() > WAV_HEADER_BYTES) {
                "empty pronunciation audio segment"
            }
            return output.absolutePath
        } catch (exception: Exception) {
            try {
                writer?.close()
            } catch (_: Exception) {}
            writer = null
            outputDir.deleteRecursively()
            throw exception
        } finally {
            try {
                writer?.close()
            } catch (_: Exception) {}
            try {
                codec?.stop()
            } catch (_: Exception) {}
            codec?.release()
            extractor.release()
        }
    }

    private fun splitAudio(sourcePath: String, chunkMs: Int): List<Map<String, Any>> {
        val source = File(sourcePath)
        require(source.exists()) { "source file does not exist: $sourcePath" }
        val extractor = MediaExtractor()
        extractor.setDataSource(source.absolutePath)
        val audioTrackIndex = (0 until extractor.trackCount).firstOrNull { index ->
            extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                ?.startsWith("audio/") == true
        } ?: error("no audio track found")
        val sourceFormat = extractor.getTrackFormat(audioTrackIndex)
        extractor.selectTrack(audioTrackIndex)
        val mime = sourceFormat.getString(MediaFormat.KEY_MIME) ?: error("missing audio mime")
        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(sourceFormat, null, null, 0)
        codec.start()

        val outputDir = File(cacheDir, "cle_asr_${UUID.randomUUID()}")
        ensureDirectoryExists(outputDir, "ASR audio chunk directory")
        val chunkUs = chunkMs.toLong() * 1000L
        val info = MediaCodec.BufferInfo()
        val chunks = mutableListOf<Map<String, Any>>()

        var inputDone = false
        var outputDone = false
        var sampleRate = sourceFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channelCount = if (sourceFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
            sourceFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        } else {
            1
        }.coerceAtLeast(1)
        var chunkIndex = 0
        var chunkStartUs = 0L
        var writer: WavChunkWriter? = null

        fun openWriter() {
            val output = File(outputDir, "chunk_${chunkIndex.toString().padStart(5, '0')}.wav")
            writer = WavChunkWriter(output)
            chunks.add(
                mapOf(
                    "path" to output.absolutePath,
                    "offsetMs" to (chunkStartUs / 1000L).toInt(),
                ),
            )
        }

        fun closeWriter() {
            writer?.close()
            writer = null
        }

        try {
            openWriter()
            while (!outputDone) {
                if (!inputDone) {
                    val inputIndex = codec.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val inputBuffer = codec.getInputBuffer(inputIndex)!!
                        inputBuffer.clear()
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                0L,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                sampleSize,
                                extractor.sampleTime.coerceAtLeast(0L),
                                0,
                            )
                            extractor.advance()
                        }
                    }
                }

                val outputIndex = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val outputFormat = codec.outputFormat
                        sampleRate = outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channelCount = if (outputFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                            outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        } else {
                            channelCount
                        }.coerceAtLeast(1)
                    }
                    outputIndex >= 0 -> {
                        val outputBuffer = codec.getOutputBuffer(outputIndex)!!
                        if (info.size > 0) {
                            outputBuffer.position(info.offset)
                            outputBuffer.limit(info.offset + info.size)
                            if (info.presentationTimeUs >= chunkStartUs + chunkUs) {
                                closeWriter()
                                chunkIndex += 1
                                chunkStartUs = (info.presentationTimeUs / chunkUs) * chunkUs
                                openWriter()
                            }
                            writer!!.writePcm(
                                pcm = outputBuffer.slice(),
                                inputSampleRate = sampleRate,
                                inputChannelCount = channelCount,
                            )
                        }
                        if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            outputDone = true
                        }
                        codec.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }
        } catch (exception: Exception) {
            outputDir.deleteRecursively()
            throw exception
        } finally {
            closeWriter()
            codec.stop()
            codec.release()
            extractor.release()
        }

        val existingChunks = chunks.filter { chunk ->
            File(chunk["path"] as String).length() > 0L
        }
        if (existingChunks.isEmpty()) {
            outputDir.deleteRecursively()
            error("no audio chunks were created")
        }
        return existingChunks
    }

    private class WavChunkWriter(private val file: File) {
        private val stream = FileOutputStream(file)
        private var dataBytes = 0

        init {
            stream.write(ByteArray(WAV_HEADER_BYTES))
        }

        fun writePcm(pcm: ByteBuffer, inputSampleRate: Int, inputChannelCount: Int) {
            pcm.order(ByteOrder.LITTLE_ENDIAN)
            val inputFrames = pcm.remaining() / (2 * inputChannelCount)
            if (inputFrames <= 0) {
                return
            }
            val outputFrames = (inputFrames * WAV_SAMPLE_RATE) / inputSampleRate
            val output = ByteBuffer.allocate(outputFrames * 2).order(ByteOrder.LITTLE_ENDIAN)
            for (frame in 0 until outputFrames) {
                val sourceFrame = (frame * inputSampleRate) / WAV_SAMPLE_RATE
                var mixed = 0
                for (channel in 0 until inputChannelCount) {
                    mixed += pcm.getShort((sourceFrame * inputChannelCount + channel) * 2).toInt()
                }
                output.putShort((mixed / inputChannelCount).toShort())
            }
            val bytes = output.array()
            stream.write(bytes)
            dataBytes += bytes.size
        }

        fun close() {
            stream.close()
            RandomAccessFile(file, "rw").use { wav ->
                wav.seek(0)
                wav.write(wavHeader(dataBytes))
            }
        }

        private fun wavHeader(dataBytes: Int): ByteArray {
            val buffer = ByteBuffer.allocate(WAV_HEADER_BYTES).order(ByteOrder.LITTLE_ENDIAN)
            buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
            buffer.putInt(36 + dataBytes)
            buffer.put("WAVE".toByteArray(Charsets.US_ASCII))
            buffer.put("fmt ".toByteArray(Charsets.US_ASCII))
            buffer.putInt(16)
            buffer.putShort(1)
            buffer.putShort(1)
            buffer.putInt(WAV_SAMPLE_RATE)
            buffer.putInt(WAV_SAMPLE_RATE * 2)
            buffer.putShort(2)
            buffer.putShort(16)
            buffer.put("data".toByteArray(Charsets.US_ASCII))
            buffer.putInt(dataBytes)
            return buffer.array()
        }
    }

    private fun ensureNativeTts() {
        if (nativeTts != null || nativeTtsInitializing) {
            return
        }
        val engine = resolveTtsEngine(pendingTtsRequests.firstOrNull()?.engine.orEmpty())
        if (engine == null) {
            failPendingTts("tts_unavailable", "No Android TTS engine is installed.")
            return
        }
        nativeTtsInitializing = true
        nativeTtsEngine = engine
        nativeTts = TextToSpeech(
            this,
            { status ->
                mainHandler.post {
                    nativeTtsInitializing = false
                    nativeTtsReady = status == TextToSpeech.SUCCESS
                    if (nativeTtsReady) {
                        nativeTts?.setOnUtteranceProgressListener(nativeTtsListener)
                        drainNativeTtsRequests()
                    } else {
                        nativeTts?.shutdown()
                        nativeTts = null
                        nativeTtsEngine = ""
                        failPendingTts(
                            "tts_init_failed",
                            "Failed to initialize Android TTS.",
                        )
                    }
                }
            },
            engine,
        )
    }

    private fun installedTtsEngines() = packageManager.queryIntentServices(
        Intent(TextToSpeech.Engine.INTENT_ACTION_TTS_SERVICE),
        0,
    )

    private fun systemDefaultTtsEngine(): String? {
        return Settings.Secure.getString(contentResolver, "tts_default_synth")
    }

    private fun resolveTtsEngine(preferredEngine: String): String? {
        val services = installedTtsEngines()
        val systemDefault = systemDefaultTtsEngine()
        val engine = preferredEngine.ifEmpty { systemDefault.orEmpty() }
        if (engine.isNotEmpty() && services.any { it.serviceInfo.packageName == engine }) {
            return engine
        }
        return services.firstOrNull()?.serviceInfo?.packageName
    }

    private fun recreateNativeTtsIfNeeded(engine: String) {
        val selectedEngine = resolveTtsEngine(engine) ?: return
        if (nativeTtsEngine == selectedEngine) {
            return
        }
        nativeTtsReady = false
        nativeTtsInitializing = false
        nativeTts?.shutdown()
        nativeTts = null
        nativeTtsEngine = ""
    }

    private fun drainNativeTtsRequests() {
        val firstRequest = pendingTtsRequests.firstOrNull()
        if (firstRequest != null && !nativeTtsInitializing) {
            recreateNativeTtsIfNeeded(firstRequest.engine)
            ensureNativeTts()
        }
        val tts = nativeTts
        if (!nativeTtsReady || tts == null || pendingTtsRequests.isEmpty()) {
            return
        }

        activeTtsResult?.success(false)
        activeTtsResult = null
        tts.stop()

        val request = pendingTtsRequests.removeFirst()
        val locale = Locale.forLanguageTag(request.language)
        // ponytail: Xiaomi TTS can report language unavailable but still speak with its default voice.
        tts.setLanguage(locale)
        selectVoice(tts, locale, request.voice)

        tts.setSpeechRate(request.rate)
        val utteranceId = UUID.randomUUID().toString()
        activeTtsUtteranceId = utteranceId
        activeTtsResult = request.result
        val params = Bundle()
        params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
        if (tts.speak(request.text, TextToSpeech.QUEUE_FLUSH, params, utteranceId) == TextToSpeech.ERROR) {
            activeTtsResult = null
            activeTtsUtteranceId = null
            request.result.error("tts_speak_failed", "Android TTS failed to speak.", null)
        }
    }

    private fun selectVoice(tts: TextToSpeech, locale: Locale, selectedVoice: String) {
        val voices = tts.voices
            .asSequence()
            .filter { it.locale.language == locale.language }
            .filter { !it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) }
            .sortedWith(
                compareByDescending<android.speech.tts.Voice> { it.quality }
                    .thenBy { it.latency },
            )
            .toList()
        val voice = voices.firstOrNull { it.name == selectedVoice } ?: voices.firstOrNull()
        if (voice != null) {
            tts.voice = voice
        }
    }

    private fun voiceQualityLabel(quality: Int): String = when {
        quality >= 500 -> "极高质量"
        quality >= 400 -> "高质量"
        quality >= 300 -> "标准质量"
        else -> "基础质量"
    }

    private val nativeTtsListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) = Unit

        override fun onDone(utteranceId: String?) {
            completeNativeTts(utteranceId, null)
        }

        @Deprecated("Deprecated in Android SDK")
        override fun onError(utteranceId: String?) {
            completeNativeTts(utteranceId, "Android TTS playback failed.")
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            completeNativeTts(utteranceId, "Android TTS playback failed: $errorCode")
        }
    }

    private fun completeNativeTts(utteranceId: String?, errorMessage: String?) {
        mainHandler.post {
            if (utteranceId != activeTtsUtteranceId) {
                return@post
            }
            val result = activeTtsResult ?: return@post
            activeTtsResult = null
            activeTtsUtteranceId = null
            if (errorMessage == null) {
                result.success(true)
            } else {
                result.error("tts_speak_failed", errorMessage, null)
            }
            drainNativeTtsRequests()
        }
    }

    private fun failPendingTts(code: String, message: String) {
        while (pendingTtsRequests.isNotEmpty()) {
            pendingTtsRequests.removeFirst().result.error(code, message, null)
        }
    }

    override fun onDestroy() {
        pronunciationExtractionRequests.values.forEach { it.set(true) }
        pronunciationExtractionRequests.clear()
        nativeTts?.shutdown()
        nativeTts = null
        nativeTtsEngine = ""
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_PICK_DIRECTORY = 28061
        private const val WAV_HEADER_BYTES = 44
        private const val WAV_SAMPLE_RATE = 16000
        private const val MAX_PRONUNCIATION_SEGMENT_MS = 60000
        private const val MAX_PRONUNCIATION_PREROLL_US = 10_000_000L
        private const val MAX_PRONUNCIATION_EXTRACTION_TIMEOUT_MS = 30_000L
    }

    private data class NativeTtsRequest(
        val text: String,
        val language: String,
        val engine: String,
        val voice: String,
        val rate: Float,
        val result: MethodChannel.Result,
    )
}
