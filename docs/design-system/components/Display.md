# Display

O ecrã do aparelho: mostra o que está a tocar e onde vai. Sempre escuro (`display`) nos dois temas, recuado no chassis.

## Conteúdo, de cima para baixo
1. LED (6px, `led`) quando a tocar, `led-off` em pausa · formato e taxa em `display-meta` (`FLAC 24/96`) · nome da fonte à direita.
2. Título da faixa em `title`, `display-ink`. É o nome do ficheiro sem extensão nem número inicial.
3. Nome da pasta em `caption`, `display-muted` · saída de áudio em `display-meta` à direita.
4. Tempo decorrido em `display-time` à esquerda, duração em `display-meta` à direita.
5. Barra de posição (ver Progresso.md), a toda a largura.

## Regras
- Padding `space-3`, cantos `radius-sm`, sombra `shadow-display`. Sem contorno.
- Clicar no tempo alterna entre decorrido e restante.
- Sem capa de álbum.
- Na mini barra: só título e tempo (`display-time-mini`), numa linha.
