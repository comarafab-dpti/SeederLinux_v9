#!/bin/bash
# SeederLinux Lite - Script de Deploy
# Use este script para configurar o projeto no servidor

set -e

TARGET_DIR="${1:-/var/www/seederlinux-lite}"

echo "=== SeederLinux Lite - Deploy ==="
echo "Instalando em: $TARGET_DIR"

# Verificar se estamos no diretório correto
if [ ! -f "public/index.html" ]; then
    echo "ERRO: Execute este script a partir do diretório raiz do projeto"
    exit 1
fi

# Criar diretório de destino
echo "Criando estrutura de diretórios..."
mkdir -p "$TARGET_DIR"

# Copiar todos os arquivos do projeto (raiz + public/)
echo "Copiando arquivos..."
cp -r public "$TARGET_DIR/public"
cp -r install "$TARGET_DIR/install"
cp -f .htaccess "$TARGET_DIR/.htaccess" 2>/dev/null || true

# Criar arquivo .env se não existir
if [ ! -f "$TARGET_DIR/.env" ]; then
    echo "Criando arquivo .env padrão..."
    cat > "$TARGET_DIR/.env" << 'EOF'
DB_HOST=localhost
DB_PORT=5432
DB_NAME=seederlinux
DB_USER=seeder
DB_PASS=seeder123

APP_NAME=SeederLinux Lite
APP_VERSION=1.0.0
APP_ENV=production
APP_DEBUG=false
EOF
fi

# Configurar permissões
echo "Configurando permissões..."
chown -R www-data:www-data "$TARGET_DIR"
chmod -R 755 "$TARGET_DIR"
chmod -R 775 "$TARGET_DIR/storage"
chmod -R 775 "$TARGET_DIR/public/bundles"
chmod -R 775 "$TARGET_DIR/public/scripts/custom"
chmod 600 "$TARGET_DIR/.env"

echo ""
echo "=== Deploy concluído! ==="
echo ""
echo "Próximos passos:"
echo ""
echo "1. Configure o Apache com DocumentRoot: $TARGET_DIR"
echo ""
echo "2. Exemplo de VirtualHost:"
echo ""
cat << 'VHOST'
<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerName seederlinux.comara.intraer
        DocumentRoot /var/www/seederlinux-lite

        <Directory /var/www/seederlinux-lite>
            Options -Indexes +FollowSymLinks
            AllowOverride All
            Require all granted
        </Directory>

        SSLEngine on
        SSLCertificateFile /etc/ssl/certs/ssl-cert-snakeoil.pem
        SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key

        ErrorLog ${APACHE_LOG_DIR}/seederlinux-error.log
        CustomLog ${APACHE_LOG_DIR}/seederlinux-access.log combined
    </VirtualHost>
</IfModule>

<VirtualHost *:80>
    ServerName seederlinux.comara.intraer
    Redirect permanent / https://seederlinux.comara.intraer/
</VirtualHost>
VHOST

echo ""
echo "3. Habilite os módulos do Apache:"
echo "   sudo a2enmod rewrite headers ssl"
echo "   sudo a2ensite seederlinux-lite"
echo "   sudo systemctl restart apache2"
echo ""
echo "4. Configure o banco de dados PostgreSQL:"
echo "   sudo -u postgres psql -f $TARGET_DIR/install/schema.sql"
echo ""
echo "5. Acesse: https://seederlinux.comara.intraer/"
echo "   (DocumentRoot é a raiz do projeto, .htaccess redireciona / para public/index.html)"
echo ""
echo "6. Login admin:"
echo "   https://seederlinux.comara.intraer/public/login.html"
echo "   Usuário: admin"
echo "   Senha: admin123"
echo "   (ALTERE A SENHA APÓS O PRIMEIRO LOGIN!)"
