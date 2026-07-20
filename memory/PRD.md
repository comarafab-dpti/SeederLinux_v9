# SeederLinux Lite - PRD & Histórico de Alterações

## 📋 Contexto do Projeto

Sistema de provisionamento automatizado de estações Linux com integração a Active Directory, para ambientes militares multi-organizacionais (OMs). O sistema gera **bundles** (scripts shell autônomos) que configuram uma estação Linux do zero: ingresso no AD, instalação de pacotes, configuração de proxy, navegadores, impressoras, VNC, Conky, branding e scripts de logon/logoff persistentes.

## 🧱 Stack Tecnológica
- **Backend:** PHP 8+ (API monolítica em `api/index.php`)
- **Banco de Dados:** PostgreSQL 16+
- **Frontend:** HTML/CSS/JS vanilla (`admin.html`, `admin.js`, `app.js`)
- **Scripts Core:** 19 scripts Bash em `scripts/core/`
- **Agente:** Python 3 (`downloads/agent.py`)

## 👥 Personas
- **Admin GAP:** Administrador global, gerencia todas as OMs
- **Operador OM:** Usuário vinculado a uma OM específica, gera bundles próprios
- **Auditor:** Somente leitura em auditoria e usuários

## 🎯 Requisitos Fundamentais
- Multi-organização com isolamento de dados por OM
- Substituição dinâmica de placeholders `{{VARIAVEL}}` em scripts
- Geração de bundles autônomos executáveis offline
- Ingresso no AD com SSSD e/ou Winbind (fallback)
- Auditoria de todas as ações administrativas
- Check-in periódico das estações provisionadas

---

## ✅ Sessão 2 — 2026-01 — Regeneração do `insert_core_scripts.sql` com dollar-quoting

### 🐛 Bug reportado pelo usuário
`install/insert_core_scripts.sql` tinha erros de escaping: aspas simples dentro dos scripts Bash não foram duplicadas (`'` → `''`), quebrando a sintaxe SQL. Resultado: apenas 2 de 19 scripts eram carregados. Erros observados:
```
psql:install/insert_core_scripts.sql:708: erro: comando inválido \n,'
psql:install/insert_core_scripts.sql:970: erro: comando inválido \
psql:install/insert_core_scripts.sql:1352: ERRO: erro de sintaxe em ou próximo a "GRP_LIST"
```

### 🔧 Solução aplicada
Regenerado `install/insert_core_scripts.sql` usando **dollar-quoting do PostgreSQL** (`$SeederScript$...$SeederScript$`), que elimina completamente a necessidade de escaping para aspas, backslashes, heredocs ou qualquer outro caractere especial dos scripts Bash.

**Ferramenta criada:** `/app/install/gen_insert_core.py` — script Python que:
- Lê os 19 arquivos `.sh` de `scripts/core/`
- Verifica que a tag `$SeederScript$` não colide com o conteúdo de nenhum script
- Gera o SQL com dollar-quoting, ordem de execução correta e `ON CONFLICT (filename) DO UPDATE`
- Suporta reexecução idempotente

**Arquivos alterados:**
- `/app/install/insert_core_scripts.sql` (regenerado, 4.531 linhas)
- `/app/install/gen_insert_core.py` (novo, gerador reprodutível)

### 🧪 Validação pelo testing_agent (iteration_1.json)
**28/28 testes pytest PASSANDO** — success_rate backend: 100%. Validações executadas contra PostgreSQL 15 real:
- ✅ 19 blocos `INSERT INTO scripts` + 19 `ON CONFLICT (filename)` 
- ✅ Zero ocorrências de escaping incorreto (`\'`)
- ✅ Dollar-quoting `$SeederScript$` presente (38 delimitadores)
- ✅ Todos os 19 scripts carregados sem erros SQL
- ✅ Ordem de execução correta: dns=1, repositories=2, packages=3, ..., proxy=17
- ✅ Preservação **byte-a-byte** do conteúdo (arquivo == banco para todos os 19)
- ✅ Idempotência (re-executar mantém 19 scripts, não duplica)
- ✅ Caractere especial `IFS=$` preservado em core_packages.sh
- ✅ 441 placeholders `{{VAR}}` preservados nos 19 scripts

### ⚠️ Bug pré-existente identificado (fora de escopo)
`install/schema.sql` linhas 258-261 usa `DO $` (single dollar) que é sintaxe inválida — deveria ser `DO $$ ... $$;`. Isso impede a criação automática da constraint UNIQUE em `scripts.filename`. Como consequência, ao rodar o `insert_core_scripts.sql` numa base recém-criada, o `ON CONFLICT (filename)` falha por falta de constraint.

