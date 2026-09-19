---
id: beleza-terminologia-profissional-2026-07-18
---

# Terminologia genérica Barbeiro/Profissional — gestão de serviços do parceiro

## Contexto
No hub de gestão de serviços do parceiro (Agenda / Adicionar marcação / Bloquear
horário / Serviços / Barbeiros / Financeiro) e no formulário de adicionar membro
da equipa, a terminologia estava fixada em "barbeiro/barbeiros" para todas as
categorias de `service_providers`. A vertical Beleza também cobre cabeleireiro,
manicure, esteticista, etc., para quem "barbeiro" não faz sentido.

## O que foi feito
Criado `lib/utils/staff_terminology.dart` — helper `StaffTerminology` que devolve
`Barbeiro/Barbeiros` quando `category == 'barbershop'` e `Profissional/Profissionais`
para qualquer outra categoria (ex.: `beauty`). Aplicado em todos os pontos da
gestão de equipa onde o termo aparecia:

- Título do AppBar e da tile "Barbeiros" no hub → plural dinâmico
- Subtítulo do hub ("Agenda, serviços, ... e financeiro") → plural dinâmico
- Subtítulo da tile "Bloquear horário" → singular dinâmico
- Botão flutuante "Novo barbeiro" → "Novo {termo}"
- Título do formulário "Editar/Novo barbeiro" → dinâmico
- Label do campo "Nome" → "Nome do {termo}"
- Diálogo e snackbar de desactivação → dinâmico
- Empty state ("Sem barbeiros" / "Adiciona o primeiro...") → dinâmico
- Mensagem de validação "Indica o nome do barbeiro." → dinâmico

Nenhuma lógica, foto ou layout foi alterada — só strings PT-PT.

Verificado que `partner_add_walk_in_screen.dart` e `partner_block_slot_screen.dart`
não contêm menções a "barbeiro" (fora de escopo, nada a fazer).

`admin_service_providers_screen.dart` (painel admin) ainda tem "Barbeiros"
fixo — fora do escopo desta tarefa (só o app do parceiro foi pedido), fica
como candidato futuro se o Danilo quiser paridade total.

## Ficheiros tocados
- `lib/utils/staff_terminology.dart` (novo)
- `lib/screens/partner/services/partner_manage_staff_screen.dart`
- `lib/screens/partner/services/partner_services_hub_screen.dart`

## Commit
```
59f0310330601edbfbd3309acff61fc438ed8a20 fix(parceiro-servicos): terminologia Barbeiro/Profissional por categoria

Autor: Danilo (Hermes autonomous) <nilofulfarotuga@gmail.com>
Data: 2026-07-18 23:01:53 +0100
```
Pushed para `autonomous-night-2026-04-29` (`1ae9138..59f0310`).

## Nota operacional
`lib/screens/partner/services/partner_manage_staff_screen.dart` tinha, no
working directory, uma feature não-commitada de upload de foto (import
`image_picker`, Edge Fn `upload-restaurant-asset`) — provavelmente WIP de
outro executor concorrente. Foi cuidadosamente preservada: isolei o commit
de terminologia via `git checkout --` (repõe a partir do index) + edição
pontual, depois restaurei a feature de foto por cima, ainda não-commitada,
para não perder o trabalho alheio. `flutter analyze` limpo nos 3 ficheiros.
