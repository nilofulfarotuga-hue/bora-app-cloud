---
id: memoria-claude-ai-em-dia-play-classificacao-conteudo
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-22
zona: verde
confianca: alta
estado: atual
---

# Em Dia / Play: respostas da classificacao IARC e o que muda quando as assinaturas abrirem

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `em-dia-play-classificacao-conteudo`, origem `claude-ai`, atualizada em 2026-09-22T11:29:21.7621+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: em dia play classificacao conteudo · memoria claude.ai · claude_ai_memoria

Estado a 22/09/2026: "Conteudo da app" na Play Console esta a 100% ("Ja verificou tudo"). Nada foi enviado para revisao, porque a Play esta parada por decisao do Danilo (bloqueio dos 12 testadores x 14 dias).

RESPOSTAS DADAS NO QUESTIONARIO IARC
- Categoria: Todos os Outros Tipos de Aplicacoes.
- Conteudo Online: SIM. A pergunta lista explicitamente "conteudo gerado por IA" e a Em Dia tem assistente IA.
- Partilha de conteudo de utilizador: NAO. A pergunta e sobre interaccao entre utilizadores; a Em Dia nao tem nenhuma.
- Partilha de localizacao: NAO. A pergunta e sobre partilhar a localizacao COM OUTROS UTILIZADORES, nao sobre usar localizacao.
- Compras digitais: NAO. Ver aviso abaixo.
- Declaracao de ID de publicidade: NAO usa. Verificado no pubspec.yaml: so firebase_core e firebase_messaging; sem firebase_analytics, sem AdMob, sem qualquer SDK de anuncios.

NOTA: em tres pontos isto diverge de docs/PLAY-FICHA-RESPOSTAS.md de proposito, porque a pergunta real na consola nao era a que o documento assumia. O documento nao esta errado, esta a responder a outra pergunta.

AVISO OBRIGATORIO PARA QUANDO AS ASSINATURAS ABRIREM
A resposta "compras digitais = NAO" so e verdade enquanto regras_legais.planos_a_venda = 'nao' e a build nao vender nada. No dia em que as assinaturas forem ligadas:
1. Voltar ao questionario IARC e mudar "compras digitais" para SIM.
2. Guardar e reenviar a classificacao para revisao.
3. Rever tambem a seccao Seguranca dos dados, que passa a ter dados de pagamento.
Deixar isto por fazer e uma violacao de politica que pode derrubar a app da loja.
