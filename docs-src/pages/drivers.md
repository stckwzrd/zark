---
title: Драйверы и низкоуровневый код
order: 30.5
section: Интероп и инструменты
description: volatile, packed struct, inline asm, Cpu, Port, Bits, атомики, сборка без libc и ядро, которое загружается в QEMU
---

Vibe подходит для драйверов и ядер: регистры устройств описываются структурами, привилегированные инструкции вызываются как обычные функции, а программа собирается без libc. Всё, что нужно, вшито в язык и прелюдию. Ни макросов, ни `#pragma`, ни атрибутов компилятора.

| Задача | В C | В Vibe |
|---|---|---|
| регистр устройства | `volatile uint32_t *` и макросы | `volatile u32* reg` или `volatile u32` в `struct` |
| формат дескриптора | `__attribute__((packed))` | `packed struct` |
| порты ввода-вывода | `asm volatile` с ограничениями | `Port::in8(p)`, `Port::out8(p, v)` |
| `cli`, `hlt`, `rdtsc`, `cr3`, MSR | свой inline asm на каждую | `Cpu::cli()`, `Cpu::halt()`, `Cpu::rdtsc()`, `Cpu::cr3()`, `Cpu::rdmsr(n)` |
| биты регистра | маски и сдвиги вручную | `Bits::get(v, 7, 4)`, `Bits::set(v, 7, 4, x)` |
| атомарные операции, спинлок | `<stdatomic.h>` | `Atomic::cas32(...)`, `Spinlock` |
| без libc | `-nostdlib -ffreestanding` и скрипты | `--freestanding` |

## `volatile`

`volatile` ставится перед типом и означает, что каждое чтение и запись обращаются к памяти: компилятор их не склеивает и не выбрасывает. Это нужно для регистров устройств.

```vibe run
struct Uart {
    volatile u32 data;
    volatile u32 status;
    volatile u32 control;
}

void main() {
    Uart dev;
    dev.status = 1;
    volatile u32* ctrl = &dev.control;
    *ctrl = 0xA0;
    *ctrl |= 1;
    println(dev.status, *ctrl);
}
```

`volatile` относится к тому, что лежит по адресу: `volatile u32* p` — указатель на `volatile u32`. Поле `volatile u32 data` и переменная `volatile u32 x` тоже работают. Ширина обращения всегда равна ширине типа: `volatile u8*` читает ровно один байт, `volatile u16*` — два.

```vibe run
void main() {
    u32 word = 0xAABBCCDD;
    volatile u8* bytes = &word as *u8;
    volatile u16* halves = &word as *u16;
    println(bytes[0], bytes[1], halves[1]);
    bytes[1] = 0x11;
    println(word);
}
```

Реальный адрес регистров задаётся числом через `as`: `auto uart = 0xFE201000 as *Uart;`.

## `packed struct`

Обычная структура выравнивает поля, как в C. `packed struct` кладёт поля вплотную, без пропусков: так устроены дескрипторы, таблицы IDT и GDT, заголовки пакетов и конфигурация PCI.

```vibe run
packed struct Descriptor {
    u64 addr;
    u32 len;
    u16 flags;
    u16 next;
}

struct Loose { u8 tag; u32 len; u16 crc; }
packed struct Tight { u8 tag; u32 len; u16 crc; }

void main() {
    println(sizeof(Descriptor), sizeof(Loose), sizeof(Tight), alignof(Tight));
    Tight t;
    t.tag = 7;
    t.len = 0x01020304;
    t.crc = 0xABCD;
    volatile u8* raw = &t as *u8;
    println(raw[0], raw[1], raw[5], t.len, t.crc);
}
```

Доступ к невыровненным полям обычный: x86-64 это допускает. Выравнивание структуры вручную (`align(4096)`) пока не поддерживается: выравнивайте нужные буферы в скрипте линковщика.

## Биты регистров: `Bits`

```vibe run
void main() {
    u64 reg = 0;
    reg = Bits::set(reg, 7, 4, 0xA);
    reg |= Bits::bit(0);
    println(reg, Bits::get(reg, 7, 4), Bits::mask(15, 8));
}
```

| Функция | Что делает |
|---|---|
| `Bits::bit(n)` | число с одним битом `n` |
| `Bits::mask(hi, lo)` | маска из битов `hi..lo` включительно |
| `Bits::get(v, hi, lo)` | значение битового поля |
| `Bits::set(v, hi, lo, x)` | `v` с заменённым полем |

Результаты имеют тип `u64`; для 32-битного регистра добавляйте `as u32`: сужение в Vibe всегда явное.

## Процессор: `Cpu` и порты: `Port`

Это обычные статические методы. Привилегированные инструкции в обычной программе вызывают сбой, поэтому используйте их в ядре или драйвере.

| Функция | Инструкция |
|---|---|
| `Cpu::cli()`, `Cpu::sti()` | запретить и разрешить прерывания |
| `Cpu::halt()`, `Cpu::pause()`, `Cpu::nop()`, `Cpu::breakpoint()` | `hlt`, `pause`, `nop`, `int3` |
| `Cpu::fence()`, `load_fence()`, `store_fence()` | `mfence`, `lfence`, `sfence` |
| `Cpu::rdtsc()` | счётчик тактов |
| `Cpu::cr0()`, `cr2()`, `cr3()`, `cr4()` и `set_cr0(v)`, `set_cr3(v)`, `set_cr4(v)` | управляющие регистры |
| `Cpu::load_idt(p)`, `load_gdt(p)`, `invlpg(addr)` | `lidt`, `lgdt`, `invlpg` |
| `Cpu::rdmsr(n)`, `Cpu::wrmsr(n, v)` | модельные регистры |
| `Port::in8(p)`, `in16`, `in32` | `in` |
| `Port::out8(p, v)`, `out16`, `out32` | `out` |

