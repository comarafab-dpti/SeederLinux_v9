# SeederLinux Lite - Documentação Completa

## Visão Geral

O SeederLinux Lite é uma solução minimalista e eficiente para o gerenciamento centralizado de scripts de provisionamento para estações Linux, com foco especial no Linux Lite. Ele permite que administradores configurem e distribuam scripts de forma dinâmica para múltiplas Organizações Militares (OMs), garantindo personalização, funcionalidade offline-first e simplicidade operacional.

### Objetivos Principais

- **Gerenciamento Centralizado:** Administrar scripts e variáveis de provisionamento a partir de um único painel web.
- **Personalização por OM:** Cada organização pode ter seu próprio conjunto de variáveis, branding e scripts.
- **Substituição Dinâmica de Variáveis:** Utilização de placeholders nos scripts que são automaticamente preenchidos.
- **Provisionamento Offline:** Geração de bundles autônomos executáveis sem conexão de rede.
- **Interface Moderna:** Painel administrativo intuitivo com Tailwind CSS.

## Arquitetura do Sistema

```
┌─────────────────────────────────────────────────────────────┐
│                    SERVIDOR CENTRAL                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Frontend     │  │ API REST     │  │ Motor Bundle │       │
│  │ (Tailwind)   │  │ (PHP 8)      │  │ (PHP)       │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│           │                │                │                │
│           └────────────────┼────────────────┘               │
│                            │                                 │
│                    ┌───────┴───────┐                        │
│                    │  PostgreSQL  │                        │
│                    └──────────────┘                        │
└─────────────────────────────────────────────────────────────┘
                             │
                    HTTP Download
                             │
┌─────────────────────────────────────────────────────────────┐
│                    ESTAÇÃO LINUX                             │
│  ┌──────────────┐                                           │
│  │ agent.py     │ ──> Baixa Bundle .sh                     │
│  │              │ ──> Executa com sudo                      │
│  └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
```

## Tecnologias Utilizadas

| Componente    | Tecnologia                    |
|---------------|-------------------------------|
| Backend       | PHP 8+ (PDO)                  |
| Banco de Dados| PostgreSQL 16+               |
| Frontend      | HTML5 + Tailwind CSS         |
| JavaScript    | Vanilla JS (Fetch API)        |
| Scripts       | Bash Shell                    |
| Agente        | Python 3                      |

## Instalação

### Pré-requisitos

- Ubuntu Server 20.04+ ou Debian 11+
- Acesso root ou sudo
- Conexão com internet

### Instalação Automatizada

```bash
# 1. Clone ou copie o projeto
sudo mkdir -p /var/www/seederlinux-lite
cd /var/www/seederlinux-lite

# 2. Execute o instalador
sudo chmod +x install/install.sh
sudo ./install/install.sh
```

O script de instalação realiza:

1. Atualização de pacotes do sistema
2. Instalação do Apache2, PHP 8+ e PostgreSQL
3. Criação do banco de dados e usuário
4. Aplicação do schema SQL
5. Configuração do VirtualHost
6. Definição de permissões

### Instalação Manual

Se preferir instalar manualmente:

```bash
# 1. Instalar dependências
sudo apt update
sudo apt install apache2 php php-pgsql php-mbstring postgresql

# 2. Criar banco de dados
sudo -u postgres psql
CREATE DATABASE seederlinux;
CREATE USER seeder WITH PASSWORD 'seeder123';
GRANT ALL PRIVILEGES ON DATABASE seederlinux TO seeder;
\q

# 3. Aplicar schema
psql -U seeder -d seederlinux -f install/schema.sql

# 4. Configurar Apache
sudo cp -r . /var/www/seederlinux-lite/
sudo chown -R www-data:www-data /var/www/seederlinux-lite
```

## Configuração Pós-Instalação

### Alterar Senha do Admin

```sql
-- Conectar ao banco
psql -U seeder -d seederlinux

-- Atualizar senha (gere um hash com password_hash)
UPDATE users SET password_hash = '$2y$10$...' WHERE username = 'admin';
```

### Configurar HTTPS

```bash
# Instalar Certbot
sudo apt install certbot python3-certbot-apache

# Obter certificado
sudo certbot --apache -d seu-dominio.com
```

### Alterar Credenciais do Banco

1. Edite `.env` com novas credenciais
2. Atualize PostgreSQL:
```bash
sudo -u postgres psql
ALTER USER seeder WITH PASSWORD 'nova-senha-forte';
```

## Painel Administrativo

### Acesso

- URL: `http://servidor/admin`
- Usuário padrão: `admin`
- Senha padrão: `admin123`

### Funcionalidades

#### 1. Dashboard

Visão geral com contagem de:
- Organizações cadastradas
- Scripts disponíveis
- Variáveis configuradas
- Execuções realizadas

#### 2. Gerenciamento de OMs

