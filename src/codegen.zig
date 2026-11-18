const std = @import("std");
const ast = @import("ast.zig");
const Tag = @import("lexer.zig").Tag;

pub const Error = error{ CompileFailed, OutOfMemory };

// ============================================================ types

pub const StructInst = struct {
    decl: *ast.StructDecl,
    args: []*const Type,
    llname: []const u8,
    display: []const u8,
    fields: []FieldInfo,
    ready: bool = false,
    names_global: []const u8 = "", // unions: variant names table
    payload_words: u64 = 0, // unions: payload size in 8-byte words
};
pub const FuncSig = struct { params: []*const Type, ret: *const Type };
pub const FieldInfo = struct { name: []const u8, ty: *const Type };

pub const EnumInfo = struct {
    decl: *ast.EnumDecl,
    names_global: []const u8,
};

pub const Type = union(enum) {
    int: struct { bits: u16, signed: bool },
    float: u16,
    boolean,
    void_,
    ptr: *const Type,
    slice: *const Type,
    array: struct { len: u64, elem: *const Type },
    strct: *StructInst,
    enm: *EnumInfo,
    errun: *const Type,
    errval,
    null_t,
    func: *const FuncSig,
};

fn typeEq(a: *const Type, b: *const Type) bool {
    if (a == b) return true;
    return switch (a.*) {
        .int => |x| b.* == .int and b.int.bits == x.bits and b.int.signed == x.signed,
        .float => |x| b.* == .float and b.float == x,
        .boolean => b.* == .boolean,
        .void_ => b.* == .void_,
        .ptr => |x| b.* == .ptr and typeEq(x, b.ptr),
        .slice => |x| b.* == .slice and typeEq(x, b.slice),
        .array => |x| b.* == .array and b.array.len == x.len and typeEq(x.elem, b.array.elem),
        .strct => |x| b.* == .strct and b.strct == x,
        .enm => |x| b.* == .enm and b.enm == x,
        .errun => |x| b.* == .errun and typeEq(x, b.errun),
        .errval => b.* == .errval,
        .null_t => b.* == .null_t,
        .func => |x| blk: {
            if (b.* != .func or b.func.params.len != x.params.len or !typeEq(x.ret, b.func.ret)) break :blk false;
            for (x.params, 0..) |p, i| if (!typeEq(p, b.func.params[i])) break :blk false;
            break :blk true;
        },
    };
}

fn isUnion(t: *const Type) bool {
    return t.* == .strct and t.strct.decl.is_union;
}

fn isStr(t: *const Type) bool {
    return t.* == .slice and t.slice.* == .int and t.slice.int.bits == 8 and !t.slice.int.signed;
}

const Value = struct { ty: *const Type, v: []const u8 };
const Addr = struct { ty: *const Type, v: []const u8, imm: bool };

const Var = struct { ptr: []const u8, ty: *const Type, mutable: bool };
const Defer = struct { stmt: *ast.Stmt, is_err: bool };
const Scope = struct {
    vars: std.StringHashMap(Var),
    defers: std.ArrayList(Defer),
};
const Loop = struct { brk: []const u8, cont: []const u8, depth: usize };

const Env = std.StringHashMap(*const Type);

const FnInst = struct {
    decl: *ast.FnDecl,
    env: Env,
    llname: []const u8,
    params: []*const Type,
    ret: *const Type,
    generated: bool = false,
};

const FmtBuilder = struct {
    fmt: std.ArrayList(u8),
    args: std.ArrayList(u8),
    string_mode: bool,
};

// ============================================================ generator

