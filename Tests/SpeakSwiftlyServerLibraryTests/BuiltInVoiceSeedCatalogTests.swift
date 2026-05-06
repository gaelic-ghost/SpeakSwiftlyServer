import Foundation
@testable import SpeakSwiftlyServer
import Testing

// MARK: - Built-In Voice Seed Catalog Tests

@Test func `built in voice seed catalog loads package built in seeds`() throws {
    let voices = try BuiltInVoiceSeedCatalog.load()

    #expect(voices.map(\.seedID) == ["swift.signal", "swift.anchor"])
    #expect(voices.map(\.profileName) == ["swift-signal", "swift-anchor"])
    #expect(voices.map(\.fallbackProfileName) == ["swift-signal-builtin", "swift-anchor-builtin"])
    #expect(voices.allSatisfy { $0.author == .system })
    #expect(voices.allSatisfy { $0.sourceKind == .generatedDesign })
    #expect(voices.allSatisfy { $0.seedVersion == "1" })
}

@Test func `built in voice seed catalog keeps seed identity separate from visible profile names`() throws {
    let voices = try BuiltInVoiceSeedCatalog.load()

    for voice in voices {
        #expect(voice.seedID.contains("."))
        #expect(voice.profileName.contains("-"))
        #expect(voice.fallbackProfileName == "\(voice.profileName)-builtin")
        #expect(voice.sampleMediaPath == "docs/media/default-voices/\(voice.profileName).wav")
        #expect(voice.voiceDescription.isEmpty == false)
        #expect(voice.sourceText.isEmpty == false)
    }
}

@Test func `built in voice seed catalog reports missing resource with actionable context`() throws {
    do {
        _ = try BuiltInVoiceSeedCatalog.load(bundle: .main)
        Issue.record("Expected loading from the main bundle to miss the package resource catalog.")
    } catch let error as BuiltInVoiceSeedCatalogError {
        #expect(error.message.contains("DefaultVoiceProfiles/catalog.json"))
        #expect(error.message.contains("package resource bundle"))
    }
}
