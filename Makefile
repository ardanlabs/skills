# Repository checks. `make test` runs lint and every skill test suite.
# ardan-pr-review suite: see zarf/tests/ardan-pr-review/README.md.

PR_REVIEW_TESTS := zarf/tests/ardan-pr-review
PR_REVIEW_SCRIPTS := $(wildcard .agents/skills/ardan-pr-review/scripts/*.sh) $(wildcard $(PR_REVIEW_TESTS)/*.sh)

.PHONY: test lint test-pr-review test-pr-review-host test-pr-review-container test-pr-review-update

test: lint test-pr-review

lint:
	shellcheck $(PR_REVIEW_SCRIPTS)

# Host (stub analyzers, the host's sh/awk and PowerShell) and container (real analyzers at
# pinned versions; needs Docker).
test-pr-review: test-pr-review-host test-pr-review-container

test-pr-review-host:
	sh $(PR_REVIEW_TESTS)/run.sh host

test-pr-review-container:
	sh $(PR_REVIEW_TESTS)/run.sh container

# Rewrite the golden files from both modes after an intended change; review the diff.
test-pr-review-update:
	UPDATE=1 sh $(PR_REVIEW_TESTS)/run.sh host
	UPDATE=1 sh $(PR_REVIEW_TESTS)/run.sh container
