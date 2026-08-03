import NoteBubbleCore

// Top-level code rather than `@main` so the activation policy is set before any
// window exists. This runs on the main thread, which `assumeIsolated` makes
// explicit to the compiler.
MainActor.assumeIsolated {
    NoteBubbleApp.launch()
}
