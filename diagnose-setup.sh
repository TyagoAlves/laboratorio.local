#!/bin/bash
# diagnose-setup.sh - Diagnóstico e recuperação do setup do Windows
# Uso: bash diagnose-setup.sh

set -euo pipefail
C='\033[0;36m'; Y='\033[1;33m'; R='\033[0;31m'; G='\033[0;32m'; N='\033[0m'
pass() { echo -e "[${G}PASS${N}] $1"; }
fail() { echo -e "[${R}FAIL${N}] $1"; }
info() { echo -e "[${C}INFO${N}] $1"; }
warn() { echo -e "[${Y}WARN${N}] $1"; }

info "=== Diagnóstico do laboratorio.local ==="
echo ""

# 1. Container rodando?
if docker ps --format '{{.Names}}' | grep -q lab-windows; then
    pass "Container lab-windows está rodando."
else
    fail "Container lab-windows NÃO está rodando."
    warn "Execute: docker compose up -d"
    exit 1
fi

# 2. Volume OEM montado?
MOUNT=$(docker inspect lab-windows --format '{{json .Mounts}}' | python3 -c "import json,sys; ms=json.load(sys.stdin); print([m['Source'] for m in ms if '/oem' in m['Destination'] or '/OEM' in m['Destination']])" 2>/dev/null)
if echo "$MOUNT" | grep -qi "oem"; then
    pass "Volume OEM montado: $MOUNT"
else
    warn "Volume OEM não encontrado. Verifique volumes em docker-compose.yml"
fi

# 3. Arquivos OEM dentro do Windows?
info "Verificando scripts OEM dentro do Windows..."
for f in C:\\OEM\\install.bat C:\\OEM\\setup.ps1; do
    if docker exec lab-windows cmd /c "if exist $f (echo 1) else (echo 0)" 2>/dev/null | grep -q 1; then
        pass "$f existe."
    else
        fail "$f NÃO encontrado."
    fi
done

# 4. AD instalado?
info "Verificando AD DS..."
AD=$(docker exec lab-windows powershell "Get-Service NTDS -ErrorAction SilentlyContinue; if(\$?){echo 'OK'}" 2>/dev/null)
if [ "$AD" = "OK" ]; then
    pass "AD DS (NTDS) está instalado e rodando."
else
    fail "AD DS NÃO está instalado."
    warn "Executando setup.ps1 manualmente..."
    docker exec lab-windows powershell -File C:\\OEM\\setup.ps1
fi

# 5. Portas de rede
info "Verificando portas acessíveis do host..."
for port in 88 389 3389 5985 8006; do
    if timeout 2 bash -c "echo >/dev/tcp/localhost/$port" 2>/dev/null; then
        pass "Porta $port está ouvindo."
    else
        warn "Porta $port não responde."
    fi
done

# 6. LDAP respondendo?
info "Verificando LDAP..."
if command -v ldapsearch &>/dev/null; then
    LDAP=$(timeout 3 ldapsearch -H ldap://localhost:389 -x -s base -b "" "" 2>&1 | head -5)
    if echo "$LDAP" | grep -qi "laboratorio"; then
        pass "LDAP respondendo com domínio laboratorio.local."
    else
        warn "LDAP não responde ou domínio não reconhecido."
    fi
else
    warn "ldapsearch não instalado. Pule verificação LDAP."
fi

# 7. hMailServer
info "Verificando hMailServer..."
HMAIL=$(docker exec lab-windows powershell "Get-Service hMailServer -ErrorAction SilentlyContinue; if(\$?){echo 'OK'}" 2>/dev/null)
if [ "$HMAIL" = "OK" ]; then
    pass "hMailServer está instalado e rodando."
else
    warn "hMailServer não encontrado ou não instalado."
fi

echo ""
info "=== Diagnóstico concluído ==="
info "Se o AD não instalou, o setup.ps1 foi executado manualmente acima."
info "Acompanhe: docker compose logs -f windows"
info "Acesse a tela: http://localhost:8006/"
