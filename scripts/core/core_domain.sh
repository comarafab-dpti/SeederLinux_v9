#!/bin/bash
# ============================================================================
# Core Script: core_domain.sh
# SeederLinux Lite - Ingresso no AD (SSSD/Winbind com fallback)
# ============================================================================
# Configura Kerberos, Samba, SSSD, PAM, NSS, sudo e mkhomedir para
# ingressar a estacao no dominio Active Directory.
#
# Suporta AUTH_METHOD:
#   sssd    - Apenas SSSD (realm join)
#   winbind - Apenas Winbind (net ads join)
#   both    - SSSD primeiro, fallback para Winbind se falhar
#
# Suporta ADMIN_PASSWORD_B64 (senha codificada em base64).
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "04 - Ingresso no Active Directory"
echo "============================================================"

# ============================================================
# Variaveis
# ============================================================
DOMINIO="{{DOMINIO}}"
DOMINIO_NETBIOS="{{DOMINIO_NETBIOS}}"
DC_IP="{{DC_IP}}"
DC_IP_LIST="{{DC_IP_LIST}}"
OU_PADRAO="{{OU_PADRAO}}"
GRUPO_ADMIN="{{GRUPO_ADMIN}}"
GRUPO_ADMIN_AD="{{GRUPO_ADMIN_AD}}"
GRUPO_ADMIN_LINUX="{{GRUPO_ADMIN_LINUX}}"
GRUPO_DASTI="{{GRUPO_DASTI}}"
OFFLINE_AUTH_ENABLED="{{OFFLINE_AUTH_ENABLED}}"
OFFLINE_AUTH_DAYS="{{OFFLINE_AUTH_DAYS}}"
ADMIN_USERNAME="{{ADMIN_USERNAME}}"
AUTH_METHOD="{{AUTH_METHOD}}"
ADMIN_PASSWORD_B64="__ADMIN_PASSWORD_B64__"

echo ">>> Dominio: $DOMINIO"
echo ">>> NetBIOS: $DOMINIO_NETBIOS}"
echo ">>> DC principal: $DC_IP"
echo ">>> Metodo de autenticacao: $AUTH_METHOD"

# ============================================================
# Decodificar senha base64 se fornecida
# ============================================================
if [ -n "$ADMIN_PASSWORD_B64" ] && [ "$ADMIN_PASSWORD_B64" != "" ]; then
    ADMIN_PASSWORD=$(echo "$ADMIN_PASSWORD_B64" | base64 -d 2>/dev/null)
    if [ -n "$ADMIN_PASSWORD" ]; then
        echo ">>> Senha do AD decodificada de base64 (${#ADMIN_PASSWORD} caracteres)"
    else
        echo ">>> AVISO: Falha ao decodificar ADMIN_PASSWORD_B64 — senha nao decodificada"
    fi
fi

# ============================================================
# Ajustar DNS para ingresso no dominio
# ============================================================
echo ">>> Ajustando DNS para ingresso no dominio..."

cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true

cat > /etc/resolv.conf <<EOF
nameserver $DNS_PRIMARIO
EOF

if [ -n "$DNS_SECUNDARIO" ] && [ "$DNS_SECUNDARIO" != "" ]; then
    echo "nameserver $DNS_SECUNDARIO" >> /etc/resolv.conf
fi

echo "search $DOMINIO" >> /etc/resolv.conf

echo ">>> DNS ajustado para ingresso: $DNS_PRIMARIO"

echo ">>> Verificando resolucao do dominio..."
if ! host "$DOMINIO" > /dev/null 2>&1; then
    echo ">>> AVISO: Dominio $DOMINIO nao resolve. Verifique o DNS."
    echo ">>> Tentando mesmo assim..."
fi

# ============================================================
# Definir modo winbind offline logon conforme AUTH_METHOD e OFFLINE_AUTH_ENABLED
# ============================================================
if { [ "$AUTH_METHOD" = "winbind" ] || [ "$AUTH_METHOD" = "both" ]; } && [ "$OFFLINE_AUTH_ENABLED" = "true" ]; then
    WINBIND_OFFLINE="yes"
else
    WINBIND_OFFLINE="false"
fi

# ============================================================
# Configurar Kerberos
# ============================================================
echo ">>> Configurando Kerberos..."
REALM="${DOMINIO^^}"

cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = ${REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = true
    rdns = false
    ticket_lifetime = 24h
    forwardable = yes
    renew_lifetime = 7d

[realms]
    ${REALM} = {
        kdc = ${DC_IP}
        admin_server = ${DC_IP}
    }

[domain_realm]
    .${DOMINIO} = ${REALM}
    ${DOMINIO} = ${REALM}
EOF

echo ">>> Kerberos configurado"

# ============================================================
# Configurar Samba
# ============================================================
echo ">>> Configurando Samba..."
cat > /etc/samba/smb.conf <<EOF
[global]
    workgroup = ${DOMINIO_NETBIOS}
    realm = ${DOMINIO}
    security = ads
    dns forwarder = ${DC_IP}
    idmap config * : backend = tdb
    idmap config * : range = 3000-7999
    idmap config ${DOMINIO_NETBIOS} : backend = rid
    idmap config ${DOMINIO_NETBIOS} : range = 10000-999999
    template shell = /bin/bash
    template homedir = /home/%D/%U
    winbind use default domain = true
    winbind offline logon = ${WINBIND_OFFLINE}
    winbind nss info = rfc2307
    winbind enum users = no
    winbind enum groups = no
    load printers = no
    printing = bsd
    printcap name = /dev/null
    disable spoolss = yes
EOF

echo ">>> Samba configurado"

# ============================================================
# Obter credenciais do administrador do dominio
# ============================================================
echo "============================================================"
echo ">>> INGRESSO NO DOMINIO - CREDENCIAIS NECESSARIAS"
echo "============================================================"

if [ -z "$ADMIN_USERNAME" ] || [ "$ADMIN_USERNAME" = "Administrator" ]; then
    read -p ">>> Usuario administrador do dominio [Administrator]: " ADMIN_USER
    ADMIN_USERNAME="${ADMIN_USER:-Administrator}"
fi

# Se a senha nao foi decodificada de base64, pedir interativamente
if [ -z "$ADMIN_PASSWORD" ] || [ "$ADMIN_PASSWORD" = "" ]; then
    read -s -p ">>> Senha do administrador do dominio: " ADMIN_PASSWORD
    echo ""
fi

echo ">>> Ingressando no dominio..."

# ============================================================
# Obter ticket Kerberos - tentar multiplas combinacoes
# ============================================================
echo ">>> Obtendo ticket Kerberos..."
KINIT_OK=false

# Tentativa 1: REALM maiusculo (Administrator@COMARA.INTRAER)
echo "$ADMIN_PASSWORD" | kinit "${ADMIN_USERNAME}@${DOMINIO^^}" 2>/dev/null && KINIT_OK=true

# Tentativa 2: NETBIOS (Administrator@COMARA)
[ "$KINIT_OK" != "true" ] && echo "$ADMIN_PASSWORD" | kinit "${ADMIN_USERNAME}@${DOMINIO_NETBIOS}" 2>/dev/null && KINIT_OK=true

# Tentativa 3: Dominio minusculo (administrator@comara.intraer)
[ "$KINIT_OK" != "true" ] && echo "$ADMIN_PASSWORD" | kinit "${ADMIN_USERNAME,,}@${DOMINIO,,}" 2>/dev/null && KINIT_OK=true

# Tentativa 4: Usuario minusculo, REALM maiusculo (administrator@COMARA.INTRAER)
[ "$KINIT_OK" != "true" ] && echo "$ADMIN_PASSWORD" | kinit "${ADMIN_USERNAME,,}@${DOMINIO^^}" 2>/dev/null && KINIT_OK=true

if [ "$KINIT_OK" != "true" ]; then
    echo ">>> ERRO: Falha ao obter ticket Kerberos com todas as combinacoes."
    echo ">>> Verifique usuario/senha e conectividade com o DC."
    read -p ">>> Deseja continuar mesmo assim? (S/n): " CONTINUE
    if [[ "$CONTINUE" =~ ^[Nn]$ ]]; then
        echo ">>> Instalacao abortada pelo usuario."
        exit 1
    fi
    echo ">>> Continuando apesar do erro..."
else
    echo ">>> Ticket Kerberos obtido com sucesso!"
fi

# ============================================================
# Ingressar no dominio - SSSD (realm join) e/ou Winbind (net ads join)
# ============================================================
JOIN_OK=false
JOIN_METHOD=""

# --- Metodo 1: SSSD (realm join) ---
if [ "$AUTH_METHOD" = "sssd" ] || [ "$AUTH_METHOD" = "both" ]; then
    echo ">>> Ingressando no dominio via realm join (SSSD)..."
    if echo "$ADMIN_PASSWORD" | realm join "$DOMINIO" \
        --user="$ADMIN_USERNAME" \
        --computer-ou="$OU_PADRAO" \
        --verbose 2>&1; then

        # Verificar se o keytab foi gerado
        if [ ! -f /etc/krb5.keytab ]; then
            echo ">>> Keytab nao encontrado. Tentando gerar com adcli..."
            echo "$ADMIN_PASSWORD" | adcli join "$DOMINIO" \
                --login-user="$ADMIN_USERNAME" \
                --domain-ou="$OU_PADRAO" \
                --verbose 2>&1 || true
        fi

        if [ -f /etc/krb5.keytab ]; then
            JOIN_OK=true
            JOIN_METHOD="sssd"
            echo ">>> Ingresso via SSSD (realm join) bem-sucedido!"
        else
            echo ">>> AVISO: realm join executado mas keytab nao gerado."
        fi
    else
        echo ">>> AVISO: realm join falhou."
    fi
fi

# --- Metodo 2: Winbind (net ads join) - fallback ou metodo principal ---
if [ "$JOIN_OK" != "true" ]; then
    if [ "$AUTH_METHOD" = "winbind" ] || [ "$AUTH_METHOD" = "both" ]; then
        echo ">>> Ingressando no dominio via net ads join (Winbind)..."
        if echo "$ADMIN_PASSWORD" | net ads join "$DOMINIO" \
            -U "$ADMIN_USERNAME" \
            createcomputer="$OU_PADRAO" 2>&1; then

            if [ -f /etc/krb5.keytab ]; then
                JOIN_OK=true
                JOIN_METHOD="winbind"
                echo ">>> Ingresso via Winbind (net ads join) bem-sucedido!"
            else
                echo ">>> AVISO: net ads join executado mas keytab nao gerado."
                # Tentar gerar keytab manualmente
                net ads keytab create -U "$ADMIN_USERNAME" 2>/dev/null && {
                    JOIN_OK=true
                    JOIN_METHOD="winbind"
                    echo ">>> Keytab gerado manualmente via net ads keytab."
                } || true
            fi
        else
            echo ">>> AVISO: net ads join falhou."
        fi
    fi
fi

# --- Verificar resultado do ingresso ---
if [ "$JOIN_OK" = "false" ]; then
    echo ">>> ERRO: Falha ao ingressar no dominio com todos os metodos."
    read -p ">>> Deseja continuar mesmo assim? (S/n): " CONTINUE
    if [[ "$CONTINUE" =~ ^[Nn]$ ]]; then
        echo ">>> Instalacao abortada pelo usuario."
        exit 1
    fi
    echo ">>> Continuando apesar do erro..."
fi

# Verificar keytab
if [ -f /etc/krb5.keytab ]; then
    echo ">>> Keytab gerado com sucesso."
    chmod 600 /etc/krb5.keytab
fi

echo ">>> Metodo de ingresso utilizado: ${JOIN_METHOD:-nenhum}"
unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_B64
echo ">>> Ingresso no dominio realizado"

# ============================================================
# Configurar SSSD (se metodo for sssd ou both)
# ============================================================
if [ "$JOIN_METHOD" = "sssd" ] || [ "$AUTH_METHOD" = "sssd" ]; then
    echo ">>> Configurando SSSD..."
    OFFLINE_CACHE=""
    if [ "$OFFLINE_AUTH_ENABLED" = "true" ]; then
        DAYS="${OFFLINE_AUTH_DAYS:-3}"
        OFFLINE_CACHE="cache_credentials = true
    krb5_store_password_if_offline = true
    offline_credentials_expiration = ${DAYS}"
    fi

    cat > /etc/sssd/sssd.conf <<EOF
[sssd]
services = nss, pam, sudo
config_file_version = 2
domains = ${DOMINIO}

[domain/${DOMINIO}]
    id_provider = ad
    ad_domain = ${DOMINIO}
    ad_server = ${DC_IP}
    ad_hostname = $(hostname).${DOMINIO}
    ldap_id_mapping = true
    enumerate = false
    use_fully_qualified_names = false
    fallback_homedir = /home/%d/%u
    default_shell = /bin/bash
    ${OFFLINE_CACHE}
    dyndns_update = false
    sudo_provider = ad
    ldap_sudo_search_base = OU=sudoers,${OU_PADRAO}
EOF

    chmod 600 /etc/sssd/sssd.conf
    echo ">>> SSSD configurado"
fi

# ============================================================
# Configurar NSS (suporta SSSD e Winbind)
# ============================================================
echo ">>> Configurando NSS..."
if [ "$JOIN_METHOD" = "winbind" ] || [ "$AUTH_METHOD" = "winbind" ]; then
    cat > /etc/nsswitch.conf <<EOF
passwd:     files systemd winbind
shadow:     files winbind
group:      files systemd winbind
gshadow:    files

hosts:      files dns

services:   files
netgroup:   files
sudoers:    files

automount:  files
EOF
else
    cat > /etc/nsswitch.conf <<EOF
passwd:     files systemd sss
shadow:     files sss
group:      files systemd sss
gshadow:    files

hosts:      files dns

services:   files sss
netgroup:   files sss
sudoers:    files sss

automount:  files sss
EOF
fi

echo ">>> NSS configurado"

# ============================================================
# Configurar PAM (mkhomedir)
# ============================================================
echo ">>> Configurando PAM e mkhomedir..."
pam-auth-update --enable mkhomedir --force 2>/dev/null || true

# Garantir criacao automatica do home
if [ -f /etc/pam.d/common-session ]; then
    grep -q "pam_mkhomedir" /etc/pam.d/common-session || \
        echo "session required pam_mkhomedir.so skel=/etc/skel umask=0022" >> /etc/pam.d/common-session
fi

# Configurar Winbind no PAM se necessario
if [ "$JOIN_METHOD" = "winbind" ] || [ "$AUTH_METHOD" = "winbind" ]; then
    pam-auth-update --enable winbind 2>/dev/null || true
fi

echo ">>> PAM configurado"

# ============================================================
# Configurar sudo para grupos do dominio
# ============================================================
echo ">>> Configurando sudo..."
SUDO_FILE="/etc/sudoers.d/seederlinux-domain"
cat > "$SUDO_FILE" <<EOF
# SeederLinux - Acesso sudo para grupos do dominio
%${GRUPO_ADMIN_AD}    ALL=(ALL:ALL) ALL
%${GRUPO_ADMIN_LINUX}  ALL=(ALL:ALL) ALL
EOF

if [ -n "$GRUPO_DASTI" ] && [ "$GRUPO_DASTI" != "" ]; then
    echo "%${GRUPO_DASTI}    ALL=(ALL:ALL) ALL" >> "$SUDO_FILE"
fi

chmod 440 "$SUDO_FILE"
visudo -cf "$SUDO_FILE" || {
    echo ">>> ERRO: sintaxe do sudoers invalida"
    read -p ">>> Deseja continuar mesmo assim? (S/n): " CONTINUE
    if [[ "$CONTINUE" =~ ^[Nn]$ ]]; then
        echo ">>> Instalacao abortada pelo usuario."
        exit 1
    fi
    echo ">>> Continuando apesar do erro..."
}

echo ">>> Sudo configurado"

# ============================================================
# Reiniciar servicos
# ============================================================
echo ">>> Reiniciando servicos..."
systemctl restart samba 2>/dev/null || true

if [ "$JOIN_METHOD" = "sssd" ] || [ "$AUTH_METHOD" = "sssd" ]; then
    systemctl restart sssd 2>/dev/null || true
    systemctl enable sssd 2>/dev/null || true
fi

if [ "$JOIN_METHOD" = "winbind" ] || [ "$AUTH_METHOD" = "winbind" ]; then
    systemctl restart winbind 2>/dev/null || true
    systemctl enable winbind 2>/dev/null || true
fi

echo ">>> [04] Ingresso no AD concluido!"
echo "============================================================"
