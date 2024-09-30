const std = @import("std");

pub fn ageDecryptFile(keyFile: []const u8, inputFile: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const res = try std.process.Child.run(.{
        .argv = &.{
            "age",
            "-i",
            keyFile,
            "-d",
            inputFile,
        },
        .allocator = allocator,
    });
    return res.stdout;
}

pub fn ageEncryptFile(pubKey: []const u8, inputFile: []const u8, allocator: std.mem.Allocator, outputFile: []const u8) !void {
    _ = try std.process.Child.run(.{
        .argv = &.{
            "age",
            "-e",
            "-r",
            pubKey,
            "-o",
            outputFile,
            inputFile,
        },
        .allocator = allocator,
    });
}
