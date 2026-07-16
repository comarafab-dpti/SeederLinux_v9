# SeederLinux Lite - Documentação Completa

## Visão Geral

O **SeederLinux Lite** é um sistema centralizado de gerenciamento de scripts de provisionamento para estações Linux, voltado a ambientes militares com múltiplas Organizações (OMs). Permite configurar, personalizar e distribuir scripts de forma dinâmica, com suporte a execução offline via bundles autônomos.

### Objetivos

- **Multi-OM:** Cada organização tem seu próprio conjunto de variáveis, branding e scripts.
- **Substituição Dinâmica:** Placeholders `{{VARIAVEL}}` nos scripts são preenchidos automaticamente.
- **Offline-First:** Bundles `.sh` autônomos executáveis sem conexão de rede.
- **Inventário:** Estações fazem check-in periódico e recebem atualizações automaticamente.
- **Auditoria:** Log completo de todas as ações no sistema.

---

## Arquitetura

```
┌────────────────────────────────────────────────────┐
│                 SERVIDOR CENTRAL                   │
│  ┌──────────────┐  ┌──────────┐  ┌─────────────┐  │
│  │ Frontend     │  │ API REST │  │ Motor Bundle│  │
│  │ (HTML/CSS/JS)│  │ (PHP 8+) │  │ (PHP)       │  │
│  └──────────────┘  └──────────┘  └─────────────┘  │
│                         │                          │
│                 ┌────────────────┐                 │
│                 │  PostgreSQL 14+│                 │
│                 └────────────────┘                 │
└────────────────────────────────────────────────────┘
              HTTP/HTTPS
┌────────────────────────────────────────────────────┐
│               ESTAÇÃO LINUX                        │
│  agent.py  →  check-in  →  download bundle  →  exec│
└────────────────────────────────────────────────────┘
```

---

## Tecnologias

| Componente     | Tecnologia               |
|----------------|--------------------------|
| Backend        | PHP 8+ (PDO)             |
| Banco de Dados | PostgreSQL 14+           |
| Frontend       | HTML5 + CSS custom + JS  |
| Tipografia     | Inter + JetBrains Mono   |
| Agente         | Python 3 (stdlib only)   |
| Scripts        | Bash Shell               |

---

## Instalação

### Pré-requisitos

- Debian 12/13 ou Ubuntu 22.04+
- Acesso root/sudo
- Apache2, PHP 8+, PostgreSQL 14+

### Instalação Automatizada

```bash
cd /opt/seederlinux-lite
sudo chmod +x install/install.sh
sudo ./install/install.sh
```

O instalador realiza:
1. Configura repositórios APT (Debian 13 ready)
2. Instala Apache2, PHP 8+ com extensões, PostgreSQL
3. Cria banco de dados e usuário
4. Aplica o schema completo (`install/schema_completo.sql`)
5. Configura VirtualHost com SSL
6. Copia arquivos e configura permissões

### Instalação Manual

```bash
# Banco de dados
sudo -u postgres psql
CREATE DATABASE seederlinux;
CREATE USER seeder WITH PASSWORD 'seeder123';
GRANT ALL PRIVILEGES ON DATABASE seederlinux TO seeder;
GRANT ALL ON SCHEMA public TO seeder;
\q

# Schema
PGPASSWORD=seeder123 psql -h localhost -U seeder -d seederlinux \
    -f install/schema_completo.sql

# .env
cat > .env << EOF
DB_HOST=localhost
DB_PORT=5432
DB_NAME=seederlinux
DB_USER=seeder
DB_PASS=seeder123
EOF
```

---

## Estrutura de Arquivos

```
/
├── admin.html              # Painel administrativo
├── index.html              # Página pública
├── login.html              # Tela de login
├── api/
│   └── index.php           # API REST (router + handlers)
├── assets/
│   ├── css/style.css       # Estilos
│   ├── js/app.js           # Utilitários globais (API, Toast, Utils)
│   ├── js/admin.js         # Lógica do painel admin
│   ├── wallpapers/         # Wallpapers por OM
│   └── logos/              # Logos por OM
├── downloads/
│   └── agent.py            # Agente Python de provisionamento
├── install/
│   ├── install.sh          # Instalador automático
│   ├── agent_install.sh    # Instalador do agente na estação
│   ├── schema_completo.sql # Schema completo do banco
│   └── ...                 # Scripts auxiliares
├── lib/
│   ├── config.php          # Configuração (DB, env)
│   ├── db.php              # Classe Database (PDO)
│   └── functions.php       # Helpers, auth, audit
└── .env                    # Credenciais de ambiente
```

