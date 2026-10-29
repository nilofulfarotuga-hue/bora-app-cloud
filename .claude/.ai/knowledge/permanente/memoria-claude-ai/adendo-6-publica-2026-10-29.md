---
id: memoria-claude-ai-adendo-6-publica-2026-10-29
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# ADENDO 6 (Claude.ai, 20:25) - robo nao recebeu a mensagem das 19:41 + fotos Letra para o Storage

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `adendo-6-publica-2026-10-29`, origem `claude.ai`, atualizada em 2026-10-29T21:14:14.148934+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: adendo 6 publica 2026 10 29 · memoria claude.ai · claude_ai_memoria

Duas coisas, sem parar o Bloco C nem o Bloco E. Reporta outros erros que encontrares em vez de os consertar calado.

1) ROBO BOOM - a mensagem do Danilo das 19:41 ("Posso reserva mesa por aqui?", de 351931992662 para o 937501673) NAO entrou no assistente: public.assistant_messages nao tem nada depois do id 332 (19:31:22). A ponte velha gravou-a em public.whatsapp_messages (id 1242) so as 19:55:06, junto com 2 mensagens antigas repetidas (ids 1240 e 1241, as das 19:03 e 19:30), o que parece reconexao da ponte com atraso; o assistente nao a recebeu ou descartou-a sem registo. Ver na VPS os registos da ponte (whatsapp-bora) e do assistente-negocio entre 19:31 e 19:56, achar a causa, consertar e provar com uma troca real (o Danilo testa do telemovel e a resposta tem de ser na hora). Nota: as 20:20 a Claude.ai atualizou por SQL o conhecimento do robo em assistant_tenants (id 74c7ff0a-654e-446c-8574-f2acd31a4c12; backup bkp_assistant_tenants_boom_bebidas_20261029): bebidas ja confirmadas no catalogo (o robo dizia "a lista de bebidas esta a ser atualizada") e reservas de mesa pela app com sinal de 3 EUR (dizia "sem reservas", mas restaurants.reservations_enabled=true). Se o assistente guarda conhecimento ou catalogo em memoria, recarregar. O catalogo da Boom tem agora 23 bebidas com precos novos, 6 bebidas novas e 14 vinhos (categoria Vinhos).

2) FOTOS LETRA - descarregar as 6 fotos de https://raw.githubusercontent.com/nilofulfarotuga-hue/bora-site/9f0a9653cdb21fa3c1ffd86260879f4f13469f28/fotos-boom/cervejas/boom-cerveja-letra-X-foto-dono.webp (X = a, b, c, d, e, f; 1000x1000 webp, fotos do dono enviadas a 29/10) e subir ao Storage: bucket restaurant-assets, caminho boom-burger-guarda/produtos/, mesmos nomes, content-type image/webp. Depois: UPDATE public.products set photo_url = URL publica do Storage, image_source = 'WhatsApp do dono 29/10/2026 (Fotos cervejas letras)' where id = 'boom-cerveja-letra-X' (hoje apontam para o jsDelivr, provisorio). Provar com SELECT em storage.objects e em products e registar em e2e_log (fluxo publica-2026-10-29, passo boom-fotos-letra-storage).

ATUALIZACAO 20:45 (ponto 2 alargado): alem das 6 cervejas, ha 11 fotos de vinhos (garrafa, fundo branco) no mesmo ramo, pasta fotos-boom/vinhos/, commit 786d58fd6681004a4143faf70fcb2d1390e61560: https://raw.githubusercontent.com/nilofulfarotuga-hue/bora-site/786d58fd6681004a4143faf70fcb2d1390e61560/fotos-boom/vinhos/ID-fabricante.webp para ID = boom-vinho-caiado-tinto, boom-vinho-caiado-branco, boom-vinho-caiado-rose, boom-vinho-adega-mayor-reserva-tinto, boom-vinho-adega-mayor-reserva-branco, boom-vinho-adega-mayor-baga-tinto, boom-vinho-adega-mayor-merlot-tinto, boom-vinho-adega-mayor-touriga-nacional-tinto, boom-vinho-adega-mayor-comendador-tinto, boom-vinho-adega-mayor-comendador-branco, boom-vinho-adega-mayor-verdelho-branco. Subir tambem para restaurant-assets/boom-burger-guarda/produtos/ID-fabricante.webp e trocar a photo_url desses 11 produtos para o Storage. Sem foto ainda: Trincadeira tinto, Arinto branco, Touriga Nacional rose.

ATUALIZACAO 20:40: a pagina boom-robo-conhecimento ainda diz "Bebidas e cervejas: a lista ainda nao esta confirmada" e "Sem reservas de mesa pelo Bora" (as duas frases estao erradas). O texto certo ja esta em assistant_tenants.knowledge (ficha.conhecimento): copiar as duas frases de la para a pagina, para a proxima sincronizacao nao repor o erro.

ATUALIZACAO 21:18 (ponto 3 novo): C5 aplicada por MCP (completa). C4 so a parte 1 (chave, colunas discount_*, funcoes de consulta). A parte 2 e 3 do ficheiro 20261029200800_c4_promocoes.sql (da seccao 4 "Historico de precos" ate ao fim) ficam para o Claude Code aplicar (supabase db push ou psql): o MCP da Claude.ai foi cancelado 2 vezes nesse trecho (gatilhos em products). Confirmar que a app apanha o erro se chamar store_active_promotions enquanto ela nao existir.
