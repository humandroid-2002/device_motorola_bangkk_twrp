#define _GNU_SOURCE
#include <ctype.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/ioctl.h>
#include <linux/dm-ioctl.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <sys/types.h>
#include <unistd.h>

#define DMCTL_LOG "/tmp/recovery.log"
#define DMCTL_TAG "[OF-DMCTL] "
#define DMCTL_MAX_HOLDERS 256
#define DMCTL_MAX_MOUNTS 64

typedef int (*ioctl_fn)(int, int, ...);

static ioctl_fn g_real_ioctl;
static int (*g_real_execve)(const char *, char *const[], char *const[]) = NULL;
static pthread_once_t g_real_ioctl_once = PTHREAD_ONCE_INIT;
static pthread_mutex_t g_release_lock = PTHREAD_MUTEX_INITIALIZER;

static void log_line(const char *fmt, ...)
{
    char body[512];
    char line[600];
    va_list ap;
    int n;

    va_start(ap, fmt);
    n = vsnprintf(body, sizeof(body), fmt, ap);
    va_end(ap);
    if (n < 0)
        return;

    n = snprintf(line, sizeof(line), DMCTL_TAG "%s\n", body);
    if (n < 0)
        return;

    int fd = open(DMCTL_LOG, O_WRONLY | O_APPEND | O_CLOEXEC);
    if (fd < 0)
        fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd < 0)
        return;
    (void)write(fd, line, (size_t)n);
    close(fd);
}

static void resolve_real_ioctl(void)
{
    g_real_ioctl = (ioctl_fn)dlsym(RTLD_NEXT, "ioctl");
}

static void resolve_real_execve(void)
{
    g_real_execve = (int (*)(const char *, char *const[], char *const[]))dlsym(RTLD_NEXT, "execve");
}

static void read_comm(pid_t pid, char *buf, size_t len)
{
    char path[64];
    ssize_t n;

    snprintf(path, sizeof(path), "/proc/%d/comm", pid);
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        snprintf(buf, len, "?");
        return;
    }
    n = read(fd, buf, len - 1);
    close(fd);
    if (n <= 0) {
        snprintf(buf, len, "?");
        return;
    }
    buf[n] = '\0';
    char *nl = strchr(buf, '\n');
    if (nl != NULL)
        *nl = '\0';
}

static pid_t read_ppid(pid_t pid)
{
    char path[64];
    char buf[512];
    int ppid = 0;
    ssize_t n;

    snprintf(path, sizeof(path), "/proc/%d/stat", pid);
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return 0;
    n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0)
        return 0;
    buf[n] = '\0';

    char *end = strrchr(buf, ')');
    if (end == NULL)
        return 0;
    if (sscanf(end + 2, "%*c %d", &ppid) != 1)
        return 0;
    return (pid_t)ppid;
}

static bool is_ancestor(pid_t pid)
{
    pid_t cur = getppid();

    while (cur > 1) {
        if (cur == pid)
            return true;
        pid_t next = read_ppid(cur);
        if (next == cur || next <= 0)
            break;
        cur = next;
    }
    return false;
}

static bool has_cmdline(pid_t pid)
{
    char path[64];
    char byte;
    ssize_t n;

    snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return false;
    n = read(fd, &byte, 1);
    close(fd);
    return n > 0;
}

static bool maps_hold(pid_t pid, unsigned int maj, unsigned int min)
{
    char path[64];
    char *line = NULL;
    size_t cap = 0;
    bool hit = false;

    snprintf(path, sizeof(path), "/proc/%d/maps", pid);
    FILE *f = fopen(path, "r");
    if (f == NULL)
        return false;
    while (getline(&line, &cap, f) >= 0) {
        unsigned int m, n;
        if (sscanf(line, "%*s %*s %*s %x:%x", &m, &n) == 2 && m == maj &&
            n == min) {
            hit = true;
            break;
        }
    }
    free(line);
    fclose(f);
    return hit;
}

static bool mountinfo_holds(pid_t pid, unsigned int maj, unsigned int min)
{
    char path[64];
    char *line = NULL;
    size_t cap = 0;
    bool hit = false;

    snprintf(path, sizeof(path), "/proc/%d/mountinfo", pid);
    FILE *f = fopen(path, "r");
    if (f == NULL)
        return false;
    while (getline(&line, &cap, f) >= 0) {
        unsigned int m, n;
        if (sscanf(line, "%*u %*u %u:%u", &m, &n) == 2 && m == maj && n == min) {
            hit = true;
            break;
        }
    }
    free(line);
    fclose(f);
    return hit;
}

