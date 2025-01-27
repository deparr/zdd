const std = @import("std");
const Args = @import("Args.zig");


// todo just copy the io for now,
// figuring out a good way to do it is future me's problem

pub fn patch(opts: Args) !void {
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

    _ = infile;
    _ = outfile;

    if (infile_handle) |f|
        f.close();

    if (outfile_handle) |f|
        f.close();
}
