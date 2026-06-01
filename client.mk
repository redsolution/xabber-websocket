all:: client
rel:: client
DEPS_DIR ?= $(CURDIR)/deps
C_REPO ?= https://github.com/redsolution/xabber-web.git
C_VERSION ?= develop
C_DEPTH ?= 1

client:
	@echo "Getting Xabber Web client ..."
	@if [ ! -d "$(DEPS_DIR)/xabber_web/.git" ]; then \
		mkdir -p "$(DEPS_DIR)/xabber_web" ;\
		cd "$(DEPS_DIR)/xabber_web" ;\
		git init -q ;\
		git remote add origin "$(C_REPO)" ;\
	else \
		cd "$(DEPS_DIR)/xabber_web" ;\
		git remote set-url origin "$(C_REPO)" ;\
	fi
	@cd "$(DEPS_DIR)/xabber_web" && git fetch -q --depth "$(C_DEPTH)" --no-tags origin "$(C_VERSION)" && git checkout -q --detach FETCH_HEAD
	@echo ". done."
	@echo -n "Copying Xabber Web files to 'priv' directory  ."
	@mkdir -p priv/client
	@cp -r $(DEPS_DIR)/xabber_web/dist priv/client/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/assets priv/client/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/manifest.json priv/client/ && echo -n "."
	@sed "s/CONNECTION_URL: ''/CONNECTION_URL: (location.protocol == 'https:' ? 'wss:' : 'ws:')+'\/\/'+location.host+'\/websocket',DISABLE_LOOKUP_WS: true/g" $(DEPS_DIR)/xabber_web/example_index.html  > priv/client/index.html
	@echo ". done."
