#!/bin/bash
# ============================================================================
# Core Script: core_legados.sh
# SeederLinux Lite - Java 8, Firefox 52.7 ESR (sistemas legados)
# ============================================================================
# Instala Java 8 (OpenJDK ou Oracle) e/ou Firefox 52.7 ESR para compatibilidade
# com sistemas legados (applets Java, sistemas antigos da intranet).
# Cada componente e controlado por seu proprio toggle:
#   INSTALL_JAVA8     - Instalar Java 8?
#   INSTALL_FIREFOX52 - Instalar Firefox 52.7 ESR?
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "11 - Configurar sistemas legados (Java 8, Firefox 52.7)"
echo "============================================================"

# ============================================================
# Variaveis
# ============================================================
INSTALL_JAVA8="{{INSTALL_JAVA8}}"
INSTALL_FIREFOX52="{{INSTALL_FIREFOX52}}"
BASE_URL="{{BASE_URL}}"
PROXY_MODE="{{PROXY_MODE}}"
PROXY_HTTP="{{PROXY_HTTP}}"
PROXY_PORTA="{{PROXY_PORTA}}"
JAVA_EXCEPTIONS="{{JAVA_EXCEPTIONS}}"

echo ">>> Instalar Java 8: $INSTALL_JAVA8"
echo ">>> Instalar Firefox 52.7: $INSTALL_FIREFOX52"
echo ">>> Excecoes Java: ${JAVA_EXCEPTIONS:-nenhuma}"

# ============================================================
# Verificar se pelo menos um toggle esta ativo
# ============================================================
if [ "$INSTALL_JAVA8" != "true" ] && [ "$INSTALL_FIREFOX52" != "true" ]; then
    echo ">>> Sistemas legados desativados. Pulando."
    echo ">>> [11] Sistemas legados nao instalados (desativado)."
    echo "============================================================"
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive

# Configurar proxy para downloads
if [ "$PROXY_MODE" = "MANUAL" ] && [ -n "$PROXY_HTTP" ] && [ "$PROXY_HTTP" != "" ]; then
    export http_proxy="http://${PROXY_HTTP}:${PROXY_PORTA}"
    export https_proxy="http://${PROXY_HTTP}:${PROXY_PORTA}"
fi

# ============================================================
# Java 8 (OpenJDK 8) - apenas se INSTALL_JAVA8=true
# ============================================================
if [ "$INSTALL_JAVA8" = "true" ]; then
    echo ">>> Instalando Java 8 (OpenJDK 8)..."

    # Verificar se ja esta instalado (foi instalado no core_packages.sh)
    if command -v java &>/dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | head -1)
        echo ">>> Java ja instalado: $JAVA_VERSION"
    else
        echo ">>> AVISO: Java 8 nao foi instalado no core_packages.sh."
        echo ">>> Tentando instalar via repositorio Adoptium/Temurin..."

        if wget -q -O /tmp/adoptium-key.asc "https://packages.adoptium.net/artifactory/api/gpg/key/public" 2>/dev/null; then
            gpg --dearmor < /tmp/adoptium-key.asc > /usr/share/keyrings/adoptium-keyring.gpg 2>/dev/null || true
            echo "deb [signed-by=/usr/share/keyrings/adoptium-keyring.gpg] https://packages.adoptium.net/artifactory/deb bookworm main" \
                > /etc/apt/sources.list.d/adoptium.list
            apt-get update
            apt-get install -y temurin-8-jre || {
                echo ">>> AVISO: Falha ao instalar Java 8 via Adoptium."
            }
            rm -f /tmp/adoptium-key.asc
        else
            echo ">>> AVISO: Nao foi possivel obter chave do repositorio Java 8."
        fi
    fi

    # Configurar excecoes Java (deployment.properties) se fornecidas
    if [ -n "$JAVA_EXCEPTIONS" ] && [ "$JAVA_EXCEPTIONS" != "" ]; then
        echo ">>> Configurando excecoes Java..."
        DEPLOY_DIR="/usr/lib/jvm/.deployment"
        mkdir -p "$DEPLOY_DIR"
        DEPLOY_FILE="$DEPLOY_DIR/deployment.properties"
        echo "# Excecoes Java - SeederLinux" > "$DEPLOY_FILE"
        echo "deployment.security.level=MEDIUM" >> "$DEPLOY_FILE"
        # Processar cada URL (uma por linha ou separada por virgula)
        IFS=
