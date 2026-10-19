// linuxbox — a small Linux userspace for
// the Blacksite console, written in
// plain POSIX C and compiled to
// WebAssembly (wasm32-wasip1) with
// wasi-sdk. One multicall binary, the
// BusyBox pattern: the applet is chosen
// by argv[0], or by argv[1] when invoked
// as linuxbox itself.
//
// Only the surface wasi-libc honestly
// offers is used: stdio, dirent, stat,
// unistd's file calls. No fork, no
// processes, no sockets — the kernel
// owns those, and a guest that asks is
// refused by the substrate, not by
// politeness.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <errno.h>
#include <dirent.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/utsname.h>

extern char **environ;

static const char *applet_names[] = {
    "linuxbox", "ls", "cat", "echo", "pwd",
    "wc", "head", "tail", "true", "false",
    "env", "cp", "mv", "rm", "mkdir",
    "touch", "uname", "grep", "sleep",
    NULL
};

// ---------- shared ----------

static int copy_stream(FILE *in, FILE *out) {
    char buf[8192];
    size_t n;
    while ((n = fread(buf, 1, sizeof buf, in)) > 0) {
        if (fwrite(buf, 1, n, out) != n) return -1;
    }
    return ferror(in) ? -1 : 0;
}

// ---------- applets ----------

static int ap_echo(int argc, char **argv) {
    int newline = 1, i = 1;
    while (i < argc && argv[i][0] == '-' && argv[i][1]) {
        if (strcmp(argv[i], "-n") == 0) { newline = 0; i++; }
        else break;
    }
    for (int first = 1; i < argc; i++, first = 0) {
        if (!first) putchar(' ');
        fputs(argv[i], stdout);
    }
    if (newline) putchar('\n');
    return 0;
}

static int ap_cat(int argc, char **argv) {
    int rc = 0;
    if (argc < 2) {
        return copy_stream(stdin, stdout) ? 1 : 0;
    }
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-") == 0) {
            if (copy_stream(stdin, stdout)) rc = 1;
            continue;
        }
        FILE *f = fopen(argv[i], "rb");
        if (!f) {
            fprintf(stderr, "cat: %s: %s\n",
                    argv[i], strerror(errno));
            rc = 1;
            continue;
        }
        if (copy_stream(f, stdout)) rc = 1;
        fclose(f);
    }
    return rc;
}

static int ap_ls(int argc, char **argv) {
    int longs = 0, all = 0, i = 1;
    while (i < argc && argv[i][0] == '-' && argv[i][1]) {
        for (const char *p = argv[i] + 1; *p; p++) {
            if (*p == 'l') longs = 1;
            if (*p == 'a') all = 1;
        }
        i++;
    }
    const char *path = i < argc ? argv[i] : ".";
    struct stat st;
    if (stat(path, &st) != 0) {
        fprintf(stderr, "ls: %s: %s\n",
                path, strerror(errno));
        return 1;
    }
    if (!S_ISDIR(st.st_mode)) {
        if (longs) printf("%lld  %s\n",
                          (long long)st.st_size, path);
        else printf("%s\n", path);
        return 0;
    }
    DIR *d = opendir(path);
    if (!d) {
        fprintf(stderr, "ls: %s: %s\n",
                path, strerror(errno));
        return 1;
    }
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (!all && e->d_name[0] == '.') continue;
        if (longs) {
            char full[1024];
            snprintf(full, sizeof full, "%s/%s",
                     path, e->d_name);
            struct stat est;
            if (stat(full, &est) == 0) {
                printf("%s %10lld  %s%s\n",
                       S_ISDIR(est.st_mode) ? "dir " : "file",
                       (long long)est.st_size,
                       e->d_name,
                       S_ISDIR(est.st_mode) ? "/" : "");
                continue;
            }
        }
        printf("%s\n", e->d_name);
    }
    closedir(d);
    return 0;
}

static int ap_pwd(int argc, char **argv) {
    (void)argc; (void)argv;
    char buf[1024];
    if (getcwd(buf, sizeof buf)) {
        printf("%s\n", buf);
        return 0;
    }
    fprintf(stderr, "pwd: %s\n", strerror(errno));
    return 1;
}

