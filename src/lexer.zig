const std = @import("std");

pub const Tag = enum {
    eof,
    ident,
    int_lit,
    float_lit,
    str_lit,
    char_lit,
    semi,
    lparen,
    rparen,
    lbrace,
    rbrace,
    lbracket,
    rbracket,
    comma,
    dot,
    dotdot,
    ellipsis,
    colon,
    fat_arrow,
    plus,
    minus,
    star,
    slash,
    percent,
    amp,
    pipe,
    caret,
    tilde,
    bang,
    question,
    eq,
    eqeq,
    neq,
    lt,
    le,
    gt,
    ge,
    shl,
    shr,
    andand,
    oror,
    plus_eq,
    minus_eq,
    star_eq,
    slash_eq,
    percent_eq,
    kw_fn,
    kw_let,
    kw_var,
    kw_const,
    kw_if,
    kw_else,
    kw_while,
    kw_for,
    kw_in,
    kw_return,
    kw_break,
    kw_continue,
    kw_struct,
    kw_enum,
    kw_impl,
    kw_extern,
    kw_export,
    kw_defer,
    kw_errdefer,
    kw_error,
    kw_catch,
    kw_true,
    kw_false,
    kw_null,
    kw_as,
    kw_import,
    kw_match,
    kw_sizeof,
    kw_alignof,
    kw_union,
    kw_type,
    kw_is,
};

pub const Token = struct {
    tag: Tag,
    text: []const u8,
    line: u32,
};

const keywords = std.StaticStringMap(Tag).initComptime(.{
    .{ "fn", .kw_fn },             .{ "let", .kw_let },           .{ "var", .kw_var },
    .{ "const", .kw_const },       .{ "if", .kw_if },             .{ "else", .kw_else },
    .{ "while", .kw_while },       .{ "for", .kw_for },           .{ "in", .kw_in },
    .{ "return", .kw_return },     .{ "break", .kw_break },       .{ "continue", .kw_continue },
    .{ "struct", .kw_struct },     .{ "enum", .kw_enum },         .{ "impl", .kw_impl },
    .{ "extern", .kw_extern },     .{ "export", .kw_export },     .{ "defer", .kw_defer },
    .{ "errdefer", .kw_errdefer }, .{ "error", .kw_error },       .{ "catch", .kw_catch },
    .{ "true", .kw_true },         .{ "false", .kw_false },       .{ "null", .kw_null },
    .{ "as", .kw_as },             .{ "import", .kw_import },     .{ "match", .kw_match },
    .{ "sizeof", .kw_sizeof },     .{ "alignof", .kw_alignof },   .{ "union", .kw_union },       .{ "type", .kw_type },         .{ "is", .kw_is },
});

fn endsStatement(t: Tag) bool {
    return switch (t) {
        .ident, .int_lit, .float_lit, .str_lit, .char_lit, .rparen, .rbracket, .rbrace, .kw_return, .kw_break, .kw_continue, .question, .kw_true, .kw_false, .kw_null => true,
        else => false,
    };
}

pub const LexError = error{ LexFailed, OutOfMemory };

