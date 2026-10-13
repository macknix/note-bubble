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
    PanelStateTests.run()
    PanelShortcutTests.run()
    HoverIntentTests.run()
    PreviewDwellTests.run()
    LayoutPlanTests.run()
    DemoDataTests.run()
    KeyComboTests.run()
    ShakeDetectorTests.run()
    exit(Check.summary())
}
