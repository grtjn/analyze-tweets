xquery version "1.0-ml";

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace atom="http://www.w3.org/2005/Atom";

declare variable $params as map:map external;

(:
let $feeds := fn:collection($tw:feeds-collection)[.//tw:url[@org = @full]][1 to 200]
:)

let $feed-uris as xs:string* := map:get($params, "feed-uris")
let $enable-online as xs:boolean := map:get($params, "enable-online")
let $set := xdmp:set($tw:enable-online, $enable-online)

let $log := xdmp:log(fn:concat("Enriching ", fn:count($feed-uris), " feeds", if ($enable-online) then " with online enabled" else (), ".."))

for $feed-uri in $feed-uris
let $log := xdmp:log(fn:concat("Enriching ", $feed-uri, " ", if ($enable-online) then "with online enabled" else (), ".."))
let $feed :=
	tw:enrich-feed(tw:unrich(tw:get-feed($feed-uri)))
return
	tw:store-feed($feed-uri, $feed),

tw:store-url-cache(),

xdmp:log("Done enriching feeds..")