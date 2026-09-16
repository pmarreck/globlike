const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode (default: ReleaseFast)") orelse .ReleaseFast;
    const lib = b.addModule("globlike", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pcre = b.dependency("pcre2", .{ .target = target, .optimize = optimize, .linkage = .static, .@"code-unit-width" = .@"8" }).artifact("pcre2-8");
    lib.linkLibrary(pcre);
    lib.addIncludePath(pcre.getEmittedIncludeTree());
    lib.link_libc = true;
    b.installArtifact(b.addLibrary(.{ .name = "globlike", .linkage = .static, .root_module = lib }));
    // Expose the transitive archive for consumers that bundle static archives.
    b.installArtifact(pcre);
    b.installFile("LICENSE", "share/licenses/globlike/LICENSE");
    b.installFile("PCRE2-LICENSE.md", "share/licenses/globlike/PCRE2-LICENSE.md");
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/unit/all.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "globlike", .module = lib }},
    }) });
    b.step("test", "Run all tests").dependOn(&b.addRunArtifact(tests).step);
    b.step("check", "Compile all tests without executing them").dependOn(&tests.step);
}
