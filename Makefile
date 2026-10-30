EASK ?= eask

.PHONY: all deps test compile lint clean

all: compile lint test

deps:
	$(EASK) install-deps --dev

test:
	$(EASK) test ert test/markdown-tblfm-test.el

compile:
	$(EASK) compile --strict

lint:
	$(EASK) lint checkdoc --strict
	$(EASK) lint package --strict

clean:
	$(EASK) clean elc