---

## Banco de Dados

### Tabelas Principais

| Tabela                  | Descrição                                          |
|-------------------------|----------------------------------------------------|
| `users`                 | Usuários do painel (admin_gap, operador_om, auditor)|
| `user_tokens`           | Tokens Bearer emitidos no login (TTL 24h)          |
| `organizations`         | Organizações Militares (OMs)                       |
| `variable_definitions`  | Catálogo global de variáveis (47 variáveis)        |
| `organization_variables`| Valores de variáveis por OM                        |
| `scripts`               | Scripts de provisionamento (Core + Custom)         |
| `deploy_bundles`        | Bundles gerados (armazenamento completo)           |
| `stations`              | Estações registradas (inventário)                  |
| `audit_events`          | Log de auditoria estruturado (JSONB)               |
| `activity_log`          | Log legado de atividades                           |
| `system_settings`       | Configurações globais do sistema                   |

### Controle de Versão (serial_config)

Cada OM possui um campo `serial_config` que é incrementado toda vez que sua configuração muda (variáveis salvas, bundle gerado). As estações comparam seu `configuration_serial` local com o serial atual da OM para detectar atualizações.

---

## API REST

Base URL: `/api/?action=<endpoint>`

### Autenticação

| Endpoint   | Método | Descrição                          |
|------------|--------|------------------------------------|
| `login`    | POST   | Login com username/senha           |
| `logout`   | POST   | Encerra sessão                     |
| `session`  | GET    | Verifica sessão ativa              |

**Autenticação suportada:** Sessão PHP + Bearer Token (header `Authorization: Bearer <token>`).

### Organizações

| Endpoint        | Método | Parâmetros        | Descrição              |
|-----------------|--------|-------------------|------------------------|
| `organizations` | GET    | —                 | Lista todas as OMs     |
| `organizations` | POST   | body JSON         | Cria nova OM           |
| `organization`  | GET    | `id`              | Detalhe de uma OM      |
| `organization`  | PUT    | `id`, body JSON   | Atualiza OM            |
| `organization`  | DELETE | `id`              | Desativa OM            |

### Variáveis

| Endpoint          | Método | Parâmetros       | Descrição                    |
|-------------------|--------|------------------|------------------------------|
| `variables`       | GET    | `id` (org_id)    | Variáveis de uma OM          |
| `variables-update`| POST   | body JSON        | Salva valores em lote        |
| `variable-add`    | POST   | body JSON        | Adiciona nova variável global|

### Scripts

| Endpoint  | Método | Parâmetros      | Descrição             |
|-----------|--------|-----------------|-----------------------|
| `scripts` | GET    | `org_id`        | Lista scripts         |
| `script`  | GET    | `id`            | Conteúdo do script    |
| `script`  | POST   | body JSON       | Cria script           |
| `script`  | PUT    | `id`, body JSON | Atualiza script       |
| `script`  | DELETE | `id`            | Desativa script       |

### Bundles

| Endpoint          | Método | Descrição                    |
|-------------------|--------|------------------------------|
| `generate-bundle` | POST   | Gera bundle para uma OM      |
| `bundle-by-id`    | GET    | Download de bundle por ID    |

### Estações

| Endpoint   | Método | Parâmetros | Descrição                              |
|------------|--------|------------|----------------------------------------|
| `stations` | GET    | `org_id`   | Lista estações                         |
| `checkin`  | POST   | body JSON  | Check-in da estação (agente)           |

### Dashboard

| Endpoint    | Método | Parâmetros | Descrição                              |
|-------------|--------|------------|----------------------------------------|
| `dashboard` | GET    | —          | Estatísticas globais                   |
| `dashboard` | GET    | `org_id`   | Estatísticas individuais de uma OM     |

### Outros

| Endpoint           | Método | Descrição                   |
|--------------------|--------|-----------------------------|
| `users`            | GET    | Lista usuários              |
| `users`            | POST   | Cria usuário                |
| `user`             | PUT    | Atualiza usuário            |
| `user`             | DELETE | Desativa usuário            |
| `audit`            | GET    | Log de auditoria            |
| `upload-wallpaper` | POST   | Upload de wallpaper por OM  |
| `upload-logo`      | POST   | Upload de logo por OM       |
| `wallpapers`       | GET    | Lista wallpapers de uma OM  |
| `logos`            | GET    | Lista logos de uma OM       |

