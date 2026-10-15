import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Service cover (schematic picture, else first work photo) with the category icon as placeholder.
struct ServiceThumbnail: View {
    let service: Service
    var size: CGFloat = 56

    var body: some View {
        ProductThumbnail(path: service.coverPath, size: size, placeholderSymbol: service.category.symbol)
    }
}

/// Media thumbnail for a server-relative path (`/uploads/…`) with a neutral placeholder.
struct ProductThumbnail: View {
    @Environment(APIClient.self) private var api
    let path: String?
    var size: CGFloat = 56
    /// Shown when there is no picture.
    var placeholderSymbol = "sparkles"

    var body: some View {
        Group {
            if let url = api.mediaURL(for: path) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder(symbol: "photo.badge.exclamationmark")
                    default:
                        placeholder(symbol: nil)
                    }
                }
            } else {
                placeholder(symbol: placeholderSymbol)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
    }

    private func placeholder(symbol: String?) -> some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.32))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// QR code rendered with CoreImage.
struct QRCodeView: View {
    let text: String
    var size: CGFloat = 220

    var body: some View {
        Group {
            if let image = QRCode.image(for: text) {
                Image(decorative: image, scale: 1)
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
        .padding(16)
        .background(.white, in: .rect(cornerRadius: 24))
        .accessibilityLabel("QR-код со ссылкой")
    }
}

nonisolated enum QRCode {
    static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
