---
name: onboard-partner-restaurant
description: Onboarda restaurante parceiro a partir de pasta com info.yaml + produtos.csv + fotos cruas. Trata imagens (rembg + resize WebP), gera descrições PT-PT apetitosas, categoriza pratos, insere via Edge Fn register-partner. Dry-run por defeito.
metadata:
  type: onboarder
  category: partner
  depends_on: bora-knowledge
  uses_edge_fns: [register-partner, upload-restaurant-asset]
  version: 1.0.0
  versao: 1.0
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: pre-telemetria (rollout 2026-07-10)
---

# Onboard Partner Restaurant

Cria 1 restaurante parceiro no Bora a partir de uma pasta local com dados crus.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md` — regras parceiro (10+5+5%)
2. `bora-knowledge/knowledge/07-database-key-tables.md` — schema `restaurants`/`products`
3. `bora-knowledge/knowledge/08-edge-functions.md` — payloads `register-partner` + `upload-restaurant-asset`
4. `bora-knowledge/knowledge/10-protected-zones.md` — zonas intocáveis

> A skill **lê** estes ficheiros em runtime (`_shared.load_knowledge()`) e **falha cedo**
> se a bora-knowledge não existir.

## Input esperado
Pasta `bora_app/.claude/.ai/onboard/<nome-restaurante>/` com:
- `info.yaml` (obrigatório) — ver `templates/info.yaml.template`
- `logo.png|jpg` (obrigatório)
- `capa.png|jpg` (obrigatório, hero image)
- `produtos.csv` (obrigatório, UTF-8) — ver `templates/produtos.csv.template`
- `fotos/` (pasta; nome dos ficheiros deve dar match com a coluna `fotos` do CSV)

## Modos
- **DEFAULT (dry-run)**: valida tudo, processa imagens, gera previews e descrições,
  escreve relatório em `<pasta>/_preview/` — **NÃO escreve em Supabase**.
- **`--commit`**: aplica em Supabase via Edge Fns. Transacional com rollback.

```bash
# dry-run (default)
python scripts/insert_supabase.py --dir ".claude/.ai/onboard/belmonte-grill"
# aplicar a sério
python scripts/insert_supabase.py --dir ".claude/.ai/onboard/belmonte-grill" --commit
```

## Pipeline (10 passos)
1. `validate_info.py` — valida `info.yaml` (NIF mód-11, IBAN `^PT\d{21}$`, email, telefone PT) e `produtos.csv`.
2. `geocode.py` — morada → lat/lng (Google Maps); valida bounding box PT continente.
3. `process_images.py` — logo + capa + fotos: rembg (fundo) + resize WebP thumb 200 / card 600 / hero 1200.
4. `generate_descriptions.py` — descrição PT-PT apetitosa (1-2 frases) por prato sem descrição.
5. `categorize_products.py` — categoria sugerida (entrada/principal/sobremesa/bebida).
6. (dry-run) escreve `_preview/` com tudo + relatório; pára aqui se sem `--commit`.
7. `insert_supabase.py` — autentica como o parceiro (cria/obtém auth user) → JWT.
8. Chama `register-partner` (JSON do `info.yaml`) → `restaurant_id` (approval_status='pending').
9. `upload-restaurant-asset` para logo (kind=`logo`) + capa (kind=`hero`) + docs → UPDATE `photo_url`/`hero_image_url`.
10. INSERT produtos em `products` (PostgREST como parceiro). Rollback se algo falhar.

## Salvaguardas
- NÃO toca `pricing_service` nem `bora_tokens`.
- NÃO altera fotos cruas originais (só processa cópias em `_preview/`).
- Rollback transacional: se INSERT falhar, apaga restaurante criado + assets.
- `approval_status='pending'`, `is_online=false` — admin aprova manualmente.
- `is_partner=true` (restaurante). Preço dos produtos é **puro** (markup é runtime).

## Dependências
Ver `requirements.txt` + `README.md`. **Não instalar nesta sessão.**

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