static int ap_wc(int argc, char **argv) {
    int wl = 0, ww = 0, wc = 0, i = 1;
    while (i < argc && argv[i][0] == '-' && argv[i][1]) {
        for (const char *p = argv[i] + 1; *p; p++) {
            if (*p == 'l') wl = 1;
            if (*p == 'w') ww = 1;
            if (*p == 'c') wc = 1;
        }
        i++;
    }
    if (!wl && !ww && !wc) { wl = ww = wc = 1; }
    FILE *f = stdin;
    const char *name = NULL;
    if (i < argc) {
        f = fopen(argv[i], "rb");
        if (!f) {
            fprintf(stderr, "wc: %s: %s\n",
                    argv[i], strerror(errno));
            return 1;
        }
        name = argv[i];
    }
    long lines = 0, words = 0, bytes = 0;
    int c, inword = 0;
    while ((c = fgetc(f)) != EOF) {
        bytes++;
        if (c == '\n') lines++;
        if (isspace(c)) inword = 0;
        else if (!inword) { inword = 1; words++; }
    }
    if (f != stdin) fclose(f);
    if (wl) printf("%ld ", lines);
    if (ww) printf("%ld ", words);
    if (wc) printf("%ld ", bytes);
    if (name) printf("%s", name);
    printf("\n");
    return 0;
}

static int parse_count(int argc, char **argv,
                       int *i, long dflt, int *bad) {
    *bad = 0;
    if (*i < argc) {
        if (strcmp(argv[*i], "-n") == 0 && *i + 1 < argc) {
            *i += 2;
            return atol(argv[*i - 1]);
        }
        if (argv[*i][0] == '-' && isdigit(argv[*i][1])) {
            int v = atoi(argv[*i] + 1);
            (*i)++;
            return v;
        }
    }
    (void)dflt;
    return dflt;
}

static int ap_headtail(int argc, char **argv, int tail) {
    int i = 1, bad = 0;
    long n = parse_count(argc, argv, &i, 10, &bad);
    FILE *f = stdin;
    if (i < argc) {
        f = fopen(argv[i], "rb");
        if (!f) {
            fprintf(stderr, "%s: %s: %s\n",
                    tail ? "tail" : "head",
                    argv[i], strerror(errno));
            return 1;
        }
    }
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    if (!tail) {
        long shown = 0;
        while (shown < n && (len = getline(&line, &cap, f)) >= 0) {
            fwrite(line, 1, (size_t)len, stdout);
            shown++;
        }
    } else {
        // Ring of the last n lines.
        char **ring = calloc((size_t)(n > 0 ? n : 1), sizeof(char *));
        long total = 0;
        while ((len = getline(&line, &cap, f)) >= 0) {
            free(ring[total % (n > 0 ? n : 1)]);
            ring[total % (n > 0 ? n : 1)] = strdup(line);
            total++;
        }
        long start = total > n ? total - n : 0;
        for (long k = start; k < total; k++) {
            fputs(ring[k % (n > 0 ? n : 1)], stdout);
        }
        for (long k = 0; k < (total < n ? total : n); k++) free(ring[k]);
        free(ring);
    }
    free(line);
    if (f != stdin) fclose(f);
    return 0;
}

static int ap_env(int argc, char **argv) {
    (void)argc; (void)argv;
    for (char **e = environ; e && *e; e++) puts(*e);
    return 0;
}

static int ap_cp(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "cp <from> <to>\n");
        return 1;
    }
    FILE *in = fopen(argv[1], "rb");
    if (!in) {
        fprintf(stderr, "cp: %s: %s\n",
                argv[1], strerror(errno));
        return 1;
    }
    FILE *out = fopen(argv[2], "wb");
    if (!out) {
        fprintf(stderr, "cp: %s: %s\n",
                argv[2], strerror(errno));
        fclose(in);
        return 1;
    }
    int bad = copy_stream(in, out);
    fclose(in);
    if (fclose(out) != 0) bad = -1;
    if (bad) {
        fprintf(stderr, "cp: write failed\n");
        return 1;
    }
    return 0;
}

static void rm_tree(const char *path, int *rc) {
    struct stat st;
    if (stat(path, &st) != 0) {
        fprintf(stderr, "rm: %s: %s\n",
                path, strerror(errno));
        *rc = 1;
        return;
    }
    if (S_ISDIR(st.st_mode)) {
        DIR *d = opendir(path);
        if (d) {
            struct dirent *e;
            while ((e = readdir(d)) != NULL) {
                if (strcmp(e->d_name, ".") == 0 ||
                    strcmp(e->d_name, "..") == 0) continue;
                char full[1024];
                snprintf(full, sizeof full, "%s/%s",
                         path, e->d_name);
                rm_tree(full, rc);
            }
            closedir(d);
        }
        if (rmdir(path) != 0) {
            fprintf(stderr, "rm: %s: %s\n",
                    path, strerror(errno));
            *rc = 1;
        }
    } else if (unlink(path) != 0) {
        fprintf(stderr, "rm: %s: %s\n",
                path, strerror(errno));
        *rc = 1;
    }
}

