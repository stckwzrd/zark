# Установка Vibe

Vibe собирается из исходников одной командой. В репозитории лежит seed для бутстрапа (LLVM IR самого компилятора), поэтому нужен только clang.

```
git clone https://github.com/stckwzrd/vibe.git
cd vibe
sh scripts/install-deps.sh
./bootstrap.sh
./install.sh
```

- `scripts/install-deps.sh` ставит нужные инструменты через найденный пакетный менеджер (apt, dnf, pacman, apk, zypper, xbps). На macOS, если clang нет, он запускает установку Xcode command line tools.
- `./bootstrap.sh` собирает компилятор по стадиям, проверяет, что он воспроизводит сам себя, гоняет тесты и кладёт результат в `build/vibe`. Занимает несколько минут.
- `./install.sh` копирует `build/vibe` в `~/.local/bin` (другое место: `PREFIX=/usr/local ./install.sh`). Vibe это один бинарник, стандартная библиотека встроена.

Проверка:

```
vibe run examples/hello.vibe
```

## Что нужно

| Инструмент | Зачем |
|---|---|
| clang 18 или новее | собирает seed, линкует программы, работает для `--release` |
| библиотека C с заголовками | glibc, musl или SDK macOS |
| binutils (`ld`) | линковка на Linux |
| bash, gzip, diffutils, make | скрипт бутстрапа |
| python3 | только для тестов |

## Поддерживаемые системы

| Система | Статус | Бэкенд |
|---|---|---|
| Linux x86-64, glibc (Debian, Ubuntu, Fedora, Arch, openSUSE) | собирается и проверяется в CI | свой x86-64 бэкенд по умолчанию, LLVM через `--llvm` / `-O` |
| Linux x86-64, musl (Alpine) | собирается и проверяется в CI | то же |
| Linux arm64 | собирается в CI | только LLVM |
| macOS, Apple Silicon и Intel | собирается в CI | только LLVM |
| Windows | через WSL2, собирается в CI | как на Linux |

Windows без WSL не поддерживается: рантайм использует `fork`, `poll` и потоки POSIX.

Свой бэкенд пишет ELF для x86-64, поэтому он есть только на Linux x86-64. На остальных системах Vibe отдаёт LLVM IR в clang, это полностью поддерживаемый путь. `vibe build --native` там выдаёт ошибку.

Части языка, привязанные к x86 (`examples/baremetal`, порты ввода-вывода и привилегированные инструкции, функции `Atomic` в прелюдии), имеют смысл только на x86-64.

## Linux

### Debian, Ubuntu и производные

```
sudo apt-get update
sudo apt-get install -y clang binutils diffutils gzip make bash git python3
git clone https://github.com/stckwzrd/vibe.git && cd vibe
./bootstrap.sh && ./install.sh
```

### Fedora, RHEL, Rocky, Alma

```
sudo dnf install -y clang binutils diffutils gzip make bash git python3 glibc-devel
git clone https://github.com/stckwzrd/vibe.git && cd vibe
./bootstrap.sh && ./install.sh
```

### Arch, Manjaro

```
sudo pacman -Syu --needed clang binutils diffutils gzip make bash git python glibc linux-api-headers
git clone https://github.com/stckwzrd/vibe.git && cd vibe
./bootstrap.sh && ./install.sh
```

### openSUSE

```
sudo zypper install -y clang binutils diffutils gzip make bash git python3 glibc-devel
git clone https://github.com/stckwzrd/vibe.git && cd vibe
./bootstrap.sh && ./install.sh
```

### Alpine (musl)

```
sudo apk add clang gcc binutils musl-dev diffutils gzip make bash git python3
git clone https://github.com/stckwzrd/vibe.git && cd vibe
./bootstrap.sh && ./install.sh
```

`gcc` на Alpine нужен только ради `libgcc` и стартовых файлов C, с которыми линкует clang.

### Void

```
sudo xbps-install -Sy clang binutils diffutils gzip make bash git python3
git clone https://github.com/stckwzrd/vibe.git && cd vibe
./bootstrap.sh && ./install.sh
```

### Другие дистрибутивы

Поставьте clang 18 или новее, заголовки библиотеки C, binutils, bash, gzip, diffutils и make через свой пакетный менеджер и запустите `./bootstrap.sh`.

### Linux на arm64 (Raspberry Pi, серверы, Asahi)

Те же команды, что и для вашего дистрибутива. Бутстрап пропускает шаги нативного бэкенда и собирает всё через LLVM.

## macOS

```
xcode-select --install
git clone https://github.com/stckwzrd/vibe.git && cd vibe
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
- При падении программа печатает `fatal: ...` и трассировку. `VIBE_CRASH_HANDLER=0` возвращает обычный core dump.
- Компилятор кэширует объекты в `.vibe-cache` рядом с местом запуска; удалите каталог, чтобы начать с чистого листа.
