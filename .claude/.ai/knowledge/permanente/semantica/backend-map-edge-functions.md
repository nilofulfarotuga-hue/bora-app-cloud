---
tema: backend-map · escopo: projeto · estado: atual · atualizado: 2026-07-05
id: backend-map-edge-functions
tipo: conceito
origem: [MCP list_edge_functions 2026-07-05, supabase/functions/]
ultima_confirmacao: 2026-07-08
zona: vermelha
confianca: auto
---

# Backend Map — Edge Functions

**55 funções ACTIVE** (verificado via MCP `list_edge_functions` 2026-07-05; local: 49 pastas com
`index.ts` em `supabase/functions/`). `jwt` = verify_jwt. 🔴 = zona de dinheiro.
Índice: [backend-map.md](./backend-map.md).
> Nota: a skill CEO-AI e o CLAUDE.md ainda dizem "43/44" — **stale**; atualizar o `SKILL.md`
> aguarda aprovação do Danilo.

## Core dinheiro / pagamentos 🔴

| Função | jwt | Linha |
|---|---|---|
| `dispatch-engine` 🔴 | não | Motor de dispatch (matching estafeta↔pedido). BLINDADA. |
| `stripe-webhook` 🔴 | não | Webhook Stripe (confirmação de pagamentos). BLINDADA. |
| `create-payment-intent` 🔴 | não | Cria PaymentIntent Stripe (cartão). BLINDADA. |
| `create-mbway-payment-intent` 🔴 | não | Cria intent MB WAY. |
| `finalize-order-from-intent` 🔴 | jwt | Cria pedido a partir de intent pago. |
| `refund` 🔴 | jwt | Executa refund (Stripe + wallet split). BLINDADA. |
| `reprocess-refund` 🔴 | jwt | Reprocessa refund falhado. |
| `charge-extra` 🔴 | jwt | Cobra extra off_session pós-entrega (sacos). |
| `pay-debt-standalone` 🔴 | jwt | Pagamento de dívida do estafeta/cliente. |
| `list-saved-cards` | jwt | Lista cartões guardados (Stripe). |
| `tvde-plan-payment` 🔴 | jwt | Pagamento de plano/corrida TVDE — isolada, SEM webhook (2026-07-03). |
| `cleaning-checkout` 🔴 | jwt | Checkout da vertical LIMPEZA (cartão captura manual / MB Way cobra já; padrão tvde-plan-payment, sem webhook). LIVE 2026-07-05 após "vai". Ver [vertical-limpeza.md](./vertical-limpeza.md). |

## Cancelamento 🔴

| Função | jwt | Linha |
|---|---|---|
| `client-cancel-order` 🔴 | jwt | Cancelamento pelo cliente (aplica fee por escalão). |
| `cancel-order-with-choice` 🔴 | jwt | Cancelamento com escolha (refund vs manter). |
| `execute-cancellation` 🔴 | jwt | Executa cancelamento acordado. |
| `admin-cancel-order` 🔴 | jwt | Cancelamento admin. |

## Reservas / Agendamentos 🔴

| Função | jwt | Linha |
|---|---|---|
| `create-reservation-payment-intent` 🔴 | jwt | Intent pré-pagamento de reserva (cartão). |
| `create-mbway-reservation-payment-intent` 🔴 | jwt | Intent reserva MB WAY. |
| `admin-cancel-reservation` | jwt | Cancelamento admin de reserva. |
| `create-appointment-payment-intent` 🔴 | jwt | Intent pagamento de marcação (cartão). |
| `create-mbway-appointment-payment-intent` 🔴 | jwt | Intent marcação MB WAY. |
| `confirm-mbway-appointment-payment` 🔴 | jwt | Confirma pagamento MB WAY da marcação. |

## Notificações / Push

| Função | jwt | Linha |
|---|---|---|
| `notify-driver` | não | Push FCM ao estafeta (oferta). |
| `notify-partner` | jwt | Push ao parceiro (novo pedido). |
| `notify-client` | jwt | Push ao cliente (estado do pedido). |
| `notify-service-provider` | não | Push ao prestador de serviço. |
| `notify-tvde-driver` | jwt | Push ao motorista TVDE (oferta corrida). |
| `notify-tvde-client` | jwt | Push ao passageiro TVDE (estado da corrida). |
| `notify-tvde-chat` | jwt | Push de mensagem de chat TVDE. |
| `notify-chat-message` | jwt | Push de nova mensagem de chat. |
| `notify-admin-urgent` | jwt | Push urgente aos admins. |
| `notify-partner-low-rating` | jwt | Alerta parceiro de rating baixo. |
| `notify-purchase-finalized` | não | Push de compra finalizada (storeShopping). |
| `notify-admin-reimbursement` 🔴 | não | Alerta admin de reembolso pendente. |
| `execute-broadcast` | não | Envia broadcast segmentado em massa. |

## Uploads / Storage

| Função | jwt | Linha |
|---|---|---|
| `upload-avatar` | jwt | Upload de avatar. |
| `upload-receipt` | jwt | Upload de talão. |
| `upload-order-photo` | jwt | Foto do pedido (entrega). |
| `upload-restaurant-asset` | jwt | Logo/hero do restaurante. |
| `upload-driver-document` | jwt | Documentos do estafeta. |

## Suporte / IA / Robot

| Função | jwt | Linha |
|---|---|---|
| `support-chatbot` | jwt | Chatbot de suporte (RAG + skills). |
| `support-submit-ticket` | jwt | Submete ticket de suporte. |
| `support-password-reset` | não | Reset de password via suporte. |
| `reindex-knowledge` | jwt | Reindexa RAG (embeddings). |
| `analyze-conversations` | não | Analisa conversas → sugere skills. |
| `robot-b` | não | Robô B (auto-fix/digest/crosstalk). |
| `admin-ai-assistant` | não | Assistente IA do admin. |
| `gemini-diagnostic` | não | Diagnóstico Gemini. |
| `ocr-receipt` | jwt | OCR de talão (Gemini Flash). |

## Admin / Ops / Catálogo

| Função | jwt | Linha |
|---|---|---|
| `admin-force-driver-logout` | jwt | Força logout do estafeta (revoga sessões). |
| `update-products` | não | Update de catálogo de mercados (cron). |
| `delete-account` | não | Apagar conta (GDPR). |
| `register-partner` | não | Registo de parceiro (restaurante/loja/farmácia). |
| `import-guarda-businesses` | jwt | Importa negócios da Guarda. |
| `privacy-policy` | não | Serve a política de privacidade. |

> BLINDADAS (não deploy sem ordem): `dispatch-engine`, `create-payment-intent`, `refund`, `stripe-webhook`.
