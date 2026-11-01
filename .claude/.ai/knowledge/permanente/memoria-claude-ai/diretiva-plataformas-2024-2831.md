---
id: memoria-claude-ai-diretiva-plataformas-2024-2831
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-01
zona: verde
confianca: alta
estado: atual
---

# Diretiva (UE) 2024/2831 trabalho em plataformas — o que obriga o Bora, estado em Portugal, o que está feito e checklist para 02/12/2026

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `diretiva-plataformas-2024-2831`, origem `claude-code`, atualizada em 2026-11-01T20:36:19.713912+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: diretiva plataformas 2024 2831 · memoria claude.ai · claude_ai_memoria

# Diretiva (UE) 2024/2831 — o que obriga o Bora (resumo 01/11/2026, missão diretiva-plataformas-2026-11-01)

## A lei em 8 linhas
1. Aplica-se a QUALQUER plataforma que organize trabalho por meios eletrónicos a pedido e use sistemas automáticos de monitorização ou decisão (art. 1.º-2.º). Não há isenção por dimensão: o Bora conta (despacho automático, GPS, heartbeat, notas).
2. O capítulo III (gestão algorítmica, arts. 7.º-11.º) aplica-se TAMBÉM a quem trabalha sem contrato de trabalho (independentes) — considerando 54. Os arts. 12.º-14.º (segurança/saúde, informação e consulta) só a empregados.
3. Art. 7.º: proibido tratar estado emocional, conversas privadas, dados fora do trabalho, inferir origem/saúde/religião/sindicato, biometria um-para-muitos. Art. 8.º: avaliação de impacto (RGPD art. 35.º) ouvindo os trabalhadores.
4. Art. 9.º: informação POR ESCRITO, clara e simples, sobre os sistemas automáticos (que dados, que decisões, parâmetros principais, motivos para restringir/suspender/encerrar conta), até ao 1.º dia de trabalho, antes de mudanças e a pedido; também às autoridades a pedido.
5. Art. 10.º: supervisão humana; avaliar o impacto das decisões automáticas pelo menos de 2 em 2 anos; pessoal competente que possa anular decisões.
6. Art. 11.º: direito a explicação + pessoa de contacto; declaração escrita de motivos até ao dia em que a decisão produz efeitos (restrição/suspensão/encerramento, recusa de pagamento, mudança contratual); pedido de revisão respondido por escrito sem demora e no máximo em 2 semanas; retificar ou compensar; restrição/suspensão/encerramento de conta SEMPRE decididos por um ser humano (n.º 5).
7. Arts. 16.º-17.º: declarar o trabalho em plataformas às autoridades do Estado onde é feito; disponibilizar n.º de pessoas, estatuto contratual e termos gerais (atualizado de 6 em 6 meses, a pedido).
8. Art. 29.º: transposição até 2 de dezembro de 2026. Art. 5.º: presunção legal de emprego ilidível, ónus na plataforma.

## Portugal (01/11/2026)
- Presunção JÁ EXISTE: art. 12.º-A do Código do Trabalho (Lei 13/2023, Agenda do Trabalho Digno, desde 01/05/2023): 2 de 6 indícios (fixa retribuição, controla por meios eletrónicos, restringe autonomia de horário/aceitação, restringe subcontratação, imagem da marca, etc.); n.º 12 estende ao TVDE (Lei 45/2018). ACT fiscaliza. Arts. 24.º/3 e 106.º/3 s) CT: igualdade e informação sobre algoritmos.
- Transposição NÃO publicada: a Proposta de Lei 77/XVII (Trabalho XXI, 18/05/2026, transpunha a Diretiva no art. 1.º a) e no art. 127.º/4 "decisões não adotadas sem intervenção humana") foi REJEITADA na generalidade a 19/06/2026. Jornal de Negócios 26/10/2026: Governo vai mexer na lei laboral "no próximo ano" (2027) por causa das diretivas das plataformas. Até lá vale a Diretiva como referência e, após 02/12/2026 sem transposição, efeito direto vertical (contra o Estado) e interpretação conforme.
- TVDE do Bora fecha a 02/11/2026: a parte TVDE (Lei 45/2018, IMT) deixa de pesar; guardar registos.

