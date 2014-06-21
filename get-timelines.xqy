xquery version '1.0-ml';

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace http="xdmp:http";
declare namespace atom="http://www.w3.org/2005/Atom";

declare option xdmp:mapping "false";

declare variable $vars as map:map external;
declare variable $query as item()+ := map:get($vars, "query");
declare variable $users as xs:string+ := map:get($vars, "users");
declare variable $full as xs:boolean := map:get($vars, "full");

let $user-id := $users[1]
let $log := xdmp:log(fn:concat("Processing ", $user-id, " of ", fn:string-join($users, ","), " against ", xdmp:database-name(xdmp:database())))
(: TODO: restore this bit, *after* implementing a begin date; when date before first user tweet, skip this, otherwise use this to speed up get-timeline.. :)
(:
let $user-tweets := /status/user[id eq $user-id]
let $is-known-user := fn:exists($user-tweets)
let $latest-user-tweet := (for $tweet in $user-tweets order by xs:dateTime($tweet/created_at/@iso-date) descending return $tweet)[1]
let $tweets := tw:get-timeline($user-id, $latest-user-tweet/id)
:)
let $tweets := try { tw:get-timeline($user-id, (), 1, fn:true()) } catch ($e) { () }

let $q := tw:parse-query($query)
let $result := (
	let $user-id := $tweets[1]/user/screen_name (: make sure to use the original screen_name case :)
	for $tweet in $tweets
	let $tweet-id := fn:data($tweet/id)
	let $tweet-uri := fn:concat('http://twitter.com/', $user-id, '/statuses/', $tweet-id)
	return
		if (tw:exists-status($tweet-uri)) then
			fn:concat('Skipped existing status ', $tweet-uri)
		else if ($full or $tweet[cts:contains(., cts:and-query($q))]) then
			let $tweet :=
				tw:enrich-status($tweet)
			return
				($tweet, tw:store-status($tweet-uri, $tweet))
		else
			fn:concat('Skipped non-relevant status ', $tweet-uri)
)
let $log := xdmp:log(fn:concat("Processed ", fn:count($tweets), " tweets for ", $user-id, " in ", xdmp:elapsed-time(), ": ", xdmp:quote($result)))
let $sleep := xdmp:sleep(120000) (: 2 minutes :)
let $users := $users[position() > 1]
let $map := map:delete($vars, "users")
let $map := map:put($vars, "users", $users)
let $spawn :=
	if (fn:exists($users)) then
		try {
			xdmp:spawn("get-timelines.xqy", (xs:QName("vars"), $vars)),
			"Spawned remainder succesfully"
		} catch ($e) {
			$e
		}
	else "Nothing to spawn"
return
	xdmp:log($spawn)