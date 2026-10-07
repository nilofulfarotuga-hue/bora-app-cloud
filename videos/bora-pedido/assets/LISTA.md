# Materiais reais — Bora (D1)
> Recolhidos 2026-10-07. Tudo do repo ou do app web; nada gerado para o vídeo.

| ficheiro | origem | o que é | uso |
|---|---|---|---|
| `bora_logo.png` (645×360) | `assets/branding/bora_logo.png` | mascote na mota + BORA (BO verde / RA laranja) | abertura, fecho |
| `bora_app_icon_app.png` | `assets/branding/` | ícone da app | badge/CTA |
| `icon_512.png` | `web/icons/Icon-512.png` | ícone PWA 512 | moldura do telemóvel (ícone), CTA |
| `Inter-VariableFont.ttf` | `assets/fonts/` | a fonte da app | todo o texto |
| `web_flow_2.png` (1170×2532) | Playwright em https://bora-app-web.pages.dev (cookies **rejeitados**) | ecrã de escolha de perfil "Sou Cliente / Sou Estafeta / Sou Parceiro" com "Entregas rápidas em Portugal" | cena 1 (abrir a app) |
| `web_cli_2.png` | idem, depois de "Sou Cliente" | ecrã "Iniciar sessão" | reserva (não usado — não vende) |
| `web_cli_3.png` | idem | ecrã "Esqueceu-se da palavra-passe?" | reserva (não usado) |
| `web_home.png` | idem, 1.º carregamento | role + banner de cookies | reserva (não usado) |
| `golden_home_grelha_390.png` (390×844) | `test/golden/_fotos/grelha_categorias_4col_390.png` (teste golden real da app) | grelha das 14 categorias da home com os tiles reais | cena 2 (escolher categoria) |
| `cat_restaurantes.png`, `cat_supermercados.png`, `cat_lojas.png`, `cat_farmacia.png`, `cat_favores.png`, `cat_compras.png` (1024²) | `assets/categories/` | tiles reais das categorias (fundo transparente) | cena 2, versão Assistente |

## O que não deu
- A home do cliente **sem login** não abre no app web (a sessão de convidado está partida em produção — já
  registado na memória). Depois de "Sou Cliente" vai para "Iniciar sessão". Por isso a home vem do golden test
  real da app (`grelha_categorias_4col_390.png`), que é o ecrã renderizado pela própria app.
- Ecrãs de loja/carrinho/pedido: não acessíveis sem sessão → desenhados em HTML com os componentes e cores da app
  (cartão branco, cantos 16, verde `#16A34A`, 1 laranja por ecrã) e marcados como UI reconstruída em `BRAND.md`.
- Frase da home (código, `client_home_screen.dart` l.347/357): **"Olá!" / "O que precisas hoje?"**.
- Frase do ecrã de perfil (captura real): **"Entregas rápidas em Portugal"**.
