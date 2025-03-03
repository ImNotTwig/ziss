const std = @import("std");

const cfg = @import("./config.zig");
const age = @import("./age.zig");
const ziss = @import("./ziss.zig");
const cli = @import("./cli/cli.zig");
const repl = @import("./cli/repl.zig");

pub var db: ziss.DataBase = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    const confPre = if (std.posix.getenv("XDG_CONFIG_HOME")) |c|
        c
    else
        try std.mem.concat(allocator, u8, &.{ std.posix.getenv("HOME").?, "/.config" });

    const confDir = try std.mem.concat(allocator, u8, &.{ confPre, "/zpass/" });
    const confFile = try std.mem.concat(allocator, u8, &.{ confDir, "zpass.cfg" });
    std.fs.makeDirAbsolute(confDir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {
            std.log.err("error creating «{s}»: {}\n", .{ confDir, err });
            std.process.exit(1);
        },
    };

    var config: cfg.Config = undefined;
    try config.init(confFile, allocator);

    std.fs.makeDirAbsolute(config.root) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {
            std.log.err("error creating «{s}»: {}\n", .{ confDir, err });
            std.process.exit(1);
        },
    };

    try db.init(config, allocator);

    //TODO: Handle commands instead of entering the repl right away

    // this isnt implemented
    try cli.parseCommands(allocator);

    var replHandler = repl.Repl{
        .allocator = allocator,
        .stdin = stdin,
        .stdout = stdout,
    };

    try replHandler.startRepl();

    try db.writeDBToFile();
}
