%% @copyright 2026 Marc Worrell
%% Vendored W3C JSON-LD 1.1 expansion suite, with upstream fixture licensing.
%% Source: https://github.com/w3c/json-ld-api/tree/main/tests
%% @end

%% Copyright 2026 Marc Worrell
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(jsonld_w3c_tests).

-include_lib("eunit/include/eunit.hrl").

expansion_test_() ->
    case os:getenv("W3C_JSONLD_TESTS") of
        false ->
            tests(default_root());
        Root ->
            tests(Root)
    end.

tests(Root) ->
    Manifest = read(Root, <<"expand-manifest.jsonld">>),
    [
        {binary_to_list(maps:get(<<"name">>, T)), fun() ->
            check(Root, T)
        end}
     || T <- maps:get(<<"sequence">>, Manifest), supported(T)
    ].

default_root() ->
    Candidates = [
        filename:join(filename:dirname(?FILE), "data/w3c-jsonld"),
        filename:join(filename:dirname(code:which(?MODULE)), "data/w3c-jsonld")
    ],
    case [P || P <- Candidates, filelib:is_file(filename:join(P, "expand-manifest.jsonld"))] of
        [Root | _] ->
            Root;
        [] ->
            error(missing_w3c_jsonld_fixtures)
    end.

supported(T) ->
    Opts = maps:get(<<"option">>, T, #{}),
    maps:get(<<"specVersion">>, Opts, <<"json-ld-1.1">>) =/= <<"json-ld-1.0">> andalso
        maps:get(<<"processingMode">>, Opts, <<"json-ld-1.1">>) =/= <<"json-ld-1.0">>.

check(Root, T) ->
    Input = maps:get(<<"input">>, T),
    Opts = maps:get(<<"option">>, T, #{}),
    Base = maps:get(<<"base">>, Opts, <<"https://w3c.github.io/json-ld-api/tests/", Input/binary>>),
    Loader = fun(Url) ->
        case binary:split(Url, <<"/tests/">>) of
            [_, Path] ->
                {ok, read(Root, Path)};
            _ ->
                {error, offline}
        end
    end,
    Context = case maps:find(<<"expandContext">>, Opts) of
        {ok, Path} ->
            maps:get(<<"@context">>, read(Root, Path));
        error ->
            #{}
    end,
    Result = zotonic_jsonld:expand(read(Root, Input), #{
        base => Base,
        allow_external_contexts => true,
        document_loader => Loader,
        context => Context
    }),
    case maps:find(<<"expect">>, T) of
        {ok, Expected} ->
            ?assertMatch({ok, _}, Result),
            {ok, Actual} = Result,
            ?assertEqual(normalize(read(Root, Expected)), normalize(Actual));
        error ->
            ?assertMatch({error, _}, Result)
    end.

read(Root, Path) ->
    {ok, Binary} = file:read_file(filename:join(Root, binary_to_list(Path))),
    jsonld_json:decode(Binary).

%% Expanded sets are unordered; JSON payloads and RDF lists retain order.
normalize(M) when is_map(M) ->
    maps:map(
        fun
            (<<"@list">>, L) ->
                [normalize(V) || V <- L];
            (<<"@value">>, V) ->
                V;
            (_, V) ->
                normalize(V)
        end,
        M
    );
normalize(L) when is_list(L) ->
    lists:sort([normalize(V) || V <- L]);
normalize(V) ->
    V.
