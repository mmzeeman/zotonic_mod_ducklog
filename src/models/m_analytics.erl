%% @author Maas-Maarten Zeeman <mmzeeman@xs4all.nl>
%% @copyright 2024-2025 Maas-Maarten Zeeman
%% @doc API to view statistics of a site. 

%% Copyright 2024-2025 Maas-Maarten Zeeman
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

-module(m_analytics).
-author("Maas-Maarten Zeeman <mmzeeman@xs4all.nl>").
-behaviour(zotonic_model).

-export([
    m_get/3
]).

-export([
    stats_overview/1, stats_overview/3,
    rsc_stats_overview/2, rsc_stats_overview/4,
    unique_visitors/1, unique_visitors/3,

    popular_pages/3,

    popular_rsc_pages/2,

    popular_resources/1, popular_resources/3,

    erroring_pages/1, erroring_pages/3,

    peer_ip_analytics/3,
    controller_health/3,

    page_views/1, sessions/1, 

    dispatch_rule_health/1, dispatch_rule_health/3,
    user_activity/1, user_activity/3
]).

-include_lib("zotonic_core/include/zotonic.hrl").

%% TODO add access control to the api.

m_get([<<"stats_overview">> | Rest], _Msg, Context) ->
    {ok, {stats_overview(Context), Rest}};

m_get([<<"rsc_stats_overview">>, Rsc | Rest], _Msg, Context) ->
    {ok, {rsc_stats_overview(Rsc, Context), Rest}};

m_get([<<"unique_visitors">> | Rest], _Msg, Context) ->
    {ok, {unique_visitors(Context), Rest}};
m_get([<<"dispatch_rule_health">> | Rest], _Msg, Context) ->
    {ok, {dispatch_rule_health(Context), Rest}};

m_get([<<"popular_pages">>, Rsc | Rest], _Msg, Context) ->
    {ok, {popular_rsc_pages(Rsc, Context), Rest}};

m_get([<<"popular_pages">> | Rest], _Msg, Context) ->
    {ok, {popular_pages(Context), Rest}};

m_get([<<"popular_resources">> | Rest], _Msg, Context) ->
    {ok, {popular_resources(Context), Rest}};

m_get([<<"popular_referrers">>, Rsc | Rest], _Msg, Context) ->
    {ok, {popular_referrers(Rsc, Context), Rest}};

m_get([<<"access_log">>, Rsc | Rest], _Msg, Context) ->
    {ok, {access_log(Rsc, Context), Rest}};

m_get([<<"user_activity">> | Rest], _Msg, Context) ->
    {ok, {user_activity(Context), Rest}};

m_get([<<"page_views">> | Rest], _Msg, Context) ->
    {ok, {page_views(Context), Rest}};
m_get([<<"sessions">> | Rest], _Msg, Context) ->
    {ok, {sessions(Context), Rest}};
m_get(V, _Msg, _Context) ->
    ?LOG_INFO("Unknown ~p lookup: ~p", [?MODULE, V]),
    {error, unknown_path}.

page_views(Context) ->
    Until = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(Until, 30),
    page_views(From, Until, Context).

page_views(From, Until, Context) -> 
    Site = z_context:site(Context),

    Q = <<"
SELECT
    count(*)
FROM
    access_log
WHERE
    rsc_id IS NOT NULL
    AND site == $site
    AND timestamp >= $from
    AND timestamp <= $until
">>,

    case z_duckdb:q(Q, #{ from => From,
                           until => Until,
                           site => Site} ) of
        {ok, _, [{Count}]} ->
            Count;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get page view count">>, reason => Reason }),
            []
    end.

sessions(Context) ->
    Until = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(Until, 30),
    sessions(From, Until, Context).

sessions(From, Until, Context) -> 
    Site = z_context:site(Context),

    Q = <<"
SELECT
    count(distinct session_id)
FROM
    access_log
