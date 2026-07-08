# CÓRTEX — Fase 1A · Relatório de Consolidação

> **Objetivo:** unir 3 fontes de conhecimento descoordenadas numa **fonte canónica única** +
> arranjar a sync do VPS. **Tudo aditivo e reversível — ZERO apagado, ZERO arquivado** (isso fica
> para o GATE final, com o "pode arquivar" do Danilo). Modo: PROTECÇÃO TOTAL (zona verde: só notas/docs).
> Data: 2026-07-08 · Branch: `autonomous-night-2026-04-29`.

## 0. As 3 fontes (antes)
| Fonte | O que é | .md | Estado |
|---|---|---|---|
| `bora_app/.obsidian-vault/` | **canónico** (versionado no git, o mais novo) | 116→**150** | ✅ fonte da verdade |
| `C:\Users\danil\Desktop\Bora` | vault que o Obsidian abre (velho) | 88 | ⚠️ deprecated (intacto, aguarda gate) |
| `.claude/.ai/knowledge/` | Cérebro dos agentes (Karpathy) | 46 | ✅ mantém-se (índice+temas) |

---

## 1. Órfãos e conflitos (Passo 1)
Comparação por **basename + SHA-256 + mtime** (`.obsidian-vault` × `Desktop\Bora`). Detalhe completo:
**`orfaos_e_conflitos.md`** (mesma pasta).
- **38 órfãos** (nome só no velho) → **33 únicos** por conteúdo (5 pares eram duplicados dentro do próprio velho).
- **1 conflito de conteúdo** 🟠: `negocios/visao-geral.md` — canónico (2026-05-08) **mais recente** que o velho (2026-04-23).
- **49 idênticos** (já migrados) · **0 casos** em que o velho seja mais novo que o canónico → **nenhuma perda de trabalho recente**.

## 2. Consolidação aditiva (Passo 2) — commit `0c623cc`
- **33 órfãos copiados** para `.obsidian-vault/_importado-velho/<caminho-de-origem>/` (o velho fica **intacto**; foi cópia).
  Inclui a auditoria de Julho (`AUDITORIA_PARIDADE_360_2026-07-01`), `00_BORA_DNA`, benchmarks, o
  `knowledge/00-12` do velho e os relatórios da migração de Maio.
- **Conflito** → versão velha guardada lado-a-lado como `negocios/visao-geral.doVelho.md` (nunca se perde texto).
- **Pastas por acento** (canónico): 40 ficheiros *tracked* de `sessoes/` → `sessões/` (PT-PT, `git mv`).
  `sessões/` passou de 13 → 53 · `sessoes/` ficou com **0 tracked** (sobram só checkpoints efémeros
  *gitignored*, que a PROTOCOLO marca como apagáveis — por isso ficam onde estão).

## 3. `schema.md` (Passo 3) — commit `0f7e0e0`
Criado `.claude/.ai/knowledge/schema.md` (a **Camada 3** — regras de trabalho do Córtex), que funde
sem perder regra: `CLAUDE.md` + `.claude/skills/ceo-ai/SKILL.md` + `PROTOCOLO.md` + o blueprint da Fase 0.
Cobre: anatomia (inbox `sessao/` vs `permanente/`), a regra de ouro (só o Bibliotecário escreve),
frontmatter obrigatório **atual** + o de **IDENTIDADE** (`id/tipo/origem/ultima_confirmacao/zona/validade_dias`)
— **documentado, não aplicado** (aplicar às 150 páginas é trabalho da 1B, faseado) — governança
zona×anel, regras duras (24 KB / zero-perda / história), e o Gate do Juiz.

## 4. Sync do VPS (Passo 4) — corrigido e a correr ✅
**Bug:** `/root/obsidian-sync.sh` (cron 04:30) puxava o vault **velho** (`Desktop\Bora`) → o Hermes lia notas velhas.

| | ANTES | DEPOIS |
|---|---|---|
| Fonte do tar | `C:/Users/danil/Desktop` → `Bora` | `.../projetosflutter/bora_app` → `.obsidian-vault` |
| Notas no container | 88 (velhas) | **150 (canónicas)** |
| Conteúdo | `Bora App/`, `auditoria-2026-05-31/` | `arquitetura/`, `_importado-velho/`, `sessões/`, `backups/` |

