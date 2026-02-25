.PHONY: help install-claude bin-version-check bin-paths-check all-checks

# Default target
.DEFAULT_GOAL := help

# Expected binary versions (source of truth: VERSIONS.md)
EXPECTED_KUBECTX_VERSION=0.9.5
EXPECTED_KUBENS_VERSION=0.9.5
EXPECTED_STERN_VERSION=1.33.0
EXPECTED_K9S_VERSION=0.50.16
EXPECTED_HELM_VERSION=3.11.1
EXPECTED_ISTIOCTL_VERSION=1.27.3

# Color codes for output
COLOR_RESET=\033[0m
COLOR_GREEN=\033[32m
COLOR_RED=\033[31m
COLOR_YELLOW=\033[33m
COLOR_BLUE=\033[36m

help: ## Display this help message
	@echo "🔧 AVAILABLE TARGETS:"
	@echo ""
	@echo "📦 INSTALL:"
	@grep -E '^install-.*:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_BLUE)%-25s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "✅ VALIDATION:"
	@grep -E '^(bin-version-check|bin-paths-check|all-checks):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_BLUE)%-25s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "Fair seas and following winds ⚓🌊⛵"
	@echo ""

bin-version-check: ## Verify installed binary versions match VERSIONS.md
	@echo "🔍 Checking binary versions against VERSIONS.md..."
	@echo ""
	@failed=0; \
	\
	echo "Checking kubectx..."; \
	if command -v kubectx >/dev/null 2>&1; then \
		actual=$$(kubectx --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
		if [ "$$actual" = "$(EXPECTED_KUBECTX_VERSION)" ]; then \
			printf "  $(COLOR_GREEN)✓$(COLOR_RESET) kubectx v$$actual (expected: v$(EXPECTED_KUBECTX_VERSION))\n"; \
		else \
			printf "  $(COLOR_RED)✗$(COLOR_RESET) kubectx v$$actual (expected: v$(EXPECTED_KUBECTX_VERSION))\n"; \
			failed=$$((failed + 1)); \
		fi \
	else \
		printf "  $(COLOR_RED)✗$(COLOR_RESET) kubectx not found in PATH\n"; \
		failed=$$((failed + 1)); \
	fi; \
	\
	echo "Checking kubens..."; \
	if command -v kubens >/dev/null 2>&1; then \
		actual=$$(kubens --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
		if [ "$$actual" = "$(EXPECTED_KUBENS_VERSION)" ]; then \
			printf "  $(COLOR_GREEN)✓$(COLOR_RESET) kubens v$$actual (expected: v$(EXPECTED_KUBENS_VERSION))\n"; \
		else \
			printf "  $(COLOR_RED)✗$(COLOR_RESET) kubens v$$actual (expected: v$(EXPECTED_KUBENS_VERSION))\n"; \
			failed=$$((failed + 1)); \
		fi \
	else \
		printf "  $(COLOR_RED)✗$(COLOR_RESET) kubens not found in PATH\n"; \
		failed=$$((failed + 1)); \
	fi; \
	\
	echo "Checking stern..."; \
	if command -v stern >/dev/null 2>&1; then \
		actual=$$(stern --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
		if [ "$$actual" = "$(EXPECTED_STERN_VERSION)" ]; then \
			printf "  $(COLOR_GREEN)✓$(COLOR_RESET) stern v$$actual (expected: v$(EXPECTED_STERN_VERSION))\n"; \
		else \
			printf "  $(COLOR_RED)✗$(COLOR_RESET) stern v$$actual (expected: v$(EXPECTED_STERN_VERSION))\n"; \
			failed=$$((failed + 1)); \
		fi \
	else \
		printf "  $(COLOR_RED)✗$(COLOR_RESET) stern not found in PATH\n"; \
		failed=$$((failed + 1)); \
	fi; \
	\
	echo "Checking k9s..."; \
	if command -v k9s >/dev/null 2>&1; then \
		actual=$$(k9s version -s 2>&1 | grep 'Version' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
		if [ "$$actual" = "$(EXPECTED_K9S_VERSION)" ]; then \
			printf "  $(COLOR_GREEN)✓$(COLOR_RESET) k9s v$$actual (expected: v$(EXPECTED_K9S_VERSION))\n"; \
		else \
			printf "  $(COLOR_RED)✗$(COLOR_RESET) k9s v$$actual (expected: v$(EXPECTED_K9S_VERSION))\n"; \
			failed=$$((failed + 1)); \
		fi \
	else \
		printf "  $(COLOR_RED)✗$(COLOR_RESET) k9s not found in PATH\n"; \
		failed=$$((failed + 1)); \
	fi; \
	\
	echo "Checking helm..."; \
	if command -v helm >/dev/null 2>&1; then \
		actual=$$(helm version --short 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
		if [ "$$actual" = "$(EXPECTED_HELM_VERSION)" ]; then \
			printf "  $(COLOR_GREEN)✓$(COLOR_RESET) helm v$$actual (expected: v$(EXPECTED_HELM_VERSION))\n"; \
		else \
			printf "  $(COLOR_RED)✗$(COLOR_RESET) helm v$$actual (expected: v$(EXPECTED_HELM_VERSION))\n"; \
			failed=$$((failed + 1)); \
		fi \
	else \
		printf "  $(COLOR_RED)✗$(COLOR_RESET) helm not found in PATH\n"; \
		failed=$$((failed + 1)); \
	fi; \
	\
	echo "Checking istioctl..."; \
	if command -v istioctl >/dev/null 2>&1; then \
		actual=$$(istioctl version --remote=false 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
		if [ "$$actual" = "$(EXPECTED_ISTIOCTL_VERSION)" ]; then \
			printf "  $(COLOR_GREEN)✓$(COLOR_RESET) istioctl v$$actual (expected: v$(EXPECTED_ISTIOCTL_VERSION))\n"; \
		else \
			printf "  $(COLOR_RED)✗$(COLOR_RESET) istioctl v$$actual (expected: v$(EXPECTED_ISTIOCTL_VERSION))\n"; \
			failed=$$((failed + 1)); \
		fi \
	else \
		printf "  $(COLOR_RED)✗$(COLOR_RESET) istioctl not found in PATH\n"; \
		failed=$$((failed + 1)); \
	fi; \
	\
	echo ""; \
	if [ $$failed -eq 0 ]; then \
		printf "$(COLOR_GREEN)✅ All binary versions match VERSIONS.md$(COLOR_RESET)\n"; \
		exit 0; \
	else \
		printf "$(COLOR_RED)❌ $$failed version mismatch(es) found$(COLOR_RESET)\n"; \
		printf "$(COLOR_YELLOW)💡 Check VERSIONS.md for expected versions$(COLOR_RESET)\n"; \
		exit 1; \
	fi

bin-paths-check: ## Verify all required binaries are in PATH
	@echo "🔍 Checking binary availability in PATH..."
	@echo ""
	@failed=0; \
	for bin in kubectx kubens stern k9s helm istioctl; do \
		if command -v $$bin >/dev/null 2>&1; then \
			path=$$(command -v $$bin); \
			printf "  $(COLOR_GREEN)✓$(COLOR_RESET) $$bin found at $$path\n"; \
		else \
			printf "  $(COLOR_RED)✗$(COLOR_RESET) $$bin not found in PATH\n"; \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	echo ""; \
	if [ $$failed -eq 0 ]; then \
		printf "$(COLOR_GREEN)✅ All binaries found in PATH$(COLOR_RESET)\n"; \
		exit 0; \
	else \
		printf "$(COLOR_RED)❌ $$failed binary(ies) missing from PATH$(COLOR_RESET)\n"; \
		printf "$(COLOR_YELLOW)💡 Ensure ~/bin is in your PATH and binaries are installed$(COLOR_RESET)\n"; \
		exit 1; \
	fi

install-claude: ## Symlink Claude Code configuration to ~/.claude
	@echo "🔧 Installing Claude Code configuration..."
	@mkdir -p "$(HOME)/.claude"
	@ln -sf "$(CURDIR)/claude/CLAUDE.md" "$(HOME)/.claude/CLAUDE.md"
	@ln -sf "$(CURDIR)/claude/settings.json" "$(HOME)/.claude/settings.json"
	@rm -rf -- "$(HOME)/.claude/hooks"
	@ln -sfn "$(CURDIR)/claude/hooks" "$(HOME)/.claude/hooks"
	@rm -rf -- "$(HOME)/.claude/skills"
	@ln -sfn "$(CURDIR)/claude/skills" "$(HOME)/.claude/skills"
	@printf "$(COLOR_GREEN)✅ Claude Code configuration linked to $(HOME)/.claude$(COLOR_RESET)\n"

all-checks: bin-paths-check bin-version-check ## Run all validation checks
	@echo ""
	@printf "$(COLOR_GREEN)✅ All checks passed!$(COLOR_RESET)\n"
