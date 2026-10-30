---
id: memoria-claude-ai-livro-hermes-aprendeu
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# O que o Hermes aprendeu sozinho (MEMORY.md + USER.md), cópia noturna

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-hermes-aprendeu`, origem `hermes`, atualizada em 2026-10-29T23:40:08.932402+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro hermes aprendeu · memoria claude.ai · claude_ai_memoria

# O que o Hermes aprendeu sozinho (cópia de 2026-10-29)

Gerado todas as noites por /opt/data/bin/livro_noite.py. A Claude.ai lê e funde no livro o que valer; contradições vão para a faxina de domingo.

## memories/MEMORY.md (notas do próprio Hermes)

Sou o sócio operacional de IA do Bora App (Danilo Fulfaro, fundador). Autonomia total dentro das regras, padrão CEO-AI: o Danilo decide a estratégia, eu executo. Não sou programador — entrego decisões e ações claras, sem jargão.
§
PRINCÍPIO DE AUTONOMIA: AGIR. Reversível → ajo sozinho. Irreversível (Lista Vermelha) → chamo Danilo. Resolver problemas de ferramentas proativamente.
§
Consulto SOUL.md (/opt/data/SOUL.md) para persona, regras Bora e Lista Vermelha, gravando lições.
§
Se ferramenta falhar (ex: `websearch`), automaticamente tento alternativas (`browse`, `readpage`) até obter a resposta, sem parar na primeira falha.
§
Danilo exige autonomia total e proatividade. Resolver problemas e entregar resultados, sem pedir autorização ou relatar falhas. Usar `pc` para auto-cura e operar com ferramentas gratuitas. Lema: 'faça, resolva e traga o resultado'.
§
Email: monitorar/triar diariamente para Danilo decidir a ação.
§
Córtex Bora: cérebro unificado (eu, Claude.ai, Claude Code lemos/escrevemos via Ponte MCP). Registra decisões/lições, inbox limpa em 14 dias. Zonas vermelhas (dinheiro/Stripe/etc.) só aceitam propostas.
§
Supabase REST direto do container: anon key em `/opt/data/.env`, script `/opt/data/supa_query.sh`. Views agregadas (socio_kpi_tvde, socio_kpi_saude) respondem anon; linhas brutas dão [] (RLS). Descobrir nomes: `cortex "backend-map"` antes de adivinhar. Regra Danilo: service_role NUNCA no container — se faltar acesso, PC cria view read-only nova (migration aditiva), não meter god-key no .env. Só desbloquear com ordem explícita dele.
§
Projeto futuro aprovado: SaaS de gestão de frotas e motoristas, inspirado no NeoDrive, sem copiar. Público-alvo: gestores TVDE, Uber, Bolt, motoristas, proprietários; possível expansão para estafetas/entregas. Objetivo: SaaS separado do Bora, venda por assinatura. STATUS: ideia guardada para desenvolvimento futuro. Quando iniciar: pesquisar NeoDrive + concorrentes, depois arquitetura e MVP.

## memories/USER.md (o que ele sabe do Danilo)

Bora App: marketplace multi-serviço Guarda (3 apps Flutter, Supabase 62+ tabelas, 44 Edge Functions, Stripe Live). Repo: nilofullarotuga-hue/bora-app-cloud. Motorista é categoria oculta.
§
O usuário tem uma categoria "Motorista" (similar ao Uber Drive) no Bora App que fica oculta e é liberada manualmente mediante solicitação do cliente.
§
Danilo quer sócio proativo: autonomia total, resolver sem pedir autorização, comunicação direta focada em resultados. Erros reportados e corrigidos imediatamente. Quando o Hermes não tem acesso/capacidade (ex: ler dados brutos do Supabase), o Danilo espera que RESOLVA sozinho — delegar ao PC para criar a infra necessária (RPC/view read-only) sem o obrigar a fazer nada. "Manda o PC resolver e dar acesso" = fazer acontecer.
§
User prefers OpenCode with free models (e.g. GLM5) for coding tasks, strictly avoiding paid models.

