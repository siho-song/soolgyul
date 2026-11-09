package com.fitkle.soolgyul

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.net.Uri
import android.provider.Settings
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val debugScreenChannelName = "soolgyul/debug-screen"
    private val labelOcrChannelName = "soolgyul/label-ocr"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            debugScreenChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "getRequestedScreen") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val isDebugBuild = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
            val requestedDebugScreen = if (isDebugBuild) {
                intent.getIntExtra("screen", -1)
            } else {
                -1
            }
            result.success(requestedDebugScreen)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            labelOcrChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "recognizeLines" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("missing_path", "A photo path is required.", null)
                    } else {
                        recognizeLabelLines(path, result)
                    }
                }
                "hasText" -> {
                    val luma = call.argument<ByteArray>("luma")
                    val width = call.argument<Int>("width")
                    val height = call.argument<Int>("height")
                    val rotation = call.argument<Int>("rotation") ?: 0
                    if (luma == null || width == null || height == null || luma.size < width * height) {
                        result.error("bad_frame", "A luma frame is required.", null)
                    } else {
                        frameHasText(luma, width, height, rotation, result)
                    }
                }
                "openAppSettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        ),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// One recognizer kept for the viewfinder frames; the photo path makes
    /// its own.
    private val frameRecognizer: TextRecognizer by lazy {
        TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
    }

    override fun onDestroy() {
        frameRecognizer.close()
        super.onDestroy()
    }

    /// Whether a grey viewfinder frame holds text. The grey bytes become a
    /// bitmap because ML Kit takes no bare luma plane.
    private fun frameHasText(
        luma: ByteArray,
        width: Int,
        height: Int,
        rotation: Int,
        result: MethodChannel.Result,
    ) {
        val pixels = IntArray(width * height)
        for (i in pixels.indices) {
            val grey = luma[i].toInt() and 0xFF
            pixels[i] = (0xFF shl 24) or (grey shl 16) or (grey shl 8) or grey
        }
        val bitmap = Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
        frameRecognizer.process(InputImage.fromBitmap(bitmap, rotation))
            .addOnSuccessListener { text -> result.success(text.textBlocks.isNotEmpty()) }
            .addOnFailureListener { result.success(false) }
    }

    /// Reads the label on the device with the ML Kit Korean and Japanese
    /// models (both also read Latin script), Korean lines first. The photo
    /// never leaves the phone.
    private fun recognizeLabelLines(path: String, result: MethodChannel.Result) {
        val image = try {
            InputImage.fromFilePath(this, Uri.fromFile(File(path)))
        } catch (error: Exception) {
            result.error("unreadable_photo", error.message, null)
            return
        }
        val korean = TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
        val japanese = TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
        korean.process(image)
            .continueWithTask { koreanTask ->
                val koreanLines = koreanTask.result.textBlocks.flatMap { block -> block.lines }.map { line -> line.text }
                japanese.process(image).continueWith { japaneseTask ->
                    val japaneseLines = japaneseTask.result.textBlocks.flatMap { block -> block.lines }.map { line -> line.text }
                    (koreanLines + japaneseLines).distinct()
                }
            }
            .addOnSuccessListener { lines -> result.success(lines) }
            .addOnFailureListener { error ->
                result.error("recognition_failed", error.message, null)
            }
            .addOnCompleteListener {
                korean.close()
                japanese.close()
            }
    }
}
