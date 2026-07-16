#!/bin/bash
# ============================================================================
# Core Script: core_browser.sh
# SeederLinux Lite - Politicas Firefox/Chrome
# ============================================================================
# Configura politicas corporativas para Firefox ESR, Google Chrome e Chromium
# via arquivos de policies (JSON) no sistema.
# Os placeholders {{VARIAVEL}} são substituídos automaticamente
# pelo sistema na geração do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "06 - Configurar politicas de navegadores"
echo "============================================================"

# ============================================================
# Variáveis
# ============================================================
HOMEPAGE="{{HOMEPAGE}}"
PROXY_MODE="{{PROXY_MODE}}"
PROXY_HTTP="{{PROXY_HTTP}}"
PROXY_PORTA="{{PROXY_PORTA}}"
PAC_URL="{{PAC_URL}}"
NO_PROXY="{{NO_PROXY}}"
DOMINIO="{{DOMINIO}}"
OM_ACRONYM="{{OM_ACRONYM}}"
CERTIFICATE_BUNDLE="{{CERTIFICATE_BUNDLE}}"

echo ">>> Homepage: $HOMEPAGE"
echo ">>> Modo de proxy: $PROXY_MODE"

# ============================================================
# Firefox ESR - Politicas (policies.json)
# ============================================================
echo ">>> Configurando politicas do Firefox ESR..."
mkdir -p /usr/lib/firefox-esr/distribution

cat > /usr/lib/firefox-esr/distribution/policies.json <<EOF
{
    "policies": {
        "DisableTelemetry": true,
        "DisableFirefoxStudies": true,
        "DisablePocket": true,
        "DisableDeveloperTools": false,
        "BlockAboutConfig": false,
        "Homepage": {
            "URL": "${HOMEPAGE}",
            "Locked": true,
            "StartPage": "homepage"
        },
        "HomepageURL": "${HOMEPAGE}",
        "SearchBar": "unified",
        "SearchEngines": {
            "Add": [
                {
                    "Name": "${OM_ACRONYM}",
                    "URL": "${HOMEPAGE}",
                    "Method": "GET"
                }
            ]
        },
        "Proxy": {
            "Mode": "system",
            "Locked": true
        },
        "Certificates": {
            "ImportEnterpriseRoots": true
        },
        "ExtensionSettings": {
            "*": {
                "installation_mode": "allowed"
            }
        },
        "DisableSetDesktopBackground": false,
        "DontCheckDefaultBrowser": true,
        "PrimaryPassword": false,
        "OfferToSaveLogins": false,
        "PasswordManagerEnabled": false,
        "SanitizeOnShutdown": {
            "Cache": true,
            "Cookies": false,
            "Downloads": false,
            "FormData": true,
            "History": false,
            "Sessions": false,
            "SiteSettings": false,
            "OfflineApps": false
        }
    }
}
EOF

echo ">>> Politicas do Firefox configuradas"

# ============================================================
# Firefox ESR - autoconfig (para proxy PAC)
# ============================================================
if [ "$PROXY_MODE" = "PAC" ]; then
    echo ">>> Configurando PAC no Firefox..."
    mkdir -p /usr/lib/firefox-esr/defaults/pref
    cat > /usr/lib/firefox-esr/defaults/pref/autoconfig.js <<EOF
pref("general.config.filename", "seederlinux.cfg");
pref("general.config.obscure_value", 0);
EOF

    cat > /usr/lib/firefox-esr/seederlinux.cfg <<EOF
lockPref("network.proxy.type", 2);
lockPref("network.proxy.autoconfig_url", "${PAC_URL}");
lockPref("network.proxy.no_proxies_on", "${NO_PROXY}");
EOF
    echo ">>> PAC configurado no Firefox"
elif [ "$PROXY_MODE" = "MANUAL" ]; then
    echo ">>> Configurando proxy manual no Firefox..."
    mkdir -p /usr/lib/firefox-esr/defaults/pref
    cat > /usr/lib/firefox-esr/defaults/pref/autoconfig.js <<EOF
pref("general.config.filename", "seederlinux.cfg");
pref("general.config.obscure_value", 0);
EOF

    cat > /usr/lib/firefox-esr/seederlinux.cfg <<EOF
lockPref("network.proxy.type", 1);
lockPref("network.proxy.http", "${PROXY_HTTP}");
lockPref("network.proxy.http_port", ${PROXY_PORTA});
lockPref("network.proxy.https", "${PROXY_HTTP}");
lockPref("network.proxy.https_port", ${PROXY_PORTA});
lockPref("network.proxy.no_proxies_on", "${NO_PROXY}");
EOF
    echo ">>> Proxy manual configurado no Firefox"
fi

# ============================================================
# Google Chrome - Politicas
# ============================================================
echo ">>> Configurando politicas do Google Chrome..."
mkdir -p /etc/opt/chrome/policies/managed
mkdir -p /etc/opt/chrome/policies/recommended

# Proxy config para Chrome
case "$PROXY_MODE" in
    NONE)
        CHROME_PROXY_MODE="direct"
        ;;
    MANUAL)
        CHROME_PROXY_MODE="fixed_servers"
        CHROME_PROXY_SERVERS="http=${PROXY_HTTP}:${PROXY_PORTA};https=${PROXY_HTTP}:${PROXY_PORTA}"
        ;;
    PAC)
        CHROME_PROXY_MODE="pac_script"
        CHROME_PROXY_PAC_URL="$PAC_URL"
        ;;
    *)
        CHROME_PROXY_MODE="system"
        ;;
esac

# Construir JSON de proxy
PROXY_JSON=""
if [ "$CHROME_PROXY_MODE" = "fixed_servers" ]; then
    PROXY_JSON=", \"ProxyMode\": \"${CHROME_PROXY_MODE}\", \"ProxyServer\": \"${CHROME_PROXY_SERVERS}\""
elif [ "$CHROME_PROXY_MODE" = "pac_script" ]; then
    PROXY_JSON=", \"ProxyMode\": \"${CHROME_PROXY_MODE}\", \"ProxyPacUrl\": \"${CHROME_PROXY_PAC_URL}\""
else
    PROXY_JSON=", \"ProxyMode\": \"${CHROME_PROXY_MODE}\""
fi

cat > /etc/opt/chrome/policies/managed/seederlinux.json <<EOF
{
    "HomepageLocation": "${HOMEPAGE}",
    "HomepageIsNewTabPage": false,
    "RestoreOnStartup": 1,
    "RestoreOnStartupURLs": ["${HOMEPAGE}"],
    "BrowserSignin": 0,
    "SyncDisabled": true,
    "BlockThirdPartyCookies": true,
    "BackgroundModeEnabled": false,
    "TelemetryReportingEnabled": false,
    "UrlKeyboardsEnabled": false${PROXY_JSON},
    "DefaultCookiesSetting": 1,
    "AutoSelectCertificateForUrls": ["{\"pattern\":\"https://*\",\"filter\":{}}"],
    "ChromeCertProtectorEnabled": false
}
EOF

echo ">>> Politicas do Chrome configuradas"

# ============================================================
# Chromium - Politicas (mesmas do Chrome)
# ============================================================
echo ">>> Configurando politicas do Chromium..."
mkdir -p /etc/chromium/policies/managed
mkdir -p /etc/chromium/policies/recommended

cp /etc/opt/chrome/policies/managed/seederlinux.json \
   /etc/chromium/policies/managed/seederlinux.json 2>/dev/null || true

echo ">>> Politicas do Chromium configuradas"

echo ">>> [06] Politicas de navegadores configuradas!"
echo "============================================================"
