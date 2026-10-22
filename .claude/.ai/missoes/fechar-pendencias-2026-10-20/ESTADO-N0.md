# ESTADO-N0 — missão geral-noite-21-10 (run_id geral-noite-2026-10-21)

Medido a 21/10/2026 entre 20:27 e 20:38 (Lisboa), pela sessão "Fechar pendências noite 21/10"
(local_6914492a, Opus 5.5, modo ignorar permissões). Só leitura.

## Máquina

RAM do PC novo: 14 GB no total, disponível 995 MB às 20:27 e 1736 MB às 20:48
(`Win32_PerfFormattedData_PerfOS_Memory.AvailableMBytes`). O grosso está nas sessões do Claude
abertas (8 processos `claude`, cerca de 3 GB). Emulador precisa de 3 GB livres: não cabe agora.

## Quem já está a trabalhar (para não duplicar)

- Sessão "Fechar pendências 2026-10-20" (local_41766afb, ocupada): enviou o A2 às 19:20Z
  (4d04865b..e768931a), ligou `tvde_fila_inteligente_enabled=true` às 19:21Z por
  `admin_update_setting` (auditado, e2e_log 4252), tem uma vigia de 45 min da fila e lançou às
  ~20:22 o agente-reservas do A3 no `C:\BoraLocal\wt-reservas-21-10` (ficheiros a mudar às 20:29).
  Combinado por mensagem às ~20:33: ela fica SÓ com o A3 e a vigia dela; o resto é desta sessão.
- Sessão do e-mail dos agentes (`agentes-email-2026-10-21`, terminal "bora-app-b3"): parada desde
  20:22 à espera de um clique para aplicar a migração `agentes_email_ajustes`. Recusou receber a
  mensagem de divisão (modo de permissões diferente). Já escreveu as 3 migrações da caixa no
  `C:\BoraLocal\wt-agentes-email-21-10` (por committar).
- Sessão das encomendas de 19/10 (`encomendas-igual-tvde-2026-10-19`, terminal "bora-app-fa"):
  parada desde 20:21 num comando de leitura à espera de clique. Também recusou a mensagem.

## Git

- origin/autonomous-night-2026-04-29 = `e768931a` (o A2 completo já está lá).
- Ramos: fila-20-10 = origin (0 à frente); encomendas-20-10 0 à frente; reservas-21-10 = origin com
  alterações por committar (agente do A3); agentes-email-21-10 0 à frente com 3 migrações soltas;
  chave-nova-16-10 2 à frente (d5d8f127 seis Edges aceitam a chave nova; bf58dc11 order-edit-settle)
  e 65 atrás.
- Pasta principal (C:\BoraLocal\projetosflutter\bora_app): 104 atrás e 1 commit só de documentação
  por enviar (d1f8f6bf, sem-permissao-21-10); muita coisa por committar de outras sessões —
  não se trabalha nela, só em worktrees.

## CI do push e768931a (19:20Z)

Web 39660820386 success; olho-golden 39660820322 success; Android 39660820486 em curso (autoteste
dos 3 perfis no emulador); iOS 39660820406 em curso. `app_latest_version_code` = 681 (ainda o A1).
Web no ar: `app.boraguarda.com/main.dart.js` HTTP 200, 11,85 MB, `tvde_pos_ao_vivo` 8 vezes,
`tvde_fila_inteligente` 5, "Fila inteligente" 7, `tvde_encomendas_` 3.

## Interruptores

tvde_fila_inteligente_enabled = true (19:21Z) · tvde_pos_ao_vivo_enabled = true (12:32Z) ·
tvde_encomendas_enabled = false · provider_atividade_obrigatoria = true (09:02Z) ·
tvde_heartbeat_window_seconds = 600 (achado A2-2, por reportar).

## Feito e provado em fechar-pendencias-20-10 (não se refaz)

0, B, C (lembretes enviados), D (680, marcos desligados), A1 base (681, desligado), H, A2 enviado e
ligado. A3 está com a outra sessão.

## Outros fluxos vivos (e2e_log, últimas 72 h)

caca-clientes 20:05 ok · ep1-perfeito (filme) 19:41 · redes-grupos-auto 19:03 ok ·
em-dia-grupos-fb 11:57 · agentes-email plano 08:13 em-curso · radar-historico bloqueado 19, 20 e
21/10 às 01:46 (YouTube sem sessão no perfil pessoal) · limpeza-semanal-pagamento-19-10 20/10 13:00 ok.
