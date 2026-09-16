const std = @import("std");
const c = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cDefine("PCRE2_STATIC", "");
    @cInclude("pcre2.h");
});

pub const Kind = enum { glob, regex };
/// Half-open byte offsets into the caller's source; regex markers are excluded.
pub const Segment = struct { kind: Kind, start: usize, end: usize };
pub const Diagnostic = struct {
    kind: enum(u32) { unexpected_close = 1, unclosed_excerpt, dangling_escape, regex_syntax, dfa_unsupported, match_failed, out_of_memory, workspace_limit, invalid_subject, unclosed_regex_delimiter, invalid_regex_flag },
    offset: ?usize = null,
    engine_code: i32 = 0,

    pub fn message(self: Diagnostic, buffer: []u8) []const u8 {
        if (self.engine_code != 0) {
            const len = c.pcre2_get_error_message_8(self.engine_code, buffer.ptr, buffer.len);
            if (len >= 0) return buffer[0..@intCast(len)];
        }
        return switch (self.kind) {
            .unexpected_close => "unexpected closing bracket; escape a literal bracket with a backslash",
            .unclosed_excerpt => "unclosed regex excerpt",
            .dangling_escape => "backslash at end of pattern",
            .regex_syntax => "invalid regular expression",
            .dfa_unsupported => "regular expression is outside the supported DFA subset",
            .match_failed => "regular expression matching failed",
            .out_of_memory => "out of memory during pattern matching",
            .workspace_limit => "DFA workspace limit exceeded",
            .invalid_subject => "subject is not valid UTF-8",
            .unclosed_regex_delimiter => "slash-delimited regex has no closing slash",
            .invalid_regex_flag => "unknown regex flag; supported flags are i, m, s, x, U, u",
        };
    }
};
pub const Options = struct { case_insensitive: bool = false, workspace_limit: usize = 262144 };
pub const MatchResult = union(enum) { matched: bool, diagnostic: Diagnostic };
pub const Pattern = struct {
    code: *c.pcre2_code_8,
    data: *c.pcre2_match_data_8,
    workspace: []c_int,
    workspace_limit: usize,
    source: []const u8,
    expression: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Pattern) void {
        c.pcre2_code_free_8(self.code);
        c.pcre2_match_data_free_8(self.data);
        self.allocator.free(self.workspace);
        self.allocator.free(self.source);
        self.allocator.free(self.expression);
    }

    /// Each Pattern owns mutable scratch storage; use separate instances concurrently.
    pub fn matches(self: *Pattern, subject: []const u8) MatchResult {
        while (true) {
            const rc = c.pcre2_dfa_match_8(self.code, subject.ptr, subject.len, 0, 0, self.data, null, self.workspace.ptr, self.workspace.len);
            if (rc >= 0) return .{ .matched = true };
            if (rc == c.PCRE2_ERROR_NOMATCH) return .{ .matched = false };
            if (rc == c.PCRE2_ERROR_DFA_WSSIZE) {
                if (self.workspace.len >= self.workspace_limit)
                    return .{ .diagnostic = .{ .kind = .workspace_limit, .engine_code = rc } };
                const length = @min(self.workspace_limit, self.workspace.len +| self.workspace.len);
                self.workspace = self.allocator.realloc(self.workspace, length) catch
                    return .{ .diagnostic = .{ .kind = .out_of_memory } };
                continue;
            }
            return .{ .diagnostic = .{
                .kind = if (rc <= c.PCRE2_ERROR_UTF8_ERR1 and rc >= c.PCRE2_ERROR_UTF8_ERR21) .invalid_subject else if (rc == c.PCRE2_ERROR_NOMEMORY) .out_of_memory else .match_failed,
                .engine_code = rc,
            } };
        }
    }
};
pub const CompileResult = union(enum) { pattern: Pattern, diagnostic: Diagnostic };
pub const SetResult = union(enum) { matched: bool, diagnostic: struct { index: usize, detail: Diagnostic } };
pub const PatternSet = struct {
    allocator: std.mem.Allocator,
    patterns: std.ArrayList(Pattern) = .empty,
    combined: ?Pattern = null,
    finalized: bool = false,
    pub fn init(allocator: std.mem.Allocator) PatternSet {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *PatternSet) void {
        if (self.combined) |*combined| combined.deinit();
        for (self.patterns.items) |*pattern| pattern.deinit();
        self.patterns.deinit(self.allocator);
    }
    pub fn add(self: *PatternSet, source: []const u8, options: Options) std.mem.Allocator.Error!?Diagnostic {
        var result = try compile(self.allocator, source, options);
        if (result == .diagnostic) return result.diagnostic;
        errdefer result.pattern.deinit();
        try self.patterns.append(self.allocator, result.pattern);
        if (self.combined) |*combined| combined.deinit();
        self.combined = null;
        self.finalized = false;
        return null;
    }
    pub fn count(self: *const PatternSet) usize {
        return self.patterns.items.len;
    }

    fn finalize(self: *PatternSet) std.mem.Allocator.Error!void {
        if (self.patterns.items.len > 1) {
            var text: std.ArrayList(u8) = .empty;
            defer text.deinit(self.allocator);
            var workspace_limit: usize = 262144;
            try text.appendSlice(self.allocator, "regex:(?:");
            for (self.patterns.items, 0..) |pattern, i| {
                workspace_limit = @min(workspace_limit, pattern.workspace_limit);
                if (i != 0) try text.append(self.allocator, '|');
                try text.appendSlice(self.allocator, pattern.expression);
            }
            try text.append(self.allocator, ')');
            const compiled = try compile(self.allocator, text.items, .{ .workspace_limit = workspace_limit });
            // Standalone directives may prevent composition. Each member was
            // already validated; matching them separately preserves semantics.
            if (compiled == .pattern) self.combined = compiled.pattern;
        }
        self.finalized = true;
    }

    pub fn matchesAny(self: *PatternSet, path: []const u8, alt: ?[]const u8) SetResult {
        if (!self.finalized) self.finalize() catch
            return .{ .diagnostic = .{ .index = 0, .detail = .{ .kind = .out_of_memory } } };
        if (self.combined) |*combined| {
            const first = combined.matches(path);
            if (first == .matched) {
                if (first.matched) return .{ .matched = true };
                if (alt) |other| {
                    const second = combined.matches(other);
                    if (second == .matched) return .{ .matched = second.matched };
                } else return .{ .matched = false };
            }
            // Retry members after a combined resource error to identify the
            // responsible rule, or establish a result with smaller workspaces.
        }
        for (self.patterns.items, 0..) |*pattern, index| {
            const first = pattern.matches(path);
            if (first == .diagnostic) return .{ .diagnostic = .{ .index = index, .detail = first.diagnostic } };
            if (first.matched) return .{ .matched = true };
            if (alt) |other| {
                const second = pattern.matches(other);
                if (second == .diagnostic) return .{ .diagnostic = .{ .index = index, .detail = second.diagnostic } };
                if (second.matched) return .{ .matched = true };
            }
        }
        return .{ .matched = false };
    }
};
pub fn compile(allocator: std.mem.Allocator, source: []const u8, options: Options) std.mem.Allocator.Error!CompileResult {
    const raw_regex = std.mem.startsWith(u8, source, "regex:");
    var prefix: usize = if (raw_regex) 6 else if (std.mem.startsWith(u8, source, "glob:")) 5 else 0;
    var end = source.len;
    var flags: u32 = c.PCRE2_UTF | c.PCRE2_UCP | (if (options.case_insensitive) @as(u32, c.PCRE2_CASELESS) else 0);
    if (raw_regex and prefix < source.len and source[prefix] == '/') {
        var last_slash: ?usize = null;
        var at = prefix + 1;
        while (at < source.len) : (at += 1) {
            if (source[at] == '\\') {
                at += 1;
            } else if (source[at] == '/') last_slash = at;
        }
        end = last_slash orelse return .{ .diagnostic = .{ .kind = .unclosed_regex_delimiter, .offset = prefix } };
        for (source[end + 1 ..], end + 1..) |flag, offset| flags |= switch (flag) {
            'i' => c.PCRE2_CASELESS,
            'm' => c.PCRE2_MULTILINE,
            's' => c.PCRE2_DOTALL,
            'x' => c.PCRE2_EXTENDED,
            'U' => c.PCRE2_UNGREEDY,
            'u' => c.PCRE2_UTF,
            else => return .{ .diagnostic = .{ .kind = .invalid_regex_flag, .offset = offset } },
        };
        prefix += 1;
    }
    var translated = try @import("translate.zig").translate(allocator, source[prefix..end], raw_regex);
    defer translated.deinit(allocator);
    if (translated.diagnostic) |diag| {
        var adjusted = diag;
        if (adjusted.offset) |offset| adjusted.offset = offset + prefix;
        return .{ .diagnostic = adjusted };
    }
    if (!raw_regex) {
        const parsed = try parse(allocator, source[prefix..]);
        defer parsed.deinit(allocator);
        for (parsed.segments) |segment| {
            if (segment.kind != .regex) continue;
            var fragment_code: c_int = 0;
            var fragment_offset: usize = 0;
            const body = source[prefix + segment.start .. prefix + segment.end];
            const fragment = c.pcre2_compile_8(body.ptr, body.len, c.PCRE2_UTF | c.PCRE2_UCP, &fragment_code, &fragment_offset, null) orelse
                return .{ .diagnostic = .{ .kind = .regex_syntax, .engine_code = fragment_code, .offset = prefix + segment.start + fragment_offset } };
            c.pcre2_code_free_8(fragment);
        }
    }
    var engine_code: c_int = 0;
    var offset: usize = 0;
    const code = c.pcre2_compile_8(translated.text.items.ptr, translated.text.items.len, flags, &engine_code, &offset, null) orelse {
        const original_offset = if (offset < translated.positions.items.len) translated.positions.items[offset] else end - prefix;
        return .{ .diagnostic = .{ .kind = .regex_syntax, .engine_code = engine_code, .offset = original_offset + prefix } };
    };
    errdefer c.pcre2_code_free_8(code);
    var compatibility: c_int = 0;
    const query = c.pcre2_pattern_info_8(code, c.PCRE2_INFO_DFA_COMPATIBILITY, &compatibility);
    if (query != 0 or compatibility != 0) {
        c.pcre2_code_free_8(code);
        return .{ .diagnostic = .{ .kind = .dfa_unsupported, .engine_code = if (query != 0) query else compatibility } };
    }
    const data = c.pcre2_match_data_create_8(1, null) orelse return error.OutOfMemory;
    errdefer c.pcre2_match_data_free_8(data);
    const owned_source = try allocator.dupe(u8, source);
    errdefer allocator.free(owned_source);
    const workspace_limit = @max(20, options.workspace_limit);
    const workspace = try allocator.alloc(c_int, @min(256, workspace_limit));
    errdefer allocator.free(workspace);
    var modifiers: std.ArrayList(u8) = .empty;
    defer modifiers.deinit(allocator);
    const flag_bits = [_]u32{ c.PCRE2_CASELESS, c.PCRE2_MULTILINE, c.PCRE2_DOTALL, c.PCRE2_EXTENDED, c.PCRE2_UNGREEDY };
    for ("imsxU", flag_bits) |letter, bit| if ((flags & bit) != 0) {
        try modifiers.append(allocator, letter);
    };
    const expression = try std.fmt.allocPrint(allocator, "(?{s}:{s})", .{ modifiers.items, translated.text.items });
    return .{ .pattern = .{ .code = code, .data = data, .workspace = workspace, .workspace_limit = workspace_limit, .source = owned_source, .expression = expression, .allocator = allocator } };
}
pub const Result = union(enum) {
    segments: []Segment,
    diagnostic: Diagnostic,

    pub fn deinit(self: Result, allocator: std.mem.Allocator) void {
        switch (self) {
            .segments => |segments| allocator.free(segments),
            .diagnostic => {},
        }
    }
};

