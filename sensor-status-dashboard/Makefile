all: assets/stylesheets/css/site.css

.PHONY: default
default: html

PYTHON ?= python2.7
VIRTUALENV_DIR ?= env

$(VIRTUALENV_DIR):
	@virtualenv --python=$(PYTHON) $(VIRTUALENV_DIR)

.PHONY: dependencies
dependencies: $(VIRTUALENV_DIR) requirements.txt
	@$(VIRTUALENV_DIR)/bin/pip install --quiet --requirement requirements.txt

.PHONY: deps
deps: dependencies

node_modules:
	@npm install

bower_components: node_modules
	@./node_modules/bower/bin/bower install

assets/stylesheets/css/site.css: node_modules bower_components \
								 assets/stylesheets/sass/site.scss
	@./node_modules/node-sass/bin/node-sass --output-style expanded \
		assets/stylesheets/sass/site.scss > assets/stylesheets/css/site.css
