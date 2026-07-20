/**
 * SeederLinux Lite - Admin JavaScript
 * API, Utils and Toast are defined in app.js and loaded before this file.
 */

let currentUser = null;
let currentOrgId = null;
let organizations = [];
let allVariables = [];
let activeCategory = 'Todas';
let uploadedImages = { wallpapers: [], logos: [] };
let scriptTab = 'Core';

const categoryLabels = {
    'dominio': 'Dominio', 'rede': 'Rede', 'proxy': 'Proxy', 'inventario': 'Inventario',
    'navegador': 'Navegador', 'seguranca': 'Seguranca', 'branding': 'Identidade',
    'assets': 'Identidade Visual & Assets', 'monitoramento': 'Monitoramento (Conky)',
    'ambiente': 'Ambiente Grafico',
    'generic': 'Geral', 'custom': 'Custom', 'arquivos': 'Arquivos',
    'acesso_remoto': 'Acesso Remoto', 'impressoras': 'Impressoras',
    'certificados': 'Certificados', 'repositorios': 'Repositorios',
    'aplicacoes': 'Aplicacoes'
};

const categoryOrder = [
    'dominio', 'rede', 'proxy', 'repositorios', 'ambiente', 'navegador',
    'branding', 'assets', 'monitoramento',
    'arquivos', 'impressoras', 'inventario', 'aplicacoes',
    'acesso_remoto', 'certificados', 'seguranca', 'generic', 'custom'
];

// Campos dependentes: chave = var pai, valor = lista de vars que aparecem apenas se pai=true
const dependentFields = {
    'VNC_ENABLED': ['VNC_PASSWORD'],
    'INSTALL_DESKTOP': ['DESKTOP_ENV'],
    'INVENTORY_ENABLED': ['OCS_SERVER', 'OCS_TAG', 'GLPI_SERVER'],
    'CERTIFICATE_AUTO_INSTALL': ['CERTIFICATE_BUNDLE'],
    'OFFLINE_AUTH_ENABLED': ['OFFLINE_AUTH_DAYS']
};

// Grupo visual: 3 vars renderizadas juntas em um bloco unico
const groupedVariables = {
    'GRUPO_ADMIN_AD': {block: 'sudo_groups', label: 'Grupo AD (Dominio)', order: 1},
    'GRUPO_ADMIN_LINUX': {block: 'sudo_groups', label: 'Grupo Local', order: 2},
    'GRUPO_DASTI': {block: 'sudo_groups', label: 'Grupo DASTI', order: 3}
};
const groupLabels = {
    'sudo_groups': 'Grupos com privilegio sudo'
};

const variableOptions = {
    'PROXY_MODE': ['NONE', 'MANUAL', 'PAC'],
    'REPOSITORY_MODE': ['PUBLIC', 'MIRROR', 'HYBRID', 'CUSTOM'],
    'REMOTE_METHOD': ['ssh', 'xrdp', 'anydesk', 'rustdesk'],
    'PROXY_PORTA': ['80', '8080', '3128', '8888'],
    'DESKTOP_ENV': ['', 'cinnamon', 'mate', 'gnome', 'xfce', 'kde', 'lxde'],
    'DISPLAY_MANAGER': ['', 'lightdm', 'gdm3', 'sddm'],
    'AUTH_METHOD': ['sssd', 'winbind', 'both'],
    'THEME': ['DEFAULT', 'Adwaita', 'Adwaita-dark', 'Arc', 'Arc-Dark', 'Breeze', 'Breeze-Dark', 'Mint-Y', 'Mint-Y-Dark', 'Numix', 'Pop', 'Yaru', 'Yaru-Dark'],
    'CONKY_PROFILE': ['default', 'minimal', 'full', 'custom'],
    'OFFLINE_AUTH_ENABLED': 'boolean',
    'INVENTORY_ENABLED': 'boolean',
    'CERTIFICATE_AUTO_INSTALL': 'boolean',
    'INSTALL_ONLYOFFICE': 'boolean',
    'INSTALL_CHROME': 'boolean',
    'INSTALL_CHROMIUM': 'boolean',
    'INSTALL_JAVA8': 'boolean',
    'INSTALL_FIREFOX52': 'boolean',
    'INSTALL_DESKTOP': 'boolean',
    'VNC_ENABLED': 'boolean'
};

const conkyPositions = ['top_left', 'top_right', 'top_middle', 'middle_left', 'middle_right', 'bottom_left', 'bottom_right', 'bottom_middle'];

const roleLabels = {
    'admin_gap': 'Admin GAP',
    'operador_om': 'Operador OM',
    'auditor': 'Auditor'
};

// ============ INITIALIZATION ============

document.addEventListener('DOMContentLoaded', async () => {
    document.querySelectorAll('.modal').forEach(m => m.classList.add('hidden'));

    try {
        const session = await API.get('session');
        if (!session.success) { location.href = '/login.html'; return; }
        currentUser = session.data;
        applyRolePermissions();
        await loadDashboard();
        await loadOrganizations();
        setupEventListeners();
    } catch (e) {
        console.error('Init error:', e);
        location.href = '/login.html';
    }
});

function applyRolePermissions() {
    const role = currentUser?.role;
    document.getElementById('user-name').textContent = currentUser?.username || 'Usuario';
    document.getElementById('user-initial').textContent = (currentUser?.username || 'U').charAt(0).toUpperCase();
    document.getElementById('user-role').textContent = roleLabels[role] || role;

    ['nav-scripts-core', 'nav-users', 'btn-new-org', 'btn-new-user'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.classList.toggle('hidden', role !== 'admin_gap');
    });

    ['nav-audit'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.classList.toggle('hidden', role !== 'admin_gap' && role !== 'auditor');
    });
}

// ============ VIEW MANAGEMENT ============

function showView(viewName) {
    ['view-dashboard', 'view-organizations', 'view-om-detail', 'view-scripts-core', 'view-users', 'view-stations', 'view-audit'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.classList.add('hidden');
    });

    document.querySelectorAll('.nav-item').forEach(btn => btn.classList.remove('active'));

    const view = document.getElementById(`view-${viewName}`);
    if (view) view.classList.remove('hidden');

    const titles = {
        dashboard: ['Dashboard', 'Visao geral do sistema'],
        organizations: ['Organizacoes', 'Dashboard de Organizacoes Militares'],
        'scripts-core': ['Scripts Core', 'Scripts do sistema'],
        users: ['Usuarios', 'Gerenciamento de usuarios'],
        stations: ['Estacoes', 'Maquinas registradas'],
        audit: ['Auditoria', 'Log de eventos']
    };

    if (titles[viewName]) {
        document.getElementById('page-title').textContent = titles[viewName][0];
        document.getElementById('page-subtitle').textContent = titles[viewName][1];
    }

    const navBtn = document.querySelector(`.nav-item[data-view="${viewName}"]`);
    if (navBtn) navBtn.classList.add('active');

    switch (viewName) {
        case 'dashboard': loadDashboard(); break;
        case 'organizations': loadOrganizationsDashboard(); break;
        case 'users': loadUsers(); break;
        case 'scripts-core': loadAllScripts(); break;
        case 'stations': loadStations(); break;
        case 'audit': loadAuditEvents(); break;
    }
}
window.showView = showView;

// ============ OM VIEW SWITCHER ============

function switchOMView(panel) {
    const dashPanel = document.getElementById('om-view-dashboard');
    const configPanel = document.getElementById('om-view-config');
    const btnDash = document.getElementById('btn-om-dashboard');
    const btnConfig = document.getElementById('btn-om-config');

    if (panel === 'dashboard') {
        dashPanel.classList.remove('hidden');
        configPanel.classList.add('hidden');
        btnDash.classList.replace('btn-secondary', 'btn-primary');
        btnConfig.classList.replace('btn-primary', 'btn-secondary');
    } else {
        dashPanel.classList.add('hidden');
        configPanel.classList.remove('hidden');
        btnConfig.classList.replace('btn-secondary', 'btn-primary');
        btnDash.classList.replace('btn-primary', 'btn-secondary');
    }
}
window.switchOMView = switchOMView;

// ============ GLOBAL DASHBOARD ============

