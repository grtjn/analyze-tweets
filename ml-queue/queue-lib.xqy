xquery version "1.0-ml";

module namespace q = "http://grtjn.nl/marklogic/queue";

import module namespace admin = "http://marklogic.com/xdmp/admin" at "/MarkLogic/admin.xqy";

declare namespace ss = "http://marklogic.com/xdmp/status/server";
declare namespace hs = "http://marklogic.com/xdmp/status/host";
declare namespace task = "http://marklogic.com/xdmp/group";

declare option xdmp:mapping "false";

declare variable $q:root-uri := "/tasks/";
declare variable $q:collection := "queue";
declare variable $q:max-prio := 50;
declare variable $q:min-prio := - $q:max-prio;
(:
declare variable $q:cron-lock-uri := fn:resolve-uri("cron-lock.xml", $q:root-uri);
declare variable $q:cron-stop-uri := fn:resolve-uri("cron-stop.xml", $q:root-uri);
declare variable $q:cron-sleep := 15 (: sec :) * 1000 (: ms :);
:)
declare variable $q:cron-sleep-unit := 'minute';
declare variable $q:cron-sleep := 1;

declare function q:purge-queue() {
	xdmp:collection-delete($q:collection)
};

declare function q:flush-task-server()
{
	(: Thnx to Christopher Cieslinski from LDSChurch  for the inspiration.. :)
	
	let $host-id as xs:unsignedLong := xdmp:host()
	let $host-status := xdmp:host-status($host-id)
	let $task-server-id as xs:unsignedLong := $host-status//hs:task-server-id
	let $task-server-status := xdmp:server-status($host-id, $task-server-id)
	
	let $this-request-id as xs:unsignedLong := xdmp:request()

	let $task-ids as xs:unsignedLong* := $task-server-status//ss:request-id[. != $this-request-id]
	let $queue-size as xs:integer := $task-server-status//ss:queue-size
	return (
		if (fn:count($task-ids) gt 1) then
			for $id in $task-ids
			return
				try {
					xdmp:log(fn:concat("Cancelling task ", $id)),
					xdmp:request-cancel($host-id, $task-server-id, $id)
				} catch ($e) {
					xdmp:log(fn:concat("Failed to cancel task ", $id))
				}
		else
			xdmp:log("No tasks to cancel..")
		,
		if ($queue-size gt 1) then (
			xdmp:log("Queue not empty yet, trying again.."),
			xdmp:sleep(1000),
			q:flush-task-server()
		) else
			xdmp:log("Queue empty, done..")
	)      
};

declare function q:get-task-server-threads-available()
	as xs:integer
{
	let $host-id as xs:unsignedLong := xdmp:host()
	let $host-status := xdmp:host-status($host-id)
	let $task-server-id as xs:unsignedLong := $host-status//hs:task-server-id
	let $task-server-status := xdmp:server-status($host-id, $task-server-id)
	let $task-server-threads as xs:integer := $task-server-status//ss:threads
	let $task-server-max-threads as xs:integer := $task-server-status//ss:max-threads
	return
		(:
		fn:floor(($task-server-max-threads - $task-server-threads) div 2)
		:)
		($task-server-max-threads - $task-server-threads)
};

declare function q:get-task-uri($id)
{
	fn:concat($q:root-uri, $id, ".xml")
};

declare function q:get-queued-tasks-count()
	as xs:integer
{
	xdmp:estimate(fn:collection($q:collection))
};

declare function q:create-task($module, $prio as xs:integer?, $params as map:map?)
	as empty-sequence()
{
	let $module := fn:resolve-uri($module, xdmp:get-request-path())
	return
	if (q:module-exists($module)) then
		let $id := xdmp:random()
		let $prio := if (fn:exists($prio)) then $prio else 0
		return
		xdmp:document-insert(q:get-task-uri($id),
			<q:task id="{$id}" created="{fn:current-dateTime()}">
				<q:module>{$module}</q:module>
				<q:prio>{$prio}</q:prio>
				<q:params>{$params}</q:params>
				<q:database>{xdmp:database()}</q:database>
				<q:modules>{xdmp:modules-database()}</q:modules>
				<q:root>{xdmp:modules-root()}</q:root>
			</q:task>,
			xdmp:default-permissions(),
			$q:collection
		)
	else
		fn:error(xs:QName("MODULENOTFOUND"), fn:concat("Module ", $module, " not found in modules-database ", xdmp:modules-database()))
};

declare function q:delete-task($id)
	as empty-sequence()
{
	xdmp:document-delete(q:get-task-uri($id))
};

declare function q:set-task-prio($id, $prio as xs:integer)
	as empty-sequence()
{
	let $prio := fn:max( (fn:min( ($prio, 50) ), -50) )
	return
		xdmp:node-replace(fn:doc(q:get-task-uri($id))/q:task/q:prio, <q:prio>{$prio}</q:prio>)
};

