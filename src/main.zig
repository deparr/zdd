const std = @import("std");
const Allocator = std.mem.Allocator;
const Args = @import("Args.zig");
const dump = @import("dump.zig");
const patch = @import("patch.zig");

// todo use arena allocator
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    var args = Args.parse(alloc) catch |e| {
        switch (e) {
            Args.ParseError.TooManyColumns => std.log.err("invalid number of columns. max. 256 or unbounded with -ps", .{}),
            Args.ParseError.InvalidWordGroupSize => std.log.err("octets per group must be a power of 2 with -e", .{}),
            Args.ParseError.OutOfMemory => std.log.err("out of memory", .{}),
            Args.ParseError.InvalidPatchFormat => std.log.err("cannot revert this type of dump", .{}),
        }
        std.process.exit(1);
    };
    defer args.deinit();

    switch (args.command) {
        .patch => try patch.patch(args),
        else => try dump.dump(args),
    }
}