async function loadDashboard() {
    const res = await API.get('dashboard');
    if (!res.success) return;

    const stats = res.data;
    document.getElementById('dash-orgs').textContent = stats.organizations || 0;
    document.getElementById('dash-scripts').textContent = stats.scripts || 0;
    document.getElementById('dash-vars').textContent = stats.variables || 0;
    document.getElementById('dash-bundles').textContent = stats.bundles_this_month || 0;
    document.getElementById('dash-stations-online').textContent = stats.stations_online || 0;
    document.getElementById('dash-stations-outdated').textContent = stats.stations_outdated || 0;

    const stationsEl = document.getElementById('recent-stations');
    if (stationsEl) {
        if (stats.recent_stations?.length) {
            stationsEl.innerHTML = `
                <table class="w-full text-sm">
                    <thead><tr class="bg-slate-900">
                        <th class="px-3 py-2 text-left text-slate-400">Hostname</th>
                        <th class="px-3 py-2 text-left text-slate-400">IP</th>
                        <th class="px-3 py-2 text-left text-slate-400">Check-in</th>
                        <th class="px-3 py-2 text-left text-slate-400">OM</th>
                        <th class="px-3 py-2 text-left text-slate-400">Status</th>
                    </tr></thead>
                    <tbody>
                        ${stats.recent_stations.map(s => `
                            <tr class="border-b border-slate-700">
                                <td class="px-3 py-2">${Utils.escapeHtml(s.hostname)}</td>
                                <td class="px-3 py-2">${Utils.escapeHtml(s.ip_address || '-')}</td>
                                <td class="px-3 py-2">${Utils.formatDate(s.last_checkin)}</td>
                                <td class="px-3 py-2">${Utils.escapeHtml(s.org_acronym || '-')}</td>
                                <td class="px-3 py-2"><span class="badge ${s.status === 'Atualizado' ? 'badge-success' : 'badge-warning'}">${s.status}</span></td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>`;
        } else {
            stationsEl.innerHTML = '<p class="text-slate-400 text-center py-4">Nenhuma estacao registrada</p>';
        }
    }

    const orgsEl = document.getElementById('recent-orgs');
    if (orgsEl && stats.recent_orgs?.length) {
        orgsEl.innerHTML = stats.recent_orgs.map(o => `
            <div class="p-3 bg-slate-800 rounded-lg border border-slate-700 flex items-center justify-between mb-2">
                <div class="flex items-center gap-2">
                    <span class="font-semibold text-blue-400">${Utils.escapeHtml(o.acronym)}</span>
                    <span class="text-slate-300">${Utils.escapeHtml(o.name)}</span>
                </div>
                <button onclick="selectOrganization(${o.id})" class="text-sm text-blue-400 hover:text-blue-300">Ver</button>
            </div>
        `).join('');
    }
}

// ============ ORGANIZATIONS DASHBOARD ============

async function loadOrganizationsDashboard() {
    const [orgsRes, dashRes] = await Promise.all([
        API.get('organizations'),
        API.get('dashboard')
    ]);

    if (!orgsRes.success) return;
    const orgs = orgsRes.data || [];

    const dash = dashRes.success ? dashRes.data : {};

    document.getElementById('orgs-dash-total').textContent = orgs.length;
    document.getElementById('orgs-dash-stations').textContent = dash.stations_total || orgs.reduce((a, o) => a + (o.station_count || 0), 0);
    document.getElementById('orgs-dash-online').textContent = dash.stations_online || 0;
    document.getElementById('orgs-dash-bundles').textContent = dash.bundles_this_month || 0;

    const searchWrapper = document.getElementById('orgs-search-wrapper');
    if (searchWrapper) searchWrapper.style.display = orgs.length > 3 ? 'block' : 'none';

    const grid = document.getElementById('orgs-cards-grid');
    if (!grid) return;

    if (orgs.length === 0) {
        grid.innerHTML = '<p class="text-slate-400 text-center py-8">Nenhuma organizacao cadastrada.</p>';
        return;
    }

    grid.innerHTML = orgs.map(org => {
        const sigla = Utils.escapeHtml(org.acronym || '');
        const nome = Utils.escapeHtml(org.name || '');
        const dominio = Utils.escapeHtml(org.domain || '');
        const scripts = org.script_count || 0;
        const stations = org.station_count || 0;
        const bundles = org.bundle_count || 0;
        const conformity = org.conformity != null ? org.conformity : 0;
        const confClass = conformity >= 80 ? 'green' : conformity >= 50 ? 'amber' : 'red';
        const allUpdated = org.all_updated != null ? org.all_updated : (conformity >= 100);

        const logoHtml = org.logo_url
            ? `<div class="org-logo"><img class="org-logo-img" src="${Utils.escapeHtml(org.logo_url)}" alt="${sigla}" onerror="if(this.style)this.style.display='none';if(this.nextElementSibling&&this.nextElementSibling.style)this.nextElementSibling.style.display='flex'"></div><div class="org-logo-placeholder" style="display:none">${sigla.substring(0, 3).toUpperCase()}</div>`
            : `<div class="org-logo-placeholder">${sigla.substring(0, 3).toUpperCase()}</div>`;

        const statusHtml = allUpdated
            ? '<span class="badge badge-success">✓ Todas atualizadas</span>'
            : `<span class="badge badge-warning">${conformity}% conformes</span>`;

        return `
            <div class="card p-4 cursor-pointer hover:border-blue-500 transition-all" onclick="selectOrganization(${org.id})">
                <div class="flex items-center gap-3 mb-3">
                    ${logoHtml}
                    <div class="flex-1 min-w-0">
                        <div class="flex items-center gap-2">
                            <span class="font-semibold text-white truncate">${nome}</span>
                            <span class="badge badge-secondary">${sigla}</span>
                        </div>
                        <div class="text-xs text-slate-400 truncate">${dominio}</div>
                    </div>
                </div>
                <div class="flex gap-4 text-xs text-slate-400 mb-2">
                    <span>${scripts} scripts</span>
                    <span>${stations} estacoes</span>
                    <span>${bundles} bundles</span>
                </div>
                <div class="conformity-bar">
                    <div class="conformity-bar-fill ${confClass}" style="width: ${conformity}%"></div>
                </div>
                <div class="mt-2">${statusHtml}</div>
            </div>
        `;
    }).join('');

    const searchInput = document.getElementById('orgs-search');
    if (searchInput && !searchInput.dataset.bound) {
        searchInput.dataset.bound = '1';
        searchInput.addEventListener('input', () => {
            const q = searchInput.value.toLowerCase();
            grid.querySelectorAll('.card').forEach((card, i) => {
                const o = orgs[i];
                const text = `${o.name} ${o.acronym} ${o.domain}`.toLowerCase();
                card.style.display = text.includes(q) ? '' : 'none';
            });
        });
    }
}

// ============ PER-OM DASHBOARD ============

async function loadOMDashboard(orgId) {
    const res = await API.get('dashboard', { org_id: orgId });
    if (!res.success) return;

    const s = res.data;
    document.getElementById('om-stat-scripts').textContent = s.scripts || 0;
    document.getElementById('om-stat-vars').textContent = s.variables || 0;
    document.getElementById('om-stat-bundles').textContent = s.bundles_this_month || 0;
    document.getElementById('om-stat-online').textContent = s.stations_online || 0;
    document.getElementById('om-stat-outdated').textContent = s.stations_outdated || 0;

    // Recent stations for this OM
    const el = document.getElementById('om-recent-stations');
    if (el) {
        if (s.recent_stations?.length) {
            el.innerHTML = `
                <table class="w-full text-sm">
                    <thead><tr class="bg-slate-900">
                        <th class="px-3 py-2 text-left text-slate-400">Hostname</th>
                        <th class="px-3 py-2 text-left text-slate-400">IP</th>
                        <th class="px-3 py-2 text-left text-slate-400">Check-in</th>
                        <th class="px-3 py-2 text-left text-slate-400">Status</th>
                    </tr></thead>
                    <tbody>
                        ${s.recent_stations.map(st => `
                            <tr class="border-b border-slate-700">
                                <td class="px-3 py-2">${Utils.escapeHtml(st.hostname)}</td>
                                <td class="px-3 py-2 font-mono text-xs">${Utils.escapeHtml(st.ip_address || '-')}</td>
                                <td class="px-3 py-2">${Utils.formatDate(st.last_checkin)}</td>
                                <td class="px-3 py-2"><span class="badge ${st.status === 'Atualizado' ? 'badge-success' : 'badge-warning'}">${st.status}</span></td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>`;
        } else {
            el.innerHTML = '<p class="text-slate-400 text-center py-4">Nenhuma estacao registrada ainda.<br><span class="text-xs">Use: <code>sudo seeder-agent --org ' + Utils.escapeHtml(organizations.find(o=>o.id===orgId)?.acronym||'SIGLA') + '</code></span></p>';
        }
    }

    // Scripts overview
    const scriptsEl = document.getElementById('om-scripts-overview');
    if (scriptsEl) {
        const scripts = s.org_scripts || [];
        const core = scripts.filter(sc => sc.is_core);
        const custom = scripts.filter(sc => !sc.is_core);
        scriptsEl.innerHTML = `
            <div class="space-y-1">
                ${core.map(sc => `
                    <div class="flex items-center justify-between py-2 border-b border-slate-700">
                        <div class="flex items-center gap-2">
                            <span class="px-1.5 py-0.5 text-xs bg-blue-500/20 text-blue-400 rounded">Core</span>
                            <span class="text-sm text-white">${Utils.escapeHtml(sc.name)}</span>
                        </div>
                        <button onclick="viewScript(${sc.id})" class="text-xs text-blue-400 hover:text-blue-300">Ver</button>
                    </div>
                `).join('')}
                ${custom.map(sc => `
                    <div class="flex items-center justify-between py-2 border-b border-slate-700">
                        <div class="flex items-center gap-2">
                            <span class="px-1.5 py-0.5 text-xs bg-emerald-500/20 text-emerald-400 rounded">Custom</span>
                            <span class="text-sm text-white">${Utils.escapeHtml(sc.name)}</span>
                        </div>
                        <button onclick="viewScript(${sc.id})" class="text-xs text-blue-400 hover:text-blue-300">Ver</button>
                    </div>
                `).join('')}
                ${!scripts.length ? '<p class="text-slate-400 text-sm text-center py-4">Nenhum script</p>' : ''}
            </div>`;
    }
}

// ============ ORGANIZATIONS ============

async function loadOrganizations() {
    const res = await API.get('organizations');
    if (!res.success) return;

    organizations = res.data;
    const el = document.getElementById('om-list');
    if (!el) return;

    if (!organizations.length) {
        el.innerHTML = '<p class="text-slate-500 text-sm text-center py-4">Nenhuma organizacao</p>';
        return;
    }

    el.innerHTML = organizations.map(o => `
        <button class="nav-item w-full flex items-center gap-3 px-3 py-2 rounded-lg text-slate-300 hover:bg-slate-700 text-left"
                data-org-id="${o.id}" onclick="selectOrganization(${o.id})">
            <div class="w-10 h-10 rounded-lg bg-gradient-to-br from-blue-500 to-emerald-500 flex items-center justify-center text-white font-bold text-sm flex-shrink-0">
                ${o.logo_url
                    ? `<img src="${Utils.escapeHtml(o.logo_url)}" class="w-full h-full object-cover rounded" onerror="if(this.parentElement)this.parentElement.textContent='${o.acronym.substring(0, 3)}'">`
                    : o.acronym.substring(0, 3)}
            </div>
            <div class="min-w-0">
                <span class="block font-medium truncate">${Utils.escapeHtml(o.acronym)}</span>
                <span class="block text-xs text-slate-500 truncate">${Utils.escapeHtml(o.name)}</span>
            </div>
        </button>
    `).join('');

    const select = document.getElementById('user-organization');
    if (select) {
        select.innerHTML = '<option value="">Nenhuma</option>' + organizations.map(o =>
            `<option value="${o.id}">${Utils.escapeHtml(o.acronym)}</option>`
        ).join('');
    }
}

async function selectOrganization(orgId) {
    currentOrgId = orgId;
    const org = organizations.find(o => o.id === orgId);
    if (!org) return;

    // Update nav
    document.querySelectorAll('.nav-item[data-org-id]').forEach(btn => {
        btn.classList.toggle('active', parseInt(btn.dataset.orgId) === orgId);
    });

    // Hide all main views, show OM detail
    ['view-dashboard', 'view-scripts-core', 'view-users', 'view-stations', 'view-audit'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.classList.add('hidden');
    });
    document.getElementById('view-om-detail').classList.remove('hidden');

    // Update header
    document.getElementById('page-title').textContent = org.acronym;
    document.getElementById('page-subtitle').textContent = org.name;

    // Update OM header elements
    document.getElementById('om-display-name').textContent = org.name;
    document.getElementById('om-display-acronym').textContent = org.acronym;
    document.getElementById('om-display-domain').textContent = org.domain || 'Sem dominio';

    // Edit modal prefill
    document.getElementById('edit-org-name').value = org.name;
    document.getElementById('edit-org-acronym').value = org.acronym;
    document.getElementById('edit-org-domain').value = org.domain || '';
    document.getElementById('edit-org-description').value = org.description || '';

    // Badge
    const badge = document.getElementById('om-badge');
    badge.innerHTML = org.logo_url
        ? `<img src="${Utils.escapeHtml(org.logo_url)}" class="w-full h-full object-cover rounded-xl" onerror="if(this.parentElement)this.parentElement.textContent='${org.acronym.substring(0, 3)}'">`
        : org.acronym.substring(0, 3);

    // Show overview panel by default
    switchOMView('dashboard');
    await loadOMDashboard(orgId);

    // Pre-carregar variaveis e scripts para que as abas ja tenham dados
    loadVariables(orgId);
    loadOrgScripts(orgId);
    loadBundles(orgId);
}
window.selectOrganization = selectOrganization;

// ============ VARIABLES ============

async function loadVariables(orgId) {
    if (!orgId) orgId = currentOrgId;

    const res = await API.get('variables', { id: orgId });
    if (!res.success) {
        Toast.error(res.error || 'Erro ao carregar variaveis');
        return;
    }

    allVariables = res.data.variables || [];
    activeCategory = 'Todas';
    renderVariables(allVariables);

    try {
        const [wRes, lRes] = await Promise.all([
            API.get('wallpapers', { org_id: orgId }),
            API.get('logos', { org_id: orgId })
        ]);
        uploadedImages.wallpapers = wRes.success ? wRes.data.images : [];
        uploadedImages.logos = lRes.success ? lRes.data.images : [];
    } catch (e) {}
}

function renderVariables(vars) {
    const el = document.getElementById('vars-list');
    if (!el) return;

    if (!vars.length) {
        el.innerHTML = '<p class="text-slate-400 text-center py-8">Nenhuma variavel</p>';
        return;
    }

    // Mapa var->value para resolver dependencias e grupos
    const varByName = {};
    vars.forEach(v => { varByName[v.name] = v; });

    // Vars ocultas por dependencia
    const hiddenNames = new Set();
    Object.entries(dependentFields).forEach(([parent, children]) => {
        const p = varByName[parent];
        if (p) {
            const val = p.current_value;
            const active = val === 'true' || val === '1' || val === true;
            if (!active) children.forEach(c => hiddenNames.add(c));
        }
    });

    const cats = [...new Set(vars.map(v => v.category || 'generic'))].sort((a, b) => {
        const ai = categoryOrder.indexOf(a);
        const bi = categoryOrder.indexOf(b);
        return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
    });

    let html = '<div class="category-tabs">';
    html += `<button class="cat-tab ${activeCategory === 'Todas' ? 'active' : ''}" onclick="filterByCategory('Todas')">Todas</button>`;
    cats.forEach(c => {
        html += `<button class="cat-tab ${activeCategory === c ? 'active' : ''}" onclick="filterByCategory('${Utils.escapeHtml(c)}')">${categoryLabels[c] || c}</button>`;
    });
    html += '</div>';

    let filtered = activeCategory === 'Todas' ? vars : vars.filter(v => (v.category || 'generic') === activeCategory);
    const search = document.getElementById('var-search')?.value?.toLowerCase() || '';
    if (search) filtered = filtered.filter(v => v.name.toLowerCase().includes(search));

    // Filtrar ocultos
    filtered = filtered.filter(v => !hiddenNames.has(v.name));

    // Categoria Repositorios tem layout especial com cards por distro
    if (activeCategory === 'repositorios') {
        el.innerHTML = html + renderRepositoryCards(filtered);
        return;
    }

    // Na view "Todas", pular vars de repositorios (tem layout proprio acessivel via aba)
    const nonRepo = activeCategory === 'Todas' ? filtered.filter(v => (v.category || 'generic') !== 'repositorios') : filtered;

    html += '<div class="var-grid">';
    if (activeCategory === 'Todas') {
        cats.filter(c => c !== 'repositorios').forEach(c => {
            const catVars = nonRepo.filter(v => (v.category || 'generic') === c);
            if (!catVars.length) return;
            html += `<h4 class="col-span-2 mt-4 first:mt-0 text-sm font-semibold text-slate-400 uppercase">${categoryLabels[c] || c}</h4>`;
            html += renderVarsWithGroups(catVars);
        });
    } else {
        html += renderVarsWithGroups(nonRepo);
    }
    html += '</div>';

    el.innerHTML = html;
}

// ===== Layout especial: Repositorios por distribuicao =====
const repoDistros = [
    { name: 'Debian',   cls: 'debian',   logo: '/assets/images/distros/debian.svg',   enabledVar: 'REPOSITORY_DEBIAN_ENABLED', urlVar: 'REPOSITORY_DEBIAN_URL', placeholder: 'http://mirror.intraer/debian' },
    { name: 'Ubuntu',   cls: 'ubuntu',   logo: '/assets/images/distros/ubuntu.svg',   enabledVar: 'REPOSITORY_UBUNTU_ENABLED', urlVar: 'REPOSITORY_UBUNTU_URL', placeholder: 'http://mirror.intraer/ubuntu' },
    { name: 'Linux Mint', cls: 'mint',   logo: '/assets/images/distros/linuxmint.svg', enabledVar: 'REPOSITORY_MINT_ENABLED', urlVar: 'REPOSITORY_MINT_URL', placeholder: 'http://mirror.intraer/mint' },
    { name: 'Zorin OS', cls: 'zorin',    logo: '/assets/images/distros/zorin.svg',    enabledVar: 'REPOSITORY_ZORIN_ENABLED', urlVar: 'REPOSITORY_ZORIN_URL', placeholder: 'http://mirror.intraer/zorin' },
    { name: 'Padrao',   cls: 'default', logo: '/assets/images/distros/default.svg', enabledVar: null, urlVar: null, placeholder: '' }
];

function renderRepositoryCards(vars) {
    const varMap = {};
    vars.forEach(v => { varMap[v.name] = v; });

    const modeVar = varMap['REPOSITORY_MODE'];
    const fallbackVar = varMap['REPOSITORY_FALLBACK'];

    let html = '<div class="var-grid" style="grid-template-columns: 1fr;">';

    // Bloco superior: Configuracoes globais
    html += `<div class="col-span-2 mb-2 p-4 bg-slate-800/40 border border-slate-700 rounded-lg">
        <div class="text-sm font-semibold text-slate-200 mb-3">Configuracoes Globais</div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">`;

    if (modeVar) {
        html += `<div>
            <label class="block text-xs font-medium text-slate-400 mb-1">Modo de Repositorio${modeVar.is_required ? '<span class="text-red-400">*</span>' : ''}</label>
            ${renderTypedInput(modeVar)}
            <p class="text-slate-500 text-xs mt-1 font-mono">REPOSITORY_MODE</p>
        </div>`;
    }

    if (fallbackVar) {
        html += `<div>
            <label class="block text-xs font-medium text-slate-400 mb-1">Fallback (URL)</label>
            ${renderTypedInput(fallbackVar)}
            <p class="text-slate-500 text-xs mt-1 font-mono">REPOSITORY_FALLBACK</p>
        </div>`;
    }

    html += `</div></div>`;

    // Bloco inferior: Cards por distribuicao (grid 2x2)
    html += '<div class="col-span-2 mt-2 grid gap-4" style="grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));">';

    repoDistros.forEach(d => {
        const enVar = varMap[d.enabledVar];
        const urlVar = varMap[d.urlVar];
        if (!enVar && !urlVar) return;

        const enabled = enVar && (enVar.current_value === 'true' || enVar.current_value === '1' || enVar.current_value === true);

        if (d.enabledVar === null) return;

        html += `<div class="repo-card ${d.cls}">
            <div class="repo-card-header">
                <img src="${d.logo}" alt="${d.name}" onerror="if(this.parentElement)this.style.display='none'">
                <h4>${d.name}</h4>
            </div>`;

        if (enVar) {
            html += `<div class="flex items-center justify-between mb-2">
                <span class="text-xs text-slate-400">Habilitar repositorio</span>
                <label class="toggle-switch">
                    <input type="checkbox" data-var="${enVar.name}" ${enabled ? 'checked' : ''} onchange="toggleRepoUrl(this, '${d.urlVar}')">
                    <span class="toggle-slider"></span>
                </label>
            </div>`;
        }

        if (urlVar) {
            const urlStyle = enabled ? '' : 'style="display:none;"';
            html += `<div class="repo-url-wrap" ${urlStyle}>
                <input type="text" class="var-input" data-var="${urlVar.name}" value="${Utils.escapeHtml(urlVar.current_value || '')}" placeholder="${d.placeholder}">
                <p class="text-slate-500 text-xs mt-1 font-mono">${urlVar.name}</p>
            </div>`;
        }

        html += `</div>`;
    });

    html += '</div></div>';
    return html;
}

function toggleRepoUrl(checkbox, urlVarName) {
    const wrap = checkbox.closest('.repo-card').querySelector('.repo-url-wrap');
    if (wrap) wrap.style.display = checkbox.checked ? '' : 'none';
}

// Renderiza vars agrupando as que pertencem ao mesmo bloco visual (ex: sudo_groups)
function renderVarsWithGroups(vars) {
    let html = '';
    const grouped = {};
    const rest = [];
    vars.forEach(v => {
        const g = groupedVariables[v.name];
        if (g) {
            grouped[g.block] = grouped[g.block] || [];
            grouped[g.block].push(v);
        } else {
            rest.push(v);
        }
    });
    // Bloco de grupos primeiro
    Object.entries(grouped).forEach(([blockKey, blockVars]) => {
        blockVars.sort((a, b) => groupedVariables[a.name].order - groupedVariables[b.name].order);
        html += `<div class="col-span-2 mb-2 p-4 bg-slate-800/40 border border-slate-700 rounded-lg">
            <div class="text-sm font-semibold text-slate-200 mb-3">${groupLabels[blockKey] || blockKey}</div>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-3">`;
        blockVars.forEach(v => {
            const label = groupedVariables[v.name].label;
            html += `<div>
                <label class="block text-xs font-medium text-slate-400 mb-1">${Utils.escapeHtml(label)}</label>
                ${renderTypedInput(v)}
                <p class="text-slate-500 text-xs mt-1 font-mono">${Utils.escapeHtml(v.name)}</p>
            </div>`;
        });
        html += `</div></div>`;
    });
    rest.forEach(v => html += renderVarRow(v));
    return html;
}

function renderVarRow(v) {
    // Category "assets" tem layout de card dedicado (com preview + upload + remover)
    if ((v.category || '') === 'assets' || v.type === 'image') {
        return renderAssetCard(v);
    }

    const input = renderTypedInput(v);
    return `
        <div class="var-row">
            <label class="block text-sm font-medium text-slate-300 mb-1">
                ${Utils.escapeHtml(v.name)}${v.is_required ? '<span class="text-red-400">*</span>' : ''}
            </label>
            ${input}
            ${v.description ? `<p class="text-slate-500 text-xs mt-1">${Utils.escapeHtml(v.description)}</p>` : ''}
        </div>`;
}

// Rótulos amigaveis para os assets
const assetLabels = {
    'LOGO_URL': { title: 'Logo da OM', hint: 'Ícone/marca exibido no login e menus' },
    'WALLPAPER_URL': { title: 'Wallpaper (Desktop)', hint: 'Papel de parede da área de trabalho' },
    'WALLPAPER_LOGIN_URL': { title: 'Wallpaper (Login)', hint: 'Papel de parede da tela de login (greeter)' },
    'GREETER_URL': { title: 'Greeter (Boas-vindas)', hint: 'Tela de boas-vindas customizada' }
};

function renderAssetCard(v) {
    const val = v.current_value || '';
    const meta = assetLabels[v.name] || { title: v.name, hint: v.description || '' };
    const preview = val
        ? `<img src="${Utils.escapeHtml(val)}" class="asset-card-preview" alt="Preview" onerror="this.classList.add('asset-card-preview-broken')">`
        : `<div class="asset-card-preview-empty">Nenhuma imagem definida</div>`;
    const acceptTypes = v.name === 'LOGO_URL'
        ? 'image/jpeg,image/png,image/gif,image/webp,image/svg+xml'
        : 'image/jpeg,image/png,image/gif,image/webp';

    return `
        <div class="asset-card" data-var-name="${Utils.escapeHtml(v.name)}">
            <div class="asset-card-header">
                <div>
                    <div class="asset-card-title">${Utils.escapeHtml(meta.title)}</div>
                    <div class="asset-card-hint">${Utils.escapeHtml(meta.hint)}</div>
                </div>
                <span class="asset-card-varname">${Utils.escapeHtml(v.name)}</span>
            </div>
            <div class="asset-card-preview-wrap" id="asset-preview-${v.id}">
                ${preview}
            </div>
            <input type="url" data-var-id="${v.id}" value="${Utils.escapeHtml(val)}" class="var-input asset-card-url" placeholder="URL da imagem (ou faça upload)" oninput="updateAssetCardPreview(${v.id}, this.value)">
            <div class="asset-card-actions">
                <label class="asset-btn asset-btn-primary">
                    <input type="file" class="hidden" accept="${acceptTypes}" onchange="uploadAsset('${Utils.escapeHtml(v.name)}', ${v.id}, this)">
                    <i class="fas fa-upload"></i> Selecionar arquivo
                </label>
                <button type="button" class="asset-btn asset-btn-secondary" onclick="clearAsset(${v.id})" ${val ? '' : 'disabled'}>
                    <i class="fas fa-trash"></i> Remover
                </button>
            </div>
        </div>`;
}

// Preview live enquanto o usuario digita/cola a URL
function updateAssetCardPreview(varId, url) {
    const wrap = document.getElementById(`asset-preview-${varId}`);
    if (!wrap) return;
    const trimmed = (url || '').trim();
    if (trimmed) {
        wrap.innerHTML = `<img src="${Utils.escapeHtml(trimmed)}" class="asset-card-preview" alt="Preview" onerror="this.classList.add('asset-card-preview-broken')">`;
    } else {
        wrap.innerHTML = `<div class="asset-card-preview-empty">Nenhuma imagem definida</div>`;
    }
    // Ativa/desativa botao Remover
    const card = wrap.closest('.asset-card');
    if (card) {
        const removeBtn = card.querySelector('.asset-btn-secondary');
        if (removeBtn) removeBtn.disabled = !trimmed;
    }
}
window.updateAssetCardPreview = updateAssetCardPreview;

// Limpar URL (sem apagar o arquivo do servidor)
function clearAsset(varId) {
    const urlInput = document.querySelector(`input[data-var-id="${varId}"].asset-card-url`);
    if (!urlInput) return;
    urlInput.value = '';
    updateAssetCardPreview(varId, '');
    Toast.info && Toast.info('URL removida. Clique em Salvar para persistir.');
}
window.clearAsset = clearAsset;

// Upload via endpoint unificado /api/?action=upload-asset
async function uploadAsset(varName, varId, inputEl) {
    if (!inputEl.files || !inputEl.files[0]) return;
    if (!currentOrgId) { Toast.error('Selecione uma OM antes'); return; }
    const file = inputEl.files[0];

    const fd = new FormData();
    fd.append('organization_id', currentOrgId);
    fd.append('var_name', varName);
    fd.append('asset', file);

    try {
        const res = await fetch('/api/?action=upload-asset', { method: 'POST', body: fd, credentials: 'include' });
        const data = await res.json();
        if (!data.success) {
            Toast.error(data.error || 'Falha no upload');
            return;
        }
        const url = data.data.url;
        // Atualiza o input e a preview
        const urlInput = document.querySelector(`input[data-var-id="${varId}"].asset-card-url`);
        if (urlInput) urlInput.value = url;
        updateAssetCardPreview(varId, url);
        // Atualiza allVariables in-memory
        const v = allVariables.find(x => String(x.id) === String(varId));
        if (v) v.current_value = url;
        Toast.success('Imagem enviada e salva com sucesso');
    } catch (e) {
        Toast.error('Erro de rede no upload');
    } finally {
        inputEl.value = '';
    }
}
window.uploadAsset = uploadAsset;

function renderTypedInput(v) {
    const val = v.current_value || '';
    const varId = v.id;
    const opts = variableOptions[v.name];

    if (opts === 'boolean' || v.type === 'boolean') {
        const checked = val === 'true' || val === '1' || val === true;
        const hasDeps = dependentFields[v.name] ? 'data-parent-toggle="1"' : '';
        return `
            <label class="toggle-switch">
                <input type="checkbox" data-var-id="${varId}" ${hasDeps} ${checked ? 'checked' : ''}>
                <span class="toggle-slider"></span>
            </label>
            <span class="ml-2 text-sm text-slate-300">${checked ? 'Ativo' : 'Inativo'}</span>`;
    }
    if (Array.isArray(opts)) {
        return `<select data-var-id="${varId}" class="var-select">
            ${opts.map(o => `<option value="${o}" ${val === o ? 'selected' : ''}>${o === '' ? '(auto-detectar)' : o}</option>`).join('')}
        </select>`;
    }
    if (v.type === 'tags') {
        const items = String(val).split(',').map(s => s.trim()).filter(Boolean);
        const chips = items.map((t, i) =>
            `<span class="tag-chip" data-idx="${i}">${Utils.escapeHtml(t)}<button type="button" class="tag-remove" onclick="removeTag(${varId}, ${i})" title="Remover">&times;</button></span>`
        ).join('');
        return `
            <div class="tags-wrapper" data-var-id="${varId}" data-type="tags">
                <div class="tags-list" id="tags-list-${varId}">${chips || '<span class="text-slate-500 text-xs">Nenhum item</span>'}</div>
                <input type="text" class="tag-input" placeholder="Digite e pressione Enter" onkeydown="handleTagInput(event, ${varId})">
                <input type="hidden" data-var-id="${varId}" data-type="tags-hidden" value="${Utils.escapeHtml(items.join(','))}">
            </div>`;
    }
    if (v.type === 'image' || (v.name.endsWith('_URL') && ['WALLPAPER_URL','WALLPAPER_LOGIN_URL','LOGO_URL','GREETER_URL'].includes(v.name))) {
        // Vars de imagem sao renderizadas via renderAssetCard (card completo).
        // Este fallback so e usado se alguem chamar renderTypedInput diretamente (ex: em modais).
        const preview = val
            ? `<img src="${Utils.escapeHtml(val)}" class="asset-preview" onerror="if(this.style)this.style.display='none'" alt="Preview">`
            : `<div class="asset-preview-empty">Sem imagem</div>`;
        return `
            <div class="asset-field">
                ${preview}
                <input type="url" data-var-id="${varId}" value="${Utils.escapeHtml(val)}" class="var-input" placeholder="URL da imagem" oninput="updateAssetPreview(this)">
            </div>`;
    }
    if (v.type === 'json_conky' || v.name === 'CONKY_CONFIG') {
        return renderConkyPanel(v, varId, val);
    }
    if (v.type === 'array') {
        let ph = 'Separe multiplos valores por virgula';
        if (v.name === 'JAVA_EXCEPTIONS') ph = 'Uma URL por linha';
        if (v.name === 'SSH_GROUPS') ph = 'Um grupo por linha (ex: linux-admins, Domain Admins)';
        return `<textarea data-var-id="${varId}" rows="2" class="var-textarea" placeholder="${ph}">${Utils.escapeHtml(val)}</textarea>`;
    }
    if (v.type === 'url' || v.name.includes('URL')) {
        let ph = '';
        if (v.name === 'BASE_URL') ph = ' placeholder="https://seederlinux.SUA-OM.intraer"';
        else if (v.name === 'SEEDER_SERVER') ph = ' placeholder="https://seederlinux.SUA-OM.intraer"';
        let note = '';
        if (v.name === 'SEEDER_SERVER') note = '<div class="var-hint" style="font-size:0.8em;color:var(--text-muted);margin-top:4px">Configure este FQDN no DNS ou adicione ao /etc/hosts das estacoes.</div>';
        return `<input type="url" data-var-id="${varId}" value="${Utils.escapeHtml(val)}" class="var-input"${ph}>${note}`;
    }
    if (v.type === 'ip' || v.name.includes('IP') || v.name.includes('DNS')) {
        return `<input type="text" data-var-id="${varId}" value="${Utils.escapeHtml(val)}" class="var-input font-mono">`;
    }
    if (v.type === 'password') {
        const alertBadge = v.name === 'ADMIN_PASSWORD_B64'
            ? '<div class="var-security-alert" style="color:var(--error);font-size:0.8em;margin-top:4px">ATENCAO: Esta senha aparece codificada (base64) no bundle. Proteja o arquivo gerado.</div>'
            : '';
        return `<input type="password" data-var-id="${varId}" value="${Utils.escapeHtml(val)}" class="var-input">${alertBadge}`;
    }
    return `<input type="text" data-var-id="${varId}" value="${Utils.escapeHtml(val)}" class="var-input">`;
}

// ============ CONKY EXPANDED PANEL ============
function renderConkyPanel(v, varId, val) {
    let cfg;
    try { cfg = JSON.parse(val || '{}'); } catch (e) { cfg = {}; }
    cfg = Object.assign({
        position: 'top_right', transparent: true, color_text: '#FFFFFF', color_bg: '#000000',
        font_size: 10, font_size_hostname: 14, gap_x: 10, gap_y: 40,
        show_cpu: true, show_ram: true, show_disk: true, disk_partition: '/',
        show_network: true, network_interface: 'eth0', show_top_processes: true,
        show_datetime: true, show_hostname: true, update_interval: 1.0
    }, cfg);

    const posOpts = conkyPositions.map(p => `<option value="${p}" ${cfg.position===p?'selected':''}>${p}</option>`).join('');

    return `
    <div class="conky-panel" data-var-id="${varId}" data-type="json_conky">
        <input type="hidden" data-var-id="${varId}" data-type="conky-hidden" id="conky-hidden-${varId}" value='${JSON.stringify(cfg).replace(/'/g,"&apos;")}'>
        <div class="conky-section conky-section-hostname">
            <div class="conky-section-title">Hostname (destaque)</div>
            <div class="conky-grid">
                <label class="conky-inline"><input type="checkbox" ${cfg.show_hostname?'checked':''} onchange="updateConkyField(${varId},'show_hostname',this.checked)">Mostrar Hostname</label>
                <label>Tamanho da fonte (hostname)<input type="number" min="8" max="32" class="var-input" value="${cfg.font_size_hostname}" onchange="updateConkyField(${varId},'font_size_hostname',parseInt(this.value))"></label>
            </div>
        </div>
        <div class="conky-section">
            <div class="conky-section-title">Aparencia</div>
            <div class="conky-grid">
                <label>Posicao<select class="var-select" onchange="updateConkyField(${varId},'position',this.value)">${posOpts}</select></label>
                <label class="conky-inline">Transparente<input type="checkbox" ${cfg.transparent?'checked':''} onchange="updateConkyField(${varId},'transparent',this.checked)"></label>
                <label>Cor do texto<input type="color" class="conky-color" value="${cfg.color_text}" onchange="updateConkyField(${varId},'color_text',this.value)"></label>
                <label>Cor de fundo<input type="color" class="conky-color" value="${cfg.color_bg}" onchange="updateConkyField(${varId},'color_bg',this.value)"></label>
                <label>Tamanho da fonte<input type="number" min="6" max="24" class="var-input" value="${cfg.font_size}" onchange="updateConkyField(${varId},'font_size',parseInt(this.value))"></label>
                <label>Margem X (gap_x)<input type="number" min="0" max="500" class="var-input" value="${cfg.gap_x}" onchange="updateConkyField(${varId},'gap_x',parseInt(this.value))"></label>
                <label>Margem Y (gap_y)<input type="number" min="0" max="500" class="var-input" value="${cfg.gap_y}" onchange="updateConkyField(${varId},'gap_y',parseInt(this.value))"></label>
                <label>Intervalo atualizacao (s)<input type="number" min="0.1" step="0.1" class="var-input" value="${cfg.update_interval}" onchange="updateConkyField(${varId},'update_interval',parseFloat(this.value))"></label>
            </div>
        </div>
        <div class="conky-section">
            <div class="conky-section-title">Informacoes exibidas</div>
            <div class="conky-grid">
                <label class="conky-inline"><input type="checkbox" ${cfg.show_cpu?'checked':''} onchange="updateConkyField(${varId},'show_cpu',this.checked)">Mostrar CPU</label>
                <label class="conky-inline"><input type="checkbox" ${cfg.show_ram?'checked':''} onchange="updateConkyField(${varId},'show_ram',this.checked)">Mostrar RAM/Swap</label>
                <label class="conky-inline"><input type="checkbox" ${cfg.show_disk?'checked':''} onchange="updateConkyField(${varId},'show_disk',this.checked)">Mostrar Disco</label>
                <label>Particao do disco<input type="text" class="var-input font-mono" value="${Utils.escapeHtml(cfg.disk_partition)}" onchange="updateConkyField(${varId},'disk_partition',this.value)"></label>
                <label class="conky-inline"><input type="checkbox" ${cfg.show_network?'checked':''} onchange="updateConkyField(${varId},'show_network',this.checked)">Mostrar Rede</label>
                <label>Interface de rede<input type="text" class="var-input font-mono" value="${Utils.escapeHtml(cfg.network_interface)}" onchange="updateConkyField(${varId},'network_interface',this.value)"></label>
                <label class="conky-inline"><input type="checkbox" ${cfg.show_top_processes?'checked':''} onchange="updateConkyField(${varId},'show_top_processes',this.checked)">Top 3 processos</label>
                <label class="conky-inline"><input type="checkbox" ${cfg.show_datetime?'checked':''} onchange="updateConkyField(${varId},'show_datetime',this.checked)">Data/Hora</label>
            </div>
        </div>
    </div>`;
}

// ============ TAG/CHIP INPUT HANDLERS ============
function handleTagInput(e, varId) {
    if (e.key !== 'Enter' && e.key !== ',') return;
    e.preventDefault();
    const val = e.target.value.trim().replace(/,/g, '');
    if (!val) return;
    const hidden = document.querySelector(`input[data-var-id="${varId}"][data-type="tags-hidden"]`);
    const items = hidden.value ? hidden.value.split(',').map(s => s.trim()).filter(Boolean) : [];
    if (items.includes(val)) { e.target.value = ''; return; }
    items.push(val);
    hidden.value = items.join(',');
    e.target.value = '';
    refreshTagsList(varId, items);
}
window.handleTagInput = handleTagInput;

function removeTag(varId, idx) {
    const hidden = document.querySelector(`input[data-var-id="${varId}"][data-type="tags-hidden"]`);
    const items = hidden.value.split(',').map(s => s.trim()).filter(Boolean);
    items.splice(idx, 1);
    hidden.value = items.join(',');
    refreshTagsList(varId, items);
}
window.removeTag = removeTag;

function refreshTagsList(varId, items) {
    const listEl = document.getElementById(`tags-list-${varId}`);
    if (!listEl) return;
    listEl.innerHTML = items.length
        ? items.map((t, i) => `<span class="tag-chip" data-idx="${i}">${Utils.escapeHtml(t)}<button type="button" class="tag-remove" onclick="removeTag(${varId}, ${i})">&times;</button></span>`).join('')
        : '<span class="text-slate-500 text-xs">Nenhum item</span>';
}

// ============ IMAGE PREVIEW ============
function updateAssetPreview(inputEl) {
    const wrapper = inputEl.closest('.asset-field');
    if (!wrapper) return;
    const url = inputEl.value.trim();
    const oldImg = wrapper.querySelector('.asset-preview, .asset-preview-empty');
    if (oldImg) oldImg.remove();
    let previewEl;
    if (url) {
        previewEl = document.createElement('img');
        previewEl.src = url;
        previewEl.className = 'asset-preview';
        previewEl.alt = 'Preview';
        previewEl.onerror = () => { previewEl.style.display = 'none'; };
    } else {
        previewEl = document.createElement('div');
        previewEl.className = 'asset-preview-empty';
        previewEl.textContent = 'Sem imagem';
    }
    wrapper.insertBefore(previewEl, inputEl);
}
window.updateAssetPreview = updateAssetPreview;

// ============ CONKY FIELD UPDATE ============
function updateConkyField(varId, field, value) {
    const hidden = document.getElementById(`conky-hidden-${varId}`);
    if (!hidden) return;
    let cfg;
    try { cfg = JSON.parse(hidden.value.replace(/&apos;/g, "'")); } catch (e) { cfg = {}; }
    cfg[field] = value;
    hidden.value = JSON.stringify(cfg);
}
window.updateConkyField = updateConkyField;

function filterByCategory(c) {
    activeCategory = c;
    renderVariables(allVariables);
}
window.filterByCategory = filterByCategory;

async function saveVariables() {
    if (!currentOrgId) return;

    const updates = {};
    // Coleta apenas UM input por variable_id (prefere o "hidden" com dados serializados)
    const collected = {};
    document.querySelectorAll('[data-var-id]').forEach(el => {
        const varId = el.dataset.varId;
        const dtype = el.dataset.type;
        let value;
        if (el.type === 'checkbox' && !dtype) {
            value = el.checked ? 'true' : 'false';
        } else if (dtype === 'tags-hidden' || dtype === 'conky-hidden') {
            value = el.value;
        } else if (el.tagName === 'INPUT' && el.type === 'file') {
            return; // ignora file inputs
        } else if (dtype === 'tags' || dtype === 'json_conky') {
            return; // wrapper — ja tratado pelo hidden
        } else {
            value = el.value;
        }
        // Prefere valores de hidden (mais confiaveis para tags/conky)
        if (!(varId in collected) || dtype === 'tags-hidden' || dtype === 'conky-hidden') {
            collected[varId] = value;
        }
    });
    Object.assign(updates, collected);

    const res = await API.post('variables-update', { organization_id: currentOrgId, variables: updates });
    if (res.success) {
        Toast.success('Variaveis salvas com sucesso');
        loadVariables(currentOrgId);
    } else {
        Toast.error(res.error || 'Erro ao salvar');
    }
}
window.saveVariables = saveVariables;

// Re-render vars quando toggle "pai" muda (para esconder/mostrar dependentes)
document.addEventListener('change', (e) => {
    if (e.target && e.target.matches('input[type="checkbox"][data-parent-toggle="1"]')) {
        // Atualiza current_value em allVariables e re-renderiza
        const varId = e.target.dataset.varId;
        const v = allVariables.find(x => String(x.id) === String(varId));
        if (v) {
            v.current_value = e.target.checked ? 'true' : 'false';
            renderVariables(allVariables);
        }
    }
});

async function addVariable(e) {
    e.preventDefault();

    const name = document.getElementById('new-var-name').value.trim();
    const type = document.getElementById('new-var-type').value;
    const value = document.getElementById('new-var-value').value;
    const description = document.getElementById('new-var-description').value;
    const category = document.getElementById('new-var-category').value;
    const required = document.getElementById('new-var-required').checked;

    if (!name) { Toast.error('Nome da variavel obrigatorio'); return; }

    const res = await API.post('variable-add', { organization_id: currentOrgId, name, value, type, description, category, required });
    if (res.success) {
        Toast.success('Variavel adicionada com sucesso');
        closeModal('modal-add-variable');
        document.getElementById('add-variable-form')?.reset();
        loadVariables(currentOrgId);
    } else {
        Toast.error(res.error || 'Erro ao adicionar variavel');
    }
}
window.addVariable = addVariable;

function selectGalleryImage(url, varId, el) {
    const input = document.querySelector(`input[data-var-id="${varId}"], textarea[data-var-id="${varId}"]`);
    if (input) input.value = url;
    const gallery = el.closest('.image-gallery');
    gallery.querySelectorAll('.gallery-thumb').forEach(t => t.classList.remove('selected'));
    el.classList.add('selected');
}
window.selectGalleryImage = selectGalleryImage;

async function handleImageUpload(type, varId, inputEl) {
    const file = inputEl.files[0];
    if (!file || !currentOrgId) return;

    const fd = new FormData();
    fd.append(type, file);
    fd.append('organization_id', currentOrgId);

    Toast.info('Enviando arquivo...');
    const res = await API.postMultipart(`upload-${type}`, fd);
    if (res.success) {
        Toast.success('Arquivo enviado com sucesso');
        const inp = document.querySelector(`input[data-var-id="${varId}"]`);
        if (inp) inp.value = res.data.url;
        const gallery = document.getElementById(`${type}-gallery`);
        if (gallery) {
            gallery.querySelectorAll('.gallery-thumb').forEach(t => t.classList.remove('selected'));
            const item = document.createElement('div');
            item.className = 'gallery-thumb selected';
            item.innerHTML = `<img src="${res.data.thumbnail || res.data.url}" alt="${res.data.filename}">`;
            item.onclick = () => selectGalleryImage(res.data.url, varId, item);
            gallery.insertBefore(item, gallery.firstChild);
        }
    } else {
        Toast.error(res.error || 'Erro no upload');
    }
}
window.handleImageUpload = handleImageUpload;

// ============ TABS ============

function switchTab(tabName) {
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.tab === tabName);
    });
    document.querySelectorAll('.tab-content').forEach(c => c.classList.add('hidden'));
    document.getElementById(`tab-${tabName}`)?.classList.remove('hidden');

    if (tabName === 'scripts') loadOrgScripts(currentOrgId);
    if (tabName === 'variables') loadVariables(currentOrgId);
}
window.switchTab = switchTab;

