import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let labelOcrChannelName = "soolgyul/label-ocr"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let labelOcrChannel = FlutterMethodChannel(
      name: labelOcrChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    labelOcrChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "recognizeLines":
        guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(FlutterError(code: "missing_path", message: "A photo path is required.", details: nil))
          return
        }
        recognizeLabelLines(atPath: path) { lines in
          DispatchQueue.main.async {
            if let lines = lines {
              result(lines)
            } else {
              result(FlutterError(code: "recognition_failed", message: nil, details: nil))
            }
          }
        }
      case "hasText":
        guard let arguments = call.arguments as? [String: Any],
          let luma = arguments["luma"] as? FlutterStandardTypedData,
          let width = arguments["width"] as? Int,
          let height = arguments["height"] as? Int,
          let rotation = arguments["rotation"] as? Int,
          luma.data.count >= width * height
        else {
          result(FlutterError(code: "bad_frame", message: "A luma frame is required.", details: nil))
          return
        }
        frameHasText(luma: luma.data, width: width, height: height, rotation: rotation) { found in
          DispatchQueue.main.async { result(found) }
        }
      case "openAppSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Reads the label on the device with Apple Vision, top line first. The
/// photo never leaves the phone.
///
/// Korean and Japanese need the iOS 16 recognizer, and a request reads
/// every line in its first language: a Japanese brand comes back as Hangul
/// garbage from a Korean request and the other way round. So the photo is
/// scanned once per script and, where both scans read the same region, the
/// more confident reading wins (both stay on a tie). Older systems read
/// Latin script only.
private func recognizeLabelLines(atPath path: String, completion: @escaping ([String]?) -> Void) {
  guard let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage else {
    completion(nil)
    return
  }
  let orientation = cgImageOrientation(of: image.imageOrientation)
  DispatchQueue.global(qos: .userInitiated).async {
    guard #available(iOS 16.0, *) else {
      let latin = scanLabel(cgImage, orientation: orientation, languages: ["en-US"], revision: nil)
      completion(latin.map { lines in lines.map { $0.text } })
      return
    }
    guard
      let korean = scanLabel(cgImage, orientation: orientation, languages: ["ko-KR", "en-US"], revision: VNRecognizeTextRequestRevision3),
      let japanese = scanLabel(cgImage, orientation: orientation, languages: ["ja-JP", "en-US"], revision: VNRecognizeTextRequestRevision3)
    else {
      completion(nil)
      return
    }
    completion(mergeScans(korean, japanese).map { $0.text })
  }
}

private struct LabelLine {
  let box: CGRect
  let text: String
  let confidence: Float
}

private func scanLabel(
  _ cgImage: CGImage, orientation: CGImagePropertyOrientation, languages: [String], revision: Int?
) -> [LabelLine]? {
  var lines: [LabelLine]?
  let request = VNRecognizeTextRequest { request, error in
    guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else { return }
    lines = observations.compactMap { observation in
      observation.topCandidates(1).first.map {
        LabelLine(box: observation.boundingBox, text: $0.string, confidence: $0.confidence)
      }
    }
  }
  request.recognitionLevel = .accurate
  request.usesLanguageCorrection = false
  if let revision = revision { request.revision = revision }
  request.recognitionLanguages = languages
  let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
  do {
    try handler.perform([request])
  } catch {
    return nil
  }
  return lines
}

/// Vision's origin is the bottom-left corner, so a higher box is nearer the top.
private func mergeScans(_ first: [LabelLine], _ second: [LabelLine]) -> [LabelLine] {
  var merged: [LabelLine] = []
  var taken = Set<Int>()
  for line in first {
    var kept = [line]
    for (index, other) in second.enumerated() where !taken.contains(index) && sameRegion(line.box, other.box) {
      taken.insert(index)
      if other.confidence > line.confidence {
        kept = [other]
      } else if other.confidence == line.confidence && other.text != line.text {
        kept.append(other)
      }
    }
    merged.append(contentsOf: kept)
  }
  for (index, other) in second.enumerated() where !taken.contains(index) {
    merged.append(other)
  }
  return merged.sorted { $0.box.maxY > $1.box.maxY }
}

private func sameRegion(_ a: CGRect, _ b: CGRect) -> Bool {
  let shared = a.intersection(b)
  if shared.isNull { return false }
  return shared.width * shared.height > 0.5 * min(a.width * a.height, b.width * b.height)
}

/// Whether a grey viewfinder frame holds text, judged by Vision's text
/// rectangle detector (fast, script-agnostic) off the main thread.
private func frameHasText(
  luma: Data, width: Int, height: Int, rotation: Int, completion: @escaping (Bool) -> Void
) {
  DispatchQueue.global(qos: .userInitiated).async {
    var pixelBuffer: CVPixelBuffer?
    let created = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8, nil, &pixelBuffer)
    guard created == kCVReturnSuccess, let buffer = pixelBuffer else {
      completion(false)
      return
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    if let base = CVPixelBufferGetBaseAddress(buffer) {
      let stride = CVPixelBufferGetBytesPerRow(buffer)
      luma.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
        guard let sourceBase = source.baseAddress else { return }
        for row in 0..<height {
          memcpy(base + row * stride, sourceBase + row * width, width)
        }
      }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])

    let orientation: CGImagePropertyOrientation
    switch rotation {
    case 90: orientation = .right
    case 180: orientation = .down
    case 270: orientation = .left
    default: orientation = .up
    }
    let request = VNDetectTextRectanglesRequest()
    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:])
    do {
      try handler.perform([request])
    } catch {
      completion(false)
      return
    }
    let lines = (request.results ?? []).filter { $0.boundingBox.height > 0.03 }
    completion(!lines.isEmpty)
  }
}

private func cgImageOrientation(of orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
  switch orientation {
  case .up: return .up
  case .upMirrored: return .upMirrored
  case .down: return .down
  case .downMirrored: return .downMirrored
  case .left: return .left
  case .leftMirrored: return .leftMirrored
  case .right: return .right
  case .rightMirrored: return .rightMirrored
  @unknown default: return .up
  }
}
