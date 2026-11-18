const std = @import("std");
const Tag = @import("lexer.zig").Tag;

pub const TypeExpr = union(enum) {
    name: struct { name: []const u8, args: []*TypeExpr },
    ptr: *TypeExpr,
    slice: *TypeExpr,
    array: struct { len: *Expr, elem: *TypeExpr },
    errun: *TypeExpr,
    func: struct { params: []*TypeExpr, ret: ?*TypeExpr },
};

pub const FieldAccess = struct { e: *Expr, name: []const u8 };
pub const FieldInit = struct { name: []const u8, value: *Expr };

pub const InterpPart = union(enum) {
    lit: []const u8,
    expr: *Expr,
    spec: struct { e: *Expr, spec: []const u8 }, // {x:08x}
};

pub const Expr = struct {
    line: u32,
    kind: Kind,

    pub const Kind = union(enum) {
        int_lit: u64,
        float_lit: f64,
        bool_lit: bool,
        str_lit: []const u8,
        interp: []InterpPart,
        null_lit,
        ident: []const u8,
        enum_lit: []const u8, // .Red
        error_val: []const u8, // error.NotFound
        binary: struct { op: Tag, l: *Expr, r: *Expr },
        unary: struct { op: Tag, e: *Expr },
        call: struct { callee: *Expr, args: []*Expr },
        field: FieldAccess,
        index: struct { e: *Expr, args: []*Expr },
        slice: struct { e: *Expr, lo: ?*Expr, hi: ?*Expr },
        struct_lit: struct { ty: *TypeExpr, fields: []FieldInit, zero_rest: bool },
        array_lit: []*Expr,
        cast: struct { e: *Expr, ty: *TypeExpr },
        try_: *Expr,
        catch_: struct { e: *Expr, err_name: ?[]const u8, handler: *Stmt },
        sizeof: *TypeExpr,
        alignof: *TypeExpr,
        is_: struct { e: *Expr, variant: []const u8 },
    };
};

pub const MatchArm = struct {
    pats: []*Expr, // empty => wildcard `_`
    body: *Stmt,
};

pub const Stmt = struct {
    line: u32,
    kind: Kind,

    pub const Kind = union(enum) {
        let: struct { name: []const u8, mutable: bool, ty: ?*TypeExpr, init: ?*Expr },
        assign: struct { op: Tag, target: *Expr, value: *Expr },
        expr: *Expr,
        if_: struct { cond: *Expr, then: *Stmt, els: ?*Stmt },
        while_: struct { cond: *Expr, body: *Stmt },
        for_range: struct { name: []const u8, lo: *Expr, hi: *Expr, body: *Stmt },
        for_each: struct { idx: ?[]const u8, name: []const u8, seq: *Expr, body: *Stmt },
        ret: ?*Expr,
        brk,
        cont,
        block: []*Stmt,
        defer_: struct { body: *Stmt, is_err: bool },
        match_: struct { value: *Expr, arms: []MatchArm },
    };
};

pub const Param = struct { name: []const u8, ty: *TypeExpr };

pub const FnDecl = struct {
    name: []const u8,
    type_params: [][]const u8,
    params: []Param,
    ret: ?*TypeExpr,
    body: ?*Stmt,
    is_extern: bool,
    is_export: bool,
    variadic: bool,
    line: u32,
    file: []const u8,
    // for methods inside `impl X[T]`
    receiver: ?[]const u8 = null,
    receiver_params: [][]const u8 = &.{},
};

pub const Field = struct { name: []const u8, ty: *TypeExpr };

pub const StructDecl = struct {
    name: []const u8,
    type_params: [][]const u8,
    fields: []Field,
    line: u32,
    is_union: bool = false,
};

pub const EnumDecl = struct {
    name: []const u8,
    variants: [][]const u8,
    line: u32,
};

pub const ConstDecl = struct {
    name: []const u8,
    ty: ?*TypeExpr,
    value: *Expr,
    mutable: bool, // top-level `var` => global variable
    line: u32,
};

pub const Decl = union(enum) {
    func: *FnDecl,
    strct: *StructDecl,
    enm: *EnumDecl,
    constant: *ConstDecl,
    import: []const u8,
    alias: struct { name: []const u8, ty: *TypeExpr, line: u32 },
};
