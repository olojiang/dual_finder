import Foundation
import Testing
@testable import DualFinderCore

@Suite("SimilarFileNameDetector")
struct SimilarFileNameDetectorTests {
    @Test("groups files whose names share a title with different suffixes")
    func groupsTitleVariants() {
        let items = [
            file("杨帆的校园生活.txt", size: 4_100_000, modifiedAt: date(2026, 6, 13)),
            file("杨帆的校园生活1-2.23.txt", size: 8_800_000, modifiedAt: date(2026, 6, 18)),
            file("杨帆的校园生活1-18 作者：就酱.txt", size: 2_100_000, modifiedAt: date(2026, 6, 17)),
            file("极品公子 超级加料版.txt", size: 14_100_000, modifiedAt: date(2026, 6, 17))
        ]

        let groups = SimilarFileNameDetector.groups(in: items)

        #expect(groups.count == 1)
        #expect(groups[0].items.map(\.name) == [
            "杨帆的校园生活.txt",
            "杨帆的校园生活1-2.23.txt",
            "杨帆的校园生活1-18 作者：就酱.txt"
        ])
    }

    @Test("orders group members by localized file name")
    func ordersGroupMembersByName() {
        let items = [
            file("《娇妻迷途》(全本) 作者：兮夜.txt"),
            file("《娇妻迷途》(1_434 全本) ［方远、张爱玲］ 作者：夜郎中～.txt")
        ]

        let groups = SimilarFileNameDetector.groups(in: items)

        #expect(groups.count == 1)
        #expect(groups[0].items.map(\.name) == [
            "《娇妻迷途》(1_434 全本) ［方远、张爱玲］ 作者：夜郎中～.txt",
            "《娇妻迷途》(全本) 作者：兮夜.txt"
        ])
    }

    @Test("orders multiple groups by localized group name")
    func ordersGroupsByName() {
        let items = [
            file("乙篇故事(全本).txt"),
            file("甲篇故事(全本).txt"),
            file("乙篇故事 1-20.txt"),
            file("甲篇故事 1-20.txt")
        ]

        let groups = SimilarFileNameDetector.groups(in: items)

        #expect(groups.map { $0.items[0].name } == [
            "甲篇故事(全本).txt",
            "乙篇故事(全本).txt"
        ])
    }

    @Test("does not group unrelated files that only share a short prefix")
    func rejectsShortSharedPrefixes() {
        let items = [
            file("末世：母狗养成基地.txt"),
            file("末世中的母子重制修改版.txt"),
            file("末世之霸艳雄途[1-196章，1-2卷60章].txt")
        ]

        #expect(SimilarFileNameDetector.groups(in: items).isEmpty)
    }

    @Test("keeps different file extensions in separate groups")
    func separatesExtensions() {
        let items = [
            file("Report final.txt"),
            file("Report final 2.pdf")
        ]

        #expect(SimilarFileNameDetector.groups(in: items).isEmpty)
    }

    private func file(_ name: String, size: Int64 = 1, modifiedAt: Date? = nil) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            kind: .file,
            type: "text",
            size: size,
            modifiedAt: modifiedAt,
            isHidden: false
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }
}
