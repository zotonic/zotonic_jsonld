%% @copyright 2026 Marc Worrell
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

-module(zotonic_jsonld).

-moduledoc("JSON-LD parsing and generation with complete context resolution before standard Zotonic prefix normalization.").

-export([
    parse/1,
    parse/2,
    decode/1,
    decode/2,
    expand/1,
    expand/2,
    generate/1,
    generate/2,
    encode/1,
    encode/2,
    to_triples/1,
    to_triples/2
]).

-type options() :: map().

-export_type([
    options/0
]).

%% @doc Parse JSON-LD using only embedded or supplied contexts by default.
%% External contexts require allow_external_contexts => true in parse/2.

-spec parse(Input) -> {ok, [map()]} | {error, term()}
    when
        Input :: binary() | map() | [map()].
parse(Input) ->
    parse(Input, #{}).

-spec parse(Input, Options) -> {ok, [map()]} | {error, term()}
    when
        Input :: term(),
        Options :: options().
parse(Input, Options) ->
    protect(fun() ->
        rdf_document:compact(jsonld_expand:expand(input(Input), defaults(Options)))
    end).

-spec decode(Input) -> {ok, [map()]} | {error, term()}
    when
        Input :: term().
decode(Input) ->
    parse(Input).

-spec decode(Input, Options) -> {ok, [map()]} | {error, term()}
    when
        Input :: term(),
        Options :: options().
decode(Input, Options) ->
    parse(Input, Options).

%% Standard expansion returns arrays and absolute predicates, without @context.

-spec expand(Input) -> {ok, [map()]} | {error, term()}
    when
        Input :: term().
expand(Input) ->
    expand(Input, #{}).

-spec expand(Input, Options) -> {ok, [map()]} | {error, term()}
    when
        Input :: term(),
        Options :: options().
expand(Input, Options) ->
    protect(fun() ->
        jsonld_expand:expand(input(Input), Options)
    end).

-spec generate(Input) -> {ok, binary()} | {error, term()}
    when
        Input :: term().
generate(Input) ->
    generate(Input, #{}).

-spec generate(Input, Options) -> {ok, binary()} | {error, term()}
    when
        Input :: term(),
        Options :: options().
generate(Input, Options) ->
    case parse(Input, Options) of
        {ok, Docs} ->
            protect(fun() ->
                Context = zotonic_rdf:namespaces(),
                D = case Docs of
                    [Doc] ->
                        Doc;
                    _ ->
                        #{
                            <<"@context">> => Context,
                            <<"@graph">> => [maps:remove(<<"@context">>, X) || X <- Docs]
                        }
                end,
                jsonld_json:encode(D, Options)
            end);
        Error ->
            Error
    end.

-spec encode(Input) -> {ok, binary()} | {error, term()}
    when
        Input :: term().
encode(Input) ->
    generate(Input).

-spec encode(Input, Options) -> {ok, binary()} | {error, term()}
    when
        Input :: term(),
        Options :: options().
encode(Input, Options) ->
    generate(Input, Options).

-spec to_triples(Input) -> {ok, [map()]} | {error, term()}
    when
        Input :: term().
to_triples(Input) ->
    to_triples(Input, #{}).

-spec to_triples(Input, Options) -> {ok, [map()]} | {error, term()}
    when
        Input :: term(),
        Options :: options().
to_triples(Input, Options) ->
    protect(fun() ->
        rdf_document:to_triples(jsonld_expand:expand(input(Input), defaults(Options)))
    end).

defaults(Options) ->
    maps:merge(#{context => zotonic_rdf:namespaces()}, Options).

input(B) when is_binary(B) ->
    jsonld_json:decode(B);
input(M) when is_map(M); is_list(M) ->
    M;
input(_) ->
    throw({jsonld, invalid_document}).

protect(F) ->
    try
        {ok, F()}
    catch
        throw:{jsonld, E} ->
            {error, E};
        throw:{rdf, E} ->
            {error, E};
        error:badarg ->
            {error, invalid_document};
        error:{badmatch, _} ->
            {error, invalid_document}
    end.