static bool fds_hold(pid_t pid, unsigned int maj, unsigned int min)
{
    char dirpath[64];
    dev_t want = makedev(maj, min);
    bool hit = false;
    struct dirent *de;

    snprintf(dirpath, sizeof(dirpath), "/proc/%d/fd", pid);
    DIR *dir = opendir(dirpath);
    if (dir == NULL)
        return false;
    while ((de = readdir(dir)) != NULL) {
        char path[PATH_MAX];
        struct stat st;

        if (de->d_name[0] == '.')
            continue;
        snprintf(path, sizeof(path), "/proc/%d/fd/%s", pid, de->d_name);
        if (stat(path, &st) != 0)
            continue;
        if ((S_ISBLK(st.st_mode) && st.st_rdev == want) || st.st_dev == want) {
            hit = true;
            break;
        }
    }
    closedir(dir);
    return hit;
}

static bool process_holds(pid_t pid, unsigned int maj, unsigned int min)
{
    if (!has_cmdline(pid))
        return false;
    if (maps_hold(pid, maj, min))
        return true;
    if (mountinfo_holds(pid, maj, min))
        return true;
    if (fds_hold(pid, maj, min))
        return true;
    return false;
}

static int find_holders(unsigned int maj, unsigned int min, pid_t *out, int max)
{
    struct dirent *de;
    pid_t self = getpid();
    int total = 0;

    DIR *proc = opendir("/proc");
    if (proc == NULL)
        return 0;
    while ((de = readdir(proc)) != NULL) {
        if (!isdigit((unsigned char)de->d_name[0]))
            continue;
        pid_t pid = (pid_t)atoi(de->d_name);
        if (pid <= 1 || pid == self || is_ancestor(pid))
            continue;
        if (!process_holds(pid, maj, min))
            continue;
        if (total < max)
            out[total] = pid;
        total++;
    }
    closedir(proc);
    return total;
}

static void unmount_device(unsigned int maj, unsigned int min)
{
    char points[DMCTL_MAX_MOUNTS][PATH_MAX];
    int count = 0;
    char *line = NULL;
    size_t cap = 0;

    FILE *f = fopen("/proc/self/mountinfo", "r");
    if (f == NULL)
        return;
    while (getline(&line, &cap, f) >= 0) {
        unsigned int m, n;
        char root[PATH_MAX];
        char mountpoint[PATH_MAX];

        if (sscanf(line, "%*u %*u %u:%u %4095s %4095s", &m, &n, root,
                   mountpoint) != 4)
            continue;
        if (m != maj || n != min)
            continue;
        if (count < DMCTL_MAX_MOUNTS) {
            snprintf(points[count], sizeof(points[count]), "%s", mountpoint);
            count++;
        }
    }
    free(line);
    fclose(f);

    for (int i = count - 1; i >= 0; i--) {
        if (umount2(points[i], 0) == 0) {
            log_line("unmounted %s", points[i]);
        } else if (errno != ENOENT) {
            if (umount2(points[i], MNT_DETACH) == 0)
                log_line("lazy unmounted %s", points[i]);
        }
    }
}

static void release_holders(const char *name, unsigned int maj, unsigned int min)
{
    pid_t holders[DMCTL_MAX_HOLDERS];
    int stable = 0;

    unmount_device(maj, min);

    for (int iter = 0; iter < 60 && stable < 2; iter++) {
        int total = find_holders(maj, min, holders, DMCTL_MAX_HOLDERS);

        if (total == 0) {
            stable++;
        } else {
            stable = 0;
            for (int i = 0; i < total && i < DMCTL_MAX_HOLDERS; i++) {
                pid_t pid = holders[i];
                char comm[64];

                read_comm(pid, comm, sizeof(comm));
                if (kill(pid, SIGKILL) == 0) {
                    log_line("killed pid %d (%s) holding %s", pid, comm, name);
                } else if (errno != ESRCH) {
                    log_line("kill pid %d (%s) failed: %s", pid, comm,
                             strerror(errno));
                }
            }
        }
        usleep(100000);
    }
    if (stable < 2)
        log_line("holders for %s still present after wait", name);
}

__attribute__((constructor)) static void dmctl_constructor(void)
{
    log_line("libdmctl loaded (pid %d)", (int)getpid());
    // Propagate the shim to child processes (e.g. the external dmctl tool)
    // so that DM_DEV_REMOVE EBUSY is handled there too, without patching
    // the dmctl binary itself.
    setenv("LD_PRELOAD", "libdmctl.so", 1);
}

