#!/bin/bash
#
# ════════════════════════════════════════════════════════════════
# VAULT SINGLE-NODE INITIALIZATION SCRIPT
# ════════════════════════════════════════════════════════════════
# Este script inicializa y configura Vault con:
# - Userpass auth para usuarios humanos
# - AppRole para aplicaciones
# - Políticas con segregación por equipos
# - Secretos de ejemplo organizados por equipo
# - Auditoría habilitada
# - UI web configurada
# ════════════════════════════════════════════════════════════════

set -e

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
OUTPUT_DIR="./vault-init-output"
POLICIES_DIR="./policies"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$POLICIES_DIR"

echo "════════════════════════════════════════════════════════════"
echo "  🔐 VAULT SINGLE-NODE INITIALIZATION"
echo "  $(date)"
echo "════════════════════════════════════════════════════════════"
echo ""

# ════════════════════════════════════════════════════════════════
# FUNCIONES DE UTILIDAD
# ════════════════════════════════════════════════════════════════

log_info() {
    echo "ℹ️  $1"
}

log_success() {
    echo "✅ $1"
}

log_warning() {
    echo "⚠️  $1"
}

log_error() {
    echo "❌ $1"
}

wait_for_vault() {
    log_info "Esperando a que Vault esté listo..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" "$VAULT_ADDR/v1/sys/health" | grep -q "501\|200\|429"; then
            log_success "Vault está listo"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    log_error "Timeout esperando Vault"
    exit 1
}

# ════════════════════════════════════════════════════════════════
# 1. VERIFICAR VAULT
# ════════════════════════════════════════════════════════════════

wait_for_vault

# ════════════════════════════════════════════════════════════════
# 2. INICIALIZAR VAULT (si es necesario)
# ════════════════════════════════════════════════════════════════

log_info "Verificando estado de inicialización..."

if vault status 2>&1 | grep -q "Initialized.*true"; then
    log_warning "Vault ya está inicializado"
    
    # Intentar usar token existente
    if [ -f "$OUTPUT_DIR/root_token" ]; then
        export VAULT_TOKEN=$(cat "$OUTPUT_DIR/root_token")
        log_success "Usando root token existente"
    else
        log_error "Vault está inicializado pero no tenemos el root token"
        log_error "Por favor, exporta VAULT_TOKEN manualmente"
        exit 1
    fi
else
    log_info "Inicializando Vault por primera vez..."
    
    # Inicializar con recovery key (single-node setup)
    INIT_OUTPUT=$(vault operator init \
        -key-shares=1 \
        -key-threshold=1 \
        -format=json)
    
    # Guardar outputs
    echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]' > "$OUTPUT_DIR/unseal_key"
    echo "$INIT_OUTPUT" | jq -r '.root_token' > "$OUTPUT_DIR/root_token"
    echo "$INIT_OUTPUT" > "$OUTPUT_DIR/init_output.json"
    
    UNSEAL_KEY=$(cat "$OUTPUT_DIR/unseal_key")
    ROOT_TOKEN=$(cat "$OUTPUT_DIR/root_token")
    
    log_success "Vault inicializado"
    log_info "Unseal Key: $UNSEAL_KEY"
    log_info "Root Token: $ROOT_TOKEN"
    
    # Unseal Vault
    log_info "Unsealing Vault..."
    vault operator unseal "$UNSEAL_KEY"
    
    # Configurar token
    export VAULT_TOKEN=$ROOT_TOKEN
    
    log_success "Vault unsealed y listo"
fi

echo ""

# ════════════════════════════════════════════════════════════════
# 3. HABILITAR AUDITORÍA
# ════════════════════════════════════════════════════════════════

log_info "Configurando auditoría..."

vault audit enable file \
    file_path=/vault/logs/audit.log \
    log_raw=false \
    hmac_accessor=true \
    mode=0600 2>/dev/null || log_warning "Audit ya habilitado"

log_success "Auditoría configurada"
echo ""

# ════════════════════════════════════════════════════════════════
# 4. HABILITAR SECRETS ENGINES
# ════════════════════════════════════════════════════════════════

log_info "Habilitando secrets engines..."

# KV v2 para secretos
vault secrets enable -version=2 -path=secret kv 2>/dev/null || \
    log_warning "KV engine ya existe"

# Database para credenciales dinámicas
vault secrets enable -path=database database 2>/dev/null || \
    log_warning "Database engine ya existe"

