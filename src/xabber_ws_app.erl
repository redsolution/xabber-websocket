-module(xabber_ws_app).
-behaviour(application).

%% API.
-export([start/2]).
-export([stop/1]).

%% Defaults
-define(PORT, 8080).
-define(WS_PATH, "/websocket").
-define(CLIENT_PATH, "/client").
-define(SSL, false).
-define(SSL_PORT, 8443).


%% API.
start(_Type, _Args) ->
  case load_config() of
    start ->
      xabber_ws_sup:start_link();
    stop ->
      init:stop(),
      {error, bad_config}
  end.

load_config() ->
  Port = application:get_env(xabber_ws, port, ?PORT),
  WS_path = application:get_env(xabber_ws, ws_path, ?WS_PATH),
  Client_path =  application:get_env(xabber_ws, client_path, ?CLIENT_PATH),
  Dispatch = cowboy_router:compile([
    {'_', [
      {WS_path, ws_handler, []},
      {Client_path, client_handler, []},
      {Client_path ++ "/[...]", cowboy_static, {priv_dir, xabber_ws, "client/"}}
    ]}
  ]),
  Opts = #{env => #{dispatch => Dispatch}},
  case   application:get_env(xabber_ws, ssl, ?SSL) of
    true  ->
      case check_ssl_params([ssl_cacertfile, ssl_certfile, ssl_keyfile]) of
        [] ->
          stop;
        [CAFile, CertFile, KeyFile] ->
          SSL_port = application:get_env(xabber_ws, ssl_port, ?SSL_PORT),
          {ok, _} = cowboy:start_tls(https, [
            {port, SSL_port},
            {cacertfile, CAFile},
            {certfile, CertFile},
            {keyfile, KeyFile}
          ], Opts),
          Dispatch_redirect =cowboy_router:compile([{'_', [{'_', redirect_handler, SSL_port}]}]),
          {ok, _} = cowboy:start_clear(http, [{port, Port}], #{env => #{dispatch => Dispatch_redirect}}),
          start
      end;
    _ ->
      {ok, _} = cowboy:start_clear(http, [{port, Port}], Opts),
      start
  end.

stop(_State) ->
  ok.

check_ssl_params(Params) ->
  try
    get_ssl_params_value(Params, [])
  catch
    throw:{undefined, Param} ->
      lager:error("SSL config error: ~p is undefined",[Param]), [];
    throw:{unavailable, File} ->
      lager:error("SSL config error: ~p is unavailable",[File]), []
  end.


get_ssl_params_value([H|T], Values) ->
  case application:get_env(xabber_ws, H) of
    undefined ->
      throw({undefined, H});
    {ok,[]} ->
      throw({undefined, H});
    {ok,Val} ->
      case filelib:is_regular(Val) of
        true ->
          get_ssl_params_value(T, [Val|Values]);
        _ ->
          throw({unavailable, Val})
      end
  end;
get_ssl_params_value([], Values) ->
  lists:reverse(Values).
