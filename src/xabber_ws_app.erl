-module(xabber_ws_app).
-behaviour(application).

-include_lib("kernel/include/logger.hrl").

%% API.
-export([start/2]).
-export([stop/1]).

%% Defaults
-define(PORT, 8080).
-define(WS_PATH, "/websocket").
-define(CLIENT_PATH, "/client").
-define(SSL, false).
-define(SSL_PORT, 8443).
-define(LOG_DIR, ".").
-define(LOG_FILE, "xabber_ws.log").
-define(LOG_LEVEL, info).
-define(LOG_CONSOLE, auto).
-define(LOG_MAX_NO_BYTES, 5242880).
-define(LOG_MAX_NO_FILES, 5).


%% API.
start(_Type, _Args) ->
  configure_logger(),
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

configure_logger() ->
  LogDir = application:get_env(xabber_ws, log_dir, ?LOG_DIR),
  LogFile = application:get_env(xabber_ws, log_file, ?LOG_FILE),
  LogLevel = application:get_env(xabber_ws, log_level, ?LOG_LEVEL),
  LogConsole = application:get_env(xabber_ws, log_console, ?LOG_CONSOLE),
  MaxNoBytes = application:get_env(xabber_ws, log_max_no_bytes, ?LOG_MAX_NO_BYTES),
  MaxNoFiles = application:get_env(xabber_ws, log_max_no_files, ?LOG_MAX_NO_FILES),
  configure_console_logger(LogLevel, LogConsole),
  LogPath = filename:join(LogDir, LogFile),
  ok = filelib:ensure_dir(LogPath),
  Config = #{
    level => LogLevel,
    config => #{
      file => LogPath,
      max_no_bytes => MaxNoBytes,
      max_no_files => MaxNoFiles
    },
    filters => [
      {drop_supervisor_reports, {fun filter_supervisor_reports/2, []}}
    ],
    formatter => {logger_formatter,
      #{
        single_line => true,
        template => [time, " ", level, " ", pid, " ", mfa, " ", msg, "\n"]
      }}
  },
  case logger:add_handler(xabber_ws_file_log, logger_std_h, Config) of
    ok ->
      ok;
    {error, {already_exist, xabber_ws_file_log}} ->
      logger:update_handler_config(xabber_ws_file_log, Config);
    {error, Reason} ->
      error({logger_config_error, Reason})
  end,
  logger:set_primary_config(level, LogLevel).

configure_console_logger(LogLevel, LogConsole) ->
  case log_to_console(LogConsole) of
    true ->
      Config = #{
        level => LogLevel,
        config => #{type => standard_io},
        filters => [
          {drop_supervisor_reports, {fun filter_supervisor_reports/2, []}}
        ],
        formatter => {logger_formatter,
          #{
            single_line => true,
            template => [time, " ", level, " ", pid, " ", mfa, " ", msg, "\n"]
          }}
      },
      remove_default_logger_handler(),
      case logger:add_handler(default, logger_std_h, Config) of
        ok ->
          ok;
        {error, Reason} ->
          error({logger_console_config_error, Reason})
      end;
    false ->
      remove_default_logger_handler()
  end.

log_to_console(true) ->
  true;
log_to_console(false) ->
  false;
log_to_console(auto) ->
  Args = init:get_plain_arguments(),
  lists:member("console", Args) andalso os:getenv("HEART_COMMAND") =:= false.

remove_default_logger_handler() ->
  case logger:remove_handler(default) of
    ok ->
      ok;
    {error, {not_found, default}} ->
      ok
  end.

filter_supervisor_reports(#{msg := {report, #{label := {supervisor, _}}}}, _Args) ->
  stop;
filter_supervisor_reports(_LogEvent, _Args) ->
  ignore.

check_ssl_params(Params) ->
  try
    get_ssl_params_value(Params, [])
  catch
    throw:{undefined, Param} ->
      ?LOG_ERROR("SSL config error: ~p is undefined",[Param]), [];
    throw:{unavailable, File} ->
      ?LOG_ERROR("SSL config error: ~p is unavailable",[File]), []
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
