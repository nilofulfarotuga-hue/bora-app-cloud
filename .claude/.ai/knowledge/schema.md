---
tema: schema-cortex · escopo: projeto · estado: atual · atualizado: 2026-07-08
---

# 🧩 SCHEMA — Como se mantém o Córtex (Camada 3)

> Fonte única das **regras de trabalho** do Córtex. Funde, sem perder regra:
> `CLAUDE.md` (raiz) + `.claude/skills/ceo-ai/SKILL.md` + `PROTOCOLO.md` + o blueprint da Fase 0.
> Complementa (não substitui) o `INDEX.md` (o *quê*) e o `PROTOCOLO.md` (o *ciclo*).
> **Invariante:** este ficheiro e cada página do Córtex carregam **< ~24 KB**. Passou → partir por sub-tema.

---

## 1. Anatomia do Córtex (onde vive cada coisa)
```
.claude/.ai/knowledge/            ← LADO CÓDIGO (repo, git) = o Córtex
  INDEX.md        ← entry point (o quê existe; lê-se SEMPRE, primeiro)
  PROTOCOLO.md    ← o ciclo ler-antes / handoff-depois
  schema.md       ← este ficheiro (as regras de trabalho)
  inbox/          ← memória DESCARTÁVEL (sessões cruas, experimentos) — regra dos 14 dias (§10)
    _descartado/  ← não promovido em 14d vem para cá (recuperável 30 dias, nunca apagado)
  permanente/     ← factos que valem no tempo (só sobe via handoff ao Bibliotecário)
    semantica/    ← o que É verdade (regras, backend-map, zonas-protegidas, pricing, DNA)
    episodica/    ← o que ACONTECEU (bugs-resolvidos, decisões, auditoria-360)
    procedural/   ← como se FAZ (convenções, licoes/)
  wiki/
    decisoes/     ← ADR: o PORQUÊ de cada decisão (tipo: decisao)
    licoes/       ← memória de experiência; só regras generalizáveis (tipo: licao)
  _tools/         ← cortex_nightly.py — manutenção noturna (dry-run) — o cérebro cuida-se (§9/§10)
  _debt.md        ← cartão de dívida (AUTO-gerado): páginas de baixa confiança (§9)
  log.md          ← proveniência append-only (quem/quando/de-que-lado escreveu)
  sessao/         ← memória de trabalho efémera (gitignored, apagável)
  _arquivo/       ← histórico bruto + mapas de migração (nunca apagar)

bora_app/.obsidian-vault/         ← VAULT CANÓNICO (117+ .md, versionado no git)
  └ é a fonte de notas humanas; espelhado ao VPS (Hermes) — one-way PC→VPS.
```
- **Inbox vs permanente:** `sessao/` é rascunho efémero (dogfooding, sobrevive a relançamentos, é
  gitignored). `permanente/` só recebe factos **verificados** via handoff. Nunca promover de `sessao/`
  para `permanente/` sem passar pelo Bibliotecário.
- **Canónico ≠ velho:** o vault canónico é `bora_app/.obsidian-vault/`. O antigo
  `C:\Users\danil\Desktop\Bora` está **deprecated** (aguarda arquivo no gate). Toda a sync (VPS) e
  referência deve apontar ao canónico. *(Pendência: `INDEX.md` linha ~78 ainda cita o velho — handoff ao Bibliotecário.)*

## 2. Quem escreve (a regra de ouro)
- **Só o agente `bibliotecario-cerebro` escreve no `permanente/`.** Os outros agentes entregam um
  **handoff** no fim da tarefa. Escrita de memória é operação de primeira classe, com gatilho
  explícito (fim de tarefa) — não "o modelo decide sozinho o que lembrar".
- Ciclo de **leitura** (antes): ler `INDEX.md` → carregar **só** os ficheiros do tema → aplicar só
  factos `estado: atual` → **nunca** o Córtex inteiro.
