all:: client
rel:: client

client:
	@echo -n "Getting Xabber Web client ..."
	@if [ ! -d "deps/xabber_web" ]; then \
		mkdir -p deps/xabber_web ;\
		cd deps/xabber_web ;\
		git init -q ;\
		git remote add origin https://github.com/redsolution/xabber-web.git ;\
	fi
	@cd deps/xabber_web && git pull -q origin master
	@echo ". done."
	@echo -n "Copying xmpp client files to 'priv' directory  ."
	@mkdir -p priv/client/client_files
	@cp -r deps/xabber_web/dist priv/client/client_files/ && echo -n "."
	@cp -r deps/xabber_web/fonts priv/client/client_files/ && echo -n "."
	@cp -r deps/xabber_web/images priv/client/client_files/ && echo -n "."
	@cp -r deps/xabber_web/sounds priv/client/client_files/ && echo -n "."
	@echo ". done."