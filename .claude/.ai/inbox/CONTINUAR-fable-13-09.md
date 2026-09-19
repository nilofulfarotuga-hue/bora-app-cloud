# CONTINUAR — missão `fable-13-09` (escrito 13/09/2026 pela janela 1, Fable)

> Ponto exacto onde a janela 1 ficou. Ler primeiro `.claude/.ai/reports/FABLE-2026-09-13.md`
> (secções 1 e 2) e as linhas do `e2e_log` com `run_id='fable-13-09'` (1688 → 17xx).
> Digest curto em `claude_ai_memoria`, página `digest-2026-09-13-janela-1`.

## Estado às 01:15 de 14/09 (última actualização desta janela)
- Produção `autonomous-night-2026-04-29` = `6bd4bc25` no remoto (5 pushes: ff596cf9 árvore unida; 156c513c portão do CI numa linha; 56656928 arnês com `convertFlutterSurfaceToImage` no Android; 207adea4 mercados/lojas fechados abrem ao toque; a391c3d1 arnês fora de horas salta carrinho/pagamento). Runs #430/#431 vermelhas por defeitos do portão/arnês; #432 por um defeito real da app (portão de horário em `openRetailBusiness`, corrigido); #433 porque o arnês exigia carrinho com a loja fechada (corrigido); **run #434 em curso** — se verde, o `build` sobe o 604 ao Play e `app_latest_version_code` passa a 604.
- Se o 604 não aparecer: ler a run em `https://github.com/nilofulfarotuga-hue/bora-app-cloud/actions/workflows/build_android.yml` (Chrome do Danilo já tem sessão no GitHub), corrigir, `flutter analyze`, push. O guardrail de git só deixa empurrar `autonomous-night-2026-04-29`; o ramo candidata só o Danilo o empurra à mão.
- Autoteste local: não corre neste PC (drive não se liga ao emulador); não insistir sem ordem.
- Fecho pendente desta janela: Anexo A do relatório com o resultado da #432, digest final, e2e `fim`, Telegram, `/ctx doctor`, `/ctx stats`.

## O que já está feito (não repetir)
- Blocos 0, 1 (1.1–1.8), 2, 3 e 4.1/4.4/4.5: feitos com prova (ver relatório).
- 4.2/4.3 (autoteste local + push + CI): o estado final está no **Anexo A** do relatório.
  Se lá disser "push feito, CI por confirmar": confirmar só por SQL —
  `select value from platform_settings where key='app_latest_version_code'` tem de ser > 603.
  Se continuar 603 passadas ~40 min do push, abrir a run em
  `https://github.com/nilofulfarotuga-hue/bora-app-cloud/actions` (Danilo) ou ler o log do job `autoteste`.

## Bloco 5 — FEITO a 13/09 (não repetir)
Skill `.claude/skills/protocolo-missao-bora/SKILL.md` criada, ligada no `CLAUDE.md` e na `ceo-ai`,
copiada para `guarda-fc-site` e `BoraStudio`; `PADRAO_BORA.md` auditado contra as 4 regras de 10/09
(2.3 e 1.27 acrescentadas; 1.17 e 3.10 já existiam, 3.10 ganhou o autoteste). Ver relatório §3.

## Restos registados (precisam de ordem nova, não são deste bloco)
- `supabase/functions/dispatch-engine/index.ts` no repo é v58; produção corre v61 (cabeçalho v59). Pasta protegida pela Trava: só com ordem explícita, e copiar do ar para o repo (nunca o contrário — ver memória "verificar a Edge no ar antes de deploy").
- Linha LOCAL do `ios-lancamento` (52 commits: `orquestracao/agentes/*`, docs) não está na produção; unir dá 11 conflitos.
- Filme do talão no ecrã do estafeta (o Bloco 2 pedia gravação): não feito; a prova é SQL + pedido real 36e6812a.
- Córtex: `cortex_memorizar` não correu (MCP sem autenticação nesta sessão) — memórias ficaram nos ficheiros de memória do Claude Code.
- Depois de o Danilo declarar o estatuto de comerciante na App Store Connect (loja PT abre): tirar do `bora-site/baixar.html` a frase "Se a App Store disser que ainda não está disponível no teu país, pede por aqui" e republicar por `wrangler`.
- Ferramentas locais deste PC: JDK 17 portátil em `C:\Users\danil\jdk17\jdk-17.0.20.1+1` (`flutter config --jdk-dir` já aponta para lá); o Flutter local é 3.47.2 e o CI 3.41.2 — o APK local precisa de `--android-skip-build-dependency-validation` (AGP 8.9.1 do projeto < mínimo 8.11.1 do 3.47).
