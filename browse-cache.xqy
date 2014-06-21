xquery version "1.0-ml";

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace http="xdmp:http";
declare namespace atom="http://www.w3.org/2005/Atom";

declare option xdmp:mapping "false";

declare variable $q := xdmp:get-request-field("q");
declare variable $start := xdmp:get-request-field("start")[1];
declare variable $size := xdmp:get-request-field("size")[1];

declare variable $action := xdmp:get-request-field("action", "")[1];

xdmp:set-response-content-type("text/html"),
<html>
	<body>
		<h1>Url cache</h1>
		<a href="?">refresh</a>
		<a href="?action=check">check statusses</a>
		<div>{
			if ($action = "check") then
				tw:check-urls()
			else ()
		}</div>
		<table>
			<tr>
				<th>Short</th><th>Status</th><th>Full</th>
			</tr>
			{
				for $i in tw:search-url-lookups($q, $start, $size)
				let $short := tw:get-url-short($i)
				let $full := tw:get-url-full($i)
				let $status := tw:get-url-status($i)
				return
					<tr>
						<td><a href="{$short}" target="_blank">{fn:substring($short, 1, 50), if (fn:string-length($short) gt 50) then '..' else ()}</a></td>
						{ (:
						<td nowrap="nowrap">{tw:check-url-status($full)}</td>
						:) }
						<td>{$status}</td>
						<td><a href="{$full}" target="_blank">{$full}</a></td>
					</tr>
			}
		</table>
	</body>
</html>