.PHONY: docs
docs:
	ldoc -c config.ld .

GH_PAGES_SOURCES = Makefile config.ld script/
gh-pages:
	git fetch origin gh-pages
	git checkout origin/gh-pages
	git checkout master $(GH_PAGES_SOURCES)
	git reset HEAD
	$(MAKE) docs
	mv -fv docs/* ./
	rm -rf $(GH_PAGES_SOURCES) docs
	git add -A
	git commit -m "Generated gh-pages for `git log master -1 --pretty=short --abbrev-commit`" && git push origin gh-pages ; git checkout --force master

.PHONY: clean
clean:
	rm -rf docs/
