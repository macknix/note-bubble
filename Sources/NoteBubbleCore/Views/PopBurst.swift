import SwiftUI

/// The payoff for a completed task: the tile's outline snaps outwards and breaks
/// into shards, left on screen for a beat after the note itself is gone.
struct PopBurst: View, Identifiable {
    let id = UUID()
    let centre: CGPoint
    let size: CGSize
    let cornerRadius: CGFloat
    let color: Color

    @State private var progress: CGFloat = 0

    private static let shardCount = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(color.opacity(0.9 * (1 - progress)), lineWidth: 2.5 * (1 - progress) + 0.5)
                .frame(width: size.width * (1 + progress * 0.6),
                       height: size.height * (1 + progress * 0.6))

            ForEach(0..<Self.shardCount, id: \.self) { index in
                let angle = (Double(index) / Double(Self.shardCount)) * 2 * .pi
                let distance = max(size.width, size.height) * (0.4 + progress * 0.6)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color.opacity(0.95 * (1 - progress)))
                    .frame(width: 6 * (1 - progress * 0.6), height: 6 * (1 - progress * 0.6))
                    .rotationEffect(.radians(angle + Double(progress) * 1.2))
                    .offset(x: cos(angle) * distance, y: sin(angle) * distance)
            }
        }
        .position(centre)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.42)) { progress = 1 }
        }
    }
}
