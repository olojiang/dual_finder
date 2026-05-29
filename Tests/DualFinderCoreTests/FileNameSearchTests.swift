import Testing
@testable import DualFinderCore

@Suite("FileNameSearch")
struct FileNameSearchTests {
    @Test("matches existing localized file name substrings")
    func matchesLocalizedSubstrings() {
        #expect(FileNameSearch.matches("sample_for_hunter", query: "hunter"))
        #expect(FileNameSearch.matches("PF_claw.jpeg", query: "pf"))
    }

    @Test("matches Chinese names by pinyin initials")
    func matchesChinesePinyinInitials() {
        let name = "篇章-王赫野#2F6Jni-original-pitch-up-3.mp3"

        #expect(FileNameSearch.matches(name, query: "pz"))
        #expect(FileNameSearch.matches(name, query: "why"))
        #expect(FileNameSearch.matches(name, query: "pzwhy"))
        #expect(FileNameSearch.matches(name, query: "p z"))
    }

    @Test("matches Chinese names by compact full pinyin")
    func matchesChineseFullPinyin() {
        let name = "篇章-王赫野#2F6Jni-original-pitch-up-3.mp3"

        #expect(FileNameSearch.matches(name, query: "pianzhang"))
        #expect(FileNameSearch.matches(name, query: "wangheye"))
    }

    @Test("rejects unrelated pinyin initials")
    func rejectsUnrelatedInitials() {
        #expect(!FileNameSearch.matches("篇章-王赫野.mp3", query: "zz"))
    }
}
