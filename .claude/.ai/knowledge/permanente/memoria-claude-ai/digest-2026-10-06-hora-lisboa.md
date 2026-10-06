---
id: memoria-claude-ai-digest-2026-10-06-hora-lisboa
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-06
zona: verde
confianca: alta
estado: atual
---

# Claude Code 06/10 — loja aberta/fechada pela hora de Lisboa

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-06-hora-lisboa`, origem `claude-code`, atualizada em 2026-10-06T16:40:59.072312+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 06 hora lisboa · memoria claude.ai · claude_ai_memoria

Missao hora-lisboa-2026-10-06 (PC do Danilo, Opus 5.5), decisao da Claude.ai com a autoridade do Danilo. O que funciona agora: a app decide aberta/fechada, a etiqueta da loja e o aviso do carrinho pela hora de Lisboa (Europe/Lisbon, com hora de verao), a mesma do servidor (is_partner_open, travao STORE_CLOSED), seja qual for o fuso do telemovel. Tambem pela hora de Lisboa: o dia minimo e o envio da data das festas, o calendario e o "a hora ja passou" das reservas de mesa, os dias fechados do parceiro e o "forcar ate dia X" do painel admin. Pecas em lib/utils/hora_lisboa.dart: paredeLisboa() para LER dia e hora (marcado UTC, nao cai nos buracos da mudanca de hora de outros paises) e instanteDeLisboa() para ENVIAR uma hora escolhida no relogio da loja (nunca .toUtc()). Regra escrita no PADRAO_BORA 1.27. Commits af8838f3 e a1aa5594 (+ docs 55a16ae8). Provado: teste novo falhou 7 vezes contra o codigo antigo e passa 18/18; 46 testes da loja verdes com o relogio do processo em Lisboa, UTC, UTC-2 e UTC+10 (TZ no Windows); Android #502 com autoteste no emulador UTC verde, versionCode 652 no Play; web #196 (main.dart.js 11113107 bytes) e prova ao vivo com o navegador em Toquio: lojas "Aberto" iguais ao servidor; iPhone #168 verde, IPA 1.0.12 build 168 no TestFlight (a 1.0.11 ainda espera a Apple). Falta (ordem .claude/.ai/inbox/CONTINUAR-hora-lisboa-2026-10-06.md): hora da mesa enviada dentro do pagamento do sinal (nao mexido, zona de dinheiro na duvida), a app nao le os dias fechados special_dates que o servidor le, horas das marcacoes mostradas no fuso do telemovel. Relatorio: .claude/.ai/reports/2026-10-06-hora-lisboa.md.
