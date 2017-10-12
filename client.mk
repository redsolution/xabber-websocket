all:: client
rel:: client
DEPS_DIR ?= $(CURDIR)/deps

client:
	@echo -n "Getting Xabber Web client ..."
	@if [ ! -d "$(DEPS_DIR)/xabber_web/.git" ]; then \
		mkdir -p $(DEPS_DIR)/xabber_web ;\
		cd $(DEPS_DIR)/xabber_web ;\
		git init -q ;\
		git remote add origin https://github.com/redsolution/xabber-web.git ;\
	fi
	@cd $(DEPS_DIR)/xabber_web && git pull -q origin master
	@echo ". done."
	@echo -n "Copying xmpp client files to 'priv' directory  ."
	@mkdir -p priv/client/client_files
	@cp -r $(DEPS_DIR)/xabber_web/dist priv/client/client_files/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/fonts priv/client/client_files/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/images priv/client/client_files/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/sounds priv/client/client_files/ && echo -n "."
	@echo ". done."