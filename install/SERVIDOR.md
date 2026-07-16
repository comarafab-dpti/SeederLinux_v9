# Configuração do Servidor - SeederLinux Lite

## Diagnóstico Rápido

Acesse `http://seu-servidor/public/check.html` para testar as rotas automaticamente antes de qualquer configuração.

## Problema: Redirecionamento para localhost / 404 na API

Se ao acessar o servidor remoto você é redirecionado para localhost ou recebe 404 na API, o problema está na configuração do VirtualHost ou DocumentRoot.

## Estrutura de Diretórios Correta

```
/var/www/seederlinux/
├── api/
│   └── index.php        # API endpoint
├── assets/
│   ├── css/
│   └── js/
├── includes/
├── install/
├── lib/
├── public/
│   ├── admin.html
│   ├── index.html       # Página inicial
│   └── login.html
├── scripts/
├── storage/
└── .htaccess           # Configuração Apache
```

## Solução: Apache

### 1. Configurar VirtualHost

Crie o arquivo `/etc/apache2/sites-available/seederlinux.conf`:

```apache
<VirtualHost *:80>
    ServerName seederlinux.seudominio.com
    DocumentRoot /var/www/seederlinux

    <Directory /var/www/seederlinux>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/seederlinux_error.log
    CustomLog ${APACHE_LOG_DIR}/seederlinux_access.log combined
</VirtualHost>
```

### 2. Habilitar módulos necessários

```bash
sudo a2enmod rewrite headers
sudo a2ensite seederlinux
sudo systemctl restart apache2
```

### 3. Copiar arquivos

```bash
# Copie todos os arquivos para /var/www/seederlinux/
sudo cp -r /caminho/para/seederlinux/* /var/www/seederlinux/

# Configurar permissões
sudo chown -R www-data:www-data /var/www/seederlinux
sudo chmod -R 755 /var/www/seederlinux
sudo chmod -R 775 /var/www/seederlinux/storage /var/www/seederlinux/public/bundles
```

## Solução: Nginx

### 1. Configurar server block

Crie o arquivo `/etc/nginx/sites-available/seederlinux`:

```nginx
server {
    listen 80;
    server_name seederlinux.seudominio.com;
    root /var/www/seederlinux;
    index index.html index.php;

    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";

    # Main location
    location / {
        try_files $uri $uri/ /public/index.html;
    }

    # API routing
    location /api/ {
        try_files $uri /api/index.php?$query_string;
    }

    # PHP handling
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_HOST $host;
        fastcgi_param SERVER_NAME $host;
    }

    # Block sensitive directories
    location ~ ^/(lib|includes|install|scripts|storage|templates)/ {
        deny all;
    }

    # Block sensitive files
    location ~ \.(sql|md|sh|py|env)$ {
        deny all;
    }
}
```

### 2. Habilitar site

```bash
sudo ln -s /etc/nginx/sites-available/seederlinux /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## Verificação

### Teste 1: Arquivos estáticos
```bash
curl -I http://seu-servidor/public/index.html
# Deve retornar 200 OK
```

### Teste 2: API
```bash
curl http://seu-servidor/api/?action=stats
# Deve retornar JSON com estatísticas
```

### Teste 3: Download
```bash
curl -I http://seu-servidor/api/download.php?file=agent.py
# Deve retornar 200 OK com Content-Type: text/x-python
```

## Problemas Comuns

### 1. Redirecionamento para localhost
**Causa:** URL absoluta no código ou Host header incorreto
**Solução:** Verifique se o `ServerName` no VirtualHost está correto

### 2. Página em branco
**Causa:** Erro PHP não exibido
**Solução:** Verifique os logs:
```bash
tail -f /var/log/apache2/error.log
# ou
tail -f /var/log/nginx/error.log
```

### 3. 404 na API
**Causa:** Rewrite module não habilitado
**Solução:**
```bash
sudo a2enmod rewrite
sudo systemctl restart apache2
```

### 4. Erro de permissão
**Causa:** Permissões incorretas
**Solução:**
```bash
sudo chown -R www-data:www-data /var/www/seederlinux
sudo chmod -R 755 /var/www/seederlinux
```

## Configuração do Banco de Dados

Crie o arquivo `.env` na raiz do projeto com:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=seederlinux
DB_USER=seeder
DB_PASS=sua_senha_segura

APP_NAME=SeederLinux Lite
APP_VERSION=1.0.0
DEBUG=false
```

## Próximos Passos

1. Acesse `http://seu-servidor/public/login.html`
2. Faça login com as credenciais padrão (admin/admin123)
3. **IMPORTANTE:** Altere a senha padrão imediatamente!
