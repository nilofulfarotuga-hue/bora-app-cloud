---
name: onboard-partner-pharmacy
description: Onboarda farmácia/parafarmácia parceira a partir de pasta com info.yaml + produtos.csv + fotos. Valida licença INFARMED, bloqueia medicamentos sujeitos a receita (só OTC), adiciona disclaimer obrigatório, gera descrições PT-PT sem claims médicas, insere via Edge Fn register-partner (category=pharmacy). Dry-run por defeito.
metadata:
  type: onboarder
  category: partner
  depends_on: bora-knowledge
  uses_edge_fns: [register-partner, upload-restaurant-asset]
  version: 1.0.0
---

# Onboard Partner Pharmacy (farmácia)

Cria 1 **farmácia** parceira no Bora. A categoria "Farmácia" já existe na home
(ver bora-knowledge 02) mas não tinha fluxo de onboarding — esta skill resolve isso.

## ⚠️ Regras específicas de farmácia
- **Só OTC** (venda livre). Produtos sujeitos a receita médica são **bloqueados** e
  flagados para revisão manual (`validate_info.py` deteta palavras-chave).
- **Disclaimer obrigatório** em cada produto: *"Em caso de dúvida, consulte o farmacêutico."*
- **Sem claims médicas** nas descrições (estilo informativo, posologia factual).
- `info.yaml` exige `licenca_infarmed`.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md`
2. `bora-knowledge/knowledge/07-database-key-tables.md`
3. `bora-knowledge/knowledge/08-edge-functions.md`
4. `bora-knowledge/knowledge/10-protected-zones.md`

## Input esperado
Pasta `bora_app/.claude/.ai/onboard/<nome-farmacia>/` com `info.yaml`, `logo.png|jpg`,
`capa.png|jpg`, `produtos.csv` (UTF-8), `fotos/`. Ver `templates/`.

## Diferenças vs restaurant/store
- `info.yaml`: `category: "farmacia"`, campo extra `licenca_infarmed` (obrigatório).
- `categorize_products.py`: medicamentos_otc, cosmetica, higiene, suplementos, bebés, outros.
- `generate_descriptions.py`: informativo, **sem claims**; acrescenta disclaimer.
- `validate_info.py`: bloqueia palavras-chave de receita (antibiótico, receita,
  "medicamento sujeito", etc.) → flag manual.
- `register-partner` com `category="pharmacy"`. takeaway/reservations = false.

## Modos
```bash
python scripts/insert_supabase.py --dir ".claude/.ai/onboard/wells-guarda"           # dry-run
python scripts/insert_supabase.py --dir ".claude/.ai/onboard/wells-guarda" --commit  # aplicar
```

## Salvaguardas
- NÃO toca `pricing_service` nem `bora_tokens`. NÃO altera fotos cruas.
- Produtos de receita → NÃO inseridos; listados no relatório para revisão.
- Disclaimer adicionado à descrição de **todos** os produtos.
- Rollback transacional. `approval_status='pending'`, `is_online=false`. `is_partner=true`.

## Dependências
Ver `requirements.txt` + `README.md`. **Não instalar nesta sessão.**
