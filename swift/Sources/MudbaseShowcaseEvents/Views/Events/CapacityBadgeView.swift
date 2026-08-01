import SwiftUI

/// Mirrors `CapacityBadge.tsx`'s three-tier variant logic exactly: full (destructive/red), nearly
/// full — within 10% of capacity, minimum 1 — (warning/orange), otherwise plenty of room
/// (success/green).
struct CapacityBadgeView: View {
    let confirmed: Int?
    let capacity: Int
    var isLoading: Bool = false

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(showsPlaceholder ? Color.secondary : Color.white)
            .background(backgroundColor, in: Capsule())
    }

    private var showsPlaceholder: Bool { isLoading || confirmed == nil }

    private var label: String {
        guard let confirmed, !isLoading else { return "…/\(capacity)" }
        let remaining = capacity - confirmed
        return remaining <= 0 ? "Full · \(confirmed)/\(capacity)" : "\(confirmed)/\(capacity) booked"
    }

    private var backgroundColor: Color {
        guard let confirmed, !isLoading else { return Color.secondary.opacity(0.15) }
        let remaining = capacity - confirmed
        if remaining <= 0 { return .red }
        let warnThreshold = max(1, Int((Double(capacity) * 0.1).rounded(.up)))
        return remaining <= warnThreshold ? .orange : .green
    }
}
