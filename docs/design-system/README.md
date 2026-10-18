# Leitor de música

Pastas, som nativo, nada a mais. Um leitor para macOS que toca a música de uma pasta local ou do servidor, numa janela pequena, com a linguagem limpa de um aparelho hi-fi (linha Cambridge Audio, B&O).

Este documento guia quem constrói a app em SwiftUI. Utilidade primeiro: cada regra aqui existe para tornar a app mais rápida de usar, não mais bonita.

## Princípios

1. **Função primeiro.** Cada elemento serve uma ação ou mostra uma informação. Se não serve, sai. Sem animações decorativas, sem gradientes, sem capas gigantes.
2. **Menos, mas melhor (Dieter Rams).** Um só plano. Sem cartões dentro de cartões, sem contornos à volta de teclas, sem réguas entre linhas. As zonas separam-se por espaço. A hierarquia vem da cor e da largura das teclas, nunca de mais traço.
3. **Pastas, não metadados.** Pasta = álbum. Mostramos o nome da pasta e o nome do ficheiro tal como estão. Nunca reorganizamos por tags.
4. **Uma janela.** Tudo cabe numa janela compacta. Não há páginas, separadores ou navegação profunda.
5. **Teclado primeiro.** Tudo o que se faz com o rato tem atalho. Media keys do Mac funcionam sempre.
6. **O aparelho, não a app.** O display é sempre escuro, como o de um amplificador. O resto do chassis segue o tema (Chumbo ou Alumínio).

## Fontes de música

A interface não distingue a origem. Local e Servidor aparecem como fontes na mesma lista, com o mesmo comportamento. O único sinal da origem é o ícone ao lado do nome da fonte (`internaldrive` ou `server.rack` em SF Symbols) e, em erro, a mensagem em `danger`.

## Cor

Cinza chumbo com um único acento.

- **Chassis:** `surface-0` é o único plano da janela: display, teclas e fila assentam todos nele. `surface-1` fica para popovers (equalizador) e `surface-2` para a linha selecionada.
- **Display:** `display` com `display-ink`, `display-muted` e `display-track` (calha da posição). Igual nos dois temas, recuado com `shadow-display`.
- **Texto:** `ink` para o principal, `ink-muted` para durações, metadados, legendas e ícones em repouso.
- **Teclas:** três tons, como numa calculadora Braun. `key-play` (âmbar) só na tecla play/pausa. `key-face` (cinzento claro) no transporte. `key-mode` (cinzento médio) em modo, saída e botões de texto.
- **Acento:** âmbar, um só, em três papéis ligados entre si: a tecla que toca (`key-play`), os LEDs (`led`) e o nome da faixa a tocar (`signal`). Nunca em fundos, hovers ou texto que não seja a faixa atual.
- **LED:** ponto de 4px, `led` aceso, `led-off` apagado. Mostra estados: reprodução no display, repetir/aleatório/equalizador ligados por cima da tecla, a faixa a tocar na lista.
- **Erro:** `danger` só em texto e ícone, nunca como fundo.
- **Foco:** `focus` num anel de 2px à volta do controlo com foco de teclado.

Temas: **Chumbo** é o principal. **Alumínio** é o tema claro e segue a aparência do sistema. Todos os pares de texto passam 4.5:1 nos dois temas.

## Letra

Duas famílias, carregadas do Google Fonts ou embebidas na app (`Inter` e `IBM Plex Mono`, ambas OFL):

- **Inter** para a interface: títulos de faixa (`title`), listas (`body`), rótulos (`label`), notas (`caption`).
- **Legendas** (`legend`, Inter 10px, minúsculas, `ink-muted`): o nome impresso no chassis por baixo de cada grupo de teclas (leitura, modo, saída) e de cada zona (volume, fila), como no Braun TG 60.
- **IBM Plex Mono** para números e o display: tempo (`display-time`), formato e taxa (`display-meta`), durações na lista (`duration`). Algarismos de largura fixa para o tempo não saltar.

Nomes japoneses e outros alfabetos caem para a fonte do sistema (Hiragino), o que é aceitável. Nunca truncar com reticências a meio: trunca no fim, e o nome completo aparece no tooltip.

## Botões

Teclas lisas, como numa calculadora ou num gravador Braun:

- Sem contorno nem lábio. A face é o limite. Cantos `radius-sm`.
- Todas as teclas de ícone têm a mesma altura (`key`, 36px). A importância vem da cor e da largura: play `key-w-lg` 56px em `key-play`, transporte `key-w-md` 40px em `key-face`, modo e saída `key-w-sm` 32px em `key-mode`.
- Premida: a face escurece 15% enquanto o rato está em baixo. Não há tecla "afundada" para estados.
- Ligada (repetir, aleatório, equalizador): LED de 4px aceso por cima da tecla. Teclas com estado têm sempre o LED, aceso ou apagado.
- As teclas agrupam-se por função, com espaço entre grupos e uma legenda por baixo: **leitura** (anterior, play/pausa, seguinte), **modo** (repetir, aleatório), **saída** (AirPlay, equalizador).
- Botões de texto (Adicionar pasta, Tocar pasta) usam `key-mode` com rótulo `label`, altura `key-text` 28px.

## Ícones

SF Symbols, peso regular, nunca preenchidos exceto `play.fill` e `pause.fill` dentro da tecla de play. Símbolos fixos: `backward.end`, `forward.end`, `play.fill`, `pause.fill`, `repeat`, `shuffle`, `airplayaudio`, `folder`, `music.note`, `internaldrive`, `server.rack`, `speaker.wave.2`.

## Janelas

Três tamanhos, mesmo conteúdo, a app escolhe pelo tamanho da janela:

- **Mini barra** (360 × 64): display mini + play/pausa + seguinte. Fica por cima das outras janelas se o utilizador quiser.
- **Player com playlist** (360 × 480): display com a posição, teclas em três grupos, volume, fila. Tudo no mesmo plano.
- **Com navegador** (720 × 480): navegador de pastas à esquerda, player com fila à direita.

## Atalhos

Espaço play/pausa · ⌘→ seguinte · ⌘← anterior · ⌘↑ ⌘↓ volume · ⌘F procurar pasta · ⌘L ir para a faixa atual · Enter tocar seleção · ⌘Enter adicionar à fila · ⌘B mostrar ou esconder as pastas · ⌘1 ⌘2 ⌘3 tamanho da janela.

## Texto da interface

Português de Portugal, frases curtas, verbo primeiro, sem pontos finais em botões. "Adicionar fonte", "Tocar pasta", "Servidor offline. Tentar de novo". Nada de "por favor" nem pontos de exclamação.

## Para quem implementa (SwiftUI)

- Tokens de cor como `Color` em `Assets.xcassets` com variante clara e escura, nomes iguais aos tokens.
- Tempo com `.font(.custom("IBMPlexMono-Light", size: 28)).monospacedDigit()`.
- Teclas como um `ButtonStyle` único com os três tamanhos.
- Áudio por AVFoundation (`AVPlayer`/`AVQueuePlayer`), saída AirPlay por `AVRoutePickerView` na tecla `airplayaudio`.
- Media keys e Centro de Controlo por `MPRemoteCommandCenter` e `MPNowPlayingInfoCenter`.
