#!/usr/bin/env bash
cd "$(dirname "$0")/.."
FILES="selfhost/gen.vibe selfhost/gen_*.vibe selfhost/parser.vibe selfhost/loader.vibe selfhost/resolve.vibe selfhost/lexer.vibe"
NAMES='List|Map|Allocator|Arena|FixedBuf|StrBuf|println|print|eprint|eprintln|bprint|sprint|sort|min|max|swap|abs|c_allocator|cstr|parse_int|read_file|write_file|memcpy|malloc|calloc|free'
bad=$(grep -nE "\"($NAMES)\"" $FILES)
protocol='Fmt|Writer|FmtPiece|Option|panic|assert|embed|asm|sizeof|alignof|main|Self'
other=$(grep -noE '"__[a-z_]+"' $FILES | grep -vE '"__(panic|errname|oob|oobs|ovf|divz|str_eq|argc|argv|rt_init|ct_emit|ct_emit_str)"')
if [ -n "$bad$other" ]; then
  echo "FAIL compiler sources mention standard library names:"
  echo "$bad"
  echo "$other"
  exit 1
fi
echo "ok   no standard library names in the compiler (allowed protocol: $protocol, __panic, __errname, __oob, __str_eq, __rt_init)"
