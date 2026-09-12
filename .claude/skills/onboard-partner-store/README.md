# README — onboard-partner-store

Skill CLI para onboardar **uma loja parceira** (retail) no Bora App.
Mesmo funcionamento que `onboard-partner-restaurant` — ver esse README para detalhe
de instalação e variáveis de ambiente (idênticas).

## Reutilização de código (DRY)
Os scripts `_shared.py`, `geocode.py` e `process_images.py` **reutilizam** os do
`onboard-partner-restaurant` (skills co-localizadas em `.claude/skills/`). São shims
finos — a lógica vive numa só fonte. Variam apenas:
- `validate_info.py` — exige `category: loja`.
- `categorize_products.py` — categorias retail (electrónica, vestuário, casa, beleza, brinquedos, outros).
- `generate_descriptions.py` — estilo retail (especificações).
- `insert_supabase.py` — `register-partner` com `category="store"`; produtos com `marca`/`unidade`.
- `templates/` — info.yaml (loja) + produtos.csv (com `marca`,`unidade`).

## Uso
```bash
cp templates/info.yaml.template     .claude/.ai/onboard/worten-guarda/info.yaml
cp templates/produtos.csv.template  .claude/.ai/onboard/worten-guarda/produtos.csv
# + logo.png, capa.png, fotos/
python scripts/insert_supabase.py --dir ".claude/.ai/onboard/worten-guarda"           # dry-run
python scripts/insert_supabase.py --dir ".claude/.ai/onboard/worten-guarda" --commit  # aplicar
```
