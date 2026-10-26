#!/bin/bash
# Rodar os dois logs que cresciam sem fim + rotação automática (geral-sabado-24-10, bloco 2b).
# Nada se perde: o conteúdo antigo fica comprimido ao lado (.1.gz); o ficheiro
# vivo continua a ser escrito pelo mesmo processo (copytruncate).
set -u
# ATENÇÃO: não esvaziar /root/whatsapp-bora/ligar.log — o vigia_porta.py lê o estado dali
# e, vazio, reinicia o WhatsApp (aconteceu a 25/10 23:46 com a 1.ª versão deste guião).
for f in /root/orquestracao/cortex-proposals-sync.log; do
  [ -f "$f" ] || continue
  antes=$(du -h "$f" | cut -f1)
  cp -p "$f" "$f.1" && : > "$f" && gzip -9 -f "$f.1"
  echo "$f: $antes -> $(du -h "$f" | cut -f1) (antigo em $f.1.gz, $(du -h "$f.1.gz" | cut -f1))"
done

cat > /etc/logrotate.d/bora-logs <<'EOF'
# Logs da Bora que crescem sem fim (24/10/2026, missão geral-sabado-24-10).
/root/orquestracao/*.log {
    weekly
    maxsize 50M
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
logrotate -d /etc/logrotate.d/bora-logs 2>&1 | grep -ciE "error" | sed 's/^/erros no teste do logrotate: /'

# A cache de pacotes do Dart/Flutter volta a descarregar-se sozinha no próximo pub get.
du -sh /root/.pub-cache 2>/dev/null
rm -rf /root/.pub-cache/hosted /root/.pub-cache/_temp
df -h / | tail -1
