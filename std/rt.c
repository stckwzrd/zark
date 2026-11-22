#define _GNU_SOURCE
#include <errno.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <dlfcn.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <time.h>
#include <netdb.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <ucontext.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#include <execinfo.h>
#elif defined(__GLIBC__)
#include <execinfo.h>
#endif

typedef struct { int64_t sec, nsec; } vtimespec;

int vrt_errno(void);

static long err(long r)
{
    return r < 0 ? -(long)vrt_errno() : r;
}

int vrt_errno(void)
{
    int e = errno;
#if defined(__APPLE__)
    switch (e) {
    case EAGAIN: return 11;
    case ENOTEMPTY: return 39;
    case ECONNRESET: return 104;
    case ETIMEDOUT: return 110;
    case ECONNREFUSED: return 111;
    case EHOSTUNREACH: return 113;
    case ECONNABORTED: return 103;
    case EADDRINUSE: return 98;
    }
#endif
    return e;
}

int vrt_os(void)
{
#if defined(__APPLE__)
    return 2;
#else
    return 1;
#endif
}

int vrt_native(void)
{
#if defined(__linux__) && defined(__x86_64__)
    return 1;
#else
    return 0;
#endif
}

static int open_flags(long f)
{
    int o = (int)(f & 3);
    if (f & 0100) o |= O_CREAT;
    if (f & 0200) o |= O_EXCL;
    if (f & 01000) o |= O_TRUNC;
    if (f & 02000) o |= O_APPEND;
    if (f & 04000) o |= O_NONBLOCK;
    if (f & 04010000) o |= O_SYNC;
    if (f & 0200000) o |= O_DIRECTORY;
    if (f & 02000000) o |= O_CLOEXEC;
    return o;
}

static long do_stat(const char *path, int follow, long *out)
{
    struct stat st;
    int r = follow ? stat(path, &st) : lstat(path, &st);
    if (r < 0) return err(-1);
    memset(out, 0, 18 * sizeof(long));
    out[3] = (long)st.st_mode;
    out[6] = (long)st.st_size;
#if defined(__APPLE__)
    out[11] = (long)st.st_mtimespec.tv_sec;
#else
    out[11] = (long)st.st_mtim.tv_sec;
#endif
    return 0;
}

long vrt_syscall(long nr, long a, long b, long c, long d, long e, long f)
{
    switch (nr) {
    case 0: return err(read((int)a, (void *)b, (size_t)c));
    case 1: return err(write((int)a, (void *)b, (size_t)c));
    case 2: return err(open((const char *)a, open_flags(b), (mode_t)c));
    case 3: return err(close((int)a));
    case 4: return do_stat((const char *)a, 1, (long *)b);
    case 6: return do_stat((const char *)a, 0, (long *)b);
    case 17: return err(pread((int)a, (void *)b, (size_t)c, (off_t)d));
    case 18: return err(pwrite((int)a, (void *)b, (size_t)c, (off_t)d));
    case 9: {
        int fl = 0;
        if (d & 1) fl |= MAP_SHARED;
        if (d & 2) fl |= MAP_PRIVATE;
        if (d & 0x10) fl |= MAP_FIXED;
        if (d & 0x20) fl |= MAP_ANON;
        void *p = mmap((void *)a, (size_t)b, (int)c, fl, (int)e, (off_t)f);
        return p == MAP_FAILED ? err(-1) : (long)p;
    }
    case 10: return err(mprotect((void *)a, (size_t)b, (int)c));
    case 11: return err(munmap((void *)a, (size_t)b));
    case 16: return err(ioctl((int)a, (unsigned long)b, c));
    case 39: return (long)getpid();
    case 50: return err(listen((int)a, (int)b));
    case 231: _exit((int)a);
    }
#if defined(__linux__)
    return err(syscall(nr, a, b, c, d, e, f));
#else
    return -38;
#endif
}

long vrt_clock_gettime(int id, vtimespec *ts)
{
    struct timespec t;
    int r = clock_gettime(id == 0 ? CLOCK_REALTIME : CLOCK_MONOTONIC, &t);
    ts->sec = t.tv_sec;
    ts->nsec = t.tv_nsec;
    return r;
}

