import Foundation

/// A minimal assertion harness.
///
/// This exists because XCTest and swift-testing both ship with Xcode, and this
/// project deliberately builds with Command Line Tools alone — so `swift test`
/// is not available. The suite is an ordinary executable instead: `swift run
/// NoteBubbleTests`, non-zero exit on failure, which is all CI or a pre-commit
/// check actually needs.
/// Reproducible randomness, so a shuffle test asserts the same thing every run.
/// A plain linear congruential generator — quality is irrelevant here, determinism
/// is the whole point.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Zero is a fixed point for this recurrence; anything else is fine.
        state = seed == 0 ? 0x4d59_5df4_d0f3_3173 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

enum Check {
    nonisolated(unsafe) private(set) static var passed = 0
    nonisolated(unsafe) private(set) static var failures: [String] = []
    nonisolated(unsafe) private static var suite = ""

    static func suite(_ name: String, _ body: () throws -> Void) rethrows {
        suite = name
        print("\n\u{001B}[1m\(name)\u{001B}[0m")
        try body()
    }

    static func isTrue(_ value: Bool, _ label: String, line: UInt = #line) {
        record(value, label, detail: "expected true", line: line)
    }

    static func isFalse(_ value: Bool, _ label: String, line: UInt = #line) {
        record(!value, label, detail: "expected false", line: line)
    }

    static func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: UInt = #line) {
        record(actual == expected, label, detail: "expected \(expected), got \(actual)", line: line)
    }

    static func notEqual<T: Equatable>(_ actual: T, _ other: T, _ label: String, line: UInt = #line) {
        record(actual != other, label, detail: "expected something other than \(other)", line: line)
    }

    static func nil_<T>(_ value: T?, _ label: String, line: UInt = #line) {
        record(value == nil, label, detail: "expected nil, got \(String(describing: value))", line: line)
    }

    /// Floating-point comparison — grid maths lands on values like 41.99999.
    static func close(_ actual: Double, _ expected: Double, _ label: String,
                      tolerance: Double = 0.001, line: UInt = #line) {
        record(abs(actual - expected) <= tolerance, label,
               detail: "expected \(expected) ± \(tolerance), got \(actual)", line: line)
    }

    static func close(_ actual: CGFloat, _ expected: CGFloat, _ label: String,
                      tolerance: Double = 0.001, line: UInt = #line) {
        close(Double(actual), Double(expected), label, tolerance: tolerance, line: line)
    }

    private static func record(_ ok: Bool, _ label: String, detail: @autoclosure () -> String, line: UInt) {
        if ok {
            passed += 1
            print("  \u{001B}[32m✓\u{001B}[0m \(label)")
        } else {
            let message = "\(suite) › \(label) (line \(line)): \(detail())"
            failures.append(message)
            print("  \u{001B}[31m✗\u{001B}[0m \(label) — \(detail())")
        }
    }

    /// Prints the summary and returns the process exit code.
    static func summary() -> Int32 {
        print("\n" + String(repeating: "─", count: 52))
        if failures.isEmpty {
            print("\u{001B}[32m\(passed) checks passed\u{001B}[0m")
            return 0
        }
        print("\u{001B}[31m\(failures.count) failed\u{001B}[0m, \(passed) passed\n")
        for failure in failures { print("  • \(failure)") }
        return 1
    }
}