WHERE
    session_id IS NOT NULL
    AND site == $site
    AND timestamp >= $from
    AND timestamp <= $until
">>,

    case z_duckdb:q(Q, #{ from => From,
                           until => Until,
                           site => Site} ) of
        {ok, _, [{Count}]} ->
            Count;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get page view count">>, reason => Reason }),
            []
    end.


stats_overview(Context) ->
    To = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(To, 30),
    stats_overview(From, To, Context).

stats_overview(From, Until, Context) ->
    Site = z_context:site(Context),

    Q1 = <<"
WITH
    date_series AS (
        SELECT unnest(
            generate_series(
                date_trunc('day', $from::timestamp),
                date_trunc('day', $until::timestamp),
                INTERVAL 1 day
            )) AS day
    ),
    unique_sessions AS (
        SELECT
            date_trunc('day', timestamp) AS day,
            count(*) AS requests, 
            count(DISTINCT rsc_id) AS rscs, 
            count(DISTINCT user_id) AS users, 
            count(DISTINCT session_id) AS sessions,
            (sum(resp_bytes) / 1048576)::uinteger AS resp_mbs,
            count(CASE WHEN resp_code >= 400 AND resp_code < 500 THEN 1 END) as client_errors,
            count(CASE WHEN resp_code >= 500 THEN 1 END) as server_errors 
        FROM
            access_log
        WHERE
            site = $site
            AND timestamp >= $from
            AND timestamp <= $until
        GROUP BY
            day
    )
SELECT
    ds.day,
    COALESCE(us.requests, 0) AS requests,
    COALESCE(us.rscs, 0) AS rscs,
    COALESCE(us.users, 0) AS users,
    COALESCE(us.sessions, 0) AS sessions,
    COALESCE(us.resp_mbs, 0) AS resp_mbs,
    COALESCE(us.client_errors, 0) AS client_errors,
    COALESCE(us.server_errors, 0) AS server_errors 
FROM
    date_series ds
LEFT JOIN
    unique_sessions us
ON
    ds.day == us.day
ORDER BY
    ds.day;
">>,

    case z_duckdb:q(Q1, #{ from => From,
                            until => Until,
                            site => Site} ) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get unique visitors">>, reason => Reason }),
            []
    end.

rsc_stats_overview(Rsc, Context) ->
    Id = m_rsc:rid(Rsc, Context),
    To = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(To, 30),
    rsc_stats_overview(Id, From, To, Context).

rsc_stats_overview(Id, From, Until, Context) ->
    Site = z_context:site(Context),

    Q1 = <<"
WITH
    date_series AS (
        SELECT unnest(
            generate_series(
                date_trunc('day', $from::timestamp),
                date_trunc('day', $until::timestamp),
                INTERVAL 1 day
            )) AS day
    ),
    rsc_stats AS (
        SELECT
            date_trunc('day', timestamp) AS day,
            count(*) AS requests, 
            count(DISTINCT session_id) AS sessions,
            count(DISTINCT user_id) AS users
        FROM
            access_log
        WHERE
            site = $site
            AND resp_code = 200
            AND req_method = 'GET'
            AND rsc_id = $id
            AND timestamp >= $from
            AND timestamp <= $until
            AND ", (no_bots_clause())/binary,
"        GROUP BY
            day
    )
SELECT
    ds.day,
    COALESCE(rs.requests, 0) AS requests,
    COALESCE(rs.sessions, 0) AS sessions,
    COALESCE(rs.users, 0) AS users
FROM
    date_series ds
LEFT JOIN
    rsc_stats rs
ON
    ds.day == rs.day
ORDER BY
    ds.day;
">>,

    case z_duckdb:q(Q1, #{ id => Id, 
                            from => From,
                            until => Until,
                            site => Site} ) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get rsc_stats overview">>,
                            id => Id,
                            reason => Reason }),
            []
    end.


unique_visitors(Context) ->
    To = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(To, 30),
    unique_visitors(From, To, Context).