long vrt_sysconf(int name)
{
    return sysconf(name == 84 ? _SC_NPROCESSORS_ONLN : name);
}

long vrt_exe_path(char *buf, unsigned long n)
{
#if defined(__APPLE__)
    char tmp[4096];
    uint32_t size = sizeof tmp;
    if (_NSGetExecutablePath(tmp, &size) != 0) return -1;
    if (!realpath(tmp, buf)) return -1;
    return (long)strlen(buf);
#else
    return readlink("/proc/self/exe", buf, n);
#endif
}

unsigned char *vrt_dirent_name(void *ent)
{
    return (unsigned char *)((struct dirent *)ent)->d_name;
}

int vrt_dirent_type(void *ent)
{
    return ((struct dirent *)ent)->d_type;
}

typedef struct {
    int flags, family, socktype, protocol;
    unsigned addrlen;
    int pad;
    void *addr;
    char *canonname;
    void *next;
} linux_ai;

int vrt_getaddrinfo(const char *node, const char *service, int passive, linux_ai **res)
{
    struct addrinfo hints, *r;
    memset(&hints, 0, sizeof hints);
    hints.ai_socktype = SOCK_STREAM;
    if (passive) hints.ai_flags = AI_PASSIVE;
    int rc = getaddrinfo(node, service, &hints, &r);
    if (rc != 0) return rc;
#if defined(__APPLE__)
    for (struct addrinfo *p = r; p; p = p->ai_next) {
        void *a = p->ai_addr;
        p->ai_addr = (void *)p->ai_canonname;
        p->ai_canonname = a;
    }
#endif
    *res = (linux_ai *)r;
    return 0;
}

void vrt_freeaddrinfo(linux_ai *r)
{
#if defined(__APPLE__)
    for (struct addrinfo *p = (struct addrinfo *)r; p; p = p->ai_next) {
        void *a = p->ai_addr;
        p->ai_addr = (void *)p->ai_canonname;
        p->ai_canonname = a;
    }
#endif
    freeaddrinfo((struct addrinfo *)r);
}

int vrt_socket(int family, int kind, int proto)
{
#if defined(__APPLE__)
    int fd = socket(family, kind & 0xf, proto);
    if (fd >= 0) {
        int one = 1;
        fcntl(fd, F_SETFD, FD_CLOEXEC);
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    }
    return fd;
#else
    return socket(family, kind, proto);
#endif
}

int vrt_setsockopt(int fd, int level, int name, void *val, unsigned len)
{
#if defined(__APPLE__)
    if (level == 1) {
        level = SOL_SOCKET;
        name = name == 2 ? SO_REUSEADDR : name == 20 ? SO_RCVTIMEO : name == 21 ? SO_SNDTIMEO : name;
    }
#endif
    return setsockopt(fd, level, name, val, len);
}

long vrt_send(int fd, void *buf, unsigned long n, int flags)
{
#if defined(__APPLE__)
    return send(fd, buf, n, 0);
#else
    return send(fd, buf, n, flags);
#endif
}

int vrt_family(const unsigned char *sa)
{
#if defined(__APPLE__)
    return sa[1] == AF_INET6 ? 10 : sa[1];
#else
    return sa[0] | (sa[1] << 8);
#endif
}

const char *vrt_inet_ntop(int family, const void *src, char *dst, unsigned n)
{
    return inet_ntop(family == 10 ? AF_INET6 : AF_INET, src, dst, n);
}

typedef struct { _Atomic int state; pthread_mutex_t m; } vmutex;
typedef struct { _Atomic int state; pthread_cond_t c; } vcond;

_Static_assert(sizeof(vmutex) <= 80, "vmutex");
_Static_assert(sizeof(vcond) <= 64, "vcond");

static void lazy(_Atomic int *s, void (*init)(void *), void *x)
{
    int z = 0;
    if (atomic_load(s) == 2) return;
    if (atomic_compare_exchange_strong(s, &z, 1)) {
        init(x);
        atomic_store(s, 2);
        return;
    }
    while (atomic_load(s) != 2) sched_yield();
}

