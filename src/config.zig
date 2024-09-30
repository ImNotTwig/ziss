const std = @import("std");

pub const Config = struct {
    pubKey: []const u8,
    privKeyFilePath: []const u8,
    root: []const u8,

    pub fn init(self: *@This(), configPath: []const u8, allocator: std.mem.Allocator) !void {
        var file = std.fs.openFileAbsolute(configPath, .{}) catch f: {
            _ = try std.fs.createFileAbsolute(configPath, .{});
            break :f try std.fs.openFileAbsolute(configPath, .{});
        };

        defer file.close();

        var buf: [1024]u8 = undefined;
        _ = try file.readAll(&buf);

        var lineIter = std.mem.splitSequence(u8, &buf, "\n");
        while (lineIter.next()) |y| {
            var keyIter = std.mem.splitSequence(u8, y, "=");

            const first = keyIter.first();

            while (keyIter.next()) |x| {
                if (std.mem.eql(u8, first, "pubKey")) {
                    self.pubKey = try allocator.dupe(u8, x);
                } else if (std.mem.eql(u8, first, "privKeyFilePath")) {
                    self.privKeyFilePath = try allocator.dupe(u8, x);
                } else if (std.mem.eql(u8, first, "root")) {
                    self.root = try allocator.dupe(u8, x);
                }
            }
        }
    }
};
