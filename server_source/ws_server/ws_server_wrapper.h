#pragma once
#include <libwebsockets.h>

#ifdef __cplusplus
extern "C" {
#endif

    struct ws_server;
    struct ws_client_conn;

    typedef struct {
        void (*on_client_open)(struct ws_client_conn *conn);
        void (*on_client_message)(struct ws_client_conn *conn, const char *msg, int len);
        void (*on_client_close)(struct ws_client_conn *conn);
    } ws_server_callbacks;

    typedef struct ws_server ws_server;
    typedef struct ws_client_conn ws_client_conn;

    ws_server* ws_server_start(int port, ws_server_callbacks cb);
    void ws_server_send(ws_client_conn *conn, const char *data, int len);
    void ws_server_stop(ws_server *server);

#ifdef __cplusplus
}
#endif
