package ws

import "core:c"
import "core:fmt"

foreign import lib {
    "ws_wrapper.o",
    "system:websockets",
    "system:ssl",
    "system:crypto",
    "system:z",
    "system:uv",
    "system:dl",
    "system:pthread",
}

ws_client :: struct {
    lws_context: rawptr,
    lws: rawptr,
    ws_callbacks: ^ws_callbacks,
    send_buf: [^]c.char,
    send_len: c.int,
}


ws_on_open :: proc "c" ()
ws_on_message :: proc "c" (cstring, i32)
ws_on_close :: proc "c" ()
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
    //ws_poll    :: proc(client: ^ws_client) ---
}