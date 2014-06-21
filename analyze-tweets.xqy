xquery version '1.0-ml';

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace atom="http://www.w3.org/2005/Atom";

declare option xdmp:mapping "false";

declare variable $query := fn:normalize-space(xdmp:get-request-field("query", xdmp:get-request-field("amp;query")[1])[1]);
declare variable $mode := xdmp:get-request-field("mode", xdmp:get-request-field("amp;mode", "date-des")[1])[1];
declare variable $filter := xdmp:get-request-field("filter")[1];
declare variable $max := xs:integer((xdmp:get-request-field("max")[. != ''], "5")[1]);
declare variable $page := xs:integer((xdmp:get-request-field("page")[. != ''], "1")[1]);
declare variable $size := xs:integer((xdmp:get-request-field("size")[. != ''], "10")[1]);
declare variable $domain := xdmp:get-request-field("domain", "")[1];
declare variable $threshold := xs:double((xdmp:get-request-field("threshold")[. != ''], "5")[1]);
declare variable $lang := xdmp:get-request-field("lang", "en")[1];

declare variable $text-query := if (fn:contains($query, 'text:')) then fn:replace($query, '^.*\s*(text:"[^"]*").*$', '$1') else ();
declare variable $token-query := if (fn:contains($query, 'token:')) then fn:replace($query, '^.*\s*(token:"[^"]*").*$', '$1') else ();
declare variable $tag-query := if (fn:contains($query, 'tag:')) then fn:replace($query, '^.*\s*(tag:[^\s]+).*$', '$1') else ();
declare variable $mention-query := if (fn:contains($query, 'mention:')) then fn:replace($query, '^.*\s*(mention:[^\s]+).*$', '$1') else ();
declare variable $from-query := if (fn:contains($query, 'from:')) then fn:replace($query, '^.*\s*(from:[^\s]+).*$', '$1') else ();
declare variable $date-query := if (fn:contains($query, 'date:')) then fn:replace($query, '^.*\s*(date:[^\s]+).*$', '$1') else ();
declare variable $other-query := fn:replace(fn:replace(fn:replace(fn:replace(fn:replace(fn:replace($query, '\s*tag:[^\s]+', ''), '\s*mention:[^\s]+', ''), '\s*from:[^\s]+', ''), '\s*date:[^\s]+', ''), '\s*(text:"[^"]*")', ''), '\s*(token:"[^"]*")', '');

declare variable $no-text-query := fn:replace($query, '\s*text:"[^"]*"', '');
declare variable $no-token-query := fn:replace($query, '\s*token:"[^"]*"', '');
declare variable $no-tag-query := fn:replace($query, '\s*tag:[^\s]+', '');
declare variable $no-mention-query := fn:replace($query, '\s*mention:[^\s]+', '');
declare variable $no-from-query := fn:replace($query, '\s*from:[^\s]+', '');
declare variable $no-date-query := fn:replace($query, '\s*date:[^\s]+', '');
declare variable $no-other-query := fn:string-join(($tag-query, $mention-query, $from-query, $date-query, $text-query, $token-query), ' ');

declare function local:message-to-html(
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
			return <a href="?query={fn:encode-for-uri(fn:concat($no-tag-query, ' tag:', $n/@id))}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}">{$n/node()}</a>
		case element(tw:user)
			return
				if (fn:exists($n/ancestor::atom:entry)) then
					<a href="?query={fn:encode-for-uri(fn:concat(fn:replace($no-from-query, ' mention:[^\s]+', ''), ' from:', $n/@id, ' mention:', $n/../../tw:from/@id))}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}">{$n/node()}</a>
				else
					<a href="?query={fn:encode-for-uri(fn:concat($no-mention-query, ' mention:', $n/@id))}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}">{$n/node()}</a>
		case element(tw:from)
			return
				if (fn:exists($n/ancestor::atom:entry)) then
					<a href="?query={fn:encode-for-uri(fn:concat($no-mention-query, ' mention:', $n/@id))}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}">{$n/node()}</a>
				else
					<a href="?query={fn:encode-for-uri(fn:concat($no-from-query, ' from:', $n/@id))}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}">@{$n/node()}</a>
		case element(tw:published)
			return <a href="?query={fn:encode-for-uri(fn:concat($no-date-query, ' date:', fn:replace($n/@iso-date, '^(\d+)-(\d+)-(\d+).*$', '$1$2$3')))}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}">{fn:replace(fn:translate($n/node(), 'TZ', ' '), '[\+\-]\d+:\d+$', '')}</a>
		case element(tw:n-gram)
			return <a href="?query={fn:encode-for-uri(fn:concat($no-token-query, ' token:"', $n, '"'))}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}">"{$n/node()}"</a>
		case element()
			return local:message-to-html($n/node())
		default
			return $n
};

