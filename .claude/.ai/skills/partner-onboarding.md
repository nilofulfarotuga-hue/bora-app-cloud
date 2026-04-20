---
name: partner-onboarding
description: Use this skill when the user says "SKILL: partner-onboarding", or when work touches new restaurant/store signup — candidacy form, required fields (NIF, IBAN, docs), admin approval flow, welcome email. Triggers on "registar parceiro", "aprovação parceiro", "onboarding restaurante".
version: 1.0.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill planeia o onboarding de parceiros — nunca publica candidatura nem aprova directamente; delega a `admin-panel-engineer` + `executor`. Prazo de 3 dias úteis vem da BR §15.3.

# PARTNER ONBOARDING

## ROLE
Especialista no processo de entrada de novos parceiros (restaurantes / lojas). Garante dados mínimos, validação legal (NIF, IBAN), canal triplo de candidatura e prazo de aprovação.

---

## EXEMPLOS WORKED

### Exemplo 1 — Novo restaurante submete candidatura

**Input (contexto real):**
"Tasquinha da Guarda" submete candidatura via app (`Sou parceiro` no registo) com 9 campos obrigatórios preenchidos: nome, morada, NIF, responsável, telefone, email, IBAN, foto do espaço, horário.

**Processo:**
1. Consultar BR §15.2 → dados obrigatórios:
   - Nome do restaurante/loja
   - Morada
   - NIF / Nome da empresa
   - Nome e telefone do responsável
   - Email
   - IBAN (para receber pagamentos)
   - Foto do espaço / logotipo
   - Horário de funcionamento
   - Tipo de cozinha (italiana, japonesa, etc.)
   - Checkbox "Aceito Termos Parceiro" (BR §15.2 final + §20.1)
2. Validação:
   - NIF: 9 dígitos, algoritmo de check digit PT
   - IBAN: `PT50 + 21 dígitos = 25 caracteres` (validar por módulo 97)
   - Email único (não duplicar parceiro)
   - Checkbox **obrigatório** — sem aceitar, bloquear submit
3. Estado inicial: `pending`.
4. Admin recebe alerta no painel (BR §16.2.3). Revisão em <3 dias úteis (BR §15.3).
5. Aprovado → email boas-vindas automático + `approved` → parceiro pode entrar no dashboard (skill `partner-dashboard-engineer`).

**Output esperado:**
```
✅ PLANO ONBOARDING PARCEIRO — BR §15
Canais candidatura: [contacto_direto_tel, site_form, app_register]
Campos obrigatórios (10): [nome, morada, NIF, responsavel, tel, email, IBAN, foto, horario, tipo_cozinha, checkbox_termos]
Validações: NIF PT mod11, IBAN PT mod97, email único
Estado: pending → admin review ≤3 dias úteis (BR §15.3) → approved
Email boas-vindas: SIM, automático pós-aprovação
Delegar a: admin-panel-engineer (review) + executor (form + validações)
```

**Failure mode:**
Falha se permitir submit sem checkbox — viola GDPR §20.1 e anulável legalmente. Falha se aceitar IBAN não-PT (só aceita `PT50…`).

---

### Exemplo 2 — Parceiro submete sem IBAN

**Input (contexto real):**
Restaurante "Burger Street" tenta submeter mas deixa IBAN em branco. BR §15.2 marca IBAN como obrigatório.

**Processo:**
1. Consultar BR §15.2 → IBAN é obrigatório para receber pagamentos.
2. Validação client-side: bloquear botão "Submeter" se IBAN vazio.
3. Mostrar mensagem clara ao parceiro:
   > "IBAN obrigatório para receber pagamentos semanais. Preenche com o formato `PT50 + 21 dígitos`."
4. Se parceiro desconhece o IBAN → botão "Terminar depois" guarda rascunho, email lembrete 24h depois.
5. Server-side: edge function rejeita INSERT se `iban IS NULL OR iban = ''`.

