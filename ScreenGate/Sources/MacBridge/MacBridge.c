#include "MacBridge.h"
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOKitLib.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <Security/SecRandom.h>
#include <CommonCrypto/CommonKeyDerivation.h>
#include <launch.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

int sg_listener(void) {
    int *fds = NULL; size_t count = 0;
    int error = launch_activate_socket("Control", &fds, &count);
    if (error || count != 1) { free(fds); return -1; }
    int fd = fds[0]; free(fds); return fd;
}

int sg_connect(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, "/var/run/com.screengate.control.sock", sizeof(address.sun_path));
    address.sun_len = sizeof(address);
    sg_socket_timeout(fd, 10);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address))) { close(fd); return -1; }
    return fd;
}

void sg_socket_timeout(int fd, int seconds) {
    struct timeval timeout = { seconds, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    int enabled = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled));
}

int sg_peer_uid(int fd, unsigned int *uid) {
    uid_t user; gid_t group;
    if (getpeereid(fd, &user, &group)) return -1;
    *uid = user; return 0;
}

int sg_random(uint8_t *out, size_t count) { return SecRandomCopyBytes(kSecRandomDefault, count, out); }

int sg_derive(const char *password, size_t length, const uint8_t *salt, size_t salt_length, uint8_t *out) {
    return CCKeyDerivationPBKDF(kCCPBKDF2, password, length, salt, salt_length,
                             kCCPRFHmacAlgSHA256, 600000, out, 32);
}

int sg_console_uid(void) {
    uid_t uid = 0; gid_t gid = 0;
    CFStringRef name = SCDynamicStoreCopyConsoleUser(NULL, &uid, &gid);
    if (!name) return -1;
    int logged_in = !CFEqual(name, CFSTR("loginwindow")) && uid >= 501;
    CFRelease(name); return logged_in ? (int)uid : -1;
}

int sg_screen_active(void) {
    if (sg_console_uid() < 0) return 0;
    /* IOConsoleUsers is system-wide, so this also works outside a GUI login session. */
    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    CFTypeRef users = IORegistryEntryCreateCFProperty(root, CFSTR("IOConsoleUsers"), kCFAllocatorDefault, 0);
    IOObjectRelease(root);
    int on_console = 0, locked = 0;
    if (users && CFGetTypeID(users) == CFArrayGetTypeID()) {
        for (CFIndex i = 0; i < CFArrayGetCount(users); i++) {
            CFDictionaryRef user = CFArrayGetValueAtIndex(users, i);
            if (CFGetTypeID(user) != CFDictionaryGetTypeID()) continue;
            if (CFDictionaryGetValue(user, CFSTR("kCGSSessionOnConsoleKey")) == kCFBooleanTrue) {
                on_console = 1;
                locked = CFDictionaryGetValue(user, CFSTR("CGSSessionScreenIsLocked")) == kCFBooleanTrue ||
                         CFDictionaryGetValue(user, CFSTR("kCGSSessionScreenIsLocked")) == kCFBooleanTrue;
            }
        }
    }
    if (users) CFRelease(users);
    /* Use the current-session dictionary as an additional lock check where available. */
    CFDictionaryRef session = CGSessionCopyCurrentDictionary();
    if (session) {
        locked |= CFDictionaryGetValue(session, CFSTR("CGSSessionScreenIsLocked")) == kCFBooleanTrue;
        CFRelease(session);
    }
    if (on_console && locked) return 0;
    if (locked) return 0;
    CGDirectDisplayID displays[32]; uint32_t count = 0;
    if (CGGetOnlineDisplayList(32, displays, &count) != kCGErrorSuccess) return 1;
    for (uint32_t i = 0; i < count; i++) if (!CGDisplayIsAsleep(displays[i])) return 1;
    return 0;
}
