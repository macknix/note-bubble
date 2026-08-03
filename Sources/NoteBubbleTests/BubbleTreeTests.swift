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
    }
}
