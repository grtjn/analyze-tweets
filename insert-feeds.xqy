xquery version "1.0-ml";

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace atom="http://www.w3.org/2005/Atom";

declare variable $params as map:map external;
declare variable $map := map:map();

let $feeds as element(atom:entry)* := map:get($params, "feeds")
let $overwrite as xs:boolean  := map:get($params, "overwrite")

let $log := xdmp:log(fn:concat("Inserting ", fn:count($feeds), " feeds.."))

for $feed as element(atom:entry) in $feeds
let $url := tw:get-feed-uri($feed)
return
	if (fn:exists(map:get($map, $url))) then
		xdmp:log(fn:concat("Duplicate feed ", $url, " (", fn:base-uri($feed), ")"))
	else if (fn:not($overwrite) and tw:is-twitter-feed($url)) then
		fn:concat('Skipped existing twitter feed ', $url)
	else if (fn:not($overwrite) and tw:exists-feed($url)) then
		fn:concat('Skipped existing feed ', $url)
	else
		let $put := map:put($map, $url, 1)
		let $feed :=
			tw:enrich-feed($feed)
		return
			($feed, tw:store-feed($url, $feed)),

tw:store-url-cache(),

xdmp:log(fn:concat("Done inserting ", fn:count(map:keys($map)), " feeds.."))
