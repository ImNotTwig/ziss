const std = @import("std");

const age = @import("./age.zig");
const cfg = @import("./config.zig");

pub const DIGEST_SIZE = 64;
//TODO:
// * add commands from npg

pub fn hash(s: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var h: [DIGEST_SIZE]u8 = undefined;
    const blake = std.crypto.hash.blake2.Blake2b512;
    blake.hash(s, &h, .{});
    const e = std.base64.Base64Encoder.init(std.base64.url_safe_alphabet_chars, null);
    var buf: [256]u8 = undefined;
    return try allocator.dupe(u8, e.encode(&buf, &h));
}

pub const Account = struct {
    data: std.StringHashMap([]const u8),
};

pub const DataBase = struct {
    accounts: std.ArrayList(Account),
    allocator: std.mem.Allocator,
    config: cfg.Config,

    pub fn init(self: *@This(), config: cfg.Config, allocator: std.mem.Allocator) !void {
        self.config = config;
        self.allocator = allocator;
        self.accounts = std.ArrayList(Account).init(allocator);

        // Add all files names in the src folder to `files`
        var dir = try std.fs.cwd().openDir(config.root, .{ .iterate = true });
        var iter = dir.iterate();
        while (try iter.next()) |file| {
            if (file.kind != .file) {
                continue;
            }
            try self.readAccountFromFile(try std.mem.concat(allocator, u8, &.{ config.root, "/", file.name }));
        }
    }

    pub fn parseAndAddAccount(self: *@This(), accString: []const u8) !void {
        var account = Account{ .data = std.StringHashMap([]const u8).init(self.allocator) };
        var lineIter = std.mem.splitSequence(u8, accString, "\n");
        while (lineIter.next()) |line| {
            var keyIter = std.mem.splitSequence(u8, line, "=");
            const first = keyIter.first();
            while (keyIter.next()) |kv| {
                try account.data.put(try self.allocator.dupe(u8, first), try self.allocator.dupe(u8, kv));
            }
        }
        try self.accounts.append(account);
    }

    pub fn readAccountFromFile(self: *@This(), accountFilePath: []const u8) !void {
        const acc = try age.ageDecryptFile(
            self.config.privKeyFilePath,
            accountFilePath,
            self.allocator,
        );

        try self.parseAndAddAccount(acc);
    }

    pub fn rmAccount(self: *@This(), path: []const u8) void {
        for (0.., self.accounts.items) |i, x| {
            if (std.mem.eql(u8, x.data.get("path").?, path)) {
                _ = self.accounts.swapRemove(i);
                return;
            }
        }
    }

    pub fn writeDBToFile(self: @This()) !void {
        for (self.accounts.items) |a| {
            var buf: [1024]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buf);
            var iter = a.data.iterator();

            while (iter.next()) |e| {
                const arr = try std.mem.concat(self.allocator, u8, &.{ e.key_ptr.*, "=", e.value_ptr.*, "\n" });
                _ = try stream.write(arr);
            }
            const accStr = stream.buffer[0..stream.pos];

            const hashOut = try hash(a.data.get("path").?, self.allocator);

            const tmpPath = try std.mem.concat(self.allocator, u8, &.{ "/tmp/zpass/", a.data.get("path").? });
            const path = try std.mem.concat(self.allocator, u8, &.{ self.config.root, "/", hashOut });

            std.fs.makeDirAbsolute("/tmp/zpass/") catch {};
            var file = try std.fs.createFileAbsolute(tmpPath, .{});
            defer {
                file.close();
                std.fs.deleteFileAbsolute(tmpPath) catch {};
            }
            _ = try std.fs.createFileAbsolute(path, .{});
            try file.writeAll(accStr);

            try age.ageEncryptFile(self.config.pubKey, tmpPath, self.allocator, path);
        }
    }
};
