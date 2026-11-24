# Roadmap — Caminhos, rios e suavização entre biomas

Status: **fases 1 a 4 implementadas** na branch `feature/paths` (2026-11-24), aguardando revisão. Ver "Status" no fim.

Objetivo: ruas, rios e suavização entre biomas sem exigir tiles de transição do modder,
sem quebrar mods nem saves existentes.

---

## 0. O que a leitura do projeto mostrou (e muda o plano)

| Achado | Consequência |
|---|---|
| Os dois TileSets usam `tile_layout = 5` (DIAMOND_DOWN). David: `tile_offset_axis = 0` (pointy-top, vizinho à direita em `(+256, 0)`). Example: `tile_offset_axis = 1` (flat-top, vizinho abaixo em `(0, +28)`). Conferido rodando o Godot headless. | Toda a geometria passa por `map_to_local` / `local_to_map` / `get_surrounding_cells`. `get_surrounding_cells` devolve os 6 vizinhos **em ordem angular**, então canto *i* = média(centro, vizinho[i], vizinho[i+1]). |
| O **mesmo** par de coordenadas tem vizinhos diferentes em pointy e flat (ex.: `(2,2)` → `(3,1)` no David, `(3,3)` no example). | "Sobreviver à troca de tileset" é exato entre tilesets com a mesma orientação. Entre orientações diferentes, as camadas de tile já se embaralham. Os caminhos degradam com elegância (ver 1.2), mas não ficam "corretos". |
| Regiões de textura são mais altas que o hex (David 256×384 sobre `tile_size` 256×256; example 32×48 sobre 32×28) e `texture_origin = (0,0)`. A arte fica centralizada na região, então o **hex desenhado fica uns ~64 px (David, ~13 px na tela) abaixo de `map_to_local`**. | Os caminhos ficariam desalinhados da arte. Vou medir isso num spike. Proposta: um campo opcional `hex_art_offset` com detecção automática (ver 1.5). |
| O pack de amostra do David tem **4 sobreposições de rio** (`1:3`, `6:3`, `7:3`, `0:4`) e **nenhuma rua**. Os rios dele passam **pelo centro** do hex. O tileset pixel-art (example) tem **11 peças de rua** (linha 9, `0:9`…`10:9`) e nenhum rio. | Fase 2: ruas por tile no **example**, rios por tile no **David**. Você liberou a troca, ver decisão D1. Rio por tile exige rio ancorado em **célula**, não em aresta (decisão D2). |
| As camadas do usuário são `TileMapLayer`s irmãs em `LayersTilemaps`, ordenadas por `z_index = total - i`. Não existe o conceito de "chão". | Os caminhos se encaixam *acima de uma camada âncora* (padrão: a de baixo, "World"). |
| `undo_redo` está em `HexMapEditor`, e strokes usam um buffer + `commit_action(false)`. | Os caminhos usam o mesmo `UndoRedo`, então um Ctrl+Z serve para tudo e segue a ordem cronológica. |
| `manifest_version` = `application/config/version` (versão do **app**, não do formato). | Entra um `format_version` inteiro separado (ver 1.3). |
| `project.godot` declara `features "4.7"` e o README diz 4.6. Tenho os binários 4.6.1 e 4.7 mono. | Vou testar no **4.7** (com ele que o projeto foi salvo). |
| Existem 4 saves "Alpha 0.3" reais em `~/Documents/rpg/maps`, um deles com caminho de tileset quebrado. | Uso cópias como fixture local, **sem commitar** (são mapas pessoais). No repo entram fixtures sintéticas equivalentes. |
| Há mudanças não commitadas (hex data panel / indicators / `hex_map_editor.tscn`). | Vou precisar editar `hex_map_editor.tscn` (decisão D5). |

---

## Decisões de design (valem para todas as fases)

1. **Dados independentes do tileset.** Caminhos guardam coordenadas de célula, nunca pixels nem atlas coords.
   Vértice = **trio ordenado das 3 células** que se encontram nele (`[(a),(b),(c)]` ordenado).
   Isso é canônico, não depende de orientação nem de índice de canto, e tem fallback natural:
   se o trio deixar de ser mutuamente adjacente após troca de tileset, a posição vira o
   centróide dos 3 centros (continua sendo um ponto razoável).
