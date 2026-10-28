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

    fn regexAt(segments: []const g.Segment, marker: usize) ?g.Segment {
        const body = marker +| 3;
        var low: usize = 0;
        var high = segments.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (segments[middle].start < body)
                low = middle + 1
            else
                high = middle;
        }
        if (low < segments.len and segments[low].kind == .regex and segments[low].start == body) return segments[low];
        return null;
    }

    fn extglobClose(source: []const u8, start: usize, end: usize, classes: syntax.Classes, segments: []const g.Segment) ?usize {
        var depth: usize = 1;
        var i = start + 2;
        while (i < end) {
            if (regexAt(segments, i)) |segment| {
                i = segment.end + 1;
                continue;
            }
            if (source[i] == '\\') {
                i += 2;
                continue;
            }
            if (source[i] == '[') {
                if (classes.end(i)) |class_end| {
                    i = class_end;
                    continue;
                }
            }
            if (i + 1 < end and std.mem.indexOfScalar(u8, "?*+@!", source[i]) != null and source[i + 1] == '(') {
                depth += 1;
                i += 2;
                continue;
            }
            if (source[i] == ')') {
                depth -= 1;
                if (depth == 0) return i;
            }
            i += 1;
        }
        return null;
    }

    fn componentEnd(source: []const u8, start: usize, end: usize, classes: syntax.Classes, segments: []const g.Segment) usize {
        var i = start;
        while (i < end) {
            if (regexAt(segments, i)) |segment| {
                i = segment.end + 1;
                continue;
            }
            if (source[i] == '\\') {
                i += 2;
                continue;
            }
            if (source[i] == '[') {
                if (classes.end(i)) |class_end| {
                    i = class_end;
                    continue;
                }
            }
            if (source[i] == '/') return i;
            i += 1;
        }
        return end;
    }

    fn globRange(self: *Translation, allocator: std.mem.Allocator, source: []const u8, start: usize, end: usize, classes: syntax.Classes, segments: []const g.Segment, alternatives: bool, depth: usize) !void {
        if (depth > 256) {
            self.diagnostic = .{ .kind = .extglob_nesting_limit, .offset = start };
            return;
        }
        var i = start;
        while (i < end) {
            if (regexAt(segments, i)) |segment| {
                try self.emit(allocator, "(?-i:", segment.start);
                for (source[segment.start..segment.end], segment.start..) |char, offset| try self.emit(allocator, &.{char}, offset);
                try self.emit(allocator, ")", segment.end);
                i = segment.end + 1;
                continue;
            }
            if (i + 1 < end and std.mem.indexOfScalar(u8, "?*+@!", source[i]) != null and source[i + 1] == '(') {
                const close = extglobClose(source, i, end, classes, segments) orelse {
                    self.diagnostic = .{ .kind = .unclosed_extglob, .offset = i };
                    return;
                };
                const operator = source[i];
                if (operator == '!') {
                    const suffix_end = componentEnd(source, close + 1, end, classes, segments);
                    try self.emit(allocator, "(?!(?:", i);
                    try self.globRange(allocator, source, i + 2, close, classes, segments, true, depth + 1);
                    if (self.diagnostic != null) return;
                    try self.emit(allocator, ")", close);
                    try self.globRange(allocator, source, close + 1, suffix_end, classes, segments, false, depth + 1);
                    if (self.diagnostic != null) return;
                    try self.emit(allocator, "(?=/|\\z))[^/]*", i);
                } else {
                    try self.emit(allocator, "(?:", i);
                    try self.globRange(allocator, source, i + 2, close, classes, segments, true, depth + 1);
                    if (self.diagnostic != null) return;
                    const quantifier: []const u8 = switch (operator) {
                        '?' => "?",
                        '*' => "*",
                        '+' => "+",
                        '@' => "",
                        else => unreachable,
                    };
                    try self.emit(allocator, ")", close);
                    try self.emit(allocator, quantifier, i);
                }
                i = close + 1;
                continue;
            }
            switch (source[i]) {
                '|' => if (alternatives) {
                    try self.emit(allocator, "|", i);
                } else try self.literal(allocator, '|', i),
                '[' => {
                    if (classes.end(i)) |class_end| {
                        try self.characterClass(allocator, source, i, class_end);
                        if (self.diagnostic != null) return;
                        i = class_end;
                        continue;
                    }
                    try self.literal(allocator, '[', i);
                },
                '\\' => {
                    i += 1;
                    try self.literal(allocator, source[i], i);
                },
                '*' => {
                    if (i + 1 < end and source[i + 1] == '*') {
                        if (i + 2 < end and source[i + 2] == '/') {
                            try self.emit(allocator, "(?:[^/]+/)*", i);
                            i += 2;
                        } else {
                            try self.emit(allocator, "(?s:.*)", i);
                            i += 1;
                        }
                    } else try self.emit(allocator, "[^/]*", i);
                },
                '?' => try self.emit(allocator, "[^/]", i),
                else => try self.literal(allocator, source[i], i),
            }
            i += 1;
        }
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
    try output.globRange(allocator, source, 0, source.len, classes, parsed.segments, false, 0);
    if (output.diagnostic != null) return output;
    try output.emit(allocator, ")\\z", source.len);
    return output;
}