---

## Sistema de Permissões (RBAC)

| Role          | Acesso                                              |
|---------------|-----------------------------------------------------|
| `admin_gap`   | Acesso total: OMs, scripts, usuários, bundles       |
| `operador_om` | Acesso apenas à própria OM (variáveis, bundle)      |
| `auditor`     | Leitura de usuários e log de auditoria              |

---

## Painel Administrativo

### Acesso

- URL: `https://servidor/admin.html`
- Login: `https://servidor/login.html`
- Credenciais padrão: `admin` / `admin123` (**alterar em produção!**)

### Funcionalidades

#### Dashboard Global
Exibe totais globais: organizações, scripts, variáveis, bundles do mês, estações online e desatualizadas.

#### Dashboard por OM
Ao clicar em uma OM no sidebar, a visão padrão é o **overview da OM**:
- Cards: Scripts disponíveis, Variáveis configuradas, Bundles do mês, Estações online, Estações desatualizadas
- Tabela: Últimas estações com check-in
- Lista: Scripts Core e Custom da OM

Botão **"Editar Config."** abre as abas de configuração:
- **Variáveis:** Edição com filtro por categoria, busca, upload de imagens
- **Scripts:** Lista Core e Custom com seleção para bundle
- **Gerar Bundle:** Gera e baixa o bundle completo

#### Galeria de Imagens
Nas variáveis `WALLPAPER_URL` e `LOGO_URL`, é possível fazer upload de imagens que são armazenadas no servidor e exibidas em galeria clicável.

---

## Catálogo de Variáveis

O sistema possui 47+ variáveis organizadas em categorias:

| Categoria       | Variáveis principais                                              |
|-----------------|-------------------------------------------------------------------|
| **Domínio**     | DOMINIO, DC_IP, DOMINIO_NETBIOS, DNS_PRIMARIO, DNS_SECUNDARIO, NTP_SERVER, OU_PADRAO, OFFLINE_AUTH_ENABLED |
| **Rede**        | BASE_URL, PRINT_SERVER, DNS_INTERNET                             |
| **Proxy**       | PROXY_HTTP, PROXY_PORTA, PROXY_URL                               |
| **Navegador**   | HOMEPAGE, PROXY_MODE, PAC_URL, NO_PROXY                          |
| **Branding**    | WALLPAPER_URL, LOGO_URL, OM_ACRONYM, OM_NAME, DISPLAY_NAME, THEME, CONKY_PROFILE |
| **Repositórios**| REPOSITORY_MODE, REPOSITORY_URL, REPOSITORY_FALLBACK            |
| **Inventário**  | OCS_SERVER, OCS_TAG, GLPI_SERVER, INVENTORY_ENABLED             |
| **Segurança**   | GRUPO_ADMIN_AD, GRUPO_ADMIN_LINUX, GRUPO_DASTI, GRUPO_ADMIN     |
| **Arquivos**    | SERVIDOR_ARQUIVOS, COMPARTILHAMENTOS, MOUNT_BASE                 |
| **Acesso Remoto**| REMOTE_METHOD, REMOTE_SERVER                                    |
| **Impressoras** | DEFAULT_PRINTER, PRINTERS                                        |
| **Certificados**| CERTIFICATE_BUNDLE, CERTIFICATE_AUTO_INSTALL                    |

---

## Scripts Core

### core_network.sh
- Configura variáveis de proxy no sistema (`/etc/environment`)
- Define página inicial do Firefox
- Configura servidor de impressão CUPS

### core_domain.sh
- Instala SSSD + realmd + Kerberos
- Ingresso da estação no Active Directory
- Configura SSSD com cache offline
- Configura `sudoers` para grupos AD
- Configura PAM para criação automática de home

### core_inventory.sh
- Instala e configura `ocsinventory-agent`
- Define servidor OCS e tag da OM
- Cria cron diário de inventário

### core_branding.sh
- Baixa wallpaper e logo da OM
- Configura LightDM e XFCE4
- Cria arquivo `/etc/seederlinux-identity`

---

## Agente Python (`agent.py`)

### Instalação

```bash
# Na estação Linux
sudo bash install/agent_install.sh
```

### Uso

