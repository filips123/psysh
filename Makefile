PSYSH_SRC = bin src box.json.dist composer.json build/stub scoper.inc.php
PSYSH_SRC_FILES = $(shell find src -type f -name "*.php")
VERSION = $(shell git describe --tag --always --dirty=-dev)

COMPOSER_OPTS = --no-interaction --no-progress --verbose
COMPOSER_REQUIRE_OPTS = $(COMPOSER_OPTS) --no-update
COMPOSER_UPDATE_OPTS = $(COMPOSER_OPTS) --prefer-stable --no-dev --classmap-authoritative --prefer-dist

ifneq ($(CI),)
	PHPUNIT_OPTS = --verbose --coverage-clover=coverage.xml
endif


# Commands

.PHONY: help build clean dist test
.DEFAULT_GOAL := help

help:
	@echo "\033[33mUsage:\033[0m\n  make TARGET\n\n\033[33mTargets:\033[0m"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[32m%-7s\033[0m %s\n", $$1, $$2}'

build: ## Compile PHARs
build: build/psysh/psysh build/psysh-compat/psysh build/psysh-php54/psysh build/psysh-php54-compat/psysh

clean: ## Clean all created artifacts
	rm -rf build/*
	rm -rf dist/*
	rm -rf vendor-bin/*/vendor/

dist: ## Build tarballs for distribution
dist: dist/psysh-$(VERSION).tar.gz dist/psysh-$(VERSION)-compat.tar.gz dist/psysh-$(VERSION)-php54.tar.gz dist/psysh-$(VERSION)-php54-compat.tar.gz
	cp build/psysh/psysh dist/psysh.phar
	cp build/psysh/psysh.asc dist/psysh.asc

test: ## Run unit tests
test: vendor/bin/phpunit
	$< $(PHPUNIT_OPTS)


# All the composer stuffs

composer.lock: composer.json
	composer install
	touch $@

vendor/autoload.php: composer.lock
	composer install
	touch $@

vendor/bin/box: vendor/autoload.php
	composer bin box install
	touch $@

vendor/bin/phpunit: vendor/autoload.php
	composer bin phpunit install
	touch $@


# Lots of PHARs

build/stub: bin/build-stub bin/psysh LICENSE
	bin/build-stub

build/psysh: $(PSYSH_SRC) $(PSYSH_SRC_FILES)
	rm -rf $@ || true
	mkdir $@
	cp -R $(PSYSH_SRC) $@/
	composer config --working-dir $@ platform.php 7.0
	composer require --working-dir $@ $(COMPOSER_REQUIRE_OPTS) php:'>=7.0.0'
	composer update --working-dir $@ $(COMPOSER_UPDATE_OPTS)

build/psysh-compat: $(PSYSH_SRC) $(PSYSH_SRC_FILES)
	rm -rf $@ || true
	mkdir $@
	cp -R $(PSYSH_SRC) $@/
	composer config --working-dir $@ platform.php 7.0
	composer require --working-dir $@ $(COMPOSER_REQUIRE_OPTS) php:'>=7.0.0'
	composer require --working-dir $@ $(COMPOSER_REQUIRE_OPTS) symfony/polyfill-iconv symfony/polyfill-mbstring hoa/console
	composer update --working-dir $@ $(COMPOSER_UPDATE_OPTS)

build/psysh-php54: $(PSYSH_SRC) $(PSYSH_SRC_FILES)
	rm -rf $@ || true
	mkdir $@
	cp -R $(PSYSH_SRC) $@/
	composer config --working-dir $@ platform.php 5.4
	composer update --working-dir $@ $(COMPOSER_UPDATE_OPTS)

build/psysh-php54-compat: $(PSYSH_SRC) $(PSYSH_SRC_FILES)
	rm -rf $@ || true
	mkdir $@
	cp -R $(PSYSH_SRC) $@/
	composer config --working-dir $@ platform.php 5.4
	composer require --working-dir $@ $(COMPOSER_REQUIRE_OPTS) symfony/polyfill-iconv symfony/polyfill-mbstring hoa/console:^2.15
	composer update --working-dir $@ $(COMPOSER_UPDATE_OPTS)

build/%/psysh: vendor/bin/box build/%
	vendor/bin/box compile --working-dir $(dir $@)

# Signatures

build/%/psysh.asc: build/%/psysh
	echo $$DECRYPT_KEY | gpg --batch --yes --passphrase-fd 0 .github/keys.asc.gpg
	gpg --batch --yes --import .github/keys.asc
	
	echo $$SIGN_KEY |\
		gpg --passphrase-fd 0 \
		-u $$KEY_ID \
		--armor \
		--detach-sig $(echo $@ | sed 's/.asc//') >\
		$@
	
	gpg --fingerprint --with-colons $$KEY_ID |\
		grep "^fpr" |\
		sed -n 's/^fpr:::::::::\([[:alnum:]]\+\):/\1/p' |\
		xargs gpg --batch --delete-secret-keys
	rm -rf .github/keys.asc

# Dist packages

dist/psysh-$(VERSION).tar.gz: build/psysh/psysh build/psysh/psysh.asc
	@mkdir -p $(@D)
	tar -C $(dir $<) -czf $@ $(notdir $<)

dist/psysh-$(VERSION)-%.tar.gz: build/psysh-%/psysh build/psysh-%/psysh.asc
	@mkdir -p $(@D)
	tar -C $(dir $<) -czf $@ $(notdir $<)
