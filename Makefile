### Defensive settings for make:
#     https://tech.davis-hansson.com/p/make/
SHELL:=bash
.ONESHELL:
.SHELLFLAGS:=-eu -o pipefail -c
.SILENT:
.DELETE_ON_ERROR:
MAKEFLAGS+=--warn-undefined-variables
MAKEFLAGS+=--no-builtin-rules

CURRENT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

PLONE_VERSION=$$(cat backend/version.txt)
VOLTO_VERSION = $(shell cat ./frontend/package.json | python -c "import sys, json; print(json.load(sys.stdin)['dependencies']['@plone/volto'])")

COMPOSE_PROJECT_NAME?="kitconcept_intranet"
SOLR_ONLY_COMPOSE?=${CURRENT_DIR}/docker-compose.yml

PROJECT_NAME=kitconcept.intranet
STACK_NAME=kitconcept-intranet

# We like colors
# From: https://coderwall.com/p/izxssa/colored-makefile-for-golang-projects
RED=`tput setaf 1`
GREEN=`tput setaf 2`
RESET=`tput sgr0`
YELLOW=`tput setaf 3`

.PHONY: all
all: install

# Add the following 'help' target to your Makefile
# And add help text after each target name starting with '\#\#'
.PHONY: help
help: ## This help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: install-frontend
install-frontend:  ## Install React Frontend
	$(MAKE) -C "./frontend/" install

.PHONY: build-frontend
build-frontend:  ## Build React Frontend
	$(MAKE) -C "./frontend/" build

.PHONY: start-frontend
start-frontend:  ## Start React Frontend
	$(MAKE) -C "./frontend/" start

.PHONY: install-backend
install-backend:  ## Create virtualenv and install Plone
	$(MAKE) -C "./backend/" build-dev
	$(MAKE) create-site

.PHONY: build-backend
build-backend:  ## Build Backend
	$(MAKE) -C "./backend/" build-dev

.PHONY: create-site
create-site: ## Create a Plone site with default content
	$(MAKE) -C "./backend/" create-site

.PHONY: create-site-force
create-site-force: ## Create a Plone site with default content
	$(MAKE) -C "./backend/" create-site-force

.PHONY: start-backend
start-backend: ## Start Plone Backend
	$(MAKE) -C "./backend/" start

.PHONY: install
install:  ## Install
	@echo "Install Backend & Frontend"
	$(MAKE) install-backend
	$(MAKE) install-frontend

# TODO production build

.PHONY: build
build:  ## Build in development mode
	@echo "Build"
	$(MAKE) build-backend
	$(MAKE) install-frontend


.PHONY: start
start:  ## Start
	@echo "Starting application"
	$(MAKE) start-backend
	$(MAKE) start-frontend

.PHONY: clean
clean:  ## Clean installation
	@echo "Clean installation"
	$(MAKE) -C "./backend/" clean
	$(MAKE) -C "./frontend/" clean

.PHONY: export
export:  ## Clean installation
	@echo "Export"
	$(MAKE) -C "./backend/" export

.PHONY: format
format:  ## Format codebase
	@echo "Format codebase"
	$(MAKE) -C "./backend/" format
	$(MAKE) -C "./frontend/" format

.PHONY: i18n
i18n:  ## Update locales
	@echo "Update locales"
	$(MAKE) -C "./backend/" i18n
	$(MAKE) -C "./frontend/" i18n

.PHONY: test-backend
test-backend:  ## Test backend codebase
	@echo "Test backend"
	$(MAKE) -C "./backend/" test

.PHONY: test-frontend
test-frontend:  ## Test frontend codebase
	@echo "Test frontend"
	$(MAKE) -C "./frontend/" test

.PHONY: test
test:  test-backend test-frontend ## Test codebase

.PHONY: build-images
build-images:  ## Build docker images
	@echo "Build"
	$(MAKE) -C "./backend/" build-image
	$(MAKE) -C "./frontend/" build-image

## Docker stack
.PHONY: stack-start
stack-start:  ## Local Stack: Start Services
	@echo "Start local Docker stack"
	@docker compose -f docker-compose.yml up -d --build
	@echo "Now visit: http://kitconcept.com.localhost"

.PHONY: start-stack
stack-create-site:  ## Local Stack: Create a new site
	@echo "Create a new site in the local Docker stack"
	@docker compose -f docker-compose.yml exec backend ./docker-entrypoint.sh create-site

.PHONY: start-ps
stack-status:  ## Local Stack: Check Status
	@echo "Check the status of the local Docker stack"
	@docker compose -f docker-compose.yml ps

.PHONY: stack-stop
stack-stop:  ##  Local Stack: Stop Services
	@echo "Stop local Docker stack"
	@docker compose -f docker-compose.yml stop

.PHONY: stack-rm
stack-rm:  ## Local Stack: Remove Services and Volumes
	@echo "Remove local Docker stack"
	@docker compose -f docker-compose.yml down
	@echo "Remove local volume data"
	@docker volume rm $(STACK_NAME)_vol-site-data

