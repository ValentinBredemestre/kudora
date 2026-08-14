DEVTOOLS_SCRIPT := ./scripts/devtools.sh

.PHONY: devtools-build

devtools-build:
	@$(DEVTOOLS_SCRIPT) build