// ============ SCRIPTS ============

async function loadAllScripts() {
    const res = await API.get('scripts');
    if (!res.success) return;

    const core = res.data.filter(s => s.is_core);
    const custom = res.data.filter(s => !s.is_core);

    const el = document.getElementById('scripts-list');
    if (!el) return;

    el.innerHTML = `
        <div class="mb-6">
            <h4 class="text-sm font-semibold text-slate-400 uppercase mb-3">Scripts Core (${core.length})</h4>
            <div class="space-y-2">
                ${core.map(s => `
                    <div class="p-4 bg-slate-900 rounded-lg border border-slate-700 flex justify-between items-center">
                        <div>
                            <span class="font-medium text-white">${Utils.escapeHtml(s.name)}</span>
                            <span class="text-slate-500 text-sm ml-2">${Utils.escapeHtml(s.filename)}</span>
                            <span class="ml-2 px-2 py-0.5 text-xs bg-blue-500/20 text-blue-400 rounded">Core</span>
                        </div>
                        <button onclick="viewScript(${s.id})" class="text-blue-400 hover:text-blue-300 text-sm">Visualizar</button>
                    </div>
                `).join('') || '<p class="text-slate-500 text-sm">Nenhum</p>'}
            </div>
        </div>
        <div>
            <div class="flex justify-between mb-3">
                <h4 class="text-sm font-semibold text-slate-400 uppercase">Scripts Custom (${custom.length})</h4>
                <button onclick="openModal('modal-new-script')" class="text-sm text-blue-400 hover:text-blue-300">+ Novo</button>
            </div>
            <div class="space-y-2">
                ${custom.map(s => `
                    <div class="p-4 bg-slate-900 rounded-lg border border-slate-700 flex justify-between items-center">
                        <div>
                            <span class="font-medium text-white">${Utils.escapeHtml(s.name)}</span>
                            <span class="text-slate-500 text-sm ml-2">${Utils.escapeHtml(s.filename)}</span>
                        </div>
                        <div class="flex gap-2">
                            <button onclick="viewScript(${s.id})" class="text-blue-400 hover:text-blue-300 text-sm">Visualizar</button>
                            <button onclick="editScript(${s.id})" class="text-amber-400 hover:text-amber-300 text-sm">Editar</button>
                            <button onclick="deleteScript(${s.id})" class="text-red-400 hover:text-red-300 text-sm">Excluir</button>
                        </div>
                    </div>
                `).join('') || '<p class="text-slate-500 text-sm">Nenhum</p>'}
            </div>
        </div>`;
}

