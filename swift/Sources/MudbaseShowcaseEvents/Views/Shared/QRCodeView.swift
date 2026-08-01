import SwiftUI
import CoreImage.CIFilterBuiltins

/// Renders a booking's `qrToken` as a scannable QR code using CoreImage — cross-platform (iOS +
/// macOS, needed since `swift build` must succeed on macOS too for this environment's
/// verification), with no third-party dependency, mirroring the web app's `qrcode.react`
/// `<QRCodeSVG>` component.
struct QRCodeView: View {
    let text: String
    var size: CGFloat = 72

    var body: some View {
        Group {
            if let cgImage = Self.generateQRCode(from: text) {
                Image(decorative: cgImage, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private static func generateQRCode(from string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
