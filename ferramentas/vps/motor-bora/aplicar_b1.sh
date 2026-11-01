#!/bin/bash
# B1 infra-claude-tudo-2026-11-01: porteiro sem racao + perfis claude-dipsy/claude-opus + porta fechada 8793.
# Copia de seguranca, compila, reinicia; se o motor nao responder, repoe tudo e reinicia.
set -u
ST=/root/infra-2026-11-01
M=/opt/motor-bora
SUF=bak-semracao-20261101
cd $ST || exit 1
sed -i 's/\r$//' porteiro.py servidor_motor.py catalogo.py
for f in porteiro.py servidor_motor.py catalogo.py; do python3 -m py_compile $f || { echo "COMPILA_FALHOU $f"; exit 2; }; done
cp -p $M/motor_bora/porteiro.py $M/motor_bora/porteiro.py.$SUF
cp -p $M/motor_bora/catalogo.py $M/motor_bora/catalogo.py.$SUF
cp -p $M/servidor_motor.py $M/servidor_motor.py.$SUF
# senha da porta fechada (32 bytes aleatorios), so root le; nunca se imprime
mkdir -p /opt/segredos
if ! grep -q '^PORTEIRO_TOKEN=' /opt/segredos/porteiro.env 2>/dev/null; then
  umask 077; echo "PORTEIRO_TOKEN=$(openssl rand -hex 32)" >> /opt/segredos/porteiro.env
fi
chmod 600 /opt/segredos/porteiro.env
echo "senha: $(wc -c < /opt/segredos/porteiro.env) bytes no ficheiro, impressao $(sed -n 's/^PORTEIRO_TOKEN=//p' /opt/segredos/porteiro.env | sha256sum | cut -c1-12)"
cp $ST/porteiro.py $M/motor_bora/porteiro.py
cp $ST/catalogo.py $M/motor_bora/catalogo.py
cp $ST/servidor_motor.py $M/servidor_motor.py
mkdir -p /etc/systemd/system/motor-bora.service.d
cat > /etc/systemd/system/motor-bora.service.d/porta-fechada.conf <<'EOF'
[Service]
Environment=MOTOR_BINDS_FECHADOS=172.16.1.1:8793
EOF
systemctl daemon-reload
systemctl restart motor-bora
ok=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 2
  if curl -s -m 3 http://127.0.0.1:8792/saude | grep -q '"ok": true'; then ok=1; break; fi
done
if [ $ok -ne 1 ]; then
  echo "MOTOR_NAO_RESPONDE: a repor"
  cp -p $M/motor_bora/porteiro.py.$SUF $M/motor_bora/porteiro.py
  cp -p $M/motor_bora/catalogo.py.$SUF $M/motor_bora/catalogo.py
  cp -p $M/servidor_motor.py.$SUF $M/servidor_motor.py
  rm -f /etc/systemd/system/motor-bora.service.d/porta-fechada.conf
  systemctl daemon-reload; systemctl restart motor-bora
  journalctl -u motor-bora -n 30 --no-pager
  exit 3
fi
echo "MOTOR_OK"
ss -tlnp | grep -E ':879[23] ' | awk '{print $4}'
python3 $ST/ver_porteiro.py
