%% All this is done to add the trailing slash

-module(client_handler).
-export([init/2]).

init(Req0, Opts) ->
  Path = cowboy_req:path(Req0),
  case binary:last(Path) of
    47 ->
      Index_file = filename:join([code:priv_dir(xabber_ws), "client", "index.html"]),
      Body = case file:read_file(Index_file) of
               {ok, Binary} ->
                 Binary;
               {error, Reason} ->
                 Reason_binary = atom_to_binary(Reason, utf8),
                 <<"<html><body>error: ", Reason_binary/binary,"</body></html>">>
             end,
      Reply = cowboy_req:reply(200,#{
        <<"content-type">> => <<"text/html; charset=utf-8">>
      }, Body, Req0),
      {ok, Reply, Opts};
    _ ->
      Req1 = cowboy_req:set_resp_header(<<"Location">>, <<Path/binary,"/">>, Req0),
      Reply = cowboy_req:reply(301, Req1),
      {ok, Reply, Opts}
  end.