else
    echo ">>> Java 8 desativado (INSTALL_JAVA8=false). Pulando."
fi

# ============================================================
# Firefox 52.7 ESR (para applets Java) - apenas se INSTALL_FIREFOX52=true
# ============================================================
if [ "$INSTALL_FIREFOX52" = "true" ]; then
    echo ">>> Instalando Firefox 52.7 ESR..."

    FF_LEGADO_DIR="/opt/firefox-legado"
    FF_LEGADO_TARBALL="/tmp/firefox-52.7-esr.tar.bz2"
    FF_LEGADO_URL="${BASE_URL}/downloads/firefox-52.7.3esr.tar.bz2"

    mkdir -p /opt

    # Tentar baixar do repositorio interno
    if wget -q -O "$FF_LEGADO_TARBALL" "$FF_LEGADO_URL" 2>/dev/null; then
        echo ">>> Firefox 52.7 baixado do repositorio interno"
        tar xjf "$FF_LEGADO_TARBALL" -C /opt/
        mv /opt/firefox "$FF_LEGADO_DIR" 2>/dev/null || true
        rm -f "$FF_LEGADO_TARBALL"
    else
        echo ">>> AVISO: Nao foi possivel baixar Firefox 52.7 do repositorio interno."
        echo ">>> Tentando download da Mozilla..."

        FF_MOZILLA_URL="https://ftp.mozilla.org/pub/firefox/releases/52.7.3esr/linux-x86_64/en-US/firefox-52.7.3esr.tar.bz2"
        if wget -q -O "$FF_LEGADO_TARBALL" "$FF_MOZILLA_URL" 2>/dev/null; then
            tar xjf "$FF_LEGADO_TARBALL" -C /opt/
            mv /opt/firefox "$FF_LEGADO_DIR" 2>/dev/null || true
            rm -f "$FF_LEGADO_TARBALL"
        else
            echo ">>> AVISO: Nao foi possivel baixar Firefox 52.7."
        fi
    fi

    # Criar link simbolico
    if [ -d "$FF_LEGADO_DIR" ]; then
        ln -sf "${FF_LEGADO_DIR}/firefox" /usr/local/bin/firefox-legado
        echo ">>> Firefox 52.7 ESR instalado em: $FF_LEGADO_DIR"

        # Criar entrada de desktop
        mkdir -p /usr/share/applications
        cat > /usr/share/applications/firefox-legado.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=Firefox 52.7 ESR (Legado)
Comment=Navegador Firefox 52.7 ESR para sistemas legados
Exec=${FF_LEGADO_DIR}/firefox
Icon=${FF_LEGADO_DIR}/browser/icons/mozicon128.png
Terminal=false
Type=Application
Categories=Network;WebBrowser;
EOF
        echo ">>> Entrada de desktop criada"
    else
        echo ">>> AVISO: Firefox 52.7 ESR nao instalado."
    fi

    # Configurar plugin Java para Firefox legado
    echo ">>> Configurando plugin Java para Firefox legado..."
    if [ -d "$FF_LEGADO_DIR" ] && command -v java &> /dev/null; then
        JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
        PLUGIN_DIR="${FF_LEGADO_DIR}/browser/plugins"
        mkdir -p "$PLUGIN_DIR"

        # Localizar libnpjp2.so
        find "$JAVA_HOME" -name "libnpjp2.so" -exec ln -sf {} "$PLUGIN_DIR/libnpjp2.so" \; 2>/dev/null || {
            echo ">>> AVISO: Plugin Java (libnpjp2.so) nao encontrado."
        }
        echo ">>> Plugin Java configurado"
    fi
else
    echo ">>> Firefox 52.7 desativado (INSTALL_FIREFOX52=false). Pulando."
fi

echo ">>> [11] Sistemas legados configurados!"
echo "============================================================"
\n,' read -ra EXC_URLS <<< "$JAVA_EXCEPTIONS"
        IDX=0
        for EXC_URL in "${EXC_URLS[@]}"; do
            EXC_URL=$(echo "$EXC_URL" | xargs)
            if [ -n "$EXC_URL" ] && [ "$EXC_URL" != "" ]; then
                echo "deployment.security.sandbox.awtwarningwindow=false" >> "$DEPLOY_FILE"
                echo "# Excecao $IDX: $EXC_URL" >> "$DEPLOY_FILE"
                # Adicionar a lista de excecoes
                echo "javaws.allow.0=$EXC_URL" >> "$DEPLOY_FILE"
                IDX=$((IDX+1))
            fi
        done
        echo ">>> Excecoes Java configuradas ($IDX URLs)"
    fi

    # Verificar Java 8
    if command -v java &> /dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | head -1)
        echo ">>> Java instalado: $JAVA_VERSION"
    else
        echo ">>> AVISO: Java nao instalado."
    fi