**2.º bug encontrado (pré-existente, não meu):** o alias `bora-pc` deixou de resolver no contexto do
`docker exec` ("could not resolve hostname bora-pc") — o `Host` block do `~/.ssh/config` não estava a
ser aplicado. Provei o caminho canónico com transporte **explícito** (ProxyCommand `tailscale nc` +
key `/opt/data/.ssh/id_ed25519` + `hermes@100.71.105.7`) → **150 .md**. Tornei a sync robusta com esse
transporte (deixa de depender do alias). O PC está no tailnet como `laptop-2q09vqa1` (100.71.105.7).
- **Backups (reversível):** script antigo → `/root/obsidian-sync.sh.bak_preCortex_20260708`;
  vault antigo do container → `/opt/data/_vault_velho_arquivo/obsidian-bora-velho-20260708` (**movido, NÃO apagado**).
- **Guard:** o run tinha rede de segurança — se a sync desse < 50 notas, **restaurava** o vault antigo
  (aconteceu 2× durante o diagnóstico; zero perda).
- **Pulso diário:** lê `/opt/data/obsidian-bora` (path inalterado) → passa a ler o canónico automaticamente.
- **Proveniência:** script final guardado no repo em `.claude/scripts/obsidian-sync.vps.sh` (recuperável se o VPS for reconstruído).

---

## 5. Painel admin — "Central do Córtex" (só REQUISITO, não implementado)
Gatilho de paridade. **NÃO construir agora** — espelhar o inbox existente (`AdminRobotSuggestionsScreen`,
`robot_suggestions`), como **cabeçalho** dessa caixa, não um 2.º inbox. Pontos de UI a cobrir na 1B:
1. **Ver o vault canónico** — browse read-only das 150 notas, por pasta/tema.
2. **Órfãos & conflitos pendentes** — o que veio do velho (`_importado-velho/`) e o conflito 🟠 (`visao-geral`) para decisão de 1 toque.
3. **Proveniência repo ↔ VPS** — última sync, contagem de notas, timestamp; estado do bridge (`bora-pc`/IP tailscale).
4. **Histórico de consolidações** — log (quando, o quê, quem) — auditabilidade.
5. **Botão de gate "arquivar velho"** — só habilitado após aprovação (o gate do Passo 6).

---

## 6. 🚦 GATE FINAL — À ESPERA do "pode arquivar" (NADA arquivado)
Cumprida a regra de ouro: **nada do velho foi apagado nem arquivado**. Confirmação de segurança:
todos os órfãos com valor **já estão no canónico** (`_importado-velho/`), e o único conflito tem o
canónico como versão mais nova (velho guardado `.doVelho.md`). **Nada com valor fica por trazer.**

**O que fica pronto para arquivar (só depois do teu "pode arquivar"):**
| Item | Onde | Porquê pode ir |
|---|---|---|
| Vault velho | `C:\Users\danil\Desktop\Bora` (89 .md) | Tudo o de valor copiado para `_importado-velho/`; Obsidian passa a abrir o canónico |
| Duplicados internos do velho | 5 pares em `auditoria-2026-05-31/` ⇄ `Bora App/relatorios/` | Conteúdo idêntico, já no canónico 1× |

**Proposta de destino de arquivo (reversível):** mover `Desktop\Bora` → `Desktop\_Bora_arquivo_2026-07-08\`
(no PC) e apontar o Obsidian ao canónico `bora_app/.obsidian-vault`. **Só faço isto quando disseres "pode arquivar".**

## 7. Bugs / riscos / decisões a tomar
- 🟠 **`negocios/visao-geral.md`** — 1 conflito. Recomendação: manter canónico (mais novo); rever `visao-geral.doVelho.md` e apagar quando validares. *(Decisão tua.)*
- 🟡 **Dup cosmética `sessoes`/`sessões`** no vault/VPS — os relatórios *tracked* foram para `sessões/`; sobra `sessoes/` com **checkpoints efémeros gitignored**. Sem impacto funcional; limpar é opcional.
- 🟡 **`INDEX.md` linha ~78** ainda diz que o vault é `Desktop\Bora` (velho). Handoff ao `bibliotecario-cerebro` para atualizar para `.obsidian-vault`. *(Não editei — só o Bibliotecário escreve no Cérebro.)*
- 🟢 **Bridge `bora-pc`** — o alias não resolve no `docker exec`; a sync já não depende dele. Se quiseres o alias de volta (usado por outros comandos do Hermes), é preciso repor o `Host bora-pc` de forma que o exec o aplique — fora do âmbito desta fase.

## 8. Commits desta fase (todos `[skip ci]`, docs)
- `0c623cc` — consolidar órfãos do vault velho no canónico (aditivo) — 75 ficheiros.
- `0f7e0e0` — `schema.md` unifica regras (ceo-ai+CLAUDE+PROTOCOLO).
- *(este relatório + `obsidian-sync.vps.sh` de proveniência — commit seguinte.)*
