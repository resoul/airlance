help:
	@node ./node_modules/locanika/dist/nika.js help

dns:
	@node ./node_modules/locanika/dist/nika.js dns

hosts:
	@node ./node_modules/locanika/dist/nika.js hosts

projects-init:
	@node ./node_modules/locanika/dist/nika.js projects-init

projects-pull:
	@node ./node_modules/locanika/dist/nika.js projects-pull

services-init:
	@node ./node_modules/locanika/dist/nika.js services-init

services-ps:
	@node ./node_modules/locanika/dist/nika.js services-ps

services-build:
	@node ./node_modules/locanika/dist/nika.js services-build

services-up:
	@node ./node_modules/locanika/dist/nika.js services-up

services-down:
	@node ./node_modules/locanika/dist/nika.js services-down

services-restart:
	@node ./node_modules/locanika/dist/nika.js services-down
	@node ./node_modules/locanika/dist/nika.js services-up

services-deploy:
	make services-down
	make services-init
	make services-build
	make services-up
	make hosts

services-clean:
	docker image prune -a --force --filter "until=24h"

-include ./services/Makefile