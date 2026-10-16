# Janela do player

Como as peças se juntam no tamanho "Player com playlist" (360 × 480). A referência para a montagem.

## Estrutura
1. Chassis `surface-0`, cantos `radius-lg`, margem `space-4`.
2. Display no topo.
3. Barra de progresso logo abaixo, sem rótulo.
4. Barra de controlos: transporte à esquerda, repetir/aleatório/AirPlay e volume à direita.
5. Fila em `surface-1`, a ocupar o resto da altura, com linhas de lista.

## Regras
- Nada acima do display além da barra de título nativa do macOS (semáforos).
- A fila mostra a pasta atual por defeito. Adicionar outra pasta junta-a ao fim.
- Na mini barra (360 × 64) só fica display mini, play/pausa e seguinte.
- No tamanho com navegador (720 × 480), o navegador de pastas entra à esquerda com a mesma linha de lista.
