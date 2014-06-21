<?xml version="1.0"?>
<xsl:stylesheet version="2.0"
	xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
	xmlns:a="clr-namespace:archivist;assembly=archivist"
	xmlns="http://www.w3.org/2005/Atom"

	exclude-result-prefixes="#all">

	<xsl:output method="xml" encoding="UTF-8" indent="yes" />
	<xsl:strip-space elements="*" />

	<xsl:template match="/">
		<feed>
			<xsl:apply-templates select="//a:Tweet" />
		</feed>
	</xsl:template>
	
	<!--
		<Tweet
			Image="http://a0.twimg.com/profile_images/776634114/frisgroen_hart_normal.jpg"
			TweetID="96200113566916608"
			Status="Inmiddels 12 uur later maar ... @arjanbroer idee voor #dvdd bij #dwdd is wel goed plan! wordt vervolgd .... na de zomervakantie! #woordspel"
			TweetDate="2011-07-27T14:47:49+02:00"
			Username="FRISGROEN"
			TweetStatus="Unapproved"
			BadWord="{x:Null}"/>
	-->
	<!--
		<entry tw:class="tweet" xmlns="http://www.w3.org/2005/Atom" xmlns:tw="http://grtjn.nl/twitter/utils">
			<id>tag:search.twitter.com,2005:109362131081756672</id>

			<published>2011-09-01T20:28:58Z</published>
			<link type="text/html" href="http://twitter.com/glewinglee/statuses/109362131081756672" rel="alternate"/>
			<title>I guess I am becoming the face of Sundog this week http://t.co/wp4pZ6r #df11</title>
			<content type="html">I guess I am becoming the face of Sundog this week &lt;a href="http://t.co/wp4pZ6r"&gt;http://t.co/wp4pZ6r&lt;/a&gt; #&lt;em&gt;df11&lt;/em&gt;</content>

			<updated>2011-09-01T20:28:58Z</updated>
			<link type="image/png" href="http://a2.twimg.com/profile_images/1407309606/26551_10150140607205456_614930455_11745256_943912_n_normal.jpg" rel="image"/>

			<author>
				<name>glewinglee (Greg Ewing-Lee)</name>
				<uri>http://twitter.com/glewinglee</uri>
			</author>
		</entry>
	-->
	<xsl:template match="a:Tweet">
		<xsl:if test="not(preceding-sibling::a:Tweet[position() = (1 to 10)]/@TweetID = @TweetID)">
			<xsl:variable name="date" select="replace(@TweetDate, '(T\d\d:\d\d)\+', '$1:00+')"/>
			<entry xmlns="http://www.w3.org/2005/Atom">
			  <id>tag:search.twitter.com,2005:<xsl:value-of select="@TweetID"/></id>

			  <published><xsl:value-of select="$date"/></published>
			  <link type="text/html" href="http://twitter.com/{lower-case(@Username)}/statuses/{@TweetID}" rel="alternate"/>
			  <title><xsl:value-of select="@Status"/></title>
			  <content type="html"><xsl:value-of select="@Status"/></content>

			  <updated><xsl:value-of select="$date"/></updated>
			  <link type="image/png" href="{@Image}" rel="image"/>

			  <author>
				<name><xsl:value-of select="lower-case(@Username)"/> (<xsl:value-of select="@Username"/>)</name>
				<uri>http://twitter.com/<xsl:value-of select="lower-case(@Username)"/></uri>
			  </author>
			</entry>
		</xsl:if>
	</xsl:template>
	
</xsl:stylesheet>
