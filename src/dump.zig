const std = @import("std");
const Args = @import("Args.zig");

pub fn dump(opts: Args) !void {
    // TODO better io
    //  move this out of dump()
    //  assumes relative path
    //  needs to be seekable

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

    const target_len = opts.length orelse 0;
    var offset = opts.offset;
    var written: usize = 0;
    var done = false;

    try writeHeader(opts, outfile);
    try bw.flush();

    while (infile.read(buf)) |nread| {
        if (nread == 0 or done)
            break;

        var nbytes_to_dump = nread;

        if (target_len > 0 and written + nread >= target_len) {
            nbytes_to_dump = target_len - written;
            done = true;
        }

        switch (opts.offset_fmt) {
            .hex => try writeHexOffset(&offset, outfile),
            .dec => try writeDecOffset(offset, outfile),
            .none => {},
        }

        try writeBytes(opts, buf[0..nbytes_to_dump], outfile);
        try writeChars(opts, buf[0..nbytes_to_dump], outfile);

        try bw.flush();

        offset += @intCast(nread);
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

inline fn writeDecOffset(offset: isize, writer: anytype) !void {
    var off = @abs(offset);
    var digits: [18]u8 = undefined;
    digits[16] = ':';
    digits[17] = ' ';
    var i: usize = 15;
    while (off > 0) : (off /= 10) {
        digits[i] = '0' + @as(u8, @intCast(off % 10));
        if (i == 0)
            return error.DecimalOffsetTooLarge;
        i -= 1;
    }
    const target: usize = if (offset < 0) 9 else 8;
    while (i >= target) : (i -= 1) {
        digits[i] = '0';
    }

    if (offset < 0) {
        digits[i] = '-';
    } else i += 1;

    _ = try writer.write(digits[i..]);
}

inline fn writeHexOffset(offset: *isize, writer: anytype) !void {
    const bytes = std.mem.asBytes(offset);
    // todo dont think this matches xxd
    var i: usize = if (bytes[4] > 0) 1 else 5;
    while (i <= bytes.len) : (i += 1) {
        try writer.print("{x:02}", .{bytes[bytes.len - i]});
    }
    _ = try writer.write(": ");
}

fn writeHeader(opts: Args, writer: anytype) !void {
    if (opts.command != .include or opts.name == null)
        return;

    const name = opts.name.?;

    switch (opts.language) {
        .c => {
            if (opts.const_decl)
                _ = try writer.write("const ");

            try writer.print("unsigned char {s}[] = {{\n", .{name});
        },
        .zig => {
            if (opts.const_decl)
                _ = try writer.write("const")
            else
                _ = try writer.write("var");

            try writer.print(" {s}: []const u8 = .{{\n", .{name});
        },
    }
}

fn writeFooter(opts: Args, len: usize, writer: anytype) !void {
    if (opts.command != .include or opts.name == null)
        return;

    const name = opts.name.?;
    _ = try writer.write("};\n");

    switch (opts.language) {
        .c => {
            if (opts.const_decl)
                _ = try writer.write("const ");

            try writer.print("unsigned int {s}_len = {d};\n", .{ name, len });
        },
        else => {},
    }
}

fn writeBytes(opts: Args, bytes: []u8, writer: anytype) !void {
    switch (opts.command) {
        .grouped => try groupedWriteBytes(opts, bytes, writer),
        .include => try includeWriteBytes(opts, bytes, writer),
        .plain => try plainWriteBytes(opts, bytes, writer),
        .words => try wordWriteBytes(opts, bytes, writer),
        else => unreachable,
    }
}

fn groupedWriteBytes(opts: Args, bytes: []u8, writer: anytype) !void {
    const groupsize = opts.groupsize;
    const chars_per_octet: usize = if (opts.format == .bin) 8 else 2;
    var target_size =
        if (groupsize > 0)
        opts.columns * chars_per_octet + (opts.columns / groupsize) + 1
    else
        opts.columns * chars_per_octet;
    if (opts.columns % groupsize != 0)
        target_size += 1;
    var written: usize = 0;

    for (bytes, 1..) |byte, i| {
        switch (opts.format) {
            .hex_upper => try writer.print("{X:02}", .{byte}),
            .hex => try writer.print("{x:02}", .{byte}),
            .bin => try writer.print("{b:08}", .{byte}),
        }

        written += chars_per_octet;
        if (groupsize > 0 and i % groupsize == 0) {
            try writer.writeByte(' ');
            written += 1;
        }
    }

    try writer.writeByteNTimes(' ', target_size - written);
}

fn includeWriteBytes(opts: Args, bytes: []u8, writer: anytype) !void {
    _ = try writer.write("  ");
    for (bytes, 1..) |byte, i| {
        switch (opts.format) {
            .hex_upper => try writer.print("0x{X:02},", .{byte}),
            else => try writer.print("0x{x:02},", .{byte}),
        }
        if (i != bytes.len)
            try writer.writeByte(' ');
    }
    try writer.writeByte('\n');
}

fn plainWriteBytes(opts: Args, bytes: []u8, writer: anytype) !void {
    for (bytes) |byte| {
        switch (opts.format) {
            .hex_upper => try writer.print("{X:02}", .{byte}),
            else => try writer.print("{x:02}", .{byte}),
        }
    }
    try writer.writeByte('\n');
}

fn wordWriteBytes(opts: Args, bytes: []u8, writer: anytype) !void {
    const groupsize = opts.groupsize;
    const chars_per_octet: usize = if (opts.format == .bin) 8 else 2;
    const partial_word: usize = if (opts.columns % groupsize > 0) 1 else 0;
    const words = opts.columns / groupsize + partial_word;
    const target_size = words * groupsize * chars_per_octet + 2 + words - 1;
    var written: usize = 0;

    var i: usize = 0;
    while (i < bytes.len) : (i += groupsize) {
        const word = bytes[i..@min(bytes.len, i + groupsize)];
        const missing_len = (groupsize - word.len) * chars_per_octet;
        try writer.writeByteNTimes(' ', missing_len);
        written += missing_len;
        for (1..word.len + 1) |j| {
            const byte = word[word.len - j];
            switch (opts.format) {
                .hex_upper => try writer.print("{X:02}", .{byte}),
                .hex => try writer.print("{x:02}", .{byte}),
                .bin => try writer.print("{b:08}", .{byte}),
            }
        }

        written += word.len * chars_per_octet;
        try writer.writeByte(' ');
        written += 1;
    }

    try writer.writeByteNTimes(' ', target_size - written);
}

fn writeChars(opts: Args, bytes: []u8, writer: anytype) !void {
    switch (opts.command) {
        .include, .plain, .patch => return,
        else => {},
    }

    for (bytes) |byte| {
        var to_print: u8 = '.';
        switch (byte) {
            ' '...'~' => to_print = byte,
            else => {},
        }
        try writer.writeByte(to_print);
    }
    try writer.writeByte('\n');
}
