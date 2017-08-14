%% @private
-module(xabber_ws_app).
-behaviour(application).

%% API.
-export([start/2]).
-export([stop/1]).

%% Defaults
-define(WS_PORT, 8080).
-define(WS_PATH, "/websocket").

%% API.
start(_Type, _Args) ->
	Port = application:get_env(xabber_ws, ws_port, ?WS_PORT),
	WS_path = application:get_env(xabber_ws, ws_path, ?WS_PATH),
	Dispatch = cowboy_router:compile([
		{'_', [
			{WS_path, ws_handler, []}
		]}
	]),
	{ok, _} = cowboy:start_clear(http, [{port, Port}], #{
		env => #{dispatch => Dispatch}
	}),
	xabber_ws_sup:start_link().

stop(_State) ->
	ok.
