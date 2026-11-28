# Código de atividade de quem faz limpezas (28/11/2026)

Missão `limpeza-planos-empresas-2026-11-28`, Bloco E.

## Conclusão

- **Código certo: CAE 81210 «Atividades de limpeza geral em edifícios».** Serve para limpeza de
  casas, lojas e escritórios por uma trabalhadora independente (no início de atividade pode
  escolher-se um código CAE ou um código da tabela do art. 151.º do CIRS).
- **1519 «Outros prestadores de serviços» é residual.** A Autoridade Tributária, nas
  informações vinculativas, diz que o 1519 só se usa quando a atividade não cabe em nenhum
  código CAE ou CIRS, e que o código deve corresponder o mais fielmente possível ao que se faz.
  Para limpezas há CAE próprio, por isso o 1519 não é o código adequado. Decisão: aceitar quem
  já o tem (não bloquear), mas pedir para acrescentar o 81210.
- **Aceites também**: 81220 (outras limpezas em edifícios e equipamentos industriais) e 81290
  (outras atividades de limpeza), como secundários.
- **CAE-Rev.4** (Decreto-Lei 9/2025, em vigor desde 01/01/2025): a equivalência exata do 81210 na
  Rev.4 está POR CONFIRMAR. O INE publica as tabelas de correspondência Rev.3↔Rev.4 no SMI
  (smi.ine.pt → Classificações → Correspondência de versões). A Rev.4 tem mais posições em
  quase todos os níveis, por isso o código de 5 dígitos pode mudar. Atenção: o "81.21 Limpieza
  general de edificios" que aparece nas pesquisas é da CNAE espanhola, não da CAE portuguesa.
- **Como acrescentar o código**: Portal das Finanças → Todos os Serviços → Atividade →
  Declaração de Alterações (grátis), ou numa repartição/Loja do Cidadão.

## O que ficou no servidor (28/11)

- Tabela `cleaner_activity_codes` (81210 preferido; 81220, 81290 e 1519 aceites), editável no
  painel por `admin_set_cleaner_activity_code` (auditado).
- `admin_cleaners_activity_status()`: lista de quem tem/não tem comprovativo e código certo.
  Lida a 28/11: das 10 profissionais (5 aprovadas), nenhuma tem comprovativo de atividade nas
  fichas; uma está marcada "sem atividade aberta". Ninguém aprovado foi bloqueado.
- App: no ecrã do comprovativo, quem tem o papel de limpeza vê a explicação do 81210.

## Fontes

- [Decreto-Lei 9/2025 (CAE-Rev.4)](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/legislacao/diplomas_legislativos/Documents/Decreto_Lei_9_2025.pdf)
- [AT, informação vinculativa PIV 28879 (1519 residual)](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/informacoes_vinculativas/rendimento/cirs/Documents/PIV_28879.pdf)
- [AT, informação vinculativa PIV 21590](https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/informacoes_vinculativas/rendimento/cirs/Documents/PIV_21590.pdf)
- [CAE 81210 (diretório Iberinform)](https://www.iberinform.pt/diretorio/diretorio-cnae/81210/limpeza-geral-de-edificios)
- [Conversão CAE Rev.3 → Rev.4](https://economiafinancas.com/2024/conversao-da-cae-rev-3-para-a-cae-rev-4/)
- [CAE-Rev.4 em vigor a partir de janeiro de 2025 (APCMC)](https://apcmc.pt/legislacao/cae-rev-4-em-vigor-a-partir-de-janeiro-de-2025/)
