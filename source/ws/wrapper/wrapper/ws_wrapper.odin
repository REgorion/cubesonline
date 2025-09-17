// ws_wrapper.h
package wrapper





ws_on_open :: proc "c" (, #c_vararg ..any)

ws_on_message :: proc "c" (cstring, i32)

ws_on_close :: proc "c" (, #c_vararg ..any)

ws_on_error :: proc "c" (cstring)

ws_callbacks :: struct {
	on_open:    ws_on_open,
	on_message: ws_on_message,
	on_close:   ws_on_close,
	on_error:   ws_on_error,
}

@(default_calling_convention="c", link_prefix="")
foreign lib {
	ws_connect :: proc(url: cstring, cb: ws_callbacks) -> ^ws_client ---
	ws_send    :: proc(client: ^ws_client, data: cstring, len: i32) ---
	ws_close   :: proc(client: ^ws_client) ---
	ws_poll    :: proc(client: ^ws_client) ---
}
