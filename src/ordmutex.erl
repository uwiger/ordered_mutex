%% -*- mode: erlang; erlang-indent-level: 4; indent-tabs-mode: nil -*-
-module(ordmutex).

-export([ do/2 ]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% We use a gen_server-based FIFO queue (one queue per alias) to manage the
%% critical section.
%%
%% Releasing the resource is done by notifying the server.
%%

do(Rsrc, F) when is_function(F, 0) ->
    {ok, Ref} = mutex_server:wait(Rsrc),
    try F()
    after
        mutex_server:done(Rsrc, Ref)
    end.

-ifdef(TEST).

mutex_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
       {"Swarm mutex, N: " ++ integer_to_list(N), fun() -> swarm_do(N) end}
      || N <- [3, 5, 20, 50, 100, 500, 1000, 10000]
     ]}.

setup() ->
    case whereis(mutex_server) of
        undefined ->
            {ok, Pid} = mutex_server:start_link(),
            Pid;
        Pid ->
            Pid
    end.

cleanup(Pid) ->
    unlink(Pid),
    MRef = erlang:monitor(process, Pid),
    exit(Pid, kill),
    receive
        {'DOWN', MRef, _, _, _} ->
            ok
    end.

swarm_do(N) ->
    Rsrc = ?LINE,
    Pid = spawn(fun() -> collect([]) end),
    L = lists:seq(1, N),
    Evens = [X || X <- L, is_even(X)],
    T0 = erlang:system_time(microsecond),
    Pids = [spawn_monitor(fun() ->
                                  send_even(Rsrc, X, Pid)
                          end) || X <- L],
    await_pids(Pids),
    T1 = erlang:system_time(microsecond),
    ?debugFmt("Time (N = ~p): ~w us (~.3f)~n", [N, T1-T0, (T1-T0)/N]),
    Results = fetch(Pid),
    {incorrect_results, []} = {incorrect_results, Results -- Evens},
    {missing_correct_results, []} = {missing_correct_results, Evens -- Results},
    ok.

collect(Acc) ->
    receive
        {_, result, N} ->
            collect([N|Acc]);
        {From, fetch} ->
            From ! {fetch_reply, Acc},
            done
    end.

fetch(Pid) ->
    Pid ! {self(), fetch},
    receive
        {fetch_reply, Result} ->
            Result
    end.

is_even(N) ->
    (N rem 2) =:= 0.

await_pids([{_, MRef}|Pids]) ->
    receive
        {'DOWN', MRef, _, _, _} ->
            await_pids(Pids)
    after 10000 ->
            error(timeout)
    end;
await_pids([]) ->
    ok.

send_even(Rsrc, N, Pid) ->
    do(Rsrc, fun() ->
                     case is_even(N) of
                         true ->
                             Pid ! {self(), result, N};
                         false ->
                             exit(not_even)
                     end
             end).

-endif.
