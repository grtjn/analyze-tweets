# Analyze Tweets

An application to pull various statistics from a large set of tweets, combined with faceted search, and some helper functionality to 'harvest' new tweets. It runs against the Twitter 1.1 REST api, utilizing the XQuery oauth library by ndw. It is written in XQuery, using MarkLogic specific functionality for searching, and statistics.

## Background

The idea for this application arose at a time I had little opportunity to attend conferences, and wanted to gather summaries from the tweets posted about them. I wrote a bit of code to do some statistics on tweets, then added functionality to pull them in using RSS feeds on Twitter searches. That got replaced later on by REST api calls. In 2010 I visited the XML Prague conference, and entered the MarkLogic DemoJam with this application, as mentioned in my summary of that conference: http://grtjn.blogspot.nl/2012/02/xmlprague-2012-day-one-and-two.html. I improved the application on and off over the past years, but never got around to actually make it public as I originally intended. That is rectified now.

## Access tokens

Twitter API requires access tokens to operate. That also allows controlling the permission levels, and will give you higher rate limits. This application will need read-only access tokens. It takes just a few steps to go through, and you need to do that only once:

* go to apps.twitter.com
* login with your normal Twitter account
* click the Create New App button
* name: Analyze {your twitter name} Tweets (needs to be unique)
* description: Search and analyze your tweets with this tool
* website: https://github.com/grtjn/analyze-tweets
* check the Yes, I agree
* click the Create Your Twitter Application button
* go to API Keys
* click Create my access token
* wait a few seconds, and click Refresh

Keep that page at hand..

## Deploy

Requires MarkLogic 6+

* git clone git@github.com:grtjn/analyze-tweets.git
* create a new Database with MarkLogic App-Services (http://localhost:8000/app-services)
* create a new HTTP app server with the MarkLogic Admin interface (http://localhost:8001)
* point the root to the analyze-tweets folder
* connect it to the database you created with App-Services

## Configure tokens

* edit tweet-utils.xqy, and locate (near the top):

       <oa:authentication>
         <oa:consumer-key><!-- Your Twitter Application API Key --></oa:consumer-key>
         <oa:consumer-key-secret><!-- Your Twitter Application API Secret --></oa:consumer-key-secret>
       </oa:authentication>
       <oa:token><!-- Your Access token for this app --></oa:token>
       <oa:secret><!-- Your Access token secret for this app --></oa:secret>
     </oa:service-provider>

* copy API Key into 'oa:consumer-key'
* copy API Secret into 'oa:consumer-key-secret'
* copy your Access token into 'oa:token'
* copy your Access token secret into 'oa:secret'
* save the file

## Start analyzing

* open the new app server in your favorite browser
* login as admin
* it will report initially that indexes need to be created
* click the button to have them created
* click ok
* enter a search phrase in the first textbox, and click 'Update tweets'
* alternatively enter a Twitter name in the second textbox, and click 'Update timeline'
* click 'Analyze tweets' to open the Analyze tweets dashboard
* have a little patients there, it is doing a lot of calculations

The Twitter search has a limited window. It usually goes back to roughly 3 days maximum. Repeat it once or twice a day to capture more tweets, or use the Update timelines functionality to go back into history. You can also schedule a search with tweets-schedule.xqy.

Be gentle with capturing many timelines, best to call it with one list of ids, watch ErrorLog to follow progress, and only call it again when it is completely done. The code is intelligent enough to interrupt itself if a rate limit gets exceeded, but running parallel processes will only make it fail quicker, you won't get tweets faster..

Have fun!
