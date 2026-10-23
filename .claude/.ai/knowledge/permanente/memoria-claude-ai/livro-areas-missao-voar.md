---
id: memoria-claude-ai-livro-areas-missao-voar
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Missão grande pós-PC-novo (prompt-missao-voar.md, 30/08) — fases, decisões do Danilo e estado; ler antes de retomar qualquer fase

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-missao-voar`, origem `claude-ai`, atualizada em 2026-10-23T05:37:40.595626+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas missao voar · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/missao-voar.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: missao-voar
description: Missão grande pós-PC-novo (prompt-missao-voar.md, 30/08) — fases, decisões do Danilo e estado; ler antes de retomar qualquer fase
sources: [chat]
aliases: [missão voar, prompt missão, consolidação geral, nunca mais sem motor]
---

- [stated] PROMPT REGISTADO (regra do histórico): `prompt-missao-voar.md`, entregue 30/08, MOTOR FABLE, sessão nova no PC novo, correr depois das 19:00 (limite semanal renovou). 9 fases: 0 conferência final da migração Acer→novo; 1 nunca mais sem motor (Ollama local como reserva gratuita + cadeia pago>Gemini grátis>Ollama); 2 Buzz ligado ao relay próprio com todos os harnesses; 3 loop de correção à distância redondo (propor migrar executor para o PC novo); 4 WhatsApp da loja; 5 máquina de vídeos YouTube; 6 sites (Guarda FC auto-update + linha de 3 propostas/dia quando o Go voltar ~8/9); 7 teste geral do app estilo Uber/Glovo; 8 GitHub privado POR ÚLTIMO
- [stated] Decisões do Danilo (30/08): nunca mais ficar sem motor de IA — hoje o limite do Claude acabou a meio de um bug de cliente e ele "sofreu"; quer reserva gratuita sempre (Ollama local) e cadeia de motores grátis também para o Emerson (que também ficou sem limite)
- [stated] WhatsApp da loja: quer sistema a responder clientes/parceiros de forma humanizada (incluindo ouvir áudios), caminho GRATUITO (conta não é business, não quer pagar API), com aprovação dele no início; quase meia-noite havia clientes a querer falar com ele
- [stated] Máquina de vídeos: generalizar o sistema que leu 400+ transcrições de trading — "vê N vídeos sobre X e tira conclusões" como ferramenta reutilizável
- [stated] GitHub: tornar o repo bora-app-cloud PRIVADO por segurança, mas SÓ NO FIM, depois do app 100% — privado tem limites de CI, por isso a ordem importa
- [stated] Regras da era RAM-fraca: quer removidas/atualizadas — "agora eu quero voar"
- [stated] Estado 30/08 à noite: Fase 0 a correr no PC novo, travada na chave SSH novo→Acer; lição provada: Taildrop Acer→novo funciona (7 GB hoje), novo→Acer engole ficheiros — plano em curso: o Acer gera o par, instala a pública (UAC do Danilo) e manda a privada por Taildrop ao PC novo
- [stated] 30/08 ~20h30 ponte SSH resolvida pelo plano invertido: par ed25519 `id_ed25519_acer` gerado NO Acer (fingerprint SHA256:oHMSSFKu5WM781IkZNbGgbZ3ovXDOSVPrcmogP9eN4c), pública instalada nos DOIS authorized_keys do Acer (hermes-agent preexistente preservada), privada enviada por Taildrop ao PC novo para C:\Users\danil\.ssh\id_ed25519_acer; teste `ssh -i ... danil@100.71.105.7 hostname` deve dar LAPTOP-2Q09VQA1 sem senha; combinado: após confirmar login, o Acer apaga a cópia privada local (até lá há privada sem passphrase no scratchpad do Acer)
- [stated] 30/08 ~21h: a chave gerada no Acer veio com passphrase e foi recusada — resolveu-se ao contrário: a pública do PC NOVO (comentário danilo-lenovo-para-acer, SHA256:OxGYS+F4JSIDdJIkEal5JOE87JOwr+Sj1RPSkzqUC1U) viajou PC novo → VPS (scp pelo hostname público) → Acer e foi instalada nos dois authorized_keys; login sem senha novo→Acer FUNCIONOU (respondeu LAPTOP-2Q09VQA1) e a Fase 0 retomou sozinha, a trazer o que faltava (14 projetos Flutter incl. guarda-fc-site 2,4 GB e jai-site, hermes-bridge 71 ficheiros, 97 skills + 44 agentes do .claude, e o vault do repo bora_app\.obsidian-vault, com +90 ficheiros que o Desktop\Bora). Pendentes pequenos: releitura independente elevada do administrators_authorized_keys; limpar a chave morta danilo-to-acer-2026-08-30 e a privada esquecida no scratchpad do Acer
- [stated] REGRA DO CICLO (30/08, firme, ele repetiu): quando o Claude Code termina uma tarefa, tem de AVISAR sozinho — o Danilo nunca mais copia resultados para o chat. Desenho combinado (entra na Fase 3): gancho de fim de tarefa escreve o relatório na caixa hermes-reporte do Córtex + aviso no Telegram via Hermes (grátis); do lado Claude.ai, tarefa programada lê essa caixa e ou responde "tudo certo" ou cria a ordem seguinte via cortex_nova_ordem, ciclo até acabar. Limite honesto já dito a ele: nada faz aparecer mensagem sozinha neste chat — o aviso final é sempre no Telegram
- [stated] 30/08 fim da noite, decisão sobre o Ollama: NÃO fica só como reserva — quer o Ollama a trabalhar a sério onde aguentar (juiz de visão, triagem do carteiro, leitura de transcrições do YouTube, compreensão das mensagens do WhatsApp), e mandou levantar todos os pontos do sistema com motor pago/limitado para decidir caso a caso se o Ollama entra como principal, reserva ou fica de fora. Fora de questão: robôs do app em produção (ficam nos Gemini deles) e código pesado do Bora. Também disse ao executor para não lhe perguntar mais nada — só parar no que fisicamente só ele pode fazer (clique de administrador, senha), anotando e seguindo para a fase seguinte
- [stated] WhatsApp do Bora já está com sessão iniciada no PC novo — não é preciso ler QR nenhum para a Fase 4
- [stated] REGRA FIXA DO WHATSAPP (31/08): NUNCA responder em grupos — nem rascunho — mesmo que mencionem o Danilo ou façam pergunta direta; só conversas individuais de cliente. Correção ao ponto anterior: a sessão aberta no PC é a do app de Windows, que é um aparelho associado à parte; a automação corre pelo WhatsApp Web no Chrome, que precisou mesmo de QR (lido em 31/08)

