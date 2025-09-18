package ws

#+build linux
import w "../ws_native"

#+build wasm32, wasm64p32
import w "../ws_client_web"

