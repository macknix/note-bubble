import Foundation
@testable import NoteBubbleCore

@MainActor
enum WorkspaceTests {
    private static func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notebubble-workspaces-\(UUID().uuidString).json")
    }

    private static func makeStore() -> (BubbleStore, URL) {
        let url = tempURL()
        return (BubbleStore(fileURL: url), url)
    }

    private static func named(_ store: BubbleStore, _ texts: [String]) {
        for text in texts {
            let id = store.addBubble()
            store.updateText(text, for: id)
        }
        store.editingID = nil
    }

    /// Writes a file in the shape the app used before workspaces existed.
    private static func writeLegacyFile(at url: URL, _ notes: [BubbleNode]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(notes).write(to: url)
    }

    static func run() {
        Check.suite("Workspaces — upgrading an old file") {
            let url = tempURL()
            defer { try? FileManager.default.removeItem(at: url) }

            var parent = BubbleNode(text: "kitchen shelves")
            parent.children = [BubbleNode(text: "measure the alcove")]
            writeLegacyFile(at: url, [parent, BubbleNode(text: "bins")])

            let store = BubbleStore(fileURL: url)
            Check.equal(store.workspaces.count, 1, "a pre-workspace file becomes one workspace")
            Check.equal(store.currentWorkspace.name, Workspace.defaultName,
                        "and it is named for the single board it always was")
            Check.equal(store.visible.map(\.text), ["kitchen shelves", "bins"],
                        "every note survives the upgrade, in order")
            Check.equal(store.root.flattened.count, 3, "including the nested ones")

            // And the next save rewrites it in the current shape without loss.
            store.saveNow()
            let reloaded = BubbleStore(fileURL: url)
            Check.equal(reloaded.root.flattened.count, 3, "re-saving keeps the notes")
            Check.equal(reloaded.workspaces.count, 1, "and still just the one board")
        }

        Check.suite("Workspaces — notes belong to their own board") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            named(store, ["home a", "home b"])
            let second = store.addWorkspace(named: "Work")
            Check.equal(store.workspaces.count, 2, "a second board is added")
            Check.equal(store.currentWorkspaceID, second, "and opened")
            Check.isTrue(store.visible.isEmpty, "a new board starts empty")

            named(store, ["work a"])
            Check.equal(store.visible.map(\.text), ["work a"], "notes land on the board you are on")

            store.selectWorkspace(at: 0)
            Check.equal(store.visible.map(\.text), ["home a", "home b"],
                        "the first board is exactly as it was left")
            Check.equal(store.stageCounts.fresh, 2, "and the counts are its own, not the whole app's")
        }

        Check.suite("Workspaces — switching leaves you at the top") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            named(store, ["parent"])
            let parent = store.visible[0].id
            store.drillInto(parent)
            named(store, ["child"])
            Check.equal(store.path, [parent], "standing inside a bubble")

            store.addWorkspace(named: "Other")
            Check.isTrue(store.isAtRoot, "a new board opens at its own top level")

            store.selectWorkspace(at: 0)
            Check.isTrue(store.isAtRoot, "and coming back lands at the top, not in a stale path")
            Check.equal(store.visible.map(\.text), ["parent"], "the bubble and its child are intact")
            Check.equal(store.visible[0].children.map(\.text), ["child"], "nesting survives the trip")
        }

        Check.suite("Workspaces — the ends are hard stops") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            store.renameWorkspace(store.currentWorkspaceID, to: "one")
            store.addWorkspace(named: "two")
            store.selectWorkspace(at: 0)

            Check.isFalse(store.goToPreviousWorkspace(), "there is nothing before the first board")
            Check.equal(store.currentIndex, 0, "so it stays put")
            Check.isTrue(store.goToNextWorkspace(), "forwards works")
            Check.equal(store.currentIndex, 1, "and lands on the next board")
            Check.isFalse(store.goToNextWorkspace(), "the last board is the end of the shelf")
            Check.equal(store.currentIndex, 1, "rather than wrapping round to the first")
        }

        Check.suite("Workspaces — naming") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            let id = store.addWorkspace()
            Check.equal(store.renamingWorkspaceID, id, "a new board opens straight into its name field")
            Check.equal(store.currentWorkspace.displayName, "Untitled", "until it is given one")

            store.renameWorkspace(id, to: "Errands")
            store.renamingWorkspaceID = nil
            Check.equal(store.currentWorkspace.name, "Errands", "renaming takes")
            Check.equal(store.workspaces.count, 2, "and the board stays")

            // A board made by a stray click and abandoned leaves no litter, exactly
            // like a bubble that was never typed into.
            store.addWorkspace()
            Check.equal(store.workspaces.count, 3, "a blank board exists while being named")
            store.renamingWorkspaceID = nil
            Check.equal(store.workspaces.count, 2, "and is discarded when the name field is left")
            Check.equal(store.currentWorkspace.name, "Errands", "leaving you where you were")

            // One with notes on it is not litter, whatever it is called.
            store.addWorkspace()
            named(store, ["something"])
            store.renamingWorkspaceID = nil
            Check.equal(store.workspaces.count, 3, "a nameless board with notes in it survives")

            // Switching away from a blank board discards it on the way out — so the
            // board being switched *to* has to be re-found afterwards, not trusted
            // to still be at the index it was asked for.
            store.addWorkspace()
            Check.equal(store.workspaces.count, 4, "a fourth board, blank and being named")
            store.selectWorkspace(at: 0)
            Check.equal(store.workspaces.count, 3, "leaving it discards it")
            Check.equal(store.currentIndex, 0, "and you land on the board you actually asked for")
        }

        Check.suite("Workspaces — filing a note onto another board") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            store.renameWorkspace(store.currentWorkspaceID, to: "Home")
            named(store, ["keep", "moving"])
            let home = store.currentWorkspaceID
            let work = store.addWorkspace(named: "Work")
            store.renamingWorkspaceID = nil
            store.selectWorkspace(home)

            // Filing happens while still standing on the board the note is leaving;
            // the panel swipes to the destination afterwards, so the note is already
            // there when that board arrives.
            let moving = store.visible[1].id
            Check.isTrue(store.move(moving, toWorkspace: work), "the note moves")
            Check.equal(store.visible.map(\.text), ["keep"], "and leaves the board it was on")

            store.selectWorkspace(work)
            Check.equal(store.visible.map(\.text), ["moving"],
                        "arriving at the top of the board it was filed on")

            store.undo()
            Check.equal(store.currentWorkspace.name, "Home", "undo returns to the board it came from")
            Check.equal(store.visible.map(\.text), ["keep", "moving"], "and puts it back")

            // A note can be filed from any level, not just the top.
            let parent = store.visible[0].id
            store.drillInto(parent)
            named(store, ["inner", "deeper"])
            let nested = store.visible[0].id

            Check.isTrue(store.move(nested, toWorkspace: work),
                         "a nested note can be filed onto another board")
            Check.equal(store.visible.map(\.text), ["deeper"], "leaving the level it was on")
            store.undo()
            Check.equal(store.path, [parent], "undo returns to the level it was filed from")
            Check.equal(store.visible.map(\.text), ["inner", "deeper"], "with the note back in it")

            // And a whole subtree travels with it.
            store.goUp()
            store.move(parent, toWorkspace: work)
            store.selectWorkspace(work)
            Check.equal(store.visible.map(\.text), ["keep"], "the parent arrives")
            Check.equal(store.visible[0].children.map(\.text), ["inner", "deeper"],
                        "with its children")

            // Nothing sensible to do with these, and none of them may crash.
            Check.isFalse(store.move(UUID(), toWorkspace: home), "an unknown note moves nowhere")
            Check.isFalse(store.move(store.visible[0].id, toWorkspace: UUID()),
                          "nor does one sent to a board that isn't there")
            Check.isFalse(store.move(store.visible[0].id, toWorkspace: work),
                          "and a note cannot be filed onto the board it is already on")
        }

        Check.suite("Workspaces — undo keeps what happened afterwards") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            store.renameWorkspace(store.currentWorkspaceID, to: "Home")
            named(store, ["stays", "travels"])
            let home = store.currentWorkspaceID
            let work = store.addWorkspace(named: "Work")
            store.renamingWorkspaceID = nil
            named(store, ["work note"])
            store.selectWorkspace(home)

            // Filed, then edited and joined by another note on the board it went to.
            let travels = store.visible[1].id
            store.move(travels, toWorkspace: work)
            store.selectWorkspace(work)
            store.updateText("travels, edited on Work", for: travels)
            named(store, ["written on Work since"])

            store.undo()
            Check.equal(store.currentWorkspaceID, home, "undoing a filing returns to the board it left")
            Check.equal(store.visible.map(\.text), ["stays", "travels, edited on Work"],
                        "bringing the note back as it is now, edits and all")
            store.selectWorkspace(work)
            Check.equal(store.visible.map(\.text), ["work note", "written on Work since"],
                        "and leaving the other board's later notes where they are")

            // A board deleted, then more written elsewhere: both survive the undo.
            store.removeWorkspace(work)
            named(store, ["written on Home since"])
            store.undo()
            Check.equal(store.workspaces.map(\.name), ["Home", "Work"],
                        "undoing a deletion puts the board back in its place")
            Check.equal(store.currentWorkspaceID, work, "and returns you to it")
            store.selectWorkspace(home)
            Check.equal(store.visible.map(\.text), ["stays", "travels, edited on Work", "written on Home since"],
                        "without losing what was written after it went")
        }

        Check.suite("Workspaces — popping something no longer in front of you") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            named(store, ["on home"])
            let note = store.visible[0].id
            store.addWorkspace(named: "Work")
            store.renamingWorkspaceID = nil

            // A confirmation answered after switching boards: the note is elsewhere.
            Check.isFalse(store.pop(note), "a pop that finds nothing reports it")
            Check.isFalse(store.canUndo, "and records nothing to undo")
            Check.isFalse(store.pop(UUID()), "nor does popping a note that never existed")

            store.selectWorkspace(at: 0)
            Check.isTrue(store.pop(note), "back on its board, it pops")
            Check.isTrue(store.canUndo, "and that is undoable")
        }

        Check.suite("Workspaces — cached tallies follow every change") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            let home = store.currentWorkspaceID
            named(store, ["one", "two"])
            Check.equal(store.everywhere.total, 2, "a first read counts")
            named(store, ["three"])
            Check.equal(store.everywhere.total, 3, "adding a note is seen, not a stale count")

            let work = store.addWorkspace(named: "Work")
            store.renamingWorkspaceID = nil
            store.selectWorkspace(home)
            let one = store.visible[0].id
            store.move(one, toWorkspace: work)
            let workBoard = store.workspaces.first { $0.id == work }!
            Check.equal(store.tally(of: workBoard).total, 1, "filing moves the count to the board it lands on")
            Check.equal(store.stageCounts.total, 2, "and away from the board it left")

            store.pop(store.visible[0].id)
            Check.equal(store.everywhere.total, 2, "popping is seen")
            store.undo()
            Check.equal(store.everywhere.total, 3, "and so is undoing it")

            Check.equal(store.everywhere.overdue, 0, "nothing is overdue yet")
            store.advanceClock(to: store.now.addingTimeInterval(8 * 86_400))
            Check.equal(store.everywhere.overdue, 3, "the clock moving is seen too")
        }

        Check.suite("Workspaces — each board ages at its own pace") {
            let fortnight = AgeWindow(overdueAfterDays: 14)
            Check.equal(fortnight.stage(forDays: 5), .fresh, "on a two-week board, five days is still fresh")
            Check.equal(fortnight.stage(forDays: 6), .aging, "six days is ageing — the week's proportions, stretched")
            Check.equal(fortnight.stage(forDays: 13.9), .aging, "still ageing just short of a fortnight")
            Check.equal(fortnight.stage(forDays: 14), .overdue, "and overdue at fourteen days")
            Check.equal(AgeWindow.standard.stage(forDays: 7), Aging.stage(forDays: 7), "the standard window is the old week")
            Check.equal(AgeWindow.presets.map(\.label), ["3 days", "1 week", "2 weeks", "1 month", "3 months"],
                        "the menu offers these")

            let url = tempURL()
            defer { try? FileManager.default.removeItem(at: url) }
            let store = BubbleStore(fileURL: url)
            let tenDaysAgo = store.now.addingTimeInterval(-10 * 86_400)
            store.replaceAll(with: [BubbleNode(text: "slow project", createdAt: tenDaysAgo)])
            let slow = store.currentWorkspaceID
            Check.equal(store.stageCounts.overdue, 1, "ten days is overdue on a standard board")

            store.setAgeWindow(AgeWindow(overdueAfterDays: 30), for: slow)
            Check.equal(store.stageCounts.overdue, 0, "but not on a board given a month")
            Check.equal(store.stageCounts.fresh, 1, "where it is still fresh")
            Check.equal(store.everywhere.overdue, 0, "and the pill and menu bar agree")

            store.saveNow()
            let reloaded = BubbleStore(fileURL: url)
            Check.equal(reloaded.currentWorkspace.window, AgeWindow(overdueAfterDays: 30), "a board's window is saved")

            store.setAgeWindow(.standard, for: slow)
            Check.nil_(store.currentWorkspace.overdueAfterDays, "the standard week is stored as no setting at all")
            Check.equal(store.stageCounts.overdue, 1, "and the note is overdue again")
        }

        Check.suite("Workspaces — deleting") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            store.renameWorkspace(store.currentWorkspaceID, to: "Home")
            named(store, ["home note"])
            let work = store.addWorkspace(named: "Work")
            store.renamingWorkspaceID = nil
            named(store, ["work note", "another"])

            store.removeWorkspace(work)
            Check.equal(store.workspaces.count, 1, "the board is gone")
            Check.equal(store.currentWorkspace.name, "Home", "and you land on the one that's left")
            Check.equal(store.visible.map(\.text), ["home note"], "which is untouched")

            Check.isTrue(store.canUndo, "deleting a board is undoable")
            Check.equal(store.undoLabel, "Work", "labelled with the board that went")
            store.undo()
            Check.equal(store.workspaces.count, 2, "undo brings the board back")
            Check.equal(store.currentWorkspace.name, "Work", "and returns you to it")
            Check.equal(store.visible.map(\.text), ["work note", "another"], "with everything on it")

            // Deleting a board *before* the current one must not change which board
            // you are looking at, only where it sits.
            store.selectWorkspace(at: 1)
            store.removeWorkspace(store.workspaces[0].id)
            Check.equal(store.currentWorkspace.name, "Work", "you stay on the board you were on")
            Check.equal(store.currentIndex, 0, "even though it has shuffled down the shelf")

            store.removeWorkspace(store.currentWorkspaceID)
            Check.equal(store.workspaces.count, 1, "the last board cannot be deleted")
            Check.equal(store.currentWorkspace.name, "Work", "and is left exactly as it was")
        }

        Check.suite("Workspaces — persistence") {
            let url = tempURL()
            defer { try? FileManager.default.removeItem(at: url) }

            let store = BubbleStore(fileURL: url)
            store.renameWorkspace(store.currentWorkspaceID, to: "Home")
            named(store, ["home note"])
            store.addWorkspace(named: "Work")
            store.renamingWorkspaceID = nil
            named(store, ["work note"])
            store.saveNow()

            let reloaded = BubbleStore(fileURL: url)
            Check.equal(reloaded.workspaces.map(\.name), ["Home", "Work"],
                        "both boards survive a reload, in order")
            Check.equal(reloaded.currentWorkspace.name, "Work", "reopening on the board you left")
            Check.equal(reloaded.visible.map(\.text), ["work note"], "showing its own notes")
            reloaded.selectWorkspace(at: 0)
            Check.equal(reloaded.visible.map(\.text), ["home note"], "and the other board's are intact")

            // A file that has lost its workspaces, or never had any, still opens.
            let empty = tempURL()
            defer { try? FileManager.default.removeItem(at: empty) }
            try? Data("{\"version\": 2, \"workspaces\": []}".utf8).write(to: empty)
            let recovered = BubbleStore(fileURL: empty)
            Check.equal(recovered.workspaces.count, 1, "there is always at least one board")
            Check.isTrue(recovered.visible.isEmpty, "an empty one")
        }

        Check.suite("Workspaces — counting inside the panel and outside it") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            let old = Date().addingTimeInterval(-10 * 86_400)
            store.replaceAll(with: [BubbleNode(text: "home fresh"),
                                    BubbleNode(text: "home rotting", createdAt: old)])
            store.addWorkspace(named: "Work")
            store.renamingWorkspaceID = nil
            var buried = BubbleNode(text: "work parent", createdAt: old)
            buried.children = [BubbleNode(text: "work child", createdAt: old)]
            store.replaceAll(with: [buried])

            // Inside the panel, a count describes the board in front of you.
            Check.equal(store.stageCounts.overdue, 2, "the bar counts this board, nesting and all")
            Check.equal(store.stageCounts.fresh, 0, "and only this board")

            // Outside it — the resting pill, the menu bar icon — there is no board in
            // front of you, so the count has to cover the lot. A note rotting on a
            // board you haven't opened in a fortnight is exactly what it is for.
            Check.equal(store.everywhere.total, 4, "every bubble in the app, at any depth")
            Check.equal(store.everywhere.overdue, 3, "and every overdue one, on any board")

            store.selectWorkspace(at: 0)
            Check.equal(store.everywhere.overdue, 3,
                        "which board is selected makes no difference to it")
            Check.equal(store.stageCounts.overdue, 1, "while the bar's count follows the board")
        }

        Check.suite("Workspaces — the bar's second row") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            Check.isFalse(store.showsPlaceRow,
                          "one board at the top level needs no place row — nothing to say")

            named(store, ["parent"])
            store.drillInto(store.visible[0].id)
            Check.isTrue(store.showsPlaceRow, "drilling in brings it back for the breadcrumb")

            store.goUp()
            store.addWorkspace(named: "second")
            Check.isTrue(store.showsPlaceRow, "and a second board earns it at the top level too")
        }
    }
}
