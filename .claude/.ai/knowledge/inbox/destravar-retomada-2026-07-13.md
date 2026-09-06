---
id: destravar-retomada-2026-07-13
tipo: relatorio
origem: [MODO PROTECAO TOTAL, pedido Danilo, 2026-07-13 noite -- destravar f523/f960 presas
  em pausada-rate-limit + corrigir mecanismo + retomar as 2 manualmente]
zona: verde (infra do carteiro + Flutter UI da Limpeza, sem tocar dinheiro/tokens)
---

# Destravar a retomada + fechar as 2 pendentes (2026-07-13)

## PASSO 1 -- Diagnóstico

- **Nenhum processo Claude Code vivo no PC** no início desta sessão (`tasklist` limpo).
- Estado real das ordens em `/opt/data/cortex-brain/orquestracao/` (via SSH + `docker exec`):
  ambas `estado: pausada-rate-limit`, f523 com `tentativa: 0`, f960 com `tentativa: 1`.
- Já existia um diagnóstico anterior no mesmo dia
  (`inbox/diagnostico-rate-limit-2026-07-13.md`) que **já tinha achado a causa raiz exata**:
  quando `.pausa-rate-limit` expira, o `carteiro.sh` só apaga o ficheiro de controlo — o loop
  principal só processa `estado: aberta`, e a ordem que estava **em execução** no instante exato
  do rate-limit fica gravada em `estado: pausada-rate-limit` para sempre. **Não é sobre
  `tentativa: 0`** (a hipótese do pedido original) — é sobre qualquer ordem que estava a ser
  executada no instante do hit, independente da tentativa (confirmado: aconteceu a f523
  tentativa=0 E a f960 tentativa=2).
- Achado extra (não estava no diagnóstico anterior): o `hermes-carteiro-vigia.sh` (cron
  `*/5min`) já tinha localmente a lógica para detetar rate-limit expirado e dar um "nudge" no
  carteiro (`CASO 1.5`, escrita numa tentativa anterior) — mas **nunca tinha sido deployada** ao
  VPS (`grep -c rate_limit_expirado` no ficheiro de produção = 0). Por isso nem o vigia nem o
  carteiro tratavam estas ordens presas.

## PASSO 2 -- Mecanismo corrigido (para nunca mais ficar preso)

1. **`carteiro.sh`** (`.claude/.ai/hermes/orquestrador-carteiro/deploy/carteiro.sh`): ao expirar
   `.pausa-rate-limit`, agora varre a fila e reabre (`estado: aberta`) qualquer ordem presa em
   `pausada-rate-limit` — a tentativa já tinha sido devolvida na altura da pausa, reabrir não
   gasta tentativa extra.
2. **`hermes-carteiro-vigia.sh`** (cron `*/5min` já existente, `.claude/scripts/`): tinha a
   deteção de rate-limit expirado escrita mas nunca deployada — deploy feito agora.
3. Não foi preciso criar cron novo: o `*/5min` do vigia + o fallback horário
   (`17 * * * * carteiro.sh`) já cobrem a frequência pedida (5-10 min); só faltava a lógica em
   produção.
4. **Deploy seguro** (ambos os ficheiros): `bash -n` (sintaxe) → `--selftest` no VPS → backup
   (`*.bak-2026-07-13*`) → swap atómico (`mv`) → confirmação de checksum. Nenhum downtime.
5. **Validação**: `--selftest` local e remoto (11/11 e 7/7 OK), + simulação de ciclo completo
   numa fila temporária local (sem tocar produção) provando que uma ordem presa em
   `pausada-rate-limit` é reaberta, executada, aprovada e notificada corretamente.

## PASSO 3 -- As 2 ordens retomadas manualmente

### f523 — avisos Telegram restaurados
Implementado diretamente no `carteiro.sh` (não delegado ao pipeline, já que o pipeline estava
parado):
- ✅ **Conclusão**: ordem avulsa aprovada volta a avisar (`✅ Bora: tarefa <id> concluída com
  sucesso. <1 linha do resultado>`) — extrai `Uma linha final:` da saída se existir, senão a
  última linha não vazia. Passos de **missão** continuam em silêncio por design (só a missão
  inteira ou um passo travado avisam — reengenharia 2026-07-12, intencional para não repetir
  aviso a cada passo encadeado).
- ⛔ **Travamento**: ordem avulsa travada (5 tentativas / timeout / juiz-sem-veredito) agora
  avisa com o motivo (`⛔ Bora: tarefa <id> TRAVOU — <nota>`) — antes ficava muda à espera do
  watchdog de 12h.