**Workaround temporário (até correção do schema.sql):**
```sql
ALTER TABLE scripts ADD CONSTRAINT scripts_filename_key UNIQUE (filename);
```

O usuário instruiu **explicitamente** que apenas `insert_core_scripts.sql` poderia ser alterado nesta sessão, então este bug do schema **não foi corrigido**. Deve ser tratado em uma sessão futura (correção trivial: trocar `DO $` por `DO $$` e `END $;` por `END $$;`).

---


### 🔴 Parte 2 - Correções Críticas (CONCLUÍDAS)

#### 2.1 - Ordem DNS/Repositories invertida
**Problema:** `core_repositories.sh` (ordem 01) executava `apt-get update` **antes** do DNS ser configurado (ordem 02), causando falha de resolução de nomes.

**Solução aplicada:**
- `core_dns.sh` → **execution_order = 1** (agora primeiro)
- `core_repositories.sh` → **execution_order = 2** (agora depois)
- Cabeçalhos dos scripts atualizados para refletir a nova ordem (`01 - Configurar DNS...`, `02 - Configurar repositorios APT`)
- Sincronização realizada em `install/insert_core_scripts.sql`

**Arquivos alterados:**
- `/app/scripts/core/core_dns.sh`
- `/app/scripts/core/core_repositories.sh`
- `/app/install/insert_core_scripts.sql`

---

#### 2.2 - Pacote `conky` genérico removido
**Problema:** O array `EXTRA_PACKAGES` em `core_packages.sh` continha tanto `conky` (pacote virtual) quanto `conky-all`, fazendo o `apt-get` falhar por ambiguidade.

**Solução aplicada:**
- Removido `conky` do array
- Mantido apenas `conky-all`
- Sincronização em `install/insert_core_scripts.sql`

**Arquivos alterados:**
- `/app/scripts/core/core_packages.sh` (linha 198)
- `/app/install/insert_core_scripts.sql`

---

#### 2.3 - Erro EOF no bloco SSH/AllowGroups
**Problema:** Linha `IFS=\n,' read -ra GRP_ARRAY <<< "$SSH_GROUPS"` quebrava o bundle com erro `encontrado EOF inesperado enquanto procurava por '' correspondente`. A aspa simples estava mal fechada e o `\n` estava em linha separada.

**Solução aplicada:**
- Correção para: `IFS=$'\n,' read -ra GRP_ARRAY <<< "$SSH_GROUPS"`
- Uso de `$'...'` (ANSI-C quoting) para interpretar `\n` como caractere de nova linha
- Sincronização em `install/insert_core_scripts.sql`

**Arquivos alterados:**
- `/app/scripts/core/core_packages.sh` (linhas 269-270)
- `/app/install/insert_core_scripts.sql`

**Validação:** `bash -n /app/scripts/core/core_packages.sh` → OK ✅

---

#### 2.4 - Desativação automática de bundles anteriores
**Problema:** Ao gerar um novo bundle, os bundles anteriores da mesma OM permaneciam ativos, causando confusão em `handlePublicBundles()` e em `handleStationCheckin()`.

**Solução aplicada:** Após o `INSERT` do novo bundle em `handleGenerateBundle()`, executa:
```sql
UPDATE deploy_bundles SET is_active = FALSE
WHERE organization_id = ? AND id != ?
```

**Arquivo alterado:** `/app/api/index.php` (linhas 862-868)

---

### 🟡 Parte 3 - Melhorias (CONCLUÍDAS)

#### 3.1 - Campo `description` em bundles

**Banco:**
- Nova coluna `description TEXT` em `deploy_bundles`
- Migration idempotente criada em `/app/install/migration_add_bundle_description.sql`
- Schema canônico (`schema.sql`) atualizado para novos deploys

**Backend (`api/index.php`):**
- `handleGenerateBundle()` aceita novo parâmetro `description`
- `INSERT` grava a descrição no banco
- `handleListBundles()` e `handlePublicBundles()` retornam a descrição

**Frontend Admin (`admin.js`, `admin.html`):**
- `generateBundle()` solicita descrição via `prompt()` (opcional)
- Se usuário cancelar prompt, geração é abortada
- Nova coluna "Descrição" na tabela de bundles gerados
- Truncamento visual em 40 caracteres com tooltip completo

