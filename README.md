# SeederLinux Lite - Gerenciamento de Provisionamento Linux

Sistema de gerenciamento centralizado de scripts para provisionamento de estações Linux.

## Instalação Rápida

```bash
sudo ./install/install.sh
```

## Acesso

- Página Pública: http://localhost/
- Painel Admin: http://localhost/admin.html
- Login: http://localhost/login.html

## Credenciais Padrão

- Usuário: admin
- Senha: admin123

**IMPORTANTE:** Altere as credenciais em produção!

## Estrutura do Projeto

```
├── public/             # Web root (DocumentRoot do Apache)
│   ├── api/            # API REST PHP (router + download handler)
│   ├── assets/         # CSS e JavaScript do frontend
│   ├── includes/       # Bibliotecas de autenticação
│   ├── lib/            # Conexão com DB, config e funções PHP
│   ├── downloads/      # Agente Python e documentação
│   ├── scripts/        # Scripts shell de provisionamento
│   ├── storage/        # Armazenamento de bundles gerados
│   ├── admin.html      # Painel administrativo
│   ├── check.html      # Diagnóstico de conectividade
│   ├── index.html      # Página pública
│   └── login.html      # Tela de login
├── install/            # Instalador e schema SQL
│   ├── install.sh      # Script de instalação
│   ├── deploy.sh       # Script de deploy manual
│   └── schema.sql      # Schema do banco PostgreSQL
├── .env                # Configuração de ambiente
└── .htaccess           # Redireciona para public/ (dev local)
```

## Uso do Agente

```bash
# Na estação Linux
sudo python3 agent.py --org COMARA --server http://192.168.1.100
```

## Documentação

Veja `install/DOCUMENTACAO.md` para documentação completa.
