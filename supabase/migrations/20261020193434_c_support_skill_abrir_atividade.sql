-- Bloco C · fechar-pendencias-2026-10-20 — skill do robô de suporte: como abrir atividade nas Finanças.
-- Gerada pela skill add-support-skill (_preview/ABRIR_ATIVIDADE_FINANCAS.md), validate_skill.py exit 0
-- (mode=read_only, sem termos sensíveis) → pode ficar ativa. Só informação; nenhuma tool, nenhuma promessa.
-- Códigos e passos confirmados em fonte oficial (lista no fim do playbook).
INSERT INTO public.support_skills (skill_name, version, category, mode, requires_human_handoff,
                                   playbook_md, allowed_tools, examples, active)
VALUES (
  'ABRIR_ATIVIDADE_FINANCAS', 1, 'faq', 'read_only', false,
  $skill$# ABRIR_ATIVIDADE_FINANCAS

**Quando usar:** um prestador (estafeta, motorista TVDE, limpeza, lavagem de carros,
barbearia ou beleza) pergunta como abrir atividade nas Finanças, o que é o "comprovativo de
atividade" que a app pede, se é preciso pagar para abrir atividade, que código de atividade
usar, ou onde se envia o comprovativo. Ex.: "como abro atividade?", "o que é o comprovativo
de atividade?", "abrir atividade é de graça?", "que código ponho?".

**Tools:** [] (resposta direta, não chamar tools). Responder em PT-PT, curto e simples.

## O que a app pede
- Quem trabalha no Bora por conta própria precisa de ter atividade aberta nas Finanças.
- Na app, no ecrã "Comprovativo de atividade", indica o NIF e envia o comprovativo (foto ou
  PDF). No ecrã principal do trabalho aparece o aviso "Falta o comprovativo de atividade"
  com o botão Enviar.
- Quem já trabalha continua a trabalhar enquanto envia. As candidaturas novas só são
  aprovadas depois de o comprovativo ser aprovado.

## Como se abre atividade
- **É grátis online.** Ao balcão também é grátis se a declaração for preenchida online; em
  papel custa 0,35 €.
- **Online, no Portal das Finanças:** entrar com o NIF e a senha das Finanças (ou com o
  Cartão de Cidadão ou a Chave Móvel Digital) → "Todos os Serviços" → "Início de
  Atividade" → "Entregar declaração". Preencher o código da atividade, a data de início, o
  volume de negócios previsto até ao fim do ano e o IBAN de uma conta em nome próprio.
  Carregar em "Validar" e depois em "Submeter".
- **Presencial:** num Serviço de Finanças (a repartição) ou numa Loja do Cidadão, com o
  documento de identificação e o NIF. No fim entregam o comprovativo do início de atividade.
- Abre-se antes de começar a trabalhar, o mais tardar no próprio dia em que se começa.
- Depois de entregar online, a atividade aparece no Portal das Finanças em "Atividade" →
  "Consultar dados de Atividade" → "Situação Fiscal Integrada - Informação Cadastral" →
  "Atividade Exercida". Uma foto ou PDF dessa página (ou o comprovativo dado na repartição)
  é o que se envia na app.

## Códigos de atividade (lista CAE-Rev.4)
- Limpeza de casas e escritórios: **81210 — Limpeza geral de edifícios**.
- Motorista TVDE: **49330 — Atividades de serviços de transporte de passageiros, a pedido,
  em veículo com condutor**.
- Estafeta (entregas): **53202 — Atividades de serviços de entrega ao domicílio sem
  tratamento ou triagem**.
- Barbearia ou cabeleireiro: **96210 — Atividades de salões de cabeleireiro e barbeiros**.
- Lavagem de carros e qualquer outro trabalho: **confirma o código na repartição de
  Finanças**.
- Se o Portal não mostrar o código, ou se houver dúvidas, **confirma o código na repartição
  de Finanças**. As Finanças aceitam códigos da lista do artigo 151.º do Código do IRS ou da
  CAE.

## Motorista TVDE
- Além da atividade nas Finanças, o motorista TVDE precisa do **certificado de motorista
  TVDE do IMT** (carta de condução de ligeiros há mais de 3 anos com o grupo 2, curso de
  formação inicial de pelo menos 50 horas e idoneidade) e de **trabalhar com um operador
  TVDE**, com contrato escrito entre os dois.
- Na app, o certificado e o contrato com o operador vão na Ficha legal do motorista.

## Regras
- Não dar conselho fiscal (IVA, IRS, regime, quanto vai pagar de imposto): encaminhar para a
  repartição de Finanças ou para um contabilista certificado.
- Nunca inventar códigos. Para um trabalho que não está na lista: "confirma o código na
  repartição de Finanças".
- Nunca pedir no chat a senha das Finanças. O NIF e o comprovativo enviam-se no ecrã
  "Comprovativo de atividade" da app, não no chat.
- Dúvidas sobre a Segurança Social: confirmar diretamente na Segurança Social.

## Escalar quando
- A pessoa diz que enviou o comprovativo e foi recusado sem perceber porquê, ou o ecrã de
  envio dá erro → [HANDOFF_HUMAN].
- A pessoa insiste numa pergunta fiscal concreta (IVA, IRS, imposto) → explicar que não damos
  conselho fiscal e [HANDOFF_HUMAN].

## Fontes oficiais (lidas a 20/10/2026)
- gov.pt — Abrir atividade nas finanças: https://www.gov.pt/servicos/abrir-atividade-nas-financas
- Portal das Finanças — Início de atividade: https://info.portaldasfinancas.gov.pt/pt/apoio_ao_contribuinte/Cidadaos/Atividade_profissional/Declaracoes_de_atividade/Inicio_de_atividade/Paginas/default.aspx
- AT — folheto Início de atividade (IRS e IVA): https://info.portaldasfinancas.gov.pt/pt/apoio_contribuinte/Folhetos_informativos/Documents/Inicio_atividade.pdf
- CAE-Rev.4 — Decreto-Lei n.º 9/2025: https://files.diariodarepublica.pt/1s/2025/02/03000/0000800049.pdf
- IMT — Certificação de motoristas TVDE: https://www.imt-ip.pt/rodoviario/infraestruturas-rodoviarias/tvde/certificacao-de-motoristas-tvde/$skill$,
  '[]'::jsonb,
  $ex$[
    {"user": "como abro atividade nas finanças?",
     "assistant": "É grátis. No Portal das Finanças entras com o NIF e a senha, vais a Todos os Serviços → Início de Atividade → Entregar declaração, pões o código da atividade, a data de início e o IBAN, e submetes. Também podes ir a uma repartição de Finanças ou Loja do Cidadão com o documento de identificação. Depois envias o comprovativo na app, no ecrã Comprovativo de atividade."},
    {"user": "que código ponho para limpezas?",
     "assistant": "Para limpeza de casas e escritórios o código CAE é 81210 — Limpeza geral de edifícios. Se o Portal não o mostrar, confirma o código na repartição de Finanças."},
    {"user": "sou motorista tvde, o que preciso?",
     "assistant": "Precisas de atividade aberta nas Finanças (código 49330 — transporte de passageiros a pedido, em veículo com condutor), do certificado de motorista TVDE do IMT e de trabalhar com um operador TVDE com contrato escrito. Se o Portal não mostrar o código, confirma na repartição de Finanças."}
  ]$ex$::jsonb,
  true
)
ON CONFLICT (skill_name) DO NOTHING;
