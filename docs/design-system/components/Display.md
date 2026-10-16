# Display

O ecrã do aparelho: mostra o que está a tocar. Sempre escuro (`display`) nos dois temas.

## Conteúdo, de cima para baixo
1. LED `signal` (6px) quando a tocar, apagado em pausa · formato e taxa em `display-meta` (`FLAC 24/96`) · fonte (`Local` ou `Servidor`).
2. Título da faixa em `title`, `display-ink`. É o nome do ficheiro sem extensão nem número inicial.
3. Nome da pasta em `caption`, `display-muted`.
4. Tempo decorrido em `display-time` à esquerda, duração em `display-meta` à direita.

## Regras
- Padding `space-3`, cantos `radius-md`.
- Clicar no tempo alterna entre decorrido e restante.
- Sem capa de álbum. Se a pasta tiver `cover.jpg`, pode aparecer como miniatura de 48px à esquerda, nunca maior.
- Na mini barra: só título e tempo (`display-time-mini`), numa linha.