`rdtsc`, `pause` и барьеры работают и в обычных программах:

```vibe run
void main() {
    Cpu::fence();
    const auto a = Cpu::rdtsc();
    const auto b = Cpu::rdtsc();
    println(b >= a);
}
```

## Атомарные операции и `Spinlock`

```vibe run
void main() {
    u32 counter = 5;
    const auto old = Atomic::fetch_add32(&counter, 3);
    const auto prev = Atomic::swap32(&counter, 100);
    const auto seen = Atomic::cas32(&counter, 100, 7);
    println(old, prev, seen, counter);

    Spinlock lock;
    lock.lock();
    println(lock.try_lock());
    lock.unlock();
    println(lock.try_lock());
}
```

| Функция | Что делает |
|---|---|
| `Atomic::fetch_add32(p, v)`, `fetch_add64` | прибавляет и возвращает старое значение |
| `Atomic::swap32(p, v)`, `swap64` | записывает и возвращает старое значение |
| `Atomic::cas32(p, expected, desired)`, `cas64` | пишет `desired`, если там `expected`; возвращает прежнее значение |

## `asm`: свои инструкции

Если нужной инструкции нет в `Cpu`, её можно вставить самим: `asm<Тип>("шаблон", "ограничения", операнды...)`. Шаблон и ограничения — в синтаксисе LLVM (AT&T). Фигурные скобки в строках экранируются: `\{rax\}`.

```vibe
u64 read_flags() { return asm<u64>("pushfq; popq $0", "=r,~\{memory\}"); }
```

Собственный бэкенд сам кодирует только шаблоны, которые использует прелюдия (они перечислены выше). Для остальных он остановится с понятным сообщением, а сборка с `--llvm` примет любой шаблон.

## Сборка без libc: `--freestanding`

`vibe build ядро.vibe boot.S -Wl,-T,linker.ld --freestanding -o kernel.elf` компонует с `-nostdlib -static` и отключает проверки границ (их сообщения требуют libc). В режиме можно использовать всё, что не вызывает libc: `Fmt` и `Writer` работают без выделений, `println` не нужен, потому что вывод вы пишете сами.

Компилятор может вызвать `memset` и `memcpy` при копировании и обнулении больших значений. В ядре определите их сами: определение с `export` заменяет объявление из прелюдии.

```vibe
export void* memset(void* dst, i32 c, u64 n) {
    auto p = dst as *u8;
    for (auto i : 0..n) { p[i] = c as u8; }
    return dst;
}
```

Файлы `.S`, `.c`, `.o` и параметры `-Wl,...`, `-T...`, `-nostdlib`, `-static` передаются как есть.

## Пример: ядро, которое загружается в QEMU

В `examples/baremetal/` лежит полное ядро x86-64 на Vibe: `boot.S` (заголовок Multiboot, переход в 64-битный режим, заглушки прерываний), `linker.ld` и `kernel.vibe`.

```vibe
struct Serial {
    static void put(u8 c) {
        while ((Port::in8(0x3F8 + 5) & 0x20) == 0) { Cpu::pause(); }
        Port::out8(0x3F8, c);
    }
}

!void serial_write(void* ctx, str s) {
    for (auto c : s) { Serial::put(c); }
}

void kprintln(Fmt f) {
    auto w = Writer{ .ctx = null, .write_fn = serial_write };
    _ = w.put(f);
    Serial::put('\n');
}

export void kmain() {
    kprintln("Hello from Vibe on bare metal!");
    kprintln("paging = {Bits::get(Cpu::cr0(), 31, 31)}");
}
```

Своя `kprintln` с интерполяцией строк получается из `Fmt` и `Writer` за шесть строк, а память не выделяется. Ядро выводит текст в последовательный порт, строит IDT (`packed struct`), ловит исключение `int3` в обработчике на Vibe и возвращается из него. Запуск:

```sh
$ examples/baremetal/run.sh
Hello from Vibe on bare metal!
protected mode = 1, paging = 1
page table aligned = true, 4 * 5 = 20
fib = [0, 1, 1, 2, 3, 5, 8, 13]
interrupt 3, error code 0, back in the kernel
after int3
```

Скрипт собирает ядро, превращает ELF в 32-битный образ для Multiboot (`objcopy -O elf32-i386`) и запускает `qemu-system-x86_64`. Тот же пример проверяется тестами на обоих бэкендах.

## Чего пока нет

- Атрибута `interrupt`: обработчики прерываний пишутся как заглушки на ассемблере (см. `boot.S`) и вызывают функцию на Vibe.
- `align(N)` для структур и переменных.
- Битовых полей в `struct`: используйте `Bits`.
- 8- и 16-битных атомарных операций.
- Кодирования произвольного `asm` в собственном бэкенде.
- Целей кроме x86-64.

## Что дальше

- C и ассемблерные файлы рядом с Vibe: [взаимодействие с C](c-interop.md).
- Память без кучи: [память и аллокаторы](memory.md).
- Устройство бэкендов: [как всё устроено](how-it-works.md).
