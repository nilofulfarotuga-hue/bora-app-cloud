---
id: memoria-claude-ai-legal-politica-suspensao-revisao-humana
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-01
zona: verde
confianca: alta
estado: atual
---

# Política de suspensão e revisão humana (nenhuma suspensão automática; motivo+quem+data; revisão por pessoa em 7 dias) — v2026-11-01

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `legal-politica-suspensao-revisao-humana`, origem `claude-code`, atualizada em 2026-11-01T20:35:33.886+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: legal politica suspensao revisao humana · memoria claude.ai · claude_ai_memoria

# Política de suspensão e revisão humana

Versão 2026-11-01 · Aplica-se a todos os prestadores da Bora: estafetas, motoristas (até ao fecho do TVDE a 02/11/2026), profissionais de limpeza, lavadores, profissionais de casa e lojas parceiras.
Base legal: Diretiva (UE) 2024/2831, artigo 11.º (revisão humana) e artigo 10.º (supervisão humana); Regulamento (UE) 2019/1150 para as lojas.

## 1. Regra número um: nenhuma suspensão é automática

A app nunca suspende, bloqueia por tempo indeterminado nem encerra uma conta sozinha. Só uma pessoa da equipa Bora pode fazer isso. O servidor recusa qualquer suspensão que não venha com motivo escrito e com o nome de quem decidiu.

Não é suspensão (e por isso pode ser automático): ficar fora das ofertas por GPS parado ou sem sinal, não poder carregar em Online com um documento caducado, ou ainda não estar aprovado. Estas situações resolvem-se pelo próprio prestador (ligar o GPS, abrir a app, carregar o documento novo) e também podem ser revistas por uma pessoa se o prestador pedir.

## 2. O que toda a suspensão tem de ter

Antes de a suspensão começar a valer, ficam registados no sistema:

- Quem é suspenso (conta e tipo de conta).
- O tipo: suspensão temporária (com data de fim), suspensão sem data, encerramento, ou restrição (por exemplo, só não recebe ofertas de um tipo de serviço).
- O motivo, por escrito e em português simples, com os factos (que pedido, que dia, o que aconteceu).
- A data e hora.
- Quem decidiu (uma pessoa da equipa Bora, identificada pela conta de administrador). Nunca "sistema".
- Até quando, se for temporária.

O prestador recebe o motivo no mesmo dia, na app e por mensagem, até ao momento em que a decisão produz efeitos.

## 3. Avisos automáticos não decidem

A app pode avisar a equipa ("esta profissional cancelou tarde 3 vezes em 30 dias", "nota média baixa", "pedido com problema"). Esse aviso entra numa fila para uma pessoa ver. A pessoa olha para o caso, fala com o prestador se for preciso e só depois decide. Se decidir suspender, aplica-se o ponto 2.

## 4. Como pedir revisão

- Na app, no ecrã "A minha conta foi suspensa", o prestador vê o motivo, a data, quem decidiu, até quando, e tem o botão "Pedir revisão", onde escreve a sua versão.
- Também pode pedir pelo WhatsApp da Bora (+351 937 501 673) ou por email (boraappbora@gmail.com). A equipa regista o pedido no sistema na hora.
- Pode pedir revisão quantas vezes tiver factos novos.

## 5. Como a revisão é feita

- É feita por uma pessoa: o responsável da Bora (administrador). Nunca pela app nem por um robô.
- A pessoa lê o pedido, vê os registos (pedidos, mensagens, GPS, notas) e, se precisar, fala com o prestador e com o cliente.
- Resposta por escrito, com os motivos, no prazo máximo de 7 dias a contar do pedido. A lei dá 14 dias; a Bora compromete-se a 7. O painel mostra o prazo e avisa a equipa quando faltam 2 dias.
- A resposta diz uma de três coisas: a suspensão fica, a suspensão é reduzida, ou a conta é reativada.
- Se a Bora errou: reativa a conta no mesmo dia, paga o que ficou por pagar e, se houve prejuízo claro (por exemplo, dias sem poder trabalhar por erro nosso), compensa.

## 6. Reativação

- Suspensão temporária: termina sozinha na data marcada; a conta volta a poder ficar online.
- Suspensão sem data ou encerramento: só uma pessoa pode reativar, com nota escrita do porquê.
- Toda a reativação fica registada (data, quem reativou, nota).

## 7. Registos e supervisão

- Todas as suspensões, pedidos de revisão e respostas ficam na tabela `prestador_suspensoes` e no registo de ações de administrador (`admin_audit_log`).
- Uma vez por ano, no mínimo, e sempre antes de mudar regras automáticas, uma pessoa da Bora revê os números: quantas suspensões, por que motivos, quantas revisões pedidas, quantas revertidas, tempo médio de resposta. Esse resumo serve para a avaliação de impacto que a Diretiva pede (artigo 10.º, pelo menos de 2 em 2 anos) e para responder à ACT ou à CNPD se pedirem.

## 8. Lojas parceiras

Para as lojas aplica-se o mesmo, mais o que já está nos Termos do Parceiro: a Bora só termina a parceria com 30 dias de aviso e as razões por escrito, salvo falta grave. Desligar uma loja da app (`is_active_admin`) conta como suspensão e segue esta política.

Versão em vigor desde 1 de novembro de 2026.

