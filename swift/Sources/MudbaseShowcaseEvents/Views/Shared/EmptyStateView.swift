import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 48)
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer(minLength: 48)
        }
        .frame(maxWidth: .infinity)
    }
}
