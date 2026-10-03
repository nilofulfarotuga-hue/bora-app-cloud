# 01 — FUNDADOR E VISÃO

## Quem é Danilo

Brasileiro, mora na Guarda (Portugal). Fundador **solo** do Bora App. Trabalha como motorista TVDE (Uber/Bolt) — é daí que vem a renda hoje e a visão de dentro do negócio: ele vive diariamente o lado do motorista/estafeta e conversa com clientes e comerciantes reais da cidade. Carro: Hyundai Ioniq 5.

Não escreve código. O projeto inteiro é construído por agentes de IA (Claude.ai orquestra; Claude Code executa; Hermes avisa) e Danilo **decide, aprova e testa no device real**. Toda a comunicação dele é por voz em PT-BR informal — mensagens chegam fragmentadas e fonéticas; interpretar sempre pela intenção, não ao pé da letra.

## Filosofia de trabalho (como ele pensa)

- **Não inventar**: copiar o que Glovo/Uber/iFood/Helpling já validaram. Sugestão só se existe nos grandes.
- **Não estragar o que funciona**: acrescentar, nunca refazer por gosto.
- **Caminho mais direto**: MCP-first; dúvida se resolve investigando, nunca chutando.
- **Autonomia com trava**: quer o máximo de execução automática, mas com zonas vermelhas (dinheiro, auth, Stripe) protegidas por travas duras e aprovação humana.
- **Prova > palavra**: "está a correr" só vale com SELECT/log/screenshot que prove.
- **Uma coisa de cada vez**: uma ordem em voo por vez; 4 ordens simultâneas já derrubaram o terminal.

## História resumida do projeto

- **Mar–Abr 2026**: fundação — motor de dispatch (Edge Function + Haversine + pg_cron), wallet dual (saldo livre + tokens), regras de negócio, catálogo de ~42.000 produtos de supermercados.
- **Mai 2026**: migração Codemagic → GitHub Actions; arquitetura multi-agente (Trava/Cérebro/Exército/Juiz/Loop); exploração de white-label.
- **Jun 2026**: hardening de segurança (RLS em 36 tabelas backup, REVOKEs, trigger protege-admin); motor de cancelamento em 5 estágios; Favores v3; chat bidirecional; MB Way em Reservas/Serviços; primeiro parceiro de Serviços (Barbearia Nobre); paridade McDonald's/BK/KFC com Glovo.
- **Jul 2026**: TVDE fechado (pagamento-antes-de-despachar, €8 ida-e-volta, paradas €2); loop E2E autônomo; Córtex Bora + motor de conhecimento (C1–C4); mini-sites de parceiros reais; candidatura à produção do Play Store submetida em 22/07/2026.

## Visão de futuro (ideias registradas do Danilo)

1. **Lançar na Guarda primeiro** — validar o modelo, gerar tração real, case de sucesso.
2. **Bora SP (Brasil)**: instância separada operada pelos irmãos dele em São Paulo, Danilo cuida da técnica remotamente. Exige: BRL, PIX (obrigatório), nota fiscal eletrônica/LGPD, cadeias de mercado brasileiras, PT-BR. Estimado 80–150h de trabalho de agente após o launch da Guarda. Decisão: instância separada (não multi-região no mesmo app).
3. **White-label / revenda**: vender o app rebatizado para outras cidades. O Bora hoje NÃO está arquitetado pra isso (EUR, MB Way, mercados PT hard-coded) — refatorar só depois do case da Guarda. Modelo preferido: white-label centralizado (uma base, vários brandings) evoluindo pra SaaS multi-tenant.
4. **Bora Business (SaaS)**: plataforma modular pra comércio local — agendamento pra clínicas, marcações pra barbearias, reservas pra hotéis — mesma infra Flutter+Supabase, parceiro ativa só os módulos do seu tipo de negócio. Ideia guardada, retomar quando ele decidir.
5. **Incubadoras (referência guardada, NÃO agir)**: NERGAEmpreende (angela.goncalves@nerga.pt) e IPG@Empreende+ / Politécnico da Guarda (Nuno Coelho, 966 961 599 — provável melhor fit tech). Domínio bora.pt (~€10–20/ano) só na hora do launch.
6. **Estratégia de parceiros por presente**: mini-sites cinematográficos gratuitos pra comerciantes reais da Guarda (Ouro e Prata, Sabores de Casa, BeUnique) como porta de entrada — o site divulga a loja e o CTA leva pro Bora.

## Pós-launch (backlog aprovado)

- Reservas Mesa Pro best-in-class (~15–25h)
- Takeaway Pro (`service_type='takeaway'`, ~10–15h)
- Tap to Pay / SoftPOS via Stripe Terminal
- Estafeta sinaliza produto em falta (sistema universal)
- Lidl/Mercadona via fluxo AJUDANTE (após Auchan+Intermarché)
