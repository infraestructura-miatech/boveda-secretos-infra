# 🚀 Vault Single-Node - Guía de Inicio Rápido

## ⚡ Setup en 3 Minutos

### 1. Iniciar Vault

```bash
# Levantar Vault
docker-compose up -d

# Ver logs
docker-compose logs -f vault
```

### 2. Inicializar Vault

```bash
# Ejecutar script de inicialización
chmod +x init-vault.sh
./init-vault.sh

# O usando Make
make init
```

### 3. Acceder a la UI

Abre tu navegador en: **http://localhost:8200/ui**

**Login:**
- Método: Username
- Usuario: `alice`
- Password: `alice123`

---

## 👥 Usuarios Creados

| Usuario | Password | Rol | Acceso |
|---------|----------|-----|--------|
| alice | alice123 | Team Alpha | `secret/team-alpha/*` |
| bob | bob123 | Team Beta | `secret/team-beta/*` |
| admin | admin123 | Administrador | Todo |
| viewer | viewer123 | Solo lectura | Todo (read-only) |

---

## 📁 Estructura de Secretos

```
secret/
├── team-alpha/          ← alice puede leer/escribir
│   ├── production/
│   │   ├── database
│   │   └── api-keys
│   └── staging/
│       └── database
│
├── team-beta/           ← bob puede leer/escribir
│   ├── production/
│   │   ├── database
│   │   └── api-keys
│   └── staging/
│       └── database
│
├── shared/              ← todos pueden leer
│   └── company-info
│
└── production/          ← solo AppRole
    └── app/
        └── config
```

---

## 💡 Casos de Uso Comunes

### Crear un Secreto (UI)

1. Login como `alice`
2. Ir a: **Secrets → secret → team-alpha → production**
3. Click **"Create secret"**
4. Path: `stripe-api`
5. Agregar keys:
   ```
   public_key: pk_test_abc123
   secret_key: sk_test_xyz789
   ```
6. Click **"Save"**

### Leer un Secreto (CLI)

```bash
# Configurar
export VAULT_ADDR='http://localhost:8200'

# Login
vault login -method=userpass username=alice password=alice123

# Leer secreto
vault kv get secret/team-alpha/production/database
```

### Crear un Usuario Nuevo (UI)

1. Login como `admin`
2. **Access → Auth Methods → userpass/**
3. **Create user**
4. Username: `carlos`
5. Password: `carlos123`
6. Policies: `team-alpha`
7. **Save**

---

## 🔧 Comandos Útiles (Make)

```bash
make up            # Iniciar Vault
make down          # Detener Vault
make logs          # Ver logs
make status        # Ver estado
make backup        # Crear backup
make shell         # Abrir shell
make clean         # Limpiar todo (CUIDADO)
```

---

## 📊 Verificar Estado

```bash
# Health check
curl http://localhost:8200/v1/sys/health

# Status
docker-compose exec vault vault status

# Ver usuarios
docker-compose exec vault vault list auth/userpass/users
```

---

## 🔐 Credenciales de AppRole

Para aplicaciones, usa AppRole:

```bash
# Leer credenciales
cat vault-init-output/app_role_id
cat vault-init-output/app_secret_id

# Login programático
vault write auth/approle/login \
    role_id="$(cat vault-init-output/app_role_id)" \
    secret_id="$(cat vault-init-output/app_secret_id)"
```

---

## 🔄 Actualizar Vault

```bash
# 1. Backup
make backup

# 2. Cambiar versión en docker-compose.yml
# image: hashicorp/vault:1.16

# 3. Actualizar
make update

# 4. Verificar
make status
```

---

## 💾 Backups

```bash
# Crear backup manual
make backup

# Listar backups
make list-backups

# Restaurar backup
make restore
# (te pedirá nombre del archivo)
```

---

## ❓ Problemas Comunes

### Vault está "sealed"

```bash
# Si no tienes auto-unseal
make unseal
```

### No puedo acceder a secretos

- Verifica que el usuario tenga la política correcta
- Alice solo puede acceder a `team-alpha/*`
- Bob solo puede acceder a `team-beta/*`

### Olvidé las credenciales

```bash
# Ver root token (SOLO para emergencias)
cat vault-init-output/root_token

# Login con root
vault login $(cat vault-init-output/root_token)
```

---

## 🌐 URLs Importantes

- **UI Web**: http://localhost:8200/ui
- **API**: http://localhost:8200
- **Health**: http://localhost:8200/v1/sys/health

---

## 📚 Siguiente Paso

Lee el [README.md](README.md) completo para:
- Entender arquitectura y decisiones de diseño
- Configurar TLS para producción
- Setup de monitoreo
- Integración con aplicaciones
- Best practices de seguridad

---

## 🆘 Ayuda

**Documentación completa**: [README.md](README.md)  
**HashiCorp Docs**: https://www.vaultproject.io/docs  
**Learn Vault**: https://learn.hashicorp.com/vault
