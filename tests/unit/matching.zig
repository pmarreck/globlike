const std = @import("std");
const g = @import("globlike");
const t = std.testing;

fn classify(source: []const u8, options: g.Options, candidates: []const []const u8, expected: []const bool) !void {
    var compiled = try g.compile(t.allocator, source, options);
    try t.expect(compiled == .pattern);
    defer compiled.pattern.deinit();
    try t.expectEqual(candidates.len, expected.len);
    for (candidates, expected) |candidate, want| {
        const result = compiled.pattern.matches(candidate);
        try t.expect(result == .matched);
        try t.expectEqual(want, result.matched);
    }
}

test "glob operators classify complete candidate sets with directory boundaries" {
    const paths = &.{ "foo", "barfoo", "a/foo", "a/b/foo", "foo\n", "a\\foo", "a/food", "a\n/foo" };
    try classify("**/foo", .{}, paths, &.{ true, false, true, true, false, false, false, true });
    try classify("*", .{}, paths, &.{ true, true, false, false, true, true, false, false });
    try classify("**", .{}, paths, &.{ true, true, true, true, true, true, true, true });
    try classify("?", .{}, &.{ "a", "é", "日", "/", "ab", "", "\n", "\\" }, &.{ true, true, true, false, false, false, true, true });
}

test "literal punctuation and escaped brackets cannot inject regex operators" {
    try classify("a+(b|c){2}.txt", .{}, &.{ "a+(b|c){2}.txt", "abb.txt", "acc.txt", "a+(b|c){2}Xtxt" }, &.{ true, false, false, false });
    try classify("file\\[draft\\]\\*.txt", .{}, &.{ "file[draft]*.txt", "filed*.txt", "file[draft]a.txt", "file[draft]*.txt\n" }, &.{ true, false, false, false });
}

test "inline regex fragments preserve grouping and independent case scope" {
    try classify("%r[Users|home]/%r{\\p{L}+}/**", .{}, &.{ "Users/Alex/a", "home/Élodie/b/c", "home/123/a", "Users/AlexX", "HOME/Alex/a" }, &.{ true, true, false, false, false });
    try classify("A%r[bc]D", .{ .case_insensitive = true }, &.{ "AbcD", "abcd", "ABCD", "AbD", "AcD", "xbcdy" }, &.{ true, true, false, false, false, false });
    try classify("A%r[(?i)bc]D", .{}, &.{ "AbcD", "ABCD", "abcd", "Abcd" }, &.{ true, true, false, false });
    try classify("%r[[a-z]]", .{}, &.{ "a", "z", "A", "ab", "[a-z]" }, &.{ true, true, false, false, false });
    try classify("A[b-c]D", .{ .case_insensitive = true }, &.{ "AbD", "AcD", "abd", "ACD", "AbcD" }, &.{ true, true, true, true, false });
}

test "explicit modes preserve regex syntax and case overrides" {
    try classify("glob:regex:*", .{}, &.{ "regex:a", "regex:", "a", "glob:regex:a" }, &.{ true, true, false, false });
    try classify("regex:(?-i)abc", .{ .case_insensitive = true }, &.{ "abc", "ABC", "xabcx", "ab" }, &.{ true, false, true, false });
    try classify("regex:[]]", .{}, &.{ "]", "a]b", "[", "abc" }, &.{ true, true, false, false });
    try classify("R:/foo/*", .{}, &.{ "R:/foo/a", "R:/foo/a/b", "r:/foo/a" }, &.{ true, false, false });
}

test "slash-delimited regex flags override default case and reject unknown flags" {
    try classify("regex:/abc/i", .{}, &.{ "abc", "ABC", "xAbCx", "ab" }, &.{ true, true, true, false });
    try classify("regex:/a.b/s", .{}, &.{ "a\nb", "acb", "ab", "a/b" }, &.{ true, true, false, true });
    try classify("regex:/home\\/file/i", .{}, &.{ "home/file", "HOME/FILE", "homeXfile", "file" }, &.{ true, true, false, false });
    var invalid = try g.compile(t.allocator, "regex:/abc/q", .{});
    defer if (invalid == .pattern) invalid.pattern.deinit();
    try t.expect(invalid == .diagnostic);
}

test "regex compile errors preserve source offset, category, code and wording" {
    const result = try g.compile(t.allocator, "regex:(", .{});
    try t.expect(result == .diagnostic);
    try t.expectEqual(.regex_syntax, result.diagnostic.kind);
    try t.expectEqual(@as(?usize, 7), result.diagnostic.offset);
    try t.expect(result.diagnostic.engine_code > 0);
    var buffer: [256]u8 = undefined;
    try t.expect(std.mem.indexOf(u8, result.diagnostic.message(&buffer), "missing closing parenthesis") != null);
    const delimiter = try g.compile(t.allocator, "glob:a%r[", .{});
    try t.expect(delimiter == .diagnostic);
    try t.expectEqual(.unclosed_excerpt, delimiter.diagnostic.kind);
    try t.expectEqual(@as(?usize, 6), delimiter.diagnostic.offset);
}

