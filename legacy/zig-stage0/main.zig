const std = @import("std");
const lex = @import("lexer.zig");
const ast = @import("ast.zig");
const Parser = @import("parser.zig").Parser;
const Gen = @import("codegen.zig").Gen;

const prelude_src = @embedFile("std.vibe");
const version = "0.1.0";

fn usage() void {
    std.debug.print(
        \\vibe {s} — a compact systems language (LLVM backend)
        \\
        \\usage:
        \\  vibe run   <file.vibe> [extra.c|.cpp|.o ...] [-O] [-- program args]
        \\  vibe build <file.vibe> [extra.c|.cpp|.o ...] [-o out] [-O] [--no-safety]
        \\  vibe ir    <file.vibe>            print LLVM IR to stdout
        \\
        \\  -O            optimize (clang -O2) and keep safety checks
        \\  --release     -O2 and drop bounds checks
        \\
    , .{version});
}

const Loader = struct {
    alloc: std.mem.Allocator,
    gen: *Gen,
    seen: std.StringHashMap(void),

    fn loadSource(l: *Loader, src: []const u8, path: []const u8) !void {
        const toks = try lex.tokenize(l.alloc, src, path);
        var p = Parser.init(l.alloc, toks, path);
        const decls = try p.parseFile();
        // imports first, so declarations are visible
        const dir = std.fs.path.dirname(path) orelse ".";
        for (decls) |d| switch (d) {
            .import => |rel| {
                const full = try std.fs.path.resolve(l.alloc, &.{ dir, rel });
                try l.loadFile(full);
            },
            else => {},
        };
        try l.gen.addDecls(decls, path);
    }

    fn loadFile(l: *Loader, path: []const u8) anyerror!void {
        if (l.seen.contains(path)) return;
        try l.seen.put(path, {});
        const src = std.fs.cwd().readFileAlloc(l.alloc, path, 64 << 20) catch |err| {
            std.debug.print("error: cannot read '{s}': {s}\n", .{ path, @errorName(err) });
            return error.CompileFailed;
        };
        try l.loadSource(src, path);
    }
};

fn runCmd(alloc: std.mem.Allocator, argv: []const []const u8) !u8 {
    var child = std.process.Child.init(argv, alloc);
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |c| c,
        else => 1,
    };
}

fn endsWith(s: []const u8, suf: []const u8) bool {
    return std.mem.endsWith(u8, s, suf);
}

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const args = try std.process.argsAlloc(alloc);
    if (args.len < 3) {
        usage();
        return 1;
    }
    const cmd = args[1];
    const is_run = std.mem.eql(u8, cmd, "run");
    const is_build = std.mem.eql(u8, cmd, "build");
    const is_ir = std.mem.eql(u8, cmd, "ir");
    if (std.mem.eql(u8, cmd, "tokens")) {
        // debug: dump tokens (used to cross-check the self-hosted lexer)
        const out = std.io.getStdOut().writer();
        for (args[2..]) |path| {
            const src = try std.fs.cwd().readFileAlloc(alloc, path, 64 << 20);
            const toks = lex.tokenize(alloc, src, path) catch return 1;
            for (toks) |t| try out.print("{d} .{s} {s}\n", .{ t.line, @tagName(t.tag), t.text });
        }
        return 0;
    }
    if (!is_run and !is_build and !is_ir) {
        usage();
        return 1;
    }

    var src_file: ?[]const u8 = null;
    var extras = std.ArrayList([]const u8).init(alloc);
    var prog_args = std.ArrayList([]const u8).init(alloc);
    var out_path: ?[]const u8 = null;
    var opt = false;
    var safety = true;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--")) {
            for (args[i + 1 ..]) |x| try prog_args.append(x);
            break;
        } else if (std.mem.eql(u8, a, "-O")) {
            opt = true;
        } else if (std.mem.eql(u8, a, "--release")) {
            opt = true;
            safety = false;
        } else if (std.mem.eql(u8, a, "--no-safety")) {
            safety = false;
        } else if (std.mem.eql(u8, a, "-o")) {
            i += 1;
            if (i < args.len) out_path = args[i];
        } else if (endsWith(a, ".vibe")) {
            src_file = a;
        } else {
            try extras.append(a);
        }
    }
    const file = src_file orelse {
        usage();
        return 1;
    };

    const gen = try Gen.init(alloc, safety);
    var loader = Loader{ .alloc = alloc, .gen = gen, .seen = std.StringHashMap(void).init(alloc) };
    loader.loadSource(prelude_src, "<std>") catch return 1;
    loader.loadFile(file) catch return 1;
    gen.generate() catch return 1;

    var ir = std.ArrayList(u8).init(alloc);
    try gen.output(ir.writer());

    if (is_ir) {
        try std.io.getStdOut().writeAll(ir.items);
        return 0;
    }

    const cache = ".vibe-cache";
    std.fs.cwd().makePath(cache) catch {};
    const stem = std.fs.path.stem(file);
    const ll_path = try std.fmt.allocPrint(alloc, "{s}/{s}.ll", .{ cache, stem });
    try std.fs.cwd().writeFile(.{ .sub_path = ll_path, .data = ir.items });

    const exe = out_path orelse if (is_run) try std.fmt.allocPrint(alloc, "{s}/{s}", .{ cache, stem }) else stem;
    const olevel: []const u8 = if (opt) "-O2" else "-O0";

    var objs = std.ArrayList([]const u8).init(alloc);
    var needs_cxx = false;
    for (extras.items) |x| {
        if (endsWith(x, ".o") or endsWith(x, ".a") or endsWith(x, ".so") or std.mem.startsWith(u8, x, "-l") or std.mem.startsWith(u8, x, "-L")) {
            try objs.append(x);
            continue;
        }
        const is_cpp = endsWith(x, ".cpp") or endsWith(x, ".cc") or endsWith(x, ".cxx");
        if (is_cpp) needs_cxx = true;
        const obj = try std.fmt.allocPrint(alloc, "{s}/{s}.o", .{ cache, std.fs.path.basename(x) });
        const code = try runCmd(alloc, &.{ if (is_cpp) "clang++" else "clang", olevel, "-c", x, "-o", obj });
        if (code != 0) return code;
        try objs.append(obj);
    }

    var link = std.ArrayList([]const u8).init(alloc);
    try link.appendSlice(&.{ if (needs_cxx) "clang++" else "clang", olevel, "-Wno-override-module", ll_path });
    try link.appendSlice(objs.items);
    try link.appendSlice(&.{ "-o", exe, "-lm" });
    const lc = try runCmd(alloc, link.items);
    if (lc != 0) {
        std.debug.print("error: clang failed (IR kept at {s})\n", .{ll_path});
        return lc;
    }

    if (is_run) {
        var run_argv = std.ArrayList([]const u8).init(alloc);
        const exe_path = if (std.mem.indexOfScalar(u8, exe, '/') == null) try std.fmt.allocPrint(alloc, "./{s}", .{exe}) else exe;
        try run_argv.append(exe_path);
        try run_argv.appendSlice(prog_args.items);
        return runCmd(alloc, run_argv.items);
    }
    return 0;
}
