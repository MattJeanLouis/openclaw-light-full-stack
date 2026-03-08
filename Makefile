.PHONY: setup setup-backup up down restart logs logs-openclaw logs-litellm status update backup restore cli config-get config-set channels-status clean help

COMPOSE := docker compose
SHELL := /bin/bash

# Setup
setup: ## Initial setup — interactive configuration wizard
	@bash scripts/setup.sh

setup-backup: ## Configure Google Drive backup with rclone
	@bash scripts/setup-backup.sh

# Lifecycle
up: ## Start all services
	$(COMPOSE) up -d

down: ## Stop all services
	$(COMPOSE) down

restart: ## Restart all services
	$(COMPOSE) restart

# Observability
logs: ## Follow logs (all services)
	$(COMPOSE) logs -f

logs-openclaw: ## Follow OpenClaw logs only
	$(COMPOSE) logs -f openclaw

logs-litellm: ## Follow LiteLLM logs only
	$(COMPOSE) logs -f litellm

status: ## Show service status and health
	@$(COMPOSE) ps
	@echo ""
	@echo "--- Healthchecks ---"
	@$(COMPOSE) ps --format '{{.Name}}\t{{.Status}}' | grep -E '(healthy|unhealthy|starting)' || echo "No healthcheck data yet"

# Updates
update: ## Pull new images and restart safely
	@bash scripts/update.sh

# Backup
backup: ## Backup database + configs
	@bash scripts/backup.sh

restore: ## Restore from backup
	@bash scripts/restore.sh

# OpenClaw CLI shortcuts
cli: ## Open OpenClaw CLI
	$(COMPOSE) exec openclaw openclaw

config-get: ## Show config value (usage: make config-get KEY=agents.defaults.model)
	$(COMPOSE) exec openclaw openclaw config get $(KEY)

config-set: ## Set config value (usage: make config-set KEY=... VALUE=...)
	$(COMPOSE) exec openclaw openclaw config set $(KEY) $(VALUE)

channels-status: ## Show channel connection status
	$(COMPOSE) exec openclaw openclaw channels status --probe

# Cleanup
clean: ## Remove containers, volumes, and build artifacts (DESTRUCTIVE)
	@echo "This will delete all data (database, sessions, etc.)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	$(COMPOSE) down -v
	rm -rf backups/ .openclaw-src/

# Help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
