xquery version '1.0-ml';

import module namespace tw="http://grtjn.nl/twitter/utils" at "tweet-utils.xqy";

declare namespace atom="http://www.w3.org/2005/Atom";

declare option xdmp:mapping "false";

declare variable $query := fn:normalize-space(xdmp:get-request-field("query", xdmp:get-request-field("amp;query", "xmlamsterdam OR xmladam OR xmladam13 OR &quot;xml amsterdam&quot;")[1])[1]);

declare function local:message-to-html(
	$message as item()*
)
	as item()*
{
	for $n in $message
	return
		typeswitch ($n)
		case element(tw:url)
			return
				let $long := fn:replace($n/@full, "http[s]?://(www.)?", "")
				let $long := if (fn:string-length($long) gt 33) then fn:concat(fn:substring($long, 33), "…") else $long
				return <a href="{$n/@full}" alt="{$long}" target="_blank">{$long}</a>
		case element(tw:tag)
			return <a href="http://search.twitter.com/search?q=&amp;tag={$n/@id}&amp;lang=all" target="_blank">{$n/node()}</a>
		case element(tw:user)
			return
				<a href="http://twitter.com/{$n/@id}" target="_blank">{$n/node()}</a>
		case element(tw:from)
			return
				<a href="http://twitter.com/{$n/@id}" target="_blank">{$n/node()}</a>
		case element(tw:published)
			return fn:replace(fn:translate($n/node(), 'TZ', ' '), '[\+\-]\d+:\d+$', '')
		case element(tw:n-gram)
			return ()
		case element()
			return local:message-to-html($n/node())
		default
			return $n
};

xdmp:set-response-content-type("text/html"),

let $page := 'Twitterwall'
let $year := '2013'
let $search-q :=
	tw:parse-query($query, $tw:feeds-collection)
let $year-q := (
	cts:element-attribute-range-query(xs:QName("tw:published"), xs:QName("date"), ">=", xs:date(fn:concat($year, "-01-01"))),
	cts:element-attribute-range-query(xs:QName("tw:published"), xs:QName("date"), "&lt;=", xs:date(fn:concat($year, "-12-31")))
)
let $no-retweet-q := 
	cts:not-query(cts:element-attribute-value-query(xs:QName("atom:entry"), xs:QName("tw:class"), ("retweet", "duplicate"), 'exact'))
let $tweets := 
	for $t in cts:search(doc(), cts:and-query(($search-q, $year-q, $no-retweet-q)))/atom:entry
	let $image-link := $t/atom:link[@rel='image']/@href
	where fn:exists($image-link)
	order by xs:dateTime($t/tw:published/@iso-date) descending
	return $t
return
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" version="XHTML+RDFa 1.0" dir="ltr"
  
  xmlns:content="http://purl.org/rss/1.0/modules/content/"
  xmlns:dc="http://purl.org/dc/terms/"
  xmlns:foaf="http://xmlns.com/foaf/0.1/"
  xmlns:og="http://ogp.me/ns#"
  xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"
  xmlns:sioc="http://rdfs.org/sioc/ns#"
  xmlns:sioct="http://rdfs.org/sioc/types#"
  xmlns:skos="http://www.w3.org/2004/02/skos/core#"
  xmlns:xsd="http://www.w3.org/2001/XMLSchema#">
  <head profile="http://www.w3.org/1999/xhtml/vocab">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta content="{$page}" about="/{$year}/{lower-case($page)}" property="dc:title" />
<link rel="shortlink" href="/{$year}/{lower-case($page)}" />
<link rel="canonical" href="/{$year}/{lower-case($page)}" />
<meta name="Generator" content="Drupal 7 (http://drupal.org)" />
    <title>{$page} | XML Amsterdam {$year}</title>
    <style type="text/css" media="all">@import url("http://xmlamsterdam.com/modules/system/system.base.css?msg4pt");
