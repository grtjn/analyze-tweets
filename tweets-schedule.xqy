xquery version "1.0-ml";

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace atom="http://www.w3.org/2005/Atom";

let $queries as xs:string* := ("marklogic")
let $set := xdmp:set($tw:enable-online, fn:false())

return tw:update-feeds($queries, fn:false()),

tw:store-url-cache(),

xdmp:log("Done updating feeds..")