- 🧹 **Fila vazia / terminal limpo**: aviso único quando não sobra nada `aberta/executando/
  respondida` (não repete a cada ciclo ocioso; rearma quando chega trabalho novo).
- **Eventos críticos** (carteiro morto/reiniciado, lock órfão): já existiam
  (`executor-lock.ps1`, `hermes-carteiro-vigia.sh`) — não foi preciso construir nada novo. RAM
  crítica está coberta por scripts de vigilância já existentes (ver
  `inbox/auto-limpeza-ram-2026-07-13.md`).
- **Testado**: (a) 3 mensagens reais enviadas ao Telegram do Danilo (uma de cada tipo), (b)
  simulação de ciclo completo local confirmando que a lógica real do script dispara `notify()`
  com a mensagem certa nos 3 pontos (ordem aprovada, ordem travada, fila vazia).

### f960 — missão Limpeza parte 1
Ao ler a ordem completa descobri que **já havia ~90% do trabalho escrito** de uma tentativa
anterior (não commitado — 8 ficheiros `M` no `git status` desde o início da sessão). Não
repeti do zero: verifiquei, completei o que faltava e validei.
- ✅ **Disponibilidade**: `cleaner_availability_screen.dart` com estado vazio acionável ("Ainda
  não marcaste nada..."), atalho a partir do `cleaner_home_screen.dart` renomeado para "A minha
  disponibilidade" com card clicável.
- ✅ **Cancelamento sem profissional**: novo status `cancelledNoCleaner` (`cleaning_models.dart`)
  + migration `20260713100000_cleaning_no_cleaner_cancel.sql` — **já estava aplicada em
  produção** (confirmado via `list_migrations`, versão `20260713131947`) de uma tentativa
  anterior antes do rate-limit. Cria cron a cada 5 min que cancela reservas cuja hora passou sem
  profissional aceite e notifica o cliente (in-app + push), sem tocar reembolso/valores.
- ✅ **Materiais obrigatórios**: checklist de 7 itens no `cleaner_apply_screen.dart`, bloqueia
  envio da candidatura sem todos confirmados, guardado em `docs.materials_ok`/`materials_list`.
- ✅ **Pergunta de produtos no wizard**: texto explícito da pergunta em
  `cleaning_wizard_screen.dart` (a escolha `_productsBy` já existia; só faltava a pergunta
  clara) — sem preço associado, como pedido.
- ✅ **Paridade admin**: `admin_cleaning_cleaners_screen.dart` ganhou secção de materiais
  confirmados + botão "Ver disponibilidade" (RPC `admin_cleaner_availability`, já aplicada);
  `admin_cleaning_bookings_screen.dart` reconhece o novo status.
- **Validado**: `flutter analyze` = 217 issues, **0 erros** (igual ao baseline conhecido — ver
  memória `project_flutter_analyze_baseline`), nenhum warning/erro nos ficheiros tocados.

### Fora de âmbito (encontrado, não tocado)
O `git status` também tinha `lib/screens/client/tvde/tvde_ride_tracking_screen.dart` e
`lib/services/notification_service.dart` modificados — **não relacionados** com f523/f960 (o
segundo é sobre heads-up de oferta de entrega para estafetas "everything", o primeiro é um fix
de bottom sheet do TVDE). Deixados intocados e não commitados — pertencem a outra ordem/tarefa.

## Commits
1. `972b8f5` — `feat(limpeza): ...` (f960, 8 ficheiros)
2. `b441803` — `fix(orquestracao): ...` (mecanismo + f523, 2 ficheiros)

## Estado final da fila (VPS)
Ambas `ordem-20260713103442-f523` e `ordem-20260713130657-f960` marcadas `estado: aprovada`
diretamente na fila real, com nota a apontar para este relatório.

---

**MECANISMO CORRIGIDO + F523 OK + F960 OK** — carteiro.sh reabre ordens presas em
pausada-rate-limit automaticamente (deployado + testado); hermes-carteiro-vigia.sh com deteção
de rate-limit expirado deployado ao VPS (estava só local); avisos Telegram de
conclusão/travamento/fila-vazia restaurados e testados com mensagens reais; missão Limpeza
parte 1 completa (disponibilidade + cancelamento-sem-profissional + materiais +
pergunta-produtos + paridade admin), migration já em produção, `flutter analyze` limpo (217/0
erros), 2 commits feitos.
