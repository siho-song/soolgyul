import Flutter
import OnnxRuntimeBindings
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
      case "findBottles":
        guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(FlutterError(code: "missing_path", message: "A photo path is required.", details: nil))
          return
        }
        findBottles(atPath: path) { boxes in
          DispatchQueue.main.async {
            if let boxes = boxes {
              result(boxes)
            } else {
              result(FlutterError(code: "detection_failed", message: nil, details: nil))
            }
          }
        }
      case "readBottle":
        guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          let left = arguments["left"] as? Double, let top = arguments["top"] as? Double,
          let right = arguments["right"] as? Double, let bottom = arguments["bottom"] as? Double
        else {
          result(FlutterError(code: "missing_box", message: "A photo path and a box are required.", details: nil))
          return
        }
        readBottle(atPath: path, box: CGRect(x: left, y: top, width: right - left, height: bottom - top)) { lines in
          DispatchQueue.main.async {
            if let lines = lines {
              result(lines)
            } else {
              result(FlutterError(code: "recognition_failed", message: nil, details: nil))
            }
          }
        }
      case "bottlePhoto":
        guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(FlutterError(code: "missing_path", message: "A photo path is required.", details: nil))
          return
        }
        var box: CGRect?
        if let left = arguments["left"] as? Double, let top = arguments["top"] as? Double,
          let right = arguments["right"] as? Double, let bottom = arguments["bottom"] as? Double
        {
          box = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
        bottlePhoto(atPath: path, box: box) { jpeg in
          DispatchQueue.main.async {
            if let jpeg = jpeg {
              result(FlutterStandardTypedData(bytes: jpeg))
            } else {
              result(FlutterError(code: "photo_failed", message: nil, details: nil))
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

/// Reads the label on the device with Apple Vision, top line first, each
/// line with where it sits in the photo. Reading sends nothing anywhere.
///
/// Korean and Japanese need the iOS 16 recognizer, and a request reads
/// every line in its first language: a Japanese brand comes back as Hangul
/// garbage from a Korean request and the other way round, and a Latin
/// brand is read best by an English request that corrects words. So the
/// photo is scanned once per script and, where two scans read the same
/// region, the more confident reading wins (both stay on a tie). Older
/// systems read Latin script only.
///
/// The photo is read at most 1280 px on its long side, the size the label
/// match was trained on: one drink fills the photo, so a larger camera
/// photo would only make the scans slower.
private func recognizeLabelLines(atPath path: String, completion: @escaping ([[String: Any]]?) -> Void) {
  DispatchQueue.global(qos: .userInitiated).async {
    guard let photo = UprightPhoto.of(path) else {
      completion(nil)
      return
    }
    let small = max(photo.width, photo.height) > 1280 ? scaledImage(photo, longSide: 1280) : photo
    guard let small = small else {
      completion(nil)
      return
    }
    completion(readLabel(small, orientation: .up)?.map(channelLine))
  }
}

private func readLabel(_ cgImage: CGImage, orientation: CGImagePropertyOrientation) -> [LabelLine]? {
  let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
  guard #available(iOS 16.0, *) else {
    let latin = textRequest(languages: ["en-US"], revision: nil)
    guard (try? handler.perform([latin])) != nil else { return nil }
    return linesRead(by: latin)
  }
  let korean = textRequest(languages: ["ko-KR", "en-US"], revision: VNRecognizeTextRequestRevision3)
  let japanese = textRequest(languages: ["ja-JP", "en-US"], revision: VNRecognizeTextRequestRevision3)
  let english = textRequest(languages: ["en-US"], revision: VNRecognizeTextRequestRevision3, correctsWords: true)
  // The three scans go through one handler, which prepares the picture once.
  guard (try? handler.perform([korean, japanese, english])) != nil,
    let koreanLines = linesRead(by: korean), let japaneseLines = linesRead(by: japanese)
  else {
    return nil
  }
  return mergeScans(mergeScans(koreanLines, japaneseLines), linesRead(by: english) ?? [])
}

/// Finds the bottles, boxes and tubes in a photo of several drinks, as
/// fractions of its width and height from the top left. Fewer than two
/// found leave nothing to cut, and the photo is read whole instead
/// ([recognizeLabelLines]). The photo drawn upright is kept for
/// [readBottle], which is asked about it next.
private func findBottles(atPath path: String, completion: @escaping ([[String: Double]]?) -> Void) {
  DispatchQueue.global(qos: .userInitiated).async {
    guard let photo = UprightPhoto.of(path), let boxes = BottleDetector.shared?.detect(photo) else {
      completion(nil)
      return
    }
    if boxes.count < 2 {
      completion([])
      return
    }
    completion(
      boxes.map { box in
        ["left": Double(box.minX), "top": Double(box.minY), "right": Double(box.maxX), "bottom": Double(box.maxY)]
      })
  }
}

/// Reads one drink of a photo by itself: the detector's [box] with a 5%
/// margin, cut out of the photo at full size and scaled to 640 px on its
/// long side. Cutting from the full photo keeps the small labels of a
/// shelf readable. At 640 px the name still reads, and the small print of
/// a label or a gift box, which a larger cut-out spends most of its time
/// on, does not.
private func readBottle(atPath path: String, box: CGRect, completion: @escaping ([[String: Any]]?) -> Void) {
  DispatchQueue.global(qos: .userInitiated).async {
    guard let photo = UprightPhoto.of(path) else {
      completion(nil)
      return
    }
    let width = CGFloat(photo.width)
    let height = CGFloat(photo.height)
    let marginX = 0.05 * box.width
    let marginY = 0.05 * box.height
    let cut = CGRect(
      x: max(0, box.minX - marginX) * width, y: max(0, box.minY - marginY) * height,
      width: (min(1, box.maxX + marginX) - max(0, box.minX - marginX)) * width,
      height: (min(1, box.maxY + marginY) - max(0, box.minY - marginY)) * height
    ).integral
    guard let piece = photo.cropping(to: cut), let scaled = scaledImage(piece, longSide: 640) else {
      completion(nil)
      return
    }
    completion(readLabel(scaled, orientation: .up)?.map(channelLine))
  }
}

/// The one bottle of a photo as a JPEG for the server's judge, which reads
/// the label itself: [box], or with none given the largest thing the
/// detector finds, cut out of the photo with a margin of 2% of the photo;
/// the whole photo when the detector finds nothing. At most 640 px on its
/// long side, the size the judge was measured at: larger costs more and
/// finds no more.
private func bottlePhoto(atPath path: String, box: CGRect?, completion: @escaping (Data?) -> Void) {
  DispatchQueue.global(qos: .userInitiated).async {
    guard let photo = UprightPhoto.of(path) else {
      completion(nil)
      return
    }
    let bottle =
      box ?? BottleDetector.shared?.detect(photo)?.max { $0.width * $0.height < $1.width * $1.height }
    var piece = photo
    if let bottle = bottle {
      let width = CGFloat(photo.width)
      let height = CGFloat(photo.height)
      let margin: CGFloat = 0.02
      let cut = CGRect(
        x: max(0, bottle.minX - margin) * width, y: max(0, bottle.minY - margin) * height,
        width: (min(1, bottle.maxX + margin) - max(0, bottle.minX - margin)) * width,
        height: (min(1, bottle.maxY + margin) - max(0, bottle.minY - margin)) * height
      ).integral
      piece = photo.cropping(to: cut) ?? photo
    }
    let longSide = min(640, CGFloat(max(piece.width, piece.height)))
    guard let scaled = scaledImage(piece, longSide: longSide) else {
      completion(nil)
      return
    }
    completion(UIImage(cgImage: scaled).jpegData(compressionQuality: 0.8))
  }
}

/// The last photo drawn upright, at most 4032 px on its long side (a
/// 12-megapixel photo), so its drinks are cut out of one drawing rather
/// than one each.
private enum UprightPhoto {
  private static var path: String?
  private static var image: CGImage?
  private static let lock = NSLock()

  static func of(_ path: String) -> CGImage? {
    lock.lock()
    defer { lock.unlock() }
    if path == self.path, let image = image { return image }
    guard let photo = UIImage(contentsOfFile: path), let drawn = uprightImage(photo, longSide: 4032) else {
      return nil
    }
    self.path = path
    image = drawn
    return drawn
  }
}

/// [image] drawn upright, its long side at most [longSide].
private func uprightImage(_ image: UIImage, longSide: CGFloat) -> CGImage? {
  let scale = min(1, longSide / max(image.size.width, image.size.height))
  let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
  let format = UIGraphicsImageRendererFormat()
  format.scale = 1
  format.opaque = true
  return UIGraphicsImageRenderer(size: size, format: format).image { _ in
    image.draw(in: CGRect(origin: .zero, size: size))
  }.cgImage
}

/// [image] scaled up or down so its long side is [longSide].
private func scaledImage(_ image: CGImage, longSide: CGFloat) -> CGImage? {
  let scale = longSide / CGFloat(max(image.width, image.height))
  if scale == 1 { return image }
  let width = Int((CGFloat(image.width) * scale).rounded())
  let height = Int((CGFloat(image.height) * scale).rounded())
  guard
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
  else { return nil }
  context.interpolationQuality = .high
  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  return context.makeImage()
}

/// The bottle detector (D-FINE nano, assets/models/bottle_detector.onnx):
/// a 640 x 640 RGB photo in, 300 boxes with a score per kind out.
private final class BottleDetector {
  static let shared: BottleDetector? = {
    do {
      return try BottleDetector()
    } catch {
      return nil
    }
  }()

  private let session: ORTSession
  private let lock = NSLock()

  private init() throws {
    let key = FlutterDartProject.lookupKey(forAsset: "assets/models/bottle_detector.onnx")
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
      throw NSError(domain: "BottleDetector", code: 1)
    }
    let env = try ORTEnv(loggingLevel: .warning)
    session = try ORTSession(env: env, modelPath: path, sessionOptions: try ORTSessionOptions())
  }

  /// The objects [photo] shows, as fractions of its width and height from
  /// the top left: those scored 0.65 or more, one box per object whatever
  /// kind it was called, and none shorter than 0.4 of the tallest. Seven or
  /// more make a crowded photo, where a bottle is too small to be sure of:
  /// its four quarters are looked at too, for the bottles the whole photo
  /// missed.
  func detect(_ photo: CGImage) -> [CGRect]? {
    guard let whole = scored(photo) else { return nil }
    var kept: [CGRect] = []
    for candidate in whole where kept.allSatisfy({ sharedPart($0, candidate.box) < 0.7 }) {
      kept.append(candidate.box)
    }
    let first = withoutShort(kept)
    guard first.count >= 7, let quarters = scoredInQuarters(photo) else { return first }
    // A quarter adds bottles, never a thing bigger than the bottles: one
    // large wrong box would make every real one short.
    let tallest = first.map(\.height).max() ?? 0
    let pool = (whole + quarters.filter { $0.box.height <= 1.2 * tallest }).sorted { $0.score > $1.score }
    var merged: [CGRect] = []
    for candidate in pool
    where merged.allSatisfy({ sharedPart($0, candidate.box) < 0.5 && coveredPart($0, candidate.box) < 0.7 }) {
      merged.append(candidate.box)
    }
    return withoutShort(merged)
  }

  private func withoutShort(_ boxes: [CGRect]) -> [CGRect] {
    let tallest = boxes.map(\.height).max() ?? 0
    return boxes.filter { $0.height >= 0.4 * tallest }
  }

  /// The boxes of the four overlapping quarters of [photo], each 55% of its
  /// width and height, as fractions of the whole photo. A box touching a
  /// cut edge inside the photo is a cut bottle and is left out: the
  /// neighbouring quarter shows it whole.
  private func scoredInQuarters(_ photo: CGImage) -> [(box: CGRect, score: Float)]? {
    let width = CGFloat(photo.width), height = CGFloat(photo.height)
    let w = (width * 0.55).rounded(), h = (height * 0.55).rounded()
    var found: [(box: CGRect, score: Float)] = []
    for (x, y) in [(CGFloat(0), CGFloat(0)), (width - w, CGFloat(0)), (CGFloat(0), height - h), (width - w, height - h)] {
      guard let quarter = photo.cropping(to: CGRect(x: x, y: y, width: w, height: h)), let boxes = scored(quarter)
      else { return nil }
      for (box, score) in boxes {
        let cutAcross = x > 0 ? box.minX < 0.02 : box.maxX > 0.98
        let cutDown = y > 0 ? box.minY < 0.02 : box.maxY > 0.98
        if cutAcross || cutDown { continue }
        found.append(
          (
            CGRect(
              x: (x + box.minX * w) / width, y: (y + box.minY * h) / height, width: box.width * w / width,
              height: box.height * h / height), score
          ))
      }
    }
    return found
  }

  /// Every box of [photo] scored 0.65 or more, surest first, as fractions
  /// of its width and height from the top left.
  private func scored(_ photo: CGImage) -> [(box: CGRect, score: Float)]? {
    let side = 640
    guard
      let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
      let pixels = context.data
    else { return nil }
    context.interpolationQuality = .medium
    context.draw(photo, in: CGRect(x: 0, y: 0, width: side, height: side))
    let bytes = pixels.bindMemory(to: UInt8.self, capacity: side * side * 4)
    let plane = side * side
    let input = NSMutableData(length: 3 * plane * MemoryLayout<Float>.size)!
    let values = input.mutableBytes.bindMemory(to: Float.self, capacity: 3 * plane)
    for index in 0..<plane {
      values[index] = Float(bytes[index * 4]) / 255
      values[plane + index] = Float(bytes[index * 4 + 1]) / 255
      values[2 * plane + index] = Float(bytes[index * 4 + 2]) / 255
    }
    lock.lock()
    defer { lock.unlock() }
    let logitsData: Data
    let boxesData: Data
    do {
      let tensor = try ORTValue(
        tensorData: input, elementType: .float, shape: [1, 3, NSNumber(value: side), NSNumber(value: side)])
      let outputs = try session.run(
        withInputs: ["pixel_values": tensor], outputNames: ["logits", "pred_boxes"], runOptions: nil)
      guard let logits = outputs["logits"], let boxes = outputs["pred_boxes"] else { return nil }
      logitsData = try logits.tensorData() as Data
      boxesData = try boxes.tensorData() as Data
    } catch {
      return nil
    }
    let logits = logitsData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let boxes = boxesData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let kinds = 3
    var found: [(box: CGRect, score: Float)] = []
    for query in 0..<(boxes.count / 4) {
      for kind in 0..<kinds {
        let score = 1 / (1 + exp(-logits[query * kinds + kind]))
        guard score >= 0.65 else { continue }
        let cx = CGFloat(boxes[query * 4]), cy = CGFloat(boxes[query * 4 + 1])
        let w = CGFloat(boxes[query * 4 + 2]), h = CGFloat(boxes[query * 4 + 3])
        found.append((CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), score))
      }
    }
    return found.sorted { $0.score > $1.score }
  }
}

/// A line as the label channel sends it: fractions of the photo's width
/// and height from its top-left corner (Vision measures from the bottom).
private func channelLine(_ line: LabelLine) -> [String: Any] {
  return [
    "text": line.text,
    "left": Double(line.box.minX),
    "top": Double(1 - line.box.maxY),
    "width": Double(line.box.width),
    "height": Double(line.box.height),
    "confidence": Double(line.confidence),
  ]
}

private struct LabelLine {
  let box: CGRect
  let text: String
  let confidence: Float
}

private func textRequest(languages: [String], revision: Int?, correctsWords: Bool = false) -> VNRecognizeTextRequest {
  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.usesLanguageCorrection = correctsWords
  if let revision = revision { request.revision = revision }
  request.recognitionLanguages = languages
  return request
}

/// The lines a performed [request] read, or nil when it failed.
private func linesRead(by request: VNRequest) -> [LabelLine]? {
  guard let observations = request.results as? [VNRecognizedTextObservation] else { return nil }
  return observations.compactMap { observation in
    observation.topCandidates(1).first.map {
      LabelLine(box: observation.boundingBox, text: $0.string, confidence: $0.confidence)
    }
  }
}

/// The lines of two scans of one photo as one reading. A line of the
/// second scan is another reading of the line of the first it shares most
/// of its box with, and a line by itself when it shares little with any;
/// of the readings of a line the surest stay, each text once. Vision's
/// origin is the bottom-left corner, so a higher box is nearer the top.
private func mergeScans(_ first: [LabelLine], _ second: [LabelLine]) -> [LabelLine] {
  var readings = first.map { [$0] }
  var merged: [LabelLine] = []
  for other in second {
    let nearest = first.indices.max { sharedPart(first[$0].box, other.box) < sharedPart(first[$1].box, other.box) }
    if let nearest = nearest, sharedPart(first[nearest].box, other.box) > 0.5 {
      readings[nearest].append(other)
    } else {
      merged.append(other)
    }
  }
  for reading in readings {
    let surest = reading.map { $0.confidence }.max() ?? 0
    var texts = Set<String>()
    merged += reading.filter { $0.confidence == surest && texts.insert($0.text).inserted }
  }
  return merged.sorted { $0.box.maxY > $1.box.maxY }
}

/// How much of what two boxes cover together they share. A line curved
/// round a bottle has a tall box that covers the small line under it
/// ("CARMEL ROAD" over "MONTEREY"); the two share little of the whole.
private func sharedPart(_ a: CGRect, _ b: CGRect) -> CGFloat {
  let shared = a.intersection(b)
  if shared.isNull { return 0 }
  let overlap = shared.width * shared.height
  return overlap / (a.width * a.height + b.width * b.height - overlap)
}

/// How much of the smaller of two boxes the other covers: a bottle found
/// again inside a wider box of the same bottle shares little of the whole.
private func coveredPart(_ a: CGRect, _ b: CGRect) -> CGFloat {
  let shared = a.intersection(b)
  if shared.isNull { return 0 }
  return shared.width * shared.height / min(a.width * a.height, b.width * b.height)
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
