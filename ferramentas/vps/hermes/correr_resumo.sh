#!/bin/bash
C=hermes-agent-fvnc-hermes-agent-1
docker cp /root/infra-2026-11-01/resumo_perfis.py $C:/tmp/resumo_perfis.py
docker exec $C bash -c 'for py in /opt/hermes/.venv/bin/python /opt/hermes/venv/bin/python /usr/local/bin/python3 /usr/bin/python3 python3; do if [ -x "$py" ] || command -v "$py" >/dev/null; then if "$py" -c "import yaml" 2>/dev/null; then "$py" /tmp/resumo_perfis.py; exit 0; fi; fi; done; echo SEM_PYTHON_COM_YAML'
