all:: client
rel:: client
DEPS_DIR ?= $(CURDIR)/deps
C_VERSION ?= develop

client:
	@echo -n "Getting Xabber Web client ..."
	@if [ ! -d "$(DEPS_DIR)/xabber_web/.git" ]; then \
		mkdir -p $(DEPS_DIR)/xabber_web ;\
		cd $(DEPS_DIR)/xabber_web ;\
		git init -q ;\
		git remote add origin https://github.com/redsolution/xabber-web.git ;\
	fi
	@cd $(DEPS_DIR)/xabber_web && git pull -q origin $(C_VERSION) && git checkout $(C_VERSION)
	@echo ". done."
	@echo -n "Copying Xabber Web files to 'priv' directory  ."
	@mkdir -p priv/client
	@cp -r $(DEPS_DIR)/xabber_web/dist priv/client/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/assets priv/client/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/manifest.json priv/client/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/background-images.xml priv/client/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/background-patterns.xml priv/client/ && echo -n "."
	@sed "s/CONNECTION_URL: ''/CONNECTION_URL: (location.protocol == 'https:' ? 'wss:' : 'ws:')+'\/\/'+location.host+'\/websocket'/g" $(DEPS_DIR)/xabber_web/example_index.html  > priv/client/index.html
	@echo ". done."
