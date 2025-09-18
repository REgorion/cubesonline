package server_source

import ws "ws_server"
import "core:time"
import "core:fmt"
import "base:runtime"
import log "core:log"

cb : ws.ws_server_callbacks
server : ^ws.ws_server
custom_context : runtime.Context

main :: proc() {
    custom_context = context
    
    cb.on_open = on_open
    cb.on_close = on_close
    cb.on_message = on_message
    server = ws.ws_server_start(1227, cb)
    
    for true {
        
        time.sleep(50 * time.Millisecond)
    }
}

on_open :: proc "c" (conn: ^ws.ws_client_conn) {
    context = custom_context
    
    fmt.println("Open")
}

on_close :: proc "c" (conn: ^ws.ws_client_conn) {
    context = custom_context
    fmt.println("Close")
}

on_message :: proc "c" (conn: ^ws.ws_client_conn, data: [^]u8, len: i32) {
    context = custom_context
    fmt.printfln("Got new message: %X", data[0:len])
    ws.ws_server_send(conn, data, len)
}