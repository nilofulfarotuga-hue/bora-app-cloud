# Sessão 7-UI-BUG004 — Validação manual (2026-05-08)

## Validação automática (executada pela sessão)

- [x] `flutter analyze` 55 issues → 55 issues final (baseline mantida)
- [x] Refactor `driverCancelAcceptedOrder` compila sem novos erros
- [x] Imports `cancel_blocked_pickup_sheet.dart` +
      `support_chat_screen.dart` resolvem
- [x] T37 backend smoke continua a passar (não tocado)
- [x] Espelho Obsidian sincronizado
      (`.obsidian-vault/sessoes/07e_b_bugs.md`)

## Checklist manual (pendente — requer device/emulador)

> ⚠️ Esta sessão alterou UI mas o ambiente de desenvolvimento corrente
> não tem device físico ligado para validar a renderização. Checklist
> abaixo deve ser executada por Danilo (ou em sessão dedicada de QA)
> antes de release.

### Cenário 1 — golden path (cancel pós-pickedUp)
- [ ] Driver app: order em status `pickedUp`
- [ ] Tap no botão "Cancelar entrega" → AlertDialog "Cancelar entrega?"
- [ ] Tap em "Sim, cancelar" → bottom sheet aparece (NÃO SnackBar)
- [ ] Sheet renderiza: drag handle, título, subtítulo, 3 botões
- [ ] Cores: botão verde (`AppTheme.primary` #1B5E20), botão laranja
      outline (`AppTheme.secondary` #E65100), botão texto cinza

### Cenário 2 — botão "Contactar suporte"
- [ ] Tap → bottom sheet fecha
- [ ] `SupportChatScreen` abre com pre-fill no input:
      `"Preciso cancelar o pedido #ID (já recolhido). Motivo: "`
- [ ] Cursor está no fim da string (utilizador continua a escrever)
- [ ] Greeting do assistant aparece em cima
      (`"Olá! Sou a Bora IA. Como posso ajudar?"`)
- [ ] Send → response vem da `support-chatbot` Edge Fn v8

### Cenário 3 — botão "Ligar agora"
- [ ] Tap → dialer do sistema abre com `+351937501673` preenchido
- [ ] **Testar device REAL** (emulator não tem dialer)
- [ ] iOS + Android ambos validados
- [ ] Se app não consegue lançar: SnackBar fallback "Liga manualmente"

### Cenário 4 — botão "Voltar"
- [ ] Tap → bottom sheet fecha
- [ ] Sem efeito secundário (sem SnackBar, sem nav)
- [ ] Order continua em status `pickedUp` (state preservado)

### Cenário 5 — regressão (cancel pré-pickup)
- [ ] Order em status `driverAccepted` (pré-pickup)
- [ ] Tap "Cancelar entrega" → AlertDialog → "Sim, cancelar"
- [ ] **NÃO** mostra bottom sheet — mostra SnackBar
      "Entrega cancelada. Pedido devolvido ao sistema."
- [ ] Order volta a `callingDriver` em DB

### Cenário 6 — regressão (RPC error genérico)
- [ ] Order com network down ou RPC error não-pickedUp
- [ ] SnackBar "Não foi possível cancelar a entrega." aparece
      (não bottom sheet)

## Permissions Android/iOS — validação build

- [ ] Android build: `flutter build apk` sem erros relacionados a
      AndroidManifest
- [ ] iOS build: `flutter build ios` sem warnings de Info.plist
- [ ] `tel:` launcher funcional em Android device físico
- [ ] `tel:` launcher funcional em iOS device físico (com novo
      `LSApplicationQueriesSchemes`)

## Não validado (fora de scope)

- Test E2E novo para UI Flutter — T37 backend já cobre o caminho RPC.
- Validação visual screenshot — sem device disponível.
- Acessibilidade (TalkBack/VoiceOver) — futuro.
