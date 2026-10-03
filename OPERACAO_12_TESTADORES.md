# OPERAÇÃO "12 TESTADORES → PRODUÇÃO" — Relatório Vivo

> Fonte de verdade da operação. Atualizado pelo Claude a cada fase.
> Última atualização: 2026-07-06 (sessão iniciada)

## Objetivo
Cumprir o requisito do Google Play para contas pessoais pós-nov/2023: **teste fechado com
≥12 testadores opt-in durante 14 dias contínuos** → depois candidatura ao acesso à Produção.

- App: **Bora App** (`pt.boraapp.bora`) · Developer ID 5372142912736686834
- Contacto: boraappbora@gmail.com
- Estratégia: testadores pagos (PrimeTestLab, 25×) + família no Brasil

## Estado por fase

| Fase | Estado | Notas |
|---|---|---|
| 0a — Promover build p/ teste fechado | ✅ FEITO | **370 publicado no alpha via API** (validate+commit OK, 2026-07-06). Em revisão do Google. |
| 0b — Conteúdo da app + países PT+BR | ✅ FEITO | App content: 14 declarações OK, **0 pendências**. Países do alpha: **Brasil + Portugal** ✅ |
| 1 — Lista testadores + link opt-in | ✅ FEITO | Grupo **bora-app-testers@googlegroups.com** criado E **ligado à faixa Alpha** (PATCH 200, persistido, verificado após reload). Email de comentários: boraappbora@gmail.com. Link opt-in oficial copiado do Console (abaixo). |
| 2 — Contratar serviço pago | ✅ PAGO (2026-07-06) | **Order #P08075612 — 25 testadores, $21.49.** Wizard de setup em curso (ver secção PrimeTestLab abaixo). |
| 3 — Mensagem família | ✅ FEITO | `MENSAGEM_FAMILIA_TESTE.md` na raiz do projeto — copiar e colar no WhatsApp. |
| 4 — Monitorização 14 dias | ✅ FEITO | Tarefa agendada Windows **BoraTesteFechadoMonitor** (diária 09:03, corre na bateria, recupera execuções perdidas). Log: `.claude/.ai/reports/teste-fechado-monitor.log`. Alertas → `ALERTA_TESTADORES.txt` no Desktop. |
| 5 — Questionário + produção | ⏳ pendente | só após 14 dias |

## 🖐️ AÇÕES DO DANILO (só falta 1)

1. **WhatsApp da família**: copiar o bloco de `MENSAGEM_FAMILIA_TESTE.md` e enviar.
   Emails que chegarem → para mim (adiciono ao grupo bora-app-testers).

Tudo o resto está feito ou corre sozinho: pagamento ✅ · setup PrimeTestLab 7/7 submetido ✅ ·
grupos ligados à faixa ✅ · países 177 ✅ · alterações em revisão no Google ✅ · monitor diário ✅.

## O que acontece a seguir (sem intervenção)

1. Google aprova as alterações (1–7 dias; email para boraappbora@gmail.com).
2. PrimeTestLab deteta a aprovação (monitorizam de hora em hora) e inicia os testes em
   30 min–4 h — os testadores deles entram via grupo khadem + link opt-in.
3. Quando o dashboard do Console mostrar **≥12 testadores a participar** → definir
   `start_date` em `.claude/scripts/monitor_teste_fechado_config.json` → relógio dos 14 dias.
4. ~Dia 7: promover build novo Interno→Alpha (Claude, via API) = atualização de meio de período.
5. Dia 14+: preparar questionário de produção (usar relatório do PrimeTestLab "VER RELATÓRIOS"
   no painel deles + feedback da família) → Danilo revê e submete.

## Checklist do Google para a candidatura à produção (visto no dashboard 2026-07-06)

- ✅ Publique um lançamento de teste fechado
- ⭕ Tenha ≥12 testadores a participar — **0 testadores atualmente**
- ⭕ Execute o teste com ≥12 testadores durante ≥14 dias

## Factos verificados (2026-07-06, via Play Developer API — read-only)

- Track **production**: sem releases
- Track **beta** (Teste Aberto): sem releases — bloqueado até ter produção (cadeado)
- Track **alpha** (Teste Fechado): build **309** (1.0.1) — desatualizado
- Track **internal**: build **370** (1.0.1) — o mais recente
- Bundles no Console: ..., 366, 367, 368, 369, **370**
- Testers via API (alpha/beta): sem Google Groups configurados (lista de emails só no Console)

