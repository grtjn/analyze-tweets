xquery version "1.0-ml";

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace http="xdmp:http";
declare namespace atom="http://www.w3.org/2005/Atom";

declare option xdmp:mapping "false";

declare variable $submit := xdmp:get-request-field("submit");
declare variable $upload := xdmp:unquote(xdmp:get-request-field("upload", ''))/*;
declare variable $query := xdmp:get-request-field("query", 'marklogic');
declare variable $user-id := xdmp:get-request-field("user-id", "grtjn");
declare variable $user-ids := tokenize($user-id, ',');
declare variable $action := xdmp:get-request-field("action");
declare variable $overwrite := boolean(xdmp:get-request-field("overwrite") = 'on');
declare variable $include-friends := boolean(xdmp:get-request-field("include-friends") = 'on');
declare variable $include-followers := boolean(xdmp:get-request-field("include-followers") = 'on');
declare variable $full := boolean(xdmp:get-request-field("full") = 'on');
declare variable $debug := boolean(xdmp:get-request-field("debug") = 'on');

declare function local:format-result($result as item()) {
	if ($result instance of element()) then
		let $uri :=
			if ($result/self::atom:entry) then
				tw:get-feed-uri($result)
			else
				tw:get-status-uri($result)
		let $co-exists :=
			if ($result/self::atom:entry) then
				tw:exists-status($uri)
			else
				tw:exists-feed($uri)
		return
			if ($result/tw:*) then (
				<a href="{$uri}">{fn:concat('@', $result/tw:from)}</a>, ': ', tw:message-to-html($result/tw:text/node()), fn:concat(' (', $result/tw:published, ') [', $co-exists, ']')
			) else if ($result/self::status) then (
				<a href="{$uri}">{fn:concat('@', $result/user/screen_name)}</a>, ': ', tw:message-to-html($result/text/node()), fn:concat(' (', $result/created_at/@iso-date, ') [', $co-exists, ']')
			) else (
				<a href="{$uri}">{fn:concat('@', substring-before($result/atom:author/atom:name, ' '))}</a>, ': ', tw:message-to-html($result/atom:title/node()), fn:concat(' (', $result/atom:published, ') [', $co-exists, ']')
			)
	else
		$result
};

xdmp:log(concat($action, ' started..')),
xdmp:log(concat('upload = ', xdmp:get-request-field-filename("upload"))),

if ($action eq 'Download Tweets') then (
	let $content-disposition :=
		fn:concat("attachment; filename=", fn:encode-for-uri($query), ".xml")
	return (
		xdmp:add-response-header("Content-Disposition",$content-disposition),
		xdmp:add-response-header("ETag",fn:string(xdmp:random())),
		xdmp:set-response-content-type("application/xml"),
		<feeds>{tw:search-feeds($query)}</feeds>
	)
) else (

xdmp:set-response-content-type("text/html"),

let $has-indexes := tw:has-indexes()
return

if ($has-indexes and not($submit = ('Recreate Indexes'))) then (
<html>
<body>
<h1>Harvest Tweets</h1>

<form action="">
<input type="hidden" name="query" value="{$query}"/>
<input type="hidden" name="user-id" value="{$user-id}"/>
<input type="hidden" name="overwrite" value="{$overwrite}"/>
<input type="hidden" name="include-friends" value="{$include-friends}"/>
<input type="hidden" name="include-followers" value="{$include-followers}"/>
<input type="hidden" name="full" value="{$full}"/>
<input type="hidden" name="debug" value="{$debug}"/>
<input type="submit" name="submit" value="Refresh"/>
</form>
<!--form action="">
<input type="hidden" name="query" value="{$query}"/>
<input type="hidden" name="user-id" value="{$user-id}"/>
<input type="hidden" name="overwrite" value="{$overwrite}"/>
<input type="hidden" name="include-friends" value="{$include-friends}"/>
<input type="hidden" name="include-followers" value="{$include-followers}"/>
<input type="hidden" name="full" value="{$full}"/>
<input type="hidden" name="debug" value="{$debug}"/>
<input type="submit" name="submit" value="Recreate Indexes"/>
</form>
<form action="ml-queue" target="_blank">
<input type="submit" name="submit" value="Background Queue"/>
</form>
<form action="browse-cache.xqy" target="_blank">
<input type="submit" name="submit" value="URL Cache"/>
</form>

<h2>Twitter</h2>
Search Twitter directly, do not store results.
<form action="?">
<input type="hidden" name="user-id" value="{$user-id}"/>
<input type="hidden" name="overwrite" value="{$overwrite}"/>
<input type="hidden" name="include-friends" value="{$include-friends}"/>
<input type="hidden" name="include-followers" value="{$include-followers}"/>
<input type="hidden" name="full" value="{$full}"/>
<input type="hidden" name="debug" value="{$debug}"/>
Query: <input type="text" name="query" value="{$query}"/>
<br/>
<input type="submit" name="action" value="Search Twitter"/> 
</form-->

<h2>Tweets</h2>
<!--
Load Twitter feeds harvested with Archivist, or stored as backup.
<form action="?" method="POST" enctype="multipart/form-data">
<input type="hidden" name="query" value="{$query}"/>
<input type="hidden" name="user-id" value="{$user-id}"/>
<input type="hidden" name="overwrite" value="{$overwrite}"/>
<input type="hidden" name="include-friends" value="{$include-friends}"/>
<input type="hidden" name="include-followers" value="{$include-followers}"/>
<input type="hidden" name="full" value="{$full}"/>
<input type="hidden" name="debug" value="{$debug}"/>
File: <input type="file" name="upload" src="{$upload}"/>
<br/>
Overwrite existing feeds: <input type="checkbox" name="overwrite">{if ($overwrite) then attribute {'checked'} {'true'} else ()}</input>
<br/>
<input type="submit" name="action" value="Upload Tweets"/>
</form>
<br/>
-->
Apply actions on Twitter feeds stored in the database.
<form action="?">
<input type="hidden" name="user-id" value="{$user-id}"/>
<input type="hidden" name="include-friends" value="{$include-friends}"/>
<input type="hidden" name="include-followers" value="{$include-followers}"/>
<input type="hidden" name="full" value="{$full}"/>
<input type="hidden" name="debug" value="{$debug}"/>
Query: <input type="text" name="query" value="{$query}"/>
<br/>
Overwrite existing feeds: <input type="checkbox" name="overwrite">{if ($overwrite) then attribute {'checked'} {'true'} else ()}</input>
<br/>
<!--input type="submit" name="action" value="Search Tweets"/-->
<input type="submit" name="action" value="Update Tweets"/>
<!--input type="submit" name="action" value="Re-enrich Tweets"/>
<!- -input type="submit" name="action" value="Unrich Tweets"/- ->
<input type="submit" name="action" value="Download Tweets"/>
<input type="submit" name="action" value="Delete Tweets"/-->
</form>

<h2>Timelines</h2>
Retrieve complete timelines from Twitter. Comma-separated list of ids allowed.
<form action="?">
<input type="hidden" name="query" value="{$query}"/>
<input type="hidden" name="full" value="{$full}"/>
<input type="hidden" name="debug" value="{$debug}"/>
User-id: <input type="text" name="user-id" value="{$user-id}"/>
<br/>
Overwrite existing feeds: <input type="checkbox" name="overwrite">{if ($overwrite) then attribute {'checked'} {'true'} else ()}</input>
<br/>
Include friends: <input type="checkbox" name="include-friends">{if ($include-friends) then attribute {'checked'} {'true'} else ()}</input>
<br/>
Include followers: <input type="checkbox" name="include-followers">{if ($include-followers) then attribute {'checked'} {'true'} else ()}</input>
<br/>
<input type="submit" name="action" value="Update Timeline"/>
<input type="submit" name="action" value="Update Favorites"/>
</form>

<!--h2>Statuses</h2>
<p>Searching statuses is likely to include a much larger history, but updating them takes quite a while due to Twitter API rate limitations (only 150 requests per hour!). The updating relies on getting the timelines of users that are mentioned in the feeds. The getting of timelines has been paced at 1 each minute at the most.</p>
<form action="?">
<input type="hidden" name="user-id" value="{$user-id}"/>
<input type="hidden" name="include-friends" value="{$include-friends}"/>
<input type="hidden" name="include-followers" value="{$include-followers}"/>
<input type="hidden" name="full" value="{$full}"/>
<input type="hidden" name="debug" value="{$debug}"/>
Query: <input type="text" name="query" value="{$query}"/>
<br/>
Overwrite existing feeds: <input type="checkbox" name="overwrite">{if ($overwrite) then attribute {'checked'} {'true'} else ()}</input>
<br/>
<input type="submit" name="action" value="Search Statuses"/>
<input type="submit" name="action" value="Update Statuses"/>
<input type="submit" name="action" value="Enrich Statuses"/>
<input type="submit" name="action" value="Unrich Statuses"/>
<input type="submit" name="action" value="Delete Statuses"/>
<br/>
Get full timelines: <input type="checkbox" name="full">{if ($full) then attribute {'checked'} {'true'} else ()}</input> (Update Statuses)
</form-->

<h2>Analyze</h2>
Jump to Twitter feeds analyzer app.
<form action="analyze-tweets.xqy" target="_blank">
<input type="hidden" name="user-id" value="{$user-id}"/>
<input type="hidden" name="overwrite" value="{$overwrite}"/>
<input type="hidden" name="include-friends" value="{$include-friends}"/>
<input type="hidden" name="include-followers" value="{$include-followers}"/>
<input type="hidden" name="full" value="{$full}"/>
<input type="hidden" name="debug" value="{$debug}"/>
Query: <input type="text" name="query" value="{$query}"/>
<br/>
<input type="submit" name="action" value="Analyze Tweets"/>
<!--input type="submit" name="action" value="Analyze Statuses"/-->
</form>

<h2>Results {$action}</h2>
<ul>{
let $results :=
	if ($action eq 'Search Twitter') then
		tw:search-twitter($query)
		
	else if ($action eq 'Upload Tweets') then
		tw:upload-feeds($upload, $overwrite)[1 to 200]
	else if ($action eq 'Search Tweets') then
		tw:search-feeds($query, 0, 200)
	else if ($action eq 'Update Tweets') then
		tw:update-feeds($query, $overwrite)[1 to 200]
	else if ($action eq 'Re-enrich Tweets') then
		tw:enrich-feeds($query)[1 to 200]
	else if ($action eq 'Unrich Tweets') then
		tw:unrich-feeds($query)[1 to 200]
	else if ($action eq 'Delete Tweets') then
		tw:delete-feeds($query)[1 to 200]
	
	else if ($action eq 'Update Timeline') then
		tw:update-timelines($user-ids, $overwrite, $include-friends, $include-followers)[1 to 200]
	else if ($action eq 'Update Favorites') then
		tw:update-favorites($user-ids, $overwrite, $include-friends, $include-followers)[1 to 200]
		
	else if ($action eq 'Search Statuses') then
		tw:search-statuses($query)[1 to 200]
	else if ($action eq 'Update Statuses') then
		tw:update-statuses($query, $full)[1 to 200]
	else if ($action eq 'Enrich Statuses') then
		tw:enrich-statuses($query)[1 to 200]
	else if ($action eq 'Unrich Statuses') then
		tw:unrich-statuses($query)[1 to 200]
	else if ($action eq 'Delete Statuses') then
		tw:delete-statuses($query)[1 to 200]
	else ()
let $count :=
	if (contains($action,' Tweets')) then
		tw:estimate-feeds($query)
	else count($results)
let $log :=
	xdmp:log(concat($action, " finished: ", $count, " (", xdmp:elapsed-time(), ")"))
return
if ($action eq 'Download Tweets') then (
	<b>Total: {$count}</b>,
	
	<pre>{fn:replace(xdmp:quote($results), '&gt;&lt;', '&gt;&#10;&lt;')}</pre>
) else (
	<b>Total: {$count}</b>,
	
	for $item in $results
	return
		<li>{local:format-result($item), if ($debug) then <div style="display: none">{$item}</div>  else ()}</li>,
		
	if ($count > 200) then
		<li>...</li>
	else ()
)
}</ul>
{tw:store-url-cache()}
<p>{xdmp:elapsed-time()}</p>
</body>
</html>

) else if ($submit = ('Create Indexes', 'Recreate Indexes')) then (

let $create := tw:create-indexes()
return

<html>
<body>
	<h2>Harvest Tweets</h2>
	<p>Indexes succesfully created!</p>
	<form action="">
	<input type="hidden" name="query" value="{$query}"/>
	<input type="hidden" name="user-id" value="{$user-id}"/>
	<input type="submit" name="submit" value="Ok"/>
	</form>
</body>
</html>

) else (

<html>
<body>
	<h2>Harvest Tweets</h2>
	<p>This feature requires some indexes to be available for optimal performance. Click below to add them in the current Docs database.</p>
	<form action="">
	<input type="hidden" name="query" value="{$query}"/>
	<input type="hidden" name="user-id" value="{$user-id}"/>
	<input type="hidden" name="action" value="{$action}"/>
	<input type="submit" name="submit" value="Create Indexes"/>
	</form>
</body>
</html>

)
)