__attribute__((visibility("default")))
int ioctl(int fd, int request, ...)
{
    va_list ap;
    void *arg;

    va_start(ap, request);
    arg = va_arg(ap, void *);
    va_end(ap);

    pthread_once(&g_real_ioctl_once, resolve_real_ioctl);
    ioctl_fn fn = g_real_ioctl;
    if (fn == NULL)
        return (int)syscall(SYS_ioctl, fd, request, arg);

    int rc = fn(fd, request, arg);
    if (rc >= 0 || errno != EBUSY)
        return rc;
    if ((unsigned int)request != (unsigned int)DM_DEV_REMOVE || arg == NULL)
        return rc;

    struct dm_ioctl *dmi = (struct dm_ioctl *)arg;
    char name[sizeof(dmi->name) + 1];
    char mapper[PATH_MAX];
    struct stat st;

    if (dmi->name[0] == '\0')
        return rc;
    memcpy(name, dmi->name, sizeof(dmi->name));
    name[sizeof(dmi->name)] = '\0';

    snprintf(mapper, sizeof(mapper), "/dev/block/mapper/%s", name);
    if (stat(mapper, &st) != 0) {
        log_line("no mapper node for %s: %s (treating as removed)", name, strerror(errno));
        return 0;
    }

    pthread_mutex_lock(&g_release_lock);
    log_line("EBUSY removing %s (%u:%u), releasing holders", name,
             major(st.st_rdev), minor(st.st_rdev));

    for (int attempt = 0; attempt < 8; attempt++) {
        release_holders(name, major(st.st_rdev), minor(st.st_rdev));
        rc = fn(fd, request, arg);
        if (rc == 0)
            break;
        if (errno == ENXIO || errno == ENODEV) {
            rc = 0;
            break;
        }
        if (errno != EBUSY)
            break;
        usleep(200000);
    }

    if (rc == 0)
        log_line("removed %s", name);
    else
        log_line("failed to remove %s: %s", name, strerror(errno));
    pthread_mutex_unlock(&g_release_lock);
    return rc;
}



static int destroy_mapper(const char *name)
{
    struct dm_ioctl dmi;
    char path[PATH_MAX];
    struct stat st;
    int fd, rc;

    fd = open("/dev/device-mapper", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        log_line("cannot open /dev/device-mapper: %s", strerror(errno));
        return -1;
    }

    memset(&dmi, 0, sizeof(dmi));
    dmi.version[0] = 4;
    dmi.version[1] = 0;
    dmi.version[2] = 0;
    dmi.data_size = sizeof(dmi);
    dmi.data_start = sizeof(dmi);
    strncpy(dmi.name, name, sizeof(dmi.name) - 1);

    if (g_real_ioctl == NULL)
        resolve_real_ioctl();
    if (g_real_ioctl == NULL) {
        close(fd);
        return -1;
    }

    rc = g_real_ioctl(fd, DM_DEV_REMOVE, &dmi);
    if (rc < 0 && errno == EBUSY) {
        snprintf(path, sizeof(path), "/dev/block/mapper/%s", name);
        if (stat(path, &st) == 0) {
            release_holders(name, major(st.st_rdev), minor(st.st_rdev));
            rc = g_real_ioctl(fd, DM_DEV_REMOVE, &dmi);
        }
    }
    if (rc < 0 && (errno == ENXIO || errno == ENODEV))
        rc = 0;
    close(fd);
    return rc;
}

__attribute__((visibility("default")))
int execve(const char *pathname, char *const argv[], char *const envp[])
{
    if (g_real_execve == NULL)
        resolve_real_execve();
    if (g_real_execve == NULL)
        return (int)syscall(SYS_execve, pathname, argv, envp);

    // Only act in the recovery process
    char comm[64];
    read_comm(getpid(), comm, sizeof(comm));
    if (strcmp(comm, "recovery") == 0 && argv && argv[0] && argv[1] && argv[2] &&
        strcmp(argv[1], "-c") == 0 &&
        (strstr(argv[2], "make_f2fs") != NULL || strstr(argv[2], "mke2fs") != NULL)) {
        const char *devs[] = { "/dev/block/sde26", "/dev/block/mapper/userdata" };
        for (int i = 0; i < 2; i++) {
            struct stat st;
            if (stat(devs[i], &st) == 0 && S_ISBLK(st.st_mode)) {
                log_line("pre-exec: releasing holders for %s before format", devs[i]);
                release_holders(devs[i], major(st.st_rdev), minor(st.st_rdev));
                unmount_device(major(st.st_rdev), minor(st.st_rdev));
            }
        }
        // The userdata mapping keeps the underlying partition busy even
        // after its holders are gone; remove it before mkfs runs.
        if (stat("/dev/block/mapper/userdata", &(struct stat){0}) == 0 &&
            destroy_mapper("userdata") == 0) {
            log_line("pre-exec: removed userdata mapping before format");
        }
    }

    return g_real_execve(pathname, argv, envp);
}