async function loadOrgScripts(orgId) {
    if (!orgId) orgId = currentOrgId;
    const res = await API.get('scripts', { org_id: orgId });
    if (!res.success) return;

    const scripts = res.data || [];
    const core = scripts.filter(s => s.is_core);
    const custom = scripts.filter(s => !s.is_core);
    const currentList = scriptTab === 'Core' ? core : custom;

    const el = document.getElementById('org-scripts-list');
    if (!el) return;

    el.innerHTML = currentList.map(s => `
        <div class="flex items-center justify-between p-3 bg-slate-900 rounded border border-slate-700 mb-1">
            <div class="flex items-center gap-3">
                <input type="checkbox" class="script-checkbox" value="${s.id}" checked>
                <div>
                    <span class="text-white">${Utils.escapeHtml(s.name)}</span>
                    <span class="text-slate-500 text-sm ml-2">v${s.version || 1}</span>
                    ${s.is_core ? '<span class="ml-2 px-2 py-0.5 text-xs bg-blue-500/20 text-blue-400 rounded">Core</span>' : ''}
                </div>
            </div>
            <button onclick="viewScript(${s.id})" class="text-blue-400 hover:text-blue-300 text-sm">Ver</button>
        </div>
    `).join('') || '<p class="text-slate-500 text-sm">Nenhum script</p>';
}

