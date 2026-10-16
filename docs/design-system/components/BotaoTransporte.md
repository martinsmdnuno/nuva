# Botão de transporte

Tecla tátil quadrada com um ícone, para todas as ações de reprodução (anterior, play/pausa, seguinte, parar, repetir, aleatório, AirPlay).

## Tamanhos
- `key-lg` (44px): só play/pausa, uma por janela.
- `key-md` (36px): anterior, seguinte, parar.
- `key-sm` (28px, `radius-sm`): repetir, aleatório, AirPlay.

## Estados
- Repouso: `key-face`, contorno `key-edge`, `shadow-key`.
- Premida ou ligada (repetir, aleatório): `key-face-pressed`, sem sombra.
- Foco de teclado: anel de 2px em `focus`, 2px de afastamento.
- Nunca desativada: se não houver fila, play abre o navegador de pastas.

## Regras
- Ícone sempre em `ink`, nunca em `signal`.
- Ordem fixa: anterior, play/pausa, seguinte, parar · grupo à direita: repetir, aleatório, AirPlay.
- Cada tecla tem tooltip com o nome e o atalho ("Seguinte ⌘→").
- O consumidor fornece: o ícone (SF Symbol) e a ação. O estilo é um único `ButtonStyle`.
