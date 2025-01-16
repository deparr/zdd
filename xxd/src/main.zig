const std = @import("std");
const Allocator = std.mem.Allocator;
const Args = @import("Args.zig");

fn dump(opts: Args) !void {
    // todo move this mess somewhere else
    var infile_handle: ?std.fs.File = null;
    var outfile_handle: ?std.fs.File = null;
    var infile_reader = std.io.getStdIn().reader();
    var outfile_writer = std.io.getStdOut().writer();
    if (opts.infile) |path| {
        infile_handle = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        infile_reader = infile_handle.?.reader();
    }   
    var br = std.io.bufferedReader(infile_reader);
    const infile = br.reader();

    if (opts.outfile) |path| {
        outfile_handle = try std.fs.cwd().openFile(path, .{ .mode = .write_only });
        outfile_writer = outfile_handle.?.writer();
    }
    var bw = std.io.bufferedWriter(outfile_writer);
    const outfile = bw.writer();

    // todo I would hope this can be stack allocated, but maybe not,
    var buf: [16]u8 = .{0} ** 16;
    var offset = opts.offset;
    while(true) {
        const nread = try infile.read(&buf);
        if (nread == 0) {
            break;
        }
        try outfile.print("{x:08}: ", .{offset});

        for (buf) |byte| {
            try outfile.print("{x:02}", .{byte});
        }

        _ = try outfile.write(" [chars]\n");

        try bw.flush();

        offset += nread;
    }

    if (infile_handle) |f|
        f.close();

    if (outfile_handle) |f|
        f.close();
}

pub fn main() !void {
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();
    // try stdout.print("Run `zig build test` to run the tests.\n", .{});
    // try bw.flush(); // Don't forget to flush!

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    var args = Args.parse(alloc) catch |e| {
        switch (e) {
            Args.ParseError.TooManyColumns => std.log.err("invalid number of columns. max. 256 or unbounded with -ps", .{}),
            Args.ParseError.InvalidWordGroupSize => std.log.err("octets per group must be a power of 2 with -e", .{}),
            Args.ParseError.OutOfMemory => std.log.err("out of memory", .{}),
        }
        std.process.exit(1);
    };
    defer args.deinit();

    args.dump();
    try dump(args);
}
