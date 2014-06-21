xquery version "1.0-ml";

module namespace tw="http://grtjn.nl/twitter/utils";

import module namespace admin = "http://marklogic.com/xdmp/admin" at "/MarkLogic/admin.xqy";
import module namespace search="http://marklogic.com/appservices/search" at "/MarkLogic/appservices/search/search.xqy";
import module namespace q = "http://grtjn.nl/marklogic/queue" at "ml-queue/queue-lib.xqy";

import module namespace oa="http://marklogic.com/ns/oauth" at "oauth.xqy";
import module namespace json="http://marklogic.com/xdmp/json" at "/MarkLogic/json/json.xqy";
import module namespace functx="http://www.functx.com" at "/MarkLogic/functx/functx-1.0-nodoc-2007-01.xqy";

declare namespace db="http://marklogic.com/xdmp/database";
declare namespace http="xdmp:http";
declare namespace atom="http://www.w3.org/2005/Atom";
declare namespace twitter="http://api.twitter.com/";
declare namespace a="clr-namespace:archivist;assembly=archivist";
declare namespace json-basic="http://marklogic.com/xdmp/json/basic";

declare option xdmp:mapping "false";

declare variable $enable-text-enrichment := fn:true();
declare variable $enable-uri-resolving := fn:false(); (: CAN BE VERY SLOW!! :)
declare variable $enable-online := fn:true();
declare variable $connection-fails := 0;
declare variable $max-resolve-follows := 5;
declare variable $debug := fn:false();

declare variable $feeds-collection := "feeds";
declare variable $statuses-collection := "statuses";

declare variable $search-recursion-limit := 25;
declare variable $search-size := 100; (: 100 is max :)
declare variable $timeline-recursion-limit := 50;
declare variable $timeline-size := 200; (: 200 is max :)
declare variable $favorites-recursion-limit := 50;
declare variable $favorites-size := 200; (: 200 is max :)

(: Twitter API :)

declare variable $config :=
     <oa:service-provider realm="">
       <oa:request-token>
         <oa:uri>https://api.twitter.com/oauth/request_token</oa:uri>
         <oa:method>GET</oa:method>
       </oa:request-token>
       <oa:user-authorization>
         <oa:uri>https://api.twitter.com/oauth/authorize</oa:uri>
       </oa:user-authorization>
       <oa:user-authentication>
         <oa:uri>https://api.twitter.com/oauth/authenticate</oa:uri>
         <oa:additional-params>force_login=true</oa:additional-params>
       </oa:user-authentication>
       <oa:access-token>
         <oa:uri>https://api.twitter.com/oauth/access_token</oa:uri>
         <oa:method>POST</oa:method>
       </oa:access-token>
       <oa:signature-methods>
         <oa:method>HMAC-SHA1</oa:method>
       </oa:signature-methods>
       <oa:oauth-version>1.0</oa:oauth-version>
	   <!--
	   - go to apps.twitter.com
	   - login with your normal Twitter account
	   - click the Create New App button
	   - name: Analyze My Tweets (or something alike)
	   - description: Search and analyze your tweets with this tool
	   - website: https://github.com/grtjn/analyze-tweets
	   - check the Yes, I agree
	   - click the Create Your Twitter Application button
	   - go to API Keys
	   - copy API Key into 'oa:consumer-key'
	   - copy API Secret into 'oa:consumer-key-secret'
	   - click Create my access token
	   - wait a few seconds, and click Refresh
	   - copy your Access token into 'oa:token'
	   - copy your Access token secret into 'oa:secret'
	   -->
       <oa:authentication>
         <oa:consumer-key><!-- Your Twitter Application API Key --></oa:consumer-key>
         <oa:consumer-key-secret><!-- Your Twitter Application API Secret --></oa:consumer-key-secret>
       </oa:authentication>
	   <oa:token><!-- Your Access token for this app --></oa:token>
	   <oa:secret><!-- Your Access token secret for this app --></oa:secret>
     </oa:service-provider>
;

declare function tw:signed-get($base-url as xs:string, $params as element(oa:options)?) {
	tw:signed-get($base-url, $params, 1, 0)
};

