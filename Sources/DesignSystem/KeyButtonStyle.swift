import SwiftUI

/// A tecla lisa do aparelho, como numa calculadora Braun. Único estilo de botão da app.
/// Sem contorno: o tom da face diz a função. Com ícone (todas a 36px de altura) ou com rótulo.
struct KeyButtonStyle: ButtonStyle {
    enum Tone {
        /// Play/pausa: âmbar, 56px. Uma por janela.
        case play
        /// Anterior e seguinte: cinzento claro, 40px.
        case transport
        /// Modo, saída e botões de texto: cinzento médio, 32px.
        case mode

        var face: Color {
            switch self {
            case .play: .keyPlay
            case .transport: .keyFace
            case .mode: .keyMode
            }
        }

        var ink: Color { self == .mode ? .keyModeInk : .keyInk }

        var width: CGFloat {
            switch self {
            case .play: Size.keyWLg
            case .transport: Size.keyWMd
            case .mode: Size.keyWSm
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .play: 18
            case .transport: 16
            case .mode: 14
            }
        }
    }

    var tone: Tone = .transport
    /// Botão de texto: altura key-text, largura pelo rótulo, sempre no tom de modo.
    var isText = false

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, tone: isText ? .mode : tone, isText: isText)
    }

    private struct KeyBody: View {
        let configuration: Configuration
        let tone: Tone
        let isText: Bool
        /// Foco do próprio botão (o ambiente `isFocused` também acende quando
        /// a lista à volta tem foco, o que acendia todas as teclas lá dentro).
        @FocusState private var isFocused: Bool

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)

            configuration.label
                .font(isText ? .dsLabel : .system(size: tone.iconSize, weight: .regular))
                .foregroundStyle(tone.ink)
                .padding(.horizontal, isText ? Space.s3 : 0)
                .frame(width: isText ? nil : tone.width, height: isText ? Size.keyText : Size.key)
                .background {
                    shape.fill(tone.face)
                    // Premida: a face escurece enquanto o rato está em baixo.
                    if configuration.isPressed { shape.fill(Color.black.opacity(0.15)) }
                }
                .overlay {
                    if isFocused {
                        RoundedRectangle(cornerRadius: Radius.sm + 4, style: .continuous)
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
    static func key(_ tone: KeyButtonStyle.Tone) -> KeyButtonStyle { KeyButtonStyle(tone: tone) }

    static var keyText: KeyButtonStyle { KeyButtonStyle(isText: true) }
}

/// Ponto de luz: estado ligado, reprodução, faixa a tocar.
struct LED: View {
    var isOn: Bool
    var size: CGFloat = Size.led

    var body: some View {
        Circle()
            .fill(isOn ? Color.led : Color.ledOff)
            .frame(width: size, height: size)
    }
}

extension View {
    /// Desliga o anel nativo; o KeyButtonStyle desenha o seu em `focus`.
    func keyFocus() -> some View { focusEffectDisabled() }

    /// LED por cima da tecla. `nil` deixa o espaço vazio, para as faces alinharem
    /// com as das teclas que têm estado.
    func keyLED(_ isOn: Bool?) -> some View {
        VStack(spacing: Space.s1) {
            if let isOn {
                LED(isOn: isOn)
            } else {
                Color.clear.frame(width: Size.led, height: Size.led)
            }
            self
        }
    }

    /// Legenda impressa no chassis por baixo de um grupo de teclas ou à frente de uma zona.
    func legend() -> some View {
        font(.dsLegend).foregroundStyle(Color.inkMuted)
    }
}
