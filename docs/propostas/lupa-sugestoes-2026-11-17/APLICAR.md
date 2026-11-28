# Lupa com sugestões desde a 1.ª letra — como aplicar (missão lupa-sugestoes-17-11)

Ordem trazida pela Claude.ai (pedido do Danilo 17/11 08:41: "se a pessoa coloca a letra A, aparece
lá as opções que tem na loja, sem carregar o servidor"). Preparado no ramo
`ai/2026-11-17-lupa-sugestoes` (por cima do PR #33 `ai/2026-11-17-busca-leve`). **Nada foi aplicado
em produção**: a trava do PC recusa DDL. Quem aplica é a Claude.ai, por esta ordem.

Registo de cada passo: `e2e_log`, fluxo `lupa-sugestoes-17-11`.

## O que muda

1. **Sugestões (bloco 1)** — `supabase/migrations/20261117140000_lupa_sugestoes.sql`
   - tabela `lupa_sugestoes` (~5 mil linhas, fora do tempo real, sem leitura direta) + `lupa_sugestoes_estado`;
   - RPC `lupa_sugestoes(p_q, p_restaurant_id)` SECURITY DEFINER: as 8 melhores pelo começo do texto,
     lidas pelo índice `lupa_sugestoes_prefixo` (intervalo `[q, q||'{')`);
   - recálculo `lupa_sugestoes_recalcular()` em lote, PARA se o vigia passar 50%;
   - pg_cron `lupa-sugestoes` (`3-59/5 * * * *`): só recalcula de hora a hora ou 5 min depois de uma loja mudar;
   - gatilho `lupa_sugestoes_loja` em `restaurants` (aprovação, ligada pelo admin, escondida, nome);
   - painel: `admin_lupa_sugestoes_listar / _recalcular / _esconder` (+ `admin_audit_log`);
   - `platform_settings.lupa_sugestoes_enabled = true`.
2. **Pesquisa sem login a usar o índice (bloco 2)** — `supabase/migrations/20261117140100_pesquisa_dono.sql`
   - `pesquisa_produtos` passa a SECURITY DEFINER com as regras de leitura de `products` escritas à
     mão (CTE `vis`); `cliente_pesquisar` recriada só para ligar `bora.pesquisa_dono` (fica IGUAL).
3. **App** (Android, iPhone, web; PT-PT): lupa da página inicial, lupa da loja e menu do restaurante
   mostram as sugestões com 1-2 letras (espera 250 ms, memória 10 min); 3+ letras = pesquisa de hoje.
   Painel admin (PT-BR): "Sugestões da lupa" (`/admin/lupa-sugestoes`).

## Ordem para aplicar

**Importante:** aplicar as migrações ANTES de juntar este PR. Se a app nova for publicada sem a RPC
`lupa_sugestoes` (ou com o interruptor desligado), com 1-2 letras as 3 lupas só mostram
"Escreve mais letras para ver todos os produtos." — deixam de mostrar o filtro local da loja (2 letras),
as lojas da lupa geral (2 letras) e o menu por baixo. Achado do Refinador, aceite e documentado.

0. Antes: ler o vigia (`select criado_em, ocupado_pct from vigia_servidor_registos order by id desc limit 3`).
   Se estiver acima de 50%, esperar.
1. Aplicar `20261117140000_lupa_sugestoes.sql` (MCP `apply_migration`, nome `lupa_sugestoes`).
   O fim do ficheiro já corre o 1.º enchimento (~3 s de CPU; se o vigia estiver acima de 50% pára e o
   cron enche nos 5 min seguintes).
   Conferir: `select ultimo_resultado from lupa_sugestoes_estado;` → `parado:false`, `total` ≈ 5000.
2. Provas do bloco 1: correr os 4 blocos de `supabase/tests/lupa_sugestoes_test.sql` (cada um desfaz
   tudo). Esperado: `FALHAS 0` nos 4; bloco 2 com pior tempo < 10 ms e o plano a usar `lupa_sugestoes_prefixo`.
3. Aplicar `20261117140100_pesquisa_dono.sql` (nome `pesquisa_dono`).
4. Prova do bloco 2: `supabase/tests/pesquisa_dono_igualdade.sql`. Esperado em cada pessoa
   (anon, normal, dono_a3, admin): `iguais = pesquisas`; `A3-fora-da-loja-A3 = 0` para anon e normal.
   Se não der: **voltar atrás** (abaixo) e reportar no e2e_log.
5. Carga (bloco 3.2), com o vigia aberto noutra janela do MCP:
   `BORA_ANON=<chave pública> node scripts/carga/lupa_sugestoes_carga.mjs 100 180 carga_lupa.json`.
   Alvo: `alvo_p95_sugestoes_300ms: true`, 0 falhas, vigia < 30%. Parar (Ctrl+C) se o vigia passar 85%.
6. Juntar o PR #33 primeiro e depois este PR (CI verde) → o CI publica nas 3 (Play, App Store, web).
   Conferir nas 3: escrever "a" na lupa da página inicial e na lupa do Continente → aparecem sugestões.

## Provas já feitas (sem aplicar, só leitura, DO + RAISE desfeito)

- **Bloco 2**: corpo novo corrido como dono com o JWT simulado vs `pesquisa_produtos_antiga` com o
  papel real. anon 22/22 + 10/10 com erros de escrita; normal igual; dono da A3 24/24; admin 24/24
  (mesmo conjunto e mesma ordem de nome+nota; as únicas diferenças letra a letra são empates de
  nome+nota, que já trocam de lugar na antiga). 0 produtos da A3 a quem não a vê.
  Tempo sem login: 24 pesquisas **16 756 ms → 1 864 ms** (~9x); erros de escrita 7 790 → 2 687 ms.
  EXPLAIN "leite" como anon: **Seq Scan 61 680 linhas, 92 ms → Bitmap Index Scan, 6,6 ms**.
- **Bloco 1**: as fontes deram 5 017 sugestões (palavra 4 148, secção 599, produto 241, loja 29).
  Sem login, "a": Amaya Sushi Bar, Auchan, Atum, Água, Açúcar, Arroz, Azeite, Ambientador (2,5 ms
  sem índice); lupa da A3 sem login: nada; o dono da A3 vê a loja e as palavras dela.
  Recálculo: 2,5 s (cada palavra normalizada uma vez; por produto eram 15,3 s).

## Como voltar atrás

- Só a app: no painel, "Sugestões da lupa" → desligar (ou
  `select admin_update_setting('lupa_sugestoes_enabled','false'::jsonb)`): a RPC devolve vazio e a
  lupa volta a esperar 3 letras (sem "não encontrei").
- Bloco 1 inteiro: `select cron.unschedule('lupa-sugestoes');`
  `drop trigger lupa_sugestoes_loja on public.restaurants;` e drop das funções
  `lupa_sugestoes*`, `admin_lupa_sugestoes_*`, `lupa_norm` e das tabelas `lupa_sugestoes`,
  `lupa_sugestoes_estado` (só dados derivados do catálogo; nada de clientes).
- Bloco 2: voltar a aplicar a parte `pesquisa_produtos` de
  `20261117100100_busca_leve_pesquisa.sql` (SECURITY INVOKER) e a `cliente_pesquisar` de
  `20261117100300_cliente_pesquisar_produtos_3_letras.sql`.

## Achados pelo caminho (não corrigidos — decisão da Claude.ai)

1. `product_embeddings_gte` tem RLS ligada e nenhuma regra de leitura: a pesquisa por significado com
   os vetores gte só funciona para o servidor, nunca na lupa da loja da app (anon/authenticated veem 0
   linhas). A migração mantém isto igual.
2. Lupa da página inicial (`cliente_pesquisar`): corre como dono e só tira as lojas escondidas no
   fim. Por isso a A3 empurra outros produtos para fora — sem login "caneta" mostra 3 produtos em
   vez de 20, "caderno" 17 em vez de 60. Conserto possível: tirar o `bora.pesquisa_dono` de
   `cliente_pesquisar` (a nova `pesquisa_produtos` já filtra) — muda resultados, por isso não foi feito.
   Os prémios do check-in também não eram filtrados nessa lupa: CORRIGIDO na 20261117140100 (filtro no
   fim, só admin os vê; hoje há 0 disponíveis, por isso 0 diferenças).

## Correções depois do Refinador (revisor com contexto limpo, 17/11)

- `pesquisa_escolhas` aceita escrita sem login: uma só linha punha qualquer texto na lupa de toda a
  gente. Agora só entra o que **3 pessoas com conta diferentes** escolheram, e com 3+ letras.
- Loja que passa a escondida: o gatilho recalcula logo (antes ficava até 1 hora nas sugestões gerais).
- Menu do restaurante: tocar numa secção faz a pesquisa com o nome da secção (não salta para a secção
  do menu). Lupa da loja: tocar na secção abre a secção.
- Textos do painel corrigidos para PT-BR.
3. `tool/l10n/gerar_dicionario.py` no Windows lê os JSON com a codificação errada e reescreve
   `lib/l10n/strings_en.dart` a perder centenas de traduções. Não usado: a frase nova foi posta à mão
   no `strings_en.dart` e no `tool/l10n/traducoes/pt-en-42-lupa-sugestoes.json`.
