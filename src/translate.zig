const std = @import("std");
const g = @import("lib.zig");
const syntax = @import("syntax.zig");

pub const Translation = struct {
    text: std.ArrayList(u8) = .empty,
    positions: std.ArrayList(usize) = .empty,
    diagnostic: ?g.Diagnostic = null,

    pub fn deinit(self: *Translation, allocator: std.mem.Allocator) void {
        self.text.deinit(allocator);
        self.positions.deinit(allocator);
    }

    fn emit(self: *Translation, allocator: std.mem.Allocator, text: []const u8, offset: usize) !void {
        try self.text.appendSlice(allocator, text);
        try self.positions.appendNTimes(allocator, offset, text.len);
    }

    fn literal(self: *Translation, allocator: std.mem.Allocator, char: u8, offset: usize) !void {
        if (std.mem.indexOfScalar(u8, "\\.^$|()[]{}*+?", char) != null) try self.emit(allocator, "\\", offset);
        try self.emit(allocator, &.{char}, offset);
    }

    /// Translate a glob class without turning glob escapes into regex escapes.
    /// The lookahead excludes separators even from negated or named classes.
    fn characterClass(self: *Translation, allocator: std.mem.Allocator, source: []const u8, start: usize, end: usize) !void {
        try self.emit(allocator, "(?=[^/])[", start);
        var i = start + 1;
        var missing_atom_end: [3]bool = @splat(false);
        if (source[i] == '!' or source[i] == '^') {
            try self.emit(allocator, "^", i);
            i += 1;
        }
        while (i < end - 1) : (i += 1) {
            if (source[i] == '[' and i + 1 < end - 1 and std.mem.indexOfScalar(u8, ":.=", source[i + 1]) != null) {
                const marker = source[i + 1];
                const kind: usize = switch (marker) {
                    ':' => 0,
                    '.' => 1,
                    else => 2,
                };
                var at = if (missing_atom_end[kind]) end else i + 2;
                while (at + 1 < end - 1 and !(source[at] == marker and source[at + 1] == ']')) : (at += 1) {}
                if (at + 1 < end - 1) {
                    if (marker != ':') {
                        self.diagnostic = .{ .kind = .unsupported_glob_class, .offset = i };
                        return;
                    }
                    for (source[i .. at + 2], i..) |char, offset| try self.emit(allocator, &.{char}, offset);
                    i = at + 1;
                    continue;
                }
                missing_atom_end[kind] = true;
            }
            if (source[i] == '\\') {
                i += 1;
                // Keep glob escapes literal, including punctuation that could
                // make the whole regex class look like a misplaced POSIX atom.
                if (std.mem.indexOfScalar(u8, "\\[]^-:.=", source[i]) != null) try self.emit(allocator, "\\", i);
            } else if (std.mem.indexOfScalar(u8, "[]^:.=", source[i]) != null) {
                try self.emit(allocator, "\\", i);
            }
            try self.emit(allocator, source[i .. i + 1], i);
        }
        try self.emit(allocator, "]", end - 1);
    }
};

pub fn translate(allocator: std.mem.Allocator, source: []const u8, raw_regex: bool) !Translation {
    var output: Translation = .{};
    errdefer output.deinit(allocator);
    if (raw_regex) {
        for (source, 0..) |char, i| try output.emit(allocator, &.{char}, i);
        return output;
    }
    const parsed = try g.parse(allocator, source);
    defer parsed.deinit(allocator);
    if (parsed == .diagnostic) return .{ .diagnostic = parsed.diagnostic };
    const classes = try syntax.Classes.init(allocator, source);
    defer classes.deinit();
    try output.emit(allocator, "\\A(?:", 0);
    for (parsed.segments) |segment| {
        if (segment.kind == .regex) {
            try output.emit(allocator, "(?-i:", segment.start);
            for (source[segment.start..segment.end], segment.start..) |char, i| try output.emit(allocator, &.{char}, i);
            try output.emit(allocator, ")", segment.end);
            continue;
        }
        var i = segment.start;
        while (i < segment.end) {
            switch (source[i]) {
                '[' => {
                    if (classes.end(i)) |end| {
                        try output.characterClass(allocator, source, i, end);
                        if (output.diagnostic != null) return output;
                        i = end;
                        continue;
                    }
                    try output.literal(allocator, '[', i);
                },
                '\\' => {
                    i += 1;
                    try output.literal(allocator, source[i], i);
                },
                '*' => {
                    if (i + 1 < segment.end and source[i + 1] == '*') {
                        if (i + 2 < segment.end and source[i + 2] == '/') {
                            try output.emit(allocator, "(?:[^/]+/)*", i);
                            i += 2;
                        } else {
                            try output.emit(allocator, "(?s:.*)", i);
                            i += 1;
                        }
                    } else try output.emit(allocator, "[^/]*", i);
                },
                '?' => try output.emit(allocator, "[^/]", i),
                else => try output.literal(allocator, source[i], i),
            }
            i += 1;
        }
    }
    try output.emit(allocator, ")\\z", source.len);
    return output;
}
