import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReceiveView: View {
    let wallet: Wallet
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(wallet.title)
                    .font(.headline)

                qrImage
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)

                Text(wallet.address)
                    .font(.footnote.monospaced())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    UIPasteboard.general.string = wallet.address
                    copied = true
                } label: {
                    Label(copied ? "Скопировано" : "Скопировать адрес", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)

                Text("Адрес нигде не зарегистрирован в сети TON и не может принять настоящие средства — этот кошелёк существует только в этом приложении.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("Получить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private var qrImage: Image {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(wallet.address.utf8)
        filter.correctionLevel = "M"
        if let outputImage = filter.outputImage {
            let context = CIContext()
            if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                return Image(decorative: cgImage, scale: 1.0)
            }
        }
        return Image(systemName: "qrcode")
    }
}
