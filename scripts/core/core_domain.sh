#!/bin/bash
# ============================================================================
# Core Script: core_domain.sh
# SeederLinux Lite - Ingresso no AD (SSSD/Winbind com fallback)
# ============================================================================
# Configura Kerberos, Samba, SSSD, PAM, NSS, sudo e mkhomedir para
# ingressar a estacao no dominio Active Directory.
#
# Metodos de autenticacao (AUTH_METHOD):
#   sssd   - Apenas SSSD (realm join)
#   winbind - Apenas Winbind (net ads join)
#   both   - Tenta SSSD primeiro, fallback para Winbind se falhar
#
# Credenciais:
#   Se ADMIN_USERNAME e ADMIN_PASSWORD_B64 forem preenchidas no painel,
#   usa-as sem perguntar (senha base64 e decodificada).
#   Caso contrario, pergunta interativamente.
#
# Os placeholders {{VARIAVEL}} são substituídos automaticamente
# pelo sistema na geração do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "04 - Ingresso no Active Directory"
echo "============================================================"

# ============================================================
# Variáveis
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
ADMIN_PASSWORD_B64="{{ADMIN_PASSWORD_B64}}"
AUTH_METHOD="{{AUTH_METHOD}}"

echo ">>> Dominio: $DOMINIO"
echo ">>> NetBIOS: $DOMINIO_NETBIOS"
echo ">>> DC principal: $DC_IP"
echo ">>> Metodo de autenticacao: $AUTH_METHOD"

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
# Configurar Samba (necessario para winbind e como fallback)
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
# Obter credenciais (flexivel: painel ou interativo)
# ============================================================
echo "============================================================"
echo ">>> INGRESSO NO DOMINIO - CREDENCIAIS"
echo "============================================================"

# Verificar se ADMIN_USERNAME foi preenchido no painel
if [ -z "$ADMIN_USERNAME" ] || [ "$ADMIN_USERNAME" = "Administrator" ] || [ "$ADMIN_USERNAME" = "{{ADMIN_USERNAME}}" ]; then
    read -p ">>> Usuario administrador do dominio [Administrator]: " ADMIN_USER
    ADMIN_USERNAME="${ADMIN_USER:-Administrator}"
fi

# Verificar se ADMIN_PASSWORD_B64 foi preenchida no painel
if [ -n "$ADMIN_PASSWORD_B64" ] && [ "$ADMIN_PASSWORD_B64" != "{{ADMIN_PASSWORD_B64}}" ] && [ "$ADMIN_PASSWORD_B64" != "" ]; then
    echo ">>> Usando senha configurada no painel (base64)..."
    ADMIN_PASSWORD=$(echo "$ADMIN_PASSWORD_B64" | base64 -d 2>/dev/null)
    if [ -z "$ADMIN_PASSWORD" ]; then
        echo ">>> AVISO: Decodificacao base64 falhou. Solicitando senha interativamente."
        read -s -p ">>> Senha do administrador do dominio: " ADMIN_PASSWORD
        echo ""
    fi
else
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
    exit 1
fi
echo ">>> Ticket Kerberos obtido com sucesso!"

# ============================================================
# Ingressar no dominio - logica com fallback SSSD -> Winbind
# ============================================================
JOIN_METHOD=""

# --- Tentativa SSSD (realm join) ---
if [ "$AUTH_METHOD" = "sssd" ] || [ "$AUTH_METHOD" = "both" ]; then
    echo ">>> Tentando ingresso via SSSD (realm join)..."
    if echo "$ADMIN_PASSWORD" | realm join "$DOMINIO" \
        --user="$ADMIN_USERNAME" \
        --computer-ou="$OU_PADRAO" \
        --verbose 2>/dev/null; then
        JOIN_METHOD="sssd"
        echo ">>> Ingresso via SSSD (realm join) bem-sucedido!"
    else
        echo ">>> realm join falhou."
        if [ "$AUTH_METHOD" = "sssd" ]; then
            echo ">>> ERRO: AUTH_METHOD=sssd e realm join falhou."
            unset ADMIN_PASSWORD
            exit 1
        fi
        echo ">>> Tentando fallback para Winbind..."
    fi
fi

# --- Tentativa SSSD com adcli (apenas se realm falhou e metodo inclui sssd) ---
if [ -z "$JOIN_METHOD" ] && { [ "$AUTH_METHOD" = "sssd" ] || [ "$AUTH_METHOD" = "both" ]; }; then
    echo ">>> Tentando adcli join como alternativa SSSD..."
    if echo "$ADMIN_PASSWORD" | adcli join "$DOMINIO" \
        --login-user="$ADMIN_USERNAME" \
        --domain-ou="$OU_PADRAO" \
        --verbose 2>/dev/null; then
        JOIN_METHOD="sssd"
        echo ">>> Ingresso via adcli bem-sucedido!"
    else
        echo ">>> adcli join tambem falhou."
        if [ "$AUTH_METHOD" = "sssd" ]; then
            echo ">>> ERRO: Todos os metodos SSSD falharam."
            unset ADMIN_PASSWORD
            exit 1
        fi
    fi