static void mutex_init(void *x) { pthread_mutex_init(&((vmutex *)x)->m, 0); }
static void cond_init(void *x) { pthread_cond_init(&((vcond *)x)->c, 0); }

int vrt_mutex_lock(vmutex *m)
{
    lazy(&m->state, mutex_init, m);
    return pthread_mutex_lock(&m->m);
}

int vrt_mutex_trylock(vmutex *m)
{
    lazy(&m->state, mutex_init, m);
    return pthread_mutex_trylock(&m->m);
}

int vrt_mutex_unlock(vmutex *m)
{
    lazy(&m->state, mutex_init, m);
    return pthread_mutex_unlock(&m->m);
}

int vrt_cond_wait(vcond *c, vmutex *m)
{
    lazy(&c->state, cond_init, c);
    return pthread_cond_wait(&c->c, &m->m);
}

int vrt_cond_timedwait(vcond *c, vmutex *m, vtimespec *ts)
{
    struct timespec t = { ts->sec, ts->nsec };
    lazy(&c->state, cond_init, c);
    return pthread_cond_timedwait(&c->c, &m->m, &t);
}

int vrt_cond_signal(vcond *c)
{
    lazy(&c->state, cond_init, c);
    return pthread_cond_signal(&c->c);
}

int vrt_cond_broadcast(vcond *c)
{
    lazy(&c->state, cond_init, c);
    return pthread_cond_broadcast(&c->c);
}

uint64_t vrt_fetch_add64(_Atomic uint64_t *p, uint64_t v) { return atomic_fetch_add(p, v); }
uint64_t vrt_swap64(_Atomic uint64_t *p, uint64_t v) { return atomic_exchange(p, v); }
uint64_t vrt_cas64(_Atomic uint64_t *p, uint64_t expected, uint64_t desired)
{
    atomic_compare_exchange_strong(p, &expected, desired);
    return expected;
}

int vrt_backtrace(void **buf, int n)
{
#if defined(__APPLE__) || defined(__GLIBC__)
    return backtrace(buf, n);
#else
    return 0;
#endif
}

typedef void (*report_fn)(int, long, unsigned long, unsigned long, unsigned long, unsigned long);

static report_fn report;
static char altstack[65536];

static void crash(int sig, siginfo_t *si, void *ucv)
{
    ucontext_t *uc = ucv;
    unsigned long pc = 0, sp = 0, fp = 0;
    long code = si->si_code;
#if defined(__APPLE__) && defined(__aarch64__)
    pc = uc->uc_mcontext->__ss.__pc;
    sp = uc->uc_mcontext->__ss.__sp;
    fp = uc->uc_mcontext->__ss.__fp;
#elif defined(__APPLE__) && defined(__x86_64__)
    pc = uc->uc_mcontext->__ss.__rip;
    sp = uc->uc_mcontext->__ss.__rsp;
    fp = uc->uc_mcontext->__ss.__rbp;
#elif defined(__linux__) && defined(__x86_64__)
    pc = uc->uc_mcontext.gregs[REG_RIP];
    sp = uc->uc_mcontext.gregs[REG_RSP];
    fp = uc->uc_mcontext.gregs[REG_RBP];
#elif defined(__linux__) && defined(__aarch64__)
    pc = uc->uc_mcontext.pc;
    sp = uc->uc_mcontext.sp;
    fp = uc->uc_mcontext.regs[29];
#endif
    if (sig == SIGFPE) code = code == FPE_INTDIV ? 1 : code == FPE_INTOVF ? 2 : 0;
    report(sig, code, (unsigned long)si->si_addr, pc, sp, fp);
}

void vrt_crash_install(report_fn fn)
{
    report = fn;
    stack_t ss;
    ss.ss_sp = altstack;
    ss.ss_size = sizeof altstack;
    ss.ss_flags = 0;
    sigaltstack(&ss, 0);
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = crash;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_RESETHAND;
    sigemptyset(&sa.sa_mask);
    int sigs[] = { SIGSEGV, SIGBUS, SIGFPE, SIGILL };
    for (int i = 0; i < 4; i++) sigaction(sigs[i], &sa, 0);
}
