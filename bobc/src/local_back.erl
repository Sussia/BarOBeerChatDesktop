%%%-------------------------------------------------------------------
%%% @author User
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. Дек. 2019 21:15
%%%-------------------------------------------------------------------
-module(local_back).
-author("User").

-behaviour(gen_server).
-include_lib("stdlib/include/qlc.hrl").


%% API
-export([
  start_link/2,
  send/1
  ]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(message, {msg_id, msg, from, time}).

-record(state, {websocket, external, remote}).

%%%===================================================================
%%% API
%%%===================================================================

send(Msg)->
  gen_server:cast(?SERVER, {send, Msg}).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------

start_link(External, Remote) ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [External, Remote], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([External, Remote]) ->
  listen_new_msg(External),
  {ok, #state{external = External, remote = Remote}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).

handle_call({websocket_init,  {WebSocket, ChatId}}, _From, #state{external = External, remote = Remote}) ->
  NewState =  #state{websocket = WebSocket, external = External, remote = Remote},
  Msgs = print_history(ChatId),
  {reply,{ok, Msgs}, NewState};

handle_call(_Request, _From, State) ->
  {reply, ok, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).


handle_cast({send, Msg}, #state{websocket = WebSocket} = State)->
  WebSocket ! {send,Msg},
  {noreply, State};


%%That function take the msg from front and save it in DB. After that it should to send msg to all users
handle_cast({forward, Msg}, State) ->

  forward(Msg, State#state.remote),
  {noreply, State}.




%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
%%-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
%%  {noreply, NewState :: #state{}} |
%%  {noreply, NewState :: #state{}, timeout() | hibernate} |
%%  {stop, Reason :: term(), NewState :: #state{}}).
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

print_history(ChatId)->
  mnesia:start(),
  mnesia:wait_for_tables([list_to_atom(ChatId)], 20000),
  do(qlc:q([{X#message.msg_id, X#message.from,X#message.msg, X#message.time } || X <- mnesia:table(list_to_atom(ChatId))])).

do(Q) ->
  F = fun() -> qlc:e(Q) end,
  {atomic, Val} = mnesia:transaction(F),
  Val.

forward(Msg, Remote)->
  {ok, Socket} = gen_tcp:connect({127,0,0,1}, Remote, [binary, {active, false}]),
  gen_tcp:send(Socket, Msg).

listen_new_msg(Remote)->
  Pid = spawn_link(
    fun() ->
      {ok, LSocket} = gen_tcp:listen(Remote, [binary, {active, false}]),
      spawn(fun() -> acceptor(LSocket) end),
      timer:sleep(infinity)
    end),
  {ok, Pid}.

acceptor(LSocket)->
  {ok, Socket}= gen_tcp:accept(LSocket),
  spawn(fun() -> acceptor(LSocket) end),
  handle(Socket).

handle(Socket)->
  inet:setopts(Socket,[{active, once}]),
  receive
    {tcp, Socket,<<"quit, _/binary">>} ->
      gen_tcp:close(Socket);
    {tcp, Socket, Msg}->
      io:format("~p~n",[Msg]),
      send(Msg),
      handle(Socket)
  end.