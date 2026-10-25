---
name: corte-automatico-reels
description: Antes da montagem de reels com pessoas reais (Bora e Em Dia), corta pausas longas do vídeo bruto com ffmpeg silencedetect (margem 0,15 s) e valida o roteiro pela regra de 2,5 palavras/segundo. Passo ANTES do fiscal. Não publica nada, não toca em código das apps nem em preços.
metadata:
  type: marketing
  versao: 1
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: radar-videos-2026-10-14
---

# Corte automático de pausas + regra de roteiro

Origem: radar de vídeos 14/10/2026 (nota 8). Custo zero: ffmpeg já existe no PC e na VPS.
**Só para vídeo com fala de pessoas reais.** Reels 100% IA/Veo com voz TTS não precisam (a voz já sai sem pausas).

## Posição no pipeline
`filmagem/bruto → [ESTA SKILL: corte] → montagem → fiscal → entrega`. Também aplicável ao Em Dia.

## 1. Roteiro (antes de filmar/gravar a voz)
Regra: **2,5 palavras por segundo** (20 s ≈ 50 palavras; 9 s ≈ 22).
```
python -I scripts/conta_palavras.py 20 --ficheiro roteiro.txt   # uma fala por linha
```
Exit 1 = excede → cortar texto ou subir a duração. O roteirista mede cada fala antes de a aprovar.

Ao escrever o roteiro, seguir também `docs/marketing/REGRAS-REELS-RADAR-2026-10-04.md` (estrutura "mas/então", última frase ligada à primeira, ar de conversa real, palavra-chave no gancho e na voz).

## 2. Corte do bruto
```
python -I scripts/corta_pausas.py bruto.mp4 cortado.mp4 --dry-run   # ver o que fica
python -I scripts/corta_pausas.py bruto.mp4 cortado.mp4
```
Parâmetros (defaults testados): `--ruido -35` (dB), `--min-pausa 0.5` (só pausas ≥0,5 s), `--margem 0.15`
(cada corte deixa 0,15 s de silêncio em cada ponta da pausa → não soa robótico).
Respirações fortes: baixar `--min-pausa` para 0.35. Ruído de fundo alto: subir `--ruido` para -30.
Trechos repetidos (a pessoa repete a frase): o script não os deteta — ver a transcrição e cortar a mão
com o segmento listado no `--dry-run`.

## 3. Verificar (obrigatório)
- Comparar duração antes/depois (o script imprime) e ouvir/fotogramas à volta dos cortes.
- Nunca ultrapassar a duração-alvo do formato (reel ≤ 20 s, story ≤ 9 s) — se cortar demais, o fiscal reprova por ritmo.
- O ficheiro de entrada nunca é alterado; guardar sempre o bruto.

## Prova de teste (22/10/2026)
Áudio sintético 6,0 s (tom 2 s, silêncio 2 s, tom 2 s) → 4,35 s (silêncio 2,0 → 0,3 s = 2×0,15). Segunda passagem não corta mais.

## Notas
- ffmpeg ≥7 usa `-/filter_complex`; o script cai para `-filter_complex_script` em versões antigas (VPS).
- Telemetria no fim: linha em `.claude/.ai/knowledge/wiki/skills-metrics.md`.

## Admin Panel Needed?
Não — é passo interno de produção de vídeo.
