import Foundation
import Testing
@testable import RipPipelineEngine

struct RipPipelineEngineTests {

    @Test func testMakeMKVGenericTrackRecognition() {
        let generic1 = URL(fileURLWithPath: "/Rips/title_t00.mkv")
        let res1 = DiscRipRecognizer.analyze(fileURL: generic1)
        #expect(res1.isDiscRip == true)
        #expect(res1.reason == .genericMakeMKV)

        let generic2 = URL(fileURLWithPath: "/Rips/title01.mkv")
        let res2 = DiscRipRecognizer.analyze(fileURL: generic2)
        #expect(res2.isDiscRip == true)

        let generic3 = URL(fileURLWithPath: "/Rips/t00.mkv")
        let res3 = DiscRipRecognizer.analyze(fileURL: generic3)
        #expect(res3.isDiscRip == true)
    }

    @Test func testMakeMKVVolumeTrackWithSuggestion() {
        let disc = URL(fileURLWithPath: "/Rips/THE_MATRIX_t00.mkv")
        let res = DiscRipRecognizer.analyze(fileURL: disc)
        #expect(res.isDiscRip == true)
        #expect(res.reason == .rawDiscTrack)
        #expect(res.suggestedTitle == "The Matrix")

        let disc2 = URL(fileURLWithPath: "/Rips/AVATAR_DISC1_t01.mkv")
        let res2 = DiscRipRecognizer.analyze(fileURL: disc2)
        #expect(res2.isDiscRip == true)
        #expect(res2.suggestedTitle == "Avatar")
    }

    @Test func testDVDAndBluRayStreamRecognition() {
        let dvd = URL(fileURLWithPath: "/Rips/VTS_01_1.mkv")
        let resDVD = DiscRipRecognizer.analyze(fileURL: dvd)
        #expect(resDVD.isDiscRip == true)
        #expect(resDVD.reason == .dvdStream)

        let bd = URL(fileURLWithPath: "/Rips/00800.mkv")
        let resBD = DiscRipRecognizer.analyze(fileURL: bd)
        #expect(resBD.isDiscRip == true)
        #expect(resBD.reason == .blurayStream)
    }

    @Test func testGenericDiscLabels() {
        let genericDisc = URL(fileURLWithPath: "/Rips/DISC_1.mkv")
        let res = DiscRipRecognizer.analyze(fileURL: genericDisc)
        #expect(res.isDiscRip == true)
        #expect(res.reason == .genericDiscLabel)

        let untitled = URL(fileURLWithPath: "/Rips/UNTITLED.mkv")
        let res2 = DiscRipRecognizer.analyze(fileURL: untitled)
        #expect(res2.isDiscRip == true)
    }

    @Test func testStandardMediaFilesNotFlagged() {
        let movie = URL(fileURLWithPath: "/Rips/Inception (2010).mkv")
        let resMovie = DiscRipRecognizer.analyze(fileURL: movie)
        #expect(resMovie.isDiscRip == false)

        let tv = URL(fileURLWithPath: "/Rips/Breaking Bad S01E01 Pilot.mkv")
        let resTV = DiscRipRecognizer.analyze(fileURL: tv)
        #expect(resTV.isDiscRip == false)
    }

    @Test func testCleanSuggestedDiscTitle() {
        let cleaned = DiscRipRecognizer.cleanSuggestedDiscTitle("THE_LORD_OF_THE_RINGS_FELLOWSHIP_OF_THE_RING_D1")
        #expect(cleaned == "The Lord of the Rings Fellowship of the Ring")
    }
}
