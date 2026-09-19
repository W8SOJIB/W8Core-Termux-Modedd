#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>

int main(int argc, char** argv) {
    // 1. Clear conflicting Android Bionic preloads and search paths
    unsetenv("LD_PRELOAD");
    unsetenv("LD_LIBRARY_PATH");

    // 2. Set dynamic Go resolver and SSL configurations for Termux environment
    setenv("GODEBUG", "netdns=cgo", 1);
    setenv("SSL_CERT_FILE", "/data/data/com.termux/files/usr/etc/tls/cert.pem", 1);
    setenv("NODE_EXTRA_CA_CERTS", "/data/data/com.termux/files/usr/etc/tls/cert.pem", 1);

    // 3. Architecture-dependent glibc dynamic linker
#if defined(__x86_64__)
    char* loader = "/data/data/com.termux/files/usr/glibc/lib/ld-linux-x86-64.so.2";
#elif defined(__aarch64__)
    char* loader = "/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1";
#else
    char* loader = "/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1";
#endif

    // 4. Construct paths for the glibc loader and the real binary
    char* home = getenv("HOME");
    char real_bin[PATH_MAX];
    if (home && strlen(home) > 0) {
        snprintf(real_bin, sizeof(real_bin), "%s/.local/share/core-termux-data/opencode/opencode", home);
    } else {
        snprintf(real_bin, sizeof(real_bin), "/data/data/com.termux/files/home/.local/share/core-termux-data/opencode/opencode");
    }
    char lib_path[] = "/data/data/com.termux/files/usr/glibc/lib";

    // 5. Validate binary and glibc loader existence
    if (access(real_bin, F_OK) != 0) {
        fprintf(stderr, "\033[0;31m✖ OpenCode binary not found at %s\033[0m\n", real_bin);
        fprintf(stderr, "Please run: \033[0;36mcore reinstall ai --opencode\033[0m\n");
        return 1;
    }

    if (access(loader, F_OK) != 0) {
        fprintf(stderr, "\033[0;31m✖ glibc loader not found at %s\033[0m\n", loader);
        fprintf(stderr, "Please install glibc: \033[0;36mpkg install glibc\033[0m\n");
        return 1;
    }

    // 6. Construct argument array for execv
    // Format: [loader, --library-path, lib_path, real_bin, ...original_args]
    char** new_argv = malloc((argc + 4) * sizeof(char*));
    if (!new_argv) {
        return 1;
    }

    new_argv[0] = loader;
    new_argv[1] = "--library-path";
    new_argv[2] = lib_path;
    new_argv[3] = real_bin;

    for (int i = 1; i < argc; i++) {
        new_argv[i + 3] = argv[i];
    }
    new_argv[argc + 3] = NULL;

    // 7. Execute the glibc loader to run the real binary
    execv(loader, new_argv);

    // If execv returns, an error occurred
    perror("execv");
    free(new_argv);
    return 1;
}