unique_visitors(From, Until, Context) ->
    Site = z_context:site(Context),

    Q1 = <<"
WITH
    date_series AS (
        SELECT unnest(
            generate_series(
                date_trunc('day', $from::timestamp),
                date_trunc('day', $until::timestamp),
                INTERVAL 1 day
            )) AS day
    ),
    unique_sessions AS (
        SELECT
            date_trunc('day', timestamp) AS day,
            count(DISTINCT session_id) AS unique
        FROM
            access_log
        WHERE
            site = $site
            AND timestamp >= $from
            AND timestamp <= $until
        GROUP BY
            day
    )
SELECT
    ds.day,
    COALESCE(us.unique, 0) AS unique
FROM
    date_series ds
LEFT JOIN
    unique_sessions us
ON
    ds.day == us.day
ORDER BY
    ds.day;
">>,

    case z_duckdb:q(Q1, #{ from => From,
                            until => Until,
                            site => Site} ) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get unique visitors">>, reason => Reason }),
            []
    end.

erroring_pages(Context) ->
    To = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(To, 30),
    erroring_pages(From, To, Context).

erroring_pages(From, Until, Context) ->
    Site = z_context:site(Context),

    Q = <<"
SELECT
    path,
    count(*),
    count(distinct session_id),count(distinct user_id)
FROM
    access_log
WHERE
    resp_code >= 500
    AND site = $site
    AND timestamp >= $from
    AND timestamp <= $until
GROUP BY
    path
ORDER BY
    COUNT(distinct session_id) DESC
