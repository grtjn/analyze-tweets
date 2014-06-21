xquery version "1.0-ml";

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace http="xdmp:http";
declare namespace atom="http://www.w3.org/2005/Atom";

declare option xdmp:mapping "false";

declare variable $args as map:map external;

let $set := xdmp:set($tw:enable-online, fn:true())

let $urls := map:get($args, "urls")

for $url in $urls
return
	tw:check-url($url)
