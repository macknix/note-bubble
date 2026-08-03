import Foundation
@testable import NoteBubbleCore

enum GridLayoutTests {
    // 432pt panel, 12pt padding, 10pt gaps → 408pt usable, four ~94.5pt columns.
    private static let layout = GridLayout(availableWidth: 432)

    private static func spec(_ height: CGFloat, span: Int = 1) -> GridLayout.TileSpec {
        GridLayout.TileSpec(
            size: CGSize(width: layout.width(spanning: span), height: height),
            span: span
        )
    }

    static func run() {
        Check.suite("GridLayout — columns") {
            Check.equal(layout.columns, 4, "the 432pt panel fits four columns")
            Check.close(layout.contentWidth, 408, "usable width is the panel less padding")
            Check.close(layout.columnWidth, 94.5, "columns divide the usable width evenly")
            Check.close(layout.width(spanning: 2), 199, "a two-column tile swallows the gap between")
            Check.equal(GridLayout(availableWidth: 10).columns, 1, "a narrow panel still shows one column")
            Check.equal(GridLayout(availableWidth: 0).columns, 1, "zero width never yields zero columns")
            Check.close(layout.width(spanning: 99), layout.contentWidth,
                        "a span wider than the grid is clamped to it")
        }

        Check.suite("GridLayout — masonry placement") {
            // Four equal tiles fill the four columns, all at the top.
            let row = layout.frames(for: (0..<4).map { _ in spec(80) })
            Check.equal(Set(row.map(\.minY)), [12], "the first four tiles share the top edge")
            Check.close(row[0].minX, 12, "first column starts after the padding")
            Check.close(row[1].minX, 116.5, "columns are spaced by the gap")

            // The fifth tile drops under column 0 — the shortest at that point.
            let five = layout.frames(for: (0..<5).map { _ in spec(80) })
            Check.close(five[4].minX, 12, "the fifth tile returns to the first column")
            Check.close(five[4].minY, 102, "and sits directly under the tile above it")

            // This is the tessellation: a short tile fills in beside a tall one
            // rather than waiting for the whole row to clear.
            let mixed = layout.frames(for: [spec(200), spec(64), spec(64), spec(64), spec(64)])
            Check.close(mixed[4].minY, 86, "a short tile stacks under its neighbour, not under the tallest")
            Check.isTrue(mixed[4].minY < mixed[0].maxY,
                         "and starts before the tall tile has finished")
        }

        Check.suite("GridLayout — wide tiles") {
            // A two-column tile has to clear both columns it covers.
            let frames = layout.frames(for: [spec(120), spec(64), spec(80, span: 2)])
            Check.close(frames[2].width, 199, "the wide tile spans two columns")
            Check.close(frames[2].minX, 221, "and takes the two shortest adjacent columns")
            Check.close(frames[2].minY, 12, "which were both still empty")

            // With every column occupied it must sit below the taller of its pair.
            let stacked = layout.frames(for: [spec(120), spec(64), spec(64), spec(64), spec(60, span: 2)])
            Check.close(stacked[4].minY, 86, "a wide tile clears the lower of the two columns it covers")
        }

        Check.suite("GridLayout — no overlaps") {
            // The guarantee that makes packing safe, over awkward mixed sizes.
            let specs: [GridLayout.TileSpec] = [
                spec(64), spec(216, span: 2), spec(88), spec(72), spec(120, span: 2),
                spec(64), spec(96), spec(80), spec(112), spec(64), spec(104, span: 2), spec(72)
            ]
            let frames = layout.frames(for: specs)

            var overlapping = false
            for a in 0..<frames.count {
                for b in (a + 1)..<frames.count where frames[a].intersects(frames[b]) {
                    overlapping = true
                }
            }
            Check.isFalse(overlapping, "no two tiles ever overlap")

            var withinBounds = true
            for frame in frames where frame.minX < 11.9 || frame.maxX > 420.1 {
                withinBounds = false
            }
            Check.isTrue(withinBounds, "every tile stays inside the padding")

            Check.isTrue(layout.contentHeight(for: specs) >= frames.map(\.maxY).max()!,
                         "content height covers the lowest tile")
            Check.close(layout.contentHeight(for: []), 0, "nothing to show needs no height")
        }

        Check.suite("GridLayout — drop targets") {
            let specs = [spec(120), spec(64), spec(96), spec(64), spec(80)]
            let frames = layout.frames(for: specs)

            for index in frames.indices {
                let centre = CGPoint(x: frames[index].midX, y: frames[index].midY)
                Check.equal(layout.index(at: centre, frames: frames), index,
                            "a tile's own centre maps back to itself")
            }

            Check.equal(layout.index(at: CGPoint(x: -900, y: -900), frames: frames), 0,
                        "far above and left targets the first tile")
            Check.equal(layout.index(at: CGPoint(x: 200, y: 5_000), frames: frames), 4,
                        "below everything appends rather than picking the nearest centre")
            Check.equal(layout.index(at: CGPoint(x: 50, y: 50), frames: []), 0,
                        "an empty grid has no slot to land on")
        }
    }
}