LIMIT 10">>,

    case z_duckdb:q(Q, #{ from => From, until => Until, site => Site} ) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get erroring pages">>, reason => Reason }),
            []
    end.

popular_pages(Context) ->
    To = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(To, 30),
    popular_pages(From, To, Context).

popular_pages(From, Until, Context) ->
    Site = z_context:site(Context),

    Q = <<"
SELECT
    path,
    count(*),
    count(distinct session_id),
    count(distinct user_id)
FROM
    access_log
WHERE
    path NOT in ('/zotonic-auth', '/mqtt-transport', '/manifest.json', '/cotonic-service-worker.js', '/robots.txt', '/favicon.ico' )
    AND NOT (path ^@ '/lib/' OR path ^@ '/lib-min' OR path ^@ '/image/' OR path ^@ '/fileuploader/' OR path ^@ '/admin' OR path ^@ '/ics/')
    AND resp_code = 200
    AND site = $site
    AND timestamp >= $from
    AND timestamp <= $until
GROUP BY
    path
ORDER BY
    COUNT(*) DESC,
    path
LIMIT 10">>,

    case z_duckdb:q(Q, #{ from => From, until => Until, site => Site} ) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get popular pages">>, reason => Reason }),
            []
    end.

popular_rsc_pages(Rsc, Context) ->
    To = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(To, 30),
    popular_rsc_pages(Rsc, From, To, Context).

popular_rsc_pages(Rsc, From, Until, Context) ->
    Id = m_rsc:rid(Rsc, Context),
    Site = z_context:site(Context),

    Q = <<"
SELECT
    CASE WHEN strlen(qs) > 0 THEN CONCAT(path, '?', qs) ELSE path END AS url,
    count(*),
    count(distinct session_id),
    count(distinct user_id)
FROM
    access_log
WHERE
    rsc_id = $id
    AND resp_code = 200
    AND req_method = 'GET'
    AND site = $site
    AND timestamp >= $from
    AND timestamp <= $until
    AND ", (no_bots_clause())/binary,
"GROUP BY
    url 
ORDER BY
    COUNT(*) DESC,
    url 
LIMIT 10">>,

    case z_duckdb:q(Q, #{ id => Id, from => From, until => Until, site => Site} ) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get popular rsc pages">>, reason => Reason }),
            []
    end.

popular_referrers(Rsc, Context) ->
    To = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(To, 30),
    popular_referrers(Rsc, From, To, Context).

popular_referrers(Rsc, From, Until, Context) ->
    Id = m_rsc:rid(Rsc, Context),
    Site = z_context:site(Context),

    Q = <<"
SELECT
    referer,
    count(*)
FROM
    access_log
WHERE
    rsc_id = $id
    AND referer IS NOT NULL
    AND resp_code = 200
    AND site = $site
    AND timestamp >= $from
    AND timestamp <= $until
GROUP BY
    referer 
ORDER BY
    COUNT(*) DESC,
    referer 
LIMIT 10">>,

    case z_duckdb:q(Q, #{ id => Id, from => From, until => Until, site => Site} ) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get popular referrer">>,
                            id => Id,
                            reason => Reason }),
            []
    end.

access_log(Rsc, Context) ->
    To = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(To, 30),
    access_log(Rsc, From, To, Context).

access_log(Rsc, From, Until, Context) ->
    Id = m_rsc:rid(Rsc, Context),
    Site = z_context:site(Context),

    Q = <<"
SELECT
    req_version,
    req_method,

    resp_code,
    path,
    qs,
    referer,

    duration_total,

    peer_ip,
    session_id, 
    user_id,

    language,
    timezone,
    user_agent,

    timestamp
FROM
    access_log
WHERE
    rsc_id = $id
    AND site = $site
    AND resp_code = 200
    AND req_method = 'GET'
    AND timestamp >= $from
    AND timestamp <= $until
    AND ", (no_bots_clause())/binary,
"ORDER BY
    timestamp DESC
LIMIT 100">>,

    case z_duckdb:q(Q, #{ id => Id, from => From, until => Until, site => Site} ) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get access_log">>,
                            id => Id,
                            reason => Reason }),
            []
    end.


popular_resources(Context) ->
    To = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(To, 30),
    popular_resources(From, To, Context).

popular_resources(From, Until, Context) ->
    Site = z_context:site(Context),

    Q = <<"SELECT
    rsc_id,
    count(*),
    count(distinct session_id),
    count(distinct user_id)
FROM
    access_log
WHERE
    rsc_id IS NOT NULL
    AND resp_code = 200
    AND site == $site
    AND timestamp >= $from
    AND timestamp <= $until
GROUP BY
    rsc_id
ORDER BY
    COUNT(*) DESC,
    rsc_id
LIMIT 10">>,

    case z_duckdb:q(Q, #{ site => Site, from => From, until => Until } ) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get popular resources">>, reason => Reason }),
            []
    end.


peer_ip_analytics(From, Until, Context) ->
    Site = z_context:site(Context),

    Q = <<"SELECT 
    peer_ip,
    COUNT(*) AS request_count,
    COUNT(DISTINCT session_id) AS unique_sessions,
    COUNT(DISTINCT user_id) AS unique_users,
    MIN(timestamp) AS first_access,
    MAX(timestamp) AS last_access,
    AVG(duration_total) AS avg_response_time,
    COUNT(CASE WHEN resp_code >= 400 THEN 1 END) AS error_count,
    COUNT(CASE WHEN resp_code >= 400 THEN 1 END) * 100.0 / COUNT(*) AS error_rate_percentage
FROM 
    access_log
WHERE
    site == $site
    AND timestamp > $from
    AND timestamp < $until
GROUP BY 
    peer_ip
ORDER BY 
    request_count DESC
LIMIT 100">>,

    case z_duckdb:q(Q, #{ from => From,
                           until => Until,
                           site => Site} ) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get peer_ip analytics">>, reason => Reason }),
            []
    end.

controller_health(From, Until, Context) ->
    Q = <<"
    SELECT 
    controller,
    COUNT(*) AS total_requests,
    COUNT(CASE WHEN resp_code < 400 THEN 1 END) AS successful_requests,
    COUNT(CASE WHEN resp_code >= 400 THEN 1 END) AS error_requests,
    (COUNT(CASE WHEN resp_code >= 400 THEN 1 END) * 100.0 / COUNT(*)) AS error_rate_percentage,
    AVG(duration_total) AS avg_response_time_ms,
    GEOMEAN(duration_total) AS mean_response_time_ms
FROM 
    access_log
WHERE
    site == $site
    AND timestamp > $from
    AND timestamp < $until
GROUP BY 
    controller
ORDER BY 
    total_requests DESC;">>,

    Site = z_context:site(Context),
    case z_duckdb:q(Q, #{ from => From,
                           until => Until,
                           site => Site} ) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get peer_ip analytics">>, reason => Reason }),
            []
    end.