declare function q:exec-task($id)
	as empty-sequence()
{
	let $task := fn:doc(q:get-task-uri($id))/q:task
	let $module := fn:data($task/q:module)
	let $params := map:map($task/q:params/*)
	let $database := (fn:data($task/q:database), xdmp:database())[1]
	let $modules := (fn:data($task/q:modules), xdmp:modules-database())[1]
	let $root := (fn:data($task/q:root), xdmp:modules-root())[1]
	return (
		(: delete immediately :)
		xdmp:eval(fn:concat('
			xdmp:document-delete("', q:get-task-uri($id), '")
		')),
		xdmp:log(fn:concat("Executing ", $root, $module, " from ", if ($modules eq 0) then '(file-sys)' else xdmp:database-name($modules), " using ", xdmp:database-name($database))),
		xdmp:spawn($module, (xs:QName("params"), $params),
			<options xmlns="xdmp:eval">
				<database>{$database}</database>
				<modules>{$modules}</modules>
				<root>{$root}</root>
			</options>
		)
	)
};

declare function q:get-tasks($start, $page-size)
	as document-node()*
{
	let $end := $start + $page-size - 1
	return
	(
		for $task in
			cts:search(fn:collection($q:collection), cts:and-query(()))
		order by $task/q:task/q:prio ascending, xs:dateTime($task/q:task/@created) ascending
		return $task
		
	) [$start to $end]

};

declare function q:module-exists($module)
	as xs:boolean
{
	if (xdmp:modules-database() eq 0) then
		(: check on file-sys :)
		fn:exists(
			xdmp:document-get(
				fn:concat(fn:translate(xdmp:modules-root(), "\", "/"), $module),
				<options xmlns="xdmp:document-get"><format>text</format></options>
			)
		)
	else
		(: check in modules database :)
		xdmp:eval(fn:concat("fn:doc-available('", $module, "')"), (),
			<options xmlns="xdmp:eval">
				<database>{xdmp:modules-database()}</database>
			</options>
		)
};

declare function q:get-request-url()
{
	fn:concat(
		xdmp:get-request-protocol(),
		"://",
		xdmp:get-request-header("Host"),
		xdmp:get-request-url()
	)
};

declare function q:is-cron-active()
	as xs:boolean
{
	(:
	xdmp:eval(fn:concat("fn:doc-available('", $q:cron-lock-uri,"')"))
	:)
	fn:exists(
		let $config := admin:get-configuration()
		let $db := xdmp:database()
		return admin:group-get-scheduled-tasks($config, xdmp:group())[task:task-database eq $db][fn:ends-with(task:task-path, 'queue-cron.xqy')]
	)
};

declare function q:claim-cron-lock()
{
	(:
	xdmp:eval(fn:concat("xdmp:document-insert('", $q:cron-lock-uri,"', <lock/>)"))
	:)
	()
};

declare function q:release-cron-lock()
{
	(:
	xdmp:eval(fn:concat("xdmp:document-delete('", $q:cron-lock-uri, "')"))
	:)
	()
};

declare function q:start-cron($id)
{
	(:
	if (q:should-cron-stop()) then
		q:deactivate-stop-sign()
	else (),
	xdmp:spawn("queue-cron.xqy", (xs:QName("id"), $id))
	:)
	let $config := admin:get-configuration()

	let $task :=
		admin:group-minutely-scheduled-task(
			fn:resolve-uri('queue-cron.xqy', xdmp:get-request-path()),
			xdmp:modules-root(),
			$q:cron-sleep,
			xdmp:database(),
			xdmp:modules-database(),
			xdmp:user(xdmp:get-current-user()),
			()
		)

	let $config := admin:group-add-scheduled-task($config, xdmp:group(), $task)

	return 
		admin:save-configuration-without-restart($config)
};

declare function q:stop-cron()
{
	(:
	q:activate-stop-sign()
	:)
	let $config := admin:get-configuration()

	let $db := xdmp:database()
	let $task :=
		admin:group-get-scheduled-tasks($config, xdmp:group())[task:task-database eq $db][fn:ends-with(task:task-path, 'queue-cron.xqy')]

	let $config := admin:group-delete-scheduled-task($config, xdmp:group(), $task)

	where fn:exists($task)
	return 
		admin:save-configuration-without-restart($config)
};

declare function q:should-cron-stop()
	as xs:boolean
{
	(:
	xdmp:eval(fn:concat("fn:doc-available('", $q:cron-stop-uri,"')"))
	:)
	fn:true()
};

declare function q:activate-stop-sign()
{
	(:
	xdmp:eval(fn:concat("xdmp:document-insert('", $q:cron-stop-uri,"', <stop/>)"))
	:)
	()
};

declare function q:deactivate-stop-sign()
{
	(:
	xdmp:eval(fn:concat("xdmp:document-delete('", $q:cron-stop-uri, "')"))
	:)
	()
};

