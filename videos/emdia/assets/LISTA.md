# Materiais reais — Em Dia (D2)
> Recolhidos 2026-10-07 do repo `C:\BoraLocal\projetosflutter\em_dia`. O app web (app.emdia.boraguarda.com) exige
> sessão (login por código) — por isso os ecrãs vêm dos **goldens reais** da app (`test/golden/_fotos`, 1170×2532,
> dados de fixture: "Danilo", Clio AA-11-BB, valores de exemplo do teste).

| ficheiro | origem | o que é | uso |
|---|---|---|---|
| `emdia_icon.png` (1024²) | `assets/branding/icon.png` | ícone: calendário verde com check | abertura, fecho, CTA |
| `Inter-VariableFont.ttf` | `assets/fonts/` | fonte da app (`AppTheme.fonte = 'Inter'`) | todo o texto |
| `painel_verde_medio_pt.png` | golden `painel_verde` | Painel: "Olá, Danilo · Estás em dia?", "Está tudo em dia", "Mês grátis até 30/09" | cena 1 |
| `calendario_medio_pt.png` | golden `calendario` | Agenda: "Este mês pagas 4 coisas: 663,30 €", calendário de Setembro 2026 | cena 2 |
| `carro_medio_pt.png` | golden `carro` | O carro: Clio AA-11-BB · TVDE; Seguro, Inspeção (24/10/2026), IUC, Carta, Revisão | cena 3 |
| `vida_entra_cheio_medio_pt.png` | golden `vida_entra_cheio` | O meu dinheiro: "Este mês entrou 989,70 €", lista de entradas | cena 4 |
| `recibos_medio_pt.png`, `vida_sobra_bom_medio_pt.png` | goldens | reserva | não usados |
| cores | `lib/config/app_theme.dart` | emDia #16A34A · aVencer #F97316 · passou #DC2626 · bg #F6F7F4 · texto #111827 / #6B7280 · cantos 16 | tudo |
| texto do push | `app_pt.arb` `pushCarro` | "A inspeção do teu carro ({matricula}) é até {data}. Marca já — os centros enchem no fim do mês." | notificação |

Lojas: Android `pt.emdia.app` (Google Play); iOS a caminho (App Store Connect 6814807320, botão escondido no site até aprovar) →
o CTA leva **Google Play + app.emdia.boraguarda.com**, sem App Store.