pub const Gen = struct {
    alloc: std.mem.Allocator,
    safety: bool,

    fns: std.StringHashMap(*ast.FnDecl),
    methods: std.StringHashMap(*ast.FnDecl),
    structs: std.StringHashMap(*ast.StructDecl),
    enums: std.StringHashMap(*EnumInfo),
    consts: std.StringHashMap(*ast.ConstDecl),
    aliases: std.StringHashMap(*ast.TypeExpr),
    globals: std.StringHashMap(Var),

    struct_insts: std.StringHashMap(*StructInst),
    fn_insts: std.StringHashMap(*FnInst),
    pending: std.ArrayList(*FnInst),
    declared: std.StringHashMap(void),
    errors: std.StringHashMap(u32),
    error_names: std.ArrayList([]const u8),

    types_out: std.ArrayList(u8),
    globals_out: std.ArrayList(u8),
    decls_out: std.ArrayList(u8),
    funcs_out: std.ArrayList(u8),
    nstr: u32 = 0,

    // per function
    body: std.ArrayList(u8),
    allocas: std.ArrayList(u8),
    ntmp: u32 = 0,
    nlbl: u32 = 0,
    scopes: std.ArrayList(Scope),
    loops: std.ArrayList(Loop),
    cur: ?*FnInst = null,
    env: Env,
    terminated: bool = false,
    cur_label: []const u8 = "entry",
    file: []const u8 = "",

    // builtin types
    t_i64: *const Type = undefined,
    t_i32: *const Type = undefined,
    t_u64: *const Type = undefined,
    t_u8: *const Type = undefined,
    t_f64: *const Type = undefined,
    t_bool: *const Type = undefined,
    t_void: *const Type = undefined,
    t_str: *const Type = undefined,
    t_errval: *const Type = undefined,
    t_null: *const Type = undefined,
    t_ptr_u8: *const Type = undefined,

    pub fn init(alloc: std.mem.Allocator, safety: bool) Error!*Gen {
        const g = try alloc.create(Gen);
        g.* = .{
            .alloc = alloc,
            .safety = safety,
            .fns = std.StringHashMap(*ast.FnDecl).init(alloc),
            .methods = std.StringHashMap(*ast.FnDecl).init(alloc),
            .structs = std.StringHashMap(*ast.StructDecl).init(alloc),
            .enums = std.StringHashMap(*EnumInfo).init(alloc),
            .consts = std.StringHashMap(*ast.ConstDecl).init(alloc),
            .aliases = std.StringHashMap(*ast.TypeExpr).init(alloc),
            .globals = std.StringHashMap(Var).init(alloc),
            .struct_insts = std.StringHashMap(*StructInst).init(alloc),
            .fn_insts = std.StringHashMap(*FnInst).init(alloc),
            .pending = std.ArrayList(*FnInst).init(alloc),
            .declared = std.StringHashMap(void).init(alloc),
            .errors = std.StringHashMap(u32).init(alloc),
            .error_names = std.ArrayList([]const u8).init(alloc),
            .types_out = std.ArrayList(u8).init(alloc),
            .globals_out = std.ArrayList(u8).init(alloc),
            .decls_out = std.ArrayList(u8).init(alloc),
            .funcs_out = std.ArrayList(u8).init(alloc),
            .body = std.ArrayList(u8).init(alloc),
            .allocas = std.ArrayList(u8).init(alloc),
            .scopes = std.ArrayList(Scope).init(alloc),
            .loops = std.ArrayList(Loop).init(alloc),
            .env = Env.init(alloc),
        };
        g.t_i64 = try g.mk(.{ .int = .{ .bits = 64, .signed = true } });
        g.t_i32 = try g.mk(.{ .int = .{ .bits = 32, .signed = true } });
        g.t_u64 = try g.mk(.{ .int = .{ .bits = 64, .signed = false } });
        g.t_u8 = try g.mk(.{ .int = .{ .bits = 8, .signed = false } });
        g.t_f64 = try g.mk(.{ .float = 64 });
        g.t_bool = try g.mk(.boolean);
        g.t_void = try g.mk(.void_);
        g.t_str = try g.mk(.{ .slice = g.t_u8 });
        g.t_errval = try g.mk(.errval);
        g.t_null = try g.mk(.null_t);
        g.t_ptr_u8 = try g.mk(.{ .ptr = g.t_u8 });
        try g.error_names.append("ok");
        return g;
    }

    fn mk(g: *Gen, t: Type) Error!*const Type {
        const p = try g.alloc.create(Type);
        p.* = t;
        return p;
    }

    fn fmt(g: *Gen, comptime f: []const u8, args: anytype) Error![]const u8 {
        return std.fmt.allocPrint(g.alloc, f, args);
    }

    fn fail(g: *Gen, line: u32, comptime f: []const u8, args: anytype) Error {
        std.debug.print("{s}:{d}: error: ", .{ g.file, line });
        std.debug.print(f, args);
        std.debug.print("\n", .{});
        return error.CompileFailed;
    }

    // ------------------------------------------------ registration

    pub fn addDecls(g: *Gen, decls: []ast.Decl, file: []const u8) Error!void {
        g.file = file;
        for (decls) |d| switch (d) {
            .func => |f| {
                if (f.receiver) |r| {
                    const key = try g.fmt("{s}.{s}", .{ r, f.name });
                    if (g.methods.contains(key)) return g.fail(f.line, "duplicate method '{s}'", .{key});
                    try g.methods.put(key, f);
                } else {
                    if (g.fns.get(f.name)) |old| {
                        if (old.is_extern and f.is_extern) continue; // same extern imported twice
                        return g.fail(f.line, "duplicate function '{s}'", .{f.name});
                    }
                    try g.fns.put(f.name, f);
                }
            },
            .strct => |s| {
                if (g.structs.contains(s.name)) return g.fail(s.line, "duplicate struct '{s}'", .{s.name});
                try g.structs.put(s.name, s);
            },
            .enm => |e| {
                const info = try g.alloc.create(EnumInfo);
                info.* = .{ .decl = e, .names_global = try g.fmt("@enum.{s}.names", .{e.name}) };
                try g.enums.put(e.name, info);
                // name table for printing
                const w = g.globals_out.writer();
                var refs = std.ArrayList(u8).init(g.alloc);
                for (e.variants, 0..) |v, i| {
                    const s = try g.strGlobal(v);
                    if (i > 0) try refs.appendSlice(", ");
                    try refs.writer().print("ptr {s}", .{s});
                }
                try w.print("{s} = private constant [{d} x ptr] [{s}]\n", .{ info.names_global, e.variants.len, refs.items });
            },
            .constant => |c| {
                try g.consts.put(c.name, c);
            },
            .import => {},
            .alias => |al| {
                if (g.aliases.contains(al.name) or g.structs.contains(al.name)) return g.fail(al.line, "duplicate type name '{s}'", .{al.name});
                try g.aliases.put(al.name, al.ty);
            },
        };
    }

    fn emitGlobalVar(g: *Gen, c: *ast.ConstDecl) Error!void {
        var ty: *const Type = undefined;
        var init_s: []const u8 = undefined;
        if (c.ty) |te| {
            ty = try g.resolveType(te, &g.env);
        } else ty = switch (c.value.kind) {
            .float_lit => g.t_f64,
            .bool_lit => g.t_bool,
            else => g.t_i64,
        };
        switch (ty.*) {
            .int => init_s = try g.fmt("{d}", .{try g.evalConst(c.value)}),
            .boolean => init_s = if (c.value.kind == .bool_lit and c.value.kind.bool_lit) "true" else "false",
            .float => init_s = try g.floatConst(switch (c.value.kind) {
                .float_lit => |f| f,
                else => @as(f64, @floatFromInt(try g.evalConst(c.value))),
            }, ty.float),
            else => init_s = "zeroinitializer",
        }
        const name = try g.fmt("@g.{s}", .{c.name});
        try g.globals_out.writer().print("{s} = global {s} {s}\n", .{ name, try g.llty(ty), init_s });
        try g.globals.put(c.name, .{ .ptr = name, .ty = ty, .mutable = true });
    }

    // ------------------------------------------------ type helpers

    fn llty(g: *Gen, t: *const Type) Error![]const u8 {
        return switch (t.*) {
            .int => |i| try g.fmt("i{d}", .{i.bits}),
            .float => |f| if (f == 32) "float" else "double",
            .boolean => "i1",
            .void_ => "void",
            .ptr, .null_t, .func => "ptr",
            .slice => "{ ptr, i64 }",
            .array => |a| try g.fmt("[{d} x {s}]", .{ a.len, try g.llty(a.elem) }),
            .strct => |s| try g.fmt("%\"{s}\"", .{s.llname}),
            .enm, .errval => "i32",
            .errun => |inner| if (inner.* == .void_) "{ i32 }" else try g.fmt("{{ i32, {s} }}", .{try g.llty(inner)}),
        };
    }

    fn mangle(g: *Gen, t: *const Type) Error![]const u8 {
        return switch (t.*) {
            .int => |i| try g.fmt("{c}{d}", .{ @as(u8, if (i.signed) 'i' else 'u'), i.bits }),
            .float => |f| try g.fmt("f{d}", .{f}),
            .boolean => "bool",
            .void_ => "void",
            .null_t => "null",
            .ptr => |p| try g.fmt("P{s}", .{try g.mangle(p)}),
            .slice => |p| try g.fmt("S{s}", .{try g.mangle(p)}),
            .array => |a| try g.fmt("A{d}{s}", .{ a.len, try g.mangle(a.elem) }),
            .strct => |s| s.llname,
            .enm => |e| e.decl.name,
            .errun => |inner| try g.fmt("E{s}", .{try g.mangle(inner)}),
            .errval => "error",
            .func => |f| blk: {
                var b = std.ArrayList(u8).init(g.alloc);
                try b.writer().print("F{d}", .{f.params.len});
                for (f.params) |p| try b.writer().print("_{s}", .{try g.mangle(p)});
                try b.writer().print("_R{s}", .{try g.mangle(f.ret)});
                break :blk b.items;
            },
        };
    }

    pub fn typeName(g: *Gen, t: *const Type) Error![]const u8 {
        if (isStr(t)) return "str";
        return switch (t.*) {
            .int => |i| try g.fmt("{c}{d}", .{ @as(u8, if (i.signed) 'i' else 'u'), i.bits }),
            .float => |f| try g.fmt("f{d}", .{f}),
            .boolean => "bool",
            .void_ => "void",
            .null_t => "null",
            .ptr => |p| try g.fmt("*{s}", .{try g.typeName(p)}),
            .slice => |p| try g.fmt("[]{s}", .{try g.typeName(p)}),
            .array => |a| try g.fmt("[{d}]{s}", .{ a.len, try g.typeName(a.elem) }),
            .strct => |s| s.display,
            .enm => |e| e.decl.name,
            .errun => |inner| try g.fmt("!{s}", .{try g.typeName(inner)}),
            .errval => "error",
            .func => |f| blk: {
                var b = std.ArrayList(u8).init(g.alloc);
                try b.appendSlice("fn(");
                for (f.params, 0..) |p, i| {
                    if (i > 0) try b.appendSlice(", ");
                    try b.appendSlice(try g.typeName(p));
                }
                try b.append(')');
                if (f.ret.* != .void_) try b.writer().print(" {s}", .{try g.typeName(f.ret)});
                break :blk b.items;
            },
        };
    }

    fn resolveType(g: *Gen, te: *ast.TypeExpr, env: *Env) Error!*const Type {
        switch (te.*) {
            .ptr => |p| return g.mk(.{ .ptr = try g.resolveType(p, env) }),
            .slice => |p| return g.mk(.{ .slice = try g.resolveType(p, env) }),
            .errun => |p| return g.mk(.{ .errun = try g.resolveType(p, env) }),
            .func => |f| {
                var ps = std.ArrayList(*const Type).init(g.alloc);
                for (f.params) |p| try ps.append(try g.resolveType(p, env));
                const sig = try g.alloc.create(FuncSig);
                sig.* = .{ .params = try ps.toOwnedSlice(), .ret = if (f.ret) |r| try g.resolveType(r, env) else g.t_void };
                return g.mk(.{ .func = sig });
            },
            .array => |a| {
                const n = try g.evalConst(a.len);
                if (n < 0) return g.fail(a.len.line, "negative array length", .{});
                return g.mk(.{ .array = .{ .len = @intCast(n), .elem = try g.resolveType(a.elem, env) } });
            },
            .name => |n| {
                if (n.args.len == 0) {
                    if (env.get(n.name)) |t| return t;
                    if (builtinType(n.name)) |bt| return g.mk(bt);
                    if (std.mem.eql(u8, n.name, "str")) return g.t_str;
                    if (g.enums.get(n.name)) |e| return g.mk(.{ .enm = e });
                    if (g.aliases.get(n.name)) |at| {
                        var empty = Env.init(g.alloc);
                        return g.resolveType(at, &empty);
                    }
                }
                if (g.structs.get(n.name)) |sd| {
                    if (sd.type_params.len != n.args.len)
                        return g.fail(sd.line, "struct '{s}' expects {d} type argument(s), got {d}", .{ n.name, sd.type_params.len, n.args.len });
                    var args = std.ArrayList(*const Type).init(g.alloc);
                    for (n.args) |a| try args.append(try g.resolveType(a, env));
                    const inst = try g.getStruct(sd, try args.toOwnedSlice());
                    return g.mk(.{ .strct = inst });
                }
                return g.fail(0, "unknown type '{s}'", .{n.name});
            },
        }
    }

    fn builtinType(name: []const u8) ?Type {
        const M = struct { n: []const u8, t: Type };
        const table = [_]M{
            .{ .n = "i8", .t = .{ .int = .{ .bits = 8, .signed = true } } },
            .{ .n = "i16", .t = .{ .int = .{ .bits = 16, .signed = true } } },
            .{ .n = "i32", .t = .{ .int = .{ .bits = 32, .signed = true } } },
            .{ .n = "i64", .t = .{ .int = .{ .bits = 64, .signed = true } } },
            .{ .n = "isize", .t = .{ .int = .{ .bits = 64, .signed = true } } },
            .{ .n = "u8", .t = .{ .int = .{ .bits = 8, .signed = false } } },
            .{ .n = "u16", .t = .{ .int = .{ .bits = 16, .signed = false } } },
            .{ .n = "u32", .t = .{ .int = .{ .bits = 32, .signed = false } } },
            .{ .n = "u64", .t = .{ .int = .{ .bits = 64, .signed = false } } },
            .{ .n = "usize", .t = .{ .int = .{ .bits = 64, .signed = false } } },
            .{ .n = "f32", .t = .{ .float = 32 } },
            .{ .n = "f64", .t = .{ .float = 64 } },
            .{ .n = "bool", .t = .boolean },
            .{ .n = "void", .t = .void_ },
        };
        for (table) |e| if (std.mem.eql(u8, e.n, name)) return e.t;
        return null;
    }

    fn getStruct(g: *Gen, sd: *ast.StructDecl, args: []*const Type) Error!*StructInst {
        var name = std.ArrayList(u8).init(g.alloc);
        var disp = std.ArrayList(u8).init(g.alloc);
        try name.appendSlice(sd.name);
        try disp.appendSlice(sd.name);
        if (args.len > 0) try disp.append('[');
        for (args, 0..) |a, i| {
            try name.writer().print(".{s}", .{try g.mangle(a)});
            if (i > 0) try disp.appendSlice(", ");
            try disp.appendSlice(try g.typeName(a));
        }
        if (args.len > 0) try disp.append(']');
        if (g.struct_insts.get(name.items)) |s| return s;
        const inst = try g.alloc.create(StructInst);
        inst.* = .{ .decl = sd, .args = args, .llname = name.items, .display = disp.items, .fields = &.{} };
        try g.struct_insts.put(name.items, inst);
        var env = Env.init(g.alloc);
        for (sd.type_params, 0..) |tp, i| try env.put(tp, args[i]);
        var fields = std.ArrayList(FieldInfo).init(g.alloc);
        for (sd.fields) |f| try fields.append(.{ .name = f.name, .ty = try g.resolveType(f.ty, &env) });
        inst.fields = try fields.toOwnedSlice();
        const w = g.types_out.writer();
        if (sd.is_union) {
            var maxsz: u64 = 0;
            var refs = std.ArrayList(u8).init(g.alloc);
            for (inst.fields, 0..) |f, i| {
                maxsz = @max(maxsz, try g.sizeOf(f.ty));
                if (i > 0) try refs.appendSlice(", ");
                try refs.writer().print("ptr {s}", .{try g.strGlobal(f.name)});
            }
            inst.payload_words = (maxsz + 7) / 8;
            inst.names_global = try g.fmt("@union.{s}.names", .{inst.llname});
            try g.globals_out.writer().print("{s} = private constant [{d} x ptr] [{s}]\n", .{ inst.names_global, inst.fields.len, refs.items });
            try w.print("%\"{s}\" = type {{ i32, [{d} x i64] }}\n", .{ inst.llname, inst.payload_words });
            inst.ready = true;
            return inst;
        }
        try w.print("%\"{s}\" = type {{ ", .{inst.llname});
        for (inst.fields, 0..) |f, i| {
            if (i > 0) try w.writeAll(", ");
            try w.writeAll(try g.llty(f.ty));
        }
        try w.writeAll(" }\n");
        inst.ready = true;
        return inst;
    }

    fn evalConst(g: *Gen, e: *ast.Expr) Error!i64 {
        switch (e.kind) {
            .int_lit => |v| return @bitCast(v),
            .ident => |n| {
                if (g.consts.get(n)) |c| if (!c.mutable) return g.evalConst(c.value);
                return g.fail(e.line, "'{s}' is not a compile-time constant", .{n});
            },
            .unary => |u| {
                const v = try g.evalConst(u.e);
                return switch (u.op) {
                    .minus => -%v,
                    .tilde => ~v,
                    else => g.fail(e.line, "unsupported operator in constant expression", .{}),
                };
            },
            .binary => |b| {
                const l = try g.evalConst(b.l);
                const r = try g.evalConst(b.r);
                return switch (b.op) {
                    .plus => l +% r,
                    .minus => l -% r,
                    .star => l *% r,
                    .slash => if (r == 0) g.fail(e.line, "division by zero in constant", .{}) else @divTrunc(l, r),
                    .percent => if (r == 0) g.fail(e.line, "division by zero in constant", .{}) else @rem(l, r),
                    .shl => l << @intCast(r & 63),
                    .shr => l >> @intCast(r & 63),
                    .amp => l & r,
                    .pipe => l | r,
                    .caret => l ^ r,
                    else => g.fail(e.line, "unsupported operator in constant expression", .{}),
                };
            },
            .sizeof => |te| return @intCast(try g.sizeOf(try g.resolveType(te, &g.env))),
            .alignof => |te| return @intCast(try g.alignOf(try g.resolveType(te, &g.env))),
            else => return g.fail(e.line, "expression is not a compile-time constant", .{}),
        }
    }

    fn sizeOf(g: *Gen, t: *const Type) Error!u64 {
        return switch (t.*) {
            .int => |i| i.bits / 8,
            .float => |f| f / 8,
            .boolean => 1,
            .void_ => 0,
            .ptr, .null_t => 8,
            .slice => 16,
            .func => 8,
            .enm, .errval => 4,
            .array => |a| a.len * try g.sizeOf(a.elem),
            .strct => |s| blk: {
                if (s.decl.is_union) break :blk 8 + 8 * s.payload_words;
                var off: u64 = 0;
                var maxa: u64 = 1;
                for (s.fields) |f| {
                    const sz = try g.sizeOf(f.ty);
                    const al = try g.alignOf(f.ty);
                    maxa = @max(maxa, al);
                    off = (off + al - 1) / al * al + sz;
                }
                break :blk (off + maxa - 1) / maxa * maxa;
            },
            .errun => |inner| blk: {
                const al: u64 = @max(4, try g.alignOf(inner));
                const off = (4 + al - 1) / al * al;
                const total = off + try g.sizeOf(inner);
                break :blk (total + al - 1) / al * al;
            },
        };
    }

    fn alignOf(g: *Gen, t: *const Type) Error!u64 {
        return switch (t.*) {
            .array => |a| try g.alignOf(a.elem),
            .strct => |s| blk: {
                if (s.decl.is_union) break :blk 8;
                var m: u64 = 1;
                for (s.fields) |f| m = @max(m, try g.alignOf(f.ty));
                break :blk m;
            },
            .slice => 8,
            .errun => |inner| @max(4, try g.alignOf(inner)),
            .void_ => 1,
            else => @max(1, try g.sizeOf(t)),
        };
    }

    // ------------------------------------------------ emission helpers

    fn strGlobal(g: *Gen, bytes: []const u8) Error![]const u8 {
        g.nstr += 1;
        const name = try g.fmt("@.str.{d}", .{g.nstr});
        const w = g.globals_out.writer();
        try w.print("{s} = private unnamed_addr constant [{d} x i8] c\"", .{ name, bytes.len + 1 });
        for (bytes) |b| {
            if (b >= 0x20 and b < 0x7f and b != '"' and b != '\\') try w.writeByte(b) else try w.print("\\{X:0>2}", .{b});
        }
        try w.writeAll("\\00\"\n");
        return name;
    }

    fn floatConst(g: *Gen, f: f64, bits: u16) Error![]const u8 {
        var v = f;
        if (bits == 32) {
            const x: f32 = @floatCast(f);
            v = x;
        }
        const u: u64 = @bitCast(v);
        return g.fmt("0x{X:0>16}", .{u});
    }

    fn tmp(g: *Gen) Error![]const u8 {
        g.ntmp += 1;
        return g.fmt("%t{d}", .{g.ntmp});
    }

    fn newLabel(g: *Gen, base: []const u8) Error![]const u8 {
        g.nlbl += 1;
        return g.fmt("{s}{d}", .{ base, g.nlbl });
    }

    fn emit(g: *Gen, comptime f: []const u8, args: anytype) Error!void {
        if (g.terminated) {
            const l = try g.newLabel("dead");
            try g.label(l);
        }
        try g.body.writer().print("  " ++ f ++ "\n", args);
    }

    fn emitTerm(g: *Gen, comptime f: []const u8, args: anytype) Error!void {
        try g.emit(f, args);
        g.terminated = true;
    }

    fn label(g: *Gen, name: []const u8) Error!void {
        if (!g.terminated) try g.body.writer().print("  br label %{s}\n", .{name});
        try g.body.writer().print("{s}:\n", .{name});
        g.cur_label = name;
        g.terminated = false;
    }

    fn br(g: *Gen, l: []const u8) Error!void {
        try g.emitTerm("br label %{s}", .{l});
    }

    fn alloca(g: *Gen, ty: *const Type, hint: []const u8) Error![]const u8 {
        g.ntmp += 1;
        const name = try g.fmt("%v.{s}.{d}", .{ hint, g.ntmp });
        try g.allocas.writer().print("  {s} = alloca {s}\n", .{ name, try g.llty(ty) });
        return name;
    }

    /// zero memory of type `ty` at `ptr`; aggregates use llvm.memset (big aggregate stores choke LLVM's isel)
    fn zeroFill(g: *Gen, ty: *const Type, ptr: []const u8) Error!void {
        switch (ty.*) {
            .array, .strct => {
                try g.declare("llvm.memset.p0.i64", "declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)");
                const gp = try g.tmp();
                try g.emit("{s} = getelementptr {s}, ptr null, i32 1", .{ gp, try g.llty(ty) });
                const sz = try g.tmp();
                try g.emit("{s} = ptrtoint ptr {s} to i64", .{ sz, gp });
                try g.emit("call void @llvm.memset.p0.i64(ptr {s}, i8 0, i64 {s}, i1 false)", .{ ptr, sz });
            },
            else => try g.emit("store {s} zeroinitializer, ptr {s}", .{ try g.llty(ty), ptr }),
        }
    }

    fn load(g: *Gen, ty: *const Type, ptr: []const u8) Error!Value {
        const t = try g.tmp();
        try g.emit("{s} = load {s}, ptr {s}", .{ t, try g.llty(ty), ptr });
        return .{ .ty = ty, .v = t };
    }

    fn store(g: *Gen, v: Value, ptr: []const u8) Error!void {
        if (v.ty.* == .void_) return;
        try g.emit("store {s} {s}, ptr {s}", .{ try g.llty(v.ty), v.v, ptr });
    }

    fn extract(g: *Gen, agg: Value, idx: usize, ty: *const Type) Error!Value {
        const t = try g.tmp();
        try g.emit("{s} = extractvalue {s} {s}, {d}", .{ t, try g.llty(agg.ty), agg.v, idx });
        return .{ .ty = ty, .v = t };
    }

    fn insert(g: *Gen, agg_ty: *const Type, agg: []const u8, v: Value, idx: usize) Error![]const u8 {
        const t = try g.tmp();
        try g.emit("{s} = insertvalue {s} {s}, {s} {s}, {d}", .{ t, try g.llty(agg_ty), agg, try g.llty(v.ty), v.v, idx });
        return t;
    }

    fn declare(g: *Gen, name: []const u8, text: []const u8) Error!void {
        if (g.declared.contains(name)) return;
        try g.declared.put(name, {});
        try g.decls_out.writer().print("{s}\n", .{text});
    }

    fn errorId(g: *Gen, name: []const u8) Error!u32 {
        if (g.errors.get(name)) |id| return id;
        const id: u32 = @intCast(g.error_names.items.len);
        try g.error_names.append(name);
        try g.errors.put(name, id);
        return id;
    }

    // ------------------------------------------------ scopes

    fn pushScope(g: *Gen) Error!void {
        try g.scopes.append(.{ .vars = std.StringHashMap(Var).init(g.alloc), .defers = std.ArrayList(Defer).init(g.alloc) });
    }

    fn popScope(g: *Gen) Error!void {
        const idx = g.scopes.items.len - 1;
        if (!g.terminated) try g.runDefers(idx, idx, false);
        _ = g.scopes.pop();
    }

    /// run defers of scopes[from_hi] down to scopes[to_lo] (inclusive), innermost first
    fn runDefers(g: *Gen, from_hi: usize, to_lo: usize, is_err: bool) Error!void {
        var i: usize = from_hi + 1;
        while (i > to_lo) {
            i -= 1;
            var j: usize = g.scopes.items[i].defers.items.len;
            while (j > 0) {
                j -= 1;
                const d = g.scopes.items[i].defers.items[j];
                if (d.is_err and !is_err) continue;
                try g.pushScope();
                try g.genStmt(d.stmt);
                try g.popScope();
            }
        }
    }

    fn declareVar(g: *Gen, name: []const u8, v: Var, line: u32) Error!void {
        const sc = &g.scopes.items[g.scopes.items.len - 1];
        if (sc.vars.contains(name)) return g.fail(line, "'{s}' is already declared in this scope", .{name});
        try sc.vars.put(name, v);
    }

    fn lookupVar(g: *Gen, name: []const u8) ?Var {
        var i = g.scopes.items.len;
        while (i > 0) {
            i -= 1;
            if (g.scopes.items[i].vars.get(name)) |v| return v;
        }
        return g.globals.get(name);
    }

    // ------------------------------------------------ functions

    fn instFn(g: *Gen, decl: *ast.FnDecl, env: Env, type_args: []*const Type) Error!*FnInst {
        var name = std.ArrayList(u8).init(g.alloc);
        if (decl.is_extern or decl.is_export) {
            try name.appendSlice(decl.name);
        } else {
            try name.appendSlice("vb.");
            if (decl.receiver != null) {
                try name.appendSlice(try g.mangle(env.get("Self").?));
                try name.append('.');
            }
            try name.appendSlice(decl.name);
            for (type_args) |a| try name.writer().print(".{s}", .{try g.mangle(a)});
        }
        if (g.fn_insts.get(name.items)) |fi| return fi;

        const saved_file = g.file;
        g.file = decl.file;
        defer g.file = saved_file;
        var envc = env;
        var params = std.ArrayList(*const Type).init(g.alloc);
        for (decl.params) |p| try params.append(try g.resolveType(p.ty, &envc));
        const ret = if (decl.ret) |r| try g.resolveType(r, &envc) else g.t_void;
        const fi = try g.alloc.create(FnInst);
        fi.* = .{ .decl = decl, .env = env, .llname = name.items, .params = try params.toOwnedSlice(), .ret = ret };
        try g.fn_insts.put(name.items, fi);
        if (decl.is_extern) {
            var txt = std.ArrayList(u8).init(g.alloc);
            try txt.writer().print("declare {s} @{s}(", .{ try g.llty(ret), decl.name });
            for (fi.params, 0..) |p, i| {
                if (i > 0) try txt.appendSlice(", ");
                try txt.appendSlice(try g.llty(p));
            }
            if (decl.variadic) try txt.appendSlice(if (fi.params.len > 0) ", ..." else "...");
            try txt.append(')');
            try g.declare(decl.name, txt.items);
        } else {
            try g.pending.append(fi);
        }
        return fi;
    }

    pub fn generate(g: *Gen) Error!void {
        var cit = g.consts.valueIterator();
        while (cit.next()) |c| {
            if (c.*.mutable) try g.emitGlobalVar(c.*);
        }
        const main_decl = g.fns.get("main");
        var main_inst: ?*FnInst = null;
        if (main_decl) |m| {
            if (m.type_params.len > 0 or m.params.len > 0) return g.fail(m.line, "main takes no parameters", .{});
            main_inst = try g.instFn(m, Env.init(g.alloc), &.{});
        }
        var it = g.fns.valueIterator();
        while (it.next()) |f| {
            if (f.*.is_export) _ = try g.instFn(f.*, Env.init(g.alloc), &.{});
        }
        while (g.pending.items.len > 0) {
            const fi = g.pending.pop();
            if (fi.generated) continue;
            fi.generated = true;
            try g.genFunction(fi);
        }
        if (main_inst) |mi| try g.genMainWrapper(mi);
        // error names table
        var refs = std.ArrayList(u8).init(g.alloc);
        for (g.error_names.items, 0..) |n, i| {
            const s = try g.strGlobal(n);
            if (i > 0) try refs.appendSlice(", ");
            try refs.writer().print("ptr {s}", .{s});
        }
        try g.globals_out.writer().print("@__vibe_errnames = private constant [{d} x ptr] [{s}]\n", .{ g.error_names.items.len, refs.items });
    }

    pub fn output(g: *Gen, w: anytype) !void {
        try w.writeAll("; generated by vibe\n");
        try w.writeAll(g.types_out.items);
        try w.writeAll("\n");
        try w.writeAll(g.globals_out.items);
        try w.writeAll("\n");
        try w.writeAll(g.decls_out.items);
        try w.writeAll("\n");
        try w.writeAll(g.funcs_out.items);
    }

    fn genMainWrapper(g: *Gen, mi: *FnInst) Error!void {
        const w = g.funcs_out.writer();
        try w.writeAll("define i32 @main(i32 %argc, ptr %argv) {\nentry:\n");
        if (g.globals.contains("__argc")) try w.writeAll("  %argc64 = sext i32 %argc to i64\n  store i64 %argc64, ptr @g.__argc\n  store ptr %argv, ptr @g.__argv\n");
        const rt = mi.ret;
        switch (rt.*) {
            .void_ => try w.print("  call void @{s}()\n  ret i32 0\n", .{mi.llname}),
            .int => |i| {
                try w.print("  %r = call {s} @{s}()\n", .{ try g.llty(rt), mi.llname });
                if (i.bits == 32) try w.writeAll("  ret i32 %r\n") else if (i.bits > 32) try w.writeAll("  %r2 = trunc i64 %r to i32\n  ret i32 %r2\n") else try w.print("  %r2 = zext i{d} %r to i32\n  ret i32 %r2\n", .{i.bits});
            },
            .errun => |inner| {
                if (inner.* != .void_) return g.fail(mi.decl.line, "main must return void, an integer, or !void", .{});
                try g.declare("dprintf", "declare i32 @dprintf(i32, ptr, ...)");
                try g.declare("fflush", "declare i32 @fflush(ptr)");
                const f = try g.strGlobal("error: %s\n");
                try w.print("  %r = call {{ i32 }} @{s}()\n  %tag = extractvalue {{ i32 }} %r, 0\n  %bad = icmp ne i32 %tag, 0\n  br i1 %bad, label %err, label %ok\nok:\n  ret i32 0\nerr:\n  call i32 @fflush(ptr null)\n", .{mi.llname});
                try w.print("  %np = getelementptr ptr, ptr @__vibe_errnames, i32 %tag\n  %n = load ptr, ptr %np\n  call i32 (i32, ptr, ...) @dprintf(i32 2, ptr {s}, ptr %n)\n  ret i32 1\n", .{f});
            },
            else => return g.fail(mi.decl.line, "main must return void, an integer, or !void", .{}),
        }
        try w.writeAll("}\n");
    }

    fn genFunction(g: *Gen, fi: *FnInst) Error!void {
        const decl = fi.decl;
        g.file = decl.file;
        g.body = std.ArrayList(u8).init(g.alloc);
        g.allocas = std.ArrayList(u8).init(g.alloc);
        g.scopes = std.ArrayList(Scope).init(g.alloc);
        g.loops = std.ArrayList(Loop).init(g.alloc);
        g.ntmp = 0;
        g.nlbl = 0;
        g.terminated = false;
        g.cur_label = "entry";
        g.cur = fi;
        g.env = fi.env;

        try g.pushScope();
        var hdr = std.ArrayList(u8).init(g.alloc);
        const linkage: []const u8 = if (decl.is_export or std.mem.eql(u8, fi.llname, "vb.main")) "" else "internal ";
        try hdr.writer().print("define {s}{s} @{s}(", .{ linkage, try g.llty(fi.ret), fi.llname });
        for (decl.params, 0..) |p, i| {
            const pt = fi.params[i];
            if (i > 0) try hdr.appendSlice(", ");
            try hdr.writer().print("{s} %a.{d}", .{ try g.llty(pt), i });
            const slot = try g.alloca(pt, p.name);
            try g.store(.{ .ty = pt, .v = try g.fmt("%a.{d}", .{i}) }, slot);
            try g.declareVar(p.name, .{ .ptr = slot, .ty = pt, .mutable = false }, decl.line);
        }
        try hdr.appendSlice(") {\n");

        try g.genStmt(decl.body.?);
        if (!g.terminated) {
            try g.runDefers(g.scopes.items.len - 1, 0, false);
            switch (fi.ret.*) {
                .void_ => try g.emitTerm("ret void", .{}),
                .errun => |inner| {
                    if (inner.* == .void_) try g.emitTerm("ret {{ i32 }} zeroinitializer", .{}) else try g.emitTerm("unreachable", .{});
                },
                else => try g.emitTerm("unreachable", .{}),
            }
        }
        _ = g.scopes.pop();

        const w = g.funcs_out.writer();
        try w.writeAll(hdr.items);
        try w.writeAll("entry:\n");
        try w.writeAll(g.allocas.items);
        try w.writeAll(g.body.items);
        try w.writeAll("}\n\n");
    }

    // ------------------------------------------------ statements

    fn genStmt(g: *Gen, s: *ast.Stmt) Error!void {
        switch (s.kind) {
            .block => |stmts| {
                try g.pushScope();
                for (stmts) |st| try g.genStmt(st);
                try g.popScope();
            },
            .let => |l| {
                var ty: ?*const Type = null;
                if (l.ty) |te| ty = try g.resolveType(te, &g.env);
                var val: ?Value = null;
                if (l.init) |ie| {
                    var v = try g.genExpr(ie, ty);
                    if (ty) |t| v = try g.coerce(v, t, s.line);
                    val = v;
                    if (ty == null) ty = v.ty;
                }
                const t = ty.?;
                if (t.* == .void_) return g.fail(s.line, "cannot declare variable '{s}' of type void", .{l.name});
                if (t.* == .null_t) return g.fail(s.line, "cannot infer type of '{s}' from null; add a type", .{l.name});
                const slot = try g.alloca(t, l.name);
                if (val) |v| try g.store(v, slot) else try g.zeroFill(t, slot);
                try g.declareVar(l.name, .{ .ptr = slot, .ty = t, .mutable = l.mutable }, s.line);
            },
            .assign => |a| {
                if (a.target.kind == .ident and std.mem.eql(u8, a.target.kind.ident, "_")) {
                    _ = try g.genExpr(a.value, null);
                    return;
                }
                const addr = try g.genAddr(a.target);
                if (addr.imm) return g.fail(s.line, "cannot assign: target is immutable (declare it with 'var')", .{});
                if (a.op == .eq) {
                    const v = try g.coerce(try g.genExpr(a.value, addr.ty), addr.ty, s.line);
                    try g.store(v, addr.v);
                } else {
                    const cur = try g.load(addr.ty, addr.v);
                    const rhs = try g.coerce(try g.genExpr(a.value, addr.ty), addr.ty, s.line);
                    const op: Tag = switch (a.op) {
                        .plus_eq => .plus,
                        .minus_eq => .minus,
                        .star_eq => .star,
                        .slash_eq => .slash,
                        else => .percent,
                    };
                    const r = try g.arith(op, cur, rhs, s.line);
                    try g.store(r, addr.v);
                }
            },
            .expr => |e| {
                const v = try g.genExpr(e, null);
                if (v.ty.* == .errun) return g.fail(s.line, "error union is ignored; handle it with '?' or 'catch'", .{});
            },
            .if_ => |i| {
                const c = try g.genCond(i.cond);
                const lt = try g.newLabel("then");
                const le = try g.newLabel("else");
                const lend = try g.newLabel("endif");
                try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c.v, lt, if (i.els != null) le else lend });
                try g.label(lt);
                try g.genStmt(i.then);
                if (!g.terminated) try g.br(lend);
                if (i.els) |els| {
                    try g.label(le);
                    try g.genStmt(els);
                    if (!g.terminated) try g.br(lend);
                }
                try g.label(lend);
            },
            .while_ => |w| {
                const lc = try g.newLabel("wcond");
                const lb = try g.newLabel("wbody");
                const le = try g.newLabel("wend");
                try g.label(lc);
                const c = try g.genCond(w.cond);
                try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c.v, lb, le });
                try g.label(lb);
                try g.loops.append(.{ .brk = le, .cont = lc, .depth = g.scopes.items.len });
                try g.genStmt(w.body);
                _ = g.loops.pop();
                if (!g.terminated) try g.br(lc);
                try g.label(le);
            },
            .for_range => |f| {
                try g.pushScope();
                var lo: Value = undefined;
                var hi: Value = undefined;
                if (isLiteral(f.lo) and !isLiteral(f.hi)) {
                    hi = try g.genExpr(f.hi, null);
                    lo = try g.coerce(try g.genExpr(f.lo, hi.ty), hi.ty, s.line);
                } else {
                    lo = try g.genExpr(f.lo, null);
                    hi = try g.coerce(try g.genExpr(f.hi, lo.ty), lo.ty, s.line);
                }
                if (lo.ty.* != .int) return g.fail(s.line, "range bounds must be integers", .{});
                const it = try g.alloca(lo.ty, f.name);
                try g.store(lo, it);
                const lc = try g.newLabel("fcond");
                const lb = try g.newLabel("fbody");
                const lstep = try g.newLabel("fstep");
                const le = try g.newLabel("fend");
                try g.label(lc);
                const cur = try g.load(lo.ty, it);
                const c = try g.tmp();
                try g.emit("{s} = icmp {s} {s} {s}, {s}", .{ c, if (lo.ty.int.signed) "slt" else "ult", try g.llty(lo.ty), cur.v, hi.v });
                try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c, lb, le });
                try g.label(lb);
                try g.pushScope();
                const slot = try g.alloca(lo.ty, f.name);
                try g.store(cur, slot);
                try g.declareVar(f.name, .{ .ptr = slot, .ty = lo.ty, .mutable = false }, s.line);
                try g.loops.append(.{ .brk = le, .cont = lstep, .depth = g.scopes.items.len });
                try g.genStmt(f.body);
                _ = g.loops.pop();
                try g.popScope();
                try g.label(lstep);
                const cur2 = try g.load(lo.ty, it);
                const nx = try g.tmp();
                try g.emit("{s} = add {s} {s}, 1", .{ nx, try g.llty(lo.ty), cur2.v });
                try g.store(.{ .ty = lo.ty, .v = nx }, it);
                try g.br(lc);
                try g.label(le);
                try g.popScope();
            },
            .for_each => |f| try g.genForEach(s, f.idx, f.name, f.seq, f.body),
            .ret => |re| try g.genReturn(s.line, re),
            .brk, .cont => {
                if (g.loops.items.len == 0) return g.fail(s.line, "break/continue outside of a loop", .{});
                const lp = g.loops.items[g.loops.items.len - 1];
                if (g.scopes.items.len > lp.depth) try g.runDefers(g.scopes.items.len - 1, lp.depth, false);
                try g.br(if (s.kind == .brk) lp.brk else lp.cont);
            },
            .defer_ => |d| {
                const sc = &g.scopes.items[g.scopes.items.len - 1];
                try sc.defers.append(.{ .stmt = d.body, .is_err = d.is_err });
            },
            .match_ => |m| {
                const v = try g.genExpr(m.value, null);
                if (isUnion(v.ty)) return g.genUnionMatch(v, m.arms, s.line);
                const lend = try g.newLabel("mend");
                for (m.arms) |arm| {
                    const lbody = try g.newLabel("arm");
                    const lnext = try g.newLabel("next");
                    if (arm.pats.len == 0) {
                        try g.br(lbody);
                    } else {
                        for (arm.pats, 0..) |pat, pi| {
                            const pv = try g.coerce(try g.genExpr(pat, v.ty), v.ty, pat.line);
                            const c = try g.compare(.eqeq, v, pv, pat.line);
                            const lalt = if (pi + 1 < arm.pats.len) try g.newLabel("alt") else lnext;
                            try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c.v, lbody, lalt });
                            if (pi + 1 < arm.pats.len) try g.label(lalt);
                        }
                    }
                    try g.label(lbody);
                    try g.pushScope();
                    try g.genStmt(arm.body);
                    try g.popScope();
                    if (!g.terminated) try g.br(lend);
                    try g.label(lnext);
                }
                try g.label(lend);
            },
        }
    }

    const UPat = struct { idx: usize, bind: ?[]const u8 };

    fn unionPattern(g: *Gen, pat: *ast.Expr, t: *const Type) Error!UPat {
        const si = t.strct;
        var name: []const u8 = undefined;
        var bind: ?[]const u8 = null;
        var head = pat;
        if (pat.kind == .call) {
            const c = pat.kind.call;
            if (c.args.len != 1 or c.args[0].kind != .ident) return g.fail(pat.line, "union pattern takes one binding name: .Variant(x)", .{});
            bind = c.args[0].kind.ident;
            head = c.callee;
        }
        switch (head.kind) {
            .enum_lit => |n| name = n,
            .field => |f| name = f.name,
            else => return g.fail(pat.line, "expected a union pattern like .Variant or .Variant(x)", .{}),
        }
        const idx = fieldIndex(si, name) orelse return g.fail(pat.line, "union '{s}' has no variant '{s}'", .{ si.display, name });
        if (bind != null and si.fields[idx].ty.* == .void_) return g.fail(pat.line, "variant '{s}' has no payload to bind", .{name});
        if (bind) |b| if (std.mem.eql(u8, b, "_")) {
            bind = null;
        };
        return .{ .idx = idx, .bind = bind };
    }

    fn genUnionMatch(g: *Gen, v: Value, arms: []ast.MatchArm, line: u32) Error!void {
        _ = line;
        const slot = (try g.spill(v)).v;
        const lt = try g.llty(v.ty);
        const tp = try g.tmp();
        try g.emit("{s} = getelementptr {s}, ptr {s}, i32 0, i32 0", .{ tp, lt, slot });
        const tag = try g.load(g.t_i32, tp);
        const pp = try g.tmp();
        try g.emit("{s} = getelementptr {s}, ptr {s}, i32 0, i32 1", .{ pp, lt, slot });
        const lend = try g.newLabel("mend");
        for (arms) |arm| {
            const lbody = try g.newLabel("arm");
            const lnext = try g.newLabel("next");
            var bind: ?UPat = null;
            if (arm.pats.len == 0) {
                try g.br(lbody);
            } else {
                for (arm.pats, 0..) |pat, pi| {
                    const up = try g.unionPattern(pat, v.ty);
                    if (up.bind != null) {
                        if (arm.pats.len > 1) return g.fail(pat.line, "bindings are not allowed in multi-pattern arms", .{});
                        bind = up;
                    }
                    const c = try g.tmp();
                    try g.emit("{s} = icmp eq i32 {s}, {d}", .{ c, tag.v, up.idx });
                    const lalt = if (pi + 1 < arm.pats.len) try g.newLabel("alt") else lnext;
                    try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c, lbody, lalt });
                    if (pi + 1 < arm.pats.len) try g.label(lalt);
                }
            }
            try g.label(lbody);
            try g.pushScope();
            if (bind) |b| {
                try g.declareVar(b.bind.?, .{ .ptr = pp, .ty = v.ty.strct.fields[b.idx].ty, .mutable = false }, arm.body.line);
            }
            try g.genStmt(arm.body);
            try g.popScope();
            if (!g.terminated) try g.br(lend);
            try g.label(lnext);
        }
        try g.label(lend);
    }

    fn genForEach(g: *Gen, s: *ast.Stmt, idx_name: ?[]const u8, name: []const u8, seq: *ast.Expr, body: *ast.Stmt) Error!void {
        try g.pushScope();
        var a = try g.genAddr(seq);
        if (a.ty.* == .ptr and (a.ty.ptr.* == .array or a.ty.ptr.* == .slice or a.ty.ptr.* == .strct)) {
            const p = try g.load(a.ty, a.v);
            a = .{ .ty = a.ty.ptr, .v = p.v, .imm = false };
        }
        // struct with a .slice() method (e.g. List[T])
        if (a.ty.* == .strct) {
            const key = try g.fmt("{s}.slice", .{a.ty.strct.decl.name});
            const md = g.methods.get(key) orelse return g.fail(s.line, "cannot iterate over '{s}' (no slice() method)", .{try g.typeName(a.ty)});
            const sv = try g.callMethod(md, a, &.{}, &.{}, null, s.line);
            const slot = try g.alloca(sv.ty, "it");
            try g.store(sv, slot);
            a = .{ .ty = sv.ty, .v = slot, .imm = false };
        }
        var elem: *const Type = undefined;
        var len: []const u8 = undefined;
        var base: []const u8 = undefined;
        switch (a.ty.*) {
            .array => |arr| {
                elem = arr.elem;
                len = try g.fmt("{d}", .{arr.len});
                base = a.v;
            },
            .slice => |el| {
                elem = el;
                const sv = try g.load(a.ty, a.v);
                base = (try g.extract(sv, 0, g.t_ptr_u8)).v;
                len = (try g.extract(sv, 1, g.t_i64)).v;
            },
            else => return g.fail(s.line, "cannot iterate over '{s}'", .{try g.typeName(a.ty)}),
        }
        const it = try g.alloca(g.t_i64, "idx");
        try g.store(.{ .ty = g.t_i64, .v = "0" }, it);
        const lc = try g.newLabel("ecnd");
        const lb = try g.newLabel("ebody");
        const lstep = try g.newLabel("estep");
        const le = try g.newLabel("eend");
        try g.label(lc);
        const cur = try g.load(g.t_i64, it);
        const c = try g.tmp();
        try g.emit("{s} = icmp slt i64 {s}, {s}", .{ c, cur.v, len });
        try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c, lb, le });
        try g.label(lb);
        try g.pushScope();
        const ep = try g.tmp();
        if (a.ty.* == .array) {
            try g.emit("{s} = getelementptr {s}, ptr {s}, i64 0, i64 {s}", .{ ep, try g.llty(a.ty), base, cur.v });
        } else {
            try g.emit("{s} = getelementptr {s}, ptr {s}, i64 {s}", .{ ep, try g.llty(elem), base, cur.v });
        }
        const ev = try g.load(elem, ep);
        const slot = try g.alloca(elem, name);
        try g.store(ev, slot);
        try g.declareVar(name, .{ .ptr = slot, .ty = elem, .mutable = false }, s.line);
        if (idx_name) |iname| {
            const islot = try g.alloca(g.t_i64, iname);
            try g.store(cur, islot);
            try g.declareVar(iname, .{ .ptr = islot, .ty = g.t_i64, .mutable = false }, s.line);
        }
        try g.loops.append(.{ .brk = le, .cont = lstep, .depth = g.scopes.items.len });
        try g.genStmt(body);
        _ = g.loops.pop();
        try g.popScope();
        try g.label(lstep);
        const cur2 = try g.load(g.t_i64, it);
        const nx = try g.tmp();
        try g.emit("{s} = add i64 {s}, 1", .{ nx, cur2.v });
        try g.store(.{ .ty = g.t_i64, .v = nx }, it);
        try g.br(lc);
        try g.label(le);
        try g.popScope();
    }

    fn genReturn(g: *Gen, line: u32, re: ?*ast.Expr) Error!void {
        const rt = g.cur.?.ret;
        var is_err = false;
        var val: ?Value = null;
        if (re) |e| {
            if (rt.* == .void_) return g.fail(line, "function returns void but a value was returned", .{});
            is_err = e.kind == .error_val;
            val = try g.coerce(try g.genExpr(e, rt), rt, line);
        } else {
            if (rt.* == .errun and rt.errun.* == .void_) {
                val = .{ .ty = rt, .v = "zeroinitializer" };
            } else if (rt.* != .void_) return g.fail(line, "missing return value", .{});
        }
        if (!is_err and rt.* == .errun and val != null and g.hasErrDefers()) {
            // error decided at runtime: run errdefers only if the tag is non-zero
            const v = val.?;
            const tag = try g.extract(v, 0, g.t_i32);
            const c = try g.tmp();
            try g.emit("{s} = icmp ne i32 {s}, 0", .{ c, tag.v });
            const le = try g.newLabel("reterr");
            const lo = try g.newLabel("retok");
            try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c, le, lo });
            try g.label(le);
            try g.runDefers(g.scopes.items.len - 1, 0, true);
            try g.emitTerm("ret {s} {s}", .{ try g.llty(rt), v.v });
            try g.label(lo);
            try g.runDefers(g.scopes.items.len - 1, 0, false);
            try g.emitTerm("ret {s} {s}", .{ try g.llty(rt), v.v });
            return;
        }
        try g.runDefers(g.scopes.items.len - 1, 0, is_err);
        if (val) |v| try g.emitTerm("ret {s} {s}", .{ try g.llty(rt), v.v }) else try g.emitTerm("ret void", .{});
    }

    fn hasErrDefers(g: *Gen) bool {
        for (g.scopes.items) |sc| {
            for (sc.defers.items) |d| if (d.is_err) return true;
        }
        return false;
    }

    // ------------------------------------------------ expressions

    fn isLiteral(e: *ast.Expr) bool {
        return switch (e.kind) {
            .int_lit, .float_lit, .null_lit, .enum_lit => true,
            .unary => |u| u.op == .minus and isLiteral(u.e),
            else => false,
        };
    }

    fn genCond(g: *Gen, e: *ast.Expr) Error!Value {
        const v = try g.genExpr(e, g.t_bool);
        if (v.ty.* != .boolean) return g.fail(e.line, "condition must be bool, got '{s}'", .{try g.typeName(v.ty)});
        return v;
    }

    fn litTarget(t: ?*const Type) ?*const Type {
        const x = t orelse return null;
        if (x.* == .errun) return x.errun;
        return x;
    }

    fn genExpr(g: *Gen, e: *ast.Expr, expected: ?*const Type) Error!Value {
        switch (e.kind) {
            .int_lit => |v| {
                if (litTarget(expected)) |t| {
                    if (t.* == .int) return .{ .ty = t, .v = try g.fmt("{d}", .{v}) };
                    if (t.* == .float) return .{ .ty = t, .v = try g.floatConst(@floatFromInt(v), t.float) };
                }
                return .{ .ty = g.t_i64, .v = try g.fmt("{d}", .{v}) };
            },
            .float_lit => |f| {
                if (litTarget(expected)) |t| if (t.* == .float) return .{ .ty = t, .v = try g.floatConst(f, t.float) };
                return .{ .ty = g.t_f64, .v = try g.floatConst(f, 64) };
            },
            .bool_lit => |b| return .{ .ty = g.t_bool, .v = if (b) "true" else "false" },
            .null_lit => return .{ .ty = g.t_null, .v = "null" },
            .str_lit => |s| {
                const gname = try g.strGlobal(s);
                if (litTarget(expected)) |t| if (t.* == .ptr) return .{ .ty = g.t_ptr_u8, .v = gname };
                return .{ .ty = g.t_str, .v = try g.fmt("{{ ptr {s}, i64 {d} }}", .{ gname, s.len }) };
            },
            .interp => return g.fail(e.line, "string interpolation never allocates: use it inside print/println/eprintln/panic, or format into a buffer with bprint(buf, \"...\")", .{}),
            .ident => |n| {
                if (g.lookupVar(n)) |v| return g.load(v.ty, v.ptr);
                if (g.consts.get(n)) |c| {
                    const saved = g.file;
                    defer g.file = saved;
                    var t = expected;
                    if (c.ty) |te| t = try g.resolveType(te, &g.env);
                    const v = try g.genExpr(c.value, t);
                    if (t) |tt| return g.coerce(v, tt, e.line);
                    return v;
                }
                if (g.fns.get(n)) |fd| {
                    if (fd.type_params.len > 0) return g.fail(e.line, "generic function '{s}' cannot be used as a value", .{n});
                    if (fd.variadic) return g.fail(e.line, "variadic function '{s}' cannot be used as a value", .{n});
                    const fi = try g.instFn(fd, Env.init(g.alloc), &.{});
                    const sig = try g.alloc.create(FuncSig);
                    sig.* = .{ .params = fi.params, .ret = fi.ret };
                    return .{ .ty = try g.mk(.{ .func = sig }), .v = try g.fmt("@{s}", .{fi.llname}) };
                }
                return g.fail(e.line, "unknown identifier '{s}'", .{n});
            },
            .enum_lit => |n| {
                const t = litTarget(expected) orelse return g.fail(e.line, "cannot infer enum type for '.{s}'", .{n});
                if (isUnion(t)) return g.makeUnion(t, n, null, e.line);
                if (t.* != .enm) return g.fail(e.line, "'.{s}' used where '{s}' is expected", .{ n, try g.typeName(t) });
                return g.enumValue(t, n, e.line);
            },
            .error_val => |n| return .{ .ty = g.t_errval, .v = try g.fmt("{d}", .{try g.errorId(n)}) },
            .binary => |b| return g.genBinary(b.op, b.l, b.r, expected, e.line),
            .unary => |u| {
                switch (u.op) {
                    .minus => {
                        if (u.e.kind == .int_lit) {
                            if (litTarget(expected)) |t| if (t.* == .float) return .{ .ty = t, .v = try g.floatConst(-@as(f64, @floatFromInt(u.e.kind.int_lit)), t.float) };
                        }
                        const v = try g.genExpr(u.e, expected);
                        const t = try g.tmp();
                        switch (v.ty.*) {
                            .int => try g.emit("{s} = sub {s} 0, {s}", .{ t, try g.llty(v.ty), v.v }),
                            .float => try g.emit("{s} = fneg {s} {s}", .{ t, try g.llty(v.ty), v.v }),
                            else => return g.fail(e.line, "cannot negate '{s}'", .{try g.typeName(v.ty)}),
                        }
                        return .{ .ty = v.ty, .v = t };
                    },
                    .bang => {
                        const v = try g.genCond(u.e);
                        const t = try g.tmp();
                        try g.emit("{s} = xor i1 {s}, true", .{ t, v.v });
                        return .{ .ty = g.t_bool, .v = t };
                    },
                    .tilde => {
                        const v = try g.genExpr(u.e, expected);
                        if (v.ty.* != .int) return g.fail(e.line, "'~' needs an integer", .{});
                        const t = try g.tmp();
                        try g.emit("{s} = xor {s} {s}, -1", .{ t, try g.llty(v.ty), v.v });
                        return .{ .ty = v.ty, .v = t };
                    },
                    .amp => {
                        const a = try g.genAddr(u.e);
                        return .{ .ty = try g.mk(.{ .ptr = a.ty }), .v = a.v };
                    },
                    .star => {
                        const v = try g.genExpr(u.e, null);
                        if (v.ty.* != .ptr) return g.fail(e.line, "cannot dereference '{s}'", .{try g.typeName(v.ty)});
                        return g.load(v.ty.ptr, v.v);
                    },
                    else => unreachable,
                }
            },
            .call => return g.genCall(e, expected),
            .field => |f| {
                // Enum.Variant
                if (f.e.kind == .ident and g.lookupVar(f.e.kind.ident) == null) {
                    if (g.enums.get(f.e.kind.ident)) |info| {
                        const t = try g.mk(.{ .enm = info });
                        return g.enumValue(t, f.name, e.line);
                    }
                }
                // Union.Variant (no payload)
                if (g.namesType(f.e)) {
                    const t = try g.typeFromExpr(f.e, expected, f.name, e.line);
                    if (isUnion(t)) return g.makeUnion(t, f.name, null, e.line);
                    return g.fail(e.line, "'{s}' has no constant '{s}'", .{ try g.typeName(t), f.name });
                }
                const a = try g.genAddr(e);
                return g.load(a.ty, a.v);
            },
            .index, .slice => {
                const a = try g.genAddrOrSlice(e);
                return a;
            },
            .struct_lit => |sl| {
                const t = try g.resolveTypeAt(sl.ty, e.line);
                if (t.* != .strct or isUnion(t)) return g.fail(e.line, "'{s}' is not a struct", .{try g.typeName(t)});
                const si = t.strct;
                var cur: []const u8 = "zeroinitializer";
                const given = try g.alloc.alloc(bool, si.fields.len);
                @memset(given, false);
                for (sl.fields) |fi| {
                    const idx = fieldIndex(si, fi.name) orelse return g.fail(e.line, "struct '{s}' has no field '{s}'", .{ si.display, fi.name });
                    if (given[idx]) return g.fail(e.line, "field '{s}' given twice", .{fi.name});
                    given[idx] = true;
                    const fty = si.fields[idx].ty;
                    const v = try g.coerce(try g.genExpr(fi.value, fty), fty, e.line);
                    cur = try g.insert(t, cur, v, idx);
                }
                if (!sl.zero_rest) {
                    for (given, 0..) |gv, i| if (!gv)
                        return g.fail(e.line, "missing field '{s}' in '{s}' literal (write '..' to zero the remaining fields)", .{ si.fields[i].name, si.display });
                }
                return .{ .ty = t, .v = cur };
            },
            .array_lit => |elems| {
                var elem_t: ?*const Type = null;
                var want_slice = false;
                if (litTarget(expected)) |t| switch (t.*) {
                    .array => |a| elem_t = a.elem,
                    .slice => |el| {
                        elem_t = el;
                        want_slice = true;
                    },
                    else => {},
                };
                if (elems.len == 0 and elem_t == null) return g.fail(e.line, "cannot infer type of empty array", .{});
                var vals = std.ArrayList(Value).init(g.alloc);
                for (elems) |el| {
                    var v = try g.genExpr(el, elem_t);
                    if (elem_t) |et| v = try g.coerce(v, et, el.line) else elem_t = v.ty;
                    try vals.append(v);
                }
                const at = try g.mk(.{ .array = .{ .len = elems.len, .elem = elem_t.? } });
                var cur: []const u8 = "undef";
                for (vals.items, 0..) |v, i| cur = try g.insert(at, cur, v, i);
                if (elems.len == 0) cur = "zeroinitializer";
                if (want_slice) {
                    const slot = try g.alloca(at, "arr");
                    try g.store(.{ .ty = at, .v = cur }, slot);
                    const st = try g.mk(.{ .slice = elem_t.? });
                    const s1 = try g.insert(st, "undef", .{ .ty = g.t_ptr_u8, .v = slot }, 0);
                    const s2 = try g.insert(st, s1, .{ .ty = g.t_i64, .v = try g.fmt("{d}", .{elems.len}) }, 1);
                    return .{ .ty = st, .v = s2 };
                }
                return .{ .ty = at, .v = cur };
            },
            .cast => |c| {
                const target = try g.resolveTypeAt(c.ty, e.line);
                const v = try g.genExpr(c.e, if (isLiteral(c.e)) target else null);
                return g.cast(v, target, e.line);
            },
            .try_ => |inner| {
                const ex: ?*const Type = if (litTarget(expected)) |x| try g.mk(.{ .errun = x }) else null;
                const v = try g.genExpr(inner, ex);
                if (v.ty.* != .errun) return g.fail(e.line, "'?' needs an error union, got '{s}'", .{try g.typeName(v.ty)});
                const rt = g.cur.?.ret;
                if (rt.* != .errun) return g.fail(e.line, "'?' used in a function that does not return an error union (make it return !T)", .{});
                const tag = try g.extract(v, 0, g.t_i32);
                const c = try g.tmp();
                try g.emit("{s} = icmp ne i32 {s}, 0", .{ c, tag.v });
                const lerr = try g.newLabel("tryerr");
                const lok = try g.newLabel("tryok");
                try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c, lerr, lok });
                try g.label(lerr);
                const rv = try g.insert(rt, "zeroinitializer", tag, 0);
                try g.runDefers(g.scopes.items.len - 1, 0, true);
                try g.emitTerm("ret {s} {s}", .{ try g.llty(rt), rv });
                try g.label(lok);
                if (v.ty.errun.* == .void_) return .{ .ty = g.t_void, .v = "" };
                return g.extract(v, 1, v.ty.errun);
            },
            .catch_ => |c| return g.genCatch(e, c.e, c.err_name, c.handler, expected),
            .is_ => |x| {
                const v = try g.genExpr(x.e, null);
                const t = try g.tmp();
                if (v.ty.* == .enm) {
                    const ev = try g.enumValue(v.ty, x.variant, e.line);
                    try g.emit("{s} = icmp eq i32 {s}, {s}", .{ t, v.v, ev.v });
                    return .{ .ty = g.t_bool, .v = t };
                }
                if (!isUnion(v.ty)) return g.fail(e.line, "'is' needs an enum or union, got '{s}'", .{try g.typeName(v.ty)});
                const idx = fieldIndex(v.ty.strct, x.variant) orelse return g.fail(e.line, "union '{s}' has no variant '{s}'", .{ v.ty.strct.display, x.variant });
                const tag = try g.extract(v, 0, g.t_i32);
                try g.emit("{s} = icmp eq i32 {s}, {d}", .{ t, tag.v, idx });
                return .{ .ty = g.t_bool, .v = t };
            },
            .sizeof, .alignof => |te| {
                const t = try g.resolveTypeAt(te, e.line);
                const n = if (e.kind == .sizeof) try g.sizeOf(t) else try g.alignOf(t);
                var rt = g.t_u64;
                if (litTarget(expected)) |x| {
                    if (x.* == .int) rt = x;
                }
                return .{ .ty = rt, .v = try g.fmt("{d}", .{n}) };
            },
        }
    }

    fn resolveTypeAt(g: *Gen, te: *ast.TypeExpr, line: u32) Error!*const Type {
        return g.resolveType(te, &g.env) catch |err| {
            std.debug.print("{s}:{d}: note: while resolving this type\n", .{ g.file, line });
            return err;
        };
    }

    /// Resolve a type written in expression position (`Point`, `List[i32]`, `Option`).
    /// A bare generic name takes its type arguments from the expected type.
    fn typeFromExpr(g: *Gen, te_expr: *ast.Expr, expected: ?*const Type, member: []const u8, line: u32) Error!*const Type {
        if (te_expr.kind == .ident) {
            if (g.structs.get(te_expr.kind.ident)) |sd| if (sd.type_params.len > 0) {
                const ex = litTarget(expected) orelse return g.fail(line, "cannot infer type arguments for '{s}'; write {s}[T].{s}", .{ sd.name, sd.name, member });
                if (ex.* != .strct or ex.strct.decl != sd) return g.fail(line, "cannot infer type arguments for '{s}' from '{s}'", .{ sd.name, try g.typeName(ex) });
                return ex;
            };
        }
        const te = (try g.exprToTypeExpr(te_expr)) orelse return g.fail(line, "expected a type", .{});
        return g.resolveTypeAt(te, line);
    }

    fn makeUnion(g: *Gen, t: *const Type, variant: []const u8, payload: ?*ast.Expr, line: u32) Error!Value {
        const si = t.strct;
        const idx = fieldIndex(si, variant) orelse return g.fail(line, "union '{s}' has no variant '{s}'", .{ si.display, variant });
        const pty = si.fields[idx].ty;
        if (pty.* != .void_ and payload == null) return g.fail(line, "'{s}.{s}' needs a payload of type '{s}'", .{ si.display, variant, try g.typeName(pty) });
        if (pty.* == .void_ and payload != null) return g.fail(line, "'{s}.{s}' has no payload", .{ si.display, variant });
        const slot = try g.alloca(t, "u");
        const tp = try g.tmp();
        try g.emit("{s} = getelementptr {s}, ptr {s}, i32 0, i32 0", .{ tp, try g.llty(t), slot });
        try g.emit("store i32 {d}, ptr {s}", .{ idx, tp });
        if (payload) |pe| {
            const v = try g.coerce(try g.genExpr(pe, pty), pty, line);
            const pp = try g.tmp();
            try g.emit("{s} = getelementptr {s}, ptr {s}, i32 0, i32 1", .{ pp, try g.llty(t), slot });
            try g.store(v, pp);
        }
        return g.load(t, slot);
    }

    fn fieldIndex(si: *StructInst, name: []const u8) ?usize {
        for (si.fields, 0..) |f, i| if (std.mem.eql(u8, f.name, name)) return i;
        return null;
    }

    fn enumValue(g: *Gen, t: *const Type, name: []const u8, line: u32) Error!Value {
        for (t.enm.decl.variants, 0..) |v, i| {
            if (std.mem.eql(u8, v, name)) return .{ .ty = t, .v = try g.fmt("{d}", .{i}) };
        }
        return g.fail(line, "enum '{s}' has no variant '{s}'", .{ t.enm.decl.name, name });
    }

    fn genCatch(g: *Gen, e: *ast.Expr, inner: *ast.Expr, err_name: ?[]const u8, handler: *ast.Stmt, expected: ?*const Type) Error!Value {
        const v = try g.genExpr(inner, if (expected) |x| try g.mk(.{ .errun = x }) else null);
        if (v.ty.* != .errun) return g.fail(e.line, "'catch' needs an error union, got '{s}'", .{try g.typeName(v.ty)});
        const vt = v.ty.errun;
        const tag = try g.extract(v, 0, g.t_i32);
        const c = try g.tmp();
        try g.emit("{s} = icmp ne i32 {s}, 0", .{ c, tag.v });
        const lerr = try g.newLabel("cerr");
        const lok = try g.newLabel("cok");
        const lend = try g.newLabel("cend");
        try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c, lerr, lok });
        try g.label(lok);
        var okv: Value = .{ .ty = g.t_void, .v = "" };
        if (vt.* != .void_) okv = try g.extract(v, 1, vt);
        const ok_lbl = g.cur_label;
        try g.br(lend);
        try g.label(lerr);
        try g.pushScope();
        if (err_name) |n| {
            const slot = try g.alloca(g.t_errval, n);
            try g.store(.{ .ty = g.t_errval, .v = tag.v }, slot);
            try g.declareVar(n, .{ .ptr = slot, .ty = g.t_errval, .mutable = false }, e.line);
        }
        var errv: ?Value = null;
        if (handler.kind == .expr and vt.* != .void_) {
            errv = try g.coerce(try g.genExpr(handler.kind.expr, vt), vt, e.line);
        } else if (handler.kind == .expr) {
            _ = try g.genExpr(handler.kind.expr, null);
        } else if (handler.kind == .block and vt.* != .void_ and handler.kind.block.len > 0 and
            handler.kind.block[handler.kind.block.len - 1].kind == .expr)
        {
            // block whose last expression is the value: catch |e| { log(e); -1 }
            const stmts = handler.kind.block;
            try g.pushScope();
            for (stmts[0 .. stmts.len - 1]) |st| try g.genStmt(st);
            if (!g.terminated) errv = try g.coerce(try g.genExpr(stmts[stmts.len - 1].kind.expr, vt), vt, e.line);
            try g.popScope();
        } else {
            try g.genStmt(handler);
        }
        try g.popScope();
        const err_reaches = !g.terminated;
        const err_lbl = g.cur_label;
        if (err_reaches and vt.* != .void_ and errv == null) return g.fail(e.line, "catch block must produce a value or leave (return/break/panic)", .{});
        if (err_reaches) try g.br(lend);
        try g.label(lend);
        if (vt.* == .void_) return okv;
        if (!err_reaches) return okv;
        const t = try g.tmp();
        try g.emit("{s} = phi {s} [ {s}, %{s} ], [ {s}, %{s} ]", .{ t, try g.llty(vt), okv.v, ok_lbl, errv.?.v, err_lbl });
        return .{ .ty = vt, .v = t };
    }

    // ------------------------------------------------ addresses

    fn genAddrOrSlice(g: *Gen, e: *ast.Expr) Error!Value {
        if (e.kind == .slice) return g.genSlice(e);
        const a = try g.genAddr(e);
        return g.load(a.ty, a.v);
    }

    fn derefAgg(g: *Gen, a: Addr) Error!Addr {
        if (a.ty.* == .ptr) {
            const p = try g.load(a.ty, a.v);
            return .{ .ty = a.ty.ptr, .v = p.v, .imm = false };
        }
        return a;
    }

    fn genAddr(g: *Gen, e: *ast.Expr) Error!Addr {
        switch (e.kind) {
            .ident => |n| {
                if (g.lookupVar(n)) |v| return .{ .ty = v.ty, .v = v.ptr, .imm = !v.mutable };
            },
            .field => |f| {
                if (f.e.kind == .ident and g.lookupVar(f.e.kind.ident) == null) {
                    if (g.enums.get(f.e.kind.ident)) |info| {
                        const et = try g.mk(.{ .enm = info });
                        return g.spill(try g.enumValue(et, f.name, e.line));
                    }
                }
                const base = try g.derefAgg(try g.genAddr(f.e));
                switch (base.ty.*) {
                    .strct => |si| {
                        const idx = fieldIndex(si, f.name) orelse return g.fail(e.line, "'{s}' has no field '{s}'", .{ si.display, f.name });
                        const t = try g.tmp();
                        try g.emit("{s} = getelementptr {s}, ptr {s}, i32 0, i32 {d}", .{ t, try g.llty(base.ty), base.v, idx });
                        return .{ .ty = si.fields[idx].ty, .v = t, .imm = base.imm };
                    },
                    .slice => |el| {
                        var idx: usize = undefined;
                        var ft: *const Type = undefined;
                        if (std.mem.eql(u8, f.name, "len")) {
                            idx = 1;
                            ft = g.t_i64;
                        } else if (std.mem.eql(u8, f.name, "ptr")) {
                            idx = 0;
                            ft = try g.mk(.{ .ptr = el });
                        } else return g.fail(e.line, "slices have only .len and .ptr", .{});
                        const t = try g.tmp();
                        try g.emit("{s} = getelementptr {{ ptr, i64 }}, ptr {s}, i32 0, i32 {d}", .{ t, base.v, idx });
                        return .{ .ty = ft, .v = t, .imm = base.imm };
                    },
                    .array => |arr| {
                        if (std.mem.eql(u8, f.name, "len")) return g.spill(.{ .ty = g.t_i64, .v = try g.fmt("{d}", .{arr.len}) });
                        if (std.mem.eql(u8, f.name, "ptr")) return g.spill(.{ .ty = try g.mk(.{ .ptr = arr.elem }), .v = base.v });
                        return g.fail(e.line, "arrays have only .len and .ptr", .{});
                    },
                    else => return g.fail(e.line, "'{s}' has no field '{s}'", .{ try g.typeName(base.ty), f.name }),
                }
            },
            .index => |ix| {
                if (ix.args.len != 1) return g.fail(e.line, "index takes one argument", .{});
                var base = try g.genAddr(ix.e);
                var ptr_elem: ?*const Type = null;
                if (base.ty.* == .ptr) {
                    const pointee = base.ty.ptr;
                    const p = try g.load(base.ty, base.v);
                    // indexing a pointer is always pointer arithmetic (use (*p)[i] for *[N]T)
                    ptr_elem = pointee;
                    base = .{ .ty = base.ty, .v = p.v, .imm = false };
                }
                const iv = try g.toI64(try g.genExpr(ix.args[0], g.t_i64), e.line);
                const t = try g.tmp();
                if (ptr_elem) |pe| {
                    try g.emit("{s} = getelementptr {s}, ptr {s}, i64 {s}", .{ t, try g.llty(pe), base.v, iv.v });
                    return .{ .ty = pe, .v = t, .imm = false };
                }
                switch (base.ty.*) {
                    .array => |arr| {
                        try g.boundsCheck(iv.v, try g.fmt("{d}", .{arr.len}), e.line);
                        try g.emit("{s} = getelementptr {s}, ptr {s}, i64 0, i64 {s}", .{ t, try g.llty(base.ty), base.v, iv.v });
                        return .{ .ty = arr.elem, .v = t, .imm = base.imm };
                    },
                    .slice => |el| {
                        const sv = try g.load(base.ty, base.v);
                        const p = try g.extract(sv, 0, g.t_ptr_u8);
                        const l = try g.extract(sv, 1, g.t_i64);
                        try g.boundsCheck(iv.v, l.v, e.line);
                        try g.emit("{s} = getelementptr {s}, ptr {s}, i64 {s}", .{ t, try g.llty(el), p.v, iv.v });
                        return .{ .ty = el, .v = t, .imm = false };
                    },
                    else => return g.fail(e.line, "cannot index '{s}'", .{try g.typeName(base.ty)}),
                }
            },
            .unary => |u| {
                if (u.op == .star) {
                    const v = try g.genExpr(u.e, null);
                    if (v.ty.* != .ptr) return g.fail(e.line, "cannot dereference '{s}'", .{try g.typeName(v.ty)});
                    return .{ .ty = v.ty.ptr, .v = v.v, .imm = false };
                }
            },
            else => {},
        }
        // rvalue: spill to a temporary
        const v = try g.genExpr(e, null);
        return g.spill(v);
    }

    fn spill(g: *Gen, v: Value) Error!Addr {
        if (v.ty.* == .void_) return g.fail(0, "void value used", .{});
        const slot = try g.alloca(v.ty, "tmp");
        try g.store(v, slot);
        return .{ .ty = v.ty, .v = slot, .imm = true };
    }

    fn toI64(g: *Gen, v: Value, line: u32) Error!Value {
        if (v.ty.* != .int) return g.fail(line, "index must be an integer, got '{s}'", .{try g.typeName(v.ty)});
        if (v.ty.int.bits == 64) return .{ .ty = g.t_i64, .v = v.v };
        const t = try g.tmp();
        try g.emit("{s} = {s} {s} {s} to i64", .{ t, if (v.ty.int.signed) "sext" else "zext", try g.llty(v.ty), v.v });
        return .{ .ty = g.t_i64, .v = t };
    }

    fn boundsCheck(g: *Gen, idx: []const u8, len: []const u8, line: u32) Error!void {
        if (!g.safety) return;
        const c = try g.tmp();
        try g.emit("{s} = icmp uge i64 {s}, {s}", .{ c, idx, len });
        const lbad = try g.newLabel("oob");
        const lok = try g.newLabel("inb");
        try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c, lbad, lok });
        try g.label(lbad);
        const fd = g.fns.get("__oob") orelse return g.fail(line, "runtime helper __oob missing (prelude)", .{});
        const fi = try g.instFn(fd, Env.init(g.alloc), &.{});
        const fname = try g.strGlobal(g.file);
        try g.emit("call void @{s}(i64 {s}, i64 {s}, {{ ptr, i64 }} {{ ptr {s}, i64 {d} }}, i64 {d})", .{ fi.llname, idx, len, fname, g.file.len, line });
        try g.emitTerm("unreachable", .{});
        try g.label(lok);
    }

    fn genSlice(g: *Gen, e: *ast.Expr) Error!Value {
        const sl = e.kind.slice;
        const base = try g.genAddr(sl.e);
        var elem: *const Type = undefined;
        var ptr: []const u8 = undefined;
        var len: ?[]const u8 = null;
        switch (base.ty.*) {
            .array => |arr| {
                elem = arr.elem;
                ptr = base.v;
                len = try g.fmt("{d}", .{arr.len});
            },
            .slice => |el| {
                elem = el;
                const sv = try g.load(base.ty, base.v);
                ptr = (try g.extract(sv, 0, g.t_ptr_u8)).v;
                len = (try g.extract(sv, 1, g.t_i64)).v;
            },
            .ptr => |pe| {
                elem = pe;
                ptr = (try g.load(base.ty, base.v)).v;
            },
            else => return g.fail(e.line, "cannot slice '{s}'", .{try g.typeName(base.ty)}),
        }
        const lo = if (sl.lo) |x| (try g.toI64(try g.genExpr(x, g.t_i64), e.line)).v else "0";
        var hi: []const u8 = undefined;
        if (sl.hi) |x| {
            hi = (try g.toI64(try g.genExpr(x, g.t_i64), e.line)).v;
        } else hi = len orelse return g.fail(e.line, "slicing a pointer needs an end index", .{});
        if (len) |l| {
            if (g.safety) {
                // lo <= hi <= len
                const hp1 = try g.tmp();
                try g.emit("{s} = add i64 {s}, 1", .{ hp1, l });
                try g.boundsCheck(hi, hp1, e.line);
                const lp1 = try g.tmp();
                try g.emit("{s} = add i64 {s}, 1", .{ lp1, hi });
                try g.boundsCheck(lo, lp1, e.line);
            }
        }
        const np = try g.tmp();
        try g.emit("{s} = getelementptr {s}, ptr {s}, i64 {s}", .{ np, try g.llty(elem), ptr, lo });
        const nl = try g.tmp();
        try g.emit("{s} = sub i64 {s}, {s}", .{ nl, hi, lo });
        const st = try g.mk(.{ .slice = elem });
        const s1 = try g.insert(st, "undef", .{ .ty = g.t_ptr_u8, .v = np }, 0);
        const s2 = try g.insert(st, s1, .{ .ty = g.t_i64, .v = nl }, 1);
        return .{ .ty = st, .v = s2 };
    }

    // ------------------------------------------------ operators

    fn genBinary(g: *Gen, op: Tag, le: *ast.Expr, re: *ast.Expr, expected: ?*const Type, line: u32) Error!Value {
        if (op == .andand or op == .oror) {
            const l = try g.genCond(le);
            const l_lbl = g.cur_label;
            const lr = try g.newLabel("rhs");
            const lend = try g.newLabel("lend");
            if (op == .andand) try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ l.v, lr, lend }) else try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ l.v, lend, lr });
            try g.label(lr);
            const r = try g.genCond(re);
            const r_lbl = g.cur_label;
            try g.br(lend);
            try g.label(lend);
            const t = try g.tmp();
            try g.emit("{s} = phi i1 [ {s}, %{s} ], [ {s}, %{s} ]", .{ t, if (op == .andand) "false" else "true", l_lbl, r.v, r_lbl });
            return .{ .ty = g.t_bool, .v = t };
        }
        const is_cmp = switch (op) {
            .eqeq, .neq, .lt, .le, .gt, .ge => true,
            else => false,
        };
        const exp: ?*const Type = if (is_cmp) null else expected;
        var l: Value = undefined;
        var r: Value = undefined;
        if (isLiteral(le) and !isLiteral(re)) {
            r = try g.genExpr(re, exp);
            l = try g.genExpr(le, r.ty);
        } else {
            l = try g.genExpr(le, exp);
            r = try g.genExpr(re, if (op == .shl or op == .shr) l.ty else l.ty);
        }
        // pointer arithmetic
        if (l.ty.* == .ptr and r.ty.* == .int and (op == .plus or op == .minus)) {
            var off = try g.toI64(r, line);
            if (op == .minus) {
                const n = try g.tmp();
                try g.emit("{s} = sub i64 0, {s}", .{ n, off.v });
                off = .{ .ty = g.t_i64, .v = n };
            }
            const t = try g.tmp();
            try g.emit("{s} = getelementptr {s}, ptr {s}, i64 {s}", .{ t, try g.llty(l.ty.ptr), l.v, off.v });
            return .{ .ty = l.ty, .v = t };
        }
        // unify
        if (!typeEq(l.ty, r.ty)) {
            if (canCoerce(r.ty, l.ty)) {
                r = try g.coerce(r, l.ty, line);
            } else if (canCoerce(l.ty, r.ty)) {
                l = try g.coerce(l, r.ty, line);
            } else return g.fail(line, "mismatched operand types '{s}' and '{s}'", .{ try g.typeName(l.ty), try g.typeName(r.ty) });
        }
        if (is_cmp) return g.compare(op, l, r, line);
        return g.arith(op, l, r, line);
    }

    fn canCoerce(from: *const Type, to: *const Type) bool {
        if (typeEq(from, to)) return true;
        if (from.* == .int and to.* == .int) {
            const f = from.int;
            const t = to.int;
            if (f.signed == t.signed) return t.bits >= f.bits;
            if (!f.signed and t.signed) return t.bits > f.bits;
            return false;
        }
        if (from.* == .null_t and (to.* == .ptr or to.* == .func)) return true;
        // *void is the only "any pointer": *T <-> *void
        if (from.* == .ptr and to.* == .ptr) return from.ptr.* == .void_ or to.ptr.* == .void_;
        if (to.* == .errun) return from.* == .errval or canCoerce(from, to.errun);
        return false;
    }

    fn coerce(g: *Gen, v: Value, to: *const Type, line: u32) Error!Value {
        if (typeEq(v.ty, to)) return v;
        if (!canCoerce(v.ty, to)) return g.fail(line, "type mismatch: expected '{s}', got '{s}'", .{ try g.typeName(to), try g.typeName(v.ty) });
        switch (to.*) {
            .int => {
                const t = try g.tmp();
                try g.emit("{s} = {s} {s} {s} to {s}", .{ t, if (v.ty.int.signed) "sext" else "zext", try g.llty(v.ty), v.v, try g.llty(to) });
                return .{ .ty = to, .v = t };
            },
            .func => return .{ .ty = to, .v = "null" },
            .ptr => {
                return .{ .ty = to, .v = v.v };
            },
            .errun => |inner| {
                if (v.ty.* == .errval) {
                    const t = try g.insert(to, "zeroinitializer", .{ .ty = g.t_i32, .v = v.v }, 0);
                    return .{ .ty = to, .v = t };
                }
                const iv = try g.coerce(v, inner, line);
                if (inner.* == .void_) return .{ .ty = to, .v = "zeroinitializer" };
                const t = try g.insert(to, "zeroinitializer", iv, 1);
                return .{ .ty = to, .v = t };
            },
            else => return g.fail(line, "type mismatch: expected '{s}', got '{s}'", .{ try g.typeName(to), try g.typeName(v.ty) }),
        }
    }

    fn arith(g: *Gen, op: Tag, l: Value, r: Value, line: u32) Error!Value {
        const t = try g.tmp();
        const ty = try g.llty(l.ty);
        switch (l.ty.*) {
            .int => |i| {
                const ins: []const u8 = switch (op) {
                    .plus => "add",
                    .minus => "sub",
                    .star => "mul",
                    .slash => if (i.signed) "sdiv" else "udiv",
                    .percent => if (i.signed) "srem" else "urem",
                    .amp => "and",
                    .pipe => "or",
                    .caret => "xor",
                    .shl => "shl",
                    .shr => if (i.signed) "ashr" else "lshr",
                    else => return g.fail(line, "bad integer operator", .{}),
                };
                try g.emit("{s} = {s} {s} {s}, {s}", .{ t, ins, ty, l.v, r.v });
            },
            .float => {
                const ins: []const u8 = switch (op) {
                    .plus => "fadd",
                    .minus => "fsub",
                    .star => "fmul",
                    .slash => "fdiv",
                    .percent => "frem",
                    else => return g.fail(line, "bad float operator", .{}),
                };
                try g.emit("{s} = {s} {s} {s}, {s}", .{ t, ins, ty, l.v, r.v });
            },
            .boolean => {
                const ins: []const u8 = switch (op) {
                    .amp => "and",
                    .pipe => "or",
                    .caret => "xor",
                    else => return g.fail(line, "bad bool operator (use && / ||)", .{}),
                };
                try g.emit("{s} = {s} i1 {s}, {s}", .{ t, ins, l.v, r.v });
            },
            else => return g.fail(line, "arithmetic on '{s}' is not supported", .{try g.typeName(l.ty)}),
        }
        return .{ .ty = l.ty, .v = t };
    }

    fn compare(g: *Gen, op: Tag, l: Value, r: Value, line: u32) Error!Value {
        const t = try g.tmp();
        if (isStr(l.ty)) {
            if (op != .eqeq and op != .neq) return g.fail(line, "strings support only == and !=", .{});
            const fd = g.fns.get("__str_eq") orelse return g.fail(line, "prelude missing __str_eq", .{});
            const fi = try g.instFn(fd, Env.init(g.alloc), &.{});
            try g.emit("{s} = call i1 @{s}({{ ptr, i64 }} {s}, {{ ptr, i64 }} {s})", .{ t, fi.llname, l.v, r.v });
            if (op == .neq) {
                const t2 = try g.tmp();
                try g.emit("{s} = xor i1 {s}, true", .{ t2, t });
                return .{ .ty = g.t_bool, .v = t2 };
            }
            return .{ .ty = g.t_bool, .v = t };
        }
        switch (l.ty.*) {
            .int, .boolean, .enm, .errval, .ptr, .null_t => {
                const signed = l.ty.* == .int and l.ty.int.signed;
                const pred: []const u8 = switch (op) {
                    .eqeq => "eq",
                    .neq => "ne",
                    .lt => if (signed) "slt" else "ult",
                    .le => if (signed) "sle" else "ule",
                    .gt => if (signed) "sgt" else "ugt",
                    .ge => if (signed) "sge" else "uge",
                    else => unreachable,
                };
                try g.emit("{s} = icmp {s} {s} {s}, {s}", .{ t, pred, try g.llty(l.ty), l.v, r.v });
            },
            .float => {
                const pred: []const u8 = switch (op) {
                    .eqeq => "oeq",
                    .neq => "une",
                    .lt => "olt",
                    .le => "ole",
                    .gt => "ogt",
                    .ge => "oge",
                    else => unreachable,
                };
                try g.emit("{s} = fcmp {s} {s} {s}, {s}", .{ t, pred, try g.llty(l.ty), l.v, r.v });
            },
            else => return g.fail(line, "cannot compare '{s}'", .{try g.typeName(l.ty)}),
        }
        return .{ .ty = g.t_bool, .v = t };
    }

    fn cast(g: *Gen, v: Value, to: *const Type, line: u32) Error!Value {
        if (typeEq(v.ty, to)) return v;
        const t = try g.tmp();
        const from = try g.llty(v.ty);
        const tt = try g.llty(to);
        const src: *const Type = v.ty;
        const intlike_src = src.* == .int or src.* == .enm or src.* == .errval or src.* == .boolean;
        const intlike_dst = to.* == .int or to.* == .enm;
        if (intlike_src and intlike_dst) {
            const sb: u16 = switch (src.*) {
                .int => |i| i.bits,
                .boolean => 1,
                else => 32,
            };
            const db: u16 = if (to.* == .int) to.int.bits else 32;
            const signed = src.* == .int and src.int.signed;
            if (sb == db) return .{ .ty = to, .v = v.v };
            if (sb > db) try g.emit("{s} = trunc {s} {s} to {s}", .{ t, from, v.v, tt }) else try g.emit("{s} = {s} {s} {s} to {s}", .{ t, if (signed) "sext" else "zext", from, v.v, tt });
            return .{ .ty = to, .v = t };
        }
        if (src.* == .int and to.* == .float) {
            try g.emit("{s} = {s} {s} {s} to {s}", .{ t, if (src.int.signed) "sitofp" else "uitofp", from, v.v, tt });
            return .{ .ty = to, .v = t };
        }
        if (src.* == .float and to.* == .int) {
            try g.emit("{s} = {s} {s} {s} to {s}", .{ t, if (to.int.signed) "fptosi" else "fptoui", from, v.v, tt });
            return .{ .ty = to, .v = t };
        }
        if (src.* == .float and to.* == .float) {
            try g.emit("{s} = {s} {s} {s} to {s}", .{ t, if (to.float > src.float) "fpext" else "fptrunc", from, v.v, tt });
            return .{ .ty = to, .v = t };
        }
        if ((src.* == .ptr or src.* == .null_t) and to.* == .ptr) return .{ .ty = to, .v = v.v };
        if (src.* == .ptr and to.* == .int) {
            try g.emit("{s} = ptrtoint ptr {s} to {s}", .{ t, v.v, tt });
            return .{ .ty = to, .v = t };
        }
        if (src.* == .int and to.* == .ptr) {
            try g.emit("{s} = inttoptr {s} {s} to ptr", .{ t, from, v.v });
            return .{ .ty = to, .v = t };
        }
        if (src.* == .slice and to.* == .ptr) return g.extract(v, 0, to);
        if (src.* == .slice and to.* == .slice) return .{ .ty = to, .v = v.v };
        return g.fail(line, "cannot cast '{s}' to '{s}'", .{ try g.typeName(src), try g.typeName(to) });
    }

    // ------------------------------------------------ calls

    fn exprToTypeExpr(g: *Gen, e: *ast.Expr) Error!?*ast.TypeExpr {
        switch (e.kind) {
            .ident => |n| {
                const te = try g.alloc.create(ast.TypeExpr);
                te.* = .{ .name = .{ .name = n, .args = &.{} } };
                return te;
            },
            .index => |ix| {
                const base = (try g.exprToTypeExpr(ix.e)) orelse return null;
                var args = std.ArrayList(*ast.TypeExpr).init(g.alloc);
                for (ix.args) |a| try args.append((try g.exprToTypeExpr(a)) orelse return null);
                base.name.args = try args.toOwnedSlice();
                return base;
            },
            .unary => |u| {
                if (u.op != .star) return null;
                const inner = (try g.exprToTypeExpr(u.e)) orelse return null;
                const te = try g.alloc.create(ast.TypeExpr);
                te.* = .{ .ptr = inner };
                return te;
            },
            else => return null,
        }
    }

    /// Is `e` (syntactically) naming a type? e.g. `Point`, `List[i32]`, `Self`
    fn namesType(g: *Gen, e: *ast.Expr) bool {
        return switch (e.kind) {
            .ident => |n| g.lookupVar(n) == null and (g.structs.contains(n) or g.enums.contains(n) or g.aliases.contains(n) or (std.mem.eql(u8, n, "Self") and g.env.contains("Self"))),
            .index => |ix| ix.e.kind == .ident and g.lookupVar(ix.e.kind.ident) == null and g.structs.contains(ix.e.kind.ident),
            else => false,
        };
    }

    fn genCall(g: *Gen, e: *ast.Expr, expected: ?*const Type) Error!Value {
        const c = e.kind.call;
        switch (c.callee.kind) {
            .ident => |name| {
                if (g.lookupVar(name) == null) {
                    if (try g.genBuiltin(name, c.args, e.line)) |v| return v;
                    if (g.fns.get(name)) |decl| return g.callDecl(decl, Env.init(g.alloc), null, c.args, &.{}, expected, e.line);
                    if (!g.consts.contains(name)) return g.fail(e.line, "unknown function '{s}'", .{name});
                }
            },
            .index => |ix| {
                // explicit type arguments: max[i64](a, b), alloc.make[T](n)
                if (ix.e.kind == .ident or ix.e.kind == .field) {
                    var targs = std.ArrayList(*const Type).init(g.alloc);
                    for (ix.args) |a| {
                        const te = (try g.exprToTypeExpr(a)) orelse return g.fail(e.line, "expected a type argument", .{});
                        try targs.append(try g.resolveTypeAt(te, e.line));
                    }
                    if (ix.e.kind == .field) return g.genFieldCall(ix.e.kind.field, c.args, targs.items, expected, e.line);
                    if (g.fns.get(ix.e.kind.ident)) |decl| return g.callDecl(decl, Env.init(g.alloc), null, c.args, targs.items, expected, e.line);
                }
            },
            .field => |f| return g.genFieldCall(f, c.args, &.{}, expected, e.line),
            .enum_lit => |n| {
                // .Variant(payload) with the union type taken from context
                const t = litTarget(expected) orelse return g.fail(e.line, "cannot infer union type for '.{s}(...)'", .{n});
                if (!isUnion(t)) return g.fail(e.line, "'.{s}(...)' used where '{s}' is expected", .{ n, try g.typeName(t) });
                if (c.args.len != 1) return g.fail(e.line, "a union variant takes exactly one payload", .{});
                return g.makeUnion(t, n, c.args[0], e.line);
            },
            else => {},
        }
        // calling a function pointer value
        const fv = try g.genExpr(c.callee, null);
        return g.callIndirect(fv, c.args, e.line);
    }

    fn genFieldCall(g: *Gen, f: ast.FieldAccess, args: []*ast.Expr, explicit: []*const Type, expected: ?*const Type, line: u32) Error!Value {
        if (g.namesType(f.e)) {
            const t = try g.typeFromExpr(f.e, expected, f.name, line);
            if (isUnion(t) and fieldIndex(t.strct, f.name) != null) {
                if (args.len != 1) return g.fail(line, "a union variant takes exactly one payload", .{});
                return g.makeUnion(t, f.name, args[0], line);
            }
            // static method: Type.method(...)
            const rname = recvName(t) orelse return g.fail(line, "'{s}' has no methods", .{try g.typeName(t)});
            const key = try g.fmt("{s}.{s}", .{ rname, f.name });
            const md = g.methods.get(key) orelse return g.fail(line, "'{s}' has no method '{s}'", .{ try g.typeName(t), f.name });
            const env = try g.recvEnv(md, t);
            return g.callDecl(md, env, null, args, explicit, expected, line);
        }
        // method call on a value
        var recv = try g.genAddr(f.e);
        if (recv.ty.* == .ptr and recvName(recv.ty.ptr) != null) recv = try g.derefAgg(recv);
        const rname = recvName(recv.ty) orelse return g.fail(line, "'{s}' has no methods", .{try g.typeName(recv.ty)});
        const key = try g.fmt("{s}.{s}", .{ rname, f.name });
        if (g.methods.get(key)) |md| return g.callMethod(md, recv, args, explicit, expected, line);
        // field holding a function pointer: self.alloc_fn(ctx, n)
        if (recv.ty.* == .strct and !recv.ty.strct.decl.is_union) {
            if (fieldIndex(recv.ty.strct, f.name)) |idx| {
                const fty = recv.ty.strct.fields[idx].ty;
                if (fty.* == .func) {
                    const fp = try g.tmp();
                    try g.emit("{s} = getelementptr {s}, ptr {s}, i32 0, i32 {d}", .{ fp, try g.llty(recv.ty), recv.v, idx });
                    const fv = try g.load(fty, fp);
                    return g.callIndirect(fv, args, line);
                }
            }
        }
        return g.fail(line, "'{s}' has no method '{s}'", .{ try g.typeName(recv.ty), f.name });
    }

    fn callIndirect(g: *Gen, fv: Value, args: []*ast.Expr, line: u32) Error!Value {
        if (fv.ty.* != .func) return g.fail(line, "'{s}' is not callable", .{try g.typeName(fv.ty)});
        const sig = fv.ty.func;
        if (args.len != sig.params.len) return g.fail(line, "function pointer expects {d} argument(s), got {d}", .{ sig.params.len, args.len });
        var argtxt = std.ArrayList(u8).init(g.alloc);
        for (args, 0..) |a, i| {
            const v = try g.coerce(try g.genExpr(a, sig.params[i]), sig.params[i], a.line);
            if (i > 0) try argtxt.appendSlice(", ");
            try argtxt.writer().print("{s} {s}", .{ try g.llty(v.ty), v.v });
        }
        if (sig.ret.* == .void_) {
            try g.emit("call void {s}({s})", .{ fv.v, argtxt.items });
            return .{ .ty = g.t_void, .v = "" };
        }
        const t = try g.tmp();
        try g.emit("{s} = call {s} {s}({s})", .{ t, try g.llty(sig.ret), fv.v, argtxt.items });
        return .{ .ty = sig.ret, .v = t };
    }

    fn recvName(t: *const Type) ?[]const u8 {
        return switch (t.*) {
            .strct => |s| s.decl.name,
            .enm => |en| en.decl.name,
            else => null,
        };
    }

    fn recvEnv(g: *Gen, md: *ast.FnDecl, t: *const Type) Error!Env {
        var env = Env.init(g.alloc);
        try env.put("Self", t);
        if (t.* == .strct) {
            const args = t.strct.args;
            if (md.receiver_params.len != args.len) return g.fail(md.line, "impl for '{s}' must list {d} type parameter(s)", .{ t.strct.decl.name, args.len });
            for (md.receiver_params, 0..) |tp, i| try env.put(tp, args[i]);
        }
        return env;
    }

    fn callMethod(g: *Gen, md: *ast.FnDecl, recv: Addr, args: []*ast.Expr, explicit: []*const Type, expected: ?*const Type, line: u32) Error!Value {
        const env = try g.recvEnv(md, recv.ty);
        if (md.params.len == 0) return g.fail(line, "'{s}' is a static method; call it as Type.{s}()", .{ md.name, md.name });
        return g.callDecl(md, env, recv, args, explicit, expected, line);
    }

    fn teMentions(te: *ast.TypeExpr, names: [][]const u8) bool {
        return switch (te.*) {
            .name => |n| blk: {
                for (names) |x| if (std.mem.eql(u8, x, n.name)) break :blk true;
                for (n.args) |a| if (teMentions(a, names)) break :blk true;
                break :blk false;
            },
            .ptr, .slice, .errun => |p| teMentions(p, names),
            .array => |a| teMentions(a.elem, names),
            .func => |f| blk: {
                for (f.params) |x| if (teMentions(x, names)) break :blk true;
                if (f.ret) |r| break :blk teMentions(r, names);
                break :blk false;
            },
        };
    }

    fn unify(g: *Gen, te: *ast.TypeExpr, actual: *const Type, tparams: [][]const u8, env: *Env) Error!void {
        switch (te.*) {
            .name => |n| {
                if (n.args.len == 0) {
                    for (tparams) |tp| {
                        if (std.mem.eql(u8, tp, n.name)) {
                            if (!env.contains(tp)) try env.put(tp, actual);
                            return;
                        }
                    }
                    return;
                }
                if (actual.* == .strct and std.mem.eql(u8, actual.strct.decl.name, n.name)) {
                    for (n.args, 0..) |a, i| if (i < actual.strct.args.len) try g.unify(a, actual.strct.args[i], tparams, env);
                }
            },
            .ptr => |p| if (actual.* == .ptr) try g.unify(p, actual.ptr, tparams, env),
            .slice => |p| if (actual.* == .slice) try g.unify(p, actual.slice, tparams, env),
            .errun => |p| if (actual.* == .errun) try g.unify(p, actual.errun, tparams, env),
            .array => |a| if (actual.* == .array) try g.unify(a.elem, actual.array.elem, tparams, env),
            .func => |f| if (actual.* == .func and actual.func.params.len == f.params.len) {
                for (f.params, 0..) |x, i| try g.unify(x, actual.func.params[i], tparams, env);
                if (f.ret) |r| try g.unify(r, actual.func.ret, tparams, env);
            },
        }
    }

    fn callDecl(g: *Gen, decl: *ast.FnDecl, base_env: Env, recv: ?Addr, args: []*ast.Expr, explicit: []*const Type, expected: ?*const Type, line: u32) Error!Value {
        const off: usize = if (recv != null) 1 else 0;
        if (!decl.variadic and args.len + off != decl.params.len) return g.fail(line, "'{s}' expects {d} argument(s), got {d}", .{ decl.name, decl.params.len - off, args.len });
        if (decl.variadic and args.len + off < decl.params.len) return g.fail(line, "'{s}' expects at least {d} argument(s)", .{ decl.name, decl.params.len - off });

        var env = Env.init(g.alloc);
        var bit = base_env.iterator();
        while (bit.next()) |kv| try env.put(kv.key_ptr.*, kv.value_ptr.*);
        const tps = decl.type_params;
        if (explicit.len > 0) {
            if (explicit.len != tps.len) return g.fail(line, "'{s}' expects {d} type argument(s)", .{ decl.name, tps.len });
            for (tps, 0..) |tp, i| try env.put(tp, explicit[i]);
        }

        const vals = try g.alloc.alloc(?Value, args.len);
        @memset(vals, null);
        // pass 1: non-literal args (to infer generics)
        for (args, 0..) |a, i| {
            const pi = i + off;
            if (pi >= decl.params.len) continue;
            const pte = decl.params[pi].ty;
            const generic = teMentions(pte, tps);
            if (generic and !allBound(tps, &env) and isLiteral(a)) continue;
            var exp: ?*const Type = null;
            if (!generic or allBound(tps, &env)) exp = try g.resolveType(pte, &env);
            const v = try g.genExpr(a, exp);
            vals[i] = v;
            if (generic) try g.unify(pte, v.ty, tps, &env);
        }
        // pass 2: literals, now with known types
        for (args, 0..) |a, i| {
            if (vals[i] != null) continue;
            const pi = i + off;
            if (pi >= decl.params.len) continue;
            const pte = decl.params[pi].ty;
            const exp: ?*const Type = if (allBound(tps, &env)) try g.resolveType(pte, &env) else null;
            const v = try g.genExpr(a, exp);
            vals[i] = v;
            try g.unify(pte, v.ty, tps, &env);
        }
        // receiver might drive inference too
        if (recv) |r| {
            const pte = decl.params[0].ty;
            if (pte.* == .ptr) try g.unify(pte.ptr, r.ty, tps, &env) else try g.unify(pte, r.ty, tps, &env);
        }
        // return type from expected
        if (!allBound(tps, &env)) if (decl.ret) |rte| if (expected) |ex| try g.unify(rte, ex, tps, &env);
        if (!allBound(tps, &env)) return g.fail(line, "cannot infer type parameters of '{s}'", .{decl.name});

        var targs = std.ArrayList(*const Type).init(g.alloc);
        for (tps) |tp| try targs.append(env.get(tp).?);
        const fi = try g.instFn(decl, env, targs.items);

        var argtxt = std.ArrayList(u8).init(g.alloc);
        if (recv) |r| {
            const pt = fi.params[0];
            if (pt.* == .ptr) {
                try argtxt.writer().print("ptr {s}", .{r.v});
            } else {
                const rv = try g.load(r.ty, r.v);
                const cv = try g.coerce(rv, pt, line);
                try argtxt.writer().print("{s} {s}", .{ try g.llty(pt), cv.v });
            }
        }
        // remaining args (variadic C args get default promotions)
        for (args, 0..) |a, i| {
            const pi = i + off;
            if (vals[i] == null) vals[i] = try g.genExpr(a, if (a.kind == .str_lit) g.t_ptr_u8 else null);
            var v = vals[i].?;
            if (pi < fi.params.len) {
                v = try g.coerce(v, fi.params[pi], a.line);
            } else {
                v = try g.cPromote(v, a.line);
            }
            if (argtxt.items.len > 0) try argtxt.appendSlice(", ");
            try argtxt.writer().print("{s} {s}", .{ try g.llty(v.ty), v.v });
        }

        var fnty: []const u8 = "";
        if (decl.variadic) {
            var ft = std.ArrayList(u8).init(g.alloc);
            try ft.writer().print("{s} (", .{try g.llty(fi.ret)});
            for (fi.params, 0..) |p, i| {
                if (i > 0) try ft.appendSlice(", ");
                try ft.appendSlice(try g.llty(p));
            }
            try ft.appendSlice(if (fi.params.len > 0) ", ...)" else "...)");
            fnty = ft.items;
        } else fnty = try g.llty(fi.ret);

        if (fi.ret.* == .void_) {
            try g.emit("call {s} @{s}({s})", .{ fnty, fi.llname, argtxt.items });
            return .{ .ty = g.t_void, .v = "" };
        }
        const t = try g.tmp();
        try g.emit("{s} = call {s} @{s}({s})", .{ t, fnty, fi.llname, argtxt.items });
        return .{ .ty = fi.ret, .v = t };
    }

    fn allBound(tps: [][]const u8, env: *Env) bool {
        for (tps) |tp| if (!env.contains(tp)) return false;
        return true;
    }

    fn cPromote(g: *Gen, v: Value, line: u32) Error!Value {
        switch (v.ty.*) {
            .int => |i| if (i.bits < 32) return g.cast(v, if (i.signed) g.t_i32 else try g.mk(.{ .int = .{ .bits = 32, .signed = false } }), line),
            .boolean => return g.cast(v, g.t_i32, line),
            .float => |f| if (f == 32) return g.cast(v, g.t_f64, line),
            .slice => return g.fail(line, "slices cannot be passed to C varargs; pass .ptr (and .len) explicitly", .{}),
            .null_t => return .{ .ty = g.t_ptr_u8, .v = "null" },
            else => {},
        }
        return v;
    }

    // ------------------------------------------------ builtins: print & friends

    fn genBuiltin(g: *Gen, name: []const u8, args: []*ast.Expr, line: u32) Error!?Value {
        const is_print = std.mem.eql(u8, name, "print");
        const is_println = std.mem.eql(u8, name, "println");
        const is_eprintln = std.mem.eql(u8, name, "eprintln");
        const is_eprint = is_eprintln or std.mem.eql(u8, name, "eprint");
        if (std.mem.eql(u8, name, "embed")) {
            // embed("file") -> str with the file's bytes, path relative to the current source file
            if (args.len != 1 or args[0].kind != .str_lit) return g.fail(line, "embed takes one string literal", .{});
            const dir = std.fs.path.dirname(g.file) orelse ".";
            const path = try std.fs.path.join(g.alloc, &.{ dir, args[0].kind.str_lit });
            const data = std.fs.cwd().readFileAlloc(g.alloc, path, 64 << 20) catch return g.fail(line, "embed: cannot read '{s}'", .{path});
            const gname = try g.strGlobal(data);
            return Value{ .ty = g.t_str, .v = try g.fmt("{{ ptr {s}, i64 {d} }}", .{ gname, data.len }) };
        }
        if (is_print or is_println or is_eprint) {
            if (g.fns.contains(name)) return null;
            var b = g.newFmt(false);
            for (args, 0..) |a, i| {
                if (i > 0) try b.fmt.append(' ');
                switch (a.kind) {
                    .interp => |parts| try g.fmtParts(&b, parts, a.line),
                    .str_lit => |s| try fmtLit(&b, s),
                    else => try g.fmtValue(&b, try g.genExpr(a, null), a.line, 0),
                }
            }
            if (is_println or is_eprintln) try b.fmt.append('\n');
            try g.flushPrint(&b, if (is_eprint) 2 else 1);
            return Value{ .ty = g.t_void, .v = "" };
        }
        if (std.mem.eql(u8, name, "bprint")) {
            // bprint(buf: []u8, ...) !str  -- format into a caller-owned buffer, no allocation
            if (args.len < 1) return g.fail(line, "bprint(buf, ...) needs a buffer", .{});
            const buf = try g.genExpr(args[0], null);
            if (!isStr(buf.ty)) return g.fail(line, "bprint: first argument must be a []u8 buffer, got '{s}'", .{try g.typeName(buf.ty)});
            var b = g.newFmt(true);
            for (args[1..], 0..) |a, i| {
                if (i > 0) try b.fmt.append(' ');
                switch (a.kind) {
                    .interp => |parts| try g.fmtParts(&b, parts, a.line),
                    .str_lit => |s| try fmtLit(&b, s),
                    else => try g.fmtValue(&b, try g.genExpr(a, null), a.line, 0),
                }
            }
            try g.declare("snprintf", "declare i32 @snprintf(ptr, i64, ptr, ...)");
            const f = try g.strGlobal(b.fmt.items);
            const bp = try g.extract(buf, 0, g.t_ptr_u8);
            const bl = try g.extract(buf, 1, g.t_i64);
            const n = try g.tmp();
            try g.emit("{s} = call i32 (ptr, i64, ptr, ...) @snprintf(ptr {s}, i64 {s}, ptr {s}{s})", .{ n, bp.v, bl.v, f, b.args.items });
            const n64 = try g.tmp();
            try g.emit("{s} = sext i32 {s} to i64", .{ n64, n });
            const bad = try g.tmp();
            try g.emit("{s} = icmp uge i64 {s}, {s}", .{ bad, n64, bl.v });
            const tag = try g.tmp();
            try g.emit("{s} = select i1 {s}, i32 {d}, i32 0", .{ tag, bad, try g.errorId("NoSpace") });
            const et = try g.mk(.{ .errun = g.t_str });
            const s1 = try g.insert(g.t_str, "undef", bp, 0);
            const s2 = try g.insert(g.t_str, s1, .{ .ty = g.t_i64, .v = n64 }, 1);
            const r1 = try g.insert(et, "undef", .{ .ty = g.t_i32, .v = tag }, 0);
            const r2 = try g.insert(et, r1, .{ .ty = g.t_str, .v = s2 }, 1);
            return Value{ .ty = et, .v = r2 };
        }
        if (std.mem.eql(u8, name, "sprint")) {
            // sprint(out: *List[u8], ...) !void -- append formatted text; growth goes through the list's allocator
            if (args.len < 1) return g.fail(line, "sprint(&list, ...) needs a *List[u8]", .{});
            const out = try g.genExpr(args[0], null);
            const ok_ty = out.ty.* == .ptr and out.ty.ptr.* == .strct and std.mem.eql(u8, out.ty.ptr.strct.decl.name, "List") and
                out.ty.ptr.strct.args.len == 1 and out.ty.ptr.strct.args[0].* == .int and out.ty.ptr.strct.args[0].int.bits == 8;
            if (!ok_ty) return g.fail(line, "sprint: first argument must be *List[u8], got '{s}'", .{try g.typeName(out.ty)});
            const lt = out.ty.ptr;
            var b = g.newFmt(true);
            for (args[1..], 0..) |a, i| {
                if (i > 0) try b.fmt.append(' ');
                switch (a.kind) {
                    .interp => |parts| try g.fmtParts(&b, parts, a.line),
                    .str_lit => |s| try fmtLit(&b, s),
                    else => try g.fmtValue(&b, try g.genExpr(a, null), a.line, 0),
                }
            }
            try g.declare("snprintf", "declare i32 @snprintf(ptr, i64, ptr, ...)");
            const f = try g.strGlobal(b.fmt.items);
            const n = try g.tmp();
            try g.emit("{s} = call i32 (ptr, i64, ptr, ...) @snprintf(ptr null, i64 0, ptr {s}{s})", .{ n, f, b.args.items });
            const n64 = try g.tmp();
            try g.emit("{s} = sext i32 {s} to i64", .{ n64, n });
            // hidden locals so we can reuse the normal method-call path for reserve()
            g.ntmp += 1;
            const lname = try g.fmt("__sp{d}", .{g.ntmp});
            const nname = try g.fmt("__spn{d}", .{g.ntmp});
            const lslot = try g.alloca(out.ty, "sp");
            try g.store(out, lslot);
            const nslot = try g.alloca(g.t_i64, "spn");
            try g.store(.{ .ty = g.t_i64, .v = n64 }, nslot);
            try g.declareVar(lname, .{ .ptr = lslot, .ty = out.ty, .mutable = false }, line);
            try g.declareVar(nname, .{ .ptr = nslot, .ty = g.t_i64, .mutable = false }, line);
            const A = struct {
                fn mk(gg: *Gen, ln: u32, k: ast.Expr.Kind) Error!*ast.Expr {
                    const e = try gg.alloc.create(ast.Expr);
                    e.* = .{ .line = ln, .kind = k };
                    return e;
                }
            };
            const lid = try A.mk(g, line, .{ .ident = lname });
            const need = try A.mk(g, line, .{ .binary = .{ .op = .plus, .l = try A.mk(g, line, .{ .binary = .{ .op = .plus, .l = try A.mk(g, line, .{ .field = .{ .e = lid, .name = "len" } }), .r = try A.mk(g, line, .{ .ident = nname }) } }), .r = try A.mk(g, line, .{ .int_lit = 1 }) } });
            const call_args = try g.alloc.alloc(*ast.Expr, 1);
            call_args[0] = need;
            const call = try A.mk(g, line, .{ .call = .{ .callee = try A.mk(g, line, .{ .field = .{ .e = lid, .name = "reserve" } }), .args = call_args } });
            const r = try g.genExpr(call, null);
            const tag = try g.extract(r, 0, g.t_i32);
            const c = try g.tmp();
            try g.emit("{s} = icmp eq i32 {s}, 0", .{ c, tag.v });
            const lok = try g.newLabel("spok");
            const lend = try g.newLabel("spend");
            try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c, lok, lend });
            try g.label(lok);
            const si = lt.strct;
            const ii = fieldIndex(si, "items").?;
            const li = fieldIndex(si, "len").?;
            const llt = try g.llty(lt);
            const ip = try g.tmp();
            try g.emit("{s} = getelementptr {s}, ptr {s}, i32 0, i32 {d}", .{ ip, llt, out.v, ii });
            const items = try g.load(g.t_str, ip);
            const base = try g.extract(items, 0, g.t_ptr_u8);
            const lp = try g.tmp();
            try g.emit("{s} = getelementptr {s}, ptr {s}, i32 0, i32 {d}", .{ lp, llt, out.v, li });
            const cur = try g.load(g.t_i64, lp);
            const dst = try g.tmp();
            try g.emit("{s} = getelementptr i8, ptr {s}, i64 {s}", .{ dst, base.v, cur.v });
            const n1 = try g.tmp();
            try g.emit("{s} = add i64 {s}, 1", .{ n1, n64 });
            try g.emit("call i32 (ptr, i64, ptr, ...) @snprintf(ptr {s}, i64 {s}, ptr {s}{s})", .{ dst, n1, f, b.args.items });
            const nl = try g.tmp();
            try g.emit("{s} = add i64 {s}, {s}", .{ nl, cur.v, n64 });
            try g.store(.{ .ty = g.t_i64, .v = nl }, lp);
            try g.br(lend);
            try g.label(lend);
            return r;
        }
        if (std.mem.eql(u8, name, "panic")) {
            if (args.len != 1) return g.fail(line, "panic takes one argument", .{});
            var b = g.newFmt(false);
            try fmtLit(&b, "panic: ");
            switch (args[0].kind) {
                .interp => |parts| try g.fmtParts(&b, parts, line),
                .str_lit => |s| try fmtLit(&b, s),
                else => try g.fmtValue(&b, try g.genExpr(args[0], null), line, 0),
            }
            try b.fmt.writer().print(" ({s}:{d})\n", .{ g.file, line });
            try g.flushPrint(&b, 2);
            try g.declare("exit", "declare void @exit(i32)");
            try g.emit("call void @exit(i32 1)", .{});
            try g.emitTerm("unreachable", .{});
            return Value{ .ty = g.t_void, .v = "" };
        }
        if (std.mem.eql(u8, name, "assert")) {
            if (args.len != 1) return g.fail(line, "assert takes one argument", .{});
            const c = try g.genCond(args[0]);
            const lbad = try g.newLabel("afail");
            const lok = try g.newLabel("aok");
            try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c.v, lok, lbad });
            try g.label(lbad);
            var b = g.newFmt(false);
            try b.fmt.writer().print("assertion failed ({s}:{d})\n", .{ g.file, line });
            try g.flushPrint(&b, 2);
            try g.declare("exit", "declare void @exit(i32)");
            try g.emit("call void @exit(i32 1)", .{});
            try g.emitTerm("unreachable", .{});
            try g.label(lok);
            return Value{ .ty = g.t_void, .v = "" };
        }
        return null;
    }

    fn newFmt(g: *Gen, string_mode: bool) FmtBuilder {
        return .{ .fmt = std.ArrayList(u8).init(g.alloc), .args = std.ArrayList(u8).init(g.alloc), .string_mode = string_mode };
    }

    fn fmtLit(b: *FmtBuilder, s: []const u8) Error!void {
        for (s) |ch| {
            if (ch == '%') try b.fmt.appendSlice("%%") else try b.fmt.append(ch);
        }
    }

    fn fmtArg(g: *Gen, b: *FmtBuilder, ty: []const u8, v: []const u8) Error!void {
        _ = g;
        try b.args.writer().print(", {s} {s}", .{ ty, v });
    }

    fn fmtParts(g: *Gen, b: *FmtBuilder, parts: []ast.InterpPart, line: u32) Error!void {
        for (parts) |p| switch (p) {
            .lit => |s| try fmtLit(b, s),
            .expr => |e| try g.fmtValue(b, try g.genExpr(e, null), line, 0),
            .spec => |sp| try g.fmtSpec(b, try g.genExpr(sp.e, null), sp.spec, line),
        };
    }

    /// {v:spec}: printf-style flags/width/precision + optional conversion letter (x X o d u c e f g s)
    fn fmtSpec(g: *Gen, b: *FmtBuilder, v: Value, spec: []const u8, line: u32) Error!void {
        for (spec) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '.' or ch == '-' or ch == '+' or ch == ' ' or ch == '#'))
            return g.fail(line, "bad format spec '{s}'", .{spec});
        var flags = spec;
        var conv: u8 = 0;
        if (spec.len > 0 and std.ascii.isAlphabetic(spec[spec.len - 1])) {
            conv = spec[spec.len - 1];
            flags = spec[0 .. spec.len - 1];
        }
        switch (v.ty.*) {
            .int => |i| {
                if (conv == 'c') {
                    const w = try g.cast(v, g.t_i32, line);
                    try b.fmt.writer().print("%{s}c", .{flags});
                    try g.fmtArg(b, "i32", w.v);
                    return;
                }
                if (conv == 0) conv = if (i.signed) 'd' else 'u';
                if (std.mem.indexOfScalar(u8, "dixXou", conv) == null) return g.fail(line, "format '{c}' is not valid for integers", .{conv});
                const w = try g.cast(v, if (i.signed) g.t_i64 else g.t_u64, line);
                try b.fmt.writer().print("%{s}ll{c}", .{ flags, conv });
                try g.fmtArg(b, "i64", w.v);
            },
            .float => {
                if (conv == 0) conv = 'f';
                if (std.mem.indexOfScalar(u8, "eEfFgGaA", conv) == null) return g.fail(line, "format '{c}' is not valid for floats", .{conv});
                const w = try g.cast(v, g.t_f64, line);
                try b.fmt.writer().print("%{s}{c}", .{ flags, conv });
                try g.fmtArg(b, "double", w.v);
            },
            else => {
                if (isStr(v.ty)) {
                    // width/alignment for strings: {name:-10}
                    const l = try g.extract(v, 1, g.t_i64);
                    const p = try g.extract(v, 0, g.t_ptr_u8);
                    const l32 = try g.tmp();
                    try g.emit("{s} = trunc i64 {s} to i32", .{ l32, l.v });
                    try b.fmt.writer().print("%{s}.*s", .{flags});
                    try g.fmtArg(b, "i32", l32);
                    try g.fmtArg(b, "ptr", p.v);
                    return;
                }
                return g.fail(line, "format specs apply to integers, floats and str, not '{s}'", .{try g.typeName(v.ty)});
            },
        }
    }

    fn fmtValue(g: *Gen, b: *FmtBuilder, v: Value, line: u32, depth: u32) Error!void {
        if (isStr(v.ty)) {
            const l = try g.extract(v, 1, g.t_i64);
            const p = try g.extract(v, 0, g.t_ptr_u8);
            const l32 = try g.tmp();
            try g.emit("{s} = trunc i64 {s} to i32", .{ l32, l.v });
            try b.fmt.appendSlice(if (depth > 0) "\"%.*s\"" else "%.*s");
            try g.fmtArg(b, "i32", l32);
            try g.fmtArg(b, "ptr", p.v);
            return;
        }
        switch (v.ty.*) {
            .int => |i| {
                const w = try g.cast(v, if (i.signed) g.t_i64 else g.t_u64, line);
                try b.fmt.appendSlice(if (i.signed) "%lld" else "%llu");
                try g.fmtArg(b, "i64", w.v);
            },
            .float => {
                const w = try g.cast(v, g.t_f64, line);
                try b.fmt.appendSlice("%g");
                try g.fmtArg(b, "double", w.v);
            },
            .boolean => {
                const ts = try g.strGlobal("true");
                const fs = try g.strGlobal("false");
                const t = try g.tmp();
                try g.emit("{s} = select i1 {s}, ptr {s}, ptr {s}", .{ t, v.v, ts, fs });
                try b.fmt.appendSlice("%s");
                try g.fmtArg(b, "ptr", t);
            },
            .ptr, .null_t => {
                try b.fmt.appendSlice("%p");
                try g.fmtArg(b, "ptr", v.v);
            },
            .enm => |en| {
                const p = try g.tmp();
                try g.emit("{s} = getelementptr ptr, ptr {s}, i32 {s}", .{ p, en.names_global, v.v });
                const n = try g.load(g.t_ptr_u8, p);
                try b.fmt.appendSlice(".%s");
                try g.fmtArg(b, "ptr", n.v);
            },
            .errval => {
                const p = try g.tmp();
                try g.emit("{s} = getelementptr ptr, ptr @__vibe_errnames, i32 {s}", .{ p, v.v });
                const n = try g.load(g.t_ptr_u8, p);
                try b.fmt.appendSlice("error.%s");
                try g.fmtArg(b, "ptr", n.v);
            },
            .void_ => try fmtLit(b, "void"),
            .func => {
                try b.fmt.appendSlice("fn@%p");
                try g.fmtArg(b, "ptr", v.v);
            },
            .strct => |si| if (si.decl.is_union) {
                const slot = (try g.spill(v)).v;
                const lt = try g.llty(v.ty);
                const tp = try g.tmp();
                try g.emit("{s} = getelementptr {s}, ptr {s}, i32 0, i32 0", .{ tp, lt, slot });
                const tag = try g.load(g.t_i32, tp);
                if (b.string_mode or depth > 0) {
                    const np = try g.tmp();
                    try g.emit("{s} = getelementptr ptr, ptr {s}, i32 {s}", .{ np, si.names_global, tag.v });
                    const n = try g.load(g.t_ptr_u8, np);
                    try fmtLit(b, si.display);
                    try b.fmt.appendSlice(".%s");
                    try g.fmtArg(b, "ptr", n.v);
                    return;
                }
                try g.flushPrint(b, 1);
                const pp = try g.tmp();
                try g.emit("{s} = getelementptr {s}, ptr {s}, i32 0, i32 1", .{ pp, lt, slot });
                const lend = try g.newLabel("pu");
                for (si.fields, 0..) |f, i| {
                    const lb = try g.newLabel("puv");
                    const ln = try g.newLabel("pun");
                    const c = try g.tmp();
                    try g.emit("{s} = icmp eq i32 {s}, {d}", .{ c, tag.v, i });
                    try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c, lb, ln });
                    try g.label(lb);
                    var b2 = g.newFmt(false);
                    try fmtLit(&b2, si.display);
                    try b2.fmt.append('.');
                    try fmtLit(&b2, f.name);
                    if (f.ty.* != .void_) {
                        try b2.fmt.append('(');
                        try g.fmtValue(&b2, try g.load(f.ty, pp), line, depth + 1);
                        try b2.fmt.append(')');
                    }
                    try g.flushPrint(&b2, 1);
                    try g.br(lend);
                    try g.label(ln);
                }
                try g.label(lend);
            } else {
                try fmtLit(b, si.display);
                try b.fmt.appendSlice("{ ");
                for (si.fields, 0..) |f, i| {
                    if (i > 0) try b.fmt.appendSlice(", ");
                    try fmtLit(b, f.name);
                    try b.fmt.appendSlice(": ");
                    if (depth > 4) {
                        try b.fmt.appendSlice("...");
                    } else try g.fmtValue(b, try g.extract(v, i, f.ty), line, depth + 1);
                }
                try b.fmt.appendSlice(" }");
            },
            .array => |a| {
                try b.fmt.append('[');
                const n: usize = @intCast(@min(a.len, 32));
                for (0..n) |i| {
                    if (i > 0) try b.fmt.appendSlice(", ");
                    try g.fmtValue(b, try g.extract(v, i, a.elem), line, depth + 1);
                }
                if (a.len > n) try b.fmt.appendSlice(", ...");
                try b.fmt.append(']');
            },
            .slice => |el| {
                if (b.string_mode or depth > 0) {
                    const l = try g.extract(v, 1, g.t_i64);
                    try b.fmt.appendSlice("[]");
                    try fmtLit(b, try g.typeName(el));
                    try b.fmt.appendSlice("(len=%lld)");
                    try g.fmtArg(b, "i64", l.v);
                    return;
                }
                // print mode: emit a loop
                try b.fmt.append('[');
                try g.flushPrint(b, 1);
                const p = try g.extract(v, 0, g.t_ptr_u8);
                const l = try g.extract(v, 1, g.t_i64);
                const it = try g.alloca(g.t_i64, "pi");
                try g.store(.{ .ty = g.t_i64, .v = "0" }, it);
                const lc = try g.newLabel("pc");
                const lb = try g.newLabel("pb");
                const le = try g.newLabel("pe");
                try g.label(lc);
                const cur = try g.load(g.t_i64, it);
                const c = try g.tmp();
                try g.emit("{s} = icmp slt i64 {s}, {s}", .{ c, cur.v, l.v });
                try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c, lb, le });
                try g.label(lb);
                const isfirst = try g.tmp();
                try g.emit("{s} = icmp eq i64 {s}, 0", .{ isfirst, cur.v });
                const es = try g.strGlobal("");
                const cs = try g.strGlobal(", ");
                const sep = try g.tmp();
                try g.emit("{s} = select i1 {s}, ptr {s}, ptr {s}", .{ sep, isfirst, es, cs });
                var b2 = g.newFmt(false);
                try b2.fmt.appendSlice("%s");
                try g.fmtArg(&b2, "ptr", sep);
                const ep = try g.tmp();
                try g.emit("{s} = getelementptr {s}, ptr {s}, i64 {s}", .{ ep, try g.llty(el), p.v, cur.v });
                const ev = try g.load(el, ep);
                try g.fmtValue(&b2, ev, line, depth + 1);
                try g.flushPrint(&b2, 1);
                const nx = try g.tmp();
                try g.emit("{s} = add i64 {s}, 1", .{ nx, cur.v });
                try g.store(.{ .ty = g.t_i64, .v = nx }, it);
                try g.br(lc);
                try g.label(le);
                try b.fmt.append(']');
            },
            .errun => |inner| {
                // print value or error name
                const tag = try g.extract(v, 0, g.t_i32);
                if (inner.* == .void_ or b.string_mode) {
                    try g.fmtValue(b, .{ .ty = g.t_errval, .v = tag.v }, line, depth);
                    return;
                }
                const c = try g.tmp();
                try g.emit("{s} = icmp ne i32 {s}, 0", .{ c, tag.v });
                const lerr = try g.newLabel("pee");
                const lok = try g.newLabel("peo");
                const lend = try g.newLabel("pend");
                try g.flushPrint(b, 1);
                try g.emitTerm("br i1 {s}, label %{s}, label %{s}", .{ c, lerr, lok });
                try g.label(lerr);
                var b1 = g.newFmt(false);
                try g.fmtValue(&b1, .{ .ty = g.t_errval, .v = tag.v }, line, depth);
                try g.flushPrint(&b1, 1);
                try g.br(lend);
                try g.label(lok);
                var b2 = g.newFmt(false);
                try g.fmtValue(&b2, try g.extract(v, 1, inner), line, depth);
                try g.flushPrint(&b2, 1);
                try g.br(lend);
                try g.label(lend);
            },
        }
    }

    fn flushPrint(g: *Gen, b: *FmtBuilder, fd: i32) Error!void {
        if (b.fmt.items.len == 0) return;
        const f = try g.strGlobal(b.fmt.items);
        if (fd == 1) {
            try g.declare("printf", "declare i32 @printf(ptr, ...)");
            try g.emit("call i32 (ptr, ...) @printf(ptr {s}{s})", .{ f, b.args.items });
        } else {
            try g.declare("fflush", "declare i32 @fflush(ptr)");
            try g.emit("call i32 @fflush(ptr null)", .{});
            try g.declare("dprintf", "declare i32 @dprintf(i32, ptr, ...)");
            try g.emit("call i32 (i32, ptr, ...) @dprintf(i32 {d}, ptr {s}{s})", .{ fd, f, b.args.items });
        }
        b.fmt.clearRetainingCapacity();
        b.args.clearRetainingCapacity();
    }

};
