import Foundation
@testable import SpeakSwiftlyServer
import Testing

// MARK: - Default Voice Catalog Tests

@Test func `default voice catalog loads package built in seeds`() throws {
    let voices = try DefaultVoiceCatalog.load()

    #expect(voices.map(\.seedID) == ["swift.signal", "swift.anchor"])
    #expect(voices.map(\.profileName) == ["swift-signal", "swift-anchor"])
    #expect(voices.map(\.fallbackProfileName) == ["swift-signal-builtin", "swift-anchor-builtin"])
    #expect(voices.allSatisfy { $0.author == .system })
    #expect(voices.allSatisfy { $0.sourceKind == .generatedDesign })
    #expect(voices.allSatisfy { $0.seedVersion == "1" })
}

@Test func `default voice catalog keeps seed identity separate from visible profile names`() throws {
    let voices = try DefaultVoiceCatalog.load()

    for voice in voices {
        #expect(voice.seedID.contains("."))
        #expect(voice.profileName.contains("-"))
        #expect(voice.fallbackProfileName == "\(voice.profileName)-builtin")
        #expect(voice.sampleMediaPath == "docs/media/default-voices/\(voice.profileName).wav")
        #expect(voice.voiceDescription.isEmpty == false)
        #expect(voice.sourceText.isEmpty == false)
    }
}

@Test func `default voice catalog reports missing resource with actionable context`() throws {
    do {
        _ = try DefaultVoiceCatalog.load(bundle: .main)
        Issue.record("Expected loading from the main bundle to miss the package resource catalog.")
    } catch let error as DefaultVoiceCatalogError {
        #expect(error.message.contains("DefaultVoiceProfiles/catalog.json"))
        #expect(error.message.contains("package resource bundle"))
    }
}
