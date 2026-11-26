package com.fitkle.soolgyul

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.provider.Settings
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.concurrent.thread

/** The long side of the photo the label judge is shown, in pixels. */
private const val BOTTLE_PHOTO_SIDE = 640

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
                "bottlePhoto" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("missing_path", "A photo path is required.", null)
                    } else {
                        bottlePhoto(path, result)
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

    /// The photo as a JPEG for the server's judge, which reads the label
    /// itself: upright and at most 640 px on its long side, the size the
    /// judge was measured at. This phone has no bottle detector, so the
    /// photo is sent whole.
    private fun bottlePhoto(path: String, result: MethodChannel.Result) {
        thread {
            val jpeg = try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, bounds)
                // Halved while it stays at least twice the size wanted, then scaled.
                var sample = 1
                while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 2 * BOTTLE_PHOTO_SIDE) {
                    sample *= 2
                }
                val decoded = BitmapFactory.decodeFile(
                    path,
                    BitmapFactory.Options().apply { inSampleSize = sample },
                ) ?: throw IllegalArgumentException("unreadable photo")
                val scale = minOf(
                    1f,
                    BOTTLE_PHOTO_SIDE.toFloat() / maxOf(decoded.width, decoded.height),
                )
                val upright = Matrix().apply {
                    postScale(scale, scale)
                    postRotate(
                        when (
                            ExifInterface(path).getAttributeInt(
                                ExifInterface.TAG_ORIENTATION,
                                ExifInterface.ORIENTATION_NORMAL,
                            )
                        ) {
                            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                            else -> 0f
                        },
                    )
                }
                val drawn = Bitmap.createBitmap(
                    decoded, 0, 0, decoded.width, decoded.height, upright, true,
                )
                ByteArrayOutputStream().also { out ->
                    drawn.compress(Bitmap.CompressFormat.JPEG, 80, out)
                }.toByteArray()
            } catch (error: Exception) {
                null
            }
            runOnUiThread {
                if (jpeg == null) {
                    result.error("photo_failed", null, null)
                } else {
                    result.success(jpeg)
                }
            }
        }
    }

    /// Reads the label on the device with the ML Kit Korean and Japanese
    /// models (both also read Latin script), Korean lines first, each line
    /// with where it sits in the photo. Reading sends nothing anywhere.
    private fun recognizeLabelLines(path: String, result: MethodChannel.Result) {
        val image = try {
            InputImage.fromFilePath(this, Uri.fromFile(File(path)))
        } catch (error: Exception) {
            result.error("unreadable_photo", error.message, null)
            return
        }
        // The boxes are measured on the upright photo.
        val turned = image.rotationDegrees % 180 != 0
        val width = (if (turned) image.height else image.width).toDouble()
        val height = (if (turned) image.width else image.height).toDouble()
        fun channelLines(text: Text): List<Map<String, Any>> =
            text.textBlocks.flatMap { block -> block.lines }.mapNotNull { line ->
                val box = line.boundingBox ?: return@mapNotNull null
                mapOf(
                    "text" to line.text,
                    "left" to box.left / width,
                    "top" to box.top / height,
                    "width" to box.width() / width,
                    "height" to box.height() / height,
                    "confidence" to line.confidence.toDouble(),
                )
            }
        val korean = TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
        val japanese = TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
        korean.process(image)
            .continueWithTask { koreanTask ->
                val koreanLines = channelLines(koreanTask.result)
                japanese.process(image).continueWith { japaneseTask ->
                    koreanLines + channelLines(japaneseTask.result)
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
