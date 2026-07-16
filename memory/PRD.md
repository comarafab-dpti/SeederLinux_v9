# SeederLinux Lite — Bundle Generator PRD

## Original Problem Statement
Ferramenta web (PHP + PostgreSQL) que gera bundles bash de provisionamento para estacoes Debian-like em ambientes AD/COMARA.

## Tech Stack
- Backend: PHP (api/index.php) + PostgreSQL
- Frontend: HTML/JS estatico (admin.html + assets/js/admin.js + assets/css/style.css)
- Bundle-gen: scripts bash em scripts/core/*.sh com placeholders `{{VAR}}` substituidos server-side via `substituir_placeholders()`

## Sessao 1 (Jan 2026): Correcao de 6 bugs + arquitetura
- schema.sql: adicionadas variaveis `DC_IP_LIST`, `ADMIN_USERNAME`, `INSTALL_DESKTOP` + seed explicito. `DESKTOP_ENV`/`DISPLAY_MANAGER` com default vazio (auto-detect).
- core_dns.sh: corrigido `$DNS_SECUNDARIO}` -> `${DNS_SECUNDARIO}`
- core_domain.sh: `winbind offline logon` agora condicional a `AUTH_METHOD` + `OFFLINE_AUTH_ENABLED`; declarada var `AUTH_METHOD`
- core_packages.sh: removida instalacao obrigatoria de DE; funcoes `detectar_de()`/`detectar_dm()` exportam `DETECTED_DE`/`DETECTED_DM`; DE so instala se `INSTALL_DESKTOP=true`
- core_branding.sh, core_logon.sh, core_logoff.sh, core_session_{lightdm,gdm3,sddm}.sh: fallback de auto-deteccao
- api/index.php `handleGenerateBundle()`: filtra scripts `core_session_*.sh` mantendo apenas o correspondente a `DISPLAY_MANAGER` (fallback lightdm)

## Sessao 2 (Jan 2026): Refatoracao UX admin
- **install/schema_update_v5_ux_refactor.sql**: migracao safe para bases existentes.
  - DNS movidos para categoria `rede`
  - WALLPAPER/LOGO/GREETER -> categoria nova `assets`, tipo `image`
  - CONKY_PROFILE -> categoria nova `monitoramento`, tipo `select`
  - COMPARTILHAMENTOS/PRINTERS/NO_PROXY -> tipo `tags`
  - Nova variavel `CONKY_CONFIG` (JSON) para configuracao avancada do Conky
- **schema.sql** (fresh install): mesmas mudancas aplicadas diretamente
- **assets/js/admin.js**:
  - Novas categorias `assets`, `monitoramento`, `ambiente`, `aplicacoes`
  - `variableOptions` expandido: DESKTOP_ENV, DISPLAY_MANAGER, AUTH_METHOD, CONKY_PROFILE, INSTALL_APPS, INSTALL_LEGADOS, INSTALL_DESKTOP, VNC_ENABLED como boolean
  - `dependentFields`: campos ocultos quando toggle pai desligado (VNC_PASSWORD, DESKTOP_ENV, OCS_*, CERTIFICATE_BUNDLE, OFFLINE_AUTH_DAYS)
  - `groupedVariables`: renderiza GRUPO_ADMIN_AD + GRUPO_ADMIN_LINUX + GRUPO_DASTI num bloco unico "Grupos com privilegio sudo"
  - `renderTypedInput` novos tipos: `tags` (chips input), `image` (preview + URL), `json_conky` (painel expandido)
  - `renderConkyPanel`: aparencia (posicao, transparencia, cores via color picker, fonte, gap_x/y, intervalo) + informacoes exibidas (CPU/RAM/Disco/Rede/Top procs/Data-hora) + interfaces/particoes configuraveis
  - `handleTagInput`/`removeTag`/`refreshTagsList`: gerenciamento das chips
  - `updateAssetPreview`: preview `<img>` atualiza on-input
  - `updateConkyField`: serializa alteracoes no hidden input
  - Re-render automatico quando toggle pai muda (mostra/esconde dependentes)
  - `saveVariables` prefere valores de hidden inputs (tags/conky) para serializacao correta
- **assets/css/style.css**: novos estilos para `.tags-wrapper`/`.tag-chip`/`.tag-remove`/`.tag-input`, `.asset-field`/`.asset-preview`/`.asset-preview-empty`, `.conky-panel`/`.conky-section`/`.conky-grid`/`.conky-color`
- **scripts/core/core_conky.sh**:
  - Declara `CONKY_CONFIG` (JSON) alem de `CONKY_PROFILE`
  - Instala `jq` alem de `conky conky-all`
  - `parse_json()` usa `has()` para preservar booleans false (bug corrigido)
  - Gera `.conkyrc` dinamicamente aplicando posicao, cores, transparencia, gaps, particao/interface configuraveis, e includes condicionais para CPU/RAM/Disco/Rede/Top/Data-hora
  - Fallback de deteccao de DE (mesmo padrao dos outros scripts)

## Files Modified
- install/schema.sql
- install/schema_update_v5_ux_refactor.sql (novo)
- assets/js/admin.js
- assets/css/style.css
- scripts/core/core_conky.sh
- api/index.php (upload-asset endpoint unificado)
- 9 scripts em scripts/core/ (sessao anterior)

## Sessao 4 (Jan 2026): Auditoria Seguranca (Opcao A)
- **api/index.php**: 3 handlers de upload agora validam MIME real via `finfo_file()` ao inves de confiar em `$_FILES[...]['type']` (forjavel pelo cliente):
  - `handleUploadWallpaper`: aceita JPG/PNG/GIF/WebP
  - `handleUploadLogo`: aceita JPG/PNG/GIF/WebP/SVG (com normalizacao `image/svg`|`text/xml`|`application/xml` -> `image/svg+xml`)
  - `handleUploadAsset` (endpoint unificado): mesma validacao + normalizacao SVG condicional
  - Erros passam a retornar HTTP 415 com o MIME real detectado para diagnostico
- **tests/test_upload_mime.php**: 3 assertions cobrindo (a) `.txt` renomeado para `.png` -> rejeitado; (b) PNG real -> aceito; (c) SVG normalizado -> aceito
- **Auditoria de setup_user.sql**: encontradas credenciais default fracas `admin`/`admin123` — documentadas em `memory/test_credentials.md` mas NAO alteradas (fora do escopo da Opcao A). Recomendacao registrada para Opcao B/C: gerar senha aleatoria no install.sh ou forcar troca no primeiro login.

## Auditoria (falso positivos confirmados via inspecao)
- SQL injection: NAO existe. `lib/db.php` usa PDO prepared statements em 100% das queries.
- XSS via PHP: NAO existe. PHP e API JSON-only; render e no JS via `Utils.escapeHtml()`.
- schema.sql com senha DB hardcoded: NAO existe.
- `NO_PROXY` como tags quebra core_proxy.sh: NAO — `tags-hidden.value = items.join(',')` produz CSV compativel.
- schema_update_v5 so INSERT: NAO — arquivo tem 6 UPDATEs explicitos de `variable_definitions`.
- Conky recria HTML a cada toggle: NAO — `updateConkyField` so atualiza hidden input JSON.

## Sessao 3 (Jan 2026): Aba Assets - Card Layout Unificado
- **api/index.php**: novo endpoint `POST /api/?action=upload-asset` unificado que aceita `organization_id`, `var_name` e `asset[]`. Whitelist de vars (`WALLPAPER_URL`, `WALLPAPER_LOGIN_URL`, `LOGO_URL`, `GREETER_URL`). Aceita SVG apenas para logo. Atualiza a variavel diretamente + bumpOrgSerial + audit.
- **assets/js/admin.js**:
  - `renderVarRow` roteia `category=assets` OU `type=image` para `renderAssetCard` (nao usa mais galeria antiga)
  - Nova constante `assetLabels` com titulo + hint amigaveis
  - `renderAssetCard` gera card com: header (titulo/hint/var name em pill mono), preview `<img>` com aspect 16:9 e checkerboard de transparencia, input URL editavel, botao "Selecionar arquivo" (upload real) + botao "Remover" (limpa URL, desabilita se vazio)
  - `updateAssetCardPreview` atualiza preview e habilita/desabilita botao Remover on-the-fly
  - `clearAsset` limpa a URL localmente (persistira ao clicar Salvar)
  - `uploadAsset` faz `fetch` FormData para o endpoint unificado, atualiza input+preview+allVariables in-memory sem reload
- **assets/css/style.css**: estilos `.asset-card`, `.asset-card-header`, `.asset-card-title`, `.asset-card-hint`, `.asset-card-varname` (pill), `.asset-card-preview-wrap` (com checkerboard para mostrar transparencia), `.asset-btn-primary`/`.asset-btn-secondary` (com estado disabled).

**Problemas resolvidos:**
- `WALLPAPER_URL` aparecendo 3× -> agora 1 card unico
- `GREETER_URL` sem botao upload -> agora tem botao "Selecionar arquivo"
- Layout confuso com secoes soltas -> cards padronizados em grid
- Ausencia de "Remover" -> botao dedicado com estado disabled
- Falta de preview em tempo real -> `oninput` atualiza a thumb

## Testing
- `bash -n` limpo em todos scripts bash
- `php -l` limpo em api/index.php e lib/functions.php
- `acorn.parse` valida admin.js (58 KB)
- `tests/test_conky_parse.sh`: 5/5 assertions passam (position, transparent=false, show_top=false, show_datetime=true, fallback)

## Backlog / Nice-to-have
- Endpoint de upload centralizado para assets (item 5 opcao b) — nao implementado
- Substituir 3 vars sudo por variavel unica SUDO_GROUPS JSON — nao implementado (compat mantida)
- Testar bundle real em VM Debian/Ubuntu/Mint/Zorin com diferentes DEs
- Estilos avancados de tema (dark/light theme picker global)
