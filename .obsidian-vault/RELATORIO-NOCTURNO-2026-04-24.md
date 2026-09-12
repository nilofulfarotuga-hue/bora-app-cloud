# Relatório Nocturno — Análise Completa do Projecto Bora
**Data:** 24 Abril 2026 | **Modo:** Análise total, zero alterações ao código

---

## O que foi feito esta noite

Análise ficheiro por ficheiro de todo o projecto `bora_app` (128 ficheiros Dart, 9 Edge Functions, backend Node.js). Resultado escrito no Obsidian.

---

## Novos ficheiros criados no Obsidian

### 📁 bugs/ (7 bugs novos)
| Ficheiro | Prioridade |
|---------|-----------|
| `BUG-012-credenciais-hardcoded.md` | 🔴 Crítico |
| `BUG-013-mbway-stub.md` | 🔴 Crítico |
| `BUG-014-stripe-modo-teste.md` | 🔴 Crítico |
| `BUG-015-reconciliacao-buffer.md` | 🟡 Médio |
| `BUG-016-driver-location-dual-stream.md` | 🟡 Médio |
| `BUG-017-cancelamento-cliente.md` | 🟠 Alta |
| `BUG-018-ratings-sem-persistencia.md` | 🟠 Alta |

### 📁 ideias/ (3 ficheiros novos)
| Ficheiro | Conteúdo |
|---------|---------|
| `ux-cliente.md` | 30+ melhorias de UX para o cliente (home, tracking, pagamentos, ratings, notificações) |
| `ux-parceiro.md` | 25+ melhorias de UX para o parceiro (dashboard, produtos, financeiro, reservas) |
| `comparacao-concorrentes.md` | Análise Uber Eats vs iFood vs Glovo — o que copiar, o que diferencia a Bora |

### 📁 arquitetura/ (pasta nova — 4 ficheiros)
| Ficheiro | Conteúdo |
|---------|---------|
| `fluxo-pedido.md` | Ciclo de vida completo de um pedido (4 tipos de pedido, estados, pagamentos, dispatch) |
| `fluxo-autenticacao.md` | Login/session para cliente, driver, parceiro e admin |
| `edge-functions.md` | Inventário das 9 Edge Functions — para que servem, estado, variáveis necessárias |
| `dependencias-ficheiros.md` | Mapa de quem usa quem (stores, services, models, config) |
| `mapa-ecras.md` | Todos os 44 ecrãs organizados por fluxo, com estado e notas |

### 📁 negocios/ (1 ficheiro novo)
| Ficheiro | Conteúdo |
|---------|---------|
| `regras-negocio-no-codigo.md` | Regras implícitas no código: buffer 15%, tipos de utilizador, aprovação drivers, GDPR |

### 📁 entregas/ (1 ficheiro novo)
| Ficheiro | Conteúdo |
|---------|---------|
| `tarefas-pendentes-codigo.md` | 18 tarefas ordenadas por prioridade, com esforço estimado (~4.5 semanas total) |

---

## Os 3 problemas mais urgentes (descobertos esta noite)

### 🔴 1. Stripe está em modo de TESTE
A chave `pk_test_` no `main.dart` significa que **cartões reais não funcionam em produção**. Trocar para `pk_live_` antes de lançar.

### 🔴 2. MBWay é uma mentira
O botão MBWay no app **simula sucesso mas não cobra nada**. Ou esconder o botão (30 min) ou implementar integração real (semanas).

### 🔴 3. Credenciais expostas no código
A `anonKey` do Supabase e a chave Stripe estão literalmente no `main.dart`. Qualquer pessoa com o APK pode extrai-las. Usar `--dart-define` no build.

---

## Diferenciais da Bora vs concorrentes (para marketing)

1. **Reservas de mesa integradas** — Uber Eats, iFood e Glovo não têm isto
2. **"Carregar compras"** — acompanhamento físico no supermercado, sem equivalente nos concorrentes
3. **MBWay** — quando implementado, é o método de pagamento preferido em Portugal
4. **Operação local** — drivers que conhecem a cidade = entregas mais rápidas

---

## Quick wins (alto impacto, baixo esforço)

| Tarefa | Esforço | Impacto |
|--------|---------|---------|
| Esconder botão MBWay até estar pronto | 30 min | Alto — evita clientes sem pagar |
| Activar Google Pay via Stripe | 1-2 dias | Alto — reduz abandono no checkout |
| Foto do driver no tracking | 2-4 horas | Médio — melhora UX |
| Tags de avaliação (Rápido, Simpático...) | 4-6 horas | Médio — mais dados de qualidade |
| Rating persistente no Supabase | 1 dia | Alto — dados reais para admins |

---

## Estado geral do projecto

**O app está ~80% pronto para lançamento.** Os 20% que faltam são:
- Stripe live mode (crítico)
- Push notifications (crítico)
- Cancelamento de pedido pelo cliente (alta)
- Ratings com persistência (alta)
- Driver flow completo (alta)

Com foco nestas 5 áreas, o lançamento está a ~2 semanas de trabalho intenso.
