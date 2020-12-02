const std = @import("std");
const cpu = std.builtin.cpu;
const os = std.builtin.os;
const Mode = std.builtin.Mode;

pub fn build(b: *std.build.Builder) !void {
    const exe = b.addExecutable("only-sh", "src/main.zig");
    exe.setTarget(b.standardTargetOptions(if (os.tag != .linux) .{} else .{
        .default_target = .{
            .cpu_arch = cpu.arch,
            .os_tag = os.tag,
            .abi = switch (cpu.arch) {
                .aarch64 => .musleabi,
                .arm => .musleabihf,
                else => .musl,
            },
        },
    }));
    exe.setBuildMode(b.standardReleaseOptions());
    exe.setOutputDir("out");
    if (exe.build_mode == Mode.ReleaseSmall or exe.build_mode == Mode.ReleaseFast) exe.strip = true;
    exe.single_threaded = true;
    exe.linkLibC();
    exe.install();
}