2. **Larguras relativas ao hex.** `PathStyle.width` etc. são frações do menor lado de `tile_size`,
   então o mesmo estilo funciona em hex de 28 px e de 256 px.
3. **Renderização desacoplada.** `PathRenderer` (interface) recebe `PathData` + `HexGeometry` e desenha.
   `VectorPathRenderer` na fase 1, `TilePathRenderer` na fase 2. O dado não sabe quem o desenha.
4. **Ordem de desenho = "passe de sobreposição" (overhang pass), não y-sort.** Recomendado (decisão D3):
   ```
   fundo
   camadas de chão (camadas do usuário até a âncora)   ← fase 3 aplica o warp aqui
   caminhos (vetor ou tile)
   overhang: cópia das camadas de chão desenhando SÓ os pixels da arte que ficam
             acima do próprio hex (montanha invadindo a fileira de trás)
   camadas acima da âncora (Decals etc.), pencil, badges, markers
   ```
   Um shader descarta os pixels dentro do hex do próprio tile (local do pixel no tile calculado via
   `UV` + grade do atlas, passada por uniform). Só liga quando a região do tile é maior que o `tile_size`.
   **Por que não y-sort:** y-sort exige intercalar pedaços de caminho entre fileiras de tiles na mesma
   árvore de canvas. Na fase 3 o chão vira uma textura de SubViewport, e aí não dá mais para
   intercalar nada. O overhang pass funciona com as duas fases.
   Consequência a aceitar: no **próprio** hex de uma montanha, a rua passa por cima da base dela.
   Só a arte que invade *outros* hexes cobre o caminho.
5. **Campos novos de mod sempre opcionais**, com default "não fornecido" (`-1`, `null`, vetor vazio).
   Recurso antigo sem o campo carrega com o default do script. Testo isso com os samples atuais intocados.
6. **Saves:** `format_version` inteiro + migrações em passos (`1 → 2 → …`). Ausência = 1 (Alpha 0.3).
   Versão maior que a conhecida: carrega o que der, avisa e não crasha.
7. **Estado de runtime em "stores"**, no padrão do `HexDataStore`: `PathStore` é a fonte da verdade
   e emite `path_changed(id)` / `store_reset`. Renderers só reagem a sinais.

---

## Fase 1 — Dados + renderização vetorial (qualquer tileset)

### Modelo de dados
```jsonc
"format_version": 2,
"path_settings": { "seed": 12345, "anchor_layer": "World", "render_mode": "auto" },
"paths": {
  "p_8f3a": {
    "id": "p_8f3a", "name": "Estrada do Rei", "description": "...",
    "kind": "road",              // "road" | "river"
    "anchor": "cell",            // "cell" (centro→centro) | "vertex" (pelas arestas)
    "points": ["(2, 3)", "(3, 3)", ...],          // cell: Vector2i; vertex: trio de Vector2i
    "style_id": "builtin:road",
    "render_mode": "auto",       // fase 2: "auto" | "vector" | "tile"
    "tile_exceptions": {}        // fase 2
  }
}
```
Rua = `anchor: cell`. Rio padrão = `anchor: vertex` (pelas arestas). Na fase 2, rio pode ser `cell` (D2).
`travel_time` / `danger` ficam para depois. `from_dict` ignora chaves desconhecidas e preenche defaults,
então adicionar isso depois não quebra nada.

### Geometria (`HexGeometry`)
Wrapper fino sobre a `TileMapLayer` de referência (pencil): `cell_center`, `corners(cell)`
(média de 3 centros), `vertex_position(trio)`, `vertex_neighbors(trio)` (vértices ligados por aresta),
`shared_edge(a, b)` (os 2 trios comuns), `nearest_vertex(point)`, `cell_at(point)`.
Tudo descontando o `hex_art_offset`. **Zero matemática hex fixa.**

### Renderização vetorial
- **Meandro estável:** cada segmento é deslocado por midpoint displacement com RNG semeado por
  `hash(seed_global, chave_canônica_do_segmento)`. As extremidades ficam fixas.
  Editar um trecho só muda aquele segmento (e, pelo Chaikin, os vizinhos imediatos).
