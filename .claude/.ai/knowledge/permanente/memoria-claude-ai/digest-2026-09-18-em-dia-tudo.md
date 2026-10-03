---
id: memoria-claude-ai-digest-2026-09-18-em-dia-tudo
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-18
zona: verde
confianca: alta
estado: atual
---

# Claude Code 18/09 — Em Dia: missão em-dia-tudo (blocos 0-9)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-18-em-dia-tudo`, origem `claude-code`, atualizada em 2026-09-18T22:46:51.623729+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 18 em dia tudo · memoria claude.ai · claude_ai_memoria

A app Em Dia está publicada em https://app.emdia.boraguarda.com e o painel de administração em https://admin.emdia.boraguarda.com.
Tudo o que se diz aqui está provado em provas/em-dia-tudo-2026-09-17/, com um ficheiro por bloco (b0 a b8) e as pastas pwa/, pwa-no-ar/, web/ e emulador/.
A app começa por perguntar «Trabalhas como?» e abre o caminho certo: recibos verdes, contrato, os dois ou empresa; cada resposta do onboarding fica guardada e a app retoma onde parou.
Quem não quer criar conta toca em «Vê como fica» no ecrã de entrada e vê a app inteira com a Maria, uma pessoa de exemplo (TVDE, 1.200 €/mês), com uma faixa laranja e nada gravado.
Todos os ecrãs têm o botão «O que é isto?», que abre a folha das palavras difíceis (41 palavras explicadas de forma simples, cada uma com botão Ouvir), e o botão Ouvir para ouvir o ecrã.
Na web a app abre sem rede: um service worker próprio guarda o que a página carregou e o primeiro ecrã vem em 723 ms com a rede cortada; o nome, as cores e o ícone já são da marca.
Os prazos do Estado que caem ao fim-de-semana ou feriado passam ao dia útil seguinte, com a fonte da lei à vista; os prazos de seguro, inspeção e carta não mudam.
Dá para importar o extrato do banco por ficheiro (CSV ou XLSX) no telemóvel, ver o que se repete por mês, como cancelar cada operador e pedir aviso na véspera.
O cofre do imposto aponta sozinho a fatia da Segurança Social e do IRS de cada entrada, com interruptor para desligar.
Os preços dos combustíveis vêm da DGEG (3.133 postos, 14.157 preços, atualização diária) e o «Perto de mim» pede a localização só quando se toca, só em primeiro plano, nunca guardada.
A prova de rendimento sai em PDF, numa página, com 12 meses fechados.
Quem tem contrato vê o recibo de vencimento linha a linha, o acerto ou reembolso do IRS do ano, o IRS Jovem, o desemprego e as horas extra.
Quem tem empresa vê o calendário (IVA, SAF-T, DMR, SS, Modelo 22, IES) e a pasta do contabilista vai por e-mail todo o dia 1 (provada a sério, com 5 ficheiros CSV).
O painel de administração tem as secções de sempre e ganhou «Assinaturas» e «Erros de leitura», com CSV que descarrega a sério e apagar conta a sério, com simulação antes e motivo obrigatório.
Fica por fazer: a fatura-recibo pela InvoiceXpress está programada e provada (a função responde 200, 403 e 401 conforme o caso) mas desligada até o Danilo criar a conta e pôr as chaves; o push final do Bloco 8 sai logo a seguir a este fecho e a build da Play (internal e alpha) vem do CI; a conta de teste na web precisa dele uma vez (python tool/provas/web_percorrer.py --entrar, porque a caixa «Confirme que é humano» não se clica); a leitura de dados sem rede fica para outra volta, porque a app abre mas o que precisa do servidor mostra o aviso de rede.
No fecho: 179 testes de unidade verdes, 39 Deno verdes, a suite golden inteira a passar e o percurso por 78 ecrãs e estados em 6 testes verdes na máquina e no emulador Android; as decisões da missão estão registadas como D47 a D73, cada uma com o quê, o porquê e como se desfaz.
