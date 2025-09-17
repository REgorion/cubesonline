// ws_wrapper.c
#include "ws_wrapper.h"
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

struct ws_client {
    struct lws_context *context;
    struct lws *wsi;
    ws_callbacks cb;

    // очередь отправки (одно сообщение за раз для простоты)
    char *send_buf;
    int send_len;

    pthread_t thread;
    int running;
    pthread_mutex_t lock;
};

static int callback_ws(struct lws *wsi,
                       enum lws_callback_reasons reason,
                       void *user, void *in, size_t len)
{
    struct ws_client *client =
        (struct ws_client*)lws_context_user(lws_get_context(wsi));
	printf("Callback id: %d\n", reason);
	fflush(stdout);

    switch (reason) {
        case LWS_CALLBACK_CLIENT_ESTABLISHED:
            if (client->cb.on_open) client->cb.on_open();
            break;

        case LWS_CALLBACK_CLIENT_RECEIVE:
            if (client->cb.on_message)
                client->cb.on_message((const char*)in, (int)len);
            break;

        case LWS_CALLBACK_CLIENT_WRITEABLE: {
            pthread_mutex_lock(&client->lock);
            if (client->send_buf) {
                unsigned char buf[LWS_PRE + 4096];
                int n = client->send_len;
                memcpy(&buf[LWS_PRE], client->send_buf, n);
                lws_write(wsi, &buf[LWS_PRE], n, LWS_WRITE_TEXT);
                free(client->send_buf);
                client->send_buf = NULL;
            }
            pthread_mutex_unlock(&client->lock);
            break;
        }

        case LWS_CALLBACK_CLOSED:
            if (client->cb.on_close) client->cb.on_close();
            break;

        case LWS_CALLBACK_CLIENT_CONNECTION_ERROR:
            if (client->cb.on_error) client->cb.on_error("connection error");
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
        0,
        4096,
    },
    { NULL, NULL, 0, 0 } // terminator
};

// поток lws_service
static void *ws_service_thread(void *arg) {
    ws_client *client = (ws_client*)arg;
    while (client->running) {
        lws_service(client->context, 50); // 50мс timeout
    }
    return NULL;
}

ws_client* ws_connect(const char *url, ws_callbacks cb) {
    struct lws_context_creation_info info;
    memset(&info, 0, sizeof info);
    info.port = CONTEXT_PORT_NO_LISTEN;
    info.protocols = protocols;
    info.client_ssl_ca_filepath = "/etc/ssl/certs/ca-certificates.crt";
    info.options = LWS_SERVER_OPTION_DO_SSL_GLOBAL_INIT;

    ws_client *client = calloc(1, sizeof(ws_client));
    client->cb = cb;
    info.user = client;
    pthread_mutex_init(&client->lock, NULL);

    lws_set_log_level(LLL_ERR | LLL_WARN | LLL_NOTICE, NULL);
    client->context = lws_create_context(&info);
    if (!client->context) {
        free(client);
        return NULL;
    }

    // разбор URL
    const char *scheme = strstr(url, "://");
    if (!scheme) return NULL;

    int ssl = 0;
    int port = 80;
    const char *host = scheme + 3;
    const char *path = "/";

    if (strncmp(url, "wss://", 6) == 0) {
        ssl = 1; port = 443;
    } else if (strncmp(url, "ws://", 5) == 0) {
        ssl = 0; port = 80;
    }

    char *hostbuf = strdup(host);
    char *slash = strchr(hostbuf, '/');
    if (slash) {
        *slash = '\0';
        path = slash + 1;
    }

    char *colon = strchr(hostbuf, ':');
    if (colon) {
        *colon = '\0';
        port = atoi(colon + 1);
    }

    struct lws_client_connect_info ccinfo = {0};
    ccinfo.context = client->context;
    ccinfo.address = hostbuf;
    ccinfo.port = port;
    ccinfo.path = path[0] ? path : "/";
    ccinfo.host = hostbuf;
    ccinfo.origin = hostbuf;
    ccinfo.protocol = protocols[0].name;
    if (ssl) {
        ccinfo.ssl_connection = LCCSCF_USE_SSL |
                                LCCSCF_ALLOW_SELFSIGNED |
                                LCCSCF_SKIP_SERVER_CERT_HOSTNAME_CHECK;
    }

    client->wsi = lws_client_connect_via_info(&ccinfo);
    free(hostbuf);

    // запускаем сервисный поток
    client->running = 1;
    pthread_create(&client->thread, NULL, ws_service_thread, client);

    return client;
}

void ws_send(ws_client *client, const char *data, int len) {
    if (!client) return;
    pthread_mutex_lock(&client->lock);
    if (!client->send_buf) {
        client->send_buf = malloc(len);
        memcpy(client->send_buf, data, len);
        client->send_len = len;
        lws_callback_on_writable(client->wsi);
        lws_cancel_service(client->context); // разбудить поток
    }
    pthread_mutex_unlock(&client->lock);
}

void ws_close(ws_client *client) {
    if (!client) return;
    client->running = 0;
    lws_cancel_service(client->context);
    pthread_join(client->thread, NULL);
    lws_context_destroy(client->context);
    pthread_mutex_destroy(&client->lock);
    free(client);
}
