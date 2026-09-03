// Presents the system camera and recognizes one HiBoss pairing QR code.
// Exports: PairingScannerView.
// Dependencies: SwiftUI, AVFoundation, and UIKit camera preview.

import AVFoundation
import SwiftUI
import UIKit

struct PairingScannerView: View {
    let onPairingPayload: (PairingPayload) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var cameraError: String?

    var body: some View {
        NavigationStack {
            Group {
                switch permission {
                case .authorized:
                    camera
                case .notDetermined:
                    ProgressView(String(localized: "Requesting camera access…"))
                case .denied, .restricted:
                    permissionDenied
                @unknown default:
                    permissionDenied
                }
            }
            .navigationTitle(String(localized: "Scan pairing code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
        .task { await requestCameraAccessIfNeeded() }
    }

    private var camera: some View {
        ZStack {
            QRScannerCameraView { rawValue in
                guard case let .success(payload) = PairingPayload.parse(rawValue) else {
                    cameraError = String(localized: "That QR code is not a valid HiBoss pairing code.")
                    return false
                }
                onPairingPayload(payload)
                return true
            }
            .ignoresSafeArea()
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.9), lineWidth: 3)
                .frame(width: 250, height: 250)
            if let cameraError {
                Text(cameraError)
                    .font(.hbSmall)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 32)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 36)
            }
        }
    }

    private var permissionDenied: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.ink2)
            Text("Camera access is needed to scan a pairing code.")
                .font(.hbBody)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel") { dismiss() }
                .buttonStyle(.borderless)
        }
        .padding(24)
    }

    private func requestCameraAccessIfNeeded() async {
        guard permission == .notDetermined else { return }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        permission = granted ? .authorized : .denied
    }
}

private struct QRScannerCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Bool

    func makeUIViewController(context: Context) -> QRScannerViewController {
        QRScannerViewController(onCode: onCode)
    }

    func updateUIViewController(_ controller: QRScannerViewController, context: Context) {}
}

@MainActor
private final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onCode: (String) -> Bool
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ai.hiboss.qr-scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?

    init(onCode: @escaping (String) -> Bool) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: sessionQueue)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        view.layer.insertSublayer(layer, at: 0)
        layer.frame = view.bounds
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let rawValue = object.stringValue else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if onCode(rawValue) {
                sessionQueue.async { [session] in session.stopRunning() }
            }
        }
    }
}
