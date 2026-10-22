---
id: memoria-claude-ai-seguranca-auditoria-2026-10-21
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-21
zona: verde
confianca: alta
estado: atual
---

# Auditoria de seguranca do app (21/10, agente N4)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `seguranca-auditoria-2026-10-21`, origem `claude-code`, atualizada em 2026-10-21T20:18:00.770536+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: seguranca auditoria 2026 10 21 · memoria claude.ai · claude_ai_memoria

Auditoria de seguranca do nosso app, feita como um atacante faria (so o Bora: app, app.boraguarda.com, emdia.boraguarda.com; nunca sites de terceiros). Nao se instalou nada de fora; usou-se o codigo nosso e o MCP do Supabase. Provas sempre com ataque real ou defeito plantado, em rollback.

CORRIGIDO E PROVADO:
1) Tres Edge de aviso (notify-admin-message, notify-cleaner, notify-washer) deixavam QUALQUER conta com sessao mandar um push com titulo e texto a escolha a qualquer pessoa (estafeta, cliente, parceiro). Portao novo exigirServidorOuAdmin (so o servidor ou um admin). Prova: chave publica da app -> 403; servidor -> 200.
2) O album de fotos de perfil (bucket avatars) deixava qualquer um, ate sem conta, trocar ou apagar a foto de outra pessoa. Agora so a propria pessoa mexe na sua pasta. Prova: antes upload/delete anonimo davam 200 e dava para alterar 10 fotos reais; depois 403.
3) Doze funcoes internas (do Cortex, do Maestro, do robo de suporte, do resumo de pedido por telefone) estavam abertas a qualquer conta pela API e escreviam dados sem ver quem chama. Fechadas: so o servidor. Prova: antes a conta normal corria; depois "permission denied".
4) Tres avisos ao admin (corrida em modo convidado, queixa TVDE, conformidade TVDE diaria) falhavam calados ou rebentavam porque mandavam um nivel que a tabela recusa. Corrigido num sitio so.

SO REPORTADO (proposta pronta, nao aplicada, em docs/seguranca/propostas/):
- platform_settings: qualquer conta com sessao le a tabela toda, incluindo o markup oculto, comissoes e config Stripe. Mexe em dinheiro -> espera o "vai" do Danilo.
- register-partner: aceita o JWT sem confirmar a assinatura (da para abrir candidatura de parceiro em nome de outra conta). A prova ao vivo foi recusada pelo classificador; proposta pronta.
- A Trava do banco funciona nesta pasta, mas aponta por uma juncao do Desktop; se a juncao sumir, deixa de correr calada. Proposta de caminho robusto. Nao se mexeu no .claude/settings.json (zona protegida).

SEM PROBLEMA: nenhuma chave de servidor/Stripe/service_role exposta nos bundles web nem no repo (so as chaves publicas, que e normal).

NAO SE TOCOU (por ordem): TVDE do agente N2, Stripe (refund/webhook/payment-intent), o filme, e o settings.json. Sem git push; ramo seguranca-21-10.
