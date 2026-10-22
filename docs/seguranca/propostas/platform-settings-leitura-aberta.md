# PROPOSTA (não aplicada) — qualquer conta lê a tabela `platform_settings` inteira, incluindo o oculto

> Auditoria de segurança 21/10/2026 (missão geral-noite-21-10, agente N4). **Toca dinheiro**
> (markup oculto, comissões, config Stripe) → só reporto, não aplico. Espera o "vai" do Danilo.

## O que se achou (provado em rollback, como conta normal)

A tabela `public.platform_settings` tem RLS ligada, mas a política de leitura é:

```
platform_settings_select_authed  SELECT  {authenticated}  USING (true)
```

Ou seja, **qualquer utilizador com sessão** (um cliente qualquer da app) consegue
`select * from platform_settings` e vê as 449 linhas, das quais 47 marcadas `is_secret`, incluindo:

- `partner_hidden_markup_pct` = 0.05 (o **markup oculto** — o cliente não devia saber que existe)
- `partner_visible_commission_pct`, `non_partner_markup_pct`, `driver_profit_share_pct`
- `stripe_connect_*`, `stripe_processing_fee_*`, `stripe_payout_fee_*`, `tvde_*`

Prova (JWT de conta normal simulado em rollback): `conta_normal_le_platform_settings total=449
secretas=47 exemplos_sensiveis=driver_profit_share_pct, non_partner_markup_pct,
partner_hidden_markup_pct, partner_visible_commission_pct, stripe_connect_enabled, ...`.

Isto é **pior** do que o buraco já conhecido da RPC `get_setting` (que pelo menos esconde as chaves
`is_secret` a quem não é admin): o SELECT direto à tabela passa ao lado dessa proteção.

## Correção proposta (não aplicada)

Trocar a política por uma que só devolve as chaves **não** secretas a quem não é admin — e deixar o
resto (Stripe, comissões, markup) só para admin / service_role:

```sql
DROP POLICY platform_settings_select_authed ON public.platform_settings;
CREATE POLICY platform_settings_select_publicas ON public.platform_settings
  FOR SELECT TO authenticated
  USING (coalesce(is_secret, false) = false OR is_admin());
```

Antes de aplicar, **procurar quem lê chaves `is_secret` com a sessão do utilizador** (a app pode
estar a ler alguma configuração sensível diretamente da tabela em vez de por RPC) — se houver, essa
leitura passa a dar vazio e é preciso movê-la para uma RPC `SECURITY DEFINER` com guarda, como já se
fez com `bora_mbway_para_cobranca()`. Sem essa verificação, **não aplicar**.

## Porque fica como proposta

Mexe em leitura de preços/comissões/Stripe. Entrega-se pronta; aplica-se com o "vai" do Danilo e
depois da verificação de quem lê a tabela direto.
