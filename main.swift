import Foundation
import CoreGraphics
import CoreServices
import ImageIO

// MARK: - Helpers

func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    print("[\(timestamp)] \(message)")
    fflush(stdout)
}

// MARK: - Configuration

let screenshotDir = ("~/Documents/Screenshots" as NSString).expandingTildeInPath
let screenshotPrefix = "Screenshot"

// Apps where we auto-paste the path (process names)
let pasteTargetApps: Set<String> = ["Electron", "Claude", "Discord", "Terminal", "iTerm2", "Warp"]

// MARK: - State

var knownFiles: Set<String> = []

/// Seed known files so we don't paste old screenshots on launch
func seedKnownFiles() {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: screenshotDir) else {
        log("ERROR: Cannot list \(screenshotDir)")
        return
    }
    for file in files where file.hasPrefix(screenshotPrefix) && file.hasSuffix(".png") {
        knownFiles.insert(file)
    }
    log("Watching \(screenshotDir) (\(knownFiles.count) existing screenshots ignored)")
}

// MARK: - Screen Size Detection

/// Get pixel dimensions of all connected displays
func getDisplayPixelSizes() -> [(width: Int, height: Int)] {
    var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetActiveDisplayList(16, &displayIDs, &count)

    var sizes: [(Int, Int)] = []
    for i in 0..<Int(count) {
        if let mode = CGDisplayCopyDisplayMode(displayIDs[i]) {
            sizes.append((mode.pixelWidth, mode.pixelHeight))
            log("Display \(i): \(mode.pixelWidth)x\(mode.pixelHeight)")
        }
    }
    return sizes
}

/// Check if a screenshot matches any display's full resolution (Cmd+Shift+3)
func isFullScreenScreenshot(path: String) -> Bool {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
          let width = props[kCGImagePropertyPixelWidth as String] as? Int,
          let height = props[kCGImagePropertyPixelHeight as String] as? Int
    else {
        log("Could not read image dimensions")
        return false
    }

    log("Screenshot dimensions: \(width)x\(height)")

    for displaySize in getDisplayPixelSizes() {
        if width == displaySize.width && height == displaySize.height {
            return true
        }
    }
    return false
}

// MARK: - Paste Logic

/// Copy path to clipboard and paste into the frontmost app if it's a target app
func handleFullScreenshot(path: String) {
    // Copy to clipboard first
    let pbTask = Process()
    pbTask.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
    let pipe = Pipe()
    pbTask.standardInput = pipe
    do {
        try pbTask.run()
        pipe.fileHandleForWriting.write(path.data(using: .utf8)!)
        pipe.fileHandleForWriting.closeFile()
        pbTask.waitUntilExit()
    } catch {
        log("pbcopy error: \(error)")
        return
    }

    // Get frontmost app via osascript
    let whoTask = Process()
    whoTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    whoTask.arguments = ["-e", """
        tell application "System Events" to get name of first application process whose frontmost is true
    """]
    let whoPipe = Pipe()
    whoTask.standardOutput = whoPipe
    do {
        try whoTask.run()
        whoTask.waitUntilExit()
    } catch {
        log("osascript error getting frontmost app: \(error)")
        return
    }
    let frontApp = String(data: whoPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    log("Frontmost app: \(frontApp)")

    if pasteTargetApps.contains(frontApp) {
        // Use CGEvent to simulate Cmd+V — doesn't require Accessibility permission
        let vKeyCode: CGKeyCode = 9  // 'v' key
        let source = CGEventSource(stateID: .combinedSessionState)

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            log("Auto-pasted into \(frontApp) via CGEvent")
        } else {
            log("Failed to create CGEvent")
        }
    } else {
        log("Frontmost app '\(frontApp)' not in paste targets, clipboard only")
    }
}

// MARK: - Cursor Display Detection

/// Get the display ID where the mouse cursor currently is
func cursorDisplayID() -> CGDirectDisplayID {
    let mouseLocation = CGEvent(source: nil)?.location ?? .zero
    var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    // Get the display containing the mouse point
    CGGetDisplaysWithPoint(mouseLocation, 16, &displayIDs, &count)
    return count > 0 ? displayIDs[0] : CGMainDisplayID()
}

/// Get pixel dimensions of a specific display
func displayPixelSize(_ displayID: CGDirectDisplayID) -> (width: Int, height: Int)? {
    guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }
    return (mode.pixelWidth, mode.pixelHeight)
}

// MARK: - Screenshot Handler

func checkForNewScreenshots() {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: screenshotDir) else { return }

    let screenshots = files.filter { $0.hasPrefix(screenshotPrefix) && $0.hasSuffix(".png") }

    // Collect all new screenshots first
    var newFullScreenPaths: [String] = []
    var newRegionPaths: [String] = []

    for file in screenshots where !knownFiles.contains(file) {
        knownFiles.insert(file)
        let fullPath = (screenshotDir as NSString).appendingPathComponent(file)
        log("New screenshot: \(file)")

        if isFullScreenScreenshot(path: fullPath) {
            newFullScreenPaths.append(fullPath)
        } else {
            newRegionPaths.append(fullPath)
            log("Region screenshot — no action")
        }
    }

    // Region screenshots (Cmd+Shift+4) = auto-paste the path
    // Full-screen screenshots (Cmd+Shift+3) = ignore
    if !newRegionPaths.isEmpty {
        // Only paste the most recent region screenshot
        let path = newRegionPaths.last!
        log("Region screenshot — auto-pasting path")
        handleFullScreenshot(path: path)
    }

    if !newFullScreenPaths.isEmpty {
        log("Full-screen screenshot(s) — no action (\(newFullScreenPaths.count) files)")
    }
}

// MARK: - File System Watcher using FSEvents

func startWatching() {
    var context = FSEventStreamContext()

    let callback: FSEventStreamCallback = { _, _, numEvents, eventPaths, _, _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            checkForNewScreenshots()
        }
    }

    guard let stream = FSEventStreamCreate(
        nil,
        callback,
        &context,
        [screenshotDir] as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.5,
        UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
    ) else {
        log("ERROR: Cannot create FSEvent stream")
        exit(1)
    }

    FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
    FSEventStreamStart(stream)
    log("FSEvents watcher started")
}

// MARK: - Main

seedKnownFiles()
startWatching()

log("Process started, entering run loop")
log("Cmd+Shift+3 (full screen) = auto-paste path into active app")
log("Cmd+Shift+4 (region) = normal screenshot, no paste")
RunLoop.main.run()
