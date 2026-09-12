# README — add-support-faq

Acrescenta uma FAQ ao RAG do agente de suporte (`support_knowledge_chunks`).

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`,
+ JWT de admin (`BORA_ADMIN_JWT` ou `BORA_ADMIN_EMAIL`+`BORA_ADMIN_PASSWORD`) para o embedding.

## Fluxo
```bash
python scripts/list_faqs.py
python scripts/add_faq.py --question "..." --answer "..." --category orders          # dry-run
python scripts/add_faq.py --question "..." --answer "..." --category orders --commit  # grava + reindex
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `audit_log` + `get_admin_jwt` |
| `list_faqs.py` | lista chunks (source_type faq/knowledge) recentes |
| `add_faq.py` | valida → INSERT chunk → invoca reindex-knowledge (embedding) → audit |

## Modelo de dados
- Tabela: **`support_knowledge_chunks`** (`source_file, source_type, section_title, chunk_text,
  char_count, content_hash, embedding`). NÃO existe `support_faqs`.
- Embedding: Edge Fn **`reindex-knowledge`** (`{mode:'pending', max_chunks}`), admin-only, Gemini 768d.

## Salvaguardas
- Bloqueia respostas com promessas $ / instruções de refund/cancelamento (escalam a humano).
- Dedup por `content_hash`. Embedding pendente se sem admin/GEMINI (correr reindex depois).
- **Admin UI** (pendência): considerar vista admin para o Danilo editar FAQs — anotado, não criado.
