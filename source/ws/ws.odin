package ws

import ws_native "../ws_client_native"
import ws_web "../ws_client_web"

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

when ODIN_OS == .Linux {
    ws_client : ^ws_native.ws_client
}

when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
    on_message_buffer : [4096]u8
    on_error_buffer : [4096]u8
}

ws_connect :: proc(url: cstring, cb: ws_callbacks) {
    when ODIN_OS == .Linux {
        ws_client = ws_native.ws_connect(url, transmute(ws_native.ws_callbacks) cb)
    } else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
        ws_web.ws_connect(
            url, i32(len(url)),
            transmute(ws_web.ws_callbacks) cb,
            transmute([^]u8)&on_message_buffer, i32(len(on_message_buffer)),
            transmute([^]u8)&on_error_buffer, i32(len(on_error_buffer))
        )
    }
}

ws_send :: proc(data: [^]u8, len: i32) {
    when ODIN_OS == .Linux {
        if ws_client != nil {
            ws_native.ws_send(ws_client, data, len)
        }
    } else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
        ws_web.ws_send(data, len)
    }
}

ws_close :: proc() {
    when ODIN_OS == .Linux {
        if ws_client != nil {
            ws_native.ws_close(ws_client)
        }
    } else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
        ws_web.ws_close()
    }
}