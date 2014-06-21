xquery version '1.0-ml';

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace atom="http://www.w3.org/2005/Atom";

declare option xdmp:mapping "false";

declare variable $query := xdmp:get-request-field("query", xdmp:get-request-field("amp;query"));

declare variable $max := xs:integer((xdmp:get-request-field("max")[. != ''], "10")[1]);

declare variable $no-date-query := fn:replace($query, '\s*date:[^\s]+', '');

let $q := tw:parse-query($query, $tw:feeds-collection)
let $no-date-q := tw:parse-query($no-date-query, $tw:feeds-collection)
let $no-date-stats := tw:get-basic-stats($no-date-q)
let $no-date-facets := tw:get-facets($no-date-q, $max)
let $oldest-date := if (fn:exists($no-date-stats/oldest-tweet/tw:published)) then xs:date(fn:replace($no-date-stats/oldest-tweet/tw:published/@date, '^(\d+)-(\d+)-\d+', '$1-$2-01')) else fn:current-date()
let $newest-date := if (fn:exists($no-date-stats/newest-tweet/tw:published)) then xs:date(fn:replace($no-date-stats/newest-tweet/tw:published/@date, '^(\d+)-(\d+)-\d+', '$1-$2-01')) else fn:current-date()
let $years := fn:year-from-date($newest-date) - fn:year-from-date($oldest-date)
let $months := $years * 12 + fn:month-from-date($newest-date) - fn:month-from-date($oldest-date)

(: small width for beamer presentations :)
let $width := 400
let $height := 100
(: large width normal use :)
let $width := 650
let $height := 100

let $graph :=
	<graph query="{$query}" no-date-query="{$no-date-query}" months="{$months}" oldest-date="{$no-date-stats/oldest-tweet/tw:published/@date}" newest-date="{$no-date-stats/newest-tweet/tw:published/@date}">
		<general_settings bg_color="ffffff" type_graph="v"/>
		<header/>
		<subheader/>
		<legend/>
		<legend_popup font="Verdana" bgcolor="cccccc" font_size="10"/>
		<Xheaders rotate="0" color="000000" size="10" title=" " title_color="000000"/>
		<Yheaders color="000000" size="10" title="Messages per month" title_rotate="90" title_color="000000"/>
		<grid grid_width="{$width}" grid_height="{$height}" grid_color="DBDBDB" grid_alpha="30" grid_thickness="1" bg_color="ffffff" bg_alpha="70" alternate_bg_color="F8F8F8" border_color="000000" border_thickness="1"/>
		<bars view_value="0" width="{ $width idiv ($months + 1) }" space="0" alpha="70" view_double_bar="0" color_double_bar="ffffff" pieces_grow_bar="10"/>{

		for $month in (0 to $months)
		let $value := $oldest-date + xs:yearMonthDuration(fn:concat("P", $month, "M"))
		let $date-q := tw:parse-query(fn:concat($no-date-query, " date:", fn:replace(fn:string($value), '^(\d+)-(\d+).*', '$1$2')), $tw:feeds-collection)
		let $count := tw:count-docs($date-q)
		let $is-selected := fn:exists(cts:element-attribute-values(xs:QName("tw:published"), xs:QName("date"), (), ("limit=10"), cts:and-query(($q, $date-q))))
		return (
			<data value="{$count}" name="{$value}" color="cecef2" selectedColor="3e3ec2" selected="{if ($is-selected) then 1 else 0}"/>
		)
		
	}</graph>
(:
let $log := xdmp:log($graph)
:)
return $graph
