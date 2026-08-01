#if os(iOS)
import SwiftUI
import AVFoundation

/// A minimal AVFoundation-based QR scanner, presented as a sheet from `CheckInView`. Camera capture
/// is UIKit-only (`AVCaptureVideoPreviewLayer` has no SwiftUI-native equivalent), so this whole file
/// is compiled only on iOS — `Package.swift`'s `.macOS(.v14)` CLI-verification target must build
/// without this feature, and does: `CheckInView`'s manual text-entry path (mirroring the web app's
/// `CheckInForm.tsx`) is always available on every platform and is the primary, most-reliable flow.
///
/// Requires `NSCameraUsageDescription` to be set on the Xcode run target's Info tab (there is no
/// physical Info.plist in this `.xcodeproj`-free package — see README "Setup" step 4) or the OS
/// silently denies camera access at runtime.
///
/// NOT verified against a real camera or the iOS Simulator in this build environment — there is no
/// Simulator or device available here. Verified only by `swift build`/type-checking against the iOS
/// SDK; see the project README's "What was and wasn't verified" section for the full, honest list.
struct QRScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var permissionDenied = false
    @State private var cameraUnavailable = false

    var body: some View {
        NavigationStack {
            Group {
                if permissionDenied {
                    unavailableMessage(systemImage: "lock.slash", message: "Camera access is denied. Enable it in Settings, or paste the code manually.")
                } else if cameraUnavailable {
                    unavailableMessage(systemImage: "camera.fill", message: "No camera is available on this device. Paste the code manually instead.")
                } else {
                    CameraPreviewRepresentable(
                        onScan: onScan,
                        onUnavailable: { cameraUnavailable = true }
                    )
                    .ignoresSafeArea()
                }
            }
            .navigationTitle("Scan QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized:
                    break
                case .notDetermined:
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    if !granted { permissionDenied = true }
                default:
                    permissionDenied = true
                }
            }
        }
    }

    private func unavailableMessage(systemImage: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bridges an `AVCaptureSession` + `AVCaptureVideoPreviewLayer` into SwiftUI.
private struct CameraPreviewRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onUnavailable: () -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onScan = onScan
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

/// Scans for QR codes only (`metadataObjectTypes = [.qr]`) and reports the first decoded string
/// exactly once per presentation — the delegate stops the session immediately after a match so it
/// can't fire twice while the sheet is still animating away.
private final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onUnavailable: (() -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !session.isRunning else { return }
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard session.isRunning else { return }
        session.stopRunning()
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            onUnavailable?()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            onUnavailable?()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned,
              let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              readable.type == .qr,
              let value = readable.stringValue
        else { return }
        hasScanned = true
        session.stopRunning()
        onScan?(value)
    }
}
#endif
