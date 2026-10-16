import AVFoundation
import CoreImage
import Foundation
import SwiftUI
import UIKit

/// Blink: messages carried by light.
///
/// The fifth transport. Chirp needs a room where sound is
/// allowed; Blink needs only line of sight: the payload —
/// the same Knocktalk sealed box as ever — is cut into
/// fragments and shown as a looping sequence of QR frames,
/// and the other phone's camera gathers them until the set
/// is whole. Fragment, index, total: the same discipline as
/// the knock fragments, at the speed of sight.
///
/// The loop is the error correction. A frame the camera
/// missed comes around again in a second; there is nothing
/// to acknowledge and no way to acknowledge it — light,
/// like sound, is a one-way confession.
enum BlinkFraming {
    static let chunkBytes = 110

    static func frames(payload: Data, suite: Int) -> [String] {
        var chunks: [Data] = []
        var start = 0
        if payload.isEmpty { chunks = [Data()] }
        while start < payload.count {
            let end = min(start + chunkBytes, payload.count)
            chunks.append(payload[start..<end])
            start = end
        }
        let total = chunks.count
        return chunks.enumerated().map { index, chunk in
            // Base64url-ish: the standard alphabet's '/' would
            // collide with the field separator.
            let body = chunk.base64EncodedString()
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
            return "NJ1/\(suite)/\(index)/\(total)/\(body)"
        }
    }

    static func qrImage(for text: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator")
        else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(
            by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = CIContext().createCGImage(
            scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Gathers blink frames until the set is whole.
final class BlinkCollector {
    private(set) var suite: Int?
    private(set) var total: Int?
    private var chunks: [Int: Data] = [:]

    var received: Int { chunks.count }

    func reset() {
        suite = nil
        total = nil
        chunks = [:]
    }

    /// Feed one decoded QR string. Returns the reassembled
    /// payload the moment the final missing frame lands.
    func feed(_ text: String) -> Data? {
        let parts = text.split(separator: "/",
                               omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0] == "NJ1",
              let suite = Int(parts[1]),
              let index = Int(parts[2]),
              let count = Int(parts[3])
        else { return nil }
        let body = String(parts[4])
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "-", with: "+")
        guard let data = Data(base64Encoded: body)
        else { return nil }
        if total != nil, total != count { reset() }
        total = count
        self.suite = suite
        chunks[index] = data
        guard chunks.count == count else { return nil }
        var out = Data()
        for i in 0..<count {
            guard let chunk = chunks[i] else { return nil }
            out.append(chunk)
        }
        return out
    }
}

/// The sender's screen: one big frame at a time, cycling.
struct BlinkSenderView: View {
    let frames: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private let timer = Timer.publish(every: 0.5, on: .main,
                                      in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image = BlinkFraming.qrImage(
                    for: frames[index]) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
                Text("frame \(index + 1) of \(frames.count) "
                     + "— looping")
                    .font(.callout.weight(.semibold))
                Text("Hold this screen to the other phone's "
                     + "camera. The sequence repeats until "
                     + "every frame is caught — a missed frame "
                     + "is just a later frame.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .navigationTitle("Blink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onReceive(timer) { _ in
                index = (index + 1) % frames.count
            }
        }
    }
}

/// The camera side: an AVCaptureSession watching for blink
/// frames, and the preview that shows what it sees.
final class BlinkReceiver: NSObject, ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var status = "idle"
    @Published private(set) var got = 0
    @Published private(set) var want = 0
    /// (payload, suite) — return true when it opened.
    var onPayload: ((Data, Int) -> Bool)?

    let session = AVCaptureSession()
    private let collector = BlinkCollector()
    private var finished = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) {
                [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.begin()
                    } else {
                        self?.status = "camera permission "
                            + "denied — iOS Settings is where "
                            + "that changes"
                    }
                }
            }
        default:
            status = "camera permission denied — iOS Settings "
                + "is where that changes"
        }
    }

    private func begin() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(
                device: device)
        else {
            status = "no camera available"
            return
        }
        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
        }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }
        session.commitConfiguration()
        collector.reset()
        finished = false
        got = 0
        want = 0
        running = true
        status = "watching — hold the phones face to face"
        DispatchQueue.global(qos: .userInitiated).async {
            [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        guard running else { return }
        running = false
        status = "idle"
        DispatchQueue.global(qos: .userInitiated).async {
            [weak self] in
            self?.session.stopRunning()
        }
    }
}

extension BlinkReceiver: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects:
                        [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard running, !finished else { return }
        for object in metadataObjects {
            guard let readable = object
                    as? AVMetadataMachineReadableCodeObject,
                  let text = readable.stringValue
            else { continue }
            if let payload = collector.feed(text) {
                finished = true
                let opened = onPayload?(
                    payload, collector.suite ?? 0) ?? false
                let message = opened
                    ? "decoded — filed in the Blink thread"
                    : "saw a whole blink that does not open "
                        + "with your pairing key"
                stop()
                status = message
                return
            }
            got = collector.received
            want = collector.total ?? 0
        }
    }
}

final class PreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            if let previewLayer = previewLayer {
                layer.addSublayer(previewLayer)
            }
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

struct BlinkPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.previewLayer = layer
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// The receiver's screen: the camera's eye, the count, the
/// verdict.
struct BlinkReceiverView: View {
    @StateObject private var receiver = BlinkReceiver()
    @Environment(\.dismiss) private var dismiss
    var onPayload: (Data, Int) -> Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                BlinkPreview(session: receiver.session)
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if receiver.want > 0 {
                    Text("frames: \(receiver.got) of "
                         + "\(receiver.want)")
                        .font(.callout.weight(.semibold))
                }
                Text(receiver.status)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .navigationTitle("Receive a blink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                receiver.onPayload = onPayload
                receiver.start()
            }
            .onDisappear { receiver.stop() }
        }
    }
}