# Transit para encriptación
vault secrets enable -path=transit transit 2>/dev/null || \
    log_warning "Transit engine ya existe"

log_success "Secrets engines habilitados"
echo ""

# ════════════════════════════════════════════════════════════════
# 5. HABILITAR MÉTODOS DE AUTENTICACIÓN
# ════════════════════════════════════════════════════════════════

log_info "Habilitando métodos de autenticación..."

# ┌────────────────────────────────────────────────────────────┐
# │ USERPASS - Para usuarios humanos vía UI o CLI             │
# └────────────────────────────────────────────────────────────┘
vault auth enable userpass 2>/dev/null || log_warning "Userpass ya habilitado"

# ┌────────────────────────────────────────────────────────────┐
# │ APPROLE - Para aplicaciones                               │
# └────────────────────────────────────────────────────────────┘
vault auth enable approle 2>/dev/null || log_warning "AppRole ya habilitado"

log_success "Métodos de autenticación habilitados"
echo ""

# ════════════════════════════════════════════════════════════════
# 6. CREAR POLÍTICAS DE ACCESO
# ════════════════════════════════════════════════════════════════

log_info "Creando políticas de acceso..."

# ┌────────────────────────────────────────────────────────────┐
# │ POLÍTICA: Team Alpha - Solo acceso a sus secretos         │
# └────────────────────────────────────────────────────────────┘
cat > "$POLICIES_DIR/team-alpha-policy.hcl" <<'EOF'
# Política para Team Alpha
# Solo pueden acceder a secret/team-alpha/*

# Leer y escribir secretos del equipo
path "secret/data/team-alpha/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Listar metadata
path "secret/metadata/team-alpha/*" {
  capabilities = ["list", "read"]
}

# Ver versiones de secretos
path "secret/data/team-alpha/*" {
  capabilities = ["read"]
  allowed_parameters = {
    "version" = []
  }
}

# Gestión de tokens propios
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Leer secretos compartidos (solo lectura)
path "secret/data/shared/*" {
  capabilities = ["read"]
}
EOF

vault policy write team-alpha "$POLICIES_DIR/team-alpha-policy.hcl"
log_success "Política 'team-alpha' creada"

# ┌────────────────────────────────────────────────────────────┐
# │ POLÍTICA: Team Beta - Solo acceso a sus secretos          │
# └────────────────────────────────────────────────────────────┘
cat > "$POLICIES_DIR/team-beta-policy.hcl" <<'EOF'
# Política para Team Beta

