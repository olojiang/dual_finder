import Foundation
import Testing
@testable import DualFinderCore

@Suite("FileMergeNaming")
struct FileMergeNamingTests {
    @Test("suggests common prefix and suffix as merged name")
    func suggestsCommonPrefixAndSuffix() {
        let names = [
            "Story Part 1.txt",
            "Story Part 2.txt",
            "Story Part 3.txt"
        ]

        #expect(FileMergeNaming.suggestedName(forNames: names) == "Story Part.txt")
    }

    @Test("keeps shared bracketed title and extension")
    func keepsSharedBracketedTitleAndExtension() {
        let names = [
            "《催眠常识修改调教我的妈妈和妹妹一》.txt",
            "《催眠常识修改调教我的妈妈和妹妹二》.txt",
            "《催眠常识修改调教我的妈妈和妹妹三》.txt"
        ]

        #expect(FileMergeNaming.suggestedName(forNames: names) == "《催眠常识修改调教我的妈妈和妹妹》.txt")
    }

    @Test("keeps shared middle text when names have multiple changing parts")
    func keepsSharedMiddleTextWhenNamesHaveMultipleChangingParts() {
        let names = [
            "《催眠常识A修改调教我的妈妈和妹妹一》.txt",
            "《催眠常识B修改调教我的妈妈和妹妹二》.txt",
            "《催眠常识C修改调教我的妈妈和妹妹三》.txt",
            "《催眠常识D修改调教我的妈妈和妹妹四》.txt"
        ]

        #expect(FileMergeNaming.suggestedName(forNames: names) == "《催眠常识修改调教我的妈妈和妹妹》.txt")
    }

    @Test("uses longest common base substring when wrappers differ")
    func usesLongestCommonBaseSubstringWhenWrappersDiffer() {
        let names = [
            "《美女养成师》.txt",
            "美女养成师堕落版 1-1300.txt"
        ]

        #expect(FileMergeNaming.suggestedName(forNames: names) == "美女养成师.txt")
    }

    @Test("prefers contiguous shared title over scattered subsequence")
    func prefersContiguousSharedTitleOverScatteredSubsequence() {
        let names = [
            "Alpha - 星海档案 - 01.txt",
            "Beta - 星海档案 - 02.txt",
            "Gamma - 星海档案 - 03.txt"
        ]

        #expect(FileMergeNaming.suggestedName(forNames: names) == "星海档案.txt")
    }

    @Test("combines stable outer and middle segments")
    func combinesStableOuterAndMiddleSegments() {
        let names = [
            "《催眠常识A修改调教我的妈妈和妹妹一》.txt",
            "《催眠常识B修改调教我的妈妈和妹妹二》.txt",
            "《催眠常识C修改调教我的妈妈和妹妹三》.txt"
        ]

        #expect(FileMergeNaming.suggestedName(forNames: names) == "《催眠常识修改调教我的妈妈和妹妹》.txt")
    }

    @Test("falls back with shared extension when common parts are not useful")
    func fallsBackWithSharedExtension() {
        #expect(FileMergeNaming.suggestedName(forNames: ["one.txt", "two.txt"]) == "Merged Files.txt")
    }
}