- **Suavização Chaikin** (2–3 iterações; o estilo define).
- **Rio:** `Line2D` de contorno (mais larga, escura) por baixo de `Line2D` de preenchimento.
  `width_curve` cresce de `width_start` (nascente = primeiro ponto) até `width_end` (foz).
- **Rua:** tracejado por comprimento de arco (`dash`, `gap`) desenhado em `_draw`. Linha contínua se `gap = 0`.
- **Ponte automática:** um passo de rua `A→B` cruza rio-de-aresta exatamente quando o rio contém
  `shared_edge(A, B)`. A detecção é combinatória, sem interseção numérica. Para rio ancorado em célula
  (fase 2), uso interseção de segmentos. A ponte é procedural por padrão (tabuleiro + guarda-corpos),
  ou o `bridge_texture` do estilo, orientada pela direção da rua.

### `PathStyle` (`resources/definitions/paths/path_style.gd`)
`id, display_name, kind, color, width, width_start, width_end, outline_color, outline_width,
dash_length, gap_length, texture (opcional, tile ao longo da linha), meander_amplitude,
meander_segments, chaikin_iterations, bridge_texture (opcional)`.
Estilos embutidos em `resources/paths/styles/`: `road`, `trail` (tracejado), `river`, `stream`.
`style_id` desconhecido (ex.: estilo de um mod não instalado) cai no padrão do `kind`.

### Ferramentas de UI
- Modo de ferramenta exclusivo (`NONE / PAINT / ROAD / RIVER / PATH_SELECT / PATH_ERASE`) em
  `GlobalEditorData`. Ao escolher uma ferramenta, o pencil e o placement de marker são desligados
  (e vice-versa). ESC sai.
- **Rua:** clicar/arrastar de hex em hex. Ao entrar numa célula nova adjacente, ela é adicionada.
  Se o arraste pular células, preencho com amostragem da reta via `local_to_map`. Começar em cima da
  ponta de uma rua existente a estende. Voltar para a penúltima célula desfaz o último passo.
- **Rio:** pega o vértice mais próximo do mouse. Se o arraste pular vértices, BFS no grafo de vértices.
- **Apagar:** clique num segmento remove esse segmento (e divide o caminho em dois).
  Shift + clique remove o caminho inteiro.
- **Selecionar:** clique abre um painel com nome, descrição e estilo (no padrão do painel de marker).
- **Undo/redo:** cada stroke vira uma ação no `undo_redo` do editor, com snapshot antes/depois do(s)
  `PathData` afetado(s): `PathStore.set_path` / `remove_path`.

### Arquivos
Novos:
- `scripts/classes/map_data/path_data.gd` — `PathData` (to_dict/from_dict)
- `scripts/classes/map_data/map_migrations.gd` — `format_version` + passos de migração
- `scripts/classes/hex_geometry.gd` — `HexGeometry`
- `scenes/ui/hex_map_editor/path_store.gd` — `PathStore`
- `scenes/ui/hex_map_editor/paths/path_renderer.gd` — interface base
- `scenes/ui/hex_map_editor/paths/vector_path_renderer.gd`
- `scenes/ui/hex_map_editor/paths/path_tools.gd` — input, strokes, undo
- `scenes/ui/hex_map_editor/paths/overhang_pass.gd` + `resources/shaders/tile_overhang.gdshader`
- `scenes/ui/hex_map_editor/paths/path_panel.{tscn,gd}` — botões das ferramentas + dados do caminho
- `resources/definitions/paths/path_style.gd`, `resources/paths/styles/*.tres`
- `tests/` — scripts headless (`extends SceneTree`): round-trip de serialização, migração de
  fixture 0.3, geometria (cantos/vértices) nos dois tilesets. Rodam com
  `godot --headless --script res://tests/run_all.gd`.

Alterados:
- `map_data.gd` (`paths`, `path_settings`, `format_version`, chama migração)
- `map_data_manager.gd` (salvar/carregar/limpar caminhos)
- `hex_map_editor.gd` (exclusividade de ferramenta e ESC; o input de pintura respeita o modo)
- `hex_map_editor.tscn` (nós `PathStore`, `Paths`, `Overhang`, painel)
- `global_editor_data.gd` (`path_store`, `active_tool`)
- `signal_bus.gd` (`path_selected`, `path_dismissed`)
- `map_tileset_configuration.gd` (`hex_art_offset` opcional, ver 1.5)

