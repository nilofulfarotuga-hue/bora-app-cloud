-- LIMPEZA — guia do que fazer e do que levar (15/10/2026, pedido do Danilo).
--
-- Porquê: uma cliente (Stephanie) perguntou no suporte "como é a limpeza
-- standard?". O robô respondeu, mas a profissional que aceita a limpeza não
-- tinha em lado nenhum o que cada tipo inclui nem o que tem de levar.
-- Regra do Danilo: sempre que houver uma limpeza, a profissional vê no app o
-- que tem de fazer e o que tem de levar, em português simples.
--
-- Onde vive a verdade: estas chaves em platform_settings (categoria
-- 'cleaning'). O app da profissional lê-as; o Danilo edita-as no painel
-- (Configurações > CLEANING). Uma linha por item; a primeira linha é a
-- explicação curta; linhas começadas por "NÃO inclui" saem a vermelho.
-- Não mexem em nenhum valor cobrado ou pago.

insert into public.platform_settings (key, value, description, category) values
('limpeza_guia_standard', to_jsonb($t$É a limpeza normal da casa, para a manter limpa e arrumada.
Cozinha: limpar bancadas, fogão por cima, lava-loiça, torneiras, armários e eletrodomésticos por fora.
Loiça: lavar ou pôr na máquina a loiça que estiver no lava-loiça.
Casa de banho: lavar e desinfetar sanita, lavatório, duche ou banheira, espelho e torneiras.
Quartos e sala: tirar o pó dos móveis e superfícies ao alcance da mão e fazer as camas.
Chão: aspirar e lavar o chão da casa toda.
Lixo: esvaziar os caixotes e pôr saco novo.
NÃO inclui: dentro do forno e do frigorífico, janelas por fora, paredes, tetos e passar roupa.$t$::text),
 'Guia da profissional: o que fazer na limpeza Standard (uma linha por item)', 'cleaning'),

('limpeza_guia_profunda', to_jsonb($t$É tudo o que está na Standard, feito mais a fundo, e ainda:
Cozinha: dentro do forno, do micro-ondas e do frigorífico (se estiver vazio); tirar a gordura dos armários e do exaustor.
Casa de banho: tirar o calcário das torneiras, do duche e dos azulejos; limpar as juntas.
Rodapés, portas, puxadores e interruptores.
Janelas e caixilhos pelo lado de dentro.
Pó nos sítios altos: candeeiros e cima dos armários.
Por baixo e por trás dos móveis leves (os pesados não se arrastam).
NÃO inclui: janelas por fora em andares altos, paredes, tetos e passar roupa.$t$::text),
 'Guia da profissional: o que fazer na limpeza Profunda (uma linha por item)', 'cleaning'),

('limpeza_guia_pos_obras', to_jsonb($t$É a limpeza depois de obras ou mudanças: casa com pó de obra e restos de tinta ou cimento.
Tirar o pó fino de todas as superfícies, portas, janelas e rodapés.
Tirar pingos de tinta, cimento e cola do chão e dos vidros, com cuidado para não riscar.
Janelas e caixilhos pelo lado de dentro.
Cozinha e casas de banho a fundo, como na Profunda.
Aspirar e lavar o chão as vezes que for preciso até sair o pó todo.
NÃO inclui: retirar entulho, restos de material ou móveis.$t$::text),
 'Guia da profissional: o que fazer na limpeza Pós-obras (uma linha por item)', 'cleaning'),

('limpeza_guia_levar_produtos_profissional', to_jsonb($t$O cliente pagou para levares tu os produtos de limpeza. Leva:
Detergente multiusos
Desengordurante para a cozinha
Lixívia ou desinfetante para a casa de banho
Limpa-vidros
Anticalcário
Detergente para o chão
Panos de microfibra, esponjas e luvas
Sacos do lixo
Na Profunda e na Pós-obras leva também um raspador de vidro e uma escova para as juntas.$t$::text),
 'Guia da profissional: o que levar quando o cliente escolheu "A profissional leva" os produtos', 'cleaning'),

('limpeza_guia_levar_produtos_cliente', to_jsonb($t$Os produtos de limpeza são do cliente: usa os que estão em casa.
Leva só as tuas luvas e uns panos, por precaução.
Se faltar algum produto, avisa o cliente pelo chat antes de começares.$t$::text),
 'Guia da profissional: o que levar quando o cliente usa os produtos de casa', 'cleaning'),

