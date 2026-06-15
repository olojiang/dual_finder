import Foundation
import Testing
@testable import DualFinderApp

@Suite("PrivacyPermissionGuide")
struct PrivacyPermissionGuideTests {
    @Test("detects Cocoa and POSIX permission failures")
    func detectsPermissionFailures() {
        let guide = PrivacyPermissionGuide()
        let cocoaRead = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        let cocoaWrite = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        let posixAccess = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        let posixPerm = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))

        #expect(guide.isFilePermissionDenied(cocoaRead))
        #expect(guide.isFilePermissionDenied(cocoaWrite))
        #expect(guide.isFilePermissionDenied(posixAccess))
        #expect(guide.isFilePermissionDenied(posixPerm))
    }

    @Test("detects permission failures wrapped as underlying errors")
    func detectsUnderlyingPermissionFailures() {
        let guide = PrivacyPermissionGuide()
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
            ]
        )
        let unrelated = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)

        #expect(guide.isFilePermissionDenied(wrapped))
        #expect(!guide.isFilePermissionDenied(unrelated))
    }
}
