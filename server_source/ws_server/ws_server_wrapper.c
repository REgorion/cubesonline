#include "ws_server_wrapper.h"
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

struct ws_server {
    struct lws_context *context;
    ws_server_callbacks cb;

    pthread_t thread;
    int running;
    pthread_mutex_t lock;
};

struct ws_client_conn {
    struct lws *wsi;
    struct ws_server *server;
    char *send_buf;
    int send_len;
};

static int callback_ws(struct lws *wsi,
                       enum lws_callback_reasons reason,
                       void *user, void *in, size_t len)
{
    struct ws_client_conn *conn = (struct ws_client_conn *)user;
    struct ws_server *server =
        (struct ws_server *)lws_context_user(lws_get_context(wsi));

    switch (reason) {
        case LWS_CALLBACK_ESTABLISHED:
            conn->wsi = wsi;
            conn->server = server;
            conn->send_buf = NULL;
            conn->send_len = 0;
            if (server->cb.on_client_open)
                server->cb.on_client_open(conn);
            break;

        case LWS_CALLBACK_RECEIVE:
            if (server->cb.on_client_message)
                server->cb.on_client_message(conn, (const char*)in, (int)len);
            break;

        case LWS_CALLBACK_SERVER_WRITEABLE: {
            pthread_mutex_lock(&server->lock);
            if (conn->send_buf) {
                unsigned char buf[LWS_PRE + 4096];
                int n = conn->send_len;
                memcpy(&buf[LWS_PRE], conn->send_buf, n);
                lws_write(wsi, &buf[LWS_PRE], n, LWS_WRITE_TEXT);
                free(conn->send_buf);
                conn->send_buf = NULL;
            }
            pthread_mutex_unlock(&server->lock);
            break;
        }

        case LWS_CALLBACK_CLOSED:
            if (server->cb.on_client_close)
                server->cb.on_client_close(conn);
            break;

        case LWS_CALLBACK_LOCK_POLL:
        case LWS_CALLBACK_UNLOCK_POLL:
        case LWS_CALLBACK_CHANGE_MODE_POLL_FD:
        case LWS_CALLBACK_VHOST_CERT_AGING:
            return 0;

        default:
            break;
    }
    return 0;
}

static struct lws_protocols protocols[] = {
    {
        "ws-protocol",
        callback_ws,
        sizeof(struct ws_client_conn),
        4096,
    },
    { NULL, NULL, 0, 0 }
};

static void *ws_service_thread(void *arg) {
    struct ws_server *server = (struct ws_server*)arg;
    while (server->running) {
        lws_service(server->context, 50);
    }
    return NULL;
}

ws_server* ws_server_start(int port, ws_server_callbacks cb) {
    struct lws_context_creation_info info;
    memset(&info, 0, sizeof info);
    info.port = port;
    info.protocols = protocols;
    info.options = LWS_SERVER_OPTION_DO_SSL_GLOBAL_INIT;

    ws_server *server = calloc(1, sizeof(ws_server));
    server->cb = cb;
    info.user = server;
    pthread_mutex_init(&server->lock, NULL);

    lws_set_log_level(LLL_ERR | LLL_WARN | LLL_NOTICE, NULL);
    server->context = lws_create_context(&info);
    if (!server->context) {
        free(server);
        return NULL;
    }

    server->running = 1;
    pthread_create(&server->thread, NULL, ws_service_thread, server);

    return server;
}

void ws_server_send(ws_client_conn *conn, const char *data, int len) {
    if (!conn || !conn->server) return;
    struct ws_server *server = conn->server;

    pthread_mutex_lock(&server->lock);
    if (!conn->send_buf) {
        conn->send_buf = malloc(len);
        memcpy(conn->send_buf, data, len);
        conn->send_len = len;
        lws_callback_on_writable(conn->wsi);
        lws_cancel_service(server->context);
    }
    pthread_mutex_unlock(&server->lock);
}

void ws_server_stop(ws_server *server) {
    if (!server) return;
    server->running = 0;
    lws_cancel_service(server->context);
    pthread_join(server->thread, NULL);
    lws_context_destroy(server->context);
    pthread_mutex_destroy(&server->lock);
    free(server);
}
