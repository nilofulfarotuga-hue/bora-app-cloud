# PUBLICAÇÃO 2 — Casa & Manutenção como NOVIDADE (m11-amigo-rosto-2026-11-09, adendo 3)

Preparado a 09/11/2026 pelo Claude Code (worktree `wt-m11-casa`, ramo `ai/2026-11-09-m11-casa`).
Ordem do Danilo (09/11 07:02): "quero que publique já tudo: o Amigo e a Casa e Manutenção, com o ícone
certinho, 3D, cartoon; deixa publicada como novidade; do jeito que fazemos sempre nas categorias".

Tudo o que escreve em produção está aqui, por ordem, para correr **com as travas desligadas pelo Danilo**.
Nada disto foi corrido em produção. Os SQL foram provados em PGlite com as funções REAIS de produção
(`docs/casa/prova/`, resultado em `prova_pglite_2026-11-09.txt`: 13 passos verdes, incluindo as recusas
esperadas e a reversão).

Comando para cada ficheiro (a partir da raiz do repo):

```
npx --no-install supabase db query --remote=ojykpzwqrtusfeakzrna --yes --agent no --output-format json -f docs/casa/sql/<ficheiro>.sql
```

Os de só leitura (`00`, `06`) podem ir com `--read-only` em vez de `--yes`. Cada ficheiro corre numa
transação: ou entra tudo, ou nada. Todos acabam num SELECT que lê de volta o que gravaram (prova material).
O admin é simulado como na M10 (claims do JWT da conta do painel `c9fccf85…`, só dentro da transação);
cada ação fica no `admin_audit_log` pelas funções do próprio painel.

---

## Estado lido em produção antes de preparar (09/11/2026 ~07:20, por SELECT)

- `casa_enabled = false` (desligada para todos desde a M10).
- `casa_valores_autorizados.autorizado = true` (Danilo, 09/11 06:54, gravado 06:56). Preços conferidos e
  iguais ao autorizado: hora 20 € (mín. 1 h), roupeiro 80, cama 70, móvel médio 40, móvel pequeno 25,
  quadros/espelho 25, varão 30, prateleiras 40, TV 45, torneira 40, candeeiro 30, silicone 30.
- Os 15 serviços de preço fixo ou à hora têm a pergunta `material` com a única opção "Sim, já tenho tudo".
- Profissional do Danilo (`ad8e790d…`, conta `503a2e09…`): `pending`, ofícios `montagem` e `fixacao`
  por aprovar, disponível todos os dias 09:00–20:00, raio 15 km, `aceita_papel('handyman') = true`.
  **Sem aparelho registado no papel `handyman`** (só tem `cleaner`).
- Sem faixa da Casa; sem difusão da Casa; a chave `casa_novo_ate` ainda não existe.
- Público da notificação (clientes com opt-in de "Promoções e novidades"): 22 (21 com aparelho ativo).

---

## Ordem da publicação

### Passo A — publicar o código (as 3: Android, iPhone, web)

O que viaja neste ramo (só ficheiros da missão, `git add` por caminho):

- `assets/categories/cat_casa.png` — ícone 3D cartoon novo (caixa de ferramentas), 1024×1024, opaco.
- `lib/screens/client_home_screen.dart` — o ladrilho da Casa usa o PNG e mostra o selo "Novo".
- `lib/widgets/bora/bora_tile_card.dart` — selo opcional no canto do ladrilho.
- `lib/stores/casa_store.dart` — lê `casa_novo_ate` (get_setting) e diz se o selo aparece.
- `lib/models/casa_models.dart` — regras do material e do selo (hora de Lisboa).
- `lib/screens/client/casa/casa_regras.dart`, `casa_widgets.dart`, `casa_pedido_wizard_screen.dart` —
  material obrigatório ("Sim, já tenho tudo"), aviso no ecrã do serviço e linha no resumo.
- `lib/screens/handyman/casa_profissional_ui.dart`, `handyman_home_screen.dart`, `handyman_trabalho_screen.dart`
  — "Material do cliente — levas só as ferramentas" na oferta e no trabalho.
