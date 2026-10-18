# Tecla

Tecla lisa com um ícone, para todas as ações de reprodução e saída (anterior, play/pausa, seguinte, repetir, aleatório, AirPlay, equalizador). Referência: as teclas da calculadora Braun ET66 e do gravador TG 60.

## Tons e larguras
Todas com altura `key` (36px) e cantos `radius-sm`. Sem contorno nem lábio.
- **Play/pausa:** `key-play`, ícone `key-ink`, largura `key-w-lg` (56px). Uma por janela.
- **Transporte** (anterior, seguinte): `key-face`, ícone `key-ink`, largura `key-w-md` (40px).
- **Modo e saída** (repetir, aleatório, AirPlay, equalizador): `key-mode`, ícone `key-mode-ink`, largura `key-w-sm` (32px).

## Estados
- Premida: a face escurece 15% enquanto o rato está em baixo.
- Ligada: LED de 4px por cima da tecla, `led` aceso, `led-off` apagado. As teclas com estado (repetir, aleatório, equalizador) mostram sempre o LED. As outras deixam o espaço vazio para as faces alinharem.
- Foco de teclado: anel de 2px em `focus`, 4px de afastamento.
- Nunca desativada: se não houver fila, play abre o navegador de pastas.

## Grupos
Três grupos com espaço entre eles e uma legenda (`legend`) por baixo: **leitura** · **modo** · **saída**. Ordem fixa dentro de cada um. Não há tecla Parar (a pausa basta, ⌘. continua no menu) nem tecla para as pastas (⌘B e menu Visualização).

## Regras
- Ícone 16px (play 18px, modo e saída 14px), peso regular.
- Cada tecla tem tooltip com o nome e o atalho ("Seguinte ⌘→").
- O consumidor fornece: o ícone (SF Symbol), o tom, a largura e a ação. Um único `ButtonStyle`.
