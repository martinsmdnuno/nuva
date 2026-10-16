# Leitor de música

Pastas, som nativo, nada a mais. Um leitor para macOS que toca a música de uma pasta local ou do servidor, numa janela pequena, com a linguagem limpa de um aparelho hi-fi (linha Cambridge Audio, B&O).

Este documento guia quem constrói a app em SwiftUI. Utilidade primeiro: cada regra aqui existe para tornar a app mais rápida de usar, não mais bonita.

## Princípios

1. **Função primeiro.** Cada elemento serve uma ação ou mostra uma informação. Se não serve, sai. Sem animações decorativas, sem gradientes, sem capas gigantes.
2. **Pastas, não metadados.** Pasta = álbum. Mostramos o nome da pasta e o nome do ficheiro tal como estão. Nunca reorganizamos por tags.
3. **Uma janela.** Tudo cabe numa janela compacta. Não há páginas, separadores ou navegação profunda.
4. **Teclado primeiro.** Tudo o que se faz com o rato tem atalho. Media keys do Mac funcionam sempre.
5. **O aparelho, não a app.** O display é sempre escuro, como o de um amplificador. O resto do chassis segue o tema (Chumbo ou Alumínio).

## Fontes de música

A interface não distingue a origem. Local e Servidor aparecem como fontes na mesma lista, com o mesmo comportamento. O único sinal da origem é o ícone ao lado do nome da fonte (`internaldrive` ou `server.rack` em SF Symbols) e, em erro, a mensagem em `danger`.

## Cor

Cinza chumbo com um único acento.

- **Chassis e painéis:** `surface-0` (fundo da janela), `surface-1` (playlist, navegador, barra de controlos), `surface-2` (linha selecionada).
- **Display:** `display` com `display-ink` e `display-muted`. Igual nos dois temas.
- **Texto:** `ink` para o principal, `ink-muted` para durações, metadados e ícones em repouso.
- **Acento:** `signal` (âmbar de VU) só marca o que está a tocar: a linha da faixa atual e o LED no display. Nunca em botões, fundos ou hovers.
- **Erro:** `danger` só em texto e ícone, nunca como fundo.
- **Foco:** `focus` num anel de 2px à volta do controlo com foco de teclado.

Temas: **Chumbo** é o principal. **Alumínio** é o tema claro e segue a aparência do sistema. Todos os pares de texto passam 4.5:1 nos dois temas.

## Letra

Duas famílias, carregadas do Google Fonts ou embebidas na app (`Inter` e `IBM Plex Mono`, ambas OFL):

- **Inter** para a interface: títulos de faixa (`title`), listas (`body`), rótulos (`label`), notas (`caption`).
- **IBM Plex Mono** para números e o display: tempo (`display-time`), formato e taxa (`display-meta`), durações na lista (`duration`). Algarismos de largura fixa para o tempo não saltar.

Nomes japoneses e outros alfabetos caem para a fonte do sistema (Hiragino), o que é aceitável. Nunca truncar com reticências a meio: trunca no fim, e o nome completo aparece no tooltip.

## Botões

Teclas táteis, como num aparelho:

- Face `key-face`, contorno de 1px `key-edge`, lábio inferior `shadow-key`, cantos `radius-md`.
- Premida ou ligada (repetir, aleatório): face `key-face-pressed`, sem lábio.
- Ícone em `ink`, 16px nas teclas `key-md`, 20px em `key-lg`.
- Três tamanhos: `key-sm` 28px (secundárias), `key-md` 36px (transporte), `key-lg` 44px (play/pausa, um por janela).
- Botões de texto (Adicionar fonte, Cancelar) usam a mesma tecla com rótulo `label`, nunca preenchidos com cor.

## Ícones

SF Symbols, peso regular, nunca preenchidos exceto `play.fill` e `pause.fill` dentro da tecla de play. Símbolos fixos: `backward.end`, `forward.end`, `play.fill`, `pause.fill`, `stop`, `repeat`, `shuffle`, `airplayaudio`, `folder`, `music.note`, `internaldrive`, `server.rack`, `speaker.wave.2`.

## Janelas

Três tamanhos, mesmo conteúdo, a app escolhe pelo tamanho da janela:

- **Mini barra** (360 × 64): display mini + play/pausa + seguinte. Fica por cima das outras janelas se o utilizador quiser.
- **Player com playlist** (360 × 480): display, barra de controlos, fila.
- **Com navegador** (720 × 480): navegador de pastas à esquerda, player com fila à direita.

## Atalhos

Espaço play/pausa · ⌘→ seguinte · ⌘← anterior · ⌘↑ ⌘↓ volume · ⌘F procurar pasta · ⌘L ir para a faixa atual · Enter tocar seleção · ⌘Enter adicionar à fila · ⌘1 ⌘2 ⌘3 tamanho da janela.

## Texto da interface

Português de Portugal, frases curtas, verbo primeiro, sem pontos finais em botões. "Adicionar fonte", "Tocar pasta", "Servidor offline. Tentar de novo". Nada de "por favor" nem pontos de exclamação.

## Para quem implementa (SwiftUI)

- Tokens de cor como `Color` em `Assets.xcassets` com variante clara e escura, nomes iguais aos tokens.
- Tempo com `.font(.custom("IBMPlexMono-Light", size: 28)).monospacedDigit()`.
- Teclas como um `ButtonStyle` único com os três tamanhos.
- Áudio por AVFoundation (`AVPlayer`/`AVQueuePlayer`), saída AirPlay por `AVRoutePickerView` na tecla `airplayaudio`.
- Media keys e Centro de Controlo por `MPRemoteCommandCenter` e `MPNowPlayingInfoCenter`.
