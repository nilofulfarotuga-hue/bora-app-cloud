---
id: memoria-claude-ai-digest-2026-10-22-cadastro-estafeta
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-22
zona: verde
confianca: alta
estado: atual
---

# Cadastro do estafeta: fotos chegam e aprovação mostra tudo — 22/10 (Claude Code, Opus)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-22-cadastro-estafeta`, origem `claude-code`, atualizada em 2026-10-22T17:54:17.117431+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 22 cadastro estafeta · memoria claude.ai · claude_ai_memoria

O cadastro do estafeta perdia as fotos desde sempre: a app mandava image/jpg (o armazém só aceitava image/jpeg) e engolia o erro; o servidor recusava ainda o documento do veículo. Corrigido: a Edge upload-driver-document v4 lê o tipo pelos bytes e aceita vehicle_doc; o cadastro tenta 3 vezes, não envia sem as fotos e diz ao estafeta o que falhou; selfie e foto do documento passaram a obrigatórias. O ecrã de aprovação do painel mostra tudo o que o cadastro pede (incluindo o comprovativo de atividade, com Aprovar ali mesmo), cada foto com zoom, o que falta a vermelho e o botão Pedir documentos em falta (aviso na app + notificação; SMS só manual pelo telemóvel do Danilo). O ecrã Conta em análise do estafeta mostra a lista do que falta com um botão por item para enviar ali mesmo (grava pelo driver_register_or_update, porque a tranca proibiu uma função nova que escreve em drivers). Contas encerradas saíram da lista de Pendentes. Provado no site no ar com 2 contas de teste (já encerradas pelo delete-account). Android publicado com versionCode 687; web no ar; iPhone a compilar no fim da sessão. SAM (estafeta real de 22/10): faltam selfie, foto e número do documento, foto do veículo e matrícula; o comprovativo que enviou é uma folha do Burger King, não das Finanças — não aprovar, usar Pedir documentos em falta. Reportado, não corrigido: cadastro de parceiro engole falhas de upload (register_partner_screen.dart 420/448/476/503); NIF repetido mostra erro técnico em inglês; rotas /#/admin abrem para qualquer sessão (dados protegidos pelo RLS); delete-account não limpa provider_atividade. Relatório: .claude/.ai/reports/cadastro-estafeta-2026-10-22.md.