@import url("http://xmlamsterdam.com/modules/system/system.menus.css?msg4pt");
@import url("http://xmlamsterdam.com/modules/system/system.messages.css?msg4pt");
@import url("http://xmlamsterdam.com/modules/system/system.theme.css?msg4pt");</style>
<style type="text/css" media="all">@import url("http://xmlamsterdam.com/modules/aggregator/aggregator.css?msg4pt");
@import url("http://xmlamsterdam.com/modules/field/theme/field.css?msg4pt");
@import url("http://xmlamsterdam.com/modules/node/node.css?msg4pt");
@import url("http://xmlamsterdam.com/sites/all/modules/quiz/quiz.css?msg4pt");
@import url("http://xmlamsterdam.com/modules/search/search.css?msg4pt");
@import url("http://xmlamsterdam.com/sites/all/modules/ubercart/uc_order/uc_order.css?msg4pt");
@import url("http://xmlamsterdam.com/sites/all/modules/ubercart/uc_product/uc_product.css?msg4pt");
@import url("http://xmlamsterdam.com/sites/all/modules/ubercart/uc_store/uc_store.css?msg4pt");
@import url("http://xmlamsterdam.com/modules/user/user.css?msg4pt");
@import url("http://xmlamsterdam.com/sites/all/modules/views/css/views.css?msg4pt");</style>
<style type="text/css" media="all">@import url("http://xmlamsterdam.com/sites/all/modules/ctools/css/ctools.css?msg4pt");</style>
<style type="text/css" media="all">@import url("http://xmlamsterdam.com/sites/default/files/color/busy-0cf1bc6f/style.css?msg4pt");</style>
<style type="text/css" media="print">@import url("http://xmlamsterdam.com/themes/busy/css/print.css?msg4pt");</style>

<!--[if lte IE 8]>
<link type="text/css" rel="stylesheet" href="http://xmlamsterdam.com/themes/busy/css/ie.css?msg4pt" media="all" />
<![endif]-->
    <script type="text/javascript" src="http://xmlamsterdam.com/misc/jquery.js?v=1.4.4"></script>
<script type="text/javascript" src="http://xmlamsterdam.com/misc/jquery.once.js?v=1.2"></script>
<script type="text/javascript" src="http://xmlamsterdam.com/misc/drupal.js?msg4pt"></script>
<script type="text/javascript">
<!--//--><![CDATA[//><!--
jQuery.extend(Drupal.settings, {"basePath":"\/","pathPrefix":"","ajaxPageState":{"theme":"busy","theme_token":"nLfPt-eS1Yw-u_dI6V2LgWLGeeAQeK3cHhx0o_hYOLg","js":{"misc\/jquery.js":1,"misc\/jquery.once.js":1,"misc\/drupal.js":1},"css":{"modules\/system\/system.base.css":1,"modules\/system\/system.menus.css":1,"modules\/system\/system.messages.css":1,"modules\/system\/system.theme.css":1,"modules\/aggregator\/aggregator.css":1,"modules\/field\/theme\/field.css":1,"modules\/node\/node.css":1,"sites\/all\/modules\/quiz\/quiz.css":1,"modules\/search\/search.css":1,"sites\/all\/modules\/ubercart\/uc_order\/uc_order.css":1,"sites\/all\/modules\/ubercart\/uc_product\/uc_product.css":1,"sites\/all\/modules\/ubercart\/uc_store\/uc_store.css":1,"modules\/user\/user.css":1,"sites\/all\/modules\/views\/css\/views.css":1,"sites\/all\/modules\/ctools\/css\/ctools.css":1,"themes\/busy\/css\/style.css":1,"themes\/busy\/css\/print.css":1,"themes\/busy\/css\/ie.css":1}}});
//--><!]]>
</script>
    <link rel="stylesheet" type="text/css" href="http://www.xmlamsterdam.com/styles/jquery.tweet.css"/>
    <link rel="stylesheet" type="text/css" href="http://www.xmlamsterdam.com/styles/xmlamsterdam.css"/>
	<script type="text/javascript" src="http://www.xmlamsterdam.com/styles/jquery.tweet.js"><!-- --></script>
	<script type="text/javascript" src="http://www.xmlamsterdam.com/styles/xmlamsterdam.js"><!-- --></script>
	<meta name="viewport"  content="initial-scale=1, width=device-width"/>
  </head>
  <body class="html not-front not-logged-in one-sidebar sidebar-first page-node page-node- page-node-55 node-type-page" >
    <div id="wrapper">
      <div id="wrapper-inner-top">
        <div id="wrapper-inner-bottom">
          <div id="wrapper-inner-color-bar">
            <div id="wrapper-inner-shadow-over-left">
              <div id="wrapper-inner-shadow-over-right">
                <div id="wrapper-inner-shadow-repeated-left">
                  <div id="wrapper-inner-shadow-top-left">
                    <div id="wrapper-inner-shadow-color-bar-left">
                      <div id="wrapper-inner-shadow-middle-left">       
                        <div id="wrapper-inner-shadow-bottom-left">
                          <div id="wrapper-inner-shadow-repeated-right">
                            <div id="wrapper-inner-shadow-top-right">
                              <div id="wrapper-inner-shadow-color-bar-right">
                                <div id="wrapper-inner-shadow-middle-right">       
                                  <div id="wrapper-inner-shadow-bottom-right">
                                    <div id="skip-link">
                                      <a href="#main-content">Skip to main content</a>
                                    </div>
                                                                            <div id="container">
      <div id="header-wrapper">
        <div id="header-top">
          <div id="logo-floater">
                        <div id="branding" class="clearfix">
              <a href="/" title="XML Amsterdam 2013 Connecting XML developers worldwide">
                                <span class="site-title">XML Amsterdam 2013</span>
              </a>
            </div>
                      </div>
                  </div>
        <div id="header" class="clearfix">
                              <div id="header-right">
            <div id="site-slogan">
              Connecting XML developers worldwide            </div>
                      </div>
                  </div>
      </div>
      <div id="main-wrapper">
        <div id="main" class="clearfix">
          <div id="content" class="has-main-menu">
                        <div id="navigation">
              <div class="section">
                <ul id="main-menu" class="links clearfix"><li class="menu-756 first"><a href="/2013">Home</a></li>
