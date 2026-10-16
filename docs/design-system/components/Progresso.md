# Barra de progresso

Mostra e controla a posição na faixa.

## Regras
- Calha `track`, parte percorrida `fill`, espessura `bar` (4px), cantos `radius-sm`.
- Sem cabeça visível em repouso. No hover aparece um círculo de 10px em `fill` e um tooltip com o tempo nesse ponto.
- Área clicável de 16px de altura, maior do que a barra.
- Setas do teclado avançam 5 segundos quando tem foco.
- Em streaming, a parte já carregada pode aparecer em `line` entre `fill` e `track`. Só se ajudar; senão omitir.
