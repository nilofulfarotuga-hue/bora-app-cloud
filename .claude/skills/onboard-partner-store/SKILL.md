---
name: onboard-partner-store
description: Onboarda loja parceira (retail — electrónica, vestuário, casa, beleza, brinquedos) a partir de pasta com info.yaml + produtos.csv + fotos. Trata imagens, gera descrições PT-PT estilo retail, categoriza, insere via Edge Fn register-partner (category=store). Dry-run por defeito.
metadata:
  type: onboarder
  category: partner
  depends_on: bora-knowledge
  uses_edge_fns: [register-partner, upload-restaurant-asset]
  version: 1.0.0
---

# Onboard Partner Store (loja / retail)

Cria 1 **loja** parceira no Bora. Mesmo esqueleto que `onboard-partner-restaurant`,
com variações de retail. A categoria "Lojas" já existe na home (ver bora-knowledge 02)
mas não tinha fluxo de onboarding — esta skill resolve isso.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md`
2. `bora-knowledge/knowledge/07-database-key-tables.md`
3. `bora-knowledge/knowledge/08-edge-functions.md`
4. `bora-knowledge/knowledge/10-protected-zones.md`

## Input esperado
Pasta `bora_app/.claude/.ai/onboard/<nome-loja>/` com `info.yaml`, `logo.png|jpg`,
`capa.png|jpg`, `produtos.csv` (UTF-8), `fotos/`. Ver `templates/`.

## Diferenças vs restaurant
- `info.yaml`: `category: "loja"`, `cuisine_type: ""` (não aplicável).
- `produtos.csv`: colunas extra opcionais `marca` e `unidade` (un/kg/lt).
- `categorize_products.py`: categorias **loja** — electrónica, vestuário, casa,
  beleza, brinquedos, outros.
- `generate_descriptions.py`: estilo **retail** (factual, especificações), não gastronómico.
  Ex.: "Auriculares Bluetooth com cancelamento de ruído ativo e 30h de bateria."
- `takeaway_enabled` / `reservations_enabled`: mantêm-se **false**.
- `register-partner` é chamado com `category="store"`.

## Modos
- **DEFAULT (dry-run)**: valida, processa imagens, gera previews — não escreve em Supabase.
- **`--commit`**: aplica via Edge Fns; transacional com rollback.

```bash
python scripts/insert_supabase.py --dir ".claude/.ai/onboard/worten-guarda"            # dry-run
python scripts/insert_supabase.py --dir ".claude/.ai/onboard/worten-guarda" --commit   # aplicar
```

## Pipeline (10 passos)
Idêntico a restaurant (validate → geocode → process_images → descriptions →
categorize → preview/commit). Ver `README.md`.

## Salvaguardas
- NÃO toca `pricing_service` nem `bora_tokens`. NÃO altera fotos cruas.
- Rollback transacional. `approval_status='pending'`, `is_online=false`.
- `is_partner=true`. Preço **puro**.

## Dependências
Ver `requirements.txt` + `README.md`. **Não instalar nesta sessão.**
