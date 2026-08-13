import Foundation
@testable import NoteBubbleCore

@MainActor
enum BubbleStoreTests {
    /// Each case gets its own throwaway file so persistence is exercised for real
    /// without any case seeing another's notes.
    private static func makeStore() -> (BubbleStore, URL) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notebubble-test-\(UUID().uuidString).json")
        return (BubbleStore(fileURL: url), url)
    }

    private static func named(_ store: BubbleStore, _ texts: [String]) {
        for text in texts {
            let id = store.addBubble()
            store.updateText(text, for: id)
        }
        store.editingID = nil
    }

    static func run() {
        Check.suite("BubbleStore — editing") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            let id = store.addBubble()
            Check.equal(store.visible.count, 1, "adding a bubble shows it at the current level")
            Check.equal(store.editingID, id, "a new bubble opens straight into edit mode")

            store.updateText("one", for: id)
            let second = store.addBubble()
            store.updateText("two", for: second)
            store.updateText("edited", for: id)
            Check.equal(store.visible.first(where: { $0.id == id })?.text, "edited",
                        "updateText applies to the right node")
        }

        Check.suite("BubbleStore — navigation") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            let parent = store.addBubble()
            store.updateText("parent", for: parent)
            store.drillInto(parent)
            Check.equal(store.path, [parent], "drilling in extends the path")
            Check.equal(store.breadcrumb, ["parent"], "the breadcrumb names the level")

            let child = store.addBubble()
            store.updateText("child", for: child)
            Check.equal(store.visible.map(\.text), ["child"], "the nested level shows its own notes")

            store.goUp()
            Check.isTrue(store.isAtRoot, "going up returns to the root")
            Check.equal(store.visible.first?.children.map(\.text), ["child"],
                        "the child stayed inside its parent")

            let blank = store.addBubble() // never typed into
            store.drillInto(blank)
            Check.isTrue(store.isAtRoot, "a blank bubble is discarded rather than entered")
        }

        Check.suite("BubbleStore — depth") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            let a = store.addBubble()
            store.updateText("a", for: a)
            store.drillInto(a)
            let b = store.addBubble()
            store.updateText("b", for: b)
            store.drillInto(b)
            Check.equal(store.path.count, 2, "two levels deep")

            store.goToDepth(1)
            Check.equal(store.path, [a], "goToDepth truncates the path")
            store.goToDepth(0)
            Check.isTrue(store.isAtRoot, "depth zero is the root")
        }

        Check.suite("BubbleStore — popping") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            let parent = store.addBubble()
            store.updateText("parent", for: parent)
            store.drillInto(parent)
            let child = store.addBubble()
            store.updateText("child", for: child)
            store.goUp()

            store.pop(parent)
            Check.isTrue(store.visible.isEmpty, "popping removes the note")
            Check.isTrue(store.root.flattened.isEmpty, "popping takes its children with it")

            store.addBubble()
            Check.equal(store.visible.count, 1, "a blank bubble exists while being typed into")
            store.editingID = nil
            Check.isTrue(store.visible.isEmpty, "a blank bubble is discarded when focus moves away")

            let real = store.addBubble()
            store.updateText("real note", for: real)
            store.editingID = nil
            Check.equal(store.visible.count, 1, "a written bubble survives losing focus")
        }

        Check.suite("BubbleStore — popping a parent from anywhere") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            // The bug this guards: a hold-to-pop and the release that follows could
            // both fire, drilling into the bubble *and* raising the confirmation.
            // Confirming then popped nothing, because removal only searched the
            // level the user was currently standing on.
            named(store, ["parent"])
            let parent = store.visible[0].id
            store.drillInto(parent)
            named(store, ["child a", "child b"])
            store.goUp()

            store.drillInto(parent) // the stray navigation
            Check.equal(store.path, [parent], "standing inside the doomed bubble")

            store.pop(parent)
            Check.isTrue(store.root.isEmpty, "the parent pops even from inside it")
            Check.isTrue(store.path.isEmpty, "popping the level you are in backs you out")

            store.undo()
            Check.equal(store.root.count, 1, "the parent comes back")
            Check.equal(store.root.node(withID: parent)?.children.count, 2,
                        "both children come back with it")
        }

        Check.suite("BubbleStore — deep removal") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            named(store, ["a"])
            let a = store.visible[0].id
            store.drillInto(a)
            named(store, ["b"])
            let b = store.visible[0].id
            store.drillInto(b)
            named(store, ["c"])
            let c = store.visible[0].id
            store.goToDepth(0)

            // Popping a grandchild while standing at the root.
            store.pop(c)
            Check.nil_(store.root.node(withID: c), "a deeply nested note pops from the root")
            Check.equal(store.root.node(withID: b)?.children.count, 0, "its parent survives")
            Check.equal(store.path, [], "an unrelated pop leaves the path alone")

            store.pop(UUID())
            Check.equal(store.root.flattened.count, 2, "popping an unknown id changes nothing")
        }

        Check.suite("BubbleStore — shuffle") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            named(store, ["a", "b", "c", "d", "e", "f"])
            let before = store.visible.map(\.text)

            // Seeded so the outcome is the same on every run.
            var generator = SeededGenerator(seed: 42)
            store.shuffle(using: &generator)
            let after = store.visible.map(\.text)

            Check.equal(Set(after), Set(before), "shuffling keeps exactly the same notes")
            Check.equal(after.count, before.count, "and the same number of them")
            Check.notEqual(after, before, "but not in the same order")

            store.undo()
            Check.equal(store.visible.map(\.text), before, "undo restores the original arrangement")

            // A single bubble has no arrangement to lose, so this must not burn an
            // undo step on a no-op.
            let (single, singleURL) = makeStore()
            defer { try? FileManager.default.removeItem(at: singleURL) }
            named(single, ["only"])
            single.shuffle(using: &generator)
            Check.isFalse(single.canUndo, "shuffling one bubble is not undoable")
            Check.equal(single.visible.map(\.text), ["only"], "and changes nothing")

            // Two bubbles must actually swap rather than landing back as they were.
            let (pair, pairURL) = makeStore()
            defer { try? FileManager.default.removeItem(at: pairURL) }
            named(pair, ["x", "y"])
            var identity = SeededGenerator(seed: 1)
            pair.shuffle(using: &identity)
            Check.notEqual(pair.visible.map(\.text), ["x", "y"], "a shuffle always changes something")

            // Nested levels shuffle independently of the root.
            let (nested, nestedURL) = makeStore()
            defer { try? FileManager.default.removeItem(at: nestedURL) }
            named(nested, ["parent"])
            let parent = nested.visible[0].id
            nested.drillInto(parent)
            named(nested, ["one", "two", "three"])
            nested.shuffle(using: &generator)
            Check.equal(Set(nested.visible.map(\.text)), ["one", "two", "three"],
                        "shuffling inside a bubble keeps its own children")
            nested.goUp()
            Check.equal(nested.visible.map(\.text), ["parent"], "and leaves the level above alone")
        }

        Check.suite("BubbleStore — undo") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            Check.isFalse(store.canUndo, "nothing to undo on a fresh store")

            named(store, ["keep", "doomed"])
            let doomed = store.visible[1].id
            store.pop(doomed)
            Check.equal(store.visible.map(\.text), ["keep"], "the note is gone")
            Check.isTrue(store.canUndo, "popping is undoable")
            Check.equal(store.undoLabel, "doomed", "undo is labelled with the popped note")

            store.undo()
            Check.equal(store.visible.map(\.text), ["keep", "doomed"], "undo restores the note")
            Check.isFalse(store.canUndo, "the stack is empty again")

            // Children must come back too — popping a parent takes the whole subtree.
            let parent = store.visible[0].id
            store.drillInto(parent)
            named(store, ["inner"])
            store.goUp()
            store.pop(parent)
            Check.isTrue(store.root.flattened.filter { $0.text == "inner" }.isEmpty,
                         "popping a parent takes its children")
            store.undo()
            Check.equal(store.root.node(withID: parent)?.children.map(\.text), ["inner"],
                        "undo restores the children as well")

            // Undo from inside a level the pop happened at should land you back there.
            let outer = store.visible[0].id
            store.drillInto(outer)
            let inner = store.visible[0].id
            store.pop(inner)
            Check.isTrue(store.visible.isEmpty, "the nested note is gone")
            store.undo()
            Check.equal(store.path, [outer], "undo returns to the level the pop happened at")
            Check.equal(store.visible.map(\.text), ["inner"], "the nested note is back")

            // Blank throwaway notes must not occupy the undo stack.
            let (fresh, freshURL) = makeStore()
            defer { try? FileManager.default.removeItem(at: freshURL) }
            fresh.addBubble()
            fresh.editingID = nil
            Check.isFalse(fresh.canUndo, "discarding a never-written note is not undoable")
        }

        Check.suite("BubbleStore — reordering") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            named(store, ["a", "b", "c", "d"])
            store.move(store.visible[0].id, to: 2)
            Check.equal(store.visible.map(\.text), ["b", "c", "a", "d"], "move reorders the level")

            store.move(store.visible[0].id, to: 99)
            Check.equal(store.visible.map(\.text), ["c", "a", "d", "b"], "a destination past the end clamps")

            let before = store.visible.map(\.text)
            store.move(UUID(), to: 0)
            Check.equal(store.visible.map(\.text), before, "moving an unknown id is a no-op")
        }

        Check.suite("BubbleStore — ageing and persistence") {
            let (store, url) = makeStore()
            defer { try? FileManager.default.removeItem(at: url) }

            let old = Date().addingTimeInterval(-10 * 86_400)
            var buried = BubbleNode(text: "buried", createdAt: old)
            buried.children = [BubbleNode(text: "deep", createdAt: old)]
            store.replaceAll(with: [buried, BubbleNode(text: "fresh")])
            Check.equal(store.stageCounts.overdue, 2, "the overdue count spans the whole tree")

            store.touch(buried.id)
            Check.equal(store.stageCounts.overdue, 1, "touching a note resets its clock")

            store.saveNow()
            let reloaded = BubbleStore(fileURL: url)
            Check.equal(reloaded.root.flattened.count, 3, "notes survive a reload")
            Check.equal(reloaded.visible.map(\.text), ["buried", "fresh"], "order survives a reload")

            let missing = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("absent-\(UUID().uuidString).json")
            Check.isTrue(BubbleStore(fileURL: missing).root.isEmpty, "a missing file loads empty")
        }
    }
}