- Ciclo de **escrita** (depois): montar o bloco de handoff e entregá-lo ao Bibliotecário:
  ```
  HANDOFF → bibliotecario-cerebro
  tipo: licao | bug | decisao | facto
  escopo: projeto | agente:<nome>
  tema-alvo: <ficheiro sugerido>
  conteudo: <o facto, apoiado no que aconteceu — com commit/data/entidade>
  ```
  O Bibliotecário **verifica** (8-checagens), faz dedup, marca `superado` se contradizer, grava no
  sítio certo e atualiza o `INDEX.md` se criar/partir ficheiro.

## 3. Frontmatter obrigatório
### 3.1 Hoje (todas as páginas atuais) — manter
```
---
tema: <slug> · escopo: projeto|agente:<nome> · estado: atual|superado (por X, data) · atualizado: YYYY-MM-DD
---
```
### 3.2 Frontmatter de IDENTIDADE (em aplicação — Bloco 1, faseado por batches)
Cada página do Córtex tem (o `bibliotecario-cerebro` carimba em batches; páginas novas nascem já com ele):
```
---
id: <slug único>
tipo: service | conceito | decisao | licao | negocio
origem: [ficheiro/commit/view que comprova]   # sem prova verificável → NAO_VERIFICADO (não inventar)
ultima_confirmacao: <YYYY-MM-DD>
zona: verde | vermelha
confianca: auto              # DERIVADA da data+proveniência — nunca escrita à mão (ver §9)
validade_dias: <opcional; só onde o conhecimento expira>
---
```
- `origem` = prova verificável (o Bibliotecário recusa factos sem origem).
- `zona: vermelha` ⇒ a página descreve dinheiro/segurança ⇒ **Anel D / PROPOSE-ONLY** (ver §4).
- `validade_dias` só onde faz sentido (ex.: um preço de mercado externo expira; o DNA não).
- **Aplicação faseada por batches** (Bloco 1): `permanente/**` primeiro (pelo Bibliotecário); o vault
  e `_importado-velho/` são **arquivo** — carimbam-se depois ou ficam como histórico. Reversível batch a batch.

## 4. Governança por zona × anel (dono de escrita)
Herdado do SOUL/CEO-AI: **qualquer página que descreva zona 🔴 = Anel D (PROPOSE-ONLY)** — o agente
lê e propõe, o Danilo aprova; a Trava bloqueia a edição.

| Tipo de página | Dono de escrita | Anel |
|---|---|---|
| zonas-protegidas, dispatch, pricing, finalizePurchase, bora_tokens, stripe-webhook, RLS orders/wallets/ledger | Claude Code **propõe** | **D 🔴** |
| backend-map, migrations não-financeiras, arquitetura | Claude Code | **A** (não-$) / D se tocar $ |
| negócio (pulso, KPIs, funil, cancelamentos, saúde) | Hermes | **A** (só lê views → reporta) |
| sinais de negócio que sugiram mudança de fluxo/campanha | Hermes **propõe** | **C** (1 toque) |
| conceitos (DNA, glossário, FAQ, benchmarks) | qualquer | **A** (atemporal) |
| `raw/` (fontes brutas) | append-only | **A** (nunca reescrever) |
| `schema.md` / regras de trabalho | Claude Code **propõe** | **C/D** |

**Anéis (do SOUL):** A = autónomo · B = autónomo com aviso · C = propõe (1 toque) · D = 🔴 Lista
Vermelha (dinheiro/RLS/auth/migrations destrutivas/build prod) = PROPOSE-ONLY.

## 5. Regras duras (invioláveis)
- **Invariante ~24 KB** por ficheiro e no índice. Passou → o Bibliotecário parte por sub-tema.
- **Zero perda:** nada sai do Córtex sem ir para `_arquivo/` + entrada no mapa de migração.
- **História não se apaga:** um facto errado marca-se `superado (por X, data)`, não se remove.
- **Frescura:** aplicar só `estado: atual`; um `superado` fica de contexto, não se aplica.
- **Aditivo e reversível** em consolidações (como esta Fase 1A): copiar, não mover o velho; conflito →
  guardar `.doVelho.md` lado a lado; arquivar só no gate com aprovação.