- `lib/screens/admin/admin_casa_definicoes_tab.dart` — painel (PT-BR): secção "Novidade (lançamento)" com o
  selo (ligar, desligar, data) e o atalho para "Faixas da home".
- `lib/l10n/strings_en.dart` — inglês das 6 frases novas.
- `supabase/migrations/20261109074000_casa_novidade_selo_novo.sql` — a chave do selo (passo 1).
- Testes: `test/casa_lancamento_test.dart` (novo), `test/golden/grelha_categorias_test.dart` (Casa na grelha).
- Fotografias: `test/golden/_fotos/casa_servico_roupeiro_medio.png` e `grelha_categorias_4col_{360,390,430}.png`.
- `docs/casa/` (este ficheiro, os SQL e a prova PGlite).

Push no ramo de produção = build Android + deploy web (o CI sobe o versionCode). iPhone pelo caminho
habitual. A app antiga continua a funcionar com a Casa ligada (mostra o ícone provisório e já obriga a
responder ao material, porque a pergunta só tem uma opção), mas o selo e o ícone novo só chegam com esta versão.

### Passo 0 — fotografia do estado antes (só leitura)
`docs/casa/sql/00_estado_antes.sql` — confirmar que bate com o estado acima.

### Passo 1 — a chave do selo (migração + registo no mesmo envio)
`docs/casa/sql/01_migracao_selo_novo.sql` — cria `platform_settings.casa_novo_ate = ''` (texto, sem selo) e
regista `20261109074000_casa_novidade_selo_novo` em `supabase_migrations.schema_migrations` com o texto exato
do ficheiro do repo (gerado por script). Idempotente.

### Passo 2 — o Danilo profissional aprovado da Casa
`docs/casa/sql/02_aprovar_danilo.sql`
1. Junta `reparacoes`, `canalizacao` e `jardinagem` aos ofícios dele (o mesmo INSERT que a `casa_candidatura`
   faz; o painel não tem botão para juntar ofícios — quem os pede é o profissional). Registado no
   `admin_audit_log` (`casa_oficio_juntar`).
2. `admin_casa_decidir_profissional(…, 'aprovar')` — o botão "Aprovar" da ficha.
3. `admin_casa_decidir_oficio(…, 'aprovar')` para os 5 ofícios (nenhum exige certificado).

Efeitos que o servidor faz sozinho (já autorizados, mas a saber): a conta profissional do Danilo recebe 6
avisos "Candidatura Casa aprovada / Ofício aprovado: …"; e ver o PARA O DANILO n.º 3 (vaga "sem comissão").

### Passo 3 — o Danilo regista o aparelho como profissional da Casa (no telemóvel, um passo)
Depois do passo 2 e com a versão nova instalada: abrir a app na conta profissional (`503a2e09…`), entrar em
"Casa e manutenção" uma vez (o portão regista o aparelho em todos os papéis) e confirmar que os 5 ofícios
aparecem ligados. Prova:
```sql
select role, platform, active, updated_at from public.provider_push_tokens
 where user_id = '503a2e09-2111-44b5-9852-d6d5897467f1' and role = 'handyman';
```
Sem esta linha a oferta chega na mesma, mas com janela curta (1 min, regra 1.23) e sem tocar.

### Passo 4 — ligar a Casa para todos e o selo "Novo" 14 dias
`docs/casa/sql/03_ligar_casa_e_selo.sql` — `admin_casa_interruptor(true)` e
`admin_casa_guardar_definicao('casa_novo_ate', hoje em Lisboa + 14 dias)`. Recusa se os valores não estiverem
autorizados ou se faltar o passo 1. Lê de volta o `casa_config()` e o que a app recebe por `get_setting`.

### Passo 5 — a faixa da home (14 dias)
`docs/casa/sql/04_faixa_home.sql` — "Novidade: Casa & Manutenção" / "Montar móveis, pendurar, pequenas
reparações", destino Categoria → `casa`, verde como a do Bora Assistente, de agora a +14 dias, ordem 1.
Não cria uma segunda se já houver uma ativa. Gere-se depois no painel > Faixas da home.