/// Frame excerpts by balancing unescaped brackets. This does not validate regex.
/// Escape sequences stay byte-for-byte intact in both kinds of source span.
pub fn parse(allocator: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error!Result {
    var output: std.ArrayList(Segment) = .empty;
    defer output.deinit(allocator);
    var openings: std.ArrayList(usize) = .empty;
    defer openings.deinit(allocator);
    var glob_start: usize = 0;
    var i: usize = 0;
    while (i < source.len) {
        switch (source[i]) {
            '\\' => {
                if (i + 1 == source.len) return .{ .diagnostic = .{ .kind = .dangling_escape, .offset = i } };
                i += 2;
                continue;
            },
            '[' => {
                if (openings.items.len == 0 and glob_start < i)
                    try output.append(allocator, .{ .kind = .glob, .start = glob_start, .end = i });
                try openings.append(allocator, i);
            },
            ']' => {
                const start = openings.pop() orelse return .{ .diagnostic = .{ .kind = .unexpected_close, .offset = i } };
                if (openings.items.len == 0) {
                    try output.append(allocator, .{ .kind = .regex, .start = start + 1, .end = i });
                    glob_start = i + 1;
                }
            },
            else => {},
        }
        i += 1;
    }
    if (openings.items.len != 0)
        return .{ .diagnostic = .{ .kind = .unclosed_excerpt, .offset = openings.items[0] } };
    if (glob_start < source.len)
        try output.append(allocator, .{ .kind = .glob, .start = glob_start, .end = source.len });
    return .{ .segments = try output.toOwnedSlice(allocator) };
}
