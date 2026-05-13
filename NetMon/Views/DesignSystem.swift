import SwiftUI

struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
    }
}

struct InfoLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(minWidth: 55, alignment: .leading)
    }
}

struct InfoValue: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, design: .monospaced))
    }
}
