# 🔐 HashiCorp Vault - Single Node Production Setup

## 📋 Tabla de Contenidos

1. [Descripción General](#descripción-general)
2. [Arquitectura](#arquitectura)
3. [Decisiones de Diseño](#decisiones-de-diseño)
4. [Inicio Rápido](#inicio-rápido)
5. [Uso de la UI Web](#uso-de-la-ui-web)
6. [Gestión de Usuarios y Roles](#gestión-de-usuarios-y-roles)
7. [Segregación de Secretos](#segregación-de-secretos)
8. [Actualizaciones](#actualizaciones)
9. [Backups](#backups)
10. [Monitoreo](#monitoreo)

---

## Descripción General

Este proyecto implementa **HashiCorp Vault en 1 nodo** optimizado para producción con:

- ✅ **Raft Integrated Storage** (sin dependencias externas)
- ✅ **Imagen Docker oficial** (fácil actualización)
- ✅ **UI Web habilitada** para gestión visual
- ✅ **Autenticación de usuarios** (Userpass + AppRole)
- ✅ **Políticas con segregación** por equipos
- ✅ **Auditoría completa**
- ✅ **Alta disponibilidad** vía VMware HA/vMotion

---

## Arquitectura

### Single-Node con VMware HA

```
┌─────────────────────────────────────────────────┐
│          VMware vSphere 8.0                     │
│   ┌─────────────────────────────────────┐       │
│   │  VM: vault-prod                     │       │
│   │  ┌───────────────────────────────┐  │       │
│   │  │  Docker Container             │  │       │
│   │  │  ┌─────────────────────────┐  │  │       │
│   │  │  │  Vault Server           │  │  │       │
│   │  │  │  - Raft Storage         │  │  │       │
│   │  │  │  - UI Enabled           │  │  │       │
│   │  │  │  - Port 8200            │  │  │       │
│   │  │  └─────────────────────────┘  │  │       │
│   │  └───────────────────────────────┘  │       │
│   └─────────────────────────────────────┘       │
│                                                  │
│   VMware HA: Auto-failover en <2 min           │
│   vMotion: Live migration sin downtime          │
└─────────────────────────────────────────────────┘
```

### Estructura de Datos

```
Volumes (Persistentes):
├── vault-data/           → Raft storage (datos de Vault)
├── vault-logs/           → Audit logs
└── postgres-data/        → PostgreSQL (opcional)

Configuración:
├── vault-config/         → vault.hcl
├── policies/             → HCL policies
└── vault-init-output/    → Credenciales generadas
```

---

## Decisiones de Diseño

### 1️⃣ Imagen Docker vs Binario

**✅ ELEGIDO: Imagen Docker Oficial (`hashicorp/vault:1.15`)**

**Ventajas:**
- Updates: `docker-compose pull && docker-compose up -d`
- Seguridad: Imagen firmada y escaneada por HashiCorp
- Mantenimiento: Zero effort, HashiCorp mantiene
- Certificación: Oficialmente soportada

**Comparación:**

| Aspecto | Docker Oficial | Binario Manual |
|---------|----------------|----------------|
| Actualización | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| Seguridad | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Facilidad | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| Confianza | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |

### 2️⃣ Raft vs Consul Storage

**✅ ELEGIDO: Raft Integrated Storage**

**Raft Ventajas:**
- ✅ Sin dependencias externas (Consul no necesario)
- ✅ Más simple de operar (1 sistema vs 2)
- ✅ Mejor performance en single-node
- ✅ Menos recursos (no necesitas cluster Consul)
- ✅ Snapshots nativos: `vault operator raft snapshot`

**Consul Ventajas (NO aplicables a single-node):**
- ✅ Si ya tienes Consul en producción
- ✅ Service discovery integrado
- ✅ KV store compartido con otras apps

**Comparación para Single-Node:**

| Aspecto | Raft | Consul |
|---------|------|--------|
| Simplicidad | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| Performance | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Recursos | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| Dependencias | ⭐⭐⭐⭐⭐ | ⭐⭐ |

**Diferencia Técnica:**

```
Raft:
  Vault → [Raft Storage] → /vault/data
  
Consul:
  Vault → [Network] → Consul Cluster → [Storage]
  (mayor latencia, más complejidad)
```

### 3️⃣ Single-Node Viability

**✅ VIABLE con VMware HA + Auto-unseal**

**Protección provista:**

| Tipo de Fallo | Protección | Downtime |
|---------------|------------|----------|
| Hardware failure | VMware HA | ~2-3 min |
| VM crash | VMware HA restart | ~2-3 min |
| Host failure | vMotion | 0 segundos |
| Storage failure | RAID/SAN | Depende |
| Vault sealed | Auto-unseal | ~30 seg |

**Limitaciones Single-Node:**

- ❌ No zero-downtime updates (requiere restart)
- ❌ No instant failover (solo con cluster 3+)
- ❌ Downtime durante patches de Vault

**Mitigación:**
- ✅ Ventanas de mantenimiento planificadas
- ✅ Backups automáticos frecuentes
- ✅ Auto-unseal para recovery rápida

---

## Inicio Rápido

### Prerequisitos

```bash
# Docker & Docker Compose instalados
docker --version
docker-compose --version

# Vault CLI (opcional, para administración)
# macOS
brew install vault

# Linux
wget https://releases.hashicorp.com/vault/1.15.4/vault_1.15.4_linux_amd64.zip
unzip vault_1.15.4_linux_amd64.zip
sudo mv vault /usr/local/bin/
```

### Paso 1: Clonar/Descargar Proyecto

```bash
# Estructura del proyecto
vault-single-node/
├── docker-compose.yml
├── vault-config/
│   └── vault.hcl
├── init-vault.sh
├── policies/              (se crea automáticamente)
└── vault-init-output/     (se crea automáticamente)
```

### Paso 2: Levantar Vault

```bash
# Iniciar Vault
docker-compose up -d

# Ver logs
docker-compose logs -f vault

# Verificar estado
docker-compose ps
```

### Paso 3: Inicializar Vault

```bash
# Hacer script ejecutable
chmod +x init-vault.sh

# Ejecutar inicialización
./init-vault.sh

# O manualmente con docker exec:
docker-compose exec vault sh -c "apk add bash curl jq && bash /init-vault.sh"
```

**Output esperado:**
```
════════════════════════════════════════════════════════════
  ✅ VAULT CONFIGURADO EXITOSAMENTE
════════════════════════════════════════════════════════════

🔐 Usuarios (login vía UI o CLI):
   alice:alice123     → Team Alpha
   bob:bob123         → Team Beta
   admin:admin123     → Administrador
   viewer:viewer123   → Solo lectura

🌐 ACCESO:
   UI Web:  http://localhost:8200/ui
   API:     http://localhost:8200
```

### Paso 4: Acceder a la UI

Abre tu navegador en: **http://localhost:8200/ui**

---

## Uso de la UI Web

### Login en la UI

1. **Abrir UI**: http://localhost:8200/ui
2. **Seleccionar método**: "Username" (userpass)
3. **Credenciales**:
   - Usuario: `alice`
   - Password: `alice123`
4. **Click** "Sign in"

![Vault UI Login](https://www.vaultproject.io/img/ui-login.png)

### Navegar Secretos

**Path:** Secrets → secret → team-alpha → production

```
UI Navigation:
1. Click "Secrets" en sidebar
2. Click "secret/" (KV v2 engine)
3. Click "team-alpha/"
4. Click "production/"
5. Click "database" para ver el secreto
```

### Crear un Nuevo Secreto (como alice)

**Ejemplo: Crear API Key para Stripe**

1. **Navegar** a: `secret/team-alpha/production`
2. **Click** "Create secret" (botón superior derecha)
3. **Path suffix**: `stripe-config`
4. **Version data**:
   ```
   Key: stripe_public_key
   Value: pk_test_abc123xyz
   
   Key: stripe_secret_key
   Value: sk_test_secret789
   ```
5. **Click** "Save"

### Editar un Secreto Existente

1. **Navegar** al secreto
2. **Click** "Create new version" (mantiene historial)
3. **Modificar** valores
4. **Click** "Save"

### Ver Versiones de Secretos

Vault KV v2 mantiene historial de versiones:

1. **Navegar** al secreto
2. **Click** "Version" dropdown
3. **Seleccionar** versión anterior
4. **Opcional**: "Delete" versión o "Restore" versión

### Crear Política (como admin)

1. **Login** como `admin:admin123`
2. **Navegar**: Policies → ACL Policies
3. **Click** "Create ACL policy"
4. **Name**: `team-gamma`
5. **Policy**:
   ```hcl
   path "secret/data/team-gamma/*" {
     capabilities = ["create", "read", "update", "delete", "list"]
   }
   ```
6. **Click** "Create policy"

### Crear Usuario (como admin)

1. **Navegar**: Access → Auth Methods
2. **Click** "userpass/"
3. **Click** "Create user"
4. **Username**: `charlie`
5. **Password**: `charlie123`
6. **Policies**: Seleccionar `team-gamma`
7. **Token TTL**: `8h`
8. **Click** "Save"

---

## Gestión de Usuarios y Roles

### Tipos de Autenticación

**1. Userpass (Usuarios Humanos)**
- ✅ Login vía UI o CLI
- ✅ Usuario/password
- ✅ Ideal para equipos pequeños/medianos
- ✅ Gestión simple

**2. AppRole (Aplicaciones)**
- ✅ Role ID + Secret ID
- ✅ Tokens temporales
- ✅ Renovación automática
- ✅ Ideal para apps/CI-CD

**3. OIDC (Empresarial - opcional)**
- ✅ SSO con Okta, Azure AD, Google
- ✅ Federación de identidades
- ✅ Para grandes empresas

### Crear Usuario vía CLI

```bash
# Configurar Vault CLI
export VAULT_ADDR='http://localhost:8200'

# Login como admin
vault login -method=userpass username=admin password=admin123

# Crear usuario
vault write auth/userpass/users/carlos \
    password=carlos123 \
    policies=team-alpha \
    token_ttl=8h \
    token_max_ttl=24h
```

### Crear Política vía CLI

```bash
# Crear archivo de política
cat > team-gamma-policy.hcl <<'EOF'
path "secret/data/team-gamma/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/team-gamma/*" {
  capabilities = ["list", "read"]
}
EOF

# Aplicar política
vault policy write team-gamma team-gamma-policy.hcl
```

### Asignar Política a Usuario

```bash
# Actualizar usuario existente
vault write auth/userpass/users/alice \
    policies=team-alpha,read-only

# O crear con múltiples políticas
vault write auth/userpass/users/diego \
    password=diego123 \
    policies="team-alpha,team-beta"
```

---

## Segregación de Secretos

### Estructura Organizacional

```
secret/
├── team-alpha/           ← Solo Team Alpha accede
│   ├── production/
│   │   ├── database
│   │   └── api-keys
│   └── staging/
│       └── database
│
├── team-beta/            ← Solo Team Beta accede
│   ├── production/
│   │   ├── database
│   │   └── api-keys
│   └── staging/
│       └── database
│
├── shared/               ← Todos leen (nadie escribe)
│   └── company-info
│
└── production/           ← Solo AppRole de apps
    └── app/
        └── config
```

### Matriz de Permisos

| Usuario/Role | team-alpha/* | team-beta/* | shared/* | production/* |
|--------------|--------------|-------------|----------|--------------|
| alice | ✅ R/W | ❌ | ✅ R | ❌ |
| bob | ❌ | ✅ R/W | ✅ R | ❌ |
| admin | ✅ R/W | ✅ R/W | ✅ R/W | ✅ R/W |
| viewer | ✅ R | ✅ R | ✅ R | ✅ R |
| production-app | ❌ | ❌ | ❌ | ✅ R |

### Ejemplo de Política Jerárquica

```hcl
# Para líder de equipo (puede gestionar su equipo + ver otros)
path "secret/data/team-alpha/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Ver otros equipos (solo lectura)
path "secret/data/team-*" {
  capabilities = ["read", "list"]
}

# Acceso a shared
path "secret/data/shared/*" {
  capabilities = ["read"]
}
```

---

## Actualizaciones

### Actualizar Vault a Nueva Versión

**Procedimiento Seguro:**

```bash
# 1. BACKUP COMPLETO (CRÍTICO)
docker-compose exec vault vault operator raft snapshot save /vault/data/backup-$(date +%Y%m%d).snap

# Copiar backup fuera del container
docker cp vault-prod:/vault/data/backup-$(date +%Y%m%d).snap ./backups/

# 2. Editar docker-compose.yml
# Cambiar: image: hashicorp/vault:1.15
# A:       image: hashicorp/vault:1.16

# 3. Descargar nueva imagen
docker-compose pull

# 4. Recrear container (con downtime ~30 segundos)
docker-compose up -d

# 5. Verificar
docker-compose logs -f vault

# 6. Health check
vault status
```

**Downtime esperado: 30-60 segundos**

**Rollback si falla:**

```bash
# 1. Editar docker-compose.yml a versión anterior
# 2. Recrear container
docker-compose up -d

# 3. Si necesitas restaurar data
docker-compose exec vault vault operator raft snapshot restore /vault/data/backup-YYYYMMDD.snap
```

### Actualizaciones sin Downtime (Requiere Cluster)

Para zero-downtime updates, necesitas cluster multi-nodo:

```
1. Update nodo standby
2. Promote standby a leader
3. Update old leader
4. Repeat para todos los nodos
```

---

## Backups

### Backup Manual

```bash
# Crear snapshot Raft
docker-compose exec vault vault operator raft snapshot save /vault/data/backup.snap

# Copiar fuera del container
docker cp vault-prod:/vault/data/backup.snap ./backups/backup-$(date +%Y%m%d-%H%M%S).snap

# Cifrar backup (recomendado)
gpg --encrypt --recipient your-email@company.com ./backups/backup-*.snap

# Subir a storage remoto
aws s3 cp ./backups/backup-*.snap.gpg s3://vault-backups/
```

### Backup Automático con Cron

```bash
# /etc/cron.d/vault-backup
# Cada 6 horas
0 */6 * * * root /opt/vault/scripts/backup-vault.sh

# /opt/vault/scripts/backup-vault.sh
#!/bin/bash
set -e

BACKUP_DIR="/backups/vault"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/vault_${DATE}.snap"

mkdir -p "$BACKUP_DIR"

# Crear snapshot
docker-compose -f /opt/vault/docker-compose.yml exec -T vault \
  vault operator raft snapshot save /vault/data/backup.snap

# Copiar fuera
docker cp vault-prod:/vault/data/backup.snap "$BACKUP_FILE"

# Cifrar
gpg --encrypt --recipient backup@company.com "$BACKUP_FILE"
rm "$BACKUP_FILE"

# Subir a S3
aws s3 cp "${BACKUP_FILE}.gpg" s3://vault-backups/$(date +%Y/%m/%d)/

# Retener solo últimos 90 días
find "$BACKUP_DIR" -name "*.snap.gpg" -mtime +90 -delete

echo "Backup completado: ${BACKUP_FILE}.gpg"
```

### Restaurar desde Backup

```bash
# 1. Detener Vault
docker-compose stop vault

# 2. Copiar backup al container
docker cp ./backups/backup-20250109.snap vault-prod:/vault/data/restore.snap

# 3. Iniciar Vault
docker-compose start vault

# 4. Esperar unseal (si no tienes auto-unseal)
docker-compose exec vault vault operator unseal <key>

# 5. Restaurar snapshot
docker-compose exec vault vault operator raft snapshot restore /vault/data/restore.snap

# 6. Reiniciar Vault
docker-compose restart vault
```

---

## Monitoreo

### Health Check

```bash
# Desde host
curl http://localhost:8200/v1/sys/health

# Response esperado (HTTP 200):
{
  "initialized": true,
  "sealed": false,
  "standby": false,
  "version": "1.15.4"
}
```

### Métricas Prometheus

Vault expone métricas en: http://localhost:8200/v1/sys/metrics?format=prometheus

**Prometheus config:**

```yaml
scrape_configs:
  - job_name: 'vault'
    metrics_path: '/v1/sys/metrics'
    params:
      format: ['prometheus']
    bearer_token: '<vault_token>'
    static_configs:
      - targets: ['vault-prod:8200']
```

### Logs de Auditoría

```bash
# Ver audit logs
docker-compose exec vault tail -f /vault/logs/audit.log

# Buscar accesos de un usuario
docker-compose exec vault grep "alice" /vault/logs/audit.log | jq

# Buscar operaciones de escritura
docker-compose exec vault grep '"operation":"update"' /vault/logs/audit.log | jq
```

### Alertas Recomendadas

```yaml
# Prometheus alerts
groups:
- name: vault
  rules:
  - alert: VaultSealed
    expr: vault_core_unsealed == 0
    for: 1m
    labels:
      severity: critical
  
  - alert: VaultHighLatency
    expr: vault_core_handle_request{quantile="0.99"} > 1
    for: 5m
    labels:
      severity: warning
  
  - alert: VaultAuthFailures
    expr: rate(vault_audit_log_request_failure[5m]) > 10
    for: 5m
    labels:
      severity: warning
```

---

## FAQ

**P: ¿Es seguro usar 1 nodo en producción?**  
R: Sí, con VMware HA + auto-unseal. El downtime es ~2-3 min en caso de fallo de hardware.

**P: ¿Cómo actualizo Vault?**  
R: Backup → cambiar versión en docker-compose.yml → `docker-compose pull` → `docker-compose up -d`

**P: ¿Puedo agregar más nodos después?**  
R: Sí, Raft soporta agregar nodos al cluster con `retry_join` config.

**P: ¿Los usuarios pueden crear secretos vía UI?**  
R: Sí, cada usuario solo puede crear secretos en su path asignado por política.

**P: ¿Cómo roto credenciales?**  
R: KV v2 mantiene versiones. Crea nueva versión del secreto, deploya apps, elimina versión antigua.

**P: ¿Qué pasa si se llena el disco?**  
R: Vault se pone en modo "sealed". Libera espacio y unseal. Monitorea uso de disco.

**P: ¿Necesito TLS?**  
R: Sí en producción real. Este setup usa TLS=disabled solo para demo/dev.

---

## Soporte

- **Documentación Oficial**: https://www.vaultproject.io/docs
- **Learn Vault**: https://learn.hashicorp.com/vault
- **Discuss Forum**: https://discuss.hashicorp.com/c/vault

---

**Última actualización**: Enero 2025  
**Versión**: 1.0