declare function local:begin-caps(
	$str as xs:string
)
	as xs:string
{
	fn:concat(fn:upper-case(fn:substring($str, 1, 1)), fn:substring($str, 2))
};

xdmp:set-response-content-type("text/html"),

let $q := tw:parse-query($query, $tw:feeds-collection)
let $q :=
	if ($filter != '') then
		cts:and-query(($q,
			cts:element-attribute-value-query(
				(xs:QName("atom:entry"), xs:QName("status")),
				xs:QName("tw:class"),
				$filter,
				'exact'
			)
		))
	else
		$q
let $basic-stats := tw:get-basic-stats($q)
let $facets := tw:get-facets($q, $max, tw:parse-query($domain, $tw:feeds-collection), $threshold, $lang)
let $max-page := fn:ceiling(fn:number($basic-stats/total-tweets) div $size)
let $page-range := 5
return
<html>
<head>
	<script type="text/javascript" src="js/tweets.js"><!-- --></script>
	<link rel="stylesheet" type="text/css" href="styles/tweets.css"/>
</head>

<body onLoad="javascript: onLoad()">

<div id="sidepanel">
<div id="stats">
<div class="title">Stats</div>
<ul class="stats">
<li><label>Start:</label><span>{local:message-to-html($basic-stats/oldest-tweet/tw:published)}</span></li>
<li><label>By:</label><span>{local:message-to-html($basic-stats/oldest-tweet/tw:from)}</span></li>
<li><label>End:</label><span>{local:message-to-html($basic-stats/newest-tweet/tw:published)}</span></li>
<li><label>By:</label><span>{local:message-to-html($basic-stats/newest-tweet/tw:from)}</span></li>
<li><label>Duration:</label><span>{fn:replace(fn:replace(fn:replace(fn:replace(fn:translate($basic-stats/duration, 'PT', ''), 'D', ' days, '), 'H', ' hours, '), 'M', ' min, '), 'S', ' sec')}</span></li>
<li><label>Total:</label><span>{$basic-stats/total-tweets/text()}</span></li>
<!--li><label>Tweets:</label><span>{$basic-stats/nr-tweets/text()}</span></li>
<li><label>Retweets:</label><span>{$basic-stats/nr-retweets/text()}</span></li-->
{
	for $type in $basic-stats/types/*
	return
		<li><label>{local:begin-caps(fn:substring-after(fn:local-name($type), 'nr-'))}:</label><span>{$type/text()}</span></li>
}
</ul>
</div>

<div id="query">
<div class="title">Query</div>
<ul class="remove">
{ if (fn:string-length($other-query) > 0) then
<li><a href="?query={fn:encode-for-uri($no-other-query)}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}&amp;max={$max}">{$other-query}</a></li>
else ()}
{ if (fn:string-length($tag-query) > 0) then
<li><a href="?query={fn:encode-for-uri($no-tag-query)}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}&amp;max={$max}">{$tag-query}</a></li>
else ()}
{ if (fn:string-length($mention-query) > 0) then
<li><a href="?query={fn:encode-for-uri($no-mention-query)}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}&amp;max={$max}">{$mention-query}</a></li>
else ()}
{ if (fn:string-length($from-query) > 0) then
<li><a href="?query={fn:encode-for-uri($no-from-query)}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}&amp;max={$max}">{$from-query}</a></li>
else ()}
{ if (fn:string-length($date-query) > 0) then
<li><a href="?query={fn:encode-for-uri($no-date-query)}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}&amp;max={$max}">{$date-query}</a></li>
else ()}
{ if (fn:string-length($token-query) > 0) then
<li><a href="?query={fn:encode-for-uri($no-token-query)}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}&amp;max={$max}">{$token-query}</a></li>
else ()}
{ if (fn:string-length($text-query) > 0) then
<li><a href="?query={fn:encode-for-uri($no-text-query)}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}&amp;max={$max}">{$text-query}</a></li>
else ()}
</ul>
<br/>
<form action="?">
<input type="hidden" name="mode" value="{$mode}"/>
<input type="hidden" name="filter" value="{$filter}"/>
<input type="hidden" name="page" value="{$page}"/>
<input type="hidden" name="size" value="{$size}"/>
<label for="query">Query:</label>
<input class="inputtext" type="text" name="query" value="{$query}"/><br/>
<label for="threshold">Threshold:</label>
<input class="inputtext" type="text" name="threshold" value="{$threshold}"/><br/>
<label for="lang">Language:</label>
<input class="inputtext" type="text" name="lang" value="{$lang}"/><br/>
<label for="domain">Domain:</label>
<input class="inputtext" type="text" name="domain" value="{$domain}"/><br/>
<label for="max">Max:</label>
<select name="max">{
	for $o in (3 to 15)
	return
		<option value="{$o}">{if ($o eq $max) then attribute selected {'selected'} else (), $o}</option>
}</select><br/>
<label for="mode">Type:</label>
<select name="filter">{
	for $v in ('all', for $i in cts:element-attribute-values(xs:QName("atom:entry"), xs:QName("tw:class"), ()) order by $i return $i)
	return
		<option value="{if ($v eq 'all') then '' else $v}">{if ($v eq $filter) then attribute selected {'selected'} else (), $v}</option>
}</select><br/>
<input type="submit" value="Search"/>
</form>
</div>

<div id="time">
<div class="title">Time <span class="smaller">({fn:data($facets/time-facet/@total)}x)</span></div>
<ul><li>Max: {local:message-to-html($facets/time-facet/*[@is-max eq 'true'])} ({fn:data($facets/time-facet/@max)}x)</li></ul>
<div id="dates">
<object id="dateschild" width="100%" height="200" type="application/x-shockwave-flash" name="dateschild" data="js/dates.swf?{xdmp:random()}" style="visibility: visible;">
<param name="bgcolor" value="#ffffff"/>
<param name="quality" value="high"/>
<param name="wmode" value="transparent"/>
<param name="flashvars" value="dateChangeCallback=setDateRange&amp;loadCallback=graphLoaded&amp;xml_file={fn:encode-for-uri(fn:concat('dates.xqy?query=', fn:encode-for-uri($query)))}"/>
</object>
</div>
<!--ol>{
	for $value in $facets/time-facet/*
	(: where $value/@count > 0 :)
	return
		<li>{if (fn:exists($value/@is-max)) then attribute {'class'} {'max'} else ()}{local:message-to-html($value)} ({data($value/@count)}x)</li>
}</ol-->
</div>

<div id="words">
<div class="title">Words <span class="smaller">({fn:data($facets/words-facet/@total)}x)</span></div>
<div id="excludes">Stop words: { string-join($facets/excludes/exclude, ", ") } ({count($facets/excludes/exclude)}x)</div>
<ol>{
	for $value in $facets/words-facet/*
	return
		<li>{local:message-to-html($value)} (score: {data($value/@score)}, {data($value/@count)}x, {round(100 * $value/@count div $basic-stats/total-tweets)}%)</li>
}</ol>
</div>

<div id="tweets">
<div class="title">Tweets <span class="smaller">({fn:data($facets/tweets-facet/@total)}x)</span></div>
<ol>{
	for $value in $facets/tweets-facet/*
	where $value/@retweets > 0
	return
		<li>@{data($value/tw:from/@id)}: {local:message-to-html($value/tw:text/node())} (<a href='?query={fn:encode-for-uri($no-text-query)}%20text%3A%22{fn:encode-for-uri($value/tw:text/@org)}%22&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}&amp;size={$size}&amp;max={$max}'>RT/FV {data($value/@retweets)}x)</a></li>
}</ol>
</div>

<div id="tweeps">
<div class="title">Tweeps <span class="smaller">({fn:data($facets/users-facet/@total)}x)</span></div>
<ol>{
	for $value in $facets/users-facet/*
	where $value/@count > 0
	return
		<li>{local:message-to-html($value)} ({data($value/@tweets)}x, FV {data($value/@favorites)}x, RT {data($value/@retweets)}x)</li>
}</ol>
</div>

<div id="tags">
<div class="title">Tags <span class="smaller">({fn:data($facets/tags-facet/@total)}x)</span></div>
<ol>{
	for $value in $facets/tags-facet/*
	(: where $value/@count > 0 :)
	return
		<li>{local:message-to-html($value)} (from: {data($value/@senders)}, {data($value/@tweets)}x, FV {data($value/@favorites)}x, RT {data($value/@retweets)}x)</li>
}</ol>
</div>

<div id="mentions">
<div class="title">Mentions <span class="smaller">({fn:data($facets/mentions-facet/@total)}x)</span></div>
<ol>{
	for $value in $facets/mentions-facet/*
	(: where $value/@count > 0 :)
	return
		<li>{local:message-to-html($value)} (from: {data($value/@senders)}, {data($value/@tweets)}x, FV {data($value/@favorites)}x, RT {data($value/@retweets)}x)</li>
}</ol>
</div>

<div id="contribs">
<div class="title">Contribs <span class="smaller">({fn:data($facets/contributors-facet/@total)}x)</span></div>
<ol>{
	for $value in $facets/contributors-facet/*
	(: where $value/@count > 0 :)
	return
		<li>{local:message-to-html($value)} ({data($value/@tweets)}x, FV {data($value/@favorites)}x, RT {data($value/@retweets)}x)</li>
}</ol>
</div>

<div id="urls">
<div class="title">Urls <span class="smaller">({fn:data($facets/urls-facet/@total)}x)</span></div>
<ol>{
	for $value in $facets/urls-facet/*
	(: where $value/@count > 0 :)
	return
		<li>{local:message-to-html($value)} (from: {data($value/@senders)}, {data($value/@tweets)}x, FV {data($value/@favorites)}x, RT {data($value/@retweets)}x)
		{ (:
		  if ($show-images and (starts-with($value, 'http://twitpic.com/') or starts-with($value, 'http://yfrog.com/'))) then
			<div style="float: right;"><iframe src="{$value}" width="650px" height="750px">&#160;</iframe></div>
		  else ()
		  :)
		}
		</li>
}</ol>
</div>
</div><!-- /sidepanel -->

<div id="mainpanel">
<div id="all-tweets">
<div class="title">{if (fn:false() and $mode ne '') then local:begin-caps($mode) else 'Timeline'}&#32;<span class="smaller">({fn:data($basic-stats/total-tweets)}x)</span></div>
<form action="?" name="sizeform" id="sizeform">
<input type="hidden" name="mode" value="{$mode}"/>
<input type="hidden" name="filter" value="{$filter}"/>
<input type="hidden" name="query" value="{$query}"/>
<input type="hidden" name="max" value="{$max}"/>
<input type="hidden" name="page" value="{$page}"/>
<label for="size">Page size:</label>
<select onChange="sizeform.submit()" name="size">{
	for $v in (5, 10, 15, 20, 30, 40, 50, 75, 100, 150, 200, 500)
	return
		<option value="{$v}">{if ($v eq $size) then attribute selected {'selected'} else (), $v}</option>
}</select>
</form>
<form action="?" name="sortform" id="sortform">
<input type="hidden" name="size" value="{$size}"/>
<input type="hidden" name="filter" value="{$filter}"/>
<input type="hidden" name="query" value="{$query}"/>
<input type="hidden" name="max" value="{$max}"/>
<input type="hidden" name="page" value="{$page}"/>
<label for="mode">Order by:</label>
<select onChange="sortform.submit()" name="mode">{
	for $o in ('date', 'text', 'from', 'mention', 'tag', 'user')
	for $a in ('asc', 'des')
	let $v := fn:concat($o, '-', $a)
	let $l := fn:concat($o, ' ', if ($a eq 'asc') then '&#9650;' else '&#9660;')
	return
		<option value="{$v}">{if ($v eq $mode) then attribute selected {'selected'} else (), $l}</option>
}</select>
</form>
<!--ul class="modes">
<li><a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode=timeline&amp;filter={$filter}">timeline</a></li>
<li><a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode=timeline&amp;filter=tweet">tweets</a></li>
<li><a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode=timeline&amp;filter=retweet">retweets</a></li>
<li><a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode=threads&amp;filter={$filter}">threads</a></li>
<li><a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode=by-user&amp;filter={$filter}">by user</a></li>
<li><a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode=by-url&amp;filter={$filter}">by url</a></li>
<li><a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode=by-tag&amp;filter={$filter}">by tag</a></li>
</ul-->
<a name="tweets"><a/></a>
{
let $page-nav :=
	<div class="pagenav">
		{ if ($page - $page-range gt 1) then
			<a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode={$mode}&amp;filter={$filter}&amp;page=1">|&lt;</a>
		else () }
		{ if ($page - $page-range ge 1) then
			<a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page - $page-range}">&lt;&lt;</a>
		else () }
		{ for $p in (2 to ($page-range - 1))
		  let $page := $page - $p
		  where $page ge 1
		  order by $p descending
		  return
			<a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}">{$page}</a>
		}
		{ if ($page gt 1) then
			<a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page - 1}">&lt;</a>
		else () }

		<a>[{$page} of {$max-page}]</a>

		{ if ($page lt $max-page) then
			<a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page + 1}">&gt;</a>
		else () }
		{ for $p in (2 to ($page-range - 1))
		  let $page := $page + $p
		  where $page le $max-page
		  order by $p ascending
		  return
			<a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page}">{$page}</a>
		}
		{ if ($page + $page-range le $max-page) then
			<a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$page + $page-range}">&gt;&gt;</a>
		else () }
		{ if ($page + $page-range lt $max-page) then
			<a href="?query={$query}&amp;max={$max}&amp;size={$size}&amp;mode={$mode}&amp;filter={$filter}&amp;page={$max-page}">&gt;|</a>
		else () }
	</div>
return ($page-nav,
if (fn:true() or $mode eq 'timeline') then
	<ul class="tweets">
	<!--table>
	<tr>
	<th>Type</th>
	<th>From</th>
	<th>Subject</th>
	<th>Stamp</th>
	</tr-->
	{
		let $start := ($page - 1) * $size + 1
		let $end := $page * $size
		let $tweets :=
			if ($mode eq 'date-des') then
				(
					for $t in cts:search(doc(), $q)
					order by xs:dateTime($t/tw:published/@iso-date) descending
					return $t
				)[$start to $end]
			else
			if ($mode eq 'date-asc') then
				(
					for $t in cts:search(doc(), $q)
					order by xs:dateTime($t/tw:published/@iso-date) ascending
					return $t
				)[$start to $end]
			else
			if ($mode eq 'text-asc') then
				(
					for $t in cts:search(doc(), $q)
					order by $t/tw:text/@org ascending
					return $t
				)[$start to $end]
			else
			if ($mode eq 'text-des') then
				(
					for $t in cts:search(doc(), $q)
					order by $t/tw:text/@org descending
					return $t
				)[$start to $end]
			else
			if ($mode eq 'from-asc') then
				(
					for $t in cts:search(doc(), $q)
					order by $t/tw:from/@id ascending
					return $t
				)[$start to $end]
			else
			if ($mode eq 'from-des') then
				(
					for $t in cts:search(doc(), $q)
					order by $t/tw:from/@id descending
					return $t
				)[$start to $end]
			else
			if ($mode eq 'mention-asc') then
				(
					for $t in cts:search(doc(), $q)
					order by $t/tw:text/tw:user[1]/@id ascending
					return $t
				)[$start to $end]
			else
			if ($mode eq 'mention-des') then
				(
					for $t in cts:search(doc(), $q)
					order by $t/tw:text/tw:user[1]/@id descending
					return $t
				)[$start to $end]
			else
			if ($mode eq 'tag-asc') then
				(
					for $t in cts:search(doc(), $q)
					order by $t/tw:text/tw:tag[1]/@id ascending
					return $t
				)[$start to $end]
			else
			if ($mode eq 'tag-des') then
				(
					for $t in cts:search(doc(), $q)
					order by $t/tw:text/tw:tag[1]/@id descending
					return $t
				)[$start to $end]
			else
			if ($mode eq 'url-asc') then
				(
					for $t in cts:search(doc(), $q)
					order by $t/tw:text/tw:url[1]/@full ascending
					return $t
				)[$start to $end]
			else
				(
					for $t in cts:search(doc(), $q)
					order by $t/tw:text/tw:url[1]/@full descending
					return $t
				)[$start to $end]
		for $t at $x in $tweets
		let $t := $t/*
		return
			(:
			<tr><td>{fn:data($t/@tw:class)}</td><td>{local:message-to-html($t/tw:from)}</td><td>{local:message-to-html($t/tw:text/node())}</td><td nowrap="true">{local:message-to-html($t/tw:published)}</td></tr>
			:)
			<li class="{if ($x = 1) then 'first' else ()}&#32;{if (($x mod 2) = 0) then 'even' else 'odd'}">
				<a href='?query={$query} text:"{fn:encode-for-uri($t/tw:text/@org)}"&amp;max={$max}&amp;size={$size}&amp;mode={$mode}&amp;filter={$filter}'>
					<div class="twclass tw{fn:data($t/@tw:class)}">&#32;{(:fn:upper-case(fn:substring($t/@tw:class, 1, 2)):)}</div>
				</a>
				<div class="tw">
					<span class="twfrom">{local:message-to-html($t/tw:from)}</span>
					<span class="twpublished">{local:message-to-html($t/tw:published)}&#32;<a href="{tw:get-feed-uri($t)}" target="_blank">&#x279a;</a></span>
					<span class="twtext">{local:message-to-html($t/tw:text/node())}</span>
				</div>
			</li>
	}
	<!--/table-->
	</ul>
else if ($mode eq 'threads') then
	<table>
	<tr>
	<th>Type</th>
	<th>From</th>
	<th>Subject</th>
	<th>Stamp</th>
	</tr>
	{
		for $t in
				cts:search(doc(), $q)[1 to 200]
		let $subject := string-join($t/tw:text/node(), '')
		return (
			<tr><td class="separator" colspan="5"><a/></td></tr>,
			<tr><td>{local-name($t)}</td><td>{$t/tw:from/node()}</td><td>{local:message-to-html($t/tw:text/node())}</td><td>{$t/tw:published/node()}</td></tr>,
			for $r at $pos in
				(: $retweets[tw:text/@org = $subject] :)
				cts:search(doc(), cts:and-query(($q, $tw:retweet-query, cts:element-attribute-value-query(xs:QName("tw:text"), xs:QName("org"), $subject, "exact"))))
			return
				<tr class="indent"><td>{local-name($r)}</td><td>{$r/tw:from/node()}</td><td>{local:message-to-html($r/tw:text/node())}</td><td>{$r/tw:published/node()}</td></tr>
		)
	}
	</table>
(:
else if ($mode eq 'by-user') then
	<table>
	<tr>
	<th>User</th>
	<th>Type</th>
	<th>From</th>
	<th>Subject</th>
	<th>Stamp</th>
	</tr>
	{
			for $user in distinct-values(($users, $mentions))
			for $t at $pos in $all-tweets[from[@id = $user] or tw:text/tw:user[@id = $user] or string-join(for $i in tw:text/tw:user/@id order by $i return $i, "+") = $user]
			order by $user
			return (
				if ($pos eq 1) then
					<tr><td class="separator" colspan="5"><a/></td></tr>
				else (),
				<tr><td>{if ($pos eq 1) then $user else ()}</td><td>{local-name($t)}</td><td>{$t/tw:from/node()}</td><td>{local:message-to-html($t/tw:text/node())}</td><td>{$t/tw:published/node()}</td></tr>
			)
	}
	</table>
else if ($mode eq 'by-url') then
	<table>
	<tr>
	<th>Url</th>
	<th>Type</th>
	<th>From</th>
	<th>Subject</th>
	<th>Stamp</th>
	</tr>
	{
			for $url in $urls-facet
			for $t at $pos in $all-tweets[tw:text/tw:url[@full = $url/@full]]
			return (
				if ($pos eq 1) then
					<tr><td class="separator" colspan="5"><a/></td></tr>
				else (),
				<tr><td>{if ($pos eq 1) then $url/@full/data(.) else ()}</td><td>{local-name($t)}</td><td>{$t/tw:from/node()}</td><td>{local:message-to-html($t/tw:text/node())}</td><td>{$t/tw:published/node()}</td></tr>
			)
	}
	</table>
else if ($mode eq 'by-tag') then
	<table>
	<tr>
	<th>Tag</th>
	<th>Type</th>
	<th>From</th>
	<th>Subject</th>
	<th>Stamp</th>
	</tr>
	{
			for $tag in $tags
			for $t at $pos in $all-tweets[tw:text/tw:tag[@id = $tag] or string-join(for $i in tw:text/tw:tag/@id[. != 'mluc11'] order by $i return $i, "+") = $tag]
			return (
				if ($pos eq 1) then
					<tr><td class="separator" colspan="5"><a/></td></tr>
				else (),
				<tr><td>{if ($pos eq 1) then $tag else ()}</td><td>{local-name($t)}</td><td>{$t/tw:from/node()}</td><td>{local:message-to-html($t/tw:text/node())}</td><td>{$t/tw:published/node()}</td></tr>
			)
	}
	</table>
:)
else (
<p>Click one of the links above to get the tweet overview...</p>
),
$page-nav
)

}
</div>
</div>

<div id="foot">
<p>{xdmp:elapsed-time()}</p>
<div style="display:none">{
$tw:new-lookup
}</div>
</div>
</body>
</html>
