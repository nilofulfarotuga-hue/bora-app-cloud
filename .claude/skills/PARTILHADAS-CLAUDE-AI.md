# Skills vindas da Claude.ai (23/10/2026)

Pedido do Danilo: as skills da Claude.ai, do Claude Code e do Hermes passam a ser uma pasta só (esta, `.claude/skills/`), lida pelos três.

## Copiadas para aqui (licença Apache 2.0 — podem ser partilhadas; o LICENSE.txt de cada uma fica junto)
- `frontend-design` — design de páginas e ecrãs com aspeto próprio (maquetes para propostas a clientes, sites).
- `skill-creator` — criar e melhorar skills, com testes. O Hermes usa-a quando transformar uma tarefa que correu bem numa skill nova.
- `mcp-builder` — construir servidores MCP (ligar agentes a serviços novos).
- `theme-factory` — 10 temas prontos de cores e letra para páginas, documentos e apresentações.
- `canvas-design` — cartazes e peças visuais em PNG/PDF (traz fontes, por isso pesa 5,6 MB).
- `web-artifacts-builder` — páginas HTML complexas (React, Tailwind) num só ficheiro.
- `financial-calculator` — contas e comparações (empréstimos, impostos, cenários), só matemática.
- `file-form` — burocracia (formulários, pedidos a entidades, multas).
- `cancel-unsubscribe` — cancelar assinaturas e auditar cobranças repetidas.
- `return-refund` — devoluções e reembolsos de compras.
- `paint` — desenhar imagens por código, sem gerador de imagens pago.

## NÃO copiadas (a licença da Anthropic proíbe tirá-las da Claude.ai ou dá-las a terceiros)
`docx`, `pdf`, `pptx`, `xlsx`, `file-reading`, `pdf-reading`, `chrome-browser`, `built-in-browser`, `computer-use`, `artifact-emulator`, e as sem licença (`deep-research`, `docs`, `google-workspace`, `import-memory`, `morning`, `doc-coauthoring`, `setup-writing-style`, `product-self-knowledge`).
O Claude Code e a Claude.ai já as têm de origem. O Hermes, se precisar de Word/Excel/PDF/PowerPoint, usa skills próprias escritas do zero (python-docx, openpyxl, pypdf, python-pptx) — nunca cópias destas.

## Deixadas de fora por não servirem ao Danilo
`benepass-reimbursement`, `file-expenses`, `grocery-shopping`, `meal-delivery`, `prescription-refill`, `hire-help`, `call-to-book`, `event-planning`, `internal-comms`, `brand-guidelines` (marca da Anthropic), `slack-gif-creator`, `algorithmic-art`, `learn`.
