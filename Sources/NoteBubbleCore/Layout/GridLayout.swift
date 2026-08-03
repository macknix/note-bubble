import CoreGraphics

/// Packs tiles of differing sizes so they tessellate.
///
/// Two decisions carry this:
///
/// 1. **Tiles are rectangles, not squares.** A note's text wants a width and needs
///    whatever height follows from it. Forcing squares meant the tall ones
///    overflowed their frames while the layout still reserved a square, which is
///    what left dead space everywhere.
/// 2. **Placement is masonry, not rows.** Rows of variable-height tiles leave a gap
///    under every short one. Masonry drops each tile into the column that is
///    currently shortest, so small tiles fill in beside tall ones.
///
/// Widths snap to whole columns — one column, or two for a wordy note — which is
/// what keeps the result reading as a tidy grid rather than a scrapbook.
struct GridLayout: Equatable {
    let width: CGFloat
    let spacing: CGFloat
    let padding: CGFloat
    let columns: Int

    /// Target width for one column. Actual columns divide the space evenly.
    static let preferredColumnWidth: CGFloat = 94

    /// Height bounds. A tile is never a sliver, never taller than a screenful, and
    /// a single-column tile taller than `wideThreshold` is better off two columns
    /// wide — that is what stops wordy notes becoming unreadable ribbons.
    static let minimumHeight: CGFloat = 64
    static let maximumHeight: CGFloat = 216
    static let wideThreshold: CGFloat = 148
    /// Heights land on whole steps so tiles settle rather than twitching per keystroke.
    static let heightStep: CGFloat = 8

    init(availableWidth: CGFloat, spacing: CGFloat = 10, padding: CGFloat = 12) {
        self.width = availableWidth
        self.spacing = spacing
        self.padding = padding

        let usable = max(availableWidth - padding * 2, Self.preferredColumnWidth)
        self.columns = max(1, Int(((usable + spacing) / (Self.preferredColumnWidth + spacing)).rounded(.down)))
    }

    var contentWidth: CGFloat {
        max(width - padding * 2, Self.preferredColumnWidth)
    }

    /// Width of a single column, with the gaps between columns removed.
    var columnWidth: CGFloat {
        (contentWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    /// Width of a tile spanning `count` columns, including the gaps it swallows.
    func width(spanning count: Int) -> CGFloat {
        let span = min(max(count, 1), columns)
        return columnWidth * CGFloat(span) + spacing * CGFloat(span - 1)
    }

    // MARK: - Tile sizing

    /// How big one note wants to be.
    struct TileSpec: Equatable {
        let size: CGSize
        /// Columns spanned — 1 or 2.
        let span: Int
    }

    /// Chooses a width in whole columns, then takes whatever height the text needs.
    func spec(for node: BubbleNode) -> TileSpec {
        let label = node.displayName

        let narrow = width(spanning: 1)
        let narrowHeight = height(of: label, inWidth: narrow)

        // A note that would tower in one column reads better spread across two.
        if narrowHeight <= Self.wideThreshold || columns < 2 {
            return TileSpec(size: CGSize(width: narrow, height: narrowHeight), span: 1)
        }

        let wide = width(spanning: 2)
        return TileSpec(size: CGSize(width: wide, height: height(of: label, inWidth: wide)), span: 2)
    }

    /// Height a tile of `tileWidth` needs to show `label` in full, clamped and
    /// snapped to the step.
    func height(of label: String, inWidth tileWidth: CGFloat) -> CGFloat {
        let needed = TileText.height(of: label, boundedBy: tileWidth - TileText.horizontalInset * 2)
            + TileText.verticalChrome
        let stepped = (needed / Self.heightStep).rounded(.up) * Self.heightStep
        return min(max(stepped, Self.minimumHeight), Self.maximumHeight)
    }

    // MARK: - Packing

    /// Frames for the given tiles, in order, packed by shortest column.
    func frames(for specs: [TileSpec]) -> [CGRect] {
        guard !specs.isEmpty else { return [] }

        // Current bottom edge of each column.
        var bottoms = [CGFloat](repeating: padding, count: columns)
        var result: [CGRect] = []
        result.reserveCapacity(specs.count)

        for spec in specs {
            let span = min(spec.span, columns)
            let start = shortestSlot(spanning: span, in: bottoms)
            // A tile spanning two columns must clear whichever of them is lower.
            let top = (start..<(start + span)).map { bottoms[$0] }.max() ?? padding

            result.append(
                CGRect(
                    x: padding + CGFloat(start) * (columnWidth + spacing),
                    y: top,
                    width: spec.size.width,
                    height: spec.size.height
                )
            )

            for column in start..<(start + span) {
                bottoms[column] = top + spec.size.height + spacing
            }
        }
        return result
    }

    /// Leftmost starting column whose span sits highest. Ties go left, which keeps
    /// the reading order as close to the model's order as packing allows.
    private func shortestSlot(spanning span: Int, in bottoms: [CGFloat]) -> Int {
        guard span < columns else { return 0 }
        var best = 0
        var bestTop = CGFloat.greatestFiniteMagnitude

        for start in 0...(columns - span) {
            let top = (start..<(start + span)).map { bottoms[$0] }.max() ?? 0
            if top < bestTop - 0.5 {
                bestTop = top
                best = start
            }
        }
        return best
    }

    /// Height needed to show every tile, for sizing the panel and its scroll view.
    func contentHeight(for specs: [TileSpec]) -> CGFloat {
        guard let lowest = frames(for: specs).map(\.maxY).max() else { return 0 }
        return lowest + padding
    }

    /// The slot a tile dropped at `point` should take, chosen by nearest centre.
    ///
    /// Hit-testing uses the *undisturbed* frames: testing against tiles that are
    /// themselves reflowing makes the drop target oscillate under the cursor.
    func index(at point: CGPoint, frames: [CGRect]) -> Int {
        guard !frames.isEmpty else { return 0 }

        // Dropped below everything means "put it at the end" — nearest-centre would
        // otherwise pick whichever tile happens to sit lowest on screen.
        if let bottom = frames.map(\.maxY).max(), point.y > bottom {
            return frames.count - 1
        }

        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, frame) in frames.enumerated() {
            let dx = frame.midX - point.x
            let dy = frame.midY - point.y
            let distance = dx * dx + dy * dy // squared: ordering is all that matters
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }
}

// MARK: - Reordering

extension Array where Element: Equatable {
    /// The order this array would have if `element` were lifted out and dropped
    /// back in at `destination` — the live reflow shown while a tile is dragged.
    func reordered(moving element: Element, to destination: Int) -> [Element] {
        guard let from = firstIndex(of: element) else { return self }
        var result = self
        result.remove(at: from)
        let clamped = Swift.min(Swift.max(destination, 0), result.count)
        result.insert(element, at: clamped)
        return result
    }
}
