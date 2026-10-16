# Linha de lista

Uma linha para pastas no navegador e para faixas na fila. A unidade de toda a navegação.

## Anatomia
Ícone (`folder` ou número da faixa) · nome em `body` · à direita, duração em `duration` ou número de faixas em `caption`.

## Estados
- Repouso: fundo transparente sobre `surface-1`, divisória de 1px `line` em baixo.
- Hover: fundo `surface-0`.
- Selecionada: fundo `surface-2`, cantos `radius-sm`.
- A tocar: nome e número em `signal`. É o único sítio da lista onde o acento aparece.

## Regras
- Altura fixa `row` (28px), padding `space-2` × `space-3`.
- O nome é o da pasta ou ficheiro, sem limpeza de tags. Truncar no fim; tooltip com o nome completo.
- Duplo clique ou Enter toca; ⌘Enter adiciona à fila; arrastar reordena a fila.
