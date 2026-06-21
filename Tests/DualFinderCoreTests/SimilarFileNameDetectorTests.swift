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

    @Test("groups book-title variants with longer edition descriptors")
    func groupsBookTitleVariantsWithLongerEditionDescriptors() {
        let items = [
            file("《绝色凶器》(校对版全本) 作者：艳墨.txt"),
            file("《绝色凶器 JSXQ (修改版)》.txt"),
            file("《经典之绝色凶器》(无删全本).txt"),
            file("翠微居《少龙外传》(无删全本) 作者：wtv.txt")
        ]

        let groups = SimilarFileNameDetector.groups(in: items)

        #expect(groups.count == 1)
        #expect(Set(groups[0].items.map(\.name)) == [
            "《绝色凶器》(校对版全本) 作者：艳墨.txt",
            "《绝色凶器 JSXQ (修改版)》.txt",
            "《经典之绝色凶器》(无删全本).txt"
        ])
    }

    @Test("groups short title variants when the normalized title is exact")
    func groupsExactShortTitleVariants() {
        let items = [
            file("御仙 1-71章 .txt"),
            file("御仙  作者：清风霜雪.txt"),
            file("御仙（1-2卷18章（1-45）_2间章）未完 - 清风霜雪.txt"),
            file("《御仙》第二部完结.txt"),
            file("御姐修行.txt")
        ]

        let groups = SimilarFileNameDetector.groups(in: items)

        #expect(groups.count == 1)
        #expect(Set(groups[0].items.map(\.name)) == [
            "御仙 1-71章 .txt",
            "御仙  作者：清风霜雪.txt",
            "御仙（1-2卷18章（1-45）_2间章）未完 - 清风霜雪.txt",
            "《御仙》第二部完结.txt"
        ])
    }

    @Test("groups names with missing opening title bracket and edition suffixes")
    func groupsMissingOpeningTitleBracketVariants() {
        let items = [
            file("半岛检察官加料版》作者：未知[1-378章] [已完结] - 未知.txt"),
            file("半岛检察官》作者：未知[1-420章] [未完结] - 未知.txt"),
            file("半岛检察官.txt"),
            file("半岛往事.txt")
        ]

        let groups = SimilarFileNameDetector.groups(in: items)

        #expect(groups.count == 1)
        #expect(Set(groups[0].items.map(\.name)) == [
            "半岛检察官加料版》作者：未知[1-378章] [已完结] - 未知.txt",
            "半岛检察官》作者：未知[1-420章] [未完结] - 未知.txt",
            "半岛检察官.txt"
        ])
    }

    @Test("does not fuzzy group different short titles")
    func rejectsDifferentShortTitles() {
        let items = [
            file("御仙.txt"),
            file("御姐.txt"),
            file("御宅.txt")
        ]

        #expect(SimilarFileNameDetector.groups(in: items).isEmpty)
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
