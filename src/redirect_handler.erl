-module(redirect_handler).


%% API
-export([init/2]).

init(Req0, RedirectPort) ->
  URI = cowboy_req:uri(Req0, #{scheme => "https", port => RedirectPort}),
  Req = cowboy_req:reply(301, #{<<"location">> => URI}, Req0),
  {ok, Req, RedirectPort}.