**Frontend Público (`index.html`):**
- Nova coluna "Descrição" na galeria pública
- Truncamento em 50 caracteres com tooltip
- Escape HTML aplicado para segurança XSS

**Arquivos alterados:**
- `/app/install/schema.sql`
- `/app/install/migration_add_bundle_description.sql` (novo)
- `/app/api/index.php` (handleGenerateBundle, handleListBundles, handlePublicBundles)
- `/app/admin.html`
- `/app/assets/js/admin.js`
- `/app/index.html`

---

#### 3.2 - Botão ativar/desativar bundle
**Status:** ✅ Já funcional (validado)

- Endpoint `bundle-toggle` em `api/index.php` (linhas 1436-1455) opera corretamente com validação de permissão por OM
- Frontend chama `toggleBundleActive(bundleId)` que hita `POST /api/?action=bundle-toggle`
- Registra evento em `audit_events` (`ACTIVATE`/`DEACTIVATE`)
- Adicionados `data-testid` nos botões para facilitar testes automatizados

---

#### 3.3 - Bloquear geração com placeholders não resolvidos
**Status:** ✅ Já funcional (validado)

Verificação existente em `handleGenerateBundle()` (linhas 840-851):
```php
if (preg_match_all('/\{\{[A-Z_]+\}\}/', $bundle, $matches)) {
    $unresolved = array_unique($matches[0]);
}
if (!empty($unresolved)) {
    jsonError('Placeholders nao resolvidos no bundle: ...', 400);
}
```

A verificação é feita **após** `substituir_placeholders()` e **antes** do `INSERT` no banco, garantindo que bundles inválidos nunca sejam persistidos.

---

## 🔬 Parte 4 - Análise Proativa (Sugestões de Melhoria)

Baseado em análise estática do código, seguem sugestões priorizadas:

### 🔴 Alta Prioridade — Segurança

1. **`api/index.php:207-208` — Timing attack em login**
   Ordem `!$user || !$user['is_active'] || !password_verify(...)` faz curto-circuito, permitindo timing attack para descobrir usernames válidos.
   **Sugestão:** sempre executar `password_verify` (mesmo com hash dummy quando user não existe).

2. **`api/index.php:26-27` — SSRF potencial em `handleUploadAsset`**
   Não há verificação de tipo real via `getimagesize()` como reforço além do finfo (usa magic bytes; se atacante forjar cabeçalho, pode ser burlado).
   **Sugestão:** validar dimensões via `getimagesize()` e rejeitar arquivos inválidos.

3. **`lib/functions.php:16-18` — `sanitizeInput` usa `htmlspecialchars` em TODOS os inputs**
   Isso quebra valores legítimos como senhas, URLs com `&`, e descrições com `<`. Além disso, escape HTML no input é anti-pattern; deve ser feito **na saída**.
   **Sugestão:** remover `htmlspecialchars` de `sanitizeInput` e aplicar escape apenas em outputs HTML (frontend já faz via `Utils.escapeHtml`).

4. **`api/index.php:216-221` — Tokens sem invalidação em logout**
   Tokens Bearer permanecem válidos após logout (só session_destroy é chamado).
   **Sugestão:** ao logout, deletar tokens ativos do usuário em `user_tokens`.

5. **`lib/functions.php:20-51` — `requireAuth` faz `password_verify` para cada token no banco**
   Loop O(n) sobre todos os tokens ativos do sistema é ineficiente e vulnerável a DoS.
   **Sugestão:** trocar `token_hash` por índice `token_prefix` (primeiros 8 chars em texto claro) para lookup rápido, mantendo verify apenas do candidato.

### 🟠 Média Prioridade — Performance & UX

6. **`api/index.php:1099-1101` — Query `latest_bundle_id` em cada check-in**
   Chamado a cada 5min por dezenas/centenas de estações. Adicionar índice composto.
   **Sugestão:** `CREATE INDEX idx_bundles_org_active_date ON deploy_bundles(organization_id, is_active, generated_at DESC)`.

7. **`assets/js/admin.js:1339` — `prompt()` nativo para descrição**
   UX ruim (impossível de estilizar, quebra em mobile).
   **Sugestão:** substituir por modal HTML com textarea (padrão já usado em outros lugares).

8. **`api/index.php:882-885` — Bundle inteiro em memória em download**
   `echo $bundle['content']` carrega todo o conteúdo em RAM. Para bundles grandes (>10MB) pode causar OOM.
   **Sugestão:** usar streaming com `fread` de arquivo temporário ou `pg_lo_export`.

