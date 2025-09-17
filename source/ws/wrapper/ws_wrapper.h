// ws_wrapper.h
#pragma once
#include <libwebsockets.h>

#ifdef __cplusplus
extern "C" {
#endif

    typedef void (*ws_on_open)();
    typedef void (*ws_on_message)(const char *msg, int len);
    typedef void (*ws_on_close)();
    typedef void (*ws_on_error)(const char *err);

    typedef struct {
        ws_on_open    on_open;
        ws_on_message on_message;
        ws_on_close   on_close;
        ws_on_error   on_error;
    } ws_callbacks;

    typedef struct ws_client ws_client;

    ws_client* ws_connect(const char *url, ws_callbacks cb);
    void ws_send(ws_client *client, const char *data, int len);
    void ws_close(ws_client *client);
    void ws_poll(ws_client *client);

#ifdef __cplusplus
}
#endif