### 1.5 Spike inicial (antes de construir em cima)
1. **Alinhamento arte × célula:** desenho os cantos via `HexGeometry` por cima dos dois tilesets e tiro
   screenshot. Se a arte estiver deslocada (esperado: sim), adiciono
   `@export var hex_art_offset := Vector2.INF` (INF = automático) em `MapTilesetConfiguration`.
   O automático estima pelo excesso de altura da região (`(region.y - tile_size.y) / 2` quando
   `texture_origin == 0`) e é refinado no spike. Mods antigos ficam no automático.
   *Não* mexo no alinhamento da pintura de tiles existente (seria outra mudança de comportamento),
   só registro aqui.
2. **Shader de overhang:** confirmar que dá para recuperar a posição local do pixel no tile a partir
   de `UV` numa `TileMapLayer` (grade uniforme do atlas). Plano B: gerar, por tileset, um atlas
   "só overhang" em runtime (Image com o hex apagado) e usar num TileSet espelho.

### Pronto quando
- Dá para desenhar, salvar, reabrir e desfazer/refazer ruas e rios no **David (pointy)** e no **example (flat)**.
- Rio e rua passam por baixo da arte que invade a fileira de trás.
- Os 4 saves Alpha 0.3 abrem sem erro novo. Salvar de novo grava `format_version: 2` e reabre igual.
- Testes headless passando.

---

## Fase 2 — Caminhos com os tiles do mod (autotiling)

### Campos opcionais em `MapTilesetConfiguration`
```gdscript
@export var road_terrain_set: int = -1
@export var road_terrain: int = -1
@export var river_terrain_set: int = -1
@export var river_terrain: int = -1
@export var path_styles: Array[PathStyle] = []   # estilos extras do mod (opcional)
```
`-1` = "o mod não fornece". Valido na carga: terrain set inexistente vira `-1` com warning, sem crash.

### `TilePathRenderer`
- Desenha numa `TileMapLayer` **dedicada** (`PathTiles`), na mesma posição dos caminhos vetoriais
  na ordem de desenho. Nunca toca nas camadas de bioma.
- **Recomendação (D4):** em vez de deixar o solver do `set_cells_terrain_path/connect` decidir, calculo
  eu a **máscara de conexões** de cada célula (6 bits, a partir do `PathData`) e procuro no TileSet
  o tile cujos *peering bits* do terrain batem com ela. Uso os mesmos metadados de terrain que o modder
  configura no editor do Godot (nada novo para ele aprender). Motivos: é determinístico, não reescreve
  células vizinhas sozinho, permite detectar **"falta essa combinação"** com exatidão e salvar exceções
  por célula. Se você preferir o solver nativo, uso `set_cells_terrain_path` e detecto falta comparando
  os peering bits do resultado. Funciona, mas as exceções ficam frágeis.
- **Combinação faltando:** esse trecho é desenhado em vetor automaticamente e marcado na UI. O usuário
  pode (a) deixar em vetor ou (b) escolher na mão um tile/alternativa daquele atlas. Isso fica salvo em
  `tile_exceptions["(x, y)"] = {source_id, atlas_coords, alternative}`.
- Só caminhos `anchor: cell` vão para tile. Rio de aresta é sempre vetor.

### Escolha de modo
`path.render_mode` (`auto | vector | tile`) > `path_settings.render_mode` do mapa > automático
(tile se o mod declara o terrain daquele `kind`, senão vetor).

### Tilesets de exemplo (D1 — você liberou a troca)
- **example (pixel, flat-top):** terrain de **rua** nas 11 peças da linha 9.
- **David (pointy-top):** terrain de **rio** nas 4 sobreposições (`1:3`, `6:3`, `7:3`, `0:4`).
  São poucas para 6 lados, então várias combinações vão cair no vetor. Isso serve de teste do fallback.
- Configuro os peering bits por script headless (`tools/configure_example_terrains.gd`), conferindo
  cada sprite visualmente, e salvo os `.tres`. Os samples continuam carregando sem os campos novos
  até eu preenchê-los.

