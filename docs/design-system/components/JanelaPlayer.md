# Janela do player

Como as peças se juntam no tamanho "Player com playlist" (360 × 480). A referência para a montagem.

## Estrutura
Tudo assenta no chassis `surface-0`, margem `space-4`. Não há cartões.
1. Display no topo, com a barra de posição dentro.
2. `space-4` · Teclas em três grupos com legenda: leitura à esquerda, modo ao meio, saída à direita, distribuídos a toda a largura.
3. `space-3` · Volume: legenda "volume" e barra com escala de 0 a 10.
4. `space-4` · Fila: cabeçalho com legenda "fila" à esquerda e "11 faixas · 39:18" à direita, depois as linhas até ao fundo.

## Regras
- Nada acima do display além da barra de título nativa do macOS (semáforos).
- A fila mostra a pasta atual por defeito. Adicionar outra pasta junta-a ao fim.
- No tamanho com navegador (720 × 480), o navegador de pastas entra à esquerda, no mesmo plano, separado por uma divisória vertical `line`.