function switchScriptTab(type) {
    scriptTab = type;
    document.querySelectorAll('.script-tab-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.scriptTab === type);
        btn.classList.toggle('btn-primary', btn.dataset.scriptTab === type);
        btn.classList.toggle('btn-secondary', btn.dataset.scriptTab !== type);
    });
    loadOrgScripts(currentOrgId);
}
window.switchScriptTab = switchScriptTab;

async function viewScript(id) {
    const res = await API.get('script', { id });
    if (!res.success) { Toast.error(res.error || 'Erro ao carregar script'); return; }

    document.getElementById('script-view-name').textContent = res.data.name;
    document.getElementById('script-view-filename').textContent = res.data.filename;
    document.getElementById('script-view-content').value = res.data.content || '';
    document.getElementById('script-view-core').textContent = res.data.is_core ? 'Sim' : 'Nao';

    document.getElementById('script-edit-btn').classList.toggle('hidden', res.data.is_core);
    document.getElementById('script-delete-btn').classList.toggle('hidden', res.data.is_core);

    if (!res.data.is_core) {
        document.getElementById('script-edit-btn').onclick = () => editScript(id);
        document.getElementById('script-delete-btn').onclick = () => deleteScript(id);
    }

    openModal('modal-view-script');
}
window.viewScript = viewScript;

