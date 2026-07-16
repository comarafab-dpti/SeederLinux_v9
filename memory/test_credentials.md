# SeederLinux Lite — Credenciais de Teste

## Admin default (do setup_user.sql)
- **Username:** `admin`
- **Password:** `admin123`
- **Hash bcrypt (cost=12):** `$2y$12$aclfbpmKYX0DoMcu8EmQeO1xyziOBv9/WjuWR6y3/ovgF74QTaLhC`
- **Role:** `admin` (via seed em `install/setup_user.sql`)

## Como redefinir
```bash
sudo -u postgres psql -d seederlinux -f /app/install/setup_user.sql
```

## Aviso de Seguranca
**Credencial default fraca detectada** (`admin` / `admin123`).
Recomendacao para producao (nao aplicado pois esta fora do escopo da Opcao A):
- Gerar senha aleatoria durante `install.sh` e exibir uma unica vez no output.
- Ou forcar troca no primeiro login (adicionar flag `must_change_password` em `users`).

## Banco de dados (fallback em lib/config.php)
- **DB_USER:** `seeder` (via `.env` DB_USER)
- **DB_PASS:** valor do `.env` DB_PASS (fallback `seeder123` se .env ausente — inaceitavel em prod)
- **DB_NAME:** `seederlinux`
- **DB_HOST:** `localhost`