<li class="menu-1029"><a href="/2013/registration">Registration</a></li>
<li class="menu-1032 active-trail active"><a href="/2013/program" class="active-trail active">Program</a></li>
<li class="menu-1033"><a href="/2013/demojam" title="MarkLogic DemoJam">DemoJam</a></li>
<li class="menu-1034"><a href="/2013/sessions">Sessions</a></li>
<li class="menu-1035"><a href="/2013/speakers">Speakers</a></li>
<li class="menu-746"><a href="/twitterwall">Twitterwall</a></li>
<li class="menu-928"><a href="/2013/location">Location</a></li>
<li class="menu-757 last"><a href="/2013/about">About</a></li>
</ul>              </div>
            </div>
                        <div id="content-area">
              <h2 class="element-invisible">You are here</h2><div class="breadcrumb"><a href="/">Home</a></div>                            <a id="main-content"></a>
              
              <div id="tabs-wrapper" class="clearfix">
              
                                                <h1 class="with-tabs">Program</h1>
                                                                                          </div>
             
                                                        <div class="clearfix">
                  <div class="region region-content">
    <div id="block-system-main" class="block block-system">

    
  <div class="content">
    <div id="node-55" class="node node-page clearfix" about="/2013/program" typeof="foaf:Document">

  
      
  
  <div class="content">
    <div class="field field-name-body field-type-text-with-summary field-label-hidden"><div class="field-items"><div class="field-item even" property="content:encoded">
	&#10;&#10;


