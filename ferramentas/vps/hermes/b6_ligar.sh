#!/bin/bash
# B6: aponta o porteiro do Telegram ao grupo Bora Bastidores (-5541278366) e prova com um INFO (nao vai ao chat do Danilo)
F=/opt/data/voz/porteiro.env
cp -p $F $F.bak-infra-20261101 2>/dev/null
if grep -q '^PORTEIRO_BASTIDORES_CHAT=' $F 2>/dev/null; then sed -i 's/^PORTEIRO_BASTIDORES_CHAT=.*/PORTEIRO_BASTIDORES_CHAT=-5541278366/' $F
else echo 'PORTEIRO_BASTIDORES_CHAT=-5541278366' >> $F; fi
grep -c '^PORTEIRO_BASTIDORES_CHAT=-5541278366' $F
cd /opt/data/voz
python3 porteiro.py --bastidores 2>&1 | tail -2
head -40 porteiro_cli.py | grep -nE 'uso|Uso|argv|danilo|INFO|--' | head -8
python3 porteiro_cli.py danilo INFO --origem infra-claude-tudo "Bastidores ligado: este aviso de prova (INFO) veio para o grupo e nao para a conversa do Danilo." 2>&1 | tail -3
sleep 4
tail -n 2 /opt/data/voz/porteiro/porteiro.log.jsonl 2>/dev/null | cut -c1-300