/// Tile sizing decides how big a note wants to be, and when it earns a second column.
enum TileSizingTests {
    private static let layout = GridLayout(availableWidth: 432)
    private static let words = "The quick brown fox jumps over the lazy dog and keeps on running "

    private static func node(_ text: String) -> BubbleNode { BubbleNode(text: text) }
    private static func text(_ repeats: Int) -> String { String(repeating: words, count: repeats) }

    static func run() {
        Check.suite("Tile sizing") {
            let empty = layout.spec(for: node(""))
            let short = layout.spec(for: node("Dentist"))
            let medium = layout.spec(for: node(text(1)))
            let huge = layout.spec(for: node(text(200)))

            Check.close(empty.size.height, GridLayout.minimumHeight, "an empty note sits at the minimum height")
            Check.equal(empty.span, 1, "and takes a single column")
            Check.close(short.size.height, GridLayout.minimumHeight, "a short note still fits the minimum")
            Check.isTrue(medium.size.height > short.size.height, "a sentence needs a taller tile")

            Check.equal(huge.span, 2, "a note that would tower spreads across two columns instead")
            Check.close(huge.size.width, layout.width(spanning: 2), "and is two columns wide")
            Check.isTrue(huge.size.height <= GridLayout.maximumHeight, "height is capped")

            var monotonic = true
            var previous: CGFloat = 0
            for count in 0...10 {
                let spec = layout.spec(for: node(text(count)))
                // Area, since growth can go sideways as well as down.
                let area = spec.size.width * spec.size.height
                if area < previous - 1 { monotonic = false }
                previous = area
            }
            Check.isTrue(monotonic, "a longer note never gets a smaller tile")

            Check.equal(medium.size.height.truncatingRemainder(dividingBy: GridLayout.heightStep), 0,
                        "heights land on the step lattice")
            Check.isTrue(layout.spec(for: node(text(3))).size.height <= GridLayout.maximumHeight,
                         "no tile exceeds the maximum height")
        }

        Check.suite("Tile text fitting") {
            // The promise sizing makes: at the size chosen, the text fits.
            for count in 0...5 {
                let label = text(count).isEmpty ? "Untitled" : text(count)
                let spec = layout.spec(for: node(text(count)))
                if spec.size.height < GridLayout.maximumHeight {
                    let available = spec.size.height - TileText.verticalChrome
                    let needed = TileText.height(of: label, boundedBy: spec.size.width - TileText.horizontalInset * 2)
                    Check.isTrue(needed <= available,
                                 "text of \(label.count) chars fits the tile it was given")
                }
            }

            Check.equal(TileText.height(of: "", boundedBy: 100), 0, "empty text has no height")
            Check.isTrue(TileText.height(of: "a longer line of words", boundedBy: 40)
                         > TileText.height(of: "a longer line of words", boundedBy: 200),
                         "narrower wrapping is taller")
        }
    }
}

enum ReorderTests {
    private static let items = ["a", "b", "c", "d"]

    static func run() {
        Check.suite("Reordering") {
            Check.equal(items.reordered(moving: "a", to: 2), ["b", "c", "a", "d"], "move forwards")
            Check.equal(items.reordered(moving: "d", to: 0), ["d", "a", "b", "c"], "move backwards")
            Check.equal(items.reordered(moving: "b", to: 1), items, "moving to its own slot changes nothing")
            Check.equal(items.reordered(moving: "a", to: 99), ["b", "c", "d", "a"], "past the end clamps to last")
            Check.equal(items.reordered(moving: "a", to: -5), ["a", "b", "c", "d"], "before the start clamps to first")
            Check.equal(items.reordered(moving: "z", to: 0), items, "an unknown element leaves the order alone")
        }
    }
}
