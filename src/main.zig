const std = @import("std");

const cfg = @import("./config.zig");
const age = @import("./age.zig");
const zpass = @import("./zpass.zig");
const cli = @import("./cli.zig");

pub var db: zpass.DataBase = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const home = std.posix.getenv("HOME").?;
    const confFile = try std.mem.concat(allocator, u8, &.{ home, "/.config/zpass/zpass.cfg" });
    const confDir = try std.mem.concat(allocator, u8, &.{ home, "/.config/zpass/" });
    var config: cfg.Config = undefined;

    std.fs.makeDirAbsolute(confDir) catch {};
    try config.init(confFile, allocator);

    std.fs.makeDirAbsolute(config.root) catch {};

    db.init(config, allocator);

    // try db.readAccountFromFile("./test.age");

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    const repl = cli.Repl{
        .allocator = allocator,
        .stdin = stdin,
        .stdout = stdout,
    };

    try repl.startRepl();

    try db.writeDBToFile();
}
