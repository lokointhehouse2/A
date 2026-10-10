/**
 * Controller helpers. Every action returns a response struct that index.cfm renders:
 *   { type:"view", view, layout, data, status } | { type:"json", payload, status } | { type:"redirect", url }
 */
component {

    public any function init( required struct beans ) {
        variables.b = arguments.beans;
        return this;
    }

    private struct function view( required string name, struct data = {}, string layout = "main", numeric status = 200 ) {
        return { type: "view", view: arguments.name, layout: arguments.layout, data: arguments.data, status: arguments.status };
    }

    private struct function ok( any data = {}, struct meta = {} ) {
        return { type: "json", payload: variables.b.json.ok( arguments.data, "", arguments.meta ), status: 200 };
    }

    private struct function created( any data = {} ) {
        return { type: "json", payload: variables.b.json.ok( arguments.data ), status: 201 };
    }

    private struct function redirect( required string url ) {
        return { type: "redirect", url: arguments.url };
    }

    private void function flash( required string type, required string message ) {
        session.flash = { type: arguments.type, message: arguments.message };
    }

    private numeric function limitParam( struct rc, numeric def = 12, numeric max = 50 ) {
        return variables.b.validator.intInRange( arguments.rc.limit ?: "", 1, arguments.max, arguments.def, "limit" );
    }

}
