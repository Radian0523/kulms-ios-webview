import SwiftUI
import AVFoundation
import Vision

/// カメラで QR コードをスキャンし、otpauth:// URI から TOTP シークレットを抽出するビュー。
struct QRCodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSecretFound: (String) -> Void

    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var hasScanned = false

    var body: some View {
        NavigationStack {
            ZStack {
                switch cameraPermission {
                case .authorized:
                    CameraPreviewView(onQRDetected: handleQR)
                        .ignoresSafeArea()
                    VStack {
                        Spacer()
                        Text(String(localized: "totpScanGuide"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.bottom, 60)
                    }
                case .notDetermined:
                    ProgressView()
                        .task {
                            await AVCaptureDevice.requestAccess(for: .video)
                            cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
                        }
                default:
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "totpCameraPermission"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button(String(localized: "openSettings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "totpScanQr"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "close")) {
                        dismiss()
                    }
                    .tint(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private func handleQR(_ code: String) {
        guard !hasScanned else { return }
        if let secret = TOTPGenerator.extractSecret(from: code) {
            hasScanned = true
            onSecretFound(secret)
            dismiss()
        }
    }
}

// MARK: - Camera Preview (AVFoundation + Vision)

private struct CameraPreviewView: UIViewRepresentable {
    let onQRDetected: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return view
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(context.coordinator, queue: DispatchQueue(label: "qr-scan-queue"))
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        context.coordinator.previewLayer = previewLayer
        context.coordinator.session = session

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onQRDetected: onQRDetected)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.session?.stopRunning()
    }

    class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        let onQRDetected: (String) -> Void
        var previewLayer: AVCaptureVideoPreviewLayer?
        var session: AVCaptureSession?
        private var isProcessing = false

        init(onQRDetected: @escaping (String) -> Void) {
            self.onQRDetected = onQRDetected
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard !isProcessing else { return }
            isProcessing = true

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                isProcessing = false
                return
            }

            let request = VNDetectBarcodesRequest { [weak self] request, _ in
                defer { self?.isProcessing = false }
                guard let results = request.results as? [VNBarcodeObservation] else { return }
                for barcode in results {
                    if barcode.symbology == .qr, let payload = barcode.payloadStringValue,
                       payload.hasPrefix("otpauth://") {
                        DispatchQueue.main.async {
                            self?.onQRDetected(payload)
                        }
                        return
                    }
                }
            }
            request.symbologies = [.qr]

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? handler.perform([request])
        }
    }
}
