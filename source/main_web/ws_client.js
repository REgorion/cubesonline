var ws_callbacks = {};
var wasmMemory = null;

var msg_ptr = 0;
var msg_max_len = 0;

var err_ptr = 0;
var err_max_len = 0;

function setMemory(memory) {
    wasmMemory = memory;
}

/**
 * Подключение к WebSocket.
 * @param {number} urlPtr - указатель на адрес подключения
 * @param {number} urlLen - длина строки адреса подключения 
 * @param {object} callbacks - объект с коллбэками (on_open, on_message, on_close, on_error)
 * @param {number} msgBufferPtr - указатель на буфер сообщений
 * @param {number} msgBufferLen - макс. длина буфера сообщений
 * @param {number} errBufferPtr - указатель на буфер ошибок
 * @param {number} errBufferLen - макс. длина буфера ошибок
 */
function ws_connect(urlPtr, urlLen, callbacks, msgBufferPtr, msgBufferLen, errBufferPtr, errBufferLen) {
    let url = loadString(urlPtr, urlLen)
    console.log(url)
    ws_callbacks = decode_callbacks(callbacks);

    msg_ptr = msgBufferPtr;
    msg_max_len = msgBufferLen;

    err_ptr = errBufferPtr;
    err_max_len = errBufferLen;

    let ws = new WebSocket(url);

    ws.onopen = () => {
        if (ws_callbacks.on_open) {
            ws_callbacks.on_open();
        }
    };

    ws.onmessage = (evt) => {
        if (ws_callbacks.on_message && wasmMemory) {
            let enc = new TextEncoder();
            let bytes = enc.encode(evt.data);

            let len = Math.min(bytes.length, msg_max_len);
            let dst = new Uint8Array(wasmMemory.buffer, msg_ptr, len);
            dst.set(bytes.subarray(0, len));

           ws_callbacks.on_message(msg_ptr, len);
        }
    };

    ws.onclose = () => {
        if (ws_callbacks.on_close) {
            ws_callbacks.on_close();
        }
    };

    ws.onerror = () => {
        if (ws_callbacks.on_error && wasmMemory) {
            let msg = "ws error";
            let enc = new TextEncoder().encode(msg);

            let len = Math.min(enc.length, err_max_len);
            let dst = new Uint8Array(wasmMemory.buffer, err_ptr, len);
            dst.set(enc.subarray(0, len));

            ws_callbacks.on_error(err_ptr, len);
        }
    };

    return ws;
}

function ws_send(ws, data, len) {
    let bytes = new Uint8Array(wasmMemory.buffer, data, len);
    ws.send(bytes);
}

function ws_close(ws) {
    ws.close();
}

function loadString(ptr, len) {
    let bytes = new Uint8Array(wasmMemory.buffer, ptr, len);
    return new TextDecoder("utf-8").decode(bytes);
}

function decode_callbacks(ptr) {
    // смотрим на память wasm как на Int32Array
    const view = new Int32Array(wasmMemory.buffer, ptr, 4);

    return {
        on_open:    view[0] ? wasmExports.__indirect_function_table.get(view[0]) : null,
        on_message: view[1] ? wasmExports.__indirect_function_table.get(view[1]) : null,
        on_close:   view[2] ? wasmExports.__indirect_function_table.get(view[2]) : null,
        on_error:   view[3] ? wasmExports.__indirect_function_table.get(view[3]) : null,
    };
}
