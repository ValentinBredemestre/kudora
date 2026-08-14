.PHONY: dependency-audit verify-no-forks verify-no-secrets vulncheck

dependency-audit:
	@$(DEVTOOLS_SCRIPT) run ./scripts/dependency-audit.sh

verify-no-forks:
	@$(DEVTOOLS_SCRIPT) run ./scripts/verify-no-forks.sh

verify-no-secrets:
	@$(DEVTOOLS_SCRIPT) run ./scripts/verify-no-secrets.sh

vulncheck:
	@$(DEVTOOLS_SCRIPT) run bash -lc 'make build >/dev/null && ./scripts/with-wasmvm.sh ./scripts/vulncheck.sh'
