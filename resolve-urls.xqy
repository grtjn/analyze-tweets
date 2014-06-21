xquery version "1.0-ml";

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace atom="http://www.w3.org/2005/Atom";

declare variable $count := xdmp:estimate(fn:collection($tw:feeds-collection)//tw:url[@org = @full]);
declare variable $urls := () (: fn:distinct-values((fn:collection($tw:feeds-collection)//tw:url[@org = @full])[1 to 10]/text()) :);
let $log := xdmp:log(fn:concat("Resolving ", $count, " urls..", fn:count($urls)))
let $set := xdmp:set($tw:enable-online, fn:true())

for $url in $urls
let $full-url := tw:resolve-url($url)
where fn:exists($full-url)
return
	tw:add-url-lookup($url, $full-url),

xdmp:log(fn:concat("Done resolving ", $count, " urls..", fn:count($urls)))
