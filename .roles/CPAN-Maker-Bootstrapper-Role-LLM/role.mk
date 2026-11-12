.PHONY: release-notes
release-notes: ## creates release-notes/release-notes-{version}.md
	$(NO_ECHO)cmb release-notes $(if $(MODEL),"--model $(MODEL)") $(if $(DRYRUN),--dryrun) $(if $(MAX_TOKENS),--max-tokens $(MAX_TOKENS))

.PHONY: change-log
change-log: ## creates a ChangeLog-M.m.r.tmp
	$(NO_ECHO)cmb change-log $(if $(MODEL),"--model $(MODEL)") $(if $(DRYRUN),--dryrun) $(if $(MAX_TOKENS),--max-tokens $(MAX_TOKENS))

post-update::
	rm -f .includes/release-notes.mk .includes/change-log.mk
