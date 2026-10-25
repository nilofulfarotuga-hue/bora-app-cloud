---
name: bora-studio-decupagem
description: Transforma um roteiro (roteiros/*.md) na decupagem estruturada do BoraStudio — atos -> cenas -> shots com falas, emoções, câmera — emitindo um <roteiro>.decupagem.json que o carregar_decupagem.py insere na bíblia de produção (producao.db). Use quando o Danilo disser "PRODUZIR roteiros/x.md" ou pedir para decupar um roteiro.
type: producao
---

# Skill: Decupagem (BoraStudio)

A decupagem é **teu** trabalho (Claude Code), não de um script: leres o roteiro e produzires
um JSON que o loader determinístico insere no DB. Depois o pipeline mecânico (02→07) corre sozinho.

## O que fazes

1. Lê `roteiros/<nome>.md`.
2. Identifica **personagens** (nome, descrição, espécie, personalidade) e atribui **voz edge-tts**:
   - masculino pt-PT → `pt-PT-DuarteNeural` · feminino pt-PT → `pt-PT-RaquelNeural`
   - (pt-BR: `pt-BR-AntonioNeural` / `pt-BR-FranciscaNeural`)
   - dá a cada personagem uma **paleta** de cores coerente (ver campos por espécie abaixo).
3. Divide em **cenas** (mudança de cenário/tempo). Cada cena tem um `humor_musica`:
   `alegre|calma|tensa|triste|epica`.
4. Divide cada cena em **shots**:
   - **1.º shot de cada cena = `estabelecimento`** (plano largo, sem falas, 2.5–3.5s).
   - Shots de **diálogo**: 1 fala cada (personagem, texto, emoção), duração-alvo 3–8s.
   - **Alterna os planos** para ritmo: `largo` → `medio` → `close` → `medio`…
   - `camera.mov`: `kenburns` (zoom lento) na maioria; `pan` ocasional; `corte` para ênfase.
5. Escreve `roteiros/<nome>.decupagem.json` com o schema abaixo.

## Schema do JSON

```json
{
  "filme": {"titulo": "…", "roteiro_path": "roteiros/x.md", "fps": 24, "largura": 1280, "altura": 720},
  "personagens": [
    {"nome": "Vento", "descricao": "cão rafeiro cor de mel, curioso",
     "voz": "pt-PT-DuarteNeural",
     "paleta": {"corpo": "#c9a06a", "detalhe": "#8a6b3f", "focinho": "#e8d3ad", "linha": "#3a2c17"}}
  ],
  "cenas": [
    {"ordem": 1, "cenario": "encosta da serra da guarda ao entardecer, estrela a cair",
     "humor_musica": "calma",
     "shots": [
       {"ordem": 1, "tipo": "estabelecimento", "personagens": [], "falas": [],
        "camera": {"plano": "largo", "mov": "kenburns"}, "duracao": 3.0},
       {"ordem": 2, "tipo": "dialogo", "personagens": ["Vento"],
        "falas": [{"personagem": "Vento", "texto": "Melra! Viste aquilo?", "emocao": "surpreso"}],
        "camera": {"plano": "medio", "mov": "kenburns"}}
     ]}
  ]
}
```

### Paletas por espécie
- **cão** (`_especie`→cao): `corpo, detalhe(orelhas), focinho, linha`
- **pássaro** (`_especie`→passaro): `corpo, detalhe(asa/tufo), barriga, bico, linha`
- A espécie é inferida da descrição (palavras "pássaro/ave/melro/bico/asa" → passaro; senão cao).

### Emoções válidas
`neutro | feliz | triste | surpreso | curioso | animado | sonhador | doce | zangado`
(o render mapeia feliz/triste/surpreso para sobrancelhas; as outras caem em neutro.)

## Depois de escrever o JSON
Corre: `python scripts/carregar_decupagem.py roteiros/<nome>.decupagem.json`
e segue para o orquestrador `python scripts/bora_studio.py`.

## Regras de ritmo (copiadas do que Glovo/Pixar consagraram para curtas)
- Nunca começar uma cena sem estabelecimento.
- Não deixar 2 closes seguidos do mesmo personagem.
- Duração do shot de diálogo ≈ tamanho da fala; o TTS corrige a duração real no DB.
