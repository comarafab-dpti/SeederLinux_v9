#!/bin/bash
# ============================================================================
# Core Script: core_logoff.sh
# SeederLinux Lite - Logoff multi-DE
# ============================================================================
# Script executado no momento do logoff do usuario. Cria o script permanente
# /usr/local/bin/seederlinux-logoff que sera chamado pelo display manager
# (LightDM/GDM3/SDDM) a cada logoff, apos reboot.
#
# O script permanente detecta automaticamente o ambiente grafico, desmonta
# compartilhamentos CIFS, limpa cache e temporarios, e encerra processos.
# Le as variaveis de /etc/seederlinux/config.env (persistente).
#
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "15 - Logoff do usuario (multi-DE)"
echo "============================================================"

# ============================================================
# Variaveis (substituidas no bundle)
# ============================================================
DOMINIO="{{DOMINIO}}"
DOMINIO_NETBIOS="{{DOMINIO_NETBIOS}}"
SERVIDOR_ARQUIVOS="{{SERVIDOR_ARQUIVOS}}"
COMPARTILHAMENTOS="{{COMPARTILHAMENTOS}}"
MOUNT_BASE="{{MOUNT_BASE}}"
DESKTOP_ENV="{{DESKTOP_ENV}}"

# ============================================================
# Detectar ambiente grafico se nao definido
# ============================================================
if [ -z "$DESKTOP_ENV" ] || [ "$DESKTOP_ENV" = "" ]; then
    if command -v cinnamon-session &>/dev/null; then DESKTOP_ENV="cinnamon"
    elif command -v mate-session &>/dev/null; then DESKTOP_ENV="mate"
    elif command -v gnome-session &>/dev/null; then DESKTOP_ENV="gnome"
    elif command -v startxfce4 &>/dev/null; then DESKTOP_ENV="xfce"
    elif command -v startplasma-x11 &>/dev/null; then DESKTOP_ENV="kde"
    elif command -v startlxde &>/dev/null; then DESKTOP_ENV="lxde"
    else DESKTOP_ENV="unknown"
    fi
    echo ">>> DE detectado automaticamente: $DESKTOP_ENV"
fi

# ============================================================
# 1. Criar o script PERMANENTE em /usr/local/bin/seederlinux-logoff
# ============================================================
echo ">>> Criando script permanente: /usr/local/bin/seederlinux-logoff"

cat > /usr/local/bin/seederlinux-logoff <<'PERMSCRIPT'
#!/bin/bash
# seederlinux-logoff - Script permanente de logoff do SeederLinux (multi-DE)
# Executado pelo display manager (LightDM/GDM3/SDDM) a cada logoff.
# Le as variaveis de /etc/seederlinux/config.env (persistente).

CONFIG_FILE="/etc/seederlinux/config.env"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo ">>> [logoff] AVISO: $CONFIG_FILE nao encontrado. Logoff sem configuracao."
    exit 0
fi

USERNAME="${USER:-$(whoami)}"
USER_HOME="${HOME:-/home/$USERNAME}"
LOG_DIR="/var/log/logon-logoff"
LOG_FILE="$LOG_DIR/logoff_${USERNAME}.log"

mkdir -p "$LOG_DIR"

exec >> "$LOG_FILE" 2>&1
echo "=== Logoff: $(date) - Usuario: $USERNAME ==="

# ============================================================
# Funcoes de deteccao de ambiente
# ============================================================
detect_de() {
    if command -v cinnamon-session &>/dev/null; then echo "cinnamon"
    elif command -v mate-session &>/dev/null; then echo "mate"
    elif command -v gnome-session &>/dev/null; then echo "gnome"
    elif command -v startxfce4 &>/dev/null; then echo "xfce"
    elif command -v startplasma-x11 &>/dev/null; then echo "kde"
    elif command -v startlxde &>/dev/null; then echo "lxde"
    else echo "unknown"
    fi
}

DESKTOP_ENV=$(detect_de)
echo ">>> [logoff] Ambiente: $DESKTOP_ENV"

# ============================================================
# Desmontar compartilhamentos CIFS do usuario
# ============================================================
if [ -n "$COMPARTILHAMENTOS" ] && [ "$COMPARTILHAMENTOS" != "" ]; then
    MOUNT_DIR="${MOUNT_BASE:-/mnt}"
    for SHARE in $COMPARTILHAMENTOS; do
        SHARE_MOUNT="${MOUNT_DIR}/${SHARE}"
        if mountpoint -q "$SHARE_MOUNT" 2>/dev/null; then
            umount "$SHARE_MOUNT" 2>/dev/null || {
                echo ">>> [logoff] AVISO: Falha ao desmontar ${SHARE_MOUNT}"
                umount -l "$SHARE_MOUNT" 2>/dev/null || true
            }
            echo ">>> [logoff] Compartilhamento desmontado: ${SHARE}"
        fi
    done
