import Foundation
#if canImport(CoreAudio)
import CoreAudio
#endif

// MARK: - Audio Route End-to-End Helpers

extension ServerE2E {
#if canImport(CoreAudio)
    private struct E2EAudioOutputDevice {
        let id: AudioDeviceID
        let name: String
        let transportType: UInt32
    }

    static func stabilizeBuiltInAudioRouteForAudiblePlayback() throws {
        let preferredDevice = try preferredBuiltInAudioOutputDevice()
        try setDefaultAudioDevice(
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            deviceID: preferredDevice.id,
            deviceName: preferredDevice.name,
        )
        try setDefaultAudioDevice(
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            deviceID: preferredDevice.id,
            deviceName: preferredDevice.name,
        )

        let deadline = Date().addingTimeInterval(8)
        var consecutiveStableSamples = 0
        while Date() < deadline {
            let defaultOutput = try currentAudioOutputDevice(
                selector: kAudioHardwarePropertyDefaultOutputDevice,
            )
            let systemOutput = try currentAudioOutputDevice(
                selector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            )

            if defaultOutput?.id == preferredDevice.id, systemOutput?.id == preferredDevice.id {
                consecutiveStableSamples += 1
                if consecutiveStableSamples >= 4 {
                    return
                }
            } else {
                consecutiveStableSamples = 0
            }

            Thread.sleep(forTimeInterval: 0.25)
        }

        let finalDefaultOutput = try currentAudioOutputDevice(
            selector: kAudioHardwarePropertyDefaultOutputDevice,
        )?.name ?? "unknown output device"
        let finalSystemOutput = try currentAudioOutputDevice(
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        )?.name ?? "unknown system output device"
        throw try SpeakSwiftlyBuildError(
            """
            The live audible end-to-end suite could not stabilize macOS playback on the built-in speakers.
            preferred_output: \(preferredDevice.name)
            default_output_after_retries: \(finalDefaultOutput)
            system_output_after_retries: \(finalSystemOutput)
            available_output_devices: \(availableAudioOutputDevices().map(\.name).joined(separator: ", "))
            """,
        )
    }

    private static func preferredBuiltInAudioOutputDevice() throws -> E2EAudioOutputDevice {
        let outputDevices = try availableAudioOutputDevices()
        let preferredNameFragments = [
            "MacBook Pro Speakers",
            "Mac mini Speakers",
            "Built-in Output",
            "Built-in Speakers",
        ]

        if let namedMatch = outputDevices.first(where: { device in
            preferredNameFragments.contains { fragment in
                device.name.localizedCaseInsensitiveContains(fragment)
            }
        }) {
            return namedMatch
        }

        if let builtInMatch = outputDevices.first(where: { $0.transportType == kAudioDeviceTransportTypeBuiltIn }) {
            return builtInMatch
        }

        throw SpeakSwiftlyBuildError(
            """
            The live audible end-to-end suite could not find a built-in macOS output device to pin before playback.
            available_output_devices: \(outputDevices.map(\.name).joined(separator: ", "))
            """,
        )
    }

    private static func availableAudioOutputDevices() throws -> [E2EAudioOutputDevice] {
        try allAudioDeviceIDs().compactMap { deviceID in
            guard try audioDeviceHasOutputStreams(deviceID) else {
                return nil
            }

            return try E2EAudioOutputDevice(
                id: deviceID,
                name: audioDeviceName(deviceID),
                transportType: audioDeviceTransportType(deviceID),
            )
        }
    }

    private static func currentAudioOutputDevice(selector: AudioObjectPropertySelector) throws -> E2EAudioOutputDevice? {
        let deviceID = try audioHardwareDeviceID(selector: selector)
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return nil
        }

        return try E2EAudioOutputDevice(
            id: deviceID,
            name: audioDeviceName(deviceID),
            transportType: audioDeviceTransportType(deviceID),
        )
    }

    private static func setDefaultAudioDevice(
        selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID,
        deviceName: String,
    ) throws {
        var mutableDeviceID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            dataSize,
            &mutableDeviceID,
        )
        guard status == noErr else {
            throw SpeakSwiftlyBuildError(
                "The live audible end-to-end suite could not select '\(deviceName)' as the active macOS audio route. CoreAudio status: \(status).",
            )
        }
    }

    private static func allAudioDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        var dataSize = UInt32.zero
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
        )
        guard sizeStatus == noErr else {
            throw SpeakSwiftlyBuildError(
                "The live audible end-to-end suite could not enumerate macOS audio devices. CoreAudio status: \(sizeStatus).",
            )
        }

        var deviceIDs = Array(
            repeating: AudioDeviceID(kAudioObjectUnknown),
            count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size,
        )
        let readStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs,
        )
        guard readStatus == noErr else {
            throw SpeakSwiftlyBuildError(
                "The live audible end-to-end suite could not read macOS audio device identifiers. CoreAudio status: \(readStatus).",
            )
        }

        return deviceIDs
    }

    private static func audioHardwareDeviceID(selector: AudioObjectPropertySelector) throws -> AudioDeviceID {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID,
        )
        guard status == noErr else {
            throw SpeakSwiftlyBuildError(
                "The live audible end-to-end suite could not inspect the active macOS output route. CoreAudio status: \(status).",
            )
        }

        return deviceID
    }

    private static func audioDeviceName(_ deviceID: AudioDeviceID) throws -> String {
        var name = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &dataSize,
                UnsafeMutableRawPointer(pointer),
            )
        }
        guard status == noErr else {
            throw SpeakSwiftlyBuildError(
                "The live audible end-to-end suite could not read the name for macOS audio device id '\(deviceID)'. CoreAudio status: \(status).",
            )
        }

        return name as String
    }

    private static func audioDeviceTransportType(_ deviceID: AudioDeviceID) throws -> UInt32 {
        var transportType = UInt32.zero
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &transportType,
        )
        guard status == noErr else {
            throw try SpeakSwiftlyBuildError(
                "The live audible end-to-end suite could not read the transport type for macOS audio device '\(audioDeviceName(deviceID))'. CoreAudio status: \(status).",
            )
        }

        return transportType
    }

    private static func audioDeviceHasOutputStreams(_ deviceID: AudioDeviceID) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain,
        )
        var dataSize = UInt32.zero
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
        )
        guard status == noErr else {
            throw try SpeakSwiftlyBuildError(
                "The live audible end-to-end suite could not inspect output streams for macOS audio device '\(audioDeviceName(deviceID))'. CoreAudio status: \(status).",
            )
        }

        return dataSize >= UInt32(MemoryLayout<AudioStreamID>.size)
    }
#else
    private static func stabilizeBuiltInAudioRouteForAudiblePlayback() throws {
        throw SpeakSwiftlyBuildError(
            "The live audible end-to-end suite can only stabilize the audio route on macOS builds with CoreAudio available.",
        )
    }
#endif
}