path "secret/data/team-beta/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/team-beta/*" {
  capabilities = ["list", "read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "secret/data/shared/*" {
  capabilities = ["read"]
}
EOF

vault policy write team-beta "$POLICIES_DIR/team-beta-policy.hcl"
log_success "Política 'team-beta' creada"

# ┌────────────────────────────────────────────────────────────┐
# │ POLÍTICA: Admin - Gestión completa (sin root)             │
# └────────────────────────────────────────────────────────────┘
cat > "$POLICIES_DIR/admin-policy.hcl" <<'EOF'
# Política de administrador (sin privilegios root)

# Gestionar todos los secretos
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Gestionar políticas
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# No puede modificar la política root
path "sys/policies/acl/root" {
  capabilities = ["deny"]
}

# Gestionar auth methods
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Ver configuración del sistema
path "sys/*" {
  capabilities = ["read", "list"]
}

# Gestionar audit devices
path "sys/audit/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Gestionar mounts
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

vault policy write admin "$POLICIES_DIR/admin-policy.hcl"
log_success "Política 'admin' creada"

# ┌────────────────────────────────────────────────────────────┐
# │ POLÍTICA: Read-Only - Solo lectura de todo                │
# └────────────────────────────────────────────────────────────┘
cat > "$POLICIES_DIR/read-only-policy.hcl" <<'EOF'
# Política de solo lectura

path "secret/data/*" {
  capabilities = ["read"]
}

path "secret/metadata/*" {
  capabilities = ["list", "read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF

vault policy write read-only "$POLICIES_DIR/read-only-policy.hcl"
log_success "Política 'read-only' creada"

# ┌────────────────────────────────────────────────────────────┐
# │ POLÍTICA: AppRole para Aplicaciones                       │
# └────────────────────────────────────────────────────────────┘
cat > "$POLICIES_DIR/app-policy.hcl" <<'EOF'
# Política para aplicaciones vía AppRole

# Acceso a secretos de producción
path "secret/data/production/*" {
  capabilities = ["read"]
}

# Credenciales dinámicas de DB
path "database/creds/app-role" {
  capabilities = ["read"]
}

# Transit encryption
path "transit/encrypt/app-*" {
  capabilities = ["update"]
}

path "transit/decrypt/app-*" {
  capabilities = ["update"]
}

# Gestión de token
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}
EOF

vault policy write app-policy "$POLICIES_DIR/app-policy.hcl"
log_success "Política 'app-policy' creada"

echo ""

# ════════════════════════════════════════════════════════════════
# 7. CREAR USUARIOS (Userpass)
# ════════════════════════════════════════════════════════════════

log_info "Creando usuarios de ejemplo..."

# Usuario: alice (Team Alpha)
vault write auth/userpass/users/alice \
    password=alice123 \
    policies=team-alpha \
    token_ttl=8h \
    token_max_ttl=24h

log_success "Usuario 'alice' creado (Team Alpha)"

# Usuario: bob (Team Beta)
vault write auth/userpass/users/bob \
    password=bob123 \
    policies=team-beta \
    token_ttl=8h \
    token_max_ttl=24h

log_success "Usuario 'bob' creado (Team Beta)"

# Usuario: admin
vault write auth/userpass/users/admin \
    password=admin123 \
    policies=admin \
    token_ttl=4h \
    token_max_ttl=12h

log_success "Usuario 'admin' creado (Administrador)"

# Usuario: viewer (solo lectura)
vault write auth/userpass/users/viewer \
    password=viewer123 \
    policies=read-only \
    token_ttl=8h \
    token_max_ttl=24h

log_success "Usuario 'viewer' creado (Read-Only)"

echo ""

# ════════════════════════════════════════════════════════════════
# 8. CREAR APPROLE PARA APLICACIONES
# ════════════════════════════════════════════════════════════════

log_info "Creando AppRole para aplicaciones..."

vault write auth/approle/role/production-app \
    token_ttl=15m \
    token_max_ttl=1h \
    token_policies="app-policy" \
    bind_secret_id=true \
    secret_id_ttl=24h \
    secret_id_num_uses=0

# Obtener credenciales
ROLE_ID=$(vault read -field=role_id auth/approle/role/production-app/role-id)
SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/production-app/secret-id)

echo "$ROLE_ID" > "$OUTPUT_DIR/app_role_id"
echo "$SECRET_ID" > "$OUTPUT_DIR/app_secret_id"

log_success "AppRole 'production-app' creado"
echo ""

# ════════════════════════════════════════════════════════════════
# 9. CREAR ESTRUCTURA DE SECRETOS
# ════════════════════════════════════════════════════════════════

log_info "Creando estructura de secretos de ejemplo..."

# Secretos de Team Alpha
vault kv put secret/team-alpha/production/database \
    host="postgres-alpha.internal" \
    port="5432" \
    username="alpha_prod_user" \
    password="alpha_prod_password_123"

vault kv put secret/team-alpha/production/api-keys \
    stripe_key="sk_live_alpha_xyz123" \
    sendgrid_key="SG.alpha.xyz123"

vault kv put secret/team-alpha/staging/database \
    host="postgres-alpha-staging.internal" \
    port="5432" \
    username="alpha_staging_user" \
    password="alpha_staging_password_123"

log_success "Secretos de Team Alpha creados"

# Secretos de Team Beta
vault kv put secret/team-beta/production/database \
    host="postgres-beta.internal" \
    port="5432" \
    username="beta_prod_user" \
    password="beta_prod_password_456"

vault kv put secret/team-beta/production/api-keys \
    aws_access_key="AKIA_BETA_ABC123" \
    aws_secret_key="beta_secret_xyz789"

vault kv put secret/team-beta/staging/database \
    host="postgres-beta-staging.internal" \
    port="5432" \
    username="beta_staging_user" \
    password="beta_staging_password_456"

log_success "Secretos de Team Beta creados"

# Secretos compartidos (todos pueden leer)
vault kv put secret/shared/company-info \
    company_name="Acme Corp" \
    support_email="support@acme.com" \
    public_api_url="https://api.acme.com"

log_success "Secretos compartidos creados"

# Secretos de producción (para AppRole)
vault kv put secret/production/app/config \
    db_host="postgres.production.internal" \
    db_port="5432" \
    api_endpoint="https://api.production.com" \
    cache_ttl="300"

log_success "Secretos de producción creados"

echo ""

# ════════════════════════════════════════════════════════════════
# 10. CONFIGURAR DATABASE ENGINE (si PostgreSQL está disponible)
# ════════════════════════════════════════════════════════════════

if nc -z postgres 5432 2>/dev/null; then
    log_info "Configurando database engine con PostgreSQL..."
    
    vault write database/config/postgresql \
        plugin_name=postgresql-database-plugin \
        allowed_roles="app-role" \
        connection_url="postgresql://{{username}}:{{password}}@postgres:5432/appdb?sslmode=disable" \
        username="vault_admin" \
        password="${POSTGRES_PASSWORD:-ChangeMeInProduction}"
    
    vault write database/roles/app-role \
        db_name=postgresql \
        creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
        default_ttl="1h" \
        max_ttl="24h"
    
    log_success "Database engine configurado"
else
    log_warning "PostgreSQL no disponible - saltando configuración de database engine"
fi

echo ""

# ════════════════════════════════════════════════════════════════
# 11. CONFIGURAR TRANSIT ENCRYPTION
# ════════════════════════════════════════════════════════════════

log_info "Configurando Transit encryption..."

vault write -f transit/keys/app-encryption \
    type=aes256-gcm96 \
    exportable=false

log_success "Transit key 'app-encryption' creada"
echo ""

# ════════════════════════════════════════════════════════════════
# RESUMEN FINAL
# ════════════════════════════════════════════════════════════════

echo "════════════════════════════════════════════════════════════"
echo "  ✅ VAULT CONFIGURADO EXITOSAMENTE"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📊 RECURSOS CREADOS:"
echo ""
echo "🔐 Usuarios (login vía UI o CLI):"
echo "   alice:alice123     → Team Alpha (secret/team-alpha/*)"
echo "   bob:bob123         → Team Beta (secret/team-beta/*)"
echo "   admin:admin123     → Administrador (gestión completa)"
echo "   viewer:viewer123   → Solo lectura (secret/*)"
echo ""
echo "🤖 AppRole (para aplicaciones):"
echo "   Role ID:    $(cat $OUTPUT_DIR/app_role_id)"
echo "   Secret ID:  $(cat $OUTPUT_DIR/app_secret_id)"
echo ""
echo "📁 Estructura de Secretos:"
echo "   secret/"
echo "   ├── team-alpha/"
echo "   │   ├── production/  (database, api-keys)"
echo "   │   └── staging/     (database)"
echo "   ├── team-beta/"
echo "   │   ├── production/  (database, api-keys)"
echo "   │   └── staging/     (database)"
echo "   ├── shared/          (company-info)"
echo "   └── production/      (app/config)"
echo ""
echo "🌐 ACCESO:"
echo "   UI Web:  ${VAULT_ADDR}/ui"
echo "   API:     ${VAULT_ADDR}"
echo ""
echo "💡 EJEMPLOS DE USO:"
echo ""
echo "   # Login como alice (Team Alpha):"
echo "   vault login -method=userpass username=alice password=alice123"
echo "   vault kv get secret/team-alpha/production/database"
echo ""
echo "   # Login vía UI:"
echo "   1. Abrir: ${VAULT_ADDR}/ui"
echo "   2. Seleccionar método: Username"
echo "   3. Usuario: alice / Password: alice123"
echo "   4. Navegar a Secrets → secret → team-alpha"
echo ""
echo "   # Login con AppRole (aplicaciones):"
echo "   vault write auth/approle/login \\"
echo "     role_id=$(cat $OUTPUT_DIR/app_role_id) \\"
echo "     secret_id=$(cat $OUTPUT_DIR/app_secret_id)"
echo ""
echo "📝 ARCHIVOS GENERADOS:"
echo "   ${OUTPUT_DIR}/root_token        (ROOT TOKEN - GUARDAR SEGURO)"
echo "   ${OUTPUT_DIR}/unseal_key        (Para unseal manual)"
echo "   ${OUTPUT_DIR}/app_role_id       (Para aplicaciones)"
echo "   ${OUTPUT_DIR}/app_secret_id     (Para aplicaciones)"
echo "   ${OUTPUT_DIR}/init_output.json  (Output completo de init)"
echo ""
echo "⚠️  SEGURIDAD:"
echo "   - Root token: Usar SOLO para configuración inicial"
echo "   - Passwords: Cambiar en producción (ejemplos son demo)"
echo "   - TLS: Habilitar para producción real"
echo "   - Backups: Configurar snapshots automáticos"
echo ""
echo "════════════════════════════════════════════════════════════"