## Datas-chave

- Início da contagem de 14 dias: **(por definir — dia em que houver ≥12 opt-ins ativos)**
- Data-alvo (início + 14): (por definir)
- Atualização de meio de período (~dia 7): (por definir)

## Link de opt-in (OFICIAL — copiado do Console 2026-07-06)

- **Web**: https://play.google.com/apps/testing/pt.boraapp.bora ✅ (confirmado no Console,
  secção "Como os testadores participam no seu teste" → Adesão na Web)
- **Android** (Play Store direta): https://play.google.com/store/apps/details?id=pt.boraapp.bora
- Só funciona para membros do grupo `bora-app-testers@googlegroups.com` (+ release aprovada)

## PrimeTestLab — Order #P08075612 (pago 2026-07-06)

- Dashboard: https://primetestlab.com/user/testing/app/3653/setup (login criado por eles,
  credenciais enviadas para boraappbora@gmail.com)
- **Testadores deles = Google Group `khadem-testers-service@googlegroups.com`** — JÁ adicionado
  à faixa Alpha (junto com `bora-app-testers@googlegroups.com` da família). PATCH 200 verificado.
  ⚠️ NÃO adicionar emails individuais deles ao nosso grupo (aviso do serviço — não funciona).
- **Países da faixa fechada: TODOS (Segmentados 177)** — exigência do serviço (testadores
  globais). NÃO afeta produção (targeting separado). Feito via UI + verificado após reload.
- **Envio ao Google CONFIRMADO** (2026-07-06 23:17): Vista geral da publicação mostra
  **"Alterações em revisão"** (4 alterações: build 370 + grupos + países). Revisão: até 7 dias
  (normalmente 1-3).
- **Wizard 7/7 CONCLUÍDO + submetido**: 1 Testers ✅ · 2 Countries ✅ · 3 Submit ✅ ·
  4 URL (`apps/testing/pt.boraapp.bora`, "Package detected" ✅) · 5 Credentials (signup próprio,
  sem verificação de telefone) ✅ · 6 Free ✅ · 7 Notas (explorar sem comprar, PT, uso diário,
  sem encomendas reais) ✅. Painel deles: **"EM ANÁLISE"** — testes arrancam 30 min–4 h depois
  de o Google aprovar. Contacto preferido: tickets de suporte (sem expor telefone).

## Sequência até ao arranque do relógio de 14 dias

1. Danilo aceita Termos do Console → Claude seleciona o grupo na aba Testadores do track alpha
   (Testar e lançar → Testes fechados → Gerir faixa → Testadores → Grupos Google →
   `bora-app-testers@googlegroups.com` → Guardar) + copia o link opt-in oficial da página.
2. Danilo paga PrimeTestLab → eles mandam emails dos testadores (4–6 h) → Claude adiciona os
   emails ao grupo (https://groups.google.com/g/bora-app-testers → People → Add members,
   com "Directly add members" ativo) e entrega-lhes o link opt-in
   https://play.google.com/apps/testing/pt.boraapp.bora via dashboard do PrimeTestLab.
3. Família manda emails → mesmos passos.
4. Quando o dashboard do Console mostrar **≥12 testadores a participar**: definir
   `start_date` em `.claude/scripts/monitor_teste_fechado_config.json` (YYYY-MM-DD) —
   o monitor diário passa a contar os 14 dias, avisa da atualização de meio de período
   (~dia 7, promover build novo do Interno via API — o Claude faz) e anuncia o dia 14.
5. Dia 14+: Claude prepara as respostas do questionário; Danilo revê e clica Submeter.

## Infra criada nesta sessão

- Tarefa agendada Windows: `BoraTesteFechadoMonitor` (09:03 diária; para remover:
  `schtasks /Delete /TN BoraTesteFechadoMonitor /F`)
- Scripts: `.claude/scripts/monitor_teste_fechado.py` + `.cmd` + `_config.json`
- Google Group: `bora-app-testers@googlegroups.com` (owner: nilofulfarotuga@gmail.com;
  membros iniciais: Danilo + boraappbora)
- Track alpha: build 370 publicado 2026-07-06 (em revisão do Google — normal, 1–3 dias)

## O que falta do Danilo

- Aceitar Termos do Play Console (1 clique) → destrava a ligação do grupo ao track
- Pagar $21.49 no PrimeTestLab (página Stripe aberta)
- Enviar mensagem WhatsApp à família + recolher emails
