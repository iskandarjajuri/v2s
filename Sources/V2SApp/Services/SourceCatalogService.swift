import AppKit
import AVFoundation
import CoreAudio
import Foundation

struct SourceCatalogSnapshot: Equatable {
    let applications: [InputSource]
    let microphones: [InputSource]
}

@MainActor
final class SourceCatalogService {
    private let microphoneDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external],
        mediaType: .audio,
        position: .unspecified
    )

    func loadSnapshot() -> SourceCatalogSnapshot {
        SourceCatalogSnapshot(
            applications: loadApplications(),
            microphones: loadMicrophones()
        )
    }

    private func loadApplications() -> [InputSource] {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular
                    && app.localizedName?.isEmpty == false
                    && app.bundleIdentifier != Bundle.main.bundleIdentifier
            }
            .map { app in
                InputSource(
                    id: "app:\(app.bundleIdentifier ?? "pid-\(app.processIdentifier)")",
                    name: app.localizedName ?? "Unknown App",
                    detail: app.bundleIdentifier ?? "pid-\(app.processIdentifier)",
                    category: .application
                )
            }

        return Self.orderedApplications(
            deduplicated(runningApps),
            playingBundleIdentifiers: Self.bundleIdentifiersRenderingAudio()
        )
    }

    /// 音を出しているアプリを先頭に、残りは名前順に並べる。会議中に v2s を開いたとき、
    /// 目的のアプリ（Meet を開いている Chrome 等）が一番上に来るので迷わず選べる。
    /// ブラウザは本体ではなくヘルパーから音を出すため、ヘルパーのバンドル ID の前方一致で見る
    /// （com.google.Chrome.helper → com.google.Chrome）。Safari の音は com.apple.WebKit.GPU から出る。
    nonisolated static func orderedApplications(
        _ applications: [InputSource],
        playingBundleIdentifiers: Set<String>
    ) -> [InputSource] {
        func isPlaying(_ source: InputSource) -> Bool {
            let bundleIdentifier = source.detail
            if bundleIdentifier == "com.apple.Safari",
               playingBundleIdentifiers.contains("com.apple.WebKit.GPU") {
                return true
            }
            return playingBundleIdentifiers.contains { $0 == bundleIdentifier || $0.hasPrefix(bundleIdentifier + ".") }
        }

        return applications.sorted { lhs, rhs in
            let lhsPlaying = isPlaying(lhs)
            let rhsPlaying = isPlaying(rhs)
            if lhsPlaying != rhsPlaying {
                return lhsPlaying
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Core Audio のプロセス一覧から、いま出力中のプロセスのバンドル ID を集める（権限不要）。
    private static func bundleIdentifiersRenderingAudio() -> Set<String> {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var processObjects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, &processObjects) == noErr else {
            return []
        }

        var result = Set<String>()
        for processObject in processObjects {
            var outputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunningOutput: UInt32 = 0
            var outputSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(processObject, &outputAddress, 0, nil, &outputSize, &isRunningOutput) == noErr,
                  isRunningOutput != 0 else {
                continue
            }

            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var bundleIdentifier: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(processObject, &bundleAddress, 0, nil, &bundleSize, &bundleIdentifier) == noErr,
               let value = bundleIdentifier?.takeRetainedValue() as String?,
               value.isEmpty == false {
                result.insert(value)
            }
        }
        return result
    }

    private func loadMicrophones() -> [InputSource] {
        let devices = microphoneDiscoverySession.devices.map { device in
            InputSource(
                id: "mic:\(device.uniqueID)",
                name: device.localizedName,
                detail: device.uniqueID,
                category: .microphone
            )
        }

        return deduplicated(devices)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func deduplicated(_ sources: [InputSource]) -> [InputSource] {
        var seen = Set<String>()

        return sources.filter { source in
            seen.insert(source.id).inserted
        }
    }
}
