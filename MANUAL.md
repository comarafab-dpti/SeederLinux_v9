# SeederLinux Lite - Manual de Procedimentos

**Versão:** 1.0  
**Data:** Julho 2026  
**Sistema:** SeederLinux Lite (PHP + PostgreSQL + Agente Python)

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Arquitetura do Sistema](#2-arquitetura-do-sistema)
3. [Scripts Core](#3-scripts-core)
4. [Ordem de Execução no Bundle](#4-ordem-de-execução-no-bundle)
5. [Fluxo Completo de Provisionamento](#5-fluxo-completo-de-provisionamento)
6. [Detecção de Ambiente Gráfico](#6-detecção-de-ambiente-gráfico)
7. [Logon e Logoff (kixtart/kixtop)](#7-logon-e-logoff-kixtartkixtop)
8. [Catálogo de Variáveis (Placeholders)](#8-catálogo-de-variáveis-placeholders)
9. [Estrutura de Diretórios](#9-estrutura-de-diretórios)
10. [Procedimento de Instalação](#10-procedimento-de-instalação)

---

## 1. Visão Geral

O **SeederLinux Lite** é um sistema de provisionamento automatizado de estações Linux que substitui o antigo projeto SoftwareLivre. Ele gera **bundles** personalizados de scripts shell que configuram uma estação Linux do zero, ingressando-a no Active Directory da OM (Organização Militar) e aplicando todas as personalizações necessárias.

### Principais diferenças do SoftwareLivre para o SeederLinux

| Aspecto | SoftwareLivre | SeederLinux Lite |
|---------|--------------|-----------------|
| Valores fixos | IPs, domínios e siglas hardcoded | Placeholders `{{VARIAVEL}}` substituídos dinamicamente |
| Estrutura | Scripts monolíticos | Scripts Core modulares com ordem de execução |
| Configuração | Edição manual de scripts | Painel administrativo web (PHP) |
| Armazenamento | Arquivos soltos | Banco de dados PostgreSQL |
| Geração | Manual | Bundle automático via sistema |
| Multi-OM | Uma cópia por OM | Uma instância, múltiplas OMs |

---

## 2. Arquitetura do Sistema

```
┌─────────────────────────────────────────────────────────┐
│                    PAINEL ADMIN (PHP)                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │   OMs    │  │ Scripts  │  │ Variáveis│  │  Bundles │  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
└─────────────────────────┬─────────────────────────────────┘
                          │
                    ┌─────┴─────┐
                    │ PostgreSQL │
                    └─────┬─────┘
                          │
              ┌───────────┴───────────┐
              │   AGENTE PYTHON (CLI)   │
              │  - Gera bundle          │
              │  - Substitui variáveis  │
              │  - Concatena scripts    │
              └───────────┬─────────────┘
                          │
                    ┌─────┴─────┐
                    │  BUNDLE   │
                    │  .sh      │
                    └─────┬─────┘
                          │
              ┌───────────┴───────────┐
              │   ESTAÇÃO LINUX       │
              │  (Debian 13 Trixie)   │
              └───────────────────────┘
```

### Componentes

- **Painel Admin (PHP):** Interface web para gerenciar OMs, scripts, variáveis e gerar bundles.
- **PostgreSQL:** Banco de dados que armazena scripts, variáveis, OMs e configurações.
- **Agente Python:** CLI que gera o bundle final, substituindo placeholders `{{VARIAVEL}}` pelos valores da OM selecionada.
- **Bundle (.sh):** Script shell único executado na estação Linux alvo.

---

## 3. Scripts Core

Os scripts Core são os scripts base do provisionamento. Eles contêm placeholders `{{VARIAVEL}}` que são substituídos pelo sistema na geração do bundle. Todos os scripts Core têm `is_core = true` na tabela `scripts`.

### 3.1. Lista Completa de Scripts Core

| # | Script | Função | Origem SoftwareLivre |
|---|--------|--------|----------------------|
| 01 | `core_repositories.sh` | Configura `sources.list` do APT (Debian 13 Trixie) conforme modo: PUBLIC, MIRROR, HYBRID ou CUSTOM | `ingreca_mint_v2.sh` |
| 02 | `core_dns.sh` | Configura DNS temporário, `/etc/resolv.conf`, `/etc/hosts` e sincroniza NTP | `ingreca_mint_v2.sh` |
| 03 | `core_packages.sh` | Instala pacotes essenciais: rede, autenticação, ambiente gráfico e utilitários | `ingreca_mint_v2.sh` |
| 04 | `core_domain.sh` | Ingresso no AD: Kerberos, Samba, SSSD, PAM, NSS, sudo, mkhomedir | `ingreca_mint_v2.sh` |
| 05 | `core_proxy.sh` | Proxy do sistema: `/etc/environment`, `apt.conf.d`, variáveis de ambiente | `ingreca_mint_v2.sh` |
| 06 | `core_browser.sh` | Políticas corporativas para Firefox ESR, Chrome e Chromium (JSON policies) | `personalizacao_v2.sh` |
| 07 | `core_inventory.sh` | OCS Inventory Agent: instalação, configuração e cron | `ingreca_mint_v2.sh` |
| 08 | `core_printers.sh` | CUPS e impressoras via servidor de impressão remoto | `instalar_impressoras_comara_v2.sh` |
| 09 | `core_vnc.sh` | x11vnc: instalação, senha, serviço systemd | `personalizacao_v2.sh` (habilitavnc.sh) |
| 10 | `core_conky.sh` | Conky: configuração, perfil personalizado, autostart por DE | `personalizacao_v2.sh` (configura-conky.sh) |
| 11 | `core_apps.sh` | OnlyOffice, Google Chrome, Firefox ESR | `ingreca_mint_v2.sh` + `personalizacao_v2.sh` |
| 12 | `core_legados.sh` | Java 8 (OpenJDK), Firefox 52.7 ESR para sistemas legados | `instala_sistemas_legados_v2.sh` |
| 13 | `core_branding.sh` | Wallpaper, logo, tema GTK, greeter — varia por DE | `personalizacao_v2.sh` |
| 14a | `core_session_lightdm.sh` | LightDM: logon/logoff (MATE, Cinnamon, XFCE, LXDE) | `personalizacao_v2.sh` |
| 14b | `core_session_gdm3.sh` | GDM3: logon/logoff (GNOME) | `personalizacao_v2.sh` |
| 14c | `core_session_sddm.sh` | SDDM: logon/logoff (KDE) | `personalizacao_v2.sh` |
| 15 | `core_logon.sh` | Logon do usuário: mapeamento de compartilhamentos, atalhos, personalizacoes | `kixtart_v2.sh` |
| 16 | `core_logoff.sh` | Logoff: limpeza de temporários, desmontagem, remoção de atalhos | `kixtop_v2.sh` |

### 3.2. Descrição Detalhada

#### 01 - core_repositories.sh
Configura o `/etc/apt/sources.list` do Debian 13 (Trixie) com suporte a quatro modos:
- **PUBLIC:** Repositórios oficiais do Debian (deb.debian.org)
- **MIRROR:** Espelho local (URL fornecida)
- **HYBRID:** Espelho local com fallback para repositórios públicos
- **CUSTOM:** URL totalmente personalizada

Realiza backup do `sources.list` original e executa `apt-get update`.

#### 02 - core_dns.sh
Configura resolução de nomes para permitir o provisionamento:
- DNS temporário em `/etc/resolv.conf` (DNS de internet ou DNS da OM)
- `/etc/hosts` com hostname FQDN e todos os controladores de domínio
- Sincronização NTP com o servidor definido (suporta chrony e ntpd)

#### 03 - core_packages.sh
Instala todos os pacotes necessários em três categorias:
- **Pacotes base:** wget, curl, vim, net-tools, dnsutils, openssh, cifs-utils, etc.
- **Pacotes de autenticação:** krb5-user, samba, sssd, adcli, realmd, etc.
- **Pacotes do ambiente gráfico:** Conforme `{{DESKTOP_ENV}}` (cinnamon, mate, gnome, xfce, kde, lxde)
- **Pacotes complementares:** cups, x11vnc, conky, firefox-esr, firmware, etc.

#### 04 - core_domain.sh
Ingresso completo no Active Directory:
- Configura `/etc/krb5.conf` com realm e KDC
- Configura `/etc/samba/smb.conf` com idmap rid
- Obtém ticket Kerberos e ingressa no domínio via `net ads join` na OU definida
- Configura `/etc/sssd/sssd.conf` com cache offline opcional
- Configura `/etc/nsswitch.conf` para SSS
- Habilita `pam_mkhomedir` para criação automática de homes
- Configura sudo para grupos do AD (`/etc/sudoers.d/seederlinux-domain`)

#### 05 - core_proxy.sh
Configura proxy em três modos:
- **NONE:** Remove configurações de proxy
- **MANUAL:** Proxy HTTP/HTTPS fixo em `/etc/environment` e `apt.conf.d`
- **PAC:** URL de arquivo PAC para configuração automática

#### 06 - core_browser.sh
Aplica políticas corporativas aos navegadores:
- **Firefox ESR:** `policies.json` com homepage, telemetria desativada, proxy, certificados. Autoconfig (`.cfg`) para proxy PAC ou manual.
- **Google Chrome:** JSON de políticas em `/etc/opt/chrome/policies/managed/`
- **Chromium:** Mesmas políticas do Chrome em `/etc/chromium/policies/managed/`

#### 07 - core_inventory.sh
Instala e configura o agente OCS Inventory:
- Instala `ocsinventory-agent` e `dmidecode`
- Configura servidor e tag da OM
- Cria cron job para coleta periódica (a cada 4 horas)
- Suporta integração com GLPI (se `{{GLPI_SERVER}}` definido)
- Executa coleta inicial

#### 08 - core_printers.sh
Configura CUPS e impressoras:
- Instala CUPS e system-config-printer
- Configura `cupsd.conf` com administração remota
- Configura `client.conf` apontando para o servidor de impressão
- Instala cada impressora listada em `{{PRINTERS}}` via `lpadmin`
- Define impressora padrão (`{{DEFAULT_PRINTER}}`)

#### 09 - core_vnc.sh
Configura x11vnc para suporte remoto:
- Instala x11vnc
- Configura senha (fornecida ou aleatória)
- Cria serviço systemd (`x11vnc.service`)
- Determina display e auth file conforme o display manager

#### 10 - core_conky.sh
Configura Conky para monitoração do sistema:
- Instala conky e conky-all
- Gera configuração com perfil personalizado ou padrão
- Cria script de inicialização (`/usr/local/bin/seederlinux-conky`)
- Configura autostart conforme o DE (XDG autostart ou KDE)

#### 11 - core_apps.sh
Instala aplicativos adicionais:
- Firefox ESR (via APT)
- Google Chrome (download direto do .deb oficial)
- OnlyOffice Desktop Editors (via repositório ou download direto)

#### 12 - core_legados.sh
Instala sistemas legados para compatibilidade:
- Java 8 (OpenJDK 8 via repositório ou Adoptium/Temurin)
- Firefox 52.7 ESR (download do repositório interno ou Mozilla)
- Configura plugin Java (libnpjp2.so) para Firefox legado
- Cria entrada de desktop para Firefox legado

#### 13 - core_branding.sh
Aplica identidade visual da OM:
- Baixa e instala wallpaper, wallpaper de login, logo e greeter
- Configura tema GTK global
- Aplica configurações específicas por DE (gsettings, dconf, xfconf, kdeglobals, pcmanfm)
- Configura greeter do display manager com wallpaper e logo de login

#### 14a - core_session_lightdm.sh
Configura LightDM para MATE, Cinnamon, XFCE e LXDE:
- Instala LightDM e greeter GTK
- Configura `lightdm.conf` com scripts de logon/logoff
- Configura greeter com tema, wallpaper e logo
- Desabilita outros display managers

#### 14b - core_session_gdm3.sh
Configura GDM3 para GNOME:
- Instala GDM3
- Configura `daemon.conf` (Wayland desativado)
- Cria scripts PreSession (logon) e PostSession (logoff)
- Desabilita outros display managers

#### 14c - core_session_sddm.sh
Configura SDDM para KDE:
- Instala SDDM e tema Breeze
- Configura `sddm.conf.d`
- Cria scripts Xsetup (logon) e Xstop (logoff)
- Desabilita outros display managers

#### 15 - core_logon.sh (kixtart_v2)
Executado no login do usuário:
- Cria diretórios base do usuário (Desktop, Downloads, Documents)
- Mapeia compartilhamentos de rede via CIFS
- Cria atalhos no desktop para compartilhamentos e portal
- Configura impressora padrão
- Inicia Conky (se aplicável)
- Corrige permissões do home

#### 16 - core_logoff.sh (kixtop_v2)
Executado no logoff do usuário:
- Desmonta compartilhamentos de rede
- Limpa cache de navegadores, arquivos temporários e thumbnails
- Remove atalhos temporários do desktop
- Salva log de sessão (com rotação de 7 dias)
- Encerra processos do usuário (Conky, x11vnc)

---

## 4. Ordem de Execução no Bundle

Os scripts são concatenados no bundle nesta ordem:

```
┌─────────────────────────────────────────────────────────┐
│  ORDEM  │  SCRIPT                    │  OBRIGATÓRIO     │
├─────────┼────────────────────────────┼──────────────────┤
│   01    │  core_repositories.sh      │  Sim             │
│   02    │  core_dns.sh               │  Sim             │
│   03    │  core_packages.sh          │  Sim             │
│   04    │  core_domain.sh            │  Sim             │
│   05    │  core_proxy.sh             │  Sim             │
│   06    │  core_browser.sh           │  Sim             │
│   07    │  core_inventory.sh         │  Se habilitado  │
│   08    │  core_printers.sh          │  Se houver serv │
│   09    │  core_vnc.sh               │  Se habilitado  │
│   10    │  core_conky.sh             │  Sim             │
│   11    │  core_apps.sh              │  Se habilitado  │
│   12    │  core_legados.sh           │  Se habilitado  │
│   13    │  core_branding.sh          │  Sim             │
│  14*    │  core_session_*.sh         │  UM conforme DM  │
│   15    │  core_logon.sh             │  Sim             │
│   16    │  core_logoff.sh            │  Sim             │
└─────────────────────────────────────────────────────────┘
```

**14\*** - Apenas UM script de sessão é incluído no bundle, conforme `{{DISPLAY_MANAGER}}`:
- `lightdm` → `core_session_lightdm.sh`
- `gdm3` → `core_session_gdm3.sh`
- `sddm` → `core_session_sddm.sh`

Scripts condicionais (07, 08, 09, 11, 12) verificam internamente se devem executar com base nas variáveis de controle (`{{INVENTORY_ENABLED}}`, `{{VNC_ENABLED}}`, `{{INSTALL_APPS}}`, `{{INSTALL_LEGADOS}}`, etc.). Mesmo incluídos no bundle, eles saem precocemente com `exit 0` se a funcionalidade estiver desativada.

---

## 5. Fluxo Completo de Provisionamento

```
SoftwareLivre (legado)                    SeederLinux Lite
┌──────────────────────┐                 ┌──────────────────────────┐
│ ingreca_mint_v2.sh   │ ── migração ──> │ core_repositories.sh     │ 01
│  (sources.list)      │                 │ core_dns.sh              │ 02
│                      │                 │ core_packages.sh        │ 03
│  (DNS, NTP, hosts)   │ ── migração ──> │ core_domain.sh           │ 04
│  (Kerberos, SSSD)    │                 │ core_proxy.sh            │ 05
│  (proxy)             │                 │ core_browser.sh         │ 06
│  (OCS)               │ ── migração ──> │ core_inventory.sh        │ 07
│                      │                 │ core_printers.sh         │ 08
│ personalizacao_v2.sh │ ── migração ──> │ core_vnc.sh              │ 09
│  (Firefox, Chrome)   │                 │ core_conky.sh            │ 10
│  (VNC, Conky)        │                 │ core_apps.sh             │ 11
│  (Wallpaper, tema)   │                 │ core_legados.sh          │ 12
│  (LightDM)           │                 │ core_branding.sh         │ 13
│                      │                 │ core_session_*.sh        │ 14
│ instalar_impressoras │ ── migração ──> │ core_printers.sh         │ 08
│ instala_legados      │ ── migração ──> │ core_legados.sh          │ 12
│ kixtart_v2.sh        │ ── migração ──> │ core_logon.sh            │ 15
│ kixtop_v2.sh         │ ── migração ──> │ core_logoff.sh           │ 16
└──────────────────────┘                 └──────────────────────────┘
```

### Etapas do fluxo

1. **Administrador** acessa o painel web e seleciona/cria a OM
2. **Administrador** define os valores das variáveis para a OM (IPs, domínio, proxy, etc.)
3. **Administrador** gera o bundle selecionando a OM e o ambiente gráfico
4. **Agente Python** lê os scripts Core do banco, substitui `{{VARIAVEL}}` pelos valores da OM, concatena na ordem correta e gera um único `.sh`
5. **Administrador** executa o bundle na estação Linux alvo (como root)
6. O bundle executa os scripts sequencialmente (01 a 16), provisionando a estação completa

---

## 6. Detecção de Ambiente Gráfico

O sistema suporta seis ambientes gráficos (Desktop Environments) e três display managers:

### Ambientes Gráficos Suportados

| DE | Display Manager Padrão | Scripts de Sessão |
|----|----------------------|-------------------|
| Cinnamon | LightDM | `core_session_lightdm.sh` |
| MATE | LightDM | `core_session_lightdm.sh` |
| GNOME | GDM3 | `core_session_gdm3.sh` |
| XFCE | LightDM | `core_session_lightdm.sh` |
| KDE | SDDM | `core_session_sddm.sh` |
| LXDE | LightDM | `core_session_lightdm.sh` |

### Variáveis de Ambiente Gráfico

- `{{DESKTOP_ENV}}` — Define qual ambiente gráfico instalar (cinnamon, mate, gnome, xfce, kde, lxde)
- `{{DISPLAY_MANAGER}}` — Define qual display manager configurar (lightdm, gdm3, sddm)

### Seleção de Script de Sessão

O agente Python seleciona **apenas um** script de sessão (14a, 14b ou 14c) com base em `{{DISPLAY_MANAGER}}`:

```python
# Lógica do agente Python (exemplo)
display_manager = variables.get("DISPLAY_MANAGER", "lightdm")

if display_manager == "lightdm":
    session_script = "core_session_lightdm.sh"
elif display_manager == "gdm3":
    session_script = "core_session_gdm3.sh"
elif display_manager == "sddm":
    session_script = "core_session_sddm.sh"
else:
    session_script = "core_session_lightdm.sh"  # fallback
```

Cada script de sessão também verifica internamente com `case "$DISPLAY_MANAGER"` se deve prosseguir, garantindo segurança mesmo se o script errado for incluído.

### Detecção Automática (se necessário)

Se a detecção automática for necessária na estação (ex: bundle genérico), o seguinte trecho pode ser usado:

```bash
# Detectar DE instalado
if command -v cinnamon-session &> /dev/null; then DESKTOP_ENV="cinnamon"
elif command -v mate-session &> /dev/null; then DESKTOP_ENV="mate"
elif command -v gnome-session &> /dev/null; then DESKTOP_ENV="gnome"
elif command -v startxfce4 &> /dev/null; then DESKTOP_ENV="xfce"
elif command -v startkde &> /dev/null; then DESKTOP_ENV="kde"
elif command -v startlxde &> /dev/null; then DESKTOP_ENV="lxde"
fi

# Detectar DM ativo
if systemctl is-active --quiet lightdm; then DISPLAY_MANAGER="lightdm"
elif systemctl is-active --quiet gdm3; then DISPLAY_MANAGER="gdm3"
elif systemctl is-active --quiet sddm; then DISPLAY_MANAGER="sddm"
fi
```

---

## 7. Logon e Logoff (kixtart/kixtop)

### Origem

No projeto SoftwareLivre, os scripts `kixtart_v2.sh` e `kixtop_v2.sh` eram executados respectivamente no login e logoff de cada usuário. No SeederLinux Lite, essa funcionalidade foi migrada para `core_logon.sh` e `core_logoff.sh`.

### Instalação como Scripts de Sistema

Os scripts `core_logon.sh` e `core_logoff.sh` são instalados como comandos de sistema:

```
/usr/local/bin/seederlinux-logon   →  core_logon.sh
/usr/local/bin/seederlinux-logoff  →  core_logoff.sh
```

### Integração com Display Managers

Cada display manager chama os scripts em momentos diferentes:

| Display Manager | Logon (seederlinux-logon) | Logoff (seederlinux-logoff) |
|----------------|--------------------------|----------------------------|
| LightDM | `session-setup-script` | `session-cleanup-script` |
| GDM3 | `PreSession/Default` | `PostSession/Default` |
| SDDM | `Xsetup` | `Xstop` |

### core_logon.sh (kixtart_v2) — O que faz no login

1. Cria diretórios base do usuário (Desktop, Downloads, Documents)
2. Mapeia compartilhamentos de rede CIFS (`{{COMPARTILHAMENTOS}}` de `{{SERVIDOR_ARQUIVOS}}`)
3. Cria atalhos no desktop para compartilhamentos e portal (`{{HOMEPAGE}}`)
4. Configura impressora padrão (`{{DEFAULT_PRINTER}}`)
5. Inicia Conky (se aplicável ao DE)
6. Corrige permissões do home

### core_logoff.sh (kixtop_v2) — O que faz no logoff

1. Desmonta compartilhamentos de rede
2. Limpa cache de navegadores (Firefox, Chrome, Chromium)
3. Limpa lixeira e arquivos temporários
4. Remove atalhos temporários do desktop
5. Salva log de sessão (com rotação de 7 dias)
6. Encerra processos do usuário (Conky, x11vnc)

---

## 8. Catálogo de Variáveis (Placeholders)

Todos os scripts Core usam **exclusivamente** as variáveis abaixo. O sistema as possui no banco de dados e as substitui na geração do bundle.

### Domínio e Autenticação

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `{{DOMINIO}}` | Domínio AD completo | `comara.intraer` |
| `{{DOMINIO_NETBIOS}}` | Nome NetBIOS | `COMARA` |
| `{{DC_IP}}` | IP do Controlador de Domínio principal | `10.10.10.10` |
| `{{DC_IP_LIST}}` | Lista de IPs de todos os DCs (separados por espaço) | `10.10.10.10 10.10.10.11` |
| `{{DNS_PRIMARIO}}` | IP do DNS primário | `10.10.10.10` |
| `{{DNS_SECUNDARIO}}` | IP do DNS secundário | `10.10.10.11` |
| `{{NTP_SERVER}}` | Servidor NTP | `10.10.10.10` |
| `{{OU_PADRAO}}` | OU padrão no AD | `OU=Estacoes,DC=comara,DC=intraer` |
| `{{GRUPO_ADMIN}}` | Grupo administrador do domínio | `Domain Admins` |
| `{{OFFLINE_AUTH_ENABLED}}` | Habilitar cache offline | `true` |
| `{{OFFLINE_AUTH_DAYS}}` | Dias de cache offline | `3` |

### Rede e Proxy

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `{{PROXY_HTTP}}` | IP do proxy HTTP | `10.10.10.5` |
| `{{PROXY_PORTA}}` | Porta do proxy | `8080` |
| `{{PROXY_URL}}` | URL completa do proxy | `http://10.10.10.5:8080` |
| `{{PROXY_MODE}}` | Modo: NONE, MANUAL, PAC | `MANUAL` |
| `{{PAC_URL}}` | URL do arquivo PAC | `http://proxy.intraer/proxy.pac` |
| `{{NO_PROXY}}` | Exceções de proxy | `localhost,127.0.0.1,.intraer` |
| `{{DNS_INTERNET}}` | DNS para internet (fallback) | `8.8.8.8` |

### URLs e Servidores

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `{{BASE_URL}}` | URL base do repositório de scripts | `https://seederlinux.intraer/scripts` |
| `{{HOMEPAGE}}` | Página inicial do portal | `https://portal.intraer` |
| `{{OCS_SERVER}}` | Servidor OCS Inventory | `ocs.intraer` |
| `{{OCS_TAG}}` | Tag OCS da organização | `COMARA` |
| `{{PRINT_SERVER}}` | Servidor de impressão | `printsrv.intraer` |
| `{{SERVIDOR_ARQUIVOS}}` | Servidor de arquivos | `filesrv.intraer` |

### Identidade Visual

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `{{OM_ACRONYM}}` | Sigla da OM | `COMARA` |
| `{{OM_NAME}}` | Nome completo da OM | `Comando de Apoio Logistico` |
| `{{DISPLAY_NAME}}` | Nome de exibição | `COMARA-SE` |
| `{{WALLPAPER_URL}}` | URL do wallpaper | `https://seederlinux.intraer/img/wallpaper.jpg` |
| `{{WALLPAPER_LOGIN_URL}}` | URL do wallpaper da tela de login | `https://seederlinux.intraer/img/login.jpg` |
| `{{LOGO_URL}}` | URL do logo | `https://seederlinux.intraer/img/logo.png` |
| `{{GREETER_URL}}` | URL do greeter personalizado | `https://seederlinux.intraer/greeter.tar.gz` |
| `{{THEME}}` | Tema GTK | `Adwaita` |
| `{{CONKY_PROFILE}}` | Perfil do Conky | `padrao` |

### Ambiente Gráfico

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `{{DESKTOP_ENV}}` | Ambiente: cinnamon, mate, gnome, xfce, kde, lxde | `cinnamon` |
| `{{DISPLAY_MANAGER}}` | Gerenciador: lightdm, gdm3, sddm | `lightdm` |

### Aplicações e Funcionalidades

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `{{INSTALL_APPS}}` | Instalar OnlyOffice, Chrome? | `true` |
| `{{INSTALL_LEGADOS}}` | Instalar Java 8, Firefox 52? | `false` |
| `{{VNC_ENABLED}}` | Habilitar VNC? | `true` |
| `{{VNC_PASSWORD}}` | Senha do VNC | `secretpass` |

### Repositórios

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `{{REPOSITORY_MODE}}` | Modo: PUBLIC, MIRROR, HYBRID, CUSTOM | `MIRROR` |
| `{{REPOSITORY_URL}}` | URL do repositório espelho | `http://mirror.intraer/debian` |
| `{{REPOSITORY_FALLBACK}}` | URL de fallback | `http://deb.debian.org/debian` |

### Grupos e Segurança

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `{{GRUPO_ADMIN_AD}}` | Grupo admin no AD para sudo | `Domain Admins` |
| `{{GRUPO_ADMIN_LINUX}}` | Grupo local para sudo | `admin-linux` |
| `{{GRUPO_DASTI}}` | Grupo DASTI para sudo | `dasti` |

### Compartilhamentos e Impressoras

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `{{COMPARTILHAMENTOS}}` | Lista de compartilhamentos | `publico documentos sistemas` |
| `{{MOUNT_BASE}}` | Base de montagem | `/mnt` |
| `{{DEFAULT_PRINTER}}` | Impressora padrão | `HP-LaserJet-4001` |
| `{{PRINTERS}}` | Lista de impressoras | `HP-LaserJet-4001 HP-ColorJet-200` |

### Outros

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `{{REMOTE_METHOD}}` | Método de acesso remoto | `vnc` |
| `{{REMOTE_SERVER}}` | Servidor de acesso remoto | `remote.intraer` |
| `{{CERTIFICATE_BUNDLE}}` | URL do bundle de certificados | `https://seederlinux.intraer/certs/ca-bundle.crt` |
| `{{CERTIFICATE_AUTO_INSTALL}}` | Instalar certificados automaticamente | `true` |
| `{{INVENTORY_ENABLED}}` | Habilitar inventário | `true` |
| `{{GLPI_SERVER}}` | Servidor GLPI | `https://glpi.intraer` |

---

## 9. Estrutura de Diretórios

```
seederlinux-lite/
├── scripts/
│   └── core/
│       ├── core_repositories.sh      # 01 - Configurar sources.list (APT)
│       ├── core_dns.sh               # 02 - DNS, NTP e resolução de nomes
│       ├── core_packages.sh          # 03 - Instalar pacotes essenciais
│       ├── core_domain.sh            # 04 - Ingresso no AD (SSSD/Winbind)
│       ├── core_proxy.sh             # 05 - Proxy do sistema
│       ├── core_browser.sh           # 06 - Políticas Firefox/Chrome
│       ├── core_inventory.sh         # 07 - OCS Inventory Agent
│       ├── core_printers.sh          # 08 - CUPS e impressoras
│       ├── core_vnc.sh               # 09 - x11vnc
│       ├── core_conky.sh             # 10 - Conky
│       ├── core_apps.sh              # 11 - OnlyOffice, Chrome, Firefox ESR
│       ├── core_legados.sh           # 12 - Java 8, Firefox 52.7 (sistemas legados)
│       ├── core_branding.sh          # 13 - Wallpaper, logo, tema (varia por DE)
│       ├── core_session_lightdm.sh   # 14a - LightDM: logon/logoff (MATE, Cinnamon, XFCE, LXDE)
│       ├── core_session_gdm3.sh      # 14b - GDM3: logon/logoff (GNOME)
│       ├── core_session_sddm.sh      # 14c - SDDM: logon/logoff (KDE)
│       ├── core_logon.sh             # 15 - kixtart_v2.sh (executado no login do usuário)
│       └── core_logoff.sh            # 16 - kixtop_v2.sh (executado no logoff do usuário)
├── install/
│   ├── schema_completo.sql           # Schema do banco de dados
│   └── insert_core_scripts.sql       # INSERTs dos scripts Core
├── lib/
│   └── config.php                    # Configuração do sistema (NÃO ALTERAR)
├── MANUAL.md                          # Este manual
└── agente/                           # Agente Python (gerador de bundle)
```

---

## 10. Procedimento de Instalação

### 10.1. Preparar o Banco de Dados

```bash
# 1. Criar o schema do banco
psql -U postgres -f install/schema_completo.sql

# 2. Inserir os scripts Core
psql -U postgres -f install/insert_core_scripts.sql
```

### 10.2. Configurar Variáveis da OM

Após a instalação, acessar o painel administrativo web para:

1. Criar a OM (sigla, nome, domínio)
2. Definir os valores das variáveis (IPs, DNS, proxy, etc.)
3. Selecionar o ambiente gráfico e display manager
4. Gerar o bundle

### 10.3. Gerar e Executar o Bundle

```bash
# Gerar bundle via agente Python (exemplo)
python3 agente/generate_bundle.py --om COMARA --output bundle-comara.sh

# Executar na estação alvo (como root)
chmod +x bundle-comara.sh
sudo ./bundle-comara.sh
```

### 10.4. Verificação Pós-Provisionamento

```bash
# Verificar ingresso no domínio
net ads testjoin

# Verificar SSSD
systemctl status sssd

# Verificar DNS
cat /etc/resolv.conf

# Verificar proxy
cat /etc/environment

# Verificar NTP
timedatectl

# Verificar impressoras
lpstat -t

# Verificar OCS
ocsinventory-agent --server=<OCS_SERVER> --info
```

---

## Notas Finais

- **NÃO usar Supabase** — O SeederLinux Lite usa PostgreSQL diretamente.
- **NÃO alterar `lib/config.php`** — A configuração do sistema é fixa.
- **Manter compatibilidade** — Todos os scripts Core são compatíveis com o sistema existente.
- **Placeholders** — Todos os valores variáveis usam `{{VARIAVEL}}` e são substituídos na geração do bundle.
- **Comentários** — Os scripts mantêm comentários em português, seguindo o padrão do SoftwareLivre.
- **Tratamento de erros** — Todos os scripts usam `set -e` e verificam operações críticas.

---

*SeederLinux Lite — Documentação v1.0*
