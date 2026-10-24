const std = @import("std");

pub fn closingDelimiter(open: u8) ?u8 {
    return switch (open) {
        '[' => ']',
        '{' => '}',
        '(' => ')',
        '<' => '>',
        else => null,
    };
}

fn atomKind(char: u8) ?usize {
    return switch (char) {
        ':' => 0,
        '.' => 1,
        '=' => 2,
        else => null,
    };
}

/// Index class terminators once so many unmatched '[' bytes cannot cause
/// repeated suffix scans. Complexity: O(n) time and auxiliary storage.
pub const Classes = struct {
    source: []const u8,
    next: []usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) !Classes {
        const next = try allocator.alloc(usize, source.len + 1);
        next[source.len] = source.len;
        var atoms: [3]usize = @splat(source.len);
        var i = source.len;
        while (i > 0) {
            i -= 1;
            if (source[i] == '/') atoms = @splat(source.len);
            if (i + 1 < source.len and source[i + 1] == ']') {
                if (atomKind(source[i])) |kind| atoms[kind] = i;
            }
            next[i] = switch (source[i]) {
                ']' => i,
                '/' => source.len,
                '\\' => if (i + 1 < source.len and source[i + 1] != '/') next[i + 2] else source.len,
                else => next[i + 1],
            };
            if (source[i] == '[' and i + 1 < source.len) {
                if (atomKind(source[i + 1])) |kind| {
                    if (atoms[kind] < source.len) next[i] = next[atoms[kind] + 2];
                }
            }
        }
        return .{ .source = source, .next = next, .allocator = allocator };
    }

    pub fn deinit(self: Classes) void {
        self.allocator.free(self.next);
    }

    /// Return the exclusive end of a glob class, or null for a literal '['.
    pub fn end(self: Classes, start: usize) ?usize {
        var at = start + 1;
        if (at < self.source.len and (self.source[at] == '!' or self.source[at] == '^')) at += 1;
        if (at < self.source.len and self.source[at] == ']') at += 1;
        const close = self.next[at];
        return if (close < self.source.len) close + 1 else null;
    }
};