**Output esperado:**
```
⚠️ BLOQUEIO ONBOARDING — IBAN em falta (BR §15.2)
Mensagem UI: "IBAN obrigatório para receber pagamentos semanais"
Formato: PT50 + 21 dígitos
Opção: "Terminar depois" (rascunho + lembrete 24h)
Server-side guard: rejeitar INSERT sem IBAN
Delegar a: executor (validação + draft save + reminder)
```

**Failure mode:**
Falha se aceitar candidatura sem IBAN — parceiro fica aprovado mas não recebe. Falha se mensagem for vaga ("campo obrigatório") sem indicar formato.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/screens/partner/` (ecrã de registo) | Formulário onboarding |
| `lib/auth/auth_store.dart` | Cria conta parceiro + metadata `bora_role=partner` |
| `.claude/.ai/business_rules.md` §15 | Onboarding completo (canais, campos, prazo, custo) |
| `.claude/.ai/business_rules.md` §16.2.3 | Admin aprova candidaturas pendentes |
| `.claude/.ai/business_rules.md` §20.1 | Checkbox obrigatório consentimento |
| `.claude/.ai/business_rules.md` §19 | Bucket `restaurant-photos` (público) |
| skill `admin-panel-engineer` | Revisão + aprovação |
| skill `partner-dashboard-engineer` | Acesso pós-aprovação |
| skill `notifications-engineer` | Email boas-vindas + lembretes |

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber Eats onboarding** — 3 dias úteis SLA mundial. Web self-service: submit docs → photo verification automática + manual review de NIF/tax docs → active. Integração com Stripe Connect para payouts.
>
> **iFood** — onboarding 100% digital, ~48h. Gestor digital envia contrato electrónico via Clicksign. Integra POS (OpenDelivery) para restaurantes grandes.
>
> **Glovo** — web form + call back comercial humano para negociar comissão. Taxa de adesão inicial (variável por cidade).
>
> **Bora equivalente:** BR §15 combina 3 canais (tel direto personalizado, site futuro, app self-service) + prazo igual a Uber (3 dias). **Diferenciador:** sem taxa de adesão nem mensalidade (BR §15.4) — só ganha por comissão 10+5+5. Competitivo para atrair parceiros locais na Guarda.

---

## RESPONSABILIDADES

- ✅ Formulário com 10 campos obrigatórios (BR §15.2)
- ✅ Validação de NIF PT (mod 11) e IBAN PT (mod 97)
- ✅ Checkbox termos parceiro obrigatório
- ✅ Estado `pending` → admin review → `approved` / `rejected`
- ✅ Email boas-vindas automático pós-aprovação
- ✅ Rascunho + lembrete 24h para candidaturas incompletas
- ✅ Sem taxa de adesão (BR §15.4)

## FRONTEIRAS

| Situação | Skill correcta |
|---|---|
| Form + validação + estado candidatura | **partner-onboarding** (eu) |
| Admin aprova/rejeita | `admin-panel-engineer` |
| Pós-aprovação: acesso ao dashboard | `partner-dashboard-engineer` |
| Email/push boas-vindas | `notifications-engineer` |
| Upload foto espaço (bucket privado/público) | `security-engineer` (verifica policies) |

## NÃO PODE FAZER

- ❌ Aprovar candidatura (é do admin)
- ❌ Pular validação de NIF ou IBAN
- ❌ Criar parceiro sem consentimento (ilegal GDPR §20.1)
- ❌ Cobrar taxa de adesão (BR §15.4 exclui isso)
- ❌ Editar `pricing_service.dart` para dar comissão diferente ao novo parceiro

---

## RULES

- Source of truth: `.claude/.ai/business_rules.md` v2 §15 · §16.2.3 · §20.1
- SLA revisão: 3 dias úteis (BR §15.3) — monitorar em `admin-panel-engineer`
- Campos obrigatórios BR §15.2 não são negociáveis
- Ordem canónica: **partner-onboarding** → `admin-panel-engineer` (review) → `partner-dashboard-engineer` (acesso)
