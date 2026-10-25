# Morada da inscrição, anexos por email, W-8BEN
> Referência de `apple-conta-e-loja`; carregar só quando o SKILL.md mandar.

## 9. Morada da inscrição, anexos por email e o W-8BEN (18/09)
- **A morada da inscrição corrige-se por pedido escrito, não pela Apple sozinha:**
  `developer.apple.com/account` → Membership details → "Update your information" → modal
  "Change contact details" → "Provide updates" → formulário
  `developer.apple.com/contact/request/update-individual-information/` (Região, tipo
  Nome/Endereço/Ambos, novo endereço, informações adicionais; **sem campo de ficheiro**). Abre
  um caso próprio (18/09: 102967621679) e a Apple pede documentação depois. O campo "New
  address in Roman character" **apaga acentos, vírgulas e "º"** no `keyup`/`blur` (só letras,
  dígitos, espaço, `.`, `-`, `#`, `&`): escreve-se em ASCII e a grafia exacta vai nas
  informações adicionais (que aceitam acentos). Fonte: ajuda "Updating your account
  information" ("go to the membership details section … to submit a request").
- **Responder a um caso com anexo:** o suporte responde de `emea_appsen_support@apple.com`
  (Genesys; o `[caseId]` no assunto liga a resposta ao caso). O `reply`/`create_draft` do Gmail
  MCP só levam anexos em base64 — 170 KB escritos à mão corrompem o PDF. Receita segura:
  rascunho pelo MCP (`create_draft` com `replyToMessageId`) → Gmail web no Chrome perfil Bora
  → `find` "file input Filedata" → `file_upload` (ficheiro copiado para o scratchpad; apagar
  depois) → chip com nome e tamanho → Send → `get_message` do SENT mostra `attachments`.
- **"Informações fiscais em falta" nas duas linhas de impostos** = questionário guardado,
  W-8BEN por preencher. O W-8BEN é do Danilo (juramento; data de nascimento, NIF, tratado,
  certificação; Enviar é irreversível): o agente deixa a aba aberta e escreve o mapa dos
  campos no CONTINUAR. "A processar" na conta bancária = IBAN colado, 24 h para processar.
