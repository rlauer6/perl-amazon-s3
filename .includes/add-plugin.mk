#-*- mode: makefile; -*-

.PHONY: add-plugin
add-plugin:
	$(NO_ECHO)if [ -z "$(PLUGIN)" ]; then \
	  echo "usage: make add-plugin PLUGIN=NAME [FORCE=1]" >&2; \
	  exit 1; \
	fi; \
	message=$$(cmb add-plugin $(if $(FORCE),--force) "$(PLUGIN)") && \
	$(MAKE) update; \
	echo -e "\n$$message\n"
