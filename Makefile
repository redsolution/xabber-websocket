PROJECT = xabber_ws
PROJECT_DESCRIPTION = Xabber Websocket server
PROJECT_VERSION = 0.3.4

DEPS = cowlib cowboy p1_utils fast_xml lager
dep_cowlib_commit = 2.7.0
dep_cowboy_commit = 2.6.1
dep_p1_utils = git https://github.com/processone/p1_utils.git
dep_fast_xml = git https://github.com/processone/fast_xml.git
dep_lager = git https://github.com/erlang-lager/lager.git

ERLC_OPTS += +'{parse_transform, lager_transform}'

include client.mk
include erlang.mk
