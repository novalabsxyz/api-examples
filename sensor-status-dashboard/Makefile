all: assets/stylesheets/css/site.css

node_modules:
	@npm install

bower_components: node_modules
	@./node_modules/bower/bin/bower install

assets/stylesheets/css/site.css: node_modules bower_components \
								 assets/stylesheets/sass/site.scss
	@./node_modules/node-sass/bin/node-sass --output-style expanded \
		assets/stylesheets/sass/site.scss > assets/stylesheets/css/site.css
