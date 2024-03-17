-module(mutex_server).

-behavior(gen_server).

-export([wait/1,
         done/2]).

-export([start_link/0]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(st, { queues = #{}
            , empty_q = queue:new() }).  %% perhaps silly optimization

wait(Rsrc) ->
    gen_server:call(?MODULE, {wait, Rsrc}, infinity).

done(Rsrc, Ref) ->
    gen_server:cast(?MODULE, {done, Rsrc, Ref}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {ok, #st{}}.

handle_call({wait, Rsrc}, {Pid, _} = From, #st{ queues = Queues
                                              , empty_q = NewQ } = St) ->
    MRef = erlang:monitor(process, Pid),
    Q0 = maps:get(Rsrc, Queues, NewQ),
    WasEmpty = queue:is_empty(Q0),
    Q1 = queue:in({From, MRef}, Q0),
    St1 = St#st{ queues = Queues#{Rsrc => Q1} },
    case WasEmpty of
        true ->
            {reply, {ok, MRef}, St1};
        false ->
            {noreply, St1}
    end.

handle_cast({done, Rsrc, MRef}, #st{ queues = Queues } = St) ->
    case maps:find(Rsrc, Queues) of
        {ok, Q} ->
            case queue:out(Q) of
                {{value, {_From, MRef}}, Q1} ->
                    erlang:demonitor(MRef),
                    Queues1 = maybe_dispatch_one(Rsrc, Q1, Queues),
                    {noreply, St#st{ queues = Queues1 }};
                {_, _} ->
                    %% Not the lock holder
                    {noreply, St}
            end;
        error ->
            {noreply, St}
    end.

handle_info({'DOWN', MRef, process, _, _}, #st{queues = Queues} = St) ->
    Queues1 =
        maps:fold(
          fun(Rsrc, Q, Acc) ->
                  drop_or_filter(Rsrc, Q, MRef, Acc)
          end, #{}, Queues),
    {noreply, St#st{ queues = Queues1 }};
handle_info(_, St) ->
    {noreply, St}.

terminate(_, _) ->
    ok.

code_change(_FromVsn, St, _Extra) ->
    {ok, St}.

%% In this function, we don't actually pop
maybe_dispatch_one(Rsrc, Q, Queues) ->
    case queue:peek(Q) of
        empty ->
            maps:remove(Rsrc, Queues);
        {value, {From, MRef}} ->
            gen_server:reply(From, {ok, MRef}),
            Queues#{Rsrc => Q}
    end.
        
drop_or_filter(Rsrc, Q, MRef, Acc) ->
    case queue:peek(Q) of
        {value, {_, MRef}} ->
            Q1 = queue:drop(Q),
            maybe_dispatch_one(Rsrc, Q1, Acc);
        {value, _Other} ->
            Q1 = queue:filter(fun({_,M}) -> M =/= MRef end, Q),
            case queue:is_empty(Q1) of
                true ->
                    Acc;
                false ->
                    Acc#{Rsrc => Q1}
            end;
        empty ->
            Acc
    end.