9. **`admin.html:243-296` — Tabela sem paginação**
   Bundles crescem indefinidamente. Sem `LIMIT`, tela fica lenta após meses de uso.
   **Sugestão:** adicionar paginação em `handleListBundles` + `handleGetAuditEvents`.

### 🟢 Baixa Prioridade — Manutenibilidade

10. **`api/index.php` — Arquivo monolítico de 1464 linhas**
    Difícil manter. Cada handler poderia estar em arquivo separado (`handlers/bundle.php`, `handlers/auth.php`, etc.).
    **Sugestão:** refatorar em módulos por domínio.

11. **`scripts/core/*.sh` — Sem `shellcheck` no CI**
    O erro EOF do 2.3 teria sido detectado por `shellcheck`.
    **Sugestão:** adicionar hook pre-commit / GitHub Action rodando `shellcheck` em `scripts/core/*.sh`.

12. **`install/insert_core_scripts.sql` — Duplicação de conteúdo dos scripts**
    O SQL replica byte-a-byte o conteúdo dos 19 arquivos `.sh`. Qualquer edição em `.sh` precisa ser espelhada no SQL manualmente.
    **Sugestão:** criar script Python/Bash (`install/build_core_scripts_sql.py`) que gera o SQL a partir dos arquivos `.sh` fonte.

---

## 📁 Estrutura Final Após Sessão 1

```
/app/
├── api/index.php                              [MODIFICADO]
├── admin.html                                 [MODIFICADO]
├── index.html                                 [MODIFICADO]
├── assets/js/admin.js                         [MODIFICADO]
├── scripts/core/
│   ├── core_dns.sh                            [MODIFICADO - ordem 01]
│   ├── core_repositories.sh                   [MODIFICADO - ordem 02]
│   └── core_packages.sh                       [MODIFICADO - conky/EOF]
├── install/
│   ├── schema.sql                             [MODIFICADO - coluna description]
│   ├── insert_core_scripts.sql                [MODIFICADO - sincronizado]
│   └── migration_add_bundle_description.sql   [NOVO]
└── memory/
    └── PRD.md                                 [NOVO]
```

---

## ⚙️ Instruções de Deploy da Sessão 1

Em ambiente de produção (servidor com PostgreSQL + PHP-FPM + Nginx/Apache):

```bash
# 1. Aplicar migration (bases existentes)
psql -U seeder -d seederlinux -f /var/www/seederlinux-lite/install/migration_add_bundle_description.sql

# 2. Re-inserir scripts core com nova ordem
psql -U seeder -d seederlinux -f /var/www/seederlinux-lite/install/insert_core_scripts.sql

# 3. (Opcional) Verificar ordem
psql -U seeder -d seederlinux -c "SELECT filename, execution_order FROM scripts WHERE is_core = TRUE ORDER BY execution_order LIMIT 5;"
# Esperado:
#   core_dns.sh          | 1
#   core_repositories.sh | 2
#   core_packages.sh     | 3
#   core_domain.sh       | 4
#   core_browser.sh      | 5

# 4. Reload do PHP-FPM (nao obrigatorio; PHP recarrega por request)
sudo systemctl reload php8.2-fpm

# 5. Testar geracao de bundle no admin
```

---

## 🗺️ Backlog / Próximos Passos

### P0 (Bloqueadores)
- Nenhum. Sistema utilizável após sessão 1.

### P1 (Alta Prioridade)
- Aplicar correções de segurança #1-#4 (timing attack, sanitizeInput, tokens em logout)
- Substituir `prompt()` por modal HTML (#7)

### P2 (Média Prioridade)
- Paginação em bundles/audit (#9)
- Índice composto para check-in (#6)
- Streaming de download (#8)

### P3 (Baixa Prioridade)
- Refatoração modular de `api/index.php` (#10)
- CI com `shellcheck` (#11)
- Gerador automático de `insert_core_scripts.sql` (#12)

---

## 🧪 Validações Realizadas

- ✅ `bash -n core_packages.sh` → OK
- ✅ `bash -n core_dns.sh` → OK
- ✅ `bash -n core_repositories.sh` → OK
- ✅ `php -l api/index.php` → OK
- ✅ `php -l lib/*.php` → OK
- ✅ `node -c assets/js/admin.js` → OK
- ✅ Grep de `^    conky$` → 0 ocorrências (removido corretamente)
- ✅ Grep de `IFS=$'\n,` → 1 ocorrência em cada arquivo (corrigido)
- ✅ Grep de `execution_order` → ordens invertidas confirmadas
