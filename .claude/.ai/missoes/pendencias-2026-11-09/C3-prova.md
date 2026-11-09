# C3 — Prova da migração 20261109214000_robo_talao_extras_pendentes (09/11/2026)

## Onde se provou e porquê

A prova em produção (`C3-prova.sql`, bloco DO que acabava em RAISE) **não correu**: a trava recusou-a.
Mensagem literal:

> TRAVA do modo automatico: BLOQUEADO - DO com EXECUTE em producao: nao da para ler o que corre. Nao contornes: regista no e2e_log, reporta e segue com o resto.

Não se contornou. A prova foi feita em **PGlite 0.2.17** (Postgres real em Node) com:
- as 6 funções copiadas de PRODUÇÃO (`_talao_norm`, `_talao_e_modificador`, `_talao_e_acompanhamento`,
  `_talao_casar_itens`, `catalog_price_update_from_receipt`, `admin_approve_catalog_price_update`), cada uma com
  md5 igual ao de `pg_get_functiondef` no ar (b6993ee2… robô, 97a3a8f7… aprovar, d4aa0819… casar);
- os dados reais do talão a244493e (14 linhas) e do pedido 56fa8623 (2 menus Triple Whopper Spicy com
  EXTRA Bacon 0,91), o produto a 13,25 e as opções reais do grupo g4;
- a migração tal e qual (o ficheiro inteiro, corrido duas vezes).
Guião, definições e saída: `C3-pglite/prova_pglite.mjs`, `C3-pglite/defs_prod.sql`, `C3-pglite/resultado.json`.

## Resultado (saída literal resumida de resultado.json)

| Cenário | resposta do robô | linhas em catalog_price_updates | preços |
|---|---|---|---|
| A antes (função de hoje) | aplicadas 0, pendentes 1, extras_mais_caros 2 | 1: menu pending 13,25→12,37 · **0 linhas de extra** | menu 13,25, bacon 0,91 |
| B antes, menu a 12,00 | **aplicadas 1**, pendentes 0 | menu applied 12,00→12,37 | menu 12,37, bacon 0,91 |
| C migração 2× | md5 robô 6a22819b… e aprovar f4f573d7… iguais nas duas corridas (idempotente); coluna option_item_id criada; bkp guarda os md5 originais b6993ee2… e 97a3a8f7… | | |
| D depois (função nova) | aplicadas 0, pendentes 1, **extras_pendentes 1**, extras_mais_caros 2 | menu pending 13,25→12,37 + **1 extra pending 0,91→2,50**, opção …-g4-i7, confiança 1,000, "EXTRA: EXTRA BACON 2 FATIAS (na app: EXTRA Bacon)" | menu 13,25, bacon 0,91, todas as opções iguais |
| D aprovar o extra no painel | `{"ok":false,"error":"extra_corrige_se_nas_opcoes","preco_balcao":2.5,"option_item_id":"…-g4-i7"}`; linha continua pending | | menu 13,25, bacon 0,91 |
| D segunda corrida no mesmo talão | extras_pendentes 0; continua 1 linha de extra (não duplica) | | |
| D aprovar a linha do MENU | `{"ok":true,"preco_novo":12.37}` (produtos aprovam-se como antes) | | menu 12,37, bacon 0,91 |
| E depois, menu a 12,00 | **aplicadas 1** (igual a B) + extras_pendentes 1 | menu applied 12,00→12,37 + extra pending 0,91→2,50 | menu 12,37, bacon 0,91 |
| fim | | | menu 13,25, bacon 0,91, md5 das opções igual ao início |

Conclusão: antes = nenhuma linha pendente para o extra; depois = 1 linha pendente para o extra, nenhum preço
de extra mudou, e os produtos normais continuam a subir sozinhos como antes (B = E).

## Ordem com a sessão paralela (volta-deposito-kfc-2026-11-09)

A migração dela `20261109220000_volta_catalogo_e_talao.sql` (worktree C:\BoraLocal\wt-volta, ainda por
juntar) **remenda a MESMA função** `catalog_price_update_from_receipt` (âncoras v_segunda / v_new_base <= 0 /
saco / 'sem_match') e substitui `_talao_casar_itens`. As minhas âncoras são outras. Provado em PGlite com a
secção "4. Robô do talão" do ficheiro dela (cópia md5 1f0428de… às 21:2x):
- dela primeiro, minha depois: as duas mudanças ficam (v_absurdas e extras_pendentes), extra pendente 0,91→2,50,
  aprovar extra recusado, segunda corrida sem duplicar;
- minha primeiro, dela depois: igual.
Se ela mudar as âncoras antes de juntar, repetir `node prova_pglite.mjs <minha migração> <migração dela>`.

## O que fica para o painel (não feito aqui, Flutter)

`lib/screens/admin/admin_correcoes_preco_screen.dart` mostra a linha do extra com o nome do menu e
"Linha do talão: EXTRA: …". O botão Aprovar dá o erro `extra_corrige_se_nas_opcoes` (de propósito: aprovar
punha o preço do MENU igual ao do extra). Falta: ler `option_item_id`, mostrar "EXTRA" e só "Rejeitar" +
atalho para as opções do produto. Rejeitar já funciona sem mudanças.
