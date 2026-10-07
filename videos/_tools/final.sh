#!/usr/bin/env bash
# final.sh <projeto> <nome> <dur> <audio.wav>  — render final 16:9 e 9:16, mux, ffprobe, apaga frames
set -e
cd "$(dirname "$0")/.."
P=$1; N=$2; D=$3; A=$4
for R in 16x9 9x16; do
  if [ "$R" = "16x9" ]; then W=1920; H=1080; else W=1080; H=1920; fi
  rm -rf "$P/frames_$R"
  node _tools/render.js --html "$P/index.html" --w $W --h $H --dur "$D" --out "$P/frames_$R" | tail -1
  node _tools/mux.js --frames "$P/frames_$R" --audio "$A" --out "$P/out/${N}_$R.mp4" --crf 17 --preset medium >/dev/null
  rm -rf "$P/frames_$R"
  echo "== ${N}_$R.mp4" >> "$P/out/ffprobe.txt"
  ffprobe -v error -show_entries format=duration:stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels -of default=nw=1 "$P/out/${N}_$R.mp4" >> "$P/out/ffprobe.txt"
  echo "FINAL_OK ${N}_$R"
done
