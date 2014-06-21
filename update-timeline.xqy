xquery version "1.0-ml";

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace atom="http://www.w3.org/2005/Atom";

declare variable $user as xs:string external;
declare variable $vars as map:map external;

declare variable $overwrite as xs:boolean? := map:get($vars, "overwrite");
declare variable $base-url as xs:string? := map:get($vars, "base-url");
declare variable $params as element()? := map:get($vars, "params");
declare variable $recurse as xs:integer? := map:get($vars, "recurse");
declare variable $retry as xs:integer? := map:get($vars, "retry");

tw:update-timeline($user, $overwrite, $base-url, $params, $recurse, $retry),

tw:store-url-cache(),

xdmp:log(fn:concat("Done updating ", $user, " timeline.."))
