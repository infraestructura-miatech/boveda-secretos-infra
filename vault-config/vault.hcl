# ════════════════════════════════════════════════════════════════
# VAULT SINGLE-NODE PRODUCTION CONFIGURATION
# ════════════════════════════════════════════════════════════════
# Configuración optimizada para 1 nodo en producción con:
# - Raft Integrated Storage (sin dependencias externas)
# - UI Web habilitada
# - Auditoría completa
# - TLS para producción
# ════════════════════════════════════════════════════════════════

# ────────────────────────────────────────────────────────────
# STORAGE BACKEND - Raft Integrated Storage
# ────────────────────────────────────────────────────────────
# Raft es la opción recomendada para single-node:
# ✅ Sin dependencias externas (no necesita Consul)
# ✅ Más simple de operar
# ✅ Snapshots nativos integrados
# ✅ Mejor performance en single-node
# ✅ Menos overhead de recursos

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"
  
  # Performance multiplier (1 = default)
  # Valores más altos = más throughput pero más latencia
  performance_multiplier = 1
  
  # Autopilot (Enterprise feature, pero config no causa error)
  autopilot {
    cleanup_dead_servers = true
    last_contact_threshold = "10s"
    max_trailing_logs = 1000
  }
}

# NOTA: En cluster multi-nodo, agregarías:
# retry_join {
#   leader_api_addr = "https://vault-node-2:8200"
# }

# ────────────────────────────────────────────────────────────
# LISTENER - API y UI Web
# ────────────────────────────────────────────────────────────

listener "tcp" {
  address       = "0.0.0.0:8200"
  
  # ┌──────────────────────────────────────────────────────┐
  # │ TLS CONFIGURATION                                     │
  # │ IMPORTANTE: Habilitar en producción real             │
  # └──────────────────────────────────────────────────────┘
  
  # Para desarrollo/testing:
  tls_disable   = 1
  
  # Para PRODUCCIÓN (descomentar y configurar):
  # tls_disable = 0
  # tls_cert_file = "/vault/tls/vault-cert.pem"
  # tls_key_file  = "/vault/tls/vault-key.pem"
  # tls_min_version = "tls12"
  # tls_cipher_suites = "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
  
  # ┌──────────────────────────────────────────────────────┐
  # │ TIMEOUTS Y LÍMITES                                    │
  # └──────────────────────────────────────────────────────┘
  
  http_idle_timeout = "5m"
  http_read_header_timeout = "10s"
  http_read_timeout = "30s"
  http_write_timeout = "30s"
  
  # ┌──────────────────────────────────────────────────────┐
  # │ SECURITY HEADERS                                      │
  # └──────────────────────────────────────────────────────┘
  
  custom_response_headers {
    "X-Content-Type-Options" = ["nosniff"]
    "X-Frame-Options" = ["DENY"]
    "X-XSS-Protection" = ["1; mode=block"]
    # Descomentar cuando uses HTTPS:
    # "Strict-Transport-Security" = ["max-age=31536000; includeSubDomains"]
  }
}

# ────────────────────────────────────────────────────────────
# UI WEB - Interfaz de Usuario
# ────────────────────────────────────────────────────────────
# Habilita la UI web de Vault en:
# http://localhost:8200/ui (o https en producción)

ui = true

# ────────────────────────────────────────────────────────────
# API ADDRESSES
# ────────────────────────────────────────────────────────────

# Dirección donde Vault escucha (para clientes)
api_addr = "http://127.0.0.1:8200"

# Dirección del cluster (para comunicación interna)
# En single-node no es crítico, pero debe estar configurado
cluster_addr = "http://127.0.0.1:8201"

# Nombre del cluster (opcional pero recomendado)
cluster_name = "vault-production"

# ────────────────────────────────────────────────────────────
# TELEMETRY - Métricas y Monitoreo
# ────────────────────────────────────────────────────────────