**Criar Nova OM:**
1. Clique no botão "+" no sidebar
2. Preencha: Nome, Sigla, Domínio
3. Valores padrão são copiados automaticamente

**Editar OM:**
1. Selecione a OM no sidebar
2. Vá na aba "Configurações"
3. Altere nome, domínio ou descrição

**Excluir OM:**
1. Selecione a OM
2. Vá em "Configurações"
3. Clique em "Excluir OM"

#### 3. Gerenciamento de Variáveis

Cada OM possui suas próprias variáveis organizadas por categoria:

| Categoria      | Variáveis                          |
|----------------|-------------------------------------|
| Domínio        | DOMINIO, DC_IP, DOMINIO_NETBIOS    |
| Rede           | DNS_INTERNET, BASE_URL, PRINT_SERVER |
| Proxy          | PROXY_HTTP, PROXY_PORTA, PROXY_URL |
| Inventário     | OCS_SERVER, OCS_TAG                |
| Segurança      | GRUPO_ADMIN_AD, GRUPO_DASTI        |
| Branding       | WALLPAPER_URL, LOGO_URL            |

#### 4. Geração de Bundle

1. Selecione a OM
2. Vá na aba "Gerar Bundle"
3. Visualize os scripts incluídos
4. Clique em "Baixar Bundle"

## Uso do Agente Python

### Na Estação Linux

```bash
# 1. Baixar o agente
wget http://servidor/downloads/agent.py
# ou
curl -O http://servidor/downloads/agent.py

# 2. Executar
sudo python3 agent.py --org COMARA

# 3. Ver ajuda
python3 agent.py --help
```

### Argumentos do Agente

| Argumento     | Descrição                              |
|---------------|-----------------------------------------|
| `--org, -o`   | Sigla da OM (obrigatório)             |
| `--server, -s`| URL do servidor (padrão: localhost)   |
| `--dry-run`   | Baixa sem executar                    |
| `--version`   | Exibe versão                           |

## Scripts Core Incluídos

### 1. core_network.sh

Configuração de rede e proxy:
- Variáveis de ambiente de proxy
- DNS do sistema
- Página inicial do Firefox
- Servidor de impressão CUPS

### 2. core_domain.sh

Ingresso em domínio Active Directory:
- Instalação de SSSD/realmd
- Configuração de Kerberos
- Grupos sudoers para AD
- Criação automática de home

### 3. core_inventory.sh

Agente OCS Inventory:
- Instalação do ocsinventory-agent
- Configuração de servidor e tag
- Agendamento de execução diária

### 4. core_branding.sh

Identidade visual:
- Download de wallpaper
- Download de logo
- Configuração do LightDM
- Identidade do sistema

## Personalização

### Adicionar Nova Variável

```sql
INSERT INTO variable_definitions (name, placeholder, description, default_value, category, is_required)
VALUES ('NOME_VAR', '{{NOME_VAR}}', 'Descrição', 'valor_padrao', 'categoria', TRUE);
```

### Adicionar Script Personalizado

```sql
INSERT INTO scripts (name, filename, description, content, is_core, execution_order)
VALUES (
    'Meu Script',
    'meu_script.sh',
    'Descrição do script',
    '#!/bin/bash\necho "Hello"',
    FALSE,
    10
);
```

## Troubleshooting

### Erro de Conexão com PostgreSQL

```bash
# Verificar serviço
sudo systemctl status postgresql

# Testar conexão
psql -h localhost -U seeder -d seederlinux

# Verificar logs
sudo tail -f /var/log/postgresql/postgresql-*.log
```

### Erro 500 no Apache

```bash
# Verificar erros
sudo tail -f /var/log/apache2/seederlinux-lite_error.log

# Verificar permissões
ls -la /var/www/seederlinux-lite/

# Verificar sintaxe PHP
php -l /var/www/seederlinux-lite/api/index.php
```

### Bundle Não Baixa

1. Verifique se a OM existe no banco
2. Confirme a sigla correta
3. Verifique conectividade de rede

## Segurança

### Recomendações

1. **Senhas:** Altere todas as senhas padrão
2. **HTTPS:** Use certificado SSL em produção
3. **Firewall:** Permita apenas portas 80/443
4. **Backup:** Configure backup do PostgreSQL
5. **Logs:** Monitore logs de acesso

### Configuração de Firewall

```bash
# UFW (Ubuntu)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# iptables
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
```

## Backup e Recuperação

### Backup do Banco

```bash
pg_dump -U seeder seederlinux > backup_$(date +%Y%m%d).sql
```

### Restauração

```bash
psql -U seeder seederlinux < backup_20240115.sql
```

## Contato e Suporte

- Documentação: `/downloads/DOCUMENTACAO.md`
- Logs: `/var/log/apache2/seederlinux-lite_error.log`

---

**SeederLinux Lite v1.0.0**
Desenvolvido para provisionamento de estações Linux OM.
