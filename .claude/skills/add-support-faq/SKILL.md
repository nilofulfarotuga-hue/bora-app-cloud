---
name: add-support-faq
description: Adiciona uma FAQ ao RAG do support-chatbot (tabela support_knowledge_chunks) e dispara reindex-knowledge para gerar o embedding. Valida que a FAQ não contém promessas $ nem instruções de cancelamento/refund (essas escalam a humano). Dry-run default; --commit grava.
metadata:
  type: support
  category: knowledge
  depends_on: bora-knowledge
  uses_edge_fns: [reindex-knowledge]
  version: 1.0.0
  versao: 1.0
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: pre-telemetria (rollout 2026-07-10)
---

# Add Support FAQ

Acrescenta uma FAQ à base de conhecimento RAG do agente de suporte. **Não há tabela
`support_faqs`** — as FAQs vivem como chunks em **`support_knowledge_chunks`** (534 chunks,
RAG via Gemini embeddings 768d). O embedding é gerado pela Edge Fn **`reindex-knowledge`**.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/06-flows.md` (suporte)
2. `bora-knowledge/knowledge/08-edge-functions.md` (reindex-knowledge)
3. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`,
e (p/ embedding) **JWT de admin** (`BORA_ADMIN_JWT` ou `BORA_ADMIN_EMAIL`+`BORA_ADMIN_PASSWORD`)
— `reindex-knowledge` exige `is_admin()` + `GEMINI_API_KEY` no servidor.

## Uso
```bash
python scripts/list_faqs.py                                        # chunks FAQ/knowledge atuais
python scripts/add_faq.py --question "Como acompanho o meu pedido?" \
  --answer "No separador Entrega vês o estado em tempo real." --category orders   # dry-run
python scripts/add_faq.py --question "..." --answer "..." --category orders --commit
```

## Modos
- **DEFAULT (dry-run)**: valida + mostra o chunk que seria inserido. NÃO escreve.
- **`--commit`**: INSERT em `support_knowledge_chunks` (source_type `knowledge`, embedding NULL)
  → chama `reindex-knowledge {mode:'pending'}` para embeber (best-effort) → `admin_audit_log`.

## Salvaguardas (validação no add)
- **Bloqueia** respostas com promessas monetárias ou instruções de cancelamento/refund
  (`reembolso`, `estorno`, `devolvemos`, `cancelar o pedido`, `€…garantido`, …) → essas situações
  **escalam a humano**, não vão para FAQ. Override consciente: `--force-sensitive` (desaconselhado).
- Dedup por `content_hash` (não insere FAQ idêntica).
- NÃO reescreve a lógica do agente. Só acrescenta conhecimento.
- Se o embedding falhar (sem admin/GEMINI), a FAQ fica gravada mas **pendente de reindex**
  (correr `reindex-knowledge` depois) — o relatório avisa.

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