telemetry {
  # Prometheus (recomendado para producción)
  prometheus_retention_time = "30s"
  disable_hostname = false
  
  # Prefijo para métricas
  metrics_prefix = "vault"
  
  # Usage reporting (opcional)
  usage_gauge_period = "10m"
  
  # StatsD (alternativa)
  # statsd_address = "localhost:8125"
  
  # DataDog (alternativa)
  # dogstatsd_addr = "localhost:8125"
  # dogstatsd_tags = ["environment:production", "service:vault"]
}

# ────────────────────────────────────────────────────────────
# LOGGING
# ────────────────────────────────────────────────────────────

# Nivel de log: trace, debug, info, warn, error
log_level = "info"

# Formato: standard o json (json recomendado para parsing)
log_format = "json"

# Archivo de log (opcional - Docker logs van a stdout)
# log_file = "/vault/logs/vault.log"

# Rotación de logs (opcional)
# log_rotate_duration = "24h"
# log_rotate_max_files = 7

# ────────────────────────────────────────────────────────────
# SEAL CONFIGURATION
# ────────────────────────────────────────────────────────────
# Por defecto usa Shamir seal (manual unseal)
# Para auto-unseal, configura uno de estos:

# AWS KMS (recomendado si estás en AWS)
# seal "awskms" {
#   region     = "us-west-2"
#   kms_key_id = "alias/vault-unseal-key"
#   endpoint   = "https://kms.us-west-2.amazonaws.com"
# }

# Azure Key Vault (recomendado si estás en Azure)
# seal "azurekeyvault" {
#   tenant_id      = "your-tenant-id"
#   client_id      = "your-client-id"
#   client_secret  = "your-client-secret"
#   vault_name     = "your-key-vault"
#   key_name       = "vault-unseal-key"
# }

# Google Cloud KMS (recomendado si estás en GCP)
# seal "gcpckms" {
#   project     = "your-gcp-project"
#   region      = "us-west1"
#   key_ring    = "vault-keyring"
#   crypto_key  = "vault-unseal-key"
# }

# Transit (usar otro Vault como auto-unseal)
# seal "transit" {
#   address         = "https://vault-master:8200"
#   token           = "s.xxxxx"
#   disable_renewal = false
#   key_name        = "autounseal"
#   mount_path      = "transit/"
# }

# ────────────────────────────────────────────────────────────
# SECURITY SETTINGS
# ────────────────────────────────────────────────────────────

# NO deshabilitar mlock en producción (previene swap de memoria)
disable_mlock = false

# Máximo TTL para leases
max_lease_ttl = "768h"  # 32 días
default_lease_ttl = "768h"

# Cache de tokens (habilitado por defecto)
disable_cache = false

# Raw storage endpoint (solo para debugging - DESHABILITAR EN PROD)
raw_storage_endpoint = false

# ────────────────────────────────────────────────────────────────
# NOTAS IMPORTANTES PARA PRODUCCIÓN
# ────────────────────────────────────────────────────────────────
#
# 1. TLS: SIEMPRE habilitar en producción
#    - Genera certificados válidos
#    - Usa Let's Encrypt o CA interna
#
# 2. AUTO-UNSEAL: Configurar en producción
#    - AWS KMS, Azure KeyVault o GCP KMS
#    - Evita manual unseal después de reinicio
#
# 3. BACKUPS:
#    - Vault Raft snapshots: vault operator raft snapshot save
#    - Frecuencia: cada 6 horas mínimo
#    - Cifrar backups antes de almacenar
#
# 4. MONITOREO:
#    - Integrar con Prometheus + Grafana
#    - Alertas en Vault sealed, high latency, auth failures
#
# 5. LOGS:
#    - Centralizar en SIEM (ELK, Splunk, etc)
#    - Retención mínima: 90 días
#
# 6. ACTUALIZACIONES:
#    - Siempre hacer backup antes
#    - Seguir release notes de HashiCorp
#    - Testear en staging primero
#
# 7. RECURSOS:
#    - CPU: 2-4 cores mínimo
#    - RAM: 4-8 GB mínimo
#    - Disco: SSD recomendado para Raft
#
# ────────────────────────────────────────────────────────────────
