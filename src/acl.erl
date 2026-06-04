-module(acl).
-include_lib("kernel/include/logger.hrl").

-export([check/1]).
-export([reload/0]).

-define(CACHE_KEY, {?MODULE, rules}).

check(Server) ->
  Rules = rules(),
  case lists:keyfind(string:lowercase(Server), 2, Rules) of
    {Rule, _} -> Rule;
    false -> default_rule()
  end.

default_rule() ->
  case application:get_env(xabber_ws, allow_all, true) of
    true -> <<"allow">>;
    _ -> <<"deny">>
  end.

reload() ->
  ACLFilePath = application:get_env(xabber_ws, accessrules_file, "config/accessrules"),
  case file:read_file(ACLFilePath) of
    {ok, Binary} ->
      Rules = parse(Binary),
      persistent_term:put(?CACHE_KEY, Rules),
      ?LOG_INFO("accessrules: reloaded ~p rules", [length(Rules)]),
      ok;
    {error, Reason} ->
      ?LOG_ERROR("accessrules: File read error: ~p", [Reason]),
      {error, Reason}
  end.

rules() ->
  case persistent_term:get(?CACHE_KEY, undefined) of
    undefined ->
      case reload() of
        ok ->
          persistent_term:get(?CACHE_KEY, []);
        {error, _Reason} ->
          persistent_term:put(?CACHE_KEY, []),
          []
      end;
    Rules ->
      Rules
  end.

parse(Binary) ->
  {ok, MP} = re:compile("[#%].*(\n|$)"),
  Binary2 = re:replace(Binary, MP, "\n", [{return,binary}, global]),
  lists:filtermap(fun parse_rule/1,
    binary:split(Binary2, <<"\n">>, [global])).

parse_rule(Line) ->
  case string:lexemes(string:lowercase(Line), " \t\r") of
    [] ->
      false;
    [Rule, Server] when Rule =:= <<"allow">>; Rule =:= <<"deny">> ->
      {true, {Rule, Server}};
    [Rule, _Server] ->
      ?LOG_ERROR("accessrules: Unknown rule: ~s", [Rule]),
      false;
    _ ->
      ?LOG_ERROR("accessrules: Wrong record: ~s", [Line]),
      false
  end.