### Arquivos
Novos: `scenes/ui/hex_map_editor/paths/tile_path_renderer.gd`, `scripts/classes/terrain_mask_index.gd`
(índice máscara → tile por terrain), `tools/configure_example_terrains.gd`.
Alterados: `map_tileset_configuration.gd`, `path_panel` (modo por caminho/mapa, lista de exceções),
`path_data.gd`, `resources/tilesets/example_tileset.tres`, `resources/tilesets/david_baumgart_packed.tres`,
`samples/*.tres`.

### Pronto quando
- No **example**, ruas saem com a arte do tileset. Rios caem no vetor.
- No **David**, rios de centro usam as 4 peças onde a combinação existe e caem no vetor no resto,
  com indicação na UI. Ruas caem no vetor.
- Um mod antigo (pck sem os campos novos) carrega e vai tudo para o vetor.
- Forçar vetor/tile por mapa e por caminho funciona e persiste.

---

## Fase 3 — Suavização entre biomas (opcional, desligável)

### Pipeline
1. **SubViewport do chão:** compartilha o `world_2d` principal, tem câmera sincronizada com a do
   editor e `canvas_cull_mask` só com as camadas de chão (via `visibility_layer`). Com a suavização
   ligada, a viewport principal deixa de desenhar o chão direto e mostra a textura do SubViewport com
   o shader. *Spike:* confirmar como o `visibility_layer` se comporta em filhos de `TileMapLayer`.
   Plano B: espelhar as células numa cópia dentro do SubViewport (sincronizada pelo `map_cells_changed`, que já existe).
2. **Máscara de distância à borda:** um TileSet "fantasma" criado em runtime com mesmo `tile_shape`,
   `tile_layout`, `tile_offset_axis` e `tile_size` do mod, com **um** tile gerado por `Image`
   (gradiente centro→borda calculado a partir dos cantos via `HexGeometry`, nada fixo). É pintado em
   toda célula ocupada, num segundo SubViewport.
3. **Shader:** onde a máscara diz "longe da borda", lê o chão direto (miolo intacto). Na faixa da
   borda, desloca a leitura com ruído em **coordenadas de mundo** (não "nada" com o pan da câmera).
   Opcional: um leve sangramento de cor numa faixa estreita.
4. O **overhang pass** da fase 1 continua por cima e não sofre warp. Montanhas não ficam tremidas.

### Metadados (todos opcionais)
Custom data layers no TileSet: `biome: String`, `is_water: bool`, `blend_color: Color`.
- Sem `blend_color`: cor média do tile calculada no atlas (só pixels dentro do hex, ponderada por alpha),
  em cache por tileset.
- Sem `is_water`: heurística pela cor média (azul dominante + saturação). O lint mostra que foi
  heurística, e dá para desligar.
- **Linha de costa / água rasa:** nas arestas entre água e não-água, desenho no overlay vetorial
  (reaproveitando o código de polyline da fase 1) uma faixa de água rasa com gradiente e um traço de costa.

### UI e persistência
Toggle e slider de intensidade, salvos como **preferência do usuário** (`user://settings.cfg`), fora do
mapa. Ligar ou desligar não altera nenhum dado salvo.

### Arquivos
Novos: `scenes/ui/hex_map_editor/blend/ground_blend.{gd,tscn}`, `scripts/classes/edge_mask_tileset.gd`,
`scripts/classes/tile_color_cache.gd`, `resources/shaders/biome_blend.gdshader`,
`scenes/ui/hex_map_editor/blend/coastline_overlay.gd`, `scripts/autloads/user_settings.gd` (ou dentro de `GlobalEditorData`).
Alterados: `hex_map_editor.tscn` (nós + controles), `project.godot` (autoload, se for separado).

### Pronto quando
- Ligar/desligar e mudar a intensidade não muda o JSON salvo (testo com diff).
- Funciona no David e no example. O miolo dos hexes fica idêntico (comparo pixels no centro de um
  screenshot com e sem).
- Costa aparece com `is_water` declarado e também pela heurística.

---

## Fase 4 — Ferramentas para quem faz mod

