import Foundation
import Testing
@testable import DualFinderApp
@testable import DualFinderCore

@Suite("UnmountFailurePrompt")
struct UnmountFailurePromptTests {
    @Test("identifies blocking processes and open paths")
    func identifiesBlockingProcesses() {
        let prompt = UnmountFailurePrompt(
            volumeName: "Media",
            mountPath: "/Volumes/Media",
            failureReason: "Resource busy",
            blockers: [UnmountProcessBlocker(
                processID: 412,
                processName: "QuickLookUIService",
                openPaths: ["/Volumes/Media/Film One.mkv"],
                executablePath: "/System/Library/Frameworks/QuickLook.framework/QuickLookUIService",
                userName: "hunter"
            )],
            inspectionError: nil
        )

        #expect(prompt.message.contains("QuickLookUIService (PID 412)"))
        #expect(prompt.message.contains("Executable: /System/Library/Frameworks/QuickLook.framework/QuickLookUIService"))
        #expect(prompt.message.contains("User: hunter"))
        #expect(prompt.message.contains("/Volumes/Media/Film One.mkv"))
        #expect(prompt.message.contains("Resource busy"))
    }
}
