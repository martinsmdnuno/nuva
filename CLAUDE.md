# Leitor de música (PoC)

App macOS nativa em SwiftUI para tocar música a partir de pastas. Simplicidade estilo Winamp, linguagem visual hi-fi limpa (Cambridge Audio, B&O). Utilidade primeiro, não design first.

## Porquê
- A app Jellyfin para Mac é fraca; outras apps baralham a biblioteca por causa de metadados (remixes, covers, mixes espalhados).
- Apple Music não abre FLAC; a biblioteca é FLAC.
- O VLC soa mal com auscultadores Bluetooth; o QuickTime não. Usar o motor de áudio nativo da Apple.
- Tem de dar para enviar o som para um WiiM (AirPlay 2).

## Princípios (não negociáveis)
1. **Pastas, não metadados.** Pasta = álbum. Mostrar nome da pasta e nome do ficheiro tal como estão. Não ler tags para organizar.
2. **Áudio nativo.** AVFoundation (`AVQueuePlayer`). Sem VLC, sem ffmpeg, sem bibliotecas de áudio de terceiros.
3. **Uma janela pequena.** Sem navegação profunda.
4. **Teclado primeiro.** Media keys, atalhos, `MPRemoteCommandCenter` e `MPNowPlayingInfoCenter`.
5. **Fontes variáveis.** A app toca de "fontes". Cada fonte é uma árvore de pastas. Local (pasta no Mac, incluindo partilhas SMB montadas) e, mais tarde, Servidor (HTTP). O player não sabe de onde vem a música.

## Arquitetura
```swift
protocol MusicSource {
    var id: UUID { get }
    var name: String { get }
    func list(_ path: String) async throws -> [Entry]   // pastas e faixas
    func url(for track: Entry) async throws -> URL      // file:// ou https://
}
```
- `LocalSource` devolve `file://`. Guarda o acesso à pasta com security-scoped bookmark.
- `JellyfinSource` entra com utilizador e palavra-passe (Keychain), navega pelo `Path` dos itens (pastas do disco, nunca as tags do Jellyfin) e toca o original com `/Audio/{id}/stream.<ext>?static=true`.
- `ServerSource` (servidor HTTP genérico) continua só o protocolo e um stub.
- Extensões tocáveis: flac, mp3, m4a, aac, alac, wav, aiff.
- Ordem das faixas: ordenação natural pelo nome do ficheiro (`localizedStandardCompare`).

## Âmbito do PoC
Dentro:
- Adicionar uma fonte Local (NSOpenPanel), lembrada entre arranques.
- Navegar pastas, tocar uma pasta, fila (adicionar, remover, reordenar).
- Play/pausa, anterior, seguinte, seek, volume, repetir, aleatório.
- Media keys e Now Playing do macOS.
- Botão AirPlay (`AVRoutePickerView` embrulhado em `NSViewRepresentable`).
- Janela "Player com playlist" (360 × 480) e "Com navegador" (720 × 480).

Fora (por agora): fonte Servidor genérica, pesquisa, favoritos, mini barra, capas, contas.

## Design system
Em `docs/design-system/`. Ler `README.md` e `tokens.json` antes de qualquer UI, e o ficheiro do componente em `components/` antes de o construir.
- Cores: um `Color` por token em `Assets.xcassets` (variante Any = Alumínio, Dark = Chumbo), nomes iguais aos tokens.
- Letra: Inter e IBM Plex Mono embebidas na app (OFL, ficheiros de Google Fonts); fallback para SF Pro/SF Mono se faltarem.
- Teclas: um único `ButtonStyle` (`KeyButtonStyle`) com tamanhos sm, md, lg.
- Texto da interface em português de Portugal.

## Stack e convenções
- Swift 6, SwiftUI, macOS 14+. Projeto gerado com XcodeGen (`project.yml`), não editar o `.xcodeproj` à mão.
- Sem dependências externas no PoC.
- Pastas: `App/`, `Sources/Player/`, `Sources/Library/`, `Sources/UI/`, `Sources/DesignSystem/`.
- Compilar com `xcodebuild` depois de cada passo e corrigir erros antes de seguir.
- Commits pequenos, um por passo.
