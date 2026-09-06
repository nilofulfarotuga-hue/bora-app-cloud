# README — onboard-partner-pharmacy

Skill CLI para onboardar **uma farmácia/parafarmácia parceira** no Bora App.
Instalação e variáveis de ambiente idênticas a `onboard-partner-restaurant`.

## Reutilização de código (DRY)
`_shared.py`, `geocode.py`, `process_images.py` reutilizam o motor do
`onboard-partner-restaurant` (skills co-localizadas). Variam:
- `validate_info.py` — exige `category: farmacia` + `licenca_infarmed`; **bloqueia produtos de receita**.
- `categorize_products.py` — medicamentos_otc / cosmetica / higiene / suplementos / bebés / outros.
- `generate_descriptions.py` — informativo, sem claims; **disclaimer** anexado.
- `insert_supabase.py` — `register-partner` com `category="pharmacy"`; produtos de receita NÃO inseridos.
- `templates/` — info.yaml (com `licenca_infarmed`) + produtos.csv.

## ⚠️ Conformidade
- Apenas **OTC** (venda livre). Receita médica → bloqueado + relatório de revisão manual.
- Disclaimer obrigatório: *"Em caso de dúvida, consulte o farmacêutico."*
- Confirmar `licenca_infarmed` válida antes de aprovar (admin).

## Uso
```bash
cp templates/info.yaml.template     .claude/.ai/onboard/wells-guarda/info.yaml
cp templates/produtos.csv.template  .claude/.ai/onboard/wells-guarda/produtos.csv
python scripts/insert_supabase.py --dir ".claude/.ai/onboard/wells-guarda"           # dry-run
python scripts/insert_supabase.py --dir ".claude/.ai/onboard/wells-guarda" --commit  # aplicar
```