## Acceptance
.PHONY: test-acceptance
test-acceptance: ## Start Cypress (for use it while developing)
	(cd frontend && ./node_modules/.bin/cypress open --config specPattern='cypress/tests/**/*.{js,jsx,ts,tsx}')

.PHONY: build-acceptance-servers
build-acceptance-servers: ## Build Acceptance Servers
	@echo "Build acceptance backend"
	@docker build backend --build-arg PLONE_VERSION=${PLONE_VERSION} -t kitconcept/kitconcept.intranet-backend:acceptance -f backend/Dockerfile.acceptance
	@echo "Build acceptance frontend"
	@docker build frontend --build-arg VOLTO_VERSION=${VOLTO_VERSION} -t kitconcept/kitconcept.intranet-frontend:acceptance -f frontend/Dockerfile

.PHONY: start-acceptance-servers
start-acceptance-servers: build-acceptance-servers ## Start Acceptance Servers
	@echo "Start acceptance backend"
	@docker run --rm -p 55001:55001 --name kitconcept.intranet-backend-acceptance -d kitconcept/kitconcept.intranet-backend:acceptance
	@echo "Start acceptance frontend"
	@docker run --rm -p 3000:3000 --name kitconcept.intranet-frontend-acceptance --link kitconcept.intranet-backend-acceptance:backend -e RAZZLE_API_PATH=http://localhost:55001/plone -e RAZZLE_INTERNAL_API_PATH=http://backend:55001/plone -d kitconcept/kitconcept.intranet-frontend:acceptance

.PHONY: stop-acceptance-servers
stop-acceptance-servers: ## Stop Acceptance Servers
	@echo "Stop acceptance containers"
	@docker stop kitconcept.intranet-frontend-acceptance
	@docker stop kitconcept.intranet-backend-acceptance

.PHONY: run-acceptance-tests
run-acceptance-tests: ## Run Acceptance tests
	$(MAKE) start-acceptance-servers
	npx wait-on --httpTimeout 20000 http-get://localhost:55001/plone http://localhost:3000
	$(MAKE) -C "./frontend/" test-acceptance-headless
	$(MAKE) stop-acceptance-servers

.PHONY: acceptance-backend-build
acceptance-backend-build: ## Build Acceptance Backend
	@echo "Build acceptance backend"
	@docker build backend --build-arg PLONE_VERSION=${PLONE_VERSION} -t kitconcept/kitconcept.intranet-backend:acceptance -f backend/Dockerfile.acceptance

.PHONY: start-test-acceptance-frontend-dev
start-test-acceptance-frontend-dev: ## Start the Core Acceptance Frontend Fixture in dev mode
	(cd frontend && RAZZLE_API_PATH=http://127.0.0.1:55001/plone yarn start)

.PHONY: start-test-acceptance-server
start-test-acceptance-server: acceptance-backend-build ## Start Backend Acceptance Servers
	@echo "Start acceptance backend"
	@docker run --rm -p 55001:55001 --name kitconcept.intranet-backend-acceptance -d kitconcept/kitconcept.intranet-backend:acceptance

.PHONY: stop-acceptance-server
stop-acceptance-server: ## Stop Backend Acceptance Server
	@echo "Stop backend acceptance container"
	@docker stop kitconcept.intranet-backend-acceptance

## Solr only
.PHONY: solr-prepare
	solr-prepare: ## Prepare solr
	@echo "$(RED)==> Preparing solr $(RESET)"
	mkdir -p ${SOLR_DATA_FOLDER}/solr

.PHONY: start-solr
start-solr: solr-start

.PHONY: stop-solr
stop-solr: solr-stop

.PHONY: start-solr-fg
start-solr-fg: solr-start-fg

.PHONY: solr-start
solr-start: ## Start solr
	@echo "Start solr"
	@COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME} docker compose -f ${SOLR_ONLY_COMPOSE} up -d

.PHONY: solr-start-and-rebuild
solr-start-and-rebuild: ## Start solr, force rebuild
	@echo "Start solr, force rebuild, erases data"
	@COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME} docker compose -f ${SOLR_ONLY_COMPOSE} up -d --build

.PHONY: solr-start-fg
solr-start-fg: ## Start solr in foreground
	@echo "Start solr in foreground"
	@COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME} docker compose -f ${SOLR_ONLY_COMPOSE} up

.PHONY: solr-stop
solr-stop: ## Stop solr
	@echo "Stop solr"
	@COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME} docker compose -f ${SOLR_ONLY_COMPOSE} down

.PHONY: solr-logs
solr-logs: ## Show solr logs
	@echo "Show solr logs"
	@COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME} docker compose -f ${SOLR_ONLY_COMPOSE} logs -f

.PHONY: solr-activate-and-reindex
solr-activate-and-reindex: instance/etc/zope.ini ## Activate and reindex solr
	PYTHONWARNINGS=ignore ./bin/zconsole run instance/etc/zope.conf scripts/solr_activate_and_reindex.py --clear