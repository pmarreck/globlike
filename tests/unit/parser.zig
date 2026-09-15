const std = @import("std");
const g = @import("globlike");
const t = std.testing;

const Expected = struct { kind: g.Kind, text: []const u8 };

fn segments(source: []const u8, expected: []const Expected) !void {
    const result = try g.parse(t.allocator, source);
    defer result.deinit(t.allocator);
    try t.expect(result == .segments);
    try t.expectEqual(expected.len, result.segments.len);
    for (expected, result.segments) |want, got| {
        try t.expectEqual(want.kind, got.kind);
        try t.expectEqualStrings(want.text, source[got.start..got.end]);
    }
}

test "empty input and ordinary glob text" {
    try segments("", &.{});
    try segments("a/*/b?/**", &.{.{ .kind = .glob, .text = "a/*/b?/**" }});
}

test "two excerpts retain intervening glob text and regex escapes" {
    try segments("/[Users|home]/[\\p{L}+]/**", &.{
        .{ .kind = .glob, .text = "/" },
        .{ .kind = .regex, .text = "Users|home" },
        .{ .kind = .glob, .text = "/" },
        .{ .kind = .regex, .text = "\\p{L}+" },
        .{ .kind = .glob, .text = "/**" },
    });
}

test "nested class brackets stay inside the excerpt" {
    try segments("[[a-z][0-9]+]", &.{.{ .kind = .regex, .text = "[a-z][0-9]+" }});
    try segments("[[[:alpha:]]+]", &.{.{ .kind = .regex, .text = "[[:alpha:]]+" }});
}

test "literal brackets inside excerpts use balanced escaped spellings" {
    try segments("[[\\[]]", &.{.{ .kind = .regex, .text = "[\\[]" }});
    try segments("[[\\]]]", &.{.{ .kind = .regex, .text = "[\\]]" }});
    const cases = [_][]const u8{ "[[[]]", "[[]]]" };
    for (cases) |source| {
        const result = try g.parse(t.allocator, source);
        defer result.deinit(t.allocator);
        try t.expect(result == .diagnostic);
    }
}

test "literal glob brackets and escaped regex brackets remain distinct" {
    try segments("file\\[draft\\].txt", &.{.{ .kind = .glob, .text = "file\\[draft\\].txt" }});
    try segments("[ \\]]", &.{.{ .kind = .regex, .text = " \\]" }});
    try segments("[ ]\\]", &.{
        .{ .kind = .regex, .text = " " },
        .{ .kind = .glob, .text = "\\]" },
    });
}

test "escaped backslashes do not swallow following delimiters" {
    try segments("\\\\[a]", &.{
        .{ .kind = .glob, .text = "\\\\" },
        .{ .kind = .regex, .text = "a" },
    });
    try segments("[\\\\]", &.{.{ .kind = .regex, .text = "\\\\" }});
    try segments("\\\\\\[", &.{.{ .kind = .glob, .text = "\\\\\\[" }});
}

test "adjacent and empty excerpts have separate boundaries" {
    try segments("[a][][b]", &.{
        .{ .kind = .regex, .text = "a" },
        .{ .kind = .regex, .text = "" },
        .{ .kind = .regex, .text = "b" },
    });
}

test "malformed delimiters report byte offsets without partial success" {
    const Case = struct { source: []const u8, expected: g.Diagnostic };
    const cases = [_]Case{
        .{ .source = "[ ]]", .expected = .{ .kind = .unexpected_close, .offset = 3 } },
        .{ .source = "a]", .expected = .{ .kind = .unexpected_close, .offset = 1 } },
        .{ .source = "a[bc", .expected = .{ .kind = .unclosed_excerpt, .offset = 1 } },
        .{ .source = "abc\\", .expected = .{ .kind = .dangling_escape, .offset = 3 } },
        .{ .source = "[a\\", .expected = .{ .kind = .dangling_escape, .offset = 2 } },
        .{ .source = "é]", .expected = .{ .kind = .unexpected_close, .offset = 2 } },
    };
    for (cases) |case| {
        const result = try g.parse(t.allocator, case.source);
        defer result.deinit(t.allocator);
        try t.expect(result == .diagnostic);
        try t.expectEqualDeep(case.expected, result.diagnostic);
    }
}

fn allocationCase(allocator: std.mem.Allocator, source: []const u8) !void {
    const result = try g.parse(allocator, source);
    defer result.deinit(allocator);
}

test "every allocation failure releases the stack and partial segments" {
    try t.checkAllAllocationFailures(t.allocator, allocationCase, .{"a[[b]]/[c]d[e]f[g]h[i]j"});
    try t.checkAllAllocationFailures(t.allocator, allocationCase, .{"a[[b]]/[c]d]"});
    try t.checkAllAllocationFailures(t.allocator, allocationCase, .{"a[[b]]/[c"});
    try t.checkAllAllocationFailures(t.allocator, allocationCase, .{"a[[b]]/[c\\"});
}

test "deep nesting uses heap storage without recursive calls" {
    const depth = 10000;
    const source = try t.allocator.alloc(u8, depth * 2 + 1);
    defer t.allocator.free(source);
    @memset(source[0..depth], '[');
    source[depth] = 'a';
    @memset(source[depth + 1 ..], ']');
    const result = try g.parse(t.allocator, source);
    defer result.deinit(t.allocator);
    try t.expect(result == .segments);
    try t.expectEqual(@as(usize, 1), result.segments.len);
    try t.expectEqualDeep(g.Segment{ .kind = .regex, .start = 1, .end = source.len - 1 }, result.segments[0]);
}

test "Unicode bytes and every source span survive parsing" {
    const inputs = [_][]const u8{
        "", "é/[\\p{L}+]/日本語", "[a][][b]", "file\\[draft\\].txt",
        "[ \\]]", "[ ]\\]", "[[[:alpha:]]+]", "a/*/b?/**",
    };
    for (inputs) |source| {
        const result = try g.parse(t.allocator, source);
        defer result.deinit(t.allocator);
        try t.expect(result == .segments);
        var reconstructed: std.ArrayList(u8) = .empty;
        defer reconstructed.deinit(t.allocator);
        for (result.segments) |segment| {
            if (segment.kind == .regex) try reconstructed.append(t.allocator, '[');
            try reconstructed.appendSlice(t.allocator, source[segment.start..segment.end]);
            if (segment.kind == .regex) try reconstructed.append(t.allocator, ']');
        }
        try t.expectEqualStrings(source, reconstructed.items);
    }
}
