import SwiftUI

/// A tecla tátil do aparelho. Único estilo de botão da app.
/// Quadrada com ícone (transporte) ou com rótulo (botão de texto).
struct KeyButtonStyle: ButtonStyle {
    enum KeySize {
        case sm, md, lg

        var side: CGFloat {
            switch self {
            case .sm: Size.keySm
            case .md: Size.keyMd
            case .lg: Size.keyLg
            }
        }

        var radius: CGFloat { self == .sm ? Radius.sm : Radius.md }

        var iconSize: CGFloat {
            switch self {
            case .sm: 13
            case .md: 16
            case .lg: 20
            }
        }
    }

    var size: KeySize = .md
    /// Ligada (repetir, aleatório): desenha-se como premida.
    var isOn = false
    /// Botão de texto: altura key-sm, largura pelo rótulo.
    var isText = false

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, size: isText ? .sm : size, isOn: isOn, isText: isText)
    }

    private struct KeyBody: View {
        let configuration: Configuration
        let size: KeySize
        let isOn: Bool
        let isText: Bool
        /// Foco do próprio botão (o ambiente `isFocused` também acende quando
        /// a lista à volta tem foco, o que acendia todas as teclas lá dentro).
        @FocusState private var isFocused: Bool

        var body: some View {
            let pressed = configuration.isPressed || isOn
            let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)

            configuration.label
                .font(isText ? .dsLabel : .system(size: size.iconSize, weight: .regular))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, isText ? Space.s3 : 0)
                .frame(minWidth: size.side, minHeight: size.side, maxHeight: size.side)
                .frame(width: isText ? nil : size.side)
                .background {
                    shape.fill(pressed ? Color.keyFacePressed : Color.keyFace)
                }
                .overlay(alignment: .bottom) {
                    // shadow-key: lábio inferior de 1px, só em repouso.
                    if !pressed {
                        Rectangle()
                            .fill(Color.black.opacity(0.35))
                            .frame(height: 1)
                            .padding(.horizontal, 1)
                            .padding(.bottom, 1)
                    }
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.keyEdge, lineWidth: 1) }
                .overlay {
                    if isFocused {
                        RoundedRectangle(cornerRadius: size.radius + 4, style: .continuous)
                            .strokeBorder(Color.focus, lineWidth: 2)
                            .padding(-4)
                    }
                }
                .contentShape(shape)
                // Só entra no ciclo de foco com o acesso total pelo teclado, como os botões nativos.
                .focusable(interactions: .activate)
                .focused($isFocused)
        }
    }
}

extension ButtonStyle where Self == KeyButtonStyle {
    static func key(_ size: KeyButtonStyle.KeySize, isOn: Bool = false) -> KeyButtonStyle {
        KeyButtonStyle(size: size, isOn: isOn)
    }

    static var keyText: KeyButtonStyle { KeyButtonStyle(isText: true) }
}

extension View {
    /// Desliga o anel nativo; o KeyButtonStyle desenha o seu em `focus`.
    func keyFocus() -> some View { focusEffectDisabled() }
}