fi

# ============================================================
# Limpar cache de navegadores
# ============================================================
rm -rf "$USER_HOME/.cache/mozilla" 2>/dev/null || true
rm -rf "$USER_HOME/.cache/google-chrome" 2>/dev/null || true
rm -rf "$USER_HOME/.cache/chromium" 2>/dev/null || true

# ============================================================
# Esvaziar lixeira
# ============================================================
rm -rf "$USER_HOME/.local/share/Trash"/* 2>/dev/null || true

# ============================================================
# Remover temporarios do usuario
# ============================================================
find /tmp -user "$USERNAME" -type f -mmin +60 -delete 2>/dev/null || true
rm -rf "$USER_HOME/.cache/thumbnails" 2>/dev/null || true

# ============================================================
# Remover atalhos temporarios do desktop (compartilhamentos desmontados)
# ============================================================
if [ -n "$COMPARTILHAMENTOS" ] && [ "$COMPARTILHAMENTOS" != "" ]; then
    for SHARE in $COMPARTILHAMENTOS; do
        rm -f "$USER_HOME/Desktop/${SHARE}.desktop" 2>/dev/null || true
    done
fi

# ============================================================
# Matar processos do usuario (conky, x11vnc)
# ============================================================
killall -u "$USERNAME" conky 2>/dev/null || true
killall -u "$USERNAME" x11vnc 2>/dev/null || true

# ============================================================
# Rotacionar logs (manter 7 dias)
# ============================================================
find "$LOG_DIR" -name "logoff_*.log" -mtime +7 -delete 2>/dev/null || true
find "$LOG_DIR" -name "logon_*.log" -mtime +7 -delete 2>/dev/null || true

echo "=== Logoff concluido: $(date) ==="
exit 0
PERMSCRIPT

chmod 755 /usr/local/bin/seederlinux-logoff
echo ">>> Script permanente criado: /usr/local/bin/seederlinux-logoff"

# ============================================================
# 2. Executar logica de logoff AGORA (durante o bundle)
# ============================================================
echo ">>> Executando logica de logoff (bundle)..."

USERNAME="${USER:-$(whoami)}"
USER_HOME="${HOME:-/home/$USERNAME}"

echo ">>> [logoff] Usuario: $USERNAME"

if [ -n "$COMPARTILHAMENTOS" ] && [ "$COMPARTILHAMENTOS" != "" ]; then
    MOUNT_DIR="${MOUNT_BASE:-/mnt}"
    for SHARE in $COMPARTILHAMENTOS; do
        SHARE_MOUNT="${MOUNT_DIR}/${SHARE}"
        if mountpoint -q "$SHARE_MOUNT" 2>/dev/null; then
            umount "$SHARE_MOUNT" 2>/dev/null || {
                echo ">>> [logoff] AVISO: Falha ao desmontar ${SHARE_MOUNT}"
                umount -l "$SHARE_MOUNT" 2>/dev/null || true
            }
            echo ">>> [logoff] Compartilhamento desmontado: ${SHARE}"
        fi
    done
fi

rm -rf "$USER_HOME/.cache/mozilla" 2>/dev/null || true
rm -rf "$USER_HOME/.cache/google-chrome" 2>/dev/null || true
rm -rf "$USER_HOME/.cache/chromium" 2>/dev/null || true
rm -rf "$USER_HOME/.local/share/Trash"/* 2>/dev/null || true
find /tmp -user "$USERNAME" -type f -mmin +60 -delete 2>/dev/null || true
rm -rf "$USER_HOME/.cache/thumbnails" 2>/dev/null || true

if [ -n "$COMPARTILHAMENTOS" ] && [ "$COMPARTILHAMENTOS" != "" ]; then
    for SHARE in $COMPARTILHAMENTOS; do
        rm -f "$USER_HOME/Desktop/${SHARE}.desktop" 2>/dev/null || true
    done
fi

killall -u "$USERNAME" conky 2>/dev/null || true
killall -u "$USERNAME" x11vnc 2>/dev/null || true

echo ">>> [15] Logoff concluido!"
echo "============================================================"