async function editScript(id) {
    const res = await API.get('script', { id });
    if (!res.success) { Toast.error(res.error); return; }

    document.getElementById('edit-script-id').value = res.data.id;
    document.getElementById('edit-script-name').value = res.data.name;
    document.getElementById('edit-script-description').value = res.data.description || '';
    document.getElementById('edit-script-content').value = res.data.content || '';

    closeModal('modal-view-script');
    openModal('modal-edit-script');
}
window.editScript = editScript;

async function deleteScript(id) {
    if (!confirm('Tem certeza que deseja excluir? Esta acao nao pode ser desfeita.')) return;
    const res = await API.delete('script', id);
    if (res.success) {
        Toast.success('Script excluido');
        closeModal('modal-view-script');
        loadAllScripts();
    } else {
        Toast.error(res.error || 'Erro ao excluir');
    }
}
window.deleteScript = deleteScript;

async function createScript(e) {
    e.preventDefault();
    const name = document.getElementById('new-script-name').value.trim();
    const filename = document.getElementById('new-script-filename').value.trim();
    const description = document.getElementById('new-script-description').value;
    const content = document.getElementById('new-script-content').value;

    if (!name || !filename) { Toast.error('Nome e arquivo obrigatorios'); return; }

    const res = await API.post('script', { name, filename, description, content, is_core: false });
    if (res.success) {
        Toast.success('Script criado com sucesso');
        closeModal('modal-new-script');
        document.getElementById('new-script-form')?.reset();
        loadAllScripts();
        if (currentOrgId) loadOrgScripts(currentOrgId);
    } else {
        Toast.error(res.error || 'Erro ao criar script');
    }
}
window.createScript = createScript;

