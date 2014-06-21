xquery version "1.0-ml";

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

let $users as xs:string* := ("grtjn")
return
	tw:update-timelines($users, fn:false(), fn:false(), fn:false()),

xdmp:log("Spawned updating timelines..")