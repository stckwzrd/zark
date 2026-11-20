---
title: Networking and threads
order: 40.6
section: Reference
description: std/thread (threads, Mutex, Channel, parallel_for), std/net (TCP) and std/http (client with HTTPS, threaded server)
---

## `std/thread`

```vibe run
import "std/thread" as thread;

!void main() {
    auto hits = thread::AtomicI64{};
    thread::Thread[4] ts;
    for (auto i : 0..4) {
        ts[i] = thread::spawn([&hits]() -> void {
            for (auto k : 0..1000) { hits.add(1); }
        })?;
    }
    for (auto t : ts) { _ = t; }
    for (auto i : 0..4) { ts[i].join(); }
    println(hits.load());

    i64[8] squares;
    thread::parallel_for(8, 0, [&squares](i64 i) -> void { squares[i] = i * i; })?;
    println(squares);
}
```

`spawn` runs a closure on a new thread. The closure keeps pointers to what it captures, so **join every thread before those variables go out of scope**. `spawn_fn(f, arg)` starts a plain `fn(void*)` instead.

| Type | What it is |
|---|---|
| `Thread` | `join()`, `detach()` |
| `Mutex` | `lock()`, `unlock()`, `try_lock()`; the zero value is ready |
| `Cond` | `wait(&m)`, `wait_ms(&m, ms)`, `signal()`, `broadcast()` |
| `AtomicI64` | `add(d)` (returns the old value), `load()`, `store(x)`, `compare_swap(old, new)` |
| `WaitGroup` | `add(n)`, `done()`, `wait()` |
| `Channel<T>` | a bounded queue: `Channel<T>::create(a, capacity)`, `send(v)`, `recv()`, `try_recv()`, `close()`, `destroy()` |

`parallel_for(n, threads, body)` calls `body(i)` for every `i` in `0..n`, split over `threads` threads (0 means one per CPU), and returns when all are done. Locks, channels and wait groups must not be copied once used: share them through a pointer (a channel is created on the heap for that reason).

```vibe run
import "std/thread" as thread;

!void main() {
    const auto jobs = thread::Channel<i64>::create(c_allocator(), 16)?;
    defer jobs.destroy();
    auto total = thread::AtomicI64{};
    auto worker = thread::spawn([&jobs, &total]() -> void {
        while (true) {
            const auto n = jobs.recv() catch { break; };   // error.Closed once drained
            total.add(n * n);
        }
    })?;
    for (auto i : 1..11) { jobs.send(i)?; }
    jobs.close();
    worker.join();
    println(total.load());
}
```

## `std/net`

```vibe run
import "std/net" as net;
import "std/thread" as thread;

!void main() {
    auto l = net::listen("127.0.0.1", 0)?;      // port 0: any free port
    const auto port = l.port();
    auto server = thread::spawn([&l]() -> void {
        auto c = l.accept() catch { return; };
        u8[256] buf;
        auto r = net::Reader::init(&c, buf[..]);
        const auto name = r.read_line() catch "";
        c.print("hello, {name}!\n") catch {};
        c.close();
    })?;

    auto c = net::connect_to("localhost", port)?;
    c.write_all("Vibe\n")?;
    u8[256] buf;
    auto r = net::Reader::init(&c, buf[..]);
    println(r.read_line()?);
    c.close();
    server.join();
    l.close();
}
```

- `listen(host, port)` gives a `Listener` with `accept()`, `port()` and `close()` (which also wakes up a thread blocked in `accept`).
- `connect_to(host, port)` gives a `Conn`: `read(buf)` (0 at the end), `write_all(s)`, `print(...)` with interpolation and no allocation, `set_timeout(ms)`, `close_write()`, `close()`, `peer(buf)`.
- `Reader::init(&conn, buf)` buffers reads: `read_line()`, `read_exact(&list, n)`, `read_all(&list)`.
- Errors: `error.HostNotFound`, `error.ConnectionRefused`, `error.AddressInUse`, `error.TimedOut`, `error.ConnectionReset`.

## `std/http`

The client speaks HTTP/1.1 over `http://` and `https://`. HTTPS uses the system's OpenSSL library (`libssl.so.3`), loaded the first time it is needed, so programs need no extra link flags; certificates and host names are checked against the system store.

```vibe fragment
import "std/http" as http;

!void main() {
    const auto a = c_allocator();
    auto r = http::get(a, "https://example.com/")?;
    defer r.deinit();
    println(r.status, r.header("content-type"), r.body.len);

    auto p = http::post(a, "https://httpbin.org/post", "application/json", "{{\"x\": 1}")?;
    defer p.deinit();

    http::Header[1] hs = [http::Header{ .name = "Authorization", .value = "Bearer TOKEN" }];
    auto q = http::send(a, http::Request{ .method = "DELETE", .url = "https://api.example.com/item/7", .headers = hs[..], .timeout_ms = 5000 })?;
    defer q.deinit();
}
```

- `Request` fields: `method` ("GET"), `url`, `headers`, `body`, `timeout_ms` (30000), `max_redirects` (5), `insecure` (skip certificate checks), `ca_file` (trust these PEM certificates instead of the system store).
- `Reply`: `status`, `reason`, `headers`, `body`, `header(name)` (case-insensitive), `ok()`, `deinit()`. Chunked bodies and redirects are handled.
- Errors: `error.UnsupportedScheme`, `error.InvalidUrl`, `error.CertificateInvalid`, `error.TlsUnavailable` (no libssl), plus the network errors above.
- `url_encode(a, s)`, `url_decode(a, s)`, `parse_url(s)`.

The server runs a handler on a pool of threads, keeps connections alive and gives every request its own arena:

```vibe run
import "std/http" as http;
import "std/thread" as thread;

!void main() {
    auto srv = http::Server::bind("127.0.0.1", 0)?;
    const auto port = srv.port();
    auto t = thread::spawn([&srv]() -> void {
        srv.serve(c_allocator(), 4, [](http::ServerRequest* req, http::ServerResponse* res) -> void {
            if (req.path == "/hello") {
                res.printf("text/plain", "hello, {req.param("name")}") catch {};
                return;
            }
            res.status = 404;
            res.text("not found") catch {};
        }) catch {};
    })?;

    u8[128] url;
    auto r = http::get(c_allocator(), bprint(url[..], "http://127.0.0.1:{port}/hello?name=web")?)?;
    println(r.status, r.body);
    r.deinit();
    srv.stop();
    t.join();
}
```

- `ServerRequest`: `method`, `path`, `query`, `headers`, `body`, `peer`, `header(name)`, `param(name)` (decoded query parameter), and `a`, an allocator freed after the handler returns.
- `ServerResponse`: set `status` (200), `header(name, value)`, then exactly one of `text`, `html`, `json`, `send(content_type, body)` or `printf(content_type, ...)`.
- `serve(a, threads, handler)` blocks until `stop()`. The handler runs on several threads at once: guard shared data with a `Mutex` or use atomics.
- The server speaks plain HTTP; put it behind a reverse proxy (nginx, Caddy) for HTTPS.
