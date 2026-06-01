PROJECT = xabber_ws
PROJECT_DESCRIPTION = Xabber Websocket server
PROJECT_VERSION = 0.4.0

DEPS = cowlib cowboy p1_utils fast_xml
dep_cowlib_commit = 2.12.1
dep_cowboy_commit = 2.10.0
dep_fast_xml_commit = 1.1.49
dep_p1_utils_commit = 1.0.25
dep_p1_utils = git https://github.com/processone/p1_utils.git
dep_fast_xml = git https://github.com/processone/fast_xml.git

# ERLC_OPTS += +'{parse_transform, lager_transform}'
BUILD_DEPS += relx

# include cacerts.mk
include client.mk
include erlang.mk
