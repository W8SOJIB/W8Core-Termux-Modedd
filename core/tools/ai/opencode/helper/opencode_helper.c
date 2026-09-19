#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <sys/stat.h>

int main(int argc, char** argv) {
    // 1. Clear conflicting Android Bionic preloads and search paths
    unsetenv("LD_PRELOAD");
    unsetenv("LD_LIBRARY_PATH");

    // 2. Dynamically resolve PREFIX and HOME
    const char* env_prefix = getenv("PREFIX");
    char prefix[PATH_MAX];
    if (env_prefix && strlen(env_prefix) > 0) {
        snprintf(prefix, sizeof(prefix), "%s", env_prefix);
    } else {
        snprintf(prefix, sizeof(prefix), "/data/data/com.termux/files/usr");
    }

    const char* env_home = getenv("HOME");
    char home[PATH_MAX];
    if (env_home && strlen(env_home) > 0) {
        snprintf(home, sizeof(home), "%s", env_home);
    } else {
        snprintf(home, sizeof(home), "/data/data/com.termux/files/home");
    }

    // 3. Set dynamic Go resolver and SSL configurations for Termux environment
    setenv("GODEBUG", "netdns=cgo", 1);

    char cert_path[PATH_MAX];
    snprintf(cert_path, sizeof(cert_path), "%s/etc/tls/cert.pem", prefix);
    if (access(cert_path, R_OK) != 0) {
        snprintf(cert_path, sizeof(cert_path), "%s/etc/ssl/cert.pem", prefix);
    }
    if (access(cert_path, R_OK) == 0) {
        setenv("SSL_CERT_FILE", cert_path, 1);
        setenv("NODE_EXTRA_CA_CERTS", cert_path, 1);
    }

    char cert_dir[PATH_MAX];
    snprintf(cert_dir, sizeof(cert_dir), "%s/etc/tls", prefix);
    if (access(cert_dir, R_OK) == 0) {
        setenv("SSL_CERT_DIR", cert_dir, 1);
    }

    // 4. Runtime environment optimizations
    if (!getenv("TERM")) {
        setenv("TERM", "xterm-256color", 1);
    }

    // Ensure TMPDIR points to a valid writable directory for OpenCode
    if (!getenv("TMPDIR")) {
        char tmp_path[PATH_MAX];
        snprintf(tmp_path, sizeof(tmp_path), "%s/tmp", prefix);
        mkdir(tmp_path, 0755);
        setenv("TMPDIR", tmp_path, 1);
    }

    // Ensure PATH contains Termux bin directory for child processes
    const char* cur_path = getenv("PATH");
    char new_path[PATH_MAX * 2];
    if (cur_path && strlen(cur_path) > 0) {
        snprintf(new_path, sizeof(new_path), "%s/bin:%s", prefix, cur_path);
    } else {
        snprintf(new_path, sizeof(new_path), "%s/bin:/system/bin:/bin", prefix);
    }
    setenv("PATH", new_path, 1);

    // 5. Architecture-dependent glibc dynamic linker
    char loader[PATH_MAX];
#if defined(__x86_64__)
    snprintf(loader, sizeof(loader), "%s/glibc/lib/ld-linux-x86-64.so.2", prefix);
#elif defined(__aarch64__)
    snprintf(loader, sizeof(loader), "%s/glibc/lib/ld-linux-aarch64.so.1", prefix);
#else
    snprintf(loader, sizeof(loader), "%s/glibc/lib/ld-linux-aarch64.so.1", prefix);
#endif

    // Fallback if loader is not at prefix/glibc/lib
    if (access(loader, F_OK) != 0) {
#if defined(__x86_64__)
        snprintf(loader, sizeof(loader), "/data/data/com.termux/files/usr/glibc/lib/ld-linux-x86-64.so.2");
#else
        snprintf(loader, sizeof(loader), "/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1");
#endif
    }

    // 6. Paths for real binary and glibc libraries
    char real_bin[PATH_MAX];
    snprintf(real_bin, sizeof(real_bin), "%s/.local/share/core-termux-data/opencode/opencode", home);

    char lib_path[PATH_MAX];
    snprintf(lib_path, sizeof(lib_path), "%s/glibc/lib", prefix);

    // 7. Validate binary and glibc loader existence
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

    // 8. Construct argument array for execv (preserves current working directory PWD)
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

    // 9. Execute the glibc loader to run the real binary natively
    execv(loader, new_argv);

    // If execv returns, an error occurred
    perror("execv");
    free(new_argv);
    return 1;
}
