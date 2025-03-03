{% with m.ducklog.popular_pages[id] as pages %}
<table class="table table-condensed">
    <thead>
        <tr>
            <td>{_ Path _}</td>
            <td>{_ Views _}</td>
            <td>{_ Sessions _}</td>
            <td>{_ Users _}</td>
        </tr>
    </thead>
    {% for page, views, sessions, users in pages %}
        <tr>
            <td>{{ page | escape }}</td>
            <td>{{ views }}</td>
            <td>{{ sessions }}</td>
            <td>{{ users }}</td>
        </tr>
    {% endfor %}
</table>
{% endwith %}

{% with m.ducklog.popular_referrers[id] as referrer %}
<table class="table table-condensed">
    <thead>
        <tr>
            <td>{_ Referrer _}</td>
            <td>{_ Visits _}</td>
        </tr>
    </thead>
    {% for referrer, visits in referrer %}
        <tr>
            <td>{{ referrer | escape }}</td>
            <td>{{ visits }}</td>
        </tr>
    {% endfor %}
</table>
{% endwith %}

{% with m.ducklog.access_log[id] as log %}
<div class="table-responsive" style="max-height: 300px; overflow: scroll;">
<table class="table table-condensed" style="white-space:nowrap;">
    <thead>
        <tr>
            <td>{_ Timestamp _}</td>

            <td>{_ Method _}</td>
            <td>{_ Code _}</td>
            <td>{_ Path _}</td>
            <td>{_ QS _}</td>

            <td>{_ Peer _}</td>
            <td>{_ Session Id _}</td>
            <td>{_ User _}</td>

            <td>{_ UA _}</td>
        </tr>
    </thead>
    {% for req_version, req_method,
           resp_code, path, qs, referer,
           duration_total,
           peer_ip, session_id, user_id,
           language, timezone, user_agent,
           timestamp in log %}
        <tr>
            <td>{{ timestamp | date:"c" }}</td>

            <td>{{ req_method }}</td>
            <td>{{ resp_code }}</td>
            <td>{{ path | escape }}</td>
            <td>{{ qs | escape }}</td>

            <td>{{ peer_ip | escape }}</td>
            <td>{{ session_id | escape }}</td>
            <td>{{ user_id | escape }}</td>

            <td>{{ user_agent | escape }}</td>
        </tr>
    {% endfor %}
</table>
</div>
{% endwith %}
