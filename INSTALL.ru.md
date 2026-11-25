# Установка Zark

Zark собирается из исходников одной командой. В репозитории лежит seed для бутстрапа (LLVM IR самого компилятора), поэтому нужен только clang.

```
git clone https://github.com/stckwzrd/zark.git
cd zark
sh scripts/install-deps.sh
./bootstrap.sh
./install.sh
```

- `scripts/install-deps.sh` ставит нужные инструменты через найденный пакетный менеджер (apt, dnf, pacman, apk, zypper, xbps). На macOS, если clang нет, он запускает установку Xcode command line tools.
- `./bootstrap.sh` собирает компилятор по стадиям, проверяет, что он воспроизводит сам себя, гоняет тесты и кладёт результат в `build/zark`. Занимает несколько минут.
- `./install.sh` копирует `build/zark` в `~/.local/bin` (другое место: `PREFIX=/usr/local ./install.sh`). Zark это один бинарник, стандартная библиотека встроена.

Проверка:

```
zark run examples/hello.zk
```

`bootstrap.sh` уже прогнал тесты. Повторить их (и проходы `--llvm` / `-O`):

```
ZARK=build/zark tests/run.sh
ZARK=build/zark tests/run.sh --llvm
ZARK=build/zark tests/run.sh -O
```

Для тестов нужен `python3` (фаззеры и генераторы); `scripts/install-deps.sh` его ставит.

## Что нужно

| Инструмент | Зачем |
|---|---|
| clang 18 или новее | собирает seed, линкует программы, работает для `--release` |
| библиотека C с заголовками | glibc, musl или SDK macOS |
| binutils (`ld`) | линковка на Linux |
| bash, gzip, diffutils, make | скрипт бутстрапа |
| python3 | набор тестов, который запускает `bootstrap.sh` (фаззеры и генераторы) |

## Поддерживаемые системы

| Система | Статус | Бэкенд |
|---|---|---|
| Linux x86-64, glibc (Debian, Ubuntu, Fedora, Arch, openSUSE) | собирается и проверяется | свой x86-64 бэкенд по умолчанию, LLVM через `--llvm` / `-O` |
| Linux x86-64, musl (Alpine) | собирается и проверяется | то же |
| Linux arm64 | поддерживается | только LLVM |
| macOS, Apple Silicon и Intel | поддерживается | только LLVM |
| Windows | через WSL2 | как на Linux |

Windows без WSL не поддерживается: рантайм использует `fork`, `poll` и потоки POSIX.

Свой бэкенд пишет ELF для x86-64, поэтому он есть только на Linux x86-64. На остальных системах Zark отдаёт LLVM IR в clang, это полностью поддерживаемый путь. `zark build --native` там выдаёт ошибку.

На arm64 (Linux и macOS) передача структур по значению в функции C пока не поддерживается: компилятор оформляет вызовы extern по правилам System V x86-64. Передавайте указатели. `tests/abi` запускается только на x86-64.

Части языка, привязанные к x86 (`examples/baremetal`, порты ввода-вывода и привилегированные инструкции, функции `Atomic` в прелюдии), имеют смысл только на x86-64.

## Linux

### Debian, Ubuntu и производные

```
sudo apt-get update
sudo apt-get install -y clang binutils diffutils gzip make bash git python3
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

### Fedora, RHEL, Rocky, Alma

```
sudo dnf install -y clang binutils diffutils gzip make bash git python3 glibc-devel
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

### Arch, Manjaro

```
sudo pacman -Syu --needed clang binutils diffutils gzip make bash git python glibc linux-api-headers
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

### openSUSE

```
sudo zypper install -y clang binutils diffutils gzip make bash git python3 glibc-devel
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

### Alpine (musl)

```
sudo apk add clang gcc binutils musl-dev diffutils gzip make bash git python3
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

`gcc` на Alpine нужен только ради `libgcc` и стартовых файлов C, с которыми линкует clang.

### Void

```
sudo xbps-install -Sy clang binutils diffutils gzip make bash git python3
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

### Другие дистрибутивы

Поставьте clang 18 или новее, заголовки библиотеки C, binutils, bash, gzip, diffutils и make через свой пакетный менеджер и запустите `./bootstrap.sh`.

### Linux на arm64 (Raspberry Pi, серверы, Asahi)

Те же команды, что и для вашего дистрибутива. Бутстрап пропускает шаги нативного бэкенда и собирает всё через LLVM.

## macOS

```
xcode-select --install
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

Xcode command line tools дают clang, `ld`, `make` и python3. Если используете LLVM из Homebrew, поставьте его первым в `PATH`. Работает на Apple Silicon и на Mac с Intel. Если `install.sh` просит, добавьте `~/.local/bin` в `PATH` в профиле оболочки.

## Windows

Поставьте WSL2 и дистрибутив Linux, дальше выполняйте шаги для Linux внутри него.

```
wsl --install -d Ubuntu-24.04
```

Откройте оболочку Ubuntu и выполните команды для Debian/Ubuntu. Клонируйте репозиторий внутри файловой системы WSL (например в `~`), а не в `/mnt/c`: так намного быстрее и концы строк остаются правильными.

## Docker

```
docker run --rm -it -v "$PWD":/src -w /src debian:stable sh -c "sh scripts/install-deps.sh && ./bootstrap.sh && bash"
```

## Если что-то не так

- `cmp: command not found`: поставьте diffutils.
- `cannot find crtbeginS.o` или `-lgcc` на Alpine: поставьте `gcc`.
- `ld: not found`: поставьте binutils.
- `error: the native backend only supports x86-64 Linux`: вы передали `--native` на другой системе, уберите флаг.
- При падении программа печатает `fatal: ...` и трассировку. `ZARK_CRASH_HANDLER=0` возвращает обычный core dump.
- Не используйте один `.zark-cache` на разных системах (например, каталог, смонтированный в Docker и из Linux, и из macOS): при смене системы удаляйте его.
- Компилятор кэширует объекты в `.zark-cache` рядом с местом запуска; удалите каталог, чтобы начать с чистого листа.
- Docker на Fedora с SELinux: рабочая директория в bind-mount имеет тип `user_home_t`, и `container_t` не может её прочитать (`bootstrap.sh: permission denied`). Монтируйте с `:z` (`-v "$PWD":/src:z`) или запускайте контейнер с `--security-opt label=disable`.
- Зависание в `tests/cbuild.sh`, если `clang` — обёртка ccache: это исправлено в `tests/compiler.sh`; если появилось снова, проверьте, что добавленный вами shim не запускает обёртку.
- `pthread_create: Resource temporarily unavailable` в тестах потоков: поднимите `ulimit -u` (набор тестов запускает много процессов и потоков).