### Passo 6 — a prova a sério (ver "Guião do teste real" abaixo)

### Passo 7 — UMA notificação aos clientes (só depois do passo 6 passar)
`docs/casa/sql/05_notificacao_clientes.sql` — pelo caminho do painel (`admin_broadcast_notification`,
`all_clients`, kind `promo` → só quem deu o opt-in de promoções e novidades; 22 pessoas a 09/11). Título
"Novidade: Casa & Manutenção"; texto: "Montar móveis, pendurar quadros e TV, pequenas reparações e jardim, a
partir de 20 € à hora. O profissional leva as ferramentas; o material é teu. Pede na app Bora, no atalho Casa."
(bate com o catálogo autorizado). Recusa se a Casa estiver desligada ou se já houve uma difusão com este título
(correr duas vezes não manda duas). A fila `execute-broadcast-queue` envia em ≤ 2 min; repetir o SELECT do fim
até `status = 'sent'`.

### Passo 8 — verificação final (só leitura)
`docs/casa/sql/06_verificar_depois.sql` — Casa visível, serviços, selo, Danilo e ofícios, aparelho handyman,
faixa, difusão, migração e auditoria do dia.

### Reverter (só se for preciso)
`docs/casa/sql/99_reverter.sql` — desliga a Casa, o selo e a faixa. Não apaga nada. (Notificação enviada não
se desenvia.)

---

## Guião do teste real (Passo 6)

**⚠️ O teste pedido ("Montar roupeiro" a 80 € em dinheiro) NÃO passa hoje**: a Casa só aceita dinheiro e o
dinheiro tem o limite geral de 40 € (`max_cash_amount_cents = 4000`, decisão 3 do Danilo de 30/10). A app mostra
"Dinheiro — só até 40,00 €", "Cartão — brevemente", "MB Way — brevemente" e não deixa pedir; o servidor recusa
com `dinheiro_acima_do_limite`. O mesmo para "Montar cama" (70 €) e "Pendurar televisão" (45 €). Ver o bloco
"ISTO MEXE EM PAGAMENTO/DINHEIRO".

Por isso o guião tem duas partes:

**Parte A — o limite (prova do bloqueio, 2 min).**
Conta cliente: a conta do painel `c9fccf85…` no perfil de cliente (web ou telemóvel). Home → ladrilho "Casa"
(com selo "Novo") → "Montagem de móveis" → "Montar roupeiro" → escolher marca → tocar "Sim, já tenho tudo" →
Continuar → amanhã às 10:00 + morada → passo Pagamento: confirmar que o dinheiro aparece cinzento com a
explicação e que não há método disponível. Fotografar.

**Parte B — o fluxo inteiro em dinheiro (≤ 40 €).**
1. Mesma conta cliente. "Montagem de móveis" → **"Montar móvel médio" (40 €)**. Confirmar no ecrã: o aviso
   "O profissional leva só as ferramentas. O material … é teu" está à vista; tocar "Continuar" sem tocar em
   "Sim, já tenho tudo" mostra "Para pedir, confirma que já tens todo o material…"; depois tocar "Sim, já tenho
   tudo" → Continuar.
2. Quando: **amanhã às 10:00** (fica a mais de 12 h → cancelar não custa nada; `casa_cancel_free_hours = 12`).
   Onde: uma morada na Guarda (até 15 km da base dele). Pagamento: **Dinheiro**. Resumo: a linha "Material:
   Sim, já tenho tudo — o profissional leva só as ferramentas". Tocar "Encomenda com obrigação de pagar".
3. Profissional: a conta `503a2e09…` no telemóvel do Danilo (passo 3 feito). A oferta toca por cima do ecrã
   com o valor que ele ganha (com a promoção ativa, ganha os 40,00 € inteiros), mostra "Material do cliente —
   levas só as ferramentas", e ele toca **Aceitar**.
