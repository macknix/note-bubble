import Foundation

// Run with `swift run NoteBubbleTests`. Exits non-zero if anything failed.
MainActor.assumeIsolated {
    GridLayoutTests.run()
    TileSizingTests.run()
    ReorderTests.run()
    BubbleTreeTests.run()
    AgingTests.run()
    BubbleStoreTests.run()
    PanelPlacementTests.run()
    TileGestureTests.run()
    WorkspaceTests.run()
    WorkspaceSwipeTests.run()
    TileFlightTests.run()
    exit(Check.summary())
}
