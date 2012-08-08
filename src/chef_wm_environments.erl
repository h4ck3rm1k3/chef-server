%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
%% ex: ts=4 sw=4 et
%% @author John Keiser <jkeiser@opscode.com>
%% @author Douglas Triggs
%% @copyright 2012 Opscode, Inc.

-module(chef_wm_environments).

-include("chef_wm.hrl").

-mixin([{chef_wm_base, [content_types_accepted/2,
                        content_types_provided/2,
                        finish_request/2,
                        malformed_request/2,
                        ping/2,
                        post_is_create/2]}]).

-mixin([{?BASE_RESOURCE, [forbidden/2,
                          is_authorized/2,
                          service_available/2]}]).

%% I think we will end up moving the generic complete wm callbacks like post_is_create,
%% content_types_* into chef_wm_base and mixing those in here separately so that we only
%% have to have those defined in one place.

%% chef_wm behavior callbacks
-behaviour(chef_wm).
-export([auth_info/2,
         init/1,
         malformed_request_message/3,
         request_type/0,
         validate_request/3]).

-export([allowed_methods/2,
         create_path/2,
         from_json/2,
         resource_exists/2,
         to_json/2]).

init(Config) ->
    chef_wm_base:init(?MODULE, Config).

request_type() ->
    "environments".

allowed_methods(Req, State) ->
    {['POST', 'GET'], Req, State}.

validate_request('GET', Req, State) ->
    {Req, State#base_state{resource_state =
                               #environment_state{}}};
validate_request('POST', Req, State) ->
    Body = wrq:req_body(Req),
    {ok, Environment} = chef_environment:parse_binary_json(Body),
    % POST /environments/_default can come from the org creator, in which case
    % superuser is allowed.  When POST /organizations is implemented in Erchef,
    % we should remove this.  No other endpoint gives special treatment to
    % superuser.
    Name = ej:get({<<"name">>}, Environment),
    SuperuserBypassesChecks = case Name of
        <<"_default">> -> true;
        _ -> false
    end,
    {Req, State#base_state{superuser_bypasses_checks = SuperuserBypassesChecks,
                           resource_state =
                               #environment_state{environment_data = Environment}}}.

auth_info(Req, State) ->
    {{create_in_container, environment}, Req, State}.

resource_exists(Req, State) ->
    {true, Req, State}.

create_path(Req, #base_state{resource_state = EnvironmentState}=State) ->
    #environment_state{environment_data = EnvironmentData} = EnvironmentState,
    Name = ej:get({<<"name">>}, EnvironmentData),
    {binary_to_list(Name), Req, State}.

from_json(Req, #base_state{resource_state = EnvironmentState}=State) ->
    #environment_state{environment_data = EnvironmentData,
                       environment_authz_id = AuthzId
                      } = EnvironmentState,
    chef_wm_base:create_from_json(Req, State, chef_environment, {authz_id, AuthzId},
                                  EnvironmentData).

to_json(Req, State) ->
    {all_environments_json(Req, State), Req, State}.

all_environments_json(Req, #base_state{chef_db_context = DbContext,
                                       organization_name = OrgName}) ->
    EnvNames = chef_db:fetch_environments(DbContext, OrgName),
    RouteFun = ?BASE_ROUTES:bulk_route_fun(environment, Req),
    UriMap= [{Name, RouteFun(Name)} || Name <- EnvNames],
    ejson:encode({UriMap}).

% TODO: previously this used chef_rest_util and handled a wide range of messages
malformed_request_message(Any, _Req, _State) ->
    error({unexpected_malformed_request_message, Any}).