test "DFA incompatibility is rejected before any subjects are matched" {
    for ([_][]const u8{ "regex:hidden/(a)\\1", "regex:(?R)", "regex:(?<=a{1,3})b", "%r[hidden/(a)\\1]" }) |source| {
        const result = try g.compile(t.allocator, source, .{});
        try t.expect(result == .diagnostic);
        try t.expectEqual(.dfa_unsupported, result.diagnostic.kind);
        try t.expect(result.diagnostic.engine_code < 0);
    }
}

test "invalid subject is an error with its native code, never a nonmatch" {
    var compiled = try g.compile(t.allocator, "*", .{});
    try t.expect(compiled == .pattern);
    defer compiled.pattern.deinit();
    const result = compiled.pattern.matches("\xff");
    try t.expect(result == .diagnostic);
    try t.expectEqual(.invalid_subject, result.diagnostic.kind);
    try t.expect(result.diagnostic.engine_code < 0);
    var buffer: [256]u8 = undefined;
    try t.expect(std.mem.indexOf(u8, result.diagnostic.message(&buffer), "UTF-8") != null);
}

test "bounded match resources produce typed diagnostics" {
    var compiled = try g.compile(t.allocator, "regex:(?:a|aa|aaa|aaaa|aaaaa)*z", .{ .workspace_limit = 20 });
    try t.expect(compiled == .pattern);
    defer compiled.pattern.deinit();
    const result = compiled.pattern.matches("aaaaaaaaaaaaaaaaaaaaz");
    try t.expect(result == .diagnostic);
    try t.expectEqual(.workspace_limit, result.diagnostic.kind);
    try t.expect(result.diagnostic.engine_code < 0);
}

test "inline regex must be valid independently and cannot escape its scope" {
    for ([_][]const u8{ "%r[a)|(?:b]", "prefix%r[)|(?i:.*]suffix" }) |source| {
        var result = try g.compile(t.allocator, source, .{});
        defer if (result == .pattern) result.pattern.deinit();
        try t.expect(result == .diagnostic);
        try t.expectEqual(.regex_syntax, result.diagnostic.kind);
    }
}

fn allocationCase(allocator: std.mem.Allocator, source: []const u8) !void {
    var result = try g.compile(allocator, source, .{});
    defer if (result == .pattern) result.pattern.deinit();
}

test "compilation releases owned buffers on every Zig allocation failure" {
    try t.checkAllAllocationFailures(t.allocator, allocationCase, .{"a%r{\\p{L}+}/[a-c]/**/b?"});
    try t.checkAllAllocationFailures(t.allocator, allocationCase, .{"regex:("});
    try t.checkAllAllocationFailures(t.allocator, allocationCase, .{"%r[(a)\\1]"});
    try t.checkAllAllocationFailures(t.allocator, allocationCase, .{"[[:digit:]"});
}

test "pattern sets agree with individual classifiers and preserve error context" {
    var set = g.PatternSet.init(t.allocator);
    defer set.deinit();
    try t.expectEqual(@as(?g.Diagnostic, null), try set.add("**/*.txt", .{}));
    try t.expectEqual(@as(?g.Diagnostic, null), try set.add("regex:/^HELLO$/i", .{}));
    const candidates = [_][]const u8{ "a.txt", "a/b.txt", "hello", "HELLO", "hello.doc", "a.txt\n", "other" };
    const expected = [_]bool{ true, true, true, true, false, false, false };
    for (candidates, expected) |path, want| {
        const result = set.matchesAny(path, null);
        try t.expect(result == .matched);
        try t.expectEqual(want, result.matched);
    }
    try t.expectEqual(@as(?g.Diagnostic, null), try set.add("new?.log", .{}));
    try t.expect(set.matchesAny("dir/new1.log", "new1.log").matched);
    const before = set.patterns.items.len;
    try t.expect((try set.add("regex:(", .{})) != null);
    try t.expectEqual(before, set.patterns.items.len);
    const failed = set.matchesAny("\xff", null);
    try t.expect(failed == .diagnostic);
    try t.expectEqual(.invalid_subject, failed.diagnostic.detail.kind);
    try t.expectEqual(@as(usize, 0), failed.diagnostic.index);
}

fn setAllocations(allocator: std.mem.Allocator) !void {
    var set = g.PatternSet.init(allocator);
    defer set.deinit();
    _ = try set.add("a*", .{});
    _ = try set.add("%r[b|c]", .{});
    const result = set.matchesAny("b", null);
    if (result == .diagnostic and result.diagnostic.detail.kind == .out_of_memory) return error.OutOfMemory;
    _ = try set.add("d", .{});
}

test "pattern set ownership survives every allocation failure" {
    try t.checkAllAllocationFailures(t.allocator, setAllocations, .{});
}

test "combined matching preserves resource caps and reports the responsible rule" {
    var set = g.PatternSet.init(t.allocator);
    defer set.deinit();
    _ = try set.add("nothing", .{});
    _ = try set.add("regex:(?:a|aa|aaa|aaaa|aaaaa)*z", .{ .workspace_limit = 20 });
    const result = set.matchesAny("aaaaaaaaaaaaaaaaaaaaz", null);
    try t.expect(result == .diagnostic);
    try t.expectEqual(@as(usize, 1), result.diagnostic.index);
    try t.expectEqual(.workspace_limit, result.diagnostic.detail.kind);
}
