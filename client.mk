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
	@echo -n "Copying Xabber Web files to 'priv' directory  ."
	@mkdir -p priv/client
	@cp -r $(DEPS_DIR)/xabber_web/dist priv/client/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/fonts priv/client/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/images priv/client/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/sounds priv/client/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/manifest.json priv/client/ && echo -n "."
	@cp -r $(DEPS_DIR)/xabber_web/firebase-messaging-sw.js priv/client/ && echo -n "."
	@sed "s/CONNECTION_URL: ''/CONNECTION_URL: 'ws:\/\/'+location.host+'\/websocket'/g" $(DEPS_DIR)/xabber_web/example_index.html  > priv/client/index.html
	@echo ". done."