```bash
# Primeiro run — vincula a estação à OM (obrigatório)
sudo seeder-agent --org COMARA

# Runs subsequentes — token já salvo
sudo seeder-agent

# Dry run (não executa)
sudo seeder-agent --org COMARA --dry-run --verbose

# Servidor personalizado
sudo seeder-agent --org COMARA --server https://seeder.minhaorg.intraer
```

### Argumentos

| Argumento       | Descrição                                               |
|-----------------|---------------------------------------------------------|
| `--org SIGLA`   | Sigla da OM (obrigatório no primeiro run)               |
| `--server URL`  | URL do servidor (sobrescreve `agent.conf`)              |
| `--dry-run`     | Simula sem fazer check-in nem executar bundle           |
| `--verbose, -v` | Saída detalhada                                         |
| `--version`     | Exibe versão do agente                                  |

### Fluxo de Operação

1. **Primeiro run:** Envia `organization_acronym` no payload. O servidor localiza a OM, registra a estação e retorna um `station_token` único.
2. **Token salvo** em `/etc/seeder/station_token` (modo 600).
3. **Runs seguintes:** Envia token no header `Authorization: Bearer` e no payload para lookup. Sem necessidade de `--org`.
4. Se `update_available=true`, baixa o bundle mais recente e executa com bash.
5. O bundle atualiza o `configuration_serial` local da estação.

### Arquivos do Agente

| Arquivo                        | Descrição                        |
|--------------------------------|----------------------------------|
| `/usr/local/bin/seeder-agent`  | Executável principal             |
| `/etc/seeder/agent.conf`       | URL do servidor                  |
| `/etc/seeder/station_token`    | Token único da estação (600)     |
| `/var/log/seeder/agent.log`    | Log de execuções                 |
| `/var/cache/seeder/bundle.sh`  | Último bundle baixado            |

### Cron Automático

Instalado em `/etc/cron.d/seeder-agent`:
```
*/15 * * * * /usr/local/bin/seeder-agent >> /var/log/seeder/agent.log 2>&1
```

---

## Geração de Bundles

O bundle é um arquivo `.sh` autônomo com:

1. **Cabeçalho:** Organização, data, serial, quantidade de scripts
2. **Variáveis:** Todas exportadas como variáveis de ambiente
3. **Scripts:** Conteúdo concatenado com placeholders substituídos

```bash
# Exemplo de bundle gerado
export DOMINIO='comara.intraer'
export DC_IP='10.108.64.51'
export PROXY_HTTP='10.108.88.4'
# ...

# --- Configuração de Rede (core_network.sh) ---
#!/bin/bash
# ... conteúdo com valores reais substituídos ...
```

Cada geração incrementa o `serial_config` da OM, sinalizando para as estações que há atualização disponível.

---

## Segurança

### Recomendações

1. **Altere a senha padrão** imediatamente após instalação
2. **Use HTTPS** em produção (certificado SSL)
3. **Firewall:** Libere apenas portas 80 e 443
4. **Tokens:** Expiram em 24h; sessões PHP têm timeout configurável

### Headers de Segurança (`.htaccess`)

```apache
Header always set X-Content-Type-Options "nosniff"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-XSS-Protection "1; mode=block"
```

---

## Troubleshooting

### Check-in falha com "Informe o acronimo da organizacao"
Estação nova sem token. Execute:
```bash
sudo seeder-agent --org <SIGLA>
```

### Check-in falha com "Organizacao nao encontrada: XYZ"
A sigla informada não existe no sistema. Verifique no painel admin qual é a sigla correta.

### Erro 500 no Apache
```bash
sudo tail -f /var/log/apache2/seederlinux-lite_error.log
```

### Erro de conexão com PostgreSQL
```bash
sudo systemctl status postgresql
PGPASSWORD=seeder123 psql -h localhost -U seeder -d seederlinux -c "SELECT 1;"
```

### Bundle não executa
```bash
sudo bash /var/cache/seeder/bundle.sh
# Verificar saída de erro
```

---

## Backup

```bash
# Backup do banco
pg_dump -U seeder seederlinux > backup_$(date +%Y%m%d_%H%M%S).sql

# Restauração
psql -U seeder seederlinux < backup_YYYYMMDD_HHMMSS.sql
```

---

**SeederLinux Lite v1.1.0**
Sistema de Gerenciamento Centralizado de Provisionamento Linux
