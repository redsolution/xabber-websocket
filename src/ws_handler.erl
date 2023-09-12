-module(ws_handler).
-include_lib("kernel/include/inet.hrl").

-record(xmlel,
{
  name = <<"">> :: binary(),
  attrs    = [] :: [attr()],
  children = [] :: [xmlel() | cdata()]
}).

-record(session,
{
  src_ip,
  src_port,
  dst_ip,
  dst_port,
  connstep = 0,
  xmppserver,
  tcpsocket,
  xmlstream
}).

-type host_port() :: {inet:hostname(), inet:port_number()}.
-type ip_port() :: {inet:ip_address(), inet:port_number()}.
-type network_error() :: {error, inet:posix() | inet_res:res_error()}.
-type(cdata() :: {xmlcdata, CData::binary()}).
-type(attr() :: {Name::binary(), Value::binary()}).
-type(xmlel() :: #xmlel{}).

-export([init/2]).
-export([terminate/3]).
-export([websocket_init/1]).
-export([websocket_handle/2]).
-export([websocket_info/2]).


-define(NS_STREAM, <<"http://etherx.jabber.org/streams">>).
-define(WS_CLOSE, <<"<close xmlns='urn:ietf:params:xml:ns:xmpp-framing'/>">>).
-define(STREAM_START(Server), <<"<stream:stream xmlns='jabber:client' to='",Server/binary,
  "' version='1.0' xmlns:stream='http://etherx.jabber.org/streams' xml:lang='en'>">>).
-define(STREAM_CLOSE, <<"</stream:stream>">>).
-define(WS_TIMEOUT, 60000).
-define(WEBSOCKET_PING, 15000).
-define(NS_WS_PROXY,  <<"urn:xabber:ws:proxy">>).

init(Req, State) ->
  IsXMPPClient = case cowboy_req:parse_header(<<"sec-websocket-protocol">>, Req) of
                   undefined ->
                     undefined;
                   SubProtocols ->
                     lists:member(<<"xmpp">>, SubProtocols)
                 end,
  case IsXMPPClient of
    true ->
      Req2 = cowboy_req:set_resp_header(<<"sec-websocket-protocol">>, <<"xmpp">>, Req),
      {IP, Port} = cowboy_req:peer(Req),
      NewState = #session{src_ip = IP, src_port = Port},
      {cowboy_websocket, Req2, NewState,
        #{idle_timeout => application:get_env(xabber_ws, ws_timeout, ?WS_TIMEOUT)}};
     _ ->
       Req2 = cowboy_req:reply(400, #{<<"content-type">> => <<"text/plain">>},
         <<"unsupported WebSocket protocol">>, Req),
       {ok, Req2, State}
  end.


terminate(Arg0, Arg1, State) when is_record(State, session)->
  lager:debug("Websocket terminated: ~p ~p ~p",[Arg0, Arg1, State]),
  case State#session.tcpsocket of
    undefined -> undefined;
    _ ->
      tcp_send(?STREAM_CLOSE, State#session.tcpsocket),
      tcp_close(State#session.tcpsocket)
  end,
  case State#session.xmlstream of
    undefined -> undefined;
    _ ->
      fxml_stream:close(State#session.xmlstream)
  end,
  ok;
terminate(Arg0, Arg1, State) ->
  lager:debug("Websocket terminated: ~p ~p ~p",[Arg0, Arg1, State]),
  ok.


websocket_init(State) ->
  {ok, State}.

websocket_handle({text, Frame}, State) ->
  X1=fxml_stream:parse_element(Frame),
  #xmlel{name = Name, attrs = Attrs}  =  X1,
  case Name of
    <<"open">> ->
      erlang:start_timer(?WEBSOCKET_PING, self(), <<>>),
      {_,Server} = fxml:get_attr(<<"to">>, Attrs),
      if
        State#session.connstep == 0 ->
          case check_server(Server) of
            <<"allow">> ->
              case init_session_to_xmpp_server(Server) of
                {ok,connected, {Socket, IP, Port}} ->
                  tcp_send(?STREAM_START(Server), Socket),
                  NewStream = fxml_stream:new(self()),
                  NewState = State#session{dst_ip = IP, dst_port = Port,
                    connstep = 1, xmppserver = Server, tcpsocket = Socket,
                    xmlstream = NewStream},
                  {ok,NewState,hibernate};
                {err, Source, Why} ->
                  forward_connection_error_to_ws(Source, Why),
                  {ok,State,hibernate};
                _ ->
                  {stop, State}
              end;
            _ ->
              lager:warning("accessrules: Not allowed domain: ~p", [Server]),
              forward_connection_error_to_ws(accessrules, 'not-allowed-domain'),
              {ok,State,hibernate}
          end;
        true ->
          fxml_stream:close(State#session.xmlstream),
          NewStream = fxml_stream:new(self()),
          Server = State#session.xmppserver,
          tcp_send(?STREAM_START(Server),State#session.tcpsocket),
          NewState = State#session{ xmlstream = NewStream},
          {ok, NewState, hibernate}
      end;
    <<"close">> ->
      tcp_send(?STREAM_CLOSE, State#session.tcpsocket),
      tcp_close(State#session.tcpsocket),
      {stop,State};
    _ ->
      tcp_send(Frame, State#session.tcpsocket),
      {ok,State,hibernate}
  end;
websocket_handle(pong, State) ->
  {ok, State, hibernate};
websocket_handle({ping, Payload}, State) ->
  {reply, {pong, Payload}, State, hibernate};
websocket_handle(_Frame, State) ->
  {ok, State, hibernate}.

websocket_info({timeout, _Ref, _Msg}, State) ->
  erlang:start_timer(?WEBSOCKET_PING, self(), <<>>),
  {reply, {ping, <<>>}, State};
websocket_info({reply, fromxmppsrv, Packet}, State) ->
  {reply, {text, Packet}, State,hibernate};
websocket_info({tcp, Socket, Packet}, State) ->
  inet:setopts(Socket,  [{active,  once}]),
  Stream = fxml_stream:parse(State#session.xmlstream, Packet),
  NewState = State#session{xmlstream = Stream},
  {ok, NewState, hibernate};
websocket_info({ssl, Socket, Packet}, State) ->
  ssl:setopts(Socket,  [{active,  once}]),
  Stream = fxml_stream:parse(State#session.xmlstream, Packet),
  NewState = State#session{xmlstream = Stream},
  {ok, NewState, hibernate};
websocket_info({tcp_closed, Socket}, State) ->
  lager:info("tcp_socket: ~p connection closed",[Socket]),
  {stop, State};
websocket_info({ssl_closed, Socket}, State) ->
  lager:info("ssl_socket: ~p connection closed",[Socket]),
  {stop, State};
websocket_info({start_tls}, State) ->
  case tcp_upgrade_to_tls(State#session.tcpsocket) of
    {ok, SSLSocket}->
      fxml_stream:close(State#session.xmlstream),
      NewStream = fxml_stream:new(self()),
      Server = State#session.xmppserver,
      tcp_send(?STREAM_START(Server),SSLSocket),
      NewState = State#session{connstep = 2, tcpsocket = SSLSocket, xmlstream = NewStream},
      {ok, NewState, hibernate};
    {err, _Why} ->
      inet:close(State#session.tcpsocket),
      {stop, State}
  end;
websocket_info({ws,stop, Why}, State) ->
  lager:debug("web_socket closed: ~p",[Why]),
  {stop, State};
websocket_info({'$gen_event', XMLStreamEl}, State) ->
  XMLStreamEl2 = case XMLStreamEl of
    {xmlstreamstart, _, Attrs} ->
      if
        State#session.connstep < 2 ->
          Attrs2 = [{<<"xmlns">>, <<"urn:ietf:params:xml:ns:xmpp-framing">>} |
                lists:keydelete(<<"xmlns">>, 1, lists:keydelete(<<"xmlns:stream">>, 1, Attrs))],
          {xmlstreamelement, #xmlel{name = <<"open">>, attrs = Attrs2}};
        true ->
          {xmlstreamelement , skip}
      end;
    {xmlstreamelement, #xmlel{name=Name} = XMLel} ->
      XMLel2 = case Name of
        <<"stream:features">> ->
          case fxml:get_subtag(XMLel, <<"proxy">>) of
            #xmlel{attrs = [{<<"xmlns">>, ?NS_WS_PROXY}]} ->
              send_proxy_iq(State);
            _ ->
              ok
          end,
          case fxml:get_subtag(XMLel, <<"starttls">>) of
            #xmlel{name = <<"starttls">>} ->
              tcp_send(<<"<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>">>,
                State#session.tcpsocket),
              skip;
            _ ->
              fxml:replace_tag_attr(<<"xmlns:stream">>, ?NS_STREAM, XMLel)
          end;
        <<"stream:", _/binary>> ->
          fxml:replace_tag_attr(<<"xmlns:stream">>, ?NS_STREAM, XMLel);
        <<"proceed">> ->
          self() ! {start_tls},
          skip;
        _ ->
          case fxml:get_tag_attr_s(<<"xmlns">>, XMLel) of
            <<"">> ->
              fxml:replace_tag_attr(<<"xmlns">>, <<"jabber:client">>, XMLel);
            _ ->
              XMLel
          end
      end,
      {xmlstreamelement , XMLel2};
    {xmlstreamend, _} ->
      {xmlstreamelement, #xmlel{name = <<"close">>,
        attrs = [{<<"xmlns">>, <<"urn:ietf:params:xml:ns:xmpp-framing">>}]}};
    _ ->
      XMLStreamEl
  end,
  case XMLStreamEl2 of
    {xmlstreamelement , skip} ->
      skip;
    {xmlstreamelement, El} ->
      self() ! {reply, fromxmppsrv, fxml:element_to_binary(El)};
    {_, Bin} ->
      self() ! {reply, fromxmppsrv, Bin}
  end,
  {ok, State, hibernate};
websocket_info(Info, State) ->
  lager:debug("web_socket closed ~p", [Info]),
  {stop, State}.


init_session_to_xmpp_server(Server) ->
  case dns_resolve(binary_to_list(Server)) of
    {ok, AddrPortList} ->
      case  tcp_connect(AddrPortList, []) of
        {ok, Address, Port, Socket} ->
          lager:info("tcp_socket:~p Connected to  ~s (~s:~p)",
            [Socket, Server, inet_parse:ntoa(Address), Port]),
          {ok,connected, {Socket, Address, Port}};
        {error, Why} ->
          lager:error("ERROR: Can not connect to ~s~p: ~p ",[Server,
            [inet_parse:ntoa(A)++":"++integer_to_list(P) || {A,P} <- AddrPortList],Why]),
          {err,tcp_connect, Why}
      end;
    {error, Why} ->
      lager:error("ERROR: Can not resolve domain name ~p : ~p",[Server,Why]),
      {err, dns, 'dns-error'}
  end.

tcp_connect([], Err) ->
  {error, Err};
tcp_connect([{Address, Port} | AddrPortList ], _Err) ->
  SocketOpts = [binary, {active, once}, {reuseaddr, true}, {nodelay, true}, {keepalive, true}],
  case gen_tcp:connect(Address, Port, SocketOpts) of
    {ok, Socket} ->
      {ok, Address, Port, Socket};
    {error, Why} ->
      tcp_connect(AddrPortList, Why)
  end.

tcp_upgrade_to_tls(Socket) ->
  case ssl:connect(Socket, []) of
    {ok, SSLSocket} ->
      lager:info("tcp_socket ~p upgrade to TLS ~p~n", [Socket,SSLSocket]),
      {ok, SSLSocket};
    {error, Why} ->
      lager:error("ERROR TCP socket not upgrade to TLS ~p~n",[Why]),
      {err, Why}
  end.

tcp_send(Packet, Socket) ->
  case Socket of
    {sslsocket,_,_} ->
      catch ssl:send(Socket,Packet);
    _ ->
      catch gen_tcp:send(Socket,Packet)
  end.


tcp_close(Socket) ->
  case Socket of
    {sslsocket,_,_} ->
      catch ssl:close(Socket);
    _ ->
      catch inet:close(Socket)
  end.


forward_connection_error_to_ws(_Source, Why) ->
  WhyBin= erlang:atom_to_binary(Why, utf8),
  self() ! {reply, fromxmppsrv, <<"<stream:error xmlns:stream='http://etherx.jabber.org/streams'><",
    WhyBin/binary," xmlns='urn:ietf:params:xml:ns:xmpp-streams'/>",
    "</stream:error>">>},
  self() ! {reply, fromxmppsrv, ?WS_CLOSE},
  self() ! {ws, stop, Why}.


send_proxy_iq(#session{connstep = 1, src_ip = SrcIP, src_port = SrcPort,
  dst_ip = DstIP, dst_port = DstPort, tcpsocket = Socket}) ->
  IQ = iolist_to_binary(io_lib:format(
    "<iq type='set' id='proxy1'>
       <proxy xmlns='~s' src_ip='~s' src_port='~p' dst_ip='~s' dst_port='~p' />
    </iq>",
    [?NS_WS_PROXY, inet:ntoa(SrcIP), SrcPort, inet:ntoa(DstIP), DstPort])),
  tcp_send(IQ, Socket);
send_proxy_iq(_) -> ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Access rules                        %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

check_server(Server) ->
  %% domain names consisting only of numbers and dots are not allowed
  try binary_to_integer(binary:replace(Server,<<$.>>,<<>>)) of
    _ ->
      <<"deny">>
  catch _:_ ->
    check_access(Server)
  end.

check_access(Server) ->
  Def_rule = case application:get_env(xabber_ws, allow_all, true) of
               true -> <<"allow">>;
               _ -> <<"deny">>
             end,
  ACL_file_path = filename:join([code:root_dir(), "config", "accessrules"]),
  case file:read_file(ACL_file_path) of
    {ok,<<>>} -> Def_rule;
    {ok, Binary} ->
      {ok, MP} = re:compile("[#|%].*\n"),
      Binary2 = re:replace(Binary,MP,"\n",[{return,binary},global]),
      ACL = lists:filtermap(
        fun(X) -> case string:lexemes(string:lowercase(X)," ") of
                    [] -> false;
                    [W1, W2] ->
                      {true, {W1, W2}};
                    _ ->
                      lager:error("accessrules: Wrong record in accessrules: ~s",[X]),
                      false
                    end
        end,
        binary:split(Binary2,<<"\n">>,[global])),
      case lists:keyfind(Server, 2, ACL) of
        {Rule, _ } -> Rule;
        _ -> Def_rule
      end;
    {error, Reason} ->
      lager:error("accessrules: File read error: ~p",[Reason]),
      Def_rule
  end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% DNS lookup.                         %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


-spec dns_resolve(string()) -> {ok, [ip_port()]} | network_error().
dns_resolve(Host) ->
  Timeout = application:get_env(xabber_ws, dns_timeout, 3000),
  Retries = application:get_env(xabber_ws, dns_retries, 3),
  case srv_record_resolve(Host, Timeout, Retries) of
    {error, _Reason} ->
      a_lookup([{Host, 5222}], [], {error, nxdomain});
    {ok, HostPortList} ->
      a_lookup(HostPortList, [], {error, nxdomain})
  end.


-spec srv_record_resolve(string(), timeout(), integer()) ->
  {ok, [host_port()]} | network_error().
srv_record_resolve(_Host, _Timeout, Retries) when Retries < 1 ->
  {error, timeout};
srv_record_resolve(Host, Timeout, Retries) ->
  case inet_res:getbyname("_xmpp-client._tcp." ++ Host, srv, Timeout) of
    {ok, HostsList} ->
      to_host_port_list(HostsList);
    {error, timeout} ->
      srv_record_resolve(Host, Timeout, Retries - 1);
    {error, _} = Err ->
      Err
  end.

-spec a_lookup([{inet:hostname(), inet:port_number()}],
     [ip_port()], network_error()) -> {ok, [ip_port()]} | network_error().
a_lookup([{Host, Port}| HostPortList], Acc, Err) ->
  Timeout = application:get_env(xabber_ws, dns_timeout, 3000),
  Retries = application:get_env(xabber_ws, dns_retries, 3),
  case a_lookup(Host, Port, Timeout, Retries) of
    {error, Reason} ->
      a_lookup(HostPortList, Acc, {error, Reason});
    {ok, AddrPorts} ->
      a_lookup(HostPortList, Acc ++ AddrPorts, Err)
  end;
a_lookup([], [], Err) ->
  Err;
a_lookup([], Acc, _) ->
  {ok, Acc}.

-spec a_lookup(inet:hostname(), inet:port_number(),
    timeout(), integer()) -> {ok, [ip_port()]} | network_error().
a_lookup(_Host, _Port, _Timeout, Retries) when Retries < 1 ->
  {error, timeout};
a_lookup(Host, Port, Timeout, Retries) ->
  Start = erlang:monotonic_time(milli_seconds),
  case inet:gethostbyname(Host, inet, Timeout) of
    {error, nxdomain} = Err ->
      End = erlang:monotonic_time(milli_seconds),
      if (End - Start) >= Timeout ->
        a_lookup(Host, Port, Timeout, Retries - 1);
        true ->
          Err
      end;
    {error, _} = Err ->
      Err;
    {ok, HostsList} ->
      to_addr_port_list(HostsList, Port)
  end.

-spec to_host_port_list(inet:hostent()) -> {ok, [host_port()]} | {error, nxdomain}.
to_host_port_list(#hostent{h_addr_list = AddrList}) ->
  AddrList2 = lists:flatmap(
    fun({Priority, Weight, Port, Host}) ->
      [{Priority + 65536 - Weight + rand:uniform(), Host, Port}];
      (_) ->
        []
    end, AddrList),
  HostPortList = [{Host, Port}
    || {_, Host, Port} <- lists:usort(AddrList2)],
  case HostPortList of
    [] -> {error, nxdomain};
    _ -> {ok, HostPortList}
  end.

-spec to_addr_port_list(inet:hostent(), inet:port_number()) ->
  {ok, [ip_port()]} | {error, nxdomain}.
to_addr_port_list(#hostent{h_addr_list = AddrList}, Port) ->
  AddrPortList = lists:map(fun(Addr) -> {Addr, Port} end, AddrList),
  case AddrPortList of
    [] -> {error, nxdomain};
    _ -> {ok, AddrPortList}
  end.