static int ap_rm(int argc, char **argv) {
    int recursive = 0, i = 1, rc = 0;
    while (i < argc && argv[i][0] == '-' && argv[i][1]) {
        for (const char *p = argv[i] + 1; *p; p++) {
            if (*p == 'r' || *p == 'R') recursive = 1;
        }
        i++;
    }
    if (i >= argc) {
        fprintf(stderr, "rm <path>...\n");
        return 1;
    }
    for (; i < argc; i++) {
        if (recursive) {
            rm_tree(argv[i], &rc);
        } else if (unlink(argv[i]) != 0) {
            if (errno == EISDIR || errno == EPERM) {
                if (rmdir(argv[i]) == 0) continue;
            }
            fprintf(stderr, "rm: %s: %s\n",
                    argv[i], strerror(errno));
            rc = 1;
        }
    }
    return rc;
}

static int ap_mkdir(int argc, char **argv) {
    int parents = 0, i = 1, rc = 0;
    while (i < argc && argv[i][0] == '-' && argv[i][1]) {
        for (const char *p = argv[i] + 1; *p; p++) {
            if (*p == 'p') parents = 1;
        }
        i++;
    }
    if (i >= argc) {
        fprintf(stderr, "mkdir <dir>...\n");
        return 1;
    }
    for (; i < argc; i++) {
        if (parents) {
            char tmp[1024];
            snprintf(tmp, sizeof tmp, "%s", argv[i]);
            for (char *p = tmp + 1; *p; p++) {
                if (*p == '/') {
                    *p = '\0';
                    mkdir(tmp, 0777);
                    *p = '/';
                }
            }
        }
        if (mkdir(argv[i], 0777) != 0 && errno != EEXIST) {
            fprintf(stderr, "mkdir: %s: %s\n",
                    argv[i], strerror(errno));
            rc = 1;
        }
    }
    return rc;
}

static int ap_touch(int argc, char **argv) {
    int rc = 0;
    if (argc < 2) {
        fprintf(stderr, "touch <file>...\n");
        return 1;
    }
    for (int i = 1; i < argc; i++) {
        int fd = open(argv[i], O_WRONLY | O_CREAT, 0666);
        if (fd < 0) {
            fprintf(stderr, "touch: %s: %s\n",
                    argv[i], strerror(errno));
            rc = 1;
            continue;
        }
        close(fd);
        if (utimensat(AT_FDCWD, argv[i], NULL, 0) != 0) {
            // Creation was the point; a
            // substrate without clock-set
            // is not a failure here.
        }
    }
    return rc;
}

static int ap_mv(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "mv <from> <to>\n");
        return 1;
    }
    if (rename(argv[1], argv[2]) != 0) {
        fprintf(stderr, "mv: %s -> %s: %s\n",
                argv[1], argv[2], strerror(errno));
        return 1;
    }
    return 0;
}

static int ap_uname(int argc, char **argv) {
    struct utsname u;
    if (uname(&u) != 0) {
        fprintf(stderr, "uname: %s\n", strerror(errno));
        return 1;
    }
    int all = argc > 1 && strchr(argv[1], 'a');
    if (all) {
        printf("%s %s %s %s %s\n", u.sysname,
               u.nodename, u.release, u.version,
               u.machine);
    } else {
        printf("%s\n", u.sysname);
    }
    return 0;
}

// Case-insensitive substring search —
// strcasestr is a GNU extension the
// wasi libc does not carry, so the
// applet rolls its own.
static int ci_contains(const char *hay,
                       const char *needle) {
    size_t nl = strlen(needle);
    if (nl == 0) return 1;
    for (const char *p = hay; *p; p++) {
        size_t i = 0;
        while (i < nl && p[i]
               && tolower((unsigned char)p[i])
                  == tolower((unsigned char)needle[i])) {
            i++;
        }
        if (i == nl) return 1;
    }
    return 0;
}