fi

# --- Tentativa Winbind (net ads join) ---
if [ -z "$JOIN_METHOD" ] && { [ "$AUTH_METHOD" = "winbind" ] || [ "$AUTH_METHOD" = "both" ]; }; then
    echo ">>> Tentando ingresso via Winbind (net ads join)..."
    if echo "$ADMIN_PASSWORD" | net ads join \
        -U "$ADMIN_USERNAME" \
        createcomputer="$OU_PADRAO" 2>/dev/null; then
        JOIN_METHOD="winbind"
        echo ">>> Ingresso via Winbind (net ads join) bem-sucedido!"
    else
        echo ">>> net ads join falhou."
    fi
fi

# --- Verificar resultado ---
if [ -z "$JOIN_METHOD" ]; then
    echo "============================================================"
    echo ">>> ERRO CRITICO: Todos os metodos de ingresso falharam!"
    echo ">>> Verifique:"
    echo ">>>   - Credenciais (usuario/senha)"
    echo ">>>   - Conectividade com o DC ($DC_IP)"
    echo ">>>   - Resolucao DNS do dominio ($DOMINIO)"
    echo ">>>   - Permissoes do usuario no AD"
    echo "============================================================"
    unset ADMIN_PASSWORD
    exit 1
fi

echo ">>> Metodo de ingresso utilizado: $JOIN_METHOD"

# Verificar keytab
if [ -f /etc/krb5.keytab ]; then
    echo ">>> Keytab gerado com sucesso."
    chmod 600 /etc/krb5.keytab
else
    echo ">>> AVISO: Keytab nao encontrado apos ingresso."
    if [ "$JOIN_METHOD" = "winbind" ]; then
        echo ">>> Winbind pode nao gerar keytab. Continuando..."
    else
        echo ">>> ERRO: Keytab nao foi gerado."
        unset ADMIN_PASSWORD
        exit 1
    fi
fi

unset ADMIN_PASSWORD
echo ">>> Ingresso no dominio realizado"

# ============================================================
# Configurar SSSD (apenas se ingresso foi SSSD)
# ============================================================
if [ "$JOIN_METHOD" = "sssd" ]; then
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

    # ============================================================
    # Configurar NSS para SSSD
    # ============================================================
    echo ">>> Configurando NSS para SSSD..."
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
    echo ">>> NSS configurado para SSSD"

# ============================================================
# Configurar Winbind (apenas se ingresso foi Winbind)
# ============================================================
elif [ "$JOIN_METHOD" = "winbind" ]; then
    echo ">>> Configurando Winbind..."

    # Atualizar smb.conf com configuracoes de winbind ja definidas
    echo ">>> Samba/Winbind ja configurado em smb.conf"

    # ============================================================
    # Configurar NSS para Winbind
    # ============================================================
    echo ">>> Configurando NSS para Winbind..."
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
    echo ">>> NSS configurado para Winbind"

    # Configurar PAM para winbind
    echo ">>> Configurando PAM para Winbind..."
    pam-auth-update --enable mkhomedir --force 2>/dev/null || true

    # Garantir criacao automatica do home
    if [ -f /etc/pam.d/common-session ]; then
        grep -q "pam_mkhomedir" /etc/pam.d/common-session || \
            echo "session required pam_mkhomedir.so skel=/etc/skel umask=0022" >> /etc/pam.d/common-session
    fi

    # Configurar cache offline do winbind se habilitado
    if [ "$OFFLINE_AUTH_ENABLED" = "true" ]; then
        echo ">>> Configurando cache offline do Winbind..."
        sed -i "s/winbind offline logon = .*/winbind offline logon = yes/" /etc/samba/smb.conf
    fi
    echo ">>> Winbind configurado"
fi

# ============================================================
# Configurar PAM (mkhomedir) - comum a ambos
# ============================================================
echo ">>> Configurando PAM e mkhomedir..."
pam-auth-update --enable mkhomedir --force 2>/dev/null || true

# Garantir criacao automatica do home
if [ -f /etc/pam.d/common-session ]; then
    grep -q "pam_mkhomedir" /etc/pam.d/common-session || \
        echo "session required pam_mkhomedir.so skel=/etc/skel umask=0022" >> /etc/pam.d/common-session
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
    exit 1
}

echo ">>> Sudo configurado"

# ============================================================
# Reiniciar servicos conforme metodo utilizado
# ============================================================
echo ">>> Reiniciando servicos..."
if [ "$JOIN_METHOD" = "sssd" ]; then
    systemctl restart samba 2>/dev/null || true
    systemctl restart sssd
    systemctl enable sssd
elif [ "$JOIN_METHOD" = "winbind" ]; then
    systemctl restart smbd nmbd winbind
    systemctl enable smbd nmbd winbind
fi

echo ">>> [04] Ingresso no AD concluido! (Metodo: $JOIN_METHOD)"
echo "============================================================"
