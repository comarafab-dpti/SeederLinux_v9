#!/usr/bin/env python3
"""
Gera install/insert_core_scripts.sql a partir dos arquivos em scripts/core/.
Usa dollar-quoting do PostgreSQL ($SeederScript$) para eliminar escaping.
"""
import os
import sys

SCRIPTS_DIR = '/app/scripts/core'
OUTPUT = '/app/install/insert_core_scripts.sql'
TAG = '$SeederScript$'

# Ordem de execucao + nome legivel + descricao
# Referencia: problem statement do usuario + estrutura atual
CATALOG = [
    # (execution_order, filename, name, description)
    (1,  'core_dns.sh',              'Configuracao de DNS',              'Configura DNS temporario, NTP e /etc/hosts. Roda ANTES de repositorios para permitir apt-get update.'),
    (2,  'core_repositories.sh',     'Configuracao de Repositorios',     'Configura repositorios APT (oficial, espelho ou customizado) apos o DNS estar resolvendo.'),
    (3,  'core_packages.sh',         'Instalacao de Pacotes',            'Instala TODOS os pacotes necessarios (sistema, OCS, CUPS, VNC, Conky, Java, etc).'),
    (4,  'core_domain.sh',           'Ingresso em Dominio AD',           'Ingressa a estacao no Active Directory (SSSD/Winbind com fallback).'),
    (5,  'core_browser.sh',          'Configuracao de Navegador',        'Configura Firefox ESR e Chrome (homepage, proxy, bookmarks) via politicas corporativas.'),
    (6,  'core_inventory.sh',        'Agente de Inventario OCS',         'Configura OCS Inventory Agent (sem apt-get; pacote instalado em core_packages.sh).'),
    (7,  'core_printers.sh',         'Configuracao de Impressoras',      'Configura CUPS e impressoras via servidor remoto.'),
    (8,  'core_vnc.sh',              'Configuracao VNC',                 'Configura x11vnc para acesso remoto assistido.'),
    (9,  'core_conky.sh',            'Configuracao de Conky',            'Configura o Conky (monitor de sistema no desktop) com perfil dinamico via JSON.'),
    (10, 'core_apps.sh',             'Instalacao de Aplicacoes Extras',  'Instala aplicacoes extras (OnlyOffice, Chrome, etc).'),
    (11, 'core_legados.sh',          'Suporte a Sistemas Legados',       'Instala Java 8 e Firefox 52 ESR para compatibilidade com sistemas legados.'),
    (12, 'core_config.sh',           'Configuracoes Adicionais',         'Configuracoes diversas do sistema (sysctl, limits, etc).'),
    (13, 'core_branding.sh',         'Identidade Visual (Branding)',     'Aplica wallpaper, logo, tema GTK e branding da OM.'),
    (14, 'core_logon.sh',            'Script de Logon Persistente',      'Script executado a cada logon de usuario (multi-DE).'),
    (15, 'core_logoff.sh',           'Script de Logoff Persistente',     'Script executado a cada logoff de usuario.'),
    (16, 'core_session_lightdm.sh',  'Sessao LightDM',                   'Configura LightDM como display manager (autoselecao via DISPLAY_MANAGER=lightdm).'),
    (16, 'core_session_gdm3.sh',     'Sessao GDM3',                      'Configura GDM3 como display manager (autoselecao via DISPLAY_MANAGER=gdm3).'),
    (16, 'core_session_sddm.sh',     'Sessao SDDM',                      'Configura SDDM como display manager (autoselecao via DISPLAY_MANAGER=sddm).'),
    (17, 'core_proxy.sh',            'Configuracao de Proxy',            'Configura proxy corporativo no sistema (apt, curl, wget, env).'),
]

def escape_sql_literal(s: str) -> str:
    """Escapa apenas para strings SQL curtas (name/description). Duplica aspas simples."""
    return s.replace("'", "''")

def main():
    header = """-- ============================================================================
-- SeederLinux Lite - Insercao dos Scripts Core
-- ============================================================================
-- Este arquivo popula a tabela 'scripts' com todos os scripts Core.
-- Gerado automaticamente a partir dos arquivos em scripts/core/.
--
-- ESCAPING: Usa dollar-quoting do PostgreSQL ($SeederScript$) para o conteudo
-- dos scripts, eliminando problemas com aspas simples, aspas duplas,
-- backslashes e qualquer outro caractere especial no bash.
-- ============================================================================

-- Limpar scripts core existentes (opcional - descomente se necessario)
-- DELETE FROM scripts WHERE is_core = TRUE;

"""

    parts = [header]
    on_conflict = (
        "ON CONFLICT (filename) DO UPDATE SET\n"
        "    name = EXCLUDED.name,\n"
        "    description = EXCLUDED.description,\n"
        "    content = EXCLUDED.content,\n"
        "    execution_order = EXCLUDED.execution_order,\n"
        "    version = EXCLUDED.version,\n"
        "    is_active = EXCLUDED.is_active,\n"
        "    updated_at = CURRENT_TIMESTAMP;\n"
    )

    missing = []
    tag_collisions = []
    for order, filename, name, description in CATALOG:
        path = os.path.join(SCRIPTS_DIR, filename)
        if not os.path.isfile(path):
            missing.append(filename)
            continue

        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Verifica se a tag conflita com o conteudo
        if TAG in content:
            tag_collisions.append(filename)
            continue

        block = (
            f"-- ============================================================================\n"
            f"-- {name} (ordem {order}) - {filename}\n"
            f"-- ============================================================================\n"
            f"INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)\n"
            f"VALUES (\n"
            f"    '{escape_sql_literal(name)}',\n"
            f"    '{escape_sql_literal(filename)}',\n"
            f"    '{escape_sql_literal(description)}',\n"
            f"    {TAG}{content}{TAG},\n"
            f"    TRUE,\n"
            f"    TRUE,\n"
            f"    {order},\n"
            f"    1,\n"
            f"    NULL\n"
            f") {on_conflict}\n"
        )
        parts.append(block)

    if missing:
        print("ERRO: Arquivos ausentes:", missing, file=sys.stderr)
        sys.exit(1)
    if tag_collisions:
        print("ERRO: Tag $SeederScript$ colide com conteudo em:", tag_collisions, file=sys.stderr)
        sys.exit(1)

    footer = """
-- ============================================================================
-- FIM: 19 scripts core inseridos.
-- Ordem de execucao:
--   01 core_dns.sh              (configura DNS ANTES de apt-get update)
--   02 core_repositories.sh     (agora tem DNS resolvendo)
--   03 core_packages.sh
--   04 core_domain.sh
--   05 core_browser.sh
--   06 core_inventory.sh
--   07 core_printers.sh
--   08 core_vnc.sh
--   09 core_conky.sh
--   10 core_apps.sh
--   11 core_legados.sh
--   12 core_config.sh
--   13 core_branding.sh
--   14 core_logon.sh
--   15 core_logoff.sh
--   16 core_session_{lightdm|gdm3|sddm}.sh   (bundle mantem apenas 1 conforme DISPLAY_MANAGER)
--   17 core_proxy.sh
-- ============================================================================
"""
    parts.append(footer)

    with open(OUTPUT, 'w', encoding='utf-8') as f:
        f.write('\n'.join(parts))

    print(f"OK: {OUTPUT} gerado com {len(CATALOG)} scripts.")

if __name__ == '__main__':
    main()