static int ap_grep(int argc, char **argv) {
    int insensitive = 0, invert = 0, number = 0, i = 1;
    while (i < argc && argv[i][0] == '-' && argv[i][1]) {
        for (const char *p = argv[i] + 1; *p; p++) {
            if (*p == 'i') insensitive = 1;
            if (*p == 'v') invert = 1;
            if (*p == 'n') number = 1;
        }
        i++;
    }
    if (i >= argc) {
        fprintf(stderr, "grep [-inv] <text> [file]\n");
        return 2;
    }
    const char *needle = argv[i++];
    FILE *f = stdin;
    if (i < argc) {
        f = fopen(argv[i], "rb");
        if (!f) {
            fprintf(stderr, "grep: %s: %s\n",
                    argv[i], strerror(errno));
            return 2;
        }
    }
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    long lineno = 0;
    int hits = 0;
    while ((len = getline(&line, &cap, f)) >= 0) {
        lineno++;
        int found = insensitive
            ? ci_contains(line, needle)
            : (strstr(line, needle) != NULL);
        if (found != invert) {
            hits++;
            if (number) printf("%ld:", lineno);
            fwrite(line, 1, (size_t)len, stdout);
            if (len == 0 || line[len - 1] != '\n') putchar('\n');
        }
    }
    free(line);
    if (f != stdin) fclose(f);
    return hits ? 0 : 1;
}

static int ap_sleep(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "sleep <seconds>\n");
        return 1;
    }
    double secs = atof(argv[1]);
    if (secs < 0) secs = 0;
    struct timespec ts;
    ts.tv_sec = (time_t)secs;
    ts.tv_nsec = (long)((secs - (double)ts.tv_sec) * 1e9);
    nanosleep(&ts, NULL);
    return 0;
}

// ---------- dispatch ----------

int main(int argc, char **argv) {
    // The kernel stages the whole tree
    // and tells us where the operator
    // stands; take up that position,
    // like any well-brought-up process.
    const char *pwd = getenv("PWD");
    if (pwd && pwd[0]) chdir(pwd);
    const char *name = "linuxbox";
    int shift = 0;
    if (argc > 0) {
        const char *base = strrchr(argv[0], '/');
        name = base ? base + 1 : argv[0];
    }
    // Invoked as linuxbox with an applet
    // name in argv[1]: shift and dispatch.
    if (strcmp(name, "linuxbox") == 0 && argc > 1) {
        int known = 0;
        for (int i = 0; applet_names[i]; i++) {
            if (strcmp(argv[1], applet_names[i]) == 0) {
                known = 1;
                break;
            }
        }
        if (known) {
            name = argv[1];
            shift = 1;
        }
    }
    argc -= shift;
    argv += shift;

    if (strcmp(name, "ls") == 0) return ap_ls(argc, argv);
    if (strcmp(name, "cat") == 0) return ap_cat(argc, argv);
    if (strcmp(name, "echo") == 0) return ap_echo(argc, argv);
    if (strcmp(name, "pwd") == 0) return ap_pwd(argc, argv);
    if (strcmp(name, "wc") == 0) return ap_wc(argc, argv);
    if (strcmp(name, "head") == 0) return ap_headtail(argc, argv, 0);
    if (strcmp(name, "tail") == 0) return ap_headtail(argc, argv, 1);
    if (strcmp(name, "true") == 0) return 0;
    if (strcmp(name, "false") == 0) return 1;
    if (strcmp(name, "env") == 0) return ap_env(argc, argv);
    if (strcmp(name, "cp") == 0) return ap_cp(argc, argv);
    if (strcmp(name, "mv") == 0) return ap_mv(argc, argv);
    if (strcmp(name, "rm") == 0) return ap_rm(argc, argv);
    if (strcmp(name, "mkdir") == 0) return ap_mkdir(argc, argv);
    if (strcmp(name, "touch") == 0) return ap_touch(argc, argv);
    if (strcmp(name, "uname") == 0) return ap_uname(argc, argv);
    if (strcmp(name, "grep") == 0) return ap_grep(argc, argv);
    if (strcmp(name, "sleep") == 0) return ap_sleep(argc, argv);

    fprintf(stderr, "linuxbox — the house's linux userspace\n");
    fprintf(stderr, "applets:");
    for (int i = 1; applet_names[i]; i++) {
        fprintf(stderr, " %s", applet_names[i]);
    }
    fprintf(stderr, "\n");
    return argc > 1 ? 2 : 0;
}
