xquery version "1.0-ml";

declare variable $url-lookup external;

xdmp:document-insert("/url-lookup.xml", document{ $url-lookup })
