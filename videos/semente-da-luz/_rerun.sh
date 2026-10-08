#!/usr/bin/env bash
cd "$(dirname "$0")/.."
P=semente-da-luz/fecho; rm -rf $P/frames_9x16
node _tools/render.js --html $P/index.html --w 1080 --h 1920 --dur 15 --out $P/frames_9x16 | tail -1
node _tools/mux.js --frames $P/frames_9x16 --audio semente-da-luz/out/fecho_audio.wav --out $P/out/semente_fecho_9x16.mp4 --crf 17 >/dev/null && echo "FINAL_OK semente_fecho_9x16"
rm -rf $P/frames_9x16
echo "== semente_fecho_9x16.mp4" >> $P/out/ffprobe.txt; ffprobe -v error -show_entries format=duration:stream=codec_type,codec_name,width,height,r_frame_rate -of default=nw=1 $P/out/semente_fecho_9x16.mp4 >> $P/out/ffprobe.txt
bash _tools/final.sh semente-da-luz/cena_s02 semente_cena_s02 10 semente-da-luz/out/s02_audio.wav
bash _tools/final.sh semente-da-luz/cena_s12 semente_cena_s12 10 semente-da-luz/out/s12_audio.wav