pub fn tokenize(alloc: std.mem.Allocator, src: []const u8, file: []const u8) LexError![]Token {
    var toks = std.ArrayList(Token).init(alloc);
    var i: usize = 0;
    var line: u32 = 1;
    var depth: i32 = 0; // ( and [ nesting: no auto-semicolons inside

    while (i < src.len) {
        const c = src[i];
        if (c == '\n') {
            if (depth == 0 and toks.items.len > 0 and endsStatement(toks.items[toks.items.len - 1].tag)) {
                try toks.append(.{ .tag = .semi, .text = "\\n", .line = line });
            }
            line += 1;
            i += 1;
            continue;
        }
        if (c == ' ' or c == '\t' or c == '\r') {
            i += 1;
            continue;
        }
        if (c == '/' and i + 1 < src.len and src[i + 1] == '/') {
            while (i < src.len and src[i] != '\n') i += 1;
            continue;
        }
        if (c == '/' and i + 1 < src.len and src[i + 1] == '*') {
            i += 2;
            while (i + 1 < src.len and !(src[i] == '*' and src[i + 1] == '/')) {
                if (src[i] == '\n') line += 1;
                i += 1;
            }
            i += 2;
            continue;
        }
        const start = i;
        if (std.ascii.isAlphabetic(c) or c == '_') {
            while (i < src.len and (std.ascii.isAlphanumeric(src[i]) or src[i] == '_')) i += 1;
            const text = src[start..i];
            const tag = keywords.get(text) orelse .ident;
            try toks.append(.{ .tag = tag, .text = text, .line = line });
            continue;
        }
        if (std.ascii.isDigit(c)) {
            var is_float = false;
            if (c == '0' and i + 1 < src.len and (src[i + 1] == 'x' or src[i + 1] == 'b' or src[i + 1] == 'o')) {
                i += 2;
                while (i < src.len and (std.ascii.isAlphanumeric(src[i]) or src[i] == '_')) i += 1;
            } else {
                while (i < src.len and (std.ascii.isDigit(src[i]) or src[i] == '_')) i += 1;
                if (i + 1 < src.len and src[i] == '.' and std.ascii.isDigit(src[i + 1])) {
                    is_float = true;
                    i += 1;
                    while (i < src.len and (std.ascii.isDigit(src[i]) or src[i] == '_')) i += 1;
                }
                if (i < src.len and (src[i] == 'e' or src[i] == 'E')) {
                    is_float = true;
                    i += 1;
                    if (i < src.len and (src[i] == '+' or src[i] == '-')) i += 1;
                    while (i < src.len and std.ascii.isDigit(src[i])) i += 1;
                }
            }
            try toks.append(.{ .tag = if (is_float) .float_lit else .int_lit, .text = src[start..i], .line = line });
            continue;
        }
        if (c == '"') {
            i += 1;
            var bdepth: u32 = 0; // inside {interpolation}
            while (i < src.len and !(src[i] == '"' and bdepth == 0)) {
                if (src[i] == '\\') {
                    i += 2;
                    continue;
                }
                if (src[i] == '{' and i + 1 < src.len and src[i + 1] == '{' and bdepth == 0) {
                    i += 2;
                    continue;
                }
                if (src[i] == '{') bdepth += 1;
                if (src[i] == '}' and bdepth > 0) bdepth -= 1;
                if (src[i] == '"' and bdepth > 0) {
                    // nested string literal inside an interpolation
                    i += 1;
                    while (i < src.len and src[i] != '"') {
                        if (src[i] == '\\') i += 1;
                        i += 1;
                    }
                }
                if (i < src.len and src[i] == '\n') line += 1;
                i += 1;
            }
            if (i >= src.len) {
                std.debug.print("{s}:{d}: error: unterminated string\n", .{ file, line });
                return error.LexFailed;
            }
            i += 1;
            try toks.append(.{ .tag = .str_lit, .text = src[start + 1 .. i - 1], .line = line });
            continue;
        }
        if (c == '\'') {
            i += 1;
            if (i < src.len and src[i] == '\\') i += 1;
            i += 1;
            if (i >= src.len or src[i] != '\'') {
                std.debug.print("{s}:{d}: error: bad char literal\n", .{ file, line });
                return error.LexFailed;
            }
            i += 1;
            try toks.append(.{ .tag = .char_lit, .text = src[start + 1 .. i - 1], .line = line });
            continue;
        }

        const Op = struct { s: []const u8, t: Tag };
        const ops = [_]Op{
            .{ .s = "...", .t = .ellipsis }, .{ .s = "..", .t = .dotdot },     .{ .s = "=>", .t = .fat_arrow },
            .{ .s = "==", .t = .eqeq },      .{ .s = "!=", .t = .neq },        .{ .s = "<=", .t = .le },
            .{ .s = ">=", .t = .ge },        .{ .s = "<<", .t = .shl },        .{ .s = ">>", .t = .shr },
            .{ .s = "&&", .t = .andand },    .{ .s = "||", .t = .oror },       .{ .s = "+=", .t = .plus_eq },
            .{ .s = "-=", .t = .minus_eq },  .{ .s = "*=", .t = .star_eq },    .{ .s = "/=", .t = .slash_eq },
            .{ .s = "%=", .t = .percent_eq }, .{ .s = "(", .t = .lparen },     .{ .s = ")", .t = .rparen },
            .{ .s = "{", .t = .lbrace },     .{ .s = "}", .t = .rbrace },      .{ .s = "[", .t = .lbracket },
            .{ .s = "]", .t = .rbracket },   .{ .s = ",", .t = .comma },       .{ .s = ".", .t = .dot },
            .{ .s = ":", .t = .colon },      .{ .s = ";", .t = .semi },        .{ .s = "+", .t = .plus },
            .{ .s = "-", .t = .minus },      .{ .s = "*", .t = .star },        .{ .s = "/", .t = .slash },
            .{ .s = "%", .t = .percent },    .{ .s = "&", .t = .amp },         .{ .s = "|", .t = .pipe },
            .{ .s = "^", .t = .caret },      .{ .s = "~", .t = .tilde },       .{ .s = "!", .t = .bang },
            .{ .s = "?", .t = .question },   .{ .s = "=", .t = .eq },          .{ .s = "<", .t = .lt },
            .{ .s = ">", .t = .gt },
        };
        var matched = false;
        for (ops) |op| {
            if (std.mem.startsWith(u8, src[i..], op.s)) {
                try toks.append(.{ .tag = op.t, .text = op.s, .line = line });
                i += op.s.len;
                matched = true;
                switch (op.t) {
                    .lparen, .lbracket => depth += 1,
                    .rparen, .rbracket => depth -= 1,
                    else => {},
                }
                break;
            }
        }
        if (!matched) {
            std.debug.print("{s}:{d}: error: unexpected character '{c}'\n", .{ file, line, c });
            return error.LexFailed;
        }
    }
    try toks.append(.{ .tag = .semi, .text = "", .line = line });
    try toks.append(.{ .tag = .eof, .text = "", .line = line });
    return toks.toOwnedSlice();
}
