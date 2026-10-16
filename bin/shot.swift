// shot の本体。アプリのウィンドウ、シミュレーター、既存の画像を、長い辺 --max 以内に縮めて PNG で出す。
// --crop は縮めた画像の上の座標で指定し、その部分を元の解像度で切り出す。全体を小さく見てから、細部だけ鮮明に見るため。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let usage = """
使い方:
  shot window <アプリ名|バンドルID> [--crop x,y,w,h] [--max 1000] [--out path]
  shot sim [UDID|booted] [--crop x,y,w,h] [--max 1000] [--out path]
  shot file <画像> [--crop x,y,w,h] [--max 1000] [--out path]
"""

var arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 1 else { fail(usage, 64) }
let mode = arguments.removeFirst()
var target: String?
var crop: CGRect?
var maxSide = 1000.0
var outputPath: String?
while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--crop":
        guard let value = arguments.first.map({ $0.split(separator: ",").compactMap { Double($0) } }), value.count == 4 else {
            fail("--crop は x,y,w,h で指定します", 64)
        }
        arguments.removeFirst()
        crop = CGRect(x: value[0], y: value[1], width: value[2], height: value[3])
    case "--max":
        guard let value = arguments.first.flatMap(Double.init), value > 0 else { fail("--max は正の数で指定します", 64) }
        arguments.removeFirst()
        maxSide = value
    case "--out":
        guard let value = arguments.first else { fail("--out にはパスを指定します", 64) }
        arguments.removeFirst()
        outputPath = value
    default:
        target = argument
    }
}

let outputDirectory = ProcessInfo.processInfo.environment["SHOT_OUTPUT_DIR"]
    ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("shot")
try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
let stamp = { () -> String in
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}()

@discardableResult
func run(_ path: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return -1 }
    process.waitUntilExit()
    return process.terminationStatus
}

func windowID(matching owner: String) -> Int? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let ownerPIDs = Set(pids(ofBundleID: owner))
    let candidates = windows.compactMap { window -> (id: Int, area: Double)? in
        let name = window[kCGWindowOwnerName as String] as? String
        let pid = window[kCGWindowOwnerPID as String] as? Int32
        guard name == owner || pid.map(ownerPIDs.contains) == true,
              window[kCGWindowLayer as String] as? Int == 0,
              let id = window[kCGWindowNumber as String] as? Int,
              let bounds = window[kCGWindowBounds as String] as? [String: Double],
              let width = bounds["Width"], let height = bounds["Height"], width > 100, height > 100 else {
            return nil
        }
        return (id, width * height)
    }
    return candidates.max(by: { $0.area < $1.area })?.id
}

func pids(ofBundleID bundleID: String) -> [Int32] {
    guard bundleID.contains(".") else { return [] }
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo")
    process.arguments = ["info", "-only", "pid", "-app", bundleID]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return [] }
    process.waitUntilExit()
    let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return text.split(whereSeparator: { !$0.isNumber }).compactMap { Int32($0) }
}

let sourcePath: String
switch mode {
case "file":
    guard let target else { fail(usage, 64) }
    sourcePath = target
case "window":
    guard let target else { fail(usage, 64) }
    guard let id = windowID(matching: target) else { fail("\(target) のウィンドウが見つかりません", 69) }
    sourcePath = (outputDirectory as NSString).appendingPathComponent("raw-\(stamp)-\(getpid()).png")
    // -l はウィンドウ単位で撮るため、ほかのウィンドウが重なっていても写らない。-o は影を付けない
    guard run("/usr/sbin/screencapture", ["-x", "-o", "-l", String(id), sourcePath]) == 0 else {
        fail("撮影に失敗しました。画面収録の権限を確かめてください")
    }
case "sim":
    sourcePath = (outputDirectory as NSString).appendingPathComponent("raw-\(stamp)-\(getpid()).png")
    guard run("/usr/bin/xcrun", ["simctl", "io", target ?? "booted", "screenshot", sourcePath]) == 0 else {
        fail("シミュレーターを撮れませんでした。起動中か確かめてください")
    }
default:
    fail(usage, 64)
}

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("画像を読めません: \(sourcePath)")
}
let original = CGSize(width: image.width, height: image.height)
let scale = min(1, maxSide / max(original.width, original.height))
let shown = CGSize(width: (original.width * scale).rounded(), height: (original.height * scale).rounded())

var region = CGRect(origin: .zero, size: original)
if let crop {
    guard crop.minX >= 0, crop.minY >= 0, crop.width > 0, crop.height > 0,
          crop.maxX <= shown.width, crop.maxY <= shown.height else {
        fail("--crop が画像（\(Int(shown.width))x\(Int(shown.height))）からはみ出しています", 65)
    }
    region = CGRect(x: crop.minX / scale, y: crop.minY / scale, width: crop.width / scale, height: crop.height / scale).integral
        .intersection(CGRect(origin: .zero, size: original))
}
guard let cropped = image.cropping(to: region) else { fail("切り出せませんでした") }
let outputScale = min(1, maxSide / max(region.width, region.height))
let outputSize = CGSize(width: (region.width * outputScale).rounded(), height: (region.height * outputScale).rounded())
guard let context = CGContext(
    data: nil, width: Int(outputSize.width), height: Int(outputSize.height), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fail("描画できませんでした") }
context.interpolationQuality = .high
context.draw(cropped, in: CGRect(origin: .zero, size: outputSize))
guard let result = context.makeImage() else { fail("描画できませんでした") }

let name = ((mode == "file" ? sourcePath : "\(mode)-\(stamp)") as NSString).lastPathComponent
let base = (name as NSString).deletingPathExtension
let destinationPath = outputPath ?? (outputDirectory as NSString).appendingPathComponent(
    crop == nil ? "\(base)-\(getpid()).png" : "\(base)-crop-\(getpid()).png"
)
guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: destinationPath) as CFURL, UTType.png.identifier as CFString, 1, nil
) else { fail("保存できません: \(destinationPath)") }
CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else { fail("保存できません: \(destinationPath)") }
if mode != "file" { try? FileManager.default.removeItem(atPath: sourcePath) }

print(destinationPath)
if crop == nil {
    print("\(Int(outputSize.width))x\(Int(outputSize.height))（元 \(Int(original.width))x\(Int(original.height))）。--crop はこの画像の座標で指定する")
} else {
    print("\(Int(outputSize.width))x\(Int(outputSize.height))（元の \(Int(region.minX)),\(Int(region.minY)) から \(Int(region.width))x\(Int(region.height))）")
}
