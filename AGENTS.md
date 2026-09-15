# BORA APP — CONTEXTO NUCLEAR (leia isto ANTES de qualquer tarefa)

> Este ficheiro é o núcleo. O detalhe completo vive em `docs/contexto/` — o índice no fim diz onde está o quê. **Abra o capítulo relevante antes de mexer na área correspondente.** Nunca adivinhe: se a resposta não está aqui nem nos capítulos, investigue no código/DB.

---

## 1. O QUE É O BORA

Plataforma multi-serviço para a **Guarda, Portugal**, construída por **um único fundador (Danilo)** com orquestração de IA. Verticais:

- **Delivery** (restaurantes + mercados/supermercados + lojas + farmácias)
- **TVDE** (ride-hailing tipo Uber/Bolt)
- **Limpeza** (tipo Helpling)
- **Reservas** (mesas com pré-pagamento €3)
- **Favores/Errands** (compras por encomenda, OCR de talão)
- **Serviços** (barbearias, salões de beleza — marcações)

Referências de mercado: **Glovo, Uber Eats, iFood, Uber, Bolt, Helpling**. Regra: nunca inventar padrão novo — copiar o que essas apps consagraram.

## 2. QUEM É DANILO (o dono)

- Brasileiro a viver na Guarda, Portugal. Fundador solo. Motorista TVDE (Uber/Bolt) como renda atual — conhece os dois lados do negócio na pele.
- Comunica em PT-BR informal, quase sempre por voz (voice-to-text — mensagens chegam fragmentadas; interpretar pela intenção).
- Não é programador: **decide e aprova**; a execução é 100% dos agentes de IA. NUNCA pedir tarefa manual técnica a ele (exceção: decisões legais/financeiras e ações que as travas de segurança exigem que sejam humanas).
- Estilo: respostas curtas e diretas; odeia repetição e enrolação.

## 3. STACK E IDENTIFICADORES

| Item | Valor |
|---|---|
| Frontend | Flutter (app cliente + estafeta + parceiro + painel admin web) |
| Backend | Supabase — Postgres, RLS, Edge Functions, pg_cron, Realtime, Storage |
| Pagamentos | **Stripe LIVE** (cuidado: cobranças reais) + MB Way |
| Push | Firebase FCM (`boraapp-d2bea`) |
| Repo | `nilofulfarotuga-hue/bora-app-cloud`, branch `autonomous-night-2026-04-29` |
| Supabase project | `ojykpzwqrtusfeakzrna` |
| Package Android | `pt.boraapp.bora` |
| Path local | `C:\Users\danil\Desktop\projetosflutter\bora_app\` |
| Vault Obsidian | `C:\Users\danil\Desktop\Bora` |
| Web app | bora-app-web.pages.dev (mesmo codebase, Cloudflare Pages) |
| Site institucional | bora-site.pages.dev (repo público `bora-site`) |
| PC do Danilo | Acer Celeron N4500, **4GB RAM** — gargalo permanente; nada pesado local |

## 4. REGRAS INVIOLÁVEIS (quebrar = falha grave)

1. **ZONAS PROTEGIDAS** — não tocar sem ordem explícita: `dispatch_engine`, `pricing_service.dart`, `finalizePurchase`, `bora_tokens`, Stripe webhook v17+, RLS de `orders`/`wallets`/`ledger`, `.claude/settings.json` (Trava protege-dinheiro).
2. **versionCode**: o CI (`build_android.yml`) auto-incrementa. NUNCA incrementar no pubspec.
3. **Push = publicação**: push na branch dispara build Android → Play alpha E deploy web. Commits só-`.md` ou só-`.claude/` não disparam (paths-ignore), MAS o paths-ignore avalia TODOS os commits do push — código pendente "pega boleia". Sempre verificar o que viaja junto antes de push.
4. **Idiomas**: apps (cliente/estafeta/parceiro) = **PT-PT**; painel admin = **PT-BR** (só Danilo usa).
5. **Design**: verde `#16A34A`, laranja `#F97316`, fonte Inter. NUNCA alterar fotos reais de produtos.
6. **Painel admin**: toda feature nova/alterada exige perguntar se precisa de correspondência no painel admin (Danilo quer autoridade total: ver/editar/criar/banir/configurar/exportar/auditar).
7. **Testes de pagamento**: sempre em DINHEIRO (Stripe é live — cartão cobra de verdade).
8. **Web + Android saem juntos**: toda atualização que vai pro Play atualiza também o web app.
9. **Fonte de verdade**: 1º `business_rules.md` (vault Obsidian), 2º código do app, 3º padrão Glovo/Uber Eats/iFood. Dúvida → investigar, nunca chutar.
10. **CEO-AI**: todo prompt de missão invoca o orchestrator em `.claude/skills/ceo-ai/` primeiro.

## 5. REGRAS DE DINHEIRO (resumo — detalhe no cap. 03)

- **PARCEIRO** (só restaurantes): 10% comissão visível + 5% markup oculto + 5% taxa serviço. Estafeta €3,80 + €0,20/km.
- **NÃO-PARCEIRO**: preço base + 15% fixo incluído; fee €2,50 fixo. Estafeta €3,80 + €0,20/km + €0,80 + 30% lucro líquido Bora. **TODOS os mercados são não-parceiros.**
- Entrega €2,50 até 4km, +€0,50/km. Cash máx €40. Sacos: restaurante €0,30, mercado €0,10/saco.
- Tokens: cliente ROUND(preço×3) mín 1; estafeta +40 normal / +50 parceiro.
- Refund p/ wallet: split **80% saldo livre + 20% tokens (60d)**, configurável em `platform_settings`.
- Reservas: pré-pagamento €3 (parceiro €2 / Bora €1; no-show e cancel <2h = Bora 100%).
- TVDE ida-e-volta €8 = preço TOTAL do cliente; motorista da ida ganha €4, da volta €3,50, Bora ~€0,50 — acerto no fecho semanal. Payout é SEMANAL, nunca reembolso instantâneo.
- Buffer MB Way: `payment_buffer_total = fees_total + round(estimativa × 1.2)` — NUNCA ×1.15.

**Confundir parceiro/não-parceiro = erro grave.**

## 6. ÍNDICE DO CONTEXTO COMPLETO (`docs/contexto/`)

| Capítulo | Quando abrir |
|---|---|
| `01-fundador-e-visao.md` | Decisões de produto/estratégia; entender "por quê" |
| `02-arquitetura.md` | Mexer em estrutura, CI/CD, deploy, Edge Functions |
| `03-regras-de-negocio.md` | QUALQUER coisa que toque preço, comissão, wallet, refund |
| `04-verticais.md` | Trabalhar em delivery, TVDE, Limpeza, Reservas, Favores, Serviços |
| `05-parceiros-reais.md` | Lojas reais: Sabores de Casa, Ouro e Prata, BeUnique, mini-sites |
| `06-infra-automacao.md` | Hermes, Córtex, loop autônomo, robôs, motor de conhecimento |
| `07-estado-atual.md` | Saber o que está pronto, pendente e em curso |
| `08-licoes-aprendidas.md` | ANTES de repetir abordagem que já falhou (SSH, GPU, OOM...) |

---
*Mantido por Claude.ai a partir da memória persistente + Córtex Bora. Última consolidação: 2026-07-22.*