4. Cliente: o pedido passa a ter profissional (aviso "Pedido confirmado", enviado pela `casa_aceitar_oferta`).
5. Cancelar sem mexer em dinheiro: cliente → "Os meus pedidos" → o pedido → Cancelar → a simulação diz
   **sem custo** (mais de 12 h antes) → confirmar. Não há dinheiro envolvido: o pagamento era em mão e nada
   foi cobrado.
6. Painel > Casa > Pedidos > a ficha → "Marcar teste" (`admin_casa_marcar_teste`), para nunca entrar em
   acertos nem relatórios.
7. Prova por SELECT (trocar `<pedido>` pelo id da ficha):
```sql
select p.id, p.estado, p.payment_method, p.payment_status, p.total_cents, p.ganho_cents, p.cancel_fee_cents,
       p.is_test_order, p.respostas ->> 'material' as material,
       (select string_agg(o.resposta || ' tinha_aparelho=' || o.tinha_aparelho, '; ') from public.casa_ofertas o where o.pedido_id = p.id) as ofertas,
       (select string_agg(coalesce(e.estado_de, '-') || '>' || e.estado_para, ' | ' order by e.created_at)
          from public.casa_pedido_eventos e where e.pedido_id = p.id) as eventos
  from public.casa_pedidos p where p.id = '<pedido>';
```
   Esperado: `estado = cancelado`, `payment_method = cash`, `cancel_fee_cents = 0`, `is_test_order = true`,
   material "Sim, já tenho tudo", uma oferta `aceite` com `tinha_aparelho = true`, eventos até `aceite` e
   depois `cancelado`. Registar no `e2e_log`
   (fluxo `m11-amigo-rosto-2026-11-09`, passo `C9-teste-real`).

(Se no ecrã do Passo 3 faltar o aparelho `handyman`, a oferta chega só com janela de 1 min e sem som: fazer o
passo 3 antes.)

---

## ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO — não foi aplicado nada

**Cartão e MB Way na Casa não existem** (PADRAO 1.1 e 1.17). `casa_config().pagamento_cartao` está cravado a
`false` e o servidor recusa `card`/`mbway` com `pagamento_cartao_indisponivel` em `casa_criar_pedido`,
`casa_aceitar_orcamento` e `casa_responder_extra`. A proposta de copiar o caminho provado da Limpeza
(Edge Function `casa-checkout` espelho da `cleaning-checkout`, retido até o cliente confirmar ou 24 h) está
pronta em `docs/propostas/casa-manutencao-2026-10-30/pagamento-cartao-mbway.md` e espera o "autorizo"
(mexe em Stripe). Enquanto não houver cartão, os serviços acima de 40 € (roupeiro, cama, TV) não se
conseguem pedir.

---

## PARA O DANILO (decisões só dele; a publicação segue sem elas)

1. **Roupeiro (80 €), cama (70 €) e TV (45 €) não se conseguem pedir hoje**: só há dinheiro e o limite é 40 €.
   Dois caminhos: (a) "autorizo construir e ligar cartão e MB Way na Casa" (o caminho da Limpeza, já escrito);
   ou (b) um limite de dinheiro só para a Casa (por exemplo 100 €), que também precisa de "autorizo" porque
   muda a regra do dinheiro.
2. **"Trocar candeeiro" (30 €) não aparece aos clientes**: está no ofício Eletricidade, que é da fase 2 e está
   desligado (precisa de documento DGEG). Se ele quiser que apareça já, muda-se o serviço para "Reparações" no
   painel > Casa > Catálogo (mudar o ofício não mexe no preço nem reabre a autorização).
3. **Aprovar o Danilo ocupa 1 das 5 vagas "2 meses sem comissão"** (regra autorizada: os 5 primeiros
   profissionais reais). Fica `sem_comissao_ate` = hoje + 2 meses na ficha dele, e sobram 4 vagas para
   profissionais de fora.

---

## O que NÃO se fez (e porquê)

- Nada escrito em produção (travas ligadas; tudo acima é para a publicação 2).
- Não se mexeu em preços, comissões, Stripe, carteira nem `max_cash_amount_cents`.
- A notificação não foi enviada (só preparada; vai depois do teste real).
