xquery version "1.0-ml";

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace atom="http://www.w3.org/2005/Atom";

declare variable $vars as map:map external;

declare variable $users as xs:string* := map:get($vars, "users");
declare variable $overwrite as xs:boolean? := map:get($vars, "overwrite");
declare variable $base-url as xs:string? := map:get($vars, "base-url");
declare variable $params as element()? := map:get($vars, "params");
declare variable $recurse as xs:integer? := map:get($vars, "recurse");
declare variable $retry as xs:integer? := map:get($vars, "retry");

let $user := $users[1]
let $_ :=
	xdmp:invoke("update-timeline.xqy", (xs:QName("user"), $user, xs:QName("vars"), $vars))

let $users := $users[. != $user]
let $_ := map:put($vars, "users", $users)
where count($users) > 0
return
	xdmp:spawn("update-timelines.xqy", (xs:QName("vars"), $vars))