async function updateScript(e) {
    e.preventDefault();
    const id = document.getElementById('edit-script-id').value;
    const name = document.getElementById('edit-script-name').value.trim();
    const description = document.getElementById('edit-script-description').value;
    const content = document.getElementById('edit-script-content').value;

    if (!name) { Toast.error('Nome obrigatorio'); return; }

    const res = await API.put('script', id, { name, description, content });
    if (res.success) {
        Toast.success('Script atualizado com sucesso');
        closeModal('modal-edit-script');
        loadAllScripts();
        if (currentOrgId) loadOrgScripts(currentOrgId);
    } else {
        Toast.error(res.error || 'Erro ao atualizar script');
    }
}
window.updateScript = updateScript;

// ============ BUNDLE ============

async function generateBundle() {
    if (!currentOrgId) { Toast.error('Selecione uma organizacao'); return; }

    const selected = [...document.querySelectorAll('.script-checkbox:checked')].map(el => parseInt(el.value));

    // Solicitar descricao opcional do bundle
    const description = prompt('Descricao do bundle (opcional):', '');
    // Se o usuario cancelar (prompt retorna null), aborta a geracao
    if (description === null) return;

    Toast.info('Gerando bundle...');

    const res = await API.post('generate-bundle', {
        organization_id: currentOrgId,
        scripts: selected,
        description: description.trim()
    });
    if (res.success) {
        Toast.success('Bundle gerado com sucesso');
        loadBundles(currentOrgId);
    } else {
        Toast.error(res.error || 'Erro ao gerar bundle');
    }
}
window.generateBundle = generateBundle;

// ============ BUNDLES GALLERY ============

async function loadBundles(orgId) {
    if (!orgId) return;
    const el = document.getElementById('bundles-tbody');
    if (!el) return;

    el.innerHTML = '<tr><td colspan="6" class="px-4 py-8 text-center text-slate-400">Carregando bundles...</td></tr>';

    const res = await API.get('bundles', { org_id: orgId });
    if (!res.success) { el.innerHTML = '<tr><td colspan="6" class="px-4 py-8 text-center text-rose-400">Erro ao carregar</td></tr>'; return; }

    if (!res.data || res.data.length === 0) {
        el.innerHTML = '<tr><td colspan="6" class="px-4 py-8 text-center text-slate-400">Nenhum bundle gerado ainda</td></tr>';
        return;
    }

    el.innerHTML = res.data.map(b => {
        const date = new Date(b.generated_at);
        const dateStr = date.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' }) +
            ' ' + date.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
        const sizeKb = b.content_size ? Math.round(b.content_size / 1024) : '-';
        const activeBadge = b.is_active
            ? '<span class="badge badge-success">Ativo</span>'
            : '<span class="badge badge-secondary">Inativo</span>';
        const descText = b.description
            ? `<span title="${Utils.escapeHtml(b.description)}">${Utils.escapeHtml(b.description.length > 40 ? b.description.substring(0, 40) + '...' : b.description)}</span>`
            : '<span class="text-slate-500 italic">—</span>';
        return `
            <tr class="border-b border-slate-700/50" data-testid="bundle-row-${b.id}">
                <td class="px-4 py-3 text-sm text-slate-300">${dateStr}</td>
                <td class="px-4 py-3 text-sm text-slate-300">${descText}</td>
                <td class="px-4 py-3 text-sm text-slate-400">${b.scripts_count || 0}</td>
                <td class="px-4 py-3 text-sm text-slate-400">${sizeKb} KB</td>
                <td class="px-4 py-3">${activeBadge}</td>
                <td class="px-4 py-3 text-right">
                    <button data-testid="bundle-download-${b.id}" onclick="downloadBundle(${b.id})" class="text-blue-400 hover:text-blue-300 text-sm mr-2">Download</button>
                    <button data-testid="bundle-toggle-${b.id}" onclick="toggleBundleActive(${b.id})" class="text-amber-400 hover:text-amber-300 text-sm">${b.is_active ? 'Desativar' : 'Ativar'}</button>
                </td>
            </tr>`;
    }).join('');
}
window.loadBundles = loadBundles;

function downloadBundle(bundleId) {
    window.location.href = `/api/?action=bundle-by-id&id=${bundleId}`;
}
window.downloadBundle = downloadBundle;

async function toggleBundleActive(bundleId) {
    const res = await API.post('bundle-toggle', { bundle_id: bundleId });
    if (res.success) {
        Toast.success(res.message || 'Status alterado');
        if (currentOrgId) loadBundles(currentOrgId);
    } else {
        Toast.error(res.error || 'Erro');
    }
}
window.toggleBundleActive = toggleBundleActive;

// ============ USERS ============

