import Foundation
@testable import NoteBubbleCore

/// Covers the recursive path-walking helper that every store mutation funnels through.
enum BubbleTreeTests {
    private static func makeTree() -> [BubbleNode] {
        var child = BubbleNode(text: "child")
        child.children = [BubbleNode(text: "grandchild")]
        var parent = BubbleNode(text: "parent")
        parent.children = [child]
        return [parent, BubbleNode(text: "sibling")]
    }

    static func run() {
        Check.suite("Bubble tree") {
            var tree = makeTree()
            tree.mutateChildren(at: [][...]) { $0.append(BubbleNode(text: "new")) }
            Check.equal(tree.count, 3, "an empty path mutates the root level")
            Check.equal(tree.last?.text, "new", "the appended node lands at the root")

            var nested = makeTree()
            let deepPath = [nested[0].id, nested[0].children[0].id]
            nested.mutateChildren(at: deepPath[...]) { $0.append(BubbleNode(text: "deep")) }
            Check.equal(nested[0].children[0].children.map(\.text), ["grandchild", "deep"],
                        "mutation reaches a nested level")

            var untouched = makeTree()
            let before = untouched
            untouched.mutateChildren(at: [UUID()][...]) { $0.removeAll() }
            Check.equal(untouched, before, "an unknown path is a no-op")

            let tree2 = makeTree()
            Check.equal(tree2.children(at: [][...]).count, 2, "root level has two nodes")
            Check.equal(tree2.children(at: [tree2[0].id][...]).map(\.text), ["child"],
                        "children(at:) descends one level")
            Check.isTrue(tree2.children(at: [UUID()][...]).isEmpty, "an unknown path has no children")

            Check.equal(Set(tree2.flattened.map(\.text)),
                        ["parent", "child", "grandchild", "sibling"],
                        "flattened includes every depth")

            Check.equal(tree2[0].descendantCount, 2, "descendants are counted at all depths")
            Check.equal(tree2[1].descendantCount, 0, "a leaf has no descendants")

            let deepID = tree2[0].children[0].children[0].id
            Check.equal(tree2.node(withID: deepID)?.text, "grandchild", "lookup searches recursively")
            Check.nil_(tree2.node(withID: UUID()), "lookup of a missing id returns nil")

            var removable = makeTree()
            Check.isTrue(removable.removeNode(withID: removable[1].id), "removes a root-level node")
            Check.equal(removable.map(\.text), ["parent"], "the sibling is gone")

            var deep = makeTree()
            let grandchild = deep[0].children[0].children[0].id
            Check.isTrue(deep.removeNode(withID: grandchild), "removes a nested node")
            Check.isTrue(deep[0].children[0].children.isEmpty, "the grandchild is gone")
            Check.equal(deep.flattened.count, 3, "nothing else was disturbed")

            var subtree = makeTree()
            subtree.removeNode(withID: subtree[0].children[0].id)
            Check.equal(Set(subtree.flattened.map(\.text)), ["parent", "sibling"],
                        "removing a node takes its descendants with it")

            var missing = makeTree()
            Check.isFalse(missing.removeNode(withID: UUID()), "reports when there was nothing to remove")
            Check.equal(missing.flattened.count, 4, "and changes nothing")
        }

        Check.suite("Stage tallies") {
            let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
            func note(_ text: String, daysOld: Double, _ children: [BubbleNode] = []) -> BubbleNode {
                BubbleNode(text: text, createdAt: now.addingTimeInterval(-daysOld * 86_400), children: children)
            }
            let tree = [
                note("fresh", daysOld: 1, [note("ageing child", daysOld: 4, [note("overdue grandchild", daysOld: 9)])]),
                note("also fresh", daysOld: 0)
            ]

            let tally = StageTally(of: tree, at: now)
            Check.equal(tally, StageTally(fresh: 2, aging: 1, overdue: 1), "every depth is counted, once")
            Check.equal(tally.total, 4, "the total is the sum")
            Check.equal(tally.worst, .overdue, "the worst stage is overdue if anything is")
            Check.equal(StageTally(of: [note("a", daysOld: 4), note("b", daysOld: 0)], at: now).worst, .aging,
                        "ageing when nothing is overdue")
            Check.nil_(StageTally(of: [], at: now).worst, "and nothing for an empty board")
            Check.equal(tally + tally, StageTally(fresh: 4, aging: 2, overdue: 2), "tallies add up across boards")

            var visited = 0
            tree.forEachNode { _ in visited += 1 }
            Check.equal(visited, tree.flattened.count, "forEachNode visits what flattened would hold")
        }
    }
}