declare function tw:signed-get($base-url as xs:string, $params as element(oa:options)?, $recurse as xs:integer, $retry as xs:integer) {
	let $request := fn:concat($base-url, "?", fn:string-join(for $key in $params/* return fn:concat(fn:local-name($key), '=', fn:string($key)), "&amp;"))
	
	let $log := xdmp:log($request)

    let $response :=
		try{
			(:
			xdmp:http-get($request, <options xmlns="xdmp:http"><timeout>5</timeout></options>)
			:)
			let $_ :=
				oa:signed-request(
					$config,
					"GET",
					$base-url,
					$params,
					$config/oa:token,
					$config/oa:secret)
			return
				if ($_/oa:error) then
					$_
				else
					json:transform-from-json(xdmp:from-json($_))
		} catch ($e) { if ($debug) then xdmp:log($e) else (), $e }
	(:
	let $log := xdmp:log(xdmp:describe($response))
	:)
	return
		if ($response/self::*:error/*:code = ("SVC-SOCCONN", "SVC-SOCHN")) then
			let $log := xdmp:log("Internet connection seems faulty, slow or down, giving up..")
			let $set := xdmp:set($connection-fails, $connection-fails + 1)
			return
				if ($connection-fails gt 3) then
					let $set := xdmp:set($enable-online, fn:false())
					return xdmp:log("Too many connection fails, disabling online..")
				else ()
		else if ($response/http:code ge 500 or fn:exists($response/self::*:error)) then (
			xdmp:log(xdmp:quote($response)),
			if ($retry lt 3) then (
				xdmp:log(fn:concat("Error response. Sleeping 60 sec before retry #", $retry+1, "..")),
				
				let $sleep := xdmp:sleep(60000) (: 1 min :)
				return
					tw:signed-get($base-url, $params, $recurse, $retry + 1)
			) else
				xdmp:log("Retry #3 failed, giving up..")
		) else if (fn:contains(fn:string-join($response, ''), 'Rate limit exceeded')) then
			if ($retry lt 3) then (
				(:
				xdmp:log(fn:concat("Rate limit exceeded. Sleeping 5 min before retry #", $retry+1, "..")),

				let $sleep := xdmp:sleep(300000) (: 5 min :)
				return
					tw:signed-get($base-url, $params, $recurse, $retry + 1)
				:)
				fn:error((), 'RATE-LIMIT-EXCEEDED', ($base-url, xdmp:quote($params), $recurse, $retry))
			) else
				xdmp:log("Retry #3 failed, giving up..")
		else
			$response
};

declare function tw:search-twitter($query as xs:string)
    as element(atom:entry)*
{
    let $tweets := tw:search-twitter($query, (), fn:true(), 1)
	let $map := map:map()
    for $tweet in $tweets
    let $uri := tw:get-feed-uri($tweet)
	where fn:not(fn:exists(map:get($map, $uri)))
    return (
		map:put($map, $uri, $tweet),
        $tweet
	)
};

declare function tw:search-twitter($query as xs:string, $next as xs:string?, $overwrite as xs:boolean, $recurse as xs:integer)
    as element(atom:entry)*
{
	tw:search-twitter($query, $next, $overwrite, $recurse, 0)
};

declare function tw:search-twitter($query as xs:string, $next as xs:string?, $overwrite as xs:boolean, $recurse as xs:integer, $retry as xs:integer)
    as element(atom:entry)*
{
	let $base-url := "https://api.twitter.com/1.1/search/tweets.json"
	let $params := <oa:options><q>{$query}</q><count>{$search-size}</count><include_entities>true</include_entities>{
		if ($next) then
			<max_id>{$next}</max_id>
		else ()
	}</oa:options>

	let $response :=
		tw:signed-get($base-url, $params)
		
	let $response_body := $response/*[1]/*
	let $response_feeds :=
		<atom:feed>{
			for $obj in $response_body
			return
				tw:status2feed(tw:json2status($obj))
		}</atom:feed>
	(:
	let $log := xdmp:log(xdmp:describe($response_feeds))
	:)
	let $tweets := $response_feeds/atom:entry
	let $log := xdmp:log(fn:count($tweets))
	return (
		$tweets,
		if ($recurse gt 0 and $recurse lt $search-recursion-limit and fn:count($tweets) eq $search-size) then
			let $last-tweet := $tweets[fn:last()]
			let $feed-uri := tw:get-feed-uri($last-tweet)
			let $next := if ($response/*[2]/*:next__results) then fn:substring-after(fn:substring-before($response/*[2]/*:next__results, "&amp;"), "?max_id=") else ()
			return
				if ($next and ($overwrite or fn:not(tw:exists-feed($feed-uri)))) then
					let $log := xdmp:log(fn:concat("Recursion #", $recurse, ".."))
					return
						tw:search-twitter($query, $next, $overwrite, $recurse + 1)
				else
					xdmp:log(fn:concat("Recursion stopped at #", $recurse, ".."))
		else
			xdmp:log(fn:concat("Recursion stopped at #", $recurse, ".."))
	)
};

declare function tw:get-tweet($status-id as xs:string)
    as element(status)?
{
	let $base-url := "https://api.twitter.com/1.1/statuses/show.json"
	let $params := <oa:options><id>{$status-id}</id><include_entities>true</include_entities></oa:options>
	
	let $response :=
		tw:signed-get($base-url, $params)
	
	let $tweet := $response
	where fn:exists($tweet)
	return
		tw:json2status($tweet)
};

declare function tw:get-followers($user-id as xs:string)
    as xs:string*
{
	let $base-url := "https://api.twitter.com/1.1/followers/ids.json"
	let $params := <oa:options><cursor>-1</cursor><count>5000</count>{
		if (fn:matches($user-id, '^[0-9]+$')) then
			<user_id>{$user-id}</user_id>
	    else
			<screen_name>{$user-id}</screen_name>
	}</oa:options>
	
	let $response :=
		tw:signed-get($base-url, $params)

	return
		($response//id/fn:string(.), $response//json-basic:ids/*/fn:string(.))
};

declare function tw:get-friends($user-id as xs:string)
    as xs:string*
{
	let $base-url := "https://api.twitter.com/1.1/friends/ids.json"
	let $params := <oa:options><cursor>-1</cursor><count>5000</count>{
		if (fn:matches($user-id, '^[0-9]+$')) then
			<user_id>{$user-id}</user_id>
	    else
			<screen_name>{$user-id}</screen_name>
	}</oa:options>
	
	let $response :=
		tw:signed-get($base-url, $params)

	return
		($response//id/fn:string(.), $response//json-basic:ids/*/fn:string(.))
};

declare function tw:get-timeline($user-id as xs:string, $latest-id as xs:string?, $overwrite as xs:boolean)
    as element(status)*
{
    tw:get-timeline($user-id, $latest-id, $overwrite, 1)
};

declare function tw:get-timeline($user-id as xs:string, $latest-id as xs:string?, $overwrite as xs:boolean, $recurse as xs:integer)
    as element(status)*
{
    let $tweets := tw:get-timeline($user-id, $latest-id, (), $overwrite, $recurse)
	let $map := map:map()
    for $tweet in $tweets
    let $uri := get-status-uri($tweet)
    (:
	let $log := xdmp:log($uri)
	:)
	where fn:not(fn:exists(map:get($map, $uri)))
    return (
		map:put($map, $uri, $tweet),
        $tweet
	)
};

declare function tw:get-timeline($user-id as xs:string, $latest-id as xs:string?, $next as xs:string?, $overwrite as xs:boolean, $recurse as xs:integer)
    as element(status)*
{
	tw:get-timeline($user-id, $latest-id, $next, $overwrite, $recurse, 0)
};

declare function tw:get-timeline($user-id as xs:string, $latest-id as xs:string?, $next as xs:string?, $overwrite as xs:boolean, $recurse as xs:integer, $retry as xs:integer)
    as element(status)*
{
	let $base-url := "https://api.twitter.com/1.1/statuses/user_timeline.json"
	let $params := <oa:options><include_rts>true</include_rts><count>{$timeline-size}</count><trim_user>false</trim_user><exclude_replies>false</exclude_replies><contributor_details>true</contributor_details>{
		if (fn:matches($user-id, '^[0-9]+$')) then
			<user_id>{$user-id}</user_id>
	    else
			<screen_name>{$user-id}</screen_name>,
			
	    if (fn:exists($latest-id)) then
			<since_id>{$latest-id}</since_id>
	    else (),
		
		if ($next) then
			<max_id>{$next}</max_id>
		else ()
	}</oa:options>
	
	let $response :=
		tw:signed-get($base-url, $params)

	let $response_body := $response/*
	let $response_feeds :=
		<statuses>{
			for $obj in $response_body
			return
				tw:json2status($obj)
		}</statuses>
	(:
	let $log := xdmp:log(xdmp:describe($response_feeds))
	:)
	return
		if ($response/http:code eq 404) then
			(: unknown/non-existing user, return dummy status! :)
			<status>
			  <created_at>Sun Jun 12 20:23:33 +0000 2011</created_at>
			  <user>
				<id>{$user-id}</id>
				<screen_name>{$user-id}</screen_name>
			  </user>
			</status>
		else
			let $tweets := $response_feeds/*
			let $log := xdmp:log(fn:count($tweets))
			where fn:exists($tweets)
			return (
				$tweets,
				(: response count isnt always exactly equal to count. Not sure why, take a small window just in case :)
				if ($recurse gt 0 and $recurse lt $timeline-recursion-limit and fn:count($tweets) ge ($timeline-size - 10)) then
					let $last-status := $tweets[fn:last()]
					let $status-uri := tw:get-status-uri($last-status)
					let $last-feed := tw:status2feed($last-status)
					let $feed-uri := tw:get-feed-uri($last-feed)
					let $next := $last-status/id
					return
						if ($next and ($overwrite or fn:not(tw:exists-status($status-uri) or tw:exists-feed($feed-uri)))) then
							let $log := xdmp:log(fn:concat("Recursion #", $recurse, ".."))
							return
								tw:get-timeline($user-id, $latest-id, $next, $overwrite, $recurse + 1)
						else
							xdmp:log(fn:concat("Recursion stopped at #", $recurse, ".."))
				else
					xdmp:log(fn:concat("Recursion stopped at #", $recurse, ".."))
			)
};

declare function tw:get-favorites($user-id as xs:string, $latest-id as xs:string?, $overwrite as xs:boolean)
    as element(status)*
{
    tw:get-favorites($user-id, $latest-id, $overwrite, 1)
};

declare function tw:get-favorites($user-id as xs:string, $latest-id as xs:string?, $overwrite as xs:boolean, $recurse as xs:integer)
    as element(status)*
{
    let $tweets := tw:get-favorites($user-id, $latest-id, (), $overwrite, $recurse)
	let $map := map:map()
    for $tweet in $tweets
    let $uri := get-status-uri($tweet)
    (:
	let $log := xdmp:log($uri)
	:)
	where fn:not(fn:exists(map:get($map, $uri)))
    return (
		map:put($map, $uri, $tweet),
        $tweet
	)
};

declare function tw:get-favorites($user-id as xs:string, $latest-id as xs:string?, $next as xs:string?, $overwrite as xs:boolean, $recurse as xs:integer)
    as element(status)*
{
	tw:get-favorites($user-id, $latest-id, $next, $overwrite, $recurse, 0)
};

declare function tw:get-favorites($user-id as xs:string, $latest-id as xs:string?, $next as xs:string?, $overwrite as xs:boolean, $recurse as xs:integer, $retry as xs:integer)
    as element(status)*
{
	let $base-url := "https://api.twitter.com/1.1/favorites/list.json"
	let $params := <oa:options><include_entities>true</include_entities><count>{$favorites-size}</count>{
		if (fn:matches($user-id, '^[0-9]+$')) then
			<user_id>{$user-id}</user_id>
	    else
			<screen_name>{$user-id}</screen_name>,
			
	    if (fn:exists($latest-id)) then
			<since_id>{$latest-id}</since_id>
	    else (),
		
		if ($next) then
			<max_id>{$next}</max_id>
		else ()
	}</oa:options>
	
	let $response :=
		tw:signed-get($base-url, $params)

	let $response_body := $response/*
	let $response_feeds :=
		<statuses>{
			for $obj in $response_body
			return
				tw:json2status($obj)
		}</statuses>
	(:
	let $log := xdmp:log(xdmp:describe($response_feeds))
	:)
	return
		if ($response/http:code eq 404) then
			(: unknown/non-existing user, return dummy status! :)
			<status>
			  <created_at>Sun Jun 12 20:23:33 +0000 2011</created_at>
			  <user>
				<id>{$user-id}</id>
				<screen_name>{$user-id}</screen_name>
			  </user>
			</status>
		else
			let $tweets := $response_feeds/*
			let $log := xdmp:log(fn:count($tweets))
			where fn:exists($tweets)
			return (
				$tweets,
				
				(: response count isnt always exactly equal to count. Not sure why, take a small window just in case :)
				if ($recurse gt 0 and $recurse lt $favorites-recursion-limit and fn:count($tweets) ge ($favorites-size - 10)) then
					let $last-status := $tweets[fn:last()]
					let $status-uri := tw:get-status-uri($last-status)
					let $last-feed := tw:status2feed($last-status)
					let $feed-uri := tw:get-feed-uri($last-feed)
					let $next := $last-status/id
					return
						if ($next and ($overwrite or fn:not(tw:exists-status($status-uri) or tw:exists-feed($feed-uri)))) then
							let $log := xdmp:log(fn:concat("Recursion #", $recurse, ".."))
							return
								tw:get-favorites($user-id, $latest-id, $next, $overwrite, $recurse + 1)
						else
							xdmp:log(fn:concat("Recursion stopped at #", $recurse, ".."))
				else
					xdmp:log(fn:concat("Recursion stopped at #", $recurse, ".."))
			)
};

(: Feeds :)

declare function tw:upload-feeds($upload as element()?, $overwrite as xs:boolean)
	as item()*
{
	let $feeds := (
        if ($upload/self::a:TwitterDataModel) then 
		
            (: xdmp:xslt-invoke('archivist2feed.xsl',$upload)/* :)
			for $t in $upload//a:Tweet
			let $date := fn:replace($t/@TweetDate, '(T\d\d:\d\d)\+', '$1:00+')
			return
			<entry xmlns="http://www.w3.org/2005/Atom">
			  <id>tag:search.twitter.com,2005:{fn:data($t/@TweetID)}</id>

			  <published>{$date}</published>
			  <link type="text/html" href="http://twitter.com/{fn:lower-case($t/@Username)}/statuses/{fn:data($t/@TweetID)}" rel="alternate"/>
			  <title>{fn:data($t/@Status)}</title>
			  <content type="html">{fn:data($t/@Status)}</content>

			  <updated>{$date}</updated>
			  <link type="image/png" href="{$t/@Image}" rel="image"/>

			  <author>
				<name>{fn:lower-case($t/@Username)} ({fn:data($t/@Username)})</name>
				<uri>http://twitter.com/{fn:lower-case($t/@Username)}</uri>
			  </author>
			</entry>
			
        else if ($upload/self::tweets) then
			(:
				<tweet url="http://twitter.com/grtjn/statuses/99373359246221312">
					<from>grtjn (Geert)</from>
					<subject>RT @smyles: jxsl http://code.google.com/p/jxsl/ a means to integrate xspec with java continuous integration tools via junit #balisage</subject>
					<stamp>5-8-2011 8:57:09</stamp>
				</tweet>
			:)

			for $tweet in $upload/tweet
			
			let $subject := fn:string($tweet/subject)
			let $url := fn:normalize-space($tweet/@url)
			let $id := fn:substring-after($url, '/statuses/')
			let $user-url := fn:substring-before($url, '/statuses/')
			let $from := fn:string($tweet/from)
			let $iso-date := tw:get-iso-date2($tweet/stamp)
			
			return
				<entry xmlns:google="http://base.google.com/ns/1.0" xmlns:openSearch="http://a9.com/-/spec/opensearch/1.1/" xmlns="http://www.w3.org/2005/Atom" xmlns:twitter="http://api.twitter.com/" xmlns:georss="http://www.georss.org/georss">
					<title>{$subject}</title>
					<id>tag:search.twitter.com,2005:{$id}</id>
					<published>{$iso-date}</published>

					<link type="text/html" href="{$url}" rel="alternate"/>
					<content type="html">{$subject}</content>
					<updated>{$iso-date}</updated>

					<author>
						<name>{$from}</name>
						<uri>{$user-url}</uri>
					</author>
				</entry>
		else ()
	)
	for $batch in (0 to fn:floor(fn:count($feeds) div 1000))
	let $feeds := $feeds[($batch * 1000) to (($batch + 1) * 1000 - 1)]
	let $params := map:map()
	let $put := map:put($params, "feeds", $feeds)
	(:
	let $spawn := xdmp:spawn("insert-feeds.xqy", (xs:QName("feeds"), $params, xs:QName("overwrite"), $overwrite), ())
	:)
	let $put := map:put($params, "overwrite", $overwrite)
	let $queue := q:create-task("insert-feeds.xqy", 0, $params)
	let $log := xdmp:log(fn:concat("Queued task for batch #", $batch, " containing ", fn:count($feeds), " feeds, with overwrite is ", $overwrite))
	return
		$feeds
};

declare function tw:parse-query($query as item()*)
	as cts:query*
{
	for $q in $query
	let $dates := fn:analyze-string($q, 'date:[^ ]+')/*:match/text()
	let $times := fn:analyze-string($q, 'time:[^ ]+')/*:match/text()
	let $q :=
		search:parse($q,
			<options xmlns="http://marklogic.com/appservices/search">
				<constraint name="stype">
					<value>
						<element ns="" name="status"/>
						<attribute ns="http://grtjn.nl/twitter/utils" name="class"/>
						<term-option>exact</term-option>
					</value>
				</constraint>
				<constraint name="type">
					<value>
						<element ns="http://www.w3.org/2005/Atom" name="entry"/>
						<attribute ns="http://grtjn.nl/twitter/utils" name="class"/>
						<term-option>exact</term-option>
					</value>
				</constraint>
				<constraint name="from">
					<value>
						<element ns="http://grtjn.nl/twitter/utils" name="from"/>
						<attribute ns="" name="id"/>
						<term-option>case-insensitive</term-option>
						<term-option>diacritic-insensitive</term-option>
						<term-option>punctuation-sensitive</term-option>
						<term-option>whitespace-insensitive</term-option>
						<term-option>unstemmed</term-option>
						</value>
				</constraint>
				<constraint name="text">
					<word>
						<element ns="http://grtjn.nl/twitter/utils" name="text"/>
						<attribute ns="" name="org"/>
					</word>
				</constraint>
				<constraint name="token">
					<word>
						<element ns="http://grtjn.nl/twitter/utils" name="n-gram"/>
						<term-option>exact</term-option>
					</word>
				</constraint>
				<constraint name="token1">
					<word>
						<element ns="http://grtjn.nl/twitter/utils" name="n-gram1"/>
						<term-option>exact</term-option>
					</word>
				</constraint>
				<constraint name="token2">
					<word>
						<element ns="http://grtjn.nl/twitter/utils" name="n-gram2"/>
						<term-option>exact</term-option>
					</word>
				</constraint>
				<constraint name="token3">
					<word>
						<element ns="http://grtjn.nl/twitter/utils" name="n-gram3"/>
						<term-option>exact</term-option>
					</word>
				</constraint>
				<constraint name="url">
					<word>
						<element ns="http://grtjn.nl/twitter/utils" name="url"/>
						<attribute ns="" name="full"/>
					</word>
				</constraint>
				<constraint name="mention">
					<value>
						<element ns="http://grtjn.nl/twitter/utils" name="user"/>
						<attribute ns="" name="id"/>
						<term-option>exact</term-option>
					</value>
				</constraint>
				<constraint name="tag">
					<value>
						<element ns="http://grtjn.nl/twitter/utils" name="tag"/>
						<attribute ns="" name="id"/>
						<term-option>exact</term-option>
					</value>
				</constraint>
				<constraint name="date">
					<range type="xs:date">
						<element ns="http://grtjn.nl/twitter/utils" name="published"/>
						<attribute ns="" name="date"/>
						{
							for $date in $dates
							let $date := fn:substring-after($date, 'date:')
							return
								if (fn:matches($date, '^\d\d\d\d$')) then
									<bucket name="{$date}" ge="{$date}-01-01" lt="{fn:number($date) + 1}-01-01">{$date}</bucket>
								else if (fn:matches($date, '^\d\d\d\d-\d\d\d\d$')) then
									let $start-year := fn:substring-before($date, '-')
									let $end-year := fn:substring-after($date, '-')
									return
										<bucket name="{$date}" ge="{$start-year}-01-01" lt="{fn:number($end-year) + 1}-01-01">{$date}</bucket>
								else if (fn:matches($date, '^\d\d\d\d\d\d$')) then
									let $year := fn:substring($date, 1, 4)
									let $month := fn:substring($date, 5, 2)
									let $end-date := xs:date(fn:concat($year, "-", $month, "-01")) + xs:yearMonthDuration ("P1M")
									return
										<bucket name="{$date}" ge="{$year}-{$month}-01" lt="{$end-date}">{$date}</bucket>
								else if (fn:matches($date, '^\d\d\d\d\d\d-\d\d\d\d\d\d$')) then
									let $start-date := fn:substring-before($date, '-')
									let $start-year := fn:substring($start-date, 1, 4)
									let $start-month := fn:substring($start-date, 5, 2)
									
									let $end-date := fn:substring-after($date, '-')
									let $end-year := fn:substring($end-date, 1, 4)
									let $end-month := fn:substring($end-date, 5, 2)
									let $end-date := xs:date(fn:concat($end-year, "-", $end-month, "-01")) + xs:yearMonthDuration ("P1M")
									return
										<bucket name="{$date}" ge="{$start-year}-{$start-month}-01" lt="{$end-date}">{$date}</bucket>
								else if (fn:matches($date, '^\d\d\d\d\d\d\d\d$')) then
									let $year := fn:substring($date, 1, 4)
									let $month := fn:substring($date, 5, 2)
									let $day := fn:substring($date, 7, 2)
									let $end-date := xs:date(fn:concat($year, "-", $month, "-", $day)) + xs:dayTimeDuration ("P1D")
									return
										<bucket name="{$date}" ge="{$year}-{$month}-{$day}" lt="{$end-date}">{$date}</bucket>
								else if (fn:matches($date, '^\d\d\d\d\d\d\d\d-\d\d\d\d\d\d\d\d$')) then
									let $start-date := fn:substring-before($date, '-')
									let $start-year := fn:substring($start-date, 1, 4)
									let $start-month := fn:substring($start-date, 5, 2)
									let $start-day := fn:substring($start-date, 7, 2)
									
									let $end-date := fn:substring-after($date, '-')
									let $end-year := fn:substring($end-date, 1, 4)
									let $end-month := fn:substring($end-date, 5, 2)
									let $end-day := fn:substring($end-date, 7, 2)
									let $end-date := xs:date(fn:concat($end-year, "-", $end-month, "-", $end-day)) + xs:dayTimeDuration ("P1D")
									return
										<bucket name="{$date}" ge="{$start-year}-{$start-month}-{$start-day}" lt="{$end-date}">{$date}</bucket>
								else
									fn:error(xs:QName("UNKNOWNFACET"), "Invalid date pattern, only patterns yyyy(-yyyy), yyyymm(-yyyymm), and yyyymmdd(-yyyymmdd) are allowed.")
						}
						
						<computed-bucket lt="-P1Y" anchor="start-of-year" name="older">Older</computed-bucket>
						<computed-bucket lt="P1Y" ge="P0Y" anchor="start-of-year" name="year">This Year</computed-bucket>
						<computed-bucket lt="P1M" ge="P0M" anchor="start-of-month" name="month">This Month</computed-bucket>
						<computed-bucket lt="P1D" ge="-P6D" anchor="start-of-day" name="week">This week</computed-bucket>
						<computed-bucket lt="P1D" ge="P0D" anchor="start-of-day" name="today">Today</computed-bucket>
						<computed-bucket ge="P0D" anchor="now" name="future">Future</computed-bucket>

						<facet-option>descending</facet-option>
					</range>
				</constraint>
				<constraint name="time">
					<range type="xs:time">
						<element ns="http://grtjn.nl/twitter/utils" name="published"/>
						<attribute ns="" name="time"/>
						{
							for $time in $times
							let $time := fn:substring-after($time, 'time:')
							return
								if (fn:matches($time, '^\d\d\d\d-\d\d\d\d$')) then
									let $start-hour := fn:substring($time, 1, 2)
									let $start-minutes := fn:substring($time, 3, 2)
									let $end-hour := fn:substring($time, 6, 2)
									let $end-minutes := fn:substring($time, 8, 2)
									return
										<bucket name="{$time}" ge="{$start-hour}:{$start-minutes}:00" lt="{$end-hour}:{$end-minutes}:59">{$time}</bucket>
								else if (fn:matches($time, '^\d\d\d\d\d\d-\d\d\d\d\d\d$')) then
									let $start-hour := fn:substring($time, 1, 2)
									let $start-minutes := fn:substring($time, 3, 2)
									let $start-seconds := fn:substring($time, 5, 2)
									let $end-hour := fn:substring($time, 8, 2)
									let $end-minutes := fn:substring($time, 10, 2)
									let $end-seconds := fn:substring($time, 12, 2)
									return
										<bucket name="{$time}" ge="{$start-hour}:{$start-minutes}:{$start-seconds}" lt="{$end-hour}:{$end-minutes}:{$end-seconds}">{$time}</bucket>
								else
									fn:error(xs:QName("UNKNOWNFACET"), "Invalid time pattern, only pattern hhmm-hhmm or hhmmss-hhmmss is allowed.")
						}
						<facet-option>descending</facet-option>
					</range>
				</constraint>
			</options>
		)
	return
		cts:query($q)
};

declare function tw:search-feeds($query as item()*)
	as element(atom:entry)*
{
	let $query := tw:parse-query($query)
	for $i in cts:search(fn:collection($feeds-collection), cts:and-query($query))/*
	order by xs:dateTime($i/tw:published/@iso-date) descending
	return $i
};

declare function tw:search-feeds($query as item()*, $page as xs:integer, $size as xs:integer)
	as element(atom:entry)*
{
	let $query := tw:parse-query($query)
	let $start := ($page - 1) * $size + 1
	let $end := $page * $size
	return
	(
		for $i in cts:search(fn:collection($feeds-collection), cts:and-query($query))
		order by xs:dateTime($i/tw:published/@iso-date) descending
		return $i
	)[$start to $end]/*
};

declare function tw:get-feed-uris($query as item()*, $page as xs:integer, $size as xs:integer)
	as xs:string*
{
	let $query := tw:parse-query($query)
	let $start := ($page - 1) * $size + 1
	let $end := $page * $size
	for $uri in
		cts:uris((), "document", cts:and-query((cts:collection-query($feeds-collection),$query)))[$start to $end][fn:not(fn:ends-with(., '/'))]
	return fn:substring-after($uri, "/feeds/")
};

declare function tw:estimate-feeds($query as item()*)
	as xs:integer
{
	let $query := tw:parse-query($query)
	return
		xdmp:estimate(cts:search(fn:collection($feeds-collection), cts:and-query($query)))
};

declare function tw:update-feeds($queries as xs:string*, $overwrite as xs:boolean)
	as item()*
{
	let $map := map:map()
	
	for $query in $queries
	let $log := xdmp:log(fn:concat("Updating ", $query, " feeds.."))
	
		let $feeds := tw:search-twitter($query, (), $overwrite, 1)
		let $log := xdmp:log(fn:count($feeds))
		for $feed in $feeds
		let $feed-uri := tw:get-feed-uri($feed)
		where fn:not(fn:exists(map:get($map, $feed-uri))) (: prevent conflicting updates :)
		return (
			map:put($map, $feed-uri, $feed),
			
			if (fn:not($overwrite) and tw:exists-feed($feed-uri)) then
				fn:concat('Skipped existing feed ', $feed-uri)
			else
				let $log :=
					xdmp:log($feed-uri)
				let $feed :=
					tw:enrich-feed($feed)
				return
					($feed-uri, tw:store-feed($feed-uri, $feed))
		)
};

declare function tw:json2status($status as element(json-basic:json))
	as element(status)
{
	let $urls :=
		for $url in $status//*:urls/*
		let $short := $url/*:url/fn:string(.)
		let $long := $url/*:expanded__url/fn:string(.)
		where fn:exists($short) and fn:exists($long)
		return
			tw:add-url-to-cache($short, $long)
	return
		<status xmlns="">{
			functx:change-element-ns-deep($status/*, "", "")
		}</status>
};

declare function tw:status2favorite($status as element(status), $screen_name as xs:string)
	as element(status)+
{
	$status,
	if (fn:not($screen_name = ($status/user/screen_name, $status/user/screen__name))) then
		<status xmlns="">{
			for $n in $status/*
			return
				if ($n[self::created_at or self::created__at]) then
					<created_at type="string">{tw:get-twitter-date(tw:get-iso-date($n) + xs:dayTimeDuration("PT1H"))}</created_at>
				else if ($n[self::text]) then
					<text type="string">FV @{fn:data(($status/user/screen_name, $status/user/screen__name)[1])}: {fn:data($n)}</text>
				else if ($n[self::user]) then
					(: replace original user with minimal accurate data of current user. Just needs presence of at least one other tweet
					   of who is favoriting someone elses tweet.. :)
					let $user-tweet :=
						cts:search(fn:doc(), cts:element-attribute-value-query(xs:QName("tw:from"), xs:QName("id"), $screen_name))[1]/atom:entry
					return
						<user>
							<name type="string">{fn:data(($user-tweet/atom:author/atom:name, $screen_name)[1])}</name>
							<screen_name type="string">{$screen_name}</screen_name>
							<profile_image_url>{fn:data($user-tweet/atom:link[@rel = 'image'])}</profile_image_url>
						</user>
				else $n
		}</status>
	else ()
};

declare function tw:status2feed($status as element(status))
	as element(atom:entry)
{
	let $id := fn:string($status/id)
	let $user-id := fn:lower-case(($status/user/screen_name, $status/user/screen__name)[1])
	let $user-name := fn:string($status/user/name)
	let $title := fn:string($status/text)
	let $published := tw:get-iso-date(($status/created_at, $status/created__at)[1])
	let $link := fn:concat('http://twitter.com/', $user-id, '/statuses/', $id)
	let $author-name := fn:concat($user-id, ' (', $user-name, ')')
	let $author-uri := fn:concat('http://twitter.com/', $user-id)
	let $image-link := ($status/user/profile_image_url, $status/user/profile__image__url)[1]/fn:string(.)
	let $image-type := if ($image-link) then fn:replace($image-link, '^.*\.([^\.]+)$', '$1') else ()
	let $result-type := fn:string(($status/result_type, $status/result__type)[1])
	let $source := fn:string($status/source)
	let $lang := fn:string(($status/iso_language_code, $status/iso__language__code)[1])
	return
	<entry xmlns="http://www.w3.org/2005/Atom">
	  <id>tag:search.twitter.com,2005:{$id}</id>

	  <published>{$published}</published>
	  <link type="text/html" href="{$link}" rel="alternate"/>
	  <title>{$title}</title>
	  <content type="html">{$title}</content>

	  <updated>{$published}</updated>
	  {
		if ($image-link) then
			<link type="image/{($image-type[. != ''][. != $image-link], 'png')[1]}" href="{$image-link}" rel="image"/>
		else ()
	  }

      <twitter:geo xmlns:twitter="http://api.twitter.com/"/> { (: What should be in here?? :) }
      <twitter:metadata xmlns:twitter="http://api.twitter.com/">
        <twitter:result_type>{$result-type}</twitter:result_type>
      </twitter:metadata>
      <twitter:source xmlns:twitter="http://api.twitter.com/">{$source}</twitter:source>
      <twitter:lang xmlns:twitter="http://api.twitter.com/">{$lang}</twitter:lang>
	
	  <author>
		<name>{$author-name}</name>
		<uri>{$author-uri}</uri>
	  </author>
	</entry>
};

declare function tw:update-timelines($user-ids as xs:string*, $overwrite as xs:boolean, $include-friends as xs:boolean, $include-followers as xs:boolean)
	as item()*
{
	let $user-ids := fn:distinct-values(($user-ids,
		if ($include-friends) then
			for $user-id in $user-ids
			return
				tw:get-friends($user-id)
		else (),
		if ($include-followers) then
			for $user-id in $user-ids
			return
				tw:get-followers($user-id)
		else ()
	))
	
	let $vars := map:map()
	let $_ := map:put($vars, "users", $user-ids)
	let $_ := map:put($vars, "overwrite", $overwrite)
	let $_ :=
		xdmp:spawn("update-timelines.xqy", (xs:QName("vars"), $vars))
	for $user-id in $user-ids
	return
		fn:concat("Updating ", $user-id, " timeline..")
};

declare function tw:update-timeline($user-id as xs:string, $overwrite as xs:boolean?, $base-url as xs:string?, $params as element()?, $recurse as xs:integer?, $retry as xs:integer?)
	as item()*
{
	(:
	xdmp:set($enable-online, fn:true()),
	xdmp:set($timeline-recursion-limit, 3),
	:)
	
	try {
		let $log := xdmp:log(fn:concat("Updating ", $user-id, " timeline", if ($overwrite) then " with overwrite" else (), if ($base-url) then " recovering from rate limit exceeded" else (), ".."))
	
		let $tweets :=
			if ($base-url) then
				tw:get-timeline($user-id, (), $params/max_id, $overwrite, $recurse, $retry)
			else
				tw:get-timeline($user-id, (), $overwrite)
				
		let $user-id := ($tweets[1]/user/screen_name, $tweets[1]/user/screen__name)[1] (: make sure to use the original screen_name case :)
		let $log := xdmp:log(fn:count($tweets))
		
		for $tweet in $tweets
		let $feed := tw:status2feed($tweet)
		let $feed-uri := tw:get-feed-uri($feed)
		return
			if (fn:not($overwrite) and tw:exists-feed($feed-uri)) then
				xdmp:log(fn:concat('Skipped existing feed ', $feed-uri))
			else
				let $log := xdmp:log($feed-uri)
				let $feed :=
					tw:enrich-feed($feed)
				return
					($feed, tw:store-feed($feed-uri, $feed))
	} catch ($e) {
		if ($debug) then xdmp:log($e) else (),
		if (fn:contains(fn:string($e), 'RATE-LIMIT-EXCEEDED')) then
			let $log := xdmp:log(fn:concat("Rate limit exceeded. Sleeping 5 min before respawning update of ", $user-id, " timeline.."))
			let $sleep := xdmp:sleep(300000) (: 5 min :)

			(: capture where processing halted, and resubmit.. :)
			let $data := $e//error:data
			let $vars := map:map()
			let $_ := map:put($vars, "overwrite", $overwrite)
			let $_ := map:put($vars, "base-url", $data/*[1]/fn:string(.))
			let $_ := map:put($vars, "params", $data/*[2]/xdmp:unquote(.)/*)
			let $_ := map:put($vars, "recurse", $data/*[3]/xs:integer(fn:string(.)))
			let $_ := map:put($vars, "retry", $data/*[4]/xs:integer(fn:string(.)))
			
			return
				xdmp:spawn("update-timeline.xqy", (xs:QName("user"), $user-id, xs:QName("vars"), $vars))
		else
			xdmp:log(fn:concat("Update of ", $user-id, " timeline failed: ", $e/*:format-string))
	}
};

declare function tw:update-favorites($user-ids as xs:string*, $overwrite as xs:boolean, $include-friends as xs:boolean, $include-followers as xs:boolean)
	as item()*
{
	let $user-ids := fn:distinct-values(($user-ids,
		if ($include-friends) then
			for $user-id in $user-ids
			return
				tw:get-friends($user-id)
		else (),
		if ($include-followers) then
			for $user-id in $user-ids
			return
				tw:get-followers($user-id)
		else ()
	))
	
	let $vars := map:map()
	let $_ := map:put($vars, "users", $user-ids)
	let $_ := map:put($vars, "overwrite", $overwrite)
	let $_ :=
		xdmp:spawn("update-favoriteses.xqy", (xs:QName("vars"), $vars))
	for $user-id in $user-ids
	return
		fn:concat("Updating ", $user-id, " favorites..")
};

declare function tw:update-favorites($user-id as xs:string, $overwrite as xs:boolean?, $base-url as xs:string?, $params as element()?, $recurse as xs:integer?, $retry as xs:integer?)
	as item()*
{
	(:
	xdmp:set($enable-online, fn:true()),
	xdmp:set($favorites-recursion-limit, 3),
	:)
	
	try {
		let $log := xdmp:log(fn:concat("Updating ", $user-id, " favorites", if ($overwrite) then " with overwrite" else (), if ($base-url) then " recovering from rate limit exceeded" else (), ".."))
	
		let $tweets :=
			if ($base-url) then
				tw:get-favorites($user-id, (), $params/max_id, $overwrite, $recurse, $retry)
			else
				tw:get-favorites($user-id, (), $overwrite)

		let $fav-user-id := ($tweets[1]/user/screen_name, $tweets[1]/user/screen__name)[1] (: make sure to use the original screen_name case :)
		let $log := xdmp:log(fn:count($tweets))
		
		(: get rid of duplicates, they cause conflicting updates!! :)
		let $feeds := map:map()
		let $_ := 
			for $tweet in $tweets
			for $fav in tw:status2favorite($tweet, $user-id)
			let $feed := tw:status2feed($fav)
			let $feed-uri := tw:get-feed-uri($feed)
			where fn:not(fn:exists(map:get($feeds, $feed-uri)))
			return (
				map:put($feeds, $feed-uri, $feed),
				$feed
			)
		
		for $feed-uri in map:keys($feeds)
		let $feed := map:get($feeds, $feed-uri)
		return
			if (fn:not($overwrite) and tw:exists-feed($feed-uri)) then
				xdmp:log(fn:concat('Skipped existing feed ', $feed-uri))
			else
				let $log := xdmp:log($feed-uri)
				let $feed :=
					tw:enrich-feed($feed)
				return
					($feed, tw:store-feed($feed-uri, $feed))
	} catch ($e) {
		if ($debug) then xdmp:log($e) else (),
		if (fn:contains(fn:string($e), 'RATE-LIMIT-EXCEEDED')) then
			let $log := xdmp:log(fn:concat("Rate limit exceeded. Sleeping 5 min before respawning update of ", $user-id, " favorites.."))
			let $sleep := xdmp:sleep(300000)

			(: capture where processing halted, and resubmit.. :)
			let $data := $e//error:data
			let $vars := map:map()
			let $_ := map:put($vars, "overwrite", $overwrite)
			let $_ := map:put($vars, "base-url", $data/*[1]/fn:string(.))
			let $_ := map:put($vars, "params", $data/*[2]/xdmp:unquote(.)/*)
			let $_ := map:put($vars, "recurse", $data/*[3]/xs:integer(fn:string(.)))
			let $_ := map:put($vars, "retry", $data/*[4]/xs:integer(fn:string(.)))
			
			return
				xdmp:spawn("update-favorites.xqy", (xs:QName("user"), $user-id, xs:QName("vars"), $vars))
		else
			xdmp:log(fn:concat("Update of ", $user-id, " favorites failed: ", $e/*:format-string))
	}
};

declare function tw:enrich-feeds($query as xs:string*)
	as item()*
{
	(:
	for $feed in tw:search-feeds($query)
	let $feed-uri := fn:base-uri($feed)
	return
		if (fn:exists($feed/tw:*)) then
			fn:concat("Skipping enriched feed ", $feed-uri)
		else (
			let $feed :=
				tw:enrich-feed($feed)
			return
				($feed, xdmp:document-insert($feed-uri, $feed, xdmp:default-permissions(), $feeds-collection))
		)
	:)
	let $count := tw:estimate-feeds($query)
	let $nr-transactions := fn:ceiling($count div 1000)
	for $transaction-nr in (1 to $nr-transactions)
	let $params := map:map()
	let $feed-uris := tw:get-feed-uris($query, $transaction-nr, 1000)
	let $log := xdmp:log(fn:count($feed-uris))
	(:
	let $log := xdmp:log($feed-uris)
	:)
	let $put := map:put($params, "feed-uris", $feed-uris)
	let $put := map:put($params, "enable-online", fn:true())
	let $queue := q:create-task("enrich-feeds.xqy", 0, $params)
	return
		fn:count($feed-uris)
};

declare function tw:enrich-feed($feed as element(atom:entry))
	as element(atom:entry)
{
	tw:enrich(
		$feed,
		fn:substring-before($feed/atom:author/atom:name, ' '),
		xs:dateTime($feed/atom:published),
		fn:string($feed/atom:title)
	)
};

declare function tw:enrich($tweet as element(), $screen_name as xs:string, $date as xs:dateTime, $text as xs:string)
	as element()
{
	let $from := <tw:from id="{fn:lower-case($screen_name)}">{$screen_name}</tw:from>
	
	let $iso-date := <tw:published iso-date="{$date}" date="{xs:date($date)}" time="{xs:time($date)}">{$date}</tw:published>

	let $is-retweet := fn:matches($text, '(RT|RSS|FV) @')
	let $org-text :=
		if ($is-retweet) then
			fn:replace($text, '^.*(RT|RSS|FV) @[a-zA-Z0-9_]+:?\s+(.*)$', '$2')
		else if (fn:string-length($text) gt 133 - fn:string-length($screen_name)) then
			fn:concat(fn:substring($text, 1, 133 - fn:string-length($screen_name)), "…")
		else $text
	let $enriched-text := <tw:text org="{$org-text}">{ if ($enable-text-enrichment) then tw:enrich-text($text) else $text }</tw:text>
	
	let $class := tw:get-classification($text)
	let $has-mentions := tw:contains-mentions($text)
	
	let $text := fn:string-join(for $n in $enriched-text/node() where fn:not($n/self::tw:url) return fn:string($n), '')
	let $monograms := tw:get-n-grams($text, 1)
	let $bigrams := tw:get-n-grams($text, 2)
	let $trigrams := tw:get-n-grams($text, 3)
	
	let $tweet :=
		element {fn:node-name($tweet)} {
			$tweet/@*,
			
			attribute {xs:QName("tw:class")} {$class},
			if ($has-mentions) then
				attribute {xs:QName("tw:contains-mentions")} {'true'}
			else (),
			
			$from,
			$iso-date,
			$enriched-text,
			
			for $n-gram in $monograms
			return
				<tw:n-gram1>{$n-gram}</tw:n-gram1>,
			for $n-gram in $bigrams
			return
				<tw:n-gram2>{$n-gram}</tw:n-gram2>,
			for $n-gram in $trigrams
			return
				<tw:n-gram3>{$n-gram}</tw:n-gram3>,
			
			$tweet/node()
		}
(:	let $log :=
		xdmp:log($tweet) :)
	return
		$tweet
};

declare function tw:get-n-grams($text, $n) {
	(:
	let $words := fn:tokenize($text, '\s+')
	:)
	(: use ML tokenize, so you get same word tokens as word-query
       use normalize-unicode and replace to get rid of diacritics
       use lower-case to ignore case
       use cts:stem to ignore stemming differences
	 :)
	(:
	let $words := for $word in cts:tokenize(fn:lower-case(fn:replace(fn:normalize-unicode($text, 'NFD'), '[\p{M}]', '')))[. instance of cts:word] return cts:stem($word)
	:)
	let $words := cts:tokenize(fn:lower-case(fn:replace(fn:normalize-unicode($text, 'NFD'), '[\p{M}]', '')))[. instance of cts:word]
	for $word at $pos in $words[fn:position() <= (fn:last() - $n + 1)] (: syntax highlight fix: > :)
	let $next-words := $words[$pos to ($pos + $n - 1)]
	return
		fn:string-join($next-words, ' ')
};

declare function tw:unrich-feeds($query as xs:string)
	as item()*
{
	let $feeds := tw:search-feeds($query)
			
	for $feed in $feeds
	let $feed-uri := fn:base-uri($feed)
	return
		if (fn:exists($feed/tw:*)) then
			let $feed := tw:unrich($feed)
			return
				($feed, xdmp:document-insert($feed-uri, $feed, xdmp:default-permissions(), $feeds-collection))
		else
			fn:concat("Skipping unrich feed ", $feed-uri)
};

declare function tw:unrich($tweet as element())
	as element()
{
	element {fn:node-name($tweet)} {
		$tweet/@* except $tweet/@tw:*,
		$tweet/node() except $tweet/tw:*
	}
};

declare function tw:delete-feeds($query as item()*)
	as xs:string*
{
	for $feed in tw:search-feeds($query)
	let $feed-uri := fn:base-uri($feed)
	return
		(fn:concat('Deleted feed ', $feed-uri), xdmp:document-delete($feed-uri))
};

declare function tw:exists-feed($uri as xs:string)
	as xs:boolean
{
	(:
	fn:exists(tw:get-feed($uri))
	:)
	let $full-uri := fn:concat('/feeds/', $uri)
	return
		cts:uris($full-uri)[1] = $full-uri
};

declare function tw:get-feed($uri as xs:string)
	as element(atom:entry)?
{
	fn:doc(fn:concat('/feeds/', $uri))/*
};

declare function tw:get-feed-uri($feed as element(atom:entry))
	as xs:string
{
	let $uri := fn:base-uri($feed)
	return
		if (fn:exists($uri) and fn:starts-with($uri, '/feeds/')) then
			fn:substring-after($uri, '/feeds/')
		else
			fn:string($feed/atom:link[@type eq 'text/html']/@href)
};

declare function tw:store-feed($uri as xs:string, $feed as element(atom:entry))
	as empty-sequence()
{
	xdmp:document-insert(fn:concat('/feeds/', $uri), $feed, xdmp:default-permissions(), $feeds-collection)
};

(: Statuses :)

declare function tw:search-statuses($query as item()*)
	as element(status)*
{
	let $query := tw:parse-query($query)
	for $i in cts:search(fn:collection($statuses-collection), cts:and-query($query))/*
	order by xs:dateTime($i/tw:published/@iso-date) descending
	return $i
};

declare function tw:search-statuses($query as item()*, $page as xs:integer, $count as xs:integer)
	as element(status)*
{
	let $query := tw:parse-query($query)
	let $start := $page * $count + 1
	let $end := ($page + 1) * $count
	return
		cts:search(fn:collection($statuses-collection), cts:and-query($query))[$start to $end]/*
};

declare function tw:update-statuses($query as xs:string, $full as xs:boolean)
	as item()*
{
	let $refresh-all := fn:false()
	
	let $feeds := tw:search-feeds($query)
	let $statuses := tw:search-statuses($query)

	let $new-feeds := (
		for $feed in $feeds
		let $feed-uri := fn:base-uri($feed)
		let $tweet-uri := fn:substring-after($feed-uri, '/feeds/')
		where fn:not(tw:exists-status($tweet-uri))
		return
			$feed
	)
	let $update-authors := fn:distinct-values(
		for $feed in $new-feeds
		let $user-id := $feed/tw:from/@id/fn:data(.)
		where fn:exists($user-id)
		order by $user-id
		return $user-id
	)
	let $unknown-users := (
		let $feed-users := $feeds/tw:from/@id/fn:data(.)
		let $feed-mentions := $feeds/tw:text/tw:user/@id/fn:data(.)
		let $status-users := $statuses/tw:from/@id/fn:data(.)
		let $status-mentions := $statuses/tw:text/tw:user/@id/fn:data(.)

		for $user in fn:distinct-values(($feed-users, $feed-mentions, $status-users, $status-mentions))
		let $user-tweets := (/status/tw:from[@id eq $user])[1]
		where $refresh-all or fn:empty($user-tweets)
		order by $user
		return
			$user
	)
	let $users := fn:distinct-values(($update-authors, $unknown-users))
	let $get-users := if ($refresh-all) then $users else $users[1 to 20]
	
	let $vars := map:map()
	let $map := map:put($vars, "query", $query)
	let $map := map:put($vars, "users", $get-users)
	let $map := map:put($vars, "full", $full)
	let $spawn := xdmp:spawn("get-timelines.xqy", (xs:QName("vars"), $vars))
	return (

		for $user-id in $get-users
		(: TODO: restore this bit, *after* implementing a begin date; when date before first user tweet, skip this, otherwise use this to speed up get-timeline.. :)
		(:
		let $user-tweets := /status/user[id eq $user-id]
		let $is-known-user := fn:exists($user-tweets)
		let $latest-user-tweet := (for $tweet in $user-tweets order by xs:dateTime($tweet/created_at/@iso-date) descending return $tweet)[1]
		let $tweets := tw:get-timeline($user-id, $latest-user-tweet/id, $full)
		: )
		let $tweets := tw:get-timeline($user-id, (), $full)
		let $user-id := ($tweets[1]/user/screen_name, $tweets[1]/user/screen__name)[1] (: make sure to use the original screen_name case :)
		
		for $tweet in $tweets[cts:contains(., cts:and-query($query))]
		let $tweet-id := fn:data($tweet/id)
		let $tweet-uri := fn:concat('http://twitter.com/', $user-id, '/statuses/', $tweet-id)
		return
			if (tw:exists-status($tweet-uri)) then
				fn:concat('Skipped existing status ', $tweet-uri)
			else
				let $tweet :=
					tw:enrich-status($tweet)
				return
					($tweet, tw:store-status($tweet-uri, $tweet))
		:)
		return
			fn:concat('Spawned getting timeline for ', $user-id),
			
		if (fn:count($users) > 20) then
			'Spawning was limited to first 20 users, repeat update after 20 min..'
		else
			()
	)
};

declare function tw:enrich-statuses($query as xs:string)
	as item()*
{
	let $statuses := tw:search-statuses($query)
			
	for $status in $statuses
	let $status-uri := fn:base-uri($status)
	return
		if (fn:exists($status/tw:*)) then
			fn:concat("Skipping enriched status", $status-uri)
		else (
			let $status :=
				tw:enrich-status($status)
			return
				($status, tw:store-status($status-uri, $status))
		)
};

declare function tw:enrich-status($status as element(status))
	as element(status)
{
	tw:enrich(
		$status,
		fn:string(($status/user/screen_name, $status/user/screen__name)[1]),
		tw:get-iso-date(($status/created_at, $status/created__at)[1]),
		fn:string($status/text)
	)
};

declare function tw:unrich-statuses($query as xs:string)
	as item()*
{
	let $statuses := tw:search-statuses($query)
			
	for $status in $statuses
	let $status-uri := fn:base-uri($status)
	return
		if (fn:exists($status/tw:*)) then (
			let $status := tw:unrich($status)
			return
				($status, tw:store-status($status-uri, $status))
		) else
			fn:concat("Skipping unrich status ", $status-uri)
};

declare function tw:delete-statuses($query as item()*)
	as xs:string*
{
	for $status in tw:search-statuses($query)
	let $uri := fn:base-uri($status)
	return
		(fn:concat('Deleted status ', $uri), xdmp:document-delete($uri))
};
declare function tw:exists-status($uri as xs:string)
	as xs:boolean
{
	(:
	fn:exists(tw:get-status($uri))
	:)
	cts:uris($uri)[1] = $uri
};

declare function tw:get-status($uri as xs:string)
	as element(status)?
{
	fn:doc($uri)/*
};

declare function tw:store-status($uri as xs:string, $status as element(status))
	as empty-sequence()
{
	xdmp:document-insert($uri, $status, xdmp:default-permissions(), $statuses-collection)
};

declare function tw:get-status-uri($status as element(status))
	as xs:string
{
	let $uri := fn:base-uri($status)
	return
		if (fn:exists($uri) and fn:not(fn:starts-with($uri, 'http://api.twitter.com'))) then
			$uri
		else
			fn:concat("http://twitter.com/", fn:lower-case(($status/user/screen_name, $status/user/screen__name)[1]), "/statuses/", $status/id)
};

(: Utilities :)

declare variable $months := ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

declare function tw:get-iso-date($twitter-date as xs:string)
	as xs:dateTime
{
	(: Sun Aug 07 12:25:12 +0000 2011 :)
	(: #1  #2  #3 #4       #5    #6   :)
	let $date := fn:tokenize($twitter-date, '\s+')
	let $year := $date[6]
	let $month := fn:index-of($months, $date[2])
	let $month := if ($month lt 10) then fn:concat('0', $month) else fn:string($month)
	let $day := $date[3]
	let $time := $date[4]
	let $tz := fn:concat(fn:substring($date[5], 1, 3), ':', fn:substring($date[5], 4, 2))
	return
		xs:dateTime(fn:concat($year, '-', $month, '-', $day, 'T', $time, $tz))
};

declare function tw:get-twitter-date($date as xs:dateTime) as xs:string {
	(: Sun Aug 07 12:25:12 +0000 2011 :)
	(: #1  #2  #3 #4       #5    #6   :)
	fn:concat(
		functx:day-of-week-abbrev-en($date),
		' ',
		functx:month-abbrev-en($date),
		' ',
		let $day := fn:day-from-dateTime($date)
		return if ($day lt 10) then fn:concat('0', $day) else $day,
		' ',
		let $hours := fn:hours-from-dateTime($date)
		return if ($hours lt 10) then fn:concat('0', $hours) else $hours,
		':',
		let $minutes := fn:minutes-from-dateTime($date)
		return if ($minutes lt 10) then fn:concat('0', $minutes) else $minutes,
		':',
		let $seconds := fn:seconds-from-dateTime($date)
		return if ($seconds lt 10) then fn:concat('0', $seconds) else $seconds,
		' ',
		fn:replace(functx:timezone-from-duration(fn:timezone-from-dateTime($date)), 'Z', '+0000'),
		' ',
		fn:year-from-dateTime($date)
	)
};

declare function tw:enrich-text($text as xs:string)
	as item()*
{
	for $x in fn:analyze-string($text, 'http://[^\s,)]*[^\s,)\."]')/*
	return
		if ($x/self::*:match) then
			let $full-url := (tw:resolve-url($x/text()), $x/text())[1]
			let $long-url := if (fn:contains($full-url, '?')) then fn:substring-before($full-url, '?') else $full-url
			return
				<tw:url full="{$full-url}" long="{$long-url}" org="{$x/text()}">{$long-url}</tw:url>
		else
			for $y in fn:analyze-string($x/text(), "#[^\s\.,!?\);:']+")/* (: ' :)
			let $tag := fn:lower-case(fn:substring-after($y/text(), '#'))
			return
				if ($y/self::*:match) then
					<tw:tag id="{$tag}">{$y/text()}</tw:tag>
				else
					for $z in fn:analyze-string($y/text(), '@[a-zA-Z0-9_]+')/*
					let $id := fn:lower-case(fn:substring-after($z/text(), '@'))
					return
						if ($z/self::*:match) then
							<tw:user id="{$id}">{$z/text()}</tw:user>
						else
							$z/text()
};

declare function tw:get-classification($text as xs:string)
	as xs:string
{
	let $is-retweet := fn:matches($text, '^(RT|RSS) ')
	let $is-favorite := fn:matches($text, '^FV ')
	let $is-commented-retweet := fn:matches($text, ' (RT|RSS|FV) ')
	let $is-reply := fn:matches($text, '^@')
	(:
	let $is-duplicate := fn:count($tweets/tweet[$t >> .][subject eq $t/subject]) > 0
	:)

	return
		if ($is-retweet) then
			'retweet'
		else if ($is-favorite) then
			'favorite'
		else if ($is-commented-retweet) then
			'comment'
		else if ($is-reply) then
			'reply'
		(:
		else if ($is-duplicate) then
			'duplicate'
		:)
		else
			'tweet'
};

declare function tw:contains-mentions($text as xs:string)
	as xs:boolean
{
	fn:matches(
		(: exclude reply mentions :)
		fn:replace(
			(: exclude RT mentions :)
			fn:replace($text, '(RT|RSS|FV) @', 'RT '),
			'^@[^ ]+ (@[^ ]+ )+', ''
		),
		' @'
	)
};

declare function tw:get-iso-date2($ms-date as xs:string)
	as xs:dateTime
{
	let $stamp := fn:replace($ms-date, '^(\d)-(\d+)-', '0$1-$2-') 
	let $stamp := fn:replace($stamp, '^(\d+)-(\d)-', '$1-0$2-') 
	let $stamp := fn:replace($stamp, ' (\d):', ' 0$1:')
	return
		xs:dateTime(fn:replace($stamp, '^(\d+)-(\d+)-(\d+) (\d+:\d+:\d+)$', '$3-$2-$1T$4Z'))
};

declare function tw:message-to-html(
	$message as item()*
)
	as item()*
{
	for $n in $message
	return
		typeswitch ($n)
		case element(tw:url)
			return <a href="{$n/@full}" alt="{$n/@long}" target="_blank">{fn:data($n/@long)}</a>
		case element(tw:tag)
			return <a href="http://twitter.com/#!/search/%23{$n/@id}" target="_blank">{$n/node()}</a>
		case element(tw:user)
			return <a href="http://twitter.com/{$n/@id}" target="_blank">{$n/node()}</a>
		case element(tw:from)
			return <a href="http://twitter.com/{$n/@id}" target="_blank">@{$n/node()}</a>
		case element()
			return tw:message-to-html($n/node())
		default
			return $n
};

declare variable $database := xdmp:database();

declare function tw:has-indexes() as xs:boolean {
	let $config := admin:get-configuration()
	return
		fn:boolean(admin:database-get-range-element-attribute-indexes($config, xdmp:database())//db:parent-namespace-uri = 'http://grtjn.nl/twitter/utils')
};

declare function tw:delete-all-indexes($config) {
    let $remove-indexes :=
      for $index in admin:database-get-element-attribute-word-lexicons($config, $database)
      return
        xdmp:set($config, admin:database-delete-element-attribute-word-lexicon($config, $database, $index))
    let $remove-indexes :=
      for $index in admin:database-get-element-word-lexicons($config, $database)
      return
        xdmp:set($config, admin:database-delete-element-word-lexicon($config, $database, $index))
    let $remove-indexes :=
      for $index in admin:database-get-element-word-query-throughs($config, $database)
      return
        xdmp:set($config, admin:database-delete-element-word-query-through($config, $database, $index))
	  
	(: remove any existing field :)
	let $remove-fields :=
		for $field as xs:string in admin:database-get-fields($config, $database)/db:field-name[. != ""]
		return
			xdmp:set($config, admin:database-delete-field($config, $database, $field))
 
    let $remove-indexes :=
      for $index in admin:database-get-geospatial-element-attribute-pair-indexes($config, $database)
      return
        xdmp:set($config, admin:database-delete-geospatial-element-attribute-pair-index($config, $database, $index))
    let $remove-indexes :=
      for $index in admin:database-get-geospatial-element-child-indexes($config, $database)
      return
        xdmp:set($config, admin:database-delete-geospatial-element-child-index($config, $database, $index))
    let $remove-indexes :=
      for $index in admin:database-get-geospatial-element-indexes($config, $database)
      return
        xdmp:set($config, admin:database-delete-geospatial-element-index($config, $database, $index))
    let $remove-indexes :=
      for $index in admin:database-get-geospatial-element-pair-indexes($config, $database)
      return
        xdmp:set($config, admin:database-delete-geospatial-element-pair-index($config, $database, $index))
    let $remove-indexes :=
      for $index in admin:database-get-phrase-arounds($config, $database)
      return
        xdmp:set($config, admin:database-delete-phrase-around($config, $database, $index))
    let $remove-indexes :=
      for $index in admin:database-get-phrase-throughs($config, $database)
      return
        xdmp:set($config, admin:database-delete-phrase-through($config, $database, $index))
	
	(: remove any existing range element index :)
	let $remove-indexes :=
		for $index in admin:database-get-range-element-indexes($config, $database)
		return
			xdmp:set($config, admin:database-delete-range-element-index($config, $database, $index))

    (: remove any existing range element attribute index :)
    let $remove-indexes :=
      for $index in admin:database-get-range-element-attribute-indexes($config, $database)
      return
        xdmp:set($config, admin:database-delete-range-element-attribute-index($config, $database, $index))

(:
    let $remove-indexes :=
      for $index in admin:database-get-range-field-indexes($config, $database)
      return
        xdmp:set($config, admin:database-delete-range-field-index($config, $database, $index))
:)
    let $remove-indexes :=
      for $index in admin:database-get-word-lexicons($config, $database)
      return
        xdmp:set($config, admin:database-delete-word-lexicon($config, $database, $index))

	return $config
};

declare function tw:add-elem-index($config, $index) {
(:
	let $config :=
		try {
			admin:database-delete-range-element-index($config, $database, $index)
		} catch ($e) {
			$config
		}
	return
:)
		try {
			admin:database-add-range-element-index($config, $database, $index)
		} catch ($e) {
			$config
		}
};

declare function tw:add-elem-word-lex($config, $index) {
(:
	let $config :=
		try {
			admin:database-delete-element-word-lexicon($config, $database, $index)
		} catch ($e) {
			$config
		}
	return
:)
		try {
			admin:database-add-element-word-lexicon($config, $database, $index)
		} catch ($e) {
			$config
		}
};

declare function tw:add-attr-index($config, $index) {
(:
	let $config :=
		try {
			admin:database-delete-range-element-attribute-index($config, $database, $index)
		} catch ($e) {
			$config
		}
	return
:)
		try {
			admin:database-add-range-element-attribute-index($config, $database, $index)
		} catch ($e) {
			$config
		}
};

declare function tw:create-indexes() {
	(:
	Element Range indexes:
	string - http://grtjn.nl/twitter/utils - text - default collation - false
	string - http://grtjn.nl/twitter/utils - n-gram1 - http://marklogic.com/collation/nl/S1/AS/T00BB - false
	string - http://grtjn.nl/twitter/utils - n-gram2 - http://marklogic.com/collation/nl/S1/AS/T00BB - false
	string - http://grtjn.nl/twitter/utils - n-gram3 - http://marklogic.com/collation/nl/S1/AS/T00BB - false

	Attribute Range indexes:
	date - http://grtjn.nl/twitter/utils - published - (niks) - date - false
	dateTime - http://grtjn.nl/twitter/utils - published - (niks) - iso-date - false
	time - http://grtjn.nl/twitter/utils - published - (niks) - time - false
	string - (niks) - status - http://grtjn.nl/twitter/utils - class - default collation - false
	string - (niks) - status - http://grtjn.nl/twitter/utils - contains-mentions - default collation - false
	string - http://www.w3.org/2005/Atom - entry - http://grtjn.nl/twitter/utils - class - default collation - false
	string - http://www.w3.org/2005/Atom - entry - http://grtjn.nl/twitter/utils - contains-mentions - default collation - false
	string - http://grtjn.nl/twitter/utils - from - (niks) - id - default collation - false
	string - http://grtjn.nl/twitter/utils - tag - (niks) - id - default collation - false
	string - http://grtjn.nl/twitter/utils - text - (niks) - org - default collation - false
	string - http://grtjn.nl/twitter/utils - url - (niks) - org - default collation - false
	string - http://grtjn.nl/twitter/utils - url - (niks) - long - default collation - false
	string - http://grtjn.nl/twitter/utils - url - (niks) - full - default collation - false
	string - http://grtjn.nl/twitter/utils - user - (niks) - id - default collation - false

	string - http://grtjn.nl/twitter/utils - url-lookup - (niks) - short - default collation - false
	string - http://grtjn.nl/twitter/utils - url-lookup - (niks) - long - default collation - false
	string - http://grtjn.nl/twitter/utils - url-lookup - (niks) - full - default collation - false
	string - http://grtjn.nl/twitter/utils - url-lookup - (niks) - status - default collation - false
	
	Element word lexicon:
	http://grtjn.nl/twitter/utils - text - http://marklogic.com/collation/nl/S1/AS/T00BB
	:)

	let $config := admin:get-configuration()
	let $config := tw:delete-all-indexes($config)

	let $index := admin:database-range-element-index("string", "http://grtjn.nl/twitter/utils", "text", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-elem-index($config, $index)
	let $index := admin:database-range-element-index("string", "http://grtjn.nl/twitter/utils", "n-gram1", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-elem-index($config, $index)
	let $index := admin:database-range-element-index("string", "http://grtjn.nl/twitter/utils", "n-gram2", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-elem-index($config, $index)
	let $index := admin:database-range-element-index("string", "http://grtjn.nl/twitter/utils", "n-gram3", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-elem-index($config, $index)
	(:
	let $index := admin:database-range-element-index("string", "http://grtjn.nl/twitter/utils", "n-gram", "http://marklogic.com/collation/nl/S1/AS/T00BB", fn:false() )
	let $config := tw:add-elem-index($config, $index)
	:)

	let $index := admin:database-range-element-attribute-index("date", "http://grtjn.nl/twitter/utils", "published", "", "date", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("dateTime", "http://grtjn.nl/twitter/utils", "published", "", "iso-date", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("time", "http://grtjn.nl/twitter/utils", "published", "", "time", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "", "status", "http://grtjn.nl/twitter/utils", "class", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "", "status", "http://grtjn.nl/twitter/utils", "contains-mentions", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "http://www.w3.org/2005/Atom", "entry", "http://grtjn.nl/twitter/utils", "class", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "http://www.w3.org/2005/Atom", "entry", "http://grtjn.nl/twitter/utils", "contains-mentions", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "http://grtjn.nl/twitter/utils", "from", "", "id", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "http://grtjn.nl/twitter/utils", "tag", "", "id", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "http://grtjn.nl/twitter/utils", "text", "", "org", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "http://grtjn.nl/twitter/utils", "url", "", "org", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "http://grtjn.nl/twitter/utils", "url", "", "long", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "http://grtjn.nl/twitter/utils", "url", "", "full", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "http://grtjn.nl/twitter/utils", "user", "", "id", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)

	let $index := admin:database-range-element-attribute-index("string", "http://grtjn.nl/twitter/utils", "url-lookup", "", "short", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "http://grtjn.nl/twitter/utils", "url-lookup", "", "long", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "http://grtjn.nl/twitter/utils", "url-lookup", "", "full", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	let $index := admin:database-range-element-attribute-index("string", "http://grtjn.nl/twitter/utils", "url-lookup", "", "status", "http://marklogic.com/collation/", fn:false() )
	let $config := tw:add-attr-index($config, $index)
	
	let $index := admin:database-element-word-lexicon("http://grtjn.nl/twitter/utils", "text", "http://marklogic.com/collation/nl/S1/AS/T00BB")
	let $config := tw:add-elem-word-lex($config, $index)

	return
		admin:save-configuration($config)
};

declare variable $values-options := ("document", "frequency-order", "fragment-frequency");
declare variable $words-options := ("document", "frequency-order", "item-frequency");
declare variable $tweet-query :=
	cts:not-query(
		cts:element-attribute-value-query(
			(xs:QName("atom:entry"), xs:QName("status")),
			xs:QName("tw:class"),
			('retweet', 'favorite', 'duplicate'),
			'exact'
		)
	)
;
declare variable $retweet-query :=
	cts:element-attribute-value-query(
		(xs:QName("atom:entry"), xs:QName("status")),
		xs:QName("tw:class"),
		('retweet', 'duplicate'),
		'exact'
	)
;
declare variable $favorite-query :=
	cts:element-attribute-value-query(
		(xs:QName("atom:entry"), xs:QName("status")),
		xs:QName("tw:class"),
		'favorite',
		'exact'
	)
;

(:
declare variable $list := "aan,about,all,alles,als,altijd,and,andere,are,beginnen,ben,bij,but,can,daar,dacht,dan,dat,der,deze,die,dit,doch,doen,don,door,draait,dus,dwdd,een,eens,for,geen,geweest,haar,had,have,heb,hebben,heeft,hem,het,hier,hij,hoe,hun,iemand,iets,jij,jou,just,kan,kon,kunnen,kijken,lekker,maar,meer,men,met,mij,mijn,moet,naar,niet,niets,nog,not,omdat,ons,ook,over,reeds,tegen,that,the,there,think,this,toch,toen,tot,uit,van,veel,voor,want,waren,was,wat,weer,wel,werd,wereld,wezen,what,who,wie,wij,wil,with,worden,you,zag,zal,zei,zelf,zich,zij,zijn,zonder,zou,one,from,they,get,name,does,doesn,gone,going,did,didn,same,wonder,guess,isn,have,haven,sure,won";
declare variable $stem-language := 'en';
declare variable $words-to-exclude := fn:distinct-values(for $w in fn:tokenize($list, ",") return cts:stem($w,$stem-language));
:)

declare function tw:parse-query($query, $collection) {
	let $parse-q := tw:parse-query($query)
	let $coll-q := cts:collection-query($collection)
	return cts:and-query(($parse-q, $coll-q))
};

declare function tw:count-docs($q) {
	xdmp:estimate(cts:search(fn:doc(), $q))
};

(: basic trend data :)
declare function tw:get-basic-stats($parsed-query) {
	let $oldest-tweet :=
		(
			for $t in cts:search(fn:doc(), $parsed-query)
			order by xs:dateTime($t/tw:published/@iso-date) ascending
			return
				$t
		)[1]/*
	let $newest-tweet :=
		(
			for $t in cts:search(fn:doc(), $parsed-query)
			order by xs:dateTime($t/tw:published/@iso-date) descending
			return
				$t
		)[1]/*
	let $duration :=
		xs:dateTime($newest-tweet/tw:published/@iso-date) - xs:dateTime($oldest-tweet/tw:published/@iso-date)
	return
	<stats>
		<oldest-tweet>{$oldest-tweet/@*, $oldest-tweet/node()}</oldest-tweet>
		<newest-tweet>{$newest-tweet/@*, $newest-tweet/node()}</newest-tweet>
		<duration>{$duration}</duration>
		<total-tweets>{tw:count-docs($parsed-query)}</total-tweets>
		<nr-tweets>{tw:count-docs(cts:and-query(($parsed-query, $tweet-query)))}</nr-tweets>
		<nr-retweets>{tw:count-docs(cts:and-query(($parsed-query, $retweet-query)))}</nr-retweets>
		<nr-favorites>{tw:count-docs(cts:and-query(($parsed-query, $favorite-query)))}</nr-favorites>
		<types>{
			for $type in cts:element-attribute-values(xs:QName("atom:entry"), xs:QName("tw:class"), (), $values-options)
			let $type-query :=
				cts:element-attribute-value-query(
					(xs:QName("atom:entry"), xs:QName("status")),
					xs:QName("tw:class"),
					$type,
					'exact'
				)
			let $count := tw:count-docs(cts:and-query(($parsed-query, $type-query)))
			return
				element { fn:concat("nr-", fn:replace($type, 'y$', 'ie'), "s") } { $count }
		}</types>
	</stats>
};

declare function tw:get-facets($parsed-query, $max) {
	tw:get-facets($parsed-query, $max, (), 5, "en")
};

declare function tw:get-words-facet($parsed-query, $max) {
	tw:get-words-facet($parsed-query, $max, (), 5, "en")
};

(: calculation of facets :)
declare function tw:get-facets($parsed-query, $max, $domain-query, $threshold, $language) {
let $urls-facet :=
	(
		for $url in cts:element-attribute-values(xs:QName("tw:url"), xs:QName("full"), (), $values-options, $parsed-query)[1 to (5 * $max)]
		let $url-query :=
			cts:element-attribute-value-query(
				xs:QName("tw:url"),
				xs:QName("full"),
				$url,
				'exact'
			)
		let $tweet-sender-count :=
			fn:count(
				cts:element-attribute-values(
					xs:QName("tw:from"),
					xs:QName("id"),
					(),
					$values-options,
					cts:and-query((
						$parsed-query,
						$tweet-query,
						$url-query
					))
				)
			)
		let $retweet-sender-count :=
			fn:count(
				cts:element-attribute-values(
					xs:QName("tw:from"),
					xs:QName("id"),
					(),
					$values-options,
					cts:and-query((
						$parsed-query,
						$retweet-query,
						$url-query
					))
				)
			)
		let $favorite-sender-count :=
			fn:count(
				cts:element-attribute-values(
					xs:QName("tw:from"),
					xs:QName("id"),
					(),
					$values-options,
					cts:and-query((
						$parsed-query,
						$favorite-query,
						$url-query
					))
				)
			)
		let $sender-count := $tweet-sender-count + $retweet-sender-count + $favorite-sender-count
		let $tweet-count :=
			tw:count-docs(
				cts:and-query((
					$parsed-query,
					$tweet-query,
					$url-query
				))
			)
		let $retweet-count :=
			tw:count-docs(
				cts:and-query((
					$parsed-query,
					$retweet-query,
					$url-query
				))
			)
		let $favorite-count :=
			tw:count-docs(
				cts:and-query((
					$parsed-query,
					$favorite-query,
					$url-query
				))
			)
		let $count := $tweet-count + $retweet-count + $favorite-count
		order by $sender-count descending, $tweet-count descending, $favorite-count descending, $retweet-count descending, $url
		return
			<tw:url full="{$url}" long="{fn:replace($url, '\?.*$', '')}" org="{$url}" count="{$count}" tweets="{$tweet-count}" retweets="{$retweet-count}" favorites="{$favorite-count}" senders="{$sender-count}" tweet-senders="{$tweet-sender-count}" retweet-senders="{$retweet-sender-count}" favorite-senders="{$favorite-sender-count}">{$url}</tw:url>
	)[1 to $max]
let $tags-facet :=
	(
		for $tag in cts:element-attribute-values(xs:QName("tw:tag"), xs:QName("id"), (), $values-options, $parsed-query)[1 to (5 * $max)]
		let $tag-query :=
			cts:element-attribute-value-query(
				xs:QName("tw:tag"),
				xs:QName("id"),
				$tag,
				'exact'
			)
		let $tweet-sender-count :=
			fn:count(
				cts:element-attribute-values(
					xs:QName("tw:from"),
					xs:QName("id"),
					(),
					$values-options,
					cts:and-query((
						$parsed-query,
						$tweet-query,
						$tag-query
					))
				)
			)
		let $retweet-sender-count :=
			fn:count(
				cts:element-attribute-values(
					xs:QName("tw:from"),
					xs:QName("id"),
					(),
					$values-options,
					cts:and-query((
						$parsed-query,
						$retweet-query,
						$tag-query
					))
				)
			)
		let $favorite-sender-count :=
			fn:count(
				cts:element-attribute-values(
					xs:QName("tw:from"),
					xs:QName("id"),
					(),
					$values-options,
					cts:and-query((
						$parsed-query,
						$favorite-query,
						$tag-query
					))
				)
			)
		let $sender-count := $tweet-sender-count + $retweet-sender-count + $favorite-sender-count
		let $tweet-count :=
			tw:count-docs(
				cts:and-query((
					$parsed-query,
					$tweet-query,
					$tag-query
				))
			)
		let $retweet-count :=
			tw:count-docs(
				cts:and-query((
					$parsed-query,
					$retweet-query,
					$tag-query
				))
			)
		let $favorite-count :=
			tw:count-docs(
				cts:and-query((
					$parsed-query,
					$favorite-query,
					$tag-query
				))
			)
		let $count := $tweet-count + $retweet-count + $favorite-count
		order by $sender-count descending, $tweet-count descending, $favorite-count descending, $retweet-count descending, $tag
		return
			<tw:tag id="{$tag}" count="{$count}" tweets="{$tweet-count}" retweets="{$retweet-count}" favorites="{$favorite-count}" senders="{$sender-count}" tweet-senders="{$tweet-sender-count}" retweet-senders="{$retweet-sender-count}" favorite-senders="{$favorite-sender-count}">#{$tag}</tw:tag>
	)[1 to $max]
let $mentions-facet :=
	(
		for $mention in cts:element-attribute-values(xs:QName("tw:user"), xs:QName("id"), (), $values-options, $parsed-query)[1 to (5 * $max)]
		let $user-query :=
			cts:element-attribute-value-query(
				xs:QName("tw:user"),
				xs:QName("id"),
				$mention,
				'exact'
			)
		let $tweet-sender-count :=
			fn:count(
				cts:element-attribute-values(
					xs:QName("tw:from"),
					xs:QName("id"),
					(),
					$values-options,
					cts:and-query((
						$parsed-query,
						$tweet-query,
						$user-query
					))
				)
			)
		let $retweet-sender-count :=
			fn:count(
				cts:element-attribute-values(
					xs:QName("tw:from"),
					xs:QName("id"),
					(),
					$values-options,
					cts:and-query((
						$parsed-query,
						$retweet-query,
						$user-query
					))
				)
			)
		let $favorite-sender-count :=
			fn:count(
				cts:element-attribute-values(
					xs:QName("tw:from"),
					xs:QName("id"),
					(),
					$values-options,
					cts:and-query((
						$parsed-query,
						$favorite-query,
						$user-query
					))
				)
			)
		let $sender-count := $tweet-sender-count + $retweet-sender-count + $favorite-sender-count
		let $tweet-count :=
			tw:count-docs(
				cts:and-query((
					$parsed-query,
					$tweet-query,
					$user-query
				))
			)
		let $retweet-count :=
			tw:count-docs(
				cts:and-query((
					$parsed-query,
					$retweet-query,
					$user-query
				))
			)
		let $favorite-count :=
			tw:count-docs(
				cts:and-query((
					$parsed-query,
					$favorite-query,
					$user-query
				))
			)
		let $count := $tweet-count + $retweet-count + $favorite-count
		order by $sender-count descending, $tweet-count descending, $favorite-count descending, $retweet-count descending, $mention
		return
			<tw:user id="{$mention}" count="{$count}" tweets="{$tweet-count}" retweets="{$retweet-count}" favorites="{$favorite-count}" senders="{$sender-count}" tweet-senders="{$tweet-sender-count}" retweet-senders="{$retweet-sender-count}" favorite-senders="{$favorite-sender-count}">@{$mention}</tw:user>
	)[1 to $max]
let $date-max := fn:max(
	for $date in cts:element-attribute-values(xs:QName("tw:published"),	xs:QName("date"), (), $values-options, $parsed-query)
	return
		cts:frequency($date)
)
return
<facets>
	<time-facet max="{$date-max}" total="{fn:count(cts:element-attribute-values(xs:QName("tw:published"), xs:QName("date"), (), $values-options, $parsed-query))}">{
		for $date in cts:element-attribute-values(xs:QName("tw:published"),	xs:QName("date"), (), $values-options, $parsed-query)
		let $total-count := cts:frequency($date)
		let $tweet-count :=
				tw:count-docs(
					cts:and-query((
						$parsed-query,
						$tweet-query,
						cts:element-attribute-value-query(
							xs:QName("tw:published"),
							xs:QName("date"),
							fn:string($date),
							'exact'
						)
					))
				)
		let $retweet-count :=
				tw:count-docs(
					cts:and-query((
						$parsed-query,
						$retweet-query,
						cts:element-attribute-value-query(
							xs:QName("tw:published"),
							xs:QName("date"),
							fn:string($date),
							'exact'
						)
					))
				)
		let $favorite-count := $total-count - $tweet-count - $retweet-count
		order by xs:date($date) ascending
		return
			<tw:published count="{$total-count}" tweets="{$tweet-count}" retweets="{$retweet-count}" favorites="{$favorite-count}" iso-date="{$date}">{
				if ($total-count eq $date-max) then attribute {'is-max'} {'true'} else (), $date
			}</tw:published>
	}</time-facet>
	<users-facet total="{fn:count(cts:element-attribute-values(xs:QName("tw:from"), xs:QName("id"), (), $values-options, cts:and-query(($parsed-query, $tweet-query))))}">{
		(
			for $user in cts:element-attribute-values(xs:QName("tw:from"), xs:QName("id"), (), $values-options, cts:and-query(($parsed-query, $tweet-query)))[1 to $max]
			let $tweet-count :=
					cts:frequency($user)
			let $retweet-count :=
				tw:count-docs(
					cts:and-query((
						$parsed-query,
						$retweet-query,
						cts:element-attribute-value-query(
							xs:QName("tw:from"),
							xs:QName("id"),
							$user,
							'exact'
						)
					))
				)
			let $favorite-count :=
				tw:count-docs(
					cts:and-query((
						$parsed-query,
						$favorite-query,
						cts:element-attribute-value-query(
							xs:QName("tw:from"),
							xs:QName("id"),
							$user,
							'exact'
						)
					))
				)
			let $count :=
				$tweet-count + $retweet-count + $favorite-count
			order by $tweet-count descending, $favorite-count descending, $retweet-count descending, $user
			return
				<tw:user id="{$user}" count="{$count}" tweets="{$tweet-count}" retweets="{$retweet-count}" favorites="{$favorite-count}">@{$user}</tw:user>
		)[1 to $max]
	}</users-facet>
	<tweets-facet total="{fn:count(cts:element-attribute-values(xs:QName("tw:text"), xs:QName("org"), (), $values-options, cts:and-query(($parsed-query, $tweet-query))))}">{
		for $subject in cts:element-attribute-values(xs:QName("tw:text"), xs:QName("org"), (), $values-options, cts:and-query(($parsed-query, cts:or-query(($retweet-query, $favorite-query)))))[1 to $max]
		let $t :=
			cts:search(
				fn:doc(),
				cts:and-query((
					$parsed-query,
					$tweet-query,
					cts:element-attribute-value-query(
						xs:QName("tw:text"),
						xs:QName("org"),
						$subject,
						'exact'
					)
				))
			)[1]/*
		let $t :=
			if (fn:empty($t)) then
				cts:search(
					fn:doc(),
					cts:and-query((
						$parsed-query,
						cts:or-query(($retweet-query, $favorite-query)),
						cts:element-attribute-value-query(
							xs:QName("tw:text"),
							xs:QName("org"),
							$subject,
							'exact'
						)
					))
				)[1]/*
			else
				$t
		let $retweet-count :=
			cts:frequency($subject)
		order by $retweet-count descending, $t/tw:from/@id, $subject
		return
			<tweet retweets="{$retweet-count}">{$t/@*, $t/node()}</tweet>
	}</tweets-facet>
	<urls-facet total="{fn:count(cts:element-attribute-values(xs:QName("tw:url"), xs:QName("full"), (), $values-options, $parsed-query))}">{
		$urls-facet
	}</urls-facet>
	<tags-facet total="{fn:count(cts:element-attribute-values(xs:QName("tw:tag"), xs:QName("id"), (), $values-options, $parsed-query))}">{
		$tags-facet
	}</tags-facet>
	<mentions-facet total="{fn:count(cts:element-attribute-values(xs:QName("tw:user"), xs:QName("id"), (), $values-options, $parsed-query))}">{
		$mentions-facet
	}</mentions-facet>
	<contributors-facet total="{fn:count(cts:element-attribute-values(xs:QName("tw:from"), xs:QName("id"), (), $values-options, $parsed-query))}">{
	(
		let $top-tags := $tags-facet[1 to 5]/@id
		let $top-urls := $urls-facet[1 to 5]/@full
		let $users :=
			cts:element-attribute-values(
				xs:QName("tw:from"),
				xs:QName("id"),
				(),
				$values-options,
				cts:and-query((
					$parsed-query,
					cts:or-query((
						cts:element-attribute-value-query(
							xs:QName("tw:tag"),
							xs:QName("id"),
							$top-tags,
							"exact"
						),
						cts:element-attribute-value-query(
							xs:QName("tw:url"),
							xs:QName("full"),
							$top-urls,
							"exact"
						)
					))
				))
			)[1 to (5 * $max)]
		for $user in $users
		let $from-q :=
			cts:element-attribute-value-query(
				xs:QName("tw:from"),
				xs:QName("id"),
				$user,
				'exact'
			)
		let $tweet-count :=
			tw:count-docs(
				cts:and-query((
					$tweet-query,
					$from-q
				))
			)
		let $retweet-count :=
			tw:count-docs(
				cts:and-query((
					$retweet-query,
					$from-q
				))
			)
		let $favorite-count :=
			tw:count-docs(
				cts:and-query((
					$favorite-query,
					$from-q
				))
			)
		let $count := $tweet-count + $retweet-count + $favorite-count
		order by $tweet-count descending, $favorite-count descending, $retweet-count descending, $user
		return
			<tw:user id="{$user}" count="{$count}" tweets="{$tweet-count}" retweets="{$retweet-count}" favorites="{$favorite-count}">@{$user}</tw:user>
	)[1 to $max]
	}</contributors-facet>
	{
		tw:get-words-facet($parsed-query, $max, $domain-query, $threshold, $language)/*
	}
</facets>
};

declare variable $domain-excludes-cache := map:map();

declare function tw:get-domain-excludes($domain-query, $threshold, $language) {
	let $key := fn:concat(xdmp:quote($domain-query), '-', $threshold, '-', $language)
	let $map := map:get($domain-excludes-cache, $key)
	return
		if (fn:exists($map)) then
			$map
		else
			let $get := (
				let $domain-count :=
					fn:count(cts:element-values(xs:QName("tw:n-gram1"), (), $words-options, $domain-query))
				let $excludes :=
					if (fn:exists($domain-query)) then
						for $v in cts:element-values(xs:QName("tw:n-gram1"), (), $words-options, $domain-query)[1 to 250]
						where (cts:frequency($v) * 100 div $domain-count) gt $threshold
						return $v
					else ()
				for $e in $excludes
				return cts:stem($e, $language)
			)
			let $set :=
				map:put($domain-excludes-cache, $key, $get)
			return
				$get
	
};

declare function tw:get-words-facet($parsed-query, $max, $domain-query, $threshold, $language) {
<facets>
	{
		let $excludes :=
			tw:get-domain-excludes($domain-query, $threshold, $language)
		return (

			<excludes>{ for $e in $excludes where fn:string-length($e) > 2 return <exclude>{$e}</exclude> }</excludes>,
				
			<words-facet total="{fn:count(cts:element-values(xs:QName("tw:n-gram1"), (), $words-options, $parsed-query))}">{
				let $word-facets :=
					(
						let $n-grams := (
							cts:element-values(xs:QName("tw:n-gram1"), (), $words-options, $parsed-query)[1 to (15 * $max)],
							cts:element-values(xs:QName("tw:n-gram2"), (), $words-options, $parsed-query)[1 to (15 * $max)],
							cts:element-values(xs:QName("tw:n-gram3"), (), $words-options, $parsed-query)[1 to (15 * $max)]
						)
						for $n-gram in $n-grams
						let $count := cts:frequency($n-gram)
						let $tokens := fn:tokenize($n-gram, '\s+')
						let $n := fn:count($tokens)
						let $tokens := $tokens[fn:string-length(.) > 2][fn:not(cts:stem(., $language) = $excludes)]
						let $n_ := fn:count($tokens)
						let $score := $n_ * $n_ * $count
						order by $score descending
						return
							element {xs:QName(fn:concat("tw:n-gram", $n))} {
								<dummy id="{$n-gram}" score="{$score}" count="{$count}" n="{$n}"/>/@*,
								$n-gram
							}
					)[1 to 5 * $max]
				return
				(
					for $w in $word-facets
					where fn:count($word-facets[fn:contains(., $w)]) = 1
					return
						$w
				)[1 to $max]
			}</words-facet>
		)
	}
</facets>
};

(:
declare variable $url-lookup :=
	if ($enable-uri-resolving) then
		let $map := fn:doc("/url-lookup.xml")/*/map:map(.)
		return
			if (fn:empty($map)) then
				map:map(xdmp:document-get(tw:get-modules-path("url-lookup.xml"))/*)
			else $map
	else ();
:)
declare variable $new-lookup := map:map();

declare function tw:resolve-url(
	$short-url as xs:string
)
	as xs:string?
{
	tw:resolve-url($short-url, 1, ())
};

declare function tw:resolve-url(
	$short-url as xs:string,
	$follows as xs:integer,
	$intermediate-urls as xs:string*
)
	as xs:string?
{
	if ($enable-uri-resolving) then
		let $url := tw:get-full-url($short-url)
		let $url := if (fn:empty($url)) then map:get($new-lookup, $short-url) else $url
		return
			if (fn:exists($url)) then
				$url
			else if (fn:not($enable-online)) then
				(: Bummer, not found in cache, and not allowed to search online :)
				()
			else
				let $log := xdmp:log(fn:concat("Resolving ", $short-url, " .."))
				let $response := try {
					xdmp:http-get($short-url, <options xmlns="xdmp:http"><timeout>5</timeout></options>)
				} catch ($e) { if ($debug) then xdmp:log($e) else (), $e }
				(:
				let $log := xdmp:log($response[1])
				:)
				let $location := $response[1]//*:location/text()
				return
					if (fn:exists($response/self::*:error)) then
						(: fail :)
						let $log := xdmp:log(fn:concat("Resolving ", $short-url, " failed with exception ", $response[1]/*:code/fn:data(.), " ", $response[1]/*:message/fn:data(.), ".."))
						return
							()
					else if ($response[1]/http:code ge 400) then
						(: error response :)
						let $log := xdmp:log(fn:concat("Resolving ", $short-url, " failed with response ", $response[1]/*:code/fn:data(.), " ", $response[1]/*:message/fn:data(.), ".."))
						return
							()
					else if (fn:exists($location)) then
						(: a redirect! :)
						let $url := fn:resolve-uri($location, $short-url)
						return
							if ($follows le $max-resolve-follows) then
								let $log := xdmp:log(fn:concat("Following link #", $follows+1, ", from ", $short-url, " to ", $url, ".."))
								return
									tw:resolve-url($url, $follows + 1, ($intermediate-urls, $short-url))
							else
								let $log := xdmp:log("Too many redirect, not following again..")
								(: Might be final target, but unchecked. Return current url. :)
								return $url
					else
						(: Final target found! :)
						let $log := xdmp:log(fn:concat("Resolved ", $short-url, ".."))
						let $puts :=
							for $intermediate in ($intermediate-urls, $short-url)
							let $log := xdmp:log(fn:concat("Resolved ", $intermediate, " to ", $short-url, ".."))
							return (
								(: map:put($url-lookup, $intermediate, $short-url), :)
								tw:add-url-to-cache($intermediate, $short-url)
							)
						return
							$short-url
	else
		(: Bummer, resolving has been disabled entirely :)
		()
};

declare function tw:add-url-to-cache($short as xs:string, $long as xs:string) {
	if (map:get($new-lookup, $short)) then ()
	else (
		xdmp:log(fn:concat("Caching url ", $short, " as ", $long)),
		map:put($new-lookup, $short, $long)
	)
};

declare function tw:store-url-cache() {
	tw:store-url-lookups($new-lookup)
};

declare function tw:load-url-lookups($path as xs:string) {
	let $map := map:map(xdmp:document-get(tw:get-modules-path($path))/*)
	return
		tw:store-url-lookups($map)
};

declare function tw:store-url-lookups($map as map:map) {
	for $short-url in map:keys($map)
	let $full-url := map:get($map, $short-url)
	where fn:not(tw:exists-url-lookup($short-url))
	return
		tw:add-url-lookup($short-url, $full-url)
};

declare function tw:save-url-lookups($path as xs:string) {
	let $map := map:map()
	let $put := (
		for $short-url in cts:element-attribute-values(xs:QName("tw:url-lookup"), xs:QName("short"), (), ("collation=http://marklogic.com/collation/"), cts:collection-query("url-lookup"))
		let $full-url := tw:get-full-url($short-url)
		return map:put($map, $short-url, $full-url)
	)
	return
		xdmp:save(tw:get-modules-path($path), document { $map })
};

declare function tw:get-full-url($short-url as xs:string) {
	cts:element-attribute-values(xs:QName("tw:url-lookup"), xs:QName("full"), (), ("limit=1","collation=http://marklogic.com/collation/"), cts:and-query((cts:collection-query("url-lookup"), cts:element-attribute-value-query(xs:QName("tw:url-lookup"), xs:QName("short"), $short-url, "exact"))))
};

declare function tw:get-long-url($short-url as xs:string) {
	cts:element-attribute-values(xs:QName("tw:url-lookup"), xs:QName("long"), (), ("limit=1","collation=http://marklogic.com/collation/"), cts:and-query((cts:collection-query("url-lookup"), cts:element-attribute-value-query(xs:QName("tw:url-lookup"), xs:QName("short"), $short-url, "exact"))))
};

declare function tw:get-url-lookup-uri($short-url as xs:string) {
	fn:concat("/url-lookup/", fn:encode-for-uri($short-url), ".xml")
};

declare function tw:exists-url-lookup($short-url as xs:string) {
	let $uri := tw:get-url-lookup-uri($short-url)
	return
		cts:uris($uri, "limit=1", cts:collection-query("url-lookup")) = $uri
};

declare function tw:add-url-lookup($short-url as xs:string, $full-url as xs:string) {
	tw:add-url-lookup($short-url, $full-url, fn:false(), ())
};

declare function tw:add-url-lookup($short-url as xs:string, $full-url as xs:string, $overwrite as xs:boolean, $status as xs:string?) {
	if ($overwrite or fn:not(tw:exists-url-lookup($short-url))) then
		let $long-url := if (fn:contains($full-url, '?')) then fn:substring-before($full-url, '?') else $full-url
		let $uri := tw:get-url-lookup-uri($short-url)
		let $log := xdmp:log(fn:concat("Adding url-lookup ", $full-url))
		return
			xdmp:document-insert($uri, <tw:url-lookup short="{$short-url}" long="{$long-url}" full="{$full-url}" status="{$status}"/>, xdmp:default-permissions(), "url-lookup")
	else ()
};

declare function tw:delete-url-lookup($short-url as xs:string) {
	if (tw:exists-url-lookup($short-url)) then
		let $uri := tw:get-url-lookup-uri($short-url)
		let $log := xdmp:log(fn:concat("Deleting url-lookup ", $short-url))
		return
			xdmp:document-delete($uri)
	else ()
};

declare function tw:search-url-lookups($q as xs:string*, $start as xs:integer?, $size as xs:integer?)
	as xs:string*
{
	let $start := ($start, 1)[1]
	let $size := ($size, 100)[1]
	let $end := $start + $size - 1
	let $q := cts:and-query(($q, cts:collection-query("url-lookup")))
	return (
		cts:uris((), "document", $q)
	)[$start to $end]
};

declare function tw:check-urls() {
	let $transaction-size := 100
	
	let $total := xdmp:estimate(fn:collection("url-lookup"))
	let $nr-transactions := fn:ceiling($total div $transaction-size)
	let $log := xdmp:log(fn:concat("Spawning ", $nr-transactions, " check-url tasks.."))
	
	let $nr-transactions := 2
	
	for $t in (1 to $nr-transactions)
	let $start := $t * ($transaction-size - 1) + 1
	let $end := $t * $transaction-size
	let $uris := tw:search-url-lookups((), $start, $transaction-size)
	let $urls := tw:get-url-full($uris)
	
	let $args := map:map()
	let $put := map:put($args, "urls", $urls)
	return
		xdmp:spawn("check-urls.xqy", (xs:QName("args"), $args))
};

declare function tw:check-url($url as xs:string)
	as item()*
{
	(: find any lookup pointing to this url :)
	let $uris := cts:uris((), "document", cts:and-query((cts:element-attribute-value-query(xs:QName("tw:url-lookup"), xs:QName("full"), $url), cts:collection-query("url-lookup"))))
	
	(: check url :)
	let $url :=
		if (fn:starts-with($url, '/')) then
			fn:resolve-uri(fn:substring($url, 2), tw:get-url-short($uris[1]))
		else $url
	let $status := tw:check-url-status($url)
	let $log-status := fn:string-join(for $s in $status return fn:string($s), " ")
	
	return

	(: check status of each related lookup :)
	for $uri in $uris
	let $org-short := tw:get-url-short($uri)
	let $org-status := tw:get-url-status($uri)
	let $log := xdmp:log(fn:concat("Checking ", $org-short, " status ", $org-status, ": ", $url, " status ", $log-status))
	return
		if (fn:not(fn:string($org-status) = fn:string($status[1])) or (($status instance of xs:integer) and (($status ge 300 and $status lt 400) or ($status ge 500)))) then
			if (fn:not($status[1] instance of xs:integer) or (($status ge 300 and $status lt 400) or ($status ge 500))) then
				(: re-resolve.. :)
				let $org-full := tw:get-url-full($uri)
				let $new-full := tw:resolve-url($url)
				return
					if (fn:exists($new-full)) then
						let $new-status := tw:check-url-status($new-full)
						let $log := xdmp:log(fn:concat("Re-resolved ", $url, ", status changed from ", $org-status, " to ", $log-status))
						return
							tw:add-url-lookup($org-short, $new-full, fn:true(), fn:string($new-status[1]))
					else
						let $log := xdmp:log(fn:concat("Re-resolving ", $url, " failed, updating status.."))
						return
							tw:add-url-lookup($org-short, $url, fn:true(), fn:string($status[1]))

			(: just update status :)
			else if ($org-short = $url) then
				let $log := xdmp:log(fn:concat("False lookup ", $url, ", removing.."))
				return
					tw:delete-url-lookup($org-short)
			else
				let $log := xdmp:log(fn:concat("Updating status of ", $url, " from ", $org-status, " to ", $log-status))
				return
					tw:add-url-lookup($org-short, $url, fn:true(), fn:string($status[1]))
		else if (fn:not($status[1] instance of xs:integer) or ($status ge 300)) then
			xdmp:log(fn:concat("Url ", $url, " for lookup ", $org-short, " still fails: ", $log-status, ".."))
		else if ($debug) then
			xdmp:log(fn:concat("Nothing changed for ", $org-short, ", ", $url, " with status ", $org-status, ", ", $log-status, ".."))
		else ()
};

declare function tw:check-url-status($url as xs:string)
	as item()*
{
	let $response := try { xdmp:http-head($url, <options xmlns="xdmp:http"><timeout>5</timeout></options>) } catch ($e) { $e }

	let $log := if ($debug) then xdmp:log($response) else ()

	return ($response/*:code/fn:data(.), $response/*:message/fn:data(.), $response//http:location/fn:data(.))
};

declare function tw:get-url-short($uris as xs:string*) {
	cts:element-attribute-values(xs:QName("tw:url-lookup"), xs:QName("short"), (), ("collation=http://marklogic.com/collation/"), cts:document-query($uris))
};

declare function tw:get-url-full($uris as xs:string*) {
	cts:element-attribute-values(xs:QName("tw:url-lookup"), xs:QName("full"), (), ("collation=http://marklogic.com/collation/"), cts:document-query($uris))
};

declare function tw:get-url-status($uris as xs:string*) {
	cts:element-attribute-values(xs:QName("tw:url-lookup"), xs:QName("status"), (), ("collation=http://marklogic.com/collation/"), cts:document-query($uris))
};

declare function tw:get-modules-path($path) {
	fn:resolve-uri($path, fn:resolve-uri(fn:substring-after(fn:replace(xdmp:get-request-path(), 'qconsole/endpoints/', ''), "/"), xdmp:modules-root()))
};

declare function tw:sec-to-time($sec) {
	let $h := fn:floor($sec div 3600)
	let $m := fn:floor(($sec mod 3600) div 60)
	let $s := $sec mod 60
	let $time := fn:concat(fn:format-number($h,'00'),':',fn:format-number($m,'00'),':',fn:format-number($s,'00'))
	return
		xs:time($time)
};
