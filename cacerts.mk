all:: cacerts
rel:: cacerts

# From https://github.com/certifi/certifi.io/blob/981735d/source/index.rst
cacerts:
	@echo "Getting Root Certificates ..."
	@curl -#fSlo priv/ssl/certs/cacerts.pem https://mkcert.org/generate/
