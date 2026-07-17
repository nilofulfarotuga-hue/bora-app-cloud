---
id: licoes-index
tipo: conceito
origem: [prompt Danilo Fase Final Bloco 4]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# 🎓 LIÇÕES — memória de experiência (problema → falhas → solução)

> Cada lição: **problema** → **tentativas que falharam** → **porquê falharam** → **solução definitiva**.
> ⚠️ **REGRA ANTI-LIXO:** uma lição só fica no permanente se virar **regra generalizável**.
> Relato de incidente isolado que não vira regra em 14 dias → morre no [[inbox]] como tudo o resto.

## Índice (semeado com lições reais da saga do Córtex)
| Lição | Regra em 1 linha |
|---|---|
| [[docker-exec-user-hermes]] | `docker exec` — escolher o **user** certo (`-u hermes` p/ env; `-u root` p/ dirs root-owned) |
| [[verificar-fonte-de-sync]] | Num sync, auditar a **FONTE**, não só o destino |
| [[verificar-estado-antes-de-reexecutar]] | Antes de reexecutar, `git log` o estado real — **verificar > reexecutar** |
| [[onde-vive-a-trava]] | Mapear **onde** vive um guard antes de o testar (a Trava é hook repo-side, não `engine` no VPS) |
| [[confirmar-ferramenta-antes-de-prometer]] | Confirmar que a ferramenta **existe** antes de prometer o passo |
| [[classificador-zona-menos-sensivel-a-palavras]] | Guard de zona lê **intenção** (verbo escrita vs leitura), não só a **palavra** — senão treina *prompt-laundering* |
| [[licao-dual-owner-column]] | `restaurants` tem `user_` E `user_id` — gravar/ler SEMPRE as duas até unificar |
| [[licao-rpc-composite-null-row]] | RPC `RETURNS <tabela>` devolve row de NULLs quando vazia — usar `SETOF`/`RETURN NULL` e validar `id != null` |
| [[licao-exception-when-others-null]] | `EXCEPTION WHEN OTHERS THEN NULL` = falha invisível — capturar em `notification_failures` + `RAISE WARNING` |
| [[licao-notify-canal-errado]] | Push pelo `type`/canal errado chega mas o app não roteia — cada público precisa do seu `type` respeitado ponta-a-ponta |
| [[licao-heartbeat-fantasma]] | `is_online=true` sem TTL = dispatch para mortos — presença precisa de cron de expiração por heartbeat |
| [[licao-parser-mudo]] | Parser nunca devolve 0 bytes — "SAIDA-VAZIA" é sintoma, não causa; diz sempre o que aconteceu |
| [[licao-autocomplete-teclado]] | Dropdown atrás do teclado em bottom-sheet — fix no widget partilhado (`viewInsets`/`isScrollControlled`), não por ecrã |