<div class="paging" id="xmlamsterdamtweets">
{count($tweets)} tweets
<div class="tweet"><ul class="tweet_list">{
for $t at $i in $tweets
let $screen_name := fn:data($t/tw:from/@id)
let $author-uri := fn:data($t/atom:author/atom:uri)
let $author-name := fn:data($t/tw:from)
let $image-link := fn:data($t/atom:link[@rel='image']/@href)
let $link := fn:data($t/atom:link[@rel='alternate']/@href)
let $timestamp := fn:translate($t/tw:published/@iso-date, 'TZ', ' ')
let $tweet := local:message-to-html($t/tw:text/node())
let $org-text := fn:string($t/tw:text/@org)
let $retweet-q :=
	cts:element-attribute-value-query(xs:QName("tw:text"), fn:QName("", "org"), $org-text, 'exact')
let $retweeters := cts:element-attribute-values(xs:QName("tw:from"), fn:QName("", "id"), (), (), $retweet-q)[. != $screen_name]
let $nr-retweets := fn:count($retweeters)
return
<li class="{ if ($i eq 1) then 'tweet_first ' else () }{ if ($i mod 2 eq 0) then 'tweet_even' else 'tweet_odd'}">
	<a href="{$author-uri}" class="tweetlink" target="_blank">
		<img width="40" height="40" border="0" title="{$author-name}" alt="{$author-name}" src="{$image-link}"/>
	</a>
	<span class="tweet_time">
		<a title="view tweet on twitter" href="{$link}" target="_blank" class="tweetlink">{$timestamp}</a>
	</span>
	<span class="tweet_join"><br/></span>
	<span class="tweet_text">{ if ($nr-retweets > 0) then <strong style="font-size: 1{$nr-retweets mod 10}0%;">{$tweet}</strong> else $tweet }{ if ($nr-retweets > 0) then (fn:concat(' (', $nr-retweets, 'x by '), for $from at $x in $retweeters return (<a href="http://twitter.com/{$from}" target="_blank">{$from}</a>, if ($x ne $nr-retweets) then ', ' else ()), ')') else ()}</span>
</li>
}</ul></div>
</div>

		&#10;&#10;<!-- till here -->&#10;&#10;
{ xdmp:elapsed-time() }
	</div></div></div>  </div>

  
  
</div>
  </div>
</div>
  </div>
              </div>
                          </div>
          </div>
                    <div class="sidebar-first sidebar">
              <div class="region region-sidebar-first">
    <div id="block-block-3" class="block block-block">

    
  <div class="content">
    <!-- Highlight:
<h1 style="font-size: 1.8em; padding-top: 5px; width: 70%; text-align: center; color: black; margin-left: 50px; background-color: #EEEEEE; margin-bottom: 30px;"><p><b>Sponsored by <a href="http://www.marklogic.com/" target="_blank"><img width="200" style="vertical-align: middle; margin-top: -11px" src="/images/new-business-marklogic_rgb_72ppi_marklogic.png"/></a></b></h1>
<p>-->
<!-- Sidebar first: --><h1 style="padding-top: 20px; padding-bottom: 10px; width: 100%; text-align: center; color: black; margin: 0px; background-color: #EEEEEE;"><b>Sponsored by<br /><a href="http://www.marklogic.com/" target="_blank"><img width="180" style="vertical-align: middle; margin-top: -11px" src="/images/new-business-marklogic_rgb_72ppi_marklogic.png" /></a></b></h1>
  </div>
</div>
<div id="block-block-4" class="block block-block">

    
  <div class="content">
    <!-- Sidebar first: --><h1 style="padding-top: 20px; padding-bottom: 10px; width: 100%; text-align: center; color: black; margin: 0px; background-color: #EEEEEE;"><b>Sister Events:<br /><br /><a href="http://www.xmlprague.cz" target="_blank"><img src="http://www.xmlprague.cz/wp-content/themes/inline-xmlprg/images/xmlprague-top-logo-13.png" width="210" /></a><br /><br /><a href="http://www.xmllondon.com" target="_blank"><img src="/images/xml-london_small.png" width="140" /></a></b></h1>
  </div>
</div>
  </div>
                      </div>
                  </div>
      </div>
      <div id="page-footer" class="clearfix">
              </div>
    </div>
                                    																		
                                  </div>
                                </div>
                              </div>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
							         <div id="page_postfooter">Built by <a href="http://www.undpaul.de" title="undpaul Drupal development" rel="external">undpaul Drupal development</a></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </body>
</html>