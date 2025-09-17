package ws_server

import "core:c"
import "core:fmt"

foreign import lib {
	"ws_server_wrapper.o",
	"system:websockets",
	"system:ssl",
	"system:crypto",
	"system:z",
	"system:uv",
	"system:dl",
	"system:pthread",
}

ws_on_client_open :: proc "c" (^ws_client_conn)
ws_on_client_message :: proc "c" (^ws_client_conn, cstring, c.int)
ws_on_client_close :: proc "c" (^ws_client_conn)

ws_server_callbacks :: struct {
	on_open:    ws_on_client_open,
	on_message: ws_on_client_message,
	on_close:   ws_on_client_close,
}

ws_server :: struct {
	lws_context: rawptr,
	cb: ws_server_callbacks,
}

ws_client_conn :: struct {
	wsi: rawptr,
	ws_server: ^ws_server,
	send_buf: [^]c.char,
	send_len: c.int,
}

@(default_calling_convention="c", link_prefix="")
foreign lib {
	ws_server_start :: proc(port: i32, cb: ws_server_callbacks) -> ^ws_server ---
	ws_server_send  :: proc(conn: ^ws_client_conn, data: cstring, len: c.int) ---
	ws_server_stop  :: proc(server: ^ws_server) ---
}