dispatch_rule_health(Context) ->
    To = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(To, 30),
    dispatch_rule_health(From, To, Context).

dispatch_rule_health(From, Until, Context) ->
    Site = z_context:site(Context),
    Q = <<"
    SELECT 
    dispatch_rule,
    COUNT(*) AS total_requests,
    COUNT(CASE WHEN resp_code < 400 THEN 1 END) AS successful_requests,
    COUNT(CASE WHEN resp_code >= 400 THEN 1 END) AS error_requests,
    (COUNT(CASE WHEN resp_code >= 400 THEN 1 END) * 100.0 / COUNT(*)) AS error_rate_percentage,
    AVG(duration_total) AS avg_response_time_ms,
    GEOMEAN(duration_total) AS mean_response_time_ms
FROM 
    access_log
WHERE
    timestamp < $until
    AND timestamp > $from
    AND site == $site
GROUP BY 
    dispatch_rule 
ORDER BY 
    total_requests DESC;">>,

    case z_duckdb:q(Q, #{ site => Site,
                           from => From,
                           until => Until } ) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get peer_ip analytics">>, reason => Reason }),
            []
    end.

user_activity(Context) ->
    To = z_datetime:to_datetime(<<"now">>),
    From = z_datetime:prev_day(To, 30),
    user_activity(From, To, Context).

user_activity(From, Until, Context) ->
    Q = <<"
SELECT 
    user_id,
    COUNT(DISTINCT session_id) AS session_count,
    COUNT(*) AS total_requests,
    COUNT(CASE WHEN req_method = 'POST' THEN 1 END) AS post_actions,
    AVG(duration_total) AS avg_response_time_ms,
    GEOMEAN(duration_total) AS mean_response_time_ms,
    MIN(timestamp) AS first_activity,
    MAX(timestamp) AS last_activity,
    ARRAY_AGG(DISTINCT peer_ip) AS ips,
    ARRAY_AGG(DISTINCT rsc_id) FILTER (WHERE rsc_id IS NOT NULL) AS rsc,
FROM 
    access_log
WHERE 
    user_id IS NOT NULL
    AND timestamp < $until
    AND timestamp > $from
    AND site == $site
GROUP BY 
    user_id
ORDER BY 
    total_requests DESC
LIMIT 20;">>,

    Site = z_context:site(Context),
    case z_duckdb:q(Q, #{from => From,
                          until => Until,
                          site => Site
                         }) of
        {ok, _, Data} ->
            Data;
        {error, Reason} ->
            ?LOG_WARNING(#{ text => <<"Could not get user activity analytics">>, reason => Reason }),
            []
    end.

no_bots_clause() ->
    <<"((session_id IS NOT NULL)
        OR ( (session_id IS NULL)
             AND user_agent IS NOT NULL
             AND NOT regexp_matches(user_agent, '(bot|crawler|spider|Googlebot|Bingbot|Yahoo! Slurp|Baiduspider|YandexBot|AhrefsBot|MJ12bot|SemrushBot|DotBot|Sogou|Exabot|facebookexternalhit|Twitterbot|Slackbot|GuzzleHttp|HeadlessChrome|python-requests|go-http-client|curl/|wget/)', 'i')
        ))
    ">>.