async function loadUsers() {
    const res = await API.get('users');
    if (!res.success) return;

    const el = document.getElementById('users-tbody');
    if (!el) return;

    el.innerHTML = res.data.length ? res.data.map(u => `
        <tr>
            <td class="px-4 py-3">${Utils.escapeHtml(u.username)}</td>
            <td class="px-4 py-3">${Utils.escapeHtml(u.full_name || '-')}</td>
            <td class="px-4 py-3">${Utils.escapeHtml(u.email || '-')}</td>
            <td class="px-4 py-3"><span class="badge badge-info">${roleLabels[u.role] || u.role}</span></td>
            <td class="px-4 py-3">${Utils.escapeHtml(u.org_acronym || '-')}</td>
            <td class="px-4 py-3"><span class="badge ${u.is_active ? 'badge-success' : 'badge-secondary'}">${u.is_active ? 'Ativo' : 'Inativo'}</span></td>
            <td class="px-4 py-3 text-right">
                <button onclick="editUser(${u.id})" class="text-blue-400 hover:text-blue-300 text-sm mr-2">Editar</button>
                <button onclick="toggleUserStatus(${u.id})" class="text-amber-400 hover:text-amber-300 text-sm mr-2">${u.is_active ? 'Desativar' : 'Ativar'}</button>
                <button onclick="deleteUser(${u.id})" class="text-red-400 hover:text-red-300 text-sm">Excluir</button>
            </td>
        </tr>
    `).join('') : '<tr><td colspan="7" class="px-4 py-8 text-center text-slate-400">Nenhum usuario</td></tr>';
}

async function saveUser(e) {
    e.preventDefault();
    const password = document.getElementById('user-password').value;
    const confirmPassword = document.getElementById('user-confirm-password').value;

    if (password && password !== confirmPassword) { Toast.error('Senhas nao conferem'); return; }

    const id = document.getElementById('user-edit-id').value;
    const data = {
        username: document.getElementById('user-username').value,
        full_name: document.getElementById('user-full-name').value,
        email: document.getElementById('user-email').value,
        role: document.getElementById('user-role').value,
        organization_id: document.getElementById('user-organization').value || null,
        password, confirm_password: confirmPassword
    };

    const res = id ? await API.put('user', id, data) : await API.post('users', data);
    if (res.success) {
        Toast.success(id ? 'Usuario atualizado' : 'Usuario criado');
        closeModal('modal-user');
        loadUsers();
    } else {
        Toast.error(res.error || 'Erro ao salvar');
    }
}
window.saveUser = saveUser;

function editUser(id) {
    API.get('users').then(res => {
        if (!res.success) return;
        const user = res.data.find(u => u.id === id);
        if (!user) return;
        document.getElementById('user-edit-id').value = user.id;
        document.getElementById('user-username').value = user.username;
        document.getElementById('user-full-name').value = user.full_name || '';
        document.getElementById('user-email').value = user.email || '';
        document.getElementById('user-role').value = user.role;
        document.getElementById('user-organization').value = user.organization_id || '';
        document.getElementById('user-password').value = '';
        document.getElementById('user-confirm-password').value = '';
        document.getElementById('modal-user-title').textContent = 'Editar Usuario';
        openModal('modal-user');
    });
}
window.editUser = editUser;

async function deleteUser(id) {
    if (!confirm('Tem certeza que deseja excluir? Esta acao nao pode ser desfeita.')) return;
    const res = await API.delete('user', id);
    if (res.success) { Toast.success('Usuario excluido'); loadUsers(); }
    else Toast.error(res.error || 'Erro ao excluir');
}
window.deleteUser = deleteUser;

async function toggleUserStatus(id) {
    const res = await API.post('user', {}, { id });
    if (res.success) { Toast.success(res.message || 'Status alterado'); loadUsers(); }
    else Toast.error(res.error || 'Erro');
}
window.toggleUserStatus = toggleUserStatus;

// ============ STATIONS ============

async function loadStations() {
    const res = await API.get('stations', { org_id: currentOrgId || 0 });
    if (!res.success) return;

    const el = document.getElementById('stations-tbody');
    if (!el) return;

    el.innerHTML = res.data.length ? res.data.map(s => {
        const connBadge = { online: 'badge-success', delayed: 'badge-warning', never: 'badge-secondary' }[s.connection_status] || 'badge-secondary';
        const connLabel = { online: 'Online', delayed: 'Atrasada', never: 'Nunca' }[s.connection_status] || '-';
        return `
            <tr>
                <td class="px-4 py-3">${Utils.escapeHtml(s.hostname)}</td>
                <td class="px-4 py-3 font-mono text-sm">${Utils.escapeHtml(s.ip_address || '-')}</td>
                <td class="px-4 py-3 font-mono text-sm">${Utils.escapeHtml(s.mac_address || '-')}</td>
                <td class="px-4 py-3">${Utils.escapeHtml(s.os_name || '-')} ${Utils.escapeHtml(s.os_version || '')}</td>
                <td class="px-4 py-3">${Utils.formatDate(s.last_checkin)}</td>
                <td class="px-4 py-3"><span class="badge ${connBadge}">${connLabel}</span></td>
                <td class="px-4 py-3">${Utils.escapeHtml(s.org_acronym || '-')}</td>
            </tr>`;
    }).join('') : '<tr><td colspan="7" class="px-4 py-8 text-center text-slate-400">Nenhuma estacao</td></tr>';
}

// ============ AUDIT ============

async function loadAuditEvents() {
    const params = {};
    const startDate = document.getElementById('audit-start-date')?.value;
    const endDate = document.getElementById('audit-end-date')?.value;
    if (startDate) params.start_date = startDate;
    if (endDate) params.end_date = endDate;

    const res = await API.get('audit', params);
    if (!res.success) return;

    const el = document.getElementById('audit-tbody');
    if (!el) return;

    el.innerHTML = res.data.length ? res.data.map(e => `
        <tr>
            <td class="px-4 py-3">${Utils.formatDate(e.created_at)}</td>
            <td class="px-4 py-3">${Utils.escapeHtml(e.full_name || e.username || '-')}</td>
            <td class="px-4 py-3"><span class="badge badge-info">${Utils.escapeHtml(e.action)}</span></td>
            <td class="px-4 py-3">${Utils.escapeHtml(e.entity)}</td>
            <td class="px-4 py-3">${Utils.escapeHtml(e.org_acronym || '-')}</td>
            <td class="px-4 py-3 text-slate-400 text-sm">${Utils.escapeHtml(e.details || '-')}</td>
        </tr>
    `).join('') : '<tr><td colspan="6" class="px-4 py-8 text-center text-slate-400">Nenhum evento</td></tr>';
}

// ============ ORG CRUD ============

async function createOrganization(e) {
    e.preventDefault();
    const res = await API.post('organizations', {
        name: document.getElementById('new-org-name').value,
        acronym: document.getElementById('new-org-acronym').value.toUpperCase(),
        domain: document.getElementById('new-org-domain').value,
        description: document.getElementById('new-org-description').value,
        dc_ip: document.getElementById('new-org-dc-ip')?.value,
        dns_primario: document.getElementById('new-org-dns-primario')?.value,
        dns_secundario: document.getElementById('new-org-dns-secundario')?.value
    });
    if (res.success) {
        Toast.success('Organizacao criada');
        closeModal('modal-new-org');
        loadDashboard();
        await loadOrganizations();
        if (res.data?.id) selectOrganization(res.data.id);
    } else {
        Toast.error(res.error || 'Erro ao criar');
    }
}
window.createOrganization = createOrganization;

async function updateOrganization(e) {
    e.preventDefault();
    if (!currentOrgId) return;
    const res = await API.put('organization', currentOrgId, {
        name: document.getElementById('edit-org-name').value,
        domain: document.getElementById('edit-org-domain').value,
        description: document.getElementById('edit-org-description').value
    });
    if (res.success) {
        Toast.success('Organizacao atualizada');
        closeModal('modal-edit-org');
        loadDashboard();
        await loadOrganizations();
        selectOrganization(currentOrgId);
    } else {
        Toast.error(res.error || 'Erro ao atualizar');
    }
}
window.updateOrganization = updateOrganization;

async function deleteOrganization(id) {
    if (!confirm('Tem certeza que deseja excluir? Esta acao nao pode ser desfeita.')) return;
    const res = await API.delete('organization', id);
    if (res.success) {
        Toast.success('Organizacao excluida');
        showView('dashboard');
        loadDashboard();
        loadOrganizations();
    } else {
        Toast.error(res.error || 'Erro ao excluir');
    }
}
window.deleteOrganization = deleteOrganization;

// ============ MODALS ============

function openModal(id) {
    const modal = document.getElementById(id);
    if (modal) modal.classList.remove('hidden');
}
window.openModal = openModal;

function closeModal(id) {
    const modal = document.getElementById(id);
    if (modal) modal.classList.add('hidden');
}
window.closeModal = closeModal;

// ============ EVENT LISTENERS ============

function setupEventListeners() {
    document.getElementById('btn-logout')?.addEventListener('click', async () => {
        await API.post('logout');
        location.href = '/login.html';
    });

    document.getElementById('btn-new-org')?.addEventListener('click', () => {
        document.getElementById('new-org-form')?.reset();
        openModal('modal-new-org');
    });

    document.getElementById('btn-save-vars')?.addEventListener('click', saveVariables);
    document.getElementById('btn-generate-bundle')?.addEventListener('click', generateBundle);

    document.getElementById('btn-new-user')?.addEventListener('click', () => {
        document.getElementById('user-form')?.reset();
        document.getElementById('user-edit-id').value = '';
        document.getElementById('modal-user-title').textContent = 'Novo Usuario';
        openModal('modal-user');
    });

    document.getElementById('var-search')?.addEventListener('input', Utils.debounce(() => {
        renderVariables(allVariables);
    }, 300));

    document.querySelectorAll('.modal-backdrop').forEach(el => {
        el.addEventListener('click', (e) => {
            if (e.target === el) el.closest('.modal')?.classList.add('hidden');
        });
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') document.querySelectorAll('.modal:not(.hidden)').forEach(m => m.classList.add('hidden'));
    });
}