- **Mod lint** (botão no seletor de tileset): tabela "recurso → o mod fornece? → o que será usado".
  Cobre terrains de rua/rio (e cobertura de combinações: *"rio: 4/64 máscaras, o resto em vetor"*),
  custom data (`biome`, `is_water`, `blend_color`), `path_styles`, `hex_art_offset` (manual/automático)
  e se o overhang pass está ativo.
- **README de modding** atualizado com os campos novos e os fallbacks.
- **Template de mod** em `templates/mod_template/`: `mod_info.tres`, config com todos os campos,
  TileSet com as custom data layers e os terrain sets de rua/rio já criados, e um README passo a passo
  até o `.pck`.

---

## Como vou testar em cada fase
- Testes headless (`tests/run_all.gd`) para dados, migração e geometria nos dois tilesets.
- Rodar o projeto no Godot 4.7 e capturar screenshots dos dois tilesets (com um hook de debug
  temporário ou interação manual), comparando o antes e o depois.
- Abrir as cópias dos 4 saves Alpha 0.3.
- Ao fim de cada fase: relatório do que verifiquei, do que não consegui verificar e do que ficou faltando.

## Fora do escopo (anotado para depois)
Tempo de viagem e perigo por caminho, afluentes/junção de rios, exportar imagem com caminhos,
corrigir o alinhamento da pintura de tiles com `hex_art_offset`.

---

## Decisões (resolvidas em 2026-11-24)

- **D1 — Tilesets de exemplo da fase 2:** ruas por tile no example, rios por tile no David.
- **D2 — Âncora do rio:** suportar os dois. Padrão `vertex` (pelas arestas, como outras ferramentas);
  se o mod fornecer tiles de rio, o usuário pode optar por `cell` + tiles.
- **D3 — Ordem de desenho:** overhang pass. É experimental, vamos iterar se precisar.
- **D4 — Autotiling:** máscara calculada por nós sobre os peering bits do terrain.
- **D5 — WIP:** já estava commitado; trabalho na branch `feature/paths`.

---

## Status da Fase 1 (2026-11-24)

**Feito:** `PathData` + `format_version` 2 com migração; `HexGeometry` (só `map_to_local`/`local_to_map`/
`get_surrounding_cells`); `PathStore`; `VectorPathRenderer` (meandro por semente, Chaikin, rio afinando,
tracejado por arco); pontes automáticas; `PathStyle` + 4 estilos embutidos; ferramentas Road/River/Select/Erase
com undo/redo; painel inferior; overhang pass; `hex_art_offset` opcional (automático por padrão, override
`(0, 8)` no sample pixel-art, medido no atlas).

**Testes** (Godot 4.7):
- `godot --headless --path . res://tests/run_all.tscn` → 138 checks (geometria nos 2 tilesets, meandro estável,
  overhang, round-trip, migração de fixture 0.3, formato mais novo). `HEXFORGE_EXTRA_SAVES=<pasta>` valida
  saves reais.
- `E2E_OUT=<pasta> godot --path . res://tests/e2e_paths.tscn` → 66 checks no editor real (SubViewport + eventos
  de mouse): desenhar, ponte, overhang, undo/redo, salvar/novo/abrir (centerline idêntica), apagar/dividir,
  selecionar + estilo pelo painel, rio pelo centro, exclusividade pencil × ferramenta.
- `tests/e2e_load_snapshot.tscn` → screenshot de um save, usado para comparar `main` × branch.

**Mudanças de comportamento fora dos caminhos:**
- Undo/redo agora funciona sem pencil selecionado; usa o evento (não dispara 2× no mesmo frame); ignora
  ctrl+z enquanto digita em campo de texto.
- Novo mapa / abrir mapa limpam o histórico de undo (antes, desfazer após abrir aplicava em tilemaps liberados).
- O overhang pass também roda em mapas sem caminhos. Em mapas antigos isso muda ~0,4% dos pixels: arte alta
  que o `TileMapLayer` desenhava por baixo da fileira de trás (copas, vilas) agora fica por cima, que é a ordem certa.

