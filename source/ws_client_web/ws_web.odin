#+build wasm32, wasm64p32
package ws_client_web

foreign import lib "ws_client"

ws_on_open :: proc "c" ()
ws_on_message :: proc "c" ([^]u8, i32)
ws_on_close :: proc "c" ()
ws_on_error :: proc "c" ()

ws_callbacks :: struct {
    on_open: ws_on_open,
    on_message: ws_on_message,
    on_close: ws_on_close,
    on_error: ws_on_error,
}

@(default_calling_convention="c", link_prefix="")
foreign lib {
    ws_connect :: proc(url: cstring, url_len: i32, callbacks: ws_callbacks, 
        message_buffer: [^]u8,
        message_buffer_len: i32,
        error_message_buffer: [^]u8,
        error_message_buffer_len: i32)---
    ws_send    :: proc(data: [^]u8, len: i32) ---
    ws_close   :: proc() ---
}