## O que ficou feito (01/11/2026)
- docs/legal/gestao-algoritmica-prestadores.md (= página legal-gestao-algoritmica-prestadores): "Como o Bora decide" para o prestador ler na app.
- docs/legal/politica-suspensao-revisao-humana.md (= página legal-politica-suspensao-revisao-humana): nenhuma suspensão automática, motivo+quem+data, revisão por pessoa em 7 dias.
- Migração PREPARADA (não aplicada): supabase/migrations/20261101230000_prestador_suspensoes_revisao_humana_2026_11_01.sql — tabela prestador_suspensoes, trigger fn_suspensao_so_com_humano nas 6 tabelas de prestador, RPCs admin_suspender_prestador / admin_reativar_prestador / admin_responder_revisao / admin_registar_pedido_revisao / admin_decidir_proposta / prestador_minha_suspensao / prestador_pedir_revisao, vista admin_fila_revisoes, cron prestador_suspensoes_manutencao, correção de cancel_cleaning_booking (deixa de suspender sozinha ao 3.º cancelamento tardio: cria proposta para pessoa decidir). Testada em Postgres local com stubs: 10 cenários ok.
- Achado: a ÚNICA automação que suspendia sem humano era cancel_cleaning_booking (limpeza). Tudo o resto (doc caducado, GPS, heartbeat, online só aprovado, blocked_for_debt com tecto 0, flagged_low_rating, robot hide_store) é restrição reversível ou só aviso para admin.

## Checklist para 02/12/2026 (por ordem)
1. [aplicar] Migração 20261101230000 (Danilo diz "aplica"). Depois: painel "desligar loja" e admin_review_cleaner suspend passam a exigir motivo ≥10 letras.
2. [app] Ecrã "A minha conta foi suspensa" (estafeta, limpeza, lavagem, casa, parceiro): motivo, data, até quando, "Equipa Bora", botão Pedir revisão → prestador_pedir_revisao; estado da revisão e resposta. Hoje só diz "Contacta o suporte".
3. [app] Secção "Como o Bora decide" em Sobre / Informação legal (texto da página legal-gestao-algoritmica-prestadores) e ligação na candidatura (art. 9.º/5: antes do recrutamento).
4. [painel] Ecrã Revisões (vista admin_fila_revisoes): fila com prazo e atraso, botões Responder (mantida/reduzida/revertida) e Decidir proposta; botão Suspender com motivo em todas as fichas de prestador (admin_suspender_prestador); registar pedido vindo do WhatsApp.
5. [termos] Nova versão dos Termos do Estafeta/Parceiro/Limpeza com cláusula "sistemas automáticos e revisão humana" apontando para o documento; versão 2026-12-01 em legal_terms_versions (estafeta e parceiro já têm portão; limpeza/lavagem/casa ainda não têm termos versionados).
6. [RGPD] Avaliação de impacto (AIPD) dos sistemas automáticos (despacho, GPS, notas, verificação de documentos Gemini) com opinião dos prestadores recolhida (art. 8.º); guardar em docs/legal/aipd-sistemas-automaticos.md.
7. [registo] Relatório anual de supervisão humana (art. 10.º): contagens de prestador_suspensoes por motivo, revisões, tempo de resposta; primeiro até 02/12/2027, depois de 2 em 2 anos.
8. [autoridades] Quando a lei portuguesa de transposição sair (2027): declaração do trabalho em plataformas (art. 16.º) e ficheiro pronto com n.º de prestadores, estatuto e termos gerais (art. 17.º) — já se pode preparar com uma vista.
9. [presunção] Manter as provas de autonomia (sem exclusividade, aceita/recusa livre sem castigo, sem horário imposto, pode usar outras plataformas) e rever o art. 12.º-A a cada mudança de regra.
10. [comunicação] Mandar a cada prestador ativo a mensagem com o documento (WhatsApp da Bora) até 01/12/2026 e registar comunicado_em.

