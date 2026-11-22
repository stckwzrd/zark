#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! cmp -s build/stage2.ll build/stage3.ll || ! cmp -s build/stage2 build/stage3; then
  echo "stage2 and stage3 differ: run ./bootstrap.sh first"; exit 1
fi
build/stage2 ir selfhost/main.zk | grep -v '^  ;@' | gzip -9n > bootstrap/seed.ll.gz
echo "seed updated: $(du -h bootstrap/seed.ll.gz | cut -f1), from stage2 $(sha256sum build/stage2 | cut -c1-16)"
