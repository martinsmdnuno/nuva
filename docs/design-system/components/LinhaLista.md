# Linha de lista

Uma linha para pastas no navegador e para faixas na fila. A unidade de toda a navegação.

## Anatomia
Coluna de 12px (ícone `folder` para pastas, LED para faixas) · nome em `body` · à direita, duração em `duration` ou número de faixas em `caption`.

## Estados
- Repouso: fundo transparente. Sem divisórias entre linhas.
- Hover: fundo `surface-1`, cantos `radius-sm`.
- Selecionada: fundo `surface-2`, cantos `radius-sm`.
- A tocar: LED `led` aceso na coluna da esquerda e nome em `signal`. É o único sítio da lista onde o acento aparece.

## Regras
- Altura fixa `row` (28px), padding horizontal `space-2`.
- Sem número de posição na fila: o ficheiro já traz o seu.
- O nome é o do ficheiro sem extensão (o formato está no display) ou o da pasta, sem limpeza de tags. Truncar no fim; tooltip com o nome completo, com extensão.
- Duplo clique ou Enter toca; ⌘Enter adiciona à fila; arrastar reordena a fila.