else
    echo ">>> Java 8 desativado (INSTALL_JAVA8=false). Pulando."
fi

# ============================================================
# Firefox 52.7 ESR (para applets Java) - apenas se INSTALL_FIREFOX52=true
# ============================================================
if [ "$INSTALL_FIREFOX52" = "true" ]; then
    echo ">>> Instalando Firefox 52.7 ESR..."

    FF_LEGADO_DIR="/opt/firefox-legado"
    FF_LEGADO_TARBALL="/tmp/firefox-52.7-esr.tar.bz2"
    FF_LEGADO_URL="${BASE_URL}/downloads/firefox-52.7.3esr.tar.bz2"

    mkdir -p /opt

    # Tentar baixar do repositorio interno
    if wget -q -O "$FF_LEGADO_TARBALL" "$FF_LEGADO_URL" 2>/dev/null; then
        echo ">>> Firefox 52.7 baixado do repositorio interno"
        tar xjf "$FF_LEGADO_TARBALL" -C /opt/
        mv /opt/firefox "$FF_LEGADO_DIR" 2>/dev/null || true
        rm -f "$FF_LEGADO_TARBALL"
    else
        echo ">>> AVISO: Nao foi possivel baixar Firefox 52.7 do repositorio interno."
        echo ">>> Tentando download da Mozilla..."

        FF_MOZILLA_URL="https://ftp.mozilla.org/pub/firefox/releases/52.7.3esr/linux-x86_64/en-US/firefox-52.7.3esr.tar.bz2"
        if wget -q -O "$FF_LEGADO_TARBALL" "$FF_MOZILLA_URL" 2>/dev/null; then
            tar xjf "$FF_LEGADO_TARBALL" -C /opt/
            mv /opt/firefox "$FF_LEGADO_DIR" 2>/dev/null || true
            rm -f "$FF_LEGADO_TARBALL"
        else
            echo ">>> AVISO: Nao foi possivel baixar Firefox 52.7."
        fi
    fi

    # Criar link simbolico
    if [ -d "$FF_LEGADO_DIR" ]; then
        ln -sf "${FF_LEGADO_DIR}/firefox" /usr/local/bin/firefox-legado
        echo ">>> Firefox 52.7 ESR instalado em: $FF_LEGADO_DIR"

        # Criar entrada de desktop
        mkdir -p /usr/share/applications
        cat > /usr/share/applications/firefox-legado.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=Firefox 52.7 ESR (Legado)
Comment=Navegador Firefox 52.7 ESR para sistemas legados
Exec=${FF_LEGADO_DIR}/firefox
Icon=${FF_LEGADO_DIR}/browser/icons/mozicon128.png
Terminal=false
Type=Application
Categories=Network;WebBrowser;
EOF
        echo ">>> Entrada de desktop criada"
    else
        echo ">>> AVISO: Firefox 52.7 ESR nao instalado."
    fi

    # Configurar plugin Java para Firefox legado
    echo ">>> Configurando plugin Java para Firefox legado..."
    if [ -d "$FF_LEGADO_DIR" ] && command -v java &> /dev/null; then
        JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
        PLUGIN_DIR="${FF_LEGADO_DIR}/browser/plugins"
        mkdir -p "$PLUGIN_DIR"

        # Localizar libnpjp2.so
        find "$JAVA_HOME" -name "libnpjp2.so" -exec ln -sf {} "$PLUGIN_DIR/libnpjp2.so" \; 2>/dev/null || {
            echo ">>> AVISO: Plugin Java (libnpjp2.so) nao encontrado."
        }
        echo ">>> Plugin Java configurado"
    fi
else
    echo ">>> Firefox 52.7 desativado (INSTALL_FIREFOX52=false). Pulando."
fi

echo ">>> [11] Sistemas legados configurados!"
echo "============================================================"
