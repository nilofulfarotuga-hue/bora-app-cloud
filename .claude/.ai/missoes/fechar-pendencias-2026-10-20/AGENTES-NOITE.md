# AGENTES DA NOITE — geral-noite-21-10 (quem está em quê)

Orquestrador: sessão "Fechar pendências noite 21/10" (local_6914492a). Um bloco = um agente = um
worktree = um ramo. Antes de arrancar, linha `N?-inicio` no e2e_log `fechar-pendencias-20-10`.
Envios para o servidor um de cada vez, com rebase antes. Nunca dois `flutter build/analyze/test`
ao mesmo tempo (conta também o agente do A3 da outra sessão).

| Bloco | Dono | Worktree / ramo | Estado |
|---|---|---|---|
| N0 estado | orquestrador | — | feito 20:38 (ESTADO-N0.md) |
| N1 A2 (provas das 3 + vigia 2 h da fila) | orquestrador | — (o código já está em origin e768931a) | em curso |
| N2 A1 resto (notify-tvde-driver + palavras) | agente-encomendas-n2 | C:\BoraLocal\wt-encomendas-n2-21-10 / encomendas-n2-21-10 | a arrancar |
| N3 A3 restos | OUTRA sessão "Fechar pendências 2026-10-20" (agente-reservas) | C:\BoraLocal\wt-reservas-21-10 / reservas-21-10 | dela, não se entra |
| N4 E segurança | agente-seguranca-n4 | C:\BoraLocal\wt-seguranca-21-10 / seguranca-21-10 | a arrancar |
| N5 e-mail dos agentes | agente-email-n5 (retoma do ponto onde a sessão bora-app-b3 parou) | C:\BoraLocal\wt-agentes-email-21-10 / agentes-email-21-10 | depois do N7 (o Chrome é um só) |
| N6 skill navegadores | orquestrador | C:\BoraLocal\wt-noite-21-10 / noite-21-10 | a fazer |
| N7 radar YouTube | orquestrador | — | a fazer |
| N8 permissões | orquestrador | — | registo |
| N9 chave (G) | orquestrador, 03:00–06:00 | C:\BoraLocal\wt-chave-nova-16-10 | agendado |
| N10 registo | orquestrador | C:\BoraLocal\wt-noite-21-10 | parciais de 2 em 2 h |
| Vigia | orquestrador (tarefa da sessão de 20 em 20 min) | — | a criar |

Sessões paradas à espera de clique do Danilo (não recebem mensagens, estão noutro modo):
"bora-app-b3" (agentes-email, migração `agentes_email_ajustes` pendente) e "bora-app-fa"
(encomendas de 19/10, comando de leitura pendente). Se forem retomadas, podem repetir passos: ver
e2e_log antes.
