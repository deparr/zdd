const std = @import("std");
const Args = @import("Args.zig");

pub fn dump(opts: Args) !void {
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

    // todo read in a multiple of column size at a time
    const buf: []u8 = try opts.alloc.alloc(u8, opts.columns);
    defer opts.alloc.free(buf);
    var offset = opts.offset;
    var written: usize = 0;

    try writeHeader(opts, outfile);
    try bw.flush();

    while (infile.read(buf)) |nread| {
        if (nread == 0) {
            break;
        }
        switch (opts.offset_fmt) {
            .hex => try outfile.print("{x:08}: ", .{offset}),
            .dec => try outfile.print("{d:08}: ", .{offset}),
            .none => {},
        }

        try writeBytes(opts, buf, nread, outfile);
        try writeChars(opts, buf, nread, outfile);

        try bw.flush();

        offset += nread;
        written += nread;
    } else |err| {
        opts.alloc.free(buf);
        return err;
    }

    try writeFooter(opts, written, outfile);
    try bw.flush();

    if (infile_handle) |f|
        f.close();

    if (outfile_handle) |f|
        f.close();
}

fn writeHeader(opts: Args, writer: anytype) !void {
    if (opts.format != .include)
        return;

    if (opts.name) |name|
        try writer.print("unsigned char {s}[] = {{\n", .{name});
}

fn writeFooter(opts: Args, len: usize, writer: anytype) !void {
    if (opts.format != .include)
        return;

    if (opts.name) |name|
        try writer.print("\n}};\nunsigned int {s}_len = {d};\n", .{ name, len });
}

fn writeBytes(opts: Args, bytes: []u8, len_bytes: usize, writer: anytype) !void {
    switch (opts.format) {
        .hex, .bin => try groupedWriteBytes(opts, bytes, len_bytes, writer),
        .include => try includeWriteBytes(opts, bytes, len_bytes, writer),
        .words => unreachable,
        .plain => unreachable,
        else => unreachable,
    }
}

fn groupedWriteBytes(opts: Args, bytes: []u8, len_bytes: usize, writer: anytype) !void {
    const groupsize = opts.groupsize;
    const chars_per_octet: usize = if (opts.format == .hex) 2 else 8;
    const target_size = if (groupsize > 0) opts.columns * chars_per_octet + (opts.columns / groupsize) - 1 + 2 else opts.columns * chars_per_octet;
    var written: usize = 0;

    for (0..len_bytes) |i| {
        if (opts.format == .hex) {
            try writer.print("{x:02}", .{bytes[i]});
        } else {
            try writer.print("{b:08}", .{bytes[i]});
        }
        written += chars_per_octet;
        if (groupsize > 0 and (i + 1) % groupsize == 0) {
            try writer.writeByte(' ');
            written += 1;
        }
    }

    try writer.writeByteNTimes(' ', target_size - written);
}

fn includeWriteBytes(opts: Args, bytes: []u8, len_bytes: usize, writer: anytype) !void {
    _ = opts;

    _ = try writer.write("  ");
    for (0..len_bytes) |i| {
        try writer.print("0x{x:02},", .{bytes[i]});
        if (i != len_bytes-1) {
            try writer.writeByte(' ');
        }
    }
    try writer.writeByte('\n');
}

fn writeChars(opts: Args, bytes: []u8, len_bytes: usize, writer: anytype) !void {
    switch (opts.format) {
        .include, .plain, .reverse => return,
        else => {},
    }

    for (0..len_bytes) |i| {
        var to_print: u8 = '.';
        switch(bytes[i]) {
            ' '...'~' => to_print = bytes[i],
            else => {},
        }
        try writer.writeByte(to_print);
    }
    try writer.writeByte('\n');
}
