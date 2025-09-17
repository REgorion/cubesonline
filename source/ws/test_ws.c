#include "ws_wrapper.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void on_open() {
    printf("[C] Connected!\n");
}

static void on_message(const char *msg, int len) {
    printf("[C] Got message: %.*s\n", len, msg);
}

static void on_close() {
    printf("[C] Connection closed\n");
}

static void on_error(const char *err) {
    printf("[C] Error: %s\n", err);
}

int main() {
    ws_callbacks cb = {
        .on_open = on_open,
        .on_message = on_message,
        .on_close = on_close,
        .on_error = on_error
    };

    // подключаемся к echo серверу
    ws_client *client = ws_connect("wss://echo.websocket.org", cb);
    if (!client) {
        printf("Failed to create client\n");
        return 1;
    }

    // небольшой цикл событий
    for (int i = 0; i < 200; i++) {
        ws_poll(client);

        if (i == 50) {
            const char *msg = "Hello from C client!";
            printf("[C] Sending: %s\n", msg);
            ws_send(client, msg, (int)strlen(msg));
        }

        usleep(50 * 1000); // 50ms
    }

    ws_close(client);
    return 0;
}