function getParam ( parameterName ) {
	var queryString = window.location.search;
	var parameterName = parameterName + "=";
	var begin = queryString.indexOf ( parameterName );
	if ( begin != -1 ) {
		begin += parameterName.length;
		var end = queryString.indexOf ( "&" , begin );
		if ( end == -1 ) {
			end = queryString.length
		}
		return unescape ( queryString.substring ( begin, end ) );
	}
	return "";
}
function setDateRange(daterange) {
	var query = getParam("query");
	var mode = getParam("mode");
	var filter = getParam("filter");
	var max = getParam("max");
	var page = getParam("page");
	var size = getParam("size");
	
	query = query.replace(/\s*date:[^\s]+/ig, "");
	
	var href = window.location.pathname + "?query=" + query + " " + daterange + "&mode=" + mode  + "&filter=" + filter + "&max=" + max + "&page=" + page + "&size=" + size + window.location.hash;
	
	//alert(href);
	
	window.location = href;
}
function graphLoaded() {
}
function onLoad() {
}
