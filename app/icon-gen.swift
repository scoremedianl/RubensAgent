import SwiftUI
import AppKit

extension Color {
    init(_ hex: UInt) {
        self.init(red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

struct Icon: View {
    let orange = Color(0xFF6B35)
    let size: CGFloat = 1024

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(0x0A1730), Color(0x000511)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(0xFF6B35).opacity(0.34), .clear],
                           center: .center, startRadius: 0, endRadius: 520)
            burst.offset(y: -34)
            // terminal prompt, clear of the burst
            Text("❯_")
                .font(.system(size: 116, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .offset(y: 384)
        }
        .frame(width: size, height: size)
    }

    // Sunburst built from separate rounded rays — painter's order, so overlaps
    // at the centre stay clean (no path-winding holes).
    private var burst: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                let len = size * (i % 2 == 0 ? 0.375 : 0.285)
                Capsule()
                    .fill(orange)
                    .frame(width: size * 0.066, height: len)
                    .offset(y: -len / 2)
                    .rotationEffect(.degrees(Double(i) / 12 * 360))
            }
            Circle().fill(orange).frame(width: size * 0.235, height: size * 0.235)
        }
        .shadow(color: Color(0xFF6B35).opacity(0.5), radius: 50)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    if let img = renderer.nsImage,
       let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
        try! png.write(to: url)
        print("wrote", url.path, png.count, "bytes")
    } else {
        print("render failed")
    }
}
