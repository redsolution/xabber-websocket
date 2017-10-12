-module(xabber_ws_app).
-behaviour(application).

%% API.
-export([start/2]).
-export([stop/1]).

%% Defaults
-define(PORT, 8080).
-define(WS_PATH, "/websocket").
-define(CLIENT_PATH, "/client").

%% API.
start(_Type, _Args) ->
	Port = application:get_env(xabber_ws, port, ?PORT),
	WS_path = application:get_env(xabber_ws, ws_path, ?WS_PATH),
	Client_path =  application:get_env(xabber_ws, client_path, ?CLIENT_PATH),
	Dispatch = cowboy_router:compile([
		{'_', [
			{WS_path, ws_handler, []},
			{Client_path, client_handler, []},
			{Client_path ++ "/[...]", cowboy_static, {priv_dir, xabber_ws, "client/client_files"}}
		]}
	]),
	{ok, _} = cowboy:start_clear(http, [{port, Port}], #{
		env => #{dispatch => Dispatch}
	}),
	xabber_ws_sup:start_link().

stop(_State) ->
	ok.
