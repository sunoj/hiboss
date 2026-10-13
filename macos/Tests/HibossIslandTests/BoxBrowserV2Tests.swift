// Regression coverage for selection, combined filters, confirmation and Box timestamps.
// Exports: BoxBrowserV2Tests, using the same store/action paths as the native browser.
// Dependencies: XCTest, AppKit, HibossKit and synthetic BoxBrowserFixtures.

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class BoxBrowserV2Tests: XCTestCase {
    func testTextRowsUseFirstLineAsTitleAndKeepTheFullContent() {
        let text = "A reference title\nThe full content stays available for preview and copying."
        let item = BoxBrowserFixtures.item("reference", text: text)
        XCTAssertEqual(item.displayTitle, "A reference title")
        XCTAssertEqual(item.summary, "The full content stays available for preview and copying.")
        XCTAssertEqual(item.text, text)
        XCTAssertEqual(item.detailBody, text)
        XCTAssertEqual(BoxBrowserFixtures.item("single", text: "Single line").summary, "")
        XCTAssertNil(BoxBrowserFixtures.item("single", text: "Single line").detailBody)
        let file = BoxBrowserFixtures.item("file", kind: .file, text: "Review",
            hasMedia: true, mediaType: "application/pdf")
        XCTAssertEqual(file.fileExtension, "PDF")
    }

    func testDetailFormatCombinesKnownMediaPartsAndOmitsUnknownParts() {
        let image = BoxBrowserFixtures.item("image", kind: .image, text: "preview.png",
            hasMedia: true, mediaType: "image/png", mediaBytes: 1_200_000, width: 1600, height: 900)
        let file = BoxBrowserFixtures.item("file", kind: .file, text: "report.pdf",
            hasMedia: true, mediaType: "application/pdf", mediaBytes: 240_000)
        let video = BoxBrowserFixtures.item("video", kind: .video, text: "clip.mp4",
            hasMedia: true, mediaType: "video/mp4", mediaBytes: 8_400_000, durationMs: 12_000)
        let unknownImage = BoxBrowserFixtures.item("unknown", kind: .image, text: nil,
            hasMedia: true, mediaType: nil)

        XCTAssertEqual(image.detailFormat, "PNG · 1600×900 · 1.2 MB")
        XCTAssertEqual(file.detailFormat, "PDF · 240 KB")
        XCTAssertEqual(video.detailFormat, "MP4 · 0:12 · 8.4 MB")
        XCTAssertNil(unknownImage.detailFormat)
    }

    func testDetailTracksSelectionAndClearsWhenFilteredOrReset() async throws {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        await store.refresh()
        XCTAssertNil(store.selectedItem)
        store.selection = "image"
        XCTAssertEqual(store.selectedItem?.displayTitle, "Navigation preview.png")
        store.selection = "link"
        XCTAssertEqual(store.selectedItem?.url, "https://developer.apple.com/swiftui/")
        store.author = .agents
        XCTAssertNil(store.selectedItem)
        XCTAssertNil(store.selection)
        store.selection = "text"
        store.reset()
        XCTAssertNil(store.selectedItem)
        XCTAssertNil(store.selection)
    }

    func testKindAndAuthorFiltersCombineWithoutResettingEachOther() async {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        await store.refresh()
        store.author = .agents
        store.kind = .image
        await store.refresh()
        XCTAssertEqual(store.author, .agents)
        XCTAssertEqual(store.visibleItems.map(\.id), ["image"])
        store.author = .boss
        XCTAssertEqual(store.kind, .image)
        XCTAssertTrue(store.visibleItems.isEmpty)
        store.kind = .link
        await store.refresh()
        XCTAssertEqual(store.author, .boss)
        XCTAssertEqual(store.visibleItems.map(\.id), ["link"])
    }

    func testArrowSelectionStopsAtBoundsAndDrivesDetail() async {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        await store.refresh()
        store.moveSelection(by: 1)
        XCTAssertEqual(store.selectedItem?.id, store.visibleItems.first?.id)
        store.moveSelection(by: -1)
        XCTAssertEqual(store.selectedItem?.id, store.visibleItems.first?.id)
        store.moveSelection(by: 1)
        XCTAssertEqual(store.selectedItem?.id, store.visibleItems[1].id)
        store.moveSelection(by: 100)
        XCTAssertEqual(store.selectedItem?.id, store.visibleItems.last?.id)
    }

    func testDeleteNamesItemAndOnlyConfirmationCallsAPI() async throws {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        await store.refresh()
        let item = try XCTUnwrap(store.items.first)
        store.selection = item.id
        store.requestDelete(item)
        XCTAssertTrue(try XCTUnwrap(store.pendingDelete).deleteTitle.contains(item.displayTitle))
        let beforeConfirmation = await api.deleted
        XCTAssertEqual(beforeConfirmation, [])
        store.pendingDelete = nil
        XCTAssertTrue(store.items.contains(item))
        store.requestDelete(item)
        let confirmed = await store.confirmDelete(item)
        XCTAssertEqual(confirmed, item)
        let deleted = await api.deleted
        XCTAssertEqual(deleted, [item.id])
        XCTAssertNil(store.selectedItem)
        XCTAssertNil(store.pendingDelete)
    }

    func testNoteEditingUpdatesSelectedDetail() async {
        let api = ScriptedBoxBrowser()
        let store = BoxBrowserStore { api }
        await store.refresh()
        let item = BoxBrowserFixtures.items[0]
        store.selection = item.id
        let saved = await store.updateNote("Revised note", for: item)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.selectedItem?.note, "Revised note")
    }

    func testTimeFormatsJustNowMinutesRecentYesterdayAndAbsoluteChineseDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(ISODate.parse("2026-10-12T09:00:00Z"))
        let locale = Locale(identifier: "zh_Hans_CN")
        XCTAssertEqual(BoxTime.relative("2026-10-12T08:59:23Z", now: now,
            locale: locale, calendar: calendar), "刚刚")
        XCTAssertEqual(BoxTime.relative("2026-10-12T08:57:00Z", now: now,
            locale: locale, calendar: calendar), "3分钟前")
        XCTAssertEqual(BoxTime.relative("2026-10-11T22:30:00Z", now: now,
            locale: locale, calendar: calendar), "10小时30分钟前")
        XCTAssertEqual(BoxTime.absolute("2026-10-11T22:30:00Z",
            now: try XCTUnwrap(ISODate.parse("2027-10-12T09:00:00Z")), locale: locale,
            timeZone: calendar.timeZone), "2026年10月11日 22:30")
        XCTAssertEqual(BoxTime.absolute("invalid"), "invalid")
        XCTAssertEqual(BoxTime.relative("invalid"), "invalid")
        XCTAssertEqual(BoxTime.relative("2026-10-12T09:00:05Z", now: now,
            locale: locale, calendar: calendar), "09:00")
        XCTAssertEqual(BoxTime.relative("2026-10-12T08:59:59Z", now: now,
            locale: Locale(identifier: "en_US"), calendar: calendar), "Just now")
        XCTAssertEqual(BoxTime.relative("2026-10-12T08:59:00Z", now: now,
            locale: Locale(identifier: "en_US"), calendar: calendar), "1 min ago")
    }

    func testDateSectionsUseLocalCalendarAcrossMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Bangkok"))
        calendar.firstWeekday = 2
        let now = try XCTUnwrap(ISODate.parse("2026-10-14T18:00:00Z"))
        XCTAssertEqual(BoxDateSection.section(for: "2026-10-14T17:30:00Z", now: now,
            calendar: calendar), .today)
        XCTAssertEqual(BoxDateSection.section(for: "2026-10-14T16:30:00Z", now: now,
            calendar: calendar), .yesterday)
        XCTAssertEqual(BoxDateSection.section(for: "2026-10-12T10:30:00Z", now: now,
            calendar: calendar), .thisWeek)
        XCTAssertEqual(BoxDateSection.section(for: "2026-10-01T10:30:00Z", now: now,
            calendar: calendar), .earlier)
    }

    func testRowsUseRelativeHoursAndAbsoluteOlderDatesInEnglishAndChinese() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(ISODate.parse("2026-10-12T09:00:00Z"))
        for (locale, hours, days) in [
            (Locale(identifier: "en_GB"), "2 hr ago", "9 Oct 09:00"),
            (Locale(identifier: "zh_Hans_CN"), "2小时前", "10月9日 09:00")
        ] {
            XCTAssertEqual(BoxTime.relative("2026-10-12T07:00:00Z", now: now,
                locale: locale, calendar: calendar), hours)
            XCTAssertEqual(BoxTime.relative("2026-10-09T09:00:00Z", now: now,
                locale: locale, calendar: calendar), days)
        }
    }

    func testQuickLookBuildsLocalTextAndLinkFilesAndCleansThemUp() async throws {
        let media = BoxBrowserMedia { nil }
        let text = BoxBrowserFixtures.item("text", text: "Full text for Quick Look")
        let url = try await BoxBrowserActions.previewURL(text, media: media)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text.text)
        let link = BoxBrowserFixtures.items[1]
        let linkURL = try await BoxBrowserActions.previewURL(link, media: media)
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: linkURL),
            format: nil) as? [String: String]
        XCTAssertEqual(plist?["URL"], link.url)
        XCTAssertEqual(BoxPaneAction.available(for: text), [.quickLook, .copy, .share, .editNote, .delete])
        XCTAssertTrue(BoxPaneAction.available(for: link).contains(.open))
        media.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkURL.path))
    }
}
