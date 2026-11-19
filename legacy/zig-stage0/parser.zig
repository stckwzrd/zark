const std = @import("std");
const lex = @import("lexer.zig");
const ast = @import("ast.zig");
const Tag = lex.Tag;
const Token = lex.Token;

pub const ParseError = error{ ParseFailed, OutOfMemory, LexFailed };

pub const Parser = struct {
    alloc: std.mem.Allocator,
    toks: []Token,
    pos: usize = 0,
    file: []const u8,
    no_struct: bool = false,

    pub fn init(alloc: std.mem.Allocator, toks: []Token, file: []const u8) Parser {
        return .{ .alloc = alloc, .toks = toks, .file = file };
    }

    fn peek(p: *Parser) Token {
        return p.toks[p.pos];
    }
    fn peekAt(p: *Parser, n: usize) Token {
        const i = @min(p.pos + n, p.toks.len - 1);
        return p.toks[i];
    }
    fn at(p: *Parser, t: Tag) bool {
        return p.toks[p.pos].tag == t;
    }
    fn advance(p: *Parser) Token {
        const t = p.toks[p.pos];
        if (p.pos < p.toks.len - 1) p.pos += 1;
        return t;
    }
    fn eat(p: *Parser, t: Tag) bool {
        if (p.at(t)) {
            _ = p.advance();
            return true;
        }
        return false;
    }
    fn fail(p: *Parser, comptime fmt: []const u8, args: anytype) ParseError {
        const t = p.peek();
        std.debug.print("{s}:{d}: error: ", .{ p.file, t.line });
        std.debug.print(fmt, args);
        std.debug.print(" (near '{s}')\n", .{t.text});
        return error.ParseFailed;
    }
    fn expect(p: *Parser, t: Tag) ParseError!Token {
        if (!p.at(t)) return p.fail("expected {s}", .{@tagName(t)});
        return p.advance();
    }
    fn skipSemis(p: *Parser) void {
        while (p.at(.semi)) _ = p.advance();
    }
    fn new(p: *Parser, comptime T: type, v: T) ParseError!*T {
        const ptr = try p.alloc.create(T);
        ptr.* = v;
        return ptr;
    }
    fn mkExpr(p: *Parser, line: u32, kind: ast.Expr.Kind) ParseError!*ast.Expr {
        return p.new(ast.Expr, .{ .line = line, .kind = kind });
    }
    fn mkStmt(p: *Parser, line: u32, kind: ast.Stmt.Kind) ParseError!*ast.Stmt {
        return p.new(ast.Stmt, .{ .line = line, .kind = kind });
    }

    // ---------------- declarations ----------------

    pub fn parseFile(p: *Parser) ParseError![]ast.Decl {
        var decls = std.ArrayList(ast.Decl).init(p.alloc);
        p.skipSemis();
        while (!p.at(.eof)) {
            try p.parseDecl(&decls);
            p.skipSemis();
        }
        return decls.toOwnedSlice();
    }

    fn parseTypeParams(p: *Parser) ParseError![][]const u8 {
        var list = std.ArrayList([]const u8).init(p.alloc);
        if (p.eat(.lbracket)) {
            while (!p.at(.rbracket)) {
                try list.append((try p.expect(.ident)).text);
                if (!p.eat(.comma)) break;
            }
            _ = try p.expect(.rbracket);
        }
        return list.toOwnedSlice();
    }

    fn parseDecl(p: *Parser, out: *std.ArrayList(ast.Decl)) ParseError!void {
        const t = p.peek();
        switch (t.tag) {
            .kw_type => {
                _ = p.advance();
                const name = (try p.expect(.ident)).text;
                _ = try p.expect(.eq);
                const ty = try p.parseType();
                try out.append(.{ .alias = .{ .name = name, .ty = ty, .line = t.line } });
            },
            .kw_import => {
                _ = p.advance();
                const s = try p.expect(.str_lit);
                try out.append(.{ .import = s.text });
            },
            .kw_fn, .kw_extern, .kw_export => try out.append(.{ .func = try p.parseFn(null, &.{}) }),
            .kw_struct, .kw_union => {
                const is_union = p.advance().tag == .kw_union;
                const name = (try p.expect(.ident)).text;
                const tps = try p.parseTypeParams();
                _ = try p.expect(.lbrace);
                var fields = std.ArrayList(ast.Field).init(p.alloc);
                p.skipSemis();
                while (!p.at(.rbrace)) {
                    const fname = (try p.expect(.ident)).text;
                    var fty: *ast.TypeExpr = undefined;
                    if (is_union and !p.at(.colon)) {
                        fty = try p.new(ast.TypeExpr, .{ .name = .{ .name = "void", .args = &.{} } });
                    } else {
                        _ = try p.expect(.colon);
                        fty = try p.parseType();
                    }
                    try fields.append(.{ .name = fname, .ty = fty });
                    _ = p.eat(.comma);
                    p.skipSemis();
                }
                _ = try p.expect(.rbrace);
                try out.append(.{ .strct = try p.new(ast.StructDecl, .{ .name = name, .type_params = tps, .fields = try fields.toOwnedSlice(), .line = t.line, .is_union = is_union }) });
            },
            .kw_enum => {
                _ = p.advance();
                const name = (try p.expect(.ident)).text;
                _ = try p.expect(.lbrace);
                var vs = std.ArrayList([]const u8).init(p.alloc);
                p.skipSemis();
                while (!p.at(.rbrace)) {
                    try vs.append((try p.expect(.ident)).text);
                    _ = p.eat(.comma);
                    p.skipSemis();
                }
                _ = try p.expect(.rbrace);
                try out.append(.{ .enm = try p.new(ast.EnumDecl, .{ .name = name, .variants = try vs.toOwnedSlice(), .line = t.line }) });
            },
            .kw_impl => {
                _ = p.advance();
                const name = (try p.expect(.ident)).text;
                const tps = try p.parseTypeParams();
                _ = try p.expect(.lbrace);
                p.skipSemis();
                while (!p.at(.rbrace)) {
                    try out.append(.{ .func = try p.parseFn(name, tps) });
                    p.skipSemis();
                }
                _ = try p.expect(.rbrace);
            },
            .kw_const, .kw_var => {
                _ = p.advance();
                const name = (try p.expect(.ident)).text;
                var ty: ?*ast.TypeExpr = null;
                if (p.eat(.colon)) ty = try p.parseType();
                _ = try p.expect(.eq);
                const v = try p.parseExpr();
                try out.append(.{ .constant = try p.new(ast.ConstDecl, .{ .name = name, .ty = ty, .value = v, .mutable = t.tag == .kw_var, .line = t.line }) });
            },
            else => return p.fail("expected declaration", .{}),
        }
    }

    fn parseFn(p: *Parser, receiver: ?[]const u8, recv_params: [][]const u8) ParseError!*ast.FnDecl {
        const is_extern = p.eat(.kw_extern);
        const is_export = p.eat(.kw_export);
        const line = (try p.expect(.kw_fn)).line;
        const name = (try p.expect(.ident)).text;
        const tps = try p.parseTypeParams();
        _ = try p.expect(.lparen);
        var params = std.ArrayList(ast.Param).init(p.alloc);
        var variadic = false;
        while (!p.at(.rparen)) {
            if (p.eat(.ellipsis)) {
                variadic = true;
                break;
            }
            const pname = (try p.expect(.ident)).text;
            var pty: *ast.TypeExpr = undefined;
            if (p.eat(.colon)) {
                pty = try p.parseType();
            } else if (std.mem.eql(u8, pname, "self")) {
                // `self` alone means `self: *Self`
                const inner = try p.new(ast.TypeExpr, .{ .name = .{ .name = "Self", .args = &.{} } });
                pty = try p.new(ast.TypeExpr, .{ .ptr = inner });
            } else return p.fail("parameter '{s}' needs a type", .{pname});
            try params.append(.{ .name = pname, .ty = pty });
            if (!p.eat(.comma)) break;
        }
        _ = try p.expect(.rparen);
        var ret: ?*ast.TypeExpr = null;
        if (!p.at(.lbrace) and !p.at(.semi) and !p.at(.eof)) ret = try p.parseType();
        var body: ?*ast.Stmt = null;
        if (!is_extern) body = try p.parseBlock();
        return p.new(ast.FnDecl, .{
            .name = name,
            .type_params = tps,
            .params = try params.toOwnedSlice(),
            .ret = ret,
            .body = body,
            .is_extern = is_extern,
            .is_export = is_export,
            .variadic = variadic,
            .line = line,
            .file = p.file,
            .receiver = receiver,
            .receiver_params = recv_params,
        });
    }

    fn startsType(t: Tag) bool {
        return switch (t) {
            .ident, .star, .bang, .lbracket, .kw_fn => true,
            else => false,
        };
    }

    pub fn parseType(p: *Parser) ParseError!*ast.TypeExpr {
        if (p.eat(.kw_fn)) {
            _ = try p.expect(.lparen);
            var params = std.ArrayList(*ast.TypeExpr).init(p.alloc);
            while (!p.at(.rparen)) {
                try params.append(try p.parseType());
                if (!p.eat(.comma)) break;
            }
            _ = try p.expect(.rparen);
            var ret: ?*ast.TypeExpr = null;
            if (startsType(p.peek().tag)) ret = try p.parseType();
            return p.new(ast.TypeExpr, .{ .func = .{ .params = try params.toOwnedSlice(), .ret = ret } });
        }
        if (p.eat(.star)) return p.new(ast.TypeExpr, .{ .ptr = try p.parseType() });
        if (p.eat(.bang)) return p.new(ast.TypeExpr, .{ .errun = try p.parseType() });
        if (p.eat(.lbracket)) {
            if (p.eat(.rbracket)) return p.new(ast.TypeExpr, .{ .slice = try p.parseType() });
            const len = try p.parseExpr();
            _ = try p.expect(.rbracket);
            return p.new(ast.TypeExpr, .{ .array = .{ .len = len, .elem = try p.parseType() } });
        }
        const name = (try p.expect(.ident)).text;
        var args = std.ArrayList(*ast.TypeExpr).init(p.alloc);
        if (p.at(.lbracket)) {
            _ = p.advance();
            while (!p.at(.rbracket)) {
                try args.append(try p.parseType());
                if (!p.eat(.comma)) break;
            }
            _ = try p.expect(.rbracket);
        }
        return p.new(ast.TypeExpr, .{ .name = .{ .name = name, .args = try args.toOwnedSlice() } });
    }

    // ---------------- statements ----------------

    fn parseBlock(p: *Parser) ParseError!*ast.Stmt {
        const line = (try p.expect(.lbrace)).line;
        var stmts = std.ArrayList(*ast.Stmt).init(p.alloc);
        const saved = p.no_struct;
        p.no_struct = false;
        p.skipSemis();
        while (!p.at(.rbrace)) {
            if (p.at(.eof)) return p.fail("unexpected end of file in block", .{});
            try stmts.append(try p.parseStmt());
            p.skipSemis();
        }
        _ = try p.expect(.rbrace);
        p.no_struct = saved;
        return p.mkStmt(line, .{ .block = try stmts.toOwnedSlice() });
    }

    fn parseCond(p: *Parser) ParseError!*ast.Expr {
        const saved = p.no_struct;
        p.no_struct = true;
        defer p.no_struct = saved;
        return p.parseExpr();
    }

    fn parseStmt(p: *Parser) ParseError!*ast.Stmt {
        const t = p.peek();
        switch (t.tag) {
            .lbrace => return p.parseBlock(),
            .kw_let, .kw_var => {
                _ = p.advance();
                const name = (try p.expect(.ident)).text;
                var ty: ?*ast.TypeExpr = null;
                if (p.eat(.colon)) ty = try p.parseType();
                var init_e: ?*ast.Expr = null;
                if (p.eat(.eq)) init_e = try p.parseExpr();
                if (ty == null and init_e == null) return p.fail("'{s}' needs a type or initializer", .{name});
                return p.mkStmt(t.line, .{ .let = .{ .name = name, .mutable = t.tag == .kw_var, .ty = ty, .init = init_e } });
            },
            .kw_if => return p.parseIf(),
            .kw_while => {
                _ = p.advance();
                const cond = try p.parseCond();
                const body = try p.parseBlock();
                return p.mkStmt(t.line, .{ .while_ = .{ .cond = cond, .body = body } });
            },
            .kw_for => {
                _ = p.advance();
                const n1 = (try p.expect(.ident)).text;
                var n2: ?[]const u8 = null;
                if (p.eat(.comma)) n2 = (try p.expect(.ident)).text;
                _ = try p.expect(.kw_in);
                const e = try p.parseCond();
                if (p.eat(.dotdot)) {
                    if (n2 != null) return p.fail("range loop takes a single variable", .{});
                    const hi = try p.parseCond();
                    const body = try p.parseBlock();
                    return p.mkStmt(t.line, .{ .for_range = .{ .name = n1, .lo = e, .hi = hi, .body = body } });
                }
                const body = try p.parseBlock();
                if (n2) |second| return p.mkStmt(t.line, .{ .for_each = .{ .idx = n1, .name = second, .seq = e, .body = body } });
                return p.mkStmt(t.line, .{ .for_each = .{ .idx = null, .name = n1, .seq = e, .body = body } });
            },
            .kw_return => {
                _ = p.advance();
                if (p.at(.semi) or p.at(.rbrace)) return p.mkStmt(t.line, .{ .ret = null });
                return p.mkStmt(t.line, .{ .ret = try p.parseExpr() });
            },
            .kw_break => {
                _ = p.advance();
                return p.mkStmt(t.line, .brk);
            },
            .kw_continue => {
                _ = p.advance();
                return p.mkStmt(t.line, .cont);
            },
            .kw_defer, .kw_errdefer => {
                _ = p.advance();
                const body = try p.parseStmt();
                return p.mkStmt(t.line, .{ .defer_ = .{ .body = body, .is_err = t.tag == .kw_errdefer } });
            },
            .kw_match => {
                _ = p.advance();
                const v = try p.parseCond();
                _ = try p.expect(.lbrace);
                var arms = std.ArrayList(ast.MatchArm).init(p.alloc);
                p.skipSemis();
                while (!p.at(.rbrace)) {
                    var pats = std.ArrayList(*ast.Expr).init(p.alloc);
                    if (p.at(.ident) and std.mem.eql(u8, p.peek().text, "_")) {
                        _ = p.advance();
                    } else {
                        while (true) {
                            try pats.append(try p.parseExpr());
                            if (!p.eat(.comma)) break;
                        }
                    }
                    _ = try p.expect(.fat_arrow);
                    const body = try p.parseStmt();
                    try arms.append(.{ .pats = try pats.toOwnedSlice(), .body = body });
                    _ = p.eat(.comma);
                    p.skipSemis();
                }
                _ = try p.expect(.rbrace);
                return p.mkStmt(t.line, .{ .match_ = .{ .value = v, .arms = try arms.toOwnedSlice() } });
            },
            else => {
                const e = try p.parseExpr();
                const op = p.peek().tag;
                switch (op) {
                    .eq, .plus_eq, .minus_eq, .star_eq, .slash_eq, .percent_eq => {
                        _ = p.advance();
                        const v = try p.parseExpr();
                        return p.mkStmt(t.line, .{ .assign = .{ .op = op, .target = e, .value = v } });
                    },
                    else => return p.mkStmt(t.line, .{ .expr = e }),
                }
            },
        }
    }

    fn parseIf(p: *Parser) ParseError!*ast.Stmt {
        const line = (try p.expect(.kw_if)).line;
        const cond = try p.parseCond();
        const then = try p.parseBlock();
        var els: ?*ast.Stmt = null;
        // allow `}\nelse`
        if (p.at(.semi) and p.peekAt(1).tag == .kw_else) _ = p.advance();
        if (p.eat(.kw_else)) {
            if (p.at(.kw_if)) els = try p.parseIf() else els = try p.parseBlock();
        }
        return p.mkStmt(line, .{ .if_ = .{ .cond = cond, .then = then, .els = els } });
    }

    // ---------------- expressions ----------------

    pub fn parseExpr(p: *Parser) ParseError!*ast.Expr {
        var l = try p.parseBin(0);
        while (p.at(.kw_catch)) {
            const line = p.advance().line;
            var name: ?[]const u8 = null;
            if (p.eat(.pipe)) {
                name = (try p.expect(.ident)).text;
                _ = try p.expect(.pipe);
            }
            var handler: *ast.Stmt = undefined;
            if (p.at(.lbrace)) {
                handler = try p.parseBlock();
            } else if (p.at(.kw_return)) {
                handler = try p.parseStmt();
            } else {
                const he = try p.parseBin(0);
                handler = try p.mkStmt(line, .{ .expr = he });
            }
            l = try p.mkExpr(line, .{ .catch_ = .{ .e = l, .err_name = name, .handler = handler } });
        }
        return l;
    }

    fn prec(t: Tag) i32 {
        return switch (t) {
            .oror => 1,
            .andand => 2,
            .eqeq, .neq, .lt, .le, .gt, .ge => 3,
            .pipe => 4,
            .caret => 5,
            .amp => 6,
            .shl, .shr => 7,
            .plus, .minus => 8,
            .star, .slash, .percent => 9,
            else => -1,
        };
    }

    fn parseBin(p: *Parser, min: i32) ParseError!*ast.Expr {
        var l = try p.parseUnary();
        while (true) {
            const op = p.peek();
            const pr = prec(op.tag);
            if (pr < 0 or pr < min) break;
            _ = p.advance();
            const r = try p.parseBin(pr + 1);
            l = try p.mkExpr(op.line, .{ .binary = .{ .op = op.tag, .l = l, .r = r } });
        }
        return l;
    }

    fn parsePrefix(p: *Parser) ParseError!*ast.Expr {
        const t = p.peek();
        switch (t.tag) {
            .minus, .bang, .tilde, .amp, .star => {
                _ = p.advance();
                const e = try p.parsePrefix();
                return p.mkExpr(t.line, .{ .unary = .{ .op = t.tag, .e = e } });
            },
            else => return p.parsePostfix(),
        }
    }

    /// `as` binds looser than prefix operators: `&x as *T` == `(&x) as *T`, `-a as i64` == `(-a) as i64`
    fn parseUnary(p: *Parser) ParseError!*ast.Expr {
        var e = try p.parsePrefix();
        while (p.at(.kw_as)) {
            const line = p.advance().line;
            const ty = try p.parseType();
            e = try p.mkExpr(line, .{ .cast = .{ .e = e, .ty = ty } });
        }
        return e;
    }

    fn isTypeLike(e: *ast.Expr) bool {
        return switch (e.kind) {
            .ident => |n| n.len > 0 and std.ascii.isUpper(n[0]),
            .index => |ix| isTypeLike(ix.e),
            else => false,
        };
    }

    pub fn exprToType(p: *Parser, e: *ast.Expr) ParseError!*ast.TypeExpr {
        switch (e.kind) {
            .ident => |n| return p.new(ast.TypeExpr, .{ .name = .{ .name = n, .args = &.{} } }),
            .index => |ix| {
                const base = try p.exprToType(ix.e);
                var args = std.ArrayList(*ast.TypeExpr).init(p.alloc);
                for (ix.args) |a| try args.append(try p.exprToType(a));
                base.name.args = try args.toOwnedSlice();
                return base;
            },
            .unary => |u| {
                if (u.op == .star) return p.new(ast.TypeExpr, .{ .ptr = try p.exprToType(u.e) });
                if (u.op == .bang) return p.new(ast.TypeExpr, .{ .errun = try p.exprToType(u.e) });
            },
            else => {},
        }
        std.debug.print("{s}:{d}: error: expected a type\n", .{ p.file, e.line });
        return error.ParseFailed;
    }

    fn parsePostfix(p: *Parser) ParseError!*ast.Expr {
        var e = try p.parsePrimary();
        while (true) {
            const t = p.peek();
            switch (t.tag) {
                .lparen => {
                    _ = p.advance();
                    var args = std.ArrayList(*ast.Expr).init(p.alloc);
                    const saved = p.no_struct;
                    p.no_struct = false;
                    while (!p.at(.rparen)) {
                        try args.append(try p.parseExpr());
                        if (!p.eat(.comma)) break;
                    }
                    p.no_struct = saved;
                    _ = try p.expect(.rparen);
                    e = try p.mkExpr(t.line, .{ .call = .{ .callee = e, .args = try args.toOwnedSlice() } });
                },
                .lbracket => {
                    _ = p.advance();
                    const saved = p.no_struct;
                    p.no_struct = false;
                    defer p.no_struct = saved;
                    if (p.eat(.dotdot)) {
                        var hi: ?*ast.Expr = null;
                        if (!p.at(.rbracket)) hi = try p.parseExpr();
                        _ = try p.expect(.rbracket);
                        e = try p.mkExpr(t.line, .{ .slice = .{ .e = e, .lo = null, .hi = hi } });
                        continue;
                    }
                    const first = try p.parseExpr();
                    if (p.eat(.dotdot)) {
                        var hi: ?*ast.Expr = null;
                        if (!p.at(.rbracket)) hi = try p.parseExpr();
                        _ = try p.expect(.rbracket);
                        e = try p.mkExpr(t.line, .{ .slice = .{ .e = e, .lo = first, .hi = hi } });
                        continue;
                    }
                    var args = std.ArrayList(*ast.Expr).init(p.alloc);
                    try args.append(first);
                    while (p.eat(.comma)) {
                        // type args like Map[K, V] may contain types such as *T
                        try args.append(try p.parseExpr());
                    }
                    _ = try p.expect(.rbracket);
                    e = try p.mkExpr(t.line, .{ .index = .{ .e = e, .args = try args.toOwnedSlice() } });
                },
                .dot => {
                    _ = p.advance();
                    const name = (try p.expect(.ident)).text;
                    e = try p.mkExpr(t.line, .{ .field = .{ .e = e, .name = name } });
                },
                .question => {
                    _ = p.advance();
                    e = try p.mkExpr(t.line, .{ .try_ = e });
                },
                .kw_is => {
                    // x is .Variant   |   x is Type.Variant
                    _ = p.advance();
                    if (!p.eat(.dot)) {
                        _ = try p.expect(.ident);
                        _ = try p.expect(.dot);
                    }
                    const vname = (try p.expect(.ident)).text;
                    e = try p.mkExpr(t.line, .{ .is_ = .{ .e = e, .variant = vname } });
                },
                .lbrace => {
                    if (p.no_struct or !isTypeLike(e)) break;
                    _ = p.advance();
                    const ty = try p.exprToType(e);
                    var fields = std.ArrayList(ast.FieldInit).init(p.alloc);
                    var zero_rest = false;
                    p.skipSemis();
                    while (!p.at(.rbrace)) {
                        if (p.eat(.dotdot)) {
                            zero_rest = true;
                            p.skipSemis();
                            break;
                        }
                        const fname = (try p.expect(.ident)).text;
                        _ = try p.expect(.colon);
                        const v = try p.parseExpr();
                        try fields.append(.{ .name = fname, .value = v });
                        _ = p.eat(.comma);
                        p.skipSemis();
                    }
                    _ = try p.expect(.rbrace);
                    e = try p.mkExpr(t.line, .{ .struct_lit = .{ .ty = ty, .fields = try fields.toOwnedSlice(), .zero_rest = zero_rest } });
                },
                else => break,
            }
        }
        return e;
    }

    fn parsePrimary(p: *Parser) ParseError!*ast.Expr {
        const t = p.advance();
        switch (t.tag) {
            .int_lit => {
                var buf = std.ArrayList(u8).init(p.alloc);
                for (t.text) |ch| if (ch != '_') try buf.append(ch);
                const v = std.fmt.parseInt(u64, buf.items, 0) catch return p.fail("bad integer literal", .{});
                return p.mkExpr(t.line, .{ .int_lit = v });
            },
            .float_lit => {
                var buf = std.ArrayList(u8).init(p.alloc);
                for (t.text) |ch| if (ch != '_') try buf.append(ch);
                const v = std.fmt.parseFloat(f64, buf.items) catch return p.fail("bad float literal", .{});
                return p.mkExpr(t.line, .{ .float_lit = v });
            },
            .char_lit => {
                const s = try p.unescape(t.text);
                if (s.len != 1) return p.fail("char literal must be one byte", .{});
                return p.mkExpr(t.line, .{ .int_lit = s[0] });
            },
            .str_lit => return p.parseString(t),
            .kw_true => return p.mkExpr(t.line, .{ .bool_lit = true }),
            .kw_false => return p.mkExpr(t.line, .{ .bool_lit = false }),
            .kw_null => return p.mkExpr(t.line, .null_lit),
            .ident => return p.mkExpr(t.line, .{ .ident = t.text }),
            .dot => {
                const name = (try p.expect(.ident)).text;
                return p.mkExpr(t.line, .{ .enum_lit = name });
            },
            .kw_error => {
                _ = try p.expect(.dot);
                const name = (try p.expect(.ident)).text;
                return p.mkExpr(t.line, .{ .error_val = name });
            },
            .kw_sizeof, .kw_alignof => {
                _ = try p.expect(.lparen);
                const ty = try p.parseType();
                _ = try p.expect(.rparen);
                if (t.tag == .kw_alignof) return p.mkExpr(t.line, .{ .alignof = ty });
                return p.mkExpr(t.line, .{ .sizeof = ty });
            },
            .lparen => {
                const saved = p.no_struct;
                p.no_struct = false;
                const e = try p.parseExpr();
                p.no_struct = saved;
                _ = try p.expect(.rparen);
                return e;
            },
            .lbracket => {
                var elems = std.ArrayList(*ast.Expr).init(p.alloc);
                while (!p.at(.rbracket)) {
                    try elems.append(try p.parseExpr());
                    if (!p.eat(.comma)) break;
                }
                _ = try p.expect(.rbracket);
                return p.mkExpr(t.line, .{ .array_lit = try elems.toOwnedSlice() });
            },
            else => {
                p.pos -= 1;
                return p.fail("expected expression", .{});
            },
        }
    }

    fn unescape(p: *Parser, raw: []const u8) ParseError![]const u8 {
        var out = std.ArrayList(u8).init(p.alloc);
        var i: usize = 0;
        while (i < raw.len) : (i += 1) {
            if (raw[i] == '\\' and i + 1 < raw.len) {
                i += 1;
                switch (raw[i]) {
                    'n' => try out.append('\n'),
                    't' => try out.append('\t'),
                    'r' => try out.append('\r'),
                    '0' => try out.append(0),
                    'e' => try out.append(27),
                    '\\' => try out.append('\\'),
                    '"' => try out.append('"'),
                    '\'' => try out.append('\''),
                    '{' => try out.append('{'),
                    '}' => try out.append('}'),
                    'x' => {
                        if (i + 2 >= raw.len) return p.fail("bad \\x escape", .{});
                        const v = std.fmt.parseInt(u8, raw[i + 1 .. i + 3], 16) catch return p.fail("bad \\x escape", .{});
                        try out.append(v);
                        i += 2;
                    },
                    else => try out.append(raw[i]),
                }
            } else try out.append(raw[i]);
        }
        return out.toOwnedSlice();
    }

    /// position of a format-spec colon at nesting depth 0: "{x:08x}"
    fn specColon(inner: []const u8) ?usize {
        var d: i32 = 0;
        var i: usize = 0;
        while (i < inner.len) : (i += 1) {
            switch (inner[i]) {
                '(', '[', '{' => d += 1,
                ')', ']', '}' => d -= 1,
                '"' => {
                    i += 1;
                    while (i < inner.len and inner[i] != '"') : (i += 1) {
                        if (inner[i] == '\\') i += 1;
                    }
                },
                '\'' => i += 2,
                ':' => if (d == 0) return i,
                else => {},
            }
        }
        return null;
    }

    fn matchBrace(raw: []const u8, open: usize) ?usize {
        var d: u32 = 0;
        var i = open;
        while (i < raw.len) : (i += 1) {
            switch (raw[i]) {
                '{' => d += 1,
                '}' => {
                    d -= 1;
                    if (d == 0) return i;
                },
                '"' => {
                    i += 1;
                    while (i < raw.len and raw[i] != '"') : (i += 1) {
                        if (raw[i] == '\\') i += 1;
                    }
                },
                else => {},
            }
        }
        return null;
    }

    /// "x = {x}, sum = {a + b}" => interpolated string
    fn parseString(p: *Parser, t: Token) ParseError!*ast.Expr {
        const raw = t.text;
        if (std.mem.indexOfScalar(u8, raw, '{') == null) {
            return p.mkExpr(t.line, .{ .str_lit = try p.unescape(raw) });
        }
        var parts = std.ArrayList(ast.InterpPart).init(p.alloc);
        var lit = std.ArrayList(u8).init(p.alloc);
        var i: usize = 0;
        var has_expr = false;
        while (i < raw.len) {
            const ch = raw[i];
            if (ch == '\\' and i + 1 < raw.len) {
                try lit.appendSlice(raw[i .. i + 2]);
                i += 2;
                continue;
            }
            if (ch == '{' and i + 1 < raw.len and raw[i + 1] == '{') {
                try lit.append('{');
                i += 2;
                continue;
            }
            if (ch == '}' and i + 1 < raw.len and raw[i + 1] == '}') {
                try lit.append('}');
                i += 2;
                continue;
            }
            if (ch == '{') {
                const close = matchBrace(raw, i) orelse return p.fail("unclosed '{{' in string", .{});
                if (lit.items.len > 0) {
                    try parts.append(.{ .lit = try p.unescape(lit.items) });
                    lit = std.ArrayList(u8).init(p.alloc);
                }
                var inner = raw[i + 1 .. close];
                var spec: ?[]const u8 = null;
                if (specColon(inner)) |ci| {
                    spec = inner[ci + 1 ..];
                    inner = inner[0..ci];
                }
                const toks = try lex.tokenize(p.alloc, inner, p.file);
                for (toks) |*tk| tk.line = t.line;
                var sub = Parser.init(p.alloc, toks, p.file);
                const e = try sub.parseExpr();
                if (!sub.at(.semi) and !sub.at(.eof)) return p.fail("unexpected tokens in interpolation '{s}'", .{inner});
                if (spec) |sp| try parts.append(.{ .spec = .{ .e = e, .spec = sp } }) else try parts.append(.{ .expr = e });
                has_expr = true;
                i = close + 1;
                continue;
            }
            try lit.append(ch);
            i += 1;
        }
        if (lit.items.len > 0) try parts.append(.{ .lit = try p.unescape(lit.items) });
        if (!has_expr) {
            var all = std.ArrayList(u8).init(p.alloc);
            for (parts.items) |pt| try all.appendSlice(pt.lit);
            return p.mkExpr(t.line, .{ .str_lit = try all.toOwnedSlice() });
        }
        return p.mkExpr(t.line, .{ .interp = try parts.toOwnedSlice() });
    }
};
