# README — onboard-partner-restaurant

Skill CLI para onboardar **um restaurante parceiro** no Bora App.

## Instalação (uma vez)
```bash
cd bora_app/.claude/skills/onboard-partner-restaurant
python -m venv .venv
.venv\Scripts\activate          # Windows (PowerShell: .venv\Scripts\Activate.ps1)
pip install -r requirements.txt
```

## Variáveis de ambiente (`.env` na raiz do skill ou via projeto)
| var | uso |
|-----|-----|
| `SUPABASE_URL` | https://ojykpzwqrtusfeakzrna.supabase.co |
| `SUPABASE_SERVICE_ROLE_KEY` | criar/obter auth user do parceiro (admin) |
| `SUPABASE_ANON_KEY` | invocar Edge Functions |
| `GOOGLE_MAPS_API_KEY` | geocoding morada → lat/lng |
| `OPENAI_API_KEY` | descrições PT-PT (opcional; sem ela usa fallback simples) |

> Estas chaves vivem em `backend/.env` / `scripts/scraper/.env` (gitignored). Nunca commitar.

## Uso
```bash
# 1. Preparar pasta a partir dos templates
mkdir .claude/.ai/onboard/belmonte-grill
cp templates/info.yaml.template     .claude/.ai/onboard/belmonte-grill/info.yaml
cp templates/produtos.csv.template  .claude/.ai/onboard/belmonte-grill/produtos.csv
# + logo.png, capa.png, fotos/

# 2. Dry-run (default — não escreve em Supabase)
python scripts/insert_supabase.py --dir ".claude/.ai/onboard/belmonte-grill"

# 3. Rever _preview/relatorio.md; depois aplicar
python scripts/insert_supabase.py --dir ".claude/.ai/onboard/belmonte-grill" --commit
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | env, logging, leitura da bora-knowledge, helpers Supabase/Edge Fn |
| `validate_info.py` | valida info.yaml + produtos.csv (NIF, IBAN, email, telefone, coords) |
| `geocode.py` | morada → lat/lng (Google Maps) |
| `process_images.py` | rembg + resize WebP (thumb 200 / card 600 / hero 1200) |
| `generate_descriptions.py` | descrições PT-PT apetitosas por prato |
| `categorize_products.py` | categoria sugerida (entrada/principal/sobremesa/bebida) |
| `insert_supabase.py` | orquestrador: pipeline + Edge Fns + rollback (dry-run default) |

## Notas
- Em erro a meio do `--commit`, o script faz rollback e imprime como retomar.
- `approval_status='pending'` — o restaurante só fica visível após aprovação admin.
- Idioma user-facing: **PT-PT**. Comentários/relatórios: PT-BR ok.
