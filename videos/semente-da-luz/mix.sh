#!/usr/bin/env bash
# mix.sh — mistura leitos sintetizados + tema real + sfx reais + falas reais → out/<clip>_audio.wav
set -e
cd "$(dirname "$0")"
A=assets; O=out
node audio.js
# abertura 12 s: drone 0–2.6, portal.wav em 2.5, tema entra em 2.5 (0→9.5 s do tema) com fade 1.2 s no fim
ffmpeg -y -v error -i $O/bed_abertura.wav -i $A/portal.wav -i $A/tema_abertura_v4.wav -filter_complex \
 "[0]afade=t=out:st=2.3:d=0.5[b];[1]adelay=2500|2500,volume=1.0[p];[2]atrim=0:9.5,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.05,afade=t=out:st=8.3:d=1.2,adelay=2500|2500,volume=0.9[m];[b][p][m]amix=inputs=3:normalize=0:duration=longest,atrim=0:12,aformat=sample_rates=48000:channel_layouts=stereo" $O/abertura_audio.wav
# fecho 15 s: últimos 15 s do tema (32.9→47.9), fade-in 1 s, fade-out 1.5 s
ffmpeg -y -v error -i $A/tema_abertura_v4.wav -af "atrim=32.9:47.9,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=1,afade=t=out:st=13.5:d=1.5,aformat=sample_rates=48000:channel_layouts=stereo" $O/fecho_audio.wav
# s02 10 s: leito + estrondo em 0.8 + portal em 2.0
ffmpeg -y -v error -i $O/bed_s02.wav -i $A/estrondo.wav -i $A/portal.wav -filter_complex \
 "[1]adelay=800|800,volume=0.9[e];[2]adelay=2000|2000,volume=0.9[p];[0][e][p]amix=inputs=3:normalize=0:duration=first,aformat=sample_rates=48000:channel_layouts=stereo" $O/s02_audio.wav
# s12 10 s: leito + falas reais s12_1 em 0.8 e s12_2 em 5.0
ffmpeg -y -v error -i $O/bed_s12.wav -i $A/s12_1.wav -i $A/s12_2.wav -filter_complex \
 "[1]adelay=800|800,volume=1.0[v1];[2]adelay=5000|5000,volume=1.0[v2];[0][v1][v2]amix=inputs=3:normalize=0:duration=first,aformat=sample_rates=48000:channel_layouts=stereo" $O/s12_audio.wav
for f in abertura fecho s02 s12; do echo "$f $(ffprobe -v error -show_entries format=duration -of csv=p=0 $O/${f}_audio.wav)"; done
