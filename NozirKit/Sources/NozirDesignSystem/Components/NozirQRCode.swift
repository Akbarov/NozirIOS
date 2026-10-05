import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The pairing code as a QR. Black on white in both themes, with a quiet zone:
/// scanners look for dark modules on a light ground.
public struct NozirQRCode: View {
    private let payload: String
    private let accessibilityLabel: String
    @State private var image: UIImage?

    public init(payload: String, accessibilityLabel: String) {
        self.payload = payload
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 184, height: 184)
        .padding(NozirSpacing.compact)
        .background(RoundedRectangle(cornerRadius: NozirRadius.cardCompact).fill(Color.white))
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        // Drawn once per code, not on every redraw of the screen around it.
        .task(id: payload) { image = Self.image(for: payload) }
    }

    /// Medium error correction, as the Android app draws it (ZXing ECC M).
    nonisolated static func image(for payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
