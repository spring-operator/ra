-module(ra_machine_version_SUITE).

-compile(export_all).

-export([
         ]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Common Test callbacks
%%%===================================================================

all() ->
    [
     {group, tests}
    ].


all_tests() ->
    [
     % server_with_higher_version_needs_quorum_to_be_elected,
     % unversioned_machine_never_sees_machine_version_command,
     server_upgrades_machine_state_on_noop_command
     % lower_version_does_not_apply_until_upgraded,
     % snapshot_persists_machine_version
    ].


%% gnarly: for rabbit_fifo we need to capture the active module and version
%% at the index to be snapshotted. This means the release_cursor effect need to be
%% overloaded to support a {version(), module()} field as well

groups() ->
    [
     {tests, [], all_tests()}
    ].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_, Config) ->
    PrivDir = ?config(priv_dir, Config),
    {ok, _} = ra:start_in(PrivDir),
    Config.

end_per_group(_Group, _Config) ->
    ok.

init_per_testcase(TestCase, Config) ->
    ra_server_sup_sup:remove_all(),
    ServerName1 = list_to_atom(atom_to_list(TestCase) ++ "1"),
    ServerName2 = list_to_atom(atom_to_list(TestCase) ++ "2"),
    ServerName3 = list_to_atom(atom_to_list(TestCase) ++ "3"),
    Cluster = [{ServerName1, node()},
               {ServerName2, node()},
               {ServerName3, node()}],
    [
     {modname, TestCase},
     {cluster, Cluster},
     {cluster_name, TestCase},
     {uid, atom_to_binary(TestCase, utf8)},
     {server_id, {TestCase, node()}},
     {uid2, atom_to_binary(ServerName2, utf8)},
     {server_id2, {ServerName2, node()}},
     {uid3, atom_to_binary(ServerName3, utf8)},
     {server_id3, {ServerName3, node()}}
     | Config].

end_per_testcase(_TestCase, _Config) ->
    meck:unload(),
    ok.

%%%===================================================================
%%% Test cases
%%%===================================================================
server_with_higher_version_needs_quorum_to_be_elected(_Config) ->
    error({todo, ?FUNCTION_NAME}).

unversioned_machine_never_sees_machine_version_command(_Config) ->
    error({todo, ?FUNCTION_NAME}).

server_upgrades_machine_state_on_noop_command(Config) ->
    Mod = ?config(modname, Config),
    meck:new(Mod, [non_strict]),
    meck:expect(Mod, init, fun (_) -> init_state end),
    meck:expect(Mod, version, fun () -> 1 end),
    meck:expect(Mod, which_module, fun (_) -> Mod end),
    meck:expect(Mod, apply, fun (_, dummy, S) ->
                                    {S, ok};
                                (_, {machine_version, 0, 1}, init_state) ->
                                    {state_v1, ok};
                                (_, {machine_version, 1, 2}, state_v1) ->
                                    {state_v2, ok}
                            end),
    ClusterName = ?config(cluster_name, Config),
    ServerId = ?config(server_id, Config),
    ok = start_cluster(ClusterName, {module, Mod, #{}}, [ServerId]),
    % need to execute a command here to ensure the noop command has been fully
    % applied. The wal fsync could take a few ms causing the race
    {ok, ok, _} = ra:process_command(ServerId, dummy),
    %% assert state_v1
    {ok, {_, state_v1}, _} = ra:leader_query(ServerId,
                                             fun (S) ->
                                                    ct:pal("leader_query ~w", [S]),
                                                   S
                                             end),
    ok = ra:stop_server(ServerId),
    %% increment version
    meck:expect(Mod, version, fun () -> 2 end),
    ok = ra:restart_server(ServerId),
    {ok, ok, _} = ra:process_command(ServerId, dummy),

    {ok, {_, state_v2}, _} = ra:leader_query(ServerId, fun ra_lib:id/1),
    ok.

lower_version_does_not_apply_until_upgraded(_Config) ->
    %% S1, S2, S3 with v1 - S1 leader
    %% upgrade version to v2 for all but C3
    %% meck:expect(Mod, version, fun () when self() == C3 -> {1, Mod};
    %%                               () -> {1, Mod} end),
    %% Restart S2
    %% Restart S1
    %% Assert S3 is not the leader
    %% commit a command to the state machine
    %% Validate S3 has not applied it but has a matching index
    %% upgrade version to v2 for all
    %% meck:expect(Mod, version, fun () -> {2, Mod} end),
    %% Restart S3
    %% Validate the final command has been applied
    error({todo, ?FUNCTION_NAME}).

snapshot_persists_machine_version(_Config) ->
    error({todo, ?FUNCTION_NAME}).

%% Utility

validate_state_enters(States) ->
    lists:foreach(fun (S) ->
                          receive {ra_event, _, {machine, {state_enter, S}}} -> ok
                          after 250 ->
                                    flush(),
                                    ct:pal("S ~w", [S]),
                                    exit({timeout, S})
                          end
                  end, States).

start_cluster(ClusterName, Machine, ServerIds) ->
    {ok, Started, _} = ra:start_cluster(ClusterName, Machine, ServerIds),
    _ = ra:members(hd(Started)),
    ?assertEqual(length(ServerIds), length(Started)),
    ok.

validate_process_down(Name, 0) ->
    exit({process_not_down, Name});
validate_process_down(Name, Num) ->
    case whereis(Name) of
        undefined ->
            ok;
        _ ->
            timer:sleep(100),
            validate_process_down(Name, Num-1)
    end.

flush() ->
    receive
        Any ->
            ct:pal("flush ~p", [Any]),
            flush()
    after 0 ->
              ok
    end.
