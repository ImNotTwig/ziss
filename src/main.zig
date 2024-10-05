const std = @import("std");

const cfg = @import("./config.zig");
const age = @import("./age.zig");
const ziss = @import("./ziss.zig");
const cli = @import("./cli.zig");

pub var db: ziss.DataBase = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    const home = std.posix.getenv("HOME").?; // no password management for homeless people ig
    const confDir = try std.mem.concat(allocator, u8, &.{ home, "/.config/zpass/" });
    const confFile = try std.mem.concat(allocator, u8, &.{ confDir, "zpass.cfg" });
    std.fs.makeDirAbsolute(confDir) catch {};

    var config: cfg.Config = undefined;
    try config.init(confFile, allocator);

    std.fs.makeDirAbsolute(config.root) catch {};

    try db.init(config, allocator);

    var repl = cli.Repl{
        .allocator = allocator,
        .stdin = stdin,
        .stdout = stdout,
    };

    try repl.startRepl();

    try db.writeDBToFile();
}
