#ifndef SCREENGATE_MACBRIDGE_H
#define SCREENGATE_MACBRIDGE_H
#include <stddef.h>
#include <stdint.h>
int sg_listener(void);
int sg_connect(void);
int sg_peer_uid(int fd, unsigned int *uid);
void sg_socket_timeout(int fd, int seconds);
int sg_random(uint8_t *out, size_t count);
int sg_derive(const char *password, size_t length, const uint8_t *salt, size_t salt_length, uint8_t *out);
int sg_screen_active(void);
int sg_console_uid(void);
#endif
