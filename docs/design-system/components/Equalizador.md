# Equalizador

Popover da tecla equalizador (grupo saída). Dez bandas de -12 a +12 dB e presets.

## Anatomia
1. Cabeçalho: "equalizador" em `label` · à direita, interruptor deslizante com LED e a palavra "ligado" ou "desligado" (`legend`). O texto descreve o estado, não a ação.
2. Presets em grelha de 4, como texto em minúsculas (`caption`) com LED à esquerda. O ativo tem o LED aceso e o texto em `ink`; os outros em `ink-muted`.
3. Bandas: escala impressa por trás (+12, +6, 0, -6, -12, réguas de 1px, a do zero em `line`), calha de 2px e cursor retangular de 16 × 8px em `key-face`, como um fader.

## Regras
- Fundo `surface-1`, padding `space-4`, largura 380px.
- Desligado: bandas a 50% de opacidade.
- Duplo clique numa banda volta a 0 dB.
