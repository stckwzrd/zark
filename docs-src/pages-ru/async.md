---
title: Асинхронность
order: 40.7
section: Справочник
description: std/async (фьючеры, Executor, spawn, join, select и отмена)
---

`std/async` — однопоточный исполнитель поверх поллера рантайма (`epoll` в Linux,
`kqueue` в macOS). Это обычный Zark плюс несколько вызовов `vrt_poller_*`; в компиляторе
нет ничего async-специфичного, кроме генерации фрейма `async`-функции.

## Фьючер

Фьючер — любой struct с двумя методами:

```zark
Poll<T> poll(Context* cx);
void cancel();
```

`poll` возвращает `Ready(value)` или `Pending`. Вернуть `Pending` — значит обещать
разбудить задачу: либо вызвать `cx.waker.wake()`, либо взвести `Readable`, `Writable` или
`Sleep`. Фьючер, который не делает ни того, ни другого, останавливает исполнитель.
`cancel()` освобождает то, что взвёл последний `poll`; `spawn` и `block_on` требуют его,
а `async`-функция получает его от компилятора.

```zark run
import "std/async" as async;

struct Countdown {
    i64 n;
    void cancel() {}
    Poll<i64> poll(Context* cx) {
        if (this->n == 0) { return .Ready(42); }
        this->n -= 1;
        cx.waker.wake();
        return .Pending;
    }
}

!void main() {
    auto ex = async::Executor::init(c_allocator())?;
    defer ex.deinit();
    auto f = Countdown{ .n = 3 };
    println(ex.block_on<Countdown, i64>(&f)?);
}
```

## Executor, spawn, join, select

`Executor::init(a)` владеет поллером и задачами. `ex.block_on(&f)` крутит фьючер и
запущенные им задачи, пока фьючер не станет готов; если прогресса нет, возвращается
`error.Deadlock`. `ex.spawn(f)` забирает фьючер по `move`, кладёт его в память исполнителя
и возвращает `JoinHandle<T>`. Тип результата `spawn` и `block_on` выводится из `poll`
фьючера.

```zark run
import "std/async" as async;

struct Ready {
    i64 v;
    void cancel() {}
    Poll<i64> poll(Context* cx) { return .Ready(this->v); }
}

struct Never {
    void cancel() {}
    Poll<i64> poll(Context* cx) { return .Pending; }
}

!void main() {
    auto ex = async::Executor::init(c_allocator())?;
    defer ex.deinit();
    auto a = ex.spawn(Ready{ .v = 20 })?;
    auto b = ex.spawn(Ready{ .v = 22 })?;
    auto j = async::join(a, b);
    const auto p = ex.block_on(&j)?;
    println(p.first + p.second);

    auto s = async::select(ex.spawn(Ready{ .v = 7 })?, ex.spawn(Never{})?);
    const auto r = ex.block_on(&s)?;
    match (r) {
        .First(v) => println(v),
        .Second(_) => println(-1),
    }
}
```

`join(a, b)` даёт `Pair<A, B>`, когда готовы оба handle. `select(a, b)` даёт
`Select2Result<A, B>` от того, кто завершился первым, и отменяет второго. `JoinHandle`
одноразовый: `take()` забирает результат, `detach()` оставляет задачу работать без
результата, и после любого из них handle невалиден. Копия использованного handle
паникует.

## Async-функции и отмена

`async`-функция выполняет тело до `await` и возвращает `Pending`-фрейм. `await f` опрашивает
`f` и приостанавливает фрейм. Компилятор превращает тело в struct-фрейм и генерирует
`poll` и `cancel`:

```zark run
import "std/async" as async;

struct Never {
    void cancel() {}
    Poll<bool> poll(Context* cx) { return .Pending; }
}

i64 cleaned = 0;

async !void worker() {
    defer cleaned += 1;
    auto n = Never{};
    await n;
}

!void main() {
    {
        auto ex = async::Executor::init(c_allocator())?;
        defer ex.deinit();
        auto h = ex.spawn(worker())?;
        ex.run_batch();
        println(cleaned);
        h.cancel();
        println(cleaned);
    }
    println(cleaned);
}
```

Отмена — это незавершённая операция, а не обычный возврат: сгенерированный `cancel()`
выполняет и `defer`, и `errdefer` всех активных на точке приостановки областей, изнутри
наружу, отменяет фьючер, которого ждали, и помечает фрейм завершённым. Повторный вызов
идемпотентен и ничего не делает. `Executor.deinit()` отменяет каждую живую задачу перед
освобождением, и каждая задача отменяется ровно один раз. `detach()` не отменяет:
задача продолжает работать.

`cancel()` у `JoinHandle` — другое: он инвалидирует handle и выбрасывает незабранный
результат, поэтому второй вызов паникует, как и `take()`. `select` отменяет
проигравший handle; `join` отменяет обе стороны, кроме той, что уже отдала значение и
была забрана.

## Каналы

`Channel<T>` — неограниченная FIFO-очередь между задачами одного исполнителя. `send` не
ждёт: он только выделяет память и возвращает `error.Closed` после `close()`. `recv()` —
фьючер, который даёт `!T`, а после закрытия и опустошения очереди — `error.Closed`.

```zark run
import "std/async" as async;

async i64 first(async::Channel<i64>* ch) {
    const auto r = await ch.recv();
    return r catch -1;
}

!void main() {
    auto ex = async::Executor::init(c_allocator())?;
    defer ex.deinit();
    auto ch = async::Channel<i64>::init(c_allocator())?;
    defer ch.deinit();
    ch.send(21)?;
    ch.send(22)?;
    auto f = first(&ch);
    println(ex.block_on(&f)?);
}
```

`select_recv(a.recv(), b.recv())` ждёт первый готовый канал и снимает регистрацию со
второго; результат — `.First(v)` или `.Second(v)`, где `v` имеет тип `!T`:

```zark
async !i64 pick(async::Channel<i64>* a, async::Channel<i64>* b) {
    const auto r = await async::select_recv(a.recv(), b.recv());
    match (r) {
        .First(v) => return v?,
        .Second(v) => return v?,
    }
}
```

Канал однопоточный: все его задачи должны работать на одном исполнителе. `close()`
будит получателей; когда очередь опустеет, они получают `error.Closed`. Отмена
приостановленного `recv` (через задачу или `select_recv`) снимает waker, поэтому
последующий `send` не будит фрейм, который уже не ждёт.

В `std/async` также есть `TcpListener`, `TcpStream`, `Readable`, `Writable` и `Sleep`.
Исполнитель однопоточный: он опрашивает задачи по одной. Многопоточного исполнителя и
канала, общего для потоков, пока нет; для этого в `std/thread` есть блокирующий
`Channel<T>`.
