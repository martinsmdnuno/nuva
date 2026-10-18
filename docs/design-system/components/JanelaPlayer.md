# Janela do player

Como as peças se juntam no tamanho "Player com playlist" (360 × 480). A referência para a montagem.

## Estrutura
Tudo assenta no chassis `surface-0`, margem `space-4`. Não há cartões.
1. Display no topo, com a barra de posição dentro.
2. `space-4` · Teclas em três grupos com legenda: leitura à esquerda, modo ao meio, saída à direita, distribuídos a toda a largura.
3. `space-3` · Volume: legenda "volume" e barra com escala de 0 a 10.
4. `space-4` · Fila: cabeçalho com a pista "pastas" à esquerda e a pista "fila 11 faixas · 39:18" à direita, depois as linhas até ao fundo.

## Compacto (⌘3)
Os passos 1 a 3 e o cabeçalho da fila, sem as linhas. A janela fica com a altura do conteúdo. O cabeçalho fica para quem não conhece a app ver por onde se volta.

## Tecla das pastas
Quem não conhece a app tem de ver que há uma gaveta, e como a abre e fecha. No cabeçalho da fila, à esquerda (o lado de onde a gaveta abre): uma tecla de modo com `sidebar.left`, LED por cima (aceso com a gaveta aberta) e a legenda "pastas" ao lado.
- Clicar abre ou fecha a gaveta, como ⌘B. Tooltip "Mostrar pastas ⌘B" / "Esconder pastas ⌘B".
- Está sempre lá, mesmo com a fila vazia e no compacto.
- Com a gaveta aberta, o cabeçalho do navegador tem a mesma tecla no canto direito, junto à divisória, para a fechar.

## Pista da fila
À direita do mesmo cabeçalho: LED + "fila" em `legend` + total em mono 10px. LED aceso com a fila à vista. Clicar alterna entre o player e o compacto (⌘1 / ⌘3).

## Regras
- Nada acima do display além da barra de título nativa do macOS (semáforos).
- A fila mostra a pasta atual por defeito. Adicionar outra pasta junta-a ao fim.
- No tamanho com navegador (720 × 480), o navegador de pastas entra à esquerda, no mesmo plano, separado por uma divisória vertical `line`.

## Primeiro arranque e fila vazia
- **Sem fontes:** o display diz "Sem música · Adicionar uma pasta ou um servidor Jellyfin". No lugar da fila, a legenda "começar" e as duas formas de trazer música, cada uma com um botão de texto, uma linha a dizer o que é e o atalho: "Adicionar pasta" (música no Mac ou num disco de rede, ⌘O) e "Adicionar Jellyfin" (servidor Jellyfin com o teu utilizador, ⇧⌘O).
- **Com fontes, fila vazia:** "Fila vazia · Abrir as pastas e tocar uma" e o botão "Mostrar pastas" (⌘B).
- Play sem fila abre as pastas.