('limpeza_guia_equipamento', to_jsonb($t$Aspirador, balde e esfregona são do cliente.
Se o cliente não tiver, combina com ele pelo chat antes de ires.$t$::text),
 'Guia da profissional: quem leva aspirador, balde e esfregona', 'cleaning')
on conflict (key) do nothing;

-- Robô do suporte: passa a saber explicar cada tipo de limpeza, o tempo, os
-- produtos e o cancelamento (antes inventava a lista e esquecia tempo e
-- produtos). Valores em euros iguais aos de platform_settings a 15/10/2026.
insert into public.support_skills
  (skill_name, version, category, mode, requires_human_handoff, playbook_md, allowed_tools, examples, active)
select 'CLEANING_INFO', 1, 'faq', 'read_only', false, $p$
# CLEANING_INFO

**Quando usar:** o cliente pergunta como é a limpeza, o que inclui, a diferença
entre Standard, Profunda e Pós-obras, quanto tempo demora, se a profissional
leva produtos ou aspirador, ou como cancelar uma limpeza.

**Tools:** [] (resposta directa). Responder em PT-PT, curto e simples.

## Tipos
- **Standard** (limpeza normal da casa): cozinha (bancadas, fogão por cima,
  lava-loiça, armários e eletrodomésticos por fora), loiça do lava-loiça,
  casa de banho lavada e desinfetada (sanita, lavatório, duche/banheira,
  espelho), pó nos móveis ao alcance, fazer as camas, aspirar e lavar o chão
  da casa toda, esvaziar o lixo. NÃO inclui dentro do forno e do frigorífico,
  janelas por fora, paredes, tetos nem passar roupa.
- **Profunda**: tudo da Standard, mais a fundo, e ainda dentro do forno,
  micro-ondas e frigorífico (vazio), gordura dos armários e exaustor, calcário
  e juntas da casa de banho, rodapés, portas, puxadores e interruptores,
  janelas e caixilhos por dentro, pó nos sítios altos, por baixo dos móveis
  leves. Custa mais 40% que a Standard.
- **Pós-obras** (depois de obras ou mudanças): pó fino de obra em tudo,
  pingos de tinta, cimento e cola no chão e vidros, janelas por dentro,
  cozinha e casas de banho a fundo, chão lavado até sair o pó. NÃO inclui
  retirar entulho, material ou móveis. Custa mais 60% que a Standard.

## Preço e tempo (Standard, preço fixo)
- T0/T1: 35 € · cerca de 3 horas
- T2: 45 € · cerca de 4 horas
- T3: 55 € · cerca de 5 horas
- T4 ou maior: 70 € · cerca de 6 horas
- Também dá para marcar por hora: 12 €/hora, mínimo 2 horas.
- Semanal ou quinzenal: 10% de desconto.

## Produtos e equipamento
- Na marcação o cliente escolhe: usar os produtos de casa (sem custo) ou a
  profissional levar os produtos (+3 €).
- Aspirador, balde e esfregona são do cliente.

## Cancelar
- Mais de 24 horas antes: grátis.
- Entre 24 e 2 horas antes: paga metade.
- Menos de 2 horas antes: paga o valor todo.

## Regras
- O preço final aparece sempre na app antes de confirmar; se o cliente
  quiser um valor exacto para o caso dele, mandar simular na app.
- Não prometer tarefas fora da lista; pedidos especiais combinam-se com a
  profissional pelo chat da limpeza.
$p$, '{}', $e$[
  {"user":"como é a limpeza standard?","assistant":"É a limpeza normal da casa: cozinha por fora, loiça, casa de banho lavada e desinfetada, pó nos móveis, camas feitas e o chão aspirado e lavado. Num T2 são 45 € e cerca de 4 horas. Pode usar os seus produtos ou pedir que a profissional os leve (+3 €)."},
  {"user":"a profissional leva aspirador?","assistant":"O aspirador, o balde e a esfregona são do cliente. Os produtos de limpeza podem ser os seus ou a profissional leva-os por mais 3 €."}
]$e$::jsonb, true
where not exists (select 1 from public.support_skills where skill_name = 'CLEANING_INFO');
