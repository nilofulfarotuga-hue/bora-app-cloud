---
name: bloqueio-classificador-auto-mode
description: >
  Usa esta skill sempre que uma ação for bloqueada com 'Permission for this action was denied by the Claude Code auto mode classifier' (visto 6x em 2 sessões/2 dias, 2026-09). Regra: NÃO repetir a mesma ação bloqueada à espera que passe — o classificador não muda de ideia por insistência. Segue a própria mensagem do erro: se há outras tarefas que não dependem dessa ação, continua com elas; regista a ação bloqueada para o Danilo decidir; nunca contorna o bloqueio.
metadata:
  versao: 1.0
  criada: 2026-09-21
  criada_por: vigia-habilidades (corrida 2026-09-21_2330)
  tema: "Permissão negada pelo classificador do modo automático (auto mode classifier)"
  origem_literal:
    - "corpus §2: 6x em 2 sessoes/2 dias: Permission for this action was denied by the Claude Code auto mode classifier. Reason: Blocked by classifier. If you have other tasks that don't depend on this"
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# bloqueio-classificador-auto-mode

> Criada pelo vigia a 21/09/2026 porque o Danilo disse: corpus §2: 6x em 2 sessoes/2 dias: Permission for this action was denied by the Claude Code auto mode classifier. Reason: Blocked by classifier. If you have other tasks that don't depend on this

# Bloqueio do classificador do modo automático

Quando uma ferramenta devolve "Permission for this action was denied by the Claude Code auto mode classifier", o bloqueio vem do harness, não é um erro teu — insistir com o mesmo comando não passa.

## O que fazer
1. Lê a razão dada pela mensagem (vem sempre um "Reason: ...").
2. Se a mensagem disser "If you have other tasks that don't depend on this, continue with those" — faz exactamente isso: separa o que está bloqueado do resto e avança no resto primeiro.
3. NÃO tentes contornar com --no-verify, elevar permissões, ou reformular o comando para escapar ao classificador — isso é a rede de segurança do Danilo, não um bug.
4. Regista no relatório final: "bloqueado pelo classificador: <ação>, motivo: <razão>" — para o Danilo decidir se muda o modo de permissão ou o motor.
5. Se a mesma ação for bloqueada em 2+ sessões distintas na mesma tarefa recorrente, propõe mudar essa tarefa de motor (skill `distribuir-trabalho`) em vez de insistir sempre no Claude Code.

## Porquê
Visto 6x em 2 sessões/2 dias (2026-09) sem nenhuma tentativa de contorno registada como correcta — o padrão certo é reportar e desviar, não insistir.
