.PHONY: test test-real

test:
	@[ -x .venv/bin/python ] || ./bin/pwninit --help >/dev/null
	@.venv/bin/python -m unittest discover -s tests

test-real:
	@[ -x .venv/bin/python ] || ./bin/pwninit --help >/dev/null
	@PWNINIT_E2E_REAL=1 .venv/bin/python -m unittest discover -s tests