**Pendências / limitações conhecidas:**
- No hex da própria montanha o caminho passa por cima da base (D3).
- Rua horizontal em flat-top vira onda (vizinhos laterais a ±30°) — esperado da geometria.
- Ponte só para rio de aresta; rio por centro × rua fica para a fase 2 (interseção geométrica).
- Nome/descrição/estilo editados no painel não entram no undo (igual ao painel de hex e de marker).
- Camadas abaixo da âncora com arte alta: o overhang delas vai por cima da âncora (caso raro).

---

## Status das Fases 2, 3 e 4 (2026-11-24)

### Fase 2 — tiles do mod
- `TerrainMaskIndex` (máscara de lados exata a partir dos peering bits; lados via `get_neighbor_cell`),
  `TilePathRenderer` (camadas `RoadTiles`/`RiverTiles` dedicadas, exceções por hex, stubs vetoriais onde falta tile).
- Modo por caminho e por mapa (`Auto / Vector / Tiles`), escolha de tile à mão e "Vector here", tudo com undo.
- Samples: example → terrain "Road" nas 11 peças (só usam os 4 lados diagonais: cobrem 11/63, retas verticais e pontas
  caem no vetor). David → terrain "River" em 3 peças + variantes espelhadas com `texture_origin` corrigido: 10/63.
  Gerado por `tools/configure_sample_terrains.gd` (reexecutável; restaura os uids que o modo `--script` apaga).
- Pontes também para rio pelo centro × rua (células compartilhadas).

### Fase 3 — suavização
- **Mudança vs. plano:** usei o "plano B" — as camadas de chão são espelhadas em SubViewports com mundo próprio
  (sem depender de `canvas_cull_mask`), e as originais ficam ocultas só enquanto a suavização está ligada.
- Nos espelhos, tiles altos usam o shader do overhang invertido (só o corpo do hex), para o warp não deformar picos;
  o overhang pass continua desenhando os picos nítidos por cima.
- Máscara de borda por TileSet fantasma (`EdgeMaskTileset`), shader `biome_blend` (ruído em coordenadas de mundo,
  só na faixa da borda, leitura transparente mantém o pixel original).
- `TileColorCache`: `is_water` / `blend_color` / `biome` da custom data, com fallback por cor média.
  `CoastlineOverlay`: água rasa + linha de costa, meandro estável por semente.
- Preferências em `user://settings.cfg`; **suavização e costa começam desligadas**, então mapas antigos ficam idênticos.
- Verificado: ligar/desligar não muda o JSON salvo; centros dos hexes idênticos pixel a pixel nos dois tilesets;
  desligar devolve exatamente a imagem original; com intensidade 0 o David difere em ~0,3% dos pixels (bordas
  semitransparentes de arte que sai do hex, misturadas sobre fundo diferente).

### Fase 4 — ferramentas de modder
- `ModLint` + botão **Check mod** no seletor de tileset (tabela recurso / status / fallback).
- README de modding atualizado (campos opcionais, terrains, custom data, fallbacks).
- `templates/mod_template/`: projeto Godot independente (ignorado pelo projeto principal) com mod completo e preset
  "Mod PCK" que **exclui** os scripts de definição (um mod não sobrescreve os scripts do jogo). Gerado por
  `tools/build_mod_template.gd`; um teste garante que as cópias dos scripts batem com as do jogo.
- `MapTilesetConfiguration.provides_path_tiles(kind)` virou `provides_road_tiles()` / `provides_river_tiles()`
  para o script não depender de `PathData` (ele é copiado para projetos de mod).

### Testes
```
godot --headless --path . res://tests/run_all.tscn          # 222 checks
#   HEXFORGE_EXTRA_SAVES=<pasta de saves>  HEXFORGE_TEMPLATE_PCK=<pck do template>  HEXFORGE_TEST_TMP=<pasta temp>
E2E_OUT=<pasta> godot --path . res://tests/e2e_paths.tscn    # 113 checks, precisa de display
```
Inclui: mod antigo empacotado em `.pck` (sem campos novos) carregado como o `ModLoader` faz; pck exportado do
template carregado e passando no lint.

### Pendências conhecidas
- Arte do template é placeholder geométrico.
- `biome` só aparece no lint por enquanto.
- O teste e2e grava as preferências de suavização em `user://settings.cfg` (restaura os valores no fim).
- README ainda diz Godot 4.6; o projeto está salvo em 4.7.
