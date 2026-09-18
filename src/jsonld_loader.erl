%% @copyright 2026 Marc Worrell
%% @doc HTTP(S) loader used only after allow_external_contexts is enabled.
%% Applications can replace it using the document_loader option.
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

-module(jsonld_loader).

-export([
    load/1
]).

-spec load(Url) -> {ok, map()} | {error, term()}
    when
        Url :: binary().
load(Url) ->
    load(Url, 5).

load(_Url, 0) ->
    {error, too_many_redirects};
load(Url, N) ->
    case uri_string:parse(Url) of
        #{scheme := Scheme} when Scheme =:= <<"http">>; Scheme =:= <<"https">> ->
            {ok, _} = application:ensure_all_started(inets),
            {ok, _} = application:ensure_all_started(ssl),
            Ssl = [
                {verify, verify_peer},
                {cacerts, public_key:cacerts_get()},
                {customize_hostname_check, [
                    {match_fun, public_key:pkix_verify_hostname_match_fun(https)}
                ]}
            ],
            Opts = [{timeout, 10000}, {connect_timeout, 5000}, {autoredirect, false}, {ssl, Ssl}],
            Headers = [{"accept", "application/ld+json, application/json"}],
            case
                httpc:request(get, {binary_to_list(Url), Headers}, Opts, [{body_format, binary}])
            of
                {ok, {{_, 200, _}, _, Body}} when byte_size(Body) =< 4194304 ->
                    {ok, #{document => Body, document_url => Url}};
                {ok, {{_, Status, _}, Hs, _}} when
                    Status =:= 301; Status =:= 302; Status =:= 303; Status =:= 307; Status =:= 308
                ->
                    case proplists:get_value("location", Hs) of
                        undefined ->
                            {error, missing_location};
                        L ->
                            load(jsonld_context:resolve(list_to_binary(L), Url), N - 1)
                    end;
                {ok, {{_, Status, _}, _, _}} ->
                    {error, {http_status_or_size, Status}};
                {error, E} ->
                    {error, E}
            end;
        _ ->
            {error, unsupported_url_scheme}
    end.
