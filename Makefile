# ════════════════════════════════════════════════════════════════
# VAULT SINGLE-NODE MAKEFILE
# ════════════════════════════════════════════════════════════════
# Comandos útiles para gestionar Vault

.PHONY: help up down restart logs init backup restore status shell clean

# Variables
COMPOSE := docker-compose
VAULT := $(COMPOSE) exec vault vault
BACKUP_DIR := ./backups
DATE := $(shell date +%Y%m%d_%H%M%S)

## help: Mostrar ayuda
help:
	@echo "════════════════════════════════════════════════════════════"
	@echo "  🔐 Vault Single-Node - Comandos Disponibles"
	@echo "════════════════════════════════════════════════════════════"
	@echo ""
	@echo "  Gestión Básica:"
	@echo "    make up          - Iniciar Vault"
	@echo "    make down        - Detener Vault"
	@echo "    make restart     - Reiniciar Vault"
	@echo "    make logs        - Ver logs en tiempo real"
	@echo "    make status      - Ver estado de Vault"
	@echo ""
	@echo "  Inicialización:"
	@echo "    make init        - Inicializar y configurar Vault"
	@echo "    make unseal      - Unseal manual (si no tienes auto-unseal)"
	@echo ""
	@echo "  Backups:"
	@echo "    make backup      - Crear backup Raft snapshot"
	@echo "    make restore     - Restaurar desde backup"
	@echo "    make list-backups - Listar backups disponibles"
	@echo ""
	@echo "  Desarrollo:"
	@echo "    make shell       - Abrir shell en container"
	@echo "    make ui          - Abrir UI en navegador"
	@echo "    make clean       - Limpiar todo (CUIDADO)"
	@echo ""
	@echo "  PostgreSQL:"
	@echo "    make up-db       - Iniciar con PostgreSQL"
	@echo "    make psql        - Conectar a PostgreSQL"
	@echo ""
	@echo "════════════════════════════════════════════════════════════"

## up: Iniciar Vault
up:
	@echo "🚀 Iniciando Vault..."
	@$(COMPOSE) up -d vault
	@echo "✅ Vault iniciado"
	@echo "🌐 UI: http://localhost:8200/ui"

## up-db: Iniciar con PostgreSQL
up-db:
	@echo "🚀 Iniciando Vault + PostgreSQL..."
	@$(COMPOSE) --profile with-database up -d
	@echo "✅ Servicios iniciados"

## down: Detener Vault
down:
	@echo "🛑 Deteniendo Vault..."
	@$(COMPOSE) down
	@echo "✅ Vault detenido"

## restart: Reiniciar Vault
restart:
	@echo "🔄 Reiniciando Vault..."
	@$(COMPOSE) restart vault
	@echo "✅ Vault reiniciado"

## logs: Ver logs en tiempo real
logs:
	@$(COMPOSE) logs -f vault

## init: Inicializar Vault
init:
	@echo "🔧 Inicializando Vault..."
	@chmod +x init-vault.sh
	@./init-vault.sh
	@echo ""
	@echo "✅ Inicialización completa"
	@echo "📁 Credenciales guardadas en: vault-init-output/"

## unseal: Unseal manual de Vault
unseal:
	@if [ ! -f vault-init-output/unseal_key ]; then \
		echo "❌ No se encontró unseal_key. Ejecuta 'make init' primero"; \
		exit 1; \
	fi
	@echo "🔓 Unsealing Vault..."
	@$(VAULT) operator unseal $$(cat vault-init-output/unseal_key)
	@echo "✅ Vault unsealed"

## status: Ver estado de Vault
status:
	@echo "📊 Estado de Vault:"
	@$(VAULT) status || echo "⚠️  Vault no disponible o sealed"

## shell: Abrir shell en container
shell:
	@$(COMPOSE) exec vault sh

## backup: Crear backup Raft
backup:
	@mkdir -p $(BACKUP_DIR)
	@echo "💾 Creando backup..."
	@$(VAULT) operator raft snapshot save /vault/data/backup_$(DATE).snap
	@docker cp vault-prod:/vault/data/backup_$(DATE).snap $(BACKUP_DIR)/
	@echo "✅ Backup creado: $(BACKUP_DIR)/backup_$(DATE).snap"

## restore: Restaurar desde backup
restore:
	@echo "⚠️  CUIDADO: Esto sobrescribirá los datos actuales"
	@read -p "Ingresa nombre del backup (ej: backup_20250109_120000.snap): " backup; \
	if [ ! -f "$(BACKUP_DIR)/$$backup" ]; then \
		echo "❌ Backup no encontrado"; \
		exit 1; \
	fi; \
	docker cp $(BACKUP_DIR)/$$backup vault-prod:/vault/data/restore.snap; \
	$(VAULT) operator raft snapshot restore /vault/data/restore.snap; \
	echo "✅ Backup restaurado"

## list-backups: Listar backups disponibles
list-backups:
	@echo "📦 Backups disponibles:"
	@ls -lh $(BACKUP_DIR)/*.snap 2>/dev/null || echo "No hay backups"

## ui: Abrir UI en navegador
ui:
	@echo "🌐 Abriendo UI web..."
	@which xdg-open > /dev/null && xdg-open http://localhost:8200/ui || \
	 which open > /dev/null && open http://localhost:8200/ui || \
	 echo "Abrir manualmente: http://localhost:8200/ui"

## psql: Conectar a PostgreSQL
psql:
	@$(COMPOSE) exec postgres psql -U vault_admin -d appdb

## clean: Limpiar todo (ELIMINA DATOS)
clean:
	@echo "⚠️  CUIDADO: Esto eliminará TODOS los datos de Vault"
	@read -p "¿Estás seguro? [y/N]: " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		$(COMPOSE) down -v; \
		rm -rf vault-init-output policies; \
		echo "✅ Todo limpiado"; \
	else \
		echo "Operación cancelada"; \
	fi

## update: Actualizar Vault a nueva versión
update:
	@echo "📦 Actualizando Vault..."
	@echo "1. Creando backup..."
	@make backup
	@echo "2. Descargando nueva imagen..."
	@$(COMPOSE) pull vault
	@echo "3. Recreando container..."
	@$(COMPOSE) up -d vault
	@echo "✅ Actualización completa"
	@echo "⏳ Espera ~30 segundos y verifica: make status"

## health: Health check de Vault
health:
	@curl -s http://localhost:8200/v1/sys/health | jq || \
	 echo "❌ Vault no responde"

## metrics: Ver métricas de Prometheus
metrics:
	@if [ -z "$$VAULT_TOKEN" ]; then \
		echo "⚠️  VAULT_TOKEN no configurado"; \
		echo "Exporta: export VAULT_TOKEN=\$$(cat vault-init-output/root_token)"; \
		exit 1; \
	fi
	@curl -s -H "X-Vault-Token: $$VAULT_TOKEN" \
		http://localhost:8200/v1/sys/metrics?format=prometheus

## audit-logs: Ver logs de auditoría
audit-logs:
	@$(COMPOSE) exec vault tail -f /vault/logs/audit.log | jq -C .

.DEFAULT_GOAL := help
