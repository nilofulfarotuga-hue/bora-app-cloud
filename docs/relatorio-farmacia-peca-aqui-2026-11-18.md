# Relatório — missão farmácia "Peça aqui" (18/11/2026)

Ordem: prompt do Claude.ai de 18/11 às 12:15, com a autorização do Danilo de 12:05, mais os adendos 1 (12:26) e 2 (12:31) do Claude.ai. Executado pelo Claude Code no PC, motor Opus 5.5. Fluxo no e2e_log: farmacia-peca-aqui-18-11.

## Fiz isto

Quando alguém procura um produto dentro da Farmácia da Sé e não encontra, a app passa a mostrar primeiro um botão verde grande "Pedir à Farmácia da Sé". O botão abre o pedido especial com o nome do produto já escrito. Por baixo aparece a frase "A farmácia confirma se tem e o preço. Só pagas depois de confirmar." O botão do Amigo continua, mas fica em segundo lugar e leva uma mensagem nova: "Não encontrei X na Farmácia da Sé. Ajuda-me a pedir à farmácia ou diz-me onde mais há." Se a farmácia estiver fechada, ou se a pessoa não puder ver os botões da farmácia, fica tudo como estava. As lojas normais não mudam.

O Amigo também aprendeu a regra "primeiro o parceiro". Com medicamentos, se a Farmácia da Sé tiver o produto no catálogo, propõe lá. Se não tiver, mostra primeiro o botão "Pedir à Farmácia da Sé" e explica numa ou duas frases como funciona; só depois, por baixo, diz que a Wells tem e por quanto. Mesmo que o modelo se esqueça do botão, o servidor põe-no à frente. Quem ainda tem a app antiga recebe "Abrir a Farmácia da Sé", que leva à loja, onde já existe o "Peça aqui". Palavras com dois sentidos, como "gotas de chocolate" ou "receita de bacalhau", não chamam a farmácia. O manual do Amigo não tinha nada sobre farmácias: acrescentei um trecho escrito para o cliente e já está no servidor.

Do lado da farmácia (os dois adendos do caso da Rita), os pedidos aceites já não desaparecem para o fundo. Ficam numa secção própria, "À espera do cliente confirmar", logo a seguir a "À espera de resposta", com o valor e há quanto tempo estão à espera. O cartão "Receitas e pedidos especiais" ficou preso no topo do separador Pedidos e diz também "1 à espera do cliente confirmar", sem tocar o som. Os aceites com mais de 6 horas passam para "Respondidos", para não ficarem lá para sempre. Deixei ainda pronto o lembrete ao cliente: se a farmácia aceitar e o cliente não confirmar em 10 minutos, recebe um aviso, uma vez só. Esta parte só começa a funcionar depois de ser aplicada a migração.

No painel admin há uma aba nova nas Farmácias, "Pedidos especiais (pedido livre)", e uma entrada no menu, "Pedidos especiais das farmácias". Mostra o que o cliente pediu, o estado, a resposta da farmácia e quanto tempo ela demorou a responder, e dá para exportar. A lista dos produtos procurados que não se encontram já existia, no ecrã "Pesquisas sem resultado", e já guarda as pesquisas da Farmácia da Sé.

## Provas

- Os testes do Amigo correm no PC: 66 verdes, dos quais 10 são novos (o caso Vomidrine, ben-u-ron, açaí e gotas de chocolate). A verificação de tipos do código do Amigo também passou.
- Os testes novos da app estão em test/farmacia_peca_aqui_test.dart e correm no CI do pedido de revisão #39 (resultado mais abaixo).
- O Juiz (um revisor que começou sem contexto) aprovou o trabalho. Corrigi os quatro pontos que ele levantou.
- O trabalho está em dois commits, bc45170e e 636dea4a, no ramo ai/2026-11-18-farmacia-peca-aqui, com o pedido de revisão aberto: https://github.com/nilofulfarotuga-hue/bora-app-cloud/pull/39

## Falta isto (e porquê)

- **Publicar o Amigo novo.** No PC não há a ferramenta do Supabase, e a trava não deixa o executor publicar funções no servidor. Fica para o Claude.ai, com a lista dos ficheiros no e2e_log. As 3 conversas de prova numa conta de teste ("quero vomidrine", "tenho dor de cabeça, quero ben-u-ron", "quero açaí") só se fazem depois disso.
- **Aplicar a migração** supabase/migrations/20261118120000_farmacia_peca_aqui.sql (lembrete ao cliente e campos novos na lista do painel). A trava recusa-me mexer na estrutura da base de dados em produção, por isso fica para o Claude.ai. Até lá, a aba do painel funciona, mas sem o texto do pedido.
- **Juntar ao ramo de produção e publicar nas 3 plataformas.** A trava não me deixa enviar para o ramo de produção; fica para o Claude.ai depois do CI verde.
- **Lupa da página inicial (ponto 1.4).** Não mexi. Outra missão ainda por juntar (ramo ai/2026-11-17-lupa-sugestoes) muda esse ecrã e também a parte da pesquisa nas lojas. Quem juntar em segundo lugar vai ter um conflito pequeno no store_products_screen.

## Erros que encontrei pelo caminho

- O registo das pesquisas sem resultado grava também os pedaços de palavra enquanto a pessoa escreve (por exemplo "alp" e "alpra", ou "eng" e "engo"). Isso suja a lista do painel. Não corrigi.
- Há dois pedidos aceites de 13/11 que nunca foram confirmados nem expiraram. O estado "aceite" não tem prazo. Não mexi nos dados.
- A trava recusa "git push -u"; o envio simples do ramo ai/ passa. Já estava anotado em docs/TRANCAS.md.
- Não existe nenhum agente nem skill chamado "Refinador" no PC. A revisão ficou só com o Juiz.

## Próximo passo (Claude.ai)

1. Ver o CI do pedido de revisão #39.
2. Aplicar a migração.
3. Publicar a função client-assistant.
4. Fazer as 3 conversas de prova.
5. Juntar ao ramo de produção e confirmar a versão nova na web, no Android e no iPhone.
