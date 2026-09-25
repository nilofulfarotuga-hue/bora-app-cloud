# Equipa e Contactos — Bora App

## Fundador / Admin

| Nome | Papel | Contacto |
|---|---|---|
| Danilo | CEO / Admin / Único admin atual | nilofulfarotuga@gmail.com |
| Bora App | Email da app | boraappbora@gmail.com |
| — | Telefone | +351 937 501 673 |

---

## Papéis na Plataforma

| Perfil | Responsabilidade |
|---|---|
| Admin (Danilo) | Gestão total — dashboard financeiro, aprovação de drivers, parceiros |
| Cliente | Faz pedidos, paga |
| Estafeta (Driver) | Aceita e entrega pedidos |
| Parceiro | Restaurante/loja com acordo comercial com a Bora |

---

## Acesso Admin

- Acesso por email allowlist temporário em `admin_dashboard_screen.dart`
- Dashboard: métricas financeiras, gestão de drivers, aprovação, pagamentos, pedidos, parceiros
- **Pendente:** substituir allowlist por RLS/role real no Supabase

---

## Contas Demo (Desenvolvimento)

| Perfil | Login | Password |
|---|---|---|
| Cliente | `cliente@bora.app` | `123456` |
| Driver | phone `910000000` | `123456` |
| Parceiro | — (sem conta demo) | — |

---

## Infraestrutura

| Serviço | Detalhe |
|---|---|
| Supabase | `ojykpzwqrtusfeakzrna.supabase.co` |
| Stripe | Integrado (chave em `main.dart`) |
| Google Maps | API key em `lib/config/maps_config.dart` |
| Firebase | Desativado (pendente `google-services.json`) |

---

## Aprovações Obrigatórias (CLAUDE.md)

Qualquer tarefa que toque em:
- Pagamentos (Stripe, MBWay, cash)
- Base de dados (tabelas, triggers, migrations)
- Segurança (RLS, auth, permissões)
- Esforço estimado > 1h

**Requer aprovação explícita do Danilo antes de executar.**