## 6. Do CLAUDE.md (regras de produto que o Córtex preserva)
- **Arquitetura:** Model → Store → Screen. Status **sempre** via enum `OrderStatus` (nunca String):
  `created→preparing→callingDriver→driverAccepted→pickedUp→onTheWay→delivered`.
- **`OrderStore`** compara por **ID** (realtime substitui objetos → identidade de objeto não vale).
- **Validation Gate = SÓ DINHEIRO:** tarefas normais executam ponta-a-ponta; a única travagem é a
  🔴 Lista Vermelha (Stripe/pagamentos/refund/MBWay, preços/taxas/comissões, `finalizePurchase`,
  `bora_tokens`, `platform_settings` financeiros, migrations que alterem valores cobrados/pagos).
  Para a Lista Vermelha: preparar tudo, **não** aplicar o passo final, e escrever
  "⚠️ ISTO MEXE EM PAGAMENTO. Confirma que eu aplico." — só aplicar após o "vai".
- **Karpathy:** pensar antes de codar · simplicidade primeiro · mudanças cirúrgicas (tocar só o
  necessário, limpar só a própria sujeira) · execução guiada por critério verificável.

## 7. Do CEO-AI (orquestração que mantém o Córtex vivo)
- O **CEO-AI é o dispatcher master**; convoca **esquadrões pequenos** (líder + 2 a 4 agentes),
  fan-out só em varreduras grandes. Toda feature nova → convocar `admin` (gatilho de paridade).
- **Gate do Juiz (obrigatório):** qualquer esquadrão que produza **código** passa o
  `juiz-revisor` (chão anti-trapaça determinístico + 3 camadas) **antes** de aceitar (commit/merge).
  Rejeição → lição → handoff ao Bibliotecário → próximo agente já sabe.
- Skills são ferramentas; **os agentes orquestram skills**, não duplicam a lógica delas.

## 8. Painel admin (paridade — a "Central do Córtex", só requisito)
Toda evolução do Córtex que precise de supervisão humana espelha o inbox de aprovação existente
(`robot_suggestions`, Fase 5) — **cabeçalho da mesma caixa, não um segundo inbox**. Requisitos de UI
listados no relatório da Fase 1A (§ painel admin) e no spec `reports/cortex/central_cortex_admin_spec.md`.

## 9. Confiança derivada + Knowledge Debt (Bloco 3)
`confianca` **nunca** é um número chutado pela IA — é **função da data + proveniência**, calculada por
`_tools/cortex_nightly.py`:
- **100%** no dia da `ultima_confirmacao`; decai **−1%/semana** desde então.
- `origem: [NAO_VERIFICADO]` → arranca em **40%**.
- `validade_dias` expirado → **0%** (dívida imediata).
- No frontmatter fica `confianca: auto` (placeholder); o valor real vive no `_debt.md` + relatório noturno.

**Knowledge Debt** (`_debt.md`, AUTO-gerado): página entra em dívida se `confianca < 50%` **OU** não
confirmada há **> 180 dias** **OU** `origem: NAO_VERIFICADO`. É o cartão que diz onde curar o cérebro.

## 10. Inbox — a regra dos 14 dias (Bloco 2)
`inbox/` é a camada **antes** do permanente. **Toda página paga aluguel:** o que ninguém promove ao
`wiki/` em **14 dias** é **movido** para `inbox/_descartado/` (recuperável 30 dias, nunca apagado) pela
consolidação noturna — **não** pelo humano. Relatórios de sessão nascem no `inbox/`, não no permanente.
Zona 🔴 **nunca** é auto-promovida nem auto-corrigida: só proposta na fila do admin.
