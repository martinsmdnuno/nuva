Lê o CLAUDE.md e tudo em docs/design-system/. Depois constrói o PoC por passos, compilando com xcodebuild no fim de cada um e fazendo commit:

1. Esqueleto: project.yml do XcodeGen, app SwiftUI macOS 14+ vazia que compila e abre uma janela de 360 × 480.
2. Design system em código: cores dos tokens em Assets.xcassets (Chumbo = Dark, Alumínio = Any), fontes Inter e IBM Plex Mono embebidas, KeyButtonStyle com sm/md/lg, e uma vista de pré-visualização com todas as teclas.
3. Fontes: protocolo MusicSource, LocalSource com NSOpenPanel e security-scoped bookmark, ServerSource como stub.
4. Player: AVQueuePlayer com fila, play/pausa, anterior, seguinte, seek, volume, repetir, aleatório. Testa com um FLAC.
5. UI: display, barra de progresso, barra de controlos e lista da fila, seguindo os ficheiros de componentes.
6. Navegador de pastas na janela de 720 × 480.
7. Sistema: media keys, Now Playing, botão AirPlay e atalhos de teclado do README.

Antes de começar, mostra-me o plano em poucas linhas e pergunta só o que for mesmo ambíguo.
