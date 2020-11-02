.DEFAULT_GOAL := default

# Bootstrap a new instance without Fedora.  Assumes there is a Drupal site in ./codebase.
# Will do a clean Drupal install and initialization
#
# (TODO: generally make ISLE more robust to the choice to omit fedora.
# otherwise we could of simply done 'hydrate' instead of update-settings-php, update-config... etc)
.PHONY: bootstrap
.SILENT: bootstrap
bootstrap: snapshot-empty default destroy-state up install \
		update-settings-php update-config-from-environment solr-cores run-islandora-migrations \
		cache-rebuild
		git checkout -- .env

# Rebuilds the Drupal cache
.PHONY: cache-rebuild
.SILENT: cache-rebuild
cache-rebuild:
	echo "rebuilding Drupal cache..."
	docker-compose exec drupal drush cr -y

.PHONY: destroy-state
.SILENT: destroy-state
destroy-state:
	echo "Destroying docker-compose volume state"
	docker-compose down -v

.PHONY: composer-install
.SILENT: composer-install
composer-install:
	echo "Installing via composer"
	docker-compose exec drupal with-contenv bash -lc 'COMPOSER_MEMORY_LIMIT=-1 composer install'

.PHONY: snapshot-image
.SILENT: snapshot-image
snapshot-image:
	docker-compose stop
	docker run --rm --volumes-from snapshot \
		-v ${PWD}/snapshot:/dump \
		alpine:latest \
		/bin/tar cvf /dump/data.tar /data
	TAG=`git describe --tags`.`date +%s` && \
		docker build -t ${REPOSITORY}/snapshot:$$TAG ./snapshot && \
		cat .env | sed s/SNAPSHOT_TAG=.*/SNAPSHOT_TAG=$$TAG/ > /tmp/.env && \
	  cp /tmp/.env .env && \
	  rm /tmp/.env
	rm docker-compose.yml
	$(MAKE) docker-compose.yml
	docker-compose up -d

.PHONY: reset
.SILENT: reset
reset: warning-destroy-state destroy-state
	@echo "Removing vendored modules"
	-rm -rf codebase/vendor
	-rm -rf codebase/web/core
	-rm -rf codebase/web/modules/contrib
	-rm -rf codebase/web/themes/contrib
	@echo "Re-generating docker-compose.yml"
	$(MAKE) docker-compose.yml
	@echo "Starting ..."
	@echo "Invoke 'docker-compose logs -f drupal' in another terminal to monitor startup progress"
	$(MAKE) start

.PHONY: warning-destroy-state
.SILENT: warning-destroy-state
warning-destroy-state:
	@echo "WARNING: Resetting state to snapshot ${SNAPSHOT_TAG}.  This will:"
	@echo "1. Remove all modules and dependencies under:"
	@echo "  codebase/vendor"
	@echo "  codebase/web/core"
	@echo "  codebase/modules/contrib"
	@echo "  codebase/themes/contrib"
	@echo "2. Re-generate docker-compose.yml"
	@echo "3. Pull the latest images"
	@echo "4. Re-install modules from composer.json"
	@echo "WARNING: continue? [Y/n]"
	@read line; if [ $$line != "Y" ]; then echo aborting; exit 1 ; fi

.PHONY: snapshot-empty
.SILENT: snapshot-empty
snapshot-empty:
	-rm docker-compose.yml
	sed s/SNAPSHOT_TAG=.*/SNAPSHOT_TAG=empty/ .env > /tmp/.env && \
      cp /tmp/.env .env && \
	    rm /tmp/.env
	$(MAKE) docker-compose.yml
	docker build -f snapshot/empty.Dockerfile -t ${REPOSITORY}/snapshot:empty ./snapshot

.PHONY: up
.SILENT: up
up:  download-default-certs docker-compose.yml start


.PHONY: start
.SILENT: start
start:
	docker-compose up -d
	sleep 5
	docker-compose exec drupal /bin/sh -c "while true ; do echo \"Waiting for Drupal to start ...\" ; if [ -d \"/var/run/s6/services/nginx\" ] ; then s6-svwait -u /var/run/s6/services/nginx && exit 0 ; else sleep 5 ; fi done"