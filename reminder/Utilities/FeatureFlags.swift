import Foundation

struct FeatureFlags {
    var enableAITranscription = false
    var keepHistoryDays = 30
    var allowUnlimitedMultimodal = false
    var requireLoginForLiveMode = false

    static let basic = FeatureFlags(
        enableAITranscription: false,
        keepHistoryDays: 30,
        allowUnlimitedMultimodal: false,
        requireLoginForLiveMode: false
    )

    static let pro = FeatureFlags(
        enableAITranscription: true,
        keepHistoryDays: 3650,
        allowUnlimitedMultimodal: true,
        requireLoginForLiveMode: true
    )
}
